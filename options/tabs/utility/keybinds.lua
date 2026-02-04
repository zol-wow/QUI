--[[
    QUI Options - CDM Keybind & Rotation Sub-Tab
    BuildKeybindsTab for Cooldown Manager > Keybinds sub-tab
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local ANCHOR_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "CENTER", text = "Center" },
}

local function BuildKeybindsTab(tabContent)
    local db = Shared.GetDB()
    local y = -10
    local FORM_ROW = 32
    local PAD = 10

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 7, subTabName = "Keybinds"})

    -- Refresh function for keybinds
    local function RefreshKeybinds()
        if _G.QUI_RefreshKeybinds then
            _G.QUI_RefreshKeybinds()
        end
    end

    -- Info text at top
    local info = GUI:CreateLabel(tabContent, "Keybind display - shows ability keybinds on cooldown icons", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    if db and db.viewers then
        local essentialViewer = db.viewers.EssentialCooldownViewer
        local utilityViewer = db.viewers.UtilityCooldownViewer

        -- =====================================================
        -- ESSENTIAL KEYBIND DISPLAY
        -- =====================================================
        local essentialHeader = GUI:CreateSectionHeader(tabContent, "ESSENTIAL KEYBIND DISPLAY")
        essentialHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - essentialHeader.gap

        local essentialShowCheck = GUI:CreateFormCheckbox(tabContent, "Show Keybinds", "showKeybinds", essentialViewer, RefreshKeybinds)
        essentialShowCheck:SetPoint("TOPLEFT", PAD, y)
        essentialShowCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialAnchor = GUI:CreateFormDropdown(tabContent, "Keybind Anchor", ANCHOR_OPTIONS, "keybindAnchor", essentialViewer, RefreshKeybinds)
        essentialAnchor:SetPoint("TOPLEFT", PAD, y)
        essentialAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialSizeSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Size", 6, 18, 1, "keybindTextSize", essentialViewer, RefreshKeybinds)
        essentialSizeSlider:SetPoint("TOPLEFT", PAD, y)
        essentialSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialColorPicker = GUI:CreateFormColorPicker(tabContent, "Keybind Text Color", "keybindTextColor", essentialViewer, RefreshKeybinds)
        essentialColorPicker:SetPoint("TOPLEFT", PAD, y)
        essentialColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialOffsetXSlider = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", essentialViewer, RefreshKeybinds)
        essentialOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        essentialOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialOffsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -20, 20, 1, "keybindOffsetY", essentialViewer, RefreshKeybinds)
        essentialOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        essentialOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- UTILITY KEYBIND DISPLAY
        -- =====================================================
        y = y - 10 -- Section spacing
        local utilityHeader = GUI:CreateSectionHeader(tabContent, "UTILITY KEYBIND DISPLAY")
        utilityHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - utilityHeader.gap

        local utilityShowCheck = GUI:CreateFormCheckbox(tabContent, "Show Keybinds", "showKeybinds", utilityViewer, RefreshKeybinds)
        utilityShowCheck:SetPoint("TOPLEFT", PAD, y)
        utilityShowCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityAnchor = GUI:CreateFormDropdown(tabContent, "Keybind Anchor", ANCHOR_OPTIONS, "keybindAnchor", utilityViewer, RefreshKeybinds)
        utilityAnchor:SetPoint("TOPLEFT", PAD, y)
        utilityAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilitySizeSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Size", 6, 18, 1, "keybindTextSize", utilityViewer, RefreshKeybinds)
        utilitySizeSlider:SetPoint("TOPLEFT", PAD, y)
        utilitySizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityColorPicker = GUI:CreateFormColorPicker(tabContent, "Keybind Text Color", "keybindTextColor", utilityViewer, RefreshKeybinds)
        utilityColorPicker:SetPoint("TOPLEFT", PAD, y)
        utilityColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityOffsetXSlider = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", utilityViewer, RefreshKeybinds)
        utilityOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        utilityOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityOffsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -20, 20, 1, "keybindOffsetY", utilityViewer, RefreshKeybinds)
        utilityOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        utilityOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- CUSTOM TRACKER KEYBIND DISPLAYS
        -- =====================================================
        y = y - 10 -- Section spacing
        local ctKeybindHeader = GUI:CreateSectionHeader(tabContent, "CUSTOM TRACKER KEYBIND DISPLAYS")
        ctKeybindHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - ctKeybindHeader.gap

        local ctKeybindInfo = GUI:CreateLabel(tabContent, "Shows keybinds on Custom Item/Spell bar icons. Settings apply globally to all custom tracker bars.", 11, C.textMuted)
        ctKeybindInfo:SetPoint("TOPLEFT", PAD, y)
        ctKeybindInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        ctKeybindInfo:SetJustifyH("LEFT")
        y = y - 28

        -- Get custom tracker keybind settings from DB
        local ctKeybindDB = db and db.customTrackers and db.customTrackers.keybinds
        if not ctKeybindDB and db and db.customTrackers then
            -- Initialize defaults if missing
            db.customTrackers.keybinds = {
                showKeybinds = false,
                keybindTextSize = 10,
                keybindTextColor = { 1, 0.82, 0, 1 },
                keybindOffsetX = 2,
                keybindOffsetY = -2,
            }
            ctKeybindDB = db.customTrackers.keybinds
        end

        -- Refresh function for custom tracker keybinds
        local function RefreshCustomTrackerKeybinds()
            if _G.QUI_RefreshCustomTrackerKeybinds then
                _G.QUI_RefreshCustomTrackerKeybinds()
            end
        end

        if ctKeybindDB then
            local ctShowCheck = GUI:CreateFormCheckbox(tabContent, "Show Keybinds", "showKeybinds", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctShowCheck:SetPoint("TOPLEFT", PAD, y)
            ctShowCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctSizeSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Size", 6, 18, 1, "keybindTextSize", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctSizeSlider:SetPoint("TOPLEFT", PAD, y)
            ctSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctColorPicker = GUI:CreateFormColorPicker(tabContent, "Keybind Text Color", "keybindTextColor", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctColorPicker:SetPoint("TOPLEFT", PAD, y)
            ctColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctOffsetXSlider = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
            ctOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local ctOffsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -20, 20, 1, "keybindOffsetY", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
            ctOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end
    else
        y = y - 10
        local noDataLabel = GUI:CreateLabel(tabContent, "Keybind settings not available - database not loaded", 12, C.textMuted)
        noDataLabel:SetPoint("TOPLEFT", PAD, y)
    end

    tabContent:SetHeight(math.abs(y) + 60)
end

local function BuildRotationAssistTab(tabContent)
    local db = Shared.GetDB()
    local y = -10
    local FORM_ROW = 32
    local PAD = 10

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "Cooldown Manager", subTabIndex = 8, subTabName = "Rotation Assist"})

    -- Refresh function for rotation helper
    local function RefreshRotationHelper()
        if _G.QUI_RefreshRotationHelper then
            _G.QUI_RefreshRotationHelper()
        end
    end

    if db and db.viewers then
        local essentialViewer = db.viewers.EssentialCooldownViewer
        local utilityViewer = db.viewers.UtilityCooldownViewer

        -- =====================================================
        -- ROTATION HELPER OVERLAY
        -- =====================================================
        local rotationHeader = GUI:CreateSectionHeader(tabContent, "ROTATION HELPER OVERLAY")
        rotationHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - rotationHeader.gap

        local rotationInfo = GUI:CreateLabel(tabContent, "Shows a border on the CDM icon recommended by Blizzard's Assisted Combat (Starter Build). Requires 'Starter Build' to be enabled in Game Menu > Options > Gameplay > Combat.", 11, C.textMuted)
        rotationInfo:SetPoint("TOPLEFT", PAD, y)
        rotationInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        rotationInfo:SetJustifyH("LEFT")
        y = y - 38

        local essentialRotationCheck = GUI:CreateFormCheckbox(tabContent, "Show on Essential CDM", "showRotationHelper", essentialViewer, RefreshRotationHelper)
        essentialRotationCheck:SetPoint("TOPLEFT", PAD, y)
        essentialRotationCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityRotationCheck = GUI:CreateFormCheckbox(tabContent, "Show on Utility CDM", "showRotationHelper", utilityViewer, RefreshRotationHelper)
        utilityRotationCheck:SetPoint("TOPLEFT", PAD, y)
        utilityRotationCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialRotationColor = GUI:CreateFormColorPicker(tabContent, "Essential Border Color", "rotationHelperColor", essentialViewer, RefreshRotationHelper)
        essentialRotationColor:SetPoint("TOPLEFT", PAD, y)
        essentialRotationColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityRotationColor = GUI:CreateFormColorPicker(tabContent, "Utility Border Color", "rotationHelperColor", utilityViewer, RefreshRotationHelper)
        utilityRotationColor:SetPoint("TOPLEFT", PAD, y)
        utilityRotationColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local essentialThicknessSlider = GUI:CreateFormSlider(tabContent, "Essential Border Thickness", 1, 6, 1, "rotationHelperThickness", essentialViewer, RefreshRotationHelper)
        essentialThicknessSlider:SetPoint("TOPLEFT", PAD, y)
        essentialThicknessSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local utilityThicknessSlider = GUI:CreateFormSlider(tabContent, "Utility Border Thickness", 1, 6, 1, "rotationHelperThickness", utilityViewer, RefreshRotationHelper)
        utilityThicknessSlider:SetPoint("TOPLEFT", PAD, y)
        utilityThicknessSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- ROTATION ASSIST ICON
        -- =====================================================
        y = y - 10 -- Extra spacing
        local raiHeader = GUI:CreateSectionHeader(tabContent, "ROTATION ASSIST ICON")
        raiHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - raiHeader.gap

        -- Get rotation assist icon DB
        local raiDB = db and db.rotationAssistIcon
        if not raiDB and db then
            -- Initialize defaults if missing
            db.rotationAssistIcon = {
                enabled = false,
                isLocked = true,
                iconSize = 56,
                visibility = "always",  -- "always", "combat", "hostile"
                frameStrata = "MEDIUM",
                -- Border
                showBorder = true,
                borderThickness = 2,
                borderColor = { 0, 0, 0, 1 },
                -- Cooldown
                cooldownSwipeEnabled = true,
                -- Keybind
                showKeybind = true,
                keybindFont = nil,  -- nil = use general.font
                keybindSize = 13,
                keybindColor = { 1, 1, 1, 1 },
                keybindOutline = true,
                keybindAnchor = "BOTTOMRIGHT",
                keybindOffsetX = -2,
                keybindOffsetY = 2,
                -- Position (anchored to CENTER of screen)
                positionX = 0,
                positionY = -180,
            }
            raiDB = db.rotationAssistIcon
        end

        -- Refresh function
        local function RefreshRAI()
            if _G.QUI_RefreshRotationAssistIcon then
                _G.QUI_RefreshRotationAssistIcon()
            end
        end

        -- Info text
        local raiInfo = GUI:CreateLabel(tabContent, "Displays a standalone movable icon showing Blizzard's next recommended ability.", 11, C.textMuted)
        raiInfo:SetPoint("TOPLEFT", PAD, y)
        y = y - 18

        local raiInfo2 = GUI:CreateLabel(tabContent, "Requires 'Starter Build' to be enabled in Game Menu > Options > Gameplay > Combat.", 11, C.textMuted)
        raiInfo2:SetPoint("TOPLEFT", PAD, y)
        y = y - 30

        -- Form rows
        local raiEnable = GUI:CreateFormCheckbox(tabContent, "Enable", "enabled", raiDB, RefreshRAI)
        raiEnable:SetPoint("TOPLEFT", PAD, y)
        raiEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiLock = GUI:CreateFormCheckbox(tabContent, "Lock Position", "isLocked", raiDB, RefreshRAI)
        raiLock:SetPoint("TOPLEFT", PAD, y)
        raiLock:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiSwipe = GUI:CreateFormCheckbox(tabContent, "Cooldown Swipe", "cooldownSwipeEnabled", raiDB, RefreshRAI)
        raiSwipe:SetPoint("TOPLEFT", PAD, y)
        raiSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local visibilityOptions = {
            { value = "always", text = "Always" },
            { value = "combat", text = "In Combat" },
            { value = "hostile", text = "Hostile Target" },
        }
        local raiVisibility = GUI:CreateFormDropdown(tabContent, "Visibility", visibilityOptions, "visibility", raiDB, RefreshRAI)
        raiVisibility:SetPoint("TOPLEFT", PAD, y)
        raiVisibility:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local strataOptions = {
            { value = "LOW", text = "Low" },
            { value = "MEDIUM", text = "Medium" },
            { value = "HIGH", text = "High" },
            { value = "DIALOG", text = "Dialog" },
        }
        local raiStrata = GUI:CreateFormDropdown(tabContent, "Frame Strata", strataOptions, "frameStrata", raiDB, RefreshRAI)
        raiStrata:SetPoint("TOPLEFT", PAD, y)
        raiStrata:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiSize = GUI:CreateFormSlider(tabContent, "Icon Size", 16, 400, 1, "iconSize", raiDB, RefreshRAI)
        raiSize:SetPoint("TOPLEFT", PAD, y)
        raiSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiBorderWidth = GUI:CreateFormSlider(tabContent, "Border Size", 0, 15, 1, "borderThickness", raiDB, RefreshRAI)
        raiBorderWidth:SetPoint("TOPLEFT", PAD, y)
        raiBorderWidth:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiBorderColor = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColor", raiDB, RefreshRAI)
        raiBorderColor:SetPoint("TOPLEFT", PAD, y)
        raiBorderColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiKeybindShow = GUI:CreateFormCheckbox(tabContent, "Show Keybind", "showKeybind", raiDB, RefreshRAI)
        raiKeybindShow:SetPoint("TOPLEFT", PAD, y)
        raiKeybindShow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiFontColor = GUI:CreateFormColorPicker(tabContent, "Keybind Color", "keybindColor", raiDB, RefreshRAI)
        raiFontColor:SetPoint("TOPLEFT", PAD, y)
        raiFontColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiAnchor = GUI:CreateFormDropdown(tabContent, "Keybind Anchor", ANCHOR_OPTIONS, "keybindAnchor", raiDB, RefreshRAI)
        raiAnchor:SetPoint("TOPLEFT", PAD, y)
        raiAnchor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiFontSize = GUI:CreateFormSlider(tabContent, "Keybind Size", 6, 48, 1, "keybindSize", raiDB, RefreshRAI)
        raiFontSize:SetPoint("TOPLEFT", PAD, y)
        raiFontSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiOffsetX = GUI:CreateFormSlider(tabContent, "Keybind X Offset", -50, 50, 1, "keybindOffsetX", raiDB, RefreshRAI)
        raiOffsetX:SetPoint("TOPLEFT", PAD, y)
        raiOffsetX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local raiOffsetY = GUI:CreateFormSlider(tabContent, "Keybind Y Offset", -50, 50, 1, "keybindOffsetY", raiDB, RefreshRAI)
        raiOffsetY:SetPoint("TOPLEFT", PAD, y)
        raiOffsetY:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
    else
        y = y - 10
        local noDataLabel = GUI:CreateLabel(tabContent, "Rotation assist settings not available - database not loaded", 12, C.textMuted)
        noDataLabel:SetPoint("TOPLEFT", PAD, y)
    end

    tabContent:SetHeight(math.abs(y) + 60)
end

-- Export
ns.QUI_KeybindsOptions = {
    BuildKeybindsTab = BuildKeybindsTab,
    BuildRotationAssistTab = BuildRotationAssistTab,
}
