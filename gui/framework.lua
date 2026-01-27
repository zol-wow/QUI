--[[
    QUI Custom GUI Framework
    Style: Horizontal tab grid at top
    Accent Color: #56D1FF
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local LSM = LibStub("LibSharedMedia-3.0")

-- Create GUI namespace
QUI.GUI = QUI.GUI or {}
local GUI = QUI.GUI

---------------------------------------------------------------------------
-- THEME COLORS - "Mint Condition" Palette
---------------------------------------------------------------------------
GUI.Colors = {
    -- Backgrounds
    bg = {0.067, 0.094, 0.153, 0.97},         -- #111827 Deep Cool Grey
    bgLight = {0.122, 0.161, 0.216, 1},       -- #1F2937 Dark Slate (inactive tabs)
    bgDark = {0.04, 0.06, 0.1, 1},            -- Even darker for contrast
    bgContent = {0.122, 0.161, 0.216, 0.5},   -- #1F2937 with alpha
    
    -- Accent colors (Mint)
    accent = {0.204, 0.827, 0.6, 1},          -- #34D399 Soft Mint (active border)
    accentLight = {0.431, 0.906, 0.718, 1},   -- #6EE7B7 Lighter Mint (headers)
    accentDark = {0.1, 0.5, 0.35, 1},
    accentHover = {0.3, 0.9, 0.65, 1},
    
    -- Tab colors
    tabSelected = {0.204, 0.827, 0.6, 1},     -- #34D399 Soft Mint
    tabSelectedText = {0.067, 0.094, 0.153, 1}, -- Dark text on selected
    tabNormal = {0.7, 0.75, 0.78, 1},         -- Slightly cool grey
    tabHover = {0.95, 0.96, 0.96, 1},
    
    -- Text colors
    text = {0.953, 0.957, 0.965, 1},          -- #F3F4F6 Off-White
    textBright = {1, 1, 1, 1},
    textMuted = {0.6, 0.65, 0.7, 1},
    
    -- Borders
    border = {0.2, 0.25, 0.3, 1},
    borderLight = {0.3, 0.35, 0.4, 1},
    borderAccent = {0.204, 0.827, 0.6, 1},    -- #34D399 Mint border
    
    -- Section headers
    sectionHeader = {0.431, 0.906, 0.718, 1}, -- #6EE7B7 Lighter Mint

    -- Slider colors (Premium redesign)
    sliderTrack = {0.15, 0.17, 0.22, 1},       -- Slightly lighter track background
    sliderThumb = {1, 1, 1, 1},                -- White thumb
    sliderThumbBorder = {0.3, 0.35, 0.4, 1},   -- Subtle border on thumb

    -- Toggle switch colors
    toggleOff = {0.176, 0.216, 0.282, 1},      -- #2D3748 Dark grey track
    toggleThumb = {1, 1, 1, 1},                -- White circle

    -- Warning/secondary accent
    warning = {0.961, 0.620, 0.043, 1},        -- #F59E0B Amber
}

local C = GUI.Colors

-- Panel dimensions (used for widget sizing)
GUI.PANEL_WIDTH = 750
GUI.CONTENT_WIDTH = 710  -- Panel width minus padding (20 each side)

-- Settings Registry for search functionality
GUI.SettingsRegistry = {}

-- Search context (auto-populated by page builders)
GUI._searchContext = {
    tabIndex = nil,
    tabName = nil,
    subTabIndex = nil,
    subTabName = nil,
    sectionName = nil,
}

-- Suppress auto-registration when rebuilding widgets for search results
GUI._suppressSearchRegistration = false

-- Deduplication keys to prevent duplicate registry entries when tabs are re-clicked
GUI.SettingsRegistryKeys = {}

-- Widget instance tracking for cross-widget synchronization (search results <-> original tabs)
GUI.WidgetInstances = {}

-- Section header registry for scroll-to-section navigation
-- Key format: "tabIndex_subTabIndex_sectionName" -> {frame = sectionFrame, scrollParent = scrollFrame}
GUI.SectionRegistry = {}

-- Generate unique key for widget instance tracking
local function GetWidgetKey(dbTable, dbKey)
    if not dbTable or not dbKey then return nil end
    return tostring(dbTable) .. "_" .. dbKey
end

-- Register a widget instance for sync tracking
local function RegisterWidgetInstance(widget, dbTable, dbKey)
    local widgetKey = GetWidgetKey(dbTable, dbKey)
    if not widgetKey then return end
    GUI.WidgetInstances[widgetKey] = GUI.WidgetInstances[widgetKey] or {}
    table.insert(GUI.WidgetInstances[widgetKey], widget)
    widget._widgetKey = widgetKey
end

-- Unregister a widget instance (called during cleanup)
local function UnregisterWidgetInstance(widget)
    if not widget._widgetKey then return end
    local instances = GUI.WidgetInstances[widget._widgetKey]
    if not instances then return end
    for i = #instances, 1, -1 do
        if instances[i] == widget then
            table.remove(instances, i)
            break
        end
    end
end

-- Broadcast value change to all sibling widget instances
local function BroadcastToSiblings(widget, val)
    if not widget._widgetKey then return end
    local instances = GUI.WidgetInstances[widget._widgetKey]
    if not instances then return end
    for _, sibling in ipairs(instances) do
        if sibling ~= widget and sibling.UpdateVisual then
            sibling.UpdateVisual(val)
        end
    end
end

-- Set search context for auto-registration (call at start of page builder)
function GUI:SetSearchContext(info)
    self._searchContext.tabIndex = info.tabIndex
    self._searchContext.tabName = info.tabName
    self._searchContext.subTabIndex = info.subTabIndex or nil
    self._searchContext.subTabName = info.subTabName or nil
    self._searchContext.sectionName = info.sectionName or nil
end

-- Set current section (call when entering a new section within a page)
function GUI:SetSearchSection(sectionName)
    self._searchContext.sectionName = sectionName
end

-- Clear search context (optional, for safety)
function GUI:ClearSearchContext()
    self._searchContext = {
        tabIndex = nil,
        tabName = nil,
        subTabIndex = nil,
        subTabName = nil,
        sectionName = nil,
    }
end

-- Flag to track if search index has been built
GUI._searchIndexBuilt = false

-- Force-load all tabs to populate search registry
function GUI:ForceLoadAllTabs()
    local frame = self.MainFrame
    if not frame or not frame.pages then return end

    -- Initialize registry if needed (don't clear - keep registrations from already-visited tabs)
    if not self.SettingsRegistry then
        self.SettingsRegistry = {}
    end
    if not self.SettingsRegistryKeys then
        self.SettingsRegistryKeys = {}
    end

    -- Build each tab that hasn't been built yet
    for tabIndex, page in pairs(frame.pages) do
        if tabIndex ~= self._searchTabIndex then  -- Skip Search tab itself
            if page and page.createFunc and not page.built then
                -- Create hidden frame if needed
                if not page.frame then
                    page.frame = CreateFrame("Frame", nil, frame.contentArea)
                    page.frame:SetAllPoints()
                    page.frame:EnableMouse(false)  -- Container frame - let children handle clicks
                end
                page.frame:Hide()  -- Keep hidden during build

                -- Run the builder to register widgets (only once)
                page.createFunc(page.frame)
                page.built = true  -- Prevent duplicate widget creation
            end
        end
    end
end

---------------------------------------------------------------------------
-- FONT PATH (uses bundled Quazii font for consistent panel formatting)
---------------------------------------------------------------------------
local FONT_PATH = LSM:Fetch("font", "Quazii") or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
GUI.FONT_PATH = FONT_PATH

-- Helper for future configurability
local function GetFontPath()
    return FONT_PATH
end

---------------------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------------------
local function CreateBackdrop(frame, bgColor, borderColor)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(bgColor or C.bg))
    frame:SetBackdropBorderColor(unpack(borderColor or C.border))
end

local function SetFont(fontString, size, flags, color)
    fontString:SetFont(GetFontPath(), size or 12, flags or "")
    if color then
        fontString:SetTextColor(unpack(color))
    end
end

---------------------------------------------------------------------------
-- WIDGET: LABEL
---------------------------------------------------------------------------
function GUI:CreateLabel(parent, text, size, color, anchor, x, y)
    -- Mark content as added (for section header auto-spacing)
    if parent._hasContent ~= nil then
        parent._hasContent = true
    end
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(label, size or 12, "", color or C.text)
    label:SetText(text or "")
    if anchor then
        label:SetPoint(anchor, parent, anchor, x or 0, y or 0)
    end
    return label
end

---------------------------------------------------------------------------
-- WIDGET: THEMED BUTTON (Neutral style - accent border on hover only)
---------------------------------------------------------------------------
function GUI:CreateButton(parent, text, width, height, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 26)

    -- Normal state: dark background with grey border (neutral)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
    btn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    -- Button text (off-white, not accent)
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetFont(GetFontPath(), 12, "")
    btnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(text or "Button")
    btn.text = btnText

    -- Hover effect: accent border only (no background change)
    btn:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, C.accent[1], C.accent[2], C.accent[3], 1)
    end)

    btn:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, C.border[1], C.border[2], C.border[3], 1)
    end)

    -- Click handler
    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    -- Method to update text
    function btn:SetText(newText)
        btnText:SetText(newText)
    end

    return btn
end

---------------------------------------------------------------------------
-- CONFIRMATION DIALOG (QUI-styled replacement for StaticPopup)
-- Singleton frame, lazy-created and reused
---------------------------------------------------------------------------
local confirmDialog = nil

function GUI:ShowConfirmation(options)
    -- options = {
    --   title = "Delete Profile?",
    --   message = "Delete profile 'ProfileName'?",
    --   warningText = "This cannot be undone.",  -- optional, amber text
    --   acceptText = "Delete",
    --   cancelText = "Cancel",
    --   onAccept = function() end,
    --   onCancel = function() end,  -- optional
    --   isDestructive = true,       -- amber text on accept button
    -- }

    if not confirmDialog then
        -- Create singleton dialog frame
        confirmDialog = CreateFrame("Frame", "QUI_ConfirmDialog", UIParent, "BackdropTemplate")
        confirmDialog:SetSize(320, 160)
        confirmDialog:SetPoint("CENTER")
        confirmDialog:SetFrameStrata("FULLSCREEN_DIALOG")
        confirmDialog:SetFrameLevel(500)
        confirmDialog:EnableMouse(true)
        confirmDialog:SetMovable(true)
        confirmDialog:RegisterForDrag("LeftButton")
        confirmDialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
        confirmDialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        confirmDialog:SetClampedToScreen(true)
        confirmDialog:Hide()

        -- Backdrop
        confirmDialog:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        confirmDialog:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.98)
        confirmDialog:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        -- Title
        confirmDialog.title = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.title, 14, "", C.accentLight)
        confirmDialog.title:SetPoint("TOP", 0, -18)

        -- Message
        confirmDialog.message = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.message, 12, "", C.text)
        confirmDialog.message:SetPoint("TOP", 0, -50)
        confirmDialog.message:SetWidth(280)
        confirmDialog.message:SetJustifyH("CENTER")

        -- Warning text
        confirmDialog.warning = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(confirmDialog.warning, 11, "", C.warning)
        confirmDialog.warning:SetPoint("TOP", confirmDialog.message, "BOTTOM", 0, -8)

        -- Accept button (left)
        confirmDialog.acceptBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
        confirmDialog.acceptBtn:SetSize(100, 28)
        confirmDialog.acceptBtn:SetPoint("BOTTOMLEFT", 40, 20)
        confirmDialog.acceptBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        confirmDialog.acceptBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        confirmDialog.acceptBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        confirmDialog.acceptBtn.text = confirmDialog.acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        confirmDialog.acceptBtn.text:SetFont(GetFontPath(), 12, "")
        confirmDialog.acceptBtn.text:SetPoint("CENTER", 0, 0)

        confirmDialog.acceptBtn:SetScript("OnEnter", function(self)
            pcall(self.SetBackdropBorderColor, self, C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        confirmDialog.acceptBtn:SetScript("OnLeave", function(self)
            pcall(self.SetBackdropBorderColor, self, C.border[1], C.border[2], C.border[3], 1)
        end)

        -- Cancel button (right)
        confirmDialog.cancelBtn = CreateFrame("Button", nil, confirmDialog, "BackdropTemplate")
        confirmDialog.cancelBtn:SetSize(100, 28)
        confirmDialog.cancelBtn:SetPoint("BOTTOMRIGHT", -40, 20)
        confirmDialog.cancelBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        confirmDialog.cancelBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        confirmDialog.cancelBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        confirmDialog.cancelBtn.text = confirmDialog.cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        confirmDialog.cancelBtn.text:SetFont(GetFontPath(), 12, "")
        confirmDialog.cancelBtn.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        confirmDialog.cancelBtn.text:SetPoint("CENTER", 0, 0)

        confirmDialog.cancelBtn:SetScript("OnEnter", function(self)
            pcall(self.SetBackdropBorderColor, self, C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        confirmDialog.cancelBtn:SetScript("OnLeave", function(self)
            pcall(self.SetBackdropBorderColor, self, C.border[1], C.border[2], C.border[3], 1)
        end)

        -- ESC to close
        confirmDialog:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                if self._onCancel then self._onCancel() end
                self:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end

    -- Configure for this call
    confirmDialog.title:SetText(options.title or "Confirm")
    confirmDialog.message:SetText(options.message or "")

    if options.warningText then
        confirmDialog.warning:SetText(options.warningText)
        confirmDialog.warning:Show()
    else
        confirmDialog.warning:Hide()
    end

    -- Accept button styling
    confirmDialog.acceptBtn.text:SetText(options.acceptText or "OK")
    if options.isDestructive then
        confirmDialog.acceptBtn.text:SetTextColor(C.warning[1], C.warning[2], C.warning[3], 1)
    else
        confirmDialog.acceptBtn.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end

    -- Cancel button
    confirmDialog.cancelBtn.text:SetText(options.cancelText or "Cancel")

    -- Store callbacks
    confirmDialog._onCancel = options.onCancel

    -- Button click handlers
    confirmDialog.acceptBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        if options.onAccept then options.onAccept() end
    end)

    confirmDialog.cancelBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        if options.onCancel then options.onCancel() end
    end)

    -- Show and enable keyboard
    confirmDialog:Show()
    confirmDialog:EnableKeyboard(true)
end

---------------------------------------------------------------------------
-- WIDGET: SECTION HEADER (Mint colored text with underline)
-- Auto-detects if first element in panel (no top margin) vs subsequent (12px margin)
---------------------------------------------------------------------------
function GUI:CreateSectionHeader(parent, text)
    -- Automatically set search section so widgets created after this header
    -- are associated with this section (no need for manual SetSearchSection calls)
    if text and not self._suppressSearchRegistration then
        self._searchContext.sectionName = text
    end

    -- Auto-detect if this is the first element (for compact spacing at top of panels)
    local isFirstElement = (parent._hasContent == false)
    if parent._hasContent ~= nil then
        parent._hasContent = true
    end

    -- First element: no top margin (18px), others: 12px top margin (30px)
    local topMargin = isFirstElement and 0 or 12
    local containerHeight = isFirstElement and 18 or 30

    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(containerHeight)

    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(header, 13, "", C.sectionHeader)
    header:SetText(text or "Section")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -topMargin)

    -- Store references and recommended gap for calling code
    container.text = header
    container.parent = parent
    container.gap = isFirstElement and 34 or 46  -- Adjusted gap for y positioning

    -- Expose SetText for convenience
    container.SetText = function(self, newText)
        header:SetText(newText)
    end

    -- Hook SetPoint to also set width and create underline after positioning
    local originalSetPoint = container.SetPoint
    container.SetPoint = function(self, point, ...)
        originalSetPoint(self, point, ...)
        -- After TOPLEFT is set, also anchor RIGHT to give container width
        if point == "TOPLEFT" then
            originalSetPoint(self, "RIGHT", parent, "RIGHT", -10, 0)
            -- Create underline now that we have positioning
            if not container.underline then
                local underline = container:CreateTexture(nil, "ARTWORK")
                underline:SetHeight(2)
                underline:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
                underline:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                underline:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
                container.underline = underline
            end

            -- Register section header for scroll-to-section navigation (after positioning)
            if not GUI._suppressSearchRegistration and GUI._searchContext.tabIndex and text then
                local tabIndex = GUI._searchContext.tabIndex
                local subTabIndex = GUI._searchContext.subTabIndex or 0
                local regKey = tabIndex .. "_" .. subTabIndex .. "_" .. text

                -- Find scroll parent by walking up the hierarchy
                local scrollParent = nil
                local current = parent
                while current do
                    if current.GetVerticalScroll and current.SetVerticalScroll then
                        scrollParent = current
                        break
                    end
                    current = current:GetParent()
                end

                GUI.SectionRegistry[regKey] = {
                    frame = container,
                    scrollParent = scrollParent,
                    contentParent = parent,
                }
            end
        end
    end

    return container
end

---------------------------------------------------------------------------
-- WIDGET: SECTION BOX (Bordered group like old GUI)
-- Auto-calculates height based on content added via box:AddElement()
---------------------------------------------------------------------------
function GUI:CreateSectionBox(parent, title)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.05, 0.05, 0.08, 0.8)
    box:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    
    -- Title (mint colored, positioned at top-left inside border)
    if title and title ~= "" then
        local titleText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetFont(GetFontPath(), 12, "")
        titleText:SetTextColor(unpack(C.accentLight))
        titleText:SetText(title)
        titleText:SetPoint("TOPLEFT", 10, -8)
        box.title = titleText
    end
    
    -- Track current Y position for auto-layout
    box.currentY = -30  -- Starting Y position for content inside the box
    box.padding = 12    -- Left/right padding
    box.elementSpacing = 8  -- Default spacing between elements
    
    -- Helper to add element and auto-position it
    function box:AddElement(element, height, spacing)
        local sp = spacing or self.elementSpacing
        element:SetPoint("TOPLEFT", self.padding, self.currentY)
        if element.SetPoint then
            -- If element supports right anchor, stretch it
            element:SetPoint("TOPRIGHT", -self.padding, self.currentY)
        end
        self.currentY = self.currentY - (height or 25) - sp
    end
    
    -- Call this after adding all elements to set the box height
    function box:FinishLayout(bottomPadding)
        local pad = bottomPadding or 12
        self:SetHeight(math.abs(self.currentY) + pad)
        return math.abs(self.currentY) + pad  -- Return height for parent tracking
    end
    
    return box
