--[[
    QUI Custom GUI Framework
    Style: Vertical sidebar + sticky sub-tab bar
    Accent Color: #56D1FF
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local QUICore = ns.Addon
local UIKit = ns.UIKit
local LSM = LibStub("LibSharedMedia-3.0")

-- Create GUI namespace
QUI.GUI = QUI.GUI or {}
local GUI = QUI.GUI

---------------------------------------------------------------------------
-- THEME COLORS - "Mint Condition" Palette
---------------------------------------------------------------------------
GUI.Colors = {
    -- Backgrounds
    bg = {0.051, 0.067, 0.09, 0.97},          -- #0d1117 deep dark
    bgLight = {0.094, 0.11, 0.14, 1},         -- slightly lighter for inactive tabs
    bgDark = {0.03, 0.04, 0.06, 1},
    bgContent = {1, 1, 1, 0.02},              -- card surface (white 2% alpha)
    bgSidebar = {0, 0, 0, 0.25},              -- sidebar panel background
    bgFooter = {0, 0, 0, 0.15},               -- footer bar surface

    -- Accent colors (Mint - derived from ApplyAccentColor)
    accent = {0.204, 0.827, 0.6, 1},          -- #34D399 Soft Mint
    accentLight = {0.431, 0.906, 0.718, 1},
    accentDark = {0.1, 0.5, 0.35, 1},
    accentHover = {0.3, 0.9, 0.65, 1},
    accentFaint = {0.204, 0.827, 0.6, 0.07},  -- active tile bg
    accentGlow = {0.204, 0.827, 0.6, 0.06},   -- content-area radial gradient

    -- Tab colors
    tabSelected = {0.204, 0.827, 0.6, 1},
    tabSelectedText = {1, 1, 1, 1},
    tabNormal = {1, 1, 1, 0.55},
    tabHover = {1, 1, 1, 0.85},

    -- Text colors
    text = {1, 1, 1, 1},
    textBright = {1, 1, 1, 1},
    textMuted = {1, 1, 1, 0.45},
    textDim = {1, 1, 1, 0.6},
    sectionLabel = {1, 1, 1, 0.42},

    -- Borders
    border = {1, 1, 1, 0.06},
    borderStrong = {1, 1, 1, 0.1},
    borderAccent = {0.204, 0.827, 0.6, 1},

    -- Section headers (legacy key kept for compat)
    sectionHeader = {0.431, 0.906, 0.718, 1},   -- legacy V1 section header (lighter mint) — alpha 1 required by CreateSectionHeader

    -- Slider colors
    sliderTrack = {1, 1, 1, 0.12},
    sliderThumb = {1, 1, 1, 1},
    sliderThumbBorder = {0, 0, 0, 0.2},

    -- Toggle switch colors
    toggleOff = {1, 1, 1, 0.12},
    toggleThumb = {1, 1, 1, 1},

    -- Warning/secondary accent
    warning = {0.961, 0.620, 0.043, 1},
}

local C = GUI.Colors

---------------------------------------------------------------------------
-- CACHED COLOR COMPONENTS — avoid unpack() in hot-path handlers
-- Refreshed by GUI:RefreshCachedColors() after accent color changes
---------------------------------------------------------------------------
local C_accent_r, C_accent_g, C_accent_b, C_accent_a = C.accent[1], C.accent[2], C.accent[3], C.accent[4]
local C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a = C.accentHover[1], C.accentHover[2], C.accentHover[3], C.accentHover[4]
local C_accentLight_r, C_accentLight_g, C_accentLight_b, C_accentLight_a = C.accentLight[1], C.accentLight[2], C.accentLight[3], C.accentLight[4]
local C_text_r, C_text_g, C_text_b, C_text_a = C.text[1], C.text[2], C.text[3], C.text[4]
local C_border_r, C_border_g, C_border_b, C_border_a = C.border[1], C.border[2], C.border[3], C.border[4]
local C_tabHover_r, C_tabHover_g, C_tabHover_b, C_tabHover_a = C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4]
local C_tabNormal_r, C_tabNormal_g, C_tabNormal_b, C_tabNormal_a = C.tabNormal[1], C.tabNormal[2], C.tabNormal[3], C.tabNormal[4]

local function RefreshCachedColors()
    C_accent_r, C_accent_g, C_accent_b, C_accent_a = C.accent[1], C.accent[2], C.accent[3], C.accent[4]
    C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a = C.accentHover[1], C.accentHover[2], C.accentHover[3], C.accentHover[4]
    C_accentLight_r, C_accentLight_g, C_accentLight_b, C_accentLight_a = C.accentLight[1], C.accentLight[2], C.accentLight[3], C.accentLight[4]
    C_text_r, C_text_g, C_text_b, C_text_a = C.text[1], C.text[2], C.text[3], C.text[4]
    C_border_r, C_border_g, C_border_b, C_border_a = C.border[1], C.border[2], C.border[3], C.border[4]
    C_tabHover_r, C_tabHover_g, C_tabHover_b, C_tabHover_a = C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4]
    C_tabNormal_r, C_tabNormal_g, C_tabNormal_b, C_tabNormal_a = C.tabNormal[1], C.tabNormal[2], C.tabNormal[3], C.tabNormal[4]
end
GUI.RefreshCachedColors = RefreshCachedColors

---------------------------------------------------------------------------
-- TOOLTIP: per-option on-hover explanation
-- Attaches a GameTooltip hover to any frame, gated by
-- QUI.db.profile.general.showOptionTooltips (default true).
-- Safe to call multiple times; HookScript is additive.
---------------------------------------------------------------------------
function GUI:AttachTooltip(frame, description, label)
    if not frame or type(description) ~= "string" or description == "" then return end
    if type(frame.HookScript) ~= "function" then return end
    frame._quiHasBaseTooltip = true
    frame:HookScript("OnEnter", function(self)
        local db = _G.QUI and _G.QUI.db and _G.QUI.db.profile
        if db and db.general and db.general.showOptionTooltips == false then return end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(label) == "string" and label ~= "" then
            GameTooltip:SetText(label, C.accent[1], C.accent[2], C.accent[3], 1)
            GameTooltip:AddLine(description, 1, 1, 1, true)
        else
            GameTooltip:SetText(description, 1, 1, 1, 1, true)
        end
        if type(self._quiTooltipAugment) == "function" then
            pcall(self._quiTooltipAugment, self, GameTooltip)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

---------------------------------------------------------------------------
-- ACCENT COLOR - Derive theme colors from a base accent color
---------------------------------------------------------------------------
function GUI:ApplyAccentColor(r, g, b)
    local function lerp(a, b, t) return a + (b - a) * t end
    -- Update in-place to preserve existing table references
    C.accent[1], C.accent[2], C.accent[3], C.accent[4] = r, g, b, 1
    C.accentFaint[1], C.accentFaint[2], C.accentFaint[3] = r, g, b
    C.accentGlow[1], C.accentGlow[2], C.accentGlow[3] = r, g, b
    C.accentLight[1] = lerp(r, 1, 0.3)
    C.accentLight[2] = lerp(g, 1, 0.3)
    C.accentLight[3] = lerp(b, 1, 0.3)
    C.accentLight[4] = 1
    C.accentDark[1], C.accentDark[2], C.accentDark[3], C.accentDark[4] = r * 0.5, g * 0.5, b * 0.5, 1
    C.accentHover[1] = lerp(r, 1, 0.15)
    C.accentHover[2] = lerp(g, 1, 0.15)
    C.accentHover[3] = lerp(b, 1, 0.15)
    C.accentHover[4] = 1
    C.tabSelected[1], C.tabSelected[2], C.tabSelected[3] = r, g, b
    C.borderAccent[1], C.borderAccent[2], C.borderAccent[3] = r, g, b
    C.sectionHeader[1], C.sectionHeader[2], C.sectionHeader[3] = C.accentLight[1], C.accentLight[2], C.accentLight[3]
    -- Refresh cached color components after accent derivation
    RefreshCachedColors()
end

---------------------------------------------------------------------------
-- THEME PRESETS
---------------------------------------------------------------------------
GUI.ThemePresets = {
    { name = "Sky Blue",     color = {0.376, 0.647, 0.980} },
    { name = "Classic Mint", color = {0.204, 0.827, 0.600} },
    { name = "Horde",        color = {0.780, 0.192, 0.192} },
    { name = "Alliance",     color = {0.267, 0.467, 0.800} },
    { name = "Midnight",     color = {0.580, 0.490, 0.890} },
    { name = "Amber",        color = {0.961, 0.620, 0.043} },
    { name = "Rose",         color = {0.914, 0.349, 0.518} },
    { name = "Emerald",      color = {0.196, 0.804, 0.494} },
}
-- Computed presets (not in the table — handled by name):
-- "Class Colored"  — uses RAID_CLASS_COLORS for the player's class
-- "Faction Auto"   — Horde or Alliance based on player faction
-- "Custom"         — user picks via color picker (stored in addonAccentColor)

--- Resolve a theme preset name to RGB values.
--- @param presetName string
--- @return number r, number g, number b
function GUI:ResolveThemePreset(presetName)
    -- Static presets
    for _, preset in ipairs(self.ThemePresets) do
        if preset.name == presetName then
            return preset.color[1], preset.color[2], preset.color[3]
        end
    end
    -- Dynamic presets
    if presetName == "Class Colored" then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return 0.376, 0.647, 0.980
    end
    if presetName == "Faction Auto" then
        local faction = UnitFactionGroup("player")
        if faction == "Horde" then return 0.780, 0.192, 0.192 end
        return 0.267, 0.467, 0.800
    end
    if presetName == "Custom" then
        local db = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile
        local c = db and db.general and db.general.addonAccentColor
        if c then return c[1], c[2], c[3] end
    end
    -- Fallback
    return 0.376, 0.647, 0.980
end

-- Panel dimensions (used for widget sizing)
GUI.PANEL_WIDTH = 1000
GUI.SIDEBAR_WIDTH = 190
GUI.CONTENT_WIDTH = 800  -- Panel width minus sidebar and padding

-- Settings Registry for search functionality
-- SettingsRegistry entry schema (all fields optional unless noted):
--   label         (string, required)   - user-visible setting name, also search-keyed
--   widgetType    (string)              - "toggle" | "slider" | "dropdown" | etc.
--   tabIndex      (number, required)    - top-level tab/category index
--   tabName       (string, required)    - top-level tab display name
--   subTabIndex   (number)              - sub-tab index within the tab
--   subTabName    (string)              - sub-tab display name
--   sectionName   (string)              - collapsible section the widget lives in
--   widgetBuilder (function, required)  - (parent) -> widget; used when rendering in
--                                         the Search results list
--   keywords      (array<string>)       - extra tokens to match (e.g. synonyms local
--                                         to this setting). Scored lower than label.
--   description   (string)              - (Phase 3+) one-line explanation shown under
--                                         the breadcrumb in search results.
--   synonyms      (array<string>)       - (Phase 3+) populated automatically from
--                                         the global synonym table; not typically set
--                                         by callers.
--   relatedTo     (array<string>)       - (Phase 3+) labels of other settings to
--                                         surface in this setting's "Related" footer.
GUI.SettingsRegistry = {}
GUI.StaticSettingsRegistry = GUI.StaticSettingsRegistry or {}
GUI.StaticSettingsRegistryKeys = GUI.StaticSettingsRegistryKeys or {}

-- Navigation Registry for searchable categories, subtabs, and sections
-- Allows users to search for tab names, subtab names, and section names directly
GUI.NavigationRegistry = {}
GUI.NavigationRegistryKeys = {}  -- Deduplication keys
GUI.StaticNavigationRegistry = GUI.StaticNavigationRegistry or {}
GUI.StaticNavigationRegistryKeys = GUI.StaticNavigationRegistryKeys or {}

-- Search context (auto-populated by page builders)
GUI._searchContext = {
    tabIndex = nil,
    tabName = nil,
    subTabIndex = nil,
    subTabName = nil,
    sectionName = nil,
    tileId = nil,
    subPageIndex = nil,
    featureId = nil,
    providerKey = nil,
    category = nil,
    surfaceTabKey = nil,
    surfaceUnitKey = nil,
}

-- Suppress auto-registration when rebuilding widgets for search results
GUI._suppressSearchRegistration = false

-- Deduplication keys to prevent duplicate registry entries when tabs are re-clicked
GUI.SettingsRegistryKeys = {}

-- Widget instance tracking for cross-widget synchronization (search results <-> original tabs)
GUI.WidgetInstances = {}

-- Section header registry for scroll-to-section navigation
-- Nested format: SectionRegistry[tabIndex * 10000 + subTabIndex][sectionName] -> {frame, scrollParent}
GUI.SectionRegistry = {}
GUI.SectionRegistryOrder = {}

local function CopySearchRegistryEntry(entry)
    local copy = {}
    if type(entry) ~= "table" then
        return copy
    end
    for key, value in pairs(entry) do
        copy[key] = value
    end
    return copy
end

local function BuildStaticRegistryKey(entry, extra)
    local parts = {
        extra or "",
        entry and entry.label or "",
        entry and entry.navType or "",
        entry and entry.tileId or "",
        tostring(entry and entry.subPageIndex or 0),
        entry and entry.tabName or "",
        entry and entry.subTabName or "",
        entry and entry.sectionName or "",
    }
    return table.concat(parts, "\31")
end

local function BuildSearchRouteLabels(info)
    if type(info) ~= "table" then
        return nil, nil, nil
    end

    local tabLabel = info.tabName
    if (type(tabLabel) ~= "string" or tabLabel == "")
        and type(info.tileId) == "string" and info.tileId ~= "" then
        tabLabel = info.tileId
    end

    local subTabLabel = info.subTabName
    if (type(subTabLabel) ~= "string" or subTabLabel == "")
        and info.subPageIndex ~= nil then
        subTabLabel = "Page " .. tostring(info.subPageIndex)
    end

    local sectionLabel = info.sectionName
    if type(sectionLabel) ~= "string" or sectionLabel == "" then
        sectionLabel = nil
    end

    return tabLabel, subTabLabel, sectionLabel
end

local function BuildSearchNavigationLabel(navType, info)
    local tabLabel, subTabLabel, sectionLabel = BuildSearchRouteLabels(info)
    if navType == "tab" then
        return tabLabel or sectionLabel
    end

    local parts = {}
    if tabLabel and tabLabel ~= "" then
        parts[#parts + 1] = tabLabel
    end

    if navType == "subtab" then
        if subTabLabel and subTabLabel ~= "" then
            parts[#parts + 1] = subTabLabel
        end
        return #parts > 0 and table.concat(parts, " > ") or nil
    end

    if subTabLabel and subTabLabel ~= "" then
        parts[#parts + 1] = subTabLabel
    end
    if sectionLabel and sectionLabel ~= "" then
        parts[#parts + 1] = sectionLabel
    end

    return #parts > 0 and table.concat(parts, " > ") or nil
end

local function BuildSearchNavigationKeywords(info)
    local tabLabel, subTabLabel, sectionLabel = BuildSearchRouteLabels(info)
    local keywords = {}
    if tabLabel and tabLabel ~= "" then
        keywords[#keywords + 1] = tabLabel
    end
    if subTabLabel and subTabLabel ~= "" then
        keywords[#keywords + 1] = subTabLabel
    end
    if sectionLabel and sectionLabel ~= "" then
        keywords[#keywords + 1] = sectionLabel
    end
    return keywords
end

function GUI:ResetStaticSearchIndex()
    self.StaticSettingsRegistry = {}
    self.StaticSettingsRegistryKeys = {}
    self.StaticNavigationRegistry = {}
    self.StaticNavigationRegistryKeys = {}
end

function GUI:ApplyGeneratedSearchCache(cache)
    self:ResetStaticSearchIndex()

    if type(cache) ~= "table" then
        return false
    end

    for _, entry in ipairs(cache.navigation or {}) do
        self:RegisterStaticNavigationEntry(entry)
    end
    for _, entry in ipairs(cache.settings or {}) do
        self:RegisterStaticSettingEntry(entry)
    end

    self._generatedSearchCacheVersion = cache.version
    return true
end

function GUI:RegisterStaticNavigationEntry(entry)
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
        return nil
    end

    local regKey = BuildStaticRegistryKey(entry, "nav")
    if self.StaticNavigationRegistryKeys[regKey] then
        return nil
    end

    self.StaticNavigationRegistryKeys[regKey] = true

    local stored = CopySearchRegistryEntry(entry)
    stored.navType = stored.navType or "tab"
    table.insert(self.StaticNavigationRegistry, stored)
    return stored
end

function GUI:RegisterStaticSettingEntry(entry)
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
        return nil
    end

    local regKey = BuildStaticRegistryKey(entry, "setting")
    if self.StaticSettingsRegistryKeys[regKey] then
        return nil
    end

    self.StaticSettingsRegistryKeys[regKey] = true

    local stored = CopySearchRegistryEntry(entry)
    table.insert(self.StaticSettingsRegistry, stored)
    return stored
end

GUI._dbPathCache = GUI._dbPathCache or setmetatable({}, { __mode = "k" })

local function CopySerializableValue(value, depth, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end
    if valueType ~= "table" then
        return nil
    end

    depth = (depth or 0) + 1
    if depth > 6 then
        return nil
    end

    seen = seen or {}
    if seen[value] then
        return nil
    end
    seen[value] = true

    local copy = {}
    for key, nested in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local nestedCopy = CopySerializableValue(nested, depth, seen)
            if nestedCopy ~= nil then
                copy[key] = nestedCopy
            end
        end
    end

    seen[value] = nil
    return copy
end

local function FindDBTablePath(target, current, prefix, seen, depth)
    if target == nil or current == nil or type(current) ~= "table" then
        return nil
    end
    if current == target then
        return prefix
    end

    depth = (depth or 0) + 1
    if depth > 12 then
        return nil
    end

    seen = seen or {}
    if seen[current] then
        return nil
    end
    seen[current] = true

    for key, value in pairs(current) do
        if type(key) == "string" and type(value) == "table" then
            local path = FindDBTablePath(target, value, prefix .. "." .. key, seen, depth)
            if path then
                seen[current] = nil
                return path
            end
        end
    end

    seen[current] = nil
    return nil
end

function GUI:ResolveSearchDBTablePath(dbTable)
    if type(dbTable) ~= "table" then
        return nil
    end

    local cached = self._dbPathCache and self._dbPathCache[dbTable]
    if type(cached) == "string" and cached ~= "" then
        return cached
    end

    local db = QUI and QUI.db
    if not db then
        return nil
    end

    local roots = {
        { path = "profile", value = db.profile },
        { path = "char", value = db.char },
        { path = "global", value = db.global },
    }

    for _, root in ipairs(roots) do
        local path = FindDBTablePath(dbTable, root.value, root.path)
        if path then
            self._dbPathCache[dbTable] = path
            return path
        end
    end

    return nil
end

function GUI:ResolveSearchDBTable(dbPath)
    if type(dbPath) ~= "string" or dbPath == "" then
        return nil
    end

    local db = QUI and QUI.db
    if not db then
        return nil
    end

    local segments = {}
    for part in dbPath:gmatch("[^%.]+") do
        segments[#segments + 1] = part
    end

    local current = db
    for _, segment in ipairs(segments) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[segment]
    end

    return type(current) == "table" and current or nil
end

local function BuildSearchSettingsRegistryKey(context, label)
    return table.concat({
        label or "",
        tostring(context and context.tabIndex or 0),
        tostring(context and context.subTabIndex or 0),
        context and context.sectionName or "",
        context and context.tileId or "",
        tostring(context and context.subPageIndex or 0),
        context and context.featureId or "",
        context and context.surfaceTabKey or "",
        context and context.surfaceUnitKey or "",
    }, "\31")
end

function GUI:BuildSearchWidgetDescriptor(kind, dbKey, dbTable, extra)
    if type(dbKey) ~= "string" or dbKey == "" then
        return nil
    end

    local dbPath = self:ResolveSearchDBTablePath(dbTable)
    if not dbPath then
        return nil
    end

    local descriptor = {
        kind = kind,
        dbKey = dbKey,
        dbPath = dbPath,
        featureId = self._searchContext.featureId,
        providerKey = self._searchContext.providerKey,
        category = self._searchContext.category,
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            local copied = CopySerializableValue(value)
            if copied ~= nil then
                descriptor[key] = copied
            end
        end
    end

    return descriptor
end

function GUI:RegisterSearchSettingWidget(entry)
    local context = self._searchContext or {}
    if self._suppressSearchRegistration
        or type(entry) ~= "table"
        or type(entry.label) ~= "string"
        or entry.label == "" then
        return nil
    end

    local stored = {
        label = entry.label,
        widgetType = entry.widgetType,
        tabIndex = context.tabIndex,
        tabName = context.tabName,
        subTabIndex = context.subTabIndex,
        subTabName = context.subTabName,
        sectionName = context.sectionName,
        tileId = context.tileId,
        subPageIndex = context.subPageIndex,
        featureId = context.featureId,
        providerKey = context.providerKey,
        category = context.category,
        surfaceTabKey = context.surfaceTabKey,
        surfaceUnitKey = context.surfaceUnitKey,
        widgetBuilder = entry.widgetBuilder,
        widgetDescriptor = entry.widgetDescriptor,
        keywords = entry.keywords,
        description = entry.description,
        relatedTo = entry.relatedTo,
    }

    local regKey = BuildSearchSettingsRegistryKey(context, entry.label)
    if self.SettingsRegistryKeys[regKey] then
        return nil
    end

    self.SettingsRegistryKeys[regKey] = true
    table.insert(self.SettingsRegistry, stored)
    return stored
end

function GUI:RegisterSearchNavigation(navType, info)
    return self:RegisterNavigationItem(navType, info)
end

-- Sidebar tree animation/layout config
GUI._sidebarAnimDuration = 0.16
GUI._sidebarRowHeights = {
    level1 = 26,
    level2 = 22,
    level3 = 20,
}

-- Generate unique key for widget instance tracking
local function GetWidgetKey(dbTable, dbKey)
    if not dbTable or not dbKey then return nil end
    return tostring(dbTable) .. "_" .. dbKey
end

-- Register a widget instance for sync tracking
local function RegisterWidgetInstance(widget, dbTable, dbKey)
    local widgetKey = GetWidgetKey(dbTable, dbKey)
    widget._syncDBTable = dbTable
    widget._syncDBKey = dbKey
    if not widgetKey then return end
    GUI.WidgetInstances[widgetKey] = GUI.WidgetInstances[widgetKey] or {}
    table.insert(GUI.WidgetInstances[widgetKey], widget)
    widget._widgetKey = widgetKey
end

-- Unregister a widget instance (called during cleanup)
local function UnregisterWidgetInstance(widget)
    if not widget._widgetKey then return end
    local instances = GUI.WidgetInstances[widget._widgetKey]
    if not instances then return end
    for i = #instances, 1, -1 do
        if instances[i] == widget then
            table.remove(instances, i)
            break
        end
    end
    -- Prune empty arrays to prevent unbounded table growth
    if #instances == 0 then
        GUI.WidgetInstances[widget._widgetKey] = nil
    end
end

-- Broadcast value change to all sibling widget instances
local function BroadcastToSiblings(widget, val)
    if not widget._widgetKey then return end
    local instances = GUI.WidgetInstances[widget._widgetKey]
    if not instances then return end
    for _, sibling in ipairs(instances) do
        if sibling ~= widget and sibling.UpdateVisual then
            sibling.UpdateVisual(val)
        end
    end
end

local function GetProviderSyncContext(frame)
    local current = frame
    local depth = 0
    while current and depth < 50 do
        if current._quiProviderSync then
            return current._quiProviderSync
        end
        if not current.GetParent then
            break
        end
        current = current:GetParent()
        depth = depth + 1
    end
end

local function ApplyWidgetSyncContext(widget, dbTable, dbKey)
    if not widget then return end
    widget._syncDBTable = dbTable
    widget._syncDBKey = dbKey
    if not widget._providerSyncContext then
        widget._providerSyncContext = GetProviderSyncContext(widget)
    end
end

local function NotifyProviderChangedForWidget(widget, options)
    if not widget then return end
    local context = widget._providerSyncContext or GetProviderSyncContext(widget)
    if not context or not context.providerKey then return end

    local compat = ns.Settings and ns.Settings.RenderAdapters
    if not compat or type(compat.NotifyProviderChanged) ~= "function" then return end

    local providerOptions = widget._providerSyncOptions or {}
    local structural = options and options.structural
    if structural == nil then
        if providerOptions.structural ~= nil then
            structural = providerOptions.structural == true
        else
            structural = not (widget._syncDBTable and widget._syncDBKey)
        end
    end

    compat.NotifyProviderChanged(context.providerKey, {
        sourceSurfaceId = context.surfaceId,
        structural = structural == true,
    })
end

local function MaybeAutoNotifyProviderSync(widget, options)
    if not widget then return end
    local context = widget._providerSyncContext or GetProviderSyncContext(widget)
    if not context then return end

    local providerOptions = widget._providerSyncOptions or {}
    local auto = providerOptions.auto
    if auto == nil then
        auto = not (widget._syncDBTable and widget._syncDBKey)
    end
    if not auto then return end

    NotifyProviderChangedForWidget(widget, options)
end

local function BuildPinnedWidgetDescriptor(binding)
    if type(binding) ~= "table" then
        return nil
    end

    return {
        kind = binding.kind,
        label = binding.label,
        pinLabel = binding.pinLabel,
        tabIndex = binding.tabIndex,
        tabName = binding.tabName,
        subTabIndex = binding.subTabIndex,
        subTabName = binding.subTabName,
        sectionName = binding.sectionName,
        tileId = binding.tileId,
        subPageIndex = binding.subPageIndex,
        featureId = binding.featureId,
        surfaceTabKey = binding.surfaceTabKey,
        surfaceUnitKey = binding.surfaceUnitKey,
    }
end

local function MaybeBindPinnedWidget(widget, kind, label, dbKey, dbTable, interactiveFrame, registryInfo)
    local pins = ns.Settings and ns.Settings.Pins
    if not pins or type(pins.BindWidget) ~= "function" then
        return
    end
    if registryInfo and registryInfo.pinnable == false then
        return
    end

    local searchContext = GUI._searchContext or {}
    pins:BindWidget(widget, {
        kind = kind,
        label = label,
        pinLabel = registryInfo and registryInfo.pinLabel or nil,
        pinPath = registryInfo and registryInfo.pinPath or nil,
        dbKey = dbKey,
        dbTable = dbTable,
        interactiveFrame = interactiveFrame,
        tabIndex = searchContext.tabIndex,
        tabName = searchContext.tabName,
        subTabIndex = searchContext.subTabIndex,
        subTabName = searchContext.subTabName,
        sectionName = searchContext.sectionName,
        tileId = searchContext.tileId,
        subPageIndex = searchContext.subPageIndex,
        featureId = searchContext.featureId,
        surfaceTabKey = searchContext.surfaceTabKey,
        surfaceUnitKey = searchContext.surfaceUnitKey,
    })

    if label and type(pins.AttachWidgetChrome) == "function" then
        pins:AttachWidgetChrome(widget, widget, interactiveFrame, label)
    end
end

local function MaybeUpdatePinnedWidgetValue(widget, value)
    local pins = ns.Settings and ns.Settings.Pins
    if not pins or type(pins.UpdatePinnedValue) ~= "function" then
        return
    end

    local binding = widget and widget._quiPinBinding or nil
    if type(binding) ~= "table" then
        return
    end

    local path = binding.path
    if (type(path) ~= "string" or path == "") and type(pins.GetResolvedWidgetPath) == "function" then
        path = pins:GetResolvedWidgetPath(binding)
        binding.path = path
    end

    if type(path) ~= "string" or path == "" or not pins:IsPinned(path) then
        return
    end

    pins:UpdatePinnedValue(path, value, BuildPinnedWidgetDescriptor(binding))
end

function GUI:SetWidgetProviderSyncOptions(widget, options)
    if not widget then return nil end
    widget._providerSyncOptions = options or {}
    ApplyWidgetSyncContext(widget, widget._syncDBTable, widget._syncDBKey)
    return widget
end

function GUI:NotifyProviderChangedForWidget(widget, options)
    NotifyProviderChangedForWidget(widget, options)
end

function GUI:CleanupWidgetTree(root)
    if not root then return end
    for _, child in ipairs({root:GetChildren()}) do
        self:CleanupWidgetTree(child)
    end
    UnregisterWidgetInstance(root)
end

function GUI:TeardownFrameTree(root, options)
    if not root then return end
    options = options or {}

    self:CleanupWidgetTree(root)

    if root.GetChildren then
        for _, child in ipairs({root:GetChildren()}) do
            if child.Hide then child:Hide() end
            if child.ClearAllPoints then child:ClearAllPoints() end
            if child.SetParent then child:SetParent(nil) end
        end
    end

    if root.GetRegions then
        for _, region in ipairs({root:GetRegions()}) do
            if region.Hide then region:Hide() end
            if region.SetParent then region:SetParent(nil) end
        end
    end

    if options.includeRoot then
        if root.Hide then root:Hide() end
        if root.ClearAllPoints then root:ClearAllPoints() end
        if root.SetParent then root:SetParent(nil) end
    end
end

-- Set search context for auto-registration (call at start of page builder)
function GUI:SetSearchContext(info)
    self._searchContext.tabIndex = info.tabIndex
    self._searchContext.tabName = info.tabName
    self._searchContext.subTabIndex = info.subTabIndex or nil
    self._searchContext.subTabName = info.subTabName or nil
    self._searchContext.sectionName = info.sectionName or nil
    self._searchContext.tileId = info.tileId or nil
    self._searchContext.subPageIndex = info.subPageIndex or nil
    self._searchContext.featureId = info.featureId or nil
    self._searchContext.providerKey = info.providerKey or nil
    self._searchContext.category = info.category or nil
    self._searchContext.surfaceTabKey = info.surfaceTabKey or nil
    self._searchContext.surfaceUnitKey = info.surfaceUnitKey or nil

    -- Auto-register navigation items for tabs and subtabs
    if (info.tabIndex or info.tileId or info.tabName) and (info.tabName or info.tileId) then
        self:RegisterSearchNavigation("tab", info)
        if (info.subTabIndex or info.subPageIndex or info.subTabName) and (info.subTabName or info.subPageIndex) then
            self:RegisterSearchNavigation("subtab", info)
        end
    end
end

-- Set current section (call when entering a new section within a page)
function GUI:SetSearchSection(sectionName)
    self._searchContext.sectionName = sectionName

    -- Auto-register section as navigation item
    if sectionName and sectionName ~= "" and (self._searchContext.tabIndex or self._searchContext.tileId or self._searchContext.tabName) then
        self:RegisterSearchNavigation("section", {
            tabIndex = self._searchContext.tabIndex,
            tabName = self._searchContext.tabName,
            subTabIndex = self._searchContext.subTabIndex,
            subTabName = self._searchContext.subTabName,
            sectionName = sectionName,
            tileId = self._searchContext.tileId,
            subPageIndex = self._searchContext.subPageIndex,
            featureId = self._searchContext.featureId,
            surfaceTabKey = self._searchContext.surfaceTabKey,
            surfaceUnitKey = self._searchContext.surfaceUnitKey,
        })
    end
end

-- Clear search context (optional, for safety)
function GUI:ClearSearchContext()
    self._searchContext = {
        tabIndex = nil,
        tabName = nil,
        subTabIndex = nil,
        subTabName = nil,
        sectionName = nil,
        tileId = nil,
        subPageIndex = nil,
        featureId = nil,
        providerKey = nil,
        category = nil,
        surfaceTabKey = nil,
        surfaceUnitKey = nil,
    }
end

local function GetSectionRegistryKey(tabIndex, subTabIndex)
    return (tabIndex or 0) * 10000 + (subTabIndex or 0)
end

local function GetRegisteredSection(tabIndex, subTabIndex, sectionName)
    if not sectionName or sectionName == "" then return nil end
    local registry = GUI.SectionRegistry[GetSectionRegistryKey(tabIndex, subTabIndex)]
    return registry and registry[sectionName] or nil
end

function GUI:ScrollToRegisteredSection(tabIndex, subTabIndex, sectionName, opts)
    local entry = GetRegisteredSection(tabIndex, subTabIndex, sectionName)
    if not entry or not entry.frame then return false end

    local scroll = entry.scrollParent or self:_findAncestorScroll(entry.frame)
    if scroll and scroll.SetVerticalScroll and entry.frame.GetTop and scroll.GetTop then
        local sectionTop = entry.frame:GetTop()
        local scrollTop = scroll:GetTop()
        if sectionTop and scrollTop then
            local offset = math.max(0, (scrollTop - sectionTop) + 10)
            pcall(scroll.SetVerticalScroll, scroll, offset)
        end
    end

    if not opts or opts.pulse ~= false then
        self:PulseWidget(entry.frame)
    end

    return true
end

-- Search jump-to-setting uses _findWidgetByLabel + per-widget scroll
-- (see options/framework_v2.lua).

-- Search results emit (tabIndex, subTabIndex) coordinates. Translate
-- through the nav map and dispatch to SelectFeatureTile so clicks from
-- nav rows, "Go >" buttons, and breadcrumbs all land on the right tile.
function GUI:NavigateTo(tabIndex, subTabIndex, sectionName)
    local frame = self.MainFrame
    if not frame then return end
    if not tabIndex then return end

    local route = GUI.ResolveV2Navigation and GUI:ResolveV2Navigation(tabIndex, subTabIndex)
    if not route then route = { tileId = "welcome", subPageIndex = nil } end
    local _, idx = GUI:FindV2TileByID(frame, route.tileId)
    if not idx then idx = 1 end
    if frame._searchBox and frame._searchBox.editBox then
        frame._searchBox.editBox:SetText("")
    end
    if frame._searchResultsArea then frame._searchResultsArea:Hide() end
    if frame._tileContent then frame._tileContent:Show() end
    GUI:SelectFeatureTile(frame, idx, {
        subPageIndex = route.subPageIndex,
        sectionName = sectionName,
        searchTabIndex = tabIndex,
        searchSubTabIndex = subTabIndex,
    })
end

-- Register a navigation item (tab, subtab, or section) for search
-- type: "tab", "subtab", or "section"
function GUI:RegisterNavigationItem(navType, info)
    if self._suppressSearchRegistration then return end
    if not info.tabIndex then return end

    -- Build unique key based on type and navigation path
    -- Use arithmetic keys for tab/subtab (avoids string concat garbage)
    local regKey
    if navType == "tab" then
        regKey = info.tabIndex * 100000
    elseif navType == "subtab" then
        regKey = info.tabIndex * 100000 + (info.subTabIndex or 0)
        if type(info.surfaceTabKey) == "string" and info.surfaceTabKey ~= "" then
            regKey = tostring(regKey) .. ":" .. info.surfaceTabKey
        end
    elseif navType == "section" then
        -- Section keys include a string name; keep string concat
        regKey = info.tabIndex * 100000 + (info.subTabIndex or 0) + 50000
        if type(info.surfaceTabKey) == "string" and info.surfaceTabKey ~= "" then
            regKey = tostring(regKey) .. ":" .. info.surfaceTabKey
        end
        local sectionKeys = self._navSectionKeys
        if not sectionKeys then
            sectionKeys = {}
            self._navSectionKeys = sectionKeys
        end
        local sName = info.sectionName or ""
        if not sectionKeys[regKey] then sectionKeys[regKey] = {} end
        if sectionKeys[regKey][sName] then return end
        sectionKeys[regKey][sName] = true
    else
        return
    end

    -- Deduplicate (tab / subtab use numeric key directly)
    if navType ~= "section" then
        if self.NavigationRegistryKeys[regKey] then return end
        self.NavigationRegistryKeys[regKey] = true
    end

    -- Build display label based on type
    local label, keywords
    if navType == "tab" then
        label = info.tabName or ""
        keywords = {info.tabName or ""}
    elseif navType == "subtab" then
        label = (info.tabName or "") .. " > " .. (info.subTabName or "")
        keywords = {info.tabName or "", info.subTabName or ""}
    elseif navType == "section" then
        local parts = {info.tabName or ""}
        if info.subTabName and info.subTabName ~= "" then
            table.insert(parts, info.subTabName)
        end
        table.insert(parts, info.sectionName or "")
        label = table.concat(parts, " > ")
        keywords = {info.tabName or "", info.subTabName or "", info.sectionName or ""}
    end

    local entry = {
        navType = navType,
        label = label,
        tabIndex = info.tabIndex,
        tabName = info.tabName,
        subTabIndex = info.subTabIndex,
        subTabName = info.subTabName,
        sectionName = info.sectionName,
        tileId = info.tileId,
        subPageIndex = info.subPageIndex,
        featureId = info.featureId,
        surfaceTabKey = info.surfaceTabKey,
        surfaceUnitKey = info.surfaceUnitKey,
        keywords = keywords,
    }

    table.insert(self.NavigationRegistry, entry)
end

-- Tiles are eagerly built into a hidden parent on login (see
-- GUI:BuildTilePage in options/framework_v2.lua) to populate the search
-- index up-front.

---------------------------------------------------------------------------
-- FONT PATH (uses bundled Quazii font for consistent panel formatting)
---------------------------------------------------------------------------
local FONT_PATH = LSM:Fetch("font", "Quazii") or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
GUI.FONT_PATH = FONT_PATH

-- Helper for future configurability
local function GetFontPath()
    return FONT_PATH
end

function GUI:GetFontPath()
    return GetFontPath()
end

---------------------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------------------
local function CreateBackdrop(frame, bgColor, borderColor)
    local px = QUICore:GetPixelSize(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    frame:SetBackdropColor(unpack(bgColor or C.bg))
    frame:SetBackdropBorderColor(unpack(borderColor or C.border))
end

local function BindWidgetMethod(container, fn)
    return function(selfOrFirst, ...)
        if selfOrFirst == container then
            return fn(...)
        end
        return fn(selfOrFirst, ...)
    end
end

local function SetFont(fontString, size, flags, color)
    fontString:SetFont(GetFontPath(), size or 12, flags or "")
    if color then
        fontString:SetTextColor(unpack(color))
    end
end

-- Ensure all text in a frame subtree uses the shared QUI font.
-- Uses select() iteration to avoid temporary table allocations.
local function ApplyFontToFrameRecursive(frame, fontPath)
    if not frame then return end

    local numRegions = frame.GetNumRegions and frame:GetNumRegions() or 0
    for i = 1, numRegions do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetFont and region.SetFont then
            local _, size, flags = region:GetFont()
            if size and size > 0 then
                region:SetFont(fontPath, size, flags or "")
            end
        end
    end

    local numChildren = frame.GetNumChildren and frame:GetNumChildren() or 0
    for i = 1, numChildren do
        local child = select(i, frame:GetChildren())
        ApplyFontToFrameRecursive(child, fontPath)
    end
end

function GUI:ApplyTabFont(frame)
    if not frame then return end
    ApplyFontToFrameRecursive(frame, GetFontPath())
end

---------------------------------------------------------------------------
-- WIDGET: LABEL
---------------------------------------------------------------------------
function GUI:CreateLabel(parent, text, size, color, anchor, x, y)
    -- Mark content as added (for section header auto-spacing)
    if parent._hasContent ~= nil then
        parent._hasContent = true
    end
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(label, size or 12, "", color or C.text)
    label:SetText(text or "")
    if anchor then
        label:SetPoint(anchor, parent, anchor, x or 0, y or 0)
    end
    return label
end

---------------------------------------------------------------------------
-- WIDGET: THEMED BUTTON (ghost/primary variants, transparent background)
---------------------------------------------------------------------------
function GUI:CreateButton(parent, text, width, height, onClick, variant)
    variant = variant or "ghost"
    local UIKit = ns.UIKit

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 120, height or 22)

    if UIKit and UIKit.CreateBorderLines and not button._pixelBorderReady then
        UIKit.CreateBorderLines(button)
        button._pixelBorderReady = true
    end

    local hoverBg = button:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints(button)
    hoverBg:SetColorTexture(1, 1, 1, 0.06)
    hoverBg:Hide()
    button._hoverBg = hoverBg

    local btnText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(text or "Button")
    button.text = btnText

    local function ApplyButtonVariant(btn, variantName)
        if variantName == "primary" then
            if UIKit and UIKit.UpdateBorderLines then
                UIKit.UpdateBorderLines(btn, 1, C.accent[1], C.accent[2], C.accent[3], 0.5)
            end
            if btn.text then btn.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end
        else
            if UIKit and UIKit.UpdateBorderLines then
                UIKit.UpdateBorderLines(btn, 1, 1, 1, 1, 0.2)
            end
            if btn.text then btn.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1) end
        end
    end
    ApplyButtonVariant(button, variant)

    local f, _, flags = button.text:GetFont()
    button.text:SetFont(f or (UIKit and UIKit.ResolveFontPath and UIKit.ResolveFontPath(GUI:GetFontPath())) or GetFontPath(), 10, flags or "")
    button:SetHeight(height or 22)
    if not width or width <= 0 then
        button:SetWidth((button.text:GetStringWidth() or 0) + 24)
    end

    button:SetScript("OnEnter", function(self)
        if variant == "primary" then
            if UIKit and UIKit.UpdateBorderLines then
                UIKit.UpdateBorderLines(self, 1, C.accent[1], C.accent[2], C.accent[3], 1)
            end
            self._hoverBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.08)
        else
            if self.text then self.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end
            self._hoverBg:SetColorTexture(1, 1, 1, 0.06)
        end
        self._hoverBg:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if variant == "primary" then
            if UIKit and UIKit.UpdateBorderLines then
                UIKit.UpdateBorderLines(self, 1, C.accent[1], C.accent[2], C.accent[3], 0.5)
            end
        else
            if self.text then self.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1) end
        end
        self._hoverBg:Hide()
    end)
    button:SetScript("OnMouseDown", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, -1) end
        self._hoverBg:SetAlpha(1.4)
    end)
    button:SetScript("OnMouseUp", function(self)
        if self.text then self.text:SetPoint("CENTER", 0, 0) end
        self._hoverBg:SetAlpha(1)
    end)

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    function button:SetText(newText)
        btnText:SetText(newText)
    end

    -- Public method for callers that need custom border colors.
    function button:SetBorderColor(r, g, b, a)
        if UIKit and UIKit.UpdateBorderLines then
            UIKit.UpdateBorderLines(self, 1, r, g, b, a or 1, false)
        end
    end

    -- Backward-compatible alias used by some option tabs.
    button.SetFieldBorderColor = button.SetBorderColor

    return button
end

---------------------------------------------------------------------------
-- WIDGET: INLINE EDIT BOX (compact utility input)
---------------------------------------------------------------------------
function GUI:CreateInlineEditBox(parent, options)
    options = options or {}
    local UIKit = ns.UIKit

    local width = options.width or 100
    local height = options.height or 22
    local editHeight = options.editHeight or (height - 2)
    local textInset = options.textInset or 6
    local fontSize = options.fontSize or 11
    local justifyH = options.justifyH or "LEFT"
    local commitOnFocusLost = options.commitOnFocusLost ~= false
    local bgColor = options.bgColor or {0.08, 0.08, 0.08, 1}
    local borderColor = options.borderColor or {0.25, 0.25, 0.25, 1}
    local activeBorderColor = options.activeBorderColor or C.accent

    local field = CreateFrame("Frame", nil, parent)
    if UIKit and UIKit.SetSizePx then
        UIKit.SetSizePx(field, width, height)
    else
        field:SetSize(width, height)
    end

    if UIKit and UIKit.CreateBackground then
        UIKit.CreateBackground(field, bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    else
        local bg = field:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    local function ApplyFallbackBorder(r, g, b, a)
        if not field._fallbackBorder then
            field._fallbackBorder = {
                top = field:CreateTexture(nil, "OVERLAY"),
                bottom = field:CreateTexture(nil, "OVERLAY"),
                left = field:CreateTexture(nil, "OVERLAY"),
                right = field:CreateTexture(nil, "OVERLAY"),
            }
            for _, edge in pairs(field._fallbackBorder) do
                edge:SetTexture("Interface\\Buttons\\WHITE8x8")
            end
        end

        local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(field)) or 1
        local border = field._fallbackBorder

        border.top:ClearAllPoints()
        border.top:SetPoint("TOPLEFT", field, "TOPLEFT", 0, 0)
        border.top:SetPoint("TOPRIGHT", field, "TOPRIGHT", 0, 0)
        border.top:SetHeight(px)

        border.bottom:ClearAllPoints()
        border.bottom:SetPoint("BOTTOMLEFT", field, "BOTTOMLEFT", 0, 0)
        border.bottom:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 0, 0)
        border.bottom:SetHeight(px)

        border.left:ClearAllPoints()
        border.left:SetPoint("TOPLEFT", border.top, "BOTTOMLEFT", 0, 0)
        border.left:SetPoint("BOTTOMLEFT", border.bottom, "TOPLEFT", 0, 0)
        border.left:SetWidth(px)

        border.right:ClearAllPoints()
        border.right:SetPoint("TOPRIGHT", border.top, "BOTTOMRIGHT", 0, 0)
        border.right:SetPoint("BOTTOMRIGHT", border.bottom, "TOPRIGHT", 0, 0)
        border.right:SetWidth(px)

        for _, edge in pairs(border) do
            edge:SetVertexColor(r or 0.25, g or 0.25, b or 0.25, a or 1)
        end
    end

    function field:SetFieldBorderColor(r, g, b, a)
        if UIKit and UIKit.UpdateBorderLines then
            if not self._pixelBorderReady and UIKit.CreateBorderLines then
                UIKit.CreateBorderLines(self)
                self._pixelBorderReady = true
            end
            UIKit.UpdateBorderLines(self, 1, r, g, b, a, false)
        else
            ApplyFallbackBorder(r, g, b, a)
        end
    end
    field:SetFieldBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

    local editBox = CreateFrame("EditBox", nil, field)
    if UIKit and UIKit.SetPointPx then
        UIKit.SetPointPx(editBox, "LEFT", field, "LEFT", textInset, 0)
        UIKit.SetPointPx(editBox, "RIGHT", field, "RIGHT", -textInset, 0)
        UIKit.SetHeightPx(editBox, editHeight)
    else
        editBox:SetPoint("LEFT", field, "LEFT", textInset, 0)
        editBox:SetPoint("RIGHT", field, "RIGHT", -textInset, 0)
        editBox:SetHeight(editHeight)
    end
    editBox:SetAutoFocus(false)
    editBox:SetFont(GetFontPath(), fontSize, "")
    editBox:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a)
    editBox:SetJustifyH(justifyH)

    if options.maxLetters and options.maxLetters > 0 then
        editBox:SetMaxLetters(options.maxLetters)
    end
    if options.numeric ~= nil then
        editBox:SetNumeric(options.numeric and true or false)
    end
    if options.text ~= nil then
        editBox:SetText(tostring(options.text))
    end

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if options.onTextChanged then
            options.onTextChanged(self, userInput)
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if options.onEnterPressed then
            options.onEnterPressed(self)
        else
            self:ClearFocus()
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        if options.onEscapePressed then
            options.onEscapePressed(self)
        else
            self:ClearFocus()
        end
    end)

    editBox:SetScript("OnEditFocusGained", function(self)
        field:SetFieldBorderColor(activeBorderColor[1], activeBorderColor[2], activeBorderColor[3], activeBorderColor[4] or 1)
        if options.onEditFocusGained then
            options.onEditFocusGained(self)
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        field:SetFieldBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        if commitOnFocusLost and options.onCommit then
            options.onCommit(self)
        end
        if options.onEditFocusLost then
            options.onEditFocusLost(self)
        end
    end)

    function field:SetEnabled(enabled)
        editBox:SetEnabled(enabled)
        editBox:EnableMouse(enabled)
        self:SetAlpha(enabled and 1 or 0.6)
        if not enabled then
            editBox:ClearFocus()
        end
    end

    field.editBox = editBox
    return field, editBox
end

---------------------------------------------------------------------------
-- CONFIRMATION DIALOG (QUI-styled replacement for StaticPopup)
-- Singleton frame, lazy-created and reused
---------------------------------------------------------------------------
local confirmDialog = nil

function GUI:ShowConfirmation(options)
    -- options = {
    --   title = "Delete Profile?",
    --   message = "Delete profile 'ProfileName'?",
    --   warningText = "This cannot be undone.",  -- optional, amber text
    --   acceptText = "Delete",
    --   cancelText = "Cancel",
    --   onAccept = function() end,
    --   onCancel = function() end,  -- optional
    --   isDestructive = true,       -- amber text on accept button
    -- }

    if not confirmDialog then
        -- Create singleton dialog frame
        confirmDialog = CreateFrame("Frame", "QUI_ConfirmDialog", UIParent, "BackdropTemplate")
        confirmDialog:SetSize(320, 160)
        confirmDialog:SetPoint("CENTER")
        confirmDialog:SetFrameStrata("FULLSCREEN_DIALOG")
        confirmDialog:SetFrameLevel(500)
        confirmDialog:SetToplevel(true)
        confirmDialog:EnableMouse(true)
        confirmDialog:SetMovable(true)
        confirmDialog:RegisterForDrag("LeftButton")
        confirmDialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
        confirmDialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        confirmDialog:SetClampedToScreen(true)
        confirmDialog:Hide()

        -- Backdrop
        local px = QUICore:GetPixelSize(confirmDialog)
        confirmDialog:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        confirmDialog:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.98)
        confirmDialog:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        -- Title
        confirmDialog.title = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.title, 14, "", C.accentLight)
        confirmDialog.title:SetPoint("TOP", 0, -18)

        -- Message
        confirmDialog.message = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.message, 12, "", C.text)
        confirmDialog.message:SetPoint("TOP", 0, -50)
        confirmDialog.message:SetWidth(280)
        confirmDialog.message:SetJustifyH("CENTER")

        -- Warning text
        confirmDialog.warning = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.warning, 11, "", C.warning)
        confirmDialog.warning:SetPoint("TOP", confirmDialog.message, "BOTTOM", 0, -8)

        -- Accept button (left)
        confirmDialog.acceptBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
        confirmDialog.acceptBtn:SetSize(100, 28)
        confirmDialog.acceptBtn:SetPoint("BOTTOMLEFT", 40, 20)
        confirmDialog.acceptBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        confirmDialog.acceptBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        confirmDialog.acceptBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        confirmDialog.acceptBtn.text = confirmDialog.acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        confirmDialog.acceptBtn.text:SetFont(GetFontPath(), 12, "")
        confirmDialog.acceptBtn.text:SetPoint("CENTER", 0, 0)

        confirmDialog.acceptBtn:SetScript("OnEnter", function(self)
            pcall(self.SetBackdropBorderColor, self, C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        confirmDialog.acceptBtn:SetScript("OnLeave", function(self)
            pcall(self.SetBackdropBorderColor, self, C.border[1], C.border[2], C.border[3], 1)
        end)

        -- Cancel button (right)
        confirmDialog.cancelBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
        confirmDialog.cancelBtn:SetSize(100, 28)
        confirmDialog.cancelBtn:SetPoint("BOTTOMRIGHT", -40, 20)
        confirmDialog.cancelBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        confirmDialog.cancelBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        confirmDialog.cancelBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        confirmDialog.cancelBtn.text = confirmDialog.cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        confirmDialog.cancelBtn.text:SetFont(GetFontPath(), 12, "")
        confirmDialog.cancelBtn.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        confirmDialog.cancelBtn.text:SetPoint("CENTER", 0, 0)

        confirmDialog.cancelBtn:SetScript("OnEnter", function(self)
            pcall(self.SetBackdropBorderColor, self, C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        confirmDialog.cancelBtn:SetScript("OnLeave", function(self)
            pcall(self.SetBackdropBorderColor, self, C.border[1], C.border[2], C.border[3], 1)
        end)

        -- ESC to close
        confirmDialog:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                if self._onCancel then self._onCancel() end
                self:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end

    -- Configure for this call
    confirmDialog.title:SetText(options.title or "Confirm")
    confirmDialog.message:SetText(options.message or "")

    if options.warningText then
        confirmDialog.warning:SetText(options.warningText)
        confirmDialog.warning:Show()
    else
        confirmDialog.warning:Hide()
    end

    -- Accept button styling
    confirmDialog.acceptBtn.text:SetText(options.acceptText or "OK")
    if options.isDestructive then
        confirmDialog.acceptBtn.text:SetTextColor(C.warning[1], C.warning[2], C.warning[3], 1)
    else
        confirmDialog.acceptBtn.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end

    -- Cancel button
    confirmDialog.cancelBtn.text:SetText(options.cancelText or "Cancel")

    -- Store callbacks
    confirmDialog._onCancel = options.onCancel

    -- Button click handlers
    confirmDialog.acceptBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        if options.onAccept then options.onAccept() end
    end)

    confirmDialog.cancelBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        if options.onCancel then options.onCancel() end
    end)

    local anchorFrame = self.MainFrame
    confirmDialog:ClearAllPoints()
    if anchorFrame and anchorFrame ~= confirmDialog and anchorFrame.IsShown and anchorFrame:IsShown() then
        confirmDialog:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
        if anchorFrame.GetFrameLevel and confirmDialog.SetFrameLevel then
            confirmDialog:SetFrameLevel(math.max((anchorFrame:GetFrameLevel() or 0) + 20, 500))
        end
    else
        confirmDialog:SetPoint("CENTER")
        if confirmDialog.SetFrameLevel then
            confirmDialog:SetFrameLevel(500)
        end
    end

    -- Show and enable keyboard
    confirmDialog:Show()
    confirmDialog:Raise()
    confirmDialog:EnableKeyboard(true)
end

---------------------------------------------------------------------------
-- WIDGET: SECTION HEADER (Mint colored text with underline)
-- Auto-detects if first element in panel (no top margin) vs subsequent (12px margin)
---------------------------------------------------------------------------
function GUI:CreateSectionHeader(parent, text)
    -- Capture suppression state at creation time so the SetPoint hook below
    -- doesn't accidentally register this header when relayout repositions it
    -- after suppression has been lifted.
    local suppressedAtCreation = self._suppressSearchRegistration

    -- Automatically set search section so widgets created after this header
    -- are associated with this section (no need for manual SetSearchSection calls)
    -- This also registers the section as a navigation item for search
    if text and not suppressedAtCreation then
        self:SetSearchSection(text)
    end

    -- Auto-detect if this is the first element (for compact spacing at top of panels)
    local isFirstElement = (parent._hasContent == false)
    if parent._hasContent ~= nil then
        parent._hasContent = true
    end

    -- First element: no top margin (18px), others: 12px top margin (30px)
    local topMargin = isFirstElement and 0 or 12
    local containerHeight = isFirstElement and 18 or 30

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(containerHeight)

    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(header, 13, "", C.sectionHeader)
    header:SetText(text or "Section")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -topMargin)

    -- Store references and recommended gap for calling code
    container.text = header
    container.parent = parent
    container.gap = isFirstElement and 34 or 46  -- Adjusted gap for y positioning

    -- Expose SetText for convenience
    container.SetText = function(self, newText)
        header:SetText(newText)
    end

    -- Hook SetPoint to also set width and create underline after positioning
    local originalSetPoint = container.SetPoint
    container.SetPoint = function(self, point, ...)
        originalSetPoint(self, point, ...)
        -- After TOPLEFT is set, also anchor RIGHT to give container width
        if point == "TOPLEFT" then
            originalSetPoint(self, "RIGHT", parent, "RIGHT", -10, 0)
            -- Create underline now that we have positioning
            if not container.underline then
                local underline = container:CreateTexture(nil, "ARTWORK")
                underline:SetHeight(2)
                underline:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
                underline:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                underline:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
                container.underline = underline
            end

            -- Register section header for scroll-to-section navigation (after positioning)
            if not suppressedAtCreation and not GUI._suppressSearchRegistration and GUI._searchContext.tabIndex and text then
                local tabIndex = GUI._searchContext.tabIndex
                local subTabIndex = GUI._searchContext.subTabIndex or 0
                local numKey = tabIndex * 10000 + subTabIndex

                -- Find scroll parent by walking up the hierarchy
                local scrollParent = nil
                local current = parent
                while current do
                    if current.GetVerticalScroll and current.SetVerticalScroll then
                        scrollParent = current
                        break
                    end
                    current = current:GetParent()
                end

                if not GUI.SectionRegistry[numKey] then
                    GUI.SectionRegistry[numKey] = {}
                end
                if not GUI.SectionRegistryOrder[numKey] then
                    GUI.SectionRegistryOrder[numKey] = {}
                end
                if not GUI.SectionRegistry[numKey][text] then
                    table.insert(GUI.SectionRegistryOrder[numKey], text)
                end
                GUI.SectionRegistry[numKey][text] = {
                    frame = container,
                    scrollParent = scrollParent,
                    contentParent = parent,
                }
            end
        end
    end

    return container
end

-- Legacy GUI:CreateSectionBox and GUI:CreateCollapsibleSection were
-- retired in Phase 4d. Use ns.QUI_Options.CreateInlineCollapsible and
-- the V3 body helpers (CreateAccentDotLabel + CreateSettingsCardGroup)
-- in options/shared.lua instead.

-- (Old CreateCollapsibleSection implementation removed — use
-- ns.QUI_Options.CreateInlineCollapsible instead.)

---------------------------------------------------------------------------
-- WIDGET: COLOR PICKER
---------------------------------------------------------------------------
function GUI:CreateColorPicker(parent, label, dbKey, dbTable, onChange, description)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 20)
    
    -- Color swatch button (same size as checkbox: 16x16)
    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(16, 16)
    swatch:SetPoint("LEFT", 0, 0)
    local px = QUICore:GetPixelSize(swatch)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Label (same font size as checkbox: 12)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Color")
    text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    
    container.swatch = swatch
    container.label = text
    
    local function GetColor()
        if dbTable and dbKey then
            local c = dbTable[dbKey]
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        end
        return 1, 1, 1, 1
    end
    
    local function SetColor(r, g, b, a)
        swatch:SetBackdropColor(r, g, b, a or 1)
        if dbTable and dbKey then
            dbTable[dbKey] = {r, g, b, a or 1}
        end
        if onChange then onChange(r, g, b, a) end
    end
    
    -- Initialize color
    local r, g, b, a = GetColor()
    swatch:SetBackdropColor(r, g, b, a)
    
    container.GetColor = GetColor
    container.SetColor = SetColor
    
    -- Open color picker on click
    swatch:SetScript("OnClick", function()
        local r, g, b, a = GetColor()
        local originalA = a or 1
        
        local info = {
            r = r,
            g = g,
            b = b,
            opacity = originalA,
            hasOpacity = true,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            opacityFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            cancelFunc = function(prev)
                SetColor(prev.r, prev.g, prev.b, originalA)
            end,
        }
        
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    -- Hover effect
    swatch:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
    end)
    swatch:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.4, 0.4, 0.4, 1)
    end)

    GUI:AttachTooltip(swatch, description, label)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: SUB-TABS (Buttons in sticky bar, content frames in page)
