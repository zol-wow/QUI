---------------------------------------------------------------------------
-- QUI Party Frames Options
-- Settings page for Cell-style party frames
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local QUICore = ns.Addon

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList
local NINE_POINT_ANCHOR_OPTIONS = Shared.NINE_POINT_ANCHOR_OPTIONS

-- Grow direction options
local GROW_DIRECTION_OPTIONS = {
    {value = "DOWN", text = "Down"},
    {value = "UP", text = "Up"},
    {value = "RIGHT", text = "Right"},
    {value = "LEFT", text = "Left"},
}

-- Health display style options
local HEALTH_DISPLAY_OPTIONS = {
    {value = "percent", text = "Percent"},
    {value = "absolute", text = "Absolute"},
    {value = "both", text = "Both"},
}

-- Grow direction options for debuffs
local DEBUFF_GROW_OPTIONS = {
    {value = "RIGHT", text = "Right"},
    {value = "LEFT", text = "Left"},
    {value = "DOWN", text = "Down"},
    {value = "UP", text = "Up"},
}

---------------------------------------------------------------------------
-- Refresh callbacks
---------------------------------------------------------------------------
local function RefreshPartyFrames()
    if _G.QUI_RefreshPartyFrames then
        _G.QUI_RefreshPartyFrames()
    end
end

-- Rebuild is needed for structural changes (showPlayer, showPowerBar)
local function RebuildPartyFrames()
    if _G.QUI_RebuildPartyFrames then
        _G.QUI_RebuildPartyFrames()
    end
end