end

---------------------------------------------------------------------------
-- WIDGET: COLLAPSIBLE SECTION
-- Expandable/collapsible container with clickable header
---------------------------------------------------------------------------
function GUI:CreateCollapsibleSection(parent, title, isExpandedByDefault, badgeConfig)
    local container = CreateFrame("Frame", nil, parent)
    local isExpanded = isExpandedByDefault ~= false  -- Default true

    -- Header (clickable, full width)
    local header = CreateFrame("Button", nil, container, "BackdropTemplate")
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    header:SetBackdropColor(C.bgLight[1], C.bgLight[2], C.bgLight[3], 0.6)
    header:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.5)

    -- Chevron indicator
    local chevron = header:CreateFontString(nil, "OVERLAY")
    chevron:SetFont(GetFontPath(), 12, "")
    chevron:SetPoint("LEFT", 10, 0)
    chevron:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Title text
    local titleText = header:CreateFontString(nil, "OVERLAY")
    SetFont(titleText, 12, "", C.accent)
    titleText:SetText(title or "Section")
    titleText:SetPoint("LEFT", chevron, "RIGHT", 6, 0)

    -- Optional badge (e.g., "Override" indicator)
    local badge = nil
    if badgeConfig and badgeConfig.text then
        badge = CreateFrame("Frame", nil, header, "BackdropTemplate")
        badge:SetHeight(18)
        badge:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        badge:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.2)
        badge:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

        local badgeText = badge:CreateFontString(nil, "OVERLAY")
        badgeText:SetFont(GetFontPath(), 10, "")
        badgeText:SetText(badgeConfig.text)
        badgeText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        badgeText:SetPoint("CENTER", 0, 0)

        -- Auto-width based on text
        local textWidth = badgeText:GetStringWidth() or 40
        badge:SetWidth(textWidth + 12)
        badge:SetPoint("RIGHT", header, "RIGHT", -10, 0)

        -- Initial visibility based on showFunc
        if badgeConfig.showFunc then
            badge:SetShown(badgeConfig.showFunc())
        end
    end

    -- Content area
    local content = CreateFrame("Frame", nil, container)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    content:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    content._hasContent = false

    -- Update function
    local function UpdateState()
        if isExpanded then
            chevron:SetText("v")  -- Down arrow
            content:Show()
            container:SetHeight(header:GetHeight() + 4 + (content:GetHeight() or 0))
        else
            chevron:SetText(">")  -- Right arrow
            content:Hide()
            container:SetHeight(header:GetHeight())
        end
    end

    -- Click handler
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        UpdateState()
        if container.OnExpandChanged then
            container.OnExpandChanged(isExpanded)
        end
    end)

    -- Hover effects
    header:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    end)
    header:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.5)
    end)

    -- API methods
    container.SetExpanded = function(self, expanded)
        isExpanded = expanded
        UpdateState()
    end

    container.GetExpanded = function()
        return isExpanded
    end

    container.UpdateHeight = function()
        UpdateState()
    end

    container.SetTitle = function(self, newTitle)
        titleText:SetText(newTitle)
    end

    -- Badge update method
    container.UpdateBadge = function()
        if badge and badgeConfig and badgeConfig.showFunc then
            badge:SetShown(badgeConfig.showFunc())
        end
    end

    container.content = content
    container.header = header
    container.badge = badge

    UpdateState()
    return container
end

