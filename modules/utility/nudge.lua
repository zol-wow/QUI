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
    DamageMeter = "Damage Meter",
    BossTargetFrameContainer = "Boss Frames",
    BuffBarCooldownViewer = "Tracked Bars",
    -- Action Bars (MainMenuBar renamed to MainActionBar in Midnight 12.0)
    MainActionBar = "Action Bar 1",
    MainMenuBar = "Action Bar 1",
    MultiBarBottomLeft = "Action Bar 2",
    MultiBarBottomRight = "Action Bar 3",
    MultiBarRight = "Action Bar 4",
    MultiBarLeft = "Action Bar 5",
    MultiBar5 = "Action Bar 6",
    MultiBar6 = "Action Bar 7",
    MultiBar7 = "Action Bar 8",
    PetActionBar = "Pet Bar",
    StanceBar = "Stance Bar",
    MicroMenuContainer = "Micro Menu",
    BagsBar = "Bag Bar",
    -- Display
    ObjectiveTrackerFrame = "Objective Tracker",
    GameTooltipDefaultContainer = "HUD Tooltip",
    TalkingHeadFrame = "Talking Head",
    ExtraAbilityContainer = "Extra Abilities",
}

-- CDM viewer names for click detection (populated when CDM_VIEWERS is defined)
local CDM_VIEWER_LOOKUP = {}

local Helpers = ns.Helpers

-- Weak-keyed table to track frames we force-showed in Edit Mode
-- (avoids writing custom properties directly onto protected Blizzard frames)
local _forceShownFrames = Helpers.CreateStateTable()

local function IsNudgeTargetFrameName(frameName)
    if not frameName then return false end

    -- CDM cooldown viewers (Essential, Utility, BuffIcon)
    if CDM_VIEWER_LOOKUP[frameName] then
        return true
    end

    -- Our cooldown viewers (legacy)
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
        local viewer = viewerName and ResolveCDMFrame(viewerName)

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
local viewersForceShown = {}  -- Viewers we force-showed during edit mode
local _viewerSelectionHooked = {}  -- guard: hook CDM viewer .Selection once each

-- Expose overlay lookup for cdm_viewer Edit Mode resize handler.
_G.QUI_GetCDMViewerOverlay = function(viewerName)
    return viewerOverlays[viewerName]
end

-- All CDM viewers that should get nudge overlays
-- Each entry maps a resolver key to its display name. The actual frame is
-- obtained at runtime via _G.QUI_GetCDMViewerFrame(key).
local CDM_VIEWERS = {
    { key = "essential", name = "EssentialCooldownViewer", anchorKey = "cdmEssential" },
    { key = "utility",   name = "UtilityCooldownViewer",   anchorKey = "cdmUtility" },
    { key = "buffIcon",  name = "BuffIconCooldownViewer",  anchorKey = "buffIcon" },
    { key = "buffBar",   name = "BuffBarCooldownViewer",   anchorKey = "buffBar" },
}
-- Reverse lookup: name -> key (used by generic functions that receive a name)
local CDM_NAME_TO_KEY = {}
for _, entry in ipairs(CDM_VIEWERS) do
    CDM_VIEWER_LOOKUP[entry.name] = true
    CDM_NAME_TO_KEY[entry.name] = entry.key
end

-- Resolve a CDM viewer frame by name (checks CDM_NAME_TO_KEY first, falls back to _G)
local function ResolveCDMFrame(viewerName)
    local key = CDM_NAME_TO_KEY[viewerName]
    if key and _G.QUI_GetCDMViewerFrame then
        return _G.QUI_GetCDMViewerFrame(key)
    end
    return _G[viewerName]
end

-- Blizzard Edit Mode frames that should get nudge overlays
local BLIZZARD_EDITMODE_FRAMES = {
    { name = "BuffFrame", label = "Buff Frame", passthrough = true, requireSelection = true },
    { name = "DebuffFrame", label = "Debuff Frame", passthrough = true, requireSelection = true },
    { name = "DamageMeter", label = "Damage Meter", passthrough = true },
    { name = "BossTargetFrameContainer", label = "Boss Frames", passthrough = true, requireSelection = true },
    -- Action Bars (MainMenuBar renamed to MainActionBar in Midnight 12.0)
    -- passthrough = true: free movers use click-passthrough like CDM viewers
    -- (EnableMouse false, hide Blizzard .Selection, let Blizzard menu open)
    { name = "MainActionBar", label = "Action Bar 1", fallback = "MainMenuBar", passthrough = true },
    { name = "MultiBarBottomLeft", label = "Action Bar 2", passthrough = true },
    { name = "MultiBarBottomRight", label = "Action Bar 3", passthrough = true },
    { name = "MultiBarRight", label = "Action Bar 4", passthrough = true },
    { name = "MultiBarLeft", label = "Action Bar 5", passthrough = true },
    { name = "MultiBar5", label = "Action Bar 6", passthrough = true },
    { name = "MultiBar6", label = "Action Bar 7", passthrough = true },
    { name = "MultiBar7", label = "Action Bar 8", passthrough = true },
    { name = "PetActionBar", label = "Pet Bar", passthrough = true, requireSelection = true },
    { name = "StanceBar", label = "Stance Bar", passthrough = true, requireSelection = true },
    { name = "MicroMenuContainer", label = "Micro Menu", passthrough = true },
    { name = "BagsBar", label = "Bag Bar", passthrough = true },
    -- Display
    { name = "ObjectiveTrackerFrame", label = "Objective Tracker", passthrough = true, requireSelection = true },
    { name = "GameTooltipDefaultContainer", label = "HUD Tooltip", passthrough = true },
    { name = "ChatFrame1", label = "Chat Frame", passthrough = true, requireSelection = true },
    -- Talking Head: only show overlay when Blizzard's .Selection is active
    -- (user has it enabled in edit mode settings).  requireSelection gates this.
    { name = "TalkingHeadFrame", label = "Talking Head", passthrough = true, requireSelection = true },
    -- Extra Abilities: gated on .Selection like Talking Head.
    -- resolver needed because ExtraAbilitiesContainer may not be a global;
    -- find it via ExtraActionBarFrame's parent chain.
    { name = "ExtraAbilityContainer", label = "Extra Abilities", passthrough = true, requireSelection = true },
}

local blizzardOverlays = {}
local _selectionHooked = {}  -- track which .Selection frames we've hooked for requireSelection

