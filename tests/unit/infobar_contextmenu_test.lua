-- Verifies the pure helpers of QUI_InfoBar/infobar/contextmenu.lua:
--   * cursor-X -> zone bucketing (thirds of bar width, clamped at the edges)
--   * add/remove/placed mutation semantics on db.zones (append to target
--     zone, refuse duplicates across zones, remove from owning zone)
--   * zones sub-table seeding for pre-seed profiles
--   * widgetSettings seeding parity with the settings page defaults
--     (infobar_content.lua EnsureWidgetSettings)
--   * Add Widget category grouping preserves Datatexts:GetAll() order
--   * Configure Widget placed list is zone-ordered and flags unloaded ids
-- Standalone: lua tests/unit/infobar_contextmenu_test.lua

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

-- Minimal env: at load time the file only needs ns.Addon.InfoBar (it wraps
-- InfoBar.ApplyAll and publishes InfoBar.ContextMenu). MenuUtil/C_Timer/
-- GetCursorPosition are referenced only inside in-game code paths.
local InfoBar = { ApplyAll = function() end }
local ns = { Addon = { InfoBar = InfoBar } }

-- contextmenu.lua now reads EnsureWidgetSettings from the shared core helper;
-- load it first (in-game core loads long before the InfoBar addon).
(dofile(ROOT .. "tests/helpers/locale.lua"))(ns)
assert(loadfile(ROOT .. "core/infobar_shared.lua"))("QUI", ns)

local chunk = assert(loadfile(ROOT .. "QUI_InfoBar/infobar/contextmenu.lua"))
chunk("QUI_InfoBar", ns)

local CM = InfoBar.ContextMenu
check(CM ~= nil, "ContextMenu published on InfoBar")

-- Zone bucketing: thirds of the bar width.
check(CM.ZoneFromCursorX(0, 900) == "left", "x=0 -> left")
check(CM.ZoneFromCursorX(299, 900) == "left", "x=299 -> left")
check(CM.ZoneFromCursorX(300, 900) == "center", "x=300 -> center")
check(CM.ZoneFromCursorX(599, 900) == "center", "x=599 -> center")
check(CM.ZoneFromCursorX(600, 900) == "right", "x=600 -> right")
check(CM.ZoneFromCursorX(1200, 900) == "right", "x past right edge -> right")
check(CM.ZoneFromCursorX(-50, 900) == "left", "x left of bar -> left")
check(CM.ZoneFromCursorX(10, 0) == "left", "zero/invalid width -> left fallback")

-- Add/remove semantics.
local db = { zones = { left = { "micromenu" }, center = {}, right = { "gold" } } }
check(CM.IsPlaced(db, "gold") == true, "IsPlaced finds id in right zone")
check(CM.IsPlaced(db, "fps") == false, "IsPlaced false for absent id")
check(CM.AddWidget(db, "center", "fps") == true, "AddWidget returns true")
check(db.zones.center[1] == "fps", "AddWidget appends to the target zone")
check(CM.AddWidget(db, "left", "fps") == false, "AddWidget refuses duplicate (any zone)")
check(#db.zones.left == 1, "duplicate add did not mutate the other zone")
check(CM.RemoveWidget(db, "gold") == true, "RemoveWidget returns true")
check(#db.zones.right == 0, "RemoveWidget removed from the owning zone")
check(CM.RemoveWidget(db, "gold") == false, "RemoveWidget absent id -> false")

-- Sub-table guards: a pre-seed profile (bar never enabled) has no zones.
local bare = {}
check(CM.AddWidget(bare, "right", "time") == true, "AddWidget seeds zones tables")
check(bare.zones.right[1] == "time", "seeded zone holds the widget")
check(#bare.zones.left == 0 and #bare.zones.center == 0, "other zones seeded empty")

-- widgetSettings seeding parity with the settings page.
local ws = CM.EnsureWidgetSettings(bare, "time")
local expected = { shortLabel = false, noLabel = false, minWidth = 0,
    xOffset = 0, hideIcon = false, clickThrough = false }
for k, v in pairs(expected) do
    check(ws[k] == v, "widgetSettings seeds " .. k)
end
local partial = { widgetSettings = { fps = { shortLabel = true } } }
local ws2 = CM.EnsureWidgetSettings(partial, "fps")
check(ws2.shortLabel == true, "existing override value preserved")
check(ws2.clickThrough == false, "missing keys backfilled")

-- Category grouping preserves GetAll() order, groups by category.
local defs = {
    { id = "gold", displayName = "Gold", category = "Character" },
    { id = "vault", displayName = "Vault", category = "Character" },
    { id = "fps", displayName = "FPS", category = "System" },
}
local cats = CM.BuildCategories(defs)
check(#cats == 2, "two categories built")
check(cats[1].category == "Character" and #cats[1].widgets == 2,
    "first category grouped with both widgets")
check(cats[1].widgets[1].id == "gold" and cats[1].widgets[1].name == "Gold",
    "widget entry carries id and display name")
check(cats[2].category == "System" and cats[2].widgets[1].id == "fps",
    "second category holds fps")
check(#CM.BuildCategories(nil) == 0, "nil defs -> empty list")

-- Placed list: zone order left/center/right + not-loaded flag.
local db2 = { zones = { left = { "micromenu" }, center = { "time" }, right = { "ghost" } } }
local registry = { micromenu = { displayName = "Micro Menu" }, time = { displayName = "Time" } }
local placed = CM.PlacedList(db2, function(id) return registry[id] end)
check(#placed == 3, "placed list covers all zones")
check(placed[1].id == "micromenu" and placed[2].id == "time" and placed[3].id == "ghost",
    "placed list is zone-ordered left/center/right")
check(placed[1].name == "Micro Menu", "display name read from registry")
check(placed[1].loaded == true, "loaded id flagged loaded")
check(placed[3].loaded == false and placed[3].name == "ghost",
    "unloaded id flagged with raw id as name")

if failures == 0 then
    print("ALL TESTS PASSED")
    os.exit(0)
else
    print(failures .. " FAILURES")
    os.exit(1)
end
