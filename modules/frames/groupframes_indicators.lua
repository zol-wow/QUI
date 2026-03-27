--[[
    QUI Group Frames - Aura Indicators
    Simple icon-row aura tracking on group frames.
    Tracked spells are configured via the Designer UI (trackedSpells table).
    Display uses the same container pattern as buffs/debuffs: icon size,
    anchor, grow direction, spacing, max count.
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
local QUI_GFI = {}
ns.QUI_GroupFrameIndicators = QUI_GFI

---------------------------------------------------------------------------
-- ICON POOL
---------------------------------------------------------------------------
local iconPool = {}
local POOL_SIZE = 40
local spellNameCache = {}

-- Reusable scratch tables for aura lookups (avoids 2 table allocations
-- per frame per UNIT_AURA event — 80+ garbage tables per raid burst).
local _scratchActiveAuras = {}     -- [spellID] = auraData
local _scratchActiveAuraNames = {} -- [spellName] = auraData

local FILTER_RAID = "PLAYER|HELPFUL|RAID"
local FILTER_RIC = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local FILTER_EXT = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local FILTER_DISP = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"
local SECRET_TRACKED_AURAS = {
    [10060] = {
        name = "Power Infusion",
        signature = "1:0:0:1",
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
    return (passesRaid and "1" or "0")
        .. ":" .. (passesRic and "1" or "0")
        .. ":" .. (passesExt and "1" or "0")
        .. ":" .. (passesDisp and "1" or "0")
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

    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
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

    -- Secret tracked auras can lose both readable spellId and reliable
    -- spell-name lookup in combat, so try their signature matcher before
    -- depending on name resolution.
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

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
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

local function CreateIconIndicator(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(16, 16)

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

    -- Cooldown swipe
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.cooldown = cd

    -- Stack text
    local stackText = frame:CreateFontString(nil, "OVERLAY")
    stackText:SetFont(GetFontPath(), 9, "OUTLINE")
    stackText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
    stackText:SetJustifyH("RIGHT")
    frame.stackText = stackText

    frame:Hide()
    return frame
end

local function AcquireIcon(parent)
    local item = table_remove(iconPool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
        return item
    end
    return CreateIconIndicator(parent)
end

local function ReleaseIcon(item)
    item:Hide()
    item:ClearAllPoints()
    if item.cooldown then item.cooldown:Clear() end
    if item.stackText then item.stackText:SetText("") end
    if #iconPool < POOL_SIZE then
        table_insert(iconPool, item)
    end
end

-- Update icon data in-place (texture, cooldown, stacks) without touching
-- position or acquire/release. Used by the fast diff path to skip the
-- full release→acquire→position cycle when the active aura set is unchanged.
local function UpdateIconData(icon, unit, auraData)
    -- Texture
    if icon.icon and auraData.icon then
        icon.icon:SetTexture(auraData.icon)
    end

    -- Cooldown swipe
    if icon.cooldown and auraData then
        local dur = auraData.duration
        local expTime = auraData.expirationTime
        if dur and expTime then
            if unit and auraData.auraInstanceID
               and C_UnitAuras and C_UnitAuras.GetAuraDuration
               and icon.cooldown.SetCooldownFromDurationObject then
                local ok, durationObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                if ok and durationObj then
                    pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durationObj)
                elseif not IsSecretValue(expTime) and not IsSecretValue(dur) then
                    if icon.cooldown.SetCooldownFromExpirationTime then
                        pcall(icon.cooldown.SetCooldownFromExpirationTime, icon.cooldown, expTime, dur)
                    else
                        pcall(icon.cooldown.SetCooldown, icon.cooldown, expTime - dur, dur)
                    end
                else
                    icon.cooldown:Clear()
                end
            elseif not IsSecretValue(expTime) and not IsSecretValue(dur) then
                if icon.cooldown.SetCooldownFromExpirationTime then
                    pcall(icon.cooldown.SetCooldownFromExpirationTime, icon.cooldown, expTime, dur)
                else
                    pcall(icon.cooldown.SetCooldown, icon.cooldown, expTime - dur, dur)
                end
            else
                icon.cooldown:Clear()
            end
        end
    end

    -- Stacks
    if icon.stackText and auraData then
        local stacks = SafeToNumber(auraData.applications, 0)
        icon.stackText:SetText(stacks > 1 and stacks or "")
    end
end

---------------------------------------------------------------------------
-- GET TRACKED SPELL IDS from DB
---------------------------------------------------------------------------
local function GetTrackedSpellIDs(isRaid)
    local db = GetDB()
    if not db then return nil end
    local vdb = (isRaid and db.raid or db.party) or db
    if not vdb.auraIndicators or not vdb.auraIndicators.enabled then
        return nil
    end

    local tracked = vdb.auraIndicators.trackedSpells
    if not tracked then return nil end

    -- Build list of enabled spell IDs
    local spells = {}
    for spellID, enabled in pairs(tracked) do
        if enabled then
            spells[#spells + 1] = tonumber(spellID) or spellID
        end
    end

    return #spells > 0 and spells or nil
end

---------------------------------------------------------------------------
-- INDICATOR STATE per frame
---------------------------------------------------------------------------
local frameIndicatorState = Helpers.CreateStateTable()

local function GetIndicatorState(frame)
    local state = frameIndicatorState[frame]
    if not state then
        state = { icons = {}, container = nil, _prevAuraIDs = {} }
        frameIndicatorState[frame] = state
    end
    return state
end

---------------------------------------------------------------------------
-- ENSURE CONTAINER: Create/update the icon container on a group frame
---------------------------------------------------------------------------
local function EnsureContainer(frame)
    local state = GetIndicatorState(frame)
    if state.container then return state.container end

    local container = CreateFrame("Frame", nil, frame)
    container:SetSize(1, 1)
    container:SetFrameLevel(frame:GetFrameLevel() + 8)
    state.container = container
    return container
end

local function PositionContainer(frame)
    local db = GetDB()
    if not db then return end
    local isRaid = frame._isRaid
    local vdb = (isRaid and db.raid or db.party) or db
    local ai = vdb.auraIndicators
    if not ai then return end

    local state = GetIndicatorState(frame)
    local container = state.container
    if not container then return end

    local anchor = ai.anchor or "TOPLEFT"
    local offX = ai.anchorOffsetX or 0
    local offY = ai.anchorOffsetY or 0

    container:ClearAllPoints()
    if anchor:find("BOTTOM") then offY = offY + (frame._bottomPad or 0) end
    container:SetPoint(anchor, frame, anchor, offX, offY)
end

---------------------------------------------------------------------------
-- CLEAR all indicators from a frame
---------------------------------------------------------------------------
local function ClearIndicators(frame)
    local state = frameIndicatorState[frame]
    if not state then return end

    for _, icon in ipairs(state.icons) do
        ReleaseIcon(icon)
    end
    wipe(state.icons)
end

---------------------------------------------------------------------------
-- UPDATE: Process indicators for a single frame
---------------------------------------------------------------------------
local function UpdateFrameIndicators(frame)
    if not frame or not frame.unit then return end

    local isRaid = frame._isRaid
    local trackedSpells = GetTrackedSpellIDs(isRaid)
    if not trackedSpells then
        ClearIndicators(frame)
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        ClearIndicators(frame)
        return
    end

    local db = GetDB()
    if not db then
        ClearIndicators(frame)
        return
    end
    local vdb = (isRaid and db.raid or db.party) or db
    local ai = vdb.auraIndicators
    if not ai then
        ClearIndicators(frame)
        return
    end

    local iconSize = ai.iconSize or 14
    local growDir = ai.growDirection or "RIGHT"
    local spacing = ai.spacing or 2
    local maxIcons = ai.maxIndicators or 5
    local anchor = ai.anchor or "TOPLEFT"

    -- Build a set of active auras on the unit from shared cache.
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
                local spellID = SafeValue(auraData.spellId, nil)
                if spellID then activeAuras[spellID] = auraData end
                local spellName = SafeValue(auraData.name, nil)
                if spellName and not activeAuraNames[spellName] then
                    activeAuraNames[spellName] = auraData
                end
            end
        end
        if cache.harmful then
            for _, auraData in ipairs(cache.harmful) do
                local spellID = SafeValue(auraData.spellId, nil)
                if spellID then activeAuras[spellID] = auraData end
                local spellName = SafeValue(auraData.name, nil)
                if spellName and not activeAuraNames[spellName] then
                    activeAuraNames[spellName] = auraData
                end
            end
        end
    else
        -- Fallback: direct scan if cache not populated
        if C_UnitAuras and C_UnitAuras.GetUnitAuras then
            for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
                local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, filter, 40)
                if ok and auras then
                    if filter == "HELPFUL" then
                        helpfulAuras = auras
                    end
                    for _, auraData in ipairs(auras) do
                        local spellID = SafeValue(auraData.spellId, nil)
                        if spellID then activeAuras[spellID] = auraData end
                        local spellName = SafeValue(auraData.name, nil)
                        if spellName and not activeAuraNames[spellName] then
                            activeAuraNames[spellName] = auraData
                        end
                    end
                end
            end
        end
    end

    local state = GetIndicatorState(frame)

    -- Expose active indicator auraInstanceIDs for buff deduplication
    if not frame._indicatorAuraIDs then frame._indicatorAuraIDs = {} end
    wipe(frame._indicatorAuraIDs)

    -- Pre-resolve which tracked spells are active and collect their auraData.
    -- This lets us diff against the previous set before touching any icons.
    local defIDs = frame._defensiveAuraIDs
    local resolvedCount = 0
    local resolvedData = state._resolvedData
    if not resolvedData then
        resolvedData = {}
        state._resolvedData = resolvedData
    end

    for _, spellID in ipairs(trackedSpells) do
        if resolvedCount >= maxIcons then break end
        local auraData = FindTrackedAuraData(unit, spellID, activeAuras, activeAuraNames, helpfulAuras)
        if auraData then
            if not (defIDs and auraData.auraInstanceID and defIDs[auraData.auraInstanceID]) then
                resolvedCount = resolvedCount + 1
                resolvedData[resolvedCount] = auraData
                if auraData.auraInstanceID then
                    frame._indicatorAuraIDs[auraData.auraInstanceID] = true
                end
            end
        end
    end
    -- Trim stale entries from previous pass
    for i = resolvedCount + 1, #resolvedData do
        resolvedData[i] = nil
    end

    -- Diff: check if the active aura set matches the previous frame.
    -- If same count and same auraInstanceIDs in order, skip the expensive
    -- release→acquire→position cycle and just update icon data in-place.
    local prevIDs = state._prevAuraIDs
    local canFastPath = (#prevIDs == resolvedCount) and (resolvedCount == #state.icons)
    if canFastPath then
        for i = 1, resolvedCount do
            local newID = resolvedData[i].auraInstanceID
            if not newID or IsSecretValue(newID) or prevIDs[i] ~= newID then
                canFastPath = false
                break
            end
        end
    end

    if canFastPath then
        -- Fast path: same aura set — only update data (cooldown, stacks, texture).
        -- Positions are unchanged, skip release→acquire→position entirely.
        for i = 1, resolvedCount do
            UpdateIconData(state.icons[i], unit, resolvedData[i])
        end
    else
        -- Full rebuild: release all icons, acquire new ones, position them
        for _, icon in ipairs(state.icons) do
            ReleaseIcon(icon)
        end
        wipe(state.icons)
        wipe(prevIDs)

        local container = EnsureContainer(frame)
        PositionContainer(frame)

        local count = 0
        for i = 1, resolvedCount do
            local auraData = resolvedData[i]
            count = count + 1
            local icon = AcquireIcon(container)
            icon:SetSize(iconSize, iconSize)

            -- Position in row
            icon:ClearAllPoints()
            local vertPart = anchor:find("TOP") and "TOP" or (anchor:find("BOTTOM") and "BOTTOM" or "")
            local firstHoriz = growDir == "LEFT" and "RIGHT" or "LEFT"
            local firstAnchor = vertPart .. firstHoriz

            if count == 1 then
                icon:SetPoint(firstAnchor, container, firstAnchor, 0, 0)
            else
                local prev = state.icons[count - 1]
                if prev then
                    if growDir == "LEFT" then
                        icon:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
                    else
                        icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                    end
                end
            end

            UpdateIconData(icon, unit, auraData)
            icon:Show()
            state.icons[count] = icon
            prevIDs[count] = auraData.auraInstanceID
        end

        -- CENTER: reposition all icons centered around the container's anchor.
        -- Only needed on full rebuild — fast path preserves existing positions.
        if growDir == "CENTER" and count > 0 then
            local totalSpan = count * iconSize + math.max(count - 1, 0) * spacing
            local startX = -totalSpan / 2
            local vertPart2 = anchor:find("TOP") and "TOP" or (anchor:find("BOTTOM") and "BOTTOM" or "")
            local iconPoint = vertPart2 == "" and "LEFT" or (vertPart2 .. "LEFT")
            for idx = 1, count do
                local ic = state.icons[idx]
                if ic then
                    ic:ClearAllPoints()
                    ic:SetPoint(iconPoint, container, anchor, startX + (idx - 1) * (iconSize + spacing), 0)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- EVENT HOOKUP
-- UNIT_AURA is driven by the shared aura scan in groupframes_auras.lua
-- (FlushPendingAuras calls GFI:RefreshFrame) to ensure indicators update
-- before buffs, enabling buff deduplication.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        QUI_GFI:RefreshAll()
    end
end)

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_GFI:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then return end

    for _, frame in pairs(GF.unitFrameMap) do
        if frame and frame:IsShown() then
            UpdateFrameIndicators(frame)
        end
    end
end

function QUI_GFI:RefreshFrame(frame)
    UpdateFrameIndicators(frame)
end
