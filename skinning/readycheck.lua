local addonName, ns = ...

---------------------------------------------------------------------------
-- READY CHECK FRAME SKINNING
-- QUI skinning for ReadyCheckFrame
---------------------------------------------------------------------------

local FONT_FLAGS = "OUTLINE"

-- Forward declaration for mover (used in ResetReadyCheckPosition)
local readyCheckMover = nil

---------------------------------------------------------------------------
-- POSITION SAVING/LOADING
---------------------------------------------------------------------------

local function GetSettings()
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general then
        return QUICore.db.profile.general
    end
    return nil
end

local function SaveReadyCheckPosition(point, relativeTo, relativePoint, x, y)
    local settings = GetSettings()
    if settings then
        settings.readyCheckPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y
        }
    end
end

local function GetReadyCheckPosition()
    local settings = GetSettings()
    if settings and settings.readyCheckPosition then
        return settings.readyCheckPosition
    end
    return nil
end

local function ResetReadyCheckPosition()
    local settings = GetSettings()
    if settings then
        settings.readyCheckPosition = nil
    end
    -- Reset to default position
    local frame = _G.ReadyCheckFrame
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -10)
    end
    -- Also reset mover overlay if it exists
    if readyCheckMover then
        readyCheckMover:ClearAllPoints()
        readyCheckMover:SetPoint("CENTER", UIParent, "CENTER", 0, -10)
    end
end

-- Expose reset function globally
_G.QUI_ResetReadyCheckPosition = ResetReadyCheckPosition

---------------------------------------------------------------------------
-- MOVER OVERLAY
---------------------------------------------------------------------------

local function CreateMover()
    if readyCheckMover then return end

    local frame = _G.ReadyCheckFrame
    if not frame then return end

    -- Get skin colors for mover
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end

    -- Create mover overlay
    readyCheckMover = CreateFrame("Frame", "QUI_ReadyCheckMover", UIParent, "BackdropTemplate")
    readyCheckMover:SetSize(frame:GetWidth() + 4, frame:GetHeight() + 4)
    readyCheckMover:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    readyCheckMover:SetBackdropColor(sr, sg, sb, 0.3)
    readyCheckMover:SetBackdropBorderColor(sr, sg, sb, 1)
    readyCheckMover:EnableMouse(true)
    readyCheckMover:SetMovable(true)
    readyCheckMover:RegisterForDrag("LeftButton")
    readyCheckMover:SetFrameStrata("FULLSCREEN_DIALOG")
    readyCheckMover:Hide()

    -- Position mover at frame's location (or saved position)
    local pos = GetReadyCheckPosition()
    if pos then
        readyCheckMover:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        readyCheckMover:SetPoint("CENTER", UIParent, "CENTER", 0, -10)
    end

    -- Mover label
    readyCheckMover.text = readyCheckMover:CreateFontString(nil, "OVERLAY")
    readyCheckMover.text:SetPoint("CENTER")
    readyCheckMover.text:SetFont(STANDARD_TEXT_FONT, 11, FONT_FLAGS)
    readyCheckMover.text:SetText("Ready Check")
    readyCheckMover.text:SetTextColor(1, 1, 1)

    -- Drag handlers
    readyCheckMover:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    readyCheckMover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint()
        SaveReadyCheckPosition(point, nil, relPoint, x, y)
    end)
end

local function ShowMover()
    CreateMover()
    if readyCheckMover then
        readyCheckMover:Show()
    end
end

local function HideMover()
    if readyCheckMover then
        readyCheckMover:Hide()
    end
end

local function ToggleMover()
    if readyCheckMover and readyCheckMover:IsShown() then
        HideMover()
    else
        ShowMover()
    end
end

-- Expose toggle function globally
_G.QUI_ToggleReadyCheckMover = ToggleMover

---------------------------------------------------------------------------
-- HELPER FUNCTIONS
---------------------------------------------------------------------------

-- Get QUI skin colors with fallback
local function GetSkinColors()
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1  -- Fallback mint
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95  -- Fallback dark

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

-- Create QUI-styled backdrop on a frame
local function CreateQUIBackdrop(frame)
    if frame.quiBackdrop then return frame.quiBackdrop end

    local backdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    backdrop:SetAllPoints()
    backdrop:SetFrameLevel(frame:GetFrameLevel())
    backdrop:EnableMouse(false)  -- Don't steal clicks

    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    frame.quiBackdrop = backdrop
    return backdrop
