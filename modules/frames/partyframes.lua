---------------------------------------------------------------------------
-- QUI Party Frames - Cell-Style Compact Party Frames
-- Creates compact party member cells with health bars filling the entire
-- cell, class colors, role icons, debuffs, absorbs, heal prediction,
-- dispel highlights, and range checking.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_PF = {}
ns.QUI_PartyFrames = QUI_PF

-- Frame references
QUI_PF.frames = {}        -- party1..party5 + optional player
QUI_PF.previewMode = false

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local MAX_PARTY = 4       -- party1-party4 (WoW max party excluding player)

local POWER_COLORS = {
    [0] = { 0, 0.50, 1 },       -- Mana
    [1] = { 1, 0, 0 },          -- Rage
    [2] = { 1, 0.5, 0.25 },     -- Focus
    [3] = { 1, 1, 0 },          -- Energy
    [6] = { 0, 0.82, 1 },       -- Runic Power
    [8] = { 0.3, 0.52, 0.9 },   -- Lunar Power
    [11] = { 0, 0.5, 1 },       -- Maelstrom
    [13] = { 0.4, 0, 0.8 },     -- Insanity
}

-- Dispel type colors
local DISPEL_COLORS = {
    Magic   = { 0.2, 0.6, 1.0 },
    Curse   = { 0.6, 0.0, 1.0 },
    Disease = { 0.6, 0.4, 0.0 },
    Poison  = { 0.0, 0.6, 0.0 },
}

-- Role icon atlas names
local ROLE_ATLAS = {
    TANK    = "roleicon-tiny-tank",
    HEALER  = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

-- Target marker icon paths (raid icons 1-8)
local RAID_ICON_TCOORDS = {
    [1] = { 0, 0.25, 0, 0.25 },       -- Star
    [2] = { 0.25, 0.5, 0, 0.25 },     -- Circle
    [3] = { 0.5, 0.75, 0, 0.25 },     -- Diamond
    [4] = { 0.75, 1, 0, 0.25 },       -- Triangle
    [5] = { 0, 0.25, 0.25, 0.5 },     -- Moon
    [6] = { 0.25, 0.5, 0.25, 0.5 },   -- Square
    [7] = { 0.5, 0.75, 0.25, 0.5 },   -- Cross
    [8] = { 0.75, 1, 0.25, 0.5 },     -- Skull
}

---------------------------------------------------------------------------
-- TOC VERSION
---------------------------------------------------------------------------
local tocVersion = tonumber((select(4, GetBuildInfo()))) or 0

---------------------------------------------------------------------------
-- DATABASE ACCESS
---------------------------------------------------------------------------
local function GetSettings()
    if QUICore and QUICore.db and QUICore.db.profile
        and QUICore.db.profile.quiUnitFrames then
        return QUICore.db.profile.quiUnitFrames.party
    end
    return nil
end

---------------------------------------------------------------------------
-- HELPER: Health percent (copy from unitframes.lua for isolation)
---------------------------------------------------------------------------
local function GetHealthPct(unit, usePredicted)
    if tocVersion >= 120000 and type(UnitHealthPercent) == "function" then
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitHealthPercent, unit, usePredicted, CurveConstants.ScaleTo100)
        end
        if not ok or pct == nil then
            ok, pct = pcall(UnitHealthPercent, unit, usePredicted)
        end
        if ok and pct ~= nil then
            return pct
        end
    end
    if UnitHealth and UnitHealthMax then
        local cur = UnitHealth(unit)
        local max = UnitHealthMax(unit)
        if cur and max and max > 0 then
            local ok, pct = pcall(function() return (cur / max) * 100 end)
            if ok then return pct end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- HELPER: Power percent
---------------------------------------------------------------------------
local function GetPowerPct(unit, powerType, usePredicted)
    if tocVersion >= 120000 and type(UnitPowerPercent) == "function" then
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted, CurveConstants.ScaleTo100)
        end
        if not ok or pct == nil then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted)
        end
        if ok and pct ~= nil then
            return pct
        end
    end
    local cur = UnitPower(unit, powerType)
    local max = UnitPowerMax(unit, powerType)
    local calcOk, result = pcall(function()
        if cur and max and max > 0 then
            return (cur / max) * 100
        end
        return nil
    end)
    if calcOk and result then
        return result
    end
    return nil
end

---------------------------------------------------------------------------
-- HELPER: Font
---------------------------------------------------------------------------
local function GetFontPath()
    return Helpers.GetGeneralFont()
end

local function GetFontOutline()
    return Helpers.GetGeneralFontOutline()
end

---------------------------------------------------------------------------
-- HELPER: Texture path
---------------------------------------------------------------------------
local function GetTexturePath(textureName)
    local name = textureName
    if not name or name == "" then name = "Quazii v5" end
    return LSM:Fetch("statusbar", name) or "Interface\\Buttons\\WHITE8x8"
end

local function GetAbsorbTexturePath(textureName)
    local name = textureName
    if not name or name == "" then name = "QUI Stripes" end
    return LSM:Fetch("statusbar", name) or "Interface\\AddOns\\QUI\\assets\\absorb_stripe"
end

---------------------------------------------------------------------------
-- HELPER: Class color
---------------------------------------------------------------------------
local function GetUnitClassColor(unit)
    if not UnitExists(unit) then
        return 0.5, 0.5, 0.5, 1
    end

    -- Try class color first (works for players, pcall for secret value safety)
    local ok, _, class = pcall(UnitClass, unit)
    if ok and class then
        local color = RAID_CLASS_COLORS[class]
        if color then
            return color.r, color.g, color.b, 1
        end
    end

    -- Fallback: reaction color for NPCs
    local rok, reaction = pcall(UnitReaction, unit, "player")
    if rok and reaction then
        local okCmp, isFriendly = pcall(function() return reaction >= 5 end)
        if okCmp and isFriendly then
            return 0.2, 0.8, 0.2, 1  -- Friendly (green)
        end
        local okCmp2, isNeutral = pcall(function() return reaction == 4 end)
        if okCmp2 and isNeutral then
            return 1, 1, 0.2, 1      -- Neutral (yellow)
        end
        return 0.8, 0.2, 0.2, 1      -- Hostile (red)
    end

    return 0.5, 0.5, 0.5, 1
end

