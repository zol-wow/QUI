-- tests/unit/pin_frame_to_target_absolute_test.lua
-- Run: lua tests/unit/pin_frame_to_target_absolute_test.lua
local ns = {}
_G.UIParent = {
  GetEffectiveScale = function() return 1 end,
}

-- issecretvalue: treat a marker table {secret=true} as secret.
_G.issecretvalue = function(v) return type(v) == "table" and v.secret == true end

-- LibStub stub required by core/utils.lua
_G.LibStub = function() return nil end

-- Load the real core/utils.lua (injects Helpers into ns)
assert(loadfile("core/utils.lua"))("QUI", ns)
local Helpers = ns.Helpers

-- Helper to build a frame mock that records SetPoint calls the way
-- Helpers.BaseSetPoint expects: it tries frame.SetPointBase then frame.SetPoint.
-- GetNumPoints/GetPoint reflect the last SetPoint so the idempotency guard works.
local function makeFrame()
  local f = {}
  f._setPointCount = 0
  f.SetPoint = function(self, pt, rel, relPt, x, y)
    self._points = { pt = pt, rel = rel, relPt = relPt, x = x, y = y }
    self._setPointCount = self._setPointCount + 1
  end
  f.ClearAllPoints = function(self) self._points = nil end
  f.GetNumPoints = function(self)
    return self._points and 1 or 0
  end
  f.GetPoint = function(self, idx)
    if idx == 1 and self._points then
      local p = self._points
      return p.pt, p.rel, p.relPt, p.x, p.y
    end
  end
  return f
end

local function makeTarget(l, b, w, h, scale)
  return {
    GetLeft = function() return l end,
    GetRight = function() return l + w end,
    GetTop = function() return b + h end,
    GetBottom = function() return b end,
    GetEffectiveScale = function() return scale or 1 end,
  }
end

-- 1. CENTER→CENTER pin: source CENTER lands on target center + offset.
local frame = makeFrame()
local target = makeTarget(100, 200, 40, 20, 1)  -- center = (120, 210)
local ok = Helpers.PinFrameToTargetAbsolute(frame, "CENTER", target, "CENTER", 5, -5)
assert(ok == true, "expected pin success")
assert(frame._points.rel == _G.UIParent, "must anchor to UIParent, not target")
assert(frame._points.relPt == "BOTTOMLEFT", "must use BOTTOMLEFT origin")
assert(frame._points.x == 125, "x = centerX(120)+offset(5)")
assert(frame._points.y == 205, "y = centerY(210)+offset(-5)")

-- 2. Corner point: BOTTOMLEFT of target.
local f2, t2 = makeFrame(), makeTarget(100, 200, 40, 20, 1)
assert(Helpers.PinFrameToTargetAbsolute(f2, "BOTTOMLEFT", t2, "BOTTOMLEFT", 0, 0))
assert(f2._points.x == 100 and f2._points.y == 200, "BOTTOMLEFT corner")

-- 3. Scale normalization: target at 2x, UIParent at 1x → coords doubled.
local f3, t3 = makeFrame(), makeTarget(100, 200, 40, 20, 2)  -- center 120,210 * 2
assert(Helpers.PinFrameToTargetAbsolute(f3, "CENTER", t3, "CENTER", 0, 0))
assert(f3._points.x == 240 and f3._points.y == 420, "scale-normalized")

-- 4. Secret rect → no pin, returns false, frame untouched.
local f4 = makeFrame()
local tSecret = makeTarget(100, 200, 40, 20, 1)
tSecret.GetLeft = function() return { secret = true } end
assert(Helpers.PinFrameToTargetAbsolute(f4, "CENTER", tSecret, "CENTER", 0, 0) == false)
assert(f4._points == nil, "secret read must not move the frame")

-- 5. Nil rect (unanchored target) → no pin.
local f5 = makeFrame()
local tNil = makeTarget(100, 200, 40, 20, 1)
tNil.GetRight = function() return nil end
assert(Helpers.PinFrameToTargetAbsolute(f5, "CENTER", tNil, "CENTER", 0, 0) == false)
assert(f5._points == nil, "nil read must not move the frame")

-- 6. Missing args → false, no throw.
assert(Helpers.PinFrameToTargetAbsolute(nil, "CENTER", target, "CENTER", 0, 0) == false)
assert(Helpers.PinFrameToTargetAbsolute(frame, "CENTER", nil, "CENTER", 0, 0) == false)