---------------------------------------------------------------------------
-- MOVEMENT BLOCKING FOR LOCKED FRAMES
-- Override OnDragStart AND OnDragStop to no-op on selection child frames
-- that handle Edit Mode dragging (both Blizzard's .Selection and LibEditMode).
-- Must disable both: OnDragStart prevents the drag from initiating, and
-- OnDragStop prevents updatePosition() from calling ClearAllPoints/SetPoint
-- which would normalize (and visibly shift) the frame's anchor on mouse-up.
-- Mouse remains enabled so tooltips, click-to-select, and right-click
-- menus still work.  No position watcher needed → no relayout flicker.
---------------------------------------------------------------------------

local _blockedFrames = {}        -- frame -> true
local _savedDragScripts = {}     -- child frame -> {start, stop} original scripts

-- Replace OnDragStart + OnDragStop with no-ops and unregister drag
-- so the event never fires (works even on secure frames).
local function DisableChildDrag(child)
    if not child then return end
    if _savedDragScripts[child] ~= nil then return end  -- already disabled
    _savedDragScripts[child] = {
        start = child:GetScript("OnDragStart") or false,
        stop  = child:GetScript("OnDragStop") or false,
    }
    child:SetScript("OnDragStart", function() end)  -- no-op
    child:SetScript("OnDragStop", function() end)    -- no-op
    pcall(function() child:RegisterForDrag() end)    -- unregister drag
end

-- Restore original OnDragStart + OnDragStop and re-register drag
local function RestoreChildDrag(child)
    if not child then return end
    local saved = _savedDragScripts[child]
    if saved == nil then return end  -- wasn't disabled by us
    _savedDragScripts[child] = nil
    child:SetScript("OnDragStart", saved.start or nil)
    child:SetScript("OnDragStop", saved.stop or nil)
    pcall(function() child:RegisterForDrag("LeftButton") end)  -- re-register drag
end

local function BlockFrameMovement(frame)
    if not frame then return end
    if _blockedFrames[frame] then return end  -- already blocked
    _blockedFrames[frame] = true

    -- Disable drag on Blizzard's native .Selection (if present)
    if frame.Selection then
        DisableChildDrag(frame.Selection)
    end

    -- Disable drag on LibEditMode's selection frame.
    -- LibEditMode creates a child frame using EditModeSystemSelectionTemplate.
    -- Find it by iterating children — identified by .system table + OnDragStart.
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        if child.system and child:GetScript("OnDragStart") then
            DisableChildDrag(child)
        end
    end
end

local function UnblockFrameMovement(frame)
    if not frame then return end
    if not _blockedFrames[frame] then return end
    _blockedFrames[frame] = nil

    -- Restore drag on Blizzard's native .Selection
    if frame.Selection then
        RestoreChildDrag(frame.Selection)
    end

    -- Restore drag on LibEditMode selections
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        if child.system then
            RestoreChildDrag(child)
        end
    end
end

-- Restore all blocked frames (called on Edit Mode exit)
local function UnblockAllFrameMovement()
    for frame in pairs(_blockedFrames) do
        if frame.Selection then
            RestoreChildDrag(frame.Selection)
        end
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if ok and children then
            for _, child in ipairs(children) do
                if child.system then
                    RestoreChildDrag(child)
                end
            end
        end
    end
    wipe(_blockedFrames)
    -- Restore any remaining drag scripts that weren't caught above
    -- (e.g., reparented .Selection frames where container.Selection was
    -- cleared before unblock ran).  Use RestoreChildDrag so re-register
    -- logic (RegisterForDrag) runs too.
    local leftovers = {}
    for child in pairs(_savedDragScripts) do
        leftovers[#leftovers + 1] = child
    end
    for _, child in ipairs(leftovers) do
        RestoreChildDrag(child)
    end
end

---------------------------------------------------------------------------
-- SELECTION FRAME ALPHA FOR LOCKED FRAMES
-- Make Blizzard's blue .Selection indicator transparent on locked frames.
-- Uses SetAlpha(0) instead of Hide() so GetRect() still returns valid
-- bounds for Blizzard's magnetic snap system (GetScaledSelectionSides).
-- Deferred via C_Timer.After(0) to avoid tainting the secure context.
---------------------------------------------------------------------------

local _hiddenSelections = {}  -- frame -> true

local function HideSelectionIndicator(frame)
    if not frame or not frame.Selection then return end
    if _G.QUI_IsSelectionKeepVisible and _G.QUI_IsSelectionKeepVisible(frame.Selection) then return end
    if _hiddenSelections[frame] then return end
    _hiddenSelections[frame] = true
    frame.Selection:SetAlpha(0)
    C_Timer.After(0, function()
        if frame.Selection and not (_G.QUI_IsSelectionKeepVisible and _G.QUI_IsSelectionKeepVisible(frame.Selection)) then
            frame.Selection:SetAlpha(0)
            -- Ensure .Selection has valid bounds so GetScaledSelectionSides()
            -- doesn't crash when Blizzard iterates magnetic snap candidates.
            -- GetRect() returns nil if the frame has no size or anchors.
            if not frame.Selection:GetRect() then
                frame.Selection:SetAllPoints(frame)
            end
        end
    end)
end

local function ShowSelectionIndicator(frame)
    if not frame or not frame.Selection then return end
    if not _hiddenSelections[frame] then return end
    _hiddenSelections[frame] = nil
    C_Timer.After(0, function()
        if frame.Selection then
            frame.Selection:SetAlpha(1)
        end
    end)
end

local function RestoreAllSelectionIndicators()
    for frame in pairs(_hiddenSelections) do
        if frame.Selection then
            C_Timer.After(0, function()
                if frame.Selection then
                    frame.Selection:SetAlpha(1)
                end
            end)
        end
    end
    wipe(_hiddenSelections)
end

-- Create a nudge button with chevron arrows (same style as unit frames)
local function CreateViewerNudgeButton(parent, direction, viewerName)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    -- Use DIALOG strata so nudge buttons appear above overlays (HIGH)
    btn:SetFrameStrata("DIALOG")
    btn:SetFrameLevel(100)

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
    -- Use DIALOG strata so nudge buttons appear above overlays (HIGH)
    btn:SetFrameStrata("DIALOG")
    btn:SetFrameLevel(100)

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
-- Parent to the QUI container (always visible).  Blizzard viewers stay
-- at alpha 0 — overlays on QUI containers track the visible frame.
local function CreateViewerOverlay(viewerName)
    local viewer = ResolveCDMFrame(viewerName) or _G[viewerName]
    if not viewer then return nil end

    local overlay = CreateFrame("Frame", nil, viewer, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetFrameStrata("HIGH")
    local px = QUICore:GetPixelSize(overlay)
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
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
    overlay.label = label
    overlay.displayName = displayName

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
    -- Support fallback names (e.g., MainActionBar -> MainMenuBar)
    if not frame and frameInfo.fallback then
        frame = _G[frameInfo.fallback]
    end
    if not frame then return nil end

    -- Parent to UIParent for alwaysShow frames so the overlay remains visible
    -- even when the source frame is hidden (e.g. PetActionBar with no pet).
    local parent = frameInfo.alwaysShow and UIParent or frame
    local overlay = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if frameInfo.alwaysShow then
        overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    elseif frameName == "ChatFrame1" then
        overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 2)
        overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, -8)
    elseif frame.Selection and frame.Selection:GetRect() then
        overlay:SetPoint("TOPLEFT", frame.Selection, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", frame.Selection, "BOTTOMRIGHT", 0, 0)
    else
        overlay:SetAllPoints()
    end
    overlay:SetFrameStrata("HIGH")
    local px = QUICore:GetPixelSize(overlay)
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
    overlay:EnableMouse(false)

    -- Label showing frame name
    local labelText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOP", overlay, "TOP", 0, -4)
    labelText:SetText(label)
    labelText:SetTextColor(0.2, 0.8, 1, 1)
    overlay.label = labelText
    overlay.displayName = label

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
    overlay:SetFrameStrata("HIGH")
    local px = QUICore:GetPixelSize(overlay)
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
    })
    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
    overlay:EnableMouse(false)

    -- Label showing "Minimap"
    local labelText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOP", overlay, "TOP", 0, -4)
    labelText:SetText("Minimap")
    labelText:SetTextColor(0.2, 0.8, 1, 1)
    overlay.label = labelText

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
    -- Force CDM frames to full alpha so overlays (children) are visible.
    -- HUD visibility may have faded them to 0; we restore on edit mode exit.
    if _G.QUI_RefreshCDMVisibility then
        _G.QUI_RefreshCDMVisibility()
    end

    -- Force-show hidden CDM containers so overlays become visible.
    wipe(viewersForceShown)
    for _, entry in ipairs(CDM_VIEWERS) do
        local viewerName = entry.name
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(entry.key)
        if viewer and not viewer:IsShown() then
            C_Timer.After(0, function()
                if viewer and not viewer:IsShown() then
                    pcall(function() viewer:Show() end)
                end
            end)
            viewersForceShown[viewerName] = true
        end
    end

    for _, entry in ipairs(CDM_VIEWERS) do
        local viewerName = entry.name
        if not viewerOverlays[viewerName] then
            viewerOverlays[viewerName] = CreateViewerOverlay(viewerName)
        end
        local overlay = viewerOverlays[viewerName]
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(entry.key)
        -- Blizzard viewer (for .Selection access — Selection stays on the
        -- Blizzard frame, not reparented to QUI containers).
        local blizzViewer = _G[viewerName]

        -- Hook .Selection show/hide so toggling a CDM viewer on/off in
        -- Blizzard's edit mode menu hides/shows THIS viewer's overlay only.
        -- Per-viewer hooks avoid re-processing all viewers (which can cause
        -- unrelated overlays to flicker or disappear during Blizzard re-layout).
        if viewer then
            local sel = blizzViewer and blizzViewer.Selection
            if sel and not _viewerSelectionHooked[sel] then
                _viewerSelectionHooked[sel] = true
                local hookedName = viewerName  -- capture for closure
                local hookedKey = entry.key    -- capture resolver key for closure
                sel:HookScript("OnHide", function()
                    if not EditModeManagerFrame or not EditModeManagerFrame:IsShown() then return end
                    local ov = viewerOverlays[hookedName]
                    if ov then
                        ov:Hide()
                        ov:EnableMouse(false)
                    end
                    if viewersForceShown[hookedName] then
                        local v = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(hookedKey)
                        if v then
                            C_Timer.After(0, function()
                                if v then
                                    pcall(function() v:Hide() end)
                                end
                            end)
                        end
                        viewersForceShown[hookedName] = nil
                    end
                end)
                sel:HookScript("OnShow", function(self)
                    if not EditModeManagerFrame or not EditModeManagerFrame:IsShown() then return end
                    -- Re-show QUI container if it was hidden
                    local v = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(hookedKey)
                    if v and not v:IsShown() then
                        C_Timer.After(0, function()
                            if v and not v:IsShown() then
                                pcall(function() v:Show() end)
                            end
                        end)
                        viewersForceShown[hookedName] = true
                    end
                    local ov = viewerOverlays[hookedName]
                    if ov then
                        ov:Show()
                    end
                end)
            end
            -- Skip overlay when .Selection is hidden (viewer disabled in edit mode settings).
            -- Also re-hide the viewer if we force-showed it on edit mode enter.
            if sel and not sel:IsShown() then
                if overlay then
                    overlay:Hide()
                    overlay:EnableMouse(false)
                end
                if viewersForceShown[viewerName] then
                    C_Timer.After(0, function()
                        if viewer then
                            pcall(function() viewer:Hide() end)
                        end
                    end)
                    viewersForceShown[viewerName] = nil
                end
                overlay = nil  -- skip locked/free logic below
            end
        end

        if overlay then
            -- Check if this viewer is locked by any anchoring system
            local isLocked = viewer and _G.QUI_IsFrameLocked and _G.QUI_IsFrameLocked(viewer)

            if isLocked then
                -- Locked: grey overlay, clickable to open CDM settings
                overlay:Show()
                overlay:SetBackdropColor(0.5, 0.5, 0.5, 0.3)
                overlay:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
                if overlay.label then
                    overlay.label:SetTextColor(0.5, 0.5, 0.5, 0.8)
                    overlay.label:SetText((overlay.displayName or viewerName) .. "  (Locked)")
                end
                if viewer then
                    BlockFrameMovement(viewer)
                end
                -- Clickable overlay — opens CDM settings panel
                overlay:EnableMouse(true)
                overlay:SetScript("OnMouseDown", nil)
                overlay:SetScript("OnMouseUp", function()
                    if _G.CooldownViewerSettings and _G.CooldownViewerSettings.Show then
                        _G.CooldownViewerSettings:Show()
                    end
                end)
            else
                -- Free: show blue QUI overlay, draggable to move QUI container.
                -- Click (no drag) opens CDM settings panel.
                overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
                overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
                if overlay.label then
                    overlay.label:SetTextColor(0.2, 0.8, 1, 1)
                    overlay.label:SetText(overlay.displayName or viewerName)
                end
                overlay:EnableMouse(true)
                overlay:SetMovable(true)
                overlay:RegisterForDrag("LeftButton")
                local capturedViewer = viewer  -- closure capture
                local capturedName = viewerName
                overlay:SetScript("OnMouseDown", function(self, button)
                    if button == "LeftButton" then
                        self.__dragging = false
                        self.__didDrag = false
                        QUICore:SelectViewer(capturedName)
                    end
                end)
                overlay:SetScript("OnDragStart", function(self)
                    self.__dragging = true
                    self.__didDrag = true
                    if capturedViewer then
                        capturedViewer:SetMovable(true)
                        capturedViewer:StartMoving()
                    end
                end)
                overlay:SetScript("OnDragStop", function(self)
                    self.__dragging = false
                    if capturedViewer then
                        pcall(function() capturedViewer:StopMovingOrSizing() end)
                    end
                    -- Save position after drag
                    if _G.QUI_SaveCDMPosition then
                        _G.QUI_SaveCDMPosition(capturedName)
                    end
                    -- Update dependent anchors
                    if _G.QUI_UpdateCDMAnchorProxyFrames then
                        _G.QUI_UpdateCDMAnchorProxyFrames()
                    end
                    if _G.QUI_UpdateFramesAnchoredTo then
                        _G.QUI_UpdateFramesAnchoredTo(capturedViewer)
                    end
                end)
                overlay:SetScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" and not self.__didDrag then
                        if _G.CooldownViewerSettings and _G.CooldownViewerSettings.Show then
                            _G.CooldownViewerSettings:Show()
                        end
                    end
                end)
                -- BuffBarCooldownViewer repositions dynamically (LayoutBuffBars).
                -- ApplyTrackedBarAnchor is guarded during Edit Mode so QUI won't
                -- move it, but Blizzard's own Edit Mode may reposition to saved coords.
                --
                -- Strategy: detach overlay to UIParent.  After viewer moves,
                -- an OnUpdate syncs the overlay to follow.
                if viewerName == "BuffBarCooldownViewer" and viewer then
                    local cx = Helpers.SafeValue(viewer:GetCenter(), nil)
                    local _, cy = viewer:GetCenter()
                    cy = Helpers.SafeValue(cy, nil)
                    local fw = Helpers.SafeValue(viewer:GetWidth(), 0)
                    local fh = Helpers.SafeValue(viewer:GetHeight(), 0)
                    if cx and cy and fw > 0 and fh > 0 then
                        local usx = Helpers.SafeValue(UIParent:GetCenter(), 0)
                        local _, usy = UIParent:GetCenter()
                        usy = Helpers.SafeValue(usy, 0)
                        overlay:SetParent(UIParent)
                        overlay:ClearAllPoints()
                        overlay:SetSize(fw, fh)
                        overlay:SetPoint("CENTER", UIParent, "CENTER", cx - usx, cy - usy)
                        overlay:SetFrameStrata("HIGH")
                        overlay:SetFrameLevel(100)
                    end
                    -- Continuously sync overlay position and size to viewer frame
                    overlay:SetScript("OnUpdate", function(self)
                        if InCombatLockdown() then return end
                        local vcx = Helpers.SafeValue(viewer:GetCenter(), nil)
                        local _, vcy = viewer:GetCenter()
                        vcy = Helpers.SafeValue(vcy, nil)
                        if not vcx or not vcy then return end
                        local vw = Helpers.SafeValue(viewer:GetWidth(), nil)
                        local vh = Helpers.SafeValue(viewer:GetHeight(), nil)
                        if not vw or not vh then return end
                        local usx2 = Helpers.SafeValue(UIParent:GetCenter(), nil)
                        local _, usy2 = UIParent:GetCenter()
                        usy2 = Helpers.SafeValue(usy2, nil)
                        if not usx2 or not usy2 then return end
                        -- Sync size
                        local curW = Helpers.SafeValue(self:GetWidth(), 0)
                        local curH = Helpers.SafeValue(self:GetHeight(), 0)
                        if math.abs(curW - vw) > 0.5 or math.abs(curH - vh) > 0.5 then
                            self:SetSize(vw, vh)
                        end
                        -- Sync position
                        local curCx = Helpers.SafeValue(self:GetCenter(), nil)
                        local _, curCy = self:GetCenter()
                        curCy = Helpers.SafeValue(curCy, nil)
                        if curCx and curCy then
                            local dx = math.abs((vcx - usx2) - (curCx - usx2))
                            local dy = math.abs((vcy - usy2) - (curCy - usy2))
                            if dx < 0.5 and dy < 0.5 then return end
                        end
                        self:ClearAllPoints()
                        self:SetPoint("CENTER", UIParent, "CENTER", vcx - usx2, vcy - usy2)
                    end)
                    overlay:Show()
                else
                    overlay:Show()
                end
                if viewer then
                    UnblockFrameMovement(viewer)
                    if _G.QUI_UpdateCDMAnchorProxyFrames then
                        _G.QUI_UpdateCDMAnchorProxyFrames()
                    end
                end
            end

            -- Size BuffIcon overlay to the anchor proxy so the overlay
            -- matches the effective bounds used for dependent-frame
            -- anchoring (accounts for icon measurement + scale + min-width).
            if viewerName == "BuffIconCooldownViewer" and viewer then
                local getProxy = _G.QUI_GetCDMAnchorProxyFrame
                local proxy = type(getProxy) == "function" and getProxy("buffIcon") or nil
                if proxy then
                    local pw = Helpers.SafeValue(proxy:GetWidth(), 0)
                    local ph = Helpers.SafeValue(proxy:GetHeight(), 0)
                    if pw > 1 and ph > 1 then
                        -- Proxy is in UIParent space; overlay is a child
                        -- of the viewer, so divide by viewer scale.
                        local vScale = Helpers.SafeValue(viewer:GetScale(), 1)
                        if vScale <= 0 then vScale = 1 end
                        overlay:ClearAllPoints()
                        overlay:SetPoint("CENTER", viewer, "CENTER", 0, 0)
                        overlay:SetSize(pw / vScale, ph / vScale)
                    end
                end
            end
        end
    end
    -- Store reference for selection manager access
    self.cdmOverlays = viewerOverlays

