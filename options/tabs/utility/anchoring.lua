--[[
    QUI Anchoring Options Module
    Reusable UI components for anchoring and snapping options
    Provides anchor dropdown, snap buttons, and offset controls
]]

local ADDON_NAME, ns = ...

local QUICore = ns.Addon

local function GetPixelSizeOrDefault(frame, default)
    local fallback = default or 1
    if QUICore and QUICore.GetPixelSize then
        local px = QUICore:GetPixelSize(frame)
        if type(px) == "number" and px > 0 then
            return px
        end
    end
    return fallback
end

local QUI_Anchoring_Options = {}
ns.QUI_Anchoring_Options = QUI_Anchoring_Options

-- Helper to get GUI (lazy load to avoid initialization order issues)
local function GetGUI()
    local QUI = _G.QUI
    if QUI and QUI.GUI then
        return QUI.GUI
    end
    return nil
end

-- Helper to get Colors (lazy load)
local function GetColors()
    local GUI = GetGUI()
    if GUI and GUI.Colors then
        return GUI.Colors
    end
    -- Fallback colors if GUI not available
    return {
        text = {1, 1, 1},
        border = {0.3, 0.3, 0.3},
        accent = {0.2, 0.6, 1}
    }
end

---------------------------------------------------------------------------
-- CREATE ANCHOR DROPDOWN
-- Parameters:
--   parent: Parent frame
--   label: Label text
--   settingsDB: Settings database table
--   anchorKey: Key name in settingsDB for anchor value (e.g., "anchor", "anchorTo")
--   x, y: Position
--   width: Width (optional, defaults to full width minus padding)
--   onChange: Callback function when value changes
--   includeList: Optional list of anchor values to include
--   excludeList: Optional list of anchor values to exclude
-- Returns: dropdown widget
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateAnchorDropdown(parent, label, settingsDB, anchorKey, x, y, width, onChange, includeList, excludeList, excludeSelf)
    if not ns.QUI_Anchoring or not ns.QUI_Anchoring.GetAnchorTargetList then
        return nil
    end
    
    local GUI = GetGUI()
    if not GUI then
        return nil
    end
    
    -- Get anchor options list (support dynamic options via function)
    local function GetAnchorOptions()
        return ns.QUI_Anchoring:GetAnchorTargetList(includeList, excludeList, excludeSelf)
    end
    local anchorOptions = GetAnchorOptions()
    
    -- Create dropdown using GUI helper (pass optionsFunction for dynamic updates)
    local dropdown = GUI:CreateFormDropdown(parent, label, anchorOptions, anchorKey, settingsDB, onChange, nil, nil, GetAnchorOptions)
    
    if x and y then
        dropdown:SetPoint("TOPLEFT", x, y)
    end
    
    if width then
        dropdown:SetPoint("RIGHT", parent, "RIGHT", -x or 0, 0)
    end
    
    return dropdown
end

---------------------------------------------------------------------------
-- CREATE SNAP BUTTON
-- Parameters:
--   parent: Parent frame
--   text: Button text
--   x, y: Position
--   width: Button width (default: 100)
--   height: Button height (default: 24)
--   onClick: Click handler function
-- Returns: button widget
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateSnapButton(parent, text, x, y, width, height, onClick)
    width = width or 100
    height = height or 24
    
    local C = GetColors()
    
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    if x and y then
        button:SetPoint("TOPLEFT", x, y)
    end
    
    local pxBtn = GetPixelSizeOrDefault(button, 1)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = pxBtn
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 1)
    button:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    
    local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonText:SetPoint("CENTER")
    buttonText:SetText(text)
    buttonText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
    
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    
    return button
end

---------------------------------------------------------------------------
-- CREATE SNAP BUTTONS ROW
-- Parameters:
--   parent: Parent frame
--   label: Label text
--   x, y: Position
--   snapTargets: Array of {text, anchorTarget, anchorPoint, offsetX, offsetY, setWidth, clearWidth, width} for each button
--   settingsDB: Settings database table
--   anchorKey: Key name in settingsDB for anchor value
--   getFrame: Function that returns the frame to snap (called when button is clicked)
--   onSnap: Callback function called after successful snap (receives anchorTarget)
--   onFailure: Optional callback for failure messages (receives error message string)
--   spacing: Spacing between buttons (default: 8)
--   buttonWidth: Button width (default: 100)
--   buttonHeight: Button height (default: 24)
--   labelWidth: Width reserved for label (default: 180)
-- Returns: container frame and array of buttons
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateSnapButtonsRow(parent, label, x, y, snapTargets, settingsDB, anchorKey, getFrame, onSnap, onFailure, spacing, buttonWidth, buttonHeight, labelWidth)
    spacing = spacing or 8
    buttonWidth = buttonWidth or 100
    buttonHeight = buttonHeight or 24
    labelWidth = labelWidth or 180
    
    local C = GetColors()
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(buttonHeight)
    if x and y then
        container:SetPoint("TOPLEFT", x, y)
    end
    container:SetPoint("RIGHT", parent, "RIGHT", -x or 0, 0)
    
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetText(label)
    labelText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    
    local buttons = {}
    
    for i, snapTarget in ipairs(snapTargets) do
        local button = self:CreateSnapButton(
            container,
            snapTarget.text,
            labelWidth + (i - 1) * (buttonWidth + spacing),
            0,
            buttonWidth,
            buttonHeight,
            function()
                if not ns.QUI_Anchoring then
                    if onFailure then
                        onFailure("Anchoring system not available")
                    end
                    return
                end
                
                -- Get the frame to snap
                local frame = getFrame and getFrame() or nil
                
                if not frame then
                    if onFailure then
                        onFailure("Frame not found")
                    end
                    return
                end
                
                -- Use anchoring module's SnapTo function
                local success = ns.QUI_Anchoring:SnapTo(
                    frame,
                    snapTarget.anchorTarget,
                    snapTarget.anchorPoint,
                    snapTarget.offsetX or 0,
                    snapTarget.offsetY or 0,
                    {
                        checkVisible = snapTarget.checkVisible ~= false,
                        setWidth = snapTarget.setWidth,
                        clearWidth = snapTarget.clearWidth,
                        onSuccess = function()
                            -- Update settings
                            settingsDB[anchorKey] = snapTarget.anchorTarget
                            if snapTarget.offsetX ~= nil then
                                settingsDB.offsetX = snapTarget.offsetX
                            end
                            if snapTarget.offsetY ~= nil then
                                settingsDB.offsetY = snapTarget.offsetY
                            end
                            if snapTarget.setWidth then
                                settingsDB.width = snapTarget.width or 0
                            end
                            if snapTarget.clearWidth then
                                settingsDB.width = 0
                            end
                            
                            if onSnap then
                                onSnap(snapTarget.anchorTarget)
                            end
                        end,
                        onFailure = onFailure
                    }
                )
            end
        )
        
        table.insert(buttons, button)
    end
    
    return container, buttons
