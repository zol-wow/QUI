--[[
    QUI Unit Frames - New Implementation
    Creates secure unit frames for Player, Target, ToT, Pet, Focus, Boss
    Features: Dark mode, class colors, power bars, castbars, preview mode
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue
local GetDB = Helpers.CreateDBGetter("quiUnitFrames")

local function GetCore()
    return (_G.QUI and _G.QUI.QUICore) or ns.Addon
end

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_UF = {}
ns.QUI_UnitFrames = QUI_UF

-- Frame references
QUI_UF.frames = {}
QUI_UF.castbars = {}
QUI_UF.previewMode = {}
QUI_UF.auraPreviewMode = {}  -- Tracks buff/debuff preview state (keyed by "unitKey_buff" or "unitKey_debuff")

-- Reference to castbar module
local QUI_Castbar = ns.QUI_Castbar

-- Edit Mode: Slider registry for real-time sync during drag
-- Format: { unitKey = { x = sliderRef, y = sliderRef, coordText = fontStringRef } }
QUI_UF.editModeSliders = {}

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local POWER_COLORS = {
    [0] = { 0, 0.50, 1 },       -- Mana (blue)
    [1] = { 1, 0, 0 },          -- Rage (red)
    [2] = { 1, 0.5, 0.25 },     -- Focus (orange)
    [3] = { 1, 1, 0 },          -- Energy (yellow)
    [6] = { 0, 0.82, 1 },       -- Runic Power (light blue)
    [8] = { 0.3, 0.52, 0.9 },   -- Lunar Power
    [11] = { 0, 0.5, 1 },       -- Maelstrom
    [13] = { 0.4, 0, 0.8 },     -- Insanity (purple)
}

-- Preview aura data for buff/debuff preview mode (4 icons with varied stacks)
local PREVIEW_AURAS = {
    buffs = {
        {icon = "Interface\\Icons\\spell_nature_regenerate", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_holy_powerwordshield", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_nature_lightningshield", stacks = 3, duration = 10},
        {icon = "Interface\\Icons\\ability_warrior_battleshout", stacks = 5, duration = 10},
    },
    debuffs = {
        {icon = "Interface\\Icons\\spell_shadow_shadowwordpain", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_shadow_mindblast", stacks = 0, duration = 10},
        {icon = "Interface\\Icons\\spell_nature_slow", stacks = 2, duration = 10},
        {icon = "Interface\\Icons\\spell_shadow_shadesofdarkness", stacks = 5, duration = 10},
    }
}

---------------------------------------------------------------------------
-- HELPER: Health percent with 12.01 API compatibility
-- API signature changed: old (unit, scaleTo100) -> new (unit, usePredicted, curve)
---------------------------------------------------------------------------
local tocVersion = tonumber((select(4, GetBuildInfo()))) or 0

local function GetHealthPct(unit, usePredicted)
    if tocVersion >= 120000 and type(UnitHealthPercent) == "function" then
        local ok, pct
        -- 12.01+: Use curve parameter (new API)
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitHealthPercent, unit, usePredicted, CurveConstants.ScaleTo100)
        end
        -- Fallback for older builds
        if not ok or pct == nil then
            ok, pct = pcall(UnitHealthPercent, unit, usePredicted)
        end
        if ok and pct ~= nil then
            return pct
        end
    end
    -- Manual calculation fallback
    if UnitHealth and UnitHealthMax then
        local cur = UnitHealth(unit)
        local max = UnitHealthMax(unit)
        if cur and max and max > 0 then
            -- Use pcall to handle Midnight secret values from UnitHealth()
            local ok, pct = pcall(function() return (cur / max) * 100 end)
            if ok then return pct end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- HELPER: Power percent with 12.01 API compatibility
-- API signature changed: old (unit, powerType, scaleTo100) -> new (unit, powerType, usePredicted, curve)
-- NOTE: When powerType is nil, API uses unit's primary/displayed power
---------------------------------------------------------------------------
local function GetPowerPct(unit, powerType, usePredicted)
    -- Don't default powerType - let API use unit's primary power when nil
    if tocVersion >= 120000 and type(UnitPowerPercent) == "function" then
        local ok, pct
        -- 12.01+: Use curve parameter (new API)
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted, CurveConstants.ScaleTo100)
        end
        -- Fallback for older builds
        if not ok or pct == nil then
            ok, pct = pcall(UnitPowerPercent, unit, powerType, usePredicted)
        end
        if ok and pct ~= nil then
            return pct
        end
    end
    -- Manual calculation fallback (may fail with secret values)
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
-- HELPER: Get database
---------------------------------------------------------------------------
-- GetDB is imported from utils.lua via Helpers at the top of this file

local function GetGeneralSettings()
    -- Get global general settings (font, texture, etc.) from main db
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        return QUICore.db.profile.general
    end
    return nil
end

local function GetUnitSettings(unit)
    local db = GetDB()
    return db and db[unit]
end

---------------------------------------------------------------------------
-- HELPER: Pixel-perfect scaling (uses QUICore:Scale if available)
---------------------------------------------------------------------------
local function Scale(x, frame)
    if QUICore and QUICore.Scale then
        return QUICore:Scale(x, frame)
    end
    return x
end

---------------------------------------------------------------------------
-- HELPER: Unit tooltip display
---------------------------------------------------------------------------
local function ShowUnitTooltip(frame)
    local ufdb = GetDB()
    local general = ufdb and ufdb.general

    -- Check if tooltips are enabled
    if not general or general.showTooltips == false then
        return
    end

    -- Determine the unit
    local unit = frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
    if not unit then
        -- Try parent for child frames (healthBar, powerBar, etc.)
        local parent = frame:GetParent()
        if parent then
            unit = parent.unit or (parent.GetAttribute and parent:GetAttribute("unit"))
        end
    end

    if not unit or not UnitExists(unit) then return end

    -- Position and show tooltip
    GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
end

local function HideUnitTooltip()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- HELPER: Get font path from LSM
---------------------------------------------------------------------------
local function GetFontPath()
    return Helpers.GetGeneralFont()
end

---------------------------------------------------------------------------
-- HELPER: Get font outline from general settings
---------------------------------------------------------------------------
local function GetFontOutline()
    return Helpers.GetGeneralFontOutline()
end

---------------------------------------------------------------------------
-- HELPER: Get texture path from LSM (falls back to general default)
---------------------------------------------------------------------------
local function GetTexturePath(textureName)
    local name = textureName
    -- If no specific texture, use general default
    if not name or name == "" then
        local general = GetGeneralSettings()
        name = general and general.texture or "Quazii"
    end
    return LSM:Fetch("statusbar", name) or "Interface\\Buttons\\WHITE8x8"
end

local function GetAbsorbTexturePath(textureName)
    local name = textureName
    if not name or name == "" then
        name = "QUI Stripes"
    end
    return LSM:Fetch("statusbar", name) or "Interface\\AddOns\\QUI\\assets\\absorb_stripe"
end

---------------------------------------------------------------------------
-- HELPER: Get class color for a unit
---------------------------------------------------------------------------
local function GetUnitClassColor(unit)
    if not UnitExists(unit) then
        return 0.5, 0.5, 0.5, 1
    end

    -- Only use class color for actual players
    local isPlayer = UnitIsPlayer(unit)
    if isPlayer then
        local _, class = UnitClass(unit)
        if class then
            local color = RAID_CLASS_COLORS[class]
            if color then
                return color.r, color.g, color.b, 1
            end
        end
    end

    -- NPCs use reaction color
    local reaction = UnitReaction(unit, "player")
    if reaction then
        if reaction >= 5 then
            return 0.2, 0.8, 0.2, 1  -- Friendly (green)
        elseif reaction == 4 then
            return 1, 1, 0.2, 1      -- Neutral (yellow)
        else
            return 0.8, 0.2, 0.2, 1  -- Hostile (red)
        end
    end

    return 0.5, 0.5, 0.5, 1
end

---------------------------------------------------------------------------
-- HELPER: Get anchor point and justification for text
-- Maps anchor setting to SetPoint anchor and JustifyH value
---------------------------------------------------------------------------
local function GetTextAnchorInfo(anchor)
    local anchorMap = {
        TOPLEFT     = { point = "TOPLEFT",     justify = "LEFT" },
        TOP         = { point = "TOP",         justify = "CENTER" },
        TOPRIGHT    = { point = "TOPRIGHT",    justify = "RIGHT" },
        LEFT        = { point = "LEFT",        justify = "LEFT" },
        CENTER      = { point = "CENTER",      justify = "CENTER" },
        RIGHT       = { point = "RIGHT",       justify = "RIGHT" },
        BOTTOMLEFT  = { point = "BOTTOMLEFT",  justify = "LEFT" },
        BOTTOM      = { point = "BOTTOM",      justify = "CENTER" },
        BOTTOMRIGHT = { point = "BOTTOMRIGHT", justify = "RIGHT" },
    }
    return anchorMap[anchor] or anchorMap.LEFT
end

---------------------------------------------------------------------------
-- HELPER: Truncate name to max length (UTF-8 safe)
---------------------------------------------------------------------------
local function TruncateName(name, maxLength)
    if not name or type(name) ~= "string" then return name end
    if not maxLength or maxLength <= 0 then return name end

    -- If name is secret return shortened name, but not utf-8 safe
    if IsSecretValue(name) then
        return string.format("%." .. maxLength .. "s", name)
    end

    -- ok to get length and shorten utf-8 safe if too long
    local lenOk, nameLen = pcall(function() return #name end)
    if not lenOk then
        -- if get length somehow still fails return
        return string.format("%." .. maxLength .. "s", name)
    end

    -- short enough
    if nameLen <= maxLength then
        return name
    end

    -- UTF-8 safe truncation
    local byte = string.byte
    local i = 1   -- byte index
    local c = 0   -- character count
    while i <= nameLen and c < maxLength do
        c = c + 1
        local b = byte(name, i)
        if b < 0x80 then
            i = i + 1          -- 1-byte sequence
        elseif b < 0xE0 then
            i = i + 2          -- 2-byte sequence
        elseif b < 0xF0 then
            i = i + 3          -- 3-byte sequence
        else
            i = i + 4          -- 4-byte sequence
        end
    end

    local subOk, truncated = pcall(string.sub, name, 1, i - 1)
    if subOk and truncated then
        return truncated
    end

    -- Last resort fallback (works with secret values in M+/dungeons)
    return string.format("%." .. maxLength .. "s", name)
end

---------------------------------------------------------------------------
-- HELPER: Format health text based on display style
---------------------------------------------------------------------------
local function FormatHealthText(hp, hpPct, style, divider, maxHp)
    style = style or "both"
    divider = divider or " | "

    -- Use pcall to handle Midnight secret values from UnitHealth()
    -- Prefer AbbreviateNumbers (Midnight API) over AbbreviateLargeNumbers (legacy)
    local success, hpStr = pcall(function()
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        return abbr and abbr(hp) or tostring(hp)
    end)
    if not success then hpStr = "" end

    if style == "percent" then
        if hpPct then
            local success, result = pcall(function() return string.format("%d%%", hpPct) end)
            return success and result or ""
        end
        return ""
    elseif style == "absolute" then
        return hpStr or ""
    elseif style == "both" then
        if hpPct then
            local success, result = pcall(function() return string.format("%s%s%d%%", hpStr or "", divider, hpPct) end)
            return success and result or hpStr or ""
        end
        return hpStr or ""
    elseif style == "both_reverse" then
        if hpPct then
            local success, result = pcall(function() return string.format("%d%%%s%s", hpPct, divider, hpStr or "") end)
            return success and result or hpStr or ""
        end
        return hpStr or ""
    elseif style == "missing_percent" then
        if hpPct then
            -- Use pcall to handle Midnight secret values
            local success, missing = pcall(function() return 100 - hpPct end)
            if not success then return "" end
            if missing > 0 then
                return string.format("-%d%%", missing)
            end
            return "0%"
        end
        return ""
    elseif style == "missing_value" then
        if hp and maxHp then
            -- Use pcall to handle Midnight secret values from UnitHealth()
            local success, missing = pcall(function() return maxHp - hp end)
            if not success then return "" end
            if missing > 0 then
                local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
                local missingStr = abbr and abbr(missing) or tostring(missing)
                return "-" .. missingStr
            end
            return "0"
        end
        return ""
    end

    return hpStr or ""
end

---------------------------------------------------------------------------
-- HELPER: Format power text based on display style
-- NOTE: powerPct should be pre-calculated using GetPowerPct() to handle secret values
-- All operations wrapped in pcall to ensure we NEVER return secret values
---------------------------------------------------------------------------
local function FormatPowerText(power, powerPct, style, divider)
    style = style or "percent"
    divider = divider or " | "

    -- Format current power value (pcall for secret value protection)
    -- Prefer AbbreviateNumbers (Midnight API) over AbbreviateLargeNumbers (legacy)
    local powerStr = ""
    pcall(function()
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        powerStr = abbr and abbr(power) or tostring(power)
    end)

    -- All return paths wrapped in pcall to catch secret values in string operations
    local result = ""

    if style == "percent" then
        local fmtOk = pcall(function()
            if powerPct then
                result = string.format("%d%%", powerPct)
            end
        end)
        if not fmtOk then result = "" end
    elseif style == "current" then
        local fmtOk = pcall(function()
            result = powerStr or ""
        end)
        if not fmtOk then result = "" end
    elseif style == "both" then
        local fmtOk = pcall(function()
            if powerPct then
                result = string.format("%s%s%d%%", powerStr or "", divider, powerPct)
            else
                result = powerStr or ""
            end
        end)
        if not fmtOk then result = "" end
    else
        local fmtOk = pcall(function()
            result = powerStr or ""
        end)
        if not fmtOk then result = "" end
    end

    return result
end

---------------------------------------------------------------------------
-- HELPER: Get hostility/reaction color for a unit (based on reaction to player)
---------------------------------------------------------------------------
local function GetUnitHostilityColor(unit)
    if not UnitExists(unit) then
        return 0.5, 0.5, 0.5, 1
    end

    -- Get custom hostility colors from DB
    local db = GetDB()
    local general = db and db.general

    local reaction = UnitReaction(unit, "player")
    if type(reaction) == "number" then
        if reaction >= 5 then
            local c = general and general.hostilityColorFriendly or { 0.2, 0.8, 0.2, 1 }
            return c[1], c[2], c[3], c[4] or 1
        elseif reaction == 4 then
            local c = general and general.hostilityColorNeutral or { 1, 1, 0.2, 1 }
            return c[1], c[2], c[3], c[4] or 1
        else
            local c = general and general.hostilityColorHostile or { 0.8, 0.2, 0.2, 1 }
            return c[1], c[2], c[3], c[4] or 1
        end
    end

    -- Default to gray if we can't determine reaction
    return 0.5, 0.5, 0.5, 1
end

---------------------------------------------------------------------------
-- HELPER: Get health bar color based on settings
-- Logic: 
--   1. If ClassColor enabled AND unit is a player -> use class color
--   2. If HostilityColor enabled -> use reaction color (for NPCs or all units)
--   3. Otherwise -> use custom color
---------------------------------------------------------------------------
local function GetHealthBarColor(unit, settings)
    if not UnitExists(unit) then
        return 0.5, 0.5, 0.5, 1
    end

    -- Get global settings from MAIN profile (not quiUnitFrames sub-table)
    local general = GetGeneralSettings()

    -- Determine if class color should be used
    -- Per-unit setting takes precedence; global is fallback only if per-unit is nil
    local useClassColor = false
    if settings and settings.useClassColor ~= nil then
        useClassColor = settings.useClassColor
    else
        useClassColor = general and general.defaultUseClassColor
    end

    if useClassColor then
        local isPlayer = UnitIsPlayer(unit)
        if type(isPlayer) == "boolean" and isPlayer then
            -- Unit is a player - use their class color
            local _, class = UnitClass(unit)
            if type(class) == "string" then
                local color = RAID_CLASS_COLORS[class]
                if color then
                    return color.r, color.g, color.b, 1
                end
            end
        else
            -- Unit is not a player (pet, NPC, etc.) - use owner's class color for pets
            local petCheck = UnitIsUnit(unit, "pet")
            local playerPetCheck = UnitIsUnit(unit, "playerpet")
            local isPet = (not IsSecretValue(petCheck) and petCheck == true) or (not IsSecretValue(playerPetCheck) and playerPetCheck == true)
            if isPet then
                -- Pet: use player's class color
                local _, class = UnitClass("player")
                if type(class) == "string" then
                    local color = RAID_CLASS_COLORS[class]
                    if color then
                        return color.r, color.g, color.b, 1
                    end
                end
            end
        end
    end

    -- Check HostilityColor - applies to NPCs
    if settings and settings.useHostilityColor then
        local reaction = UnitReaction(unit, "player")
        if type(reaction) == "number" then
            if reaction >= 5 then
                local c = general and general.hostilityColorFriendly or { 0.2, 0.8, 0.2, 1 }
                return c[1], c[2], c[3], c[4] or 1
            elseif reaction == 4 then
                local c = general and general.hostilityColorNeutral or { 1, 1, 0.2, 1 }
                return c[1], c[2], c[3], c[4] or 1
            else
                local c = general and general.hostilityColorHostile or { 0.8, 0.2, 0.2, 1 }
                return c[1], c[2], c[3], c[4] or 1
            end
        end
    end

    -- Use per-unit customHealthColor if available, otherwise fall back to global
    if settings and settings.customHealthColor then
        local c = settings.customHealthColor
        return c[1], c[2], c[3], c[4] or 1
    end

    -- Fallback to GLOBAL defaultHealthColor (from Colors tab)
    local c = general and general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
    return c[1], c[2], c[3], c[4] or 1
end

---------------------------------------------------------------------------
-- HELPER: Get power color for a unit
---------------------------------------------------------------------------
local function GetUnitPowerColor(unit)
    local powerType = UnitPowerType(unit)
    local color = POWER_COLORS[powerType]
    if color then
        return color[1], color[2], color[3], 1
    end
    return 0.5, 0.5, 0.5, 1
end


---------------------------------------------------------------------------
-- UPDATE: Health bar (no comparisons, just pass values directly)
---------------------------------------------------------------------------
local function UpdateHealth(frame)
    if not frame or not frame.unit or not frame.healthBar then return end
    local unit = frame.unit
    
    -- Don't update if unit doesn't exist
    if not UnitExists(unit) then
        return
    end
    
    -- Get health values directly - StatusBar can handle secret values
    -- The key is to NOT do any comparisons or arithmetic on these values
    local hp = UnitHealth(unit)
    local maxHP = UnitHealthMax(unit)
    
    -- Pass directly to StatusBar - it handles secret values gracefully
    frame.healthBar:SetMinMaxValues(0, maxHP or 1)
    frame.healthBar:SetValue(hp or 0)
    
    -- Update health text using new display style system
    if frame.healthText then
        local settings = GetUnitSettings(frame.unitKey)

        -- Check if health text is disabled
        if settings and settings.showHealth == false then
            frame.healthText:Hide()
        else
            -- Determine display style (backwards compatible with old settings)
            local displayStyle = settings and settings.healthDisplayStyle
            if not displayStyle then
                -- Backwards compatibility: derive style from old showHealthAbsolute/showHealthPercent
                local showAbsolute = settings and settings.showHealthAbsolute
                local showPercent = settings and settings.showHealthPercent
                if showPercent == nil then showPercent = true end

                if showAbsolute and showPercent then
                    displayStyle = "both"
                elseif showAbsolute then
                    displayStyle = "absolute"
                elseif showPercent then
                    displayStyle = "percent"
                else
                    displayStyle = "percent"
                end
            end

            local divider = settings and settings.healthDivider or " | "

            if hp then
                local hpPct = GetHealthPct(unit, false)
                local healthStr = FormatHealthText(hp, hpPct, displayStyle, divider, maxHP)
                frame.healthText:SetText(healthStr)
                frame.healthText:Show()
            else
                frame.healthText:SetText("")
            end
        end
    end
    
    -- Update health bar color using unit-specific settings
    local general = GetGeneralSettings()
    local settings = GetUnitSettings(frame.unitKey)

    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        local r, g, b, a = GetHealthBarColor(frame.unit, settings)
        frame.healthBar:SetStatusBarColor(r, g, b, a)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Absorb shields (attached + overflow mode to prevent left overflow)
-- Uses CreateUnitHealPredictionCalculator to detect when absorb would overflow
---------------------------------------------------------------------------
local function UpdateAbsorbs(frame)
    if not frame or not frame.unit or not frame.healthBar then return end
    if not frame.absorbBar then return end

    local unit = frame.unit
    local settings = GetUnitSettings(frame.unitKey)

    -- Check if enabled
    if not settings or not settings.absorbs or settings.absorbs.enabled == false then
        frame.absorbBar:Hide()
        if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
        if frame.healAbsorbBar then frame.healAbsorbBar:Hide() end
        return
    end

    if not UnitExists(unit) then
        frame.absorbBar:Hide()
        if frame.absorbOverflowBar then frame.absorbOverflowBar:Hide() end
        if frame.healAbsorbBar then frame.healAbsorbBar:Hide() end
        return
    end

    -- Get values (StatusBar handles secret values natively)
    local maxHealth = UnitHealthMax(unit)
    local absorbAmount = UnitGetTotalAbsorbs(unit)
    local healthTexture = frame.healthBar:GetStatusBarTexture()

    -- Get color settings upfront
    local absorbSettings = settings.absorbs or {}
    local c = absorbSettings.color or { 1, 1, 1 }
    local a = absorbSettings.opacity or 0.7

    -- Safe check for zero absorb using pcall (secret values throw on comparison)
    -- If absorbAmount is nil, treat as zero
    -- If comparison succeeds and equals 0, hide bars
    -- If comparison fails (secret value), let StatusBar handle it (renders 0-width for 0)
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

    -- For secret values OR non-zero absorbs, proceed with display
    do
        -- Create overflow bar once if needed (for overlay mode when absorb too big)
        -- Use stripe texture directly on StatusBar (no overlay) to avoid 1px sliver at 0 width
        local absorbTexturePath = GetAbsorbTexturePath(absorbSettings.texture)
        if not frame.absorbOverflowBar then
            frame.absorbOverflowBar = CreateFrame("StatusBar", nil, frame.healthBar)
            frame.absorbOverflowBar:SetStatusBarTexture(absorbTexturePath)
            local overflowBarTex = frame.absorbOverflowBar:GetStatusBarTexture()
            if overflowBarTex then
                overflowBarTex:SetHorizTile(false)
                overflowBarTex:SetVertTile(false)
                overflowBarTex:SetTexCoord(0, 1, 0, 1)
            end
            frame.absorbOverflowBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
            frame.absorbOverflowBar:EnableMouse(false)
        else
            -- Update texture if settings changed
            frame.absorbOverflowBar:SetStatusBarTexture(absorbTexturePath)
        end

        -- Create visibility helper textures once if needed (for secret boolean → alpha conversion)
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

        -- Get clamped absorbs using prediction calculator
        local clampedAbsorbs = absorbAmount  -- Default to full absorb if no calculator

        -- Default visibility: attached bar visible, overflow bar hidden
        frame.attachedVisHelper:SetAlpha(1)
        frame.overflowVisHelper:SetAlpha(0)

        if CreateUnitHealPredictionCalculator and unit then
            -- Create calculator once per frame
            if not frame.absorbCalculator then
                frame.absorbCalculator = CreateUnitHealPredictionCalculator()
            end
            local calc = frame.absorbCalculator

            -- Clamp mode 1 = Missing Health (clamp to space between current HP and 0)
            pcall(function() calc:SetDamageAbsorbClampMode(1) end)

            -- Populate calculator with unit data
            UnitGetDetailedHealPrediction(unit, nil, calc)

            -- Get clamped absorbs + isClamped boolean (both can be secret values)
            -- CRITICAL: We cannot do ANY tests on secret values - no if, or, and, comparisons
            local results = { pcall(function() return calc:GetDamageAbsorbs() end) }
            local success = results[1]
            -- results[2] = clampedValue (secret number), results[3] = isClamped (secret boolean)

            if success then
                -- Store clampedValue directly - it goes straight to StatusBar which handles secrets
                clampedAbsorbs = results[2]

                -- Use SetAlphaFromBoolean to convert secret boolean → alpha
                -- isClamped = true → attached alpha=0, overflow alpha=1
                -- isClamped = false → attached alpha=1, overflow alpha=0
                -- We pass the result directly to SetAlpha without reading it
                pcall(function()
                    frame.attachedVisHelper:SetAlphaFromBoolean(results[3], 0, 1)
                    frame.overflowVisHelper:SetAlphaFromBoolean(results[3], 1, 0)
                end)
            end
        end

        -- ALWAYS position and show BOTH bars - alpha controls which is visible
        -- No branching based on secret values - just pass alpha directly

        -- ATTACHED BAR: Starts where health ENDS, grows RIGHTWARD into empty space
        -- Anchor LEFT edge of absorb bar to RIGHT edge of health fill texture
        frame.absorbBar:ClearAllPoints()
        frame.absorbBar:SetPoint("LEFT", healthTexture, "RIGHT", 0, 0)
        frame.absorbBar:SetHeight(frame.healthBar:GetHeight())
        frame.absorbBar:SetWidth(frame.healthBar:GetWidth())  -- Full width available for absorb to fill
        frame.absorbBar:SetReverseFill(false)  -- Grows LEFT to RIGHT (rightward into empty space)
        frame.absorbBar:SetMinMaxValues(0, maxHealth or 1)
        frame.absorbBar:SetValue(clampedAbsorbs)  -- Clamped value (secret-safe via StatusBar)
        frame.absorbBar:SetStatusBarTexture(absorbTexturePath)  -- Apply texture from settings
        frame.absorbBar:SetStatusBarColor(c[1], c[2], c[3], a)  -- Apply color directly to StatusBar
        frame.absorbBar:SetAlpha(frame.attachedVisHelper:GetAlpha())  -- Secret alpha passed directly
        frame.absorbBar:Show()

        -- OVERFLOW BAR: Overlay mode - fills from RIGHT to LEFT
        -- Shows absorb starting from the RIGHT side (max health edge) going left
        frame.absorbOverflowBar:ClearAllPoints()
        frame.absorbOverflowBar:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
        frame.absorbOverflowBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
        frame.absorbOverflowBar:SetReverseFill(true)  -- CRITICAL: Fill from RIGHT to LEFT
        frame.absorbOverflowBar:SetMinMaxValues(0, maxHealth or 1)
        frame.absorbOverflowBar:SetValue(absorbAmount)  -- Full unclamped absorb value
        frame.absorbOverflowBar:SetStatusBarColor(c[1], c[2], c[3], a)  -- Apply color directly to StatusBar
        frame.absorbOverflowBar:SetAlpha(frame.overflowVisHelper:GetAlpha())  -- Secret alpha passed directly
        frame.absorbOverflowBar:Show()
    end

    -- Heal absorbs (fills from left, overlays on health)
    if frame.healAbsorbBar then
        local healAbsorbAmount = UnitGetTotalHealAbsorbs(unit)
        frame.healAbsorbBar:ClearAllPoints()
        frame.healAbsorbBar:SetPoint("TOPLEFT", frame.healthBar, "TOPLEFT", 0, 0)
        frame.healAbsorbBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
        frame.healAbsorbBar:SetReverseFill(false)  -- Fill from LEFT (eats into health)
        frame.healAbsorbBar:SetMinMaxValues(0, maxHealth or 1)
        frame.healAbsorbBar:SetValue(healAbsorbAmount or 0)

        -- Safe check for zero using pcall (secret values throw on comparison)
        local hideHealAbsorb = false
        if not healAbsorbAmount then
            hideHealAbsorb = true
        else
            local success, isZero = pcall(function() return healAbsorbAmount == 0 end)
            if success and isZero then
                hideHealAbsorb = true
            end
        end

        if hideHealAbsorb then
            frame.healAbsorbBar:Hide()
        else
            frame.healAbsorbBar:Show()
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Power bar (no comparisons, just pass values directly)
---------------------------------------------------------------------------
local function UpdatePower(frame)
    if not frame or not frame.unit or not frame.powerBar then return end
    local unit = frame.unit

    if not UnitExists(unit) then return end

    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.showPowerBar then
        frame.powerBar:Hide()
        return
    end

    -- Get power values directly - StatusBar can handle secret values
    local p = UnitPower(unit)
    local pMax = UnitPowerMax(unit)

    -- Pass directly to StatusBar - it handles secret values gracefully
    frame.powerBar:SetMinMaxValues(0, pMax or 1)
    frame.powerBar:SetValue(p or 0)
    frame.powerBar:Show()
    
    -- Set power color
    if settings.powerBarUsePowerColor ~= false then
        local r, g, b = GetUnitPowerColor(unit)
        frame.powerBar:SetStatusBarColor(r, g, b, 1)
    else
        local c = settings.powerBarColor or { 0, 0.5, 1, 1 }
        frame.powerBar:SetStatusBarColor(c[1], c[2], c[3], 1)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Power text (separate from power bar)
---------------------------------------------------------------------------
local function UpdatePowerText(frame)
    if not frame or not frame.unit then return end
    if not frame.powerText then return end

    local unit = frame.unit
    local settings = GetUnitSettings(frame.unitKey)

    -- Check if power text is enabled
    if not settings or not settings.showPowerText then
        frame.powerText:Hide()
        return
    end

    if not UnitExists(unit) then
        frame.powerText:Hide()
        return
    end

    -- Get power percentage using API that handles secret values
    -- NOTE: Don't pass explicit powerType - let API use unit's primary power
    local powerPct = GetPowerPct(unit)

    -- Get raw power value for "current" and "both" styles
    local power = UnitPower(unit)

    -- Format power text (pass pre-calculated percentage)
    local style = settings.powerTextFormat or "percent"
    local divider = settings.healthDivider or " | "
    local powerStr = FormatPowerText(power, powerPct, style, divider)

    -- The string comparison (powerStr ~= "") fails on secret-derived strings.
    -- BUT SetText() can still display them! So just try to set it directly.
    if powerStr then
        local setOk = pcall(function()
            frame.powerText:SetText(powerStr)
        end)

        if setOk then
            -- Apply color (master override OR per-unit setting)
            local general = GetGeneralSettings()
            if general and general.masterColorPowerText then
                -- MASTER OVERRIDE: Apply class/reaction color (NOT power type color)
                local r, g, b = GetUnitClassColor(unit)
                frame.powerText:SetTextColor(r, g, b, 1)
            elseif settings.powerTextUsePowerColor then
                -- Per-unit setting: Use power type color (mana blue, rage red, etc.)
                local r, g, b = GetUnitPowerColor(unit)
                frame.powerText:SetTextColor(r, g, b, 1)
            elseif settings.powerTextUseClassColor then
                -- Per-unit setting: Use class/reaction color
                local r, g, b = GetUnitClassColor(unit)
                frame.powerText:SetTextColor(r, g, b, 1)
            elseif settings.powerTextColor then
                -- Per-unit setting: Use custom color
                local c = settings.powerTextColor
                frame.powerText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            else
                -- Default: White text
                frame.powerText:SetTextColor(1, 1, 1, 1)
            end
            frame.powerText:Show()
        else
            frame.powerText:Hide()
        end
    else
        frame.powerText:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Status indicators (player only: rested, combat)
---------------------------------------------------------------------------
local function UpdateIndicators(frame)
    if not frame or frame.unitKey ~= "player" then return end
    local settings = GetUnitSettings("player")
    if not settings or not settings.indicators then return end

    local indSettings = settings.indicators

    -- Rested indicator
    if frame.restedIndicator then
        local rested = indSettings.rested
        if rested and rested.enabled and IsResting() then
            frame.restedIndicator:Show()
        else
            frame.restedIndicator:Hide()
        end
    end

    -- Combat indicator
    if frame.combatIndicator then
        local combat = indSettings.combat
        if combat and combat.enabled and UnitAffectingCombat("player") then
            frame.combatIndicator:Show()
        else
            frame.combatIndicator:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Stance/Form text (player only: shows current form, stance, or aura)
---------------------------------------------------------------------------
local function UpdateStance(frame)
    if not frame or frame.unitKey ~= "player" then return end
    if not frame.stanceText then return end

    local settings = GetUnitSettings("player")
    if not settings or not settings.indicators or not settings.indicators.stance then
        frame.stanceText:Hide()
        if frame.stanceIcon then frame.stanceIcon:Hide() end
        return
    end

    local stanceSettings = settings.indicators.stance
    if not stanceSettings.enabled then
        frame.stanceText:Hide()
        if frame.stanceIcon then frame.stanceIcon:Hide() end
        return
    end

    local general = GetGeneralSettings()

    -- Update font and position from current settings
    local fontPath = GetFontPath()
    local fontOutline = general and general.fontOutline or "OUTLINE"
    local fontSize = stanceSettings.fontSize or 12
    frame.stanceText:SetFont(fontPath, fontSize, fontOutline)

    -- Update position based on current anchor settings
    local anchorInfo = GetTextAnchorInfo(stanceSettings.anchor or "BOTTOM")
    local offsetX = stanceSettings.offsetX or 0
    local offsetY = stanceSettings.offsetY or -2

    frame.stanceText:ClearAllPoints()
    frame.stanceText:SetPoint(anchorInfo.point, frame, anchorInfo.point, offsetX, offsetY)
    frame.stanceText:SetJustifyH(anchorInfo.justify)

    -- Get current shapeshift form info
    local formIndex = GetShapeshiftForm()
    local formName = nil
    local formIcon = nil

    if formIndex and formIndex > 0 then
        local icon, active, castable, spellID = GetShapeshiftFormInfo(formIndex)
        if spellID then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo then
                formName = spellInfo.name
            end
        end
        formIcon = icon
    end

    -- If no form/stance active, hide the text
    if not formName or formName == "" then
        frame.stanceText:Hide()
        if frame.stanceIcon then frame.stanceIcon:Hide() end
        return
    end

    -- Update text
    frame.stanceText:SetText(formName)

    -- Set text color
    if stanceSettings.useClassColor then
        local _, class = UnitClass("player")
        if class then
            local color = RAID_CLASS_COLORS[class]
            if color then
                frame.stanceText:SetTextColor(color.r, color.g, color.b, 1)
            else
                frame.stanceText:SetTextColor(1, 1, 1, 1)
            end
        end
    else
        local c = stanceSettings.customColor or { 1, 1, 1, 1 }
        frame.stanceText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    frame.stanceText:Show()

    -- Update icon if enabled
    if frame.stanceIcon then
        local iconSize = stanceSettings.iconSize or 14
        local iconOffsetX = stanceSettings.iconOffsetX or -2
        frame.stanceIcon:SetSize(iconSize, iconSize)
        frame.stanceIcon:ClearAllPoints()
        frame.stanceIcon:SetPoint("RIGHT", frame.stanceText, "LEFT", iconOffsetX, 0)

        if stanceSettings.showIcon and formIcon then
            frame.stanceIcon:SetTexture(formIcon)
            frame.stanceIcon:Show()
        else
            frame.stanceIcon:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- UPDATE: Target Marker (raid icons like skull, cross, diamond, etc.)
---------------------------------------------------------------------------
local function UpdateTargetMarker(frame)
    if not frame or not frame.unit or not frame.targetMarker then return end
    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.targetMarker or not settings.targetMarker.enabled then
        frame.targetMarker:Hide()
        return
    end

    local index = GetRaidTargetIndex(frame.unit)
    if index then
        SetRaidTargetIconTexture(frame.targetMarker, index)
        frame.targetMarker:Show()
    else
        frame.targetMarker:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Leader/Assistant Icon (crown for leader, flag for assistant)
---------------------------------------------------------------------------
local function UpdateLeaderIcon(frame)
    if not frame or not frame.unit or not frame.leaderIcon then return end
    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.leaderIcon or not settings.leaderIcon.enabled then
        frame.leaderIcon:Hide()
        return
    end

    -- Only show in group
    if not IsInGroup() then
        frame.leaderIcon:Hide()
        return
    end

    -- Check if unit is leader or assistant
    -- Note: Assistants only exist in raids, not parties
    if UnitIsGroupLeader(frame.unit) then
        frame.leaderIcon:SetTexture([[Interface\GroupFrame\UI-Group-LeaderIcon]])
        frame.leaderIcon:Show()
    elseif IsInRaid() and UnitIsGroupAssistant(frame.unit) then
        frame.leaderIcon:SetTexture([[Interface\GroupFrame\UI-Group-AssistantIcon]])
        frame.leaderIcon:Show()
    else
        frame.leaderIcon:Hide()
    end
end

---------------------------------------------------------------------------
-- UPDATE: Health text color (independent of name visibility)
---------------------------------------------------------------------------
local function UpdateHealthTextColor(frame)
    if not frame or not frame.healthText or not frame.unit then return end

    local settings = GetUnitSettings(frame.unitKey)
    if not settings then return end

    local general = GetGeneralSettings()

    if general and general.masterColorHealthText then
        local r, g, b = GetUnitClassColor(frame.unit)
        frame.healthText:SetTextColor(r, g, b, 1)
    elseif settings.healthTextUseClassColor then
        local r, g, b = GetUnitClassColor(frame.unit)
        frame.healthText:SetTextColor(r, g, b, 1)
    elseif settings.healthTextColor then
        local c = settings.healthTextColor
        frame.healthText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    elseif general and general.classColorText then
        local r, g, b = GetUnitClassColor(frame.unit)
        frame.healthText:SetTextColor(r, g, b, 1)
    else
        frame.healthText:SetTextColor(1, 1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- UPDATE: Name text (with truncation and inline ToT support)
---------------------------------------------------------------------------
local function UpdateName(frame)
    if not frame or not frame.unit or not frame.nameText then return end
    local unit = frame.unit

    local settings = GetUnitSettings(frame.unitKey)
    if not settings or not settings.showName then
        frame.nameText:Hide()
        return
    end

    local name = UnitName(unit) or ""

    -- Apply name truncation if maxNameLength is set
    local maxLen = settings.maxNameLength
    if maxLen and maxLen > 0 then
        name = TruncateName(name, maxLen)
    end

    -- Inline Target of Target for target frame only
    if frame.unitKey == "target" and settings.showInlineToT then
        local totUnit = "targettarget"
        if UnitExists(totUnit) then
            local totName = UnitName(totUnit) or ""
            local totCharLimit = settings.totNameCharLimit
            if totCharLimit and totCharLimit > 0 then
                totName = TruncateName(totName, totCharLimit)
            elseif maxLen and maxLen > 0 then
                totName = TruncateName(totName, maxLen)
            end
            local separator = settings.totSeparator or " >> "

            -- Determine divider color
            local dividerColorHex
            if settings.totDividerUseClassColor then
                -- Class/reaction color for divider
                local dR, dG, dB = GetUnitClassColor(totUnit)
                dividerColorHex = string.format("|cff%02x%02x%02x", dR * 255, dG * 255, dB * 255)
            elseif settings.totDividerColor then
                -- Custom divider color
                local c = settings.totDividerColor
                dividerColorHex = string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
            else
                -- Default white
                dividerColorHex = "|cFFFFFFFF"
            end

            -- Build the inline text with class coloring for ToT (master override OR per-unit setting)
            local general = GetGeneralSettings()
            if general and general.masterColorToTText then
                -- MASTER OVERRIDE: Color ToT name only
                local totR, totG, totB = GetUnitClassColor(totUnit)
                local totColorHex = string.format("|cff%02x%02x%02x", totR * 255, totG * 255, totB * 255)
                name = name .. dividerColorHex .. separator .. "|r" .. totColorHex .. totName .. "|r"
            elseif settings.totUseClassColor then
                -- Per-unit: ToT name colored
                local totR, totG, totB = GetUnitClassColor(totUnit)
                local totColorHex = string.format("|cff%02x%02x%02x", totR * 255, totG * 255, totB * 255)
                name = name .. dividerColorHex .. separator .. "|r" .. totColorHex .. totName .. "|r"
            else
                -- Default: Divider colored, ToT name uncolored
                name = name .. dividerColorHex .. separator .. "|r" .. totName
            end
        end
    end

    frame.nameText:SetText(name)

    -- Apply name text color (master override OR per-unit setting)
    local general = GetGeneralSettings()
    if general and general.masterColorNameText then
        -- MASTER OVERRIDE: Apply class/reaction color to ALL frames
        local r, g, b = GetUnitClassColor(unit)
        frame.nameText:SetTextColor(r, g, b, 1)
    elseif settings.nameTextUseClassColor then
        -- Per-unit setting: Use class/reaction color
        local r, g, b = GetUnitClassColor(unit)
        frame.nameText:SetTextColor(r, g, b, 1)
    elseif settings.nameTextColor then
        -- Per-unit setting: Use custom color
        local c = settings.nameTextColor
        frame.nameText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    elseif general and general.classColorText then
        -- Backwards compat: Legacy global toggle (deprecated)
        local r, g, b = GetUnitClassColor(unit)
        frame.nameText:SetTextColor(r, g, b, 1)
    else
        -- Default: White text
        frame.nameText:SetTextColor(1, 1, 1, 1)
    end

    frame.nameText:Show()
end

---------------------------------------------------------------------------
-- UPDATE: Full frame update
---------------------------------------------------------------------------
local function UpdateFrame(frame)
    if not frame then return end
    
    -- Always update health bar color (for dark mode toggle even when unit doesn't exist)
    if frame.healthBar then
        local general = GetGeneralSettings()
        local settings = GetUnitSettings(frame.unitKey)

        if general and general.darkMode then
            local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
            frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        else
            -- Use unit-specific color settings (class color → hostility color → custom color)
            local r, g, b, a = GetHealthBarColor(frame.unit, settings)
            frame.healthBar:SetStatusBarColor(r, g, b, a)
        end
    end

    UpdateHealth(frame)
    UpdateAbsorbs(frame)
    UpdatePower(frame)
    UpdatePowerText(frame)
    UpdateName(frame)
    UpdateHealthTextColor(frame)
    UpdateIndicators(frame)
    UpdateStance(frame)
    UpdateTargetMarker(frame)
    UpdateLeaderIcon(frame)

    -- Update portrait texture (third param disables circular mask for square portrait)
    if frame.portraitTexture and frame.portrait and frame.portrait:IsShown() then
        if UnitExists(frame.unit) then
            SetPortraitTexture(frame.portraitTexture, frame.unit, true)
            frame.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)  -- Crop to focus on face
        end
    end
end

---------------------------------------------------------------------------
-- CREATE: Boss Frame (special handling for boss1-boss5)
---------------------------------------------------------------------------
local function CreateBossFrame(unit, frameKey, bossIndex)
    -- Boss frames use shared "boss" settings
    local settings = GetUnitSettings("boss")
    local general = GetGeneralSettings()
    
    if not settings then return nil end
    
    -- Create secure button with unique name (QUI_Boss1, QUI_Boss2, etc.)
    local frameName = "QUI_Boss" .. bossIndex
    local frame = CreateFrame("Button", frameName, UIParent, "SecureUnitButtonTemplate, BackdropTemplate, PingableUnitFrameTemplate")
    
    frame.unit = unit  -- "boss1", "boss2", etc.
    frame.unitKey = "boss"  -- Settings key
    
    -- Size and position (config values are virtual coords, snap to pixel grid)
    local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
    frame:SetSize(width, height)

    -- Position relative to UIParent CENTER (config offsets are virtual coords)
    if QUICore.SetSnappedPoint then
        QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
    end

    -- Make it movable in Edit Mode
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Secure unit attributes for click targeting
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")

    -- Tooltip on hover
    frame:HookScript("OnEnter", function(self)
        ShowUnitTooltip(self)
    end)
    frame:HookScript("OnLeave", HideUnitTooltip)

    -- Use secure state driver for visibility
    RegisterStateDriver(frame, "visibility", "[@" .. unit .. ",exists] show; hide")

    -- Refresh frame content when it becomes visible (boss spawns)
    frame:HookScript("OnShow", function(self)
        local bossKey = "boss" .. bossIndex
        if QUI_UF.previewMode[bossKey] then return end
        UpdateFrame(self)
    end)

    -- Background
    local bgColor = { 0.1, 0.1, 0.1, 0.9 }
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
    end

    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    if borderSize > 0 then
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- Health bar
    local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
    local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0
    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    healthBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:EnableMouse(false)
    frame.healthBar = healthBar

    -- Absorb bar (StatusBar handles secret values via SetValue)
    -- Use stripe texture directly on StatusBar (no overlay) to avoid 1px sliver at 0 width
    local absorbSettings = settings.absorbs or {}
    local absorbBar = CreateFrame("StatusBar", nil, healthBar)
    absorbBar:SetStatusBarTexture(GetAbsorbTexturePath(absorbSettings.texture))
    local absorbBarTex = absorbBar:GetStatusBarTexture()
    if absorbBarTex then
        absorbBarTex:SetHorizTile(false)
        absorbBarTex:SetVertTile(false)
        absorbBarTex:SetTexCoord(0, 1, 0, 1)
    end
    local ac = absorbSettings.color or { 1, 1, 1 }
    local aa = absorbSettings.opacity or 0.7
    absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    absorbBar:SetPoint("TOP", healthBar, "TOP", 0, 0)
    absorbBar:SetPoint("BOTTOM", healthBar, "BOTTOM", 0, 0)
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:Hide()  -- Start hidden until UpdateAbsorbs shows it
    frame.absorbBar = absorbBar

    -- Heal absorb bar (fills from right side of current health)
    local healAbsorbBar = CreateFrame("StatusBar", nil, healthBar)
    healAbsorbBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    healAbsorbBar:SetAllPoints(healthBar)
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:SetStatusBarColor(0.6, 0.1, 0.1, 0.8)
    healAbsorbBar:SetReverseFill(true)
    frame.healAbsorbBar = healAbsorbBar

    -- Set initial health bar color based on settings (use same logic as UpdateFrame)
    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        local r, g, b, a = GetHealthBarColor(unit, settings)
        healthBar:SetStatusBarColor(r, g, b, a)
    end

    -- Power bar
    if settings.showPowerBar then
        local powerBar = CreateFrame("StatusBar", nil, frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        powerBar:SetStatusBarTexture(GetTexturePath(settings.texture))
        local powerColor = settings.powerBarColor or { 0, 0.5, 1, 1 }
        powerBar:SetStatusBarColor(powerColor[1], powerColor[2], powerColor[3], powerColor[4] or 1)
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        powerBar:EnableMouse(false)
        frame.powerBar = powerBar

        -- Power bar separator (1px black line above power bar)
        if settings.powerBarBorder ~= false then
            local separator = powerBar:CreateTexture(nil, "OVERLAY")
            separator:SetHeight(QUICore:GetPixelSize(powerBar))
            separator:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
            separator:SetTexture("Interface\\Buttons\\WHITE8x8")
            separator:SetVertexColor(0, 0, 0, 1)
            frame.powerBarSeparator = separator
        end
    end

    -- Name text
    if settings.showName then
        local nameAnchorInfo = GetTextAnchorInfo(settings.nameAnchor or "LEFT")
        local nameOffsetX = QUICore:PixelRound(settings.nameOffsetX or 4, healthBar)
        local nameOffsetY = QUICore:PixelRound(settings.nameOffsetY or 0, healthBar)
        local nameText = healthBar:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(GetFontPath(), settings.nameFontSize or 12, GetFontOutline())
        nameText:SetShadowOffset(0, 0)
        nameText:SetPoint(nameAnchorInfo.point, healthBar, nameAnchorInfo.point, nameOffsetX, nameOffsetY)
        nameText:SetJustifyH(nameAnchorInfo.justify)
        nameText:SetText("Boss " .. bossIndex)
        frame.nameText = nameText
    end

    -- Health text
    if settings.showHealth then
        local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
        local healthOffsetX = QUICore:PixelRound(settings.healthOffsetX or -4, healthBar)
        local healthOffsetY = QUICore:PixelRound(settings.healthOffsetY or 0, healthBar)
        local healthText = healthBar:CreateFontString(nil, "OVERLAY")
        healthText:SetFont(GetFontPath(), settings.healthFontSize or 11, GetFontOutline())
        healthText:SetShadowOffset(0, 0)
        healthText:SetPoint(healthAnchorInfo.point, healthBar, healthAnchorInfo.point, healthOffsetX, healthOffsetY)
        healthText:SetJustifyH(healthAnchorInfo.justify)
        healthText:SetText("100%")
        frame.healthText = healthText
    end

    -- Power text (separate from power bar, for displaying power %)
    local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
    local powerText = healthBar:CreateFontString(nil, "OVERLAY")
    powerText:SetFont(GetFontPath(), settings.powerTextFontSize or 10, GetFontOutline())
    powerText:SetShadowOffset(0, 0)
    local pOffX = QUICore:PixelRound(settings.powerTextOffsetX or -4, healthBar)
    local pOffY = QUICore:PixelRound(settings.powerTextOffsetY or 2, healthBar)
    powerText:SetPoint(powerAnchorInfo.point, healthBar, powerAnchorInfo.point, pOffX, pOffY)
    powerText:SetJustifyH(powerAnchorInfo.justify)
    powerText:Hide()  -- Hidden by default, UpdatePowerText will show if enabled
    frame.powerText = powerText

    -- Target Marker (raid icons - boss frames)
    if settings.targetMarker then
        -- Create indicator container frame
        local indicatorFrame = CreateFrame("Frame", nil, frame)
        indicatorFrame:SetAllPoints()
        indicatorFrame:SetFrameLevel(healthBar:GetFrameLevel() + 5)
        frame.indicatorFrame = indicatorFrame

        local marker = settings.targetMarker
        local targetMarker = indicatorFrame:CreateTexture(nil, "OVERLAY")
        targetMarker:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])  -- Base texture atlas
        targetMarker:SetSize(marker.size or 20, marker.size or 20)
        local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
        targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
        targetMarker:Hide()
        frame.targetMarker = targetMarker
    end

    -- Register events for updates
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local eventUnit = ...
            if eventUnit == self.unit then
                UpdateHealth(self)
                UpdateAbsorbs(self)
            end
        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            local eventUnit = ...
            if eventUnit == self.unit then
                UpdateAbsorbs(self)
            end
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
            local eventUnit = ...
            if eventUnit == self.unit then
                UpdatePower(self)
                UpdatePowerText(self)
            end
        elseif event == "UNIT_NAME_UPDATE" then
            local eventUnit = ...
            if eventUnit == self.unit then
                UpdateName(self)
            end
        elseif event == "RAID_TARGET_UPDATE" then
            UpdateTargetMarker(self)
        end
    end)

    frame:RegisterUnitEvent("UNIT_HEALTH", unit)
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    frame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    frame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit)
    frame:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
    frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit)  -- Frequent updates for smoother power text sync
    frame:RegisterUnitEvent("UNIT_MAXPOWER", unit)
    frame:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    frame:RegisterEvent("RAID_TARGET_UPDATE")  -- Target marker (skull, cross, etc.)

    -- Register with Clique if available
    if _G.ClickCastFrames then
        _G.ClickCastFrames[frame] = true
    end

    return frame