---------------------------------------------------------------------------
-- WIDGET: COLOR PICKER
---------------------------------------------------------------------------
function GUI:CreateColorPicker(parent, label, dbKey, dbTable, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 20)
    
    -- Color swatch button (same size as checkbox: 16x16)
    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(16, 16)
    swatch:SetPoint("LEFT", 0, 0)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Label (same font size as checkbox: 12)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Color")
    text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    
    container.swatch = swatch
    container.label = text
    
    local function GetColor()
        if dbTable and dbKey then
            local c = dbTable[dbKey]
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        end
        return 1, 1, 1, 1
    end
    
    local function SetColor(r, g, b, a)
        swatch:SetBackdropColor(r, g, b, a or 1)
        if dbTable and dbKey then
            dbTable[dbKey] = {r, g, b, a or 1}
        end
        if onChange then onChange(r, g, b, a) end
    end
    
    -- Initialize color
    local r, g, b, a = GetColor()
    swatch:SetBackdropColor(r, g, b, a)
    
    container.GetColor = GetColor
    container.SetColor = SetColor
    
    -- Open color picker on click
    swatch:SetScript("OnClick", function()
        local r, g, b, a = GetColor()
        local originalA = a or 1
        
        local info = {
            r = r,
            g = g,
            b = b,
            opacity = originalA,
            hasOpacity = true,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            opacityFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            cancelFunc = function(prev)
                SetColor(prev.r, prev.g, prev.b, originalA)
            end,
        }
        
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    -- Hover effect
    swatch:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
    end)
    swatch:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.4, 0.4, 0.4, 1)
    end)
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: SUB-TABS (Horizontal tabs within a page)
---------------------------------------------------------------------------
function GUI:CreateSubTabs(parent, tabs)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(28)
    
    local tabButtons = {}
    local tabContents = {}
    local buttonWidth = 90
    local spacing = 2
    
    for i, tabInfo in ipairs(tabs) do
        -- Tab button
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(buttonWidth, 24)
        btn:SetPoint("TOPLEFT", 10 + (i-1) * (buttonWidth + spacing), 0)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(btn.text, 10, "", C.text)
        btn.text:SetText(tabInfo.name)
        btn.text:SetPoint("CENTER", 0, 0)
        
        btn.index = i
        tabButtons[i] = btn
        
        -- Content frame for this tab
        local content = CreateFrame("Frame", nil, container)
        content:SetPoint("TOPLEFT", 0, -30)
        content:SetPoint("BOTTOMRIGHT", 0, 0)
        content:Hide()
        content:EnableMouse(false)  -- Container frame - let children handle clicks
        content._hasContent = false  -- Track if any content added (for auto-spacing)
        tabContents[i] = content
        
        -- Create content if builder function provided
        if tabInfo.builder then
            tabInfo.builder(content)
        end
    end

    -- Dynamic relayout function for responsive sub-tabs
    local function RelayoutSubTabs()
        local containerWidth = container:GetWidth()
        if containerWidth < 1 then return end  -- Not sized yet

        local separatorSpacing = 15  -- Extra spacing after tabs with isSeparator
        local availableWidth = containerWidth - 20  -- 10px padding each side

        -- Count separators to account for extra spacing
        local separatorCount = 0
        for _, tabInfo in ipairs(tabs) do
            if tabInfo.isSeparator then separatorCount = separatorCount + 1 end
        end

        local totalSpacing = (#tabButtons - 1) * spacing + (separatorCount * separatorSpacing)
        local newButtonWidth = math.floor((availableWidth - totalSpacing) / #tabButtons)
        newButtonWidth = math.max(newButtonWidth, 50)  -- minimum 50px

        local xOffset = 10
        for i, btn in ipairs(tabButtons) do
            btn:SetWidth(newButtonWidth)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", xOffset, 0)
            xOffset = xOffset + newButtonWidth + spacing

            -- Add extra spacing after separator tabs
            if tabs[i] and tabs[i].isSeparator then
                xOffset = xOffset + separatorSpacing
            end
        end
    end

    -- Hook resize to relayout sub-tabs dynamically
    container:SetScript("OnSizeChanged", RelayoutSubTabs)

    -- Tab selection function
    local function SelectSubTab(index)
        for i, btn in ipairs(tabButtons) do
            if i == index then
                -- ACTIVE: Dark background with thick mint border highlight + mint text
                pcall(btn.SetBackdropColor, btn, 0.12, 0.18, 0.18, 1)  -- Slightly tinted dark bg
                pcall(btn.SetBackdropBorderColor, btn, unpack(C.accent))
                btn.text:SetFont(GetFontPath(), 10, "")
                btn.text:SetTextColor(unpack(C.accent))  -- Mint colored text - easy to read
                tabContents[i]:Show()
            else
                -- INACTIVE: Standard dark look
                pcall(btn.SetBackdropColor, btn, 0.15, 0.15, 0.15, 1)
                pcall(btn.SetBackdropBorderColor, btn, 0.3, 0.3, 0.3, 1)
                btn.text:SetFont(GetFontPath(), 10, "")
                btn.text:SetTextColor(unpack(C.text))
                tabContents[i]:Hide()
            end
        end
        container.selectedTab = index
    end
    
    -- Button click handlers
    for i, btn in ipairs(tabButtons) do
        btn:SetScript("OnClick", function() SelectSubTab(i) end)
        btn:SetScript("OnEnter", function(self)
            if container.selectedTab ~= i then
                pcall(self.SetBackdropBorderColor, self, unpack(C.accentHover))
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if container.selectedTab ~= i then
                pcall(self.SetBackdropBorderColor, self, 0.3, 0.3, 0.3, 1)
            end
        end)
    end
    
    container.tabButtons = tabButtons
    container.tabContents = tabContents
    container.SelectTab = SelectSubTab
    container.RelayoutSubTabs = RelayoutSubTabs  -- Expose for external use if needed

    -- Select first tab by default
    SelectSubTab(1)

    -- Initial layout (deferred to ensure container has width from parent anchoring)
    C_Timer.After(0, RelayoutSubTabs)

    return container
end

---------------------------------------------------------------------------
-- WIDGET: DESCRIPTION TEXT
---------------------------------------------------------------------------
function GUI:CreateDescription(parent, text, color)
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(desc, 11, "", color or C.textMuted)
    desc:SetText(text)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    return desc
end

---------------------------------------------------------------------------
-- WIDGET: CHECKBOX
---------------------------------------------------------------------------
function GUI:CreateCheckbox(parent, label, dbKey, dbTable, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(300, 20)
    
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Checkmark (mint-colored using standard check but tinted)
    box.check = box:CreateTexture(nil, "OVERLAY")
    box.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.check:SetPoint("CENTER", 0, 0)
    box.check:SetSize(20, 20)
    box.check:SetVertexColor(0.204, 0.827, 0.6, 1)  -- Mint #34D399
    box.check:SetDesaturated(true)  -- Remove yellow, then apply mint
    box.check:Hide()
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)  -- Bumped from 11 to 12
    text:SetText(label or "Option")
    text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    
    container.box = box
    container.label = text
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end
    
    local function SetValue(val)
        container.checked = val
        if val then
            box.check:Show()
            box:SetBackdropBorderColor(unpack(C.accent))  -- Mint when checked
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(unpack(C.border))
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = SetValue
    SetValue(GetValue())
    
    box:SetScript("OnClick", function() SetValue(not GetValue()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, unpack(C.accentHover)) end)
    box:SetScript("OnLeave", function(self)
        if GetValue() then
            pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
        else
            pcall(self.SetBackdropBorderColor, self, unpack(C.border))
        end
    end)
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: CHECKBOX CENTERED (label centered above checkbox)
---------------------------------------------------------------------------
function GUI:CreateCheckboxCentered(parent, label, dbKey, dbTable, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(100, 40)  -- Taller to fit label above
    
    -- Label on top, centered
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 11, "", C.accentLight)  -- Mint like slider labels
    text:SetText(label or "Option")
    text:SetPoint("TOP", container, "TOP", 0, 0)
    
    -- Checkbox box below label, centered
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("TOP", text, "BOTTOM", 0, -4)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Checkmark
    box.check = box:CreateTexture(nil, "OVERLAY")
    box.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.check:SetPoint("CENTER", 0, 0)
    box.check:SetSize(20, 20)
    box.check:SetVertexColor(0.204, 0.827, 0.6, 1)
    box.check:SetDesaturated(true)
    box.check:Hide()
    
    container.box = box
    container.label = text
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end
    
    local function SetValue(val)
        container.checked = val
        if val then
            box.check:Show()
            box:SetBackdropBorderColor(unpack(C.accent))
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(unpack(C.border))
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = SetValue
    SetValue(GetValue())
    
    box:SetScript("OnClick", function() SetValue(not GetValue()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, unpack(C.accentHover)) end)
    box:SetScript("OnLeave", function(self)
        if GetValue() then
            pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
        else
            pcall(self.SetBackdropBorderColor, self, unpack(C.border))
        end
    end)
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: COLOR PICKER CENTERED (label centered above swatch)
---------------------------------------------------------------------------
function GUI:CreateColorPickerCentered(parent, label, dbKey, dbTable, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(100, 40)  -- Taller to fit label above
    
    -- Label on top, centered (mint like slider labels)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 11, "", C.accentLight)
    text:SetText(label or "Color")
    text:SetPoint("TOP", container, "TOP", 0, 0)
    
    -- Color swatch below label, centered
    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(16, 16)
    swatch:SetPoint("TOP", text, "BOTTOM", 0, -4)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    container.swatch = swatch
    container.label = text
    
    local function GetColor()
        if dbTable and dbKey then
            local c = dbTable[dbKey]
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        end
        return 1, 1, 1, 1
    end
    
    local function SetColor(r, g, b, a)
        swatch:SetBackdropColor(r, g, b, a or 1)
        if dbTable and dbKey then
            dbTable[dbKey] = {r, g, b, a or 1}
        end
        if onChange then onChange(r, g, b, a) end
    end
    
    -- Initialize color
    local r, g, b, a = GetColor()
    swatch:SetBackdropColor(r, g, b, a)
    
    container.GetColor = GetColor
    container.SetColor = SetColor
    
    -- Open color picker on click
    swatch:SetScript("OnClick", function()
        local r, g, b, a = GetColor()
        local originalA = a or 1
        local info = {
            hasOpacity = true,
            opacity = originalA,
            r = r, g = g, b = b,
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            opacityFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame:GetColorAlpha()
                SetColor(newR, newG, newB, newA)
            end,
            cancelFunc = function(prev)
                SetColor(prev.r, prev.g, prev.b, originalA)
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    swatch:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
    end)
    swatch:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.4, 0.4, 0.4, 1)
    end)
    
    return container
end

---------------------------------------------------------------------------
-- Inverted Checkbox: checked = false in DB, unchecked = true in DB
-- Use for "Hide X" options where DB stores "showX"
---------------------------------------------------------------------------
function GUI:CreateCheckboxInverted(parent, label, dbKey, dbTable, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(300, 20)
    
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    box.check = box:CreateTexture(nil, "OVERLAY")
    box.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.check:SetPoint("CENTER", 0, 0)
    box.check:SetSize(20, 20)
    box.check:SetVertexColor(0.204, 0.827, 0.6, 1)
    box.check:SetDesaturated(true)
    box.check:Hide()
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    
    container.box = box
    container.label = text
    
    -- INVERTED: DB true = unchecked, DB false = checked
    local function GetDBValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return true
    end
    
    local function IsChecked()
        return not GetDBValue()  -- Invert for display
    end
    
    local function SetChecked(checked)
        container.checked = checked
        local dbVal = not checked  -- Invert for storage
        if checked then
            box.check:Show()
            box:SetBackdropBorderColor(unpack(C.accent))
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(unpack(C.border))
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
        if dbTable and dbKey then dbTable[dbKey] = dbVal end
        if onChange then onChange(dbVal) end
    end
    
    container.GetValue = IsChecked
    container.SetValue = SetChecked
    SetChecked(IsChecked())
    
    box:SetScript("OnClick", function() SetChecked(not IsChecked()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, unpack(C.accentHover)) end)
    box:SetScript("OnLeave", function(self)
        if IsChecked() then
            pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
        else
            pcall(self.SetBackdropBorderColor, self, unpack(C.border))
        end
    end)
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: SLIDER (Full-width, stacks vertically like old GUI)
-- Layout: Label centered on top, slider bar below, min|editbox|max at bottom
-- Options table (optional 8th param): { deferOnDrag = true } to defer onChange until mouse release
---------------------------------------------------------------------------
function GUI:CreateSlider(parent, label, min, max, step, dbKey, dbTable, onChange, options)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(60)
    container:EnableMouse(true)  -- Block clicks from passing through to frames behind
    -- Width will be set by anchoring TOPLEFT and TOPRIGHT

    -- Parse options
    options = options or {}
    local deferOnDrag = options.deferOnDrag or false

    -- Label (top, centered, mint colored)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 11, "", C.accentLight)
    text:SetText(label or "Setting")
    text:SetPoint("TOP", 0, 0)

    -- Track container (for the filled + unfilled portions)
    local trackContainer = CreateFrame("Frame", nil, container)
    trackContainer:SetHeight(6)  -- Premium thinner track
    trackContainer:SetPoint("TOPLEFT", 35, -18)
    trackContainer:SetPoint("TOPRIGHT", -35, -18)

    -- Unfilled track (background)
    local trackBg = CreateFrame("Frame", nil, trackContainer, "BackdropTemplate")
    trackBg:SetAllPoints()
    trackBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    trackBg:SetBackdropColor(C.sliderTrack[1], C.sliderTrack[2], C.sliderTrack[3], 1)
    trackBg:SetBackdropBorderColor(0.1, 0.12, 0.15, 1)

    -- Filled track (mint portion from left to thumb)
    local trackFill = CreateFrame("Frame", nil, trackContainer, "BackdropTemplate")
    trackFill:SetPoint("TOPLEFT", 1, -1)
    trackFill:SetPoint("BOTTOMLEFT", 1, 1)
    trackFill:SetWidth(1)
    trackFill:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    trackFill:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Actual slider (invisible, just for interaction)
    local slider = CreateFrame("Slider", nil, trackContainer)
    slider:SetAllPoints()
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)
    slider:SetHitRectInsets(0, 0, -10, -10)  -- Expand hit area 10px above/below for reliable hover detection

    -- Thumb frame (white circle with border)
    local thumbFrame = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrame:SetSize(14, 14)
    thumbFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    thumbFrame:SetBackdropColor(C.sliderThumb[1], C.sliderThumb[2], C.sliderThumb[3], 1)
    thumbFrame:SetBackdropBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
    thumbFrame:SetFrameLevel(slider:GetFrameLevel() + 2)
    thumbFrame:EnableMouse(false)  -- Let clicks pass through to slider

    -- Hidden thumb texture for slider mechanics
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(14, 14)
    thumb:SetAlpha(0)

    -- Min label (left of slider)
    local minText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(minText, 10, "", C.textMuted)
    minText:SetText(tostring(min or 0))
    minText:SetPoint("RIGHT", trackContainer, "LEFT", -5, 0)

    -- Max label (right of slider)
    local maxText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(maxText, 10, "", C.textMuted)
    maxText:SetText(tostring(max or 100))
    maxText:SetPoint("LEFT", trackContainer, "RIGHT", 5, 0)

    -- Editbox for value (center, below slider)
    local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editBox:SetSize(70, 22)
    editBox:SetPoint("TOP", trackContainer, "BOTTOM", 0, -6)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    editBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
    editBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    editBox:SetFont(GetFontPath(), 11, "")
    editBox:SetTextColor(unpack(C.text))
    editBox:SetJustifyH("CENTER")
    editBox:SetAutoFocus(false)

    -- Configure slider
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)

    container.slider = slider
    container.editBox = editBox
    container.trackFill = trackFill
    container.thumbFrame = thumbFrame
    container.trackContainer = trackContainer
    container.min = min or 0
    container.max = max or 100
    container.step = step or 1

    -- Track dragging state for deferOnDrag mode
    local isDragging = false

    -- Update filled track and thumb position
    local function UpdateTrackFill(value)
        local minVal, maxVal = container.min, container.max
        local pct = (value - minVal) / (maxVal - minVal)
        pct = math.max(0, math.min(1, pct))

        local trackWidth = trackContainer:GetWidth() - 2
        local fillWidth = math.max(1, pct * trackWidth)
        trackFill:SetWidth(fillWidth)

        local thumbX = pct * (trackWidth - 14) + 7
        thumbFrame:ClearAllPoints()
        thumbFrame:SetPoint("CENTER", trackContainer, "LEFT", thumbX + 1, 0)
    end

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] or container.min end
        return container.value or container.min
    end

    local function FormatVal(val)
        if container.step >= 1 then
            return tostring(math.floor(val))
        else
            return string.format("%.2f", val)
        end
    end

    local function SetValue(val, skipCallback)
        val = math.max(container.min, math.min(container.max, val))
        if container.step >= 1 then
            val = math.floor(val / container.step + 0.5) * container.step
        else
            local mult = 1 / container.step
            val = math.floor(val * mult + 0.5) / mult
        end

        container.value = val
        slider:SetValue(val)
        editBox:SetText(FormatVal(val))
        UpdateTrackFill(val)

        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange and not skipCallback then onChange(val) end
    end

    container.GetValue = GetValue
    container.SetValue = SetValue

    -- Slider drag callback
    slider:SetScript("OnValueChanged", function(self, value)
        if container.step >= 1 then
            value = math.floor(value / container.step + 0.5) * container.step
        else
            local mult = 1 / container.step
            value = math.floor(value * mult + 0.5) / mult
        end
        editBox:SetText(FormatVal(value))
        container.value = value
        UpdateTrackFill(value)
        if dbTable and dbKey then dbTable[dbKey] = value end

        -- If deferOnDrag, only call onChange when not dragging (or on release)
        if deferOnDrag then
            if not isDragging then
                if onChange then onChange(value) end
            end
        else
            if onChange then onChange(value) end
        end
    end)

    -- Track mouse down/up for deferOnDrag mode
    slider:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
        end
    end)

    slider:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and isDragging then
            isDragging = false
            if deferOnDrag and onChange then
                local value = self:GetValue()
                if container.step >= 1 then
                    value = math.floor(value / container.step + 0.5) * container.step
                else
                    local mult = 1 / container.step
                    value = math.floor(value * mult + 0.5) / mult
                end
                onChange(value)
            end
        end
    end)

    -- Hover effects
    slider:SetScript("OnEnter", function()
        thumbFrame:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    slider:SetScript("OnLeave", function()
        thumbFrame:SetBackdropBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then SetValue(val) end
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        editBox:SetText(FormatVal(GetValue()))
        self:ClearFocus()
    end)

    -- Hover effect on editbox
    editBox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end)
    editBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        end
    end)

    -- Initialize after a brief delay to ensure width is calculated
    C_Timer.After(0, function()
        SetValue(GetValue(), true)
    end)

    return container
end

---------------------------------------------------------------------------
-- WIDGET: DROPDOWN (Matches slider width with same 35px inset, same height for alignment)
---------------------------------------------------------------------------
local CHEVRON_ZONE_WIDTH = 28
local CHEVRON_BG_ALPHA = 0.15
local CHEVRON_BG_ALPHA_HOVER = 0.25
local CHEVRON_TEXT_ALPHA = 0.7

