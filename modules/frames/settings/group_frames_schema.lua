local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Renderer = Settings and Settings.Renderer
local Schema = Settings and Settings.Schema
local FullSurface = Settings and Settings.FullSurface
if not Renderer or type(Renderer.RenderFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function" then
    return
end

local Helpers = ns.Helpers
local SpellList = ns.QUI_GroupFramesSpellListSettings
local AuraIndicatorsEditor = ns.QUI_GroupFramesAuraIndicatorsSettings
local PinnedAurasEditor = ns.QUI_GroupFramesPinnedAurasSettings

local GroupFramesSchema = ns.QUI_GroupFramesSettingsSchema or {}
ns.QUI_GroupFramesSettingsSchema = GroupFramesSchema

local FORM_ROW = 32
local HEADER_GAP = 26
local SECTION_BOTTOM_PAD = 10
local DESCRIPTION_TEXT_COLOR = { 0.5, 0.5, 0.5, 1 }
local LAYOUT_OPTIONS = {
    { value = "VERTICAL", text = "Vertical (columns)" },
    { value = "HORIZONTAL", text = "Horizontal (rows)" },
}
local SORT_OPTIONS = {
    { value = "INDEX", text = "Group Index" },
    { value = "NAME", text = "Name" },
}
local GROUP_BY_OPTIONS = {
    { value = "GROUP", text = "Group Number" },
    { value = "ROLE", text = "Role" },
    { value = "CLASS", text = "Class" },
    { value = "NONE", text = "None (Flat List)" },
}
local ANCHOR_SIDE_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
}
local PET_ANCHOR_OPTIONS = {
    { value = "BOTTOM", text = "Below Group" },
    { value = "RIGHT", text = "Right of Group" },
    { value = "LEFT", text = "Left of Group" },
}
local SPOTLIGHT_FILTER_OPTIONS = {
    { value = "ROLE", text = "By Role" },
    { value = "NAME", text = "By Name" },
}
local HEALTH_DISPLAY_OPTIONS = {
    { value = "percent", text = "Percentage" },
    { value = "absolute", text = "Absolute" },
    { value = "both", text = "Both" },
    { value = "deficit", text = "Deficit" },
}
local HEALTH_FILL_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal (Left to Right)" },
    { value = "VERTICAL", text = "Vertical (Bottom to Top)" },
}
local NINE_POINT_OPTIONS = {
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
local TEXT_JUSTIFY_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
}
local AURA_GROW_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
    { value = "CENTER", text = "Center" },
    { value = "UP", text = "Up" },
    { value = "DOWN", text = "Down" },
}
local FILTER_MODE_OPTIONS = {
    { value = "off", text = "Off (Show All)" },
    { value = "classification", text = "Classification" },
}
local TAB_SEARCH_CONTEXTS = {
    general = { subTabIndex = 1, subTabName = "General" },
    appearance = { subTabIndex = 2, subTabName = "Appearance" },
    layout = { subTabIndex = 3, subTabName = "Layout" },
    dimensions = { subTabIndex = 4, subTabName = "Dimensions" },
    rangepet = { subTabIndex = 5, subTabName = "Range & Pet" },
    spotlight = { subTabIndex = 6, subTabName = "Spotlight" },
    health = { subTabIndex = 7, subTabName = "Health" },
    power = { subTabIndex = 8, subTabName = "Power" },
    name = { subTabIndex = 9, subTabName = "Name" },
    buffs = { subTabIndex = 10, subTabName = "Buffs" },
    debuffs = { subTabIndex = 11, subTabName = "Debuffs" },
    indicators = { subTabIndex = 12, subTabName = "Indicators" },
    auraIndicators = { subTabIndex = 13, subTabName = "Aura Ind." },
    pinnedAuras = { subTabIndex = 14, subTabName = "Pinned" },
    privateAuras = { subTabIndex = 15, subTabName = "Priv. Auras" },
    healer = { subTabIndex = 16, subTabName = "Healer" },
    defensive = { subTabIndex = 17, subTabName = "Defensive" },
}
local VISUAL_DB_KEYS = {
    general = true, layout = true, health = true, power = true, name = true,
    absorbs = true, healPrediction = true, indicators = true,
    healer = true, classPower = true, range = true, auras = true,
    privateAuras = true, auraIndicators = true, castbar = true,
    portrait = true, pets = true, dimensions = true, spotlight = true,
}

local function GetGUI()
    return QUI and QUI.GUI or nil
end

local function GetOptionsAPI()
    return ns.QUI_Options
end

local function GetProfileDB()
    local core = Helpers and Helpers.GetCore and Helpers.GetCore()
    return core and core.db and core.db.profile or nil
end

local function NormalizeContextMode(contextMode)
    if contextMode == "raid" then
        return "raid"
    end
    return "party"
end

local function ResolveGroupFramesDB(contextMode)
    local profile = GetProfileDB()
    local gfdb = profile and profile.quiGroupFrames
    contextMode = NormalizeContextMode(contextMode)
    if type(gfdb) ~= "table" or type(gfdb[contextMode]) ~= "table" then
        return nil
    end

    return {
        profile = profile,
        gfdb = gfdb,
        contextMode = contextMode,
        contextDB = gfdb[contextMode],
        sourceLabel = contextMode == "raid" and "Raid" or "Party",
        targetMode = contextMode == "raid" and "party" or "raid",
        targetLabel = contextMode == "raid" and "Party" or "Raid",
    }
end

local function SetSearchContext(searchContext)
    local gui = GetGUI()
    if gui and type(gui.SetSearchContext) == "function" and type(searchContext) == "table" then
        gui:SetSearchContext(searchContext)
    end
end

local function CreateSearchContext(tabKey)
    local context = TAB_SEARCH_CONTEXTS[tabKey] or TAB_SEARCH_CONTEXTS.general
    return {
        tabIndex = 6,
        tabName = "Group Frames",
        subTabIndex = context.subTabIndex,
        subTabName = context.subTabName,
    }
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = DeepCopy(child)
    end
    return copy
end

local function EnsureSubTable(parent, key)
    if type(parent) ~= "table" then
        return nil
    end
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end
    return parent[key]
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

local function CreateSectionBuilder(sectionHost, ctx, searchContext)
    local optionsAPI = GetOptionsAPI()
    if not optionsAPI then
        return nil
    end

    PrepareSectionHost(sectionHost, ctx)
    SetSearchContext(searchContext)

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

    function builder.Description(text)
        if type(text) ~= "string" or text == "" then
            return
        end

        local description = sectionHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        description:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, y)
        description:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, y)
        description:SetJustifyH("LEFT")
        description:SetText(text)
        description:SetTextColor(
            DESCRIPTION_TEXT_COLOR[1],
            DESCRIPTION_TEXT_COLOR[2],
            DESCRIPTION_TEXT_COLOR[3],
            DESCRIPTION_TEXT_COLOR[4]
        )
        local height = 14
        if description.GetStringHeight then
            height = math.max(14, math.ceil(description:GetStringHeight() or 14))
        end
        y = y - height - 4
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

local function GetFontListWithDefault(optionsAPI)
    local fonts = {}
    if optionsAPI and type(optionsAPI.GetFontList) == "function" then
        for _, option in ipairs(optionsAPI.GetFontList() or {}) do
            fonts[#fonts + 1] = DeepCopy(option)
        end
    end
    table.insert(fonts, 1, { value = "", text = "(Frame Font)" })
    return fonts
end

local function AddAuraDurationTextRows(card, gui, optionsAPI, auras, prefix, labelPrefix, refresh, enabledCond)
    local showKey = "show" .. labelPrefix .. "DurationText"
    local fontKey = prefix .. "DurationFont"
    local fontSizeKey = prefix .. "DurationFontSize"
    local anchorKey = prefix .. "DurationAnchor"
    local offsetXKey = prefix .. "DurationOffsetX"
    local offsetYKey = prefix .. "DurationOffsetY"
    local useTimeColorKey = prefix .. "DurationUseTimeColor"
    local colorKey = prefix .. "DurationColor"
    local controlledRows = {}
    local colorRow

    local function TextEnabled()
        return enabledCond() and auras[showKey] ~= false
    end

    local function UsesStaticColor()
        local useTimeColor = auras[useTimeColorKey]
        if useTimeColor == nil then
            useTimeColor = auras.showDurationColor ~= false
        end
        return TextEnabled() and not useTimeColor
    end

    local updateRows
    local function onChange()
        refresh()
        if updateRows then
            updateRows()
        end
    end

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, showKey, auras, onChange, {
        description = "Show remaining-time text on " .. string.lower(labelPrefix) .. " icons.",
    })
    local showRow = optionsAPI.BuildSettingRow(card.frame, "Show " .. labelPrefix .. " Duration Text", showCheckbox)

    local fontDropdown = gui:CreateFormDropdown(card.frame, nil, GetFontListWithDefault(optionsAPI), fontKey, auras, onChange, nil, {
        searchable = true,
    })
    local fontRow = optionsAPI.BuildSettingRow(card.frame, "Duration Font", fontDropdown)
    controlledRows[#controlledRows + 1] = fontRow
    card.AddRow(showRow, fontRow)

    local fontSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, fontSizeKey, auras, onChange, { deferOnDrag = true }, {
        description = "Font size used for the remaining-time text.",
    })
    local fontSizeRow = optionsAPI.BuildSettingRow(card.frame, "Duration Font Size", fontSizeSlider)
    controlledRows[#controlledRows + 1] = fontSizeRow
    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, anchorKey, auras, onChange, {
        description = "Anchor point for the remaining-time text on each icon.",
    })
    local anchorRow = optionsAPI.BuildSettingRow(card.frame, "Duration Anchor", anchorDropdown)
    controlledRows[#controlledRows + 1] = anchorRow
    card.AddRow(fontSizeRow, anchorRow)

    local offsetXSlider = gui:CreateFormSlider(card.frame, nil, -40, 40, 1, offsetXKey, auras, onChange, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for duration text.",
    })
    local offsetXRow = optionsAPI.BuildSettingRow(card.frame, "Duration X Offset", offsetXSlider)
    controlledRows[#controlledRows + 1] = offsetXRow
    local offsetYSlider = gui:CreateFormSlider(card.frame, nil, -40, 40, 1, offsetYKey, auras, onChange, { deferOnDrag = true }, {
        description = "Vertical pixel offset for duration text.",
    })
    local offsetYRow = optionsAPI.BuildSettingRow(card.frame, "Duration Y Offset", offsetYSlider)
    controlledRows[#controlledRows + 1] = offsetYRow
    card.AddRow(offsetXRow, offsetYRow)

    local useTimeColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, useTimeColorKey, auras, onChange, {
        description = "Use green/yellow/red time-based duration colors instead of the static text color.",
    })
    local useTimeColorRow = optionsAPI.BuildSettingRow(card.frame, "Use Time-Based Duration Color", useTimeColorCheckbox)
    controlledRows[#controlledRows + 1] = useTimeColorRow
    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, colorKey, auras, onChange, nil, {
        description = "Static duration text color when time-based coloring is off.",
    })
    colorRow = optionsAPI.BuildSettingRow(card.frame, "Duration Text Color", colorPicker)
    card.AddRow(useTimeColorRow, colorRow)

    updateRows = function()
        local showAlpha = enabledCond() and 1.0 or 0.4
        local textAlpha = TextEnabled() and 1.0 or 0.4
        showRow:SetAlpha(showAlpha)
        for _, row in ipairs(controlledRows) do
            row:SetAlpha(textAlpha)
        end
        colorRow:SetAlpha(UsesStaticColor() and 1.0 or 0.4)
    end

    updateRows()
    return updateRows
end

local function RequestTabRepaint(ctx)
    local repaint = ctx and ctx.state and ctx.state.repaintTabs or nil
    if type(repaint) == "function" then
        repaint()
    end
end

local function ScheduleTabRepaint(ctx)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            RequestTabRepaint(ctx)
        end)
    else
        RequestTabRepaint(ctx)
    end
end

local function GetBuilderCursorY(builder)
    if not builder or type(builder.Height) ~= "function" then
        return 0
    end
    return -(builder.Height(0) or 0)
end

local function RenderEmbeddedEditorSection(sectionHost, builder, render, options)
    if not sectionHost or not builder or type(render) ~= "function" then
        return 0
    end

    local topOffset = GetBuilderCursorY(builder)
    if FullSurface and type(FullSurface.RenderEmbeddedEditor) == "function" then
        local height = FullSurface.RenderEmbeddedEditor(sectionHost, {
            topOffset = topOffset,
            minHeight = options and options.minHeight or 1,
            render = render,
        })
        height = type(height) == "number" and height or 1
        builder.Spacer(height)
        return height
    end

    local editorHost = CreateFrame("Frame", nil, sectionHost)
    editorHost:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, topOffset)
    editorHost:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, topOffset)
    editorHost:SetHeight(1)

    local height = render(editorHost)
    if type(height) ~= "number" or height <= 0 then
        height = editorHost.GetHeight and editorHost:GetHeight() or 1
    end
    height = math.max(1, height)
    editorHost:SetHeight(height)
    builder.Spacer(height)
    return height
end

local function AppendSpellListBlock(sectionHost, builder, ctx, title, description, listTable, presets, onChange)
    if not sectionHost or not builder or type(listTable) ~= "table"
        or not SpellList or type(SpellList.CreateListFrame) ~= "function" then
        return
    end

    builder.Spacer(6)
    builder.Header(title)
    builder.Description(description)

    local height = RenderEmbeddedEditorSection(sectionHost, builder, function(panel)
        local listFrame
        local function UpdatePanelHeight(nextHeight)
            if type(nextHeight) ~= "number" or nextHeight <= 0 then
                nextHeight = listFrame and listFrame.GetHeight and listFrame:GetHeight() or 1
            end
            if panel.SetHeight then
                panel:SetHeight(math.max(1, nextHeight))
            end
        end

        listFrame = SpellList.CreateListFrame(panel, listTable, presets, function()
            if type(onChange) == "function" then
                onChange()
            end
            ScheduleTabRepaint(ctx)
        end, UpdatePanelHeight)
        listFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        listFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
        UpdatePanelHeight()
        return panel.GetHeight and panel:GetHeight() or 1
    end, {
        minHeight = 1,
    })

    builder.Spacer(2)
    return height
end

local function RefreshGroupFrames(contextMode)
    if _G.QUI_RefreshGroupFrames then
        _G.QUI_RefreshGroupFrames()
    end
    if _G.QUI_LayoutModeSyncHandle then
        _G.QUI_LayoutModeSyncHandle(NormalizeContextMode(contextMode) == "raid" and "raidFrames" or "partyFrames")
    end
    if _G.QUI_RefreshGroupFramePreview then
        _G.QUI_RefreshGroupFramePreview(NormalizeContextMode(contextMode))
    end
