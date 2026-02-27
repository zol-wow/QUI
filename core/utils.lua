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

-- Cache global secret-value API functions at file scope (avoids repeated _G lookups)
local issecretvalue = _G.issecretvalue
local canaccesstable = _G.canaccesstable

local function GetCore()
    return (_G.QUI and _G.QUI.QUICore) or ns.Addon
end

---------------------------------------------------------------------------
-- SECRET VALUE UTILITIES (Patch 12.0+)
-- Combat-related APIs can return "secret values" in restricted contexts.
-- These helpers provide safe operations that won't error on secrets.
---------------------------------------------------------------------------

--- Check if a value is a secret value (12.x combat restriction)
--- @param value any The value to check
--- @return boolean True if value is a secret value
function Helpers.IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

--- Check if a table can be accessed (not tainted/restricted)
--- @param tbl table The table to check
--- @return boolean True if table can be accessed safely
function Helpers.CanAccessTable(tbl)
    return not canaccesstable or canaccesstable(tbl)
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

-- Reference to QUICore (set after ADDON_LOADED)
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

--- Get QUICore reference (with _G.QUI fallback)
--- Drop-in replacement for the local GetCore() pattern used across 30+ files.
--- @return table|nil QUICore addon object
function Helpers.GetCore()
    return (_G.QUI and _G.QUI.QUICore) or ns.Addon
end

--- No-op kept for backward compatibility with callers.
function Helpers.InvalidateProfileCache()
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
        if profile then
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
    if profile then
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
    local profile = Helpers.GetProfile()
    if profile then
        if not profile[moduleName] then
            profile[moduleName] = defaults
        end
        return profile[moduleName]
    end
    return defaults
end

---------------------------------------------------------------------------
-- CDM HUD MIN-WIDTH HELPERS
-- Shared constants/parsing/migration for frameAnchoring.hudMinWidth
---------------------------------------------------------------------------

Helpers.HUD_MIN_WIDTH_DEFAULT = 200
Helpers.HUD_MIN_WIDTH_MIN = 100
Helpers.HUD_MIN_WIDTH_MAX = 500

--- Clamp and round HUD min width into allowed bounds.
--- @param width any
--- @return number
function Helpers.ClampHUDMinWidth(width)
    local rounded = math.floor(Helpers.SafeToNumber(width, Helpers.HUD_MIN_WIDTH_DEFAULT) + 0.5)
    if rounded < Helpers.HUD_MIN_WIDTH_MIN then
        return Helpers.HUD_MIN_WIDTH_MIN
    end
    if rounded > Helpers.HUD_MIN_WIDTH_MAX then
        return Helpers.HUD_MIN_WIDTH_MAX
    end
    return rounded
end

--- Parse HUD min-width settings from a frameAnchoring table.
--- Supports both current object format and legacy scalar format.
--- @param frameAnchoring table|nil
--- @return boolean, number enabled, width
function Helpers.ParseHUDMinWidth(frameAnchoring)
    if type(frameAnchoring) ~= "table" then
        return false, Helpers.HUD_MIN_WIDTH_DEFAULT
    end

    local cfg = frameAnchoring.hudMinWidth
    local enabled, width

    if type(cfg) == "table" then
        enabled = cfg.enabled == true
        width = cfg.width
    else
        local legacyEnabled = frameAnchoring.hudMinWidthEnabled
        if legacyEnabled == nil then
            enabled = tonumber(cfg) ~= nil
        else
            enabled = legacyEnabled == true
        end
        width = cfg
    end

    return enabled == true, Helpers.ClampHUDMinWidth(width)
end

--- Parse HUD min-width settings from a profile table.
--- @param profile table|nil
--- @return boolean, number enabled, width
function Helpers.GetHUDMinWidthSettingsFromProfile(profile)
    local frameAnchoring = profile and profile.frameAnchoring
    return Helpers.ParseHUDMinWidth(frameAnchoring)
