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
local AurasEditor = ns.QUI_AuraElementsEditor
local AuraModel = ns.QUI_GroupFramesAuraModel
local AuraDefaults = ns.QUI_GroupFramesAuraDefaults

local GroupFramesSchema = ns.QUI_GroupFramesSettingsSchema or {}
ns.QUI_GroupFramesSettingsSchema = GroupFramesSchema

local FORM_ROW = 32
local HEADER_GAP = 26
local SECTION_BOTTOM_PAD = 10
local DESCRIPTION_TEXT_COLOR = { 0.5, 0.5, 0.5, 1 }
local LAYOUT_OPTIONS = {
    { value = "VERTICAL", text = ns.L["Vertical (columns)"] },
    { value = "HORIZONTAL", text = ns.L["Horizontal (rows)"] },
}
local SORT_OPTIONS = {
    { value = "INDEX", text = ns.L["Group Index"] },
    { value = "NAME", text = ns.L["Name"] },
}
local GROUP_BY_OPTIONS = {
    { value = "GROUP", text = ns.L["Group Number"] },
    { value = "ROLE", text = ns.L["Role"] },
    { value = "CLASS", text = ns.L["Class"] },
    { value = "NONE", text = ns.L["None (Flat List)"] },
}
local ANCHOR_SIDE_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "RIGHT", text = ns.L["Right"] },
}
local PET_ANCHOR_OPTIONS = {
    { value = "BOTTOM", text = ns.L["Below Group"] },
    { value = "RIGHT", text = ns.L["Right of Group"] },
    { value = "LEFT", text = ns.L["Left of Group"] },
}
local TARGET_FRAME_ANCHOR_OPTIONS = {
    { value = "BOTTOM", text = ns.L["Below Member"] },
    { value = "TOP", text = ns.L["Above Member"] },
    { value = "RIGHT", text = ns.L["Right of Member"] },
    { value = "LEFT", text = ns.L["Left of Member"] },
}
local SPOTLIGHT_FILTER_OPTIONS = {
    { value = "ROLE", text = ns.L["By Role"] },
    { value = "NAME", text = ns.L["By Name"] },
}
local HEALTH_DISPLAY_OPTIONS = {
    { value = "percent", text = ns.L["Percentage"] },
    { value = "absolute", text = ns.L["Absolute"] },
    { value = "both", text = ns.L["Both"] },
    { value = "deficit", text = ns.L["Deficit"] },
}
local HEALTH_FILL_OPTIONS = {
    { value = "HORIZONTAL", text = ns.L["Horizontal (Left to Right)"] },
    { value = "VERTICAL", text = ns.L["Vertical (Bottom to Top)"] },
}
local NINE_POINT_OPTIONS = ns.QUI_SettingsLayoutShared.BuildNinePointAnchorOptions()
local DISPEL_SCOPE_OPTIONS = {
    { value = "PLAYER_DISPELLABLE", text = ns.L["Dispellable by Me"] },
    { value = "ALL_TYPED", text = ns.L["All Typed Debuffs"] },
}
local TEXT_JUSTIFY_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "CENTER", text = ns.L["Center"] },
    { value = "RIGHT", text = ns.L["Right"] },
}
local AURA_GROW_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "RIGHT", text = ns.L["Right"] },
    { value = "CENTER", text = ns.L["Center"] },
    { value = "UP", text = ns.L["Up"] },
    { value = "DOWN", text = ns.L["Down"] },
}
local FILTER_MODE_OPTIONS = {
    { value = "off", text = ns.L["Off (Show All)"] },
    { value = "classification", text = ns.L["Classification"] },
}
local TAB_SEARCH_CONTEXTS = {
    general = { subTabIndex = 1, subTabName = "General" },
    appearance = { subTabIndex = 2, subTabName = "Appearance" },
    layout = { subTabIndex = 3, subTabName = "Layout" },
    health = { subTabIndex = 4, subTabName = "Health" },
    indicators = { subTabIndex = 5, subTabName = "Indicators" },
    auras = { subTabIndex = 6, subTabName = "Auras" },
}
local GROUP_FRAMES_SEARCH_TILE_ID = "group_frames"
local GROUP_FRAMES_SEARCH_FEATURE_ID = "groupFramesPage"
local GROUP_FRAMES_SEARCH_SUB_PAGE_INDEX = 2
local VISUAL_DB_KEYS = {
    general = true, layout = true, health = true, power = true, name = true,
    absorbs = true, healAbsorbs = true, healPrediction = true, indicators = true,
    healer = true, classPower = true, range = true, auras = true,
    auraIndicators = true, castbar = true,
    targetedSpells = true,
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

local function GetSearchProviderKey(contextMode)
    return NormalizeContextMode(contextMode) == "raid" and "raidFrames" or "partyFrames"
end

local function GetRenderContextMode(ctx)
    return ctx and ((ctx.options and ctx.options.contextMode) or ctx.contextMode) or nil
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
        sourceLabel = contextMode == "raid" and ns.L["Raid"] or ns.L["Party"],
        targetMode = contextMode == "raid" and "party" or "raid",
        targetLabel = contextMode == "raid" and ns.L["Party"] or ns.L["Raid"],
    }
end

local function SetSearchContext(searchContext)
    local gui = GetGUI()
    if gui and type(gui.SetSearchContext) == "function" and type(searchContext) == "table" then
        gui:SetSearchContext(searchContext)
    end
end

local function CreateSearchContext(tabKey, contextMode)
    local context = TAB_SEARCH_CONTEXTS[tabKey] or TAB_SEARCH_CONTEXTS.general
    local SearchRoute = ns.Settings and ns.Settings.SearchRoute
    local searchContext = {
        tabIndex = 6,
        tabName = "Group Frames",
        subTabIndex = context.subTabIndex,
        subTabName = context.subTabName,
        tileId = GROUP_FRAMES_SEARCH_TILE_ID,
        subPageIndex = GROUP_FRAMES_SEARCH_SUB_PAGE_INDEX,
        featureId = GROUP_FRAMES_SEARCH_FEATURE_ID,
        providerKey = GetSearchProviderKey(contextMode),
        category = "frames",
        surfaceTabKey = tabKey,
    }
    if SearchRoute and type(SearchRoute.Apply) == "function" then
        return SearchRoute.Apply(searchContext)
    end
    return searchContext
end

local DeepCopy = ns.Helpers.DeepCopy

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
    if type(searchContext) == "table" then
        searchContext.providerKey = GetSearchProviderKey(GetRenderContextMode(ctx))
    end
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
    table.insert(fonts, 1, { value = "", text = ns.L["(Frame Font)"] })
    return fonts
end

