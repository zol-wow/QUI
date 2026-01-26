--[[
    QUI Options - Dragonriding/Skyriding Tab
    BuildDragonridingTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildDragonridingTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 1, tabName = "General & QoL", subTabIndex = 8, subTabName = "Dragonriding"})

    -- Refresh callback
    local function RefreshSkyriding()
        if _G.QUI_RefreshSkyriding then
            _G.QUI_RefreshSkyriding()
        end
    end

    -- Get skyriding settings
    if not db.skyriding then db.skyriding = {} end
    local sr = db.skyriding

    -- Initialize defaults if missing
    if sr.enabled == nil then sr.enabled = true end
    if sr.width == nil then sr.width = 250 end
    if sr.vigorHeight == nil then sr.vigorHeight = 12 end
    if sr.secondWindHeight == nil then sr.secondWindHeight = 6 end
    if sr.offsetX == nil then sr.offsetX = 0 end
    if sr.offsetY == nil then sr.offsetY = -150 end
    if sr.locked == nil then sr.locked = true end
    if sr.barTexture == nil then sr.barTexture = "Solid" end
    if sr.showSegments == nil then sr.showSegments = true end
    if sr.showSpeed == nil then sr.showSpeed = true end
    if sr.showVigorText == nil then sr.showVigorText = true end
    if sr.secondWindMode == nil then sr.secondWindMode = "PIPS" end
    if sr.visibility == nil then sr.visibility = "AUTO" end
    if sr.fadeDelay == nil then sr.fadeDelay = 3 end
    if sr.speedFormat == nil then sr.speedFormat = "PERCENT" end
    if sr.vigorTextFormat == nil then sr.vigorTextFormat = "FRACTION" end
    if sr.useClassColorVigor == nil then sr.useClassColorVigor = false end
    if sr.useClassColorSecondWind == nil then sr.useClassColorSecondWind = false end

    -- SECTION: Enable
    GUI:SetSearchSection("Enable")
    local header = GUI:CreateSectionHeader(tabContent, "Skyriding Vigor Bar")
    header:SetPoint("TOPLEFT", PADDING, y)
    y = y - header.gap

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Vigor Bar", "enabled", sr, RefreshSkyriding)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local desc = GUI:CreateLabel(tabContent, "Displays vigor charges, recharge progress, and speed while skyriding.", 10, C.textMuted)
    desc:SetPoint("TOPLEFT", PADDING, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    desc:SetJustifyH("LEFT")
    y = y - 24

    -- SECTION: Visibility
    GUI:SetSearchSection("Visibility")
    local visHeader = GUI:CreateSectionHeader(tabContent, "Visibility")
    visHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - visHeader.gap

    local visOptions = {
        {value = "ALWAYS", text = "Always Visible"},
        {value = "FLYING_ONLY", text = "Only When Flying"},
        {value = "AUTO", text = "Auto (fade when grounded)"},
    }
    local visDropdown = GUI:CreateFormDropdown(tabContent, "Visibility Mode", visOptions, "visibility", sr, RefreshSkyriding)
    visDropdown:SetPoint("TOPLEFT", PADDING, y)
    visDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local fadeDelaySlider = GUI:CreateFormSlider(tabContent, "Fade Delay (sec)", 0, 10, 0.5, "fadeDelay", sr, RefreshSkyriding)
    fadeDelaySlider:SetPoint("TOPLEFT", PADDING, y)
    fadeDelaySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local fadeDurationSlider = GUI:CreateFormSlider(tabContent, "Fade Speed (sec)", 0.1, 1.0, 0.1, "fadeDuration", sr, RefreshSkyriding)
    fadeDurationSlider:SetPoint("TOPLEFT", PADDING, y)
    fadeDurationSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local visInfo = GUI:CreateLabel(tabContent, "Auto mode shows the bar while in a skyriding zone and fades after landing.", 10, C.textMuted)
    visInfo:SetPoint("TOPLEFT", PADDING, y)
    visInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    visInfo:SetJustifyH("LEFT")
    visInfo:SetWordWrap(true)
    y = y - 30

    -- SECTION: Bar Size
    GUI:SetSearchSection("Bar Size")
    local sizeHeader = GUI:CreateSectionHeader(tabContent, "Bar Size")
    sizeHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - sizeHeader.gap

    local widthSlider = GUI:CreateFormSlider(tabContent, "Width", 100, 500, 1, "width", sr, RefreshSkyriding)
    widthSlider:SetPoint("TOPLEFT", PADDING, y)
    widthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local vigorHeightSlider = GUI:CreateFormSlider(tabContent, "Vigor Height", 4, 30, 1, "vigorHeight", sr, RefreshSkyriding)
    vigorHeightSlider:SetPoint("TOPLEFT", PADDING, y)
    vigorHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local swHeightSlider = GUI:CreateFormSlider(tabContent, "Second Wind Height", 2, 20, 1, "secondWindHeight", sr, RefreshSkyriding)
    swHeightSlider:SetPoint("TOPLEFT", PADDING, y)
    swHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local textureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", Shared.GetTextureList(), "barTexture", sr, RefreshSkyriding)
    textureDropdown:SetPoint("TOPLEFT", PADDING, y)
    textureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- SECTION: Position
    GUI:SetSearchSection("Position")
    local posHeader = GUI:CreateSectionHeader(tabContent, "Position")
    posHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - posHeader.gap

    local lockCheck = GUI:CreateFormCheckbox(tabContent, "Lock Position", "locked", sr, RefreshSkyriding)
    lockCheck:SetPoint("TOPLEFT", PADDING, y)
    lockCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local lockInfo = GUI:CreateLabel(tabContent, "Uncheck to drag the bar to a new position.", 10, C.textMuted)
    lockInfo:SetPoint("TOPLEFT", PADDING, y)
    lockInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    lockInfo:SetJustifyH("LEFT")
    y = y - 20

    local xSlider = GUI:CreateFormSlider(tabContent, "X Offset", -1000, 1000, 1, "offsetX", sr, RefreshSkyriding)
    xSlider:SetPoint("TOPLEFT", PADDING, y)
    xSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local ySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -1000, 1000, 1, "offsetY", sr, RefreshSkyriding)
    ySlider:SetPoint("TOPLEFT", PADDING, y)
    ySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- SECTION: Fill Colors
    GUI:SetSearchSection("Fill Colors")
    local fillHeader = GUI:CreateSectionHeader(tabContent, "Fill Colors")
    fillHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - fillHeader.gap

    local barColorPicker  -- Forward declaration for conditional disable
    local function UpdateVigorColorState()
        if barColorPicker then
            barColorPicker:SetAlpha(sr.useClassColorVigor and 0.4 or 1)
        end
        RefreshSkyriding()
    end

    local useClassVigorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Vigor", "useClassColorVigor", sr, UpdateVigorColorState)
    useClassVigorCheck:SetPoint("TOPLEFT", PADDING, y)
    useClassVigorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    barColorPicker = GUI:CreateFormColorPicker(tabContent, "Vigor Fill Color", "barColor", sr, RefreshSkyriding)
    barColorPicker:SetPoint("TOPLEFT", PADDING, y)
    barColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    barColorPicker:SetAlpha(sr.useClassColorVigor and 0.4 or 1)
    y = y - FORM_ROW

    local swColorPicker  -- Forward declaration for conditional disable
    local function UpdateSWColorState()
        if swColorPicker then
            swColorPicker:SetAlpha(sr.useClassColorSecondWind and 0.4 or 1)
        end
        RefreshSkyriding()
    end

    local useClassSWCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Second Wind", "useClassColorSecondWind", sr, UpdateSWColorState)
    useClassSWCheck:SetPoint("TOPLEFT", PADDING, y)
    useClassSWCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    swColorPicker = GUI:CreateFormColorPicker(tabContent, "Second Wind Color", "secondWindColor", sr, RefreshSkyriding)
    swColorPicker:SetPoint("TOPLEFT", PADDING, y)
    swColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    swColorPicker:SetAlpha(sr.useClassColorSecondWind and 0.4 or 1)
    y = y - FORM_ROW

    -- SECTION: Background & Effects
    GUI:SetSearchSection("Background & Effects")
    local bgHeader = GUI:CreateSectionHeader(tabContent, "Background & Effects")
    bgHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - bgHeader.gap

    local bgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "backgroundColor", sr, RefreshSkyriding)
    bgColorPicker:SetPoint("TOPLEFT", PADDING, y)
    bgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local swBgColorPicker = GUI:CreateFormColorPicker(tabContent, "Second Wind Background", "secondWindBackgroundColor", sr, RefreshSkyriding)
    swBgColorPicker:SetPoint("TOPLEFT", PADDING, y)
    swBgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local segColorPicker = GUI:CreateFormColorPicker(tabContent, "Segment Marker Color", "segmentColor", sr, RefreshSkyriding)
    segColorPicker:SetPoint("TOPLEFT", PADDING, y)
    segColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local rechargeColorPicker = GUI:CreateFormColorPicker(tabContent, "Recharge Animation Color", "rechargeColor", sr, RefreshSkyriding)
    rechargeColorPicker:SetPoint("TOPLEFT", PADDING, y)
    rechargeColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- SECTION: Text Display
    GUI:SetSearchSection("Text Display")
    local textHeader = GUI:CreateSectionHeader(tabContent, "Text Display")
    textHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - textHeader.gap

    local showVigorCheck = GUI:CreateFormCheckbox(tabContent, "Show Vigor Count", "showVigorText", sr, RefreshSkyriding)
    showVigorCheck:SetPoint("TOPLEFT", PADDING, y)
    showVigorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local vigorFormatOptions = {
        {value = "FRACTION", text = "Fraction (4/6)"},
        {value = "CURRENT", text = "Current Only (4)"},
    }
    local vigorFormatDropdown = GUI:CreateFormDropdown(tabContent, "Vigor Format", vigorFormatOptions, "vigorTextFormat", sr, RefreshSkyriding)
    vigorFormatDropdown:SetPoint("TOPLEFT", PADDING, y)
    vigorFormatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local showSpeedCheck = GUI:CreateFormCheckbox(tabContent, "Show Speed", "showSpeed", sr, RefreshSkyriding)
    showSpeedCheck:SetPoint("TOPLEFT", PADDING, y)
    showSpeedCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local speedFormatOptions = {
        {value = "PERCENT", text = "Percentage (312%)"},
        {value = "RAW", text = "Raw Speed (9.5)"},
    }
    local speedFormatDropdown = GUI:CreateFormDropdown(tabContent, "Speed Format", speedFormatOptions, "speedFormat", sr, RefreshSkyriding)
    speedFormatDropdown:SetPoint("TOPLEFT", PADDING, y)
    speedFormatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local showAbilityIconCheck = GUI:CreateFormCheckbox(tabContent, "Show Whirling Surge Icon", "showAbilityIcon", sr, RefreshSkyriding)
    showAbilityIconCheck:SetPoint("TOPLEFT", PADDING, y)
    showAbilityIconCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Text Font Size", 8, 24, 1, "vigorFontSize", sr, function()
        sr.speedFontSize = sr.vigorFontSize  -- Keep both in sync
        RefreshSkyriding()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
    fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_SkyridingOptions = {
    BuildDragonridingTab = BuildDragonridingTab
}