function GUI:CreateDropdown(parent, label, options, dbKey, dbTable, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(60)  -- Match slider height for vertical alignment
    container:SetWidth(200)  -- Default width, can be overridden by SetWidth()

    -- Label on top (if provided) - mint green like slider labels, centered
    if label and label ~= "" then
        local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 11, "", C.accentLight)  -- Mint green like other labels
        text:SetText(label)
        text:SetPoint("TOP", container, "TOP", 0, 0)  -- Centered
    end

    -- Dropdown button (same width as slider track - inset 35px on each side)
    local dropdown = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropdown:SetHeight(24)  -- Increased from 20 for better tap target
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 35, -16)
    dropdown:SetPoint("RIGHT", container, "RIGHT", -35, 0)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 1)
    dropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)  -- Increased from 0.25 for better visibility

    -- Chevron zone (right side with accent tint)
    local chevronZone = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    chevronZone:SetWidth(CHEVRON_ZONE_WIDTH)
    chevronZone:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1)
    chevronZone:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -1, 1)
    chevronZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)

    -- Separator line (left edge of chevron zone)
    local separator = chevronZone:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", chevronZone, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", chevronZone, "BOTTOMLEFT", 0, 0)
    separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    -- Line chevron (two angled lines forming a V pointing DOWN)
    local chevronLeft = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronLeft:SetSize(7, 2)
    chevronLeft:SetPoint("CENTER", chevronZone, "CENTER", -2, -1)
    chevronLeft:SetRotation(math.rad(-45))

    local chevronRight = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronRight:SetSize(7, 2)
    chevronRight:SetPoint("CENTER", chevronZone, "CENTER", 2, -1)
    chevronRight:SetRotation(math.rad(45))

    dropdown.chevronLeft = chevronLeft
    dropdown.chevronRight = chevronRight
    dropdown.chevronZone = chevronZone
    dropdown.separator = separator

    -- Selected text - centered, accounting for chevron zone
    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 11, "", C.text)
    dropdown.selected:SetPoint("LEFT", 8, 0)
    dropdown.selected:SetPoint("RIGHT", chevronZone, "LEFT", -5, 0)
    dropdown.selected:SetJustifyH("CENTER")

    -- Hover effect
    dropdown:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA_HOVER)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.35, 0.35, 0.35, 1)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    end)
    
    container.dropdown = dropdown
    
    -- Normalize options to {value, text} format
    local normalizedOptions = {}
    if type(options) == "table" then
        for i, opt in ipairs(options) do
            if type(opt) == "table" then
                normalizedOptions[i] = opt
            else
                -- Simple string array like {"Up", "Down"}
                normalizedOptions[i] = {value = opt:lower(), text = opt}
            end
        end
    end
    container.options = normalizedOptions
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.value
    end
    
    local function GetDisplayText(val)
        for _, opt in ipairs(container.options) do
            if opt.value == val then return opt.text end
        end
        -- If not found, capitalize first letter
        if type(val) == "string" then
            return val:sub(1,1):upper() .. val:sub(2)
        end
        return tostring(val or "Select...")
    end
    
    local function SetValue(val, skipCallback)
        container.value = val
        dropdown.selected:SetText(GetDisplayText(val))
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange and not skipCallback then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = SetValue
    
    -- Initialize with current value
    SetValue(GetValue(), true)
    
    -- Dropdown menu frame (created once, reused)
    local menuFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    menuFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menuFrame:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
    menuFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menuFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    menuFrame:SetBackdropBorderColor(unpack(C.accent))
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:Hide()
    
    local menuButtons = {}
    local buttonHeight = 22
    
    for i, opt in ipairs(container.options) do
        local btn = CreateFrame("Button", nil, menuFrame, "BackdropTemplate")
        btn:SetHeight(buttonHeight)
        btn:SetPoint("TOPLEFT", 2, -2 - (i-1) * buttonHeight)
        btn:SetPoint("TOPRIGHT", -2, -2 - (i-1) * buttonHeight)
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(btn.text, 11, "", C.text)
        btn.text:SetText(opt.text)
        btn.text:SetPoint("LEFT", 8, 0)
        
        btn:SetScript("OnEnter", function(self)
            pcall(function()
                self:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                self:SetBackdropColor(0.204, 0.827, 0.6, 0.25)  -- Mint at 25% opacity (ghost)
            end)
            -- Keep text white
        end)
        btn:SetScript("OnLeave", function(self)
            pcall(function()
                self:SetBackdrop(nil)
            end)
        end)
        btn:SetScript("OnClick", function()
            SetValue(opt.value)
            menuFrame:Hide()
        end)
        
        menuButtons[i] = btn
    end
    
    menuFrame:SetHeight(4 + #container.options * buttonHeight)
    
    -- Toggle menu on click
    dropdown:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide()
        else
            menuFrame:Show()
        end
    end)
    
    -- Close menu when clicking elsewhere (with delay to handle gap)
    local closeTimer = 0
    local CLOSE_DELAY = 0.15  -- 150ms grace period
    
    menuFrame:SetScript("OnShow", function()
        closeTimer = 0
        menuFrame.__checkElapsed = 0
        menuFrame:SetScript("OnUpdate", function(self, elapsed)
            -- Throttle checks to ~15 FPS (66ms) for CPU efficiency
            self.__checkElapsed = self.__checkElapsed + elapsed
            if self.__checkElapsed < 0.066 then return end
            local deltaTime = self.__checkElapsed
            self.__checkElapsed = 0

            -- Check if mouse is over dropdown button OR menu (with tolerance)
            local isOverDropdown = dropdown:IsMouseOver()
            local isOverMenu = self:IsMouseOver()

            -- Also check if mouse is in the gap between them
            local scale = dropdown:GetEffectiveScale()
            local mouseX, mouseY = GetCursorPosition()
            mouseX, mouseY = mouseX / scale, mouseY / scale

            local dLeft, dBottom, dWidth, dHeight = dropdown:GetRect()
            local mLeft, mBottom, mWidth, mHeight = self:GetRect()

            if dLeft and mLeft then
                -- Check if mouse X is within the dropdown/menu horizontal bounds
                local inHorizontalBounds = mouseX >= dLeft and mouseX <= (dLeft + dWidth)
                -- Check if mouse Y is between the bottom of dropdown and top of menu (the gap)
                local inGap = mouseY >= mBottom and mouseY <= (dBottom + dHeight) and inHorizontalBounds

                if isOverDropdown or isOverMenu or inGap then
                    closeTimer = 0
                else
                    closeTimer = closeTimer + deltaTime
                    if closeTimer > CLOSE_DELAY then
                        self:Hide()
                    end
                end
            else
                -- Fallback if GetRect fails
                if not isOverDropdown and not isOverMenu then
                    closeTimer = closeTimer + deltaTime
                    if closeTimer > CLOSE_DELAY then
                        self:Hide()
                    end
                else
                    closeTimer = 0
                end
            end
        end)
    end)
    
    menuFrame:SetScript("OnHide", function()
        menuFrame:SetScript("OnUpdate", nil)
        closeTimer = 0
    end)
    
    return container
end

---------------------------------------------------------------------------
-- WIDGET: DROPDOWN FULL WIDTH (For pages like Spec Profiles - no inset)
---------------------------------------------------------------------------
function GUI:CreateDropdownFullWidth(parent, label, options, dbKey, dbTable, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(45)  -- Compact height for full-width dropdowns
    container:SetWidth(200)  -- Default width, can be overridden by SetWidth()

    -- Label on top (if provided) - mint green, centered
    if label and label ~= "" then
        local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(text, 11, "", C.accentLight)
        text:SetText(label)
        text:SetPoint("TOP", container, "TOP", 0, 0)
    end

    -- Dropdown button (full width, no inset)
    local dropdown = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropdown:SetHeight(24)
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -18)
    dropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 1)
    dropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)  -- Increased from 0.25

    -- Chevron zone (right side with accent tint)
    local chevronZone = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    chevronZone:SetWidth(CHEVRON_ZONE_WIDTH)
    chevronZone:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1)
    chevronZone:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -1, 1)
    chevronZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)

    -- Separator line (left edge of chevron zone)
    local separator = chevronZone:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", chevronZone, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", chevronZone, "BOTTOMLEFT", 0, 0)
    separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    -- Line chevron (two angled lines forming a V pointing DOWN)
    local chevronLeft = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronLeft:SetSize(7, 2)
    chevronLeft:SetPoint("CENTER", chevronZone, "CENTER", -2, -1)
    chevronLeft:SetRotation(math.rad(-45))

    local chevronRight = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronRight:SetSize(7, 2)
    chevronRight:SetPoint("CENTER", chevronZone, "CENTER", 2, -1)
    chevronRight:SetRotation(math.rad(45))

    dropdown.chevronLeft = chevronLeft
    dropdown.chevronRight = chevronRight
    dropdown.chevronZone = chevronZone
    dropdown.separator = separator

    -- Selected text - centered, accounting for chevron zone
    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 11, "", C.text)
    dropdown.selected:SetPoint("LEFT", 10, 0)
    dropdown.selected:SetPoint("RIGHT", chevronZone, "LEFT", -5, 0)
    dropdown.selected:SetJustifyH("CENTER")

    -- Hover effect
    dropdown:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA_HOVER)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.35, 0.35, 0.35, 1)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    end)

    container.dropdown = dropdown

    -- Normalize options
    local normalizedOptions = {}
    if type(options) == "table" then
        for i, opt in ipairs(options) do
            if type(opt) == "table" then
                normalizedOptions[i] = opt
            else
                normalizedOptions[i] = {value = opt:lower(), text = opt}
            end
        end
    end
    container.options = normalizedOptions
    
    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.value
    end
    
    local function GetDisplayText(val)
        for _, opt in ipairs(container.options) do
            if opt.value == val then return opt.text end
        end
        if type(val) == "string" then
            return val:sub(1,1):upper() .. val:sub(2)
        end
        return tostring(val or "Select...")
    end
    
    local function SetValue(val, skipCallback)
        container.value = val
        dropdown.selected:SetText(GetDisplayText(val))
        if dbTable and dbKey then dbTable[dbKey] = val end
        if onChange and not skipCallback then onChange(val) end
    end
    
    container.GetValue = GetValue
    container.SetValue = SetValue
    SetValue(GetValue(), true)
    
    -- Dropdown menu
    local menuFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    menuFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menuFrame:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
    menuFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menuFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    menuFrame:SetBackdropBorderColor(unpack(C.accent))
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:Hide()
    
    local buttonHeight = 22
    for i, opt in ipairs(container.options) do
        local btn = CreateFrame("Button", nil, menuFrame, "BackdropTemplate")
        btn:SetHeight(buttonHeight)
        btn:SetPoint("TOPLEFT", 2, -2 - (i-1) * buttonHeight)
        btn:SetPoint("TOPRIGHT", -2, -2 - (i-1) * buttonHeight)
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        SetFont(btn.text, 11, "", C.text)
        btn.text:SetText(opt.text)
        btn.text:SetPoint("LEFT", 8, 0)
        
        btn:SetScript("OnEnter", function(self)
            pcall(function()
                self:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                self:SetBackdropColor(0.204, 0.827, 0.6, 0.25)  -- Mint at 25% opacity (ghost)
            end)
            -- Keep text white
        end)
        btn:SetScript("OnLeave", function(self)
            pcall(function() self:SetBackdrop(nil) end)
        end)
        btn:SetScript("OnClick", function()
            SetValue(opt.value)
            menuFrame:Hide()
        end)
    end
    
    menuFrame:SetHeight(4 + #container.options * buttonHeight)
    
    dropdown:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide()
        else
            menuFrame:Show()
        end
    end)
    
    -- Close menu when clicking elsewhere
    local closeTimer = 0
    menuFrame:SetScript("OnShow", function()
        closeTimer = 0
        menuFrame.__checkElapsed = 0
        menuFrame:SetScript("OnUpdate", function(self, elapsed)
            -- Throttle checks to ~15 FPS (66ms) for CPU efficiency
            self.__checkElapsed = self.__checkElapsed + elapsed
            if self.__checkElapsed < 0.066 then return end
            local deltaTime = self.__checkElapsed
            self.__checkElapsed = 0

            local isOverDropdown = dropdown:IsMouseOver()
            local isOverMenu = self:IsMouseOver()
            if not isOverDropdown and not isOverMenu then
                closeTimer = closeTimer + deltaTime
                if closeTimer > 0.15 then
                    self:Hide()
                end
            else
                closeTimer = 0
            end
        end)
    end)

    menuFrame:SetScript("OnHide", function()
        menuFrame:SetScript("OnUpdate", nil)
        closeTimer = 0
    end)

    return container
end

---------------------------------------------------------------------------
-- FORM WIDGETS (Label on left, widget on right)
---------------------------------------------------------------------------

local FORM_ROW_HEIGHT = 28

---------------------------------------------------------------------------
-- WIDGET: iOS-STYLE TOGGLE SWITCH (Premium)
-- Track: 40x20px, fully rounded
-- OFF: Dark grey track, white circle on left
-- ON: Mint track, white circle slides to right
---------------------------------------------------------------------------
function GUI:CreateFormToggle(parent, label, dbKey, dbTable, onChange, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", 0, 0)

    -- Toggle track (the pill-shaped background)
    local track = CreateFrame("Button", nil, container, "BackdropTemplate")
    track:SetSize(40, 20)
    track:SetPoint("LEFT", container, "LEFT", 180, 0)
    track:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    -- Thumb (the sliding circle)
    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:SetSize(16, 16)
    thumb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    thumb:SetBackdropColor(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
    thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)

    container.track = track
    container.thumb = thumb
    container.label = text

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end

    local function UpdateVisual(val)
        if val then
            -- ON state: Mint track, thumb on right
            track:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
            track:SetBackdropBorderColor(C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1)
            thumb:ClearAllPoints()
            thumb:SetPoint("RIGHT", track, "RIGHT", -2, 0)
        else
            -- OFF state: Dark grey track, thumb on left
            track:SetBackdropColor(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1)
            track:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0)
        end
    end

    local function SetValue(val, skipCallback)
        container.checked = val
        UpdateVisual(val)
        if dbTable and dbKey then dbTable[dbKey] = val end
        BroadcastToSiblings(container, val)
        if onChange and not skipCallback then onChange(val) end
    end

    container.GetValue = GetValue
    container.SetValue = SetValue
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)

    SetValue(GetValue(), true)  -- Skip callback on init

    -- Click to toggle
    track:SetScript("OnClick", function() SetValue(not GetValue()) end)

    -- Hover effects
    track:SetScript("OnEnter", function(self)
        if GetValue() then
            self:SetBackdropBorderColor(C.accentHover[1], C.accentHover[2], C.accentHover[3], 1)
        else
            self:SetBackdropBorderColor(0.25, 0.28, 0.35, 1)
        end
    end)
    track:SetScript("OnLeave", function(self)
        if GetValue() then
            self:SetBackdropBorderColor(C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1)
        else
            self:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
        end
    end)

    -- Enable/disable the toggle (for conditional UI)
    container.SetEnabled = function(self, enabled)
        track:EnableMouse(enabled)
        -- Visual feedback: dim when disabled
        container:SetAlpha(enabled and 1 or 0.4)
    end

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0)
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            local entry = {
                label = label,
                widgetType = "toggle",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormToggle(p, label, dbKey, dbTable, onChange)
                end,
            }
            -- Add keywords from registryInfo if provided
            if registryInfo and registryInfo.keywords then
                entry.keywords = registryInfo.keywords
            end
            table.insert(GUI.SettingsRegistry, entry)
        end
    end

    return container
