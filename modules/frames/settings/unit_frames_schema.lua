local ADDON_NAME, ns = ...

local Settings = ns.Settings
local Renderer = Settings and Settings.Renderer
local Schema = Settings and Settings.Schema
if not Renderer or type(Renderer.RenderFeature) ~= "function"
    or not Schema or type(Schema.Feature) ~= "function" then
    return
end

local Helpers = ns.Helpers

local UnitFramesSchema = ns.QUI_UnitFramesSettingsSchema or {}
ns.QUI_UnitFramesSettingsSchema = UnitFramesSchema

local HEADER_GAP = 26
local SECTION_BOTTOM_PAD = 6
local FORM_ROW = 32
local DESCRIPTION_TEXT_COLOR = { 0.5, 0.5, 0.5, 1 }
local UNIT_FRAMES_FEATURE_ID = "unitFramesPage"
local UNIT_FRAMES_TILE_ROUTE = {
    tileId = "unit_frames",
    subPageIndex = 1,
}
local GENERAL_SEARCH_CONTEXT = {
    tabIndex = 5,
    tabName = "Unit Frames",
    subTabIndex = 1,
    subTabName = "General",
    featureId = UNIT_FRAMES_FEATURE_ID,
    tileId = UNIT_FRAMES_TILE_ROUTE.tileId,
    subPageIndex = UNIT_FRAMES_TILE_ROUTE.subPageIndex,
    surfaceTabKey = "general",
}
local UNIT_SUBTAB_INDEX = {
    player = 2,
    target = 3,
    targettarget = 4,
    pet = 5,
    focus = 6,
    boss = 7,
}
local UNIT_DISPLAY_NAMES = {
    player = "Player",
    target = "Target",
    targettarget = "Target of Target",
    pet = "Pet",
    focus = "Focus",
    boss = "Boss",
}
local UNIT_SURFACE_TABS = {
    ["Frame"] = "frame",
    ["Bars"] = "bars",
    ["Castbar"] = "castbar",
    ["Text"] = "text",
    ["Icons"] = "icons",
    ["Indicators"] = "indicators",
    ["Portrait"] = "portrait",
    ["Priv. Auras"] = "privateAuras",
}
local FRAME_TAB_FEATURES = {}
local BARS_TAB_FEATURES = {}
local CASTBAR_TAB_FEATURES = {}
local TEXT_TAB_FEATURES = {}
local ICONS_TAB_FEATURES = {}
local PORTRAIT_TAB_FEATURES = {}
local INDICATORS_TAB_FEATURES = {}
local PRIVATE_AURAS_TAB_FEATURES = {}
local TOT_SEPARATOR_OPTIONS = {
    { value = " >> ",  text = ">>" },
    { value = " > ",   text = ">" },
    { value = " - ",   text = "-" },
    { value = " | ",   text = "|" },
    { value = " -> ",  text = "->" },
    { value = " —> ",  text = "—>" },
    { value = " >>> ", text = ">>>" },
}
local HEALTH_STYLE_OPTIONS = {
    { value = "percent",         text = "Percent Only (75%)" },
    { value = "absolute",        text = "Value Only (45.2k)" },
    { value = "both",            text = "Value | Percent" },
    { value = "both_reverse",    text = "Percent | Value" },
    { value = "missing_percent", text = "Missing Percent (-25%)" },
    { value = "missing_value",   text = "Missing Value (-12.5k)" },
}
local HEALTH_DIVIDER_OPTIONS = {
    { value = " | ", text = "|  (pipe)" },
    { value = " - ", text = "-  (dash)" },
    { value = " / ", text = "/  (slash)" },
    { value = " • ", text = "•  (dot)" },
}
local POWER_TEXT_FORMAT_OPTIONS = {
    { value = "percent", text = "Percent (75%)" },
    { value = "current", text = "Current (12.5k)" },
    { value = "both",    text = "Both (12.5k | 75%)" },
}
local PORTRAIT_SIDE_OPTIONS = {
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
}
local PRIVATE_AURA_GROW_OPTIONS = {
    { value = "RIGHT",  text = "Right" },
    { value = "LEFT",   text = "Left" },
    { value = "UP",     text = "Up" },
    { value = "DOWN",   text = "Down" },
    { value = "CENTER", text = "Center" },
}
local AURA_CORNER_OPTIONS = {
    { value = "TOPLEFT",     text = "Top Left" },
    { value = "TOPRIGHT",    text = "Top Right" },
    { value = "BOTTOMLEFT",  text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}
local AURA_GROW_OPTIONS = {
    { value = "LEFT",  text = "Left" },
    { value = "RIGHT", text = "Right" },
    { value = "UP",    text = "Up" },
    { value = "DOWN",  text = "Down" },
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

local function ResolveGeneralDB()
    local profile = GetProfileDB()
    local ufdb = profile and profile.quiUnitFrames
    if type(profile) ~= "table" or type(ufdb) ~= "table" then
        return nil
    end

    if type(profile.general) ~= "table" then
        profile.general = {}
    end
    if type(ufdb.general) ~= "table" then
        ufdb.general = {}
    end

    return {
        profile = profile,
        ufdb = ufdb,
        general = profile.general,
        unitFramesGeneral = ufdb.general,
    }
end

local function ResolveUnitDB(unitKey)
    if type(unitKey) ~= "string" or unitKey == "" then
        return nil
    end

    local profile = GetProfileDB()
    local ufdb = profile and profile.quiUnitFrames
    local unitDB = ufdb and ufdb[unitKey]
    if type(profile) ~= "table" or type(ufdb) ~= "table" or type(unitDB) ~= "table" then
        return nil
    end

    if type(profile.general) ~= "table" then
        profile.general = {}
    end
    if unitKey == "target" and unitDB.invertHealthDirection == nil then
        unitDB.invertHealthDirection = false
    end

    return {
        profile = profile,
        ufdb = ufdb,
        unitDB = unitDB,
        general = profile.general,
        displayName = UNIT_DISPLAY_NAMES[unitKey] or unitKey:gsub("^%l", string.upper),
    }
end

local function UnitHasHostilityColors(unitKey)
    return unitKey == "target"
        or unitKey == "focus"
        or unitKey == "targettarget"
        or unitKey == "pet"
        or unitKey == "boss"
end

local function UnitHasHealPrediction(unitKey)
    return unitKey == "player" or unitKey == "target"
end

local function EnsureAbsorbSettings(unitDB)
    if type(unitDB.absorbs) ~= "table" then
        unitDB.absorbs = {
            enabled = true,
            color = { 0.2, 0.8, 0.8 },
            opacity = 0.7,
            texture = "QUI Stripes",
        }
    end
    return unitDB.absorbs
end

local function EnsureHealPredictionSettings(unitDB)
    if type(unitDB.healPrediction) ~= "table" then
        unitDB.healPrediction = {
            enabled = false,
            color = { 0.2, 1, 0.2 },
            opacity = 0.5,
        }
    end
    return unitDB.healPrediction
end

local function EnsurePlayerStanceSettings(unitDB)
    if type(unitDB.indicators) ~= "table" then
        unitDB.indicators = {}
    end
    if type(unitDB.indicators.stance) ~= "table" then
        unitDB.indicators.stance = {
            enabled = false,
            fontSize = 12,
            anchor = "BOTTOM",
            offsetX = 0,
            offsetY = -2,
            useClassColor = true,
            customColor = { 1, 1, 1, 1 },
            showIcon = false,
            iconSize = 14,
            iconOffsetX = -2,
        }
    end
    return unitDB.indicators.stance
end

local function UnitSupportsPortrait(unitKey)
    return unitKey == "player" or unitKey == "target" or unitKey == "focus"
end

local function UnitSupportsPrivateAuras(unitKey)
    return unitKey == "player" or unitKey == "target" or unitKey == "focus"
end

local function UnitSupportsLeaderIndicator(unitKey)
    return unitKey == "player" or unitKey == "target" or unitKey == "focus"
end

local function UnitSupportsClassificationIndicator(unitKey)
    return unitKey == "target" or unitKey == "focus" or unitKey == "boss"
end

local function EnsurePortraitSettings(unitDB, unitKey)
    if unitDB.showPortrait == nil then
        unitDB.showPortrait = false
    end
    if unitDB.portraitSide == nil then
        unitDB.portraitSide = (unitKey == "player") and "LEFT" or "RIGHT"
    end
    if unitDB.portraitSize == nil then
        if unitDB.portraitScale then
            local height = unitDB.height or 40
            unitDB.portraitSize = math.floor(height * unitDB.portraitScale)
        else
            unitDB.portraitSize = 40
        end
    end
    if unitDB.portraitBorderSize == nil then unitDB.portraitBorderSize = 1 end
    if unitDB.portraitGap == nil then unitDB.portraitGap = 0 end
    if unitDB.portraitOffsetX == nil then unitDB.portraitOffsetX = 0 end
    if unitDB.portraitOffsetY == nil then unitDB.portraitOffsetY = 0 end
    if unitDB.portraitBorderUseClassColor == nil then unitDB.portraitBorderUseClassColor = false end
    if unitDB.portraitBorderColor == nil then unitDB.portraitBorderColor = { 0, 0, 0, 1 } end
end

local function EnsureRestedIndicatorSettings(unitDB)
    if type(unitDB.indicators) ~= "table" then
        unitDB.indicators = {}
    end
    if type(unitDB.indicators.rested) ~= "table" then
        unitDB.indicators.rested = {
            enabled = true,
            size = 16,
            anchor = "TOPLEFT",
            offsetX = -2,
            offsetY = 2,
        }
    end
    return unitDB.indicators.rested
end

local function EnsureCombatIndicatorSettings(unitDB)
    if type(unitDB.indicators) ~= "table" then
        unitDB.indicators = {}
    end
    if type(unitDB.indicators.combat) ~= "table" then
        unitDB.indicators.combat = {
            enabled = false,
            size = 16,
            anchor = "TOPLEFT",
            offsetX = -2,
            offsetY = 2,
        }
    end
    return unitDB.indicators.combat
end

local function EnsureTargetMarkerSettings(unitDB)
    if type(unitDB.targetMarker) ~= "table" then
        unitDB.targetMarker = {
            enabled = false,
            size = 20,
            anchor = "TOP",
            xOffset = 0,
            yOffset = 8,
        }
    end
    return unitDB.targetMarker
end

local function EnsureLeaderIndicatorSettings(unitDB)
    if type(unitDB.leaderIcon) ~= "table" then
        unitDB.leaderIcon = {
            enabled = false,
            size = 16,
            anchor = "TOPLEFT",
            xOffset = -8,
            yOffset = 8,
        }
    end
    return unitDB.leaderIcon
end

local function EnsureClassificationIndicatorSettings(unitDB)
    if type(unitDB.classificationIcon) ~= "table" then
        unitDB.classificationIcon = {
            enabled = false,
            size = 16,
            anchor = "LEFT",
            xOffset = -8,
            yOffset = 0,
        }
    end
    return unitDB.classificationIcon
end

local function EnsurePrivateAurasSettings(unitDB)
    if type(unitDB.privateAuras) ~= "table" then
        unitDB.privateAuras = {
            enabled = true,
            maxPerFrame = 3,
            iconSize = 22,
            growDirection = "RIGHT",
            spacing = 2,
            anchor = "TOPLEFT",
            anchorOffsetX = 0,
            anchorOffsetY = 0,
            showCountdown = true,
            showCountdownNumbers = true,
            reverseSwipe = false,
            borderScale = 1,
            textScale = 1,
            textOffsetX = 0,
            textOffsetY = 0,
            frameLevel = 50,
        }
    end
    return unitDB.privateAuras
end

local function EnsureAuraSettings(unitDB, unitKey)
    if type(unitDB.auras) ~= "table" then
        unitDB.auras = {}
    end

    local auraDB = unitDB.auras
    if auraDB.showBuffs == nil then auraDB.showBuffs = false end
    if auraDB.showDebuffs == nil then auraDB.showDebuffs = false end
    if unitKey ~= "player" and auraDB.onlyMyDebuffs == nil then auraDB.onlyMyDebuffs = true end
    if auraDB.iconSize == nil then auraDB.iconSize = 22 end
    if auraDB.buffIconSize == nil then auraDB.buffIconSize = 22 end
    if auraDB.debuffAnchor == nil then auraDB.debuffAnchor = "TOPLEFT" end
    if auraDB.debuffGrow == nil then auraDB.debuffGrow = "RIGHT" end
    if auraDB.debuffOffsetX == nil then auraDB.debuffOffsetX = 0 end
    if auraDB.debuffOffsetY == nil then auraDB.debuffOffsetY = 2 end
    if auraDB.buffAnchor == nil then auraDB.buffAnchor = "BOTTOMLEFT" end
    if auraDB.buffGrow == nil then auraDB.buffGrow = "RIGHT" end
    if auraDB.buffOffsetX == nil then auraDB.buffOffsetX = 0 end
    if auraDB.buffOffsetY == nil then auraDB.buffOffsetY = -2 end
    if auraDB.debuffMaxIcons == nil then auraDB.debuffMaxIcons = 16 end
    if auraDB.buffMaxIcons == nil then auraDB.buffMaxIcons = 16 end
    if auraDB.debuffMaxPerRow == nil then auraDB.debuffMaxPerRow = 0 end
    if auraDB.buffMaxPerRow == nil then auraDB.buffMaxPerRow = 0 end
    if auraDB.debuffHideSwipe == nil then auraDB.debuffHideSwipe = false end
    if auraDB.buffHideSwipe == nil then auraDB.buffHideSwipe = false end
    return auraDB
end

local function EnsureAuraTextSettings(auraDB, prefix)
    local defaults = {
        Spacing = 2,
        ShowStack = true,
        StackSize = 10,
        StackAnchor = "BOTTOMRIGHT",
        StackOffsetX = -1,
        StackOffsetY = 1,
        StackColor = { 1, 1, 1, 1 },
        ShowDuration = true,
        DurationSize = 12,
        DurationAnchor = "CENTER",
        DurationOffsetX = 0,
        DurationOffsetY = 0,
        DurationColor = { 1, 1, 1, 1 },
    }

    for key, value in pairs(defaults) do
        local fullKey = prefix .. key
        if auraDB[fullKey] == nil then
            auraDB[fullKey] = value
        end
    end
end

local function RefreshUnitFrames()
    if _G.QUI_RefreshUnitFrames then
        _G.QUI_RefreshUnitFrames()
    end
    if _G.QUI_RefreshUnitFramePreview then
        _G.QUI_RefreshUnitFramePreview()
    end
end

local function RefreshUnitAuras(unitKey)
    RefreshUnitFrames()
    if _G.QUI_RefreshAuras and type(unitKey) == "string" and unitKey ~= "" then
        _G.QUI_RefreshAuras(unitKey)
    end
end

local function SetSearchContext(searchContext)
    local gui = GetGUI()
    if gui and type(gui.SetSearchContext) == "function" and type(searchContext) == "table" then
        gui:SetSearchContext(searchContext)
    end
end

local function CreateUnitSearchContext(unitKey, subTabName)
    return {
        tabIndex = 5,
        tabName = "Unit Frames",
        subTabIndex = UNIT_SUBTAB_INDEX[unitKey] or 2,
        subTabName = subTabName or (UNIT_DISPLAY_NAMES[unitKey] or unitKey or "Frame"),
        featureId = UNIT_FRAMES_FEATURE_ID,
        tileId = UNIT_FRAMES_TILE_ROUTE.tileId,
        subPageIndex = UNIT_FRAMES_TILE_ROUTE.subPageIndex,
        surfaceTabKey = UNIT_SURFACE_TABS[subTabName],
        surfaceUnitKey = unitKey,
    }
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

    function builder.Row(build)
        local row = CreateFrame("Frame", nil, sectionHost)
        row:SetHeight(FORM_ROW)
        row:SetPoint("TOPLEFT", sectionHost, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", sectionHost, "TOPRIGHT", 0, y)
        build(row)
        y = y - FORM_ROW - 10
    end

    function builder.Height(extra)
        return math.abs(y) + (extra or SECTION_BOTTOM_PAD)
    end

    return builder
end

local function GetRenderState(ctx)
    local state = ctx and ctx.state and ctx.state.generalTab or nil
    if type(state) ~= "table" then
        state = {
            defaultCells = {},
            darkCells = {},
        }
        ctx.state.generalTab = state
    end
    return state
end

local function ResetRenderState(ctx)
    local state = {
        defaultCells = {},
        darkCells = {},
    }
    ctx.state.generalTab = state
    return state
end

local function UpdateDarkModeDim(ctx, general)
    local state = GetRenderState(ctx)
    local darkOn = general and general.darkMode
    local defaultAlpha = darkOn and 0.4 or 1.0
    local darkAlpha = darkOn and 1.0 or 0.4

    if state.defaultCells.healthColor then
        state.defaultCells.healthColor:SetAlpha(defaultAlpha)
    end
    if state.defaultCells.bgColor then
        state.defaultCells.bgColor:SetAlpha(defaultAlpha)
    end
    if state.darkCells.healthColor then
        state.darkCells.healthColor:SetAlpha(darkAlpha)
    end
    if state.darkCells.bgColor then
        state.darkCells.bgColor:SetAlpha(darkAlpha)
    end
end

local function UpdateDefaultClassDim(ctx, general)
    local state = GetRenderState(ctx)
    if not state.defaultCells.healthColor then
        return
    end

    local alpha = general and general.defaultUseClassColor and 0.4 or 1.0
    if general and general.darkMode then
        alpha = 0.4
    end
    state.defaultCells.healthColor:SetAlpha(alpha)
end

local function ShowReloadConfirmation()
    local gui = GetGUI()
    if not gui or type(gui.ShowConfirmation) ~= "function" then
        return
    end

    gui:ShowConfirmation({
        title = "Reload UI?",
        message = "Enabling or disabling unit frames requires a UI reload to take effect.",
        acceptText = "Reload",
        cancelText = "Later",
        onAccept = function()
            QUI:SafeReload()
        end,
    })
end

local function RenderEnableSection(sectionHost, ctx)
    local gui = GetGUI()
    local db = ResolveGeneralDB()
    if not gui or not db then
        return nil
    end

    ResetRenderState(ctx)

    local builder = CreateSectionBuilder(sectionHost, ctx, GENERAL_SEARCH_CONTEXT)
    if not builder then
        return nil
    end

    builder.Row(function(row)
        local checkbox = gui:CreateFormCheckbox(
            row,
            "Enable Unitframes (Req. Reload)",
            "enabled",
            db.ufdb,
            function()
                RefreshUnitFrames()
                ShowReloadConfirmation()
            end,
            {
                description = "Master toggle for QUI unit frames. Turning this off restores the Blizzard default unit frames after a reload.",
            }
        )
        checkbox:SetPoint("TOPLEFT", 0, 0)
        checkbox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    end)

    return builder.Height(0)
end

local function RenderDefaultColorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local db = ResolveGeneralDB()
    if not gui or not optionsAPI or not db then
        return nil
    end

    local renderState = GetRenderState(ctx)
    local builder = CreateSectionBuilder(sectionHost, ctx, GENERAL_SEARCH_CONTEXT)
    if not builder then
        return nil
    end

    builder.Header("Default Unit Colors")
    builder.Description("Colors and opacity applied when Dark Mode is disabled.")

    local card = builder.Card()

    local classColors = gui:CreateFormCheckbox(card.frame, nil, "defaultUseClassColor", db.general, function()
        RefreshUnitFrames()
        UpdateDefaultClassDim(ctx, db.general)
    end, {
        description = "Color player health bars by class. Disables the Default Health Color swatch below while on.",
    })

    local healthColorPicker = gui:CreateFormColorPicker(
        card.frame,
        nil,
        "defaultHealthColor",
        db.general,
        RefreshUnitFrames,
        { noAlpha = true },
        {
            description = "Solid color used for health bars when Use Class Colors is off.",
        }
    )
    renderState.defaultCells.healthColor = optionsAPI.BuildSettingRow(card.frame, "Default Health Color", healthColorPicker)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Use Class Colors", classColors),
        renderState.defaultCells.healthColor
    )

    local backgroundColorPicker = gui:CreateFormColorPicker(
        card.frame,
        nil,
        "defaultBgColor",
        db.general,
        RefreshUnitFrames,
        { noAlpha = true },
        {
            description = "Color drawn behind the health bar, visible through the Background Opacity slider.",
        }
    )
    renderState.defaultCells.bgColor = optionsAPI.BuildSettingRow(card.frame, "Default Background Color", backgroundColorPicker)
    local healthOpacity = gui:CreateFormSlider(
        card.frame,
        nil,
        0.1,
        1.0,
        0.01,
        "defaultHealthOpacity",
        db.general,
        RefreshUnitFrames,
        nil,
        {
            description = "Opacity of the filled portion of the health bar. 1.0 is fully opaque.",
        }
    )
    card.AddRow(
        renderState.defaultCells.bgColor,
        optionsAPI.BuildSettingRow(card.frame, "Health Opacity", healthOpacity)
    )

    local backgroundOpacity = gui:CreateFormSlider(
        card.frame,
        nil,
        0.1,
        1.0,
        0.01,
        "defaultBgOpacity",
        db.general,
        RefreshUnitFrames,
        nil,
        {
            description = "Opacity of the bar background shown behind the health fill.",
        }
    )
    local frameOpacity = gui:CreateFormSlider(
        card.frame,
        nil,
        0.1,
        1.0,
        0.01,
        "defaultOpacity",
        db.general,
        RefreshUnitFrames,
        nil,
        {
            description = "Overall opacity of the unit frame, multiplied on top of the individual bar opacities.",
        }
    )
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Background Opacity", backgroundOpacity),
        optionsAPI.BuildSettingRow(card.frame, "Frame Opacity", frameOpacity)
    )

    builder.CloseCard(card)
    UpdateDefaultClassDim(ctx, db.general)
    return builder.Height()
end

local function RenderDarkModeSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local db = ResolveGeneralDB()
    if not gui or not optionsAPI or not db then
        return nil
    end

    local renderState = GetRenderState(ctx)
    local builder = CreateSectionBuilder(sectionHost, ctx, GENERAL_SEARCH_CONTEXT)
    if not builder then
        return nil
    end

    builder.Header("Dark Mode")
    builder.Description("Instantly applies dark flat colors to all unit frame health bars.")

    local card = builder.Card()

    local darkMode = gui:CreateFormCheckbox(card.frame, nil, "darkMode", db.general, function()
        RefreshUnitFrames()
        UpdateDarkModeDim(ctx, db.general)
    end, {
        description = "Apply flat dark colors to every unit frame's health bar. When off, the Default Unit Colors above are used instead.",
    })

    local darkHealthColor = gui:CreateFormColorPicker(
        card.frame,
        nil,
        "darkModeHealthColor",
        db.general,
        RefreshUnitFrames,
        { noAlpha = true },
        {
            description = "Health bar color used while Dark Mode is on.",
        }
    )
    renderState.darkCells.healthColor = optionsAPI.BuildSettingRow(card.frame, "Darkmode Health Color", darkHealthColor)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Enable Dark Mode", darkMode),
        renderState.darkCells.healthColor
    )

    local darkBackgroundColor = gui:CreateFormColorPicker(
        card.frame,
        nil,
        "darkModeBgColor",
        db.general,
        RefreshUnitFrames,
        { noAlpha = true },
        {
            description = "Bar background color used while Dark Mode is on.",
        }
    )
    renderState.darkCells.bgColor = optionsAPI.BuildSettingRow(card.frame, "Darkmode Background Color", darkBackgroundColor)
    local darkHealthOpacity = gui:CreateFormSlider(
        card.frame,
        nil,
        0.1,
        1.0,
        0.01,
        "darkModeHealthOpacity",
        db.general,
        RefreshUnitFrames,
        nil,
        {
            description = "Opacity of the health fill while Dark Mode is on.",
        }
    )
    card.AddRow(
        renderState.darkCells.bgColor,
        optionsAPI.BuildSettingRow(card.frame, "Darkmode Health Opacity", darkHealthOpacity)
    )

    local darkBackgroundOpacity = gui:CreateFormSlider(
        card.frame,
        nil,
        0.1,
        1.0,
        0.01,
        "darkModeBgOpacity",
        db.general,
        RefreshUnitFrames,
        nil,
        {
            description = "Opacity of the bar background while Dark Mode is on.",
        }
    )
    local darkFrameOpacity = gui:CreateFormSlider(
        card.frame,
        nil,
        0.1,
        1.0,
        0.01,
        "darkModeOpacity",
        db.general,
        RefreshUnitFrames,
        nil,
        {
            description = "Overall frame opacity while Dark Mode is on, multiplied on top of the individual bar opacities.",
        }
    )
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Darkmode Background Opacity", darkBackgroundOpacity),
        optionsAPI.BuildSettingRow(card.frame, "Darkmode Frame Opacity", darkFrameOpacity)
    )

    builder.CloseCard(card)
    UpdateDarkModeDim(ctx, db.general)
    UpdateDefaultClassDim(ctx, db.general)
    return builder.Height()