---------------------------------------------------------------------------
-- HELPER: Truncate name (UTF-8 safe)
---------------------------------------------------------------------------
local function TruncateName(name, maxLength)
    if not name or type(name) ~= "string" then return name end
    if not maxLength or maxLength <= 0 then return name end
    if IsSecretValue(name) then
        return string.format("%." .. maxLength .. "s", name)
    end
    local lenOk, nameLen = pcall(function() return #name end)
    if not lenOk then
        return string.format("%." .. maxLength .. "s", name)
    end
    if nameLen <= maxLength then return name end
    local byte = string.byte
    local i = 1
    local c = 0
    while i <= nameLen and c < maxLength do
        c = c + 1
        local b = byte(name, i)
        if b < 0x80 then
            i = i + 1
        elseif b < 0xE0 then
            i = i + 2
        elseif b < 0xF0 then
            i = i + 3
        else
            i = i + 4
        end
    end
    local subOk, truncated = pcall(string.sub, name, 1, i - 1)
    if subOk and truncated then return truncated end
    return string.format("%." .. maxLength .. "s", name)
end

---------------------------------------------------------------------------
-- HELPER: Tooltip
---------------------------------------------------------------------------
local function ShowUnitTooltip(frame)
    local unit = frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
    if not unit or not UnitExists(unit) then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

local function HideUnitTooltip()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- UPDATE: Health bar
---------------------------------------------------------------------------
local function UpdateHealth(frame)
    if not frame or not frame.unit or not frame.healthBar then return end
    local unit = frame.unit
    if not UnitExists(unit) then return end

    local hp = UnitHealth(unit)
    local maxHP = UnitHealthMax(unit)
    frame.healthBar:SetMinMaxValues(0, maxHP or 1)
    frame.healthBar:SetValue(hp or 0)

    -- Health text
    if frame.healthText then
        local settings = GetSettings()
        if settings and settings.showHealth then
            local hpPct = GetHealthPct(unit, false)
            if hpPct then
                local style = settings.healthDisplayStyle or "percent"
                if style == "percent" then
                    local okFmt, str = pcall(string.format, "%.0f%%", hpPct)
                    frame.healthText:SetText(okFmt and str or "")
                else
                    frame.healthText:SetText("")
                end
                frame.healthText:Show()
            else
                frame.healthText:SetText("")
            end
        else
            frame.healthText:Hide()
        end
    end

    -- Health bar color
    local settings = GetSettings()
    if settings and settings.useClassColor then
        local r, g, b = GetUnitClassColor(unit)
        frame.healthBar:SetStatusBarColor(r, g, b, 1)
    else
        local c = settings and settings.customHealthColor or { 0.2, 0.6, 0.2, 1 }
        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Absorbs
---------------------------------------------------------------------------
local function UpdateAbsorbs(frame)
    if not frame or not frame.unit or not frame.healthBar then return end
    if not frame.absorbBar then return end

    local unit = frame.unit
    local settings = GetSettings()

    if not settings or not settings.absorbs or settings.absorbs.enabled == false then
        frame.absorbBar:Hide()
        if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
        return
    end

    if not UnitExists(unit) then
        frame.absorbBar:Hide()
        if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
        return
    end

    local maxHealth = UnitHealthMax(unit)
    local absorbAmount = UnitGetTotalAbsorbs(unit)
    local healthTexture = frame.healthBar:GetStatusBarTexture()

    local absorbSettings = settings.absorbs or {}
    local c = absorbSettings.color or { 1, 1, 1 }
    local a = absorbSettings.opacity or 0.3

    -- Safe zero check
    local hideAbsorb = false
    if not absorbAmount then
        hideAbsorb = true
    else
        local success, isZero = pcall(function() return absorbAmount == 0 end)
        if success and isZero then
            hideAbsorb = true
        end
    end

    if hideAbsorb then
        frame.absorbBar:Hide()
        if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
        return
    end

    local absorbTexturePath = GetAbsorbTexturePath(absorbSettings.texture)

    -- Create overflow bar if needed
    if not frame.absorbOverflowBar then
        frame.absorbOverflowBar = CreateFrame("StatusBar", nil, frame.healthBar)
        frame.absorbOverflowBar:SetStatusBarTexture(absorbTexturePath)
        frame.absorbOverflowBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
        frame.absorbOverflowBar:EnableMouse(false)
    else
        frame.absorbOverflowBar:SetStatusBarTexture(absorbTexturePath)
    end

    -- Create visibility helpers
    if not frame.attachedVisHelper then
        frame.attachedVisHelper = frame.absorbBar:CreateTexture(nil, "BACKGROUND")
        frame.attachedVisHelper:SetSize(1, 1)
        frame.attachedVisHelper:SetColorTexture(0, 0, 0, 0)
    end
    if not frame.overflowVisHelper then
        frame.overflowVisHelper = frame.absorbOverflowBar:CreateTexture(nil, "BACKGROUND")
        frame.overflowVisHelper:SetSize(1, 1)
        frame.overflowVisHelper:SetColorTexture(0, 0, 0, 0)
    end

    local clampedAbsorbs = absorbAmount
    frame.attachedVisHelper:SetAlpha(1)
    frame.overflowVisHelper:SetAlpha(0)

    if CreateUnitHealPredictionCalculator and unit then
        if not frame.absorbCalculator then
            frame.absorbCalculator = CreateUnitHealPredictionCalculator()
        end
        local calc = frame.absorbCalculator
        pcall(function() calc:SetDamageAbsorbClampMode(1) end)
        UnitGetDetailedHealPrediction(unit, nil, calc)
        local results = { pcall(function() return calc:GetDamageAbsorbs() end) }
        if results[1] then
            clampedAbsorbs = results[2]
            pcall(function()
                frame.attachedVisHelper:SetAlphaFromBoolean(results[3], 0, 1)
                frame.overflowVisHelper:SetAlphaFromBoolean(results[3], 1, 0)
            end)
        end
    end

    -- Attached bar
    frame.absorbBar:ClearAllPoints()
    frame.absorbBar:SetPoint("LEFT", healthTexture, "RIGHT", 0, 0)
    frame.absorbBar:SetHeight(frame.healthBar:GetHeight())
    frame.absorbBar:SetWidth(frame.healthBar:GetWidth())
    frame.absorbBar:SetReverseFill(false)
    frame.absorbBar:SetMinMaxValues(0, maxHealth or 1)
    frame.absorbBar:SetValue(clampedAbsorbs)
    frame.absorbBar:SetStatusBarTexture(absorbTexturePath)
    frame.absorbBar:SetStatusBarColor(c[1], c[2], c[3], a)
    frame.absorbBar:SetAlpha(frame.attachedVisHelper:GetAlpha())
    frame.absorbBar:Show()

    -- Overflow bar
    frame.absorbOverflowBar:ClearAllPoints()
    frame.absorbOverflowBar:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
    frame.absorbOverflowBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
    frame.absorbOverflowBar:SetReverseFill(true)
    frame.absorbOverflowBar:SetMinMaxValues(0, maxHealth or 1)
    frame.absorbOverflowBar:SetValue(absorbAmount)
    frame.absorbOverflowBar:SetStatusBarColor(c[1], c[2], c[3], a)
    frame.absorbOverflowBar:SetAlpha(frame.overflowVisHelper:GetAlpha())
    frame.absorbOverflowBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Heal prediction
---------------------------------------------------------------------------
local function UpdateHealPrediction(frame)
    if not frame or not frame.unit or not frame.healthBar or not frame.healPredictionBar then return end

    local unit = frame.unit
    local settings = GetSettings()
    local predSettings = settings and settings.healPrediction

    if not predSettings or predSettings.enabled == false then
        frame.healPredictionBar:Hide()
        return
    end

    if not UnitExists(unit) then
        frame.healPredictionBar:Hide()
        return
    end

    local maxHealth = UnitHealthMax(unit)
    local incomingHeals

    if CreateUnitHealPredictionCalculator then
        if not frame.healPredictionCalculator then
            frame.healPredictionCalculator = CreateUnitHealPredictionCalculator()
            local calc = frame.healPredictionCalculator
            if calc and calc.SetIncomingHealClampMode then
                local clampMode = 1
                if Enum and Enum.UnitIncomingHealClampMode and Enum.UnitIncomingHealClampMode.MissingHealth then
                    clampMode = Enum.UnitIncomingHealClampMode.MissingHealth
                end
                pcall(calc.SetIncomingHealClampMode, calc, clampMode)
            end
            if calc and calc.SetIncomingHealOverflowPercent then
                pcall(calc.SetIncomingHealOverflowPercent, calc, 1.0)
            end
        end

        local calc = frame.healPredictionCalculator
        if calc and UnitGetDetailedHealPrediction then
            pcall(UnitGetDetailedHealPrediction, unit, nil, calc)
            local results = { pcall(function() return calc:GetIncomingHeals() end) }
            if results[1] then
                incomingHeals = results[2]
            end
        end
    end

    if not incomingHeals then
        incomingHeals = UnitGetIncomingHeals and UnitGetIncomingHeals(unit)
    end

    if not incomingHeals then
        frame.healPredictionBar:Hide()
        return
    end

    local okZero, isZero = pcall(function() return incomingHeals == 0 end)
    if okZero and isZero then
        frame.healPredictionBar:Hide()
        return
    end

    local healthTexture = frame.healthBar:GetStatusBarTexture()
    frame.healPredictionBar:ClearAllPoints()
    frame.healPredictionBar:SetPoint("LEFT", healthTexture, "RIGHT", 0, 0)
    frame.healPredictionBar:SetHeight(frame.healthBar:GetHeight())
    frame.healPredictionBar:SetWidth(frame.healthBar:GetWidth())
    frame.healPredictionBar:SetReverseFill(false)
    frame.healPredictionBar:SetMinMaxValues(0, maxHealth or 1)
    frame.healPredictionBar:SetValue(incomingHeals)
    frame.healPredictionBar:SetStatusBarTexture(GetTexturePath(settings.texture))

    local c = predSettings.color or { 0.2, 1, 0.2 }
    local a = predSettings.opacity or 0.4
    frame.healPredictionBar:SetStatusBarColor(c[1] or 0.2, c[2] or 1, c[3] or 0.2, a)
    frame.healPredictionBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Power bar
---------------------------------------------------------------------------
local function UpdatePower(frame)
    if not frame or not frame.unit or not frame.powerBar then return end
    local unit = frame.unit
    if not UnitExists(unit) then return end

    local settings = GetSettings()
    if not settings or not settings.showPowerBar then
        frame.powerBar:Hide()
        return
    end

    local powerType = UnitPowerType(unit)
    local power = UnitPower(unit)
    local maxPower = UnitPowerMax(unit)

    frame.powerBar:SetMinMaxValues(0, maxPower or 1)
    frame.powerBar:SetValue(power or 0)

    -- Color
    if settings.powerBarUsePowerColor then
        local c = POWER_COLORS[powerType]
        if c then
            frame.powerBar:SetStatusBarColor(c[1], c[2], c[3], 1)
        else
            frame.powerBar:SetStatusBarColor(0, 0.5, 1, 1)
        end
    else
        local c = settings.powerBarColor or { 0, 0.5, 1, 1 }
        frame.powerBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end

    frame.powerBar:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Name text
---------------------------------------------------------------------------
local function UpdateName(frame)
    if not frame or not frame.unit or not frame.nameText then return end
    local unit = frame.unit
    if not UnitExists(unit) then
        frame.nameText:SetText("")
        return
    end

    local settings = GetSettings()
    local name = UnitName(unit) or ""
    local maxLen = settings and settings.maxNameLength or 6
    if maxLen > 0 then
        name = TruncateName(name, maxLen)
    end
    frame.nameText:SetText(name)

    -- Name color
    if settings and settings.nameUseClassColor then
        local r, g, b = GetUnitClassColor(unit)
        frame.nameText:SetTextColor(r, g, b, 1)
    else
        local c = settings and settings.nameColor or { 1, 1, 1, 1 }
        frame.nameText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Role icon
---------------------------------------------------------------------------
local function UpdateRoleIcon(frame)
    if not frame or not frame.unit or not frame.roleIcon then return end
    local settings = GetSettings()
    if not settings or not settings.showRoleIcon then
        frame.roleIcon:Hide()
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        frame.roleIcon:Hide()
        return
    end

    local role = UnitGroupRolesAssigned(unit)
    local atlas = role and ROLE_ATLAS[role]
    if atlas then
        frame.roleIcon:SetAtlas(atlas)
        frame.roleIcon:Show()
    else
        frame.roleIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Leader icon
---------------------------------------------------------------------------
local function UpdateLeaderIcon(frame)
    if not frame or not frame.unit or not frame.leaderIcon then return end
    local settings = GetSettings()
    if not settings or not settings.leaderIcon or not settings.leaderIcon.enabled then
        frame.leaderIcon:Hide()
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        frame.leaderIcon:Hide()
        return
    end

    if UnitIsGroupLeader(unit) then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:Show()
    elseif UnitIsGroupAssistant and UnitIsGroupAssistant(unit) then
        frame.leaderIcon:SetAtlas("groupfinder-icon-leader")
        frame.leaderIcon:Show()
    else
        frame.leaderIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Target marker (raid icon)
---------------------------------------------------------------------------
local function UpdateTargetMarker(frame)
    if not frame or not frame.unit or not frame.targetMarker then return end
    local settings = GetSettings()
    if not settings or not settings.targetMarker or not settings.targetMarker.enabled then
        frame.targetMarker:Hide()
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        frame.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(unit)
    if index and RAID_ICON_TCOORDS[index] then
        local coords = RAID_ICON_TCOORDS[index]
        frame.targetMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        frame.targetMarker:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        frame.targetMarker:Show()
    else
        frame.targetMarker:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Debuffs (compact icons)
---------------------------------------------------------------------------
local function UpdateDebuffs(frame)
    if not frame or not frame.unit then return end
    local settings = GetSettings()
    if not settings or not settings.auras or not settings.auras.showDebuffs then
        if frame.debuffIcons then
            for _, icon in ipairs(frame.debuffIcons) do
                icon:Hide()
            end
        end
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        if frame.debuffIcons then
            for _, icon in ipairs(frame.debuffIcons) do
                icon:Hide()
            end
        end
        return
    end

    local auraSettings = settings.auras
    local maxIcons = auraSettings.debuffMaxIcons or 3
    local iconSize = auraSettings.iconSize or 16
    local spacing = auraSettings.debuffSpacing or 1

    -- Create debuff icons if needed
    if not frame.debuffIcons then
        frame.debuffIcons = {}
        for i = 1, maxIcons do
            local icon = CreateFrame("Frame", nil, frame)
            icon:SetSize(iconSize, iconSize)
            icon:SetFrameLevel(frame:GetFrameLevel() + 5)

            icon.texture = icon:CreateTexture(nil, "ARTWORK")
            icon.texture:SetAllPoints()
            icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            icon.border = icon:CreateTexture(nil, "OVERLAY")
            icon.border:SetPoint("TOPLEFT", -1, 1)
            icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
            icon.border:SetColorTexture(0.8, 0, 0, 1)
            icon.border:SetDrawLayer("OVERLAY", -1)

            icon.stackText = icon:CreateFontString(nil, "OVERLAY")
            icon.stackText:SetFont(GetFontPath() or "Fonts\\FRIZQT__.TTF", auraSettings.debuffStackSize or 8, "OUTLINE")
            icon.stackText:SetPoint("BOTTOMRIGHT", 1, -1)
            icon.stackText:SetTextColor(1, 1, 1, 1)

            frame.debuffIcons[i] = icon
            icon:Hide()
        end
    end

    -- Update icon sizes
    for _, icon in ipairs(frame.debuffIcons) do
        icon:SetSize(iconSize, iconSize)
    end

    -- Position icons based on anchor and grow direction
    local anchor = auraSettings.debuffAnchor or "CENTER"
    local grow = auraSettings.debuffGrow or "RIGHT"
    local ofsX = auraSettings.debuffOffsetX or 0
    local ofsY = auraSettings.debuffOffsetY or 0

    local shown = 0
    for i = 1, 40 do
        if shown >= maxIcons then break end
        local auraData = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex(unit, i)
        if not auraData then break end
        if auraData.icon then
            shown = shown + 1
            local btn = frame.debuffIcons[shown]
            btn.texture:SetTexture(auraData.icon)
            -- Stack count
            if auraSettings.debuffShowStack and auraData.applications and auraData.applications > 1 then
                btn.stackText:SetText(auraData.applications)
                btn.stackText:Show()
            else
                btn.stackText:Hide()
            end
            -- Debuff type color on border
            if auraData.dispelName and DISPEL_COLORS[auraData.dispelName] then
                local dc = DISPEL_COLORS[auraData.dispelName]
                btn.border:SetColorTexture(dc[1], dc[2], dc[3], 1)
            else
                btn.border:SetColorTexture(0.8, 0, 0, 1)
            end
            btn:Show()
        end
    end

    -- Hide unused icons
    for i = shown + 1, #frame.debuffIcons do
        frame.debuffIcons[i]:Hide()
    end

    -- Arrange visible icons
    for i = 1, shown do
        local btn = frame.debuffIcons[i]
        btn:ClearAllPoints()
        if i == 1 then
            btn:SetPoint(anchor, frame, anchor, ofsX, ofsY)
        else
            local prev = frame.debuffIcons[i - 1]
            if grow == "RIGHT" then
                btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
            elseif grow == "LEFT" then
                btn:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
            elseif grow == "DOWN" then
                btn:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
            elseif grow == "UP" then
                btn:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
            end
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Dispel highlight (colored border for dispellable debuffs)
---------------------------------------------------------------------------
local function UpdateDispelHighlight(frame)
    if not frame or not frame.unit or not frame.dispelBorder then return end
    local settings = GetSettings()
    if not settings or not settings.dispelHighlight or not settings.dispelHighlight.enabled then
        frame.dispelBorder:Hide()
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        frame.dispelBorder:Hide()
        return
    end

    -- Check for dispellable debuffs
    local dispelType = nil
    for i = 1, 40 do
        local auraData = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex(unit, i)
        if not auraData then break end
        if auraData.isStealable or (auraData.dispelName and DISPEL_COLORS[auraData.dispelName]) then
            dispelType = auraData.dispelName
            break
        end
    end

    if dispelType and DISPEL_COLORS[dispelType] then
        local dc = DISPEL_COLORS[dispelType]
        frame.dispelBorder:SetBackdropBorderColor(dc[1], dc[2], dc[3], 1)
        frame.dispelBorder:Show()
    else
        frame.dispelBorder:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Status text (Dead, Offline, Ghost)
---------------------------------------------------------------------------
local function UpdateStatus(frame)
    if not frame or not frame.unit or not frame.statusText then return end
    local settings = GetSettings()
    local statusIcons = settings and settings.statusIcons
    local unit = frame.unit

    if not UnitExists(unit) then
        frame.statusText:SetText("")
        frame.statusText:Hide()
        return
    end

    if statusIcons and statusIcons.showDead and UnitIsDead(unit) then
        frame.statusText:SetText("DEAD")
        frame.statusText:SetTextColor(1, 0, 0, 1)
        frame.statusText:Show()
        if frame.nameText then frame.nameText:Hide() end
        if frame.healthText then frame.healthText:Hide() end
        return
    end

    if statusIcons and statusIcons.showOffline and not UnitIsConnected(unit) then
        frame.statusText:SetText("OFFLINE")
        frame.statusText:SetTextColor(0.5, 0.5, 0.5, 1)
        frame.statusText:Show()
        if frame.nameText then frame.nameText:Hide() end
        if frame.healthText then frame.healthText:Hide() end
        return
    end

    if UnitIsGhost(unit) then
        frame.statusText:SetText("GHOST")
        frame.statusText:SetTextColor(0.5, 0.5, 0.5, 1)
        frame.statusText:Show()
        if frame.nameText then frame.nameText:Hide() end
        if frame.healthText then frame.healthText:Hide() end
        return
    end

    frame.statusText:SetText("")
    frame.statusText:Hide()
    if frame.nameText then
        local s = GetSettings()
        if s and s.showName then frame.nameText:Show() end
    end
    if frame.healthText then
        local s = GetSettings()
        if s and s.showHealth then frame.healthText:Show() end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Range check (alpha dimming)
---------------------------------------------------------------------------
local function UpdateRange(frame)
    if not frame or not frame.unit then return end
    local settings = GetSettings()
    if not settings or not settings.rangeCheck or not settings.rangeCheck.enabled then
        frame:SetAlpha(1)
        return
    end

    local unit = frame.unit
    if not UnitExists(unit) then
        frame:SetAlpha(1)
        return
    end

    -- player is always in range of self
    if unit == "player" then
        frame:SetAlpha(1)
        return
    end

    local inRange, checked = UnitInRange(unit)
    -- Both return values can be secret booleans in Midnight — wrap in pcall
    local ok, outOfRange = pcall(function() return checked and not inRange end)
    if ok and outOfRange then
        frame:SetAlpha(settings.rangeCheck.outOfRangeAlpha or 0.4)
    else
        frame:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- MASTER UPDATE: All elements
---------------------------------------------------------------------------
local function UpdateFrame(frame)
    if not frame then return end
    UpdateHealth(frame)
    UpdateAbsorbs(frame)
    UpdateHealPrediction(frame)
    UpdatePower(frame)
    UpdateName(frame)
    UpdateRoleIcon(frame)
    UpdateLeaderIcon(frame)
    UpdateTargetMarker(frame)
    UpdateDebuffs(frame)
    UpdateDispelHighlight(frame)
    UpdateStatus(frame)
    UpdateRange(frame)
end

---------------------------------------------------------------------------
-- CREATE: Single party frame (Cell-style)
---------------------------------------------------------------------------
local function CreatePartyFrame(unit, frameKey, index)
    local settings = GetSettings()
    if not settings then return nil end

    local frameName = "QUI_Party" .. (index or 1)
    local frame = CreateFrame("Button", frameName, UIParent,
        "SecureUnitButtonTemplate, BackdropTemplate")

    frame.unit = unit
    frame.unitKey = "party"
    frame.partyIndex = index

    -- Size (pixel-perfect)
    local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 72, frame))
                  or (settings.width or 72)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 36, frame))
                   or (settings.height or 36)
    frame:SetSize(width, height)

    -- Position first frame at anchor point
    if index == 1 or (unit == "player" and index == 0) then
        if QUICore.SetSnappedPoint then
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER",
                                     settings.offsetX or -400, settings.offsetY or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER",
                           settings.offsetX or -400, settings.offsetY or 0)
        end
    end

    -- Make movable
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Secure attributes for click targeting
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")

    -- Tooltips
    frame:HookScript("OnEnter", function(self) ShowUnitTooltip(self) end)
    frame:HookScript("OnLeave", HideUnitTooltip)

    -- Background & border (pixel-perfect)
    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0
    local bgColor = settings.bgColor or { 0.1, 0.1, 0.1, 0.9 }

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.9)
    if borderSize > 0 then
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- Health bar (fills entire cell - Cell-style)
    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    if settings.showPowerBar then
        local pbHeight = QUICore:Pixels(settings.powerBarHeight or 3, frame)
        healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + pbHeight)
    else
        healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
    end
    healthBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:EnableMouse(false)
    frame.healthBar = healthBar

    -- Health bar background (deficit color)
    local healthBG = healthBar:CreateTexture(nil, "BACKGROUND")
    healthBG:SetAllPoints()
    healthBG:SetTexture("Interface\\Buttons\\WHITE8x8")
    healthBG:SetVertexColor(0.1, 0.1, 0.1, 1)
    frame.healthBG = healthBG

    -- Absorb bar (overlay on health bar)
    local absorbBar = CreateFrame("StatusBar", nil, healthBar)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    absorbBar:EnableMouse(false)
    local absorbTexture = GetAbsorbTexturePath(settings.absorbs and settings.absorbs.texture)
    absorbBar:SetStatusBarTexture(absorbTexture)
    absorbBar:Hide()
    frame.absorbBar = absorbBar

    -- Heal prediction bar
    local healPredBar = CreateFrame("StatusBar", nil, healthBar)
    healPredBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredBar:EnableMouse(false)
    healPredBar:Hide()
    frame.healPredictionBar = healPredBar

    -- Power bar (narrow bar at bottom, optional)
    if settings.showPowerBar then
        local powerBar = CreateFrame("StatusBar", nil, frame)
        local pbHeight = QUICore:Pixels(settings.powerBarHeight or 3, frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(pbHeight)
        powerBar:SetStatusBarTexture(GetTexturePath(settings.texture))
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        powerBar:EnableMouse(false)

        -- Power bar background
        local powerBG = powerBar:CreateTexture(nil, "BACKGROUND")
        powerBG:SetAllPoints()
        powerBG:SetTexture("Interface\\Buttons\\WHITE8x8")
        powerBG:SetVertexColor(0.05, 0.05, 0.05, 1)

        frame.powerBar = powerBar
    end

    -- Name text (always created, visibility toggled by showName)
    local nameText = healthBar:CreateFontString(nil, "OVERLAY")
    local fontPath = GetFontPath() or "Fonts\\FRIZQT__.TTF"
    local fontOutline = GetFontOutline() or "OUTLINE"
    nameText:SetFont(fontPath, settings.nameFontSize or 11, fontOutline)
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetWordWrap(false)
    local nameAnchor = settings.nameAnchor or "CENTER"
    nameText:SetPoint(nameAnchor, healthBar, nameAnchor,
                      settings.nameOffsetX or 0, settings.nameOffsetY or 0)
    local justify = (nameAnchor == "LEFT" or nameAnchor == "TOPLEFT" or nameAnchor == "BOTTOMLEFT") and "LEFT"
                 or (nameAnchor == "RIGHT" or nameAnchor == "TOPRIGHT" or nameAnchor == "BOTTOMRIGHT") and "RIGHT"
                 or "CENTER"
    nameText:SetJustifyH(justify)
    if not settings.showName then nameText:Hide() end
    frame.nameText = nameText

    -- Health text
    local healthText = healthBar:CreateFontString(nil, "OVERLAY")
    local fontPath = GetFontPath() or "Fonts\\FRIZQT__.TTF"
    local fontOutline = GetFontOutline() or "OUTLINE"
    healthText:SetFont(fontPath, settings.healthFontSize or 10, fontOutline)
    healthText:SetTextColor(1, 1, 1, 1)
    healthText:SetWordWrap(false)
    local hAnchor = settings.healthAnchor or "BOTTOM"
    healthText:SetPoint(hAnchor, healthBar, hAnchor,
                        settings.healthOffsetX or 0, settings.healthOffsetY or 2)
    if not settings.showHealth then healthText:Hide() end
    frame.healthText = healthText

    -- Role icon
    local roleIcon = healthBar:CreateTexture(nil, "OVERLAY")
    roleIcon:SetSize(settings.roleIconSize or 10, settings.roleIconSize or 10)
    local roleAnchor = settings.roleIconAnchor or "TOPLEFT"
    roleIcon:SetPoint(roleAnchor, healthBar, roleAnchor,
                      settings.roleIconOffsetX or 1, settings.roleIconOffsetY or -1)
    roleIcon:Hide()
    frame.roleIcon = roleIcon

    -- Leader icon
    local leaderIcon = healthBar:CreateTexture(nil, "OVERLAY")
    local ldrSettings = settings.leaderIcon or {}
    leaderIcon:SetSize(ldrSettings.size or 12, ldrSettings.size or 12)
    local ldrAnchor = ldrSettings.anchor or "TOPRIGHT"
    leaderIcon:SetPoint(ldrAnchor, healthBar, ldrAnchor,
                        ldrSettings.xOffset or -1, ldrSettings.yOffset or -1)
    leaderIcon:Hide()
    frame.leaderIcon = leaderIcon

    -- Target marker (raid icon)
    local tmSettings = settings.targetMarker or {}
    local targetMarker = healthBar:CreateTexture(nil, "OVERLAY")
    targetMarker:SetSize(tmSettings.size or 14, tmSettings.size or 14)
    local tmAnchor = tmSettings.anchor or "TOP"
    targetMarker:SetPoint(tmAnchor, healthBar, tmAnchor,
                          tmSettings.xOffset or 0, tmSettings.yOffset or -2)
    targetMarker:Hide()
    frame.targetMarker = targetMarker

    -- Dispel highlight border (separate frame overlaying the cell)
    local dispelBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    dispelBorder:SetFrameLevel(frame:GetFrameLevel() + 6)
    local dispelBorderPx = settings.dispelHighlight and settings.dispelHighlight.borderSize or 2
    local dispelBorderSize = QUICore:Pixels(dispelBorderPx, frame)
    dispelBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    dispelBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    dispelBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = dispelBorderSize,
    })
    dispelBorder:SetBackdropBorderColor(0.2, 0.6, 1.0, 1)
    dispelBorder:EnableMouse(false)
    dispelBorder:Hide()
    frame.dispelBorder = dispelBorder

    -- Status text (centered, for DEAD/OFFLINE/GHOST)
    local statusText = healthBar:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(GetFontPath() or "Fonts\\FRIZQT__.TTF", settings.nameFontSize or 11, "OUTLINE")
    statusText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    statusText:SetTextColor(1, 0, 0, 1)
    statusText:Hide()
    frame.statusText = statusText

    -- State driver for visibility
    if unit == "player" then
        RegisterStateDriver(frame, "visibility", "[group] show; hide")
    else
        local partyNum = unit:match("party(%d+)")
        if partyNum then
            RegisterStateDriver(frame, "visibility", "[@" .. unit .. ",exists] show; hide")
        end
    end

    -- Range check via OnUpdate (0.5s interval)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            UpdateRange(self)
        end
    end)

    -- Register events
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    frame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    frame:RegisterEvent("UNIT_HEAL_PREDICTION")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_POWER_FREQUENT")
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_NAME_UPDATE")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("UNIT_CONNECTION")
    frame:RegisterEvent("RAID_TARGET_UPDATE")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PARTY_LEADER_CHANGED")
    frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")

    -- Event handler
    frame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_ENTERING_WORLD" then
            UpdateFrame(self)
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED"
            or event == "PLAYER_ROLES_ASSIGNED" then
            UpdateFrame(self)
        elseif event == "RAID_TARGET_UPDATE" then
            UpdateTargetMarker(self)
        elseif arg1 == self.unit then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                UpdateHealth(self)
                UpdateAbsorbs(self)
                UpdateHealPrediction(self)
                UpdateStatus(self)
            elseif event == "UNIT_ABSORB_AMOUNT_CHANGED"
                or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                UpdateAbsorbs(self)
            elseif event == "UNIT_HEAL_PREDICTION" then
                UpdateHealPrediction(self)
            elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
                or event == "UNIT_MAXPOWER" then
                UpdatePower(self)
            elseif event == "UNIT_NAME_UPDATE" then
                UpdateName(self)
            elseif event == "UNIT_AURA" then
                UpdateDebuffs(self)
                UpdateDispelHighlight(self)
            elseif event == "UNIT_CONNECTION" then
                UpdateStatus(self)
            end
        end
    end)

    -- Clique compatibility
    if _G.ClickCastFrames then
        _G.ClickCastFrames[frame] = true
    end

    return frame