end

-- Inverted toggle: checked = DB false, unchecked = DB true (for "Hide X" options)
function GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", 0, 0)

    -- Toggle track
    local track = CreateFrame("Button", nil, container, "BackdropTemplate")
    track:SetSize(40, 20)
    track:SetPoint("LEFT", container, "LEFT", 180, 0)
    track:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    -- Thumb
    local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
    thumb:SetSize(16, 16)
    thumb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    thumb:SetBackdropColor(C.toggleThumb[1], C.toggleThumb[2], C.toggleThumb[3], 1)
    thumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)

    container.track = track
    container.thumb = thumb
    container.label = text

    -- INVERTED: DB true = toggle OFF, DB false = toggle ON
    local function GetDBValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return true
    end

    local function IsOn()
        return not GetDBValue()  -- Invert for display
    end

    local function UpdateVisual(isOn)
        if isOn then
            track:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
            track:SetBackdropBorderColor(C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1)
            thumb:ClearAllPoints()
            thumb:SetPoint("RIGHT", track, "RIGHT", -2, 0)
        else
            track:SetBackdropColor(C.toggleOff[1], C.toggleOff[2], C.toggleOff[3], 1)
            track:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0)
        end
    end

    local function SetOn(isOn, skipCallback)
        container.checked = isOn
        local dbVal = not isOn  -- Invert for storage
        UpdateVisual(isOn)
        if dbTable and dbKey then dbTable[dbKey] = dbVal end
        BroadcastToSiblings(container, isOn)
        if onChange and not skipCallback then onChange(dbVal) end
    end

    container.GetValue = IsOn
    container.SetValue = SetOn
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)

    SetOn(IsOn(), true)  -- Skip callback on init

    track:SetScript("OnClick", function() SetOn(not IsOn()) end)

    track:SetScript("OnEnter", function(self)
        if IsOn() then
            self:SetBackdropBorderColor(C.accentHover[1], C.accentHover[2], C.accentHover[3], 1)
        else
            self:SetBackdropBorderColor(0.25, 0.28, 0.35, 1)
        end
    end)
    track:SetScript("OnLeave", function(self)
        if IsOn() then
            self:SetBackdropBorderColor(C.accent[1] * 0.8, C.accent[2] * 0.8, C.accent[3] * 0.8, 1)
        else
            self:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
        end
    end)

    -- Enable/disable the toggle (for conditional UI)
    container.SetEnabled = function(self, enabled)
        track:EnableMouse(enabled)
        -- Visual feedback: dim when disabled
        container:SetAlpha(enabled and 1 or 0.4)
    end

    return container
end

---------------------------------------------------------------------------
-- WIDGET: FORM CHECKBOX (Now uses Toggle Switch style!)
---------------------------------------------------------------------------
function GUI:CreateFormCheckbox(parent, label, dbKey, dbTable, onChange, registryInfo)
    -- Redirect to toggle for the premium look
    return GUI:CreateFormToggle(parent, label, dbKey, dbTable, onChange, registryInfo)
end

-- Keep original checkbox available for multi-select scenarios
function GUI:CreateFormCheckboxOriginal(parent, label, dbKey, dbTable, onChange)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Option")
    text:SetPoint("LEFT", 0, 0)

    -- Checkbox aligned with other widgets (starts at 180px from left)
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(18, 18)
    box:SetPoint("LEFT", container, "LEFT", 180, 0)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.1, 0.1, 0.1, 1)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Checkmark
    box.check = box:CreateTexture(nil, "OVERLAY")
    box.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box.check:SetPoint("CENTER", 0, 0)
    box.check:SetSize(22, 22)
    box.check:SetVertexColor(0.204, 0.827, 0.6, 1)
    box.check:SetDesaturated(true)
    box.check:Hide()

    container.box = box
    container.label = text

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.checked
    end

    local function UpdateVisual(val)
        if val then
            box.check:Show()
            box:SetBackdropBorderColor(unpack(C.accent))
            box:SetBackdropColor(0.1, 0.2, 0.15, 1)
        else
            box.check:Hide()
            box:SetBackdropBorderColor(unpack(C.border))
            box:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
    end

    local function SetValue(val, skipCallback)
        container.checked = val
        UpdateVisual(val)
        if dbTable and dbKey then dbTable[dbKey] = val end
        BroadcastToSiblings(container, val)
        if onChange and not skipCallback then onChange(val) end
    end

    container.GetValue = GetValue
    container.SetValue = SetValue
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)

    SetValue(GetValue(), true)

    box:SetScript("OnClick", function() SetValue(not GetValue()) end)
    box:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, unpack(C.accentHover)) end)
    box:SetScript("OnLeave", function(self)
        if GetValue() then
            pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
        else
            pcall(self.SetBackdropBorderColor, self, unpack(C.border))
        end
    end)

    return container
end

-- Form Checkbox Inverted: checked = DB false, unchecked = DB true (for "Hide X" options)
function GUI:CreateFormCheckboxInverted(parent, label, dbKey, dbTable, onChange)
    -- Redirect to toggle inverted for the premium look
    return GUI:CreateFormToggleInverted(parent, label, dbKey, dbTable, onChange)
end

function GUI:CreateFormSlider(parent, label, min, max, step, dbKey, dbTable, onChange, options, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)
    container:EnableMouse(true)  -- Block clicks from passing through to frames behind

    options = options or {}
    local deferOnDrag = options.deferOnDrag or false
    local precision = options.precision
    local formatStr = precision and string.format("%%.%df", precision) or (step < 1 and "%.2f" or "%d")

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Setting")
    text:SetPoint("LEFT", 0, 0)
    container.label = text

    -- Track container (for the filled + unfilled portions)
    local trackContainer = CreateFrame("Frame", nil, container)
    trackContainer:SetHeight(6)  -- Thicker track (was 14, now 6 for cleaner look)
    trackContainer:SetPoint("LEFT", container, "LEFT", 180, 0)
    trackContainer:SetPoint("RIGHT", container, "RIGHT", -70, 0)

    -- Unfilled track (background) - rounded appearance via backdrop
    local trackBg = CreateFrame("Frame", nil, trackContainer, "BackdropTemplate")
    trackBg:SetAllPoints()
    trackBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    trackBg:SetBackdropColor(C.sliderTrack[1], C.sliderTrack[2], C.sliderTrack[3], 1)
    trackBg:SetBackdropBorderColor(0.1, 0.12, 0.15, 1)

    -- Filled track (mint portion from left to thumb)
    local trackFill = CreateFrame("Frame", nil, trackContainer, "BackdropTemplate")
    trackFill:SetPoint("TOPLEFT", 1, -1)
    trackFill:SetPoint("BOTTOMLEFT", 1, 1)
    trackFill:SetWidth(1)  -- Will be updated dynamically
    trackFill:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    trackFill:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Actual slider (invisible, just for interaction)
    local slider = CreateFrame("Slider", nil, trackContainer)
    slider:SetAllPoints()
    slider:SetOrientation("HORIZONTAL")
    slider:SetHitRectInsets(0, 0, -10, -10)  -- Expand hit area 10px above/below for reliable hover detection

    -- Thumb frame (white circle with border)
    local thumbFrame = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrame:SetSize(14, 14)
    thumbFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    thumbFrame:SetBackdropColor(C.sliderThumb[1], C.sliderThumb[2], C.sliderThumb[3], 1)
    thumbFrame:SetBackdropBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
    thumbFrame:SetFrameLevel(slider:GetFrameLevel() + 2)
    thumbFrame:EnableMouse(false)  -- Let clicks pass through to slider

    -- Round the thumb corners using a mask texture overlay
    local thumbRound = thumbFrame:CreateTexture(nil, "OVERLAY")
    thumbRound:SetAllPoints()
    thumbRound:SetColorTexture(1, 1, 1, 0)  -- Invisible, just for structure

    -- Use the thumb frame as the visual, position it manually
    slider.thumbFrame = thumbFrame

    -- Hidden thumb texture for slider mechanics
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(14, 14)
    thumb:SetAlpha(0)  -- Hide the actual thumb, we use thumbFrame instead

    -- Editbox for value (far right)
    local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editBox:SetSize(60, 22)
    editBox:SetPoint("RIGHT", 0, 0)
    editBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    editBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
    editBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    editBox:SetFont(GetFontPath(), 11, "")
    editBox:SetTextColor(unpack(C.text))
    editBox:SetJustifyH("CENTER")
    editBox:SetAutoFocus(false)

    -- Configure slider
    slider:SetMinMaxValues(min or 0, max or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)

    container.slider = slider
    container.editBox = editBox
    container.trackFill = trackFill
    container.thumbFrame = thumbFrame
    container.trackContainer = trackContainer
    container.min = min or 0
    container.max = max or 100
    container.step = step or 1

    local isDragging = false

    -- Update filled track and thumb position
    local function UpdateTrackFill(value)
        local minVal, maxVal = container.min, container.max
        local pct = (value - minVal) / (maxVal - minVal)
        pct = math.max(0, math.min(1, pct))

        local trackWidth = trackContainer:GetWidth() - 2  -- Account for border
        local fillWidth = math.max(1, pct * trackWidth)
        trackFill:SetWidth(fillWidth)

        -- Position the thumb frame
        local thumbX = pct * (trackWidth - 14) + 7  -- Center thumb on fill edge
        thumbFrame:SetPoint("CENTER", trackContainer, "LEFT", thumbX + 1, 0)
    end

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] or container.min end
        return container.value or container.min
    end

    local function UpdateVisual(val)
        val = math.max(container.min, math.min(container.max, val))
        if not precision then
            val = math.floor(val / container.step + 0.5) * container.step
        end
        slider:SetValue(val)
        editBox:SetText(string.format(formatStr, val))
        UpdateTrackFill(val)
    end

    local function SetValue(val, skipOnChange)
        val = math.max(container.min, math.min(container.max, val))
        if precision then
            local factor = 10 ^ precision
            val = math.floor(val * factor + 0.5) / factor
        else
            val = math.floor(val / container.step + 0.5) * container.step
        end
        container.value = val
        UpdateVisual(val)
        if dbTable and dbKey then dbTable[dbKey] = val end
        BroadcastToSiblings(container, val)
        if not skipOnChange and onChange then onChange(val) end
    end

    container.GetValue = GetValue
    container.SetValue = SetValue
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)

    slider:SetScript("OnValueChanged", function(self, value, userInput)
        -- Ignore user input if slider is disabled
        if userInput and container.isEnabled == false then return end

        value = math.floor(value / container.step + 0.5) * container.step
        editBox:SetText(string.format(formatStr, value))
        UpdateTrackFill(value)
        if dbTable and dbKey then dbTable[dbKey] = value end
        if userInput then
            BroadcastToSiblings(container, value)
            if deferOnDrag and isDragging then return end
            if onChange then onChange(value) end
        end
    end)

    slider:SetScript("OnMouseDown", function() isDragging = true end)
    slider:SetScript("OnMouseUp", function()
        if isDragging and deferOnDrag then
            isDragging = false
            if onChange then onChange(slider:GetValue()) end
        end
        isDragging = false
    end)

    -- Hover effects on thumb
    slider:SetScript("OnEnter", function()
        thumbFrame:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    slider:SetScript("OnLeave", function()
        thumbFrame:SetBackdropBorderColor(C.sliderThumbBorder[1], C.sliderThumbBorder[2], C.sliderThumbBorder[3], 1)
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or container.min
        SetValue(val)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(string.format(formatStr, GetValue()))
        self:ClearFocus()
    end)

    -- Hover effect on editbox
    editBox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end)
    editBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        end
    end)

    -- Re-update track fill when container size changes (fixes initial layout timing)
    trackContainer:SetScript("OnSizeChanged", function(self, width, height)
        if width and width > 0 then
            UpdateTrackFill(GetValue())
        end
    end)

    -- Initialize value (visual update will happen via OnSizeChanged when layout completes)
    SetValue(GetValue(), true)

    -- Enable/disable the slider (for conditional UI)
    -- Note: Uses self parameter for colon-call syntax (widget:SetEnabled(bool))
    container.SetEnabled = function(self, enabled)
        slider:EnableMouse(enabled)
        editBox:EnableMouse(enabled)
        editBox:SetEnabled(enabled)

        -- Store state for scripts to check
        container.isEnabled = enabled

        -- Visual feedback: dim when disabled (matches HUD Visibility pattern)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    -- Initialize enabled state
    container.isEnabled = true

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0)
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            table.insert(GUI.SettingsRegistry, {
                label = label,
                widgetType = "slider",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormSlider(p, label, min, max, step, dbKey, dbTable, onChange, options)
                end,
            })
        end
    end

    return container
end

