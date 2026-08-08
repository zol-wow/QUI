local _, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers
local QUI = QUI
local GUI = QUI and QUI.GUI

local ResourceBarsBuilders = ns.QUI_ResourceBarsSettingsBuilders or {}
ns.QUI_ResourceBarsSettingsBuilders = ResourceBarsBuilders

local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

local function GetInternal()
    return ns.QUI_ResourceBars_Internal
end

local VISIBILITY_OPTIONS = {
    { value = "always", text = ns.L["Always"] },
    { value = "combat", text = ns.L["In Combat"] },
    { value = "hostile", text = ns.L["Hostile Target"] },
}

local ORIENTATION_OPTIONS = {
    { value = "HORIZONTAL", text = ns.L["Horizontal"] },
    { value = "VERTICAL", text = ns.L["Vertical"] },
}

local COLOR_MODE_OPTIONS = {
    { value = "power", text = ns.L["Power Type Color"] },
    { value = "class", text = ns.L["Class Color"] },
    { value = "custom", text = ns.L["Custom Color"] },
}

local TEXT_ALIGN_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "CENTER", text = ns.L["Center"] },
    { value = "RIGHT", text = ns.L["Right"] },
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
    return Helpers.GetCurrentSpecID() or 0
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

local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function row(parent, label, widget, desc)
    return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
end

local function BuildIndicatorCard(L, cfg)
    local indicatorCfg = EnsureIndicatorConfig(cfg)
    local valueProxy = CreateIndicatorValueProxy(indicatorCfg)

    L.headerAt(ns.L["Breakpoint Indicators"])
    local s = L.sectionAt()

    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", indicatorCfg, RefreshPowerBars,
        { description = ns.L["Draw custom marker lines on this bar at the current specialization's breakpoint values."] })
    local thicknessW = GUI:CreateFormSlider(s.frame, nil, 1, 6, 1, "thickness", indicatorCfg, RefreshPowerBars,
        { description = ns.L["Pixel thickness of each custom breakpoint marker line."] })
    s.AddRow(
        row(s.frame, ns.L["Enable Breakpoint Indicators"], enableW),
        row(s.frame, ns.L["Indicator Thickness"], thicknessW)
    )

    local colorW = GUI:CreateFormColorPicker(s.frame, nil, "color", indicatorCfg, RefreshPowerBars, nil,
        { description = ns.L["Color used for custom breakpoint marker lines."] })
    local v1W = GUI:CreateFormEditBox(s.frame, nil, "value1", valueProxy, RefreshPowerBars,
        { maxLetters = 8, width = 90 },
        { description = ns.L["Resource value where this specialization draws a custom breakpoint marker line."] })
    s.AddRow(
        row(s.frame, ns.L["Indicator Color"], colorW),
        row(s.frame, ns.L["Breakpoint 1"], v1W)
    )

    local v2W = GUI:CreateFormEditBox(s.frame, nil, "value2", valueProxy, RefreshPowerBars,
        { maxLetters = 8, width = 90 },
        { description = ns.L["Resource value where this specialization draws a custom breakpoint marker line."] })
    local v3W = GUI:CreateFormEditBox(s.frame, nil, "value3", valueProxy, RefreshPowerBars,
        { maxLetters = 8, width = 90 },
        { description = ns.L["Resource value where this specialization draws a custom breakpoint marker line."] })
    s.AddRow(
        row(s.frame, ns.L["Breakpoint 2"], v2W),
        row(s.frame, ns.L["Breakpoint 3"], v3W)
    )

    L.closeSection(s)
end

local function BuildSegmentCard(L, cfg)
    L.headerAt(ns.L["Segment Dividers"])
    local s = L.sectionAt()

    local thickRow, colorRow

    local function SyncTickRows()
        local on = cfg.showTicks == true
        if thickRow then thickRow:SetEnabled(on) end
        if colorRow then colorRow:SetEnabled(on) end
        RefreshPowerBars()
    end

    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "showTicks", cfg, SyncTickRows,
        { description = ns.L["Draw divider lines between resource segments (Holy Power, Chi, combo points, etc.). No effect on Runes or Essence, which render as separate segments."] })
    local thickW = GUI:CreateFormSlider(s.frame, nil, 1, 10, 1, "tickThickness", cfg, RefreshPowerBars,
        { description = ns.L["Width of each segment divider in pixels. The same value covers more total bar width on specs with more segments."] })
    thickRow = row(s.frame, ns.L["Divider Width"], thickW)
    s.AddRow(
        row(s.frame, ns.L["Show Segment Dividers"], enableW),
        thickRow
    )

    local colorW = GUI:CreateFormColorPicker(s.frame, nil, "tickColor", cfg, RefreshPowerBars, nil,
        { description = ns.L["Color of the segment divider lines."] })
    colorRow = row(s.frame, ns.L["Divider Color"], colorW)
    s.AddRow(colorRow)

    SyncTickRows()

    L.closeSection(s)
