--[[ QUI Group Frames - Name and Status Updates ]]
local ADDON_NAME, ns = ...
local QUI_GF = ns.QUI_GroupFrames
if not QUI_GF then return end
local _ = QUI_GF._
if not _ then return end

local QUICore = _.QUICore
local Helpers = _.Helpers
local IsSecretValue = _.IsSecretValue
local SafeValue = _.SafeValue
local SafeToNumber = _.SafeToNumber
local ApplyCooldownFromAura = _.ApplyCooldownFromAura
local _state = _.state
local COLORS = _.COLORS
local RAID_CLASS_COLORS = _.RAID_CLASS_COLORS
local GetNameSettings = _.GetNameSettings
local GetIndicatorSettings = _.GetIndicatorSettings
local GetHealerSettings = _.GetHealerSettings
local GetPortraitSettings = _.GetPortraitSettings
local GetFrameState = _.GetFrameState
local GetUnitLifeState = _.GetUnitLifeState
local GetCachedBackdrop = _.GetCachedBackdrop
local UnitExists = UnitExists
local UnitName = UnitName
local UnitClass = UnitClass
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsAFK = UnitIsAFK
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitThreatSituation = UnitThreatSituation
local UnitIsUnit = UnitIsUnit
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitPhaseReason = UnitPhaseReason
local GetReadyCheckStatus = GetReadyCheckStatus
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local SetPortraitTexture = SetPortraitTexture
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local StaticPopup_FindVisible = StaticPopup_FindVisible
local C_UnitAuras = C_UnitAuras
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local math_min = math.min
local math_max = math.max

-- Dispel constants and cached state
local _dispel = {
    defaultColors = {
        Magic   = { 0.2, 0.6, 1.0, 1 },  -- Blue
        Curse   = { 0.6, 0.0, 1.0, 1 },  -- Purple
        Disease = { 0.6, 0.4, 0.0, 1 },  -- Brown
        Poison  = { 0.0, 0.6, 0.0, 1 },  -- Green
        Bleed   = { 0.8, 0.0, 0.0, 1 },  -- Red
    },
    allEnums = {1, 2, 3, 4, 9, 11},  -- WoW 12.0+, from SpellDispelType DB2
    enumNames = {
        [1] = "Magic", [2] = "Curse", [3] = "Disease", [4] = "Poison",
        [9] = "Bleed", [11] = "Bleed",
    },
    colorCurve = nil,
    cachedColors = nil,
    borderKeys = {"borderTop", "borderBottom", "borderLeft", "borderRight"},
}

-- Forward declarations; bodies defined later in file
local GetDispelColors
local InvalidateDispelColors

local function GetDispelColorCurve(opacity)
    if _dispel.colorCurve then return _dispel.colorCurve end
    if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
    local colors = GetDispelColors()
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(0, 0, 0, 0))  -- None = invisible
    for _, enumVal in ipairs(_dispel.allEnums) do
        local typeName = _dispel.enumNames[enumVal]
        local c = typeName and colors[typeName]
        if c then
            curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], opacity or 0.8))
        end
    end
    _dispel.colorCurve = curve
    return curve
end

-- Defensive cooldown spell IDs (fallback when AuraUtil.AuraFilters unavailable)
local DEFENSIVE_SPELL_IDS = {
    -- External defensives
    [102342] = true, -- Ironbark
    [33206]  = true, -- Pain Suppression
    [47788]  = true, -- Guardian Spirit
    [6940]   = true, -- Blessing of Sacrifice
    [116849] = true, -- Life Cocoon
    [357170] = true, -- Time Dilation
    [98008]  = true, -- Spirit Link Totem
    -- Big personal defensives
    [48707]  = true, -- Anti-Magic Shell
    [48792]  = true, -- Icebound Fortitude
    [61336]  = true, -- Survival Instincts
    [22812]  = true, -- Barkskin
    [186265] = true, -- Aspect of the Turtle
    [45438]  = true, -- Ice Block
    [55233]  = true, -- Vampiric Blood
    [184364] = true, -- Enraged Regeneration
    [12975]  = true, -- Last Stand
    [871]    = true, -- Shield Wall
    [31224]  = true, -- Cloak of Shadows
    [5277]   = true, -- Evasion
    [104773] = true, -- Unending Resolve
    [47585]  = true, -- Dispersion
    [19236]  = true, -- Desperate Prayer
    [108271] = true, -- Astral Shift
    [122278] = true, -- Dampen Harm
    [122783] = true, -- Diffuse Magic
    [363916] = true, -- Obsidian Scales
}