end

---------------------------------------------------------------------------
-- Force update ToT frame when target-related events fire
---------------------------------------------------------------------------
local function ForceUpdateToT()
    local totFrame = QUI_UF.frames and QUI_UF.frames.targettarget
    if not totFrame or not UnitExists("targettarget") then return end
    UpdateHealth(totFrame)
    UpdateAbsorbs(totFrame)
    UpdatePower(totFrame)
    UpdatePowerText(totFrame)
    UpdateName(totFrame)
end

-- ToT polling for health updates (unit events don't fire reliably for targettarget)
local totUpdateTicker = nil
local TOT_UPDATE_INTERVAL = 0.2  -- 200ms = 5 updates/sec

local function StartToTTicker()
    if totUpdateTicker then return end
    totUpdateTicker = C_Timer.NewTicker(TOT_UPDATE_INTERVAL, function()
        if UnitExists("targettarget") then
            ForceUpdateToT()
        end
    end)
end

local function StopToTTicker()
    if totUpdateTicker then
        totUpdateTicker:Cancel()
        totUpdateTicker = nil
    end
end

---------------------------------------------------------------------------
-- CREATE: Unit Frame
---------------------------------------------------------------------------
local function CreateUnitFrame(unit, unitKey)
    local settings = GetUnitSettings(unitKey)
    local general = GetGeneralSettings()
    
    if not settings then return nil end
    
    -- Create secure button for click targeting
    local frameName = "QUI_" .. unitKey:gsub("^%l", string.upper)
    local frame = CreateFrame("Button", frameName, UIParent, "SecureUnitButtonTemplate, BackdropTemplate, PingableUnitFrameTemplate")
    
    frame.unit = unit
    frame.unitKey = unitKey
    
    -- Size and position (config values are virtual coords, snap to pixel grid)
    local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
    frame:SetSize(width, height)

    -- Position relative to UIParent CENTER (config offsets are virtual coords)
    if QUICore.SetSnappedPoint then
        QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
    end

    -- Make it movable in Edit Mode (we'll handle this later)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    -- Secure unit attributes for click targeting
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")      -- Left click = target
    frame:SetAttribute("*type2", "togglemenu")  -- Right click = menu
    frame:RegisterForClicks("AnyUp")

    -- Tooltip on hover
    frame:HookScript("OnEnter", function(self)
        ShowUnitTooltip(self)
    end)
    frame:HookScript("OnLeave", HideUnitTooltip)

    -- Use secure state driver for visibility (handles combat lockdown)
    if unit == "target" then
        RegisterStateDriver(frame, "visibility", "[@target,exists] show; hide")
    elseif unit == "focus" then
        RegisterStateDriver(frame, "visibility", "[@focus,exists] show; hide")
    elseif unit == "pet" then
        RegisterStateDriver(frame, "visibility", "[@pet,exists] show; hide")
    elseif unit == "targettarget" then
        -- ToT: show when target's target exists
        RegisterStateDriver(frame, "visibility", "[@targettarget,exists] show; hide")
        -- Start/stop ToT health polling based on visibility
        frame:HookScript("OnShow", StartToTTicker)
        frame:HookScript("OnHide", StopToTTicker)
        -- If already visible (had target on load), start ticker now
        if frame:IsShown() then
            StartToTTicker()
        end
    elseif unit:match("^boss%d+$") then
        -- Boss frames: show when that boss unit exists
        RegisterStateDriver(frame, "visibility", "[@" .. unit .. ",exists] show; hide")
    end
    
    -- Background
    local bgColor = { 0.1, 0.1, 0.1, 0.9 }
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
    end
    
    -- Pixel-perfect border size
    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    if borderSize > 0 then
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- Health bar (pixel-perfect insets)
    local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
    local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0
    local healthBar = CreateFrame("StatusBar", nil, frame)
    healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    healthBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:EnableMouse(false)
    frame.healthBar = healthBar

    -- Absorb bar (StatusBar handles secret values via SetValue)
    -- Use stripe texture directly on StatusBar (no overlay) to avoid 1px sliver at 0 width
    local absorbSettings = settings.absorbs or {}
    local absorbBar = CreateFrame("StatusBar", nil, healthBar)
    absorbBar:SetStatusBarTexture(GetAbsorbTexturePath(absorbSettings.texture))
    local absorbBarTex = absorbBar:GetStatusBarTexture()
    if absorbBarTex then
        absorbBarTex:SetHorizTile(false)
        absorbBarTex:SetVertTile(false)
        absorbBarTex:SetTexCoord(0, 1, 0, 1)
    end
    local ac = absorbSettings.color or { 1, 1, 1 }
    local aa = absorbSettings.opacity or 0.7
    absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], aa)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    absorbBar:SetPoint("TOP", healthBar, "TOP", 0, 0)
    absorbBar:SetPoint("BOTTOM", healthBar, "BOTTOM", 0, 0)
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)
    absorbBar:Hide()  -- Start hidden until UpdateAbsorbs shows it
    frame.absorbBar = absorbBar

    -- Heal absorb bar (fills from right side of current health)
    local healAbsorbBar = CreateFrame("StatusBar", nil, healthBar)
    healAbsorbBar:SetStatusBarTexture(GetTexturePath(settings.texture))
    healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    healAbsorbBar:SetAllPoints(healthBar)
    healAbsorbBar:SetMinMaxValues(0, 1)
    healAbsorbBar:SetValue(0)
    healAbsorbBar:SetStatusBarColor(0.6, 0.1, 0.1, 0.8)
    healAbsorbBar:SetReverseFill(true)
    frame.healAbsorbBar = healAbsorbBar

    -- Set initial health bar color based on settings (use same logic as UpdateFrame)
    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        local r, g, b, a = GetHealthBarColor(unit, settings)
        healthBar:SetStatusBarColor(r, g, b, a)
    end

    -- Power bar (inside the frame, at the bottom, pixel-perfect)
    if settings.showPowerBar then
        local powerBar = CreateFrame("StatusBar", nil, frame)
        powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        powerBar:SetHeight(powerHeight)
        powerBar:SetStatusBarTexture(GetTexturePath(settings.texture))
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(100)
        -- Set initial power color from settings
        local powerColor = settings.powerBarColor or { 0, 0.5, 1, 1 }
        powerBar:SetStatusBarColor(powerColor[1], powerColor[2], powerColor[3], powerColor[4] or 1)
        powerBar:EnableMouse(false)
        frame.powerBar = powerBar

        -- Power bar separator (1px black line above power bar)
        if settings.powerBarBorder ~= false then
            local separator = powerBar:CreateTexture(nil, "OVERLAY")
            separator:SetHeight(QUICore:GetPixelSize(powerBar))
            separator:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
            separator:SetTexture("Interface\\Buttons\\WHITE8x8")
            separator:SetVertexColor(0, 0, 0, 1)
            frame.powerBarSeparator = separator
        end
    end

    -- Portrait (optional, side-attached)
    if settings.showPortrait then
        local portrait = CreateFrame("Button", nil, frame, "SecureUnitButtonTemplate, BackdropTemplate")
        local portraitSizePx = settings.portraitSize or 40
        local portraitBorderSize = QUICore:Pixels(settings.portraitBorderSize or 1, portrait)
        portrait:SetSize(QUICore:PixelRound(portraitSizePx, portrait), QUICore:PixelRound(portraitSizePx, portrait))

        local portraitGap = QUICore:PixelRound(settings.portraitGap or 0, portrait)
        local portraitOffsetX = QUICore:PixelRound(settings.portraitOffsetX or 0, portrait)
        local portraitOffsetY = QUICore:PixelRound(settings.portraitOffsetY or 0, portrait)
        local side = settings.portraitSide or "LEFT"
        if side == "LEFT" then
            portrait:SetPoint("RIGHT", frame, "LEFT", -portraitGap + portraitOffsetX, portraitOffsetY)
        else
            portrait:SetPoint("LEFT", frame, "RIGHT", portraitGap + portraitOffsetX, portraitOffsetY)
        end

        -- Secure unit attributes for click targeting
        portrait:SetAttribute("unit", unit)
        portrait:SetAttribute("*type1", "target")
        portrait:SetAttribute("*type2", "togglemenu")
        portrait:RegisterForClicks("AnyUp")

        -- Tooltip on hover
        portrait:HookScript("OnEnter", function(self)
            ShowUnitTooltip(frame)
        end)
        portrait:HookScript("OnLeave", HideUnitTooltip)

        -- Border around portrait
        portrait:SetBackdrop({
            bgFile = nil,
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = portraitBorderSize,
        })

        -- Determine border color
        local borderR, borderG, borderB = 0, 0, 0
        if settings.portraitBorderUseClassColor then
            local _, class = UnitClass(unit)
            if class then
                local classColor = RAID_CLASS_COLORS[class]
                if classColor then
                    borderR, borderG, borderB = classColor.r, classColor.g, classColor.b
                end
            end
        elseif settings.portraitBorderColor then
            borderR = settings.portraitBorderColor[1] or 0
            borderG = settings.portraitBorderColor[2] or 0
            borderB = settings.portraitBorderColor[3] or 0
        end
        portrait:SetBackdropBorderColor(borderR, borderG, borderB, 1)

        local portraitTex = portrait:CreateTexture(nil, "ARTWORK")
        portraitTex:SetPoint("TOPLEFT", portraitBorderSize, -portraitBorderSize)
        portraitTex:SetPoint("BOTTOMRIGHT", -portraitBorderSize, portraitBorderSize)
        frame.portraitTexture = portraitTex
        frame.portrait = portrait

        SetPortraitTexture(portraitTex, unit, true)
        portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)  -- Crop to focus on face
    end

    -- Text frame (above health bar for proper layering)
    local textFrame = CreateFrame("Frame", nil, frame)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    
    -- Name text
    local fontPath = GetFontPath()
    local fontOutline = general and general.fontOutline or "OUTLINE"
    local nameFontSize = settings.nameFontSize or 12
    local nameAnchorInfo = GetTextAnchorInfo(settings.nameAnchor or "LEFT")
    local nameOffsetX = QUICore:PixelRound(settings.nameOffsetX or 4, frame)
    local nameOffsetY = QUICore:PixelRound(settings.nameOffsetY or 0, frame)

    local nameText = textFrame:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(fontPath, nameFontSize, fontOutline)
    nameText:SetPoint(nameAnchorInfo.point, frame, nameAnchorInfo.point, nameOffsetX, nameOffsetY)
    nameText:SetJustifyH(nameAnchorInfo.justify)
    nameText:SetTextColor(1, 1, 1, 1)
    frame.nameText = nameText
    
    -- Health text
    local healthFontSize = settings.healthFontSize or 12
    local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
    local healthOffsetX = QUICore:PixelRound(settings.healthOffsetX or -4, frame)
    local healthOffsetY = QUICore:PixelRound(settings.healthOffsetY or 0, frame)

    local healthText = textFrame:CreateFontString(nil, "OVERLAY")
    healthText:SetFont(fontPath, healthFontSize, fontOutline)
    healthText:SetPoint(healthAnchorInfo.point, frame, healthAnchorInfo.point, healthOffsetX, healthOffsetY)
    healthText:SetJustifyH(healthAnchorInfo.justify)
    healthText:SetTextColor(1, 1, 1, 1)
    frame.healthText = healthText

    -- Power text (separate from power bar, for displaying power %)
    local powerTextFontSize = settings.powerTextFontSize or 12
    local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
    local powerTextOffsetX = QUICore:PixelRound(settings.powerTextOffsetX or -4, frame)
    local powerTextOffsetY = QUICore:PixelRound(settings.powerTextOffsetY or 2, frame)

    local powerText = textFrame:CreateFontString(nil, "OVERLAY")
    powerText:SetFont(fontPath, powerTextFontSize, fontOutline)
    powerText:SetPoint(powerAnchorInfo.point, frame, powerAnchorInfo.point, powerTextOffsetX, powerTextOffsetY)
    powerText:SetJustifyH(powerAnchorInfo.justify)
    powerText:SetTextColor(1, 1, 1, 1)
    powerText:Hide()  -- Hidden by default, UpdatePowerText will show if enabled
    frame.powerText = powerText

    -- Status indicators (player frame only)
    if unitKey == "player" then
        local indSettings = settings.indicators

        -- Create indicator container frame with high frame level (renders above healthBar/textFrame)
        local indicatorFrame = CreateFrame("Frame", nil, frame)
        indicatorFrame:SetAllPoints()
        indicatorFrame:SetFrameLevel(textFrame:GetFrameLevel() + 5)
        frame.indicatorFrame = indicatorFrame

        -- Rested indicator (shows when in rested area)
        if indSettings and indSettings.rested then
            local rested = indSettings.rested
            local restedIndicator = indicatorFrame:CreateTexture(nil, "OVERLAY")
            restedIndicator:SetSize(rested.size or 16, rested.size or 16)
            local anchorInfo = GetTextAnchorInfo(rested.anchor or "TOPLEFT")
            restedIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, rested.offsetX or -2, rested.offsetY or 2)
            restedIndicator:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            restedIndicator:SetTexCoord(0.0625, 0.4375, 0.0625, 0.4375)  -- Rested icon portion
            restedIndicator:Hide()
            frame.restedIndicator = restedIndicator
        end

        -- Combat indicator (shows during combat)
        if indSettings and indSettings.combat then
            local combat = indSettings.combat
            local combatIndicator = indicatorFrame:CreateTexture(nil, "OVERLAY")
            combatIndicator:SetSize(combat.size or 16, combat.size or 16)
            local anchorInfo = GetTextAnchorInfo(combat.anchor or "TOPLEFT")
            combatIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, combat.offsetX or -2, combat.offsetY or 2)
            combatIndicator:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
            combatIndicator:SetTexCoord(0.5625, 0.9375, 0.0625, 0.4375)  -- Combat icon portion
            combatIndicator:Hide()
            frame.combatIndicator = combatIndicator
        end

        -- Stance/Form text (shows current form, stance, or aura)
        -- Always create so it can be toggled dynamically without reload
        local general = GetGeneralSettings()
        local fontOutline = general and general.fontOutline or "OUTLINE"

        local stanceText = indicatorFrame:CreateFontString(nil, "OVERLAY")
        stanceText:SetFont(fontPath, 12, fontOutline)
        stanceText:SetPoint("BOTTOM", frame, "BOTTOM", 0, -2)
        stanceText:SetJustifyH("CENTER")
        stanceText:SetTextColor(1, 1, 1, 1)
        stanceText:Hide()
        frame.stanceText = stanceText

        local stanceIcon = indicatorFrame:CreateTexture(nil, "OVERLAY")
        stanceIcon:SetSize(14, 14)
        stanceIcon:SetPoint("RIGHT", stanceText, "LEFT", -2, 0)
        stanceIcon:Hide()
        frame.stanceIcon = stanceIcon
    end

    -- Target Marker (raid icons - applies to all unit frames)
    if settings.targetMarker then
        -- Create indicator container if not exists (for non-player frames)
        if not frame.indicatorFrame then
            local indicatorFrame = CreateFrame("Frame", nil, frame)
            indicatorFrame:SetAllPoints()
            indicatorFrame:SetFrameLevel(textFrame:GetFrameLevel() + 5)
            frame.indicatorFrame = indicatorFrame
        end

        local marker = settings.targetMarker
        local targetMarker = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
        targetMarker:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])  -- Base texture atlas
        targetMarker:SetSize(marker.size or 20, marker.size or 20)
        local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
        targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
        targetMarker:Hide()
        frame.targetMarker = targetMarker
    end

    -- Leader/Assistant Icon (crown for leader, flag for assistant)
    -- Only create if enabled to avoid CPU usage when disabled
    if settings.leaderIcon and settings.leaderIcon.enabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
        -- Create indicator container if not exists
        if not frame.indicatorFrame then
            local indicatorFrame = CreateFrame("Frame", nil, frame)
            indicatorFrame:SetAllPoints()
            indicatorFrame:SetFrameLevel(textFrame:GetFrameLevel() + 5)
            frame.indicatorFrame = indicatorFrame
        end

        local leader = settings.leaderIcon
        local leaderIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
        leaderIcon:SetSize(leader.size or 16, leader.size or 16)
        local anchorInfo = GetTextAnchorInfo(leader.anchor or "TOPLEFT")
        leaderIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, leader.xOffset or -8, leader.yOffset or 8)
        leaderIcon:Hide()
        frame.leaderIcon = leaderIcon
    end

    -- Event handling
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    frame:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    frame:RegisterEvent("UNIT_POWER_UPDATE")
    frame:RegisterEvent("UNIT_POWER_FREQUENT")  -- Frequent updates for smoother power text sync
    frame:RegisterEvent("UNIT_MAXPOWER")
    frame:RegisterEvent("UNIT_NAME_UPDATE")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("UNIT_TARGET")  -- For inline Target of Target updates
    frame:RegisterEvent("RAID_TARGET_UPDATE")  -- Target marker (skull, cross, etc.)

    -- Leader/Assistant icon events (player, target, focus only) - only register if feature enabled
    if settings.leaderIcon and settings.leaderIcon.enabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
        frame:RegisterEvent("PARTY_LEADER_CHANGED")
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    end

    -- Indicator-specific events (player only)
    if unitKey == "player" then
        frame:RegisterEvent("PLAYER_UPDATE_RESTING")  -- Rested indicator
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Combat indicator (entering combat)
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Combat indicator (leaving combat)
        frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM") -- Stance/form text
    end

    frame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_ENTERING_WORLD" then
            UpdateFrame(self)
        elseif event == "PLAYER_TARGET_CHANGED" then
            if self.unitKey == "target" then
                -- State driver handles visibility, just update if unit exists
                if UnitExists(self.unit) then
                    UpdateFrame(self)
                end
            elseif self.unitKey == "targettarget" then
                -- ToT: update if exists, otherwise clear the display
                -- NOTE: State driver handles Show/Hide - don't call manually to avoid taint
                if UnitExists(self.unit) then
                    UpdateFrame(self)
                else
                    -- Clear the ToT display when target has no target
                    if self.nameText then self.nameText:SetText("") end
                    if self.healthText then self.healthText:SetText("") end
                    if self.powerText then self.powerText:Hide() end
                    if self.healthBar then
                        self.healthBar:SetValue(0)
                    end
                end
            end
        elseif event == "UNIT_TARGET" then
            if arg1 == "target" then
                -- Update inline ToT when target's target changes
                if self.unitKey == "target" then
                    UpdateName(self)  -- Refresh name text (includes inline ToT)
                -- Update standalone ToT frame when target's target changes
                elseif self.unitKey == "targettarget" then
                    if UnitExists(self.unit) then
                        UpdateFrame(self)
                    else
                        -- Clear display when target has no target
                        if self.nameText then self.nameText:SetText("") end
                        if self.healthText then self.healthText:SetText("") end
                        if self.powerText then self.powerText:Hide() end
                        if self.healthBar then self.healthBar:SetValue(0) end
                    end
                end
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            if self.unitKey == "focus" then
                -- State driver handles visibility, just update if unit exists
                if UnitExists(self.unit) then
                    UpdateFrame(self)
                end
            end
        elseif event == "UNIT_PET" then
            if self.unitKey == "pet" then
                -- State driver handles visibility, just update if unit exists
                if UnitExists(self.unit) then
                    UpdateFrame(self)
                end
            end
        elseif event == "PLAYER_UPDATE_RESTING"
               or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            -- Indicator events (player only)
            if self.unitKey == "player" then
                UpdateIndicators(self)
            end
        elseif event == "UPDATE_SHAPESHIFT_FORM" then
            -- Stance/form text (player only)
            if self.unitKey == "player" then
                UpdateStance(self)
            end
        elseif event == "RAID_TARGET_UPDATE" then
            -- Target marker changed on any unit
            UpdateTargetMarker(self)
        elseif event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
            -- Leader/Assistant status changed (player, target, focus only)
            UpdateLeaderIcon(self)
        elseif arg1 == self.unit then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                UpdateHealth(self)
                UpdateAbsorbs(self)
                -- Force update ToT when target health changes
                if self.unitKey == "target" then
                    ForceUpdateToT()
                end
            elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                UpdateAbsorbs(self)
                if self.unitKey == "target" then
                    ForceUpdateToT()
                end
            elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
                UpdatePower(self)
                UpdatePowerText(self)
                if self.unitKey == "target" then
                    ForceUpdateToT()
                end
            elseif event == "UNIT_NAME_UPDATE" then
                UpdateName(self)
            end
        end
    end)
    
    -- Initial update (player frame is always shown, others use state driver)
    if UnitExists(unit) or unitKey == "player" then
        UpdateFrame(frame)
    end
    -- Note: State driver handles visibility for target/focus/pet frames
    -- Player frame needs explicit show since it has no state driver
    if unitKey == "player" then
        frame:Show()
    end

    -- Register with Clique if available
    if _G.ClickCastFrames then
        _G.ClickCastFrames[frame] = true
    end

    return frame
