---------------------------------------------------------------------------
-- Alts window: chassis (bg + 1px border + drag header + close + ESC) and
-- tab strip. Tab views self-register via Window.RegisterTab(id, label,
-- builder); builder(parent) returns { frame, Refresh() }. Position/size
-- persist in profile alts.window (bags chassis precedent).
--
-- Pure UI: reads settings via Alts.GetSettings; no data access of its own.
-- Mirrors QUI_Bags/bags/views/chassis.lua idioms (UIKit pixel backdrop +
-- border, Helpers skin colors / general font, GetCore():PixelRound drag
-- persistence, UISpecialFrames ESC-close) and the bank_window.lua tab
-- button pattern (WHITE8x8 bg + UIKit.CreateBorderLines/UpdateBorderLines
-- selected-state).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local Window = {}
Alts.Window = Window

local HEADER_H, TAB_H, TAB_GAP, PAD = 28, 22, 4, 8

local win          -- created lazily on first Toggle
local tabs = {}    -- ordered: { id, label, builder, view, button }
local activeTab    -- id

--- Register a tab view. builder(parent) returns { frame, Refresh() };
--- frame is hidden + SetAllPoints(body) by Build. MUST be called at file
--- load (before the first Toggle) — Build runs once and never re-renders
--- the strip, so a post-Build registration is silently invisible.
--- Reskin covers chrome + tab labels ONLY: views own their content's font/
--- color refresh (re-apply inside their Refresh()).
function Window.RegisterTab(id, label, builder)
    tabs[#tabs + 1] = { id = id, label = label, builder = builder }
end

local function Settings()
    local s = Alts.GetSettings()
    return s and s.window
end

local function Reskin()
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    win._bg:SetVertexColor(bgr, bgg, bgb, bga)
    if win._border and win._border.SetBackdropBorderColor then
        win._border:SetBackdropBorderColor(sr, sg, sb, sa)
    end
    local fontPath = Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local outline = Helpers.GetGeneralFontOutline() or "OUTLINE"
    win._title:SetFont(fontPath, 13, outline)
    win._closeText:SetFont(fontPath, 12, outline)
    for _, t in ipairs(tabs) do
        if t.button and t.button._label then
            t.button._label:SetFont(fontPath, 11, outline)
        end
    end
end

local function SelectTab(id)
    activeTab = id
    local sr, sg, sb = Helpers.GetSkinColors()
    for _, t in ipairs(tabs) do
        local on = (t.id == id)
        if t.view then t.view.frame:SetShown(on) end
        if t.button then UIKit.UpdateBorderLines(t.button, 1, sr, sg, sb, on and 1 or 0.35) end
        if on and t.view and t.view.Refresh then t.view.Refresh() end
    end
end

local function BuildTabStrip()
    local fontPath = Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local outline = Helpers.GetGeneralFontOutline() or "OUTLINE"
    local x = 0
    for _, t in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, win._tabStrip)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0, 0, 0, 0.35)
        UIKit.DisablePixelSnap(bg)
        btn._label = btn:CreateFontString(nil, "ARTWORK")
        btn._label:SetPoint("CENTER", 0, 0)
        -- font BEFORE SetText: a templateless FontString has no font and
        -- SetText errors ("Font not set"); Reskin re-applies later.
        btn._label:SetFont(fontPath, 11, outline)
        btn._label:SetText(t.label)
        UIKit.CreateBorderLines(btn)
        btn:SetSize(math.max(56, math.ceil(btn._label:GetStringWidth()) + 16), TAB_H)
        btn:SetPoint("TOPLEFT", win._tabStrip, "TOPLEFT", x, 0)
        btn:SetScript("OnClick", function() SelectTab(t.id) end)
        x = x + btn:GetWidth() + TAB_GAP
        t.button = btn
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
    win._border = UIKit.CreateBackdropBorder(win, 1, 1, 1, 1, 1)

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
        if not point then return end -- GetPoint is MayReturnNothing per API docs
        local core = Helpers.GetCore()
        if core and core.PixelRound then x, y = core:PixelRound(x), core:PixelRound(y) end
        local s = Settings()
        if s then s.point, s.x, s.y = point, x, y end
    end)
    win._header = header

    win._title = header:CreateFontString(nil, "ARTWORK")
    -- font BEFORE SetText (templateless FontString errors otherwise)
    win._title:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 13,
        Helpers.GetGeneralFontOutline() or "OUTLINE")
    win._title:SetPoint("LEFT", PAD, 0)
    win._title:SetText("Alts")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(HEADER_H - 8, HEADER_H - 8)
    close:SetPoint("RIGHT", -6, 0)
    win._closeText = close:CreateFontString(nil, "ARTWORK")
    win._closeText:SetPoint("CENTER", 0, 0)
    win._closeText:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    win._closeText:SetText("X")
    close:SetScript("OnClick", function() win:Hide() end)
    win._close = close

    win._tabStrip = CreateFrame("Frame", nil, win)
    win._tabStrip:SetPoint("TOPLEFT", PAD, -HEADER_H)
    win._tabStrip:SetPoint("TOPRIGHT", -PAD, -HEADER_H)
    win._tabStrip:SetHeight(TAB_H)

    win._body = CreateFrame("Frame", nil, win)
    win._body:SetPoint("TOPLEFT", PAD, -(HEADER_H + TAB_H + 4))
    win._body:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    BuildTabStrip()
    for _, t in ipairs(tabs) do
        t.view = t.builder(win._body)
        t.view.frame:SetAllPoints(win._body)
        t.view.frame:Hide()
    end

    win:SetScript("OnHide", function()
        win:StopMovingOrSizing()
    end)

    Reskin()

    -- ESC-close (chassis.lua precedent)
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

--- Active tab refresh — bus subscribers call this on data changes.
function Window.RefreshActive()
    if not (win and win:IsShown()) then return end
    for _, t in ipairs(tabs) do
        if t.id == activeTab and t.view and t.view.Refresh then t.view.Refresh() end
    end
end

--- Profile switch: re-apply persisted position/size.
-- live theme recolor (bags chassis precedent: second Registry entry on the
-- skinning group). Hidden windows skip — Toggle reskins on next show.
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
