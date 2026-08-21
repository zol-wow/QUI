-- tests/unit/cdm_reanchor_guard_test.lua
-- Run: lua tests/unit/cdm_reanchor_guard_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor.lua", "cdm_reanchor.lua")("QUI", ns)
local CDMReanchor = assert(ns.CDMReanchor)

-- hooksecurefunc stub: wraps owner[method] so the hook runs AFTER the original.
local function hooksecurefunc(owner, method, hook)
    local original = owner[method] or function() end
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

-- A frame whose SetPoint records calls and is hookable.
local container = {}
local setCalls = {}
local frame = {}
frame.ClearAllPoints = function() end
frame.SetPoint = function(self, point, rel, relPoint, x, y)
    setCalls[#setCalls+1] = { point = point, rel = rel, x = x, y = y }
end

-- raw methods delegate to the (hooked) frame methods so the guard's own re-anchor
-- goes through the same SetPoint path, exercising the recursion guard.
local raw = {
    ClearAllPoints = function(f) f:ClearAllPoints() end,
    SetPoint = function(f, p, rel, rp, x, y) f:SetPoint(p, rel, rp, x, y) end,
    SetAlpha = function() end,
}
local bridge = CDMReanchor.New({ raw = raw, securecall = function(fn, ...) return fn(...) end, hooksecurefunc = hooksecurefunc })

-- container stands in for the QUI chrome-shell anchor icon.
bridge:InstallAnchorGuard(frame)
bridge:Overlay(frame, container)
-- Overlay stamps a two-point stretch: TOPLEFT->TL + BOTTOMRIGHT->BR, both onto the anchor.
local afterOverlay = #setCalls
assert(afterOverlay >= 2, "overlay stamps two corner anchors")

-- Blizzard re-points the frame to a foreign relative frame:
local blizzGrid = {}
frame:SetPoint("CENTER", blizzGrid, "CENTER", 0, 0)

-- The guard must have re-forced our two-point overlay (TOPLEFT + BOTTOMRIGHT onto the anchor).
local n = #setCalls
local c1, c2 = setCalls[n - 1], setCalls[n]
assert(c1.rel == container and c2.rel == container,
    "guard re-forces our two-point anchor after a foreign re-point")
local pts = { [c1.point] = true, [c2.point] = true }
assert(pts.TOPLEFT and pts.BOTTOMRIGHT, "guard restores both corner anchors")
assert(c1.x == 0 and c1.y == 0 and c2.x == 0 and c2.y == 0, "two-point overlay uses zero offsets")

-- Our own re-anchor (rel == anchor) must NOT recurse infinitely.
local before = #setCalls
frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
assert(#setCalls - before <= 2, "guard ignores our own anchor calls (no runaway recursion)")

-- Installing twice does not double-hook: one corrective pass = exactly two SetPoint.
local n1 = #setCalls
bridge:InstallAnchorGuard(frame)
frame:SetPoint("LEFT", blizzGrid, "LEFT", 0, 0)
local corrections = 0
for i = n1 + 1, #setCalls do if setCalls[i].rel == container then corrections = corrections + 1 end end
assert(corrections == 2, "guard installs at most once per frame (single two-point correction)")

-- Task 2: park is retired -> the anchor guard hides a SUNK re-anchored frame
-- in place via SetAlpha(0) (taint-safe), and NEVER writes strata/level on the live frame.
do
    local calls = {}
    local function rec(name) return function(_, ...) calls[#calls + 1] = { name, ... } end end
    local f2 = {}
    f2.ClearAllPoints = function() end
    f2.SetPoint = function(_, ...) calls[#calls + 1] = { "SetPoint", ... } end
    local raw2 = {
        ClearAllPoints = function() end,
        SetPoint = function() end,
        SetAlpha = function(_, a) calls[#calls + 1] = { "SetAlpha", a } end,
        SetFrameStrata = rec("SetFrameStrata"),
        SetFrameLevel = rec("SetFrameLevel"),
    }
    local b2 = CDMReanchor.New({ raw = raw2, securecall = function(fn, ...) return fn(...) end, hooksecurefunc = hooksecurefunc })
    b2:Sink(f2)
    b2:InstallAnchorGuard(f2)
    -- Blizzard re-anchors the sunk frame to its own grid:
    f2:SetPoint("CENTER", {}, "CENTER", 0, 0)
    local sawAlpha0 = false
    for _, c in ipairs(calls) do
        if c[1] == "SetAlpha" and c[2] == 0 then sawAlpha0 = true end
        assert(c[1] ~= "SetFrameStrata", "guard never SetFrameStrata on an unclaimed frame")
        assert(c[1] ~= "SetFrameLevel", "guard never SetFrameLevel on an unclaimed frame")
    end
    assert(sawAlpha0, "guard preserves alpha-0 for a sunk re-anchored frame")
end

do
    local calls = {}
    local frame = {}
    frame.ClearAllPoints = function() end
    frame.SetPoint = function() end
    local raw = {
        ClearAllPoints = function() end,
        SetPoint = function() end,
        SetAlpha = function(_, a) calls[#calls + 1] = a end,
    }
    local bridge = CDMReanchor.New({ raw = raw, securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = hooksecurefunc })
    bridge:InstallAnchorGuard(frame)
    frame:SetPoint("CENTER", {}, "CENTER", 0, 0)
    assert(#calls == 0, "newly acquired native frame is not alpha-hidden before claim")
end

-- Task 2: Sink no longer touches SetIgnoreParentAlpha (the lift it used to clear is
-- gone) -- that dead, forbidden live-frame state write is removed.
do
    local sawIPA = false
    local raw3 = {
        ClearAllPoints = function() end,
        SetPoint = function() end,
        SetAlpha = function() end,
        SetIgnoreParentAlpha = function() sawIPA = true end,
    }
    local b3 = CDMReanchor.New({ raw = raw3, securecall = function(fn, ...) return fn(...) end })
    b3:Sink({})
    assert(not sawIPA, "Sink makes no SetIgnoreParentAlpha call on the live frame")
end

print("OK: cdm_reanchor_guard_test")
