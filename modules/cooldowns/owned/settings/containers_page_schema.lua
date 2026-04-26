local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Renderer = Settings and Settings.Renderer
local Schema = Settings and Settings.Schema
local FullSurface = Settings and Settings.FullSurface
if not Renderer or type(Renderer.RenderFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function" then
    return
end

local QUI = QUI
local LSM = ns.LSM
local Helpers = ns.Helpers

local CDMSettingsSchema = ns.QUI_CooldownManagerSettingsSchema or {}
ns.QUI_CooldownManagerSettingsSchema = CDMSettingsSchema

local TAB_SEARCH_CONTEXTS = {
    entries = "Entries",
    layout = "Appearance",
    filters = "Filters",
    perspec = "Per-Spec",
    effects = "Effects",
    keybinds = "Keybinds",
}

local HEADER_GAP = 22
local SECTION_BOTTOM_PAD = 12

local KEYBIND_ANCHOR_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "CENTER", text = "Center" },
}

local COLOR_MODE_OPTIONS = {
    { value = "default", text = "Default (Blizzard)" },
    { value = "class", text = "Class Color" },
    { value = "accent", text = "UI Accent Color" },
    { value = "custom", text = "Custom Color" },
}

local GLOW_TYPE_OPTIONS = {
    { value = "Pixel Glow", text = "Pixel Glow" },
    { value = "Autocast Shine", text = "Autocast Shine" },
    { value = "Button Glow", text = "Button Glow" },
    { value = "Flash", text = "Flash" },
    { value = "Hammer", text = "Hammer" },
    { value = "Proc Glow", text = "Proc Glow" },
}

local DISPLAY_MODE_OPTIONS = {
    { value = "always", text = "Always" },
    { value = "active", text = "Active Only" },
    { value = "combat", text = "Combat Only" },
}

local TEXT_ANCHOR_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOP", text = "Top" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local AURA_GROWTH_DIRECTION_OPTIONS = {
    { value = "CENTERED_HORIZONTAL", text = "Centered" },
    { value = "UP", text = "Grow Up" },
    { value = "DOWN", text = "Grow Down" },
}

local INACTIVE_MODE_OPTIONS = {
    { value = "always", text = "Always Show" },
    { value = "fade", text = "Fade When Inactive" },
    { value = "hide", text = "Hide When Inactive" },
}

local STACK_DIRECTION_OPTIONS = {
    { value = true, text = "Up / Right" },
    { value = false, text = "Down / Left" },
}

local BAR_ORIENTATION_OPTIONS = {
    { value = "horizontal", text = "Horizontal" },
    { value = "vertical", text = "Vertical" },
}

local BAR_FILL_DIRECTION_OPTIONS = {
    { value = "up", text = "Fill Up" },
    { value = "down", text = "Fill Down" },
}

local BAR_ICON_POSITION_OPTIONS = {
    { value = "top", text = "Top" },
    { value = "bottom", text = "Bottom" },
}

local TRACKER_LAYOUT_DIRECTION_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal" },
    { value = "VERTICAL", text = "Vertical" },
}

local CUSTOM_BAR_GROW_DIRECTION_OPTIONS = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
    { value = "DOWN", text = "Down" },
    { value = "UP", text = "Up" },
}

local function GetGUI()
    return QUI and QUI.GUI or nil
end

local function GetOptionsAPI()
    return ns.QUI_Options
end

local function BuildStatusbarTextureOptions()
    local textureOptions = {}
    if not LSM or type(LSM.HashTable) ~= "function" then
        return textureOptions
    end

    local textures = LSM:HashTable("statusbar")
    if type(textures) ~= "table" then
        return textureOptions
    end

    for name in pairs(textures) do
        textureOptions[#textureOptions + 1] = {
            value = name,
            text = name,
        }
    end

    table.sort(textureOptions, function(a, b)
        return a.text < b.text
    end)

    return textureOptions
end

local function SetSearchContext(tabKey)
    local gui = GetGUI()
    if gui and type(gui.SetSearchContext) == "function" then
        gui:SetSearchContext({
            tabIndex = 4,
            tabName = "Cooldown Manager",
            subTabIndex = 0,
            subTabName = TAB_SEARCH_CONTEXTS[tabKey] or "Containers",
        })
    end
end

local function GetModel()
    return ns.QUI_CooldownManagerSettingsModel
end

local function GetProfileDB()
    return QUI and QUI.db and QUI.db.profile or nil
end

local function NormalizeContainerKey(containerKey)
    local model = GetModel()
    local normalize = model and model.NormalizeContainerKey
    if type(normalize) == "function" then
        return normalize(containerKey)
    end
    return containerKey
end

local function IsBuiltIn(containerKey)
    local model = GetModel()
    local isBuiltIn = model and model.IsBuiltIn
    return type(isBuiltIn) == "function" and isBuiltIn(containerKey) == true
end

local function ResolveContainerType(containerKey)
    if containerKey == "essential" or containerKey == "utility" then return "cooldown" end
    if containerKey == "buff" then return "aura" end
    if containerKey == "trackedBar" then return "auraBar" end
    local ncdm = QUI and QUI.db and QUI.db.profile and QUI.db.profile.ncdm
    local settings = ncdm and ncdm.containers and ncdm.containers[containerKey]
    return settings and settings.containerType or "cooldown"
end

local function RenderUnavailableLabel(sectionHost, text)
    local label = sectionHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 10, -10)
    label:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", -10, -10)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    label:SetTextColor(0.6, 0.6, 0.6, 1)
    return 60
end

local function ResolveContainerKey(ctx)
    local key = ctx and ctx.options and ctx.options.containerKey or nil
    key = NormalizeContainerKey(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return key
end

local function ResolveKeybindsDB(containerKey)
    local profile = GetProfileDB()
    if not profile or type(containerKey) ~= "string" or containerKey == "" then
        return nil
    end

    if containerKey == "essential" then
        return profile.viewers and profile.viewers.EssentialCooldownViewer or nil
    end
    if containerKey == "utility" then
        return profile.viewers and profile.viewers.UtilityCooldownViewer or nil
    end

    local ncdm = profile.ncdm
    return ncdm and ncdm.containers and ncdm.containers[containerKey] or nil
end

local function ResolveTrackerDB(containerKey)
    local profile = GetProfileDB()
    if not profile or type(containerKey) ~= "string" or containerKey == "" then
        return nil
    end

    local ncdm = profile.ncdm
    if not ncdm then
        return nil
    end

    return ncdm[containerKey] or (ncdm.containers and ncdm.containers[containerKey]) or nil
end

local function RefreshKeybinds()
    if _G.QUI_RefreshKeybinds then
        _G.QUI_RefreshKeybinds()
    end
end

local function RefreshContainer(containerKey)
    if type(containerKey) ~= "string" or containerKey == "" then
        if _G.QUI_RefreshNCDM then
            _G.QUI_RefreshNCDM()
        end
        return
    end

    if _G.QUI_ForceLayoutContainer then
        _G.QUI_ForceLayoutContainer(containerKey)
    elseif _G.QUI_RefreshNCDM then
        _G.QUI_RefreshNCDM()
    end
end

local function RefreshSwipe()
    if _G.QUI_RefreshCooldownSwipe then
        _G.QUI_RefreshCooldownSwipe()
    end
end

local function RefreshCooldownEffects()
    if _G.QUI_RefreshCooldownEffects then
        _G.QUI_RefreshCooldownEffects()
    end
end

local function RefreshGlows()
    if _G.QUI_RefreshCustomGlows then
        _G.QUI_RefreshCustomGlows()
    end
end

local function RefreshHighlighter()
    if _G.QUI_RefreshCooldownHighlighter then
        _G.QUI_RefreshCooldownHighlighter()
    end
end

local function PrepareSectionHost(sectionHost, ctx)
    if not sectionHost then
        return
    end

    local pad = ctx and ctx.surface and ctx.surface.padding or 0
    local width = ctx and ctx.width or 760
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end
    width = math.max(320, width - (pad * 2))
    if sectionHost.SetWidth then
        sectionHost:SetWidth(width)
    end
end

local function RenderInfoMessage(sectionHost, ctx, tabKey, text)
    if not sectionHost or type(text) ~= "string" or text == "" then
        return 60
    end

    SetSearchContext(tabKey)
    PrepareSectionHost(sectionHost, ctx)

    local label = sectionHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 10, -10)
    label:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", -10, -10)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetText(text)
    label:SetTextColor(0.75, 0.75, 0.75, 1)

    local height = label.GetStringHeight and label:GetStringHeight() or 0
    if type(height) ~= "number" or height <= 0 then
        height = 40
    end
    return math.max(height + 20, 60)