end

---------------------------------------------------------------------------
-- CREATE: Castbar for a unit frame
-- For target/focus: hooks Blizzard's spellbar to avoid "secret value" issues
-- For player: uses direct UnitCastingInfo (no secret values for player)
---------------------------------------------------------------------------
local function CreateCastbar(unitFrame, unit, unitKey)
    -- Delegate to castbar module
    if QUI_Castbar then
        return QUI_Castbar:CreateCastbar(unitFrame, unit, unitKey)
    end
    return nil
end

---------------------------------------------------------------------------
-- CREATE: Boss Castbar (delegates to castbar module)
---------------------------------------------------------------------------
local function CreateBossCastbar(unitFrame, unit, bossIndex)
    -- Delegate to castbar module
    if QUI_Castbar then
        return QUI_Castbar:CreateBossCastbar(unitFrame, unit, bossIndex)
    end
    return nil
end

---------------------------------------------------------------------------
-- AURAS: Create buff/debuff icons for target/focus frames
---------------------------------------------------------------------------
local AURA_THROTTLE = 0.15  -- Update every 150ms max
local lastAuraUpdate = {}

-- Apply aura icon settings (for real-time updates without recreating icons)
-- isDebuff: true for debuffs, false for buffs - uses per-type settings when available
-- Duration text uses Blizzard's built-in countdown (handles secret values internally)
local function ApplyAuraIconSettings(icon, auraSettings, isDebuff)
    if not icon then return end
    auraSettings = auraSettings or {}

    local fontPath = GetFontPath()
    local fontOutline = GetFontOutline()

    -- Determine prefix for per-type settings (debuff* or buff*)
    local prefix = isDebuff and "debuff" or "buff"

    -- Stack text settings (per-type with fallback to shared settings)
    local showStack = auraSettings[prefix .. "ShowStack"]
    if showStack == nil then showStack = auraSettings.showStack end
    if showStack == nil then showStack = true end  -- default true

    local stackSize = auraSettings[prefix .. "StackSize"] or auraSettings.stackSize or 10
    local stackAnchor = auraSettings[prefix .. "StackAnchor"] or auraSettings.stackAnchor or "BOTTOMRIGHT"
    local stackOffsetX = auraSettings[prefix .. "StackOffsetX"] or auraSettings.stackOffsetX or -1
    local stackOffsetY = auraSettings[prefix .. "StackOffsetY"] or auraSettings.stackOffsetY or 1
    local stackColor = auraSettings[prefix .. "StackColor"] or auraSettings.stackColor or {1, 1, 1, 1}

    if icon.count then
        icon.count:SetFont(fontPath, stackSize, fontOutline)
        icon.count:ClearAllPoints()
        icon.count:SetPoint(stackAnchor, icon, stackAnchor, stackOffsetX, stackOffsetY)
        icon.count:SetTextColor(stackColor[1] or 1, stackColor[2] or 1, stackColor[3] or 1, stackColor[4] or 1)
    end
    icon._showStack = showStack

    -- Swipe toggle (per-type: debuffHideSwipe or buffHideSwipe)
    local hideSwipe = auraSettings[prefix .. "HideSwipe"]
    if hideSwipe == nil then hideSwipe = false end  -- default: show swipe
    if icon.cooldown then
        icon.cooldown:SetDrawSwipe(not hideSwipe)
    end

    -- Duration text settings (per-type)
    local showDuration = auraSettings[prefix .. "ShowDuration"]
    if showDuration == nil then showDuration = true end

    local durationSize = auraSettings[prefix .. "DurationSize"] or 12
    local durationAnchor = auraSettings[prefix .. "DurationAnchor"] or "CENTER"
    local durationOffsetX = auraSettings[prefix .. "DurationOffsetX"] or 0
    local durationOffsetY = auraSettings[prefix .. "DurationOffsetY"] or 0
    local durationColor = auraSettings[prefix .. "DurationColor"] or {1, 1, 1, 1}

    -- Safe duration text handling (pcall wrapped to prevent errors from breaking auras)
    if icon.cooldown then
        pcall(function()
            -- Toggle Blizzard countdown visibility
            if icon.cooldown.SetHideCountdownNumbers then
                icon.cooldown:SetHideCountdownNumbers(not showDuration)
            end

            -- Find and style the countdown FontString (created lazily by Blizzard)
            if showDuration and icon.cooldown.GetRegions then
                for _, region in ipairs({ icon.cooldown:GetRegions() }) do
                    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                        if region.SetFont then
                            region:SetFont(fontPath, durationSize, fontOutline)
                        end
                        if region.ClearAllPoints and region.SetPoint then
                            region:ClearAllPoints()
                            region:SetPoint(durationAnchor, icon, durationAnchor, durationOffsetX, durationOffsetY)
                        end
                        if region.SetTextColor then
                            region:SetTextColor(durationColor[1] or 1, durationColor[2] or 1, durationColor[3] or 1, durationColor[4] or 1)
                        end
                        break
                    end
                end
            end
        end)
    end
