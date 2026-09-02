local ADDON_NAME, ns = ...
local QUI = QUI
local QUICore = ns.Addon
local UIKit = ns.UIKit
local SkinBase = ns.SkinBase
local LSM = LibStub("LibSharedMedia-3.0")

QUI.GUI = QUI.GUI or {}
local GUI = QUI.GUI

-- Palette owner: core/theme.lua (root addon, QUI.toc; this LoD addon requires
-- QUI so it is always loaded first). Headless harnesses load core/theme.lua
-- before this file too (tools/generate_search_cache.lua). The `or {}` keeps the
-- merge contract (options_lod_theme_core_test); no role is defined here.
GUI.Colors = GUI.Colors or {}

GUI.DIALOG_BUTTON_BG = { 0.15, 0.15, 0.15, 1 }
GUI.CHECKBOX_BG      = { 0.1, 0.1, 0.1, 1 }
GUI.SLIDER_BG        = { 0.1, 0.1, 0.1, 1 }
GUI.GRID_BG          = { 0.1, 0.1, 0.1, 1 }
GUI.BORDER_INACTIVE  = { 0.3, 0.3, 0.3, 1 }
GUI.BORDER_SWATCH    = { 0.4, 0.4, 0.4, 1 }
GUI.ERROR_TEXT       = { 0.9, 0.3, 0.3, 1 }
GUI.DESCRIPTION_TEXT = GUI.Colors.textDim or { 1, 1, 1, 0.6 }

local C = GUI.Colors

local C_accent_r, C_accent_g, C_accent_b, C_accent_a = C.accent[1], C.accent[2], C.accent[3], C.accent[4]
local C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a = C.accentHover[1], C.accentHover[2], C.accentHover[3], C.accentHover[4]
local C_accentLight_r, C_accentLight_g, C_accentLight_b, C_accentLight_a = C.accentLight[1], C.accentLight[2], C.accentLight[3], C.accentLight[4]
local C_text_r, C_text_g, C_text_b, C_text_a = C.text[1], C.text[2], C.text[3], C.text[4]
local C_border_r, C_border_g, C_border_b, C_border_a = C.border[1], C.border[2], C.border[3], C.border[4]
local C_tabHover_r, C_tabHover_g, C_tabHover_b, C_tabHover_a = C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4]
local C_tabNormal_r, C_tabNormal_g, C_tabNormal_b, C_tabNormal_a = C.tabNormal[1], C.tabNormal[2], C.tabNormal[3], C.tabNormal[4]
local C_accentText_r, C_accentText_g, C_accentText_b, C_accentText_a = C.accentText[1], C.accentText[2], C.accentText[3], C.accentText[4]

local function RefreshCachedColors()
    C_accent_r, C_accent_g, C_accent_b, C_accent_a = C.accent[1], C.accent[2], C.accent[3], C.accent[4]
    C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a = C.accentHover[1], C.accentHover[2], C.accentHover[3], C.accentHover[4]
    C_accentLight_r, C_accentLight_g, C_accentLight_b, C_accentLight_a = C.accentLight[1], C.accentLight[2], C.accentLight[3], C.accentLight[4]
    C_text_r, C_text_g, C_text_b, C_text_a = C.text[1], C.text[2], C.text[3], C.text[4]
    C_border_r, C_border_g, C_border_b, C_border_a = C.border[1], C.border[2], C.border[3], C.border[4]
    C_tabHover_r, C_tabHover_g, C_tabHover_b, C_tabHover_a = C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4]
    C_tabNormal_r, C_tabNormal_g, C_tabNormal_b, C_tabNormal_a = C.tabNormal[1], C.tabNormal[2], C.tabNormal[3], C.tabNormal[4]
    C_accentText_r, C_accentText_g, C_accentText_b, C_accentText_a = C.accentText[1], C.accentText[2], C.accentText[3], C.accentText[4]
end
GUI.RefreshCachedColors = RefreshCachedColors

local function ApplyToggleVisual(t, isOn, isHovered)
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

function GUI:SetTooltipInfo(frame, description, label)
    if not frame or type(description) ~= "string" or description == "" then return false end
    frame._quiTooltipDescription = description
    frame._quiTooltipLabel = label
    return true
end

function GUI:GetTooltipTitleColor()
    local accent = self.Colors and self.Colors.accent or C.accent
    return accent[1] or 1, accent[2] or 1, accent[3] or 1, accent[4] or 1
end

function GUI:AttachTooltip(frame, description, label)
    if not GUI:SetTooltipInfo(frame, description, label) then return end
    if type(frame.HookScript) ~= "function" then return end
    if type(frame.EnableMouse) == "function" then frame:EnableMouse(true) end
    frame._quiHasBaseTooltip = true
    frame:HookScript("OnEnter", function(self)
        local db = _G.QUI and _G.QUI.db and _G.QUI.db.profile
        if db and db.general and db.general.showOptionTooltips == false then return end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if type(label) == "string" and label ~= "" then
            GameTooltip:SetText(label, GUI:GetTooltipTitleColor())
            GameTooltip:AddLine(description, 1, 1, 1, true)
        else
            GameTooltip:SetText(description, 1, 1, 1, 1, true)
        end
        if type(self._quiTooltipAugment) == "function" then
            ns.SafeCallMethod("bulkhead", self, "_quiTooltipAugment", GameTooltip)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then
            GameTooltip:Hide()
        end
    end)
end

-- GUI:ApplyAccentColor lives in core/theme.lua (single palette owner); it
-- recomputes every derived role and calls GUI:RefreshCachedColors() above.

GUI.ThemePresets = GUI.ThemePresets or {
    { name = "Sky Blue",     color = {0.376, 0.647, 0.980} },
    { name = "Classic Mint", color = {0.204, 0.827, 0.600} },
    { name = "Horde",        color = {0.780, 0.192, 0.192} },
    { name = "Alliance",     color = {0.267, 0.467, 0.800} },
    { name = "Midnight",     color = {0.580, 0.490, 0.890} },
    { name = "Amber",        color = {0.961, 0.620, 0.043} },
    { name = "Rose",         color = {0.914, 0.349, 0.518} },
    { name = "Emerald",      color = {0.196, 0.804, 0.494} },
}

function GUI:ResolveThemePreset(presetName)
    for _, preset in ipairs(self.ThemePresets or {}) do
        if preset.name == presetName then
            return preset.color[1], preset.color[2], preset.color[3]
        end
    end
    if presetName == "Class Colored" then
        local _, class = UnitClass("player")
        -- @secret-policy: collapse-only — UnitClass can return SECRET on 12.1 PTR7
        if issecretvalue and issecretvalue(class) then class = nil end
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
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
    return 0.376, 0.647, 0.980
end

GUI.PANEL_WIDTH = 1000
GUI.SIDEBAR_WIDTH = 190
GUI.CONTENT_WIDTH = 800

GUI.PANEL_MIN_WIDTH = 750
GUI.PANEL_MAX_WIDTH = 1200
GUI.PANEL_MIN_HEIGHT = 400
GUI.PANEL_MAX_HEIGHT = 1200
GUI.PANEL_SCREEN_MARGIN = 40

local function PanelScreenLimit(frame, available, minSize, maxSize)
    local scale = frame and frame.GetScale and frame:GetScale()
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local room = math.floor(((available or 0) - GUI.PANEL_SCREEN_MARGIN) / scale)
    return math.max(minSize, math.min(maxSize, room))
end

function GUI:MaxPanelWidth(frame)
    return PanelScreenLimit(frame, UIParent:GetWidth(), self.PANEL_MIN_WIDTH, self.PANEL_MAX_WIDTH)
end

function GUI:MaxPanelHeight(frame)
    return PanelScreenLimit(frame, UIParent:GetHeight(), self.PANEL_MIN_HEIGHT, self.PANEL_MAX_HEIGHT)
end

GUI.SettingsRegistry = {}
GUI.StaticSettingsRegistry = GUI.StaticSettingsRegistry or {}
GUI.StaticSettingsRegistryKeys = GUI.StaticSettingsRegistryKeys or {}

GUI.NavigationRegistry = {}
GUI.NavigationRegistryKeys = {}
GUI.StaticNavigationRegistry = GUI.StaticNavigationRegistry or {}
GUI.StaticNavigationRegistryKeys = GUI.StaticNavigationRegistryKeys or {}

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
    surfaceTypeKey = nil,
}

GUI._suppressSearchRegistration = false

GUI.SettingsRegistryKeys = {}

GUI.WidgetInstances = {}

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
        tostring(entry and entry.tabIndex or 0),
        tostring(entry and entry.subTabIndex or 0),
        entry and entry.tileId or "",
        tostring(entry and entry.subPageIndex or 0),
        entry and entry.tabName or "",
        entry and entry.subTabName or "",
        entry and entry.sectionName or "",
        entry and entry.featureId or "",
        entry and entry.providerKey or "",
        entry and entry.category or "",
        entry and entry.surfaceTabKey or "",
        entry and entry.surfaceUnitKey or "",
        entry and entry.surfaceTypeKey or "",
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
        subTabLabel = ns.L["Page"] .. " " .. tostring(info.subPageIndex)
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
    self:InvalidateSearchTokenIndex()
end

function GUI:ResetRuntimeSearchIndex()
    self.SettingsRegistry = {}
    self.SettingsRegistryKeys = {}
    self.NavigationRegistry = {}
    self.NavigationRegistryKeys = {}
    self:InvalidateSearchTokenIndex()
end

local function RehydrateSearchRows(rows, order)
    if type(rows) ~= "table" then
        return {}
    end
    if type(order) ~= "table" or #order == 0 then
        return rows
    end

    local out = {}
    for index = 1, #rows do
        local row = rows[index]
        if type(row) == "table" then
            local record = {}
            for slot = 1, #order do
                local value = row[slot]
                if value ~= false then
                    record[order[slot]] = value
                end
            end
            out[#out + 1] = record
        end
    end
    return out
end

function GUI:ApplyGeneratedSearchCache(cache, schema)
    self:ResetStaticSearchIndex()
    self:ResetRuntimeSearchIndex()
    self._generatedSearchCacheVersion = nil

    if type(cache) ~= "table" then
        return false
    end

    local order = type(schema) == "table" and schema or {}
    for _, entry in ipairs(RehydrateSearchRows(cache.navigation, order.navigation)) do
        self:RegisterStaticNavigationEntry(entry)
    end
    for _, entry in ipairs(RehydrateSearchRows(cache.settings, order.settings)) do
        self:RegisterStaticSettingEntry(entry)
    end

    self._generatedSearchCacheVersion = cache.version
    return true
end

function GUI:HasGeneratedSearchCache()
    return self._generatedSearchCacheVersion ~= nil
end

function GUI:EnsureSearchCacheLoaded()
    if self:HasGeneratedSearchCache() or self._searchCacheLoadAttempted then
        return
    end
    self._searchCacheLoadAttempted = true

    if ns.QUI_SearchCachePacked then
        local ok, cache = pcall(ns.Unpack, ns.QUI_SearchCachePacked,
            "@QUI_Options/search_cache.lua")
        ns.QUI_SearchCachePacked = nil
        if ok then
            self:ApplyGeneratedSearchCache(cache, ns.QUI_SearchCacheSchema)
        end
    end
    if self:HasGeneratedSearchCache() and self.MainFrame then
        self:SeedStaticSearchRoutesFromTiles(self.MainFrame)
    end
end

function GUI:RegisterStaticNavigationEntry(entry)
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
        return nil
    end

    local stored = self:PrepareSearchEntry(CopySearchRegistryEntry(entry), true)

    local regKey = BuildStaticRegistryKey(stored, "nav")
    if self.StaticNavigationRegistryKeys[regKey] then
        return nil
    end

    self.StaticNavigationRegistryKeys[regKey] = true
    stored.navType = stored.navType or "tab"
    table.insert(self.StaticNavigationRegistry, stored)
    self:InvalidateSearchTokenIndex()
    return stored
end

function GUI:RegisterStaticSettingEntry(entry)
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
        return nil
    end

    local stored = self:PrepareSearchEntry(CopySearchRegistryEntry(entry), true)

    local regKey = BuildStaticRegistryKey(stored, "setting")
    if self.StaticSettingsRegistryKeys[regKey] then
        return nil
    end

    self.StaticSettingsRegistryKeys[regKey] = true
    table.insert(self.StaticSettingsRegistry, stored)
    self:InvalidateSearchTokenIndex()
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

local SEARCH_DB_PATH_SKIP_KEYS = {
    _migrationBackup = true,
    _schemaVersion = true,
    _defaultsVersion = true,
}

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
        if type(key) == "string"
            and type(value) == "table"
            and not SEARCH_DB_PATH_SKIP_KEYS[key]
            and rawget(value, "_quiTransientOptionsProxy") ~= true
        then
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
    if rawget(dbTable, "_quiTransientOptionsProxy") == true then
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
        context and context.providerKey or "",
        context and context.surfaceTabKey or "",
        context and context.surfaceUnitKey or "",
        context and context.surfaceTypeKey or "",
    }, "\31")
end

local function IsTransientOptionsBinding(dbTable)
    return type(dbTable) == "table" and rawget(dbTable, "_quiTransientOptionsProxy") == true
end

local function ShouldRegisterSearchSetting(registryInfo, dbTable)
    if IsTransientOptionsBinding(dbTable) then
        return false
    end
    return not (type(registryInfo) == "table" and registryInfo.searchable == false)
end

function GUI:BuildSearchWidgetDescriptor(kind, dbKey, dbTable, extra)
    if type(dbKey) ~= "string" or dbKey == "" then
        return nil
    end
    if IsTransientOptionsBinding(dbTable) then
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
    if self:HasGeneratedSearchCache()
        or self._suppressSearchRegistration
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
        surfaceTypeKey = context.surfaceTypeKey,
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
    self:PrepareSearchEntry(stored)
    table.insert(self.SettingsRegistry, stored)
    self:InvalidateSearchTokenIndex()
    return stored
end

local function RegisterSearchSettingWidgetForBinding(dbTable, registryInfo, entry)
    if not ShouldRegisterSearchSetting(registryInfo, dbTable) then
        return nil
    end
    return GUI:RegisterSearchSettingWidget(entry)
end

function GUI:RegisterSearchNavigation(navType, info)
    if self:HasGeneratedSearchCache() then
        return nil
    end
    return self:RegisterNavigationItem(navType, info)
end

GUI._sidebarAnimDuration = 0.16
GUI._sidebarRowHeights = {
    level1 = 26,
    level2 = 22,
    level3 = 20,
}

local function GetWidgetKey(dbTable, dbKey)
    if not dbTable or not dbKey then return nil end
    return tostring(dbTable) .. "_" .. dbKey
end

local function RegisterWidgetInstance(widget, dbTable, dbKey)
    if IsTransientOptionsBinding(dbTable) then
        return
    end
    local widgetKey = GetWidgetKey(dbTable, dbKey)
    widget._syncDBTable = dbTable
    widget._syncDBKey = dbKey
    if not widgetKey then return end
    GUI.WidgetInstances[widgetKey] = GUI.WidgetInstances[widgetKey] or {}
    table.insert(GUI.WidgetInstances[widgetKey], widget)
    widget._widgetKey = widgetKey
end

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
    if #instances == 0 then
        GUI.WidgetInstances[widget._widgetKey] = nil
    end
end

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

function GUI:RefreshWidgetInstances()
    for _, instances in pairs(self.WidgetInstances or {}) do
        for _, widget in ipairs(instances) do
            if widget and type(widget.Refresh) == "function" then
                if ns.SafeCallMethod then
                    ns.SafeCallMethod("bulkhead", widget, "Refresh")
                else
                    widget.Refresh()
                end
            end
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
    if IsTransientOptionsBinding(dbTable) then
        widget._syncDBTable = nil
        widget._syncDBKey = nil
        return
    end
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
        surfaceTypeKey = binding.surfaceTypeKey,
    }
end

local function MaybeBindPinnedWidget(widget, kind, label, dbKey, dbTable, interactiveFrame, registryInfo)
    local pins = ns.Settings and ns.Settings.Pins
    if not pins or type(pins.BindWidget) ~= "function" then
        return
    end
    if IsTransientOptionsBinding(dbTable) then
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
        surfaceTypeKey = searchContext.surfaceTypeKey,
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
    self._searchContext.surfaceTypeKey = info.surfaceTypeKey or nil

    if (info.tabIndex or info.tileId or info.tabName) and (info.tabName or info.tileId) then
        self:RegisterSearchNavigation("tab", info)
        if (info.subTabIndex or info.subPageIndex or info.subTabName) and (info.subTabName or info.subPageIndex) then
            self:RegisterSearchNavigation("subtab", info)
        end
    end
end

function GUI:SetSearchSection(sectionName)
    self._searchContext.sectionName = sectionName

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
            surfaceTypeKey = self._searchContext.surfaceTypeKey,
        })
    end