end

local function RefreshSpotlight()
    local groupFrames = ns.QUI_GroupFrames
    if groupFrames and groupFrames.RecreateSpotlightHeader then
        groupFrames:RecreateSpotlightHeader()
    end

    local editMode = ns.QUI_GroupFrameEditMode
    if editMode then
        if editMode.DestroySpotlightHeader then
            editMode:DestroySpotlightHeader()
        end
        if editMode.CreateSpotlightHeader then
            editMode:CreateSpotlightHeader()
        end
    end

    if _G.QUI_LayoutModeSyncHandle then
        _G.QUI_LayoutModeSyncHandle("spotlightFrames")
    end

    RefreshGroupFrames("raid")
end

local function NotifyProvider(providerKey, structural)
    local compat = ns.Settings and ns.Settings.RenderAdapters
    if compat and compat.NotifyProviderChanged then
        compat.NotifyProviderChanged(providerKey, {
            structural = structural == true,
        })
    end
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

local function RenderGeneralEnableSection(sectionHost, ctx)
    local gui = GetGUI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not groupFrames then
        return nil
    end

    SetSearchContext(CreateSearchContext("general"))

    local enableCheck = gui:CreateFormCheckbox(
        sectionHost,
        "Enable QUI Group Frames (Req. Reload)",
        "enabled",
        groupFrames.gfdb,
        function()
            RefreshGroupFrames(groupFrames.contextMode)
            gui:ShowConfirmation({
                title = "Reload UI?",
                message = "Changing the QUI Group Frames enabled state requires a UI reload to take full effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function()
                    QUI:SafeReload()
                end,
            })
        end,
        { description = "Replace Blizzard's party and raid frames with QUI group frames. Requires a UI reload to take effect." }
    )
    enableCheck:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -4)
    enableCheck:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -4)

    return 42
end

local function RenderGeneralCopySettingsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    SetSearchContext(CreateSearchContext("general"))

    local header = optionsAPI.CreateAccentDotLabel(sectionHost, "Copy Settings", 0)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, 0)

    local description = gui:CreateLabel(
        sectionHost,
        "Copy all " .. groupFrames.sourceLabel .. " visual settings into " .. groupFrames.targetLabel .. ".",
        11,
        (gui.Colors and gui.Colors.textMuted) or { 0.6, 0.6, 0.6, 1 }
    )
    description:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -HEADER_GAP)
    description:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -HEADER_GAP)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)

    local descHeight = 18
    if description.GetStringHeight then
        descHeight = math.max(18, math.ceil(description:GetStringHeight() or 18))
    end

    local copyButton = gui:CreateButton(
        sectionHost,
        "Copy All: " .. groupFrames.sourceLabel .. " -> " .. groupFrames.targetLabel,
        220,
        28,
        function()
            gui:ShowConfirmation({
                title = "Copy All Settings",
                message = "This will overwrite ALL " .. groupFrames.targetLabel .. " visual settings with " .. groupFrames.sourceLabel .. " settings. Continue?",
                acceptText = "Copy All",
                cancelText = "Cancel",
                isDestructive = true,
                onAccept = function()
                    local src = groupFrames.gfdb[groupFrames.contextMode]
                    local dst = groupFrames.gfdb[groupFrames.targetMode]
                    if type(src) ~= "table" or type(dst) ~= "table" then
                        return
                    end

                    for key in pairs(VISUAL_DB_KEYS) do
                        if src[key] ~= nil then
                            dst[key] = DeepCopy(src[key])
                        end
                    end

                    RefreshGroupFrames(groupFrames.contextMode)
                    NotifyProvider("partyFrames", true)
                    NotifyProvider("raidFrames", true)
                end,
            })
        end
    )
    copyButton:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -(HEADER_GAP + descHeight + 10))

    return HEADER_GAP + descHeight + 10 + 28 + 8
end

local function RenderAppearanceSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local general = EnsureSubTable(groupFrames.contextDB, "general")
    local portrait = EnsureSubTable(groupFrames.contextDB, "portrait")
    if not general or not portrait then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("appearance"))
    if not builder then
        return nil
    end

    builder.Header("Appearance")
    builder.Description("Colors, fonts, and portrait styling for " .. groupFrames.sourceLabel .. " group frames.")

    local card = builder.Card()
    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end
    local portraitSideCell
    local portraitSizeCell

    local borderSizeSlider = gui:CreateFormSlider(card.frame, nil, 0, 3, 1, "borderSize", general, refresh, { deferOnDrag = true }, {
        description = "Border thickness in pixels around each group frame. Set to 0 to hide borders.",
    })
    local textureDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.GetTextureList(), "texture", general, refresh, {
        description = "Health bar texture used for all frames in this group. Supports SharedMedia textures.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Border Size", borderSizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Texture", textureDropdown)
    )

    local darkModeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "darkMode", general, refresh, {
        description = "Invert the frames so missing health is dark and remaining health is colored.",
    })
    local classColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "useClassColor", general, refresh, {
        description = "Color the health bar by class instead of the default non-class color.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Dark Mode", darkModeCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Use Class Color", classColorCheckbox)
    )

    local bgColorPicker = gui:CreateFormColorPicker(card.frame, nil, "defaultBgColor", general, refresh, nil, {
        description = "Backdrop color behind the health fill when Dark Mode is off.",
    })
    local bgOpacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "defaultBgOpacity", general, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = "Opacity of the default frame background.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Background Color", bgColorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Background Opacity", bgOpacitySlider)
    )

    local darkHealthColorPicker = gui:CreateFormColorPicker(card.frame, nil, "darkModeHealthColor", general, refresh, nil, {
        description = "Remaining-health fill color when Dark Mode is on.",
    })
    local darkHealthOpacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "darkModeHealthOpacity", general, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = "Opacity of the remaining-health fill in Dark Mode.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Dark Mode Health Color", darkHealthColorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Dark Mode Health Opacity", darkHealthOpacitySlider)
    )

    local darkBgColorPicker = gui:CreateFormColorPicker(card.frame, nil, "darkModeBgColor", general, refresh, nil, {
        description = "Backdrop color shown behind the health fill in Dark Mode.",
    })
    local darkBgOpacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "darkModeBgOpacity", general, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = "Opacity of the Dark Mode backdrop color.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Dark Mode BG Color", darkBgColorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Dark Mode BG Opacity", darkBgOpacitySlider)
    )

    local fontDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.GetFontList(), "font", general, refresh, {
        description = "Font used for names, health text, and indicators.",
    })
    local fontSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 20, 1, "fontSize", general, refresh, { deferOnDrag = true }, {
        description = "Font size used for group-frame text.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Font", fontDropdown),
        optionsAPI.BuildSettingRow(card.frame, "Font Size", fontSizeSlider)
    )

    local showTooltipsCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showTooltips", general, refresh, {
        description = "Show the Blizzard unit tooltip when hovering a group frame.",
    })
    local function UpdatePortraitCells()
        local alpha = portrait.showPortrait and 1.0 or 0.4
        if portraitSideCell then
            portraitSideCell:SetAlpha(alpha)
        end
        if portraitSizeCell then
            portraitSizeCell:SetAlpha(alpha)
        end
    end
    local showPortraitCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showPortrait", portrait, function()
        refresh()
        UpdatePortraitCells()
    end, {
        description = "Show a portrait next to each frame.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Tooltips on Hover", showTooltipsCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Show Portrait", showPortraitCheckbox)
    )

    local portraitSideDropdown = gui:CreateFormDropdown(card.frame, nil, ANCHOR_SIDE_OPTIONS, "portraitSide", portrait, refresh, {
        description = "Which side of the frame the portrait sits on.",
    })
    portraitSideCell = optionsAPI.BuildSettingRow(card.frame, "Portrait Side", portraitSideDropdown)
    local portraitSizeSlider = gui:CreateFormSlider(card.frame, nil, 16, 60, 1, "portraitSize", portrait, refresh, { deferOnDrag = true }, {
        description = "Portrait width and height in pixels.",
    })
    portraitSizeCell = optionsAPI.BuildSettingRow(card.frame, "Portrait Size", portraitSizeSlider)
    card.AddRow(portraitSideCell, portraitSizeCell)

    UpdatePortraitCells()
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderLayoutSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local layout = EnsureSubTable(groupFrames.contextDB, "layout")
    if not layout then
        return nil
    end

    if not layout.orientation then
        local growDirection = layout.growDirection or "DOWN"
        layout.orientation = (growDirection == "LEFT" or growDirection == "RIGHT") and "HORIZONTAL" or "VERTICAL"
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("layout"))
    if not builder then
        return nil
    end

    if groupFrames.contextMode == "raid" then
        if type(groupFrames.gfdb.testMode) ~= "table" then
            groupFrames.gfdb.testMode = {}
        end

        builder.Header("Preview Size")
        builder.Description("Controls how many placeholder raid members the preview renders.")

        local previewCard = builder.Card()
        local previewSlider = gui:CreateFormSlider(previewCard.frame, nil, 10, 40, 5, "raidCount", groupFrames.gfdb.testMode, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if editMode and editMode.IsTestMode and editMode:IsTestMode() and editMode.RefreshTestMode then
                editMode:RefreshTestMode()
            end
            if _G.QUI_LayoutModeSyncHandle then
                _G.QUI_LayoutModeSyncHandle("raidFrames")
            end
        end, { deferOnDrag = true }, {
            description = "How many placeholder raid members the test preview renders.",
        })
        previewCard.AddRow(optionsAPI.BuildSettingRow(previewCard.frame, "Raid Preview Size", previewSlider))
        builder.CloseCard(previewCard)
        builder.Spacer(10)
    end

    builder.Header("Layout")
    builder.Description("Arrange the " .. groupFrames.sourceLabel .. " frames and choose how members are grouped.")

    local card = builder.Card()
    local refresh = function(structural)
        RefreshGroupFrames(groupFrames.contextMode)
        if structural then
            NotifyProvider(groupFrames.contextMode == "raid" and "raidFrames" or "partyFrames", true)
        end
    end
    local function onOrientationChange()
        if layout.orientation == "HORIZONTAL" then
            layout.growDirection = "RIGHT"
            layout.groupGrowDirection = "DOWN"
        else
            layout.growDirection = "DOWN"
            layout.groupGrowDirection = "RIGHT"
        end
        refresh()
    end

    local orientationDropdown = gui:CreateFormDropdown(card.frame, nil, LAYOUT_OPTIONS, "orientation", layout, onOrientationChange, {
        description = "Orient frames vertically (columns) or horizontally (rows).",
    })
    local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 10, 1, "spacing", layout, refresh, { deferOnDrag = true }, {
        description = "Pixel gap between frames inside the same group.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Layout", orientationDropdown),
        optionsAPI.BuildSettingRow(card.frame, "Frame Spacing", spacingSlider)
    )

    if groupFrames.contextMode == "raid" then
        local groupBy = layout.groupBy or "GROUP"
        local groupByDropdown = gui:CreateFormDropdown(card.frame, nil, GROUP_BY_OPTIONS, "groupBy", layout, function()
            refresh(true)
            RequestTabRepaint(ctx)
        end, {
            description = "How raid members are split into groups before sorting.",
        })
        if gui.SetWidgetProviderSyncOptions then
            gui:SetWidgetProviderSyncOptions(groupByDropdown, { auto = true, structural = true })
        end

        if groupBy ~= "NONE" then
            local groupSpacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 30, 1, "groupSpacing", layout, refresh, { deferOnDrag = true }, {
                description = "Pixel gap between groups when Group By is not None.",
            })
            card.AddRow(
                optionsAPI.BuildSettingRow(card.frame, "Group By", groupByDropdown),
                optionsAPI.BuildSettingRow(card.frame, "Group Spacing", groupSpacingSlider)
            )
        else
            local unitsPerColumnSlider = gui:CreateFormSlider(card.frame, nil, 1, 40, 1, "unitsPerFlat", layout, refresh, { deferOnDrag = true }, {
                description = "How many units fit in a single column or row before wrapping.",
            })
            card.AddRow(
                optionsAPI.BuildSettingRow(card.frame, "Group By", groupByDropdown),
                optionsAPI.BuildSettingRow(card.frame, "Units Per Column", unitsPerColumnSlider)
            )
        end

        local sortMethodDropdown = gui:CreateFormDropdown(card.frame, nil, SORT_OPTIONS, "sortMethod", layout, refresh, {
            description = "Sort units by Blizzard group index or alphabetically by name.",
        })
        local selfFirstCheckbox = gui:CreateFormCheckbox(card.frame, nil, "raidSelfFirst", groupFrames.gfdb, refresh, {
            description = "Pin your own frame to the first slot regardless of the sort order.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Sort Method", sortMethodDropdown),
            optionsAPI.BuildSettingRow(card.frame, "Always Show Self First", selfFirstCheckbox)
        )

        local sortByRoleCheckbox = gui:CreateFormCheckbox(card.frame, nil, "sortByRole", layout, refresh, {
            description = "Order tanks first, healers second, and damage dealers last.",
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Sort by Role (Tank > Healer > DPS)", sortByRoleCheckbox))

        local limitGroupsCheckbox = gui:CreateFormCheckbox(card.frame, nil, "limitGroupsByRaidSize", layout, function()
            refresh(true)
            RequestTabRepaint(ctx)
        end, {
            description = "Limit visible raid groups by instance size: groups 1-4 in Mythic and 1-6 otherwise.",
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Limit Groups by Raid Size", limitGroupsCheckbox))
    else
        local showPlayerCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showPlayer", layout, refresh, {
            description = "Include the player's own frame in the party display.",
        })
        local showSoloCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showSolo", layout, refresh, {
            description = "Show the party frame while solo with only your own unit visible.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Show Player in Group", showPlayerCheckbox),
            optionsAPI.BuildSettingRow(card.frame, "Show Player Frame When Solo", showSoloCheckbox)
        )

        local selfFirstCheckbox = gui:CreateFormCheckbox(card.frame, nil, "partySelfFirst", groupFrames.gfdb, refresh, {
            description = "Pin your own frame to the first slot regardless of the sort order.",
        })
        local sortByRoleCheckbox = gui:CreateFormCheckbox(card.frame, nil, "sortByRole", layout, refresh, {
            description = "Order tanks first, healers second, and damage dealers last.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Always Show Self First", selfFirstCheckbox),
            optionsAPI.BuildSettingRow(card.frame, "Sort by Role (Tank > Healer > DPS)", sortByRoleCheckbox)
        )
    end

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderDimensionsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local dimensions = EnsureSubTable(groupFrames.contextDB, "dimensions")
    if not dimensions then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("dimensions"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    if groupFrames.contextMode ~= "raid" then
        builder.Header("Dimensions")
        builder.Description("Width and height for each " .. string.lower(groupFrames.sourceLabel) .. " frame.")

        local card = builder.Card()
        local widthSlider = gui:CreateFormSlider(card.frame, nil, 80, 400, 1, "partyWidth", dimensions, refresh, { deferOnDrag = true }, {
            description = "Width of each party frame in pixels.",
        })
        local heightSlider = gui:CreateFormSlider(card.frame, nil, 16, 80, 1, "partyHeight", dimensions, refresh, { deferOnDrag = true }, {
            description = "Height of each party frame in pixels.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Width", widthSlider),
            optionsAPI.BuildSettingRow(card.frame, "Height", heightSlider)
        )
        builder.CloseCard(card)
        return builder.Height()
    end

    local function AddSizeSection(title, widthKey, widthRange, heightKey, heightRange, description)
        builder.Header(title)
        if description then
            builder.Description(description)
        end

        local card = builder.Card()
        local widthSlider = gui:CreateFormSlider(card.frame, nil, widthRange[1], widthRange[2], 1, widthKey, dimensions, refresh, { deferOnDrag = true }, {
            description = "Frame width used for this raid-size bracket.",
        })
        local heightSlider = gui:CreateFormSlider(card.frame, nil, heightRange[1], heightRange[2], 1, heightKey, dimensions, refresh, { deferOnDrag = true }, {
            description = "Frame height used for this raid-size bracket.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Width", widthSlider),
            optionsAPI.BuildSettingRow(card.frame, "Height", heightSlider)
        )
        builder.CloseCard(card)
        builder.Spacer(10)
    end

    AddSizeSection("Small Raid (6-15 players)", "smallRaidWidth", { 60, 400 }, "smallRaidHeight", { 14, 100 },
        "Frame size used when the raid has between 6 and 15 members.")
    AddSizeSection("Medium Raid (16-25 players)", "mediumRaidWidth", { 50, 300 }, "mediumRaidHeight", { 12, 100 },
        "Frame size used when the raid has between 16 and 25 members.")
    AddSizeSection("Large Raid (26-40 players)", "largeRaidWidth", { 40, 250 }, "largeRaidHeight", { 10, 100 },
        "Frame size used when the raid has between 26 and 40 members.")
    return builder.Height()
end

local function RenderRangePetSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local range = EnsureSubTable(groupFrames.contextDB, "range")
    local pets = EnsureSubTable(groupFrames.contextDB, "pets")
    if not range or not pets then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("rangepet"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Range Check")
    builder.Description("Fade units when they move out of your supported spell range.")

    local rangeCard = builder.Card()
    local rangeAlphaCell
    local function UpdateRangeCells()
        local alpha = range.enabled and 1.0 or 0.4
        if rangeAlphaCell then
            rangeAlphaCell:SetAlpha(alpha)
        end
    end
    local rangeEnabledCheckbox = gui:CreateFormCheckbox(rangeCard.frame, nil, "enabled", range, function()
        refresh()
        UpdateRangeCells()
    end, {
        description = "Fade group frames when the unit is out of range.",
    })
    local rangeAlphaSlider = gui:CreateFormSlider(rangeCard.frame, nil, 0.1, 0.8, 0.05, "outOfRangeAlpha", range, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = "Opacity applied to out-of-range frames.",
    })
    rangeAlphaCell = optionsAPI.BuildSettingRow(rangeCard.frame, "Out-of-Range Alpha", rangeAlphaSlider)
    rangeCard.AddRow(
        optionsAPI.BuildSettingRow(rangeCard.frame, "Enable Range Check", rangeEnabledCheckbox),
        rangeAlphaCell
    )
    UpdateRangeCells()
    builder.CloseCard(rangeCard)
    builder.Spacer(10)

    builder.Header("Pet Frames")
    builder.Description("Show companion frames for pets alongside the main group.")

    local petCard = builder.Card()
    local petWidthCell
    local petHeightCell
    local petAnchorCell
    local function UpdatePetCells()
        local alpha = pets.enabled and 1.0 or 0.4
        if petWidthCell then
            petWidthCell:SetAlpha(alpha)
        end
        if petHeightCell then
            petHeightCell:SetAlpha(alpha)
        end
        if petAnchorCell then
            petAnchorCell:SetAlpha(alpha)
        end
    end
    local petsEnabledCheckbox = gui:CreateFormCheckbox(petCard.frame, nil, "enabled", pets, function()
        refresh()
        UpdatePetCells()
    end, {
        description = "Show small frames for group-member pets.",
    })
    local petWidthSlider = gui:CreateFormSlider(petCard.frame, nil, 40, 200, 1, "width", pets, refresh, { deferOnDrag = true }, {
        description = "Width of each pet frame in pixels.",
    })
    petWidthCell = optionsAPI.BuildSettingRow(petCard.frame, "Pet Frame Width", petWidthSlider)
    petCard.AddRow(
        optionsAPI.BuildSettingRow(petCard.frame, "Enable Pet Frames", petsEnabledCheckbox),
        petWidthCell
    )

    local petHeightSlider = gui:CreateFormSlider(petCard.frame, nil, 10, 40, 1, "height", pets, refresh, { deferOnDrag = true }, {
        description = "Height of each pet frame in pixels.",
    })
    petHeightCell = optionsAPI.BuildSettingRow(petCard.frame, "Pet Frame Height", petHeightSlider)
    local petAnchorDropdown = gui:CreateFormDropdown(petCard.frame, nil, PET_ANCHOR_OPTIONS, "anchorTo", pets, refresh, {
        description = "Where pet frames are anchored relative to the group.",
    })
    petAnchorCell = optionsAPI.BuildSettingRow(petCard.frame, "Pet Anchor", petAnchorDropdown)
    petCard.AddRow(petHeightCell, petAnchorCell)

    UpdatePetCells()
    builder.CloseCard(petCard)
    return builder.Height()
end

local function RenderSpotlightSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    if groupFrames.contextMode ~= "raid" then
        return RenderUnavailableLabel(sectionHost, "Spotlight is only available for Raid frames.")
    end

    local spotlight = EnsureSubTable(groupFrames.contextDB, "spotlight")
    if not spotlight then
        return nil
    end

    if not spotlight.filterMode then
        spotlight.filterMode = "ROLE"
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("spotlight"))
    if not builder then
        return nil
    end

    builder.Description("Creates a separate frame that pins raid members by role or name to a dedicated group.")

    local function onSpotlightChange(structural)
        if spotlight.enabled and not spotlight.filterTank and not spotlight.filterHealer and not spotlight.filterDamager then
            spotlight.filterTank = true
        end

        local layoutMode = ns.QUI_LayoutMode
        if layoutMode and layoutMode.SetElementEnabled then
            layoutMode:SetElementEnabled("spotlightFrames", spotlight.enabled == true)
        end

        RefreshSpotlight()
        if structural then
            NotifyProvider("spotlightFrames", true)
            RequestTabRepaint(ctx)
        end
    end

    local enableCard = builder.Card()
    local enableCheckbox = gui:CreateFormCheckbox(enableCard.frame, nil, "enabled", spotlight, function()
        onSpotlightChange()
    end, {
        description = "Enable a separate Spotlight group for pinned raid members.",
    })
    enableCard.AddRow(optionsAPI.BuildSettingRow(enableCard.frame, "Enable Spotlight", enableCheckbox))
    builder.CloseCard(enableCard)
    builder.Spacer(10)

    builder.Header("Filter")
    local filterCard = builder.Card()
    local filterModeDropdown = gui:CreateFormDropdown(filterCard.frame, nil, SPOTLIGHT_FILTER_OPTIONS, "filterMode", spotlight, function()
        onSpotlightChange(true)
    end, {
        description = "Pin members by role or by a manual character-name list.",
    })
    filterCard.AddRow(optionsAPI.BuildSettingRow(filterCard.frame, "Filter By", filterModeDropdown))

    if spotlight.filterMode == "ROLE" then
        local tankCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "filterTank", spotlight, onSpotlightChange, {
            description = "Include tanks in the Spotlight group.",
        })
        local healerCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "filterHealer", spotlight, onSpotlightChange, {
            description = "Include healers in the Spotlight group.",
        })
        filterCard.AddRow(
            optionsAPI.BuildSettingRow(filterCard.frame, "Tanks", tankCheckbox),
            optionsAPI.BuildSettingRow(filterCard.frame, "Healers", healerCheckbox)
        )
    else
        local nameListEdit = gui:CreateFormEditBox(filterCard.frame, nil, "nameList", spotlight, onSpotlightChange, {
            commitOnEnter = true,
            commitOnFocusLost = true,
        }, {
            description = "Comma-separated character names to pin in Spotlight.",
        })
        filterCard.AddRow(optionsAPI.BuildSettingRow(filterCard.frame, "Player Names", nameListEdit))
    end
    builder.CloseCard(filterCard)
    builder.Spacer(10)

    builder.Header("Dimensions")
    local dimsCard = builder.Card()
    local widthSlider = gui:CreateFormSlider(dimsCard.frame, nil, 60, 300, 1, "frameWidth", spotlight, onSpotlightChange, { deferOnDrag = true }, {
        description = "Width of each Spotlight frame in pixels.",
    })
    local heightSlider = gui:CreateFormSlider(dimsCard.frame, nil, 16, 80, 1, "frameHeight", spotlight, onSpotlightChange, { deferOnDrag = true }, {
        description = "Height of each Spotlight frame in pixels.",
    })
    dimsCard.AddRow(
        optionsAPI.BuildSettingRow(dimsCard.frame, "Width", widthSlider),
        optionsAPI.BuildSettingRow(dimsCard.frame, "Height", heightSlider)
    )
    builder.CloseCard(dimsCard)
    builder.Spacer(10)

    builder.Header("Layout")
    local layoutCard = builder.Card()
    if not spotlight.orientation then
        local growDirection = spotlight.growDirection or "DOWN"
        spotlight.orientation = (growDirection == "LEFT" or growDirection == "RIGHT") and "HORIZONTAL" or "VERTICAL"
    end
    local orientationDropdown = gui:CreateFormDropdown(layoutCard.frame, nil, LAYOUT_OPTIONS, "orientation", spotlight, function()
        spotlight.growDirection = spotlight.orientation == "HORIZONTAL" and "RIGHT" or "DOWN"
        onSpotlightChange()
    end, {
        description = "Stack Spotlight frames vertically (column) or horizontally (row).",
    })
    local spacingSlider = gui:CreateFormSlider(layoutCard.frame, nil, 0, 10, 1, "spacing", spotlight, onSpotlightChange, { deferOnDrag = true }, {
        description = "Pixel gap between adjacent Spotlight frames.",
    })
    layoutCard.AddRow(
        optionsAPI.BuildSettingRow(layoutCard.frame, "Layout", orientationDropdown),
        optionsAPI.BuildSettingRow(layoutCard.frame, "Spacing", spacingSlider)
    )
    builder.CloseCard(layoutCard)

    return builder.Height()
