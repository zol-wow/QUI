-- tests/unit/options_preview_panel_scale_test.lua
-- Run: lua tests/unit/options_preview_panel_scale_test.lua
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

local HEADER_H, PAD = 22, 8

local win = NewWindow()
local session = {}
local P = BuildPanel(win, session)
P.Show()

---------------------------------------------------------------------------
-- 1) contentHost is a scaled inner host, default scale 1
---------------------------------------------------------------------------
assert(P.contentHost ~= P._contentWrapper, "contentHost is the inner scaleHost")
assert(P.contentHost.parent == P._contentWrapper, "scaleHost parented to content wrapper")
assert(P.GetContentScale() == 1, "default scale 1")

---------------------------------------------------------------------------
-- 2) Panel size = content dims x scale (+ chrome); host SetScale applied
---------------------------------------------------------------------------
P.Resize(400, 600)
P.SetContentScale(0.5)
assert(P.contentHost.scale == 0.5, "scaleHost scaled")
assert(P.frame.width == 400 * 0.5 + PAD * 2, "width scaled")
assert(P.frame.height == 600 * 0.5 + HEADER_H + PAD * 2, "height scaled")

-- Later Resize (driver rebuild) keeps the session scale
P.Resize(500, 800)
assert(P.frame.width == 500 * 0.5 + PAD * 2, "resize respects current scale")

---------------------------------------------------------------------------
-- 3) Clamp 0.4 .. 1.25
---------------------------------------------------------------------------
P.SetContentScale(0.1)
assert(P.GetContentScale() == 0.4, "clamped low")
P.SetContentScale(9)
assert(P.GetContentScale() == 1.25, "clamped high")

---------------------------------------------------------------------------
-- 3b) A consumer may widen the clamp; the default stays 0.4 .. 1.25
---------------------------------------------------------------------------
local winZ = NewWindow()
gui.MainFrame = winZ
local PZ = FullSurface.CreateDockedPreviewPanel({
    gui = gui, window = winZ, minWidth = 140,
    controlStripHeight = 0, sessionState = {},
    scaleMin = 0.25, scaleMax = 3,
})
PZ.Show()
PZ.SetContentScale(9)
assert(PZ.GetContentScale() == 3,
    "scaleMax opt raises the ceiling, got " .. tostring(PZ.GetContentScale()))
PZ.SetContentScale(0.01)
assert(PZ.GetContentScale() == 0.25,
    "scaleMin opt lowers the floor, got " .. tostring(PZ.GetContentScale()))

---------------------------------------------------------------------------
-- 3c) defaultScale seeds a fresh session and is clamped to the panel's range
---------------------------------------------------------------------------
local winD = NewWindow()
gui.MainFrame = winD
local PD = FullSurface.CreateDockedPreviewPanel({
    gui = gui, window = winD, minWidth = 140,
    controlStripHeight = 0, sessionState = {},
    scaleMax = 3, defaultScale = 3,
})
assert(PD.GetContentScale() == 3,
    "defaultScale seeds a fresh session, got " .. tostring(PD.GetContentScale()))
assert(PD.contentHost.scale == 3, "seeded scale reaches the scaleHost")

local carried = { scale = 0.75 }
local PE = FullSurface.CreateDockedPreviewPanel({
    gui = gui, window = winD, minWidth = 140,
    controlStripHeight = 0, sessionState = carried,
    scaleMax = 3, defaultScale = 3,
})
assert(PE.GetContentScale() == 0.75,
    "defaultScale must not stomp a carried session scale, got " .. tostring(PE.GetContentScale()))

local PF = FullSurface.CreateDockedPreviewPanel({
    gui = gui, window = winD, minWidth = 140,
    controlStripHeight = 0, sessionState = {},
    defaultScale = 9,
})
assert(PF.GetContentScale() == 1.25,
    "defaultScale clamps to the panel range, got " .. tostring(PF.GetContentScale()))
gui.MainFrame = win

---------------------------------------------------------------------------
-- 4) MIN_W floor applies to the SCALED width
---------------------------------------------------------------------------
P.SetContentScale(0.4)
P.Resize(200, 300)   -- 200 * 0.4 = 80 < minWidth 140
assert(P.frame.width == 140 + PAD * 2, "MIN_W floor on scaled width")