end

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
        surfaceTypeKey = nil,
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

function GUI.RegisterSectionEntry(tabIndex, subTabIndex, title, frame, contentParent)
    local numKey = GetSectionRegistryKey(tabIndex, subTabIndex)

    local scrollParent = nil
    local current = contentParent
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
    if not GUI.SectionRegistry[numKey][title] then
        table.insert(GUI.SectionRegistryOrder[numKey], title)
    end
    GUI.SectionRegistry[numKey][title] = {
        frame = frame,
        scrollParent = scrollParent,
        contentParent = contentParent,
    }
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
            scroll:SetVerticalScroll(offset)
        end
    end

    if not opts or opts.pulse ~= false then
        self:PulseWidget(entry.frame)
    end

    return true
end

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

function GUI:RegisterNavigationItem(navType, info)
    if self._suppressSearchRegistration then return end
    if not info.tabIndex then return end

    local regKey
    if navType == "tab" then
        regKey = info.tabIndex * 100000
    elseif navType == "subtab" then
        regKey = info.tabIndex * 100000 + (info.subTabIndex or 0)
        if type(info.surfaceTabKey) == "string" and info.surfaceTabKey ~= "" then
            regKey = tostring(regKey) .. ":" .. info.surfaceTabKey
        end
    elseif navType == "section" then
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

    if navType ~= "section" then
        if self.NavigationRegistryKeys[regKey] then return end
        self.NavigationRegistryKeys[regKey] = true
    end

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
        surfaceTypeKey = info.surfaceTypeKey,
        keywords = keywords,
    }

    table.insert(self.NavigationRegistry, self:PrepareSearchEntry(entry))
    self:InvalidateSearchTokenIndex()
end

local FONT_PATH = LSM:Fetch("font", "Quazii") or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
GUI.FONT_PATH = FONT_PATH

local function GetFontPath()
    return FONT_PATH
end

function GUI:GetFontPath()
    return GetFontPath()
end

local function CreateBackdrop(frame, bgColor, borderColor)
    if SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(frame, 1, true, false, borderColor or C.border, bgColor or C.bg)
    end
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
    local H = ns.Helpers
    if H and H.ApplyFontWithFallback then
        H.ApplyFontWithFallback(fontString, GetFontPath(), size or 12, flags or "")
    else
        fontString:SetFont(GetFontPath(), size or 12, flags or "")
    end
    if color then
        fontString:SetTextColor(unpack(color))
    end
end

local function ApplyFontToFrameRecursive(frame, fontPath)
    if not frame then return end

    local numRegions = frame.GetNumRegions and frame:GetNumRegions() or 0
    for i = 1, numRegions do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetFont and region.SetFont then
            local _, size, flags = region:GetFont()
            if size and size > 0 then
                ns.Helpers.ApplyFontWithFallback(region, fontPath, size, flags or "")
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

function GUI:CreateLabel(parent, text, size, color, anchor, x, y)
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

function GUI:CreateButton(parent, text, width, height, onClick, variant)
    return ns.UIKit.CreateButton(parent, {
        text = text,
        width = width,
        height = height,
        onClick = onClick,
        variant = variant,
    })
end

local function ApplyFallbackPixelBorder(field, r, g, b, a, gray)
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
        edge:SetVertexColor(r or gray, g or gray, b or gray, a or 1)
    end
end

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

    function field:SetFieldBorderColor(r, g, b, a)
        if UIKit and UIKit.UpdateBorderLines then
            if not self._pixelBorderReady and UIKit.CreateBorderLines then
                UIKit.CreateBorderLines(self)
                self._pixelBorderReady = true
            end
            UIKit.UpdateBorderLines(self, 1, r, g, b, a, false)
        else
            ApplyFallbackPixelBorder(field, r, g, b, a, 0.25)
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
    ns.Helpers.ApplyFontWithFallback(editBox, GetFontPath(), fontSize, "")
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

local confirmDialog = nil

function GUI:ShowConfirmation(options)

    if not confirmDialog then
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

        if SkinBase and SkinBase.ApplyPixelBackdrop then
            SkinBase.ApplyPixelBackdrop(confirmDialog, 1, true, false, { C.border[1], C.border[2], C.border[3], 1 }, { C.bg[1], C.bg[2], C.bg[3], 0.98 })
        end

        confirmDialog.title = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.title, 14, "", C.accentLight)
        confirmDialog.title:SetPoint("TOP", 0, -18)

        confirmDialog.message = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.message, 12, "", C.text)
        confirmDialog.message:SetPoint("TOP", 0, -50)
        confirmDialog.message:SetWidth(280)
        confirmDialog.message:SetJustifyH("CENTER")

        confirmDialog.warning = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.warning, 11, "", C.warning)
        confirmDialog.warning:SetPoint("TOP", confirmDialog.message, "BOTTOM", 0, -8)
        confirmDialog.warning:SetWidth(280)
        confirmDialog.warning:SetJustifyH("CENTER")

        confirmDialog.acceptBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
        confirmDialog.acceptBtn:SetSize(100, 28)
        confirmDialog.acceptBtn:SetPoint("BOTTOMLEFT", 40, 20)
        if SkinBase and SkinBase.ApplyPixelBackdrop then
            SkinBase.ApplyPixelBackdrop(confirmDialog.acceptBtn, 1, true, false, { C.border[1], C.border[2], C.border[3], 1 }, GUI.DIALOG_BUTTON_BG)
        end

        confirmDialog.acceptBtn.text = confirmDialog.acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ns.Helpers.ApplyFontWithFallback(confirmDialog.acceptBtn.text, GetFontPath(), 12, "")
        confirmDialog.acceptBtn.text:SetPoint("CENTER", 0, 0)

        confirmDialog.acceptBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        confirmDialog.acceptBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)

        confirmDialog.cancelBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
        confirmDialog.cancelBtn:SetSize(100, 28)
        confirmDialog.cancelBtn:SetPoint("BOTTOMRIGHT", -40, 20)
        if SkinBase and SkinBase.ApplyPixelBackdrop then
            SkinBase.ApplyPixelBackdrop(confirmDialog.cancelBtn, 1, true, false, { C.border[1], C.border[2], C.border[3], 1 }, GUI.DIALOG_BUTTON_BG)
        end

        confirmDialog.cancelBtn.text = confirmDialog.cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ns.Helpers.ApplyFontWithFallback(confirmDialog.cancelBtn.text, GetFontPath(), 12, "")
        confirmDialog.cancelBtn.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        confirmDialog.cancelBtn.text:SetPoint("CENTER", 0, 0)

        confirmDialog.cancelBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        confirmDialog.cancelBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)

        confirmDialog:SetScript("OnKeyDown", function(self, key)
            local locked = InCombatLockdown()
            if key == "ESCAPE" then
                if not locked then self:SetPropagateKeyboardInput(false) end
                if self._onCancel then self._onCancel() end
                self:Hide()
            else
                if not locked then self:SetPropagateKeyboardInput(true) end
            end
        end)
    end

    confirmDialog.title:SetText(options.title or ns.L["Confirm"])
    confirmDialog.message:SetText(options.message or "")

    if options.warningText then
        confirmDialog.warning:SetText(options.warningText)
        confirmDialog.warning:Show()
    else
        confirmDialog.warning:Hide()
    end

    local msgH = confirmDialog.message:GetStringHeight() or 14
    local warnH = 0
    if options.warningText then
        warnH = (confirmDialog.warning:GetStringHeight() or 11) + 8
    end
    confirmDialog:SetHeight(math.max(160, 50 + msgH + warnH + 18 + 28 + 20))

    confirmDialog.acceptBtn.text:SetText(options.acceptText or ns.L["OK"])
    if options.isDestructive then
        confirmDialog.acceptBtn.text:SetTextColor(C.warning[1], C.warning[2], C.warning[3], 1)
    else
        confirmDialog.acceptBtn.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end

    confirmDialog.cancelBtn.text:SetText(options.cancelText or ns.L["Cancel"])

    confirmDialog._onCancel = options.onCancel

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

    confirmDialog:Show()
    confirmDialog:Raise()
    confirmDialog:EnableKeyboard(true)
end

function GUI:CreateSectionHeader(parent, text)
    local suppressedAtCreation = self._suppressSearchRegistration

    if text and not suppressedAtCreation then
        self:SetSearchSection(text)
    end

    local isFirstElement = (parent._hasContent == false)
    if parent._hasContent ~= nil then
        parent._hasContent = true
    end

    local topMargin = isFirstElement and 0 or 12
    local containerHeight = isFirstElement and 18 or 30

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(containerHeight)

    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(header, 13, "", C.sectionHeader)
    header:SetText(text or "Section")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -topMargin)

    container.text = header
    container.parent = parent
    container.gap = isFirstElement and 34 or 46

    container.SetText = function(self, newText)
        header:SetText(newText)
    end

    local originalSetPoint = container.SetPoint
    container.SetPoint = function(self, point, ...)
        originalSetPoint(self, point, ...)
        if point == "TOPLEFT" then
            originalSetPoint(self, "RIGHT", parent, "RIGHT", -10, 0)
            if not container.underline then
                local underline = container:CreateTexture(nil, "ARTWORK")
                underline:SetHeight(2)
                underline:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
                underline:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                underline:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
                container.underline = underline
            end

            if not suppressedAtCreation and not GUI._suppressSearchRegistration and GUI._searchContext.tabIndex and text then
                GUI.RegisterSectionEntry(GUI._searchContext.tabIndex, GUI._searchContext.subTabIndex, text, container, parent)
            end
        end
    end

    return container
end

function GUI:CreateAccentCheckbox(parent, options)
    options = options or {}
    if not options.colors then
        options.colors = C
    end

    local UIKit = ns.UIKit
    if UIKit and UIKit.CreateAccentCheckbox then
        local widget = UIKit.CreateAccentCheckbox(parent, options)
        if widget and options.description then
            GUI:SetTooltipInfo(widget, options.description, options.label)
        end
        return widget
    end

    return nil
end

local CHEVRON_ZONE_WIDTH = 28
local CHEVRON_BG_ALPHA = 0.15
local CHEVRON_BG_ALPHA_HOVER = 0.25
local CHEVRON_TEXT_ALPHA = 0.7

local DROPDOWN_MAX_VISIBLE_ITEMS = 10
local DROPDOWN_ITEM_HEIGHT = 22
local DROPDOWN_SCROLLBAR_WIDTH = 6

local function PositionDropdownMenu(menuFrame, dropdown, menuHeight)
    menuFrame:ClearAllPoints()
    local uiScale = UIParent:GetEffectiveScale()
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / uiScale
    local panelBottom = 0
    if GUI.MainFrame and GUI.MainFrame:IsShown() then
        local pb = GUI.MainFrame:GetBottom()
        if pb then
            local panelScale = GUI.MainFrame:GetEffectiveScale()
            panelBottom = pb * panelScale / uiScale
        end
    end
    if cursorY - menuHeight < panelBottom + 10 then
        menuFrame:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
        menuFrame:SetPoint("BOTTOMRIGHT", dropdown, "TOPRIGHT", 0, 2)
    else
        menuFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        menuFrame:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
    end
end

-- Dropdown pool fills come from the live palette so a custom accent tints
-- them: selected = selectedWash hue @ .12, hover = white @ .08 (contract:
-- selected rows carry a faint accent wash + 2 px accent bar; hover stays
-- neutral). Re-applied via GUI:OnAccentChanged (see RetintSharedMenu).
local DROPDOWN_SELECTED_WASH_ALPHA = 0.12
local DROPDOWN_HOVER_ALPHA = 0.08

local function TintSharedMenuButton(f)
    local wash = C.selectedWash or C.accent
    f._selectedBg:SetColorTexture(wash[1], wash[2], wash[3], DROPDOWN_SELECTED_WASH_ALPHA)
    f._hoverBg:SetColorTexture(1, 1, 1, DROPDOWN_HOVER_ALPHA)
    if f._selectedBar then
        f._selectedBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end
end

local function RetintSharedMenu(menu)
    if not menu then return end
    for _, f in ipairs(menu._buttonPool or {}) do
        TintSharedMenuButton(f)
    end
    local thumb = menu.scrollBar and menu.scrollBar.thumb
    if thumb then
        thumb:SetColorTexture(C.scrollThumb[1], C.scrollThumb[2], C.scrollThumb[3], C.scrollThumb[4])
    end
end

local function CreateDropdownScrollBody(menuFrame)
    local scrollFrame = CreateFrame("ScrollFrame", nil, menuFrame)
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(200)
    scrollFrame:SetScrollChild(scrollContent)

    local scrollBar = CreateFrame("Frame", nil, menuFrame)
    scrollBar:SetWidth(DROPDOWN_SCROLLBAR_WIDTH)
    scrollBar:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", menuFrame, "BOTTOMRIGHT", -1, 2)
    scrollBar:Hide()

    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(DROPDOWN_SCROLLBAR_WIDTH)
    thumb:SetColorTexture(C.scrollThumb[1], C.scrollThumb[2], C.scrollThumb[3], C.scrollThumb[4])
    scrollBar.thumb = thumb

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

    local SCROLL_STEP = 22
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local okCur, currentScroll = pcall(self.GetVerticalScroll, self)
        if not okCur then return end
        local contentH = scrollContent:GetHeight()
        local frameH = self:GetHeight()
        local maxScroll = math.max(0, contentH - frameH)
        local newScroll = math.max(0, math.min(currentScroll - (delta * SCROLL_STEP), maxScroll))
        self:SetVerticalScroll(newScroll)
        UpdateThumb()
    end)

    scrollFrame:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    return scrollFrame, scrollContent, scrollBar, UpdateThumb
end

local DROPDOWN_SEARCH_BOX_HEIGHT = 28

local sharedDropdownMenu

local function GetSharedDropdownMenu()
    if sharedDropdownMenu then return sharedDropdownMenu end

    local Kit = ns.UIKit
    local useUIKitBorders = Kit
        and Kit.CreateBackground
        and Kit.CreateBorderLines
        and Kit.UpdateBorderLines
    local menu = CreateFrame("Frame", nil, UIParent, useUIKitBorders and nil or "BackdropTemplate")
    if useUIKitBorders then
        menu.bg = Kit.CreateBackground(menu, C.bg[1], C.bg[2], C.bg[3], 1)
        Kit.CreateBorderLines(menu)
        Kit.UpdateBorderLines(menu, 1, 1, 1, 1, 0.2, false)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(menu, 1, true, false, { 1, 1, 1, 0.2 }, { C.bg[1], C.bg[2], C.bg[3], 1 })
    end
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClipsChildren(true)
    menu:Hide()

    local scrollFrame, scrollContent, scrollBar, updateThumb = CreateDropdownScrollBody(menu)
    menu.scrollFrame = scrollFrame
    menu.scrollContent = scrollContent
    menu.scrollBar = scrollBar
    menu.updateThumb = updateThumb
    menu.UpdateScrollInset = function()
        if scrollBar:IsShown() then
            scrollFrame:SetPoint("BOTTOMRIGHT", -(DROPDOWN_SCROLLBAR_WIDTH + 2), 0)
        else
            scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
        end
    end

    local searchContainer = CreateFrame("Frame", nil, menu)
    searchContainer:SetHeight(DROPDOWN_SEARCH_BOX_HEIGHT)
    searchContainer:SetPoint("TOPLEFT", 0, 0)
    searchContainer:SetPoint("TOPRIGHT", 0, 0)
    searchContainer:Hide()
    menu.searchContainer = searchContainer

    local searchBg = searchContainer:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetColorTexture(0.06, 0.06, 0.06, 1)

    local searchBorder = searchContainer:CreateTexture(nil, "ARTWORK")
    searchBorder:SetHeight(1)
    searchBorder:SetPoint("BOTTOMLEFT", searchContainer, "BOTTOMLEFT", 0, 0)
    searchBorder:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", 0, 0)
    searchBorder:SetColorTexture(0.25, 0.25, 0.25, 1)

    local searchBox = CreateFrame("EditBox", nil, searchContainer)
    searchBox:SetPoint("TOPLEFT", 8, -2)
    searchBox:SetPoint("BOTTOMRIGHT", -8, 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(GameFontNormal)
    SetFont(searchBox, 11, "", C.text)
    searchBox:SetMaxLetters(50)
    menu.searchBox = searchBox
    searchContainer.searchBox = searchBox

    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(placeholder, 11, "", C.textMuted or {0.6, 0.6, 0.6})
    placeholder:SetText(ns.L["Search..."])
    placeholder:SetPoint("LEFT", 0, 0)
    placeholder:SetJustifyH("LEFT")
    searchBox.placeholder = placeholder

    searchBox:SetScript("OnEditFocusGained", function()
        searchBorder:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    end)
    searchBox:SetScript("OnEditFocusLost", function()
        searchBorder:SetColorTexture(0.25, 0.25, 0.25, 1)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local owner = menu._owner
        if not owner then return end
        local txt = self:GetText()
        owner.searchText = txt or ""
        if self.placeholder then
            self.placeholder:SetShown(txt == nil or txt == "")
        end
        if menu._ownerBuildMenu then
            menu._ownerBuildMenu()
            C_Timer.After(0, function() menu.updateThumb(); menu.UpdateScrollInset() end)
        end
    end)

    menu._headerPool = {}
    menu._buttonPool = {}
    menu._headerIdx = 0
    menu._buttonIdx = 0

    local closeTimer = 0
    menu:SetScript("OnShow", function(self)
        closeTimer = 0
        self.__checkElapsed = 0
        self:SetScript("OnUpdate", function(frame, elapsed)
            frame.__checkElapsed = (frame.__checkElapsed or 0) + elapsed
            if frame.__checkElapsed < 0.066 then return end
            local deltaTime = frame.__checkElapsed
            frame.__checkElapsed = 0

            if searchBox:IsShown() and searchBox:HasFocus() then
                closeTimer = 0
                return
            end

            local ownerDropdown = frame._ownerDropdown
            local isOverDropdown = ownerDropdown and ownerDropdown:IsMouseOver()
            local isOverMenu = frame:IsMouseOver()
            if not isOverDropdown and not isOverMenu then
                closeTimer = closeTimer + deltaTime
                if closeTimer > 0.15 then
                    frame:Hide()
                end
            else
                closeTimer = 0
            end
        end)
    end)

    menu:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        closeTimer = 0
        searchBox:SetText("")
        searchBox:ClearFocus()
        local owner = self._owner
        if owner then owner.searchText = "" end
    end)

    sharedDropdownMenu = menu
    -- The menu is UIParent-parented and outlives GUI:RefreshAccentColor's
    -- panel rebuild, so it re-tints from the live tokens on accent change.
    if GUI.OnAccentChanged then
        GUI:OnAccentChanged(function() RetintSharedMenu(menu) end)
    end
    return menu
