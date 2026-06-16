-- Verifies the pure helpers of QUI_InfoBar/infobar/dragreorder.lua:
--   * MoveWidget: remove-then-insert with same-zone gap adjustment, no-op
--     detection, cross-zone moves, absent id
--   * ResolveArrayInsert: screen side -> array index, mirrored for right zone
--   * ResolveTargetZone: cursor-x -> zone by span containment, else nearest
-- Standalone: lua tests/unit/infobar_dragreorder_test.lua

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]unit[/\\]") or "./"

local failures = 0
local function check(cond, label)
    if cond then
        print("ok - " .. label)
    else
        failures = failures + 1
        print("FAIL - " .. label)
    end
end

-- Minimal env: dragreorder.lua needs ns.Addon.InfoBar (wraps ApplyAll,
-- publishes DragReorder) and InfoBar.ContextMenu (FindWidget/EnsureZones).
-- Load infobar_shared then contextmenu (same order the in-game TOC uses)
-- so ContextMenu exists before dragreorder loads.
-- The in-game wiring block at the bottom of dragreorder.lua runs one
-- load-time statement against the WoW API (`CreateFrame("Frame")` for its
-- OnUpdate driver); stub just enough for the chunk to load headlessly. The
-- pure helpers under test never touch any of it.
CreateFrame = CreateFrame or function()
    return { Hide = function() end, Show = function() end, SetScript = function() end }
end
local InfoBar = { ApplyAll = function() end, GetZoneFrames = function() return {} end }
local ns = { Addon = { InfoBar = InfoBar } }
(dofile(ROOT .. "tests/helpers/locale.lua"))(ns)
assert(loadfile(ROOT .. "core/infobar_shared.lua"))("QUI", ns)
assert(loadfile(ROOT .. "QUI_InfoBar/infobar/contextmenu.lua"))("QUI_InfoBar", ns)
assert(loadfile(ROOT .. "QUI_InfoBar/infobar/dragreorder.lua"))("QUI_InfoBar", ns)

local DR = InfoBar.DragReorder
check(DR ~= nil, "DragReorder published on InfoBar")

-- MoveWidget: within-zone move down (a to the end of left).
local db = { zones = { left = { "a", "b", "c" }, center = {}, right = {} } }
check(DR.MoveWidget(db, "a", "left", 4) == true, "move a within left returns true")
check(table.concat(db.zones.left, ",") == "b,c,a", "a moved to end of left")

-- within-zone move up (c to front).
db = { zones = { left = { "a", "b", "c" }, center = {}, right = {} } }
check(DR.MoveWidget(db, "c", "left", 1) == true, "move c to front returns true")
check(table.concat(db.zones.left, ",") == "c,a,b", "c moved to front of left")

-- no-op: dropping b back into its own slot (both adjacency boundaries).
db = { zones = { left = { "a", "b", "c" }, center = {}, right = {} } }
check(DR.MoveWidget(db, "b", "left", 2) == false, "drop b before itself is a no-op")
check(DR.MoveWidget(db, "b", "left", 3) == false, "drop b after itself is a no-op")
check(table.concat(db.zones.left, ",") == "a,b,c", "no-op left list unchanged")

-- cross-zone move.
db = { zones = { left = { "a", "b" }, center = {}, right = { "x" } } }
check(DR.MoveWidget(db, "a", "right", 1) == true, "move a into right at index 1")
check(table.concat(db.zones.left, ",") == "b", "a removed from left")
check(table.concat(db.zones.right, ",") == "a,x", "a inserted at front of right")

-- absent id.
db = { zones = { left = {}, center = {}, right = {} } }
check(DR.MoveWidget(db, "ghost", "left", 1) == false, "absent id returns false")

-- ResolveArrayInsert: left/center (isRight=false): left side = before anchor.
check(DR.ResolveArrayInsert("left", 3, false) == 3, "left side, non-right -> anchor index")
check(DR.ResolveArrayInsert("right", 3, false) == 4, "right side, non-right -> anchor+1")
-- right zone is mirrored: screen-left = later in array.
check(DR.ResolveArrayInsert("left", 1, true) == 2, "left side, right zone -> anchor+1")
check(DR.ResolveArrayInsert("right", 1, true) == 1, "right side, right zone -> anchor index")

-- ResolveTargetZone: containment then nearest.
local spans = {
    { key = "left", left = 0, right = 100 },
    { key = "center", left = 200, right = 300 },
    { key = "right", left = 400, right = 500 },
}
check(DR.ResolveTargetZone(50, spans) == "left", "cursor inside left span")
check(DR.ResolveTargetZone(250, spans) == "center", "cursor inside center span")
check(DR.ResolveTargetZone(450, spans) == "right", "cursor inside right span")
check(DR.ResolveTargetZone(150, spans) == "left", "gap left-of-center -> nearest is left")
check(DR.ResolveTargetZone(170, spans) == "center", "gap right-of-left -> nearest is center")
check(DR.ResolveTargetZone(-50, spans) == "left", "left of everything -> left")
check(DR.ResolveTargetZone(999, spans) == "right", "right of everything -> right")

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