---------------------------------------------------------------------------
function GUI:CreateSubTabs(parent, tabs)
    local UIKit = ns.UIKit
    local function RoundVirtual(value, frame)
        if QUICore and QUICore.PixelRound then
            return QUICore:PixelRound(value or 0, frame)
        end
        return value or 0
    end
    local function SetSnappedPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
        if QUICore and QUICore.SetSnappedPoint then
            QUICore:SetSnappedPoint(frame, point, relativeTo, relativePoint, xOffset, yOffset)
        else
            frame:SetPoint(point, relativeTo, relativePoint, xOffset or 0, yOffset or 0)
        end
    end
    local function ApplyPixelBackdrop(frame)
        if QUICore and QUICore.SetPixelPerfectBackdrop then
            QUICore:SetPixelPerfectBackdrop(frame, 1, "Interface\\Buttons\\WHITE8x8")
            return
        end
        local px = QUICore:GetPixelSize(frame)
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
    end

    -- Content container stays in the page (parent = scroll content)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 0, 0)
    container:SetPoint("TOPRIGHT", 0, 0)
    container:SetHeight(RoundVirtual(28, container))  -- Minimal height - content frames anchor below

    -- Button group goes in the sticky sub-tab bar
    local mainFrame = self.MainFrame
    local buttonGroup = CreateFrame("Frame", nil, mainFrame.subTabBar)
    buttonGroup:SetAllPoints()
    buttonGroup:Hide()  -- Hidden until this page is selected

    local tabButtons = {}
    local tabContents = {}
    local subTabDefs = {}
    local spacing = 2

    for i, tabInfo in ipairs(tabs) do
        subTabDefs[i] = {
            index = i,
            name = tabInfo.name,
            isSeparator = tabInfo.isSeparator and true or false,
        }

        -- Tab button (parented to buttonGroup in sticky bar)
        local btn = CreateFrame("Button", nil, buttonGroup, "BackdropTemplate")
        btn:SetSize(RoundVirtual(90, btn), RoundVirtual(24, btn))
        SetSnappedPoint(btn, "TOPLEFT", buttonGroup, "TOPLEFT", 10 + (i-1) * (90 + spacing), -3)
        ApplyPixelBackdrop(btn)
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        if UIKit and UIKit.RegisterScaleRefresh then
            UIKit.RegisterScaleRefresh(btn, "subTabPixelBackdrop", function(owner)
                owner:SetHeight(RoundVirtual(24, owner))
                ApplyPixelBackdrop(owner)
            end)
        end

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(btn.text, 10, "", C.text)
        btn.text:SetText(tabInfo.name)
        btn.text:SetPoint("CENTER", 0, 0)

        btn.index = i
        tabButtons[i] = btn

        -- Content frame for this tab (parented to page container)
        local content = CreateFrame("Frame", nil, container)
        content:SetPoint("TOPLEFT", 0, 0)
        content:SetPoint("BOTTOMRIGHT", 0, 0)
        content:Hide()
        content:EnableMouse(false)
        content._hasContent = false
        tabContents[i] = content

        -- Create content if builder function provided
        if tabInfo.builder then
            tabInfo.builder(content)
        end
    end

    -- Dynamic relayout function for responsive sub-tabs (wraps to multiple rows)
    local function RelayoutSubTabs()
        local barWidth = buttonGroup:GetWidth()
        if barWidth < 1 then return end

        local separatorSpacing = 15
        local btnPadding = 40  -- 10px padding on each side of text
        local availableWidth = barWidth - 20  -- 10px margin on each side
        local rowHeight = 24
        local rowGap = 2
        local topPad = 3

        -- Calculate natural (minimum) width for each button based on text
        -- Reuse tables stored on the container to avoid per-call allocations
        local naturalWidths = buttonGroup._layoutWidths
        if not naturalWidths then
            naturalWidths = {}
            buttonGroup._layoutWidths = naturalWidths
        else
            wipe(naturalWidths)
        end
        for i, btn in ipairs(tabButtons) do
            local textWidth = btn.text:GetStringWidth()
            naturalWidths[i] = math.max(textWidth + btnPadding, 50)
        end

        -- Greedy line-breaking: flow buttons left-to-right, wrap when they don't fit
        -- Reuse row tables stored on the container
        local rows = buttonGroup._layoutRows
        if not rows then
            rows = { {} }
            buttonGroup._layoutRows = rows
        else
            -- Wipe each existing inner row table, then trim excess
            for ri = 1, #rows do wipe(rows[ri]) end
        end
        local numUsedRows = 1
        local currentRowWidth = 0

        for i = 1, #tabButtons do
            local gapBefore = 0
            local curRow = rows[numUsedRows]
            if #curRow > 0 then
                gapBefore = spacing
                -- Separator spacing comes after the previous button
                local prevIdx = curRow[#curRow]
                if tabs[prevIdx] and tabs[prevIdx].isSeparator then
                    gapBefore = gapBefore + separatorSpacing
                end
            end

            local neededWidth = gapBefore + naturalWidths[i]

            if currentRowWidth + neededWidth > availableWidth and #curRow > 0 then
                -- Start a new row (reuse existing table or create)
                numUsedRows = numUsedRows + 1
                if not rows[numUsedRows] then
                    rows[numUsedRows] = {}
                end
                currentRowWidth = naturalWidths[i]
            else
                currentRowWidth = currentRowWidth + neededWidth
            end

            rows[numUsedRows][#rows[numUsedRows] + 1] = i
        end

        -- Trim excess rows from previous layouts that used more rows
        for ri = numUsedRows + 1, #rows do
            rows[ri] = nil
        end

        local numRows = #rows

        -- Layout each row: stretch buttons to fill the available width evenly
        for rowIdx, rowBtnIndices in ipairs(rows) do
            local rowSepCount = 0
            for j = 1, #rowBtnIndices - 1 do
                local btnIdx = rowBtnIndices[j]
                if tabs[btnIdx] and tabs[btnIdx].isSeparator then
                    rowSepCount = rowSepCount + 1
                end
            end

            local totalRowSpacing = math.max(0, #rowBtnIndices - 1) * spacing + rowSepCount * separatorSpacing
            local rowBtnWidth = math.floor((availableWidth - totalRowSpacing) / #rowBtnIndices)
            rowBtnWidth = math.max(rowBtnWidth, 50)
            rowBtnWidth = RoundVirtual(rowBtnWidth, buttonGroup)

            local xOffset = 10
            local yOffset = -(topPad + (rowIdx - 1) * (rowHeight + rowGap))

            for j, btnIdx in ipairs(rowBtnIndices) do
                local btn = tabButtons[btnIdx]
                btn:SetWidth(rowBtnWidth)
                btn:SetHeight(RoundVirtual(rowHeight, btn))
                btn:ClearAllPoints()
                SetSnappedPoint(btn, "TOPLEFT", buttonGroup, "TOPLEFT", xOffset, yOffset)
                xOffset = RoundVirtual(xOffset + rowBtnWidth + spacing, buttonGroup)

                if tabs[btnIdx] and tabs[btnIdx].isSeparator and j < #rowBtnIndices then
                    xOffset = RoundVirtual(xOffset + separatorSpacing, buttonGroup)
                end
            end
        end

        -- Adjust the sub-tab bar height to fit all rows
        local totalBarHeight = topPad + numRows * rowHeight + math.max(0, numRows - 1) * rowGap + 3
        if mainFrame.subTabBar then
            mainFrame.subTabBar:SetHeight(RoundVirtual(totalBarHeight, mainFrame.subTabBar))
        end
    end

    buttonGroup:SetScript("OnSizeChanged", RelayoutSubTabs)
    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(buttonGroup, "subTabLayout", function()
            RelayoutSubTabs()
        end)
    end

    -- Tab selection function
    local function SelectSubTab(index)
        for i, btn in ipairs(tabButtons) do
            if i == index then
                pcall(btn.SetBackdropColor, btn, 0.12, 0.18, 0.18, 1)
                pcall(btn.SetBackdropBorderColor, btn, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
                btn.text:SetFont(GetFontPath(), 10, "")
                btn.text:SetTextColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
                tabContents[i]:Show()
            else
                pcall(btn.SetBackdropColor, btn, 0.15, 0.15, 0.15, 1)
                pcall(btn.SetBackdropBorderColor, btn, 0.3, 0.3, 0.3, 1)
                btn.text:SetFont(GetFontPath(), 10, "")
                btn.text:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a)
                tabContents[i]:Hide()
            end
        end
        buttonGroup.selectedTab = index
        container.selectedTab = index
        if buttonGroup._onSelect then
            buttonGroup._onSelect(index, tabs[index])
        end
    end

    -- Button click handlers
    for i, btn in ipairs(tabButtons) do
        btn:SetScript("OnClick", function() SelectSubTab(i) end)
        btn:SetScript("OnEnter", function(self)
            if buttonGroup.selectedTab ~= i then
                pcall(self.SetBackdropBorderColor, self, C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if buttonGroup.selectedTab ~= i then
                pcall(self.SetBackdropBorderColor, self, 0.3, 0.3, 0.3, 1)
            end
        end)
    end

    -- Expose on both container and buttonGroup for compatibility
    buttonGroup.tabButtons = tabButtons
    buttonGroup.tabContents = tabContents
    buttonGroup.subTabDefs = subTabDefs
    buttonGroup.SelectTab = SelectSubTab
    buttonGroup.RelayoutSubTabs = RelayoutSubTabs
    container.tabButtons = tabButtons
    container.tabContents = tabContents
    container.subTabDefs = subTabDefs
    container.SelectTab = SelectSubTab
    container.RelayoutSubTabs = RelayoutSubTabs

    -- Select first tab by default
    SelectSubTab(1)

    -- Initial layout (deferred to ensure bar has width)
    C_Timer.After(0, RelayoutSubTabs)

    return container
end

---------------------------------------------------------------------------
-- WIDGET: DESCRIPTION TEXT
---------------------------------------------------------------------------
function GUI:CreateDescription(parent, text, color)
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(desc, 11, "", color or C.textMuted)
    desc:SetText(text)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    return desc
end

---------------------------------------------------------------------------
-- WIDGET: CHECKBOX
---------------------------------------------------------------------------
function GUI:CreateAccentCheckbox(parent, options)
    options = options or {}
    if not options.colors then
        options.colors = C
    end

    local UIKit = ns.UIKit
    if UIKit and UIKit.CreateAccentCheckbox then
        local widget = UIKit.CreateAccentCheckbox(parent, options)
        if widget and options.description then
            GUI:AttachTooltip(widget, options.description, options.label)
        end
        return widget
    end

    return nil
end

function GUI:CreateCheckbox(parent, label, dbKey, dbTable, onChange, description)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(300, 20)

    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    local px = QUICore:GetPixelSize(box)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Checkmark (mint-colored using standard check but tinted)
    box.check = box:CreateTexture(nil, "OVERLAY")
    box.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.check:SetPoint("CENTER", 0, 0)
    box.check:SetSize(20, 20)
    box.check:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    box.check:SetDesaturated(true)  -- Remove yellow, then apply mint
    box.check:Hide()
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)  -- Bumped from 11 to 12
    text:SetText(label or "Option")
    text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    
    container.box = box
    container.label = text
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end
    
    local function SetValue(val)
        container.checked = val
        if val then
            box.check:Show()
            box:SetBackdropBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)  -- Mint when checked
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(C_border_r, C_border_g, C_border_b, C_border_a)
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    SetValue(GetValue())
    
    box:SetScript("OnClick", function() SetValue(not GetValue()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a) end)
    box:SetScript("OnLeave", function(self)
        if GetValue() then
            pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        else
            pcall(self.SetBackdropBorderColor, self, C_border_r, C_border_g, C_border_b, C_border_a)
        end
    end)

    GUI:AttachTooltip(box, description, label)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: CHECKBOX CENTERED (label centered above checkbox)
---------------------------------------------------------------------------
function GUI:CreateCheckboxCentered(parent, label, dbKey, dbTable, onChange, description)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(100, 40)  -- Taller to fit label above
    
    -- Label on top, centered
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 11, "", C.accentLight)  -- Mint like slider labels
    text:SetText(label or "Option")
    text:SetPoint("TOP", container, "TOP", 0, 0)
    
    -- Checkbox box below label, centered
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("TOP", text, "BOTTOM", 0, -4)
    local px = QUICore:GetPixelSize(box)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Checkmark
    box.check = box:CreateTexture(nil, "OVERLAY")
    box.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.check:SetPoint("CENTER", 0, 0)
    box.check:SetSize(20, 20)
    box.check:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    box.check:SetDesaturated(true)
    box.check:Hide()
    
    container.box = box
    container.label = text
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end
    
    local function SetValue(val)
        container.checked = val
        if val then
            box.check:Show()
            box:SetBackdropBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(C_border_r, C_border_g, C_border_b, C_border_a)
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    SetValue(GetValue())
    
    box:SetScript("OnClick", function() SetValue(not GetValue()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a) end)
    box:SetScript("OnLeave", function(self)
        if GetValue() then
            pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        else
            pcall(self.SetBackdropBorderColor, self, C_border_r, C_border_g, C_border_b, C_border_a)
        end
    end)

    GUI:AttachTooltip(box, description, label)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: COLOR PICKER CENTERED (label centered above swatch)
---------------------------------------------------------------------------
function GUI:CreateColorPickerCentered(parent, label, dbKey, dbTable, onChange, description)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(100, 40)  -- Taller to fit label above
    
    -- Label on top, centered (mint like slider labels)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 11, "", C.accentLight)
    text:SetText(label or "Color")
    text:SetPoint("TOP", container, "TOP", 0, 0)
    
    -- Color swatch below label, centered
    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(16, 16)
    swatch:SetPoint("TOP", text, "BOTTOM", 0, -4)
    local px = QUICore:GetPixelSize(swatch)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    container.swatch = swatch
    container.label = text
    
    local function GetColor()
        if dbTable and dbKey then
            local c = dbTable[dbKey]
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        end
        return 1, 1, 1, 1
    end
    
    local function SetColor(r, g, b, a)
        swatch:SetBackdropColor(r, g, b, a or 1)
        if dbTable and dbKey then
            dbTable[dbKey] = {r, g, b, a or 1}
        end
        if onChange then onChange(r, g, b, a) end
    end
    
    -- Initialize color
    local r, g, b, a = GetColor()
    swatch:SetBackdropColor(r, g, b, a)
    
    container.GetColor = GetColor
    container.SetColor = SetColor
    
    -- Open color picker on click
    swatch:SetScript("OnClick", function()
        local r, g, b, a = GetColor()
        local originalA = a or 1
        local info = {
            hasOpacity = true,
            opacity = originalA,
            r = r, g = g, b = b,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            opacityFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            cancelFunc = function(prev)
                SetColor(prev.r, prev.g, prev.b, originalA)
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    swatch:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
    end)
    swatch:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.4, 0.4, 0.4, 1)
    end)

    GUI:AttachTooltip(swatch, description, label)
    return container
end

