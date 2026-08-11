-- tests/unit/options_preview_panel_collapse_test.lua
-- Run: lua tests/unit/options_preview_panel_collapse_test.lua
-- luacheck: globals CreateFrame UIParent GetCursorPosition hooksecurefunc

local function NewFrame()
    local f = {
        children = {}, scripts = {}, hooks = {}, points = {},
        shown = true, width = 0, height = 0, scale = 1,
        level = 500, movingCalls = 0,
    }
    function f:SetPoint(point, relTo, relPoint, x, y)
        self.points[#self.points + 1] =
            { point = point, relTo = relTo, relPoint = relPoint, x = x, y = y }
    end
    function f:GetPoint(i) local p = self.points[i or 1]
        if not p then return nil end
        return p.point, p.relTo, p.relPoint, p.x, p.y end
    function f:ClearAllPoints() self.points = {} end
    function f:SetAllPoints() end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:SetScale(s) self.scale = s end
    function f:GetScale() return self.scale end
    function f:GetEffectiveScale() return self.scale end
    function f:GetLeft() return self.left end
    function f:GetRight() return self.right end
    function f:GetTop() return self.top end
    function f:Show() self.shown = true
        if self.hooks.OnShow then self.hooks.OnShow(self) end end
    function f:Hide() self.shown = false
        if self.hooks.OnHide then self.hooks.OnHide(self) end end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f:IsShown() return self.shown end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    function f:HookScript(k, fn) self.hooks[k] = fn end
    function f:EnableMouse() end
    function f:SetMovable(v) self.movable = v end
    function f:RegisterForDrag() end
    function f:RegisterForClicks() end
    function f:SetClampedToScreen() end
    function f:SetFrameStrata() end
    function f:SetToplevel(v) self.topLevel = v and true or false end
    function f:Raise() self.raiseCount = (self.raiseCount or 0) + 1 end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end
    function f:GetParent() return self.parent end
    function f:StartMoving() self.movingCalls = self.movingCalls + 1 end
    function f:StopMovingOrSizing() end
    function f:CreateTexture()
        local t = { SetAllPoints = function() end, SetTexture = function() end,
            SetVertexColor = function() end, SetColorTexture = function() end,
            SetGradient = function() end, SetPoint = function() end,
            SetHeight = function(s, h) s.height = h end,
            GetHeight = function(s) return s.height end,
            SetShown = function(s, v) s.shown = v and true or false end,
            IsShown = function(s) return s.shown end,
            Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end }
        t.shown = true
        return t
    end
    return f
end

function CreateFrame(_, _, parent)
    local f = NewFrame()
    f.parent = parent
    if parent and parent.children then
        parent.children[#parent.children + 1] = f
    end
    return f
end

UIParent = NewFrame()
UIParent.left, UIParent.right = 0, 1600
function hooksecurefunc(tbl, name, fn)
    local orig = tbl[name]
    tbl[name] = function(...) orig(...) if fn then fn(...) end end
end
GetCursorPosition = function() return 0, 0 end

local ns = {
    L = setmetatable({}, { __index = function(_, k) return k end }),
}
assert(loadfile("core/settings/full_surface.lua"))("QUI", ns)
local FullSurface = assert(ns.Settings and ns.Settings.FullSurface)

-- A window wide enough that the right dock always fits by default.
local function NewWindow()
    local win = NewFrame()
    win.left, win.right, win.top = 100, 700, 900
    win.width, win.height = 600, 850
    return win
end

local gui = {
    Colors = {},
    CreateLabel = function(_, parent, text)
        local fs = { text = text }
        function fs:SetJustifyH() end
        function fs:SetText(t) self.text = t end
        function fs:SetPoint() end
        -- Deterministic stand-in for real font metrics: 6px per character.
        function fs:GetStringWidth() return #(self.text or "") * 6 end
        fs.parent = parent
        return fs
    end,
}

local function BuildPanel(win, sessionState)
    gui.MainFrame = win
    return FullSurface.CreateDockedPreviewPanel({
        gui = gui, window = win, minWidth = 140,
        controlStripHeight = 0, sessionState = sessionState,
    })
end

local HEADER_H, PAD = 22, 8   -- builder defaults (opts.headerHeight / opts.pad)
local COLLAPSED_MIN_W = 96    -- builder constant
local COLLAPSE_BTN_W, DOCK_BTN_W = 20, 44   -- builder constants

-- Mirrors the builder's collapsed-width formula: pad + title + gap + buttons
-- + pad, floored at COLLAPSED_MIN_W. Title metrics come from the 6px/char
-- CreateLabel stub above, so keep test titles ASCII (# counts bytes).
local function ExpectedCollapsedW(titleText, detached)
    local btnW = COLLAPSE_BTN_W
    if detached then btnW = btnW + 4 + DOCK_BTN_W end
    local w = PAD + #titleText * 6 + 8 + btnW + PAD
    return (w < COLLAPSED_MIN_W) and COLLAPSED_MIN_W or w
end

local win = NewWindow()
local P = BuildPanel(win, {})
P.Show()

---------------------------------------------------------------------------
-- 0) Z-order: the panel outranks everything the window hosts (it can be
--    dragged on top of it), and the level is re-asserted every Show because
--    the toplevel window can be raised between shows.
---------------------------------------------------------------------------
assert(P.frame.level == win.level + 40, "panel level clears the in-window stack")
assert(P.frame.topLevel == true, "panel is independently top-level")
assert((P.frame.raiseCount or 0) >= 1, "panel is raised after show")
win.level = 700
P.Show()
assert(P.frame.level == 740, "level re-asserted against the raised window")
win.level = 500
P.Show()

---------------------------------------------------------------------------
-- 1) Resize while expanded applies content dims + chrome
---------------------------------------------------------------------------
P.Resize(300, 400)
assert(P.frame.width == 300 + PAD * 2, "expanded width = content + pad")
assert(P.frame.height == 400 + HEADER_H + PAD * 2, "expanded height = content + chrome")

---------------------------------------------------------------------------
-- 2) Collapse: shrinks in BOTH axes -- header-only height AND a title-strip
--    width, content + strip hidden
---------------------------------------------------------------------------
P.collapseButton.scripts.OnClick(P.collapseButton)
assert(P.IsCollapsed() == true, "collapsed")
assert(P._contentWrapper.shown == false, "content wrapper hidden")
assert(P.frame.height == HEADER_H + PAD * 2, "header-only height")
assert(P.frame.width == ExpectedCollapsedW("Preview", false), "collapsed to title-strip width")
assert(P.frame.width < 300 + PAD * 2, "collapsed width is narrower than expanded")
-- Header band fills the pill and the separator is hidden (nothing below it)
assert(P.frame._headerSep.shown == false, "separator hidden while collapsed")
assert(P.frame._headerBand.height == HEADER_H + PAD * 2 - 2, "band fills collapsed pill")

