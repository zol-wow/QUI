--[[
    QUI Group Frames - Aura Indicators
    One tracked aura can drive multiple frame effects at once:
    - icon strip entries
    - anchored aura bars
    - health bar color overrides
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local LSM = ns.LSM
local QUICore = ns.Addon
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local NormalizeAuraIndicatorConfig = Helpers.NormalizeAuraIndicatorConfig
local ApplyCooldownFromAura = Helpers.ApplyCooldownFromAura
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local wipe = wipe
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local GetTime = GetTime
local C_UnitAuras = C_UnitAuras
local math_max = math.max
local math_min = math.min
local table_insert = table.insert
local table_remove = table.remove
local tostring = tostring
local tonumber = tonumber

local QUI_GFI = {}
ns.QUI_GroupFrameIndicators = QUI_GFI

local POOL_SIZE = 60
local iconPool = {}
local barPool = {}
local spellNameCache = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_Ind_iconPool", tbl = iconPool }
    mp[#mp + 1] = { name = "GF_Ind_barPool", tbl = barPool }
    mp[#mp + 1] = { name = "GF_Ind_spellNameCache", tbl = spellNameCache }
end

local _scratchHelpfulAurasByID = {}
local _scratchHarmfulAurasByID = {}
local _scratchHelpfulAuraNames = {}
local _scratchHarmfulAuraNames = {}
local _scratchIconPayloads = {}
local _scratchBarPayloads = {}

-- Pre-allocated payload pool: avoids creating fresh {} per indicator per
-- dispatch.  Payloads hold transient auraData refs that anchor C-side tables
-- in memory — nilling them after render lets the GC collect those tables
-- promptly instead of retaining them until the next dispatch cycle.
local PAYLOAD_POOL_SIZE = 40
local _payloadPool = {}
local _payloadPoolSize = 0

local function AcquirePayload()
    if _payloadPoolSize > 0 then
        local p = _payloadPool[_payloadPoolSize]
        _payloadPool[_payloadPoolSize] = nil
        _payloadPoolSize = _payloadPoolSize - 1
        return p
    end
    return { indicator = nil, auraData = nil, key = nil }
end

local function ReleasePayload(p)
    p.indicator = nil
    p.auraData = nil
    p.key = nil
    if _payloadPoolSize < PAYLOAD_POOL_SIZE then
        _payloadPoolSize = _payloadPoolSize + 1
        _payloadPool[_payloadPoolSize] = p
    end
end

local function ReleasePayloads(arr)
    for i = 1, #arr do
        ReleasePayload(arr[i])
        arr[i] = nil
    end
end

local EMPTY_TABLE = {}
local DEFAULT_HEALTH_COLOR = { 0.2, 0.8, 0.2, 1 }
local AURA_FILTERS = { "HELPFUL", "HARMFUL" }
local HEALTH_TINT_ANIMATION_DEFAULT = "fill"
local HEALTH_TINT_ANIMATION_DURATIONS = {
    instant = 0,
    fill = 0.35,
    fade = 0.25,
    fillFade = 0.35,
    pulse = 0.28,
}

local FILTER_RAID = "PLAYER|HELPFUL|RAID"
local FILTER_RIC = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local FILTER_EXT = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local FILTER_DISP = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"
local FILTER_PLAYER_HELPFUL = "HELPFUL|PLAYER"
local FILTER_PLAYER_HARMFUL = "HARMFUL|PLAYER"
local SECRET_TRACKED_AURAS = {
    [10060] = {
        name = "Power Infusion",
        signature = 9,  -- raid(8) + disp(1)
        filter = "HELPFUL",
        scanLimit = 100,
    },
}

local function ColorsEqual(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    return (a[1] or 0) == (b[1] or 0)
        and (a[2] or 0) == (b[2] or 0)
        and (a[3] or 0) == (b[3] or 0)
        and (a[4] or 1) == (b[4] or 1)
end

local function GetVisualDB(isRaid)
    local db = GetDB()
    if not db then
        return nil
    end
    local vdb = (isRaid and db.raid or db.party) or db
    local ai = vdb and vdb.auraIndicators
    if ai and NormalizeAuraIndicatorConfig then
        NormalizeAuraIndicatorConfig(ai)
    end
    return vdb
end

local function GetFontPath()
    local vdb = GetVisualDB(false)
    local general = vdb and vdb.general
    local fontName = general and general.font or "Quazii"
    return LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
end

local function GetStatusBarTexturePath(isRaid)
    local vdb = GetVisualDB(isRaid)
    local general = vdb and vdb.general
    local textureName = general and general.texture or "Quazii v5"
    return LSM and LSM:Fetch("statusbar", textureName, true) or "Interface\\TargetingFrame\\UI-StatusBar"
end

local function NormalizeHealthTintAnimation(value)
    if value == "instant"
        or value == "fill"
        or value == "fade"
        or value == "fillFade"
        or value == "pulse" then
        return value
    end
    return HEALTH_TINT_ANIMATION_DEFAULT
end

local activeHealthTintAnimations = {}
local activeHealthTintAnimationCount = 0
local healthTintAnimationFrame = CreateFrame("Frame")
healthTintAnimationFrame:Hide()

local function EaseOutCubic(t)
    local inv = 1 - t
    return 1 - (inv * inv * inv)
end

local function UnregisterHealthTintAnimation(overlay)
    if activeHealthTintAnimations[overlay] then
        activeHealthTintAnimations[overlay] = nil
        activeHealthTintAnimationCount = math_max(activeHealthTintAnimationCount - 1, 0)
        if activeHealthTintAnimationCount == 0 then
            healthTintAnimationFrame:Hide()
        end
    end
    if overlay then
        overlay._quiTintAnimating = nil
    end
end

local function RegisterHealthTintAnimation(overlay)
    if not activeHealthTintAnimations[overlay] then
        activeHealthTintAnimations[overlay] = true
        activeHealthTintAnimationCount = activeHealthTintAnimationCount + 1
    end
    overlay._quiTintAnimating = true
    healthTintAnimationFrame:Show()
end

healthTintAnimationFrame:SetScript("OnUpdate", function(_, elapsed)
    for overlay in pairs(activeHealthTintAnimations) do
        if not overlay:IsShown() then
            UnregisterHealthTintAnimation(overlay)
        else
            overlay._quiTintElapsed = (overlay._quiTintElapsed or 0) + elapsed
            local duration = overlay._quiTintDuration or 0
            local progress = duration > 0 and math_min(overlay._quiTintElapsed / duration, 1) or 1
            local eased = EaseOutCubic(progress)
            local value
            local alpha = (overlay._quiTintStartAlpha or 1)
                + ((overlay._quiTintTargetAlpha or 1) - (overlay._quiTintStartAlpha or 1)) * eased

            if overlay._quiTintTweenValue then
                value = (overlay._quiTintStartValue or 0)
                    + ((overlay._quiTintTargetValue or 0) - (overlay._quiTintStartValue or 0)) * eased
                overlay:SetValue(value)
            end

            overlay:SetAlpha(alpha)

            if progress >= 1 then
                if overlay._quiTintTweenValue then
                    overlay:SetValue(overlay._quiTintTargetValue or value)
                end
                overlay:SetAlpha(overlay._quiTintTargetAlpha or alpha)
                UnregisterHealthTintAnimation(overlay)
            end
        end
    end
end)

local function GetOrCreateHealthTintOverlay(frame)
    if not frame or not frame.healthBar then
        return nil
    end

    local overlay = frame._auraIndicatorHealthTintOverlay
    if not overlay then
        overlay = CreateFrame("StatusBar", nil, frame.healthBar)
        overlay:SetAllPoints(frame.healthBar)
        overlay:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
        overlay:SetMinMaxValues(0, 100)
        overlay:SetValue(0)
        overlay:SetAlpha(1)
        overlay:EnableMouse(false)
        overlay:Hide()
        frame._auraIndicatorHealthTintOverlay = overlay
    end

    local texture = frame.healthBar:GetStatusBarTexture()
    overlay:SetStatusBarTexture(texture and texture:GetTexture() or GetStatusBarTexturePath(frame._isRaid))
    overlay:SetOrientation(frame._isVerticalFill and "VERTICAL" or "HORIZONTAL")
    if overlay.SetReverseFill then
        overlay:SetReverseFill(false)
    end
    overlay:SetAllPoints(frame.healthBar)
    overlay:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
    return overlay
end

local function HideHealthTintOverlay(frame)
    local overlay = frame and frame._auraIndicatorHealthTintOverlay
    if not overlay then
        return
    end
    UnregisterHealthTintAnimation(overlay)
    overlay:SetAlpha(1)
    overlay:SetValue(0)
    overlay._quiTintWasShown = nil
    overlay:Hide()
end

local function StartHealthTintAnimation(overlay, mode, targetValue, targetAlpha)
    mode = NormalizeHealthTintAnimation(mode)
    local duration = HEALTH_TINT_ANIMATION_DURATIONS[mode] or HEALTH_TINT_ANIMATION_DURATIONS[HEALTH_TINT_ANIMATION_DEFAULT]
    local nativeInterpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    local canTweenValue = not IsSecretValue(targetValue) and type(targetValue) == "number"

    overlay._quiTintMode = mode
    overlay._quiTintElapsed = 0
    overlay._quiTintDuration = duration
    overlay._quiTintTargetValue = targetValue
    overlay._quiTintTargetAlpha = targetAlpha
    overlay._quiTintTweenValue = nil

    if mode == "instant" or duration <= 0 then
        overlay:SetValue(targetValue)
        overlay:SetAlpha(targetAlpha)
        UnregisterHealthTintAnimation(overlay)
        return
    elseif mode == "fade" then
        overlay:SetValue(targetValue)
        overlay._quiTintStartValue = targetValue
        overlay._quiTintStartAlpha = 0
    elseif mode == "fillFade" then
        overlay:SetValue(0)
        if nativeInterpolation then
            overlay:SetValue(targetValue, nativeInterpolation)
            overlay._quiTintStartValue = targetValue
        elseif canTweenValue then
            overlay._quiTintTweenValue = true
            overlay._quiTintStartValue = 0
        else
            overlay:SetValue(targetValue)
            overlay._quiTintStartValue = targetValue
        end
        overlay._quiTintStartAlpha = 0
    elseif mode == "pulse" then
        overlay:SetValue(targetValue)
        overlay._quiTintStartValue = targetValue
        overlay._quiTintStartAlpha = targetAlpha * 0.35
    else
        overlay:SetAlpha(targetAlpha)
        overlay:SetValue(0)
        if nativeInterpolation then
            overlay:SetValue(targetValue, nativeInterpolation)
            UnregisterHealthTintAnimation(overlay)
            return
        elseif canTweenValue then
            overlay._quiTintTweenValue = true
            overlay._quiTintStartValue = 0
        else
            overlay:SetValue(targetValue)
            UnregisterHealthTintAnimation(overlay)
            return
        end
        overlay._quiTintStartAlpha = targetAlpha
    end

    if overlay._quiTintTweenValue then
        overlay:SetValue(overlay._quiTintStartValue or 0)
    end
    overlay:SetAlpha(overlay._quiTintStartAlpha or targetAlpha)
    RegisterHealthTintAnimation(overlay)
end

local function GetAuraIndicatorSettings(isRaid)
    local vdb = GetVisualDB(isRaid)
    return vdb and vdb.auraIndicators or nil
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

local function AuraMatchesPlayerCast(unit, auraData)
    if not unit or not auraData then
        return false
    end

    local auraInstanceID = SafeValue(auraData.auraInstanceID, nil)
    local helpfulPlayerMatch, harmfulPlayerMatch = nil, nil
    if auraInstanceID then
        helpfulPlayerMatch = GetAuraFilterMatch(unit, auraInstanceID, FILTER_PLAYER_HELPFUL)
        if helpfulPlayerMatch == true then
            return true
        end

        harmfulPlayerMatch = GetAuraFilterMatch(unit, auraInstanceID, FILTER_PLAYER_HARMFUL)
        if harmfulPlayerMatch == true then
            return true
        end

        if helpfulPlayerMatch == false and harmfulPlayerMatch == false then
            return false
        end
    end

    local fromPlayer = SafeValue(auraData.isFromPlayerOrPlayerPet, nil)
    if fromPlayer ~= nil then
        return fromPlayer == true
    end

    local sourceUnit = SafeValue(auraData.sourceUnit, nil)
    if type(sourceUnit) == "string" then
        if sourceUnit == "player" then
            return true
        end
        if UnitIsUnit then
            local ok, isPlayer = pcall(UnitIsUnit, sourceUnit, "player")
            if ok and not IsSecretValue(isPlayer) then
                return isPlayer == true
            end
        end
    end

    local sourceGUID = SafeValue(auraData.sourceGUID, nil)
    if sourceGUID and UnitGUID then
        local playerGUID = UnitGUID("player")
        if playerGUID then
            return sourceGUID == playerGUID
        end
    end

    return true
end

local function AuraMatchesTrackedSpell(auraData, spellID, spellName)
    if not auraData then
        return false
    end

    local auraSpellID = SafeValue(auraData.spellId, nil)
    if auraSpellID and auraSpellID == spellID then
        return true
    end

    if spellName then
        local auraName = SafeValue(auraData.name, nil)
        if auraName and auraName == spellName then
            return true
        end
    end

    return false
end

local function FindTrackedAuraInList(unit, spellID, spellName, auraList, onlyMine)
    if not auraList then
        return nil
    end

    for _, auraData in ipairs(auraList) do
        if AuraMatchesTrackedSpell(auraData, spellID, spellName)
            and (not onlyMine or AuraMatchesPlayerCast(unit, auraData)) then
            return auraData
        end
    end

    return nil
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

local function FindSecretTrackedAura(unit, spellID, helpfulAuras, onlyMine)
    local config = SECRET_TRACKED_AURAS[spellID]
    if not config then
        return nil
    end

    if helpfulAuras then
        for _, helpfulAura in ipairs(helpfulAuras) do
            if IsSecretTrackedAura(unit, helpfulAura, config)
                and (not onlyMine or AuraMatchesPlayerCast(unit, helpfulAura)) then
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
                if IsSecretTrackedAura(unit, auraData, config)
                    and (not onlyMine or AuraMatchesPlayerCast(unit, auraData)) then
                    return auraData
                end
            end
        end
    end

    return nil
end

local function FindTrackedAuraData(
    unit,
    spellID,
    helpfulByID,
    helpfulByName,
    harmfulByID,
    harmfulByName,
    helpfulAuras,
    harmfulAuras,
    onlyMine
)
    local function CandidateMatches(auraData)
        if not auraData then
            return false
        end
        return not onlyMine or AuraMatchesPlayerCast(unit, auraData)
    end

    local auraData = helpfulByID and helpfulByID[spellID]
    if CandidateMatches(auraData) then
        return auraData
    end

    auraData = harmfulByID and harmfulByID[spellID]
    if CandidateMatches(auraData) then
        return auraData
    end
    local secretAura = FindSecretTrackedAura(unit, spellID, helpfulAuras, onlyMine)
    if secretAura then
        return secretAura
    end

    local spellName = GetTrackedSpellName(spellID)
    if onlyMine then
        auraData = FindTrackedAuraInList(unit, spellID, spellName, helpfulAuras, true)
        if auraData then
            return auraData
        end

        auraData = FindTrackedAuraInList(unit, spellID, spellName, harmfulAuras, true)
        if auraData then
            return auraData
        end
    end

    if not spellName then
        return nil
    end

    auraData = helpfulByName and helpfulByName[spellName]
    if CandidateMatches(auraData) then
        return auraData
    end

    auraData = harmfulByName and harmfulByName[spellName]
    if CandidateMatches(auraData) then
        return auraData
    end

    if not InCombatLockdown() and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local okHelpful, helpfulAura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HELPFUL")
        if okHelpful and helpfulAura and CandidateMatches(helpfulAura) then
            return helpfulAura
        end

        local okHarmful, harmfulAura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, "HARMFUL")
        if okHarmful and harmfulAura and CandidateMatches(harmfulAura) then
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

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    frame.cooldown = cd

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

local function UpdateIconData(icon, unit, auraData)
    if icon.icon and auraData.icon then
        icon.icon:SetTexture(auraData.icon)
    end

    if icon.cooldown and auraData then
        if icon.cooldown.SetDrawSwipe then
            pcall(icon.cooldown.SetDrawSwipe, icon.cooldown, icon._hideSwipe ~= true)
        end
        if icon.cooldown.SetReverse then
            pcall(icon.cooldown.SetReverse, icon.cooldown, icon._reverseSwipe == true)
        end
        local dur = auraData.duration
        local expTime = auraData.expirationTime
        if dur and expTime then
            ApplyCooldownFromAura(icon.cooldown, unit, auraData.auraInstanceID, expTime, dur)
        else
            icon.cooldown:Clear()
        end
    end

    if icon.stackText and auraData then
        local stacks = SafeToNumber(auraData.applications, 0)
        icon.stackText:SetText(stacks > 1 and stacks or "")
    end
end

local function CreateBarIndicator(parent)
    local bar = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.28)
    bar.background = bg

    bar:Hide()
    return bar
end

local function AcquireBar(parent)
    local item = table_remove(barPool)
    if item then
        item:SetParent(parent)
        item:ClearAllPoints()
        return item
    end
    return CreateBarIndicator(parent)
end

local UnregisterBarTimer

local function ReleaseBar(item)
    item:Hide()
    item:ClearAllPoints()
    if UnregisterBarTimer then
        UnregisterBarTimer(item)
    end
    item._elapsed = 0
    item._indicator = nil
    item._auraData = nil
    item._unit = nil
    item._layoutOrientation = nil
    item._layoutWidth = nil
    item._layoutHeight = nil
    item._layoutAnchor = nil
    item._layoutTexturePath = nil
    item:SetMinMaxValues(0, 1)
    item:SetValue(1)
    if item.background then
        item.background:SetColorTexture(0, 0, 0, 0.28)
    end
    item:SetBackdrop(nil)
    if #barPool < POOL_SIZE then
        table_insert(barPool, item)
    end
end

local DEFAULT_BORDER_COLOR = { 0, 0, 0, 1 }

local function GetBarDisplayColor(indicator, remaining)
    local color = indicator.color or DEFAULT_HEALTH_COLOR
    local threshold = SafeToNumber(indicator.lowTimeThreshold, 0)
    if remaining and threshold > 0 and remaining <= threshold then
        local lowColor = indicator.lowTimeColor
        if type(lowColor) == "table" then
            return lowColor
        end
    end
    return color
end

local function ApplyBarColor(bar, indicator, remaining)
    local color = GetBarDisplayColor(indicator, remaining)
    local r = color[1] or 0.2
    local g = color[2] or 0.8
    local b = color[3] or 0.2
    local a = color[4] or 1
    bar:SetStatusBarColor(r, g, b, a)
    if bar.background then
        local bg = indicator.backgroundColor
        if type(bg) == "table" then
            bar.background:SetColorTexture(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.18)
        else
            bar.background:SetColorTexture(r, g, b, 0.18)
        end
    end
end

local function UpdateBarProgress(bar)
    local auraData = bar._auraData
    local indicator = bar._indicator
    if not auraData or not indicator then
        return
    end

    local duration = SafeToNumber(auraData.duration, 0)
    local expirationTime = SafeToNumber(auraData.expirationTime, 0)
    local remaining = nil
    local pct = 1
    if duration > 0 and expirationTime > 0 and not IsSecretValue(auraData.duration) and not IsSecretValue(auraData.expirationTime) then
        remaining = math_max(expirationTime - GetTime(), 0)
        pct = math_min(math_max(remaining / duration, 0), 1)
    end

    bar:SetValue(pct)
    ApplyBarColor(bar, indicator, remaining)
end

local activeTimerBars = {}
local activeTimerBarCount = 0
local barTimerFrame = CreateFrame("Frame")
barTimerFrame:Hide()

local function BarTimerOnUpdate(self, elapsed)
    self._elapsed = (self._elapsed or 0) + elapsed
    if self._elapsed < 0.08 then
        return
    end
    self._elapsed = 0
    for bar in pairs(activeTimerBars) do
        if bar:IsShown() then
            UpdateBarProgress(bar)
        else
            activeTimerBars[bar] = nil
            activeTimerBarCount = math_max(activeTimerBarCount - 1, 0)
        end
    end
    if activeTimerBarCount == 0 then
        self:Hide()
    end
end

barTimerFrame:SetScript("OnUpdate", BarTimerOnUpdate)

local function RegisterBarTimer(bar)
    if not activeTimerBars[bar] then
        activeTimerBars[bar] = true
        activeTimerBarCount = activeTimerBarCount + 1
    end
    barTimerFrame:Show()
end

UnregisterBarTimer = function(bar)
    if activeTimerBars[bar] then
        activeTimerBars[bar] = nil
        activeTimerBarCount = math_max(activeTimerBarCount - 1, 0)
        if activeTimerBarCount == 0 then
            barTimerFrame:Hide()
        end
    end
end

local function ConfigureBarIndicator(bar, frame, auraData, indicator)
    local orientation = indicator.orientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL"
    local thickness = math_max(1, SafeToNumber(indicator.thickness, 4))
    local length = math_max(1, SafeToNumber(indicator.length, 40))
    local matchFrameSize = indicator.matchFrameSize == true
    local frameWidth = math_max(1, (frame:GetWidth() or 1) - 2)
    local frameHeight = math_max(1, (frame:GetHeight() or 1) - ((frame._bottomPad or 0) * 0.5) - 2)
    local width = orientation == "HORIZONTAL" and (matchFrameSize and frameWidth or length) or thickness
    local height = orientation == "VERTICAL" and (matchFrameSize and frameHeight or length) or thickness
    local anchor = indicator.anchor or "BOTTOM"
    local offsetX = SafeToNumber(indicator.offsetX, 0)
    local offsetY = SafeToNumber(indicator.offsetY, 0)

    local borderSize = math_max(1, SafeToNumber(indicator.borderSize, 1))
    local borderColor = indicator.borderColor or DEFAULT_BORDER_COLOR
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(bar) or 1
    local texturePath = GetStatusBarTexturePath(frame._isRaid)
    local bottomPad = frame._bottomPad or 0
    local hideBorder = indicator.hideBorder == true
    local br, bg, bb, ba = borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] or 1
    local layoutChanged = bar._layoutOrientation ~= orientation
        or bar._layoutWidth ~= width
        or bar._layoutHeight ~= height
        or bar._layoutAnchor ~= anchor
        or bar._layoutOffsetX ~= offsetX
        or bar._layoutOffsetY ~= offsetY
        or bar._layoutBottomPad ~= bottomPad
        or bar._layoutBorderSize ~= borderSize
        or bar._layoutHideBorder ~= hideBorder
        or bar._layoutTexturePath ~= texturePath
        or bar._layoutBorderR ~= br
        or bar._layoutBorderG ~= bg
        or bar._layoutBorderB ~= bb
        or bar._layoutBorderA ~= ba

    if layoutChanged then
        bar._layoutOrientation = orientation
        bar._layoutWidth = width
        bar._layoutHeight = height
        bar._layoutAnchor = anchor
        bar._layoutOffsetX = offsetX
        bar._layoutOffsetY = offsetY
        bar._layoutBottomPad = bottomPad
        bar._layoutBorderSize = borderSize
        bar._layoutHideBorder = hideBorder
        bar._layoutTexturePath = texturePath
        bar._layoutBorderR, bar._layoutBorderG, bar._layoutBorderB, bar._layoutBorderA = br, bg, bb, ba
        bar:ClearAllPoints()
        if anchor:find("BOTTOM") then
            offsetY = offsetY + bottomPad
        end
        bar:SetPoint(anchor, frame, anchor, offsetX, offsetY)
        bar:SetSize(width, height)
        bar:SetOrientation(orientation)
        bar:SetStatusBarTexture(texturePath)

        if hideBorder then
            bar:SetBackdrop(nil)
        else
            bar:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = borderSize * px,
            })
            bar:SetBackdropBorderColor(br, bg, bb, ba)
        end
    end

    bar._unit = frame.unit
    bar._auraData = auraData
    bar._indicator = indicator
    bar._elapsed = 0
    UpdateBarProgress(bar)

    local duration = SafeToNumber(auraData.duration, 0)
    local expirationTime = SafeToNumber(auraData.expirationTime, 0)
    if duration > 0 and expirationTime > 0 and not IsSecretValue(auraData.duration) and not IsSecretValue(auraData.expirationTime) then
        RegisterBarTimer(bar)
    else
        UnregisterBarTimer(bar)
    end
