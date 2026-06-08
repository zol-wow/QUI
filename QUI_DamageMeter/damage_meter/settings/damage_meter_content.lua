--[[
    QUI Options - Native Damage Meter
    Builds the "Damage Meter (Native)" sub-page. Migrated to V3 body pattern
    (CreateAccentDotLabel + CreateSettingsCardGroup + BuildSettingRow). The
    override-row machinery is preserved: in Per-Window mode each appearance
    widget shows an Override toggle paired with the actual control inside a
    full-width row cell. In Global mode rows pair 2-per-row normally.

    Owns: visibility dropdown, refresh rates, appearance (bars/fonts/colors),
    session timer, spell history (icon strip + bar window), windows list.
]]

-- luacheck: globals C_Timer

local _, ns = ...
local QUI = _G.QUI
local GUI = QUI and QUI.GUI

local Shared   = ns.QUI_Options
local Opts     = Shared
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema   = Settings and Settings.Schema

local PAD = (Opts and Opts.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14
local FORM_ROW = 32

local NATIVE_DM_SUBPAGE_INDEX = 7  -- gameplay tile slot, immediately after Combat (6)

local function GetMod()
    return ns.QUI_DamageMeter or _G.QUI_DamageMeter
end

local function GetTextureList()
    local LSM = ns.LSM
    local list = { { value = nil, text = "(default)" } }
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            table.insert(list, { value = name, text = name })
        end
    end
    return list
end

local function GetFontList()
    local LSM = ns.LSM
    local list = { { value = nil, text = "(default)" } }
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            table.insert(list, { value = name, text = name })
        end
    end
    return list
end

local function DB()
    local q = _G.QUI
    if q and q.db and q.db.profile and q.db.profile.damageMeter then
        return q.db.profile.damageMeter.native
    end
    return nil
end

-- ===========================================================================
-- Per-window override state
-- ===========================================================================
local editingWindowID = 0
local tabContentRef = nil
local BuildNativeDamageMeterTab  -- forward

local function RebuildPage()
    if not tabContentRef then return end
    for _, child in ipairs({ tabContentRef:GetChildren() }) do
        if child then
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(nil)
        end
    end
    local SettingsNS = ns.Settings
    local Adapters   = SettingsNS and SettingsNS.RenderAdapters
    if Adapters and type(Adapters.RenderWithTileChrome) == "function" then
        Adapters.RenderWithTileChrome(function()
            BuildNativeDamageMeterTab(tabContentRef)
        end)
    else
        BuildNativeDamageMeterTab(tabContentRef)
    end
end

local function ToggleOverride(globalTable, key, on)
    if editingWindowID == 0 then return end
    local d = DB()
    if not d then return end
    d.appearance.perWindow = d.appearance.perWindow or {}
    d.appearance.perWindow[editingWindowID] = d.appearance.perWindow[editingWindowID] or {}
    local pw = d.appearance.perWindow[editingWindowID]
    if on then
        if pw[key] == nil then
            pw[key] = globalTable[key]
        end
    else
        pw[key] = nil
    end
end

local function PerWindowHasOverride(key)
    if editingWindowID == 0 then return false end
    local d = DB()
    if not (d and d.appearance and d.appearance.perWindow) then return false end
    local pw = d.appearance.perWindow[editingWindowID]
    return pw and pw[key] ~= nil
end

local function GetOverrideTarget()
    local d = DB()
    if not d then return nil end
    d.appearance.perWindow = d.appearance.perWindow or {}
    d.appearance.perWindow[editingWindowID] = d.appearance.perWindow[editingWindowID] or {}
    return d.appearance.perWindow[editingWindowID]
end

local function NestedHasOverride(parentKey, leafKey)
    if editingWindowID == 0 then return false end
    local d = DB()
    if not (d and d.appearance and d.appearance.perWindow) then return false end
    local pw = d.appearance.perWindow[editingWindowID]
    if not (pw and pw[parentKey]) then return false end
    return pw[parentKey][leafKey] ~= nil
end

local function GetNestedOverrideTarget(parentKey)
    local d = DB()
    if not d then return nil end
    d.appearance.perWindow = d.appearance.perWindow or {}
    d.appearance.perWindow[editingWindowID] = d.appearance.perWindow[editingWindowID] or {}
    local pw = d.appearance.perWindow[editingWindowID]
    pw[parentKey] = pw[parentKey] or {}
    return pw[parentKey]
end

local function ToggleNestedOverride(globalParent, parentKey, leafKey, on)
    if editingWindowID == 0 then return end
    local target = GetNestedOverrideTarget(parentKey)
    if not target then return end
    if on then
        if target[leafKey] == nil then
            local g = globalParent[parentKey]
            target[leafKey] = g and g[leafKey]
        end
    else
        target[leafKey] = nil
    end
end

-- ===========================================================================
-- V3 layout helpers
-- ===========================================================================
local function MakeLayout(content)
    local y = -10
    local L = {}
    function L.headerAt(text)
        local h = Opts.CreateAccentDotLabel(content, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end
    function L.sectionAt()
        local c = Opts.CreateSettingsCardGroup(content, y)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        c.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        return c
    end
    function L.closeSection(c)
        c.Finalize()
        y = y - c.frame:GetHeight() - SECTION_GAP
    end
    function L.placeCustom(frame, height)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        frame:SetHeight(height)
        y = y - height - SECTION_GAP
    end
    function L.finish()
        content:SetHeight(math.abs(y) + 10)
        return content:GetHeight()
    end
    return L
end

local function row(parent, label, widget, desc)
    return Opts.BuildSettingRow(parent, label, widget, desc)
end

-- ===========================================================================
-- Override widget wrapper: composes toggle + widget into a single composite
-- frame suitable for the right slot of a BuildSettingRow cell. In Global mode
-- (editingWindowID == 0), no toggle is shown — the widget is returned bare.
-- In Per-Window mode, toggle goes left, widget right, with in-place rebuild
-- on toggle flip so the bind table swaps without a page-wide repaint.
-- ===========================================================================
local function BuildOverrideWidget(parent, globalTable, key, onChange, widgetBuilder)
    if editingWindowID == 0 then
        return widgetBuilder(parent, globalTable)
    end

    local hasOverride = PerWindowHasOverride(key)
    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetSize(260, 22)

    local activeWidget
    local function rebuildWidget()
        if activeWidget then
            activeWidget:Hide(); activeWidget:ClearAllPoints(); activeWidget:SetParent(nil)
            activeWidget = nil
        end
        local now = PerWindowHasOverride(key)
        local bt = now and GetOverrideTarget() or globalTable
        activeWidget = widgetBuilder(wrapper, bt)
        activeWidget:ClearAllPoints()
        activeWidget:SetPoint("LEFT", wrapper, "LEFT", 36, 0)
        activeWidget:SetPoint("RIGHT", wrapper, "RIGHT", 0, 0)
        activeWidget:SetAlpha(now and 1 or 0.4)
        if activeWidget.EnableMouse then activeWidget:EnableMouse(now) end
    end

    local toggleState = { override = hasOverride }
    local toggle = GUI:CreateFormToggle(wrapper, nil, "override", toggleState, function(val)
        ToggleOverride(globalTable, key, val and true or false)
        if onChange then onChange() end
        rebuildWidget()
    end)
    toggle:SetPoint("LEFT", wrapper, "LEFT", 0, 0)

    rebuildWidget()
    return wrapper
end

local function BuildNestedOverrideWidget(parent, globalParent, parentKey, leafKey, onChange, widgetBuilder)
    if editingWindowID == 0 then
        local globalSub = globalParent[parentKey] or {}
        globalParent[parentKey] = globalSub
        return widgetBuilder(parent, globalSub)
    end

    local hasOverride = NestedHasOverride(parentKey, leafKey)
    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetSize(260, 22)

    local activeWidget
    local function rebuildWidget()
        if activeWidget then
            activeWidget:Hide(); activeWidget:ClearAllPoints(); activeWidget:SetParent(nil)
            activeWidget = nil
        end
        local now = NestedHasOverride(parentKey, leafKey)
        local bt = now and GetNestedOverrideTarget(parentKey) or (globalParent[parentKey] or {})
        activeWidget = widgetBuilder(wrapper, bt)
        activeWidget:ClearAllPoints()
        activeWidget:SetPoint("LEFT", wrapper, "LEFT", 36, 0)
        activeWidget:SetPoint("RIGHT", wrapper, "RIGHT", 0, 0)
        activeWidget:SetAlpha(now and 1 or 0.4)
        if activeWidget.EnableMouse then activeWidget:EnableMouse(now) end
    end

    local toggleState = { override = hasOverride }
    local toggle = GUI:CreateFormToggle(wrapper, nil, "override", toggleState, function(val)
        ToggleNestedOverride(globalParent, parentKey, leafKey, val and true or false)
        if onChange then onChange() end
        rebuildWidget()
    end)
    toggle:SetPoint("LEFT", wrapper, "LEFT", 0, 0)

    rebuildWidget()
    return wrapper
end

-- ===========================================================================
-- Page builder
-- ===========================================================================
BuildNativeDamageMeterTab = function(tabContent)
    tabContentRef = tabContent
    -- Resolve the options namespace at call time, not load time. This file is
    -- loaded before the on-demand QUI_Options addon (shared.lua) REPLACES
    -- ns.QUI_Options, so the upvalues captured at load can be nil (headless) or
    -- the stale gui_shell stub (which lacks GetDB/CreateAccentDotLabel, making
    -- the builder early-return with no widgets). Re-resolve live-first: a truthy
    -- stale stub must not win over the replacement. This also updates
    -- MakeLayout/row, which close over the same Shared/Opts upvalues.
    Shared = ns.QUI_Options or Shared
    Opts   = ns.QUI_Options or Opts
    local db = Shared and Shared.GetDB and Shared.GetDB()
    if not db then return end

    if GUI and GUI.SetSearchContext then
        GUI:SetSearchContext({
            tileId       = "gameplay",
            tabName      = "Gameplay",
            subPageIndex = NATIVE_DM_SUBPAGE_INDEX,
            subTabName   = "Damage Meter (Native)",
            featureId    = "damageMeterNativePage",
            category     = "gameplay",
        })
    end

    if not db.damageMeter then db.damageMeter = {} end
    if not db.damageMeter.native then
        db.damageMeter.native = {
            visibility = "always",
            refreshRateCombat = 0.5,
            refreshRateIdle = 2.0,
            autoResetOnChallengeStart = true,
            autoSwapChallengeSessions = false,
        }
    end
    if not db.damageMeter.native.appearance then
        db.damageMeter.native.appearance = { global = { barHeight = 18 } }
    end
    if not db.damageMeter.native.appearance.global then
        db.damageMeter.native.appearance.global = { barHeight = 18 }
    end

    local function ApplyNative()
        local mod = GetMod()
        if mod and mod.WindowManager and mod.WindowManager.RefreshAll then
            mod.WindowManager:RefreshAll()
        end
    end

    local L = MakeLayout(tabContent)
    local native = db.damageMeter.native
    if native.autoResetOnChallengeStart == nil then native.autoResetOnChallengeStart = true end
    if native.autoSwapChallengeSessions == nil then native.autoSwapChallengeSessions = false end
    local app = native.appearance.global

    -- Per-window mode banner: pair override-aware cells full-width so the
    -- toggle has room next to its widget. In Global mode, pair 2-per-row.
    local isPerWindow = editingWindowID > 0
    local function placeOverrideRow(s, label, wrapper, pendingRef)
        local cell = row(s.frame, label, wrapper)
        if isPerWindow then
            s.AddRow(cell)
            return nil
        else
            if pendingRef then
                s.AddRow(pendingRef, cell)
                return nil
            end
            return cell
        end
    end

    ---------------------------------------------------------------------------
    -- Editing Window selector
    ---------------------------------------------------------------------------
    L.headerAt("Editing Window")
    local sEdit = L.sectionAt()
    local editingOptions = { { value = 0, text = "Global (apply to all windows)" } }
    for id, w in pairs(native.windows or {}) do
        local displayName = (w and w.name and w.name ~= "") and w.name or ("Window " .. id)
        table.insert(editingOptions, { value = id, text = displayName .. " (per-window overrides)" })
    end
    table.sort(editingOptions, function(a, b) return a.value < b.value end)
    local state = { editing = editingWindowID }
    local editW = GUI:CreateFormDropdown(sEdit.frame, nil, editingOptions, "editing", state, function()
        editingWindowID = state.editing
        RebuildPage()
    end, { description = "Pick 'Global' to edit shared appearance, or a specific window to set per-window overrides. Each appearance widget below shows an Override toggle in per-window mode." })
    sEdit.AddRow(row(sEdit.frame, "Editing", editW))
    L.closeSection(sEdit)

    ---------------------------------------------------------------------------
    -- Behavior
    ---------------------------------------------------------------------------
    L.headerAt("Behavior")
    local sBeh = L.sectionAt()

    local visibilityOptions = {
        { text = "Always",    value = "always"   },
        { text = "In Combat", value = "inCombat" },
        { text = "Hidden",    value = "hidden"   },
    }
    local visW = GUI:CreateFormDropdown(sBeh.frame, nil, visibilityOptions, "visibility", native, ApplyNative,
        { description = "When the native meter is visible. Always = shown at all times; In Combat = only during combat; Hidden = meter exists but is invisible." })
    local refCW = GUI:CreateFormSlider(sBeh.frame, nil, 0.1, 2.0, 0.1, "refreshRateCombat", native, ApplyNative,
        { description = "How often (seconds) the meter refreshes in combat (0.1-2.0)." })
    sBeh.AddRow(row(sBeh.frame, "Visibility", visW), row(sBeh.frame, "Refresh Rate (Combat)", refCW))

    local refIW = GUI:CreateFormSlider(sBeh.frame, nil, 0.5, 5.0, 0.1, "refreshRateIdle", native, ApplyNative,
        { description = "How often (seconds) the meter refreshes outside combat (0.5-5.0)." })
    local hoverW = GUI:CreateFormCheckbox(sBeh.frame, nil, "showHoverTooltip", native, ApplyNative,
        { description = "Show a tooltip with class color, total, per-second, and percent when hovering a row." })
    sBeh.AddRow(row(sBeh.frame, "Refresh Rate (Idle)", refIW), row(sBeh.frame, "Show Hover Tooltip", hoverW))

    local pinW = GUI:CreateFormCheckbox(sBeh.frame, nil, "showPinnedSelf", native, ApplyNative,
        { description = "If the local player isn't in the visible top-N, show them at the bottom anyway." })
    local breakdownAnchorOptions = {
        { value = "row",    text = "Next to row (default)" },
        { value = "center", text = "Center of screen" },
    }
    local breakW = GUI:CreateFormDropdown(sBeh.frame, nil, breakdownAnchorOptions, "breakdownAnchor", native, ApplyNative,
        { description = "Where the per-source spell breakdown popup appears when you click a row." })
    sBeh.AddRow(row(sBeh.frame, "Show Pinned Self", pinW), row(sBeh.frame, "Breakdown Popup Position", breakW))

    local absorbW = GUI:CreateFormCheckbox(sBeh.frame, nil, "combineAbsorbsIntoHealing", native, ApplyNative,
        { description = "When ON (default), Healing Done / HPS sum each source's healing AND absorb shields. Turn off for pure HealingDone (matching Blizzard's stock meter)." })
    local shortNameW = GUI:CreateFormCheckbox(sBeh.frame, nil, "shortenNames", native, ApplyNative,
        { description = "When ON (default), hide realm names: show \"Name\" instead of \"Name-Realm\" for cross-realm players on rows, tooltips, and the breakdown popup." })
    sBeh.AddRow(row(sBeh.frame, "Include Absorbs in Healing", absorbW), row(sBeh.frame, "Hide Realm Names", shortNameW))

    local autoResetW = GUI:CreateFormCheckbox(sBeh.frame, nil, "autoResetOnChallengeStart", native, ApplyNative,
        { description = "When ON (default), clear all damage-meter sessions when a Mythic+ key starts so Overall begins at zero for that run." })
    local autoSwapW = GUI:CreateFormCheckbox(sBeh.frame, nil, "autoSwapChallengeSessions", native, ApplyNative,
        { description = "When ON, windows showing Overall switch to Current when a key starts, then Current switches back to Overall when the key completes." })
    sBeh.AddRow(row(sBeh.frame, "Auto Reset on Key Start", autoResetW), row(sBeh.frame, "Auto Swap Current/Overall", autoSwapW))

    -- Override-aware fields: Number Format, Icon Style
    local numberFormatOptions = {
        { value = "minimal",  text = "Minimal (1K / 2M)" },
        { value = "compact",  text = "Compact (1.5K / 2.4M)" },
        { value = "complete", text = "Complete (1,500 / 2,400,000)" },
    }
    local iconStyleOptions = {
        { value = "spec",  text = "Spec icon (when available)" },
        { value = "class", text = "Class icon" },
        { value = "none",  text = "None" },
    }
    local numW = BuildOverrideWidget(sBeh.frame, app, "numberFormat", ApplyNative,
        function(p, bt)
            return GUI:CreateFormDropdown(p, nil, numberFormatOptions, "numberFormat", bt, ApplyNative,
                { description = "How damage / healing values are formatted in row text and tooltips." })
        end)
    local iconW = BuildOverrideWidget(sBeh.frame, app, "iconStyle", ApplyNative,
        function(p, bt)
            return GUI:CreateFormDropdown(p, nil, iconStyleOptions, "iconStyle", bt, ApplyNative,
                { description = "Which icon to show on each row." })
        end)
    local pending = placeOverrideRow(sBeh, "Number Format", numW, nil)
    placeOverrideRow(sBeh, "Icon Style", iconW, pending)
    L.closeSection(sBeh)

    ---------------------------------------------------------------------------
    -- Appearance: Bars
    ---------------------------------------------------------------------------
    L.headerAt("Appearance: Bars")
    local sBars = L.sectionAt()
    local textures = GetTextureList()

    local function override(parent, key, builder)
        return BuildOverrideWidget(parent, app, key, ApplyNative, builder)
    end

    local hW = override(sBars.frame, "barHeight", function(p, bt)
        return GUI:CreateFormSlider(p, nil, 12, 30, 1, "barHeight", bt, ApplyNative,
            { description = "Pixel height of each damage row (12-30)." })
    end)
    local spaceW = override(sBars.frame, "barSpacing", function(p, bt)
        return GUI:CreateFormSlider(p, nil, 0, 8, 1, "barSpacing", bt, ApplyNative,
            { description = "Pixel gap between rows (0-8)." })
    end)
    pending = placeOverrideRow(sBars, "Bar Height", hW, nil)
    pending = placeOverrideRow(sBars, "Bar Spacing", spaceW, pending)

    local texW = BuildNestedOverrideWidget(sBars.frame, app, "textures", "bar", ApplyNative,
        function(p, bt)
            return GUI:CreateFormDropdown(p, nil, textures, "bar", bt, ApplyNative,
                { description = "LSM statusbar texture for the bar fill. (default) keeps the QUI built-in WHITE8x8." })
        end)
    local fillW = override(sBars.frame, "barFillAlpha", function(p, bt)
        return GUI:CreateFormSlider(p, nil, 0.1, 1.0, 0.05, "barFillAlpha", bt, ApplyNative,
            { description = "Opacity of the bar fill (0.1-1.0)." })
    end)
    pending = placeOverrideRow(sBars, "Bar Texture", texW, pending)
    pending = placeOverrideRow(sBars, "Bar Fill Alpha", fillW, pending)

    local rowBgW = override(sBars.frame, "showRowBackground", function(p, bt)
        return GUI:CreateFormCheckbox(p, nil, "showRowBackground", bt, ApplyNative,
            { description = "Show the dark trough behind each row's colored fill." })
    end)
    local classW = override(sBars.frame, "useClassColor", function(p, bt)
        return GUI:CreateFormCheckbox(p, nil, "useClassColor", bt, ApplyNative,
            { description = "Color bars by class instead of accent/custom." })
    end)
    local accentW = override(sBars.frame, "barColorAccent", function(p, bt)
        return GUI:CreateFormCheckbox(p, nil, "barColorAccent", bt, ApplyNative,
            { description = "When class color is off, use QUI accent color. Otherwise the custom Bar Color below is used." })
    end)
    pending = placeOverrideRow(sBars, "Show Row Background", rowBgW, pending)
    pending = placeOverrideRow(sBars, "Use Class Color", classW, pending)
    pending = placeOverrideRow(sBars, "Use Accent (class off)", accentW, pending)

    local colorW = override(sBars.frame, "barColor", function(p, bt)
        return GUI:CreateFormColorPicker(p, nil, "barColor", bt, ApplyNative, nil,
            { description = "Custom bar color used when both Use Class Color and Use Accent are off." })
    end)
    pending = placeOverrideRow(sBars, "Custom Bar Color", colorW, pending)
    if pending then sBars.AddRow(pending) end
    L.closeSection(sBars)

    ---------------------------------------------------------------------------
    -- Appearance: Fonts (font-slot overrides: rowName, rowValue, header)
    ---------------------------------------------------------------------------
    local outlineOptions = {
        { value = "",             text = "None" },
        { value = "OUTLINE",      text = "Outline" },
        { value = "THICKOUTLINE", text = "Thick Outline" },
    }
    local fontList = GetFontList()
    local fonts = app.fonts or {}
    app.fonts = fonts

    local function ResolveFontSlot(slotKey)
        if editingWindowID == 0 then
            return fonts[slotKey] or {}, true
        end
        local has = NestedHasOverride("fonts", slotKey)
        local s = has and (GetNestedOverrideTarget("fonts")[slotKey] or {}) or (fonts[slotKey] or {})
        return s, has
    end

    local function BuildFontSlotCard(slotKey, label)
        L.headerAt(label)
        local s = L.sectionAt()

        if editingWindowID > 0 then
            local hasOverride = NestedHasOverride("fonts", slotKey)
            local slotState = { override = hasOverride }
            local slotToggle = GUI:CreateFormToggle(s.frame, nil, "override", slotState, function(val)
                local target = GetNestedOverrideTarget("fonts")
                if val then
                    if not target[slotKey] then
                        local g = fonts[slotKey] or {}
                        target[slotKey] = { name = g.name, size = g.size, outline = g.outline }
                    end
                else
                    target[slotKey] = nil
                end
                ApplyNative()
                RebuildPage()
            end)
            s.AddRow(row(s.frame, "Override " .. label .. " font slot", slotToggle))
        end

        local slot, enabled = ResolveFontSlot(slotKey)

        local fontW = GUI:CreateFormDropdown(s.frame, nil, fontList, "name", slot, ApplyNative,
            { description = "LSM font for " .. label .. "." })
        if not enabled then fontW:SetAlpha(0.4); if fontW.EnableMouse then fontW:EnableMouse(false) end end
        local sizeW = GUI:CreateFormSlider(s.frame, nil, 8, 22, 1, "size", slot, ApplyNative,
            { description = "Font size in pixels." })
        if not enabled then sizeW:SetAlpha(0.4); if sizeW.EnableMouse then sizeW:EnableMouse(false) end end
        s.AddRow(row(s.frame, "Font", fontW), row(s.frame, "Size", sizeW))

        local outW = GUI:CreateFormDropdown(s.frame, nil, outlineOptions, "outline", slot, ApplyNative,
            { description = "Text outline for readability." })
        if not enabled then outW:SetAlpha(0.4); if outW.EnableMouse then outW:EnableMouse(false) end end
        s.AddRow(row(s.frame, "Outline", outW))
        L.closeSection(s)
    end

    L.headerAt("Appearance: Fonts")
    BuildFontSlotCard("rowName", "Row Name")
    BuildFontSlotCard("rowValue", "Row Value")
    BuildFontSlotCard("header", "Header")

    ---------------------------------------------------------------------------
    -- Appearance: Colors (nested under colors.{key})
    ---------------------------------------------------------------------------
    L.headerAt("Appearance: Colors")
    local sCol = L.sectionAt()

    local function nestedColor(parent, leafKey, desc)
        return BuildNestedOverrideWidget(parent, app, "colors", leafKey, ApplyNative,
            function(p, bt)
                return GUI:CreateFormColorPicker(p, nil, leafKey, bt, ApplyNative, nil,
                    { description = desc })
            end)
    end

    local bgW = nestedColor(sCol.frame, "bg", "Background fill color for the meter window.")
    local headerColorW = nestedColor(sCol.frame, "headerText", "Color of the meter-type label and session timer. (Default: QUI accent.)")
    pending = placeOverrideRow(sCol, "Window Background", bgW, nil)
    pending = placeOverrideRow(sCol, "Header Text", headerColorW, pending)

    local rowNameW = nestedColor(sCol.frame, "rowName", "Color of the player-name text on each row.")
    local rowValueW = nestedColor(sCol.frame, "rowValue", "Color of the damage / healing number on each row.")
    pending = placeOverrideRow(sCol, "Row Name", rowNameW, pending)
    pending = placeOverrideRow(sCol, "Row Value", rowValueW, pending)

    local borderW = nestedColor(sCol.frame, "border", "Window border color. (Default: QUI accent.)")
    pending = placeOverrideRow(sCol, "Border", borderW, pending)
    if pending then sCol.AddRow(pending) end
    L.closeSection(sCol)

    ---------------------------------------------------------------------------
    -- Windows — bespoke layout (per-window two-row + Add button)
    ---------------------------------------------------------------------------
    local TYPE_NAMES = {
        [0] = "Damage Done", [1] = "Healing Done", [2] = "Damage Taken",
        [3] = "Interrupts",  [4] = "Dispels",      [5] = "Deaths",
    }
    local SESSION_NAMES = { [0] = "Overall", [1] = "Current", [2] = "Expired" }

    local function CountWindows()
        local n = 0
        for _ in pairs(native.windows or {}) do n = n + 1 end
        return n
    end

    L.headerAt("Windows")
    local windowsFrame = CreateFrame("Frame", nil, tabContent)
    local windowsHeight = (CountWindows() + 1) * FORM_ROW + 8
    L.placeCustom(windowsFrame, windowsHeight)

    local windows = native.windows or {}
    local ids = {}
    for id in pairs(windows) do table.insert(ids, id) end
    table.sort(ids)

    local qFont = GUI.GetFontPath and GUI:GetFontPath() or "Fonts\\FRIZQT__.TTF"
    local qC = GUI and GUI.Colors

    local wy = -4
    for _, id in ipairs(ids) do
        local ws = windows[id]
        local typeLabel = TYPE_NAMES[ws.damageMeterType] or ("Type " .. tostring(ws.damageMeterType))
        local sessionLabel = SESSION_NAMES[ws.sessionType] or ("Session " .. tostring(ws.sessionType))
        local autoName = string.format("Window %d — %s / %s", id, typeLabel, sessionLabel)
        local windowID = id
        if not ws.name or ws.name == "" then ws.name = autoName end

        -- Single row: nameEdit | Hide toggle + label | Delete, anchored left-to-right
        local nameEdit = GUI:CreateFormEditBox(windowsFrame, nil, "name", ws, function()
            RebuildPage()
        end, { width = 220, maxLetters = 60 },
            { description = "Display name for this window. Leave blank to auto-name from the window's metric and session type." })
        nameEdit:SetPoint("TOPLEFT", windowsFrame, "TOPLEFT", 0, wy - 4)

        local hideToggle = GUI:CreateFormToggle(windowsFrame, nil, "hidden", ws, function()
            ApplyNative()
        end, { description = "Hide this window without deleting it. The window keeps its layout and overrides and reappears when toggled back on." })
        hideToggle:SetPoint("LEFT", nameEdit, "RIGHT", 12, 0)

        local hideText = windowsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hideText:SetFont(qFont, 12, "")
        if qC and qC.text then
            hideText:SetTextColor(qC.text[1] or 1, qC.text[2] or 1, qC.text[3] or 1, qC.text[4] or 1)
        end
        hideText:SetText("Hide")
        hideText:SetPoint("LEFT", hideToggle, "RIGHT", 6, 0)

        local delBtn = GUI:CreateButton(windowsFrame, "Delete", 70, 22, function()
            local mod = GetMod()
            if mod and mod.WindowManager then
                mod.WindowManager:DeleteWindow(windowID)
            end
            RebuildPage()
        end, "ghost")
        delBtn:SetPoint("TOPRIGHT", windowsFrame, "TOPRIGHT", -4, wy - 4)
        GUI:AttachTooltip(delBtn, "Permanently remove this window. Its layout and per-window overrides are lost.", "Delete Window")

        wy = wy - FORM_ROW
    end

    local count = #ids
    local addLabel = (count >= 5) and "+ Add Window  (cap is 5)" or "+ Add Window"
    local addBtn = GUI:CreateButton(windowsFrame, addLabel, 380, 22, function()
        local mod = GetMod()
        if mod and mod.WindowManager then
            local newID = mod.WindowManager:SpawnNew()
            if newID then
                RebuildPage()
            else
                print("|cff30D1FF[QUI]|r At the 5-window cap; delete one first.")
            end
        end
    end, "ghost")
    addBtn:SetPoint("TOPLEFT", windowsFrame, "TOPLEFT", 0, wy)
    if count >= 5 then addBtn:Disable() end
    GUI:AttachTooltip(addBtn,
        "Create a new damage meter window. The new window starts with global appearance and can be customized via the Editing Window selector. Up to 5 windows are supported.",
        "Add Window")

    return L.finish()
end

-- ===========================================================================
-- Export + Feature registration
-- ===========================================================================
ns.QUI_NativeDamageMeterOptions = {
    BuildNativeDamageMeterTab = BuildNativeDamageMeterTab,
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id          = "damageMeterNativePage",
        category    = "gameplay",
        nav         = { tileId = "gameplay", subPageIndex = NATIVE_DM_SUBPAGE_INDEX },
        sections    = {
            Schema.Section({
                id        = "settings",
                kind      = "page",
                minHeight = 80,
                build     = BuildNativeDamageMeterTab,
            }),
        },
    }))
end
