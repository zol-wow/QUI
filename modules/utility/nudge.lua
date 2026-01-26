local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)

-- Extra nudge targets: Blizzard Edit Mode unit frame anchors
-- These are the invisible movers that our reskinned unit frames use.
local UNIT_ANCHOR_FRAMES = {
    PlayerFrame = "Player",
    TargetFrame = "Target",
    FocusFrame  = "Focus",
    PetFrame    = "Pet",
}

-- Blizzard Edit Mode frame names lookup (defined early for IsNudgeTargetFrameName)
local BLIZZARD_FRAME_LABELS = {
    BuffFrame = "Buff Frame",
    DebuffFrame = "Debuff Frame",
    DamageMeterSessionWindow1 = "Damage Meter",
    BuffBarCooldownViewer = "Tracked Bars",
}

local function IsNudgeTargetFrameName(frameName)
    if not frameName then return false end

    -- Our cooldown viewers
    if QUICore.viewers then
        for _, viewerName in ipairs(QUICore.viewers) do
            if frameName == viewerName then
                return true
            end
        end
    end

    -- Blizzard unit-frame anchors
    if UNIT_ANCHOR_FRAMES[frameName] then
        return true
    end

    -- Blizzard Edit Mode frames
    if BLIZZARD_FRAME_LABELS[frameName] then
        return true
    end

    return false
end

local function GetNudgeDisplayName(frameName)
    if not frameName then
        return ""
    end

    -- Friendly names for unit-frame anchors
    local unitLabel = UNIT_ANCHOR_FRAMES[frameName]
    if unitLabel then
        return unitLabel
    end

    -- Friendly names for Blizzard Edit Mode frames
    local blizzLabel = BLIZZARD_FRAME_LABELS[frameName]
    if blizzLabel then
        return blizzLabel
    end

    -- Fallback: prettify viewer names
    return frameName
        :gsub("CooldownViewer", "")
        :gsub("Icon", " Icon")
end

-- Nudge Frame for Viewer / Anchor Positioning
-- LAZY LOADED: Frame is only created when Edit Mode is first entered

local NudgeFrame = nil  -- Created on first use

