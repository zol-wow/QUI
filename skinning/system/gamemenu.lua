local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- GAME MENU (ESC MENU) SKINNING + QUAZII UI BUTTON
--
-- TAINT SAFETY: GameMenuFrame is a secure frame. In Midnight (12.0+),
-- writing ANY addon property to it or its pool buttons (layoutIndex,
-- quiBackdrop, etc.), creating child frames on it from addon context,
-- or calling AddButton/MarkDirty from addon context taints the secure
-- execution chain. When the user clicks "Edit Mode", the tainted
-- context propagates through SetAttribute → ShowUIPanel → EnterEditMode
-- → TargetUnit() → ADDON_ACTION_FORBIDDEN.
--
-- Solution: ALL visual work uses an overlay container parented to
-- UIParent. ALL state is tracked in local tables. ALL modifications
-- are deferred via C_Timer.After(0) to break the taint chain from
-- InitButtons secure context.
---------------------------------------------------------------------------

-- Static colors
local COLORS = {
    text = { 0.9, 0.9, 0.9, 1 },
}

local FONT_FLAGS = "OUTLINE"

-- Local state (NEVER write to GameMenuFrame or its buttons)
local skinState = { skinned = false }
local buttonOverlays = setmetatable({}, { __mode = "k" }) -- weak-keyed: overlay info per button
local overlayContainer = nil   -- UIParent-child container for all overlays
local menuBackdrop = nil       -- backdrop overlay for GameMenuFrame itself
local quiStandaloneButton = nil -- standalone QUI button (parented to UIParent)

-- Get game menu font size from settings
local function GetGameMenuFontSize()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings.gameMenuFontSize or 12
end

---------------------------------------------------------------------------
-- OVERLAY CONTAINER (parented to UIParent, NOT GameMenuFrame)
---------------------------------------------------------------------------
local function GetOverlayContainer()
    if overlayContainer then return overlayContainer end
    overlayContainer = CreateFrame("Frame", "QUIGameMenuOverlay", UIParent)
    overlayContainer:SetFrameStrata("DIALOG")
    overlayContainer:EnableMouse(false)
    overlayContainer:Hide()
    return overlayContainer
end

---------------------------------------------------------------------------
-- BUTTON OVERLAY (child of overlay container, positioned over button)
---------------------------------------------------------------------------
local function GetOrCreateButtonOverlay(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local info = buttonOverlays[button]
    if info then return info end

    local oc = GetOverlayContainer()
    local overlay = CreateFrame("Frame", nil, oc, "BackdropTemplate")
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 1)
    overlay:EnableMouse(false)

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)

    info = {
        overlay = overlay,
        skinColor = { sr, sg, sb, sa },
        bgColor = { btnBgR, btnBgG, btnBgB, 1 },
    }
    buttonOverlays[button] = info
    return info
end

---------------------------------------------------------------------------
-- STYLE A BUTTON (overlay approach — zero writes to the button itself)
---------------------------------------------------------------------------
local function StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button then return end

    local info = GetOrCreateButtonOverlay(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local overlay = info.overlay

    local px = SkinBase.GetPixelSize(overlay, 1)
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px }
    })

    local btnBgR, btnBgG, btnBgB = info.bgColor[1], info.bgColor[2], info.bgColor[3]
    overlay:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    overlay:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide default textures (these are reads + method calls, not property writes)
    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Center then button.Center:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end

    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local normal = button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local disabled = button:GetDisabledTexture()
    if disabled then disabled:SetAlpha(0) end

    -- Style button text (SetFont on fontstring child is safe)
    local text = button:GetFontString()
    if text then
        local QUI = _G.QUI
        local fontPath = QUI and QUI.GetGlobalFont and QUI:GetGlobalFont() or STANDARD_TEXT_FONT
        local fontSize = GetGameMenuFontSize()
        text:SetFont(fontPath, fontSize, FONT_FLAGS)
        text:SetTextColor(unpack(COLORS.text))
    end

    -- Hover effects — read state from local table, not from button properties
    if not info.hooked then
        info.hooked = true
        button:HookScript("OnEnter", function(self)
            local binfo = buttonOverlays[self]
            if not binfo then return end
            local ov = binfo.overlay
            if ov then
                local r, g, b, a = unpack(binfo.bgColor)
                ov:SetBackdropColor(math.min(r + 0.15, 1), math.min(g + 0.15, 1), math.min(b + 0.15, 1), a)
                local sr2, sg2, sb2, sa2 = unpack(binfo.skinColor)
                ov:SetBackdropBorderColor(math.min(sr2 * 1.4, 1), math.min(sg2 * 1.4, 1), math.min(sb2 * 1.4, 1), sa2)
            end
            local txt = self:GetFontString()
            if txt then txt:SetTextColor(1, 1, 1, 1) end
        end)

        button:HookScript("OnLeave", function(self)
            local binfo = buttonOverlays[self]
            if not binfo then return end
            local ov = binfo.overlay
            if ov then
                ov:SetBackdropColor(unpack(binfo.bgColor))
                ov:SetBackdropBorderColor(unpack(binfo.skinColor))
            end
            local txt = self:GetFontString()
            if txt then txt:SetTextColor(unpack(COLORS.text)) end
        end)
    end