---------------------------------------------------------------------------
-- Inverted Checkbox: checked = false in DB, unchecked = true in DB
-- Use for "Hide X" options where DB stores "showX"
---------------------------------------------------------------------------
function GUI:CreateCheckboxInverted(parent, label, dbKey, dbTable, onChange, description)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(300, 20)

    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    local px = QUICore:GetPixelSize(box)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    box.check = box:CreateTexture(nil, "OVERLAY")
    box.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.check:SetPoint("CENTER", 0, 0)
    box.check:SetSize(20, 20)
    box.check:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    box.check:SetDesaturated(true)
    box.check:Hide()
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    
    container.box = box
    container.label = text
    
    -- INVERTED: DB true = unchecked, DB false = checked
    local function GetDBValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return true
    end
    
    local function IsChecked()
        return not GetDBValue()  -- Invert for display
    end
    
    local function SetChecked(checked)
        container.checked = checked
        local dbVal = not checked  -- Invert for storage
        if checked then
            box.check:Show()
            box:SetBackdropBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(C_border_r, C_border_g, C_border_b, C_border_a)
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
        if dbTable and dbKey then dbTable[dbKey] = dbVal end
        if onChange then onChange(dbVal) end
    end
    
    container.GetValue = IsChecked
    container.SetValue = SetChecked
    SetChecked(IsChecked())
    
    box:SetScript("OnClick", function() SetChecked(not IsChecked()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a) end)
    box:SetScript("OnLeave", function(self)
        if IsChecked() then
            pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        else
            pcall(self.SetBackdropBorderColor, self, C_border_r, C_border_g, C_border_b, C_border_a)
        end
    end)

    GUI:AttachTooltip(box, description, label)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: SLIDER (Full-width, stacks vertically like old GUI)
-- Layout: Label centered on top, slider bar below, min|editbox|max at bottom
-- Options table (optional 8th param): { deferOnDrag = true } to defer onChange until mouse release
---------------------------------------------------------------------------
function GUI:CreateSlider(parent, label, min, max, step, dbKey, dbTable, onChange, options)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(60)
    container:EnableMouse(true)  -- Block clicks from passing through to frames behind
    -- Width will be set by anchoring TOPLEFT and TOPRIGHT

    -- Parse options
    options = options or {}
    local deferOnDrag = options.deferOnDrag or false

    -- Label (top, centered, mint colored)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 11, "", C.accentLight)
    text:SetText(label or "Setting")
    text:SetPoint("TOP", 0, 0)

    -- Track container (for the filled + unfilled portions)
    local trackContainer = CreateFrame("Frame", nil, container)
    trackContainer:SetHeight(6)  -- Premium thinner track
    trackContainer:SetPoint("TOPLEFT", 35, -18)
    trackContainer:SetPoint("TOPRIGHT", -35, -18)

    -- Unfilled track (background)
    local trackBg = CreateFrame("Frame", nil, trackContainer, "BackdropTemplate")
    trackBg:SetAllPoints()
    local px = QUICore:GetPixelSize(trackBg)
    trackBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    trackBg:SetBackdropColor(C.sliderTrack[1], C.sliderTrack[2], C.sliderTrack[3], 1)
    trackBg:SetBackdropBorderColor(0.1, 0.12, 0.15, 1)

    -- Filled track (mint portion from left to thumb)
    local trackFill = CreateFrame("Frame", nil, trackContainer, "BackdropTemplate")
    trackFill:SetPoint("TOPLEFT", px, -px)
    trackFill:SetPoint("BOTTOMLEFT", px, px)
    trackFill:SetWidth(1)
    trackFill:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    trackFill:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Actual slider (invisible, just for interaction)
    local slider = CreateFrame("Slider", nil, trackContainer)
    slider:SetAllPoints()
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)
    slider:SetHitRectInsets(0, 0, -10, -10)  -- Expand hit area 10px above/below for reliable hover detection

    -- Thumb frame (white circle with border)
    local thumbFrame = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrame:SetSize(14, 14)
    thumbFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    thumbFrame:SetBackdropColor(C.sliderThumb[1], C.sliderThumb[2], C.sliderThumb[3], 1)
    thumbFrame:SetBackdropBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
    thumbFrame:SetFrameLevel(slider:GetFrameLevel() + 2)
    thumbFrame:EnableMouse(false)  -- Let clicks pass through to slider

    -- Hidden thumb texture for slider mechanics
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(14, 14)
    thumb:SetAlpha(0)

    -- Min label (left of slider)
    local minText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(minText, 10, "", C.textMuted)
    minText:SetText(tostring(min or 0))
    minText:SetPoint("RIGHT", trackContainer, "LEFT", -5, 0)

    -- Max label (right of slider)
    local maxText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(maxText, 10, "", C.textMuted)
    maxText:SetText(tostring(max or 100))
    maxText:SetPoint("LEFT", trackContainer, "RIGHT", 5, 0)

    -- Editbox for value (center, below slider)
    local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editBox:SetSize(70, 22)
    editBox:SetPoint("TOP", trackContainer, "BOTTOM", 0, -6)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    editBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
    editBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    editBox:SetFont(GetFontPath(), 11, "")
    editBox:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a)
    editBox:SetJustifyH("CENTER")
    editBox:SetAutoFocus(false)

    -- Configure slider
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    container.slider = slider
    container.editBox = editBox
    container.trackFill = trackFill
    container.thumbFrame = thumbFrame
    container.trackContainer = trackContainer
    container.min = min or 0
    container.max = max or 100
    container.step = step or 1

    -- Track dragging state for deferOnDrag mode
    local isDragging = false

    -- Update filled track and thumb position
    local function UpdateTrackFill(value)
        local minVal, maxVal = container.min, container.max
        local pct = (value - minVal) / (maxVal - minVal)
        pct = math.max(0, math.min(1, pct))

        local trackWidth = trackContainer:GetWidth() - 2
        local fillWidth = math.max(1, pct * trackWidth)
        trackFill:SetWidth(fillWidth)

        local thumbX = pct * (trackWidth - 14) + 7
        thumbFrame:ClearAllPoints()
        thumbFrame:SetPoint("CENTER", trackContainer, "LEFT", thumbX + 1, 0)
    end

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] or container.min end
        return container.value or container.min
    end

    local function FormatVal(val)
        if container.step >= 1 then
            return tostring(math.floor(val))
        else
            return string.format("%.2f", val)
        end
    end

    local function SetValue(val, skipCallback)
        val = math.max(container.min, math.min(container.max, val))
        if container.step >= 1 then
            val = math.floor(val / container.step + 0.5) * container.step
        else
            local mult = 1 / container.step
            val = math.floor(val * mult + 0.5) / mult
        end

        container.value = val
        slider:SetValue(val)
        editBox:SetText(FormatVal(val))
        UpdateTrackFill(val)

        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange and not skipCallback then onChange(val) end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)

    -- Slider drag callback
    slider:SetScript("OnValueChanged", function(self, value)
        if container.step >= 1 then
            value = math.floor(value / container.step + 0.5) * container.step
        else
            local mult = 1 / container.step
            value = math.floor(value * mult + 0.5) / mult
        end
        editBox:SetText(FormatVal(value))
        container.value = value
        UpdateTrackFill(value)
        if dbTable and dbKey then dbTable[dbKey] = value end

        -- If deferOnDrag, only call onChange when not dragging (or on release)
        if deferOnDrag then
            if not isDragging then
                if onChange then onChange(value) end
            end
        else
            if onChange then onChange(value) end
        end
    end)

    -- Track mouse down/up for deferOnDrag mode
    slider:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
        end
    end)

    slider:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and isDragging then
            isDragging = false
            if deferOnDrag and onChange then
                local value = self:GetValue()
                if container.step >= 1 then
                    value = math.floor(value / container.step + 0.5) * container.step
                else
                    local mult = 1 / container.step
                    value = math.floor(value * mult + 0.5) / mult
                end
                onChange(value)
            end
        end
    end)

    -- Hover effects
    slider:SetScript("OnEnter", function()
        thumbFrame:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    slider:SetScript("OnLeave", function()
        thumbFrame:SetBackdropBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then SetValue(val) end
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        editBox:SetText(FormatVal(GetValue()))
        self:ClearFocus()
    end)

    -- Hover effect on editbox
    editBox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end)
    editBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        end
    end)

    -- Initialize after a brief delay to ensure width is calculated
    C_Timer.After(0, function()
        SetValue(GetValue(), true)
    end)

    GUI:AttachTooltip(slider, options.description, label)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: DROPDOWN (Matches slider width with same 35px inset, same height for alignment)
---------------------------------------------------------------------------
local CHEVRON_ZONE_WIDTH = 28
local CHEVRON_BG_ALPHA = 0.15
local CHEVRON_BG_ALPHA_HOVER = 0.25
local CHEVRON_TEXT_ALPHA = 0.7

---------------------------------------------------------------------------
-- DROPDOWN SHARED: Position menu above or below dropdown based on screen space,
-- add scroll frame + scrollbar when content exceeds max visible height.
---------------------------------------------------------------------------
local DROPDOWN_MAX_VISIBLE_ITEMS = 10
local DROPDOWN_ITEM_HEIGHT = 22
local DROPDOWN_SCROLLBAR_WIDTH = 6

-- Position the menu frame above or below the dropdown button.
-- Uses GetCursorPosition() as a reliable screen-space reference (the cursor
-- is always on the dropdown button when clicked). Compares cursor Y against
-- screen height to decide whether to open up or down.
local function PositionDropdownMenu(menuFrame, dropdown, menuHeight)
    menuFrame:ClearAllPoints()
    local uiScale = UIParent:GetEffectiveScale()
    -- GetCursorPosition returns raw screen pixels; divide by UIParent scale
    -- to get UIParent-space coordinates (which menuFrame uses as its parent).
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / uiScale
    -- Check against the QUI options panel bottom, not the screen bottom,
    -- since the menu is parented to UIParent but should stay within the panel.
    local panelBottom = 0
    if GUI.MainFrame and GUI.MainFrame:IsShown() then
        local pb = GUI.MainFrame:GetBottom()
        if pb then
            local panelScale = GUI.MainFrame:GetEffectiveScale()
            panelBottom = pb * panelScale / uiScale
        end
    end
    -- Open upward if the menu would extend below the options panel
    if cursorY - menuHeight < panelBottom + 10 then
        menuFrame:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
        menuFrame:SetPoint("BOTTOMRIGHT", dropdown, "TOPRIGHT", 0, 2)
    else
        menuFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        menuFrame:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
    end
end

-- Create a scrollable menu body inside a menuFrame.
-- Returns scrollFrame, scrollContent, scrollBar (thumb-only, styled), UpdateThumb.
-- Uses a custom mouse-wheel handler that also updates the scrollbar thumb,
-- since bare ScrollFrames don't fire OnVerticalScroll/OnScrollRangeChanged reliably.
local function CreateDropdownScrollBody(menuFrame)
    local scrollFrame = CreateFrame("ScrollFrame", nil, menuFrame)
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(200)
    scrollFrame:SetScrollChild(scrollContent)

    -- Minimal styled scrollbar (thin thumb, no arrows)
    local scrollBar = CreateFrame("Frame", nil, menuFrame)
    scrollBar:SetWidth(DROPDOWN_SCROLLBAR_WIDTH)
    scrollBar:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", menuFrame, "BOTTOMRIGHT", -1, 2)
    scrollBar:Hide()

    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(DROPDOWN_SCROLLBAR_WIDTH)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
    scrollBar.thumb = thumb

    -- Update thumb position/size based on current scroll state
    local function UpdateThumb()
        local contentH = scrollContent:GetHeight()
        local frameH = scrollFrame:GetHeight()
        if contentH <= frameH or frameH <= 0 then
            scrollBar:Hide()
            return
        end
        scrollBar:Show()
        local trackH = scrollBar:GetHeight()
        if trackH <= 0 then return end
        local thumbH = math.max(20, (frameH / contentH) * trackH)
        thumb:SetHeight(thumbH)
        local scrollMax = contentH - frameH
        local okScroll, scrollCur = pcall(scrollFrame.GetVerticalScroll, scrollFrame)
        scrollCur = (okScroll and scrollCur) or 0
        local ratio = (scrollMax > 0) and (scrollCur / scrollMax) or 0
        local yOff = -ratio * (trackH - thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollBar, "TOP", 0, yOff)
    end

    -- Custom mouse wheel handler that scrolls AND updates thumb
    local SCROLL_STEP = 22  -- one item per scroll tick
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local okCur, currentScroll = pcall(self.GetVerticalScroll, self)
        if not okCur then return end
        local contentH = scrollContent:GetHeight()
        local frameH = self:GetHeight()
        local maxScroll = math.max(0, contentH - frameH)
        local newScroll = math.max(0, math.min(currentScroll - (delta * SCROLL_STEP), maxScroll))
        pcall(self.SetVerticalScroll, self, newScroll)
        UpdateThumb()
    end)

    -- Also try to catch scroll range changes (works on some WoW versions)
    scrollFrame:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    return scrollFrame, scrollContent, scrollBar, UpdateThumb
end

function GUI:CreateDropdown(parent, label, options, dbKey, dbTable, onChange, description)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(60)  -- Match slider height for vertical alignment
    container:SetWidth(200)  -- Default width, can be overridden by SetWidth()

    -- Label on top (if provided) - mint green like slider labels, centered
    if label and label ~= "" then
        local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 11, "", C.accentLight)  -- Mint green like other labels
        text:SetText(label)
        text:SetPoint("TOP", container, "TOP", 0, 0)  -- Centered
    end

    -- Dropdown button (same width as slider track - inset 35px on each side) — V3 widget surface
    local UIKit = ns.UIKit
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines
    local dropdown = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    dropdown:SetHeight(22)
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 35, -16)
    dropdown:SetPoint("RIGHT", container, "RIGHT", -35, 0)
    local px = QUICore:GetPixelSize(dropdown)
    if useUIKitBorders then
        dropdown.bg = UIKit.CreateBackground(dropdown, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        UIKit.CreateBorderLines(dropdown)
        UIKit.UpdateBorderLines(dropdown, 1, 1, 1, 1, 0.2, false)
    else
        dropdown:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        dropdown:SetBackdropColor(C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        dropdown:SetBackdropBorderColor(1, 1, 1, 0.2)
    end

    local function SetDropdownBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(dropdown, 1, r, g, b, a or 1, false)
        else
            pcall(dropdown.SetBackdropBorderColor, dropdown, r, g, b, a or 1)
        end
    end

    local chevron = UIKit.CreateChevronCaret(dropdown, {
        point = "RIGHT", relativeTo = dropdown, relativePoint = "RIGHT",
        xPixels = -8, sizePixels = 10, lineWidthPixels = 6,
        r = C.textMuted[1], g = C.textMuted[2], b = C.textMuted[3], a = 1,
        expanded = true,
    })
    dropdown.chevron = chevron

    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 10, "", C.text)
    dropdown.selected:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    dropdown.selected:SetPoint("RIGHT", chevron, "LEFT", -4, 0)
    dropdown.selected:SetJustifyH("LEFT")

    -- Hover effect: border brightens
    dropdown:SetScript("OnEnter", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.35)
    end)
    dropdown:SetScript("OnLeave", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.2)
    end)

    container.dropdown = dropdown
    
    -- Normalize options to {value, text} format
    local normalizedOptions = {}
    if type(options) == "table" then
        for i, opt in ipairs(options) do
            if type(opt) == "table" then
                normalizedOptions[i] = opt
            else
                -- Simple string array like {"Up", "Down"}
                normalizedOptions[i] = {value = opt:lower(), text = opt}
            end
        end
    end
    container.options = normalizedOptions
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.value
    end
    
    local function GetDisplayText(val)
        for _, opt in ipairs(container.options) do
            if opt.value == val then return opt.text end
        end
        -- If not found, capitalize first letter
        if type(val) == "string" then
            return val:sub(1,1):upper() .. val:sub(2)
        end
        return tostring(val or "Select...")
    end
    
    local function SetValue(val, skipCallback)
        container.value = val
        dropdown.selected:SetText(GetDisplayText(val))
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange and not skipCallback then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    
    -- Initialize with current value
    SetValue(GetValue(), true)
    
    -- Dropdown menu frame (parented to UIParent to avoid scroll frame clipping) — V3 surface
    local menuFrame = CreateFrame("Frame", nil, UIParent, useUIKitBorders and nil or "BackdropTemplate")
    if useUIKitBorders then
        menuFrame.bg = UIKit.CreateBackground(menuFrame, C.bg[1], C.bg[2], C.bg[3], 1)
        UIKit.CreateBorderLines(menuFrame)
        UIKit.UpdateBorderLines(menuFrame, 1, 1, 1, 1, 0.2, false)
    else
        menuFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        menuFrame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
        menuFrame:SetBackdropBorderColor(1, 1, 1, 0.2)
    end
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:SetClipsChildren(true)
    menuFrame:Hide()

    -- Hide menu when dropdown becomes hidden (tab switch, panel close, etc.)
    dropdown:HookScript("OnHide", function() menuFrame:Hide() end)

    -- Scroll body for long option lists
    local scrollFrame, scrollContent, scrollBar, updateThumb = CreateDropdownScrollBody(menuFrame)

    local menuButtons = {}
    local buttonHeight = DROPDOWN_ITEM_HEIGHT

    local function RefreshMenuSelection()
        for i, opt in ipairs(container.options) do
            local row = menuButtons[i]
            if row then
                if opt.value == container.value then
                    row._selectedBg:Show()
                    row._selectedBar:Show()
                    row.text:SetTextColor(C_accent_r, C_accent_g, C_accent_b, 1)
                else
                    row._selectedBg:Hide()
                    row._selectedBar:Hide()
                    row.text:SetTextColor(C_text_r, C_text_g, C_text_b, 1)
                end
            end
        end
    end
    container.RefreshMenuSelection = RefreshMenuSelection

    for i, opt in ipairs(container.options) do
        local btn = CreateFrame("Button", nil, scrollContent)
        btn:SetHeight(buttonHeight)
        btn:SetPoint("TOPLEFT", 2, -2 - (i-1) * buttonHeight)
        btn:SetPoint("TOPRIGHT", -2, -2 - (i-1) * buttonHeight)

        btn._selectedBg = btn:CreateTexture(nil, "BACKGROUND")
        btn._selectedBg:SetAllPoints(btn)
        btn._selectedBg:SetColorTexture(0.204, 0.827, 0.6, 0.04)
        btn._selectedBg:Hide()

        btn._hoverBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        btn._hoverBg:SetAllPoints(btn)
        btn._hoverBg:SetColorTexture(0.204, 0.827, 0.6, 0.08)
        btn._hoverBg:Hide()

        btn._selectedBar = btn:CreateTexture(nil, "OVERLAY")
        btn._selectedBar:SetWidth(2)
        btn._selectedBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn._selectedBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        btn._selectedBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        btn._selectedBar:Hide()

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(btn.text, 10, "", C.text)
        btn.text:SetText(opt.text)
        btn.text:SetPoint("LEFT", 8, 0)

        btn:SetScript("OnEnter", function(self)
            self._hoverBg:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self._hoverBg:Hide()
        end)
        btn:SetScript("OnClick", function()
            SetValue(opt.value)
            menuFrame:Hide()
        end)

        menuButtons[i] = btn
    end

    local totalHeight = 4 + #container.options * buttonHeight
    local maxHeight = 4 + DROPDOWN_MAX_VISIBLE_ITEMS * buttonHeight
    scrollContent:SetHeight(totalHeight)
    menuFrame:SetHeight(math.min(totalHeight, maxHeight))

    -- Adjust scroll content right edge when scrollbar is visible
    local function UpdateScrollInset()
        if scrollBar:IsShown() then
            scrollFrame:SetPoint("BOTTOMRIGHT", -(DROPDOWN_SCROLLBAR_WIDTH + 2), 0)
        else
            scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end

    -- Toggle menu on click
    dropdown:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide()
        else
            RefreshMenuSelection()
            PositionDropdownMenu(menuFrame, dropdown, menuFrame:GetHeight())
            scrollContent:SetWidth(dropdown:GetWidth() - 4)
            menuFrame:Show()
            C_Timer.After(0, function() updateThumb(); UpdateScrollInset() end)
        end
    end)

    -- Close menu when clicking elsewhere (with delay to handle gap)
    local closeTimer = 0
    local CLOSE_DELAY = 0.15  -- 150ms grace period

    menuFrame:HookScript("OnShow", function()
        closeTimer = 0
        menuFrame.__checkElapsed = 0
        menuFrame:SetScript("OnUpdate", function(self, elapsed)
            self.__checkElapsed = (self.__checkElapsed or 0) + elapsed
            if self.__checkElapsed < 0.066 then return end
            local deltaTime = self.__checkElapsed
            self.__checkElapsed = 0

            local isOverDropdown = dropdown:IsMouseOver()
            local isOverMenu = self:IsMouseOver()

            if not isOverDropdown and not isOverMenu then
                closeTimer = closeTimer + deltaTime
                if closeTimer > CLOSE_DELAY then
                    self:Hide()
                end
            else
                closeTimer = 0
            end
        end)
    end)

    menuFrame:HookScript("OnHide", function()
        menuFrame:SetScript("OnUpdate", nil)
        closeTimer = 0
    end)

    GUI:AttachTooltip(dropdown, description, label)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: DROPDOWN FULL WIDTH (For pages like Spec Profiles - no inset)
---------------------------------------------------------------------------
function GUI:CreateDropdownFullWidth(parent, label, options, dbKey, dbTable, onChange, description)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(45)  -- Compact height for full-width dropdowns
    container:SetWidth(200)  -- Default width, can be overridden by SetWidth()

    -- Label on top (if provided) - mint green, centered
    if label and label ~= "" then
        local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 11, "", C.accentLight)
        text:SetText(label)
        text:SetPoint("TOP", container, "TOP", 0, 0)
    end

    -- Dropdown button (full width, no inset) — V3 widget surface
    local UIKit = ns.UIKit
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines
    local dropdown = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    dropdown:SetHeight(22)
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -18)
    dropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    local px = QUICore:GetPixelSize(dropdown)
    if useUIKitBorders then
        dropdown.bg = UIKit.CreateBackground(dropdown, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        UIKit.CreateBorderLines(dropdown)
        UIKit.UpdateBorderLines(dropdown, 1, 1, 1, 1, 0.2, false)
    else
        dropdown:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        dropdown:SetBackdropColor(C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        dropdown:SetBackdropBorderColor(1, 1, 1, 0.2)
    end

    local function SetDropdownBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(dropdown, 1, r, g, b, a or 1, false)
        else
            pcall(dropdown.SetBackdropBorderColor, dropdown, r, g, b, a or 1)
        end
    end

    -- Chevron glyph on right edge
    local chevron = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(chevron, 10, "", C.textMuted)
    chevron:SetText("\226\150\190")  -- ▾
    chevron:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
    dropdown.chevron = chevron

    -- Selected text label
    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 10, "", C.text)
    dropdown.selected:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    dropdown.selected:SetPoint("RIGHT", chevron, "LEFT", -4, 0)
    dropdown.selected:SetJustifyH("LEFT")

    -- Hover effect: border brightens
    dropdown:SetScript("OnEnter", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.35)
    end)
    dropdown:SetScript("OnLeave", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.2)
    end)

    container.dropdown = dropdown

    -- Normalize options
    local normalizedOptions = {}
    if type(options) == "table" then
        for i, opt in ipairs(options) do
            if type(opt) == "table" then
                normalizedOptions[i] = opt
            else
                normalizedOptions[i] = {value = opt:lower(), text = opt}
            end
        end
    end
    container.options = normalizedOptions
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.value
    end
    
    local function GetDisplayText(val)
        for _, opt in ipairs(container.options) do
            if opt.value == val then return opt.text end
        end
        if type(val) == "string" then
            return val:sub(1,1):upper() .. val:sub(2)
        end
        return tostring(val or "Select...")
    end
    
    local function SetValue(val, skipCallback)
        container.value = val
        dropdown.selected:SetText(GetDisplayText(val))
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange and not skipCallback then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    SetValue(GetValue(), true)
    
    -- Dropdown menu (parented to UIParent to avoid scroll frame clipping)
    local menuFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menuFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    menuFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    menuFrame:SetBackdropBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:SetClipsChildren(true)
    menuFrame:Hide()

    -- Hide menu when dropdown becomes hidden (tab switch, panel close, etc.)
    dropdown:HookScript("OnHide", function() menuFrame:Hide() end)

    -- Scroll body for long option lists
    local scrollFrame, scrollContent, scrollBar, updateThumb = CreateDropdownScrollBody(menuFrame)

    local buttonHeight = DROPDOWN_ITEM_HEIGHT
    for i, opt in ipairs(container.options) do
        local btn = CreateFrame("Button", nil, scrollContent, "BackdropTemplate")
        btn:SetHeight(buttonHeight)
        btn:SetPoint("TOPLEFT", 2, -2 - (i-1) * buttonHeight)
        btn:SetPoint("TOPRIGHT", -2, -2 - (i-1) * buttonHeight)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(btn.text, 11, "", C.text)
        btn.text:SetText(opt.text)
        btn.text:SetPoint("LEFT", 8, 0)

        btn:SetScript("OnEnter", function(self)
            pcall(function()
                self:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
            end)
        end)
        btn:SetScript("OnLeave", function(self)
            pcall(function() self:SetBackdrop(nil) end)
        end)
        btn:SetScript("OnClick", function()
            SetValue(opt.value)
            menuFrame:Hide()
        end)
    end

    local totalHeight = 4 + #container.options * buttonHeight
    local maxHeight = 4 + DROPDOWN_MAX_VISIBLE_ITEMS * buttonHeight
    scrollContent:SetHeight(totalHeight)
    menuFrame:SetHeight(math.min(totalHeight, maxHeight))

    local function UpdateScrollInset()
        if scrollBar:IsShown() then
            scrollFrame:SetPoint("BOTTOMRIGHT", -(DROPDOWN_SCROLLBAR_WIDTH + 2), 0)
        else
            scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end

    dropdown:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide()
        else
            PositionDropdownMenu(menuFrame, dropdown, menuFrame:GetHeight())
            scrollContent:SetWidth(dropdown:GetWidth() - 4)
            menuFrame:Show()
            C_Timer.After(0, function() updateThumb(); UpdateScrollInset() end)
        end
    end)

    -- Close menu when clicking elsewhere
    local closeTimer = 0
    menuFrame:HookScript("OnShow", function()
        closeTimer = 0
        menuFrame.__checkElapsed = 0
        menuFrame:SetScript("OnUpdate", function(self, elapsed)
            self.__checkElapsed = (self.__checkElapsed or 0) + elapsed
            if self.__checkElapsed < 0.066 then return end
            local deltaTime = self.__checkElapsed
            self.__checkElapsed = 0

            local isOverDropdown = dropdown:IsMouseOver()
            local isOverMenu = self:IsMouseOver()
            if not isOverDropdown and not isOverMenu then
                closeTimer = closeTimer + deltaTime
                if closeTimer > 0.15 then
                    self:Hide()
                end
            else
                closeTimer = 0
            end
        end)
    end)

    menuFrame:HookScript("OnHide", function()
        menuFrame:SetScript("OnUpdate", nil)
        closeTimer = 0
    end)

    GUI:AttachTooltip(dropdown, description, label)
    return container
end

---------------------------------------------------------------------------
-- FORM WIDGETS (Label on left, widget on right)
---------------------------------------------------------------------------

local FORM_ROW_HEIGHT = 28

---------------------------------------------------------------------------
-- WIDGET: TOGGLE SWITCH (V3)
-- Track: 26x14 pill. Knob: 10x10, 2px inset.
-- OFF: C.toggleOff track, knob anchored LEFT +2.
-- ON:  C.accent track, knob anchored RIGHT -2.
---------------------------------------------------------------------------
function GUI:CreateFormToggle(parent, label, dbKey, dbTable, onChange, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label  -- For search jump-to-setting (V2)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    -- Bare mode: when label is nil, skip the built-in label FontString and
    -- shrink container to just the toggle control. Used by V3 BuildSettingRow
    -- which provides its own label + cell-level layout.
    local text
    local toggleLeftOffset = 180  -- default for labeled widget
    if label then
        container:SetHeight(FORM_ROW_HEIGHT)
        -- Label on left (off-white text, constrained to not overlap toggle)
        text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 12, "", C.text)
        text:SetText(label)
        text:SetPoint("LEFT", 0, 0)
        text:SetWidth(170)
        text:SetWordWrap(true)
        text:SetNonSpaceWrap(true)
        text:SetJustifyH("LEFT")
    else
        container:SetSize(26, 14)
        toggleLeftOffset = 0
    end

    local toggle = CreateFrame("Button", nil, container)
    toggle:SetSize(26, 14)
    toggle:SetPoint("LEFT", container, "LEFT", toggleLeftOffset, 0)

    local track = toggle:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints(toggle)
    track:SetColorTexture(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], C.toggleOff[4])
    toggle.track = track

    local trackMask = toggle:CreateMaskTexture()
    trackMask:SetTexture(ns.Helpers.AssetPath .. "pill_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    trackMask:SetAllPoints(track)
    track:AddMaskTexture(trackMask)
    toggle._trackMask = trackMask

    local knob = toggle:CreateTexture(nil, "OVERLAY")
    knob:SetSize(10, 10)
    knob:SetColorTexture(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], C.toggleThumb[4])
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", toggle, "LEFT", 2, 0)
    toggle.knob = knob

    -- Knob mask (circular at 10x10)
    local knobMask = toggle:CreateMaskTexture()
    knobMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    knobMask:SetAllPoints(knob)
    knob:AddMaskTexture(knobMask)
    toggle._knobMask = knobMask

    container.track = toggle
    container.thumb = toggle
    container.label = text

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end

    local isHovered = false

    local function SetToggleVisual(t, isOn)
        local hoverBoost = isHovered and 0.06 or 0
        if isOn then
            t.track:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], math.min(1, C.accent[4] + hoverBoost))
            t.knob:ClearAllPoints()
            t.knob:SetPoint("RIGHT", t, "RIGHT", -2, 0)
        else
            t.track:SetColorTexture(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], math.min(1, C.toggleOff[4] + hoverBoost))
            t.knob:ClearAllPoints()
            t.knob:SetPoint("LEFT", t, "LEFT", 2, 0)
        end
        if t._knobMask then t._knobMask:SetAllPoints(t.knob) end
    end

    local function UpdateVisual(val)
        SetToggleVisual(toggle, val and true or false)
    end

    local function SetValue(val, skipCallback)
        container.checked = val
        UpdateVisual(val)
        if dbTable and dbKey then dbTable[dbKey] = val end
        if not skipCallback then
            MaybeUpdatePinnedWidgetValue(container, val)
        end
        BroadcastToSiblings(container, val)
        if onChange and not skipCallback then onChange(val) end
        if not skipCallback then
            MaybeAutoNotifyProviderSync(container)
        end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "checkbox", label, dbKey, dbTable, toggle, registryInfo)

    SetValue(GetValue(), true)  -- Skip callback on init

    if ns.UIKit and ns.UIKit.RegisterScaleRefresh then
        ns.UIKit.RegisterScaleRefresh(toggle, "formToggleScale", function()
            toggle:SetSize(26, 14)
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", container, "LEFT", toggleLeftOffset, 0)
            knob:SetSize(10, 10)
            UpdateVisual(GetValue())
        end)
    end

    toggle:SetScript("OnClick", function() SetValue(not GetValue()) end)

    toggle:SetScript("OnEnter", function()
        isHovered = true
        SetToggleVisual(toggle, GetValue() and true or false)
    end)
    toggle:SetScript("OnLeave", function()
        isHovered = false
        SetToggleVisual(toggle, GetValue() and true or false)
    end)

    -- Enable/disable the toggle (for conditional UI)
    container.SetEnabled = function(self, enabled)
        toggle:EnableMouse(enabled)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    GUI:RegisterSearchSettingWidget({
        label = label,
        widgetType = "toggle",
        widgetBuilder = function(p)
            return GUI:CreateFormToggle(p, label, dbKey, dbTable, onChange)
        end,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor("toggle", dbKey, dbTable),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    })

    GUI:AttachTooltip(toggle, registryInfo and registryInfo.description or nil, label)
    return container
end

-- Inverted toggle: checked = DB false, unchecked = DB true (for "Hide X" options)
function GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    container._widgetLabel = label
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    -- Label on left (off-white text, constrained to not overlap toggle)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(170)
    text:SetWordWrap(true)
    text:SetNonSpaceWrap(true)
    text:SetJustifyH("LEFT")

    local toggle = CreateFrame("Button", nil, container)
    toggle:SetSize(26, 14)
    toggle:SetPoint("LEFT", container, "LEFT", 180, 0)

    local track = toggle:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints(toggle)
    track:SetColorTexture(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], C.toggleOff[4])
    toggle.track = track

    local trackMask = toggle:CreateMaskTexture()
    trackMask:SetTexture(ns.Helpers.AssetPath .. "pill_mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    trackMask:SetAllPoints(track)
    track:AddMaskTexture(trackMask)
    toggle._trackMask = trackMask

    local knob = toggle:CreateTexture(nil, "OVERLAY")
    knob:SetSize(10, 10)
    knob:SetColorTexture(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], C.toggleThumb[4])
    knob:ClearAllPoints()
    knob:SetPoint("LEFT", toggle, "LEFT", 2, 0)
    toggle.knob = knob

    -- Knob mask (circular at 10x10)
    local knobMask = toggle:CreateMaskTexture()
    knobMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    knobMask:SetAllPoints(knob)
    knob:AddMaskTexture(knobMask)
    toggle._knobMask = knobMask

    container.track = toggle
    container.thumb = toggle
    container.label = text

    -- INVERTED: DB true = toggle OFF, DB false = toggle ON
    local function GetDBValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return true
    end

    local function IsOn()
        return not GetDBValue()  -- Invert for display
    end

    local isHovered = false

    local function SetToggleVisual(t, isOn)
        local hoverBoost = isHovered and 0.06 or 0
        if isOn then
            t.track:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], math.min(1, C.accent[4] + hoverBoost))
            t.knob:ClearAllPoints()
            t.knob:SetPoint("RIGHT", t, "RIGHT", -2, 0)
        else
            t.track:SetColorTexture(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], math.min(1, C.toggleOff[4] + hoverBoost))
            t.knob:ClearAllPoints()
            t.knob:SetPoint("LEFT", t, "LEFT", 2, 0)
        end
        if t._knobMask then t._knobMask:SetAllPoints(t.knob) end
    end

    local function UpdateVisual(isOn)
        SetToggleVisual(toggle, isOn and true or false)
    end

    local function SetOn(isOn, skipCallback)
        container.checked = isOn
        local dbVal = not isOn  -- Invert for storage
        UpdateVisual(isOn)
        if dbTable and dbKey then dbTable[dbKey] = dbVal end
        if not skipCallback then
            MaybeUpdatePinnedWidgetValue(container, dbVal)
        end
        BroadcastToSiblings(container, isOn)
        if onChange and not skipCallback then onChange(dbVal) end
        if not skipCallback then
            MaybeAutoNotifyProviderSync(container)
        end
    end

    container.GetValue = IsOn
    container.SetValue = SetOn
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "checkbox", label, dbKey, dbTable, toggle, registryInfo)

    SetOn(IsOn(), true)  -- Skip callback on init

    if ns.UIKit and ns.UIKit.RegisterScaleRefresh then
        ns.UIKit.RegisterScaleRefresh(toggle, "formToggleInvertedScale", function()
            toggle:SetSize(26, 14)
            toggle:ClearAllPoints()
            toggle:SetPoint("LEFT", container, "LEFT", 180, 0)
            knob:SetSize(10, 10)
            UpdateVisual(IsOn())
        end)
    end

    toggle:SetScript("OnClick", function() SetOn(not IsOn()) end)

    toggle:SetScript("OnEnter", function()
        isHovered = true
        SetToggleVisual(toggle, IsOn() and true or false)
    end)
    toggle:SetScript("OnLeave", function()
        isHovered = false
        SetToggleVisual(toggle, IsOn() and true or false)
    end)

    -- Enable/disable the toggle (for conditional UI)
    container.SetEnabled = function(self, enabled)
        toggle:EnableMouse(enabled)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    GUI:RegisterSearchSettingWidget({
        label = label,
        widgetType = "toggle",
        widgetBuilder = function(p)
            return GUI:CreateFormToggleInverted(p, label, dbKey, dbTable, onChange, registryInfo)
        end,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor("toggle_inverted", dbKey, dbTable),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    })

    GUI:AttachTooltip(toggle, registryInfo and registryInfo.description or nil, label)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: FORM CHECKBOX (Now uses Toggle Switch style!)
---------------------------------------------------------------------------
function GUI:CreateFormCheckbox(parent, label, dbKey, dbTable, onChange, registryInfo)
    -- Redirect to toggle for the premium look
    return GUI:CreateFormToggle(parent, label, dbKey, dbTable, onChange, registryInfo)
end

