--[[
    QUI Group Frames - Pinned Aura Indicators
    Per-spec aura tracking with individually anchored indicators on group frames.
    Each slot has its own anchor position (9-point), display type (icon or square),
    and renders independently on the frame.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = ns.LSM
local QUICore = ns.Addon
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

-- Upvalue hot-path globals
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local wipe = wipe
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local C_UnitAuras = C_UnitAuras
local table_insert = table.insert
local table_remove = table.remove

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFP = {}
ns.QUI_GroupFramePinnedAuras = QUI_GFP

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local INACTIVE_ALPHA = 0.15

-- Default inset per anchor direction
local ANCHOR_INSET = {
    TOPLEFT     = { 1,  -1 },
    TOP         = { 0,  -1 },
    TOPRIGHT    = { -1, -1 },
    LEFT        = { 1,   0 },
    CENTER      = { 0,   0 },
    RIGHT       = { -1,  0 },
    BOTTOMLEFT  = { 1,   1 },
    BOTTOM      = { 0,   1 },
    BOTTOMRIGHT = { -1,  1 },
}

---------------------------------------------------------------------------
-- ICON POOL
---------------------------------------------------------------------------
local iconPool = {}
local POOL_SIZE = 60
local spellNameCache = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_Pin_iconPool", tbl = iconPool }
    mp[#mp + 1] = { name = "GF_Pin_spellNameCache", tbl = spellNameCache }
end

local DEFAULT_SQUARE_COLOR = { 0.5, 0.5, 0.5, 1 }
local DEFAULT_INSET = { 0, 0 }
local AURA_FILTERS = { "HELPFUL", "HARMFUL" }

-- Reusable scratch tables for aura lookups (avoids 2 table allocations
-- per frame per UNIT_AURA event — 80+ garbage tables per raid burst).
local _scratchActiveAuras = {}     -- [spellID] = auraData
local _scratchActiveAuraNames = {} -- [spellName] = auraData

---------------------------------------------------------------------------
-- SECRET AURA HANDLING (shared patterns from groupframes_indicators.lua)
---------------------------------------------------------------------------
local FILTER_RAID = "PLAYER|HELPFUL|RAID"
local FILTER_RIC = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local FILTER_EXT = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local FILTER_DISP = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"
local SECRET_TRACKED_AURAS = {
    [10060] = {
        name = "Power Infusion",
        signature = 9,  -- raid(8) + disp(1)
        filter = "HELPFUL",
        scanLimit = 100,
    },
}

local function GetFontPath()
    local db = GetDB()
    local vdb = db and (db.party or db)
    local general = vdb and vdb.general
    local fontName = general and general.font or "Quazii"
    return LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
end

local function GetTrackedSpellName(spellID)
    local key = tonumber(spellID) or spellID
    local cached = spellNameCache[key]
    if cached ~= nil then
        return cached or nil
    end

    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, result = pcall(C_Spell.GetSpellName, key)
        if ok and type(result) == "string" and result ~= "" then
            name = result
        end
    elseif GetSpellInfo then
        local ok, result = pcall(GetSpellInfo, key)
        if ok and type(result) == "string" and result ~= "" then
            name = result
        end
    end

    spellNameCache[key] = name or false
    return name
end

local function MakeAuraSignature(passesRaid, passesRic, passesExt, passesDisp)
    return (passesRaid and 8 or 0) + (passesRic and 4 or 0) + (passesExt and 2 or 0) + (passesDisp and 1 or 0)
end

local function GetAuraFilterMatch(unit, auraInstanceID, filterString)
    if not unit or auraInstanceID == nil then
        return nil
    end
    if not C_UnitAuras or not C_UnitAuras.IsAuraFilteredOutByInstanceID then
        return nil
    end

    local ok, filteredOut = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, auraInstanceID, filterString)
    if not ok or IsSecretValue(filteredOut) then
        return nil
    end

    return not filteredOut
end

local function IsSecretTrackedAura(unit, auraData, config)
    if not config then
        return false
    end

    local auraInstanceID = auraData and auraData.auraInstanceID
    if auraInstanceID == nil then
        return false
    end

    local auraSpellID = auraData and auraData.spellId
    if auraSpellID and not IsSecretValue(auraSpellID) then
        return false
    end

    local auraName = auraData and auraData.name
    if auraName and not IsSecretValue(auraName) and auraName ~= config.name then
        return false
    end

    local passesRaid = GetAuraFilterMatch(unit, auraInstanceID, FILTER_RAID)
    local passesRic = GetAuraFilterMatch(unit, auraInstanceID, FILTER_RIC)
    local passesExt = GetAuraFilterMatch(unit, auraInstanceID, FILTER_EXT)
    local passesDisp = GetAuraFilterMatch(unit, auraInstanceID, FILTER_DISP)

    if passesRaid == nil or passesRic == nil or passesExt == nil or passesDisp == nil then
        return false
    end

    return MakeAuraSignature(passesRaid, passesRic, passesExt, passesDisp) == config.signature
end

local function FindSecretTrackedAura(unit, spellID, helpfulAuras)
    local config = SECRET_TRACKED_AURAS[spellID]
    if not config then
        return nil
    end

    if helpfulAuras then
        for _, helpfulAura in ipairs(helpfulAuras) do
            if IsSecretTrackedAura(unit, helpfulAura, config) then
                return helpfulAura
            end
        end
    end

    -- Skip expensive bulk scan in combat — the helpfulAuras path above
    -- already covers auras present in the shared cache.  The full
    -- GetUnitAuras(unit, filter, 100) scan allocates massive C-side
    -- tables that overwhelm the GC in 20-person raids.
    if not InCombatLockdown() and C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local scanFilter = config.filter or "HELPFUL"
        local scanLimit = config.scanLimit or 100
        local ok, allAuras = pcall(C_UnitAuras.GetUnitAuras, unit, scanFilter, scanLimit)
        if ok and allAuras then
            for _, auraData in ipairs(allAuras) do
                if IsSecretTrackedAura(unit, auraData, config) then
                    return auraData
                end
            end
        end
    end

    return nil
end

local function FindTrackedAuraData(unit, spellID, activeAurasByID, activeAurasByName, helpfulAuras)
    local auraData = activeAurasByID[spellID]
    if auraData then
        return auraData
    end

    local secretAura = FindSecretTrackedAura(unit, spellID, helpfulAuras)
    if secretAura then
        return secretAura
    end

    local spellName = GetTrackedSpellName(spellID)
    if not spellName then
        return nil
    end

    auraData = activeAurasByName[spellName]
    if auraData then
        return auraData
    end

    if not InCombatLockdown() and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local okHelpful, helpfulAura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HELPFUL")
        if okHelpful and helpfulAura then
            return helpfulAura
        end

        local okHarmful, harmfulAura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HARMFUL")
        if okHarmful and harmfulAura then
            return harmfulAura
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- CREATE INDICATOR FRAME
---------------------------------------------------------------------------
local function CreateIndicator(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(8, 8)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon = tex

    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    frame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- Cooldown swipe (used by icon display type)
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.cooldown = cd

    -- Stack text (used by icon display type)
    local stackText = frame:CreateFontString(nil, "OVERLAY")
    stackText:SetFont(GetFontPath(), 9, "OUTLINE")
    stackText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
    stackText:SetJustifyH("RIGHT")
    frame.stackText = stackText

    -- Solid color texture (used by square display type, hidden by default)
    local solidTex = frame:CreateTexture(nil, "ARTWORK")
    solidTex:SetAllPoints()
    solidTex:SetColorTexture(1, 1, 1, 1)
    solidTex:Hide()
    frame.solidColor = solidTex

    frame:Hide()
    return frame
end

local function AcquireIndicator(parent)
    local item = table_remove(iconPool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
        return item
    end
    return CreateIndicator(parent)
end

local function ReleaseIndicator(item)
    item:Hide()
    item:ClearAllPoints()
    if item.cooldown then item.cooldown:Clear() end
    if item.stackText then item.stackText:SetText("") end
    if item.icon then item.icon:Show(); item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    if item.solidColor then item.solidColor:Hide() end
    item:SetAlpha(1)
    item:SetBackdropBorderColor(0, 0, 0, 1)
    if #iconPool < POOL_SIZE then
        table_insert(iconPool, item)
    end
end

-- Update indicator data in-place without touching position or acquire/release.
-- Handles both "icon" and "square" display types, active and inactive states.
local function UpdateIndicatorData(ind, unit, slot, auraData, showSwipe)
    local isActive = auraData ~= nil
    local displayType = slot.displayType or "icon"

    if not isActive then
        if ind.cooldown then
            ind.cooldown:Hide()
            ind.cooldown:Clear()
        end
        if ind.stackText then
            ind.stackText:SetText("")
        end
        if ind.solidColor then
            ind.solidColor:Hide()
        end
        if ind.icon then
            ind.icon:Hide()
        end
        ind:SetAlpha(1)
        ind:Hide()
        return
    end

    ind:Show()

    if displayType == "square" then
        local color = slot.color or DEFAULT_SQUARE_COLOR
        ind.icon:Hide()
        ind.solidColor:SetColorTexture(color[1] or 0.5, color[2] or 0.5, color[3] or 0.5, color[4] or 1)
        ind.solidColor:Show()
        if ind.cooldown then
            ind.cooldown:Hide()
            ind.cooldown:Clear()
        end
        if ind.stackText then
            ind.stackText:SetText("")
        end
        ind:SetAlpha(1)
        ind:SetBackdropBorderColor(0, 0, 0, 1)
    else
        ind.solidColor:Hide()
        ind.icon:Show()
        ind.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        if auraData.icon then
            ind.icon:SetTexture(auraData.icon)
        end

        if showSwipe and ind.cooldown then
            ind.cooldown:Show()
            if ind.cooldown.SetReverse then
                pcall(ind.cooldown.SetReverse, ind.cooldown, ind._reverseSwipe == true)
            end
            local dur = auraData.duration
            local expTime = auraData.expirationTime
            if dur and expTime then
                if unit and auraData.auraInstanceID
                   and C_UnitAuras and C_UnitAuras.GetAuraDuration
                   and ind.cooldown.SetCooldownFromDurationObject then
                    local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                    if ok and durationObj then
                        pcall(ind.cooldown.SetCooldownFromDurationObject, ind.cooldown, durationObj)
                    elseif not IsSecretValue(expTime) and not IsSecretValue(dur) then
                        if ind.cooldown.SetCooldownFromExpirationTime then
                            pcall(ind.cooldown.SetCooldownFromExpirationTime, ind.cooldown, expTime, dur)
                        else
                            pcall(ind.cooldown.SetCooldown, ind.cooldown, expTime - dur, dur)
                        end
                    else
                        ind.cooldown:Clear()
                    end
                elseif not IsSecretValue(expTime) and not IsSecretValue(dur) then
                    if ind.cooldown.SetCooldownFromExpirationTime then
                        pcall(ind.cooldown.SetCooldownFromExpirationTime, ind.cooldown, expTime, dur)
                    else
                        pcall(ind.cooldown.SetCooldown, ind.cooldown, expTime - dur, dur)
                    end
                else
                    ind.cooldown:Clear()
                end
            else
                ind.cooldown:Clear()
            end
        elseif ind.cooldown then
            ind.cooldown:Hide()
            ind.cooldown:Clear()
        end

        if ind.stackText then
            local stacks = SafeToNumber(auraData.applications, 0)
            ind.stackText:SetText(stacks > 1 and stacks or "")
        end

        ind:SetAlpha(1)
        ind:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

---------------------------------------------------------------------------
-- SPEC DETECTION
---------------------------------------------------------------------------
local function GetPlayerSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then return GetSpecializationInfo(specIndex) end
    return nil
end

---------------------------------------------------------------------------
-- GET PINNED AURA SETTINGS
---------------------------------------------------------------------------
local function GetPinnedAuraSettings(isRaid)
    local db = GetDB()
    if not db then return nil end
    local vdb = (isRaid and db.raid or db.party) or db
    return vdb.pinnedAuras
end

---------------------------------------------------------------------------
-- STATE PER FRAME
---------------------------------------------------------------------------
local framePinnedState = Helpers.CreateStateTable()

local function GetPinnedState(frame)
    local state = framePinnedState[frame]
    if not state then
        state = { indicators = {} }
        framePinnedState[frame] = state
    end
    return state
end

---------------------------------------------------------------------------
-- CLEAR INDICATORS
---------------------------------------------------------------------------
local function ClearAllIndicators(frame)
    local state = framePinnedState[frame]
    if not state then return end
    for _, ind in ipairs(state.indicators) do
        ReleaseIndicator(ind)
    end
    wipe(state.indicators)
end

---------------------------------------------------------------------------
-- UPDATE: Process pinned auras for a single frame
---------------------------------------------------------------------------
local function UpdateFramePinnedAuras(frame)
    if not frame or not frame.unit then return end

    local isRaid = frame._isRaid
    local pa = GetPinnedAuraSettings(isRaid)
    if not pa or not pa.enabled then
        ClearAllIndicators(frame)
        return
    end

    local specID = GetPlayerSpecID()
    if not specID then
        ClearAllIndicators(frame)
        return
    end

    local specSlots = pa.specSlots
    if not specSlots then
        ClearAllIndicators(frame)
        return
    end

    local slots = specSlots[specID]
    if not slots or #slots == 0 then
        ClearAllIndicators(frame)
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        ClearAllIndicators(frame)
        return
    end

    local slotSize = pa.slotSize or 8
    local showSwipe = pa.showSwipe
    local reverseSwipe = pa.reverseSwipe == true
    local inset = pa.edgeInset or 2

    -- Build active aura lookup from shared cache.
    -- Uses module-level scratch tables (wipe+reuse) to avoid per-call allocation.
    local activeAuras = _scratchActiveAuras
    local activeAuraNames = _scratchActiveAuraNames
    wipe(activeAuras)
    wipe(activeAuraNames)
    local helpfulAuras = nil
    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    if cache then
        if cache.helpful then
            helpfulAuras = cache.helpful
            for _, auraData in ipairs(cache.helpful) do
                local spID = SafeValue(auraData.spellId, nil)
                if spID then activeAuras[spID] = auraData end
                local spName = SafeValue(auraData.name, nil)
                if spName and not activeAuraNames[spName] then
                    activeAuraNames[spName] = auraData
                end
            end
        end
        if cache.harmful then
            for _, auraData in ipairs(cache.harmful) do
                local spID = SafeValue(auraData.spellId, nil)
                if spID then activeAuras[spID] = auraData end
                local spName = SafeValue(auraData.name, nil)
                if spName and not activeAuraNames[spName] then
                    activeAuraNames[spName] = auraData
                end
            end
        end
    elseif not InCombatLockdown() and C_UnitAuras and C_UnitAuras.GetUnitAuras then
        -- Fallback: shared cache missing (should not happen in normal dispatch).
        -- Skip in combat to avoid C-side table allocations that overwhelm the GC.
        for _, filter in ipairs(AURA_FILTERS) do
            local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, filter, 40)
            if ok and auras then
                if filter == "HELPFUL" then helpfulAuras = auras end
                for _, auraData in ipairs(auras) do
                    local spID = SafeValue(auraData.spellId, nil)
                    if spID then activeAuras[spID] = auraData end
                    local spName = SafeValue(auraData.name, nil)
                    if spName and not activeAuraNames[spName] then
                        activeAuraNames[spName] = auraData
                    end
                end
            end
        end
    end

    -- Expose pinned aura IDs for buff deduplication
    if not frame._pinnedAuraIDs then frame._pinnedAuraIDs = {} end
    wipe(frame._pinnedAuraIDs)

    local state = GetPinnedState(frame)

    -- Count valid slots to determine if we can reuse existing indicators
    -- (slot set is config-fixed per spec — only changes on settings/spec change).
    local validSlotCount = 0
    for _, slot in ipairs(slots) do
        if slot.spellID then validSlotCount = validSlotCount + 1 end
    end

    -- Fast path: if slot count matches existing indicator count, reuse
    -- indicators in-place (skip release→acquire→position cycle).
    local canReuse = (#state.indicators == validSlotCount) and (validSlotCount > 0)

    if canReuse then
        -- In-place update: just refresh data/state on existing indicators
        local idx = 0
        for _, slot in ipairs(slots) do
            local spellID = slot.spellID
            if spellID then
                idx = idx + 1
                local ind = state.indicators[idx]
                local auraData = FindTrackedAuraData(unit, spellID, activeAuras, activeAuraNames, helpfulAuras)
                if auraData and auraData.auraInstanceID then
                    frame._pinnedAuraIDs[auraData.auraInstanceID] = true
                end
                ind._reverseSwipe = reverseSwipe
                UpdateIndicatorData(ind, unit, slot, auraData, showSwipe)
            end
        end
    else
        -- Full rebuild: release all, acquire new, position
        for _, ind in ipairs(state.indicators) do
            ReleaseIndicator(ind)
        end
        wipe(state.indicators)

        local bottomPad = frame._bottomPad or 0

        for _, slot in ipairs(slots) do
            local spellID = slot.spellID
            if spellID then
                local anchor = slot.anchor or "TOPLEFT"
                local auraData = FindTrackedAuraData(unit, spellID, activeAuras, activeAuraNames, helpfulAuras)
                if auraData and auraData.auraInstanceID then
                    frame._pinnedAuraIDs[auraData.auraInstanceID] = true
                end

                local ind = AcquireIndicator(frame)
                ind:SetSize(slotSize, slotSize)
                ind:SetFrameLevel(frame:GetFrameLevel() + 8)

                -- Position at anchor with inset
                ind:ClearAllPoints()
                local insetDir = ANCHOR_INSET[anchor] or DEFAULT_INSET
                local offX = insetDir[1] * inset + (slot.offsetX or 0)
                local offY = insetDir[2] * inset + (slot.offsetY or 0)
                if anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
                    offY = offY + bottomPad
                end
                ind:SetPoint(anchor, frame, anchor, offX, offY)

                ind._reverseSwipe = reverseSwipe
                UpdateIndicatorData(ind, unit, slot, auraData, showSwipe)
                state.indicators[#state.indicators + 1] = ind
            end
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HOOKUP
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec change: evict spell name cache (spell roster changes per spec)
        wipe(spellNameCache)
        QUI_GFP:RefreshAll()
    end
end)

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_GFP:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    for _, frame in pairs(GF.unitFrameMap) do
        if frame and frame:IsShown() then
            UpdateFramePinnedAuras(frame)
        end
    end
end

function QUI_GFP:RefreshFrame(frame)
    UpdateFramePinnedAuras(frame)
end

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "GF_PinnedAuras", frame = eventFrame }