end

-- Update button overlay colors (for live refresh)
local function UpdateButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local info = buttonOverlays[button]
    if not info or not info.overlay then return end

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    info.overlay:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    info.overlay:SetBackdropBorderColor(sr, sg, sb, sa)
    info.skinColor = { sr, sg, sb, sa }
    info.bgColor = { btnBgR, btnBgG, btnBgB, 1 }
end

-- Hide Blizzard decorative elements (method calls, not property writes)
local function HideBlizzardDecorations()
    if GameMenuFrame.Border then GameMenuFrame.Border:Hide() end
    if GameMenuFrame.Header then GameMenuFrame.Header:Hide() end
end

---------------------------------------------------------------------------
-- DIM BACKGROUND FRAME
---------------------------------------------------------------------------
local dimFrame = nil

local function CreateDimFrame()
    if dimFrame then return dimFrame end

    dimFrame = CreateFrame("Frame", "QUIGameMenuDim", UIParent)
    dimFrame:SetAllPoints(UIParent)
    dimFrame:SetFrameStrata("DIALOG")
    dimFrame:SetFrameLevel(0)
    dimFrame:EnableMouse(false)
    dimFrame:Hide()

    dimFrame.overlay = dimFrame:CreateTexture(nil, "BACKGROUND")
    dimFrame.overlay:SetAllPoints()
    dimFrame.overlay:SetColorTexture(0, 0, 0, 0.5)

    return dimFrame
end

local function ShowDimBehindGameMenu()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
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
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general

    if settings and settings.gameMenuDim and GameMenuFrame:IsShown() then
        ShowDimBehindGameMenu()
    else
        HideDimBehindGameMenu()
    end
end

---------------------------------------------------------------------------
-- MENU BACKDROP (child of overlay container, NOT GameMenuFrame)
---------------------------------------------------------------------------
local function CreateMenuBackdrop(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if menuBackdrop then return menuBackdrop end

    local oc = GetOverlayContainer()
    menuBackdrop = CreateFrame("Frame", nil, oc, "BackdropTemplate")
    menuBackdrop:SetAllPoints(GameMenuFrame)
    menuBackdrop:SetFrameLevel(GameMenuFrame:GetFrameLevel())
    menuBackdrop:EnableMouse(false)

    return menuBackdrop
end

local function UpdateMenuBackdrop(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not menuBackdrop then
        CreateMenuBackdrop(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    local px = SkinBase.GetPixelSize(menuBackdrop, 1)
    menuBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = px,
        insets = { left = px, right = px, top = px, bottom = px },
    })
    menuBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    menuBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
end

---------------------------------------------------------------------------
-- MAIN SKINNING (deferred — runs in clean execution context)
---------------------------------------------------------------------------
local function SkinGameMenu()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or not settings.skinGameMenu then return end
    if not GameMenuFrame then return end
    if skinState.skinned then return end

    -- Get colors based on setting
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "gameMenu")

    HideBlizzardDecorations()
    UpdateMenuBackdrop(sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Style all buttons via overlays
    if GameMenuFrame.buttonPool then
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    skinState.skinned = true
end

-- Refresh colors on already-skinned game menu (for live preview)
local function RefreshGameMenuColors()
    if not GameMenuFrame or not skinState.skinned then return end

    -- Get colors based on setting
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "gameMenu")

    if menuBackdrop then
        menuBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        menuBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

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
end

-- Expose refresh functions globally
_G.QUI_RefreshGameMenuColors = RefreshGameMenuColors
_G.QUI_RefreshGameMenuFontSize = RefreshGameMenuFontSize

