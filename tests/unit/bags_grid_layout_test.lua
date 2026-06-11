-- tests/unit/bags_grid_layout_test.lua
-- Run: lua tests/unit/bags_grid_layout_test.lua
local ns = {}
local chunk = assert(loadfile("QUI_Bags/bags/views/grid_layout.lua"))
chunk("QUI", ns)
local Grid = ns.Bags.GridLayout

-- Test 1: basic placement, row-major, top-left origin, y grows downward
local pos = Grid.Compute(5, { columns = 2, iconSize = 30, spacing = 4 })
assert(pos.width == 2 * 30 + 1 * 4, "width wrong: " .. pos.width)
assert(pos.height == 3 * 30 + 2 * 4, "height wrong: " .. pos.height)
assert(pos[1].x == 0 and pos[1].y == 0, "slot 1 wrong")
assert(pos[2].x == 34 and pos[2].y == 0, "slot 2 wrong")
assert(pos[3].x == 0 and pos[3].y == -34, "slot 3 wrong (rows go down)")
assert(pos[5].x == 0 and pos[5].y == -68, "slot 5 wrong")

-- Test 2: exact row fit
local pos2 = Grid.Compute(4, { columns = 2, iconSize = 30, spacing = 4 })
assert(pos2.height == 2 * 30 + 1 * 4, "exact fit height wrong")

-- Test 3: fewer items than columns shrinks width to actual usage? NO —
-- width stays columns-based for stable window size
local pos3 = Grid.Compute(1, { columns = 12, iconSize = 36, spacing = 4 })
assert(pos3.width == 12 * 36 + 11 * 4, "width must be column-stable")
assert(pos3.height == 36, "single row height wrong")

-- Test 4: zero items
local pos4 = Grid.Compute(0, { columns = 12, iconSize = 36, spacing = 4 })
assert(pos4.width > 0 and pos4.height == 0, "zero-item layout wrong")

-- Test 5: defensive config clamps
local pos5 = Grid.Compute(3, { columns = 0, iconSize = 36, spacing = 4 })
assert(pos5[3] ~= nil, "columns=0 must clamp, not crash")

print("OK: bags_grid_layout_test")
