--[[ QUI Group Frames - Health Updates ]]
local ADDON_NAME, ns = ...
local QUI_GF = ns.QUI_GroupFrames
if not QUI_GF then return end
local _ = QUI_GF._
if not _ then return end

local Helpers = _.Helpers
local IsSecretValue = _.IsSecretValue
local SafeToNumber = _.SafeToNumber
local _state = _.state
local COLORS = _.COLORS
local RAID_CLASS_COLORS = _.RAID_CLASS_COLORS
local GetGeneralSettings = _.GetGeneralSettings
local GetHealthSettings = _.GetHealthSettings
local GetVisualDB = _.GetVisualDB
local GetUnitLifeState = _.GetUnitLifeState
local SetBackdropFillColor = _.SetBackdropFillColor
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitHealthMissing = UnitHealthMissing
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local UnitClass = UnitClass
local GetTime = GetTime
local pcall = pcall
local type = type
local CreateUnitHealPredictionCalculator = CreateUnitHealPredictionCalculator
local UpdateDarkModeVisuals

local function GetHealthPct(unit)
    -- C-side UnitHealthPercent handles secret values natively — no pcall needed
    -- Returns 0-100 via CurveConstants.ScaleTo100 (matches QUI pattern)
    return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
end

---------------------------------------------------------------------------
-- HELPERS: Group size + dimensions
---------------------------------------------------------------------------

local function GetHealthBarColor(unit, isRaid)
    local general = GetGeneralSettings(isRaid)
    if general and general.darkMode then
        local c = general.darkModeHealthColor or _state.defaultColors.darkHealth
        return c[1], c[2], c[3], c[4] or 1
    end

    if general and general.useClassColor ~= false then
        local _, class = UnitClass(unit)
        if class then
            local cc = RAID_CLASS_COLORS[class]
            if cc then
                return cc.r, cc.g, cc.b, 1
            end
        end
    end

    return 0.2, 0.8, 0.2, 1 -- Fallback green
end

---------------------------------------------------------------------------
-- HELPERS: Health text display modes
---------------------------------------------------------------------------
local DISPLAY = {}

DISPLAY.percent = function(text, unit, _settings, _abbr, pctFmt)
    local pct = GetHealthPct(unit)
    return pcall(text.SetFormattedText, text, pctFmt, pct)
end

DISPLAY.absolute = function(text, unit, _settings, abbr)
    local hp = UnitHealth(unit, true)
    if abbr then
        return pcall(text.SetText, text, abbr(hp))
    end
    return pcall(text.SetFormattedText, text, "%s", hp)
end

DISPLAY.combined = function(text, unit, settings, abbr)
    local hp = UnitHealth(unit, true)
    local pct = GetHealthPct(unit)
    local fmt = settings.hideHealthPercentSymbol and "%s | %.0f" or "%s | %.0f%%"
    if abbr then
        return pcall(text.SetFormattedText, text, fmt, abbr(hp), pct)
    end
    return pcall(text.SetFormattedText, text, fmt, hp, pct)
end
DISPLAY.both = DISPLAY.combined

DISPLAY.deficit = function(text, unit, _settings, abbr)
    local miss = UnitHealthMissing(unit, true)
    if C_StringUtil and C_StringUtil.TruncateWhenZero and C_StringUtil.WrapString then
        local truncated = C_StringUtil.TruncateWhenZero(miss)
        local result = C_StringUtil.WrapString(truncated, "-")
        return pcall(text.SetText, text, result)
    elseif abbr then
        return pcall(text.SetFormattedText, text, "-%s", abbr(miss))
    end
    return pcall(text.SetFormattedText, text, "-%s", miss)
end

_.HealthTextDisplay = DISPLAY

