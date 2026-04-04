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
    bg = {0.067, 0.094, 0.153, 0.97},         -- #111827 Deep Cool Grey
    bgLight = {0.122, 0.161, 0.216, 1},       -- #1F2937 Dark Slate (inactive tabs)
    bgDark = {0.04, 0.06, 0.1, 1},            -- Even darker for contrast
    bgContent = {0.122, 0.161, 0.216, 0.5},   -- #1F2937 with alpha
    
    -- Accent colors (Mint)
    accent = {0.204, 0.827, 0.6, 1},          -- #34D399 Soft Mint (active border)
    accentLight = {0.431, 0.906, 0.718, 1},   -- #6EE7B7 Lighter Mint (headers)
    accentDark = {0.1, 0.5, 0.35, 1},
    accentHover = {0.3, 0.9, 0.65, 1},
    
    -- Tab colors
    tabSelected = {0.204, 0.827, 0.6, 1},     -- #34D399 Soft Mint
    tabSelectedText = {0.067, 0.094, 0.153, 1}, -- Dark text on selected
    tabNormal = {0.7, 0.75, 0.78, 1},         -- Slightly cool grey
    tabHover = {0.95, 0.96, 0.96, 1},
    
    -- Text colors
    text = {0.953, 0.957, 0.965, 1},          -- #F3F4F6 Off-White
    textBright = {1, 1, 1, 1},
    textMuted = {0.6, 0.65, 0.7, 1},
    
    -- Borders
    border = {0.2, 0.25, 0.3, 1},
    borderLight = {0.3, 0.35, 0.4, 1},
    borderAccent = {0.204, 0.827, 0.6, 1},    -- #34D399 Mint border
    
    -- Section headers
    sectionHeader = {0.431, 0.906, 0.718, 1}, -- #6EE7B7 Lighter Mint

    -- Slider colors (Premium redesign)
    sliderTrack = {0.15, 0.17, 0.22, 1},       -- Slightly lighter track background
    sliderThumb = {1, 1, 1, 1},                -- White thumb
    sliderThumbBorder = {0.3, 0.35, 0.4, 1},   -- Subtle border on thumb

    -- Toggle switch colors
    toggleOff = {0.176, 0.216, 0.282, 1},      -- #2D3748 Dark grey track
    toggleThumb = {1, 1, 1, 1},                -- White circle

    -- Warning/secondary accent
    warning = {0.961, 0.620, 0.043, 1},        -- #F59E0B Amber
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
-- ACCENT COLOR - Derive theme colors from a base accent color
---------------------------------------------------------------------------
function GUI:ApplyAccentColor(r, g, b)
    local function lerp(a, b, t) return a + (b - a) * t end
    -- Update in-place to preserve existing table references
    C.accent[1], C.accent[2], C.accent[3], C.accent[4] = r, g, b, 1
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
GUI.SettingsRegistry = {}

-- Navigation Registry for searchable categories, subtabs, and sections
-- Allows users to search for tab names, subtab names, and section names directly
GUI.NavigationRegistry = {}
GUI.NavigationRegistryKeys = {}  -- Deduplication keys