end

local function ResetSharedMenuItems(menu)
    for i = 1, menu._headerIdx do menu._headerPool[i]:Hide() end
    for i = 1, menu._buttonIdx do menu._buttonPool[i]:Hide() end
    menu._headerIdx = 0
    menu._buttonIdx = 0
    for _, child in ipairs({menu.scrollContent:GetChildren()}) do child:Hide() end
end

local function AcquireSharedMenuHeader(menu)
    menu._headerIdx = menu._headerIdx + 1
    local f = menu._headerPool[menu._headerIdx]
    if not f then
        f = CreateFrame("Button", nil, menu.scrollContent)
        f._headerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f._headerText:SetPoint("LEFT", 4, 0)
        f._chevron1 = f:CreateTexture(nil, "OVERLAY")
        f._chevron1:SetSize(5, 1)
        f._chevron2 = f:CreateTexture(nil, "OVERLAY")
        f._chevron2:SetSize(5, 1)
        menu._headerPool[menu._headerIdx] = f
    end
    f._chevron1:Hide()
    f._chevron2:Hide()
    f:ClearAllPoints()
    f:Show()
    return f
end

local function AcquireSharedMenuButton(menu)
    menu._buttonIdx = menu._buttonIdx + 1
    local f = menu._buttonPool[menu._buttonIdx]
    if not f then
        f = CreateFrame("Button", nil, menu.scrollContent)
        f._selectedBg = f:CreateTexture(nil, "BACKGROUND")
        f._selectedBg:SetAllPoints(f)
        f._selectedBg:Hide()
        f._hoverBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f._hoverBg:SetAllPoints(f)
        f._hoverBg:Hide()
        f._selectedBar = f:CreateTexture(nil, "OVERLAY")
        f._selectedBar:SetWidth(2)
        f._selectedBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f._selectedBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        f._selectedBar:Hide()
        TintSharedMenuButton(f)
        f._btnText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f._btnText:SetPoint("LEFT", 8, 0)
        menu._buttonPool[menu._buttonIdx] = f
    end
    f:ClearAllPoints()
    f:Show()
    return f
end

local function AcquireSharedMenuFor(menu, container, dropdown, searchable, buildMenu)
    menu._owner = container
    menu._ownerDropdown = dropdown
    menu._ownerBuildMenu = buildMenu
    -- The menu is shared across every form dropdown: a scroll offset left by a
    -- long list would push a short list entirely out of the clipped viewport.
    menu.scrollFrame:SetVerticalScroll(0)
    if searchable then
        menu.searchContainer:Show()
        menu.scrollFrame:SetPoint("TOPLEFT", 0, -DROPDOWN_SEARCH_BOX_HEIGHT)
        SetFont(menu.searchBox, 11, "", C.text)
        SetFont(menu.searchBox.placeholder, 11, "", C.textMuted or {0.6, 0.6, 0.6})
        menu.searchBox:SetText("")
        menu.searchBox.placeholder:SetShown(true)
        container.searchText = ""
    else
        menu.searchContainer:Hide()
        menu.scrollFrame:SetPoint("TOPLEFT", 0, 0)
    end
    menu.scrollBar.thumb:SetColorTexture(C.scrollThumb[1], C.scrollThumb[2], C.scrollThumb[3], C.scrollThumb[4])
end

local FORM_ROW_HEIGHT = 28

local function AttachFormWidgetTooltip(container, control, description, label)
    GUI:SetTooltipInfo(control, description, label)
    if label then
        GUI:AttachTooltip(container, description, label)
    else
        GUI:SetTooltipInfo(container, description, label)
    end
end

local function BuildPillToggle(parent, label, dbKey, dbTable, onChange, registryInfo, invert)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    local text
    local toggleLeftOffset = 180
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

    local knobMask = toggle:CreateMaskTexture()
    knobMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    knobMask:SetAllPoints(knob)
    knob:AddMaskTexture(knobMask)
    toggle._knobMask = knobMask

    container.track = toggle
    container.thumb = toggle
    container.label = text

    local function GetValue()
        if dbTable and dbKey then
            local db = dbTable[dbKey]
            if invert then return not db end
            return db
        end
        if invert then return false end
        return container.checked
    end

    local isHovered = false

    local function SetToggleVisual(t, isOn)
        ApplyToggleVisual(t, isOn, isHovered)
    end

    local function UpdateVisual(isOn)
        SetToggleVisual(toggle, isOn and true or false)
    end

    local function SetValue(isOn, skipCallback)
        isOn = isOn and true or false
        local dbVal
        if invert then dbVal = not isOn else dbVal = isOn end
        container.checked = isOn
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

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    container.UpdateVisual = UpdateVisual

    container.Refresh = function() UpdateVisual(GetValue()) end

    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "checkbox", label, dbKey, dbTable, toggle, registryInfo)

    local initialOn = GetValue() and true or false
    container.checked = initialOn
    UpdateVisual(initialOn)

    if ns.UIKit and ns.UIKit.RegisterScaleRefresh then
        local scaleKey = invert and "formToggleInvertedScale" or "formToggleScale"
        ns.UIKit.RegisterScaleRefresh(toggle, scaleKey, function()
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

    container.SetEnabled = function(self, enabled)
        toggle:EnableMouse(enabled)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    if not GUI:HasGeneratedSearchCache() then
        local descriptorType = invert and "toggle_inverted" or "toggle"
        RegisterSearchSettingWidgetForBinding(dbTable, registryInfo, {
            label = label,
            widgetType = "toggle",
            widgetBuilder = function(p)
                if invert then
                    return GUI:CreateFormToggleInverted(p, label, dbKey, dbTable, onChange, registryInfo)
                end
                return GUI:CreateFormToggle(p, label, dbKey, dbTable, onChange, registryInfo)
            end,
            widgetDescriptor = GUI:BuildSearchWidgetDescriptor(descriptorType, dbKey, dbTable),
            keywords = registryInfo and registryInfo.keywords or nil,
            description = registryInfo and registryInfo.description or nil,
            relatedTo = registryInfo and registryInfo.relatedTo or nil,
        })
    end

    local tooltipDescription = registryInfo and registryInfo.description or nil
    AttachFormWidgetTooltip(container, toggle, tooltipDescription, label)
    return container
end

function GUI:CreateFormToggle(parent, label, dbKey, dbTable, onChange, registryInfo)
    return BuildPillToggle(parent, label, dbKey, dbTable, onChange, registryInfo, false)
end

function GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange, registryInfo)
    return BuildPillToggle(parent, label, dbKey, dbTable, onChange, registryInfo, true)
end

function GUI:CreateFormCheckbox(parent, label, dbKey, dbTable, onChange, registryInfo)
    return GUI:CreateFormToggle(parent, label, dbKey, dbTable, onChange, registryInfo)
end

function GUI:CreateFormCheckboxOriginal(parent, label, dbKey, dbTable, onChange, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(170)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end

    local SetValue

    local box = UIKit.CreateAccentCheckbox(container, {
        checked = GetValue() and true or false,
        onChange = function(val)
            if SetValue then SetValue(val, false, true) end
        end,
    })
    box:ClearAllPoints()
    box:SetPoint("LEFT", container, "LEFT", 180, 0)

    container.box = box
    container.label = text

    local function UpdateVisual(val)
        box:SetChecked(val and true or false, true)
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

    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "checkbox", label, dbKey, dbTable, box, registryInfo)

    SetValue(GetValue(), true)

    local tooltipDescription = registryInfo and registryInfo.description or nil
    AttachFormWidgetTooltip(container, box, tooltipDescription, label)
    return container
end

function GUI:CreateFormCheckboxInverted(parent, label, dbKey, dbTable, onChange, registryInfo)
    return GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange, registryInfo)
end

function GUI:CreateFormEditBox(parent, label, dbKey, dbTable, onChange, options, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    options = options or {}
    local UIKit = ns.UIKit

    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    local text
    local fieldLeftOffset = 180
    if label then
        container:SetHeight(FORM_ROW_HEIGHT)
        text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 12, "", C.text)
        text:SetText(label)
        text:SetPoint("LEFT", 0, 0)
        text:SetWidth(170)
        text:SetWordWrap(true)
        text:SetJustifyH("LEFT")
    else
        container:SetSize((options.width and options.width > 0) and options.width or 180, FORM_ROW_HEIGHT)
        fieldLeftOffset = 0
    end

    local field = CreateFrame("Frame", nil, container)
    field:SetHeight(24)
    field:SetPoint("LEFT", container, "LEFT", fieldLeftOffset, 0)
    if label and options.width and options.width > 0 then
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

    local function SetFieldBorderColor(r, g, b, a)
        if UIKit and UIKit.UpdateBorderLines then
            if not field._pixelBorderReady and UIKit.CreateBorderLines then
                UIKit.CreateBorderLines(field)
                field._pixelBorderReady = true
            end
            UIKit.UpdateBorderLines(field, 1, r, g, b, a, false)
        else
            ApplyFallbackPixelBorder(field, r, g, b, a, 0.35)
        end
    end
    SetFieldBorderColor(1, 1, 1, 0.2)

    local editBox = CreateFrame("EditBox", nil, field)
    editBox:SetPoint("TOPLEFT", field, "TOPLEFT", 6, -2)
    editBox:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -6, 2)
    editBox:SetAutoFocus(false)
    do
        local f, _, flags = editBox:GetFont()
        ns.Helpers.ApplyFontWithFallback(editBox, f or UIKit.ResolveFontPath(GUI:GetFontPath()), 10, flags or "")
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

    container.Refresh = function()
        if editBox:HasFocus() then return end
        UpdateVisual(GetValue())
    end

    RegisterWidgetInstance(container, dbTable, dbKey)

    container.value = GetValue()
    UpdateVisual(container.value)

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

    local effectiveDescription = (registryInfo and registryInfo.description)
        or (options and options.description)
        or nil

    if not GUI:HasGeneratedSearchCache() then
        RegisterSearchSettingWidgetForBinding(dbTable, registryInfo, {
            label = label,
            widgetType = "editbox",
            widgetBuilder = function(p)
                return GUI:CreateFormEditBox(p, label, dbKey, dbTable, onChange, options)
            end,
            widgetDescriptor = GUI:BuildSearchWidgetDescriptor("editbox", dbKey, dbTable, {
                options = options,
            }),
            keywords = registryInfo and registryInfo.keywords or nil,
            description = effectiveDescription,
            relatedTo = registryInfo and registryInfo.relatedTo or nil,
        })
    end

    AttachFormWidgetTooltip(container, editBox, effectiveDescription, label)
    return container
end