end

-- Hide all viewer overlays
function QUICore:HideViewerOverlays()
    for _, entry in ipairs(CDM_VIEWERS) do
        local viewerName = entry.name
        local overlay = viewerOverlays[viewerName]
        if overlay then
            overlay:Hide()
            overlay:EnableMouse(false)
            overlay:SetScript("OnMouseDown", nil)
            overlay:SetScript("OnMouseUp", nil)
            overlay:SetScript("OnUpdate", nil)
            -- Re-parent overlay back to QUI container if it was
            -- detached to UIParent during Edit Mode (BuffBarCooldownViewer).
            if overlay:GetParent() == UIParent then
                local quiContainer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(entry.key)
                local parent = quiContainer or _G[viewerName]
                if parent then
                    overlay:SetParent(parent)
                    overlay:ClearAllPoints()
                    overlay:SetAllPoints()
                end
            end
        end
        -- Re-hide viewers we force-showed on edit mode enter.
        if viewersForceShown[viewerName] then
            local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame(entry.key)
            if viewer then
                C_Timer.After(0, function()
                    if viewer then
                        pcall(function() viewer:Hide() end)
                    end
                end)
            end
        end
    end
    wipe(viewersForceShown)
end

-- Show overlays on all Blizzard Edit Mode frames
function QUICore:ShowBlizzardFrameOverlays()
    for _, frameInfo in ipairs(BLIZZARD_EDITMODE_FRAMES) do
        local frameName = frameInfo.name
        local frame = _G[frameName]

        -- Support fallback names (e.g., MainActionBar -> MainMenuBar for pre-Midnight)
        if not frame and frameInfo.fallback then
            frame = _G[frameInfo.fallback]
            if frame then
                frameName = frameInfo.fallback
            end
        end

        -- Skip if frame doesn't exist, or is hidden unless alwaysShow
        -- (e.g., hidden action bars/damage meters skip, but PetActionBar/StanceBar always show)
        -- Force-show alwaysShow frames so the bar and .Selection are visible
        -- in Edit Mode (e.g., PetActionBar when pet is dismissed).
        if frame and frameInfo.alwaysShow and not frame:IsShown() then
            if not InCombatLockdown() then
                frame:Show()
                _forceShownFrames[frame] = true
            end
        end

        -- Skip frames gated on Selection visibility (e.g., TalkingHead disabled
        -- in Blizzard's edit mode settings).  If the user hasn't enabled this
        -- system in edit mode, don't create an overlay — it would be invisible
        -- but could block clicks on underlying frames.
        if frame and frameInfo.requireSelection then
            local sel = frame.Selection
            -- Hook Selection show/hide so toggling mid-edit-mode refreshes overlays
            if sel and not _selectionHooked[sel] then
                _selectionHooked[sel] = true
                sel:HookScript("OnShow", function()
                    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                        QUICore:ShowBlizzardFrameOverlays()
                    end
                end)
                sel:HookScript("OnHide", function()
                    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                        QUICore:ShowBlizzardFrameOverlays()
                    end
                end)
            end
            if not sel or not sel:IsShown() then
                -- System is disabled in edit mode settings — hide any existing overlay
                if blizzardOverlays[frameName] then
                    blizzardOverlays[frameName]:Hide()
                    blizzardOverlays[frameName]:EnableMouse(false)
                end
                frame = nil  -- skip overlay creation below
            end
        end

        if frame and (frame:IsShown() or frameInfo.alwaysShow or frameInfo.passthrough) then
            if not blizzardOverlays[frameName] then
                blizzardOverlays[frameName] = CreateBlizzardFrameOverlay(frameInfo)
            elseif not frameInfo.alwaysShow and blizzardOverlays[frameName]:GetParent() ~= frame then
                -- Frame was recreated by its addon (e.g., Details! damage meter).
                -- The old overlay is orphaned; rebuild for the new frame.
                blizzardOverlays[frameName] = CreateBlizzardFrameOverlay(frameInfo)
            end
            local overlay = blizzardOverlays[frameName]
            if overlay then
                -- Check if this frame is locked by any anchoring system
                local isLocked = _G.QUI_IsFrameLocked and _G.QUI_IsFrameLocked(frame)

                if isLocked then
                    -- Locked: grey overlay, no drag allowed.
                    overlay:Show()
                    overlay:SetBackdropColor(0.5, 0.5, 0.5, 0.3)
                    overlay:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
                    if overlay.label then
                        overlay.label:SetTextColor(0.5, 0.5, 0.5, 0.8)
                        overlay.label:SetText((overlay.displayName or frameName) .. "  (Locked)")
                    end
                    -- For force-shown frames, bar buttons eat click-throughs
                    -- so we handle the menu directly on the overlay.
                    if _forceShownFrames[frame] then
                        overlay:EnableMouse(true)
                        overlay:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                            GameTooltip:SetText(overlay.displayName or frameName)
                            GameTooltip:Show()
                        end)
                        overlay:SetScript("OnLeave", function(self)
                            GameTooltip:Hide()
                        end)
                        overlay:SetScript("OnMouseDown", function(self, button)
                            if button == "LeftButton" and frame.SelectSystem then
                                pcall(function()
                                    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
                                        EditModeManagerFrame:ClearSelectedSystem()
                                    end
                                    frame.isSelected = false
                                    frame:SelectSystem()
                                    if frame.Selection then
                                        frame.Selection:SetAlpha(0)
                                    end
                                end)
                            end
                        end)
                        overlay:SetScript("OnMouseUp", nil)
                    else
                        -- Normal locked: click-through to .Selection for menu
                        overlay:EnableMouse(false)
                        overlay:SetScript("OnMouseDown", nil)
                        overlay:SetScript("OnMouseUp", nil)
                    end
                    -- Block drag by overriding OnDragStart on selection children
                    BlockFrameMovement(frame)
                    -- Hide Blizzard's blue .Selection indicator
                    HideSelectionIndicator(frame)
                elseif frameInfo.passthrough and not _forceShownFrames[frame] then
                    -- Free passthrough: visual-only QUI overlay, clicks pass
                    -- through to Blizzard's .Selection for Edit Mode menu + drag.
                    overlay:Show()
                    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
                    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
                    if overlay.label then
                        overlay.label:SetTextColor(0.2, 0.8, 1, 1)
                        overlay.label:SetText(overlay.displayName or frameName)
                    end
                    overlay:EnableMouse(false)
                    overlay:SetScript("OnMouseDown", nil)
                    overlay:SetScript("OnMouseUp", nil)
                    UnblockFrameMovement(frame)
                    HideSelectionIndicator(frame)
                else
                    -- Free: show blue QUI overlay with drag handling.
                    -- For force-shown frames (alwaysShow), also open the
                    -- Blizzard Edit Mode menu on clean left-click.
                    overlay:Show()
                    overlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
                    overlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
                    if overlay.label then
                        overlay.label:SetTextColor(0.2, 0.8, 1, 1)
                        overlay.label:SetText(overlay.displayName or frameName)
                    end
                    -- Ensure movement is unblocked for free frames
                    UnblockFrameMovement(frame)
                    ShowSelectionIndicator(frame)
                    overlay:EnableMouse(true)
                    if _forceShownFrames[frame] then
                        overlay:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                            GameTooltip:SetText(overlay.displayName or frameName)
                            GameTooltip:Show()
                        end)
                        overlay:SetScript("OnLeave", function(self)
                            GameTooltip:Hide()
                        end)
                    end
                    overlay:SetMovable(true)
                    overlay:RegisterForDrag("LeftButton")
                    overlay:SetScript("OnMouseDown", function(self, button)
                        if button == "LeftButton" then
                            self.__dragging = false
                            QUICore:SelectViewer(frameName)
                            -- Open Blizzard Edit Mode menu on mouse down
                            -- (matches stance bar behavior).
                            if _forceShownFrames[frame] and frame.SelectSystem then
                                pcall(function()
                                    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
                                        EditModeManagerFrame:ClearSelectedSystem()
                                    end
                                    frame.isSelected = false
                                    frame:SelectSystem()
                                    if frame.Selection then
                                        frame.Selection:SetAlpha(0)
                                    end
                                end)
                            end
                        end
                    end)
                    overlay:SetScript("OnDragStart", function(self)
                        self.__dragging = true
                        pcall(function()
                            frame:SetMovable(true)
                            frame:StartMoving()
                        end)
                    end)
                    overlay:SetScript("OnDragStop", function(self)
                        self.__dragging = false
                        pcall(function() frame:StopMovingOrSizing() end)
                        if LibEditModeOverride and EnsureEditModeReady() and LibEditModeOverride:HasEditModeSettings(frame) then
                            local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
                            pcall(function()
                                LibEditModeOverride:ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
                            end)
                        end
                    end)
                    overlay:SetScript("OnMouseUp", nil)
                end
            end
        end
    end
    -- Store reference for selection manager access
    self.blizzardOverlays = blizzardOverlays
