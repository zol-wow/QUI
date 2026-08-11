local ADDON_NAME, ns = ...
local QUI = QUI

local Settings = ns.Settings
local Renderer = Settings and Settings.Renderer
local Schema = Settings and Settings.Schema
if not Renderer or type(Renderer.RenderFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function" then
    return
end

local Helpers = ns.Helpers

local NameplatesSchema = ns.QUI_NameplatesSettingsSchema or {}
ns.QUI_NameplatesSettingsSchema = NameplatesSchema

local HEADER_GAP = 26
local SECTION_BOTTOM_PAD = 10
local DESCRIPTION_TEXT_COLOR = { 0.5, 0.5, 0.5, 1 }

local HEALTH_TEXT_STYLE_OPTIONS = {
    { value = "percent", text = ns.L["Percentage"] },
    { value = "absolute", text = ns.L["Absolute"] },
    { value = "both", text = ns.L["Both"] },
    { value = "none", text = ns.L["None"] },
}
local HEALTH_TEXT_PRECISION_OPTIONS = {
    { value = 0, text = ns.L["Whole Numbers"] },
    { value = 1, text = ns.L["One Decimal"] },
}
local HEALTH_TEXT_BOTH_FORMAT_OPTIONS = {
    { value = "bar", text = "1.4M | 65%" },
    { value = "paren", text = "1.4M (65%)" },
    { value = "dash", text = "1.4M - 65%" },
    { value = "space", text = "1.4M 65%" },
}
local RAID_MARKER_POSITION_OPTIONS = {
    { value = "TOPRIGHT", text = ns.L["Top Right"] },
    { value = "TOP", text = ns.L["Top"] },
    { value = "LEFT", text = ns.L["Left"] },
    { value = "RIGHT", text = ns.L["Right"] },
}
local TARGET_STYLE_OPTIONS = {
    { value = "wash", text = ns.L["Glow Wash"] },
    { value = "arrows", text = ns.L["Arrows"] },
    { value = "brackets", text = ns.L["Brackets"] },
    { value = "glowline", text = ns.L["Underline Glow"] },
}
local FONT_OUTLINE_OPTIONS = {
    { value = "OUTLINE", text = ns.L["Outline"] },
    { value = "THICKOUTLINE", text = ns.L["Thick Outline"] },
    { value = "", text = ns.L["None"] },
}
local QUEST_ICON_POSITION_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "RIGHT", text = ns.L["Right"] },
    { value = "TOP", text = ns.L["Top"] },
}
local FRIENDLY_INSTANCE_OPTIONS = {
    { value = "never", text = ns.L["Never"] },
    { value = "nameonly", text = ns.L["Name Only"] },
    { value = "always", text = ns.L["Always"] },
}

local RENDER_MODE_OPTIONS = {
    { value = "bars", text = ns.L["Health Bars"] },
    { value = "simplified", text = ns.L["Simplified"] },
    { value = "nameonly", text = ns.L["Name Only"] },
}

local ANCHOR_POINT_OPTIONS = {
    { value = "TOPLEFT", text = ns.L["Top Left"] },
    { value = "TOP", text = ns.L["Top"] },
    { value = "TOPRIGHT", text = ns.L["Top Right"] },
    { value = "LEFT", text = ns.L["Left"] },
    { value = "CENTER", text = ns.L["Center"] },
    { value = "RIGHT", text = ns.L["Right"] },
    { value = "BOTTOMLEFT", text = ns.L["Bottom Left"] },
    { value = "BOTTOM", text = ns.L["Bottom"] },
    { value = "BOTTOMRIGHT", text = ns.L["Bottom Right"] },
}

local JUSTIFY_OPTIONS = {
    { value = "LEFT", text = ns.L["Left"] },
    { value = "CENTER", text = ns.L["Center"] },
    { value = "RIGHT", text = ns.L["Right"] },
}

local TAB_SEARCH_CONTEXTS = {
    general = { subTabIndex = 1, subTabName = "General" },
    visibility = { subTabIndex = 2, subTabName = "Visibility" },
    frame = { subTabIndex = 3, subTabName = "Frame" },
    text = { subTabIndex = 4, subTabName = "Text" },
    indicators = { subTabIndex = 5, subTabName = "Indicators" },
    auras = { subTabIndex = 6, subTabName = "Auras" },
    castbars = { subTabIndex = 7, subTabName = "Castbar" },
    colors = { subTabIndex = 8, subTabName = "Colors" },
}
local NAMEPLATES_SEARCH_TAB_INDEX = 22
local NAMEPLATES_SEARCH_TILE_ID = "nameplates"
local NAMEPLATES_SEARCH_FEATURE_ID = "nameplatesPage"
local NAMEPLATES_SEARCH_SUB_PAGE_INDEX = 1

local function GetGUI()
    return QUI and QUI.GUI or nil
end

local function GetOptionsAPI()
    return ns.QUI_Options
end

local function ResolveNameplatesDB()
    local profile = Helpers and Helpers.GetProfile and Helpers.GetProfile()
    local npdb = profile and profile.nameplates
    if type(npdb) ~= "table" then
        return nil
    end
    return npdb
end

local function ResolveTypeDB(typeKey)
    local npdb = ResolveNameplatesDB()
    if not npdb then
        return nil
    end
    local NP = ns.QUI_Nameplates
    if NP and NP.NormalizeTypes then
        NP.NormalizeTypes(npdb)
    end
    local types = npdb.types
    if type(types) ~= "table" then
        return nil
    end
    local plateType = NP and NP.PlateType
    local defaultKey = plateType and plateType.DEFAULT_KEY or "enemyNPC"
    if type(typeKey) == "string" and types[typeKey] then
        return types[typeKey]
    end
    return types[defaultKey]
end
NameplatesSchema.ResolveTypeDB = ResolveTypeDB

local function FillTableInPlace(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end
    for key in pairs(dst) do
        if src[key] == nil then
            dst[key] = nil
        end
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            FillTableInPlace(dst[key], value)
        else
            dst[key] = value
        end
    end
end

function NameplatesSchema.CopyTypeConfig(sourceKey, targetKey)
    if type(sourceKey) ~= "string" or type(targetKey) ~= "string" or sourceKey == targetKey then
        return false
    end
    local NP = ns.QUI_Nameplates
    local plateType = NP and NP.PlateType
    if not plateType or not plateType.KEYS[sourceKey] or not plateType.KEYS[targetKey] then
        return false
    end
    local npdb = ResolveNameplatesDB()
    if not npdb or not NP.NormalizeTypes then
        return false
    end
    NP.NormalizeTypes(npdb)
    local types = npdb.types
    if type(types) ~= "table" or not types[sourceKey] or not types[targetKey] then
        return false
    end
    FillTableInPlace(types[targetKey], types[sourceKey])
    return true
end

local function SetSearchContext(searchContext)
    local gui = GetGUI()
    if gui and type(gui.SetSearchContext) == "function" and type(searchContext) == "table" then
        gui:SetSearchContext(searchContext)
    end
end

local function CreateSearchContext(tabKey, typeKey)
    local context = TAB_SEARCH_CONTEXTS[tabKey] or TAB_SEARCH_CONTEXTS.display
    local SearchRoute = ns.Settings and ns.Settings.SearchRoute
    local searchContext = {
        tabIndex = NAMEPLATES_SEARCH_TAB_INDEX,
        tabName = "Nameplates",
        subTabIndex = context.subTabIndex,
        subTabName = context.subTabName,
        tileId = NAMEPLATES_SEARCH_TILE_ID,
        subPageIndex = NAMEPLATES_SEARCH_SUB_PAGE_INDEX,
        featureId = NAMEPLATES_SEARCH_FEATURE_ID,
        category = "frames",
        surfaceTabKey = tabKey,
        surfaceTypeKey = typeKey,
    }
    if SearchRoute and type(SearchRoute.Apply) == "function" then
        return SearchRoute.Apply(searchContext)
    end
    return searchContext
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
            return nil, nil
        end

        local originY = y
        local header = optionsAPI.CreateAccentDotLabel(sectionHost, text, y)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, y)
        header:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, y)
        y = y - HEADER_GAP
        return header, originY
    end

    local function AddParagraph(text, color)
        if type(text) ~= "string" or text == "" then
            return
        end

        local description = sectionHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        description:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, y)
        description:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, y)
        description:SetJustifyH("LEFT")
        description:SetText(text)
        description:SetTextColor(color[1], color[2], color[3], color[4])
        local height = 14
        if description.GetStringHeight then
            height = math.max(14, math.ceil(description:GetStringHeight() or 14))
        end
        y = y - height - 4
        return description
    end

    function builder.Description(text)
        return AddParagraph(text, DESCRIPTION_TEXT_COLOR)
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

local function RefreshNameplates()
    if ns.QUI_RefreshNameplates then
        ns.QUI_RefreshNameplates()
    end
    if ns.QUI_RefreshNameplatePreview then
        ns.QUI_RefreshNameplatePreview()
    end
end

local function InvalidateTabBodies()
    local surface = ns.QUI_NameplatesSettingsSurface
    if surface and type(surface.InvalidateTabBodies) == "function" then
        surface.InvalidateTabBodies()
    end
end

local function RefreshNameplatesAndRepaint()
    RefreshNameplates()
    local surface = ns.QUI_NameplatesSettingsSurface
    if surface and type(surface.RepaintActiveTab) == "function" then
        surface.RepaintActiveTab()
    end
end

local function ScheduleSectionReflow(ctx)
    if type(ctx) ~= "table" or type(ctx.RerenderFeature) ~= "function" then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            ctx:RerenderFeature()
        end)
    else
        ctx:RerenderFeature()
    end
end

local function RenderEnableSection(sectionHost, ctx)
    local gui = GetGUI()
    local npdb = ResolveNameplatesDB()
    if not gui or not npdb then
        return nil
    end

    PrepareSectionHost(sectionHost, ctx)
    SetSearchContext(CreateSearchContext("general"))

    local enableCheck = gui:CreateFormCheckbox(
        sectionHost,
        ns.L["Enable QUI Nameplates (Req. Reload)"],
        "enabled",
        npdb,
        function()
            RefreshNameplates()
            gui:ShowConfirmation({
                title = ns.L["Reload UI?"],
                message = ns.L["Nameplates load at login: changing the enabled state requires a UI reload to install or remove the nameplate hooks."],
                acceptText = ns.L["Reload"],
                cancelText = ns.L["Later"],
                onAccept = function()
                    QUI:SafeReload()
                end,
            })
        end,
        { description = ns.L["Replace Blizzard's nameplates with QUI's custom nameplates. Requires a UI reload to take full effect."] }
    )
    enableCheck:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -4)
    enableCheck:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -4)

    return 64
end

