local addonName, ns = ...

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
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
local OVERLAY_LEVEL_OFFSET = 50
local BUTTON_OVERLAY_LEVEL_OFFSET = OVERLAY_LEVEL_OFFSET + 5
local BUTTON_OVERLAY_PADDING = 1
local BUTTON_OVERLAY_STRATA = "TOOLTIP"
local BUTTON_OVERLAY_BASE_LEVEL = 9000
local MAX_FRAME_LEVEL = 10000
local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8x8"

-- Local state (NEVER write to GameMenuFrame or its buttons)
local skinState = { skinned = false }
local buttonOverlays = Helpers.CreateStateTable() -- weak-keyed: overlay info per button
local overlayContainer = nil   -- UIParent-child container for all overlays
local menuBackdrop = nil       -- backdrop overlay for GameMenuFrame itself
local quiStandaloneButton = nil -- standalone QUI button (parented to UIParent)
local editModeButton = nil      -- standalone Edit Mode button (parented to UIParent)

local function IsLockedDown()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

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

local function GetFrameLevel(frame, fallback)
    if frame and frame.GetFrameLevel then
        local level = frame:GetFrameLevel()
        if type(level) == "number" then
            return level
        end
    end
    return fallback or 0
end

local function SyncOverlayContainerLevel()
    local oc = GetOverlayContainer()
    if not GameMenuFrame then return oc end

    if GameMenuFrame.GetFrameStrata and oc.SetFrameStrata then
        local strata = GameMenuFrame:GetFrameStrata()
        if type(strata) == "string" and strata ~= "" then
            oc:SetFrameStrata(strata)
        end
    end

    if oc.SetFrameLevel then
        oc:SetFrameLevel(GetFrameLevel(GameMenuFrame, 0) + OVERLAY_LEVEL_OFFSET)
    end

    return oc
end

local function GetOverlayFrameLevel(button)
    local buttonLevel = GetFrameLevel(button, 0)
    return math.min(MAX_FRAME_LEVEL, math.max(BUTTON_OVERLAY_BASE_LEVEL, buttonLevel + BUTTON_OVERLAY_LEVEL_OFFSET))
end

local function SyncButtonOverlayLayering(overlay, button)
    if not overlay then return end
    if overlay.SetFrameStrata then
        overlay:SetFrameStrata(BUTTON_OVERLAY_STRATA)
    end
    if overlay.SetFrameLevel then
        overlay:SetFrameLevel(GetOverlayFrameLevel(button))
    end
end

local function AnchorButtonOverlay(overlay, button)
    if not overlay or not button then return end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", -BUTTON_OVERLAY_PADDING, BUTTON_OVERLAY_PADDING)
    overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", BUTTON_OVERLAY_PADDING, -BUTTON_OVERLAY_PADDING)
end

---------------------------------------------------------------------------
-- BUTTON OVERLAY (child of overlay container, positioned over button)
---------------------------------------------------------------------------
local function GetOrCreateButtonOverlay(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local oc = SyncOverlayContainerLevel()
    local info = buttonOverlays[button]
    if info then
        if info.overlay then
            AnchorButtonOverlay(info.overlay, button)
            SyncButtonOverlayLayering(info.overlay, button)
            info.overlay:Show()
        end
        return info
    end

    local overlay = CreateFrame("Frame", nil, oc, "BackdropTemplate")
    AnchorButtonOverlay(overlay, button)
    SyncButtonOverlayLayering(overlay, button)
    overlay:EnableMouse(false)

    local btnBgR = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgG = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgB = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)

    info = {
        overlay = overlay,
        skinColor = { sr, sg, sb, sa },
        bgColor = { btnBgR, btnBgG, btnBgB, 1 },
    }
    buttonOverlays[button] = info
    return info
end

local function GetPixelSize(frame)
    if SkinBase and SkinBase.GetPixelSize then
        return SkinBase.GetPixelSize(frame, 1)
    end
    return 1
end

