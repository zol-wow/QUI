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

    -- Hover effects via IsMouseOver() polling on the overlay.
    -- HookScript on secure pool buttons doesn't fire reliably in Midnight
    -- 12.0+, so we poll the overlay's bounds instead.  The overlay keeps
    -- EnableMouse(false) so clicks pass through to the button underneath.
    -- OnUpdate only runs while overlayContainer is shown (menu open).
    if not info.hoverSetup then
        info.hoverSetup = true
        info.hovered = false
        overlay:SetScript("OnUpdate", function(self)
            local binfo = buttonOverlays[button]
            if not binfo then return end

            if self:IsMouseOver() then
                if not binfo.hovered then
                    binfo.hovered = true
                    local r, g, b, a = unpack(binfo.bgColor)
                    self:SetBackdropColor(math.min(r + 0.30, 1), math.min(g + 0.30, 1), math.min(b + 0.30, 1), a)
                    local sr2, sg2, sb2, sa2 = unpack(binfo.skinColor)
                    self:SetBackdropBorderColor(math.min(sr2 * 1.6, 1), math.min(sg2 * 1.6, 1), math.min(sb2 * 1.6, 1), sa2)
                    local txt = button:GetFontString()
                    if txt then txt:SetTextColor(1, 1, 1, 1) end
                    if binfo.overlayText then binfo.overlayText:SetTextColor(1, 1, 1, 1) end
                end
            else
                if binfo.hovered then
                    binfo.hovered = false
                    self:SetBackdropColor(unpack(binfo.bgColor))
                    self:SetBackdropBorderColor(unpack(binfo.skinColor))
                    local txt = button:GetFontString()
                    if txt then txt:SetTextColor(unpack(COLORS.text)) end
                    if binfo.overlayText then binfo.overlayText:SetTextColor(unpack(COLORS.text)) end
                end
            end
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

    -- Also refresh the QUI standalone button overlay
    if quiStandaloneButton then
        UpdateButtonColors(quiStandaloneButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
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

    -- Also refresh the QUI standalone button overlay text
    if quiStandaloneButton then
        local info = buttonOverlays[quiStandaloneButton]
        if info and info.overlayText then
            info.overlayText:SetFont(fontPath, fontSize, FONT_FLAGS)
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

-- Position the standalone QUI button below the bottom-most GameMenuFrame button.
-- We cannot insert into Blizzard's layout (taint), so we place our button below
-- the last pool button and extend the menu backdrop to cover it.
local function PositionStandaloneButton()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or settings.addQUIButton == false then
        if quiStandaloneButton then quiStandaloneButton:Hide() end
        -- Restore backdrop to default (covers GameMenuFrame only)
        if menuBackdrop then
            menuBackdrop:ClearAllPoints()
            menuBackdrop:SetAllPoints(GameMenuFrame)
        end
        return
    end

    if not GameMenuFrame or not GameMenuFrame.buttonPool then return end

    local btn = GetOrCreateStandaloneButton()

    -- Anchor to GameMenuFrame's BOTTOM edge so the QUI button is entirely
    -- outside the secure frame's rectangle.  GameMenuFrame has padding below
    -- its last pool button; if we anchor to the pool button, the top portion
    -- of our button lands inside GameMenuFrame's bounds and the secure frame
    -- eats the mouse events (only the bottom half would be clickable).
    -- We still read a pool button for width/height reference.
    local refButton = nil
    for button in GameMenuFrame.buttonPool:EnumerateActive() do
        refButton = button
        break
    end

    btn:ClearAllPoints()
    btn:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -2)
    if refButton then
        btn:SetWidth(refButton:GetWidth())
        btn:SetHeight(refButton:GetHeight())
    end
    btn:SetFrameLevel(GameMenuFrame:GetFrameLevel() + 10)
    btn:Show()

    -- Style the QUI button when game menu skinning is enabled.
    -- Check settings directly (not skinState.skinned) so this works
    -- regardless of whether SkinGameMenu() has run yet.
    local core2 = GetCore()
    local stg2 = core2 and core2.db and core2.db.profile and core2.db.profile.general
    if stg2 and stg2.skinGameMenu then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(stg2, "gameMenu")
        StyleButton(btn, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        -- Ensure the "QUI" text renders above the overlay backdrop.
        -- The overlay sits at button level+1, which can hide the button's
        -- own FontString.  Mirror the text on the overlay so it's always visible.
        local info = buttonOverlays[btn]
        if info and info.overlay then
            if not info.overlayText then
                local ot = info.overlay:CreateFontString(nil, "OVERLAY")
                ot:SetPoint("CENTER")
                ot:SetJustifyH("CENTER")
                ot:SetJustifyV("MIDDLE")
                info.overlayText = ot
            end
            local QUI2 = _G.QUI
            local fp = QUI2 and QUI2.GetGlobalFont and QUI2:GetGlobalFont() or STANDARD_TEXT_FONT
            local fs = GetGameMenuFontSize()
            info.overlayText:SetFont(fp, fs, FONT_FLAGS)
            info.overlayText:SetText("QUI")
            info.overlayText:SetTextColor(unpack(COLORS.text))
            -- Hide the original button text so it doesn't double-render
            local origText = btn:GetFontString()
            if origText then origText:SetAlpha(0) end

            -- Keep overlay EnableMouse(false) (the default) so mouse events
            -- pass through to the QUI button underneath — exactly like pool
            -- buttons.  The button's HookScript (set by StyleButton) handles
            -- hover highlights, and its OnClick handles the click.
            info.overlay:EnableMouse(false)
        end
    end

    -- Extend the menu backdrop to cover the QUI button.
    -- Deferred by one frame so GetBottom() returns the resolved position.
    if menuBackdrop then
        C_Timer.After(0, function()
            if not quiStandaloneButton or not quiStandaloneButton:IsShown() then
                if menuBackdrop then
                    menuBackdrop:ClearAllPoints()
                    menuBackdrop:SetAllPoints(GameMenuFrame)
                end
                return
            end
            local gmBottom = GameMenuFrame:GetBottom()
            local btnBottom = quiStandaloneButton:GetBottom()
            if gmBottom and btnBottom and btnBottom < gmBottom then
                local extend = gmBottom - btnBottom + 12 -- 12px padding below button
                menuBackdrop:ClearAllPoints()
                menuBackdrop:SetPoint("TOPLEFT", GameMenuFrame, "TOPLEFT")
                menuBackdrop:SetPoint("TOPRIGHT", GameMenuFrame, "TOPRIGHT")
                menuBackdrop:SetPoint("BOTTOMLEFT", GameMenuFrame, "BOTTOMLEFT", 0, -extend)
                menuBackdrop:SetPoint("BOTTOMRIGHT", GameMenuFrame, "BOTTOMRIGHT", 0, -extend)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

-- TAINT SAFETY: NEVER hook GameMenuFrame directly (HookScript, hooksecurefunc).
-- Even deferred callbacks (C_Timer.After(0) inside the hook) still execute addon
-- code in GameMenuFrame's secure context, tainting the execution chain. When the
-- user then clicks "Edit Mode", the tainted context propagates through:
--   SetAttribute → ShowUIPanel → EnterEditMode → TargetUnit() → ADDON_ACTION_FORBIDDEN
--
-- Instead, use a visibility watcher frame that polls GameMenuFrame:IsShown()
-- without any hooks on the secure frame itself.
if GameMenuFrame then
    local gameMenuWatcher = CreateFrame("Frame", nil, UIParent)
    local wasShown = false
    local lastButtonCount = 0

    gameMenuWatcher:SetScript("OnUpdate", function()
        local isShown = GameMenuFrame:IsShown()

        if isShown and not wasShown then
            -- GameMenuFrame just became visible
            wasShown = true

            ShowDimBehindGameMenu()

            local oc = GetOverlayContainer()
            oc:Show()

            -- Skin pool buttons first so skinState.skinned is true when
            -- PositionStandaloneButton styles the QUI button.
            SkinGameMenu()
            PositionStandaloneButton()

            if skinState.skinned and GameMenuFrame.buttonPool then
                local count = 0
                local core = GetCore()
                local stg = core and core.db and core.db.profile and core.db.profile.general
                local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(stg, "gameMenu")
                for button in GameMenuFrame.buttonPool:EnumerateActive() do
                    count = count + 1
                    if not buttonOverlays[button] then
                        StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                    end
                end
                lastButtonCount = count
            end
        elseif isShown then
            -- Already showing — check if buttons changed (InitButtons was called)
            local count = 0
            if GameMenuFrame.buttonPool then
                for _ in GameMenuFrame.buttonPool:EnumerateActive() do
                    count = count + 1
                end
            end
            if count ~= lastButtonCount then
                lastButtonCount = count
                SkinGameMenu()
                PositionStandaloneButton()
                if skinState.skinned and GameMenuFrame.buttonPool then
                    local core3 = GetCore()
                    local stg3 = core3 and core3.db and core3.db.profile and core3.db.profile.general
                    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(stg3, "gameMenu")
                    for button in GameMenuFrame.buttonPool:EnumerateActive() do
                        if not buttonOverlays[button] then
                            StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                        end
                    end
                end
            end
        elseif wasShown then
            -- GameMenuFrame just became hidden
            wasShown = false
            lastButtonCount = 0

            HideDimBehindGameMenu()

            local oc = GetOverlayContainer()
            oc:Hide()

            if quiStandaloneButton then
                quiStandaloneButton:Hide()
            end

            -- Reset backdrop to default size (no QUI button extension)
            if menuBackdrop then
                menuBackdrop:ClearAllPoints()
                menuBackdrop:SetAllPoints(GameMenuFrame)
            end
        end
    end)
end
