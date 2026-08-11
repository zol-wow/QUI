-- tests/unit/bags_refresh_scope_test.lua
-- Run: lua tests/unit/bags_refresh_scope_test.lua
-- The refresh-scope classifier (PURE): Classify (BagsChanged payload →
-- dirty class), UnionBags (pending-set merge), and LayoutSignature —
-- equal signatures must guarantee identical GridLayout/CategoryLayout
-- placement, so the bag window may re-dress in place without relayout.
local ns = {}
(dofile("tests/helpers/locale.lua"))(ns)
assert(loadfile("QUI_Bags/bags/views/grid_layout.lua"))("QUI", ns)
assert(loadfile("QUI_Bags/bags/views/category_layout.lua"))("QUI", ns)
local chunk = assert(loadfile("QUI_Bags/bags/views/refresh_scope.lua"))
chunk("QUI", ns)
local RS = ns.Bags.RefreshScope
assert(RS and type(RS.Classify) == "function", "RefreshScope.Classify must be exported")

-- Classify: nil payload (unknown scope, e.g. glow-priming republish) → full;
-- empty array (synthetic lock/cooldown re-dress ping) → dress-all;
-- non-empty bag-ID array → dress-bags candidate.
assert(RS.Classify(nil) == "full", "nil payload must classify full")
assert(RS.Classify({}) == "dress-all", "empty array must classify dress-all")
assert(RS.Classify({ 0, 3 }) == "dress-bags", "bag-ID array must classify dress-bags")

-- UnionBags: nil pending seeds a fresh set; merges accumulate.
local set = RS.UnionBags(nil, { 0, 3 })
assert(set[0] and set[3] and not set[1], "union must seed from changed array")
set = RS.UnionBags(set, { 3, 5 })
assert(set[0] and set[3] and set[5], "union must accumulate across events")

-- Signature fixtures. buildDetails is injected (Details.Build shape).
local function details(entry) return entry and entry.d or nil end
local function slotsA()
    return {
        { bagID = 0, slot = 1, entry = { itemID = 11, quality = 2, count = 1,
            d = { classID = 4, quality = 2, name = "Boots" } } },
        { bagID = 0, slot = 2, entry = nil },
        { bagID = 1, slot = 1, entry = { itemID = 22, quality = 0, count = 5,
            d = { classID = 15, quality = 0, name = "Grays" } } },
    }
end
local flat = { layoutMode = "flat", reagentDisplay = "separate" }
local flatGrouped = { layoutMode = "flat", reagentDisplay = "separate", groupEmptySlots = true }
local cat = { layoutMode = "categories" }

-- Flat plain: purely positional — count change, itemID swap, and
-- occupancy flips leave the signature untouched.
local base = RS.LayoutSignature(slotsA(), flat, details)
local b = slotsA(); b[1].entry.count = 20
assert(RS.LayoutSignature(b, flat, details) == base, "flat: count change must not move cells")
b = slotsA(); b[1].entry.itemID = 99
assert(RS.LayoutSignature(b, flat, details) == base, "flat: item identity must not move cells")
b = slotsA(); b[2].entry = { itemID = 7, quality = 1, d = { classID = 0, quality = 1, name = "Potion" } }
assert(RS.LayoutSignature(b, flat, details) == base, "flat plain: occupancy must not move cells")
-- ...but a slot-count change (bag swap) or hidden-bag change (cell list) must.
b = slotsA(); table.remove(b, 3)
assert(RS.LayoutSignature(b, flat, details) ~= base, "flat: slot-count change must relayout")
-- reagentDisplay partitions flat cells → joins the signature header.
assert(RS.LayoutSignature(slotsA(), { layoutMode = "flat", reagentDisplay = "merged" }, details) ~= base,
    "flat: reagentDisplay change must relayout")
-- Mode flip always differs.
assert(RS.LayoutSignature(slotsA(), cat, details) ~= base, "mode flip must relayout")

-- Flat + groupEmptySlots: the collapse points follow the occupancy pattern.
local gBase = RS.LayoutSignature(slotsA(), flatGrouped, details)
b = slotsA(); b[2].entry = { itemID = 7, quality = 1, d = { classID = 0, quality = 1, name = "Potion" } }
assert(RS.LayoutSignature(b, flatGrouped, details) ~= gBase,
    "grouped: occupancy flip must relayout")
b = slotsA(); b[1].entry.count = 20
assert(RS.LayoutSignature(b, flatGrouped, details) == gBase,
    "grouped: count change must not relayout")

-- Categories: signature carries the Group inputs — bucket (or recent),
-- quality, name, itemID. Count-only changes re-dress in place.
local cBase = RS.LayoutSignature(slotsA(), cat, details)
b = slotsA(); b[1].entry.count = 20
assert(RS.LayoutSignature(b, cat, details) == cBase, "cat: count change must not relayout")
b = slotsA(); b[1].entry.d.name = "Aoots"
assert(RS.LayoutSignature(b, cat, details) ~= cBase, "cat: name arrival/change reorders → relayout")
b = slotsA(); b[1].entry.quality = 3; b[1].entry.d.quality = 3
assert(RS.LayoutSignature(b, cat, details) ~= cBase, "cat: quality change reorders → relayout")
b = slotsA(); b[1].entry.itemID = 99
assert(RS.LayoutSignature(b, cat, details) ~= cBase, "cat: itemID change must relayout")
b = slotsA(); b[1].entry.d.classID = 0
assert(RS.LayoutSignature(b, cat, details) ~= cBase, "cat: bucket change must relayout")
b = slotsA(); b[2].entry = { itemID = 7, quality = 1, d = { classID = 0, quality = 1, name = "Potion" } }
assert(RS.LayoutSignature(b, cat, details) ~= cBase, "cat: new occupied cell must relayout")
-- Pending details (nil) coalesce like Group: entry.quality fallback, misc bucket.
b = slotsA(); b[1].entry.d = nil
assert(RS.LayoutSignature(b, cat, details) ~= cBase, "cat: details-pending buckets differently")
-- recent flag (new-item glow) outranks the bucket, exactly like Group.
local recentOpts = { layoutMode = "categories",
    getRecent = function(cell) return cell.bagID == 0 and cell.slot == 1 end }
assert(RS.LayoutSignature(slotsA(), recentOpts, details) ~= cBase,
    "cat: recent-flag flip must relayout")

print("OK: bags_refresh_scope_test")