end

local frameIndicatorState = Helpers.CreateStateTable()

local function GetIndicatorState(frame)
    local state = frameIndicatorState[frame]
    if not state then
        state = {
            icons = {},
            bars = {},
            iconContainer = nil,
        }
        frameIndicatorState[frame] = state
    end
    return state
end

local function EnsureIconContainer(frame)
    local state = GetIndicatorState(frame)
    if state.iconContainer then
        return state.iconContainer
    end

    local container = CreateFrame("Frame", nil, frame)
    container:SetSize(1, 1)
    container:SetFrameLevel(frame:GetFrameLevel() + 8)
    state.iconContainer = container
    return container
end

local function PositionIconContainer(frame, ai)
    local state = GetIndicatorState(frame)
    local container = state.iconContainer
    if not container then
        return
    end

    local anchor = ai.anchor or "TOPLEFT"
    local offX = ai.anchorOffsetX or 0
    local offY = ai.anchorOffsetY or 0
    local bottomPad = frame._bottomPad or 0
    if state.iconContainerAnchor == anchor
        and state.iconContainerOffX == offX
        and state.iconContainerOffY == offY
        and state.iconContainerBottomPad == bottomPad then
        return
    end
    state.iconContainerAnchor = anchor
    state.iconContainerOffX = offX
    state.iconContainerOffY = offY
    state.iconContainerBottomPad = bottomPad

    container:ClearAllPoints()
    if anchor:find("BOTTOM") then
        offY = offY + bottomPad
    end
    container:SetPoint(anchor, frame, anchor, offX, offY)