-- Search context (auto-populated by page builders)
GUI._searchContext = {
    tabIndex = nil,
    tabName = nil,
    subTabIndex = nil,
    subTabName = nil,
    sectionName = nil,
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
GUI.SectionNavigateHandlers = {}

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

    local builders = ns.SettingsBuilders
    if not builders or type(builders.NotifyProviderChanged) ~= "function" then return end

    local providerOptions = widget._providerSyncOptions or {}
    local structural = options and options.structural
    if structural == nil then
        if providerOptions.structural ~= nil then
            structural = providerOptions.structural == true
        else
            structural = not (widget._syncDBTable and widget._syncDBKey)
        end
    end

    builders.NotifyProviderChanged(context.providerKey, {
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

-- Set search context for auto-registration (call at start of page builder)
function GUI:SetSearchContext(info)
    self._searchContext.tabIndex = info.tabIndex
    self._searchContext.tabName = info.tabName
    self._searchContext.subTabIndex = info.subTabIndex or nil
    self._searchContext.subTabName = info.subTabName or nil
    self._searchContext.sectionName = info.sectionName or nil

    -- Auto-register navigation items for tabs and subtabs
    if info.tabIndex and info.tabName then
        self:RegisterNavigationItem("tab", info)
        if info.subTabIndex and info.subTabName then
            self:RegisterNavigationItem("subtab", info)
        end
    end
end

-- Set current section (call when entering a new section within a page)
function GUI:SetSearchSection(sectionName)
    self._searchContext.sectionName = sectionName

    -- Auto-register section as navigation item
    if sectionName and sectionName ~= "" and self._searchContext.tabIndex then
        self:RegisterNavigationItem("section", {
            tabIndex = self._searchContext.tabIndex,
            tabName = self._searchContext.tabName,
            subTabIndex = self._searchContext.subTabIndex,
            subTabName = self._searchContext.subTabName,
            sectionName = sectionName,
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
    }
end

local function GetSectionRegistryKey(tabIndex, subTabIndex)
    return (tabIndex or 0) * 10000 + (subTabIndex or 0)
end

function GUI:RegisterSectionNavigateHandler(tabIndex, subTabIndex, sectionName, handler)
    if not tabIndex or not subTabIndex or not sectionName or sectionName == "" then return end
    if type(handler) ~= "function" then return end
    local key = GetSectionRegistryKey(tabIndex, subTabIndex)
    self.SectionNavigateHandlers[key] = self.SectionNavigateHandlers[key] or {}
    self.SectionNavigateHandlers[key][sectionName] = handler
end

function GUI:RunSectionNavigateHandler(tabIndex, subTabIndex, sectionName)
    if not tabIndex or not subTabIndex or not sectionName or sectionName == "" then return false end
    local key = GetSectionRegistryKey(tabIndex, subTabIndex)
    local handlers = self.SectionNavigateHandlers[key]
    local handler = handlers and handlers[sectionName]
    if type(handler) ~= "function" then return false end
    local ok, handled = pcall(handler)
    if not ok then return false end
    return handled ~= false
end

function GUI:GetOrderedSections(tabIndex, subTabIndex)
    local key = GetSectionRegistryKey(tabIndex, subTabIndex)
    local order = self.SectionRegistryOrder[key] or {}
    local registry = self.SectionRegistry[key] or {}
    local out = {}
    for _, sectionName in ipairs(order) do
        if registry[sectionName] then
            table.insert(out, sectionName)
        end
    end
    return out
end

function GUI:ScrollToSection(tabIndex, subTabIndex, sectionName)
    if not tabIndex or not sectionName or sectionName == "" then return false end
    local key = GetSectionRegistryKey(tabIndex, subTabIndex or 0)
    local subReg = self.SectionRegistry[key]
    local sectionInfo = subReg and subReg[sectionName]
    if not sectionInfo or not sectionInfo.scrollParent or not sectionInfo.frame then
        return false
    end

    local scrollFrame = sectionInfo.scrollParent
    local sectionFrame = sectionInfo.frame
    local contentParent = sectionInfo.contentParent
    if not contentParent or not sectionFrame:IsVisible() then
        return false
    end

    local sectionTop = sectionFrame:GetTop()
    local contentTop = contentParent:GetTop()
    if not sectionTop or not contentTop then
        return false
    end

    local sectionOffset = contentTop - sectionTop
    local scrollPos = math.max(0, sectionOffset - 20)
    local maxScroll = (type(ns.GetSafeVerticalScrollRange) == "function")
        and ns.GetSafeVerticalScrollRange(scrollFrame)
        or 0
    scrollPos = math.min(scrollPos, maxScroll)
    scrollFrame:SetVerticalScroll(scrollPos)
    return true
end

function GUI:NavigateTo(tabIndex, subTabIndex, sectionName)
    local frame = self.MainFrame
    if not frame then return end
    if not tabIndex then return end
    local hasSectionTarget = (sectionName and sectionName ~= "" and subTabIndex)

    frame._sidebarExpandedTabs = frame._sidebarExpandedTabs or {}
    frame._sidebarExpandedSubTabs = frame._sidebarExpandedSubTabs or {}
    frame._sidebarExpandedTabs[tabIndex] = true
    if subTabIndex then
        frame._sidebarExpandedSubTabs[tabIndex] = frame._sidebarExpandedSubTabs[tabIndex] or {}
        frame._sidebarExpandedSubTabs[tabIndex][subTabIndex] = true
    end
    if hasSectionTarget then
        frame._sidebarActiveSectionKey = tabIndex .. ":" .. subTabIndex .. ":" .. sectionName
    else
        frame._sidebarActiveSectionKey = nil
    end
    frame._sidebarPendingSectionSelection = hasSectionTarget and true or nil

    self:SelectTab(frame, tabIndex)

    if subTabIndex then
        C_Timer.After(0, function()
            if not self.MainFrame then return end
            local page = frame.pages and frame.pages[tabIndex]
            if page and page._subTabGroup and page._subTabGroup.SelectTab then
                page._subTabGroup.SelectTab(subTabIndex)
            end
            if sectionName and sectionName ~= "" then
                local handled = self:RunSectionNavigateHandler(tabIndex, subTabIndex, sectionName)
                if handled then
                    frame._sidebarPendingSectionSelection = nil
                else
                    C_Timer.After(0.05, function()
                        self:ScrollToSection(tabIndex, subTabIndex, sectionName)
                        frame._sidebarPendingSectionSelection = nil
                    end)
                end
            else
                frame._sidebarPendingSectionSelection = nil
            end
        end)
    elseif sectionName and sectionName ~= "" then
        C_Timer.After(0.05, function()
            self:ScrollToSection(tabIndex, 0, sectionName)
            frame._sidebarPendingSectionSelection = nil
        end)
    else
        frame._sidebarPendingSectionSelection = nil
    end
end

function GUI:UpdateSidebarSectionHighlightFromScroll(scrollFrame)
    local frame = self.MainFrame
    if not frame or not scrollFrame then return end
    if frame._sidebarPendingSectionSelection then return end
    if frame._sidebarManualSectionSelection then return end

    local tabIndex = frame.activeTab
    if not tabIndex then return end
    local page = frame.pages and frame.pages[tabIndex]
    local subTabIndex = page and page._subTabGroup and page._subTabGroup.selectedTab
    if not subTabIndex then return end

    local key = GetSectionRegistryKey(tabIndex, subTabIndex)
    local order = self.SectionRegistryOrder[key]
    local registry = self.SectionRegistry[key]
    if not order or #order == 0 or not registry then return end

    local currentScroll = scrollFrame:GetVerticalScroll() or 0

    -- At the top — no section should be highlighted
    if currentScroll <= 5 then
        if frame._sidebarActiveSectionKey then
            frame._sidebarActiveSectionKey = nil
            self:RefreshSidebarTree(frame)
        end
        return
    end

    local threshold = currentScroll + 28
    local activeName
    local bestOffset = -math.huge

    for _, sectionName in ipairs(order) do
        local info = registry[sectionName]
        if info and info.scrollParent == scrollFrame and info.frame and info.contentParent and info.frame:IsVisible() then
            local sectionTop = info.frame:GetTop()
            local contentTop = info.contentParent:GetTop()
            if sectionTop and contentTop then
                local sectionOffset = contentTop - sectionTop
                if sectionOffset <= threshold and sectionOffset > bestOffset then
                    bestOffset = sectionOffset
                    activeName = sectionName
                end
            end
        end
    end

    if not activeName then
        for _, sectionName in ipairs(order) do
            local info = registry[sectionName]
            if info and info.scrollParent == scrollFrame then
                activeName = sectionName
                break
            end
        end
    end

    if activeName then
        local nextKey = tabIndex .. ":" .. subTabIndex .. ":" .. activeName
        if frame._sidebarActiveSectionKey ~= nextKey then
            frame._sidebarActiveSectionKey = nextKey
            self:RefreshSidebarTree(frame)
        end
    end
end

function GUI:AttachSidebarSectionScrollSpy(scrollFrame)
    if not scrollFrame or scrollFrame._quiSidebarSectionSpyHooked then return end
    scrollFrame._quiSidebarSectionSpyHooked = true
    scrollFrame:HookScript("OnVerticalScroll", function(self)
        local now = (type(GetTime) == "function") and GetTime() or 0
        local last = self._quiSidebarSectionSpyLast or 0
        if now - last < 0.05 then return end
        self._quiSidebarSectionSpyLast = now
        GUI:UpdateSidebarSectionHighlightFromScroll(self)
    end)
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
    elseif navType == "section" then
        -- Section keys include a string name; keep string concat
        regKey = info.tabIndex * 100000 + (info.subTabIndex or 0) + 50000
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
        keywords = keywords,
    }

    table.insert(self.NavigationRegistry, entry)
end

-- Flag to track if search index has been built
GUI._searchIndexBuilt = false
GUI._searchIndexProgress = 0   -- Number of tabs indexed so far
GUI._searchIndexTotal = 0      -- Total tabs to index
GUI._searchIndexTicker = nil   -- Background ticker reference

-- Build a single tab's search index (creates hidden frame, runs builder).
-- Returns true if a tab was built, false if nothing left to build.
function GUI:BuildNextTabIndex()
    local frame = self.MainFrame
    if not frame or not frame.pages then return false end

    -- Initialize registry if needed
    if not self.SettingsRegistry then self.SettingsRegistry = {} end
    if not self.SettingsRegistryKeys then self.SettingsRegistryKeys = {} end

    -- Find the next unbuilt tab
    for tabIndex, page in pairs(frame.pages) do
        if tabIndex ~= self._searchTabIndex then
            if page and page.createFunc and not page.built then
                -- Create hidden frame if needed
                if not page.frame then
                    page.frame = CreateFrame("Frame", nil, frame.contentArea)
                    page.frame:SetAllPoints()
                    page.frame:EnableMouse(false)
                end
                page.frame:Hide()

                -- Run the builder to register widgets
                local loadTab = frame.tabs[tabIndex]
                if loadTab and loadTab.name then
                    self:SetSearchContext({
                        tabIndex = tabIndex,
                        tabName = loadTab.name,
                    })
                end
                page.createFunc(page.frame)
                page.built = true

                -- Capture sub-tab group created during page build
                if GUI._lastSubTabGroup then
                    page._subTabGroup = GUI._lastSubTabGroup
                    page._subTabDefs = page._subTabGroup.subTabDefs
                    GUI._lastSubTabGroup = nil
                end

                self._searchIndexProgress = self._searchIndexProgress + 1
                return true  -- Built one tab this tick
            end
        end
    end

    return false  -- Nothing left to build
end

-- Start background incremental index building (1 tab per tick).
-- Called once after all tabs have been added to the options panel.
function GUI:StartBackgroundIndexBuild()
    if self._searchIndexBuilt then return end
    if self._searchIndexTicker then return end  -- Already running

    local frame = self.MainFrame
    if not frame or not frame.pages then return end

    -- Count total tabs that need building
    local total = 0
    for tabIndex, page in pairs(frame.pages) do
        if tabIndex ~= self._searchTabIndex and page and page.createFunc and not page.built then
            total = total + 1
        end
    end
    self._searchIndexTotal = total
    self._searchIndexProgress = 0

    if total == 0 then
        self._searchIndexBuilt = true
        return
    end

    -- Build one tab per tick using chained C_Timer.NewTimer(0) so each
    -- handle is cancellable and only one tab builds per frame.
    local function BuildNextTick()
        -- Abort if panel was destroyed/rebuilt
        if not self.MainFrame or self.MainFrame ~= frame then
            self._searchIndexTicker = nil
            return
        end

        local built = self:BuildNextTabIndex()
        if built then
            -- Schedule next tab for next frame
            self._searchIndexTicker = C_Timer.NewTimer(0, BuildNextTick)
        else
            -- All done
            self._searchIndexBuilt = true
            self._searchIndexTicker = nil
        end
    end

    -- Start after a short delay so login/reload UI work completes first
    self._searchIndexTicker = C_Timer.NewTimer(0.5, BuildNextTick)
end

-- Force-complete any remaining unbuilt tabs synchronously.
-- Only called as a fallback if user opens Search before background build finishes.
function GUI:ForceLoadAllTabs()
    -- Cancel background builder if running
    if self._searchIndexTicker then
        self._searchIndexTicker:Cancel()
        self._searchIndexTicker = nil
    end

    local frame = self.MainFrame
    if not frame or not frame.pages then return end
    if not self.SettingsRegistry then self.SettingsRegistry = {} end
    if not self.SettingsRegistryKeys then self.SettingsRegistryKeys = {} end

    while self:BuildNextTabIndex() do end  -- Build all remaining

    self._searchIndexBuilt = true
end

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
-- WIDGET: THEMED BUTTON (Neutral style - accent border on hover only)
---------------------------------------------------------------------------
function GUI:CreateButton(parent, text, width, height, onClick)
    local UIKit = ns.UIKit
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines

    local btn = CreateFrame("Button", nil, parent, useUIKitBorders and nil or "BackdropTemplate")
    btn:SetSize(width or 120, height or 26)
    if useUIKitBorders then
        btn.bg = UIKit.CreateBackground(btn, 0.15, 0.15, 0.15, 1)
        UIKit.CreateBorderLines(btn)
        UIKit.UpdateBorderLines(btn, 1, C.border[1], C.border[2], C.border[3], 1, false)
    else
        -- Normal state: dark background with grey border (neutral)
        local px = QUICore:GetPixelSize(btn)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end

    -- Button text (off-white, not accent)
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetFont(GetFontPath(), 12, "")
    btnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(text or "Button")
    btn.text = btnText

    local function SetButtonBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(btn, 1, r, g, b, a or 1, false)
        else
            pcall(btn.SetBackdropBorderColor, btn, r, g, b, a or 1)
        end
    end

    -- Hover effect: accent border only (no background change)
    btn:SetScript("OnEnter", function()
        SetButtonBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)

    btn:SetScript("OnLeave", function()
        SetButtonBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)

    -- Click handler
    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    -- Method to update text
    function btn:SetText(newText)
        btnText:SetText(newText)
    end

    -- Public method for callers that need custom hover colors.
    function btn:SetBorderColor(r, g, b, a)
        SetButtonBorderColor(r, g, b, a)
    end

    -- Backward-compatible alias used by some option tabs.
    btn.SetFieldBorderColor = btn.SetBorderColor

    return btn
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

    -- Show and enable keyboard
    confirmDialog:Show()
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
                if scrollParent then
                    GUI:AttachSidebarSectionScrollSpy(scrollParent)
                end
            end
        end
    end

    return container
end

---------------------------------------------------------------------------
-- WIDGET: SECTION BOX (Bordered group like old GUI)
-- Auto-calculates height based on content added via box:AddElement()
---------------------------------------------------------------------------
function GUI:CreateSectionBox(parent, title)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local px = QUICore:GetPixelSize(box)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    box:SetBackdropColor(0.05, 0.05, 0.08, 0.8)
    box:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    
    -- Title (mint colored, positioned at top-left inside border)
    if title and title ~= "" then
        local titleText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetFont(GetFontPath(), 12, "")
        titleText:SetTextColor(C_accentLight_r, C_accentLight_g, C_accentLight_b, C_accentLight_a)
        titleText:SetText(title)
        titleText:SetPoint("TOPLEFT", 10, -8)
        box.title = titleText
    end
    
    -- Track current Y position for auto-layout
    box.currentY = -30  -- Starting Y position for content inside the box
    box.padding = 12    -- Left/right padding
    box.elementSpacing = 8  -- Default spacing between elements
    
    -- Helper to add element and auto-position it
    function box:AddElement(element, height, spacing)
        local sp = spacing or self.elementSpacing
        element:SetPoint("TOPLEFT", self.padding, self.currentY)
        if element.SetPoint then
            -- If element supports right anchor, stretch it
            element:SetPoint("TOPRIGHT", -self.padding, self.currentY)
        end
        self.currentY = self.currentY - (height or 25) - sp
    end
    
    -- Call this after adding all elements to set the box height
    function box:FinishLayout(bottomPadding)
        local pad = bottomPadding or 12
        self:SetHeight(math.abs(self.currentY) + pad)
        return math.abs(self.currentY) + pad  -- Return height for parent tracking
    end
    
    return box
end

---------------------------------------------------------------------------
-- WIDGET: COLLAPSIBLE SECTION
-- Expandable/collapsible container with clickable header
---------------------------------------------------------------------------
function GUI:CreateCollapsibleSection(parent, title, isExpandedByDefault, badgeConfig)
    local container = CreateFrame("Frame", nil, parent)
    local isExpanded = isExpandedByDefault ~= false  -- Default true

    -- Header (clickable, full width)
    local header = CreateFrame("Button", nil, container, "BackdropTemplate")
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    local px = QUICore:GetPixelSize(header)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    header:SetBackdropColor(C.bgLight[1], C.bgLight[2], C.bgLight[3], 0.6)
    header:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.5)

    -- Chevron indicator
    local chevron
    if UIKit and UIKit.CreateChevronCaret then
        chevron = UIKit.CreateChevronCaret(header, {
            point = "LEFT",
            relativeTo = header,
            relativePoint = "LEFT",
            xPixels = 10,
            yPixels = 0,
            sizePixels = 10,
            lineWidthPixels = 6,
            lineHeightPixels = 1,
            expanded = isExpanded,
            collapsedDirection = "right",
            r = C.accent[1],
            g = C.accent[2],
            b = C.accent[3],
            a = 1,
        })
    else
        chevron = CreateVectorCaret(header, 0)
        chevron:ClearAllPoints()
        chevron:SetPoint("LEFT", header, "LEFT", 10, 0)
    end

    -- Title text
    local titleText = header:CreateFontString(nil, "OVERLAY")
    SetFont(titleText, 12, "", C.accent)
    titleText:SetText(title or "Section")
    titleText:SetPoint("LEFT", chevron, "RIGHT", 6, 0)

    -- Optional badge (e.g., "Override" indicator)
    local badge = nil
    if badgeConfig and badgeConfig.text then
        badge = CreateFrame("Frame", nil, header, "BackdropTemplate")
        badge:SetHeight(18)
        badge:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        badge:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.2)
        badge:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

        local badgeText = badge:CreateFontString(nil, "OVERLAY")
        badgeText:SetFont(GetFontPath(), 10, "")
        badgeText:SetText(badgeConfig.text)
        badgeText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        badgeText:SetPoint("CENTER", 0, 0)

        -- Auto-width based on text
        local textWidth = badgeText:GetStringWidth() or 40
        badge:SetWidth(textWidth + 12)
        badge:SetPoint("RIGHT", header, "RIGHT", -10, 0)

        -- Initial visibility based on showFunc
        if badgeConfig.showFunc then
            badge:SetShown(badgeConfig.showFunc())
        end
    end

    -- Content area
    local contentClip = CreateFrame("ScrollFrame", nil, container)
    contentClip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    contentClip:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    contentClip:SetHeight(0)
    contentClip:SetShown(isExpanded)

    local content = CreateFrame("Frame", nil, contentClip)
    content:SetHeight(1)
    content:SetWidth(1)
    contentClip:SetScrollChild(content)
    contentClip:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(width or 1, 1))
    end)
    content._hasContent = false
    content:SetAlpha(isExpanded and 1 or 0)

    local function UpdateChevronVisual()
        if UIKit and UIKit.SetChevronCaretExpanded and UIKit.SetChevronCaretColor then
            UIKit.SetChevronCaretExpanded(chevron, isExpanded)
            UIKit.SetChevronCaretColor(chevron, C.accent[1], C.accent[2], C.accent[3], 1)
        elseif chevron and chevron.SetText then
            chevron:SetText(isExpanded and "v" or ">")
            chevron:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end
    end

    -- Update function
    local function ApplyState(currentHeight)
        local height = math.max(0, currentHeight or 0)
        contentClip:SetHeight(height)
        container:SetHeight(header:GetHeight() + height + (height > 0 and 4 or 0))
    end

    local function NotifyExpandChanged()
        if container.OnExpandChanged then
            container.OnExpandChanged(isExpanded)
        end
    end

    local function UpdateState(skipAnimation)
        local targetHeight = isExpanded and (content:GetHeight() or 0) or 0
        UpdateChevronVisual()
        if isExpanded then
            contentClip:Show()
        end

        if skipAnimation or not (UIKit and UIKit.AnimateValue and UIKit.CancelValueAnimation) then
            if UIKit and UIKit.CancelValueAnimation then
                UIKit.CancelValueAnimation(container, "helpCollapsible")
            end
            ApplyState(targetHeight)
            content:SetAlpha(isExpanded and 1 or 0)
            if not isExpanded then
                contentClip:Hide()
            end
            NotifyExpandChanged()
            return
        end

        UIKit.CancelValueAnimation(container, "helpCollapsible")
        UIKit.AnimateValue(container, "helpCollapsible", {
            fromValue = contentClip:GetHeight() or 0,
            toValue = targetHeight,
            duration = (GUI._sidebarAnimDuration or 0.16),
            onUpdate = function(_, progressHeight)
                local totalRange = math.max(content:GetHeight() or 0, 1)
                local ratio = math.max(0, math.min(1, progressHeight / totalRange))
                ApplyState(progressHeight)
                content:SetAlpha(ratio)
                NotifyExpandChanged()
            end,
            onFinish = function(_, finalHeight)
                ApplyState(finalHeight)
                content:SetAlpha(isExpanded and 1 or 0)
                if not isExpanded then
                    contentClip:Hide()
                end
                NotifyExpandChanged()
            end,
        })
    end

    -- Click handler
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        UpdateState()
    end)

    -- Hover effects
    header:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
        if UIKit and UIKit.SetChevronCaretColor then
            UIKit.SetChevronCaretColor(chevron, 1, 1, 1, 1)
        end
    end)
    header:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.5)
        UpdateChevronVisual()
    end)

    -- API methods
    container.SetExpanded = function(self, expanded, skipAnimation)
        isExpanded = expanded
        UpdateState(skipAnimation)
    end

    container.GetExpanded = function()
        return isExpanded
    end

    container.UpdateHeight = function()
        UpdateState(true)
    end

    container.SetTitle = function(self, newTitle)
        titleText:SetText(newTitle)
    end

    -- Badge update method
    container.UpdateBadge = function()
        if badge and badgeConfig and badgeConfig.showFunc then
            badge:SetShown(badgeConfig.showFunc())
        end
    end

    container.content = content
    container.header = header
    container.badge = badge

    UpdateState(true)
    return container
end

---------------------------------------------------------------------------
-- WIDGET: COLOR PICKER
---------------------------------------------------------------------------
function GUI:CreateColorPicker(parent, label, dbKey, dbTable, onChange)
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

    -- Store as last sub-tab group so SelectTab can capture it
    GUI._lastSubTabGroup = buttonGroup

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
        return UIKit.CreateAccentCheckbox(parent, options)
    end

    return nil
end

