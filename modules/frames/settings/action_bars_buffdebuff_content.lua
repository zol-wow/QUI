local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options

local GROW_DIRECTION_OPTIONS = {
    { value = "right_down", text = "Right then Down" },
    { value = "left_down",  text = "Left then Down" },
    { value = "right_up",   text = "Right then Up" },
    { value = "left_up",    text = "Left then Up" },
}

local function RefreshBuffBorders()
    if Opts and Opts.RefreshBuffBorders then
        Opts.RefreshBuffBorders()
        return
    end

    if _G.QUI_RefreshBuffBorders then
        _G.QUI_RefreshBuffBorders()
    end
end

local function GetBuffBordersSettings()
    local db = Opts and Opts.GetDB and Opts.GetDB()
    if not db then
        return nil
    end

    db.buffBorders = db.buffBorders or {}
    return db.buffBorders
end

local function GetGrowDirection(settings, prefix)
    local growLeft = settings[prefix .. "GrowLeft"] == true
    local growUp = settings[prefix .. "GrowUp"] == true

    if growLeft and growUp then
        return "left_up"
    elseif growLeft then
        return "left_down"
    elseif growUp then
        return "right_up"
    end

    return "right_down"
end

local function SetGrowDirection(settings, prefix, value)
    if type(settings) ~= "table" then
        return
    end

    settings[prefix .. "GrowLeft"] = value == "left_down" or value == "left_up"
    settings[prefix .. "GrowUp"] = value == "right_up" or value == "left_up"
end

local function CreateGrowDirectionProxy(settings, prefix)
    return setmetatable({}, {
        __index = function(_, key)
            if key == "growDirection" then
                return GetGrowDirection(settings, prefix)
            end
        end,
        __newindex = function(_, key, value)
            if key == "growDirection" then
                SetGrowDirection(settings, prefix, value)
            end
        end,
    })
end

local function BuildSharedSection(tabContent, headerAt, sectionAt, closeSection, settings)
    headerAt("Shared")
    local card = sectionAt()

    local showStacks = GUI:CreateFormToggle(card.frame, nil, "showStacks", settings, RefreshBuffBorders,
        { description = "Show stack counts on aura icons when the buff or debuff has multiple stacks." })
    local hideSwipe = GUI:CreateFormToggle(card.frame, nil, "hideSwipe", settings, RefreshBuffBorders,
        { description = "Hide the cooldown swipe animation that fills the icon as time expires." })
    card.AddRow(
        Opts.BuildSettingRow(card.frame, "Show Stack Counts", showStacks),
        Opts.BuildSettingRow(card.frame, "Hide Duration Swipe", hideSwipe)
    )

    local borderSize = GUI:CreateFormSlider(card.frame, nil, 1, 6, 1, "borderSize", settings, RefreshBuffBorders, nil,
        { description = "Thickness of the border drawn around buff and debuff icons." })
    local fontSize = GUI:CreateFormSlider(card.frame, nil, 8, 24, 1, "fontSize", settings, RefreshBuffBorders, nil,
        { description = "Font size used for both stack text and countdown text." })
    card.AddRow(
        Opts.BuildSettingRow(card.frame, "Border Size", borderSize),
        Opts.BuildSettingRow(card.frame, "Font Size", fontSize)
    )

    local fadeOutAlpha = GUI:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "fadeOutAlpha", settings, RefreshBuffBorders, nil,
        { description = "Opacity used when a faded buff or debuff frame is not being hovered." })
    card.AddRow(Opts.BuildSettingRow(card.frame, "Fade Out Opacity", fadeOutAlpha))

    closeSection(card)
end