-- Create the NudgeFrame UI on first use (saves CPU on /reload)
local function CreateNudgeUI()
    if NudgeFrame then return NudgeFrame end

    NudgeFrame = CreateFrame("Frame", ADDON_NAME .. "NudgeFrame", UIParent, "BackdropTemplate")
    QUICore.nudgeFrame = NudgeFrame

    -- Frame properties
    NudgeFrame:SetSize(200, 320)
    NudgeFrame:SetFrameStrata("DIALOG")
    NudgeFrame:SetClampedToScreen(true)
    NudgeFrame:EnableMouse(true)
    NudgeFrame:SetMovable(false)
    NudgeFrame:Hide()

    -- Backdrop
    NudgeFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })

    -- Position docked to Edit Mode frame
    function NudgeFrame:UpdatePosition()
        if EditModeManagerFrame then
            self:ClearAllPoints()
            self:SetPoint("RIGHT", EditModeManagerFrame, "LEFT", -5, 0)
        end
    end

    -- Title text
    local title = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Viewer Position")

    -- Info text showing current selection
    local infoText = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOP", title, "BOTTOM", 0, -8)
    infoText:SetWidth(180)
    infoText:SetWordWrap(true)
    NudgeFrame.infoText = infoText

    -- Position display
    local posText = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    posText:SetPoint("TOP", infoText, "BOTTOM", 0, -8)
    posText:SetWidth(180)
    posText:SetJustifyH("CENTER")
    NudgeFrame.posText = posText

    -- Helper function to create arrow buttons
    local function CreateArrowButton(parent, direction, x, yFromTop)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(32, 32)
        button:SetPoint("TOP", parent, "TOP", x, yFromTop)

        -- Button background
        button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

        -- Rotate texture based on direction
        local texture = button:GetNormalTexture()
        if direction == "UP" then
            texture:SetRotation(math.rad(90))
            button:GetPushedTexture():SetRotation(math.rad(90))
        elseif direction == "DOWN" then
            texture:SetRotation(math.rad(270))
            button:GetPushedTexture():SetRotation(math.rad(270))
        elseif direction == "LEFT" then
            texture:SetRotation(math.rad(180))
            button:GetPushedTexture():SetRotation(math.rad(180))
        elseif direction == "RIGHT" then
            texture:SetRotation(math.rad(0))
            button:GetPushedTexture():SetRotation(math.rad(0))
        end

        button:SetScript("OnClick", function()
            QUICore:NudgeSelectedViewer(direction)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)

        -- Tooltip
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Nudge " .. direction:lower())
            GameTooltip:AddLine("Move selected viewer 1 pixel " .. direction:lower(), 1, 1, 1)
            GameTooltip:Show()
        end)

        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return button
    end

    -- Create directional buttons
    NudgeFrame.upButton = CreateArrowButton(NudgeFrame, "UP", 0, -90)
    NudgeFrame.downButton = CreateArrowButton(NudgeFrame, "DOWN", 0, -150)
    NudgeFrame.leftButton = CreateArrowButton(NudgeFrame, "LEFT", -25, -120)
    NudgeFrame.rightButton = CreateArrowButton(NudgeFrame, "RIGHT", 25, -120)

    -- Close button
    local closeButton = CreateFrame("Button", nil, NudgeFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        NudgeFrame:Hide()
    end)

    -- Nudge amount slider
    local amountSlider = CreateFrame("Slider", nil, NudgeFrame, "OptionsSliderTemplate")
    amountSlider:SetPoint("BOTTOM", 0, 60)
    amountSlider:SetMinMaxValues(0.1, 10)
    amountSlider:SetValueStep(0.1)
    amountSlider:SetObeyStepOnDrag(true)
    amountSlider:SetWidth(150)
    amountSlider:SetHeight(15)
    NudgeFrame.amountSlider = amountSlider

    -- Slider label
    local amountLabel = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    amountLabel:SetPoint("BOTTOM", amountSlider, "TOP", 0, 2)
    amountLabel:SetText("Nudge Amount: 1px")
    NudgeFrame.amountLabel = amountLabel

    -- Slider min/max labels
    amountSlider.Low:SetText("0.1")
    amountSlider.High:SetText("10")

    -- Slider value change handler
    amountSlider:SetScript("OnValueChanged", function(self, value)
        -- Round to 1 decimal place
        value = math.floor(value * 10 + 0.5) / 10
        QUICore.db.profile.nudgeAmount = value
        -- Format to show 1 decimal place for fractional values
        local displayValue = (value % 1 == 0) and tostring(math.floor(value)) or string.format("%.1f", value)
        amountLabel:SetText("Nudge Amount: " .. displayValue .. "px")
    end)

    -- Viewer selector dropdown
    local viewerDropdown = CreateFrame("Frame", ADDON_NAME .. "ViewerDropdown", NudgeFrame, "UIDropDownMenuTemplate")
    viewerDropdown:SetPoint("BOTTOM", 0, 20)
    NudgeFrame.viewerDropdown = viewerDropdown

    -- Dropdown label
    local dropdownLabel = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropdownLabel:SetPoint("BOTTOM", viewerDropdown, "TOP", 0, 0)
    dropdownLabel:SetText("Select Viewer:")

    -- Initialize dropdown
    local function ViewerDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()

        -- Cooldown viewers
        if QUICore.viewers then
            for _, viewerName in ipairs(QUICore.viewers) do
                local displayName = GetNudgeDisplayName(viewerName)

                info.text = displayName
                info.value = viewerName
                info.func = function()
                    QUICore:SelectViewer(viewerName)
                    UIDropDownMenu_SetText(viewerDropdown, displayName)
                    CloseDropDownMenus()
                end
                info.checked = (QUICore.selectedViewer == viewerName)
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- Blizzard unit-frame anchors
        for frameName, label in pairs(UNIT_ANCHOR_FRAMES) do
            local displayName = label

            info.text = displayName
            info.value = frameName
            info.func = function()
                QUICore:SelectViewer(frameName)
                UIDropDownMenu_SetText(viewerDropdown, displayName)
                CloseDropDownMenus()
            end
            info.checked = (QUICore.selectedViewer == frameName)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(viewerDropdown, ViewerDropdown_Initialize)
    UIDropDownMenu_SetWidth(viewerDropdown, 150)
    UIDropDownMenu_SetText(viewerDropdown, "Select...")

    -- Update info display
    function NudgeFrame:UpdateInfo()
        local viewerName = QUICore.selectedViewer
        local viewer = viewerName and _G[viewerName]

        if viewer then
            local displayName = GetNudgeDisplayName(viewerName)
            self.infoText:SetText(displayName)
            self.infoText:SetTextColor(0, 1, 0)

            -- Show position
            local point, relativeTo, relativePoint, xOfs, yOfs = viewer:GetPoint(1)
            if point then
                self.posText:SetFormattedText("Position: %.1f, %.1f", xOfs or 0, yOfs or 0)
                self.posText:SetTextColor(1, 1, 1)
            else
                self.posText:SetText("No position data")
                self.posText:SetTextColor(0.7, 0.7, 0.7)
            end

            -- Enable controls
            self.upButton:Enable()
            self.downButton:Enable()
            self.leftButton:Enable()
            self.rightButton:Enable()
            self.amountSlider:Enable()
        else
            self.infoText:SetText("Click a viewer in Edit Mode")
            self.infoText:SetTextColor(0.7, 0.7, 0.7)
            self.posText:SetText("")

            -- Disable controls
            self.upButton:Disable()
            self.downButton:Disable()
            self.leftButton:Disable()
            self.rightButton:Disable()
            self.amountSlider:Disable()
        end
    end

    -- Update amount slider
    function NudgeFrame:UpdateAmountSlider()
        local amount = QUICore.db.profile.nudgeAmount or 1
        self.amountSlider:SetValue(amount)
        -- Format to show 1 decimal place for fractional values
        local displayAmount = (amount % 1 == 0) and tostring(math.floor(amount)) or string.format("%.1f", amount)
        self.amountLabel:SetText("Nudge Amount: " .. displayAmount .. "px")
    end

    -- Update visibility
    -- Panel disabled - nudge arrows now appear directly on viewers
    function NudgeFrame:UpdateVisibility()
        self:Hide()
    end

    -- Update on show
    NudgeFrame:SetScript("OnShow", function(self)
        self:UpdatePosition()
        self:UpdateInfo()
        self:UpdateAmountSlider()
    end)

    return NudgeFrame