function GUI:CreateCheckbox(parent, label, dbKey, dbTable, onChange)
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
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: CHECKBOX CENTERED (label centered above checkbox)
---------------------------------------------------------------------------
function GUI:CreateCheckboxCentered(parent, label, dbKey, dbTable, onChange)
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
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: COLOR PICKER CENTERED (label centered above swatch)
---------------------------------------------------------------------------
function GUI:CreateColorPickerCentered(parent, label, dbKey, dbTable, onChange)
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
    
    return container
end

---------------------------------------------------------------------------
-- Inverted Checkbox: checked = false in DB, unchecked = true in DB
-- Use for "Hide X" options where DB stores "showX"
---------------------------------------------------------------------------
function GUI:CreateCheckboxInverted(parent, label, dbKey, dbTable, onChange)
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

function GUI:CreateDropdown(parent, label, options, dbKey, dbTable, onChange)
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

    -- Dropdown button (same width as slider track - inset 35px on each side)
    local dropdown = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropdown:SetHeight(24)  -- Increased from 20 for better tap target
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 35, -16)
    dropdown:SetPoint("RIGHT", container, "RIGHT", -35, 0)
    local px = QUICore:GetPixelSize(dropdown)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 1)
    dropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)  -- Increased from 0.25 for better visibility

    -- Chevron zone (right side with accent tint)
    local chevronZone = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    chevronZone:SetWidth(CHEVRON_ZONE_WIDTH)
    chevronZone:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1)
    chevronZone:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -1, 1)
    chevronZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)

    -- Separator line (left edge of chevron zone)
    local separator = chevronZone:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", chevronZone, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", chevronZone, "BOTTOMLEFT", 0, 0)
    separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    -- Line chevron (two angled lines forming a V pointing DOWN)
    local chevronLeft = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronLeft:SetSize(7, 2)
    chevronLeft:SetPoint("CENTER", chevronZone, "CENTER", -2, -1)
    chevronLeft:SetRotation(math.rad(-45))

    local chevronRight = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronRight:SetSize(7, 2)
    chevronRight:SetPoint("CENTER", chevronZone, "CENTER", 2, -1)
    chevronRight:SetRotation(math.rad(45))

    dropdown.chevronLeft = chevronLeft
    dropdown.chevronRight = chevronRight
    dropdown.chevronZone = chevronZone
    dropdown.separator = separator

    -- Selected text - centered, accounting for chevron zone
    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 11, "", C.text)
    dropdown.selected:SetPoint("LEFT", 8, 0)
    dropdown.selected:SetPoint("RIGHT", chevronZone, "LEFT", -5, 0)
    dropdown.selected:SetJustifyH("CENTER")

    -- Hover effect
    dropdown:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA_HOVER)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.35, 0.35, 0.35, 1)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
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
    
    -- Dropdown menu frame (parented to UIParent to avoid scroll frame clipping)
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

    local menuButtons = {}
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
            pcall(function()
                self:SetBackdrop(nil)
            end)
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
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: DROPDOWN FULL WIDTH (For pages like Spec Profiles - no inset)
---------------------------------------------------------------------------
function GUI:CreateDropdownFullWidth(parent, label, options, dbKey, dbTable, onChange)
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

    -- Dropdown button (full width, no inset)
    local dropdown = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropdown:SetHeight(24)
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -18)
    dropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    local px = QUICore:GetPixelSize(dropdown)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 1)
    dropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)  -- Increased from 0.25

    -- Chevron zone (right side with accent tint)
    local chevronZone = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    chevronZone:SetWidth(CHEVRON_ZONE_WIDTH)
    chevronZone:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1)
    chevronZone:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -1, 1)
    chevronZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)

    -- Separator line (left edge of chevron zone)
    local separator = chevronZone:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", chevronZone, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", chevronZone, "BOTTOMLEFT", 0, 0)
    separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    -- Line chevron (two angled lines forming a V pointing DOWN)
    local chevronLeft = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronLeft:SetSize(7, 2)
    chevronLeft:SetPoint("CENTER", chevronZone, "CENTER", -2, -1)
    chevronLeft:SetRotation(math.rad(-45))

    local chevronRight = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronRight:SetSize(7, 2)
    chevronRight:SetPoint("CENTER", chevronZone, "CENTER", 2, -1)
    chevronRight:SetRotation(math.rad(45))

    dropdown.chevronLeft = chevronLeft
    dropdown.chevronRight = chevronRight
    dropdown.chevronZone = chevronZone
    dropdown.separator = separator

    -- Selected text - centered, accounting for chevron zone
    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 11, "", C.text)
    dropdown.selected:SetPoint("LEFT", 10, 0)
    dropdown.selected:SetPoint("RIGHT", chevronZone, "LEFT", -5, 0)
    dropdown.selected:SetJustifyH("CENTER")

    -- Hover effect
    dropdown:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA_HOVER)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.35, 0.35, 0.35, 1)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
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

    return container
end

---------------------------------------------------------------------------
-- FORM WIDGETS (Label on left, widget on right)
---------------------------------------------------------------------------

local FORM_ROW_HEIGHT = 28

---------------------------------------------------------------------------
-- WIDGET: iOS-STYLE TOGGLE SWITCH (Premium)
-- Track: 40x20px, fully rounded
-- OFF: Dark grey track, white circle on left
-- ON: Mint track, white circle slides to right
---------------------------------------------------------------------------
function GUI:CreateFormToggle(parent, label, dbKey, dbTable, onChange, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    local UIKit = ns.UIKit
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

    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines

    -- Toggle track (the pill-shaped background)
    local track = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    track:SetSize(40, 20)
    track:SetPoint("LEFT", container, "LEFT", 180, 0)
    if useUIKitBorders then
        track._bg = UIKit.CreateBackground(track, C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1)
        UIKit.CreateBorderLines(track)
    else
        local px = QUICore:GetPixelSize(track)
        track:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
    end

    -- Thumb (the sliding circle)
    local thumb = CreateFrame("Frame", nil, track, useUIKitBorders and nil or "BackdropTemplate")
    thumb:SetSize(16, 16)
    if useUIKitBorders then
        thumb._bg = UIKit.CreateBackground(thumb, C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
        UIKit.CreateBorderLines(thumb)
        UIKit.UpdateBorderLines(thumb, 1, 0.85, 0.85, 0.85, 1, false)
    else
        local px = QUICore:GetPixelSize(track)
        thumb:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        thumb:SetBackdropColor(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
        thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    end
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)

    container.track = track
    container.thumb = thumb
    container.label = text

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end

    local function SetTrackVisual(bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
        if useUIKitBorders then
            if track._bg then
                track._bg:SetVertexColor(bgR, bgG, bgB, bgA)
            end
            UIKit.UpdateBorderLines(track, 1, borderR, borderG, borderB, borderA, false)
            return
        end
        track:SetBackdropColor(bgR, bgG, bgB, bgA)
        track:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
    end

    local function SetThumbAnchor(isOn)
        thumb:ClearAllPoints()
        if isOn then
            thumb:SetPoint("RIGHT", track, "RIGHT", -2, 0)
        else
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0)
        end
    end

    local function UpdateVisual(val)
        if val then
            -- ON state: Mint track, thumb on right
            SetTrackVisual(C.accent[1], C.accent[2], C.accent[3], 1, C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1)
            SetThumbAnchor(true)
        else
            -- OFF state: Dark grey track, thumb on left
            SetTrackVisual(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1, 0.12, 0.14, 0.18, 1)
            SetThumbAnchor(false)
        end
    end

    local function SetValue(val, skipCallback)
        container.checked = val
        UpdateVisual(val)
        if dbTable and dbKey then dbTable[dbKey] = val end
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

    SetValue(GetValue(), true)  -- Skip callback on init

    if useUIKitBorders and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(track, "formToggleScale", function()
            track:SetSize(40, 20)
            track:ClearAllPoints()
            track:SetPoint("LEFT", container, "LEFT", 180, 0)
            thumb:SetSize(16, 16)
            UIKit.UpdateBorderLines(thumb, 1, 0.85, 0.85, 0.85, 1, false)
            UpdateVisual(GetValue())
        end)
    end

    -- Click to toggle
    track:SetScript("OnClick", function() SetValue(not GetValue()) end)

    -- Hover effects
    track:SetScript("OnEnter", function()
        if GetValue() then
            if useUIKitBorders then
                UIKit.UpdateBorderLines(track, 1, C.accentHover[1], C.accentHover[2], C.accentHover[3], 1, false)
            else
                track:SetBackdropBorderColor(C.accentHover[1], C.accentHover[2], C.accentHover[3], 1)
            end
        else
            if useUIKitBorders then
                UIKit.UpdateBorderLines(track, 1, 0.25, 0.28, 0.35, 1, false)
            else
                track:SetBackdropBorderColor(0.25, 0.28, 0.35, 1)
            end
        end
    end)
    track:SetScript("OnLeave", function()
        UpdateVisual(GetValue())
    end)

    -- Enable/disable the toggle (for conditional UI)
    container.SetEnabled = function(self, enabled)
        track:EnableMouse(enabled)
        -- Visual feedback: dim when disabled
        container:SetAlpha(enabled and 1 or 0.4)
    end

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0) .. "_" .. (GUI._searchContext.sectionName or "")
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            local entry = {
                label = label,
                widgetType = "toggle",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormToggle(p, label, dbKey, dbTable, onChange)
                end,
            }
            -- Add keywords from registryInfo if provided
            if registryInfo and registryInfo.keywords then
                entry.keywords = registryInfo.keywords
            end
            table.insert(GUI.SettingsRegistry, entry)
        end
    end

    return container
end

-- Inverted toggle: checked = DB false, unchecked = DB true (for "Hide X" options)
function GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    local UIKit = ns.UIKit
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

    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines

    -- Toggle track
    local track = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    track:SetSize(40, 20)
    track:SetPoint("LEFT", container, "LEFT", 180, 0)
    if useUIKitBorders then
        track._bg = UIKit.CreateBackground(track, C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1)
        UIKit.CreateBorderLines(track)
    else
        local px = QUICore:GetPixelSize(track)
        track:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
    end

    -- Thumb
    local thumb = CreateFrame("Frame", nil, track, useUIKitBorders and nil or "BackdropTemplate")
    thumb:SetSize(16, 16)
    if useUIKitBorders then
        thumb._bg = UIKit.CreateBackground(thumb, C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
        UIKit.CreateBorderLines(thumb)
        UIKit.UpdateBorderLines(thumb, 1, 0.85, 0.85, 0.85, 1, false)
    else
        local px = QUICore:GetPixelSize(track)
        thumb:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        thumb:SetBackdropColor(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
        thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    end
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)

    container.track = track
    container.thumb = thumb
    container.label = text

    -- INVERTED: DB true = toggle OFF, DB false = toggle ON
    local function GetDBValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return true
    end

    local function IsOn()
        return not GetDBValue()  -- Invert for display
    end

    local function SetTrackVisual(bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
        if useUIKitBorders then
            if track._bg then
                track._bg:SetVertexColor(bgR, bgG, bgB, bgA)
            end
            UIKit.UpdateBorderLines(track, 1, borderR, borderG, borderB, borderA, false)
            return
        end
        track:SetBackdropColor(bgR, bgG, bgB, bgA)
        track:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
    end

    local function SetThumbAnchor(isOn)
        thumb:ClearAllPoints()
        if isOn then
            thumb:SetPoint("RIGHT", track, "RIGHT", -2, 0)
        else
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0)
        end
    end

    local function UpdateVisual(isOn)
        if isOn then
            SetTrackVisual(C.accent[1], C.accent[2], C.accent[3], 1, C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1)
            SetThumbAnchor(true)
        else
            SetTrackVisual(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1, 0.12, 0.14, 0.18, 1)
            SetThumbAnchor(false)
        end
    end

    local function SetOn(isOn, skipCallback)
        container.checked = isOn
        local dbVal = not isOn  -- Invert for storage
        UpdateVisual(isOn)
        if dbTable and dbKey then dbTable[dbKey] = dbVal end
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

    SetOn(IsOn(), true)  -- Skip callback on init

    if useUIKitBorders and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(track, "formToggleInvertedScale", function()
            track:SetSize(40, 20)
            track:ClearAllPoints()
            track:SetPoint("LEFT", container, "LEFT", 180, 0)
            thumb:SetSize(16, 16)
            UIKit.UpdateBorderLines(thumb, 1, 0.85, 0.85, 0.85, 1, false)
            UpdateVisual(IsOn())
        end)
    end

    track:SetScript("OnClick", function() SetOn(not IsOn()) end)

    track:SetScript("OnEnter", function()
        if IsOn() then
            if useUIKitBorders then
                UIKit.UpdateBorderLines(track, 1, C.accentHover[1], C.accentHover[2], C.accentHover[3], 1, false)
            else
                track:SetBackdropBorderColor(C.accentHover[1], C.accentHover[2], C.accentHover[3], 1)
            end
        else
            if useUIKitBorders then
                UIKit.UpdateBorderLines(track, 1, 0.25, 0.28, 0.35, 1, false)
            else
                track:SetBackdropBorderColor(0.25, 0.28, 0.35, 1)
            end
        end
    end)
    track:SetScript("OnLeave", function()
        UpdateVisual(IsOn())
    end)

    -- Enable/disable the toggle (for conditional UI)
    container.SetEnabled = function(self, enabled)
        track:EnableMouse(enabled)
        -- Visual feedback: dim when disabled
        container:SetAlpha(enabled and 1 or 0.4)
    end

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
function GUI:CreateFormCheckboxOriginal(parent, label, dbKey, dbTable, onChange)
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
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(18, 18)
    box:SetPoint("LEFT", container, "LEFT", 180, 0)
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
    box.check:SetSize(22, 22)
    box.check:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    box.check:SetDesaturated(true)
    box.check:Hide()

    container.box = box
    container.label = text

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end

    local function UpdateVisual(val)
        if val then
            box.check:Show()
            box:SetBackdropBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(C_border_r, C_border_g, C_border_b, C_border_a)
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
    end

    local function SetValue(val, skipCallback)
        container.checked = val
        UpdateVisual(val)
        if dbTable and dbKey then dbTable[dbKey] = val end
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

    SetValue(GetValue(), true)

    box:SetScript("OnClick", function() SetValue(not GetValue()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, C_accentHover_r, C_accentHover_g, C_accentHover_b, C_accentHover_a) end)
    box:SetScript("OnLeave", function(self)
        if GetValue() then
            pcall(self.SetBackdropBorderColor, self, C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        else
            pcall(self.SetBackdropBorderColor, self, C_border_r, C_border_g, C_border_b, C_border_a)
        end
    end)

    return container
end

-- Form Checkbox Inverted: checked = DB false, unchecked = DB true (for "Hide X" options)
function GUI:CreateFormCheckboxInverted(parent, label, dbKey, dbTable, onChange)
    -- Redirect to toggle inverted for the premium look
    return GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange)
end

function GUI:CreateFormEditBox(parent, label, dbKey, dbTable, onChange, options, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    options = options or {}
    local UIKit = ns.UIKit

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
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
        fieldBg = UIKit.CreateBackground(field, 0.08, 0.08, 0.08, 1)
    else
        fieldBg = field:CreateTexture(nil, "BACKGROUND")
        fieldBg:SetAllPoints()
        fieldBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        fieldBg:SetVertexColor(0.08, 0.08, 0.08, 1)
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
    SetFieldBorderColor(0.35, 0.35, 0.35, 1)

    local editBox = CreateFrame("EditBox", nil, field)
    editBox:SetPoint("TOPLEFT", field, "TOPLEFT", 6, -2)
    editBox:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -6, 2)
    editBox:SetAutoFocus(false)
    editBox:SetFont(GetFontPath(), 11, "")
    editBox:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a)
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
        SetFieldBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        if options.onEditFocusGained then
            options.onEditFocusGained(self)
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        SetFieldBorderColor(0.35, 0.35, 0.35, 1)
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

    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0) .. "_" .. (GUI._searchContext.sectionName or "")
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            local entry = {
                label = label,
                widgetType = "editbox",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormEditBox(p, label, dbKey, dbTable, onChange, options)
                end,
            }
            if registryInfo and registryInfo.keywords then
                entry.keywords = registryInfo.keywords
            end
            table.insert(GUI.SettingsRegistry, entry)
        end
    end

    return container