end

local function RenderTextColorOverridesSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local db = ResolveGeneralDB()
    if not gui or not optionsAPI or not db then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, GENERAL_SEARCH_CONTEXT)
    if not builder then
        return nil
    end

    builder.Header("Text Class Color Overrides")
    builder.Description("Apply class / reaction color to text across ALL unit frames. Recommended for Dark Mode.")

    local card = builder.Card()

    local nameText = gui:CreateFormCheckbox(card.frame, nil, "masterColorNameText", db.general, RefreshUnitFrames, {
        description = "Color every unit frame's name text by class or reaction, overriding per-frame name color settings.",
    })
    local healthText = gui:CreateFormCheckbox(card.frame, nil, "masterColorHealthText", db.general, RefreshUnitFrames, {
        description = "Color every unit frame's health text by class or reaction, overriding per-frame health-text color settings.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Color ALL Name Text", nameText),
        optionsAPI.BuildSettingRow(card.frame, "Color ALL Health Text", healthText)
    )

    local powerText = gui:CreateFormCheckbox(card.frame, nil, "masterColorPowerText", db.general, RefreshUnitFrames, {
        description = "Color every unit frame's power text by class or reaction, overriding per-frame power-text color settings.",
    })
    local castbarText = gui:CreateFormCheckbox(card.frame, nil, "masterColorCastbarText", db.general, RefreshUnitFrames, {
        description = "Color every unit frame's castbar text by class or reaction, overriding per-frame castbar-text color settings.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Color ALL Power Text", powerText),
        optionsAPI.BuildSettingRow(card.frame, "Color ALL Castbar Text", castbarText)
    )

    local targetOfTargetText = gui:CreateFormCheckbox(card.frame, nil, "masterColorToTText", db.general, RefreshUnitFrames, {
        description = "Color every target-of-target unit frame's text by class or reaction, overriding per-frame target-of-target text color settings.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Color ALL ToT Text", targetOfTargetText))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderTooltipsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local db = ResolveGeneralDB()
    if not gui or not optionsAPI or not db then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, GENERAL_SEARCH_CONTEXT)
    if not builder then
        return nil
    end

    builder.Header("Tooltips")

    local card = builder.Card()
    local showTooltips = gui:CreateFormCheckbox(card.frame, nil, "showTooltips", db.unitFramesGeneral, RefreshUnitFrames, {
        description = "Show the standard unit tooltip when you hover a QUI unit frame. Disable to keep hovers silent.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Show Tooltip for Unitframes", showTooltips))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderSmootherUpdatesSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local db = ResolveGeneralDB()
    if not gui or not optionsAPI or not db then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, GENERAL_SEARCH_CONTEXT)
    if not builder then
        return nil
    end

    builder.Header("Smoother Updates")
    builder.Description("Enable for maximum smoothness at the cost of extra CPU usage.")

    local card = builder.Card()
    local smootherAnimation = gui:CreateFormCheckbox(card.frame, nil, "smootherAnimation", db.unitFramesGeneral, RefreshUnitFrames, {
        description = "Interpolate health and power bar changes frame-by-frame for smoother motion. Costs extra CPU on low-end setups.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Smoother Animation", smootherAnimation))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderHostilityColorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local db = ResolveGeneralDB()
    if not gui or not optionsAPI or not db then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, GENERAL_SEARCH_CONTEXT)
    if not builder then
        return nil
    end

    builder.Header("Hostility Colors")
    builder.Description("Customize hostile, neutral, and friendly NPC colors.")

    local card = builder.Card()

    local hostileColor = gui:CreateFormColorPicker(
        card.frame,
        nil,
        "hostilityColorHostile",
        db.general,
        RefreshUnitFrames,
        { noAlpha = true },
        {
            description = "Color used for hostile NPC and enemy player health bars.",
        }
    )
    local neutralColor = gui:CreateFormColorPicker(
        card.frame,
        nil,
        "hostilityColorNeutral",
        db.general,
        RefreshUnitFrames,
        { noAlpha = true },
        {
            description = "Color used for neutral NPC health bars.",
        }
    )
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Hostile Color", hostileColor),
        optionsAPI.BuildSettingRow(card.frame, "Neutral Color", neutralColor)
    )

    local friendlyColor = gui:CreateFormColorPicker(
        card.frame,
        nil,
        "hostilityColorFriendly",
        db.general,
        RefreshUnitFrames,
        { noAlpha = true },
        {
            description = "Color used for friendly NPC and cross-faction player health bars.",
        }
    )
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Friendly Color", friendlyColor))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderFrameEnableSection(sectionHost, ctx)
    local gui = GetGUI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not unit then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Frame"))
    if not builder then
        return nil
    end

    builder.Row(function(row)
        local checkbox = gui:CreateFormCheckbox(
            row,
            "Enable " .. unit.displayName .. " Frame",
            "enabled",
            unit.unitDB,
            function()
                ShowReloadConfirmation()
            end,
            {
                description = "Enable QUI's " .. unit.displayName .. " unit frame. Disabling hands this unit back to the Blizzard default frame after a reload.",
            }
        )
        checkbox:SetPoint("TOPLEFT", 0, 0)
        checkbox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    end)

    return builder.Height(0)