end

---------------------------------------------------------------------------
-- GET NINE POINT ANCHOR OPTIONS
-- Returns the standard 9-point anchor options array
---------------------------------------------------------------------------
function QUI_Anchoring_Options:GetNinePointAnchorOptions()
    return {
        {value = "TOPLEFT", text = "Top Left"},
        {value = "TOP", text = "Top Center"},
        {value = "TOPRIGHT", text = "Top Right"},
        {value = "LEFT", text = "Center Left"},
        {value = "CENTER", text = "Center"},
        {value = "RIGHT", text = "Center Right"},
        {value = "BOTTOMLEFT", text = "Bottom Left"},
        {value = "BOTTOM", text = "Bottom Center"},
        {value = "BOTTOMRIGHT", text = "Bottom Right"},
    }
end

---------------------------------------------------------------------------
-- CREATE ANCHOR POINT SELECTOR WIDGET
-- Creates a visual grid-based anchor point selector
-- Parameters:
--   parent: Parent frame
--   label: Label text
--   settingsDB: Settings database table
--   key: Key name in settingsDB for anchor point value
--   x, y: Position
--   onChange: Callback function when value changes
--   size: Size of the selector widget (default: 200)
-- Returns: selector widget frame
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateAnchorPointSelector(parent, label, settingsDB, key, x, y, onChange, size)
    size = size or 200
    local C = GetColors()
    
    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(size, size + 30) -- Extra height for label
    
    if x and y then
        container:SetPoint("TOPLEFT", x, y)
    end
    
    -- Label
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT", 0, 0)
    labelText:SetText(label)
    labelText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    
    -- Grid container
    local gridSize = size
    local cellSize = gridSize / 3
    local grid = CreateFrame("Frame", nil, container, "BackdropTemplate")
    grid:SetSize(gridSize, gridSize)
    grid:SetPoint("TOPLEFT", 0, -25)
    local px = GetPixelSizeOrDefault(grid, 1)
    grid:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = {left = px, right = px, top = px, bottom = px}
    })
    grid:SetBackdropColor(0.1, 0.1, 0.1, 1)
    grid:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.5)
    
    -- Anchor point mapping: [row][col] = anchorPoint
    local anchorPoints = {
        {"TOPLEFT", "TOP", "TOPRIGHT"},
        {"LEFT", "CENTER", "RIGHT"},
        {"BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"},
    }
    
    -- Create cells
    local cells = {}
    for row = 1, 3 do
        cells[row] = {}
        for col = 1, 3 do
            local cell = CreateFrame("Button", nil, grid, "BackdropTemplate")
            cell:SetSize(cellSize - 2, cellSize - 2)
            cell:SetPoint("TOPLEFT", grid, "TOPLEFT", (col - 1) * cellSize + 1, -(row - 1) * cellSize - 1)

            local pxCell = GetPixelSizeOrDefault(cell, 1)
            cell:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = pxCell,
            })
            cell:SetBackdropColor(0.15, 0.15, 0.15, 1)
            cell:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.3)
            
            -- Visual indicator (small square representing the anchor point)
            local indicator = cell:CreateTexture(nil, "OVERLAY")
            indicator:SetSize(cellSize * 0.3, cellSize * 0.3)
            
            local anchorPoint = anchorPoints[row][col]
            local offsetX, offsetY = 0, 0
            
            -- Position indicator based on anchor point
            if anchorPoint:find("LEFT") then
                offsetX = cellSize * 0.15
            elseif anchorPoint:find("RIGHT") then
                offsetX = cellSize * 0.55
            else
                offsetX = cellSize * 0.35
            end
            
            if anchorPoint:find("TOP") then
                offsetY = -cellSize * 0.15
            elseif anchorPoint:find("BOTTOM") then
                offsetY = -cellSize * 0.55
            else
                offsetY = -cellSize * 0.35
            end
            
            indicator:SetPoint("TOPLEFT", cell, "TOPLEFT", offsetX, offsetY)
            indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
            
            -- Store anchor point and indicator reference
            cell.anchorPoint = anchorPoint
            cell.indicator = indicator
            
            -- Hover effects
            cell:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            end)
            
            cell:SetScript("OnLeave", function(self)
                local currentValue = settingsDB[key]
                if currentValue == self.anchorPoint then
                    self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    if self.indicator then
                        self.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
                    end
                else
                    self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.3)
                    if self.indicator then
                        self.indicator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
                    end
                end
            end)
            
            -- Store reference to cells table for UpdateSelection
            cell.cells = cells
            cell.settingsDB = settingsDB
            cell.key = key
            cell.C = C
            
            -- Update selection visual (updates all cells)
            cell.UpdateSelection = function(self)
                local currentValue = self.settingsDB[self.key]
                for r = 1, 3 do
                    for c = 1, 3 do
                        local cellFrame = self.cells[r][c]
                        if cellFrame.anchorPoint == currentValue then
                            cellFrame:SetBackdropBorderColor(self.C.accent[1], self.C.accent[2], self.C.accent[3], 1)
                            cellFrame:SetBackdropColor(0.2, 0.2, 0.2, 1)
                            if cellFrame.indicator then
                                cellFrame.indicator:SetColorTexture(self.C.accent[1], self.C.accent[2], self.C.accent[3], 0.8)
                            end
                        else
                            cellFrame:SetBackdropBorderColor(self.C.border[1], self.C.border[2], self.C.border[3], 0.3)
                            cellFrame:SetBackdropColor(0.15, 0.15, 0.15, 1)
                            if cellFrame.indicator then
                                cellFrame.indicator:SetColorTexture(self.C.accent[1], self.C.accent[2], self.C.accent[3], 0.6)
                            end
                        end
                    end
                end
            end
            
            -- Click handler
            cell:SetScript("OnClick", function(self)
                self.settingsDB[self.key] = self.anchorPoint
                self:UpdateSelection()
                if onChange then
                    onChange()
                end
            end)
            
            cells[row][col] = cell
        end
    end
    
    -- Initialize selection (use first cell's UpdateSelection to update all)
    if settingsDB[key] and cells[1][1] then
        cells[1][1]:UpdateSelection()
    end
    
    -- Store cells and update function for external access
    container.cells = cells
    container.UpdateSelection = function(self)
        if cells[1][1] then
            cells[1][1]:UpdateSelection()
        end
    end
    
    return container
end

---------------------------------------------------------------------------
-- CREATE MULTI-ANCHOR POPOVER
-- Creates a scrollable popover anchored to a button for managing multiple anchor point pairs
-- Parameters:
--   anchorButton: Button frame to anchor the popover to
--   settingsDB: Settings database table
--   onChange: Callback function when values change
--   anchorsKey: Key name for anchors array in settingsDB (default: "anchors")
--   maxAnchors: Maximum number of anchor pairs allowed (default: 2)
-- Returns: popover frame
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateMultiAnchorPopover(anchorButton, settingsDB, onChange, anchorsKey, maxAnchors)
    anchorsKey = anchorsKey or "anchors"
    maxAnchors = maxAnchors or 2
    
    local C = GetColors()
    local GUI = GetGUI()
    if not GUI then return nil end
    
    -- Initialize anchors array if not exists
    if not settingsDB[anchorsKey] then
        settingsDB[anchorsKey] = {
            {source = "BOTTOMLEFT", target = "BOTTOMLEFT"}
        }
    end
    
    -- Create popover frame (anchored to button/container)
    local popover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    -- Calculate size: 2 anchor rows + add button + padding
    -- Each anchor row: selectorSize (75) + 30 (label/spacing) + 8 (padding) = ~113px
    -- 2 rows = 226px, add button = 30px, title = 25px, padding = 15px = ~296px height
    -- Width: 2 selectors (75 each) + spacing + labels + remove button = ~400px
    popover:SetSize(420, 300)
    popover:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", 0, -5)
    popover:SetFrameStrata("FULLSCREEN_DIALOG")
    popover:SetFrameLevel(500)
    local pxPopover = GetPixelSizeOrDefault(popover, 1)
    popover:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = pxPopover,
        insets = {left = 2 * pxPopover, right = 2 * pxPopover, top = 2 * pxPopover, bottom = 2 * pxPopover}
    })
    popover:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.98)
    popover:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    popover:EnableMouse(true)
    popover:SetClampedToScreen(true)
    popover:Hide()
    
    -- Close button in top right
    local closeBtn = GUI:CreateButton(popover, "×", 24, 24, function()
        popover:Hide()
    end)
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    if closeBtn.text then
        local fontPath = GUI.GetFontPath and GUI:GetFontPath() or "Fonts\\FRIZQT__.TTF"
        closeBtn.text:SetFont(fontPath, 16, "")
    end
    
    -- Title text
    local titleText = popover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", 5, -5)
    titleText:SetText("Advanced Anchor Settings")
    titleText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
    
    -- Content area (no scrolling needed for max 2 anchors)
    local content = CreateFrame("Frame", nil, popover)
    content:SetPoint("TOPLEFT", 2, -28)
    content:SetPoint("BOTTOMRIGHT", -2, 2)
    
    -- Create multi-anchor controls inside the content
    local PAD = 5  -- Reduced padding
    local FORM_ROW = 30
    local anchors = settingsDB[anchorsKey]
    local selectorSize = 75
    local spacing = 8  -- Reduced spacing
    local rowHeight = selectorSize + 30
    local currentY = -PAD
    
    -- Store references
    popover.anchors = anchors
    popover.maxAnchors = maxAnchors
    popover.onChange = onChange
    popover.anchorRows = {}
    
    -- Update content height (no scrolling needed for max 2 anchors)
    local function UpdateContentHeight()
        -- Content height is managed by the popover size, no need to set it
    end
    
    -- Function to rebuild all anchor rows
    local function RebuildAnchors()
        -- Clear existing rows
        for i, row in ipairs(popover.anchorRows) do
            if row.frame then
                row.frame:Hide()
                row.frame:SetParent(nil)
            end
        end
        popover.anchorRows = {}
        currentY = -PAD
        
        -- Create rows for each anchor pair with improved styling
        for i, anchor in ipairs(anchors) do
            -- Container frame with background for list item appearance
            local rowFrame = CreateFrame("Frame", nil, content, "BackdropTemplate")
            rowFrame:SetHeight(rowHeight + 8)
            rowFrame:SetPoint("TOPLEFT", PAD, currentY)
            rowFrame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            
            -- Background for list item
            local pxRow = GetPixelSizeOrDefault(rowFrame, 1)
            rowFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = pxRow,
                insets = {left = 2 * pxRow, right = 2 * pxRow, top = 2 * pxRow, bottom = 2 * pxRow}
            })
            rowFrame:SetBackdropColor(C.bg[1] * 1.2, C.bg[2] * 1.2, C.bg[3] * 1.2, 0.5)
            rowFrame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.3)
            
            -- Label for anchor pair number
            local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 5, 0)
            label:SetText("Anchor " .. i)
            label:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
            
            -- Source anchor point selector
            local sourceSelector = self:CreateAnchorPointSelector(
                rowFrame,
                "Source",
                anchor,
                "source",
                70,
                0,
                onChange,
                selectorSize
            )
            
            -- Target anchor point selector
            local targetSelector = self:CreateAnchorPointSelector(
                rowFrame,
                "Target",
                anchor,
                "target",
                70 + selectorSize + spacing,
                0,
                onChange,
                selectorSize
            )
            
            -- Remove button (only show if more than 1 anchor)
            local removeButton
            if #anchors > 1 then
                removeButton = GUI:CreateButton(rowFrame, "×", 24, 24, function()
                    table.remove(anchors, i)
                    RebuildAnchors()
                    UpdateContentHeight()
                    if onChange then onChange() end
                end)
                removeButton:SetPoint("RIGHT", -5, 0)
                if removeButton.text then
                    local fontPath = GUI.GetFontPath and GUI:GetFontPath() or "Fonts\\FRIZQT__.TTF"
                    removeButton.text:SetFont(fontPath, 14, "")
                    removeButton.text:SetTextColor(0.9, 0.3, 0.3, 1) -- Red tint for remove
                end
            end
            
            table.insert(popover.anchorRows, {
                frame = rowFrame,
                sourceSelector = sourceSelector,
                targetSelector = targetSelector,
                removeButton = removeButton
            })
            
            currentY = currentY - (rowHeight + 8) - 3 -- Reduced spacing between items
        end
        
        -- Add button (only show if under max) - styled as a list item
        if #anchors < maxAnchors then
            if not popover.addButton then
                local addButtonFrame = CreateFrame("Frame", nil, content, "BackdropTemplate")
                addButtonFrame:SetHeight(FORM_ROW + 6)
                addButtonFrame:SetPoint("TOPLEFT", PAD, currentY)
                addButtonFrame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
                
                local pxAdd = GetPixelSizeOrDefault(addButtonFrame, 1)
                addButtonFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = pxAdd,
                    insets = {left = 2 * pxAdd, right = 2 * pxAdd, top = 2 * pxAdd, bottom = 2 * pxAdd}
                })
                addButtonFrame:SetBackdropColor(C.bg[1] * 1.1, C.bg[2] * 1.1, C.bg[3] * 1.1, 0.3)
                addButtonFrame:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
                
                popover.addButton = GUI:CreateButton(addButtonFrame, "+ Add Anchor", 100, 22, function()
                    table.insert(anchors, {source = "BOTTOMLEFT", target = "BOTTOMLEFT"})
                    RebuildAnchors()
                    UpdateContentHeight()
                    if onChange then onChange() end
                end)
                popover.addButton:SetPoint("CENTER", 0, 0)
                popover.addButtonFrame = addButtonFrame
            end
            popover.addButtonFrame:SetPoint("TOPLEFT", PAD, currentY)
            popover.addButtonFrame:Show()
            currentY = currentY - (FORM_ROW + 6) - 3
        else
            if popover.addButtonFrame then
                popover.addButtonFrame:Hide()
            end
        end
        
        UpdateContentHeight()
    end
    
    -- Initial build
    RebuildAnchors()
    
    -- Click outside to close
    local clickFrame = CreateFrame("Frame", nil, UIParent)
    clickFrame:SetAllPoints(UIParent)
    clickFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    clickFrame:SetFrameLevel(499)
    clickFrame:EnableMouse(true)
    clickFrame:Hide()
    clickFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            popover:Hide()
        end
    end)
    popover.clickFrame = clickFrame
    
    -- ESC key to close
    popover:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    popover:EnableKeyboard(true)
    
    -- Expose methods
    popover.Show = function(self)
        self:SetShown(true)
        clickFrame:Show()
        -- Reposition relative to anchor (button or container)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", 0, -5)
    end
    
    popover.Hide = function(self)
        self:SetShown(false)
        clickFrame:Hide()
    end
    
    popover.Toggle = function(self)
        if self:IsShown() then
            self:Hide()
        else
            self:Show()
        end
    end
    
    popover.Refresh = function(self)
        RebuildAnchors()
    end
    
    return popover