local function BuildAuraSection(tabContent, headerAt, sectionAt, closeSection, settings, spec)
    headerAt(spec.title)

    local general = sectionAt()
    local enabled = GUI:CreateFormToggle(general.frame, nil, spec.enabledKey, settings, RefreshBuffBorders,
        { description = spec.enableDescription })
    local showBorders = GUI:CreateFormToggle(general.frame, nil, spec.showBordersKey, settings, RefreshBuffBorders,
        { description = spec.borderDescription })
    general.AddRow(
        Opts.BuildSettingRow(general.frame, "Enabled", enabled),
        Opts.BuildSettingRow(general.frame, "Show Borders", showBorders)
    )

    local hideFrame = GUI:CreateFormToggle(general.frame, nil, spec.hideFrameKey, settings, RefreshBuffBorders,
        { description = spec.hideDescription })
    local fadeFrame = GUI:CreateFormToggle(general.frame, nil, spec.fadeKey, settings, RefreshBuffBorders,
        { description = spec.fadeDescription })
    general.AddRow(
        Opts.BuildSettingRow(general.frame, "Hide Frame", hideFrame),
        Opts.BuildSettingRow(general.frame, "Fade On Mouseover", fadeFrame)
    )
    closeSection(general)

    local layout = sectionAt()
    local iconSize = GUI:CreateFormSlider(layout.frame, nil, 0, 64, 1, spec.iconSizeKey, settings, RefreshBuffBorders, nil,
        { description = "Pixel size of each icon. Set to 0 to use the default size." })
    local iconsPerRow = GUI:CreateFormSlider(layout.frame, nil, 0, 20, 1, spec.iconsPerRowKey, settings, RefreshBuffBorders, nil,
        { description = "Maximum number of icons before wrapping to a new row. Set to 0 to use the default row length." })
    layout.AddRow(
        Opts.BuildSettingRow(layout.frame, "Icon Size", iconSize),
        Opts.BuildSettingRow(layout.frame, "Icons Per Row", iconsPerRow)
    )

    local iconSpacing = GUI:CreateFormSlider(layout.frame, nil, 0, 12, 1, spec.iconSpacingKey, settings, RefreshBuffBorders, nil,
        { description = "Horizontal gap between icons in the same row." })
    local rowSpacing = GUI:CreateFormSlider(layout.frame, nil, 0, 20, 1, spec.rowSpacingKey, settings, RefreshBuffBorders, nil,
        { description = "Vertical gap between wrapped rows of icons." })
    layout.AddRow(
        Opts.BuildSettingRow(layout.frame, "Icon Spacing", iconSpacing),
        Opts.BuildSettingRow(layout.frame, "Row Spacing", rowSpacing)
    )

    local growProxy = CreateGrowDirectionProxy(settings, spec.prefix)
    local growDirection = GUI:CreateFormDropdown(layout.frame, nil, GROW_DIRECTION_OPTIONS, "growDirection", growProxy, RefreshBuffBorders,
        { description = "Choose which direction new icons are added from the anchor corner." })
    local invertSwipe = GUI:CreateFormToggle(layout.frame, nil, spec.invertSwipeKey, settings, RefreshBuffBorders,
        { description = "Invert the swipe shading so the cooldown fill darkens in the opposite direction." })
    layout.AddRow(
        Opts.BuildSettingRow(layout.frame, "Grow Direction", growDirection),
        Opts.BuildSettingRow(layout.frame, "Invert Swipe Darkening", invertSwipe)
    )
    closeSection(layout)

    local text = sectionAt()
    local stackAnchor = GUI:CreateFormDropdown(text.frame, nil, Opts.NINE_POINT_ANCHOR_OPTIONS, spec.stackAnchorKey, settings, RefreshBuffBorders,
        { description = "Which point of the icon the stack count text is anchored to." })
    local stackX = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.stackOffsetXKey, settings, RefreshBuffBorders, nil,
        { description = "Horizontal offset for the stack count text." })
    text.AddRow(
        Opts.BuildSettingRow(text.frame, "Stack Anchor", stackAnchor),
        Opts.BuildSettingRow(text.frame, "Stack X Offset", stackX)
    )

    local stackY = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.stackOffsetYKey, settings, RefreshBuffBorders, nil,
        { description = "Vertical offset for the stack count text." })
    local durationAnchor = GUI:CreateFormDropdown(text.frame, nil, Opts.NINE_POINT_ANCHOR_OPTIONS, spec.durationAnchorKey, settings, RefreshBuffBorders,
        { description = "Which point of the icon the countdown text is anchored to." })
    text.AddRow(
        Opts.BuildSettingRow(text.frame, "Stack Y Offset", stackY),
        Opts.BuildSettingRow(text.frame, "Duration Anchor", durationAnchor)
    )

    local durationX = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.durationOffsetXKey, settings, RefreshBuffBorders, nil,
        { description = "Horizontal offset for the countdown text." })
    local durationY = GUI:CreateFormSlider(text.frame, nil, -20, 20, 1, spec.durationOffsetYKey, settings, RefreshBuffBorders, nil,
        { description = "Vertical offset for the countdown text." })
    text.AddRow(
        Opts.BuildSettingRow(text.frame, "Duration X Offset", durationX),
        Opts.BuildSettingRow(text.frame, "Duration Y Offset", durationY)
    )
    closeSection(text)