local function UpdateHealth(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        if frame.healthBar then frame.healthBar:SetValue(0) end
        local GFI = ns.QUI_GroupFrameIndicators
        if GFI and GFI.SyncHealthBarTint then
            GFI:SyncHealthBarTint(frame, 0, false)
        end
        if frame.healthText then frame.healthText:SetText("") end
        return
    end

    -- BackdropTemplate-backed frames can lose their cached tint when the client
    -- rebuilds backdrop internals. Re-apply our configured backdrop/alpha here
    -- so frequent health updates restore the intended colors without waiting for
    -- a full frame refresh.
    UpdateDarkModeVisuals(frame)

    local isConnected, isDeadOrGhost, isGhost = GetUnitLifeState(unit)

    -- Health bar value — use percentage-based approach
    -- UnitHealthPercent returns 0-100 via CurveConstants.ScaleTo100, C-side handles secrets
    -- SetMinMaxValues(0, 100) is set once at frame creation (DecorateGroupFrame) — never changes.
    if frame.healthBar then
        local healthPct = 0
        if isDeadOrGhost then
            frame.healthBar:SetValue(0)
        else
            healthPct = GetHealthPct(unit)
            frame.healthBar:SetValue(healthPct)
        end

        -- Color (dirty-checked: skip SetStatusBarColor when unchanged)
        local r, g, b, a
        if not isConnected then
            r, g, b, a = COLORS.OFFLINE[1], COLORS.OFFLINE[2], COLORS.OFFLINE[3], COLORS.OFFLINE[4]
        elseif isDeadOrGhost then
            r, g, b, a = COLORS.DEAD[1], COLORS.DEAD[2], COLORS.DEAD[3], COLORS.DEAD[4]
        else
            r, g, b, a = GetHealthBarColor(unit, frame._isRaid)
        end
        if r ~= frame._lastHealthColorR
            or g ~= frame._lastHealthColorG
            or b ~= frame._lastHealthColorB
            or a ~= frame._lastHealthColorA
        then
            frame._lastHealthColorR = r
            frame._lastHealthColorG = g
            frame._lastHealthColorB = b
            frame._lastHealthColorA = a
            frame.healthBar:SetStatusBarColor(r, g, b, a)
        end

        local GFI = ns.QUI_GroupFrameIndicators
        if GFI and GFI.SyncHealthBarTint then
            GFI:SyncHealthBarTint(frame, healthPct, isConnected and not isDeadOrGhost)
        end
    end

    -- Centered status text overlay for dead/offline
    if frame.statusText then
        if not isConnected then
            frame.statusText:SetText("OFFLINE")
            frame.statusText:SetTextColor(COLORS.OFFLINE[1], COLORS.OFFLINE[2], COLORS.OFFLINE[3])
            frame.statusText:Show()
        elseif isDeadOrGhost then
            frame.statusText:SetText(isGhost and "GHOST" or "DEAD")
            frame.statusText:SetTextColor(COLORS.DEAD[1], COLORS.DEAD[2], COLORS.DEAD[3])
            frame.statusText:Show()
            -- Dim the frame slightly for dead units (offline dimming handled in UpdateConnection)
            frame:SetAlpha(0.65)
        else
            frame.statusText:Hide()
        end
    end

    -- Health text — use SetFormattedText (C-side) which handles secret values natively.
    -- pcall wraps each call so a transient secret-conversion failure on a single
    -- unit doesn't bail the rest of the per-frame update path.
    local isRaid = frame._isRaid
    local healthSettings = GetHealthSettings(isRaid)
    if frame.healthText and healthSettings and healthSettings.showHealthText ~= false then
        if not isConnected then
            frame.healthText:SetText("")
        elseif isDeadOrGhost then
            frame.healthText:SetText("")
        else
            local style = healthSettings.healthDisplayStyle or "percent"
            local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
            local pctFmt = healthSettings.hideHealthPercentSymbol and "%.0f" or "%.0f%%"
            local display = DISPLAY[style] or DISPLAY.percent
            local ok = display(frame.healthText, unit, healthSettings, abbr, pctFmt)
            if not ok then
                frame.healthText:SetText("")
            end
            local tc = healthSettings.healthTextColor or COLORS.WHITE
            frame.healthText:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
        end
    elseif frame.healthText then
        frame.healthText:SetText("")
    end
end

---------------------------------------------------------------------------
-- UPDATE: Power
---------------------------------------------------------------------------

local function UpdateAbsorbs(frame, _unit, _maxHP)
    if not frame or not frame.absorbBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.absorbs or vdb.absorbs.enabled == false then
        frame.absorbBar:Hide()
        return
    end

    local unit = _unit or frame.unit
    if not unit then return end

    -- When called standalone (UNIT_ABSORB_AMOUNT_CHANGED), do our own guards.
    if not _unit then
        local _, isDeadOrGhost = GetUnitLifeState(unit)
        if not UnitExists(unit) or isDeadOrGhost then
            frame.absorbBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local absorbAmount = UnitGetTotalAbsorbs(unit)

    -- Hide explicit zero absorbs. Some clients/textures can keep drawing a
    -- visible reverse-filled StatusBar at value 0; secret values still pass
    -- directly to C-side APIs below.
    if not absorbAmount then
        frame.absorbBar:Hide()
        return
    end
    if not IsSecretValue(absorbAmount) and SafeToNumber(absorbAmount, 0) <= 0 then
        frame.absorbBar:SetValue(0)
        frame.absorbBar:Hide()
        return
    end

    -- Geometry is set up at frame creation (SetFrameLevel, SetAllPoints,
    -- SetReverseFill, SetOrientation).  Only redo when orientation changes.
    if frame._absorbVertical ~= frame._isVerticalFill then
        frame.absorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
        frame.absorbBar:ClearAllPoints()
        frame.absorbBar:SetAllPoints(frame.healthBar)
        frame.absorbBar:SetReverseFill(true)
        frame.absorbBar:SetOrientation(frame._isVerticalFill and "VERTICAL" or "HORIZONTAL")
        frame._absorbVertical = frame._isVerticalFill
    end

    -- C-side SetMinMaxValues/SetValue handle secret values natively.
    -- Always call — maxHP may be a secret value (combat), so Lua-side ~= is forbidden.
    frame.absorbBar:SetMinMaxValues(0, maxHP)
    frame.absorbBar:SetValue(absorbAmount)

    -- Color (dirty-checked: settings-driven or class-based, both stable per event)
    local aa = vdb.absorbs.opacity or 0.3
    local ar, ag, ab
    if vdb.absorbs.useClassColor then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            ar, ag, ab = cc.r, cc.g, cc.b
        else
            ar, ag, ab = 1, 1, 1
        end
    else
        local ac = vdb.absorbs.color or COLORS.WHITE
        ar, ag, ab = ac[1], ac[2], ac[3]
    end
    if ar ~= frame._lastAbsorbColorR or aa ~= frame._lastAbsorbColorA then
        frame._lastAbsorbColorR = ar
        frame._lastAbsorbColorA = aa
        frame.absorbBar:SetStatusBarColor(ar, ag, ab, aa)
    end
    frame.absorbBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Heal Absorb (debuffs that absorb healing, e.g. Necrotic Wound)
---------------------------------------------------------------------------
local function UpdateHealAbsorb(frame, _unit, _maxHP)
    if not frame or not frame.healAbsorbBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.healAbsorbs or vdb.healAbsorbs.enabled == false then
        frame.healAbsorbBar:Hide()
        return
    end

    local unit = _unit or frame.unit
    if not unit then return end

    if not _unit then
        local _, isDeadOrGhost = GetUnitLifeState(unit)
        if not UnitExists(unit) or isDeadOrGhost then
            frame.healAbsorbBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local healAbsorbAmount = UnitGetTotalHealAbsorbs(unit)

    if not healAbsorbAmount then
        frame.healAbsorbBar:Hide()
        return
    end
    if not IsSecretValue(healAbsorbAmount) and SafeToNumber(healAbsorbAmount, 0) <= 0 then
        frame.healAbsorbBar:SetValue(0)
        frame.healAbsorbBar:Hide()
        return
    end

    -- Redo geometry if orientation changed
    if frame._healAbsorbVertical ~= frame._isVerticalFill then
        frame.healAbsorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 3)
        frame.healAbsorbBar:ClearAllPoints()
        frame.healAbsorbBar:SetAllPoints(frame.healthBar)
        frame.healAbsorbBar:SetReverseFill(true)
        frame.healAbsorbBar:SetOrientation(frame._isVerticalFill and "VERTICAL" or "HORIZONTAL")
        frame._healAbsorbVertical = frame._isVerticalFill
    end

    -- C-side SetMinMaxValues handles secret values natively — no Lua comparison.
    frame.healAbsorbBar:SetMinMaxValues(0, maxHP)
    frame.healAbsorbBar:SetValue(healAbsorbAmount)

    -- Color (dirty-checked: settings-driven, never changes during combat)
    local ha = vdb.healAbsorbs.opacity or 0.6
    local hc = vdb.healAbsorbs.color or _state.defaultColors.healAbsorb
    if hc[1] ~= frame._lastHealAbsorbColorR or ha ~= frame._lastHealAbsorbColorA then
        frame._lastHealAbsorbColorR = hc[1]
        frame._lastHealAbsorbColorA = ha
        frame.healAbsorbBar:SetStatusBarColor(hc[1], hc[2], hc[3], ha)
    end
    frame.healAbsorbBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Heal Prediction