end

local function CreateAuraIcon(parent, index, size, auraSettings, isDebuff)
    -- Use plain Frame (no BackdropTemplate) to avoid secret value crashes during combat
    -- BackdropTemplate causes "arithmetic on secret value" errors when frame is resized
    local icon = CreateFrame("Frame", nil, parent)
    -- Use parent's strata but higher frame level to render above unit frame
    -- (avoids showing through major UI panels like spellbook)
    icon:SetFrameLevel(parent:GetFrameLevel() + 10)
    icon:SetSize(size, size)

    -- Enable mouse for tooltip interaction
    icon:EnableMouse(true)

    -- Aura data storage for tooltips
    icon.unit = nil
    icon.auraInstanceID = nil
    icon.filter = nil  -- "HELPFUL" or "HARMFUL"

    -- Tooltip scripts using safe auraInstanceID API
    icon:SetScript("OnEnter", function(self)
        if self.unit and self.auraInstanceID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.filter == "HELPFUL" then
                GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID)
            else
                GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID)
            end
            GameTooltip:Show()
        end
    end)

    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Border (using BACKGROUND texture to avoid secret value errors during combat)
    local border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetColorTexture(0, 0, 0, 1)
    local iconPx = QUICore:GetPixelSize(icon)
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -iconPx, iconPx)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", iconPx, -iconPx)
    icon.border = border

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", 0, 0)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.icon = tex

    -- Cooldown swipe
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetReverse(true)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd.noOCC = true
    -- noCooldownCount removed to enable Blizzard countdown text (styled via ApplyAuraIconSettings)
    icon.cooldown = cd

    -- Stack count (position/font set by ApplyAuraIconSettings)
    local count = icon:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", -iconPx, iconPx)  -- default, will be updated by settings
    count:SetTextColor(1, 1, 1, 1)
    icon.count = count
    icon._showStack = true  -- default

    -- Apply initial settings
    ApplyAuraIconSettings(icon, auraSettings, isDebuff)

    icon:Hide()
    return icon
end

local function GetAuraIcon(container, index, parent, size, auraSettings, isDebuff)
    if container[index] then
        container[index]:SetSize(size, size)
        -- Update settings on existing icon
        ApplyAuraIconSettings(container[index], auraSettings, isDebuff)
        return container[index]
    end

    local icon = CreateAuraIcon(parent, index, size, auraSettings, isDebuff)
    container[index] = icon
    return icon
end

local function UpdateAuras(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit
    
    if not UnitExists(unit) then
        -- Hide all auras
        if frame.buffIcons then
            for _, icon in ipairs(frame.buffIcons) do
                icon:Hide()
            end
        end
        if frame.debuffIcons then
            for _, icon in ipairs(frame.debuffIcons) do
                icon:Hide()
            end
        end
        return
    end
    
    -- Throttle updates
    local now = GetTime()
    local lastUpdate = lastAuraUpdate[unit] or 0
    if (now - lastUpdate) < AURA_THROTTLE then
        return
    end
    lastAuraUpdate[unit] = now
    
    -- Check if C_UnitAuras is available
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return
    end
    
    -- Get settings from database
    local settings = GetUnitSettings(frame.unitKey)
    local auraSettings = settings and settings.auras or {}
    
    local iconSize = auraSettings.iconSize or 22  -- Debuff icon size
    local buffIconSize = auraSettings.buffIconSize or 22  -- Buff icon size
    local showBuffs = auraSettings.showBuffs ~= false  -- default true
    local showDebuffs = auraSettings.showDebuffs ~= false  -- default true
    local onlyMyDebuffs = auraSettings.onlyMyDebuffs ~= false  -- default true

    -- Check if in preview mode for either aura type
    local unitKey = frame.unitKey
    local buffPreviewActive = QUI_UF.auraPreviewMode[unitKey .. "_buff"]
    local debuffPreviewActive = QUI_UF.auraPreviewMode[unitKey .. "_debuff"]

    -- Debuff settings
    local debuffAnchor = auraSettings.debuffAnchor or "TOPLEFT"
    local debuffGrow = auraSettings.debuffGrow or "RIGHT"
    local debuffMaxIcons = auraSettings.debuffMaxIcons or 16
    local debuffOffsetX = auraSettings.debuffOffsetX or 0
    local debuffOffsetY = auraSettings.debuffOffsetY or 2
    local debuffSpacing = auraSettings.debuffSpacing or auraSettings.iconSpacing or 2

    -- Buff settings
    local buffAnchor = auraSettings.buffAnchor or "BOTTOMLEFT"
    local buffGrow = auraSettings.buffGrow or "RIGHT"
    local buffMaxIcons = auraSettings.buffMaxIcons or 16
    local buffOffsetX = auraSettings.buffOffsetX or 0
    local buffOffsetY = auraSettings.buffOffsetY or -2
    local buffSpacing = auraSettings.buffSpacing or auraSettings.iconSpacing or 2

    -- Initialize containers
    frame.buffIcons = frame.buffIcons or {}
    frame.debuffIcons = frame.debuffIcons or {}

    -- Hide existing icons first (skip if preview is active for that type)
    if not buffPreviewActive then
        for _, icon in ipairs(frame.buffIcons) do
            icon:Hide()
        end
    end
    if not debuffPreviewActive then
        for _, icon in ipairs(frame.debuffIcons) do
            icon:Hide()
        end
    end
    
    -- Helper to safely set cooldown (handles secret values on enemy targets)
    -- Uses duration object API when available for combat-safe cooldown display
    local function SafeSetCooldown(cooldownFrame, auraData, unit)
        if not cooldownFrame then return false end
        if not auraData then return false end

        local applied = false

        -- Prefer duration object API (combat-safe on enemy targets)
        if cooldownFrame.SetCooldownFromDurationObject and auraData.auraInstanceID then
            local durationObj
            if C_UnitAuras and C_UnitAuras.GetAuraDuration then
                local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, auraData.auraInstanceID)
                if ok and obj then
                    durationObj = obj
                end
            end

            if durationObj then
                local setOk = pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, durationObj, true)
                if setOk then
                    applied = true
                else
                    -- Fallback: derive numbers from duration object methods
                    local eOK, elapsed = pcall(durationObj.GetElapsedDuration, durationObj)
                    local rOK, remaining = pcall(durationObj.GetRemainingDuration, durationObj)
                    if eOK and rOK and elapsed and remaining then
                        local startTime = GetTime() - elapsed
                        local total = elapsed + remaining
                        local numOk = pcall(cooldownFrame.SetCooldown, cooldownFrame, startTime, total)
                        if numOk then
                            applied = true
                        end
                    end
                end
            end
        end

        -- Fallback: numeric start/duration (avoid comparisons; allow secret-safe arithmetic)
        if not applied then
            local duration = auraData.duration
            local expirationTime = auraData.expirationTime
            if duration and expirationTime then
                local ok = pcall(function()
                    local startTime = expirationTime - duration
                    cooldownFrame:SetCooldown(startTime, duration)
                end)
                if ok then
                    applied = true
                end
            end
        end

        return applied
    end
    
    -- Helper to safely display stack count using combat-safe API
    -- Passes directly to SetText without comparing (return value may be secret-derived)
    local function DisplayStackCount(countText, unit, auraInstanceID)
        if not auraInstanceID or not C_UnitAuras.GetAuraApplicationDisplayCount then
            countText:SetText("")
            return
        end
        -- stackMinimum=2 means don't show "1", stackMaximum=99 for normal display
        -- API returns "" for <2 stacks, number string for 2-99, "*" for 100+
        local ok, stackText = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, 2, 99)
        if ok then
            countText:SetText(stackText)
        else
            countText:SetText("")
        end
    end

    -- Populate debuffs (skip if preview is active)
    local debuffCount = 0
    local debuffIndex = 1
    -- Filter: player frame always shows all; others respect onlyMyDebuffs setting
    local debuffFilter = "HARMFUL"
    if unit ~= "player" and onlyMyDebuffs then
        debuffFilter = "HARMFUL|PLAYER"
    end
    if showDebuffs and not debuffPreviewActive then
        while debuffCount < debuffMaxIcons do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, debuffIndex, debuffFilter)
            if not auraData then break end
            
            debuffCount = debuffCount + 1

            local icon = GetAuraIcon(frame.debuffIcons, debuffCount, frame, iconSize, auraSettings, true)

            -- Store aura data for tooltip
            icon.unit = unit
            icon.auraInstanceID = auraData.auraInstanceID
            icon.filter = debuffFilter

            -- Safely set texture (icon field is always safe)
            if auraData.icon then
                icon.icon:SetTexture(auraData.icon)
            end

            -- Red border for debuffs
            if icon.border then
                icon.border:SetColorTexture(0.8, 0.2, 0.2, 1)
            end

            -- Cooldown (safely handles secret values via duration object API)
            if SafeSetCooldown(icon.cooldown, auraData, unit) then
                icon.cooldown:Show()
            else
                icon.cooldown:Hide()
            end

            -- Stack count (using combat-safe API, no comparisons on result)
            if icon._showStack then
                DisplayStackCount(icon.count, unit, auraData.auraInstanceID)
                icon.count:Show()
            else
                icon.count:Hide()
            end

            -- Calculate position based on anchor and single grow direction
            local idx = debuffCount - 1
            local xPos, yPos = debuffOffsetX, debuffOffsetY
            if debuffGrow == "RIGHT" then
                xPos = xPos + idx * (iconSize + debuffSpacing)
            elseif debuffGrow == "LEFT" then
                xPos = xPos - idx * (iconSize + debuffSpacing)
            elseif debuffGrow == "UP" then
                yPos = yPos + idx * (iconSize + debuffSpacing)
            elseif debuffGrow == "DOWN" then
                yPos = yPos - idx * (iconSize + debuffSpacing)
            end
            
            -- Map user anchor to frame anchor points (flip vertical only for outside positioning)
            -- Border compensation: icons have 1px border extending beyond frame
            local iconPoint, framePoint, borderOffsetX
            if debuffAnchor == "TOPLEFT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMLEFT", "TOPLEFT", 1
            elseif debuffAnchor == "TOPRIGHT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMRIGHT", "TOPRIGHT", -1
            elseif debuffAnchor == "BOTTOMLEFT" then
                iconPoint, framePoint, borderOffsetX = "TOPLEFT", "BOTTOMLEFT", 1
            elseif debuffAnchor == "BOTTOMRIGHT" then
                iconPoint, framePoint, borderOffsetX = "TOPRIGHT", "BOTTOMRIGHT", -1
            end

            icon:ClearAllPoints()
            icon:SetPoint(iconPoint, frame, framePoint, xPos + (borderOffsetX or 0), yPos)
            icon:Show()
            
            debuffIndex = debuffIndex + 1
        end
    end
    
    -- Populate buffs (skip if preview is active)
    local buffCount = 0
    local buffIndex = 1
    if showBuffs and not buffPreviewActive then
        while buffCount < buffMaxIcons do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, buffIndex, "HELPFUL")
            if not auraData then break end
            
            buffCount = buffCount + 1

            local icon = GetAuraIcon(frame.buffIcons, buffCount, frame, buffIconSize, auraSettings, false)

            -- Store aura data for tooltip
            icon.unit = unit
            icon.auraInstanceID = auraData.auraInstanceID
            icon.filter = "HELPFUL"

            -- Safely set texture
            if auraData.icon then
                icon.icon:SetTexture(auraData.icon)
            end

            -- Default black border for buffs
            if icon.border then
                icon.border:SetColorTexture(0, 0, 0, 1)
            end

            -- Cooldown (safely handles secret values via duration object API)
            if SafeSetCooldown(icon.cooldown, auraData, unit) then
                icon.cooldown:Show()
            else
                icon.cooldown:Hide()
            end

            -- Stack count (using combat-safe API, no comparisons on result)
            if icon._showStack then
                DisplayStackCount(icon.count, unit, auraData.auraInstanceID)
                icon.count:Show()
            else
                icon.count:Hide()
            end

            -- Calculate position based on anchor and single grow direction
            local idx = buffCount - 1
            local xPos, yPos = buffOffsetX, buffOffsetY
            if buffGrow == "RIGHT" then
                xPos = xPos + idx * (buffIconSize + buffSpacing)
            elseif buffGrow == "LEFT" then
                xPos = xPos - idx * (buffIconSize + buffSpacing)
            elseif buffGrow == "UP" then
                yPos = yPos + idx * (buffIconSize + buffSpacing)
            elseif buffGrow == "DOWN" then
                yPos = yPos - idx * (buffIconSize + buffSpacing)
            end

            -- Map user anchor to frame anchor points (flip vertical only for outside positioning)
            -- Border compensation: icons have 1px border extending beyond frame
            local iconPoint, framePoint, borderOffsetX
            if buffAnchor == "TOPLEFT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMLEFT", "TOPLEFT", 1
            elseif buffAnchor == "TOPRIGHT" then
                iconPoint, framePoint, borderOffsetX = "BOTTOMRIGHT", "TOPRIGHT", -1
            elseif buffAnchor == "BOTTOMLEFT" then
                iconPoint, framePoint, borderOffsetX = "TOPLEFT", "BOTTOMLEFT", 1
            elseif buffAnchor == "BOTTOMRIGHT" then
                iconPoint, framePoint, borderOffsetX = "TOPRIGHT", "BOTTOMRIGHT", -1
            end

            icon:ClearAllPoints()
            icon:SetPoint(iconPoint, frame, framePoint, xPos + (borderOffsetX or 0), yPos)
            icon:Show()

            buffIndex = buffIndex + 1
        end
    end