-- Keep original checkbox available for multi-select scenarios
function GUI:CreateFormCheckboxOriginal(parent, label, dbKey, dbTable, onChange, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    -- Label on left (off-white text, constrained to not overlap checkbox)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(170)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")

    -- Checkbox aligned with other widgets (starts at 180px from left)
    -- V3 accent checkbox primitive owns visuals (14x14, accent fill + ✓ glyph + hover).
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end

    local SetValue  -- forward declaration; referenced by the primitive's onChange

    local box = UIKit.CreateAccentCheckbox(container, {
        checked = GetValue() and true or false,
        onChange = function(val)
            -- User click path: primitive already flipped its visual state; we forward
            -- through SetValue semantics (DB write, broadcast, provider sync) but skip
            -- the redundant primitive SetChecked (SetValue is called with skipVisual=true).
            if SetValue then SetValue(val, false, true) end
        end,
    })
    box:ClearAllPoints()
    box:SetPoint("LEFT", container, "LEFT", 180, 0)

    container.box = box
    container.label = text

    local function UpdateVisual(val)
        box:SetChecked(val and true or false, true)  -- skipOnChange so we don't re-enter SetValue
    end

    SetValue = function(val, skipCallback, skipVisual)
        container.checked = val
        if not skipVisual then
            UpdateVisual(val)
        end
        if dbTable and dbKey then dbTable[dbKey] = val end
        if not skipCallback then
            MaybeUpdatePinnedWidgetValue(container, val)
        end
        BroadcastToSiblings(container, val)
        if onChange and not skipCallback then onChange(val) end
        if not skipCallback then
            MaybeAutoNotifyProviderSync(container)
        end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "checkbox", label, dbKey, dbTable, box, registryInfo)

    SetValue(GetValue(), true)

    GUI:AttachTooltip(box, registryInfo and registryInfo.description or nil, label)
    return container
end

-- Form Checkbox Inverted: checked = DB false, unchecked = DB true (for "Hide X" options)
function GUI:CreateFormCheckboxInverted(parent, label, dbKey, dbTable, onChange, registryInfo)
    -- Redirect to toggle inverted for the premium look
    return GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange, registryInfo)
end

function GUI:CreateFormEditBox(parent, label, dbKey, dbTable, onChange, options, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    options = options or {}
    local UIKit = ns.UIKit

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    container._widgetLabel = label  -- For search jump-to-setting (V2)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Text")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(170)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")

    local field = CreateFrame("Frame", nil, container)
    field:SetHeight(24)
    field:SetPoint("LEFT", container, "LEFT", 180, 0)
    if options.width and options.width > 0 then
        field:SetWidth(options.width)
    else
        field:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    end

    local fieldBg
    if UIKit and UIKit.CreateBackground then
        fieldBg = UIKit.CreateBackground(field, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
    else
        fieldBg = field:CreateTexture(nil, "BACKGROUND")
        fieldBg:SetAllPoints()
        fieldBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        fieldBg:SetVertexColor(C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
    end

    local function UpdateFallbackBorder(r, g, b, a)
        if not field._fallbackBorder then
            field._fallbackBorder = {
                top = field:CreateTexture(nil, "OVERLAY"),
                bottom = field:CreateTexture(nil, "OVERLAY"),
                left = field:CreateTexture(nil, "OVERLAY"),
                right = field:CreateTexture(nil, "OVERLAY"),
            }
            for _, edge in pairs(field._fallbackBorder) do
                edge:SetTexture("Interface\\Buttons\\WHITE8x8")
            end
        end

        local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(field)) or 1
        local border = field._fallbackBorder
        border.top:ClearAllPoints()
        border.top:SetPoint("TOPLEFT", field, "TOPLEFT", 0, 0)
        border.top:SetPoint("TOPRIGHT", field, "TOPRIGHT", 0, 0)
        border.top:SetHeight(px)

        border.bottom:ClearAllPoints()
        border.bottom:SetPoint("BOTTOMLEFT", field, "BOTTOMLEFT", 0, 0)
        border.bottom:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 0, 0)
        border.bottom:SetHeight(px)

        border.left:ClearAllPoints()
        border.left:SetPoint("TOPLEFT", border.top, "BOTTOMLEFT", 0, 0)
        border.left:SetPoint("BOTTOMLEFT", border.bottom, "TOPLEFT", 0, 0)
        border.left:SetWidth(px)

        border.right:ClearAllPoints()
        border.right:SetPoint("TOPRIGHT", border.top, "BOTTOMRIGHT", 0, 0)
        border.right:SetPoint("BOTTOMRIGHT", border.bottom, "TOPRIGHT", 0, 0)
        border.right:SetWidth(px)

        for _, edge in pairs(border) do
            edge:SetVertexColor(r or 0.35, g or 0.35, b or 0.35, a or 1)
        end
    end

    local function SetFieldBorderColor(r, g, b, a)
        if UIKit and UIKit.UpdateBorderLines then
            if not field._pixelBorderReady and UIKit.CreateBorderLines then
                UIKit.CreateBorderLines(field)
                field._pixelBorderReady = true
            end
            UIKit.UpdateBorderLines(field, 1, r, g, b, a, false)
        else
            UpdateFallbackBorder(r, g, b, a)
        end
    end
    SetFieldBorderColor(1, 1, 1, 0.2)

    local editBox = CreateFrame("EditBox", nil, field)
    editBox:SetPoint("TOPLEFT", field, "TOPLEFT", 6, -2)
    editBox:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -6, 2)
    editBox:SetAutoFocus(false)
    do
        local f, _, flags = editBox:GetFont()
        editBox:SetFont(f or UIKit.ResolveFontPath(GUI:GetFontPath()), 10, flags or "")
    end
    editBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    editBox:SetTextInsets(4, 4, 0, 0)
    editBox:SetJustifyH("LEFT")

    if options.maxLetters and options.maxLetters > 0 then
        editBox:SetMaxLetters(options.maxLetters)
    end

    container.label = text
    container.field = field
    container.editBox = editBox

    local commitOnEnter = options.commitOnEnter ~= false
    local commitOnFocusLost = options.commitOnFocusLost ~= false
    local liveUpdate = options.live == true
    local initialValue = options.value
    local isSyncingVisual = false

    local function GetValue()
        if dbTable and dbKey then
            local v = dbTable[dbKey]
            if v == nil then
                return initialValue or ""
            end
            return tostring(v)
        end
        if container.value == nil then
            return initialValue or ""
        end
        return tostring(container.value)
    end

    local function UpdateVisual(val)
        isSyncingVisual = true
        editBox:SetText(val or "")
        isSyncingVisual = false
    end

    local function SetValue(val, skipOnChange, source)
        local nextVal = val or ""
        if type(nextVal) ~= "string" then
            nextVal = tostring(nextVal)
        end

        container.value = nextVal
        if dbTable and dbKey then
            dbTable[dbKey] = nextVal
        end

        if source ~= editBox then
            UpdateVisual(nextVal)
        end

        BroadcastToSiblings(container, nextVal)
        if onChange and not skipOnChange then
            onChange(nextVal)
        end
        if not skipOnChange then
            MaybeAutoNotifyProviderSync(container)
        end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    container.UpdateVisual = UpdateVisual

    RegisterWidgetInstance(container, dbTable, dbKey)
    SetValue(GetValue(), true)

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if isSyncingVisual then return end
        if options.onTextChanged then
            options.onTextChanged(self, userInput)
        end
        if liveUpdate and userInput then
            SetValue(self:GetText(), false, self)
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if commitOnEnter then
            SetValue(self:GetText(), false, self)
        end
        if options.onEnterPressed then
            options.onEnterPressed(self)
        else
            self:ClearFocus()
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        if options.onEscapePressed then
            options.onEscapePressed(self)
        else
            self:ClearFocus()
        end
    end)

    editBox:SetScript("OnEditFocusGained", function(self)
        SetFieldBorderColor(C.borderAccent[1], C.borderAccent[2], C.borderAccent[3], 1)
        if options.onEditFocusGained then
            options.onEditFocusGained(self)
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        SetFieldBorderColor(1, 1, 1, 0.2)
        if commitOnFocusLost then
            SetValue(self:GetText(), false, self)
        end
        if options.onEditFocusLost then
            options.onEditFocusLost(self)
        end
    end)

    container.SetEnabled = function(self, enabled)
        self.isEnabled = enabled and true or false
        editBox:SetEnabled(enabled)
        editBox:EnableMouse(enabled)
        field:SetAlpha(enabled and 1 or 0.6)
        self:SetAlpha(enabled and 1 or 0.6)
        if not enabled then
            editBox:ClearFocus()
        end
    end
    container.isEnabled = true

    GUI:RegisterSearchSettingWidget({
        label = label,
        widgetType = "editbox",
        widgetBuilder = function(p)
            return GUI:CreateFormEditBox(p, label, dbKey, dbTable, onChange, options)
        end,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor("editbox", dbKey, dbTable, {
            options = options,
        }),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    })

    GUI:AttachTooltip(editBox, registryInfo and registryInfo.description or nil, label)
    return container
end

function GUI:CreateFormSlider(parent, label, min, max, step, dbKey, dbTable, onChange, options, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    options = options or {}
    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label  -- For search jump-to-setting (V2)
    container:EnableMouse(true)  -- Block clicks from passing through to frames behind

    local UIKit = ns.UIKit
    ApplyWidgetSyncContext(container, dbTable, dbKey)
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines
    local deferOnDrag = options.deferOnDrag or false
    local onDragPreview = options.onDragPreview
    local precision = options.precision
    local formatStr = precision and string.format("%%.%df", precision) or (step < 1 and "%.2f" or "%d")

    -- Bare mode: label=nil skips the internal label and shrinks the container
    -- to just the slider + edit cluster — V3 BuildSettingRow provides the label.
    local text
    local sliderLeftOffset = 180
    if label then
        container:SetHeight(FORM_ROW_HEIGHT)
        text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 12, "", C.text)
        text:SetText(label)
        text:SetPoint("LEFT", 0, 0)
        text:SetWidth(170)
        text:SetWordWrap(true)
        text:SetNonSpaceWrap(true)
        text:SetJustifyH("LEFT")
        container.label = text
    else
        container:SetSize(180, FORM_ROW_HEIGHT)
        sliderLeftOffset = 0
    end

    local SLIDER_TRACK_WIDTH = (options and options.width) or 120
    local SLIDER_TRACK_HEIGHT = 4
    local SLIDER_THUMB_SIZE = 10

    -- Slider frame doubles as the track; textures paint the visual state
    local slider = CreateFrame("Slider", nil, container)
    slider:SetSize(SLIDER_TRACK_WIDTH, SLIDER_TRACK_HEIGHT)
    slider:SetPoint("LEFT", container, "LEFT", sliderLeftOffset, 0)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHitRectInsets(0, 0, -10, -10)

    local trackBg = slider:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints(slider)
    trackBg:SetColorTexture(C.sliderTrack[1], C.sliderTrack[2], C.sliderTrack[3], C.sliderTrack[4])
    slider.trackBg = trackBg
    slider.track = trackBg

    local trackFill = slider:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 0)
    trackFill:SetPoint("BOTTOMLEFT", slider, "BOTTOMLEFT", 0, 0)
    trackFill:SetWidth(1)
    trackFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], C.accent[4])
    slider.fill = trackFill

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(SLIDER_THUMB_SIZE, SLIDER_THUMB_SIZE)
    thumb:SetColorTexture(C.sliderThumb[1], C.sliderThumb[2], C.sliderThumb[3], C.sliderThumb[4])
    slider.thumb = thumb

    local thumbMask = slider:CreateMaskTexture()
    thumbMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    thumbMask:SetAllPoints(thumb)
    thumb:AddMaskTexture(thumbMask)
    slider._thumbMask = thumbMask

    -- Suppress native Slider thumb so our custom texture alone renders
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local nativeThumb = slider:GetThumbTexture()
    nativeThumb:SetSize(SLIDER_THUMB_SIZE, SLIDER_THUMB_SIZE)
    nativeThumb:SetAlpha(0)

    -- Aliases for legacy identifiers consumed elsewhere in this file
    local thumbFrame = thumb
    local trackContainer = slider
    local px = QUICore:GetPixelSize(slider)

    -- Nudge button (decrement) — left of editbox
    local nudgeMinus = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    nudgeMinus:SetSize(16, 22)
    nudgeMinus:SetPoint("RIGHT", container, "RIGHT", -64, 0)

    -- Now that the nudge cluster's left edge is anchored, make the slider
    -- track shrink to fit — previously the fixed 120px track would collide
    -- with the nudge buttons in narrow containers (e.g. Layout Mode drawer).
    slider:SetPoint("RIGHT", nudgeMinus, "LEFT", -8, 0)
    if useUIKitBorders then
        nudgeMinus.bg = UIKit.CreateBackground(nudgeMinus, 0.08, 0.08, 0.08, 1)
        UIKit.CreateBorderLines(nudgeMinus)
        UIKit.UpdateBorderLines(nudgeMinus, 1, 0.25, 0.25, 0.25, 1, false)
    else
        nudgeMinus:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        nudgeMinus:SetBackdropColor(0.08, 0.08, 0.08, 1)
        nudgeMinus:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
    local nudgeMinusText = nudgeMinus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(nudgeMinusText, 11, "", C.text)
    nudgeMinusText:SetText("-")
    nudgeMinusText:SetPoint("CENTER", 0, 0)

    -- Editbox for value (between nudge buttons)
    local editBox = CreateFrame("EditBox", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    editBox:SetSize((options and options.editWidth) or 36, 18)
    editBox:SetPoint("LEFT", nudgeMinus, "RIGHT", 1, 0)
    if useUIKitBorders then
        editBox.bg = UIKit.CreateBackground(editBox, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        UIKit.CreateBorderLines(editBox)
        UIKit.UpdateBorderLines(editBox, 1, C.border[1], C.border[2], C.border[3], C.border[4], false)
    else
        editBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        editBox:SetBackdropColor(C.bgContent[1], C.bgContent[2], C.bgContent[3], 1)
        editBox:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
    end
    editBox:SetFont(GetFontPath(), 10, "")
    editBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    editBox:SetJustifyH("CENTER")
    editBox:SetTextInsets(4, 4, 0, 0)
    editBox:SetAutoFocus(false)

    -- Nudge button (increment) — right of editbox
    local nudgePlus = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    nudgePlus:SetSize(16, 22)
    nudgePlus:SetPoint("LEFT", editBox, "RIGHT", 1, 0)
    if useUIKitBorders then
        nudgePlus.bg = UIKit.CreateBackground(nudgePlus, 0.08, 0.08, 0.08, 1)
        UIKit.CreateBorderLines(nudgePlus)
        UIKit.UpdateBorderLines(nudgePlus, 1, 0.25, 0.25, 0.25, 1, false)
    else
        nudgePlus:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        nudgePlus:SetBackdropColor(0.08, 0.08, 0.08, 1)
        nudgePlus:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
    local nudgePlusText = nudgePlus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(nudgePlusText, 11, "", C.text)
    nudgePlusText:SetText("+")
    nudgePlusText:SetPoint("CENTER", 0, 0)

    local function SetEditBoxBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(editBox, 1, r, g, b, a or 1, false)
        else
            editBox:SetBackdropBorderColor(r, g, b, a or 1)
        end
    end

    -- Configure slider
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)

    container.slider = slider
    container.editBox = editBox
    container.trackFill = trackFill
    container.thumbFrame = thumbFrame
    container.trackContainer = trackContainer
    container.min = min or 0
    container.max = max or 100
    container.step = step or 1

    local isDragging = false

    -- Update filled track and thumb position
    local function UpdateTrackFill(value)
        local minVal, maxVal = container.min, container.max
        local pct = (maxVal > minVal) and ((value - minVal) / (maxVal - minVal)) or 0
        pct = math.max(0, math.min(1, pct))

        local trackWidth = slider:GetWidth()
        local x = trackWidth * pct
        trackFill:SetWidth(math.max(1, x))

        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", slider, "LEFT", x, 0)
        if slider._thumbMask then
            slider._thumbMask:SetAllPoints(thumb)
        end
    end

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] or container.min end
        return container.value or container.min
    end

    local function UpdateVisual(val)
        val = math.max(container.min, math.min(container.max, val))
        if not precision then
            val = math.floor(val / container.step + 0.5) * container.step
        end
        slider:SetValue(val)
        editBox:SetText(string.format(formatStr, val))
        UpdateTrackFill(val)
    end

    local function SetValue(val, skipOnChange)
        val = math.max(container.min, math.min(container.max, val))
        if precision then
            local factor = 10 ^ precision
            val = math.floor(val * factor + 0.5) / factor
        else
            val = math.floor(val / container.step + 0.5) * container.step
        end
        container.value = val
        UpdateVisual(val)
        if dbTable and dbKey then dbTable[dbKey] = val end
        if not skipOnChange then
            MaybeUpdatePinnedWidgetValue(container, val)
        end
        BroadcastToSiblings(container, val)
        if not skipOnChange and onChange then onChange(val) end
        if not skipOnChange then
            MaybeAutoNotifyProviderSync(container)
        end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    container.UpdateVisual = UpdateVisual

    -- Nudge button click handlers
    nudgeMinus:SetScript("OnClick", function()
        if container.isEnabled == false then return end
        local cur = GetValue()
        SetValue(cur - container.step)
    end)
    nudgePlus:SetScript("OnClick", function()
        if container.isEnabled == false then return end
        local cur = GetValue()
        SetValue(cur + container.step)
    end)

    -- Nudge button hover effects
    local function SetNudgeBorderColor(btn, r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(btn, 1, r, g, b, a or 1, false)
        else
            btn:SetBackdropBorderColor(r, g, b, a or 1)
        end
    end
    nudgeMinus:SetScript("OnEnter", function(self)
        SetNudgeBorderColor(self, C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    nudgeMinus:SetScript("OnLeave", function(self)
        SetNudgeBorderColor(self, 0.25, 0.25, 0.25, 1)
    end)
    nudgePlus:SetScript("OnEnter", function(self)
        SetNudgeBorderColor(self, C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    nudgePlus:SetScript("OnLeave", function(self)
        SetNudgeBorderColor(self, 0.25, 0.25, 0.25, 1)
    end)

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "slider", label, dbKey, dbTable, slider, registryInfo)

    slider:SetScript("OnValueChanged", function(self, value, userInput)
        -- Ignore user input if slider is disabled
        if userInput and container.isEnabled == false then return end

        value = math.floor(value / container.step + 0.5) * container.step
        editBox:SetText(string.format(formatStr, value))
        UpdateTrackFill(value)
        if dbTable and dbKey then dbTable[dbKey] = value end
        if userInput then
            MaybeUpdatePinnedWidgetValue(container, value)
            BroadcastToSiblings(container, value)
            if deferOnDrag and isDragging then
                if onDragPreview then onDragPreview(value) end
                return
            end
            if onChange then onChange(value) end
            MaybeAutoNotifyProviderSync(container)
        end
    end)

    slider:SetScript("OnMouseDown", function() isDragging = true end)
    slider:SetScript("OnMouseUp", function()
        if isDragging and deferOnDrag then
            isDragging = false
            if onChange then onChange(slider:GetValue()) end
            MaybeAutoNotifyProviderSync(container)
        end
        isDragging = false
    end)

    -- Track fills a dynamic width now (bounded by the nudge cluster on the
    -- right). Re-render fill + thumb positions when the slider resizes.
    slider:SetScript("OnSizeChanged", function()
        UpdateTrackFill(GetValue())
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or container.min
        SetValue(val)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(string.format(formatStr, GetValue()))
        self:ClearFocus()
    end)

    -- Hover / focus accent on editbox border
    editBox:SetScript("OnEnter", function(self)
        SetEditBoxBorderColor(C.borderAccent[1], C.borderAccent[2], C.borderAccent[3], C.borderAccent[4])
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        SetEditBoxBorderColor(C.borderAccent[1], C.borderAccent[2], C.borderAccent[3], C.borderAccent[4])
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        SetEditBoxBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
    end)
    editBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            SetEditBoxBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
        end
    end)

    -- Re-update track fill when slider size changes (fixes initial layout timing)
    slider:SetScript("OnSizeChanged", function(self, width, height)
        if width and width > 0 then
            UpdateTrackFill(GetValue())
        end
    end)

    -- Initialize value (visual update will happen via OnSizeChanged when layout completes)
    SetValue(GetValue(), true)

    -- EditBox:SetText() doesn't persist when called inside a hidden parent
    -- hierarchy (e.g. collapsed composer sections with alpha 0). Expose a
    -- refresh method so parent containers can re-apply the text when the
    -- widget becomes visible.
    container._refreshEditBox = function()
        local val = GetValue()
        local txt = string.format(formatStr, val)
        editBox:SetText(txt)
        -- Force WoW to re-render the EditBox text — SetText updates
        -- the internal state but the visual FontString may not refresh
        -- when the EditBox was created inside a hidden parent hierarchy.
        editBox:SetCursorPosition(0)
    end

    -- Enable/disable the slider (for conditional UI)
    -- Note: Uses self parameter for colon-call syntax (widget:SetEnabled(bool))
    container.SetEnabled = function(self, enabled)
        slider:EnableMouse(enabled)
        editBox:EnableMouse(enabled)
        editBox:SetEnabled(enabled)
        nudgeMinus:EnableMouse(enabled)
        nudgePlus:EnableMouse(enabled)

        -- Store state for scripts to check
        container.isEnabled = enabled

        -- Visual feedback: dim when disabled (matches HUD Visibility pattern)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    -- Initialize enabled state
    container.isEnabled = true

    GUI:RegisterSearchSettingWidget({
        label = label,
        widgetType = "slider",
        widgetBuilder = function(p)
            return GUI:CreateFormSlider(p, label, min, max, step, dbKey, dbTable, onChange, options)
        end,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor("slider", dbKey, dbTable, {
            min = min,
            max = max,
            step = step,
            options = options,
        }),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    })

    GUI:AttachTooltip(slider, registryInfo and registryInfo.description or nil, label)
    return container
end

function GUI:CreateFormDropdown(parent, label, options, dbKey, dbTable, onChange, registryInfo, opts)
    if parent._hasContent ~= nil then parent._hasContent = true end
    opts = opts or {}
    local searchable = opts.searchable or false
    local collapsible = opts.collapsible or false
    local SEARCH_BOX_HEIGHT = 28
    local UIKit = ns.UIKit
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines
    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label  -- For search jump-to-setting (V2)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    -- Bare mode: label=nil skips the internal label and shrinks container
    -- to just the dropdown — V3 BuildSettingRow provides the label.
    local text
    local dropdownLeftOffset = 180
    if label then
        container:SetHeight(FORM_ROW_HEIGHT)
        text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 12, "", C.text)
        text:SetText(label)
        text:SetPoint("LEFT", 0, 0)
    else
        container:SetSize(180, FORM_ROW_HEIGHT)
        dropdownLeftOffset = 0
    end

    -- Dropdown button (right side) — V3 widget surface
    local dropdown = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    dropdown:SetHeight(22)
    dropdown:SetPoint("LEFT", container, "LEFT", dropdownLeftOffset, 0)
    dropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    local px = QUICore:GetPixelSize(dropdown)
    if useUIKitBorders then
        dropdown.bg = UIKit.CreateBackground(dropdown, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        UIKit.CreateBorderLines(dropdown)
        UIKit.UpdateBorderLines(dropdown, 1, 1, 1, 1, 0.2, false)
    else
        dropdown:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        dropdown:SetBackdropColor(C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        dropdown:SetBackdropBorderColor(1, 1, 1, 0.2)
    end

    local function SetDropdownBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(dropdown, 1, r, g, b, a or 1, false)
        else
            pcall(dropdown.SetBackdropBorderColor, dropdown, r, g, b, a or 1)
        end
    end

    local chevron = UIKit.CreateChevronCaret(dropdown, {
        point = "RIGHT", relativeTo = dropdown, relativePoint = "RIGHT",
        xPixels = -8, sizePixels = 10, lineWidthPixels = 6,
        r = C.textMuted[1], g = C.textMuted[2], b = C.textMuted[3], a = 1,
        expanded = true,
    })
    dropdown.chevron = chevron

    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 10, "", C.text)
    dropdown.selected:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
    dropdown.selected:SetPoint("RIGHT", chevron, "LEFT", -4, 0)
    dropdown.selected:SetJustifyH("LEFT")

    -- Hover effect: border brightens
    dropdown:SetScript("OnEnter", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.35)
    end)
    dropdown:SetScript("OnLeave", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.2)
    end)

    -- Menu frame (parented to UIParent to avoid scroll frame clipping)
    local menuFrame = CreateFrame("Frame", nil, UIParent, useUIKitBorders and nil or "BackdropTemplate")
    if useUIKitBorders then
        menuFrame.bg = UIKit.CreateBackground(menuFrame, C.bg[1], C.bg[2], C.bg[3], 1)
        UIKit.CreateBorderLines(menuFrame)
        UIKit.UpdateBorderLines(menuFrame, 1, 1, 1, 1, 0.2, false)
    else
        menuFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        menuFrame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
        menuFrame:SetBackdropBorderColor(1, 1, 1, 0.2)
    end
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:SetClipsChildren(true)
    menuFrame:Hide()

    -- Hide menu when dropdown becomes hidden (tab switch, panel close, etc.)
    dropdown:HookScript("OnHide", function() menuFrame:Hide() end)

    -- Scroll body with scrollbar
    local scrollFrame, scrollContent, scrollBar, updateThumb = CreateDropdownScrollBody(menuFrame)
    menuFrame.scrollContent = scrollContent

    -- Search box for searchable dropdowns (above scroll content)
    local searchBox
    if searchable then
        scrollFrame:SetPoint("TOPLEFT", 0, -SEARCH_BOX_HEIGHT)

        local searchContainer = CreateFrame("Frame", nil, menuFrame)
        searchContainer:SetHeight(SEARCH_BOX_HEIGHT)
        searchContainer:SetPoint("TOPLEFT", 0, 0)
        searchContainer:SetPoint("TOPRIGHT", 0, 0)

        local searchBg = searchContainer:CreateTexture(nil, "BACKGROUND")
        searchBg:SetAllPoints()
        searchBg:SetColorTexture(0.06, 0.06, 0.06, 1)

        local searchBorder = searchContainer:CreateTexture(nil, "ARTWORK")
        searchBorder:SetHeight(1)
        searchBorder:SetPoint("BOTTOMLEFT", searchContainer, "BOTTOMLEFT", 0, 0)
        searchBorder:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", 0, 0)
        searchBorder:SetColorTexture(0.25, 0.25, 0.25, 1)

        searchBox = CreateFrame("EditBox", nil, searchContainer)
        searchBox:SetPoint("TOPLEFT", 8, -2)
        searchBox:SetPoint("BOTTOMRIGHT", -8, 2)
        searchBox:SetAutoFocus(false)
        searchBox:SetFontObject(GameFontNormal)
        SetFont(searchBox, 11, "", C.text)
        searchBox:SetMaxLetters(50)

        local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(placeholder, 11, "", C.textMuted or {0.6, 0.6, 0.6})
        placeholder:SetText("Search...")
        placeholder:SetPoint("LEFT", 0, 0)
        placeholder:SetJustifyH("LEFT")
        searchBox.placeholder = placeholder

        searchBox:SetScript("OnEditFocusGained", function(self)
            searchBorder:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        end)
        searchBox:SetScript("OnEditFocusLost", function(self)
            searchBorder:SetColorTexture(0.25, 0.25, 0.25, 1)
        end)
        searchBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)
        searchBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)

        searchContainer.searchBox = searchBox
    end

    container.dropdown = dropdown
    container.menuFrame = menuFrame
    container.options = options or {}
    container.collapsedHeaders = {}
    container.searchText = ""
    container.searchBox = searchBox

    -- Default all headers to collapsed when collapsible is enabled
    if collapsible then
        for _, opt in ipairs(container.options) do
            if opt.isHeader then
                container.collapsedHeaders[opt.text] = true
            end
        end
    end

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.selectedValue
    end

    local function UpdateVisual(val)
        if val == nil then return end
        for _, opt in ipairs(container.options) do
            if not opt.isHeader and opt.value == val then
                dropdown.selected:SetText(opt.text)
                break
            end
        end
    end

    local function SetValue(val, skipOnChange)
        container.selectedValue = val
        if dbTable and dbKey then dbTable[dbKey] = val end
        UpdateVisual(val)
        if not skipOnChange then
            MaybeUpdatePinnedWidgetValue(container, val)
        end
        BroadcastToSiblings(container, val)
        if not skipOnChange and onChange then onChange(val) end
        if not skipOnChange then
            MaybeAutoNotifyProviderSync(container)
        end
    end

    local function UpdateScrollInset()
        if scrollBar:IsShown() then
            scrollFrame:SetPoint("BOTTOMRIGHT", -(DROPDOWN_SCROLLBAR_WIDTH + 2), 0)
        else
            scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end

    -- Frame pools for BuildMenu to avoid creating frames on every rebuild
    local headerPool = {}
    local buttonPool = {}
    local headerPoolIdx, buttonPoolIdx = 0, 0

    local function AcquireHeader()
        headerPoolIdx = headerPoolIdx + 1
        local f = headerPool[headerPoolIdx]
        if not f then
            f = CreateFrame("Button", nil, scrollContent)
            f._headerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f._headerText:SetPoint("LEFT", 4, 0)
            if collapsible then
                f._chevron1 = f:CreateTexture(nil, "OVERLAY")
                f._chevron1:SetSize(5, 1)
                f._chevron2 = f:CreateTexture(nil, "OVERLAY")
                f._chevron2:SetSize(5, 1)
            end
            headerPool[headerPoolIdx] = f
        end
        f:ClearAllPoints()
        f:Show()
        return f
    end

    local function AcquireButton()
        buttonPoolIdx = buttonPoolIdx + 1
        local f = buttonPool[buttonPoolIdx]
        if not f then
            f = CreateFrame("Button", nil, scrollContent)
            f._selectedBg = f:CreateTexture(nil, "BACKGROUND")
            f._selectedBg:SetAllPoints(f)
            f._selectedBg:SetColorTexture(0.204, 0.827, 0.6, 0.04)
            f._selectedBg:Hide()
            f._hoverBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
            f._hoverBg:SetAllPoints(f)
            f._hoverBg:SetColorTexture(0.204, 0.827, 0.6, 0.08)
            f._hoverBg:Hide()
            f._selectedBar = f:CreateTexture(nil, "OVERLAY")
            f._selectedBar:SetWidth(2)
            f._selectedBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            f._selectedBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
            f._selectedBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            f._selectedBar:Hide()
            f._btnText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f._btnText:SetPoint("LEFT", 8, 0)
            buttonPool[buttonPoolIdx] = f
        end
        f:ClearAllPoints()
        f:Show()
        return f
    end

    local function BuildMenu()
        -- Hide all pooled frames and reset indices
        for i = 1, headerPoolIdx do headerPool[i]:Hide() end
        for i = 1, buttonPoolIdx do buttonPool[i]:Hide() end
        headerPoolIdx = 0
        buttonPoolIdx = 0
        -- Also hide any non-pooled children (e.g. "no results" text from previous builds)
        for _, child in ipairs({scrollContent:GetChildren()}) do child:Hide() end

        local yOff = -4
        local itemHeight = 22
        local headerHeight = 18
        local maxVisibleItems = DROPDOWN_MAX_VISIBLE_ITEMS
        local filterText = searchable and container.searchText and container.searchText:lower() or ""
        local isFiltering = filterText ~= ""
        local visibleCount = 0
        local currentHeader = nil
        local mutedColor = C.textMuted or {0.6, 0.6, 0.6}

        -- Reset scroll to top when filtering
        if isFiltering then
            pcall(scrollFrame.SetVerticalScroll, scrollFrame, 0)
        end

        for i, opt in ipairs(container.options) do
            if opt.isHeader then
                currentHeader = opt.text

                -- When filtering, skip headers with no matching children
                if isFiltering then
                    local hasMatch = false
                    for j = i + 1, #container.options do
                        local nxt = container.options[j]
                        if nxt.isHeader then break end
                        if nxt.text:lower():find(filterText, 1, true) then
                            hasMatch = true
                            break
                        end
                    end
                    if not hasMatch then
                        -- Skip this header entirely; items will be skipped below
                    else
                        -- Render header (no collapse during search)
                        local header = AcquireHeader()
                        if visibleCount > 0 then yOff = yOff - 4 end
                        header:SetHeight(headerHeight)
                        header:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, yOff)
                        header:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -4, yOff)
                        SetFont(header._headerText, 10, "", mutedColor)
                        header._headerText:SetText(opt.text)
                        header._headerText:SetPoint("LEFT", 4, 0)
                        header:SetScript("OnClick", nil)
                        header:SetScript("OnEnter", nil)
                        header:SetScript("OnLeave", nil)
                        if header._chevron1 then header._chevron1:Hide() end
                        if header._chevron2 then header._chevron2:Hide() end
                        yOff = yOff - headerHeight
                        visibleCount = visibleCount + 1
                    end
                else
                    -- Normal (non-filtering) mode
                    local isCollapsed = collapsible and container.collapsedHeaders[currentHeader]
                    local header = AcquireHeader()
                    if visibleCount > 0 then yOff = yOff - 4 end
                    header:SetHeight(headerHeight)
                    header:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, yOff)
                    header:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -4, yOff)
                    SetFont(header._headerText, 10, "", mutedColor)
                    header._headerText:SetText(opt.text)

                    if collapsible then
                        -- Chevron indicator: v (expanded) or > (collapsed)
                        header._headerText:SetPoint("LEFT", 14, 0)
                        local c1, c2 = header._chevron1, header._chevron2
                        c1:Show()
                        c2:Show()
                        c1:SetColorTexture(mutedColor[1], mutedColor[2], mutedColor[3], 0.8)
                        c2:SetColorTexture(mutedColor[1], mutedColor[2], mutedColor[3], 0.8)
                        if isCollapsed then
                            -- Right-pointing chevron >
                            c1:SetSize(5, 1)
                            c1:ClearAllPoints()
                            c1:SetPoint("LEFT", header, "LEFT", 4, 2)
                            c1:SetRotation(math.rad(-45))
                            c2:SetSize(5, 1)
                            c2:ClearAllPoints()
                            c2:SetPoint("LEFT", header, "LEFT", 4, -2)
                            c2:SetRotation(math.rad(45))
                        else
                            -- Down-pointing chevron v
                            c1:SetSize(5, 1)
                            c1:ClearAllPoints()
                            c1:SetPoint("LEFT", header, "LEFT", 2, 0)
                            c1:SetRotation(math.rad(-45))
                            c2:SetSize(5, 1)
                            c2:ClearAllPoints()
                            c2:SetPoint("LEFT", header, "LEFT", 6, 0)
                            c2:SetRotation(math.rad(45))
                        end

                        local headerName = currentHeader
                        header:SetScript("OnClick", function()
                            container.collapsedHeaders[headerName] = not container.collapsedHeaders[headerName]
                            BuildMenu()
                            C_Timer.After(0, function() updateThumb(); UpdateScrollInset() end)
                        end)
                        header:SetScript("OnEnter", function()
                            header._headerText:SetTextColor(C_accent_r, C_accent_g, C_accent_b, 0.8)
                            c1:SetColorTexture(C_accent_r, C_accent_g, C_accent_b, 0.8)
                            c2:SetColorTexture(C_accent_r, C_accent_g, C_accent_b, 0.8)
                        end)
                        header:SetScript("OnLeave", function()
                            header._headerText:SetTextColor(mutedColor[1], mutedColor[2], mutedColor[3], 1)
                            c1:SetColorTexture(mutedColor[1], mutedColor[2], mutedColor[3], 0.8)
                            c2:SetColorTexture(mutedColor[1], mutedColor[2], mutedColor[3], 0.8)
                        end)
                    else
                        header._headerText:SetPoint("LEFT", 4, 0)
                        header:SetScript("OnClick", nil)
                        header:SetScript("OnEnter", nil)
                        header:SetScript("OnLeave", nil)
                    end

                    yOff = yOff - headerHeight
                    visibleCount = visibleCount + 1
                end
            else
                -- Regular item
                local isCollapsed = collapsible and not isFiltering and currentHeader
                    and container.collapsedHeaders[currentHeader]
                if isCollapsed then
                    -- Skip collapsed items
                elseif isFiltering and not opt.text:lower():find(filterText, 1, true) then
                    -- Skip non-matching items during search
                else
                    local btn = AcquireButton()
                    btn:SetHeight(itemHeight)
                    btn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, yOff)
                    btn:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -4, yOff)
                    btn._btnText:ClearAllPoints()
                    btn._btnText:SetPoint("LEFT", btn, "LEFT", 8, 0)
                    SetFont(btn._btnText, 10, "", C.text)
                    btn._btnText:SetText(opt.text)

                    local isSelected = (container.selectedValue == opt.value)
                    if isSelected then
                        btn._selectedBg:Show()
                        btn._selectedBar:Show()
                        btn._btnText:SetTextColor(C_accent_r, C_accent_g, C_accent_b, 1)
                    else
                        btn._selectedBg:Hide()
                        btn._selectedBar:Hide()
                        btn._btnText:SetTextColor(C_text_r, C_text_g, C_text_b, 1)
                    end
                    btn._hoverBg:Hide()

                    btn:SetScript("OnClick", function()
                        SetValue(opt.value)
                        menuFrame:Hide()
                    end)
                    btn:SetScript("OnEnter", function(self)
                        self._hoverBg:Show()
                    end)
                    btn:SetScript("OnLeave", function(self)
                        self._hoverBg:Hide()
                    end)
                    yOff = yOff - itemHeight
                    visibleCount = visibleCount + 1
                end
            end
        end

        -- "No matches" message when filtering yields nothing
        if isFiltering and visibleCount == 0 then
            local noMatch = AcquireButton()
            noMatch:SetHeight(itemHeight)
            noMatch:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, -10)
            noMatch:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -4, -10)
            noMatch._selectedBg:Hide()
            noMatch._selectedBar:Hide()
            noMatch._hoverBg:Hide()
            noMatch._btnText:ClearAllPoints()
            noMatch._btnText:SetPoint("CENTER", 0, 0)
            SetFont(noMatch._btnText, 10, "", mutedColor)
            noMatch._btnText:SetText("No matches")
            noMatch:SetScript("OnClick", nil)
            noMatch:SetScript("OnEnter", nil)
            noMatch:SetScript("OnLeave", nil)
            yOff = -40
        end

        local totalHeight = math.abs(yOff) + 4
        local maxHeight = (maxVisibleItems * itemHeight) + 8
        local searchOffset = searchable and SEARCH_BOX_HEIGHT or 0

        scrollContent:SetHeight(totalHeight)
        scrollContent:SetWidth(dropdown:GetWidth() - 4)
        menuFrame:SetHeight(math.min(totalHeight, maxHeight) + searchOffset)
    end

    -- Wire up search box OnTextChanged (after BuildMenu is defined)
    if searchBox then
        searchBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local txt = self:GetText()
            container.searchText = txt or ""
            if self.placeholder then
                self.placeholder:SetShown(txt == nil or txt == "")
            end
            BuildMenu()
            C_Timer.After(0, function() updateThumb(); UpdateScrollInset() end)
        end)
    end

    dropdown:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide()
        else
            BuildMenu()
            PositionDropdownMenu(menuFrame, dropdown, menuFrame:GetHeight())
            menuFrame:Show()
            C_Timer.After(0, function() updateThumb(); UpdateScrollInset() end)
        end
    end)

    -- Close menu when clicking elsewhere
    local closeTimer = 0
    menuFrame:HookScript("OnShow", function()
        closeTimer = 0
        menuFrame.__checkElapsed = 0
        menuFrame:SetScript("OnUpdate", function(self, elapsed)
            self.__checkElapsed = (self.__checkElapsed or 0) + elapsed
            if self.__checkElapsed < 0.066 then return end
            local deltaTime = self.__checkElapsed
            self.__checkElapsed = 0

            -- Don't auto-close while user is typing in search
            if searchBox and searchBox:HasFocus() then
                closeTimer = 0
                return
            end

            local isOverDropdown = dropdown:IsMouseOver()
            local isOverMenu = self:IsMouseOver()
            if not isOverDropdown and not isOverMenu then
                closeTimer = closeTimer + deltaTime
                if closeTimer > 0.15 then
                    self:Hide()
                end
            else
                closeTimer = 0
            end
        end)
    end)

    menuFrame:HookScript("OnHide", function()
        menuFrame:SetScript("OnUpdate", nil)
        closeTimer = 0
        if searchBox then
            searchBox:SetText("")
            searchBox:ClearFocus()
            container.searchText = ""
        end
    end)

    local function SetOptions(newOptions)
        container.options = newOptions or {}
        -- Default new headers to collapsed
        if collapsible then
            for _, opt in ipairs(container.options) do
                if opt.isHeader and container.collapsedHeaders[opt.text] == nil then
                    container.collapsedHeaders[opt.text] = true
                end
            end
        end
        -- Check if current value still exists in new options (skip headers)
        local currentVal = GetValue()
        local found = false
        for _, opt in ipairs(container.options) do
            if not opt.isHeader and opt.value == currentVal then
                dropdown.selected:SetText(opt.text)
                found = true
                break
            end
        end
        if not found and container.preserveUnknownValue and currentVal ~= nil and currentVal ~= "" then
            -- Value not in current list but was previously set — keep it visible
            -- (e.g. anchor target may not be registered yet)
            dropdown.selected:SetText(tostring(currentVal))
        elseif not found then
            dropdown.selected:SetText("")
            container.selectedValue = nil
            if dbTable and dbKey then dbTable[dbKey] = "" end
        end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    -- BindWidgetMethod so `dd:SetOptions(opts)` and `dd.SetOptions(opts)`
    -- both work; without it, a colon-call passes the container itself as
    -- `newOptions` and silently empties the menu.
    container.SetOptions = BindWidgetMethod(container, SetOptions)
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "dropdown", label, dbKey, dbTable, dropdown, registryInfo)

    SetValue(GetValue(), true)

    -- Enable/disable the dropdown (for conditional UI)
    container.SetEnabled = function(self, enabled)
        dropdown:EnableMouse(enabled)
        container.isEnabled = enabled
        container:SetAlpha(enabled and 1 or 0.4)
    end
    container.isEnabled = true

    GUI:RegisterSearchSettingWidget({
        label = label,
        widgetType = "dropdown",
        widgetBuilder = function(p)
            return GUI:CreateFormDropdown(p, label, options, dbKey, dbTable, onChange, nil, opts)
        end,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor("dropdown", dbKey, dbTable, {
            options = options,
            dropdownOptions = opts,
        }),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    })

    GUI:AttachTooltip(dropdown, registryInfo and registryInfo.description or nil, label)
    return container