---------------------------------------------------------------------------
-- 5) Scale survives rebuild via the SAME session table; detached does not
---------------------------------------------------------------------------
P.SetContentScale(0.75)
P.header.scripts.OnDragStart(P.header)   -- detach before "theme rebuild"
local P2 = BuildPanel(NewWindow(), session)
assert(P2.GetContentScale() == 0.75, "scale carried across rebuild")
assert(P2.contentHost.scale == 0.75, "carried scale applied to new scaleHost")
assert(P2.IsDetached() == false, "detach reset on rebuild")

---------------------------------------------------------------------------
-- 6) Grip drag: VERTICAL delta drives scale (panel height tracks
-- contentH*scale for both party and raid; width floors at MIN_W -- see
-- section 9). Exact inverse of ApplySize's height formula, so the grabbed
-- bottom edge follows the cursor. Reflow deferred to release.
-- chrome = HEADER_H + STRIP_H(0) + PAD*2 = 22 + 16 = 38.
---------------------------------------------------------------------------
local win3 = NewWindow()
local P3 = BuildPanel(win3, {})
P3.Show()
P3.Resize(400, 600)                  -- panel height = 600 + 38 = 638
assert(P3.grip, "grip exists")
assert(P3.grip.shown == true, "grip visible expanded")

local cursorX, cursorY = 0, 0
GetCursorPosition = function() return cursorX, cursorY end

cursorY = 1000
P3.grip.scripts.OnMouseDown(P3.grip, "LeftButton")
-- Reflow() always does ClearAllPoints() (a fresh {} table) + exactly one
-- SetPoint(), so its *length* is invariably 1 after any completed Reflow --
-- a count comparison can't distinguish "Reflow ran" from "it didn't". The
-- mock's ClearAllPoints reassigns self.points to a brand-new table object,
-- so object IDENTITY of the points table is a true signal: same reference =>
-- no Reflow; a new reference => ClearAllPoints (and therefore Reflow) ran.
local pointsBefore = P3.frame.points

-- drag DOWN 300px (WoW Y decreases downward): startH 638 -> 938,
-- scale = (938 - 38)/600 = 1.5 -> clamps to 1.25
cursorY = 1000 - 300
P3.grip.scripts.OnUpdate(P3.grip, 0.05)   -- past the 0.016 throttle
assert(P3.GetContentScale() == 1.25,
    "drag down grows scale (clamped high), got " .. tostring(P3.GetContentScale()))
assert(P3.frame.points == pointsBefore, "no Reflow during drag")

-- drag UP from the start point: startH 638, y = 1250 -> newH = 638 - 250 = 388,
-- scale = (388 - 38)/600 = 0.5833
cursorY = 1000 + 250
P3.grip.scripts.OnUpdate(P3.grip, 0.05)
local got = P3.GetContentScale()
assert(math.abs(got - 0.5833) < 0.01, "drag up shrinks scale, got " .. tostring(got))

P3.grip.scripts.OnMouseUp(P3.grip)
assert(P3.grip.scripts.OnUpdate == nil, "tracker removed on release")
assert(P3.frame.points ~= pointsBefore, "Reflow on release")

---------------------------------------------------------------------------
-- 7) Grip hidden while collapsed, restored on expand
---------------------------------------------------------------------------
P3.collapseButton.scripts.OnClick(P3.collapseButton)
assert(P3.grip.shown == false, "grip hidden collapsed")
P3.collapseButton.scripts.OnClick(P3.collapseButton)
assert(P3.grip.shown == true, "grip back on expand")

---------------------------------------------------------------------------
-- 8) Left-dock regression: when Reflow left-docks the panel (TOPRIGHT ->
-- window TOPLEFT, so the RIGHT edge is pinned), a naive SetSize would move
-- the opposite edge. The grip must re-pin the panel's TOP-LEFT for the drag
-- so the box grows down/right from a fixed top-left, regardless of dock side.
---------------------------------------------------------------------------
local winL = NewWindow()
winL.left, winL.right = 1400, 1550   -- narrow window pinned near right edge
local PL = BuildPanel(winL, {})
PL.Resize(120, 200)                  -- width max(120,140)+16 = 156; height 238
PL.Show()                            -- right dock 1550+6+156=1712 > 1600 fails
                                     -- -> left dock 1400-6-156=1238 >= 0 chosen
