-- tests/unit/storage_scan_professions_test.lua
-- Run: lua tests/unit/storage_scan_professions_test.lua
local loader = dofile("tests/helpers/load_storage_data.lua")
_G.QUI_StorageDB = nil

_G.GetProfessions = function() return 5, 9, nil, 10, 8 end
local INFO = {
    [5] = { "Alchemy", 136240, 75, 100, 0, 0, 171 },
    [9] = { "Herbalism", 136246, 50, 100, 0, 0, 182 },
    [10] = { "Fishing", 136245, 25, 300, 0, 0, 356 },
    [8] = { "Cooking", 133971, 60, 300, 0, 0, 185 },
}
_G.GetProfessionInfo = function(i)
    local e = INFO[i]
    return e[1], e[2], e[3], e[4], e[5], e[6], e[7]
end

local ns = loader.LoadAll({})
local Storage = ns.Storage
Storage.Store.Initialize()
Storage.Store.EnsureCurrentCharacter()

local published = 0
Storage.Bus.Subscribe("ProfessionsChanged", function() published = published + 1 end)

Storage.ScanProfessions.MarkAllDirty()
assert(Storage.ScanProfessions.Drain() == true)
assert(published == 1, "Drain publishes ProfessionsChanged")
local profs = Storage.Store.GetCurrentCharacter().professions
assert(#profs == 4, "four professions, nil archaeology skipped; got " .. #profs)
assert(profs[1].skillLineID == 171 and profs[1].isPrimary == true, "primary first")
assert(profs[2].skillLineID == 182 and profs[2].isPrimary == true)
assert(profs[3].rank == 60 and profs[3].name == "Cooking", "secondaries follow")
assert(profs[4].rank == 25 and profs[4].maxRank == 300, "fishing")
assert(Storage.ScanProfessions.Drain() == false, "self-guards on dirty")

print("OK: storage_scan_professions_test")