local function RequestTabRepaint(ctx)
    if type(ctx) ~= "table" then
        return
    end
    local repaint = ctx.state and ctx.state.repaintTabs or nil
    if type(repaint) == "function" then
        repaint()
        return
    end
    if type(ctx.RerenderFeature) == "function" then
        ctx:RerenderFeature()
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

    SetSearchContext(CreateSearchContext("general", groupFrames.contextMode))

    local enableCheck = gui:CreateFormCheckbox(
        sectionHost,
        ns.L["Enable QUI Group Frames (Req. Reload)"],
        "enabled",
        groupFrames.gfdb,
        function(enabled)
            if ns.QUI_Modules and type(ns.QUI_Modules.SetEnabled) == "function" then
                ns.QUI_Modules:SetEnabled("moduleAddon_QUI_GroupFrames", enabled, {
                    suppressReloadPrompt = true,
                })
            end
            RefreshGroupFrames(groupFrames.contextMode)
            gui:ShowConfirmation({
                title = ns.L["Reload UI?"],
                message = ns.L["Changing the QUI Group Frames enabled state requires a UI reload to take full effect."],
                acceptText = ns.L["Reload"],
                cancelText = ns.L["Later"],
                onAccept = function()
                    QUI:SafeReload()
                end,
            })
        end,
        { description = ns.L["Replace Blizzard's party and raid frames with QUI group frames. Requires a UI reload to take effect."] }
    )
    enableCheck:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -4)
    enableCheck:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -4)

    local externalSkinCheck = gui:CreateFormCheckbox(
        sectionHost,
        "External Skinning",
        "externalSkinning",
        groupFrames.gfdb,
        function()
            RefreshGroupFrames(groupFrames.contextMode)
        end,
        { description = "When an external button-skinning addon is installed, let it skin group-frame aura icons instead of QUI's own border." }
    )
    externalSkinCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -8)
    externalSkinCheck:SetPoint("TOPRIGHT", enableCheck, "BOTTOMRIGHT", 0, -8)

    local skinOptions = {}
    if ns.IconSkin and ns.IconSkin.GetSkinList then
        for _, name in ipairs(ns.IconSkin.GetSkinList()) do
            skinOptions[#skinOptions + 1] = { value = name, text = name }
        end
    end
    if #skinOptions == 0 then skinOptions = { { value = "Default", text = "Default" } } end

    local iconSkinDropdown = gui:CreateFormDropdown(
        sectionHost,
        "Button Skin",
        skinOptions,
        "iconSkin",
        groupFrames.gfdb,
        function()
            RefreshGroupFrames(groupFrames.contextMode)
        end,
        { description = "In-house skin preset (gloss + backdrop) for group-frame aura icons. Default keeps QUI's original look." }
    )
    iconSkinDropdown:SetPoint("TOPLEFT", externalSkinCheck, "BOTTOMLEFT", 0, -12)
    iconSkinDropdown:SetPoint("TOPRIGHT", externalSkinCheck, "BOTTOMRIGHT", 0, -12)

    return 142
end

local function RenderGeneralCopySettingsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    SetSearchContext(CreateSearchContext("general", groupFrames.contextMode))

    local header = optionsAPI.CreateAccentDotLabel(sectionHost, ns.L["Copy Settings"], 0)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, 0)

    local description = gui:CreateLabel(
        sectionHost,
        string.format(ns.L["Copy all %1$s visual settings into %2$s."], groupFrames.sourceLabel, groupFrames.targetLabel),
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

    local function RefreshCopiedSettings()
        local surface = ns.QUI_GroupFramesSettingsSurface
        if surface and type(surface.InvalidateTabBodies) == "function" then
            surface.InvalidateTabBodies()
        end

        RefreshGroupFrames(groupFrames.contextMode)
        NotifyProvider("partyFrames", true)
        NotifyProvider("raidFrames", true)
    end

    local copyButton = gui:CreateButton(
        sectionHost,
        string.format(ns.L["Copy All: %1$s -> %2$s"], groupFrames.sourceLabel, groupFrames.targetLabel),
        220,
        28,
        function()
            gui:ShowConfirmation({
                title = ns.L["Copy All Settings"],
                message = string.format(ns.L["This will overwrite ALL %1$s visual settings with %2$s settings. Continue?"], groupFrames.targetLabel, groupFrames.sourceLabel),
                acceptText = ns.L["Copy All"],
                cancelText = ns.L["Cancel"],
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
                    if groupFrames.targetMode == "raid" and type(dst.name) == "table" then
                        dst.name.showLevel = false
                    end

                    RefreshCopiedSettings()
                end,
            })
        end
    )
    copyButton:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -(HEADER_GAP + descHeight + 10))

    local height = HEADER_GAP + descHeight + 10 + 28
    local profileCopy = ns.QUI_ProfileCopyOptions
    if profileCopy
        and type(profileCopy.CreateCard) == "function"
        and type(profileCopy.HasSourceProfile) == "function"
        and profileCopy.HasSourceProfile()
    then
        local controller = profileCopy.CreateCard(sectionHost, {
            yOffset = -(height + 12),
            fixedCategoryID = "groupFrames",
            fixedCategoryLabel = ns.L["Group / Raid Frames"],
            onCopied = RefreshCopiedSettings,
        })
        height = height + 12 + controller.frame:GetHeight()
    end

    return height + 8
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

    builder.Header(ns.L["Appearance"])
    builder.Description(string.format(ns.L["Colors, fonts, and portrait styling for %1$s group frames."], groupFrames.sourceLabel))

    local card = builder.Card()
    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end
    local portraitSideCell
    local portraitSizeCell

    local borderSizeSlider = gui:CreateFormSlider(card.frame, nil, 0, 3, 1, "borderSize", general, refresh, { deferOnDrag = true }, {
        description = ns.L["Border thickness in pixels around each group frame. Set to 0 to hide borders."],
    })
    local textureDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.GetTextureList(), "texture", general, refresh, {
        description = ns.L["Health bar texture used for all frames in this group. Supports SharedMedia textures."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Border Size"], borderSizeSlider),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Texture"], textureDropdown)
    )

    local healthColorRow
    local function UpdateHealthColorRow()
        if healthColorRow then
            local active = general.darkMode ~= true and general.useClassColor == false
            healthColorRow:SetAlpha(active and 1.0 or 0.4)
        end
    end
    local darkModeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "darkMode", general, function()
        refresh()
        UpdateHealthColorRow()
    end, {
        description = ns.L["Invert the frames so missing health is dark and remaining health is colored."],
    })
    local classColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "useClassColor", general, function()
        refresh()
        UpdateHealthColorRow()
    end, {
        description = ns.L["Color the health bar by class instead of the Health Color swatch below."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Dark Mode"], darkModeCheckbox),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Use Class Color"], classColorCheckbox)
    )

    local healthColorPicker = gui:CreateFormColorPicker(card.frame, nil, "healthBarColor", general, refresh, nil, {
        description = ns.L["Health bar fill color used when Use Class Color and Dark Mode are both off."],
    })
    healthColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Health Color"], healthColorPicker)
    card.AddRow(healthColorRow)
    UpdateHealthColorRow()

    local bgColorPicker = gui:CreateFormColorPicker(card.frame, nil, "defaultBgColor", general, refresh, nil, {
        description = ns.L["Backdrop color behind the health fill when Dark Mode is off."],
    })
    local bgOpacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "defaultBgOpacity", general, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = ns.L["Opacity of the default frame background."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Background Color"], bgColorPicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Background Opacity"], bgOpacitySlider)
    )

    local darkHealthColorPicker = gui:CreateFormColorPicker(card.frame, nil, "darkModeHealthColor", general, refresh, nil, {
        description = ns.L["Remaining-health fill color when Dark Mode is on."],
    })
    local darkHealthOpacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "darkModeHealthOpacity", general, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = ns.L["Opacity of the remaining-health fill in Dark Mode."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Dark Mode Health Color"], darkHealthColorPicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Dark Mode Health Opacity"], darkHealthOpacitySlider)
    )

    local darkBgColorPicker = gui:CreateFormColorPicker(card.frame, nil, "darkModeBgColor", general, refresh, nil, {
        description = ns.L["Backdrop color shown behind the health fill in Dark Mode."],
    })
    local darkBgOpacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "darkModeBgOpacity", general, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = ns.L["Opacity of the Dark Mode backdrop color."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Dark Mode BG Color"], darkBgColorPicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Dark Mode BG Opacity"], darkBgOpacitySlider)
    )

    local fontDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.GetFontList(), "font", general, refresh, {
        description = ns.L["Font used for names, health text, and indicators."],
    })
    local fontSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 20, 1, "fontSize", general, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size used for group-frame text."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Font"], fontDropdown),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Font Size"], fontSizeSlider)
    )

    local showTooltipsCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showTooltips", general, refresh, {
        description = ns.L["Show the Blizzard unit tooltip when hovering a group frame."],
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
        description = ns.L["Show a portrait next to each frame."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Tooltips on Hover"], showTooltipsCheckbox),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Portrait"], showPortraitCheckbox)
    )

    local portraitSideDropdown = gui:CreateFormDropdown(card.frame, nil, ANCHOR_SIDE_OPTIONS, "portraitSide", portrait, refresh, {
        description = ns.L["Which side of the frame the portrait sits on."],
    })
    portraitSideCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Portrait Side"], portraitSideDropdown)
    local portraitSizeSlider = gui:CreateFormSlider(card.frame, nil, 16, 60, 1, "portraitSize", portrait, refresh, { deferOnDrag = true }, {
        description = ns.L["Portrait width and height in pixels."],
    })
    portraitSizeCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Portrait Size"], portraitSizeSlider)
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

        builder.Header(ns.L["Preview Size"])
        builder.Description(ns.L["Controls how many placeholder raid members the preview renders."])

        local previewCard = builder.Card()
        local previewSlider = gui:CreateFormSlider(previewCard.frame, nil, 5, 40, 5, "raidCount", groupFrames.gfdb.testMode, function()
            local Drv = ns.QUI_GroupFramesPreview
            if Drv and Drv._SnapRaidCount and groupFrames.gfdb.testMode then
                groupFrames.gfdb.testMode.raidCount = Drv._SnapRaidCount(groupFrames.gfdb.testMode.raidCount)
            end
            local editMode = ns.QUI_GroupFrameEditMode
            if editMode and editMode.IsTestMode and editMode:IsTestMode() and editMode.RefreshTestMode then
                editMode:RefreshTestMode()
            end
            if _G.QUI_LayoutModeSyncHandle then
                _G.QUI_LayoutModeSyncHandle("raidFrames")
            end
        end, { deferOnDrag = true }, {
            description = ns.L["How many placeholder raid members the test preview renders."],
        })
        previewCard.AddRow(optionsAPI.BuildSettingRow(previewCard.frame, ns.L["Raid Preview Size"], previewSlider))
        builder.CloseCard(previewCard)
        builder.Spacer(10)
    end

    builder.Header(ns.L["Layout"])
    builder.Description(string.format(ns.L["Arrange the %1$s frames and choose how members are grouped."], groupFrames.sourceLabel))

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
        description = ns.L["Orient frames vertically (columns) or horizontally (rows)."],
    })
    local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 10, 1, "spacing", layout, refresh, { deferOnDrag = true }, {
        description = ns.L["Pixel gap between frames inside the same group."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Layout"], orientationDropdown),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Frame Spacing"], spacingSlider)
    )

    if groupFrames.contextMode == "raid" then
        local groupBy = layout.groupBy or "GROUP"
        local groupByDropdown = gui:CreateFormDropdown(card.frame, nil, GROUP_BY_OPTIONS, "groupBy", layout, function()
            refresh(true)
            RequestTabRepaint(ctx)
        end, {
            description = ns.L["How raid members are split into groups before sorting."],
        })
        if gui.SetWidgetProviderSyncOptions then
            gui:SetWidgetProviderSyncOptions(groupByDropdown, { auto = true, structural = true })
        end

        if groupBy ~= "NONE" then
            local groupSpacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 30, 1, "groupSpacing", layout, refresh, { deferOnDrag = true }, {
                description = ns.L["Pixel gap between groups when Group By is not None."],
            })
            card.AddRow(
                optionsAPI.BuildSettingRow(card.frame, ns.L["Group By"], groupByDropdown),
                optionsAPI.BuildSettingRow(card.frame, ns.L["Group Spacing"], groupSpacingSlider)
            )
        else
            local unitsPerColumnSlider = gui:CreateFormSlider(card.frame, nil, 1, 40, 1, "unitsPerFlat", layout, refresh, { deferOnDrag = true }, {
                description = ns.L["How many units fit in a single column or row before wrapping."],
            })
            card.AddRow(
                optionsAPI.BuildSettingRow(card.frame, ns.L["Group By"], groupByDropdown),
                optionsAPI.BuildSettingRow(card.frame, ns.L["Units Per Column"], unitsPerColumnSlider)
            )
        end

        local sortMethodDropdown = gui:CreateFormDropdown(card.frame, nil, SORT_OPTIONS, "sortMethod", layout, refresh, {
            description = ns.L["Sort units by Blizzard group index or alphabetically by name."],
        })
        local selfFirstCheckbox = gui:CreateFormCheckbox(card.frame, nil, "raidSelfFirst", groupFrames.gfdb, refresh, {
            description = ns.L["Pin your own frame to the first slot regardless of the sort order."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Sort Method"], sortMethodDropdown),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Always Show Self First"], selfFirstCheckbox)
        )

        local sortByRoleCheckbox = gui:CreateFormCheckbox(card.frame, nil, "sortByRole", layout, refresh, {
            description = ns.L["Order tanks first, healers second, and damage dealers last."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Sort by Role (Tank > Healer > DPS)"], sortByRoleCheckbox))

        local limitGroupsCheckbox = gui:CreateFormCheckbox(card.frame, nil, "limitGroupsByRaidSize", layout, function()
            refresh(true)
            RequestTabRepaint(ctx)
        end, {
            description = ns.L["Limit visible raid groups by instance size: groups 1-4 in Mythic and 1-6 otherwise."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Limit Groups by Raid Size"], limitGroupsCheckbox))

        local hiddenPlayersEdit = gui:CreateFormEditBox(card.frame, nil, "hiddenPlayers", groupFrames.gfdb, function()
            refresh(true)
        end, {
            commitOnEnter = true,
            commitOnFocusLost = true,
        }, {
            description = ns.L["Comma-separated character names whose frames are hidden entirely. Add -Realm to limit an entry to one realm. Shared between party and raid; roster changes during combat apply after combat ends."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Hidden Players"], hiddenPlayersEdit))

        local gfdb = groupFrames.gfdb
        if type(gfdb.raidSizeOffsets) ~= "table" then
            gfdb.raidSizeOffsets = {}
        end
        for _, bucket in ipairs({ "small", "medium", "large" }) do
            if type(gfdb.raidSizeOffsets[bucket]) ~= "table" then
                gfdb.raidSizeOffsets[bucket] = { offsetX = 0, offsetY = 0 }
            end
        end

        local perSizeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "raidPerSizePositions", gfdb, refresh, {
            description = ns.L["Position raid frames differently for small (15 or fewer), medium (16-25), and large (26+) raids. The offsets below are added to the base raid position set in Edit Mode; you must be in that raid size to see them apply."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Per-Size Raid Positions"], perSizeCheckbox))

        local smallX = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "offsetX", gfdb.raidSizeOffsets.small, refresh, { deferOnDrag = true }, {
            description = ns.L["Horizontal offset for small raids, added to the base raid position."],
        })
        local smallY = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "offsetY", gfdb.raidSizeOffsets.small, refresh, { deferOnDrag = true }, {
            description = ns.L["Vertical offset for small raids, added to the base raid position."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Small Raid X"], smallX),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Small Raid Y"], smallY)
        )

        local medX = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "offsetX", gfdb.raidSizeOffsets.medium, refresh, { deferOnDrag = true }, {
            description = ns.L["Horizontal offset for medium raids, added to the base raid position."],
        })
        local medY = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "offsetY", gfdb.raidSizeOffsets.medium, refresh, { deferOnDrag = true }, {
            description = ns.L["Vertical offset for medium raids, added to the base raid position."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Medium Raid X"], medX),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Medium Raid Y"], medY)
        )

        local largeX = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "offsetX", gfdb.raidSizeOffsets.large, refresh, { deferOnDrag = true }, {
            description = ns.L["Horizontal offset for large raids, added to the base raid position."],
        })
        local largeY = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "offsetY", gfdb.raidSizeOffsets.large, refresh, { deferOnDrag = true }, {
            description = ns.L["Vertical offset for large raids, added to the base raid position."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Large Raid X"], largeX),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Large Raid Y"], largeY)
        )
    else
        local showPlayerCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showPlayer", layout, refresh, {
            description = ns.L["Include the player's own frame in the party display."],
        })
        local showSoloCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showSolo", layout, refresh, {
            description = ns.L["Show the party frame while solo with only your own unit visible."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Show Player in Group"], showPlayerCheckbox),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Show Player Frame When Solo"], showSoloCheckbox)
        )

        local selfFirstCheckbox = gui:CreateFormCheckbox(card.frame, nil, "partySelfFirst", groupFrames.gfdb, refresh, {
            description = ns.L["Pin your own frame to the first slot regardless of the sort order."],
        })
        local sortByRoleCheckbox = gui:CreateFormCheckbox(card.frame, nil, "sortByRole", layout, refresh, {
            description = ns.L["Order tanks first, healers second, and damage dealers last."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Always Show Self First"], selfFirstCheckbox),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Sort by Role (Tank > Healer > DPS)"], sortByRoleCheckbox)
        )

        local hideDPSCheckbox = gui:CreateFormCheckbox(card.frame, nil, "hideDPS", layout, refresh, {
            description = ns.L["Show only tank and healer frames in the party, hiding damage dealers. Note: a DPS-spec player hides their own frame too. Party only (raid uses group-based filtering)."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Hide DPS Frames"], hideDPSCheckbox)
        )

        local hiddenPlayersEdit = gui:CreateFormEditBox(card.frame, nil, "hiddenPlayers", groupFrames.gfdb, function()
            refresh(true)
        end, {
            commitOnEnter = true,
            commitOnFocusLost = true,
        }, {
            description = ns.L["Comma-separated character names whose frames are hidden entirely. Add -Realm to limit an entry to one realm. Shared between party and raid; roster changes during combat apply after combat ends."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Hidden Players"], hiddenPlayersEdit))
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

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("layout"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    if groupFrames.contextMode ~= "raid" then
        builder.Header(ns.L["Dimensions"])
        builder.Description(string.format(ns.L["Width and height for each %1$s frame."], groupFrames.sourceLabel))

        local card = builder.Card()
        local widthSlider = gui:CreateFormSlider(card.frame, nil, 80, 400, 1, "partyWidth", dimensions, refresh, { deferOnDrag = true }, {
            description = ns.L["Width of each party frame in pixels."],
        })
        local heightSlider = gui:CreateFormSlider(card.frame, nil, 16, 80, 1, "partyHeight", dimensions, refresh, { deferOnDrag = true }, {
            description = ns.L["Height of each party frame in pixels."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Width"], widthSlider),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Height"], heightSlider)
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
            description = ns.L["Frame width used for this raid-size bracket."],
        })
        local heightSlider = gui:CreateFormSlider(card.frame, nil, heightRange[1], heightRange[2], 1, heightKey, dimensions, refresh, { deferOnDrag = true }, {
            description = ns.L["Frame height used for this raid-size bracket."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Width"], widthSlider),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Height"], heightSlider)
        )
        builder.CloseCard(card)
        builder.Spacer(10)
    end

    AddSizeSection(ns.L["Small Raid (6-15 players)"], "smallRaidWidth", { 60, 400 }, "smallRaidHeight", { 14, 100 },
        ns.L["Frame size used when the raid has between 6 and 15 members."])
    AddSizeSection(ns.L["Medium Raid (16-25 players)"], "mediumRaidWidth", { 50, 300 }, "mediumRaidHeight", { 12, 100 },
        ns.L["Frame size used when the raid has between 16 and 25 members."])
    AddSizeSection(ns.L["Large Raid (26-40 players)"], "largeRaidWidth", { 40, 250 }, "largeRaidHeight", { 10, 100 },
        ns.L["Frame size used when the raid has between 26 and 40 members."])
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

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("general"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Range Check"])
    builder.Description(ns.L["Fade units when they move out of your supported spell range."])

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
        description = ns.L["Fade group frames when the unit is out of range."],
    })
    local rangeAlphaSlider = gui:CreateFormSlider(rangeCard.frame, nil, 0.1, 0.8, 0.05, "outOfRangeAlpha", range, refresh, {
        precision = 2,
        deferOnDrag = true,
    }, {
        description = ns.L["Opacity applied to out-of-range frames."],
    })
    rangeAlphaCell = optionsAPI.BuildSettingRow(rangeCard.frame, ns.L["Out-of-Range Alpha"], rangeAlphaSlider)
    rangeCard.AddRow(
        optionsAPI.BuildSettingRow(rangeCard.frame, ns.L["Enable Range Check"], rangeEnabledCheckbox),
        rangeAlphaCell
    )
    UpdateRangeCells()
    builder.CloseCard(rangeCard)
    builder.Spacer(10)

    builder.Header(ns.L["Pet Frames"])
    builder.Description(ns.L["Show companion frames for pets alongside the main group."])

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
        description = ns.L["Show small frames for group-member pets."],
    })
    local petWidthSlider = gui:CreateFormSlider(petCard.frame, nil, 40, 200, 1, "width", pets, refresh, { deferOnDrag = true }, {
        description = ns.L["Width of each pet frame in pixels."],
    })
    petWidthCell = optionsAPI.BuildSettingRow(petCard.frame, ns.L["Pet Frame Width"], petWidthSlider)
    petCard.AddRow(
        optionsAPI.BuildSettingRow(petCard.frame, ns.L["Enable Pet Frames"], petsEnabledCheckbox),
        petWidthCell
    )

    local petHeightSlider = gui:CreateFormSlider(petCard.frame, nil, 10, 40, 1, "height", pets, refresh, { deferOnDrag = true }, {
        description = ns.L["Height of each pet frame in pixels."],
    })
    petHeightCell = optionsAPI.BuildSettingRow(petCard.frame, ns.L["Pet Frame Height"], petHeightSlider)
    local petAnchorDropdown = gui:CreateFormDropdown(petCard.frame, nil, PET_ANCHOR_OPTIONS, "anchorTo", pets, refresh, {
        description = ns.L["Where pet frames are anchored relative to the group."],
    })
    petAnchorCell = optionsAPI.BuildSettingRow(petCard.frame, ns.L["Pet Anchor"], petAnchorDropdown)
    petCard.AddRow(petHeightCell, petAnchorCell)

    UpdatePetCells()
    builder.CloseCard(petCard)
    return builder.Height()
end

local function RenderPartyTargetsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local targets = EnsureSubTable(groupFrames.contextDB, "targetFrames")
    if not targets then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("general"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Party Target Frames"])
    builder.Description(ns.L["Show each party member's current target (name and health) beside their frame."])

    local card = builder.Card()
    local widthCell, heightCell, anchorCell, gapCell, nameCell
    local function UpdateCells()
        local alpha = targets.enabled and 1.0 or 0.4
        if widthCell then widthCell:SetAlpha(alpha) end
        if heightCell then heightCell:SetAlpha(alpha) end
        if anchorCell then anchorCell:SetAlpha(alpha) end
        if gapCell then gapCell:SetAlpha(alpha) end
        if nameCell then nameCell:SetAlpha(alpha) end
    end

    local enabledCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", targets, function()
        refresh()
        UpdateCells()
    end, {
        description = ns.L["Show a small target frame for each party member."],
    })
    local widthSlider = gui:CreateFormSlider(card.frame, nil, 40, 300, 1, "width", targets, refresh, { deferOnDrag = true }, {
        description = ns.L["Width of each target frame in pixels."],
    })
    widthCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Target Frame Width"], widthSlider)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Enable Party Target Frames"], enabledCheckbox),
        widthCell
    )

    local heightSlider = gui:CreateFormSlider(card.frame, nil, 10, 60, 1, "height", targets, refresh, { deferOnDrag = true }, {
        description = ns.L["Height of each target frame in pixels."],
    })
    heightCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Target Frame Height"], heightSlider)
    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, TARGET_FRAME_ANCHOR_OPTIONS, "anchorTo", targets, refresh, {
        description = ns.L["Where each target frame sits relative to its party member frame."],
    })
    anchorCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Target Frame Anchor"], anchorDropdown)
    card.AddRow(heightCell, anchorCell)

    local gapSlider = gui:CreateFormSlider(card.frame, nil, 0, 20, 1, "anchorGap", targets, refresh, { deferOnDrag = true }, {
        description = ns.L["Gap between each target frame and its party member frame."],
    })
    gapCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Target Frame Gap"], gapSlider)
    local nameCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showName", targets, refresh, {
        description = ns.L["Show the target's name on the target frame."],
    })
    nameCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Show Target Name"], nameCheckbox)
    card.AddRow(gapCell, nameCell)

    UpdateCells()
    builder.CloseCard(card)
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
        return RenderUnavailableLabel(sectionHost, ns.L["Spotlight is only available for Raid frames."])
    end

    local spotlight = EnsureSubTable(groupFrames.contextDB, "spotlight")
    if not spotlight then
        return nil
    end

    if not spotlight.filterMode then
        spotlight.filterMode = "ROLE"
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("layout"))
    if not builder then
        return nil
    end

    builder.Header(ns.L["Spotlight"])
    builder.Description(ns.L["Creates a separate frame that pins raid members by role or name to a dedicated group."])

    local spotlightRows = {}
    local UpdateSpotlightRows
    local function track(cell)
        spotlightRows[#spotlightRows + 1] = cell
        return cell
    end

    local function onSpotlightChange(structural)
        if spotlight.enabled and not spotlight.filterTank and not spotlight.filterHealer then
            spotlight.filterTank = true
        end

        local layoutMode = ns.QUI_LayoutMode
        if layoutMode and layoutMode.SetElementEnabled then
            layoutMode:SetElementEnabled("spotlightFrames", spotlight.enabled == true)
        end

        RefreshSpotlight()
        if UpdateSpotlightRows then UpdateSpotlightRows() end
        if structural then
            NotifyProvider("spotlightFrames", true)
            RequestTabRepaint(ctx)
        end
    end

    local enableCard = builder.Card()
    local enableCheckbox = gui:CreateFormCheckbox(enableCard.frame, nil, "enabled", spotlight, function()
        onSpotlightChange()
    end, {
        description = ns.L["Enable a separate Spotlight group for pinned raid members."],
    })
    enableCard.AddRow(optionsAPI.BuildSettingRow(enableCard.frame, ns.L["Enable Spotlight"], enableCheckbox))
    builder.CloseCard(enableCard)
    builder.Spacer(10)

    builder.Header(ns.L["Filter"])
    local filterCard = builder.Card()
    local filterModeDropdown = gui:CreateFormDropdown(filterCard.frame, nil, SPOTLIGHT_FILTER_OPTIONS, "filterMode", spotlight, function()
        onSpotlightChange(true)
    end, {
        description = ns.L["Pin members by role or by a manual character-name list."],
    })
    filterCard.AddRow(track(optionsAPI.BuildSettingRow(filterCard.frame, ns.L["Filter By"], filterModeDropdown)))

    if spotlight.filterMode == "ROLE" then
        local tankCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "filterTank", spotlight, onSpotlightChange, {
            description = ns.L["Include tanks in the Spotlight group."],
        })
        local healerCheckbox = gui:CreateFormCheckbox(filterCard.frame, nil, "filterHealer", spotlight, onSpotlightChange, {
            description = ns.L["Include healers in the Spotlight group."],
        })
        filterCard.AddRow(
            track(optionsAPI.BuildSettingRow(filterCard.frame, ns.L["Tanks"], tankCheckbox)),
            track(optionsAPI.BuildSettingRow(filterCard.frame, ns.L["Healers"], healerCheckbox))
        )
    else
        local nameListEdit = gui:CreateFormEditBox(filterCard.frame, nil, "nameList", spotlight, onSpotlightChange, {
            commitOnEnter = true,
            commitOnFocusLost = true,
        }, {
            description = ns.L["Comma-separated character names to pin in Spotlight."],
        })
        filterCard.AddRow(track(optionsAPI.BuildSettingRow(filterCard.frame, ns.L["Player Names"], nameListEdit)))
    end
    builder.CloseCard(filterCard)
    builder.Spacer(10)

    builder.Header(ns.L["Dimensions"])
    local dimsCard = builder.Card()
    local widthSlider = gui:CreateFormSlider(dimsCard.frame, nil, 60, 300, 1, "frameWidth", spotlight, onSpotlightChange, { deferOnDrag = true }, {
        description = ns.L["Width of each Spotlight frame in pixels."],
    })
    local heightSlider = gui:CreateFormSlider(dimsCard.frame, nil, 16, 80, 1, "frameHeight", spotlight, onSpotlightChange, { deferOnDrag = true }, {
        description = ns.L["Height of each Spotlight frame in pixels."],
    })
    dimsCard.AddRow(
        track(optionsAPI.BuildSettingRow(dimsCard.frame, ns.L["Width"], widthSlider)),
        track(optionsAPI.BuildSettingRow(dimsCard.frame, ns.L["Height"], heightSlider))
    )
    builder.CloseCard(dimsCard)
    builder.Spacer(10)

    builder.Header(ns.L["Layout"])
    local layoutCard = builder.Card()
    if not spotlight.orientation then
        local growDirection = spotlight.growDirection or "DOWN"
        spotlight.orientation = (growDirection == "LEFT" or growDirection == "RIGHT") and "HORIZONTAL" or "VERTICAL"
    end
    local orientationDropdown = gui:CreateFormDropdown(layoutCard.frame, nil, LAYOUT_OPTIONS, "orientation", spotlight, function()
        spotlight.growDirection = spotlight.orientation == "HORIZONTAL" and "RIGHT" or "DOWN"
        onSpotlightChange()
    end, {
        description = ns.L["Stack Spotlight frames vertically (column) or horizontally (row)."],
    })
    local spacingSlider = gui:CreateFormSlider(layoutCard.frame, nil, 0, 10, 1, "spacing", spotlight, onSpotlightChange, { deferOnDrag = true }, {
        description = ns.L["Pixel gap between adjacent Spotlight frames."],
    })
    layoutCard.AddRow(
        track(optionsAPI.BuildSettingRow(layoutCard.frame, ns.L["Layout"], orientationDropdown)),
        track(optionsAPI.BuildSettingRow(layoutCard.frame, ns.L["Spacing"], spacingSlider))
    )
    builder.CloseCard(layoutCard)

    function UpdateSpotlightRows()
        local on = spotlight.enabled and true or false
        for _, cell in ipairs(spotlightRows) do
            if cell.SetEnabled then cell:SetEnabled(on) end
        end
    end
    UpdateSpotlightRows()

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

    local DRAW_ORDER_LIST = {
        { value = 1, text = ns.L["Back"] },
        { value = 2, text = ns.L["Middle"] },
        { value = 3, text = ns.L["Front"] },
    }
    local FILL_FROM_LIST = {
        { value = "reverse", text = ns.L["From End"] },
        { value = "default", text = ns.L["From Start"] },
    }
    local BAR_MODE_OPTIONS = {
        { value = "overlay", text = ns.L["Overlay"] },
        { value = "detached", text = ns.L["Detached"] },
    }
    local function AddOverlayControls(card, tbl, ctlOpts)
        ctlOpts = ctlOpts or {}
        local textureDrop = gui:CreateFormDropdown(card.frame, nil, optionsAPI.GetTextureList(), "texture", tbl, refresh, {
            description = ns.L["Texture used for this overlay bar."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Texture"], textureDrop))

        local orderDrop = gui:CreateFormDropdown(card.frame, nil, DRAW_ORDER_LIST, "drawOrder", tbl, refresh, {
            description = ns.L["Which overlay draws on top when absorb, heal-absorb and heal-prediction overlap. Front draws above the others."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Draw Order"], orderDrop))

        if ctlOpts.fillOrigin then
            local fillDrop = gui:CreateFormDropdown(card.frame, nil, FILL_FROM_LIST, "fillFrom", tbl, refresh, {
                description = ns.L["Which edge the overlay fills from."],
            })
            card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Fill From"], fillDrop))
        end

        local sparkCheck = gui:CreateFormCheckbox(card.frame, nil, "spark", tbl, refresh, {
            description = ns.L["Show a bright line at the leading edge of the overlay."],
        })
        local sparkColor = gui:CreateFormColorPicker(card.frame, nil, "sparkColor", tbl, refresh, nil, {
            description = ns.L["Color of the leading-edge spark line."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Edge Spark"], sparkCheck),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Spark Color"], sparkColor)
        )

        local outlineCheck = gui:CreateFormCheckbox(card.frame, nil, "outline", tbl, refresh, {
            description = ns.L["Draw a pixel border around the overlay bar."],
        })
        local outlineColor = gui:CreateFormColorPicker(card.frame, nil, "outlineColor", tbl, refresh, nil, {
            description = ns.L["Color of the overlay bar outline."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Outline"], outlineCheck),
            optionsAPI.BuildSettingRow(card.frame, ns.L["Outline Color"], outlineColor)
        )

        local widthCell, heightCell, anchorCell, offsetXCell, offsetYCell
        local function UpdateDetachedRows()
            local a = (tbl.mode == "detached") and 1.0 or 0.4
            if widthCell then widthCell:SetAlpha(a) end
            if heightCell then heightCell:SetAlpha(a) end
            if anchorCell then anchorCell:SetAlpha(a) end
            if offsetXCell then offsetXCell:SetAlpha(a) end
            if offsetYCell then offsetYCell:SetAlpha(a) end
        end

        local modeDrop = gui:CreateFormDropdown(card.frame, nil, BAR_MODE_OPTIONS, "mode", tbl, function()
            refresh()
            UpdateDetachedRows()
        end, {
            description = ns.L["Overlay draws on the health bar; Detached is a separate mini-bar with its own size and position."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Bar Mode"], modeDrop))

        local widthSlider = gui:CreateFormSlider(card.frame, nil, 10, 200, 1, "width", tbl, refresh, { deferOnDrag = true }, {
            description = ns.L["Detached mini-bar width in pixels."],
        })
        widthCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Bar Width"], widthSlider)
        local heightSlider = gui:CreateFormSlider(card.frame, nil, 2, 40, 1, "height", tbl, refresh, { deferOnDrag = true }, {
            description = ns.L["Detached mini-bar height in pixels."],
        })
        heightCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Bar Height"], heightSlider)
        card.AddRow(widthCell, heightCell)

        local anchorDrop = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "anchor", tbl, refresh, {
            description = ns.L["Anchor point of the detached mini-bar on the unit frame."],
        })
        anchorCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Bar Anchor"], anchorDrop)
        card.AddRow(anchorCell)

        local offXSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetX", tbl, refresh, { deferOnDrag = true }, {
            description = ns.L["Horizontal offset of the detached mini-bar."],
        })
        offsetXCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Offset X"], offXSlider)
        local offYSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetY", tbl, refresh, { deferOnDrag = true }, {
            description = ns.L["Vertical offset of the detached mini-bar."],
        })
        offsetYCell = optionsAPI.BuildSettingRow(card.frame, ns.L["Offset Y"], offYSlider)
        card.AddRow(offsetXCell, offsetYCell)

        UpdateDetachedRows()
    end

    builder.Header(ns.L["Health Bar"])
    local barCard = builder.Card()
    local textureDropdown = gui:CreateFormDropdown(barCard.frame, nil, optionsAPI.GetTextureList(), "texture", general, refresh, {
        description = ns.L["Statusbar texture used for the health bar. Supports SharedMedia textures."],
    })
    local healthOpacitySlider = gui:CreateFormSlider(barCard.frame, nil, 0, 1, 0.05, "defaultHealthOpacity", general, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the filled portion of the health bar. 1.0 is fully opaque."],
    })
    barCard.AddRow(
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Health Texture"], textureDropdown),
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Health Opacity"], healthOpacitySlider)
    )

    local fillDirectionDropdown = gui:CreateFormDropdown(barCard.frame, nil, HEALTH_FILL_OPTIONS, "healthFillDirection", health, refresh, {
        description = ns.L["Direction the health fill drains toward as the unit loses health."],
    })
    barCard.AddRow(optionsAPI.BuildSettingRow(barCard.frame, ns.L["Fill Direction"], fillDirectionDropdown))
    builder.CloseCard(barCard)

    builder.Spacer(6)
    builder.Header(ns.L["Health Text"])
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
        description = ns.L["Show the unit's health as text on this frame. Use Display Style below to pick the format."],
    })
    local healthDisplayDropdown = gui:CreateFormDropdown(textCard.frame, nil, HEALTH_DISPLAY_OPTIONS, "healthDisplayStyle", health, refresh, {
        description = ns.L["How health is formatted: percent only, raw value, value-plus-percent, or deficit."],
    })
    healthDisplayRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Display Style"], healthDisplayDropdown)
    textCard.AddRow(
        optionsAPI.BuildSettingRow(textCard.frame, ns.L["Show Health Text"], showHealthTextCheckbox),
        healthDisplayRow
    )

    local healthFontSlider = gui:CreateFormSlider(textCard.frame, nil, 6, 24, 1, "healthFontSize", health, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size used for the health text."],
    })
    healthFontRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Font Size"], healthFontSlider)
    local healthAnchorDropdown = gui:CreateFormDropdown(textCard.frame, nil, NINE_POINT_OPTIONS, "healthAnchor", health, refresh, {
        description = ns.L["Where on the frame the health text is anchored. X/Y Offset below nudges it from this anchor point."],
    })
    healthAnchorRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Anchor"], healthAnchorDropdown)
    textCard.AddRow(healthFontRow, healthAnchorRow)

    local healthJustifyDropdown = gui:CreateFormDropdown(textCard.frame, nil, TEXT_JUSTIFY_OPTIONS, "healthJustify", health, refresh, {
        description = ns.L["Horizontal text alignment within the health text region."],
    })
    healthJustifyRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Text Justify"], healthJustifyDropdown)
    local healthXSlider = gui:CreateFormSlider(textCard.frame, nil, -100, 100, 1, "healthOffsetX", health, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset for the health text from its anchor. Positive moves right, negative moves left."],
    })
    healthXRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["X Offset"], healthXSlider)
    textCard.AddRow(healthJustifyRow, healthXRow)

    local healthYSlider = gui:CreateFormSlider(textCard.frame, nil, -100, 100, 1, "healthOffsetY", health, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset for the health text from its anchor. Positive moves up, negative moves down."],
    })
    healthYRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Y Offset"], healthYSlider)
    local healthColorPicker = gui:CreateFormColorPicker(textCard.frame, nil, "healthTextColor", health, refresh, nil, {
        description = ns.L["Color used for the health text."],
    })
    healthColorRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Text Color"], healthColorPicker)
    textCard.AddRow(healthYRow, healthColorRow)
    UpdateHealthTextRows()
    builder.CloseCard(textCard)

    builder.Spacer(6)
    builder.Header(ns.L["Absorb Shield"])
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
        description = ns.L["Overlay an indicator on the health bar showing the size of incoming damage absorbs."],
    })
    local absorbClassCheckbox = gui:CreateFormCheckbox(absorbCard.frame, nil, "useClassColor", absorbs, function()
        refresh()
        UpdateAbsorbRows()
    end, {
        description = ns.L["Tint the absorb overlay with the unit's class color instead of the Absorb Color swatch below."],
    })
    absorbClassRow = optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Use Class Color"], absorbClassCheckbox)
    absorbCard.AddRow(
        optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Show Absorb Shield"], absorbEnableCheckbox),
        absorbClassRow
    )

    local absorbColorPicker = gui:CreateFormColorPicker(absorbCard.frame, nil, "color", absorbs, refresh, nil, {
        description = ns.L["Tint used for the absorb overlay when Use Class Color is off."],
    })
    absorbColorRow = optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Absorb Color"], absorbColorPicker)
    local absorbOpacitySlider = gui:CreateFormSlider(absorbCard.frame, nil, 0.1, 1, 0.05, "opacity", absorbs, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the absorb shield overlay."],
    })
    absorbOpacityRow = optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Absorb Opacity"], absorbOpacitySlider)
    absorbCard.AddRow(absorbColorRow, absorbOpacityRow)
    UpdateAbsorbRows()
    AddOverlayControls(absorbCard, absorbs, { fillOrigin = true })
    builder.CloseCard(absorbCard)

    builder.Spacer(6)
    builder.Header(ns.L["Heal Absorb"])
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
        description = ns.L["Overlay an indicator on the health bar showing active heal-absorb effects that must be healed through before real healing lands."],
    })
    local healAbsorbColorPicker = gui:CreateFormColorPicker(healAbsorbCard.frame, nil, "color", healAbsorbs, refresh, nil, {
        description = ns.L["Tint used for the heal-absorb overlay."],
    })
    healAbsorbColorRow = optionsAPI.BuildSettingRow(healAbsorbCard.frame, ns.L["Heal Absorb Color"], healAbsorbColorPicker)
    healAbsorbCard.AddRow(
        optionsAPI.BuildSettingRow(healAbsorbCard.frame, ns.L["Show Heal Absorb"], healAbsorbEnableCheckbox),
        healAbsorbColorRow
    )

    local healAbsorbOpacitySlider = gui:CreateFormSlider(healAbsorbCard.frame, nil, 0.1, 1, 0.05, "opacity", healAbsorbs, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the heal-absorb overlay."],
    })
    healAbsorbOpacityRow = optionsAPI.BuildSettingRow(healAbsorbCard.frame, ns.L["Heal Absorb Opacity"], healAbsorbOpacitySlider)
    healAbsorbCard.AddRow(healAbsorbOpacityRow)
    UpdateHealAbsorbRows()
    AddOverlayControls(healAbsorbCard, healAbsorbs, { fillOrigin = true })
    builder.CloseCard(healAbsorbCard)

    builder.Spacer(6)
    builder.Header(ns.L["Heal Prediction"])
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
        description = ns.L["Overlay an indicator on the health bar showing heals being cast on this unit before they land."],
    })
    local healPredictionClassCheckbox = gui:CreateFormCheckbox(healPredictionCard.frame, nil, "useClassColor", healPrediction, function()
        refresh()
        UpdateHealPredictionRows()
    end, {
        description = ns.L["Tint the heal-prediction overlay with the caster's class color instead of the Heal Prediction Color swatch below."],
    })
    healPredictionClassRow = optionsAPI.BuildSettingRow(healPredictionCard.frame, ns.L["Use Class Color"], healPredictionClassCheckbox)
    healPredictionCard.AddRow(
        optionsAPI.BuildSettingRow(healPredictionCard.frame, ns.L["Show Heal Prediction"], healPredictionEnableCheckbox),
        healPredictionClassRow
    )

    local healPredictionColorPicker = gui:CreateFormColorPicker(healPredictionCard.frame, nil, "color", healPrediction, refresh, nil, {
        description = ns.L["Tint used for the incoming-heal overlay when Use Class Color is off."],
    })
    healPredictionColorRow = optionsAPI.BuildSettingRow(healPredictionCard.frame, ns.L["Heal Prediction Color"], healPredictionColorPicker)
    local healPredictionOpacitySlider = gui:CreateFormSlider(healPredictionCard.frame, nil, 0.1, 1, 0.05, "opacity", healPrediction, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the incoming-heal overlay."],
    })
    healPredictionOpacityRow = optionsAPI.BuildSettingRow(healPredictionCard.frame, ns.L["Heal Prediction Opacity"], healPredictionOpacitySlider)
    healPredictionCard.AddRow(healPredictionColorRow, healPredictionOpacityRow)
    UpdateHealPredictionRows()
    AddOverlayControls(healPredictionCard, healPrediction, { fillOrigin = false })
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

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("appearance"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Power"])
    builder.Description(string.format(ns.L["Power-bar visibility and coloring for %1$s group frames."], groupFrames.sourceLabel))

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
        description = ns.L["Show a power bar below the health bar on this frame."],
    })
    local heightSlider = gui:CreateFormSlider(card.frame, nil, 1, 12, 1, "powerBarHeight", power, refresh, { deferOnDrag = true }, {
        description = ns.L["Height of the power bar in pixels. Counted as part of the overall frame height."],
    })
    heightRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Height"], heightSlider)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Power Bar"], showPowerBarCheckbox),
        heightRow
    )

    local healerCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarOnlyHealers", power, refresh, {
        description = ns.L["Restrict the power bar to units specced as healers."],
    })
    healerRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Only Show for Healers"], healerCheckbox)
    local tankCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarOnlyTanks", power, refresh, {
        description = ns.L["Restrict the power bar to units specced as tanks."],
    })
    tankRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Only Show for Tanks"], tankCheckbox)
    card.AddRow(healerRow, tankRow)

    local usePowerColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarUsePowerColor", power, function()
        refresh()
        UpdatePowerRows()
    end, {
        description = ns.L["Color the power bar by power type instead of the Custom Color swatch below."],
    })
    usePowerColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Use Power Type Color"], usePowerColorCheckbox)
    local customColorPicker = gui:CreateFormColorPicker(card.frame, nil, "powerBarColor", power, refresh, nil, {
        description = ns.L["Solid color for the power bar when Use Power Type Color is off."],
    })
    customColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Custom Color"], customColorPicker)
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

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("appearance"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Name"])
    builder.Description(string.format(ns.L["Name text placement and styling for %1$s group frames."], groupFrames.sourceLabel))

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
        description = ns.L["Show the unit's name on this frame."],
    })
    local fontSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, "nameFontSize", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size used for the unit's name."],
    })
    fontSizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Font Size"], fontSizeSlider)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Name"], showNameCheckbox),
        fontSizeRow
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "nameAnchor", name, refresh, {
        description = ns.L["Where on the frame the name text is anchored. X/Y Offset below nudges it from this anchor point."],
    })
    anchorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Anchor"], anchorDropdown)
    local justifyDropdown = gui:CreateFormDropdown(card.frame, nil, TEXT_JUSTIFY_OPTIONS, "nameJustify", name, refresh, {
        description = ns.L["Horizontal text alignment within the name text region."],
    })
    justifyRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Text Justify"], justifyDropdown)
    card.AddRow(anchorRow, justifyRow)

    local maxLengthSlider = gui:CreateFormSlider(card.frame, nil, 0, 20, 1, "maxNameLength", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Truncate names longer than this many characters. Set to 0 to disable truncation entirely."],
    })
    maxLengthRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Max Name Length (0 = unlimited)"], maxLengthSlider)
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "nameOffsetX", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset for the name text from its anchor. Positive moves right, negative moves left."],
    })
    xOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["X Offset"], xOffsetSlider)
    card.AddRow(maxLengthRow, xOffsetRow)

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "nameOffsetY", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset for the name text from its anchor. Positive moves up, negative moves down."],
    })
    yOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Y Offset"], yOffsetSlider)
    local useClassColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "nameTextUseClassColor", name, function()
        refresh()
        UpdateNameRows()
    end, {
        description = ns.L["Color the name text by the unit's class instead of the Text Color swatch below."],
    })
    useClassColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Use Class Color"], useClassColorCheckbox)
    card.AddRow(yOffsetRow, useClassColorRow)

    local textColorPicker = gui:CreateFormColorPicker(card.frame, nil, "nameTextColor", name, refresh, nil, {
        description = ns.L["Color used for the name when Use Class Color is off."],
    })
    textColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Text Color"], textColorPicker)
    card.AddRow(textColorRow)

    UpdateNameRows()
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderGroupNumberSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames or groupFrames.contextMode ~= "raid" then
        return nil
    end

    local groupNumber = EnsureSubTable(groupFrames.contextDB, "groupNumber")
    if not groupNumber then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("appearance"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Group Header"])
    builder.Description(ns.L["Shows a single \"Group N\" header above each raid subgroup block. Requires Group By = Group; party frames have no subgroups, so this is raid-only."])

    local card = builder.Card()
    local fontSizeRow, anchorRow, xOffsetRow, yOffsetRow, textColorRow
    local function UpdateGroupNumberRows()
        local alpha = groupNumber.showGroupNumber == true and 1.0 or 0.4
        if fontSizeRow then fontSizeRow:SetAlpha(alpha) end
        if anchorRow then anchorRow:SetAlpha(alpha) end
        if xOffsetRow then xOffsetRow:SetAlpha(alpha) end
        if yOffsetRow then yOffsetRow:SetAlpha(alpha) end
        if textColorRow then textColorRow:SetAlpha(alpha) end
    end

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showGroupNumber", groupNumber, function()
        refresh()
        UpdateGroupNumberRows()
    end, {
        description = ns.L["Show a single \"Group N\" header above each raid subgroup (requires Group By = Group)."],
    })
    local fontSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, "groupNumberFontSize", groupNumber, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size used for the group header label."],
    })
    fontSizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Font Size"], fontSizeSlider)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Group Header"], showCheckbox),
        fontSizeRow
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "groupNumberAnchor", groupNumber, refresh, {
        description = ns.L["Where the \"Group N\" header anchors relative to the group block. X/Y Offset below nudges it from that point."],
    })
    anchorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Anchor"], anchorDropdown)
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "groupNumberOffsetX", groupNumber, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset for the group header from its anchor. Positive moves right, negative moves left."],
    })
    xOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["X Offset"], xOffsetSlider)
    card.AddRow(anchorRow, xOffsetRow)

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "groupNumberOffsetY", groupNumber, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset for the group header from its anchor. Positive moves up, negative moves down."],
    })
    yOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Y Offset"], yOffsetSlider)
    local textColorPicker = gui:CreateFormColorPicker(card.frame, nil, "groupNumberTextColor", groupNumber, refresh, nil, {
        description = ns.L["Color used for the group header text."],
    })
    textColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Text Color"], textColorPicker)
    card.AddRow(yOffsetRow, textColorRow)

    UpdateGroupNumberRows()
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderLevelSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames or groupFrames.contextMode ~= "party" then
        return nil
    end

    local name = EnsureSubTable(groupFrames.contextDB, "name")
    if not name then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("appearance"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Level"])
    builder.Description(ns.L["Level text placement and styling for party frames."])

    local card = builder.Card()
    local fontRow, fontSizeRow, anchorRow, justifyRow, xOffsetRow, yOffsetRow, textColorRow
    local function UpdateLevelRows()
        local alpha = name.showLevel == true and 1.0 or 0.4
        if fontRow then fontRow:SetAlpha(alpha) end
        if fontSizeRow then fontSizeRow:SetAlpha(alpha) end
        if anchorRow then anchorRow:SetAlpha(alpha) end
        if justifyRow then justifyRow:SetAlpha(alpha) end
        if xOffsetRow then xOffsetRow:SetAlpha(alpha) end
        if yOffsetRow then yOffsetRow:SetAlpha(alpha) end
        if textColorRow then textColorRow:SetAlpha(alpha) end
    end

    local showLevelCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showLevel", name, function()
        refresh()
        UpdateLevelRows()
    end, {
        description = ns.L["Show the unit's level on party frames."],
    })
    local fontDropdown = gui:CreateFormDropdown(card.frame, nil, GetFontListWithDefault(optionsAPI), "levelFont", name, refresh, nil, {
        searchable = true,
    })
    fontRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level Font"], fontDropdown)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Level"], showLevelCheckbox),
        fontRow
    )

    local fontSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, "levelFontSize", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size used for the unit level."],
    })
    fontSizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level Font Size"], fontSizeSlider)
    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "levelAnchor", name, refresh, {
        description = ns.L["Where on the frame the level text is anchored. X/Y Offset below nudges it from this anchor point."],
    })
    anchorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level Anchor"], anchorDropdown)
    card.AddRow(fontSizeRow, anchorRow)

    local justifyDropdown = gui:CreateFormDropdown(card.frame, nil, TEXT_JUSTIFY_OPTIONS, "levelJustify", name, refresh, {
        description = ns.L["Horizontal text alignment within the level text region."],
    })
    justifyRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level Text Justify"], justifyDropdown)
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "levelOffsetX", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset for the level text from its anchor. Positive moves right, negative moves left."],
    })
    xOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level X Offset"], xOffsetSlider)
    card.AddRow(justifyRow, xOffsetRow)

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "levelOffsetY", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset for the level text from its anchor. Positive moves up, negative moves down."],
    })
    yOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level Y Offset"], yOffsetSlider)
    local textColorPicker = gui:CreateFormColorPicker(card.frame, nil, "levelTextColor", name, refresh, nil, {
        description = ns.L["Color used for the level text."],
    })
    textColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level Text Color"], textColorPicker)
    card.AddRow(yOffsetRow, textColorRow)

    UpdateLevelRows()
    builder.CloseCard(card)
    return builder.Height()