end

local function CreateSectionBuilder(sectionHost, ctx, tabKey)
    local optionsAPI = GetOptionsAPI()
    if not optionsAPI then
        return nil
    end

    PrepareSectionHost(sectionHost, ctx)
    SetSearchContext(tabKey)

    local y = 0
    local builder = {}

    function builder.Header(text)
        if type(text) ~= "string" or text == "" then
            return
        end

        local header = optionsAPI.CreateAccentDotLabel(sectionHost, text, y)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, y)
        header:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, y)
        y = y - HEADER_GAP
    end

    function builder.Card()
        local card = optionsAPI.CreateSettingsCardGroup(sectionHost, y)
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, y)
        card.frame:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, y)
        return card
    end

    function builder.CloseCard(card)
        card.Finalize()
        y = y - card.frame:GetHeight()
    end

    function builder.Spacer(amount)
        y = y - (amount or 10)
    end

    function builder.Height(extra)
        return math.abs(y) + (extra or SECTION_BOTTOM_PAD)
    end

    return builder
end

local function RefreshUtilityAnchor()
    if _G.QUI_RefreshNCDM then
        _G.QUI_RefreshNCDM()
    end
    if _G.QUI_ApplyUtilityAnchor then
        _G.QUI_ApplyUtilityAnchor()
    end
end

