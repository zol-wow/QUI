-- tests/unit/cdm_composer_reset_rows_clear_all_test.lua
-- Run: lua tests/unit/cdm_composer_reset_rows_clear_all_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local source = readAll("QUI_CDM/cdm/settings/composer.lua")

local seedWrapper = assert(source:find("function ns.CDMComposer.SeedFromBlizzard", 1, true),
    "composer SeedFromBlizzard wrapper should exist")
assert(source:find("AssignCooldownRowsByCapacity(entries, containerKind)", seedWrapper, true),
    "ready Blizzard reset seeds should be assigned to active cooldown rows by capacity before storage")

local refreshStart = assert(source:find("RefreshEntryList = function()", 1, true),
    "RefreshEntryList should exist")
local groupingStart = assert(source:find("local rowEntries = {}", refreshStart, true),
    "RefreshEntryList should build cooldown row groupings")
assert(source:find("local overflowEntries = {}", groupingStart, true),
    "RefreshEntryList should keep entries beyond configured row capacity out of normal rows")
assert(source:find("FindCooldownRowWithRoom(activeRowNums, rowCounts, rowMax, r)", groupingStart, true),
    "cooldown entries should spill from a full requested row into the next configured row with capacity")
assert(source:find("startIndex", source:find("local function FindCooldownRowWithRoom", 1, true) or 1, true),
    "row spillover helper should start after the requested row when that row is full")
assert(not source:find("local r = entry.row or activeRowNums%[1%]", groupingStart),
    "unassigned cooldown entries must not all fall back to the first active row")

local clearHelper = assert(source:find("local function ClearActiveContainerEntries", 1, true),
    "clear-all helper should exist")
assert(source:find("db.ownedSpells = {}", clearHelper, true),
    "clear-all should remove owned cooldown/aura entries")
assert(source:find("db.dormantSpells = {}", clearHelper, true),
    "clear-all should remove dormant entries too")
assert(source:find("db.removedSpells = {}", clearHelper, true),
    "clear-all should reset removed-spell bookkeeping")
assert(source:find("specTrackerSpells", clearHelper, true),
    "clear-all should handle spec-specific custom composer entries")

local contextMenu = assert(source:find("local function ShowEntryContextMenu", 1, true),
    "entry context menu should exist")
assert(source:find('"Remove All Entries"', contextMenu, true),
    "entry right-click menu should expose a Remove All Entries option")
assert(source:find("ClearActiveContainerEntries()", contextMenu, true),
    "Remove All Entries menu item should call the clear-all helper")

print("OK: cdm_composer_reset_rows_clear_all_test")