function GUI:CreateFormDropdown(parent, label, options, dbKey, dbTable, onChange, registryInfo)
    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Setting")
    text:SetPoint("LEFT", 0, 0)

    -- Dropdown button (right side)
    local dropdown = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropdown:SetHeight(24)  -- Increased from 22
    dropdown:SetPoint("LEFT", container, "LEFT", 180, 0)
    dropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 1)
    dropdown:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)  -- Increased from 0.25

    -- Chevron zone (right side with accent tint)
    local chevronZone = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    chevronZone:SetWidth(CHEVRON_ZONE_WIDTH)
    chevronZone:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1)
    chevronZone:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -1, 1)
    chevronZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)

    -- Separator line (left edge of chevron zone)
    local separator = chevronZone:CreateTexture(nil, "ARTWORK")
    separator:SetWidth(1)
    separator:SetPoint("TOPLEFT", chevronZone, "TOPLEFT", 0, 0)
    separator:SetPoint("BOTTOMLEFT", chevronZone, "BOTTOMLEFT", 0, 0)
    separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)

    -- Line chevron (two angled lines forming a V pointing DOWN)
    local chevronLeft = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronLeft:SetSize(7, 2)
    chevronLeft:SetPoint("CENTER", chevronZone, "CENTER", -2, -1)
    chevronLeft:SetRotation(math.rad(-45))

    local chevronRight = chevronZone:CreateTexture(nil, "OVERLAY")
    chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    chevronRight:SetSize(7, 2)
    chevronRight:SetPoint("CENTER", chevronZone, "CENTER", 2, -1)
    chevronRight:SetRotation(math.rad(45))

    dropdown.chevronLeft = chevronLeft
    dropdown.chevronRight = chevronRight
    dropdown.chevronZone = chevronZone
    dropdown.separator = separator

    -- Selected text, accounting for chevron zone
    dropdown.selected = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(dropdown.selected, 11, "", C.text)
    dropdown.selected:SetPoint("LEFT", 8, 0)
    dropdown.selected:SetPoint("RIGHT", chevronZone, "LEFT", -5, 0)
    dropdown.selected:SetJustifyH("LEFT")

    -- Hover effect
    dropdown:SetScript("OnEnter", function(self)
        pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA_HOVER)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.35, 0.35, 0.35, 1)
        chevronZone:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], CHEVRON_BG_ALPHA)
        separator:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        chevronLeft:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
        chevronRight:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], CHEVRON_TEXT_ALPHA)
    end)

    -- Menu frame
    local menuFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
    menuFrame:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menuFrame:SetPoint("TOPRIGHT", dropdown, "BOTTOMRIGHT", 0, -2)
    menuFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menuFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    menuFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:SetClipsChildren(true)
    menuFrame:Hide()

    -- Scroll frame for long option lists
    local scrollFrame = CreateFrame("ScrollFrame", nil, menuFrame)
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollFrame:EnableMouseWheel(true)

    -- Scroll content (child frame)
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetWidth(menuFrame:GetWidth() or 200)
    scrollFrame:SetScrollChild(scrollContent)
    menuFrame.scrollContent = scrollContent

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = self:GetVerticalScroll()
        local maxScroll = math.max(0, scrollContent:GetHeight() - menuFrame:GetHeight())
        local newScroll = currentScroll - (delta * 20)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
    end)

    -- Update scroll content width when menu opens
    menuFrame:SetScript("OnShow", function(self)
        scrollContent:SetWidth(self:GetWidth() - 2)
    end)

    container.dropdown = dropdown
    container.menuFrame = menuFrame
    container.options = options or {}

    local function GetValue()
        if dbTable and dbKey then return dbTable[dbKey] end
        return container.selectedValue
    end

    local function UpdateVisual(val)
        for _, opt in ipairs(container.options) do
            if opt.value == val then
                dropdown.selected:SetText(opt.text)
                break
            end
        end
    end

    local function SetValue(val, skipOnChange)
        container.selectedValue = val
        if dbTable and dbKey then dbTable[dbKey] = val end
        UpdateVisual(val)
        BroadcastToSiblings(container, val)
        if not skipOnChange and onChange then onChange(val) end
    end

    local function BuildMenu()
        -- Clear existing children from scroll content
        local scrollContent = menuFrame.scrollContent
        if scrollContent then
            for _, child in ipairs({scrollContent:GetChildren()}) do child:Hide() end
        end

        local yOff = -4
        local itemHeight = 20
        local maxVisibleItems = 8
        local numItems = #container.options

        for i, opt in ipairs(container.options) do
            local btn = CreateFrame("Button", nil, scrollContent or menuFrame)
            btn:SetHeight(itemHeight)
            btn:SetPoint("TOPLEFT", 4, yOff)
            btn:SetPoint("TOPRIGHT", -4, yOff)
            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            SetFont(btnText, 11, "", C.text)
            btnText:SetText(opt.text)
            btnText:SetPoint("LEFT", 4, 0)
            btn:SetScript("OnClick", function()
                SetValue(opt.value)
                menuFrame:Hide()
            end)
            btn:SetScript("OnEnter", function() btnText:SetTextColor(unpack(C.accent)) end)
            btn:SetScript("OnLeave", function() btnText:SetTextColor(unpack(C.text)) end)
            yOff = yOff - itemHeight
        end

        local totalHeight = math.abs(yOff) + 4
        local maxHeight = (maxVisibleItems * itemHeight) + 8

        -- Update scroll content height
        if scrollContent then
            scrollContent:SetHeight(totalHeight)
        end

        -- Set menu height (capped at maxHeight)
        menuFrame:SetHeight(math.min(totalHeight, maxHeight))
    end

    dropdown:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide()
        else
            BuildMenu()
            menuFrame:Show()
        end
    end)

    local function SetOptions(newOptions)
        container.options = newOptions or {}
        -- Check if current value still exists in new options
        local currentVal = GetValue()
        local found = false
        for _, opt in ipairs(container.options) do
            if opt.value == currentVal then
                dropdown.selected:SetText(opt.text)
                found = true
                break
            end
        end
        if not found then
            dropdown.selected:SetText("")
            container.selectedValue = nil
            if dbTable and dbKey then dbTable[dbKey] = "" end
        end
    end

    container.GetValue = GetValue
    container.SetValue = SetValue
    container.SetOptions = SetOptions
    container.UpdateVisual = UpdateVisual

    -- Register for cross-widget sync
    RegisterWidgetInstance(container, dbTable, dbKey)

    SetValue(GetValue(), true)

    -- Enable/disable the dropdown (for conditional UI)
    container.SetEnabled = function(self, enabled)
        dropdown:EnableMouse(enabled)
        container.isEnabled = enabled
        container:SetAlpha(enabled and 1 or 0.4)
    end
    container.isEnabled = true

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0)
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            table.insert(GUI.SettingsRegistry, {
                label = label,
                widgetType = "dropdown",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormDropdown(p, label, options, dbKey, dbTable, onChange)
                end,
            })
        end
    end

    return container
end

function GUI:CreateFormColorPicker(parent, label, dbKey, dbTable, onChange, options)
    options = options or {}
    local noAlpha = options.noAlpha or false

    if parent._hasContent ~= nil then parent._hasContent = true end
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(FORM_ROW_HEIGHT)

    -- Label on left (off-white text)
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(text, 12, "", C.text)
    text:SetText(label or "Color")
    text:SetPoint("LEFT", 0, 0)

    -- Color swatch aligned with other widgets (starts at 180px from left)
    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(50, 18)
    swatch:SetPoint("LEFT", container, "LEFT", 180, 0)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    container.swatch = swatch
    container.label = text

    local function GetColor()
        if dbTable and dbKey then
            local c = dbTable[dbKey]
            if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        end
        return 1, 1, 1, 1
    end

    local function SetColor(r, g, b, a)
        local finalAlpha = noAlpha and 1 or (a or 1)
        swatch:SetBackdropColor(r, g, b, finalAlpha)
        if dbTable and dbKey then
            dbTable[dbKey] = {r, g, b, finalAlpha}
        end
        if onChange then onChange(r, g, b, finalAlpha) end
    end

    container.GetColor = GetColor
    container.SetColor = SetColor

    local r, g, b, a = GetColor()
    swatch:SetBackdropColor(r, g, b, a)

    swatch:SetScript("OnClick", function()
        local currentR, currentG, currentB, currentA = GetColor()
        local originalA = currentA
        ColorPickerFrame:SetupColorPickerAndShow({
            r = currentR, g = currentG, b = currentB, opacity = currentA,
            hasOpacity = not noAlpha,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = noAlpha and 1 or ColorPickerFrame:GetColorAlpha()
                SetColor(r, g, b, a)
            end,
            cancelFunc = function(prev)
                SetColor(prev.r, prev.g, prev.b, noAlpha and 1 or originalA)
            end,
        })
    end)

    swatch:SetScript("OnEnter", function(self) pcall(self.SetBackdropBorderColor, self, unpack(C.accent)) end)
    swatch:SetScript("OnLeave", function(self) pcall(self.SetBackdropBorderColor, self, 0.4, 0.4, 0.4, 1) end)

    -- Enable/disable (for conditional UI)
    container.SetEnabled = function(self, enabled)
        swatch:EnableMouse(enabled)
        container:SetAlpha(enabled and 1 or 0.4)
    end

    -- Auto-register for search using current context (if context is set)
    if GUI._searchContext.tabIndex and label and not GUI._suppressSearchRegistration then
        local regKey = label .. "_" .. (GUI._searchContext.tabIndex or 0) .. "_" .. (GUI._searchContext.subTabIndex or 0)
        if not GUI.SettingsRegistryKeys[regKey] then
            GUI.SettingsRegistryKeys[regKey] = true
            table.insert(GUI.SettingsRegistry, {
                label = label,
                widgetType = "colorpicker",
                tabIndex = GUI._searchContext.tabIndex,
                tabName = GUI._searchContext.tabName,
                subTabIndex = GUI._searchContext.subTabIndex,
                subTabName = GUI._searchContext.subTabName,
                sectionName = GUI._searchContext.sectionName,
                widgetBuilder = function(p)
                    return GUI:CreateFormColorPicker(p, label, dbKey, dbTable, onChange, options)
                end,
            })
        end
    end

    return container
end

---------------------------------------------------------------------------
-- SEARCH FUNCTIONALITY
---------------------------------------------------------------------------
local SEARCH_DEBOUNCE = 0.15  -- 150ms debounce
local SEARCH_MIN_CHARS = 2    -- Minimum characters before searching
local SEARCH_MAX_RESULTS = 30 -- Cap results to prevent UI overload

-- Search timer reference (for cleanup)
GUI._searchTimer = nil

-- Create the search box widget for the top bar
function GUI:CreateSearchBox(parent)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(160, 20)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(0.08, 0.10, 0.14, 1)
    container:SetBackdropBorderColor(0.25, 0.28, 0.32, 1)

    -- Search icon (magnifying glass character)
    local icon = container:CreateFontString(nil, "OVERLAY")
    SetFont(icon, 11, "", C.textMuted)
    icon:SetText("|TInterface\\Common\\UI-Searchbox-Icon:12:12:0:0|t")
    icon:SetPoint("LEFT", 6, 0)

    -- EditBox for search input
    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("LEFT", 24, 0)
    editBox:SetPoint("RIGHT", container, "RIGHT", -24, 0)
    editBox:SetHeight(16)
    editBox:SetAutoFocus(false)
    editBox:SetFont(GetFontPath(), 11, "")
    editBox:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    editBox:SetMaxLetters(50)

    -- Placeholder text
    local placeholder = editBox:CreateFontString(nil, "OVERLAY")
    SetFont(placeholder, 11, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.6})
    placeholder:SetText("Search settings...")
    placeholder:SetPoint("LEFT", 0, 0)

    -- Clear button (X)
    local clearBtn = CreateFrame("Button", nil, container)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", -4, 0)
    clearBtn:Hide()

    local clearText = clearBtn:CreateFontString(nil, "OVERLAY")
    SetFont(clearText, 12, "", C.textMuted)
    clearText:SetText("x")
    clearText:SetPoint("CENTER", 0, 0)

    clearBtn:SetScript("OnEnter", function()
        clearText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    end)
    clearBtn:SetScript("OnLeave", function()
        clearText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
    end)
    clearBtn:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:ClearFocus()
        -- OnTextChanged handler will trigger result clearing
    end)

    -- Text changed handler with debounce
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end

        local text = self:GetText()

        -- Show/hide placeholder and clear button
        placeholder:SetShown(text == "")
        clearBtn:SetShown(text ~= "")

        -- Cancel pending search timer
        if GUI._searchTimer then
            GUI._searchTimer:Cancel()
            GUI._searchTimer = nil
        end

        -- Debounce search execution (handled by parent via onSearch callback)
        if text:len() >= SEARCH_MIN_CHARS then
            GUI._searchTimer = C_Timer.NewTimer(SEARCH_DEBOUNCE, function()
                if container.onSearch then
                    container.onSearch(text)
                end
            end)
        elseif text == "" then
            if container.onClear then
                container.onClear()
            end
        end
    end)

    -- Focus effects
    editBox:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    end)
    editBox:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(0.25, 0.28, 0.32, 1)
    end)

    -- ESC clears search
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        if container.onClear then
            container.onClear()
        end
    end)

    -- Enter also clears focus (search already happened via debounce)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    container.editBox = editBox
    container.placeholder = placeholder
    container.clearBtn = clearBtn

    return container
end

-- Execute search against the settings registry (returns filtered results)
function GUI:ExecuteSearch(searchTerm)
    if not searchTerm or searchTerm:len() < SEARCH_MIN_CHARS then
        return {}
    end

    local results = {}
    local lowerSearch = searchTerm:lower()

    for _, entry in ipairs(self.SettingsRegistry) do
        local score = 0

        -- Label match (highest priority)
        local lowerLabel = (entry.label or ""):lower()
        if lowerLabel:find(lowerSearch, 1, true) then
            score = 100
            -- Bonus for starts-with match
            if lowerLabel:sub(1, lowerSearch:len()) == lowerSearch then
                score = score + 50
            end
        end

        -- Keyword match (secondary)
        if score == 0 and entry.keywords then
            for _, keyword in ipairs(entry.keywords) do
                if keyword:lower():find(lowerSearch, 1, true) then
                    score = 50
                    break
                end
            end
        end

        -- Section name matching removed - causes too many false positives

        if score > 0 then
            table.insert(results, {data = entry, score = score})
        end
    end

    -- Sort by score (highest first), then alphabetically
    table.sort(results, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return (a.data.label or "") < (b.data.label or "")
    end)

    -- Limit results
    if #results > SEARCH_MAX_RESULTS then
        for i = SEARCH_MAX_RESULTS + 1, #results do
            results[i] = nil
        end
    end

    return results
end