end

---------------------------------------------------------------------------
-- LAYOUT: Position all frames based on grow direction
---------------------------------------------------------------------------
local function LayoutFrames()
    local settings = GetSettings()
    if not settings then return end

    local spacing = settings.spacing or 2
    local grow = settings.growDirection or "DOWN"

    -- Collect ordered frames (player first if shown, then party1..party4)
    local orderedKeys = {}
    if settings.showPlayer and QUI_PF.frames["partyplayer"] then
        table.insert(orderedKeys, "partyplayer")
    end
    for i = 1, MAX_PARTY do
        local key = "party" .. i
        if QUI_PF.frames[key] then
            table.insert(orderedKeys, key)
        end
    end

    for i, key in ipairs(orderedKeys) do
        local frame = QUI_PF.frames[key]
        if frame and i > 1 then
            local prevFrame = QUI_PF.frames[orderedKeys[i - 1]]
            if prevFrame then
                frame:ClearAllPoints()
                if grow == "DOWN" then
                    frame:SetPoint("TOP", prevFrame, "BOTTOM", 0, -spacing)
                elseif grow == "UP" then
                    frame:SetPoint("BOTTOM", prevFrame, "TOP", 0, spacing)
                elseif grow == "RIGHT" then
                    frame:SetPoint("LEFT", prevFrame, "RIGHT", spacing, 0)
                elseif grow == "LEFT" then
                    frame:SetPoint("RIGHT", prevFrame, "LEFT", -spacing, 0)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- INITIALIZE: Create all party frames
