local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local Helpers = ns.Helpers

local ResourceBarsBuilders = ns.QUI_ResourceBarsSettingsBuilders or {}
ns.QUI_ResourceBarsSettingsBuilders = ResourceBarsBuilders

local TEXT_SPEC_KEYS = {
    "showText", "showPercent", "hidePercentSymbol", "textAlign",
    "textSize", "textX", "textY", "textUseClassColor", "textCustomColor",
}

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

local function GetRuntime()
    local GUI = QUI and QUI.GUI
    local U = ns.QUI_LayoutMode_Utils
    if not GUI or not U
        or type(U.StandardRelayout) ~= "function"
        or type(U.CreateCollapsible) ~= "function"
        or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.PlaceRow) ~= "function"
        or type(U.GetTextureList) ~= "function" then
        return nil, nil, 32
    end

    return GUI, U, U.FORM_ROW or 32
end

local function GetProfileDB()
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    return core and core.db and core.db.profile or nil
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
    if not spec then
        return 0
    end
    return GetSpecializationInfo(spec) or 0
end

local function EnsureTextSpecOverrides(cfg, specID)
    if type(cfg.textSpecOverrides) ~= "table" then
        cfg.textSpecOverrides = {}
    end
    if type(cfg.textSpecOverrides[specID]) ~= "table" then
        local base = {}
        for _, key in ipairs(TEXT_SPEC_KEYS) do
            local value = cfg[key]
            if type(value) == "table" then
                local copy = {}
                for tableKey, tableValue in pairs(value) do
                    copy[tableKey] = tableValue
                end
                value = copy
            end
            base[key] = value
        end
        cfg.textSpecOverrides[specID] = base
    end
    return cfg.textSpecOverrides[specID]
end