function GUI:CreateFormSlider(parent, label, min, max, step, dbKey, dbTable, onChange, options, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    options = options or {}
    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label
    container:EnableMouse(true)

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

    local function FormatValue(val)
        local s = string.format(formatStr, val)
        if precision and s:find(".", 1, true) then
            s = s:gsub("0+$", ""):gsub("%.$", "")
        end
        return s
    end

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

    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local nativeThumb = slider:GetThumbTexture()
    nativeThumb:SetSize(SLIDER_THUMB_SIZE, SLIDER_THUMB_SIZE)
    nativeThumb:SetAlpha(0)

    local thumbFrame = thumb
    local trackContainer = slider

    local nudgeMinus = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    nudgeMinus:SetSize(16, 22)
    local editBoxWidth = (options and options.editWidth) or 36
    nudgeMinus:SetPoint("RIGHT", container, "RIGHT", -(editBoxWidth + 28), 0)

    slider:SetPoint("RIGHT", nudgeMinus, "LEFT", -8, 0)
    if useUIKitBorders then
        nudgeMinus.bg = UIKit.CreateBackground(nudgeMinus, 0.08, 0.08, 0.08, 1)
        UIKit.CreateBorderLines(nudgeMinus)
        UIKit.UpdateBorderLines(nudgeMinus, 1, 0.25, 0.25, 0.25, 1, false)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(nudgeMinus, 1, true, false, { 0.25, 0.25, 0.25, 1 }, { 0.08, 0.08, 0.08, 1 })
    end
    local nudgeMinusText = nudgeMinus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(nudgeMinusText, 11, "", C.text)
    nudgeMinusText:SetText("-")
    nudgeMinusText:SetPoint("CENTER", 0, 0)

    local editBox = CreateFrame("EditBox", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    editBox:SetSize(editBoxWidth, 18)
    editBox:SetPoint("LEFT", nudgeMinus, "RIGHT", 1, 0)
    if useUIKitBorders then
        editBox.bg = UIKit.CreateBackground(editBox, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        UIKit.CreateBorderLines(editBox)
        UIKit.UpdateBorderLines(editBox, 1, C.border[1], C.border[2], C.border[3], C.border[4], false)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(editBox, 1, true, false, { C.border[1], C.border[2], C.border[3], C.border[4] }, { C.bgContent[1], C.bgContent[2], C.bgContent[3], 1 })
    end
    ns.Helpers.ApplyFontWithFallback(editBox, GetFontPath(), 10, "")
    editBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    editBox:SetJustifyH("CENTER")
    editBox:SetTextInsets(4, 4, 0, 0)
    editBox:SetAutoFocus(false)

    local nudgePlus = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    nudgePlus:SetSize(16, 22)
    nudgePlus:SetPoint("LEFT", editBox, "RIGHT", 1, 0)
    if useUIKitBorders then
        nudgePlus.bg = UIKit.CreateBackground(nudgePlus, 0.08, 0.08, 0.08, 1)
        UIKit.CreateBorderLines(nudgePlus)
        UIKit.UpdateBorderLines(nudgePlus, 1, 0.25, 0.25, 0.25, 1, false)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(nudgePlus, 1, true, false, { 0.25, 0.25, 0.25, 1 }, { 0.08, 0.08, 0.08, 1 })
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
        editBox:SetText(FormatValue(val))
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

    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "slider", label, dbKey, dbTable, slider, registryInfo)

    local DRAG_CHANGE_INTERVAL = 0.1
    local lastDragChangeAt = 0
    local pendingDragValue = nil

    local function FireDragChange(value)
        lastDragChangeAt = GetTime()
        pendingDragValue = nil
        if onChange then onChange(value) end
        MaybeAutoNotifyProviderSync(container)
    end

    local function QueueDragChange(value)
        if GetTime() - lastDragChangeAt >= DRAG_CHANGE_INTERVAL then
            FireDragChange(value)
            return
        end
        local timerArmed = pendingDragValue ~= nil
        pendingDragValue = value
        if not timerArmed then
            C_Timer.After(DRAG_CHANGE_INTERVAL, function()
                if isDragging and pendingDragValue ~= nil then
                    FireDragChange(pendingDragValue)
                end
            end)
        end
    end

    slider:SetScript("OnValueChanged", function(self, value, userInput)
        if userInput and container.isEnabled == false then return end

        value = math.floor(value / container.step + 0.5) * container.step
        editBox:SetText(FormatValue(value))
        UpdateTrackFill(value)
        if userInput then
            if dbTable and dbKey then dbTable[dbKey] = value end
            MaybeUpdatePinnedWidgetValue(container, value)
            BroadcastToSiblings(container, value)
            if deferOnDrag and isDragging then
                if onDragPreview then onDragPreview(value) end
                return
            end
            if isDragging then
                QueueDragChange(value)
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
        if pendingDragValue ~= nil then
            FireDragChange(slider:GetValue())
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or container.min
        SetValue(val)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(GetValue()))
        self:ClearFocus()
    end)

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

    slider:SetScript("OnSizeChanged", function(self, width, height)
        if width and width > 0 then
            UpdateTrackFill(GetValue())
        end
    end)

    container.value = math.max(container.min, math.min(container.max, GetValue()))
    UpdateVisual(container.value)

    container._refreshEditBox = function()
        local val = GetValue()
        local txt = FormatValue(val)
        editBox:SetText(txt)
        editBox:SetCursorPosition(0)
    end

    container.SetEnabled = function(self, enabled)
        slider:EnableMouse(enabled)
        editBox:EnableMouse(enabled)
        editBox:SetEnabled(enabled)
        nudgeMinus:EnableMouse(enabled)
        nudgePlus:EnableMouse(enabled)

        container.isEnabled = enabled

        container:SetAlpha(enabled and 1 or 0.4)
    end

    container.isEnabled = true

    local effectiveDescription = (registryInfo and registryInfo.description)
        or (options and options.description)
        or nil

    if not GUI:HasGeneratedSearchCache() then
        RegisterSearchSettingWidgetForBinding(dbTable, registryInfo, {
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
            description = effectiveDescription,
            relatedTo = registryInfo and registryInfo.relatedTo or nil,
        })
    end

    AttachFormWidgetTooltip(container, slider, effectiveDescription, label)
    return container
end

function GUI:CreateFormDropdown(parent, label, options, dbKey, dbTable, onChange, registryInfo, opts)
    if parent._hasContent ~= nil then parent._hasContent = true end
    opts = opts or {}
    local searchable = opts.searchable or false
    local collapsible = opts.collapsible or false
    local UIKit = ns.UIKit
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines
    local container = CreateFrame("Frame", nil, parent)
    container._widgetLabel = label
    ApplyWidgetSyncContext(container, dbTable, dbKey)

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

    local dropdown = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    dropdown:SetHeight(22)
    dropdown:SetPoint("LEFT", container, "LEFT", dropdownLeftOffset, 0)
    dropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    if useUIKitBorders then
        dropdown.bg = UIKit.CreateBackground(dropdown, C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06)
        UIKit.CreateBorderLines(dropdown)
        UIKit.UpdateBorderLines(dropdown, 1, 1, 1, 1, 0.2, false)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(dropdown, 1, true, false, { 1, 1, 1, 0.2 }, { C.bgContent[1], C.bgContent[2], C.bgContent[3], 0.06 })
    end

    local function SetDropdownBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(dropdown, 1, r, g, b, a or 1, false)
        else
            dropdown:SetBackdropBorderColor(r, g, b, a or 1)
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

    dropdown:SetScript("OnEnter", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.35)
    end)
    dropdown:SetScript("OnLeave", function(self)
        SetDropdownBorderColor(1, 1, 1, 0.2)
    end)

    container.dropdown = dropdown
    container.options = options or {}
    container.collapsedHeaders = {}
    container.searchText = ""

    dropdown:HookScript("OnHide", function()
        local menu = sharedDropdownMenu
        if menu and menu._owner == container then
            menu:Hide()
        end
    end)

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

    local function BuildMenu()
        local menu = GetSharedDropdownMenu()
        local scrollContent = menu.scrollContent
        ResetSharedMenuItems(menu)

        local yOff = -4
        local itemHeight = 22
        local headerHeight = 18
        local maxVisibleItems = DROPDOWN_MAX_VISIBLE_ITEMS
        local filterText = searchable and container.searchText and container.searchText:lower() or ""
        local isFiltering = filterText ~= ""
        local visibleCount = 0
        local currentHeader = nil
        local mutedColor = C.textMuted or {0.6, 0.6, 0.6}

        if isFiltering then
            menu.scrollFrame:SetVerticalScroll(0)
        end

        for i, opt in ipairs(container.options) do
            if opt.isHeader then
                currentHeader = opt.text

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
                    else
                        local header = AcquireSharedMenuHeader(menu)
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
                    local isCollapsed = collapsible and container.collapsedHeaders[currentHeader]
                    local header = AcquireSharedMenuHeader(menu)
                    if visibleCount > 0 then yOff = yOff - 4 end
                    header:SetHeight(headerHeight)
                    header:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, yOff)
                    header:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -4, yOff)
                    SetFont(header._headerText, 10, "", mutedColor)
                    header._headerText:SetText(opt.text)

                    if collapsible then
                        header._headerText:SetPoint("LEFT", 14, 0)
                        local c1, c2 = header._chevron1, header._chevron2
                        c1:Show()
                        c2:Show()
                        c1:SetColorTexture(mutedColor[1], mutedColor[2], mutedColor[3], 0.8)
                        c2:SetColorTexture(mutedColor[1], mutedColor[2], mutedColor[3], 0.8)
                        if isCollapsed then
                            c1:SetSize(5, 1)
                            c1:ClearAllPoints()
                            c1:SetPoint("LEFT", header, "LEFT", 4, 2)
                            c1:SetRotation(math.rad(-45))
                            c2:SetSize(5, 1)
                            c2:ClearAllPoints()
                            c2:SetPoint("LEFT", header, "LEFT", 4, -2)
                            c2:SetRotation(math.rad(45))
                        else
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
                            C_Timer.After(0, function() menu.updateThumb(); menu.UpdateScrollInset() end)
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
                local isCollapsed = collapsible and not isFiltering and currentHeader
                    and container.collapsedHeaders[currentHeader]
                if isCollapsed then
                elseif isFiltering and not opt.text:lower():find(filterText, 1, true) then
                else
                    local btn = AcquireSharedMenuButton(menu)
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
                        btn._selectedBar:SetColorTexture(C_accent_r, C_accent_g, C_accent_b, 1)
                        btn._selectedBar:Show()
                        btn._btnText:SetTextColor(C.tabSelectedText[1], C.tabSelectedText[2], C.tabSelectedText[3], C.tabSelectedText[4])
                    else
                        btn._selectedBg:Hide()
                        btn._selectedBar:Hide()
                        btn._btnText:SetTextColor(C_text_r, C_text_g, C_text_b, 1)
                    end
                    btn._hoverBg:Hide()

                    btn:SetScript("OnClick", function()
                        SetValue(opt.value)
                        menu:Hide()
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

        if isFiltering and visibleCount == 0 then
            local noMatch = AcquireSharedMenuButton(menu)
            noMatch:SetHeight(itemHeight)
            noMatch:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, -10)
            noMatch:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -4, -10)
            noMatch._selectedBg:Hide()
            noMatch._selectedBar:Hide()
            noMatch._hoverBg:Hide()
            noMatch._btnText:ClearAllPoints()
            noMatch._btnText:SetPoint("CENTER", 0, 0)
            SetFont(noMatch._btnText, 10, "", mutedColor)
            noMatch._btnText:SetText(ns.L["No matches"])
            noMatch:SetScript("OnClick", nil)
            noMatch:SetScript("OnEnter", nil)
            noMatch:SetScript("OnLeave", nil)
            yOff = -40
        end

        local totalHeight = math.abs(yOff) + 4
        local maxHeight = (maxVisibleItems * itemHeight) + 8
        local searchOffset = searchable and DROPDOWN_SEARCH_BOX_HEIGHT or 0

        scrollContent:SetHeight(totalHeight)
        scrollContent:SetWidth(dropdown:GetWidth() - 4)
        menu:SetHeight(math.min(totalHeight, maxHeight) + searchOffset)
    end

    dropdown:SetScript("OnClick", function()
        local menu = GetSharedDropdownMenu()
        if menu:IsShown() and menu._owner == container then
            menu:Hide()
            return
        end
        if menu:IsShown() then
            menu:Hide()
        end
        AcquireSharedMenuFor(menu, container, dropdown, searchable, BuildMenu)
        BuildMenu()
        PositionDropdownMenu(menu, dropdown, menu:GetHeight())
        menu:SetFrameLevel((container:GetFrameLevel() or 0) + 10)
        menu:Show()
        C_Timer.After(0, function() menu.updateThumb(); menu.UpdateScrollInset() end)
    end)

    local function SetOptions(newOptions)
        container.options = newOptions or {}
        if collapsible then
            for _, opt in ipairs(container.options) do
                if opt.isHeader and container.collapsedHeaders[opt.text] == nil then
                    container.collapsedHeaders[opt.text] = true
                end
            end
        end
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
            dropdown.selected:SetText(tostring(currentVal))
        elseif not found then
            dropdown.selected:SetText("")
        end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    container.SetOptions = BindWidgetMethod(container, SetOptions)
    container.UpdateVisual = UpdateVisual

    container.Refresh = function() UpdateVisual(GetValue()) end

    RegisterWidgetInstance(container, dbTable, dbKey)
    MaybeBindPinnedWidget(container, "dropdown", label, dbKey, dbTable, dropdown, registryInfo)

    SetValue(GetValue(), true)

    container.SetEnabled = function(self, enabled)
        dropdown:EnableMouse(enabled)
        container.isEnabled = enabled
        container:SetAlpha(enabled and 1 or 0.4)
    end
    container.isEnabled = true

    if not GUI:HasGeneratedSearchCache() then
        RegisterSearchSettingWidgetForBinding(dbTable, registryInfo, {
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
    end

    local tooltipDescription = registryInfo and registryInfo.description or nil
    AttachFormWidgetTooltip(container, dropdown, tooltipDescription, label)
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
    container._widgetLabel = label
    ApplyWidgetSyncContext(container, dbTable, dbKey)

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

    local swatch = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    swatch:SetSize(18, 18)
    swatch:SetPoint("LEFT", container, "LEFT", swatchLeftOffset, 0)
    if useUIKitBorders then
        swatch.bg = UIKit.CreateBackground(swatch, 1, 1, 1, 1)
        UIKit.CreateBorderLines(swatch)
        UIKit.UpdateBorderLines(swatch, 1, 1, 1, 1, 0.35, false)
    elseif SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(swatch, 1, true, false, { 1, 1, 1, 0.35 }, nil)
    end

    container.swatch = swatch
    container.label = text

    local function SetSwatchBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(swatch, 1, r, g, b, a or 1, false)
        else
            swatch:SetBackdropBorderColor(r, g, b, a or 1)
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
        if ColorPickerFrame:IsShown() then
            HideUIPanel(ColorPickerFrame)
            C_Timer.After(0, OpenPicker)
        else
            OpenPicker()
        end
    end)

    swatch:HookScript("OnEnter", function() SetSwatchBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    swatch:HookScript("OnLeave", function() SetSwatchBorderColor(1, 1, 1, 0.35) end)

    container.SetEnabled = function(self, enabled)
        swatch:EnableMouse(enabled)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    local effectiveDescription = (registryInfo and registryInfo.description)
        or (options and options.description)
        or nil

    if not GUI:HasGeneratedSearchCache() then
        RegisterSearchSettingWidgetForBinding(dbTable, registryInfo, {
            label = label,
            widgetType = "colorpicker",
            widgetBuilder = function(p)
                return GUI:CreateFormColorPicker(p, label, dbKey, dbTable, onChange, options)
            end,
            widgetDescriptor = GUI:BuildSearchWidgetDescriptor("colorpicker", dbKey, dbTable, {
                options = options,
            }),
            keywords = registryInfo and registryInfo.keywords or nil,
            description = effectiveDescription,
            relatedTo = registryInfo and registryInfo.relatedTo or nil,
        })
    end

    AttachFormWidgetTooltip(container, swatch, effectiveDescription, label)
    return container
end

function GUI:CreateScrollableTextBox(parent, height, text, options)
    options = options or {}
    local bgColor = options.bgColor or {0.05, 0.07, 0.1, 0.9}
    local borderColor = options.borderColor or C.border
    local fontSize = options.fontSize or 11

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetHeight(height)

    if SkinBase and SkinBase.ApplyPixelBackdrop then
        SkinBase.ApplyPixelBackdrop(container, 1, true, false, { borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1 }, { bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1 })
    end

    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", 6, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 4)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    ns.Helpers.ApplyFontWithFallback(editBox, GetFontPath(), fontSize, "")
    editBox:SetTextColor(0.7, 0.75, 0.8, 1)
    editBox:SetWidth(scrollFrame:GetWidth() or 400)
    editBox:SetText(text or "")
    editBox:SetCursorPosition(0)

    scrollFrame:SetScrollChild(editBox)

    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        editBox:SetWidth(w)
    end)

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

local SEARCH_DEBOUNCE = 0.15
local SEARCH_MIN_CHARS = 2
local SEARCH_MAX_RESULTS = 30

local function NormalizeSearchText(text)
    text = ns.Helpers.FoldUTF8(text)
    text = text:gsub("[%z\1-\31]", " ")
    text = text:gsub("[_%-%./\\&]+", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local SEARCH_LOCALIZE_MAX_DEPTH = 3

local function LocalizeGeneratedString(text, depth)
    if type(text) ~= "string" or text == "" then
        return text
    end
    local L = ns.L
    if type(L) ~= "table" then
        return text
    end

    local direct = L[text]
    if type(direct) == "string" and direct ~= text then
        return direct
    end

    depth = (depth or 0) + 1
    if depth > SEARCH_LOCALIZE_MAX_DEPTH then
        return text
    end

    if text:find(" > ", 1, true) then
        local parts, changed = {}, false
        for part in (text .. " > "):gmatch("(.-) > ") do
            local localized = LocalizeGeneratedString(part, depth)
            changed = changed or localized ~= part
            parts[#parts + 1] = localized
        end
        if changed then
            return table.concat(parts, " > ")
        end
        return text
    end

    if text:find("%d") then
        local numbers = {}
        local skeleton = (text:gsub("%d+", function(run)
            numbers[#numbers + 1] = run
            return "\1"
        end))
        for _, spec in ipairs({ "%%d", "%%s" }) do
            local formatKey = (skeleton:gsub("\1", spec))
            local translated = L[formatKey]
            if type(translated) == "string" and translated ~= formatKey then
                local index = 0
                return (translated:gsub("%%[ds]", function()
                    index = index + 1
                    return numbers[index] or ""
                end))
            end
        end
    end

    return text
end

function GUI:PrepareSearchEntry(entry, localize)
    if type(entry) ~= "table" then
        return entry
    end

    if localize then
        local sourceLabel = entry.label
        entry.label = LocalizeGeneratedString(entry.label)
        if type(sourceLabel) == "string" and entry.label ~= sourceLabel then
            entry.sourceLabel = sourceLabel
        end
        entry.description = LocalizeGeneratedString(entry.description)
        entry.tabName = LocalizeGeneratedString(entry.tabName)
        entry.subTabName = LocalizeGeneratedString(entry.subTabName)
        entry.sectionName = LocalizeGeneratedString(entry.sectionName)
        if type(entry.keywords) == "table" then
            local localized = {}
            for index, keyword in ipairs(entry.keywords) do
                localized[index] = LocalizeGeneratedString(keyword)
            end
            entry.keywords = localized
        end
    end

    entry._rawLabel = ns.Helpers.FoldUTF8(entry.label)
    entry._normLabel = NormalizeSearchText(entry.label)

    if type(entry.sourceLabel) == "string" then
        entry._rawSourceLabel = ns.Helpers.FoldUTF8(entry.sourceLabel)
        entry._normSourceLabel = NormalizeSearchText(entry.sourceLabel)
    end

    if type(entry.keywords) == "table" then
        local raw, normalized = {}, {}
        for index, keyword in ipairs(entry.keywords) do
            raw[index] = ns.Helpers.FoldUTF8(keyword)
            normalized[index] = NormalizeSearchText(keyword)
        end
        entry._rawKeywords = raw
        entry._normKeywords = normalized
    else
        entry._rawKeywords = nil
        entry._normKeywords = nil
    end

    if entry.tabName or entry.subTabName or entry.sectionName then
        local context = table.concat({
            entry.tabName or "",
            entry.subTabName or "",
            entry.sectionName or "",
        }, " ")
        entry._rawContext = ns.Helpers.FoldUTF8(context)
        entry._normContext = NormalizeSearchText(context)
    else
        entry._rawContext = nil
        entry._normContext = nil
    end

    return entry
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

local function DL1(a, b)
    local la, lb = #a, #b
    if math.abs(la - lb) > 1 then return false end
    if la == lb then
        local diffs, firstDiffI = 0, nil
        for i = 1, la do
            if a:byte(i) ~= b:byte(i) then
                diffs = diffs + 1
                if diffs == 1 then firstDiffI = i end
                if diffs > 2 then return false end
            end
        end
        if diffs <= 1 then return true end
        local i = firstDiffI
        return i < la
            and a:byte(i) == b:byte(i + 1)
            and a:byte(i + 1) == b:byte(i)
    end
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
    local raw = ns.Helpers.FoldUTF8(searchTerm)
    local normalized = NormalizeSearchText(searchTerm)
    local seen = {}
    local out = {}

    local function AddTerm(term, penalty)
        local rawTerm = ns.Helpers.FoldUTF8(term)
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

local function ScorePreparedText(rawText, normalizedText, term)
    if type(rawText) ~= "string" or rawText == "" or not term then return 0 end
    normalizedText = normalizedText or rawText

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

local SEARCH_INDEX_MIN_TOKEN = 3
local SEARCH_INDEX_MAX_PREFIX = 8

local function AddSearchPosting(index, token, entry)
    local bucket = index[token]
    if not bucket then
        bucket = {}
        index[token] = bucket
    end
    if bucket[#bucket] ~= entry then
        bucket[#bucket + 1] = entry
    end
end

local function IndexSearchText(index, text, entry)
    if type(text) ~= "string" or text == "" then return end
    for token in text:gmatch("%S+") do
        AddSearchPosting(index, token, entry)
        local limit = math.min(#token, SEARCH_INDEX_MAX_PREFIX)
        for length = SEARCH_INDEX_MIN_TOKEN, limit - 1 do
            AddSearchPosting(index, token:sub(1, length) .. "*", entry)
        end
    end
end

function GUI:InvalidateSearchTokenIndex()
    self._searchTokenIndex = nil
end

function GUI:BuildSearchTokenIndex()
    local navIndex, settingsIndex = {}, {}

    local function feed(index, registry)
        for _, entry in ipairs(registry or {}) do
            if not entry._normLabel then
                self:PrepareSearchEntry(entry)
            end
            IndexSearchText(index, entry._normLabel, entry)
            IndexSearchText(index, entry._normSourceLabel, entry)
            IndexSearchText(index, entry._normContext, entry)
            if entry._normKeywords then
                for _, keyword in ipairs(entry._normKeywords) do
                    IndexSearchText(index, keyword, entry)
                end
            end
        end
    end

    feed(navIndex, self.StaticNavigationRegistry)
    feed(navIndex, self.NavigationRegistry)
    feed(settingsIndex, self.StaticSettingsRegistry)
    feed(settingsIndex, self.SettingsRegistry)

    self._searchTokenIndex = { navigation = navIndex, settings = settingsIndex }
    return self._searchTokenIndex
end

function GUI:CollectSearchCandidates(searchTerms, kind)
    for _, term in ipairs(searchTerms) do
        if #term.tokens == 0 then return nil end
        for _, token in ipairs(term.tokens) do
            if #token < SEARCH_INDEX_MIN_TOKEN then return nil end
        end
    end

    local index = self._searchTokenIndex or self:BuildSearchTokenIndex()
    index = index[kind]
    if not index then return nil end

    local candidates, seen = {}, {}
    local function drain(bucket)
        if not bucket then return end
        for _, entry in ipairs(bucket) do
            if not seen[entry] then
                seen[entry] = true
                candidates[#candidates + 1] = entry
            end
        end
    end

    for _, term in ipairs(searchTerms) do
        for _, token in ipairs(term.tokens) do
            drain(index[token])
            drain(index[token:sub(1, math.min(#token, SEARCH_INDEX_MAX_PREFIX)) .. "*"])
        end
    end

    if #candidates == 0 then return nil end
    return candidates
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

GUI._searchTimer = nil

function GUI:CreateSearchBox(parent, placeholderText)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(160, 28)

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

    local icon = container:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", container, "LEFT", 8, 0)
    local atlasOk = ns.SafeCall("best-effort-style", function() icon:SetAtlas("common-search-magnifier") end)
    if not atlasOk or not icon:GetAtlas() then
        icon:SetTexture("Interface\\FriendsFrame\\UI-Searchbox-Icon")
    end
    icon:SetVertexColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    container._icon = icon

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    editBox:SetPoint("RIGHT", container, "RIGHT", -24, 0)
    editBox:SetHeight(16)
    editBox:SetAutoFocus(false)
    ns.Helpers.ApplyFontWithFallback(editBox, GetFontPath(), 10, "")
    editBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    editBox:SetMaxLetters(50)

    container._editBox = editBox

    local placeholder = editBox:CreateFontString(nil, "OVERLAY")
    SetFont(placeholder, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 1})
    placeholder:SetText(placeholderText or ns.L["Search settings..."])
    placeholder:SetPoint("LEFT", 0, 0)

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
        if container.onClear then
            container.onClear()
        end
    end)

    editBox:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()

        placeholder:SetShown(text == "")
        clearBtn:SetShown(text ~= "")

        if not userInput then return end

        if GUI._searchTimer then
            GUI._searchTimer:Cancel()
            GUI._searchTimer = nil
        end

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

    editBox:SetScript("OnEditFocusGained", function(self)
        container:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
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

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        if container.onClear then
            container.onClear()
        end
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    container.editBox = editBox
    container.placeholder = placeholder
    container.clearBtn = clearBtn

    return container
end

function GUI:ExecuteSearch(searchTerm)
    if not searchTerm or searchTerm:len() < SEARCH_MIN_CHARS then
        return {}, {}
    end

    local results = {}
    local navResults = {}
    local searchTerms = BuildSearchTerms(searchTerm)

    local function ScoreEntry(entry, keywordWeight, contextWeight)
        if not entry._rawLabel then
            self:PrepareSearchEntry(entry)
        end

        local bestScore = 0
        local rawKeywords, normKeywords = entry._rawKeywords, entry._normKeywords
        for _, term in ipairs(searchTerms) do
            local score = ScorePreparedText(entry._rawLabel, entry._normLabel, term)
            if entry._rawSourceLabel then
                score = math.max(score,
                    ScorePreparedText(entry._rawSourceLabel, entry._normSourceLabel, term))
            end
            if rawKeywords then
                for index = 1, #rawKeywords do
                    score = math.max(score,
                        ScorePreparedText(rawKeywords[index], normKeywords[index], term) * keywordWeight)
                end
            end
            if contextWeight and entry._rawContext then
                score = math.max(score,
                    ScorePreparedText(entry._rawContext, entry._normContext, term) * contextWeight)
            end
            bestScore = math.max(bestScore, score)
        end
        return bestScore
    end

    local function eachCandidate(kind, registries, visit)
        local candidates = self:CollectSearchCandidates(searchTerms, kind)
        if candidates then
            for _, entry in ipairs(candidates) do visit(entry) end
            return
        end
        for _, registry in ipairs(registries) do
            for _, entry in ipairs(registry) do visit(entry) end
        end
    end

    local mergedNavResults = {}
    local mergedNavByKey = {}
    eachCandidate("navigation", {
        self.StaticNavigationRegistry or {},
        self.NavigationRegistry or {},
    }, function(entry)
        MergeSearchHit(self, mergedNavResults, mergedNavByKey, entry, ScoreEntry(entry, 0.9))
    end)

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
    eachCandidate("settings", {
        self.StaticSettingsRegistry or {},
        self.SettingsRegistry or {},
    }, function(entry)
        MergeSearchHit(self, mergedSettingsResults, mergedSettingsByKey, entry, ScoreEntry(entry, 0.72, 0.45))
    end)

    table.sort(mergedSettingsResults, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return (a.data.label or "") < (b.data.label or "")
    end)

    if #mergedSettingsResults > SEARCH_MAX_RESULTS then
        for i = SEARCH_MAX_RESULTS + 1, #mergedSettingsResults do
            mergedSettingsResults[i] = nil
        end
    end

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
        ns.SafeCall("bulkhead", feature.apply)
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

function GUI:RenderSearchResults(content, results, searchTerm, navResults)
    if not content then return end

    local cache = content._searchRenderCache
    if not cache then
        cache = {
            widgets = {},
            navRows = {},
            goButtons = {},
            crumbs = {},
            fallbackRows = {},
            fs = {},
            tex = {},
        }
        content._searchRenderCache = cache
    end
    for _, w in pairs(cache.widgets) do w:Hide(); w:ClearAllPoints() end
    for _, r in pairs(cache.navRows) do r:Hide(); r:ClearAllPoints() end
    for _, b in pairs(cache.goButtons) do b:Hide(); b:ClearAllPoints() end
    for _, b in pairs(cache.crumbs) do b:Hide(); b:ClearAllPoints() end
    for _, r in pairs(cache.fallbackRows) do r:Hide(); r:ClearAllPoints() end
    for _, fs in ipairs(cache.fs) do fs:Hide() end
    for _, tex in ipairs(cache.tex) do tex:Hide() end
    cache.fsUsed = 0
    cache.texUsed = 0
    if content._searchErrorRow then content._searchErrorRow:Hide() end

    local function AcquireFS()
        cache.fsUsed = cache.fsUsed + 1
        local fs = cache.fs[cache.fsUsed]
        if not fs then
            fs = content:CreateFontString(nil, "OVERLAY")
            cache.fs[cache.fsUsed] = fs
        end
        fs:ClearAllPoints()
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:Show()
        return fs
    end

    local function AcquireTex()
        cache.texUsed = cache.texUsed + 1
        local tex = cache.tex[cache.texUsed]
        if not tex then
            tex = content:CreateTexture(nil, "ARTWORK")
            cache.tex[cache.texUsed] = tex
        end
        tex:ClearAllPoints()
        tex:Show()
        return tex
    end

    local y = -10
    local PADDING = 15
    local FORM_ROW = 32

    local hasResults = (results and #results > 0) or (navResults and #navResults > 0)

    if not hasResults then
        if searchTerm and searchTerm ~= "" then
            local noResults = AcquireFS()
            SetFont(noResults, 12, "", C.textMuted)
            noResults:SetText(ns.L["No settings match \"%s\""]:format(searchTerm))
            noResults:SetPoint("TOPLEFT", PADDING, y)
            y = y - 30

            local tip = AcquireFS()
            SetFont(tip, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7})
            tip:SetText(ns.L["Try different keywords"])
            tip:SetPoint("TOPLEFT", PADDING, y)
            y = y - 30
        else
            local instructions = AcquireFS()
            SetFont(instructions, 12, "", C.textMuted)
            instructions:SetText(ns.L["Search settings — try 'cooldown', 'party', 'action bars'"])
            instructions:SetPoint("TOPLEFT", PADDING, y)
            y = y - 20

            local hint = AcquireFS()
            SetFont(hint, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.6})
            hint:SetText(ns.L["Shortcut: / or Ctrl+F to focus"])
            hint:SetPoint("TOPLEFT", PADDING, y)
            y = y - 20
        end

        content:SetHeight(math.abs(y) + 20)
        return
    end

    if navResults and #navResults > 0 then
        local navHeader = AcquireFS()
        SetFont(navHeader, 11, "", C.textMuted)
        navHeader:SetText(ns.L["Categories & Sections"])
        navHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20

        for _, navResult in ipairs(navResults) do
            local entry = navResult.data

            local navKey = BuildMergedSearchIdentity(GUI, entry)
            local navRow = cache.navRows[navKey]
            if not navRow then
                navRow = CreateFrame("Button", nil, content, "BackdropTemplate")
                if SkinBase and SkinBase.ApplyPixelBackdrop then
                    SkinBase.ApplyPixelBackdrop(navRow, 1, true, false, { 0.2, 0.22, 0.25, 0.6 }, { 0.12, 0.14, 0.17, 0.8 })
                end

                local typeBadge = navRow:CreateFontString(nil, "OVERLAY")
                local typeLabels = {tab = ns.L["TAB"], subtab = ns.L["SUBTAB"], section = ns.L["SECTION"], moduleToggle = ns.L["[Module]"]}
                local isModuleToggle = entry.navType == "moduleToggle"
                if isModuleToggle then
                    SetFont(typeBadge, 9, "", C.accent)
                else
                    SetFont(typeBadge, 9, "", C.textMuted)
                end
                typeBadge:SetText(typeLabels[entry.navType] or ns.L["NAV"])
                typeBadge:SetPoint("LEFT", 8, 0)

                local navLabel = navRow:CreateFontString(nil, "OVERLAY")
                SetFont(navLabel, 11, "", C.text)
                navLabel:SetText(entry.label or "")
                navLabel:SetPoint("LEFT", typeBadge, "RIGHT", 10, 0)
                navLabel:SetPoint("RIGHT", navRow, "RIGHT", -50, 0)
                navLabel:SetJustifyH("LEFT")
                navLabel:SetWordWrap(false)

                if not isModuleToggle then
                    local goText = navRow:CreateFontString(nil, "OVERLAY")
                    SetFont(goText, 10, "", C.accent)
                    goText:SetText(ns.L["Go >"])
                    goText:SetPoint("RIGHT", -10, 0)
                end

                if isModuleToggle and entry.featureId then
                    local registry = ns.Settings and ns.Settings.Registry
                    local feature = registry
                        and type(registry.GetFeature) == "function"
                        and registry:GetFeature(entry.featureId)
                        or nil
                    if feature and feature.moduleEntry
                       and ns.QUI_ModulesPage and ns.QUI_ModulesPage.CreateModuleTogglePill then
                        local pill = ns.QUI_ModulesPage.CreateModuleTogglePill(navRow, feature.id, feature.moduleEntry)
                        pill:SetPoint("RIGHT", navRow, "RIGHT", -8, 0)
                        navRow._pill = pill

                        pill:SetScript("OnMouseDown", function()
                            navRow._suppressNavigate = true
                        end)
                        pill:HookScript("OnClick", function(self)
                            if self._refresh then self._refresh() end
                        end)
                    end
                end

                navRow:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
                    self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
                end)
                navRow:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0.12, 0.14, 0.17, 0.8)
                    self:SetBackdropBorderColor(0.2, 0.22, 0.25, 0.6)
                end)

                navRow:SetScript("OnClick", function(self)
                    if self._suppressNavigate then
                        self._suppressNavigate = false
                        return
                    end
                    GUI:NavigateSearchResult(self._navEntry)
                end)

                cache.navRows[navKey] = navRow
            elseif navRow._pill and navRow._pill._refresh then
                navRow._pill._refresh()
            end

            navRow._navEntry = entry
            navRow:SetSize(content:GetWidth() - (PADDING * 2), 26)
            navRow:SetPoint("TOPLEFT", PADDING, y)
            navRow:Show()

            y = y - 30
        end

        y = y - 10

        if results and #results > 0 then
            local sep = AcquireTex()
            sep:SetPoint("TOPLEFT", PADDING, y + 5)
            sep:SetSize(content:GetWidth() - (PADDING * 2), 1)
            sep:SetColorTexture(0.3, 0.32, 0.35, 0.5)
            y = y - 15
        end
    end

    if not results or #results == 0 then
        content:SetHeight(math.abs(y) + 20)
        return
    end

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

    GUI._suppressSearchRegistration = true

    local function RenderGroupedResults()
    for _, groupKey in ipairs(tabOrder) do
        local group = groupedResults[groupKey]
        local groupData = group.data

        local header = AcquireFS()
        SetFont(header, 12, "", C.accentLight)
        header:SetText(groupKey)
        header:SetPoint("TOPLEFT", PADDING, y)

        if GUI.ResolveSearchNavigation and GUI:ResolveSearchNavigation(groupData) then
            local goBtn = cache.goButtons[groupKey]
            if not goBtn then
                goBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
                goBtn:SetSize(36, 16)
                if SkinBase and SkinBase.ApplyPixelBackdrop then
                    SkinBase.ApplyPixelBackdrop(goBtn, 1, true, false, { C.accent[1], C.accent[2], C.accent[3], 0.5 }, { C.accent[1], C.accent[2], C.accent[3], 0.15 })
                end

                local btnText = goBtn:CreateFontString(nil, "OVERLAY")
                SetFont(btnText, 9, "", C.accent)
                btnText:SetText(ns.L["Go >"])
                btnText:SetPoint("CENTER", 0, 0)

                goBtn:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.3)
                    self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
                end)
                goBtn:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
                    self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
                end)

                goBtn:SetScript("OnClick", function(self)
                    GUI:NavigateSearchResult(self._navEntry)
                end)

                cache.goButtons[groupKey] = goBtn
            end
            goBtn._navEntry = groupData
            goBtn:SetPoint("LEFT", header, "RIGHT", 8, 0)
            goBtn:Show()
        end

        y = y - 24

        local sep = AcquireTex()
        sep:SetPoint("TOPLEFT", PADDING, y + 2)
        sep:SetSize(content:GetWidth() - (PADDING * 2), 1)
        sep:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        y = y - 12

        for _, result in ipairs(group.entries) do
            local entry = result.data

            local widget = nil
            if entry.widgetBuilder or entry.widgetDescriptor then
                local entryKey = BuildMergedSearchIdentity(GUI, entry)
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
                    local crumbBtn = cache.crumbs[entryKey]
                    if not crumbBtn then
                        crumbBtn = CreateFrame("Button", nil, content)

                        local crumb = crumbBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        SetFont(crumb, 11, "")
                        crumb:SetPoint("LEFT", crumbBtn, "LEFT", 0, 0)
                        crumb:SetTextColor(0.55, 0.55, 0.6, 1)
                        crumb:SetJustifyH("LEFT")
                        crumbBtn._crumb = crumb

                        crumbBtn:SetScript("OnEnter", function() crumb:SetTextColor(1, 1, 1, 1) end)
                        crumbBtn:SetScript("OnLeave", function() crumb:SetTextColor(0.55, 0.55, 0.6, 1) end)

                        crumbBtn:SetScript("OnClick", function(self)
                            local clickEntry = self._navEntry
                            GUI:NavigateSearchResult(clickEntry, {
                                scrollToLabel = clickEntry.label,
                                pulse = true,
                            })
                        end)

                        cache.crumbs[entryKey] = crumbBtn
                    end
                    crumbBtn._navEntry = entry
                    crumbBtn._crumb:SetText(crumbText)
                    crumbBtn:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING + 4, y - 2)
                    crumbBtn:SetHeight(14)
                    crumbBtn:SetWidth(content:GetWidth() - (PADDING * 2) - 8)
                    crumbBtn:Show()
                    y = y - CRUMB_HEIGHT
                end

                widget = cache.widgets[entryKey]
                if widget then
                    widget:Show()
                    if widget.Refresh then
                        widget.Refresh()
                    elseif widget.UpdateVisual and widget.GetValue then
                        widget.UpdateVisual(widget.GetValue())
                    end
                else
                    if entry.widgetBuilder then
                        widget = entry.widgetBuilder(content)
                    else
                        widget = GUI:CreateSearchWidgetFromDescriptor(content, entry)
                    end
                    if widget then
                        cache.widgets[entryKey] = widget
                    end
                end
                if widget then
                    widget:SetPoint("TOPLEFT", PADDING, y)
                    widget:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
                    y = y - FORM_ROW
                end

                if entry.description and entry.description ~= "" then
                    local desc = AcquireFS()
                    SetFont(desc, 11, "")
                    desc:SetPoint("TOPLEFT", PADDING + 4, y)
                    desc:SetPoint("RIGHT", content, "RIGHT", -(PADDING + 4), 0)
                    desc:SetText(entry.description)
                    desc:SetTextColor(0.7, 0.7, 0.72, 1)
                    desc:SetJustifyH("LEFT")
                    desc:SetWordWrap(true)
                    y = y - DESC_HEIGHT
                end
            end

            if not widget then
                local hasRoute = GUI.ResolveSearchNavigation and GUI:ResolveSearchNavigation(entry)
                if hasRoute then
                    local fallbackKey = BuildMergedSearchIdentity(GUI, entry)
                    local fallbackRow = cache.fallbackRows[fallbackKey]
                    if not fallbackRow then
                        fallbackRow = CreateFrame("Button", nil, content, "BackdropTemplate")
                        if SkinBase and SkinBase.ApplyPixelBackdrop then
                            SkinBase.ApplyPixelBackdrop(fallbackRow, 1, true, false, { 0.2, 0.22, 0.25, 0.45 }, { 0.12, 0.14, 0.17, 0.55 })
                        end

                        local fallbackLabel = fallbackRow:CreateFontString(nil, "OVERLAY")
                        SetFont(fallbackLabel, 11, "", C.textMuted)
                        fallbackLabel:SetPoint("LEFT", 8, 0)
                        fallbackLabel:SetPoint("RIGHT", -8, 0)
                        fallbackLabel:SetJustifyH("LEFT")
                        fallbackRow._label = fallbackLabel

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
                        fallbackRow:SetScript("OnClick", function(self)
                            GUI:NavigateSearchResult(self._navEntry, {
                                scrollToLabel = self._navEntry.label,
                                pulse = true,
                            })
                        end)

                        cache.fallbackRows[fallbackKey] = fallbackRow
                    end
                    fallbackRow._navEntry = entry
                    fallbackRow._label:SetText(entry.label or ns.L["Unknown setting"])
                    fallbackRow:SetSize(content:GetWidth() - (PADDING * 2), 24)
                    fallbackRow:SetPoint("TOPLEFT", PADDING, y)
                    fallbackRow:Show()
                    y = y - 28
                else
                    local fallbackLabel = AcquireFS()
                    SetFont(fallbackLabel, 11, "", C.textMuted)
                    fallbackLabel:SetText(entry.label or ns.L["Unknown setting"])
                    fallbackLabel:SetPoint("TOPLEFT", PADDING, y)
                    y = y - 24
                end
            end
        end

        y = y - 10
    end
    end

    local ok, err = xpcall(RenderGroupedResults, geterrorhandler and geterrorhandler() or debug.traceback)

    GUI._suppressSearchRegistration = false

    if not ok then
        local errorRow = content._searchErrorRow
        if not errorRow then
            errorRow = CreateFrame("Frame", nil, content, "BackdropTemplate")
            if SkinBase and SkinBase.ApplyPixelBackdrop then
                SkinBase.ApplyPixelBackdrop(errorRow, 1, true, false, { 1, 0.25, 0.25, 0.65 }, { 0.25, 0.05, 0.05, 0.75 })
            end

            local label = errorRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            SetFont(label, 11, "", {1, 0.45, 0.45, 1})
            label:SetPoint("LEFT", errorRow, "LEFT", 8, 0)
            label:SetPoint("RIGHT", errorRow, "RIGHT", -8, 0)
            label:SetJustifyH("LEFT")
            label:SetText(ns.L["Some search results failed to render. Check the Lua error log."])

            content._searchErrorRow = errorRow
        end
        errorRow:ClearAllPoints()
        errorRow:SetSize(content:GetWidth() - (PADDING * 2), 28)
        errorRow:SetPoint("TOPLEFT", PADDING, y)
        errorRow:Show()
        y = y - 32
    end

    content:SetHeight(math.abs(y) + 20)
end

function GUI:CreateMainFrame()
    if self.MainFrame then
        return self.MainFrame
    end

    self.SectionRegistry = {}
    self.SectionRegistryOrder = {}
    self:ClearSearchContext()

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

    local frame = CreateFrame("Frame", "QUI_Options", UIParent)

    frame:SetScale((profile and profile.configPanelScale) or 1.0)

    local function ClampPanelToScreen()
        frame:SetSize(
            math.max(GUI.PANEL_MIN_WIDTH, math.min(GUI:MaxPanelWidth(frame), frame:GetWidth())),
            math.max(GUI.PANEL_MIN_HEIGHT, math.min(GUI:MaxPanelHeight(frame), frame:GetHeight())))
    end

    local savedWidth = (profile and profile.configPanelWidth) or FRAME_WIDTH
    local savedHeight = (profile and profile.configPanelHeight) or FRAME_HEIGHT
    frame:SetSize(savedWidth, savedHeight)
    ClampPanelToScreen()

    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(500)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:Hide()

    local savedAlpha = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile.configPanelAlpha or 0.97
    frame._bg = UIKit.CreateBackground(frame, C.bg[1], C.bg[2], C.bg[3], savedAlpha)
    UIKit.CreateBorderLines(frame)
    UIKit.UpdateBorderLines(frame, 1, C.border[1], C.border[2], C.border[3], C.border[4] or 1)

    self.MainFrame = frame

    if not tContains(UISpecialFrames, "QUI_Options") then
        tinsert(UISpecialFrames, "QUI_Options")
    end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(50)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(title, 14, "OUTLINE", C.accentLight)
    title:SetText("QUI")
    title:SetPoint("TOPLEFT", 12, -10)

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(version, 11, "", C.accentLight)
    local versionText = (QUI and QUI.versionString) or C_AddOns.GetAddOnMetadata("QUI", "Version") or "1.0.0-alpha1"
    version:SetText("v" .. versionText)
    version:SetPoint("TOPRIGHT", -40, -10)

    local thumb

    local accentSwatch = CreateFrame("Button", nil, titleBar)
    accentSwatch:SetSize(14, 14)
    accentSwatch:SetPoint("TOPLEFT", titleBar, "TOPLEFT", SIDEBAR_W + 14, -8)
    accentSwatch._bg = UIKit.CreateBackground(accentSwatch, C.accent[1], C.accent[2], C.accent[3], 1)
    UIKit.CreateBorderLines(accentSwatch)
    UIKit.UpdateBorderLines(accentSwatch, 1, 0.4, 0.4, 0.4, 1)

    local function RefreshAllSkinning()
        if ns.Registry then
            ns.Registry:RefreshAll("skinning")
        end
        if _G.QUI_RefreshStatusTrackingBarSkin then _G.QUI_RefreshStatusTrackingBarSkin() end
    end

    local function ApplyAccentToAll(r, g, b)
        GUI:ApplyAccentColor(r, g, b)
        accentSwatch._bg:SetVertexColor(r, g, b, 1)
        title:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
        version:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
        RefreshAllSkinning()
    end

    local themeLabel = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(themeLabel, 10, "", C.textMuted)
    themeLabel:SetText(ns.L["Theme"])
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
        db.skinUseClassColor = (presetName == "Class Colored")
        local r, g, b = GUI:ResolveThemePreset(presetName)
        db.addonAccentColor = {r, g, b, 1}
        GUI:ApplyAccentColor(r, g, b)
        accentSwatch._bg:SetVertexColor(r, g, b, 1)
        accentSwatch:SetAlpha(presetName == "Custom" and 1 or 0.5)
        themeDropText:SetText(presetName)
        GUI:RefreshAccentColor()
        C_Timer.After(0, RefreshAllSkinning)
    end

    local themeMenu = CreateFrame("Frame", nil, themeDropBtn)
    UIKit.CreateBackground(themeMenu, 0.08, 0.08, 0.12, 0.95)
    UIKit.CreateBorderLines(themeMenu)
    UIKit.UpdateBorderLines(themeMenu, 1, 0.3, 0.3, 0.3, 1)
    themeMenu:SetFrameStrata("TOOLTIP")
    themeMenu:Hide()

    local function BuildThemeMenu()
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

            local presetColor
            for _, p in ipairs(GUI.ThemePresets) do
                if p.name == name then presetColor = p.color; break end
            end
            if name == "Class Colored" then
                local _, class = UnitClass("player")
                -- @secret-policy: collapse-only — secret class ⇒ no swatch (text-only entry).
                if issecretvalue and issecretvalue(class) then class = nil end
                local cc = class and RAID_CLASS_COLORS[class]
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

    themeMenu:SetScript("OnHide", function()
        UIKit.UpdateBorderLines(themeDropBtn, 1, 0.3, 0.3, 0.3, 1)
    end)

    accentSwatch:SetScript("OnEnter", function(self)
        UIKit.UpdateBorderLines(self, 1, C_accentLight_r, C_accentLight_g, C_accentLight_b, C_accentLight_a)
    end)
    accentSwatch:SetScript("OnLeave", function(self)
        UIKit.UpdateBorderLines(self, 1, 0.4, 0.4, 0.4, 1)
    end)

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

    do
        local initDB = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile and QUI.QUICore.db.profile.general
        local preset = initDB and initDB.themePreset or "Sky Blue"
        themeDropText:SetText(preset)
        local r, g, b = GUI:ResolveThemePreset(preset)
        ApplyAccentToAll(r, g, b)
        accentSwatch:SetAlpha(preset == "Custom" and 1 or 0.5)
    end

    local LOCALE_NAMES = {
        enUS = "English",          deDE = "Deutsch",
        esES = "Español",          esMX = "Español (México)",
        frFR = "Français",         itIT = "Italiano",
        koKR = "한국어",            ptBR = "Português",
        ruRU = "Русский",          zhCN = "简体中文",
        zhTW = "繁體中文",
    }
    local LOCALE_ORDER = {
        "enUS", "deDE", "esES", "esMX", "frFR", "itIT",
        "koKR", "ptBR", "ruRU", "zhCN", "zhTW",
    }

    local function GetSelectedLocale()
        local g = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.global
        return (g and g.selectedLocale) or GetLocale()
    end

    local langLabel = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(langLabel, 10, "", C.textMuted)
    langLabel:SetText(ns.L["Language"])
    langLabel:SetPoint("LEFT", themeDropBtn, "RIGHT", 14, 0)

    local langDropBtn = CreateFrame("Button", nil, titleBar)
    langDropBtn:SetSize(110, 16)
    langDropBtn:SetPoint("LEFT", langLabel, "RIGHT", 6, 0)
    UIKit.CreateBackground(langDropBtn, 0.1, 0.1, 0.1, 0.8)
    UIKit.CreateBorderLines(langDropBtn)
    UIKit.UpdateBorderLines(langDropBtn, 1, 0.3, 0.3, 0.3, 1)

    local langDropText = langDropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(langDropText, 10, "", C.text)
    langDropText:SetPoint("LEFT", 4, 0)
    langDropText:SetPoint("RIGHT", -14, 0)
    langDropText:SetJustifyH("LEFT")
    langDropText:SetWordWrap(false)
    langDropText:SetText(LOCALE_NAMES[GetSelectedLocale()] or "English")

    local langDropArrow = langDropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(langDropArrow, 8, "", C.textMuted)
    langDropArrow:SetText("v")
    langDropArrow:SetPoint("RIGHT", -3, 0)

    local langMenu = CreateFrame("Frame", nil, langDropBtn)
    UIKit.CreateBackground(langMenu, 0.08, 0.08, 0.12, 0.95)
    UIKit.CreateBorderLines(langMenu)
    UIKit.UpdateBorderLines(langMenu, 1, 0.3, 0.3, 0.3, 1)
    langMenu:SetFrameStrata("TOOLTIP")
    langMenu:Hide()

    local function ApplyLocaleSelection(code)
        local g = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.global
        if not g then return end
        g.selectedLocale = code
        langDropText:SetText(LOCALE_NAMES[code] or code)
        if QUI.GUI and QUI.GUI.ShowConfirmation then
            QUI.GUI:ShowConfirmation({
                title = ns.L["Reload Required"],
                message = ns.L["Reload the UI to apply the new language?"],
                acceptText = ns.L["Reload Now"],
                cancelText = ns.L["Later"],
                onAccept = function()
                    if QUI.SafeReload then QUI:SafeReload() else ReloadUI() end
                end,
            })
        end
    end

    local function BuildLangMenu()
        for _, child in ipairs({langMenu:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        local itemH = 18
        langMenu:SetSize(langDropBtn:GetWidth(), #LOCALE_ORDER * itemH + 4)
        langMenu:ClearAllPoints()
        langMenu:SetPoint("TOPLEFT", langDropBtn, "BOTTOMLEFT", 0, -2)

        local current = GetSelectedLocale()
        for i, code in ipairs(LOCALE_ORDER) do
            local item = CreateFrame("Button", nil, langMenu)
            item:SetSize(langDropBtn:GetWidth() - 4, itemH)
            item:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * itemH))

            local itemBg = item:CreateTexture(nil, "BACKGROUND")
            itemBg:SetAllPoints()
            itemBg:SetColorTexture(0, 0, 0, 0)

            local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            SetFont(itemText, 10, "", code == current and C.accent or C.text)
            itemText:SetText(LOCALE_NAMES[code] or code)
            itemText:SetPoint("LEFT", 4, 0)

            item:SetScript("OnEnter", function()
                itemBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
            end)
            item:SetScript("OnLeave", function()
                itemBg:SetColorTexture(0, 0, 0, 0)
            end)
            item:SetScript("OnClick", function()
                langMenu:Hide()
                ApplyLocaleSelection(code)
            end)
        end
    end

    langDropBtn:SetScript("OnClick", function()
        if langMenu:IsShown() then
            langMenu:Hide()
        else
            BuildLangMenu()
            langMenu:Show()
        end
    end)
    langDropBtn:SetScript("OnEnter", function()
        UIKit.UpdateBorderLines(langDropBtn, 1, C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    langDropBtn:SetScript("OnLeave", function()
        if not langMenu:IsShown() then
            UIKit.UpdateBorderLines(langDropBtn, 1, 0.3, 0.3, 0.3, 1)
        end
    end)
    langMenu:SetScript("OnHide", function()
        UIKit.UpdateBorderLines(langDropBtn, 1, 0.3, 0.3, 0.3, 1)
    end)

    local scaleContainer = CreateFrame("Frame", nil, titleBar)
    scaleContainer:SetSize(160, 20)
    scaleContainer:SetPoint("LEFT", langDropBtn, "RIGHT", 14, 0)

    local scaleLabel = scaleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(scaleLabel, 10, "", C.textMuted)
    scaleLabel:SetText(ns.L["Panel Scale:"])
    scaleLabel:SetPoint("LEFT", scaleContainer, "LEFT", 0, 0)

    local scaleEditBox = CreateFrame("EditBox", nil, scaleContainer)
    scaleEditBox:SetSize(38, 16)
    scaleEditBox:SetPoint("LEFT", scaleLabel, "RIGHT", 5, 0)
    UIKit.CreateBackground(scaleEditBox, 0.08, 0.08, 0.08, 1)
    UIKit.CreateBorderLines(scaleEditBox)
    UIKit.UpdateBorderLines(scaleEditBox, 1, 0.25, 0.25, 0.25, 1)
    ns.Helpers.ApplyFontWithFallback(scaleEditBox, GetFontPath(), 10, "")
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
        ClampPanelToScreen()
        if QUI.QUICore and QUI.QUICore.db then
            QUI.QUICore.db.profile.configPanelScale = value
            QUI.QUICore._preservedPanelScale = value
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

    UIKit.CreateCloseButton(titleBar, {
        size = 22,
        point = "TOPRIGHT", relativeTo = frame, x = -10, y = -5,
        onClick = function() frame:Hide() end,
    })

    local titleSep = frame:CreateTexture(nil, "ARTWORK")
    titleSep:SetPoint("TOPLEFT", 10, -30)
    titleSep:SetPoint("TOPRIGHT", -10, -30)
    titleSep:SetHeight(1)
    titleSep:SetColorTexture(C_border_r, C_border_g, C_border_b, C_border_a)

    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 10, -35)
    sidebar:SetPoint("BOTTOMLEFT", 10, 10)
    sidebar:SetWidth(SIDEBAR_W)

    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(C.bgSidebar[1], C.bgSidebar[2], C.bgSidebar[3], C.bgSidebar[4])
    sidebar._bg = sidebarBg

    local sidebarBorder = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebarBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarBorder:SetWidth(1)
    sidebarBorder:SetColorTexture(C_border_r, C_border_g, C_border_b, C_border_a)
    sidebar._divider = sidebarBorder

    frame.sidebar = sidebar

    local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMRIGHT", 1, 0)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
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

    local resetBtn = GUI:CreateButton(footer, ns.L["Reset to Defaults"], 0, 22, function()
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

    local reloadBtn = GUI:CreateButton(footer, ns.L["Reload UI"], 0, 22, function()
        if QUI and QUI.SafeReload then
            QUI:SafeReload()
        else
            ReloadUI()
        end
    end, "ghost")
    reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
    frame._footerReloadBtn = reloadBtn

    local subTabBar = CreateFrame("Frame", nil, frame)
    subTabBar:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    subTabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -35)
    subTabBar:SetHeight(30)
    subTabBar:SetFrameLevel(frame:GetFrameLevel() + 5)
    subTabBar:EnableMouse(true)
    subTabBar:Hide()

    local subTabBarBg = subTabBar:CreateTexture(nil, "BACKGROUND")
    subTabBarBg:SetAllPoints()
    subTabBarBg:SetColorTexture(unpack(C.bgContent))

    local subTabBarBorder = subTabBar:CreateTexture(nil, "ARTWORK")
    subTabBarBorder:SetPoint("BOTTOMLEFT", subTabBar, "BOTTOMLEFT", 0, 0)
    subTabBarBorder:SetPoint("BOTTOMRIGHT", subTabBar, "BOTTOMRIGHT", 0, 0)
    subTabBarBorder:SetHeight(1)
    subTabBarBorder:SetColorTexture(C_border_r, C_border_g, C_border_b, C_border_a)

    frame.subTabBar = subTabBar

    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    contentArea:SetPoint("BOTTOMRIGHT", -10, 46)
    contentArea:EnableMouse(false)

    local contentBg = contentArea:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints()
    contentBg:SetColorTexture(unpack(C.bgContent))

    local glow = contentArea:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(contentArea)
    glow:SetTexture("Interface\\BUTTONS\\WHITE8x8")
    if glow.SetGradient then
        local ok = ns.SafeCall("best-effort-style", function()
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

    frame.tabs = {}
    frame.pages = {}
    frame.activeTab = nil

    local MIN_HEIGHT = GUI.PANEL_MIN_HEIGHT
    local MIN_WIDTH = GUI.PANEL_MIN_WIDTH

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

                local newWidth = math.max(MIN_WIDTH, math.min(GUI:MaxPanelWidth(frame), self.startWidth + deltaX))
                local newHeight = math.max(MIN_HEIGHT, math.min(GUI:MaxPanelHeight(frame), self.startHeight + deltaY))

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
                QUI.QUICore.db.profile.configPanelHeight = frame:GetHeight()
            end
        end
    end)

    resizeHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(ns.L["Drag to resize"], 1, 1, 1)
        GameTooltip:Show()
    end)

    resizeHandle:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    frame.resizeHandle = resizeHandle

    frame:SetScript("OnHide", function()
        local gfem = ns and ns.QUI_GroupFrameEditMode
        if gfem then
            if gfem:IsEditMode() then gfem:DisableEditMode() end
            if gfem:IsTestMode() then gfem:DisableTestMode() end
        end
    end)

    return frame
end

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

function GUI:Hide()
    if self.MainFrame then
        self.MainFrame:Hide()
    end
end

function GUI:RefreshAccentColor()
    if not self.MainFrame then return end
    local wasShown = self.MainFrame:IsShown()
    local prevTileIndex = self.MainFrame._lastTileIndex
    local activeTile = prevTileIndex
        and self.MainFrame._tiles
        and self.MainFrame._tiles[prevTileIndex]
        or nil
    local prevSubPageIndex = activeTile and activeTile._activeSubPageIndex or nil

    local point, _, relPoint, xOfs, yOfs = self.MainFrame:GetPoint()

    if self.TeardownFrameTree then
        self:TeardownFrameTree(self.MainFrame, { includeRoot = true })
    else
        self.MainFrame:Hide()
        self.MainFrame:SetParent(nil)
    end
    self.MainFrame = nil

    self.SettingsRegistry = {}
    self.SettingsRegistryKeys = {}

    self:InitializeOptions()

    if point and self.MainFrame then
        self.MainFrame:ClearAllPoints()
        self.MainFrame:SetPoint(point, UIParent, relPoint, xOfs, yOfs)
    end

    if prevTileIndex and self.MainFrame and self.MainFrame._tiles and self.MainFrame._tiles[prevTileIndex] then
        self:SelectFeatureTile(self.MainFrame, prevTileIndex, {
            subPageIndex = prevSubPageIndex,
        })
    end

    if wasShown and self.MainFrame then
        self.MainFrame:Show()
    end

    if self.NotifyAccentChanged then self:NotifyAccentChanged() end
end

local function StyleScrollBar(scrollFrame)
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if not scrollBar then return end

    if scrollBar.Track then
        scrollBar.Track:SetAlpha(0)
    end

    local thumb = scrollBar.ThumbTexture or scrollBar:GetThumbTexture()
    if thumb then
        thumb:SetColorTexture(C.scrollThumb[1], C.scrollThumb[2], C.scrollThumb[3], C.scrollThumb[4])
        thumb:SetSize(8, 40)
    end

    local upBtn = scrollBar.ScrollUpButton or _G[scrollFrame:GetName() .. "ScrollBarScrollUpButton"]
    local downBtn = scrollBar.ScrollDownButton or _G[scrollFrame:GetName() .. "ScrollBarScrollDownButton"]
    if upBtn then upBtn:SetAlpha(0) upBtn:SetSize(1, 1) end
    if downBtn then downBtn:SetAlpha(0) downBtn:SetSize(1, 1) end
end

local ExportPopup = nil

function GUI:ShowExportPopup(title, exportString)
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

        popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        popup.title:SetPoint("TOP", 0, -12)
        popup.title:SetTextColor(1, 1, 1, 1)

        popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        popup.hint:SetPoint("TOP", popup.title, "BOTTOM", 0, -4)
        SetFont(popup.hint, 11, "", C.textMuted)
        popup.hint:SetText(ns.L["Select all (Ctrl+A) then copy (Ctrl+C)"])

        local editBg = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        editBg:SetPoint("TOPLEFT", 12, -55)
        editBg:SetPoint("BOTTOMRIGHT", -12, 45)
        CreateBackdrop(editBg, {0.04, 0.05, 0.07, 1}, nil)

        local scrollFrame = CreateFrame("ScrollFrame", "QUI_ExportPopupScroll", editBg, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 8, -8)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)
        StyleScrollBar(scrollFrame)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        ns.Helpers.ApplyFontWithFallback(editBox, GetFontPath(), 11, "")
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

        local selectBtn = self:CreateButton(popup, ns.L["Select All"], 100, 26, function()
            popup.editBox:SetFocus()
            popup.editBox:HighlightText()
        end)
        selectBtn:SetPoint("BOTTOMLEFT", 12, 10)

        local closeBtn = self:CreateButton(popup, ns.L["Close"], 80, 26, function()
            popup:Hide()
        end)
        closeBtn:SetPoint("BOTTOMRIGHT", -12, 10)

        UIKit.CreateCloseButton(popup, {
            size = 22,
            point = "TOPRIGHT", x = -6, y = -6,
            onClick = function() popup:Hide() end,
        })

        popup:Hide()
        ExportPopup = popup
    end

    ExportPopup.title:SetText(title or ns.L["Export"])
    ExportPopup.editBox:SetText(exportString or "")
    ExportPopup:Show()
    ExportPopup:Raise()
    ExportPopup.editBox:SetFocus()
    ExportPopup.editBox:HighlightText()
end

function GUI:Toggle()
    if self.MainFrame and self.MainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

local C = GUI.Colors
local Helpers = ns.Helpers

ns.QUI_Framework = ns.QUI_Framework or {}
local FW2 = ns.QUI_Framework

local SIDEBAR_SEARCH_RESERVE = 44
local SIDEBAR_TILE_HEIGHT = 26
local SIDEBAR_TILE_GAP = 2
local SIDEBAR_TOOLS_RESERVE = 96
local SIDEBAR_BOTTOM_GAP = 6
local SIDEBAR_SCROLLBAR_WIDTH = 4

local function SidebarScrollOffset(scroll)
    local getter = ns.GetSafeVerticalScroll
    return (getter and getter(scroll)) or 0
end

local function SidebarStackHeight(count)
    if count <= 0 then return 0 end
    return count * SIDEBAR_TILE_HEIGHT + (count - 1) * SIDEBAR_TILE_GAP
end

local function SidebarBottomInset(frame)
    local bottomCount = frame._bottomTiles and #frame._bottomTiles or 0
    if bottomCount > 0 then
        return SIDEBAR_TOOLS_RESERVE + SIDEBAR_BOTTOM_GAP
            + SidebarStackHeight(bottomCount) + SIDEBAR_BOTTOM_GAP
    end
    if frame._toolsStrip then
        return SIDEBAR_TOOLS_RESERVE + SIDEBAR_BOTTOM_GAP
    end
    return 10
end

local function UpdateSidebarScrollBounds(frame)
    local scroll = frame._sidebarScroll
    if not scroll then return end
    scroll:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", 0, SidebarBottomInset(frame))
    if frame._sidebarClampScroll then frame._sidebarClampScroll() end
end

local function EnsureSidebarScroll(frame)
    if frame._sidebarScroll then return frame._sidebarScrollChild end

    local sidebar = frame.sidebar

    local scroll = CreateFrame("ScrollFrame", nil, sidebar)
    scroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -SIDEBAR_SEARCH_RESERVE)
    scroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, SidebarBottomInset(frame))

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(sidebar:GetWidth() or GUI.SIDEBAR_WIDTH)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local scrollBar = CreateFrame("Frame", nil, sidebar)
    scrollBar:SetWidth(SIDEBAR_SCROLLBAR_WIDTH)
    scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -1, 0)
    scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -1, 0)
    scrollBar:Hide()

    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SIDEBAR_SCROLLBAR_WIDTH)
    thumb:SetColorTexture(C.scrollThumb[1], C.scrollThumb[2], C.scrollThumb[3], C.scrollThumb[4])

    local function UpdateThumb()
        local contentH = child:GetHeight()
        local frameH = scroll:GetHeight()
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
        local scrollCur = SidebarScrollOffset(scroll)
        local ratio = (scrollMax > 0) and (scrollCur / scrollMax) or 0
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", scrollBar, "TOP", 0, -ratio * (trackH - thumbH))
    end

    local function ClampScroll()
        local maxScroll = math.max(0, child:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(SidebarScrollOffset(scroll), maxScroll)))
        UpdateThumb()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = SidebarScrollOffset(self)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(
            math.max(0, math.min(currentScroll - (delta * (SIDEBAR_TILE_HEIGHT + SIDEBAR_TILE_GAP)), maxScroll)))
        UpdateThumb()
    end)
    scroll:SetScript("OnScrollRangeChanged", UpdateThumb)
    scroll:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w or GUI.SIDEBAR_WIDTH)
        ClampScroll()
    end)

    frame._sidebarScroll = scroll
    frame._sidebarScrollChild = child
    frame._sidebarUpdateThumb = UpdateThumb
    frame._sidebarClampScroll = ClampScroll

    return child