end

--- Normalize/migrate HUD min-width settings to object format in-place.
--- @param frameAnchoring table|nil
--- @return table|nil hudMinWidth object ({ enabled, width })
function Helpers.MigrateHUDMinWidthSettings(frameAnchoring)
    if type(frameAnchoring) ~= "table" then
        return nil
    end

    local cfg = frameAnchoring.hudMinWidth
    if type(cfg) == "table" then
        -- Normalize in place so existing widget/db references stay valid.
        cfg.enabled = (cfg.enabled == true)
        cfg.width = Helpers.ClampHUDMinWidth(cfg.width)
        frameAnchoring.hudMinWidthEnabled = nil
        return cfg
    end

    local enabled, width = Helpers.ParseHUDMinWidth(frameAnchoring)
    frameAnchoring.hudMinWidth = { enabled = enabled, width = width }
    frameAnchoring.hudMinWidthEnabled = nil
    return frameAnchoring.hudMinWidth
end

--- Check whether player/target HUD frames are anchored to CDM.
--- Covers both legacy unitframes anchor settings and frameAnchoring overrides.
--- @param profile table|nil
--- @return boolean
function Helpers.IsHUDAnchoredToCDM(profile)
    if type(profile) ~= "table" then
        return false
    end

    local unitframes = profile.unitframes
    if unitframes then
        local playerAnchor = unitframes.player and unitframes.player.anchorTo
        local targetAnchor = unitframes.target and unitframes.target.anchorTo
        if playerAnchor == "essential" or playerAnchor == "utility" then
            return true
        end
        if targetAnchor == "essential" or targetAnchor == "utility" then
            return true
        end
    end

    local frameAnchoring = profile.frameAnchoring
    if frameAnchoring then
        local playerFrame = frameAnchoring.playerFrame
        local targetFrame = frameAnchoring.targetFrame
        if playerFrame and playerFrame.enabled and (playerFrame.parent == "cdmEssential" or playerFrame.parent == "cdmUtility") then
            return true
        end
        if targetFrame and targetFrame.enabled and (targetFrame.parent == "cdmEssential" or targetFrame.parent == "cdmUtility") then
            return true
        end
    end

    return false
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

local function GetBorderKeys(prefix)
    if not prefix or prefix == "" then
        return {
            override  = "borderOverride",
            hide      = "hideBorder",
            useClass  = "borderUseClassColor",
            color     = "borderColor",
        }
    end
    return {
        override  = prefix .. "BorderOverride",
        hide      = prefix .. "HideBorder",
        useClass  = prefix .. "BorderUseClassColor",
        color     = prefix .. "BorderColor",
    }
end

--- Get skin border color from dedicated border settings.
--- Falls back to skin accent color so existing profiles keep current visuals.
--- Supports optional per-module override settings tables.
--- @param moduleSettings table|nil Optional module settings table
--- @param prefix string|nil Optional key prefix for module settings in camelCase
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local profile = Helpers.GetProfile()
    local general = profile and profile.general

    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinAccentColor()
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if general then
        if general.skinBorderUseClassColor then
            r, g, b = Helpers.GetPlayerClassColor()
            a = 1
        elseif type(general.skinBorderColor) == "table" then
            r = general.skinBorderColor[1] or r
            g = general.skinBorderColor[2] or g
            b = general.skinBorderColor[3] or b
            a = general.skinBorderColor[4] or a
        end

        if general.hideSkinBorders then
            a = 0
        end
    end

    if type(moduleSettings) == "table" then
        local keys = GetBorderKeys(type(prefix) == "string" and prefix or "")

        if moduleSettings[keys.override] then
            if moduleSettings[keys.useClass] then
                r, g, b = Helpers.GetPlayerClassColor()
                a = 1
            elseif type(moduleSettings[keys.color]) == "table" then
                local moduleColor = moduleSettings[keys.color]
                r = moduleColor[1] or r
                g = moduleColor[2] or g
                b = moduleColor[3] or b
                a = moduleColor[4] or a
            end

            if moduleSettings[keys.hide] then
                a = 0
            end
        end
    end

    return r, g, b, a