end  -- End of CreateNudgeUI()

-- Helper to ensure NudgeFrame exists before using it
local function EnsureNudgeFrame()
    if not NudgeFrame then
        CreateNudgeUI()
    end
    return NudgeFrame
end

---------------------------------------------------------------------------
-- CDM VIEWER EDIT MODE OVERLAYS
-- Nudge arrows directly on cooldown viewers during Edit Mode
---------------------------------------------------------------------------

local viewerOverlays = {}

-- All CDM viewers that should get nudge overlays
local CDM_VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

-- Blizzard Edit Mode frames that should get nudge overlays
local BLIZZARD_EDITMODE_FRAMES = {
    { name = "BuffFrame", label = "Buff Frame" },
    { name = "DebuffFrame", label = "Debuff Frame" },
    { name = "DamageMeterSessionWindow1", label = "Damage Meter" },
    { name = "BuffBarCooldownViewer", label = "Tracked Bars" },
}

local blizzardOverlays = {}

-- Create a nudge button with chevron arrows (same style as unit frames)
local function CreateViewerNudgeButton(parent, direction, viewerName)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)

    -- Background - dark grey at 70% for visibility over any game content
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)
    btn.bg = bg

    -- Chevron lines - white for high contrast
    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)

    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    -- Direction-specific angles and positions
    if direction == "DOWN" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, 1)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, 1)
        line2:SetRotation(math.rad(45))
    elseif direction == "UP" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, -1)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, -1)
        line2:SetRotation(math.rad(-45))
    elseif direction == "LEFT" then
        line1:SetPoint("CENTER", btn, "CENTER", 1, -2)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 1, 2)
        line2:SetRotation(math.rad(45))
    elseif direction == "RIGHT" then
        line1:SetPoint("CENTER", btn, "CENTER", -1, -2)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", -1, 2)
        line2:SetRotation(math.rad(-45))
    end

    btn.line1 = line1
    btn.line2 = line2

    -- Hover highlight - yellow
    btn:SetScript("OnEnter", function(self)
        self.line1:SetVertexColor(1, 0.8, 0, 1)
        self.line2:SetVertexColor(1, 0.8, 0, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.line1:SetVertexColor(1, 1, 1, 0.9)
        self.line2:SetVertexColor(1, 1, 1, 0.9)
    end)

    btn:SetScript("OnClick", function()
        -- Select this viewer and nudge it
        QUICore:SelectViewer(viewerName)
        QUICore:NudgeSelectedViewer(direction)
    end)

    return btn
end

-- Minimap overlay storage
local minimapOverlay = nil

-- Create a nudge button specifically for the minimap
local function CreateMinimapNudgeButton(parent, direction)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)

    -- Background - dark grey at 70% for visibility
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)
    btn.bg = bg

    -- Chevron lines - white for high contrast
    local line1 = btn:CreateTexture(nil, "ARTWORK")
    line1:SetColorTexture(1, 1, 1, 0.9)
    line1:SetSize(7, 2)

    local line2 = btn:CreateTexture(nil, "ARTWORK")
    line2:SetColorTexture(1, 1, 1, 0.9)
    line2:SetSize(7, 2)

    -- Direction-specific angles and positions (same as viewer nudge buttons)
    if direction == "DOWN" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, 1)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, 1)
        line2:SetRotation(math.rad(45))
    elseif direction == "UP" then
        line1:SetPoint("CENTER", btn, "CENTER", -2, -1)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", 2, -1)
        line2:SetRotation(math.rad(-45))
    elseif direction == "LEFT" then
        line1:SetPoint("CENTER", btn, "CENTER", 1, -2)
        line1:SetRotation(math.rad(-45))
        line2:SetPoint("CENTER", btn, "CENTER", 1, 2)
        line2:SetRotation(math.rad(45))
    elseif direction == "RIGHT" then
        line1:SetPoint("CENTER", btn, "CENTER", -1, -2)
        line1:SetRotation(math.rad(45))
        line2:SetPoint("CENTER", btn, "CENTER", -1, 2)
        line2:SetRotation(math.rad(-45))
    end

    btn.line1 = line1
    btn.line2 = line2

    -- Hover highlight - yellow
    btn:SetScript("OnEnter", function(self)
        self.line1:SetVertexColor(1, 0.8, 0, 1)
        self.line2:SetVertexColor(1, 0.8, 0, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.line1:SetVertexColor(1, 1, 1, 0.9)
        self.line2:SetVertexColor(1, 1, 1, 0.9)
    end)

    -- Click handler - nudge minimap position
    btn:SetScript("OnClick", function()
        QUICore:SelectEditModeElement("minimap", "minimap")
        QUICore:NudgeMinimap(direction)
    end)

    return btn
end

-- Create overlay for a single CDM viewer
local function CreateViewerOverlay(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return nil end

    local overlay = CreateFrame("Frame", nil, viewer, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
    overlay:EnableMouse(false)  -- Don't block clicks to the viewer itself

    -- Label showing viewer name
    local displayName = GetNudgeDisplayName(viewerName)
    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", overlay, "TOP", 0, -4)
    label:SetText(displayName)
    label:SetTextColor(0.2, 0.8, 1, 1)

    -- Nudge buttons around the overlay (same positioning as unit frames)
    local nudgeUp = CreateViewerNudgeButton(overlay, "UP", viewerName)
    nudgeUp:SetPoint("BOTTOM", overlay, "TOP", 0, 4)

    local nudgeDown = CreateViewerNudgeButton(overlay, "DOWN", viewerName)
    nudgeDown:SetPoint("TOP", overlay, "BOTTOM", 0, -4)

    local nudgeLeft = CreateViewerNudgeButton(overlay, "LEFT", viewerName)
    nudgeLeft:SetPoint("RIGHT", overlay, "LEFT", -4, 0)

    local nudgeRight = CreateViewerNudgeButton(overlay, "RIGHT", viewerName)
    nudgeRight:SetPoint("LEFT", overlay, "RIGHT", 4, 0)

    overlay.nudgeUp = nudgeUp
    overlay.nudgeDown = nudgeDown
    overlay.nudgeLeft = nudgeLeft
    overlay.nudgeRight = nudgeRight

    -- Store viewerName for selection manager
    overlay.elementKey = viewerName

    -- Hide nudge buttons initially (will show on click/selection)
    nudgeUp:Hide()
    nudgeDown:Hide()
    nudgeLeft:Hide()
    nudgeRight:Hide()

    overlay:Hide()
    return overlay
end

-- Create overlay for a Blizzard Edit Mode frame
local function CreateBlizzardFrameOverlay(frameInfo)
    local frameName = frameInfo.name
    local label = frameInfo.label
    local frame = _G[frameName]
    if not frame then return nil end

    local overlay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
    overlay:EnableMouse(false)

    -- Label showing frame name
    local labelText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOP", overlay, "TOP", 0, -4)
    labelText:SetText(label)
    labelText:SetTextColor(0.2, 0.8, 1, 1)

    -- Nudge buttons around the overlay (same positioning as CDM viewers)
    local nudgeUp = CreateViewerNudgeButton(overlay, "UP", frameName)
    nudgeUp:SetPoint("BOTTOM", overlay, "TOP", 0, 4)

    local nudgeDown = CreateViewerNudgeButton(overlay, "DOWN", frameName)
    nudgeDown:SetPoint("TOP", overlay, "BOTTOM", 0, -4)

    local nudgeLeft = CreateViewerNudgeButton(overlay, "LEFT", frameName)
    nudgeLeft:SetPoint("RIGHT", overlay, "LEFT", -4, 0)

    local nudgeRight = CreateViewerNudgeButton(overlay, "RIGHT", frameName)
    nudgeRight:SetPoint("LEFT", overlay, "RIGHT", 4, 0)

    overlay.nudgeUp = nudgeUp
    overlay.nudgeDown = nudgeDown
    overlay.nudgeLeft = nudgeLeft
    overlay.nudgeRight = nudgeRight

    -- Store frameName for selection manager
    overlay.elementKey = frameName

    -- Hide nudge buttons initially (will show on click/selection)
    nudgeUp:Hide()
    nudgeDown:Hide()
    nudgeLeft:Hide()
    nudgeRight:Hide()

    overlay:Hide()
    return overlay
end

-- Create overlay for the QUI minimap
local function CreateMinimapOverlay()
    if not Minimap then return nil end

    local overlay = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
    overlay:EnableMouse(false)

    -- Label showing "Minimap"
    local labelText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOP", overlay, "TOP", 0, -4)
    labelText:SetText("Minimap")
    labelText:SetTextColor(0.2, 0.8, 1, 1)

    -- Info text showing X/Y position (above UP arrow)
    local infoText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetTextColor(0.7, 0.7, 0.7, 1)
    overlay.infoText = infoText

    -- Nudge buttons around the overlay
    local nudgeUp = CreateMinimapNudgeButton(overlay, "UP")
    nudgeUp:SetPoint("BOTTOM", overlay, "TOP", 0, 4)

    local nudgeDown = CreateMinimapNudgeButton(overlay, "DOWN")
    nudgeDown:SetPoint("TOP", overlay, "BOTTOM", 0, -4)

    local nudgeLeft = CreateMinimapNudgeButton(overlay, "LEFT")
    nudgeLeft:SetPoint("RIGHT", overlay, "LEFT", -4, 0)

    local nudgeRight = CreateMinimapNudgeButton(overlay, "RIGHT")
    nudgeRight:SetPoint("LEFT", overlay, "RIGHT", 4, 0)

    -- Position info text above the UP arrow
    infoText:SetPoint("BOTTOM", nudgeUp, "TOP", 0, 2)

    overlay.nudgeUp = nudgeUp
    overlay.nudgeDown = nudgeDown
    overlay.nudgeLeft = nudgeLeft
    overlay.nudgeRight = nudgeRight

    -- Store element key for selection manager
    overlay.elementKey = "minimap"

    -- Hide nudge buttons initially (will show on click/selection)
    nudgeUp:Hide()
    nudgeDown:Hide()
    nudgeLeft:Hide()
    nudgeRight:Hide()
    infoText:Hide()

    overlay:Hide()
    return overlay
end

-- Show overlays on all CDM viewers
function QUICore:ShowViewerOverlays()
    for _, viewerName in ipairs(CDM_VIEWERS) do
        if not viewerOverlays[viewerName] then
            viewerOverlays[viewerName] = CreateViewerOverlay(viewerName)
        end
        local overlay = viewerOverlays[viewerName]
        if overlay then
            overlay:Show()

            -- Enable mouse on OVERLAY and handle clicks there
            -- (Icons inside viewer intercept clicks to the viewer frame itself)
            overlay:EnableMouse(true)
            overlay:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" then
                    QUICore:SelectViewer(viewerName)
                    -- Start drag on the viewer
                    local viewer = _G[viewerName]
                    if viewer then
                        viewer:SetMovable(true)  -- Enable movable for Blizzard CDM viewers
                        viewer:StartMoving()
                    end
                end
            end)
            overlay:SetScript("OnMouseUp", function(self, button)
                local viewer = _G[viewerName]
                if viewer then
                    viewer:StopMovingOrSizing()
                    -- Save position via LibEditModeOverride
                    if LibEditModeOverride and EnsureEditModeReady() and LibEditModeOverride:HasEditModeSettings(viewer) then
                        local point, relativeTo, relativePoint, x, y = viewer:GetPoint(1)
                        pcall(function()
                            LibEditModeOverride:ReanchorFrame(viewer, point, relativeTo, relativePoint, x, y)
                        end)
                    end
                end
            end)
        end
    end
    -- Store reference for selection manager access
    self.cdmOverlays = viewerOverlays
end

-- Hide all viewer overlays
function QUICore:HideViewerOverlays()
    for _, viewerName in ipairs(CDM_VIEWERS) do
        local overlay = viewerOverlays[viewerName]
        if overlay then
            overlay:Hide()
            overlay:EnableMouse(false)
            overlay:SetScript("OnMouseDown", nil)
            overlay:SetScript("OnMouseUp", nil)
        end
    end
end

-- Show overlays on all Blizzard Edit Mode frames
function QUICore:ShowBlizzardFrameOverlays()
    for _, frameInfo in ipairs(BLIZZARD_EDITMODE_FRAMES) do
        local frameName = frameInfo.name
        local frame = _G[frameName]

        -- Skip if frame doesn't exist (e.g., DamageMeter not in combat)
        if frame then
            if not blizzardOverlays[frameName] then
                blizzardOverlays[frameName] = CreateBlizzardFrameOverlay(frameInfo)
            end
            local overlay = blizzardOverlays[frameName]
            if overlay then
                overlay:Show()

                -- Enable mouse on OVERLAY and handle clicks there
                overlay:EnableMouse(true)
                overlay:SetScript("OnMouseDown", function(self, button)
                    if button == "LeftButton" then
                        QUICore:SelectViewer(frameName)
                        -- Start drag on the frame
                        frame:SetMovable(true)  -- Enable movable for Blizzard Edit Mode frames
                        frame:StartMoving()
                    end
                end)
                overlay:SetScript("OnMouseUp", function(self, button)
                    if frame then
                        frame:StopMovingOrSizing()
                        -- Save position via LibEditModeOverride
                        if LibEditModeOverride and EnsureEditModeReady() and LibEditModeOverride:HasEditModeSettings(frame) then
                            local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
                            pcall(function()
                                LibEditModeOverride:ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
                            end)
                        end
                    end
                end)
            end
        end
    end
    -- Store reference for selection manager access
    self.blizzardOverlays = blizzardOverlays
end

-- Hide all Blizzard frame overlays
function QUICore:HideBlizzardFrameOverlays()
    for _, frameInfo in ipairs(BLIZZARD_EDITMODE_FRAMES) do
        local overlay = blizzardOverlays[frameInfo.name]
        if overlay then
            overlay:Hide()
            overlay:EnableMouse(false)
            overlay:SetScript("OnMouseDown", nil)
            overlay:SetScript("OnMouseUp", nil)
        end
    end
end

-- Show minimap overlay
function QUICore:ShowMinimapOverlay()
    if not minimapOverlay then
        minimapOverlay = CreateMinimapOverlay()
    end
    if minimapOverlay then
        minimapOverlay:Show()

        -- Enable mouse for click detection, pass drag to Minimap
        minimapOverlay:EnableMouse(true)
        minimapOverlay:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                QUICore:SelectEditModeElement("minimap", "minimap")
                -- Start drag on the Minimap
                if Minimap:IsMovable() then
                    Minimap:StartMoving()
                end
            end
        end)
        minimapOverlay:SetScript("OnMouseUp", function(self, button)
            Minimap:StopMovingOrSizing()
            -- Save position to DB
            local settings = QUICore.db and QUICore.db.profile and QUICore.db.profile.minimap
            if settings then
                local point, _, relPoint, x, y = Minimap:GetPoint()
                settings.position = {point, relPoint, x, y}
            end
            -- Update info text
            if minimapOverlay and minimapOverlay.infoText and settings and settings.position then
                minimapOverlay.infoText:SetText(string.format("Minimap  X:%d Y:%d",
                    math.floor(settings.position[3] or 0),
                    math.floor(settings.position[4] or 0)))
            end
        end)

        -- Store reference for selection manager access
        self.minimapOverlay = minimapOverlay
    end
end

-- Hide minimap overlay
function QUICore:HideMinimapOverlay()
    if minimapOverlay then
        minimapOverlay:Hide()
        minimapOverlay:EnableMouse(false)
        minimapOverlay:SetScript("OnMouseDown", nil)
        minimapOverlay:SetScript("OnMouseUp", nil)
    end
end

-- Edit Mode Click Detection

local clickDetector = CreateFrame("Frame")
clickDetector:Hide()
local lastClickedFrame = nil

function QUICore:EnableClickDetection()
    clickDetector:Show()
    clickDetector._elapsed = 0
    clickDetector:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = self._elapsed + elapsed
        if self._elapsed < 0.033 then return end -- ~30 FPS throttle
        self._elapsed = 0
        if IsMouseButtonDown("LeftButton") then
            local frames = GetMouseFoci()
            if frames and #frames > 0 then
                for _, frame in ipairs(frames) do
                    if frame and frame ~= WorldFrame then
                        local frameName = frame:GetName()

                        -- Check if this is one of our viewers or unit-frame anchors
                        if IsNudgeTargetFrameName(frameName) then
                            if lastClickedFrame ~= frame then
                                lastClickedFrame = frame
                                QUICore:SelectViewer(frameName)
                            end
                            return
                        end

                        -- Also check parent frame (for overlay clicks that pass through)
                        -- Overlays have no name but their parent is the viewer
                        if not frameName and frame:GetParent() then
                            local parentName = frame:GetParent():GetName()
                            if IsNudgeTargetFrameName(parentName) then
                                if lastClickedFrame ~= frame then
                                    lastClickedFrame = frame
                                    QUICore:SelectViewer(parentName)
                                end
                                return
                            end
                        end
                    end
                end
            end
        else
            lastClickedFrame = nil
        end
    end)
