local oldChallengeMode = _G.C_ChallengeMode
local oldUnitFactionGroup = _G.UnitFactionGroup

local names = {
    [249] = "Kings' Rest",
    [250] = "Temple of Sethraliss",
    [399] = "Ruby Life Pools",
    [584] = "The Blinding Vale",
    [585] = "Voidscar Arena",
    [586] = "Den of Nalorakk",
    [587] = "Murder Row",
    [588] = "Altar of Fangs",
}

_G.UnitFactionGroup = function() return "Alliance" end
_G.C_ChallengeMode = {
    GetMapUIInfo = function(mapID) return names[mapID] end,
}

local ns = {
    Helpers = {
        UpperUTF8 = string.upper,
        TruncateUTF8 = function(value, length) return value:sub(1, length) end,
    },
}
assert(loadfile("modules/minimap/dungeon_data.lua"))("QUI", ns)

local expected = {
    [249] = 1286831,
    [250] = 1286828,
    [399] = 393256,
    [584] = 1286801,
    [585] = 1286804,
    [586] = 1286807,
    [587] = 1286809,
    [588] = 1286812,
}
for mapID, spellID in pairs(expected) do
    assert(ns.DungeonData.GetTeleportSpellID(mapID) == spellID, mapID)
end

_G.C_ChallengeMode = oldChallengeMode
_G.UnitFactionGroup = oldUnitFactionGroup
print("ALL TESTS PASSED")
