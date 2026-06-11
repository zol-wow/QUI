-- tests/unit/bags_store_test.lua
-- Run: lua tests/unit/bags_store_test.lua
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_bags_data.lua")
local ns = loader.LoadAll(nil, "store.lua")
local Store = ns.Bags.Store

-- Test 1: fresh init creates versioned schema
_G.QUI_StorageDB = nil
Store.Initialize()
assert(type(QUI_StorageDB) == "table", "did not create SV table")
assert(QUI_StorageDB.version == Store.SCHEMA_VERSION, "missing schema version")
assert(type(QUI_StorageDB.characters) == "table", "missing characters table")
assert(type(QUI_StorageDB.guilds) == "table", "missing guilds table")
assert(type(QUI_StorageDB.warband) == "table" and type(QUI_StorageDB.warband.tabs) == "table",
       "missing warband table")
assert(Store.IsReady(), "store should be ready after init")

-- Test 2: EnsureCurrentCharacter creates the record with details
local rec, key = Store.EnsureCurrentCharacter()
assert(key == "Testchar-TestRealm", "bad character key: " .. tostring(key))
assert(rec.details.class == "MAGE", "details.class not captured")
assert(rec.details.faction == "Alliance", "details.faction not captured")
assert(type(rec.details.lastSeen) == "number", "details.lastSeen not captured")
assert(type(rec.bags) == "table" and type(rec.bankTabs) == "table", "missing container tables")
assert(Store.GetCurrentCharacter() == rec, "GetCurrentCharacter mismatch")
-- idempotent: second call returns the same record
local rec2 = Store.EnsureCurrentCharacter()
assert(rec2 == rec, "EnsureCurrentCharacter not idempotent")

-- Test 3: ListCharacters / DeleteCharacter
QUI_StorageDB.characters["Alt-TestRealm"] = { details = {}, bags = {}, bankTabs = {} }
local list = Store.ListCharacters()
assert(#list == 2 and list[1] == "Alt-TestRealm" and list[2] == "Testchar-TestRealm", "ListCharacters wrong")
Store.DeleteCharacter("Alt-TestRealm")
assert(Store.GetCharacter("Alt-TestRealm") == nil, "DeleteCharacter failed")

-- Test 4: future-version data is left untouched and store goes read-only
_G.QUI_StorageDB = { version = Store.SCHEMA_VERSION + 1, characters = { marker = true } }
local printed = {}
local realPrint = print
_G.print = function(msg) printed[#printed + 1] = tostring(msg) end
Store.Initialize()
_G.print = realPrint
assert(QUI_StorageDB.characters.marker == true, "future-version data was mutated")
assert(not Store.IsReady(), "store must be read-only on future-version data")
assert(#printed >= 1, "expected a user-visible warning")

-- Test 5: re-Initialize on an existing current-version db preserves data
-- and clears the read-only flag set by Test 4
_G.QUI_StorageDB = {
    version = Store.SCHEMA_VERSION,
    characters = { ["Keeper-TestRealm"] = { details = {}, bags = {}, bankTabs = {} } },
    -- guilds/warband intentionally missing: re-init must heal them
}
Store.Initialize()
assert(Store.IsReady(), "re-init on current-version db must clear read-only")
assert(Store.GetCharacter("Keeper-TestRealm") ~= nil, "re-init must preserve existing characters")
assert(type(QUI_StorageDB.guilds) == "table", "re-init must heal missing guilds table")
assert(type(QUI_StorageDB.warband) == "table" and type(QUI_StorageDB.warband.tabs) == "table",
       "re-init must heal missing warband table")

-- Test 6: EnsureGuild creates and returns the record; idempotent
do
    _G.QUI_StorageDB = nil
    Store.Initialize()
    -- create new record
    local g = Store.EnsureGuild("TestGuild-TestRealm")
    assert(type(g) == "table", "EnsureGuild must return a table")
    assert(type(g.tabs) == "table", "guild record must have tabs")
    assert(g.money == 0, "guild record must have money=0")
    assert(type(g.details) == "table", "guild record must have details")
    -- idempotent
    local g2 = Store.EnsureGuild("TestGuild-TestRealm")
    assert(g2 == g, "EnsureGuild must be idempotent")
    -- GetGuild returns same record
    assert(Store.GetGuild("TestGuild-TestRealm") == g, "GetGuild must return EnsureGuild record")
end

-- Test 7: EnsureGuild returns nil when not ready or key nil
do
    -- not ready (future-version db put store in read-only)
    _G.QUI_StorageDB = { version = Store.SCHEMA_VERSION + 1, characters = {} }
    local realPrint2 = print; _G.print = function() end
    Store.Initialize()
    _G.print = realPrint2
    assert(not Store.IsReady(), "store should be read-only here")
    local g = Store.EnsureGuild("Any-Realm")
    assert(g == nil, "EnsureGuild must return nil when not ready")
    -- key nil
    _G.QUI_StorageDB = nil
    Store.Initialize()
    local gnil = Store.EnsureGuild(nil)
    assert(gnil == nil, "EnsureGuild must return nil for nil key")
end

-- Test 8: GetCurrentGuildKey returns nil when unguilded
do
    -- base stubs have GetGuildInfo returning nil
    local gkey = Store.GetCurrentGuildKey()
    assert(gkey == nil, "GetCurrentGuildKey must be nil when unguilded: got " .. tostring(gkey))
end

-- Test 9: GetCurrentGuildKey returns "GuildName-Realm" when guilded
do
    -- Override GetGuildInfo to simulate being in a guild
    local origGGI = _G.GetGuildInfo
    _G.GetGuildInfo = function(unit) if unit == "player" then return "Dragons" end end
    local gkey = Store.GetCurrentGuildKey()
    _G.GetGuildInfo = origGGI
    assert(gkey == "Dragons-TestRealm",
        "GetCurrentGuildKey wrong: expected Dragons-TestRealm, got " .. tostring(gkey))
end

print("OK: bags_store_test")
