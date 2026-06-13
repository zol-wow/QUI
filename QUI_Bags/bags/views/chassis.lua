---------------------------------------------------------------------------
-- Bags views: window chassis. Shared shell for bag/bank/guild windows:
-- QUI pixel backdrop + border, title, drag + position persistence, close
-- button, search box, ESC-close (UISpecialFrames), live skin recolor.
-- Pure UI: reads settings via callbacks the owner provides; no data access.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers

local Chassis = {}
Bags.Chassis = Chassis

local windows = {} -- name → window (for ReskinAll)

local HEADER_H = 28
local FOOTER_H = 22
local PAD = 8

local function IsControlShown(control)
    if not control then return false end
    if control.IsShown then return control:IsShown() end
    if control.IsVisible then return control:IsVisible() end
    return true
end

local function ControlWidth(control)
    if not control then return 0 end
    local w = nil
    if control.GetWidth then w = control:GetWidth() end
    if (not w or w <= 0) and control.GetStringWidth then
        w = control:GetStringWidth()
    end
    return w or control.width or 0
end

local function ClampNumber(value, fallback, minValue, maxValue)
    local n = tonumber(value)
    if not n then n = fallback end
    if n < minValue then return minValue end
    if n > maxValue then return maxValue end
    return n
end

local function ClampInteger(value, fallback, minValue, maxValue)
    local n = tonumber(value)
    if not n then
        if fallback == nil then return nil end
        n = fallback
    end
    n = math.floor(n)
    if n < minValue then return minValue end
    if n > maxValue then return maxValue end
    return n
end

--- Build a window's one-shot ScheduleRefresh closure. The returned function
--- installs an OnUpdate that clears itself and calls refresh() on the next
--- frame, guarded so it never double-schedules while one is pending. The
--- window's OnUpdate is owned exclusively by this closure. getWin returns the
--- (lazily created) chassis window; refresh is the window's Refresh entry.
function Chassis.MakeScheduleRefresh(getWin, refresh)
    return function()
        local win = getWin()
        if win and win:IsShown() and not win._updateScheduled then
            win._updateScheduled = true
            win:SetScript("OnUpdate", function(self)
                self:SetScript("OnUpdate", nil)
                self._updateScheduled = false
                refresh()
            end)
        end
    end
end

--- Build the shared dark-panel button preamble: a Button with a 35%-black
--- WHITE8x8 background (pixel-snap disabled). When withLabel is true a
--- centered ARTWORK label (general font, 11px OUTLINE) is created and stashed
--- on btn._label. Callers add their own border lines, sizing, text, scripts,
--- and click registration so per-button ordering stays exactly as before.
function Chassis.CreatePanelButton(parent, withLabel)
    local btn = CreateFrame("Button", nil, parent)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(bg)
    if withLabel then
        btn._label = btn:CreateFontString(nil, "ARTWORK")
        btn._label:SetPoint("CENTER", 0, 0)
        btn._label:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
    end
    return btn
end

--- Measure the minimum width needed for a horizontal header control row.
--- Hidden/nil controls are ignored; opts = { leftPad, rightPad, gap }.
function Chassis.MeasureHeaderWidth(controls, opts)
    opts = opts or {}
    local leftPad = opts.leftPad or PAD
    local rightPad = opts.rightPad or PAD
    local gap = opts.gap or 0
    local width = leftPad + rightPad
    local visible = 0
    for _, control in ipairs(controls or {}) do
        if IsControlShown(control) then
            if visible > 0 then width = width + gap end
            width = width + ControlWidth(control)
            visible = visible + 1
        end
    end
    return width
end

--- Shallow-copy appearance settings and clamp render-critical dimensions.
function Chassis.ClampAppearance(appearance)
    local src = appearance or {}
    local out = {}
    for k, v in pairs(src) do out[k] = v end
    out.iconSize = ClampNumber(src.iconSize, 36, 24, 48)
    out.spacing = ClampNumber(src.spacing, 4, 0, 8)
    out.columns = ClampInteger(src.columns, 12, 1, 20)
    out.bankColumns = ClampInteger(src.bankColumns, nil, 1, 24)
    out.guildColumns = ClampInteger(src.guildColumns, nil, 1, 24)
    return out
end

local function Reskin(win)
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    win._bg:SetVertexColor(bgr, bgg, bgb, bga)
    if win._border and win._border.SetBackdropBorderColor then
        win._border:SetBackdropBorderColor(sr, sg, sb, sa)
    end
    local fontPath = Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    local outline = Helpers.GetGeneralFontOutline() or "OUTLINE"
    win._title:SetFont(fontPath, 13, outline)
    win._closeText:SetFont(fontPath, 12, outline)
    win._searchBox:SetFont(fontPath, 12, outline)
    if win._searchBox._placeholder then
        win._searchBox._placeholder:SetFont(fontPath, 12, outline)
    end
    if win._searchBox._refreshChrome then
        win._searchBox._refreshChrome(win._searchBox)
    end