end

--- Get skin bar color from dedicated bar settings.
--- Falls back to border color so existing profiles keep current visuals.
--- Supports optional per-module override settings tables.
--- @param moduleSettings table|nil Optional module settings table
--- @param prefix string|nil Optional key prefix for module settings in camelCase
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBarColor(moduleSettings, prefix)
    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if type(moduleSettings) == "table" then
        local keyPrefix = type(prefix) == "string" and prefix or ""
        local useClassKey = keyPrefix ~= "" and (keyPrefix .. "BarUseClassColor") or "barUseClassColor"
        local colorKey = keyPrefix ~= "" and (keyPrefix .. "BarColor") or "barColor"

        if moduleSettings[useClassKey] then
            r, g, b = Helpers.GetPlayerClassColor()
            a = 1
        elseif type(moduleSettings[colorKey]) == "table" then
            local moduleColor = moduleSettings[colorKey]
            r = moduleColor[1] or r
            g = moduleColor[2] or g
            b = moduleColor[3] or b
            a = moduleColor[4] or a
        end
    end

    return r, g, b, a
end

--- Get the addon-wide accent color (from options panel color picker)
--- @return number, number, number, number r, g, b, a
function Helpers.GetAddonAccentColor()
    local QUI = _G.QUI
    if QUI and QUI.GetAddonAccentColor then
        return QUI:GetAddonAccentColor()
    end
    return 0.204, 0.827, 0.6, 1  -- Fallback to mint
end

--- Get just the skin background color
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBgColor()
    local _, _, _, _, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    return bgr, bgg, bgb, bga
end

--- Get skin background color with optional module-level override
--- Supports optional per-module override settings tables for background color
--- @param moduleSettings table|nil Optional module settings table
--- @param prefix string|nil Optional key prefix for module settings in camelCase
--- @return number, number, number, number r, g, b, a
function Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    local profile = Helpers.GetProfile()
    local general = profile and profile.general

    local fallbackR, fallbackG, fallbackB, fallbackA = Helpers.GetSkinBgColor()
    local r, g, b, a = fallbackR, fallbackG, fallbackB, fallbackA

    if type(moduleSettings) == "table" then
        local keyPrefix = type(prefix) == "string" and prefix or ""
        local overrideKey = keyPrefix ~= "" and (keyPrefix .. "BgOverride") or "bgOverride"
        local hideKey = keyPrefix ~= "" and (keyPrefix .. "HideBackground") or "hideBackground"
        local colorKey = keyPrefix ~= "" and (keyPrefix .. "BackgroundColor") or "backgroundColor"

        if moduleSettings[overrideKey] then
            if type(moduleSettings[colorKey]) == "table" then
                local moduleColor = moduleSettings[colorKey]
                r = moduleColor[1] or r
                g = moduleColor[2] or g
                b = moduleColor[3] or b
                a = moduleColor[4] or a
            end

            if moduleSettings[hideKey] then
                a = 0
            end
        end
    end

    return r, g, b, a
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

--- Create an OnUpdate callback throttler.
--- Returns a function(self, elapsed, ...) that only calls callback at the
--- requested interval and passes the accumulated elapsed as second argument.
--- @param interval number Seconds between callback executions
--- @param callback function Callback(self, accumulatedElapsed, ...)
--- @return function Throttled OnUpdate handler
function Helpers.CreateOnUpdateThrottle(interval, callback)
    interval = tonumber(interval) or 0
    local elapsedSinceLast = 0
    return function(self, elapsed, ...)
        elapsedSinceLast = elapsedSinceLast + (elapsed or 0)
        if elapsedSinceLast < interval then
            return
        end
        local accumulated = elapsedSinceLast
        elapsedSinceLast = 0
        callback(self, accumulated, ...)
    end