end

---------------------------------------------------------------------------
-- CREATE ANCHOR PRESET CONTROLS
-- Creates preset buttons and advanced anchor popover
-- Parameters:
--   parent: Parent frame
--   settingsDB: Settings database table
--   x, y: Position
--   onChange: Callback function when values change
--   PAD: Padding constant
--   FORM_ROW: Form row height constant
--   anchorsKey: Key name for anchors array in settingsDB (default: "anchors")
--   maxAnchors: Maximum number of anchor pairs allowed (default: 2)
--   onPresetChange: Optional callback when preset buttons are clicked (for refreshing other UI)
-- Returns: container frame, advanced button, advanced popover, and updated y position
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateAnchorPresetControls(parent, settingsDB, x, y, onChange, PAD, FORM_ROW, anchorsKey, maxAnchors, onPresetChange)
    anchorsKey = anchorsKey or "anchors"
    maxAnchors = maxAnchors or 2
    
    local C = GetColors()
    local GUI = GetGUI()
    if not GUI then return nil, nil, nil, y end
    
    -- Initialize anchors array if not exists
    if not settingsDB[anchorsKey] then
        settingsDB[anchorsKey] = {
            {source = "BOTTOMLEFT", target = "BOTTOMLEFT"}
        }
    end
    
    local anchors = settingsDB[anchorsKey]
    
    -- Preset buttons container
    local presetButtonContainer = CreateFrame("Frame", nil, parent)
    presetButtonContainer:SetHeight(FORM_ROW)
    presetButtonContainer:SetPoint("TOPLEFT", x or PAD, y)
    presetButtonContainer:SetPoint("RIGHT", parent, "RIGHT", -(x or PAD), 0)
    
    local presetLabel = presetButtonContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    presetLabel:SetPoint("LEFT", 0, 0)
    presetLabel:SetText("Anchor point(s):")
    presetLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    
    local buttonWidth = 110
    local buttonSpacing = 8
    
    -- Helper function to apply preset and refresh
    local function ApplyPreset(presetAnchors, refreshPopover)
        while #anchors > 0 do
            table.remove(anchors, 1)
        end
        for _, anchor in ipairs(presetAnchors) do
            table.insert(anchors, anchor)
        end
        -- Reset offset X and Y to 0 when applying presets
        if settingsDB then
            settingsDB.offsetX = 0
            settingsDB.offsetY = 0
            -- Update slider displays to reflect the new values
            -- SetValue is a method, but the function signature expects (val, skipOnChange) not (self, val, skipOnChange)
            -- So we need to update the slider components directly
            if settingsDB._offsetXSlider then
                local container = settingsDB._offsetXSlider
                if container.slider and container.editBox then
                    container.value = 0
                    container.slider:SetValue(0)
                    container.editBox:SetText("0")
                    -- Update track fill
                    if container.trackFill and container.trackContainer then
                        local minVal, maxVal = container.min or -500, container.max or 500
                        local pct = (0 - minVal) / (maxVal - minVal)
                        pct = math.max(0, math.min(1, pct))
                        local trackWidth = container.trackContainer:GetWidth() - 2
                        local fillWidth = math.max(1, pct * trackWidth)
                        container.trackFill:SetWidth(fillWidth)
                        if container.thumbFrame then
                            local thumbX = pct * (trackWidth - 14) + 7
                            container.thumbFrame:ClearAllPoints()
                            container.thumbFrame:SetPoint("CENTER", container.trackContainer, "LEFT", thumbX + 1, 0)
                        end
                    end
                end
            end
            if settingsDB._offsetYSlider then
                local container = settingsDB._offsetYSlider
                if container.slider and container.editBox then
                    container.value = 0
                    container.slider:SetValue(0)
                    container.editBox:SetText("0")
                    -- Update track fill
                    if container.trackFill and container.trackContainer then
                        local minVal, maxVal = container.min or -500, container.max or 500
                        local pct = (0 - minVal) / (maxVal - minVal)
                        pct = math.max(0, math.min(1, pct))
                        local trackWidth = container.trackContainer:GetWidth() - 2
                        local fillWidth = math.max(1, pct * trackWidth)
                        container.trackFill:SetWidth(fillWidth)
                        if container.thumbFrame then
                            local thumbX = pct * (trackWidth - 14) + 7
                            container.thumbFrame:ClearAllPoints()
                            container.thumbFrame:SetPoint("CENTER", container.trackContainer, "LEFT", thumbX + 1, 0)
                        end
                    end
                end
            end
        end
        if onPresetChange then
            onPresetChange()
        end
        if onChange then
            onChange()
        end
        if refreshPopover then
            refreshPopover()
        end
    end
    
    -- Above (auto width) - castbar above target, auto width matching
    -- Align first button to match dropdown alignment (180px from left, same as CreateFormDropdown)
    local presetAboveBtn = GUI:CreateButton(presetButtonContainer, "Above (auto width)", buttonWidth, 24, function()
        ApplyPreset({
            {source = "BOTTOMLEFT", target = "TOPLEFT"},
            {source = "BOTTOMRIGHT", target = "TOPRIGHT"}
        })
    end)
    presetAboveBtn:SetPoint("LEFT", presetButtonContainer, "LEFT", 180, 0)
    
    -- Below (auto width) - castbar below target, auto width matching
    local presetBelowBtn = GUI:CreateButton(presetButtonContainer, "Below (auto width)", buttonWidth, 24, function()
        ApplyPreset({
            {source = "TOPLEFT", target = "BOTTOMLEFT"},
            {source = "TOPRIGHT", target = "BOTTOMRIGHT"}
        })
    end)
    presetBelowBtn:SetPoint("LEFT", presetAboveBtn, "RIGHT", buttonSpacing, 0)
    
    -- Left (auto height) - castbar to the left of target, auto height matching
    local presetLeftBtn = GUI:CreateButton(presetButtonContainer, "Left (auto height)", buttonWidth, 24, function()
        ApplyPreset({
            {source = "TOPRIGHT", target = "TOPLEFT"},
            {source = "BOTTOMRIGHT", target = "BOTTOMLEFT"}
        })
    end)
    presetLeftBtn:SetPoint("LEFT", presetBelowBtn, "RIGHT", buttonSpacing, 0)
    
    -- Right (auto height) - castbar to the right of target, auto height matching
    local presetRightBtn = GUI:CreateButton(presetButtonContainer, "Right (auto height)", buttonWidth, 24, function()
        -- Handler will be replaced by UpdatePresetHandler below
    end)
    presetRightBtn:SetPoint("LEFT", presetLeftBtn, "RIGHT", buttonSpacing, 0)
    
    -- Advanced anchor button (opens popover) - on same row as preset buttons
    local advancedAnchorButton = GUI:CreateButton(
        presetButtonContainer,
        "Advanced...",
        100,
        24,
        function()
            -- Toggle will be handled by the popover creation
        end
    )
    advancedAnchorButton:SetPoint("RIGHT", presetButtonContainer, "RIGHT", 0, 0)
    
    y = y - FORM_ROW
    
    -- Create advanced anchor popover (anchored to the first preset button)
    local advancedAnchorDialog = self:CreateMultiAnchorPopover(
        presetAboveBtn,  -- Anchor to first button for inline positioning
        settingsDB,
        onChange,
        anchorsKey,
        maxAnchors
    )
    
    -- Set button click handler to toggle popover
    advancedAnchorButton:SetScript("OnClick", function()
        if advancedAnchorDialog then
            advancedAnchorDialog:Toggle()
        end
    end)
    
    -- Store reference to popover refresh in button for preset updates
    advancedAnchorButton._popover = advancedAnchorDialog
    
    -- Create refresh function for popover
    local function RefreshPopover()
        if advancedAnchorDialog and advancedAnchorDialog.Refresh then
            advancedAnchorDialog:Refresh()
        end
    end
    
    -- Update preset button handlers to refresh popover
    local function UpdatePresetHandler(btn, presetAnchors)
        local originalOnClick = btn:GetScript("OnClick")
        btn:SetScript("OnClick", function()
            ApplyPreset(presetAnchors, RefreshPopover)
        end)
    end
    
    UpdatePresetHandler(presetAboveBtn, {
        {source = "BOTTOMLEFT", target = "TOPLEFT"},
        {source = "BOTTOMRIGHT", target = "TOPRIGHT"}
    })
    
    UpdatePresetHandler(presetBelowBtn, {
        {source = "TOPLEFT", target = "BOTTOMLEFT"},
        {source = "TOPRIGHT", target = "BOTTOMRIGHT"}
    })
    
    UpdatePresetHandler(presetLeftBtn, {
        {source = "TOPRIGHT", target = "TOPLEFT"},
        {source = "BOTTOMRIGHT", target = "BOTTOMLEFT"}
    })
    
    UpdatePresetHandler(presetRightBtn, {
        {source = "TOPLEFT", target = "TOPRIGHT"},
        {source = "BOTTOMLEFT", target = "BOTTOMRIGHT"}
    })
    
    return presetButtonContainer, advancedAnchorButton, advancedAnchorDialog, y
