--[[
    QUI Options - Party Keystones Tab
    BuildPartyKeystonesTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildPartyKeystonesTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING

    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 10, subTabName = "Party Keystones"})

    local general = db and db.general
    if not general then return end

    -- Refresh callback
    local function RefreshKeyTracker()
        if _G.QUI_RefreshKeyTracker then
            _G.QUI_RefreshKeyTracker()
        end
    end

    -- SECTION: Party Keystones
    GUI:SetSearchSection("Party Keystones")
    local enableHeader = GUI:CreateSectionHeader(tabContent, "Party Keystones")
    enableHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - enableHeader.gap

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Party Keystones", "keyTrackerEnabled", general, RefreshKeyTracker)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local enableInfo = GUI:CreateLabel(tabContent, "Show party member keystones on the Group Finder (PVE) frame.", 10, C.textMuted)
    enableInfo:SetPoint("TOPLEFT", PADDING, y)
    enableInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    enableInfo:SetJustifyH("LEFT")
    y = y - 20

    -- SECTION: Appearance
    GUI:SetSearchSection("Appearance")
    local appearanceHeader = GUI:CreateSectionHeader(tabContent, "Appearance")
    appearanceHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - appearanceHeader.gap

    local fontList = Shared.GetFontList()
    local fontDropdown = GUI:CreateFormDropdown(tabContent, "Font", fontList, "keyTrackerFont", general, RefreshKeyTracker)
    fontDropdown:SetPoint("TOPLEFT", PADDING, y)
    fontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 7, 12, 1, "keyTrackerFontSize", general, RefreshKeyTracker)
    fontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
    fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - Shared.SLIDER_HEIGHT

    local textColorPicker = GUI:CreateFormColorPicker(tabContent, "Text Color", "keyTrackerTextColor", general, RefreshKeyTracker)
    textColorPicker:SetPoint("TOPLEFT", PADDING, y)
    textColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local widthSlider = GUI:CreateFormSlider(tabContent, "Frame Width", 120, 250, 1, "keyTrackerWidth", general, RefreshKeyTracker)
    widthSlider:SetPoint("TOPLEFT", PADDING, y)
    widthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - Shared.SLIDER_HEIGHT

    -- SECTION: Position
    GUI:SetSearchSection("Position")
    local posHeader = GUI:CreateSectionHeader(tabContent, "Position")
    posHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - posHeader.gap

    local anchorOptions = Shared.NINE_POINT_ANCHOR_OPTIONS

    local pointDropdown = GUI:CreateFormDropdown(tabContent, "Anchor Point", anchorOptions, "keyTrackerPoint", general, RefreshKeyTracker)
    pointDropdown:SetPoint("TOPLEFT", PADDING, y)
    pointDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local relPointDropdown = GUI:CreateFormDropdown(tabContent, "Relative Point", anchorOptions, "keyTrackerRelPoint", general, RefreshKeyTracker)
    relPointDropdown:SetPoint("TOPLEFT", PADDING, y)
    relPointDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local xOffsetSlider = GUI:CreateFormSlider(tabContent, "X Offset", -200, 200, 1, "keyTrackerOffsetX", general, RefreshKeyTracker)
    xOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
    xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - Shared.SLIDER_HEIGHT

    local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -200, 200, 1, "keyTrackerOffsetY", general, RefreshKeyTracker)
    yOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
    yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - Shared.SLIDER_HEIGHT

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_PartyKeystonesOptions = {
    BuildPartyKeystonesTab = BuildPartyKeystonesTab,
}