end

local function RenderFrameStandaloneCastbarSection(sectionHost, ctx)
    local gui = GetGUI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not unit or unitKey ~= "player" then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Frame"))
    if not builder then
        return nil
    end

    builder.Row(function(row)
        local checkbox = gui:CreateFormCheckbox(
            row,
            "Enable Player Castbar (Standalone Mode)",
            "standaloneCastbar",
            unit.unitDB,
            function(value)
                if _G.QUI_ToggleStandaloneCastbar then
                    _G.QUI_ToggleStandaloneCastbar()
                end
                if value then
                    return
                end

                local playerFrameEnabled = unit.ufdb and unit.ufdb.enabled and unit.unitDB.enabled
                if not playerFrameEnabled then
                    local confirm = GetGUI()
                    if confirm and type(confirm.ShowConfirmation) == "function" then
                        confirm:ShowConfirmation({
                            title = "Reload UI?",
                            message = "A reload is required to restore the default Blizzard player castbar.",
                            acceptText = "Reload",
                            cancelText = "Later",
                            onAccept = function()
                                QUI:SafeReload()
                            end,
                        })
                    end
                end
            end,
            {
                description = "Keep the QUI player castbar available even when the QUI Player Frame is disabled. Only takes effect when unit frames are off or the Player Frame itself is off.",
            }
        )
        checkbox:SetPoint("TOPLEFT", 0, 0)
        checkbox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    end)
    builder.Description("Standalone mode keeps the QUI Player Castbar available when Unit Frames are disabled globally or when the Player Frame is disabled. It has no effect while the QUI Player Frame is enabled.")

    return builder.Height()
end

local function RenderFrameAppearanceSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Frame"))
    if not builder then
        return nil
    end

    builder.Header("Frame Size & Appearance")
    local card = builder.Card()

    local widthCallback = RefreshUnitFrames
    if unitKey == "player" then
        widthCallback = function()
            RefreshUnitFrames()
            if _G.QUI_UpdateLockedCastbarToFrame then
                _G.QUI_UpdateLockedCastbarToFrame()
            end
        end
    end

    local widthSlider = gui:CreateFormSlider(card.frame, nil, 100, 500, 1, "width", unit.unitDB, widthCallback, nil, {
        description = "Frame width in pixels.",
    })
    local heightSlider = gui:CreateFormSlider(card.frame, nil, 20, 100, 1, "height", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Frame height in pixels. This is the total frame height, including the power bar if one is shown.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Width", widthSlider),
        optionsAPI.BuildSettingRow(card.frame, "Height", heightSlider)
    )

    local borderSlider = gui:CreateFormSlider(card.frame, nil, 0, 5, 1, "borderSize", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Border thickness in pixels around the frame. Set to 0 to hide the border entirely.",
    })
    local textureDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.GetTextureList(), "texture", unit.unitDB, RefreshUnitFrames, {
        description = "Statusbar texture used for the health bar. Supports SharedMedia.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Border Size", borderSlider),
        optionsAPI.BuildSettingRow(card.frame, "Bar Texture", textureDropdown)
    )

    if unitKey == "boss" then
        local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 100, 1, "spacing", unit.unitDB, RefreshUnitFrames, nil, {
            description = "Vertical spacing in pixels between adjacent boss frames in an encounter.",
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Spacing", spacingSlider))
    elseif unitKey == "target" then
        local invertCheckbox = gui:CreateFormCheckbox(card.frame, nil, "invertHealthDirection", unit.unitDB, RefreshUnitFrames, {
            description = "Fill the target's health bar left-to-right instead of right-to-left, so both the player and target bars grow inward toward the center.",
        })
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Invert Healthbar Direction (LTR)", invertCheckbox))
    end

    builder.CloseCard(card)
    return builder.Height()
end

local function BuildFrameTabFeature(unitKey)
    if FRAME_TAB_FEATURES[unitKey] then
        return FRAME_TAB_FEATURES[unitKey]
    end

    local sections = { "enable" }
    if unitKey == "player" then
        sections[#sections + 1] = "standaloneCastbar"
    end
    sections[#sections + 1] = "frameAppearance"

    local feature = Schema.Feature({
        id = "unitFramesFrameTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = sections,
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
                render = RenderFrameEnableSection,
            }),
            Schema.Section({
                id = "standaloneCastbar",
                kind = "custom",
                minHeight = 60,
                render = RenderFrameStandaloneCastbarSection,
            }),
            Schema.Section({
                id = "frameAppearance",
                kind = "custom",
                minHeight = 120,
                render = RenderFrameAppearanceSection,
            }),
        },
    })

    FRAME_TAB_FEATURES[unitKey] = feature
    return feature
end

local function RenderBarsHealthColorsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local hasHostility = UnitHasHostilityColors(unitKey)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Bars"))
    if not builder then
        return nil
    end

    builder.Header("Health Bar Colors")
    if hasHostility then
        builder.Description("Class color for players, hostility color for NPCs. Custom color is the fallback.")
    end

    local card = builder.Card()
    local customCell

    local classCheckbox = gui:CreateFormCheckbox(card.frame, nil, "useClassColor", unit.unitDB, RefreshUnitFrames, {
        description = "Color this frame's health bar by class when the unit is a player. Higher priority than Hostility Color or Custom Color.",
    })

    if hasHostility then
        local hostilityCheckbox = gui:CreateFormCheckbox(card.frame, nil, "useHostilityColor", unit.unitDB, function()
            RefreshUnitFrames()
            if customCell then
                customCell:SetAlpha(unit.unitDB.useHostilityColor and 0.4 or 1.0)
            end
        end, {
            description = "Color NPC health bars by hostility using the colors from the Hostility Colors section in General. Disables Custom Color while on.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Use Class Color", classCheckbox),
            optionsAPI.BuildSettingRow(card.frame, "Use Hostility Color", hostilityCheckbox)
        )

        local customColor = gui:CreateFormColorPicker(card.frame, nil, "customHealthColor", unit.unitDB, RefreshUnitFrames, nil, {
            description = "Fallback solid color for the health bar when neither class color nor hostility color applies.",
        })
        customCell = optionsAPI.BuildSettingRow(card.frame, "Custom Color", customColor)
        customCell:SetAlpha(unit.unitDB.useHostilityColor and 0.4 or 1.0)
        card.AddRow(customCell)
    else
        local customColor = gui:CreateFormColorPicker(card.frame, nil, "customHealthColor", unit.unitDB, RefreshUnitFrames, nil, {
            description = "Fallback solid color for the health bar when Use Class Color is off.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Use Class Color", classCheckbox),
            optionsAPI.BuildSettingRow(card.frame, "Custom Color", customColor)
        )
    end

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderBarsAbsorbSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local absorbs = EnsureAbsorbSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Bars"))
    if not builder then
        return nil
    end

    builder.Header("Absorb Indicator")
    local card = builder.Card()

    local enabledCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", absorbs, RefreshUnitFrames, {
        description = "Overlay an indicator on the health bar showing the size of incoming damage absorbs.",
    })
    local opacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "opacity", absorbs, RefreshUnitFrames, nil, {
        description = "Opacity of the absorb shield overlay.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Absorb Shields", enabledCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Opacity", opacitySlider)
    )

    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, "color", absorbs, RefreshUnitFrames, nil, {
        description = "Tint used for the absorb overlay.",
    })
    local textureDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.GetTextureList(), "texture", absorbs, RefreshUnitFrames, {
        description = "Statusbar texture used for the absorb overlay. Stripes or patterned textures make absorbs easier to read at a glance.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Absorb Color", colorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Absorb Texture", textureDropdown)
    )

    builder.CloseCard(card)
    builder.Description("Supports SharedMedia textures. Install the SharedMedia addon to add your own.")
    return builder.Height()
end

local function RenderBarsHealPredictionSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or not UnitHasHealPrediction(unitKey) then
        return nil
    end

    local healPrediction = EnsureHealPredictionSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Bars"))
    if not builder then
        return nil
    end

    builder.Header("Heal Prediction")
    local card = builder.Card()

    local enabledCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", healPrediction, RefreshUnitFrames, {
        description = "Overlay an indicator on the health bar showing heals being cast on this unit before they land.",
    })
    local opacitySlider = gui:CreateFormSlider(card.frame, nil, 0, 1, 0.05, "opacity", healPrediction, RefreshUnitFrames, nil, {
        description = "Opacity of the incoming-heal overlay.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Incoming Heals", enabledCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Opacity", opacitySlider)
    )

    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, "color", healPrediction, RefreshUnitFrames, { noAlpha = true }, {
        description = "Tint used for the incoming-heal overlay.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Heal Color", colorPicker))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderBarsPowerSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Bars"))
    if not builder then
        return nil
    end

    builder.Header("Power Bar")
    local card = builder.Card()
    local customColorCell

    local showPowerCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showPowerBar", unit.unitDB, RefreshUnitFrames, {
        description = "Show a power bar below the health bar on this frame.",
    })
    local powerHeightSlider = gui:CreateFormSlider(card.frame, nil, 1, 20, 1, "powerBarHeight", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Height of the power bar in pixels. Counted as part of the overall frame Height.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Power Bar", showPowerCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Power Bar Height", powerHeightSlider)
    )

    local borderCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarBorder", unit.unitDB, RefreshUnitFrames, {
        description = "Draw a thin border around the power bar to visually separate it from the health bar above.",
    })
    local usePowerTypeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerBarUsePowerColor", unit.unitDB, function()
        RefreshUnitFrames()
        if customColorCell then
            customColorCell:SetAlpha(unit.unitDB.powerBarUsePowerColor and 0.4 or 1.0)
        end
    end, {
        description = "Color the power bar by power type. Disables the Custom Bar Color swatch below while on.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Power Bar Border", borderCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Use Power Type Color", usePowerTypeCheckbox)
    )

    local powerColorPicker = gui:CreateFormColorPicker(card.frame, nil, "powerBarColor", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Solid color for the power bar when Use Power Type Color is off.",
    })
    customColorCell = optionsAPI.BuildSettingRow(card.frame, "Custom Bar Color", powerColorPicker)
    customColorCell:SetAlpha(unit.unitDB.powerBarUsePowerColor and 0.4 or 1.0)
    card.AddRow(customColorCell)

    builder.CloseCard(card)
    return builder.Height()
end

local function BuildBarsTabFeature(unitKey)
    if BARS_TAB_FEATURES[unitKey] then
        return BARS_TAB_FEATURES[unitKey]
    end

    local sections = {
        "healthColors",
        "absorb",
    }
    if UnitHasHealPrediction(unitKey) then
        sections[#sections + 1] = "healPrediction"
    end
    sections[#sections + 1] = "power"

    local feature = Schema.Feature({
        id = "unitFramesBarsTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = sections,
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = "healthColors",
                kind = "custom",
                minHeight = 96,
                render = RenderBarsHealthColorsSection,
            }),
            Schema.Section({
                id = "absorb",
                kind = "custom",
                minHeight = 96,
                render = RenderBarsAbsorbSection,
            }),
            Schema.Section({
                id = "healPrediction",
                kind = "custom",
                minHeight = 72,
                render = RenderBarsHealPredictionSection,
            }),
            Schema.Section({
                id = "power",
                kind = "custom",
                minHeight = 86,
                render = RenderBarsPowerSection,
            }),
        },
    })

    BARS_TAB_FEATURES[unitKey] = feature
    return feature
end

local CASTBAR_TICK_SOURCE_OPTIONS = {
    { value = "auto",        text = "Auto (Static then Runtime)" },
    { value = "static",      text = "Static Only" },
    { value = "runtimeOnly", text = "Runtime Calibration Only" },
}

local CASTBAR_COPY_KEYS = {
    "width", "height", "fontSize", "borderSize", "texture", "showIcon", "enabled",
    "iconAnchor", "iconSpacing", "spellTextAnchor", "spellTextOffsetX", "spellTextOffsetY",
    "timeTextAnchor", "timeTextOffsetX", "timeTextOffsetY", "showSpellText", "showTimeText",
    "useClassColor", "channelFillForward",
}

local CASTBAR_UNIT_COPY_LABELS = {
    player = "Player", target = "Target", targettarget = "ToT",
    focus = "Focus", pet = "Pet", boss = "Boss",
}