end

-- Hide all Blizzard frame overlays
function QUICore:HideBlizzardFrameOverlays()
    for _, frameInfo in ipairs(BLIZZARD_EDITMODE_FRAMES) do
        local frameName = frameInfo.name
        local frame = _G[frameName]
        if not frame and frameInfo.fallback then
            frame = _G[frameInfo.fallback]
        end
        local overlay = blizzardOverlays[frameName]
        -- Check fallback name too (e.g., MainActionBar -> MainMenuBar)
        if not overlay and frameInfo.fallback then
            overlay = blizzardOverlays[frameInfo.fallback]
        end
        if overlay then
            overlay:Hide()
            overlay:EnableMouse(false)
            overlay:SetScript("OnMouseDown", nil)
            overlay:SetScript("OnMouseUp", nil)
            overlay:SetScript("OnDragStart", nil)
            overlay:SetScript("OnDragStop", nil)
            -- Stop watchers when leaving Edit Mode
            if overlay._passthroughWatcher then
                overlay._passthroughWatcher:Hide()
            end
            if overlay._selectionAlphaWatcher then
                overlay._selectionAlphaWatcher:Hide()
            end
        end
        -- Hide frames we force-showed on Edit Mode enter
        if frame and _forceShownFrames[frame] then
            if not InCombatLockdown() then
                frame:Hide()
            end
            _forceShownFrames[frame] = nil
        end
    end
