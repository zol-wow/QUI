--[[ QUI Group Frames - Power Updates ]]
local ADDON_NAME, ns = ...
local QUI_GF = ns.QUI_GroupFrames
if not QUI_GF then return end
local _ = QUI_GF._
if not _ then return end

local QUICore = _.QUICore
local IsSecretValue = _.IsSecretValue
local _state = _.state
local GetPowerSettings = _.GetPowerSettings
local GetGeneralSettings = _.GetGeneralSettings
local GetFrameState = _.GetFrameState
local UnitExists = UnitExists
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local type = type

-- Power type → color mapping
local POWER_COLORS = {
    [0]  = { 0, 0.50, 1 },       -- Mana
    [1]  = { 1, 0, 0 },          -- Rage
    [2]  = { 1, 0.5, 0.25 },     -- Focus
    [3]  = { 1, 1, 0 },          -- Energy
    [6]  = { 0, 0.82, 1 },       -- Runic Power
    [8]  = { 0.3, 0.52, 0.9 },   -- Lunar Power
    [11] = { 0, 0.5, 1 },        -- Maelstrom
    [13] = { 0.4, 0, 0.8 },      -- Insanity
    [17] = { 0.79, 0.26, 0.99 }, -- Fury
    [18] = { 1, 0.61, 0 },       -- Pain
}

local function GetPowerBarColor(unit, isRaid)
    local db = GetPowerSettings(isRaid)
    if db and not db.powerBarUsePowerColor then
        local c = db.powerBarColor or _state.defaultColors.powerBar
        return c[1], c[2], c[3], c[4] or 1
    end

    local powerType = UnitPowerType(unit)
    if powerType then
        local c = POWER_COLORS[powerType]
        if c then return c[1], c[2], c[3], 1 end
    end
    return 0, 0.5, 1, 1 -- Default mana blue
end

---------------------------------------------------------------------------
-- UPDATE: Power
---------------------------------------------------------------------------
local function ShouldShowPowerForUnit(unit, isRaid)
    local ps = GetPowerSettings(isRaid)
    if not ps then return true end
    local onlyHealers = ps.powerBarOnlyHealers
    local onlyTanks = ps.powerBarOnlyTanks
    if not onlyHealers and not onlyTanks then return true end
    local role = UnitGroupRolesAssigned(unit)
    if onlyHealers and role == "HEALER" then return true end
    if onlyTanks and role == "TANK" then return true end
    return false
end

local function ResizeHealthForPower(frame, showPowerForUnit)
    if not frame.healthBar then return end
    local isRaid = frame._isRaid
    local general = GetGeneralSettings(isRaid)
    local borderPx = general and general.borderSize or 1
    local borderSize = borderPx > 0 and (QUICore.Pixels and QUICore:Pixels(borderPx, frame) or borderPx) or 0
    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(frame) or 1

    local bottomPad = borderSize
    if showPowerForUnit then
        local powerSettings = GetPowerSettings(isRaid)
        local rawPowerHeight = (powerSettings and powerSettings.powerBarHeight) or 4
        local powerHeight = QUICore.PixelRound and QUICore:PixelRound(rawPowerHeight, frame) or rawPowerHeight
        bottomPad = borderSize + powerHeight + px
    end

    local state = GetFrameState(frame)
    if state.healthPowerShow == showPowerForUnit
        and state.healthPowerBorder == borderSize
        and state.healthPowerBottom == bottomPad
    then
        return
    end
    state.healthPowerShow = showPowerForUnit
    state.healthPowerBorder = borderSize
    state.healthPowerBottom = bottomPad
    frame._bottomPad = bottomPad

    frame.healthBar:ClearAllPoints()
    frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, bottomPad)
end

local function UpdatePower(frame)
    if not frame or not frame.unit or not frame.powerBar then return end
    local unit = frame.unit

    if not UnitExists(unit) then
        frame.powerBar:SetValue(0)
        return
    end

    -- Role-based filtering
    if not ShouldShowPowerForUnit(unit, frame._isRaid) then
        frame.powerBar:Hide()
        if frame._powerSeparator then frame._powerSeparator:Hide() end
        if frame._powerBg then frame._powerBg:Hide() end
        ResizeHealthForPower(frame, false)
        return
    end
    frame.powerBar:Show()
    if frame._powerSeparator then frame._powerSeparator:Show() end
    if frame._powerBg then frame._powerBg:Show() end
    ResizeHealthForPower(frame, true)

    local power = UnitPower(unit)
    local maxPower = UnitPowerMax(unit)

    -- UnitPower/UnitPowerMax return nil for arena opponents — hide the bar.
    if type(power) ~= "number" or type(maxPower) ~= "number" then
        frame.powerBar:Hide()
        return
    end

    -- C-side SetMinMaxValues/SetValue handle secret values natively.
    -- Only update SetMinMaxValues when maxPower actually changes (rare: buffs/talents).
    -- Guard the Lua-side comparison with IsSecretValue to avoid errors from
    -- taint-propagated secret values.
    if IsSecretValue(maxPower) or maxPower ~= frame._lastMaxPower then
        if not IsSecretValue(maxPower) then
            frame._lastMaxPower = maxPower
        end
        frame.powerBar:SetMinMaxValues(0, maxPower)
    end
    frame.powerBar:SetValue(power)

    -- Color (dirty-checked: power color changes only on form/spec change, not every tick)
    local r, g, b, a = GetPowerBarColor(unit, frame._isRaid)
    if r ~= frame._lastPowerColorR
        or g ~= frame._lastPowerColorG
        or b ~= frame._lastPowerColorB
        or a ~= frame._lastPowerColorA
    then
        frame._lastPowerColorR = r
        frame._lastPowerColorG = g
        frame._lastPowerColorB = b
        frame._lastPowerColorA = a
        frame.powerBar:SetStatusBarColor(r, g, b, a)
    end
end

_.GetPowerBarColor = GetPowerBarColor
_.ShouldShowPowerForUnit = ShouldShowPowerForUnit
_.ResizeHealthForPower = ResizeHealthForPower
_.UpdatePower = UpdatePower