GetDispelColors = function()
    if _dispel.cachedColors then return _dispel.cachedColors end
    local hs = GetHealerSettings()
    local dbColors = hs and hs.dispelOverlay and hs.dispelOverlay.colors
    if not dbColors then
        _dispel.cachedColors = _dispel.defaultColors
        return _dispel.defaultColors
    end
    _dispel.cachedColors = {
        Magic   = dbColors.Magic   or _dispel.defaultColors.Magic,
        Curse   = dbColors.Curse   or _dispel.defaultColors.Curse,
        Disease = dbColors.Disease or _dispel.defaultColors.Disease,
        Poison  = dbColors.Poison  or _dispel.defaultColors.Poison,
        Bleed   = dbColors.Bleed   or _dispel.defaultColors.Bleed,
    }
    return _dispel.cachedColors
end

InvalidateDispelColors = function()
    _dispel.cachedColors = nil
end

local function UpdateName(frame)
    if not frame or not frame.unit or not frame.nameText then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        frame.nameText:SetText("")
        return
    end

    local isRaid = frame._isRaid
    local nameSettings = GetNameSettings(isRaid)
    if nameSettings and nameSettings.showName == false then
        frame.nameText:SetText("")
        return
    end

    local name = UnitName(unit)
    if name then
        local maxLen = nameSettings and nameSettings.maxNameLength or 10
        if maxLen > 0 and #name > maxLen then
            name = Helpers.TruncateUTF8 and Helpers.TruncateUTF8(name, maxLen) or name:sub(1, maxLen)
        end
        frame.nameText:SetText(name)

        -- Color
        if nameSettings and nameSettings.nameTextUseClassColor then
            local _, class = UnitClass(unit)
            if class then
                local cc = RAID_CLASS_COLORS[class]
                if cc then
                    frame.nameText:SetTextColor(cc.r, cc.g, cc.b, 1)
                    return
                end
            end
        end
        local tc = nameSettings and nameSettings.nameTextColor or COLORS.WHITE
        frame.nameText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    else
        frame.nameText:SetText("")
    end
end

---------------------------------------------------------------------------
-- UPDATE: Absorbs
---------------------------------------------------------------------------
-- Absorbs: optional pre-computed args from fast health path avoid redundant API calls.