end

local function EnsureDispelColors(dispel)
    if type(dispel.colors) ~= "table" then
        dispel.colors = {
            Magic = { 0.2, 0.6, 1.0, 1 },
            Curse = { 0.6, 0.0, 1.0, 1 },
            Disease = { 0.6, 0.4, 0.0, 1 },
            Poison = { 0.0, 0.6, 0.0, 1 },
        }
    end
    if ns.QUI_GroupFrameIconLayout and ns.QUI_GroupFrameIconLayout.SeedDispelColors then
        ns.QUI_GroupFrameIconLayout.SeedDispelColors(dispel.colors)
    end
end

local function RenderDispelOverlaySection(sectionHost, ctx)
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
    if not dispel then
        return nil
    end
    EnsureDispelColors(dispel)

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("appearance"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Dispel Overlay"])
    builder.Description(string.format(ns.L["Dispel border and type-icon alerts for %1$s group frames."], groupFrames.sourceLabel))

    local dispelCard = builder.Card()
    local borderRows, iconRows = {}, {}
    local scopeRow
    local function UpdateDispelRows()
        local borderAlpha = dispel.enabled ~= false and 1.0 or 0.4
        local iconAlpha = dispel.showIcon == true and 1.0 or 0.4
        for _, row in ipairs(borderRows) do
            row:SetAlpha(borderAlpha)
        end
        for _, row in ipairs(iconRows) do
            row:SetAlpha(iconAlpha)
        end
        if scopeRow then
            scopeRow:SetAlpha((dispel.enabled ~= false or dispel.showIcon == true) and 1.0 or 0.4)
        end
    end

    local dispelEnableCheckbox = gui:CreateFormCheckbox(dispelCard.frame, nil, "enabled", dispel, function()
        refresh()
        UpdateDispelRows()
    end, {
        description = ns.L["Outline the frame border in the dispel type's color when a debuff you can dispel is active on the unit."],
    })
    local iconEnableCheckbox = gui:CreateFormCheckbox(dispelCard.frame, nil, "showIcon", dispel, function()
        refresh()
        UpdateDispelRows()
    end, {
        description = ns.L["Show the Blizzard Magic, Curse, Disease, Poison, or Bleed type icon. Independent of the colored border."],
    })
    dispelCard.AddRow(
        optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Enable Dispel Overlay"], dispelEnableCheckbox),
        optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Show Dispel Type Icon"], iconEnableCheckbox)
    )

    local scopeDropdown = gui:CreateFormDropdown(dispelCard.frame, nil, DISPEL_SCOPE_OPTIONS, "scope", dispel, refresh, {
        description = ns.L["Dispellable by Me shows actionable dispels. All Typed Debuffs also shows awareness-only types such as Bleed and Enrage. Cleanse-Ready Glow always remains actionable-only."],
    })
    scopeRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Show For"], scopeDropdown)
    local iconSizeSlider = gui:CreateFormSlider(dispelCard.frame, nil, 8, 64, 1, "iconSize", dispel, refresh, { deferOnDrag = true }, {
        description = ns.L["Width and height of the dispel type icon in pixels."],
    })
    local iconSizeRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Icon Size"], iconSizeSlider)
    iconRows[#iconRows + 1] = iconSizeRow
    dispelCard.AddRow(scopeRow, iconSizeRow)

    local borderSizeSlider = gui:CreateFormSlider(dispelCard.frame, nil, 1, 16, 1, "borderSize", dispel, refresh, { deferOnDrag = true }, {
        description = ns.L["Pixel thickness of the dispel border."],
    })
    local borderSizeRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Border Size"], borderSizeSlider)
    borderRows[#borderRows + 1] = borderSizeRow
    local iconOpacitySlider = gui:CreateFormSlider(dispelCard.frame, nil, 0.1, 1, 0.05, "iconOpacity", dispel, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the dispel type icon."],
    })
    local iconOpacityRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Icon Opacity"], iconOpacitySlider)
    iconRows[#iconRows + 1] = iconOpacityRow
    dispelCard.AddRow(
        borderSizeRow,
        iconOpacityRow
    )

    local borderOpacitySlider = gui:CreateFormSlider(dispelCard.frame, nil, 0.1, 1, 0.05, "opacity", dispel, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the dispel-type colored border."],
    })
    local borderOpacityRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Border Opacity"], borderOpacitySlider)
    borderRows[#borderRows + 1] = borderOpacityRow
    local fillOpacitySlider = gui:CreateFormSlider(dispelCard.frame, nil, 0, 0.5, 0.05, "fillOpacity", dispel, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of a color tint applied across the health bar when a dispellable debuff is active."],
    })
    local fillOpacityRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Fill Opacity"], fillOpacitySlider)
    borderRows[#borderRows + 1] = fillOpacityRow
    dispelCard.AddRow(borderOpacityRow, fillOpacityRow)

    local iconAnchorDropdown = gui:CreateFormDropdown(dispelCard.frame, nil, NINE_POINT_OPTIONS, "iconAnchor", dispel, refresh, {
        description = ns.L["Where the dispel type icon anchors on the unit frame."],
    })
    local iconAnchorRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Icon Anchor"], iconAnchorDropdown)
    iconRows[#iconRows + 1] = iconAnchorRow
    local iconXSlider = gui:CreateFormSlider(dispelCard.frame, nil, -100, 100, 1, "iconOffsetX", dispel, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset of the dispel type icon."],
    })
    local iconXRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Icon X Offset"], iconXSlider)
    iconRows[#iconRows + 1] = iconXRow
    dispelCard.AddRow(iconAnchorRow, iconXRow)

    local iconYSlider = gui:CreateFormSlider(dispelCard.frame, nil, -100, 100, 1, "iconOffsetY", dispel, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset of the dispel type icon."],
    })
    local iconYRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Icon Y Offset"], iconYSlider)
    iconRows[#iconRows + 1] = iconYRow
    dispelCard.AddRow(iconYRow)

    local magicColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Magic", dispel.colors, refresh, nil, {
        description = ns.L["Color used when the active dispellable debuff is of Magic type."],
    })
    local magicColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Magic Color"], magicColorPicker)
    borderRows[#borderRows + 1] = magicColorRow
    local curseColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Curse", dispel.colors, refresh, nil, {
        description = ns.L["Color used when the active dispellable debuff is of Curse type."],
    })
    local curseColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Curse Color"], curseColorPicker)
    borderRows[#borderRows + 1] = curseColorRow
    dispelCard.AddRow(magicColorRow, curseColorRow)

    local diseaseColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Disease", dispel.colors, refresh, nil, {
        description = ns.L["Color used when the active dispellable debuff is of Disease type."],
    })
    local diseaseColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Disease Color"], diseaseColorPicker)
    borderRows[#borderRows + 1] = diseaseColorRow
    local poisonColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Poison", dispel.colors, refresh, nil, {
        description = ns.L["Color used when the active dispellable debuff is of Poison type."],
    })
    local poisonColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Poison Color"], poisonColorPicker)
    borderRows[#borderRows + 1] = poisonColorRow
    dispelCard.AddRow(diseaseColorRow, poisonColorRow)

    local bleedColorPicker = gui:CreateFormColorPicker(dispelCard.frame, nil, "Bleed", dispel.colors, refresh, nil, {
        description = ns.L["Bleed effects can't be dispelled — this color is for awareness only."],
    })
    local bleedColorRow = optionsAPI.BuildSettingRow(dispelCard.frame, ns.L["Bleed"], bleedColorPicker)
    borderRows[#borderRows + 1] = bleedColorRow
    dispelCard.AddRow(bleedColorRow)

    UpdateDispelRows()
    builder.CloseCard(dispelCard)

    local glow = EnsureSubTable(healer, "cleanseGlow")
    if glow then
        if type(glow.color) ~= "table" then
            glow.color = { 0.1, 1.0, 0.1, 1 }
        end
        builder.Header(ns.L["Cleanse-Ready Glow"])
        local glowCard = builder.Card()
        local glowEnableCheckbox = gui:CreateFormCheckbox(glowCard.frame, nil, "enabled", glow, refresh, {
            description = ns.L["Show an additive glow around the frame whenever you can dispel a debuff on this unit. Independent of the dispel border above; works on its own."],
        })
        local glowColorPicker = gui:CreateFormColorPicker(glowCard.frame, nil, "color", glow, refresh, nil, {
            description = ns.L["Color of the cleanse-ready glow."],
        })
        glowCard.AddRow(
            optionsAPI.BuildSettingRow(glowCard.frame, ns.L["Enable Cleanse-Ready Glow"], glowEnableCheckbox),
            optionsAPI.BuildSettingRow(glowCard.frame, ns.L["Glow Color"], glowColorPicker)
        )
        builder.CloseCard(glowCard)
    end

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
    local targetHighlight = EnsureSubTable(healer, "targetHighlight")
    if not targetHighlight then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("general"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Target Highlight"])
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
        description = ns.L["Highlight the frame representing your current target so it stands out in party/raid."],
    })
    local targetColorPicker = gui:CreateFormColorPicker(targetCard.frame, nil, "color", targetHighlight, refresh, nil, {
        description = ns.L["Color used for the target highlight border and optional fill tint."],
    })
    targetColorRow = optionsAPI.BuildSettingRow(targetCard.frame, ns.L["Highlight Color"], targetColorPicker)
    targetCard.AddRow(
        optionsAPI.BuildSettingRow(targetCard.frame, ns.L["Enable Target Highlight"], targetEnableCheckbox),
        targetColorRow
    )

    local targetFillSlider = gui:CreateFormSlider(targetCard.frame, nil, 0, 0.5, 0.05, "fillOpacity", targetHighlight, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of a color tint applied across the targeted unit's health bar."],
    })
    targetFillRow = optionsAPI.BuildSettingRow(targetCard.frame, ns.L["Fill Opacity"], targetFillSlider)
    targetCard.AddRow(targetFillRow)
    UpdateTargetRows()
    builder.CloseCard(targetCard)

    return builder.Height()