end

-- Setup aura tracking for a frame
local function SetupAuraTracking(frame)
    if not frame then return end

    local unit = frame.unit

    -- Register aura events and unit-change events based on unit type
    frame:RegisterEvent("UNIT_AURA")
    if unit == "target" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unit == "focus" then
        frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    elseif unit == "pet" then
        frame:RegisterEvent("UNIT_PET")
    elseif unit == "targettarget" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")  -- ToT changes when target changes
        frame:RegisterEvent("UNIT_TARGET")            -- ToT changes when target's target changes
    elseif unit:match("^boss%d+$") then
        frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    end
    -- player: no extra event needed, UNIT_AURA handles it

    -- Hook into existing OnEvent or create new one
    local oldOnEvent = frame:GetScript("OnEvent")
    frame:SetScript("OnEvent", function(self, event, arg1, ...)
        if oldOnEvent then
            oldOnEvent(self, event, arg1, ...)
        end

        if event == "UNIT_AURA" and arg1 == self.unit then
            -- Force immediate update by clearing throttle
            lastAuraUpdate[self.unit] = 0
            UpdateAuras(self)
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Update target and targettarget when target changes
            if self.unit == "target" or self.unit == "targettarget" then
                lastAuraUpdate[self.unit] = 0
                UpdateAuras(self)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" and self.unit == "focus" then
            -- Clear throttle and update immediately on focus change
            lastAuraUpdate["focus"] = 0
            UpdateAuras(self)
        elseif event == "UNIT_PET" and self.unit == "pet" then
            -- Pet changed (summoned/dismissed)
            lastAuraUpdate["pet"] = 0
            UpdateAuras(self)
        elseif event == "UNIT_TARGET" and self.unit == "targettarget" then
            -- Target's target changed
            lastAuraUpdate["targettarget"] = 0
            UpdateAuras(self)
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" and self.unit:match("^boss%d+$") then
            -- Boss unit changed - full refresh for name, health, power, auras
            lastAuraUpdate[self.unit] = 0
            UpdateFrame(self)
            UpdateAuras(self)
        end
    end)
    
    -- Multiple initial updates to catch auras after load
    C_Timer.After(0.1, function()
        lastAuraUpdate[unit] = 0
        UpdateAuras(frame)
    end)
    C_Timer.After(0.5, function()
        lastAuraUpdate[unit] = 0
        UpdateAuras(frame)
    end)
    C_Timer.After(1.0, function()
        lastAuraUpdate[unit] = 0
        UpdateAuras(frame)
    end)
end

---------------------------------------------------------------------------
-- PREVIEW MODE: Show fake data
---------------------------------------------------------------------------
function QUI_UF:ShowPreview(unitKey)
    -- Handle boss frames specially - show all 5
    if unitKey == "boss" then
        local general = GetGeneralSettings()
        local settings = GetUnitSettings("boss")
        local spacing = settings and settings.spacing or 40
        
        -- First apply current settings to all boss frames
        self:RefreshFrame("boss")
        
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                self.previewMode[bossKey] = true
                if not InCombatLockdown() then
                    UnregisterStateDriver(frame, "visibility")
                end
                frame:Show()
                frame.healthBar:SetMinMaxValues(0, 100)
                frame.healthBar:SetValue(75 - (i * 5))  -- Vary health for visual distinction
                if frame.nameText then
                    frame.nameText:SetText("Boss " .. i)
                end
                if frame.healthText then
                    frame.healthText:SetText("75.0K - " .. (75 - (i * 5)) .. "%")
                end
                if frame.powerBar and settings and settings.showPowerBar then
                    frame.powerBar:SetMinMaxValues(0, 100)
                    frame.powerBar:SetValue(60)
                    frame.powerBar:Show()
                end

                -- Set fake power text
                if frame.powerText then
                    if settings and settings.showPowerText then
                        frame.powerText:SetText("60%")
                        if settings.powerTextUsePowerColor then
                            frame.powerText:SetTextColor(0, 0.6, 1, 1)
                        elseif settings.powerTextUseClassColor then
                            frame.powerText:SetTextColor(0.96, 0.55, 0.73, 1)
                        elseif settings.powerTextColor then
                            local c = settings.powerTextColor
                            frame.powerText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
                        else
                            frame.powerText:SetTextColor(1, 1, 1, 1)
                        end
                        frame.powerText:Show()
                    else
                        frame.powerText:Hide()
                    end
                end

                -- Apply colors
                if general and general.darkMode then
                    local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
                    frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                else
                    -- Default mode: use class color or custom default health color
                    if general and general.defaultUseClassColor then
                        local _, class = UnitClass("player")
                        if class and RAID_CLASS_COLORS[class] then
                            local color = RAID_CLASS_COLORS[class]
                            frame.healthBar:SetStatusBarColor(color.r, color.g, color.b, 1)
                        else
                            local c = general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
                            frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                        end
                    else
                        local c = general and general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
                        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                    end
                end

                -- Show boss castbar preview if castbar previewMode is enabled
                if settings and settings.castbar and settings.castbar.previewMode then
                    local castbar = self.castbars[bossKey]
                    if castbar and QUI_Castbar then
                        -- Trigger the castbar to show its preview
                        QUI_Castbar:RefreshBossCastbar(castbar, bossKey, settings.castbar, frame)
                    end
                end

                -- Show boss aura previews if aura previewMode is enabled
                if self.auraPreviewMode["boss_buff"] then
                    self:ShowAuraPreviewForFrame(frame, "boss", "buff")
                end
                if self.auraPreviewMode["boss_debuff"] then
                    self:ShowAuraPreviewForFrame(frame, "boss", "debuff")
                end
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end
    
    self.previewMode[unitKey] = true
    
    -- Unregister state driver so we can show the frame manually
    if not InCombatLockdown() then
        UnregisterStateDriver(frame, "visibility")
    end
    
    -- Show frame with fake data
    frame:Show()
    
    -- Set fake health
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(75)
    
    -- Set fake name
    if frame.nameText then
        local names = {
            player = UnitName("player") or "Player",
            target = "Target Dummy",
            targettarget = "ToT Name",
            pet = "Pet Name",
            focus = "Focus Target",
        }
        frame.nameText:SetText(names[unitKey] or "Preview")
    end
    
    -- Set fake health text
    if frame.healthText then
        frame.healthText:SetText("75.0K - 75%")
    end
    
    -- Set fake power
    if frame.powerBar then
        frame.powerBar:SetMinMaxValues(0, 100)
        frame.powerBar:SetValue(60)
        frame.powerBar:Show()
    end

    -- Set fake power text
    local settings = GetUnitSettings(unitKey)
    if frame.powerText then
        if settings and settings.showPowerText then
            frame.powerText:SetText("60%")
            if settings.powerTextUsePowerColor then
                frame.powerText:SetTextColor(0, 0.6, 1, 1)
            elseif settings.powerTextUseClassColor then
                frame.powerText:SetTextColor(0.96, 0.55, 0.73, 1)
            elseif settings.powerTextColor then
                local c = settings.powerTextColor
                frame.powerText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            else
                frame.powerText:SetTextColor(1, 1, 1, 1)
            end
            frame.powerText:Show()
        else
            frame.powerText:Hide()
        end
    end

    -- Apply colors for preview
    local general = GetGeneralSettings()

    if general and general.darkMode then
        local c = general.darkModeHealthColor or { 0.15, 0.15, 0.15, 1 }
        frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    else
        -- Default mode: use class color or custom default health color
        if general and general.defaultUseClassColor then
            local _, class = UnitClass("player")
            if class and RAID_CLASS_COLORS[class] then
                local color = RAID_CLASS_COLORS[class]
                frame.healthBar:SetStatusBarColor(color.r, color.g, color.b, 1)
            else
                local c = general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
                frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
            end
        else
            local c = general and general.defaultHealthColor or { 0.2, 0.2, 0.2, 1 }
            frame.healthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