---------------------------------------------------------------------------
function QUI_PF:Initialize()
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    -- Don't create in raid (party frames are for 5-man groups)
    -- State drivers handle visibility, but we skip creation in raid

    -- Create player frame if showPlayer is enabled
    if settings.showPlayer then
        self.frames["partyplayer"] = CreatePartyFrame("player", "partyplayer", 0)
    end

    -- Create party1..party4
    for i = 1, MAX_PARTY do
        local partyUnit = "party" .. i
        self.frames[partyUnit] = CreatePartyFrame(partyUnit, partyUnit, i)
    end

    -- Layout frames
    LayoutFrames()

    -- Initial update after a delay (DB values may not be available immediately)
    C_Timer.After(1.5, function() self:RefreshAll() end)
end

---------------------------------------------------------------------------
-- REFRESH: Update all frames (data only)
---------------------------------------------------------------------------
function QUI_PF:RefreshAll()
    for _, frame in pairs(self.frames) do
        if frame and frame.unit then
            UpdateFrame(frame)
        end
    end
end

---------------------------------------------------------------------------
-- APPLY SETTINGS: Update visual properties on existing frames (live edit)
-- Called from options GUI to reflect changes without /reload
---------------------------------------------------------------------------
local function ApplySettingsToFrame(frame)
    if not frame then return end
    local settings = GetSettings()
    if not settings then return end

    -- Size
    local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 72, frame))
                  or (settings.width or 72)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 36, frame))
                   or (settings.height or 36)
    frame:SetSize(width, height)

    -- Border & backdrop
    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0
    local bgColor = settings.bgColor or { 0.1, 0.1, 0.1, 0.9 }

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.9)
    if borderSize > 0 then
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- Health bar anchors (adjust for power bar)
    if frame.healthBar then
        frame.healthBar:ClearAllPoints()
        frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
        if settings.showPowerBar and frame.powerBar then
            local pbHeight = QUICore:Pixels(settings.powerBarHeight or 3, frame)
            frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + pbHeight)
        else
            frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        end
        frame.healthBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    end

    -- Power bar
    if frame.powerBar then
        if settings.showPowerBar then
            local pbHeight = QUICore:Pixels(settings.powerBarHeight or 3, frame)
            frame.powerBar:ClearAllPoints()
            frame.powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
            frame.powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
            frame.powerBar:SetHeight(pbHeight)
            frame.powerBar:SetStatusBarTexture(GetTexturePath(settings.texture))
            frame.powerBar:Show()
        else
            frame.powerBar:Hide()
        end
    end

    -- Name text
    if frame.nameText then
        local fontPath = GetFontPath() or "Fonts\\FRIZQT__.TTF"
        local fontOutline = GetFontOutline() or "OUTLINE"
        frame.nameText:SetFont(fontPath, settings.nameFontSize or 11, fontOutline)
        frame.nameText:ClearAllPoints()
        local nameAnchor = settings.nameAnchor or "CENTER"
        frame.nameText:SetPoint(nameAnchor, frame.healthBar, nameAnchor,
                                settings.nameOffsetX or 0, settings.nameOffsetY or 0)
        local justify = (nameAnchor == "LEFT" or nameAnchor == "TOPLEFT" or nameAnchor == "BOTTOMLEFT") and "LEFT"
                     or (nameAnchor == "RIGHT" or nameAnchor == "TOPRIGHT" or nameAnchor == "BOTTOMRIGHT") and "RIGHT"
                     or "CENTER"
        frame.nameText:SetJustifyH(justify)
        if settings.showName then
            frame.nameText:Show()
        else
            frame.nameText:Hide()
        end
        -- Update name color
        if settings.nameUseClassColor and UnitExists(frame.unit) then
            local r, g, b = GetUnitClassColor(frame.unit)
            frame.nameText:SetTextColor(r, g, b, 1)
        else
            local c = settings.nameColor or { 1, 1, 1, 1 }
            frame.nameText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
    end

    -- Health text
    if frame.healthText then
        local fontPath = GetFontPath() or "Fonts\\FRIZQT__.TTF"
        local fontOutline = GetFontOutline() or "OUTLINE"
        frame.healthText:SetFont(fontPath, settings.healthFontSize or 10, fontOutline)
        frame.healthText:ClearAllPoints()
        local hAnchor = settings.healthAnchor or "BOTTOM"
        frame.healthText:SetPoint(hAnchor, frame.healthBar, hAnchor,
                                  settings.healthOffsetX or 0, settings.healthOffsetY or 2)
        if settings.showHealth then
            frame.healthText:Show()
        else
            frame.healthText:Hide()
        end
    end

    -- Role icon
    if frame.roleIcon then
        frame.roleIcon:SetSize(settings.roleIconSize or 10, settings.roleIconSize or 10)
        frame.roleIcon:ClearAllPoints()
        local roleAnchor = settings.roleIconAnchor or "TOPLEFT"
        frame.roleIcon:SetPoint(roleAnchor, frame.healthBar, roleAnchor,
                                settings.roleIconOffsetX or 1, settings.roleIconOffsetY or -1)
    end

    -- Leader icon
    if frame.leaderIcon then
        local ldrSettings = settings.leaderIcon or {}
        frame.leaderIcon:SetSize(ldrSettings.size or 12, ldrSettings.size or 12)
        frame.leaderIcon:ClearAllPoints()
        local ldrAnchor = ldrSettings.anchor or "TOPRIGHT"
        frame.leaderIcon:SetPoint(ldrAnchor, frame.healthBar, ldrAnchor,
                                  ldrSettings.xOffset or -1, ldrSettings.yOffset or -1)
    end

    -- Target marker
    if frame.targetMarker then
        local tmSettings = settings.targetMarker or {}
        frame.targetMarker:SetSize(tmSettings.size or 14, tmSettings.size or 14)
        frame.targetMarker:ClearAllPoints()
        local tmAnchor = tmSettings.anchor or "TOP"
        frame.targetMarker:SetPoint(tmAnchor, frame.healthBar, tmAnchor,
                                    tmSettings.xOffset or 0, tmSettings.yOffset or -2)
    end

    -- Dispel border size
    if frame.dispelBorder then
        local dispelBorderPx = settings.dispelHighlight and settings.dispelHighlight.borderSize or 2
        local dispelBorderSize = QUICore:Pixels(dispelBorderPx, frame)
        frame.dispelBorder:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = dispelBorderSize,
        })
    end

    -- Status text font
    if frame.statusText then
        frame.statusText:SetFont(GetFontPath() or "Fonts\\FRIZQT__.TTF", settings.nameFontSize or 11, "OUTLINE")
    end