end

local function RenderHealthSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local general = EnsureSubTable(groupFrames.contextDB, "general")
    local health = EnsureSubTable(groupFrames.contextDB, "health")
    local absorbs = EnsureSubTable(groupFrames.contextDB, "absorbs")
    local healAbsorbs = EnsureSubTable(groupFrames.contextDB, "healAbsorbs")
    local healPrediction = EnsureSubTable(groupFrames.contextDB, "healPrediction")
    if not general or not health or not absorbs or not healAbsorbs or not healPrediction then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("health"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Health")
    builder.Description("Health fill, health text, and incoming-heal overlays for " .. groupFrames.sourceLabel .. " group frames.")

    builder.Header("Health Bar")
    local barCard = builder.Card()
    local textureDropdown = gui:CreateFormDropdown(barCard.frame, nil, optionsAPI.GetTextureList(), "texture", general, refresh, {
        description = "Statusbar texture used for the health bar. Supports SharedMedia textures.",
    })
    local healthOpacitySlider = gui:CreateFormSlider(barCard.frame, nil, 0, 1, 0.05, "defaultHealthOpacity", general, refresh, { deferOnDrag = true }, {
        description = "Opacity of the filled portion of the health bar. 1.0 is fully opaque.",
    })
    barCard.AddRow(
        optionsAPI.BuildSettingRow(barCard.frame, "Health Texture", textureDropdown),
        optionsAPI.BuildSettingRow(barCard.frame, "Health Opacity", healthOpacitySlider)
    )

    local fillDirectionDropdown = gui:CreateFormDropdown(barCard.frame, nil, HEALTH_FILL_OPTIONS, "healthFillDirection", health, refresh, {
        description = "Direction the health fill drains toward as the unit loses health.",
    })
    barCard.AddRow(optionsAPI.BuildSettingRow(barCard.frame, "Fill Direction", fillDirectionDropdown))
    builder.CloseCard(barCard)

    builder.Spacer(6)
    builder.Header("Health Text")
    local textCard = builder.Card()
    local healthDisplayRow, healthFontRow, healthAnchorRow, healthJustifyRow, healthXRow, healthYRow, healthColorRow
    local function UpdateHealthTextRows()
        local alpha = health.showHealthText and 1.0 or 0.4
        if healthDisplayRow then healthDisplayRow:SetAlpha(alpha) end
        if healthFontRow then healthFontRow:SetAlpha(alpha) end
        if healthAnchorRow then healthAnchorRow:SetAlpha(alpha) end
        if healthJustifyRow then healthJustifyRow:SetAlpha(alpha) end
        if healthXRow then healthXRow:SetAlpha(alpha) end
        if healthYRow then healthYRow:SetAlpha(alpha) end
        if healthColorRow then healthColorRow:SetAlpha(alpha) end
    end

    local showHealthTextCheckbox = gui:CreateFormCheckbox(textCard.frame, nil, "showHealthText", health, function()
        refresh()
        UpdateHealthTextRows()
    end, {
        description = "Show the unit's health as text on this frame. Use Display Style below to pick the format.",
    })
    local healthDisplayDropdown = gui:CreateFormDropdown(textCard.frame, nil, HEALTH_DISPLAY_OPTIONS, "healthDisplayStyle", health, refresh, {
        description = "How health is formatted: percent only, raw value, value-plus-percent, or deficit.",
    })
    healthDisplayRow = optionsAPI.BuildSettingRow(textCard.frame, "Display Style", healthDisplayDropdown)
    textCard.AddRow(
        optionsAPI.BuildSettingRow(textCard.frame, "Show Health Text", showHealthTextCheckbox),
        healthDisplayRow
    )

    local healthFontSlider = gui:CreateFormSlider(textCard.frame, nil, 6, 24, 1, "healthFontSize", health, refresh, { deferOnDrag = true }, {
        description = "Font size used for the health text.",
    })
    healthFontRow = optionsAPI.BuildSettingRow(textCard.frame, "Font Size", healthFontSlider)
    local healthAnchorDropdown = gui:CreateFormDropdown(textCard.frame, nil, NINE_POINT_OPTIONS, "healthAnchor", health, refresh, {
        description = "Where on the frame the health text is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    healthAnchorRow = optionsAPI.BuildSettingRow(textCard.frame, "Anchor", healthAnchorDropdown)
    textCard.AddRow(healthFontRow, healthAnchorRow)

    local healthJustifyDropdown = gui:CreateFormDropdown(textCard.frame, nil, TEXT_JUSTIFY_OPTIONS, "healthJustify", health, refresh, {
        description = "Horizontal text alignment within the health text region.",
    })
    healthJustifyRow = optionsAPI.BuildSettingRow(textCard.frame, "Text Justify", healthJustifyDropdown)
    local healthXSlider = gui:CreateFormSlider(textCard.frame, nil, -100, 100, 1, "healthOffsetX", health, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the health text from its anchor. Positive moves right, negative moves left.",
    })
    healthXRow = optionsAPI.BuildSettingRow(textCard.frame, "X Offset", healthXSlider)
    textCard.AddRow(healthJustifyRow, healthXRow)

    local healthYSlider = gui:CreateFormSlider(textCard.frame, nil, -100, 100, 1, "healthOffsetY", health, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the health text from its anchor. Positive moves up, negative moves down.",
    })
    healthYRow = optionsAPI.BuildSettingRow(textCard.frame, "Y Offset", healthYSlider)
    local healthColorPicker = gui:CreateFormColorPicker(textCard.frame, nil, "healthTextColor", health, refresh, nil, {
        description = "Color used for the health text.",
    })
    healthColorRow = optionsAPI.BuildSettingRow(textCard.frame, "Text Color", healthColorPicker)
    textCard.AddRow(healthYRow, healthColorRow)
    UpdateHealthTextRows()
    builder.CloseCard(textCard)

    builder.Spacer(6)
    builder.Header("Absorb Shield")
    local absorbCard = builder.Card()
    local absorbClassRow, absorbColorRow, absorbOpacityRow
    local function UpdateAbsorbRows()
        local enabled = absorbs.enabled == true
        local useClassColor = absorbs.useClassColor == true
        if absorbClassRow then absorbClassRow:SetAlpha(enabled and 1.0 or 0.4) end
        if absorbColorRow then absorbColorRow:SetAlpha((enabled and not useClassColor) and 1.0 or 0.4) end
        if absorbOpacityRow then absorbOpacityRow:SetAlpha(enabled and 1.0 or 0.4) end
    end

    local absorbEnableCheckbox = gui:CreateFormCheckbox(absorbCard.frame, nil, "enabled", absorbs, function()
        refresh()
        UpdateAbsorbRows()
    end, {
        description = "Overlay an indicator on the health bar showing the size of incoming damage absorbs.",
    })
    local absorbClassCheckbox = gui:CreateFormCheckbox(absorbCard.frame, nil, "useClassColor", absorbs, function()
        refresh()
        UpdateAbsorbRows()
    end, {
        description = "Tint the absorb overlay with the unit's class color instead of the Absorb Color swatch below.",
    })
    absorbClassRow = optionsAPI.BuildSettingRow(absorbCard.frame, "Use Class Color", absorbClassCheckbox)
    absorbCard.AddRow(
        optionsAPI.BuildSettingRow(absorbCard.frame, "Show Absorb Shield", absorbEnableCheckbox),
        absorbClassRow
    )

    local absorbColorPicker = gui:CreateFormColorPicker(absorbCard.frame, nil, "color", absorbs, refresh, nil, {
        description = "Tint used for the absorb overlay when Use Class Color is off.",
    })
    absorbColorRow = optionsAPI.BuildSettingRow(absorbCard.frame, "Absorb Color", absorbColorPicker)
    local absorbOpacitySlider = gui:CreateFormSlider(absorbCard.frame, nil, 0.1, 1, 0.05, "opacity", absorbs, refresh, { deferOnDrag = true }, {
        description = "Opacity of the absorb shield overlay.",
    })
    absorbOpacityRow = optionsAPI.BuildSettingRow(absorbCard.frame, "Absorb Opacity", absorbOpacitySlider)
    absorbCard.AddRow(absorbColorRow, absorbOpacityRow)
    UpdateAbsorbRows()
    builder.CloseCard(absorbCard)

    builder.Spacer(6)
    builder.Header("Heal Absorb")
    local healAbsorbCard = builder.Card()
    local healAbsorbColorRow, healAbsorbOpacityRow
    local function UpdateHealAbsorbRows()
        local alpha = healAbsorbs.enabled and 1.0 or 0.4
        if healAbsorbColorRow then healAbsorbColorRow:SetAlpha(alpha) end
        if healAbsorbOpacityRow then healAbsorbOpacityRow:SetAlpha(alpha) end
    end

    local healAbsorbEnableCheckbox = gui:CreateFormCheckbox(healAbsorbCard.frame, nil, "enabled", healAbsorbs, function()
        refresh()
        UpdateHealAbsorbRows()
    end, {
        description = "Overlay an indicator on the health bar showing active heal-absorb effects that must be healed through before real healing lands.",
    })
    local healAbsorbColorPicker = gui:CreateFormColorPicker(healAbsorbCard.frame, nil, "color", healAbsorbs, refresh, nil, {
        description = "Tint used for the heal-absorb overlay.",
    })
    healAbsorbColorRow = optionsAPI.BuildSettingRow(healAbsorbCard.frame, "Heal Absorb Color", healAbsorbColorPicker)
    healAbsorbCard.AddRow(
        optionsAPI.BuildSettingRow(healAbsorbCard.frame, "Show Heal Absorb", healAbsorbEnableCheckbox),
        healAbsorbColorRow
    )

    local healAbsorbOpacitySlider = gui:CreateFormSlider(healAbsorbCard.frame, nil, 0.1, 1, 0.05, "opacity", healAbsorbs, refresh, { deferOnDrag = true }, {
        description = "Opacity of the heal-absorb overlay.",
    })
    healAbsorbOpacityRow = optionsAPI.BuildSettingRow(healAbsorbCard.frame, "Heal Absorb Opacity", healAbsorbOpacitySlider)
    healAbsorbCard.AddRow(healAbsorbOpacityRow)
    UpdateHealAbsorbRows()
    builder.CloseCard(healAbsorbCard)

    builder.Spacer(6)
    builder.Header("Heal Prediction")
    local healPredictionCard = builder.Card()
    local healPredictionClassRow, healPredictionColorRow, healPredictionOpacityRow
    local function UpdateHealPredictionRows()
        local enabled = healPrediction.enabled == true
        local useClassColor = healPrediction.useClassColor == true
        if healPredictionClassRow then healPredictionClassRow:SetAlpha(enabled and 1.0 or 0.4) end
        if healPredictionColorRow then healPredictionColorRow:SetAlpha((enabled and not useClassColor) and 1.0 or 0.4) end
        if healPredictionOpacityRow then healPredictionOpacityRow:SetAlpha(enabled and 1.0 or 0.4) end
    end

    local healPredictionEnableCheckbox = gui:CreateFormCheckbox(healPredictionCard.frame, nil, "enabled", healPrediction, function()
        refresh()
        UpdateHealPredictionRows()
    end, {
        description = "Overlay an indicator on the health bar showing heals being cast on this unit before they land.",
    })
    local healPredictionClassCheckbox = gui:CreateFormCheckbox(healPredictionCard.frame, nil, "useClassColor", healPrediction, function()
        refresh()
        UpdateHealPredictionRows()
    end, {
        description = "Tint the heal-prediction overlay with the caster's class color instead of the Heal Prediction Color swatch below.",
    })
    healPredictionClassRow = optionsAPI.BuildSettingRow(healPredictionCard.frame, "Use Class Color", healPredictionClassCheckbox)
    healPredictionCard.AddRow(
        optionsAPI.BuildSettingRow(healPredictionCard.frame, "Show Heal Prediction", healPredictionEnableCheckbox),
        healPredictionClassRow
    )

    local healPredictionColorPicker = gui:CreateFormColorPicker(healPredictionCard.frame, nil, "color", healPrediction, refresh, nil, {
        description = "Tint used for the incoming-heal overlay when Use Class Color is off.",
    })
    healPredictionColorRow = optionsAPI.BuildSettingRow(healPredictionCard.frame, "Heal Prediction Color", healPredictionColorPicker)
    local healPredictionOpacitySlider = gui:CreateFormSlider(healPredictionCard.frame, nil, 0.1, 1, 0.05, "opacity", healPrediction, refresh, { deferOnDrag = true }, {
        description = "Opacity of the incoming-heal overlay.",
    })
    healPredictionOpacityRow = optionsAPI.BuildSettingRow(healPredictionCard.frame, "Heal Prediction Opacity", healPredictionOpacitySlider)
    healPredictionCard.AddRow(healPredictionColorRow, healPredictionOpacityRow)
    UpdateHealPredictionRows()
    builder.CloseCard(healPredictionCard)

    return builder.Height()
end

local function RenderPowerSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local power = EnsureSubTable(groupFrames.contextDB, "power")
    if not power then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("power"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Power")
    builder.Description("Power-bar visibility and coloring for " .. groupFrames.sourceLabel .. " group frames.")

    local card = builder.Card()
    local heightRow, healerRow, tankRow, usePowerColorRow, customColorRow
    local function UpdatePowerRows()
        local showPowerBar = power.showPowerBar == true
        local usePowerColor = power.powerBarUsePowerColor == true
        local alpha = showPowerBar and 1.0 or 0.4
        if heightRow then heightRow:SetAlpha(alpha) end
        if healerRow then healerRow:SetAlpha(alpha) end
        if tankRow then tankRow:SetAlpha(alpha) end
        if usePowerColorRow then usePowerColorRow:SetAlpha(alpha) end
        if customColorRow then
            customColorRow:SetAlpha((showPowerBar and not usePowerColor) and 1.0 or 0.4)
        end
    end

    local showPowerBarCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showPowerBar", power, function()
        refresh()
        UpdatePowerRows()
    end, {
        description = "Show a power bar below the health bar on this frame.",
    })
    local heightSlider = gui:CreateFormSlider(card.frame, nil, 1, 12, 1, "powerBarHeight", power, refresh, { deferOnDrag = true }, {
        description = "Height of the power bar in pixels. Counted as part of the overall frame height.",
    })
    heightRow = optionsAPI.BuildSettingRow(card.frame, "Height", heightSlider)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Power Bar", showPowerBarCheckbox),
        heightRow
    )

    local healerCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarOnlyHealers", power, refresh, {
        description = "Restrict the power bar to units specced as healers.",
    })
    healerRow = optionsAPI.BuildSettingRow(card.frame, "Only Show for Healers", healerCheckbox)
    local tankCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarOnlyTanks", power, refresh, {
        description = "Restrict the power bar to units specced as tanks.",
    })
    tankRow = optionsAPI.BuildSettingRow(card.frame, "Only Show for Tanks", tankCheckbox)
    card.AddRow(healerRow, tankRow)

    local usePowerColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarUsePowerColor", power, function()
        refresh()
        UpdatePowerRows()
    end, {
        description = "Color the power bar by power type instead of the Custom Color swatch below.",
    })
    usePowerColorRow = optionsAPI.BuildSettingRow(card.frame, "Use Power Type Color", usePowerColorCheckbox)
    local customColorPicker = gui:CreateFormColorPicker(card.frame, nil, "powerBarColor", power, refresh, nil, {
        description = "Solid color for the power bar when Use Power Type Color is off.",
    })
    customColorRow = optionsAPI.BuildSettingRow(card.frame, "Custom Color", customColorPicker)
    card.AddRow(usePowerColorRow, customColorRow)

    UpdatePowerRows()
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderNameSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local name = EnsureSubTable(groupFrames.contextDB, "name")
    if not name then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("name"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Name")
    builder.Description("Name text placement and styling for " .. groupFrames.sourceLabel .. " group frames.")

    local card = builder.Card()
    local fontSizeRow, anchorRow, justifyRow, maxLengthRow, xOffsetRow, yOffsetRow, useClassColorRow, textColorRow
    local function UpdateNameRows()
        local showName = name.showName == true
        local useClassColor = name.nameTextUseClassColor == true
        local alpha = showName and 1.0 or 0.4
        if fontSizeRow then fontSizeRow:SetAlpha(alpha) end
        if anchorRow then anchorRow:SetAlpha(alpha) end
        if justifyRow then justifyRow:SetAlpha(alpha) end
        if maxLengthRow then maxLengthRow:SetAlpha(alpha) end
        if xOffsetRow then xOffsetRow:SetAlpha(alpha) end
        if yOffsetRow then yOffsetRow:SetAlpha(alpha) end
        if useClassColorRow then useClassColorRow:SetAlpha(alpha) end
        if textColorRow then
            textColorRow:SetAlpha((showName and not useClassColor) and 1.0 or 0.4)
        end
    end

    local showNameCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showName", name, function()
        refresh()
        UpdateNameRows()
    end, {
        description = "Show the unit's name on this frame.",
    })
    local fontSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, "nameFontSize", name, refresh, { deferOnDrag = true }, {
        description = "Font size used for the unit's name.",
    })
    fontSizeRow = optionsAPI.BuildSettingRow(card.frame, "Font Size", fontSizeSlider)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Name", showNameCheckbox),
        fontSizeRow
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "nameAnchor", name, refresh, {
        description = "Where on the frame the name text is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    anchorRow = optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown)
    local justifyDropdown = gui:CreateFormDropdown(card.frame, nil, TEXT_JUSTIFY_OPTIONS, "nameJustify", name, refresh, {
        description = "Horizontal text alignment within the name text region.",
    })
    justifyRow = optionsAPI.BuildSettingRow(card.frame, "Text Justify", justifyDropdown)
    card.AddRow(anchorRow, justifyRow)

    local maxLengthSlider = gui:CreateFormSlider(card.frame, nil, 0, 20, 1, "maxNameLength", name, refresh, { deferOnDrag = true }, {
        description = "Truncate names longer than this many characters. Set to 0 to disable truncation entirely.",
    })
    maxLengthRow = optionsAPI.BuildSettingRow(card.frame, "Max Name Length (0 = unlimited)", maxLengthSlider)
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "nameOffsetX", name, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the name text from its anchor. Positive moves right, negative moves left.",
    })
    xOffsetRow = optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider)
    card.AddRow(maxLengthRow, xOffsetRow)

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "nameOffsetY", name, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the name text from its anchor. Positive moves up, negative moves down.",
    })
    yOffsetRow = optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
    local useClassColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "nameTextUseClassColor", name, function()
        refresh()
        UpdateNameRows()
    end, {
        description = "Color the name text by the unit's class instead of the Text Color swatch below.",
    })
    useClassColorRow = optionsAPI.BuildSettingRow(card.frame, "Use Class Color", useClassColorCheckbox)
    card.AddRow(yOffsetRow, useClassColorRow)

    local textColorPicker = gui:CreateFormColorPicker(card.frame, nil, "nameTextColor", name, refresh, nil, {
        description = "Color used for the name when Use Class Color is off.",
    })
    textColorRow = optionsAPI.BuildSettingRow(card.frame, "Text Color", textColorPicker)
    card.AddRow(textColorRow)

    UpdateNameRows()
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderPrivateAurasSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local privateAuras = EnsureSubTable(groupFrames.contextDB, "privateAuras")
    if not privateAuras then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("privateAuras"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Private Auras")
    builder.Description("Private-aura anchors and countdown styling for " .. groupFrames.sourceLabel .. " group frames.")

    local card = builder.Card()
    local controlledRows = {}
    local function UpdatePrivateAuraRows()
        local alpha = privateAuras.enabled and 1.0 or 0.4
        for _, row in ipairs(controlledRows) do
            row:SetAlpha(alpha)
        end
    end

    local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", privateAuras, function()
        refresh()
        UpdatePrivateAuraRows()
    end, {
        description = "Anchor Blizzard private aura indicators to this frame.",
    })
    local maxPerFrameSlider = gui:CreateFormSlider(card.frame, nil, 1, 5, 1, "maxPerFrame", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Hard cap on how many private aura slots this frame displays at once.",
    })
    local maxPerFrameRow = optionsAPI.BuildSettingRow(card.frame, "Max Per Frame", maxPerFrameSlider)
    controlledRows[#controlledRows + 1] = maxPerFrameRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Enable Private Auras", enableCheckbox),
        maxPerFrameRow
    )

    local iconSizeSlider = gui:CreateFormSlider(card.frame, nil, 10, 40, 1, "iconSize", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Pixel size of each private aura icon.",
    })
    local iconSizeRow = optionsAPI.BuildSettingRow(card.frame, "Icon Size", iconSizeSlider)
    controlledRows[#controlledRows + 1] = iconSizeRow
    local growDirectionDropdown = gui:CreateFormDropdown(card.frame, nil, AURA_GROW_OPTIONS, "growDirection", privateAuras, refresh, {
        description = "Direction additional private aura icons are added in after the first.",
    })
    local growDirectionRow = optionsAPI.BuildSettingRow(card.frame, "Grow Direction", growDirectionDropdown)
    controlledRows[#controlledRows + 1] = growDirectionRow
    card.AddRow(iconSizeRow, growDirectionRow)

    local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 8, 1, "spacing", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Pixel gap between adjacent private aura icons.",
    })
    local spacingRow = optionsAPI.BuildSettingRow(card.frame, "Spacing", spacingSlider)
    controlledRows[#controlledRows + 1] = spacingRow
    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "anchor", privateAuras, refresh, {
        description = "Where on the frame the first private aura icon is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    local anchorRow = optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown)
    controlledRows[#controlledRows + 1] = anchorRow
    card.AddRow(spacingRow, anchorRow)

    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "anchorOffsetX", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the private aura block from its anchor.",
    })
    local xOffsetRow = optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider)
    controlledRows[#controlledRows + 1] = xOffsetRow
    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "anchorOffsetY", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the private aura block from its anchor.",
    })
    local yOffsetRow = optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
    controlledRows[#controlledRows + 1] = yOffsetRow
    card.AddRow(xOffsetRow, yOffsetRow)

    local borderScaleSlider = gui:CreateFormSlider(card.frame, nil, -100, 10, 0.5, "borderScale", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Scale applied to the Blizzard-drawn border around each private aura icon.",
    })
    local borderScaleRow = optionsAPI.BuildSettingRow(card.frame, "Border Scale", borderScaleSlider)
    controlledRows[#controlledRows + 1] = borderScaleRow
    local showCountdownCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showCountdown", privateAuras, refresh, {
        description = "Show the cooldown swipe animation over private aura icons.",
    })
    local showCountdownRow = optionsAPI.BuildSettingRow(card.frame, "Show Countdown", showCountdownCheckbox)
    controlledRows[#controlledRows + 1] = showCountdownRow
    card.AddRow(borderScaleRow, showCountdownRow)

    local showCountdownNumbersCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showCountdownNumbers", privateAuras, refresh, {
        description = "Show the remaining-duration countdown text over private aura icons.",
    })
    local showCountdownNumbersRow = optionsAPI.BuildSettingRow(card.frame, "Show Countdown Numbers", showCountdownNumbersCheckbox)
    controlledRows[#controlledRows + 1] = showCountdownNumbersRow
    local reverseSwipeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "reverseSwipe", privateAuras, refresh, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the aura ticks down.",
    })
    local reverseSwipeRow = optionsAPI.BuildSettingRow(card.frame, "Reverse Swipe", reverseSwipeCheckbox)
    controlledRows[#controlledRows + 1] = reverseSwipeRow
    card.AddRow(showCountdownNumbersRow, reverseSwipeRow)

    local textScaleSlider = gui:CreateFormSlider(card.frame, nil, 0.5, 5, 0.5, "textScale", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Scale multiplier for the stack count and countdown number text on private aura icons.",
    })
    local textScaleRow = optionsAPI.BuildSettingRow(card.frame, "Stack & Countdown Scale", textScaleSlider)
    controlledRows[#controlledRows + 1] = textScaleRow
    local textOffsetXSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "textOffsetX", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the stack count and countdown number text on private aura icons.",
    })
    local textOffsetXRow = optionsAPI.BuildSettingRow(card.frame, "Stack & Countdown X Offset", textOffsetXSlider)
    controlledRows[#controlledRows + 1] = textOffsetXRow
    card.AddRow(textScaleRow, textOffsetXRow)

    local textOffsetYSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "textOffsetY", privateAuras, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the stack count and countdown number text on private aura icons.",
    })
    local textOffsetYRow = optionsAPI.BuildSettingRow(card.frame, "Stack & Countdown Y Offset", textOffsetYSlider)
    controlledRows[#controlledRows + 1] = textOffsetYRow
    card.AddRow(textOffsetYRow)

    UpdatePrivateAuraRows()
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderHealerSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local healer = EnsureSubTable(groupFrames.contextDB, "healer")
    if not healer then
        return nil
    end
    local dispel = EnsureSubTable(healer, "dispelOverlay")
    local targetHighlight = EnsureSubTable(healer, "targetHighlight")
    if not dispel or not targetHighlight then
        return nil
    end
    if type(dispel.colors) ~= "table" then
        dispel.colors = {
            Magic = { 0.2, 0.6, 1.0, 1 },
            Curse = { 0.6, 0.0, 1.0, 1 },
            Disease = { 0.6, 0.4, 0.0, 1 },
            Poison = { 0.0, 0.6, 0.0, 1 },
        }
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("healer"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Healer")
    builder.Description("Dispel overlays, including Blizzard private-dispel markers when available, and target-highlighting helpers for " .. groupFrames.sourceLabel .. " group frames.")

    builder.Header("Dispel Overlay")
    local dispelCard = builder.Card()
    local dispelRows = {}
    local function UpdateDispelRows()
        local alpha = dispel.enabled and 1.0 or 0.4
        for _, row in ipairs(dispelRows) do
            row:SetAlpha(alpha)
        end
    end

    local dispelEnableCheckbox = gui:CreateFormCheckbox(dispelCard.frame, nil, "enabled", dispel, function()
        refresh()
        UpdateDispelRows()
    end, {
        description = "Outline the frame border in the dispel type's color when a dispellable debuff or private-dispel marker is active on the unit.",
    })
    local borderSizeSlider = gui:CreateFormSlider(dispelCard.frame, nil, 1, 16, 1, "borderSize", dispel, refresh, { deferOnDrag = true }, {
        description = "Pixel thickness of the dispel border.",
    })
    local borderSizeRow = optionsAPI.BuildSettingRow(dispelCard.frame, "Border Size", borderSizeSlider)
    dispelRows[#dispelRows + 1] = borderSizeRow
    dispelCard.AddRow(
        optionsAPI.BuildSettingRow(dispelCard.frame, "Enable Dispel Overlay", dispelEnableCheckbox),
        borderSizeRow
    )

    local borderOpacitySlider = gui:CreateFormSlider(dispelCard.frame, nil, 0.1, 1, 0.05, "opacity", dispel, refresh, { deferOnDrag = true }, {
        description = "Opacity of the dispel-type colored border.",
    })
    local borderOpacityRow = optionsAPI.BuildSettingRow(dispelCard.frame, "Border Opacity", borderOpacitySlider)
    dispelRows[#dispelRows + 1] = borderOpacityRow
    local fillOpacitySlider = gui:CreateFormSlider(dispelCard.frame, nil, 0, 0.5, 0.05, "fillOpacity", dispel, refresh, { deferOnDrag = true }, {
        description = "Opacity of a color tint applied across the health bar when a dispellable debuff is active.",
    })
    local fillOpacityRow = optionsAPI.BuildSettingRow(dispelCard.frame, "Fill Opacity", fillOpacitySlider)
    dispelRows[#dispelRows + 1] = fillOpacityRow
    dispelCard.AddRow(borderOpacityRow, fillOpacityRow)

    local magicColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Magic", dispel.colors, refresh, nil, {
        description = "Color used when the active dispellable debuff is of Magic type.",
    })
    local magicColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, "Magic Color", magicColorPicker)
    dispelRows[#dispelRows + 1] = magicColorRow
    local curseColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Curse", dispel.colors, refresh, nil, {
        description = "Color used when the active dispellable debuff is of Curse type.",
    })
    local curseColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, "Curse Color", curseColorPicker)
    dispelRows[#dispelRows + 1] = curseColorRow
    dispelCard.AddRow(magicColorRow, curseColorRow)

    local diseaseColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Disease", dispel.colors, refresh, nil, {
        description = "Color used when the active dispellable debuff is of Disease type.",
    })
    local diseaseColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, "Disease Color", diseaseColorPicker)
    dispelRows[#dispelRows + 1] = diseaseColorRow
    local poisonColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Poison", dispel.colors, refresh, nil, {
        description = "Color used when the active dispellable debuff is of Poison type.",
    })
    local poisonColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, "Poison Color", poisonColorPicker)
    dispelRows[#dispelRows + 1] = poisonColorRow
    dispelCard.AddRow(diseaseColorRow, poisonColorRow)

    UpdateDispelRows()
    builder.CloseCard(dispelCard)

    builder.Spacer(6)
    builder.Header("Target Highlight")
    local targetCard = builder.Card()
    local targetColorRow, targetFillRow
    local function UpdateTargetRows()
        local alpha = targetHighlight.enabled and 1.0 or 0.4
        if targetColorRow then targetColorRow:SetAlpha(alpha) end
        if targetFillRow then targetFillRow:SetAlpha(alpha) end
    end

    local targetEnableCheckbox = gui:CreateFormCheckbox(targetCard.frame, nil, "enabled", targetHighlight, function()
        refresh()
        UpdateTargetRows()
    end, {
        description = "Highlight the frame representing your current target so it stands out in party/raid.",
    })
    local targetColorPicker = gui:CreateFormColorPicker(targetCard.frame, nil, "color", targetHighlight, refresh, nil, {
        description = "Color used for the target highlight border and optional fill tint.",
    })
    targetColorRow = optionsAPI.BuildSettingRow(targetCard.frame, "Highlight Color", targetColorPicker)
    targetCard.AddRow(
        optionsAPI.BuildSettingRow(targetCard.frame, "Enable Target Highlight", targetEnableCheckbox),
        targetColorRow
    )

    local targetFillSlider = gui:CreateFormSlider(targetCard.frame, nil, 0, 0.5, 0.05, "fillOpacity", targetHighlight, refresh, { deferOnDrag = true }, {
        description = "Opacity of a color tint applied across the targeted unit's health bar.",
    })
    targetFillRow = optionsAPI.BuildSettingRow(targetCard.frame, "Fill Opacity", targetFillSlider)
    targetCard.AddRow(targetFillRow)
    UpdateTargetRows()
    builder.CloseCard(targetCard)

    return builder.Height()
end

local function RenderDefensiveSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local healer = EnsureSubTable(groupFrames.contextDB, "healer")
    if not healer then
        return nil
    end
    local defensive = EnsureSubTable(healer, "defensiveIndicator")
    if not defensive then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("defensive"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Defensive")
    builder.Description("Defensive-cooldown icon strip placement for " .. groupFrames.sourceLabel .. " group frames.")

    local card = builder.Card()
    local controlledRows = {}
    local function UpdateDefensiveRows()
        local alpha = defensive.enabled and 1.0 or 0.4
        for _, row in ipairs(controlledRows) do
            row:SetAlpha(alpha)
        end
    end

    local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", defensive, function()
        refresh()
        UpdateDefensiveRows()
    end, {
        description = "Show a dedicated icon strip for active defensive cooldowns on this frame.",
    })
    local maxIconsSlider = gui:CreateFormSlider(card.frame, nil, 1, 5, 1, "maxIcons", defensive, refresh, { deferOnDrag = true }, {
        description = "Hard cap on how many defensive icons this frame displays at once.",
    })
    local maxIconsRow = optionsAPI.BuildSettingRow(card.frame, "Max Icons", maxIconsSlider)
    controlledRows[#controlledRows + 1] = maxIconsRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Enable Defensive Indicator", enableCheckbox),
        maxIconsRow
    )

    local iconSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 32, 1, "iconSize", defensive, refresh, { deferOnDrag = true }, {
        description = "Pixel size of each defensive icon.",
    })
    local iconSizeRow = optionsAPI.BuildSettingRow(card.frame, "Icon Size", iconSizeSlider)
    controlledRows[#controlledRows + 1] = iconSizeRow
    local reverseSwipeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "reverseSwipe", defensive, refresh, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the defensive ticks down.",
    })
    local reverseSwipeRow = optionsAPI.BuildSettingRow(card.frame, "Reverse Swipe", reverseSwipeCheckbox)
    controlledRows[#controlledRows + 1] = reverseSwipeRow
    card.AddRow(iconSizeRow, reverseSwipeRow)

    local growDirectionDropdown = gui:CreateFormDropdown(card.frame, nil, AURA_GROW_OPTIONS, "growDirection", defensive, refresh, {
        description = "Direction additional defensive icons are added in after the first.",
    })
    local growDirectionRow = optionsAPI.BuildSettingRow(card.frame, "Grow Direction", growDirectionDropdown)
    controlledRows[#controlledRows + 1] = growDirectionRow
    local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 8, 1, "spacing", defensive, refresh, { deferOnDrag = true }, {
        description = "Pixel gap between adjacent defensive icons.",
    })
    local spacingRow = optionsAPI.BuildSettingRow(card.frame, "Spacing", spacingSlider)
    controlledRows[#controlledRows + 1] = spacingRow
    card.AddRow(growDirectionRow, spacingRow)

    local positionDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "position", defensive, refresh, {
        description = "Where on the frame the defensive icon strip is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    local positionRow = optionsAPI.BuildSettingRow(card.frame, "Position", positionDropdown)
    controlledRows[#controlledRows + 1] = positionRow
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetX", defensive, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the defensive icons from their anchor.",
    })
    local xOffsetRow = optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider)
    controlledRows[#controlledRows + 1] = xOffsetRow
    card.AddRow(positionRow, xOffsetRow)

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetY", defensive, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the defensive icons from their anchor.",
    })
    local yOffsetRow = optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
    controlledRows[#controlledRows + 1] = yOffsetRow
    card.AddRow(yOffsetRow)

    UpdateDefensiveRows()
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderIndicatorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local indicators = EnsureSubTable(groupFrames.contextDB, "indicators")
    if not indicators then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("indicators"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Indicators")
    builder.Description("Utility icons and threat highlights for " .. groupFrames.sourceLabel .. " group frames.")

    builder.Header("Role Icon")
    local roleCard = builder.Card()
    local roleRows = {}
    local function UpdateRoleRows()
        local alpha = indicators.showRoleIcon and 1.0 or 0.4
        for _, row in ipairs(roleRows) do
            row:SetAlpha(alpha)
        end
    end

    local showRoleIconCheckbox = gui:CreateFormCheckbox(roleCard.frame, nil, "showRoleIcon", indicators, function()
        refresh()
        UpdateRoleRows()
    end, {
        description = "Show the unit's assigned group role icon on this frame.",
    })
    local showTankCheckbox = gui:CreateFormCheckbox(roleCard.frame, nil, "showRoleTank", indicators, refresh, {
        description = "Include the tank role icon on units specced as tanks.",
    })
    local showTankRow = optionsAPI.BuildSettingRow(roleCard.frame, "Show Tank", showTankCheckbox)
    roleRows[#roleRows + 1] = showTankRow
    roleCard.AddRow(
        optionsAPI.BuildSettingRow(roleCard.frame, "Show Role Icon", showRoleIconCheckbox),
        showTankRow
    )

    local showHealerCheckbox = gui:CreateFormCheckbox(roleCard.frame, nil, "showRoleHealer", indicators, refresh, {
        description = "Include the healer role icon on units specced as healers.",
    })
    local showHealerRow = optionsAPI.BuildSettingRow(roleCard.frame, "Show Healer", showHealerCheckbox)
    roleRows[#roleRows + 1] = showHealerRow
    local showDPSCheckbox = gui:CreateFormCheckbox(roleCard.frame, nil, "showRoleDPS", indicators, refresh, {
        description = "Include the DPS role icon on units specced as damage dealers.",
    })
    local showDPSRow = optionsAPI.BuildSettingRow(roleCard.frame, "Show DPS", showDPSCheckbox)
    roleRows[#roleRows + 1] = showDPSRow
    roleCard.AddRow(showHealerRow, showDPSRow)

    local roleSizeSlider = gui:CreateFormSlider(roleCard.frame, nil, 6, 24, 1, "roleIconSize", indicators, refresh, { deferOnDrag = true }, {
        description = "Pixel size of the role icon.",
    })
    local roleSizeRow = optionsAPI.BuildSettingRow(roleCard.frame, "Icon Size", roleSizeSlider)
    roleRows[#roleRows + 1] = roleSizeRow
    local roleAnchorDropdown = gui:CreateFormDropdown(roleCard.frame, nil, NINE_POINT_OPTIONS, "roleIconAnchor", indicators, refresh, {
        description = "Where on the frame the role icon is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    local roleAnchorRow = optionsAPI.BuildSettingRow(roleCard.frame, "Anchor", roleAnchorDropdown)
    roleRows[#roleRows + 1] = roleAnchorRow
    roleCard.AddRow(roleSizeRow, roleAnchorRow)

    local roleXSlider = gui:CreateFormSlider(roleCard.frame, nil, -100, 100, 1, "roleIconOffsetX", indicators, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the role icon from its anchor.",
    })
    local roleXRow = optionsAPI.BuildSettingRow(roleCard.frame, "X Offset", roleXSlider)
    roleRows[#roleRows + 1] = roleXRow
    local roleYSlider = gui:CreateFormSlider(roleCard.frame, nil, -100, 100, 1, "roleIconOffsetY", indicators, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the role icon from its anchor.",
    })
    local roleYRow = optionsAPI.BuildSettingRow(roleCard.frame, "Y Offset", roleYSlider)
    roleRows[#roleRows + 1] = roleYRow
    roleCard.AddRow(roleXRow, roleYRow)
    UpdateRoleRows()
    builder.CloseCard(roleCard)

    local function AddIndicatorCard(title, showKey, sizeKey, anchorKey, offXKey, offYKey)
        builder.Spacer(6)
        builder.Header(title)

        local card = builder.Card()
        local controlledRows = {}
        local function UpdateRows()
            local alpha = indicators[showKey] and 1.0 or 0.4
            for _, row in ipairs(controlledRows) do
                row:SetAlpha(alpha)
            end
        end

        local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, showKey, indicators, function()
            refresh()
            UpdateRows()
        end, {
            description = "Show the " .. title .. " indicator on this unit frame.",
        })
        local sizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 32, 1, sizeKey, indicators, refresh, { deferOnDrag = true }, {
            description = "Pixel size of the " .. title .. " indicator.",
        })
        local sizeRow = optionsAPI.BuildSettingRow(card.frame, "Icon Size", sizeSlider)
        controlledRows[#controlledRows + 1] = sizeRow
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Enable", enableCheckbox),
            sizeRow
        )

        local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, anchorKey, indicators, refresh, {
            description = "Where on the frame the " .. title .. " indicator is anchored. X/Y Offset below nudges it from this anchor point.",
        })
        local anchorRow = optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown)
        controlledRows[#controlledRows + 1] = anchorRow
        local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, offXKey, indicators, refresh, { deferOnDrag = true }, {
            description = "Horizontal pixel offset for the " .. title .. " indicator from its anchor.",
        })
        local xOffsetRow = optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider)
        controlledRows[#controlledRows + 1] = xOffsetRow
        card.AddRow(anchorRow, xOffsetRow)

        local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, offYKey, indicators, refresh, { deferOnDrag = true }, {
            description = "Vertical pixel offset for the " .. title .. " indicator from its anchor.",
        })
        local yOffsetRow = optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
        controlledRows[#controlledRows + 1] = yOffsetRow
        card.AddRow(yOffsetRow)

        UpdateRows()
        builder.CloseCard(card)
    end

    AddIndicatorCard("Ready Check", "showReadyCheck", "readyCheckSize", "readyCheckAnchor", "readyCheckOffsetX", "readyCheckOffsetY")
    AddIndicatorCard("Resurrection", "showResurrection", "resurrectionSize", "resurrectionAnchor", "resurrectionOffsetX", "resurrectionOffsetY")
    AddIndicatorCard("Summon Pending", "showSummonPending", "summonSize", "summonAnchor", "summonOffsetX", "summonOffsetY")
    AddIndicatorCard("Leader Icon", "showLeaderIcon", "leaderSize", "leaderAnchor", "leaderOffsetX", "leaderOffsetY")
    AddIndicatorCard("Raid Target Marker", "showTargetMarker", "targetMarkerSize", "targetMarkerAnchor", "targetMarkerOffsetX", "targetMarkerOffsetY")
    AddIndicatorCard("Phase Icon", "showPhaseIcon", "phaseSize", "phaseAnchor", "phaseOffsetX", "phaseOffsetY")

    builder.Spacer(6)
    builder.Header("Threat")
    local threatCard = builder.Card()
    local threatRows = {}
    local function UpdateThreatRows()
        local alpha = indicators.showThreatBorder and 1.0 or 0.4
        for _, row in ipairs(threatRows) do
            row:SetAlpha(alpha)
        end
    end

    local showThreatCheckbox = gui:CreateFormCheckbox(threatCard.frame, nil, "showThreatBorder", indicators, function()
        refresh()
        UpdateThreatRows()
    end, {
        description = "Outline the frame border when the unit has aggro on an NPC.",
    })
    local borderSizeSlider = gui:CreateFormSlider(threatCard.frame, nil, 1, 16, 1, "threatBorderSize", indicators, refresh, { deferOnDrag = true }, {
        description = "Pixel thickness of the threat border.",
    })
    local borderSizeRow = optionsAPI.BuildSettingRow(threatCard.frame, "Border Size", borderSizeSlider)
    threatRows[#threatRows + 1] = borderSizeRow
    threatCard.AddRow(
        optionsAPI.BuildSettingRow(threatCard.frame, "Show Threat Border", showThreatCheckbox),
        borderSizeRow
    )

    local threatColorPicker = gui:CreateFormColorPicker(threatCard.frame, nil, "threatColor", indicators, refresh, nil, {
        description = "Color used for the threat border and optional fill tint.",
    })
    local threatColorRow = optionsAPI.BuildSettingRow(threatCard.frame, "Threat Color", threatColorPicker)
    threatRows[#threatRows + 1] = threatColorRow
    local threatFillSlider = gui:CreateFormSlider(threatCard.frame, nil, 0, 0.5, 0.05, "threatFillOpacity", indicators, refresh, { deferOnDrag = true }, {
        description = "Opacity of a color tint applied across the health bar when the unit has aggro. Set to 0 to keep only the border.",
    })
    local threatFillRow = optionsAPI.BuildSettingRow(threatCard.frame, "Threat Fill Opacity", threatFillSlider)
    threatRows[#threatRows + 1] = threatFillRow
    threatCard.AddRow(threatColorRow, threatFillRow)
    UpdateThreatRows()
    builder.CloseCard(threatCard)

    return builder.Height()
end

local function RenderBuffsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local auras = EnsureSubTable(groupFrames.contextDB, "auras")
    if not auras then
        return nil
    end
    local buffClassifications = EnsureSubTable(auras, "buffClassifications")
    local buffBlacklist = EnsureSubTable(auras, "buffBlacklist")
    if not buffClassifications or not buffBlacklist then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("buffs"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Buffs")
    builder.Description("Buff icon placement and filtering for " .. groupFrames.sourceLabel .. " group frames.")

    local buffsCard = builder.Card()
    local maxBuffsRow, iconSizeRow, hideSwipeRow, reverseSwipeRow, anchorRow, growDirectionRow, spacingRow, xOffsetRow, yOffsetRow
    local updateBuffDurationRows
    local UpdateFilterRows
    local function UpdateBuffRows()
        local showBuffs = auras.showBuffs == true
        local showAlpha = showBuffs and 1.0 or 0.4
        if maxBuffsRow then maxBuffsRow:SetAlpha(showAlpha) end
        if iconSizeRow then iconSizeRow:SetAlpha(showAlpha) end
        if hideSwipeRow then hideSwipeRow:SetAlpha(showAlpha) end
        if reverseSwipeRow then
            reverseSwipeRow:SetAlpha((showBuffs and not auras.buffHideSwipe) and 1.0 or 0.4)
        end
        if anchorRow then anchorRow:SetAlpha(showAlpha) end
        if growDirectionRow then growDirectionRow:SetAlpha(showAlpha) end
        if spacingRow then spacingRow:SetAlpha(showAlpha) end
        if xOffsetRow then xOffsetRow:SetAlpha(showAlpha) end
        if yOffsetRow then yOffsetRow:SetAlpha(showAlpha) end
        if updateBuffDurationRows then updateBuffDurationRows() end
    end

    local showBuffsCheckbox = gui:CreateFormCheckbox(buffsCard.frame, nil, "showBuffs", auras, function()
        refresh()
        UpdateBuffRows()
        if UpdateFilterRows then
            UpdateFilterRows()
        end
    end, {
        description = "Show buff icons on this unit frame.",
    })
    local maxBuffsSlider = gui:CreateFormSlider(buffsCard.frame, nil, 0, 8, 1, "maxBuffs", auras, refresh, { deferOnDrag = true }, {
        description = "Hard cap on how many buff icons this frame displays at once.",
    })
    maxBuffsRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Max Buffs", maxBuffsSlider)
    buffsCard.AddRow(
        optionsAPI.BuildSettingRow(buffsCard.frame, "Show Buffs", showBuffsCheckbox),
        maxBuffsRow
    )

    local iconSizeSlider = gui:CreateFormSlider(buffsCard.frame, nil, 8, 32, 1, "buffIconSize", auras, refresh, { deferOnDrag = true }, {
        description = "Pixel size of each buff icon.",
    })
    iconSizeRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Icon Size", iconSizeSlider)
    local hideSwipeCheckbox = gui:CreateFormCheckbox(buffsCard.frame, nil, "buffHideSwipe", auras, function()
        refresh()
        UpdateBuffRows()
    end, {
        description = "Hide the cooldown swipe animation drawn over buff icons.",
    })
    hideSwipeRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Hide Duration Swipe", hideSwipeCheckbox)
    buffsCard.AddRow(iconSizeRow, hideSwipeRow)

    updateBuffDurationRows = AddAuraDurationTextRows(
        buffsCard,
        gui,
        optionsAPI,
        auras,
        "buff",
        "Buff",
        refresh,
        function() return auras.showBuffs == true end
    )

    local reverseSwipeCheckbox = gui:CreateFormCheckbox(buffsCard.frame, nil, "buffReverseSwipe", auras, refresh, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as time passes.",
    })
    reverseSwipeRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Reverse Swipe", reverseSwipeCheckbox)
    local anchorDropdown = gui:CreateFormDropdown(buffsCard.frame, nil, NINE_POINT_OPTIONS, "buffAnchor", auras, refresh, {
        description = "Which corner of the frame the first buff icon is anchored to.",
    })
    anchorRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Anchor", anchorDropdown)
    buffsCard.AddRow(reverseSwipeRow, anchorRow)

    local growDirectionDropdown = gui:CreateFormDropdown(buffsCard.frame, nil, AURA_GROW_OPTIONS, "buffGrowDirection", auras, refresh, {
        description = "Direction additional buff icons are added in after the first.",
    })
    growDirectionRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Grow Direction", growDirectionDropdown)
    local spacingSlider = gui:CreateFormSlider(buffsCard.frame, nil, 0, 8, 1, "buffSpacing", auras, refresh, { deferOnDrag = true }, {
        description = "Pixel gap between adjacent buff icons.",
    })
    spacingRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Spacing", spacingSlider)
    buffsCard.AddRow(growDirectionRow, spacingRow)

    local xOffsetSlider = gui:CreateFormSlider(buffsCard.frame, nil, -100, 100, 1, "buffOffsetX", auras, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the buff block from its anchor corner.",
    })
    xOffsetRow = optionsAPI.BuildSettingRow(buffsCard.frame, "X Offset", xOffsetSlider)
    local yOffsetSlider = gui:CreateFormSlider(buffsCard.frame, nil, -100, 100, 1, "buffOffsetY", auras, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the buff block from its anchor corner.",
    })
    yOffsetRow = optionsAPI.BuildSettingRow(buffsCard.frame, "Y Offset", yOffsetSlider)
    buffsCard.AddRow(xOffsetRow, yOffsetRow)

    UpdateBuffRows()
    builder.CloseCard(buffsCard)

    builder.Spacer(6)
    builder.Header("Buff Filtering")
    local filterCard = builder.Card()
    local filterModeRow, onlyMineRow, hidePermanentRow, dedupeRow, raidRow, raidInCombatRow, cancelableRow, notCancelableRow, importantRow, bigDefensiveRow, externalDefensiveRow
    UpdateFilterRows = function()
        local showBuffs = auras.showBuffs == true
        local showAlpha = showBuffs and 1.0 or 0.4
        local classificationAlpha = (showBuffs and (auras.filterMode or "off") == "classification") and 1.0 or 0.4
        if filterModeRow then filterModeRow:SetAlpha(showAlpha) end
        if onlyMineRow then onlyMineRow:SetAlpha(showAlpha) end
        if hidePermanentRow then hidePermanentRow:SetAlpha(showAlpha) end
        if dedupeRow then dedupeRow:SetAlpha(showAlpha) end
        if raidRow then raidRow:SetAlpha(classificationAlpha) end
        if raidInCombatRow then raidInCombatRow:SetAlpha(classificationAlpha) end
        if cancelableRow then cancelableRow:SetAlpha(classificationAlpha) end
        if notCancelableRow then notCancelableRow:SetAlpha(classificationAlpha) end
        if importantRow then importantRow:SetAlpha(classificationAlpha) end
        if bigDefensiveRow then bigDefensiveRow:SetAlpha(classificationAlpha) end
        if externalDefensiveRow then externalDefensiveRow:SetAlpha(classificationAlpha) end
    end

    local filterModeDropdown = gui:CreateFormDropdown(filterCard.frame, nil, FILTER_MODE_OPTIONS, "filterMode", auras, function()
        refresh()
        UpdateFilterRows()
    end, {
        description = "Choose how buffs are filtered: off shows everything and classification only shows the categories selected below.",
    })
    filterModeRow = optionsAPI.BuildSettingRow(filterCard.frame, "Filter Mode", filterModeDropdown)
    local onlyMineCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "buffFilterOnlyMine", auras, refresh, {
        description = "Only show buffs cast by you.",
    })
    onlyMineRow = optionsAPI.BuildSettingRow(filterCard.frame, "Only My Buffs", onlyMineCheckbox)
    filterCard.AddRow(filterModeRow, onlyMineRow)

    local hidePermanentCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "buffHidePermanent", auras, refresh, {
        description = "Hide buffs with no remaining duration.",
    })
    hidePermanentRow = optionsAPI.BuildSettingRow(filterCard.frame, "Hide Permanent Buffs", hidePermanentCheckbox)
    local dedupeCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "buffDeduplicateDefensives", auras, refresh, {
        description = "Hide buff icons that are already shown by the defensive indicator or an aura indicator.",
    })
    dedupeRow = optionsAPI.BuildSettingRow(filterCard.frame, "Deduplicate Defensives/Indicators", dedupeCheckbox)
    filterCard.AddRow(hidePermanentRow, dedupeRow)

    local raidCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "raid", buffClassifications, refresh, {
        description = "Include buffs flagged by Blizzard as raid-relevant.",
    })
    raidRow = optionsAPI.BuildSettingRow(filterCard.frame, "Raid", raidCheckbox)
    local raidInCombatCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "raidInCombat", buffClassifications, refresh, {
        description = "Include buffs flagged as raid-relevant only while in combat.",
    })
    raidInCombatRow = optionsAPI.BuildSettingRow(filterCard.frame, "Raid (In Combat)", raidInCombatCheckbox)
    filterCard.AddRow(raidRow, raidInCombatRow)

    local cancelableCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "cancelable", buffClassifications, refresh, {
        description = "Include buffs you can right-click to cancel.",
    })
    cancelableRow = optionsAPI.BuildSettingRow(filterCard.frame, "Cancelable", cancelableCheckbox)
    local notCancelableCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "notCancelable", buffClassifications, refresh, {
        description = "Include buffs you cannot right-click to cancel, such as many external or NPC-applied buffs.",
    })
    notCancelableRow = optionsAPI.BuildSettingRow(filterCard.frame, "Not Cancelable", notCancelableCheckbox)
    filterCard.AddRow(cancelableRow, notCancelableRow)

    local importantCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "important", buffClassifications, refresh, {
        description = "Include buffs flagged by Blizzard as important.",
    })
    importantRow = optionsAPI.BuildSettingRow(filterCard.frame, "Important", importantCheckbox)
    local bigDefensiveCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "bigDefensive", buffClassifications, refresh, {
        description = "Include major personal defensive buffs such as immunities and high-impact mitigation.",
    })
    bigDefensiveRow = optionsAPI.BuildSettingRow(filterCard.frame, "Big Defensive", bigDefensiveCheckbox)
    filterCard.AddRow(importantRow, bigDefensiveRow)

    local externalDefensiveCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "externalDefensive", buffClassifications, refresh, {
        description = "Include externally-applied defensive buffs such as Pain Suppression or Ironbark.",
    })
    externalDefensiveRow = optionsAPI.BuildSettingRow(filterCard.frame, "External Defensive", externalDefensiveCheckbox)
    filterCard.AddRow(externalDefensiveRow)

    UpdateFilterRows()
    builder.CloseCard(filterCard)

    AppendSpellListBlock(
        sectionHost,
        builder,
        ctx,
        "Buff Blacklist",
        "Blacklisted buffs are always hidden regardless of filter mode.",
        buffBlacklist,
        SpellList.GetBuffBlacklistPresets and SpellList.GetBuffBlacklistPresets() or nil,
        refresh
    )

    return builder.Height()