end

function GUI:CreateFormSlider(parent, label, min, max, step, dbKey, dbTable, onChange, options, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    container:EnableMouse(true)  -- Block clicks from passing through to frames behind

    options = options or {}
    local UIKit = ns.UIKit
    ApplyWidgetSyncContext(container, dbTable, dbKey)
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines
    local deferOnDrag = options.deferOnDrag or false
    local precision = options.precision
    local formatStr = precision and string.format("%%.%df", precision) or (step < 1 and "%.2f" or "%d")

    -- Label on left (off-white text, constrained to not overlap slider track)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Setting")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(170)
    text:SetWordWrap(true)
    text:SetNonSpaceWrap(true)
    text:SetJustifyH("LEFT")
    text:SetWidth(170)
    text:SetWordWrap(true)
    text:SetJustifyH("LEFT")
    container.label = text

    -- Track container (for the filled + unfilled portions)
    local trackContainer = CreateFrame("Frame", nil, container)
    trackContainer:SetHeight(6)  -- Thicker track (was 14, now 6 for cleaner look)
    trackContainer:SetPoint("LEFT", container, "LEFT", 180, 0)
    trackContainer:SetPoint("RIGHT", container, "RIGHT", -70, 0)

    -- Unfilled track (background) - rounded appearance via backdrop
    local trackBg = CreateFrame("Frame", nil, trackContainer, useUIKitBorders and nil or "BackdropTemplate")
    trackBg:SetAllPoints()
    local px = QUICore:GetPixelSize(trackBg)
    if useUIKitBorders then
        trackBg.bg = UIKit.CreateBackground(trackBg, C.sliderTrack[1], C.sliderTrack[2], C.sliderTrack[3], 1)
        UIKit.CreateBorderLines(trackBg)
        UIKit.UpdateBorderLines(trackBg, 1, 0.1, 0.12, 0.15, 1, false)
    else
        trackBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        trackBg:SetBackdropColor(C.sliderTrack[1], C.sliderTrack[2], C.sliderTrack[3], 1)
        trackBg:SetBackdropBorderColor(0.1, 0.12, 0.15, 1)
    end

    -- Filled track (mint portion from left to thumb)
    local trackFill = CreateFrame("Frame", nil, trackContainer, useUIKitBorders and nil or "BackdropTemplate")
    trackFill:SetPoint("TOPLEFT", px, -px)
    trackFill:SetPoint("BOTTOMLEFT", px, px)
    trackFill:SetWidth(1)  -- Will be updated dynamically
    if useUIKitBorders then
        trackFill.bg = UIKit.CreateBackground(trackFill, C.accent[1], C.accent[2], C.accent[3], 1)
    else
        trackFill:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        trackFill:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end

    -- Actual slider (invisible, just for interaction)
    local slider = CreateFrame("Slider", nil, trackContainer)
    slider:SetAllPoints()
    slider:SetOrientation("HORIZONTAL")
    slider:SetHitRectInsets(0, 0, -10, -10)  -- Expand hit area 10px above/below for reliable hover detection

    -- Thumb frame (white circle with border)
    local thumbFrame = CreateFrame("Frame", nil, slider, useUIKitBorders and nil or "BackdropTemplate")
    thumbFrame:SetSize(14, 14)
    if useUIKitBorders then
        thumbFrame.bg = UIKit.CreateBackground(thumbFrame, C.sliderThumb[1], C.sliderThumb[2], C.sliderThumb[3], 1)
        UIKit.CreateBorderLines(thumbFrame)
        UIKit.UpdateBorderLines(thumbFrame, 1, C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1, false)
    else
        thumbFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        thumbFrame:SetBackdropColor(C.sliderThumb[1], C.sliderThumb[2], C.sliderThumb[3], 1)
        thumbFrame:SetBackdropBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
    end
    thumbFrame:SetFrameLevel(slider:GetFrameLevel() + 2)
    thumbFrame:EnableMouse(false)  -- Let clicks pass through to slider

    -- Round the thumb corners using a mask texture overlay
    local thumbRound = thumbFrame:CreateTexture(nil, "OVERLAY")
    thumbRound:SetAllPoints()
    thumbRound:SetColorTexture(1, 1, 1, 0)  -- Invisible, just for structure

    -- Use the thumb frame as the visual, position it manually
    slider.thumbFrame = thumbFrame

    -- Hidden thumb texture for slider mechanics
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(14, 14)
    thumb:SetAlpha(0)  -- Hide the actual thumb, we use thumbFrame instead

    -- Editbox for value (far right)
    local editBox = CreateFrame("EditBox", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    editBox:SetSize(60, 22)
    editBox:SetPoint("RIGHT", 0, 0)
    if useUIKitBorders then
        editBox.bg = UIKit.CreateBackground(editBox, 0.08, 0.08, 0.08, 1)
        UIKit.CreateBorderLines(editBox)
        UIKit.UpdateBorderLines(editBox, 1, 0.25, 0.25, 0.25, 1, false)
    else
        editBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        editBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
        editBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
    editBox:SetFont(GetFontPath(), 11, "")
    editBox:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a)
    editBox:SetJustifyH("CENTER")
    editBox:SetAutoFocus(false)

    local function SetThumbBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(thumbFrame, 1, r, g, b, a or 1, false)
        else
            thumbFrame:SetBackdropBorderColor(r, g, b, a or 1)
        end
    end

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
        local pct = (value - minVal) / (maxVal - minVal)
        pct = math.max(0, math.min(1, pct))

        local trackWidth = trackContainer:GetWidth() - 2  -- Account for border
        local fillWidth = math.max(1, pct * trackWidth)
        trackFill:SetWidth(fillWidth)

        -- Position the thumb frame
        local thumbX = pct * (trackWidth - 14) + 7  -- Center thumb on fill edge
        thumbFrame:SetPoint("CENTER", trackContainer, "LEFT", thumbX + 1, 0)
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
        BroadcastToSiblings(container, val)
        if not skipOnChange and onChange then onChange(val) end
        if not skipOnChange then
            MaybeAutoNotifyProviderSync(container)
        end
    end

    container.GetValue = GetValue
    container.SetValue = BindWidgetMethod(container, SetValue)
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)

    slider:SetScript("OnValueChanged", function(self, value, userInput)
        -- Ignore user input if slider is disabled
        if userInput and container.isEnabled == false then return end

        value = math.floor(value / container.step + 0.5) * container.step
        editBox:SetText(string.format(formatStr, value))
        UpdateTrackFill(value)
        if dbTable and dbKey then dbTable[dbKey] = value end
        if userInput then
            BroadcastToSiblings(container, value)
            if deferOnDrag and isDragging then return end
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

    -- Hover effects on thumb
    slider:SetScript("OnEnter", function()
        SetThumbBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    slider:SetScript("OnLeave", function()
        SetThumbBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
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

    -- Hover effect on editbox
    editBox:SetScript("OnEnter", function(self)
        SetEditBoxBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        SetEditBoxBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        SetEditBoxBorderColor(0.25, 0.25, 0.25, 1)
    end)
    editBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            SetEditBoxBorderColor(0.25, 0.25, 0.25, 1)
        end
    end)

    -- Re-update track fill when container size changes (fixes initial layout timing)
    trackContainer:SetScript("OnSizeChanged", function(self, width, height)
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

        -- Store state for scripts to check
        container.isEnabled = enabled

        -- Visual feedback: dim when disabled (matches HUD Visibility pattern)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    -- Initialize enabled state
    container.isEnabled = true

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0) .. "_" .. (GUI._searchContext.sectionName or "")
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            table.insert(GUI.SettingsRegistry, {
                label = label,
                widgetType = "slider",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormSlider(p, label, min, max, step, dbKey, dbTable, onChange, options)
                end,
            })
        end
    end

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
    container:SetHeight(FORM_ROW_HEIGHT)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Setting")
    text:SetPoint("LEFT", 0, 0)

    -- Dropdown button (right side)
    local dropdown = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    dropdown:SetHeight(24)  -- Increased from 22
    dropdown:SetPoint("LEFT", container, "LEFT", 180, 0)
    dropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    local px = QUICore:GetPixelSize(dropdown)
    if useUIKitBorders then
        dropdown.bg = UIKit.CreateBackground(dropdown, 0.08, 0.08, 0.08, 1)
        UIKit.CreateBorderLines(dropdown)
        UIKit.UpdateBorderLines(dropdown, 1, 0.35, 0.35, 0.35, 1, false)
    else
        dropdown:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        dropdown:SetBackdropColor(0.08, 0.08, 0.08, 1)
        dropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)  -- Increased from 0.25
    end

    local function SetDropdownBorderColor(r, g, b, a)
        if useUIKitBorders then
            UIKit.UpdateBorderLines(dropdown, 1, r, g, b, a or 1, false)
        else
            pcall(dropdown.SetBackdropBorderColor, dropdown, r, g, b, a or 1)
        end
    end

    -- Chevron zone (right side with accent tint)
    local chevronZone = CreateFrame("Frame", nil, dropdown)
    chevronZone:SetWidth(CHEVRON_ZONE_WIDTH)
    chevronZone:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1)
    chevronZone:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -1, 1)
    local chevronZoneBg = chevronZone:CreateTexture(nil, "BACKGROUND")
    chevronZoneBg:SetAllPoints()
    chevronZoneBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    chevronZoneBg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)

    -- Separator line (left edge of chevron zone)
    local separator = chevronZone:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", chevronZone, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", chevronZone, "BOTTOMLEFT", 0, 0)
    separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    -- Line chevron (two angled lines forming a V pointing DOWN)
    local chevronLeft = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronLeft:SetSize(7, 2)
    chevronLeft:SetPoint("CENTER", chevronZone, "CENTER", -2, -1)
    chevronLeft:SetRotation(math.rad(-45))

    local chevronRight = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronRight:SetSize(7, 2)
    chevronRight:SetPoint("CENTER", chevronZone, "CENTER", 2, -1)
    chevronRight:SetRotation(math.rad(45))

    dropdown.chevronLeft = chevronLeft
    dropdown.chevronRight = chevronRight
    dropdown.chevronZone = chevronZone
    dropdown.separator = separator

    -- Selected text, accounting for chevron zone
    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 11, "", C.text)
    dropdown.selected:SetPoint("LEFT", 8, 0)
    dropdown.selected:SetPoint("RIGHT", chevronZone, "LEFT", -5, 0)
    dropdown.selected:SetJustifyH("LEFT")

    -- Hover effect
    dropdown:SetScript("OnEnter", function(self)
        SetDropdownBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        chevronZoneBg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA_HOVER)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        SetDropdownBorderColor(0.35, 0.35, 0.35, 1)
        chevronZoneBg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    end)

    -- Menu frame (parented to UIParent to avoid scroll frame clipping)
    local menuFrame = CreateFrame("Frame", nil, UIParent, useUIKitBorders and nil or "BackdropTemplate")
    if useUIKitBorders then
        menuFrame.bg = UIKit.CreateBackground(menuFrame, 0.1, 0.1, 0.1, 0.98)
        UIKit.CreateBorderLines(menuFrame)
        UIKit.UpdateBorderLines(menuFrame, 1, 0.3, 0.3, 0.3, 1, false)
    else
        menuFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        menuFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
        menuFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
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
            f._btnText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f._btnText:SetPoint("LEFT", 4, 0)
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
        local itemHeight = 20
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
                    SetFont(btn._btnText, 11, "", C.text)
                    btn._btnText:SetText(opt.text)
                    btn._btnText:SetPoint("LEFT", 4, 0)
                    btn:SetScript("OnClick", function()
                        SetValue(opt.value)
                        menuFrame:Hide()
                    end)
                    btn:SetScript("OnEnter", function() btn._btnText:SetTextColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a) end)
                    btn:SetScript("OnLeave", function() btn._btnText:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a) end)
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
            SetFont(noMatch._btnText, 11, "", mutedColor)
            noMatch._btnText:SetText("No matches")
            noMatch._btnText:SetPoint("CENTER", 0, 0)
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
    container.SetOptions = SetOptions
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)

    SetValue(GetValue(), true)

    -- Enable/disable the dropdown (for conditional UI)
    container.SetEnabled = function(self, enabled)
        dropdown:EnableMouse(enabled)
        container.isEnabled = enabled
        container:SetAlpha(enabled and 1 or 0.4)
    end
    container.isEnabled = true

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0) .. "_" .. (GUI._searchContext.sectionName or "")
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            table.insert(GUI.SettingsRegistry, {
                label = label,
                widgetType = "dropdown",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormDropdown(p, label, options, dbKey, dbTable, onChange, nil, opts)
                end,
            })
        end
    end

    return container