end

function Chassis.ReskinAll()
    for _, win in pairs(windows) do Reskin(win) end
end

--- opts: { name (global, required), title, onClose(win) -- fires on ANY hide (incl. parent hides/cinematics), not only user closes,
---         onUserClose() -- X-button clicks route here when provided (owner's close path: sound, opener clearing); absent → plain win:Hide(),
---         onSearchChanged(text), getPosition() → {point,x,y}, setPosition(point,x,y),
---         compactSearch (bool: search renders narrow until focused/non-empty),
---         onChromeChanged() -- header geometry changed (search expand/collapse); owners re-measure }
function Chassis.CreateWindow(opts)
    if opts.name and windows[opts.name] then
        return windows[opts.name]
    end
    local win = CreateFrame("Frame", opts.name, UIParent)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    if win.SetDontSavePosition then win:SetDontSavePosition(true) end
    win:Hide()

    -- shell: solid bg + 1px QUI border
    win._bg = win:CreateTexture(nil, "BACKGROUND")
    win._bg:SetAllPoints()
    win._bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    UIKit.DisablePixelSnap(win._bg)
    win._border = UIKit.CreateBackdropBorder(win, 1, 1, 1, 1, 1)

    -- header: drag region + title + close
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        win:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local point, _, _, x, y = win:GetPoint()
        if not point then return end -- GetPoint is MayReturnNothing per API docs
        local core = Helpers.GetCore()
        if core and core.PixelRound then
            x, y = core:PixelRound(x), core:PixelRound(y)
        end
        if opts.setPosition then opts.setPosition(point, x, y) end
    end)
    win._header = header

    win._title = header:CreateFontString(nil, "ARTWORK")
    win._title:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 13, Helpers.GetGeneralFontOutline() or "OUTLINE")
    win._title:SetPoint("LEFT", PAD, 0)
    win._title:SetText(opts.title or "")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(HEADER_H - 8, HEADER_H - 8)
    close:SetPoint("RIGHT", -6, 0)
    win._closeText = close:CreateFontString(nil, "ARTWORK")
    win._closeText:SetPoint("CENTER", 0, 0)
    win._closeText:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12, "OUTLINE")
    win._closeText:SetText("X")
    close:SetScript("OnClick", function()
        if opts.onUserClose then opts.onUserClose() else win:Hide() end
    end)
    win._close = close

    -- search box (header, left of close)
    local search = CreateFrame("EditBox", nil, header)
    search:SetSize(140, HEADER_H - 10)
    search:SetPoint("RIGHT", close, "LEFT", -8, 0)
    search:SetAutoFocus(false)
    search:SetTextInsets(4, 4, 0, 0)
    local searchBg = search:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    searchBg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(searchBg)
    -- Border + ghost label: a bare dark strip reads as dead chrome, not an
    -- input. 1px QUI border (accent while focused, dim skin color
    -- otherwise) + "Search" placeholder while empty and unfocused.
    UIKit.CreateBorderLines(search)
    local placeholder = search:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", search, "LEFT", 5, 0)
    -- font BEFORE SetText: a templateless FontString has none, and
    -- SetText errors ("Font not set") — Reskin re-applies the themed font
    -- later, but creation must not depend on it
    placeholder:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 12,
        Helpers.GetGeneralFontOutline() or "OUTLINE")
    placeholder:SetTextColor(0.55, 0.55, 0.55, 0.9)
    placeholder:SetText(_G.SEARCH or "Search")
    search._placeholder = placeholder
    -- compact mode: narrow at rest, full-width while focused or non-empty
    -- (the expand/collapse pings onChromeChanged so owners re-measure the
    -- header width and re-render)
    local SEARCH_FULL_W, SEARCH_COMPACT_W = 140, 70
    local function UpdateSearchWidth(self)
        if not opts.compactSearch then return end
        local expanded = self:HasFocus() or (self:GetText() or "") ~= ""
        local want = expanded and SEARCH_FULL_W or SEARCH_COMPACT_W
        if self:GetWidth() ~= want then
            self:SetWidth(want)
            if opts.onChromeChanged then opts.onChromeChanged() end
        end
    end
    if opts.compactSearch then search:SetWidth(SEARCH_COMPACT_W) end
    local function RefreshSearchChrome(self)
        placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
        UpdateSearchWidth(self)
        if self:HasFocus() then
            local QGUI = _G.QUI and _G.QUI.GUI
            local acc = QGUI and QGUI.Colors and QGUI.Colors.accent
            local ar, ag, ab
            if acc then ar, ag, ab = acc[1], acc[2], acc[3]
            else ar, ag, ab = Helpers.GetSkinColors() end
            UIKit.UpdateBorderLines(self, 1, ar, ag, ab, 0.9)
        else
            local sr, sg, sb = Helpers.GetSkinColors()
            UIKit.UpdateBorderLines(self, 1, sr, sg, sb, 0.5)
        end
    end
    search._refreshChrome = RefreshSearchChrome
    search:SetScript("OnEditFocusGained", RefreshSearchChrome)
    search:SetScript("OnEditFocusLost", RefreshSearchChrome)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    local lastDispatched = nil
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text ~= lastDispatched then
            lastDispatched = text
            if opts.onSearchChanged then opts.onSearchChanged(text) end
        end
        RefreshSearchChrome(self)
    end)
    win._searchBox = search
    RefreshSearchChrome(search)

    -- body (content region between header and footer)
    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", PAD, -HEADER_H)
    body:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H)
    win._body = body

    -- footer (money / free slots text, owner-populated). Height is
    -- dynamic: owners that wrap footer controls into extra rows on narrow
    -- windows grow it via SetFooterHeight below.
    local footerH = FOOTER_H
    local footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(footerH)
    win._footer = footer

    win:SetScript("OnHide", function()
        win:StopMovingOrSizing()
        if opts.onClose then opts.onClose(win) end
    end)

    -- ESC-close
    if opts.name and not tContains(UISpecialFrames, opts.name) then
        tinsert(UISpecialFrames, opts.name)
    end

    --- size the window so the body content area is contentW x contentH
    function win:SetContentSize(contentW, contentH)
        self._contentW, self._contentH = contentW, contentH
        self:SetSize(contentW + PAD * 2, contentH + HEADER_H + footerH)
    end

    --- grow/shrink the footer (multi-row footers); keeps the body content
    --- area intact by re-applying the last SetContentSize
    function win:SetFooterHeight(h)
        if h == footerH then return end
        footerH = h
        footer:SetHeight(h)
        body:SetPoint("BOTTOMRIGHT", -PAD, h)
        if self._contentW then
            self:SetContentSize(self._contentW, self._contentH)
        end
    end

    function win:ApplyPosition()
        local pos = opts.getPosition and opts.getPosition()
        self:ClearAllPoints()
        if pos and pos.point then
            self:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
        else
            self:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 120)
        end
    end

    Reskin(win)
    windows[opts.name or tostring(win)] = win
    return win