end

--- Create a time-based throttle wrapper for event-heavy callbacks.
--- @param interval number Seconds between callback executions
--- @param callback function Callback(...)
--- @return function Throttled function
function Helpers.CreateTimeThrottle(interval, callback)
    interval = tonumber(interval) or 0
    local lastRun = 0
    return function(...)
        local now = GetTime()
        if (now - lastRun) < interval then
            return
        end
        lastRun = now
        return callback(...)
    end
end

-- if QUI Player or Target Frames don't exist, find a 3rd party UF
-- eg Elv, Unhalted, or Blizzard UF for anchoring purposes
-- @param type string eg player or target
-- @return frame
function Helpers.FindAnchorFrame(type)
    local frameHighestWidth, highestWidth = nil, 0
    local f = EnumerateFrames()
    while f do
        -- Fast field access first; only fall back to GetAttribute if nil
        local unit = f.unit
        if unit == nil and f.GetAttribute then
            unit = f:GetAttribute("unit")
        end
        -- Cheapest checks first: unit match > IsVisible > IsObjectType > GetName
        if unit == type and f:IsVisible() and f:IsObjectType("Button") and f:GetName() then
            local w = f:GetWidth()
            if w > 20 and w > highestWidth then
                frameHighestWidth, highestWidth = f, w
            end
        end
        f = EnumerateFrames(f)
    end
    return frameHighestWidth
end

---------------------------------------------------------------------------
-- HUD VISIBILITY HELPERS
-- Shared checks for CDM, Unitframes, and Custom Trackers visibility
---------------------------------------------------------------------------

--- Spell ID for Dracthyr Evoker Soar (racial flight form)
local SOAR_SPELL_ID = 381322

--- Check if player is mounted (includes Druid flight form, Dracthyr Soar)
--- Druid: GetShapeshiftFormID() == 27 (Swift Flight Form)
--- Evoker: Soar buff (369536) when using racial flight form
--- @return boolean True if mounted or in Druid/Evoker flight form
function Helpers.IsPlayerMounted()
    if IsMounted and IsMounted() then return true end
    if GetShapeshiftFormID and GetShapeshiftFormID() == 27 then return true end
    -- Dracthyr Evoker Soar (racial flight form; not detected by IsMounted)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SOAR_SPELL_ID)
        if ok and aura then return true end
    end
    return false
end

--- Check if player is flying (airborne)
--- @return boolean True if flying
function Helpers.IsPlayerFlying()
    if IsFlying then return IsFlying() end
    return false
end

--- Check if player is skyriding
--- Uses C_PlayerInfo.GetGlidingInfo() for accurate
--- grounded detection (PLAYER_IS_GLIDING_CHANGED fires on takeoff/landing).
--- @return boolean True if flying in a dynamic flight zone
function Helpers.IsPlayerSkyriding()
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return false end
    local ok, gliding = pcall(C_PlayerInfo.GetGlidingInfo)
    return ok and gliding
end

--- Check if player is inside a dungeon or raid instance.
--- Used by HUD visibility hide-rule overrides.
--- @return boolean True when instance type is party or raid
function Helpers.IsPlayerInDungeonOrRaid()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party" or instanceType == "raid"
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
ns.GetSkinBorderColor = Helpers.GetSkinBorderColor
ns.GetSkinBarColor = Helpers.GetSkinBarColor
ns.GetClassColor = Helpers.GetClassColor
ns.GetPlayerClassColor = Helpers.GetPlayerClassColor
ns.GetItemQualityColor = Helpers.GetItemQualityColor
ns.CreateEventFrame = Helpers.CreateEventFrame
ns.InCombat = Helpers.InCombat
ns.GetCore = Helpers.GetCore
ns.IsPlayerMounted = Helpers.IsPlayerMounted
ns.IsPlayerFlying = Helpers.IsPlayerFlying
ns.IsPlayerSkyriding = Helpers.IsPlayerSkyriding
ns.IsPlayerInDungeonOrRaid = Helpers.IsPlayerInDungeonOrRaid
ns.CreateOnUpdateThrottle = Helpers.CreateOnUpdateThrottle
ns.CreateTimeThrottle = Helpers.CreateTimeThrottle

 ---------------------------------------------------------------------------