end

local function RenderDebuffsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local auras = EnsureSubTable(groupFrames.contextDB, "auras")
    if not auras then
        return nil
    end
    local debuffClassifications = EnsureSubTable(auras, "debuffClassifications")
    local debuffBlacklist = EnsureSubTable(auras, "debuffBlacklist")
    if not debuffClassifications or not debuffBlacklist then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("debuffs"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Debuffs")
    builder.Description("Debuff icon placement and filtering for " .. groupFrames.sourceLabel .. " group frames.")

    local debuffsCard = builder.Card()
    local maxDebuffsRow, iconSizeRow, hideSwipeRow, reverseSwipeRow, anchorRow, growDirectionRow, spacingRow, xOffsetRow, yOffsetRow
    local updateDebuffDurationRows
    local UpdateFilterRows
    local function UpdateDebuffRows()
        local showDebuffs = auras.showDebuffs == true
        local showAlpha = showDebuffs and 1.0 or 0.4
        if maxDebuffsRow then maxDebuffsRow:SetAlpha(showAlpha) end
        if iconSizeRow then iconSizeRow:SetAlpha(showAlpha) end
        if hideSwipeRow then hideSwipeRow:SetAlpha(showAlpha) end
        if reverseSwipeRow then
            reverseSwipeRow:SetAlpha((showDebuffs and not auras.debuffHideSwipe) and 1.0 or 0.4)
        end
        if anchorRow then anchorRow:SetAlpha(showAlpha) end
        if growDirectionRow then growDirectionRow:SetAlpha(showAlpha) end
        if spacingRow then spacingRow:SetAlpha(showAlpha) end
        if xOffsetRow then xOffsetRow:SetAlpha(showAlpha) end
        if yOffsetRow then yOffsetRow:SetAlpha(showAlpha) end
        if updateDebuffDurationRows then updateDebuffDurationRows() end
    end

    local showDebuffsCheckbox = gui:CreateFormCheckbox(debuffsCard.frame, nil, "showDebuffs", auras, function()
        refresh()
        UpdateDebuffRows()
        if UpdateFilterRows then
            UpdateFilterRows()
        end
    end, {
        description = "Show debuff icons on this unit frame.",
    })
    local maxDebuffsSlider = gui:CreateFormSlider(debuffsCard.frame, nil, 0, 8, 1, "maxDebuffs", auras, refresh, { deferOnDrag = true }, {
        description = "Hard cap on how many debuff icons this frame displays at once.",
    })
    maxDebuffsRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Max Debuffs", maxDebuffsSlider)
    debuffsCard.AddRow(
        optionsAPI.BuildSettingRow(debuffsCard.frame, "Show Debuffs", showDebuffsCheckbox),
        maxDebuffsRow
    )

    local iconSizeSlider = gui:CreateFormSlider(debuffsCard.frame, nil, 8, 32, 1, "debuffIconSize", auras, refresh, { deferOnDrag = true }, {
        description = "Pixel size of each debuff icon.",
    })
    iconSizeRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Icon Size", iconSizeSlider)
    local hideSwipeCheckbox = gui:CreateFormCheckbox(debuffsCard.frame, nil, "debuffHideSwipe", auras, function()
        refresh()
        UpdateDebuffRows()
    end, {
        description = "Hide the cooldown swipe animation drawn over debuff icons.",
    })
    hideSwipeRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Hide Duration Swipe", hideSwipeCheckbox)
    debuffsCard.AddRow(iconSizeRow, hideSwipeRow)

    updateDebuffDurationRows = AddAuraDurationTextRows(
        debuffsCard,
        gui,
        optionsAPI,
        auras,
        "debuff",
        "Debuff",
        refresh,
        function() return auras.showDebuffs == true end
    )

    local reverseSwipeCheckbox = gui:CreateFormCheckbox(debuffsCard.frame, nil, "debuffReverseSwipe", auras, refresh, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as time passes.",
    })
    reverseSwipeRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Reverse Swipe", reverseSwipeCheckbox)
    local anchorDropdown = gui:CreateFormDropdown(debuffsCard.frame, nil, NINE_POINT_OPTIONS, "debuffAnchor", auras, refresh, {
        description = "Which corner of the frame the first debuff icon is anchored to.",
    })
    anchorRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Anchor", anchorDropdown)
    debuffsCard.AddRow(reverseSwipeRow, anchorRow)

    local growDirectionDropdown = gui:CreateFormDropdown(debuffsCard.frame, nil, AURA_GROW_OPTIONS, "debuffGrowDirection", auras, refresh, {
        description = "Direction additional debuff icons are added in after the first.",
    })
    growDirectionRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Grow Direction", growDirectionDropdown)
    local spacingSlider = gui:CreateFormSlider(debuffsCard.frame, nil, 0, 8, 1, "debuffSpacing", auras, refresh, { deferOnDrag = true }, {
        description = "Pixel gap between adjacent debuff icons.",
    })
    spacingRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Spacing", spacingSlider)
    debuffsCard.AddRow(growDirectionRow, spacingRow)

    local xOffsetSlider = gui:CreateFormSlider(debuffsCard.frame, nil, -100, 100, 1, "debuffOffsetX", auras, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the debuff block from its anchor corner.",
    })
    xOffsetRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "X Offset", xOffsetSlider)
    local yOffsetSlider = gui:CreateFormSlider(debuffsCard.frame, nil, -100, 100, 1, "debuffOffsetY", auras, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the debuff block from its anchor corner.",
    })
    yOffsetRow = optionsAPI.BuildSettingRow(debuffsCard.frame, "Y Offset", yOffsetSlider)
    debuffsCard.AddRow(xOffsetRow, yOffsetRow)

    UpdateDebuffRows()
    builder.CloseCard(debuffsCard)

    builder.Spacer(6)
    builder.Header("Debuff Filtering")
    local filterCard = builder.Card()
    local filterModeRow, raidRow, raidInCombatRow, crowdControlRow, importantRow
    UpdateFilterRows = function()
        local showDebuffs = auras.showDebuffs == true
        local showAlpha = showDebuffs and 1.0 or 0.4
        local classificationAlpha = (showDebuffs and (auras.filterMode or "off") == "classification") and 1.0 or 0.4
        if filterModeRow then filterModeRow:SetAlpha(showAlpha) end
        if raidRow then raidRow:SetAlpha(classificationAlpha) end
        if raidInCombatRow then raidInCombatRow:SetAlpha(classificationAlpha) end
        if crowdControlRow then crowdControlRow:SetAlpha(classificationAlpha) end
        if importantRow then importantRow:SetAlpha(classificationAlpha) end
    end

    local filterModeDropdown = gui:CreateFormDropdown(filterCard.frame, nil, FILTER_MODE_OPTIONS, "filterMode", auras, function()
        refresh()
        UpdateFilterRows()
    end, {
        description = "Choose how debuffs are filtered: off shows everything and classification only shows the categories selected below.",
    })
    filterModeRow = optionsAPI.BuildSettingRow(filterCard.frame, "Filter Mode", filterModeDropdown)
    filterCard.AddRow(filterModeRow)

    local raidCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "raid", debuffClassifications, refresh, {
        description = "Include debuffs flagged by Blizzard as raid-relevant.",
    })
    raidRow = optionsAPI.BuildSettingRow(filterCard.frame, "Raid", raidCheckbox)
    local raidInCombatCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "raidInCombat", debuffClassifications, refresh, {
        description = "Include debuffs flagged as raid-relevant only while in combat.",
    })
    raidInCombatRow = optionsAPI.BuildSettingRow(filterCard.frame, "Raid (In Combat)", raidInCombatCheckbox)
    filterCard.AddRow(raidRow, raidInCombatRow)

    local crowdControlCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "crowdControl", debuffClassifications, refresh, {
        description = "Include crowd-control debuffs (stuns, fears, roots, silences, etc.).",
    })
    crowdControlRow = optionsAPI.BuildSettingRow(filterCard.frame, "Crowd Control", crowdControlCheckbox)
    local importantCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "important", debuffClassifications, refresh, {
        description = "Include debuffs flagged by Blizzard as important.",
    })
    importantRow = optionsAPI.BuildSettingRow(filterCard.frame, "Important", importantCheckbox)
    filterCard.AddRow(crowdControlRow, importantRow)

    UpdateFilterRows()
    builder.CloseCard(filterCard)

    AppendSpellListBlock(
        sectionHost,
        builder,
        ctx,
        "Debuff Blacklist",
        "Blacklisted debuffs are always hidden regardless of filter mode.",
        debuffBlacklist,
        SpellList.GetDebuffBlacklistPresets and SpellList.GetDebuffBlacklistPresets() or nil,
        refresh
    )

    return builder.Height()