local function EnsureCastbarSettings(unitDB, unitKey)
    if type(unitDB.castbar) ~= "table" then
        unitDB.castbar = {}
    end
    local castDB = unitDB.castbar
    local defaultShowChannelTicks = (unitKey == "player")

    if castDB.enabled == nil then castDB.enabled = true end
    castDB.fontSize = castDB.fontSize or 12
    castDB.iconSize = castDB.iconSize or 25
    castDB.iconScale = castDB.iconScale or 1.0
    castDB.height = castDB.height or 25
    castDB.width = castDB.width or 250
    if castDB.widthAdjustment == nil then castDB.widthAdjustment = 0 end
    castDB.borderSize = castDB.borderSize or 1
    castDB.iconBorderSize = castDB.iconBorderSize or 2
    castDB.texture = castDB.texture or "Solid"
    if castDB.useClassColor == nil then castDB.useClassColor = false end
    if castDB.color == nil then
        castDB.color = { 1, 0.7, 0, 1 }
    elseif not castDB.color[4] or castDB.color[4] == 0 then
        castDB.color[4] = 1
    end
    if castDB.bgColor == nil then castDB.bgColor = { 0.149, 0.149, 0.149, 1 } end
    if castDB.notInterruptibleColor == nil then castDB.notInterruptibleColor = { 0.7, 0.2, 0.2, 1 } end
    if castDB.gcdColor == nil then
        castDB.gcdColor = { castDB.color[1], castDB.color[2], castDB.color[3], castDB.color[4] or 1 }
    end
    if castDB.showChannelTicks == nil then castDB.showChannelTicks = defaultShowChannelTicks end
    castDB.channelTickThickness = castDB.channelTickThickness or 1
    castDB.channelTickColor = castDB.channelTickColor or { 1, 1, 1, 0.9 }
    castDB.channelTickMinConfidence = castDB.channelTickMinConfidence or 0.7
    castDB.channelTickSourcePolicy = castDB.channelTickSourcePolicy or "auto"
    if castDB.channelFillForward == nil then castDB.channelFillForward = false end
    if castDB.maxLength == nil then castDB.maxLength = 0 end
    if castDB.iconAnchor == nil then castDB.iconAnchor = "LEFT" end
    if castDB.iconSpacing == nil then castDB.iconSpacing = 0 end
    if castDB.showIcon == nil then castDB.showIcon = true end
    if castDB.spellTextAnchor == nil then castDB.spellTextAnchor = "LEFT" end
    if castDB.spellTextOffsetX == nil then castDB.spellTextOffsetX = 4 end
    if castDB.spellTextOffsetY == nil then castDB.spellTextOffsetY = 0 end
    if castDB.showSpellText == nil then castDB.showSpellText = true end
    if castDB.timeTextAnchor == nil then castDB.timeTextAnchor = "RIGHT" end
    if castDB.timeTextOffsetX == nil then castDB.timeTextOffsetX = -4 end
    if castDB.timeTextOffsetY == nil then castDB.timeTextOffsetY = 0 end
    if castDB.showTimeText == nil then castDB.showTimeText = true end
    if castDB.previewMode == nil then castDB.previewMode = false end

    if not castDB.anchor then
        if castDB.lockedToEssential then castDB.anchor = "essential"
        elseif castDB.lockedToUtility then castDB.anchor = "utility"
        elseif castDB.lockedToFrame then castDB.anchor = "unitframe"
        else castDB.anchor = "none" end
        castDB.lockedToEssential = nil
        castDB.lockedToUtility = nil
        castDB.lockedToFrame = nil
    end

    if unitKey == "player" then
        if castDB.showGCD == nil then castDB.showGCD = false end
        if castDB.showGCDReverse == nil then castDB.showGCDReverse = false end
        if castDB.showGCDMelee == nil then castDB.showGCDMelee = (castDB.showGCDMeleeOnly == true) end
        if castDB.hideTimeTextOnEmpowered == nil then castDB.hideTimeTextOnEmpowered = false end
        if castDB.empoweredLevelTextAnchor == nil then castDB.empoweredLevelTextAnchor = "CENTER" end
        if castDB.empoweredLevelTextOffsetX == nil then castDB.empoweredLevelTextOffsetX = 0 end
        if castDB.empoweredLevelTextOffsetY == nil then castDB.empoweredLevelTextOffsetY = 0 end
        if castDB.showEmpoweredLevel == nil then castDB.showEmpoweredLevel = false end
        if type(castDB.empoweredStageColors) ~= "table" then castDB.empoweredStageColors = {} end
        if type(castDB.empoweredFillColors) ~= "table" then castDB.empoweredFillColors = {} end
    end

    return castDB
end

local function CopyCastbarSettings(sourceDB, targetDB, sourceUnitKey, targetUnitKey)
    if not sourceDB or not targetDB then return end
    for _, key in ipairs(CASTBAR_COPY_KEYS) do
        if sourceDB[key] ~= nil then targetDB[key] = sourceDB[key] end
    end
    local skipTicks = (sourceUnitKey == "boss") or (targetUnitKey == "boss")
        or (sourceUnitKey == "pet") or (targetUnitKey == "pet")
    if not skipTicks then
        for _, key in ipairs({ "showChannelTicks", "channelTickThickness", "channelTickMinConfidence", "channelTickSourcePolicy" }) do
            if sourceDB[key] ~= nil then targetDB[key] = sourceDB[key] end
        end
        if sourceDB.channelTickColor then
            targetDB.channelTickColor = { sourceDB.channelTickColor[1], sourceDB.channelTickColor[2], sourceDB.channelTickColor[3], sourceDB.channelTickColor[4] }
        end
    end
    for _, colorKey in ipairs({ "color", "bgColor", "gcdColor", "notInterruptibleColor" }) do
        local c = sourceDB[colorKey]
        if c then targetDB[colorKey] = { c[1], c[2], c[3], c[4] } end
    end
    if sourceDB.empoweredStageColors then
        targetDB.empoweredStageColors = {}
        for i = 1, 5 do
            local c = sourceDB.empoweredStageColors[i]
            if c then targetDB.empoweredStageColors[i] = { c[1], c[2], c[3], c[4] } end
        end
    end
    if sourceDB.empoweredFillColors then
        targetDB.empoweredFillColors = {}
        for i = 1, 5 do
            local c = sourceDB.empoweredFillColors[i]
            if c then targetDB.empoweredFillColors[i] = { c[1], c[2], c[3], c[4] } end
        end
    end
end