end

-- Forward declarations — these must be visible to ShowMinimapOverlay's drag
-- handlers (closures capture locals by lexical scope; locals declared later in
-- the file would be invisible and resolve to nil globals).
local _resizeContainer = nil  -- lazily created mover frame; Minimap anchors to this during edit mode
local _preEditMinimapPosition = nil  -- snapshot of db.minimap.position on edit mode enter
local _preEditMinimapSize = nil      -- snapshot of db.minimap.size on edit mode enter
local _editModeSaved = false         -- set true by SaveLayoutChanges hook; false = revert
local _editModeMoving = false        -- true while edit mode is active (mover anchored)

-- Mark Blizzard's Edit Mode layout as having unsaved changes so the
-- save/revert dialog appears on exit. Deferred to the next frame via
-- C_Timer.After(0) to isolate addon-code taint from Blizzard's secure
-- Edit Mode execution context.
local function MarkEditModeLayoutDirty()
    C_Timer.After(0, function()
        if not EditModeManagerFrame then return end
        if EditModeManagerFrame.hasActiveChanges then return end
        pcall(EditModeManagerFrame.SetHasActiveChanges, EditModeManagerFrame, true)
    end)
end

-- Show minimap overlay
function QUICore:ShowMinimapOverlay()
    if not minimapOverlay then
        minimapOverlay = CreateMinimapOverlay()
    end
    if not minimapOverlay then return end

    -- Check if the minimap is locked by any anchoring system
    local isLocked = Minimap and _G.QUI_IsFrameLocked and _G.QUI_IsFrameLocked(Minimap)

    -- Helper: anchor the overlay to cover the minimap
    local function AnchorOverlayToMinimap()
        minimapOverlay:ClearAllPoints()
        minimapOverlay:SetAllPoints(Minimap)
    end

    if isLocked then
        -- Locked: grey overlay, block movement
        minimapOverlay:Show()
        minimapOverlay:SetBackdropColor(0.5, 0.5, 0.5, 0.3)
        minimapOverlay:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        if minimapOverlay.label then
            minimapOverlay.label:SetTextColor(0.5, 0.5, 0.5, 0.8)
            minimapOverlay.label:SetText("Minimap  (Locked)")
        end
        AnchorOverlayToMinimap()
        minimapOverlay:EnableMouse(false)
        minimapOverlay:SetScript("OnMouseDown", nil)
        minimapOverlay:SetScript("OnMouseUp", nil)
        minimapOverlay:SetScript("OnDragStart", nil)
        minimapOverlay:SetScript("OnDragStop", nil)
        minimapOverlay:RegisterForDrag()
        BlockFrameMovement(Minimap)
    else
        -- Free: unified mover drag.
        -- The overlay stays attached to Minimap at all times. On drag,
        -- _resizeContainer (the mover) is moved via StartMoving(). Minimap
        -- follows automatically (anchored at CENTER 0,0), and the overlay
        -- follows Minimap (child, SetAllPoints). Everything moves as one unit.
        minimapOverlay:Show()
        minimapOverlay:SetBackdropColor(0.2, 0.8, 1, 0.3)
        minimapOverlay:SetBackdropBorderColor(0.2, 0.8, 1, 1)
        if minimapOverlay.label then
            minimapOverlay.label:SetTextColor(0.2, 0.8, 1, 1)
            minimapOverlay.label:SetText("Minimap")
        end
        AnchorOverlayToMinimap()
        minimapOverlay:EnableMouse(true)
        minimapOverlay:RegisterForDrag("LeftButton")

        minimapOverlay:SetScript("OnDragStart", function(self)
            if _resizeContainer then
                _resizeContainer:StartMoving()
            end
            -- Update frames anchored to minimap during drag
            self:SetScript("OnUpdate", function()
                if _G.QUI_UpdateFramesAnchoredTo then
                    _G.QUI_UpdateFramesAnchoredTo("minimap")
                end
            end)
        end)

        minimapOverlay:SetScript("OnDragStop", function(self)
            if _resizeContainer then
                _resizeContainer:StopMovingOrSizing()
            end
            self:SetScript("OnUpdate", nil)
            -- Snap mover to pixel grid and save position
            if not InCombatLockdown() and _resizeContainer then
                local pt, _, rp, ox, oy = QUICore:SnapFramePosition(_resizeContainer)
                if pt then
                    local mmSettings = QUICore.db and QUICore.db.profile
                        and QUICore.db.profile.minimap
                    if mmSettings then
                        mmSettings.position = {pt, rp, ox, oy}
                    end
                end
            end
            MarkEditModeLayoutDirty()
            if _G.QUI_UpdateFramesAnchoredTo then
                _G.QUI_UpdateFramesAnchoredTo("minimap")
            end
        end)

        -- Left-click: select minimap (shows nudge buttons) and open
        -- Blizzard's Edit Mode settings panel. SelectSystem() is deferred
        -- to isolate addon-code taint from Blizzard's secure context.
        minimapOverlay:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                QUICore:SelectEditModeElement("minimap", "minimap")
                C_Timer.After(0, function()
                    if MinimapCluster and MinimapCluster.SelectSystem then
                        pcall(function()
                            MinimapCluster.isSelected = false
                            MinimapCluster:SelectSystem()
                        end)
                    end
                end)
            end
        end)
        minimapOverlay:SetScript("OnMouseUp", nil)
        minimapOverlay:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText("Minimap")
            GameTooltip:Show()
        end)
        minimapOverlay:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        UnblockFrameMovement(Minimap)
    end

    -- Store reference for selection manager access
    self.minimapOverlay = minimapOverlay
