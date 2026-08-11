-- tests/unit/options_preview_panel_detach_test.lua
-- Run: lua tests/unit/options_preview_panel_detach_test.lua
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

---------------------------------------------------------------------------
-- 1) Default: docked right — first Reflow anchors TOPLEFT -> window TOPRIGHT
---------------------------------------------------------------------------
local win = NewWindow()
local P = BuildPanel(win, {})
assert(P, "panel built")
P.Show()
local p1 = P.frame.points[#P.frame.points]
assert(p1 and p1.point == "TOPLEFT" and p1.relTo == win and p1.relPoint == "TOPRIGHT",
    "docked right by default")
assert(P.IsDetached() == false, "starts docked")

---------------------------------------------------------------------------
-- 2) Drag header -> detached; window resize/move hooks no longer re-anchor
---------------------------------------------------------------------------
P.header.scripts.OnDragStart(P.header)
assert(P.IsDetached() == true, "drag sets detached")
assert(P.frame.movingCalls == 1, "StartMoving called")
P.header.scripts.OnDragStop(P.header)

-- Freeze-check: force geometry where an UNGUARDED Reflow would switch to a
-- DIFFERENT dock (left, relPoint TOPLEFT). With the guard, the anchor stays
-- frozen at the pre-detach dock-right tuple. Asserting the tuple (not just
-- the count) is what actually exercises `if session.detached then return end`.
local function lastPoint() return P.frame.points[#P.frame.points] end
local frozen = lastPoint()
assert(frozen.relPoint == "TOPRIGHT", "pre-detach docked right")
-- Narrow window pinned to the right edge: right dock no longer fits
-- (1550+6+156 > 1600) but left dock does (1450-6-156 >= 0) -> unguarded
-- Reflow would pick relPoint TOPLEFT.
win.left, win.right = 1450, 1550
win.hooks.OnSizeChanged(win)          -- window resized
win.StopMovingOrSizing(win)           -- window dragged (hooksecurefunc path)
P.frame.hooks.OnShow(P.frame)         -- tab switch re-show
local after = lastPoint()
assert(after.relPoint == "TOPRIGHT" and after.x == frozen.x,
    "Reflow guard: anchor frozen while detached (would flip to TOPLEFT if guard missing)")

-- Restore window geometry so later sections' dock-right expectations still hold.
win.left, win.right = 100, 700

---------------------------------------------------------------------------
-- 3) Re-dock button: shown only while detached; click restores dock anchor
---------------------------------------------------------------------------
assert(P.dockButton.shown == true, "dock button visible while detached")
P.dockButton.scripts.OnClick(P.dockButton)
assert(P.IsDetached() == false, "re-dock clears flag")
local p2 = P.frame.points[#P.frame.points]
assert(p2 and p2.point == "TOPLEFT" and p2.relPoint == "TOPRIGHT", "re-docked right")
assert(P.dockButton.shown == false, "dock button hidden while docked")

---------------------------------------------------------------------------
-- 4) Session reset: window OnHide clears detach; next show re-docks
---------------------------------------------------------------------------
P.header.scripts.OnDragStart(P.header)
assert(P.IsDetached() == true)
win:Hide()
assert(P.IsDetached() == false, "window close clears detach")

print("options_preview_panel_detach_test: OK")