end

local function BuildBarSettings(content, cfg, o)
    if not GUI or not cfg or not ns.QUI_Options then return 80 end

    local L = MakeLayout(content)

    L.headerAt(ns.L["Enable"])
    local sEnable = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(sEnable.frame, nil, "enabled", cfg, RefreshPowerBars,
        { description = o.enableDesc })
    sEnable.AddRow(row(sEnable.frame, o.enableLabel, enableW))
    L.closeSection(sEnable)

    L.headerAt(ns.L["General"])
    local s1 = L.sectionAt()

    local visW = GUI:CreateFormDropdown(s1.frame, nil, VISIBILITY_OPTIONS, "visibility", cfg, RefreshPowerBars,
        { description = o.visibilityDesc })
    local oriW = GUI:CreateFormDropdown(s1.frame, nil, ORIENTATION_OPTIONS, "orientation", cfg, RefreshPowerBars,
        { description = ns.L["Fill direction: horizontal (left-to-right) or vertical (bottom-to-top)."] })
    s1.AddRow(
        row(s1.frame, ns.L["Visibility"], visW),
        row(s1.frame, ns.L["Orientation"], oriW)
    )

    if o.secondary then
        local autoW = GUI:CreateFormCheckbox(s1.frame, nil, "autoAttach", cfg, RefreshPowerBars,
            { description = o.autoAttachDesc })
        local standW = GUI:CreateFormCheckbox(s1.frame, nil, "standaloneMode", cfg, RefreshPowerBars,
            { description = ns.L["Keep this bar always visible even when the player unit frame is hidden."] })
        s1.AddRow(
            row(s1.frame, ns.L["Auto Attach"], autoW),
            row(s1.frame, ns.L["Standalone Mode"], standW)
        )

        local swapW = GUI:CreateFormCheckbox(s1.frame, nil, "swapToPrimaryPosition", cfg, RefreshPowerBars,
            { description = ns.L["When the secondary resource is dominant for your spec, swap it into the primary bar's position for that spec."] })
        local hidePW = GUI:CreateFormCheckbox(s1.frame, nil, "hidePrimaryOnSwap", cfg, RefreshPowerBars,
            { description = ns.L["When Swap to Primary Position is active, also hide the primary power bar so both resources aren't shown together."] })
        s1.AddRow(
            row(s1.frame, ns.L["Swap to Primary Position"], swapW),
            row(s1.frame, ns.L["Hide Primary on Swap"], hidePW)
        )

        local fragW = GUI:CreateFormCheckbox(s1.frame, nil, "showFragmentedPowerBarText", cfg, RefreshPowerBars,
            { description = ns.L["Display the numeric current/max value on fragmented resources (soul shards, holy power, combo points)."] })
        s1.AddRow(row(s1.frame, ns.L["Show Fragmented Power Bar Text"], fragW))
    end
    L.closeSection(s1)

    L.headerAt(ns.L["Dimensions"])
    local s2 = L.sectionAt()

    local wW = GUI:CreateFormSlider(s2.frame, nil, 50, 600, 1, "width", cfg, RefreshPowerBars,
        { description = o.widthDesc })
    local hW = GUI:CreateFormSlider(s2.frame, nil, 2, 40, 1, "height", cfg, RefreshPowerBars,
        { description = ns.L["Height of the bar in pixels."] })
    s2.AddRow(
        row(s2.frame, ns.L["Width"], wW),
        row(s2.frame, ns.L["Height"], hW)
    )

    local xW = GUI:CreateFormSlider(s2.frame, nil, -500, 500, 1, "offsetX", cfg, RefreshPowerBars,
        { description = o.offsetXDesc })
    local yW = GUI:CreateFormSlider(s2.frame, nil, -500, 500, 1, "offsetY", cfg, RefreshPowerBars,
        { description = o.offsetYDesc })
    s2.AddRow(
        row(s2.frame, ns.L["X Offset"], xW),
        row(s2.frame, ns.L["Y Offset"], yW)
    )
    L.closeSection(s2)

    L.headerAt(ns.L["Appearance"])
    local s3 = L.sectionAt()

    local texW = GUI:CreateFormDropdown(s3.frame, nil, GetTextureList(), "texture", cfg, RefreshPowerBars,
        { description = ns.L["Statusbar texture used for the power fill."] })
    local borderW = GUI:CreateFormSlider(s3.frame, nil, 0, 5, 1, "borderSize", cfg, RefreshPowerBars,
        { description = ns.L["Border thickness in pixels. Set to 0 to hide the border."] })
    s3.AddRow(
        row(s3.frame, ns.L["Bar Texture"], texW),
        row(s3.frame, ns.L["Border Size"], borderW)
    )

    if ns.QUI_BorderControl then
        local borderSrcW, borderColorW = ns.QUI_BorderControl.Attach(
            GUI, s3.frame, cfg, "", RefreshPowerBars,
            {
                label             = ns.L["Border Color Source"],
                colorLabel        = ns.L["Border Color"],
                sourceDescription = ns.L["Where the bar border gets its color: Inherit (global skin border), Theme accent, Class color, or Custom."],
                colorDescription  = ns.L["Custom bar border color, used when Border Color Source is set to Custom."],
            }
        )
        s3.AddRow(
            row(s3.frame, ns.L["Border Color Source"], borderSrcW),
            row(s3.frame, ns.L["Border Color"], borderColorW)
        )
    end
    L.closeSection(s3)

    BuildIndicatorCard(L, cfg)

    local textTarget = cfg
    if o.secondary then
        BuildSegmentCard(L, cfg)

        textTarget = setmetatable({}, {
            __index = function(_, dbKey)
                if cfg.textPerSpec then
                    local specID = GetCurrentSpecID()
                    if specID ~= 0 then
                        return EnsureTextSpecOverrides(cfg, specID)[dbKey]
                    end
                end
                return cfg[dbKey]
            end,
            __newindex = function(_, dbKey, value)
                if cfg.textPerSpec then
                    local specID = GetCurrentSpecID()
                    if specID ~= 0 then
                        EnsureTextSpecOverrides(cfg, specID)[dbKey] = value
                        return
                    end
                end
                cfg[dbKey] = value
            end,
        })
    end

    L.headerAt(ns.L["Text"])
    local s4 = L.sectionAt()

    if o.secondary then
        local perSpecDesc = ns.L["Store text settings separately per specialization."]
        if cfg.textPerSpec then
            local specName = select(2, GetSpecializationInfo(GetSpecialization() or 0)) or ns.L["Unknown"]
            perSpecDesc = perSpecDesc .. " " .. ns.L["Editing: "] .. specName
        end
        local perSpecW = GUI:CreateFormCheckbox(s4.frame, nil, "textPerSpec", cfg, RefreshPowerBars,
            { description = perSpecDesc })
        s4.AddRow(row(s4.frame, ns.L["Per-Spec Text Settings"], perSpecW, perSpecDesc))
    end

    local showTW = GUI:CreateFormCheckbox(s4.frame, nil, "showText", textTarget, RefreshPowerBars,
        { description = ns.L["Show the power value as text on the bar."] })
    local showPW = GUI:CreateFormCheckbox(s4.frame, nil, "showPercent", textTarget, RefreshPowerBars,
        { description = o.showPercentDesc })
    s4.AddRow(
        row(s4.frame, ns.L["Show Text"], showTW),
        row(s4.frame, ns.L["Show Percent"], showPW)
    )

    local hidePctW = GUI:CreateFormCheckbox(s4.frame, nil, "hidePercentSymbol", textTarget, RefreshPowerBars,
        { description = ns.L["Drop the '%' sign from percent text for a cleaner look."] })
    local alignW = GUI:CreateFormDropdown(s4.frame, nil, TEXT_ALIGN_OPTIONS, "textAlign", textTarget, RefreshPowerBars,
        { description = ns.L["Horizontal alignment of the power text on the bar."] })
    s4.AddRow(
        row(s4.frame, ns.L["Hide % Symbol"], hidePctW),
        row(s4.frame, ns.L["Text Alignment"], alignW)
    )

    local sizeW = GUI:CreateFormSlider(s4.frame, nil, 6, 24, 1, "textSize", textTarget, RefreshPowerBars,
        { description = ns.L["Font size used for the power text."] })
    local txW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "textX", textTarget, RefreshPowerBars,
        { description = ns.L["Horizontal pixel offset for the power text from its alignment point."] })
    s4.AddRow(
        row(s4.frame, ns.L["Text Size"], sizeW),
        row(s4.frame, ns.L["Text X Offset"], txW)
    )

    local tyW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "textY", textTarget, RefreshPowerBars,
        { description = ns.L["Vertical pixel offset for the power text from its alignment point."] })
    s4.AddRow(row(s4.frame, ns.L["Text Y Offset"], tyW))
    L.closeSection(s4)

    L.headerAt(ns.L["Colors"])
    local s5 = L.sectionAt()

    local modeW = GUI:CreateFormDropdown(s5.frame, nil, COLOR_MODE_OPTIONS, "colorMode", cfg, RefreshPowerBars,
        { description = o.colorModeDesc })
    local customW = GUI:CreateFormColorPicker(s5.frame, nil, "customColor", cfg, RefreshPowerBars, nil,
        { description = ns.L["Custom fill color used when Color Mode is set to Custom."] })
    s5.AddRow(
        row(s5.frame, ns.L["Color Mode"], modeW),
        row(s5.frame, ns.L["Custom Color"], customW)
    )

    local bgW = GUI:CreateFormColorPicker(s5.frame, nil, "bgColor", cfg, RefreshPowerBars, nil,
        { description = ns.L["Backdrop color drawn behind the fill."] })
    s5.AddRow(row(s5.frame, ns.L["Background Color"], bgW))
    L.closeSection(s5)

    L.headerAt(ns.L["Lock"])
    local s6 = L.sectionAt()

    local lockEW = GUI:CreateFormCheckbox(s6.frame, nil, "lockedToEssential", cfg, RefreshPowerBars,
        { description = ns.L["Match the width of the Essential Cooldowns row and ride its visibility."] })
    local lockUW = GUI:CreateFormCheckbox(s6.frame, nil, "lockedToUtility", cfg, RefreshPowerBars,
        { description = ns.L["Match the width of the Utility Cooldowns row and ride its visibility."] })
    s6.AddRow(
        row(s6.frame, ns.L["Lock to Essential"], lockEW),
        row(s6.frame, ns.L["Lock to Utility"], lockUW)
    )
    L.closeSection(s6)

    return L.finish()