end

-- Hide minimap overlay
function QUICore:HideMinimapOverlay()
    if minimapOverlay then
        minimapOverlay:Hide()
        minimapOverlay:EnableMouse(false)
        minimapOverlay:SetScript("OnMouseDown", nil)
        minimapOverlay:SetScript("OnMouseUp", nil)
        minimapOverlay:SetScript("OnDragStart", nil)
        minimapOverlay:SetScript("OnDragStop", nil)
        minimapOverlay:SetScript("OnEnter", nil)
        minimapOverlay:SetScript("OnLeave", nil)
        minimapOverlay:SetScript("OnUpdate", nil)
        minimapOverlay:RegisterForDrag()
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

                        -- Walk up ancestor chain to find a nudge target.
                        -- Clicks land on .Selection children (which may be named
                        -- or unnamed), so check multiple parent levels.
                        local ancestor = frame:GetParent()
                        for _ = 1, 5 do
                            if not ancestor then break end
                            local ancestorName = ancestor:GetName()
                            if IsNudgeTargetFrameName(ancestorName) then
                                if lastClickedFrame ~= frame then
                                    lastClickedFrame = frame
                                    QUICore:SelectViewer(ancestorName)
                                end
                                return
                            end
                            ancestor = ancestor:GetParent()
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
    if not viewerName or not ResolveCDMFrame(viewerName) then
        self.selectedViewer = nil
        if self.nudgeFrame then
            self.nudgeFrame:UpdateInfo()
        end
        return
    end

    self.selectedViewer = viewerName

    -- Use central selection manager for click-to-select arrows
    -- Determine element type: CDM viewers first, then "blizzard" for Blizzard Edit Mode frames
    if self.SelectEditModeElement then
        local elementType
        if CDM_VIEWER_LOOKUP[viewerName] then
            elementType = "cdm"
        elseif BLIZZARD_FRAME_LABELS[viewerName] then
            elementType = "blizzard"
        else
            elementType = "cdm"
        end
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

---------------------------------------------------------------------------
-- MINIMAP EDIT MODE ANCHOR SETUP
-- During Edit Mode, Minimap is anchored to an invisible mover frame
-- (_resizeContainer). Dragging the mover moves everything as one unit.
-- On exit, Minimap is detached and repositioned directly on UIParent.
---------------------------------------------------------------------------

-- Detect save vs revert on Edit Mode exit.
-- SaveLayoutChanges is called when the user saves; it is NOT called when the
-- user reverts/discards. StopClusterSizeWatcher checks _editModeSaved to decide
-- whether to commit or revert minimap position/size changes made during edit mode.
if EditModeManagerFrame and EditModeManagerFrame.SaveLayoutChanges then
    hooksecurefunc(EditModeManagerFrame, "SaveLayoutChanges", function()
        _editModeSaved = true
    end)
end

-- Anchor Minimap to the mover frame for Edit Mode drag/nudge.
function QUICore.StartClusterSizeWatcher()
    _editModeSaved = false
    _editModeMoving = true

    if not Minimap then return end

    -- Snapshot minimap DB state so we can revert on exit-without-saving.
    -- Deep-copy the position array so nudge writes don't mutate our snapshot.
    local settings = QUICore.db and QUICore.db.profile and QUICore.db.profile.minimap
    if settings then
        _preEditMinimapPosition = settings.position and {unpack(settings.position)} or nil
        _preEditMinimapSize = settings.size
    end

    -- Create the mover frame once (lazy). Invisible frame on UIParent
    -- that serves as the drag anchor for Minimap during Edit Mode.
    if not _resizeContainer then
        _resizeContainer = CreateFrame("Frame", nil, UIParent)
        _resizeContainer:SetAlpha(0)
        _resizeContainer:Show()
    end

    -- Position mover at Minimap's screen center (accounting for scale)
    local mCx, mCy = Minimap:GetCenter()
    local mmScale = Minimap:GetScale() or 1
    local px, py = UIParent:GetCenter()
    if mCx and px then
        local mmW = Minimap:GetWidth()
        _resizeContainer:ClearAllPoints()
        _resizeContainer:SetPoint("CENTER", UIParent, "CENTER",
            mCx * mmScale - px, mCy * mmScale - py)
        _resizeContainer:SetSize(mmW, mmW)
        _resizeContainer:SetMovable(true)
        _resizeContainer:SetClampedToScreen(true)

        -- Anchor Minimap to mover at CENTER (0,0).
        -- Dragging the mover moves Minimap (and all its children) as one unit.
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", _resizeContainer, "CENTER", 0, 0)
    end
    Minimap:SetClampedToScreen(false)
end

-- Detach Minimap from the mover and handle save vs revert on Edit Mode exit.
function QUICore.StopClusterSizeWatcher()
    _editModeMoving = false

    if not Minimap then return end
    local settings = QUICore.db and QUICore.db.profile and QUICore.db.profile.minimap

    if not _editModeSaved and _preEditMinimapPosition then
        -- REVERT: restore snapshot position and size to the DB and frame.
        if settings then
            settings.position = {unpack(_preEditMinimapPosition)}
            if _preEditMinimapSize then
                settings.size = _preEditMinimapSize
            end
        end
        Minimap:ClearAllPoints()
        local pos = _preEditMinimapPosition
        Minimap:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or "CENTER",
            pos[3] or 0, pos[4] or 0)
    else
        -- SAVE: detach from mover, keep current position.
        local mCx, mCy = Minimap:GetCenter()
        local mmScale = Minimap:GetScale() or 1
        local pCx, pCy = UIParent:GetCenter()
        local ox = (mCx and pCx) and ((mCx * mmScale - pCx) / mmScale) or 0
        local oy = (mCy and pCy) and ((mCy * mmScale - pCy) / mmScale) or 0
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
        if settings then
            settings.position = {"CENTER", "CENTER", ox, oy}
        end
    end

    Minimap:SetClampedToScreen(true)
    _preEditMinimapPosition = nil
    _preEditMinimapSize = nil