-- Render search results into a content frame (for Search tab)
function GUI:RenderSearchResults(content, results, searchTerm)
    if not content then return end

    -- Clear previous child frames (unregister from widget sync first)
    for _, child in ipairs({content:GetChildren()}) do
        UnregisterWidgetInstance(child)
        child:Hide()
        child:SetParent(nil)
    end

    -- Clear previous font strings
    if content._fontStrings then
        for _, fs in ipairs(content._fontStrings) do
            fs:Hide()
            fs:SetText("")
        end
    end
    content._fontStrings = {}

    -- Clear previous textures
    if content._textures then
        for _, tex in ipairs(content._textures) do
            tex:Hide()
        end
    end
    content._textures = {}

    local y = -10
    local PADDING = 15
    local FORM_ROW = 32

    -- No results message
    if not results or #results == 0 then
        if searchTerm and searchTerm ~= "" then
            local noResults = content:CreateFontString(nil, "OVERLAY")
            SetFont(noResults, 12, "", C.textMuted)
            noResults:SetText("No settings found for \"" .. searchTerm .. "\"")
            noResults:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, noResults)
            y = y - 30

            local tip = content:CreateFontString(nil, "OVERLAY")
            SetFont(tip, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7})
            tip:SetText("Try different keywords, or visit other tabs first to index their settings")
            tip:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, tip)
            y = y - 30
        else
            -- Empty state - show instructions
            local instructions = content:CreateFontString(nil, "OVERLAY")
            SetFont(instructions, 12, "", C.textMuted)
            instructions:SetText("Type at least 2 characters to search settings")
            instructions:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, instructions)
            y = y - 30

            local tip2 = content:CreateFontString(nil, "OVERLAY")
            SetFont(tip2, 10, "", {C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7})
            tip2:SetText("Settings are indexed when you visit each tab")
            tip2:SetPoint("TOPLEFT", PADDING, y)
            table.insert(content._fontStrings, tip2)
            y = y - 20
        end

        content:SetHeight(math.abs(y) + 20)
        return
    end

    -- Build composite group key from available metadata
    local function GetGroupKey(entry)
        local parts = {entry.tabName or "Other"}
        if entry.subTabName and entry.subTabName ~= "" then
            table.insert(parts, entry.subTabName)
        end
        if entry.sectionName and entry.sectionName ~= "" then
            table.insert(parts, entry.sectionName)
        end
        return table.concat(parts, " > ")
    end

    -- Group results by composite key
    local groupedResults = {}
    local tabOrder = {}

    for _, result in ipairs(results) do
        local groupKey = GetGroupKey(result.data)
        if not groupedResults[groupKey] then
            groupedResults[groupKey] = {entries = {}, data = result.data}
            table.insert(tabOrder, groupKey)
        end
        table.insert(groupedResults[groupKey].entries, result)
    end

    -- Suppress auto-registration while creating search result widgets
    GUI._suppressSearchRegistration = true

    -- Render grouped results with actual widgets
    for _, groupKey in ipairs(tabOrder) do
        local group = groupedResults[groupKey]
        local groupData = group.data

        -- Group header
        local header = content:CreateFontString(nil, "OVERLAY")
        SetFont(header, 12, "", C.accentLight)
        header:SetText(groupKey)
        header:SetPoint("TOPLEFT", PADDING, y)
        table.insert(content._fontStrings, header)

        -- "Go >" navigation button
        if groupData.tabIndex then
            local goBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
            goBtn:SetSize(36, 16)
            goBtn:SetPoint("LEFT", header, "RIGHT", 8, 0)
            goBtn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 1,
            })
            goBtn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
            goBtn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)

            local btnText = goBtn:CreateFontString(nil, "OVERLAY")
            SetFont(btnText, 9, "", C.accent)
            btnText:SetText("Go >")
            btnText:SetPoint("CENTER", 0, 0)

            goBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.3)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
            end)
            goBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
            end)

            local targetTabIndex = groupData.tabIndex
            local targetSubTabIndex = groupData.subTabIndex
            local targetSectionName = groupData.sectionName
            goBtn:SetScript("OnClick", function()
                local frame = GUI.MainFrame
                if not frame then return end
                GUI:SelectTab(frame, targetTabIndex)

                -- Recursive helper to find subtab container at any depth
                local function FindSubTabContainer(parentFrame, depth)
                    if depth > 5 then return nil end  -- Prevent infinite recursion

                    -- Check if this frame is a subtab container
                    if parentFrame.SelectTab and parentFrame.tabButtons then
                        return parentFrame
                    end

                    -- Check scroll child if this is a scroll frame
                    if parentFrame.GetScrollChild then
                        local scrollChild = parentFrame:GetScrollChild()
                        if scrollChild then
                            local found = FindSubTabContainer(scrollChild, depth + 1)
                            if found then return found end
                        end
                    end

                    -- Check regular children
                    if parentFrame.GetChildren then
                        for _, child in ipairs({parentFrame:GetChildren()}) do
                            local found = FindSubTabContainer(child, depth + 1)
                            if found then return found end
                        end
                    end

                    return nil
                end

                -- Helper to scroll to a section
                local function ScrollToSection()
                    local subTabIdx = targetSubTabIndex or 0
                    local regKey = targetTabIndex .. "_" .. subTabIdx .. "_" .. (targetSectionName or "")
                    local sectionInfo = GUI.SectionRegistry[regKey]

                    if sectionInfo and sectionInfo.scrollParent and sectionInfo.frame then
                        local scrollFrame = sectionInfo.scrollParent
                        local sectionFrame = sectionInfo.frame
                        local contentParent = sectionInfo.contentParent

                        -- Calculate the section's position relative to the scroll content
                        if contentParent and sectionFrame:IsVisible() then
                            local sectionTop = sectionFrame:GetTop()
                            local contentTop = contentParent:GetTop()

                            if sectionTop and contentTop then
                                -- Get section's offset from top of content
                                local sectionOffset = contentTop - sectionTop
                                -- Add some padding above the section (20px)
                                local scrollPos = math.max(0, sectionOffset - 20)
                                -- Clamp to valid scroll range
                                local maxScroll = scrollFrame:GetVerticalScrollRange() or 0
                                scrollPos = math.min(scrollPos, maxScroll)
                                scrollFrame:SetVerticalScroll(scrollPos)
                            end
                        end
                    end
                end

                -- Navigate to subtab if specified, then scroll to section
                if targetSubTabIndex then
                    C_Timer.After(0, function()
                        local page = frame.pages and frame.pages[targetTabIndex]
                        if page and page.frame then
                            local subTabContainer = FindSubTabContainer(page.frame, 0)
                            if subTabContainer then
                                subTabContainer.SelectTab(targetSubTabIndex)  -- Use dot, not colon - SelectTab expects index as first arg
                            end
                        end
                        -- Scroll to section after subtab selection (with small delay for layout)
                        if targetSectionName then
                            C_Timer.After(0.05, ScrollToSection)
                        end
                    end)
                elseif targetSectionName then
                    -- No subtab, just scroll to section
                    C_Timer.After(0.05, ScrollToSection)
                end
            end)
        end

        y = y - 24

        -- Separator line under header
        local sep = content:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("TOPLEFT", PADDING, y + 2)
        sep:SetSize(content:GetWidth() - (PADDING * 2), 1)
        sep:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
        table.insert(content._textures, sep)
        y = y - 12

        -- Results in this group - create actual widgets
        for _, result in ipairs(group.entries) do
            local entry = result.data

            if entry.widgetBuilder then
                local widget = entry.widgetBuilder(content)
                if widget then
                    widget:SetPoint("TOPLEFT", PADDING, y)
                    widget:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
                    y = y - FORM_ROW
                end
            else
                -- Fallback: show label if no builder
                local fallbackLabel = content:CreateFontString(nil, "OVERLAY")
                SetFont(fallbackLabel, 11, "", C.textMuted)
                fallbackLabel:SetText(entry.label or "Unknown setting")
                fallbackLabel:SetPoint("TOPLEFT", PADDING, y)
                table.insert(content._fontStrings, fallbackLabel)
                y = y - 24
            end
        end

        y = y - 10  -- Gap between groups
    end

    -- Re-enable auto-registration
    GUI._suppressSearchRegistration = false

    content:SetHeight(math.abs(y) + 20)
end

-- Clear search results display
function GUI:ClearSearchInTab(content)
    self:RenderSearchResults(content, nil, nil)
end

---------------------------------------------------------------------------
-- MAIN OPTIONS FRAME
---------------------------------------------------------------------------
function GUI:CreateMainFrame()
    if self.MainFrame then
        return self.MainFrame
    end
    
    local FRAME_WIDTH = GUI.PANEL_WIDTH
    local FRAME_HEIGHT = 850
    local TAB_BUTTON_HEIGHT = 22
    local TAB_START_X = 10   -- Start tabs from the left edge
    local TAB_SPACING = 2
    local TABS_PER_ROW = 5   -- 5 tabs per row (for 4 rows = 20 tabs max)
    local PADDING = 20       -- Left + right padding (10 each side)

    -- Load saved width first (so tab width calculation uses actual panel width)
    local savedWidth = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile.configPanelWidth or FRAME_WIDTH

    -- Calculate button width to fit exactly in frame (use savedWidth, not default)
    local availableWidth = savedWidth - PADDING - (TAB_SPACING * (TABS_PER_ROW - 1))
    local TAB_BUTTON_WIDTH = math.floor(availableWidth / TABS_PER_ROW)
    local frame = CreateFrame("Frame", "QUI_Options", UIParent, "BackdropTemplate")
    frame:SetSize(savedWidth, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)  -- Keep panel responsive when clicking elsewhere
    frame:EnableMouse(true)  -- Block mouse events from passing through to frames behind
    CreateBackdrop(frame, C.bg, C.border)

    -- Apply saved panel alpha
    local savedAlpha = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile.configPanelAlpha or 0.97
    frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], savedAlpha)

    self.MainFrame = frame

    -- Handle resize events (relayout tabs when width changes)
    frame:SetScript("OnSizeChanged", function(self, width, height)
        GUI:RelayoutTabs(self)
    end)

    -- Note: Registry is NOT cleared on show - deduplication keys prevent duplicates
    -- when tabs are re-clicked. Registry persists to allow searching across all visited tabs.

    -- Title bar area (draggable)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(50)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Title bar with title on left, version/close on right (single line)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(title, 14, "OUTLINE", C.accentLight)  -- Lighter mint for title
    title:SetText("QUI")
    title:SetPoint("TOPLEFT", 12, -10)
    
    -- Version text (mint green, to the left of close button)
    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(version, 11, "", C.accentLight)  -- Same mint as title
    version:SetText("Version 2.00")
    version:SetPoint("TOPRIGHT", -30, -10)

    -- Panel Scale (compact inline: label + editbox + slider)
    -- Uses OnMouseUp pattern to avoid jittery scaling during drag
    local scaleContainer = CreateFrame("Frame", nil, frame)
    scaleContainer:SetSize(160, 20)
    scaleContainer:SetPoint("CENTER", frame, "TOP", 0, -15)

    local scaleLabel = scaleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(scaleLabel, 10, "", C.textMuted)
    scaleLabel:SetText("Panel Scale:")
    scaleLabel:SetPoint("LEFT", scaleContainer, "LEFT", 0, 0)

    -- Editable input field for manual entry
    local scaleEditBox = CreateFrame("EditBox", nil, scaleContainer, "BackdropTemplate")
    scaleEditBox:SetSize(38, 16)
    scaleEditBox:SetPoint("LEFT", scaleLabel, "RIGHT", 5, 0)
    scaleEditBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scaleEditBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
    scaleEditBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    scaleEditBox:SetFont(GetFontPath(), 10, "")
    scaleEditBox:SetTextColor(unpack(C.text))
    scaleEditBox:SetJustifyH("CENTER")
    scaleEditBox:SetAutoFocus(false)
    scaleEditBox:SetMaxLetters(4)

    local scaleSlider = CreateFrame("Slider", nil, scaleContainer, "BackdropTemplate")
    scaleSlider:SetSize(70, 12)
    scaleSlider:SetPoint("LEFT", scaleEditBox, "RIGHT", 5, 0)
    scaleSlider:SetOrientation("HORIZONTAL")
    scaleSlider:SetMinMaxValues(0.8, 1.5)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:EnableMouse(true)
    scaleSlider:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    scaleSlider:SetBackdropColor(0.22, 0.22, 0.22, 0.9)
    local thumb = scaleSlider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 14)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    scaleSlider:SetThumbTexture(thumb)

    -- Helper to apply scale (used on release and manual entry)
    local function ApplyScale(value)
        value = math.max(0.8, math.min(1.5, value))
        value = math.floor(value * 20 + 0.5) / 20  -- Round to 0.05
        frame:SetScale(value)
        if QUI.QUICore and QUI.QUICore.db then
            QUI.QUICore.db.profile.configPanelScale = value
        end
        return value
    end

    -- Initialize scale from saved value
    local savedScale = QUI.QUICore and QUI.QUICore.db and QUI.QUICore.db.profile.configPanelScale or 1.0
    scaleSlider:SetValue(savedScale)
    scaleEditBox:SetText(string.format("%.2f", savedScale))
    frame:SetScale(savedScale)

    -- Track if we're dragging to defer SetScale until release
    local isDragging = false

    -- OnValueChanged: Update editbox text only, defer SetScale during drag
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20  -- Round to 0.05
        scaleEditBox:SetText(string.format("%.2f", value))
        -- Only apply immediately if NOT dragging (e.g., clicking on track)
        if not isDragging then
            ApplyScale(value)
        end
    end)

    -- OnMouseDown: Start tracking drag
    scaleSlider:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
        end
    end)

    -- OnMouseUp: Apply scale smoothly when user releases
    scaleSlider:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and isDragging then
            isDragging = false
            local value = self:GetValue()
            ApplyScale(value)
        end
    end)

    -- EditBox: Manual entry support
    scaleEditBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = ApplyScale(val)
            scaleSlider:SetValue(val)
            self:SetText(string.format("%.2f", val))
        end
        self:ClearFocus()
    end)

    scaleEditBox:SetScript("OnEscapePressed", function(self)
        self:SetText(string.format("%.2f", scaleSlider:GetValue()))
        self:ClearFocus()
    end)

    -- Hover effect for editbox
    scaleEditBox:SetScript("OnEditFocusGained", function(self)
        pcall(self.SetBackdropBorderColor, self, unpack(C.accent))
    end)

    scaleEditBox:SetScript("OnEditFocusLost", function(self)
        pcall(self.SetBackdropBorderColor, self, 0.25, 0.25, 0.25, 1)
        -- Validate and revert if invalid
        local val = tonumber(self:GetText())
        if not val then
            self:SetText(string.format("%.2f", scaleSlider:GetValue()))
        end
    end)

    -- Close button (X)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() frame:Hide() end)
    
    -- Separator line below title
    local titleSep = frame:CreateTexture(nil, "ARTWORK")
    titleSep:SetPoint("TOPLEFT", 10, -30)
    titleSep:SetPoint("TOPRIGHT", -10, -30)
    titleSep:SetHeight(1)
    titleSep:SetColorTexture(unpack(C.border))
    
    -- Tab button container (starts right below title line)
    local tabContainer = CreateFrame("Frame", nil, frame)
    tabContainer:SetPoint("TOPLEFT", TAB_START_X, -35)
    tabContainer:SetPoint("TOPRIGHT", -10, -35)
    tabContainer:SetHeight(100)  -- Height for 4 rows of tabs (22px each + spacing)
    frame.tabContainer = tabContainer
    
    -- Content area (below tabs) - starts after 4 rows of tabs
    local contentArea = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentArea:SetPoint("TOPLEFT", 10, -140)  -- 35 (title) + 100 (tabs) + 5 (gap)
    contentArea:SetPoint("BOTTOMRIGHT", -10, 10)
    contentArea:EnableMouse(false)  -- Container frame - let children handle clicks

    -- Content background (Dark Slate with transparency)
    local contentBg = contentArea:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints()
    contentBg:SetColorTexture(unpack(C.bgContent))
    
    -- Top line above content (subtle mint hint)
    local topLine = contentArea:CreateTexture(nil, "ARTWORK")
    topLine:SetPoint("BOTTOMLEFT", contentArea, "TOPLEFT", 0, 0)
    topLine:SetPoint("BOTTOMRIGHT", contentArea, "TOPRIGHT", 0, 0)
    topLine:SetHeight(1)
    topLine:SetColorTexture(unpack(C.border))
    
    frame.contentArea = contentArea
    
    -- Store tabs and pages
    frame.tabs = {}
    frame.pages = {}
    frame.activeTab = nil
    frame.TAB_BUTTON_WIDTH = TAB_BUTTON_WIDTH
    frame.TAB_BUTTON_HEIGHT = TAB_BUTTON_HEIGHT
    frame.TAB_SPACING = TAB_SPACING
    frame.TABS_PER_ROW = TABS_PER_ROW
    
    ---------------------------------------------------------------------------
    -- RESIZE HANDLE (Bottom-right corner, horizontal and vertical)
    ---------------------------------------------------------------------------
    local MIN_HEIGHT = 400
    local MAX_HEIGHT = 1200
    local MIN_WIDTH = 600
    local MAX_WIDTH = 1000
    
    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(20, 20)
    resizeHandle:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 10)
    
    -- Diagonal grip texture
    local gripTexture = resizeHandle:CreateTexture(nil, "OVERLAY")
    gripTexture:SetAllPoints()
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTexture:SetVertexColor(0.6, 0.8, 0.7, 0.8)  -- Subtle mint tint

    -- Highlight texture on hover
    local gripHighlight = resizeHandle:CreateTexture(nil, "HIGHLIGHT")
    gripHighlight:SetAllPoints()
    gripHighlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    gripHighlight:SetVertexColor(0.2, 0.82, 0.6, 1)  -- Mint highlight

    -- Pushed texture when dragging
    local gripPushed = resizeHandle:CreateTexture(nil, "ARTWORK")
    gripPushed:SetAllPoints()
    gripPushed:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    gripPushed:SetVertexColor(0.2, 0.82, 0.6, 1)
    gripPushed:Hide()
    
    resizeHandle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            gripPushed:Show()
            gripTexture:Hide()

            -- Re-anchor to TOPLEFT so resizing only moves right/bottom edges
            local left = frame:GetLeft()
            local top = frame:GetTop()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

            -- Store initial values for both axes
            local cursorX, cursorY = GetCursorPosition()
            local scale = frame:GetEffectiveScale()
            self.startX = cursorX / scale
            self.startY = cursorY / scale
            self.startWidth = frame:GetWidth()
            self.startHeight = frame:GetHeight()
            self.isResizing = true

            -- Start resizing (both horizontal and vertical)
            self._resizeElapsed = 0
            self:SetScript("OnUpdate", function(self, elapsed)
                if not self.isResizing then return end
                self._resizeElapsed = (self._resizeElapsed or 0) + elapsed
                if self._resizeElapsed < 0.016 then return end -- ~60 FPS cap
                self._resizeElapsed = 0

                local cursorX, cursorY = GetCursorPosition()
                local scale = frame:GetEffectiveScale()
                local currentX = cursorX / scale
                local currentY = cursorY / scale

                -- Calculate deltas
                local deltaX = currentX - self.startX  -- Drag right = increase width
                local deltaY = self.startY - currentY  -- Inverted: drag down = increase height

                -- Apply clamped values
                local newWidth = math.max(MIN_WIDTH, math.min(MAX_WIDTH, self.startWidth + deltaX))
                local newHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, self.startHeight + deltaY))

                frame:SetSize(newWidth, newHeight)
            end)
        end
    end)
    
    resizeHandle:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            gripPushed:Hide()
            gripTexture:Show()
            self.isResizing = false
            self:SetScript("OnUpdate", nil)

            -- Save dimensions to DB
            if QUI.QUICore and QUI.QUICore.db then
                QUI.QUICore.db.profile.configPanelWidth = frame:GetWidth()
            end
        end
    end)

    -- Tooltip on hover
    resizeHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)

    resizeHandle:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    frame.resizeHandle = resizeHandle

    ---------------------------------------------------------------------------
    -- TAB RELAYOUT (called on resize to adjust tab widths)
    ---------------------------------------------------------------------------
    function GUI:RelayoutTabs(targetFrame)
        if not targetFrame.tabs or #targetFrame.tabs == 0 then return end

        local PADDING = 20
        local TAB_SPACING = targetFrame.TAB_SPACING
        local TABS_PER_ROW = targetFrame.TABS_PER_ROW
        local TAB_BUTTON_HEIGHT = targetFrame.TAB_BUTTON_HEIGHT

        local availableWidth = targetFrame:GetWidth() - PADDING - (TAB_SPACING * (TABS_PER_ROW - 1))
        local tabWidth = math.floor(availableWidth / TABS_PER_ROW)

        for i, tab in ipairs(targetFrame.tabs) do
            local row = math.floor((i - 1) / TABS_PER_ROW)
            local col = (i - 1) % TABS_PER_ROW
            local x = col * (tabWidth + TAB_SPACING)
            local y = -row * (TAB_BUTTON_HEIGHT + TAB_SPACING) - 5

            tab:SetWidth(tabWidth)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", targetFrame.tabContainer, "TOPLEFT", x, y)
        end

        targetFrame.TAB_BUTTON_WIDTH = tabWidth
    end

    return frame
