local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]unit[/\\]") or "./"

local registered
local Datatexts = {
    Register = function(_, id, definition)
        registered = { id = id, definition = definition }
    end,
}
local ns = {
    Addon = { Datatexts = Datatexts },
    DungeonData = {
        GetTeleportSpellID = function(mapID)
            return ({ [101] = 5001, [102] = 5002, [103] = 5002 })[mapID]
        end,
    },
    L = setmetatable({}, { __index = function(_, key) return key end }),
}

local oldChallengeMode = _G.C_ChallengeMode
_G.C_ChallengeMode = {
    GetMapTable = function() return { 101, 102, 103, 999 } end,
    GetMapUIInfo = function(mapID) return ({ [101] = "Current One", [102] = "Current Two" })[mapID] end,
}

assert(loadfile(ROOT .. "modules/infobar/travel.lua"))("QUI", ns)
local entries = ns.TravelData.GetTeleportEntries()
assert(registered and registered.id == "travel")
assert(#entries == 2)
assert(entries[1][1] == 5001 and entries[1][2] == "Current One")
assert(entries[2][1] == 5002 and entries[2][2] == "Current Two")

_G.C_ChallengeMode = oldChallengeMode
print("ALL TESTS PASSED")