end

function QUICore:DisableClickDetection()
    clickDetector:Hide()
    clickDetector:SetScript("OnUpdate", nil)
    lastClickedFrame = nil
end

-- Viewer Selection & Nudging

-- Select a viewer for nudging
function QUICore:SelectViewer(viewerName)
    if not viewerName or not _G[viewerName] then
        self.selectedViewer = nil
        if self.nudgeFrame then
            self.nudgeFrame:UpdateInfo()
        end
        return
    end

    self.selectedViewer = viewerName

    -- Use central selection manager for click-to-select arrows
    -- Determine element type: "blizzard" for Blizzard Edit Mode frames, "cdm" for CDM viewers
    if self.SelectEditModeElement then
        local elementType = BLIZZARD_FRAME_LABELS[viewerName] and "blizzard" or "cdm"
        self:SelectEditModeElement(elementType, viewerName)
    end

    if self.nudgeFrame then
        self.nudgeFrame:UpdateInfo()
        local displayName = GetNudgeDisplayName(viewerName)
        UIDropDownMenu_SetText(self.nudgeFrame.viewerDropdown, displayName)
        -- Panel disabled - nudge arrows now on viewers directly
    end
end

-- Ensure LibEditModeOverride is ready and layouts are loaded
local function EnsureEditModeReady()
    if not LibEditModeOverride then
        return false
    end
    
    if not LibEditModeOverride:IsReady() then
        return false
    end
    
    if not LibEditModeOverride:AreLayoutsLoaded() then
        LibEditModeOverride:LoadLayouts()
    end
    
    return LibEditModeOverride:CanEditActiveLayout()
