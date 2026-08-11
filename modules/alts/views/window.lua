local ADDON_NAME, ns = ...
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local Window = {}
Alts.Window = Window

local HEADER_H, SIDEBAR_W, TAB_H, TAB_GAP, PAD = 32, 120, 26, 2, 10

local win
local tabs = {}
local activeTab

function Window.RegisterTab(id, label, builder, desc)
    tabs[#tabs + 1] = { id = id, label = label, builder = builder, desc = desc }
end

local function Settings()
    local s = Alts.GetSettings()
    return s and s.window
end

local FALLBACK = {
    bg        = { 0.051, 0.067, 0.09, 0.97 },
    bgSidebar = { 0, 0, 0, 0.25 },
    bgContent = { 1, 1, 1, 0.02 },
    accent    = { 0.204, 0.827, 0.6, 1 },
    accentFaint = { 0.204, 0.827, 0.6, 0.07 },
    accentGlow  = { 0.204, 0.827, 0.6, 0.06 },
    accentLight = { 0.431, 0.906, 0.718, 1 },
    border    = { 1, 1, 1, 0.06 },
    text      = { 1, 1, 1, 1 },
    textDim   = { 1, 1, 1, 0.6 },
}

local function Colors()
    local gui = _G.QUI and _G.QUI.GUI
    return (gui and gui.Colors) or FALLBACK
end

local function Col(name)
    local c = Colors()[name] or FALLBACK[name]
    return c[1], c[2], c[3], c[4] or 1
end

local function Accent()
    local gui = _G.QUI and _G.QUI.GUI
    local core = Helpers.GetCore and Helpers.GetCore()
    local general = core and core.db and core.db.profile and core.db.profile.general
    if gui and gui.ResolveThemePreset and general and general.themePreset then
        return gui:ResolveThemePreset(general.themePreset)
    end
    local custom = general and general.addonAccentColor
    if custom and custom[1] then return custom[1], custom[2], custom[3] end
    return Col("accent")
end

local function PanelAlpha()
    local core = Helpers.GetCore and Helpers.GetCore()
    local profile = core and core.db and core.db.profile
    return (profile and profile.configPanelAlpha) or 0.97
end

local function SetTabActiveState(t, active)
    local ar, ag, ab = Accent()
    t.button._indicator:SetShown(active)
    t.button._indicator:SetColorTexture(ar, ag, ab, 1)
    if active then
        t.button._hoverBg:SetColorTexture(ar, ag, ab, 0.07)
        t.button._hoverBg:Show()
        t.button._label:SetTextColor(Col("text"))
    else
        t.button._hoverBg:SetColorTexture(1, 1, 1, 0.03)
        t.button._hoverBg:Hide()
        t.button._label:SetTextColor(Col("textDim"))
    end
end

local function Reskin()
    local ar, ag, ab = Accent()
    local br, bg_, bb = Col("bg")
    win._bg:SetVertexColor(br, bg_, bb, PanelAlpha())
    UIKit.UpdateBorderLines(win, 1, Col("border"))
    win._sidebarBg:SetColorTexture(Col("bgSidebar"))
    win._sidebarDivider:SetColorTexture(Col("border"))
    win._titleSep:SetColorTexture(Col("border"))
    win._contentBg:SetColorTexture(Col("bgContent"))
    if win._glow.SetGradient then
        local gr, gg, gb, ga = Col("accentGlow")
        local ok = pcall(function()
            win._glow:SetGradient("HORIZONTAL",
                CreateColor(ar, ag, ab, ga or 0.06),
                CreateColor(ar, ag, ab, 0))
        end)
        if not ok then win._glow:SetColorTexture(gr, gg, gb, ga) end
    end

    local fontPath = Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local outline = Helpers.GetGeneralFontOutline() or "OUTLINE"
    CJKFont(win._title, fontPath, 14, outline)
    win._title:SetTextColor(Col("accentLight"))
    for _, t in ipairs(tabs) do
        if t.button then
            CJKFont(t.button._label, fontPath, 11, outline)
            SetTabActiveState(t, t.id == activeTab)
        end
    end
    if ns.AltsViewShared and ns.AltsViewShared.RestyleScrollBars then
        ns.AltsViewShared.RestyleScrollBars()
    end
end

local function SelectTab(id)
    activeTab = id
    for _, t in ipairs(tabs) do
        local on = (t.id == id)
        if t.view then t.view.frame:SetShown(on) end
        if t.button then SetTabActiveState(t, on) end
        if on and t.view and t.view.Refresh then t.view.Refresh() end
    end
end

local function BuildSidebarTabs()
    local fontPath = Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local outline = Helpers.GetGeneralFontOutline() or "OUTLINE"
    local gui = _G.QUI and _G.QUI.GUI
    local prev
    for _, t in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, win._sidebar)
        btn:SetHeight(TAB_H)
        if prev then
            btn:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -TAB_GAP)
            btn:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -TAB_GAP)
        else
            btn:SetPoint("TOPLEFT", win._sidebar, "TOPLEFT", 6, -6)
            btn:SetPoint("TOPRIGHT", win._sidebar, "TOPRIGHT", -6, -6)
        end

        btn._hoverBg = btn:CreateTexture(nil, "BACKGROUND")
        btn._hoverBg:SetAllPoints()
        btn._hoverBg:SetColorTexture(1, 1, 1, 0.03)
        UIKit.DisablePixelSnap(btn._hoverBg)
        btn._hoverBg:Hide()

        btn._indicator = btn:CreateTexture(nil, "OVERLAY")
        btn._indicator:SetPoint("TOPLEFT", 0, 0)
        btn._indicator:SetPoint("BOTTOMLEFT", 0, 0)
        btn._indicator:SetWidth(3)
        UIKit.DisablePixelSnap(btn._indicator)
        btn._indicator:Hide()

        btn._label = btn:CreateFontString(nil, "ARTWORK")
        CJKFont(btn._label, fontPath, 11, outline)
        btn._label:SetPoint("LEFT", btn, "LEFT", 10, 0)
        btn._label:SetJustifyH("LEFT")
        btn._label:SetText(t.label)

        btn:SetScript("OnClick", function() SelectTab(t.id) end)
        btn:SetScript("OnEnter", function(self)
            if t.id ~= activeTab then self._hoverBg:Show() end
        end)
        btn:SetScript("OnLeave", function(self)
            if t.id ~= activeTab then self._hoverBg:Hide() end
        end)
        if gui and gui.AttachTooltip and t.desc then
            gui:AttachTooltip(btn, t.desc, t.label)
        end

        t.button = btn
        prev = btn
    end