end

local function BuildBuffDebuffTab(tabContent)
    local settings = GetBuffBordersSettings()
    if not settings then
        local label = tabContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 15, -15)
        label:SetPoint("RIGHT", tabContent, "RIGHT", -15, 0)
        label:SetJustifyH("LEFT")
        label:SetText("Buff and debuff settings are unavailable right now.")
        tabContent:SetHeight(80)
        return
    end

    local PAD = Opts.PADDING
    local HEADER_GAP = 26
    local SECTION_GAP = 14
    local y = -10

    GUI:SetSearchContext({tabIndex = 2, tabName = "Unit Frames", subTabIndex = 4, subTabName = "Buff & Debuff"})

    local function headerAt(text)
        local header = Opts.CreateAccentDotLabel(tabContent, text, y)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        header:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end

    local function sectionAt()
        local card = Opts.CreateSettingsCardGroup(tabContent, y)
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, y)
        card.frame:SetPoint("TOPRIGHT", tabContent, "TOPRIGHT", -PAD, y)
        return card
    end

    local function closeSection(card)
        card.Finalize()
        y = y - card.frame:GetHeight() - SECTION_GAP
    end

    BuildSharedSection(tabContent, headerAt, sectionAt, closeSection, settings)

    BuildAuraSection(tabContent, headerAt, sectionAt, closeSection, settings, {
        title = "Buffs",
        prefix = "buff",
        enabledKey = "enableBuffs",
        showBordersKey = "showBuffBorders",
        hideFrameKey = "hideBuffFrame",
        fadeKey = "fadeBuffFrame",
        invertSwipeKey = "buffInvertSwipeDarkening",
        iconSizeKey = "buffIconSize",
        iconsPerRowKey = "buffIconsPerRow",
        iconSpacingKey = "buffIconSpacing",
        rowSpacingKey = "buffRowSpacing",
        stackAnchorKey = "buffStackTextAnchor",
        stackOffsetXKey = "buffStackTextOffsetX",
        stackOffsetYKey = "buffStackTextOffsetY",
        durationAnchorKey = "buffDurationTextAnchor",
        durationOffsetXKey = "buffDurationTextOffsetX",
        durationOffsetYKey = "buffDurationTextOffsetY",
        enableDescription = "Show the custom buff frame managed by QUI.",
        borderDescription = "Draw borders around buff icons.",
        hideDescription = "Hide the buff frame entirely, even when hovering its anchor area.",
        fadeDescription = "Fade the buff frame out until you hover it.",
    })

    BuildAuraSection(tabContent, headerAt, sectionAt, closeSection, settings, {
        title = "Debuffs",
        prefix = "debuff",
        enabledKey = "enableDebuffs",
        showBordersKey = "showDebuffBorders",
        hideFrameKey = "hideDebuffFrame",
        fadeKey = "fadeDebuffFrame",
        invertSwipeKey = "debuffInvertSwipeDarkening",
        iconSizeKey = "debuffIconSize",
        iconsPerRowKey = "debuffIconsPerRow",
        iconSpacingKey = "debuffIconSpacing",
        rowSpacingKey = "debuffRowSpacing",
        stackAnchorKey = "debuffStackTextAnchor",
        stackOffsetXKey = "debuffStackTextOffsetX",
        stackOffsetYKey = "debuffStackTextOffsetY",
        durationAnchorKey = "debuffDurationTextAnchor",
        durationOffsetXKey = "debuffDurationTextOffsetX",
        durationOffsetYKey = "debuffDurationTextOffsetY",
        enableDescription = "Show the custom debuff frame managed by QUI.",
        borderDescription = "Draw borders around debuff icons.",
        hideDescription = "Hide the debuff frame entirely, even when hovering its anchor area.",
        fadeDescription = "Fade the debuff frame out until you hover it.",
    })

    tabContent:SetHeight(math.abs(y) + 40)
end

ns.QUI_BuffDebuffOptions = {
    BuildBuffDebuffTab = BuildBuffDebuffTab,
}
