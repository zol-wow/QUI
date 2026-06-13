local _, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local QUI = QUI
local GUI = QUI and QUI.GUI

-- NOTE: do NOT capture `ns.QUI_Options` as a file-level local. This file is
-- loaded by the QUI addon before the on-demand QUI_Options addon is loaded;
-- at that point ns.QUI_Options is the minimal stub installed by
-- core/gui_shell.lua. Once QUI_Options/shared.lua runs it REPLACES the table,
-- so any captured local would be stale. Re-resolve at call time below.

local ResourceBarsBuilders = ns.QUI_ResourceBarsSettingsBuilders or {}
ns.QUI_ResourceBarsSettingsBuilders = ResourceBarsBuilders

local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

-- Per-spec text helpers live in resourcebars.lua and are shared via the
-- ns.QUI_ResourceBars_Internal export. That table is populated at runtime
-- (the QUI_ResourceBars addon loads before this on-demand QUI_Options file),
-- so resolve it lazily at call time rather than capturing a file-local.
local function GetInternal()
    return ns.QUI_ResourceBars_Internal
end

local VISIBILITY_OPTIONS = {
    { value = "always", text = "Always" },
    { value = "combat", text = "In Combat" },
    { value = "hostile", text = "Hostile Target" },
}

local ORIENTATION_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal" },
    { value = "VERTICAL", text = "Vertical" },
}

local COLOR_MODE_OPTIONS = {
    { value = "power", text = "Power Type Color" },
    { value = "class", text = "Class Color" },
    { value = "custom", text = "Custom Color" },
}

local TEXT_ALIGN_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
}

local function GetProfileDB()
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    return core and core.db and core.db.profile or nil
end

local function GetTextureList()
    local Opts = ns.QUI_Options
    if Opts and type(Opts.GetTextureList) == "function" then
        return Opts.GetTextureList()
    end
    local U = ns.QUI_LayoutMode_Utils
    if U and type(U.GetTextureList) == "function" then
        return U.GetTextureList()
    end
    return {}
end

local function RefreshPowerBars()
    if QUICore and type(QUICore.UpdatePowerBar) == "function" then
        QUICore:UpdatePowerBar()
    end
    if QUICore and type(QUICore.UpdateSecondaryPowerBar) == "function" then
        QUICore:UpdateSecondaryPowerBar()
    end
    if type(_G.QUI_RefreshResourceBarPreview) == "function" then
        _G.QUI_RefreshResourceBarPreview()
    end
end

local function GetCurrentSpecID()
    local spec = GetSpecialization()
    if not spec then return 0 end
    return GetSpecializationInfo(spec) or 0
end