---------------------------------------------------------------------------
-- BUILD: Party Frames tab content
---------------------------------------------------------------------------
local function BuildPartyFramesTab(tabContent)
    local y = -10
    local FORM_ROW = 32

    local db = GetDB()
    local function GetPartyDB()
        return db and db.quiUnitFrames and db.quiUnitFrames.party
    end

    local partyDB = GetPartyDB()
    if not partyDB then
        local info = GUI:CreateLabel(tabContent, "Party Frames settings not available. Please reload UI.", 12, C.textMuted)
        info:SetPoint("TOPLEFT", PADDING, y)
        tabContent:SetHeight(60)
        return
    end

    GUI:SetSearchContext({tabIndex = 3, tabName = "Unit Frames", subTabIndex = 8, subTabName = "Party"})

    -- Auto-show preview when opening this tab (so user can see changes live)
    if partyDB.enabled and _G.QUI_ShowPartyFramePreview then
        _G.QUI_ShowPartyFramePreview()
    end

    -- Hide preview when tab content is hidden
    tabContent:SetScript("OnHide", function()
        if _G.QUI_HidePartyFramePreview then
            _G.QUI_HidePartyFramePreview()
        end
    end)

    ---------------------------------------------------------------------------
    -- Section: Enable & Preview
    ---------------------------------------------------------------------------
    local enableHeader = GUI:CreateSectionHeader(tabContent, "Party Frames")
    enableHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - enableHeader.gap

    local enableDesc = GUI:CreateLabel(tabContent, "Cell-style compact party frames. Enable to replace Blizzard party frames.", 11, C.textMuted)
    enableDesc:SetPoint("TOPLEFT", PADDING, y)
    enableDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    enableDesc:SetJustifyH("LEFT")
    enableDesc:SetWordWrap(true)
    enableDesc:SetHeight(20)
    y = y - 28

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Party Frames", "enabled", partyDB, RebuildPartyFrames)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Layout
    ---------------------------------------------------------------------------
    local layoutHeader = GUI:CreateSectionHeader(tabContent, "Layout")
    layoutHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - layoutHeader.gap

    local growDropdown = GUI:CreateFormDropdown(tabContent, "Grow Direction", GROW_DIRECTION_OPTIONS, "growDirection", partyDB, RefreshPartyFrames)
    growDropdown:SetPoint("TOPLEFT", PADDING, y)
    growDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local spacingSlider = GUI:CreateFormSlider(tabContent, "Spacing", 0, 20, 1, "spacing", partyDB, RefreshPartyFrames)
    spacingSlider:SetPoint("TOPLEFT", PADDING, y)
    spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local showPlayerCheck = GUI:CreateFormCheckbox(tabContent, "Show Player in Party", "showPlayer", partyDB, RebuildPartyFrames)
    showPlayerCheck:SetPoint("TOPLEFT", PADDING, y)
    showPlayerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Cell Size
    ---------------------------------------------------------------------------
    local sizeHeader = GUI:CreateSectionHeader(tabContent, "Cell Size")
    sizeHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - sizeHeader.gap

    local widthSlider = GUI:CreateFormSlider(tabContent, "Width", 40, 400, 1, "width", partyDB, RefreshPartyFrames)
    widthSlider:SetPoint("TOPLEFT", PADDING, y)
    widthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local heightSlider = GUI:CreateFormSlider(tabContent, "Height", 20, 100, 1, "height", partyDB, RefreshPartyFrames)
    heightSlider:SetPoint("TOPLEFT", PADDING, y)
    heightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 5, 1, "borderSize", partyDB, RefreshPartyFrames)
    borderSlider:SetPoint("TOPLEFT", PADDING, y)
    borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Health Bar
    ---------------------------------------------------------------------------
    local healthBarHeader = GUI:CreateSectionHeader(tabContent, "Health Bar")
    healthBarHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - healthBarHeader.gap

    local textureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", partyDB, RefreshPartyFrames)
    textureDropdown:SetPoint("TOPLEFT", PADDING, y)
    textureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", partyDB, RefreshPartyFrames)
    classColorCheck:SetPoint("TOPLEFT", PADDING, y)
    classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local customHealthColor = GUI:CreateFormColorPicker(tabContent, "Custom Health Color", "customHealthColor", partyDB, RefreshPartyFrames, {noAlpha = true})
    customHealthColor:SetPoint("TOPLEFT", PADDING, y)
    customHealthColor:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local bgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", partyDB, RefreshPartyFrames)
    bgColorPicker:SetPoint("TOPLEFT", PADDING, y)
    bgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Name Text
    ---------------------------------------------------------------------------
    local nameHeader = GUI:CreateSectionHeader(tabContent, "Name Text")
    nameHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - nameHeader.gap

    local showNameCheck = GUI:CreateFormCheckbox(tabContent, "Show Name", "showName", partyDB, RefreshPartyFrames)
    showNameCheck:SetPoint("TOPLEFT", PADDING, y)
    showNameCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local nameFontSlider = GUI:CreateFormSlider(tabContent, "Name Font Size", 6, 24, 1, "nameFontSize", partyDB, RefreshPartyFrames)
    nameFontSlider:SetPoint("TOPLEFT", PADDING, y)
    nameFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local nameAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Name Anchor", NINE_POINT_ANCHOR_OPTIONS, "nameAnchor", partyDB, RefreshPartyFrames)
    nameAnchorDropdown:SetPoint("TOPLEFT", PADDING, y)
    nameAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local maxNameSlider = GUI:CreateFormSlider(tabContent, "Max Name Length", 0, 20, 1, "maxNameLength", partyDB, RefreshPartyFrames)
    maxNameSlider:SetPoint("TOPLEFT", PADDING, y)
    maxNameSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local nameClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Name Class Color", "nameUseClassColor", partyDB, RefreshPartyFrames)
    nameClassColorCheck:SetPoint("TOPLEFT", PADDING, y)
    nameClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local nameColorPicker = GUI:CreateFormColorPicker(tabContent, "Name Color", "nameColor", partyDB, RefreshPartyFrames, {noAlpha = true})
    nameColorPicker:SetPoint("TOPLEFT", PADDING, y)
    nameColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Health Text
    ---------------------------------------------------------------------------
    local healthTextHeader = GUI:CreateSectionHeader(tabContent, "Health Text")
    healthTextHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - healthTextHeader.gap

    local showHealthCheck = GUI:CreateFormCheckbox(tabContent, "Show Health Text", "showHealth", partyDB, RefreshPartyFrames)
    showHealthCheck:SetPoint("TOPLEFT", PADDING, y)
    showHealthCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local healthStyleDropdown = GUI:CreateFormDropdown(tabContent, "Display Style", HEALTH_DISPLAY_OPTIONS, "healthDisplayStyle", partyDB, RefreshPartyFrames)
    healthStyleDropdown:SetPoint("TOPLEFT", PADDING, y)
    healthStyleDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local healthFontSlider = GUI:CreateFormSlider(tabContent, "Health Font Size", 6, 24, 1, "healthFontSize", partyDB, RefreshPartyFrames)
    healthFontSlider:SetPoint("TOPLEFT", PADDING, y)
    healthFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local healthAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Health Anchor", NINE_POINT_ANCHOR_OPTIONS, "healthAnchor", partyDB, RefreshPartyFrames)
    healthAnchorDropdown:SetPoint("TOPLEFT", PADDING, y)
    healthAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Power Bar
    ---------------------------------------------------------------------------
    local powerHeader = GUI:CreateSectionHeader(tabContent, "Power Bar")
    powerHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - powerHeader.gap

    local showPowerCheck = GUI:CreateFormCheckbox(tabContent, "Show Power Bar", "showPowerBar", partyDB, RebuildPartyFrames)
    showPowerCheck:SetPoint("TOPLEFT", PADDING, y)
    showPowerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local powerHeightSlider = GUI:CreateFormSlider(tabContent, "Power Bar Height", 1, 10, 1, "powerBarHeight", partyDB, RefreshPartyFrames)
    powerHeightSlider:SetPoint("TOPLEFT", PADDING, y)
    powerHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local powerColorTypeCheck = GUI:CreateFormCheckbox(tabContent, "Use Power Type Color", "powerBarUsePowerColor", partyDB, RefreshPartyFrames)
    powerColorTypeCheck:SetPoint("TOPLEFT", PADDING, y)
    powerColorTypeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local powerColorPicker = GUI:CreateFormColorPicker(tabContent, "Custom Power Color", "powerBarColor", partyDB, RefreshPartyFrames)
    powerColorPicker:SetPoint("TOPLEFT", PADDING, y)
    powerColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Role & Status Icons
    ---------------------------------------------------------------------------
    local iconsHeader = GUI:CreateSectionHeader(tabContent, "Icons & Indicators")
    iconsHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - iconsHeader.gap

    local showRoleCheck = GUI:CreateFormCheckbox(tabContent, "Show Role Icon", "showRoleIcon", partyDB, RefreshPartyFrames)
    showRoleCheck:SetPoint("TOPLEFT", PADDING, y)
    showRoleCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local roleIconSizeSlider = GUI:CreateFormSlider(tabContent, "Role Icon Size", 6, 24, 1, "roleIconSize", partyDB, RefreshPartyFrames)
    roleIconSizeSlider:SetPoint("TOPLEFT", PADDING, y)
    roleIconSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local roleAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Role Icon Anchor", NINE_POINT_ANCHOR_OPTIONS, "roleIconAnchor", partyDB, RefreshPartyFrames)
    roleAnchorDropdown:SetPoint("TOPLEFT", PADDING, y)
    roleAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- Leader icon
    local leaderDB = partyDB.leaderIcon
    if leaderDB then
        local showLeaderCheck = GUI:CreateFormCheckbox(tabContent, "Show Leader Icon", "enabled", leaderDB, RefreshPartyFrames)
        showLeaderCheck:SetPoint("TOPLEFT", PADDING, y)
        showLeaderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local leaderSizeSlider = GUI:CreateFormSlider(tabContent, "Leader Icon Size", 6, 24, 1, "size", leaderDB, RefreshPartyFrames)
        leaderSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        leaderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    -- Target marker
    local tmDB = partyDB.targetMarker
    if tmDB then
        local showTMCheck = GUI:CreateFormCheckbox(tabContent, "Show Target Marker", "enabled", tmDB, RefreshPartyFrames)
        showTMCheck:SetPoint("TOPLEFT", PADDING, y)
        showTMCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local tmSizeSlider = GUI:CreateFormSlider(tabContent, "Marker Size", 6, 32, 1, "size", tmDB, RefreshPartyFrames)
        tmSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        tmSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    ---------------------------------------------------------------------------
    -- Section: Absorbs & Heal Prediction
    ---------------------------------------------------------------------------
    local absorbHeader = GUI:CreateSectionHeader(tabContent, "Absorbs & Heal Prediction")
    absorbHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - absorbHeader.gap

    local absorbDB = partyDB.absorbs
    if absorbDB then
        local showAbsorbCheck = GUI:CreateFormCheckbox(tabContent, "Show Absorb Shields", "enabled", absorbDB, RefreshPartyFrames)
        showAbsorbCheck:SetPoint("TOPLEFT", PADDING, y)
        showAbsorbCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local absorbColorPicker = GUI:CreateFormColorPicker(tabContent, "Absorb Color", "color", absorbDB, RefreshPartyFrames, {noAlpha = true})
        absorbColorPicker:SetPoint("TOPLEFT", PADDING, y)
        absorbColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local absorbOpacitySlider = GUI:CreateFormSlider(tabContent, "Absorb Opacity", 0.1, 1.0, 0.05, "opacity", absorbDB, RefreshPartyFrames)
        absorbOpacitySlider:SetPoint("TOPLEFT", PADDING, y)
        absorbOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    local healDB = partyDB.healPrediction
    if healDB then
        local showHealCheck = GUI:CreateFormCheckbox(tabContent, "Show Heal Prediction", "enabled", healDB, RefreshPartyFrames)
        showHealCheck:SetPoint("TOPLEFT", PADDING, y)
        showHealCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local healColorPicker = GUI:CreateFormColorPicker(tabContent, "Heal Prediction Color", "color", healDB, RefreshPartyFrames, {noAlpha = true})
        healColorPicker:SetPoint("TOPLEFT", PADDING, y)
        healColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local healOpacitySlider = GUI:CreateFormSlider(tabContent, "Heal Opacity", 0.1, 1.0, 0.05, "opacity", healDB, RefreshPartyFrames)
        healOpacitySlider:SetPoint("TOPLEFT", PADDING, y)
        healOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    ---------------------------------------------------------------------------
    -- Section: Auras (Debuffs)
    ---------------------------------------------------------------------------
    local auraHeader = GUI:CreateSectionHeader(tabContent, "Auras")
    auraHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - auraHeader.gap

    local auraDB = partyDB.auras
    if auraDB then
        local showDebuffsCheck = GUI:CreateFormCheckbox(tabContent, "Show Debuffs", "showDebuffs", auraDB, RefreshPartyFrames)
        showDebuffsCheck:SetPoint("TOPLEFT", PADDING, y)
        showDebuffsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local debuffSizeSlider = GUI:CreateFormSlider(tabContent, "Debuff Icon Size", 8, 32, 1, "iconSize", auraDB, RefreshPartyFrames)
        debuffSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        debuffSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local debuffMaxSlider = GUI:CreateFormSlider(tabContent, "Max Debuff Icons", 1, 8, 1, "debuffMaxIcons", auraDB, RefreshPartyFrames)
        debuffMaxSlider:SetPoint("TOPLEFT", PADDING, y)
        debuffMaxSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local debuffAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Debuff Anchor", NINE_POINT_ANCHOR_OPTIONS, "debuffAnchor", auraDB, RefreshPartyFrames)
        debuffAnchorDropdown:SetPoint("TOPLEFT", PADDING, y)
        debuffAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local debuffGrowDropdown = GUI:CreateFormDropdown(tabContent, "Debuff Grow Direction", DEBUFF_GROW_OPTIONS, "debuffGrow", auraDB, RefreshPartyFrames)
        debuffGrowDropdown:SetPoint("TOPLEFT", PADDING, y)
        debuffGrowDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local debuffSpacingSlider = GUI:CreateFormSlider(tabContent, "Debuff Spacing", 0, 10, 1, "debuffSpacing", auraDB, RefreshPartyFrames)
        debuffSpacingSlider:SetPoint("TOPLEFT", PADDING, y)
        debuffSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local showStacksCheck = GUI:CreateFormCheckbox(tabContent, "Show Stack Count", "debuffShowStack", auraDB, RefreshPartyFrames)
        showStacksCheck:SetPoint("TOPLEFT", PADDING, y)
        showStacksCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    ---------------------------------------------------------------------------
    -- Section: Dispel Highlight
    ---------------------------------------------------------------------------
    local dispelHeader = GUI:CreateSectionHeader(tabContent, "Dispel Highlight")
    dispelHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - dispelHeader.gap

    local dispelDB = partyDB.dispelHighlight
    if dispelDB then
        local showDispelCheck = GUI:CreateFormCheckbox(tabContent, "Enable Dispel Highlight", "enabled", dispelDB, RefreshPartyFrames)
        showDispelCheck:SetPoint("TOPLEFT", PADDING, y)
        showDispelCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local dispelBorderSlider = GUI:CreateFormSlider(tabContent, "Highlight Border Size", 1, 5, 1, "borderSize", dispelDB, RefreshPartyFrames)
        dispelBorderSlider:SetPoint("TOPLEFT", PADDING, y)
        dispelBorderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    ---------------------------------------------------------------------------
    -- Section: Range Check
    ---------------------------------------------------------------------------
    local rangeHeader = GUI:CreateSectionHeader(tabContent, "Range Check")
    rangeHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - rangeHeader.gap

    local rangeDB = partyDB.rangeCheck
    if rangeDB then
        local rangeCheck = GUI:CreateFormCheckbox(tabContent, "Enable Range Check", "enabled", rangeDB, RefreshPartyFrames)
        rangeCheck:SetPoint("TOPLEFT", PADDING, y)
        rangeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local rangeAlphaSlider = GUI:CreateFormSlider(tabContent, "Out of Range Alpha", 0.1, 1.0, 0.05, "outOfRangeAlpha", rangeDB, RefreshPartyFrames)
        rangeAlphaSlider:SetPoint("TOPLEFT", PADDING, y)
        rangeAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    ---------------------------------------------------------------------------
    -- Section: Position
    ---------------------------------------------------------------------------
    local posHeader = GUI:CreateSectionHeader(tabContent, "Position")
    posHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - posHeader.gap

    local posDesc = GUI:CreateLabel(tabContent, "Adjust the anchor position of the first party frame cell.", 11, C.textMuted)
    posDesc:SetPoint("TOPLEFT", PADDING, y)
    posDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    posDesc:SetJustifyH("LEFT")
    y = y - 24

    local xSlider = GUI:CreateFormSlider(tabContent, "X Offset", -1500, 1500, 1, "offsetX", partyDB, RefreshPartyFrames)
    xSlider:SetPoint("TOPLEFT", PADDING, y)
    xSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -1000, 1000, 1, "offsetY", partyDB, RefreshPartyFrames)
    ySlider:SetPoint("TOPLEFT", PADDING, y)
    ySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    ---------------------------------------------------------------------------
    -- Section: Status Indicators
    ---------------------------------------------------------------------------
    local statusHeader = GUI:CreateSectionHeader(tabContent, "Status Indicators")
    statusHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - statusHeader.gap

    local statusDB = partyDB.statusIcons
    if statusDB then
        local showDeadCheck = GUI:CreateFormCheckbox(tabContent, "Show Dead Text", "showDead", statusDB, RefreshPartyFrames)
        showDeadCheck:SetPoint("TOPLEFT", PADDING, y)
        showDeadCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local showOfflineCheck = GUI:CreateFormCheckbox(tabContent, "Show Offline Text", "showOffline", statusDB, RefreshPartyFrames)
        showOfflineCheck:SetPoint("TOPLEFT", PADDING, y)
        showOfflineCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local showResCheck = GUI:CreateFormCheckbox(tabContent, "Show Resurrect Status", "showResurrect", statusDB, RefreshPartyFrames)
        showResCheck:SetPoint("TOPLEFT", PADDING, y)
        showResCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local showSummonCheck = GUI:CreateFormCheckbox(tabContent, "Show Summon Status", "showSummon", statusDB, RefreshPartyFrames)
        showSummonCheck:SetPoint("TOPLEFT", PADDING, y)
        showSummonCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    -- Final height
    tabContent:SetHeight(math.abs(y) + 30)
end

---------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
---------------------------------------------------------------------------
ns.QUI_PartyFramesOptions = {
    BuildPartyFramesTab = BuildPartyFramesTab,
}
