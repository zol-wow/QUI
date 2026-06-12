-- tests/unit/storage_summaries_iterate_test.lua
-- Run: lua tests/unit/storage_summaries_iterate_test.lua
local loader = dofile("tests/helpers/load_storage_data.lua")
_G.QUI_StorageDB = nil
local ns = loader.LoadAll({})
local Storage = ns.Storage
Storage.Store.Initialize()
local rec = Storage.Store.EnsureCurrentCharacter()
rec.bags[0] = { size = 2, slots = { [1] = { itemID = 6948, count = 1 }, [2] = { itemID = 2589, count = 20 } } }
Storage.Summaries.SeedOwners()

local seen = {}
Storage.Summaries.IterateOwnerItems(Storage.Store.GetCurrentCharacterKey(), function(itemID, byLocation)
    seen[itemID] = byLocation
end)
assert(seen[6948] and seen[2589], "both items iterated")
local total = 0
for _, count in pairs(seen[2589]) do total = total + count end
assert(total == 20, "counts per location")

-- unknown owner: no error, no iteration
local called = false
Storage.Summaries.IterateOwnerItems("Nobody-Realm", function() called = true end)
assert(called == false, "unknown owner iterates nothing")

print("OK: storage_summaries_iterate_test")