local function RenderCastbarSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local castDB = EnsureCastbarSettings(unit.unitDB, unitKey)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Castbar"))
    if not builder then
        return nil
    end

    local refresh = RefreshUnitFrames

    -- General -----------------------------------------------------------
    builder.Header("General")
    local generalCard = builder.Card()
    local enableCheckbox = gui:CreateFormCheckbox(generalCard.frame, nil, "enabled", castDB, refresh, {
        description = "Show the castbar for this unit.",
    })
    local showIconCheckbox = gui:CreateFormCheckbox(generalCard.frame, nil, "showIcon", castDB, refresh, {
        description = "Show the spell icon beside the castbar.",
    })
    generalCard.AddRow(
        optionsAPI.BuildSettingRow(generalCard.frame, "Enable Castbar", enableCheckbox),
        optionsAPI.BuildSettingRow(generalCard.frame, "Show Spell Icon", showIconCheckbox)
    )

    local channelFillCheckbox = gui:CreateFormCheckbox(generalCard.frame, nil, "channelFillForward", castDB, refresh, {
        description = "Channeled spells fill the bar from empty to full instead of draining from full to empty.",
    })
    if unitKey == "player" then
        local castColorPicker
        local useClassColorCheckbox = gui:CreateFormCheckbox(generalCard.frame, nil, "useClassColor", castDB, function()
            refresh()
            if castColorPicker and castColorPicker.SetEnabled then
                castColorPicker:SetEnabled(not castDB.useClassColor)
            end
        end, {
            description = "Fill the player castbar with your class color. Disables the Castbar Color picker while on.",
        })
        generalCard.AddRow(
            optionsAPI.BuildSettingRow(generalCard.frame, "Use Class Color", useClassColorCheckbox),
            optionsAPI.BuildSettingRow(generalCard.frame, "Channel Fills Forward", channelFillCheckbox)
        )

        castColorPicker = gui:CreateFormColorPicker(generalCard.frame, nil, "color", castDB, refresh, nil, {
            description = "Base fill color of the castbar. Ignored while Use Class Color is on.",
        })
        if castDB.useClassColor and castColorPicker.SetEnabled then
            castColorPicker:SetEnabled(false)
        end
        local bgColorPicker = gui:CreateFormColorPicker(generalCard.frame, nil, "bgColor", castDB, refresh, nil, {
            description = "Color of the unfilled portion of the castbar.",
        })
        generalCard.AddRow(
            optionsAPI.BuildSettingRow(generalCard.frame, "Castbar Color", castColorPicker),
            optionsAPI.BuildSettingRow(generalCard.frame, "Background Color", bgColorPicker)
        )
    else
        generalCard.AddRow(optionsAPI.BuildSettingRow(generalCard.frame, "Channel Fills Forward", channelFillCheckbox))

        local castColorPicker = gui:CreateFormColorPicker(generalCard.frame, nil, "color", castDB, refresh, nil, {
            description = "Base fill color of the castbar. For target/focus, this is the interruptible-cast color.",
        })
        local bgColorPicker = gui:CreateFormColorPicker(generalCard.frame, nil, "bgColor", castDB, refresh, nil, {
            description = "Color of the unfilled portion of the castbar.",
        })
        generalCard.AddRow(
            optionsAPI.BuildSettingRow(generalCard.frame, "Castbar Color", castColorPicker),
            optionsAPI.BuildSettingRow(generalCard.frame, "Background Color", bgColorPicker)
        )

        if unitKey == "target" or unitKey == "focus" then
            local notInterruptiblePicker = gui:CreateFormColorPicker(generalCard.frame, nil, "notInterruptibleColor", castDB, refresh, nil, {
                description = "Color applied to the castbar when the target is casting something you can't interrupt.",
            })
            generalCard.AddRow(optionsAPI.BuildSettingRow(generalCard.frame, "Uninterruptible Cast Color", notInterruptiblePicker))
        end
    end

    local textureDropdown = gui:CreateFormDropdown(generalCard.frame, nil, optionsAPI.GetTextureList(), "texture", castDB, refresh, {
        description = "Statusbar texture used to fill the castbar. Supports SharedMedia.",
    })
    local borderSlider = gui:CreateFormSlider(generalCard.frame, nil, 0, 5, 1, "borderSize", castDB, refresh, nil, {
        description = "Thickness of the castbar outline in pixels. 0 hides the outline.",
    })
    generalCard.AddRow(
        optionsAPI.BuildSettingRow(generalCard.frame, "Bar Texture", textureDropdown),
        optionsAPI.BuildSettingRow(generalCard.frame, "Border Size", borderSlider)
    )
    builder.CloseCard(generalCard)

    -- GCD (player) ------------------------------------------------------
    if unitKey == "player" then
        builder.Header("GCD")
        local gcdCard = builder.Card()
        local showGCDCheckbox = gui:CreateFormCheckbox(gcdCard.frame, nil, "showGCD", castDB, refresh, {
            description = "Animate the player castbar as a sweep during your global cooldown even when you're not casting.",
        })
        local reverseCheckbox = gui:CreateFormCheckbox(gcdCard.frame, nil, "showGCDReverse", castDB, refresh, {
            description = "Reverse the direction of the GCD sweep on the castbar.",
        })
        gcdCard.AddRow(
            optionsAPI.BuildSettingRow(gcdCard.frame, "Show GCD as Castbar", showGCDCheckbox),
            optionsAPI.BuildSettingRow(gcdCard.frame, "Reverse Direction", reverseCheckbox)
        )

        local meleeCheckbox = gui:CreateFormCheckbox(gcdCard.frame, nil, "showGCDMelee", castDB, refresh, {
            description = "Sweep the GCD during instant melee swings, not just during spell casts.",
        })
        local gcdColorPicker = gui:CreateFormColorPicker(gcdCard.frame, nil, "gcdColor", castDB, refresh, nil, {
            description = "Fill color used for the GCD sweep (separate from the normal cast color).",
        })
        gcdCard.AddRow(
            optionsAPI.BuildSettingRow(gcdCard.frame, "Show on Melee Swings", meleeCheckbox),
            optionsAPI.BuildSettingRow(gcdCard.frame, "GCD Bar Color", gcdColorPicker)
        )
        builder.CloseCard(gcdCard)
    end

    -- Size --------------------------------------------------------------
    builder.Header("Size")
    local sizeCard = builder.Card()
    local widthSlider = gui:CreateFormSlider(sizeCard.frame, nil, 50, 2000, 1, "width", castDB, refresh, nil, {
        description = "Pixel width of the castbar.",
    })
    local heightSlider = gui:CreateFormSlider(sizeCard.frame, nil, 4, 60, 1, "height", castDB, refresh, nil, {
        description = "Pixel height of the castbar itself.",
    })
    sizeCard.AddRow(
        optionsAPI.BuildSettingRow(sizeCard.frame, "Width", widthSlider),
        optionsAPI.BuildSettingRow(sizeCard.frame, "Bar Height", heightSlider)
    )

    local iconSizeSlider = gui:CreateFormSlider(sizeCard.frame, nil, 8, 80, 1, "iconSize", castDB, refresh, nil, {
        description = "Pixel size of the spell icon beside the castbar.",
    })
    local iconScaleSlider = gui:CreateFormSlider(sizeCard.frame, nil, 0.5, 2.0, 0.1, "iconScale", castDB, refresh, nil, {
        description = "Scale multiplier applied to the spell icon. >1 enlarges it relative to the bar.",
    })
    sizeCard.AddRow(
        optionsAPI.BuildSettingRow(sizeCard.frame, "Icon Size", iconSizeSlider),
        optionsAPI.BuildSettingRow(sizeCard.frame, "Icon Scale", iconScaleSlider)
    )

    local previewCheckbox = gui:CreateFormCheckbox(sizeCard.frame, nil, "previewMode", castDB, refresh, {
        description = "Render a fake spell on the castbar for visual tuning.",
    })
    sizeCard.AddRow(optionsAPI.BuildSettingRow(sizeCard.frame, "Castbar Preview", previewCheckbox))
    builder.CloseCard(sizeCard)

    -- Channel Ticks (skip boss/pet) ------------------------------------
    if unitKey ~= "boss" and unitKey ~= "pet" then
        builder.Header("Channel Ticks")
        local tickCard = builder.Card()
        local showTicksCheckbox = gui:CreateFormCheckbox(tickCard.frame, nil, "showChannelTicks", castDB, refresh, {
            description = "Draw tick marks on the castbar at the moments a channeled spell triggers a tick.",
        })
        local thicknessSlider = gui:CreateFormSlider(tickCard.frame, nil, 1, 5, 0.5, "channelTickThickness", castDB, refresh, nil, {
            description = "Thickness of the tick markers, in pixels.",
        })
        tickCard.AddRow(
            optionsAPI.BuildSettingRow(tickCard.frame, "Show Tick Markers", showTicksCheckbox),
            optionsAPI.BuildSettingRow(tickCard.frame, "Tick Thickness", thicknessSlider)
        )

        local sourceDropdown = gui:CreateFormDropdown(tickCard.frame, nil, CASTBAR_TICK_SOURCE_OPTIONS, "channelTickSourcePolicy", castDB, refresh, {
            description = "Where the tick timings come from. Auto tries QUI's static table first, then live calibration.",
        })
        local confidenceSlider = gui:CreateFormSlider(tickCard.frame, nil, 0.5, 1.0, 0.05, "channelTickMinConfidence", castDB, refresh, nil, {
            description = "Minimum calibration confidence required before runtime-detected ticks are drawn.",
        })
        tickCard.AddRow(
            optionsAPI.BuildSettingRow(tickCard.frame, "Tick Source", sourceDropdown),
            optionsAPI.BuildSettingRow(tickCard.frame, "Min Confidence", confidenceSlider)
        )

        local tickColorPicker = gui:CreateFormColorPicker(tickCard.frame, nil, "channelTickColor", castDB, refresh, nil, {
            description = "Color of the tick markers drawn on the castbar.",
        })
        tickCard.AddRow(optionsAPI.BuildSettingRow(tickCard.frame, "Tick Color", tickColorPicker))
        builder.CloseCard(tickCard)
    end

    -- Text & Display ---------------------------------------------------
    builder.Header("Text & Display")
    local textCard = builder.Card()
    local fontSizeSlider = gui:CreateFormSlider(textCard.frame, nil, 8, 24, 1, "fontSize", castDB, refresh, nil, {
        description = "Font size used for the spell name and cast time text on the castbar.",
    })
    local maxLenSlider = gui:CreateFormSlider(textCard.frame, nil, 0, 30, 1, "maxLength", castDB, refresh, nil, {
        description = "Maximum number of characters shown for the spell name. 0 disables truncation.",
    })
    textCard.AddRow(
        optionsAPI.BuildSettingRow(textCard.frame, "Font Size", fontSizeSlider),
        optionsAPI.BuildSettingRow(textCard.frame, "Max Length (0=none)", maxLenSlider)
    )
    builder.CloseCard(textCard)

    -- Element Positioning: Icon ----------------------------------------
    builder.Header("Icon Positioning")
    local iconCard = builder.Card()
    local iconAnchorDropdown = gui:CreateFormDropdown(iconCard.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "iconAnchor", castDB, refresh, {
        description = "Which edge or corner of the castbar the spell icon attaches to.",
    })
    local iconSpacingSlider = gui:CreateFormSlider(iconCard.frame, nil, -50, 50, 1, "iconSpacing", castDB, refresh, nil, {
        description = "Pixel gap between the icon and the castbar. Negative values overlap them.",
    })
    iconCard.AddRow(
        optionsAPI.BuildSettingRow(iconCard.frame, "Icon Anchor", iconAnchorDropdown),
        optionsAPI.BuildSettingRow(iconCard.frame, "Icon Spacing", iconSpacingSlider)
    )

    local iconBorderSlider = gui:CreateFormSlider(iconCard.frame, nil, 0, 5, 0.1, "iconBorderSize", castDB, refresh, nil, {
        description = "Thickness of the border drawn around the spell icon, in pixels.",
    })
    iconCard.AddRow(optionsAPI.BuildSettingRow(iconCard.frame, "Icon Border Size", iconBorderSlider))
    builder.CloseCard(iconCard)

    -- Spell Name Text --------------------------------------------------
    builder.Header("Spell Name Text")
    local spellTextCard = builder.Card()
    local spellAnchorDropdown = gui:CreateFormDropdown(spellTextCard.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "spellTextAnchor", castDB, refresh, {
        description = "Which edge or corner of the castbar the spell name anchors to.",
    })
    local spellShowCheckbox = gui:CreateFormCheckbox(spellTextCard.frame, nil, "showSpellText", castDB, refresh, {
        description = "Display the spell name on top of the castbar.",
    })
    spellTextCard.AddRow(
        optionsAPI.BuildSettingRow(spellTextCard.frame, "Spell Text Anchor", spellAnchorDropdown),
        optionsAPI.BuildSettingRow(spellTextCard.frame, "Show Spell Text", spellShowCheckbox)
    )

    local spellOffXSlider = gui:CreateFormSlider(spellTextCard.frame, nil, -200, 200, 1, "spellTextOffsetX", castDB, refresh, nil, {
        description = "Horizontal pixel offset of the spell name from its anchor.",
    })
    local spellOffYSlider = gui:CreateFormSlider(spellTextCard.frame, nil, -200, 200, 1, "spellTextOffsetY", castDB, refresh, nil, {
        description = "Vertical pixel offset of the spell name from its anchor.",
    })
    spellTextCard.AddRow(
        optionsAPI.BuildSettingRow(spellTextCard.frame, "Spell X Offset", spellOffXSlider),
        optionsAPI.BuildSettingRow(spellTextCard.frame, "Spell Y Offset", spellOffYSlider)
    )
    builder.CloseCard(spellTextCard)

    -- Time Remaining Text ----------------------------------------------
    builder.Header("Time Remaining Text")
    local timeTextCard = builder.Card()
    local timeAnchorDropdown = gui:CreateFormDropdown(timeTextCard.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "timeTextAnchor", castDB, refresh, {
        description = "Which edge or corner of the castbar the time remaining text anchors to.",
    })
    local timeShowCheckbox = gui:CreateFormCheckbox(timeTextCard.frame, nil, "showTimeText", castDB, refresh, {
        description = "Display the cast time remaining (e.g. 1.4s) on top of the castbar.",
    })
    timeTextCard.AddRow(
        optionsAPI.BuildSettingRow(timeTextCard.frame, "Time Text Anchor", timeAnchorDropdown),
        optionsAPI.BuildSettingRow(timeTextCard.frame, "Show Time Text", timeShowCheckbox)
    )

    local timeOffXSlider = gui:CreateFormSlider(timeTextCard.frame, nil, -200, 200, 1, "timeTextOffsetX", castDB, refresh, nil, {
        description = "Horizontal pixel offset of the time text from its anchor.",
    })
    local timeOffYSlider = gui:CreateFormSlider(timeTextCard.frame, nil, -200, 200, 1, "timeTextOffsetY", castDB, refresh, nil, {
        description = "Vertical pixel offset of the time text from its anchor.",
    })
    timeTextCard.AddRow(
        optionsAPI.BuildSettingRow(timeTextCard.frame, "Time X Offset", timeOffXSlider),
        optionsAPI.BuildSettingRow(timeTextCard.frame, "Time Y Offset", timeOffYSlider)
    )
    builder.CloseCard(timeTextCard)

    -- Empowered (player) -----------------------------------------------
    if unitKey == "player" then
        builder.Header("Empowered Spells")
        local empoweredCard = builder.Card()
        local hideTimeCheckbox = gui:CreateFormCheckbox(empoweredCard.frame, nil, "hideTimeTextOnEmpowered", castDB, refresh, {
            description = "Hide the time remaining text while casting an empowered spell so the stage markers read more clearly.",
        })
        local showLevelCheckbox = gui:CreateFormCheckbox(empoweredCard.frame, nil, "showEmpoweredLevel", castDB, refresh, {
            description = "Display the current empowered stage number on the castbar while casting an empowered spell.",
        })
        empoweredCard.AddRow(
            optionsAPI.BuildSettingRow(empoweredCard.frame, "Hide Time Text on Empowered", hideTimeCheckbox),
            optionsAPI.BuildSettingRow(empoweredCard.frame, "Show Stage Number", showLevelCheckbox)
        )

        local levelAnchorDropdown = gui:CreateFormDropdown(empoweredCard.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "empoweredLevelTextAnchor", castDB, refresh, {
            description = "Where the current empowered stage number is anchored on the castbar.",
        })
        empoweredCard.AddRow(optionsAPI.BuildSettingRow(empoweredCard.frame, "Stage Number Anchor", levelAnchorDropdown))

        local levelOffXSlider = gui:CreateFormSlider(empoweredCard.frame, nil, -200, 200, 1, "empoweredLevelTextOffsetX", castDB, refresh, nil, {
            description = "Horizontal pixel offset of the empowered stage text from its anchor.",
        })
        local levelOffYSlider = gui:CreateFormSlider(empoweredCard.frame, nil, -200, 200, 1, "empoweredLevelTextOffsetY", castDB, refresh, nil, {
            description = "Vertical pixel offset of the empowered stage text from its anchor.",
        })
        empoweredCard.AddRow(
            optionsAPI.BuildSettingRow(empoweredCard.frame, "Stage Number X Offset", levelOffXSlider),
            optionsAPI.BuildSettingRow(empoweredCard.frame, "Stage Number Y Offset", levelOffYSlider)
        )
        builder.CloseCard(empoweredCard)

        local castbarMod = ns.QUI_Castbar
        local defaultStageColors = (castbarMod and castbarMod.STAGE_COLORS) or {}
        local defaultFillColors = (castbarMod and castbarMod.STAGE_FILL_COLORS) or {}
        local stagePickers, fillPickers = {}, {}

        for i = 1, 5 do
            if not castDB.empoweredStageColors[i] and defaultStageColors[i] then
                local d = defaultStageColors[i]
                castDB.empoweredStageColors[i] = { d[1], d[2], d[3], d[4] }
            end
            if not castDB.empoweredFillColors[i] and defaultFillColors[i] then
                local d = defaultFillColors[i]
                castDB.empoweredFillColors[i] = { d[1], d[2], d[3], d[4] }
            end
        end

        builder.Header("Empowered Stage Colors")
        builder.Description("Background overlay for each stage of an empowered spell.")
        local stageCard = builder.Card()
        for i = 1, 5, 2 do
            local widget1 = gui:CreateFormColorPicker(stageCard.frame, nil, i, castDB.empoweredStageColors, refresh, nil, {
                description = "Background overlay color for empowered stage " .. i .. ".",
            })
            stagePickers[i] = widget1
            local row1 = optionsAPI.BuildSettingRow(stageCard.frame, "Stage " .. i, widget1)
            local row2
            if i + 1 <= 5 then
                local widget2 = gui:CreateFormColorPicker(stageCard.frame, nil, i + 1, castDB.empoweredStageColors, refresh, nil, {
                    description = "Background overlay color for empowered stage " .. (i + 1) .. ".",
                })
                stagePickers[i + 1] = widget2
                row2 = optionsAPI.BuildSettingRow(stageCard.frame, "Stage " .. (i + 1), widget2)
            end
            if row2 then stageCard.AddRow(row1, row2) else stageCard.AddRow(row1) end
        end
        builder.CloseCard(stageCard)

        builder.Header("Empowered Fill Colors")
        builder.Description("Castbar fill color for each stage of an empowered spell.")
        local fillCard = builder.Card()
        for i = 1, 5, 2 do
            local widget1 = gui:CreateFormColorPicker(fillCard.frame, nil, i, castDB.empoweredFillColors, refresh, nil, {
                description = "Fill color used for the castbar itself during empowered stage " .. i .. ".",
            })
            fillPickers[i] = widget1
            local row1 = optionsAPI.BuildSettingRow(fillCard.frame, "Fill " .. i, widget1)
            local row2
            if i + 1 <= 5 then
                local widget2 = gui:CreateFormColorPicker(fillCard.frame, nil, i + 1, castDB.empoweredFillColors, refresh, nil, {
                    description = "Fill color used for the castbar itself during empowered stage " .. (i + 1) .. ".",
                })
                fillPickers[i + 1] = widget2
                row2 = optionsAPI.BuildSettingRow(fillCard.frame, "Fill " .. (i + 1), widget2)
            end
            if row2 then fillCard.AddRow(row1, row2) else fillCard.AddRow(row1) end
        end
        builder.CloseCard(fillCard)

        builder.Row(function(row)
            local resetBtn = gui:CreateButton(row, "Reset Empowered Colors to Defaults", 260, 24, function()
                for i = 1, 5 do
                    if defaultStageColors[i] then
                        local d = defaultStageColors[i]
                        castDB.empoweredStageColors[i] = { d[1], d[2], d[3], d[4] }
                        if stagePickers[i] and stagePickers[i].swatch then
                            stagePickers[i].swatch:SetBackdropColor(d[1], d[2], d[3], d[4])
                        end
                    end
                    if defaultFillColors[i] then
                        local d = defaultFillColors[i]
                        castDB.empoweredFillColors[i] = { d[1], d[2], d[3], d[4] }
                        if fillPickers[i] and fillPickers[i].swatch then
                            fillPickers[i].swatch:SetBackdropColor(d[1], d[2], d[3], d[4])
                        end
                    end
                end
                refresh()
            end)
            resetBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
        end)
    end

    -- Copy From Other Unit ---------------------------------------------
    local copyOptions = {}
    for _, k in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss" }) do
        if k ~= unitKey then
            copyOptions[#copyOptions + 1] = { value = k, text = CASTBAR_UNIT_COPY_LABELS[k] }
        end
    end
    local copySelector = { selected = copyOptions[1] and copyOptions[1].value or nil }

    builder.Header("Copy Settings")
    local copyCard = builder.Card()
    local copyDropdown = gui:CreateFormDropdown(copyCard.frame, nil, copyOptions, "selected", copySelector, nil, {
        description = "Pick another unit's castbar configuration to copy into this one. Click Apply to perform the copy.",
    })
    copyCard.AddRow(optionsAPI.BuildSettingRow(copyCard.frame, "Copy From Unit", copyDropdown))
    builder.CloseCard(copyCard)

    builder.Row(function(row)
        local applyBtn = gui:CreateButton(row, "Apply Copy", 100, 24, function()
            local sourceKey = copySelector.selected
            if not sourceKey then return end
            local sourceUnitDB = unit.ufdb and unit.ufdb[sourceKey]
            if sourceUnitDB and sourceUnitDB.castbar then
                CopyCastbarSettings(sourceUnitDB.castbar, castDB, sourceKey, unitKey)
                refresh()
            end
        end)
        applyBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    end)

    return builder.Height()
end

local function BuildCastbarTabFeature(unitKey)
    if CASTBAR_TAB_FEATURES[unitKey] then
        return CASTBAR_TAB_FEATURES[unitKey]
    end

    local feature = Schema.Feature({
        id = "unitFramesCastbarTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = { "castbar" },
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = "castbar",
                kind = "custom",
                minHeight = 600,
                render = RenderCastbarSection,
            }),
        },
    })

    CASTBAR_TAB_FEATURES[unitKey] = feature
    return feature