end

---------------------------------------------------------------------------
-- CREATE MULTI-ANCHOR DIALOG (Legacy - kept for backward compatibility)
-- Creates a scrollable popup dialog for managing multiple anchor point pairs
-- Parameters:
--   settingsDB: Settings database table
--   onChange: Callback function when values change
--   anchorsKey: Key name for anchors array in settingsDB (default: "anchors")
--   maxAnchors: Maximum number of anchor pairs allowed (default: 2)
-- Returns: dialog frame
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateMultiAnchorDialog(settingsDB, onChange, anchorsKey, maxAnchors)
    anchorsKey = anchorsKey or "anchors"
    maxAnchors = maxAnchors or 2
    
    local C = GetColors()
    local GUI = GetGUI()
    if not GUI then return nil end
    
    -- Initialize anchors array if not exists
    if not settingsDB[anchorsKey] then
        settingsDB[anchorsKey] = {
            {source = "BOTTOMLEFT", target = "BOTTOMLEFT"}
        }
    end
    
    -- Create dialog frame
    local dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(600, 500)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(100)
    local pxDialog = GetPixelSizeOrDefault(dialog, 1)
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2 * pxDialog,
        insets = {left = 4 * pxDialog, right = 4 * pxDialog, top = 4 * pxDialog, bottom = 4 * pxDialog}
    })
    dialog:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 0.98)
    dialog:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:Hide()
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    titleBar:SetBackdropColor(C.bgLight[1], C.bgLight[2], C.bgLight[3], 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() dialog:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
    
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText("Advanced Anchor Settings")
    titleText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
    
    -- Close button
    local closeBtn = GUI:CreateButton(titleBar, "×", 30, 30, function()
        dialog:Hide()
    end)
    closeBtn:SetPoint("RIGHT", -5, 0)
    if closeBtn.text then
        local fontPath = GUI.GetFontPath and GUI:GetFontPath() or "Fonts\\FRIZQT__.TTF"
        closeBtn.text:SetFont(fontPath, 18, "")
    end
    
    -- Scrollable content area
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 10)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(570)
    scrollFrame:SetScrollChild(content)
    
    -- Style scrollbar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, -2)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 2)
        
        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(0.35, 0.45, 0.5, 0.8)
        end
        
        local scrollUp = scrollBar.ScrollUpButton or scrollBar.Back
        local scrollDown = scrollBar.ScrollDownButton or scrollBar.Forward
        if scrollUp then scrollUp:Hide(); scrollUp:SetAlpha(0) end
        if scrollDown then scrollDown:Hide(); scrollDown:SetAlpha(0) end
    end
    
    ns.ApplyScrollWheel(scrollFrame)

    -- Create multi-anchor controls inside the scrollable content
    local PAD = 10
    local FORM_ROW = 30
    local anchors = settingsDB[anchorsKey]
    local selectorSize = 75
    local spacing = 10
    local rowHeight = selectorSize + 30
    local currentY = -PAD
    
    -- Store references
    dialog.anchors = anchors
    dialog.maxAnchors = maxAnchors
    dialog.onChange = onChange
    dialog.anchorRows = {}
    
    -- Update content height for scrolling
    local function UpdateContentHeight()
        content:SetHeight(math.abs(currentY) + PAD)
    end
    
    -- Function to rebuild all anchor rows
    local function RebuildAnchors()
        -- Clear existing rows
        for i, row in ipairs(dialog.anchorRows) do
            if row.frame then
                row.frame:Hide()
                row.frame:SetParent(nil)
            end
        end
        dialog.anchorRows = {}
        currentY = -PAD
        
        -- Create rows for each anchor pair
        for i, anchor in ipairs(anchors) do
            local rowFrame = CreateFrame("Frame", nil, content)
            rowFrame:SetHeight(rowHeight)
            rowFrame:SetPoint("TOPLEFT", PAD, currentY)
            rowFrame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
            
            -- Label for anchor pair number
            local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            label:SetText("Anchor " .. i)
            label:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            
            -- Source anchor point selector
            local sourceSelector = self:CreateAnchorPointSelector(
                rowFrame,
                "Source",
                anchor,
                "source",
                80,
                0,
                onChange,
                selectorSize
            )
            
            -- Target anchor point selector
            local targetSelector = self:CreateAnchorPointSelector(
                rowFrame,
                "Target",
                anchor,
                "target",
                80 + selectorSize + spacing,
                0,
                onChange,
                selectorSize
            )
            
            -- Remove button (only show if more than 1 anchor)
            local removeButton
            if #anchors > 1 then
                removeButton = GUI:CreateButton(rowFrame, "Remove", 80, 24, function()
                    table.remove(anchors, i)
                    RebuildAnchors()
                    UpdateContentHeight()
                    if onChange then onChange() end
                end)
                removeButton:SetPoint("RIGHT", -10, 0)
            end
            
            table.insert(dialog.anchorRows, {
                frame = rowFrame,
                sourceSelector = sourceSelector,
                targetSelector = targetSelector,
                removeButton = removeButton
            })
            
            currentY = currentY - rowHeight - (FORM_ROW / 2)
        end
        
        -- Add button (only show if under max)
        if #anchors < maxAnchors then
            if not dialog.addButton then
                dialog.addButton = GUI:CreateButton(content, "Add Anchor", 100, 24, function()
                    table.insert(anchors, {source = "BOTTOMLEFT", target = "BOTTOMLEFT"})
                    RebuildAnchors()
                    UpdateContentHeight()
                    if onChange then onChange() end
                end)
            end
            dialog.addButton:SetPoint("TOPLEFT", PAD, currentY)
            dialog.addButton:Show()
            currentY = currentY - FORM_ROW
        else
            if dialog.addButton then
                dialog.addButton:Hide()
            end
        end
        
        -- Preset buttons removed - they're now in the main options UI
        
        UpdateContentHeight()
    end
    
    -- Initial build
    RebuildAnchors()
    
    -- ESC key to close
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    dialog:EnableKeyboard(true)
    
    -- Expose methods
    dialog.Show = function(self)
        self:SetShown(true)
    end
    
    dialog.Hide = function(self)
        self:SetShown(false)
    end
    
    dialog.Toggle = function(self)
        if self:IsShown() then
            self:Hide()
        else
            self:Show()
        end
    end
    
    return dialog