end

local function RenderTargetedSpellsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end

    local targeted = EnsureSubTable(groupFrames.contextDB, "targetedSpells")
    if not targeted then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("auras"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
        local TS = ns.QUI_GroupFrameTargetedSpells
        if TS and type(TS.ApplySettings) == "function" then
            TS:ApplySettings()
        end
    end

    builder.Header(ns.L["Targeted Spells"])
    builder.Description(string.format(ns.L["Enemy cast icons shown on %1$s group frames when a nameplate spell is targeting that player."], groupFrames.sourceLabel))

    local card = builder.Card()
    local controlledRows = {}
    local function UpdateTargetedRows()
        local alpha = targeted.enabled ~= false and 1.0 or 0.4
        for _, row in ipairs(controlledRows) do
            row:SetAlpha(alpha)
        end
    end

    local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", targeted, function()
        refresh()
        UpdateTargetedRows()
    end, {
        description = ns.L["Show spell icons on group members when enemy nameplate casts report a displayable player target."],
    })
    local maxIconsSlider = gui:CreateFormSlider(card.frame, nil, 1, 5, 1, "maxIcons", targeted, refresh, { deferOnDrag = true }, {
        description = ns.L["Hard cap on how many targeted spell icons this frame displays at once."],
    })
    local maxIconsRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Max Icons"], maxIconsSlider)
    controlledRows[#controlledRows + 1] = maxIconsRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Enable Targeted Spells"], enableCheckbox),
        maxIconsRow
    )

    local iconSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 48, 1, "iconSize", targeted, refresh, { deferOnDrag = true }, {
        description = ns.L["Pixel size of each targeted spell icon."],
    })
    local iconSizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Icon Size"], iconSizeSlider)
    controlledRows[#controlledRows + 1] = iconSizeRow
    local reverseSwipeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "reverseSwipe", targeted, refresh, {
        description = ns.L["Reverse the swipe direction so the shaded portion grows instead of shrinks as the cast progresses."],
    })
    local reverseSwipeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Reverse Swipe"], reverseSwipeCheckbox)
    controlledRows[#controlledRows + 1] = reverseSwipeRow
    card.AddRow(iconSizeRow, reverseSwipeRow)

    local growDirectionDropdown = gui:CreateFormDropdown(card.frame, nil, AURA_GROW_OPTIONS, "growDirection", targeted, refresh, {
        description = ns.L["Direction additional targeted spell icons are added in after the first."],
    })
    local growDirectionRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Grow Direction"], growDirectionDropdown)
    controlledRows[#controlledRows + 1] = growDirectionRow
    local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 8, 1, "spacing", targeted, refresh, { deferOnDrag = true }, {
        description = ns.L["Pixel gap between adjacent targeted spell icons."],
    })
    local spacingRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Spacing"], spacingSlider)
    controlledRows[#controlledRows + 1] = spacingRow
    card.AddRow(growDirectionRow, spacingRow)

    local positionDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, "position", targeted, refresh, {
        description = ns.L["Where on the frame the targeted spell icon strip is anchored. X/Y Offset below nudges it from this anchor point."],
    })
    local positionRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Position"], positionDropdown)
    controlledRows[#controlledRows + 1] = positionRow
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetX", targeted, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset for the targeted spell icons from their anchor."],
    })
    local xOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["X Offset"], xOffsetSlider)
    controlledRows[#controlledRows + 1] = xOffsetRow
    card.AddRow(positionRow, xOffsetRow)

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetY", targeted, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset for the targeted spell icons from their anchor."],
    })
    local yOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Y Offset"], yOffsetSlider)
    controlledRows[#controlledRows + 1] = yOffsetRow
    card.AddRow(yOffsetRow)

    UpdateTargetedRows()
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

    builder.Header(ns.L["Role Icon"])
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
        description = ns.L["Show the unit's assigned group role icon on this frame."],
    })
    local showTankCheckbox = gui:CreateFormCheckbox(roleCard.frame, nil, "showRoleTank", indicators, refresh, {
        description = ns.L["Include the tank role icon on units specced as tanks."],
    })
    local showTankRow = optionsAPI.BuildSettingRow(roleCard.frame, ns.L["Show Tank"], showTankCheckbox)
    roleRows[#roleRows + 1] = showTankRow
    roleCard.AddRow(
        optionsAPI.BuildSettingRow(roleCard.frame, ns.L["Show Role Icon"], showRoleIconCheckbox),
        showTankRow
    )

    local showHealerCheckbox = gui:CreateFormCheckbox(roleCard.frame, nil, "showRoleHealer", indicators, refresh, {
        description = ns.L["Include the healer role icon on units specced as healers."],
    })
    local showHealerRow = optionsAPI.BuildSettingRow(roleCard.frame, ns.L["Show Healer"], showHealerCheckbox)
    roleRows[#roleRows + 1] = showHealerRow
    local showDPSCheckbox = gui:CreateFormCheckbox(roleCard.frame, nil, "showRoleDPS", indicators, refresh, {
        description = ns.L["Include the DPS role icon on units specced as damage dealers."],
    })
    local showDPSRow = optionsAPI.BuildSettingRow(roleCard.frame, ns.L["Show DPS"], showDPSCheckbox)
    roleRows[#roleRows + 1] = showDPSRow
    roleCard.AddRow(showHealerRow, showDPSRow)

    local roleSizeSlider = gui:CreateFormSlider(roleCard.frame, nil, 6, 24, 1, "roleIconSize", indicators, refresh, { deferOnDrag = true }, {
        description = ns.L["Pixel size of the role icon."],
    })
    local roleSizeRow = optionsAPI.BuildSettingRow(roleCard.frame, ns.L["Icon Size"], roleSizeSlider)
    roleRows[#roleRows + 1] = roleSizeRow
    local roleAnchorDropdown = gui:CreateFormDropdown(roleCard.frame, nil, NINE_POINT_OPTIONS, "roleIconAnchor", indicators, refresh, {
        description = ns.L["Where on the frame the role icon is anchored. X/Y Offset below nudges it from this anchor point."],
    })
    local roleAnchorRow = optionsAPI.BuildSettingRow(roleCard.frame, ns.L["Anchor"], roleAnchorDropdown)
    roleRows[#roleRows + 1] = roleAnchorRow
    roleCard.AddRow(roleSizeRow, roleAnchorRow)

    local roleXSlider = gui:CreateFormSlider(roleCard.frame, nil, -100, 100, 1, "roleIconOffsetX", indicators, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal pixel offset for the role icon from its anchor."],
    })
    local roleXRow = optionsAPI.BuildSettingRow(roleCard.frame, ns.L["X Offset"], roleXSlider)
    roleRows[#roleRows + 1] = roleXRow
    local roleYSlider = gui:CreateFormSlider(roleCard.frame, nil, -100, 100, 1, "roleIconOffsetY", indicators, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical pixel offset for the role icon from its anchor."],
    })
    local roleYRow = optionsAPI.BuildSettingRow(roleCard.frame, ns.L["Y Offset"], roleYSlider)
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
            description = string.format(ns.L["Show the %1$s indicator on this unit frame."], title),
        })
        local sizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 32, 1, sizeKey, indicators, refresh, { deferOnDrag = true }, {
            description = string.format(ns.L["Pixel size of the %1$s indicator."], title),
        })
        local sizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Icon Size"], sizeSlider)
        controlledRows[#controlledRows + 1] = sizeRow
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["Enable"], enableCheckbox),
            sizeRow
        )

        local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, NINE_POINT_OPTIONS, anchorKey, indicators, refresh, {
            description = string.format(ns.L["Where on the frame the %1$s indicator is anchored. X/Y Offset below nudges it from this anchor point."], title),
        })
        local anchorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Anchor"], anchorDropdown)
        controlledRows[#controlledRows + 1] = anchorRow
        local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, offXKey, indicators, refresh, { deferOnDrag = true }, {
            description = string.format(ns.L["Horizontal pixel offset for the %1$s indicator from its anchor."], title),
        })
        local xOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["X Offset"], xOffsetSlider)
        controlledRows[#controlledRows + 1] = xOffsetRow
        card.AddRow(anchorRow, xOffsetRow)

        local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, offYKey, indicators, refresh, { deferOnDrag = true }, {
            description = string.format(ns.L["Vertical pixel offset for the %1$s indicator from its anchor."], title),
        })
        local yOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Y Offset"], yOffsetSlider)
        controlledRows[#controlledRows + 1] = yOffsetRow
        card.AddRow(yOffsetRow)

        UpdateRows()
        builder.CloseCard(card)
    end

    AddIndicatorCard(ns.L["Ready Check"], "showReadyCheck", "readyCheckSize", "readyCheckAnchor", "readyCheckOffsetX", "readyCheckOffsetY")
    AddIndicatorCard(ns.L["Resurrection"], "showResurrection", "resurrectionSize", "resurrectionAnchor", "resurrectionOffsetX", "resurrectionOffsetY")
    AddIndicatorCard(ns.L["Summon Pending"], "showSummonPending", "summonSize", "summonAnchor", "summonOffsetX", "summonOffsetY")
    AddIndicatorCard(ns.L["Leader Icon"], "showLeaderIcon", "leaderSize", "leaderAnchor", "leaderOffsetX", "leaderOffsetY")
    AddIndicatorCard(ns.L["Raid Target Marker"], "showTargetMarker", "targetMarkerSize", "targetMarkerAnchor", "targetMarkerOffsetX", "targetMarkerOffsetY")
    AddIndicatorCard(ns.L["Phase Icon"], "showPhaseIcon", "phaseSize", "phaseAnchor", "phaseOffsetX", "phaseOffsetY")

    return builder.Height()
end

local function RenderThreatSection(sectionHost, ctx)
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

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("appearance"))
    if not builder then
        return nil
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    builder.Header(ns.L["Threat"])
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
        description = ns.L["Outline the frame border when the unit has aggro on an NPC."],
    })
    local borderSizeSlider = gui:CreateFormSlider(threatCard.frame, nil, 1, 16, 1, "threatBorderSize", indicators, refresh, { deferOnDrag = true }, {
        description = ns.L["Pixel thickness of the threat border."],
    })
    local borderSizeRow = optionsAPI.BuildSettingRow(threatCard.frame, ns.L["Border Size"], borderSizeSlider)
    threatRows[#threatRows + 1] = borderSizeRow
    threatCard.AddRow(
        optionsAPI.BuildSettingRow(threatCard.frame, ns.L["Show Threat Border"], showThreatCheckbox),
        borderSizeRow
    )

    local threatColorPicker = gui:CreateFormColorPicker(threatCard.frame, nil, "threatColor", indicators, refresh, nil, {
        description = ns.L["Color used for the threat border and optional fill tint."],
    })
    local threatColorRow = optionsAPI.BuildSettingRow(threatCard.frame, ns.L["Threat Color"], threatColorPicker)
    threatRows[#threatRows + 1] = threatColorRow
    local threatFillSlider = gui:CreateFormSlider(threatCard.frame, nil, 0, 0.5, 0.05, "threatFillOpacity", indicators, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of a color tint applied across the health bar when the unit has aggro. Set to 0 to keep only the border."],
    })
    local threatFillRow = optionsAPI.BuildSettingRow(threatCard.frame, ns.L["Threat Fill Opacity"], threatFillSlider)
    threatRows[#threatRows + 1] = threatFillRow
    threatCard.AddRow(threatColorRow, threatFillRow)
    UpdateThreatRows()
    builder.CloseCard(threatCard)

    return builder.Height()
end

local function BuildSpecBucketOptions()
    local options = { { value = "*", text = ns.L["All Specs"] } }
    local currentSpecID
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    local currentIndex = GetSpecialization and GetSpecialization() or nil
    for index = 1, numSpecs do
        if GetSpecializationInfo then
            local specID, specName = GetSpecializationInfo(index)
            if specID then
                options[#options + 1] = {
                    value = specID,
                    text = specName or string.format(ns.L["Spec %1$s"], tostring(specID)),
                }
                if index == currentIndex then
                    currentSpecID = specID
                end
            end
        end
    end
    return options, currentSpecID
end

local function GetSelectedBucket(ctx, contextMode, defaultBucket)
    local state = ctx and ctx.state
    if type(state) ~= "table" then
        return defaultBucket
    end
    local store = state._aurasSelectedBucket
    if type(store) ~= "table" then
        store = {}
        state._aurasSelectedBucket = store
    end
    if store[contextMode] == nil then
        store[contextMode] = defaultBucket
    end
    return store[contextMode]
end

local function SetSelectedBucket(ctx, contextMode, bucketKey)
    local state = ctx and ctx.state
    if type(state) ~= "table" then
        return
    end
    local store = state._aurasSelectedBucket
    if type(store) ~= "table" then
        store = {}
        state._aurasSelectedBucket = store
    end
    store[contextMode] = bucketKey
end

local function ElementIndexKey(contextMode, bucketKey)
    return tostring(contextMode) .. "\0" .. tostring(bucketKey)
end

local function GetSelectedElementIndex(ctx, contextMode, bucketKey)
    local state = ctx and ctx.state
    if type(state) ~= "table" then
        return nil
    end
    local store = state._aurasSelectedElement
    if type(store) ~= "table" then
        return nil
    end
    return store[ElementIndexKey(contextMode, bucketKey)]
end

local function SetSelectedElementIndex(ctx, contextMode, bucketKey, index)
    local state = ctx and ctx.state
    if type(state) ~= "table" then
        return
    end
    local store = state._aurasSelectedElement
    if type(store) ~= "table" then
        store = {}
        state._aurasSelectedElement = store
    end
    store[ElementIndexKey(contextMode, bucketKey)] = (type(index) == "number" and index) or nil
end

local function RenderAurasSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local groupFrames = ResolveGroupFramesDB(ctx and ctx.options and ctx.options.contextMode)
    if not gui or not optionsAPI or not groupFrames then
        return nil
    end
    if not AurasEditor or type(AurasEditor.RenderAuras) ~= "function" then
        return RenderUnavailableLabel(sectionHost, ns.L["Aura settings unavailable."])
    end

    local auras = EnsureSubTable(groupFrames.contextDB, "auras")
    if not auras then
        return nil
    end
    local AuraModel = ns.QUI_GroupFramesAuraModel
    if AuraModel and AuraModel.EnsureSeeded then
        AuraModel.EnsureSeeded(auras, groupFrames.contextMode)
    end
    if type(auras.elements) ~= "table" then
        auras.elements = {}
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("auras"))
    if not builder then
        return nil
    end

    local specOptions = BuildSpecBucketOptions()
    local selectedBucket = GetSelectedBucket(ctx, groupFrames.contextMode, "*")
    local validBucket = false
    for _, option in ipairs(specOptions) do
        if option.value == selectedBucket then
            validBucket = true
            break
        end
    end
    if not validBucket then
        selectedBucket = "*"
        SetSelectedBucket(ctx, groupFrames.contextMode, selectedBucket)
    end

    local isSpecBucket = (selectedBucket ~= "*")
    local overrideOn = false
    if isSpecBucket and AuraModel and AuraModel.HasSpecOverride then
        overrideOn = AuraModel.HasSpecOverride(auras.elements, selectedBucket) and true or false
    end

    local refresh = function()
        RefreshGroupFrames(groupFrames.contextMode)
    end

    local refreshAuras = function()
        if _G.QUI_RefreshGroupFrames then
            _G.QUI_RefreshGroupFrames()
        end
        if _G.QUI_LayoutModeSyncHandle then
            _G.QUI_LayoutModeSyncHandle(NormalizeContextMode(groupFrames.contextMode) == "raid" and "raidFrames" or "partyFrames")
        end
        if _G.QUI_RefreshGroupFramePreview then
            _G.QUI_RefreshGroupFramePreview(NormalizeContextMode(groupFrames.contextMode), true, selectedBucket)
        end
    end

    builder.Header(ns.L["Auras"])
    builder.Description(string.format(ns.L["Buff/debuff strips and tracked auras on %1$s group frames. A spec either inherits the All Specs bucket or overrides it with its own — never both."], groupFrames.sourceLabel))

    if _G.QUI_RefreshGroupFramePreview then
        _G.QUI_RefreshGroupFramePreview(NormalizeContextMode(groupFrames.contextMode), true, selectedBucket)
    end

    local card = builder.Card()
    local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", auras, refresh, {
        description = ns.L["Master switch for all aura strips and tracked auras on these frames."],
    })
    local specDropdown = gui:CreateFormDropdown(card.frame, nil, specOptions, nil, nil, function(value)
        SetSelectedBucket(ctx, groupFrames.contextMode, value)
        ScheduleTabRepaint(ctx)
    end, {
        description = ns.L["Choose which spec to view. \"All Specs\" is the shared bucket; a specific spec either inherits it or overrides it."],
    })
    if specDropdown.SetValue then
        specDropdown:SetValue(selectedBucket, true)
    end
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Enable Auras"], enableCheckbox),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Editing Spec"], specDropdown)
    )

    local debuffBorderCheckbox = gui:CreateFormCheckbox(card.frame, nil, "debuffBorderByType", auras, refresh, {
        description = ns.L["Color debuff icon borders by dispel type (Magic, Curse, Poison, Disease, Bleed). Reuses your Dispel Overlay colors. Works in combat."],
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Debuff Border by Type"], debuffBorderCheckbox))

    if isSpecBucket then
        local overrideToggle = gui:CreateFormCheckbox(card.frame, nil, nil, nil, function(val)
            if val then
                if AuraModel and AuraModel.EnableSpecOverride then
                    AuraModel.EnableSpecOverride(auras, selectedBucket)
                end
            else
                if AuraModel and AuraModel.DisableSpecOverride then
                    AuraModel.DisableSpecOverride(auras, selectedBucket)
                end
            end
            refresh()
            ScheduleTabRepaint(ctx)
        end, {
            description = ns.L["On: this spec uses its own strips/tracked auras (seeded from All Specs). Off: it inherits the All Specs bucket."],
        })
        if overrideToggle.SetValue then
            overrideToggle:SetValue(overrideOn, true)
        end
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Override All Specs"], overrideToggle))
    end
    builder.CloseCard(card)

    builder.Spacer(6)
    builder.Header(ns.L["Tracked Auras"])

    if isSpecBucket and not overrideOn then
        builder.Description(ns.L["This spec inherits the All Specs settings. Turn on \"Override All Specs\" above to give it its own strips and tracked auras."])
        return builder.Height()
    end

    local forcedIndex = GetSelectedElementIndex(ctx, groupFrames.contextMode, selectedBucket)
    local editorMounted = false
    local editorHeight

    RenderEmbeddedEditorSection(sectionHost, builder, function(editorHost)
        return AurasEditor.RenderAuras(editorHost, auras, selectedBucket, function()
            refreshAuras()
        end, {
            forceSelectedIndex = forcedIndex,
            capabilities = {
                elementTypes        = { filterStrip = true, tracked = true, missingRaidBuff = true },
                trackedDisplayTypes = { icon = true, square = true, bar = true, healthTint = true, border = true },
                cancelEligible      = false,
                maxStripElements    = 4,
                allowSpecOverride   = true,
                defaultBucketFn     = AuraDefaults and function()
                    return AuraDefaults.DefaultStripBucket(groupFrames.contextMode)
                end or nil,
                unitPolarity        = "friendly",
            },
            onSelectionChanged = function(index)
                SetSelectedElementIndex(ctx, groupFrames.contextMode, selectedBucket, index)
            end,
            onLayoutChanged = function(height)
                if type(height) ~= "number" then
                    return
                end
                local previousHeight = editorHeight
                editorHeight = height
                if not editorMounted or previousHeight == nil or previousHeight == height then
                    return
                end
                local sectionHeight = ctx.runtime
                    and ctx.runtime.sectionHeights
                    and ctx.runtime.sectionHeights.auras
                if type(ctx.ResizeSection) == "function" and type(sectionHeight) == "number" then
                    ctx:ResizeSection("auras", sectionHeight + (height - previousHeight))
                else
                    ScheduleTabRepaint(ctx)
                end
            end,
        })
    end, {
        minHeight = 1,
    })
    editorMounted = true

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

local function CreateMultiSectionTabFeature(id, sectionDefs)
    local sectionIds = {}
    local sections = {}
    for i, def in ipairs(sectionDefs) do
        sectionIds[i] = def.id
        sections[i] = Schema.Section({
            id = def.id,
            kind = "custom",
            minHeight = def.minHeight,
            render = def.render,
        })
    end
    return Schema.Feature({
        id = id,
        surfaces = {
            groupFrameTab = {
                sections = sectionIds,
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = sections,
    })
end

local GENERAL_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesGeneralTab", {
    { id = "enable", minHeight = 42, render = RenderGeneralEnableSection },
    { id = "rangepet", minHeight = 140, render = RenderRangePetSection },
    { id = "healer", minHeight = 140, render = RenderHealerSection },
    { id = "copySettings", minHeight = 164, render = RenderGeneralCopySettingsSection },
})

local GENERAL_PARTY_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesGeneralPartyTab", {
    { id = "enable", minHeight = 42, render = RenderGeneralEnableSection },
    { id = "rangepet", minHeight = 140, render = RenderRangePetSection },
    { id = "partyTargets", minHeight = 200, render = RenderPartyTargetsSection },
    { id = "healer", minHeight = 140, render = RenderHealerSection },
    { id = "copySettings", minHeight = 164, render = RenderGeneralCopySettingsSection },
})

