-- tests/unit/bags_store_realm_key_test.lua
-- Character/guild cache keys must use the NORMALIZED realm (no spaces —
-- UnitFullName format) in every code path. Mixing in GetRealmName()'s
-- display name ("Aerie Peak" vs "AeriePeak") forks the same character into
-- two records across sessions depending on which API answered at login.
-- Run: lua tests/unit/bags_store_realm_key_test.lua
-- luacheck: globals QUI_StorageDB

-- Install scenario stubs BEFORE the loader (InstallBaseStubs uses `or`).
-- Login-time worst case: UnitFullName has no realm yet; the display realm
-- is multi-word.
_G.UnitFullName = function() return "Testchar", nil end
_G.GetNormalizedRealmName = function() return "AeriePeak" end
_G.GetRealmName = function() return "Aerie Peak" end

local loader = dofile("tests/helpers/load_bags_data.lua")
local ns = loader.LoadAll(nil, "store.lua")
local Store = ns.Bags.Store

_G.QUI_StorageDB = nil
Store.Initialize()

-- Test 1: nil UnitFullName realm → key uses the normalized realm, never the
-- spaced display name.
local rec, key = Store.EnsureCurrentCharacter()
assert(key == "Testchar-AeriePeak",
    "key must use the normalized realm, got " .. tostring(key))

-- Test 2: later in the session UnitFullName answers (normalized format) —
-- the SAME record must be hit, no dual records.
_G.UnitFullName = function() return "Testchar", "AeriePeak" end
local rec2, key2 = Store.EnsureCurrentCharacter()
assert(key2 == key, "session key drifted: " .. tostring(key2))
assert(rec2 == rec, "dual character record created")
local n = 0
for _ in pairs(QUI_StorageDB.characters) do n = n + 1 end
assert(n == 1, "expected exactly 1 character record, got " .. n)

-- Test 3: guild keys take the same normalized realm.
_G.GetGuildInfo = function() return "My Guild" end
_G.UnitFullName = function() return "Testchar", nil end
local gkey = Store.GetCurrentGuildKey()
assert(gkey == "My Guild-AeriePeak",
    "guild key must use the normalized realm, got " .. tostring(gkey))

-- Test 4: last-resort fallback (no UnitFullName realm AND no
-- GetNormalizedRealmName): the display realm is normalized by hand —
-- spaces/dashes/apostrophes stripped — so the key format never forks.
_G.GetNormalizedRealmName = nil
_G.GetRealmName = function() return "Aerie Peak" end
assert(Store.GetCurrentCharacterKey() == "Testchar-AeriePeak",
    "fallback must strip spaces, got " .. tostring(Store.GetCurrentCharacterKey()))
_G.GetRealmName = function() return "Kil'jaeden" end
assert(Store.GetCurrentCharacterKey() == "Testchar-Kiljaeden",
    "fallback must strip apostrophes, got " .. tostring(Store.GetCurrentCharacterKey()))
_G.GetRealmName = function() return "Azjol-Nerub" end
assert(Store.GetCurrentCharacterKey() == "Testchar-AzjolNerub",
    "fallback must strip dashes, got " .. tostring(Store.GetCurrentCharacterKey()))

print("OK: bags_store_realm_key_test")