local function AppendTrackerGeneralSection(builder, gui, optionsAPI, tracker, containerKey, refresh)
    if not builder or not gui or not optionsAPI or type(tracker) ~= "table" then
        return
    end

    local isEssential = (containerKey == "essential")
    local isCustomBar = (tracker.containerType == "customBar")

    tracker.iconDisplayMode = tracker.iconDisplayMode or "always"
    tracker.layoutDirection = tracker.layoutDirection or "HORIZONTAL"
    if isCustomBar then
        tracker.growDirection = tracker.growDirection or "RIGHT"
    end

    builder.Header("General")
    local card = builder.Card()

    local displayModeDropdown = gui:CreateFormDropdown(card.frame, nil, DISPLAY_MODE_OPTIONS, "iconDisplayMode", tracker, refresh, {
        description = "When icons appear: always visible, only while the spell is active/on cooldown, or only while in combat.",
    })

    if isCustomBar then
        local growDirectionDropdown = gui:CreateFormDropdown(card.frame, nil, CUSTOM_BAR_GROW_DIRECTION_OPTIONS, "growDirection", tracker, function()
            local growDirection = tracker.growDirection
            tracker.layoutDirection = (growDirection == "UP" or growDirection == "DOWN") and "VERTICAL" or "HORIZONTAL"
            refresh()
        end, {
            description = "Direction new icons are added from the anchor. Right/Left builds a horizontal bar, Up/Down builds a vertical bar.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Display Mode", displayModeDropdown),
            optionsAPI.BuildSettingRow(card.frame, "Grow Direction", growDirectionDropdown)
        )
    else
        local layoutDirectionDropdown = gui:CreateFormDropdown(card.frame, nil, TRACKER_LAYOUT_DIRECTION_OPTIONS, "layoutDirection", tracker, refresh, {
            description = "Whether this container's rows flow horizontally or vertically.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Display Mode", displayModeDropdown),
            optionsAPI.BuildSettingRow(card.frame, "Layout Direction", layoutDirectionDropdown)
        )
    end

    local clickableIconsCheckbox = gui:CreateFormCheckbox(card.frame, nil, "clickableIcons", tracker, refresh, {
        description = "Allow icons to receive mouse clicks (tooltips, macros, activation). Turn off to make the container pass clicks through.",
    })
    local desaturateOnCooldownCheckbox = gui:CreateFormCheckbox(card.frame, nil, "desaturateOnCooldown", tracker, refresh, {
        description = "Desaturate icons while they are on cooldown so off-cooldown spells stand out visually.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Clickable Icons", clickableIconsCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Desaturate On Cooldown", desaturateOnCooldownCheckbox)
    )

    local greyOutInactiveCheckbox = gui:CreateFormCheckbox(card.frame, nil, "greyOutInactive", tracker, refresh, {
        description = "Grey out debuff icons when the debuff is not currently active.",
    })
    local greyOutInactiveBuffsCheckbox = gui:CreateFormCheckbox(card.frame, nil, "greyOutInactiveBuffs", tracker, refresh, {
        description = "Grey out buff icons when the buff is not currently active.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Grey Out Inactive Debuffs", greyOutInactiveCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Grey Out Inactive Buffs", greyOutInactiveBuffsCheckbox)
    )

    if not isEssential then
        local anchorBelowEssentialCheckbox = gui:CreateFormCheckbox(card.frame, nil, "anchorBelowEssential", tracker, RefreshUtilityAnchor, {
            description = "Anchor this container below the essential container so they stack together.",
        })
        local anchorGapSlider = gui:CreateFormSlider(card.frame, nil, -200, 200, 1, "anchorGap", tracker, RefreshUtilityAnchor, nil, {
            description = "Pixel gap between the essential container and this one when Anchor Below Essential is on.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Anchor Below Essential", anchorBelowEssentialCheckbox),
            optionsAPI.BuildSettingRow(card.frame, "Anchor Gap", anchorGapSlider)
        )
    end

    builder.CloseCard(card)
end

local function AppendTrackerRowSection(builder, gui, optionsAPI, rowNum, rowData, refresh)
    if not builder or not gui or not optionsAPI or type(rowData) ~= "table" then
        return
    end

    if Helpers and type(Helpers.EnsureDefaults) == "function" then
        Helpers.EnsureDefaults(rowData, {
            xOffset = 0,
            durationSize = 14,
            durationOffsetX = 0,
            durationOffsetY = 0,
            durationTextColor = { 1, 1, 1, 1 },
            durationAnchor = "CENTER",
            stackSize = 14,
            stackOffsetX = 0,
            stackOffsetY = 0,
            stackTextColor = { 1, 1, 1, 1 },
            stackAnchor = "BOTTOMRIGHT",
            opacity = 1.0,
        })
    end

    builder.Header("Row " .. rowNum)
    local card = builder.Card()

    local iconsInRowSlider = gui:CreateFormSlider(card.frame, nil, 0, 20, 1, "iconCount", rowData, refresh, nil, {
        description = "How many icons fit in this row before the container moves overflow to the next row.",
    })
    local iconSizeSlider = gui:CreateFormSlider(card.frame, nil, 5, 80, 1, "iconSize", rowData, refresh, nil, {
        description = "Square size of each icon in this row, in pixels.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Icons in Row", iconsInRowSlider),
        optionsAPI.BuildSettingRow(card.frame, "Icon Size", iconSizeSlider)
    )

    local borderSizeSlider = gui:CreateFormSlider(card.frame, nil, 0, 5, 1, "borderSize", rowData, refresh, nil, {
        description = "Border thickness in pixels around each icon in this row. Set to 0 to hide.",
    })
    local borderColorPicker = gui:CreateFormColorPicker(card.frame, nil, "borderColorTable", rowData, refresh, nil, {
        description = "Border color applied to every icon in this row.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Border Size", borderSizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Border Color", borderColorPicker)
    )

    local iconZoomSlider = gui:CreateFormSlider(card.frame, nil, 0, 0.2, 0.01, "zoom", rowData, refresh, nil, {
        description = "Crop the edges of each icon to hide Blizzard's default border. Higher values crop more.",
    })
    local paddingSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "padding", rowData, refresh, nil, {
        description = "Pixel gap between adjacent icons. Negative values overlap icons.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Icon Zoom", iconZoomSlider),
        optionsAPI.BuildSettingRow(card.frame, "Padding", paddingSlider)
    )

    local rowYOffsetSlider = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "yOffset", rowData, refresh, nil, {
        description = "Vertical pixel offset for this row relative to the container's anchor.",
    })
    local rowXOffsetSlider = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "xOffset", rowData, refresh, nil, {
        description = "Horizontal pixel offset for this row relative to the container's anchor.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Row Y-Offset", rowYOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Row X-Offset", rowXOffsetSlider)
    )

    local rowOpacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1.0, 0.05, "opacity", rowData, refresh, nil, {
        description = "Opacity of every icon in this row. 0 is fully transparent, 1 is fully opaque.",
    })
    local hideDurationTextCheckbox = gui:CreateFormCheckbox(card.frame, nil, "hideDurationText", rowData, refresh, {
        description = "Hide the duration countdown text on every icon in this row. The swipe animation still plays.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Row Opacity", rowOpacitySlider),
        optionsAPI.BuildSettingRow(card.frame, "Hide Duration Text", hideDurationTextCheckbox)
    )

    local durationTextSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 50, 1, "durationSize", rowData, refresh, nil, {
        description = "Font size for the duration countdown text on icons in this row.",
    })
    local durationAnchorDropdown = gui:CreateFormDropdown(card.frame, nil, TEXT_ANCHOR_OPTIONS, "durationAnchor", rowData, refresh, {
        description = "Which corner of the icon the duration text is anchored to.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Duration Text Size", durationTextSizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Anchor Duration To", durationAnchorDropdown)
    )

    local durationXOffsetSlider = gui:CreateFormSlider(card.frame, nil, -80, 80, 1, "durationOffsetX", rowData, refresh, nil, {
        description = "Horizontal pixel offset for the duration text from its anchor.",
    })
    local durationYOffsetSlider = gui:CreateFormSlider(card.frame, nil, -80, 80, 1, "durationOffsetY", rowData, refresh, nil, {
        description = "Vertical pixel offset for the duration text from its anchor.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Duration X-Offset", durationXOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Duration Y-Offset", durationYOffsetSlider)
    )

    local durationTextColorPicker = gui:CreateFormColorPicker(card.frame, nil, "durationTextColor", rowData, refresh, nil, {
        description = "Color used for the duration countdown text.",
    })
    local stackTextSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 50, 1, "stackSize", rowData, refresh, nil, {
        description = "Font size for the stack count text on icons in this row.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Duration Text Color", durationTextColorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Stack Text Size", stackTextSizeSlider)
    )

    local stackAnchorDropdown = gui:CreateFormDropdown(card.frame, nil, TEXT_ANCHOR_OPTIONS, "stackAnchor", rowData, refresh, {
        description = "Which corner of the icon the stack count is anchored to.",
    })
    local stackXOffsetSlider = gui:CreateFormSlider(card.frame, nil, -80, 80, 1, "stackOffsetX", rowData, refresh, nil, {
        description = "Horizontal pixel offset for the stack count from its anchor.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Anchor Stack To", stackAnchorDropdown),
        optionsAPI.BuildSettingRow(card.frame, "Stack X-Offset", stackXOffsetSlider)
    )

    local stackYOffsetSlider = gui:CreateFormSlider(card.frame, nil, -80, 80, 1, "stackOffsetY", rowData, refresh, nil, {
        description = "Vertical pixel offset for the stack count from its anchor.",
    })
    local stackTextColorPicker = gui:CreateFormColorPicker(card.frame, nil, "stackTextColor", rowData, refresh, nil, {
        description = "Color used for the stack count text.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Stack Y-Offset", stackYOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Stack Text Color", stackTextColorPicker)
    )

    local iconShapeSlider = gui:CreateFormSlider(card.frame, nil, 1.0, 2.0, 0.01, "aspectRatioCrop", rowData, refresh, nil, {
        description = "Aspect ratio crop for icons: 1.0 is square, higher values flatten icons into wider rectangles.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Icon Shape", iconShapeSlider))

    builder.CloseCard(card)
end

local function AppendLayoutRouteControls(sectionHost, builder, containerKey)
    local CDMC = ns.CDMContainers
    local U = ns.QUI_LayoutMode_Utils
    if not sectionHost or not builder
        or type(containerKey) ~= "string" or containerKey == ""
        or not CDMC or type(CDMC.ResolveLayoutElementKey) ~= "function"
        or not U or type(U.BuildPositionCollapsible) ~= "function"
        or type(U.BuildOpenFullSettingsLink) ~= "function"
        or type(U.StandardRelayout) ~= "function" then
        return
    end

    local elementKey = CDMC.ResolveLayoutElementKey(containerKey)
    if type(elementKey) ~= "string" or elementKey == "" then
        return
    end

    local topOffset = builder.Height(0)
    local routeHost = CreateFrame("Frame", nil, sectionHost)
    routeHost:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -topOffset)
    routeHost:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -topOffset)

    local sections = {}
    local function relayout()
        U.StandardRelayout(routeHost, sections)
    end

    U.BuildPositionCollapsible(routeHost, elementKey, nil, sections, relayout)
    U.BuildOpenFullSettingsLink(routeHost, elementKey, sections, relayout)
    relayout()

    local routeHeight = routeHost.GetHeight and routeHost:GetHeight() or 0
    if type(routeHeight) == "number" and routeHeight > 0 then
        routeHost:SetHeight(routeHeight)
        builder.Spacer(routeHeight)
    end
end

local function ResolveEffectsContext(containerKey)
    local profile = GetProfileDB()
    if not profile or type(containerKey) ~= "string" or containerKey == "" then
        return nil
    end

    if type(profile.cooldownSwipe) ~= "table" then
        profile.cooldownSwipe = {}
    end
    if type(profile.cooldownEffects) ~= "table" then
        profile.cooldownEffects = {}
    end
    if type(profile.customGlow) ~= "table" then
        profile.customGlow = {}
    end
    if type(profile.cooldownHighlighter) ~= "table" then
        profile.cooldownHighlighter = {}
    end

    local glowPrefix
    if containerKey == "essential" then
        glowPrefix = "essential"
    elseif containerKey == "utility" then
        glowPrefix = "utility"
    else
        glowPrefix = containerKey
    end

    local hideKey, hideLabel
    if containerKey == "essential" then
        hideKey = "hideEssential"
        hideLabel = "Hide on Essential Cooldowns"
    elseif containerKey == "utility" then
        hideKey = "hideUtility"
        hideLabel = "Hide on Utility Cooldowns"
    else
        hideKey = "hide_" .. containerKey
        hideLabel = "Hide Cooldown Effects"
    end

    local glowDB = profile.customGlow
    local pandemicKey = glowPrefix .. "PandemicEnabled"
    if glowDB[pandemicKey] == nil then
        glowDB[pandemicKey] = true
    end

    return {
        profile = profile,
        swipeDB = profile.cooldownSwipe,
        effectsDB = profile.cooldownEffects,
        glowDB = glowDB,
        highlighterDB = profile.cooldownHighlighter,
        glowPrefix = glowPrefix,
        pandemicKey = pandemicKey,
        hideKey = hideKey,
        hideLabel = hideLabel,
    }
end

local function RenderEntriesSection(sectionHost, ctx)
    local containerKey = ResolveContainerKey(ctx)
    SetSearchContext("entries")

    if not containerKey then
        return nil
    end
    if not _G.QUI_EmbedCDMComposer then
        return RenderUnavailableLabel(sectionHost, "CDM Composer unavailable (module not loaded).")
    end

    if FullSurface and type(FullSurface.RenderEmbeddedEditor) == "function" then
        local height = FullSurface.RenderEmbeddedEditor(sectionHost, {
            host = sectionHost,
            minHeight = 160,
            beforeRender = function(host)
                host._hideComposerNav = true
            end,
            render = function(host)
                _G.QUI_EmbedCDMComposer(host, containerKey)
            end,
        })
        if type(height) == "number" and height > 0 then
            return math.max(height, 160)
        end
    end

    sectionHost._hideComposerNav = true
    _G.QUI_EmbedCDMComposer(sectionHost, containerKey)

    local height = sectionHost.GetHeight and sectionHost:GetHeight() or 0
    if type(height) ~= "number" or height <= 0 then
        height = 160
    end
    return math.max(height, 160)
end

local function RenderLayoutSection(sectionHost, ctx)
    local containerKey = ResolveContainerKey(ctx)
    if not containerKey then
        return nil
    end

    local containerType = ResolveContainerType(containerKey)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local tracker = ResolveTrackerDB(containerKey)
    if not gui or not optionsAPI or not tracker then
        return RenderUnavailableLabel(sectionHost, "Layout unavailable.")
    end

    if containerType == "aura" or containerType == "auraBar" then
        local builder = CreateSectionBuilder(sectionHost, ctx, "layout")
        local refresh = function()
            RefreshContainer(containerKey)
        end

        local enableCard = builder.Card()
        local enableDescription
        if containerType == "aura" then
            enableDescription = "Enable this buff icon container. Disabling hides the entire container and all its icons."
            tracker.iconDisplayMode = tracker.iconDisplayMode or "active"
            tracker.growthDirection = tracker.growthDirection or "CENTERED_HORIZONTAL"
        else
            enableDescription = "Enable this tracked bar container. Disabling hides every bar it would otherwise render."
            tracker.iconDisplayMode = tracker.iconDisplayMode or "active"
            tracker.inactiveMode = tracker.inactiveMode or "hide"
            tracker.orientation = tracker.orientation or "horizontal"
            tracker.fillDirection = tracker.fillDirection or "up"
            tracker.iconPosition = tracker.iconPosition or "top"
        end

        local enableCheckbox = gui:CreateFormCheckbox(enableCard.frame, nil, "enabled", tracker, refresh, {
            description = enableDescription,
        })
        enableCard.AddRow(optionsAPI.BuildSettingRow(enableCard.frame, "Enable", enableCheckbox))
        builder.CloseCard(enableCard)

        if containerType == "aura" then
            builder.Header("General")
            local generalCard = builder.Card()
            local displayModeDropdown = gui:CreateFormDropdown(generalCard.frame, nil, DISPLAY_MODE_OPTIONS, "iconDisplayMode", tracker, refresh, {
                description = "When icons appear: always, only when the buff is active, or only while in combat.",
            })
            generalCard.AddRow(optionsAPI.BuildSettingRow(generalCard.frame, "Display Mode", displayModeDropdown))
            builder.CloseCard(generalCard)

            builder.Spacer(6)
            builder.Header("Appearance")
            local appearanceCard = builder.Card()
            local sizeSlider = gui:CreateFormSlider(appearanceCard.frame, nil, 20, 80, 1, "iconSize", tracker, refresh, nil, {
                description = "Square size of each buff icon in pixels.",
            })
            local borderSlider = gui:CreateFormSlider(appearanceCard.frame, nil, 0, 8, 1, "borderSize", tracker, refresh, nil, {
                description = "Border thickness in pixels around each icon. Set to 0 to hide the border.",
            })
            appearanceCard.AddRow(
                optionsAPI.BuildSettingRow(appearanceCard.frame, "Icon Size", sizeSlider),
                optionsAPI.BuildSettingRow(appearanceCard.frame, "Border Size", borderSlider)
            )

            local zoomSlider = gui:CreateFormSlider(appearanceCard.frame, nil, 0, 0.2, 0.01, "zoom", tracker, refresh, nil, {
                description = "Crop the edges of each icon to hide Blizzard's default border. Higher values crop more.",
            })
            local paddingSlider = gui:CreateFormSlider(appearanceCard.frame, nil, -20, 20, 1, "padding", tracker, refresh, nil, {
                description = "Pixel gap between adjacent icons. Negative values overlap icons.",
            })
            appearanceCard.AddRow(
                optionsAPI.BuildSettingRow(appearanceCard.frame, "Icon Zoom", zoomSlider),
                optionsAPI.BuildSettingRow(appearanceCard.frame, "Icon Padding", paddingSlider)
            )

            local opacitySlider = gui:CreateFormSlider(appearanceCard.frame, nil, 0, 1.0, 0.05, "opacity", tracker, refresh, nil, {
                description = "Opacity of the icons. 0 is fully transparent, 1 is fully opaque.",
            })
            local aspectRatioSlider = gui:CreateFormSlider(appearanceCard.frame, nil, 1.0, 2.0, 0.01, "aspectRatioCrop", tracker, refresh, nil, {
                description = "Aspect ratio crop: 1.0 is square, higher values flatten icons into wider rectangles.",
            })
            appearanceCard.AddRow(
                optionsAPI.BuildSettingRow(appearanceCard.frame, "Opacity", opacitySlider),
                optionsAPI.BuildSettingRow(appearanceCard.frame, "Icon Shape", aspectRatioSlider)
            )
            builder.CloseCard(appearanceCard)

            builder.Spacer(6)
            builder.Header("Growth & Text")
            local textCard = builder.Card()
            local growthDropdown = gui:CreateFormDropdown(textCard.frame, nil, AURA_GROWTH_DIRECTION_OPTIONS, "growthDirection", tracker, refresh, {
                description = "How the icon block grows from its anchor: centered horizontal, stacked up, or stacked down.",
            })
            local durationSizeSlider = gui:CreateFormSlider(textCard.frame, nil, 8, 50, 1, "durationSize", tracker, refresh, nil, {
                description = "Font size for the duration countdown text on buff icons.",
            })
            textCard.AddRow(
                optionsAPI.BuildSettingRow(textCard.frame, "Growth Direction", growthDropdown),
                optionsAPI.BuildSettingRow(textCard.frame, "Duration Size", durationSizeSlider)
            )

            local durationAnchorDropdown = gui:CreateFormDropdown(textCard.frame, nil, TEXT_ANCHOR_OPTIONS, "durationAnchor", tracker, refresh, {
                description = "Which corner of the icon the duration text is anchored to.",
            })
            local durationXSlider = gui:CreateFormSlider(textCard.frame, nil, -20, 20, 1, "durationOffsetX", tracker, refresh, nil, {
                description = "Horizontal pixel offset for the duration text from its anchor.",
            })
            textCard.AddRow(
                optionsAPI.BuildSettingRow(textCard.frame, "Duration Anchor", durationAnchorDropdown),
                optionsAPI.BuildSettingRow(textCard.frame, "Duration X Offset", durationXSlider)
            )

            local durationYSlider = gui:CreateFormSlider(textCard.frame, nil, -20, 20, 1, "durationOffsetY", tracker, refresh, nil, {
                description = "Vertical pixel offset for the duration text from its anchor.",
            })
            local stackSizeSlider = gui:CreateFormSlider(textCard.frame, nil, 8, 50, 1, "stackSize", tracker, refresh, nil, {
                description = "Font size for the stack count text on buff icons.",
            })
            textCard.AddRow(
                optionsAPI.BuildSettingRow(textCard.frame, "Duration Y Offset", durationYSlider),
                optionsAPI.BuildSettingRow(textCard.frame, "Stack Size", stackSizeSlider)
            )

            local stackAnchorDropdown = gui:CreateFormDropdown(textCard.frame, nil, TEXT_ANCHOR_OPTIONS, "stackAnchor", tracker, refresh, {
                description = "Which corner of the icon the stack count is anchored to.",
            })
            local stackXSlider = gui:CreateFormSlider(textCard.frame, nil, -20, 20, 1, "stackOffsetX", tracker, refresh, nil, {
                description = "Horizontal pixel offset for the stack count from its anchor.",
            })
            textCard.AddRow(
                optionsAPI.BuildSettingRow(textCard.frame, "Stack Anchor", stackAnchorDropdown),
                optionsAPI.BuildSettingRow(textCard.frame, "Stack X Offset", stackXSlider)
            )

            local stackYSlider = gui:CreateFormSlider(textCard.frame, nil, -20, 20, 1, "stackOffsetY", tracker, refresh, nil, {
                description = "Vertical pixel offset for the stack count from its anchor.",
            })
            textCard.AddRow(optionsAPI.BuildSettingRow(textCard.frame, "Stack Y Offset", stackYSlider))
            builder.CloseCard(textCard)
        else
            builder.Header("General")
            local generalCard = builder.Card()
            local displayModeDropdown = gui:CreateFormDropdown(generalCard.frame, nil, DISPLAY_MODE_OPTIONS, "iconDisplayMode", tracker, refresh, {
                description = "When bars appear: always, only while the tracked buff/debuff is active, or only while in combat.",
            })
            local hideIconCheckbox = gui:CreateFormCheckbox(generalCard.frame, nil, "hideIcon", tracker, refresh, {
                description = "Hide the spell icon next to each bar, showing just the bar and text.",
            })
            generalCard.AddRow(
                optionsAPI.BuildSettingRow(generalCard.frame, "Display Mode", displayModeDropdown),
                optionsAPI.BuildSettingRow(generalCard.frame, "Hide Icon", hideIconCheckbox)
            )
            local hideTextCheckbox = gui:CreateFormCheckbox(generalCard.frame, nil, "hideText", tracker, refresh, {
                description = "Hide the duration and spell-name text on every bar in this container.",
            })
            generalCard.AddRow(optionsAPI.BuildSettingRow(generalCard.frame, "Hide Text", hideTextCheckbox))
            builder.CloseCard(generalCard)

            builder.Spacer(6)
            builder.Header("Inactive Behavior")
            local inactiveCard = builder.Card()
            local inactiveAlphaRow, desaturateRow, reserveSlotRow
            local function updateInactiveRowAlpha()
                local mode = tracker.inactiveMode or "hide"
                if inactiveAlphaRow then
                    inactiveAlphaRow:SetAlpha(mode == "fade" and 1.0 or 0.4)
                end
                if desaturateRow then
                    desaturateRow:SetAlpha(mode ~= "always" and 1.0 or 0.4)
                end
                if reserveSlotRow then
                    reserveSlotRow:SetAlpha(mode == "hide" and 1.0 or 0.4)
                end
            end

            local inactiveModeDropdown = gui:CreateFormDropdown(inactiveCard.frame, nil, INACTIVE_MODE_OPTIONS, "inactiveMode", tracker, function()
                refresh()
                updateInactiveRowAlpha()
            end, {
                description = "What happens to bars when the tracked buff is not active: always show, fade to the alpha below, or hide entirely.",
            })
            local inactiveAlphaSlider = gui:CreateFormSlider(inactiveCard.frame, nil, 0, 1, 0.05, "inactiveAlpha", tracker, refresh, nil, {
                description = "Opacity applied to bars when Inactive Buffs mode is Fade. Ignored in Always Show / Hide.",
            })
            inactiveAlphaRow = optionsAPI.BuildSettingRow(inactiveCard.frame, "Inactive Alpha", inactiveAlphaSlider)
            inactiveCard.AddRow(
                optionsAPI.BuildSettingRow(inactiveCard.frame, "Inactive Buffs", inactiveModeDropdown),
                inactiveAlphaRow
            )

            local desaturateCheckbox = gui:CreateFormCheckbox(inactiveCard.frame, nil, "desaturateInactive", tracker, refresh, {
                description = "Desaturate the icon and bar fill when the tracked buff is inactive. Applies in Always Show and Fade modes.",
            })
            local reserveSlotCheckbox = gui:CreateFormCheckbox(inactiveCard.frame, nil, "reserveSlotWhenInactive", tracker, refresh, {
                description = "Keep the bar's slot reserved (blank) when hidden, so active bars don't shift position. Only applies in Hide mode.",
            })
            desaturateRow = optionsAPI.BuildSettingRow(inactiveCard.frame, "Desaturate Inactive", desaturateCheckbox)
            reserveSlotRow = optionsAPI.BuildSettingRow(inactiveCard.frame, "Reserve Slot When Inactive", reserveSlotCheckbox)
            inactiveCard.AddRow(desaturateRow, reserveSlotRow)
            builder.CloseCard(inactiveCard)
            updateInactiveRowAlpha()

            builder.Spacer(6)
            builder.Header("Dimensions & Appearance")
            local dimensionsCard = builder.Card()
            local heightSlider = gui:CreateFormSlider(dimensionsCard.frame, nil, 2, 48, 1, "barHeight", tracker, refresh, nil, {
                description = "Height of each bar in pixels.",
            })
            local widthSlider = gui:CreateFormSlider(dimensionsCard.frame, nil, 100, 400, 1, "barWidth", tracker, refresh, nil, {
                description = "Width of each bar in pixels. Ignored when Auto Width From Anchor is on.",
            })
            dimensionsCard.AddRow(
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Bar Height", heightSlider),
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Bar Width", widthSlider)
            )

            local borderSlider = gui:CreateFormSlider(dimensionsCard.frame, nil, 0, 4, 1, "borderSize", tracker, refresh, nil, {
                description = "Border thickness in pixels around each bar. Set to 0 to hide.",
            })
            local spacingSlider = gui:CreateFormSlider(dimensionsCard.frame, nil, 0, 20, 1, "spacing", tracker, refresh, nil, {
                description = "Pixel gap between adjacent bars in this container.",
            })
            dimensionsCard.AddRow(
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Border Size", borderSlider),
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Bar Spacing", spacingSlider)
            )

            local textSizeSlider = gui:CreateFormSlider(dimensionsCard.frame, nil, 8, 24, 1, "textSize", tracker, refresh, nil, {
                description = "Font size used for the duration and spell-name text on each bar.",
            })
            local textureOptions = BuildStatusbarTextureOptions()
            if #textureOptions > 0 then
                local textureDropdown = gui:CreateFormDropdown(dimensionsCard.frame, nil, textureOptions, "texture", tracker, refresh, {
                    description = "Statusbar texture used for the bar fill.",
                })
                dimensionsCard.AddRow(
                    optionsAPI.BuildSettingRow(dimensionsCard.frame, "Text Size", textSizeSlider),
                    optionsAPI.BuildSettingRow(dimensionsCard.frame, "Bar Texture", textureDropdown)
                )
            else
                dimensionsCard.AddRow(optionsAPI.BuildSettingRow(dimensionsCard.frame, "Text Size", textSizeSlider))
            end

            local autoWidthCheckbox = gui:CreateFormCheckbox(dimensionsCard.frame, nil, "autoWidth", tracker, refresh, {
                description = "Stretch bars to match the width of the frame they anchor to (e.g. the player frame).",
            })
            local autoWidthOffsetSlider = gui:CreateFormSlider(dimensionsCard.frame, nil, -20, 20, 1, "autoWidthOffset", tracker, refresh, nil, {
                description = "Pixel adjustment applied to the auto-matched width. Useful for aligning with a frame's inner or outer edge.",
            })
            dimensionsCard.AddRow(
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Auto Width From Anchor", autoWidthCheckbox),
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Auto Width Adjust", autoWidthOffsetSlider)
            )

            local stackDirectionDropdown = gui:CreateFormDropdown(dimensionsCard.frame, nil, STACK_DIRECTION_OPTIONS, "growUp", tracker, refresh, {
                description = "Direction new bars are added from the anchor: stacking upward/rightward or downward/leftward.",
            })
            local stackOffsetSlider = gui:CreateFormSlider(dimensionsCard.frame, nil, -20, 20, 1, "stackOffsetX", tracker, refresh, nil, {
                description = "Horizontal pixel offset between stacked bars.",
            })
            dimensionsCard.AddRow(
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Stack Direction", stackDirectionDropdown),
                optionsAPI.BuildSettingRow(dimensionsCard.frame, "Stack X Offset", stackOffsetSlider)
            )
            builder.CloseCard(dimensionsCard)

            builder.Spacer(6)
            builder.Header("Colors")
            local colorCard = builder.Card()
            local classColorCheckbox = gui:CreateFormCheckbox(colorCard.frame, nil, "useClassColor", tracker, refresh, {
                description = "Color each bar by the player's class instead of the custom Bar Color below.",
            })
            local barColorPicker = gui:CreateFormColorPicker(colorCard.frame, nil, "barColor", tracker, refresh, nil, {
                description = "Fallback bar color used when Use Class Color is off.",
            })
            colorCard.AddRow(
                optionsAPI.BuildSettingRow(colorCard.frame, "Use Class Color", classColorCheckbox),
                optionsAPI.BuildSettingRow(colorCard.frame, "Bar Color (Fallback)", barColorPicker)
            )

            local barOpacitySlider = gui:CreateFormSlider(colorCard.frame, nil, 0, 1, 0.05, "barOpacity", tracker, refresh, nil, {
                description = "Opacity of the bar fill. 0 is fully transparent, 1 is fully opaque.",
            })
            local backgroundColorPicker = gui:CreateFormColorPicker(colorCard.frame, nil, "bgColor", tracker, refresh, nil, {
                description = "Backdrop color drawn behind the bar fill.",
            })
            colorCard.AddRow(
                optionsAPI.BuildSettingRow(colorCard.frame, "Bar Opacity", barOpacitySlider),
                optionsAPI.BuildSettingRow(colorCard.frame, "Background Color", backgroundColorPicker)
            )

            local backgroundOpacitySlider = gui:CreateFormSlider(colorCard.frame, nil, 0, 1, 0.1, "bgOpacity", tracker, refresh, nil, {
                description = "Opacity of the backdrop fill behind the bar.",
            })
            colorCard.AddRow(optionsAPI.BuildSettingRow(colorCard.frame, "Background Opacity", backgroundOpacitySlider))
            builder.CloseCard(colorCard)

            builder.Spacer(6)
            builder.Header("Orientation")
            local orientationCard = builder.Card()
            local fillDirectionRow, iconPositionRow, showTextRow
            local function updateOrientationRowAlpha()
                local alpha = (tracker.orientation == "vertical") and 1.0 or 0.4
                if fillDirectionRow then
                    fillDirectionRow:SetAlpha(alpha)
                end
                if iconPositionRow then
                    iconPositionRow:SetAlpha(alpha)
                end
                if showTextRow then
                    showTextRow:SetAlpha(alpha)
                end
            end

            local orientationDropdown = gui:CreateFormDropdown(orientationCard.frame, nil, BAR_ORIENTATION_OPTIONS, "orientation", tracker, function()
                refresh()
                updateOrientationRowAlpha()
            end, {
                description = "Render bars horizontally (width fills left to right) or vertically (height fills upward). Vertical mode enables the controls below.",
            })
            local fillDirectionDropdown = gui:CreateFormDropdown(orientationCard.frame, nil, BAR_FILL_DIRECTION_OPTIONS, "fillDirection", tracker, refresh, {
                description = "For vertical bars, whether remaining-duration fills upward (empty to full from the bottom) or downward (full to empty from the top).",
            })
            fillDirectionRow = optionsAPI.BuildSettingRow(orientationCard.frame, "Fill Direction", fillDirectionDropdown)
            orientationCard.AddRow(
                optionsAPI.BuildSettingRow(orientationCard.frame, "Bar Orientation", orientationDropdown),
                fillDirectionRow
            )

            local iconPositionDropdown = gui:CreateFormDropdown(orientationCard.frame, nil, BAR_ICON_POSITION_OPTIONS, "iconPosition", tracker, refresh, {
                description = "For vertical bars, whether the spell icon sits at the top or the bottom of each bar.",
            })
            local showTextCheckbox = gui:CreateFormCheckbox(orientationCard.frame, nil, "showTextOnVertical", tracker, refresh, {
                description = "Render the duration and spell-name text on vertical bars. Turn off for icon-only vertical bars.",
            })
            iconPositionRow = optionsAPI.BuildSettingRow(orientationCard.frame, "Icon Position", iconPositionDropdown)
            showTextRow = optionsAPI.BuildSettingRow(orientationCard.frame, "Show Text (Vertical)", showTextCheckbox)
            orientationCard.AddRow(iconPositionRow, showTextRow)
            builder.CloseCard(orientationCard)
            updateOrientationRowAlpha()
        end

        return builder.Height()
    end

    if (containerType == "cooldown" or containerType == "customBar") and gui and optionsAPI and tracker then
        local builder = CreateSectionBuilder(sectionHost, ctx, "layout")
        if not builder then
            return nil
        end

        local refresh = function()
            RefreshContainer(containerKey)
        end

        local enableCard = builder.Card()
        local enableCheckbox = gui:CreateFormCheckbox(enableCard.frame, nil, "enabled", tracker, refresh, {
            description = "Enable this cooldown container. Disabling hides all rows and icons it would otherwise render.",
        })
        enableCard.AddRow(optionsAPI.BuildSettingRow(enableCard.frame, "Enable", enableCheckbox))
        builder.CloseCard(enableCard)

        builder.Spacer(6)
        AppendTrackerGeneralSection(builder, gui, optionsAPI, tracker, containerKey, refresh)

        local rowMax = (tracker.containerType == "customBar") and 1 or 3
        for rowNum = 1, rowMax do
            local rowData = tracker["row" .. rowNum]
            if rowData then
                builder.Spacer(6)
                AppendTrackerRowSection(builder, gui, optionsAPI, rowNum, rowData, refresh)
            end
        end

        return builder.Height()
    end

    return RenderUnavailableLabel(sectionHost, "Layout unavailable.")
end

local function RenderFiltersSection(sectionHost, ctx)
    local containerKey = ResolveContainerKey(ctx)
    local containerType = ResolveContainerType(containerKey)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local tracker = ResolveTrackerDB(containerKey)
    if not containerKey then
        return nil
    end

    if not tracker or tracker.builtIn then
        return RenderUnavailableLabel(sectionHost, "Filters unavailable.")
    end

    if containerType == "aura" then
        return RenderInfoMessage(
            sectionHost,
            ctx,
            "filters",
            "Buff icon containers currently use their Layout and Effects settings instead of separate Filters controls."
        )
    end

    if containerType == "auraBar" then
        return RenderInfoMessage(
            sectionHost,
            ctx,
            "filters",
            "Buff bar containers currently use their Layout display and inactive-behavior settings instead of separate Filters controls."
        )
    end

    if not gui or not optionsAPI then
        return RenderUnavailableLabel(sectionHost, "Filters unavailable.")
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, "filters")
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshContainer(containerKey)
    end

    builder.Header("Visibility Filters")
    local card = builder.Card()

    local hideGCDCheckbox = gui:CreateFormCheckbox(card.frame, nil, "hideGCD", tracker, refresh, {
        description = "Hide icons for spells whose only remaining cooldown is the global cooldown.",
    })
    local hideNonUsableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "hideNonUsable", tracker, refresh, {
        description = "Hide icons for spells you cannot cast right now (wrong form, out of range, silenced, etc.).",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Hide GCD", hideGCDCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Hide Non-Usable", hideNonUsableCheckbox)
    )

    local showOnlyOnCooldownCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showOnlyOnCooldown", tracker, refresh, {
        description = "Only show icons while they are on cooldown. Off-cooldown spells are hidden entirely.",
    })
    local showOnlyOffCooldownCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showOnlyWhenOffCooldown", tracker, refresh, {
        description = "Only show icons when they are off cooldown and ready to cast.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Only On Cooldown", showOnlyOnCooldownCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Show Only Off Cooldown", showOnlyOffCooldownCheckbox)
    )

    local showOnlyWhenActiveCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showOnlyWhenActive", tracker, refresh, {
        description = "Only show icons while the linked buff/debuff is currently active on the player or their target.",
    })
    local showOnlyInCombatCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showOnlyInCombat", tracker, refresh, {
        description = "Only show icons while you are in combat.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Only When Active", showOnlyWhenActiveCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Show Only In Combat", showOnlyInCombatCheckbox)
    )

    local dynamicLayoutCheckbox = gui:CreateFormCheckbox(card.frame, nil, "dynamicLayout", tracker, refresh, {
        description = "Collapse the row when filters hide icons so remaining icons pack together. Turn off to keep slots reserved in their original positions.",
    })
    local showItemChargesCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showItemCharges", tracker, refresh, {
        description = "Show the remaining-charges counter on tracked items and spells with charges.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Dynamic Layout (Collapse Hidden)", dynamicLayoutCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Show Item Charges", showItemChargesCheckbox)
    )

    local showRechargeSwipeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showRechargeSwipe", tracker, refresh, {
        description = "Show the recharge swipe animation on spells with charges while at least one charge is regenerating.",
    })
    local noDesaturateCheckbox = gui:CreateFormCheckbox(card.frame, nil, "noDesaturateWithCharges", tracker, refresh, {
        description = "Keep charge-based spells in full color even while regenerating the next charge, ignoring the container's desaturate-on-cooldown rule.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Recharge Swipe", showRechargeSwipeCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "No Desaturate With Charges", noDesaturateCheckbox)
    )

    local qualityCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showProfessionQuality", tracker, refresh, {
        description = "Show the profession-quality indicator on crafted item icons in this container.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Show Crafted Item Quality", qualityCheckbox))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderPerSpecSection(sectionHost, ctx)
    local containerKey = ResolveContainerKey(ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local tracker = ResolveTrackerDB(containerKey)
    if not containerKey then
        return nil
    end

    if not tracker or tracker.builtIn or not gui or not optionsAPI then
        return RenderUnavailableLabel(sectionHost, "Per-Spec entries unavailable.")
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, "perspec")
    if not builder then
        return nil
    end

    builder.Header("Per-Spec Entries")
    local card = builder.Card()
    local specSpecificCheckbox = gui:CreateFormCheckbox(card.frame, nil, "specSpecific", tracker, function()
        if ns.CDMSpellData and ns.CDMSpellData.OnSpecSpecificToggled then
            ns.CDMSpellData:OnSpecSpecificToggled(containerKey)
        end
        RefreshContainer(containerKey)
    end, {
        description = "Store separate entry lists per specialization, so each spec shows a different set of tracked spells. The current list is swapped in on spec change.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Spec-Specific Entries", specSpecificCheckbox))
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderEffectsSection(sectionHost, ctx)
    local containerKey = ResolveContainerKey(ctx)
    local containerType = ResolveContainerType(containerKey)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    if not containerKey then
        return nil
    end

    if containerType == "auraBar" then
        return RenderInfoMessage(
            sectionHost,
            ctx,
            "effects",
            "Buff bar containers do not currently expose separate Effects controls."
        )
    end

    if containerType == "aura" then
        local profile = GetProfileDB()
        if not gui or not optionsAPI or not profile then
            return RenderUnavailableLabel(sectionHost, "Effects unavailable.")
        end
        if type(profile.customGlow) ~= "table" then
            profile.customGlow = {}
        end
        if profile.customGlow.buffPandemicEnabled == nil then
            profile.customGlow.buffPandemicEnabled = true
        end

        local builder = CreateSectionBuilder(sectionHost, ctx, "effects")
        if not builder then
            return nil
        end

        builder.Header("Effects")
        local card = builder.Card()
        local pandemicCheckbox = gui:CreateFormCheckbox(card.frame, nil, "buffPandemicEnabled", profile.customGlow, RefreshGlows, {
            description = "Emit a refresh glow during the pandemic window (the last ~30% of the buff's duration) so you know when refreshing is optimal.",
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Mirror Pandemic Refresh Glow", pandemicCheckbox))
        builder.CloseCard(card)
        return builder.Height()
    end

    local effectsCtx = ResolveEffectsContext(containerKey)

    if not gui or not optionsAPI or not effectsCtx then
        return RenderUnavailableLabel(sectionHost, "Effects unavailable.")
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, "effects")
    if not builder then
        return nil
    end

    builder.Header("Cooldown Swipe")
    local swipeCard = builder.Card()
    local swipeRadialCheckbox = gui:CreateFormCheckbox(swipeCard.frame, nil, "showCooldownSwipe", effectsCtx.swipeDB, RefreshSwipe, {
        description = "Show the clockwise cooldown swipe animation on icons in this container.",
    })
    local gcdSwipeCheckbox = gui:CreateFormCheckbox(swipeCard.frame, nil, "showGCDSwipe", effectsCtx.swipeDB, RefreshSwipe, {
        description = "Also play the swipe during global cooldowns. Turn off to reserve the animation for real cooldowns only.",
    })
    swipeCard.AddRow(
        optionsAPI.BuildSettingRow(swipeCard.frame, "Radial Darkening", swipeRadialCheckbox),
        optionsAPI.BuildSettingRow(swipeCard.frame, "GCD Swipe", gcdSwipeCheckbox)
    )
    local buffSwipeCheckbox = gui:CreateFormCheckbox(swipeCard.frame, nil, "showBuffSwipe", effectsCtx.swipeDB, RefreshSwipe, {
        description = "Play a swipe animation on buff/debuff icons to represent remaining duration.",
    })
    local rechargeEdgeCheckbox = gui:CreateFormCheckbox(swipeCard.frame, nil, "showRechargeEdge", effectsCtx.swipeDB, RefreshSwipe, {
        description = "Show a bright edge on the active recharge slice for spells with charges.",
    })
    swipeCard.AddRow(
        optionsAPI.BuildSettingRow(swipeCard.frame, "Buff/Debuff Swipe", buffSwipeCheckbox),
        optionsAPI.BuildSettingRow(swipeCard.frame, "Recharge Edge", rechargeEdgeCheckbox)
    )
    builder.CloseCard(swipeCard)
    builder.Spacer(10)

    builder.Header("Overlay Color")
    local overlayCard = builder.Card()
    local overlayColorPicker
    local swipeColorPicker
    local function UpdateSwipeColorStates()
        if overlayColorPicker then
            overlayColorPicker:SetEnabled((effectsCtx.swipeDB.overlayColorMode or "default") == "custom")
        end
        if swipeColorPicker then
            swipeColorPicker:SetEnabled((effectsCtx.swipeDB.swipeColorMode or "default") == "custom")
        end
    end
    local overlayModeDropdown = gui:CreateFormDropdown(overlayCard.frame, nil, COLOR_MODE_OPTIONS, "overlayColorMode", effectsCtx.swipeDB, function()
        RefreshSwipe()
        UpdateSwipeColorStates()
    end, {
        description = "How the buff/debuff overlay is colored: Blizzard default, class color, UI accent, or the custom swatch.",
    })
    overlayColorPicker = gui:CreateFormColorPicker(overlayCard.frame, nil, "overlayColor", effectsCtx.swipeDB, RefreshSwipe, nil, {
        description = "Custom color used for the buff/debuff overlay when Buff Overlay Color is set to Custom.",
    })
    overlayCard.AddRow(
        optionsAPI.BuildSettingRow(overlayCard.frame, "Buff Overlay Color", overlayModeDropdown),
        optionsAPI.BuildSettingRow(overlayCard.frame, "Overlay Custom Color", overlayColorPicker)
    )
    local swipeModeDropdown = gui:CreateFormDropdown(overlayCard.frame, nil, COLOR_MODE_OPTIONS, "swipeColorMode", effectsCtx.swipeDB, function()
        RefreshSwipe()
        UpdateSwipeColorStates()
    end, {
        description = "How the cooldown swipe is colored: Blizzard default, class color, UI accent, or the custom swatch.",
    })
    swipeColorPicker = gui:CreateFormColorPicker(overlayCard.frame, nil, "swipeColor", effectsCtx.swipeDB, RefreshSwipe, nil, {
        description = "Custom color used for the cooldown swipe when Cooldown Swipe Color is set to Custom.",
    })
    overlayCard.AddRow(
        optionsAPI.BuildSettingRow(overlayCard.frame, "Cooldown Swipe Color", swipeModeDropdown),
        optionsAPI.BuildSettingRow(overlayCard.frame, "Swipe Custom Color", swipeColorPicker)
    )
    UpdateSwipeColorStates()
    builder.CloseCard(overlayCard)
    builder.Spacer(10)

    builder.Header("Hide Cooldown Effects")
    local hideCard = builder.Card()
    local hideCheckbox = gui:CreateFormCheckbox(hideCard.frame, nil, effectsCtx.hideKey, effectsCtx.effectsDB, RefreshCooldownEffects, {
        description = "Suppress all cooldown effects (swipe, overlay, flash) for this container, even on Blizzard-managed elements driven by the same icons.",
    })
    hideCard.AddRow(optionsAPI.BuildSettingRow(hideCard.frame, effectsCtx.hideLabel, hideCheckbox))
    builder.CloseCard(hideCard)
    builder.Spacer(10)

    builder.Header("Custom Glow")
    local glowCard = builder.Card()
    local glowTypeKey = effectsCtx.glowPrefix .. "GlowType"
    local glowColorKey = effectsCtx.glowPrefix .. "Color"
    local glowEnabledKey = effectsCtx.glowPrefix .. "Enabled"
    local glowLinesKey = effectsCtx.glowPrefix .. "Lines"
    local glowThicknessKey = effectsCtx.glowPrefix .. "Thickness"
    local glowScaleKey = effectsCtx.glowPrefix .. "Scale"
    local glowFrequencyKey = effectsCtx.glowPrefix .. "Frequency"
    local glowXOffsetKey = effectsCtx.glowPrefix .. "XOffset"
    local glowYOffsetKey = effectsCtx.glowPrefix .. "YOffset"
    local glowWidgets = {}
    local function UpdateGlowWidgetStates()
        local glowType = effectsCtx.glowDB[glowTypeKey] or "Pixel Glow"
        local isPixel = glowType == "Pixel Glow"
        local isAutocast = glowType == "Autocast Shine"
        local isButton = glowType == "Button Glow"
        local isTexture = glowType == "Flash" or glowType == "Hammer"
        if glowWidgets.lines then glowWidgets.lines:SetEnabled(isPixel or isAutocast) end
        if glowWidgets.thickness then glowWidgets.thickness:SetEnabled(isPixel) end
        if glowWidgets.scale then glowWidgets.scale:SetEnabled(isAutocast) end
        if glowWidgets.xOffset then glowWidgets.xOffset:SetEnabled(not isButton and not isTexture) end
        if glowWidgets.yOffset then glowWidgets.yOffset:SetEnabled(not isButton and not isTexture) end
    end
    local glowEnableCheckbox = gui:CreateFormCheckbox(glowCard.frame, nil, glowEnabledKey, effectsCtx.glowDB, RefreshGlows, {
        description = "Override the Blizzard proc glow with QUI's custom glow style for icons in this container.",
    })
    local pandemicCheckbox = gui:CreateFormCheckbox(glowCard.frame, nil, effectsCtx.pandemicKey, effectsCtx.glowDB, RefreshGlows, {
        description = "Also emit the glow during the pandemic refresh window (the last ~30% of the active debuff's duration) to signal optimal refresh timing.",
    })
    glowCard.AddRow(
        optionsAPI.BuildSettingRow(glowCard.frame, "Enable Custom Glow", glowEnableCheckbox),
        optionsAPI.BuildSettingRow(glowCard.frame, "Mirror Pandemic Refresh Glow", pandemicCheckbox)
    )
    local glowTypeDropdown = gui:CreateFormDropdown(glowCard.frame, nil, GLOW_TYPE_OPTIONS, glowTypeKey, effectsCtx.glowDB, function()
        RefreshGlows()
        UpdateGlowWidgetStates()
    end, {
        description = "Which LibCustomGlow style to render. Pixel/Autocast support line count and thickness; Button/Flash/Hammer ignore those controls.",
    })
    local glowColorPicker = gui:CreateFormColorPicker(glowCard.frame, nil, glowColorKey, effectsCtx.glowDB, RefreshGlows, nil, {
        description = "Color used for the custom glow effect.",
    })
    glowCard.AddRow(
        optionsAPI.BuildSettingRow(glowCard.frame, "Glow Type", glowTypeDropdown),
        optionsAPI.BuildSettingRow(glowCard.frame, "Glow Color", glowColorPicker)
    )
    glowWidgets.lines = gui:CreateFormSlider(glowCard.frame, nil, 1, 30, 1, glowLinesKey, effectsCtx.glowDB, RefreshGlows, nil, {
        description = "Number of glow particles/lines. Only used by Pixel Glow and Autocast Shine.",
    })
    glowWidgets.thickness = gui:CreateFormSlider(glowCard.frame, nil, 1, 10, 1, glowThicknessKey, effectsCtx.glowDB, RefreshGlows, nil, {
        description = "Thickness of each glow line. Only used by Pixel Glow.",
    })
    glowCard.AddRow(
        optionsAPI.BuildSettingRow(glowCard.frame, "Lines", glowWidgets.lines),
        optionsAPI.BuildSettingRow(glowCard.frame, "Thickness", glowWidgets.thickness)
    )
    glowWidgets.scale = gui:CreateFormSlider(glowCard.frame, nil, 0.5, 3.0, 0.1, glowScaleKey, effectsCtx.glowDB, RefreshGlows, nil, {
        description = "Size multiplier for the Autocast Shine glow.",
    })
    local glowFrequencySlider = gui:CreateFormSlider(glowCard.frame, nil, 0.1, 2.0, 0.05, glowFrequencyKey, effectsCtx.glowDB, RefreshGlows, nil, {
        description = "How fast the glow animates. Higher values rotate/pulse faster.",
    })
    glowCard.AddRow(
        optionsAPI.BuildSettingRow(glowCard.frame, "Shine Scale", glowWidgets.scale),
        optionsAPI.BuildSettingRow(glowCard.frame, "Animation Speed", glowFrequencySlider)
    )
    glowWidgets.xOffset = gui:CreateFormSlider(glowCard.frame, nil, -20, 20, 1, glowXOffsetKey, effectsCtx.glowDB, RefreshGlows, nil, {
        description = "Horizontal pixel offset for the glow effect. Ignored by Button Glow and texture glows.",
    })
    glowWidgets.yOffset = gui:CreateFormSlider(glowCard.frame, nil, -20, 20, 1, glowYOffsetKey, effectsCtx.glowDB, RefreshGlows, nil, {
        description = "Vertical pixel offset for the glow effect. Ignored by Button Glow and texture glows.",
    })
    glowCard.AddRow(
        optionsAPI.BuildSettingRow(glowCard.frame, "X Offset", glowWidgets.xOffset),
        optionsAPI.BuildSettingRow(glowCard.frame, "Y Offset", glowWidgets.yOffset)
    )
    UpdateGlowWidgetStates()
    builder.CloseCard(glowCard)
    builder.Spacer(10)

    builder.Header("Cast Highlighter")
    local highlighterCard = builder.Card()
    local highlighterEnableCheckbox = gui:CreateFormCheckbox(highlighterCard.frame, nil, "enabled", effectsCtx.highlighterDB, RefreshHighlighter, {
        description = "Flash each spell's icon briefly when you cast it, highlighting exactly which tracked ability just went out.",
    })
    local highlighterTypeDropdown = gui:CreateFormDropdown(highlighterCard.frame, nil, GLOW_TYPE_OPTIONS, "glowType", effectsCtx.highlighterDB, RefreshHighlighter, {
        description = "Which LibCustomGlow style to use for the post-cast highlight.",
    })
    highlighterCard.AddRow(
        optionsAPI.BuildSettingRow(highlighterCard.frame, "Enable Cast Highlighter", highlighterEnableCheckbox),
        optionsAPI.BuildSettingRow(highlighterCard.frame, "Glow Type", highlighterTypeDropdown)
    )
    local highlighterColorPicker = gui:CreateFormColorPicker(highlighterCard.frame, nil, "color", effectsCtx.highlighterDB, RefreshHighlighter, nil, {
        description = "Color used for the post-cast highlight effect.",
    })
    local highlighterDurationSlider = gui:CreateFormSlider(highlighterCard.frame, nil, 0.1, 2.0, 0.1, "duration", effectsCtx.highlighterDB, RefreshHighlighter, nil, {
        description = "How long the highlight stays on the icon after each cast, in seconds.",
    })
    highlighterCard.AddRow(
        optionsAPI.BuildSettingRow(highlighterCard.frame, "Highlight Color", highlighterColorPicker),
        optionsAPI.BuildSettingRow(highlighterCard.frame, "Highlight Duration", highlighterDurationSlider)
    )
    builder.CloseCard(highlighterCard)

    return builder.Height()
end

local function RenderKeybindsSection(sectionHost, ctx)
    local containerKey = ResolveContainerKey(ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local viewerDB = ResolveKeybindsDB(containerKey)
    if not containerKey then
        return nil
    end

    if not gui or not optionsAPI or not viewerDB then
        return RenderUnavailableLabel(sectionHost, "Keybind settings unavailable.")
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, "keybinds")
    if not builder then
        return nil
    end

    builder.Header("Keybinds")
    local card = builder.Card()

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showKeybinds", viewerDB, RefreshKeybinds, {
        description = "Show the bound key text on each icon in this container.",
    })
    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, KEYBIND_ANCHOR_OPTIONS, "keybindAnchor", viewerDB, RefreshKeybinds, {
        description = "Which corner of each icon the keybind text is anchored to.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Keybinds", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Keybind Anchor", anchorDropdown)
    )

    local sizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 18, 1, "keybindTextSize", viewerDB, RefreshKeybinds, nil, {
        description = "Font size for the keybind text.",
    })
    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, "keybindTextColor", viewerDB, RefreshKeybinds, nil, {
        description = "Color used for the keybind text.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Text Size", sizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Text Color", colorPicker)
    )

    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "keybindOffsetX", viewerDB, RefreshKeybinds, nil, {
        description = "Horizontal pixel offset for the keybind text from its anchor corner.",
    })
    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "keybindOffsetY", viewerDB, RefreshKeybinds, nil, {
        description = "Vertical pixel offset for the keybind text from its anchor corner.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
    )

    builder.CloseCard(card)
    return builder.Height()