function QUI_UF:HidePreview(unitKey)
    -- Handle boss frames specially - hide all 5
    if unitKey == "boss" then
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                self.previewMode[bossKey] = false
                -- Clear preview text so stale "Boss X" doesn't persist
                if frame.nameText then
                    frame.nameText:SetText("")
                end
                if not InCombatLockdown() then
                    RegisterStateDriver(frame, "visibility", "[@boss" .. i .. ",exists] show; hide")
                end
                if UnitExists("boss" .. i) then
                    UpdateFrame(frame)
                    frame:Show()
                else
                    frame:Hide()
                end

                -- Hide boss castbar preview
                local castbar = self.castbars[bossKey]
                if castbar then
                    castbar.isPreviewSimulation = false
                    castbar:SetScript("OnUpdate", nil)
                    castbar:Hide()
                end

                -- Hide boss aura previews
                self:HideAuraPreviewForFrame(frame, bossKey, "buff")
                self:HideAuraPreviewForFrame(frame, bossKey, "debuff")
            end
        end
        -- Clear aura preview mode flags (don't change the saved setting)
        -- Just visually hide them - the setting persists so they show when preview is re-enabled
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end
    
    self.previewMode[unitKey] = false
    
    -- Re-register state driver for non-player units
    if not InCombatLockdown() then
        local unit = frame.unit
        if unit == "target" then
            RegisterStateDriver(frame, "visibility", "[@target,exists] show; hide")
        elseif unit == "focus" then
            RegisterStateDriver(frame, "visibility", "[@focus,exists] show; hide")
        elseif unit == "pet" then
            RegisterStateDriver(frame, "visibility", "[@pet,exists] show; hide")
        elseif unit == "targettarget" then
            RegisterStateDriver(frame, "visibility", "[@targettarget,exists] show; hide")
        end
    end
    
    -- Restore real state
    if UnitExists(frame.unit) or unitKey == "player" then
        UpdateFrame(frame)
        frame:Show()
    else
        frame:Hide()
    end
end

---------------------------------------------------------------------------
-- AURA PREVIEW MODE: Show fake buff/debuff icons
---------------------------------------------------------------------------
function QUI_UF:ShowAuraPreview(unitKey, auraType)
    -- Handle boss frames specially - show aura preview on all 5
    if unitKey == "boss" then
        local previewKey = "boss_" .. auraType
        self.auraPreviewMode[previewKey] = true
        -- Only show if boss frame preview is active
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame and self.previewMode[bossKey] then
                self:ShowAuraPreviewForFrame(frame, "boss", auraType)
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    local previewKey = unitKey .. "_" .. auraType
    self.auraPreviewMode[previewKey] = true

    self:ShowAuraPreviewForFrame(frame, unitKey, auraType)
end

function QUI_UF:ShowAuraPreviewForFrame(frame, unitKey, auraType)
    if not frame then return end

    -- Get settings
    local settings = GetUnitSettings(unitKey)
    local auraSettings = settings and settings.auras or {}

    -- Determine which preview data and settings to use
    local previewData = (auraType == "buff") and PREVIEW_AURAS.buffs or PREVIEW_AURAS.debuffs
    local isDebuff = (auraType == "debuff")

    -- Get size and positioning settings
    local iconSize, anchor, grow, offsetX, offsetY, spacing, maxIcons
    if isDebuff then
        iconSize = auraSettings.iconSize or 22
        anchor = auraSettings.debuffAnchor or "TOPLEFT"
        grow = auraSettings.debuffGrow or "RIGHT"
        offsetX = auraSettings.debuffOffsetX or 0
        offsetY = auraSettings.debuffOffsetY or 2
        spacing = auraSettings.debuffSpacing or 2
        maxIcons = auraSettings.debuffMaxIcons or 16
    else
        iconSize = auraSettings.buffIconSize or 22
        anchor = auraSettings.buffAnchor or "BOTTOMLEFT"
        grow = auraSettings.buffGrow or "RIGHT"
        offsetX = auraSettings.buffOffsetX or 0
        offsetY = auraSettings.buffOffsetY or -2
        spacing = auraSettings.buffSpacing or 2
        maxIcons = auraSettings.buffMaxIcons or 16
    end

    -- Initialize preview icon container if needed
    local containerKey = isDebuff and "previewDebuffIcons" or "previewBuffIcons"
    frame[containerKey] = frame[containerKey] or {}
    local container = frame[containerKey]

    -- Hide real auras of this type
    local realContainer = isDebuff and frame.debuffIcons or frame.buffIcons
    if realContainer then
        for _, icon in ipairs(realContainer) do
            icon:Hide()
        end
    end

    -- Hide any existing preview icons first (in case maxIcons was reduced)
    for _, icon in ipairs(container) do
        icon:SetScript("OnUpdate", nil)
        icon:Hide()
    end

    -- Track start time for looping cooldown animation
    local previewStartTime = GetTime()
    local previewDuration = 10
    local previewDataCount = #previewData

    -- Create/show preview icons based on maxIcons setting
    for i = 1, maxIcons do
        -- Cycle through mock data using modulo
        local dataIndex = ((i - 1) % previewDataCount) + 1
        local auraData = previewData[dataIndex]
        local icon = container[i]
        if not icon then
            -- Create new preview icon (simplified, no tooltip interaction needed)
            icon = CreateFrame("Frame", nil, frame)
            icon:SetFrameLevel(frame:GetFrameLevel() + 10)

            -- Border
            local border = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
            border:SetColorTexture(0, 0, 0, 1)
            local prevIconPx = QUICore:GetPixelSize(icon)
            border:SetPoint("TOPLEFT", icon, "TOPLEFT", -prevIconPx, prevIconPx)
            border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", prevIconPx, -prevIconPx)
            icon.border = border

            -- Icon texture
            local tex = icon:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", 0, 0)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon.icon = tex

            -- Cooldown swipe
            local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:SetDrawEdge(false)
            cd:SetReverse(true)
            cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
            cd:SetSwipeColor(0, 0, 0, 0.8)
            cd.noOCC = true
            cd.noCooldownCount = true
            icon.cooldown = cd

            -- Stack count
            local count = icon:CreateFontString(nil, "OVERLAY")
            count:SetTextColor(1, 1, 1, 1)
            icon.count = count

            container[i] = icon
        end

        -- Configure icon size
        icon:SetSize(iconSize, iconSize)

        -- Apply settings (font, stack position, etc.)
        local fontPath = GetFontPath()
        local fontOutline = GetFontOutline()
        local prefix = isDebuff and "debuff" or "buff"

        local showStack = auraSettings[prefix .. "ShowStack"]
        if showStack == nil then showStack = auraSettings.showStack end
        if showStack == nil then showStack = true end

        local stackSize = auraSettings[prefix .. "StackSize"] or auraSettings.stackSize or 10
        local stackAnchor = auraSettings[prefix .. "StackAnchor"] or auraSettings.stackAnchor or "BOTTOMRIGHT"
        local stackOffsetX = auraSettings[prefix .. "StackOffsetX"] or auraSettings.stackOffsetX or -1
        local stackOffsetY = auraSettings[prefix .. "StackOffsetY"] or auraSettings.stackOffsetY or 1
        local stackColor = auraSettings[prefix .. "StackColor"] or auraSettings.stackColor or {1, 1, 1, 1}

        icon.count:SetFont(fontPath, stackSize, fontOutline)
        icon.count:ClearAllPoints()
        icon.count:SetPoint(stackAnchor, icon, stackAnchor, stackOffsetX, stackOffsetY)
        icon.count:SetTextColor(stackColor[1] or 1, stackColor[2] or 1, stackColor[3] or 1, stackColor[4] or 1)

        -- Hide Duration Swipe setting
        local hideSwipe = auraSettings[prefix .. "HideSwipe"]
        if hideSwipe == nil then hideSwipe = false end
        icon.cooldown:SetDrawSwipe(not hideSwipe)

        -- Set texture
        icon.icon:SetTexture(auraData.icon)

        -- Set border color (red for debuffs, black for buffs)
        if isDebuff then
            icon.border:SetColorTexture(0.8, 0.2, 0.2, 1)
        else
            icon.border:SetColorTexture(0, 0, 0, 1)
        end

        -- Set stack count
        if showStack and auraData.stacks and auraData.stacks > 1 then
            icon.count:SetText(auraData.stacks)
            icon.count:Show()
        else
            icon.count:Hide()
        end

        -- Calculate position
        local idx = i - 1
        local xPos, yPos = offsetX, offsetY
        if grow == "RIGHT" then
            xPos = xPos + idx * (iconSize + spacing)
        elseif grow == "LEFT" then
            xPos = xPos - idx * (iconSize + spacing)
        elseif grow == "UP" then
            yPos = yPos + idx * (iconSize + spacing)
        elseif grow == "DOWN" then
            yPos = yPos - idx * (iconSize + spacing)
        end

        -- Map user anchor to frame anchor points (flip vertical only for outside positioning)
        -- Border compensation: icons have 1px border extending beyond frame
        local iconPoint, framePoint, borderOffsetX
        if anchor == "TOPLEFT" then
            iconPoint, framePoint, borderOffsetX = "BOTTOMLEFT", "TOPLEFT", 1
        elseif anchor == "TOPRIGHT" then
            iconPoint, framePoint, borderOffsetX = "BOTTOMRIGHT", "TOPRIGHT", -1
        elseif anchor == "BOTTOMLEFT" then
            iconPoint, framePoint, borderOffsetX = "TOPLEFT", "BOTTOMLEFT", 1
        elseif anchor == "BOTTOMRIGHT" then
            iconPoint, framePoint, borderOffsetX = "TOPRIGHT", "BOTTOMRIGHT", -1
        end

        icon:ClearAllPoints()
        icon:SetPoint(iconPoint, frame, framePoint, xPos + (borderOffsetX or 0), yPos)

        -- Setup looping cooldown animation
        icon.cooldown:SetCooldown(previewStartTime, previewDuration)
        icon.cooldown:Show()

        -- Store start time for OnUpdate loop
        icon._previewStartTime = previewStartTime
        icon._previewDuration = previewDuration

        icon:SetScript("OnUpdate", function(self, elapsed)
            local now = GetTime()
            local elapsedTime = now - self._previewStartTime
            if elapsedTime >= self._previewDuration then
                self._previewStartTime = now
                self.cooldown:SetCooldown(now, self._previewDuration)
            end
        end)

        icon:Show()
    end
end

function QUI_UF:HideAuraPreview(unitKey, auraType)
    -- Handle boss frames specially - hide aura preview on all 5
    if unitKey == "boss" then
        local previewKey = "boss_" .. auraType
        self.auraPreviewMode[previewKey] = false
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                self:HideAuraPreviewForFrame(frame, bossKey, auraType)
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    local previewKey = unitKey .. "_" .. auraType
    self.auraPreviewMode[previewKey] = false

    self:HideAuraPreviewForFrame(frame, unitKey, auraType)
end

function QUI_UF:HideAuraPreviewForFrame(frame, unitKey, auraType)
    if not frame then return end

    local isDebuff = (auraType == "debuff")
    local containerKey = isDebuff and "previewDebuffIcons" or "previewBuffIcons"
    local container = frame[containerKey]

    -- Hide and cleanup preview icons
    if container then
        for _, icon in ipairs(container) do
            icon:SetScript("OnUpdate", nil)
            icon:Hide()
        end
    end

    -- Refresh real auras
    lastAuraUpdate[unitKey] = 0
    UpdateAuras(frame)
end

---------------------------------------------------------------------------
-- REFRESH: Apply settings changes
---------------------------------------------------------------------------
function QUI_UF:RefreshFrame(unitKey)
    -- Handle boss frames specially - refresh all 5
    if unitKey == "boss" then
        local settings = GetUnitSettings("boss")
        local general = GetGeneralSettings()
        local spacing = settings and settings.spacing or 40
        
        if not settings or InCombatLockdown() then
            -- Just update non-secure elements
            for i = 1, 5 do
                local frame = self.frames["boss" .. i]
                if frame then UpdateFrame(frame) end
            end
            return
        end
        
        local borderPx = settings.borderSize or 1
        local texturePath = GetTexturePath(settings.texture)

        -- Get HUD layer priority for boss frames
        local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
        local bossLayerPriority = hudLayering and hudLayering.bossFrames or 4
        local bossFrameLevel
        if QUICore and QUICore.GetHUDFrameLevel then
            bossFrameLevel = QUICore:GetHUDFrameLevel(bossLayerPriority)
        end

        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                -- Apply HUD layer priority
                if bossFrameLevel then
                    frame:SetFrameLevel(bossFrameLevel)
                end

                -- Pixel-perfect values per frame
                local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0
                local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
                local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0

                -- Update size (config values are virtual coords, snap to pixel grid)
                local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
    frame:SetSize(width, height)

                -- Position: first boss at configured position, rest stacked below
                frame:ClearAllPoints()
                if i == 1 then
                    if QUICore.SetSnappedPoint then
                        QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
                    else
                        frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
                    end
                else
                    local prevFrame = self.frames["boss" .. (i - 1)]
                    if prevFrame then
                        frame:SetPoint("TOP", prevFrame, "BOTTOM", 0, -spacing)
                    end
                end

                -- Get colors and separate opacity values based on dark mode state
                local bgColor, healthOpacity, bgOpacity
                if general and general.darkMode then
                    bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
                    healthOpacity = general.darkModeHealthOpacity or general.darkModeOpacity or 1.0
                    bgOpacity = general.darkModeBgOpacity or general.darkModeOpacity or 1.0
                else
                    bgColor = general and general.defaultBgColor or { 0.1, 0.1, 0.1, 0.9 }
                    healthOpacity = general and general.defaultHealthOpacity or general and general.defaultOpacity or 1.0
                    bgOpacity = general and general.defaultBgOpacity or general and general.defaultOpacity or 1.0
                end
                local bgAlpha = (bgColor[4] or 1) * bgOpacity

                -- Update backdrop (including border size)
                frame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
                    edgeSize = borderSize > 0 and borderSize or nil,
                })
                frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgAlpha)
                if borderSize > 0 then
                    frame:SetBackdropBorderColor(0, 0, 0, 1)
                end

                -- Apply opacity to bars only (not text)
                frame.healthBar:SetAlpha(healthOpacity)
                if frame.powerBar then frame.powerBar:SetAlpha(healthOpacity) end

                -- Update health bar texture and position
                frame.healthBar:SetStatusBarTexture(texturePath)
                frame.healthBar:ClearAllPoints()
                frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
                frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
                
                -- Update power bar
                if frame.powerBar then
                    if settings.showPowerBar then
                        frame.powerBar:SetStatusBarTexture(texturePath)
                        frame.powerBar:ClearAllPoints()
                        frame.powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
                        frame.powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
                        frame.powerBar:SetHeight(powerHeight)
                        frame.powerBar:Show()
                    else
                        frame.powerBar:Hide()
                    end
                end

                -- Update power bar separator
                if frame.powerBarSeparator then
                    if settings.showPowerBar and settings.powerBarBorder ~= false then
                        frame.powerBarSeparator:Show()
                    else
                        frame.powerBarSeparator:Hide()
                    end
                end

                -- Update name text (create dynamically if needed)
                if settings.showName then
                    if not frame.nameText then
                        local nameText = frame.healthBar:CreateFontString(nil, "OVERLAY")
                        nameText:SetShadowOffset(0, 0)
                        frame.nameText = nameText
                    end
                    frame.nameText:SetFont(GetFontPath(), settings.nameFontSize or 11, GetFontOutline())
                    local nameAnchorInfo = GetTextAnchorInfo(settings.nameAnchor or "LEFT")
                    local nameOffsetX = QUICore:PixelRound(settings.nameOffsetX or 4, frame.healthBar)
                    local nameOffsetY = QUICore:PixelRound(settings.nameOffsetY or 0, frame.healthBar)
                    frame.nameText:ClearAllPoints()
                    frame.nameText:SetPoint(nameAnchorInfo.point, frame.healthBar, nameAnchorInfo.point, nameOffsetX, nameOffsetY)
                    frame.nameText:SetJustifyH(nameAnchorInfo.justify)
                    frame.nameText:Show()
                    -- In preview mode, set preview text; otherwise update with real data
                    if self.previewMode[bossKey] then
                        frame.nameText:SetText("Boss " .. i)
                    else
                        UpdateName(frame)
                    end
                elseif frame.nameText then
                    frame.nameText:Hide()
                end

                -- Update health text (create dynamically if needed)
                if settings.showHealth then
                    if not frame.healthText then
                        local healthText = frame.healthBar:CreateFontString(nil, "OVERLAY")
                        healthText:SetShadowOffset(0, 0)
                        frame.healthText = healthText
                    end
                    frame.healthText:SetFont(GetFontPath(), settings.healthFontSize or 11, GetFontOutline())
                    local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
                    local healthOffsetX = QUICore:PixelRound(settings.healthOffsetX or -4, frame.healthBar)
                    local healthOffsetY = QUICore:PixelRound(settings.healthOffsetY or 0, frame.healthBar)
                    frame.healthText:ClearAllPoints()
                    frame.healthText:SetPoint(healthAnchorInfo.point, frame.healthBar, healthAnchorInfo.point, healthOffsetX, healthOffsetY)
                    frame.healthText:SetJustifyH(healthAnchorInfo.justify)
                    frame.healthText:Show()
                    -- In preview mode, set preview text; otherwise update with real data
                    if self.previewMode[bossKey] then
                        -- Use same mock format as ShowPreview: "75.0K - X%"
                        frame.healthText:SetText("75.0K - " .. (75 - (i * 5)) .. "%")
                    else
                        UpdateHealth(frame)
                    end
                elseif frame.healthText then
                    frame.healthText:Hide()
                end

                -- Update power text (create dynamically if needed)
                if settings.showPowerText then
                    if not frame.powerText then
                        local powerText = frame.healthBar:CreateFontString(nil, "OVERLAY")
                        powerText:SetShadowOffset(0, 0)
                        frame.powerText = powerText
                    end
                    local fontPath = GetFontPath()
                    local fontOutline = GetFontOutline()
                    frame.powerText:SetFont(fontPath, settings.powerTextFontSize or 12, fontOutline)
                    frame.powerText:ClearAllPoints()
                    local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
                    local powerOffsetX = QUICore:PixelRound(settings.powerTextOffsetX or -4, frame.healthBar)
                    local powerOffsetY = QUICore:PixelRound(settings.powerTextOffsetY or 2, frame.healthBar)
                    frame.powerText:SetPoint(powerAnchorInfo.point, frame.healthBar, powerAnchorInfo.point, powerOffsetX, powerOffsetY)
                    frame.powerText:SetJustifyH(powerAnchorInfo.justify)
                    frame.powerText:Show()
                    -- In preview mode, set preview text; otherwise update with real data
                    if self.previewMode[bossKey] then
                        -- Use same mock value as ShowPreview
                        frame.powerText:SetText("60%")
                    else
                        UpdatePowerText(frame)
                    end
                elseif frame.powerText then
                    frame.powerText:Hide()
                end

                -- Update target marker (boss frames)
                if frame.targetMarker and settings.targetMarker then
                    local marker = settings.targetMarker
                    frame.targetMarker:SetSize(marker.size or 20, marker.size or 20)
                    frame.targetMarker:ClearAllPoints()
                    local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
                    frame.targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
                    UpdateTargetMarker(frame)
                end

                -- Only update with real data if not in preview mode
                if not self.previewMode[bossKey] then
                    UpdateFrame(frame)
                end
                
                -- Refresh boss castbar if it exists (delegate to castbar module)
                local castbar = self.castbars[bossKey]
                if castbar and QUI_Castbar and QUI_Castbar.RefreshBossCastbar then
                    local castSettings = settings.castbar
                    if castSettings then
                        QUI_Castbar:RefreshBossCastbar(castbar, bossKey, castSettings, frame)
                    end
                end
            end
        end
        return
    end
    
    local frame = self.frames[unitKey]
    if not frame then return end

    -- Skip frame modifications during combat (secure frames are protected)
    if InCombatLockdown() then
        -- Only update non-secure elements (colors, text)
        UpdateFrame(frame)
        return
    end

    local settings = GetUnitSettings(unitKey)
    local general = GetGeneralSettings()
    if not settings then return end

    -- Apply HUD layer priority
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerKey = unitKey .. "Frame"
    -- Map unitKey to hudLayering key (player -> playerFrame, target -> targetFrame, etc.)
    local layerPriority
    if unitKey == "player" then
        layerPriority = hudLayering and hudLayering.playerFrame or 4
    elseif unitKey == "target" then
        layerPriority = hudLayering and hudLayering.targetFrame or 4
    elseif unitKey == "targettarget" then
        layerPriority = hudLayering and hudLayering.totFrame or 3
    elseif unitKey == "pet" then
        layerPriority = hudLayering and hudLayering.petFrame or 3
    elseif unitKey == "focus" then
        layerPriority = hudLayering and hudLayering.focusFrame or 4
    else
        layerPriority = 4  -- Default for any other unit type
    end
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        frame:SetFrameLevel(frameLevel)
    end

    -- Update size (config values are virtual coords, snap to pixel grid)
    local width = (QUICore.PixelRound and QUICore:PixelRound(settings.width or 220, frame)) or (settings.width or 220)
    local height = (QUICore.PixelRound and QUICore:PixelRound(settings.height or 35, frame)) or (settings.height or 35)
    frame:SetSize(width, height)

    -- Update position
    frame:ClearAllPoints()
    local isAnchored = settings.anchorTo and settings.anchorTo ~= "disabled"
    if isAnchored and (unitKey == "player" or unitKey == "target") then
        -- Anchored to another frame: defer to the global callback
        _G.QUI_UpdateAnchoredUnitFrames()
    else
        -- Standard positioning (config offsets are virtual coords)
        if QUICore.SetSnappedPoint then
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 0)
        end
    end
    
    -- Get colors and separate opacity values based on dark mode state
    local bgColor, healthOpacity, bgOpacity
    if general and general.darkMode then
        bgColor = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
        healthOpacity = general.darkModeHealthOpacity or general.darkModeOpacity or 1.0
        bgOpacity = general.darkModeBgOpacity or general.darkModeOpacity or 1.0
    else
        bgColor = general and general.defaultBgColor or { 0.1, 0.1, 0.1, 0.9 }
        healthOpacity = general and general.defaultHealthOpacity or general and general.defaultOpacity or 1.0
        bgOpacity = general and general.defaultBgOpacity or general and general.defaultOpacity or 1.0
    end
    local bgAlpha = (bgColor[4] or 1) * bgOpacity

    -- Pixel-perfect border size
    local borderPx = settings.borderSize or 1
    local borderSize = borderPx > 0 and QUICore:Pixels(borderPx, frame) or 0

    -- Update backdrop (including border size)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = borderSize > 0 and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = borderSize > 0 and borderSize or nil,
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgAlpha)
    if borderSize > 0 then
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    -- Apply opacity to bars only (not text)
    frame.healthBar:SetAlpha(healthOpacity)
    if frame.powerBar then frame.powerBar:SetAlpha(healthOpacity) end

    -- Update power bar height (config value is virtual coords, snap to pixel grid)
    local powerHeight = settings.showPowerBar and QUICore:PixelRound(settings.powerBarHeight or 4, frame) or 0
    local separatorHeight = (settings.showPowerBar and settings.powerBarBorder ~= false) and QUICore:GetPixelSize(frame) or 0

    -- Update health bar texture
    local texturePath = GetTexturePath(settings.texture)
    frame.healthBar:SetStatusBarTexture(texturePath)

    -- Resize health bar (pixel-perfect)
    frame.healthBar:ClearAllPoints()
    frame.healthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", borderSize, -borderSize)
    frame.healthBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize + powerHeight + separatorHeight)
    
    -- Update power bar (create dynamically if needed)
    if settings.showPowerBar then
        if not frame.powerBar then
            -- Create power bar dynamically when setting is enabled
            local powerBar = CreateFrame("StatusBar", nil, frame)
            powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
            powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
            powerBar:SetHeight(powerHeight)
            powerBar:SetStatusBarTexture(texturePath)
            powerBar:SetMinMaxValues(0, 100)
            powerBar:SetValue(100)
            local powerColor = settings.powerBarColor or { 0, 0.5, 1, 1 }
            powerBar:SetStatusBarColor(powerColor[1], powerColor[2], powerColor[3], powerColor[4] or 1)
            powerBar:EnableMouse(false)
            frame.powerBar = powerBar
        end
        -- Update existing power bar
        frame.powerBar:SetStatusBarTexture(texturePath)
        frame.powerBar:ClearAllPoints()
        frame.powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", borderSize, borderSize)
        frame.powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -borderSize, borderSize)
        frame.powerBar:SetHeight(powerHeight)
        frame.powerBar:Show()
    elseif frame.powerBar then
        frame.powerBar:Hide()
    end

    -- Update power bar separator (create dynamically if needed)
    if settings.showPowerBar and settings.powerBarBorder ~= false then
        if not frame.powerBarSeparator then
            -- Create separator dynamically
            local separator = frame.powerBar:CreateTexture(nil, "OVERLAY")
            separator:SetHeight(QUICore:GetPixelSize(frame.powerBar))
            separator:SetPoint("BOTTOMLEFT", frame.powerBar, "TOPLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", frame.powerBar, "TOPRIGHT", 0, 0)
            separator:SetTexture("Interface\\Buttons\\WHITE8x8")
            separator:SetVertexColor(0, 0, 0, 1)
            frame.powerBarSeparator = separator
        end
        frame.powerBarSeparator:Show()
    elseif frame.powerBarSeparator then
        frame.powerBarSeparator:Hide()
    end

    -- Update portrait (create dynamically if needed)
    if settings.showPortrait then
        local portraitSizePx = settings.portraitSize or 40
        local side = settings.portraitSide or "LEFT"

        if not frame.portrait then
            local portrait = CreateFrame("Button", nil, frame, "SecureUnitButtonTemplate, BackdropTemplate")
            local portraitTex = portrait:CreateTexture(nil, "ARTWORK")
            frame.portraitTexture = portraitTex
            frame.portrait = portrait

            -- Secure unit attributes for click targeting
            portrait:SetAttribute("unit", frame.unit)
            portrait:SetAttribute("*type1", "target")
            portrait:SetAttribute("*type2", "togglemenu")
            portrait:RegisterForClicks("AnyUp")

            -- Tooltip on hover
            portrait:HookScript("OnEnter", function(self)
                ShowUnitTooltip(frame)
            end)
            portrait:HookScript("OnLeave", HideUnitTooltip)
        end

        -- Pixel-perfect portrait values
        local portraitBorderSize = QUICore:Pixels(settings.portraitBorderSize or 1, frame.portrait)
        local portraitGap = QUICore:PixelRound(settings.portraitGap or 0, frame.portrait)
        local portraitOffsetX = QUICore:PixelRound(settings.portraitOffsetX or 0, frame.portrait)
        local portraitOffsetY = QUICore:PixelRound(settings.portraitOffsetY or 0, frame.portrait)

        -- Update size and position (config value is virtual coords, snap to pixel grid)
        frame.portrait:SetSize(QUICore:PixelRound(portraitSizePx, frame.portrait), QUICore:PixelRound(portraitSizePx, frame.portrait))
        frame.portrait:ClearAllPoints()
        if side == "LEFT" then
            frame.portrait:SetPoint("RIGHT", frame, "LEFT", -portraitGap + portraitOffsetX, portraitOffsetY)
        else
            frame.portrait:SetPoint("LEFT", frame, "RIGHT", portraitGap + portraitOffsetX, portraitOffsetY)
        end

        -- Determine border color first (needed for both styles)
        local borderR, borderG, borderB = 0, 0, 0
        if settings.portraitBorderUseClassColor then
            local _, class = UnitClass(frame.unit)
            if class then
                local classColor = RAID_CLASS_COLORS[class]
                if classColor then
                    borderR, borderG, borderB = classColor.r, classColor.g, classColor.b
                end
            end
        elseif settings.portraitBorderColor then
            borderR = settings.portraitBorderColor[1] or 0
            borderG = settings.portraitBorderColor[2] or 0
            borderB = settings.portraitBorderColor[3] or 0
        end

        frame.portrait:SetBackdrop({
            bgFile = nil,
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = portraitBorderSize,
        })
        frame.portrait:SetBackdropBorderColor(borderR, borderG, borderB, 1)

        -- Position portrait texture inside border
        frame.portraitTexture:ClearAllPoints()
        frame.portraitTexture:SetPoint("TOPLEFT", portraitBorderSize, -portraitBorderSize)
        frame.portraitTexture:SetPoint("BOTTOMRIGHT", -portraitBorderSize, portraitBorderSize)

        -- Update portrait texture
        if UnitExists(frame.unit) then
            SetPortraitTexture(frame.portraitTexture, frame.unit, true)
            frame.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
        end

        frame.portrait:Show()
    elseif frame.portrait then
        frame.portrait:Hide()
    end

    -- Update fonts and text positions
    local fontPath = GetFontPath()
    local fontOutline = general and general.fontOutline or "OUTLINE"
    
    if frame.nameText then
        frame.nameText:SetFont(fontPath, settings.nameFontSize or 12, fontOutline)
        frame.nameText:ClearAllPoints()
        local nameAnchorInfo = GetTextAnchorInfo(settings.nameAnchor or "LEFT")
        frame.nameText:SetPoint(nameAnchorInfo.point, frame, nameAnchorInfo.point, QUICore:PixelRound(settings.nameOffsetX or 4, frame), QUICore:PixelRound(settings.nameOffsetY or 0, frame))
        frame.nameText:SetJustifyH(nameAnchorInfo.justify)
        if settings.showName then
            frame.nameText:Show()
        else
            frame.nameText:Hide()
        end
    end
    
    if frame.healthText then
        frame.healthText:SetFont(fontPath, settings.healthFontSize or 12, fontOutline)
        frame.healthText:ClearAllPoints()
        local healthAnchorInfo = GetTextAnchorInfo(settings.healthAnchor or "RIGHT")
        frame.healthText:SetPoint(healthAnchorInfo.point, frame, healthAnchorInfo.point, QUICore:PixelRound(settings.healthOffsetX or -4, frame), QUICore:PixelRound(settings.healthOffsetY or 0, frame))
        frame.healthText:SetJustifyH(healthAnchorInfo.justify)
        -- Show/hide health text based on showHealth toggle first
        if settings.showHealth == false then
            frame.healthText:Hide()
        else
            -- Show health text based on display style (backwards compatible)
            local displayStyle = settings.healthDisplayStyle
            if displayStyle and displayStyle ~= "" then
                frame.healthText:Show()
            else
                -- Backwards compat: check old showHealthAbsolute/showHealthPercent
                local showAbsolute = settings.showHealthAbsolute
                local showPercent = settings.showHealthPercent
                if showAbsolute or showPercent then
                    frame.healthText:Show()
                else
                    frame.healthText:Hide()
                end
            end
        end
    end

    -- Update power text position and font
    if frame.powerText then
        frame.powerText:SetFont(fontPath, settings.powerTextFontSize or 12, fontOutline)
        frame.powerText:ClearAllPoints()
        local powerAnchorInfo = GetTextAnchorInfo(settings.powerTextAnchor or "BOTTOMRIGHT")
        frame.powerText:SetPoint(powerAnchorInfo.point, frame, powerAnchorInfo.point, QUICore:PixelRound(settings.powerTextOffsetX or -4, frame), QUICore:PixelRound(settings.powerTextOffsetY or 2, frame))
        frame.powerText:SetJustifyH(powerAnchorInfo.justify)
        -- Show/hide handled by UpdatePowerText based on settings.showPowerText
    end

    -- Update status indicators (player only)
    if unitKey == "player" and settings.indicators then
        local indSettings = settings.indicators

        -- Rested indicator
        if frame.restedIndicator and indSettings.rested then
            local rested = indSettings.rested
            frame.restedIndicator:SetSize(rested.size or 16, rested.size or 16)
            frame.restedIndicator:ClearAllPoints()
            local anchorInfo = GetTextAnchorInfo(rested.anchor or "TOPLEFT")
            frame.restedIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, rested.offsetX or -2, rested.offsetY or 2)
        end

        -- Combat indicator
        if frame.combatIndicator and indSettings.combat then
            local combat = indSettings.combat
            frame.combatIndicator:SetSize(combat.size or 16, combat.size or 16)
            frame.combatIndicator:ClearAllPoints()
            local anchorInfo = GetTextAnchorInfo(combat.anchor or "TOPLEFT")
            frame.combatIndicator:SetPoint(anchorInfo.point, frame, anchorInfo.point, combat.offsetX or -2, combat.offsetY or 2)
        end

        -- Stance/form text - call UpdateStance to refresh font, position, color
        if frame.stanceText then
            UpdateStance(frame)
        end

        -- Apply HUD layer priority to indicator frame (independent from player frame)
        if frame.indicatorFrame then
            local indicatorPriority = hudLayering and hudLayering.playerIndicators or 6
            if QUICore and QUICore.GetHUDFrameLevel then
                local indicatorLevel = QUICore:GetHUDFrameLevel(indicatorPriority)
                frame.indicatorFrame:SetFrameLevel(indicatorLevel)
            end
        end
    end

    -- Update target marker (all unit frames)
    if frame.targetMarker and settings.targetMarker then
        local marker = settings.targetMarker
        frame.targetMarker:SetSize(marker.size or 20, marker.size or 20)
        frame.targetMarker:ClearAllPoints()
        local anchorInfo = GetTextAnchorInfo(marker.anchor or "TOP")
        frame.targetMarker:SetPoint(anchorInfo.point, frame, anchorInfo.point, marker.xOffset or 0, marker.yOffset or 8)
        UpdateTargetMarker(frame)
    end

    -- Update leader/assistant icon (player, target, focus only)
    if settings.leaderIcon and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
        local leader = settings.leaderIcon
        if leader.enabled then
            -- Create icon if it doesn't exist (feature was enabled after initial load)
            if not frame.leaderIcon then
                if not frame.indicatorFrame then
                    local indicatorFrame = CreateFrame("Frame", nil, frame)
                    indicatorFrame:SetAllPoints()
                    indicatorFrame:SetFrameLevel(frame.textFrame:GetFrameLevel() + 5)
                    frame.indicatorFrame = indicatorFrame
                end
                local leaderIcon = frame.indicatorFrame:CreateTexture(nil, "OVERLAY")
                leaderIcon:Hide()
                frame.leaderIcon = leaderIcon
                -- Register events if not already registered
                frame:RegisterEvent("PARTY_LEADER_CHANGED")
                frame:RegisterEvent("GROUP_ROSTER_UPDATE")
            end
            -- Update size and position
            frame.leaderIcon:SetSize(leader.size or 16, leader.size or 16)
            frame.leaderIcon:ClearAllPoints()
            local anchorInfo = GetTextAnchorInfo(leader.anchor or "TOPLEFT")
            frame.leaderIcon:SetPoint(anchorInfo.point, frame, anchorInfo.point, leader.xOffset or -8, leader.yOffset or 8)
            UpdateLeaderIcon(frame)
        elseif frame.leaderIcon then
            -- Feature disabled - hide the icon
            frame.leaderIcon:Hide()
        end
    end

    -- Update colors and values
    if self.previewMode[unitKey] then
        self:ShowPreview(unitKey)
    else
        UpdateFrame(frame)
    end
    
    -- Refresh castbar if exists, OR create if newly enabled
    local castbar = self.castbars[unitKey]
    local castSettings = settings.castbar
    if castSettings and castSettings.enabled then
        if castbar and QUI_Castbar and QUI_Castbar.RefreshCastbar then
            -- Castbar exists - refresh it
            QUI_Castbar:RefreshCastbar(castbar, unitKey, castSettings, frame)
        elseif not castbar and QUI_Castbar and QUI_Castbar.CreateCastbar then
            -- Castbar doesn't exist but is now enabled - create it
            self.castbars[unitKey] = QUI_Castbar:CreateCastbar(frame, unitKey, unitKey)
        end
    end