end

local PRIMARY_BAR_OPTS = {
    enableLabel = ns.L["Enable Primary Power Bar"],
    enableDesc = ns.L["Show the primary power bar (mana, rage, energy, focus, runic power, etc.) as a standalone QUI-managed bar."],
    visibilityDesc = ns.L["When the primary power bar is visible (always, in combat only, when depleted, etc.)."],
    widthDesc = ns.L["Width of the bar in pixels. Ignored when Auto Attach matches the player frame width."],
    offsetXDesc = ns.L["Horizontal pixel offset from the auto-attach anchor (or from its manual position when Auto Attach is off)."],
    offsetYDesc = ns.L["Vertical pixel offset from the auto-attach anchor (or from its manual position when Auto Attach is off)."],
    showPercentDesc = ns.L["Append the percent value after the raw number (e.g. '5000 / 50%')."],
    colorModeDesc = ns.L["How the fill is colored: by power type, class color, or a custom swatch."],
}

local SECONDARY_BAR_OPTS = {
    secondary = true,
    enableLabel = ns.L["Enable Secondary Power Bar"],
    enableDesc = ns.L["Show the secondary power bar for classes with an alternate resource (combo points, runes, holy power, etc.)."],
    visibilityDesc = ns.L["When the secondary power bar is visible (always, in combat only, when depleted, etc.)."],
    autoAttachDesc = ns.L["Automatically attach the bar below the primary power bar. Disable to position the bar freely via the Position controls."],
    widthDesc = ns.L["Width of the bar in pixels."],
    offsetXDesc = ns.L["Horizontal pixel offset from the auto-attach anchor."],
    offsetYDesc = ns.L["Vertical pixel offset from the auto-attach anchor."],
    showPercentDesc = ns.L["Append the percent value after the raw number."],
    colorModeDesc = ns.L["How the fill is colored: by resource type, class color, or a custom swatch."],
}

local function BuildPrimaryPowerSettings(content, _key)
    local profile = GetProfileDB()
    return BuildBarSettings(content, profile and profile.powerBar, PRIMARY_BAR_OPTS)
end

local function BuildSecondaryPowerSettings(content, _key)
    local profile = GetProfileDB()
    return BuildBarSettings(content, profile and profile.secondaryPowerBar, SECONDARY_BAR_OPTS)
end

ResourceBarsBuilders.BuildPrimaryPowerSettings = BuildPrimaryPowerSettings
ResourceBarsBuilders.BuildSecondaryPowerSettings = BuildSecondaryPowerSettings