local APPEARANCE_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesAppearanceTab", {
    { id = "appearance", minHeight = 160, render = RenderAppearanceSection },
    { id = "name", minHeight = 140, render = RenderNameSection },
    { id = "groupNumber", minHeight = 140, render = RenderGroupNumberSection },
    { id = "power", minHeight = 140, render = RenderPowerSection },
    { id = "threat", minHeight = 140, render = RenderThreatSection },
    { id = "dispelOverlay", minHeight = 140, render = RenderDispelOverlaySection },
})

local APPEARANCE_PARTY_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesAppearancePartyTab", {
    { id = "appearance", minHeight = 160, render = RenderAppearanceSection },
    { id = "name", minHeight = 140, render = RenderNameSection },
    { id = "level", minHeight = 150, render = RenderLevelSection },
    { id = "power", minHeight = 140, render = RenderPowerSection },
    { id = "threat", minHeight = 140, render = RenderThreatSection },
    { id = "dispelOverlay", minHeight = 140, render = RenderDispelOverlaySection },
})

local LAYOUT_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesLayoutTab", {
    { id = "layout", minHeight = 160, render = RenderLayoutSection },
    { id = "dimensions", minHeight = 140, render = RenderDimensionsSection },
})

local LAYOUT_RAID_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesLayoutRaidTab", {
    { id = "layout", minHeight = 160, render = RenderLayoutSection },
    { id = "spotlight", minHeight = 180, render = RenderSpotlightSection },
    { id = "dimensions", minHeight = 140, render = RenderDimensionsSection },
})