-- TEXT TRUNCATION HELPERS
-- UTF-8 safe text truncation for names and labels
 ---------------------------------------------------------------------------

 --- Truncate text to max character length (UTF-8 safe)
 --- Handles secret values from combat-restricted APIs in Patch 12.0+
 --- @param text string|any The text to truncate
 --- @param maxLength number Maximum character count (0 or nil = no limit)
 --- @return string The truncated text, or original if no truncation needed
 function Helpers.TruncateUTF8(text, maxLength)
     if text == nil then return "" end
     if type(text) ~= "string" then
         return Helpers.SafeToString(text, "")
     end
     if not maxLength or maxLength <= 0 then return text end

     if Helpers.IsSecretValue(text) then
         return string.format("%." .. maxLength .. "s", text)
     end

     local lenOk, textLen = pcall(function() return #text end)
     if not lenOk then
         return string.format("%." .. maxLength .. "s", text)
     end

     if textLen <= maxLength then
         return text
     end

     local byte = string.byte
     local i = 1
     local c = 0
     while i <= textLen and c < maxLength do
         c = c + 1
         local b = byte(text, i)
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

     local subOk, truncated = pcall(string.sub, text, 1, i - 1)
     if subOk and truncated then
         return truncated
     end

     return string.format("%." .. maxLength .. "s", text)
 end

 ns.TruncateUTF8 = Helpers.TruncateUTF8

---------------------------------------------------------------------------
-- TAINT-SAFETY UTILITIES
-- Shared patterns for WoW 12.0 taint-safe frame property management.
---------------------------------------------------------------------------

--- Create a weak-keyed state table (and optional lazy-init getter).
-- @return table  The weak-keyed table.
-- @return function  getter(key) — returns tbl[key], auto-creating {} if missing.
function Helpers.CreateStateTable()
    local tbl = setmetatable({}, { __mode = "k" })
    local function get(key)
        local s = tbl[key]
        if not s then s = {}; tbl[key] = s end
        return s
    end
    return tbl, get
end

--- Check whether Blizzard Edit Mode is currently active.
-- Nil-safe for EditModeManagerFrame; uses IsEditModeActive() (not IsShown()).
-- @return boolean
function Helpers.IsEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive
       and EditModeManagerFrame:IsEditModeActive() or false
end

--- Hook a frame's Show method to defer-hide it on the next frame.
-- @param frame  The frame to hook.
-- @param opts   Optional table: { clearAlpha = bool, combatCheck = bool }
--               clearAlpha (default false): also call SetAlpha(0) after Hide.
--               combatCheck (default true): skip hide if InCombatLockdown().
local _deferredHideHooked = setmetatable({}, { __mode = "k" })

-- Queue for frames that need Hide() deferred until combat ends.
-- When combatCheck=false and we're in combat, we alpha-hide immediately
-- and queue the real Hide() for PLAYER_REGEN_ENABLED.
local _combatHideQueue = {}  -- [frame] = clearAlpha (bool)
local _combatHideFrame
local function FlushCombatHideQueue()
    -- Guard against rapid combat re-entry (PLAYER_REGEN_ENABLED can fire
    -- while InCombatLockdown() is already true again from a new combat).
    if InCombatLockdown() then return end
    for frame, shouldClearAlpha in pairs(_combatHideQueue) do
        if not (frame.IsForbidden and frame:IsForbidden()) then
            pcall(frame.Hide, frame)
            if shouldClearAlpha and frame.SetAlpha then frame:SetAlpha(0) end
        end
    end
    wipe(_combatHideQueue)
    _combatHideFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end
local function QueueCombatHide(frame, clearAlpha)
    _combatHideQueue[frame] = clearAlpha or false
    if not _combatHideFrame then
        _combatHideFrame = CreateFrame("Frame")
        _combatHideFrame:SetScript("OnEvent", FlushCombatHideQueue)
    end
    _combatHideFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Helpers.DeferredHideOnShow(frame, opts)
    if not frame or not frame.Show then return end
    if _deferredHideHooked[frame] then return end
    _deferredHideHooked[frame] = true
    local clearAlpha = opts and opts.clearAlpha or false
    local combatCheck = not opts or opts.combatCheck ~= false
    hooksecurefunc(frame, "Show", function(self)
        C_Timer.After(0, function()
            if self.IsForbidden and self:IsForbidden() then return end
            if InCombatLockdown() then
                if combatCheck then return end
                -- Visually hide via alpha now; defer real Hide() to combat end.
                -- Calling Hide() during combat fires ADDON_ACTION_BLOCKED even
                -- inside pcall — IsProtected() doesn't catch all restricted frames.
                if self.SetAlpha then self:SetAlpha(0) end
                QueueCombatHide(self, clearAlpha)
                return
            end
            pcall(self.Hide, self)
            if clearAlpha and self.SetAlpha then self:SetAlpha(0) end
        end)
    end)
end

--- Hook a texture's SetAtlas method to defer-clear it on the next frame.
-- @param texture     The texture to hook.
-- @param combatCheck Optional boolean (default true): skip clear if InCombatLockdown().
local _deferredAtlasHooked = setmetatable({}, { __mode = "k" })
function Helpers.DeferredSetAtlasBlock(texture, combatCheck)
    if not texture or not texture.SetAtlas then return end
    if _deferredAtlasHooked[texture] then return end
    _deferredAtlasHooked[texture] = true
    if combatCheck == nil then combatCheck = true end
    hooksecurefunc(texture, "SetAtlas", function(self)
        C_Timer.After(0, function()
            if combatCheck and InCombatLockdown() then return end
            if not self then return end
            if self.SetTexture then self:SetTexture(nil) end
            if self.SetAlpha then self:SetAlpha(0) end
        end)
    end)
end

--- Check whether Blizzard's Edit Mode panel is currently shown.
-- Uses IsShown() (not IsEditModeActive()) — checks panel visibility,
-- used for UI fade/hide suppression during edit mode.
-- @return boolean
function Helpers.IsEditModeShown()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown() or false
end

--- Combat-safe Show: skips if already shown or if protected + in combat.
-- @param frame  The frame to show.
-- @return boolean  true if shown (or already was), false if skipped/failed.
function Helpers.SafeShow(frame)
    if not frame then return false end
    if frame:IsShown() then return true end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        return false
    end
    return pcall(frame.Show, frame)
end

--- Combat-safe Hide: skips if already hidden or if protected + in combat.
-- @param frame  The frame to hide.
-- @return boolean  true if hidden (or already was), false if skipped/failed.
function Helpers.SafeHide(frame)
    if not frame then return false end
    if not frame:IsShown() then return true end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        return false
    end
    return pcall(frame.Hide, frame)
end

ns.InvalidateProfileCache = Helpers.InvalidateProfileCache
ns.CreateStateTable = Helpers.CreateStateTable
ns.IsEditModeActive = Helpers.IsEditModeActive
ns.IsEditModeShown = Helpers.IsEditModeShown
ns.SafeShow = Helpers.SafeShow
ns.SafeHide = Helpers.SafeHide
ns.DeferredHideOnShow = Helpers.DeferredHideOnShow
ns.DeferredSetAtlasBlock = Helpers.DeferredSetAtlasBlock