end

local function Build()
    local cfg = Settings()
    win = CreateFrame("Frame", "QUI_AltsWindow", UIParent)
    win:SetSize((cfg and cfg.width) or 920, (cfg and cfg.height) or 540)
    win:SetPoint((cfg and cfg.point) or "CENTER", UIParent, (cfg and cfg.point) or "CENTER",
        (cfg and cfg.x) or 0, (cfg and cfg.y) or 0)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    if win.SetDontSavePosition then win:SetDontSavePosition(true) end
    win:Hide()

    win._bg = win:CreateTexture(nil, "BACKGROUND")
    win._bg:SetAllPoints()
    win._bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    UIKit.DisablePixelSnap(win._bg)
    UIKit.CreateBorderLines(win)

    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local point, _, _, x, y = win:GetPoint()
        if not point then return end
        local core = Helpers.GetCore()
        if core and core.PixelRound then x, y = core:PixelRound(x), core:PixelRound(y) end
        local s = Settings()
        if s then s.point, s.x, s.y = point, x, y end
    end)
    win._header = header

    win._title = header:CreateFontString(nil, "ARTWORK")
    CJKFont(win._title, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 14,
        Helpers.GetGeneralFontOutline() or "OUTLINE")
    win._title:SetPoint("LEFT", 12, 0)
    win._title:SetText("Alts")

    win._close = UIKit.CreateCloseButton(header, {
        point = "RIGHT", x = -8, y = 0,
        onClick = function() win:Hide() end,
    })

    win._titleSep = win:CreateTexture(nil, "ARTWORK")
    win._titleSep:SetPoint("TOPLEFT", PAD, -HEADER_H)
    win._titleSep:SetPoint("TOPRIGHT", -PAD, -HEADER_H)
    win._titleSep:SetHeight(1)
    UIKit.DisablePixelSnap(win._titleSep)

    local sidebar = CreateFrame("Frame", nil, win)
    sidebar:SetPoint("TOPLEFT", PAD, -(HEADER_H + 1))
    sidebar:SetPoint("BOTTOMLEFT", PAD, PAD)
    sidebar:SetWidth(SIDEBAR_W)
    win._sidebar = sidebar

    win._sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    win._sidebarBg:SetAllPoints()
    UIKit.DisablePixelSnap(win._sidebarBg)

    win._sidebarDivider = sidebar:CreateTexture(nil, "ARTWORK")
    win._sidebarDivider:SetPoint("TOPRIGHT", 0, 0)
    win._sidebarDivider:SetPoint("BOTTOMRIGHT", 0, 0)
    win._sidebarDivider:SetWidth(1)
    UIKit.DisablePixelSnap(win._sidebarDivider)

    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    content:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    content:SetClipsChildren(true)
    win._content = content

    win._contentBg = content:CreateTexture(nil, "BACKGROUND")
    win._contentBg:SetAllPoints()
    UIKit.DisablePixelSnap(win._contentBg)

    win._glow = content:CreateTexture(nil, "BACKGROUND")
    win._glow:SetAllPoints()
    win._glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    UIKit.DisablePixelSnap(win._glow)

    win._body = CreateFrame("Frame", nil, content)
    win._body:SetPoint("TOPLEFT", 8, -8)
    win._body:SetPoint("BOTTOMRIGHT", -8, 8)

    BuildSidebarTabs()
    for _, t in ipairs(tabs) do
        t.view = t.builder(win._body)
        t.view.frame:SetAllPoints(win._body)
        t.view.frame:Hide()
    end

    win:SetScript("OnHide", function()
        win:StopMovingOrSizing()
    end)

    Reskin()

    if not tContains(UISpecialFrames, "QUI_AltsWindow") then
        tinsert(UISpecialFrames, "QUI_AltsWindow")
    end
end

function Window.IsShown()
    return win and win:IsShown() or false
end

function Window.Hide()
    if win then win:Hide() end
end

function Window.Toggle()
    if not win then Build() end
    if win:IsShown() then
        win:Hide()
    else
        Reskin()
        win:Show()
        SelectTab(activeTab or (tabs[1] and tabs[1].id))
    end
end

function Window.RefreshActive()
    if not (win and win:IsShown()) then return end
    for _, t in ipairs(tabs) do
        if t.id == activeTab and t.view and t.view.Refresh then t.view.Refresh() end
    end
end

if ns.Registry then
    ns.Registry:Register("altsSkin", {
        refresh = function()
            if win and win:IsShown() then Reskin() end
        end,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

function Window.OnProfileChanged()
    if not win then return end
    local cfg = Settings()
    if not cfg then return end
    win:ClearAllPoints()
    win:SetPoint(cfg.point or "CENTER", UIParent, cfg.point or "CENTER", cfg.x or 0, cfg.y or 0)
    win:SetSize(cfg.width or 920, cfg.height or 540)
end