end

-- Nudge the selected viewer
function QUICore:NudgeSelectedViewer(direction)
    if not self.selectedViewer then return false end

    local viewer = _G[self.selectedViewer]
    if not viewer then return false end

    local amount = 1  -- Always 1px nudge

    -- Get current point from the Edit Mode system frame
    local point, relativeTo, relativePoint, xOfs, yOfs = viewer:GetPoint(1)
    if not point then return false end

    local newX = xOfs or 0
    local newY = yOfs or 0

    if direction == "UP" then
        newY = newY + amount
    elseif direction == "DOWN" then
        newY = newY - amount
    elseif direction == "LEFT" then
        newX = newX - amount
    elseif direction == "RIGHT" then
        newX = newX + amount
    end

    -- Use LibEditModeOverride if available (cleaner, more reliable)
    if LibEditModeOverride and EnsureEditModeReady() and LibEditModeOverride:HasEditModeSettings(viewer) then
        -- Use the library's ReanchorFrame method which properly registers with Edit Mode
        local success, err = pcall(function()
            LibEditModeOverride:ReanchorFrame(viewer, point, relativeTo, relativePoint, newX, newY)
        end)
        
        if success then
            -- Update the display in your nudge panel
            if self.nudgeFrame and self.nudgeFrame:IsShown() then
                self.nudgeFrame:UpdateInfo()
            end
            return true
        end
    end

    -- Fallback to manual method if library isn't available or frame isn't registered
    viewer:ClearAllPoints()
    viewer:SetPoint(point, relativeTo, relativePoint, newX, newY)

    -- Tell Edit Mode that THIS system's position changed
    if EditModeManagerFrame and EditModeManagerFrame.editModeActive then
        if EditModeManagerFrame.OnSystemPositionChange then
            -- Properly register that this Edit Mode system has a new position
            EditModeManagerFrame:OnSystemPositionChange(viewer)
        elseif EditModeManagerFrame.SetHasActiveChanges then
            -- Fallback: at least mark as dirty
            EditModeManagerFrame:SetHasActiveChanges(true)
        end
    end

    -- Update the display in your nudge panel
    if self.nudgeFrame and self.nudgeFrame:IsShown() then
        self.nudgeFrame:UpdateInfo()
    end

    return true