---------------------------------------------------------------------------
-- 3) Resize while collapsed is deferred, applied on expand
---------------------------------------------------------------------------
P.Resize(500, 600)
assert(P.frame.height == HEADER_H + PAD * 2, "resize deferred while collapsed")
P.collapseButton.scripts.OnClick(P.collapseButton)
assert(P.IsCollapsed() == false, "expanded again")
assert(P._contentWrapper.shown == true, "content wrapper shown")
assert(P.frame.width == 500 + PAD * 2, "deferred width applied on expand")
assert(P.frame.height == 600 + HEADER_H + PAD * 2, "deferred height applied on expand")

---------------------------------------------------------------------------
-- 4) Height cap: taller than window clamps to window height
---------------------------------------------------------------------------
P.Resize(300, 2000)
assert(P.frame.height == win.height, "height capped at window height")

---------------------------------------------------------------------------
-- 5) Collapsed state seeds from sessionState (theme-rebuild carry)
---------------------------------------------------------------------------
local carried = { collapsed = true }
local P2 = BuildPanel(NewWindow(), carried)
assert(P2.IsCollapsed() == true, "collapsed restored from session table")
assert(P2.frame.height == HEADER_H + PAD * 2, "restored panel builds collapsed")

---------------------------------------------------------------------------
-- 6) Collapsed width tracks the title (Party vs Raid titles differ)
---------------------------------------------------------------------------
P.collapseButton.scripts.OnClick(P.collapseButton)   -- collapse again
local LONG = "Preview - Raid 25 player layout"
P.SetTitle(LONG)
assert(P.frame.width == ExpectedCollapsedW(LONG, false), "collapsed width follows title")
assert(P.frame.width > COLLAPSED_MIN_W, "long title exceeds the floor")

---------------------------------------------------------------------------
-- 7) Detaching while collapsed makes room for the Dock button; redock shrinks
---------------------------------------------------------------------------
P.header.scripts.OnDragStart(P.header)
assert(P.IsDetached() == true, "detached")
assert(P.frame.width == ExpectedCollapsedW(LONG, true), "collapsed width includes Dock button")
P.Redock()
assert(P.frame.width == ExpectedCollapsedW(LONG, false), "width shrinks back on redock")

---------------------------------------------------------------------------
-- 8) Expanding restores the content width + the separator/band chrome
---------------------------------------------------------------------------
P.collapseButton.scripts.OnClick(P.collapseButton)
assert(P.IsCollapsed() == false, "expanded")
assert(P.frame.width == 300 + PAD * 2, "content width restored on expand")
assert(P.frame._headerSep.shown == true, "separator shown while expanded")
assert(P.frame._headerBand.height == HEADER_H + PAD - 1, "band back to header height")
-- A title change while expanded must NOT touch the panel size.
P.SetTitle("Preview - Party")
assert(P.frame.width == 300 + PAD * 2, "expanded width unaffected by title change")

---------------------------------------------------------------------------
-- 9) Redock re-measures BEFORE choosing a dock side. Window placed so the
--    narrow (docked) pill fits on the right but the wide (detached, Dock
--    button visible) one does not: reflowing on the stale width flips the
--    panel to the left dock it does not need.
---------------------------------------------------------------------------
local tight = NewWindow()
tight.left, tight.right, tight.top = 900, 1464, 900   -- 130px of screen to the right
tight.width, tight.height = 580, 850
local P3 = BuildPanel(tight, {})
P3.Show()
P3.Resize(300, 400)
P3.collapseButton.scripts.OnClick(P3.collapseButton)
local TIGHT_TITLE = "Preview Raid"                    -- 112px docked / 150px detached
P3.SetTitle(TIGHT_TITLE)
local NARROW, WIDE = ExpectedCollapsedW(TIGHT_TITLE, false), ExpectedCollapsedW(TIGHT_TITLE, true)
assert(NARROW < 130 and WIDE > 130,
    "fixture straddles the right-dock gap: narrow fits, wide does not")
P3.header.scripts.OnDragStart(P3.header)
assert(P3.frame.width == WIDE, "detached pill is the wide one")
P3.Redock()
assert(P3.frame.width == NARROW, "redocked pill re-measured narrow")
local point, relTo, relPoint = P3.frame:GetPoint(1)
assert(point == "TOPLEFT" and relTo == tight and relPoint == "TOPRIGHT",
    "redock picks the right dock using the post-redock width")

print("options_preview_panel_collapse_test: OK")
