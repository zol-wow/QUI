-- tests/unit/cdm_reanchor_overlayrect_test.lua
-- Run: lua tests/unit/cdm_reanchor_overlayrect_test.lua
-- G9 Task B1: OverlayRect generalizes the two-point overlay so a Blizzard CDM frame
-- can be pinned to an ARBITRARY relative frame (the QUI container) at computed slot
-- corners -- not just onto a per-slot shell at zero offset. Overlay stays a thin,
-- byte-identical wrapper; the anchor guard re-asserts the stored RECT.
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

local function newRecordingFrame(sink)
    local f = {}
    f.ClearAllPoints = function() sink[#sink + 1] = { op = "clear" } end
    f.SetPoint = function(self, point, rel, relPoint, x, y)
        sink[#sink + 1] = { op = "set", point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end
    return f
end

-- raw setters delegate to the (hookable) frame methods so the guard's own re-anchor
-- flows through the same SetPoint path, exercising the recursion guard.
local function newRaw(alphaSink)
    return {
        ClearAllPoints = function(f) f:ClearAllPoints() end,
        SetPoint = function(f, p, rel, rp, x, y) f:SetPoint(p, rel, rp, x, y) end,
        SetAlpha = function(_, a) if alphaSink then alphaSink[#alphaSink + 1] = a end end,
    }
end

------------------------------------------------------------------------
-- (a) OverlayRect pins the two computed corners to the container with the
--     given rel-points/offsets, and records the full rect on frame data.
------------------------------------------------------------------------
do
    local calls = {}
    local frame = newRecordingFrame(calls)
    local container = {}
    local bridge = CDMReanchor.New({ raw = newRaw(), securecall = function(fn, ...) return fn(...) end })

    bridge:OverlayRect(frame, container, "TOPLEFT", 4, -6, "TOPLEFT", 44, -46)

    -- Two-point pin: TOPLEFT and BOTTOMRIGHT of the frame, both relative to the container.
    local sets = {}
    local sawClear = false
    for _, c in ipairs(calls) do
        if c.op == "clear" then sawClear = true end
        if c.op == "set" then sets[c.point] = c end
    end
    assert(sawClear, "OverlayRect clears points before re-pinning")
    assert(sets.TOPLEFT, "OverlayRect pins the TOPLEFT corner")
    assert(sets.BOTTOMRIGHT, "OverlayRect pins the BOTTOMRIGHT corner")
    assert(sets.TOPLEFT.rel == container and sets.BOTTOMRIGHT.rel == container,
        "OverlayRect pins BOTH corners to the given relative frame (container)")
    assert(sets.TOPLEFT.relPoint == "TOPLEFT" and sets.TOPLEFT.x == 4 and sets.TOPLEFT.y == -6,
        "OverlayRect uses the TL rel-point + offsets verbatim")
    assert(sets.BOTTOMRIGHT.relPoint == "TOPLEFT" and sets.BOTTOMRIGHT.x == 44 and sets.BOTTOMRIGHT.y == -46,
        "OverlayRect uses the BR rel-point + offsets verbatim (arbitrary corner, not just BOTTOMRIGHT/0/0)")

    -- Full rect recorded on external frame data + claim/anchor bookkeeping.
    local fd = bridge:GetData(frame)
    assert(fd.claimedBy == container, "OverlayRect claims the frame for the container")
    assert(fd.overlayAnchor == container, "OverlayRect stamps overlayAnchor = container (guard self-call/unclaimed logic)")
    assert(fd.sunk == nil, "OverlayRect un-sinks the frame")
    local r = fd.overlayRect
    assert(type(r) == "table", "OverlayRect records fd.overlayRect")
    assert(r.relativeTo == container, "rect.relativeTo == container")
    assert(r.tlRelPoint == "TOPLEFT" and r.tlX == 4 and r.tlY == -6, "rect stores TL rel-point + offsets")
    assert(r.brRelPoint == "TOPLEFT" and r.brX == 44 and r.brY == -46, "rect stores BR rel-point + offsets")
    assert(frame.overlayRect == nil and frame.claimedBy == nil, "OverlayRect writes NO state onto the Blizzard frame")
end

------------------------------------------------------------------------
-- (a2) Re-claiming a previously sunk frame restores visibility. Sink uses
--      alpha-0 for unclaimed pool frames; the bridge's claim primitive must
--      own the matching alpha-1 restore so active BuffIcon frames can reappear.
------------------------------------------------------------------------
do
    local calls = {}
    local alpha = {}
    local frame = newRecordingFrame(calls)
    local container = {}
    local bridge = CDMReanchor.New({ raw = newRaw(alpha), securecall = function(fn, ...) return fn(...) end })

    bridge:Sink(frame)
    bridge:OverlayRect(frame, container, "TOPLEFT", 0, 0, "BOTTOMRIGHT", 10, -10)

    local sawAlpha0, sawAlpha1 = false, false
    for _, a in ipairs(alpha) do
        if a == 0 then sawAlpha0 = true end
        if a == 1 then sawAlpha1 = true end
    end
    assert(sawAlpha0, "setup sanity: Sink alpha-hides the frame")
    assert(sawAlpha1, "OverlayRect restores alpha 1 when re-claiming a sunk frame")
end

------------------------------------------------------------------------
-- (b) REGRESSION LOCK: Overlay stays byte-identical -- TL->anchor TOPLEFT 0,0
--     and BR->anchor BOTTOMRIGHT 0,0, same fd fields.
------------------------------------------------------------------------
do
    local calls = {}
    local frame = newRecordingFrame(calls)
    local anchor = {}
    local bridge = CDMReanchor.New({ raw = newRaw(), securecall = function(fn, ...) return fn(...) end })

    bridge:Overlay(frame, anchor)

    local sets = {}
    for _, c in ipairs(calls) do
        if c.op == "set" then sets[c.point] = c end
    end
    assert(sets.TOPLEFT and sets.TOPLEFT.rel == anchor and sets.TOPLEFT.relPoint == "TOPLEFT"
        and sets.TOPLEFT.x == 0 and sets.TOPLEFT.y == 0,
        "Overlay legacy: TOPLEFT->anchor TOPLEFT 0,0")
    assert(sets.BOTTOMRIGHT and sets.BOTTOMRIGHT.rel == anchor and sets.BOTTOMRIGHT.relPoint == "BOTTOMRIGHT"
        and sets.BOTTOMRIGHT.x == 0 and sets.BOTTOMRIGHT.y == 0,
        "Overlay legacy: BOTTOMRIGHT->anchor BOTTOMRIGHT 0,0")

    local fd = bridge:GetData(frame)
    assert(fd.claimedBy == anchor, "Overlay legacy: claimedBy = anchor")
    assert(fd.overlayAnchor == anchor, "Overlay legacy: overlayAnchor = anchor")
    assert(fd.sunk == nil, "Overlay legacy: sunk cleared")
end

------------------------------------------------------------------------
-- (c) Guard re-asserts the stored RECT (not shell zero-offset points) when
--     Blizzard SetPoints the frame to a different relativeTo, and ignores our
--     own container-relative calls.
------------------------------------------------------------------------
do
    local calls = {}
    local frame = newRecordingFrame(calls)
    local container = {}
    local bridge = CDMReanchor.New({ raw = newRaw(), securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = hooksecurefunc })

    bridge:InstallAnchorGuard(frame)
    bridge:OverlayRect(frame, container, "TOPLEFT", 4, -6, "TOPLEFT", 44, -46)

    -- Blizzard's Layout re-anchors the frame to its viewer grid (a foreign relativeTo).
    local blizzViewer = {}
    frame:SetPoint("CENTER", blizzViewer, "CENTER", 0, 0)

    -- The guard must re-assert the stored RECT, NOT the shell zero-offset points.
    local sets = {}
    for _, c in ipairs(calls) do
        if c.op == "set" and c.rel == container then sets[c.point] = c end
    end
    assert(sets.TOPLEFT and sets.TOPLEFT.x == 4 and sets.TOPLEFT.y == -6 and sets.TOPLEFT.relPoint == "TOPLEFT",
        "guard re-asserts the stored TL rect corner (offsets 4,-6) after a foreign re-point")
    assert(sets.BOTTOMRIGHT and sets.BOTTOMRIGHT.x == 44 and sets.BOTTOMRIGHT.y == -46
        and sets.BOTTOMRIGHT.relPoint == "TOPLEFT",
        "guard re-asserts the stored BR rect corner (offsets 44,-46) after a foreign re-point")

    -- Our own container-relative SetPoint calls must be ignored (no runaway recursion).
    local before = #calls
    frame:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -6)
    assert(#calls - before <= 1, "guard ignores our own container-relative call (self-call detection == rect.relativeTo)")
end

------------------------------------------------------------------------
-- (d) Unclaimed still hides via SetAlpha(0).
------------------------------------------------------------------------
do
    local calls = {}
    local alpha = {}
    local frame = newRecordingFrame(calls)
    local bridge = CDMReanchor.New({ raw = newRaw(alpha), securecall = function(fn, ...) return fn(...) end,
        hooksecurefunc = hooksecurefunc })

    bridge:GetData(frame).overlayAnchor = nil   -- explicitly unclaimed, no rect
    bridge:InstallAnchorGuard(frame)
    frame:SetPoint("CENTER", {}, "CENTER", 0, 0)

    local sawAlpha0 = false
    for _, a in ipairs(alpha) do if a == 0 then sawAlpha0 = true end end
    assert(sawAlpha0, "guard SetAlpha(0)s an unclaimed re-anchored frame (rect + legacy both absent)")
end

print("OK: cdm_reanchor_overlayrect_test")