local function BuildPrimaryPowerSettings(content, key)
    local GUI, U, FORM_ROW = GetRuntime()
    local profile = GetProfileDB()
    local primary = profile and profile.powerBar
    if not GUI or not U or not primary then
        return 80
    end

    key = key or "primaryPower"

    local sections = {}
    local function relayout()
        U.StandardRelayout(content, sections)
    end

    local enableRow = CreateFrame("Frame", nil, content)
    enableRow:SetHeight(FORM_ROW)
    local enableCheck = GUI:CreateFormCheckbox(enableRow, "Enable", "enabled", primary, function()
        RefreshPowerBars()
    end, { description = "Show the primary power bar (mana, rage, energy, focus, runic power, etc.) as a standalone QUI-managed bar." })
    enableCheck:SetPoint("TOPLEFT", 0, 0)
    enableCheck:SetPoint("RIGHT", enableRow, "RIGHT", 0, 0)
    sections[#sections + 1] = enableRow

    U.CreateCollapsible(content, "General", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        local visDD = GUI:CreateFormDropdown(body, "Visibility", VISIBILITY_OPTIONS, "visibility", primary, RefreshPowerBars,
            { description = "When the primary power bar is visible (always, in combat only, when depleted, etc.)." })
        sy = U.PlaceRow(visDD, body, sy)

        local oriDD = GUI:CreateFormDropdown(body, "Orientation", ORIENTATION_OPTIONS, "orientation", primary, RefreshPowerBars,
            { description = "Fill direction: horizontal (left-to-right) or vertical (bottom-to-top)." })
        sy = U.PlaceRow(oriDD, body, sy)

        local autoCheck = GUI:CreateFormCheckbox(body, "Auto Attach", "autoAttach", primary, RefreshPowerBars,
            { description = "Automatically attach the bar below the player unit frame. Disable to position the bar freely via the Position collapsible." })
        sy = U.PlaceRow(autoCheck, body, sy)

        local standCheck = GUI:CreateFormCheckbox(body, "Standalone Mode", "standaloneMode", primary, RefreshPowerBars,
            { description = "Keep this bar always visible even when the player unit frame is hidden." })
        U.PlaceRow(standCheck, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Dimensions", 5 * FORM_ROW + 8, function(body)
        local sy = -4
        local wSlider = GUI:CreateFormSlider(body, "Width", 50, 600, 1, "width", primary, RefreshPowerBars, nil,
            { description = "Width of the bar in pixels. Ignored when Auto Attach matches the player frame width." })
        sy = U.PlaceRow(wSlider, body, sy)

        local hSlider = GUI:CreateFormSlider(body, "Height", 2, 40, 1, "height", primary, RefreshPowerBars, nil,
            { description = "Height of the bar in pixels." })
        sy = U.PlaceRow(hSlider, body, sy)

        local snapSlider = GUI:CreateFormSlider(body, "Snap Gap", 0, 20, 1, "snapGap", primary, RefreshPowerBars, nil,
            { description = "Pixel gap between this bar and the frame it auto-attaches to." })
        sy = U.PlaceRow(snapSlider, body, sy)

        local xSlider = GUI:CreateFormSlider(body, "X Offset", -500, 500, 1, "offsetX", primary, RefreshPowerBars, nil,
            { description = "Horizontal pixel offset from the auto-attach anchor (or from its manual position when Auto Attach is off)." })
        sy = U.PlaceRow(xSlider, body, sy)

        local ySlider = GUI:CreateFormSlider(body, "Y Offset", -500, 500, 1, "offsetY", primary, RefreshPowerBars, nil,
            { description = "Vertical pixel offset from the auto-attach anchor (or from its manual position when Auto Attach is off)." })
        U.PlaceRow(ySlider, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Appearance", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local texDD = GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "texture", primary, RefreshPowerBars,
            { description = "Statusbar texture used for the power fill." })
        sy = U.PlaceRow(texDD, body, sy)

        local borderSlider = GUI:CreateFormSlider(body, "Border Size", 0, 5, 1, "borderSize", primary, RefreshPowerBars, nil,
            { description = "Border thickness in pixels. Set to 0 to hide the border." })
        U.PlaceRow(borderSlider, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Text", 7 * FORM_ROW + 8, function(body)
        local sy = -4
        local showTextCheck = GUI:CreateFormCheckbox(body, "Show Text", "showText", primary, RefreshPowerBars,
            { description = "Show the power value as text on the bar." })
        sy = U.PlaceRow(showTextCheck, body, sy)

        local showPctCheck = GUI:CreateFormCheckbox(body, "Show Percent", "showPercent", primary, RefreshPowerBars,
            { description = "Append the percent value after the raw number (e.g. '5000 / 50%')." })
        sy = U.PlaceRow(showPctCheck, body, sy)

        local hidePctSymbolCheck = GUI:CreateFormCheckbox(body, "Hide % Symbol", "hidePercentSymbol", primary, RefreshPowerBars,
            { description = "Drop the '%' sign from percent text for a cleaner look." })
        sy = U.PlaceRow(hidePctSymbolCheck, body, sy)

        local textAlignDD = GUI:CreateFormDropdown(body, "Text Alignment", TEXT_ALIGN_OPTIONS, "textAlign", primary, RefreshPowerBars,
            { description = "Horizontal alignment of the power text on the bar." })
        sy = U.PlaceRow(textAlignDD, body, sy)

        local textSizeSlider = GUI:CreateFormSlider(body, "Text Size", 6, 24, 1, "textSize", primary, RefreshPowerBars, nil,
            { description = "Font size used for the power text." })
        sy = U.PlaceRow(textSizeSlider, body, sy)

        local textXSlider = GUI:CreateFormSlider(body, "Text X Offset", -50, 50, 1, "textX", primary, RefreshPowerBars, nil,
            { description = "Horizontal pixel offset for the power text from its alignment point." })
        sy = U.PlaceRow(textXSlider, body, sy)

        local textYSlider = GUI:CreateFormSlider(body, "Text Y Offset", -50, 50, 1, "textY", primary, RefreshPowerBars, nil,
            { description = "Vertical pixel offset for the power text from its alignment point." })
        U.PlaceRow(textYSlider, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Colors", 3 * FORM_ROW + 8, function(body)
        local sy = -4
        local colorDD = GUI:CreateFormDropdown(body, "Color Mode", COLOR_MODE_OPTIONS, "colorMode", primary, RefreshPowerBars,
            { description = "How the fill is colored: by power type, class color, role, or a custom swatch." })
        sy = U.PlaceRow(colorDD, body, sy)

        local customPicker = GUI:CreateFormColorPicker(body, "Custom Color", "customColor", primary, RefreshPowerBars, nil,
            { description = "Custom fill color used when Color Mode is set to Custom." })
        sy = U.PlaceRow(customPicker, body, sy)

        local bgPicker = GUI:CreateFormColorPicker(body, "Background Color", "bgColor", primary, RefreshPowerBars, nil,
            { description = "Backdrop color drawn behind the fill." })
        U.PlaceRow(bgPicker, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Lock", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local lockEss = GUI:CreateFormCheckbox(body, "Lock to Essential", "lockedToEssential", primary, RefreshPowerBars,
            { description = "Match the width of the Essential Cooldowns row and ride its visibility." })
        sy = U.PlaceRow(lockEss, body, sy)

        local lockUtil = GUI:CreateFormCheckbox(body, "Lock to Utility", "lockedToUtility", primary, RefreshPowerBars,
            { description = "Match the width of the Utility Cooldowns row and ride its visibility." })
        U.PlaceRow(lockUtil, body, sy)
    end, sections, relayout)

    U.BuildPositionCollapsible(content, key, { autoWidth = true }, sections, relayout)
    U.BuildOpenFullSettingsLink(content, key, sections, relayout)

    relayout()
    return content:GetHeight()
end

local function BuildSecondaryPowerSettings(content, key)
    local GUI, U, FORM_ROW = GetRuntime()
    local profile = GetProfileDB()
    local secondary = profile and profile.secondaryPowerBar
    if not GUI or not U or not secondary then
        return 80
    end

    key = key or "secondaryPower"

    local sections = {}
    local function relayout()
        U.StandardRelayout(content, sections)
    end

    local enableRow = CreateFrame("Frame", nil, content)
    enableRow:SetHeight(FORM_ROW)
    local enableCheck = GUI:CreateFormCheckbox(enableRow, "Enable", "enabled", secondary, function()
        RefreshPowerBars()
    end, { description = "Show the secondary power bar for classes with an alternate resource (combo points, runes, holy power, etc.)." })
    enableCheck:SetPoint("TOPLEFT", 0, 0)
    enableCheck:SetPoint("RIGHT", enableRow, "RIGHT", 0, 0)
    sections[#sections + 1] = enableRow

    U.CreateCollapsible(content, "General", 7 * FORM_ROW + 8, function(body)
        local sy = -4
        local visDD = GUI:CreateFormDropdown(body, "Visibility", VISIBILITY_OPTIONS, "visibility", secondary, RefreshPowerBars,
            { description = "When the secondary power bar is visible (always, in combat only, when depleted, etc.)." })
        sy = U.PlaceRow(visDD, body, sy)

        local oriDD = GUI:CreateFormDropdown(body, "Orientation", ORIENTATION_OPTIONS, "orientation", secondary, RefreshPowerBars,
            { description = "Fill direction: horizontal (left-to-right) or vertical (bottom-to-top)." })
        sy = U.PlaceRow(oriDD, body, sy)

        local autoCheck = GUI:CreateFormCheckbox(body, "Auto Attach", "autoAttach", secondary, RefreshPowerBars,
            { description = "Automatically attach the bar below the primary power bar. Disable to position the bar freely via the Position collapsible." })
        sy = U.PlaceRow(autoCheck, body, sy)

        local standCheck = GUI:CreateFormCheckbox(body, "Standalone Mode", "standaloneMode", secondary, RefreshPowerBars,
            { description = "Keep this bar always visible even when the player unit frame is hidden." })
        sy = U.PlaceRow(standCheck, body, sy)

        local swapCheck = GUI:CreateFormCheckbox(body, "Swap to Primary Position", "swapToPrimaryPosition", secondary, RefreshPowerBars,
            { description = "When the secondary resource is the dominant one for your spec, swap it into the primary bar's position for the duration of that spec." })
        sy = U.PlaceRow(swapCheck, body, sy)

        local hideCheck = GUI:CreateFormCheckbox(body, "Hide Primary on Swap", "hidePrimaryOnSwap", secondary, RefreshPowerBars,
            { description = "When Swap to Primary Position is active, also hide the primary power bar to avoid showing both resources." })
        sy = U.PlaceRow(hideCheck, body, sy)

        local fragCheck = GUI:CreateFormCheckbox(body, "Show Fragmented Power Bar Text", "showFragmentedPowerBarText", secondary, RefreshPowerBars,
            { description = "Display the numeric current/max value on fragmented resources (soul shards, holy power, combo points)." })
        U.PlaceRow(fragCheck, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Dimensions", 5 * FORM_ROW + 8, function(body)
        local sy = -4
        local wSlider = GUI:CreateFormSlider(body, "Width", 50, 600, 1, "width", secondary, RefreshPowerBars, nil,
            { description = "Width of the bar in pixels." })
        sy = U.PlaceRow(wSlider, body, sy)

        local hSlider = GUI:CreateFormSlider(body, "Height", 2, 40, 1, "height", secondary, RefreshPowerBars, nil,
            { description = "Height of the bar in pixels." })
        sy = U.PlaceRow(hSlider, body, sy)

        local snapSlider = GUI:CreateFormSlider(body, "Snap Gap", 0, 20, 1, "snapGap", secondary, RefreshPowerBars, nil,
            { description = "Pixel gap between this bar and the frame it auto-attaches to." })
        sy = U.PlaceRow(snapSlider, body, sy)

        local xSlider = GUI:CreateFormSlider(body, "X Offset", -500, 500, 1, "offsetX", secondary, RefreshPowerBars, nil,
            { description = "Horizontal pixel offset from the auto-attach anchor." })
        sy = U.PlaceRow(xSlider, body, sy)

        local ySlider = GUI:CreateFormSlider(body, "Y Offset", -500, 500, 1, "offsetY", secondary, RefreshPowerBars, nil,
            { description = "Vertical pixel offset from the auto-attach anchor." })
        U.PlaceRow(ySlider, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Appearance", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local texDD = GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "texture", secondary, RefreshPowerBars,
            { description = "Statusbar texture used for the power fill." })
        sy = U.PlaceRow(texDD, body, sy)

        local borderSlider = GUI:CreateFormSlider(body, "Border Size", 0, 5, 1, "borderSize", secondary, RefreshPowerBars, nil,
            { description = "Border thickness in pixels. Set to 0 to hide the border." })
        U.PlaceRow(borderSlider, body, sy)
    end, sections, relayout)

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

    U.CreateCollapsible(content, "Text", 9 * FORM_ROW + 8, function(body)
        local sy = -4

        local perSpecCheck = GUI:CreateFormCheckbox(body, "Per-Spec Text Settings", "textPerSpec", secondary, RefreshPowerBars,
            { description = "Store the text settings below separately for each specialization, so different specs can use different text layouts." })
        sy = U.PlaceRow(perSpecCheck, body, sy)

        if secondary.textPerSpec then
            local specName = select(2, GetSpecializationInfo(GetSpecialization() or 0)) or "Unknown"
            local specLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            specLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 4, sy - 2)
            specLabel:SetTextColor(0.6, 0.6, 0.6, 0.8)
            specLabel:SetText("Editing: " .. specName)
            sy = sy - 16
        end

        local showTextCheck = GUI:CreateFormCheckbox(body, "Show Text", "showText", textProxy, RefreshPowerBars,
            { description = "Show the power value as text on the bar." })
        sy = U.PlaceRow(showTextCheck, body, sy)

        local showPctCheck = GUI:CreateFormCheckbox(body, "Show Percent", "showPercent", textProxy, RefreshPowerBars,
            { description = "Append the percent value after the raw number." })
        sy = U.PlaceRow(showPctCheck, body, sy)

        local hidePctSymbolCheck = GUI:CreateFormCheckbox(body, "Hide % Symbol", "hidePercentSymbol", textProxy, RefreshPowerBars,
            { description = "Drop the '%' sign from percent text for a cleaner look." })
        sy = U.PlaceRow(hidePctSymbolCheck, body, sy)

        local textAlignDD = GUI:CreateFormDropdown(body, "Text Alignment", TEXT_ALIGN_OPTIONS, "textAlign", textProxy, RefreshPowerBars,
            { description = "Horizontal alignment of the power text on the bar." })
        sy = U.PlaceRow(textAlignDD, body, sy)

        local textSizeSlider = GUI:CreateFormSlider(body, "Text Size", 6, 24, 1, "textSize", textProxy, RefreshPowerBars, nil,
            { description = "Font size used for the power text." })
        sy = U.PlaceRow(textSizeSlider, body, sy)

        local textXSlider = GUI:CreateFormSlider(body, "Text X Offset", -50, 50, 1, "textX", textProxy, RefreshPowerBars, nil,
            { description = "Horizontal pixel offset for the power text from its alignment point." })
        sy = U.PlaceRow(textXSlider, body, sy)

        local textYSlider = GUI:CreateFormSlider(body, "Text Y Offset", -50, 50, 1, "textY", textProxy, RefreshPowerBars, nil,
            { description = "Vertical pixel offset for the power text from its alignment point." })
        U.PlaceRow(textYSlider, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Colors", 3 * FORM_ROW + 8, function(body)
        local sy = -4
        local colorDD = GUI:CreateFormDropdown(body, "Color Mode", COLOR_MODE_OPTIONS, "colorMode", secondary, RefreshPowerBars,
            { description = "How the fill is colored: by resource type, class color, role, or a custom swatch." })
        sy = U.PlaceRow(colorDD, body, sy)

        local customPicker = GUI:CreateFormColorPicker(body, "Custom Color", "customColor", secondary, RefreshPowerBars, nil,
            { description = "Custom fill color used when Color Mode is set to Custom." })
        sy = U.PlaceRow(customPicker, body, sy)

        local bgPicker = GUI:CreateFormColorPicker(body, "Background Color", "bgColor", secondary, RefreshPowerBars, nil,
            { description = "Backdrop color drawn behind the fill." })
        U.PlaceRow(bgPicker, body, sy)
    end, sections, relayout)

    U.CreateCollapsible(content, "Lock", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local lockEss = GUI:CreateFormCheckbox(body, "Lock to Essential", "lockedToEssential", secondary, RefreshPowerBars,
            { description = "Match the width of the Essential Cooldowns row and ride its visibility." })
        sy = U.PlaceRow(lockEss, body, sy)

        local lockUtil = GUI:CreateFormCheckbox(body, "Lock to Utility", "lockedToUtility", secondary, RefreshPowerBars,
            { description = "Match the width of the Utility Cooldowns row and ride its visibility." })
        U.PlaceRow(lockUtil, body, sy)
    end, sections, relayout)

    U.BuildPositionCollapsible(content, key, { autoWidth = true }, sections, relayout)
    U.BuildOpenFullSettingsLink(content, key, sections, relayout)

    relayout()
    return content:GetHeight()
end

ResourceBarsBuilders.BuildPrimaryPowerSettings = BuildPrimaryPowerSettings
ResourceBarsBuilders.BuildSecondaryPowerSettings = BuildSecondaryPowerSettings