end

---------------------------------------------------------------------------
-- CREATE MULTI-ANCHOR CONTROLS (Legacy - inline version)
-- Creates a flexible UI for managing multiple anchor point pairs
-- Parameters:
--   parent: Parent frame
--   settingsDB: Settings database table
--   x, y: Position
--   onChange: Callback function when values change
--   PAD: Padding constant
--   FORM_ROW: Form row height constant
--   anchorsKey: Key name for anchors array in settingsDB (default: "anchors")
--   maxAnchors: Maximum number of anchor pairs allowed (default: 2)
-- Returns: container frame and updated y position
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateMultiAnchorControls(parent, settingsDB, x, y, onChange, PAD, FORM_ROW, anchorsKey, maxAnchors)
    anchorsKey = anchorsKey or "anchors"
    maxAnchors = maxAnchors or 2
    
    local C = GetColors()
    local GUI = GetGUI()
    if not GUI then return nil, y end
    
    -- Initialize anchors array if not exists
    if not settingsDB[anchorsKey] then
        settingsDB[anchorsKey] = {
            {source = "BOTTOMLEFT", target = "BOTTOMLEFT"}
        }
    end
    
    -- Container for all anchor controls
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", x or PAD, y)
    container:SetPoint("RIGHT", parent, "RIGHT", -(x or PAD), 0)
    
    local anchors = settingsDB[anchorsKey]
    local selectorSize = 75  -- Reduced from 150 (50% scale)
    local spacing = 10
    local rowHeight = selectorSize + 30
    local currentY = 0
    
    -- Store references to anchor rows
    container.anchorRows = {}
    container.anchors = anchors
    container.maxAnchors = maxAnchors
    container.onChange = onChange
    
    -- Function to rebuild all anchor rows
    local function RebuildAnchors()
        -- Clear existing rows
        for i, row in ipairs(container.anchorRows) do
            if row.frame then
                row.frame:Hide()
                row.frame:SetParent(nil)
            end
        end
        container.anchorRows = {}
        currentY = 0
        
        -- Create rows for each anchor pair
        for i, anchor in ipairs(anchors) do
            local rowFrame = CreateFrame("Frame", nil, container)
            rowFrame:SetHeight(rowHeight)
            rowFrame:SetPoint("TOPLEFT", 0, -currentY)
            rowFrame:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            
            -- Label for anchor pair number
            local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", 0, 0)
            label:SetText("Anchor " .. i)
            label:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            
            -- Source anchor point selector
            local sourceSelector = self:CreateAnchorPointSelector(
                rowFrame,
                "Source",
                anchor,
                "source",
                80,
                0,
                onChange,
                selectorSize
            )
            
            -- Target anchor point selector
            local targetSelector = self:CreateAnchorPointSelector(
                rowFrame,
                "Target",
                anchor,
                "target",
                80 + selectorSize + spacing,
                0,
                onChange,
                selectorSize
            )
            
            -- Remove button (only show if more than 1 anchor)
            local removeButton
            if #anchors > 1 then
                removeButton = GUI:CreateButton(rowFrame, "Remove", 80, 24, function()
                    table.remove(anchors, i)
                    RebuildAnchors()
                    if onChange then onChange() end
                end)
                removeButton:SetPoint("RIGHT", -10, 0)
            end
            
            table.insert(container.anchorRows, {
                frame = rowFrame,
                sourceSelector = sourceSelector,
                targetSelector = targetSelector,
                removeButton = removeButton
            })
            
            currentY = currentY + rowHeight + (FORM_ROW / 2)
        end
        
        -- Add button (only show if under max)
        if #anchors < maxAnchors then
            if not container.addButton then
                container.addButton = GUI:CreateButton(container, "Add Anchor", 100, 24, function()
                    table.insert(anchors, {source = "BOTTOMLEFT", target = "BOTTOMLEFT"})
                    RebuildAnchors()
                    if onChange then onChange() end
                end)
            end
            container.addButton:SetPoint("TOPLEFT", 0, -currentY)
            container.addButton:Show()
            currentY = currentY + FORM_ROW
        else
            if container.addButton then
                container.addButton:Hide()
            end
        end
        
        -- Update preset container position
        if container.presetContainer then
            container.presetContainer:SetPoint("TOPLEFT", 0, -currentY)
        end
        
        container:SetHeight(currentY + FORM_ROW)
    end
    
    -- Add preset buttons for common layouts
    local presetContainer = CreateFrame("Frame", nil, container)
    presetContainer:SetHeight(FORM_ROW)
    presetContainer:SetPoint("TOPLEFT", 0, 0)
    presetContainer:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    container.presetContainer = presetContainer
    
    local presetLabel = presetContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    presetLabel:SetPoint("LEFT", 0, 0)
    presetLabel:SetText("Presets:")
    presetLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    
    -- Preset 1: Source BOTTOM to Target TOP (castbar below target - "Above Target" means castbar is above, so source is BOTTOM)
    local preset1Btn = GUI:CreateButton(presetContainer, "Above Target", 120, 24, function()
        -- Clear existing anchors
        while #anchors > 0 do
            table.remove(anchors, 1)
        end
        -- Castbar above target: source BOTTOM connects to target TOP
        table.insert(anchors, {source = "BOTTOMLEFT", target = "TOPLEFT"})
        table.insert(anchors, {source = "BOTTOMRIGHT", target = "TOPRIGHT"})
        RebuildAnchors()
        if onChange then onChange() end
    end)
    preset1Btn:SetPoint("LEFT", presetLabel, "RIGHT", 10, 0)
    
    -- Preset 2: Source TOP to Target BOTTOM (castbar below target - "Below Target" means castbar is below, so source is TOP)
    local preset2Btn = GUI:CreateButton(presetContainer, "Below Target", 120, 24, function()
        -- Clear existing anchors
        while #anchors > 0 do
            table.remove(anchors, 1)
        end
        -- Castbar below target: source TOP connects to target BOTTOM
        table.insert(anchors, {source = "TOPLEFT", target = "BOTTOMLEFT"})
        table.insert(anchors, {source = "TOPRIGHT", target = "BOTTOMRIGHT"})
        RebuildAnchors()
        if onChange then onChange() end
    end)
    preset2Btn:SetPoint("LEFT", preset1Btn, "RIGHT", 10, 0)
    
    -- Initial build
    RebuildAnchors()
    
    -- Update container height and y position
    y = y - container:GetHeight()
    
    return container, y
