local ADDON_NAME, ns = ...

local pairs = pairs
local ipairs = ipairs
local type = type
local wipe = wipe
local tostring = tostring
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue

local AuraEvents = {}
ns.AuraEvents = AuraEvents

local subscribers = {
    player = {},
    group  = {},
    roster = {},
    nameplate = {},
    all    = {},
}

local rosterUnits = { player = true }
for i = 1, 4 do rosterUnits["party" .. i] = true end
for i = 1, 40 do rosterUnits["raid" .. i] = true end

local nameplateUnits = {}
for i = 1, 40 do nameplateUnits["nameplate" .. i] = true end

local EnsureNameplateFrames

function AuraEvents:Subscribe(filter, callback)
    local list = subscribers[filter]
    if not list then
        error("AuraEvents:Subscribe invalid filter '" .. tostring(filter) .. "', use 'player', 'group', 'roster', 'nameplate', or 'all'")
    end
    if filter == "nameplate" then
        EnsureNameplateFrames()
    end
    for _, cb in ipairs(list) do
        if cb == callback then return end
    end
    list[#list + 1] = callback
    if self._RecountSubscribers then self:_RecountSubscribers() end
end

function AuraEvents:Unsubscribe(filter, callback)
    local list = subscribers[filter]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
            if self._RecountSubscribers then self:_RecountSubscribers() end
            return
        end
    end
end

local pendingUnits = {}
local pendingAllEligible = {}
local coalesceFrame = CreateFrame("Frame")
coalesceFrame:Hide()

local nAll, nRoster, nPlayer, nGroup, nNameplate = 0, 0, 0, 0, 0
local subAll, subRoster, subPlayer, subGroup, subNameplate =
    subscribers.all, subscribers.roster, subscribers.player, subscribers.group, subscribers.nameplate

local function ProtectedFanout(list, n, unit, info)
    for i = 1, n do
        local ok, err = pcall(list[i], unit, info)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

local function DispatchUnit(unit, info, isRoster, isNameplate, allEligible)
    if not isNameplate or allEligible then
        ProtectedFanout(subAll, nAll, unit, info)
    end

    if isNameplate then
        ProtectedFanout(subNameplate, nNameplate, unit, info)
    elseif isRoster then
        ProtectedFanout(subRoster, nRoster, unit, info)

        if unit == "player" then
            ProtectedFanout(subPlayer, nPlayer, unit, info)
        else
            ProtectedFanout(subGroup, nGroup, unit, info)
        end
    end
end

coalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    for unit, updateInfo in pairs(pendingUnits) do
        local info = updateInfo ~= true and updateInfo or nil

        local ok, err = pcall(DispatchUnit, unit, info, rosterUnits[unit],
            nameplateUnits[unit], pendingAllEligible[unit])
        if not ok then
            geterrorhandler()(err)
        end

        if info and info._isMerged then
            info._isMerged = nil
            wipe(info.addedAuras)
            wipe(info.removedAuraInstanceIDs)
            wipe(info.updatedAuraInstanceIDs)
        end
    end
    wipe(pendingUnits)
    wipe(pendingAllEligible)
end)

local function RecountSubscribers()
    nAll = #subAll
    nRoster = #subRoster
    nPlayer = #subPlayer
    nGroup = #subGroup
    nNameplate = #subNameplate
end
AuraEvents._RecountSubscribers = RecountSubscribers

local mergedInfoPool = {}

local function GetMergedInfo(unit)
    local m = mergedInfoPool[unit]
    if not m then
        m = { addedAuras = {}, removedAuraInstanceIDs = {}, updatedAuraInstanceIDs = {} }
        mergedInfoPool[unit] = m
    end
    return m
end