end

local function CreateSingleSectionTabFeature(id, sectionId, minHeight, render)
    return Schema.Feature({
        id = id,
        surfaces = {
            cdmTab = {
                sections = { sectionId },
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = sectionId,
                kind = "custom",
                minHeight = minHeight,
                render = render,
            }),
        },
    })
end

local ENTRIES_TAB_FEATURE = CreateSingleSectionTabFeature("cdmEntriesTab", "entries", 160, RenderEntriesSection)
local LAYOUT_TAB_FEATURE = CreateSingleSectionTabFeature("cdmLayoutTab", "layout", 160, RenderLayoutSection)
local FILTERS_TAB_FEATURE = CreateSingleSectionTabFeature("cdmFiltersTab", "filters", 120, RenderFiltersSection)
local PERSPEC_TAB_FEATURE = CreateSingleSectionTabFeature("cdmPerSpecTab", "perspec", 120, RenderPerSpecSection)
local EFFECTS_TAB_FEATURE = CreateSingleSectionTabFeature("cdmEffectsTab", "effects", 120, RenderEffectsSection)
local KEYBINDS_TAB_FEATURE = CreateSingleSectionTabFeature("cdmKeybindsTab", "keybinds", 120, RenderKeybindsSection)

local function RenderFeatureTab(feature, host, containerKey)
    if not host then
        return false
    end

    local normalizedKey = NormalizeContainerKey(containerKey)
    if type(normalizedKey) ~= "string" or normalizedKey == "" then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(feature, host, {
        surface = "cdmTab",
        width = width,
        containerKey = normalizedKey,
        builtIn = IsBuiltIn(normalizedKey),
    })
end

function CDMSettingsSchema.RenderEntriesTab(host, containerKey)
    return RenderFeatureTab(ENTRIES_TAB_FEATURE, host, containerKey)
end

function CDMSettingsSchema.RenderLayoutTab(host, containerKey)
    return RenderFeatureTab(LAYOUT_TAB_FEATURE, host, containerKey)
end

function CDMSettingsSchema.RenderFiltersTab(host, containerKey)
    return RenderFeatureTab(FILTERS_TAB_FEATURE, host, containerKey)
end

function CDMSettingsSchema.RenderPerSpecTab(host, containerKey)
    return RenderFeatureTab(PERSPEC_TAB_FEATURE, host, containerKey)
end

function CDMSettingsSchema.RenderEffectsTab(host, containerKey)
    return RenderFeatureTab(EFFECTS_TAB_FEATURE, host, containerKey)
end

function CDMSettingsSchema.RenderKeybindsTab(host, containerKey)
    return RenderFeatureTab(KEYBINDS_TAB_FEATURE, host, containerKey)
end