end

---------------------------------------------------------------------------
-- CREATE ANCHOR POINT CONTROLS (Legacy - single anchor pair)
-- Creates source and target anchor point selectors (visual grid widgets)
-- Parameters:
--   parent: Parent frame
--   settingsDB: Settings database table
--   x, y: Position
--   onChange: Callback function when values change
--   PAD: Padding constant
--   FORM_ROW: Form row height constant
--   sourceKey: Key name for source anchor point (default: "anchorPoint")
--   targetKey: Key name for target anchor point (default: "targetAnchorPoint")
--   sourceLabel: Label for source selector (default: "Source Anchor Point")
--   targetLabel: Label for target selector (default: "Target Anchor Point")
-- Returns: sourceSelector, targetSelector, and updated y position
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateAnchorPointControls(parent, settingsDB, x, y, onChange, PAD, FORM_ROW, sourceKey, targetKey, sourceLabel, targetLabel)
    sourceKey = sourceKey or "anchorPoint"
    targetKey = targetKey or "targetAnchorPoint"
    sourceLabel = sourceLabel or "Source Anchor Point"
    targetLabel = targetLabel or "Target Anchor Point"
    
    -- Initialize defaults if not set
    if not settingsDB[sourceKey] then
        settingsDB[sourceKey] = "BOTTOMLEFT"
    end
    if not settingsDB[targetKey] then
        settingsDB[targetKey] = "BOTTOMLEFT"
    end
    
    -- Create visual selectors side by side
    local selectorSize = 150
    local spacing = 20
    
    -- Source anchor point selector
    local sourceSelector = self:CreateAnchorPointSelector(
        parent,
        sourceLabel,
        settingsDB,
        sourceKey,
        x or PAD,
        y,
        onChange,
        selectorSize
    )
    
    -- Target anchor point selector (to the right of source)
    local targetSelector = self:CreateAnchorPointSelector(
        parent,
        targetLabel,
        settingsDB,
        targetKey,
        (x or PAD) + selectorSize + spacing,
        y,
        onChange,
        selectorSize
    )
    
    -- Update y position (selectors are selectorSize + 30 tall)
    y = y - (selectorSize + 30) - (FORM_ROW / 2)
    
    return sourceSelector, targetSelector, y
