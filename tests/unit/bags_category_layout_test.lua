-- tests/unit/bags_category_layout_test.lua
-- Run: lua tests/unit/bags_category_layout_test.lua
-- The category layout engine (PURE): Categorize (ItemClass → bucket),
-- Group (ordered buckets, recent first / junk last, in-bucket sort), and
-- Compute (stacked per-category grids with header rows; same TOPLEFT
-- coordinate contract as GridLayout).
-- ItemClass EnumValues per ItemConstantsDocumentation.lua:199 —
-- Consumable=0, Container=1, Weapon=2, Gem=3, Armor=4, Reagent=5,
-- Tradegoods=7, Recipe=9, Questitem=12, Key=13, Miscellaneous=15,
-- Battlepet=17, Profession=19.
local ns = {}
assert(loadfile("QUI_Bags/bags/views/grid_layout.lua"))("QUI", ns)
local chunk = assert(loadfile("QUI_Bags/bags/views/category_layout.lua"))
chunk("QUI", ns)
local CL = ns.Bags.CategoryLayout
assert(CL and type(CL.Categorize) == "function", "CategoryLayout.Categorize must be exported")

-- Categorize: classID → bucket; junk quality outranks class; nil → misc
assert(CL.Categorize({ classID = 2, quality = 3 }) == "equipment", "weapons are equipment")
assert(CL.Categorize({ classID = 4, quality = 2 }) == "equipment", "armor is equipment")
assert(CL.Categorize({ classID = 0, quality = 1 }) == "consumables", "consumables bucket")
assert(CL.Categorize({ classID = 7, quality = 1 }) == "trade", "trade goods bucket")
assert(CL.Categorize({ classID = 5, quality = 1 }) == "trade", "reagents fold into trade")
assert(CL.Categorize({ classID = 19, quality = 1 }) == "trade", "profession items fold into trade")
assert(CL.Categorize({ classID = 12, quality = 1 }) == "quest", "quest items bucket")
assert(CL.Categorize({ classID = 13, quality = 1 }) == "quest", "keys fold into quest")
assert(CL.Categorize({ classID = 9, quality = 1 }) == "recipes", "recipes bucket")
assert(CL.Categorize({ classID = 17, quality = 1 }) == "battlepets", "battle pets bucket")
assert(CL.Categorize({ classID = 4, quality = 0 }) == "junk", "gray quality outranks class")
assert(CL.Categorize({ classID = 1, quality = 1 }) == "misc", "containers land in misc")
assert(CL.Categorize({ classID = 15, quality = 1 }) == "misc", "miscellaneous bucket")
assert(CL.Categorize(nil) == "misc", "pending details land in misc")

-- Group: ordered buckets (recent first, junk last), empty buckets omitted,
-- empty slots dropped, in-bucket sort quality desc → name asc → itemID asc.
local cells = {
    { bagID = 0, slot = 1, entry = { itemID = 11, quality = 0 } },             -- junk
    { bagID = 0, slot = 2, entry = nil },                                      -- empty: dropped
    { bagID = 0, slot = 3, entry = { itemID = 12, quality = 3 } },             -- equipment (Bow)
    { bagID = 0, slot = 4, entry = { itemID = 13, quality = 4 } },             -- equipment (epic)
    { bagID = 0, slot = 5, entry = { itemID = 14, quality = 1 } },             -- consumable
    { bagID = 0, slot = 6, entry = { itemID = 15, quality = 3 }, recent = true }, -- recent outranks class
    { bagID = 0, slot = 7, entry = { itemID = 16, quality = 3 } },             -- equipment (Axe)
}
local DETAILS = {
    [11] = { classID = 15, quality = 0, name = "Trash" },
    [12] = { classID = 2, quality = 3, name = "Bow" },
    [13] = { classID = 4, quality = 4, name = "Chest" },
    [14] = { classID = 0, quality = 1, name = "Potion" },
    [15] = { classID = 7, quality = 3, name = "Ore" },
    [16] = { classID = 2, quality = 3, name = "Axe" },
}
local groups = CL.Group(cells, function(entry) return DETAILS[entry.itemID] end)
assert(#groups == 4, "expected recent/equipment/consumables/junk, got " .. #groups)
assert(groups[1].key == "recent" and #groups[1].cells == 1
    and groups[1].cells[1].entry.itemID == 15, "recent bucket must come first")
assert(groups[2].key == "equipment" and #groups[2].cells == 3, "equipment bucket second")
-- in-bucket: quality desc (13 epic first), then name asc (Axe before Bow)
assert(groups[2].cells[1].entry.itemID == 13, "epic chest sorts first (quality desc)")
assert(groups[2].cells[2].entry.itemID == 16 and groups[2].cells[3].entry.itemID == 12,
    "name ascending breaks quality ties (Axe before Bow)")
assert(groups[3].key == "consumables", "consumables third")
assert(groups[#groups].key == "junk", "junk bucket must come last")
for _, g in ipairs(groups) do
    assert(g.title and g.title ~= "", g.key .. " must carry a title")
    for _, c in ipairs(g.cells) do assert(c.entry, "empty slots must be dropped") end
end

-- Compute: stacked sections — header row, then that bucket's grid; width is
-- the full-columns grid width; coordinates TOPLEFT-relative, y negative.
local layout = CL.Compute(groups, { columns = 2, iconSize = 10, spacing = 2, headerHeight = 14 })
assert(layout.width == 22, "width must be the full 2-column grid width (10+2+10)")
assert(#layout.headers == #groups, "one header per group")
assert(layout.headers[1].y == 0 and layout.headers[1].title == groups[1].title,
    "first header sits at the top")
-- first group's single button: directly under its 14px header
local b1 = layout.buttons[1]
assert(b1.cell.entry.itemID == 15 and b1.x == 0 and b1.y == -14,
    "first button must sit under the first header")
-- second group's header: below header(14) + one 10px row + section gap(2)
assert(layout.headers[2].y == -(14 + 10 + 2),
    "second header must stack below the first section, got " .. layout.headers[2].y)
-- equipment grid: 3 cells over 2 columns → 2 rows; epic chest first at col 0
local b2 = layout.buttons[2]
assert(b2.cell.entry.itemID == 13 and b2.x == 0 and b2.y == layout.headers[2].y - 14,
    "first equipment button under the second header")
local b4 = layout.buttons[4]
assert(b4.cell.entry.itemID == 12 and b4.x == 0 and b4.y == b2.y - 12,
    "row 2 wraps to column 0 one step (10+2) lower")
assert(#layout.buttons == 6, "six occupied cells positioned")
assert(layout.height > 0, "total height must be positive")

print("OK: bags_category_layout_test")