end

-- Nudge the minimap
function QUICore:NudgeMinimap(direction)
    local db = self.db and self.db.profile and self.db.profile.minimap
    if not db or not db.position then return end

    local amount = self.nudgeAmount or 1
    if IsShiftKeyDown() then amount = amount * 10 end

    -- position = {point, relativePoint, xOffset, yOffset}
    local xOfs = db.position[3] or 0
    local yOfs = db.position[4] or 0

    if direction == "UP" then
        yOfs = yOfs + amount
    elseif direction == "DOWN" then
        yOfs = yOfs - amount
    elseif direction == "LEFT" then
        xOfs = xOfs - amount
    elseif direction == "RIGHT" then
        xOfs = xOfs + amount
    end

    db.position[3] = xOfs
    db.position[4] = yOfs

    -- Apply position
    Minimap:ClearAllPoints()
    Minimap:SetPoint(db.position[1], UIParent, db.position[2], xOfs, yOfs)

    -- Update info text
    if minimapOverlay and minimapOverlay.infoText then
        minimapOverlay.infoText:SetText(string.format("Minimap  X:%d Y:%d", math.floor(xOfs), math.floor(yOfs)))
    end
end

-- Hook Edit Mode enter/exit
local function SetupEditModeHooks()
    if not EditModeManagerFrame then return end
    
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        -- Ensure LibEditModeOverride layouts are loaded when entering Edit Mode
        if LibEditModeOverride and LibEditModeOverride:IsReady() then
            if not LibEditModeOverride:AreLayoutsLoaded() then
                LibEditModeOverride:LoadLayouts()
            end
        end

        -- NudgeFrame is lazy-loaded, only update if it exists
        if QUICore.nudgeFrame then
            QUICore.nudgeFrame:UpdateVisibility()
        end
        QUICore:EnableClickDetection()
        -- Let Blizzard's native Edit Mode handle CDM viewers and standard Edit Mode frames
        -- QUICore:ShowViewerOverlays()
        -- QUICore:ShowBlizzardFrameOverlays()
        QUICore:ShowMinimapOverlay()  -- Show nudge overlay on QUI minimap
        QUICore:EnableMinimapEditMode()  -- Temporarily allow minimap movement
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        -- NudgeFrame is lazy-loaded, only hide if it exists
        if QUICore.nudgeFrame then
            QUICore.nudgeFrame:Hide()
        end
        QUICore:DisableClickDetection()
        -- QUICore:HideViewerOverlays()
        -- QUICore:HideBlizzardFrameOverlays()
        QUICore:HideMinimapOverlay()  -- Hide minimap overlay
        QUICore:DisableMinimapEditMode()  -- Restore minimap lock setting
        QUICore.selectedViewer = nil
        -- Clear central selection (in case a CDM viewer was selected)
        if QUICore.ClearEditModeSelection then
            QUICore:ClearEditModeSelection()
        end
        
        -- Fix for arrow-key positioning bug: Convert TOPLEFT anchoring to CENTER anchoring
        -- Arrow keys in Edit Mode use TOPLEFT anchor, mouse drag uses CENTER anchor
        -- Uses GetCenter() for exact center position directly from WoW
        C_Timer.After(0.066, function()
            local uiCenterX, uiCenterY = UIParent:GetCenter()

            -- Fix BuffIconCooldownViewer
            local buffViewer = _G["BuffIconCooldownViewer"]
            if buffViewer then
                local point = buffViewer:GetPoint(1)
                if point == "TOPLEFT" then
                    local frameCenterX, frameCenterY = buffViewer:GetCenter()
                    if frameCenterX and frameCenterY then
                        local offsetX = frameCenterX - uiCenterX
                        local offsetY = frameCenterY - uiCenterY

                        -- Try LibEditModeOverride first (proper way - saves to Edit Mode db)
                        local success = false
                        if LibEditModeOverride and LibEditModeOverride:HasEditModeSettings(buffViewer) then
                            success = pcall(function()
                                LibEditModeOverride:ReanchorFrame(buffViewer, "CENTER", UIParent, "CENTER", offsetX, offsetY)
                            end)
                        end

                        -- Fallback: Direct reanchor
                        if not success then
                            buffViewer:ClearAllPoints()
                            buffViewer:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
                        end
                    end
                end
            end

            -- Fix BuffBarCooldownViewer (tracked bars)
            local barViewer = _G["BuffBarCooldownViewer"]
            if barViewer then
                local point = barViewer:GetPoint(1)
                if point == "TOPLEFT" then
                    local frameCenterX, frameCenterY = barViewer:GetCenter()
                    if frameCenterX and frameCenterY then
                        local offsetX = frameCenterX - uiCenterX
                        local offsetY = frameCenterY - uiCenterY

                        -- Try LibEditModeOverride first (proper way - saves to Edit Mode db)
                        local success = false
                        if LibEditModeOverride and LibEditModeOverride:HasEditModeSettings(barViewer) then
                            success = pcall(function()
                                LibEditModeOverride:ReanchorFrame(barViewer, "CENTER", UIParent, "CENTER", offsetX, offsetY)
                            end)
                        end

                        -- Fallback: Direct reanchor
                        if not success then
                            barViewer:ClearAllPoints()
                            barViewer:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
                        end
                    end
                end
            end
        end)
    end)