end

local function EnsureSidebarTileVisible(frame, tile)
    local scroll = frame._sidebarScroll
    if not scroll or not tile or not tile._sidebarSlot then return end
    if tile._sidebarBucket ~= "top" then return end

    local viewportH = scroll:GetHeight()
    if viewportH <= 0 then return end

    local tileTop = (tile._sidebarSlot - 1) * (SIDEBAR_TILE_HEIGHT + SIDEBAR_TILE_GAP)
    local tileBottom = tileTop + SIDEBAR_TILE_HEIGHT
    local maxScroll = math.max(0, frame._sidebarScrollChild:GetHeight() - viewportH)

    local cur = SidebarScrollOffset(scroll)

    local target = cur
    if tileTop < cur then
        target = tileTop
    elseif tileBottom > cur + viewportH then
        target = tileBottom - viewportH
    end

    target = math.max(0, math.min(target, maxScroll))
    scroll:SetVerticalScroll(target)
    if frame._sidebarUpdateThumb then frame._sidebarUpdateThumb() end
end

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

    local tileParent = config.isBottomItem and frame.sidebar or EnsureSidebarScroll(frame)
    local tile = CreateFrame("Button", nil, tileParent)
    tile:SetHeight(SIDEBAR_TILE_HEIGHT)
    tile.index = index
    tile.id = config.id
    tile.config = config
    tile._sidebarSlot = bucketIndex
    tile._sidebarBucket = config.isBottomItem and "bottom" or "top"

    if config.isBottomItem then
        if bucketIndex == 1 then
            local inset = SIDEBAR_TOOLS_RESERVE + SIDEBAR_BOTTOM_GAP
            tile:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMLEFT", 6, inset)
            tile:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", -6, inset)
        else
            local prev = bucket[bucketIndex - 1]
            tile:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, SIDEBAR_TILE_GAP)
            tile:SetPoint("BOTTOMRIGHT", prev, "TOPRIGHT", 0, SIDEBAR_TILE_GAP)
        end
    else
        if bucketIndex == 1 then
            tile:SetPoint("TOPLEFT", tileParent, "TOPLEFT", 6, 0)
            tile:SetPoint("TOPRIGHT", tileParent, "TOPRIGHT", -6, 0)
        else
            local prev = bucket[bucketIndex - 1]
            tile:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -SIDEBAR_TILE_GAP)
            tile:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -SIDEBAR_TILE_GAP)
        end
    end
    bucket[bucketIndex] = tile

    if config.isBottomItem then
        UpdateSidebarScrollBounds(frame)
    else
        frame._sidebarScrollChild:SetHeight(math.max(1, SidebarStackHeight(bucketIndex)))
        if frame._sidebarClampScroll then frame._sidebarClampScroll() end
    end

    tile.indicator = tile:CreateTexture(nil, "OVERLAY")
    tile.indicator:SetPoint("TOPLEFT", 0, 0)
    tile.indicator:SetPoint("BOTTOMLEFT", 0, 0)
    tile.indicator:SetWidth(3)
    tile.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    tile.indicator:Hide()

    tile.hoverBg = tile:CreateTexture(nil, "BACKGROUND")
    tile.hoverBg:SetAllPoints()
    tile.hoverBg:SetColorTexture(1, 1, 1, 0.03)
    tile.hoverBg:Hide()

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

    tile.text = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    do
        local curFont = tile.text:GetFont()
        if Helpers and Helpers.ApplyFontWithFallback then
            Helpers.ApplyFontWithFallback(tile.text, curFont, 11, "")
        else
            tile.text:SetFont(curFont, 11)
        end
    end
    tile.text:SetText(config.name)
    tile.text:SetPoint("LEFT", tile, "LEFT", textX, 0)
    tile.text:SetPoint("RIGHT", tile, "RIGHT", config.moduleFeatureId and -44 or -10, 0)
    tile.text:SetJustifyH("LEFT")
    tile.text:SetWordWrap(false)
    tile.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 1)

    if config.moduleFeatureId then
        local settings = ns.Settings
        local registry = settings and settings.Registry
        local feature = registry and type(registry.GetFeature) == "function"
            and registry:GetFeature(config.moduleFeatureId)
        local entry = feature and feature.moduleEntry
        local modulesPage = ns.QUI_ModulesPage
        if type(entry) == "table" and modulesPage
            and type(modulesPage.CreateModuleTogglePill) == "function" then
            tile.moduleToggle = modulesPage.CreateModuleTogglePill(
                tile, config.moduleFeatureId, entry)
            tile.moduleToggle:SetPoint("RIGHT", tile, "RIGHT", -8, 1)
        end
    end

    frame._tiles[index] = tile

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