end

local function SetHealthBarOverride(frame, indicator, auraData)
    local color = indicator and indicator.color
    local animation = indicator and NormalizeHealthTintAnimation(indicator.animation)
    local auraKey = auraData and (SafeValue(auraData.auraInstanceID, nil) or SafeValue(auraData.spellId, nil))
    local changed = not ColorsEqual(frame._auraIndicatorHealthTintColor, color)
        or frame._auraIndicatorHealthTintAnimation ~= animation
        or frame._auraIndicatorHealthTintAuraKey ~= auraKey
    if not changed then
        return
    end

    frame._auraIndicatorHealthTintColor = color
    frame._auraIndicatorHealthTintAnimation = animation
    frame._auraIndicatorHealthTintAuraKey = auraKey
    frame._auraIndicatorHealthTintPendingStart = color ~= nil
    if not color then
        HideHealthTintOverlay(frame)
    end

    local GF = ns.QUI_GroupFrames
    if GF and GF.RefreshHealth then
        GF:RefreshHealth(frame)
    end
end

function QUI_GFI:SyncHealthBarTint(frame, healthPct, canShow)
    if not frame then
        return
    end

    local color = frame._auraIndicatorHealthTintColor
    if not color or canShow == false then
        HideHealthTintOverlay(frame)
        return
    end

    local overlay = GetOrCreateHealthTintOverlay(frame)
    if not overlay then
        return
    end

    local r = color[1] or 0.2
    local g = color[2] or 0.8
    local b = color[3] or 0.2
    local a = color[4] or 1
    local targetValue = healthPct or 0

    overlay:SetStatusBarColor(r, g, b, a)
    overlay:Show()

    if frame._auraIndicatorHealthTintPendingStart or not overlay._quiTintWasShown then
        frame._auraIndicatorHealthTintPendingStart = nil
        overlay._quiTintWasShown = true
        StartHealthTintAnimation(overlay, frame._auraIndicatorHealthTintAnimation, targetValue, 1)
    elseif overlay._quiTintAnimating then
        if overlay._quiTintTweenValue and not IsSecretValue(targetValue) and type(targetValue) == "number" then
            overlay._quiTintTargetValue = targetValue
        else
            overlay._quiTintTweenValue = nil
            overlay._quiTintTargetValue = targetValue
            overlay:SetValue(targetValue)
        end
        overlay._quiTintTargetAlpha = 1
    else
        overlay:SetValue(targetValue)
        overlay:SetAlpha(1)
    end