end

function QUI_UF:RefreshAll()
    -- Track if we've refreshed boss frames to avoid doing it 5 times
    local bossRefreshed = false
    
    for unitKey, frame in pairs(self.frames) do
        -- Boss frames (boss1-boss5) share settings from "boss" key
        if unitKey:match("^boss%d+$") then
            if not bossRefreshed then
                self:RefreshFrame("boss")  -- Refresh all 5 at once
                bossRefreshed = true
            end
        else
            self:RefreshFrame(unitKey)
        end
    end
end

---------------------------------------------------------------------------
-- EDIT MODE: Toggle draggable frames with arrow nudge buttons
---------------------------------------------------------------------------
QUI_UF.editModeActive = false

-- Register slider references for real-time sync during edit mode
function QUI_UF:RegisterEditModeSliders(unitKey, xSlider, ySlider)
    self.editModeSliders[unitKey] = self.editModeSliders[unitKey] or {}
    self.editModeSliders[unitKey].x = xSlider
    self.editModeSliders[unitKey].y = ySlider
end

-- Update sliders and coordinate display when position changes
function QUI_UF:NotifyPositionChanged(unitKey, offsetX, offsetY)
    -- Update options panel sliders if registered
    local sliders = self.editModeSliders[unitKey]
    if sliders then
        if sliders.x and sliders.x.SetValue then
            sliders.x.SetValue(offsetX, true)  -- true = skip onChange callback
        end
        if sliders.y and sliders.y.SetValue then
            sliders.y.SetValue(offsetY, true)
        end
    end

    -- Update info text on overlay if visible
    local frame = self.frames[unitKey]
    if frame and frame.editOverlay and frame.editOverlay.infoText then
        local label = frame.editOverlay.unitLabel or unitKey
        frame.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d", label, offsetX, offsetY))
    end
end

-- Helper: Create nudge button with chevron arrows (dropdown style)
local function CreateNudgeButton(parent, direction, deltaX, deltaY, unitKey)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)

    -- Background - dark grey at 70% for visibility over any game content
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)
    btn.bg = bg

    -- Chevron lines - white for high contrast
    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)

    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    -- Direction-specific angles and positions
    if direction == "DOWN" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, 1)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, 1)
        line2:SetRotation(math.rad(45))
    elseif direction == "UP" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, -1)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, -1)
        line2:SetRotation(math.rad(-45))
    elseif direction == "LEFT" then
        line1:SetPoint("CENTER", btn, "CENTER", -1, -2)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", -1, 2)
        line2:SetRotation(math.rad(45))
    elseif direction == "RIGHT" then
        line1:SetPoint("CENTER", btn, "CENTER", 1, -2)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 1, 2)
        line2:SetRotation(math.rad(-45))
    end
    btn.line1 = line1
    btn.line2 = line2

    -- Hover effect - mint accent on hover
    btn:SetScript("OnEnter", function(self)
        self.line1:SetColorTexture(0.204, 0.827, 0.6, 1)
        self.line2:SetColorTexture(0.204, 0.827, 0.6, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.line1:SetColorTexture(1, 1, 1, 0.9)
        self.line2:SetColorTexture(1, 1, 1, 0.9)
    end)
    
    btn:SetScript("OnClick", function()
        local frame = parent:GetParent()
        local settingsKey = frame.unitKey
        if settingsKey and settingsKey:match("^boss%d+$") then
            settingsKey = "boss"
        end
        local settings = GetUnitSettings(settingsKey)

        -- Block nudging for anchored frames
        local isAnchored = settings and settings.anchorTo and settings.anchorTo ~= "disabled"
        if isAnchored and (settingsKey == "player" or settingsKey == "target") then
            return
        end

        if settings then
            local shift = IsShiftKeyDown()
            local step = shift and 10 or 1
            settings.offsetX = (settings.offsetX or 0) + (deltaX * step)
            settings.offsetY = (settings.offsetY or 0) + (deltaY * step)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX, settings.offsetY)

            -- Notify options panel of position change
            QUI_UF:NotifyPositionChanged(settingsKey, settings.offsetX, settings.offsetY)
        end
    end)

    return btn
end

function QUI_UF:EnableEditMode()
    if InCombatLockdown() then
        print("|cFF56D1FFQUI|r: Cannot enter Edit Mode during combat.")
        return
    end

    self.editModeActive = true

    -- Hide Blizzard's selection frames (prevents visual conflicts in Edit Mode)
    self:HideBlizzardSelectionFrames()

    -- Unregister state drivers so frames stay visible
    for unitKey, frame in pairs(self.frames) do
        UnregisterStateDriver(frame, "visibility")
    end
    
    -- Create central Save and Exit button if not exists
    if not self.exitEditModeBtn then
        local exitBtn = CreateFrame("Button", "QUI_ExitEditModeBtn", UIParent, "BackdropTemplate")
        exitBtn:SetSize(180, 40)
        exitBtn:SetPoint("TOP", UIParent, "TOP", 0, -100)
        exitBtn:SetFrameStrata("TOOLTIP")
        local exitBtnPx = QUICore:GetPixelSize(exitBtn)
        exitBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = exitBtnPx * 2,
        })
        exitBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        exitBtn:SetBackdropBorderColor(0.34, 0.82, 1, 1)  -- Blue accent

        local exitText = exitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        exitText:SetPoint("CENTER")
        exitText:SetText("SAVE AND EXIT")
        exitText:SetTextColor(0.34, 0.82, 1, 1)
        exitBtn.text = exitText

        -- Hint text below button
        local hintText = exitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hintText:SetPoint("TOP", exitBtn, "BOTTOM", 0, -5)
        hintText:SetText("Drag frames or click arrow buttons to nudge (Shift=1px)")
        hintText:SetTextColor(0.7, 0.7, 0.7, 1)
        exitBtn.hint = hintText

        exitBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 0, 1)
            self.text:SetTextColor(1, 1, 0, 1)
        end)
        exitBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.34, 0.82, 1, 1)
            self.text:SetTextColor(0.34, 0.82, 1, 1)
        end)
        exitBtn:SetScript("OnClick", function()
            if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                -- Save changes first
                if EditModeManagerFrame.SaveLayoutChanges then
                    pcall(EditModeManagerFrame.SaveLayoutChanges, EditModeManagerFrame)
                end
                -- Then exit (pcall: Blizzard's exit path can trigger secret value
                -- errors in CompactUnitFrame_UpdateInRange via party frame refresh)
                pcall(HideUIPanel, EditModeManagerFrame)
            else
                -- Fallback for /qui editmode case
                QUI_UF:DisableEditMode()
            end
        end)

        self.exitEditModeBtn = exitBtn
    end
    self.exitEditModeBtn:Show()
    
    for unitKey, frame in pairs(self.frames) do
        -- Create highlight overlay if not exists
        if not frame.editOverlay then
            local overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            overlay:SetAllPoints()
            overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
            local overlayPx = QUICore:GetPixelSize(overlay)
            overlay:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = overlayPx * 2,
            })
            overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
            overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
            
            -- Nudge buttons (arrow buttons around the frame)
            local nudgeLeft = CreateNudgeButton(overlay, "LEFT", -1, 0, unitKey)
            nudgeLeft:SetPoint("RIGHT", overlay, "LEFT", -4, 0)
            overlay.nudgeLeft = nudgeLeft

            local nudgeRight = CreateNudgeButton(overlay, "RIGHT", 1, 0, unitKey)
            nudgeRight:SetPoint("LEFT", overlay, "RIGHT", 4, 0)
            overlay.nudgeRight = nudgeRight

            local nudgeUp = CreateNudgeButton(overlay, "UP", 0, 1, unitKey)
            nudgeUp:SetPoint("BOTTOM", overlay, "TOP", 0, 4)
            overlay.nudgeUp = nudgeUp

            -- Info line above UP arrow (consolidated: name + coords)
            local infoText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoText:SetPoint("BOTTOM", nudgeUp, "TOP", 0, 2)  -- 2px above the up arrow
            infoText:SetTextColor(0.7, 0.7, 0.7, 1)  -- Subtle grey
            overlay.infoText = infoText
            overlay.unitLabel = unitKey:gsub("^%l", string.upper):gsub("(%l)(%u)", "%1 %2")

            local nudgeDown = CreateNudgeButton(overlay, "DOWN", 0, -1, unitKey)
            nudgeDown:SetPoint("TOP", overlay, "BOTTOM", 0, -4)
            overlay.nudgeDown = nudgeDown

            -- Store unitKey for selection manager
            overlay.elementKey = unitKey

            -- Hide nudge buttons initially (will show on click/selection)
            nudgeLeft:Hide()
            nudgeRight:Hide()
            nudgeUp:Hide()
            nudgeDown:Hide()
            infoText:Hide()

            -- Allow clicks to pass through overlay to frame for dragging
            overlay:EnableMouse(false)

            frame.editOverlay = overlay
        end

        -- Update info text with current position
        local settingsKey = unitKey
        if unitKey:match("^boss%d+$") then
            settingsKey = "boss"
        end
        local settings = GetUnitSettings(settingsKey)
        if settings and frame.editOverlay.infoText then
            local label = frame.editOverlay.unitLabel or unitKey
            local isAnchored = settings.anchorTo and settings.anchorTo ~= "disabled"
            if isAnchored and (settingsKey == "player" or settingsKey == "target") then
                local anchorNames = {essential = "Essential", utility = "Utility", primary = "Primary", secondary = "Secondary"}
                local anchorName = anchorNames[settings.anchorTo] or settings.anchorTo
                frame.editOverlay.infoText:SetText(label .. "  (Locked to " .. anchorName .. ")")
            else
                local x = settings.offsetX or 0
                local y = settings.offsetY or 0
                frame.editOverlay.infoText:SetText(string.format("%s  X:%d Y:%d", label, x, y))
            end
        end
        
        frame.editOverlay:Show()
        
        -- Enable dragging
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")

        -- Store unitKey on frame for click handler
        frame._editModeUnitKey = unitKey

        -- Click handler to select this element and show its arrows
        frame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and QUI_UF.editModeActive then
                local core = GetCore()
                if core and core.SelectEditModeElement then
                    core:SelectEditModeElement("unitframe", self._editModeUnitKey)
                end
            end
        end)

        frame:SetScript("OnDragStart", function(self)
            if QUI_UF.editModeActive then
                -- Block dragging for anchored frames
                local settingsKey = self.unitKey
                if self.unitKey:match("^boss%d+$") then settingsKey = "boss" end
                local settings = GetUnitSettings(settingsKey)
                local isAnchored = settings and settings.anchorTo and settings.anchorTo ~= "disabled"
                if isAnchored and (settingsKey == "player" or settingsKey == "target") then
                    return -- Locked to anchor, cannot drag
                end

                self:StartMoving()
                self._isMoving = true

                -- Update position in real-time during drag
                self:SetScript("OnUpdate", function(self)
                    if not self._isMoving then
                        self:SetScript("OnUpdate", nil)
                        return
                    end

                    -- Calculate offset from UIParent center
                    local selfX, selfY = self:GetCenter()
                    local parentX, parentY = UIParent:GetCenter()
                    if selfX and selfY and parentX and parentY then
                        local rawX, rawY = selfX - parentX, selfY - parentY
                        local offsetX = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawX) or Round(rawX)
                        local offsetY = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawY) or Round(rawY)

                        -- Update database in real-time
                        local settingsKey = self.unitKey
                        if self.unitKey:match("^boss%d+$") then
                            settingsKey = "boss"
                        end
                        local settings = GetUnitSettings(settingsKey)
                        if settings then
                            settings.offsetX = offsetX
                            settings.offsetY = offsetY

                            -- Notify options panel of position change (real-time sync)
                            QUI_UF:NotifyPositionChanged(settingsKey, offsetX, offsetY)
                        end
                    end
                end)
            end
        end)

        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self._isMoving = false
            self:SetScript("OnUpdate", nil)

            -- Final position save
            local selfX, selfY = self:GetCenter()
            local parentX, parentY = UIParent:GetCenter()
            if selfX and selfY and parentX and parentY then
                local rawX, rawY = selfX - parentX, selfY - parentY
                local offsetX = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawX) or Round(rawX)
                local offsetY = QUICore and QUICore.PixelRound and QUICore:PixelRound(rawY) or Round(rawY)

                -- Boss frames: all boss frames save to "boss" settings
                local settingsKey = self.unitKey
                if self.unitKey:match("^boss%d+$") then
                    settingsKey = "boss"
                end
                local settings = GetUnitSettings(settingsKey)
                if settings then
                    settings.offsetX = offsetX
                    settings.offsetY = offsetY

                    -- Final notification to options panel
                    QUI_UF:NotifyPositionChanged(settingsKey, offsetX, offsetY)
                end
            end
        end)

        -- Enable keyboard for arrow key nudging (skip boss frames - SecureUnitButtonTemplate rejects this call)
        local isBossFrame = frame.unit and frame.unit:match("^boss%d$")
        if not isBossFrame then
            frame:EnableKeyboard(true)
        end
        frame:SetScript("OnKeyDown", function(self, key)
            if not QUI_UF.editModeActive then return end

            local deltaX, deltaY = 0, 0
            if key == "LEFT" then deltaX = -1
            elseif key == "RIGHT" then deltaX = 1
            elseif key == "UP" then deltaY = 1
            elseif key == "DOWN" then deltaY = -1
            else return end  -- Ignore other keys

            local settingsKey = self.unitKey
            if settingsKey and settingsKey:match("^boss%d+$") then
                settingsKey = "boss"
            end
            local settings = GetUnitSettings(settingsKey)

            -- Block nudging for anchored frames
            local isAnchored = settings and settings.anchorTo and settings.anchorTo ~= "disabled"
            if isAnchored and (settingsKey == "player" or settingsKey == "target") then
                return
            end

            local shift = IsShiftKeyDown()
            local step = shift and 10 or 1

            if settings then
                settings.offsetX = (settings.offsetX or 0) + (deltaX * step)
                settings.offsetY = (settings.offsetY or 0) + (deltaY * step)
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX, settings.offsetY)

                -- Notify options panel of position change
                QUI_UF:NotifyPositionChanged(settingsKey, settings.offsetX, settings.offsetY)
            end
        end)
        
        -- Show frame even if unit doesn't exist (for positioning)
        frame:Show()
        
        -- Show preview data so frames are visible
        self:ShowPreview(unitKey)
    end
    
    print("|cFF56D1FFQUI|r: Edit Mode |cff00ff00ENABLED|r - Drag frames to reposition.")
end

function QUI_UF:DisableEditMode()
    self.editModeActive = false

    -- Clear Edit Mode selection (hides arrows on selected element)
    local core = GetCore()
    if core and core.ClearEditModeSelection then
        core:ClearEditModeSelection()
    end

    -- Hide the exit button
    if self.exitEditModeBtn then
        self.exitEditModeBtn:Hide()
    end
    
    for unitKey, frame in pairs(self.frames) do
        -- Hide overlay
        if frame.editOverlay then
            frame.editOverlay:Hide()
        end
        
        -- Disable dragging and click handlers
        frame:RegisterForDrag()
        -- Skip EnableKeyboard for boss frames (SecureUnitButtonTemplate rejects this call)
        local isBossFrame = frame.unit and frame.unit:match("^boss%d$")
        if not isBossFrame then
            frame:EnableKeyboard(false)
        end
        frame:SetScript("OnMouseDown", nil)
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        frame:SetScript("OnKeyDown", nil)
        
        -- Hide preview mode that was enabled for edit mode
        self.previewMode[unitKey] = false
        
        -- Re-register state drivers for non-player units
        if not InCombatLockdown() then
            local unit = frame.unit
            if unit == "target" then
                RegisterStateDriver(frame, "visibility", "[@target,exists] show; hide")
            elseif unit == "focus" then
                RegisterStateDriver(frame, "visibility", "[@focus,exists] show; hide")
            elseif unit == "pet" then
                RegisterStateDriver(frame, "visibility", "[@pet,exists] show; hide")
            elseif unit == "targettarget" then
                RegisterStateDriver(frame, "visibility", "[@targettarget,exists] show; hide")
            elseif unit and unit:match("^boss%d$") then
                local bossNum = unit:match("^boss(%d)$")
                if bossNum then
                    RegisterStateDriver(frame, "visibility", "[@boss" .. bossNum .. ",exists] show; hide")
                end
            end
        end
        
        -- Update frame with real data if unit exists
        if UnitExists(frame.unit) or unitKey == "player" then
            UpdateFrame(frame)
        end
    end
    
    print("|cFF56D1FFQUI|r: Edit Mode |cffff0000DISABLED|r - Positions saved.")
end

function QUI_UF:ToggleEditMode()
    if self.editModeActive then
        self:DisableEditMode()
    else
        self:EnableEditMode()
    end
end

---------------------------------------------------------------------------
-- HIDE BLIZZARD DEFAULT FRAMES
---------------------------------------------------------------------------
local function KillBlizzardFrame(frame, allowInEditMode)
    if not frame then return end
    
    -- Unregister events to stop updates
    frame:UnregisterAllEvents()
    
    -- For secure frames like PlayerFrame, we can't call Hide() directly
    -- Instead, make it invisible and non-interactive
    frame:SetAlpha(0)
    frame:EnableMouse(false)
    
    -- Move it off-screen as extra measure
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    
    -- Use RegisterStateDriver to keep it hidden (works with secure frames)
    if not InCombatLockdown() then
        RegisterStateDriver(frame, "visibility", "hide")
    end
end

local function KillBlizzardChildFrame(frame)
    if not frame then return end
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    
    -- Use pcall to safely try Hide() - some child frames may be protected
    pcall(function() frame:Hide() end)
    
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
    
    -- Set alpha to 0 as fallback
    frame:SetAlpha(0)
    
    frame:SetScript("OnShow", function(f) 
        pcall(function() f:Hide() end)
        f:SetAlpha(0)
    end)
end

local function HideBlizzardTargetVisuals()
    if not TargetFrame then return end
    
    -- Hide main art & bars but keep the frame alive for tooltips/buffs
    KillBlizzardChildFrame(TargetFrame.TargetFrameContainer)
    KillBlizzardChildFrame(TargetFrame.TargetFrameContent)
    KillBlizzardChildFrame(TargetFrame.healthbar)
    KillBlizzardChildFrame(TargetFrame.manabar)
    KillBlizzardChildFrame(TargetFrame.powerBarAlt)
    KillBlizzardChildFrame(TargetFrame.overAbsorbGlow)
    KillBlizzardChildFrame(TargetFrame.overHealAbsorbGlow)
    KillBlizzardChildFrame(TargetFrame.totalAbsorbBar)
    KillBlizzardChildFrame(TargetFrame.tempMaxHealthLossBar)
    KillBlizzardChildFrame(TargetFrame.myHealPredictionBar)
    KillBlizzardChildFrame(TargetFrame.otherHealPredictionBar)
    KillBlizzardChildFrame(TargetFrame.name)
    KillBlizzardChildFrame(TargetFrame.portrait)
    KillBlizzardChildFrame(TargetFrame.threatIndicator)
    KillBlizzardChildFrame(TargetFrame.threatNumericIndicator)
    
    -- Hide buff/debuff frames (modern WoW structure)
    KillBlizzardChildFrame(TargetFrame.BuffFrame)
    KillBlizzardChildFrame(TargetFrame.DebuffFrame)
    KillBlizzardChildFrame(TargetFrame.buffsContainer)
    KillBlizzardChildFrame(TargetFrame.debuffsContainer)
    
    -- Hide old-style aura buttons
    for i = 1, 40 do
        KillBlizzardChildFrame(_G["TargetFrameBuff"..i])
        KillBlizzardChildFrame(_G["TargetFrameDebuff"..i])
    end
    
    -- Release aura pools (Dragonflight+)
    if TargetFrame.auraPools and TargetFrame.auraPools.ReleaseAll then
        TargetFrame.auraPools:ReleaseAll()
    end
    
    -- Hide the entire TargetFrame since we have our own
    KillBlizzardFrame(TargetFrame)
end