end

local function RenderPinnedAurasSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end
    if not PinnedAurasEditor or type(PinnedAurasEditor.RenderSpellSlots) ~= "function" then
        return RenderUnavailableLabel(sectionHost, "Pinned aura settings unavailable.")
    end

    local pinnedAuras = EnsureSubTable(groupFrames.contextDB, "pinnedAuras")
    if not pinnedAuras then
        return nil
    end
    if type(pinnedAuras.specSlots) ~= "table" then
        pinnedAuras.specSlots = {}
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("pinnedAuras"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Pinned Auras")
    builder.Description("Per-spec aura indicators anchored to positions on " .. groupFrames.sourceLabel .. " group frames.")

    local card = builder.Card()
    local slotSizeRow, edgeInsetRow, showSwipeRow, reverseSwipeRow
    local function UpdatePinnedRows()
        local enabled = pinnedAuras.enabled == true
        if slotSizeRow then slotSizeRow:SetAlpha(enabled and 1.0 or 0.4) end
        if edgeInsetRow then edgeInsetRow:SetAlpha(enabled and 1.0 or 0.4) end
        if showSwipeRow then showSwipeRow:SetAlpha(enabled and 1.0 or 0.4) end
        if reverseSwipeRow then
            reverseSwipeRow:SetAlpha((enabled and pinnedAuras.showSwipe) and 1.0 or 0.4)
        end
    end

    local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", pinnedAuras, function()
        refresh()
        UpdatePinnedRows()
    end, {
        description = "Enable per-spec pinned aura slots on group frames.",
    })
    local slotSizeSlider = gui:CreateFormSlider(card.frame, nil, 4, 20, 1, "slotSize", pinnedAuras, refresh, { deferOnDrag = true }, {
        description = "Pixel size of each pinned aura slot.",
    })
    slotSizeRow = optionsAPI.BuildSettingRow(card.frame, "Slot Size", slotSizeSlider)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Enable Pinned Auras", enableCheckbox),
        slotSizeRow
    )

    local edgeInsetSlider = gui:CreateFormSlider(card.frame, nil, 0, 10, 1, "edgeInset", pinnedAuras, refresh, { deferOnDrag = true }, {
        description = "Pixel inset from the frame edge when placing pinned aura slots.",
    })
    edgeInsetRow = optionsAPI.BuildSettingRow(card.frame, "Edge Inset", edgeInsetSlider)
    local showSwipeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showSwipe", pinnedAuras, function()
        refresh()
        UpdatePinnedRows()
    end, {
        description = "Show the cooldown swipe animation over pinned aura slots.",
    })
    showSwipeRow = optionsAPI.BuildSettingRow(card.frame, "Show Cooldown Swipe", showSwipeCheckbox)
    card.AddRow(edgeInsetRow, showSwipeRow)

    local reverseSwipeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "reverseSwipe", pinnedAuras, refresh, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the aura ticks down.",
    })
    reverseSwipeRow = optionsAPI.BuildSettingRow(card.frame, "Reverse Swipe", reverseSwipeCheckbox)
    card.AddRow(reverseSwipeRow)

    UpdatePinnedRows()
    builder.CloseCard(card)

    builder.Spacer(6)
    builder.Header("Spell Slots")
    builder.Description("Add spec-specific pinned spells and assign each one a dedicated anchor.")

    RenderEmbeddedEditorSection(sectionHost, builder, function(editorHost)
        return PinnedAurasEditor.RenderSpellSlots(editorHost, pinnedAuras, function()
            refresh()
            ScheduleTabRepaint(ctx)
        end)
    end, {
        minHeight = 1,
    })

    return builder.Height()