end

if EditModeManagerFrame then
    SetupEditModeHooks()
else
    -- Wait for EditModeManagerFrame to load
    local waitFrame = CreateFrame("Frame")
    waitFrame:RegisterEvent("ADDON_LOADED")
    waitFrame:SetScript("OnEvent", function(self, event, addon)
        if EditModeManagerFrame then
            SetupEditModeHooks()
            self:UnregisterAllEvents()
        end
    end)
end

-- Fix anchor mismatch on startup (for /reload scenarios)
-- Uses GetCenter() for exact center position directly from WoW
local viewerAnchorFixFrame = CreateFrame("Frame")
viewerAnchorFixFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
viewerAnchorFixFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
    -- Only run on reload, not fresh launch (fresh launch has correct anchors)
    if not isReloadingUi then return end

    -- Delay to ensure Edit Mode data is loaded and viewers exist
    C_Timer.After(0.5, function()
        -- Get UIParent center for reference
        local uiCenterX, uiCenterY = UIParent:GetCenter()

        -- Fix BuffBarCooldownViewer anchor using GetCenter() for exact position
        local barViewer = _G["BuffBarCooldownViewer"]
        if barViewer then
            local point = barViewer:GetPoint(1)
            if point == "TOPLEFT" then
                -- Get exact center position directly from WoW
                local frameCenterX, frameCenterY = barViewer:GetCenter()
                if frameCenterX and frameCenterY then
                    -- Calculate offset from UIParent center
                    local offsetX = frameCenterX - uiCenterX
                    local offsetY = frameCenterY - uiCenterY

                    -- Apply the fix
                    barViewer:ClearAllPoints()
                    barViewer:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
                end
            end
        end

        -- Same fix for BuffIconCooldownViewer
        local iconViewer = _G["BuffIconCooldownViewer"]
        if iconViewer then
            local point = iconViewer:GetPoint(1)
            if point == "TOPLEFT" then
                local frameCenterX, frameCenterY = iconViewer:GetCenter()
                if frameCenterX and frameCenterY then
                    local offsetX = frameCenterX - uiCenterX
                    local offsetY = frameCenterY - uiCenterY

                    iconViewer:ClearAllPoints()
                    iconViewer:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
                end
            end
        end
    end)
end)

-- Add nudgeamount
local oldOnInitialize = QUICore.OnInitialize
function QUICore:OnInitialize()
    if oldOnInitialize then
        oldOnInitialize(self)
    end
    
    -- Add nudgeAmount default
    if not self.db.profile.nudgeAmount then
        self.db.profile.nudgeAmount = 1
    end
end