local function NormalizeIndicatorValues(values)
    if type(values) ~= "table" then return {} end

    local normalized = {}
    local seen = {}
    for _, rawValue in pairs(values) do
        local value = tonumber(rawValue)
        if value and value > 0 then
            value = math.floor((value * 1000) + 0.5) / 1000
            local key = string.format("%.3f", value)
            if not seen[key] then
                seen[key] = true
                normalized[#normalized + 1] = value
            end
        end
    end

    table.sort(normalized)
    while #normalized > 3 do
        table.remove(normalized)
    end

    return normalized
end

local function EnsureIndicatorConfig(cfg)
    if type(cfg.indicators) ~= "table" then
        cfg.indicators = {}
    end

    local indicators = cfg.indicators
    if indicators.enabled == nil then indicators.enabled = false end
    if indicators.thickness == nil then indicators.thickness = 2 end
    if type(indicators.color) ~= "table" then
        indicators.color = { 1, 1, 1, 0.9 }
    end
    if type(indicators.perSpec) ~= "table" then
        indicators.perSpec = {}
    end

    return indicators
end

local function EnsureSpecIndicatorValues(indicatorCfg)
    indicatorCfg.perSpec = indicatorCfg.perSpec or {}

    local specID = GetCurrentSpecID()
    local values = indicatorCfg.perSpec[specID]
    local stringKey = tostring(specID)
    if type(values) ~= "table" then
        values = indicatorCfg.perSpec[stringKey]
    end
    if type(values) ~= "table" then
        values = {}
    end

    values = NormalizeIndicatorValues(values)
    indicatorCfg.perSpec[specID] = values
    indicatorCfg.perSpec[stringKey] = nil

    return specID, values
end

local function CreateIndicatorValueProxy(indicatorCfg)
    return setmetatable({}, {
        __index = function(_, dbKey)
            local index = tonumber(tostring(dbKey):match("^value([123])$"))
            if not index then return nil end

            local _, values = EnsureSpecIndicatorValues(indicatorCfg)
            local value = values[index]
            return value and tostring(value) or ""
        end,
        __newindex = function(_, dbKey, rawValue)
            local index = tonumber(tostring(dbKey):match("^value([123])$"))
            if not index then return end

            local specID, values = EnsureSpecIndicatorValues(indicatorCfg)
            local nextValues = {}
            for i = 1, 3 do nextValues[i] = values[i] end

            local value = tonumber(rawValue)
            if value and value > 0 then
                nextValues[index] = value
            else
                nextValues[index] = nil
            end

            indicatorCfg.perSpec[specID] = NormalizeIndicatorValues(nextValues)
        end,
    })
end

local function EnsureTextSpecOverrides(cfg, specID)
    local internal = GetInternal()
    if internal and internal.EnsureTextSpecOverrides then
        return internal.EnsureTextSpecOverrides(cfg, specID)
    end
    if type(cfg.textSpecOverrides) ~= "table" then
        cfg.textSpecOverrides = {}
    end
    return cfg.textSpecOverrides[specID]
end

---------------------------------------------------------------------------
-- V3 BODY HELPERS (per-page, scoped via closure over the page's `y` cursor)
---------------------------------------------------------------------------
-- Shared provider-panel layout scaffold (core/settings_layout_shared.lua).
local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function row(parent, label, widget, desc)
    return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
end

---------------------------------------------------------------------------
-- INDICATOR (BREAKPOINT) CARD
---------------------------------------------------------------------------
local function BuildIndicatorCard(L, cfg)
    local indicatorCfg = EnsureIndicatorConfig(cfg)
    local valueProxy = CreateIndicatorValueProxy(indicatorCfg)

    L.headerAt("Breakpoint Indicators")
    local s = L.sectionAt()

    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", indicatorCfg, RefreshPowerBars,
        { description = "Draw custom marker lines on this bar at the current specialization's breakpoint values." })
    local thicknessW = GUI:CreateFormSlider(s.frame, nil, 1, 6, 1, "thickness", indicatorCfg, RefreshPowerBars,
        { description = "Pixel thickness of each custom breakpoint marker line." })
    s.AddRow(
        row(s.frame, "Enable Breakpoint Indicators", enableW),
        row(s.frame, "Indicator Thickness", thicknessW)
    )

    local colorW = GUI:CreateFormColorPicker(s.frame, nil, "color", indicatorCfg, RefreshPowerBars, nil,
        { description = "Color used for custom breakpoint marker lines." })
    local v1W = GUI:CreateFormEditBox(s.frame, nil, "value1", valueProxy, RefreshPowerBars,
        { maxLetters = 8, width = 90 },
        { description = "Resource value where this specialization draws a custom breakpoint marker line." })
    s.AddRow(
        row(s.frame, "Indicator Color", colorW),
        row(s.frame, "Breakpoint 1", v1W)
    )

    local v2W = GUI:CreateFormEditBox(s.frame, nil, "value2", valueProxy, RefreshPowerBars,
        { maxLetters = 8, width = 90 },
        { description = "Resource value where this specialization draws a custom breakpoint marker line." })
    local v3W = GUI:CreateFormEditBox(s.frame, nil, "value3", valueProxy, RefreshPowerBars,
        { maxLetters = 8, width = 90 },
        { description = "Resource value where this specialization draws a custom breakpoint marker line." })
    s.AddRow(
        row(s.frame, "Breakpoint 2", v2W),
        row(s.frame, "Breakpoint 3", v3W)
    )

    L.closeSection(s)
end

---------------------------------------------------------------------------
-- PRIMARY POWER BAR
---------------------------------------------------------------------------
local function BuildPrimaryPowerSettings(content, _key)
    local profile = GetProfileDB()
    local primary = profile and profile.powerBar
    if not GUI or not primary or not ns.QUI_Options then return 80 end

    local L = MakeLayout(content)

    -- ENABLE
    L.headerAt("Enable")
    local sEnable = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(sEnable.frame, nil, "enabled", primary, RefreshPowerBars,
        { description = "Show the primary power bar (mana, rage, energy, focus, runic power, etc.) as a standalone QUI-managed bar." })
    sEnable.AddRow(row(sEnable.frame, "Enable Primary Power Bar", enableW))
    L.closeSection(sEnable)

    -- GENERAL
    L.headerAt("General")
    local s1 = L.sectionAt()

    local visW = GUI:CreateFormDropdown(s1.frame, nil, VISIBILITY_OPTIONS, "visibility", primary, RefreshPowerBars,
        { description = "When the primary power bar is visible (always, in combat only, when depleted, etc.)." })
    local oriW = GUI:CreateFormDropdown(s1.frame, nil, ORIENTATION_OPTIONS, "orientation", primary, RefreshPowerBars,
        { description = "Fill direction: horizontal (left-to-right) or vertical (bottom-to-top)." })
    s1.AddRow(
        row(s1.frame, "Visibility", visW),
        row(s1.frame, "Orientation", oriW)
    )

    local autoW = GUI:CreateFormCheckbox(s1.frame, nil, "autoAttach", primary, RefreshPowerBars,
        { description = "Automatically attach the bar below the player unit frame. Disable to position the bar freely via the Position controls." })
    local standW = GUI:CreateFormCheckbox(s1.frame, nil, "standaloneMode", primary, RefreshPowerBars,
        { description = "Keep this bar always visible even when the player unit frame is hidden." })
    s1.AddRow(
        row(s1.frame, "Auto Attach", autoW),
        row(s1.frame, "Standalone Mode", standW)
    )
    L.closeSection(s1)

    -- DIMENSIONS
    L.headerAt("Dimensions")
    local s2 = L.sectionAt()

    local wW = GUI:CreateFormSlider(s2.frame, nil, 50, 600, 1, "width", primary, RefreshPowerBars,
        { description = "Width of the bar in pixels. Ignored when Auto Attach matches the player frame width." })
    local hW = GUI:CreateFormSlider(s2.frame, nil, 2, 40, 1, "height", primary, RefreshPowerBars,
        { description = "Height of the bar in pixels." })
    s2.AddRow(
        row(s2.frame, "Width", wW),
        row(s2.frame, "Height", hW)
    )

    local snapW = GUI:CreateFormSlider(s2.frame, nil, 0, 20, 1, "snapGap", primary, RefreshPowerBars,
        { description = "Pixel gap between this bar and the frame it auto-attaches to." })
    local xW = GUI:CreateFormSlider(s2.frame, nil, -500, 500, 1, "offsetX", primary, RefreshPowerBars,
        { description = "Horizontal pixel offset from the auto-attach anchor (or from its manual position when Auto Attach is off)." })
    s2.AddRow(
        row(s2.frame, "Snap Gap", snapW),
        row(s2.frame, "X Offset", xW)
    )

    local yW = GUI:CreateFormSlider(s2.frame, nil, -500, 500, 1, "offsetY", primary, RefreshPowerBars,
        { description = "Vertical pixel offset from the auto-attach anchor (or from its manual position when Auto Attach is off)." })
    s2.AddRow(row(s2.frame, "Y Offset", yW))
    L.closeSection(s2)

    -- APPEARANCE
    L.headerAt("Appearance")
    local s3 = L.sectionAt()

    local texW = GUI:CreateFormDropdown(s3.frame, nil, GetTextureList(), "texture", primary, RefreshPowerBars,
        { description = "Statusbar texture used for the power fill." })
    local borderW = GUI:CreateFormSlider(s3.frame, nil, 0, 5, 1, "borderSize", primary, RefreshPowerBars,
        { description = "Border thickness in pixels. Set to 0 to hide the border." })
    s3.AddRow(
        row(s3.frame, "Bar Texture", texW),
        row(s3.frame, "Border Size", borderW)
    )
    L.closeSection(s3)

    -- BREAKPOINT INDICATORS
    BuildIndicatorCard(L, primary)

    -- TEXT
    L.headerAt("Text")
    local s4 = L.sectionAt()

    local showTW = GUI:CreateFormCheckbox(s4.frame, nil, "showText", primary, RefreshPowerBars,
        { description = "Show the power value as text on the bar." })
    local showPW = GUI:CreateFormCheckbox(s4.frame, nil, "showPercent", primary, RefreshPowerBars,
        { description = "Append the percent value after the raw number (e.g. '5000 / 50%')." })
    s4.AddRow(
        row(s4.frame, "Show Text", showTW),
        row(s4.frame, "Show Percent", showPW)
    )

    local hidePctW = GUI:CreateFormCheckbox(s4.frame, nil, "hidePercentSymbol", primary, RefreshPowerBars,
        { description = "Drop the '%' sign from percent text for a cleaner look." })
    local alignW = GUI:CreateFormDropdown(s4.frame, nil, TEXT_ALIGN_OPTIONS, "textAlign", primary, RefreshPowerBars,
        { description = "Horizontal alignment of the power text on the bar." })
    s4.AddRow(
        row(s4.frame, "Hide % Symbol", hidePctW),
        row(s4.frame, "Text Alignment", alignW)
    )

    local sizeW = GUI:CreateFormSlider(s4.frame, nil, 6, 24, 1, "textSize", primary, RefreshPowerBars,
        { description = "Font size used for the power text." })
    local txW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "textX", primary, RefreshPowerBars,
        { description = "Horizontal pixel offset for the power text from its alignment point." })
    s4.AddRow(
        row(s4.frame, "Text Size", sizeW),
        row(s4.frame, "Text X Offset", txW)
    )

    local tyW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "textY", primary, RefreshPowerBars,
        { description = "Vertical pixel offset for the power text from its alignment point." })
    s4.AddRow(row(s4.frame, "Text Y Offset", tyW))
    L.closeSection(s4)

    -- COLORS
    L.headerAt("Colors")
    local s5 = L.sectionAt()

    local modeW = GUI:CreateFormDropdown(s5.frame, nil, COLOR_MODE_OPTIONS, "colorMode", primary, RefreshPowerBars,
        { description = "How the fill is colored: by power type, class color, or a custom swatch." })
    local customW = GUI:CreateFormColorPicker(s5.frame, nil, "customColor", primary, RefreshPowerBars, nil,
        { description = "Custom fill color used when Color Mode is set to Custom." })
    s5.AddRow(
        row(s5.frame, "Color Mode", modeW),
        row(s5.frame, "Custom Color", customW)
    )

    local bgW = GUI:CreateFormColorPicker(s5.frame, nil, "bgColor", primary, RefreshPowerBars, nil,
        { description = "Backdrop color drawn behind the fill." })
    s5.AddRow(row(s5.frame, "Background Color", bgW))
    L.closeSection(s5)

    -- LOCK
    L.headerAt("Lock")
    local s6 = L.sectionAt()

    local lockEW = GUI:CreateFormCheckbox(s6.frame, nil, "lockedToEssential", primary, RefreshPowerBars,
        { description = "Match the width of the Essential Cooldowns row and ride its visibility." })
    local lockUW = GUI:CreateFormCheckbox(s6.frame, nil, "lockedToUtility", primary, RefreshPowerBars,
        { description = "Match the width of the Utility Cooldowns row and ride its visibility." })
    s6.AddRow(
        row(s6.frame, "Lock to Essential", lockEW),
        row(s6.frame, "Lock to Utility", lockUW)
    )
    L.closeSection(s6)

    return L.finish()