end

function QUI_PF:ApplySettings()
    local settings = GetSettings()
    if not settings then return end

    -- If disabled and no frames, nothing to do
    if not settings.enabled and not next(self.frames) then return end

    -- If no frames exist yet, create them (first time enabling from options)
    if not next(self.frames) and settings.enabled then
        self:Initialize()
    end

    -- If still no frames after init attempt, bail
    if not next(self.frames) then return end

    -- Apply visual settings to all frames
    for _, frame in pairs(self.frames) do
        if frame then
            ApplySettingsToFrame(frame)
        end
    end

    -- Re-layout (spacing, grow direction, position)
    -- Reposition anchor frame
    local anchorKey = settings.showPlayer and "partyplayer" or "party1"
    local anchorFrame = self.frames[anchorKey]
    if anchorFrame then
        anchorFrame:ClearAllPoints()
        if QUICore.SetSnappedPoint then
            QUICore:SetSnappedPoint(anchorFrame, "CENTER", UIParent, "CENTER",
                                     settings.offsetX or -400, settings.offsetY or 0)
        else
            anchorFrame:SetPoint("CENTER", UIParent, "CENTER",
                               settings.offsetX or -400, settings.offsetY or 0)
        end
    end

    LayoutFrames()

    -- If in preview mode, re-apply preview data
    if self.previewMode then
        self:ShowPreview()
    else
        -- Update data on all frames
        self:RefreshAll()
    end