end

local function RenderAuraIndicatorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end
    if not AuraIndicatorsEditor or type(AuraIndicatorsEditor.RenderTrackedAuras) ~= "function" then
        return RenderUnavailableLabel(sectionHost, "Aura indicator settings unavailable.")
    end

    local auraIndicators = EnsureSubTable(groupFrames.contextDB, "auraIndicators")
    if not auraIndicators then
        return nil
    end
    local normalizeAuraIndicators = ns.Helpers and ns.Helpers.NormalizeAuraIndicatorConfig
    if normalizeAuraIndicators then
        normalizeAuraIndicators(auraIndicators)
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("auraIndicators"))
    if not builder then
        return nil
    end

    local refresh = function()
        if normalizeAuraIndicators then
            normalizeAuraIndicators(auraIndicators)
        end
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header("Aura Indicators")
    builder.Description("Track specific buffs and debuffs on " .. groupFrames.sourceLabel .. " group frames as icons, bars, or health-bar tints.")

    local defaultsCard = builder.Card()
    local iconSizeRow, maxIndicatorsRow, hideSwipeRow, reverseSwipeRow, anchorRow, growDirectionRow, spacingRow, xOffsetRow, yOffsetRow
    local function UpdateDefaultRows()
        local enabled = auraIndicators.enabled == true
        local alpha = enabled and 1.0 or 0.4
        if iconSizeRow then iconSizeRow:SetAlpha(alpha) end
        if maxIndicatorsRow then maxIndicatorsRow:SetAlpha(alpha) end
        if hideSwipeRow then hideSwipeRow:SetAlpha(alpha) end
        if reverseSwipeRow then
            reverseSwipeRow:SetAlpha((enabled and not auraIndicators.hideSwipe) and 1.0 or 0.4)
        end
        if anchorRow then anchorRow:SetAlpha(alpha) end
        if growDirectionRow then growDirectionRow:SetAlpha(alpha) end
        if spacingRow then spacingRow:SetAlpha(alpha) end
        if xOffsetRow then xOffsetRow:SetAlpha(alpha) end
        if yOffsetRow then yOffsetRow:SetAlpha(alpha) end
    end

    local enableCheckbox = gui:CreateFormCheckbox(defaultsCard.frame, nil, "enabled", auraIndicators, function()
        refresh()
        UpdateDefaultRows()
    end, {
        description = "Track specific buffs/debuffs and display them as icons, bars, or health-bar tints on this frame.",
    })
    local iconSizeSlider = gui:CreateFormSlider(defaultsCard.frame, nil, 8, 32, 1, "iconSize", auraIndicators, refresh, { deferOnDrag = true }, {
        description = "Pixel size of each aura-indicator icon in the shared icon strip.",
    })
    iconSizeRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Icon Size", iconSizeSlider)
    defaultsCard.AddRow(
        optionsAPI.BuildSettingRow(defaultsCard.frame, "Enable Aura Indicators", enableCheckbox),
        iconSizeRow
    )

    local maxIndicatorsSlider = gui:CreateFormSlider(defaultsCard.frame, nil, 1, 10, 1, "maxIndicators", auraIndicators, refresh, { deferOnDrag = true }, {
        description = "Hard cap on how many aura-indicator icons this frame displays in the shared icon strip.",
    })
    maxIndicatorsRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Max Indicators", maxIndicatorsSlider)
    local hideSwipeCheckbox = gui:CreateFormCheckbox(defaultsCard.frame, nil, "hideSwipe", auraIndicators, function()
        refresh()
        UpdateDefaultRows()
    end, {
        description = "Hide the clockwise cooldown swipe animation drawn over aura-indicator icons.",
    })
    hideSwipeRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Hide Duration Swipe", hideSwipeCheckbox)
    defaultsCard.AddRow(maxIndicatorsRow, hideSwipeRow)

    local reverseSwipeCheckbox = gui:CreateFormCheckbox(defaultsCard.frame, nil, "reverseSwipe", auraIndicators, refresh, {
        description = "Reverse the swipe direction so the shaded portion grows instead of shrinks as the aura ticks down.",
    })
    reverseSwipeRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Reverse Swipe", reverseSwipeCheckbox)
    local anchorDropdown = gui:CreateFormDropdown(defaultsCard.frame, nil, NINE_POINT_OPTIONS, "anchor", auraIndicators, refresh, {
        description = "Where on the frame the aura-indicator icon strip is anchored.",
    })
    anchorRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Anchor", anchorDropdown)
    defaultsCard.AddRow(reverseSwipeRow, anchorRow)

    local growDirectionDropdown = gui:CreateFormDropdown(defaultsCard.frame, nil, AURA_GROW_OPTIONS, "growDirection", auraIndicators, refresh, {
        description = "Direction additional aura-indicator icons are added in after the first.",
    })
    growDirectionRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Grow Direction", growDirectionDropdown)
    local spacingSlider = gui:CreateFormSlider(defaultsCard.frame, nil, 0, 8, 1, "spacing", auraIndicators, refresh, { deferOnDrag = true }, {
        description = "Pixel gap between adjacent aura-indicator icons.",
    })
    spacingRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Spacing", spacingSlider)
    defaultsCard.AddRow(growDirectionRow, spacingRow)

    local xOffsetSlider = gui:CreateFormSlider(defaultsCard.frame, nil, -100, 100, 1, "anchorOffsetX", auraIndicators, refresh, { deferOnDrag = true }, {
        description = "Horizontal pixel offset for the aura-indicator icon strip from its anchor.",
    })
    xOffsetRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "X Offset", xOffsetSlider)
    local yOffsetSlider = gui:CreateFormSlider(defaultsCard.frame, nil, -100, 100, 1, "anchorOffsetY", auraIndicators, refresh, { deferOnDrag = true }, {
        description = "Vertical pixel offset for the aura-indicator icon strip from its anchor.",
    })
    yOffsetRow = optionsAPI.BuildSettingRow(defaultsCard.frame, "Y Offset", yOffsetSlider)
    defaultsCard.AddRow(xOffsetRow, yOffsetRow)

    UpdateDefaultRows()
    builder.CloseCard(defaultsCard)

    builder.Spacer(6)
    builder.Header("Tracked Auras")

    RenderEmbeddedEditorSection(sectionHost, builder, function(editorHost)
        return AuraIndicatorsEditor.RenderTrackedAuras(editorHost, auraIndicators, function()
            refresh()
            ScheduleTabRepaint(ctx)
        end)
    end, {
        minHeight = 1,
    })

    return builder.Height()
