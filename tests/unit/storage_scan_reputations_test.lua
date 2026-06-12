-- tests/unit/storage_scan_reputations_test.lua
-- Run: lua tests/unit/storage_scan_reputations_test.lua
local loader = dofile("tests/helpers/load_storage_data.lua")
_G.QUI_StorageDB = nil

-- Simulated rep pane: header (collapsed) → child faction; plus a major
-- faction and a paragon faction at top level.
local pane = {
    { factionID = 1100, name = "Old Expansion", isHeader = true, isCollapsed = true, reaction = 4 },
    { factionID = 2600, name = "Renown Folk", isHeader = false, reaction = 8,
      currentStanding = 0, currentReactionThreshold = 0, nextReactionThreshold = 0 },
    { factionID = 2510, name = "Paragon Pals", isHeader = false, reaction = 8,
      currentStanding = 21000, currentReactionThreshold = 21000, nextReactionThreshold = 21000 },
}
local childRow = { factionID = 1133, name = "Old Friends", isHeader = false, reaction = 5,
    currentStanding = 4500, currentReactionThreshold = 3000, nextReactionThreshold = 9000 }
local expanded = false

_G.C_Reputation = {
    GetNumFactions = function() return expanded and 4 or 3 end,
    GetFactionDataByIndex = function(i)
        if not expanded then return pane[i] end
        if i == 1 then return pane[1] end
        if i == 2 then return childRow end
        return pane[i - 1]
    end,
    GetFactionDataByID = function(id)
        for _, f in ipairs({ pane[1], childRow, pane[2], pane[3] }) do
            if f.factionID == id then return f end
        end
    end,
    ExpandFactionHeader = function(i) assert(i == 1); expanded = true; pane[1].isCollapsed = false end,
    CollapseFactionHeader = function(i) expanded = false; pane[1].isCollapsed = true end,
    IsMajorFaction = function(id) return id == 2600 end,
    IsFactionParagon = function(id) return id == 2510 end,
    GetFactionParagonInfo = function(id)
        if id == 2510 then return 31000, 10000, 90001, true, false end
    end,
}
_G.C_MajorFactions = {
    GetMajorFactionData = function(id)
        if id == 2600 then return { renownLevel = 14, renownReputationEarned = 1500, renownLevelThreshold = 2500 } end
    end,
}
_G.InCombatLockdown = function() return false end

local ns = loader.LoadAll({})
local Storage = ns.Storage
Storage.Store.Initialize()
Storage.Store.EnsureCurrentCharacter()

local published = 0
Storage.Bus.Subscribe("ReputationsChanged", function() published = published + 1 end)

Storage.ScanReputations.MarkFullDirty()
assert(Storage.ScanReputations.Drain() == true)
assert(published == 1, "full walk publishes once")
local reps = Storage.Store.GetCurrentCharacter().reputations

local child = reps[1133]
assert(child, "collapsed-header child captured via expand")
assert(child.value == 4500 and child.standing == 5, "child standing")
assert(child.floor == 3000 and child.ceiling == 9000, "thresholds")
assert(pane[1].isCollapsed == true, "collapse state restored")
assert(reps[1100] == nil, "plain headers not stored")

local renown = reps[2600]
assert(renown.renownLevel == 14 and renown.renownEarned == 1500 and renown.renownThreshold == 2500, "major faction")

local paragon = reps[2510]
assert(paragon.paragonValue == 31000 and paragon.paragonThreshold == 10000 and paragon.paragonPending == true, "paragon raw values")

-- shared name/group maps
assert(Storage.Store.GetFactionNames()[1133] == "Old Friends")
assert(Storage.Store.GetFactionGroups()[1133] == "Old Expansion", "child grouped under its header")

-- in-combat full walk defers (dirty preserved, no publish)
_G.InCombatLockdown = function() return true end
Storage.ScanReputations.MarkFullDirty()
assert(Storage.ScanReputations.Drain() == false, "combat defers the walk")
_G.InCombatLockdown = function() return false end
assert(Storage.ScanReputations.Drain() == true, "deferred walk runs after combat")
assert(published == 2)

-- incremental: single-faction update path (no expand/collapse calls)
local expandCalls = 0
local oldExpand = _G.C_Reputation.ExpandFactionHeader
_G.C_Reputation.ExpandFactionHeader = function(...) expandCalls = expandCalls + 1; return oldExpand(...) end
childRow.currentStanding = 5000
Storage.ScanReputations.OnFactionStandingChanged(1133)
assert(Storage.ScanReputations.Drain() == true)
assert(reps ~= Storage.Store.GetCurrentCharacter().reputations or reps[1133].value == 5000, "incremental update")
assert(Storage.Store.GetCurrentCharacter().reputations[1133].value == 5000, "incremental update value")
assert(expandCalls == 0, "incremental path never touches headers")

print("OK: storage_scan_reputations_test")