end

---------------------------------------------------------------------------
-- REBUILD: Destroy and recreate all frames (for structural changes)
-- Used when showPlayer or showPowerBar toggles change
---------------------------------------------------------------------------
function QUI_PF:Rebuild()
    if InCombatLockdown() then return end
    local wasPreview = self.previewMode

    -- Destroy existing frames
    for key, frame in pairs(self.frames) do
        if frame then
            UnregisterStateDriver(frame, "visibility")
            frame:UnregisterAllEvents()
            frame:SetScript("OnUpdate", nil)
            frame:SetScript("OnEvent", nil)
            frame:Hide()
            -- Remove from Clique
            if _G.ClickCastFrames then
                _G.ClickCastFrames[frame] = nil
            end
        end
    end
    self.frames = {}
    self.previewMode = false

    -- Recreate
    local settings = GetSettings()
    if not settings or not settings.enabled then return end

    if settings.showPlayer then
        self.frames["partyplayer"] = CreatePartyFrame("player", "partyplayer", 0)
    end
    for i = 1, MAX_PARTY do
        self.frames["party" .. i] = CreatePartyFrame("party" .. i, "party" .. i, i)
    end

    LayoutFrames()

    -- Register with Clique
    local _, cliqueLoaded = C_AddOns.IsAddOnLoaded("Clique")
    if cliqueLoaded then
        _G.ClickCastFrames = _G.ClickCastFrames or {}
        for _, frame in pairs(self.frames) do
            if frame then _G.ClickCastFrames[frame] = true end
        end
    end

    -- Restore preview if it was active
    if wasPreview then
        self:ShowPreview()
    else
        self:RefreshAll()
    end
