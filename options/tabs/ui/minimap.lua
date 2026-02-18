--[[
    QUI Options - Minimap & Datatext Tabs
    BuildMinimapTab and BuildDatatextTab for Minimap & Datatext page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local UIKit = ns.UIKit

-- Import shared utilities
local Shared = ns.QUI_Options
local QUICore = ns.Addon

-- Refresh callbacks
local function RefreshMinimap()
    if _G.QUI_RefreshMinimap then
        _G.QUI_RefreshMinimap()
    end
end

local function RefreshUIHider()
    if _G.QUI_RefreshUIHider then
        _G.QUI_RefreshUIHider()
    end
end

local function RefreshDatapanels()
    if QUICore and QUICore.Datapanels then
        QUICore.Datapanels:RefreshAll()
    end
end

-- Tab rebuild support for dynamic panel list
local datatextTabContent = nil
local BuildDatatextTab  -- forward declaration for rebuild

local function RebuildDatatextTab()
    if not datatextTabContent or not BuildDatatextTab then return end
    -- Hide all existing children
    local children = {datatextTabContent:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:ClearAllPoints()
    end
    -- Hide all regions (font strings, textures)
    local regions = {datatextTabContent:GetRegions()}
    for _, region in ipairs(regions) do
        region:Hide()
    end
    -- Rebuild the tab contents
    BuildDatatextTab(datatextTabContent)
end

local function GetTrackedBackpackCurrencies()
    local currencies = {}
    local seen = {}

    if not _G.C_CurrencyInfo or not C_CurrencyInfo.GetBackpackCurrencyInfo then
        return currencies
    end

    local i = 1
    while true do
        local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
        if not info then break end

        local currencyID = info.currencyTypesID or info.currencyID
        if currencyID and info.name and info.quantity ~= nil and not seen[currencyID] then
            seen[currencyID] = true
            currencies[#currencies + 1] = {
                value = tostring(currencyID),
                text = info.name,
            }
        end
        i = i + 1
    end

    return currencies
end

local function BuildTrackedCurrencySignature()
    local currencies = GetTrackedBackpackCurrencies()
    local values = {}
    for i = 1, #currencies do
        values[i] = currencies[i].value
    end
    return table.concat(values, ",")
end

local function CheckAndRebuildCurrencyOptions()
    if not datatextTabContent or not datatextTabContent:IsShown() then
        return
    end

    local currentSignature = BuildTrackedCurrencySignature()
    if currentSignature ~= (datatextTabContent._lastTrackedCurrencySignature or "") then
        datatextTabContent._lastTrackedCurrencySignature = currentSignature
        RebuildDatatextTab()
    end
end

-- Singleton edit popup for custom datapanels
local editPopup = nil

local function ShowPanelEditPopup(panelConfig, panelIndex)
    if not editPopup then
        editPopup = CreateFrame("Frame", "QUI_DatapanelEditPopup", UIParent, "BackdropTemplate")
        editPopup:SetSize(440, 520)
        editPopup:SetPoint("CENTER")
        editPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        editPopup:SetFrameLevel(400)
        editPopup:EnableMouse(true)
        editPopup:SetMovable(true)
        editPopup:RegisterForDrag("LeftButton")
        editPopup:SetScript("OnDragStart", function(self) self:StartMoving() end)
        editPopup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        editPopup:SetClampedToScreen(true)

        local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(editPopup)) or 1
        editPopup:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        editPopup:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.98)
        editPopup:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)

        -- Title
        editPopup.title = editPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        editPopup.title:SetPoint("TOP", 0, -12)
        editPopup.title:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)

        -- Close button
        local closeBtn = GUI:CreateButton(editPopup, "Close", 70, 24, function()
            editPopup:Hide()
        end)
        closeBtn:SetPoint("TOPRIGHT", -8, -8)

        -- Scroll frame (mouse wheel only, no scroll bar)
        editPopup.scrollFrame = CreateFrame("ScrollFrame", nil, editPopup)
        editPopup.scrollFrame:SetPoint("TOPLEFT", 8, -40)
        editPopup.scrollFrame:SetPoint("BOTTOMRIGHT", -8, 10)
        ns.ApplyScrollWheel(editPopup.scrollFrame)

        editPopup:Hide()
    end

    -- Hide old content before creating new scroll child
    local oldChild = editPopup.scrollFrame:GetScrollChild()
    if oldChild then
        oldChild:Hide()
        oldChild:SetParent(nil)
    end

    -- Create new content frame each time (replaces old scroll child)
    local content = CreateFrame("Frame", nil, editPopup.scrollFrame)
    content:SetWidth(440 - 16)  -- popup width minus padding
    editPopup.scrollFrame:SetScrollChild(content)
    editPopup.scrollFrame:SetVerticalScroll(0)

    -- Set title
    editPopup.title:SetText("Edit: " .. (panelConfig.name or ("Panel " .. panelIndex)))

    -- Suppress search registration for popup widgets
    local prevSuppress = GUI._suppressSearchRegistration
    GUI._suppressSearchRegistration = true

    local y = -10
    local PAD = 10
    local FORM_ROW = 32

    -- Panel Settings
    local settingsHeader = GUI:CreateSectionHeader(content, "Panel Settings")
    settingsHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - settingsHeader.gap

    local widthSlider = GUI:CreateFormSlider(content, "Width", 100, 800, 10, "width", panelConfig, RefreshDatapanels)
    widthSlider:SetPoint("TOPLEFT", PAD, y)
    widthSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local heightSlider = GUI:CreateFormSlider(content, "Height (Per Row)", 18, 50, 1, "height", panelConfig, RefreshDatapanels)
    heightSlider:SetPoint("TOPLEFT", PAD, y)
    heightSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local numSlotsSlider = GUI:CreateFormSlider(content, "Number of Slots", 1, 8, 1, "numSlots", panelConfig, function()
        RefreshDatapanels()
        -- Rebuild popup to show correct number of slot configs
        ShowPanelEditPopup(panelConfig, panelIndex)
    end)
    numSlotsSlider:SetPoint("TOPLEFT", PAD, y)
    numSlotsSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local bgOpacitySlider = GUI:CreateFormSlider(content, "Background Opacity", 0, 100, 5, "bgOpacity", panelConfig, RefreshDatapanels)
    bgOpacitySlider:SetPoint("TOPLEFT", PAD, y)
    bgOpacitySlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local borderSlider = GUI:CreateFormSlider(content, "Border Size (0=hidden)", 0, 8, 1, "borderSize", panelConfig, RefreshDatapanels)
    borderSlider:SetPoint("TOPLEFT", PAD, y)
    borderSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    if not panelConfig.borderColor then
        panelConfig.borderColor = {0, 0, 0, 1}
    end

    local borderColorPicker = GUI:CreateFormColorPicker(content, "Border Color", "borderColor", panelConfig, RefreshDatapanels)
    borderColorPicker:SetPoint("TOPLEFT", PAD, y)
    borderColorPicker:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local fontSlider = GUI:CreateFormSlider(content, "Font Size", 9, 18, 1, "fontSize", panelConfig, RefreshDatapanels)
    fontSlider:SetPoint("TOPLEFT", PAD, y)
    fontSlider:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    y = y - 10

    -- Slot Configuration
    local slotsHeader = GUI:CreateSectionHeader(content, "Slot Configuration")
    slotsHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - slotsHeader.gap

    -- Build datatext options from registry
    local dtOptions = {{value = "", text = "(empty)"}}
    if QUICore and QUICore.Datatexts then
        local allDatatexts = QUICore.Datatexts:GetAll()
        for _, datatextDef in ipairs(allDatatexts) do
            table.insert(dtOptions, {value = datatextDef.id, text = datatextDef.displayName})
        end
    end

    -- Ensure slots and slotSettings exist
    if not panelConfig.slots then panelConfig.slots = {} end
    if not panelConfig.slotSettings then panelConfig.slotSettings = {} end

    local numSlots = panelConfig.numSlots or 3
    for s = 1, numSlots do
        if not panelConfig.slotSettings[s] then
            panelConfig.slotSettings[s] = { shortLabel = false, noLabel = false }
        end

        local slotDropdown = GUI:CreateFormDropdown(content, "Slot " .. s, dtOptions, nil, nil, function(val)
            panelConfig.slots[s] = val
            RefreshDatapanels()
        end)
        slotDropdown:SetPoint("TOPLEFT", PAD, y)
        slotDropdown:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        if slotDropdown.SetValue then slotDropdown.SetValue(panelConfig.slots[s] or "") end
        y = y - FORM_ROW

        local noLabelCheck  -- Forward declare for mutual reference
        local shortLabelCheck = GUI:CreateFormCheckbox(content, "Slot " .. s .. " Short Label", "shortLabel", panelConfig.slotSettings[s], function()
            if noLabelCheck then noLabelCheck:SetEnabled(not panelConfig.slotSettings[s].shortLabel) end
            RefreshDatapanels()
        end)
        shortLabelCheck:SetPoint("TOPLEFT", PAD, y)
        shortLabelCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        noLabelCheck = GUI:CreateFormCheckbox(content, "Slot " .. s .. " No Label", "noLabel", panelConfig.slotSettings[s], function()
            if shortLabelCheck then shortLabelCheck:SetEnabled(not panelConfig.slotSettings[s].noLabel) end
            RefreshDatapanels()
        end)
        noLabelCheck:SetPoint("TOPLEFT", PAD, y)
        noLabelCheck:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        noLabelCheck:SetEnabled(not panelConfig.slotSettings[s].shortLabel)
        shortLabelCheck:SetEnabled(not panelConfig.slotSettings[s].noLabel)
        y = y - FORM_ROW

        y = y - 6  -- Gap between slots
    end

    -- Hint text
    local hintText = GUI:CreateLabel(content, "Empty slots are hidden. Panels only appear when at least one slot has a datatext.", 11, C.textMuted)
    hintText:SetPoint("TOPLEFT", PAD, y)
    hintText:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    hintText:SetJustifyH("LEFT")
    y = y - 28

    -- Set content height for scrolling
    content:SetHeight(math.abs(y) + 20)

    -- Restore search registration state
    GUI._suppressSearchRegistration = prevSuppress

    editPopup:Show()
