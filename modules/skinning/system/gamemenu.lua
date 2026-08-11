local _, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local Helpers = ns.Helpers
local GetCore = Helpers.GetCore
local SkinBase = ns.SkinBase

local COLORS = { text = { 0.9, 0.9, 0.9, 1 } }

local buttonState = Helpers.CreateStateTable()

local installed = false
local staticDone = false
local menuBg = nil
local dimFrame = nil
local quiButton = nil
local editModeButton = nil

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

local function StripChromeOnce()
    for i = 1, select("#", GameMenuFrame:GetRegions()) do
        local r = select(i, GameMenuFrame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") then
            r:SetAlpha(0)
        end
    end
end

local function ReassertChrome()
    if GameMenuFrame.NineSlice then GameMenuFrame.NineSlice:SetAlpha(0) end
    if GameMenuFrame.Border then GameMenuFrame.Border:SetAlpha(0) end
    if GameMenuFrame.Header then GameMenuFrame.Header:SetAlpha(0) end
end

local function ReassertLevels(refLevel)
    local base = refLevel or GameMenuFrame:GetFrameLevel() or 1
    if menuBg then menuBg:SetFrameLevel(math.max(0, base - 2)) end
    if dimFrame then dimFrame:SetFrameLevel(math.max(0, base - 3)) end
end

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
        SkinBase.SetInsetPixelPoints(inset, button, 1)
        inset:EnableMouse(false)
        info.inset = inset

        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(inset)
        hl:SetColorTexture(1, 1, 1, 0.10)
        info.highlight = hl
    end

    info.inset:SetFrameLevel(math.max(0, (button:GetFrameLevel() or 1) - 1))

    local btnBgR = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgG = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgB = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
    SkinBase.ApplyFullBackdrop(info.inset, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)

    SkinBase.ApplyButtonFontObjects(button, { size = fontSize, color = COLORS.text })
end

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

local function RestoreButtonArt(button)
    if not button then return end
    local info = buttonState[button]
    if not info then return end
    if info.inset then info.inset:Hide() end
    if info.highlight then info.highlight:SetAlpha(0) end
    local fs = button.GetFontString and button:GetFontString()
    for i = 1, select("#", button:GetRegions()) do
        local r = select(i, button:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture")
           and r ~= fs and r ~= info.highlight then
            r:SetAlpha(1)
        end
    end
    if button.SetNormalFontObject then button:SetNormalFontObject("GameFontNormal") end
    if button.SetHighlightFontObject then button:SetHighlightFontObject("GameFontHighlight") end
    if button.SetDisabledFontObject then button:SetDisabledFontObject("GameFontDisable") end
end

local function PositionCustomButtons(settings, skin, refButton, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
    if settings.addQUIButton == false then
        if quiButton then quiButton:Hide() end
    else
        local b = GetOrCreateQUIButton()
        b:ClearAllPoints()
        b:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -2)
        if refButton then b:SetSize(refButton:GetWidth(), refButton:GetHeight()) end
        b:Show()
        if skin then
            SkinButton(b, false, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
        else
            RestoreButtonArt(b)
        end
    end

    if settings.addEditModeButton == false then
        if editModeButton then editModeButton:Hide() end
    else
        local b = GetOrCreateEditModeButton()
        local anchor = (quiButton and quiButton:IsShown()) and quiButton or GameMenuFrame
        b:ClearAllPoints()
        b:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
        if refButton then b:SetSize(refButton:GetWidth(), refButton:GetHeight()) end
        b:Show()
        if skin then
            SkinButton(b, false, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
        else
            RestoreButtonArt(b)
        end
    end
end

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

local function ApplyStaticSkin()
    if staticDone then return end
    local bg = EnsureMenuBg()
    EnsureDim()
    StripChromeOnce()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetGameMenuColors()
    SkinBase.ApplyFullBackdrop(bg, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    staticDone = true
end

local function OnInitButtons(menu)
    local settings = GetGeneralSettings()
    if not settings then return end
    if not menu or not menu.buttonPool then return end

    local skin = settings.skinGameMenu
    local wantButtons = settings.addQUIButton ~= false or settings.addEditModeButton ~= false
    if not skin and not wantButtons then return end

    if skin then
        ApplyStaticSkin()
        ReassertChrome()
    end

    local sr, sg, sb, sa, bgr, bgg, bgb = GetGameMenuColors()
    local fontSize = GetGameMenuFontSize()

    local refButton, minLevel
    for button in menu.buttonPool:EnumerateActive() do
        if skin then
            SkinButton(button, true, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
        end
        local lvl = button:GetFrameLevel() or 0
        if not minLevel or lvl < minLevel then minLevel = lvl end
        refButton = refButton or button
    end

    if skin then ReassertLevels(minLevel) end
    PositionCustomButtons(settings, skin, refButton, sr, sg, sb, sa, bgr, bgg, bgb, fontSize)
    if skin then
        AssertDim(settings)
        ExtendMenuBg()
    end
end

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
        return
    end
    local fontSize = GetGameMenuFontSize()
    for button in pairs(buttonState) do
        SkinBase.ApplyButtonFontObjects(button, { size = fontSize, color = COLORS.text })
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