end

function GUI:CreateFormColorPicker(parent, label, dbKey, dbTable, onChange, options)
    options = options or {}
    local noAlpha = options.noAlpha or false
    local UIKit = ns.UIKit
    local useUIKitBorders = UIKit
        and UIKit.CreateBackground
        and UIKit.CreateBorderLines
        and UIKit.UpdateBorderLines

    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    ApplyWidgetSyncContext(container, dbTable, dbKey)

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Color")
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(170)
    text:SetWordWrap(true)
    text:SetNonSpaceWrap(true)
    text:SetJustifyH("LEFT")

    -- Color swatch aligned with other widgets (starts at 180px from left)
    local swatch = CreateFrame("Button", nil, container, useUIKitBorders and nil or "BackdropTemplate")
    swatch:SetSize(50, 18)
    swatch:SetPoint("LEFT", container, "LEFT", 180, 0)
    local px = QUICore:GetPixelSize(swatch)
    if useUIKitBorders then
        swatch.bg = UIKit.CreateBackground(swatch, 1, 1, 1, 1)
        UIKit.CreateBorderLines(swatch)
        UIKit.UpdateBorderLines(swatch, 1, 0.4, 0.4, 0.4, 1, false)
    else
        swatch:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
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
        if dbTable and dbKey then
            dbTable[dbKey] = {r, g, b, finalAlpha}
        end
        if onChange then onChange(r, g, b, finalAlpha) end
        BroadcastToSiblings(container, {r, g, b, finalAlpha})
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

    local r, g, b, a = GetColor()
    SetSwatchColor(r, g, b, a)

    swatch:SetScript("OnClick", function()
        local currentR, currentG, currentB, currentA = GetColor()
        local originalA = currentA
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
    end)

    swatch:SetScript("OnEnter", function() SetSwatchBorderColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a) end)
    swatch:SetScript("OnLeave", function() SetSwatchBorderColor(0.4, 0.4, 0.4, 1) end)

    -- Enable/disable (for conditional UI)
    container.SetEnabled = function(self, enabled)
        swatch:EnableMouse(enabled)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0) .. "_" .. (GUI._searchContext.sectionName or "")
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            table.insert(GUI.SettingsRegistry, {
                label = label,
                widgetType = "colorpicker",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormColorPicker(p, label, dbKey, dbTable, onChange, options)
                end,
            })
        end
    end

    return container
end

local CreateFormEditBoxModern = GUI.CreateFormEditBox

---------------------------------------------------------------------------
-- FORM EDIT BOX (single-line text input with label and DB binding)
---------------------------------------------------------------------------
function GUI:CreateFormEditBox(parent, label, dbKey, dbTable, onChange, options)
    if CreateFormEditBoxModern then
        return CreateFormEditBoxModern(self, parent, label, dbKey, dbTable, onChange, options)
    end
    return nil
end

---------------------------------------------------------------------------
-- Inline edit box (lightweight, no label, used inside custom list entries)
---------------------------------------------------------------------------
function GUI:CreateInlineEditBox(parent, options)
    options = options or {}
    local w = options.width or 120
    local h = options.height or 22
    local editH = options.editHeight or (h - 2)
    local inset = options.textInset or 6
    local bg = options.bgColor or {0.08, 0.08, 0.08, 1}
    local border = options.borderColor or {0.25, 0.25, 0.25, 1}
    local activeBorder = options.activeBorderColor or C.accent

    -- Background frame with backdrop
    local bgFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bgFrame:SetSize(w, h)
    local px = QUICore:GetPixelSize(bgFrame)
    bgFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    bgFrame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    bgFrame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)

    -- Helper for callers to update border color (used by CDM position fields)
    bgFrame.SetFieldBorderColor = function(self, r, g, b, a)
        pcall(self.SetBackdropBorderColor, self, r, g, b, a or 1)
    end

    -- Edit box inside
    local editBox = CreateFrame("EditBox", nil, bgFrame)
    editBox:SetHeight(editH)
    editBox:SetPoint("LEFT", inset, 0)
    editBox:SetPoint("RIGHT", -inset, 0)
    editBox:SetFont(GetFontPath(), options.fontSize or 11, "")
    editBox:SetTextColor(C_text_r, C_text_g, C_text_b, C_text_a)
    editBox:SetJustifyH(options.justifyH or "LEFT")
    editBox:SetAutoFocus(false)

    if options.maxLetters then
        editBox:SetMaxLetters(options.maxLetters)
    end

    if options.text then
        editBox:SetText(options.text)
    end

    -- Border hover/focus effects
    editBox:SetScript("OnEnter", function(self)
        pcall(bgFrame.SetBackdropBorderColor, bgFrame, activeBorder[1], activeBorder[2], activeBorder[3], activeBorder[4] or 1)
    end)
    editBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            pcall(bgFrame.SetBackdropBorderColor, bgFrame, border[1], border[2], border[3], border[4] or 1)
        end
    end)

    editBox:HookScript("OnEditFocusGained", function(self)
        pcall(bgFrame.SetBackdropBorderColor, bgFrame, activeBorder[1], activeBorder[2], activeBorder[3], activeBorder[4] or 1)
        if options.onEditFocusGained then options.onEditFocusGained(self) end
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        pcall(bgFrame.SetBackdropBorderColor, bgFrame, border[1], border[2], border[3], border[4] or 1)
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        if options.onEnterPressed then options.onEnterPressed(self) end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        if options.onEscapePressed then options.onEscapePressed(self) end
        self:ClearFocus()
    end)

    return bgFrame, editBox
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

-- Search timer reference (for cleanup)
GUI._searchTimer = nil