local function HideBlizzardFocusVisuals()
    if not FocusFrame then return end
    
    KillBlizzardChildFrame(FocusFrame.TargetFrameContainer)
    KillBlizzardChildFrame(FocusFrame.TargetFrameContent)
    KillBlizzardChildFrame(FocusFrame.healthbar)
    KillBlizzardChildFrame(FocusFrame.manabar)
    KillBlizzardChildFrame(FocusFrame.powerBarAlt)
    KillBlizzardChildFrame(FocusFrame.overAbsorbGlow)
    KillBlizzardChildFrame(FocusFrame.overHealAbsorbGlow)
    KillBlizzardChildFrame(FocusFrame.totalAbsorbBar)
    KillBlizzardChildFrame(FocusFrame.tempMaxHealthLossBar)
    KillBlizzardChildFrame(FocusFrame.myHealPredictionBar)
    KillBlizzardChildFrame(FocusFrame.otherHealPredictionBar)
    KillBlizzardChildFrame(FocusFrame.name)
    KillBlizzardChildFrame(FocusFrame.portrait)
    KillBlizzardChildFrame(FocusFrame.threatIndicator)
    KillBlizzardChildFrame(FocusFrame.threatNumericIndicator)
    
    -- Hide buff/debuff frames (modern WoW structure)
    KillBlizzardChildFrame(FocusFrame.BuffFrame)
    KillBlizzardChildFrame(FocusFrame.DebuffFrame)
    KillBlizzardChildFrame(FocusFrame.buffsContainer)
    KillBlizzardChildFrame(FocusFrame.debuffsContainer)
    
    -- Hide old-style aura buttons
    for i = 1, 40 do
        KillBlizzardChildFrame(_G["FocusFrameBuff"..i])
        KillBlizzardChildFrame(_G["FocusFrameDebuff"..i])
    end
    
    -- Release aura pools
    if FocusFrame.auraPools and FocusFrame.auraPools.ReleaseAll then
        FocusFrame.auraPools:ReleaseAll()
    end
    
    -- Hide the entire FocusFrame since we have our own
    KillBlizzardFrame(FocusFrame)
end

function QUI_UF:HideBlizzardFrames()
    local db = GetDB()
    if not db or not db.enabled then return end
    
    -- Hide Player frame
    if db.player and db.player.enabled then
        KillBlizzardFrame(PlayerFrame)
    end
    
    -- Hide Blizzard Player Castbar if our QUI player castbar is enabled
    if db.player and db.player.castbar and db.player.castbar.enabled then
        if PlayerCastingBarFrame then
            PlayerCastingBarFrame:SetAlpha(0)
            PlayerCastingBarFrame:SetScale(0.0001)
            PlayerCastingBarFrame:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -10000, 10000)
            PlayerCastingBarFrame:UnregisterAllEvents()
            if PlayerCastingBarFrame.SetUnit then
                PlayerCastingBarFrame:SetUnit(nil)
            end
            -- Hook Show to prevent Blizzard from ever showing (catches talent changes, etc.)
            if not PlayerCastingBarFrame._quiShowHooked then
                PlayerCastingBarFrame._quiShowHooked = true
                hooksecurefunc(PlayerCastingBarFrame, "Show", function(self)
                    self:Hide()
                end)
            end
        end
        -- Also hide the pet castbar if it exists
        if PetCastingBarFrame then
            PetCastingBarFrame:SetAlpha(0)
            PetCastingBarFrame:SetScale(0.0001)
            PetCastingBarFrame:UnregisterAllEvents()
        end
    end
    
    -- Hide Target frame visuals (keep frame for auras/tooltips)
    if db.target and db.target.enabled then
        HideBlizzardTargetVisuals()
    end
    
    -- Hide Target of Target
    if db.targettarget and db.targettarget.enabled then
        KillBlizzardFrame(TargetFrameToT)
    end
    
    -- Hide Pet frame
    if db.pet and db.pet.enabled then
        KillBlizzardFrame(PetFrame)
    end
    
    -- Hide Focus frame visuals (always hide Blizzard focus frame when QUI unit frames are enabled)
    HideBlizzardFocusVisuals()
    
    -- Hide Boss frames (allow in Edit Mode)
    if db.boss and db.boss.enabled then
        for i = 1, 5 do
            local bf = _G["Boss" .. i .. "TargetFrame"]
            KillBlizzardFrame(bf, true)
        end

        -- Fix Edit Mode crash: BossTargetFrameContainer.GetScaledSelectionSides() crashes
        -- when GetRect() returns nil (children moved off-screen).
        -- Hook the crashing function directly to return safe fallback values.
        if BossTargetFrameContainer and not BossTargetFrameContainer._quiEditModeFixed then
            -- Hook GetScaledSelectionSides to handle nil GetRect case
            if BossTargetFrameContainer.GetScaledSelectionSides then
                local originalGetScaledSelectionSides = BossTargetFrameContainer.GetScaledSelectionSides
                BossTargetFrameContainer.GetScaledSelectionSides = function(self)
                    local left, bottom, width, height = self:GetRect()
                    if left == nil then
                        -- Return off-screen fallback sides (left, right, bottom, top)
                        return -10000, -9999, 10000, 10001
                    end
                    return originalGetScaledSelectionSides(self)
                end
            end

            -- Also try to give container valid bounds as backup
            BossTargetFrameContainer:SetSize(1, 1)
            if not BossTargetFrameContainer:GetPoint() then
                BossTargetFrameContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end

            BossTargetFrameContainer._quiEditModeFixed = true
        end
    end
end

---------------------------------------------------------------------------
-- INITIALIZE
---------------------------------------------------------------------------
function QUI_UF:Initialize()
    -- Defer initialization if in combat (protects RegisterStateDriver calls)
    if InCombatLockdown() then
        QUI_UF.pendingInitialize = true
        return
    end

    local db = GetDB()
    if not db or not db.enabled then return end

    -- Setup castbar module with helpers and references
    if QUI_Castbar then
        QUI_Castbar:SetHelpers({
            GetUnitSettings = GetUnitSettings,
            Scale = Scale,
            GetFontPath = GetFontPath,
            GetFontOutline = GetFontOutline,
            GetTexturePath = GetTexturePath,
            GetUnitClassColor = GetUnitClassColor,
            TruncateName = TruncateName,
            GetGeneralSettings = GetGeneralSettings,
            GetDB = GetDB,
        })
        QUI_Castbar:SetUnitFramesModule(self)
        QUI_Castbar.castbars = self.castbars
    end
    
    -- Hide Blizzard default frames first
    self:HideBlizzardFrames()
    
    -- Create player frame
    if db.player and db.player.enabled then
        self.frames.player = CreateUnitFrame("player", "player")
        -- Create player castbar
        if db.player.castbar and db.player.castbar.enabled then
            self.castbars.player = CreateCastbar(self.frames.player, "player", "player")
        end
        -- Setup aura tracking for player
        SetupAuraTracking(self.frames.player)
    end

    -- Create target frame
    if db.target and db.target.enabled then
        self.frames.target = CreateUnitFrame("target", "target")
        -- Create target castbar
        if db.target.castbar and db.target.castbar.enabled then
            self.castbars.target = CreateCastbar(self.frames.target, "target", "target")
        end
        -- Setup aura tracking for target (debuffs above, buffs below)
        SetupAuraTracking(self.frames.target)
    end
    
    -- Create target of target frame
    if db.targettarget and db.targettarget.enabled then
        self.frames.targettarget = CreateUnitFrame("targettarget", "targettarget")
        -- Create targettarget castbar
        if db.targettarget.castbar and db.targettarget.castbar.enabled then
            self.castbars.targettarget = CreateCastbar(self.frames.targettarget, "targettarget", "targettarget")
        end
        -- Setup aura tracking for targettarget
        SetupAuraTracking(self.frames.targettarget)
    end

    -- Create pet frame
    if db.pet and db.pet.enabled then
        self.frames.pet = CreateUnitFrame("pet", "pet")
        -- Create pet castbar (opt-in for vehicle/RP casts)
        if db.pet.castbar and db.pet.castbar.enabled then
            self.castbars.pet = CreateCastbar(self.frames.pet, "pet", "pet")
        end
        -- Setup aura tracking for pet
        SetupAuraTracking(self.frames.pet)
    end

    -- Create focus frame
    if db.focus and db.focus.enabled then
        self.frames.focus = CreateUnitFrame("focus", "focus")
        -- Create focus castbar
        if db.focus.castbar and db.focus.castbar.enabled then
            self.castbars.focus = CreateCastbar(self.frames.focus, "focus", "focus")
        end
        -- Setup aura tracking for focus (debuffs above, buffs below)
        SetupAuraTracking(self.frames.focus)
    end
    
    -- Create boss frames (boss1 through boss5)
    if db.boss and db.boss.enabled then
        local spacing = db.boss.spacing or 40
        for i = 1, 5 do
            local bossUnit = "boss" .. i
            local bossKey = "boss" .. i
            -- Pass bossKey (boss1, boss2, etc.) for unique frame names, but settings come from "boss"
            self.frames[bossKey] = CreateBossFrame(bossUnit, bossKey, i)
            
            -- Position boss frames vertically stacked
            if self.frames[bossKey] and i > 1 then
                local prevFrame = self.frames["boss" .. (i - 1)]
                if prevFrame then
                    self.frames[bossKey]:ClearAllPoints()
                    self.frames[bossKey]:SetPoint("TOP", prevFrame, "BOTTOM", 0, -spacing)
                end
            end
            
            -- Create boss castbar (uses "boss" settings but unique unit)
            if self.frames[bossKey] and db.boss.castbar and db.boss.castbar.enabled then
                self.castbars[bossKey] = CreateBossCastbar(self.frames[bossKey], bossUnit, i)
            end

            -- Setup aura tracking for boss frame
            SetupAuraTracking(self.frames[bossKey])
        end
    end

    -- Single delayed refresh to catch health values once available
    -- (Consolidated from 3 calls at 0.5s/1.0s/2.0s to reduce CPU spike on login)
    C_Timer.After(1.5, function() self:RefreshAll() end)

    -- Performance: Removed 200ms health polling ticker
    -- UNIT_HEALTH and UNIT_POWER_UPDATE events already handle updates reliably
    -- The ticker was polling ALL unit frames 5x/sec even when no health changed
end

---------------------------------------------------------------------------
-- BLIZZARD EDIT MODE INTEGRATION
---------------------------------------------------------------------------
-- Hook Blizzard's Edit Mode to trigger QUI's edit mode when user enters via Esc > Edit Mode
function QUI_UF:HookBlizzardEditMode()
    if not EditModeManagerFrame then return end
    if self._blizzEditModeHooked then return end
    self._blizzEditModeHooked = true

    -- Track if we triggered from Blizzard Edit Mode (vs /qui editmode)
    self.triggeredByBlizzEditMode = false

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if InCombatLockdown() then return end
        if self.editModeActive then return end  -- Already active via /qui editmode
        self.triggeredByBlizzEditMode = true
        self:EnableEditMode()
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if InCombatLockdown() then return end
        if not self.editModeActive then return end
        if not self.triggeredByBlizzEditMode then return end  -- Don't exit if user used /qui editmode
        self.triggeredByBlizzEditMode = false
        self:DisableEditMode()
    end)
end

-- Hide Blizzard's selection frames when QUI frames are enabled
-- Called during EnableEditMode() to prevent visual conflicts
function QUI_UF:HideBlizzardSelectionFrames()
    local function HideSelection(parent, unitKey)
        if not parent or not parent.Selection then return end

        local db = GetDB()
        if not db or not db[unitKey] or not db[unitKey].enabled then return end

        parent.Selection:Hide()

        -- Hook OnShow to persistently hide while QUI frames are enabled
        if not parent.Selection._quiHooked then
            parent.Selection._quiHooked = true
            parent.Selection:HookScript("OnShow", function(self)
                local db = GetDB()
                if db and db[unitKey] and db[unitKey].enabled then
                    self:Hide()
                end
            end)
        end
    end

    HideSelection(PlayerFrame, "player")
    HideSelection(TargetFrame, "target")
    HideSelection(FocusFrame, "focus")
    HideSelection(PetFrame, "pet")
    HideSelection(TargetFrameToT, "targettarget")
    -- Boss frames use Blizzard's boss frames which are separate
end

---------------------------------------------------------------------------
-- CLIQUE COMPATIBILITY
---------------------------------------------------------------------------
function QUI_UF:RegisterWithClique()
    -- Check if Clique is loaded
    local _, cliqueLoaded = C_AddOns.IsAddOnLoaded("Clique")
    if not cliqueLoaded then return end

    -- Ensure ClickCastFrames exists
    _G.ClickCastFrames = _G.ClickCastFrames or {}

    -- Register all unit frames with Clique
    for unitKey, frame in pairs(self.frames) do
        if frame and frame.GetName then
            _G.ClickCastFrames[frame] = true
        end
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
        -- Delay initialization to ensure DB is ready
        C_Timer.After(0.5, function()
            QUI_UF:Initialize()
            -- Hook Blizzard Edit Mode after frames are created
            QUI_UF:HookBlizzardEditMode()
            -- Register frames with Clique after creation
            C_Timer.After(0.5, function()
                QUI_UF:RegisterWithClique()
            end)
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Refresh after loading screens
        C_Timer.After(1.0, function()
            QUI_UF:RefreshAll()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Process pending initialization (from /reload during combat)
        if QUI_UF.pendingInitialize then
            QUI_UF.pendingInitialize = false
            QUI_UF:Initialize()
            QUI_UF:HookBlizzardEditMode()
            C_Timer.After(0.5, function()
                QUI_UF:RegisterWithClique()
            end)
        end
    end
end)

---------------------------------------------------------------------------
-- GLOBAL REFRESH FUNCTION (for GUI)
---------------------------------------------------------------------------
_G.QUI_RefreshUnitFrames = function()
    QUI_UF:RefreshAll()
end

-- Force immediate aura refresh for a specific unit or all units with auras
_G.QUI_RefreshAuras = function(unitKey)
    if unitKey then
        -- Boss uses "boss" as unitKey but frames are boss1-boss5
        if unitKey == "boss" then
            for i = 1, 5 do
                local bossKey = "boss" .. i
                local frame = QUI_UF.frames[bossKey]
                if frame then
                    lastAuraUpdate[bossKey] = 0
                    UpdateAuras(frame)
                end
            end
        else
            local frame = QUI_UF.frames[unitKey]
            if frame then
                lastAuraUpdate[unitKey] = 0
                UpdateAuras(frame)
            end
        end
    else
        -- Refresh all units that have aura tracking
        for _, key in ipairs({"player", "target", "focus", "pet", "targettarget"}) do
            local frame = QUI_UF.frames[key]
            if frame then
                lastAuraUpdate[key] = 0
                UpdateAuras(frame)
            end
        end
        -- Boss frames
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = QUI_UF.frames[bossKey]
            if frame then
                lastAuraUpdate[bossKey] = 0
                UpdateAuras(frame)
            end
        end
    end
end

_G.QUI_ShowUnitFramePreview = function(unitKey)
    QUI_UF:ShowPreview(unitKey)
end

_G.QUI_HideUnitFramePreview = function(unitKey)
    QUI_UF:HidePreview(unitKey)
end

_G.QUI_ShowAuraPreview = function(unitKey, auraType)
    QUI_UF:ShowAuraPreview(unitKey, auraType)
end

_G.QUI_HideAuraPreview = function(unitKey, auraType)
    QUI_UF:HideAuraPreview(unitKey, auraType)
end

_G.QUI_ToggleUnitFrameEditMode = function()
    QUI_UF:ToggleEditMode()
end

-- Register slider references for real-time sync during edit mode
_G.QUI_RegisterEditModeSliders = function(unitKey, xSlider, ySlider)
    QUI_UF:RegisterEditModeSliders(unitKey, xSlider, ySlider)
end

-- Global references for external access
_G.QUI_UnitFrames = QUI_UF.frames
_G.QUI_Castbars = QUI_UF.castbars

-- Castbar functions are now in qui_castbar.lua module

-- Helper: Get anchor frame by type
local function GetAnchorFrame(anchorType)
    if anchorType == "essential" then
        return _G["EssentialCooldownViewer"]
    elseif anchorType == "utility" then
        return _G["UtilityCooldownViewer"]
    elseif anchorType == "primary" then
        local core = GetCore()
        return core and core.powerBar
    elseif anchorType == "secondary" then
        local core = GetCore()
        return core and core.secondaryPowerBar
    end
    return nil
end

-- Helper: Get anchor frame dimensions
local function GetAnchorDimensions(anchorFrame, anchorType)
    if not anchorFrame then return nil end

    local width, height
    if anchorType == "essential" or anchorType == "utility" then
        -- CDM viewers store width in custom property
        width = anchorFrame.__cdmRow1Width or anchorFrame:GetWidth()
        height = anchorFrame.__cdmTotalHeight or anchorFrame:GetHeight()
    else
        -- Power bars use standard methods
        width = anchorFrame:GetWidth()
        height = anchorFrame:GetHeight()
    end

    local centerX, centerY = anchorFrame:GetCenter()
    if not centerX or not centerY then return nil end

    return {
        width = width,
        height = height,
        centerX = centerX,
        centerY = centerY,
        top = centerY + (height / 2),
        left = centerX - (width / 2),
        right = centerX + (width / 2),
    }
end

-- Update unit frames that are anchored to another frame
-- Called when anchor frames (CDM, Power Bars) reposition
_G.QUI_UpdateAnchoredUnitFrames = function()
    if InCombatLockdown() then return end  -- Skip during combat to avoid protected function errors
    local db = GetDB()
    if not db then return end

    local screenCenterX, screenCenterY = UIParent:GetCenter()
    if not screenCenterX or not screenCenterY then return end

    -- Update Player (anchors to LEFT edge of anchor frame)
    local playerSettings = db.player
    local playerAnchorType = playerSettings and playerSettings.anchorTo
    if playerAnchorType and playerAnchorType ~= "disabled" and QUI_UF.frames.player then
        local anchorFrame = GetAnchorFrame(playerAnchorType)
        if anchorFrame and anchorFrame:IsShown() then
            local anchor = GetAnchorDimensions(anchorFrame, playerAnchorType)
            if anchor then
                local frame = QUI_UF.frames.player
                local frameWidth = frame:GetWidth()
                local frameHeight = frame:GetHeight()
                local gap = QUICore:PixelRound(playerSettings.anchorGap or 10, frame)
                local yOffset = QUICore:PixelRound(playerSettings.anchorYOffset or 0, frame)

                -- X: Anchor left edge - gap - half frame width
                local frameX = anchor.left - gap - (frameWidth / 2) - screenCenterX
                -- Y: Align unit frame TOP with anchor TOP, then apply offset
                local frameY = (anchor.top - (frameHeight / 2) - screenCenterY) + yOffset

                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", frameX, frameY)
            end
        else
            -- Fallback: anchor target doesn't exist, use standard offset positioning
            local frame = QUI_UF.frames.player
            frame:ClearAllPoints()
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER",
                playerSettings.offsetX or 0,
                playerSettings.offsetY or 0)
        end
    end

    -- Update Target (anchors to RIGHT edge of anchor frame)
    local targetSettings = db.target
    local targetAnchorType = targetSettings and targetSettings.anchorTo
    if targetAnchorType and targetAnchorType ~= "disabled" and QUI_UF.frames.target then
        local anchorFrame = GetAnchorFrame(targetAnchorType)
        if anchorFrame and anchorFrame:IsShown() then
            local anchor = GetAnchorDimensions(anchorFrame, targetAnchorType)
            if anchor then
                local frame = QUI_UF.frames.target
                local frameWidth = frame:GetWidth()
                local frameHeight = frame:GetHeight()
                local gap = QUICore:PixelRound(targetSettings.anchorGap or 10, frame)
                local yOffset = QUICore:PixelRound(targetSettings.anchorYOffset or 0, frame)

                -- X: Anchor right edge + gap + half frame width
                local frameX = anchor.right + gap + (frameWidth / 2) - screenCenterX
                -- Y: Align unit frame TOP with anchor TOP, then apply offset
                local frameY = (anchor.top - (frameHeight / 2) - screenCenterY) + yOffset

                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", frameX, frameY)
            end
        else
            -- Fallback: anchor target doesn't exist, use standard offset positioning
            local frame = QUI_UF.frames.target
            frame:ClearAllPoints()
            QUICore:SetSnappedPoint(frame, "CENTER", UIParent, "CENTER",
                targetSettings.offsetX or 0,
                targetSettings.offsetY or 0)
        end
    end
end

-- Backwards compatibility alias
_G.QUI_UpdateCDMAnchoredUnitFrames = _G.QUI_UpdateAnchoredUnitFrames

-- Global callback for NCDM to update castbar anchored to Essential
-- Width is now controlled by dual anchors, so just refresh the castbar
_G.QUI_UpdateLockedCastbarToEssential = function(forceUpdate)
    local db = GetDB()
    if not db or not db.player then return end

    local castDB = db.player.castbar
    if not castDB or castDB.anchor ~= "essential" then return end

    -- Just refresh the castbar - dual anchors will handle sizing
    if _G.QUI_RefreshCastbar then
        _G.QUI_RefreshCastbar("player")
    end
end

-- Global callback for NCDM to update castbar anchored to Utility
-- Width is now controlled by dual anchors, so just refresh the castbar
_G.QUI_UpdateLockedCastbarToUtility = function(forceUpdate)
    local db = GetDB()
    if not db or not db.player then return end

    local castDB = db.player.castbar
    if not castDB or castDB.anchor ~= "utility" then return end

    -- Just refresh the castbar - dual anchors will handle sizing
    if _G.QUI_RefreshCastbar then
        _G.QUI_RefreshCastbar("player")
    end
end

-- Global callback for unit frame width changes to update anchored castbar
_G.QUI_UpdateLockedCastbarToFrame = function()
    local db = GetDB()
    if not db or not db.player then return end

    local castDB = db.player.castbar
    if not castDB or castDB.anchor ~= "unitframe" then return end

    -- Just refresh the castbar - dual anchors will handle sizing
    if _G.QUI_RefreshCastbar then
        _G.QUI_RefreshCastbar("player")
    end
end