local HEALTH_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesHealthTab",
    "health",
    140,
    RenderHealthSection
)

local INDICATORS_TAB_FEATURE = CreateSingleSectionTabFeature(
    "groupFramesIndicatorsTab",
    "indicators",
    140,
    RenderIndicatorsSection
)

local AURAS_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesAurasTab", {
    { id = "auras", minHeight = 180, render = RenderAurasSection },
    { id = "targetedSpells", minHeight = 160, render = RenderTargetedSpellsSection },
})

local DISPEL_TAB_FEATURE = CreateMultiSectionTabFeature("groupFramesDispelTab", {
    { id = "dispelOverlay", minHeight = 140, render = RenderDispelOverlaySection },
})

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
    local feature = NormalizeContextMode(contextMode) == "party"
        and GENERAL_PARTY_TAB_FEATURE or GENERAL_TAB_FEATURE
    return RenderFeatureTab(feature, host, contextMode)
end

function GroupFramesSchema.RenderAppearanceTab(host, contextMode)
    local feature = NormalizeContextMode(contextMode) == "party"
        and APPEARANCE_PARTY_TAB_FEATURE or APPEARANCE_TAB_FEATURE
    return RenderFeatureTab(feature, host, contextMode)
end

function GroupFramesSchema.RenderLayoutTab(host, contextMode)
    local feature = NormalizeContextMode(contextMode) == "raid"
        and LAYOUT_RAID_TAB_FEATURE or LAYOUT_TAB_FEATURE
    return RenderFeatureTab(feature, host, contextMode)
end

function GroupFramesSchema.RenderHealthTab(host, contextMode)
    return RenderFeatureTab(HEALTH_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderIndicatorsTab(host, contextMode)
    return RenderFeatureTab(INDICATORS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderAurasTab(host, contextMode)
    return RenderFeatureTab(AURAS_TAB_FEATURE, host, contextMode)
end

function GroupFramesSchema.RenderDispelTab(host, contextMode)
    return RenderFeatureTab(DISPEL_TAB_FEATURE, host, contextMode)
end