-- Create the search box widget for the top bar
function GUI:CreateSearchBox(parent)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(160, 20)
    local px = QUICore:GetPixelSize(container)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    container:SetBackdropColor(0.08, 0.10, 0.14, 1)
    container:SetBackdropBorderColor(0.25, 0.28, 0.32, 1)

    -- Search icon (magnifying glass character)
    local icon = container:CreateFontString(nil, "OVERLAY")
    SetFont(icon, 11, "", C.textMuted)
    icon:SetText("|TInterface\\Common\\UI-Searchbox-Icon:12:12:0:0|t")
    icon:SetPoint("LEFT", 6, 0)

    -- EditBox for search input
    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("LEFT", 24, 0)
    editBox:SetPoint("RIGHT", container, "RIGHT", -24, 0)
    editBox:SetHeight(16)
    editBox:SetAutoFocus(false)
    editBox:SetFont(GetFontPath(), 11, "")
    editBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    editBox:SetMaxLetters(50)

    -- Placeholder text
    local placeholder = editBox:CreateFontString(nil, "OVERLAY")
    SetFont(placeholder, 11, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.6})
    placeholder:SetText("Search settings...")
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
        -- OnTextChanged handler will trigger result clearing
    end)

    -- Text changed handler with debounce
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end

        local text = self:GetText()

        -- Show/hide placeholder and clear button
        placeholder:SetShown(text == "")
        clearBtn:SetShown(text ~= "")

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
        elseif text == "" then
            if container.onClear then
                container.onClear()
            end
        end
    end)

    -- Focus effects
    editBox:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(0.25, 0.28, 0.32, 1)
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
    local lowerSearch = searchTerm:lower()

    -- Search navigation items (tabs, subtabs, sections)
    for _, entry in ipairs(self.NavigationRegistry or {}) do
        local score = 0

        -- Check keywords (tab name, subtab name, section name)
        if entry.keywords then
            for _, keyword in ipairs(entry.keywords) do
                local lowerKeyword = (keyword or ""):lower()
                if lowerKeyword ~= "" and lowerKeyword:find(lowerSearch, 1, true) then
                    -- Higher score for exact/starts-with matches
                    if lowerKeyword == lowerSearch then
                        score = math.max(score, 200)
                    elseif lowerKeyword:sub(1, lowerSearch:len()) == lowerSearch then
                        score = math.max(score, 180)
                    else
                        score = math.max(score, 150)
                    end
                end
            end
        end

        if score > 0 then
            table.insert(navResults, {data = entry, score = score, isNavigation = true})
        end
    end

    -- Sort navigation results by specificity (sections > subtabs > tabs), then score
    table.sort(navResults, function(a, b)
        -- Navigation type priority: section (most specific) > subtab > tab
        local typeOrder = {section = 1, subtab = 2, tab = 3}
        local aOrder = typeOrder[a.data.navType] or 4
        local bOrder = typeOrder[b.data.navType] or 4
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        if a.score ~= b.score then
            return a.score > b.score
        end
        return (a.data.label or "") < (b.data.label or "")
    end)

    -- Search settings registry
    for _, entry in ipairs(self.SettingsRegistry) do
        local score = 0

        -- Label match (highest priority)
        local lowerLabel = (entry.label or ""):lower()
        if lowerLabel:find(lowerSearch, 1, true) then
            score = 100
            -- Bonus for starts-with match
            if lowerLabel:sub(1, lowerSearch:len()) == lowerSearch then
                score = score + 50
            end
        end

        -- Keyword match (secondary)
        if score == 0 and entry.keywords then
            for _, keyword in ipairs(entry.keywords) do
                if keyword:lower():find(lowerSearch, 1, true) then
                    score = 50
                    break
                end
            end
        end

        if score > 0 then
            table.insert(results, {data = entry, score = score})
        end
    end

    -- Sort settings results by score (highest first), then alphabetically
    table.sort(results, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return (a.data.label or "") < (b.data.label or "")
    end)

    -- Limit settings results
    if #results > SEARCH_MAX_RESULTS then
        for i = SEARCH_MAX_RESULTS + 1, #results do
            results[i] = nil
        end
    end

    -- Limit navigation results (keep fewer since they're shown prominently)
    local NAV_MAX_RESULTS = 10
    if #navResults > NAV_MAX_RESULTS then
        for i = NAV_MAX_RESULTS + 1, #navResults do
            navResults[i] = nil
        end
    end

    return results, navResults
end

-- Render search results into a content frame (for Search tab)
function GUI:RenderSearchResults(content, results, searchTerm, navResults)
    if not content then return end

    -- Clear previous child frames (unregister from widget sync first)
    -- Snapshot children before mutating: SetParent(nil) removes children
    -- from the list mid-iteration, causing select() to return nil.
    local kids = { content:GetChildren() }
    for _, child in ipairs(kids) do
        UnregisterWidgetInstance(child)
        child:Hide()
        child:SetParent(nil)
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

    local y = -10
    local PADDING = 15
    local FORM_ROW = 32

    -- Check if we have any results at all (either settings or navigation)
    local hasResults = (results and #results > 0) or (navResults and #navResults > 0)

    -- Index progress info
    local isIndexing = not GUI._searchIndexBuilt and GUI._searchIndexTotal > 0
    local indexProgress = GUI._searchIndexProgress or 0
    local indexTotal = GUI._searchIndexTotal or 0

    -- No results message
    if not hasResults then
        if searchTerm and searchTerm ~= "" then
            local noResults = content:CreateFontString(nil, "OVERLAY")
            SetFont(noResults, 12, "", C.textMuted)
            noResults:SetText("No settings found for \"" .. searchTerm .. "\"")
            noResults:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, noResults)
            y = y - 30

            if isIndexing then
                local tip = content:CreateFontString(nil, "OVERLAY")
                SetFont(tip, 10, "", {C.accent[1], C.accent[2], C.accent[3], 0.8})
                tip:SetText("Indexing settings... (" .. indexProgress .. "/" .. indexTotal .. " tabs) — more results may appear shortly")
                tip:SetPoint("TOPLEFT", PADDING, y)
                table.insert(content._fontStrings, tip)
                y = y - 30
            else
                local tip = content:CreateFontString(nil, "OVERLAY")
                SetFont(tip, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7})
                tip:SetText("Try different keywords")
                tip:SetPoint("TOPLEFT", PADDING, y)
                table.insert(content._fontStrings, tip)
                y = y - 30
            end
        else
            -- Empty state - show instructions
            local instructions = content:CreateFontString(nil, "OVERLAY")
            SetFont(instructions, 12, "", C.textMuted)
            instructions:SetText("Type at least 2 characters to search settings")
            instructions:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, instructions)
            y = y - 30

            if isIndexing then
                local tip2 = content:CreateFontString(nil, "OVERLAY")
                SetFont(tip2, 10, "", {C.accent[1], C.accent[2], C.accent[3], 0.8})
                tip2:SetText("Indexing settings... (" .. indexProgress .. "/" .. indexTotal .. " tabs)")
                tip2:SetPoint("TOPLEFT", PADDING, y)
                table.insert(content._fontStrings, tip2)
            else
                local tip2 = content:CreateFontString(nil, "OVERLAY")
                SetFont(tip2, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7})
                tip2:SetText("All settings indexed and ready to search")
                tip2:SetPoint("TOPLEFT", PADDING, y)
                table.insert(content._fontStrings, tip2)
            end
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

            -- Click to navigate
            local targetTabIndex = entry.tabIndex
            local targetSubTabIndex = entry.subTabIndex
            local targetSectionName = entry.sectionName
            navRow:SetScript("OnClick", function()
                GUI:NavigateTo(targetTabIndex, targetSubTabIndex, targetSectionName)
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

    -- Build composite group key from available metadata
    local function GetGroupKey(entry)
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

    -- Render grouped results with actual widgets (pcall ensures flag always resets on error)
    pcall(function()
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
        if groupData.tabIndex then
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

            local targetTabIndex = groupData.tabIndex
            local targetSubTabIndex = groupData.subTabIndex
            local targetSectionName = groupData.sectionName
            goBtn:SetScript("OnClick", function()
                GUI:NavigateTo(targetTabIndex, targetSubTabIndex, targetSectionName)
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

            if entry.widgetBuilder then
                local widget = entry.widgetBuilder(content)
                if widget then
                    widget:SetPoint("TOPLEFT", PADDING, y)
                    widget:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
                    y = y - FORM_ROW
                end
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

        y = y - 10  -- Gap between groups
    end
    end)  -- end pcall

    -- Re-enable auto-registration (guaranteed even if widget builder errored)
    GUI._suppressSearchRegistration = false

    -- Show indexing progress note at the bottom if still building
    if isIndexing then
        y = y - 10
        local progressNote = content:CreateFontString(nil, "OVERLAY")
        SetFont(progressNote, 10, "", {C.accent[1], C.accent[2], C.accent[3], 0.7})
        progressNote:SetText("Indexing... (" .. indexProgress .. "/" .. indexTotal .. " tabs) — more results may appear")
        progressNote:SetPoint("TOPLEFT", PADDING, y)
        table.insert(content._fontStrings, progressNote)
        y = y - 20
    end

    content:SetHeight(math.abs(y) + 20)
end

-- Clear search results display
function GUI:ClearSearchInTab(content)
    self:RenderSearchResults(content, nil, nil, nil)
end

local function EnsureTable(t, key)
    if not t[key] then
        t[key] = {}
    end
    return t[key]
end

function GUI:GetSidebarSubTabs(frame, tabIndex)
    if not frame or not frame.pages then return {} end
    local page = frame.pages[tabIndex]
    if not page then return {} end
    if page._subTabDefs then return page._subTabDefs end

    local group = page._subTabGroup
    if group and group.subTabDefs then
        page._subTabDefs = group.subTabDefs
        return page._subTabDefs
    end
    return {}
end

function GUI:IsSidebarSubTabSectionsHidden(frame, tabIndex, subTabIndex)
    if not frame or not tabIndex or not subTabIndex then return false end
    return frame._sidebarHiddenSections
        and frame._sidebarHiddenSections[tabIndex]
        and frame._sidebarHiddenSections[tabIndex][subTabIndex]
        and true or false
end

function GUI:SetSidebarSubTabSectionsHidden(frame, tabIndex, subTabIndex, hidden)
    if not frame or not tabIndex or not subTabIndex then return end
    frame._sidebarHiddenSections = frame._sidebarHiddenSections or {}
    frame._sidebarHiddenSections[tabIndex] = frame._sidebarHiddenSections[tabIndex] or {}
    frame._sidebarHiddenSections[tabIndex][subTabIndex] = hidden and true or nil
    self:RefreshSidebarTree(frame)
end

function GUI:RelayoutSidebarBottomItems(frame)
    if not frame or not frame.sidebar then return end
    local itemStride = 28
    for i, item in ipairs(frame._sidebarBottomItems or {}) do
        local y = (i - 1) * itemStride
        item:ClearAllPoints()
        item:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMLEFT", 0, y)
        item:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", -1, y)
    end

    local bottomCount = #(frame._sidebarBottomItems or {})
    local reserved = bottomCount > 0 and (bottomCount * itemStride + 8) or 6

    if frame.sidebarBottomSeparator then
        frame.sidebarBottomSeparator:ClearAllPoints()
        frame.sidebarBottomSeparator:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMLEFT", 8, reserved)
        frame.sidebarBottomSeparator:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", -8, reserved)
    end

    if frame.sidebarTreeScroll then
        frame.sidebarTreeScroll:ClearAllPoints()
        frame.sidebarTreeScroll:SetPoint("TOPLEFT", frame.sidebar, "TOPLEFT", 0, -5)
        frame.sidebarTreeScroll:SetPoint("TOPRIGHT", frame.sidebar, "TOPRIGHT", -1, -5)
        frame.sidebarTreeScroll:SetPoint("BOTTOMLEFT", frame.sidebar, "BOTTOMLEFT", 0, reserved + 8)
        frame.sidebarTreeScroll:SetPoint("BOTTOMRIGHT", frame.sidebar, "BOTTOMRIGHT", -1, reserved + 8)
    end
end

local function PlayCaretToggleAnimation(caret)
    if not caret then return end
    if not caret._toggleAnim then
        local ag = caret:CreateAnimationGroup()
        local fadeDown = ag:CreateAnimation("Alpha")
        fadeDown:SetOrder(1)
        fadeDown:SetFromAlpha(1)
        fadeDown:SetToAlpha(0.45)
        fadeDown:SetDuration(0.06)
        local fadeUp = ag:CreateAnimation("Alpha")
        fadeUp:SetOrder(2)
        fadeUp:SetFromAlpha(0.45)
        fadeUp:SetToAlpha(1)
        fadeUp:SetDuration(0.08)
        caret._toggleAnim = ag
    end
    if caret._toggleAnim:IsPlaying() then
        caret._toggleAnim:Stop()
    end
    caret._toggleAnim:Play()
end

local function CreateVectorCaret(parent, xOffset)
    if UIKit and UIKit.CreateChevronCaret then
        return UIKit.CreateChevronCaret(parent, {
            point = "RIGHT",
            relativeTo = parent,
            relativePoint = "RIGHT",
            xPixels = xOffset or -8,
            yPixels = 0,
            sizePixels = 10,
            lineWidthPixels = 6,
            lineHeightPixels = 1,
        })
    end

    local caret = CreateFrame("Frame", nil, parent)
    local function Pixels(value)
        if QUICore and QUICore.Pixels then
            return QUICore:Pixels(value, caret)
        end
        return value
    end

    caret:SetSize(Pixels(10), Pixels(10))
    if QUICore and QUICore.SetSnappedPoint then
        QUICore:SetSnappedPoint(caret, "RIGHT", parent, "RIGHT", xOffset or -8, 0)
    else
        caret:SetPoint("RIGHT", parent, "RIGHT", xOffset or -8, 0)
    end

    caret.line1 = caret:CreateTexture(nil, "OVERLAY")
    caret.line1:SetSize(Pixels(6), Pixels(1))
    caret.line1:SetColorTexture(1, 1, 1, 1)

    caret.line2 = caret:CreateTexture(nil, "OVERLAY")
    caret.line2:SetSize(Pixels(6), Pixels(1))
    caret.line2:SetColorTexture(1, 1, 1, 1)

    return caret
end

local function SetCaretVisual(caret, isExpanded, useAccent)
    if not caret then return end
    if UIKit and UIKit.SetChevronCaretExpanded and UIKit.SetChevronCaretColor then
        UIKit.SetChevronCaretExpanded(caret, isExpanded)
        if useAccent then
            UIKit.SetChevronCaretColor(caret, C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
        else
            UIKit.SetChevronCaretColor(caret, C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end
        return
    end

    local function Pixels(value)
        if QUICore and QUICore.Pixels then
            return QUICore:Pixels(value, caret)
        end
        return value
    end

    caret:SetSize(Pixels(10), Pixels(10))
    if caret.line1 then
        caret.line1:SetSize(Pixels(6), Pixels(1))
    end
    if caret.line2 then
        caret.line2:SetSize(Pixels(6), Pixels(1))
    end

    if caret.line1 and caret.line2 then
        if isExpanded then
            -- Down chevron (v)
            caret.line1:SetRotation(math.rad(-45))
            caret.line1:ClearAllPoints()
            caret.line1:SetPoint("CENTER", caret, "CENTER", -Pixels(2), 0)
            caret.line2:SetRotation(math.rad(45))
            caret.line2:ClearAllPoints()
            caret.line2:SetPoint("CENTER", caret, "CENTER", Pixels(2), 0)
        else
            -- Right chevron (>)
            caret.line1:SetRotation(math.rad(45))
            caret.line1:ClearAllPoints()
            caret.line1:SetPoint("CENTER", caret, "CENTER", -Pixels(1), Pixels(2))
            caret.line2:SetRotation(math.rad(-45))
            caret.line2:ClearAllPoints()
            caret.line2:SetPoint("CENTER", caret, "CENTER", -Pixels(1), -Pixels(2))
        end
    end
    if useAccent then
        if caret.line1 then
            caret.line1:SetVertexColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
        end
        if caret.line2 then
            caret.line2:SetVertexColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)
        end
    else
        if caret.line1 then
            caret.line1:SetVertexColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end
        if caret.line2 then
            caret.line2:SetVertexColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end
    end
end

local function CreateSidebarTreeRow(frame, rowType, key)
    local row = CreateFrame("Button", nil, frame.sidebarTreeContent)
    row._treeKey = key
    row._treeType = rowType
    row._treeProgress = 0
    row._treeTarget = 0
    row:Hide()

    row.hoverBg = row:CreateTexture(nil, "BACKGROUND")
    row.hoverBg:SetAllPoints()
    row.hoverBg:SetColorTexture(1, 1, 1, 0.04)
    row.hoverBg:Hide()

    row.activeBg = row:CreateTexture(nil, "ARTWORK")
    row.activeBg:SetAllPoints()
    row.activeBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
    row.activeBg:Hide()

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if rowType == "subtab" then
        SetFont(row.text, 10, "", C.textMuted)
        row.text:SetPoint("LEFT", row, "LEFT", 26, 0)
    else
        SetFont(row.text, 10, "", C.textMuted)
        row.text:SetPoint("LEFT", row, "LEFT", 40, 0)
    end
    row.text:SetJustifyH("LEFT")

    row.expandText = CreateVectorCaret(row, -8)
    row.expandText:Hide()

    row:SetScript("OnEnter", function(self)
        if not self._isActive then
            self.hoverBg:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self._isActive then
            self.hoverBg:Hide()
        end
    end)

    table.insert(frame._sidebarDynamicRows, row)
    return row
end

function GUI:StartSidebarTreeAnimation(frame)
    if not frame then return end
    if not frame._sidebarAnimFrame then
        frame._sidebarAnimFrame = CreateFrame("Frame", nil, frame)
    end

    local anim = frame._sidebarAnimFrame
    anim:SetScript("OnUpdate", function(self, elapsed)
        local host = self._hostFrame
        if not host then
            self:SetScript("OnUpdate", nil)
            return
        end

        local duration = GUI._sidebarAnimDuration or 0.16
        local step = (duration > 0) and (elapsed / duration) or 1
        local anyActive = false

        for _, row in ipairs(host._sidebarDynamicRows or {}) do
            local target = row._treeTarget or 0
            local progress = row._treeProgress or 0
            if math.abs(progress - target) > 0.001 then
                if target > progress then
                    progress = math.min(target, progress + step)
                else
                    progress = math.max(target, progress - step)
                end
                row._treeProgress = progress
                if progress > 0 then
                    row:Show()
                elseif target <= 0 then
                    row:Hide()
                end
                anyActive = true
            end
        end

        GUI:RelayoutSidebarTree(host)
        if not anyActive then
            self:SetScript("OnUpdate", nil)
        end
    end)
    anim._hostFrame = frame
end

function GUI:RelayoutSidebarTree(frame)
    if not frame or not frame.sidebarTreeContent then return end
    local y = -5
    local spacing = 2
    local h1 = GUI._sidebarRowHeights.level1
    local h2 = GUI._sidebarRowHeights.level2
    local h3 = GUI._sidebarRowHeights.level3

    local function IsRowAnimating(row)
        if not row then return false end
        local p = row._treeProgress or 0
        local t = row._treeTarget or 0
        return p > 0.001 or t > 0.001
    end

    for _, tab in ipairs(frame._sidebarTopTabs or {}) do
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", frame.sidebarTreeContent, "TOPLEFT", 0, y)
        tab:SetPoint("TOPRIGHT", frame.sidebarTreeContent, "TOPRIGHT", -1, y)
        tab:SetHeight(h1)
        y = y - h1 - spacing

        local subDefs = self:GetSidebarSubTabs(frame, tab.index)
        local subRowsByTab = frame._sidebarTreeSubRows and frame._sidebarTreeSubRows[tab.index]
        local sectionRowsByTab = frame._sidebarTreeSectionRows and frame._sidebarTreeSectionRows[tab.index]
        local isTabExpanded = frame._sidebarExpandedTabs and frame._sidebarExpandedTabs[tab.index]
        local hasAnimatingSubRows = false

        for _, subDef in ipairs(subDefs) do
            local subRow = subRowsByTab and subRowsByTab[subDef.index]
            if IsRowAnimating(subRow) then
                hasAnimatingSubRows = true
                break
            end
        end

        if isTabExpanded or hasAnimatingSubRows then
            for _, subDef in ipairs(subDefs) do
                local subRow = subRowsByTab and subRowsByTab[subDef.index]
                if IsRowAnimating(subRow) then
                    local p = math.max(0, math.min(1, subRow._treeProgress or 0))
                    local rowH = math.max(1, h2 * p)
                    subRow:ClearAllPoints()
                    subRow:SetPoint("TOPLEFT", frame.sidebarTreeContent, "TOPLEFT", 0, y)
                    subRow:SetPoint("TOPRIGHT", frame.sidebarTreeContent, "TOPRIGHT", -1, y)
                    subRow:SetHeight(rowH)
                    subRow:SetAlpha(p)
                    y = y - rowH - (spacing * p)

                    local sectionRowsBySub = sectionRowsByTab and sectionRowsByTab[subDef.index]
                    local isSubExpanded = frame._sidebarExpandedSubTabs
                        and frame._sidebarExpandedSubTabs[tab.index]
                        and frame._sidebarExpandedSubTabs[tab.index][subDef.index]
                    local hasAnimatingSections = false
                    if sectionRowsBySub then
                        for _, secRow in pairs(sectionRowsBySub) do
                            if IsRowAnimating(secRow) then
                                hasAnimatingSections = true
                                break
                            end
                        end
                    end

                    if isSubExpanded or hasAnimatingSections then
                        local sectionNames = self:GetOrderedSections(tab.index, subDef.index)
                        local seenNames = {}
                        for _, sectionName in ipairs(sectionNames) do
                            seenNames[sectionName] = true
                            local secRow = sectionRowsBySub and sectionRowsBySub[sectionName]
                            if IsRowAnimating(secRow) then
                                local sp = math.max(0, math.min(1, secRow._treeProgress or 0))
                                local secH = math.max(1, h3 * sp)
                                secRow:ClearAllPoints()
                                secRow:SetPoint("TOPLEFT", frame.sidebarTreeContent, "TOPLEFT", 0, y)
                                secRow:SetPoint("TOPRIGHT", frame.sidebarTreeContent, "TOPRIGHT", -1, y)
                                secRow:SetHeight(secH)
                                secRow:SetAlpha(sp)
                                y = y - secH - (spacing * sp)
                            end
                        end

                        -- Fallback for any animated section row not present in current ordered list.
                        if sectionRowsBySub then
                            for sectionName, secRow in pairs(sectionRowsBySub) do
                                if not seenNames[sectionName] and IsRowAnimating(secRow) then
                                    local sp = math.max(0, math.min(1, secRow._treeProgress or 0))
                                    local secH = math.max(1, h3 * sp)
                                    secRow:ClearAllPoints()
                                    secRow:SetPoint("TOPLEFT", frame.sidebarTreeContent, "TOPLEFT", 0, y)
                                    secRow:SetPoint("TOPRIGHT", frame.sidebarTreeContent, "TOPRIGHT", -1, y)
                                    secRow:SetHeight(secH)
                                    secRow:SetAlpha(sp)
                                    y = y - secH - (spacing * sp)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    frame.sidebarTreeContent:SetHeight(math.max(1, math.abs(y) + 12))
end

function GUI:RefreshSidebarTree(frame)
    frame = frame or self.MainFrame
    if not frame or not frame.sidebarTreeContent then return end

    frame._sidebarExpandedTabs = frame._sidebarExpandedTabs or {}
    frame._sidebarExpandedSubTabs = frame._sidebarExpandedSubTabs or {}
    frame._sidebarTreeSubRows = frame._sidebarTreeSubRows or {}
    frame._sidebarTreeSectionRows = frame._sidebarTreeSectionRows or {}
    frame._sidebarDynamicRows = frame._sidebarDynamicRows or {}

    local activeTab = frame.activeTab
    local activeSubTab
    if activeTab and frame.pages and frame.pages[activeTab] and frame.pages[activeTab]._subTabGroup then
        activeSubTab = frame.pages[activeTab]._subTabGroup.selectedTab
    end

    local activeSectionKey = frame._sidebarActiveSectionKey
    local touched = {}

    for _, tab in ipairs(frame._sidebarTopTabs or {}) do
        local page = frame.pages and frame.pages[tab.index]
        local subDefs = self:GetSidebarSubTabs(frame, tab.index)
        local hasSubTabs = (#subDefs > 0) or (tab._hasSubTabsHint and true or false)

        if tab.expandText then
            if hasSubTabs then
                local isExpanded = frame._sidebarExpandedTabs and frame._sidebarExpandedTabs[tab.index]
                if tab._lastCaretExpanded ~= isExpanded then
                    tab._lastCaretExpanded = isExpanded
                    PlayCaretToggleAnimation(tab.expandText)
                end
                SetCaretVisual(tab.expandText, isExpanded, isExpanded)
                tab.expandText:Show()
            else
                tab.expandText:Hide()
            end
        end

        if hasSubTabs and frame._sidebarExpandedTabs[tab.index] then
            local tabSubRows = EnsureTable(frame._sidebarTreeSubRows, tab.index)
            local tabSectionRows = EnsureTable(frame._sidebarTreeSectionRows, tab.index)
            local expandedSubs = EnsureTable(frame._sidebarExpandedSubTabs, tab.index)

            for _, subDef in ipairs(subDefs) do
                local rowKey = tab.index .. ":" .. subDef.index
                local subRow = tabSubRows[subDef.index]
                if not subRow then
                    subRow = CreateSidebarTreeRow(frame, "subtab", rowKey)
                    tabSubRows[subDef.index] = subRow
                    subRow:SetScript("OnClick", function(selfRow)
                        local tabIndex = selfRow.tabIndex
                        local subTabIndex = selfRow.subTabIndex
                        if not tabIndex or not subTabIndex then return end
                        frame._sidebarExpandedTabs[tabIndex] = true
                        frame._sidebarExpandedSubTabs[tabIndex] = frame._sidebarExpandedSubTabs[tabIndex] or {}
                        local isExpanded = frame._sidebarExpandedSubTabs[tabIndex][subTabIndex] and true or false
                        -- Read current active state at click time, not from stale closure
                        local curActiveTab = frame.activeTab
                        local curActiveSubTab
                        if curActiveTab and frame.pages and frame.pages[curActiveTab] and frame.pages[curActiveTab]._subTabGroup then
                            curActiveSubTab = frame.pages[curActiveTab]._subTabGroup.selectedTab
                        end
                        local isActive = (curActiveTab == tabIndex and curActiveSubTab == subTabIndex)
                        if isExpanded and isActive then
                            -- Check if content is scrolled away from top
                            local regKey = GetSectionRegistryKey(tabIndex, subTabIndex)
                            local order = GUI.SectionRegistryOrder[regKey]
                            local registry = GUI.SectionRegistry[regKey]
                            local scrollFrame
                            if order and order[1] and registry and registry[order[1]] then
                                scrollFrame = registry[order[1]].scrollParent
                            end
                            local currentScroll = scrollFrame and scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll() or 0
                            if currentScroll > 5 then
                                -- Not at top — scroll to top and clear section highlight
                                frame._sidebarManualSectionSelection = true
                                scrollFrame:SetVerticalScroll(0)
                                frame._sidebarActiveSectionKey = nil
                                GUI:RefreshSidebarTree(frame)
                                C_Timer.After(0.1, function()
                                    frame._sidebarManualSectionSelection = nil
                                end)
                                return
                            end
                            -- Already at top (or no sections) — collapse
                            frame._sidebarExpandedSubTabs[tabIndex][subTabIndex] = false
                            frame._sidebarActiveSectionKey = nil
                            GUI:RefreshSidebarTree(frame)
                            return
                        end
                        frame._sidebarExpandedSubTabs[tabIndex][subTabIndex] = true
                        frame._sidebarActiveSectionKey = nil
                        GUI:NavigateTo(tabIndex, subTabIndex, nil)
                    end)
                end

                subRow.tabIndex = tab.index
                subRow.subTabIndex = subDef.index
                subRow.text:SetText(subDef.name or ("Sub Tab " .. subDef.index))
                subRow._isActive = (activeTab == tab.index and activeSubTab == subDef.index)
                if subRow._isActive then
                    subRow.text:SetTextColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
                    subRow.activeBg:Show()
                    subRow.hoverBg:Hide()
                else
                    subRow.text:SetTextColor(C_text_r, C_text_g, C_text_b, 0.9)
                    subRow.activeBg:Hide()
                end

                local sectionsHidden = self:IsSidebarSubTabSectionsHidden(frame, tab.index, subDef.index)
                local sectionNames = sectionsHidden and {} or self:GetOrderedSections(tab.index, subDef.index)
                local hasSections = (not sectionsHidden) and (#sectionNames > 0)
                if hasSections then
                    local isExpanded = expandedSubs[subDef.index] and true or false
                    if subRow._lastCaretExpanded ~= isExpanded then
                        subRow._lastCaretExpanded = isExpanded
                        PlayCaretToggleAnimation(subRow.expandText)
                    end
                    SetCaretVisual(subRow.expandText, isExpanded, isExpanded)
                    subRow.expandText:Show()
                else
                    subRow.expandText:Hide()
                end

                subRow._treeTarget = 1
                touched[subRow] = true
                if subRow._treeProgress <= 0 then
                    subRow._treeProgress = 0
                    subRow:Show()
                end

                if hasSections and expandedSubs[subDef.index] then
                    local sectionRowBySub = EnsureTable(tabSectionRows, subDef.index)
                    for _, sectionName in ipairs(sectionNames) do
                        local sectionKey = tab.index .. ":" .. subDef.index .. ":" .. sectionName
                        local secRow = sectionRowBySub[sectionName]
                        if not secRow then
                            secRow = CreateSidebarTreeRow(frame, "section", sectionKey)
                            sectionRowBySub[sectionName] = secRow
                            secRow:SetScript("OnClick", function(selfRow)
                                if not selfRow.tabIndex or not selfRow.subTabIndex or not selfRow.sectionName then return end
                                frame._sidebarExpandedTabs[selfRow.tabIndex] = true
                                frame._sidebarExpandedSubTabs[selfRow.tabIndex] = frame._sidebarExpandedSubTabs[selfRow.tabIndex] or {}
                                frame._sidebarExpandedSubTabs[selfRow.tabIndex][selfRow.subTabIndex] = true
                                frame._sidebarActiveSectionKey = selfRow._treeKey
                                GUI:NavigateTo(selfRow.tabIndex, selfRow.subTabIndex, selfRow.sectionName)
                                GUI:RefreshSidebarTree(frame)
                            end)
                        end

                        secRow.tabIndex = tab.index
                        secRow.subTabIndex = subDef.index
                        secRow.sectionName = sectionName
                        secRow.text:SetText(sectionName)
                        secRow.expandText:Hide()
                        secRow._isActive = (activeSectionKey == secRow._treeKey)
                        if secRow._isActive then
                            secRow.text:SetTextColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
                            secRow.activeBg:Show()
                            secRow.hoverBg:Hide()
                        else
                            secRow.text:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
                            secRow.activeBg:Hide()
                        end

                        secRow._treeTarget = 1
                        touched[secRow] = true
                        if secRow._treeProgress <= 0 then
                            secRow._treeProgress = 0
                            secRow:Show()
                        end
                    end
                end
            end
        end
    end

    for _, row in ipairs(frame._sidebarDynamicRows or {}) do
        if not touched[row] then
            row._treeTarget = 0
        end
    end

    self:StartSidebarTreeAnimation(frame)
    self:RelayoutSidebarTree(frame)
end

function GUI:ToggleSidebarTabExpanded(frame, tabIndex, forceExpanded)
    if not frame then return end
    frame._sidebarExpandedTabs = frame._sidebarExpandedTabs or {}
    local current = frame._sidebarExpandedTabs[tabIndex]
    local nextValue = (forceExpanded ~= nil) and forceExpanded or (not current)
    frame._sidebarExpandedTabs[tabIndex] = nextValue
    if not nextValue and frame._sidebarExpandedSubTabs then
        frame._sidebarExpandedSubTabs[tabIndex] = nil
    end
    self:RefreshSidebarTree(frame)
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
    self.SectionNavigateHandlers = {}
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
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:EnableMouse(true)

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

    -- Sidebar background
    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(unpack(C.bgContent))

    -- Right border on sidebar
    local sidebarBorder = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebarBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarBorder:SetWidth(1)
    sidebarBorder:SetColorTexture(C_border_r, C_border_g, C_border_b, C_border_a)

    frame.sidebar = sidebar
    frame._sidebarItems = {}       -- All sidebar items (tabs + bottom items)
    frame._sidebarTopTabs = {}     -- Top-level tab rows rendered in the tree
    frame._sidebarBottomItems = {} -- Bottom section items (search, action buttons)
    frame._sidebarDynamicRows = {} -- Level 2/3 rows (subtabs + sections)
    frame._sidebarExpandedTabs = {}
    frame._sidebarExpandedSubTabs = {}

    local sidebarTreeScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    sidebarTreeScroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -5)
    sidebarTreeScroll:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, -5)
    sidebarTreeScroll:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, 40)
    sidebarTreeScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 40)
    ns.ApplyScrollWheel(sidebarTreeScroll)

    local sidebarTreeContent = CreateFrame("Frame", nil, sidebarTreeScroll)
    sidebarTreeContent:SetWidth(SIDEBAR_W - 1)
    sidebarTreeContent:SetHeight(1)
    sidebarTreeScroll:SetScrollChild(sidebarTreeContent)
    sidebarTreeScroll:SetScript("OnSizeChanged", function(self, width)
        sidebarTreeContent:SetWidth(width)
        GUI:RelayoutSidebarTree(frame)
    end)

    local treeScrollBar = sidebarTreeScroll.ScrollBar
    if treeScrollBar then
        treeScrollBar:SetPoint("TOPLEFT", sidebarTreeScroll, "TOPRIGHT", 2, -16)
        treeScrollBar:SetPoint("BOTTOMLEFT", sidebarTreeScroll, "BOTTOMRIGHT", 2, 16)
        treeScrollBar:SetWidth(7)
        if treeScrollBar.Track then
            treeScrollBar.Track:SetAlpha(0)
        end
        local thumb = treeScrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
            thumb:SetWidth(3)
            thumb:SetHeight(26)
        end
        local scrollUp = treeScrollBar.ScrollUpButton or treeScrollBar.Back
        local scrollDown = treeScrollBar.ScrollDownButton or treeScrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end
    end

    local sidebarBottomSeparator = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarBottomSeparator:SetHeight(1)
    sidebarBottomSeparator:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.6)

    frame.sidebarTreeScroll = sidebarTreeScroll
    frame.sidebarTreeContent = sidebarTreeContent
    frame.sidebarBottomSeparator = sidebarBottomSeparator
    self:RelayoutSidebarBottomItems(frame)

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
    contentArea:SetPoint("BOTTOMRIGHT", -10, 10)
    contentArea:EnableMouse(false)

    -- Content background
    local contentBg = contentArea:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints()
    contentBg:SetColorTexture(unpack(C.bgContent))

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
-- ADD TAB (Sidebar item style - vertical list on left)
---------------------------------------------------------------------------
function GUI:AddTab(frame, name, pageCreateFunc, isBottomItem)
    local index = #frame.tabs + 1

    -- Create sidebar item button
    local tabParent = isBottomItem and frame.sidebar or frame.sidebarTreeContent
    local tab = CreateFrame("Button", nil, tabParent)
    tab:SetHeight(26)
    tab.index = index
    tab.name = name
    tab.isBottomItem = isBottomItem

    -- Left active indicator bar (3px wide, hidden by default)
    tab.indicator = tab:CreateTexture(nil, "OVERLAY")
    tab.indicator:SetPoint("TOPLEFT", 0, 0)
    tab.indicator:SetPoint("BOTTOMLEFT", 0, 0)
    tab.indicator:SetWidth(3)
    tab.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    tab.indicator:Hide()

    -- Hover/active background
    tab.hoverBg = tab:CreateTexture(nil, "BACKGROUND")
    tab.hoverBg:SetAllPoints()
    tab.hoverBg:SetColorTexture(1, 1, 1, 0.05)
    tab.hoverBg:Hide()

    -- Tab text - left-aligned with padding after indicator
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(tab.text, 11, "", C.tabNormal)
    tab.text:SetText(name)
    tab.text:SetPoint("LEFT", tab, "LEFT", 15, 0)
    tab.text:SetJustifyH("LEFT")

    if not isBottomItem then
        tab.expandText = CreateVectorCaret(tab, -8)
        tab.expandText:Hide()
    end

    -- Position in sidebar
    if isBottomItem then
        table.insert(frame._sidebarBottomItems, tab)
        self:RelayoutSidebarBottomItems(frame)
    else
        table.insert(frame._sidebarTopTabs, tab)
    end

    frame.tabs[index] = tab
    frame.pages[index] = {
        createFunc = pageCreateFunc,
        frame = nil
    }
    frame._sidebarItems[index] = tab

    -- Click handler
    tab:SetScript("OnClick", function()
        if not isBottomItem then
            frame._sidebarExpandedTabs = frame._sidebarExpandedTabs or {}
            local isExpanded = frame._sidebarExpandedTabs[index] and true or false
            if isExpanded then
                GUI:ToggleSidebarTabExpanded(frame, index, false)
                return
            end

            -- Select first so lazy-built pages can expose sub-tab metadata immediately.
            GUI:SelectTab(frame, index)
            local subTabs = GUI:GetSidebarSubTabs(frame, index)
            if #subTabs > 0 then
                -- Opening a level-1 branch should not auto-cascade to level-3.
                if frame._sidebarExpandedSubTabs then
                    frame._sidebarExpandedSubTabs[index] = nil
                end
                GUI:ToggleSidebarTabExpanded(frame, index, true)
            else
                GUI:RefreshSidebarTree(frame)
            end
        else
            GUI:SelectTab(frame, index)
        end
    end)

    tab:SetScript("OnEnter", function(self)
        if frame.activeTab ~= self.index then
            self.text:SetTextColor(C_tabHover_r, C_tabHover_g, C_tabHover_b, C_tabHover_a)
            self.hoverBg:Show()
        end
    end)

    tab:SetScript("OnLeave", function(self)
        if frame.activeTab ~= self.index then
            self.text:SetTextColor(C_tabNormal_r, C_tabNormal_g, C_tabNormal_b, C_tabNormal_a)
            self.hoverBg:Hide()
        end
    end)

    -- Select first tab by default
    if index == 1 then
        GUI:SelectTab(frame, 1)
        frame._sidebarExpandedTabs[index] = true
        GUI:RefreshSidebarTree(frame)
    elseif not isBottomItem then
        GUI:RefreshSidebarTree(frame)
    end

    return tab
