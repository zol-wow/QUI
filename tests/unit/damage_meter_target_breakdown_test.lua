-- tests/unit/damage_meter_target_breakdown_test.lua
-- Run: lua tests/unit/damage_meter_target_breakdown_test.lua
--
-- Target breakdowns ("who damaged whom") are reconstructed from the
-- EnemyDamageTaken meter, where each enemy source's combatSpells carry a
-- combatSpellDetails.unitName identifying the ATTACKING PLAYER. Two pure
-- helpers do the work:
--   AggregateSpellsByUnit — sum an enemy's spells per attacking player.
--   PivotPlayerTargets    — invert per-enemy player totals into per-player
--                           enemy-target lists.
-- Both must be secret-safe: a secret unit name or amount can't be a table key
-- or a summand, so such entries are skipped; enemy names (which may be secret
-- in M+) are carried as VALUES only, never keys.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end
local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")
local function extract(funcName)
    local chunk = src:match("(local function " .. funcName .. ".-\nend\n)")
    assert(chunk, "could not locate " .. funcName .. " in damage_meter.lua")
    return chunk
end

local AggregateSpellsByUnit = assert(loadstring(
    extract("AggregateSpellsByUnit") .. "\nreturn AggregateSpellsByUnit"))()
local PivotPlayerTargets = assert(loadstring(
    extract("PivotPlayerTargets") .. "\nreturn PivotPlayerTargets"))()

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local function isSecret(v) return v == SECRET end
local function spell(unitName, amt, class, icon)
    return { totalAmount = amt, combatSpellDetails = { unitName = unitName, unitClassFilename = class, specIconID = icon } }
end
local function names(list) local o = {} for i, e in ipairs(list) do o[i] = e.name end return table.concat(o, ",") end

-- ===== AggregateSpellsByUnit =====

-- Sums per unit, sorts descending, carries class + spec icon.
local agg = AggregateSpellsByUnit({
    spell("Anya", 100, "MAGE", 11),
    spell("Bok",  300, "WARRIOR", 22),
    spell("Anya", 250, "MAGE", 11),   -- second hit by Anya -> 350 total
}, isSecret)
assert(names(agg) == "Anya,Bok", "sorted desc by total (Anya 350 > Bok 300), got " .. names(agg))
assert(agg[1].totalAmount == 350 and agg[2].totalAmount == 300, "amounts summed per unit")
assert(agg[1].classFilename == "MAGE" and agg[1].specIconID == 11, "class + spec icon carried")

-- Secret unit name is skipped (can't be a table key).
local aggSecretName = AggregateSpellsByUnit({
    spell(SECRET, 999), spell("Anya", 100),
}, isSecret)
assert(names(aggSecretName) == "Anya", "secret unit name skipped, got " .. names(aggSecretName))

-- Secret amount is skipped (can't be summed).
local aggSecretAmt = AggregateSpellsByUnit({
    spell("Anya", SECRET), spell("Bok", 50),
}, isSecret)
assert(names(aggSecretAmt) == "Bok", "secret amount skipped, got " .. names(aggSecretAmt))

-- Degenerate inputs.
assert(#AggregateSpellsByUnit(nil, isSecret) == 0, "nil spells -> empty")
assert(#AggregateSpellsByUnit({}, isSecret) == 0, "empty spells -> empty")

-- ===== PivotPlayerTargets =====

-- Two enemies; Anya hit both, Bok hit one. Map keyed by player; each list
-- sorted desc by amount; enemy names carried as values.
local map = PivotPlayerTargets({
    { enemyName = "Boss", players = { { name = "Anya", totalAmount = 100 }, { name = "Bok", totalAmount = 40 } } },
    { enemyName = "Add",  players = { { name = "Anya", totalAmount = 250 } } },
})
assert(map.Anya and #map.Anya == 2, "Anya hit two enemies")
assert(names(map.Anya) == "Add,Boss", "Anya targets sorted desc (Add 250 > Boss 100), got " .. names(map.Anya))
assert(map.Bok and #map.Bok == 1 and map.Bok[1].name == "Boss", "Bok hit only Boss")

-- A secret enemy name is preserved as a value (renders in a FontString later),
-- never used as a key.
local mapSecret = PivotPlayerTargets({
    { enemyName = SECRET, players = { { name = "Anya", totalAmount = 70 } } },
})
assert(#mapSecret.Anya == 1 and mapSecret.Anya[1].name == SECRET, "secret enemy name carried as value")

assert(next(PivotPlayerTargets({})) == nil, "empty perEnemy -> empty map")
assert(next(PivotPlayerTargets(nil)) == nil, "nil perEnemy -> empty map")

print("OK: damage_meter_target_breakdown_test")