end

function GUI:CreateFormColorPicker(parent, label, dbKey, dbTable, onChange, options, registryInfo)
    options = options or {}
    local noAlpha = options.noAlpha or false
    local UIKit = ns.UIKit
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines

    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label  -- For search jump-to-setting (V2)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    -- Bare mode: label=nil skips the internal label and shrinks container
    -- to just the swatch — V3 BuildSettingRow provides the label.
    local text
    local swatchLeftOffset = 180
    if label then
        container:SetHeight(FORM_ROW_HEIGHT)
        text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 12, "", C.text)
        text:SetText(label)
        text:SetPoint("LEFT", 0, 0)
        text:SetWidth(170)
        text:SetWordWrap(true)
        text:SetNonSpaceWrap(true)
        text:SetJustifyH("LEFT")
    else
        container:SetSize(18, 18)
        swatchLeftOffset = 0
    end

    -- Color swatch
    local swatch = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", container, "LEFT", swatchLeftOffset, 0)
    local px = QUICore:GetPixelSize(swatch)
    if useUIKitBorders then
        swatch.bg = UIKit.CreateBackground(swatch, 1, 1, 1, 1)
        UIKit.CreateBorderLines(swatch)
        UIKit.UpdateBorderLines(swatch, 1, 1, 1, 1, 0.35, false)
    else
        swatch:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        swatch:SetBackdropBorderColor(1, 1, 1, 0.35)
    end

    container.swatch = swatch
    container.label = text

    local function SetSwatchBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(swatch, 1, r, g, b, a or 1, false)
        else
            pcall(swatch.SetBackdropBorderColor, swatch, r, g, b, a or 1)
        end
    end

    local function SetSwatchColor(r, g, b, a)
        if useUIKitBorders then
            if swatch.bg then
                swatch.bg:SetVertexColor(r, g, b, a)
            end
        else
            swatch:SetBackdropColor(r, g, b, a)
        end
    end

    local function GetColor()
        if dbTable and dbKey then
            local c = dbTable[dbKey]
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        end
        return 1, 1, 1, 1
    end

    local function SetColor(r, g, b, a)
        local finalAlpha = noAlpha and 1 or (a or 1)
        SetSwatchColor(r, g, b, finalAlpha)
        local nextValue = {r, g, b, finalAlpha}
        if dbTable and dbKey then
            dbTable[dbKey] = nextValue
        end
        MaybeUpdatePinnedWidgetValue(container, nextValue)
        if onChange then onChange(r, g, b, finalAlpha) end
        BroadcastToSiblings(container, nextValue)
        MaybeAutoNotifyProviderSync(container)
    end

    local function UpdateVisual(val)
        if type(val) == "table" then
            SetSwatchColor(val[1] or 1, val[2] or 1, val[3] or 1, val[4] or 1)
            return
        end
        local r, g, b, a = GetColor()
        SetSwatchColor(r, g, b, a)
    end

    container.GetColor = GetColor
    container.SetColor = SetColor
    container.UpdateVisual = UpdateVisual

    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "color", label, dbKey, dbTable, swatch, registryInfo)

    local r, g, b, a = GetColor()
    SetSwatchColor(r, g, b, a)

    swatch:SetScript("OnClick", function()
        local currentR, currentG, currentB, currentA = GetColor()
        local originalA = currentA
        local function OpenPicker()
            ColorPickerFrame:SetupColorPickerAndShow({
                r = currentR, g = currentG, b = currentB, opacity = currentA,
                hasOpacity = not noAlpha,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = noAlpha and 1 or ColorPickerFrame:GetColorAlpha()
                    SetColor(r, g, b, a)
                end,
                cancelFunc = function(prev)
                    SetColor(prev.r, prev.g, prev.b, noAlpha and 1 or originalA)
                end,
            })
            ColorPickerFrame:SetFrameStrata("TOOLTIP")
            ColorPickerFrame:Raise()
        end
        -- When switching swatches mid-session, the existing picker must finish
        -- its hide cycle (including any cancelFunc side effects) before the new
        -- Setup call, or ShowUIPanel's own toggle logic turns our call into a close.
        if ColorPickerFrame:IsShown() then
            HideUIPanel(ColorPickerFrame)
            C_Timer.After(0, OpenPicker)
        else
            OpenPicker()
        end
    end)

    swatch:HookScript("OnEnter", function() SetSwatchBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    swatch:HookScript("OnLeave", function() SetSwatchBorderColor(1, 1, 1, 0.35) end)

    -- Enable/disable (for conditional UI)
    container.SetEnabled = function(self, enabled)
        swatch:EnableMouse(enabled)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    GUI:RegisterSearchSettingWidget({
        label = label,
        widgetType = "colorpicker",
        widgetBuilder = function(p)
            return GUI:CreateFormColorPicker(p, label, dbKey, dbTable, onChange, options)
        end,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor("colorpicker", dbKey, dbTable, {
            options = options,
        }),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    })

    GUI:AttachTooltip(swatch, registryInfo and registryInfo.description or nil, label)
    return container
end

local CreateFormEditBoxModern = GUI.CreateFormEditBox
local CreateInlineEditBoxModern = GUI.CreateInlineEditBox

---------------------------------------------------------------------------
-- FORM EDIT BOX (single-line text input with label and DB binding)
---------------------------------------------------------------------------
function GUI:CreateFormEditBox(parent, label, dbKey, dbTable, onChange, options, registryInfo)
    if CreateFormEditBoxModern then
        return CreateFormEditBoxModern(self, parent, label, dbKey, dbTable, onChange, options, registryInfo)
    end
    return nil
end

---------------------------------------------------------------------------
-- Inline edit box (lightweight, no label, used inside custom list entries)
---------------------------------------------------------------------------
function GUI:CreateInlineEditBox(parent, options)
    if CreateInlineEditBoxModern then
        return CreateInlineEditBoxModern(self, parent, options)
    end
    return nil
end

---------------------------------------------------------------------------
-- SEARCH FUNCTIONALITY
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Scrollable read-only text box (used by Welcome and Import tabs)
---------------------------------------------------------------------------
function GUI:CreateScrollableTextBox(parent, height, text, options)
    options = options or {}
    local bgColor = options.bgColor or {0.05, 0.07, 0.1, 0.9}
    local borderColor = options.borderColor or C.border
    local fontSize = options.fontSize or 11

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetHeight(height)

    local px = QUICore.GetPixelSize and QUICore:GetPixelSize(container) or 1
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    container:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    container:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

    -- ScrollFrame to hold the EditBox
    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", 6, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 4)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(GetFontPath(), fontSize, "")
    editBox:SetTextColor(0.7, 0.75, 0.8, 1)
    editBox:SetWidth(scrollFrame:GetWidth() or 400)
    editBox:SetText(text or "")
    editBox:SetCursorPosition(0)

    scrollFrame:SetScrollChild(editBox)

    -- Keep editBox width in sync with scrollFrame
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        editBox:SetWidth(w)
    end)

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, editBox:GetHeight() - self:GetHeight())
        local newScroll = math.min(maxScroll, math.max(0, current - delta * 20))
        self:SetVerticalScroll(newScroll)
    end)

    container.editBox = editBox
    container.scrollFrame = scrollFrame
    return container
end

local SEARCH_DEBOUNCE = 0.15  -- 150ms debounce
local SEARCH_MIN_CHARS = 2    -- Minimum characters before searching
local SEARCH_MAX_RESULTS = 30 -- Cap results to prevent UI overload