end

-- Sync a detached overlay (e.g. BuffBarCooldownViewer) to its viewer position.
-- Called after nudging moves the viewer so the overlay follows.
function QUICore:SyncDetachedOverlay(viewerName)
    if viewerName ~= "BuffBarCooldownViewer" then return end
    local overlay = viewerOverlays[viewerName]
    local viewer = ResolveCDMFrame(viewerName)
    if not overlay or not viewer then return end
    -- Only sync if overlay is parented to UIParent (detached)
    if overlay:GetParent() ~= UIParent then return end
    local cx, cy = viewer:GetCenter()
    if not cx or not cy then return end
    local usx, usy = UIParent:GetCenter()
    if not usx or not usy then return end
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", UIParent, "CENTER", cx - usx, cy - usy)
end

-- Nudge the selected viewer
function QUICore:NudgeSelectedViewer(direction)
    if not self.selectedViewer then return false end

    local viewer = ResolveCDMFrame(self.selectedViewer)
    if not viewer then return false end

    -- Block nudging if frame is locked by any anchoring system
    if _G.QUI_IsFrameLocked and _G.QUI_IsFrameLocked(viewer) then
        return false
    end

    local amount = 1  -- Always 1px nudge

    -- Compute delta
    local dx, dy = 0, 0
    if direction == "UP" then
        dy = amount
    elseif direction == "DOWN" then
        dy = -amount
    elseif direction == "LEFT" then
        dx = -amount
    elseif direction == "RIGHT" then
        dx = amount
    end

    -- Use LibEditModeOverride if available (cleaner, more reliable)
    -- SKIP for BuffBarCooldownViewer: ReanchorFrame triggers Blizzard's
    -- OnSystemPositionChange → ResetPartyFrames → CompactUnitFrame taint.
    -- Use direct AdjustPointsOffset instead (same as drag handler).
    if LibEditModeOverride and EnsureEditModeReady()
        and LibEditModeOverride:HasEditModeSettings(viewer)
        and self.selectedViewer ~= "BuffBarCooldownViewer" then
        local point, relativeTo, relativePoint, xOfs, yOfs = viewer:GetPoint(1)
        if not point then return false end
        local newX = (xOfs or 0) + dx
        local newY = (yOfs or 0) + dy
        local success, err = pcall(function()
            LibEditModeOverride:ReanchorFrame(viewer, point, relativeTo, relativePoint, newX, newY)
        end)

        if success then
            if self.nudgeFrame and self.nudgeFrame:IsShown() then
                self.nudgeFrame:UpdateInfo()
            end
            if _G.QUI_UpdateFramesAnchoredTo then
                _G.QUI_UpdateFramesAnchoredTo(viewer)
            end
            return true
        end
    end

    -- Fallback: Use AdjustPointsOffset to shift existing anchor offsets IN-PLACE.
    -- This avoids ClearAllPoints() + SetPoint() which momentarily orphans the frame,
    -- triggering Blizzard's layout cascade on all dependent frames.
    -- AdjustPointsOffset(dx, dy) simply adds dx/dy to all existing anchor point offsets.
    if viewer.AdjustPointsOffset then
        viewer:AdjustPointsOffset(dx, dy)
    else
        local point, relativeTo, relativePoint, xOfs, yOfs = viewer:GetPoint(1)
        if point then
            viewer:ClearAllPoints()
            viewer:SetPoint(point, relativeTo, relativePoint, (xOfs or 0) + dx, (yOfs or 0) + dy)
        end
    end

    -- Sync detached overlay for BuffBarCooldownViewer
    self:SyncDetachedOverlay(self.selectedViewer)

    -- TAINT SAFETY: Do NOT call EditModeManagerFrame:SetHasActiveChanges(true) or
    -- EditModeManagerFrame:OnSystemPositionChange() here.
    -- SetHasActiveChanges() is a direct method call on a secure frame — taints it.
    -- OnSystemPositionChange() triggers magnetic snap recalculation (flicker).

    if self.nudgeFrame and self.nudgeFrame:IsShown() then
        self.nudgeFrame:UpdateInfo()
    end

    if _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo(viewer)
    end

    -- Save CDM container position to DB after nudge
    if CDM_VIEWER_LOOKUP[self.selectedViewer] and _G.QUI_SaveCDMPosition then
        _G.QUI_SaveCDMPosition(self.selectedViewer)
    end

    return true
end

-- Nudge the minimap
function QUICore:NudgeMinimap(direction)
    -- Block nudging if minimap is locked by any anchoring system
    if _G.QUI_IsFrameLocked and _G.QUI_IsFrameLocked(Minimap) then
        return
    end

    if InCombatLockdown() then return end

    local db = self.db and self.db.profile and self.db.profile.minimap
    if not db or not db.position then return end

    local amount = self.nudgeAmount or 1
    if IsShiftKeyDown() then amount = amount * 10 end

    -- Normalize position format (handles both keyed defaults and array from drag)
    local pos = db.position
    local point = pos[1] or pos.point or "CENTER"
    local relPoint = pos[2] or pos.relPoint or "CENTER"
    local xOfs = pos[3] or pos.x or 0
    local yOfs = pos[4] or pos.y or 0

    if direction == "UP" then
        yOfs = yOfs + amount
    elseif direction == "DOWN" then
        yOfs = yOfs - amount
    elseif direction == "LEFT" then
        xOfs = xOfs - amount
    elseif direction == "RIGHT" then
        xOfs = xOfs + amount
    end

    -- Save back in array format (canonical after first nudge)
    db.position = {point, relPoint, xOfs, yOfs}

    -- Apply position
    if _editModeMoving and _resizeContainer then
        -- Move mover by the nudge delta; Minimap follows via (0,0) anchor
        -- Use AdjustPointsOffset to preserve whatever anchor WoW set after StopMovingOrSizing
        local dx = (direction == "RIGHT" and amount or direction == "LEFT" and -amount or 0)
        local dy = (direction == "UP" and amount or direction == "DOWN" and -amount or 0)
        if _resizeContainer.AdjustPointsOffset then
            _resizeContainer:AdjustPointsOffset(dx, dy)
        else
            local pt, rel, relPt, cOx, cOy = _resizeContainer:GetPoint(1)
            if pt then
                _resizeContainer:ClearAllPoints()
                _resizeContainer:SetPoint(pt, rel, relPt, (cOx or 0) + dx, (cOy or 0) + dy)
            end
        end
        MarkEditModeLayoutDirty()
    else
        Minimap:ClearAllPoints()
        Minimap:SetPoint(point, UIParent, relPoint, xOfs, yOfs)
    end

    if _G.QUI_UpdateFramesAnchoredTo then
        _G.QUI_UpdateFramesAnchoredTo("minimap")
    end

    -- Update info text
    if minimapOverlay and minimapOverlay.infoText then
        minimapOverlay.infoText:SetText(string.format("Minimap  X:%d Y:%d", math.floor(xOfs), math.floor(yOfs)))
    end
end