local function installRegisterSection(targetBody)
    targetBody._sections = {}
    function targetBody:RegisterSection(id, label, frame)
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
end

function GUI:BuildTilePage(frame, tile)
    if not tile or tile._built then return end

    if not frame._tileContent then
        frame._tileContent = CreateFrame("Frame", nil, frame.contentArea)
        frame._tileContent:SetAllPoints(frame.contentArea)
    end
    local content = frame._tileContent

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
    ns.Helpers.ApplyFontWithFallback(crumb, fpath or select(1, crumb:GetFont()), 10, "")
    crumb:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    crumb:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    crumb:SetText(ns.L["Settings"] .. "  >  " .. (tile.config.name or ""))
    tile._crumb = crumb

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ns.Helpers.ApplyFontWithFallback(title, fpath or select(1, title:GetFont()), 15, "")
    title:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    title:SetPoint("TOPLEFT", crumb, "BOTTOMLEFT", 0, -4)
    title:SetText(tile.config.name or "")
    tile._title = title

    if tile.config.subtitle and tile.config.subtitle ~= "" then
        local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ns.Helpers.ApplyFontWithFallback(subtitle, fpath or select(1, subtitle:GetFont()), 11, "")
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

        installRegisterSection(body)

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
                if GUI and GUI.Hide then GUI:Hide() end
                if _G.QUI_OpenLayoutMode then _G.QUI_OpenLayoutMode() end
                if moverKey ~= "" and _G.QUI_LayoutModeSelectMover then
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

        if entry.navType and entry.navType ~= "alias" and entry.navType ~= "moduleToggle" then
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

    if not (opts and opts.searchEntry) and frame._searchBox and frame._searchBox.editBox then
        local box = frame._searchBox.editBox
        if box:GetText() ~= "" then
            box:SetText("")
            box:ClearFocus()
        end
    end

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

    EnsureSidebarTileVisible(frame, tile)

    GUI:BuildTilePage(frame, tile)

    local content = frame._tileContent
    if content then content:Show() end
    if frame._searchResultsArea then frame._searchResultsArea:Hide() end

    for _, t in ipairs(frame._tiles) do
        if t._pageFrame and t ~= tile then t._pageFrame:Hide() end
    end
    tile._pageFrame:Show()

    if frame._tiles then
        for _, t in ipairs(frame._tiles) do
            if t._primaryBtn then t._primaryBtn:Hide() end
        end
    end
    if tile._primaryBtn then tile._primaryBtn:Show() end

    if opts and opts.subPageIndex and tile._subPageSelect then
        tile._subPageSelect(opts.subPageIndex)
    end

    if opts and type(opts.searchEntry) == "table" then
        self:ApplyFeatureSearchNavigation(tile, opts.searchEntry, opts)
    end

    if opts and (opts.scrollToPath or opts.scrollToLabel or opts.scrollToFeatureId) then
        C_Timer.After(0, function()
            local root = opts.searchRoot or tile._pageFrame
            local scrolledToSection = false

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
                            scroll:SetVerticalScroll(offset)
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
                if not scrolledToSection then
                    local scroll = GUI:_findAncestorScroll(target)
                    if scroll then
                        local scrollChild = scroll.GetScrollChild and scroll:GetScrollChild() or nil
                        local bodyTop = scrollChild and scrollChild.GetTop and scrollChild:GetTop() or nil
                        local widgetTop = target.GetTop and target:GetTop() or nil
                        if bodyTop and widgetTop and scroll.SetVerticalScroll then
                            local offset = math.max(0, bodyTop - widgetTop - 50)
                            scroll:SetVerticalScroll(offset)
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
        GUI:EnsureSearchCacheLoaded()
        frame._searchResultsArea = frame._searchResultsArea or GUI:_CreateV2SearchResultsArea(frame)
        frame._searchResultsArea:Show()
        if frame._tileContent then frame._tileContent:Hide() end
        local results, navResults = GUI:ExecuteSearch(text)
        GUI:RenderSearchResults(frame._searchResultsArea.inner, results, text, navResults)
    end
    box.onClear = function()
        if frame._searchResultsArea then frame._searchResultsArea:Hide() end
        if frame._tileContent then frame._tileContent:Show() end
    end

    if box._editBox and box._editBox.HookScript then
        box._editBox:HookScript("OnEditFocusGained", function()
            GUI:EnsureSearchCacheLoaded()
        end)
    end

    frame._searchBox = box
    return box
end

function GUI:_CreateV2SearchResultsArea(frame)
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

function GUI:RenderSubPageTabs(tile, contentArea, subPages, onSelect, headerFrame)
    if not subPages or #subPages == 0 then return end

    local single = #subPages == 1

    local bar
    if not single then
        bar = CreateFrame("Frame", nil, contentArea)
        if headerFrame then
            bar:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -8)
            bar:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -8)
        else
            bar:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 18, -70)
            bar:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -18, -70)
        end
        bar:SetHeight(28)

        local underline = bar:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", 0, 0)
        underline:SetHeight(1)
        underline:SetColorTexture(C.border[1], C.border[2], C.border[3], C.border[4])
    end

    local body = CreateFrame("Frame", nil, contentArea)
    local footerReserve = tile and tile.config and tile.config.relatedSettings and 32 or 0
    if single then
        if headerFrame then
            body:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", -18, -10)
        else
            body:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, -70)
        end
    else
        body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -18, -8)
    end
    body:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, footerReserve)

    local tabs = {}
    local currentIndex = 1

    tile._subPageBodies = tile._subPageBodies or {}

    local function RunOnSelect(sp, contentBody)
        return onSelect(sp, contentBody)
    end

    local select

    local function BuildSubPageBody(i)
        if tile._subPageBodies[i] then
            return tile._subPageBodies[i]
        end

        local sp = subPages[i]
        if not sp then
            return nil
        end

        local container = CreateFrame("Frame", nil, body)
        container:SetAllPoints(body)
        container:Hide()
        tile._subPageBodies[i] = container

        local contentRoot = container
        if sp.preview and type(sp.preview.build) == "function" then
            local preview = CreateFrame("Frame", nil, container)
            preview:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            preview:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            preview:SetHeight(sp.preview.height or 90)
            sp.preview.build(preview)
            container._preview = preview

            contentRoot = CreateFrame("Frame", nil, container)
            contentRoot:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)
            contentRoot:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        end

        local scrollFrame, contentBody
        if sp.noScroll then
            contentBody = contentRoot
            installRegisterSection(contentBody)
            RunOnSelect(sp, contentBody)
        elseif ns.QUI_Options and ns.QUI_Options.CreateScrollableContent then
            scrollFrame, contentBody = ns.QUI_Options.CreateScrollableContent(contentRoot)
            installRegisterSection(contentBody)
            RunOnSelect(sp, contentBody)
        else
            contentBody = contentRoot
            installRegisterSection(contentBody)
            RunOnSelect(sp, contentBody)
        end

        container._contentRoot = contentRoot
        container._scrollFrame = scrollFrame
        container._contentBody = contentBody

        if sp.sectionNav and scrollFrame and #contentBody._sections >= 2 then
            local function tryBuildSectionNav()
                if container._sectionNav then return end
                local bodyH = contentBody:GetHeight() or 0
                local viewH = scrollFrame:GetHeight() or 0
                if bodyH > viewH and viewH > 0 then
                    container._sectionNav = GUI:RenderSectionNav(scrollFrame, contentBody, contentBody._sections)
                end
            end

            tryBuildSectionNav()
            C_Timer.After(0, tryBuildSectionNav)

            contentBody:HookScript("OnSizeChanged", function()
                if not container._sectionNav then
                    C_Timer.After(0, tryBuildSectionNav)
                end
            end)
        end

        return container
    end

    local function RunSubPageTabClick(i)
        return select(i)
    end

    select = function(i)
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
            local crumbText = ns.L["Settings"] .. "  >  " .. (tile.config.name or "")
            if tile.config.subPages and tile.config.subPages[i] and tile.config.subPages[i].name then
                crumbText = crumbText .. "  >  " .. tile.config.subPages[i].name
            end
            tile._crumb:SetText(crumbText)
        end

        for _, sub in pairs(tile._subPageBodies) do
            sub:Hide()
        end

        BuildSubPageBody(i)

        tile._subPageBodies[i]:Show()
    end

    local ROW_HEIGHT = 28
    local TAB_GAP_X = 16
    local TAB_GAP_Y = 4

    if not single then
        for i, sp in ipairs(subPages) do
            local btn = CreateFrame("Button", nil, bar)
            btn:SetHeight(ROW_HEIGHT)

            btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.label:SetText(sp.name)
            btn.label:SetPoint("CENTER", 0, 0)
            local f, _, fl = btn.label:GetFont()
            ns.Helpers.ApplyFontWithFallback(btn.label, f or (ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(GUI:GetFontPath())) or f, 11, fl or "")

            local labelW = btn.label:GetStringWidth() + 24
            btn:SetWidth(labelW)

            btn.activeBar = btn:CreateTexture(nil, "OVERLAY")
            btn.activeBar:SetPoint("BOTTOMLEFT", 4, 0)
            btn.activeBar:SetPoint("BOTTOMRIGHT", -4, 0)
            btn.activeBar:SetHeight(2)
            btn.activeBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            btn.activeBar:Hide()

            btn:SetScript("OnClick", function() RunSubPageTabClick(i) end)

            tabs[i] = btn
        end

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
    end

    tile._subPageSelect = select
    select(1)

    return body, select
