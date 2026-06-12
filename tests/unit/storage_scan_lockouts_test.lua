-- tests/unit/storage_scan_lockouts_test.lua
-- Run: lua tests/unit/storage_scan_lockouts_test.lua
local loader = dofile("tests/helpers/load_storage_data.lua")
_G.QUI_StorageDB = nil

local SAVED = {
    { "Nerub-ar Palace", 111, 400000, 16, true, false, 0, true, 20, "Heroic", 8, 5 },
    { "Stale Entry", 222, 0, 14, false, false, 0, true, 20, "Normal", 8, 8 },
}
_G.GetNumSavedInstances = function() return #SAVED end
_G.GetSavedInstanceInfo = function(i)
    local e = SAVED[i]
    return e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10], e[11], e[12]
end

local ns = loader.LoadAll({})
local Storage = ns.Storage
Storage.Store.Initialize()
Storage.Store.EnsureCurrentCharacter()

local published = 0
Storage.Bus.Subscribe("LockoutsChanged", function() published = published + 1 end)

local before = os.time()
Storage.ScanLockouts.MarkAllDirty()
assert(Storage.ScanLockouts.Drain() == true)
assert(published == 1)
local locks = Storage.Store.GetCurrentCharacter().lockouts
assert(#locks == 1, "unlocked/expired entries skipped; got " .. #locks)
local l = locks[1]
assert(l.name == "Nerub-ar Palace" and l.difficultyName == "Heroic" and l.isRaid == true)
assert(l.bossesKilled == 5 and l.bossesTotal == 8)
assert(l.resetAt >= before + 400000, "absolute epoch reset")
assert(Storage.ScanLockouts.Drain() == false, "self-guards on dirty")

print("OK: storage_scan_lockouts_test")