---------------------------------------------------------------------------
-- HealPrediction: optional pre-computed args from fast health path avoid redundant API calls.
local function UpdateHealPrediction(frame, _unit, _maxHP)
    if not frame or not frame.healPredictionBar then return end
    local isRaid = frame._isRaid
    local vdb = GetVisualDB(isRaid)
    if not vdb or not vdb.healPrediction or vdb.healPrediction.enabled == false then
        frame.healPredictionBar:Hide()
        return
    end

    local unit = _unit or frame.unit
    if not unit then return end

    -- When called standalone (UNIT_HEAL_PREDICTION), do our own guards.
    if not _unit then
        local _, isDeadOrGhost = GetUnitLifeState(unit)
        if not UnitExists(unit) or isDeadOrGhost then
            frame.healPredictionBar:Hide()
            return
        end
    end

    local maxHP = _maxHP or UnitHealthMax(unit)
    local incomingHeals

    -- Use CreateUnitHealPredictionCalculator (11.1+) if available (matches QUI pattern)
    if CreateUnitHealPredictionCalculator then
        if not frame._healPredCalc then
            frame._healPredCalc = CreateUnitHealPredictionCalculator()
            frame._healPredCalc:SetIncomingHealClampMode(0)
            frame._healPredCalc:SetIncomingHealOverflowPercent(1.0)
        end
        local calc = frame._healPredCalc
        UnitGetDetailedHealPrediction(unit, nil, calc)
        incomingHeals = calc:GetIncomingHeals()
    else
        -- Fallback to simple API
        incomingHeals = UnitGetIncomingHeals(unit)
    end

    -- Only hide on nil (API unavailable). Do NOT check for zero — StatusBar
    -- naturally shows 0-width when value is 0 (matches QUI pattern).
    if not incomingHeals then
        frame.healPredictionBar:Hide()
        return
    end

    -- Anchor from health fill edge.  Only redo geometry when orientation changes.
    if frame._healPredVertical ~= frame._isVerticalFill then
        local healthTexture = frame.healthBar:GetStatusBarTexture()
        frame.healPredictionBar:ClearAllPoints()
        if frame._isVerticalFill then
            frame.healPredictionBar:SetPoint("BOTTOMLEFT", healthTexture, "TOPLEFT", 0, 0)
            frame.healPredictionBar:SetPoint("TOPRIGHT", frame.healthBar, "TOPRIGHT", 0, 0)
            frame.healPredictionBar:SetOrientation("VERTICAL")
        else
            frame.healPredictionBar:SetPoint("TOPLEFT", healthTexture, "TOPRIGHT", 0, 0)
            frame.healPredictionBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
            frame.healPredictionBar:SetOrientation("HORIZONTAL")
        end
        frame._healPredVertical = frame._isVerticalFill
    end

    -- C-side SetMinMaxValues handles secret values natively — no Lua comparison.
    frame.healPredictionBar:SetMinMaxValues(0, maxHP)
    frame.healPredictionBar:SetValue(incomingHeals)

    -- Color (dirty-checked: settings-driven or class-based, both stable per event)
    local pa = vdb.healPrediction.opacity or 0.5
    local pr, pg, pb
    if vdb.healPrediction.useClassColor then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            pr, pg, pb = cc.r, cc.g, cc.b
        else
            pr, pg, pb = 0.2, 1, 0.2
        end
    else
        local pc = vdb.healPrediction.color
        if pc then
            pr, pg, pb = pc[1], pc[2], pc[3]
        else
            pr, pg, pb = 0.2, 1, 0.2
        end
    end
    if pr ~= frame._lastHealPredColorR or pa ~= frame._lastHealPredColorA then
        frame._lastHealPredColorR = pr
        frame._lastHealPredColorA = pa
        frame.healPredictionBar:SetStatusBarColor(pr, pg, pb, pa)
    end
    frame.healPredictionBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Role Icon