end

-- Style a button with QUI look
local function SkinButton(button, sr, sg, sb, bgr, bgg, bgb, bga)
    if not button or button.quiSkinned then return end

    -- Hide default button textures
    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.LeftSeparator then button.LeftSeparator:SetAlpha(0) end
    if button.RightSeparator then button.RightSeparator:SetAlpha(0) end

    -- Hide NineSlice if present
    if button.NineSlice then button.NineSlice:SetAlpha(0) end

    -- Strip other textures
    for _, region in ipairs({button:GetRegions()}) do
        if region:GetObjectType() == "Texture" then
            local drawLayer = region:GetDrawLayer()
            if drawLayer == "BACKGROUND" then
                region:SetAlpha(0)
            end
        end
    end

    -- Create backdrop
    local backdrop = CreateQUIBackdrop(button)
    local btnBgr = math.min(bgr + 0.07, 1)  -- Slightly lighter for buttons
    local btnBgg = math.min(bgg + 0.07, 1)
    local btnBgb = math.min(bgb + 0.07, 1)
    backdrop:SetBackdropColor(btnBgr, btnBgg, btnBgb, bga)
    backdrop:SetBackdropBorderColor(sr, sg, sb, 1)

    -- Store colors for hover effects
    button.quiNormalBg = { btnBgr, btnBgg, btnBgb, bga }
    button.quiHoverBg = { math.min(btnBgr + 0.1, 1), math.min(btnBgg + 0.1, 1), math.min(btnBgb + 0.1, 1), bga }
    button.quiBorderColor = { sr, sg, sb, 1 }

    -- Hover effects
    button:HookScript("OnEnter", function(self)
        if self.quiBackdrop and self.quiHoverBg then
            self.quiBackdrop:SetBackdropColor(unpack(self.quiHoverBg))
        end
    end)
    button:HookScript("OnLeave", function(self)
        if self.quiBackdrop and self.quiNormalBg then
            self.quiBackdrop:SetBackdropColor(unpack(self.quiNormalBg))
        end
    end)

    -- Style button text
    local text = button:GetFontString()
    if text then
        text:SetFont(STANDARD_TEXT_FONT, 12, FONT_FLAGS)
        text:SetTextColor(0.9, 0.9, 0.9, 1)
    end

    button.quiSkinned = true
end

-- Update button colors (for live refresh)
local function RefreshButtonColors(button, sr, sg, sb, bgr, bgg, bgb, bga)
    if not button or not button.quiBackdrop then return end

    local btnBgr = math.min(bgr + 0.07, 1)
    local btnBgg = math.min(bgg + 0.07, 1)
    local btnBgb = math.min(bgb + 0.07, 1)

    button.quiNormalBg = { btnBgr, btnBgg, btnBgb, bga }
    button.quiHoverBg = { math.min(btnBgr + 0.1, 1), math.min(btnBgg + 0.1, 1), math.min(btnBgb + 0.1, 1), bga }
    button.quiBorderColor = { sr, sg, sb, 1 }

    button.quiBackdrop:SetBackdropColor(btnBgr, btnBgg, btnBgb, bga)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, 1)
end

---------------------------------------------------------------------------
-- HIDE BLIZZARD DECORATIONS
---------------------------------------------------------------------------

local function HideBlizzardDecorations()
    local frame = _G.ReadyCheckFrame
    local listenerFrame = _G.ReadyCheckListenerFrame
    if not frame then return end

    -- Hide portrait texture
    if _G.ReadyCheckPortrait then
        _G.ReadyCheckPortrait:SetAlpha(0)
    end

    -- The main decorations are on ReadyCheckListenerFrame
    if listenerFrame then
        -- Hide NineSlice border (the main frame decoration)
        if listenerFrame.NineSlice then
            listenerFrame.NineSlice:SetAlpha(0)
        end

        -- Hide PortraitContainer (gold circle frame)
        if listenerFrame.PortraitContainer then
            listenerFrame.PortraitContainer:SetAlpha(0)
        end

        -- Hide TitleContainer (header bar with "Ready Check" text)
        if listenerFrame.TitleContainer then
            listenerFrame.TitleContainer:SetAlpha(0)
        end

        -- Hide background texture
        if listenerFrame.Bg then
            listenerFrame.Bg:SetAlpha(0)
        end

        -- Hide all textures on listener frame
        for _, region in ipairs({listenerFrame:GetRegions()}) do
            if region:GetObjectType() == "Texture" then
                region:SetAlpha(0)
            end
        end
    end

    -- Also hide any textures directly on ReadyCheckFrame
    for _, region in ipairs({frame:GetRegions()}) do
        if region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
        end
    end
