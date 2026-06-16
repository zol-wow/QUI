local _, ns = ...

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- GAME MENU (ESC MENU) SKINNING + QUI BUTTONS
--
-- Flash-free design: the skin is baked into GameMenuFrame itself.  A
-- hooksecurefunc on InitButtons runs synchronously inside OnShow, BEFORE the
-- frame paints, so the menu is styled the instant it appears.  No OnUpdate
-- poll, no UIParent overlays, no show/hide hooks.
--
-- Hook surface (matches the proven retail pattern):
--   * hooksecurefunc(GameMenuFrame, "InitButtons")  -- the only frame hook
--   * hooksecurefunc(<slice>, "SetAlpha")           -- clamp button art to 0
-- Dim + custom buttons are parented to GameMenuFrame so they auto-hide with
-- it; no OnHide hook is needed.
--
-- TAINT: never call AddButton/MarkDirty from addon context (the custom
-- buttons are our own frames, not pool buttons) and never hook the global
-- ShowUIPanel/HideUIPanel.  All per-button skin state lives in a weak-keyed
-- Lua table, never as a property written onto a secure button.  The prior
-- ADDON_ACTION_FORBIDDEN on Edit Mode was a different root cause (red herring).
---------------------------------------------------------------------------

local COLORS = { text = { 0.9, 0.9, 0.9, 1 } }
local FONT_FLAGS = "OUTLINE"

-- weak-keyed: per-button skin state { inset=, highlight=, clamped=bool }
local buttonState = Helpers.CreateStateTable()

local installed = false
local staticDone = false
local menuBg = nil          -- themed bg/border, child of GameMenuFrame
local dimFrame = nil        -- screen dim, child of GameMenuFrame
local quiButton = nil       -- standalone QUI button (child of GameMenuFrame)
local editModeButton = nil  -- standalone Edit Mode button (child of GameMenuFrame)

---------------------------------------------------------------------------
-- settings helpers
---------------------------------------------------------------------------
local function GetGeneralSettings()
    local core = GetCore()
    return core and core.db and core.db.profile and core.db.profile.general
end

local function GetGameMenuFontSize()
    local s = GetGeneralSettings()
    return s and s.gameMenuFontSize or 12
end

local function GetGameMenuColors()
    return SkinBase.GetSkinColors(GetGeneralSettings(), "gameMenu")
end

---------------------------------------------------------------------------
-- chrome strip
---------------------------------------------------------------------------
local function StripChromeOnce()
    -- GameMenuFrame draws its panel via region textures (NineSlice etc.).
    for i = 1, select("#", GameMenuFrame:GetRegions()) do
        local r = select(i, GameMenuFrame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then
            r:SetAlpha(0)
        end
    end
end

local function ReassertChrome()
    -- Blizzard's InitButtons -> Reset re-shows these decorations every open.
    if GameMenuFrame.NineSlice then GameMenuFrame.NineSlice:SetAlpha(0) end
    if GameMenuFrame.Border then GameMenuFrame.Border:SetAlpha(0) end
    if GameMenuFrame.Header then GameMenuFrame.Header:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- frame-level layering
--
-- Drawn back-to-front: dim -> menuBg -> per-button inset bg -> the button's
-- own fontstring + HIGHLIGHT texture.  The inset sits one level BELOW its
-- button so the button's text/highlight draw over it.  menuBg/dim sit below
-- the lowest pool button so buttons always draw on top.
---------------------------------------------------------------------------
local function ReassertLevels(refLevel)
    local base = refLevel or GameMenuFrame:GetFrameLevel() or 1
    if menuBg then menuBg:SetFrameLevel(math.max(0, base - 2)) end
    if dimFrame then dimFrame:SetFrameLevel(math.max(0, base - 3)) end
end

---------------------------------------------------------------------------
-- dim + menu background (children of GameMenuFrame -> auto-hide on close)
---------------------------------------------------------------------------
local function EnsureDim()
    if dimFrame then return dimFrame end
    dimFrame = CreateFrame("Frame", "QUIGameMenuDim", GameMenuFrame)
    dimFrame:SetAllPoints(UIParent)
    dimFrame:EnableMouse(false)
    local tex = dimFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 0.5)
    dimFrame.tex = tex
    return dimFrame
end

local function AssertDim(settings)
    local dim = EnsureDim()
    if settings and settings.gameMenuDim then dim:Show() else dim:Hide() end
end

local function EnsureMenuBg()
    if menuBg then return menuBg end
    menuBg = CreateFrame("Frame", "QUIGameMenuBg", GameMenuFrame)
    menuBg:SetAllPoints(GameMenuFrame)
    menuBg:EnableMouse(false)
    return menuBg