end

local function ClearIndicators(frame)
    local state = frameIndicatorState[frame]
    if frame and frame._indicatorAuraIDs then
        wipe(frame._indicatorAuraIDs)
    end
    if frame and frame._auraIndicatorHealthTintColor then
        SetHealthBarOverride(frame, nil, nil)
    end
    if not state then
        return
    end

    for _, icon in ipairs(state.icons) do
        ReleaseIcon(icon)
    end
    wipe(state.icons)

    for _, bar in ipairs(state.bars) do
        ReleaseBar(bar)
    end
    wipe(state.bars)

    if state.iconContainer then
        state.iconContainer:Hide()
    end
end

local function BuildActiveAuraLookup(unit)
    local helpfulByID = _scratchHelpfulAurasByID
    local harmfulByID = _scratchHarmfulAurasByID
    local helpfulByName = _scratchHelpfulAuraNames
    local harmfulByName = _scratchHarmfulAuraNames
    wipe(helpfulByID)
    wipe(harmfulByID)
    wipe(helpfulByName)
    wipe(harmfulByName)
    local helpfulAuras = nil
    local harmfulAuras = nil

    local GFA = ns.QUI_GroupFrameAuras
    local cache = GFA and GFA.unitAuraCache and GFA.unitAuraCache[unit]
    if cache and cache.hasFullScan then
        helpfulAuras = cache.helpful
        harmfulAuras = cache.harmful
        return
            cache.helpfulBySpellID or helpfulByID,
            cache.helpfulByName or helpfulByName,
            cache.harmfulBySpellID or harmfulByID,
            cache.harmfulByName or harmfulByName,
            helpfulAuras,
            harmfulAuras
    elseif not InCombatLockdown() and C_UnitAuras and C_UnitAuras.GetUnitAuras then
        -- Fallback: shared cache missing (should not happen in normal dispatch).
        -- Skip in combat to avoid C-side table allocations that overwhelm the GC.
        for _, filter in ipairs(AURA_FILTERS) do
            local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, filter, 40)
            if ok and auras then
                if filter == "HELPFUL" then
                    helpfulAuras = auras
                    for _, auraData in ipairs(auras) do
                        local spellID = SafeValue(auraData.spellId, nil)
                        if spellID then helpfulByID[spellID] = auraData end
                        local spellName = SafeValue(auraData.name, nil)
                        if spellName then helpfulByName[spellName] = auraData end
                    end
                else
                    harmfulAuras = auras
                    for _, auraData in ipairs(auras) do
                        local spellID = SafeValue(auraData.spellId, nil)
                        if spellID then harmfulByID[spellID] = auraData end
                        local spellName = SafeValue(auraData.name, nil)
                        if spellName then harmfulByName[spellName] = auraData end
                    end
                end
            end
        end
    end

    return helpfulByID, helpfulByName, harmfulByID, harmfulByName, helpfulAuras, harmfulAuras