---------------------------------------------------------------------------
local ROLE_ATLAS = {
    TANK   = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

local ROLE_TOGGLE_KEY = {
    TANK    = "showRoleTank",
    HEALER  = "showRoleHealer",
    DAMAGER = "showRoleDPS",
}


---------------------------------------------------------------------------
UpdateDarkModeVisuals = function(frame, force)
    if not frame then return end
    local general = GetGeneralSettings(frame._isRaid)
    local bgColor, healthOpacity, bgOpacity
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or _state.defaultColors.darkModeBg
        healthOpacity = general.darkModeHealthOpacity or 1.0
        bgOpacity = general.darkModeBgOpacity or 1.0
    else
        bgColor = general and general.defaultBgColor or _state.defaultColors.frameBg
        healthOpacity = general and general.defaultHealthOpacity or 1.0
        bgOpacity = general and general.defaultBgOpacity or 1.0
    end
    local bgAlpha = (bgColor[4] or 1) * bgOpacity
    local now
    if force
        or bgColor[1] ~= frame._lastBackdropColorR
        or bgColor[2] ~= frame._lastBackdropColorG
        or bgColor[3] ~= frame._lastBackdropColorB
        or bgAlpha ~= frame._lastBackdropColorA
    then
        frame._lastBackdropColorR = bgColor[1]
        frame._lastBackdropColorG = bgColor[2]
        frame._lastBackdropColorB = bgColor[3]
        frame._lastBackdropColorA = bgAlpha
        now = GetTime()
        frame._lastBackdropReapplyTime = now
        SetBackdropFillColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
    else
        now = GetTime()
        if (now - (frame._lastBackdropReapplyTime or 0)) >= _state.backdropReapplyInterval then
            frame._lastBackdropReapplyTime = now
            SetBackdropFillColor(frame, bgColor[1], bgColor[2], bgColor[3], bgAlpha)
        end
    end
    if frame.healthBar then
        if healthOpacity ~= frame._lastHealthBarAlpha then
            frame._lastHealthBarAlpha = healthOpacity
            frame.healthBar:SetAlpha(healthOpacity)
        end
    end
end

---------------------------------------------------------------------------

_.GetHealthPct = GetHealthPct
_.GetHealthBarColor = GetHealthBarColor
_.UpdateHealth = UpdateHealth
_.UpdateAbsorbs = UpdateAbsorbs
_.UpdateHealAbsorb = UpdateHealAbsorb
_.UpdateHealPrediction = UpdateHealPrediction
_.UpdateDarkModeVisuals = UpdateDarkModeVisuals

function QUI_GF:RefreshHealth(frame)
    UpdateHealth(frame)
end