end

local function BuildMinimapTab(tabContent)
    local y = -10
    local PAD = 10
    local FORM_ROW = 32
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 6, tabName = "Minimap & Datatext", subTabIndex = 1, subTabName = "Minimap"})

    -- Early return if database not ready
    if not db then
        local errorLabel = GUI:CreateLabel(tabContent, "Database not ready. Please /reload.", 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, y)
        tabContent:SetHeight(50)
        return
    end

    -- Ensure minimap table exists (for fresh installs where AceDB defaults may not initialize)
    if not db.minimap then
        db.minimap = {}
    end
    local mm = db.minimap

    if true then  -- Always build widgets

        -- SECTION 1: General
        local generalHeader = GUI:CreateSectionHeader(tabContent, "General")
        generalHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - generalHeader.gap

        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable QUI Minimap", "enabled", mm, RefreshMinimap)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local lockCheck = GUI:CreateFormCheckbox(tabContent, "Lock QUI Minimap", "lock", mm, RefreshMinimap)
        lockCheck:SetPoint("TOPLEFT", PAD, y)
        lockCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local sizeSlider = GUI:CreateFormSlider(tabContent, "Map Dimensions (Pixels)", 120, 380, 1, "size", mm, RefreshMinimap)
        sizeSlider:SetPoint("TOPLEFT", PAD, y)
        sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local scaleSlider = GUI:CreateFormSlider(tabContent, "Minimap Scale", 0.5, 2.0, 0.01, "scale", mm, RefreshMinimap, { deferOnDrag = true })
        scaleSlider:SetPoint("TOPLEFT", PAD, y)
        scaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local scaleDesc = GUI:CreateLabel(tabContent, "Scales minimap and datatext panel together without changing base pixel size.", 11, C.textMuted)
        scaleDesc:SetPoint("TOPLEFT", PAD, y + 4)
        scaleDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        scaleDesc:SetJustifyH("LEFT")
        y = y - 20

        y = y - 10

        -- SECTION 2: Frame Styling
        local styleHeader = GUI:CreateSectionHeader(tabContent, "Frame Styling")
        styleHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - styleHeader.gap

        local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 1, 16, 1, "borderSize", mm, RefreshMinimap)
        borderSlider:SetPoint("TOPLEFT", PAD, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderColor = GUI:CreateFormColorPicker(tabContent, "Custom Border Color", "borderColor", mm, RefreshMinimap)
        borderColor:SetPoint("TOPLEFT", PAD, y)
        borderColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Normalize mutually exclusive flags on load (prefer class color)
        if mm.useClassColorBorder and mm.useAccentColorBorder then
            mm.useAccentColorBorder = false
        end

        local accentBorderCheck
        local classBorderCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Edge", "useClassColorBorder", mm, function(val)
            if val then
                mm.useAccentColorBorder = false
                if accentBorderCheck and accentBorderCheck.SetChecked then accentBorderCheck:SetChecked(false) end
            end
            if borderColor and borderColor.SetEnabled then
                borderColor:SetEnabled(not val and not mm.useAccentColorBorder)
            end
            RefreshMinimap()
        end)
        classBorderCheck:SetPoint("TOPLEFT", PAD, y)
        classBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        accentBorderCheck = GUI:CreateFormCheckbox(tabContent, "Use Accent Color for Edge", "useAccentColorBorder", mm, function(val)
            if val then
                mm.useClassColorBorder = false
                if classBorderCheck and classBorderCheck.SetChecked then classBorderCheck:SetChecked(false) end
            end
            if borderColor and borderColor.SetEnabled then
                borderColor:SetEnabled(not val and not mm.useClassColorBorder)
            end
            RefreshMinimap()
        end)
        accentBorderCheck:SetPoint("TOPLEFT", PAD, y)
        accentBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Sync color picker enabled state on load
        if borderColor and borderColor.SetEnabled then
            borderColor:SetEnabled(not mm.useClassColorBorder and not mm.useAccentColorBorder)
        end

        y = y - 10

        -- SECTION 3: Hide Minimap Elements
        local hideHeader = GUI:CreateSectionHeader(tabContent, "Hide Minimap Elements")
        hideHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - hideHeader.gap

        -- Using inverted checkboxes: checked = hide (DB false), unchecked = show (DB true)
        local hideMail = GUI:CreateFormCheckboxInverted(tabContent, "Hide Mail (reload after)", "showMail", mm, RefreshMinimap)
        hideMail:SetPoint("TOPLEFT", PAD, y)
        hideMail:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideTracking = GUI:CreateFormCheckboxInverted(tabContent, "Hide Tracking", "showTracking", mm, RefreshMinimap)
        hideTracking:SetPoint("TOPLEFT", PAD, y)
        hideTracking:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideDifficulty = GUI:CreateFormCheckboxInverted(tabContent, "Hide Difficulty", "showDifficulty", mm, RefreshMinimap)
        hideDifficulty:SetPoint("TOPLEFT", PAD, y)
        hideDifficulty:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideExpansion = GUI:CreateFormCheckboxInverted(tabContent, "Hide Progress Report", "showMissions", mm, RefreshMinimap)
        hideExpansion:SetPoint("TOPLEFT", PAD, y)
        hideExpansion:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- UIHider minimap controls (uses db.uiHider)
        if not db.uiHider then db.uiHider = {} end

        local hideBorder = GUI:CreateFormCheckbox(tabContent, "Hide Border (Top)", "hideMinimapBorder", db.uiHider, RefreshUIHider)
        hideBorder:SetPoint("TOPLEFT", PAD, y)
        hideBorder:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideClock = GUI:CreateFormCheckbox(tabContent, "Hide Clock Button", "hideTimeManager", db.uiHider, RefreshUIHider)
        hideClock:SetPoint("TOPLEFT", PAD, y)
        hideClock:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideCalendar = GUI:CreateFormCheckbox(tabContent, "Hide Calendar Button", "hideGameTime", db.uiHider, RefreshUIHider)
        hideCalendar:SetPoint("TOPLEFT", PAD, y)
        hideCalendar:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideZoneText = GUI:CreateFormCheckbox(tabContent, "Hide Zone Text (Native)", "hideMinimapZoneText", db.uiHider, RefreshUIHider)
        hideZoneText:SetPoint("TOPLEFT", PAD, y)
        hideZoneText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideZoom = GUI:CreateFormCheckboxInverted(tabContent, "Hide Zoom Buttons", "showZoomButtons", mm, RefreshMinimap)
        hideZoom:SetPoint("TOPLEFT", PAD, y)
        hideZoom:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        -- SECTION 4: Zone Label
        local zoneHeader = GUI:CreateSectionHeader(tabContent, "Zone Label")
        zoneHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - zoneHeader.gap

        local showZoneCheck = GUI:CreateFormCheckbox(tabContent, "Show Zone Label", "showZoneText", mm, RefreshMinimap)
        showZoneCheck:SetPoint("TOPLEFT", PAD, y)
        showZoneCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if mm.zoneTextConfig then
            local zoneOffsetX = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -150, 150, 1, "offsetX", mm.zoneTextConfig, RefreshMinimap)
            zoneOffsetX:SetPoint("TOPLEFT", PAD, y)
            zoneOffsetX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local zoneOffsetY = GUI:CreateFormSlider(tabContent, "Vertical Offset", -150, 150, 1, "offsetY", mm.zoneTextConfig, RefreshMinimap)
            zoneOffsetY:SetPoint("TOPLEFT", PAD, y)
            zoneOffsetY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local zoneSize = GUI:CreateFormSlider(tabContent, "Label Size", 8, 20, 1, "fontSize", mm.zoneTextConfig, RefreshMinimap)
            zoneSize:SetPoint("TOPLEFT", PAD, y)
            zoneSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local zoneAllCaps = GUI:CreateFormCheckbox(tabContent, "Uppercase Text", "allCaps", mm.zoneTextConfig, RefreshMinimap)
            zoneAllCaps:SetPoint("TOPLEFT", PAD, y)
            zoneAllCaps:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local zoneClassColor = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", mm.zoneTextConfig, RefreshMinimap)
            zoneClassColor:SetPoint("TOPLEFT", PAD, y)
            zoneClassColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end
    end

    -- SECTION 5: Dungeon Eye (LFG Queue Button)
    if true then
        y = y - 10
        GUI:SetSearchSection("Dungeon Eye")
        local eyeHeader = GUI:CreateSectionHeader(tabContent, "Dungeon Eye (LFG Queue)")
        eyeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - eyeHeader.gap

        -- Description text
        local eyeDesc = GUI:CreateLabel(tabContent, "When enabled, the queue eye automatically appears on the minimap when you join a queue.", 11, C.textMuted)
        eyeDesc:SetPoint("TOPLEFT", PAD, y)
        eyeDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        eyeDesc:SetJustifyH("LEFT")
        y = y - 20

        -- Ensure dungeonEye settings exist
        local mm = db.minimap
        if not mm.dungeonEye then
            mm.dungeonEye = {
                enabled = true,
                corner = "BOTTOMLEFT",
                scale = 0.6,
                offsetX = 0,
                offsetY = 0,
            }
        end
        local eye = mm.dungeonEye

        -- Enable toggle
        local eyeEnable = GUI:CreateFormCheckbox(tabContent, "Enable Dungeon Eye", "enabled", eye, RefreshMinimap)
        eyeEnable:SetPoint("TOPLEFT", PAD, y)
        eyeEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Corner dropdown
        local cornerOptions = {
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "TOPLEFT", text = "Top Left"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
        }
        local eyeCorner = GUI:CreateFormDropdown(tabContent, "Corner Position", cornerOptions, "corner", eye, RefreshMinimap)
        eyeCorner:SetPoint("TOPLEFT", PAD, y)
        eyeCorner:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Scale slider
        local eyeScale = GUI:CreateFormSlider(tabContent, "Icon Scale", 0.1, 2.0, 0.1, "scale", eye, RefreshMinimap)
        eyeScale:SetPoint("TOPLEFT", PAD, y)
        eyeScale:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- X Offset slider
        local eyeOffsetX = GUI:CreateFormSlider(tabContent, "X Offset", -30, 30, 1, "offsetX", eye, RefreshMinimap)
        eyeOffsetX:SetPoint("TOPLEFT", PAD, y)
        eyeOffsetX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Y Offset slider
        local eyeOffsetY = GUI:CreateFormSlider(tabContent, "Y Offset", -30, 30, 1, "offsetY", eye, RefreshMinimap)
        eyeOffsetY:SetPoint("TOPLEFT", PAD, y)
        eyeOffsetY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    end

    tabContent:SetHeight(math.abs(y) + 50)
