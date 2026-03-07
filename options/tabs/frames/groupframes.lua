--[[
    QUI Group Frames Options
    Full settings UI with sub-tabs for all group frame features.
]]

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
local GetFontList = Shared.GetFontList
local NINE_POINT_ANCHOR_OPTIONS = Shared.NINE_POINT_ANCHOR_OPTIONS

-- Constants
local FORM_ROW = 32
local DROP_ROW = 52       -- Dropdown container is 60px tall (label + button); needs more than FORM_ROW
local SECTION_GAP = 46
local SLIDER_HEIGHT = 65
local PAD = 10

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local function GetGFDB()
    local db = GetDB()
    return db and db.quiGroupFrames
end

local function RefreshGF()
    if _G.QUI_RefreshGroupFrames then
        _G.QUI_RefreshGroupFrames()
    end
end

local GROW_OPTIONS = {
    { value = "DOWN", text = "Down" },
    { value = "UP", text = "Up" },
    { value = "RIGHT", text = "Right (Horizontal)" },
    { value = "LEFT", text = "Left (Horizontal)" },
}

local GROUP_GROW_OPTIONS = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
}

local SORT_OPTIONS = {
    { value = "INDEX", text = "Group Index" },
    { value = "NAME", text = "Name" },
}

local GROUP_BY_OPTIONS = {
    { value = "GROUP", text = "Group Number" },
    { value = "ROLE", text = "Role" },
    { value = "CLASS", text = "Class" },
}