end

---------------------------------------------------------------------------
-- CREATE OFFSET CONTROLS
-- Parameters:
--   parent: Parent frame
--   settingsDB: Settings database table
--   x, y: Position
--   onChange: Callback function when values change
--   PAD: Padding constant
--   FORM_ROW: Form row height constant
-- Returns: offsetX slider, offsetY slider, and updated y position
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateOffsetControls(parent, settingsDB, x, y, onChange, PAD, FORM_ROW)
    local GUI = GetGUI()
    if not GUI then
        return nil, nil, y
    end
    
    -- Ensure onChange is a function (default to empty function if nil)
    onChange = onChange or function() end
    
    local offsetXSlider = GUI:CreateFormSlider(parent, "Offset X", -500, 500, 1, "offsetX", settingsDB, onChange)
    if offsetXSlider then
        offsetXSlider:SetPoint("TOPLEFT", x or PAD, y)
        offsetXSlider:SetPoint("RIGHT", parent, "RIGHT", -(x or PAD), 0)
        y = y - FORM_ROW
    end
    
    local offsetYSlider = GUI:CreateFormSlider(parent, "Offset Y", -500, 500, 1, "offsetY", settingsDB, onChange)
    if offsetYSlider then
        offsetYSlider:SetPoint("TOPLEFT", x or PAD, y)
        offsetYSlider:SetPoint("RIGHT", parent, "RIGHT", -(x or PAD), 0)
        y = y - FORM_ROW
    end
    
    -- Store slider references in settingsDB so they can be updated externally
    if settingsDB then
        settingsDB._offsetXSlider = offsetXSlider
        settingsDB._offsetYSlider = offsetYSlider
    end
    
    return offsetXSlider, offsetYSlider, y