end

---------------------------------------------------------------------------
-- button skinning
---------------------------------------------------------------------------
local function StripButtonArt(button, isPool, info)
    local fs = button.GetFontString and button:GetFontString()
    for i = 1, select("#", button:GetRegions()) do
        local r = select(i, button:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture")
           and r ~= fs and r ~= info.highlight then
            r:SetAlpha(0)
        end
    end
    if isPool and not info.clamped then
        -- ThreeSliceButton re-sets these atlases on every mouse state change,
        -- so clamp their alpha to 0 once via a durable hook.
        for _, key in ipairs({ "Left", "Center", "Right" }) do
            local tex = button[key]
            if tex and tex.SetAlpha then
                tex:SetAlpha(0)
                hooksecurefunc(tex, "SetAlpha", function(self, a)
                    if a and a > 0 then self:SetAlpha(0) end
                end)
            end
        end
        info.clamped = true
    end
end

local function SkinButton(button, isPool, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
    if not button then return end
    local info = buttonState[button]
    if not info then
        info = {}
        buttonState[button] = info
    end

    StripButtonArt(button, isPool, info)

    if not info.inset then
        local inset = CreateFrame("Frame", nil, button)
        inset:SetPoint("TOPLEFT", 1, -1)
        inset:SetPoint("BOTTOMRIGHT", -1, 1)
        inset:EnableMouse(false)
        info.inset = inset

        -- Flat hover highlight, on the button (auto-shown on mouseover).
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(inset)
        hl:SetColorTexture(1, 1, 1, 0.10)
        info.highlight = hl
    end

    -- Inset draws one level below the button so text/highlight sit on top.
    info.inset:SetFrameLevel(math.max(0, (button:GetFrameLevel() or 1) - 1))

    local btnBgR = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgG = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgB = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
    SkinBase.ApplyFullBackdrop(info.inset, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)

    local fs = button.GetFontString and button:GetFontString()
    if fs then
        SkinBase.SkinFontString(fs, { size = fontSize, outline = FONT_FLAGS, color = COLORS.text })
    end
end

---------------------------------------------------------------------------
-- custom buttons (our own frames, parented to GameMenuFrame)
---------------------------------------------------------------------------
local function GetOrCreateQUIButton()
    if quiButton then return quiButton end
    quiButton = CreateFrame("Button", "QUIGameMenuButton", GameMenuFrame, "UIPanelButtonTemplate")
    quiButton:SetText(ns.L["QUI"])
    quiButton:SetSize(160, 30)
    quiButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        HideUIPanel(GameMenuFrame)
        local QUI = _G.QUI
        if QUI and QUI.ShowOptions then QUI:ShowOptions() end
    end)
    quiButton:Hide()
    return quiButton
end

local function GetOrCreateEditModeButton()
    if editModeButton then return editModeButton end
    editModeButton = CreateFrame("Button", "QUIGameMenuEditModeButton", GameMenuFrame, "UIPanelButtonTemplate")
    editModeButton:SetText(ns.L["QUI Edit Mode"])
    editModeButton:SetSize(160, 30)
    editModeButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        HideUIPanel(GameMenuFrame)
        if _G.QUI_ToggleLayoutMode then _G.QUI_ToggleLayoutMode() end
    end)
    editModeButton:Hide()
    return editModeButton
end

