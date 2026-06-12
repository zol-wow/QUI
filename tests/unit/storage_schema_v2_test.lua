-- tests/unit/storage_schema_v2_test.lua
-- Run: lua tests/unit/storage_schema_v2_test.lua
local loader = dofile("tests/helpers/load_storage_data.lua")

-- Seed a v1 store with one legacy character record.
_G.QUI_StorageDB = {
    version = 1,
    characters = {
        ["Old-Realm"] = {
            details = { class = "MAGE" },
            bags = {}, bankTabs = {}, mail = {}, equipped = {},
            currencies = {}, auctions = {},
        },
    },
    guilds = {},
    warband = { tabs = {}, money = 0 },
}

local ns = loader.LoadAll({})
local Store = ns.Storage.Store

assert(Store.SCHEMA_VERSION == 2, "schema version must be 2")
local db = Store.Initialize()
assert(db.version == 2, "migrated version")
assert(not Store.readOnly, "v1 -> v2 must not go read-only")

-- v1 record gains the new tables
local old = db.characters["Old-Realm"]
assert(type(old.professions) == "table", "migration adds professions")
assert(type(old.reputations) == "table", "migration adds reputations")
assert(type(old.weeklies) == "table", "migration adds weeklies")
assert(type(old.lockouts) == "table", "migration adds lockouts")
assert(old.details.class == "MAGE", "existing details preserved")

-- shared faction-name maps exist
assert(type(db.factionNames) == "table", "factionNames map")
assert(type(db.factionGroups) == "table", "factionGroups map")

-- new records carry the new tables from birth
local rec = Store.EnsureCurrentCharacter()
assert(type(rec.professions) == "table" and type(rec.weeklies) == "table",
    "NewCharacterRecord includes alt tables")

-- newer-version guard still works
_G.QUI_StorageDB = { version = 99 }
local ns2 = loader.LoadAll({})
ns2.Storage.Store.Initialize()
assert(ns2.Storage.Store.readOnly, "newer version stays read-only")

print("OK: storage_schema_v2_test")
