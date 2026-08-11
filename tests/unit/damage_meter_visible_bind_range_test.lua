-- tests/unit/damage_meter_visible_bind_range_test.lua
-- Run: lua tests/unit/damage_meter_visible_bind_range_test.lua
--
-- Standalone tests for ComputeVisibleBindRange — the pure helper that maps
-- scroll offset + viewport height to the inclusive pooled-row range the
-- window must BIND. Off-screen pooled rows are hidden, not re-styled: the
-- old Refresh re-ran _SetRowSource across all 40 pool rows every data tick.
-- Partially clipped rows count as visible (ceil on the bottom edge) so a
-- half-row at the viewport bottom always carries live data. Degenerate
-- geometry (unlaid-out viewport, zero pitch) fails OPEN to the full range —
-- stale rows are worse than an oversized bind.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")
local chunk = src:match("(local function ComputeVisibleBindRange.-\nend\n)")
assert(chunk, "could not locate ComputeVisibleBindRange in damage_meter.lua")
local ComputeVisibleBindRange =
    assert(loadstring(chunk .. "\nreturn ComputeVisibleBindRange"))()

-- pitch 20 (barH 18 + gap 2), pool-capped total 40 unless stated.

-- Case 1: top of list, viewport exactly 10 rows.
do
    local first, last = ComputeVisibleBindRange(0, 200, 20, 40)
    assert(first == 1 and last == 10, "unscrolled exact fit binds rows 1-10")
end

-- Case 2: partial row at the bottom edge counts (ceil).
do
    local first, last = ComputeVisibleBindRange(0, 205, 20, 40)
    assert(first == 1 and last == 11, "half-clipped bottom row must bind")
end

-- Case 3: mid-scroll — partially scrolled-off top row still binds (floor).
do
    local first, last = ComputeVisibleBindRange(45, 200, 20, 40)
    assert(first == 3 and last == 13, "mid-scroll binds rows 3-13")
end

-- Case 4: clamped at the end of the list.
do
    local first, last = ComputeVisibleBindRange(700, 200, 20, 40)
    assert(first == 36 and last == 40, "tail scroll clamps last to total")
end

-- Case 5: over-scrolled past content (transient before the clamp elsewhere).
do
    local first, last = ComputeVisibleBindRange(1000, 200, 20, 40)
    assert(first == 40 and last == 40, "over-scroll degrades to last row")
end

-- Case 6: fail-open on degenerate geometry.
do
    local f1, l1 = ComputeVisibleBindRange(0, 0, 20, 40)
    assert(f1 == 1 and l1 == 40, "zero viewport binds everything")
    local f2, l2 = ComputeVisibleBindRange(0, 200, 0, 40)
    assert(f2 == 1 and l2 == 40, "zero pitch binds everything")
    local f3, l3 = ComputeVisibleBindRange(nil, nil, 20, 40)
    assert(f3 == 1 and l3 == 40, "nil geometry binds everything")
end

-- Case 7: empty list -> empty range (first > last).
do
    local first, last = ComputeVisibleBindRange(0, 200, 20, 0)
    assert(first == 1 and last == 0, "no sources -> nothing to bind")
end

-- Case 8: negative scroll treated as 0.
do
    local first, last = ComputeVisibleBindRange(-5, 200, 20, 40)
    assert(first == 1 and last == 10, "negative scroll clamps to top")
end

-- Wiring: the window binds through _BindVisibleRows; the old unconditional
-- 40-row loop is gone from Refresh.
assert(src:find("function Window:_BindVisibleRows", 1, true),
    "Window:_BindVisibleRows must be defined")
assert(src:find("ComputeVisibleBindRange(scrollY, viewH", 1, true),
    "_BindVisibleRows must compute the range via ComputeVisibleBindRange")
assert(not src:find("for i = 1, renderCount do\n        self:_SetRowSource", 1, true),
    "Refresh must not bind the full pool unconditionally")

-- Wiring: scroll and viewport-resize re-bind without waiting for a data tick.
local wheel = src:match('SetScript%("OnMouseWheel",%s*function%(sf, delta%)(.-)\n    end%)')
assert(wheel, "could not extract OnMouseWheel handler")
assert(wheel:find("_BindVisibleRows", 1, true),
    "OnMouseWheel must re-bind newly revealed rows")
local sized = src:match('SetScript%("OnSizeChanged",%s*function%(_, w%)(.-)\n    end%)')
assert(sized, "could not extract OnSizeChanged handler")
assert(sized:find("_BindVisibleRows", 1, true),
    "OnSizeChanged must re-bind after viewport resize")

print("OK: damage_meter_visible_bind_range_test")
