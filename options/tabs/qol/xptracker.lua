--[[
    QUI Options - XP Tracker Tab
    BuildXPTrackerTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildXPTrackerTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 11, subTabName = "XP Tracker"})

    -- Refresh callback
    local function RefreshXPTracker()
        if _G.QUI_RefreshXPTracker then
            _G.QUI_RefreshXPTracker()
        end
    end

    -- Get xpTracker settings
    if not db.xpTracker then db.xpTracker = {} end
    local xp = db.xpTracker

    -- Initialize defaults if missing
    if xp.enabled == nil then xp.enabled = false end
    if xp.width == nil then xp.width = 300 end
    if xp.height == nil then xp.height = 90 end
    if xp.barHeight == nil then xp.barHeight = 20 end
    if xp.headerFontSize == nil then xp.headerFontSize = 12 end
    if xp.headerLineHeight == nil then xp.headerLineHeight = 18 end
    if xp.fontSize == nil then xp.fontSize = 11 end
    if xp.lineHeight == nil then xp.lineHeight = 14 end
    if xp.offsetX == nil then xp.offsetX = 0 end
    if xp.offsetY == nil then xp.offsetY = 150 end
    if xp.locked == nil then xp.locked = true end
    if xp.hideTextUntilHover == nil then xp.hideTextUntilHover = false end
    if xp.detailsGrowDirection == nil then xp.detailsGrowDirection = "auto" end
    if xp.barTexture == nil then xp.barTexture = "Solid" end
    if xp.showBarText == nil then xp.showBarText = true end
    if xp.showRested == nil then xp.showRested = true end

    -- SECTION: Enable
    GUI:SetSearchSection("Enable")
    local header = GUI:CreateSectionHeader(tabContent, "XP Tracker")
    header:SetPoint("TOPLEFT", PADDING, y)
    y = y - header.gap

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable XP Tracker", "enabled", xp, RefreshXPTracker)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local desc = GUI:CreateLabel(tabContent, "Displays experience progress, rested XP, XP/hour rate, and time-to-level estimates. Auto-hides at max level.", 10, C.textMuted)
    desc:SetPoint("TOPLEFT", PADDING, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    y = y - 30

    -- Preview toggle (standalone, not DB-bound)
    local isPreview = _G.QUI_IsXPTrackerPreviewMode and _G.QUI_IsXPTrackerPreviewMode() or false
    local previewToggle = GUI:CreateFormToggle(tabContent, "Preview Mode", nil, nil, function(val)
        if _G.QUI_ToggleXPTrackerPreview then
            _G.QUI_ToggleXPTrackerPreview(val)
        end
    end)
    previewToggle:SetPoint("TOPLEFT", PADDING, y)
    previewToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    -- Use dot-call here: CreateFormToggle.SetValue(val, skipCallback) is not a colon method.
    previewToggle.SetValue(isPreview, true)
    y = y - FORM_ROW

    local previewDesc = GUI:CreateLabel(tabContent, "Shows the tracker with sample data for positioning and styling.", 10, C.textMuted)
    previewDesc:SetPoint("TOPLEFT", PADDING, y)
    previewDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    previewDesc:SetJustifyH("LEFT")
    y = y - 24

    -- SECTION: Frame Size
    GUI:SetSearchSection("Frame Size")
    local sizeHeader = GUI:CreateSectionHeader(tabContent, "Frame Size")
    sizeHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - sizeHeader.gap

    local widthSlider = GUI:CreateFormSlider(tabContent, "Bar Width", 200, 1000, 1, "width", xp, RefreshXPTracker)
    widthSlider:SetPoint("TOPLEFT", PADDING, y)
    widthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local heightSlider = GUI:CreateFormSlider(tabContent, "Height", 60, 200, 1, "height", xp, RefreshXPTracker)
    heightSlider:SetPoint("TOPLEFT", PADDING, y)
    heightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local barHeightSlider = GUI:CreateFormSlider(tabContent, "Bar Height", 8, 40, 1, "barHeight", xp, RefreshXPTracker)
    barHeightSlider:SetPoint("TOPLEFT", PADDING, y)
    barHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local headerFontSizeSlider = GUI:CreateFormSlider(tabContent, "Header Font Size", 8, 22, 1, "headerFontSize", xp, RefreshXPTracker)
    headerFontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
    headerFontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local headerLineHeightSlider = GUI:CreateFormSlider(tabContent, "Header Line Height", 12, 30, 1, "headerLineHeight", xp, RefreshXPTracker)
    headerLineHeightSlider:SetPoint("TOPLEFT", PADDING, y)
    headerLineHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 18, 1, "fontSize", xp, RefreshXPTracker)
    fontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
    fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local lineHeightSlider = GUI:CreateFormSlider(tabContent, "Line Height", 10, 24, 1, "lineHeight", xp, RefreshXPTracker)
    lineHeightSlider:SetPoint("TOPLEFT", PADDING, y)
    lineHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local textureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", Shared.GetTextureList(), "barTexture", xp, RefreshXPTracker)
    textureDropdown:SetPoint("TOPLEFT", PADDING, y)
    textureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- SECTION: Position
    GUI:SetSearchSection("Position")
    local posHeader = GUI:CreateSectionHeader(tabContent, "Position")
    posHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - posHeader.gap

    local lockCheck = GUI:CreateFormCheckbox(tabContent, "Lock Position", "locked", xp, RefreshXPTracker)
    lockCheck:SetPoint("TOPLEFT", PADDING, y)
    lockCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local lockInfo = GUI:CreateLabel(tabContent, "Uncheck to drag the tracker to a new position.", 10, C.textMuted)
    lockInfo:SetPoint("TOPLEFT", PADDING, y)
    lockInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    lockInfo:SetJustifyH("LEFT")
    y = y - 20

    local xSlider = GUI:CreateFormSlider(tabContent, "X Offset", -1000, 1000, 1, "offsetX", xp, RefreshXPTracker)
    xSlider:SetPoint("TOPLEFT", PADDING, y)
    xSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -1000, 1000, 1, "offsetY", xp, RefreshXPTracker)
    ySlider:SetPoint("TOPLEFT", PADDING, y)
    ySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- SECTION: Colors
    GUI:SetSearchSection("Colors")
    local colorHeader = GUI:CreateSectionHeader(tabContent, "Colors")
    colorHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - colorHeader.gap

    local barColorPicker = GUI:CreateFormColorPicker(tabContent, "XP Bar Color", "barColor", xp, RefreshXPTracker)
    barColorPicker:SetPoint("TOPLEFT", PADDING, y)
    barColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local restedColorPicker = GUI:CreateFormColorPicker(tabContent, "Rested XP Color", "restedColor", xp, RefreshXPTracker)
    restedColorPicker:SetPoint("TOPLEFT", PADDING, y)
    restedColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local backdropColorPicker = GUI:CreateFormColorPicker(tabContent, "Backdrop Color", "backdropColor", xp, RefreshXPTracker)
    backdropColorPicker:SetPoint("TOPLEFT", PADDING, y)
    backdropColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColor", xp, RefreshXPTracker)
    borderColorPicker:SetPoint("TOPLEFT", PADDING, y)
    borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- SECTION: Display Options
    GUI:SetSearchSection("Display Options")
    local displayHeader = GUI:CreateSectionHeader(tabContent, "Display Options")
    displayHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - displayHeader.gap

    local showBarTextCheck = GUI:CreateFormCheckbox(tabContent, "Show Bar Text", "showBarText", xp, RefreshXPTracker)
    showBarTextCheck:SetPoint("TOPLEFT", PADDING, y)
    showBarTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local showBarTextDesc = GUI:CreateLabel(tabContent, "Shows XP values and percentages overlaid on the progress bar.", 10, C.textMuted)
    showBarTextDesc:SetPoint("TOPLEFT", PADDING, y)
    showBarTextDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    showBarTextDesc:SetJustifyH("LEFT")
    y = y - 24

    local showRestedCheck = GUI:CreateFormCheckbox(tabContent, "Show Rested XP Overlay", "showRested", xp, RefreshXPTracker)
    showRestedCheck:SetPoint("TOPLEFT", PADDING, y)
    showRestedCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local showRestedDesc = GUI:CreateLabel(tabContent, "Shows a colored overlay on the progress bar representing rested XP bonus.", 10, C.textMuted)
    showRestedDesc:SetPoint("TOPLEFT", PADDING, y)
    showRestedDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    showRestedDesc:SetJustifyH("LEFT")
    y = y - 24

    local hideTextCheck = GUI:CreateFormCheckbox(tabContent, "Hide Text Until Hover", "hideTextUntilHover", xp, RefreshXPTracker)
    hideTextCheck:SetPoint("TOPLEFT", PADDING, y)
    hideTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local hideTextDesc = GUI:CreateLabel(tabContent, "Hides the header and stat lines, showing only the bar. Hover to reveal text.", 10, C.textMuted)
    hideTextDesc:SetPoint("TOPLEFT", PADDING, y)
    hideTextDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    hideTextDesc:SetJustifyH("LEFT")
    y = y - 24

    local growDirectionOptions = {
        {value = "auto", text = "Auto"},
        {value = "up", text = "Up"},
        {value = "down", text = "Down"},
    }
    local growDirectionDropdown = GUI:CreateFormDropdown(tabContent, "Details Grow Direction", growDirectionOptions, "detailsGrowDirection", xp, RefreshXPTracker)
    growDirectionDropdown:SetPoint("TOPLEFT", PADDING, y)
    growDirectionDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local growDirectionDesc = GUI:CreateLabel(tabContent, "Auto grows details above/below based on screen space. Up/Down forces a fixed direction.", 10, C.textMuted)
    growDirectionDesc:SetPoint("TOPLEFT", PADDING, y)
    growDirectionDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    growDirectionDesc:SetJustifyH("LEFT")
    y = y - 24

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_XPTrackerOptions = {
    BuildXPTrackerTab = BuildXPTrackerTab
}