local function EnsureButtonOverlayTextures(info)
    local overlay = info and info.overlay
    if not overlay then return end

    if not overlay.coverTexture then
        overlay.coverTexture = overlay:CreateTexture(nil, "OVERLAY")
        overlay.coverTexture:SetTexture(SOLID_TEXTURE)
    end
    if overlay.coverTexture.SetDrawLayer then
        overlay.coverTexture:SetDrawLayer("OVERLAY", 0)
    end
    overlay.coverTexture:ClearAllPoints()
    overlay.coverTexture:SetAllPoints(overlay)

    if not overlay.borderTop then
        overlay.borderTop = overlay:CreateTexture(nil, "OVERLAY")
        overlay.borderBottom = overlay:CreateTexture(nil, "OVERLAY")
        overlay.borderLeft = overlay:CreateTexture(nil, "OVERLAY")
        overlay.borderRight = overlay:CreateTexture(nil, "OVERLAY")
        overlay.borderTop:SetTexture(SOLID_TEXTURE)
        overlay.borderBottom:SetTexture(SOLID_TEXTURE)
        overlay.borderLeft:SetTexture(SOLID_TEXTURE)
        overlay.borderRight:SetTexture(SOLID_TEXTURE)
    end
    if overlay.borderTop.SetDrawLayer then
        overlay.borderTop:SetDrawLayer("OVERLAY", 1)
        overlay.borderBottom:SetDrawLayer("OVERLAY", 1)
        overlay.borderLeft:SetDrawLayer("OVERLAY", 1)
        overlay.borderRight:SetDrawLayer("OVERLAY", 1)
    end

    local px = GetPixelSize(overlay)

    overlay.borderTop:ClearAllPoints()
    overlay.borderTop:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    overlay.borderTop:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
    overlay.borderTop:SetHeight(px)

    overlay.borderBottom:ClearAllPoints()
    overlay.borderBottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, 0)
    overlay.borderBottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    overlay.borderBottom:SetHeight(px)

    overlay.borderLeft:ClearAllPoints()
    overlay.borderLeft:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, -px)
    overlay.borderLeft:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, px)
    overlay.borderLeft:SetWidth(px)

    overlay.borderRight:ClearAllPoints()
    overlay.borderRight:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, -px)
    overlay.borderRight:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, px)
    overlay.borderRight:SetWidth(px)
end

