-- tests/unit/storage_scan_character_test.lua
-- Run: lua tests/unit/storage_scan_character_test.lua
local loader = dofile("tests/helpers/load_storage_data.lua")
_G.QUI_StorageDB = nil

_G.UnitLevel = function() return 80 end
_G.UnitXP = function() return 1000 end
_G.UnitXPMax = function() return 5000 end
_G.GetXPExhaustion = function() return 2500 end
_G.GetMoney = function() return 1234567 end
_G.GetAverageItemLevel = function() return 660.5, 658.25, 600 end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 2 end,
    GetSpecializationInfo = function(i)
        assert(i == 2)
        return 63, "Fire", "desc", 12345, "DAMAGER"
    end,
}
_G.C_Map = {
    GetBestMapForUnit = function() return 84 end,
    GetMapInfo = function(id) return { mapID = id, name = "Stormwind City" } end,
}

local ns = loader.LoadAll({})
local Storage = ns.Storage
Storage.Store.Initialize()
Storage.Store.EnsureCurrentCharacter()

local published = 0
Storage.Bus.Subscribe("CharacterChanged", function() published = published + 1 end)

Storage.ScanCharacter.MarkAllDirty()
assert(Storage.ScanCharacter.Drain() == true, "drain reports change")
assert(published == 1, "Drain publishes CharacterChanged")
local d = Storage.Store.GetCurrentCharacter().details
assert(d.level == 80 and d.xp == 1000 and d.xpMax == 5000, "level/xp")
assert(d.restedXP == 2500, "rested")
assert(d.money == 1234567, "money")
assert(d.ilvl == 658.25, "EQUIPPED ilvl (second return)")
assert(d.specID == 63 and d.specIcon == 12345, "spec")
assert(d.zone == "Stormwind City", "zone")
assert(type(d.lastSeen) == "number" and d.lastSeen > 0, "lastSeen")

-- played time arrives by event payload, not by drain
Storage.ScanCharacter.OnTimePlayed(360000, 7200)
assert(d.playedTotal == 360000 and d.playedLevel == 7200, "played")
assert(published == 2, "OnTimePlayed publishes CharacterChanged")

-- no dirty → no work
assert(Storage.ScanCharacter.Drain() == false, "self-guards on dirty")

print("OK: storage_scan_character_test")
