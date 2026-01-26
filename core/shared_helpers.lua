---------------------------------------------------------------------------
-- QUI Shared Helpers
-- Common utility functions used across multiple modules
-- This file should be loaded early (before other utils) via utils.xml
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

-- Ensure namespace tables exist
ns.Helpers = ns.Helpers or {}
local Helpers = ns.Helpers

-- Cache LibSharedMedia reference
local LSM = LibStub("LibSharedMedia-3.0", true)

---------------------------------------------------------------------------
-- SECRET VALUE UTILITIES (Patch 12.0+)
-- Combat-related APIs can return "secret values" in restricted contexts.
-- These helpers provide safe operations that won't error on secrets.
---------------------------------------------------------------------------

--- Check if a value is a secret value (12.x combat restriction)
--- @param value any The value to check
--- @return boolean True if value is a secret value
function Helpers.IsSecretValue(value)
    if type(issecretvalue) == "function" then
        return issecretvalue(value)
    end
    return false
end

--- Check if a table can be accessed (not tainted/restricted)
--- @param tbl table The table to check
--- @return boolean True if table can be accessed safely
function Helpers.CanAccessTable(tbl)
    if type(canaccesstable) == "function" then
        return canaccesstable(tbl)
    end
    return true  -- Pre-12.0 always accessible
end

--- Safely get a value, returning fallback if it's a secret
--- @param value any The potentially secret value
--- @param fallback any Value to return if secret (default: nil)
--- @return any The value or fallback
function Helpers.SafeValue(value, fallback)
    if Helpers.IsSecretValue(value) then
        return fallback
    end
    return value
end

--- Safely compare two values (returns false if either is secret)
--- @param a any First value
--- @param b any Second value
--- @return boolean|nil Result of comparison, or nil if can't compare
function Helpers.SafeCompare(a, b)
    if Helpers.IsSecretValue(a) or Helpers.IsSecretValue(b) then
        return nil
    end
    return a == b
end

--- Safely perform arithmetic on a value
--- @param value any The potentially secret value
--- @param operation function The arithmetic operation (receives value, returns result)
--- @param fallback any Value to return if secret or error
--- @return any Result of operation or fallback
function Helpers.SafeArithmetic(value, operation, fallback)
    if Helpers.IsSecretValue(value) then
        return fallback
    end
    local ok, result = pcall(operation, value)
    if ok then
        return result
    end
    return fallback
end

--- Safely convert to number
--- @param value any The potentially secret value
--- @param fallback number Value to return if secret or not a number
--- @return number The number or fallback
function Helpers.SafeToNumber(value, fallback)
    if Helpers.IsSecretValue(value) then
        return fallback or 0
    end
    local ok, num = pcall(tonumber, value)
    if ok and num then
        return num
    end
    return fallback or 0
end

--- Safely convert to string
--- @param value any The potentially secret value
--- @param fallback string Value to return if secret or conversion fails (default: "")
--- @return string The string or fallback
function Helpers.SafeToString(value, fallback)
    fallback = fallback or ""
    if Helpers.IsSecretValue(value) then
        return fallback
    end
    local ok, str = pcall(tostring, value)
    if ok and str then
        return str
    end
    return fallback
end

---------------------------------------------------------------------------
-- DATABASE ACCESS HELPERS
-- Standardized pattern for accessing QUICore database profiles
---------------------------------------------------------------------------

-- Cache reference to QUICore (set after ADDON_LOADED)
local QUICore = nil

--- Initialize QUICore reference (call after ADDON_LOADED)
function Helpers.InitQUICore()
    QUICore = ns.Addon
end

--- Get QUICore reference
--- @return table|nil QUICore addon object
function Helpers.GetQUICore()
    if not QUICore then
        QUICore = ns.Addon
    end
    return QUICore
end

--- Get the full profile database
--- @return table|nil The profile table or nil
function Helpers.GetProfile()
    local core = Helpers.GetQUICore()
    if core and core.db and core.db.profile then
        return core.db.profile
    end
    return nil