end

---------------------------------------------------------------------------
-- ADD ACTION BUTTON (Sidebar bottom item - executes action, no page)
---------------------------------------------------------------------------
function GUI:AddActionButton(frame, name, onClick, accentColor)
    local index = #frame.tabs + 1

    -- Create sidebar item in bottom section
    local btn = CreateFrame("Button", nil, frame.sidebar)
    btn:SetHeight(26)
    btn.index = index
    btn.name = name
    btn.isActionButton = true

    local borderColor = {C.accent[1], C.accent[2], C.accent[3], 1}
    btn.borderColor = borderColor
    btn.bgColor = {0.05, 0.08, 0.12, 1}

    -- Hover background
    btn.hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    btn.hoverBg:SetAllPoints()
    btn.hoverBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.08)
    btn.hoverBg:Hide()

    -- Button text - left-aligned, mint colored
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(btn.text, 11, "", borderColor)
    btn.text:SetText(name)
    btn.text:SetPoint("LEFT", btn, "LEFT", 15, 0)
    btn.text:SetJustifyH("LEFT")

    -- Position at bottom of sidebar, anchored upward
    table.insert(frame._sidebarBottomItems, btn)
    self:RelayoutSidebarBottomItems(frame)

    -- Store in tabs array but mark as action button
    frame.tabs[index] = btn
    frame.pages[index] = nil
    frame._sidebarItems[index] = btn

    -- Click handler - execute action
    btn:SetScript("OnClick", function()
        if onClick then
            onClick()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        self.hoverBg:Show()
        self.text:SetTextColor(C.accentHover[1], C.accentHover[2], C.accentHover[3], 1)
    end)

    btn:SetScript("OnLeave", function(self)
        self.hoverBg:Hide()
        self.text:SetTextColor(unpack(self.borderColor))
    end)

    return btn
