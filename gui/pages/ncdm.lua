local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

-- Local references for shared infrastructure
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList

--------------------------------------------------------------------------------
-- Refresh callback for NCDM changes
--------------------------------------------------------------------------------
local function RefreshNCDM()
    if _G.QUI_RefreshNCDM then
        _G.QUI_RefreshNCDM()
    end
end

--------------------------------------------------------------------------------
-- Initialize NCDM defaults for existing profiles that don't have them
--------------------------------------------------------------------------------
local function EnsureNCDMDefaults(db)
    if not db then return end

    -- Default row settings
    local defaultRow = {
        iconCount = 4,
        iconSize = 50,
        borderSize = 2,
        shape = "square",
        zoom = 0,
        padding = -8,
        yOffset = 0,
        opacity = 1.0,
    }

    -- Ensure ncdm table exists
    if not db.ncdm then
        db.ncdm = {}
    end

    -- Ensure essential exists
    if not db.ncdm.essential then
        db.ncdm.essential = { enabled = true }
    end
    for i = 1, 3 do
        local rowKey = "row" .. i
        if not db.ncdm.essential[rowKey] then
            db.ncdm.essential[rowKey] = {}
            for k, v in pairs(defaultRow) do
                db.ncdm.essential[rowKey][k] = v
            end
            -- Row 3 disabled by default
            if i == 3 then
                db.ncdm.essential[rowKey].iconCount = 0
            end
        end
    end

    -- Ensure utility exists
    if not db.ncdm.utility then
        db.ncdm.utility = { enabled = true }
    end
    for i = 1, 3 do
        local rowKey = "row" .. i
        if not db.ncdm.utility[rowKey] then
            db.ncdm.utility[rowKey] = {}
            for k, v in pairs(defaultRow) do
                db.ncdm.utility[rowKey][k] = v
            end
            db.ncdm.utility[rowKey].iconSize = 42
            db.ncdm.utility[rowKey].iconCount = 6
            db.ncdm.utility[rowKey].zoom = 0.08
            -- Row 3 disabled by default
            if i == 3 then
                db.ncdm.utility[rowKey].iconCount = 0
            end
        end
    end

    -- Ensure buff exists
    if not db.ncdm.buff then
        db.ncdm.buff = { enabled = false }
    end
end