end

---------------------------------------------------------------------------
-- ADD TAB (Clean style - no left bar, mint text when active)
---------------------------------------------------------------------------
function GUI:AddTab(frame, name, pageCreateFunc)
    local index = #frame.tabs + 1
    
    local row = math.floor((index - 1) / frame.TABS_PER_ROW)
    local col = (index - 1) % frame.TABS_PER_ROW
    
    local x = col * (frame.TAB_BUTTON_WIDTH + frame.TAB_SPACING)
    local y = -row * (frame.TAB_BUTTON_HEIGHT + frame.TAB_SPACING) - 5  -- Small top padding
    
    -- Create tab button
    local tab = CreateFrame("Button", nil, frame.tabContainer, "BackdropTemplate")
    tab:SetSize(frame.TAB_BUTTON_WIDTH, frame.TAB_BUTTON_HEIGHT)
    tab:SetPoint("TOPLEFT", frame.tabContainer, "TOPLEFT", x, y)
    tab:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    tab:SetBackdropColor(unpack(C.bgLight))  -- Dark Slate inactive
    tab:SetBackdropBorderColor(unpack(C.border))
    tab.index = index
    tab.name = name
    
    -- Tab text - centered
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(tab.text, 11, "", C.tabNormal)
    tab.text:SetText(name)
    tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab.text:SetJustifyH("CENTER")
    
    frame.tabs[index] = tab
    frame.pages[index] = {
        createFunc = pageCreateFunc,
        frame = nil
    }
    
    -- Click handler
    tab:SetScript("OnClick", function()
        GUI:SelectTab(frame, index)
    end)
    
    tab:SetScript("OnEnter", function(self)
        if frame.activeTab ~= self.index then
            self.text:SetTextColor(unpack(C.tabHover))
            pcall(self.SetBackdropBorderColor, self, unpack(C.borderLight))
        end
    end)
    
    tab:SetScript("OnLeave", function(self)
        if frame.activeTab ~= self.index then
            self.text:SetTextColor(unpack(C.tabNormal))
            pcall(self.SetBackdropBorderColor, self, unpack(C.border))
        end
    end)
    
    -- Select first tab by default
    if index == 1 then
        GUI:SelectTab(frame, 1)
    end
    
    return tab
end

---------------------------------------------------------------------------
-- ADD ACTION BUTTON (Special button that executes action instead of opening page)
-- Styled like "CREATE" button - dark bg with thick mint border, centered text
---------------------------------------------------------------------------
function GUI:AddActionButton(frame, name, onClick, accentColor)
    local index = #frame.tabs + 1
    
    local row = math.floor((index - 1) / frame.TABS_PER_ROW)
    local col = (index - 1) % frame.TABS_PER_ROW
    
    local x = col * (frame.TAB_BUTTON_WIDTH + frame.TAB_SPACING)
    local y = -row * (frame.TAB_BUTTON_HEIGHT + frame.TAB_SPACING) - 5
    
    -- Create action button (styled like CREATE button)
    local btn = CreateFrame("Button", nil, frame.tabContainer, "BackdropTemplate")
    btn:SetSize(frame.TAB_BUTTON_WIDTH, frame.TAB_BUTTON_HEIGHT)
    btn:SetPoint("TOPLEFT", frame.tabContainer, "TOPLEFT", x, y)
    
    -- Dark background with thick mint border (like CREATE button)
    local bgColor = {0.05, 0.08, 0.12, 1}  -- Very dark
    local borderColor = {0.2, 0.82, 0.6, 1}  -- Mint/teal accent
    
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,  -- Thicker border
    })
    btn:SetBackdropColor(unpack(bgColor))
    btn:SetBackdropBorderColor(unpack(borderColor))
    btn.index = index
    btn.name = name
    btn.isActionButton = true
    btn.bgColor = bgColor
    btn.borderColor = borderColor
    
    -- Button text - CENTERED, mint colored
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    SetFont(btn.text, 11, "", borderColor)  -- Mint text color
    btn.text:SetText(name)
    btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.text:SetJustifyH("CENTER")
    
    -- Store in tabs array but mark as action button
    frame.tabs[index] = btn
    frame.pages[index] = nil  -- No page for action buttons
    
    -- Click handler - execute action
    btn:SetScript("OnClick", function()
        if onClick then
            onClick()
        end
    end)
    
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.1, 0.15, 0.2, 1)  -- Slightly lighter on hover
        self:SetBackdropBorderColor(0.4, 1, 0.8, 1)  -- Brighter mint on hover
        self.text:SetTextColor(0.4, 1, 0.8, 1)  -- Brighter text
    end)
    
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(self.bgColor))
        self:SetBackdropBorderColor(unpack(self.borderColor))
        self.text:SetTextColor(unpack(self.borderColor))
    end)
    
    return btn
end

---------------------------------------------------------------------------
-- SELECT TAB
---------------------------------------------------------------------------
function GUI:SelectTab(frame, index)
    -- Skip if this is an action button (no page to show)
    local targetTab = frame.tabs[index]
    if targetTab and targetTab.isActionButton then
        return
    end

    -- Force-load all tabs when Search tab is selected
    -- Only if all tabs have been added (avoid running during initial setup)
    if index == self._searchTabIndex and self._allTabsAdded and not self._searchIndexBuilt then
        self:ForceLoadAllTabs()
        self._searchIndexBuilt = true
    end

    -- Clear search if active
    if frame._searchActive then
        if frame.searchBox and frame.searchBox.editBox then
            frame.searchBox.editBox:SetText("")
        end
        self:ClearSearchResults()
    end

    -- Deselect previous
    if frame.activeTab then
        local prevTab = frame.tabs[frame.activeTab]
        if prevTab and not prevTab.isActionButton then
            prevTab.text:SetTextColor(unpack(C.tabNormal))  -- Normal grey text
            pcall(prevTab.SetBackdropColor, prevTab, unpack(C.bgLight))
            pcall(prevTab.SetBackdropBorderColor, prevTab, unpack(C.border))
        end
        
        if frame.pages[frame.activeTab] and frame.pages[frame.activeTab].frame then
            frame.pages[frame.activeTab].frame:Hide()
        end
    end
    
    -- Select new
    frame.activeTab = index
    local tab = frame.tabs[index]
    if tab and not tab.isActionButton then
        tab.text:SetTextColor(unpack(C.accent))  -- Mint text when active
        pcall(tab.SetBackdropColor, tab, unpack(C.bgLight))
        pcall(tab.SetBackdropBorderColor, tab, unpack(C.accent))  -- Mint border
    end
    
    -- Create/show page
    local page = frame.pages[index]
    if page then
        if not page.frame then
            page.frame = CreateFrame("Frame", nil, frame.contentArea)
            page.frame:SetAllPoints()
            page.frame:EnableMouse(false)  -- Container frame - let children handle clicks
            if page.createFunc then
                page.createFunc(page.frame)
                page.built = true  -- Prevent duplicate widget creation
            end
        end
        page.frame:Show()
        
        -- Force OnShow scripts to fire on all children (for refresh purposes)
        -- This ensures dynamic content like profile dropdowns update
        local function TriggerOnShow(frame)
            if frame.GetScript and frame:GetScript("OnShow") then
                frame:GetScript("OnShow")(frame)
            end
            if frame.GetChildren then
                for _, child in ipairs({frame:GetChildren()}) do
                    TriggerOnShow(child)
                end
            end
        end
        TriggerOnShow(page.frame)
    end
end

---------------------------------------------------------------------------
-- SHOW FUNCTION
---------------------------------------------------------------------------
function GUI:Show()
    if not self.MainFrame then
        self:InitializeOptions()
    end
    self.MainFrame:Show()
end

---------------------------------------------------------------------------
-- HIDE FUNCTION
---------------------------------------------------------------------------
function GUI:Hide()
    if self.MainFrame then
        self.MainFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- TOGGLE FUNCTION
---------------------------------------------------------------------------
function GUI:Toggle()
    if self.MainFrame and self.MainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Store reference
QUI.GUI = GUI