local function SetButtonOverlayColors(info, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    local overlay = info and info.overlay
    if not overlay then return end
    EnsureButtonOverlayTextures(info)

    overlay.coverTexture:SetColorTexture(bgR, bgG, bgB, bgA)
    overlay.borderTop:SetColorTexture(borderR, borderG, borderB, borderA)
    overlay.borderBottom:SetColorTexture(borderR, borderG, borderB, borderA)
    overlay.borderLeft:SetColorTexture(borderR, borderG, borderB, borderA)
    overlay.borderRight:SetColorTexture(borderR, borderG, borderB, borderA)
end

local function RefreshButtonOverlayVisuals(info)
    if not info then return end
    local r, g, b, a = unpack(info.bgColor)
    local sr, sg, sb, sa = unpack(info.skinColor)

    if info.hovered then
        SetButtonOverlayColors(
            info,
            math.min(r + 0.30, 1), math.min(g + 0.30, 1), math.min(b + 0.30, 1), a,
            math.min(sr * 1.6, 1), math.min(sg * 1.6, 1), math.min(sb * 1.6, 1), sa
        )
        if info.overlayText then info.overlayText:SetTextColor(1, 1, 1, 1) end
    else
        SetButtonOverlayColors(info, r, g, b, a, sr, sg, sb, sa)
        if info.overlayText then info.overlayText:SetTextColor(unpack(COLORS.text)) end
    end
end

local function GetButtonText(button, fallback)
    if fallback then return fallback end
    if button and button.GetText then
        local text = button:GetText()
        if type(text) == "string" and text ~= "" then
            return text
        end
    end
    local fontString = button and button.GetFontString and button:GetFontString()
    if fontString and fontString.GetText then
        local text = fontString:GetText()
        if type(text) == "string" and text ~= "" then
            return text
        end
    end
    return ""
end

local function UpdateOverlayText(info, label)
    if not info or not info.overlay then return end
    if not info.overlayText then
        local text = info.overlay:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        info.overlayText = text
    end
    if info.overlayText.SetDrawLayer then
        info.overlayText:SetDrawLayer("OVERLAY", 2)
    end

    local fontPath = Helpers.GetGeneralFont()
    local fontSize = GetGameMenuFontSize()
    info.overlayText:SetFont(fontPath, fontSize, FONT_FLAGS)
    info.overlayText:SetText(label or "")
    info.overlayText:SetTextColor(unpack(COLORS.text))
end

local function ApplyOverlayHover(info, hovered)
    if not info or not info.overlay or info.hovered == hovered then return end
    info.hovered = hovered
    RefreshButtonOverlayVisuals(info)
end

local function UpdateButtonHover(button)
    local info = buttonOverlays[button]
    if not info then return end
    local hovered = button and button.IsMouseOver and button:IsMouseOver() or false
    ApplyOverlayHover(info, hovered)
end

local function UpdateVisibleButtonHovers()
    if GameMenuFrame and GameMenuFrame.buttonPool then
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            UpdateButtonHover(button)
        end
    end
    if quiStandaloneButton and quiStandaloneButton:IsShown() then
        UpdateButtonHover(quiStandaloneButton)
    end
    if editModeButton and editModeButton:IsShown() then
        UpdateButtonHover(editModeButton)
    end
end

---------------------------------------------------------------------------
-- STYLE A BUTTON (overlay approach — zero writes to the button itself)
---------------------------------------------------------------------------
local function StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga, label)
    if not button then return end

    local info = GetOrCreateButtonOverlay(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local overlay = info.overlay

    local btnBgR, btnBgG, btnBgB = info.bgColor[1], info.bgColor[2], info.bgColor[3]
    SetButtonOverlayColors(info, btnBgR, btnBgG, btnBgB, 1, sr, sg, sb, sa)
    UpdateOverlayText(info, GetButtonText(button, label))
    UpdateButtonHover(button)
end

-- Update button overlay colors (for live refresh)
local function UpdateButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local info = buttonOverlays[button]
    if not info or not info.overlay then return end

    local btnBgR = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgG = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgB = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
    info.skinColor = { sr, sg, sb, sa }
    info.bgColor = { btnBgR, btnBgG, btnBgB, 1 }
    RefreshButtonOverlayVisuals(info)
end

-- Hide Blizzard decorative elements (method calls, not property writes)
local function HideBlizzardDecorations()
    if IsLockedDown() then return end
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

    local oc = SyncOverlayContainerLevel()
    menuBackdrop = CreateFrame("Frame", nil, oc, "BackdropTemplate")
    menuBackdrop:SetAllPoints(GameMenuFrame)
    menuBackdrop:SetFrameLevel(math.max(GetFrameLevel(oc, 0) + 1, GetFrameLevel(GameMenuFrame, 0) + 1))
    menuBackdrop:EnableMouse(false)

    return menuBackdrop
end

local function UpdateMenuBackdrop(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not menuBackdrop then
        CreateMenuBackdrop(sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    SkinBase.ApplyFullBackdrop(menuBackdrop, sr, sg, sb, sa, bgr, bgg, bgb, bga)
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

    SkinBase.SkinFrameText(GameMenuFrame, { recurse = true })
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

    -- Also refresh the Edit Mode button overlay
    if editModeButton then
        UpdateButtonColors(editModeButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
end

-- Refresh font size on game menu buttons
local function RefreshGameMenuFontSize()
    if not GameMenuFrame then return end

    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or not settings.skinGameMenu then
        if core and core.ApplyGlobalFontToGameMenu then
            core:ApplyGlobalFontToGameMenu()
        end
        return
    end

    local fontSize = GetGameMenuFontSize()
    local fontPath = Helpers.GetGeneralFont()

    if GameMenuFrame.buttonPool then
        for button in GameMenuFrame.buttonPool:EnumerateActive() do
            local info = buttonOverlays[button]
            if info and info.overlayText then
                info.overlayText:SetFont(fontPath, fontSize, FONT_FLAGS)
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

    -- Also refresh the Edit Mode button overlay text
    if editModeButton then
        local info = buttonOverlays[editModeButton]
        if info and info.overlayText then
            info.overlayText:SetFont(fontPath, fontSize, FONT_FLAGS)
        end
    end
end

-- Expose refresh functions globally
_G.QUI_RefreshGameMenuColors = RefreshGameMenuColors
_G.QUI_RefreshGameMenuFontSize = RefreshGameMenuFontSize

if ns.Registry then
    ns.Registry:Register("skinGameMenu", {
        refresh = _G.QUI_RefreshGameMenuColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
    ns.Registry:Register("skinGameMenuFonts", {
        refresh = _G.QUI_RefreshGameMenuFontSize,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

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
        if QUI and QUI.ShowOptions then
            QUI:ShowOptions()
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
        if quiStandaloneButton then
            quiStandaloneButton:Hide()
            local info = buttonOverlays[quiStandaloneButton]
            if info and info.overlay then info.overlay:Hide() end
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
        StyleButton(btn, sr, sg, sb, sa, bgr, bgg, bgb, bga, "QUI")
    end

end

---------------------------------------------------------------------------
-- EDIT MODE STANDALONE BUTTON (parented to UIParent, NOT GameMenuFrame)
---------------------------------------------------------------------------
local function GetOrCreateEditModeButton()
    if editModeButton then return editModeButton end

    editModeButton = CreateFrame("Button", "QUIGameMenuEditModeButton", UIParent, "UIPanelButtonTemplate")
    editModeButton:SetText("QUI Edit Mode")
    editModeButton:SetSize(160, 30)
    editModeButton:SetFrameStrata("DIALOG")
    editModeButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        HideUIPanel(GameMenuFrame)
        if _G.QUI_ToggleLayoutMode then
            _G.QUI_ToggleLayoutMode()
        end
    end)
    editModeButton:Hide()

    return editModeButton
end

-- Position the Edit Mode button below the QUI button (if visible) or below GameMenuFrame.
local function PositionEditModeButton()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or settings.addEditModeButton == false then
        if editModeButton then
            editModeButton:Hide()
            local info = buttonOverlays[editModeButton]
            if info and info.overlay then info.overlay:Hide() end
        end
        return
    end

    if not GameMenuFrame or not GameMenuFrame.buttonPool then return end

    local btn = GetOrCreateEditModeButton()

    -- Anchor below the QUI button if it's visible, otherwise below GameMenuFrame
    local anchor = (quiStandaloneButton and quiStandaloneButton:IsShown()) and quiStandaloneButton or GameMenuFrame

    btn:ClearAllPoints()
    btn:SetPoint("TOP", anchor, "BOTTOM", 0, -2)

    -- Match button size to pool buttons
    local refButton = nil
    for button in GameMenuFrame.buttonPool:EnumerateActive() do
        refButton = button
        break
    end
    if refButton then
        btn:SetWidth(refButton:GetWidth())
        btn:SetHeight(refButton:GetHeight())
    end
    btn:SetFrameLevel(GameMenuFrame:GetFrameLevel() + 10)
    btn:Show()

    -- Style the Edit Mode button when game menu skinning is enabled
    local core2 = GetCore()
    local stg2 = core2 and core2.db and core2.db.profile and core2.db.profile.general
    if stg2 and stg2.skinGameMenu then
        local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(stg2, "gameMenu")
        StyleButton(btn, sr, sg, sb, sa, bgr, bgg, bgb, bga, "QUI Edit Mode")
    end
end

-- Extend the menu backdrop to cover all standalone buttons (QUI + Edit Mode).
-- Called after both buttons are positioned. Deferred by one frame so
-- GetBottom() returns the resolved position.
local function ExtendMenuBackdrop()
    if not menuBackdrop then return end

    C_Timer.After(0, function()
        -- Find the lowest visible standalone button
        local lowestBottom = nil
        if quiStandaloneButton and quiStandaloneButton:IsShown() then
            local b = quiStandaloneButton:GetBottom()
            if b then lowestBottom = b end
        end
        if editModeButton and editModeButton:IsShown() then
            local b = editModeButton:GetBottom()
            if b and (not lowestBottom or b < lowestBottom) then
                lowestBottom = b
            end
        end

        if not lowestBottom then
            menuBackdrop:ClearAllPoints()
            menuBackdrop:SetAllPoints(GameMenuFrame)
            return
        end

        local gmBottom = GameMenuFrame:GetBottom()
        if gmBottom and lowestBottom < gmBottom then
            local extend = gmBottom - lowestBottom + 12
            menuBackdrop:ClearAllPoints()
            menuBackdrop:SetPoint("TOPLEFT", GameMenuFrame, "TOPLEFT")
            menuBackdrop:SetPoint("TOPRIGHT", GameMenuFrame, "TOPRIGHT")
            menuBackdrop:SetPoint("BOTTOMLEFT", GameMenuFrame, "BOTTOMLEFT", 0, -extend)
            menuBackdrop:SetPoint("BOTTOMRIGHT", GameMenuFrame, "BOTTOMRIGHT", 0, -extend)
        else
            menuBackdrop:ClearAllPoints()
            menuBackdrop:SetAllPoints(GameMenuFrame)
        end
    end)
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
--
-- LIFECYCLE: The watcher OnUpdate runs permanently with a 0.05s throttle.
-- We intentionally do NOT hook ShowUIPanel/HideUIPanel — those hooks insert
-- addon code into the secure call chain for every panel open (world map, etc.),
-- causing ADDON_ACTION_BLOCKED taint errors during combat.  The cost of one
-- IsShown() C-call per tick when the menu is hidden is negligible.
if GameMenuFrame then
    local gameMenuWatcher = CreateFrame("Frame", nil, UIParent)
    local wasShown = false
    local lastButtonCount = 0
    -- Poll while the menu is visible only; use a short interval so ESC feels instant
    -- even when Blizzard asynchronously adds/reflows buttons.
    local WATCHER_INTERVAL = 0.05
    local watcherElapsed = 0

    -- The OnUpdate handler — only set when the game menu might be visible
    local function WatcherOnUpdate(self, delta)
        watcherElapsed = watcherElapsed + (delta or 0)
        if watcherElapsed < WATCHER_INTERVAL then return end
        watcherElapsed = 0

        local isShown = GameMenuFrame:IsShown()

        if isShown and not wasShown then
            -- GameMenuFrame just became visible
            wasShown = true

            ShowDimBehindGameMenu()

            local oc = SyncOverlayContainerLevel()
            oc:Show()

            -- Skin pool buttons first so skinState.skinned is true when
            -- PositionStandaloneButton styles the QUI button.
            SkinGameMenu()

            -- Blizzard's InitButtons re-shows Border/Header every open.
            -- SkinGameMenu() only runs once (skinState.skinned gate), so
            -- hide decorations on every show to prevent frame height growth.
            if skinState.skinned then
                HideBlizzardDecorations()
            end

            PositionStandaloneButton()
            PositionEditModeButton()
            ExtendMenuBackdrop()

            if skinState.skinned and GameMenuFrame.buttonPool then
                local count = 0
                local core = GetCore()
                local stg = core and core.db and core.db.profile and core.db.profile.general
                local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(stg, "gameMenu")
                for button in GameMenuFrame.buttonPool:EnumerateActive() do
                    count = count + 1
                    -- Re-style ALL buttons each show (not just new ones).
                    -- Pool re-acquisition can replace button internals, so
                    -- overlay anchors and mirrored labels are refreshed.
                    StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
                lastButtonCount = count
            end
            RefreshGameMenuFontSize()
            UpdateVisibleButtonHovers()
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
                if skinState.skinned then
                    HideBlizzardDecorations()
                end
                PositionStandaloneButton()
                PositionEditModeButton()
                ExtendMenuBackdrop()
                if skinState.skinned and GameMenuFrame.buttonPool then
                    local core3 = GetCore()
                    local stg3 = core3 and core3.db and core3.db.profile and core3.db.profile.general
                    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(stg3, "gameMenu")
                    for button in GameMenuFrame.buttonPool:EnumerateActive() do
                        StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                    end
                end
                RefreshGameMenuFontSize()
            end
            UpdateVisibleButtonHovers()
        elseif wasShown then
            -- GameMenuFrame just became hidden — stop the polling loop
            wasShown = false
            lastButtonCount = 0

            HideDimBehindGameMenu()

            local oc = SyncOverlayContainerLevel()
            oc:Hide()

            for button, info in pairs(buttonOverlays) do
                if info and info.overlay then
                    info.hovered = false
                end
            end

            if quiStandaloneButton then
                quiStandaloneButton:Hide()
            end

            if editModeButton then
                editModeButton:Hide()
            end

            -- Reset backdrop to default size (no standalone button extension)
            if menuBackdrop then
                menuBackdrop:ClearAllPoints()
                menuBackdrop:SetAllPoints(GameMenuFrame)
            end

        end
    end

    -- TAINT SAFETY: We intentionally keep the watcher running permanently
    -- instead of using hooksecurefunc("ShowUIPanel"/\"HideUIPanel") to
    -- start/stop it.  Hooking ShowUIPanel inserts addon code into the
    -- secure call chain for EVERY panel (world map, character sheet, etc.),
    -- which taints the secureexecuterange batch and causes
    -- ADDON_ACTION_BLOCKED errors on protected functions like
    -- SetPropagateMouseClicks when opening the world map during combat.
    --
    -- Cost: one GameMenuFrame:IsShown() C-call per throttle tick (0.05s)
    -- when the menu is hidden — negligible compared to event dispatch.
    gameMenuWatcher:SetScript("OnUpdate", WatcherOnUpdate)
end