local dock = PL.frame.points[#PL.frame.points]
assert(dock.point == "TOPRIGHT" and dock.relPoint == "TOPLEFT", "panel left-docked")

cursorX, cursorY = 0, 1000
PL.grip.scripts.OnMouseDown(PL.grip, "LeftButton")
local pin = PL.frame.points[#PL.frame.points]
assert(pin.point == "TOPLEFT" and pin.relPoint == "TOPLEFT",
    "grip re-pins TOPLEFT for the drag (grabbed corner must track cursor when left-docked)")

-- Drag down grows scale even while left-docked. startH 238, y = 900 ->
-- newH = 338, scale = (338 - 38)/200 = 1.5 -> clamps to 1.25.
cursorY = 1000 - 100
PL.grip.scripts.OnUpdate(PL.grip, 0.05)
assert(PL.GetContentScale() > 1.0, "drag down grows scale while left-docked")
PL.grip.scripts.OnMouseUp(PL.grip)

---------------------------------------------------------------------------
-- 9) Production party-layout regression: minWidth=240 with a narrow party
-- roster (contentW ~150) keeps panel WIDTH pinned at the MIN_W floor (256)
-- across the WHOLE scale range, so a width-driven grip would sit frozen. The
-- grip must drive scale from the vertical axis -- the tall party layout's
-- height is the dimension that actually responds.
---------------------------------------------------------------------------
local winP = NewWindow()
local PP = FullSurface.CreateDockedPreviewPanel({
    gui = gui, window = winP, minWidth = 240,
    controlStripHeight = 0, sessionState = {},
})
PP.Show()
PP.Resize(150, 400)                  -- party: narrow (150) + tall (400)
assert(PP.frame.width == 240 + PAD * 2, "party width at MIN_W floor")
local floorW = PP.frame.width
local scale0 = PP.GetContentScale()

cursorX, cursorY = 0, 1000
PP.grip.scripts.OnMouseDown(PP.grip, "LeftButton")
cursorY = 1000 - 200                 -- drag down 200 -> scale grows
PP.grip.scripts.OnUpdate(PP.grip, 0.05)
assert(PP.GetContentScale() > scale0,
    "vertical drag scales party preview despite floored width")
assert(PP.frame.width == floorW,
    "panel width stays at floor while scaling (grip drives height, not width)")
PP.grip.scripts.OnMouseUp(PP.grip)

---------------------------------------------------------------------------
-- 10) Hide mid-drag cancels grip tracking: OnMouseUp may never fire if the
-- panel is torn down / hidden while the button is held. A stale OnUpdate must
-- not survive to resume when the frame is shown again.
---------------------------------------------------------------------------
local winH = NewWindow()
local PH = BuildPanel(winH, {})
PH.Show()
PH.Resize(400, 600)
cursorX, cursorY = 0, 1000
PH.grip.scripts.OnMouseDown(PH.grip, "LeftButton")
assert(PH.grip.scripts.OnUpdate ~= nil, "drag installed OnUpdate")
PH.Hide()                            -- panel hide mid-drag
assert(PH.grip.scripts.OnUpdate == nil, "hide cancels grip tracking")

---------------------------------------------------------------------------
-- 11) Capped-height regression: when ApplySize caps the panel to the window
-- height, panel:GetHeight() < contentH*scale + chrome. The grip must derive
-- the drag from the START scale, not the clamped live height -- otherwise a
-- held grip with zero cursor movement snaps the scale down on the first tick.
---------------------------------------------------------------------------
local winC = NewWindow()             -- height 850
local PC = BuildPanel(winC, {})
PC.Show()
PC.Resize(300, 800)                  -- contentH 800
PC.SetContentScale(1.25)             -- h = 800*1.25 + 38 = 1038 -> capped to 850
assert(PC.frame.height == winC.height, "panel height capped at window height")
local scaleBefore = PC.GetContentScale()
assert(scaleBefore == 1.25, "pre-grab scale is 1.25")

cursorX, cursorY = 0, 1000
PC.grip.scripts.OnMouseDown(PC.grip, "LeftButton")
PC.grip.scripts.OnUpdate(PC.grip, 0.05)   -- zero cursor movement
assert(PC.GetContentScale() == scaleBefore,
    "held grip does not jump scale when height was capped, got " .. tostring(PC.GetContentScale()))
PC.grip.scripts.OnMouseUp(PC.grip)

print("options_preview_panel_scale_test: OK")