local function NormalizeSearchText(text)
    text = (text or ""):lower()
    text = text:gsub("[%z\1-\31]", " ")
    text = text:gsub("[_%-%./\\&]+", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function TokenizeSearchText(text)
    local out = {}
    local seen = {}
    for token in NormalizeSearchText(text):gmatch("%S+") do
        if not seen[token] then
            seen[token] = true
            table.insert(out, token)
        end
    end
    return out
end

local function ContainsWholeWord(haystack, needle)
    if haystack == "" or needle == "" then return false end
    return (" " .. haystack .. " "):find(" " .. needle .. " ", 1, true) ~= nil
end

-- Returns true if the Damerau-Levenshtein distance between a and b is <= 1.
-- Cheap for short strings. Does NOT compute the full matrix — early-exits.
local function DL1(a, b)
    local la, lb = #a, #b
    if math.abs(la - lb) > 1 then return false end
    if la == lb then
        -- same length: count mismatches; also allow a single transposition.
        local diffs, firstDiffI = 0, nil
        for i = 1, la do
            if a:byte(i) ~= b:byte(i) then
                diffs = diffs + 1
                if diffs == 1 then firstDiffI = i end
                if diffs > 2 then return false end
            end
        end
        if diffs <= 1 then return true end
        -- diffs == 2: must be an adjacent transposition
        local i = firstDiffI
        return i < la
            and a:byte(i) == b:byte(i + 1)
            and a:byte(i + 1) == b:byte(i)
    end
    -- lengths differ by 1: walk both, allow one skip.
    local s, l = a, b
    if la > lb then s, l = b, a end
    local si, li, skipped = 1, 1, false
    while si <= #s and li <= #l do
        if s:byte(si) == l:byte(li) then
            si = si + 1
            li = li + 1
        elseif not skipped then
            li = li + 1
            skipped = true
        else
            return false
        end
    end
    return true
end

local function BuildSearchTerms(searchTerm)
    local synExpand = ns.QUI_SearchSynonyms and ns.QUI_SearchSynonyms.Expand
    local raw = (searchTerm or ""):lower()
    local normalized = NormalizeSearchText(searchTerm)
    local seen = {}
    local out = {}

    local function AddTerm(term, penalty)
        local rawTerm = (term or ""):lower()
        local normalizedTerm = NormalizeSearchText(term)
        if rawTerm == "" and normalizedTerm == "" then return end

        local key = rawTerm .. "\31" .. normalizedTerm
        if seen[key] then return end
        seen[key] = true

        table.insert(out, {
            raw = rawTerm,
            normalized = normalizedTerm,
            tokens = TokenizeSearchText(term),
            penalty = penalty or 1.0,
        })
    end

    AddTerm(searchTerm, 1.0)
    if normalized ~= "" and normalized ~= raw then
        AddTerm(normalized, 1.0)
    end

    local expanded = synExpand and synExpand(normalized ~= "" and normalized or raw) or { normalized ~= "" and normalized or raw }
    for idx, term in ipairs(expanded) do
        AddTerm(term, idx == 1 and 1.0 or 0.82)
    end

    return out
end

local function ScoreSearchText(text, term)
    local rawText = (text or ""):lower()
    if rawText == "" or not term then return 0 end

    local normalizedText = NormalizeSearchText(text)
    local score = 0

    if term.raw ~= "" then
        if rawText == term.raw then
            score = math.max(score, 260)
        end
        if rawText:sub(1, #term.raw) == term.raw then
            score = math.max(score, 225)
        end
        if rawText:find(term.raw, 1, true) then
            score = math.max(score, 170)
        end
    end

    if term.normalized ~= "" then
        if normalizedText == term.normalized then
            score = math.max(score, 250)
        end
        if normalizedText:sub(1, #term.normalized) == term.normalized then
            score = math.max(score, 220)
        end
        if normalizedText:find(term.normalized, 1, true) then
            score = math.max(score, 165)
        end

        local tokenHits = 0
        local allTokens = (#term.tokens > 0)
        for _, token in ipairs(term.tokens) do
            if ContainsWholeWord(normalizedText, token) then
                tokenHits = tokenHits + 1
            else
                allTokens = false
            end
        end
        if allTokens and #term.tokens > 0 then
            score = math.max(score, 210 + math.min(#term.tokens, 4) * 6)
        elseif tokenHits > 0 and #term.tokens == 1 then
            -- Multi-token queries require all tokens — otherwise
            -- "action tracker" matches every entry containing just
            -- "action" or just "tracker". This branch only ever fires
            -- for single-token queries because allTokens is true when
            -- the only token matches. Kept for symmetry / future use.
            score = math.max(score, 110 + tokenHits * 8)
        end

        if score == 0 and #term.tokens == 1 and #term.normalized >= 4 then
            for token in normalizedText:gmatch("%S+") do
                if DL1(term.normalized, token) then
                    score = math.max(score, 60)
                    break
                end
            end
        end
    end

    return score * (term.penalty or 1.0)
end

local function BuildMergedSearchIdentity(gui, entry)
    if type(entry) ~= "table" then
        return ""
    end

    local crumbText = ""
    if gui and type(gui.GetSearchBreadcrumb) == "function" then
        local crumb = gui:GetSearchBreadcrumb(entry)
        if type(crumb) == "table" and #crumb > 0 then
            crumbText = table.concat(crumb, " ")
        end
    end

    if crumbText == "" then
        local parts = {}
        if entry.tileId and entry.tileId ~= "" then
            parts[#parts + 1] = entry.tileId
        end
        if entry.subPageIndex then
            parts[#parts + 1] = tostring(entry.subPageIndex)
        end
        if entry.tabName and entry.tabName ~= "" then
            parts[#parts + 1] = entry.tabName
        end
        if entry.subTabName and entry.subTabName ~= "" then
            parts[#parts + 1] = entry.subTabName
        end
        if entry.sectionName and entry.sectionName ~= "" then
            parts[#parts + 1] = entry.sectionName
        end
        crumbText = table.concat(parts, " ")
    end

    return NormalizeSearchText((entry.label or "") .. "\31" .. crumbText)
end

local function MergeSearchHit(gui, mergedResults, mergedByKey, entry, score)
    if type(entry) ~= "table" or type(score) ~= "number" or score <= 0 then
        return
    end

    local key = BuildMergedSearchIdentity(gui, entry)
    if key == "" then
        key = NormalizeSearchText(entry.label or "")
    end

    local existing = mergedByKey[key]
    if not existing then
        local stored = { data = CopySearchRegistryEntry(entry), score = score }
        mergedByKey[key] = stored
        table.insert(mergedResults, stored)
        return
    end

    if score > existing.score then
        existing.score = score
    end

    local current = existing.data
    if entry.widgetBuilder and not current.widgetBuilder then
        local replacement = CopySearchRegistryEntry(entry)
        if replacement.tileId == nil then replacement.tileId = current.tileId end
        if replacement.subPageIndex == nil then replacement.subPageIndex = current.subPageIndex end
        if replacement.tabName == nil or replacement.tabName == "" then replacement.tabName = current.tabName end
        if replacement.subTabName == nil or replacement.subTabName == "" then replacement.subTabName = current.subTabName end
        if replacement.sectionName == nil or replacement.sectionName == "" then replacement.sectionName = current.sectionName end
        if replacement.keywords == nil then replacement.keywords = current.keywords end
        if replacement.description == nil then replacement.description = current.description end
        existing.data = replacement
        current = replacement
    end

    if (not current.tileId or current.tileId == "") and entry.tileId and entry.tileId ~= "" then
        current.tileId = entry.tileId
    end
    if current.subPageIndex == nil and entry.subPageIndex ~= nil then
        current.subPageIndex = entry.subPageIndex
    end
    if (not current.tabName or current.tabName == "") and entry.tabName and entry.tabName ~= "" then
        current.tabName = entry.tabName
    end
    if (not current.subTabName or current.subTabName == "") and entry.subTabName and entry.subTabName ~= "" then
        current.subTabName = entry.subTabName
    end
    if (not current.sectionName or current.sectionName == "") and entry.sectionName and entry.sectionName ~= "" then
        current.sectionName = entry.sectionName
    end
    if current.keywords == nil and entry.keywords ~= nil then
        current.keywords = entry.keywords
    end
    if current.description == nil and entry.description ~= nil then
        current.description = entry.description
    end
end

-- Search timer reference (for cleanup)
GUI._searchTimer = nil

-- Create the search box widget for the top bar
function GUI:CreateSearchBox(parent, placeholderText)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(160, 28)

    -- V3 visuals: white bg @ 6% + pixel border lines @ 20%
    if UIKit and UIKit.CreateBackground then
        UIKit.CreateBackground(container, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
    end
    if UIKit and UIKit.CreateBorderLines and not container._pixelBorderReady then
        UIKit.CreateBorderLines(container)
        container._pixelBorderReady = true
    end
    if UIKit and UIKit.UpdateBorderLines then
        UIKit.UpdateBorderLines(container, 1, 1, 1, 1, 0.2)
    end

    -- Magnifier icon (texture, not glyph — Friz Quadrata can't render Unicode)
    local icon = container:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", container, "LEFT", 8, 0)
    local atlasOk = pcall(function() icon:SetAtlas("common-search-magnifier") end)
    if not atlasOk or not icon:GetAtlas() then
        icon:SetTexture("Interface\\FriendsFrame\\UI-Searchbox-Icon")
    end
    icon:SetVertexColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    container._icon = icon

    -- EditBox for search input
    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    editBox:SetPoint("RIGHT", container, "RIGHT", -24, 0)
    editBox:SetHeight(16)
    editBox:SetAutoFocus(false)
    editBox:SetFont(GetFontPath(), 10, "")
    editBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    editBox:SetMaxLetters(50)

    -- Expose the EditBox so consumers can reach it for SetText / ClearFocus
    -- without knowing the internal layout (the function returns the container
    -- frame, which doesn't itself have EditBox methods).
    container._editBox = editBox

    -- Placeholder text
    local placeholder = editBox:CreateFontString(nil, "OVERLAY")
    SetFont(placeholder, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 1})
    placeholder:SetText(placeholderText or "Search settings...")
    placeholder:SetPoint("LEFT", 0, 0)

    -- Clear button (X)
    local clearBtn = CreateFrame("Button", nil, container)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", -4, 0)
    clearBtn:Hide()

    local clearText = clearBtn:CreateFontString(nil, "OVERLAY")
    SetFont(clearText, 12, "", C.textMuted)
    clearText:SetText("x")
    clearText:SetPoint("CENTER", 0, 0)

    clearBtn:SetScript("OnEnter", function()
        clearText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end)
    clearBtn:SetScript("OnLeave", function()
        clearText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    end)
    clearBtn:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:ClearFocus()
        -- SetText fires OnTextChanged with userInput=false, which only
        -- updates placeholder/clear-button visibility and returns before
        -- dispatching onClear. Invoke it directly so the consumer's
        -- filter state is reset.
        if container.onClear then
            container.onClear()
        end
    end)

    -- Text changed handler with debounce
    editBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()

        -- Show/hide placeholder and clear button. Done unconditionally so
        -- programmatic SetText("") (e.g. sidebar nav clearing the search)
        -- restores the placeholder, not just user typing.
        placeholder:SetShown(text == "")
        clearBtn:SetShown(text ~= "")

        if not userInput then return end

        -- Cancel pending search timer
        if GUI._searchTimer then
            GUI._searchTimer:Cancel()
            GUI._searchTimer = nil
        end

        -- Debounce search execution (handled by parent via onSearch callback)
        if text:len() >= SEARCH_MIN_CHARS then
            GUI._searchTimer = C_Timer.NewTimer(SEARCH_DEBOUNCE, function()
                if container.onSearch then
                    container.onSearch(text)
                end
            end)
        else
            if container.onClear then
                container.onClear()
            end
        end
    end)

    -- Focus effects
    editBox:SetScript("OnEditFocusGained", function(self)
        container:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        -- "Back to results": if the search box still has a term (e.g. user
        -- clicked a result and is now on the navigated tile), focusing the
        -- search bar re-opens the results overlay.
        local text = self:GetText()
        if text and text:len() >= SEARCH_MIN_CHARS and container.onSearch then
            container.onSearch(text)
        end
    end)
    editBox:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(0.25, 0.28, 0.32, 1)
    end)
    editBox:HookScript("OnEditFocusGained", function()
        if UIKit and UIKit.UpdateBorderLines then
            UIKit.UpdateBorderLines(container, 1, C.borderAccent[1], C.borderAccent[2], C.borderAccent[3], 1)
        end
    end)
    editBox:HookScript("OnEditFocusLost", function()
        if UIKit and UIKit.UpdateBorderLines then
            UIKit.UpdateBorderLines(container, 1, 1, 1, 1, 0.2)
        end
    end)

    -- ESC clears search
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        if container.onClear then
            container.onClear()
        end
    end)

    -- Enter also clears focus (search already happened via debounce)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    container.editBox = editBox
    container.placeholder = placeholder
    container.clearBtn = clearBtn

    return container
end

-- Execute search against the settings registry (returns filtered results)
function GUI:ExecuteSearch(searchTerm)
    if not searchTerm or searchTerm:len() < SEARCH_MIN_CHARS then
        return {}, {}
    end

    local results = {}
    local navResults = {}
    local searchTerms = BuildSearchTerms(searchTerm)

    local function ScoreEntry(entry, keywordWeight, contextWeight)
        local bestScore = 0
        for _, term in ipairs(searchTerms) do
            local score = ScoreSearchText(entry.label, term)
            if entry.keywords then
                for _, keyword in ipairs(entry.keywords) do
                    score = math.max(score, ScoreSearchText(keyword, term) * keywordWeight)
                end
            end
            if contextWeight and (entry.tabName or entry.subTabName or entry.sectionName) then
                local contextText = table.concat({
                    entry.tabName or "",
                    entry.subTabName or "",
                    entry.sectionName or "",
                }, " ")
                score = math.max(score, ScoreSearchText(contextText, term) * contextWeight)
            end
            bestScore = math.max(bestScore, score)
        end
        return bestScore
    end

    local mergedNavResults = {}
    local mergedNavByKey = {}
    for _, registry in ipairs({
        self.StaticNavigationRegistry or {},
        self.NavigationRegistry or {},
    }) do
        for _, entry in ipairs(registry) do
            MergeSearchHit(self, mergedNavResults, mergedNavByKey, entry, ScoreEntry(entry, 0.9))
        end
    end

    -- Sort navigation results by score, then specificity.
    table.sort(mergedNavResults, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        local typeOrder = {section = 1, subtab = 2, tab = 3}
        local aOrder = typeOrder[a.data.navType] or 4
        local bOrder = typeOrder[b.data.navType] or 4
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        return (a.data.label or "") < (b.data.label or "")
    end)

    local mergedSettingsResults = {}
    local mergedSettingsByKey = {}
    for _, registry in ipairs({
        self.StaticSettingsRegistry or {},
        self.SettingsRegistry or {},
    }) do
        for _, entry in ipairs(registry) do
            MergeSearchHit(self, mergedSettingsResults, mergedSettingsByKey, entry, ScoreEntry(entry, 0.72, 0.45))
        end
    end

    -- Sort settings results by score (highest first), then alphabetically
    table.sort(mergedSettingsResults, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return (a.data.label or "") < (b.data.label or "")
    end)

    -- Limit settings results
    if #mergedSettingsResults > SEARCH_MAX_RESULTS then
        for i = SEARCH_MAX_RESULTS + 1, #mergedSettingsResults do
            mergedSettingsResults[i] = nil
        end
    end

    -- Limit navigation results (keep fewer since they're shown prominently)
    local NAV_MAX_RESULTS = 10
    if #mergedNavResults > NAV_MAX_RESULTS then
        for i = NAV_MAX_RESULTS + 1, #mergedNavResults do
            mergedNavResults[i] = nil
        end
    end

    for _, result in ipairs(mergedSettingsResults) do
        table.insert(results, result)
    end
    for _, result in ipairs(mergedNavResults) do
        result.isNavigation = true
        table.insert(navResults, result)
    end

    return results, navResults
end

function GUI:HandleSearchDescriptorChange(descriptor)
    if type(descriptor) ~= "table" then
        return
    end

    local settings = ns.Settings
    local registry = settings and settings.Registry
    local feature = registry
        and type(registry.GetFeature) == "function"
        and descriptor.featureId
        and registry:GetFeature(descriptor.featureId)
        or nil

    if feature and type(feature.apply) == "function" then
        pcall(feature.apply)
    end

    local compat = settings and settings.RenderAdapters
    if descriptor.providerKey
        and compat
        and type(compat.NotifyProviderChanged) == "function" then
        compat.NotifyProviderChanged(descriptor.providerKey, { source = "search" })
    end

    if feature and feature.category and ns.Registry and type(ns.Registry.RefreshAll) == "function" then
        ns.Registry:RefreshAll(feature.category)
    end
end

function GUI:CreateSearchWidgetFromDescriptor(parent, entry)
    local descriptor = entry and entry.widgetDescriptor
    if type(descriptor) ~= "table" then
        return nil
    end

    local dbTable = self:ResolveSearchDBTable(descriptor.dbPath)
    if not dbTable then
        return nil
    end

    local label = entry.label
    local registryInfo = {
        keywords = entry.keywords,
        description = entry.description,
        relatedTo = entry.relatedTo,
    }

    if descriptor.kind == "toggle" then
        return self:CreateFormToggle(parent, label, descriptor.dbKey, dbTable, function()
            GUI:HandleSearchDescriptorChange(descriptor)
        end, registryInfo)
    end

    if descriptor.kind == "toggle_inverted" then
        return self:CreateFormToggleInverted(parent, label, descriptor.dbKey, dbTable, function()
            GUI:HandleSearchDescriptorChange(descriptor)
        end, registryInfo)
    end

    if descriptor.kind == "editbox" then
        return self:CreateFormEditBox(parent, label, descriptor.dbKey, dbTable, function()
            GUI:HandleSearchDescriptorChange(descriptor)
        end, descriptor.options or {}, registryInfo)
    end

    if descriptor.kind == "slider" then
        return self:CreateFormSlider(
            parent,
            label,
            descriptor.min,
            descriptor.max,
            descriptor.step,
            descriptor.dbKey,
            dbTable,
            function()
                GUI:HandleSearchDescriptorChange(descriptor)
            end,
            descriptor.options or {},
            registryInfo
        )
    end

    if descriptor.kind == "dropdown" and type(descriptor.options) == "table" then
        return self:CreateFormDropdown(
            parent,
            label,
            descriptor.options,
            descriptor.dbKey,
            dbTable,
            function()
                GUI:HandleSearchDescriptorChange(descriptor)
            end,
            registryInfo,
            descriptor.dropdownOptions or {}
        )
    end

    if descriptor.kind == "colorpicker" then
        return self:CreateFormColorPicker(
            parent,
            label,
            descriptor.dbKey,
            dbTable,
            function()
                GUI:HandleSearchDescriptorChange(descriptor)
            end,
            descriptor.options or {},
            registryInfo
        )
    end

    return nil
end

-- Render search results into a content frame (for Search tab)
function GUI:RenderSearchResults(content, results, searchTerm, navResults)
    if not content then return end

    if GUI.TeardownFrameTree then
        GUI:TeardownFrameTree(content)
    else
        -- Snapshot children before mutating: SetParent(nil) removes children
        -- from the list mid-iteration, causing select() to return nil.
        local kids = { content:GetChildren() }
        for _, child in ipairs(kids) do
            UnregisterWidgetInstance(child)
            child:Hide()
            child:SetParent(nil)
        end
    end

    -- Clear previous font strings
    if content._fontStrings then
        for _, fs in ipairs(content._fontStrings) do
            fs:Hide()
            fs:SetText("")
        end
    end
    content._fontStrings = {}

    -- Clear previous textures
    if content._textures then
        for _, tex in ipairs(content._textures) do
            tex:Hide()
        end
    end
    content._textures = {}

    -- Clear previous breadcrumb click buttons (search jump-to-setting)
    if content._clickButtons then
        for _, btn in ipairs(content._clickButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
    end
    content._clickButtons = {}

    local y = -10
    local PADDING = 15
    local FORM_ROW = 32

    -- Check if we have any results at all (either settings or navigation)
    local hasResults = (results and #results > 0) or (navResults and #navResults > 0)

    -- No results message
    if not hasResults then
        if searchTerm and searchTerm ~= "" then
            local noResults = content:CreateFontString(nil, "OVERLAY")
            SetFont(noResults, 12, "", C.textMuted)
            noResults:SetText("No settings match \"" .. searchTerm .. "\"")
            noResults:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, noResults)
            y = y - 30

            local tip = content:CreateFontString(nil, "OVERLAY")
            SetFont(tip, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7})
            tip:SetText("Try different keywords")
            tip:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, tip)
            y = y - 30
        else
            local instructions = content:CreateFontString(nil, "OVERLAY")
            SetFont(instructions, 12, "", C.textMuted)
            instructions:SetText("Search settings — try 'cooldown', 'party', 'action bars'")
            instructions:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, instructions)
            y = y - 20

            local hint = content:CreateFontString(nil, "OVERLAY")
            SetFont(hint, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.6})
            hint:SetText("Shortcut: / or Ctrl+F to focus")
            hint:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, hint)
            y = y - 20
        end

        content:SetHeight(math.abs(y) + 20)
        return
    end

    -- Render navigation results first (tabs, subtabs, sections)
    if navResults and #navResults > 0 then
        local navHeader = content:CreateFontString(nil, "OVERLAY")
        SetFont(navHeader, 11, "", C.textMuted)
        navHeader:SetText("Categories & Sections")
        navHeader:SetPoint("TOPLEFT", PADDING, y)
        table.insert(content._fontStrings, navHeader)
        y = y - 20

        for _, navResult in ipairs(navResults) do
            local entry = navResult.data

            -- Create navigation row container
            local navRow = CreateFrame("Button", nil, content, "BackdropTemplate")
            navRow:SetSize(content:GetWidth() - (PADDING * 2), 26)
            navRow:SetPoint("TOPLEFT", PADDING, y)
            local navPx = QUICore:GetPixelSize(navRow)
            navRow:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = navPx,
            })
            navRow:SetBackdropColor(0.12, 0.14, 0.17, 0.8)
            navRow:SetBackdropBorderColor(0.2, 0.22, 0.25, 0.6)

            -- Type icon/badge
            local typeBadge = navRow:CreateFontString(nil, "OVERLAY")
            SetFont(typeBadge, 9, "", C.textMuted)
            local typeLabels = {tab = "TAB", subtab = "SUBTAB", section = "SECTION"}
            typeBadge:SetText(typeLabels[entry.navType] or "NAV")
            typeBadge:SetPoint("LEFT", 8, 0)

            -- Navigation label
            local navLabel = navRow:CreateFontString(nil, "OVERLAY")
            SetFont(navLabel, 11, "", C.text)
            navLabel:SetText(entry.label or "")
            navLabel:SetPoint("LEFT", typeBadge, "RIGHT", 10, 0)
            navLabel:SetPoint("RIGHT", navRow, "RIGHT", -50, 0)
            navLabel:SetJustifyH("LEFT")
            navLabel:SetWordWrap(false)

            -- Go button
            local goText = navRow:CreateFontString(nil, "OVERLAY")
            SetFont(goText, 10, "", C.accent)
            goText:SetText("Go >")
            goText:SetPoint("RIGHT", -10, 0)

            -- Hover effects
            navRow:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
            end)
            navRow:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.12, 0.14, 0.17, 0.8)
                self:SetBackdropBorderColor(0.2, 0.22, 0.25, 0.6)
            end)

            -- Click to navigate. Pass the entry through verbatim — losing
            -- tileId / subPageIndex / featureId / navType here breaks v2
            -- routing and the section-anchor scroll-to-feature path.
            navRow:SetScript("OnClick", function()
                GUI:NavigateSearchResult(entry)
            end)

            y = y - 30
        end

        y = y - 10  -- Gap before settings results

        -- Separator between navigation and settings
        if results and #results > 0 then
            local sep = content:CreateTexture(nil, "ARTWORK")
            sep:SetPoint("TOPLEFT", PADDING, y + 5)
            sep:SetSize(content:GetWidth() - (PADDING * 2), 1)
            sep:SetColorTexture(0.3, 0.32, 0.35, 0.5)
            table.insert(content._textures, sep)
            y = y - 15
        end
    end

    -- Skip settings rendering if no settings results
    if not results or #results == 0 then
        content:SetHeight(math.abs(y) + 20)
        return
    end

    -- Build composite group key from available metadata. Translate the
    -- registered tab/subtab names through the nav map to tile/sub-page
    -- names so headers reflect the current sidebar taxonomy.
    local function GetGroupKey(entry)
        if GUI.GetSearchBreadcrumb then
            local v2 = GUI:GetSearchBreadcrumb(entry)
            if v2 and #v2 > 0 then return table.concat(v2, " > ") end
        end
        local parts = {entry.tabName or "Other"}
        if entry.subTabName and entry.subTabName ~= "" then
            table.insert(parts, entry.subTabName)
        end
        if entry.sectionName and entry.sectionName ~= "" then
            table.insert(parts, entry.sectionName)
        end
        return table.concat(parts, " > ")
    end

    -- Group results by composite key
    local groupedResults = {}
    local tabOrder = {}

    for _, result in ipairs(results) do
        local groupKey = GetGroupKey(result.data)
        if not groupedResults[groupKey] then
            groupedResults[groupKey] = {entries = {}, data = result.data}
            table.insert(tabOrder, groupKey)
        end
        table.insert(groupedResults[groupKey].entries, result)
    end

    -- Suppress auto-registration while creating search result widgets
    GUI._suppressSearchRegistration = true

    local function RenderGroupedResults()
    for _, groupKey in ipairs(tabOrder) do
        local group = groupedResults[groupKey]
        local groupData = group.data

        -- Group header
        local header = content:CreateFontString(nil, "OVERLAY")
        SetFont(header, 12, "", C.accentLight)
        header:SetText(groupKey)
        header:SetPoint("TOPLEFT", PADDING, y)
        table.insert(content._fontStrings, header)

        -- "Go >" navigation button
        if GUI.ResolveSearchNavigation and GUI:ResolveSearchNavigation(groupData) then
            local goBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
            goBtn:SetSize(36, 16)
            goBtn:SetPoint("LEFT", header, "RIGHT", 8, 0)
            local goPx = QUICore:GetPixelSize(goBtn)
            goBtn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = goPx,
            })
            goBtn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
            goBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

            local btnText = goBtn:CreateFontString(nil, "OVERLAY")
            SetFont(btnText, 9, "", C.accent)
            btnText:SetText("Go >")
            btnText:SetPoint("CENTER", 0, 0)

            goBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.3)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
            end)
            goBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
            end)

            local clickEntry = groupData
            goBtn:SetScript("OnClick", function()
                GUI:NavigateSearchResult(clickEntry)
            end)
        end

        y = y - 24

        -- Separator line under header
        local sep = content:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("TOPLEFT", PADDING, y + 2)
        sep:SetSize(content:GetWidth() - (PADDING * 2), 1)
        sep:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        table.insert(content._textures, sep)
        y = y - 12

        -- Results in this group - create actual widgets
        for _, result in ipairs(group.entries) do
            local entry = result.data

            local widget = nil
            if entry.widgetBuilder or entry.widgetDescriptor then
                -- Breadcrumb: "Tile » Sub-page » Section" above the widget.
                -- In V2, prefer names from the V2 tile/sub-page taxonomy.
                local crumbParts
                if GUI.GetSearchBreadcrumb then
                    crumbParts = GUI:GetSearchBreadcrumb(entry)
                end
                if not crumbParts then
                    crumbParts = {}
                    if entry.tabName and entry.tabName ~= "" then
                        table.insert(crumbParts, entry.tabName)
                    end
                    if entry.subTabName and entry.subTabName ~= "" then
                        table.insert(crumbParts, entry.subTabName)
                    end
                    if entry.sectionName and entry.sectionName ~= "" then
                        table.insert(crumbParts, entry.sectionName)
                    end
                end
                local crumbText = table.concat(crumbParts, " \194\187 ")

                local CRUMB_HEIGHT = 14
                local DESC_HEIGHT = 16

                if crumbText ~= "" then
                    local crumbBtn = CreateFrame("Button", nil, content)
                    crumbBtn:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING + 4, y - 2)
                    crumbBtn:SetHeight(14)
                    crumbBtn:SetWidth(content:GetWidth() - (PADDING * 2) - 8)

                    local crumb = crumbBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    crumb:SetPoint("LEFT", crumbBtn, "LEFT", 0, 0)
                    crumb:SetText(crumbText)
                    crumb:SetTextColor(0.55, 0.55, 0.6, 1)
                    crumb:SetJustifyH("LEFT")

                    crumbBtn:SetScript("OnEnter", function() crumb:SetTextColor(1, 1, 1, 1) end)
                    crumbBtn:SetScript("OnLeave", function() crumb:SetTextColor(0.55, 0.55, 0.6, 1) end)

                    local clickEntry = entry
                    crumbBtn:SetScript("OnClick", function()
                        GUI:NavigateSearchResult(clickEntry, {
                            scrollToLabel = clickEntry.label,
                            pulse = true,
                        })
                    end)

                    table.insert(content._fontStrings, crumb)
                    table.insert(content._clickButtons, crumbBtn)
                    y = y - CRUMB_HEIGHT
                end

                if entry.widgetBuilder then
                    widget = entry.widgetBuilder(content)
                else
                    widget = GUI:CreateSearchWidgetFromDescriptor(content, entry)
                end
                if widget then
                    widget:SetPoint("TOPLEFT", PADDING, y)
                    widget:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
                    y = y - FORM_ROW
                end

                -- Description: muted one-liner under the widget
                if entry.description and entry.description ~= "" then
                    local desc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    desc:SetPoint("TOPLEFT", PADDING + 4, y)
                    desc:SetPoint("RIGHT", content, "RIGHT", -(PADDING + 4), 0)
                    desc:SetText(entry.description)
                    desc:SetTextColor(0.7, 0.7, 0.72, 1)
                    desc:SetJustifyH("LEFT")
                    desc:SetWordWrap(true)
                    table.insert(content._fontStrings, desc)
                    y = y - DESC_HEIGHT
                end
            end

            if not widget then
                local hasRoute = GUI.ResolveSearchNavigation and GUI:ResolveSearchNavigation(entry)
                if hasRoute then
                    local fallbackRow = CreateFrame("Button", nil, content, "BackdropTemplate")
                    fallbackRow:SetSize(content:GetWidth() - (PADDING * 2), 24)
                    fallbackRow:SetPoint("TOPLEFT", PADDING, y)
                    local rowPx = QUICore:GetPixelSize(fallbackRow)
                    fallbackRow:SetBackdrop({
                        bgFile = "Interface\\BUTTONS\\WHITE8X8",
                        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                        edgeSize = rowPx,
                    })
                    fallbackRow:SetBackdropColor(0.12, 0.14, 0.17, 0.55)
                    fallbackRow:SetBackdropBorderColor(0.2, 0.22, 0.25, 0.45)

                    local fallbackLabel = fallbackRow:CreateFontString(nil, "OVERLAY")
                    SetFont(fallbackLabel, 11, "", C.textMuted)
                    fallbackLabel:SetPoint("LEFT", 8, 0)
                    fallbackLabel:SetPoint("RIGHT", -8, 0)
                    fallbackLabel:SetJustifyH("LEFT")
                    fallbackLabel:SetText(entry.label or "Unknown setting")

                    fallbackRow:SetScript("OnEnter", function(self)
                        self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
                        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.45)
                        fallbackLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                    end)
                    fallbackRow:SetScript("OnLeave", function(self)
                        self:SetBackdropColor(0.12, 0.14, 0.17, 0.55)
                        self:SetBackdropBorderColor(0.2, 0.22, 0.25, 0.45)
                        fallbackLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
                    end)
                    fallbackRow:SetScript("OnClick", function()
                        GUI:NavigateSearchResult(entry, {
                            scrollToLabel = entry.label,
                            pulse = true,
                        })
                    end)
                    y = y - 28
                else
                    -- Fallback: show label if no builder
                    local fallbackLabel = content:CreateFontString(nil, "OVERLAY")
                    SetFont(fallbackLabel, 11, "", C.textMuted)
                    fallbackLabel:SetText(entry.label or "Unknown setting")
                    fallbackLabel:SetPoint("TOPLEFT", PADDING, y)
                    table.insert(content._fontStrings, fallbackLabel)
                    y = y - 24
                end
            end
        end

        y = y - 10  -- Gap between groups
    end
    end

    local ok, err = xpcall(RenderGroupedResults, geterrorhandler and geterrorhandler() or debug.traceback)

    -- Re-enable auto-registration (guaranteed even if widget builder errored)
    GUI._suppressSearchRegistration = false

    if not ok then
        local errorRow = CreateFrame("Frame", nil, content, "BackdropTemplate")
        errorRow:SetSize(content:GetWidth() - (PADDING * 2), 28)
        errorRow:SetPoint("TOPLEFT", PADDING, y)
        local rowPx = QUICore:GetPixelSize(errorRow)
        errorRow:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = rowPx,
        })
        errorRow:SetBackdropColor(0.25, 0.05, 0.05, 0.75)
        errorRow:SetBackdropBorderColor(1, 0.25, 0.25, 0.65)

        local label = errorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        SetFont(label, 11, "", {1, 0.45, 0.45, 1})
        label:SetPoint("LEFT", errorRow, "LEFT", 8, 0)
        label:SetPoint("RIGHT", errorRow, "RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetText("Some search results failed to render. Check the Lua error log.")
        table.insert(content._fontStrings, label)
        y = y - 32
    end

    content:SetHeight(math.abs(y) + 20)
end

-- Clear search results display
function GUI:ClearSearchInTab(content)
    self:RenderSearchResults(content, nil, nil, nil)
end


---------------------------------------------------------------------------
-- MAIN OPTIONS FRAME
---------------------------------------------------------------------------
function GUI:CreateMainFrame()
    if self.MainFrame then
        return self.MainFrame
    end

    -- Rebuild section navigation state from scratch for each fresh panel build.
    -- This prevents stale third-level sidebar entries from older tab layouts
    -- from leaking into the current options tree.
    self.SectionRegistry = {}
    self.SectionRegistryOrder = {}
    self:ClearSearchContext()

    -- Initialize accent colors from saved DB before creating any widgets
    local db = QUI.QUICore and QUI.QUICore.db
    local profile = db and db.profile
    local general = profile and profile.general
    local preset = general and general.themePreset
    if preset and GUI.ResolveThemePreset then
        local r, g, b = GUI:ResolveThemePreset(preset)
        GUI:ApplyAccentColor(r, g, b)
    else
        local accentDB = general and general.addonAccentColor
        if accentDB and accentDB[1] and accentDB[2] and accentDB[3] then
            GUI:ApplyAccentColor(accentDB[1], accentDB[2], accentDB[3])
        end
    end

    local FRAME_WIDTH = GUI.PANEL_WIDTH
    local FRAME_HEIGHT = 850
    local SIDEBAR_W = GUI.SIDEBAR_WIDTH
    local SIDEBAR_ITEM_H = 26
    local SIDEBAR_ITEM_SPACING = 2

    -- Load saved width first (clamp to new minimum)
    local savedWidth = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile.configPanelWidth or FRAME_WIDTH
    if savedWidth < 750 then savedWidth = 750 end  -- Migration: clamp old narrow panels

    local frame = CreateFrame("Frame", "QUI_Options", UIParent)
    frame:SetSize(savedWidth, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(500)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:Hide()

    -- Apply saved panel alpha
    local savedAlpha = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile.configPanelAlpha or 0.97
    frame._bg = UIKit.CreateBackground(frame, C.bg[1], C.bg[2], C.bg[3], savedAlpha)
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, 1, C.border[1], C.border[2], C.border[3], C.border[4] or 1)

    self.MainFrame = frame

    -- ESC to close the settings panel
    if not tContains(UISpecialFrames, "QUI_Options") then
        tinsert(UISpecialFrames, "QUI_Options")
    end

    -- Note: Registry is NOT cleared on show - deduplication keys prevent duplicates
    -- when tabs are re-clicked. Registry persists to allow searching across all visited tabs.

    -- Title bar area (draggable)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(50)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- Title bar with title on left, version/close on right (single line)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(title, 14, "OUTLINE", C.accentLight)
    title:SetText("QUI")
    title:SetPoint("TOPLEFT", 12, -10)

    -- Version text (accent colored, to the left of close button)
    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(version, 11, "", C.accentLight)
    local versionText = (QUI and QUI.versionString) or C_AddOns.GetAddOnMetadata("QUI", "Version") or "2.xx"
    version:SetText("v" .. versionText)
    version:SetPoint("TOPRIGHT", -40, -10)

    -- Forward-declare thumb (created with scale slider below, but referenced in accent callbacks)
    local thumb

    -- Accent Color swatch (parented to titleBar so it receives clicks above the drag region)
    local accentSwatch = CreateFrame("Button", nil, titleBar)
    accentSwatch:SetSize(14, 14)
    accentSwatch:SetPoint("TOPLEFT", titleBar, "TOPLEFT", SIDEBAR_W + 14, -8)
    accentSwatch._bg = UIKit.CreateBackground(accentSwatch, C.accent[1], C.accent[2], C.accent[3], 1)
    UIKit.CreateBorderLines(accentSwatch)
    UIKit.UpdateBorderLines(accentSwatch, 1, 0.4, 0.4, 0.4, 1)

    -- Helper to refresh all skinned in-game elements
    local function RefreshAllSkinning()
        if ns.Registry then
            ns.Registry:RefreshAll("skinning")
        end
        if _G.QUI_RefreshStatusTrackingBarSkin then _G.QUI_RefreshStatusTrackingBarSkin() end
    end

    -- Helper to apply accent color to header elements + theme + skinning
    local function ApplyAccentToAll(r, g, b)
        GUI:ApplyAccentColor(r, g, b)
        accentSwatch._bg:SetVertexColor(r, g, b, 1)
        title:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
        version:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
        RefreshAllSkinning()
    end

    -- Theme preset dropdown
    local themeLabel = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(themeLabel, 10, "", C.textMuted)
    themeLabel:SetText("Theme")
    themeLabel:SetPoint("LEFT", accentSwatch, "RIGHT", 4, 0)

    local themeDropBtn = CreateFrame("Button", nil, titleBar)
    themeDropBtn:SetSize(110, 16)
    themeDropBtn:SetPoint("LEFT", themeLabel, "RIGHT", 6, 0)
    UIKit.CreateBackground(themeDropBtn, 0.1, 0.1, 0.1, 0.8)
    UIKit.CreateBorderLines(themeDropBtn)
    UIKit.UpdateBorderLines(themeDropBtn, 1, 0.3, 0.3, 0.3, 1)

    local themeDropText = themeDropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(themeDropText, 10, "", C.text)
    themeDropText:SetPoint("LEFT", 4, 0)
    themeDropText:SetPoint("RIGHT", -14, 0)
    themeDropText:SetJustifyH("LEFT")
    themeDropText:SetWordWrap(false)

    local themeDropArrow = themeDropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(themeDropArrow, 8, "", C.textMuted)
    themeDropArrow:SetText("v")
    themeDropArrow:SetPoint("RIGHT", -3, 0)

    -- Build the full preset list (static + computed)
    local function GetAllPresetNames()
        local names = {}
        for _, p in ipairs(GUI.ThemePresets) do
            names[#names + 1] = p.name
        end
        names[#names + 1] = "Class Colored"
        names[#names + 1] = "Faction Auto"
        names[#names + 1] = "Custom"
        return names
    end

    local function GetCurrentPreset()
        local db = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile and QUI.QUICore.db.profile.general
        return db and db.themePreset or "Sky Blue"
    end

    local function SetCurrentPreset(presetName)
        local db = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile and QUI.QUICore.db.profile.general
        if not db then return end
        db.themePreset = presetName
        -- Keep legacy flag in sync
        db.skinUseClassColor = (presetName == "Class Colored")
        -- Resolve and apply
        local r, g, b = GUI:ResolveThemePreset(presetName)
        db.addonAccentColor = {r, g, b, 1}
        GUI:ApplyAccentColor(r, g, b)
        accentSwatch._bg:SetVertexColor(r, g, b, 1)
        accentSwatch:SetAlpha(presetName == "Custom" and 1 or 0.5)
        themeDropText:SetText(presetName)
        GUI:RefreshAccentColor()
        C_Timer.After(0, RefreshAllSkinning)
    end

    -- Dropdown menu frame
    local themeMenu = CreateFrame("Frame", nil, themeDropBtn)
    UIKit.CreateBackground(themeMenu, 0.08, 0.08, 0.12, 0.95)
    UIKit.CreateBorderLines(themeMenu)
    UIKit.UpdateBorderLines(themeMenu, 1, 0.3, 0.3, 0.3, 1)
    themeMenu:SetFrameStrata("TOOLTIP")
    themeMenu:Hide()

    local function BuildThemeMenu()
        -- Clear old children
        for _, child in ipairs({themeMenu:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        local presets = GetAllPresetNames()
        local itemH = 18
        themeMenu:SetSize(themeDropBtn:GetWidth(), #presets * itemH + 4)
        themeMenu:ClearAllPoints()
        themeMenu:SetPoint("TOPLEFT", themeDropBtn, "BOTTOMLEFT", 0, -2)

        local currentPreset = GetCurrentPreset()
        for i, name in ipairs(presets) do
            local item = CreateFrame("Button", nil, themeMenu)
            item:SetSize(themeDropBtn:GetWidth() - 4, itemH)
            item:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * itemH))

            local itemBg = item:CreateTexture(nil, "BACKGROUND")
            itemBg:SetAllPoints()
            itemBg:SetColorTexture(0, 0, 0, 0)

            -- Color swatch for static presets
            local presetColor
            for _, p in ipairs(GUI.ThemePresets) do
                if p.name == name then presetColor = p.color; break end
            end
            if name == "Class Colored" then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                if cc then presetColor = {cc.r, cc.g, cc.b} end
            elseif name == "Faction Auto" then
                local faction = UnitFactionGroup("player")
                if faction == "Horde" then
                    presetColor = {0.780, 0.192, 0.192}
                else
                    presetColor = {0.267, 0.467, 0.800}
                end
            end

            if presetColor then
                local swatch = item:CreateTexture(nil, "ARTWORK")
                swatch:SetSize(10, 10)
                swatch:SetPoint("LEFT", 4, 0)
                swatch:SetColorTexture(presetColor[1], presetColor[2], presetColor[3], 1)
            end

            local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            SetFont(itemText, 10, "", name == currentPreset and C.accent or C.text)
            itemText:SetText(name)
            itemText:SetPoint("LEFT", presetColor and 18 or 4, 0)

            item:SetScript("OnEnter", function()
                itemBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
            end)
            item:SetScript("OnLeave", function()
                itemBg:SetColorTexture(0, 0, 0, 0)
            end)
            item:SetScript("OnClick", function()
                themeMenu:Hide()
                if name == "Custom" then
                    SetCurrentPreset("Custom")
                    -- Open color picker for custom
                    local db = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile and QUI.QUICore.db.profile.general
                    if not db then return end
                    local cur = db.addonAccentColor or {0.376, 0.647, 0.980, 1}
                    local pickerWatcher = CreateFrame("Frame")
                    pickerWatcher:SetScript("OnUpdate", function(self)
                        if not ColorPickerFrame:IsShown() then
                            self:SetScript("OnUpdate", nil)
                            self:Hide()
                            GUI:RefreshAccentColor()
                            C_Timer.After(0, RefreshAllSkinning)
                        end
                    end)
                    pickerWatcher:Show()
                    ColorPickerFrame:SetupColorPickerAndShow({
                        r = cur[1], g = cur[2], b = cur[3], opacity = 1,
                        hasOpacity = false,
                        swatchFunc = function()
                            local r, g, b = ColorPickerFrame:GetColorRGB()
                            db.addonAccentColor = {r, g, b, 1}
                            GUI:ApplyAccentColor(r, g, b)
                            accentSwatch._bg:SetVertexColor(r, g, b, 1)
                            title:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
                            version:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
                        end,
                        cancelFunc = function(prev)
                            local r, g, b = prev.r, prev.g, prev.b
                            db.addonAccentColor = {r, g, b, 1}
                            GUI:ApplyAccentColor(r, g, b)
                        end,
                    })
                else
                    SetCurrentPreset(name)
                end
            end)
        end
    end

    themeDropBtn:SetScript("OnClick", function()
        if themeMenu:IsShown() then
            themeMenu:Hide()
        else
            BuildThemeMenu()
            themeMenu:Show()
        end
    end)
    themeDropBtn:SetScript("OnEnter", function()
        UIKit.UpdateBorderLines(themeDropBtn, 1, C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    themeDropBtn:SetScript("OnLeave", function()
        if not themeMenu:IsShown() then
            UIKit.UpdateBorderLines(themeDropBtn, 1, 0.3, 0.3, 0.3, 1)
        end
    end)

    -- Close dropdown when clicking elsewhere
    themeMenu:SetScript("OnHide", function()
        UIKit.UpdateBorderLines(themeDropBtn, 1, 0.3, 0.3, 0.3, 1)
    end)

    accentSwatch:SetScript("OnEnter", function(self)
        UIKit.UpdateBorderLines(self, 1, C_accentLight_r, C_accentLight_g, C_accentLight_b, C_accentLight_a)
    end)
    accentSwatch:SetScript("OnLeave", function(self)
        UIKit.UpdateBorderLines(self, 1, 0.4, 0.4, 0.4, 1)
    end)

    -- Clicking the swatch opens color picker in Custom mode
    accentSwatch:SetScript("OnClick", function()
        local db = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile and QUI.QUICore.db.profile.general
        if not db then return end
        SetCurrentPreset("Custom")
        local cur = db.addonAccentColor or {0.376, 0.647, 0.980, 1}
        local pickerWatcher = CreateFrame("Frame")
        pickerWatcher:SetScript("OnUpdate", function(self)
            if not ColorPickerFrame:IsShown() then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                GUI:RefreshAccentColor()
                C_Timer.After(0, RefreshAllSkinning)
            end
        end)
        pickerWatcher:Show()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = cur[1], g = cur[2], b = cur[3], opacity = 1,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                db.addonAccentColor = {r, g, b, 1}
                GUI:ApplyAccentColor(r, g, b)
                accentSwatch._bg:SetVertexColor(r, g, b, 1)
                title:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
                version:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
            end,
            cancelFunc = function(prev)
                local r, g, b = prev.r, prev.g, prev.b
                db.addonAccentColor = {r, g, b, 1}
                GUI:ApplyAccentColor(r, g, b)
            end,
        })
    end)

    local function UpdateAccentFromDB()
        local db = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile and QUI.QUICore.db.profile.general
        if not db then return end
        local preset = db.themePreset or "Sky Blue"
        themeDropText:SetText(preset)
        local r, g, b = GUI:ResolveThemePreset(preset)
        ApplyAccentToAll(r, g, b)
        accentSwatch:SetAlpha(preset == "Custom" and 1 or 0.5)
    end

    -- Initialize theme from DB
    do
        local initDB = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile and QUI.QUICore.db.profile.general
        local preset = initDB and initDB.themePreset or "Sky Blue"
        themeDropText:SetText(preset)
        local r, g, b = GUI:ResolveThemePreset(preset)
        ApplyAccentToAll(r, g, b)
        accentSwatch:SetAlpha(preset == "Custom" and 1 or 0.5)
    end

    -- Panel Scale (compact inline: label + editbox + slider)
    local scaleContainer = CreateFrame("Frame", nil, titleBar)
    scaleContainer:SetSize(160, 20)
    scaleContainer:SetPoint("LEFT", themeDropBtn, "RIGHT", 14, 0)

    local scaleLabel = scaleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(scaleLabel, 10, "", C.textMuted)
    scaleLabel:SetText("Panel Scale:")
    scaleLabel:SetPoint("LEFT", scaleContainer, "LEFT", 0, 0)

    local scaleEditBox = CreateFrame("EditBox", nil, scaleContainer)
    scaleEditBox:SetSize(38, 16)
    scaleEditBox:SetPoint("LEFT", scaleLabel, "RIGHT", 5, 0)
    UIKit.CreateBackground(scaleEditBox, 0.08, 0.08, 0.08, 1)
    UIKit.CreateBorderLines(scaleEditBox)
    UIKit.UpdateBorderLines(scaleEditBox, 1, 0.25, 0.25, 0.25, 1)
    scaleEditBox:SetFont(GetFontPath(), 10, "")
    scaleEditBox:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a)
    scaleEditBox:SetJustifyH("CENTER")
    scaleEditBox:SetAutoFocus(false)
    scaleEditBox:SetMaxLetters(4)

    local scaleSlider = CreateFrame("Slider", nil, scaleContainer)
    scaleSlider:SetSize(70, 12)
    scaleSlider:SetPoint("LEFT", scaleEditBox, "RIGHT", 5, 0)
    scaleSlider:SetOrientation("HORIZONTAL")
    scaleSlider:SetMinMaxValues(0.8, 1.5)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:EnableMouse(true)
    UIKit.CreateBackground(scaleSlider, 0.22, 0.22, 0.22, 0.9)
    thumb = scaleSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 14)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    scaleSlider:SetThumbTexture(thumb)

    local function ApplyScale(value)
        value = math.max(0.8, math.min(1.5, value))
        value = math.floor(value * 20 + 0.5) / 20
        frame:SetScale(value)
        if QUI.QUICore and QUI.QUICore.db then
            QUI.QUICore.db.profile.configPanelScale = value
        end
        return value
    end

    local savedScale = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile.configPanelScale or 1.0
    scaleSlider:SetValue(savedScale)
    scaleEditBox:SetText(string.format("%.2f", savedScale))
    frame:SetScale(savedScale)

    local isDragging = false

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20
        scaleEditBox:SetText(string.format("%.2f", value))
        if not isDragging then
            ApplyScale(value)
        end
    end)

    scaleSlider:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
        end
    end)

    scaleSlider:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and isDragging then
            isDragging = false
            local value = self:GetValue()
            ApplyScale(value)
        end
    end)

    scaleEditBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = ApplyScale(val)
            scaleSlider:SetValue(val)
            self:SetText(string.format("%.2f", val))
        end
        self:ClearFocus()
    end)

    scaleEditBox:SetScript("OnEscapePressed", function(self)
        self:SetText(string.format("%.2f", scaleSlider:GetValue()))
        self:ClearFocus()
    end)

    scaleEditBox:SetScript("OnEditFocusGained", function(self)
        UIKit.UpdateBorderLines(self, 1, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
    end)

    scaleEditBox:SetScript("OnEditFocusLost", function(self)
        UIKit.UpdateBorderLines(self, 1, 0.25, 0.25, 0.25, 1)
        local val = tonumber(self:GetText())
        if not val then
            self:SetText(string.format("%.2f", scaleSlider:GetValue()))
        end
    end)

    -- Close button [x]
    local close = CreateFrame("Button", nil, titleBar)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -5)
    close._bg = UIKit.CreateBackground(close, 0.08, 0.08, 0.08, 0.6)
    UIKit.CreateBorderLines(close)
    UIKit.UpdateBorderLines(close, 1, C.border[1], C.border[2], C.border[3], 1)

    -- X drawn with two rotated lines
    local LINE_LEN, LINE_W = 10, 1.5
    local xLine1 = close:CreateTexture(nil, "OVERLAY")
    xLine1:SetSize(LINE_LEN, LINE_W)
    xLine1:SetPoint("CENTER")
    xLine1:SetColorTexture(C.text[1], C.text[2], C.text[3], 0.8)
    xLine1:SetRotation(math.rad(45))

    local xLine2 = close:CreateTexture(nil, "OVERLAY")
    xLine2:SetSize(LINE_LEN, LINE_W)
    xLine2:SetPoint("CENTER")
    xLine2:SetColorTexture(C.text[1], C.text[2], C.text[3], 0.8)
    xLine2:SetRotation(math.rad(-45))

    close:SetScript("OnClick", function() frame:Hide() end)
    close:SetScript("OnEnter", function(self)
        UIKit.UpdateBorderLines(self, 1, C.accent[1], C.accent[2], C.accent[3], 1)
        self._bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
        xLine1:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        xLine2:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    close:SetScript("OnLeave", function(self)
        UIKit.UpdateBorderLines(self, 1, C.border[1], C.border[2], C.border[3], 1)
        self._bg:SetVertexColor(0.08, 0.08, 0.08, 0.6)
        xLine1:SetColorTexture(C.text[1], C.text[2], C.text[3], 0.8)
        xLine2:SetColorTexture(C.text[1], C.text[2], C.text[3], 0.8)
    end)

    -- Separator line below title
    local titleSep = frame:CreateTexture(nil, "ARTWORK")
    titleSep:SetPoint("TOPLEFT", 10, -30)
    titleSep:SetPoint("TOPRIGHT", -10, -30)
    titleSep:SetHeight(1)
    titleSep:SetColorTexture(C_border_r, C_border_g, C_border_b, C_border_a)

    ---------------------------------------------------------------------------
    -- SIDEBAR (vertical tab list on the left)
    ---------------------------------------------------------------------------
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 10, -35)
    sidebar:SetPoint("BOTTOMLEFT", 10, 10)
    sidebar:SetWidth(SIDEBAR_W)

    -- Sidebar background (slightly darker than main frame bg)
    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(C.bgSidebar[1], C.bgSidebar[2], C.bgSidebar[3], C.bgSidebar[4])
    sidebar._bg = sidebarBg

    -- Right border on sidebar
    local sidebarBorder = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebarBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarBorder:SetWidth(1)
    sidebarBorder:SetColorTexture(C_border_r, C_border_g, C_border_b, C_border_a)
    sidebar._divider = sidebarBorder

    frame.sidebar = sidebar

    ---------------------------------------------------------------------------
    -- FOOTER BAR (spans content area width, 36px tall at bottom)
    ---------------------------------------------------------------------------
    local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMRIGHT", 1, 0)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(36)

    local footerBg = footer:CreateTexture(nil, "BACKGROUND")
    footerBg:SetAllPoints(footer)
    footerBg:SetColorTexture(C.bgFooter[1], C.bgFooter[2], C.bgFooter[3], C.bgFooter[4])

    local footerDivider = footer:CreateTexture(nil, "OVERLAY")
    footerDivider:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    footerDivider:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    footerDivider:SetHeight(1)
    footerDivider:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])

    frame.footerBar = footer

    -- Left cluster: Reset to Defaults + Reload UI (ghost variant, auto-sized)
    local resetBtn = GUI:CreateButton(footer, "Reset to Defaults", 0, 22, function()
        local tileIndex = frame._lastTileIndex
        local tile = tileIndex and frame._tiles and frame._tiles[tileIndex]
        if tile and tile.config and tile.config.onReset then
            tile.config.onReset()
        else
            print("|cff34D399QUI|r: No reset hook registered for this page.")
        end
    end, "ghost")
    resetBtn:SetPoint("LEFT", footer, "LEFT", 18, 0)
    frame._footerResetBtn = resetBtn

    local reloadBtn = GUI:CreateButton(footer, "Reload UI", 0, 22, function()
        if QUI and QUI.SafeReload then
            QUI:SafeReload()
        else
            ReloadUI()
        end
    end, "ghost")
    reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
    frame._footerReloadBtn = reloadBtn

    ---------------------------------------------------------------------------
    -- SUB-TAB BAR (sticky bar above scroll content, hidden by default)
    ---------------------------------------------------------------------------
    local subTabBar = CreateFrame("Frame", nil, frame)
    subTabBar:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    subTabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -35)
    subTabBar:SetHeight(30)
    subTabBar:SetFrameLevel(frame:GetFrameLevel() + 5)  -- Above content area
    subTabBar:EnableMouse(true)  -- Block clicks from passing through
    subTabBar:Hide()

    -- Sub-tab bar background
    local subTabBarBg = subTabBar:CreateTexture(nil, "BACKGROUND")
    subTabBarBg:SetAllPoints()
    subTabBarBg:SetColorTexture(unpack(C.bgContent))

    -- Bottom border on sub-tab bar
    local subTabBarBorder = subTabBar:CreateTexture(nil, "ARTWORK")
    subTabBarBorder:SetPoint("BOTTOMLEFT", subTabBar, "BOTTOMLEFT", 0, 0)
    subTabBarBorder:SetPoint("BOTTOMRIGHT", subTabBar, "BOTTOMRIGHT", 0, 0)
    subTabBarBorder:SetHeight(1)
    subTabBarBorder:SetColorTexture(C_border_r, C_border_g, C_border_b, C_border_a)

    frame.subTabBar = subTabBar

    ---------------------------------------------------------------------------
    -- CONTENT AREA (right of sidebar, below sub-tab bar when visible)
    ---------------------------------------------------------------------------
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    contentArea:SetPoint("BOTTOMRIGHT", -10, 36)
    contentArea:EnableMouse(false)

    -- Content background
    local contentBg = contentArea:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints()
    contentBg:SetColorTexture(unpack(C.bgContent))

    -- Decorative accent wash across the full content area.
    local glow = contentArea:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(contentArea)
    glow:SetTexture("Interface\\BUTTONS\\WHITE8x8")
    if glow.SetGradient then
        local ok = pcall(function()
            glow:SetGradient("HORIZONTAL",
                CreateColor(C.accentGlow[1], C.accentGlow[2], C.accentGlow[3], C.accentGlow[4]),
                CreateColor(C.accentGlow[1], C.accentGlow[2], C.accentGlow[3], 0))
        end)
        if not ok then
            glow:SetColorTexture(C.accentGlow[1], C.accentGlow[2], C.accentGlow[3], C.accentGlow[4])
        end
    else
        glow:SetColorTexture(C.accentGlow[1], C.accentGlow[2], C.accentGlow[3], C.accentGlow[4])
    end
    contentArea._accentGlow = glow

    frame.contentArea = contentArea

    -- Store tabs and pages
    frame.tabs = {}
    frame.pages = {}
    frame.activeTab = nil

    ---------------------------------------------------------------------------
    -- RESIZE HANDLE (Bottom-right corner, horizontal and vertical)
    ---------------------------------------------------------------------------
    local MIN_HEIGHT = 400
    local MAX_HEIGHT = 1200
    local MIN_WIDTH = 750
    local MAX_WIDTH = 1200

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(20, 20)
    resizeHandle:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 10)

    local gripTexture = resizeHandle:CreateTexture(nil, "OVERLAY")
    gripTexture:SetAllPoints()
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTexture:SetVertexColor(C.accentDark[1] + 0.3, C.accentDark[2] + 0.3, C.accentDark[3] + 0.3, 0.8)

    local gripHighlight = resizeHandle:CreateTexture(nil, "HIGHLIGHT")
    gripHighlight:SetAllPoints()
    gripHighlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    gripHighlight:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)

    local gripPushed = resizeHandle:CreateTexture(nil, "ARTWORK")
    gripPushed:SetAllPoints()
    gripPushed:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    gripPushed:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    gripPushed:Hide()

    resizeHandle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            gripPushed:Show()
            gripTexture:Hide()

            local left = frame:GetLeft()
            local top = frame:GetTop()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

            local cursorX, cursorY = GetCursorPosition()
            local scale = frame:GetEffectiveScale()
            self.startX = cursorX / scale
            self.startY = cursorY / scale
            self.startWidth = frame:GetWidth()
            self.startHeight = frame:GetHeight()
            self.isResizing = true

            self._resizeElapsed = 0
            self:SetScript("OnUpdate", function(self, elapsed)
                if not self.isResizing then return end
                self._resizeElapsed = (self._resizeElapsed or 0) + elapsed
                if self._resizeElapsed < 0.016 then return end
                self._resizeElapsed = 0

                local cursorX, cursorY = GetCursorPosition()
                local scale = frame:GetEffectiveScale()
                local currentX = cursorX / scale
                local currentY = cursorY / scale

                local deltaX = currentX - self.startX
                local deltaY = self.startY - currentY

                local newWidth = math.max(MIN_WIDTH, math.min(MAX_WIDTH, self.startWidth + deltaX))
                local newHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, self.startHeight + deltaY))

                frame:SetSize(newWidth, newHeight)
            end)
        end
    end)

    resizeHandle:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            gripPushed:Hide()
            gripTexture:Show()
            self.isResizing = false
            self:SetScript("OnUpdate", nil)

            if QUI.QUICore and QUI.QUICore.db then
                QUI.QUICore.db.profile.configPanelWidth = frame:GetWidth()
            end
        end
    end)

    resizeHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)

    resizeHandle:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    frame.resizeHandle = resizeHandle

    -- Teardown preview/edit states when the options panel is closed
    frame:SetScript("OnHide", function()
        local gfem = ns and ns.QUI_GroupFrameEditMode
        if gfem then
            if gfem:IsEditMode() then gfem:DisableEditMode() end
            if gfem:IsTestMode() then gfem:DisableTestMode() end
        end
    end)

    return frame
end

---------------------------------------------------------------------------
-- SHOW FUNCTION
---------------------------------------------------------------------------
function GUI:Show()
    if not self.MainFrame then
        self:InitializeOptions()
    end
    if not self._combatFrame then
        self._combatFrame = CreateFrame("Frame")
        self._combatFrame:SetScript("OnEvent", function()
            if GUI.MainFrame and GUI.MainFrame:IsShown() then
                GUI:Hide()
                print("|cff60A5FAQUI:|r Settings closed (combat).")
            end
        end)
        self._combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    end
    self.MainFrame:Show()
    self.MainFrame:Raise()