local HEALTH_DISPLAY_OPTIONS = {
    { value = "percent", text = "Percentage" },
    { value = "absolute", text = "Absolute" },
    { value = "both", text = "Both" },
    { value = "deficit", text = "Deficit" },
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

local INDICATOR_TYPE_OPTIONS = {
    { value = "icon", text = "Icon" },
    { value = "square", text = "Colored Square" },
    { value = "bar", text = "Progress Bar" },
    { value = "border", text = "Border Color" },
    { value = "healthcolor", text = "Health Bar Color" },
}

local BAR_ORIENTATION_OPTIONS = {
    { value = "HORIZONTAL", text = "Horizontal" },
    { value = "VERTICAL", text = "Vertical" },
}

local BAR_WIDTH_OPTIONS = {
    { value = "full", text = "Full Width" },
    { value = "half", text = "Half Width" },
}

---------------------------------------------------------------------------
-- HELPER: Preview button for indicator/healer/aura sub-tabs
---------------------------------------------------------------------------
local function CreatePreviewButton(tabContent, y)
    local editMode = ns.QUI_GroupFrameEditMode
    local isActive = editMode and editMode:IsTestMode()

    local label = isActive and "Preview Active" or "Show Preview"
    local btn = GUI:CreateButton(tabContent, label, 140, 26, function()
        if not editMode then return end
        if not editMode:IsTestMode() then
            editMode:EnableTestMode("party")
        end
    end)
    btn:SetPoint("TOPLEFT", PAD, y)

    -- Dim the button when preview is already active
    if isActive then
        btn:Disable()
    end

    return btn, y - 34
end

---------------------------------------------------------------------------
-- PAGE: Group Frames
---------------------------------------------------------------------------
local function CreateGroupFramesPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local db = GetDB()

    -- Build sub-tabs
    local function BuildGeneralTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 1, subTabName = "General"})

        if not gfdb then
            local info = GUI:CreateLabel(tabContent, "Group frame settings not available - database not loaded", 12, C.textMuted)
            info:SetPoint("TOPLEFT", PAD, y)
            tabContent:SetHeight(100)
            return
        end

        -- Enable checkbox (requires reload)
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Group Frames (Req. Reload)", "enabled", gfdb, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Enabling or disabling group frames requires a UI reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Info text
        local infoText = GUI:CreateDescription(tabContent, "Custom party and raid frames. Replaces Blizzard's default group frames when enabled. Compatible with DandersFrames (only one system active at a time).")
        infoText:SetPoint("TOPLEFT", PAD, y)
        infoText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - 40

        -- Test Mode section
        local testHeader = GUI:CreateSectionHeader(tabContent, "Test / Preview")
        testHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - testHeader.gap

        local testDesc = GUI:CreateLabel(tabContent, "Preview group frames when solo. Also available via /qui grouptest", 11, C.textMuted)
        testDesc:SetPoint("TOPLEFT", PAD, y)
        testDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        testDesc:SetJustifyH("LEFT")
        y = y - 24

        -- Party preview + edit
        local partyTestBtn = GUI:CreateButton(tabContent, "Party Preview (5)", 150, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if editMode then editMode:ToggleTestMode("party") end
        end)
        partyTestBtn:SetPoint("TOPLEFT", PAD, y)

        local partyEditBtn = GUI:CreateButton(tabContent, "Edit Party", 120, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if not editMode then return end
            -- If already editing party, toggle off; otherwise enter/switch to party
            if editMode:IsEditMode() and editMode._lastTestPreviewType == "party" then
                editMode:DisableEditMode()
            else
                editMode:EnableEditMode("party")
            end
        end)
        partyEditBtn:SetPoint("LEFT", partyTestBtn, "RIGHT", 10, 0)
        y = y - 36

        -- Raid preview + edit
        local raidTestBtn = GUI:CreateButton(tabContent, "Raid Preview (25)", 150, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if editMode then editMode:ToggleTestMode("raid") end
        end)
        raidTestBtn:SetPoint("TOPLEFT", PAD, y)

        local raidEditBtn = GUI:CreateButton(tabContent, "Edit Raid", 120, 28, function()
            local editMode = ns.QUI_GroupFrameEditMode
            if not editMode then return end
            -- If already editing raid, toggle off; otherwise enter/switch to raid
            if editMode:IsEditMode() and editMode._lastTestPreviewType == "raid" then
                editMode:DisableEditMode()
            else
                editMode:EnableEditMode("raid")
            end
        end)
        raidEditBtn:SetPoint("LEFT", raidTestBtn, "RIGHT", 10, 0)
        y = y - 40

        -- Appearance section
        local appearHeader = GUI:CreateSectionHeader(tabContent, "Appearance")
        appearHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - appearHeader.gap

        local general = gfdb.general
        if not general then gfdb.general = {} general = gfdb.general end

        -- Class colors
        local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Colors", "useClassColor", general, RefreshGF)
        classColorCheck:SetPoint("TOPLEFT", PAD, y)
        classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Widget refs for bidirectional conditional enable/disable
        local defaultWidgets = {}
        local darkModeWidgets = {}

        local function UpdateDarkModeWidgetStates()
            local darkModeOn = general.darkMode
            -- Default widgets: enabled when dark mode OFF
            if defaultWidgets.bgColor then defaultWidgets.bgColor:SetEnabled(not darkModeOn) end
            if defaultWidgets.healthOpacity then defaultWidgets.healthOpacity:SetEnabled(not darkModeOn) end
            if defaultWidgets.bgOpacity then defaultWidgets.bgOpacity:SetEnabled(not darkModeOn) end
            -- Darkmode widgets: enabled when dark mode ON
            if darkModeWidgets.healthColor then darkModeWidgets.healthColor:SetEnabled(darkModeOn) end
            if darkModeWidgets.bgColor then darkModeWidgets.bgColor:SetEnabled(darkModeOn) end
            if darkModeWidgets.healthOpacity then darkModeWidgets.healthOpacity:SetEnabled(darkModeOn) end
            if darkModeWidgets.bgOpacity then darkModeWidgets.bgOpacity:SetEnabled(darkModeOn) end
        end

        -- Default Background Color
        local defBgColor = GUI:CreateFormColorPicker(tabContent, "Default Background Color", "defaultBgColor", general, RefreshGF, { noAlpha = true })
        defBgColor:SetPoint("TOPLEFT", PAD, y)
        defBgColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.bgColor = defBgColor
        y = y - FORM_ROW

        -- Default Health Opacity
        local defHealthOpacity = GUI:CreateFormSlider(tabContent, "Health Opacity", 0.1, 1.0, 0.01, "defaultHealthOpacity", general, RefreshGF)
        defHealthOpacity:SetPoint("TOPLEFT", PAD, y)
        defHealthOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.healthOpacity = defHealthOpacity
        y = y - SLIDER_HEIGHT

        -- Default Background Opacity
        local defBgOpacity = GUI:CreateFormSlider(tabContent, "Background Opacity", 0.1, 1.0, 0.01, "defaultBgOpacity", general, RefreshGF)
        defBgOpacity:SetPoint("TOPLEFT", PAD, y)
        defBgOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.bgOpacity = defBgOpacity
        y = y - SLIDER_HEIGHT

        -- Dark mode toggle
        local darkModeCheck = GUI:CreateFormCheckbox(tabContent, "Dark Mode", "darkMode", general, function()
            RefreshGF()
            UpdateDarkModeWidgetStates()
        end)
        darkModeCheck:SetPoint("TOPLEFT", PAD, y)
        darkModeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Darkmode Health Color
        local dmHealthColor = GUI:CreateFormColorPicker(tabContent, "Darkmode Health Color", "darkModeHealthColor", general, RefreshGF, { noAlpha = true })
        dmHealthColor:SetPoint("TOPLEFT", PAD, y)
        dmHealthColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.healthColor = dmHealthColor
        y = y - FORM_ROW

        -- Darkmode Background Color
        local dmBgColor = GUI:CreateFormColorPicker(tabContent, "Darkmode Background Color", "darkModeBgColor", general, RefreshGF, { noAlpha = true })
        dmBgColor:SetPoint("TOPLEFT", PAD, y)
        dmBgColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.bgColor = dmBgColor
        y = y - FORM_ROW

        -- Darkmode Health Opacity
        local dmHealthOpacity = GUI:CreateFormSlider(tabContent, "Darkmode Health Opacity", 0.1, 1.0, 0.01, "darkModeHealthOpacity", general, RefreshGF)
        dmHealthOpacity:SetPoint("TOPLEFT", PAD, y)
        dmHealthOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.healthOpacity = dmHealthOpacity
        y = y - SLIDER_HEIGHT

        -- Darkmode Background Opacity
        local dmBgOpacity = GUI:CreateFormSlider(tabContent, "Darkmode Background Opacity", 0.1, 1.0, 0.01, "darkModeBgOpacity", general, RefreshGF)
        dmBgOpacity:SetPoint("TOPLEFT", PAD, y)
        dmBgOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.bgOpacity = dmBgOpacity
        y = y - SLIDER_HEIGHT

        -- Set initial enable/disable states
        UpdateDarkModeWidgetStates()

        -- Texture
        local textureDrop = GUI:CreateDropdown(tabContent, "Health Bar Texture", GetTextureList(), "texture", general, RefreshGF)
        textureDrop:SetPoint("TOPLEFT", PAD, y)
        textureDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Border size
        local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 3, 1, "borderSize", general, RefreshGF)
        borderSlider:SetPoint("TOPLEFT", PAD, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Font
        local fontDrop = GUI:CreateDropdown(tabContent, "Font", GetFontList(), "font", general, RefreshGF)
        fontDrop:SetPoint("TOPLEFT", PAD, y)
        fontDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Font size
        local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 20, 1, "fontSize", general, RefreshGF)
        fontSizeSlider:SetPoint("TOPLEFT", PAD, y)
        fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Tooltips
        local tooltipCheck = GUI:CreateFormCheckbox(tabContent, "Show Tooltips on Hover", "showTooltips", general, RefreshGF)
        tooltipCheck:SetPoint("TOPLEFT", PAD, y)
        tooltipCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildLayoutTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 2, subTabName = "Layout"})

        local layout = gfdb.layout
        if not layout then gfdb.layout = {} layout = gfdb.layout end
        local position = gfdb.position
        if not position then gfdb.position = {} position = gfdb.position end

        -- Grow direction
        local growDrop = GUI:CreateDropdown(tabContent, "Grow Direction", GROW_OPTIONS, "growDirection", layout, RefreshGF)
        growDrop:SetPoint("TOPLEFT", PAD, y)
        growDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Group grow direction (raid)
        local groupGrowDrop = GUI:CreateDropdown(tabContent, "Group Grow Direction (Raid)", GROUP_GROW_OPTIONS, "groupGrowDirection", layout, RefreshGF)
        groupGrowDrop:SetPoint("TOPLEFT", PAD, y)
        groupGrowDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Spacing
        local spacingSlider = GUI:CreateFormSlider(tabContent, "Frame Spacing", 0, 10, 1, "spacing", layout, RefreshGF)
        spacingSlider:SetPoint("TOPLEFT", PAD, y)
        spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Group spacing
        local groupSpacingSlider = GUI:CreateFormSlider(tabContent, "Group Spacing (Raid)", 0, 30, 1, "groupSpacing", layout, RefreshGF)
        groupSpacingSlider:SetPoint("TOPLEFT", PAD, y)
        groupSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Show player
        local showPlayerCheck = GUI:CreateFormCheckbox(tabContent, "Show Player in Group", "showPlayer", layout, RefreshGF)
        showPlayerCheck:SetPoint("TOPLEFT", PAD, y)
        showPlayerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Sorting section
        local sortHeader = GUI:CreateSectionHeader(tabContent, "Sorting")
        sortHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - sortHeader.gap

        -- Group By
        local groupByDrop = GUI:CreateDropdown(tabContent, "Group By", GROUP_BY_OPTIONS, "groupBy", layout, RefreshGF)
        groupByDrop:SetPoint("TOPLEFT", PAD, y)
        groupByDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Sort method
        local sortDrop = GUI:CreateDropdown(tabContent, "Sort Method", SORT_OPTIONS, "sortMethod", layout, RefreshGF)
        sortDrop:SetPoint("TOPLEFT", PAD, y)
        sortDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Sort by role
        local roleSortCheck = GUI:CreateFormCheckbox(tabContent, "Sort by Role (Tank > Healer > DPS)", "sortByRole", layout, RefreshGF)
        roleSortCheck:SetPoint("TOPLEFT", PAD, y)
        roleSortCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Position section
        local posHeader = GUI:CreateSectionHeader(tabContent, "Position")
        posHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - posHeader.gap

        local xSlider = GUI:CreateFormSlider(tabContent, "X Offset", -800, 800, 1, "offsetX", position, RefreshGF)
        xSlider:SetPoint("TOPLEFT", PAD, y)
        xSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local ySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -500, 500, 1, "offsetY", position, RefreshGF)
        ySlider:SetPoint("TOPLEFT", PAD, y)
        ySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildDimensionsTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 3, subTabName = "Dimensions"})

        local dims = gfdb.dimensions
        if not dims then gfdb.dimensions = {} dims = gfdb.dimensions end

        -- Party dimensions
        local partyHeader = GUI:CreateSectionHeader(tabContent, "Party (1-5 players)")
        partyHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - partyHeader.gap

        local partyW = GUI:CreateFormSlider(tabContent, "Width", 80, 400, 1, "partyWidth", dims, RefreshGF)
        partyW:SetPoint("TOPLEFT", PAD, y)
        partyW:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local partyH = GUI:CreateFormSlider(tabContent, "Height", 16, 80, 1, "partyHeight", dims, RefreshGF)
        partyH:SetPoint("TOPLEFT", PAD, y)
        partyH:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Small raid
        local smallHeader = GUI:CreateSectionHeader(tabContent, "Small Raid (6-15 players)")
        smallHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - smallHeader.gap

        local smallW = GUI:CreateFormSlider(tabContent, "Width", 60, 400, 1, "smallRaidWidth", dims, RefreshGF)
        smallW:SetPoint("TOPLEFT", PAD, y)
        smallW:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local smallH = GUI:CreateFormSlider(tabContent, "Height", 14, 100, 1, "smallRaidHeight", dims, RefreshGF)
        smallH:SetPoint("TOPLEFT", PAD, y)
        smallH:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Medium raid
        local medHeader = GUI:CreateSectionHeader(tabContent, "Medium Raid (16-25 players)")
        medHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - medHeader.gap

        local medW = GUI:CreateFormSlider(tabContent, "Width", 50, 300, 1, "mediumRaidWidth", dims, RefreshGF)
        medW:SetPoint("TOPLEFT", PAD, y)
        medW:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local medH = GUI:CreateFormSlider(tabContent, "Height", 12, 100, 1, "mediumRaidHeight", dims, RefreshGF)
        medH:SetPoint("TOPLEFT", PAD, y)
        medH:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Large raid
        local largeHeader = GUI:CreateSectionHeader(tabContent, "Large Raid (26-40 players)")
        largeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - largeHeader.gap

        local largeW = GUI:CreateFormSlider(tabContent, "Width", 40, 250, 1, "largeRaidWidth", dims, RefreshGF)
        largeW:SetPoint("TOPLEFT", PAD, y)
        largeW:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local largeH = GUI:CreateFormSlider(tabContent, "Height", 10, 100, 1, "largeRaidHeight", dims, RefreshGF)
        largeH:SetPoint("TOPLEFT", PAD, y)
        largeH:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildHealthPowerTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 4, subTabName = "Health & Power"})

        -- Health section
        local healthHeader = GUI:CreateSectionHeader(tabContent, "Health Text")
        healthHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - healthHeader.gap

        local health = gfdb.health
        if not health then gfdb.health = {} health = gfdb.health end

        local showHealthCheck = GUI:CreateFormCheckbox(tabContent, "Show Health Text", "showHealthText", health, RefreshGF)
        showHealthCheck:SetPoint("TOPLEFT", PAD, y)
        showHealthCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local displayDrop = GUI:CreateDropdown(tabContent, "Display Style", HEALTH_DISPLAY_OPTIONS, "healthDisplayStyle", health, RefreshGF)
        displayDrop:SetPoint("TOPLEFT", PAD, y)
        displayDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local healthFontSlider = GUI:CreateFormSlider(tabContent, "Health Font Size", 8, 20, 1, "healthFontSize", health, RefreshGF)
        healthFontSlider:SetPoint("TOPLEFT", PAD, y)
        healthFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local healthAnchorDrop = GUI:CreateDropdown(tabContent, "Health Text Anchor", NINE_POINT_ANCHOR_OPTIONS, "healthAnchor", health, RefreshGF)
        healthAnchorDrop:SetPoint("TOPLEFT", PAD, y)
        healthAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local healthColor = GUI:CreateFormColorPicker(tabContent, "Health Text Color", "healthTextColor", health, RefreshGF)
        healthColor:SetPoint("TOPLEFT", PAD, y)
        healthColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Name section
        local nameHeader = GUI:CreateSectionHeader(tabContent, "Name Text")
        nameHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - nameHeader.gap

        local nameDB = gfdb.name
        if not nameDB then gfdb.name = {} nameDB = gfdb.name end

        local showNameCheck = GUI:CreateFormCheckbox(tabContent, "Show Name", "showName", nameDB, RefreshGF)
        showNameCheck:SetPoint("TOPLEFT", PAD, y)
        showNameCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local nameFontSlider = GUI:CreateFormSlider(tabContent, "Name Font Size", 8, 20, 1, "nameFontSize", nameDB, RefreshGF)
        nameFontSlider:SetPoint("TOPLEFT", PAD, y)
        nameFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local nameAnchorDrop = GUI:CreateDropdown(tabContent, "Name Anchor", NINE_POINT_ANCHOR_OPTIONS, "nameAnchor", nameDB, RefreshGF)
        nameAnchorDrop:SetPoint("TOPLEFT", PAD, y)
        nameAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local maxNameSlider = GUI:CreateFormSlider(tabContent, "Max Name Length", 0, 20, 1, "maxNameLength", nameDB, RefreshGF)
        maxNameSlider:SetPoint("TOPLEFT", PAD, y)
        maxNameSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local classColorNameCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Name", "nameTextUseClassColor", nameDB, RefreshGF)
        classColorNameCheck:SetPoint("TOPLEFT", PAD, y)
        classColorNameCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local nameColor = GUI:CreateFormColorPicker(tabContent, "Name Text Color", "nameTextColor", nameDB, RefreshGF)
        nameColor:SetPoint("TOPLEFT", PAD, y)
        nameColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Absorbs section
        local absorbHeader = GUI:CreateSectionHeader(tabContent, "Absorbs & Heal Prediction")
        absorbHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - absorbHeader.gap

        local absorbDB = gfdb.absorbs
        if not absorbDB then gfdb.absorbs = {} absorbDB = gfdb.absorbs end

        local absorbCheck = GUI:CreateFormCheckbox(tabContent, "Show Absorb Overlay", "enabled", absorbDB, RefreshGF)
        absorbCheck:SetPoint("TOPLEFT", PAD, y)
        absorbCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local absorbOpacity = GUI:CreateFormSlider(tabContent, "Absorb Opacity", 0.1, 1, 0.05, "opacity", absorbDB, RefreshGF)
        absorbOpacity:SetPoint("TOPLEFT", PAD, y)
        absorbOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local healPredDB = gfdb.healPrediction
        if not healPredDB then gfdb.healPrediction = {} healPredDB = gfdb.healPrediction end

        local healPredCheck = GUI:CreateFormCheckbox(tabContent, "Show Heal Prediction", "enabled", healPredDB, RefreshGF)
        healPredCheck:SetPoint("TOPLEFT", PAD, y)
        healPredCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healPredOpacity = GUI:CreateFormSlider(tabContent, "Heal Prediction Opacity", 0.1, 1, 0.05, "opacity", healPredDB, RefreshGF)
        healPredOpacity:SetPoint("TOPLEFT", PAD, y)
        healPredOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Power bar
        local powerHeader = GUI:CreateSectionHeader(tabContent, "Power Bar")
        powerHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - powerHeader.gap

        local power = gfdb.power
        if not power then gfdb.power = {} power = gfdb.power end

        local showPowerCheck = GUI:CreateFormCheckbox(tabContent, "Show Power Bar", "showPowerBar", power, RefreshGF)
        showPowerCheck:SetPoint("TOPLEFT", PAD, y)
        showPowerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerH = GUI:CreateFormSlider(tabContent, "Power Bar Height", 1, 10, 1, "powerBarHeight", power, RefreshGF)
        powerH:SetPoint("TOPLEFT", PAD, y)
        powerH:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildIndicatorsTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 5, subTabName = "Indicators"})

        local _, newY = CreatePreviewButton(tabContent, y)
        y = newY

        local ind = gfdb.indicators
        if not ind then gfdb.indicators = {} ind = gfdb.indicators end

        -- Role icon
        local roleHeader = GUI:CreateSectionHeader(tabContent, "Role & Status Icons")
        roleHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - roleHeader.gap

        local roleCheck = GUI:CreateFormCheckbox(tabContent, "Show Role Icon", "showRoleIcon", ind, RefreshGF)
        roleCheck:SetPoint("TOPLEFT", PAD, y)
        roleCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local roleSize = GUI:CreateFormSlider(tabContent, "Role Icon Size", 8, 24, 1, "roleIconSize", ind, RefreshGF)
        roleSize:SetPoint("TOPLEFT", PAD, y)
        roleSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local roleAnchor = GUI:CreateDropdown(tabContent, "Role Icon Anchor", NINE_POINT_ANCHOR_OPTIONS, "roleIconAnchor", ind, RefreshGF)
        roleAnchor:SetPoint("TOPLEFT", PAD, y)
        roleAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Ready check
        local readyCheck = GUI:CreateFormCheckbox(tabContent, "Show Ready Check", "showReadyCheck", ind, RefreshGF)
        readyCheck:SetPoint("TOPLEFT", PAD, y)
        readyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Resurrection indicator
        local resCheck = GUI:CreateFormCheckbox(tabContent, "Show Resurrection Indicator", "showResurrection", ind, RefreshGF)
        resCheck:SetPoint("TOPLEFT", PAD, y)
        resCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Summon pending
        local summonCheck = GUI:CreateFormCheckbox(tabContent, "Show Summon Pending", "showSummonPending", ind, RefreshGF)
        summonCheck:SetPoint("TOPLEFT", PAD, y)
        summonCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Leader icon
        local leaderCheck = GUI:CreateFormCheckbox(tabContent, "Show Leader Icon", "showLeaderIcon", ind, RefreshGF)
        leaderCheck:SetPoint("TOPLEFT", PAD, y)
        leaderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Target marker
        local markerCheck = GUI:CreateFormCheckbox(tabContent, "Show Raid Target Marker", "showTargetMarker", ind, RefreshGF)
        markerCheck:SetPoint("TOPLEFT", PAD, y)
        markerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Phase icon
        local phaseCheck = GUI:CreateFormCheckbox(tabContent, "Show Phase Icon", "showPhaseIcon", ind, RefreshGF)
        phaseCheck:SetPoint("TOPLEFT", PAD, y)
        phaseCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Threat border
        local threatHeader = GUI:CreateSectionHeader(tabContent, "Threat")
        threatHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - threatHeader.gap

        local threatCheck = GUI:CreateFormCheckbox(tabContent, "Show Threat Border", "showThreatBorder", ind, RefreshGF)
        threatCheck:SetPoint("TOPLEFT", PAD, y)
        threatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local threatColor = GUI:CreateFormColorPicker(tabContent, "Threat Color", "threatColor", ind, RefreshGF)
        threatColor:SetPoint("TOPLEFT", PAD, y)
        threatColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local threatFill = GUI:CreateFormSlider(tabContent, "Threat Fill Opacity", 0, 0.5, 0.05, "threatFillOpacity", ind, RefreshGF)
        threatFill:SetPoint("TOPLEFT", PAD, y)
        threatFill:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildHealerFeaturesTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 6, subTabName = "Healer Features"})

        local _, newY = CreatePreviewButton(tabContent, y)
        y = newY

        local healer = gfdb.healer
        if not healer then gfdb.healer = {} healer = gfdb.healer end

        -- Dispel overlay
        local dispelHeader = GUI:CreateSectionHeader(tabContent, "Dispel Overlay")
        dispelHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - dispelHeader.gap

        local dispelDesc = GUI:CreateLabel(tabContent, "Colors the frame border based on dispellable debuff type (Magic=blue, Curse=purple, Disease=brown, Poison=green)", 11, C.textMuted)
        dispelDesc:SetPoint("TOPLEFT", PAD, y)
        dispelDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        dispelDesc:SetJustifyH("LEFT")
        y = y - 30

        local dispelDB = healer.dispelOverlay
        if not dispelDB then healer.dispelOverlay = {} dispelDB = healer.dispelOverlay end

        local dispelCheck = GUI:CreateFormCheckbox(tabContent, "Enable Dispel Overlay", "enabled", dispelDB, RefreshGF)
        dispelCheck:SetPoint("TOPLEFT", PAD, y)
        dispelCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local dispelColor = GUI:CreateFormColorPicker(tabContent, "Dispel Color", "color", dispelDB, RefreshGF)
        dispelColor:SetPoint("TOPLEFT", PAD, y)
        dispelColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local dispelOpacity = GUI:CreateFormSlider(tabContent, "Overlay Opacity", 0.1, 1, 0.05, "opacity", dispelDB, RefreshGF)
        dispelOpacity:SetPoint("TOPLEFT", PAD, y)
        dispelOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local dispelFill = GUI:CreateFormSlider(tabContent, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", dispelDB, RefreshGF)
        dispelFill:SetPoint("TOPLEFT", PAD, y)
        dispelFill:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Target highlight
        local highlightHeader = GUI:CreateSectionHeader(tabContent, "Target Highlight")
        highlightHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - highlightHeader.gap

        local highlightDB = healer.targetHighlight
        if not highlightDB then healer.targetHighlight = {} highlightDB = healer.targetHighlight end

        local highlightCheck = GUI:CreateFormCheckbox(tabContent, "Highlight Current Target", "enabled", highlightDB, RefreshGF)
        highlightCheck:SetPoint("TOPLEFT", PAD, y)
        highlightCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local highlightColor = GUI:CreateFormColorPicker(tabContent, "Highlight Color", "color", highlightDB, RefreshGF)
        highlightColor:SetPoint("TOPLEFT", PAD, y)
        highlightColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local highlightFill = GUI:CreateFormSlider(tabContent, "Fill Opacity", 0, 0.5, 0.05, "fillOpacity", highlightDB, RefreshGF)
        highlightFill:SetPoint("TOPLEFT", PAD, y)
        highlightFill:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- My buff indicator
        local myBuffHeader = GUI:CreateSectionHeader(tabContent, "My Buff Indicator")
        myBuffHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - myBuffHeader.gap

        local myBuffDesc = GUI:CreateLabel(tabContent, "Shows a visual overlay when you have an active buff on the unit (e.g., HoTs for healers)", 11, C.textMuted)
        myBuffDesc:SetPoint("TOPLEFT", PAD, y)
        myBuffDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        myBuffDesc:SetJustifyH("LEFT")
        y = y - 30

        local myBuffDB = healer.myBuffIndicator
        if not myBuffDB then healer.myBuffIndicator = {} myBuffDB = healer.myBuffIndicator end

        local myBuffCheck = GUI:CreateFormCheckbox(tabContent, "Enable My Buff Indicator", "enabled", myBuffDB, RefreshGF)
        myBuffCheck:SetPoint("TOPLEFT", PAD, y)
        myBuffCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local myBuffColor = GUI:CreateFormColorPicker(tabContent, "Indicator Color", "color", myBuffDB, RefreshGF)
        myBuffColor:SetPoint("TOPLEFT", PAD, y)
        myBuffColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Defensive indicator
        local defHeader = GUI:CreateSectionHeader(tabContent, "Defensive Indicator")
        defHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - defHeader.gap

        local defDB = healer.defensiveIndicator
        if not defDB then healer.defensiveIndicator = {} defDB = healer.defensiveIndicator end

        local defCheck = GUI:CreateFormCheckbox(tabContent, "Show Defensive Cooldown Icon", "enabled", defDB, RefreshGF)
        defCheck:SetPoint("TOPLEFT", PAD, y)
        defCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local defSize = GUI:CreateFormSlider(tabContent, "Icon Size", 10, 30, 1, "iconSize", defDB, RefreshGF)
        defSize:SetPoint("TOPLEFT", PAD, y)
        defSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local positionOptions = {
            {value = "TOPLEFT", text = "Top Left"},
            {value = "TOP", text = "Top"},
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "LEFT", text = "Left"},
            {value = "CENTER", text = "Center"},
            {value = "RIGHT", text = "Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
            {value = "BOTTOM", text = "Bottom"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }
        local defPos = GUI:CreateFormDropdown(tabContent, "Position", positionOptions, "position", defDB, RefreshGF)
        defPos:SetPoint("TOPLEFT", PAD, y)
        defPos:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local defOffX = GUI:CreateFormSlider(tabContent, "X Offset", -50, 50, 1, "offsetX", defDB, RefreshGF)
        defOffX:SetPoint("TOPLEFT", PAD, y)
        defOffX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local defOffY = GUI:CreateFormSlider(tabContent, "Y Offset", -50, 50, 1, "offsetY", defDB, RefreshGF)
        defOffY:SetPoint("TOPLEFT", PAD, y)
        defOffY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildAurasTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 7, subTabName = "Auras"})

        local _, newY = CreatePreviewButton(tabContent, y)
        y = newY

        local auras = gfdb.auras
        if not auras then gfdb.auras = {} auras = gfdb.auras end

        -- Debuffs
        local debuffHeader = GUI:CreateSectionHeader(tabContent, "Debuffs")
        debuffHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - debuffHeader.gap

        local debuffCheck = GUI:CreateFormCheckbox(tabContent, "Show Debuffs", "showDebuffs", auras, RefreshGF)
        debuffCheck:SetPoint("TOPLEFT", PAD, y)
        debuffCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local maxDebuffs = GUI:CreateFormSlider(tabContent, "Max Debuff Icons", 0, 8, 1, "maxDebuffs", auras, RefreshGF)
        maxDebuffs:SetPoint("TOPLEFT", PAD, y)
        maxDebuffs:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local debuffSize = GUI:CreateFormSlider(tabContent, "Debuff Icon Size", 8, 32, 1, "debuffIconSize", auras, RefreshGF)
        debuffSize:SetPoint("TOPLEFT", PAD, y)
        debuffSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Debuff position
        local debuffPosHeader = GUI:CreateSectionHeader(tabContent, "Debuff Position")
        debuffPosHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - debuffPosHeader.gap

        local debuffAnchorDrop = GUI:CreateDropdown(tabContent, "Anchor Point", NINE_POINT_ANCHOR_OPTIONS, "debuffAnchor", auras, RefreshGF)
        debuffAnchorDrop:SetPoint("TOPLEFT", PAD, y)
        debuffAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local debuffGrowDrop = GUI:CreateDropdown(tabContent, "Grow Direction", AURA_GROW_OPTIONS, "debuffGrowDirection", auras, RefreshGF)
        debuffGrowDrop:SetPoint("TOPLEFT", PAD, y)
        debuffGrowDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local debuffSpacing = GUI:CreateFormSlider(tabContent, "Spacing", 0, 10, 1, "debuffSpacing", auras, RefreshGF)
        debuffSpacing:SetPoint("TOPLEFT", PAD, y)
        debuffSpacing:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local debuffOffX = GUI:CreateFormSlider(tabContent, "Offset X", -50, 50, 1, "debuffOffsetX", auras, RefreshGF)
        debuffOffX:SetPoint("TOPLEFT", PAD, y)
        debuffOffX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local debuffOffY = GUI:CreateFormSlider(tabContent, "Offset Y", -50, 50, 1, "debuffOffsetY", auras, RefreshGF)
        debuffOffY:SetPoint("TOPLEFT", PAD, y)
        debuffOffY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Buffs
        local buffHeader = GUI:CreateSectionHeader(tabContent, "Buffs")
        buffHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - buffHeader.gap

        local buffCheck = GUI:CreateFormCheckbox(tabContent, "Show Buffs", "showBuffs", auras, RefreshGF)
        buffCheck:SetPoint("TOPLEFT", PAD, y)
        buffCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local maxBuffs = GUI:CreateFormSlider(tabContent, "Max Buff Icons", 0, 8, 1, "maxBuffs", auras, RefreshGF)
        maxBuffs:SetPoint("TOPLEFT", PAD, y)
        maxBuffs:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local buffSize = GUI:CreateFormSlider(tabContent, "Buff Icon Size", 8, 32, 1, "buffIconSize", auras, RefreshGF)
        buffSize:SetPoint("TOPLEFT", PAD, y)
        buffSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Buff position
        local buffPosHeader = GUI:CreateSectionHeader(tabContent, "Buff Position")
        buffPosHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - buffPosHeader.gap

        local buffAnchorDrop = GUI:CreateDropdown(tabContent, "Anchor Point", NINE_POINT_ANCHOR_OPTIONS, "buffAnchor", auras, RefreshGF)
        buffAnchorDrop:SetPoint("TOPLEFT", PAD, y)
        buffAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local buffGrowDrop = GUI:CreateDropdown(tabContent, "Grow Direction", AURA_GROW_OPTIONS, "buffGrowDirection", auras, RefreshGF)
        buffGrowDrop:SetPoint("TOPLEFT", PAD, y)
        buffGrowDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local buffSpacingSlider = GUI:CreateFormSlider(tabContent, "Spacing", 0, 10, 1, "buffSpacing", auras, RefreshGF)
        buffSpacingSlider:SetPoint("TOPLEFT", PAD, y)
        buffSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local buffOffX = GUI:CreateFormSlider(tabContent, "Offset X", -50, 50, 1, "buffOffsetX", auras, RefreshGF)
        buffOffX:SetPoint("TOPLEFT", PAD, y)
        buffOffX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local buffOffY = GUI:CreateFormSlider(tabContent, "Offset Y", -50, 50, 1, "buffOffsetY", auras, RefreshGF)
        buffOffY:SetPoint("TOPLEFT", PAD, y)
        buffOffY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Visual settings
        local visualHeader = GUI:CreateSectionHeader(tabContent, "Visual")
        visualHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - visualHeader.gap

        local durationColorCheck = GUI:CreateFormCheckbox(tabContent, "Duration Color Coding (green → yellow → red)", "showDurationColor", auras, RefreshGF)
        durationColorCheck:SetPoint("TOPLEFT", PAD, y)
        durationColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local pulseCheck = GUI:CreateFormCheckbox(tabContent, "Expiring Pulse Animation", "showExpiringPulse", auras, RefreshGF)
        pulseCheck:SetPoint("TOPLEFT", PAD, y)
        pulseCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildAuraIndicatorsTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 8, subTabName = "Aura Indicators"})

        local aidb = gfdb.auraIndicators
        if not aidb then gfdb.auraIndicators = {} aidb = gfdb.auraIndicators end

        -- Enable
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Aura Indicators", "enabled", aidb, RefreshGF)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local presetCheck = GUI:CreateFormCheckbox(tabContent, "Use Built-in Spec Presets", "usePresets", aidb, RefreshGF)
        presetCheck:SetPoint("TOPLEFT", PAD, y)
        presetCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Load preset button
        local presetDesc = GUI:CreateLabel(tabContent, "Load a preset indicator configuration for your current specialization:", 11, C.textMuted)
        presetDesc:SetPoint("TOPLEFT", PAD, y)
        presetDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        presetDesc:SetJustifyH("LEFT")
        y = y - 22

        local loadPresetBtn = GUI:CreateButton(tabContent, "Load Spec Preset", 160, 28, function()
            local specID = GetSpecializationInfo(GetSpecialization() or 1)
            if specID then
                local GFI = ns.QUI_GroupFrameIndicators
                if GFI then
                    local ok = GFI:LoadPresetForSpec(specID)
                    if ok then
                        print("|cFF34D399[QUI]|r Loaded indicator preset for current spec.")
                    else
                        print("|cFF34D399[QUI]|r No preset available for current spec.")
                    end
                end
            end
        end)
        loadPresetBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 36

        -- Indicator types info
        local typesHeader = GUI:CreateSectionHeader(tabContent, "Indicator Types")
        typesHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - typesHeader.gap

        local typesDesc = GUI:CreateLabel(tabContent,
            "Available types: Icon (spell texture + cooldown), Colored Square, Progress Bar, Border Color, Health Bar Color.\n" ..
            "Each indicator can be positioned at any of 9 anchor points (TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, RIGHT, BOTTOMLEFT, BOTTOM, BOTTOMRIGHT).",
            11, C.textMuted)
        typesDesc:SetPoint("TOPLEFT", PAD, y)
        typesDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        typesDesc:SetJustifyH("LEFT")
        y = y - 60

        -- Import/Export section
        local ioHeader = GUI:CreateSectionHeader(tabContent, "Import / Export")
        ioHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - ioHeader.gap

        -- Export button
        local exportBtn = GUI:CreateButton(tabContent, "Export Config", 130, 28, function()
            local specID = GetSpecializationInfo(GetSpecialization() or 1)
            local GFI = ns.QUI_GroupFrameIndicators
            if GFI and specID then
                local encoded = GFI:ExportIndicatorConfig(specID)
                if encoded then
                    -- Show in an edit box for copy
                    local popup = GUI:ShowConfirmation({
                        title = "Indicator Config Export",
                        message = "Copy the string below (Ctrl+C):\n\n" .. encoded:sub(1, 100) .. "...",
                        acceptText = "OK",
                        cancelText = nil,
                    })
                else
                    print("|cFF34D399[QUI]|r No indicator config to export for current spec.")
                end
            end
        end)
        exportBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 36

        -- Healer spec presets info
        local presetsHeader = GUI:CreateSectionHeader(tabContent, "Available Presets")
        presetsHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - presetsHeader.gap

        local presetInfo = {
            "Restoration Druid: Lifebloom, Rejuvenation, Regrowth, Wild Growth, Ironbark",
            "Restoration Shaman: Riptide, Earth Shield, Spirit Link",
            "Discipline Priest: Atonement, PW: Shield, Pain Suppression, Power Infusion",
            "Holy Priest: Renew, Prayer of Mending, Guardian Spirit",
            "Holy Paladin: Beacon of Light, Glimmer, Blessing of Sacrifice",
            "Preservation Evoker: Echo, Reversion, Time Dilation, Lifebind",
            "Mistweaver Monk: Renewing Mist, Enveloping Mist, Essence Font, Life Cocoon",
        }

        for _, text in ipairs(presetInfo) do
            local label = GUI:CreateLabel(tabContent, "• " .. text, 11, C.textMuted)
            label:SetPoint("TOPLEFT", PAD + 4, y)
            label:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            label:SetJustifyH("LEFT")
            y = y - 18
        end

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildClickCastTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 9, subTabName = "Click-Casting"})

        local cc = gfdb.clickCast
        if not cc then gfdb.clickCast = {} cc = gfdb.clickCast end

        -- Enable
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Click-Casting", "enabled", cc, function()
            RefreshGF()
            if cc.enabled then
                print("|cFF34D399[QUI]|r Click-casting enabled. Reload recommended.")
            end
        end)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local cliqueNote = GUI:CreateLabel(tabContent, "Note: If Clique addon is loaded, QUI click-casting is disabled by default to avoid conflicts.", 11, C.textMuted)
        cliqueNote:SetPoint("TOPLEFT", PAD, y)
        cliqueNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        cliqueNote:SetJustifyH("LEFT")
        y = y - 30

        -- Per-spec toggle
        local perSpecCheck = GUI:CreateFormCheckbox(tabContent, "Per-Spec Bindings", "perSpec", cc, RefreshGF)
        perSpecCheck:SetPoint("TOPLEFT", PAD, y)
        perSpecCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Smart res
        local smartResCheck = GUI:CreateFormCheckbox(tabContent, "Smart Resurrection (auto-swap to res on dead targets)", "smartRes", cc, RefreshGF)
        smartResCheck:SetPoint("TOPLEFT", PAD, y)
        smartResCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Show tooltip
        local tooltipCheck = GUI:CreateFormCheckbox(tabContent, "Show Binding Tooltip on Hover", "showTooltip", cc, RefreshGF)
        tooltipCheck:SetPoint("TOPLEFT", PAD, y)
        tooltipCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -------------------------------------------------------------------
        -- CLICK-CAST BACKEND REFERENCE
        -------------------------------------------------------------------
        local GFCC = ns.QUI_GroupFrameClickCast

        -- Action type icons/labels
        local ACTION_TYPE_OPTIONS = {
            { value = "spell",  text = "Spell" },
            { value = "macro",  text = "Macro" },
            { value = "target", text = "Target Unit" },
            { value = "focus",  text = "Set Focus" },
            { value = "assist", text = "Assist" },
        }

        local BUTTON_OPTIONS = {
            { value = "LeftButton",   text = "Left Click" },
            { value = "RightButton",  text = "Right Click" },
            { value = "MiddleButton", text = "Middle Click" },
            { value = "Button4",      text = "Button 4" },
            { value = "Button5",      text = "Button 5" },
        }

        local MOD_OPTIONS = {
            { value = "",              text = "None" },
            { value = "shift",         text = "Shift" },
            { value = "ctrl",          text = "Ctrl" },
            { value = "alt",           text = "Alt" },
            { value = "shift-ctrl",    text = "Shift+Ctrl" },
            { value = "shift-alt",     text = "Shift+Alt" },
            { value = "ctrl-alt",      text = "Ctrl+Alt" },
            { value = "shift-ctrl-alt", text = "Shift+Ctrl+Alt" },
        }

        local ACTION_FALLBACK_ICONS = {
            target = "Interface\\Icons\\Ability_Hunter_SniperShot",
            focus  = "Interface\\Icons\\Ability_TrickShot",
            assist = "Interface\\Icons\\Ability_Hunter_MasterMarksman",
            macro  = "Interface\\Icons\\INV_Misc_Note_01",
        }

        -------------------------------------------------------------------
        -- A. SPEC CONTEXT LABEL
        -------------------------------------------------------------------
        local specLabel = GUI:CreateLabel(tabContent, "", 11, C.accent)
        specLabel:SetPoint("TOPLEFT", PAD, y)
        specLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        specLabel:SetJustifyH("LEFT")
        specLabel:Hide()

        local function UpdateSpecLabel()
            if cc.perSpec then
                local specIndex = GetSpecialization()
                if specIndex then
                    local _, specName = GetSpecializationInfo(specIndex)
                    if specName then
                        specLabel:SetText("Editing bindings for: " .. specName)
                        specLabel:Show()
                        return
                    end
                end
            end
            specLabel:Hide()
        end
        UpdateSpecLabel()
        if specLabel:IsShown() then y = y - 20 end

        -------------------------------------------------------------------
        -- B. CURRENT BINDINGS LIST
        -------------------------------------------------------------------
        local bindingsHeader = GUI:CreateSectionHeader(tabContent, "Current Bindings")
        bindingsHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - bindingsHeader.gap

        -- Container for dynamically built binding rows
        local bindingListFrame = CreateFrame("Frame", nil, tabContent)
        bindingListFrame:SetPoint("TOPLEFT", PAD, y)
        bindingListFrame:SetSize(400, 20)

        -- Forward declaration
        local RefreshBindingList

        -------------------------------------------------------------------
        -- C. ADD BINDING FORM (below list — anchored dynamically)
        -------------------------------------------------------------------
        local addContainer = CreateFrame("Frame", nil, tabContent)
        addContainer:SetPoint("TOPLEFT", bindingListFrame, "BOTTOMLEFT", 0, -10)
        addContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        addContainer:SetHeight(400)
        addContainer:EnableMouse(false)

        local addHeader = GUI:CreateSectionHeader(addContainer, "Add Binding")
        addHeader:SetPoint("TOPLEFT", 0, 0)
        local ay = -addHeader.gap

        -- Drop zone
        local dropZone = CreateFrame("Button", nil, addContainer, "BackdropTemplate")
        dropZone:SetHeight(68)
        dropZone:SetPoint("TOPLEFT", 0, ay)
        dropZone:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
        local pxDrop = QUICore:GetPixelSize(dropZone)
        dropZone:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxDrop,
        })
        dropZone:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.8)
        dropZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

        local dropLabel = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dropLabel:SetPoint("CENTER", 0, 0)
        dropLabel:SetText("Drop a spell from your spellbook")
        dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

        -- Add-form state table (not DB-bound)
        local addState = {
            button    = "LeftButton",
            modifiers = "",
            actionType = "spell",
            spellName = "",
            macroText = "",
        }

        -- Spell name input reference (forward declared for drop zone)
        local spellInput

        dropZone:SetScript("OnReceiveDrag", function()
            local cursorType, id1, id2, _, id4 = GetCursorInfo()
            if cursorType == "spell" then
                local slotIndex = id1
                local bookType = id2 or "spell"
                local spellID = id4

                if not spellID and slotIndex then
                    local spellBank = (bookType == "pet") and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
                    local spellBookInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                    if spellBookInfo then
                        spellID = spellBookInfo.spellID
                    end
                end

                if spellID then
                    local overrideID = C_Spell.GetOverrideSpell(spellID)
                    if overrideID and overrideID ~= spellID then
                        spellID = overrideID
                    end
                    local name = C_Spell.GetSpellName(spellID)
                    if name then
                        addState.spellName = name
                        addState.actionType = "spell"
                        if spellInput then spellInput:SetText(name) end
                    end
                end
                ClearCursor()
            end
        end)
        dropZone:SetScript("OnMouseUp", function(self)
            local cursorType = GetCursorInfo()
            if cursorType == "spell" then
                local handler = self:GetScript("OnReceiveDrag")
                if handler then handler() end
            end
        end)
        dropZone:SetScript("OnEnter", function(self)
            local cursorType = GetCursorInfo()
            if cursorType == "spell" then
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                dropLabel:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
            end
        end)
        dropZone:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
            dropLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end)
        ay = ay - 78

        -- Mouse Button dropdown
        local buttonDrop = GUI:CreateFormDropdown(addContainer, "Mouse Button", BUTTON_OPTIONS, "button", addState)
        buttonDrop:SetPoint("TOPLEFT", 0, ay)
        buttonDrop:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
        ay = ay - FORM_ROW

        -- Modifier dropdown
        local modDrop = GUI:CreateFormDropdown(addContainer, "Modifier", MOD_OPTIONS, "modifiers", addState)
        modDrop:SetPoint("TOPLEFT", 0, ay)
        modDrop:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
        ay = ay - FORM_ROW

        -- Action Type dropdown
        local spellInputContainer, macroInputContainer  -- forward declare for show/hide

        local actionDrop = GUI:CreateFormDropdown(addContainer, "Action Type", ACTION_TYPE_OPTIONS, "actionType", addState, function(val)
            addState.actionType = val
            if spellInputContainer then
                if val == "spell" then spellInputContainer:Show() else spellInputContainer:Hide() end
            end
            if macroInputContainer then
                if val == "macro" then macroInputContainer:Show() else macroInputContainer:Hide() end
            end
        end)
        actionDrop:SetPoint("TOPLEFT", 0, ay)
        actionDrop:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
        ay = ay - FORM_ROW

        -- Spell Name editbox (shown for "spell" action type)
        spellInputContainer = CreateFrame("Frame", nil, addContainer)
        spellInputContainer:SetHeight(FORM_ROW)
        spellInputContainer:SetPoint("TOPLEFT", 0, ay)
        spellInputContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)

        local spellLabel = spellInputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        spellLabel:SetPoint("LEFT", 0, 0)
        spellLabel:SetText("Spell Name")
        spellLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local spellInputBg = CreateFrame("Frame", nil, spellInputContainer, "BackdropTemplate")
        spellInputBg:SetPoint("LEFT", spellInputContainer, "LEFT", 180, 0)
        spellInputBg:SetPoint("RIGHT", spellInputContainer, "RIGHT", 0, 0)
        spellInputBg:SetHeight(24)
        local pxSpell = QUICore:GetPixelSize(spellInputBg)
        spellInputBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxSpell,
        })
        spellInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        spellInput = CreateFrame("EditBox", nil, spellInputBg)
        spellInput:SetPoint("LEFT", 8, 0)
        spellInput:SetPoint("RIGHT", -8, 0)
        spellInput:SetHeight(22)
        spellInput:SetAutoFocus(false)
        spellInput:SetFont(GUI.FONT_PATH, 11, "")
        spellInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        spellInput:SetText("")
        spellInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        spellInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        spellInput:SetScript("OnTextChanged", function(self)
            addState.spellName = self:GetText()
        end)
        spellInput:SetScript("OnEditFocusGained", function()
            spellInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        spellInput:SetScript("OnEditFocusLost", function()
            spellInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end)
        ay = ay - FORM_ROW

        -- Macro Text editbox (shown for "macro" action type)
        macroInputContainer = CreateFrame("Frame", nil, addContainer)
        macroInputContainer:SetHeight(FORM_ROW)
        macroInputContainer:SetPoint("TOPLEFT", 0, ay)
        macroInputContainer:SetPoint("RIGHT", addContainer, "RIGHT", 0, 0)
        macroInputContainer:Hide()

        local macroLabel = macroInputContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        macroLabel:SetPoint("LEFT", 0, 0)
        macroLabel:SetText("Macro Text")
        macroLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local macroInputBg = CreateFrame("Frame", nil, macroInputContainer, "BackdropTemplate")
        macroInputBg:SetPoint("LEFT", macroInputContainer, "LEFT", 180, 0)
        macroInputBg:SetPoint("RIGHT", macroInputContainer, "RIGHT", 0, 0)
        macroInputBg:SetHeight(24)
        local pxMacro = QUICore:GetPixelSize(macroInputBg)
        macroInputBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxMacro,
        })
        macroInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        local macroInput = CreateFrame("EditBox", nil, macroInputBg)
        macroInput:SetPoint("LEFT", 8, 0)
        macroInput:SetPoint("RIGHT", -8, 0)
        macroInput:SetHeight(22)
        macroInput:SetAutoFocus(false)
        macroInput:SetFont(GUI.FONT_PATH, 11, "")
        macroInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        macroInput:SetText("")
        macroInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        macroInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        macroInput:SetScript("OnTextChanged", function(self)
            addState.macroText = self:GetText()
        end)
        macroInput:SetScript("OnEditFocusGained", function()
            macroInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        macroInput:SetScript("OnEditFocusLost", function()
            macroInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end)
        -- ay not decremented here since macro row overlaps spell row slot

        -- "Add Binding" button
        local addBtnY = ay - FORM_ROW  -- below the last input row
        local addBtn = GUI:CreateButton(addContainer, "Add Binding", 130, 26, function()
            local actionType = addState.actionType
            local newBinding = {
                button    = addState.button,
                modifiers = addState.modifiers,
                actionType = actionType,
            }

            if actionType == "spell" then
                local name = addState.spellName
                if not name or name == "" then
                    print("|cFFFF5555[QUI]|r Enter a spell name.")
                    return
                end
                -- Validate spell exists
                local spellID = C_Spell.GetSpellIDForSpellIdentifier(name)
                if not spellID then
                    print("|cFFFF5555[QUI]|r Spell not found: " .. name)
                    return
                end
                newBinding.spell = C_Spell.GetSpellName(spellID) or name
            elseif actionType == "macro" then
                local text = addState.macroText
                if not text or text == "" then
                    print("|cFFFF5555[QUI]|r Enter macro text.")
                    return
                end
                newBinding.spell = "Macro"
                newBinding.macro = text
            else
                -- target/focus/assist — no spell needed
                newBinding.spell = actionType
            end

            local ok, err = GFCC:AddBinding(newBinding)
            if not ok then
                print("|cFFFF5555[QUI]|r " .. (err or "Failed to add binding."))
                return
            end

            -- Reset form
            addState.spellName = ""
            addState.macroText = ""
            spellInput:SetText("")
            macroInput:SetText("")

            RefreshBindingList()
        end)
        addBtn:SetPoint("TOPLEFT", 0, addBtnY)

        -- Total add container height
        addContainer:SetHeight(math.abs(addBtnY) + 36)

        -------------------------------------------------------------------
        -- D. REFRESH BINDING LIST
        -------------------------------------------------------------------
        RefreshBindingList = function()
            -- Clear existing children
            for _, child in ipairs({bindingListFrame:GetChildren()}) do
                child:Hide()
                child:SetParent(nil)
            end

            UpdateSpecLabel()

            local buttonNames = GFCC:GetButtonNames()
            local modLabels  = GFCC:GetModifierLabels()
            local bindings   = GFCC:GetEditableBindings()
            local listY = 0

            if #bindings == 0 then
                local emptyLabel = CreateFrame("Frame", nil, bindingListFrame)
                emptyLabel:SetSize(300, 28)
                emptyLabel:SetPoint("TOPLEFT", 0, 0)
                local emptyText = emptyLabel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("LEFT", 0, 0)
                emptyText:SetText("No bindings configured yet.")
                emptyText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
                listY = -28
            else
                for i, binding in ipairs(bindings) do
                    local row = CreateFrame("Frame", nil, bindingListFrame)
                    row:SetSize(400, 28)
                    row:SetPoint("TOPLEFT", 0, listY)

                    -- Spell icon (24x24)
                    local iconTex = row:CreateTexture(nil, "ARTWORK")
                    iconTex:SetSize(24, 24)
                    iconTex:SetPoint("LEFT", 0, 0)
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                    local actionType = binding.actionType or "spell"
                    if actionType == "spell" and binding.spell then
                        local spellID = C_Spell.GetSpellIDForSpellIdentifier(binding.spell)
                        if spellID then
                            local info = C_Spell.GetSpellInfo(spellID)
                            iconTex:SetTexture(info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
                        else
                            iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                        end
                    else
                        iconTex:SetTexture(ACTION_FALLBACK_ICONS[actionType] or "Interface\\Icons\\INV_Misc_QuestionMark")
                    end

                    -- Modifier + button label
                    local modLabel = modLabels[binding.modifiers or ""] or ""
                    local btnLabel = buttonNames[binding.button] or binding.button
                    local comboText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    comboText:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                    comboText:SetWidth(140)
                    comboText:SetJustifyH("LEFT")
                    comboText:SetText(modLabel .. btnLabel)
                    comboText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

                    -- Spell/action name
                    local spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    spellText:SetPoint("LEFT", comboText, "RIGHT", 8, 0)
                    spellText:SetWidth(140)
                    spellText:SetJustifyH("LEFT")
                    local displayName = binding.spell or actionType
                    if actionType == "macro" then displayName = "Macro" end
                    spellText:SetText(displayName)
                    spellText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

                    -- Remove "X" button (22x22)
                    local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                    removeBtn:SetSize(22, 22)
                    local pxRm = QUICore:GetPixelSize(removeBtn)
                    removeBtn:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = pxRm,
                    })
                    removeBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                    removeBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                    local xText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    xText:SetPoint("CENTER", 0, 0)
                    xText:SetText("X")
                    xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
                    removeBtn:SetScript("OnEnter", function(self)
                        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                        xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    end)
                    removeBtn:SetScript("OnLeave", function(self)
                        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        xText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
                    end)
                    removeBtn:SetScript("OnClick", function()
                        GFCC:RemoveBinding(i)
                        RefreshBindingList()
                    end)
                    removeBtn:SetPoint("LEFT", spellText, "RIGHT", 8, 0)

                    listY = listY - 30
                end
            end

            -- Update list frame height
            local listHeight = math.max(20, math.abs(listY))
            bindingListFrame:SetHeight(listHeight)

            -- Recalculate total content height:
            -- Fixed top sections (toggles + notes + spec label) took us to the y before bindingsHeader
            -- Then: bindingsHeader.gap + listHeight + 10 gap + addContainer height + padding
            local fixedTop = math.abs(y)  -- y at the point we placed bindingListFrame
            local totalHeight = fixedTop + listHeight + 10 + addContainer:GetHeight() + 30
            tabContent:SetHeight(totalHeight)
        end

        RefreshBindingList()

        -------------------------------------------------------------------
        -- E. WIRE PER-SPEC TOGGLE TO REFRESH
        -------------------------------------------------------------------
        perSpecCheck.track:HookScript("OnClick", function()
            C_Timer.After(0.05, function()
                RefreshBindingList()
            end)
        end)
    end

    ---------------------------------------------------------------------------
    -- SUB-TAB: Private Auras (Boss Debuffs)
    ---------------------------------------------------------------------------
    local AURA_GROW_OPTIONS = {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "UP", text = "Up" },
        { value = "DOWN", text = "Down" },
    }

    local PRIVATE_AURA_GROW_OPTIONS = {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "UP", text = "Up" },
        { value = "DOWN", text = "Down" },
    }

    local function BuildPrivateAurasTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 10, subTabName = "Private Auras"})

        local pa = gfdb.privateAuras
        if not pa then gfdb.privateAuras = {} pa = gfdb.privateAuras end

        local desc = GUI:CreateLabel(tabContent,
            "Private auras are boss debuffs hidden from addons. WoW renders them directly into frames you provide. " ..
            "These are critical boss mechanics — keeping this enabled is recommended.",
            11, C.textMuted)
        desc:SetPoint("TOPLEFT", PAD, y)
        desc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        desc:SetJustifyH("LEFT")
        y = y - 40

        -- Enable
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Private Auras", "enabled", pa, RefreshGF)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Icon settings
        local iconHeader = GUI:CreateSectionHeader(tabContent, "Icon Settings")
        iconHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - iconHeader.gap

        local maxSlots = GUI:CreateFormSlider(tabContent, "Max Icons Per Frame", 1, 4, 1, "maxPerFrame", pa, RefreshGF)
        maxSlots:SetPoint("TOPLEFT", PAD, y)
        maxSlots:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local iconSize = GUI:CreateFormSlider(tabContent, "Icon Size", 10, 40, 1, "iconSize", pa, RefreshGF)
        iconSize:SetPoint("TOPLEFT", PAD, y)
        iconSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local spacingSlider = GUI:CreateFormSlider(tabContent, "Icon Spacing", 0, 10, 1, "spacing", pa, RefreshGF)
        spacingSlider:SetPoint("TOPLEFT", PAD, y)
        spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Position
        local posHeader = GUI:CreateSectionHeader(tabContent, "Position")
        posHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - posHeader.gap

        local anchorDrop = GUI:CreateDropdown(tabContent, "Anchor Point", NINE_POINT_ANCHOR_OPTIONS, "anchor", pa, RefreshGF)
        anchorDrop:SetPoint("TOPLEFT", PAD, y)
        anchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local growDrop = GUI:CreateDropdown(tabContent, "Grow Direction", PRIVATE_AURA_GROW_OPTIONS, "growDirection", pa, RefreshGF)
        growDrop:SetPoint("TOPLEFT", PAD, y)
        growDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local offsetX = GUI:CreateFormSlider(tabContent, "Offset X", -50, 50, 1, "anchorOffsetX", pa, RefreshGF)
        offsetX:SetPoint("TOPLEFT", PAD, y)
        offsetX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local offsetY = GUI:CreateFormSlider(tabContent, "Offset Y", -50, 50, 1, "anchorOffsetY", pa, RefreshGF)
        offsetY:SetPoint("TOPLEFT", PAD, y)
        offsetY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Countdown
        local countdownHeader = GUI:CreateSectionHeader(tabContent, "Countdown")
        countdownHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - countdownHeader.gap

        local countdownCheck = GUI:CreateFormCheckbox(tabContent, "Show Countdown Frame", "showCountdown", pa, RefreshGF)
        countdownCheck:SetPoint("TOPLEFT", PAD, y)
        countdownCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local numbersCheck = GUI:CreateFormCheckbox(tabContent, "Show Countdown Numbers", "showCountdownNumbers", pa, RefreshGF)
        numbersCheck:SetPoint("TOPLEFT", PAD, y)
        numbersCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        tabContent:SetHeight(math.abs(y) + 30)
    end

    local function BuildRangeTab(tabContent)
        local y = -10
        local gfdb = GetGFDB()
        if not gfdb then return end

        GUI:SetSearchContext({tabIndex = 6, tabName = "Group Frames", subTabIndex = 11, subTabName = "Range & Misc"})

        -- Range check
        local rangeHeader = GUI:CreateSectionHeader(tabContent, "Range Check")
        rangeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - rangeHeader.gap

        local range = gfdb.range
        if not range then gfdb.range = {} range = gfdb.range end

        local rangeCheck = GUI:CreateFormCheckbox(tabContent, "Enable Range Check (dim out-of-range members)", "enabled", range, RefreshGF)
        rangeCheck:SetPoint("TOPLEFT", PAD, y)
        rangeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local rangeAlpha = GUI:CreateFormSlider(tabContent, "Out-of-Range Alpha", 0.1, 0.8, 0.05, "outOfRangeAlpha", range, RefreshGF)
        rangeAlpha:SetPoint("TOPLEFT", PAD, y)
        rangeAlpha:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Portrait
        local portraitHeader = GUI:CreateSectionHeader(tabContent, "Portrait")
        portraitHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - portraitHeader.gap

        local portrait = gfdb.portrait
        if not portrait then gfdb.portrait = {} portrait = gfdb.portrait end

        local portraitCheck = GUI:CreateFormCheckbox(tabContent, "Show Portrait", "showPortrait", portrait, RefreshGF)
        portraitCheck:SetPoint("TOPLEFT", PAD, y)
        portraitCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local portraitSide = GUI:CreateDropdown(tabContent, "Portrait Side", ANCHOR_SIDE_OPTIONS, "portraitSide", portrait, RefreshGF)
        portraitSide:SetPoint("TOPLEFT", PAD, y)
        portraitSide:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local portraitSize = GUI:CreateFormSlider(tabContent, "Portrait Size", 16, 60, 1, "portraitSize", portrait, RefreshGF)
        portraitSize:SetPoint("TOPLEFT", PAD, y)
        portraitSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        -- Pet frames
        local petHeader = GUI:CreateSectionHeader(tabContent, "Pet Frames")
        petHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - petHeader.gap

        local pets = gfdb.pets
        if not pets then gfdb.pets = {} pets = gfdb.pets end

        local petCheck = GUI:CreateFormCheckbox(tabContent, "Enable Pet Frames", "enabled", pets, RefreshGF)
        petCheck:SetPoint("TOPLEFT", PAD, y)
        petCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local petW = GUI:CreateFormSlider(tabContent, "Pet Frame Width", 40, 200, 1, "width", pets, RefreshGF)
        petW:SetPoint("TOPLEFT", PAD, y)
        petW:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local petH = GUI:CreateFormSlider(tabContent, "Pet Frame Height", 10, 40, 1, "height", pets, RefreshGF)
        petH:SetPoint("TOPLEFT", PAD, y)
        petH:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        local petAnchor = GUI:CreateDropdown(tabContent, "Pet Anchor", PET_ANCHOR_OPTIONS, "anchorTo", pets, RefreshGF)
        petAnchor:SetPoint("TOPLEFT", PAD, y)
        petAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        -- Spotlight
        local spotHeader = GUI:CreateSectionHeader(tabContent, "Spotlight")
        spotHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - spotHeader.gap

        local spotDesc = GUI:CreateLabel(tabContent, "Pin specific raid members (by role or name) to a separate highlighted group for tank-watch or healing assignment awareness.", 11, C.textMuted)
        spotDesc:SetPoint("TOPLEFT", PAD, y)
        spotDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        spotDesc:SetJustifyH("LEFT")
        y = y - 30

        local spot = gfdb.spotlight
        if not spot then gfdb.spotlight = {} spot = gfdb.spotlight end

        local spotCheck = GUI:CreateFormCheckbox(tabContent, "Enable Spotlight", "enabled", spot, RefreshGF)
        spotCheck:SetPoint("TOPLEFT", PAD, y)
        spotCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spotGrow = GUI:CreateDropdown(tabContent, "Spotlight Grow Direction", GROW_OPTIONS, "growDirection", spot, RefreshGF)
        spotGrow:SetPoint("TOPLEFT", PAD, y)
        spotGrow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - DROP_ROW

        local spotSpacing = GUI:CreateFormSlider(tabContent, "Spotlight Spacing", 0, 10, 1, "spacing", spot, RefreshGF)
        spotSpacing:SetPoint("TOPLEFT", PAD, y)
        spotSpacing:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - SLIDER_HEIGHT

        tabContent:SetHeight(math.abs(y) + 30)
    end

    -- Create sub-tabs
    local subTabs = {
        {name = "General", builder = BuildGeneralTab},
        {name = "Layout", builder = BuildLayoutTab},
        {name = "Dimensions", builder = BuildDimensionsTab},
        {name = "Health & Power", builder = BuildHealthPowerTab},
        {name = "Indicators", builder = BuildIndicatorsTab},
        {name = "Healer", builder = BuildHealerFeaturesTab},
        {name = "Auras", builder = BuildAurasTab},
        {name = "Aura Indicators", builder = BuildAuraIndicatorsTab},
        {name = "Click-Cast", builder = BuildClickCastTab},
        {name = "Private Auras", builder = BuildPrivateAurasTab},
        {name = "Range & Misc", builder = BuildRangeTab},
    }

    GUI:CreateSubTabs(content, subTabs)

    content:SetHeight(600)
end

---------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
---------------------------------------------------------------------------
ns.QUI_GroupFramesOptions = {
    CreateGroupFramesPage = CreateGroupFramesPage
}