end

---------------------------------------------------------------------------
-- PREVIEW MODE (for settings GUI / edit mode)
---------------------------------------------------------------------------
function QUI_PF:ShowPreview()
    self.previewMode = true
    local settings = GetSettings()
    if not settings then return end

    -- Ensure frames exist
    if not next(self.frames) then
        -- Create temporary frames for preview
        if settings.showPlayer then
            self.frames["partyplayer"] = CreatePartyFrame("player", "partyplayer", 0)
        end
        for i = 1, MAX_PARTY do
            self.frames["party" .. i] = CreatePartyFrame("party" .. i, "party" .. i, i)
        end
        LayoutFrames()
    end

    -- Show all frames with fake data
    local fakeNames = {"Tank", "Healer", "DPS1", "DPS2", "You"}
    local fakeClasses = {"WARRIOR", "PRIEST", "ROGUE", "MAGE", "PALADIN"}
    local fakeHealth = {85, 60, 100, 45, 75}
    local fakeRoles = {"TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER"}

    local idx = 0
    local orderedKeys = {}
    if settings.showPlayer and self.frames["partyplayer"] then
        table.insert(orderedKeys, "partyplayer")
    end
    for i = 1, MAX_PARTY do
        if self.frames["party" .. i] then
            table.insert(orderedKeys, "party" .. i)
        end
    end

    for _, key in ipairs(orderedKeys) do
        idx = idx + 1
        local frame = self.frames[key]
        if frame then
            if not InCombatLockdown() then
                UnregisterStateDriver(frame, "visibility")
            end
            frame:Show()

            -- Fake health
            frame.healthBar:SetMinMaxValues(0, 100)
            frame.healthBar:SetValue(fakeHealth[idx] or 75)

            -- Fake class color
            local classColor = RAID_CLASS_COLORS[fakeClasses[idx] or "WARRIOR"]
            if classColor and settings.useClassColor then
                frame.healthBar:SetStatusBarColor(classColor.r, classColor.g, classColor.b, 1)
            end

            -- Fake name
            if frame.nameText then
                frame.nameText:SetText(TruncateName(fakeNames[idx] or "Party", settings.maxNameLength or 6))
                frame.nameText:Show()
            end

            -- Fake health text
            if frame.healthText and settings.showHealth then
                frame.healthText:SetText((fakeHealth[idx] or 75) .. "%")
                frame.healthText:Show()
            end

            -- Fake role
            if frame.roleIcon and settings.showRoleIcon then
                local role = fakeRoles[idx]
                local atlas = role and ROLE_ATLAS[role]
                if atlas then
                    frame.roleIcon:SetAtlas(atlas)
                    frame.roleIcon:Show()
                end
            end

            -- Fake power
            if frame.powerBar then
                frame.powerBar:SetMinMaxValues(0, 100)
                frame.powerBar:SetValue(80)
                frame.powerBar:SetStatusBarColor(0, 0.5, 1, 1)
                frame.powerBar:Show()
            end

            -- Hide absorbs/heal prediction/dispel/status in preview
            if frame.absorbBar then frame.absorbBar:Hide() end
            if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
            if frame.healPredictionBar then frame.healPredictionBar:Hide() end
            if frame.dispelBorder then frame.dispelBorder:Hide() end
            if frame.statusText then frame.statusText:Hide() end
            if frame.targetMarker then frame.targetMarker:Hide() end
            if frame.debuffIcons then
                for _, icon in ipairs(frame.debuffIcons) do icon:Hide() end
            end
        end
    end