end

---------------------------------------------------------------------------
-- HIDE FUNCTION
---------------------------------------------------------------------------
function GUI:Hide()
    if self.MainFrame then
        self.MainFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- REFRESH ACCENT COLOR (Rebuilds the panel to pick up new theme colors)
---------------------------------------------------------------------------
function GUI:RefreshAccentColor()
    if not self.MainFrame then return end
    local wasShown = self.MainFrame:IsShown()
    local prevTileIndex = self.MainFrame._lastTileIndex

    local point, _, relPoint, xOfs, yOfs = self.MainFrame:GetPoint()

    if self.TeardownFrameTree then
        self:TeardownFrameTree(self.MainFrame, { includeRoot = true })
    else
        self.MainFrame:Hide()
        self.MainFrame:SetParent(nil)
    end
    self.MainFrame = nil

    -- Registry re-seeds from the tile builders on re-init.
    self.SettingsRegistry = {}
    self.SettingsRegistryKeys = {}

    self:InitializeOptions()

    if point and self.MainFrame then
        self.MainFrame:ClearAllPoints()
        self.MainFrame:SetPoint(point, UIParent, relPoint, xOfs, yOfs)
    end

    if prevTileIndex and self.MainFrame and self.MainFrame._tiles and self.MainFrame._tiles[prevTileIndex] then
        self:SelectFeatureTile(self.MainFrame, prevTileIndex)
    end

    if wasShown and self.MainFrame then
        self.MainFrame:Show()
    end
end

---------------------------------------------------------------------------
-- SCROLLBAR STYLING (hides default Blizzard chrome, mint accent thumb)
---------------------------------------------------------------------------
local function StyleScrollBar(scrollFrame)
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if not scrollBar then return end

    -- Hide default track texture
    if scrollBar.Track then
        scrollBar.Track:SetAlpha(0)
    end

    -- Style thumb to mint accent
    local thumb = scrollBar.ThumbTexture or scrollBar:GetThumbTexture()
    if thumb then
        thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
        thumb:SetSize(8, 40)
    end

    -- Hide up/down buttons
    local upBtn = scrollBar.ScrollUpButton or _G[scrollFrame:GetName() .. "ScrollBarScrollUpButton"]
    local downBtn = scrollBar.ScrollDownButton or _G[scrollFrame:GetName() .. "ScrollBarScrollDownButton"]
    if upBtn then upBtn:SetAlpha(0) upBtn:SetSize(1, 1) end
    if downBtn then downBtn:SetAlpha(0) downBtn:SetSize(1, 1) end
end

---------------------------------------------------------------------------
-- EXPORT POPUP (QUI-styled popup for export strings)
---------------------------------------------------------------------------
local ExportPopup = nil  -- Reusable popup frame

function GUI:ShowExportPopup(title, exportString)
    -- Create popup frame if it doesn't exist
    if not ExportPopup then
        local popup = CreateFrame("Frame", "QUI_ExportPopup", UIParent, "BackdropTemplate")
        popup:SetSize(500, 220)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(500)
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        CreateBackdrop(popup, {0.08, 0.10, 0.14, 0.98}, {C.accent[1], C.accent[2], C.accent[3], 1})

        -- Title
        popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        popup.title:SetPoint("TOP", 0, -12)
        popup.title:SetTextColor(1, 1, 1, 1)

        -- Hint text
        popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        popup.hint:SetPoint("TOP", popup.title, "BOTTOM", 0, -4)
        SetFont(popup.hint, 11, "", C.textMuted)
        popup.hint:SetText("Select all (Ctrl+A) then copy (Ctrl+C)")

        -- Background for edit area
        local editBg = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        editBg:SetPoint("TOPLEFT", 12, -55)
        editBg:SetPoint("BOTTOMRIGHT", -12, 45)
        CreateBackdrop(editBg, {0.04, 0.05, 0.07, 1}, nil)

        -- Scroll frame for edit box
        local scrollFrame = CreateFrame("ScrollFrame", "QUI_ExportPopupScroll", editBg, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 8, -8)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)
        StyleScrollBar(scrollFrame)

        -- Edit box
        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFont(GetFontPath(), 11, "")
        editBox:SetTextColor(0.85, 0.88, 0.92, 1)
        editBox:SetWidth(scrollFrame:GetWidth() - 10)
        editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        scrollFrame:SetScrollChild(editBox)
        popup.editBox = editBox
        popup.scrollFrame = scrollFrame

        -- Update editbox width when scroll frame sizes
        scrollFrame:SetScript("OnSizeChanged", function(self)
            editBox:SetWidth(self:GetWidth() - 10)
        end)
        ns.ApplyScrollWheel(scrollFrame)

        -- Select All button
        local selectBtn = self:CreateButton(popup, "Select All", 100, 26, function()
            popup.editBox:SetFocus()
            popup.editBox:HighlightText()
        end)
        selectBtn:SetPoint("BOTTOMLEFT", 12, 10)

        -- Close button
        local closeBtn = self:CreateButton(popup, "Close", 80, 26, function()
            popup:Hide()
        end)
        closeBtn:SetPoint("BOTTOMRIGHT", -12, 10)

        -- X button in corner
        local xBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        xBtn:SetSize(22, 22)
        xBtn:SetPoint("TOPRIGHT", -6, -6)
        CreateBackdrop(xBtn, {0.12, 0.12, 0.12, 1}, nil)
        local xText = xBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        xText:SetPoint("CENTER", 0, 0)
        xText:SetText("x")
        xText:SetTextColor(0.6, 0.6, 0.6, 1)
        xBtn:SetScript("OnEnter", function(self)
            pcall(self.SetBackdropBorderColor, self, 1, 0.3, 0.3, 1)
            xText:SetTextColor(1, 0.3, 0.3, 1)
        end)
        xBtn:SetScript("OnLeave", function(self)
            pcall(self.SetBackdropBorderColor, self, C.border[1], C.border[2], C.border[3], 1)
            xText:SetTextColor(0.6, 0.6, 0.6, 1)
        end)
        xBtn:SetScript("OnClick", function() popup:Hide() end)

        popup:Hide()
        ExportPopup = popup
    end

    -- Set content and show
    ExportPopup.title:SetText(title or "Export")
    ExportPopup.editBox:SetText(exportString or "")
    ExportPopup:Show()
    ExportPopup:Raise()
    ExportPopup.editBox:SetFocus()
    ExportPopup.editBox:HighlightText()
end

---------------------------------------------------------------------------
-- IMPORT POPUP (QUI-styled popup for import strings)
---------------------------------------------------------------------------
local ImportPopup = nil  -- Reusable popup frame

-- config = {
--     title = "Import Title",
--     hint = "Paste string below",
--     hasMerge = true/false,  -- if true, shows Merge + Replace All buttons; if false, just Import button
--     onImport = function(str) end,  -- called for single import or merge
--     onReplace = function(str) end, -- called for replace all (only if hasMerge)
--     onSuccess = function() end,     -- called after successful import (for reload prompt)
-- }
function GUI:ShowImportPopup(config)
    -- Create popup frame if it doesn't exist
    if not ImportPopup then
        local popup = CreateFrame("Frame", "QUI_ImportPopup", UIParent, "BackdropTemplate")
        popup:SetSize(500, 250)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(500)
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        CreateBackdrop(popup, {0.08, 0.10, 0.14, 0.98}, {C.accent[1], C.accent[2], C.accent[3], 1})

        -- Title
        popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        popup.title:SetPoint("TOP", 0, -12)
        popup.title:SetTextColor(1, 1, 1, 1)

        -- Hint text
        popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        popup.hint:SetPoint("TOP", popup.title, "BOTTOM", 0, -4)
        SetFont(popup.hint, 11, "", C.textMuted)

        -- Background for edit area
        local editBg = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        editBg:SetPoint("TOPLEFT", 12, -55)
        editBg:SetPoint("BOTTOMRIGHT", -12, 50)
        CreateBackdrop(editBg, {0.04, 0.05, 0.07, 1}, nil)

        -- Scroll frame for edit box
        local scrollFrame = CreateFrame("ScrollFrame", "QUI_ImportPopupScroll", editBg, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 8, -8)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)
        StyleScrollBar(scrollFrame)

        -- Edit box
        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFont(GetFontPath(), 11, "")
        editBox:SetTextColor(0.85, 0.88, 0.92, 1)
        editBox:SetWidth(scrollFrame:GetWidth() - 10)
        editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        scrollFrame:SetScrollChild(editBox)
        popup.editBox = editBox
        popup.scrollFrame = scrollFrame

        scrollFrame:SetScript("OnSizeChanged", function(self)
            editBox:SetWidth(self:GetWidth() - 10)
        end)
        ns.ApplyScrollWheel(scrollFrame)

        -- Button container (buttons are created/updated dynamically)
        popup.buttons = {}

        -- X button in corner
        local xBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        xBtn:SetSize(22, 22)
        xBtn:SetPoint("TOPRIGHT", -6, -6)
        CreateBackdrop(xBtn, {0.12, 0.12, 0.12, 1}, nil)
        local xText = xBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        xText:SetPoint("CENTER", 0, 0)
        xText:SetText("x")
        xText:SetTextColor(0.6, 0.6, 0.6, 1)
        xBtn:SetScript("OnEnter", function(self)
            pcall(self.SetBackdropBorderColor, self, 1, 0.3, 0.3, 1)
            xText:SetTextColor(1, 0.3, 0.3, 1)
        end)
        xBtn:SetScript("OnLeave", function(self)
            pcall(self.SetBackdropBorderColor, self, C.border[1], C.border[2], C.border[3], 1)
            xText:SetTextColor(0.6, 0.6, 0.6, 1)
        end)
        xBtn:SetScript("OnClick", function() popup:Hide() end)

        popup:Hide()
        ImportPopup = popup
    end

    -- Clear existing buttons
    for _, btn in pairs(ImportPopup.buttons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(ImportPopup.buttons)

    -- Create buttons based on config
    local guiRef = self
    local function DoImport(replaceAll)
        local str = ImportPopup.editBox:GetText()
        if not str or str == "" then
            print("|cffff0000QUI:|r No import string provided")
            return
        end

        local ok, msg
        if replaceAll and config.onReplace then
            ok, msg = config.onReplace(str)
        elseif config.onImport then
            ok, msg = config.onImport(str)
        end

        local printFeedback = ns.PrintImportFeedback
        if ok then
            if printFeedback then
                printFeedback(true, msg, false)
            else
                print("|cff34D399QUI:|r " .. (msg or "Import successful"))
            end
            ImportPopup:Hide()
            if config.onSuccess then
                config.onSuccess()
            end
        else
            if printFeedback then
                printFeedback(false, msg, false)
            else
                print("|cffff0000QUI:|r " .. (msg or "Import failed"))
            end
        end
    end

    if config.hasMerge then
        -- Merge + Replace All + Cancel layout
        local mergeBtn = guiRef:CreateButton(ImportPopup, "Merge", 100, 26, function()
            DoImport(false)
        end)
        mergeBtn:SetPoint("BOTTOMLEFT", 12, 12)
        table.insert(ImportPopup.buttons, mergeBtn)

        local replaceBtn = guiRef:CreateButton(ImportPopup, "Replace All", 100, 26, function()
            DoImport(true)
        end)
        replaceBtn:SetPoint("LEFT", mergeBtn, "RIGHT", 10, 0)
        table.insert(ImportPopup.buttons, replaceBtn)

        local cancelBtn = guiRef:CreateButton(ImportPopup, "Cancel", 80, 26, function()
            ImportPopup:Hide()
        end)
        cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
        table.insert(ImportPopup.buttons, cancelBtn)
    else
        -- Import + Cancel layout
        local importBtn = guiRef:CreateButton(ImportPopup, "Import", 100, 26, function()
            DoImport(false)
        end)
        importBtn:SetPoint("BOTTOMLEFT", 12, 12)
        table.insert(ImportPopup.buttons, importBtn)

        local cancelBtn = guiRef:CreateButton(ImportPopup, "Cancel", 80, 26, function()
            ImportPopup:Hide()
        end)
        cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
        table.insert(ImportPopup.buttons, cancelBtn)
    end

    -- Set content and show
    ImportPopup.title:SetText(config.title or "Import")
    ImportPopup.hint:SetText(config.hint or "Paste the import string below")
    ImportPopup.editBox:SetText("")
    ImportPopup:Show()
    ImportPopup:Raise()
    ImportPopup.editBox:SetFocus()
end

---------------------------------------------------------------------------
-- TOGGLE FUNCTION
---------------------------------------------------------------------------
function GUI:Toggle()
    if self.MainFrame and self.MainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

---------------------------------------------------------------------------
-- V2 EXTENSIONS — feature-tile sidebar, horizontal sub-page tabs,
-- inline search, tools strip, V2 navigation routes, breadcrumbs,
-- pulse-on-jump widget highlight.
-- (Previously options/framework_v2.lua, merged into framework.lua.)
---------------------------------------------------------------------------

local C = GUI.Colors
local Helpers = ns.Helpers

ns.QUI_Framework = ns.QUI_Framework or {}
local FW2 = ns.QUI_Framework

--[[
    GUI:AddFeatureTile(frame, config)

    Registers a sidebar feature tile. config fields:
        id        (string, required) - stable key, e.g. "minimap"
        iconTexture (string, optional) - texture path shown left of name
        icon      (string, optional) - legacy single-char fallback shown left of name
        name      (string, required) - display name in sidebar
        subtitle  (string, optional) - shown under page title in content area
        subPages  (array, required if using sub-pages) - list of { name, buildFunc }
                  buildFunc(contentArea) builds the sub-page body
        buildFunc (function, optional) - for tiles with no sub-pages
        isBottomItem (boolean, optional) - render in bottom sidebar section (Help, etc.)

    Returns the tile registration table so callers can attach extra metadata.
]]
function GUI:AddFeatureTile(frame, config)
    assert(type(config) == "table", "AddFeatureTile: config required")
    assert(config.id, "AddFeatureTile: config.id required")
    assert(config.name, "AddFeatureTile: config.name required")

    frame._tiles = frame._tiles or {}
    frame._topTiles = frame._topTiles or {}
    frame._bottomTiles = frame._bottomTiles or {}

    local index = #frame._tiles + 1
    local bucket = config.isBottomItem and frame._bottomTiles or frame._topTiles
    local bucketIndex = #bucket + 1

    -- Tiles parent directly to frame.sidebar and lay themselves out in the
    -- sidebar column (no intermediate scroll/tree container).
    local tile = CreateFrame("Button", nil, frame.sidebar)
    tile:SetHeight(26)
    tile.index = index
    tile.id = config.id
    tile.config = config

    -- Vertical layout within bucket. Top bucket stacks down from below the
    -- sidebar search bar (search bar eats ~44px at the top: -10 offset + 28
    -- height + 6 gap). Bottom bucket stacks up from above the Tools strip
    -- (~102px reserved: 24 bottom offset + 72 strip height + 6 gap).
    if config.isBottomItem then
        if bucketIndex == 1 then
            tile:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMLEFT", 6, 102)
            tile:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", -6, 102)
        else
            local prev = bucket[bucketIndex - 1]
            tile:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, 2)
            tile:SetPoint("BOTTOMRIGHT", prev, "TOPRIGHT", 0, 2)
        end
    else
        if bucketIndex == 1 then
            tile:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", 6, -44)
            tile:SetPoint("TOPRIGHT", frame.sidebar, "TOPRIGHT", -6, -44)
        else
            local prev = bucket[bucketIndex - 1]
            tile:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
            tile:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -2)
        end
    end
    bucket[bucketIndex] = tile

    -- Left active indicator bar
    tile.indicator = tile:CreateTexture(nil, "OVERLAY")
    tile.indicator:SetPoint("TOPLEFT", 0, 0)
    tile.indicator:SetPoint("BOTTOMLEFT", 0, 0)
    tile.indicator:SetWidth(3)
    tile.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    tile.indicator:Hide()

    -- Hover/active background
    tile.hoverBg = tile:CreateTexture(nil, "BACKGROUND")
    tile.hoverBg:SetAllPoints()
    tile.hoverBg:SetColorTexture(1, 1, 1, 0.03)
    tile.hoverBg:Hide()

    -- Icon (optional)
    local textX = 15
    local iconTexturePath = config.iconTexture
    if iconTexturePath == nil and config.id then
        iconTexturePath = Helpers.AssetPath .. "sidebar\\" .. config.id
    end
    if iconTexturePath then
        local SIDEBAR_ICON_SIZE = 20
        tile.iconTexture = tile:CreateTexture(nil, "OVERLAY")
        tile.iconTexture:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        tile.iconTexture:SetPoint("LEFT", tile, "LEFT", 10, 0)
        tile.iconTexture:SetTexture(iconTexturePath)
        tile.iconTexture:SetVertexColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.75)
        textX = 37
    elseif config.icon then
        tile.icon = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tile.icon:SetText(config.icon)
        tile.icon:SetPoint("LEFT", tile, "LEFT", 10, 0)
        tile.icon:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.55)
        textX = 28
    end

    -- Name text
    tile.text = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tile.text:SetFont(tile.text:GetFont(), 11)
    tile.text:SetText(config.name)
    tile.text:SetPoint("LEFT", tile, "LEFT", textX, 0)
    tile.text:SetJustifyH("LEFT")
    tile.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1)

    -- Store so V2 init can lay them out (Task 8)
    frame._tiles[index] = tile

    -- Click handler stub — real selection logic added in Task 8
    tile:SetScript("OnClick", function(self)
        GUI:SelectFeatureTile(frame, self.index)
    end)

    tile:SetScript("OnEnter", function(self)
        if not self._isActive then self.hoverBg:SetColorTexture(1, 1, 1, 0.03); self.hoverBg:Show() end
    end)
    tile:SetScript("OnLeave", function(self)
        if not self._isActive then self.hoverBg:Hide() end
    end)

    return tile
end

--[[
    GUI:BuildTilePage(frame, tile)

    Builds the tile's page frame (title, sub-page tabs, body) into a hidden
    parent without changing the current selection or touching visibility.
    Idempotent: re-entry is a no-op once `tile._built` is set.

    This is the single build path — SelectFeatureTile calls it before
    showing, and the indexer calls it during login to eagerly populate the
    search registry without any visible flicker (build into a hidden
    frame, then attach to the visible content area on first select).
]]
function GUI:BuildTilePage(frame, tile)
    if not tile or tile._built then return end

    -- Ensure content container exists (shared parent for all tile pages).
    if not frame._tileContent then
        frame._tileContent = CreateFrame("Frame", nil, frame.contentArea)
        frame._tileContent:SetAllPoints(frame.contentArea)
    end
    local content = frame._tileContent

    -- Build the page hidden. Callers decide when (if ever) to Show it.
    tile._pageFrame = CreateFrame("Frame", nil, content)
    tile._pageFrame:SetAllPoints(content)
    tile._pageFrame:Hide()

    local header = CreateFrame("Frame", nil, tile._pageFrame)
    header:SetPoint("TOPLEFT", tile._pageFrame, "TOPLEFT", 18, -14)
    header:SetPoint("TOPRIGHT", tile._pageFrame, "TOPRIGHT", -18, -14)
    header:SetHeight(48)
    tile._header = header

    local crumb = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local fpath = ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(GUI:GetFontPath())
    crumb:SetFont(fpath or select(1, crumb:GetFont()), 10, "")
    crumb:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    crumb:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    crumb:SetText("Settings  >  " .. (tile.config.name or ""))
    tile._crumb = crumb

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetFont(fpath or select(1, title:GetFont()), 15, "")
    title:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    title:SetPoint("TOPLEFT", crumb, "BOTTOMLEFT", 0, -4)
    title:SetText(tile.config.name or "")
    tile._title = title

    if tile.config.subtitle and tile.config.subtitle ~= "" then
        local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        subtitle:SetFont(fpath or select(1, subtitle:GetFont()), 11, "")
        subtitle:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        subtitle:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText(tile.config.subtitle)
        tile._subtitle = subtitle
        header:SetHeight(54)
    end

    local pins = ns.Settings and ns.Settings.Pins
    if pins and type(pins.AttachCountChip) == "function" then
        pins:AttachCountChip(header)
    end

    -- Anchor body/sub-tabs to the header's bottom so a taller header
    -- (subtitle present) pushes content down instead of overlapping.

    -- Persistent preview area (tile-level). If tile.config.preview is set,
    -- build a preview frame below the header. The sub-tab strip and all
    -- sub-page bodies anchor below this preview, so the preview stays
    -- visible as the user switches sub-tabs. Used by feature tiles where
    -- a live preview of the configured element (action buttons, unit
    -- frame, nameplate, etc.) applies across every sub-tab.
    local anchorFrame = header
    if tile.config.preview and type(tile.config.preview.build) == "function" then
        local pv = CreateFrame("Frame", nil, tile._pageFrame)
        pv:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
        pv:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)
        pv:SetHeight(tile.config.preview.height or 90)
        tile.config.preview.build(pv)
        tile._preview = pv
        anchorFrame = pv
    end

    if tile.config.subPages and #tile.config.subPages > 0 then
        GUI:RenderSubPageTabs(tile, tile._pageFrame, tile.config.subPages, function(sp, body)
            if type(sp.buildFunc) == "function" then sp.buildFunc(body) end
        end, anchorFrame)
    elseif type(tile.config.buildFunc) == "function" then
        local container = CreateFrame("Frame", nil, tile._pageFrame)
        local footerReserve = tile.config.relatedSettings and 32 or 0
        container:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", -18, -10)
        container:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 18, -10)
        container:SetPoint("BOTTOMRIGHT", tile._pageFrame, "BOTTOMRIGHT", 0, footerReserve)

        local scrollFrame, body
        if tile.config.noScroll then
            body = container
        elseif ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
            scrollFrame, body = ns.QUI_Options.CreateScrollableContent(container)
        else
            body = container
        end

        -- Mirror the RegisterSection install used by the sub-page render path
        -- so CreateAccentDotLabel can auto-register sections on direct
        -- (no-subPages) tiles that opt in via tile.config.sectionNav.
        body._sections = {}
        function body:RegisterSection(id, label, frame)
            if type(id) ~= "string" or id == "" or not frame then return end
            local resolvedLabel = (type(label) == "string" and label ~= "") and label or id
            for j, existing in ipairs(self._sections) do
                if existing.id == id then
                    self._sections[j] = { id = id, label = resolvedLabel, frame = frame }
                    return
                end
            end
            self._sections[#self._sections + 1] = {
                id = id,
                label = resolvedLabel,
                frame = frame,
            }
        end

        tile.config.buildFunc(body)

        if tile.config.sectionNav and scrollFrame and #body._sections >= 2 then
            local function tryBuildSectionNav()
                if container._sectionNav then return end
                local bodyH = body:GetHeight() or 0
                local viewH = scrollFrame:GetHeight() or 0
                if bodyH > viewH and viewH > 0 then
                    container._sectionNav = GUI:RenderSectionNav(scrollFrame, body, body._sections)
                end
            end
            tryBuildSectionNav()
            C_Timer.After(0, tryBuildSectionNav)
            body:HookScript("OnSizeChanged", function()
                if not container._sectionNav then
                    C_Timer.After(0, tryBuildSectionNav)
                end
            end)
        end
    end

    if tile.config.relatedSettings and ns.QUI_RenderRelatedFooter then
        ns.QUI_RenderRelatedFooter(tile._pageFrame, tile.config.relatedSettings, frame)
    end

    -- Per-tile primary CTA docked at the right edge of the footer bar.
    -- Config shape: { label, onClick }  or  { label, moverKey = "<key>" }
    -- When moverKey is set (and no explicit onClick), the button closes the
    -- options panel, opens Layout Mode, and selects the named mover handle.
    if tile.config.primaryCTA and frame.footerBar and not tile._primaryBtn then
        local cta = tile.config.primaryCTA
        local onClick = cta.onClick
        if not onClick and cta.moverKey ~= nil then
            local moverKey = cta.moverKey
            onClick = function()
                if InCombatLockdown and InCombatLockdown() then
                    print("|cff60A5FAQUI:|r Cannot open Layout Mode during combat.")
                    return
                end
                if GUI and GUI.Hide then pcall(GUI.Hide, GUI) end
                if _G.QUI_OpenLayoutMode then _G.QUI_OpenLayoutMode() end
                if moverKey ~= "" and _G.QUI_LayoutModeSelectMover then
                    -- SelectMover works once handles are created. Open is
                    -- synchronous but handle creation happens via a C_Timer
                    -- callback chain; defer one tick so the key is found.
                    C_Timer.After(0.05, function()
                        _G.QUI_LayoutModeSelectMover(moverKey)
                    end)
                end
            end
        end
        tile._primaryBtn = GUI:CreateButton(
            frame.footerBar,
            cta.label or "",
            0, 22,
            onClick,
            "primary"
        )
        tile._primaryBtn:ClearAllPoints()
        tile._primaryBtn:SetPoint("RIGHT", frame.footerBar, "RIGHT", -18, 0)
        tile._primaryBtn:Hide()
    end

    tile._built = true
end

local function FindStaticNavigationRoute(gui, navType, tileId, subPageIndex)
    for _, entry in ipairs(gui and gui.StaticNavigationRegistry or {}) do
        if entry.navType == navType
            and entry.tileId == tileId
            and entry.subPageIndex == subPageIndex then
            return entry
        end
    end

    return nil
end

function GUI:SeedStaticSearchRoutesFromTiles(frame)
    if not frame or not frame._tiles then
        return
    end

    local tilesById = {}
    for _, tile in ipairs(frame._tiles) do
        if tile and type(tile.id) == "string" and tile.id ~= "" then
            tilesById[tile.id] = tile
        end
    end

    local function BackfillRoute(entry)
        if type(entry) ~= "table" then
            return
        end

        if not entry.tileId then
            local resolved = GUI:ResolveV2Navigation(entry.tabIndex, entry.subTabIndex)
            if resolved then
                entry.tileId = resolved.tileId or entry.tileId
                if entry.subPageIndex == nil then
                    entry.subPageIndex = resolved.subPageIndex
                end
            end
        end

        local tile = entry.tileId and tilesById[entry.tileId] or nil
        if not tile then
            return
        end

        local tileName = tile.config and tile.config.name or nil
        if type(tileName) == "string" and tileName ~= "" then
            entry.tabName = tileName
        end

        local subPage = entry.subPageIndex
            and tile.config
            and tile.config.subPages
            and tile.config.subPages[entry.subPageIndex]
            or nil
        local subPageName = subPage and subPage.name or nil
        if type(subPageName) == "string" and subPageName ~= "" then
            entry.subTabName = subPageName
        end

        if entry.navType then
            local label = BuildSearchNavigationLabel(entry.navType, entry)
            if type(label) == "string" and label ~= "" then
                entry.label = label
            end
            local keywords = BuildSearchNavigationKeywords(entry)
            if #keywords > 0 then
                entry.keywords = keywords
            end
        end
    end

    for _, entry in ipairs(self.StaticSettingsRegistry or {}) do
        BackfillRoute(entry)
    end
    for _, entry in ipairs(self.StaticNavigationRegistry or {}) do
        BackfillRoute(entry)
    end

    for _, tile in ipairs(frame._tiles) do
        if tile and tile.config then
            if not FindStaticNavigationRoute(self, "tab", tile.id, nil) then
                self:RegisterStaticNavigationEntry({
                    navType = "tab",
                    label = tile.config.name,
                    tabName = tile.config.name,
                    tileId = tile.id,
                    keywords = BuildSearchNavigationKeywords({
                        tabName = tile.config.name,
                        tileId = tile.id,
                    }),
                })
            end

            for subPageIndex, subPage in ipairs(tile.config.subPages or {}) do
                if type(subPage) == "table"
                    and type(subPage.name) == "string"
                    and subPage.name ~= ""
                    and not FindStaticNavigationRoute(self, "subtab", tile.id, subPageIndex) then
                    self:RegisterStaticNavigationEntry({
                        navType = "subtab",
                        label = BuildSearchNavigationLabel("subtab", {
                            tabName = tile.config.name,
                            subTabName = subPage.name,
                            tileId = tile.id,
                            subPageIndex = subPageIndex,
                        }),
                        tabName = tile.config.name,
                        subTabName = subPage.name,
                        tileId = tile.id,
                        subPageIndex = subPageIndex,
                        keywords = BuildSearchNavigationKeywords({
                            tabName = tile.config.name,
                            subTabName = subPage.name,
                            tileId = tile.id,
                            subPageIndex = subPageIndex,
                        }),
                    })
                end

                -- Stack sub-pages render one heading per featureId at runtime
                -- (see BuildFeatureStackPage). Mirror those headings as section
                -- nav entries so search ranks the heading label (e.g. "Action
                -- Tracker") instead of just the inner widget labels.
                if type(subPage) == "table" and type(subPage.featureIds) == "table" then
                    local registry = ns.Settings and ns.Settings.Registry
                    local renderAdapters = ns.Settings and ns.Settings.RenderAdapters
                    for _, item in ipairs(subPage.featureIds) do
                        local featureId, explicitLabel
                        if type(item) == "string" then
                            featureId = item
                        elseif type(item) == "table" and type(item.key) == "string" then
                            featureId = item.key
                            explicitLabel = item.label
                        end

                        local sectionLabel = explicitLabel
                        if featureId and (type(sectionLabel) ~= "string" or sectionLabel == "") then
                            local feature = registry and type(registry.GetFeature) == "function"
                                and registry:GetFeature(featureId) or nil
                            local providerKey = (feature and feature.providerKey) or featureId
                            if renderAdapters and type(renderAdapters.GetProviderLabel) == "function" then
                                sectionLabel = renderAdapters.GetProviderLabel(providerKey)
                            else
                                sectionLabel = providerKey
                            end
                        end

                        if type(sectionLabel) == "string" and sectionLabel ~= "" then
                            self:RegisterStaticNavigationEntry({
                                navType = "section",
                                label = BuildSearchNavigationLabel("section", {
                                    tabName = tile.config.name,
                                    subTabName = subPage.name,
                                    sectionName = sectionLabel,
                                    tileId = tile.id,
                                    subPageIndex = subPageIndex,
                                }),
                                tabName = tile.config.name,
                                subTabName = subPage.name,
                                sectionName = sectionLabel,
                                tileId = tile.id,
                                subPageIndex = subPageIndex,
                                featureId = featureId,
                                keywords = BuildSearchNavigationKeywords({
                                    tabName = tile.config.name,
                                    subTabName = subPage.name,
                                    sectionName = sectionLabel,
                                    tileId = tile.id,
                                    subPageIndex = subPageIndex,
                                }),
                            })
                        end
                    end
                end
            end
        end
    end
end

function GUI:SelectFeatureTile(frame, index, opts)
    frame._tiles = frame._tiles or {}
    local tile = frame._tiles[index]
    if not tile then return end

    -- Sidebar selection is "navigate elsewhere" — clear any stale search
    -- term so the user lands on the tile with a fresh search box (placeholder
    -- restored by CreateSearchBox's OnTextChanged). Search-driven navigation
    -- (NavigateSearchResult) sets opts.searchEntry and skips this so the term
    -- persists for "back to results".
    if not (opts and opts.searchEntry) and frame._searchBox and frame._searchBox.editBox then
        local box = frame._searchBox.editBox
        if box:GetText() ~= "" then
            box:SetText("")
            box:ClearFocus()
        end
    end

    -- Update sidebar active state
    for i, t in ipairs(frame._tiles) do
        local active = (i == index)
        t._isActive = active
        t.indicator:SetShown(active)
        if active then
            t.hoverBg:Show()
            t.hoverBg:SetColorTexture(C.accentFaint[1], C.accentFaint[2], C.accentFaint[3], C.accentFaint[4])
            t.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            if t.iconTexture then t.iconTexture:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1) end
            if t.icon then t.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end
        else
            t.hoverBg:Hide()
            t.hoverBg:SetColorTexture(1, 1, 1, 0.03)
            t.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1)
            if t.iconTexture then t.iconTexture:SetVertexColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.75) end
            if t.icon then t.icon:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.55) end
        end
    end
    frame._lastTileIndex = index

    -- Build the tile's page (hidden) if not yet done. Eager indexer
    -- usually has this already built — it's a no-op for cached tiles.
    GUI:BuildTilePage(frame, tile)

    -- Ensure content container is visible and search overlay is hidden.
    local content = frame._tileContent
    if content then content:Show() end
    if frame._searchResultsArea then frame._searchResultsArea:Hide() end

    -- Hide every other tile's page frame; show this one.
    for _, t in ipairs(frame._tiles) do
        if t._pageFrame and t ~= tile then t._pageFrame:Hide() end
    end
    tile._pageFrame:Show()

    -- Swap footer primary CTA to the newly selected tile's button (if any).
    if frame._tiles then
        for _, t in ipairs(frame._tiles) do
            if t._primaryBtn then t._primaryBtn:Hide() end
        end
    end
    if tile._primaryBtn then tile._primaryBtn:Show() end

    -- Switch sub-page if requested (search jump-to-setting).
    if opts and opts.subPageIndex and tile._subPageSelect then
        tile._subPageSelect(opts.subPageIndex)
    end

    if opts and type(opts.searchEntry) == "table" then
        self:ApplyFeatureSearchNavigation(tile, opts.searchEntry, opts)
    end

    -- Scroll to and pulse a specific widget (search jump-to-setting).
    if opts and (opts.scrollToPath or opts.scrollToLabel or opts.scrollToFeatureId) then
        C_Timer.After(0, function()
            local root = opts.searchRoot or tile._pageFrame
            local scrolledToSection = false

            -- Stack-page section results: BuildFeatureStackPage tags each
            -- feature title row with _quiSearchSectionFeatureId. Walk the
            -- frame tree (same approach as pinned-widget navigation) to
            -- find the tagged row and scroll its ancestor ScrollFrame to
            -- bring it into view. More robust than relying on stored
            -- _subPageBodies references because layout timing doesn't
            -- matter — we re-query the live frame tree at click time.
            if opts.scrollToFeatureId then
                local target = GUI:_findSectionByFeatureId(root, opts.scrollToFeatureId)
                if target then
                    local scroll = GUI:_findAncestorScroll(target)
                    if scroll then
                        local scrollChild = scroll.GetScrollChild and scroll:GetScrollChild() or nil
                        local bodyTop = scrollChild and scrollChild.GetTop and scrollChild:GetTop() or nil
                        local sectionTop = target.GetTop and target:GetTop() or nil
                        if bodyTop and sectionTop and scroll.SetVerticalScroll then
                            local offset = math.max(0, bodyTop - sectionTop)
                            pcall(scroll.SetVerticalScroll, scroll, offset)
                            scrolledToSection = true
                        end
                    end
                end
            end

            local target = nil
            if opts.scrollToPath then
                target = GUI:_findWidgetByPinnedPath(root, opts.scrollToPath)
            end
            if not target and opts.scrollToLabel then
                target = GUI:_findWidgetByLabel(root, opts.scrollToLabel)
            end
            if target then
                -- Only re-scroll when the section-anchor pass didn't already
                -- land us on the right card. The legacy widget-scroll math
                -- below uses screen-center coords which give wrong (often
                -- zero) absolute scroll values once any prior scroll has
                -- moved the widget near the viewport top — running it after
                -- the section anchor would yank scroll back to 0.
                if not scrolledToSection then
                    local scroll = GUI:_findAncestorScroll(target)
                    if scroll then
                        local scrollChild = scroll.GetScrollChild and scroll:GetScrollChild() or nil
                        local bodyTop = scrollChild and scrollChild.GetTop and scrollChild:GetTop() or nil
                        local widgetTop = target.GetTop and target:GetTop() or nil
                        if bodyTop and widgetTop and scroll.SetVerticalScroll then
                            -- Offset from scroll-child top to widget top is
                            -- invariant under scroll, so this gives the
                            -- correct absolute scroll value to bring the
                            -- widget into view (with ~50px breathing room).
                            local offset = math.max(0, bodyTop - widgetTop - 50)
                            pcall(scroll.SetVerticalScroll, scroll, offset)
                        end
                    end
                end
                if opts.pulse then GUI:PulseWidget(target) end
            end
        end)
    elseif opts and opts.sectionName and opts.searchTabIndex then
        C_Timer.After(0, function()
            GUI:ScrollToRegisteredSection(
                opts.searchTabIndex,
                opts.searchSubTabIndex,
                opts.sectionName
            )
        end)
    end

end