end

function GUI:RenderSectionNav(scrollFrame, body, sections, options)
    options = options or {}
    if type(sections) ~= "table" or #sections < 2 then return nil end
    if not scrollFrame or not body then return nil end

    local C = self.Colors or {}
    local accent = C.accent or { 0.204, 0.827, 0.6, 1 }
    local tabNormal = C.tabNormal or { 1, 1, 1, 0.55 }
    local tabHover = C.tabHover or { 1, 1, 1, 0.85 }
    local tabSelectedText = C.tabSelectedText or { 1, 1, 1, 1 }
    local CHIP_HEIGHT = 22
    local CHIP_PAD_X = 10
    local CHIP_GAP_X = 8
    local CHIP_GAP_Y = 6
    local STRIP_PAD_TOP = 4
    local STRIP_PAD_BOTTOM = 4
    local ACTIVE_THRESHOLD = 12
    local TWEEN_DURATION = 0.12

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
            chips[activeIdx].label:SetTextColor(tabNormal[1], tabNormal[2], tabNormal[3], tabNormal[4])
            chips[activeIdx].underline:Hide()
        end
        if idx and chips[idx] then
            chips[idx].label:SetTextColor(tabSelectedText[1], tabSelectedText[2], tabSelectedText[3], tabSelectedText[4])
            chips[idx].underline:Show()
        end
        activeIdx = idx
    end

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
        ns.Helpers.ApplyFontWithFallback(label, f or (ns.UIKit and ns.UIKit.ResolveFontPath and ns.UIKit.ResolveFontPath(self:GetFontPath())) or f, 11, fl or "")
        label:SetPoint("LEFT", CHIP_PAD_X, 0)
        label:SetTextColor(tabNormal[1], tabNormal[2], tabNormal[3], tabNormal[4])
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

        chip:SetScript("OnEnter", function()
            hover:Show()
            if activeIdx ~= i then
                label:SetTextColor(tabHover[1], tabHover[2], tabHover[3], tabHover[4])
            end
        end)
        chip:SetScript("OnLeave", function()
            hover:Hide()
            if activeIdx ~= i then
                label:SetTextColor(tabNormal[1], tabNormal[2], tabNormal[3], tabNormal[4])
            end
        end)

        chips[i] = chip
    end

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

        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", stripParent, "TOPLEFT", 5, -5 - stripH)
        scrollFrame:SetPoint("BOTTOMRIGHT", stripParent, "BOTTOMRIGHT", -28, 5)
    end

    strip:SetScript("OnSizeChanged", function() relayoutChips() end)

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