--------------------------------------------------------------------------------
-- CreateCDMSetupPage - Main page builder for CDM Setup & Class Bars tab
--------------------------------------------------------------------------------
local function CreateCDMSetupPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local db = GetDB()

    -- Ensure NCDM tables exist for this profile
    EnsureNCDMDefaults(db)

    -- Helper to copy all settings from one row to another
    local function CopyRowSettings(sourceRow, targetRow)
        if not sourceRow or not targetRow then return end

        -- Copy all numeric and string settings
        local keys = {"iconCount", "iconSize", "borderSize", "shape", "zoom", "padding", "yOffset",
                      "durationSize", "durationOffsetX", "durationOffsetY", "durationAnchor",
                      "stackSize", "stackOffsetX", "stackOffsetY", "stackAnchor", "opacity"}
        for _, key in ipairs(keys) do
            if sourceRow[key] ~= nil then
                targetRow[key] = sourceRow[key]
            end
        end

        -- Copy color tables (deep copy)
        if sourceRow.durationTextColor then
            targetRow.durationTextColor = {sourceRow.durationTextColor[1], sourceRow.durationTextColor[2], sourceRow.durationTextColor[3], sourceRow.durationTextColor[4]}
        end
        if sourceRow.stackTextColor then
            targetRow.stackTextColor = {sourceRow.stackTextColor[1], sourceRow.stackTextColor[2], sourceRow.stackTextColor[3], sourceRow.stackTextColor[4]}
        end
    end

    -- Helper to build a single row's settings (form layout - single column)
    -- trackerData is the parent table (e.g., db.ncdm.essential) containing row1, row2, row3
    local function BuildRowSettings(tabContent, rowNum, rowData, trackerName, trackerData, rebuildCallback)
        local y = tabContent._currentY or -10
        local PAD = 10
        local FORM_ROW = 32

        -- Ensure offset and text size defaults exist
        if rowData.xOffset == nil then rowData.xOffset = 0 end
        if rowData.durationSize == nil then rowData.durationSize = 14 end
        if rowData.durationOffsetX == nil then rowData.durationOffsetX = 0 end
        if rowData.durationOffsetY == nil then rowData.durationOffsetY = 0 end
        if rowData.durationTextColor == nil then rowData.durationTextColor = {1, 1, 1, 1} end
        if rowData.durationAnchor == nil then rowData.durationAnchor = "CENTER" end
        if rowData.stackSize == nil then rowData.stackSize = 14 end
        if rowData.stackOffsetX == nil then rowData.stackOffsetX = 0 end
        if rowData.stackOffsetY == nil then rowData.stackOffsetY = 0 end
        if rowData.stackTextColor == nil then rowData.stackTextColor = {1, 1, 1, 1} end
        if rowData.stackAnchor == nil then rowData.stackAnchor = "BOTTOMRIGHT" end
        if rowData.opacity == nil then rowData.opacity = 1.0 end

        -- Row Header
        local rowHeader = GUI:CreateSectionHeader(tabContent, string.format("Row %d Configuration", rowNum))
        rowHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - rowHeader.gap

        -- Icon settings
        local countSlider = GUI:CreateFormSlider(tabContent, "Icons in Row", 0, 20, 1, "iconCount", rowData, RefreshNCDM)
        countSlider:SetPoint("TOPLEFT", PAD, y)
        countSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local sizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 5, 80, 1, "iconSize", rowData, RefreshNCDM)
        sizeSlider:SetPoint("TOPLEFT", PAD, y)
        sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 5, 1, "borderSize", rowData, RefreshNCDM)
        borderSlider:SetPoint("TOPLEFT", PAD, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColorTable", rowData, RefreshNCDM)
        borderColorPicker:SetPoint("TOPLEFT", PAD, y)
        borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local zoomSlider = GUI:CreateFormSlider(tabContent, "Icon Zoom", 0, 0.2, 0.01, "zoom", rowData, RefreshNCDM)
        zoomSlider:SetPoint("TOPLEFT", PAD, y)
        zoomSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local paddingSlider = GUI:CreateFormSlider(tabContent, "Padding", -20, 20, 1, "padding", rowData, RefreshNCDM)
        paddingSlider:SetPoint("TOPLEFT", PAD, y)
        paddingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Row Y-Offset", -500, 500, 1, "yOffset", rowData, RefreshNCDM)
        yOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local xOffsetSlider = GUI:CreateFormSlider(tabContent, "Row X-Offset", -500, 500, 1, "xOffset", rowData, RefreshNCDM)
        xOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local opacitySlider = GUI:CreateFormSlider(tabContent, "Row Opacity", 0, 1.0, 0.05, "opacity", rowData, RefreshNCDM)
        opacitySlider:SetPoint("TOPLEFT", PAD, y)
        opacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local anchorOptions = {
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

        local durationSlider = GUI:CreateFormSlider(tabContent, "Duration Text Size", 8, 50, 1, "durationSize", rowData, RefreshNCDM)
        durationSlider:SetPoint("TOPLEFT", PAD, y)
        durationSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Duration To", anchorOptions, "durationAnchor", rowData, RefreshNCDM)
        durationAnchorDD:SetPoint("TOPLEFT", PAD, y)
        durationAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationXSlider = GUI:CreateFormSlider(tabContent, "Duration X-Offset", -80, 80, 1, "durationOffsetX", rowData, RefreshNCDM)
        durationXSlider:SetPoint("TOPLEFT", PAD, y)
        durationXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationYSlider = GUI:CreateFormSlider(tabContent, "Duration Y-Offset", -80, 80, 1, "durationOffsetY", rowData, RefreshNCDM)
        durationYSlider:SetPoint("TOPLEFT", PAD, y)
        durationYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationColorPicker = GUI:CreateFormColorPicker(tabContent, "Duration Text Color", "durationTextColor", rowData, RefreshNCDM)
        durationColorPicker:SetPoint("TOPLEFT", PAD, y)
        durationColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackSlider = GUI:CreateFormSlider(tabContent, "Stack Text Size", 8, 50, 1, "stackSize", rowData, RefreshNCDM)
        stackSlider:SetPoint("TOPLEFT", PAD, y)
        stackSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Stack To", anchorOptions, "stackAnchor", rowData, RefreshNCDM)
        stackAnchorDD:SetPoint("TOPLEFT", PAD, y)
        stackAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackXSlider = GUI:CreateFormSlider(tabContent, "Stack X-Offset", -80, 80, 1, "stackOffsetX", rowData, RefreshNCDM)
        stackXSlider:SetPoint("TOPLEFT", PAD, y)
        stackXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackYSlider = GUI:CreateFormSlider(tabContent, "Stack Y-Offset", -80, 80, 1, "stackOffsetY", rowData, RefreshNCDM)
        stackYSlider:SetPoint("TOPLEFT", PAD, y)
        stackYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackColorPicker = GUI:CreateFormColorPicker(tabContent, "Stack Text Color", "stackTextColor", rowData, RefreshNCDM)
        stackColorPicker:SetPoint("TOPLEFT", PAD, y)
        stackColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeSlider = GUI:CreateFormSlider(tabContent, "Icon Shape", 1.0, 2.0, 0.01, "aspectRatioCrop", rowData, RefreshNCDM)
        shapeSlider:SetPoint("TOPLEFT", PAD, y)
        shapeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeTip = GUI:CreateLabel(tabContent, "Higher values imply flatter icons.", 11, C.textMuted)
        shapeTip:SetPoint("TOPLEFT", PAD, y)
        shapeTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        shapeTip:SetJustifyH("LEFT")
        y = y - 20

        -- Copy from dropdown (if trackerData is provided)
        if trackerData then
            local copyOptions = {}
            for i = 1, 3 do
                if i ~= rowNum then
                    table.insert(copyOptions, {value = "row" .. i, text = "Row " .. i})
                end
            end

            -- Copy Settings From - using form dropdown with Apply button
            local copyWrapper = { selected = copyOptions[1] and copyOptions[1].value or nil }
            local copyRow = CreateFrame("Frame", nil, tabContent)
            copyRow:SetHeight(FORM_ROW)
            copyRow:SetPoint("TOPLEFT", PAD, y)
            copyRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            local applyBtn = GUI:CreateButton(copyRow, "Apply", 60, 24, function()
                if copyWrapper.selected and trackerData[copyWrapper.selected] then
                    CopyRowSettings(trackerData[copyWrapper.selected], rowData)
                    RefreshNCDM()
                    if rebuildCallback then rebuildCallback() end
                end
            end)
            applyBtn:SetPoint("RIGHT", copyRow, "RIGHT", 0, 2)

            local copyDropdown = GUI:CreateFormDropdown(copyRow, "Copy Settings From", copyOptions, "selected", copyWrapper, nil)
            copyDropdown:SetPoint("TOPLEFT", 0, 0)
            copyDropdown:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)

            y = y - FORM_ROW
        end

        -- Add spacing between rows
        y = y - 15

        tabContent._currentY = y
        return y
    end

    -- Build Essential sub-tab
    local function BuildEssentialTab(tabContent)
        tabContent._currentY = -10
        local PAD = 10
        local y = tabContent._currentY

        -- Set search context for auto-registration
        GUI:SetSearchContext({tabIndex = 6, tabName = "CDM Setup & Class Bars", subTabIndex = 1, subTabName = "Essential"})

        if db and db.ncdm and db.ncdm.essential then
            local ess = db.ncdm.essential

            -- Rebuild callback to refresh the tab after copying
            local function rebuildEssential()
                -- Clear and rebuild the tab content
                for _, child in pairs({tabContent:GetChildren()}) do
                    child:Hide()
                    child:SetParent(nil)
                end
                for _, region in pairs({tabContent:GetRegions()}) do
                    region:Hide()
                end
                BuildEssentialTab(tabContent)
            end

            -- Enable checkbox
            local FORM_ROW = 32
            local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Essential Cooldowns Display", "enabled", ess, RefreshNCDM)
            enableCheck:SetPoint("TOPLEFT", PAD, y)
            enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Layout Direction dropdown
            ess.layoutDirection = ess.layoutDirection or "HORIZONTAL"
            local directionOptions = {
                {value = "HORIZONTAL", text = "Horizontal"},
                {value = "VERTICAL", text = "Vertical"},
            }
            local directionDropdown = GUI:CreateFormDropdown(tabContent, "Layout Direction", directionOptions, "layoutDirection", ess, RefreshNCDM)
            directionDropdown:SetPoint("TOPLEFT", PAD, y)
            directionDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Hint text
            local hintText = GUI:CreateLabel(tabContent, "Tip: Set Icon Size to 100% in Edit Mode for best results.", 11, C.textMuted)
            hintText:SetPoint("TOPLEFT", PAD, y)
            hintText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            hintText:SetJustifyH("LEFT")
            y = y - 24
            tabContent._currentY = y

            -- Row 1
            if ess.row1 then
                BuildRowSettings(tabContent, 1, ess.row1, "Essential", ess, rebuildEssential)
            end

            -- Row 2
            if ess.row2 then
                BuildRowSettings(tabContent, 2, ess.row2, "Essential", ess, rebuildEssential)
            end

            -- Row 3
            if ess.row3 then
                BuildRowSettings(tabContent, 3, ess.row3, "Essential", ess, rebuildEssential)
            end
        else
            local info = GUI:CreateLabel(tabContent, "NCDM Essential settings not found. Please reload UI.", 12, C.accentLight)
            info:SetPoint("TOPLEFT", PAD, y)
        end

        tabContent:SetHeight(math.abs(tabContent._currentY) + 50)
    end

    -- Build Utility sub-tab
    local function BuildUtilityTab(tabContent)
        tabContent._currentY = -10
        local PAD = 10
        local y = tabContent._currentY

        -- Set search context for auto-registration
        GUI:SetSearchContext({tabIndex = 6, tabName = "CDM Setup & Class Bars", subTabIndex = 2, subTabName = "Utility"})

        if db and db.ncdm and db.ncdm.utility then
            local util = db.ncdm.utility

            -- Rebuild callback to refresh the tab after copying
            local function rebuildUtility()
                -- Clear and rebuild the tab content
                for _, child in pairs({tabContent:GetChildren()}) do
                    child:Hide()
                    child:SetParent(nil)
                end
                for _, region in pairs({tabContent:GetRegions()}) do
                    region:Hide()
                end
                BuildUtilityTab(tabContent)
            end

            -- Enable checkbox
            local FORM_ROW = 32
            local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Utility Cooldowns Display", "enabled", util, RefreshNCDM)
            enableCheck:SetPoint("TOPLEFT", PAD, y)
            enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Anchor Below Essential toggle
            local anchorCheck = GUI:CreateFormCheckbox(tabContent, "Anchor Below Essential Rows", "anchorBelowEssential", util, function()
                RefreshNCDM()
                if _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
                end
            end)
            anchorCheck:SetPoint("TOPLEFT", PAD, y)
            anchorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Anchor Gap slider
            local gapSlider = GUI:CreateFormSlider(tabContent, "Anchor Gap", -200, 200, 1, "anchorGap", util, function()
                RefreshNCDM()
                if _G.QUI_ApplyUtilityAnchor then
                    _G.QUI_ApplyUtilityAnchor()
                end
            end)
            gapSlider:SetPoint("TOPLEFT", PAD, y)
            gapSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Layout Direction dropdown
            util.layoutDirection = util.layoutDirection or "HORIZONTAL"
            local directionOptions = {
                {value = "HORIZONTAL", text = "Horizontal"},
                {value = "VERTICAL", text = "Vertical"},
            }
            local directionDropdown = GUI:CreateFormDropdown(tabContent, "Layout Direction", directionOptions, "layoutDirection", util, RefreshNCDM)
            directionDropdown:SetPoint("TOPLEFT", PAD, y)
            directionDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
            tabContent._currentY = y

            -- Hint text
            local hintText = GUI:CreateLabel(tabContent, "Tip: Set Icon Size to 100% in Edit Mode for best results.", 11, C.textMuted)
            hintText:SetPoint("TOPLEFT", PAD, y)
            hintText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            hintText:SetJustifyH("LEFT")
            y = y - 24
            tabContent._currentY = y

            -- Row 1
            if util.row1 then
                BuildRowSettings(tabContent, 1, util.row1, "Utility", util, rebuildUtility)
            end

            -- Row 2
            if util.row2 then
                BuildRowSettings(tabContent, 2, util.row2, "Utility", util, rebuildUtility)
            end

            -- Row 3
            if util.row3 then
                BuildRowSettings(tabContent, 3, util.row3, "Utility", util, rebuildUtility)
            end
        else
            local info = GUI:CreateLabel(tabContent, "NCDM Utility settings not found. Please reload UI.", 12, C.accentLight)
            info:SetPoint("TOPLEFT", PAD, y)
        end

        tabContent:SetHeight(math.abs(tabContent._currentY) + 50)
    end

    -- Build Buff sub-tab with customization options
    local function BuildBuffTab(tabContent)
        local PAD = 10
        local y = -10

        -- Set search context for widget auto-registration
        GUI:SetSearchContext({tabIndex = 6, tabName = "CDM Setup & Class Bars", subTabIndex = 3, subTabName = "Buff"})

        -- Ensure buff settings exist with all required fields
        if not db.ncdm then db.ncdm = {} end
        if not db.ncdm.buff then db.ncdm.buff = {} end

        -- Ensure all fields exist with defaults
        local buffData = db.ncdm.buff
        if buffData.enabled == nil then buffData.enabled = true end
        if buffData.iconSize == nil then buffData.iconSize = 42 end
        if buffData.borderSize == nil then buffData.borderSize = 2 end
        if buffData.shape == nil then buffData.shape = "square" end  -- DEPRECATED
        if buffData.aspectRatioCrop == nil then buffData.aspectRatioCrop = 1.0 end
        if buffData.growthDirection == nil then buffData.growthDirection = "CENTERED_HORIZONTAL" end
        if buffData.zoom == nil then buffData.zoom = 0 end
        if buffData.padding == nil then buffData.padding = 0 end
        if buffData.durationSize == nil then buffData.durationSize = 12 end
        if buffData.stackSize == nil then buffData.stackSize = 12 end
        if buffData.opacity == nil then buffData.opacity = 1.0 end

        -- Callback to refresh buff bar
        local function RefreshBuff()
            if _G.QUI_RefreshBuffBar then
                _G.QUI_RefreshBuffBar()
            end
        end

        -- Header
        local FORM_ROW = 32
        local header = GUI:CreateSectionHeader(tabContent, "Buff Icon Settings")
        header:SetPoint("TOPLEFT", PAD, y)
        y = y - 24

        local enableCb = GUI:CreateFormCheckbox(tabContent, "Enable Buff Icon Styling", "enabled", buffData, RefreshBuff)
        enableCb:SetPoint("TOPLEFT", PAD, y)
        enableCb:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local sizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 20, 80, 1, "iconSize", buffData, RefreshBuff)
        sizeSlider:SetPoint("TOPLEFT", PAD, y)
        sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 8, 1, "borderSize", buffData, RefreshBuff)
        borderSlider:SetPoint("TOPLEFT", PAD, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local zoomSlider = GUI:CreateFormSlider(tabContent, "Icon Zoom", 0, 0.2, 0.01, "zoom", buffData, RefreshBuff)
        zoomSlider:SetPoint("TOPLEFT", PAD, y)
        zoomSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local paddingSlider = GUI:CreateFormSlider(tabContent, "Icon Padding", -20, 20, 1, "padding", buffData, RefreshBuff)
        paddingSlider:SetPoint("TOPLEFT", PAD, y)
        paddingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local opacitySlider = GUI:CreateFormSlider(tabContent, "Buff Opacity", 0, 1.0, 0.05, "opacity", buffData, RefreshBuff)
        opacitySlider:SetPoint("TOPLEFT", PAD, y)
        opacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationSlider = GUI:CreateFormSlider(tabContent, "Duration Size", 8, 50, 1, "durationSize", buffData, RefreshBuff)
        durationSlider:SetPoint("TOPLEFT", PAD, y)
        durationSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local anchorOptions = {
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

        local durationAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Duration To", anchorOptions, "durationAnchor", buffData, RefreshBuff)
        durationAnchorDD:SetPoint("TOPLEFT", PAD, y)
        durationAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationXSlider = GUI:CreateFormSlider(tabContent, "Duration X Offset", -20, 20, 1, "durationOffsetX", buffData, RefreshBuff)
        durationXSlider:SetPoint("TOPLEFT", PAD, y)
        durationXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local durationYSlider = GUI:CreateFormSlider(tabContent, "Duration Y Offset", -20, 20, 1, "durationOffsetY", buffData, RefreshBuff)
        durationYSlider:SetPoint("TOPLEFT", PAD, y)
        durationYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackSlider = GUI:CreateFormSlider(tabContent, "Stack Size", 8, 50, 1, "stackSize", buffData, RefreshBuff)
        stackSlider:SetPoint("TOPLEFT", PAD, y)
        stackSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackAnchorDD = GUI:CreateFormDropdown(tabContent, "Anchor Stack To", anchorOptions, "stackAnchor", buffData, RefreshBuff)
        stackAnchorDD:SetPoint("TOPLEFT", PAD, y)
        stackAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackXSlider = GUI:CreateFormSlider(tabContent, "Stack X Offset", -20, 20, 1, "stackOffsetX", buffData, RefreshBuff)
        stackXSlider:SetPoint("TOPLEFT", PAD, y)
        stackXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackYSlider = GUI:CreateFormSlider(tabContent, "Stack Y Offset", -20, 20, 1, "stackOffsetY", buffData, RefreshBuff)
        stackYSlider:SetPoint("TOPLEFT", PAD, y)
        stackYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local growthDropdown = GUI:CreateFormDropdown(tabContent, "Growth Direction", {
            {value = "CENTERED_HORIZONTAL", text = "Centered"},
            {value = "UP", text = "Grow Up"},
            {value = "DOWN", text = "Grow Down"},
        }, "growthDirection", buffData, RefreshBuff)
        growthDropdown:SetPoint("TOPLEFT", PAD, y)
        growthDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeSlider = GUI:CreateFormSlider(tabContent, "Icon Shape", 1.0, 2.0, 0.01, "aspectRatioCrop", buffData, RefreshBuff)
        shapeSlider:SetPoint("TOPLEFT", PAD, y)
        shapeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local shapeTip = GUI:CreateLabel(tabContent, "Higher values imply flatter icons.", 11, C.textMuted)
        shapeTip:SetPoint("TOPLEFT", PAD, y)
        shapeTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        shapeTip:SetJustifyH("LEFT")
        y = y - 20

        y = y - 10 -- Spacer

        local info = GUI:CreateLabel(tabContent, "Position the Buff Icons using Edit Mode (Esc > Edit Mode).", 11, C.textMuted)
        info:SetPoint("TOPLEFT", PAD, y)
        info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        info:SetJustifyH("LEFT")
        y = y - FORM_ROW

        -----------------------------------------------------------------------
        -- TRACKED BAR SECTION
        -----------------------------------------------------------------------

        -- Ensure trackedBar settings exist with defaults
        if not db.ncdm.trackedBar then db.ncdm.trackedBar = {} end
        local trackedData = db.ncdm.trackedBar
        if trackedData.enabled == nil then trackedData.enabled = true end
        if trackedData.hideIcon == nil then trackedData.hideIcon = false end
        if trackedData.barHeight == nil then trackedData.barHeight = 24 end
        if trackedData.barWidth == nil then trackedData.barWidth = 200 end
        if trackedData.texture == nil then trackedData.texture = "Quazii v5" end
        if trackedData.useClassColor == nil then trackedData.useClassColor = true end
        if trackedData.barColor == nil then trackedData.barColor = {0.204, 0.827, 0.6, 1} end
        if trackedData.barOpacity == nil then trackedData.barOpacity = 1.0 end
        if trackedData.borderSize == nil then trackedData.borderSize = 1 end
        if trackedData.bgColor == nil then trackedData.bgColor = {0, 0, 0, 1} end
        if trackedData.bgOpacity == nil then trackedData.bgOpacity = 0.7 end
        if trackedData.textSize == nil then trackedData.textSize = 12 end
        if trackedData.spacing == nil then trackedData.spacing = 4 end
        if trackedData.growUp == nil then trackedData.growUp = true end
        if trackedData.hideText == nil then trackedData.hideText = false end
        -- Vertical bar settings
        if trackedData.orientation == nil then trackedData.orientation = "horizontal" end
        if trackedData.fillDirection == nil then trackedData.fillDirection = "up" end
        if trackedData.iconPosition == nil then trackedData.iconPosition = "top" end
        if trackedData.showTextOnVertical == nil then trackedData.showTextOnVertical = false end

        y = y - 10 -- Extra spacing before new section

        local trackedHeader = GUI:CreateSectionHeader(tabContent, "Tracked Bar")
        trackedHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - trackedHeader.gap

        -- Description text
        local trackedDesc = GUI:CreateLabel(tabContent, "Controls the appearance of buff duration bars for spells under 'Tracked Bars' of your CDM. Hint: Most players will opt to display buffs via the Buff Icon section above.", 11, C.textMuted)
        trackedDesc:SetPoint("TOPLEFT", PAD, y)
        trackedDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        trackedDesc:SetJustifyH("LEFT")
        trackedDesc:SetWordWrap(true)
        trackedDesc:SetHeight(30)
        y = y - 40

        -- Enable toggle
        local trackedEnable = GUI:CreateFormCheckbox(tabContent, "Enable Tracked Bar Styling", "enabled", trackedData, RefreshBuff)
        trackedEnable:SetPoint("TOPLEFT", PAD, y)
        trackedEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Hide Icon toggle
        local hideIconCheck = GUI:CreateFormCheckbox(tabContent, "Hide Icon", "hideIcon", trackedData, RefreshBuff)
        hideIconCheck:SetPoint("TOPLEFT", PAD, y)
        hideIconCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Height
        local heightSlider = GUI:CreateFormSlider(tabContent, "Bar Height", 2, 48, 1, "barHeight", trackedData, RefreshBuff)
        heightSlider:SetPoint("TOPLEFT", PAD, y)
        heightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Width
        local widthSlider = GUI:CreateFormSlider(tabContent, "Bar Width", 100, 400, 1, "barWidth", trackedData, RefreshBuff)
        widthSlider:SetPoint("TOPLEFT", PAD, y)
        widthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Texture
        local textureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", trackedData, RefreshBuff)
        textureDropdown:SetPoint("TOPLEFT", PAD, y)
        textureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Forward reference for orientation change callback
        local updateVerticalStates

        -- Bar Orientation
        local orientationDropdown = GUI:CreateFormDropdown(tabContent, "Bar Orientation", {
            {value = "horizontal", text = "Horizontal"},
            {value = "vertical", text = "Vertical"},
        }, "orientation", trackedData, function()
            RefreshBuff()
            if updateVerticalStates then updateVerticalStates() end
            GUI:ShowConfirmation({
                title = "Reload Required",
                message = "Changing bar orientation requires a UI reload to take full effect.",
                acceptText = "Reload Now",
                cancelText = "Later",
                isDestructive = false,
                onAccept = function()
                    QUI:SafeReload()
                end,
            })
        end)
        orientationDropdown:SetPoint("TOPLEFT", PAD, y)
        orientationDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Stack Direction (renamed from Growth Direction, context-dependent)
        local growthDropdown = GUI:CreateFormDropdown(tabContent, "Stack Direction", {
            {value = true, text = "Up / Right"},
            {value = false, text = "Down / Left"},
        }, "growUp", trackedData, RefreshBuff)
        growthDropdown:SetPoint("TOPLEFT", PAD, y)
        growthDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local stackTip = GUI:CreateLabel(tabContent, "Up/Down for horizontal bars, Right/Left for vertical bars.", 11, C.textMuted)
        stackTip:SetPoint("TOPLEFT", PAD, y)
        stackTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        stackTip:SetJustifyH("LEFT")
        y = y - 20

        -- Fill Direction (Vertical only)
        local fillDropdown = GUI:CreateFormDropdown(tabContent, "Fill Direction (Vertical)", {
            {value = "up", text = "Fill Up"},
            {value = "down", text = "Fill Down"},
        }, "fillDirection", trackedData, RefreshBuff)
        fillDropdown:SetPoint("TOPLEFT", PAD, y)
        fillDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fillTip = GUI:CreateLabel(tabContent, "Direction the progress bar fills as buff duration decreases.", 11, C.textMuted)
        fillTip:SetPoint("TOPLEFT", PAD, y)
        fillTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        fillTip:SetJustifyH("LEFT")
        y = y - 20

        -- Icon Position (Vertical only)
        local iconPosDropdown = GUI:CreateFormDropdown(tabContent, "Icon Position (Vertical)", {
            {value = "top", text = "Top"},
            {value = "bottom", text = "Bottom"},
        }, "iconPosition", trackedData, RefreshBuff)
        iconPosDropdown:SetPoint("TOPLEFT", PAD, y)
        iconPosDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconPosTip = GUI:CreateLabel(tabContent, "Where the spell icon appears on vertical bars.", 11, C.textMuted)
        iconPosTip:SetPoint("TOPLEFT", PAD, y)
        iconPosTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        iconPosTip:SetJustifyH("LEFT")
        y = y - 20

        -- Show Text (Vertical only)
        local showTextCheck = GUI:CreateFormCheckbox(tabContent, "Show Text (Vertical)", "showTextOnVertical", trackedData, RefreshBuff)
        showTextCheck:SetPoint("TOPLEFT", PAD, y)
        showTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textTip = GUI:CreateLabel(tabContent, "Text hidden by default on vertical bars. Enable for bars 48+ pixels wide.", 11, C.textMuted)
        textTip:SetPoint("TOPLEFT", PAD, y)
        textTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textTip:SetJustifyH("LEFT")
        y = y - 20

        -- UX: Dim vertical-only options when horizontal
        updateVerticalStates = function()
            local isVertical = trackedData.orientation == "vertical"
            local alpha = isVertical and 1.0 or 0.4
            fillDropdown:SetAlpha(alpha)
            iconPosDropdown:SetAlpha(alpha)
            showTextCheck:SetAlpha(alpha)
            -- Swap height/width labels based on orientation
            if heightSlider.label and widthSlider.label then
                if isVertical then
                    heightSlider.label:SetText("Bar Width")
                    widthSlider.label:SetText("Bar Length")
                else
                    heightSlider.label:SetText("Bar Height")
                    widthSlider.label:SetText("Bar Width")
                end
            end
        end
        updateVerticalStates()  -- Initial state

        -- Use Class Color
        local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", trackedData, RefreshBuff)
        classColorCheck:SetPoint("TOPLEFT", PAD, y)
        classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Color (fallback)
        local barColorPicker = GUI:CreateFormColorPicker(tabContent, "Bar Color (Fallback)", "barColor", trackedData, RefreshBuff)
        barColorPicker:SetPoint("TOPLEFT", PAD, y)
        barColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Opacity
        local barOpacitySlider = GUI:CreateFormSlider(tabContent, "Bar Opacity", 0, 1, 0.05, "barOpacity", trackedData, RefreshBuff)
        barOpacitySlider:SetPoint("TOPLEFT", PAD, y)
        barOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Border Size
        local trackedBorderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 4, 1, "borderSize", trackedData, RefreshBuff)
        trackedBorderSlider:SetPoint("TOPLEFT", PAD, y)
        trackedBorderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Background Color
        local bgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", trackedData, RefreshBuff)
        bgColorPicker:SetPoint("TOPLEFT", PAD, y)
        bgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Background Opacity
        local bgOpacitySlider = GUI:CreateFormSlider(tabContent, "Background Opacity", 0, 1, 0.1, "bgOpacity", trackedData, RefreshBuff)
        bgOpacitySlider:SetPoint("TOPLEFT", PAD, y)
        bgOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Text Size
        local trackedTextSlider = GUI:CreateFormSlider(tabContent, "Text Size", 8, 24, 1, "textSize", trackedData, RefreshBuff)
        trackedTextSlider:SetPoint("TOPLEFT", PAD, y)
        trackedTextSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Hide Text
        local hideTextCheck = GUI:CreateFormCheckbox(tabContent, "Hide Text", "hideText", trackedData, RefreshBuff)
        hideTextCheck:SetPoint("TOPLEFT", PAD, y)
        hideTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Bar Spacing
        local spacingSlider = GUI:CreateFormSlider(tabContent, "Bar Spacing", 0, 20, 1, "spacing", trackedData, RefreshBuff)
        spacingSlider:SetPoint("TOPLEFT", PAD, y)
        spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        tabContent:SetHeight(math.abs(y) + 20)
    end

    -- Build Powerbar sub-tab
    local function BuildPowerbarTab(tabContent)
        local PAD = 10
        local y = -10

        -- Set search context for widget auto-registration
        GUI:SetSearchContext({tabIndex = 6, tabName = "CDM Setup & Class Bars", subTabIndex = 4, subTabName = "Class Resource Bar"})

        -- Ensure powerBar settings exist
        if not db.powerBar then db.powerBar = {} end
        if not db.secondaryPowerBar then db.secondaryPowerBar = {} end

        -- Ensure all fields exist with defaults
        local primary = db.powerBar
        if primary.enabled == nil then primary.enabled = true end
        if primary.autoAttach == nil then primary.autoAttach = true end
        if primary.width == nil then primary.width = 310 end
        if primary.height == nil then primary.height = 8 end
        if primary.offsetX == nil then primary.offsetX = 0 end
        if primary.offsetY == nil then primary.offsetY = 25 end
        if primary.texture == nil then primary.texture = "Solid" end
        if primary.colorMode == nil then primary.colorMode = "power" end  -- "power", "class", or "custom"
        if primary.usePowerColor == nil then primary.usePowerColor = true end  -- Default to power type color
        if primary.useClassColor == nil then primary.useClassColor = false end
        if primary.useCustomColor == nil then primary.useCustomColor = false end
        if primary.customColor == nil then primary.customColor = {0.2, 0.6, 1.0, 1} end
        if primary.bgColor == nil then primary.bgColor = {0.1, 0.1, 0.1, 0.8} end
        if primary.showText == nil then primary.showText = true end
        if primary.showPercent == nil then primary.showPercent = true end
        if primary.textSize == nil then primary.textSize = 14 end
        if primary.textX == nil then primary.textX = 0 end
        if primary.textY == nil then primary.textY = 2 end
        if primary.borderSize == nil then primary.borderSize = 1 end
        if primary.orientation == nil then primary.orientation = "AUTO" end
        if primary.snapGap == nil then primary.snapGap = 5 end

        local secondary = db.secondaryPowerBar
        if secondary.enabled == nil then secondary.enabled = true end
        if secondary.autoAttach == nil then secondary.autoAttach = true end
        if secondary.width == nil then secondary.width = 310 end
        if secondary.height == nil then secondary.height = 8 end
        if secondary.lockedBaseX == nil then secondary.lockedBaseX = 0 end
        if secondary.lockedBaseY == nil then secondary.lockedBaseY = 0 end
        if secondary.offsetX == nil then secondary.offsetX = 0 end
        if secondary.offsetY == nil then secondary.offsetY = 0 end
        if secondary.texture == nil then secondary.texture = "Solid" end
        if secondary.colorMode == nil then secondary.colorMode = "power" end  -- "power", "class", or "custom"
        if secondary.usePowerColor == nil then secondary.usePowerColor = true end  -- Default to power type color
        if secondary.useClassColor == nil then secondary.useClassColor = false end
        if secondary.useCustomColor == nil then secondary.useCustomColor = false end
        if secondary.customColor == nil then secondary.customColor = {1.0, 0.8, 0.2, 1} end
        if secondary.bgColor == nil then secondary.bgColor = {0.1, 0.1, 0.1, 0.8} end
        if secondary.showText == nil then secondary.showText = true end
        if secondary.showPercent == nil then secondary.showPercent = false end
        if secondary.showFragmentedPowerBarText == nil then secondary.showFragmentedPowerBarText = true end
        if secondary.textSize == nil then secondary.textSize = 14 end
        if secondary.textX == nil then secondary.textX = 0 end
        if secondary.textY == nil then secondary.textY = 2 end
        if secondary.borderSize == nil then secondary.borderSize = 1 end
        if secondary.orientation == nil then secondary.orientation = "AUTO" end
        if secondary.snapGap == nil then secondary.snapGap = 5 end

        -- Callback to refresh power bars
        local function RefreshPowerBars()
            if _G.QUI and _G.QUI.QUICore then
                local QUICore = _G.QUI.QUICore
                if QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
                if QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
            end
        end

        -- Get texture options from LSM
        local function GetTextureOptions()
            local options = {}
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local textures = LSM:HashTable("statusbar")
                for name, _ in pairs(textures) do
                    table.insert(options, {value = name, text = name})
                end
                table.sort(options, function(a, b) return a.text < b.text end)
            else
                options = {
                    {value = "Quazii", text = "Quazii"},
                    {value = "Smooth", text = "Smooth"},
                    {value = "Flat", text = "Flat"},
                }
            end
            return options
        end

        -- Forward declare slider references
        local widthPrimarySlider, widthSecondarySlider
        local yOffsetPrimarySlider, yOffsetSecondarySlider

        local FORM_ROW = 32

        -- =====================================================
        -- GENERAL SETTINGS
        -- =====================================================
        local generalHeader = GUI:CreateSectionHeader(tabContent, "General")
        generalHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - generalHeader.gap

        -- Reload prompt for enable/standalone toggles
        local function PromptResourceBarReload()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Changing resource bar settings requires a UI reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end

        -- Enable toggles
        local enablePrimary = GUI:CreateFormToggle(tabContent, "Enable Primary Class Resource Bar", "enabled", primary, PromptResourceBarReload)
        enablePrimary:SetPoint("TOPLEFT", PAD, y)
        enablePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local enableSecondary = GUI:CreateFormToggle(tabContent, "Enable Secondary Class Resource Bar", "enabled", secondary, PromptResourceBarReload)
        enableSecondary:SetPoint("TOPLEFT", PAD, y)
        enableSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Standalone toggles
        local standalonePrimary = GUI:CreateFormToggle(tabContent, "Primary Standalone Mode", "standaloneMode", primary, PromptResourceBarReload)
        standalonePrimary:SetPoint("TOPLEFT", PAD, y)
        standalonePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local standaloneSecondary = GUI:CreateFormToggle(tabContent, "Secondary Standalone Mode", "standaloneMode", secondary, PromptResourceBarReload)
        standaloneSecondary:SetPoint("TOPLEFT", PAD, y)
        standaloneSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local secondaryImptText = GUI:CreateLabel(tabContent, "IMPT: If you choose NOT to display a Primary Bar, and ONLY want a Secondary Bar, toggle this ON. Else it will not show.", 11, C.warning)
        secondaryImptText:SetPoint("TOPLEFT", PAD, y)
        secondaryImptText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        secondaryImptText:SetJustifyH("LEFT")
        y = y - 25

        local standaloneDesc = GUI:CreateLabel(tabContent, "Standalone Mode: Bar won't fade or hide with CDM visibility. Use if you don't use Essential/Utility cooldown displays.", 11, C.textMuted)
        standaloneDesc:SetPoint("TOPLEFT", PAD, y)
        standaloneDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        standaloneDesc:SetJustifyH("LEFT")
        y = y - 25

        -- Unthrottled CPU Use toggle (affects both primary and secondary)
        local unthrottledToggle = GUI:CreateFormToggle(tabContent, "Unthrottled CPU Use", "unthrottledCPU", primary, RefreshPowerBars)
        unthrottledToggle:SetPoint("TOPLEFT", PAD, y)
        unthrottledToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local unthrottledDesc = GUI:CreateLabel(tabContent, "Remove throttle on the number of updates per second. Toggle on for smoother updates, but higher CPU Usage.", 11, C.textMuted)
        unthrottledDesc:SetPoint("TOPLEFT", PAD, y)
        unthrottledDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        unthrottledDesc:SetJustifyH("LEFT")
        y = y - 25

        -- Spacer before Primary section
        y = y - 10

        -- =====================================================
        -- PRIMARY POWER BAR SECTION
        -- =====================================================
        local primaryHeader = GUI:CreateSectionHeader(tabContent, "Primary Class Resource Bar")
        primaryHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - primaryHeader.gap

        local primaryDesc = GUI:CreateLabel(tabContent, "Customize individual resource colors in the Resource Colors section at the bottom. Applied when 'Use Resource Type Color' is enabled.", 11, C.textMuted)
        primaryDesc:SetPoint("TOPLEFT", PAD, y)
        primaryDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        primaryDesc:SetJustifyH("LEFT")
        y = y - 20

        local primaryWarning = GUI:CreateLabel(tabContent, "Designed for horizontal layouts used by most players. Vertical mode requires extra setup (row offsets, orientation toggles).", 11, C.warning)
        primaryWarning:SetPoint("TOPLEFT", PAD, y)
        primaryWarning:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        primaryWarning:SetJustifyH("LEFT")
        y = y - 20

        -- Orientation dropdown
        local orientationOptions = {
            {value = "HORIZONTAL", text = "Horizontal"},
            {value = "VERTICAL", text = "Vertical"},
        }
        local orientationPrimary = GUI:CreateFormDropdown(tabContent, "Orientation", orientationOptions, "orientation", primary, RefreshPowerBars)
        orientationPrimary:SetPoint("TOPLEFT", PAD, y)
        orientationPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Snap to Essential button (form style with label)
        local snapPrimaryContainer = CreateFrame("Frame", nil, tabContent)
        snapPrimaryContainer:SetHeight(FORM_ROW)
        snapPrimaryContainer:SetPoint("TOPLEFT", PAD, y)
        snapPrimaryContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local snapPrimaryLabel = snapPrimaryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapPrimaryLabel:SetPoint("LEFT", 0, 0)
        snapPrimaryLabel:SetText("Quick Position")
        snapPrimaryLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local snapPrimaryBtn = CreateFrame("Button", nil, snapPrimaryContainer, "BackdropTemplate")
        snapPrimaryBtn:SetSize(115, 24)
        snapPrimaryBtn:SetPoint("LEFT", snapPrimaryContainer, "LEFT", 180, 0)
        snapPrimaryBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        snapPrimaryBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapPrimaryText = snapPrimaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapPrimaryText:SetPoint("CENTER")
        snapPrimaryText:SetText("Snap to Essentials")
        snapPrimaryText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapPrimaryBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapPrimaryBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapPrimaryBtn:SetScript("OnClick", function()
            -- Force CDM refresh to ensure __cdmIconWidth is current
            if _G.QUI_RefreshNCDM then
                _G.QUI_RefreshNCDM()
            end

            local essentialViewer = _G.EssentialCooldownViewer

            if essentialViewer and essentialViewer:IsShown() then
                local rawCenterX, rawCenterY = essentialViewer:GetCenter()
                local rawScreenX, rawScreenY = UIParent:GetCenter()

                if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                    local essentialCenterX = math.floor(rawCenterX + 0.5)
                    local essentialCenterY = math.floor(rawCenterY + 0.5)
                    local screenCenterX = math.floor(rawScreenX + 0.5)
                    local screenCenterY = math.floor(rawScreenY + 0.5)
                    local barBorderSize = primary.borderSize or 1
                    local isVertical = primary.orientation == "VERTICAL"

                    if isVertical then
                        -- Vertical bar: goes to the RIGHT of Essential, length matches total height
                        local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
                        local topBottomBorderSize = essentialViewer.__cdmRow1BorderSize or 0
                        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)

                        local totalWidth = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth()
                        local barThickness = primary.height or 8
                        local rightColBorderSize = essentialViewer.__cdmBottomRowBorderSize or 0

                        local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize
                        local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize

                        primary.offsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) - 4
                        primary.offsetY = math.floor(essentialCenterY - screenCenterY + 0.5)
                        primary.width = math.floor(targetWidth + 0.5)
                    else
                        -- Horizontal bar: goes ABOVE Essential, width matches row width
                        local rowWidth = essentialViewer.__cdmRow1Width or essentialViewer.__cdmIconWidth or 300
                        local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
                        local row1BorderSize = essentialViewer.__cdmRow1BorderSize or 2
                        local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
                        local barHeight = primary.height or 8
                        local cdmVisualTop = essentialCenterY + (totalHeight / 2) + row1BorderSize
                        local powerBarCenterY = cdmVisualTop + (barHeight / 2) + barBorderSize

                        primary.offsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) - 1
                        primary.offsetX = math.floor(essentialCenterX - screenCenterX + 0.5)
                        primary.width = math.floor(targetWidth + 0.5)
                    end

                    primary.autoAttach = false
                    primary.useRawPixels = true
                    RefreshPowerBars()

                    if widthPrimarySlider and widthPrimarySlider.SetValue then
                        widthPrimarySlider.SetValue(primary.width, true)
                    end
                    if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                        yOffsetPrimarySlider.SetValue(primary.offsetY, true)
                    end
                else
                    print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                end
            else
                print("|cFF56D1FFQUI:|r Essential Cooldowns viewer not found or not visible.")
            end
        end)

        -- Snap to Utility button (side by side with Essential)
        local snapUtilityBtn = CreateFrame("Button", nil, snapPrimaryContainer, "BackdropTemplate")
        snapUtilityBtn:SetSize(115, 24)
        snapUtilityBtn:SetPoint("LEFT", snapPrimaryBtn, "RIGHT", 5, 0)
        snapUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        snapUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapUtilityText = snapUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapUtilityText:SetPoint("CENTER")
        snapUtilityText:SetText("Snap to Utility")
        snapUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapUtilityBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapUtilityBtn:SetScript("OnClick", function()
            -- Force CDM refresh to ensure dimensions are current
            if _G.QUI_RefreshNCDM then
                _G.QUI_RefreshNCDM()
            end

            local utilityViewer = _G.UtilityCooldownViewer

            if utilityViewer and utilityViewer:IsShown() then
                local rawCenterX, rawCenterY = utilityViewer:GetCenter()
                local rawScreenX, rawScreenY = UIParent:GetCenter()

                if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                    local utilityCenterX = math.floor(rawCenterX + 0.5)
                    local utilityCenterY = math.floor(rawCenterY + 0.5)
                    local screenCenterX = math.floor(rawScreenX + 0.5)
                    local screenCenterY = math.floor(rawScreenY + 0.5)
                    local barBorderSize = primary.borderSize or 1
                    local isVertical = primary.orientation == "VERTICAL"

                    if isVertical then
                        -- Vertical bar: goes to the LEFT of Utility, length matches total height
                        local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
                        local topBottomBorderSize = utilityViewer.__cdmRow1BorderSize or 0
                        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)

                        local totalWidth = utilityViewer.__cdmIconWidth or utilityViewer:GetWidth()
                        local barThickness = primary.height or 8
                        local row1BorderSize = utilityViewer.__cdmRow1BorderSize or 0

                        local cdmVisualLeft = utilityCenterX - (totalWidth / 2) - row1BorderSize
                        local powerBarCenterX = cdmVisualLeft - (barThickness / 2) - barBorderSize

                        primary.offsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) + 1
                        primary.offsetY = math.floor(utilityCenterY - screenCenterY + 0.5)
                        primary.width = math.floor(targetWidth + 0.5)
                    else
                        -- Horizontal bar: goes BELOW Utility, width matches row width
                        local rowWidth = utilityViewer.__cdmBottomRowWidth or utilityViewer.__cdmIconWidth or 300
                        local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
                        local bottomRowBorderSize = utilityViewer.__cdmBottomRowBorderSize or 2
                        local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
                        local barHeight = primary.height or 8
                        local cdmVisualBottom = utilityCenterY - (totalHeight / 2) - bottomRowBorderSize
                        local powerBarCenterY = cdmVisualBottom - (barHeight / 2) - barBorderSize

                        primary.offsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) + 1
                        primary.offsetX = math.floor(utilityCenterX - screenCenterX + 0.5)
                        primary.width = math.floor(targetWidth + 0.5)
                    end

                    primary.autoAttach = false
                    primary.useRawPixels = true
                    RefreshPowerBars()

                    if widthPrimarySlider and widthPrimarySlider.SetValue then
                        widthPrimarySlider.SetValue(primary.width, true)
                    end
                    if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                        yOffsetPrimarySlider.SetValue(primary.offsetY, true)
                    end
                else
                    print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                end
            else
                print("|cFF56D1FFQUI:|r Utility Cooldowns viewer not found or not visible.")
            end
        end)
        y = y - FORM_ROW

        -- Lock buttons (auto-resize when CDM changes)
        local lockContainer = CreateFrame("Frame", nil, tabContent)
        lockContainer:SetHeight(FORM_ROW)
        lockContainer:SetPoint("TOPLEFT", PAD, y)
        lockContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local lockLabel = lockContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockLabel:SetPoint("LEFT", 0, 0)
        lockLabel:SetText("Auto-Resize")
        lockLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Essentials button
        local lockEssentialBtn = CreateFrame("Button", nil, lockContainer, "BackdropTemplate")
        lockEssentialBtn:SetSize(115, 24)
        lockEssentialBtn:SetPoint("LEFT", lockContainer, "LEFT", 180, 0)
        lockEssentialBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        lockEssentialBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)

        local lockEssentialText = lockEssentialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockEssentialText:SetPoint("CENTER")
        lockEssentialText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Utility button
        local lockUtilityBtn = CreateFrame("Button", nil, lockContainer, "BackdropTemplate")
        lockUtilityBtn:SetSize(115, 24)
        lockUtilityBtn:SetPoint("LEFT", lockEssentialBtn, "RIGHT", 5, 0)
        lockUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        lockUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)

        local lockUtilityText = lockUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockUtilityText:SetPoint("CENTER")
        lockUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local function UpdateLockButtonStates()
            -- Essential button state
            if primary.lockedToEssential then
                lockEssentialText:SetText("Unlock Essential")
                lockEssentialBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockEssentialText:SetText("Lock to Essential")
                lockEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Utility button state
            if primary.lockedToUtility then
                lockUtilityText:SetText("Unlock Utility")
                lockUtilityBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockUtilityText:SetText("Lock to Utility")
                lockUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Disable Width slider when locked
            if widthPrimarySlider and widthPrimarySlider.SetEnabled then
                widthPrimarySlider:SetEnabled(not primary.lockedToEssential and not primary.lockedToUtility)
            end
        end
        UpdateLockButtonStates()

        -- Essential button hover
        lockEssentialBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockEssentialBtn:SetScript("OnLeave", function(self)
            if not primary.lockedToEssential then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)

        -- Utility button hover
        lockUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockUtilityBtn:SetScript("OnLeave", function(self)
            if not primary.lockedToUtility then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)

        -- Lock to Essentials click handler
        lockEssentialBtn:SetScript("OnClick", function()
            if primary.lockedToEssential then
                -- Unlock
                primary.lockedToEssential = false
                UpdateLockButtonStates()
            else
                -- Lock: do snap first, then enable lock
                if _G.QUI_RefreshNCDM then
                    _G.QUI_RefreshNCDM()
                end

                local essentialViewer = _G.EssentialCooldownViewer
                if essentialViewer and essentialViewer:IsShown() then
                    local rawCenterX, rawCenterY = essentialViewer:GetCenter()
                    local rawScreenX, rawScreenY = UIParent:GetCenter()

                    if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                        local essentialCenterX = math.floor(rawCenterX + 0.5)
                        local essentialCenterY = math.floor(rawCenterY + 0.5)
                        local screenCenterX = math.floor(rawScreenX + 0.5)
                        local screenCenterY = math.floor(rawScreenY + 0.5)

                        local barBorderSize = primary.borderSize or 1
                        local isVertical = primary.orientation == "VERTICAL"

                        if isVertical then
                            -- Vertical bar: goes to the RIGHT of Essential
                            local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
                            local topBottomBorderSize = essentialViewer.__cdmRow1BorderSize or 0
                            local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
                            local totalWidth = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth()
                            local barThickness = primary.height or 8
                            local rightColBorderSize = essentialViewer.__cdmBottomRowBorderSize or 0
                            local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize
                            local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize
                            primary.offsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) - 4
                            primary.offsetY = math.floor(essentialCenterY - screenCenterY + 0.5)
                            primary.width = math.floor(targetWidth + 0.5)
                        else
                            -- Horizontal bar: goes ABOVE Essential
                            local rowWidth = essentialViewer.__cdmRow1Width or essentialViewer.__cdmIconWidth or 300
                            local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
                            local row1BorderSize = essentialViewer.__cdmRow1BorderSize or 2
                            local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
                            local barHeight = primary.height or 8
                            local cdmVisualTop = essentialCenterY + (totalHeight / 2) + row1BorderSize
                            local powerBarCenterY = cdmVisualTop + (barHeight / 2) + barBorderSize
                            primary.offsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) - 1
                            primary.offsetX = math.floor(essentialCenterX - screenCenterX + 0.5)
                            primary.width = math.floor(targetWidth + 0.5)
                        end
                        primary.autoAttach = false
                        primary.useRawPixels = true
                        primary.lockedToEssential = true
                        primary.lockedToUtility = false  -- Mutually exclusive

                        RefreshPowerBars()
                        UpdateLockButtonStates()

                        if widthPrimarySlider and widthPrimarySlider.SetValue then
                            widthPrimarySlider.SetValue(primary.width, true)
                        end
                        if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                            yOffsetPrimarySlider.SetValue(primary.offsetY, true)
                        end
                    else
                        print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                    end
                else
                    print("|cFF56D1FFQUI:|r Essential Cooldowns viewer not found or not visible.")
                end
            end
        end)

        -- Lock to Utility click handler
        lockUtilityBtn:SetScript("OnClick", function()
            if primary.lockedToUtility then
                -- Unlock
                primary.lockedToUtility = false
                UpdateLockButtonStates()
            else
                -- Lock: do snap first, then enable lock
                if _G.QUI_RefreshNCDM then
                    _G.QUI_RefreshNCDM()
                end

                local utilityViewer = _G.UtilityCooldownViewer
                if utilityViewer and utilityViewer:IsShown() then
                    local rawCenterX, rawCenterY = utilityViewer:GetCenter()
                    local rawScreenX, rawScreenY = UIParent:GetCenter()

                    if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                        local utilityCenterX = math.floor(rawCenterX + 0.5)
                        local utilityCenterY = math.floor(rawCenterY + 0.5)
                        local screenCenterX = math.floor(rawScreenX + 0.5)
                        local screenCenterY = math.floor(rawScreenY + 0.5)

                        local barBorderSize = primary.borderSize or 1
                        local isVertical = primary.orientation == "VERTICAL"

                        if isVertical then
                            -- Vertical bar: goes to the LEFT of Utility
                            local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
                            local topBottomBorderSize = utilityViewer.__cdmRow1BorderSize or 0
                            local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
                            local totalWidth = utilityViewer.__cdmIconWidth or utilityViewer:GetWidth()
                            local barThickness = primary.height or 8
                            local row1BorderSize = utilityViewer.__cdmRow1BorderSize or 0
                            local cdmVisualLeft = utilityCenterX - (totalWidth / 2) - row1BorderSize
                            local powerBarCenterX = cdmVisualLeft - (barThickness / 2) - barBorderSize
                            primary.offsetX = math.floor(powerBarCenterX - screenCenterX + 0.5) + 1
                            primary.offsetY = math.floor(utilityCenterY - screenCenterY + 0.5)
                            primary.width = math.floor(targetWidth + 0.5)
                        else
                            -- Horizontal bar: goes BELOW Utility
                            local rowWidth = utilityViewer.__cdmBottomRowWidth or utilityViewer.__cdmIconWidth or 300
                            local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
                            local bottomRowBorderSize = utilityViewer.__cdmBottomRowBorderSize or 2
                            local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
                            local barHeight = primary.height or 8
                            local cdmVisualBottom = utilityCenterY - (totalHeight / 2) - bottomRowBorderSize
                            local powerBarCenterY = cdmVisualBottom - (barHeight / 2) - barBorderSize
                            primary.offsetY = math.floor(powerBarCenterY - screenCenterY + 0.5) + 1
                            primary.offsetX = math.floor(utilityCenterX - screenCenterX + 0.5)
                            primary.width = math.floor(targetWidth + 0.5)
                        end
                        primary.autoAttach = false
                        primary.useRawPixels = true
                        primary.lockedToUtility = true
                        primary.lockedToEssential = false  -- Mutually exclusive

                        RefreshPowerBars()
                        UpdateLockButtonStates()

                        if widthPrimarySlider and widthPrimarySlider.SetValue then
                            widthPrimarySlider.SetValue(primary.width, true)
                        end
                        if yOffsetPrimarySlider and yOffsetPrimarySlider.SetValue then
                            yOffsetPrimarySlider.SetValue(primary.offsetY, true)
                        end
                    else
                        print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                    end
                else
                    print("|cFF56D1FFQUI:|r Utility Cooldowns viewer not found or not visible.")
                end
            end
        end)
        y = y - FORM_ROW

        -- Color options (form style) - radio-button behavior: clicking one turns off the others
        local customColorPickerPrimary

        local powerColorPrimary = GUI:CreateFormCheckbox(tabContent, "Use Resource Type Color", "usePowerColor", primary, function()
            if primary.usePowerColor then
                primary.useClassColor = false
                primary.useCustomColor = false
                primary.colorMode = "power"
            else
                -- Fallback: if turning off and nothing else is on, re-enable this
                if not primary.useClassColor and not primary.useCustomColor then
                    primary.usePowerColor = true
                end
            end
            if customColorPickerPrimary then
                customColorPickerPrimary:SetEnabled(primary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        powerColorPrimary:SetPoint("TOPLEFT", PAD, y)
        powerColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local resourceColorDescPrimary = GUI:CreateLabel(tabContent, "Uses per-resource colors from the Resource Colors section below.", 11)
        resourceColorDescPrimary:SetPoint("TOPLEFT", PAD, y + 4)
        resourceColorDescPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        resourceColorDescPrimary:SetJustifyH("LEFT")
        resourceColorDescPrimary:SetTextColor(0.6, 0.6, 0.6)
        y = y - FORM_ROW

        local classColorPrimary = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", primary, function()
            if primary.useClassColor then
                primary.usePowerColor = false
                primary.useCustomColor = false
                primary.colorMode = "class"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not primary.usePowerColor and not primary.useCustomColor then
                    primary.usePowerColor = true
                end
            end
            if customColorPickerPrimary then
                customColorPickerPrimary:SetEnabled(primary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        classColorPrimary:SetPoint("TOPLEFT", PAD, y)
        classColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local bgColorPrimary = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", primary, RefreshPowerBars)
        bgColorPrimary:SetPoint("TOPLEFT", PAD, y)
        bgColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local customColorOverridePrimary = GUI:CreateFormCheckbox(tabContent, "Custom Color Override", "useCustomColor", primary, function()
            if primary.useCustomColor then
                primary.usePowerColor = false
                primary.useClassColor = false
                primary.colorMode = "custom"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not primary.usePowerColor and not primary.useClassColor then
                    primary.usePowerColor = true
                end
            end
            if customColorPickerPrimary then
                customColorPickerPrimary:SetEnabled(primary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        customColorOverridePrimary:SetPoint("TOPLEFT", PAD, y)
        customColorOverridePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        customColorPickerPrimary = GUI:CreateFormColorPicker(tabContent, "Custom Color", "customColor", primary, RefreshPowerBars)
        customColorPickerPrimary:SetPoint("TOPLEFT", PAD, y)
        customColorPickerPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        customColorPickerPrimary:SetEnabled(primary.useCustomColor)
        y = y - FORM_ROW

        -- Text display options
        local showTextPrimary = GUI:CreateFormCheckbox(tabContent, "Show Number", "showText", primary, RefreshPowerBars)
        showTextPrimary:SetPoint("TOPLEFT", PAD, y)
        showTextPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showPercentPrimary = GUI:CreateFormCheckbox(tabContent, "Show as Percent", "showPercent", primary, RefreshPowerBars)
        showPercentPrimary:SetPoint("TOPLEFT", PAD, y)
        showPercentPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Tick marks
        local showTicksPrimary = GUI:CreateFormCheckbox(tabContent, "Show Tick Marks", "showTicks", primary, RefreshPowerBars)
        showTicksPrimary:SetPoint("TOPLEFT", PAD, y)
        showTicksPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickThicknessPrimary = GUI:CreateFormSlider(tabContent, "Tick Thickness", 1, 4, 1, "tickThickness", primary, RefreshPowerBars)
        tickThicknessPrimary:SetPoint("TOPLEFT", PAD, y)
        tickThicknessPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickColorPrimary = GUI:CreateFormColorPicker(tabContent, "Tick Color", "tickColor", primary, RefreshPowerBars)
        tickColorPrimary:SetPoint("TOPLEFT", PAD, y)
        tickColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Size sliders (form style)
        widthPrimarySlider = GUI:CreateFormSlider(tabContent, "Width", 0, 2000, 1, "width", primary, RefreshPowerBars)
        widthPrimarySlider:SetPoint("TOPLEFT", PAD, y)
        widthPrimarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        widthPrimarySlider:SetEnabled(not primary.lockedToEssential and not primary.lockedToUtility)  -- Disabled when locked
        y = y - FORM_ROW

        local heightPrimary = GUI:CreateFormSlider(tabContent, "Height", 1, 100, 1, "height", primary, RefreshPowerBars)
        heightPrimary:SetPoint("TOPLEFT", PAD, y)
        heightPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderPrimary = GUI:CreateFormSlider(tabContent, "Border Size", 0, 8, 1, "borderSize", primary, RefreshPowerBars)
        borderPrimary:SetPoint("TOPLEFT", PAD, y)
        borderPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Position sliders
        local xOffsetPrimarySlider = GUI:CreateFormSlider(tabContent, "X Offset", -1000, 1000, 1, "offsetX", primary, RefreshPowerBars)
        xOffsetPrimarySlider:SetPoint("TOPLEFT", PAD, y)
        xOffsetPrimarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        yOffsetPrimarySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -1000, 1000, 1, "offsetY", primary, RefreshPowerBars)
        yOffsetPrimarySlider:SetPoint("TOPLEFT", PAD, y)
        yOffsetPrimarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Register sliders for real-time sync during Edit Mode
        if _G.QUI and _G.QUI.QUICore and _G.QUI.QUICore.RegisterPowerBarEditModeSliders then
            _G.QUI.QUICore:RegisterPowerBarEditModeSliders("primary", xOffsetPrimarySlider, yOffsetPrimarySlider)
        end

        -- Text sliders
        local textSizePrimary = GUI:CreateFormSlider(tabContent, "Text Size", 8, 50, 1, "textSize", primary, RefreshPowerBars)
        textSizePrimary:SetPoint("TOPLEFT", PAD, y)
        textSizePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textXPrimary = GUI:CreateFormSlider(tabContent, "Text X Offset", -500, 500, 1, "textX", primary, RefreshPowerBars)
        textXPrimary:SetPoint("TOPLEFT", PAD, y)
        textXPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textYPrimary = GUI:CreateFormSlider(tabContent, "Text Y Offset", -500, 500, 1, "textY", primary, RefreshPowerBars)
        textYPrimary:SetPoint("TOPLEFT", PAD, y)
        textYPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Text color settings
        local textCustomColorPrimary  -- Forward declare for mutual reference

        local textUseClassColorPrimary = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Text", "textUseClassColor", primary, function()
            if textCustomColorPrimary then
                textCustomColorPrimary:SetEnabled(not primary.textUseClassColor)
            end
            RefreshPowerBars()
        end)
        textUseClassColorPrimary:SetPoint("TOPLEFT", PAD, y)
        textUseClassColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        textCustomColorPrimary = GUI:CreateFormColorPicker(tabContent, "Custom Text Color", "textCustomColor", primary, RefreshPowerBars)
        textCustomColorPrimary:SetPoint("TOPLEFT", PAD, y)
        textCustomColorPrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textCustomColorPrimary:SetEnabled(not primary.textUseClassColor)  -- Initial state
        y = y - FORM_ROW

        local texturePrimary = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", primary, RefreshPowerBars)
        texturePrimary:SetPoint("TOPLEFT", PAD, y)
        texturePrimary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Spacer between sections
        y = y - 15

        -- =====================================================
        -- SECONDARY POWER BAR SECTION
        -- =====================================================
        local secondaryHeader = GUI:CreateSectionHeader(tabContent, "Secondary Class Resource Bar")
        secondaryHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - secondaryHeader.gap

        local secondaryDesc = GUI:CreateLabel(tabContent, "Customize individual resource colors in the Resource Colors section at the bottom. Applied when 'Use Resource Type Color' is enabled.", 11, C.textMuted)
        secondaryDesc:SetPoint("TOPLEFT", PAD, y)
        secondaryDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        secondaryDesc:SetJustifyH("LEFT")
        y = y - 20

        local secondaryWarning = GUI:CreateLabel(tabContent, "Designed for horizontal layouts used by most players. Vertical mode requires extra setup (row offsets, orientation toggles).", 11, C.warning)
        secondaryWarning:SetPoint("TOPLEFT", PAD, y)
        secondaryWarning:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        secondaryWarning:SetJustifyH("LEFT")
        y = y - 20

        -- Orientation dropdown
        local orientationOptionsSecondary = {
            {value = "HORIZONTAL", text = "Horizontal"},
            {value = "VERTICAL", text = "Vertical"},
        }
        local orientationSecondary = GUI:CreateFormDropdown(tabContent, "Orientation", orientationOptionsSecondary, "orientation", secondary, RefreshPowerBars)
        orientationSecondary:SetPoint("TOPLEFT", PAD, y)
        orientationSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Quick Position row with 3 buttons: Snap to Essentials, Snap to Utility, Snap to Primary
        local snapSecondaryContainer = CreateFrame("Frame", nil, tabContent)
        snapSecondaryContainer:SetHeight(FORM_ROW)
        snapSecondaryContainer:SetPoint("TOPLEFT", PAD, y)
        snapSecondaryContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local snapSecondaryLabel = snapSecondaryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecondaryLabel:SetPoint("LEFT", 0, 0)
        snapSecondaryLabel:SetText("Quick Position")
        snapSecondaryLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Snap to Essentials button
        local snapSecEssentialBtn = CreateFrame("Button", nil, snapSecondaryContainer, "BackdropTemplate")
        snapSecEssentialBtn:SetSize(100, 24)
        snapSecEssentialBtn:SetPoint("LEFT", snapSecondaryContainer, "LEFT", 180, 0)
        snapSecEssentialBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        snapSecEssentialBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapSecEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapSecEssentialText = snapSecEssentialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecEssentialText:SetPoint("CENTER")
        snapSecEssentialText:SetText("Essentials")
        snapSecEssentialText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapSecEssentialBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapSecEssentialBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapSecEssentialBtn:SetScript("OnClick", function()
            if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
            local essentialViewer = _G.EssentialCooldownViewer
            if essentialViewer and essentialViewer:IsShown() then
                local rawCenterX, rawCenterY = essentialViewer:GetCenter()
                local rawScreenX, rawScreenY = UIParent:GetCenter()
                if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                    local essentialCenterX = math.floor(rawCenterX + 0.5)
                    local essentialCenterY = math.floor(rawCenterY + 0.5)
                    local screenCenterX = math.floor(rawScreenX + 0.5)
                    local screenCenterY = math.floor(rawScreenY + 0.5)
                    local barBorderSize = secondary.borderSize or 1
                    local isVertical = secondary.orientation == "VERTICAL"

                    if isVertical then
                        -- Vertical bar: goes to the RIGHT of Essential
                        local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
                        local topBottomBorderSize = essentialViewer.__cdmRow1BorderSize or 0
                        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
                        local totalWidth = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth()
                        local barThickness = secondary.height or 8
                        local rightColBorderSize = essentialViewer.__cdmBottomRowBorderSize or 0
                        local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize
                        local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize
                        secondary.lockedBaseX = math.floor(powerBarCenterX - screenCenterX + 0.5) - 4
                        secondary.lockedBaseY = math.floor(essentialCenterY - screenCenterY + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    else
                        -- Horizontal bar: goes ABOVE Essential
                        local rowWidth = essentialViewer.__cdmRow1Width or essentialViewer.__cdmIconWidth or 300
                        local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
                        local row1BorderSize = essentialViewer.__cdmRow1BorderSize or 2
                        local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
                        local barHeight = secondary.height or 8
                        local cdmVisualTop = essentialCenterY + (totalHeight / 2) + row1BorderSize
                        local powerBarCenterY = cdmVisualTop + (barHeight / 2) + barBorderSize
                        secondary.lockedBaseY = math.floor(powerBarCenterY - screenCenterY + 0.5) - 1
                        secondary.lockedBaseX = math.floor(essentialCenterX - screenCenterX + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    end

                    secondary.offsetX = 0  -- Reset user adjustment
                    secondary.offsetY = 0
                    secondary.autoAttach = false
                    secondary.useRawPixels = true
                    RefreshPowerBars()
                    if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                    if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                else
                    print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                end
            else
                print("|cFF56D1FFQUI:|r Essential Cooldowns viewer not found or not visible.")
            end
        end)

        -- Snap to Utility button
        local snapSecUtilityBtn = CreateFrame("Button", nil, snapSecondaryContainer, "BackdropTemplate")
        snapSecUtilityBtn:SetSize(100, 24)
        snapSecUtilityBtn:SetPoint("LEFT", snapSecEssentialBtn, "RIGHT", 5, 0)
        snapSecUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        snapSecUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapSecUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapSecUtilityText = snapSecUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecUtilityText:SetPoint("CENTER")
        snapSecUtilityText:SetText("Utility")
        snapSecUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapSecUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapSecUtilityBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapSecUtilityBtn:SetScript("OnClick", function()
            if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
            local utilityViewer = _G.UtilityCooldownViewer
            if utilityViewer and utilityViewer:IsShown() then
                local rawCenterX, rawCenterY = utilityViewer:GetCenter()
                local rawScreenX, rawScreenY = UIParent:GetCenter()
                if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                    local utilityCenterX = math.floor(rawCenterX + 0.5)
                    local utilityCenterY = math.floor(rawCenterY + 0.5)
                    local screenCenterX = math.floor(rawScreenX + 0.5)
                    local screenCenterY = math.floor(rawScreenY + 0.5)
                    local barBorderSize = secondary.borderSize or 1
                    local isVertical = secondary.orientation == "VERTICAL"

                    if isVertical then
                        -- Vertical bar: goes to the LEFT of Utility
                        local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
                        local topBottomBorderSize = utilityViewer.__cdmRow1BorderSize or 0
                        local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
                        local totalWidth = utilityViewer.__cdmIconWidth or utilityViewer:GetWidth()
                        local barThickness = secondary.height or 8
                        local cdmVisualLeft = utilityCenterX - (totalWidth / 2)
                        local powerBarCenterX = cdmVisualLeft - (barThickness / 2)
                        secondary.lockedBaseX = math.floor(powerBarCenterX - screenCenterX + 0.5)
                        secondary.lockedBaseY = math.floor(utilityCenterY - screenCenterY + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    else
                        -- Horizontal bar: goes BELOW Utility
                        local rowWidth = utilityViewer.__cdmBottomRowWidth or utilityViewer.__cdmIconWidth or 300
                        local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
                        local bottomRowBorderSize = utilityViewer.__cdmBottomRowBorderSize or 2
                        local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
                        local barHeight = secondary.height or 8
                        local cdmVisualBottom = utilityCenterY - (totalHeight / 2) - bottomRowBorderSize
                        local powerBarCenterY = cdmVisualBottom - (barHeight / 2) - barBorderSize
                        secondary.lockedBaseY = math.floor(powerBarCenterY - screenCenterY + 0.5) + 1
                        secondary.lockedBaseX = math.floor(utilityCenterX - screenCenterX + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    end

                    secondary.offsetX = 0  -- Reset user adjustment
                    secondary.offsetY = 0
                    secondary.autoAttach = false
                    secondary.useRawPixels = true
                    RefreshPowerBars()
                    if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                    if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                else
                    print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                end
            else
                print("|cFF56D1FFQUI:|r Utility Cooldowns viewer not found or not visible.")
            end
        end)

        -- Snap to Primary button
        local snapSecPrimaryBtn = CreateFrame("Button", nil, snapSecondaryContainer, "BackdropTemplate")
        snapSecPrimaryBtn:SetSize(100, 24)
        snapSecPrimaryBtn:SetPoint("LEFT", snapSecUtilityBtn, "RIGHT", 5, 0)
        snapSecPrimaryBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        snapSecPrimaryBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapSecPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local snapSecPrimaryText = snapSecPrimaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapSecPrimaryText:SetPoint("CENTER")
        snapSecPrimaryText:SetText("Primary")
        snapSecPrimaryText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        snapSecPrimaryBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        snapSecPrimaryBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        snapSecPrimaryBtn:SetScript("OnClick", function()
            local QUICore = _G.QUI and _G.QUI.QUICore
            local primaryBar = QUICore and QUICore.powerBar
            local primaryCfg = QUICore and QUICore.db and QUICore.db.profile.powerBar
            if primaryBar and primaryBar:IsShown() and primaryCfg then
                local primaryCenterX, primaryCenterY = primaryBar:GetCenter()
                local screenCenterX, screenCenterY = UIParent:GetCenter()
                if primaryCenterX and primaryCenterY and screenCenterX and screenCenterY then
                    primaryCenterX = math.floor(primaryCenterX + 0.5)
                    primaryCenterY = math.floor(primaryCenterY + 0.5)
                    screenCenterX = math.floor(screenCenterX + 0.5)
                    screenCenterY = math.floor(screenCenterY + 0.5)
                    local primaryHeight = primaryCfg.height or 8
                    local primaryWidth = primaryCfg.width or primaryBar:GetWidth() or 300
                    local primaryBorderSize = primaryCfg.borderSize or 1
                    local secondaryHeight = secondary.height or 8
                    local secondaryBorderSize = secondary.borderSize or 1
                    local isVertical = secondary.orientation == "VERTICAL"

                    if isVertical then
                        -- Vertical secondary: goes to the RIGHT of Primary
                        local primaryActualWidth = primaryBar:GetWidth()
                        local primaryVisualRight = primaryCenterX + (primaryActualWidth / 2)
                        local secondaryBarCenterX = primaryVisualRight + (secondaryHeight / 2)
                        local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                        secondary.lockedBaseX = math.floor(secondaryBarCenterX - screenCenterX + 0.5)
                        secondary.lockedBaseY = math.floor(primaryCenterY - screenCenterY + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    else
                        -- Horizontal bar: Secondary goes ABOVE Primary
                        local primaryVisualTop = primaryCenterY + (primaryHeight / 2) + primaryBorderSize
                        local secondaryBarCenterY = primaryVisualTop + (secondaryHeight / 2) + secondaryBorderSize
                        local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                        secondary.lockedBaseY = math.floor(secondaryBarCenterY - screenCenterY + 0.5) - 1
                        secondary.lockedBaseX = math.floor(primaryCenterX - screenCenterX + 0.5)
                        secondary.width = math.floor(targetWidth + 0.5)
                    end

                    secondary.offsetX = 0  -- Reset user adjustment
                    secondary.offsetY = 0
                    secondary.autoAttach = false
                    secondary.useRawPixels = true
                    RefreshPowerBars()
                    if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                    if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                else
                    print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                end
            else
                print("|cFF56D1FFQUI:|r Primary Class Resource Bar not found or not visible. Enable it first.")
            end
        end)
        y = y - FORM_ROW

        -- Auto-Resize row with 3 buttons: Lock to Essential, Lock to Utility, Lock to Primary
        local lockSecContainer = CreateFrame("Frame", nil, tabContent)
        lockSecContainer:SetHeight(FORM_ROW)
        lockSecContainer:SetPoint("TOPLEFT", PAD, y)
        lockSecContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local lockSecLabel = lockSecContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecLabel:SetPoint("LEFT", 0, 0)
        lockSecLabel:SetText("Auto-Resize")
        lockSecLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Essential button
        local lockSecEssentialBtn = CreateFrame("Button", nil, lockSecContainer, "BackdropTemplate")
        lockSecEssentialBtn:SetSize(100, 24)
        lockSecEssentialBtn:SetPoint("LEFT", lockSecContainer, "LEFT", 180, 0)
        lockSecEssentialBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        lockSecEssentialBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        lockSecEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local lockSecEssentialText = lockSecEssentialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecEssentialText:SetPoint("CENTER")
        lockSecEssentialText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Utility button
        local lockSecUtilityBtn = CreateFrame("Button", nil, lockSecContainer, "BackdropTemplate")
        lockSecUtilityBtn:SetSize(100, 24)
        lockSecUtilityBtn:SetPoint("LEFT", lockSecEssentialBtn, "RIGHT", 5, 0)
        lockSecUtilityBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        lockSecUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        lockSecUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local lockSecUtilityText = lockSecUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecUtilityText:SetPoint("CENTER")
        lockSecUtilityText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Lock to Primary button
        local lockSecPrimaryBtn = CreateFrame("Button", nil, lockSecContainer, "BackdropTemplate")
        lockSecPrimaryBtn:SetSize(100, 24)
        lockSecPrimaryBtn:SetPoint("LEFT", lockSecUtilityBtn, "RIGHT", 5, 0)
        lockSecPrimaryBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        lockSecPrimaryBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        lockSecPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local lockSecPrimaryText = lockSecPrimaryBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lockSecPrimaryText:SetPoint("CENTER")
        lockSecPrimaryText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Function to update lock button states (visual + width slider)
        local function UpdateSecLockButtonStates()
            -- Essential button state
            if secondary.lockedToEssential then
                lockSecEssentialText:SetText("Unlock")
                lockSecEssentialBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockSecEssentialText:SetText("Essential")
                lockSecEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Utility button state
            if secondary.lockedToUtility then
                lockSecUtilityText:SetText("Unlock")
                lockSecUtilityBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockSecUtilityText:SetText("Utility")
                lockSecUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Primary button state
            if secondary.lockedToPrimary then
                lockSecPrimaryText:SetText("Unlock")
                lockSecPrimaryBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                lockSecPrimaryText:SetText("Primary")
                lockSecPrimaryBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
            -- Disable Width slider when any lock is active
            if widthSecondarySlider and widthSecondarySlider.SetEnabled then
                widthSecondarySlider:SetEnabled(not secondary.lockedToEssential and not secondary.lockedToUtility and not secondary.lockedToPrimary)
            end
        end

        -- Hover effects (preserve lock state color on leave)
        lockSecEssentialBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockSecEssentialBtn:SetScript("OnLeave", function(self)
            if not secondary.lockedToEssential then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)
        lockSecUtilityBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockSecUtilityBtn:SetScript("OnLeave", function(self)
            if not secondary.lockedToUtility then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)
        lockSecPrimaryBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        lockSecPrimaryBtn:SetScript("OnLeave", function(self)
            if not secondary.lockedToPrimary then
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end
        end)

        -- Lock to Essential click handler
        lockSecEssentialBtn:SetScript("OnClick", function()
            if secondary.lockedToEssential then
                secondary.lockedToEssential = false
                UpdateSecLockButtonStates()
            else
                if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
                local essentialViewer = _G.EssentialCooldownViewer
                if essentialViewer and essentialViewer:IsShown() then
                    local rawCenterX, rawCenterY = essentialViewer:GetCenter()
                    local rawScreenX, rawScreenY = UIParent:GetCenter()
                    if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                        local essentialCenterX = math.floor(rawCenterX + 0.5)
                        local essentialCenterY = math.floor(rawCenterY + 0.5)
                        local screenCenterX = math.floor(rawScreenX + 0.5)
                        local screenCenterY = math.floor(rawScreenY + 0.5)
                        local totalHeight = essentialViewer.__cdmTotalHeight or essentialViewer:GetHeight() or 100
                        local row1BorderSize = essentialViewer.__cdmRow1BorderSize or 2
                        local barBorderSize = secondary.borderSize or 1
                        local isVertical = secondary.orientation == "VERTICAL"

                        if isVertical then
                            -- Vertical bar: goes to the RIGHT of Essential
                            local topBottomBorderSize = essentialViewer.__cdmRow1BorderSize or 0
                            local targetWidth = totalHeight + (2 * topBottomBorderSize) - (2 * barBorderSize)
                            local totalWidth = essentialViewer.__cdmIconWidth or essentialViewer:GetWidth()
                            local barThickness = secondary.height or 8
                            local rightColBorderSize = essentialViewer.__cdmBottomRowBorderSize or 0
                            local cdmVisualRight = essentialCenterX + (totalWidth / 2) + rightColBorderSize
                            local powerBarCenterX = cdmVisualRight + (barThickness / 2) + barBorderSize
                            secondary.lockedBaseX = math.floor(powerBarCenterX - screenCenterX + 0.5) - 4
                            secondary.lockedBaseY = math.floor(essentialCenterY - screenCenterY + 0.5)
                            secondary.width = math.floor(targetWidth + 0.5)
                        else
                            -- Horizontal bar: goes ABOVE Essential
                            local rowWidth = essentialViewer.__cdmRow1Width or essentialViewer.__cdmIconWidth or 300
                            local barHeight = secondary.height or 8
                            local targetWidth = rowWidth + (2 * row1BorderSize) - (2 * barBorderSize)
                            local cdmVisualTop = essentialCenterY + (totalHeight / 2) + row1BorderSize
                            local powerBarCenterY = cdmVisualTop + (barHeight / 2) + barBorderSize
                            secondary.lockedBaseY = math.floor(powerBarCenterY - screenCenterY + 0.5) - 1
                            secondary.lockedBaseX = math.floor(essentialCenterX - screenCenterX + 0.5)
                            secondary.width = math.floor(targetWidth + 0.5)
                        end
                        secondary.offsetX = 0  -- Reset user adjustment
                        secondary.offsetY = 0
                        secondary.autoAttach = false
                        secondary.useRawPixels = true
                        secondary.lockedToEssential = true
                        secondary.lockedToUtility = false
                        secondary.lockedToPrimary = false
                        RefreshPowerBars()
                        UpdateSecLockButtonStates()
                        if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                        if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                    else
                        print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                    end
                else
                    print("|cFF56D1FFQUI:|r Essential Cooldowns viewer not found or not visible.")
                end
            end
        end)

        -- Lock to Utility click handler
        lockSecUtilityBtn:SetScript("OnClick", function()
            if secondary.lockedToUtility then
                secondary.lockedToUtility = false
                UpdateSecLockButtonStates()
            else
                if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
                local utilityViewer = _G.UtilityCooldownViewer
                if utilityViewer and utilityViewer:IsShown() then
                    local rawCenterX, rawCenterY = utilityViewer:GetCenter()
                    local rawScreenX, rawScreenY = UIParent:GetCenter()
                    if rawCenterX and rawCenterY and rawScreenX and rawScreenY then
                        local utilityCenterX = math.floor(rawCenterX + 0.5)
                        local utilityCenterY = math.floor(rawCenterY + 0.5)
                        local screenCenterX = math.floor(rawScreenX + 0.5)
                        local screenCenterY = math.floor(rawScreenY + 0.5)
                        local totalHeight = utilityViewer.__cdmTotalHeight or utilityViewer:GetHeight() or 100
                        local bottomRowBorderSize = utilityViewer.__cdmBottomRowBorderSize or 2
                        local barBorderSize = secondary.borderSize or 1
                        local isVertical = secondary.orientation == "VERTICAL"

                        if isVertical then
                            -- Vertical bar: goes to the LEFT of Utility
                            local row1BorderSize = utilityViewer.__cdmRow1BorderSize or 0
                            local targetWidth = totalHeight + (2 * row1BorderSize) - (2 * barBorderSize)
                            local totalWidth = utilityViewer.__cdmIconWidth or utilityViewer:GetWidth()
                            local barThickness = secondary.height or 8
                            local cdmVisualLeft = utilityCenterX - (totalWidth / 2)
                            local powerBarCenterX = cdmVisualLeft - (barThickness / 2)
                            secondary.lockedBaseX = math.floor(powerBarCenterX - screenCenterX + 0.5)
                            secondary.lockedBaseY = math.floor(utilityCenterY - screenCenterY + 0.5)
                            secondary.width = math.floor(targetWidth + 0.5)
                        else
                            -- Horizontal bar: goes BELOW Utility
                            local rowWidth = utilityViewer.__cdmBottomRowWidth or utilityViewer.__cdmIconWidth or 300
                            local barHeight = secondary.height or 8
                            local targetWidth = rowWidth + (2 * bottomRowBorderSize) - (2 * barBorderSize)
                            local cdmVisualBottom = utilityCenterY - (totalHeight / 2) - bottomRowBorderSize
                            local powerBarCenterY = cdmVisualBottom - (barHeight / 2) - barBorderSize
                            secondary.lockedBaseY = math.floor(powerBarCenterY - screenCenterY + 0.5) + 1
                            secondary.lockedBaseX = math.floor(utilityCenterX - screenCenterX + 0.5)
                            secondary.width = math.floor(targetWidth + 0.5)
                        end
                        secondary.offsetX = 0  -- Reset user adjustment
                        secondary.offsetY = 0
                        secondary.autoAttach = false
                        secondary.useRawPixels = true
                        secondary.lockedToUtility = true
                        secondary.lockedToEssential = false
                        secondary.lockedToPrimary = false
                        RefreshPowerBars()
                        UpdateSecLockButtonStates()
                        if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                        if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                    else
                        print("|cFF56D1FFQUI:|r Could not get screen positions. Try again.")
                    end
                else
                    print("|cFF56D1FFQUI:|r Utility Cooldowns viewer not found or not visible.")
                end
            end
        end)

        -- Lock to Primary click handler
        lockSecPrimaryBtn:SetScript("OnClick", function()
            if secondary.lockedToPrimary then
                secondary.lockedToPrimary = false
                UpdateSecLockButtonStates()
            else
                local QUICore = _G.QUI and _G.QUI.QUICore
                local primaryBar = QUICore and QUICore.powerBar
                local primaryCfg = QUICore and QUICore.db and QUICore.db.profile.powerBar
                if primaryBar and primaryBar:IsShown() and primaryCfg then
                    local primaryCenterX, primaryCenterY = primaryBar:GetCenter()
                    local screenCenterX, screenCenterY = UIParent:GetCenter()
                    if primaryCenterX and primaryCenterY and screenCenterX and screenCenterY then
                        primaryCenterX = math.floor(primaryCenterX + 0.5)
                        primaryCenterY = math.floor(primaryCenterY + 0.5)
                        screenCenterX = math.floor(screenCenterX + 0.5)
                        screenCenterY = math.floor(screenCenterY + 0.5)
                        local primaryHeight = primaryCfg.height or 8
                        local primaryWidth = primaryCfg.width or primaryBar:GetWidth() or 300
                        local primaryBorderSize = primaryCfg.borderSize or 1
                        local secondaryHeight = secondary.height or 8
                        local secondaryBorderSize = secondary.borderSize or 1
                        local isVertical = secondary.orientation == "VERTICAL"

                        if isVertical then
                            local primaryActualWidth = primaryBar:GetWidth()
                            local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                            secondary.width = math.floor(targetWidth + 0.5)
                        else
                            local targetWidth = primaryWidth + (2 * primaryBorderSize) - (2 * secondaryBorderSize)
                            secondary.width = math.floor(targetWidth + 0.5)
                        end
                    end

                    -- Reset user adjustment (base position is calculated live from primary bar)
                    secondary.offsetX = 0
                    secondary.offsetY = 0
                    secondary.lockedToPrimary = true
                    secondary.lockedToEssential = false
                    secondary.lockedToUtility = false
                    secondary.autoAttach = false
                    secondary.useRawPixels = true
                    RefreshPowerBars()
                    UpdateSecLockButtonStates()
                    if widthSecondarySlider and widthSecondarySlider.SetValue then widthSecondarySlider.SetValue(secondary.width, true) end
                    if yOffsetSecondarySlider and yOffsetSecondarySlider.SetValue then yOffsetSecondarySlider.SetValue(secondary.offsetY, true) end
                else
                    print("|cFF56D1FFQUI:|r Primary Class Resource Bar not found or not visible. Enable it first.")
                end
            end
        end)

        -- Initialize button states
        UpdateSecLockButtonStates()
        y = y - FORM_ROW

        -- Color options (form style) - radio-button behavior: clicking one turns off the others
        local customColorPickerSecondary

        local powerColorSecondary = GUI:CreateFormCheckbox(tabContent, "Use Resource Type Color", "usePowerColor", secondary, function()
            if secondary.usePowerColor then
                secondary.useClassColor = false
                secondary.useCustomColor = false
                secondary.colorMode = "power"
            else
                -- Fallback: if turning off and nothing else is on, re-enable this
                if not secondary.useClassColor and not secondary.useCustomColor then
                    secondary.usePowerColor = true
                end
            end
            if customColorPickerSecondary then
                customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        powerColorSecondary:SetPoint("TOPLEFT", PAD, y)
        powerColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local resourceColorDescSecondary = GUI:CreateLabel(tabContent, "Uses per-resource colors from the Resource Colors section below.", 11)
        resourceColorDescSecondary:SetPoint("TOPLEFT", PAD, y + 4)
        resourceColorDescSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        resourceColorDescSecondary:SetJustifyH("LEFT")
        resourceColorDescSecondary:SetTextColor(0.6, 0.6, 0.6)
        y = y - FORM_ROW

        local classColorSecondary = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", secondary, function()
            if secondary.useClassColor then
                secondary.usePowerColor = false
                secondary.useCustomColor = false
                secondary.colorMode = "class"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not secondary.usePowerColor and not secondary.useCustomColor then
                    secondary.usePowerColor = true
                end
            end
            if customColorPickerSecondary then
                customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        classColorSecondary:SetPoint("TOPLEFT", PAD, y)
        classColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local bgColorSecondary = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", secondary, RefreshPowerBars)
        bgColorSecondary:SetPoint("TOPLEFT", PAD, y)
        bgColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local customColorOverrideSecondary = GUI:CreateFormCheckbox(tabContent, "Custom Color Override", "useCustomColor", secondary, function()
            if secondary.useCustomColor then
                secondary.usePowerColor = false
                secondary.useClassColor = false
                secondary.colorMode = "custom"
            else
                -- Fallback: if turning off and nothing else is on, enable Resource Type Color
                if not secondary.usePowerColor and not secondary.useClassColor then
                    secondary.usePowerColor = true
                end
            end
            if customColorPickerSecondary then
                customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
            end
            RefreshPowerBars()
        end)
        customColorOverrideSecondary:SetPoint("TOPLEFT", PAD, y)
        customColorOverrideSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        customColorPickerSecondary = GUI:CreateFormColorPicker(tabContent, "Custom Color", "customColor", secondary, RefreshPowerBars)
        customColorPickerSecondary:SetPoint("TOPLEFT", PAD, y)
        customColorPickerSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        customColorPickerSecondary:SetEnabled(secondary.useCustomColor)
        y = y - FORM_ROW

        -- Text display options
        local showTextSecondary = GUI:CreateFormCheckbox(tabContent, "Show Number", "showText", secondary, RefreshPowerBars)
        showTextSecondary:SetPoint("TOPLEFT", PAD, y)
        showTextSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showPercentSecondary = GUI:CreateFormCheckbox(tabContent, "Show as Percent", "showPercent", secondary, RefreshPowerBars)
        showPercentSecondary:SetPoint("TOPLEFT", PAD, y)
        showPercentSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local showRuneTextSecondary = GUI:CreateFormCheckbox(tabContent, "Show Rune CD Text (DKs)", "showFragmentedPowerBarText", secondary, RefreshPowerBars)
        showRuneTextSecondary:SetPoint("TOPLEFT", PAD, y)
        showRuneTextSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        local _, playerClass = UnitClass("player")
        showRuneTextSecondary:SetEnabled(playerClass == "DEATHKNIGHT")
        y = y - FORM_ROW

        -- Tick marks
        local showTicksSecondary = GUI:CreateFormCheckbox(tabContent, "Show Tick Marks", "showTicks", secondary, RefreshPowerBars)
        showTicksSecondary:SetPoint("TOPLEFT", PAD, y)
        showTicksSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickThicknessSecondary = GUI:CreateFormSlider(tabContent, "Tick Thickness", 1, 4, 1, "tickThickness", secondary, RefreshPowerBars)
        tickThicknessSecondary:SetPoint("TOPLEFT", PAD, y)
        tickThicknessSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tickColorSecondary = GUI:CreateFormColorPicker(tabContent, "Tick Color", "tickColor", secondary, RefreshPowerBars)
        tickColorSecondary:SetPoint("TOPLEFT", PAD, y)
        tickColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Size sliders (form style)
        widthSecondarySlider = GUI:CreateFormSlider(tabContent, "Width", 0, 2000, 1, "width", secondary, RefreshPowerBars)
        widthSecondarySlider:SetPoint("TOPLEFT", PAD, y)
        widthSecondarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local heightSecondary = GUI:CreateFormSlider(tabContent, "Height", 1, 100, 1, "height", secondary, RefreshPowerBars)
        heightSecondary:SetPoint("TOPLEFT", PAD, y)
        heightSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSecondary = GUI:CreateFormSlider(tabContent, "Border Size", 0, 8, 1, "borderSize", secondary, RefreshPowerBars)
        borderSecondary:SetPoint("TOPLEFT", PAD, y)
        borderSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Position sliders
        local xOffsetSecondarySlider = GUI:CreateFormSlider(tabContent, "X Offset", -1000, 1000, 1, "offsetX", secondary, RefreshPowerBars)
        xOffsetSecondarySlider:SetPoint("TOPLEFT", PAD, y)
        xOffsetSecondarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        yOffsetSecondarySlider = GUI:CreateFormSlider(tabContent, "Y Offset", -1000, 1000, 1, "offsetY", secondary, RefreshPowerBars)
        yOffsetSecondarySlider:SetPoint("TOPLEFT", PAD, y)
        yOffsetSecondarySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Register sliders for real-time sync during Edit Mode
        if _G.QUI and _G.QUI.QUICore and _G.QUI.QUICore.RegisterPowerBarEditModeSliders then
            _G.QUI.QUICore:RegisterPowerBarEditModeSliders("secondary", xOffsetSecondarySlider, yOffsetSecondarySlider)
        end

        -- Text sliders
        local textSizeSecondary = GUI:CreateFormSlider(tabContent, "Text Size", 8, 50, 1, "textSize", secondary, RefreshPowerBars)
        textSizeSecondary:SetPoint("TOPLEFT", PAD, y)
        textSizeSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textXSecondary = GUI:CreateFormSlider(tabContent, "Text X Offset", -500, 500, 1, "textX", secondary, RefreshPowerBars)
        textXSecondary:SetPoint("TOPLEFT", PAD, y)
        textXSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local textYSecondary = GUI:CreateFormSlider(tabContent, "Text Y Offset", -500, 500, 1, "textY", secondary, RefreshPowerBars)
        textYSecondary:SetPoint("TOPLEFT", PAD, y)
        textYSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Text color settings
        local textCustomColorSecondary  -- Forward declare for mutual reference

        local textUseClassColorSecondary = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Text", "textUseClassColor", secondary, function()
            if textCustomColorSecondary then
                textCustomColorSecondary:SetEnabled(not secondary.textUseClassColor)
            end
            RefreshPowerBars()
        end)
        textUseClassColorSecondary:SetPoint("TOPLEFT", PAD, y)
        textUseClassColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        textCustomColorSecondary = GUI:CreateFormColorPicker(tabContent, "Custom Text Color", "textCustomColor", secondary, RefreshPowerBars)
        textCustomColorSecondary:SetPoint("TOPLEFT", PAD, y)
        textCustomColorSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textCustomColorSecondary:SetEnabled(not secondary.textUseClassColor)  -- Initial state
        y = y - FORM_ROW

        local textureSecondary = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", secondary, RefreshPowerBars)
        textureSecondary:SetPoint("TOPLEFT", PAD, y)
        textureSecondary:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- =====================================================
        -- POWER COLORS (Global - affects both bars)
        -- =====================================================
        y = y - 20  -- Spacer between sections

        local powerColorsHeader = GUI:CreateSectionHeader(tabContent, "Reset Resource Bar Colors To Default")
        powerColorsHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - powerColorsHeader.gap

        -- Get powerColors DB table
        local pc = db.powerColors
        if not pc then
            db.powerColors = {}
            pc = db.powerColors
        end

        -- Default power colors (used for Reset button)
        local defaultPowerColors = {
            rage = { 1.00, 0.00, 0.00, 1 },
            energy = { 1.00, 1.00, 0.00, 1 },
            mana = { 0.00, 0.00, 1.00, 1 },
            focus = { 1.00, 0.50, 0.25, 1 },
            runicPower = { 0.00, 0.82, 1.00, 1 },
            fury = { 0.79, 0.26, 0.99, 1 },
            insanity = { 0.40, 0.00, 0.80, 1 },
            maelstrom = { 0.00, 0.50, 1.00, 1 },
            lunarPower = { 0.30, 0.52, 0.90, 1 },
            holyPower = { 0.95, 0.90, 0.60, 1 },
            chi = { 0.00, 1.00, 0.59, 1 },
            comboPoints = { 1.00, 0.96, 0.41, 1 },
            soulShards = { 0.58, 0.51, 0.79, 1 },
            arcaneCharges = { 0.10, 0.10, 0.98, 1 },
            essence = { 0.20, 0.58, 0.50, 1 },
            stagger = { 0.00, 1.00, 0.59, 1 },
            soulFragments = { 0.64, 0.19, 0.79, 1 },
            runes = { 0.77, 0.12, 0.23, 1 },
            bloodRunes = { 0.77, 0.12, 0.23, 1 },
            frostRunes = { 0.00, 0.82, 1.00, 1 },
            unholyRunes = { 0.00, 0.80, 0.00, 1 },
        }

        -- Initialize defaults if missing
        for key, value in pairs(defaultPowerColors) do
            if pc[key] == nil then pc[key] = {value[1], value[2], value[3], value[4]} end
        end

        -- Store widget references for Reset button
        local powerColorWidgets = {}

        -- Reset to Defaults button
        local resetPowerColorsContainer = CreateFrame("Frame", nil, tabContent)
        resetPowerColorsContainer:SetHeight(FORM_ROW)
        resetPowerColorsContainer:SetPoint("TOPLEFT", PAD, y)
        resetPowerColorsContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local resetPowerColorsLabel = resetPowerColorsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resetPowerColorsLabel:SetPoint("LEFT", 0, 0)
        resetPowerColorsLabel:SetText("Reset Colors")
        resetPowerColorsLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local resetPowerColorsBtn = CreateFrame("Button", nil, resetPowerColorsContainer, "BackdropTemplate")
        resetPowerColorsBtn:SetSize(140, 24)
        resetPowerColorsBtn:SetPoint("LEFT", resetPowerColorsContainer, "LEFT", 180, 0)
        resetPowerColorsBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        resetPowerColorsBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        resetPowerColorsBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local resetPowerColorsText = resetPowerColorsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        resetPowerColorsText:SetPoint("CENTER")
        resetPowerColorsText:SetText("Reset to Defaults")
        resetPowerColorsText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        resetPowerColorsBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        resetPowerColorsBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        resetPowerColorsBtn:SetScript("OnClick", function()
            for key, value in pairs(defaultPowerColors) do
                pc[key] = {value[1], value[2], value[3], value[4]}
            end
            -- Refresh color swatches
            for _, widget in ipairs(powerColorWidgets) do
                if widget.swatch and pc[widget.dbKey] then
                    local col = pc[widget.dbKey]
                    widget.swatch:SetBackdropColor(col[1], col[2], col[3], col[4] or 1)
                end
            end
            RefreshPowerBars()
            print("|cFF56D1FFQUI:|r Resource colors reset to defaults.")
        end)
        y = y - FORM_ROW

        -- =====================================================
        -- SUB-SECTION: Core Resources
        -- =====================================================
        y = y - 8
        local coreHeader = GUI:CreateSectionHeader(tabContent, "Bar Colors for Core Resources")
        coreHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - coreHeader.gap

        local rageColor = GUI:CreateFormColorPicker(tabContent, "Rage", "rage", pc, RefreshPowerBars)
        rageColor:SetPoint("TOPLEFT", PAD, y)
        rageColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        rageColor.dbKey = "rage"
        table.insert(powerColorWidgets, rageColor)
        y = y - FORM_ROW

        local energyColor = GUI:CreateFormColorPicker(tabContent, "Energy", "energy", pc, RefreshPowerBars)
        energyColor:SetPoint("TOPLEFT", PAD, y)
        energyColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        energyColor.dbKey = "energy"
        table.insert(powerColorWidgets, energyColor)
        y = y - FORM_ROW

        local manaColor = GUI:CreateFormColorPicker(tabContent, "Mana", "mana", pc, RefreshPowerBars)
        manaColor:SetPoint("TOPLEFT", PAD, y)
        manaColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        manaColor.dbKey = "mana"
        table.insert(powerColorWidgets, manaColor)
        y = y - FORM_ROW

        local focusColor = GUI:CreateFormColorPicker(tabContent, "Focus", "focus", pc, RefreshPowerBars)
        focusColor:SetPoint("TOPLEFT", PAD, y)
        focusColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        focusColor.dbKey = "focus"
        table.insert(powerColorWidgets, focusColor)
        y = y - FORM_ROW

        local runicPowerColor = GUI:CreateFormColorPicker(tabContent, "Runic Power", "runicPower", pc, RefreshPowerBars)
        runicPowerColor:SetPoint("TOPLEFT", PAD, y)
        runicPowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        runicPowerColor.dbKey = "runicPower"
        table.insert(powerColorWidgets, runicPowerColor)
        y = y - FORM_ROW

        local furyColor = GUI:CreateFormColorPicker(tabContent, "Fury", "fury", pc, RefreshPowerBars)
        furyColor:SetPoint("TOPLEFT", PAD, y)
        furyColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        furyColor.dbKey = "fury"
        table.insert(powerColorWidgets, furyColor)
        y = y - FORM_ROW

        local insanityColor = GUI:CreateFormColorPicker(tabContent, "Insanity", "insanity", pc, RefreshPowerBars)
        insanityColor:SetPoint("TOPLEFT", PAD, y)
        insanityColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        insanityColor.dbKey = "insanity"
        table.insert(powerColorWidgets, insanityColor)
        y = y - FORM_ROW

        local maelstromColor = GUI:CreateFormColorPicker(tabContent, "Maelstrom", "maelstrom", pc, RefreshPowerBars)
        maelstromColor:SetPoint("TOPLEFT", PAD, y)
        maelstromColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        maelstromColor.dbKey = "maelstrom"
        table.insert(powerColorWidgets, maelstromColor)
        y = y - FORM_ROW

        local lunarPowerColor = GUI:CreateFormColorPicker(tabContent, "Astral Power", "lunarPower", pc, RefreshPowerBars)
        lunarPowerColor:SetPoint("TOPLEFT", PAD, y)
        lunarPowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        lunarPowerColor.dbKey = "lunarPower"
        table.insert(powerColorWidgets, lunarPowerColor)
        y = y - FORM_ROW

        -- =====================================================
        -- SUB-SECTION: Builder Resources
        -- =====================================================
        y = y - 8
        local builderHeader = GUI:CreateSectionHeader(tabContent, "Bar Colors for Builder Resources")
        builderHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - builderHeader.gap

        local holyPowerColor = GUI:CreateFormColorPicker(tabContent, "Holy Power", "holyPower", pc, RefreshPowerBars)
        holyPowerColor:SetPoint("TOPLEFT", PAD, y)
        holyPowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        holyPowerColor.dbKey = "holyPower"
        table.insert(powerColorWidgets, holyPowerColor)
        y = y - FORM_ROW

        local chiColor = GUI:CreateFormColorPicker(tabContent, "Chi", "chi", pc, RefreshPowerBars)
        chiColor:SetPoint("TOPLEFT", PAD, y)
        chiColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        chiColor.dbKey = "chi"
        table.insert(powerColorWidgets, chiColor)
        y = y - FORM_ROW

        local comboPointsColor = GUI:CreateFormColorPicker(tabContent, "Combo Points", "comboPoints", pc, RefreshPowerBars)
        comboPointsColor:SetPoint("TOPLEFT", PAD, y)
        comboPointsColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        comboPointsColor.dbKey = "comboPoints"
        table.insert(powerColorWidgets, comboPointsColor)
        y = y - FORM_ROW

        local soulShardsColor = GUI:CreateFormColorPicker(tabContent, "Soul Shards", "soulShards", pc, RefreshPowerBars)
        soulShardsColor:SetPoint("TOPLEFT", PAD, y)
        soulShardsColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        soulShardsColor.dbKey = "soulShards"
        table.insert(powerColorWidgets, soulShardsColor)
        y = y - FORM_ROW

        local arcaneChargesColor = GUI:CreateFormColorPicker(tabContent, "Arcane Charges", "arcaneCharges", pc, RefreshPowerBars)
        arcaneChargesColor:SetPoint("TOPLEFT", PAD, y)
        arcaneChargesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        arcaneChargesColor.dbKey = "arcaneCharges"
        table.insert(powerColorWidgets, arcaneChargesColor)
        y = y - FORM_ROW

        local essenceColor = GUI:CreateFormColorPicker(tabContent, "Essence", "essence", pc, RefreshPowerBars)
        essenceColor:SetPoint("TOPLEFT", PAD, y)
        essenceColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        essenceColor.dbKey = "essence"
        table.insert(powerColorWidgets, essenceColor)
        y = y - FORM_ROW

        -- =====================================================
        -- SUB-SECTION: Specialized Resources
        -- =====================================================
        y = y - 8
        local specialHeader = GUI:CreateSectionHeader(tabContent, "Bar Colors for Specialized Resources")
        specialHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - specialHeader.gap

        local staggerColor = GUI:CreateFormColorPicker(tabContent, "Stagger (Fallback)", "stagger", pc, RefreshPowerBars)
        staggerColor:SetPoint("TOPLEFT", PAD, y)
        staggerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerColor.dbKey = "stagger"
        table.insert(powerColorWidgets, staggerColor)
        y = y - FORM_ROW

        local useStaggerLevels = GUI:CreateFormCheckbox(tabContent, "Use Stagger Level Colors", "useStaggerLevelColors", pc, RefreshPowerBars)
        useStaggerLevels:SetPoint("TOPLEFT", PAD, y)
        useStaggerLevels:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local staggerLightColor = GUI:CreateFormColorPicker(tabContent, "Stagger - Light (0-30%)", "staggerLight", pc, RefreshPowerBars)
        staggerLightColor:SetPoint("TOPLEFT", PAD, y)
        staggerLightColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerLightColor.dbKey = "staggerLight"
        table.insert(powerColorWidgets, staggerLightColor)
        y = y - FORM_ROW

        local staggerModerateColor = GUI:CreateFormColorPicker(tabContent, "Stagger - Moderate (30-60%)", "staggerModerate", pc, RefreshPowerBars)
        staggerModerateColor:SetPoint("TOPLEFT", PAD, y)
        staggerModerateColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerModerateColor.dbKey = "staggerModerate"
        table.insert(powerColorWidgets, staggerModerateColor)
        y = y - FORM_ROW

        local staggerHeavyColor = GUI:CreateFormColorPicker(tabContent, "Stagger - Heavy (60%+)", "staggerHeavy", pc, RefreshPowerBars)
        staggerHeavyColor:SetPoint("TOPLEFT", PAD, y)
        staggerHeavyColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        staggerHeavyColor.dbKey = "staggerHeavy"
        table.insert(powerColorWidgets, staggerHeavyColor)
        y = y - FORM_ROW

        local soulFragmentsColor = GUI:CreateFormColorPicker(tabContent, "Soul Fragments", "soulFragments", pc, RefreshPowerBars)
        soulFragmentsColor:SetPoint("TOPLEFT", PAD, y)
        soulFragmentsColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        soulFragmentsColor.dbKey = "soulFragments"
        table.insert(powerColorWidgets, soulFragmentsColor)
        y = y - FORM_ROW

        local runesColor = GUI:CreateFormColorPicker(tabContent, "Runes (Generic)", "runes", pc, RefreshPowerBars)
        runesColor:SetPoint("TOPLEFT", PAD, y)
        runesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        runesColor.dbKey = "runes"
        table.insert(powerColorWidgets, runesColor)
        y = y - FORM_ROW

        local bloodRunesColor = GUI:CreateFormColorPicker(tabContent, "Blood Runes", "bloodRunes", pc, RefreshPowerBars)
        bloodRunesColor:SetPoint("TOPLEFT", PAD, y)
        bloodRunesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        bloodRunesColor.dbKey = "bloodRunes"
        table.insert(powerColorWidgets, bloodRunesColor)
        y = y - FORM_ROW

        local frostRunesColor = GUI:CreateFormColorPicker(tabContent, "Frost Runes", "frostRunes", pc, RefreshPowerBars)
        frostRunesColor:SetPoint("TOPLEFT", PAD, y)
        frostRunesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        frostRunesColor.dbKey = "frostRunes"
        table.insert(powerColorWidgets, frostRunesColor)
        y = y - FORM_ROW

        local unholyRunesColor = GUI:CreateFormColorPicker(tabContent, "Unholy Runes", "unholyRunes", pc, RefreshPowerBars)
        unholyRunesColor:SetPoint("TOPLEFT", PAD, y)
        unholyRunesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        unholyRunesColor.dbKey = "unholyRunes"
        table.insert(powerColorWidgets, unholyRunesColor)
        y = y - FORM_ROW

        -- Extra padding at bottom for dropdown menus to expand into
        tabContent:SetHeight(math.abs(y) + 60)
    end

    -- Create sub-tabs
    local subTabs = GUI:CreateSubTabs(content, {
        {name = "Essential", builder = BuildEssentialTab},
        {name = "Utility", builder = BuildUtilityTab},
        {name = "Buff", builder = BuildBuffTab},
        {name = "Class Resource Bar", builder = BuildPowerbarTab},
    })
    subTabs:SetPoint("TOPLEFT", 5, -5)
    subTabs:SetPoint("TOPRIGHT", -5, -5)
    subTabs:SetHeight(700)

    content:SetHeight(750)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_NCDMOptions = {
    CreateCDMSetupPage = CreateCDMSetupPage,
    EnsureNCDMDefaults = EnsureNCDMDefaults,
    RefreshNCDM = RefreshNCDM,
}