--[[
    GUI:AddSidebarSearchBar(frame)

    Creates an inline search box at the top of the sidebar. Uses the existing
    search index (ExecuteSearch / RenderSearchResults). Typing switches the
    content area to a results view; clearing restores the last selected tile.
]]
function GUI:AddSidebarSearchBar(frame)
    local container = CreateFrame("Frame", nil, frame.sidebar)
    container:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", 8, -10)
    container:SetPoint("TOPRIGHT", frame.sidebar, "TOPRIGHT", -8, -10)
    container:SetHeight(28)

    local box = GUI:CreateSearchBox(container)
    box:SetAllPoints(container)

    box.onSearch = function(text)
        if not text or text == "" then
            if frame._lastTileIndex then
                GUI:SelectFeatureTile(frame, frame._lastTileIndex)
            end
            return
        end
        frame._searchResultsArea = frame._searchResultsArea or GUI:_CreateV2SearchResultsArea(frame)
        frame._searchResultsArea:Show()
        if frame._tileContent then frame._tileContent:Hide() end
        local results, navResults = GUI:ExecuteSearch(text)
        -- Render into the scroll child so content is clipped to the viewport.
        GUI:RenderSearchResults(frame._searchResultsArea.inner, results, text, navResults)
    end
    box.onClear = function()
        if frame._searchResultsArea then frame._searchResultsArea:Hide() end
        if frame._tileContent then frame._tileContent:Show() end
    end

    frame._searchBox = box
    return box
end

-- Lazy-creates a results area that overlays the tile content area.
-- Uses shared CreateScrollableContent so the scrollbar matches QUI's
-- standard skinned scrollbar (thumb color, hidden arrows, auto-hide).
function GUI:_CreateV2SearchResultsArea(frame)
    -- Outer wrapper fills the content area; CreateScrollableContent's
    -- inset anchors handle the 5/5/28/5 padding to match other panels.
    local wrapper = CreateFrame("Frame", nil, frame.contentArea)
    wrapper:SetAllPoints(frame.contentArea)

    local scrollFrame, inner
    if ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
        scrollFrame, inner = ns.QUI_Options.CreateScrollableContent(wrapper)
    else
        scrollFrame = CreateFrame("ScrollFrame", nil, wrapper, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 5, -5)
        scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)
        inner = CreateFrame("Frame", nil, scrollFrame)
        inner:SetSize(math.max(1, scrollFrame:GetWidth()), 1)
        scrollFrame:SetScrollChild(inner)
    end

    wrapper.inner = inner
    wrapper.scrollFrame = scrollFrame
    wrapper:Hide()
    return wrapper
end

--[[
    GUI:RenderSubPageTabs(tile, contentArea, subPages, onSelect)

    Renders a horizontal tab bar at the top of contentArea with one button
    per subPage. Clicking a tab calls onSelect(subPage, tabBody) where
    tabBody is the area below the tab bar into which subPage.buildFunc
    should render its widgets. Clears tabBody between switches.
]]
function GUI:RenderSubPageTabs(tile, contentArea, subPages, onSelect, headerFrame)
    if not subPages or #subPages == 0 then return end

    -- Tab bar — anchor to header bottom when provided so a taller header
    -- (with subtitle) shifts the tabs down instead of overlapping. Bar is
    -- header-aligned (matches gameplay/cooldown_manager etc.) so chips
    -- visually line up under the header text. Body underneath extends past
    -- the bar to full contentArea width so page content and the optional
    -- section-nav chip strip span properly — see body anchors below.
    local bar = CreateFrame("Frame", nil, contentArea)
    if headerFrame then
        bar:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -8)
        bar:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -8)
    else
        bar:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 18, -70)
        bar:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -18, -70)
    end
    bar:SetHeight(28)

    -- Underline beneath the bar
    local underline = bar:CreateTexture(nil, "OVERLAY")
    underline:SetPoint("BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", 0, 0)
    underline:SetHeight(1)
    underline:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])

    -- Tab body below. Reserve 32px at the bottom when the tile has a
    -- related-settings footer so sub-page content doesn't sit under it.
    -- Body extends 18px past the bar's left so it's full-width relative to
    -- contentArea (matches the direct render path's container, which uses
    -- the same -18/+18 trick to extend past the header). Without this the
    -- section-nav chip strip — which anchors to scrollFrame:GetParent() —
    -- ends up 18px short on the left versus the direct path.
    local body = CreateFrame("Frame", nil, contentArea)
    local footerReserve = tile and tile.config and tile.config.relatedSettings and 32 or 0
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -18, -8)
    body:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, footerReserve)

    local tabs = {}
    local currentIndex = 1

    -- Per-sub-page body cache. Build once, then Hide/Show on switch.
    -- Prevents widget-instance leaks and preserves ephemeral state.
    tile._subPageBodies = tile._subPageBodies or {}

    local function select(i)
        currentIndex = i
        tile._activeSubPageIndex = i
        for j, t in ipairs(tabs) do
            if j == i then
                t.label:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
                t.activeBar:Show()
            else
                t.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1)
                t.activeBar:Hide()
            end
        end

        if tile and tile._crumb and tile.config then
            local crumbText = "Settings  >  " .. (tile.config.name or "")
            if tile.config.subPages and tile.config.subPages[i] and tile.config.subPages[i].name then
                crumbText = crumbText .. "  >  " .. tile.config.subPages[i].name
            end
            tile._crumb:SetText(crumbText)
        end

        -- Hide every cached sub-page body unconditionally. Must run BEFORE
        -- the lazy-build branch below: CreateFrame defaults a new frame to
        -- Shown, so a freshly-built container sits on top of any previously
        -- built-and-still-shown bodies in the shared body area. Registering
        -- the container in _subPageBodies BEFORE running the builder also
        -- prevents orphans leaking on builder error.
        for _, sub in pairs(tile._subPageBodies) do
            sub:Hide()
        end

        -- Lazily build this sub-page's body the first time it's selected.
        -- Each sub-page gets its own container. If the sub-page's builder
        -- doesn't self-wrap (BuildXxxTab pattern), we wrap it in a QUI-skinned
        -- scroll frame. If it DOES self-wrap (CreateXxxPage pattern → calls
        -- CreateScrollableContent internally), set noScroll=true on the
        -- sub-page entry so we don't nest scroll frames.
        if not tile._subPageBodies[i] then
            local sp = subPages[i]
            local container = CreateFrame("Frame", nil, body)
            container:SetAllPoints(body)
            container:Hide()
            tile._subPageBodies[i] = container

            local function installRegisterSection(targetBody)
                targetBody._sections = {}
                function targetBody:RegisterSection(id, label, frame)
                    if type(id) ~= "string" or id == "" or not frame then return end
                    local resolvedLabel = (type(label) == "string" and label ~= "") and label or id
                    -- Dedupe by id so partial re-renders that don't go through
                    -- ClearDynamicContent (e.g. provider notifications that
                    -- re-invoke the renderer in place) replace the stale frame
                    -- reference instead of growing the list. Without this the
                    -- chip strip's idx-based clicks land on hidden ghosts.
                    for i, existing in ipairs(self._sections) do
                        if existing.id == id then
                            self._sections[i] = { id = id, label = resolvedLabel, frame = frame }
                            return
                        end
                    end
                    self._sections[#self._sections + 1] = {
                        id = id,
                        label = resolvedLabel,
                        frame = frame,
                    }
                end
            end

            -- installRegisterSection must run before onSelect in each branch:
            -- onSelect triggers the page builder (e.g. BuildFeatureStackPage),
            -- which calls RegisterSection, so the method must already exist on
            -- contentBody by then. The guard in BuildFeatureStackPage drops
            -- registrations silently if the method is missing.
            local scrollFrame, contentBody
            if sp.noScroll then
                contentBody = container
                installRegisterSection(contentBody)
                onSelect(sp, contentBody)
            elseif ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
                scrollFrame, contentBody = ns.QUI_Options.CreateScrollableContent(container)
                installRegisterSection(contentBody)
                onSelect(sp, contentBody)
            else
                contentBody = container
                installRegisterSection(contentBody)
                onSelect(sp, contentBody)
            end

            container._scrollFrame = scrollFrame
            container._contentBody = contentBody

            -- Section nav strip (opt-in). Requires a scroll frame, ≥2
            -- registered sections, and content taller than the viewport.
            -- The strip is built lazily because contentBody height isn't
            -- known until the first layout pass settles.
            if sp.sectionNav and scrollFrame and #contentBody._sections >= 2 then
                local function tryBuildSectionNav()
                    if container._sectionNav then return end
                    local bodyH = contentBody:GetHeight() or 0
                    local viewH = scrollFrame:GetHeight() or 0
                    if bodyH > viewH and viewH > 0 then
                        container._sectionNav = GUI:RenderSectionNav(scrollFrame, contentBody, contentBody._sections)
                    end
                end

                -- Try immediately (covers the case where everything is
                -- already laid out by the time onSelect returns), then
                -- again after a frame so deferred layout settles.
                tryBuildSectionNav()
                C_Timer.After(0, tryBuildSectionNav)

                -- And also when content height changes — newly arriving
                -- content can flip the page from no-scroll to scroll.
                contentBody:HookScript("OnSizeChanged", function()
                    if not container._sectionNav then
                        C_Timer.After(0, tryBuildSectionNav)
                    end
                end)
            end
        end

        tile._subPageBodies[i]:Show()
    end

    local ROW_HEIGHT = 28
    local TAB_GAP_X = 16
    local TAB_GAP_Y = 4

    for i, sp in ipairs(subPages) do
        local btn = CreateFrame("Button", nil, bar)
        btn:SetHeight(ROW_HEIGHT)

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.label:SetText(sp.name)
        btn.label:SetPoint("CENTER", 0, 0)
        local f, _, fl = btn.label:GetFont()
        btn.label:SetFont(f or (ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(GUI:GetFontPath())) or f, 11, fl or "")

        local labelW = btn.label:GetStringWidth() + 24
        btn:SetWidth(labelW)

        btn.activeBar = btn:CreateTexture(nil, "OVERLAY")
        btn.activeBar:SetPoint("BOTTOMLEFT", 4, 0)
        btn.activeBar:SetPoint("BOTTOMRIGHT", -4, 0)
        btn.activeBar:SetHeight(2)
        btn.activeBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        btn.activeBar:Hide()

        btn:SetScript("OnClick", function() select(i) end)

        tabs[i] = btn
    end

    -- Flow tabs onto multiple rows when the bar is too narrow to hold them
    -- all on one line. Re-runs on OnSizeChanged so resizing the settings
    -- window (or populating during layout) reflows correctly.
    local function LayoutTabs()
        local barWidth = bar:GetWidth()
        if not barWidth or barWidth <= 0 then return end

        local x, y = 0, 0
        local rows = 1
        for _, btn in ipairs(tabs) do
            local w = btn:GetWidth()
            if x > 0 and (x + w) > barWidth then
                x = 0
                y = y - (ROW_HEIGHT + TAB_GAP_Y)
                rows = rows + 1
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
            x = x + w + TAB_GAP_X
        end
        bar:SetHeight(rows * ROW_HEIGHT + math.max(rows - 1, 0) * TAB_GAP_Y)
    end
    bar:SetScript("OnSizeChanged", LayoutTabs)
    LayoutTabs()

    tile._subPageSelect = select
    -- Auto-select first sub-page
    select(1)

    return body, select
end

--[[
    GUI:RenderSectionNav(scrollFrame, body, sections, options)

    Builds a sticky chip strip pinned to the top of scrollFrame. Each chip
    jumps the scroll to the corresponding section's anchor frame, with a
    short ease-out tween. Scroll-spy updates the active chip as the user
    scrolls. Chips wrap to multiple rows when they don't fit one row.

    sections: array of { id, label, frame } registered via body:RegisterSection.
    options: reserved for future use (currently unused).

    The strip is parented to scrollFrame:GetParent() so it sits above the
    viewport and never moves with content. The scrollFrame's TOPLEFT anchor
    is shifted down by the strip's measured height to make room.
]]
function GUI:RenderSectionNav(scrollFrame, body, sections, options)
    options = options or {}
    if type(sections) ~= "table" or #sections < 2 then return nil end
    if not scrollFrame or not body then return nil end

    local C = self.Colors or {}
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local CHIP_HEIGHT = 22
    local CHIP_PAD_X = 10
    local CHIP_GAP_X = 8
    local CHIP_GAP_Y = 6
    local STRIP_PAD_TOP = 4
    local STRIP_PAD_BOTTOM = 4
    local ACTIVE_THRESHOLD = 12
    local TWEEN_DURATION = 0.12

    -- Strip parented to the scroll frame's parent so it doesn't scroll.
    -- Anchor to stripParent (not scrollFrame) so relayoutChips can push
    -- scrollFrame down by stripH without dragging the strip with it.
    -- The 5/-28/-5 insets mirror CreateScrollableContent's left/right margins
    -- so the strip aligns horizontally with where the scroll viewport was.
    local stripParent = scrollFrame:GetParent()
    local strip = CreateFrame("Frame", nil, stripParent)
    strip:SetPoint("TOPLEFT", stripParent, "TOPLEFT", 5, -5)
    strip:SetPoint("TOPRIGHT", stripParent, "TOPRIGHT", -28, -5)
    strip:SetFrameLevel((scrollFrame:GetFrameLevel() or 0) + 5)

    local chips = {}
    local activeIdx = nil

    local function setActive(idx)
        if idx == activeIdx then return end
        if activeIdx and chips[activeIdx] then
            chips[activeIdx].label:SetTextColor(0.7, 0.7, 0.7, 1)
            chips[activeIdx].underline:Hide()
        end
        if idx and chips[idx] then
            chips[idx].label:SetTextColor(accent[1], accent[2], accent[3], 1)
            chips[idx].underline:Show()
        end
        activeIdx = idx
    end

    -- Build chip buttons.
    for i, section in ipairs(sections) do
        local chip = CreateFrame("Button", nil, strip)
        chip:SetHeight(CHIP_HEIGHT)

        local hover = chip:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.06)
        hover:Hide()

        local label = chip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText(section.label or section.id or "?")
        local f, _, fl = label:GetFont()
        label:SetFont(f or (ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(self:GetFontPath())) or f, 11, fl or "")
        label:SetPoint("LEFT", CHIP_PAD_X, 0)
        label:SetTextColor(0.7, 0.7, 0.7, 1)
        chip.label = label

        local underline = chip:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", CHIP_PAD_X, 1)
        underline:SetPoint("BOTTOMRIGHT", -CHIP_PAD_X, 1)
        underline:SetHeight(1)
        underline:SetColorTexture(accent[1], accent[2], accent[3], 1)
        underline:Hide()
        chip.underline = underline

        local labelW = label:GetStringWidth()
        chip:SetWidth(labelW + CHIP_PAD_X * 2)

        chip:SetScript("OnEnter", function() hover:Show() end)
        chip:SetScript("OnLeave", function() hover:Hide() end)

        chips[i] = chip
    end

    -- Wrap layout: flow chips left-to-right, wrap when they'd exceed strip width.
    local function relayoutChips()
        local stripWidth = strip:GetWidth() or 0
        if stripWidth <= 0 then
            stripWidth = scrollFrame:GetWidth() or 600
        end

        local x = 0
        local row = 0
        for _, chip in ipairs(chips) do
            local w = chip:GetWidth()
            if x > 0 and x + w > stripWidth then
                row = row + 1
                x = 0
            end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -(STRIP_PAD_TOP + row * (CHIP_HEIGHT + CHIP_GAP_Y)))
            x = x + w + CHIP_GAP_X
        end
        local rows = row + 1
        local stripH = STRIP_PAD_TOP + rows * CHIP_HEIGHT + (rows - 1) * CHIP_GAP_Y + STRIP_PAD_BOTTOM
        strip:SetHeight(stripH)

        -- Push the scroll frame's top down by stripH. The 5/-28/5 inset
        -- numbers mirror CreateScrollableContent's defaults — keep in sync
        -- if those ever change.
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", stripParent, "TOPLEFT", 5, -5 - stripH)
        scrollFrame:SetPoint("BOTTOMRIGHT", stripParent, "BOTTOMRIGHT", -28, 5)
    end

    strip:SetScript("OnSizeChanged", function() relayoutChips() end)

    -- Anchor offset cache. Recomputed on body resize and after layout settles.
    local anchors = {}
    local function refreshOffsets()
        wipe(anchors)
        local bodyTop = body:GetTop() or 0
        for i, section in ipairs(sections) do
            if section.frame and section.frame:IsShown() then
                local frameTop = section.frame:GetTop() or bodyTop
                local offset = math.max(0, bodyTop - frameTop)
                anchors[#anchors + 1] = { offset = offset, idx = i }
            end
        end
        table.sort(anchors, function(a, b) return a.offset < b.offset end)
    end

    -- Smooth-scroll tween. Suppresses scroll-spy during the tween so the
    -- active chip we set on click doesn't get overwritten by the spy.
    local activeTicker = nil
    local tweenSuppressionUntil = 0

    local function smoothScrollTo(target)
        local current = scrollFrame:GetVerticalScroll() or 0
        local maxScroll = scrollFrame:GetVerticalScrollRange() or 0
        if target < 0 then target = 0 end
        if target > maxScroll then target = maxScroll end
        local distance = target - current
        if math.abs(distance) < 1 then
            scrollFrame:SetVerticalScroll(target)
            return
        end
        if activeTicker then activeTicker:Cancel() end
        local startTime = GetTime()
        tweenSuppressionUntil = startTime + TWEEN_DURATION + 0.05
        activeTicker = C_Timer.NewTicker(0.016, function(ticker)
            local t = (GetTime() - startTime) / TWEEN_DURATION
            if t >= 1 then
                scrollFrame:SetVerticalScroll(target)
                ticker:Cancel()
                activeTicker = nil
                return
            end
            -- Ease-out cubic.
            local eased = 1 - (1 - t) ^ 3
            scrollFrame:SetVerticalScroll(current + distance * eased)
        end)
    end

    for i, chip in ipairs(chips) do
        chip:SetScript("OnClick", function()
            setActive(i)
            refreshOffsets()
            for _, a in ipairs(anchors) do
                if a.idx == i then
                    smoothScrollTo(a.offset - ACTIVE_THRESHOLD)
                    return
                end
            end
        end)
    end

    -- Scroll-spy: linear scan over the sorted anchor list (section count
    -- is small in practice). Suppressed during the click-driven tween so
    -- the click-flip wins over the spy.
    scrollFrame:HookScript("OnVerticalScroll", function(_, scrollOffset)
        if GetTime() < tweenSuppressionUntil then return end
        if #anchors == 0 then return end
        local foundIdx = nil
        for _, a in ipairs(anchors) do
            if a.offset <= scrollOffset + ACTIVE_THRESHOLD then
                foundIdx = a.idx
            else
                break
            end
        end
        if foundIdx then setActive(foundIdx) end
    end)

    body:HookScript("OnSizeChanged", function()
        C_Timer.After(0, refreshOffsets)
    end)

    relayoutChips()

    -- Defer initial offset compute and active-chip set so layout settles
    -- before we measure.
    C_Timer.After(0, function()
        refreshOffsets()
        setActive(1)
    end)

    return {
        frame = strip,
        setActive = setActive,
        refreshOffsets = refreshOffsets,
        relayoutChips = relayoutChips,
        destroy = function()
            if activeTicker then
                activeTicker:Cancel()
                activeTicker = nil
            end
            scrollFrame:ClearAllPoints()
            scrollFrame:SetPoint("TOPLEFT", stripParent, "TOPLEFT", 5, -5)
            scrollFrame:SetPoint("BOTTOMRIGHT", stripParent, "BOTTOMRIGHT", -28, 5)
            strip:Hide()
            strip:SetParent(nil)
        end,
    }
end

--[[
    GUI:AddToolsStripButton(frame, config)

    Registers an action button in the sidebar Tools strip. The strip is
    created lazily on first call. Each button is a tool, not a tab — clicks
    fire config.onClick without changing the selected tile.

    config fields:
        id       (string, required)
        iconTexture (string, optional) - texture path shown before label
        icon     (string, optional) - legacy text prefix fallback
        label    (string, required)
        onClick  (function, required)
]]
function GUI:AddToolsStripButton(frame, config)
    assert(type(config) == "table", "AddToolsStripButton: config required")
    assert(config.id, "config.id required")
    assert(config.label, "config.label required")
    assert(type(config.onClick) == "function", "config.onClick required")

    frame._tools = frame._tools or {}

    if not frame._toolsStrip then
        local strip = CreateFrame("Frame", nil, frame.sidebar)
        -- Single-column layout: strip holds the TOOLS heading plus a stack
        -- of full-width buttons. Height fits 2 rows (heading + 2 buttons).
        strip:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMLEFT", 6, 24)
        strip:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", -6, 24)
        strip:SetHeight(72)

        local sep = strip:CreateTexture(nil, "OVERLAY")
        sep:SetPoint("TOPLEFT", 2, 0)
        sep:SetPoint("TOPRIGHT", -2, 0)
        sep:SetHeight(1)
        sep:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])

        local heading = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", 4, -6)
        heading:SetText("TOOLS")
        heading:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.5)

        frame._toolsStrip = strip
    end

    local strip = frame._toolsStrip
    local idx = #frame._tools + 1

    local btn = CreateFrame("Button", nil, strip, "BackdropTemplate")
    btn:SetHeight(24)
    -- Full-width, one button per row. strip:GetWidth() returns 0 at build
    -- time because the strip itself is anchored (not sized), so we derive
    -- the width from the strip's left/right anchors via dual anchoring.
    local yOffset = -20 - (idx - 1) * 26
    btn:SetPoint("TOPLEFT", strip, "TOPLEFT", 4, yOffset)
    btn:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -4, yOffset)

    QUICore.SafeSetBackdrop(btn, {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(1, 1, 1, 0.06)
    btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])

    local iconTexturePath = config.iconTexture
    if iconTexturePath == nil and config.id then
        iconTexturePath = Helpers.AssetPath .. "sidebar_tools\\" .. config.id
    end

    if iconTexturePath then
        local ICON_SIZE = 14
        local GAP = 7

        local content = CreateFrame("Frame", nil, btn)
        content:SetHeight(ICON_SIZE)
        content:SetPoint("CENTER", btn, "CENTER", 0, 0)

        local icon = content:CreateTexture(nil, "OVERLAY")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", content, "LEFT", 0, 0)
        icon:SetTexture(iconTexturePath)
        icon:SetVertexColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.9)
        btn.iconTexture = icon

        local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", GAP, 0)
        label:SetText(config.label)
        label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1)
        btn.label = label
        btn._content = content

        local contentWidth = ICON_SIZE + GAP + math.ceil(label:GetStringWidth())
        content:SetWidth(contentWidth)
    else
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", 0, 0)
        label:SetText(((config.icon and (config.icon .. " ")) or "") .. config.label)
        label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1)
        btn.label = label
    end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.accentFaint[1], C.accentFaint[2], C.accentFaint[3], 0.12)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.3)
        if self.iconTexture then
            self.iconTexture:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(1, 1, 1, 0.06)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
        if self.iconTexture then
            self.iconTexture:SetVertexColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.9)
        end
    end)
    btn:SetScript("OnClick", function() config.onClick() end)

    frame._tools[idx] = btn
    return btn
end

--[[
    Navigation mapping: (tabIndex, subTabIndex) -> (tileId, subPageIndex).

    Each tile's Register() declares which (tabIndex, subTabIndex)
    coordinates it absorbs. Search entries are keyed by those coordinates;
    this map translates them to (tileId, subPageIndex) for jump-to-setting.

    Key format: "tabIndex:subTabIndex" (subTabIndex may be 0 for tiles
    that absorbed a top-level tab with no sub-tabs).
]]
GUI._navMap = GUI._navMap or {}

function GUI:RegisterV2NavRoute(tabIndex, subTabIndex, tileId, subPageIndex)
    local key = (tabIndex or 0) .. ":" .. (subTabIndex or 0)
    -- Preserve nil subPageIndex (tile-only route with no sub-page target).
    -- Fallback registrations use this so the breadcrumb shows just the
    -- tile name rather than an arbitrary sub-page name.
    GUI._navMap[key] = { tileId = tileId, subPageIndex = subPageIndex }
end

function GUI:ResolveV2Navigation(tabIndex, subTabIndex)
    local key = (tabIndex or 0) .. ":" .. (subTabIndex or 0)
    local match = GUI._navMap[key]
    if not match and subTabIndex then
        match = GUI._navMap[(tabIndex or 0) .. ":0"]
    end
    return match
end

function GUI:FindV2TileByID(frame, tileId)
    if not frame or not frame._tiles then return nil end
    for i, tile in ipairs(frame._tiles) do
        if tile.id == tileId then
            return tile, i
        end
    end
end

function GUI:IsSearchRouteCompatible(route, entry)
    if not route or not entry then return false end

    local frame = self.MainFrame
    if not frame then return false end

    local tile = self:FindV2TileByID(frame, route.tileId)
    if not tile then return false end

    local tileName = NormalizeSearchText(tile.config and tile.config.name or route.tileId)
    local subPageName = ""
    if route.subPageIndex and tile.config and tile.config.subPages then
        local subPage = tile.config.subPages[route.subPageIndex]
        subPageName = NormalizeSearchText(subPage and subPage.name or "")
    end

    local expectedSub = NormalizeSearchText(entry.subTabName)
    if expectedSub ~= "" then
        return expectedSub == subPageName or expectedSub == tileName
    end

    local expectedTab = NormalizeSearchText(entry.tabName)
    if expectedTab ~= "" then
        return expectedTab == subPageName or expectedTab == tileName
    end

    return true
end

function GUI:FindSearchRouteByName(entry)
    if not entry then return nil end

    local frame = self.MainFrame
    if not frame or not frame._tiles then return nil end

    local function FindUniqueSubPage(name)
        local normalized = NormalizeSearchText(name)
        if normalized == "" then return nil end

        local matches = {}
        for _, tile in ipairs(frame._tiles) do
            local subPages = tile.config and tile.config.subPages
            if subPages then
                for idx, subPage in ipairs(subPages) do
                    if NormalizeSearchText(subPage and subPage.name or "") == normalized then
                        matches[#matches + 1] = { tileId = tile.id, subPageIndex = idx }
                    end
                end
            end
        end

        if #matches == 1 then
            return matches[1]
        end
        return nil
    end

    local route = FindUniqueSubPage(entry.subTabName)
    if route then return route end

    route = FindUniqueSubPage(entry.tabName)
    if route then return route end

    local normalizedTab = NormalizeSearchText(entry.tabName)
    if normalizedTab ~= "" then
        local match = nil
        for _, tile in ipairs(frame._tiles) do
            local tileName = NormalizeSearchText(tile.config and tile.config.name or tile.id)
            if tileName == normalizedTab then
                if match then
                    return nil
                end
                match = { tileId = tile.id }
            end
        end
        return match
    end

    return nil
end

local function AreSearchRoutesEquivalent(a, b)
    if not a or not b then
        return false
    end
    if a.tileId ~= b.tileId then
        return false
    end
    if a.subPageIndex ~= nil and b.subPageIndex ~= nil and a.subPageIndex ~= b.subPageIndex then
        return false
    end
    return true
end

function GUI:ResolveSearchNavigation(entry)
    if not entry then return nil end

    local directRoute = nil
    if type(entry.tileId) == "string" and entry.tileId ~= "" then
        directRoute = {
            tileId = entry.tileId,
            subPageIndex = entry.subPageIndex,
        }
    end

    local tabIndex = entry.tabIndex or 0
    local subTabIndex = entry.subTabIndex or 0
    local exactRoute = GUI._navMap and GUI._navMap[tabIndex .. ":" .. subTabIndex]
    local fallbackRoute = self:ResolveV2Navigation(entry.tabIndex, entry.subTabIndex)
    local nameRoute = self:FindSearchRouteByName(entry)
    local tabRoute = exactRoute or fallbackRoute

    if directRoute then
        if tabRoute and not AreSearchRoutesEquivalent(directRoute, tabRoute) then
            directRoute = nil
        elseif tabRoute then
            -- When the saved explicit route agrees with the legacy tab route,
            -- trust it even if the V2 tile does not expose a matching human
            -- sub-page label (for example legacy "General" subtabs now living
            -- inside a single tile surface).
            return directRoute
        elseif not self:IsSearchRouteCompatible(directRoute, entry) then
            directRoute = nil
        else
            return directRoute
        end
    end

    if exactRoute then
        -- Explicit nav-map registrations are authoritative. Name matching is
        -- only a heuristic fallback and can misroute generic labels like
        -- "General" to the wrong tile.
        return exactRoute
    end

    if fallbackRoute then
        -- Fallback tab routes are also more reliable than fuzzy name lookup
        -- for tiles that absorbed several legacy subtabs into one page.
        return fallbackRoute
    end

    return nameRoute
end

function GUI:GetSearchBreadcrumb(entry)
    if not entry then return nil end

    local frame = self.MainFrame
    if not frame then return nil end

    local route = self:ResolveSearchNavigation(entry)
    if route then
        local tile = self:FindV2TileByID(frame, route.tileId)
        if tile then
            local parts = { tile.config and tile.config.name or route.tileId }
            if route.subPageIndex and tile.config and tile.config.subPages then
                local subPage = tile.config.subPages[route.subPageIndex]
                if subPage and subPage.name then
                    table.insert(parts, subPage.name)
                end
            end
            if entry.sectionName and entry.sectionName ~= "" then
                table.insert(parts, entry.sectionName)
            end
            return parts
        end
    end

    local parts = {}
    if entry.tabName and entry.tabName ~= "" then table.insert(parts, entry.tabName) end
    if entry.subTabName and entry.subTabName ~= "" then table.insert(parts, entry.subTabName) end
    if entry.sectionName and entry.sectionName ~= "" then table.insert(parts, entry.sectionName) end
    if #parts > 0 then return parts end

    return self:GetV2Breadcrumb(entry.tabIndex, entry.subTabIndex, entry.sectionName)
end

function GUI:NavigateSearchResult(entry, opts)
    local frame = self.MainFrame
    if not frame or not entry then return end

    local route = self:ResolveSearchNavigation(entry)
    if not route then return end

    local _, idx = self:FindV2TileByID(frame, route.tileId)
    if not idx then return end

    -- Hide the results overlay and reveal the tile content, but keep the
    -- search term in the box: focusing it again re-opens the results overlay
    -- (see CreateSearchBox OnEditFocusGained — "back to results"). The X
    -- button or a sidebar tile click is the explicit way to reset the search.
    if frame._searchResultsArea then
        frame._searchResultsArea:Hide()
    end
    if frame._tileContent then
        frame._tileContent:Show()
    end

    local selectOpts = {
        subPageIndex = route.subPageIndex,
        sectionName = entry.sectionName,
        searchTabIndex = entry.tabIndex,
        searchSubTabIndex = entry.subTabIndex,
        searchEntry = entry,
        -- Stack-page section results carry the featureId of the title row
        -- registered by BuildFeatureStackPage. Forwarding it triggers the
        -- scroll-to-section path in SelectFeatureTile so the user lands at
        -- the matching feature card instead of the top of the sub-page.
        scrollToFeatureId = (entry.navType == "section" and entry.featureId) or nil,
    }
    if opts then
        for key, value in pairs(opts) do
            selectOpts[key] = value
        end
    end

    self:SelectFeatureTile(frame, idx, selectOpts)
end

function GUI:ApplyFeatureSearchNavigation(tile, entry, opts)
    if not tile or type(entry) ~= "table" then
        return false
    end

    local featureId = entry.featureId
    if (type(featureId) ~= "string" or featureId == "") and tile.config then
        featureId = tile.config.featureId
    end
    if type(featureId) ~= "string" or featureId == "" then
        return false
    end

    local settings = ns.Settings
    local registry = settings and settings.Registry
    local feature = registry
        and type(registry.GetFeature) == "function"
        and registry:GetFeature(featureId)
        or nil
    if not feature or type(feature.searchNavigate) ~= "function" then
        return false
    end

    local ok, handled = pcall(feature.searchNavigate, entry, {
        tile = tile,
        pageFrame = tile._pageFrame,
        opts = opts,
    })
    return ok and handled ~= false
end

--[[
    GUI:GetV2Breadcrumb(tabIndex, subTabIndex, sectionName)

    Resolves a (tab, subtab) coordinate through the nav map and returns
    breadcrumb parts using tile/sub-page display names.

    Always returns a non-nil table when a main frame exists. Resolution
    tiers:
      1. Exact (tab, subtab) match → tile + sub-page
      2. (tab, 0) fallback → tile only
      3. First tile that registered any route for this tab → tile only
      4. Final fallback → "Settings" + sectionName

    Returns nil only if the main frame hasn't been created yet.
]]
function GUI:GetV2Breadcrumb(tabIndex, subTabIndex, sectionName)
    local frame = self.MainFrame
    if not frame then return nil end

    -- Tier 1 + 2: direct map lookup (ResolveV2Navigation already does the :0 fallback).
    local route = self:ResolveV2Navigation(tabIndex, subTabIndex)

    -- Tier 3: no exact or :0 match — find ANY route for this tab so at
    -- least the tile name is sensible.
    if not route and tabIndex and GUI._navMap then
        local prefix = tabIndex .. ":"
        for key, mapping in pairs(GUI._navMap) do
            if key:sub(1, #prefix) == prefix then
                route = { tileId = mapping.tileId }  -- drop subPageIndex: we don't know which
                break
            end
        end
    end

    local tile = route and self:FindV2TileByID(frame, route.tileId)

    -- Tier 4: still nothing — synthesize a generic breadcrumb so the caller
    -- always has something sensible to display.
    if not tile then
        local parts = { "Settings" }
        if sectionName and sectionName ~= "" then table.insert(parts, sectionName) end
        return parts
    end

    local parts = { tile.config and tile.config.name or route.tileId }
    if route.subPageIndex and tile.config and tile.config.subPages then
        local sp = tile.config.subPages[route.subPageIndex]
        if sp and sp.name then table.insert(parts, sp.name) end
    end
    if sectionName and sectionName ~= "" then
        table.insert(parts, sectionName)
    end
    return parts
end

--[[
    GUI:PulseWidget(widget)

    Briefly flashes an accent-colored overlay over `widget` to draw the user's
    eye after a search jump-to-setting navigation. Reuses a cached overlay
    texture per widget to avoid leaking textures on repeat pulses.
]]
function GUI:PulseWidget(widget)
    if not widget then return end
    local pulse = widget._pulseOverlay
    if not pulse then
        pulse = widget:CreateTexture(nil, "OVERLAY")
        pulse:SetAllPoints(widget)
        pulse:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.45)
        pulse:SetAlpha(0)
        widget._pulseOverlay = pulse
    end
    if pulse._anim then pulse._anim:Stop() end
    local ag = pulse:CreateAnimationGroup()
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.1); fadeIn:SetOrder(1)
    local hold = ag:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(0.2); hold:SetOrder(2)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.3); fadeOut:SetOrder(3)
    pulse._anim = ag
    ag:Play()
end

-- Walk the descendant tree under `root` and return the first frame whose
-- stored `_widgetLabel` equals `label`. Falls back to matching FontString
-- child text as a last resort.
function GUI:_findWidgetByLabel(root, label)
    if not root or not label then return nil end
    if root._widgetLabel == label then return root end
    local n = root.GetNumChildren and root:GetNumChildren() or 0
    for i = 1, n do
        local child = select(i, root:GetChildren())
        if child then
            local match = GUI:_findWidgetByLabel(child, label)
            if match then return match end
        end
    end
    local r = root.GetNumRegions and root:GetNumRegions() or 0
    for i = 1, r do
        local region = select(i, root:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            if region.GetText and region:GetText() == label then return root end
        end
    end
    return nil
end

function GUI:_findWidgetByPinnedPath(root, path)
    if not root or type(path) ~= "string" or path == "" then
        return nil
    end

    local binding = root._quiPinBinding
    if type(binding) == "table" and binding.path == path then
        return root
    end

    local n = root.GetNumChildren and root:GetNumChildren() or 0
    for i = 1, n do
        local child = select(i, root:GetChildren())
        if child then
            local match = GUI:_findWidgetByPinnedPath(child, path)
            if match then
                return match
            end
        end
    end

    return nil
end

function GUI:_findAncestorScroll(frame)
    local p = frame and frame.GetParent and frame:GetParent()
    while p do
        if p.GetObjectType and p:GetObjectType() == "ScrollFrame" then return p end
        p = p.GetParent and p:GetParent() or nil
    end
end

-- Walks the frame tree under root looking for a section title row tagged
-- with _quiSearchSectionFeatureId == featureId (set by BuildFeatureStackPage).
-- Same approach as _findWidgetByPinnedPath — re-queries the live tree at
-- click time, so layout/build timing doesn't matter.
function GUI:_findSectionByFeatureId(root, featureId)
    if not root or type(featureId) ~= "string" or featureId == "" then
        return nil
    end
    if root._quiSearchSectionFeatureId == featureId then
        return root
    end
    local n = root.GetNumChildren and root:GetNumChildren() or 0
    for i = 1, n do
        local child = select(i, root:GetChildren())
        if child then
            local match = GUI:_findSectionByFeatureId(child, featureId)
            if match then return match end
        end
    end
    return nil
end

--[[
    GUI:FocusSearchBox()
    Puts keyboard focus on the V2 sidebar search box and highlights any
    existing text. Used by the `/` and `Ctrl+F` keyboard shortcuts.
]]
function GUI:FocusSearchBox()
    local frame = self.MainFrame
    if not frame or not frame._searchBox then return end
    local box = frame._searchBox.editBox or frame._searchBox
    if box and box.SetFocus then
        box:SetFocus()
        if box.HighlightText then pcall(box.HighlightText, box) end
    end
end

-- Store reference
QUI.GUI = GUI