end

--- Create a DB getter function for a specific module
--- @param moduleName string The module key in the profile (e.g., "ncdm", "castbar")
--- @return function A function that returns the module's DB table or nil
function Helpers.CreateDBGetter(moduleName)
    return function()
        local profile = Helpers.GetProfile()
        if profile and profile[moduleName] then
            return profile[moduleName]
        end
        return nil
    end
end

--- Get a specific module's database directly
--- @param moduleName string The module key in the profile
--- @return table|nil The module's DB table or nil
function Helpers.GetModuleDB(moduleName)
    local profile = Helpers.GetProfile()
    if profile and profile[moduleName] then
        return profile[moduleName]
    end
    return nil
end

--- Get module settings with defaults fallback
--- This is the standard pattern for modules to access their settings.
--- Creates the profile entry if it doesn't exist.
--- @param moduleName string The module key in the profile (e.g., "cooldownEffects", "castbar")
--- @param defaults table Default values to return/initialize if settings don't exist
--- @return table The module's settings table (never nil)
function Helpers.GetModuleSettings(moduleName, defaults)
    defaults = defaults or {}
    -- Try namespace first (preferred)
    local core = Helpers.GetQUICore()
    if core and core.db and core.db.profile then
        if not core.db.profile[moduleName] then
            core.db.profile[moduleName] = defaults
        end
        return core.db.profile[moduleName]
    end
    -- Fallback to global QUI.QUICore
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile then
        if not QUICore.db.profile[moduleName] then
            QUICore.db.profile[moduleName] = defaults
        end
        return QUICore.db.profile[moduleName]
    end
    return defaults
end

---------------------------------------------------------------------------
-- FONT HELPERS
-- Centralized font fetching from general settings
---------------------------------------------------------------------------

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local DEFAULT_FONT_NAME = "Friz Quadrata TT"
local DEFAULT_OUTLINE = "OUTLINE"

--- Get the user's configured general font path
--- @return string Font file path
function Helpers.GetGeneralFont()
    local profile = Helpers.GetProfile()
    if profile and profile.general then
        local fontName = profile.general.font or DEFAULT_FONT_NAME
        if LSM then
            return LSM:Fetch("font", fontName) or DEFAULT_FONT
        end
    end
    return DEFAULT_FONT
end

--- Get the user's configured font outline style
--- @return string Font outline flag (e.g., "OUTLINE", "THICKOUTLINE", "")
function Helpers.GetGeneralFontOutline()
    local profile = Helpers.GetProfile()
    if profile and profile.general then
        return profile.general.fontOutline or DEFAULT_OUTLINE
    end
    return DEFAULT_OUTLINE
end

--- Get both font path and outline in one call
--- @return string, string Font path and outline flag
function Helpers.GetGeneralFontSettings()
    return Helpers.GetGeneralFont(), Helpers.GetGeneralFontOutline()
end

---------------------------------------------------------------------------
-- TEXTURE HELPERS
-- Centralized texture fetching from general settings
---------------------------------------------------------------------------

local DEFAULT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_TEXTURE_NAME = "Blizzard"

--- Get the user's configured general texture path
--- @return string Texture file path
function Helpers.GetGeneralTexture()
    local profile = Helpers.GetProfile()
    if profile and profile.general then
        local textureName = profile.general.texture or DEFAULT_TEXTURE_NAME
        if LSM then
            return LSM:Fetch("statusbar", textureName) or DEFAULT_TEXTURE
        end
    end
    return DEFAULT_TEXTURE
end

---------------------------------------------------------------------------
-- COLOR/THEME HELPERS
-- Centralized color utilities for skin system and class colors
---------------------------------------------------------------------------