end

---------------------------------------------------------------------------
-- SELECT TAB
---------------------------------------------------------------------------
function GUI:SelectTab(frame, index)
    -- Skip if this is an action button (no page to show)
    local targetTab = frame.tabs[index]
    if targetTab and targetTab.isActionButton then
        return
    end

    -- Start background index build if not done yet (non-blocking)
    if index == self._searchTabIndex and self._allTabsAdded and not self._searchIndexBuilt then
        self:StartBackgroundIndexBuild()
    end

    -- Auto-focus search input when navigating to Search tab
    if index == self._searchTabIndex then
        C_Timer.After(0, function()
            local page = frame.pages[index]
            if page and page.frame and page.frame.searchBox and page.frame.searchBox.editBox then
                page.frame.searchBox.editBox:SetFocus()
            end
        end)
    end

    -- Clear search if active
    if frame._searchActive then
        if frame.searchBox and frame.searchBox.editBox then
            frame.searchBox.editBox:SetText("")
        end
        self:ClearSearchResults()
    end

    -- Deselect previous sidebar item
    if frame.activeTab then
        local prevTab = frame.tabs[frame.activeTab]
        if prevTab and not prevTab.isActionButton then
            prevTab.text:SetTextColor(C_tabNormal_r, C_tabNormal_g, C_tabNormal_b, C_tabNormal_a)
            if prevTab.indicator then prevTab.indicator:Hide() end
            if prevTab.hoverBg then prevTab.hoverBg:Hide() end
        end

        if frame.pages[frame.activeTab] and frame.pages[frame.activeTab].frame then
            frame.pages[frame.activeTab].frame:Hide()
        end
    end

    -- Select new sidebar item
    frame.activeTab = index
    local tab = frame.tabs[index]
    if tab and not tab.isActionButton then
        tab.text:SetTextColor(C_accent_r, C_accent_g, C_accent_b, C_accent_a)
        if tab.indicator then tab.indicator:Show() end
        if tab.hoverBg then tab.hoverBg:Show() end
    end

    -- Create/show page
    local page = frame.pages[index]
    if page then
        if not page.frame then
            page.frame = CreateFrame("Frame", nil, frame.contentArea)
            page.frame:SetAllPoints()
            page.frame:EnableMouse(false)
            if page.createFunc then
                local activeTopTab = frame.tabs[index]
                if activeTopTab and activeTopTab.name then
                    GUI:SetSearchContext({
                        tabIndex = index,
                        tabName = activeTopTab.name,
                    })
                end
                page.createFunc(page.frame)
                page.built = true
            end
        end

        -- Capture sub-tab group created during page build
        if GUI._lastSubTabGroup then
            page._subTabGroup = GUI._lastSubTabGroup
            page._subTabDefs = page._subTabGroup.subTabDefs
            GUI._lastSubTabGroup = nil
        end

        if page._subTabGroup then
            page._subTabDefs = page._subTabGroup.subTabDefs or page._subTabDefs
            page._subTabGroup._onSelect = function(subIndex)
                if not frame then return end
                if not frame._sidebarPendingSectionSelection then
                    frame._sidebarActiveSectionKey = nil
                end
                GUI:RefreshSidebarTree(frame)
                if not frame._sidebarPendingSectionSelection then
                    C_Timer.After(0, function()
                        local key = GetSectionRegistryKey(index, subIndex)
                        local order = GUI.SectionRegistryOrder[key]
                        local reg = GUI.SectionRegistry[key]
                        if order and order[1] and reg and reg[order[1]] and reg[order[1]].scrollParent then
                            GUI:UpdateSidebarSectionHighlightFromScroll(reg[order[1]].scrollParent)
                        end
                    end)
                end
            end
        end

        page.frame:Show()

        -- Legacy top sub-tab bar is deprecated; sidebar tree is now the sole navigator.
        if frame._activeSubTabGroup then
            frame._activeSubTabGroup:Hide()
        end
        if page._subTabGroup then
            page._subTabGroup:Hide()
        end
        frame._activeSubTabGroup = nil
        frame.subTabBar:Hide()
        frame.contentArea:ClearAllPoints()
        frame.contentArea:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT", 5, 0)
        frame.contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

        -- Force OnShow scripts to fire on all children (for refresh purposes)
        -- Uses select() to avoid temporary table allocations on each recursion level
        local function TriggerOnShow(f)
            if f.GetScript and f:GetScript("OnShow") then
                f:GetScript("OnShow")(f)
            end
            if f.GetNumChildren then
                local n = f:GetNumChildren()
                for i = 1, n do
                    TriggerOnShow(select(i, f:GetChildren()))
                end
            end
        end
        TriggerOnShow(page.frame)
        GUI:ApplyTabFont(page.frame)

        -- Some tab widgets build rows asynchronously after OnShow; apply a second pass.
        C_Timer.After(0, function()
            if page.frame and page.frame:IsShown() then
                GUI:ApplyTabFont(page.frame)
                GUI:RefreshSidebarTree(frame)
            end
        end)
    end

    GUI:RefreshSidebarTree(frame)
end

---------------------------------------------------------------------------
-- SHOW FUNCTION
---------------------------------------------------------------------------
function GUI:Show()
    if not self.MainFrame then
        self:InitializeOptions()
    end
    self.MainFrame:Show()
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
    -- Save current state
    local savedTab = self.MainFrame.activeTab or 1
    local wasShown = self.MainFrame:IsShown()

    -- Save current position so the window doesn't jump back to center
    local point, _, relPoint, xOfs, yOfs = self.MainFrame:GetPoint()

    -- Tear down old frame
    self.MainFrame:Hide()
    self.MainFrame:SetParent(nil)
    self.MainFrame = nil

    -- Reset search index state (will be rebuilt from dedup keys)
    self._searchIndexBuilt = false
    self._allTabsAdded = false
    self.SettingsRegistry = {}
    self.SettingsRegistryKeys = {}

    -- Recreate
    self:InitializeOptions()

    -- Restore position
    if point and self.MainFrame then
        self.MainFrame:ClearAllPoints()
        self.MainFrame:SetPoint(point, UIParent, relPoint, xOfs, yOfs)
    end

    -- Restore tab
    if savedTab and self.MainFrame then
        GUI:SelectTab(self.MainFrame, savedTab)
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

-- Store reference
QUI.GUI = GUI