end

local function RenderTextNameSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Text"))
    if not builder then
        return nil
    end

    builder.Header("Name Text")
    local card = builder.Card()

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showName", unit.unitDB, RefreshUnitFrames, {
        description = "Show the unit's name on this frame.",
    })
    local sizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 24, 1, "nameFontSize", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Font size used for the unit's name.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Name", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Font Size", sizeSlider)
    )

    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, "nameTextColor", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Color used for the name when class/reaction coloring is not applied to name text.",
    })
    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "nameAnchor", unit.unitDB, RefreshUnitFrames, {
        description = "Where on the frame the name text is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Custom Name Text Color", colorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown)
    )

    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "nameOffsetX", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Horizontal pixel offset for the name text from its anchor. Positive moves right, negative moves left.",
    })
    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -50, 50, 1, "nameOffsetY", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Vertical pixel offset for the name text from its anchor. Positive moves up, negative moves down.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
    )

    local maxLengthSlider = gui:CreateFormSlider(card.frame, nil, 0, 30, 1, "maxNameLength", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Truncate names longer than this many characters. Set to 0 to disable truncation entirely.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Max Length (0 = none)", maxLengthSlider))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderTextTargetOfTargetSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or unitKey ~= "target" then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Text"))
    if not builder then
        return nil
    end

    builder.Header("Target Of Target Text")
    local card = builder.Card()
    local dividerCell

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showInlineToT", unit.unitDB, RefreshUnitFrames, {
        description = "Append your target's current target to the name text, using the separator and color chosen below.",
    })
    local separatorDropdown = gui:CreateFormDropdown(card.frame, nil, TOT_SEPARATOR_OPTIONS, "totSeparator", unit.unitDB, RefreshUnitFrames, {
        description = "Separator string placed between the target's name and its target's name.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Inline Target-of-Target", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "ToT Separator", separatorDropdown)
    )

    local classColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "totDividerUseClassColor", unit.unitDB, function()
        RefreshUnitFrames()
        if dividerCell then
            dividerCell:SetAlpha(unit.unitDB.totDividerUseClassColor and 0.4 or 1.0)
        end
    end, {
        description = "Color the separator between target and target-of-target by the target-of-target unit's class or reaction. Disables Custom Divider Color while on.",
    })
    local dividerColorPicker = gui:CreateFormColorPicker(card.frame, nil, "totDividerColor", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Fallback color for the separator when Color Divider By Class/React is off.",
    })
    dividerCell = optionsAPI.BuildSettingRow(card.frame, "Custom Divider Color", dividerColorPicker)
    dividerCell:SetAlpha(unit.unitDB.totDividerUseClassColor and 0.4 or 1.0)
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Color Divider By Class/React", classColorCheckbox),
        dividerCell
    )

    local limitSlider = gui:CreateFormSlider(card.frame, nil, 0, 100, 1, "totNameCharLimit", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Maximum characters shown for the target-of-target's name. Set to 0 to show the full name.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "ToT Name Character Limit", limitSlider))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderTextHealthSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Text"))
    if not builder then
        return nil
    end

    builder.Header("Health Text")
    local card = builder.Card()

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showHealth", unit.unitDB, RefreshUnitFrames, {
        description = "Show the unit's health as text on this frame. Use Display Style below to pick the format.",
    })
    local displayDropdown = gui:CreateFormDropdown(card.frame, nil, HEALTH_STYLE_OPTIONS, "healthDisplayStyle", unit.unitDB, RefreshUnitFrames, {
        description = "How health is formatted: percent only, raw value, value-plus-percent, or missing health as a negative percent/value.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Health", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Display Style", displayDropdown)
    )

    local hidePercentCheckbox = gui:CreateFormCheckbox(card.frame, nil, "hideHealthPercentSymbol", unit.unitDB, RefreshUnitFrames, {
        description = "Drop the % sign from percent-based health text for a cleaner look.",
    })
    local dividerDropdown = gui:CreateFormDropdown(card.frame, nil, HEALTH_DIVIDER_OPTIONS, "healthDivider", unit.unitDB, RefreshUnitFrames, {
        description = "Character used to separate the two values when Display Style combines value and percent.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Hide % Symbol", hidePercentCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Divider", dividerDropdown)
    )

    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, "healthTextColor", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Color used for the health text when class/reaction coloring is not applied to health text.",
    })
    local sizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 24, 1, "healthFontSize", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Font size used for the health text.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Custom Health Text Color", colorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Font Size", sizeSlider)
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "healthAnchor", unit.unitDB, RefreshUnitFrames, {
        description = "Where on the frame the health text is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "healthOffsetX", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Horizontal pixel offset for the health text from its anchor. Positive moves right, negative moves left.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown),
        optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider)
    )

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -50, 50, 1, "healthOffsetY", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Vertical pixel offset for the health text from its anchor. Positive moves up, negative moves down.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderTextPowerSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Text"))
    if not builder then
        return nil
    end

    builder.Header("Power Text")
    local card = builder.Card()
    local customColorCell

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showPowerText", unit.unitDB, RefreshUnitFrames, {
        description = "Show the unit's power value as text on the power bar.",
    })
    local formatDropdown = gui:CreateFormDropdown(card.frame, nil, POWER_TEXT_FORMAT_OPTIONS, "powerTextFormat", unit.unitDB, RefreshUnitFrames, {
        description = "How power is formatted: percent only, raw current value, or both.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Power Text", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Display Format", formatDropdown)
    )

    local hidePercentCheckbox = gui:CreateFormCheckbox(card.frame, nil, "hidePowerPercentSymbol", unit.unitDB, RefreshUnitFrames, {
        description = "Drop the % sign from percent-based power text.",
    })
    local usePowerTypeCheckbox = gui:CreateFormCheckbox(card.frame, nil, "powerTextUsePowerColor", unit.unitDB, function()
        RefreshUnitFrames()
        if customColorCell then
            customColorCell:SetAlpha(unit.unitDB.powerTextUsePowerColor and 0.4 or 1.0)
        end
    end, {
        description = "Color the power text by power type. Disables the Custom Power Text Color swatch below while on.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Hide % Symbol", hidePercentCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Use Power Type Color", usePowerTypeCheckbox)
    )

    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, "powerTextColor", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Color for the power text when Use Power Type Color is off.",
    })
    customColorCell = optionsAPI.BuildSettingRow(card.frame, "Custom Power Text Color", colorPicker)
    customColorCell:SetAlpha(unit.unitDB.powerTextUsePowerColor and 0.4 or 1.0)
    local sizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 24, 1, "powerTextFontSize", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Font size used for the power text.",
    })
    card.AddRow(
        customColorCell,
        optionsAPI.BuildSettingRow(card.frame, "Font Size", sizeSlider)
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "powerTextAnchor", unit.unitDB, RefreshUnitFrames, {
        description = "Where on the frame the power text is anchored. X/Y Offset below nudges it from this anchor point.",
    })
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "powerTextOffsetX", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Horizontal pixel offset for the power text from its anchor. Positive moves right, negative moves left.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown),
        optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider)
    )

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -50, 50, 1, "powerTextOffsetY", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Vertical pixel offset for the power text from its anchor. Positive moves up, negative moves down.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderTextStanceSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or unitKey ~= "player" then
        return nil
    end

    local stanceDB = EnsurePlayerStanceSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Text"))
    if not builder then
        return nil
    end

    builder.Header("Stance / Form Text")
    builder.Description("Displays current stance, form, or aura.")
    local card = builder.Card()

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", stanceDB, RefreshUnitFrames, {
        description = "Show a text label on the player frame naming your current stance, shapeshift form, or aura.",
    })
    local sizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 24, 1, "fontSize", stanceDB, RefreshUnitFrames, nil, {
        description = "Font size used for the stance/form text.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Stance/Form Text", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Font Size", sizeSlider)
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "anchor", stanceDB, RefreshUnitFrames, {
        description = "Where on the player frame the stance/form text is anchored.",
    })
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetX", stanceDB, RefreshUnitFrames, nil, {
        description = "Horizontal pixel offset for the stance/form text from its anchor.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown),
        optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider)
    )

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "offsetY", stanceDB, RefreshUnitFrames, nil, {
        description = "Vertical pixel offset for the stance/form text from its anchor.",
    })
    local classColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "useClassColor", stanceDB, RefreshUnitFrames, {
        description = "Color the stance/form text using your class color instead of the Custom Color below.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Use Class Color", classColorCheckbox)
    )

    local colorPicker = gui:CreateFormColorPicker(card.frame, nil, "customColor", stanceDB, RefreshUnitFrames, nil, {
        description = "Fallback color for the stance/form text when Use Class Color is off.",
    })
    local showIconCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showIcon", stanceDB, RefreshUnitFrames, {
        description = "Show an icon for the active stance/form next to the text.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Custom Color", colorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Show Icon", showIconCheckbox)
    )

    local iconSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 32, 1, "iconSize", stanceDB, RefreshUnitFrames, nil, {
        description = "Pixel size of the stance/form icon.",
    })
    local iconOffsetSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "iconOffsetX", stanceDB, RefreshUnitFrames, nil, {
        description = "Horizontal offset between the stance/form icon and its adjacent text.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Icon Size", iconSizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Icon X Offset", iconOffsetSlider)
    )

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderAuraIconsSection(sectionHost, ctx, prefix, kind)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local auraDB = EnsureAuraSettings(unit.unitDB, unitKey)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Icons"))
    if not builder then
        return nil
    end

    local refreshAuras = function()
        RefreshUnitAuras(unitKey)
    end
    local kindLower = string.lower(kind)
    local anchorKey = prefix .. "Anchor"
    local growKey = prefix .. "Grow"
    local maxKey = prefix .. "MaxIcons"
    local maxRowKey = prefix .. "MaxPerRow"
    local offsetXKey = prefix .. "OffsetX"
    local offsetYKey = prefix .. "OffsetY"
    local iconSizeKey = (prefix == "debuff") and "iconSize" or "buffIconSize"
    local hideSwipeKey = prefix .. "HideSwipe"
    local showKey = (prefix == "debuff") and "showDebuffs" or "showBuffs"

    builder.Header(kind .. " Icons")
    local card = builder.Card()

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, showKey, auraDB, refreshAuras, {
        description = "Show " .. kindLower .. " icons on this unit frame.",
    })
    local hideSwipeCheckbox = gui:CreateFormCheckbox(card.frame, nil, hideSwipeKey, auraDB, refreshAuras, {
        description = "Hide the clockwise cooldown swipe animation drawn over " .. kindLower .. " icons. Duration text still works if it is enabled below.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show " .. kind .. "s", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Hide Duration Swipe", hideSwipeCheckbox)
    )

    local iconSizeSlider = gui:CreateFormSlider(card.frame, nil, 12, 50, 1, iconSizeKey, auraDB, refreshAuras, nil, {
        description = "Pixel size of each " .. kindLower .. " icon.",
    })
    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, AURA_CORNER_OPTIONS, anchorKey, auraDB, refreshAuras, {
        description = "Which corner of the frame the first " .. kindLower .. " icon is anchored to.",
    })

    if prefix == "debuff" and unitKey ~= "player" then
        local onlyMyCheckbox = gui:CreateFormCheckbox(card.frame, nil, "onlyMyDebuffs", auraDB, refreshAuras, {
            description = "Only show debuffs cast by you. Useful when the frame is used for your own debuff tracking.",
        })
        local growDropdown = gui:CreateFormDropdown(card.frame, nil, AURA_GROW_OPTIONS, growKey, auraDB, refreshAuras, {
            description = "Direction additional " .. kindLower .. " icons are added in after the first.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Only My Debuffs", onlyMyCheckbox),
            optionsAPI.BuildSettingRow(card.frame, "Icon Size", iconSizeSlider)
        )
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown),
            optionsAPI.BuildSettingRow(card.frame, "Grow Direction", growDropdown)
        )
    else
        local growDropdown = gui:CreateFormDropdown(card.frame, nil, AURA_GROW_OPTIONS, growKey, auraDB, refreshAuras, {
            description = "Direction additional " .. kindLower .. " icons are added in after the first.",
        })
        card.AddRow(
            optionsAPI.BuildSettingRow(card.frame, "Icon Size", iconSizeSlider),
            optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown)
        )
        card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Grow Direction", growDropdown))
    end

    local maxIconsSlider = gui:CreateFormSlider(card.frame, nil, 1, 32, 1, maxKey, auraDB, refreshAuras, nil, {
        description = "Hard cap on how many " .. kindLower .. " icons this frame displays at once.",
    })
    local maxPerRowSlider = gui:CreateFormSlider(card.frame, nil, 0, 16, 1, maxRowKey, auraDB, refreshAuras, nil, {
        description = "How many icons fit in a row before wrapping. Set to 0 to keep them all on a single row.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Max Icons", maxIconsSlider),
        optionsAPI.BuildSettingRow(card.frame, "Max Per Row (0 = unlimited)", maxPerRowSlider)
    )

    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, offsetXKey, auraDB, refreshAuras, nil, {
        description = "Horizontal pixel offset for the " .. kindLower .. " block from its anchor corner.",
    })
    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, offsetYKey, auraDB, refreshAuras, nil, {
        description = "Vertical pixel offset for the " .. kindLower .. " block from its anchor corner.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
    )

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderAuraTextSection(sectionHost, ctx, prefix, kind)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or unitKey == "pet" then
        return nil
    end

    local auraDB = EnsureAuraSettings(unit.unitDB, unitKey)
    EnsureAuraTextSettings(auraDB, prefix)

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Icons"))
    if not builder then
        return nil
    end

    local refreshAuras = function()
        RefreshUnitAuras(unitKey)
    end
    local kindLower = string.lower(kind)

    builder.Header(kind .. " Stack & Duration")
    local card = builder.Card()

    local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 10, 1, prefix .. "Spacing", auraDB, refreshAuras, nil, {
        description = "Pixel gap between adjacent " .. kindLower .. " icons.",
    })
    local showStackCheckbox = gui:CreateFormCheckbox(card.frame, nil, prefix .. "ShowStack", auraDB, refreshAuras, {
        description = "Show the stack count on stacked " .. kindLower .. " icons.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Spacing", spacingSlider),
        optionsAPI.BuildSettingRow(card.frame, "Stack Show", showStackCheckbox)
    )

    local stackSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 40, 1, prefix .. "StackSize", auraDB, refreshAuras, nil, {
        description = "Font size used for the stack count on " .. kindLower .. " icons.",
    })
    local stackAnchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, prefix .. "StackAnchor", auraDB, refreshAuras, {
        description = "Which corner of the " .. kindLower .. " icon the stack count is anchored to.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Stack Size", stackSizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Stack Anchor", stackAnchorDropdown)
    )

    local stackXOffsetSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, prefix .. "StackOffsetX", auraDB, refreshAuras, nil, {
        description = "Horizontal pixel offset for the stack count from its anchor.",
    })
    local stackYOffsetSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, prefix .. "StackOffsetY", auraDB, refreshAuras, nil, {
        description = "Vertical pixel offset for the stack count from its anchor.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Stack X Offset", stackXOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Stack Y Offset", stackYOffsetSlider)
    )

    local stackColorPicker = gui:CreateFormColorPicker(card.frame, nil, prefix .. "StackColor", auraDB, refreshAuras, nil, {
        description = "Color for the stack count text on " .. kindLower .. " icons.",
    })
    local showDurationCheckbox = gui:CreateFormCheckbox(card.frame, nil, prefix .. "ShowDuration", auraDB, refreshAuras, {
        description = "Show the remaining-duration countdown text on " .. kindLower .. " icons.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Stack Color", stackColorPicker),
        optionsAPI.BuildSettingRow(card.frame, "Duration Show", showDurationCheckbox)
    )

    local durationSizeSlider = gui:CreateFormSlider(card.frame, nil, 8, 40, 1, prefix .. "DurationSize", auraDB, refreshAuras, nil, {
        description = "Font size used for the duration countdown on " .. kindLower .. " icons.",
    })
    local durationAnchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, prefix .. "DurationAnchor", auraDB, refreshAuras, {
        description = "Which part of the " .. kindLower .. " icon the duration countdown is anchored to.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Duration Size", durationSizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Duration Anchor", durationAnchorDropdown)
    )

    local durationXOffsetSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, prefix .. "DurationOffsetX", auraDB, refreshAuras, nil, {
        description = "Horizontal pixel offset for the duration countdown from its anchor.",
    })
    local durationYOffsetSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, prefix .. "DurationOffsetY", auraDB, refreshAuras, nil, {
        description = "Vertical pixel offset for the duration countdown from its anchor.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Duration X Offset", durationXOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Duration Y Offset", durationYOffsetSlider)
    )

    local durationColorPicker = gui:CreateFormColorPicker(card.frame, nil, prefix .. "DurationColor", auraDB, refreshAuras, nil, {
        description = "Color for the duration countdown text on " .. kindLower .. " icons.",
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, "Duration Color", durationColorPicker))

    builder.CloseCard(card)
    return builder.Height()