end

---------------------------------------------------------------------------
-- CREATE COMPLETE ANCHOR CONTROLS
-- Creates all anchoring UI components: dropdown, preset controls, and offset sliders
-- Parameters:
--   parent: Parent frame
--   settingsDB: Settings database table
--   x, y: Position
--   onChange: Callback function when values change
--   PAD: Padding constant
--   FORM_ROW: Form row height constant
--   anchorKey: Key name for anchor value in settingsDB (default: "anchorTo")
--   anchorsKey: Key name for anchors array in settingsDB (default: "anchors")
--   maxAnchors: Maximum number of anchor pairs allowed (default: 2)
--   excludeSelf: Optional anchor target name to exclude from dropdown (prevents self-anchoring)
--   dropdownLabel: Optional label for dropdown (default: "Anchor To")
--   offsetMin: Optional minimum value for offset sliders (default: -500)
--   offsetMax: Optional maximum value for offset sliders (default: 500)
--   onPresetChange: Optional callback when preset buttons are clicked (for refreshing other UI)
-- Returns: dropdown, presetContainer, advancedButton, popover, offsetXSlider, offsetYSlider, and updated y position
---------------------------------------------------------------------------
function QUI_Anchoring_Options:CreateAnchorControls(parent, settingsDB, x, y, onChange, PAD, FORM_ROW, anchorKey, anchorsKey, maxAnchors, excludeSelf, dropdownLabel, offsetMin, offsetMax, onPresetChange)
    anchorKey = anchorKey or "anchorTo"
    anchorsKey = anchorsKey or "anchors"
    maxAnchors = maxAnchors or 2
    dropdownLabel = dropdownLabel or "Anchor To"
    offsetMin = offsetMin or -500
    offsetMax = offsetMax or 500
    
    local GUI = GetGUI()
    if not GUI then
        return nil, nil, nil, nil, nil, nil, y
    end
    
    -- Initialize anchor settings if not exists
    if not settingsDB[anchorKey] then
        settingsDB[anchorKey] = "disabled"
    end
    if not settingsDB.offsetX then
        settingsDB.offsetX = 0
    end
    if not settingsDB.offsetY then
        settingsDB.offsetY = 0
    end
    
    -- Create anchor dropdown
    local anchorDropdown = self:CreateAnchorDropdown(
        parent, dropdownLabel, settingsDB, anchorKey, x or PAD, y, nil, onChange, nil, nil, excludeSelf
    )
    local dropdownY = y
    if anchorDropdown then
        anchorDropdown:SetPoint("RIGHT", parent, "RIGHT", -(x or PAD), 0)
        dropdownY = y - FORM_ROW
    end
    
    -- Create preset controls and advanced popover
    local presetContainer, advancedButton, popover, presetY = self:CreateAnchorPresetControls(
        parent, settingsDB, x or PAD, dropdownY, onChange, PAD, FORM_ROW, anchorsKey, maxAnchors, onPresetChange
    )
    
    -- Create offset sliders with custom range if provided
    local offsetXSlider, offsetYSlider, offsetY
    if offsetMin ~= -500 or offsetMax ~= 500 then
        -- Custom range - create sliders manually
        offsetXSlider = GUI:CreateFormSlider(parent, "Offset X", offsetMin, offsetMax, 1, "offsetX", settingsDB, onChange)
        if offsetXSlider then
            offsetXSlider:SetPoint("TOPLEFT", x or PAD, presetY)
            offsetXSlider:SetPoint("RIGHT", parent, "RIGHT", -(x or PAD), 0)
            offsetY = presetY - FORM_ROW
        end
        
        offsetYSlider = GUI:CreateFormSlider(parent, "Offset Y", offsetMin, offsetMax, 1, "offsetY", settingsDB, onChange)
        if offsetYSlider then
            offsetYSlider:SetPoint("TOPLEFT", x or PAD, offsetY)
            offsetYSlider:SetPoint("RIGHT", parent, "RIGHT", -(x or PAD), 0)
            offsetY = offsetY - FORM_ROW
        end
        
        -- Store slider references in settingsDB
        if settingsDB then
            settingsDB._offsetXSlider = offsetXSlider
            settingsDB._offsetYSlider = offsetYSlider
        end
    else
        -- Standard range - use CreateOffsetControls
        offsetXSlider, offsetYSlider, offsetY = self:CreateOffsetControls(
            parent, settingsDB, x or PAD, presetY, onChange, PAD, FORM_ROW
        )
    end
    
    return anchorDropdown, presetContainer, advancedButton, popover, offsetXSlider, offsetYSlider, offsetY
end