local function PositionCustomButtons(settings, refButton, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
    -- QUI button: anchored to GameMenuFrame's BOTTOM edge (entirely outside
    -- the frame rect so the secure frame never eats its clicks).
    if settings.addQUIButton == false then
        if quiButton then quiButton:Hide() end
    else
        local b = GetOrCreateQUIButton()
        b:ClearAllPoints()
        b:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -2)
        if refButton then b:SetSize(refButton:GetWidth(), refButton:GetHeight()) end
        b:Show()
        SkinButton(b, false, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
    end

    -- Edit Mode button: below the QUI button when shown, else below the menu.
    if settings.addEditModeButton == false then
        if editModeButton then editModeButton:Hide() end
    else
        local b = GetOrCreateEditModeButton()
        local anchor = (quiButton and quiButton:IsShown()) and quiButton or GameMenuFrame
        b:ClearAllPoints()
        b:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
        if refButton then b:SetSize(refButton:GetWidth(), refButton:GetHeight()) end
        b:Show()
        SkinButton(b, false, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
    end
end

-- Extend menuBg downward to cover whichever custom buttons are visible.
-- Deferred one frame so GetBottom() is resolved.
local function ExtendMenuBg()
    if not menuBg then return end
    C_Timer.After(0, function()
        if not menuBg or not GameMenuFrame then return end
        local lowest
        if quiButton and quiButton:IsShown() then
            local v = quiButton:GetBottom()
            if v then lowest = v end
        end
        if editModeButton and editModeButton:IsShown() then
            local v = editModeButton:GetBottom()
            if v and (not lowest or v < lowest) then lowest = v end
        end

        menuBg:ClearAllPoints()
        if not lowest then
            menuBg:SetAllPoints(GameMenuFrame)
            return
        end
        local gmBottom = GameMenuFrame:GetBottom()
        if gmBottom and lowest < gmBottom then
            local extend = gmBottom - lowest + 12
            menuBg:SetPoint("TOPLEFT", GameMenuFrame, "TOPLEFT")
            menuBg:SetPoint("TOPRIGHT", GameMenuFrame, "TOPRIGHT")
            menuBg:SetPoint("BOTTOMLEFT", GameMenuFrame, "BOTTOMLEFT", 0, -extend)
            menuBg:SetPoint("BOTTOMRIGHT", GameMenuFrame, "BOTTOMRIGHT", 0, -extend)
        else
            menuBg:SetAllPoints(GameMenuFrame)
        end
    end)
end

---------------------------------------------------------------------------
-- static skin (once)
---------------------------------------------------------------------------
local function ApplyStaticSkin()
    if staticDone then return end
    local bg = EnsureMenuBg()
    EnsureDim()
    StripChromeOnce()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetGameMenuColors()
    SkinBase.ApplyFullBackdrop(bg, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    staticDone = true
end

---------------------------------------------------------------------------
-- the only frame hook: skin everything synchronously on each open
---------------------------------------------------------------------------
local function OnInitButtons(menu)
    local settings = GetGeneralSettings()
    if not settings or not settings.skinGameMenu then return end
    if not menu or not menu.buttonPool then return end

    ApplyStaticSkin()
    ReassertChrome()

    local sr, sg, sb, sa, bgr, bgg, bgb = GetGameMenuColors()
    local fontSize = GetGameMenuFontSize()

    local refButton, minLevel
    for button in menu.buttonPool:EnumerateActive() do
        SkinButton(button, true, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
        local lvl = button:GetFrameLevel() or 0
        if not minLevel or lvl < minLevel then minLevel = lvl end
        refButton = refButton or button
    end

    ReassertLevels(minLevel)
    PositionCustomButtons(settings, refButton, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
    AssertDim(settings)
    ExtendMenuBg()
end

---------------------------------------------------------------------------
-- live refresh (settings preview) — names/signatures unchanged
---------------------------------------------------------------------------
local function RefreshGameMenuColors()
    if not staticDone then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetGameMenuColors()
    if menuBg then
        SkinBase.ApplyFullBackdrop(menuBg, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end
    local btnBgR = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgG = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgB = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
    for _, info in pairs(buttonState) do
        if info.inset then
            SkinBase.ApplyFullBackdrop(info.inset, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)
        end
    end
end

local function RefreshGameMenuFontSize()
    local settings = GetGeneralSettings()
    if not settings or not settings.skinGameMenu then
        local core = GetCore()
        if core and core.ApplyGlobalFontToGameMenu then
            core:ApplyGlobalFontToGameMenu()
        end
        return
    end
    local fontSize = GetGameMenuFontSize()
    for button in pairs(buttonState) do
        local fs = button.GetFontString and button:GetFontString()
        if fs then
            SkinBase.SkinFontString(fs, { size = fontSize, outline = FONT_FLAGS, fontOnly = true })
        end
    end
end

_G.QUI_RefreshGameMenuColors = RefreshGameMenuColors
_G.QUI_RefreshGameMenuFontSize = RefreshGameMenuFontSize
_G.QUI_RefreshGameMenuDim = function()
    local settings = GetGeneralSettings()
    if not dimFrame then return end
    if settings and settings.gameMenuDim and GameMenuFrame and GameMenuFrame:IsShown() then
        dimFrame:Show()
    else
        dimFrame:Hide()
    end
end

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
-- install the hook (GameMenuFrame may not exist yet if its addon is LoD)
---------------------------------------------------------------------------
local function Install()
    if installed or not GameMenuFrame then return end
    installed = true
    hooksecurefunc(GameMenuFrame, "InitButtons", OnInitButtons)
end

if GameMenuFrame then
    Install()
else
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self)
        if GameMenuFrame then
            Install()
            self:UnregisterAllEvents()
        end
    end)
end