function GUI:AddToolsStripButton(frame, config)
    assert(type(config) == "table", "AddToolsStripButton: config required")
    assert(config.id, "config.id required")
    assert(config.label, "config.label required")
    assert(type(config.onClick) == "function", "config.onClick required")

    frame._tools = frame._tools or {}

    if not frame._toolsStrip then
        local strip = CreateFrame("Frame", nil, frame.sidebar)
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
        heading:SetText(ns.L["TOOLS"])
        heading:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3], 0.5)

        frame._toolsStrip = strip
        UpdateSidebarScrollBounds(frame)
    end

    local strip = frame._toolsStrip
    local idx = #frame._tools + 1

    local btn = CreateFrame("Button", nil, strip, "BackdropTemplate")
    btn:SetHeight(24)
    local yOffset = -20 - (idx - 1) * 26
    btn:SetPoint("TOPLEFT", strip, "TOPLEFT", 4, yOffset)
    btn:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -4, yOffset)

    QUICore.SafeSetBackdrop(btn, {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = QUICore:GetPixelSize(btn),
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

GUI._navMap = GUI._navMap or {}

function GUI:RegisterV2NavRoute(tabIndex, subTabIndex, tileId, subPageIndex)
    local key = (tabIndex or 0) .. ":" .. (subTabIndex or 0)
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
            return directRoute
        elseif not self:IsSearchRouteCompatible(directRoute, entry) then
            directRoute = nil
        else
            return directRoute
        end
    end

    if exactRoute then
        return exactRoute
    end

    if fallbackRoute then
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

    local ok, handled = ns.SafeCall("bulkhead", feature.searchNavigate, entry, {
        tile = tile,
        pageFrame = tile._pageFrame,
        opts = opts,
    })
    return ok and handled ~= false
end

function GUI:GetV2Breadcrumb(tabIndex, subTabIndex, sectionName)
    local frame = self.MainFrame
    if not frame then return nil end

    local route = self:ResolveV2Navigation(tabIndex, subTabIndex)

    if not route and tabIndex and GUI._navMap then
        local prefix = tabIndex .. ":"
        for key, mapping in pairs(GUI._navMap) do
            if key:sub(1, #prefix) == prefix then
                route = { tileId = mapping.tileId }
                break
            end
        end
    end

    local tile = route and self:FindV2TileByID(frame, route.tileId)

    if not tile then
        local parts = { ns.L["Settings"] }
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
    local ag = pulse._anim
    if not ag then
        ag = pulse:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.1); fadeIn:SetOrder(1)
        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(0.2); hold:SetOrder(2)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.3); fadeOut:SetOrder(3)
        pulse._anim = ag
    end
    ag:Stop()
    ag:Play()
end

local function FindInFrameTree(root, matchSelf)
    if not root then return nil end
    local self = matchSelf(root)
    if self then return self end
    local n = root.GetNumChildren and root:GetNumChildren() or 0
    for i = 1, n do
        local child = select(i, root:GetChildren())
        if child then
            local match = FindInFrameTree(child, matchSelf)
            if match then return match end
        end
    end
    return nil
end

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
    return FindInFrameTree(root, function(node)
        local binding = node._quiPinBinding
        if type(binding) == "table" and binding.path == path then
            return node
        end
        return nil
    end)
end

function GUI:_findAncestorScroll(frame)
    local p = frame and frame.GetParent and frame:GetParent()
    while p do
        if p.GetObjectType and p:GetObjectType() == "ScrollFrame" then return p end
        p = p.GetParent and p:GetParent() or nil
    end
end

function GUI:_findSectionByFeatureId(root, featureId)
    if not root or type(featureId) ~= "string" or featureId == "" then
        return nil
    end
    return FindInFrameTree(root, function(node)
        if node._quiSearchSectionFeatureId == featureId then
            return node
        end
        return nil
    end)
end

function GUI:FocusSearchBox()
    local frame = self.MainFrame
    if not frame or not frame._searchBox then return end
    self:EnsureSearchCacheLoaded()
    local box = frame._searchBox.editBox or frame._searchBox
    if box and box.SetFocus then
        box:SetFocus()
        if box.HighlightText then box:HighlightText() end
    end
end

function GUI:OnFontChanged()
    if not self.MainFrame or not self.MainFrame:IsShown() then return end
    self:RefreshAccentColor()
end

QUI.GUI = GUI