end

---------------------------------------------------------------------------
-- Shared sort-mode context menu (bag + bank sort buttons' right-click).
-- Writes the same behavior.sortKey/sortReverse the options page binds.
-- House MenuUtil idiom (bag-slot menu precedent); CreateRadio(text,
-- isSelected, setSelected, data) verified in the vendored
-- Blizzard_Menu/11_0_0_MenuImplementationGuide.lua.
---------------------------------------------------------------------------
-- Lazy: chassis has no load-time settings dependency (the header-width
-- unit test loads this file with a minimal Helpers stub); the getter
-- resolves on first menu/tooltip use, which only happens in-game.
local getBagsSettings
local function GetBagsSettings()
    if not getBagsSettings then
        if not (Helpers and Helpers.CreateDBGetter) then return nil end
        getBagsSettings = Helpers.CreateDBGetter("bags")
    end
    return getBagsSettings()
end

local SORT_MODES = {
    { key = "quality", label = "Quality" },
    { key = "type", label = "Type" },
    { key = "name", label = "Name" },
    { key = "ilvl", label = "Item Level" },
    { key = "expansion", label = "Expansion" },
}

function Chassis.SortModeText()
    local s = GetBagsSettings()
    local key = s and s.behavior and s.behavior.sortKey or "quality"
    local label = "Quality"
    for _, m in ipairs(SORT_MODES) do
        if m.key == key then label = m.label end
    end
    if s and s.behavior and s.behavior.sortReverse then
        label = label .. " (reversed)"
    end
    return label
end

--- Right-click menu for a sort button. extra(root) appends owner-specific
--- entries (bank: "Sort all tabs"; bags: "Stack reagents").
function Chassis.ShowSortMenu(anchor, extra)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle("Sort by")
        for _, m in ipairs(SORT_MODES) do
            root:CreateRadio(m.label,
                function()
                    local s = GetBagsSettings()
                    return (s and s.behavior and s.behavior.sortKey or "quality") == m.key
                end,
                function()
                    local s = GetBagsSettings()
                    if s and s.behavior then s.behavior.sortKey = m.key end
                end)
        end
        root:CreateCheckbox("Reverse order",
            function()
                local s = GetBagsSettings()
                return s and s.behavior and s.behavior.sortReverse or false
            end,
            function()
                local s = GetBagsSettings()
                if s and s.behavior then s.behavior.sortReverse = not s.behavior.sortReverse end
            end)
        if extra then extra(root) end
    end)
end

-- live theme recolor (second Registry entry: skinning group)
if ns.Registry then
    ns.Registry:Register("bagsSkin", {
        refresh = Chassis.ReskinAll,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