-- Register Edit Mode enter/exit callbacks via central dispatcher (avoids taint from
-- multiple hooksecurefunc calls on EnterEditMode/ExitEditMode).
local function RegisterEditModeCallbacks()
    -- Enter callback
    QUICore:RegisterEditModeEnter(function()
        -- Ensure LibEditModeOverride layouts are loaded when entering Edit Mode
        if LibEditModeOverride and LibEditModeOverride:IsReady() then
            if not LibEditModeOverride:AreLayoutsLoaded() then
                LibEditModeOverride:LoadLayouts()
            end
        end

        -- Anchor Minimap to the mover frame for drag/nudge
        QUICore.StartClusterSizeWatcher()

        -- Snapshot positions of all QUI-managed frames (including disabled overrides).
        -- When exiting Edit Mode without saving, Blizzard reverts frames to its own
        -- stored positions — which may not match where QUI had positioned them.
        -- We capture the current position so we can restore it after Blizzard's revert.
        QUICore._editModeFrameSnapshots = {}
        if _G.QUI_GetFrameAnchoringDB then
            local db = _G.QUI_GetFrameAnchoringDB()
            if db then
                for key, settings in pairs(db) do
                    if type(settings) == "table" then
                        local resolver = _G.QUI_GetFrameResolver and _G.QUI_GetFrameResolver(key)
                        local frame = resolver and resolver()
                        -- For boss frames (table of frames), snapshot the first
                        if frame and type(frame) == "table" and not frame.GetObjectType then
                            frame = frame[1]
                        end
                        if frame and frame.GetPoint and frame:GetNumPoints() and frame:GetNumPoints() > 0 then
                            local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
                            if point then
                                QUICore._editModeFrameSnapshots[key] = {
                                    frame = frame,
                                    point = point,
                                    relativeTo = relativeTo,
                                    relativePoint = relativePoint,
                                    xOfs = xOfs,
                                    yOfs = yOfs,
                                    enabled = settings.enabled,
                                }
                            end
                        end
                    end
                end
            end
        end

        -- NudgeFrame is lazy-loaded, only update if it exists
        if QUICore.nudgeFrame then
            QUICore.nudgeFrame:UpdateVisibility()
        end
        QUICore:EnableClickDetection()
        QUICore:ShowViewerOverlays()
        QUICore:ShowBlizzardFrameOverlays()
        QUICore:ShowMinimapOverlay()  -- Show nudge overlay on QUI minimap
        QUICore:EnableMinimapEditMode()  -- Temporarily allow minimap movement
    end)

    -- Exit callback
    QUICore:RegisterEditModeExit(function()
        -- Detach Minimap from mover and handle save vs revert
        QUICore.StopClusterSizeWatcher()

        -- Refresh minimap layout (backdrop, border, data text, etc.)
        if _G.QUI_RefreshMinimap then
            _G.QUI_RefreshMinimap()
        end

        -- Restore drag scripts and .Selection alpha on all locked frames
        UnblockAllFrameMovement()
        RestoreAllSelectionIndicators()

        -- NudgeFrame is lazy-loaded, only hide if it exists
        if QUICore.nudgeFrame then
            QUICore.nudgeFrame:Hide()
        end
        QUICore:DisableClickDetection()
        QUICore:HideViewerOverlays()
        QUICore:HideBlizzardFrameOverlays()
        QUICore:HideMinimapOverlay()  -- Hide minimap overlay
        QUICore:DisableMinimapEditMode()  -- Restore minimap lock setting
        -- Restore CDM visibility to match HUD visibility settings.
        -- Edit mode forced alpha 1; now re-evaluate so hidden frames fade back out.
        if _G.QUI_RefreshCDMVisibility then
            _G.QUI_RefreshCDMVisibility()
        end
        QUICore.selectedViewer = nil
        -- Clear central selection (in case a CDM viewer was selected)
        if QUICore.ClearEditModeSelection then
            QUICore:ClearEditModeSelection()
        end

        -- Re-snap all anchored frames after Blizzard finishes reverting positions.
        -- When exiting Edit Mode without saving, Blizzard reverts frame positions
        -- asynchronously (ClearAllPoints + SetPoint on each frame). This overrides
        -- QUI's anchor chain positioning. The timing varies by frame count and
        -- system load. We counteract this with:
        -- 1. An OnUpdate watcher that re-applies every ~0.2s for ~2s
        -- 2. A final definitive re-anchor at 3s (after all Blizzard reverts are done)
        -- QUI_UpdateAnchoredFrames handles frames with ENABLED anchors.
        -- Frames with DISABLED anchors need special handling: Blizzard's revert puts
        -- them at Blizzard's stored position (which may differ from where QUI had them).
        -- We restore those from the snapshot captured on Edit Mode entry.
        -- TAINT SAFETY: Uses QUICore._editModeActive flag instead of secure frame reads.

        -- Restore snapshots for frames with disabled anchors.
        -- These frames are not managed by QUI_UpdateAnchoredFrames (because their
        -- anchor is disabled), but Blizzard's revert may move them to the wrong position.
        local snapshots = QUICore._editModeFrameSnapshots
        local function RestoreDisabledAnchorSnapshots()
            if not snapshots then return end
            for key, snap in pairs(snapshots) do
                -- Only restore frames whose anchor is CURRENTLY disabled.
                -- Enabled anchors are handled by QUI_UpdateAnchoredFrames.
                local db = _G.QUI_GetFrameAnchoringDB and _G.QUI_GetFrameAnchoringDB()
                local settings = db and db[key]
                if settings and not settings.enabled and snap.frame then
                    pcall(function()
                        snap.frame:ClearAllPoints()
                        snap.frame:SetPoint(
                            snap.point,
                            snap.relativeTo or UIParent,
                            snap.relativePoint,
                            snap.xOfs or 0,
                            snap.yOfs or 0
                        )
                    end)
                end
            end
        end

        if _G.QUI_UpdateAnchoredFrames then
            -- Immediate re-apply to minimize the visible jump
            _G.QUI_UpdateAnchoredFrames()
            if _G.QUI_ApplyAllFrameAnchors then
                _G.QUI_ApplyAllFrameAnchors()
            end
            RestoreDisabledAnchorSnapshots()

            local anchorWatcher = CreateFrame("Frame", nil, UIParent)
            local totalElapsed = 0
            local tickElapsed = 0
            local DURATION = 2.0     -- seconds to keep re-applying via OnUpdate
            local INTERVAL = 0.2     -- seconds between each re-apply
            anchorWatcher:SetScript("OnUpdate", function(self, dt)
                totalElapsed = totalElapsed + dt
                if totalElapsed >= DURATION then
                    self:SetScript("OnUpdate", nil)
                    return
                end
                -- If user re-entered Edit Mode, stop immediately
                if QUICore._editModeActive then
                    self:SetScript("OnUpdate", nil)
                    return
                end
                -- Throttle: only re-apply every INTERVAL seconds
                tickElapsed = tickElapsed + dt
                if tickElapsed < INTERVAL then return end
                tickElapsed = 0
                -- Re-apply all anchored frame positions (enabled anchors)
                _G.QUI_UpdateAnchoredFrames()
                -- Re-apply frame anchoring overrides (cdmUtility, power bars, etc.)
                if _G.QUI_ApplyAllFrameAnchors then
                    _G.QUI_ApplyAllFrameAnchors()
                end
                -- Restore disabled-anchor frames to their pre-Edit-Mode position
                RestoreDisabledAnchorSnapshots()
            end)

            -- Final definitive re-anchor well after Blizzard's revert completes.
            -- This catches any late Blizzard layout passes that fire after the watcher.
            C_Timer.After(3.0, function()
                if QUICore._editModeActive then return end
                _G.QUI_UpdateAnchoredFrames()
                if _G.QUI_ApplyAllFrameAnchors then
                    _G.QUI_ApplyAllFrameAnchors()
                end
                RestoreDisabledAnchorSnapshots()
                -- Clean up snapshots
                QUICore._editModeFrameSnapshots = nil
            end)
        end

        -- Fix for arrow-key positioning bug: Convert TOPLEFT anchoring to CENTER anchoring
        -- Arrow keys in Edit Mode use TOPLEFT anchor, mouse drag uses CENTER anchor
        -- Uses GetCenter() for exact center position directly from WoW
        C_Timer.After(0.066, function()
            local uiCenterX, uiCenterY = UIParent:GetCenter()

            -- Fix BuffIconCooldownViewer
            local buffViewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffIcon")
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
            local barViewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffBar")
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

RegisterEditModeCallbacks()

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
        local barViewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffBar")
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
        local iconViewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("buffIcon")
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