end

function QUI_PF:HidePreview()
    self.previewMode = false
    local settings = GetSettings()

    for key, frame in pairs(self.frames) do
        if frame then
            -- Restore state drivers
            if not InCombatLockdown() then
                if key == "partyplayer" then
                    RegisterStateDriver(frame, "visibility", "[group] show; hide")
                else
                    RegisterStateDriver(frame, "visibility", "[@" .. key .. ",exists] show; hide")
                end
            end
            -- Refresh with real data
            if UnitExists(frame.unit) then
                UpdateFrame(frame)
            end
        end
    end
end

---------------------------------------------------------------------------
-- EDIT MODE: Drag-to-move support
---------------------------------------------------------------------------
function QUI_PF:EnableEditMode()
    local settings = GetSettings()
    if not settings then return end

    -- Get the first frame (anchor frame)
    local anchorKey = settings.showPlayer and "partyplayer" or "party1"
    local anchorFrame = self.frames[anchorKey]
    if not anchorFrame then return end

    -- Show preview if not in group
    if not IsInGroup() then
        self:ShowPreview()
    end

    -- Enable dragging on anchor frame
    anchorFrame:EnableMouse(true)
    anchorFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    anchorFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:StopMovingOrSizing()
            -- Save new position
            local _, _, _, x, y = self:GetPoint()
            settings.offsetX = x
            settings.offsetY = y
        end
    end)
end

function QUI_PF:DisableEditMode()
    local settings = GetSettings()
    if not settings then return end

    local anchorKey = settings.showPlayer and "partyplayer" or "party1"
    local anchorFrame = self.frames[anchorKey]
    if not anchorFrame then return end

    anchorFrame:SetScript("OnMouseDown", nil)
    anchorFrame:SetScript("OnMouseUp", nil)

    if self.previewMode then
        self:HidePreview()
    end
end

---------------------------------------------------------------------------
-- EVENT: Addon loaded
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.6, function()
            QUI_PF:Initialize()
            -- Register with Clique
            C_Timer.After(0.5, function()
                local _, cliqueLoaded = C_AddOns.IsAddOnLoaded("Clique")
                if cliqueLoaded then
                    _G.ClickCastFrames = _G.ClickCastFrames or {}
                    for _, frame in pairs(QUI_PF.frames) do
                        if frame then _G.ClickCastFrames[frame] = true end
                    end
                end
            end)
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.0, function()
            QUI_PF:RefreshAll()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if QUI_PF.pendingInitialize then
            QUI_PF.pendingInitialize = false
            QUI_PF:Initialize()
        end
    end
end)

---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTION (for GUI)
---------------------------------------------------------------------------
_G.QUI_RefreshPartyFrames = function()
    QUI_PF:ApplySettings()
end

_G.QUI_RebuildPartyFrames = function()
    QUI_PF:Rebuild()
end

_G.QUI_ShowPartyFramePreview = function()
    QUI_PF:ShowPreview()
end

_G.QUI_HidePartyFramePreview = function()
    QUI_PF:HidePreview()
end