end

---------------------------------------------------------------------------
-- MAIN SKINNING FUNCTION
---------------------------------------------------------------------------

local function SkinReadyCheckFrame()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinReadyCheck then return end

    local frame = _G.ReadyCheckFrame
    local listenerFrame = _G.ReadyCheckListenerFrame
    if not frame or frame.quiSkinned then return end

    -- Get colors
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    -- Hide Blizzard decorations
    HideBlizzardDecorations()

    -- Create QUI backdrop on ListenerFrame (where the content is)
    local targetFrame = listenerFrame or frame
    local backdrop = CreateQUIBackdrop(targetFrame)
    backdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    backdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Store reference on main frame for refresh
    frame.quiBackdrop = backdrop

    -- Skin Yes/No buttons and re-center them
    local yesButton = _G.ReadyCheckFrameYesButton
    local noButton = _G.ReadyCheckFrameNoButton

    if yesButton then
        SkinButton(yesButton, sr, sg, sb, bgr, bgg, bgb, bga)
        yesButton:ClearAllPoints()
        yesButton:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOM", -5, 12)
    end
    if noButton then
        SkinButton(noButton, sr, sg, sb, bgr, bgg, bgb, bga)
        noButton:ClearAllPoints()
        noButton:SetPoint("BOTTOMLEFT", targetFrame, "BOTTOM", 5, 12)
    end

    -- Style and re-center the main text (was offset for portrait)
    local text = _G.ReadyCheckFrameText
    if text then
        text:ClearAllPoints()
        text:SetPoint("TOP", targetFrame, "TOP", 0, -30)
        text:SetFont(STANDARD_TEXT_FONT, 12, FONT_FLAGS)
        text:SetTextColor(0.9, 0.9, 0.9, 1)
    end

    -- Create custom title (hide Blizzard's, make our own)
    if not frame.quiTitle then
        frame.quiTitle = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.quiTitle:SetPoint("TOP", targetFrame, "TOP", 0, -8)
        frame.quiTitle:SetFont(STANDARD_TEXT_FONT, 13, FONT_FLAGS)
    end
    frame.quiTitle:SetText("Ready Check")
    frame.quiTitle:SetTextColor(sr, sg, sb, 1)  -- Use skin color for title

    -- Hook OnShow to reapply hiding and restore position (Blizzard may reset)
    frame:HookScript("OnShow", function(self)
        HideBlizzardDecorations()
        -- Restore saved position
        local pos = GetReadyCheckPosition()
        if pos then
            self:ClearAllPoints()
            self:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        end
    end)

    -- Make frame movable (only when unlocked)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if self.quiUnlocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if self.quiUnlocked then
            self:StopMovingOrSizing()
            -- Save position
            local point, _, relativePoint, x, y = self:GetPoint()
            SaveReadyCheckPosition(point, nil, relativePoint, x, y)
        end
    end)

    frame.quiSkinned = true
end

---------------------------------------------------------------------------
-- LIVE COLOR REFRESH
---------------------------------------------------------------------------

local function RefreshReadyCheckColors()
    local frame = _G.ReadyCheckFrame
    if not frame or not frame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetSkinColors()

    -- Update main frame backdrop
    if frame.quiBackdrop then
        frame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        frame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update title color
    if frame.quiTitle then
        frame.quiTitle:SetTextColor(sr, sg, sb, 1)
    end

    -- Update buttons
    RefreshButtonColors(_G.ReadyCheckFrameYesButton, sr, sg, sb, bgr, bgg, bgb, bga)
    RefreshButtonColors(_G.ReadyCheckFrameNoButton, sr, sg, sb, bgr, bgg, bgb, bga)
end

-- Expose refresh function globally (required for live preview)
_G.QUI_RefreshReadyCheckColors = RefreshReadyCheckColors

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if _G.ReadyCheckFrame then
            SkinReadyCheckFrame()
        end
    end
end)