end

local function CreateSingleSectionTabFeature(id, sectionId, minHeight, render)
    return Schema.Feature({
        id = id,
        surfaces = {
            groupFrameTab = {
                sections = {
                    sectionId,
                },
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

local GENERAL_TAB_FEATURE = Schema.Feature({
    id = "groupFramesGeneralTab",
    surfaces = {
        groupFrameTab = {
            sections = {
                "enable",
                "copySettings",
            },
            padding = 10,
            sectionGap = 14,
            topPadding = 10,
            bottomPadding = 40,
        },
    },
    sections = {
        Schema.Section({
            id = "enable",
            kind = "custom",
            minHeight = 42,
            render = RenderGeneralEnableSection,
        }),
        Schema.Section({
            id = "copySettings",
            kind = "custom",
            minHeight = 88,
            render = RenderGeneralCopySettingsSection,
        }),
    },
})

local APPEARANCE_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesAppearanceTab",
    "appearance",
    160,
    RenderAppearanceSection
)

local LAYOUT_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesLayoutTab",
    "layout",
    160,
    RenderLayoutSection
)

local DIMENSIONS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesDimensionsTab",
    "dimensions",
    140,
    RenderDimensionsSection
)

local RANGEPET_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesRangePetTab",
    "rangepet",
    140,
    RenderRangePetSection
)