---------------------------------------------------------------------------
-- QUAZII UI STANDALONE BUTTON (parented to UIParent, NOT GameMenuFrame)
---------------------------------------------------------------------------
local function GetOrCreateStandaloneButton()
    if quiStandaloneButton then return quiStandaloneButton end

    quiStandaloneButton = CreateFrame("Button", "QUIGameMenuButton", UIParent, "UIPanelButtonTemplate")
    quiStandaloneButton:SetText("QUI")
    quiStandaloneButton:SetSize(160, 30)
    quiStandaloneButton:SetFrameStrata("DIALOG")
    quiStandaloneButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        HideUIPanel(GameMenuFrame)
        local QUI = _G.QUI
        if QUI and QUI.GUI then
            QUI.GUI:Show()
        end
    end)
    quiStandaloneButton:Hide()

    return quiStandaloneButton
end

-- Position the standalone QUI button below the last GameMenuFrame button
local function PositionStandaloneButton()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or settings.addQUIButton == false then
        if quiStandaloneButton then quiStandaloneButton:Hide() end
        return
    end

    if not GameMenuFrame or not GameMenuFrame.buttonPool then return end

    local btn = GetOrCreateStandaloneButton()

    -- Find the Macros button to position after
    local macrosButton = nil
    for button in GameMenuFrame.buttonPool:EnumerateActive() do
        if button:GetText() == MACROS then
            macrosButton = button
            break
        end
    end

    if macrosButton then
        btn:ClearAllPoints()
        btn:SetPoint("TOP", macrosButton, "BOTTOM", 0, -2)
        btn:SetWidth(macrosButton:GetWidth())
        btn:SetHeight(macrosButton:GetHeight())
        btn:SetFrameLevel(GameMenuFrame:GetFrameLevel() + 10)
        btn:Show()
    else
        -- Fallback: position at bottom of frame
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOM", GameMenuFrame, "BOTTOM", 0, 15)
        btn:SetFrameLevel(GameMenuFrame:GetFrameLevel() + 10)
        btn:Show()
    end

    -- Style it if skinning is active
    if skinState.skinned then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
        StyleButton(btn, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

-- Hook into GameMenuFrame button initialization (with defensive check)
if GameMenuFrame and GameMenuFrame.InitButtons then
    hooksecurefunc(GameMenuFrame, "InitButtons", function()
        -- CRITICAL: Defer ALL work to break the taint chain.
        -- InitButtons runs in Blizzard's secure context. Any addon code
        -- that runs synchronously here (even reading pool buttons) can
        -- taint the execution context and propagate to Edit Mode.
        C_Timer.After(0, function()
            if not GameMenuFrame:IsShown() then return end

            -- Position standalone QUI button (no AddButton, no layoutIndex writes)
            PositionStandaloneButton()

            -- Skin menu if enabled
            SkinGameMenu()

            -- Style any new buttons
            if skinState.skinned and GameMenuFrame.buttonPool then
                local core = GetCore()
                local settings = core and core.db and core.db.profile and core.db.profile.general
                local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "gameMenu")
                for button in GameMenuFrame.buttonPool:EnumerateActive() do
                    if not buttonOverlays[button] then
                        StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                    end
                end
            end
        end)
    end)

    -- Hook Show/Hide for dim effect and overlay visibility
    -- CRITICAL: Defer ALL work in OnShow/OnHide. These hooks run synchronously
    -- in GameMenuFrame's secure execution context. Any operation that reads
    -- from GameMenuFrame (e.g. GetFrameLevel()) taints the context, which
    -- then propagates to Edit Mode → TargetUnit/UpdateHealthColor errors.
    GameMenuFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if not GameMenuFrame:IsShown() then return end

            ShowDimBehindGameMenu()

            local oc = GetOverlayContainer()
            oc:Show()

            PositionStandaloneButton()

            if not skinState.skinned then return end
            if not GameMenuFrame.buttonPool then return end

            local core = GetCore()
            local settings = core and core.db and core.db.profile and core.db.profile.general
            local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "gameMenu")
            for button in GameMenuFrame.buttonPool:EnumerateActive() do
                if not buttonOverlays[button] then
                    StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end
        end)
    end)
    GameMenuFrame:HookScript("OnHide", function()
        C_Timer.After(0, function()
            HideDimBehindGameMenu()

            local oc = GetOverlayContainer()
            oc:Hide()

            if quiStandaloneButton then
                quiStandaloneButton:Hide()
            end
        end)
    end)
end