local function AddTextPositionRows(gui, optionsAPI, card, tbl, refresh, gatedRows)
    local pointDropdown = gui:CreateFormDropdown(card.frame, nil, ANCHOR_POINT_OPTIONS, "point", tbl, refresh, {
        description = ns.L["Which point of the text is pinned."],
    })
    local relPointDropdown = gui:CreateFormDropdown(card.frame, nil, ANCHOR_POINT_OPTIONS, "relativePoint", tbl, refresh, {
        description = ns.L["Which point of the health bar the text pins to."],
    })
    local pointRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Anchor"], pointDropdown)
    local relPointRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Attach To"], relPointDropdown)
    card.AddRow(pointRow, relPointRow)

    local offsetXSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetX", tbl, refresh, { deferOnDrag = true }, {
        description = ns.L["Horizontal offset from the anchor, in pixels."],
    })
    local offsetYSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetY", tbl, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical offset from the anchor, in pixels."],
    })
    local offsetXRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Offset X"], offsetXSlider)
    local offsetYRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Offset Y"], offsetYSlider)
    card.AddRow(offsetXRow, offsetYRow)

    local justifyDropdown = gui:CreateFormDropdown(card.frame, nil, JUSTIFY_OPTIONS, "justify", tbl, refresh, {
        description = ns.L["Horizontal alignment of the text."],
    })
    local justifyRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Justify"], justifyDropdown)
    card.AddRow(justifyRow)

    if gatedRows then
        gatedRows[#gatedRows + 1] = pointRow
        gatedRows[#gatedRows + 1] = relPointRow
        gatedRows[#gatedRows + 1] = offsetXRow
        gatedRows[#gatedRows + 1] = offsetYRow
        gatedRows[#gatedRows + 1] = justifyRow
    end
end

local function RenderHealthSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local health = EnsureSubTable(npdb, "health")
    if not health then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("frame", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Health Bar"])
    builder.Description(ns.L["Bar dimensions and styling. The hitbox below scales relative to these dimensions."])

    local barCard = builder.Card()
    local widthSlider = gui:CreateFormSlider(barCard.frame, nil, 60, 300, 1, "width", health, refresh, { deferOnDrag = true }, {
        description = ns.L["Health bar width in pixels."],
    })
    local heightSlider = gui:CreateFormSlider(barCard.frame, nil, 4, 40, 1, "height", health, refresh, { deferOnDrag = true }, {
        description = ns.L["Health bar height in pixels."],
    })
    barCard.AddRow(
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Width"], widthSlider),
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Height"], heightSlider)
    )

    local textureDropdown = gui:CreateFormDropdown(barCard.frame, nil, optionsAPI.GetTextureList(), "texture", health, refresh, {
        description = ns.L["Statusbar texture used for the health bar. The cast bar inherits it unless given its own."],
    })
    local borderSlider = gui:CreateFormSlider(barCard.frame, nil, 0, 4, 1, "borderSize", health, refresh, { deferOnDrag = true }, {
        description = ns.L["Pixel thickness of the plate border. 0 hides it."],
    })
    barCard.AddRow(
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Texture"], textureDropdown),
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Border Size"], borderSlider)
    )

    local borderColorPicker = gui:CreateFormColorPicker(barCard.frame, nil, "borderColor", health, refresh, { noAlpha = true }, {
        description = ns.L["Border color for the health and cast bars."],
    })
    local smoothToggle = gui:CreateFormCheckbox(barCard.frame, nil, "smooth", health, refresh, {
        description = ns.L["Animate health bar changes instead of snapping to the new value."],
    })
    barCard.AddRow(
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Border Color"], borderColorPicker),
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Smooth Health"], smoothToggle)
    )

    local powerBar = EnsureSubTable(npdb, "powerBar")
    if powerBar then
        local powerToggle = gui:CreateFormCheckbox(barCard.frame, nil, "enabled", powerBar, refresh, {
            description = ns.L["Thin resource bar under the health bar on units that have one."],
        })
        local powerHeightSlider = gui:CreateFormSlider(barCard.frame, nil, 3, 14, 1, "height", powerBar, refresh, { deferOnDrag = true }, {
            description = ns.L["Height of the enemy resource bar in pixels."],
        })
        barCard.AddRow(
            optionsAPI.BuildSettingRow(barCard.frame, ns.L["Enemy Power Bar"], powerToggle),
            optionsAPI.BuildSettingRow(barCard.frame, ns.L["Power Bar Height"], powerHeightSlider)
        )

        local manaOnlyToggle = gui:CreateFormCheckbox(barCard.frame, nil, "manaOnly", powerBar, refresh, {
            description = ns.L["Only show the bar on mana users. Turn this off to show every resource type."],
        })
        barCard.AddRow(
            optionsAPI.BuildSettingRow(barCard.frame, ns.L["Mana Users Only"], manaOnlyToggle)
        )
    end

    local font = EnsureSubTable(npdb, "font")
    if font then
        local fontFaceOptions = { { value = "", text = ns.L["Suite Font"] } }
        for _, entry in ipairs(optionsAPI.GetFontList()) do
            fontFaceOptions[#fontFaceOptions + 1] = entry
        end
        local fontFaceDropdown = gui:CreateFormDropdown(barCard.frame, nil, fontFaceOptions, "face", font, refresh, {
            description = ns.L["Font used by every nameplate text. Suite Font follows the global font setting."],
        })
        local fontOutlineDropdown = gui:CreateFormDropdown(barCard.frame, nil, FONT_OUTLINE_OPTIONS, "outline", font, refresh, {
            description = ns.L["Outline style applied to every nameplate text."],
        })
        barCard.AddRow(
            optionsAPI.BuildSettingRow(barCard.frame, ns.L["Nameplate Font"], fontFaceDropdown),
            optionsAPI.BuildSettingRow(barCard.frame, ns.L["Nameplate Font Outline"], fontOutlineDropdown)
        )
    end

    local bgColorPicker = gui:CreateFormColorPicker(barCard.frame, nil, "bgColor", health, refresh, { noAlpha = true }, {
        description = ns.L["Background color behind the health fill."],
    })
    local bgAlphaSlider = gui:CreateFormSlider(barCard.frame, nil, 0, 1, 0.05, "bgAlpha", health, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the health bar background."],
    })
    barCard.AddRow(
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Background Color"], bgColorPicker),
        optionsAPI.BuildSettingRow(barCard.frame, ns.L["Background Opacity"], bgAlphaSlider)
    )
    builder.CloseCard(barCard)

    return builder.Height()
end

local function RenderHealthTextSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local healthText = EnsureSubTable(npdb, "healthText")
    if not healthText then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("text", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Health Text"])
    local textCard = builder.Card()
    local textRows = {}
    local function UpdateTextRows()
        local alpha = healthText.enabled ~= false and 1.0 or 0.4
        for _, row in ipairs(textRows) do
            row:SetAlpha(alpha)
        end
    end

    local textToggle = gui:CreateFormCheckbox(textCard.frame, nil, "enabled", healthText, function()
        refresh()
        UpdateTextRows()
    end, {
        description = ns.L["Show a health value on the bar."],
    })
    local styleDropdown = gui:CreateFormDropdown(textCard.frame, nil, HEALTH_TEXT_STYLE_OPTIONS, "style", healthText, refresh, {
        description = ns.L["Percentage, absolute value, or both."],
    })
    local styleRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Style"], styleDropdown)
    textRows[#textRows + 1] = styleRow
    textCard.AddRow(
        optionsAPI.BuildSettingRow(textCard.frame, ns.L["Show Health Text"], textToggle),
        styleRow
    )

    local textSizeSlider = gui:CreateFormSlider(textCard.frame, nil, 6, 24, 1, "size", healthText, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size of the health text."],
    })
    local textSizeRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Font Size"], textSizeSlider)
    textRows[#textRows + 1] = textSizeRow
    local hidePercentCheckbox = gui:CreateFormCheckbox(textCard.frame, nil, "hidePercentSymbol", healthText, refresh, {
        description = ns.L["Drop the % symbol from percentage health text."],
    })
    local hidePercentRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Hide Percent Symbol"], hidePercentCheckbox)
    textRows[#textRows + 1] = hidePercentRow
    textCard.AddRow(textSizeRow, hidePercentRow)

    local textColorPicker = gui:CreateFormColorPicker(textCard.frame, nil, "color", healthText, refresh, { noAlpha = true }, {
        description = ns.L["Color of the health text."],
    })
    local textColorRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Text Color"], textColorPicker)
    textRows[#textRows + 1] = textColorRow
    local precisionDropdown = gui:CreateFormDropdown(textCard.frame, nil, HEALTH_TEXT_PRECISION_OPTIONS, "precision", healthText, refresh, {
        description = ns.L["Decimal places on percentage health text."],
    })
    local precisionRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Percent Precision"], precisionDropdown)
    textRows[#textRows + 1] = precisionRow
    textCard.AddRow(textColorRow, precisionRow)

    local bothFormatDropdown = gui:CreateFormDropdown(textCard.frame, nil, HEALTH_TEXT_BOTH_FORMAT_OPTIONS, "bothFormat", healthText, refresh, {
        description = ns.L["Separator between the value and the percentage when the style shows both."],
    })
    local bothFormatRow = optionsAPI.BuildSettingRow(textCard.frame, ns.L["Both Style Format"], bothFormatDropdown)
    textRows[#textRows + 1] = bothFormatRow
    textCard.AddRow(bothFormatRow)
    AddTextPositionRows(gui, optionsAPI, textCard, healthText, refresh, textRows)
    UpdateTextRows()
    builder.CloseCard(textCard)

    return builder.Height()
end

local function RenderNameSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local name = EnsureSubTable(npdb, "name")
    if not name then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("text", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Name"])
    local card = builder.Card()
    local nameRows = {}
    local function UpdateNameRows()
        local alpha = name.enabled ~= false and 1.0 or 0.4
        for _, row in ipairs(nameRows) do
            row:SetAlpha(alpha)
        end
    end

    local nameToggle = gui:CreateFormCheckbox(card.frame, nil, "enabled", name, function()
        refresh()
        UpdateNameRows()
    end, {
        description = ns.L["Show the unit name above the health bar."],
    })
    local nameSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, "size", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size of the name text."],
    })
    local nameSizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Font Size"], nameSizeSlider)
    nameRows[#nameRows + 1] = nameSizeRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Name"], nameToggle),
        nameSizeRow
    )

    local classColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "classColorPlayers", name, refresh, {
        description = ns.L["Color enemy player names by class."],
    })
    local classColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Class Color Players"], classColorCheckbox)
    nameRows[#nameRows + 1] = classColorRow
    local nameColorPicker = gui:CreateFormColorPicker(card.frame, nil, "color", name, refresh, { noAlpha = true }, {
        description = ns.L["Name color. Class coloring takes precedence for enemy players when it is enabled."],
    })
    local nameColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Name Color"], nameColorPicker)
    nameRows[#nameRows + 1] = nameColorRow
    card.AddRow(classColorRow, nameColorRow)

    local truncateSlider = gui:CreateFormSlider(card.frame, nil, 8, 40, 1, "truncateLength", name, refresh, { deferOnDrag = true }, {
        description = ns.L["Longest name shown before it is cut short."],
    })
    local truncateRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Max Name Length"], truncateSlider)
    nameRows[#nameRows + 1] = truncateRow
    card.AddRow(truncateRow)

    local npcTitle = EnsureSubTable(npdb, "npcTitle")
    if npcTitle then
        local titleToggle = gui:CreateFormCheckbox(card.frame, nil, "enabled", npcTitle, refresh, {
            description = ns.L["Show the NPC's title line under the name. Open world only."],
        })
        local titleSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 16, 1, "size", npcTitle, refresh, { deferOnDrag = true }, {
            description = ns.L["Font size of the NPC title."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["NPC Title"], titleToggle),
            optionsAPI.BuildSettingRow(card.frame, ns.L["NPC Title Size"], titleSizeSlider)
        )

        local titleColorPicker = gui:CreateFormColorPicker(card.frame, nil, "color", npcTitle, refresh, { noAlpha = true }, {
            description = ns.L["Color of the NPC title."],
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, ns.L["NPC Title Color"], titleColorPicker)
        )
    end
    AddTextPositionRows(gui, optionsAPI, card, name, refresh, nameRows)
    UpdateNameRows()
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderCastbarSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local castbar = EnsureSubTable(npdb, "castbar")
    if not castbar then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("castbars", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Cast Bar"])
    builder.Description(ns.L["Cast bar below the health bar. Cast state colors live on the Colors tab."])
    local card = builder.Card()
    local castRows = {}
    local function UpdateCastRows()
        local alpha = castbar.enabled ~= false and 1.0 or 0.4
        for _, row in ipairs(castRows) do
            row:SetAlpha(alpha)
        end
    end
    local function AddGatedRow(label, widget)
        local row = optionsAPI.BuildSettingRow(card.frame, label, widget)
        castRows[#castRows + 1] = row
        return row
    end

    local enableToggle = gui:CreateFormCheckbox(card.frame, nil, "enabled", castbar, function()
        refresh()
        UpdateCastRows()
    end, {
        description = ns.L["Show a cast bar on enemy nameplates."],
    })
    local heightSlider = gui:CreateFormSlider(card.frame, nil, 4, 40, 1, "height", castbar, refresh, { deferOnDrag = true }, {
        description = ns.L["Cast bar height in pixels."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Cast Bar"], enableToggle),
        AddGatedRow(ns.L["Height"], heightSlider)
    )

    local gapSlider = gui:CreateFormSlider(card.frame, nil, -10, 20, 1, "gap", castbar, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical gap between the cast bar and the health bar."],
    })
    local iconToggle = gui:CreateFormCheckbox(card.frame, nil, "showIcon", castbar, refresh, {
        description = ns.L["Show the spell icon beside the cast bar."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Gap"], gapSlider),
        AddGatedRow(ns.L["Show Icon"], iconToggle)
    )

    local castTextureOptions = { { value = "", text = ns.L["Inherit Health Bar Texture"] } }
    for _, entry in ipairs(optionsAPI.GetTextureList()) do
        castTextureOptions[#castTextureOptions + 1] = entry
    end
    local castTextureDropdown = gui:CreateFormDropdown(card.frame, nil, castTextureOptions, "texture", castbar, refresh, {
        description = ns.L["Statusbar texture for the cast bar. Inherit uses the health bar texture."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Cast Bar Texture"], castTextureDropdown)
    )

    local timerToggle = gui:CreateFormCheckbox(card.frame, nil, "showTimer", castbar, refresh, {
        description = ns.L["Show the remaining cast time."],
    })
    local spellNameToggle = gui:CreateFormCheckbox(card.frame, nil, "showSpellName", castbar, refresh, {
        description = ns.L["Show the name of the spell being cast."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Show Timer"], timerToggle),
        AddGatedRow(ns.L["Show Spell Name"], spellNameToggle)
    )

    local castTargetToggle = gui:CreateFormCheckbox(card.frame, nil, "showCastTarget", castbar, refresh, {
        description = ns.L["Show who the cast is aimed at, under the cast bar."],
    })
    local castTargetSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 18, 1, "castTargetSize", castbar, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size of the cast target name."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Show Cast Target"], castTargetToggle),
        AddGatedRow(ns.L["Cast Target Size"], castTargetSizeSlider)
    )

    local interruptTintToggle = gui:CreateFormCheckbox(card.frame, nil, "interruptReadyTint", castbar, refresh, {
        description = ns.L["Tint interruptible casts while your own interrupt is off cooldown."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Interrupt Ready Tint"], interruptTintToggle)
    )

    local nameSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, "nameSize", castbar, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size of the spell name text."],
    })
    local timerSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 24, 1, "timerSize", castbar, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size of the cast timer text."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Spell Name Size"], nameSizeSlider),
        AddGatedRow(ns.L["Timer Size"], timerSizeSlider)
    )

    local holdSlider = gui:CreateFormSlider(card.frame, nil, 0, 3, 0.1, "interruptedHoldTime", castbar, refresh, { deferOnDrag = true }, {
        description = ns.L["Seconds the interrupted state stays visible before the cast bar hides."],
    })
    card.AddRow(AddGatedRow(ns.L["Interrupted Hold Time"], holdSlider))

    local kickTickToggle = gui:CreateFormCheckbox(card.frame, nil, "kickTick", castbar, refresh, {
        description = ns.L["Mark where your interrupt comes off cooldown on the cast timeline. The marker converges on the cast edge as your kick becomes ready."],
    })
    local liftToggle = gui:CreateFormCheckbox(card.frame, nil, "liftOverlay", castbar, refresh, {
        description = ns.L["Render cast bars above neighboring nameplates so stacked plates never cover an active cast."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Interrupt Ready Tick"], kickTickToggle),
        AddGatedRow(ns.L["Lift Above Other Plates"], liftToggle)
    )
    UpdateCastRows()
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderAbsorbsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local absorbs = EnsureSubTable(npdb, "absorbs")
    if not absorbs then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("frame", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Absorbs"])
    local absorbCard = builder.Card()
    local absorbRows = {}
    local function UpdateAbsorbRows()
        local alpha = absorbs.enabled ~= false and 1.0 or 0.4
        for _, row in ipairs(absorbRows) do
            row:SetAlpha(alpha)
        end
    end

    local absorbToggle = gui:CreateFormCheckbox(absorbCard.frame, nil, "enabled", absorbs, function()
        refresh()
        UpdateAbsorbRows()
    end, {
        description = ns.L["Show an absorb shield overlay on the health bar."],
    })
    local absorbColorPicker = gui:CreateFormColorPicker(absorbCard.frame, nil, "color", absorbs, refresh, { noAlpha = true }, {
        description = ns.L["Tint of the absorb overlay."],
    })
    local absorbColorRow = optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Absorb Color"], absorbColorPicker)
    absorbRows[#absorbRows + 1] = absorbColorRow
    absorbCard.AddRow(
        optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Show Absorbs"], absorbToggle),
        absorbColorRow
    )

    local absorbOpacitySlider = gui:CreateFormSlider(absorbCard.frame, nil, 0, 1, 0.05, "opacity", absorbs, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the absorb overlay."],
    })
    local absorbOpacityRow = optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Absorb Opacity"], absorbOpacitySlider)
    absorbRows[#absorbRows + 1] = absorbOpacityRow
    local absorbTextToggle = gui:CreateFormCheckbox(absorbCard.frame, nil, "showText", absorbs, refresh, {
        description = ns.L["Show the absorb amount as text on the health bar."],
    })
    local absorbTextRow = optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Show Absorb Text"], absorbTextToggle)
    absorbRows[#absorbRows + 1] = absorbTextRow
    absorbCard.AddRow(absorbOpacityRow, absorbTextRow)

    local absorbTextSizeSlider = gui:CreateFormSlider(absorbCard.frame, nil, 6, 18, 1, "textSize", absorbs, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size of the absorb text."],
    })
    local absorbTextSizeRow = optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Absorb Text Size"], absorbTextSizeSlider)
    absorbRows[#absorbRows + 1] = absorbTextSizeRow
    absorbCard.AddRow(absorbTextSizeRow)

    local healPrediction = EnsureSubTable(npdb, "healPrediction")
    if healPrediction then
        local healToggle = gui:CreateFormCheckbox(absorbCard.frame, nil, "enabled", healPrediction, refresh, {
            description = ns.L["Show incoming heals as a bar segment past the current health."],
        })
        local healColorPicker = gui:CreateFormColorPicker(absorbCard.frame, nil, "color", healPrediction, refresh, { noAlpha = true }, {
            description = ns.L["Tint of the incoming-heal segment."],
        })
        absorbCard.AddRow(
            optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Heal Prediction"], healToggle),
            optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Heal Prediction Color"], healColorPicker)
        )

        local healOpacitySlider = gui:CreateFormSlider(absorbCard.frame, nil, 0, 1, 0.05, "opacity", healPrediction, refresh, { deferOnDrag = true }, {
            description = ns.L["Opacity of the incoming-heal segment."],
        })
        absorbCard.AddRow(
            optionsAPI.BuildSettingRow(absorbCard.frame, ns.L["Heal Prediction Opacity"], healOpacitySlider)
        )
    end
    UpdateAbsorbRows()
    builder.CloseCard(absorbCard)

    return builder.Height()
end

local function RenderExtrasSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local raidMarker = EnsureSubTable(npdb, "raidMarker")
    if not raidMarker then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("indicators", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Raid Marker"])
    local markerCard = builder.Card()
    local markerRows = {}
    local function UpdateMarkerRows()
        local alpha = raidMarker.enabled ~= false and 1.0 or 0.4
        for _, row in ipairs(markerRows) do
            row:SetAlpha(alpha)
        end
    end

    local markerToggle = gui:CreateFormCheckbox(markerCard.frame, nil, "enabled", raidMarker, function()
        refresh()
        UpdateMarkerRows()
    end, {
        description = ns.L["Show the unit's raid target marker on the plate."],
    })
    local markerSizeSlider = gui:CreateFormSlider(markerCard.frame, nil, 8, 48, 1, "size", raidMarker, refresh, { deferOnDrag = true }, {
        description = ns.L["Raid marker icon size in pixels."],
    })
    local markerSizeRow = optionsAPI.BuildSettingRow(markerCard.frame, ns.L["Size"], markerSizeSlider)
    markerRows[#markerRows + 1] = markerSizeRow
    markerCard.AddRow(
        optionsAPI.BuildSettingRow(markerCard.frame, ns.L["Show Raid Marker"], markerToggle),
        markerSizeRow
    )

    local markerPositionDropdown = gui:CreateFormDropdown(markerCard.frame, nil, RAID_MARKER_POSITION_OPTIONS, "position", raidMarker, refresh, {
        description = ns.L["Where the raid marker sits relative to the health bar."],
    })
    local markerPositionRow = optionsAPI.BuildSettingRow(markerCard.frame, ns.L["Position"], markerPositionDropdown)
    markerRows[#markerRows + 1] = markerPositionRow
    markerCard.AddRow(markerPositionRow)
    UpdateMarkerRows()
    builder.CloseCard(markerCard)

    local questIcon = EnsureSubTable(npdb, "questIcon")
    if questIcon then
        builder.Spacer(14)
        builder.Header(ns.L["Quest Icon"])
        local questCard = builder.Card()
        local questRows = {}
        local function UpdateQuestRows()
            local alpha = questIcon.enabled == true and 1.0 or 0.4
            for _, row in ipairs(questRows) do
                row:SetAlpha(alpha)
            end
        end

        local questToggle = gui:CreateFormCheckbox(questCard.frame, nil, "enabled", questIcon, function()
            refresh()
            UpdateQuestRows()
        end, {
            description = ns.L["Show an icon on units that count toward one of your active quests."],
        })
        local questSizeSlider = gui:CreateFormSlider(questCard.frame, nil, 10, 32, 1, "size", questIcon, refresh, { deferOnDrag = true }, {
            description = ns.L["Quest icon size in pixels."],
        })
        local questSizeRow = optionsAPI.BuildSettingRow(questCard.frame, ns.L["Quest Icon Size"], questSizeSlider)
        questRows[#questRows + 1] = questSizeRow
        questCard.AddRow(
            optionsAPI.BuildSettingRow(questCard.frame, ns.L["Show Quest Icon"], questToggle),
            questSizeRow
        )

        local questPositionDropdown = gui:CreateFormDropdown(questCard.frame, nil, QUEST_ICON_POSITION_OPTIONS, "position", questIcon, refresh, {
            description = ns.L["Where the quest icon sits relative to the health bar."],
        })
        local questPositionRow = optionsAPI.BuildSettingRow(questCard.frame, ns.L["Quest Icon Position"], questPositionDropdown)
        questRows[#questRows + 1] = questPositionRow
        questCard.AddRow(questPositionRow)
        UpdateQuestRows()
        builder.CloseCard(questCard)
    end

    local pvpIcon = EnsureSubTable(npdb, "pvpIcon")
    if pvpIcon then
        builder.Spacer(14)
        builder.Header(ns.L["PvP Objective Icon"])
        local pvpCard = builder.Card()
        local pvpToggle = gui:CreateFormCheckbox(pvpCard.frame, nil, "enabled", pvpIcon, refresh, {
            description = ns.L["Mark flag, cart, orb and bounty carriers with Blizzard's objective icon."],
        })
        local pvpSizeSlider = gui:CreateFormSlider(pvpCard.frame, nil, 10, 36, 1, "size", pvpIcon, refresh, { deferOnDrag = true }, {
            description = ns.L["PvP objective icon size in pixels."],
        })
        pvpCard.AddRow(
            optionsAPI.BuildSettingRow(pvpCard.frame, ns.L["PvP Objective Icon"], pvpToggle),
            optionsAPI.BuildSettingRow(pvpCard.frame, ns.L["PvP Icon Size"], pvpSizeSlider)
        )
        builder.CloseCard(pvpCard)
    end

    return builder.Height()
end

local function RenderClassPowerSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local power = EnsureSubTable(npdb, "power")
    if not power then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("indicators", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Class Power"])
    builder.Description(ns.L["Your own combo points, charges or runes, shown under your current target's plate."])
    local card = builder.Card()
    local powerRows = {}
    local function UpdatePowerRows()
        local alpha = power.enabled == true and 1.0 or 0.4
        for _, row in ipairs(powerRows) do
            row:SetAlpha(alpha)
        end
    end

    local powerToggle = gui:CreateFormCheckbox(card.frame, nil, "enabled", power, function()
        refresh()
        UpdatePowerRows()
    end, {
        description = ns.L["Show your class resource pips beneath your target's plate."],
    })
    local powerSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 20, 1, "size", power, refresh, { deferOnDrag = true }, {
        description = ns.L["Size of each resource pip in pixels."],
    })
    local powerSizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Pip Size"], powerSizeSlider)
    powerRows[#powerRows + 1] = powerSizeRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Class Power"], powerToggle),
        powerSizeRow
    )

    local powerSpacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 10, 1, "spacing", power, refresh, { deferOnDrag = true }, {
        description = ns.L["Gap between resource pips in pixels."],
    })
    local powerSpacingRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Pip Spacing"], powerSpacingSlider)
    powerRows[#powerRows + 1] = powerSpacingRow
    local powerOffsetSlider = gui:CreateFormSlider(card.frame, nil, -30, 30, 1, "offsetY", power, refresh, { deferOnDrag = true }, {
        description = ns.L["Vertical offset of the pip row below the plate."],
    })
    local powerOffsetRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Pip Offset"], powerOffsetSlider)
    powerRows[#powerRows + 1] = powerOffsetRow
    card.AddRow(powerSpacingRow, powerOffsetRow)
    UpdatePowerRows()
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderLevelSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local level = EnsureSubTable(npdb, "level")
    if not level then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("text", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Level"])
    builder.Description(ns.L["Unit level beside the health bar, with an optional elite or rare marker."])
    local card = builder.Card()
    local levelRows = {}
    local function UpdateLevelRows()
        local alpha = level.enabled == true and 1.0 or 0.4
        for _, row in ipairs(levelRows) do
            row:SetAlpha(alpha)
        end
    end

    local levelToggle = gui:CreateFormCheckbox(card.frame, nil, "enabled", level, function()
        refresh()
        UpdateLevelRows()
    end, {
        description = ns.L["Show the unit level, colored by how dangerous the unit is for you."],
    })
    local levelSizeSlider = gui:CreateFormSlider(card.frame, nil, 6, 18, 1, "size", level, refresh, { deferOnDrag = true }, {
        description = ns.L["Font size of the level text."],
    })
    local levelSizeRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Level Font Size"], levelSizeSlider)
    levelRows[#levelRows + 1] = levelSizeRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show Level"], levelToggle),
        levelSizeRow
    )

    local classificationRows = {}
    local function UpdateClassificationRows()
        local alpha = level.showClassification == true and 1.0 or 0.4
        for _, row in ipairs(classificationRows) do
            row:SetAlpha(alpha)
        end
    end

    local classificationToggle = gui:CreateFormCheckbox(card.frame, nil, "showClassification", level, function()
        refresh()
        UpdateClassificationRows()
    end, {
        description = ns.L["Show an elite, rare or boss marker. Works with the level hidden."],
    })
    local classificationSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 32, 1, "classificationSize",
        level, refresh, { deferOnDrag = true }, {
            description = ns.L["Pixel size of the classification marker."],
        })
    local classificationSizeRow = optionsAPI.BuildSettingRow(card.frame,
        ns.L["Classification Marker Size"], classificationSizeSlider)
    classificationRows[#classificationRows + 1] = classificationSizeRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Classification Marker"], classificationToggle),
        classificationSizeRow
    )
    AddTextPositionRows(gui, optionsAPI, card, level, refresh, levelRows)
    UpdateLevelRows()
    UpdateClassificationRows()
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderAuraRowsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local auras = EnsureSubTable(npdb, "auras")
    if not auras then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("auras", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Auras"])
    builder.Description(ns.L["Aura icon rows above the nameplate. Each row's filtering, spell lists and text styling live in its own block below."])

    local masterCard = builder.Card()
    local masterToggle = gui:CreateFormCheckbox(masterCard.frame, nil, "enabled", auras, refresh, {
        description = ns.L["Master switch for all nameplate aura rows."],
    })
    local worldToggle = gui:CreateFormCheckbox(masterCard.frame, nil, "enableWorld", auras, refresh, {
        description = ns.L["Show aura rows in the open world."],
    })
    masterCard.AddRow(
        optionsAPI.BuildSettingRow(masterCard.frame, ns.L["Show Auras"], masterToggle),
        optionsAPI.BuildSettingRow(masterCard.frame, ns.L["Auras In World"], worldToggle)
    )

    local dungeonToggle = gui:CreateFormCheckbox(masterCard.frame, nil, "enableDungeon", auras, refresh, {
        description = ns.L["Show aura rows in dungeons."],
    })
    local raidToggle = gui:CreateFormCheckbox(masterCard.frame, nil, "enableRaid", auras, refresh, {
        description = ns.L["Show aura rows in raids."],
    })
    masterCard.AddRow(
        optionsAPI.BuildSettingRow(masterCard.frame, ns.L["Auras In Dungeons"], dungeonToggle),
        optionsAPI.BuildSettingRow(masterCard.frame, ns.L["Auras In Raids"], raidToggle)
    )
    builder.CloseCard(masterCard)

    local NP = ns.QUI_Nameplates
    local AurasEditor = ns.QUI_AuraElementsEditor
    if not (NP and AurasEditor and type(AurasEditor.RenderAuras) == "function") then
        return builder.Height()
    end

    local editorOriginY = -(builder.Height(0) or 0)
    local editorHost = CreateFrame("Frame", nil, sectionHost)
    editorHost:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, editorOriginY)
    editorHost:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, editorOriginY)
    editorHost:SetHeight(1)

    local mounted, mountHeight = false, nil
    local height = AurasEditor.RenderAuras(editorHost, auras, "*", RefreshNameplates, {
        capabilities = {
            elementTypes        = { filterStrip = true, tracked = true },
            trackedDisplayTypes = { icon = true, square = true, bar = true },
            unitPolarity        = "hostile",
            durationDecimals    = true,
            roleGate            = false,
            allowSpecOverride   = false,
            defaultBucketFn     = NP.DefaultNameplateBucket,
        },
        onLayoutChanged = function(newHeight)
            if type(newHeight) ~= "number" then return end
            local previous = mountHeight
            mountHeight = newHeight
            if not mounted or previous == nil or previous == newHeight then return end
            local sectionHeight = ctx.runtime and ctx.runtime.sectionHeights
                and ctx.runtime.sectionHeights.auraRows
            if type(ctx.ResizeSection) == "function" and type(sectionHeight) == "number" then
                ctx:ResizeSection("auraRows", sectionHeight + (newHeight - previous))
            end
        end,
    })
    mounted = true
    height = (type(height) == "number" and height > 0) and height or 1
    editorHost:SetHeight(height)
    return builder.Height() + height
end

local function RenderHitboxSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local cvars = EnsureSubTable(npdb, "cvars")
    if not cvars then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("frame"))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Hitbox & Stacking"])
    builder.Description(ns.L["The game allows only one clickable plate area for every nameplate, so it is derived from the LARGEST health bar across all six types and these scales apply on top of it. Editing them from any type tab changes every plate."])
    local card = builder.Card()

    local scaleXSlider = gui:CreateFormSlider(card.frame, nil, 50, 200, 5, "hitboxScaleX", cvars, refresh, { deferOnDrag = true }, {
        description = ns.L["Hitbox width as a percentage of the health bar width."],
    })
    local scaleYSlider = gui:CreateFormSlider(card.frame, nil, 50, 200, 5, "hitboxScaleY", cvars, refresh, { deferOnDrag = true }, {
        description = ns.L["Hitbox height as a percentage of the health bar height."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Hitbox Width Scale"], scaleXSlider),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Hitbox Height Scale"], scaleYSlider)
    )

    local visualizerToggle = gui:CreateFormCheckbox(card.frame, nil, "hitboxVisualizer", cvars, refresh, {
        description = ns.L["Draw the hitbox outline on every plate while tuning the scales."],
    })
    local stackingSpacingSlider = gui:CreateFormSlider(card.frame, nil, 0.5, 2, 0.05, "stackingSpacing", cvars, refresh, { deferOnDrag = true }, {
        description = ns.L["Multiplier on the vertical space plates keep when stacking."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Hitbox Visualizer"], visualizerToggle),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Stacking Spacing"], stackingSpacingSlider)
    )

    local clickthroughEnemyToggle = gui:CreateFormCheckbox(card.frame, nil, "clickthroughEnemy", cvars, refresh, {
        description = ns.L["Mouse clicks pass through enemy nameplates instead of targeting the unit."],
    })
    local clickthroughFriendlyToggle = gui:CreateFormCheckbox(card.frame, nil, "clickthroughFriendly", cvars, refresh, {
        description = ns.L["Mouse clicks pass through friendly nameplates instead of targeting the unit."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Click-Through Enemy Plates"], clickthroughEnemyToggle),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Click-Through Friendly Plates"], clickthroughFriendlyToggle)
    )
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderRenderModeSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    local Model = ns.QUI_NameplatesSettingsModel
    if not gui or not optionsAPI or not npdb or not Model then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("visibility"))
    if not builder then
        return nil
    end

    local NPCVars = ns.QUI_NameplatesCVars
    local cvars = EnsureSubTable(npdb, "cvars") or {}

    builder.Header(ns.L["Render Mode"])
    builder.Description(ns.L["How much of the plate each unit type draws. Simplified and Name Only strip the auras, cast bar, power bar, level, icons, highlights and health text, so those settings stop having any effect on that type."])
    local card = builder.Card()

    local baseDescription = ns.L["Health Bars draws the full QUI plate; Simplified draws a bare health bar and name; Name Only draws just the unit name."]
    local friendlyDescription = baseDescription
        .. " " .. ns.L["Open world only. Inside dungeons and raids Blizzard draws friendly plates itself, so the Show In Instances setting governs there instead."]

    local pending = nil
    for _, option in ipairs(Model.GetTypeOptions()) do
        local typeDB = ResolveTypeDB(option.value)
        if typeDB then
            local dropdown = gui:CreateFormDropdown(card.frame, nil, RENDER_MODE_OPTIONS, "renderMode", typeDB, RefreshNameplates, {
                description = option.value == "friendly" and friendlyDescription or baseDescription,
            })
            if NPCVars and NPCVars.IsTypeVisible and dropdown.SetEnabled then
                dropdown:SetEnabled(NPCVars.IsTypeVisible(cvars, option.value) == true)
            end
            local row = optionsAPI.BuildSettingRow(card.frame, option.text, dropdown)
            if pending then
                card.AddRow(pending, row)
                pending = nil
            else
                pending = row
            end
        end
    end
    if pending then
        card.AddRow(pending)
    end
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderVisibilitySection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local cvars = EnsureSubTable(npdb, "cvars")
    if not cvars then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("visibility"))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Enemy Nameplates"])
    builder.Description(ns.L["Whether hostile units get a nameplate at all. Turning this off also turns off everything indented under it."])
    local card = builder.Card()

    local masterToggle = gui:CreateFormCheckbox(card.frame, nil, "showEnemies", cvars, RefreshNameplatesAndRepaint, {
        description = ns.L["Show nameplates on hostile players and NPCs."],
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Enemy Nameplates"], masterToggle))

    local enemyRefresh = RefreshNameplatesAndRepaint
    local ENEMY_ROWS = {
        { key = "showEnemyMinions", label = ns.L["Enemy Minions"], description = ns.L["Show nameplates on enemy minions. Pets, totems and guardians sit under this."] },
        { key = "showEnemyPets", label = ns.L["Enemy Pets"], description = ns.L["Show nameplates on enemy player pets."], minion = true },
        { key = "showEnemyTotems", label = ns.L["Enemy Totems"], description = ns.L["Show nameplates on enemy totems."], minion = true },
        { key = "showEnemyGuardians", label = ns.L["Enemy Guardians"], description = ns.L["Show nameplates on enemy guardians."], minion = true },
        { key = "showEnemyMinus", label = ns.L["Minor Enemies"], description = ns.L["Show nameplates on trivial and critter-tier enemies."] },
    }

    local enemiesOn = cvars.showEnemies ~= false
    local enemyMinionsOn = enemiesOn and cvars.showEnemyMinions ~= false
    local pending = nil
    for i = 1, #ENEMY_ROWS do
        local def = ENEMY_ROWS[i]
        local toggle = gui:CreateFormCheckbox(card.frame, nil, def.key, cvars, enemyRefresh, {
            description = def.description,
        })
        if toggle.SetEnabled then
            toggle:SetEnabled(def.minion and enemyMinionsOn or (not def.minion and enemiesOn))
        end
        local row = optionsAPI.BuildSettingRow(card.frame, def.label, toggle)
        if pending then
            card.AddRow(pending, row)
            pending = nil
        else
            pending = row
        end
    end
    if pending then
        card.AddRow(pending)
    end
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderFriendlyKindsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local cvars = EnsureSubTable(npdb, "cvars")
    if not cvars then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("visibility"))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Friendly Unit Kinds"])
    builder.Description(ns.L["Which friendly unit kinds get a nameplate. These follow the Friendly Nameplates mode set below."])
    local card = builder.Card()

    local FRIENDLY_ROWS = {
        { key = "showFriendlyMinions", label = ns.L["Friendly Minions"], description = ns.L["Show nameplates on friendly minions. Pets, totems and guardians sit under this."] },
        { key = "showFriendlyPets", label = ns.L["Friendly Pets"], description = ns.L["Show nameplates on friendly player pets."], minion = true },
        { key = "showFriendlyTotems", label = ns.L["Friendly Totems"], description = ns.L["Show nameplates on friendly totems."], minion = true },
        { key = "showFriendlyGuardians", label = ns.L["Friendly Guardians"], description = ns.L["Show nameplates on friendly guardians."], minion = true },
    }

    local friendlyMinionsOn = cvars.showFriendlyMinions ~= false
    local pending = nil
    for i = 1, #FRIENDLY_ROWS do
        local def = FRIENDLY_ROWS[i]
        local toggle = gui:CreateFormCheckbox(card.frame, nil, def.key, cvars, RefreshNameplatesAndRepaint, {
            description = def.description,
        })
        if def.minion and toggle.SetEnabled then
            toggle:SetEnabled(friendlyMinionsOn)
        end
        local row = optionsAPI.BuildSettingRow(card.frame, def.label, toggle)
        if pending then
            card.AddRow(pending, row)
            pending = nil
        else
            pending = row
        end
    end
    if pending then
        card.AddRow(pending)
    end
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderReactionColorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local colors = EnsureSubTable(npdb, "colors")
    if not colors then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("colors", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Reaction Colors"])
    local card = builder.Card()

    local hostilePicker = gui:CreateFormColorPicker(card.frame, nil, "hostile", colors, refresh, { noAlpha = true }, {
        description = ns.L["Health bar color for hostile units."],
    })
    local neutralPicker = gui:CreateFormColorPicker(card.frame, nil, "neutral", colors, refresh, { noAlpha = true }, {
        description = ns.L["Health bar color for neutral units."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Hostile"], hostilePicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Neutral"], neutralPicker)
    )

    local friendlyPicker = gui:CreateFormColorPicker(card.frame, nil, "friendly", colors, refresh, { noAlpha = true }, {
        description = ns.L["Health bar color for friendly units (bars mode)."],
    })
    local tappedPicker = gui:CreateFormColorPicker(card.frame, nil, "tapped", colors, refresh, { noAlpha = true }, {
        description = ns.L["Health bar color for tapped units (another player's kill credit)."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Friendly"], friendlyPicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Tapped"], tappedPicker)
    )

    local questRows = {}
    local function UpdateQuestRows()
        local alpha = colors.questEnabled ~= false and 1.0 or 0.4
        for _, row in ipairs(questRows) do
            row:SetAlpha(alpha)
        end
    end
    local questToggle = gui:CreateFormCheckbox(card.frame, nil, "questEnabled", colors, function()
        refresh()
        UpdateQuestRows()
    end, {
        description = ns.L["Recolor plates of units that count for one of your active quests."],
    })
    local questPicker = gui:CreateFormColorPicker(card.frame, nil, "quest", colors, refresh, { noAlpha = true }, {
        description = ns.L["Health bar color for quest units."],
    })
    local questColorRow = optionsAPI.BuildSettingRow(card.frame, ns.L["Quest Color"], questPicker)
    questRows[#questRows + 1] = questColorRow
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Quest Units"], questToggle),
        questColorRow
    )

    local classColorToggle = gui:CreateFormCheckbox(card.frame, nil, "classColorEnemyPlayers", colors, refresh, {
        description = ns.L["Color enemy players' health bars by class instead of the hostile color."],
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Class Color Enemy Players"], classColorToggle))
    UpdateQuestRows()
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderCastColorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local colors = EnsureSubTable(npdb, "colors")
    if not colors then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("colors", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Cast Colors"])
    local card = builder.Card()

    local interruptiblePicker = gui:CreateFormColorPicker(card.frame, nil, "castInterruptible", colors, refresh, { noAlpha = true }, {
        description = ns.L["Cast bar color while the cast can be interrupted."],
    })
    local uninterruptiblePicker = gui:CreateFormColorPicker(card.frame, nil, "castUninterruptible", colors, refresh, { noAlpha = true }, {
        description = ns.L["Cast bar color for uninterruptible casts."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Interruptible"], interruptiblePicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Uninterruptible"], uninterruptiblePicker)
    )

    local interruptedPicker = gui:CreateFormColorPicker(card.frame, nil, "castInterrupted", colors, refresh, { noAlpha = true }, {
        description = ns.L["Cast bar color after a successful interrupt."],
    })
    local interruptReadyPicker = gui:CreateFormColorPicker(card.frame, nil, "castInterruptReady", colors, refresh, { noAlpha = true }, {
        description = ns.L["Cast bar color while your interrupt is off cooldown. Needs the Interrupt Ready Tint toggle."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Interrupted"], interruptedPicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Interrupt Ready"], interruptReadyPicker)
    )

    local channelPicker = gui:CreateFormColorPicker(card.frame, nil, "castChannel", colors, refresh, { noAlpha = true }, {
        description = ns.L["Cast bar color for channeled spells."],
    })
    local empoweredPicker = gui:CreateFormColorPicker(card.frame, nil, "castEmpowered", colors, refresh, { noAlpha = true }, {
        description = ns.L["Cast bar color for empowered spells."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Channeled"], channelPicker),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Empowered"], empoweredPicker)
    )

    local importantToggle = gui:CreateFormCheckbox(card.frame, nil, "castImportantEnabled", colors, refresh, {
        description = ns.L["Recolor casts the game flags as important, such as spells that are lethal if not interrupted."],
    })
    local importantPicker = gui:CreateFormColorPicker(card.frame, nil, "castImportant", colors, refresh, { noAlpha = true }, {
        description = ns.L["Cast bar color for important casts."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Important Casts"], importantToggle),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Important Cast Color"], importantPicker)
    )
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderThreatColorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local colors = EnsureSubTable(npdb, "colors")
    if not colors then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("colors", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Threat"])
    builder.Description(ns.L["Role-aware threat coloring, overriding reaction colors wherever it applies."])
    local card = builder.Card()
    local threatRows = {}
    local function UpdateThreatRows()
        local alpha = colors.threatEnabled ~= false and 1.0 or 0.4
        for _, row in ipairs(threatRows) do
            row:SetAlpha(alpha)
        end
    end
    local function AddGatedRow(label, widget)
        local row = optionsAPI.BuildSettingRow(card.frame, label, widget)
        threatRows[#threatRows + 1] = row
        return row
    end

    local threatToggle = gui:CreateFormCheckbox(card.frame, nil, "threatEnabled", colors, function()
        refresh()
        UpdateThreatRows()
    end, {
        description = ns.L["Color enemy health bars by your threat standing, adjusted for your role."],
    })
    local tankHasAggroPicker = gui:CreateFormColorPicker(card.frame, nil, "tankHasAggro", colors, refresh, { noAlpha = true }, {
        description = ns.L["Tank: you hold aggro."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Threat Colors"], threatToggle),
        AddGatedRow(ns.L["Tank: Has Aggro"], tankHasAggroPicker)
    )

    local tankNoAggroPicker = gui:CreateFormColorPicker(card.frame, nil, "tankNoAggro", colors, refresh, { noAlpha = true }, {
        description = ns.L["Tank: you lost aggro."],
    })
    local offTankPicker = gui:CreateFormColorPicker(card.frame, nil, "offTankAggro", colors, refresh, { noAlpha = true }, {
        description = ns.L["Tank: another tank holds aggro."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Tank: Lost Aggro"], tankNoAggroPicker),
        AddGatedRow(ns.L["Off-Tank Has Aggro"], offTankPicker)
    )

    local dpsHasAggroPicker = gui:CreateFormColorPicker(card.frame, nil, "dpsHasAggro", colors, refresh, { noAlpha = true }, {
        description = ns.L["DPS/Healer: you pulled aggro."],
    })
    local dpsNearAggroPicker = gui:CreateFormColorPicker(card.frame, nil, "dpsNearAggro", colors, refresh, { noAlpha = true }, {
        description = ns.L["DPS/Healer: your threat is getting close."],
    })
    card.AddRow(
        AddGatedRow(ns.L["DPS: Has Aggro"], dpsHasAggroPicker),
        AddGatedRow(ns.L["DPS: Near Aggro"], dpsNearAggroPicker)
    )

    local instancesOnlyToggle = gui:CreateFormCheckbox(card.frame, nil, "threatInstancesOnly", colors, refresh, {
        description = ns.L["Restrict threat coloring to dungeons and raids. Turn this off to color by threat everywhere, including the open world."],
    })
    card.AddRow(
        AddGatedRow(ns.L["Only In Instances"], instancesOnlyToggle)
    )
    UpdateThreatRows()
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderTargetFocusSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local colors = EnsureSubTable(npdb, "colors")
    local highlight = EnsureSubTable(npdb, "highlight")
    if not colors or not highlight then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("colors", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Target & Focus"])
    local overrideCard = builder.Card()

    local targetColorRow, focusColorRow
    local function UpdateOverrideRows()
        if targetColorRow then
            targetColorRow:SetAlpha(colors.targetEnabled == true and 1.0 or 0.4)
        end
        if focusColorRow then
            focusColorRow:SetAlpha(colors.focusEnabled ~= false and 1.0 or 0.4)
        end
    end

    local targetToggle = gui:CreateFormCheckbox(overrideCard.frame, nil, "targetEnabled", colors, function()
        refresh()
        UpdateOverrideRows()
    end, {
        description = ns.L["Recolor your current target's health bar."],
    })
    local targetPicker = gui:CreateFormColorPicker(overrideCard.frame, nil, "target", colors, refresh, { noAlpha = true }, {
        description = ns.L["Health bar color for your current target."],
    })
    targetColorRow = optionsAPI.BuildSettingRow(overrideCard.frame, ns.L["Target Color"], targetPicker)
    overrideCard.AddRow(
        optionsAPI.BuildSettingRow(overrideCard.frame, ns.L["Color Target"], targetToggle),
        targetColorRow
    )

    local focusToggle = gui:CreateFormCheckbox(overrideCard.frame, nil, "focusEnabled", colors, function()
        refresh()
        UpdateOverrideRows()
    end, {
        description = ns.L["Recolor your focus unit's health bar."],
    })
    local focusPicker = gui:CreateFormColorPicker(overrideCard.frame, nil, "focus", colors, refresh, { noAlpha = true }, {
        description = ns.L["Health bar color for your focus unit."],
    })
    focusColorRow = optionsAPI.BuildSettingRow(overrideCard.frame, ns.L["Focus Color"], focusPicker)
    overrideCard.AddRow(
        optionsAPI.BuildSettingRow(overrideCard.frame, ns.L["Color Focus"], focusToggle),
        focusColorRow
    )
    UpdateOverrideRows()
    builder.CloseCard(overrideCard)

    builder.Spacer(14)
    builder.Header(ns.L["Highlight"])
    local highlightCard = builder.Card()
    local glowRows = {}
    local focusGlowRows = {}
    local mouseoverRows = {}
    local function UpdateHighlightRows()
        local glowAlpha = highlight.targetGlow ~= false and 1.0 or 0.4
        for _, row in ipairs(glowRows) do
            row:SetAlpha(glowAlpha)
        end
        local focusAlpha = highlight.focusGlow == true and 1.0 or 0.4
        for _, row in ipairs(focusGlowRows) do
            row:SetAlpha(focusAlpha)
        end
        local hoverAlpha = highlight.mouseover ~= false and 1.0 or 0.4
        for _, row in ipairs(mouseoverRows) do
            row:SetAlpha(hoverAlpha)
        end
    end

    local glowToggle = gui:CreateFormCheckbox(highlightCard.frame, nil, "targetGlow", highlight, function()
        refresh()
        UpdateHighlightRows()
    end, {
        description = ns.L["Glow border around your current target's plate."],
    })
    local glowColorPicker = gui:CreateFormColorPicker(highlightCard.frame, nil, "targetGlowColor", highlight, refresh, { noAlpha = true }, {
        description = ns.L["Color of the target glow."],
    })
    local glowColorRow = optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Glow Color"], glowColorPicker)
    glowRows[#glowRows + 1] = glowColorRow
    highlightCard.AddRow(
        optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Target Glow"], glowToggle),
        glowColorRow
    )

    local targetStyleDropdown = gui:CreateFormDropdown(highlightCard.frame, nil, TARGET_STYLE_OPTIONS, "targetStyle", highlight, refresh, {
        description = ns.L["Shape used to mark your target: a full glow wash, side arrows, corner brackets, or an underline."],
    })
    local targetStyleRow = optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Target Marker"], targetStyleDropdown)
    glowRows[#glowRows + 1] = targetStyleRow
    highlightCard.AddRow(targetStyleRow)

    local glowAlphaSlider = gui:CreateFormSlider(highlightCard.frame, nil, 0, 1, 0.05, "targetGlowAlpha", highlight, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the target glow."],
    })
    local glowAlphaRow = optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Glow Opacity"], glowAlphaSlider)
    glowRows[#glowRows + 1] = glowAlphaRow
    local mouseoverToggle = gui:CreateFormCheckbox(highlightCard.frame, nil, "mouseover", highlight, function()
        refresh()
        UpdateHighlightRows()
    end, {
        description = ns.L["Brighten the plate under your mouse cursor."],
    })
    highlightCard.AddRow(
        glowAlphaRow,
        optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Mouseover Highlight"], mouseoverToggle)
    )

    local mouseoverAlphaSlider = gui:CreateFormSlider(highlightCard.frame, nil, 0, 1, 0.05, "mouseoverAlpha", highlight, refresh, { deferOnDrag = true }, {
        description = ns.L["Strength of the mouseover highlight."],
    })
    local mouseoverAlphaRow = optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Mouseover Intensity"], mouseoverAlphaSlider)
    mouseoverRows[#mouseoverRows + 1] = mouseoverAlphaRow
    local mouseoverColorPicker = gui:CreateFormColorPicker(highlightCard.frame, nil, "mouseoverColor", highlight, refresh, { noAlpha = true }, {
        description = ns.L["Color of the mouseover highlight."],
    })
    local mouseoverColorRow = optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Mouseover Color"], mouseoverColorPicker)
    mouseoverRows[#mouseoverRows + 1] = mouseoverColorRow
    highlightCard.AddRow(mouseoverAlphaRow, mouseoverColorRow)

    local focusGlowToggle = gui:CreateFormCheckbox(highlightCard.frame, nil, "focusGlow", highlight, function()
        refresh()
        UpdateHighlightRows()
    end, {
        description = ns.L["Show a glow behind your focus target's health bar."],
    })
    local focusGlowColorPicker = gui:CreateFormColorPicker(highlightCard.frame, nil, "focusGlowColor", highlight, refresh, { noAlpha = true }, {
        description = ns.L["Color of the focus glow."],
    })
    local focusGlowColorRow = optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Focus Glow Color"], focusGlowColorPicker)
    focusGlowRows[#focusGlowRows + 1] = focusGlowColorRow
    highlightCard.AddRow(
        optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Focus Glow"], focusGlowToggle),
        focusGlowColorRow
    )

    local focusGlowAlphaSlider = gui:CreateFormSlider(highlightCard.frame, nil, 0, 1, 0.05, "focusGlowAlpha", highlight, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity of the focus glow."],
    })
    local focusGlowAlphaRow = optionsAPI.BuildSettingRow(highlightCard.frame, ns.L["Focus Glow Opacity"], focusGlowAlphaSlider)
    focusGlowRows[#focusGlowRows + 1] = focusGlowAlphaRow
    highlightCard.AddRow(focusGlowAlphaRow)
    UpdateHighlightRows()
    builder.CloseCard(highlightCard)

    return builder.Height()
end

local function RenderCombatStateSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveTypeDB(ctx and ctx.options and ctx.options.typeKey)
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local colors = EnsureSubTable(npdb, "colors")
    if not colors then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("colors", ctx and ctx.options and ctx.options.typeKey))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Out of Combat"])
    local oocCard = builder.Card()
    local oocFactorRow
    local function UpdateOocRows()
        if oocFactorRow then
            oocFactorRow:SetAlpha(colors.oocDarken ~= false and 1.0 or 0.4)
        end
    end

    local oocToggle = gui:CreateFormCheckbox(oocCard.frame, nil, "oocDarken", colors, function()
        refresh()
        UpdateOocRows()
    end, {
        description = ns.L["Darken hostile plates while the unit is out of combat."],
    })
    local oocFactorSlider = gui:CreateFormSlider(oocCard.frame, nil, 0.3, 1, 0.05, "oocDarkenFactor", colors, refresh, { deferOnDrag = true }, {
        description = ns.L["Multiplier applied to the bar color out of combat. Lower is darker."],
    })
    oocFactorRow = optionsAPI.BuildSettingRow(oocCard.frame, ns.L["Darken Factor"], oocFactorSlider)
    oocCard.AddRow(
        optionsAPI.BuildSettingRow(oocCard.frame, ns.L["Darken Out of Combat"], oocToggle),
        oocFactorRow
    )
    UpdateOocRows()
    builder.CloseCard(oocCard)

    builder.Spacer(14)
    builder.Header(ns.L["Execute Range"])
    local executeCard = builder.Card()
    local executeRows = {}
    local function UpdateExecuteRows()
        local alpha = colors.executeEnabled == true and 1.0 or 0.4
        for _, row in ipairs(executeRows) do
            row:SetAlpha(alpha)
        end
    end

    local executeToggle = gui:CreateFormCheckbox(executeCard.frame, nil, "executeEnabled", colors, function()
        refresh()
        UpdateExecuteRows()
    end, {
        description = ns.L["Fade a colored overlay onto the health bar as the unit drops below the execute threshold."],
    })
    local executePicker = gui:CreateFormColorPicker(executeCard.frame, nil, "execute", colors, refresh, { noAlpha = true }, {
        description = ns.L["Color of the execute-range overlay."],
    })
    local executeColorRow = optionsAPI.BuildSettingRow(executeCard.frame, ns.L["Execute Color"], executePicker)
    executeRows[#executeRows + 1] = executeColorRow
    executeCard.AddRow(
        optionsAPI.BuildSettingRow(executeCard.frame, ns.L["Execute Coloring"], executeToggle),
        executeColorRow
    )

    local autoToggle = gui:CreateFormCheckbox(executeCard.frame, nil, "executeAuto", colors, function()
        refresh()
        UpdateExecuteRows()
    end, {
        description = ns.L["Derive the threshold from your known execute ability. Classes without one fall back to the slider."],
    })
    local autoRow = optionsAPI.BuildSettingRow(executeCard.frame, ns.L["Auto Threshold"], autoToggle)
    executeRows[#executeRows + 1] = autoRow
    local thresholdSlider = gui:CreateFormSlider(executeCard.frame, nil, 5, 50, 1, "executeThreshold", colors, refresh, { deferOnDrag = true }, {
        description = ns.L["Health percentage below which the execute color applies."],
    })
    local thresholdRow = optionsAPI.BuildSettingRow(executeCard.frame, ns.L["Execute Threshold"], thresholdSlider)
    executeRows[#executeRows + 1] = thresholdRow
    executeCard.AddRow(autoRow, thresholdRow)
    UpdateExecuteRows()
    builder.CloseCard(executeCard)

    return builder.Height()
end

local function RenderFriendlySection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local friendly = EnsureSubTable(npdb, "friendly")
    if not friendly then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("visibility"))
    if not builder then
        return nil
    end

    local cvars = EnsureSubTable(npdb, "cvars")
    if not cvars then
        return nil
    end

    local refresh = RefreshNameplatesAndRepaint
    local friendlyOn = friendly.enabled ~= false
    local friendlyMinionsOn = friendlyOn and cvars.showFriendlyMinions ~= false

    local function Gate(widget, enabled)
        if widget and widget.SetEnabled then
            widget:SetEnabled(enabled)
        end
        return widget
    end

    builder.Header(ns.L["Friendly Nameplates"])
    builder.Description(ns.L["Whether friendly units get a nameplate at all, and where. Turning this off also turns off everything under it."])
    local card = builder.Card()

    local masterToggle = gui:CreateFormCheckbox(card.frame, nil, "enabled", friendly, refresh, {
        description = ns.L["Off hides friendly nameplates entirely, whatever the Friendly unit type's render mode is set to."],
    })
    local showNPCsToggle = Gate(gui:CreateFormCheckbox(card.frame, nil, "showNPCs", friendly, refresh, {
        description = ns.L["Show nameplates on friendly NPCs such as quest givers and vendors."],
    }), friendlyOn)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Friendly Nameplates"], masterToggle),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Friendly NPCs"], showNPCsToggle)
    )

    local FRIENDLY_KIND_ROWS = {
        { key = "showFriendlyMinions", label = ns.L["Friendly Minions"], description = ns.L["Show nameplates on friendly minions. Pets, totems and guardians sit under this."] },
        { key = "showFriendlyPets", label = ns.L["Friendly Pets"], description = ns.L["Show nameplates on friendly player pets."], minion = true },
        { key = "showFriendlyTotems", label = ns.L["Friendly Totems"], description = ns.L["Show nameplates on friendly totems."], minion = true },
        { key = "showFriendlyGuardians", label = ns.L["Friendly Guardians"], description = ns.L["Show nameplates on friendly guardians."], minion = true },
    }

    local pending = nil
    for i = 1, #FRIENDLY_KIND_ROWS do
        local def = FRIENDLY_KIND_ROWS[i]
        local toggle = Gate(gui:CreateFormCheckbox(card.frame, nil, def.key, cvars, refresh, {
            description = def.description,
        }), def.minion and friendlyMinionsOn or friendlyOn)
        local row = optionsAPI.BuildSettingRow(card.frame, def.label, toggle)
        if pending then
            card.AddRow(pending, row)
            pending = nil
        else
            pending = row
        end
    end
    if pending then
        card.AddRow(pending)
    end

    local showWorldToggle = Gate(gui:CreateFormCheckbox(card.frame, nil, "showInWorld", friendly, refresh, {
        description = ns.L["Show friendly nameplates in the open world."],
    }), friendlyOn)
    local showInstancesDropdown = Gate(gui:CreateFormDropdown(card.frame, nil, FRIENDLY_INSTANCE_OPTIONS, "showInInstances", friendly, refresh, {
        description = ns.L["Friendly plates inside dungeons and raids are drawn by Blizzard, not by QUI, so the Friendly render mode does not reach them. Name Only is the only look the game allows there."],
    }), friendlyOn)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show In World"], showWorldToggle),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Show In Instances"], showInstancesDropdown)
    )
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderFadingSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local fading = EnsureSubTable(npdb, "fading")
    local layout = EnsureSubTable(npdb, "layout")
    if not fading or not layout then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("frame"))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Fading And Scale"])
    builder.Description(ns.L["Opacity and size of plates relative to your current target. Editing these from any type tab changes every plate."])
    local card = builder.Card()

    local nonTargetSlider = gui:CreateFormSlider(card.frame, nil, 0.2, 1, 0.05, "nonTargetAlpha", fading, refresh, { deferOnDrag = true }, {
        description = ns.L["Dim plates that are not your current target. 1 leaves them undimmed."],
    })
    local occludedSlider = gui:CreateFormSlider(card.frame, nil, 0.1, 1, 0.05, "occludedAlphaMult", fading, refresh, { deferOnDrag = true }, {
        description = ns.L["Opacity multiplier for plates whose unit is behind terrain or walls."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Non-Target Opacity"], nonTargetSlider),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Occluded Opacity"], occludedSlider)
    )

    local targetScaleSlider = gui:CreateFormSlider(card.frame, nil, 1, 1.5, 0.05, "targetScale", layout, refresh, { deferOnDrag = true }, {
        description = ns.L["Size multiplier for your current target's plate."],
    })
    local verticalOffsetSlider = gui:CreateFormSlider(card.frame, nil, -50, 50, 1, "verticalOffset", layout, refresh, { deferOnDrag = true }, {
        description = ns.L["Move the plate up or down relative to the unit."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Target Scale"], targetScaleSlider),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Vertical Offset"], verticalOffsetSlider)
    )

    local simplified = EnsureSubTable(npdb, "simplified")
    if simplified then
        local simplifiedScaleSlider = gui:CreateFormSlider(card.frame, nil, 0.5, 2, 0.05, "scale", simplified, refresh, { deferOnDrag = true }, {
            description = ns.L["Size multiplier for the stripped-down plates, for the unit types you set to Simplified."],
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Simplified Plate Scale"], simplifiedScaleSlider))
    end
    builder.CloseCard(card)

    return builder.Height()
end

local function RenderCVarsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local cvars = EnsureSubTable(npdb, "cvars")
    if not cvars then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("general"))
    if not builder then
        return nil
    end

    local refresh = RefreshNameplates

    builder.Header(ns.L["Nameplate CVars"])
    builder.Description(ns.L["Client-level nameplate variables. QUI owns these while nameplates are enabled; combat changes apply after combat ends."])
    local card = builder.Card()

    local distanceSlider = gui:CreateFormSlider(card.frame, nil, 10, 60, 1, "maxDistance", cvars, refresh, { deferOnDrag = true }, {
        description = ns.L["Maximum distance (yards) at which nameplates are visible."],
    })
    local stackEnemyToggle = gui:CreateFormCheckbox(card.frame, nil, "stackingEnemy", cvars, refresh, {
        description = ns.L["Stack enemy plates instead of letting them overlap."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Max Distance"], distanceSlider),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Stack Enemy Plates"], stackEnemyToggle)
    )

    local stackFriendlyToggle = gui:CreateFormCheckbox(card.frame, nil, "stackingFriendly", cvars, refresh, {
        description = ns.L["Stack friendly plates instead of letting them overlap."],
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Stack Friendly Plates"], stackFriendlyToggle))
    builder.CloseCard(card)

    return builder.Height()
end

local STARTER_STYLE_LABELS = {
    default = {
        label = ns.L["Shipped Defaults"],
        description = ns.L["Reset every nameplate setting to the values QUI ships with."],
    },
    compact = {
        label = ns.L["Compact"],
        description = ns.L["Narrow, short plates with no health text, for dense pulls."],
    },
    chunky = {
        label = ns.L["Chunky"],
        description = ns.L["Wide, tall plates showing both the health value and the percentage."],
    },
}

local function RenderStarterStylesSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local NPPresets = ns.QUI_Nameplates and ns.QUI_Nameplates.Presets
    if not (NPPresets and NPPresets.ApplyStyleTable and NPPresets.GetStarterStyleKeys) then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("general"))
    if not builder then
        return nil
    end

    builder.Header(ns.L["Starter Styles"])
    builder.Description(ns.L["One-click starting points. Each one overwrites only the settings it opinionates, then you tune from there."])

    for _, key in ipairs(NPPresets.GetStarterStyleKeys()) do
        local meta = STARTER_STYLE_LABELS[key]
        if meta then
            local row = CreateFrame("Frame", nil, sectionHost)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -builder.Height(0))
            row:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -builder.Height(0))
            builder.Spacer(30)

            local label = gui:CreateLabel(row, meta.label, 12)
            label:SetPoint("LEFT", row, "LEFT", 4, 0)

            local applyBtn = gui:CreateButton(row, ns.L["Apply"], 70, 20, function()
                gui:ShowConfirmation({
                    title = meta.label,
                    message = meta.description,
                    acceptText = ns.L["Apply"],
                    cancelText = ns.L["Cancel"],
                    onAccept = function()
                        if NPPresets.ApplyStyleTable(key) then
                            RefreshNameplates()
                            InvalidateTabBodies()
                            ScheduleSectionReflow(ctx)
                        end
                    end,
                })
            end)
            applyBtn:SetPoint("LEFT", row, "LEFT", 200, 0)
        end
    end

    return builder.Height()
end

local function RenderSpecPresetsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local npdb = ResolveNameplatesDB()
    if not gui or not optionsAPI or not npdb then
        return nil
    end

    local Presets = ns.QUI_Nameplates and ns.QUI_Nameplates.Presets

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext("general"))
    if not builder then
        return nil
    end

    builder.Header(ns.L["Spec & Role Presets"])
    builder.Description(ns.L["Save the current nameplate settings as a preset. Spec presets live in this profile; role presets are account-wide — every character shares them. With auto-switch on, changing spec (or logging in) applies the matching preset; a spec preset wins over a role preset."])
    local card = builder.Card()

    local autoToggle = gui:CreateFormCheckbox(card.frame, nil, "specAutoSwitch", npdb, RefreshNameplates, {
        description = ns.L["Automatically apply the saved spec preset when you change specialization."],
    })
    local roleStore = (Presets and Presets.GetRoleStore and Presets.GetRoleStore()) or { autoSwitch = false }
    local roleAutoToggle = gui:CreateFormCheckbox(card.frame, nil, "autoSwitch", roleStore, RefreshNameplates, {
        description = ns.L["Account-wide: any character switching to a tank, healer, or damage spec applies that role's preset."],
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, ns.L["Auto-switch on spec change"], autoToggle),
        optionsAPI.BuildSettingRow(card.frame, ns.L["Auto-switch by role (account-wide)"], roleAutoToggle)
    )
    builder.CloseCard(card)
    builder.Spacer(8)

    if not Presets then
        return builder.Height()
    end

    local function AddPresetRow(labelText, saved, onSave, onApply, onClear)
        local row = CreateFrame("Frame", nil, sectionHost)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -builder.Height(0))
        row:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -builder.Height(0))
        builder.Spacer(30)

        local label = gui:CreateLabel(row, labelText .. (saved and (" |cFF34D399" .. ns.L["(saved)"] .. "|r") or ""), 12)
        label:SetPoint("LEFT", row, "LEFT", 4, 0)

        local saveBtn = gui:CreateButton(row, ns.L["Save"], 70, 20, function()
            onSave()
            ScheduleSectionReflow(ctx)
        end)
        saveBtn:SetPoint("LEFT", row, "LEFT", 200, 0)

        local applyBtn = gui:CreateButton(row, ns.L["Apply"], 70, 20, function()
            if onApply() then
                ScheduleSectionReflow(ctx)
            end
        end)
        applyBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)

        local clearBtn = gui:CreateButton(row, ns.L["Clear"], 70, 20, function()
            onClear()
            ScheduleSectionReflow(ctx)
        end)
        clearBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)

        if not saved then
            if applyBtn.Disable then applyBtn:Disable() end
            if clearBtn.Disable then clearBtn:Disable() end
        end
    end

    local numSpecs = 0
    if GetNumSpecializations then
        local ok, n = pcall(GetNumSpecializations)
        if ok and type(n) == "number" then numSpecs = n end
    end
    for specIndex = 1, numSpecs do
        local specName = ns.L["Spec"] .. " " .. specIndex
        if GetSpecializationInfo then
            local ok, _, name = pcall(GetSpecializationInfo, specIndex)
            if ok and type(name) == "string" and name ~= "" then
                specName = name
            end
        end
        AddPresetRow(specName, Presets.HasPreset(specIndex),
            function() Presets.SaveForSpec(specIndex) end,
            function() return Presets.ApplyForSpec(specIndex) end,
            function() Presets.ClearForSpec(specIndex) end)
    end

    builder.Spacer(6)
    local ROLE_ROWS = {
        { role = "TANK", label = ns.L["Tank (all characters)"] },
        { role = "HEALER", label = ns.L["Healer (all characters)"] },
        { role = "DAMAGER", label = ns.L["Damage (all characters)"] },
    }
    for _, def in ipairs(ROLE_ROWS) do
        local role = def.role
        AddPresetRow(def.label, Presets.HasRolePreset(role),
            function() Presets.SaveForRole(role) end,
            function() return Presets.ApplyForRole(role) end,
            function() Presets.ClearForRole(role) end)
    end

    return builder.Height()
end

local function BuildCopyFromSection(tabKey)
    return function(sectionHost, ctx)
        local gui = GetGUI()
        local optionsAPI = GetOptionsAPI()
        local typeKey = ctx and ctx.options and ctx.options.typeKey
        local hideCopyFrom = ctx and ctx.options and ctx.options.hideCopyFrom
        if not gui or not optionsAPI or type(typeKey) ~= "string" or hideCopyFrom then
            return nil
        end

        local Model = ns.QUI_NameplatesSettingsModel
        local getTypeOptions = Model and Model.GetTypeOptions
        if type(getTypeOptions) ~= "function" then
            return nil
        end

        local typeLabels = {}
        local copyOptions = {}
        for _, option in ipairs(getTypeOptions()) do
            typeLabels[option.value] = option.text
            if option.value ~= typeKey then
                copyOptions[#copyOptions + 1] = option
            end
        end
        if #copyOptions == 0 then
            return nil
        end

        local builder = CreateSectionBuilder(sectionHost, ctx, CreateSearchContext(tabKey, typeKey))
        if not builder then
            return nil
        end

        builder.Header(ns.L["Copy Settings"])
        local card = builder.Card()
        local copySelector = { selected = copyOptions[1].value }
        local copyDropdown = gui:CreateFormDropdown(card.frame, nil, copyOptions, "selected", copySelector, nil)
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, ns.L["Copy From"], copyDropdown))
        builder.CloseCard(card)

        local row = CreateFrame("Frame", nil, sectionHost)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, -builder.Height(0))
        row:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, -builder.Height(0))
        builder.Spacer(30)

        local applyBtn = gui:CreateButton(row, ns.L["Apply Copy"], 100, 24, function()
            local sourceKey = copySelector.selected
            if type(sourceKey) ~= "string" or sourceKey == typeKey then
                return
            end
            gui:ShowConfirmation({
                title = ns.L["Copy All Settings"],
                message = string.format(ns.L["This will overwrite ALL %1$s visual settings with %2$s settings. Continue?"],
                    typeLabels[typeKey] or typeKey, typeLabels[sourceKey] or sourceKey),
                acceptText = ns.L["Copy All"],
                cancelText = ns.L["Cancel"],
                isDestructive = true,
                onAccept = function()
                    if NameplatesSchema.CopyTypeConfig(sourceKey, typeKey) then
                        RefreshNameplates()
                        InvalidateTabBodies()
                        ScheduleSectionReflow(ctx)
                    end
                end,
            })
        end)
        applyBtn:SetPoint("LEFT", row, "LEFT", 0, 0)

        return builder.Height()
    end
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
            nameplateTab = {
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

local GENERAL_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesGeneralTab", {
    { id = "enable", minHeight = 64, render = RenderEnableSection },
    { id = "starterStyles", minHeight = 150, render = RenderStarterStylesSection },
    { id = "specPresets", minHeight = 160, render = RenderSpecPresetsSection },
    { id = "cvarsSection", minHeight = 130, render = RenderCVarsSection },
})

local VISIBILITY_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesVisibilityTab", {
    { id = "enemyVisibility", minHeight = 220, render = RenderVisibilitySection },
    { id = "friendly", minHeight = 200, render = RenderFriendlySection },
    { id = "renderMode", minHeight = 220, render = RenderRenderModeSection },
})

local FRAME_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesFrameTab", {
    { id = "copyFrom", minHeight = 110, render = BuildCopyFromSection("frame") },
    { id = "health", minHeight = 260, render = RenderHealthSection },
    { id = "absorbs", minHeight = 180, render = RenderAbsorbsSection },
    { id = "hitbox", minHeight = 130, render = RenderHitboxSection },
    { id = "fading", minHeight = 170, render = RenderFadingSection },
})

local TEXT_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesTextTab", {
    { id = "copyFrom", minHeight = 110, render = BuildCopyFromSection("text") },
    { id = "name", minHeight = 180, render = RenderNameSection },
    { id = "healthText", minHeight = 200, render = RenderHealthTextSection },
    { id = "level", minHeight = 200, render = RenderLevelSection },
})

local INDICATORS_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesIndicatorsTab", {
    { id = "copyFrom", minHeight = 110, render = BuildCopyFromSection("indicators") },
    { id = "extras", minHeight = 180, render = RenderExtrasSection },
    { id = "classPower", minHeight = 170, render = RenderClassPowerSection },
})

local AURAS_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesAurasTab", {
    { id = "copyFrom", minHeight = 110, render = BuildCopyFromSection("auras") },
    { id = "auraRows", minHeight = 640, render = RenderAuraRowsSection },
})

local CASTBARS_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesCastbarsTab", {
    { id = "copyFrom", minHeight = 110, render = BuildCopyFromSection("castbars") },
    { id = "castbar", minHeight = 220, render = RenderCastbarSection },
})

local COLORS_TAB_FEATURE = CreateMultiSectionTabFeature("nameplatesColorsTab", {
    { id = "copyFrom", minHeight = 110, render = BuildCopyFromSection("colors") },
    { id = "reaction", minHeight = 200, render = RenderReactionColorsSection },
    { id = "cast", minHeight = 120, render = RenderCastColorsSection },
    { id = "threat", minHeight = 160, render = RenderThreatColorsSection },
    { id = "targetFocus", minHeight = 220, render = RenderTargetFocusSection },
    { id = "combatState", minHeight = 180, render = RenderCombatStateSection },
})

local function RenderFeatureTab(feature, host, typeKey, hideCopyFrom)
    if not host then
        return false
    end

    local npdb = ResolveNameplatesDB()
    if not npdb then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(feature, host, {
        surface = "nameplateTab",
        width = width,
        typeKey = typeKey,
        hideCopyFrom = hideCopyFrom,
    })
end

function NameplatesSchema.RenderGeneralTab(host)
    return RenderFeatureTab(GENERAL_TAB_FEATURE, host)
end

function NameplatesSchema.RenderVisibilityTab(host)
    return RenderFeatureTab(VISIBILITY_TAB_FEATURE, host)
end

function NameplatesSchema.RenderFrameTab(host, typeKey)
    return RenderFeatureTab(FRAME_TAB_FEATURE, host, typeKey)
end

function NameplatesSchema.RenderTextTab(host, typeKey)
    return RenderFeatureTab(TEXT_TAB_FEATURE, host, typeKey)
end

function NameplatesSchema.RenderIndicatorsTab(host, typeKey)
    return RenderFeatureTab(INDICATORS_TAB_FEATURE, host, typeKey)
end

function NameplatesSchema.RenderAurasTab(host, typeKey, hideCopyFrom)
    return RenderFeatureTab(AURAS_TAB_FEATURE, host, typeKey, hideCopyFrom)
end

function NameplatesSchema.RenderCastbarsTab(host, typeKey)
    return RenderFeatureTab(CASTBARS_TAB_FEATURE, host, typeKey)
end

function NameplatesSchema.RenderColorsTab(host, typeKey)
    return RenderFeatureTab(COLORS_TAB_FEATURE, host, typeKey)
end

