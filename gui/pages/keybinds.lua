--[[
    QUI Options - CDM Keybind & Rotation Page
    CreateCDKeybindsPage for CDM Keybind & Rotation tab
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function CreateCDKeybindsPage(parent)
    local scroll, content = Shared.CreateScrollableContent(parent)
    local db = Shared.GetDB()
    local y = -15
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local ROW_GAP = Shared.ROW_GAP

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 8, tabName = "CDM Keybind & Rotation"})

    -- Refresh function for keybinds
    local function RefreshKeybinds()
        if _G.QUI_RefreshKeybinds then
            _G.QUI_RefreshKeybinds()
        end
    end

    -- Refresh function for rotation helper
    local function RefreshRotationHelper()
        if _G.QUI_RefreshRotationHelper then
            _G.QUI_RefreshRotationHelper()
        end
    end

    -- Info text at top
    local info = GUI:CreateLabel(content, "Keybind display - shows ability keybinds on cooldown icons", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PADDING, y)
    info:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
    info:SetJustifyH("LEFT")
    y = y - 28

    if db and db.viewers then
        local essentialViewer = db.viewers.EssentialCooldownViewer
        local utilityViewer = db.viewers.UtilityCooldownViewer

        -- =====================================================
        -- ESSENTIAL KEYBIND DISPLAY
        -- =====================================================
        local essentialHeader = GUI:CreateSectionHeader(content, "ESSENTIAL KEYBIND DISPLAY")
        essentialHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - essentialHeader.gap

        local essentialShowCheck = GUI:CreateFormCheckbox(content, "Show Keybinds", "showKeybinds", essentialViewer, RefreshKeybinds)
        essentialShowCheck:SetPoint("TOPLEFT", PADDING, y)
        essentialShowCheck:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local anchorOptions = {
            { value = "TOPLEFT", text = "Top Left" },
            { value = "TOPRIGHT", text = "Top Right" },
            { value = "BOTTOMLEFT", text = "Bottom Left" },
            { value = "BOTTOMRIGHT", text = "Bottom Right" },
            { value = "CENTER", text = "Center" },
        }
        local essentialAnchor = GUI:CreateFormDropdown(content, "Keybind Anchor", anchorOptions, "keybindAnchor", essentialViewer, RefreshKeybinds)
        essentialAnchor:SetPoint("TOPLEFT", PADDING, y)
        essentialAnchor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local essentialSizeSlider = GUI:CreateFormSlider(content, "Keybind Text Size", 6, 18, 1, "keybindTextSize", essentialViewer, RefreshKeybinds)
        essentialSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        essentialSizeSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local essentialColorPicker = GUI:CreateFormColorPicker(content, "Keybind Text Color", "keybindTextColor", essentialViewer, RefreshKeybinds)
        essentialColorPicker:SetPoint("TOPLEFT", PADDING, y)
        essentialColorPicker:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local essentialOffsetXSlider = GUI:CreateFormSlider(content, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", essentialViewer, RefreshKeybinds)
        essentialOffsetXSlider:SetPoint("TOPLEFT", PADDING, y)
        essentialOffsetXSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local essentialOffsetYSlider = GUI:CreateFormSlider(content, "Vertical Offset", -20, 20, 1, "keybindOffsetY", essentialViewer, RefreshKeybinds)
        essentialOffsetYSlider:SetPoint("TOPLEFT", PADDING, y)
        essentialOffsetYSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- UTILITY KEYBIND DISPLAY
        -- =====================================================
        y = y - 10 -- Section spacing
        local utilityHeader = GUI:CreateSectionHeader(content, "UTILITY KEYBIND DISPLAY")
        utilityHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - utilityHeader.gap

        local utilityShowCheck = GUI:CreateFormCheckbox(content, "Show Keybinds", "showKeybinds", utilityViewer, RefreshKeybinds)
        utilityShowCheck:SetPoint("TOPLEFT", PADDING, y)
        utilityShowCheck:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilityAnchor = GUI:CreateFormDropdown(content, "Keybind Anchor", anchorOptions, "keybindAnchor", utilityViewer, RefreshKeybinds)
        utilityAnchor:SetPoint("TOPLEFT", PADDING, y)
        utilityAnchor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilitySizeSlider = GUI:CreateFormSlider(content, "Keybind Text Size", 6, 18, 1, "keybindTextSize", utilityViewer, RefreshKeybinds)
        utilitySizeSlider:SetPoint("TOPLEFT", PADDING, y)
        utilitySizeSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilityColorPicker = GUI:CreateFormColorPicker(content, "Keybind Text Color", "keybindTextColor", utilityViewer, RefreshKeybinds)
        utilityColorPicker:SetPoint("TOPLEFT", PADDING, y)
        utilityColorPicker:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilityOffsetXSlider = GUI:CreateFormSlider(content, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", utilityViewer, RefreshKeybinds)
        utilityOffsetXSlider:SetPoint("TOPLEFT", PADDING, y)
        utilityOffsetXSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilityOffsetYSlider = GUI:CreateFormSlider(content, "Vertical Offset", -20, 20, 1, "keybindOffsetY", utilityViewer, RefreshKeybinds)
        utilityOffsetYSlider:SetPoint("TOPLEFT", PADDING, y)
        utilityOffsetYSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- CUSTOM TRACKER KEYBIND DISPLAYS
        -- =====================================================
        y = y - 10 -- Section spacing
        local ctKeybindHeader = GUI:CreateSectionHeader(content, "CUSTOM TRACKER KEYBIND DISPLAYS")
        ctKeybindHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - ctKeybindHeader.gap

        local ctKeybindInfo = GUI:CreateLabel(content, "Shows keybinds on Custom Item/Spell bar icons. Settings apply globally to all custom tracker bars.", 11, C.textMuted)
        ctKeybindInfo:SetPoint("TOPLEFT", PADDING, y)
        ctKeybindInfo:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
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
            local ctShowCheck = GUI:CreateFormCheckbox(content, "Show Keybinds", "showKeybinds", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctShowCheck:SetPoint("TOPLEFT", PADDING, y)
            ctShowCheck:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local ctSizeSlider = GUI:CreateFormSlider(content, "Keybind Text Size", 6, 18, 1, "keybindTextSize", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctSizeSlider:SetPoint("TOPLEFT", PADDING, y)
            ctSizeSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local ctColorPicker = GUI:CreateFormColorPicker(content, "Keybind Text Color", "keybindTextColor", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctColorPicker:SetPoint("TOPLEFT", PADDING, y)
            ctColorPicker:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local ctOffsetXSlider = GUI:CreateFormSlider(content, "Horizontal Offset", -20, 20, 1, "keybindOffsetX", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctOffsetXSlider:SetPoint("TOPLEFT", PADDING, y)
            ctOffsetXSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local ctOffsetYSlider = GUI:CreateFormSlider(content, "Vertical Offset", -20, 20, 1, "keybindOffsetY", ctKeybindDB, RefreshCustomTrackerKeybinds)
            ctOffsetYSlider:SetPoint("TOPLEFT", PADDING, y)
            ctOffsetYSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW
        end

        -- =====================================================
        -- ROTATION HELPER OVERLAY
        -- =====================================================
        y = y - 10 -- Section spacing
        local rotationHeader = GUI:CreateSectionHeader(content, "ROTATION HELPER OVERLAY")
        rotationHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - rotationHeader.gap

        local rotationInfo = GUI:CreateLabel(content, "Shows a border on the CDM icon recommended by Blizzard's Assisted Combat (Starter Build). Requires 'Starter Build' to be enabled in Game Menu > Options > Gameplay > Combat.", 11, C.textMuted)
        rotationInfo:SetPoint("TOPLEFT", PADDING, y)
        rotationInfo:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        rotationInfo:SetJustifyH("LEFT")
        y = y - 38

        local essentialRotationCheck = GUI:CreateFormCheckbox(content, "Show on Essential CDM", "showRotationHelper", essentialViewer, RefreshRotationHelper)
        essentialRotationCheck:SetPoint("TOPLEFT", PADDING, y)
        essentialRotationCheck:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilityRotationCheck = GUI:CreateFormCheckbox(content, "Show on Utility CDM", "showRotationHelper", utilityViewer, RefreshRotationHelper)
        utilityRotationCheck:SetPoint("TOPLEFT", PADDING, y)
        utilityRotationCheck:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local essentialRotationColor = GUI:CreateFormColorPicker(content, "Essential Border Color", "rotationHelperColor", essentialViewer, RefreshRotationHelper)
        essentialRotationColor:SetPoint("TOPLEFT", PADDING, y)
        essentialRotationColor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilityRotationColor = GUI:CreateFormColorPicker(content, "Utility Border Color", "rotationHelperColor", utilityViewer, RefreshRotationHelper)
        utilityRotationColor:SetPoint("TOPLEFT", PADDING, y)
        utilityRotationColor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local essentialThicknessSlider = GUI:CreateFormSlider(content, "Essential Border Thickness", 1, 6, 1, "rotationHelperThickness", essentialViewer, RefreshRotationHelper)
        essentialThicknessSlider:SetPoint("TOPLEFT", PADDING, y)
        essentialThicknessSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local utilityThicknessSlider = GUI:CreateFormSlider(content, "Utility Border Thickness", 1, 6, 1, "rotationHelperThickness", utilityViewer, RefreshRotationHelper)
        utilityThicknessSlider:SetPoint("TOPLEFT", PADDING, y)
        utilityThicknessSlider:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- ROTATION ASSIST ICON
        -- =====================================================
        y = y - 10 -- Extra spacing
        local raiHeader = GUI:CreateSectionHeader(content, "ROTATION ASSIST ICON")
        raiHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - raiHeader.gap

        -- Get rotation assist icon DB
        local raiDB = db and db.rotationAssistIcon

        -- Refresh function
        local function RefreshRAI()
            if _G.QUI_RefreshRotationAssistIcon then
                _G.QUI_RefreshRotationAssistIcon()
            end
        end

        if raiDB then
            -- Info text
            local raiInfo = GUI:CreateLabel(content, "Displays a standalone movable icon showing Blizzard's next recommended ability.", 11, C.textMuted)
            raiInfo:SetPoint("TOPLEFT", PADDING, y)
            y = y - 18

            local raiInfo2 = GUI:CreateLabel(content, "Requires 'Starter Build' to be enabled in Game Menu > Options > Gameplay > Combat.", 11, C.textMuted)
            raiInfo2:SetPoint("TOPLEFT", PADDING, y)
            y = y - 30

            -- Form rows
            local raiEnable = GUI:CreateFormCheckbox(content, "Enable", "enabled", raiDB, RefreshRAI)
            raiEnable:SetPoint("TOPLEFT", PADDING, y)
            raiEnable:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiLock = GUI:CreateFormCheckbox(content, "Lock Position", "isLocked", raiDB, RefreshRAI)
            raiLock:SetPoint("TOPLEFT", PADDING, y)
            raiLock:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiSwipe = GUI:CreateFormCheckbox(content, "Cooldown Swipe", "cooldownSwipeEnabled", raiDB, RefreshRAI)
            raiSwipe:SetPoint("TOPLEFT", PADDING, y)
            raiSwipe:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local visibilityOptions = {
                { value = "always", text = "Always" },
                { value = "combat", text = "In Combat" },
                { value = "hostile", text = "Hostile Target" },
            }
            local raiVisibility = GUI:CreateFormDropdown(content, "Visibility", visibilityOptions, "visibility", raiDB, RefreshRAI)
            raiVisibility:SetPoint("TOPLEFT", PADDING, y)
            raiVisibility:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local strataOptions = {
                { value = "LOW", text = "Low" },
                { value = "MEDIUM", text = "Medium" },
                { value = "HIGH", text = "High" },
                { value = "DIALOG", text = "Dialog" },
            }
            local raiStrata = GUI:CreateFormDropdown(content, "Frame Strata", strataOptions, "frameStrata", raiDB, RefreshRAI)
            raiStrata:SetPoint("TOPLEFT", PADDING, y)
            raiStrata:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiSize = GUI:CreateFormSlider(content, "Icon Size", 16, 400, 1, "iconSize", raiDB, RefreshRAI)
            raiSize:SetPoint("TOPLEFT", PADDING, y)
            raiSize:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiBorderWidth = GUI:CreateFormSlider(content, "Border Size", 0, 15, 1, "borderThickness", raiDB, RefreshRAI)
            raiBorderWidth:SetPoint("TOPLEFT", PADDING, y)
            raiBorderWidth:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiBorderColor = GUI:CreateFormColorPicker(content, "Border Color", "borderColor", raiDB, RefreshRAI)
            raiBorderColor:SetPoint("TOPLEFT", PADDING, y)
            raiBorderColor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiKeybindShow = GUI:CreateFormCheckbox(content, "Show Keybind", "showKeybind", raiDB, RefreshRAI)
            raiKeybindShow:SetPoint("TOPLEFT", PADDING, y)
            raiKeybindShow:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiFontColor = GUI:CreateFormColorPicker(content, "Keybind Color", "keybindColor", raiDB, RefreshRAI)
            raiFontColor:SetPoint("TOPLEFT", PADDING, y)
            raiFontColor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiAnchorOptions = {
                { value = "TOPLEFT", text = "Top Left" },
                { value = "TOPRIGHT", text = "Top Right" },
                { value = "BOTTOMLEFT", text = "Bottom Left" },
                { value = "BOTTOMRIGHT", text = "Bottom Right" },
                { value = "CENTER", text = "Center" },
            }
            local raiAnchor = GUI:CreateFormDropdown(content, "Keybind Anchor", raiAnchorOptions, "keybindAnchor", raiDB, RefreshRAI)
            raiAnchor:SetPoint("TOPLEFT", PADDING, y)
            raiAnchor:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiFontSize = GUI:CreateFormSlider(content, "Keybind Size", 6, 48, 1, "keybindSize", raiDB, RefreshRAI)
            raiFontSize:SetPoint("TOPLEFT", PADDING, y)
            raiFontSize:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiOffsetX = GUI:CreateFormSlider(content, "Keybind X Offset", -50, 50, 1, "keybindOffsetX", raiDB, RefreshRAI)
            raiOffsetX:SetPoint("TOPLEFT", PADDING, y)
            raiOffsetX:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW

            local raiOffsetY = GUI:CreateFormSlider(content, "Keybind Y Offset", -50, 50, 1, "keybindOffsetY", raiDB, RefreshRAI)
            raiOffsetY:SetPoint("TOPLEFT", PADDING, y)
            raiOffsetY:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW
        else
            local noRAILabel = GUI:CreateLabel(content, "Rotation Assist Icon settings not available - database not loaded", 12, C.textMuted)
            noRAILabel:SetPoint("TOPLEFT", PADDING, y)
            y = y - ROW_GAP
        end
    else
        y = y - 10
        local noDataLabel = GUI:CreateLabel(content, "Keybind settings not available - database not loaded", 12, C.textMuted)
        noDataLabel:SetPoint("TOPLEFT", PADDING, y)
    end

    content:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_KeybindsOptions = {
    CreateCDKeybindsPage = CreateCDKeybindsPage
}