end

BuildDatatextTab = function(tabContent)
    datatextTabContent = tabContent  -- Store for rebuild
    local y = -10
    local PAD = 10
    local FORM_ROW = 32
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 6, tabName = "Minimap & Datatext", subTabIndex = 2, subTabName = "Datatext"})

    -- Early return if database not ready
    if not db then
        local errorLabel = GUI:CreateLabel(tabContent, "Database not ready. Please /reload.", 12, {1, 0.3, 0.3, 1})
        errorLabel:SetPoint("TOPLEFT", PAD, y)
        tabContent:SetHeight(50)
        return
    end

    if not tabContent._currencyWatcher then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        watcher:SetScript("OnEvent", function()
            CheckAndRebuildCurrencyOptions()
        end)
        if BackpackTokenFrame and BackpackTokenFrame.Update then
            hooksecurefunc(BackpackTokenFrame, "Update", function()
                CheckAndRebuildCurrencyOptions()
            end)
        end
        tabContent._currencyWatcher = watcher
    end
    if not tabContent._currencyTicker and C_Timer and C_Timer.NewTicker then
        tabContent._currencyTicker = C_Timer.NewTicker(0.5, function()
            CheckAndRebuildCurrencyOptions()
        end)
    end
    tabContent._lastTrackedCurrencySignature = BuildTrackedCurrencySignature()

    -- Ensure datatext table exists (for fresh installs where AceDB defaults may not initialize)
    if not db.datatext then
        db.datatext = {}
    end
    local dt = db.datatext

    if true then  -- Always build widgets

        -- SECTION 1: Minimap Datatext Settings
        GUI:SetSearchSection("Minimap Datatext Settings")
        local panelHeader = GUI:CreateSectionHeader(tabContent, "Minimap Datatext Settings")
        panelHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - panelHeader.gap

        -- Description text (grouped together)
        local noteLabel = GUI:CreateLabel(tabContent, "This datatext panel is anchored below the minimap and cannot be moved. To create additional movable panels, scroll down to 'Custom Movable Panels'.", 11, C.textMuted)
        noteLabel:SetPoint("TOPLEFT", PAD, y)
        noteLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        noteLabel:SetJustifyH("LEFT")
        y = y - 38

        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Minimap Datatext", "enabled", dt, RefreshMinimap)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forceSingleLine = GUI:CreateFormCheckbox(tabContent, "Force Single Line", "forceSingleLine", dt, RefreshMinimap)
        forceSingleLine:SetPoint("TOPLEFT", PAD, y)
        forceSingleLine:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local heightSlider = GUI:CreateFormSlider(tabContent, "Panel Height (Per Row)", 18, 50, 1, "height", dt, RefreshMinimap)
        heightSlider:SetPoint("TOPLEFT", PAD, y)
        heightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local bgOpacitySlider = GUI:CreateFormSlider(tabContent, "Background Transparency", 0, 100, 5, "bgOpacity", dt, RefreshMinimap)
        bgOpacitySlider:SetPoint("TOPLEFT", PAD, y)
        bgOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSizeSlider = GUI:CreateFormSlider(tabContent, "Border Size (0=hidden)", 0, 8, 1, "borderSize", dt, RefreshMinimap)
        borderSizeSlider:SetPoint("TOPLEFT", PAD, y)
        borderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColor", dt, RefreshMinimap)
        borderColorPicker:SetPoint("TOPLEFT", PAD, y)
        borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local offsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -40, 40, 1, "offsetY", dt, RefreshMinimap)
        offsetYSlider:SetPoint("TOPLEFT", PAD, y)
        offsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        -- Build datatext options from registry
        local dtOptions = {{value = "", text = "(empty)"}}
        if QUICore and QUICore.Datatexts then
            local allDatatexts = QUICore.Datatexts:GetAll()
            for _, datatextDef in ipairs(allDatatexts) do
                table.insert(dtOptions, {value = datatextDef.id, text = datatextDef.displayName})
            end
        end

        -- Ensure slots table and per-slot configs exist
        if not dt.slots then
            dt.slots = {"time", "friends", "guild"}
        end
        if not dt.slot1 then dt.slot1 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if not dt.slot2 then dt.slot2 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if not dt.slot3 then dt.slot3 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if dt.slot1.noLabel == nil then dt.slot1.noLabel = false end
        if dt.slot2.noLabel == nil then dt.slot2.noLabel = false end
        if dt.slot3.noLabel == nil then dt.slot3.noLabel = false end

        -- Slot 1 Group
        local slot1 = GUI:CreateFormDropdown(tabContent, "Slot 1 (Left)", dtOptions, nil, nil, function(val)
            dt.slots[1] = val
            RefreshMinimap()
        end)
        slot1:SetPoint("TOPLEFT", PAD, y)
        slot1:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        if slot1.SetValue then slot1.SetValue(dt.slots[1] or "") end
        y = y - FORM_ROW

        local slot1NoLabel  -- Forward declare for mutual reference
        local slot1Short = GUI:CreateFormCheckbox(tabContent, "Slot 1 Short Label", "shortLabel", dt.slot1, function()
            if slot1NoLabel then slot1NoLabel:SetEnabled(not dt.slot1.shortLabel) end
            RefreshMinimap()
        end)
        slot1Short:SetPoint("TOPLEFT", PAD, y)
        slot1Short:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        slot1NoLabel = GUI:CreateFormCheckbox(tabContent, "Slot 1 No Label", "noLabel", dt.slot1, function()
            if slot1Short then slot1Short:SetEnabled(not dt.slot1.noLabel) end
            RefreshMinimap()
        end)
        slot1NoLabel:SetPoint("TOPLEFT", PAD, y)
        slot1NoLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        slot1NoLabel:SetEnabled(not dt.slot1.shortLabel)
        slot1Short:SetEnabled(not dt.slot1.noLabel)
        y = y - FORM_ROW

        local slot1XOff = GUI:CreateFormSlider(tabContent, "Slot 1 X Offset", -50, 50, 1, "xOffset", dt.slot1, RefreshMinimap)
        slot1XOff:SetPoint("TOPLEFT", PAD, y)
        slot1XOff:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local slot1YOff = GUI:CreateFormSlider(tabContent, "Slot 1 Y Offset", -20, 20, 1, "yOffset", dt.slot1, RefreshMinimap)
        slot1YOff:SetPoint("TOPLEFT", PAD, y)
        slot1YOff:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10  -- Gap before Slot 2

        -- Slot 2 Group
        local slot2 = GUI:CreateFormDropdown(tabContent, "Slot 2 (Center)", dtOptions, nil, nil, function(val)
            dt.slots[2] = val
            RefreshMinimap()
        end)
        slot2:SetPoint("TOPLEFT", PAD, y)
        slot2:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        if slot2.SetValue then slot2.SetValue(dt.slots[2] or "") end
        y = y - FORM_ROW

        local slot2NoLabel  -- Forward declare for mutual reference
        local slot2Short = GUI:CreateFormCheckbox(tabContent, "Slot 2 Short Label", "shortLabel", dt.slot2, function()
            if slot2NoLabel then slot2NoLabel:SetEnabled(not dt.slot2.shortLabel) end
            RefreshMinimap()
        end)
        slot2Short:SetPoint("TOPLEFT", PAD, y)
        slot2Short:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        slot2NoLabel = GUI:CreateFormCheckbox(tabContent, "Slot 2 No Label", "noLabel", dt.slot2, function()
            if slot2Short then slot2Short:SetEnabled(not dt.slot2.noLabel) end
            RefreshMinimap()
        end)
        slot2NoLabel:SetPoint("TOPLEFT", PAD, y)
        slot2NoLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        slot2NoLabel:SetEnabled(not dt.slot2.shortLabel)
        slot2Short:SetEnabled(not dt.slot2.noLabel)
        y = y - FORM_ROW

        local slot2XOff = GUI:CreateFormSlider(tabContent, "Slot 2 X Offset", -50, 50, 1, "xOffset", dt.slot2, RefreshMinimap)
        slot2XOff:SetPoint("TOPLEFT", PAD, y)
        slot2XOff:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local slot2YOff = GUI:CreateFormSlider(tabContent, "Slot 2 Y Offset", -20, 20, 1, "yOffset", dt.slot2, RefreshMinimap)
        slot2YOff:SetPoint("TOPLEFT", PAD, y)
        slot2YOff:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10  -- Gap before Slot 3

        -- Slot 3 Group
        local slot3 = GUI:CreateFormDropdown(tabContent, "Slot 3 (Right)", dtOptions, nil, nil, function(val)
            dt.slots[3] = val
            RefreshMinimap()
        end)
        slot3:SetPoint("TOPLEFT", PAD, y)
        slot3:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        if slot3.SetValue then slot3.SetValue(dt.slots[3] or "") end
        y = y - FORM_ROW

        local slot3NoLabel  -- Forward declare for mutual reference
        local slot3Short = GUI:CreateFormCheckbox(tabContent, "Slot 3 Short Label", "shortLabel", dt.slot3, function()
            if slot3NoLabel then slot3NoLabel:SetEnabled(not dt.slot3.shortLabel) end
            RefreshMinimap()
        end)
        slot3Short:SetPoint("TOPLEFT", PAD, y)
        slot3Short:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        slot3NoLabel = GUI:CreateFormCheckbox(tabContent, "Slot 3 No Label", "noLabel", dt.slot3, function()
            if slot3Short then slot3Short:SetEnabled(not dt.slot3.noLabel) end
            RefreshMinimap()
        end)
        slot3NoLabel:SetPoint("TOPLEFT", PAD, y)
        slot3NoLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        slot3NoLabel:SetEnabled(not dt.slot3.shortLabel)
        slot3Short:SetEnabled(not dt.slot3.noLabel)
        y = y - FORM_ROW

        local slot3XOff = GUI:CreateFormSlider(tabContent, "Slot 3 X Offset", -50, 50, 1, "xOffset", dt.slot3, RefreshMinimap)
        slot3XOff:SetPoint("TOPLEFT", PAD, y)
        slot3XOff:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local slot3YOff = GUI:CreateFormSlider(tabContent, "Slot 3 Y Offset", -20, 20, 1, "yOffset", dt.slot3, RefreshMinimap)
        slot3YOff:SetPoint("TOPLEFT", PAD, y)
        slot3YOff:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Hint text explaining flexible slot behavior
        local hintText = GUI:CreateLabel(tabContent, "Empty slots are hidden. Using 2 datatexts gives each 50% width.", 11, C.textMuted)
        hintText:SetPoint("TOPLEFT", PAD, y)
        hintText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        hintText:SetJustifyH("LEFT")
        y = y - 28

        y = y - 10

        -- SECTION 3: Spec Display Options
        local specHeader = GUI:CreateSectionHeader(tabContent, "Spec Display Options")
        specHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - specHeader.gap

        local specDisplayDropdown = GUI:CreateFormDropdown(tabContent, "Spec Display Mode", {
            {value = "icon", text = "Icon Only"},
            {value = "loadout", text = "Icon + Loadout"},
            {value = "full", text = "Full (Spec / Loadout)"},
        }, "specDisplayMode", dt, function()
            -- Refresh all datatexts to apply the new display mode immediately
            if QUICore and QUICore.Datatexts and QUICore.Datatexts.UpdateAll then
                QUICore.Datatexts:UpdateAll()
            end
        end)
        specDisplayDropdown:SetPoint("TOPLEFT", PAD, y)
        specDisplayDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        -- SECTION 4: Time Options
        local timeHeader = GUI:CreateSectionHeader(tabContent, "Time Options")
        timeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - timeHeader.gap

        local timeFormatDropdown = GUI:CreateFormDropdown(tabContent, "Time Format", {
            {value = "local", text = "Local Time"},
            {value = "server", text = "Server Time"},
        }, "timeFormat", dt, RefreshMinimap)
        timeFormatDropdown:SetPoint("TOPLEFT", PAD, y)
        timeFormatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local clockFormatDropdown = GUI:CreateFormDropdown(tabContent, "Clock Format", {
            {value = true, text = "24-Hour Clock"},
            {value = false, text = "AM/PM"},
        }, "use24Hour", dt, RefreshMinimap)
        clockFormatDropdown:SetPoint("TOPLEFT", PAD, y)
        clockFormatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        -- SECTION 5: Text Styling
        local fontHeader = GUI:CreateSectionHeader(tabContent, "Text Styling")
        fontHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - fontHeader.gap

        local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Text Size", 9, 18, 1, "fontSize", dt, RefreshMinimap)
        fontSizeSlider:SetPoint("TOPLEFT", PAD, y)
        fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local useClassColor = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", dt, function()
            RefreshMinimap()
            -- Also update custom datapanels
            if QUICore and QUICore.Datatexts and QUICore.Datatexts.UpdateAll then
                QUICore.Datatexts:UpdateAll()
            end
        end)
        useClassColor:SetPoint("TOPLEFT", PAD, y)
        useClassColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local valueColor = GUI:CreateFormColorPicker(tabContent, "Custom Text Color", "valueColor", dt, function()
            RefreshMinimap()
            -- Also update custom datapanels
            if QUICore and QUICore.Datatexts and QUICore.Datatexts.UpdateAll then
                QUICore.Datatexts:UpdateAll()
            end
        end)
        valueColor:SetPoint("TOPLEFT", PAD, y)
        valueColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10

        -- SECTION 5b: Time Datatext Settings
        local timeHeader2 = GUI:CreateSectionHeader(tabContent, "Time Datatext")
        timeHeader2:SetPoint("TOPLEFT", PAD, y)
        y = y - timeHeader2.gap

        local lockoutCacheSlider = GUI:CreateFormSlider(tabContent, "Lockout Refresh (minutes)", 1, 30, 1, "lockoutCacheMinutes", dt, nil)
        lockoutCacheSlider:SetPoint("TOPLEFT", PAD, y)
        lockoutCacheSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local lockoutNote = GUI:CreateLabel(tabContent, "How often to refresh raid lockout data when hovering the Time datatext.", 11, C.textMuted)
        lockoutNote:SetPoint("TOPLEFT", PAD, y)
        lockoutNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        lockoutNote:SetJustifyH("LEFT")
        y = y - 20

        y = y - 10

        -- SECTION 5c: Currencies Datatext Settings
        GUI:SetSearchSection("Currencies Datatext")
        local currenciesHeader = GUI:CreateSectionHeader(tabContent, "Currencies Datatext")
        currenciesHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - currenciesHeader.gap

        local currenciesNote = GUI:CreateLabel(tabContent, "Choose up to 6 tracked currencies. Drag rows to reorder. Changes to tracked backpack currencies update this list automatically.", 11, C.textMuted)
        currenciesNote:SetPoint("TOPLEFT", PAD, y)
        currenciesNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        currenciesNote:SetJustifyH("LEFT")
        y = y - 38

        if type(dt.currencyOrder) ~= "table" then
            dt.currencyOrder = {}
        end
        if type(dt.currencyEnabled) ~= "table" then
            dt.currencyEnabled = {}
        end

        local trackedCurrencies = GetTrackedBackpackCurrencies()
        local trackedById = {}
        local trackedByName = {}
        for _, currency in ipairs(trackedCurrencies) do
            trackedById[currency.value] = currency
            trackedByName[currency.text] = currency.value
        end

        local function SyncCurrencySettings()
            local ordered = {}
            local seen = {}

            for _, rawValue in ipairs(dt.currencyOrder) do
                local value = rawValue
                if type(value) == "number" then
                    value = tostring(value)
                end

                if type(value) == "string" and value ~= "" and value ~= "none" then
                    local resolved = value
                    if not trackedById[resolved] then
                        local numericValue = tonumber(resolved)
                        if numericValue and trackedById[tostring(numericValue)] then
                            resolved = tostring(numericValue)
                        else
                            resolved = trackedByName[resolved]
                        end
                    end

                    if resolved and trackedById[resolved] and not seen[resolved] then
                        seen[resolved] = true
                        ordered[#ordered + 1] = resolved
                    end
                end
            end

            for _, currency in ipairs(trackedCurrencies) do
                if not seen[currency.value] then
                    seen[currency.value] = true
                    ordered[#ordered + 1] = currency.value
                end
            end

            local enabled = {}
            for _, currencyId in ipairs(ordered) do
                local currentValue = dt.currencyEnabled[currencyId]
                if currentValue == nil then
                    enabled[currencyId] = true
                else
                    enabled[currencyId] = currentValue and true or false
                end
            end

            dt.currencyOrder = ordered
            dt.currencyEnabled = enabled
        end

        local function RefreshCurrenciesDatatext()
            if QUICore and QUICore.Datatexts then
                QUICore.Datatexts:UpdateAll()
            end
        end

        SyncCurrencySettings()

        local selectedCount = 0
        for _, currencyId in ipairs(dt.currencyOrder) do
            if dt.currencyEnabled[currencyId] ~= false then
                selectedCount = selectedCount + 1
            end
        end

        local rowHeader = GUI:CreateLabel(tabContent, "Tracked currencies: reorder list and check Show (first 6 checked are displayed). Checked: " .. tostring(selectedCount), 11, C.textMuted)
        rowHeader:SetPoint("TOPLEFT", PAD, y + 6)
        y = y - 18

        local currencyRows = {}
        local ROW_HEIGHT = 26
        local ROW_GAP = 4
        local ROW_STEP = ROW_HEIGHT + ROW_GAP
        local listStartY = y

        local dragState = {
            active = false,
            fromIndex = nil,
            toIndex = nil,
            row = nil,
            rowBaseStrata = nil,
            rowBaseLevel = nil,
            rowBaseAlpha = nil,
        }

        local placeholder = CreateFrame("Frame", nil, tabContent, "BackdropTemplate")
        placeholder:SetHeight(ROW_HEIGHT)
        placeholder:SetPoint("LEFT", tabContent, "LEFT", PAD, 0)
        placeholder:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        local placeholderPx = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(placeholder)) or 1
        placeholder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = placeholderPx,
        })
        placeholder:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.08)
        placeholder:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
        placeholder:Hide()

        local function LayoutCurrencyRows(skipRow, insertIndex)
            local nextY = listStartY
            local placedPlaceholder = false
            local rowCount = #currencyRows

            for i = 1, rowCount do
                local row = currencyRows[i]

                if skipRow and insertIndex == i and not placedPlaceholder then
                    placeholder:ClearAllPoints()
                    placeholder:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, nextY)
                    placeholder:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                    placeholder:Show()
                    nextY = nextY - ROW_STEP
                    placedPlaceholder = true
                end

                if row ~= skipRow then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, nextY)
                    row:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                    if dragState.active then
                        row:SetAlpha(0.94)
                    else
                        row:SetAlpha(1)
                    end
                    nextY = nextY - ROW_STEP
                end
            end

            if skipRow and not placedPlaceholder then
                placeholder:ClearAllPoints()
                placeholder:SetPoint("TOPLEFT", tabContent, "TOPLEFT", PAD, nextY)
                placeholder:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                placeholder:Show()
            elseif not skipRow then
                placeholder:Hide()
            end
        end

        local function ComputeDropIndex()
            local rowCount = #currencyRows
            if rowCount <= 1 then
                return 1
            end

            local scale = UIParent:GetEffectiveScale() or 1
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / scale

            -- Map cursor to insertion slot in [1, rowCount + 1].
            local topY = tabContent:GetTop() + listStartY
            local relative = topY - cursorY
            local slot = math.floor((relative + (ROW_STEP * 0.5)) / ROW_STEP) + 1
            if slot < 1 then slot = 1 end
            if slot > (rowCount + 1) then slot = rowCount + 1 end
            return slot
        end

        local function CommitDragOrder()
            if not dragState.fromIndex or not dragState.toIndex then
                return false
            end

            local moving = dt.currencyOrder[dragState.fromIndex]
            if not moving then
                return false
            end

            local targetIndex = dragState.toIndex
            if targetIndex > dragState.fromIndex then
                targetIndex = targetIndex - 1
            end

            if targetIndex < 1 then targetIndex = 1 end
            if targetIndex > #dt.currencyOrder then targetIndex = #dt.currencyOrder end
            if targetIndex == dragState.fromIndex then
                return false
            end

            table.remove(dt.currencyOrder, dragState.fromIndex)
            table.insert(dt.currencyOrder, targetIndex, moving)
            return true
        end

        for idx, currencyId in ipairs(dt.currencyOrder) do
            local row = CreateFrame("Button", nil, tabContent, "BackdropTemplate")
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", PAD, y)
            row:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(row)) or 1
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = px,
            })
            row:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.8)
            row:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
            row:EnableMouse(true)
            row:SetMovable(true)
            row:RegisterForDrag("LeftButton")

            local dragHandleZone = CreateFrame("Frame", nil, row, "BackdropTemplate")
            dragHandleZone:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            dragHandleZone:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
            dragHandleZone:SetWidth(26)
            local handlePx = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(dragHandleZone)) or 1
            dragHandleZone:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = handlePx,
            })
            dragHandleZone:SetBackdropColor(C.bgLight[1], C.bgLight[2], C.bgLight[3], 0.45)
            dragHandleZone:SetBackdropBorderColor(0.22, 0.24, 0.28, 1)

            local dragHint = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            dragHint:SetPoint("CENTER", dragHandleZone, "CENTER", 0, 0)
            dragHint:SetText("::")
            dragHint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

            local displayName = trackedById[currencyId] and trackedById[currencyId].text or ("Unknown (" .. tostring(currencyId) .. ")")
            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("LEFT", dragHandleZone, "RIGHT", 8, 0)
            nameText:SetPoint("RIGHT", -120, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetText(displayName)
            nameText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

            local showCheck
            local function SetShowValue(val, skipRefresh)
                local finalValue = val and true or false
                dt.currencyEnabled[currencyId] = finalValue
                if showCheck then showCheck:SetChecked(finalValue, true) end

                if not skipRefresh then
                    RefreshCurrenciesDatatext()
                    RebuildDatatextTab()
                end
            end

            showCheck = UIKit.CreateAccentCheckbox(row, {
                size = 16,
                checked = dt.currencyEnabled[currencyId] ~= false,
                colors = C,
                onChange = function(checked)
                    SetShowValue(checked)
                end,
            })
            showCheck:SetPoint("RIGHT", -40, 0)

            local showLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            showLabel:SetPoint("LEFT", showCheck, "RIGHT", 4, 0)
            showLabel:SetText("Show")
            showLabel:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)

            local initialShow = dt.currencyEnabled[currencyId] ~= false
            SetShowValue(initialShow, true)

            local function IsCursorOnHandle()
                local scale = UIParent:GetEffectiveScale() or 1
                local cursorX = (GetCursorPosition() or 0) / scale
                local left = dragHandleZone:GetLeft()
                local right = dragHandleZone:GetRight()
                return left and right and cursorX >= left and cursorX <= right
            end

            row:SetScript("OnDragStart", function(self)
                if not IsCursorOnHandle() then
                    return
                end
                dragState.active = true
                dragState.row = self
                dragState.fromIndex = idx
                dragState.toIndex = idx
                dragState.rowBaseStrata = self:GetFrameStrata()
                dragState.rowBaseLevel = self:GetFrameLevel()
                dragState.rowBaseAlpha = self:GetAlpha()
                self:StartMoving()
                self:SetFrameStrata("TOOLTIP")
                self:SetFrameLevel(400)
                self:SetAlpha(0.92)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                dragHandleZone:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                LayoutCurrencyRows(self, dragState.toIndex)

                self:SetScript("OnUpdate", function()
                    if not dragState.active then return end
                    local nextIndex = ComputeDropIndex()
                    if nextIndex ~= dragState.toIndex then
                        dragState.toIndex = nextIndex
                        LayoutCurrencyRows(dragState.row, dragState.toIndex)
                    end
                end)
            end)
            row:SetScript("OnEnter", function(self)
                if dragState.active and dragState.row ~= self then
                    self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                elseif not dragState.active then
                    dragHandleZone:SetBackdropBorderColor(0.30, 0.34, 0.40, 1)
                end
            end)
            row:SetScript("OnLeave", function(self)
                if not (dragState.active and dragState.row == self) then
                    self:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
                end
                if not (dragState.active and dragState.row == self) then
                    dragHandleZone:SetBackdropBorderColor(0.22, 0.24, 0.28, 1)
                end
            end)
            row:SetScript("OnDragStop", function(self)
                if not dragState.active then
                    return
                end
                self:StopMovingOrSizing()
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(dragState.rowBaseAlpha or 1)
                self:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
                dragHandleZone:SetBackdropBorderColor(0.22, 0.24, 0.28, 1)
                self:SetFrameStrata(dragState.rowBaseStrata or "MEDIUM")
                if dragState.rowBaseLevel then
                    self:SetFrameLevel(dragState.rowBaseLevel)
                end
                dragState.active = false

                local changed = CommitDragOrder()
                dragState.row = nil
                dragState.fromIndex = nil
                dragState.toIndex = nil
                dragState.rowBaseStrata = nil
                dragState.rowBaseLevel = nil
                dragState.rowBaseAlpha = nil
                placeholder:Hide()
                LayoutCurrencyRows(nil, nil)

                if changed then
                    RefreshCurrenciesDatatext()
                    RebuildDatatextTab()
                end
            end)

            currencyRows[#currencyRows + 1] = row
            y = y - ROW_STEP
        end

        LayoutCurrencyRows(nil, nil)

        if #dt.currencyOrder == 0 then
            local emptyNote = GUI:CreateLabel(tabContent, "No tracked currencies yet. Track currencies in the Currency Panel and this list will update immediately.", 11, C.textMuted)
            emptyNote:SetPoint("TOPLEFT", PAD, y + 6)
            emptyNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            emptyNote:SetJustifyH("LEFT")
            y = y - 20
        end

        y = y - 10

        -- SECTION 6: Custom Movable Datapanels
        local customPanelsHeader = GUI:CreateSectionHeader(tabContent, "Custom Movable Panels")
        customPanelsHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - customPanelsHeader.gap

        local panelsNote = GUI:CreateLabel(tabContent, "Create additional datatext panels that can be freely positioned anywhere on screen.", 11, C.textMuted)
        panelsNote:SetPoint("TOPLEFT", PAD, y)
        panelsNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        panelsNote:SetJustifyH("LEFT")
        y = y - 28

        local panelsWarning = GUI:CreateLabel(tabContent, "Note: Panels will only appear if at least one slot has a datatext assigned.", 11, C.textMuted)
        panelsWarning:SetPoint("TOPLEFT", PAD, y)
        panelsWarning:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        panelsWarning:SetJustifyH("LEFT")
        y = y - 28

        -- Ensure quiDatatexts.panels exists
        if not db.quiDatatexts then
            db.quiDatatexts = {panels = {}}
        end
        if not db.quiDatatexts.panels then
            db.quiDatatexts.panels = {}
        end

        -- List existing panels
        local panels = db.quiDatatexts.panels

        if #panels > 0 then
            for i, panelConfig in ipairs(panels) do
                local panelFrame = CreateFrame("Frame", nil, tabContent, "BackdropTemplate")
                panelFrame:SetHeight(60)
                panelFrame:SetPoint("TOPLEFT", PAD, y)
                panelFrame:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                local px = (QUICore and QUICore.GetPixelSize and QUICore:GetPixelSize(panelFrame)) or 1
                panelFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = px,
                })
                panelFrame:SetBackdropColor(C.bgLight[1], C.bgLight[2], C.bgLight[3], 0.8)
                panelFrame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

                -- Panel name
                local nameLabel = panelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                nameLabel:SetPoint("TOPLEFT", 10, -10)
                nameLabel:SetText(string.format("Panel %d: %s", i, panelConfig.name or ("Panel " .. i)))
                nameLabel:SetTextColor(C.accentLight[1], C.accentLight[2], C.accentLight[3], 1)

                -- Status (simplified - just slot count)
                local statusLabel = panelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                statusLabel:SetPoint("TOPLEFT", 10, -30)
                statusLabel:SetText(string.format("%d slots", panelConfig.numSlots or 3))
                statusLabel:SetTextColor(0.7, 0.7, 0.7, 1)

                -- Edit button - opens configuration popup
                local editBtn = GUI:CreateButton(panelFrame, "Edit", 60, 22, function()
                    ShowPanelEditPopup(panelConfig, i)
                end)
                editBtn:SetPoint("RIGHT", -140, 0)

                -- Enable toggle
                local enableCheck = GUI:CreateCheckbox(panelFrame, "Enabled", "enabled", panelConfig, function()
                    if QUICore and QUICore.Datapanels then
                        QUICore.Datapanels:UpdatePanel(panelConfig.id)
                    end
                end)
                enableCheck:SetPoint("RIGHT", -80, 0)

                -- Delete button (with confirmation)
                local delBtn = GUI:CreateButton(panelFrame, "Delete", 60, 22, function()
                    GUI:ShowConfirmation({
                        title = "Delete Panel?",
                        message = "Delete '" .. (panelConfig.name or ("Panel " .. i)) .. "'?",
                        warningText = "This cannot be undone.",
                        acceptText = "Delete",
                        cancelText = "Cancel",
                        isDestructive = true,
                        onAccept = function()
                            -- Close edit popup if open for this panel
                            if editPopup and editPopup:IsShown() then
                                editPopup:Hide()
                            end
                            table.remove(db.quiDatatexts.panels, i)
                            if QUICore and QUICore.Datapanels then
                                QUICore.Datapanels:DeletePanel(panelConfig.id)
                                QUICore.Datapanels:RefreshAll()
                            end
                            RebuildDatatextTab()
                        end,
                    })
                end)
                delBtn:SetPoint("RIGHT", -10, 0)

                y = y - 70
            end
        else
            local noPanelsLabel = GUI:CreateLabel(tabContent, "No custom panels created yet. Click 'Add Panel' below to get started.", 11, C.textDim)
            noPanelsLabel:SetPoint("TOPLEFT", PAD, y)
            y = y - 30
        end

        -- Add Panel button
        local addPanelBtn = GUI:CreateButton(tabContent, "Add Panel", 120, 28, function()
            local newID = "panel" .. (time() % 100000)
            local newPanel = {
                id = newID,
                name = "Panel " .. (#panels + 1),
                enabled = true,
                locked = false,
                numSlots = 3,
                width = 300,
                height = 22,
                bgOpacity = 50,
                borderSize = 2,
                borderColor = {0, 0, 0, 1},
                fontSize = 12,
                position = {"CENTER", "CENTER", 0, 300},
                slots = {},
                slotSettings = {},
            }
            table.insert(db.quiDatatexts.panels, newPanel)
            RefreshDatapanels()
            RebuildDatatextTab()
        end)
        addPanelBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 40
    end

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_MinimapOptions = {
    BuildMinimapTab = BuildMinimapTab,
    BuildDatatextTab = BuildDatatextTab,
}