end

local function RenderDebuffIconsSection(sectionHost, ctx)
    return RenderAuraIconsSection(sectionHost, ctx, "debuff", "Debuff")
end

local function RenderDebuffTextSection(sectionHost, ctx)
    return RenderAuraTextSection(sectionHost, ctx, "debuff", "Debuff")
end

local function RenderBuffIconsSection(sectionHost, ctx)
    return RenderAuraIconsSection(sectionHost, ctx, "buff", "Buff")
end

local function RenderBuffTextSection(sectionHost, ctx)
    return RenderAuraTextSection(sectionHost, ctx, "buff", "Buff")
end

local function BuildTextTabFeature(unitKey)
    if TEXT_TAB_FEATURES[unitKey] then
        return TEXT_TAB_FEATURES[unitKey]
    end

    local sections = { "name" }
    if unitKey == "target" then
        sections[#sections + 1] = "targetOfTarget"
    end
    sections[#sections + 1] = "health"
    sections[#sections + 1] = "power"
    if unitKey == "player" then
        sections[#sections + 1] = "stance"
    end

    local feature = Schema.Feature({
        id = "unitFramesTextTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = sections,
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = "name",
                kind = "custom",
                minHeight = 118,
                render = RenderTextNameSection,
            }),
            Schema.Section({
                id = "targetOfTarget",
                kind = "custom",
                minHeight = 92,
                render = RenderTextTargetOfTargetSection,
            }),
            Schema.Section({
                id = "health",
                kind = "custom",
                minHeight = 132,
                render = RenderTextHealthSection,
            }),
            Schema.Section({
                id = "power",
                kind = "custom",
                minHeight = 132,
                render = RenderTextPowerSection,
            }),
            Schema.Section({
                id = "stance",
                kind = "custom",
                minHeight = 128,
                render = RenderTextStanceSection,
            }),
        },
    })

    TEXT_TAB_FEATURES[unitKey] = feature
    return feature
end

local function BuildIconsTabFeature(unitKey)
    if ICONS_TAB_FEATURES[unitKey] then
        return ICONS_TAB_FEATURES[unitKey]
    end

    local sections = {
        "debuffIcons",
        "buffIcons",
    }
    if unitKey ~= "pet" then
        table.insert(sections, 2, "debuffText")
        sections[#sections + 1] = "buffText"
    end

    local feature = Schema.Feature({
        id = "unitFramesIconsTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = sections,
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = "debuffIcons",
                kind = "custom",
                minHeight = 162,
                render = RenderDebuffIconsSection,
            }),
            Schema.Section({
                id = "debuffText",
                kind = "custom",
                minHeight = 196,
                render = RenderDebuffTextSection,
            }),
            Schema.Section({
                id = "buffIcons",
                kind = "custom",
                minHeight = 162,
                render = RenderBuffIconsSection,
            }),
            Schema.Section({
                id = "buffText",
                kind = "custom",
                minHeight = 196,
                render = RenderBuffTextSection,
            }),
        },
    })

    ICONS_TAB_FEATURES[unitKey] = feature
    return feature
end

local function RenderPortraitUnavailableSection(sectionHost, ctx)
    local gui = GetGUI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    if UnitSupportsPortrait(unitKey) then
        return nil
    end

    SetSearchContext(CreateUnitSearchContext(unitKey, "Portrait"))

    local info = gui and gui.CreateLabel and gui:CreateLabel(
        sectionHost,
        "Portrait is only supported on the Player, Target, and Focus frames.",
        12,
        { 0.5, 0.5, 0.5, 1 }
    ) or nil
    if info then
        info:SetPoint("TOPLEFT", 10, -10)
    else
        local label = sectionHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 10, -10)
        label:SetText("Portrait is only supported on the Player, Target, and Focus frames.")
        label:SetTextColor(0.5, 0.5, 0.5, 1)
    end
    return 60
end

local function RenderPortraitSettingsSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or not UnitSupportsPortrait(unitKey) then
        return nil
    end

    EnsurePortraitSettings(unit.unitDB, unitKey)

    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Portrait"))
    if not builder then
        return nil
    end

    builder.Header("Portrait")
    local card = builder.Card()
    local borderColorCell

    local showCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showPortrait", unit.unitDB, RefreshUnitFrames, {
        description = "Show a 3D unit portrait next to this frame. Side, size, gap, and border style are set below.",
    })
    local sideDropdown = gui:CreateFormDropdown(card.frame, nil, PORTRAIT_SIDE_OPTIONS, "portraitSide", unit.unitDB, RefreshUnitFrames, {
        description = "Which side of the frame the portrait sits on.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Portrait", showCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Portrait Side", sideDropdown)
    )

    local sizeSlider = gui:CreateFormSlider(card.frame, nil, 20, 150, 1, "portraitSize", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Portrait width and height in pixels.",
    })
    local borderSlider = gui:CreateFormSlider(card.frame, nil, 0, 5, 1, "portraitBorderSize", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Border thickness in pixels around the portrait. Set to 0 to hide the border entirely.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Portrait Size (Pixels)", sizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Portrait Border", borderSlider)
    )

    local gapSlider = gui:CreateFormSlider(card.frame, nil, 0, 10, 1, "portraitGap", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Pixel gap between the portrait and the unit frame.",
    })
    local offsetXSlider = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "portraitOffsetX", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Extra horizontal pixel offset applied to the portrait on top of its Side and Gap placement.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Portrait Gap", gapSlider),
        optionsAPI.BuildSettingRow(card.frame, "Portrait Offset X", offsetXSlider)
    )

    local offsetYSlider = gui:CreateFormSlider(card.frame, nil, -500, 500, 1, "portraitOffsetY", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Extra vertical pixel offset applied to the portrait.",
    })
    local classColorCheckbox = gui:CreateFormCheckbox(card.frame, nil, "portraitBorderUseClassColor", unit.unitDB, function()
        RefreshUnitFrames()
        if borderColorCell then
            borderColorCell:SetAlpha(unit.unitDB.portraitBorderUseClassColor and 0.4 or 1.0)
        end
    end, {
        description = "Color the portrait border by the unit's class color instead of the Custom Border Color below.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Portrait Offset Y", offsetYSlider),
        optionsAPI.BuildSettingRow(card.frame, "Use Class Color for Border", classColorCheckbox)
    )

    local borderColorPicker = gui:CreateFormColorPicker(card.frame, nil, "portraitBorderColor", unit.unitDB, RefreshUnitFrames, nil, {
        description = "Fallback color for the portrait border when Use Class Color for Border is off.",
    })
    borderColorCell = optionsAPI.BuildSettingRow(card.frame, "Border Color", borderColorPicker)
    borderColorCell:SetAlpha(unit.unitDB.portraitBorderUseClassColor and 0.4 or 1.0)
    card.AddRow(borderColorCell)

    builder.CloseCard(card)
    return builder.Height()
end

local function BuildPortraitTabFeature(unitKey)
    if PORTRAIT_TAB_FEATURES[unitKey] then
        return PORTRAIT_TAB_FEATURES[unitKey]
    end

    local sections
    if UnitSupportsPortrait(unitKey) then
        sections = { "portrait" }
    else
        sections = { "unsupported" }
    end

    local feature = Schema.Feature({
        id = "unitFramesPortraitTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = sections,
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = "unsupported",
                kind = "custom",
                minHeight = 60,
                render = RenderPortraitUnavailableSection,
            }),
            Schema.Section({
                id = "portrait",
                kind = "custom",
                minHeight = 120,
                render = RenderPortraitSettingsSection,
            }),
        },
    })

    PORTRAIT_TAB_FEATURES[unitKey] = feature
    return feature
end

local function AddIndicatorCardRows(card, optionsAPI, gui, db, labels, xKey, yKey)
    local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", db, RefreshUnitFrames, {
        description = labels.descEnable,
    })
    local sizeSlider = gui:CreateFormSlider(card.frame, nil, labels.sizeMin or 8, labels.sizeMax or 48, 1, "size", db, RefreshUnitFrames, nil, {
        description = labels.descSize,
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, labels.enable, enableCheckbox),
        optionsAPI.BuildSettingRow(card.frame, labels.size, sizeSlider)
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "anchor", db, RefreshUnitFrames, {
        description = labels.descAnchor,
    })
    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, xKey, db, RefreshUnitFrames, nil, {
        description = labels.descX,
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, labels.anchor, anchorDropdown),
        optionsAPI.BuildSettingRow(card.frame, labels.x, xOffsetSlider)
    )

    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, yKey, db, RefreshUnitFrames, nil, {
        description = labels.descY,
    })
    card.AddRow(optionsAPI.BuildSettingRow(card.frame, labels.y, yOffsetSlider))
end

local function RenderIndicatorsRestedSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or unitKey ~= "player" then
        return nil
    end

    local rested = EnsureRestedIndicatorSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Indicators"))
    if not builder then
        return nil
    end

    builder.Header("Rested Indicator")
    builder.Description("Shows when in a rested area (disabled by default).")
    local card = builder.Card()
    AddIndicatorCardRows(card, optionsAPI, gui, rested, {
        enable = "Enable Rested Indicator",
        size = "Rested Icon Size",
        anchor = "Rested Anchor",
        x = "Rested X Offset",
        y = "Rested Y Offset",
        sizeMin = 8,
        sizeMax = 32,
        descEnable = "Show the rested icon on the player frame while you're in a rested area.",
        descSize = "Pixel size of the rested icon.",
        descAnchor = "Where on the player frame the rested icon is anchored.",
        descX = "Horizontal pixel offset for the rested icon from its anchor.",
        descY = "Vertical pixel offset for the rested icon from its anchor.",
    }, "offsetX", "offsetY")
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderIndicatorsCombatSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or unitKey ~= "player" then
        return nil
    end

    local combat = EnsureCombatIndicatorSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Indicators"))
    if not builder then
        return nil
    end

    builder.Header("Combat Indicator")
    builder.Description("Shows during combat (disabled by default).")
    local card = builder.Card()
    AddIndicatorCardRows(card, optionsAPI, gui, combat, {
        enable = "Enable Combat Indicator",
        size = "Combat Icon Size",
        anchor = "Combat Anchor",
        x = "Combat X Offset",
        y = "Combat Y Offset",
        sizeMin = 8,
        sizeMax = 32,
        descEnable = "Show the combat icon on the player frame while you're in combat.",
        descSize = "Pixel size of the combat icon.",
        descAnchor = "Where on the player frame the combat icon is anchored.",
        descX = "Horizontal pixel offset for the combat icon from its anchor.",
        descY = "Vertical pixel offset for the combat icon from its anchor.",
    }, "offsetX", "offsetY")
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderIndicatorsTargetMarkerSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit then
        return nil
    end

    local marker = EnsureTargetMarkerSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Indicators"))
    if not builder then
        return nil
    end

    builder.Header("Target Marker")
    builder.Description("Shows raid target markers (skull, cross, diamond, etc.) on the unit frame.")
    local card = builder.Card()
    AddIndicatorCardRows(card, optionsAPI, gui, marker, {
        enable = "Show Target Marker",
        size = "Marker Size",
        anchor = "Anchor To",
        x = "X Offset",
        y = "Y Offset",
        sizeMin = 8,
        sizeMax = 48,
        descEnable = "Show the unit's raid target icon on this frame when one is assigned.",
        descSize = "Pixel size of the raid target icon.",
        descAnchor = "Where on the frame the raid target icon is anchored.",
        descX = "Horizontal pixel offset for the raid target icon from its anchor.",
        descY = "Vertical pixel offset for the raid target icon from its anchor.",
    }, "xOffset", "yOffset")
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderIndicatorsLeaderSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or not UnitSupportsLeaderIndicator(unitKey) then
        return nil
    end

    local leader = EnsureLeaderIndicatorSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Indicators"))
    if not builder then
        return nil
    end

    builder.Header("Leader/Assistant Icon")
    builder.Description("Shows crown icon for party/raid leader, flag icon for raid assistants.")
    local card = builder.Card()
    AddIndicatorCardRows(card, optionsAPI, gui, leader, {
        enable = "Show Leader/Assistant Icon",
        size = "Icon Size",
        anchor = "Anchor To",
        x = "X Offset",
        y = "Y Offset",
        sizeMin = 8,
        sizeMax = 32,
        descEnable = "Show a crown icon on the party/raid leader and a flag icon on raid assistants.",
        descSize = "Pixel size of the leader/assistant icon.",
        descAnchor = "Where on the frame the leader/assistant icon is anchored.",
        descX = "Horizontal pixel offset for the leader/assistant icon from its anchor.",
        descY = "Vertical pixel offset for the leader/assistant icon from its anchor.",
    }, "xOffset", "yOffset")
    builder.CloseCard(card)
    return builder.Height()
