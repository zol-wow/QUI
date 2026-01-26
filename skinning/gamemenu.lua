local addonName, ns = ...

---------------------------------------------------------------------------
-- GAME MENU (ESC MENU) SKINNING + QUAZII UI BUTTON
---------------------------------------------------------------------------

-- Static colors
local COLORS = {
    text = { 0.9, 0.9, 0.9, 1 },
}

local FONT_FLAGS = "OUTLINE"

-- Get game menu font size from settings
local function GetGameMenuFontSize()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    return settings and settings.gameMenuFontSize or 12
end

-- Get skinning colors (uses unified color system)
local function GetGameMenuColors()
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

-- Create a styled backdrop for frames
local function CreateQUIBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame.quiBackdrop then
        frame.quiBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.quiBackdrop:SetAllPoints()
        frame.quiBackdrop:SetFrameLevel(frame:GetFrameLevel())
        frame.quiBackdrop:EnableMouse(false)
    end

    frame.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    frame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Style a button with QUI theme
local function StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button then return end

    -- Create backdrop if needed
    if not button.quiBackdrop then
        button.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.quiBackdrop:SetAllPoints()
        button.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
        button.quiBackdrop:EnableMouse(false)
    end

    button.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    -- Button bg slightly lighter than main bg
    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide default textures
    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Center then button.Center:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end

    -- Hide highlight/pushed/normal/disabled textures
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local normal = button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local disabled = button:GetDisabledTexture()
    if disabled then disabled:SetAlpha(0) end

    -- Style button text
    local text = button:GetFontString()
    if text then
        local QUI = _G.QUI
        local fontPath = QUI and QUI.GetGlobalFont and QUI:GetGlobalFont() or STANDARD_TEXT_FONT
        local fontSize = GetGameMenuFontSize()
        text:SetFont(fontPath, fontSize, FONT_FLAGS)
        text:SetTextColor(unpack(COLORS.text))
    end

    -- Store colors for hover effects
    button.quiSkinColor = { sr, sg, sb, sa }
    button.quiBgColor = { btnBgR, btnBgG, btnBgB, 1 }

    -- Set hover scripts directly (game menu buttons don't need original handlers)
    button:SetScript("OnEnter", function(self)
        if self.quiBackdrop then
            if self.quiBgColor then
                local r, g, b, a = unpack(self.quiBgColor)
                self.quiBackdrop:SetBackdropColor(math.min(r + 0.15, 1), math.min(g + 0.15, 1), math.min(b + 0.15, 1), a)
            end
            if self.quiSkinColor then
                local r, g, b, a = unpack(self.quiSkinColor)
                self.quiBackdrop:SetBackdropBorderColor(math.min(r * 1.4, 1), math.min(g * 1.4, 1), math.min(b * 1.4, 1), a)
            end
        end
        local txt = self:GetFontString()
        if txt then txt:SetTextColor(1, 1, 1, 1) end
    end)

    button:SetScript("OnLeave", function(self)
        if self.quiBackdrop then
            if self.quiBgColor then
                self.quiBackdrop:SetBackdropColor(unpack(self.quiBgColor))
            end
            if self.quiSkinColor then
                self.quiBackdrop:SetBackdropBorderColor(unpack(self.quiSkinColor))
            end
        end
        local txt = self:GetFontString()
        if txt then txt:SetTextColor(unpack(COLORS.text)) end
    end)

    button.quiStyled = true
end

-- Update button colors (for live refresh)
local function UpdateButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or not button.quiBackdrop then return end

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    button.quiSkinColor = { sr, sg, sb, sa }
    button.quiBgColor = { btnBgR, btnBgG, btnBgB, 1 }
end

-- Hide Blizzard decorative elements
local function HideBlizzardDecorations()
    if GameMenuFrame.Border then GameMenuFrame.Border:Hide() end
    if GameMenuFrame.Header then GameMenuFrame.Header:Hide() end
end

-- Dim background frame
local dimFrame = nil

local function CreateDimFrame()
    if dimFrame then return dimFrame end

    dimFrame = CreateFrame("Frame", "QUIGameMenuDim", UIParent)
    dimFrame:SetAllPoints(UIParent)
    dimFrame:SetFrameStrata("DIALOG")
    dimFrame:SetFrameLevel(0)
    dimFrame:EnableMouse(false)  -- Don't capture mouse events
    dimFrame:Hide()

    -- Dark overlay texture
    dimFrame.overlay = dimFrame:CreateTexture(nil, "BACKGROUND")
    dimFrame.overlay:SetAllPoints()
    dimFrame.overlay:SetColorTexture(0, 0, 0, 0.5)

    return dimFrame
end

local function ShowDimBehindGameMenu()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinGameMenu or not settings.gameMenuDim then return end

    local dim = CreateDimFrame()
    dim:SetFrameStrata("DIALOG")
    dim:SetFrameLevel(GameMenuFrame:GetFrameLevel() - 1)
    dim:Show()
end

local function HideDimBehindGameMenu()
    if dimFrame then
        dimFrame:Hide()
    end
end

-- Expose for settings toggle
_G.QUI_RefreshGameMenuDim = function()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general

    if settings and settings.gameMenuDim and GameMenuFrame:IsShown() then
        ShowDimBehindGameMenu()
    else
        HideDimBehindGameMenu()
    end
end

-- Main skinning function
local function SkinGameMenu()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinGameMenu then return end

    if not GameMenuFrame then return end
    if GameMenuFrame.quiSkinned then return end

    -- Get colors based on setting
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetGameMenuColors()

    -- Hide Blizzard decorations
    HideBlizzardDecorations()

    -- Create backdrop
    CreateQUIBackdrop(GameMenuFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Adjust frame padding for cleaner look
    GameMenuFrame.topPadding = 15
    GameMenuFrame.bottomPadding = 15
    GameMenuFrame.leftPadding = 15
    GameMenuFrame.rightPadding = 15
    GameMenuFrame.spacing = 2

    -- Style all buttons in the pool
    if GameMenuFrame.buttonPool then
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    GameMenuFrame:MarkDirty()
    GameMenuFrame.quiSkinned = true
end

-- Refresh colors on already-skinned game menu (for live preview)
local function RefreshGameMenuColors()
    if not GameMenuFrame or not GameMenuFrame.quiSkinned then return end

    -- Get colors based on setting
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetGameMenuColors()

    -- Update main frame backdrop
    if GameMenuFrame.quiBackdrop then
        GameMenuFrame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        GameMenuFrame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update all buttons
    if GameMenuFrame.buttonPool then
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            UpdateButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end
end

-- Refresh font size on game menu buttons
local function RefreshGameMenuFontSize()
    if not GameMenuFrame then return end

    local fontSize = GetGameMenuFontSize()
    local QUI = _G.QUI
    local fontPath = QUI and QUI.GetGlobalFont and QUI:GetGlobalFont() or STANDARD_TEXT_FONT

    if GameMenuFrame.buttonPool then
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            local text = button:GetFontString()
            if text then
                text:SetFont(fontPath, fontSize, FONT_FLAGS)
            end
        end
    end

    -- Mark dirty to recalculate layout if needed
    if GameMenuFrame.MarkDirty then
        GameMenuFrame:MarkDirty()
    end
end

-- Expose refresh functions globally
_G.QUI_RefreshGameMenuColors = RefreshGameMenuColors
_G.QUI_RefreshGameMenuFontSize = RefreshGameMenuFontSize

---------------------------------------------------------------------------
-- QUAZII UI BUTTON INJECTION
---------------------------------------------------------------------------

-- Inject button on every InitButtons call (buttonPool gets reset each time)
local function InjectQUIButton()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or settings.addQUIButton == false then return end

    if not GameMenuFrame or not GameMenuFrame.buttonPool then return end

    -- Find the Macros button to insert after
    local macrosIndex = nil
    for button in GameMenuFrame.buttonPool:EnumerateActive() do
        if button:GetText() == MACROS then
            macrosIndex = button.layoutIndex
            break
        end
    end

    if macrosIndex then
        -- Shift buttons after Macros down by 1
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            if button.layoutIndex and button.layoutIndex > macrosIndex then
                button.layoutIndex = button.layoutIndex + 1
            end
        end

        -- Add QUI button
        local quiButton = GameMenuFrame:AddButton("QUI", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
            HideUIPanel(GameMenuFrame)
            local QUI = _G.QUI
            if QUI and QUI.GUI then
                QUI.GUI:Show()
            end
        end)
        quiButton.layoutIndex = macrosIndex + 1
        GameMenuFrame:MarkDirty()
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

-- Hook into GameMenuFrame button initialization (with defensive check)
if GameMenuFrame and GameMenuFrame.InitButtons then
    hooksecurefunc(GameMenuFrame, "InitButtons", function()
        -- Inject QUI button (always, regardless of skinning setting)
        InjectQUIButton()

        -- Skin menu if enabled (defer to ensure buttons are ready)
        C_Timer.After(0, function()
            SkinGameMenu()

            -- Style any new buttons that were added
            if GameMenuFrame.quiSkinned and GameMenuFrame.buttonPool then
                local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetGameMenuColors()

                for button in GameMenuFrame.buttonPool:EnumerateActive() do
                    if not button.quiStyled then
                        StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                    end
                end
            end
        end)
    end)

    -- Hook Show/Hide for dim effect and button re-styling
    GameMenuFrame:HookScript("OnShow", function()
        ShowDimBehindGameMenu()

        -- Defer button styling to ensure InitButtons has completed
        C_Timer.After(0, function()
            if not GameMenuFrame:IsShown() then return end
            if not GameMenuFrame.quiSkinned or not GameMenuFrame.buttonPool then return end

            local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetGameMenuColors()
            for button in GameMenuFrame.buttonPool:EnumerateActive() do
                -- Force full re-styling every time (hooks may be lost on pool recycle)
                button.quiStyled = nil
                StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end)
    end)
    GameMenuFrame:HookScript("OnHide", function()
        HideDimBehindGameMenu()
    end)
end