end

---------------------------------------------------------------------------
-- SECONDARY POWER BAR
---------------------------------------------------------------------------
local function BuildSecondaryPowerSettings(content, _key)
    local profile = GetProfileDB()
    local secondary = profile and profile.secondaryPowerBar
    if not GUI or not secondary or not ns.QUI_Options then return 80 end

    local L = MakeLayout(content)

    -- ENABLE
    L.headerAt("Enable")
    local sEnable = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(sEnable.frame, nil, "enabled", secondary, RefreshPowerBars,
        { description = "Show the secondary power bar for classes with an alternate resource (combo points, runes, holy power, etc.)." })
    sEnable.AddRow(row(sEnable.frame, "Enable Secondary Power Bar", enableW))
    L.closeSection(sEnable)

    -- GENERAL
    L.headerAt("General")
    local s1 = L.sectionAt()

    local visW = GUI:CreateFormDropdown(s1.frame, nil, VISIBILITY_OPTIONS, "visibility", secondary, RefreshPowerBars,
        { description = "When the secondary power bar is visible (always, in combat only, when depleted, etc.)." })
    local oriW = GUI:CreateFormDropdown(s1.frame, nil, ORIENTATION_OPTIONS, "orientation", secondary, RefreshPowerBars,
        { description = "Fill direction: horizontal (left-to-right) or vertical (bottom-to-top)." })
    s1.AddRow(
        row(s1.frame, "Visibility", visW),
        row(s1.frame, "Orientation", oriW)
    )

    local autoW = GUI:CreateFormCheckbox(s1.frame, nil, "autoAttach", secondary, RefreshPowerBars,
        { description = "Automatically attach the bar below the primary power bar. Disable to position the bar freely via the Position controls." })
    local standW = GUI:CreateFormCheckbox(s1.frame, nil, "standaloneMode", secondary, RefreshPowerBars,
        { description = "Keep this bar always visible even when the player unit frame is hidden." })
    s1.AddRow(
        row(s1.frame, "Auto Attach", autoW),
        row(s1.frame, "Standalone Mode", standW)
    )

    local swapW = GUI:CreateFormCheckbox(s1.frame, nil, "swapToPrimaryPosition", secondary, RefreshPowerBars,
        { description = "When the secondary resource is dominant for your spec, swap it into the primary bar's position for that spec." })
    local hidePW = GUI:CreateFormCheckbox(s1.frame, nil, "hidePrimaryOnSwap", secondary, RefreshPowerBars,
        { description = "When Swap to Primary Position is active, also hide the primary power bar so both resources aren't shown together." })
    s1.AddRow(
        row(s1.frame, "Swap to Primary Position", swapW),
        row(s1.frame, "Hide Primary on Swap", hidePW)
    )

    local fragW = GUI:CreateFormCheckbox(s1.frame, nil, "showFragmentedPowerBarText", secondary, RefreshPowerBars,
        { description = "Display the numeric current/max value on fragmented resources (soul shards, holy power, combo points)." })
    s1.AddRow(row(s1.frame, "Show Fragmented Power Bar Text", fragW))
    L.closeSection(s1)

    -- DIMENSIONS
    L.headerAt("Dimensions")
    local s2 = L.sectionAt()

    local wW = GUI:CreateFormSlider(s2.frame, nil, 50, 600, 1, "width", secondary, RefreshPowerBars,
        { description = "Width of the bar in pixels." })
    local hW = GUI:CreateFormSlider(s2.frame, nil, 2, 40, 1, "height", secondary, RefreshPowerBars,
        { description = "Height of the bar in pixels." })
    s2.AddRow(
        row(s2.frame, "Width", wW),
        row(s2.frame, "Height", hW)
    )

    local snapW = GUI:CreateFormSlider(s2.frame, nil, 0, 20, 1, "snapGap", secondary, RefreshPowerBars,
        { description = "Pixel gap between this bar and the frame it auto-attaches to." })
    local xW = GUI:CreateFormSlider(s2.frame, nil, -500, 500, 1, "offsetX", secondary, RefreshPowerBars,
        { description = "Horizontal pixel offset from the auto-attach anchor." })
    s2.AddRow(
        row(s2.frame, "Snap Gap", snapW),
        row(s2.frame, "X Offset", xW)
    )

    local yW = GUI:CreateFormSlider(s2.frame, nil, -500, 500, 1, "offsetY", secondary, RefreshPowerBars,
        { description = "Vertical pixel offset from the auto-attach anchor." })
    s2.AddRow(row(s2.frame, "Y Offset", yW))
    L.closeSection(s2)

    -- APPEARANCE
    L.headerAt("Appearance")
    local s3 = L.sectionAt()

    local texW = GUI:CreateFormDropdown(s3.frame, nil, GetTextureList(), "texture", secondary, RefreshPowerBars,
        { description = "Statusbar texture used for the power fill." })
    local borderW = GUI:CreateFormSlider(s3.frame, nil, 0, 5, 1, "borderSize", secondary, RefreshPowerBars,
        { description = "Border thickness in pixels. Set to 0 to hide the border." })
    s3.AddRow(
        row(s3.frame, "Bar Texture", texW),
        row(s3.frame, "Border Size", borderW)
    )
    L.closeSection(s3)

    -- BREAKPOINT INDICATORS
    BuildIndicatorCard(L, secondary)

    -- TEXT (with optional per-spec proxy)
    local textProxy = setmetatable({}, {
        __index = function(_, dbKey)
            if secondary.textPerSpec then
                local specID = GetCurrentSpecID()
                if specID ~= 0 then
                    return EnsureTextSpecOverrides(secondary, specID)[dbKey]
                end
            end
            return secondary[dbKey]
        end,
        __newindex = function(_, dbKey, value)
            if secondary.textPerSpec then
                local specID = GetCurrentSpecID()
                if specID ~= 0 then
                    EnsureTextSpecOverrides(secondary, specID)[dbKey] = value
                    return
                end
            end
            secondary[dbKey] = value
        end,
    })

    L.headerAt("Text")
    local s4 = L.sectionAt()

    local perSpecDesc = "Store text settings separately per specialization."
    if secondary.textPerSpec then
        local specName = select(2, GetSpecializationInfo(GetSpecialization() or 0)) or "Unknown"
        perSpecDesc = perSpecDesc .. " Editing: " .. specName
    end
    local perSpecW = GUI:CreateFormCheckbox(s4.frame, nil, "textPerSpec", secondary, RefreshPowerBars,
        { description = perSpecDesc })
    s4.AddRow(row(s4.frame, "Per-Spec Text Settings", perSpecW, perSpecDesc))

    local showTW = GUI:CreateFormCheckbox(s4.frame, nil, "showText", textProxy, RefreshPowerBars,
        { description = "Show the power value as text on the bar." })
    local showPW = GUI:CreateFormCheckbox(s4.frame, nil, "showPercent", textProxy, RefreshPowerBars,
        { description = "Append the percent value after the raw number." })
    s4.AddRow(
        row(s4.frame, "Show Text", showTW),
        row(s4.frame, "Show Percent", showPW)
    )

    local hidePctW = GUI:CreateFormCheckbox(s4.frame, nil, "hidePercentSymbol", textProxy, RefreshPowerBars,
        { description = "Drop the '%' sign from percent text for a cleaner look." })
    local alignW = GUI:CreateFormDropdown(s4.frame, nil, TEXT_ALIGN_OPTIONS, "textAlign", textProxy, RefreshPowerBars,
        { description = "Horizontal alignment of the power text on the bar." })
    s4.AddRow(
        row(s4.frame, "Hide % Symbol", hidePctW),
        row(s4.frame, "Text Alignment", alignW)
    )

    local sizeW = GUI:CreateFormSlider(s4.frame, nil, 6, 24, 1, "textSize", textProxy, RefreshPowerBars,
        { description = "Font size used for the power text." })
    local txW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "textX", textProxy, RefreshPowerBars,
        { description = "Horizontal pixel offset for the power text from its alignment point." })
    s4.AddRow(
        row(s4.frame, "Text Size", sizeW),
        row(s4.frame, "Text X Offset", txW)
    )

    local tyW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "textY", textProxy, RefreshPowerBars,
        { description = "Vertical pixel offset for the power text from its alignment point." })
    s4.AddRow(row(s4.frame, "Text Y Offset", tyW))
    L.closeSection(s4)

    -- COLORS
    L.headerAt("Colors")
    local s5 = L.sectionAt()

    local modeW = GUI:CreateFormDropdown(s5.frame, nil, COLOR_MODE_OPTIONS, "colorMode", secondary, RefreshPowerBars,
        { description = "How the fill is colored: by resource type, class color, or a custom swatch." })
    local customW = GUI:CreateFormColorPicker(s5.frame, nil, "customColor", secondary, RefreshPowerBars, nil,
        { description = "Custom fill color used when Color Mode is set to Custom." })
    s5.AddRow(
        row(s5.frame, "Color Mode", modeW),
        row(s5.frame, "Custom Color", customW)
    )

    local bgW = GUI:CreateFormColorPicker(s5.frame, nil, "bgColor", secondary, RefreshPowerBars, nil,
        { description = "Backdrop color drawn behind the fill." })
    s5.AddRow(row(s5.frame, "Background Color", bgW))
    L.closeSection(s5)

    -- LOCK
    L.headerAt("Lock")
    local s6 = L.sectionAt()

    local lockEW = GUI:CreateFormCheckbox(s6.frame, nil, "lockedToEssential", secondary, RefreshPowerBars,
        { description = "Match the width of the Essential Cooldowns row and ride its visibility." })
    local lockUW = GUI:CreateFormCheckbox(s6.frame, nil, "lockedToUtility", secondary, RefreshPowerBars,
        { description = "Match the width of the Utility Cooldowns row and ride its visibility." })
    s6.AddRow(
        row(s6.frame, "Lock to Essential", lockEW),
        row(s6.frame, "Lock to Utility", lockUW)
    )
    L.closeSection(s6)

    return L.finish()
end

ResourceBarsBuilders.BuildPrimaryPowerSettings = BuildPrimaryPowerSettings
ResourceBarsBuilders.BuildSecondaryPowerSettings = BuildSecondaryPowerSettings