end

local function RenderIndicatorsClassificationSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or not UnitSupportsClassificationIndicator(unitKey) then
        return nil
    end

    local classification = EnsureClassificationIndicatorSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Indicators"))
    if not builder then
        return nil
    end

    builder.Header("Classification Icon")
    builder.Description("Shows an icon indicating if the unit is Elite, Rare, Rare Elite, or a Boss.")
    local card = builder.Card()
    AddIndicatorCardRows(card, optionsAPI, gui, classification, {
        enable = "Show Classification Icon",
        size = "Icon Size",
        anchor = "Anchor To",
        x = "X Offset",
        y = "Y Offset",
        sizeMin = 8,
        sizeMax = 48,
        descEnable = "Show a classification icon next to elite, rare, rare-elite, and boss NPCs on this unit frame.",
        descSize = "Pixel size of the classification icon.",
        descAnchor = "Where on the frame the classification icon is anchored.",
        descX = "Horizontal pixel offset for the classification icon from its anchor.",
        descY = "Vertical pixel offset for the classification icon from its anchor.",
    }, "xOffset", "yOffset")
    builder.CloseCard(card)
    return builder.Height()
end

local function BuildIndicatorsTabFeature(unitKey)
    if INDICATORS_TAB_FEATURES[unitKey] then
        return INDICATORS_TAB_FEATURES[unitKey]
    end

    local sections = {}
    if unitKey == "player" then
        sections[#sections + 1] = "rested"
        sections[#sections + 1] = "combat"
    end
    sections[#sections + 1] = "targetMarker"
    if UnitSupportsLeaderIndicator(unitKey) then
        sections[#sections + 1] = "leader"
    end
    if UnitSupportsClassificationIndicator(unitKey) then
        sections[#sections + 1] = "classification"
    end

    local feature = Schema.Feature({
        id = "unitFramesIndicatorsTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = sections,
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = "rested",
                kind = "custom",
                minHeight = 96,
                render = RenderIndicatorsRestedSection,
            }),
            Schema.Section({
                id = "combat",
                kind = "custom",
                minHeight = 96,
                render = RenderIndicatorsCombatSection,
            }),
            Schema.Section({
                id = "targetMarker",
                kind = "custom",
                minHeight = 96,
                render = RenderIndicatorsTargetMarkerSection,
            }),
            Schema.Section({
                id = "leader",
                kind = "custom",
                minHeight = 96,
                render = RenderIndicatorsLeaderSection,
            }),
            Schema.Section({
                id = "classification",
                kind = "custom",
                minHeight = 96,
                render = RenderIndicatorsClassificationSection,
            }),
        },
    })

    INDICATORS_TAB_FEATURES[unitKey] = feature
    return feature
end

local function RenderPrivateAurasUnavailableSection(sectionHost, ctx)
    local gui = GetGUI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    if UnitSupportsPrivateAuras(unitKey) then
        return nil
    end

    SetSearchContext(CreateUnitSearchContext(unitKey, "Priv. Auras"))

    local info = gui and gui.CreateLabel and gui:CreateLabel(
        sectionHost,
        "Private Auras are only supported on the Player, Target, and Focus frames.",
        12,
        { 0.5, 0.5, 0.5, 1 }
    ) or nil
    if info then
        info:SetPoint("TOPLEFT", 10, -10)
    else
        local label = sectionHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 10, -10)
        label:SetText("Private Auras are only supported on the Player, Target, and Focus frames.")
        label:SetTextColor(0.5, 0.5, 0.5, 1)
    end
    return 60
end

local function RenderPrivateAurasSection(sectionHost, ctx)
    local gui = GetGUI()
    local optionsAPI = GetOptionsAPI()
    local unitKey = ctx and ctx.options and ctx.options.unitKey or nil
    local unit = ResolveUnitDB(unitKey)
    if not gui or not optionsAPI or not unit or not UnitSupportsPrivateAuras(unitKey) then
        return nil
    end

    local privateAuras = EnsurePrivateAurasSettings(unit.unitDB)
    local builder = CreateSectionBuilder(sectionHost, ctx, CreateUnitSearchContext(unitKey, "Priv. Auras"))
    if not builder then
        return nil
    end

    builder.Header("Private Auras")
    builder.Description("Shows boss debuffs and other private auras on this unit frame. The client renders the icon, cooldown spiral, and stack/duration text.")
    local card = builder.Card()

    local enableCheckbox = gui:CreateFormCheckbox(card.frame, nil, "enabled", privateAuras, RefreshUnitFrames, {
        description = "Enable private auras on this unit frame.",
    })
    local maxSlider = gui:CreateFormSlider(card.frame, nil, 1, 5, 1, "maxPerFrame", privateAuras, RefreshUnitFrames, nil, {
        description = "Maximum number of private-aura icons the client will draw on this frame at once.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Enable Private Auras", enableCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Max Per Frame", maxSlider)
    )

    local sizeSlider = gui:CreateFormSlider(card.frame, nil, 10, 40, 1, "iconSize", privateAuras, RefreshUnitFrames, nil, {
        description = "Pixel size of each private-aura icon.",
    })
    local spacingSlider = gui:CreateFormSlider(card.frame, nil, 0, 8, 1, "spacing", privateAuras, RefreshUnitFrames, nil, {
        description = "Pixel gap between adjacent private-aura icons.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Icon Size", sizeSlider),
        optionsAPI.BuildSettingRow(card.frame, "Spacing", spacingSlider)
    )

    local anchorDropdown = gui:CreateFormDropdown(card.frame, nil, optionsAPI.NINE_POINT_ANCHOR_OPTIONS, "anchor", privateAuras, RefreshUnitFrames, {
        description = "Where on the frame the first private-aura icon is anchored.",
    })
    local growDropdown = gui:CreateFormDropdown(card.frame, nil, PRIVATE_AURA_GROW_OPTIONS, "growDirection", privateAuras, RefreshUnitFrames, {
        description = "Direction additional private-aura icons are added in after the first.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Anchor", anchorDropdown),
        optionsAPI.BuildSettingRow(card.frame, "Grow Direction", growDropdown)
    )

    local xOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "anchorOffsetX", privateAuras, RefreshUnitFrames, nil, {
        description = "Horizontal pixel offset for the private-aura block from its anchor.",
    })
    local yOffsetSlider = gui:CreateFormSlider(card.frame, nil, -100, 100, 1, "anchorOffsetY", privateAuras, RefreshUnitFrames, nil, {
        description = "Vertical pixel offset for the private-aura block from its anchor.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "X Offset", xOffsetSlider),
        optionsAPI.BuildSettingRow(card.frame, "Y Offset", yOffsetSlider)
    )

    local countdownCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showCountdown", privateAuras, RefreshUnitFrames, {
        description = "Show the clockwise cooldown swipe over each private-aura icon.",
    })
    local numbersCheckbox = gui:CreateFormCheckbox(card.frame, nil, "showCountdownNumbers", privateAuras, RefreshUnitFrames, {
        description = "Show the Blizzard-rendered countdown number on each private-aura icon.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Show Countdown Spiral", countdownCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Show Countdown Numbers", numbersCheckbox)
    )

    local reverseCheckbox = gui:CreateFormCheckbox(card.frame, nil, "reverseSwipe", privateAuras, RefreshUnitFrames, {
        description = "Reverse the swipe direction so it fills clockwise as time elapses instead of sweeping away.",
    })
    local borderSlider = gui:CreateFormSlider(card.frame, nil, -100, 10, 0.5, "borderScale", privateAuras, RefreshUnitFrames, nil, {
        description = "Scale applied to the private-aura icon border. Set to -100 to hide the border entirely.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Reverse Swipe", reverseCheckbox),
        optionsAPI.BuildSettingRow(card.frame, "Border Scale", borderSlider)
    )

    local textScaleSlider = gui:CreateFormSlider(card.frame, nil, 0.5, 5, 0.5, "textScale", privateAuras, RefreshUnitFrames, nil, {
        description = "Scale factor applied to the stack count and countdown number on each private-aura icon.",
    })
    local frameLevelSlider = gui:CreateFormSlider(card.frame, nil, 0, 100, 1, "frameLevel", privateAuras, RefreshUnitFrames, nil, {
        description = "Frame-level offset added to the private-aura container so icons render above or below other elements on this frame.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Stack/Number Scale", textScaleSlider),
        optionsAPI.BuildSettingRow(card.frame, "Frame Level Offset", frameLevelSlider)
    )

    local textOffsetXSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "textOffsetX", privateAuras, RefreshUnitFrames, nil, {
        description = "Horizontal offset for the stack count / countdown number within each private-aura icon.",
    })
    local textOffsetYSlider = gui:CreateFormSlider(card.frame, nil, -20, 20, 1, "textOffsetY", privateAuras, RefreshUnitFrames, nil, {
        description = "Vertical offset for the stack count / countdown number within each private-aura icon.",
    })
    card.AddRow(
        optionsAPI.BuildSettingRow(card.frame, "Stack/Number X Offset", textOffsetXSlider),
        optionsAPI.BuildSettingRow(card.frame, "Stack/Number Y Offset", textOffsetYSlider)
    )

    builder.CloseCard(card)
    return builder.Height()
end

local function BuildPrivateAurasTabFeature(unitKey)
    if PRIVATE_AURAS_TAB_FEATURES[unitKey] then
        return PRIVATE_AURAS_TAB_FEATURES[unitKey]
    end

    local sections
    if UnitSupportsPrivateAuras(unitKey) then
        sections = { "privateAuras" }
    else
        sections = { "unsupported" }
    end

    local feature = Schema.Feature({
        id = "unitFramesPrivateAurasTab:" .. unitKey,
        surfaces = {
            unitFrameTab = {
                sections = sections,
                padding = 10,
                sectionGap = 14,
                topPadding = 10,
                bottomPadding = 40,
            },
        },
        sections = {
            Schema.Section({
                id = "unsupported",
                kind = "custom",
                minHeight = 60,
                render = RenderPrivateAurasUnavailableSection,
            }),
            Schema.Section({
                id = "privateAuras",
                kind = "custom",
                minHeight = 180,
                render = RenderPrivateAurasSection,
            }),
        },
    })

    PRIVATE_AURAS_TAB_FEATURES[unitKey] = feature
    return feature
end

local GENERAL_TAB_FEATURE = Schema.Feature({
    id = "unitFramesGeneralTab",
    createState = function()
        return {
            generalTab = {
                defaultCells = {},
                darkCells = {},
            },
        }
    end,
    surfaces = {
        unitFrameTab = {
            sections = {
                "enable",
                "defaultColors",
                "darkMode",
                "textColorOverrides",
                "tooltips",
                "smootherUpdates",
                "hostilityColors",
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
            render = RenderEnableSection,
        }),
        Schema.Section({
            id = "defaultColors",
            kind = "custom",
            minHeight = 120,
            render = RenderDefaultColorsSection,
        }),
        Schema.Section({
            id = "darkMode",
            kind = "custom",
            minHeight = 120,
            render = RenderDarkModeSection,
        }),
        Schema.Section({
            id = "textColorOverrides",
            kind = "custom",
            minHeight = 96,
            render = RenderTextColorOverridesSection,
        }),
        Schema.Section({
            id = "tooltips",
            kind = "custom",
            minHeight = 58,
            render = RenderTooltipsSection,
        }),
        Schema.Section({
            id = "smootherUpdates",
            kind = "custom",
            minHeight = 72,
            render = RenderSmootherUpdatesSection,
        }),
        Schema.Section({
            id = "hostilityColors",
            kind = "custom",
            minHeight = 86,
            render = RenderHostilityColorsSection,
        }),
    },
})

function UnitFramesSchema.GetGeneralTabFeature()
    return GENERAL_TAB_FEATURE
end

function UnitFramesSchema.RenderGeneralTab(host)
    if not host then
        return false
    end

    local db = ResolveGeneralDB()
    if not db then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(GENERAL_TAB_FEATURE, host, {
        surface = "unitFrameTab",
        width = width,
    }) ~= nil
end

function UnitFramesSchema.RenderFrameTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildFrameTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end

function UnitFramesSchema.RenderBarsTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildBarsTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end

function UnitFramesSchema.RenderCastbarTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildCastbarTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end

function UnitFramesSchema.RenderTextTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildTextTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end

function UnitFramesSchema.RenderIconsTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildIconsTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end

function UnitFramesSchema.RenderPortraitTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildPortraitTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end

function UnitFramesSchema.RenderIndicatorsTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildIndicatorsTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end

function UnitFramesSchema.RenderPrivateAurasTab(host, unitKey)
    if not host then
        return false
    end

    local unit = ResolveUnitDB(unitKey)
    if not unit then
        return false
    end

    local width = host.GetWidth and host:GetWidth() or 0
    if type(width) ~= "number" or width <= 0 then
        width = 760
    end

    return Renderer:RenderFeature(BuildPrivateAurasTabFeature(unitKey), host, {
        surface = "unitFrameTab",
        width = width,
        unitKey = unitKey,
    }) ~= nil
end