--- Get skin colors from the QUI theme system
--- Returns both accent color and background color with fallbacks
--- @return number, number, number, number, number, number, number, number sr, sg, sb, sa, bgr, bgg, bgb, bga
function Helpers.GetSkinColors()
    local QUI = _G.QUI
    -- Fallback mint accent (#34D399)
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    -- Fallback dark background
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

--- Get just the skin accent color
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinAccentColor()
    local sr, sg, sb, sa = Helpers.GetSkinColors()
    return sr, sg, sb, sa
end

--- Get just the skin background color
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBgColor()
    local _, _, _, _, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    return bgr, bgg, bgb, bga
end

--- Get class color for a class token (e.g., "WARRIOR", "MAGE")
--- @param classToken string The uppercase class token from UnitClass
--- @return number, number, number r, g, b values (0-1)
function Helpers.GetClassColor(classToken)
    if not classToken then return 1, 1, 1 end
    local classColor = RAID_CLASS_COLORS[classToken]
    if classColor then
        return classColor.r, classColor.g, classColor.b
    end
    return 1, 1, 1  -- White fallback
end

--- Get class color for the player
--- @return number, number, number r, g, b values (0-1)
function Helpers.GetPlayerClassColor()
    local _, classToken = UnitClass("player")
    return Helpers.GetClassColor(classToken)
end

--- Get item quality color
--- @param quality number Item quality (0-8)
--- @return number, number, number r, g, b values (0-1)
function Helpers.GetItemQualityColor(quality)
    if not quality or quality < 0 then return 1, 1, 1 end
    local r, g, b = C_Item.GetItemQualityColor(quality)
    if r then
        return r, g, b
    end
    return 1, 1, 1  -- White fallback
end

---------------------------------------------------------------------------
-- UTILITY HELPERS
-- Common utility functions for frame creation and event handling
---------------------------------------------------------------------------

--- Create an event frame with registered events and callback
--- @param events table Array of event names to register
--- @param onEventCallback function Callback function(self, event, ...)
--- @param name string|nil Optional frame name
--- @return Frame The created event frame
function Helpers.CreateEventFrame(events, onEventCallback, name)
    local frame = CreateFrame("Frame", name)
    if events then
        for _, event in ipairs(events) do
            frame:RegisterEvent(event)
        end
    end
    if onEventCallback then
        frame:SetScript("OnEvent", onEventCallback)
    end
    return frame
end

--- Check if currently in combat lockdown (wrapper for future extensibility)
--- @return boolean True if in combat lockdown
function Helpers.InCombat()
    return InCombatLockdown()
end

---------------------------------------------------------------------------
-- EXPOSE TO NAMESPACE
-- Also maintain backward compatibility with ns.Utils.IsSecretValue
---------------------------------------------------------------------------

-- Ensure ns.Utils exists and add our helpers there too for compatibility
ns.Utils = ns.Utils or {}
ns.Utils.IsSecretValue = Helpers.IsSecretValue
ns.Utils.SafeValue = Helpers.SafeValue
ns.Utils.SafeCompare = Helpers.SafeCompare
ns.Utils.SafeArithmetic = Helpers.SafeArithmetic
ns.Utils.SafeToNumber = Helpers.SafeToNumber
ns.Utils.SafeToString = Helpers.SafeToString

-- Shorthand aliases on namespace for convenience
ns.GetGeneralFont = Helpers.GetGeneralFont
ns.GetGeneralFontOutline = Helpers.GetGeneralFontOutline
ns.GetGeneralTexture = Helpers.GetGeneralTexture
ns.GetModuleDB = Helpers.GetModuleDB
ns.GetModuleSettings = Helpers.GetModuleSettings
ns.CreateDBGetter = Helpers.CreateDBGetter
ns.GetSkinColors = Helpers.GetSkinColors
ns.GetClassColor = Helpers.GetClassColor
ns.GetPlayerClassColor = Helpers.GetPlayerClassColor
ns.GetItemQualityColor = Helpers.GetItemQualityColor
ns.CreateEventFrame = Helpers.CreateEventFrame
ns.InCombat = Helpers.InCombat