local ROLE_ATLAS = {
    TANK = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

local ROLE_TOGGLE_KEY = {
    TANK    = "showRoleTank",
    HEALER  = "showRoleHealer",
    DAMAGER = "showRoleDPS",
}

local function UpdateRoleIcon(frame)
    if not frame or not frame.unit or not frame.roleIcon then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showRoleIcon == false then
        frame.roleIcon:Hide()
        return
    end

    local role = UnitGroupRolesAssigned(frame.unit)
    -- Check per-role toggle
    local toggleKey = ROLE_TOGGLE_KEY[role]
    if toggleKey and indSettings[toggleKey] == false then
        frame.roleIcon:Hide()
        return
    end

    local atlas = ROLE_ATLAS[role]
    if atlas then
        frame.roleIcon:SetAtlas(atlas)
        frame.roleIcon:Show()
    else
        frame.roleIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Ready Check
---------------------------------------------------------------------------
local READY_CHECK_TEXTURES = {
    ready    = "INTERFACE\\RAIDFRAME\\ReadyCheck-Ready",
    notready = "INTERFACE\\RAIDFRAME\\ReadyCheck-NotReady",
    waiting  = "INTERFACE\\RAIDFRAME\\ReadyCheck-Waiting",
}

local function UpdateReadyCheck(frame)
    if not frame or not frame.unit or not frame.readyCheckIcon then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showReadyCheck == false then
        frame.readyCheckIcon:Hide()
        return
    end

    local status = GetReadyCheckStatus(frame.unit)
    if status then
        -- QUI pattern: AFK players waiting on ready check show "not ready"
        if status == "waiting" then
            local isAFK = UnitIsAFK(frame.unit)
            if not IsSecretValue(isAFK) and isAFK then
                status = "notready"
            end
        end
        local tex = READY_CHECK_TEXTURES[status] or READY_CHECK_TEXTURES.waiting
        frame.readyCheckIcon:SetTexture(tex)
        frame.readyCheckIcon:Show()
    else
        frame.readyCheckIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Resurrection
---------------------------------------------------------------------------
local function UpdateResurrection(frame)
    if not frame or not frame.unit or not frame.resIcon then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showResurrection == false then
        frame.resIcon:Hide()
        return
    end

    local hasRes = UnitHasIncomingResurrection(frame.unit)
    if hasRes then
        frame.resIcon:Show()
    else
        frame.resIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Summon Pending
---------------------------------------------------------------------------
_state.IsPlayerUnit = function(unit)
    if unit == "player" then return true end
    if UnitIsUnit then
        local ok, isPlayer = pcall(UnitIsUnit, unit, "player")
        return ok and not IsSecretValue(isPlayer) and isPlayer == true
    end
    return false
end

_state.GetActivePlayerSummonPopup = function()
    if not StaticPopup_FindVisible then return nil, nil end

    local checkedPopup = false
    local ok, popup = pcall(StaticPopup_FindVisible, "CONFIRM_SUMMON")
    if ok and not IsSecretValue(popup) then
        if popup then return true, "CONFIRM_SUMMON" end
        checkedPopup = true
    end

    ok, popup = pcall(StaticPopup_FindVisible, "CONFIRM_SUMMON_SCENARIO")
    if ok and not IsSecretValue(popup) then
        if popup then return true, "CONFIRM_SUMMON_SCENARIO" end
        checkedPopup = true
    end

    ok, popup = pcall(StaticPopup_FindVisible, "CONFIRM_SUMMON_STARTING_AREA")
    if ok and not IsSecretValue(popup) then
        if popup then return true, "CONFIRM_SUMMON_STARTING_AREA" end
        checkedPopup = true
    end

    if checkedPopup then return false, nil end
    return nil, nil
end

_state.HasActivePlayerSummonConfirmation = function()
    local popupVisible = _state.GetActivePlayerSummonPopup()
    if popupVisible ~= nil then return popupVisible end

    if C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft then
        local ok, timeLeft = pcall(C_SummonInfo.GetSummonConfirmTimeLeft)
        if ok and not IsSecretValue(timeLeft) then
            return SafeToNumber(timeLeft, 0) > 0
        end
    end
    return false
end

local function UpdateSummonPending(frame)
    if not frame or not frame.unit or not frame.summonIcon then return end
    if not UnitExists(frame.unit) then
        frame.summonIcon:Hide()
        return
    end

    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showSummonPending == false then
        frame.summonIcon:Hide()
        return
    end

    local showSummon = false
    if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        local okHas, hasSummon = pcall(C_IncomingSummon.HasIncomingSummon, frame.unit)
        local okStatus, status = pcall(C_IncomingSummon.IncomingSummonStatus, frame.unit)
        if okHas and okStatus and not IsSecretValue(hasSummon) and not IsSecretValue(status) and hasSummon == true then
            local pendingStatus = Enum and Enum.SummonStatus and Enum.SummonStatus.Pending or 1
            showSummon = status == pendingStatus
        end
    elseif C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then
        local ok, hasSummon = pcall(C_IncomingSummon.HasIncomingSummon, frame.unit)
        if ok and not IsSecretValue(hasSummon) then
            showSummon = hasSummon == true
        end
    end

    if showSummon and _state.IsPlayerUnit(frame.unit) then
        showSummon = _state.HasActivePlayerSummonConfirmation()
    end

    if showSummon then
        frame.summonIcon:Show()
    else
        frame.summonIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Threat Border
---------------------------------------------------------------------------
local function UpdateThreat(frame)
    if not frame or not frame.unit or not frame.threatBorder then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showThreatBorder == false then
        frame.threatBorder:Hide()
        return
    end

    local status = UnitThreatSituation(frame.unit)
    if status and status >= 2 then
        local tc = indSettings.threatColor or _state.defaultColors.threat
        frame.threatBorder:SetBackdropBorderColor(tc[1], tc[2], tc[3], tc[4] or 0.8)
        -- Keep threat border below icons/indicators — re-level in case frame
        -- base level shifted since decoration (secure header can re-level children)
        frame.threatBorder:SetFrameLevel(frame:GetFrameLevel() + 3)
        frame.threatBorder:Show()
    else
        frame.threatBorder:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Target Marker (Raid Icon)
---------------------------------------------------------------------------
local function UpdateTargetMarker(frame)
    if not frame or not frame.unit or not frame.targetMarker then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showTargetMarker == false then
        frame.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(frame.unit)
    if index then
        frame.targetMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(frame.targetMarker, index)
        frame.targetMarker:Show()
    else
        frame.targetMarker:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Leader Icon
---------------------------------------------------------------------------
local function UpdateLeaderIcon(frame)
    if not frame or not frame.unit or not frame.leaderIcon then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showLeaderIcon == false then
        frame.leaderIcon:Hide()
        return
    end

    local isLeader = UnitIsGroupLeader(frame.unit)
    local isAssistant = UnitIsGroupAssistant(frame.unit)
    if isLeader then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:Show()
    elseif isAssistant then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader") -- Same icon, slight dimming
        frame.leaderIcon:SetAlpha(0.6)
        frame.leaderIcon:Show()
    else
        frame.leaderIcon:Hide()
        frame.leaderIcon:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Phase Icon
---------------------------------------------------------------------------
local function UpdatePhaseIcon(frame)
    if not frame or not frame.unit or not frame.phaseIcon then return end
    local isRaid = frame._isRaid
    local indSettings = GetIndicatorSettings(isRaid)
    if not indSettings or indSettings.showPhaseIcon == false then
        frame.phaseIcon:Hide()
        return
    end

    local phased = UnitPhaseReason(frame.unit) ~= nil and UnitExists(frame.unit)
    if phased then
        frame.phaseIcon:Show()
    else
        frame.phaseIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Connection (offline dimming)
---------------------------------------------------------------------------
local function UpdateConnection(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit

    local isConnected, isDead = GetUnitLifeState(unit)

    if not isConnected and UnitExists(unit) then
        frame:SetAlpha(0.5)
    elseif isDead then
        -- Dead dimming (set in UpdateHealth) — don't override with 1.0
        frame:SetAlpha(0.65)
    else
        -- Alive + connected: don't fight with DoRangeCheck for alpha ownership.
        -- Range check ticker runs every 0.2s and owns the alpha for alive targets.
        -- Only set alpha here if range check hasn't initialized state yet.
        local state = GetFrameState(frame)
        if state.outOfRange == nil then
            frame:SetAlpha(1)
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Target Highlight
---------------------------------------------------------------------------
local function UpdateTargetHighlight(frame)
    if not frame or not frame.targetHighlight then return end
    local isRaid = frame._isRaid
    local healerSettings = GetHealerSettings(isRaid)
    if not healerSettings or not healerSettings.targetHighlight or healerSettings.targetHighlight.enabled == false then
        frame.targetHighlight:Hide()
        return
    end

    if frame.unit and UnitIsUnit(frame.unit, "target") then
        local c = healerSettings.targetHighlight.color or _state.defaultColors.targetHighlight
        frame.targetHighlight:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.6)
        frame.targetHighlight:Show()
        -- Keep fast-path cache in sync (used by PLAYER_TARGET_CHANGED fast unhighlight)
        local list = QUI_GF._targetHighlightFrames
        if not list then
            list = {}
            QUI_GF._targetHighlightFrames = list
        end
        for i = 1, #list do
            if list[i] == frame then return end
        end
        list[#list + 1] = frame
    else
        frame.targetHighlight:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Dispel Overlay
---------------------------------------------------------------------------
-- Helper: apply color to all 4 StatusBar borders + fill
local function SetDispelBorderColor(overlay, r, g, b, a)
    for _, key in ipairs(_dispel.borderKeys) do
        local border = overlay[key]
        if border then
            border:GetStatusBarTexture():SetVertexColor(r, g, b, a)
        end
    end
    if overlay.fill then
        local fillA = overlay._fillOpacity or 0
        overlay.fill:SetVertexColor(r, g, b, fillA)
    end
end

-- Helper: apply a ColorMixin (secret-safe) to all 4 StatusBar borders + fill
local function SetDispelBorderColorMixin(overlay, color)
    for _, key in ipairs(_dispel.borderKeys) do
        local border = overlay[key]
        if border then
            local tex = border:GetStatusBarTexture()
            -- GetRGBA() returns secret values; SetVertexColor is C-side and handles them
            tex:SetVertexColor(color:GetRGBA())
        end
    end
    if overlay.fill then
        -- Use the same RGB but with the fill opacity
        local fillA = overlay._fillOpacity or 0
        overlay.fill:SetVertexColor(color:GetRGBA())
        overlay.fill:SetAlpha(fillA)
    end
end

local function ShowConfiguredDispelOverlay(overlay, colors, dispelType, opacity)
    if not dispelType or not colors then return false end

    local c = colors[dispelType]
    if not c then return false end

    SetDispelBorderColor(overlay, c[1], c[2], c[3], opacity)
    overlay:Show()
    return true
end

local function UpdateDispelOverlay(frame)
    if not frame or not frame.unit or not frame.dispelOverlay then return end
    local isRaid = frame._isRaid
    local healerSettings = GetHealerSettings(isRaid)
    if not healerSettings or not healerSettings.dispelOverlay or healerSettings.dispelOverlay.enabled == false then
        frame.dispelOverlay:Hide()
        return
    end

    local _, isDeadOrGhost = GetUnitLifeState(frame.unit)
    if not UnitExists(frame.unit) or isDeadOrGhost then
        frame.dispelOverlay:Hide()
        return
    end

    local unit = frame.unit
    local overlay = frame.dispelOverlay

    -- Fast path: the aura scan already classified every harmful aura against
    -- HARMFUL|RAID_PLAYER_DISPELLABLE and stashed the matching instance IDs
    -- in cache.playerDispellable. Probe the set directly — this replaces a
    -- per-aura pcall+filter-check loop with a single next() call, which is
    -- the biggest raid-perf win on this path.
    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    local hasDispellable = false
    local firstDispellableInstID = nil
    local firstDispellableType = nil
    local fromPrivateSlots = false

    if cache and cache.playerDispellableOrder then
        local instID = cache.playerDispellableOrder[1]
        if instID then
            hasDispellable = true
            firstDispellableInstID = instID
            local dispelAura = cache.debuffsByID and cache.debuffsByID[instID]
            if dispelAura and dispelAura.dispelName and not IsSecretValue(dispelAura.dispelName) then
                firstDispellableType = SafeValue(dispelAura.dispelName, nil)
            end
        end
    end

    if not hasDispellable then
        local GFPA = ns.QUI_GroupFramePrivateAuras
        if GFPA then
            local privateState = GFPA.GetPrivateDispelState and GFPA:GetPrivateDispelState(unit)
            if not privateState and GFPA.RefreshPrivateDispelState then
                privateState = GFPA:RefreshPrivateDispelState(unit)
            end
            if privateState and (privateState.auraInstanceID or privateState.slot) then
                hasDispellable = true
                fromPrivateSlots = true
                firstDispellableInstID = privateState.auraInstanceID
            end
        end
    end

    if not hasDispellable then
        overlay:Hide()
        return
    end

    -- Preferred color path: let the client resolve the color from the aura instance.
    if firstDispellableInstID and C_UnitAuras.GetAuraDispelTypeColor then
        local opacity = healerSettings.dispelOverlay.opacity or 0.8
        local curve = GetDispelColorCurve(opacity)
        if curve then
            local cOk, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, firstDispellableInstID, curve)
            if cOk and color then
                SetDispelBorderColorMixin(overlay, color)
                overlay:Show()
                return
            end
        end
    end

    -- Fallback color path: look up the resolved dispel type in the color table.
    local colors = GetDispelColors()
    local fallbackOpacity = healerSettings.dispelOverlay.opacity or 0.8
    if ShowConfiguredDispelOverlay(overlay, colors, firstDispellableType, fallbackOpacity) then
        return
    end

    -- Last-resort fallback: detection succeeded but no type-specific color
    -- could be resolved. For private-slot-only matches, prefer any available
    -- dispel color; otherwise default to Magic blue so the healer still sees
    -- the overlay instead of silently dropping it.
    local fallback = fromPrivateSlots and colors and (colors.Magic or colors.Curse or colors.Disease or colors.Poison)
        or (colors and colors.Magic)
    fallback = fallback or _state.defaultColors.dispelFallback
    SetDispelBorderColor(overlay, fallback[1], fallback[2], fallback[3], fallbackOpacity)
    overlay:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Defensive Indicator
---------------------------------------------------------------------------
-- Growth direction offsets for multi-icon layout
local DEFENSIVE_GROWTH_OFFSETS = {
    RIGHT  = function(size, spacing) return size + spacing, 0 end,
    LEFT   = function(size, spacing) return -(size + spacing), 0 end,
    CENTER = function(size, spacing) return size + spacing, 0 end,
    UP     = function(size, spacing) return 0, size + spacing end,
    DOWN   = function(size, spacing) return 0, -(size + spacing) end,
}

-- Defensive indicator state (scratch tables, classification cache, filter strings)
local _defensive = {
    foundAuras = {},     -- pooled scratch (wipe and reuse)
    seen = {},           -- pooled scratch (wipe and reuse)
    -- Positive-only cache. Negative hits are effectively one-shot because each
    -- auraInstanceID is classified once when it enters the shared aura cache;
    -- storing false for every non-defensive aura just creates fight-long growth.
    cache = {},          -- auraInstanceID → true
    filterBig = nil,     -- pre-cached filter string
    filterExternal = nil,
}

local function AuraMatchesDefensiveClassification(unit, auraInstanceID, classification)
    if not unit or not classification or not auraInstanceID or IsSecretValue(auraInstanceID) then
        return false
    end
    if not C_UnitAuras or not C_UnitAuras.IsAuraFilteredOutByInstanceID then
        return false
    end

    -- Use cached filter strings to avoid per-call string concatenation
    local filterStr
    if AuraUtil and AuraUtil.AuraFilters then
        if classification == AuraUtil.AuraFilters.BigDefensive then
            if not _defensive.filterBig then
                _defensive.filterBig = "HELPFUL|" .. classification
            end
            filterStr = _defensive.filterBig
        elseif classification == AuraUtil.AuraFilters.ExternalDefensive then
            if not _defensive.filterExternal then
                _defensive.filterExternal = "HELPFUL|" .. classification
            end
            filterStr = _defensive.filterExternal
        end
    end
    if not filterStr then
        filterStr = "HELPFUL|" .. classification
    end

    local ok, filteredOut = pcall(
        C_UnitAuras.IsAuraFilteredOutByInstanceID,
        unit,
        auraInstanceID,
        filterStr
    )
    if not ok or IsSecretValue(filteredOut) then
        return false
    end

    return not filteredOut
end

local function IsVerifiedDefensiveAura(unit, auraData)
    if not unit or not auraData then
        return false
    end

    -- Fast path: known spell IDs in the fallback allow-list.
    local spellID = SafeValue(auraData.spellId, nil)
    if spellID and DEFENSIVE_SPELL_IDS[spellID] then
        return true
    end

    -- Fail closed when aura data is obfuscated (common when units are far away).
    local auraInstanceID = auraData.auraInstanceID
    local filters = AuraUtil and AuraUtil.AuraFilters
    if not auraInstanceID or not filters then
        return false
    end

    -- Check cache first
    local cached = _defensive.cache[auraInstanceID]
    if cached then
        return true
    end

    if AuraMatchesDefensiveClassification(unit, auraInstanceID, filters.BigDefensive) then
        _defensive.cache[auraInstanceID] = true
        return true
    end
    if AuraMatchesDefensiveClassification(unit, auraInstanceID, filters.ExternalDefensive) then
        _defensive.cache[auraInstanceID] = true
        return true
    end

    return false
end

-- Exposed so the aura scanner (groupframes_auras.lua) can pre-classify
-- defensives at scan time and stash matching instance IDs on the unit cache.
-- Mirrors the dispel scan-time set pattern — moves the per-aura filter call
-- out of the per-event UpdateDefensiveIndicator hot path.
QUI_GF.IsVerifiedDefensiveAura = IsVerifiedDefensiveAura

_state.maxDefensiveIcons = 5

_state.HideDefensiveIcons = function(frame)
    local icons = frame and frame.defensiveIcons
    if frame and frame._defensiveAuraIDs then
        wipe(frame._defensiveAuraIDs)
    end
    if icons then
        for _, icon in ipairs(icons) do
            icon:Hide()
        end
    end
end

_state.EnsureDefensiveIcons = function(frame, reverseSwipe)
    local icons = frame.defensiveIcons
    local maxIconFrames = _state.maxDefensiveIcons
    if icons and #icons >= maxIconFrames then
        for i = 1, #icons do
            local cd = icons[i].cooldown
            if cd then cd:SetReverse(reverseSwipe) end
        end
        return icons
    end

    if InCombatLockdown() then
        return icons
    end

    if not icons then
        icons = {}
        frame.defensiveIcons = icons
    end

    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1
    for i = #icons + 1, maxIconFrames do
        local defIcon = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        defIcon:SetSize(16, 16)
        defIcon:ClearAllPoints()
        defIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
        defIcon:SetFrameLevel(frame:GetFrameLevel() + 10)

        local defTex = defIcon:CreateTexture(nil, "ARTWORK")
        defTex:SetAllPoints()
        defTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        defIcon.icon = defTex

        defIcon:SetBackdrop(GetCachedBackdrop(nil, "Interface\\Buttons\\WHITE8x8", px))
        defIcon:SetBackdropBorderColor(0, 0.8, 0, 1)

        local defCD = CreateFrame("Cooldown", nil, defIcon, "CooldownFrameTemplate")
        defCD:SetAllPoints(defTex)
        defCD:SetDrawEdge(false)
        defCD:SetDrawSwipe(true)
        defCD:SetHideCountdownNumbers(false)
        defCD:SetReverse(reverseSwipe)
        defIcon.cooldown = defCD

        if defIcon.SetMouseClickEnabled then
            defIcon:SetMouseClickEnabled(false)
        end
        defIcon:EnableMouse(false)

        defIcon:Hide()
        icons[i] = defIcon
    end

    frame.defensiveIcon = icons[1]
    return icons
end

local function UpdateDefensiveIndicator(frame)
    if not frame or not frame.unit then return end

    local isRaid = frame._isRaid
    local healerSettings = GetHealerSettings(isRaid)
    if not healerSettings or not healerSettings.defensiveIndicator
       or not healerSettings.defensiveIndicator.enabled then
        _state.HideDefensiveIcons(frame)
        return
    end

    local unit = frame.unit
    local _, isDeadOrGhost = GetUnitLifeState(unit)
    if not UnitExists(unit) or isDeadOrGhost then
        _state.HideDefensiveIcons(frame)
        return
    end

    local defSettings = healerSettings.defensiveIndicator
    local maxIcons = defSettings.maxIcons or 3
    local reverseSwipe = defSettings.reverseSwipe ~= false
    local defensiveIcons = _state.EnsureDefensiveIcons(frame, reverseSwipe)
    if not defensiveIcons or #defensiveIcons == 0 then return end

    -- Scan-time set fast path: the aura scanner already classified every
    -- helpful aura against BigDefensive + ExternalDefensive and stashed the
    -- matching instance IDs in cache.defensives / cache.defensiveOrder. Walk
    -- the pre-classified order list and resolve each ID through the shared
    -- instance-ID map so this path scales with actual defensives present.
    local foundAuras = _defensive.foundAuras
    local seen = _defensive.seen
    wipe(foundAuras)
    wipe(seen)

    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    if cache and cache.defensiveOrder and cache.buffsByID and #cache.defensiveOrder > 0 then
        local defensiveOrder = cache.defensiveOrder
        local buffsByID = cache.buffsByID
        for i = 1, #defensiveOrder do
            local instID = defensiveOrder[i]
            if not seen[instID] then
                local ad = buffsByID[instID]
                if ad then
                    seen[instID] = true
                    foundAuras[#foundAuras + 1] = ad
                    if #foundAuras >= maxIcons then break end
                end
            end
        end
    end

    -- Layout settings
    local iconSize = defSettings.iconSize or 16
    local position = defSettings.position or "CENTER"
    local offsetX = defSettings.offsetX or 0
    local offsetY = defSettings.offsetY or 0
    local spacing = defSettings.spacing or 2
    local growDir = defSettings.growDirection or "RIGHT"
    local growFn = DEFENSIVE_GROWTH_OFFSETS[growDir] or DEFENSIVE_GROWTH_OFFSETS.RIGHT
    local stepX, stepY = growFn(iconSize, spacing)
    local visibleCount = math_min(#foundAuras, #defensiveIcons)

    -- CENTER: calculate centering offset based on visible count
    local centerOffX = 0
    if growDir == "CENTER" then
        local totalSpan = visibleCount * iconSize + math_max(visibleCount - 1, 0) * spacing
        centerOffX = -totalSpan / 2
    end
    local bottomPad = frame._bottomPad or 0
    local layoutChanged = frame._defensiveIndicatorCount ~= visibleCount
        or frame._defensiveIndicatorIconSize ~= iconSize
        or frame._defensiveIndicatorPosition ~= position
        or frame._defensiveIndicatorOffsetX ~= offsetX
        or frame._defensiveIndicatorOffsetY ~= offsetY
        or frame._defensiveIndicatorSpacing ~= spacing
        or frame._defensiveIndicatorGrowDir ~= growDir
        or frame._defensiveIndicatorBottomPad ~= bottomPad
    frame._defensiveIndicatorCount = visibleCount
    frame._defensiveIndicatorIconSize = iconSize
    frame._defensiveIndicatorPosition = position
    frame._defensiveIndicatorOffsetX = offsetX
    frame._defensiveIndicatorOffsetY = offsetY
    frame._defensiveIndicatorSpacing = spacing
    frame._defensiveIndicatorGrowDir = growDir
    frame._defensiveIndicatorBottomPad = bottomPad

    -- Expose active defensive auraInstanceIDs for buff deduplication
    if not frame._defensiveAuraIDs then frame._defensiveAuraIDs = {} end
    wipe(frame._defensiveAuraIDs)
    for id in pairs(seen) do
        frame._defensiveAuraIDs[id] = true
    end

    for i, defIcon in ipairs(defensiveIcons) do
        local aura = foundAuras[i]
        if aura then
            -- Update icon texture
            if aura.icon and defIcon.icon then
                pcall(defIcon.icon.SetTexture, defIcon.icon, aura.icon)
            end

            -- Update cooldown swipe
            local cd = defIcon.cooldown
            if cd and aura.duration and aura.expirationTime then
                if cd.SetReverse then
                    pcall(cd.SetReverse, cd, reverseSwipe)
                end
                ApplyCooldownFromAura(
                    cd,
                    unit,
                    aura.auraInstanceID,
                    aura.expirationTime,
                    aura.duration,
                    nil,
                    aura.timeMod
                )
            elseif cd then
                cd:Clear()
            end

            -- Position: first icon at anchor, subsequent offset by growth direction
            if layoutChanged then
                defIcon:SetSize(iconSize, iconSize)
                defIcon:ClearAllPoints()
                defIcon:SetPoint(position, frame, position, offsetX + centerOffX + stepX * (i - 1), offsetY + stepY * (i - 1))
                defIcon:SetFrameLevel(frame:GetFrameLevel() + 10)
            end
            defIcon:Show()
        else
            defIcon:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Portrait
---------------------------------------------------------------------------
local function UpdatePortrait(frame)
    if not frame or not frame.unit then return end
    local isRaid = frame._isRaid
    local portraitSettings = GetPortraitSettings(isRaid)

    if not portraitSettings or not portraitSettings.showPortrait then
        if frame.portrait then frame.portrait:Hide() end
        return
    end

    if not frame.portrait or not frame.portraitTexture then return end

    local unit = frame.unit
    if not UnitExists(unit) then
        frame.portrait:Hide()
        return
    end

    pcall(SetPortraitTexture, frame.portraitTexture, unit, true)
    frame.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)

    local isConnected, isDeadOrGhost = GetUnitLifeState(unit)
    frame.portraitTexture:SetDesaturated(isDeadOrGhost or not isConnected)

    frame.portrait:Show()
end


_.InvalidateDispelColors = InvalidateDispelColors
_.ResetDispelColorCurve = function() _dispel.colorCurve = nil end
_.ClearDefensiveCache = function() wipe(_defensive.cache) end
_.UpdateName = UpdateName
_.UpdateRoleIcon = UpdateRoleIcon
_.UpdateReadyCheck = UpdateReadyCheck
_.UpdateResurrection = UpdateResurrection
_.UpdateSummonPending = UpdateSummonPending
_.UpdateThreat = UpdateThreat
_.UpdateTargetMarker = UpdateTargetMarker
_.UpdateLeaderIcon = UpdateLeaderIcon
_.UpdatePhaseIcon = UpdatePhaseIcon
_.UpdateConnection = UpdateConnection
_.UpdateTargetHighlight = UpdateTargetHighlight
_.UpdateDispelOverlay = UpdateDispelOverlay
_.UpdateDefensiveIndicator = UpdateDefensiveIndicator
_.UpdatePortrait = UpdatePortrait

function QUI_GF:UpdateDispelOverlay(frame)
    UpdateDispelOverlay(frame)
end

function QUI_GF:UpdateDefensiveIndicator(frame)
    UpdateDefensiveIndicator(frame)
end
