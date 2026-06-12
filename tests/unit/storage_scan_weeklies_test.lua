-- tests/unit/storage_scan_weeklies_test.lua
-- Run: lua tests/unit/storage_scan_weeklies_test.lua
local loader = dofile("tests/helpers/load_storage_data.lua")
_G.QUI_StorageDB = nil

_G.C_WeeklyRewards = {
    GetActivities = function()
        return {
            { type = 1, index = 1, threshold = 1, progress = 1, level = 10, id = 1, activityTierID = 1, rewards = {} },
            { type = 1, index = 2, threshold = 4, progress = 2, level = 7, id = 2, activityTierID = 1, rewards = {} },
        }
    end,
}
_G.C_ChallengeMode = {
    GetOverallDungeonScore = function() return 2750 end,
    GetMapUIInfo = function(id) return "The Dawnbreaker", id, 2100 end,
}
_G.C_MythicPlus = {
    GetOwnedKeystoneChallengeMapID = function() return 505 end,
    GetOwnedKeystoneLevel = function() return 12 end,
}

local ns = loader.LoadAll({})
local Storage = ns.Storage
Storage.Store.Initialize()
Storage.Store.EnsureCurrentCharacter()

local published = 0
Storage.Bus.Subscribe("WeekliesChanged", function() published = published + 1 end)

Storage.ScanWeeklies.MarkAllDirty()
assert(Storage.ScanWeeklies.Drain() == true)
assert(published == 1)
local w = Storage.Store.GetCurrentCharacter().weeklies
assert(#w.activities == 2 and w.activities[2].progress == 2 and w.activities[2].threshold == 4)
assert(w.mplusRating == 2750)
assert(w.keystoneMapID == 505 and w.keystoneLevel == 12 and w.keystoneName == "The Dawnbreaker")
assert(Storage.ScanWeeklies.Drain() == false, "self-guards on dirty")

print("OK: storage_scan_weeklies_test")