local SPOTLIGHT_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesSpotlightTab",
    "spotlight",
    180,
    RenderSpotlightSection
)

local HEALTH_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesHealthTab",
    "health",
    140,
    RenderHealthSection
)

local POWER_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesPowerTab",
    "power",
    140,
    RenderPowerSection
)

local NAME_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesNameTab",
    "name",
    140,
    RenderNameSection
)

local BUFFS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesBuffsTab",
    "buffs",
    140,
    RenderBuffsSection
)

local DEBUFFS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesDebuffsTab",
    "debuffs",
    140,
    RenderDebuffsSection
)

local INDICATORS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesIndicatorsTab",
    "indicators",
    140,
    RenderIndicatorsSection
)

local AURA_INDICATORS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesAuraIndicatorsTab",
    "auraIndicators",
    140,
    RenderAuraIndicatorsSection
)

local PINNED_AURAS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesPinnedAurasTab",
    "pinnedAuras",
    140,
    RenderPinnedAurasSection
)

local PRIVATE_AURAS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesPrivateAurasTab",
    "privateAuras",
    140,
    RenderPrivateAurasSection
)

local HEALER_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesHealerTab",
    "healer",
    140,
    RenderHealerSection
)

local DEFENSIVE_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesDefensiveTab",
    "defensive",
    140,
    RenderDefensiveSection
)

local function RenderFeatureTab(feature, host, contextMode)
    if not host then
        return false
    end

    local groupFrames = ResolveGroupFramesDB(contextMode)
    if not groupFrames then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(feature, host, {
        surface = "groupFrameTab",
        width = width,
        contextMode = groupFrames.contextMode,
    })
end

function GroupFramesSchema.RenderGeneralTab(host, contextMode)
    return RenderFeatureTab(GENERAL_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderAppearanceTab(host, contextMode)
    return RenderFeatureTab(APPEARANCE_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderLayoutTab(host, contextMode)
    return RenderFeatureTab(LAYOUT_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderDimensionsTab(host, contextMode)
    return RenderFeatureTab(DIMENSIONS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderRangePetTab(host, contextMode)
    return RenderFeatureTab(RANGEPET_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderSpotlightTab(host, contextMode)
    return RenderFeatureTab(SPOTLIGHT_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderHealthTab(host, contextMode)
    return RenderFeatureTab(HEALTH_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderPowerTab(host, contextMode)
    return RenderFeatureTab(POWER_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderNameTab(host, contextMode)
    return RenderFeatureTab(NAME_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderBuffsTab(host, contextMode)
    return RenderFeatureTab(BUFFS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderDebuffsTab(host, contextMode)
    return RenderFeatureTab(DEBUFFS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderIndicatorsTab(host, contextMode)
    return RenderFeatureTab(INDICATORS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderAuraIndicatorsTab(host, contextMode)
    return RenderFeatureTab(AURA_INDICATORS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderPinnedAurasTab(host, contextMode)
    return RenderFeatureTab(PINNED_AURAS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderPrivateAurasTab(host, contextMode)
    return RenderFeatureTab(PRIVATE_AURAS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderHealerTab(host, contextMode)
    return RenderFeatureTab(HEALER_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderDefensiveTab(host, contextMode)
    return RenderFeatureTab(DEFENSIVE_TAB_FEATURE, host, contextMode)
end