local function AppendDeltaField(merged, updateInfo, field)
    local src = updateInfo[field]
    if src and not (issecretvalue and issecretvalue(src)) then
        local dst = merged[field]
        for _, v in ipairs(src) do
            dst[#dst + 1] = v
        end
    end
end

local function AccumulateDelta(merged, updateInfo)
    AppendDeltaField(merged, updateInfo, "addedAuras")
    AppendDeltaField(merged, updateInfo, "removedAuraInstanceIDs")
    AppendDeltaField(merged, updateInfo, "updatedAuraInstanceIDs")
end

local function AnyIDElementSecret(arr)
    if not arr then return false end
    for i = 1, #arr do
        if issecretvalue(arr[i]) then return true end -- @secret-policy: report-secret-detected
    end
    return false
end

local function AnyAddedAuraSecret(arr)
    if not arr then return false end
    for i = 1, #arr do
        local data = arr[i]
        if issecretvalue(data) then return true end -- @secret-policy: report-secret-detected
        if data ~= nil
            and (issecretvalue(data.auraInstanceID)
                or issecretvalue(data.spellId)
                or issecretvalue(data.spellID)) then
            return true -- @secret-policy: report-secret-detected
        end
    end
    return false
end

local function PayloadIsSecret(updateInfo)
    if not issecretvalue then return false end
    if issecretvalue(updateInfo) then return true end -- @secret-policy: report-secret-detected
    if not updateInfo then return false end
    if issecretvalue(updateInfo.isFullUpdate)
        or issecretvalue(updateInfo.addedAuras)
        or issecretvalue(updateInfo.updatedAuraInstanceIDs)
        or issecretvalue(updateInfo.removedAuraInstanceIDs) then
        return true -- @secret-policy: report-secret-detected
    end
    return AnyAddedAuraSecret(updateInfo.addedAuras)
        or AnyIDElementSecret(updateInfo.updatedAuraInstanceIDs)
        or AnyIDElementSecret(updateInfo.removedAuraInstanceIDs)
end

local function IsNonRosterEventInteresting(unit)
    if unit == "target" then return true end
    if InCombatLockdown() then return false end
    local tt = _G.GameTooltip
    if not (tt and tt:IsShown()) then return false end
    local _, ttUnit = tt:GetUnit()
    if ttUnit == nil then return false end
    if issecretvalue and issecretvalue(ttUnit) then return false end -- @secret-policy: reject-secret-value (unknown tooltip unit = not interesting)
    return unit == ttUnit
end

local canaccesstable = canaccesstable

local function QueueAuraEvent(unit, updateInfo)
    if canaccesstable and not (issecretvalue and issecretvalue(updateInfo))
        and type(updateInfo) == "table" and not canaccesstable(updateInfo) then
        updateInfo = nil
    end
    local existing = pendingUnits[unit]
    if existing == true then
    elseif issecretvalue and issecretvalue(updateInfo) then
        pendingUnits[unit] = true -- @secret-policy: report-secret-detected (full-update sentinel promotion)
    elseif PayloadIsSecret(updateInfo) then
        pendingUnits[unit] = true
    elseif updateInfo and updateInfo.isFullUpdate then
        pendingUnits[unit] = true
    elseif not updateInfo then
        pendingUnits[unit] = true
    elseif existing then
        local merged = GetMergedInfo(unit)
        if type(existing) == "table" and not existing._isMerged then
            wipe(merged.addedAuras)
            wipe(merged.removedAuraInstanceIDs)
            wipe(merged.updatedAuraInstanceIDs)
            merged._isMerged = true
            AccumulateDelta(merged, existing)
        end
        AccumulateDelta(merged, updateInfo)
        pendingUnits[unit] = merged
    else
        pendingUnits[unit] = updateInfo
    end
    coalesceFrame:Show()
end

local rosterFrames = {}
for unit in pairs(rosterUnits) do
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_AURA", unit)
    f:SetScript("OnEvent", function(_, _, _, updateInfo)
        QueueAuraEvent(unit, updateInfo)
    end)
    rosterFrames[unit] = f
end

local nameplateFrames = nil
EnsureNameplateFrames = function()
    if nameplateFrames then return end
    nameplateFrames = {}
    for unit in pairs(nameplateUnits) do
        local f = CreateFrame("Frame")
        f:RegisterUnitEvent("UNIT_AURA", unit)
        f:SetScript("OnEvent", function(_, _, _, updateInfo)
            QueueAuraEvent(unit, updateInfo)
        end)
        nameplateFrames[unit] = f
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if issecretvalue and issecretvalue(unit) then
        return
    end
    if rosterUnits[unit] then
        return
    end
    if nameplateUnits[unit] then
        if IsNonRosterEventInteresting(unit) then
            pendingAllEligible[unit] = true
            if nameplateFrames then
                coalesceFrame:Show()
            else
                QueueAuraEvent(unit, updateInfo)
            end
        end
        return
    end
    if not IsNonRosterEventInteresting(unit) then
        return
    end
    QueueAuraEvent(unit, updateInfo)
end)

local liftFrame = CreateFrame("Frame")
liftFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
liftFrame:SetScript("OnEvent", function()
    local C_Secrets = _G.C_Secrets
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return
    end
    for unit in pairs(rosterUnits) do
        QueueAuraEvent(unit, nil)
    end
    QueueAuraEvent("target", nil)
end)

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "AuraEvt_mergedInfoPool", tbl = mergedInfoPool }
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AuraDispatch", frame = coalesceFrame, scriptType = "OnUpdate" }
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "AuraRouter", frame = eventFrame }
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end