-- 7. Idempotency: stationary target → SetPoint called exactly once on second call.
do
  local fi = makeFrame()
  local ti = makeTarget(100, 200, 40, 20, 1)  -- center = (120, 210)
  local ok1, px1, py1 = Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(ok1 == true, "idempotency first call must succeed")
  assert(fi._setPointCount == 1, "first call must invoke SetPoint once")
  local ok2, px2, py2 = Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(ok2 == true, "idempotency second call must return true")
  assert(fi._setPointCount == 1, "second call on stationary target must NOT invoke SetPoint again")
  assert(px1 == px2 and py1 == py2, "both calls must return identical px,py")
end

-- 8. Idempotency: moving target → SetPoint called again after target moves.
do
  local fi = makeFrame()
  local l, b = 100, 200
  local ti = {
    GetLeft          = function() return l end,
    GetRight         = function() return l + 40 end,
    GetTop           = function() return b + 20 end,
    GetBottom        = function() return b end,
    GetEffectiveScale = function() return 1 end,
  }
  -- First pin (stationary)
  local ok1 = Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(ok1 == true, "moving-target first pin must succeed")
  assert(fi._setPointCount == 1, "first pin must call SetPoint once")
  -- Second call, same position → no-op
  Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(fi._setPointCount == 1, "same position must still be a no-op")
  -- Move target and call again → must re-pin
  l, b = 300, 400
  local ok3 = Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(ok3 == true, "re-pin after target move must succeed")
  assert(fi._setPointCount == 2, "moved target must trigger a second SetPoint call")
end

-- 9. Idempotency guard: GetPoint returns secret coords → fall through and apply.
do
  local fi = makeFrame()
  local ti = makeTarget(100, 200, 40, 20, 1)
  -- First pin to set a known position.
  Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(fi._setPointCount == 1)
  -- Poison the GetPoint return so x is secret; guard must fall through.
  fi.GetPoint = function(self, idx)
    return "CENTER", _G.UIParent, "BOTTOMLEFT", { secret = true }, { secret = true }
  end
  Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(fi._setPointCount == 2, "secret coords in GetPoint must fall through to re-apply")
end

-- 10. Idempotency guard: GetNumPoints == 0 → no skip attempt, apply normally.
do
  local fi = makeFrame()
  fi.GetNumPoints = function() return 0 end  -- override: always 0 points
  local ti = makeTarget(100, 200, 40, 20, 1)
  Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(fi._setPointCount == 1, "GetNumPoints==0 first call must still apply")
  Helpers.PinFrameToTargetAbsolute(fi, "CENTER", ti, "CENTER", 0, 0)
  assert(fi._setPointCount == 2, "GetNumPoints==0 always falls through, no idempotency skip")
end

-- FrameIsProtected test cases
-- 1. nil frame -> false
assert(Helpers.FrameIsProtected(nil) == false, "nil frame")

-- 2. frame with no IsProtected method -> false
assert(Helpers.FrameIsProtected({}) == false, "no IsProtected method")

-- 3. frame:IsProtected() returns true -> true
assert(Helpers.FrameIsProtected({ IsProtected = function() return true end }) == true, "protected")

-- 4. frame:IsProtected() returns false -> false
assert(Helpers.FrameIsProtected({ IsProtected = function() return false end }) == false, "not protected")

-- 5. frame:IsProtected() returns a secret value -> false
assert(Helpers.FrameIsProtected({ IsProtected = function() return { secret = true } end }) == false, "secret return")

-- 6. frame:IsProtected() raises an error (pcall fails) -> false
assert(Helpers.FrameIsProtected({ IsProtected = function() error("boom") end }) == false, "errors -> false")

-- FrameIsAnchoringRestricted test cases (companion query; catches the dependent
-- case where a frame hosts protected anchor-children but IsProtected stays false)
assert(Helpers.FrameIsAnchoringRestricted(nil) == false, "ar: nil frame")
assert(Helpers.FrameIsAnchoringRestricted({}) == false, "ar: no method")
assert(Helpers.FrameIsAnchoringRestricted({ IsAnchoringRestricted = function() return true end }) == true, "ar: restricted")
assert(Helpers.FrameIsAnchoringRestricted({ IsAnchoringRestricted = function() return false end }) == false, "ar: not restricted")
assert(Helpers.FrameIsAnchoringRestricted({ IsAnchoringRestricted = function() return { secret = true } end }) == false, "ar: secret -> false")
assert(Helpers.FrameIsAnchoringRestricted({ IsAnchoringRestricted = function() error("boom") end }) == false, "ar: errors -> false")

print("PASS pin_frame_to_target_absolute_test")