end

local function RenderIconIndicators(frame, ai, iconPayloads)
    local state = GetIndicatorState(frame)

    if #iconPayloads == 0 then
        for _, icon in ipairs(state.icons) do
            ReleaseIcon(icon)
        end
        wipe(state.icons)
        state.iconCount = nil
        state.iconSize = nil
        state.iconGrowDir = nil
        state.iconSpacing = nil
        state.iconAnchor = nil
        state.iconHideSwipe = nil
        state.iconReverseSwipe = nil
        if state.iconContainer then
            state.iconContainer:Hide()
        end
        ReleasePayloads(iconPayloads)
        return
    end

    local container = EnsureIconContainer(frame)
    local iconSize = ai.iconSize or 14
    local growDir = ai.growDirection or "RIGHT"
    local spacing = ai.spacing or 2
    local maxIcons = ai.maxIndicators or 5
    local anchor = ai.anchor or "TOPLEFT"
    local count = math_min(#iconPayloads, maxIcons)
    local hideSwipe = ai.hideSwipe == true
    local reverseSwipe = ai.reverseSwipe == true
    local layoutChanged = state.iconCount ~= count
        or state.iconSize ~= iconSize
        or state.iconGrowDir ~= growDir
        or state.iconSpacing ~= spacing
        or state.iconAnchor ~= anchor
        or state.iconHideSwipe ~= hideSwipe
        or state.iconReverseSwipe ~= reverseSwipe
    state.iconCount = count
    state.iconSize = iconSize
    state.iconGrowDir = growDir
    state.iconSpacing = spacing
    state.iconAnchor = anchor
    state.iconHideSwipe = hideSwipe
    state.iconReverseSwipe = reverseSwipe

    PositionIconContainer(frame, ai)
    container:Show()

    for idx = 1, count do
        local payload = iconPayloads[idx]
        local icon = state.icons[idx]
        if not icon then
            icon = AcquireIcon(container)
            state.icons[idx] = icon
            layoutChanged = true
        end
        icon:SetSize(iconSize, iconSize)
        icon._hideSwipe = hideSwipe
        icon._reverseSwipe = reverseSwipe

        if layoutChanged then
            icon:ClearAllPoints()

            local vertPart = anchor:find("TOP") and "TOP" or (anchor:find("BOTTOM") and "BOTTOM" or "")
            local firstHoriz = growDir == "LEFT" and "RIGHT" or "LEFT"
            local firstAnchor = vertPart .. firstHoriz

            if idx == 1 then
                icon:SetPoint(firstAnchor, container, firstAnchor, 0, 0)
            else
                local prev = state.icons[idx - 1]
                if growDir == "LEFT" then
                    icon:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
                else
                    icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                end
            end
        end

        UpdateIconData(icon, frame.unit, payload.auraData)
        icon:Show()
    end

    for idx = #state.icons, count + 1, -1 do
        ReleaseIcon(state.icons[idx])
        state.icons[idx] = nil
    end

    if layoutChanged and growDir == "CENTER" and count > 0 then
        local totalSpan = count * iconSize + math_max(count - 1, 0) * spacing
        local startX = -totalSpan / 2
        local vertPart2 = anchor:find("TOP") and "TOP" or (anchor:find("BOTTOM") and "BOTTOM" or "")
        local iconPoint = vertPart2 == "" and "LEFT" or (vertPart2 .. "LEFT")
        for idx = 1, count do
            local icon = state.icons[idx]
            icon:ClearAllPoints()
            icon:SetPoint(iconPoint, container, anchor, startX + (idx - 1) * (iconSize + spacing), 0)
        end
    end

    -- Release payloads back to pool — breaks auraData reference chain
    ReleasePayloads(iconPayloads)
end

local function RenderBarIndicators(frame, barPayloads)
    local state = GetIndicatorState(frame)

    for idx, payload in ipairs(barPayloads) do
        local bar = state.bars[idx]
        if not bar then
            bar = AcquireBar(frame)
            state.bars[idx] = bar
        end
        bar:SetFrameLevel(frame:GetFrameLevel() + 9)
        ConfigureBarIndicator(bar, frame, payload.auraData, payload.indicator)
        bar:Show()
    end

    for idx = #state.bars, #barPayloads + 1, -1 do
        ReleaseBar(state.bars[idx])
        state.bars[idx] = nil
    end

    -- Release payloads back to pool — breaks auraData reference chain
    ReleasePayloads(barPayloads)
end

local function UpdateFrameIndicators(frame)
    if not frame or not frame.unit then
        return
    end

    local ai = GetAuraIndicatorSettings(frame._isRaid)
    if not ai or ai.enabled == false then
        ClearIndicators(frame)
        return
    end

    local entries = ai.entries
    if type(entries) ~= "table" or #entries == 0 then
        ClearIndicators(frame)
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        ClearIndicators(frame)
        return
    end

    local helpfulByID, helpfulByName, harmfulByID, harmfulByName, helpfulAuras, harmfulAuras = BuildActiveAuraLookup(unit)
    local iconPayloads = _scratchIconPayloads
    local barPayloads = _scratchBarPayloads
    wipe(iconPayloads)
    wipe(barPayloads)

    if not frame._indicatorAuraIDs then
        frame._indicatorAuraIDs = {}
    end
    wipe(frame._indicatorAuraIDs)

    local defIDs = frame._defensiveAuraIDs
    local healthIndicator = nil
    local healthAuraData = nil

    for _, entry in ipairs(entries) do
        if entry.enabled ~= false and entry.spellID then
            local auraData = FindTrackedAuraData(
                unit,
                entry.spellID,
                helpfulByID,
                helpfulByName,
                harmfulByID,
                harmfulByName,
                helpfulAuras,
                harmfulAuras,
                entry.onlyMine == true
            )
            if auraData then
                local auraInstanceID = auraData.auraInstanceID
                if auraInstanceID then
                    frame._indicatorAuraIDs[auraInstanceID] = true
                end

                for _, indicator in ipairs(entry.indicators or EMPTY_TABLE) do
                    if indicator.enabled ~= false then
                        if indicator.type == "icon" then
                            if not (defIDs and auraInstanceID and defIDs[auraInstanceID]) then
                                local p = AcquirePayload()
                                p.indicator = indicator
                                p.auraData = auraData
                                iconPayloads[#iconPayloads + 1] = p
                            end
                        elseif indicator.type == "bar" then
                            local p = AcquirePayload()
                            p.indicator = indicator
                            p.auraData = auraData
                            barPayloads[#barPayloads + 1] = p
                        elseif indicator.type == "healthBarColor" and not healthIndicator then
                            healthIndicator = indicator
                            healthAuraData = auraData
                        end
                    end
                end
            end
        end
    end

    RenderIconIndicators(frame, ai, iconPayloads)
    RenderBarIndicators(frame, barPayloads)
    SetHealthBarOverride(frame, healthIndicator, healthAuraData)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function()
    -- Spec change: evict spell name cache (spell roster changes per spec)
    wipe(spellNameCache)
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then
        return
    end
    QUI_GFI:RefreshAll()
end)

function QUI_GFI:RefreshAll()
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.initialized then
        return
    end

    for _, list in pairs(GF.unitFrameMap) do
        for i = 1, #list do
            local frame = list[i]
            if frame and frame:IsShown() then
                UpdateFrameIndicators(frame)
            end
        end
    end
end

function QUI_GFI:RefreshFrame(frame)
    UpdateFrameIndicators(frame)
end

ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "GF_Indicators", frame = eventFrame }
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "GF_IndicatorBars", frame = barTimerFrame, scriptType = "OnUpdate" }
ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "GF_HealthTintAnims", frame = healthTintAnimationFrame, scriptType = "OnUpdate" }
