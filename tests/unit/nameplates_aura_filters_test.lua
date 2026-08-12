-- tests/unit/nameplates_aura_filters_test.lua
-- Run: lua tests/unit/nameplates_aura_filters_test.lua
--
-- Filter compilation for the shared element model (core/aura_elements.lua),
-- exercised against nameplates' own shipped defaults
-- (NPAuras.DefaultNameplateBucket): E.CompileFilters produces each element's
-- filter string(s); E.CompileCandidateFilters carries onlyMine/whitelist/
-- blacklist as candidate filters instead of filter-string tokens; and
-- NPAuras.IsContextEnabled (unchanged since the port) still gates per
-- world/dungeon/raid.

local function fail(msg)
    print("FAIL: nameplates_aura_filters_test - " .. msg)
    os.exit(1)
end
local function eq(a, b, label)
    if a ~= b then fail(label .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end
end

local ns = { Helpers = { IsSecretValue = function() return false end } }
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("QUI_Nameplates/nameplates/shared.lua"))("QUI_Nameplates", ns)
assert(loadfile("QUI_Nameplates/nameplates/plate_auras.lua"))("QUI_Nameplates", ns)
local NP = ns.QUI_Nameplates
local Auras = NP.Auras
if not Auras then fail("NP.Auras not exported") end
local E = ns.AuraElements

local bucket = Auras.DefaultNameplateBucket()
if #bucket ~= 3 then fail("DefaultNameplateBucket must seed 3 elements, got " .. #bucket) end
local debuffs, buffs, cc = bucket[1], bucket[2], bucket[3]

local debuffFilters = E.CompileFilters(debuffs)
if #debuffFilters ~= 1 then
    fail("debuffs element must compile to a single filter string, got " .. #debuffFilters)
end
-- Mine-only strips must carry the engine-enforced PLAYER token: the Lua-side
-- isFromPlayerOrPlayerPet candidate filter cannot discriminate on secret
-- (in-combat) aura data, so without PLAYER the strip shows everyone's debuffs.
eq(debuffFilters[1], "HARMFUL|INCLUDE_NAME_PLATE_ONLY|PLAYER", "debuffs filter string")

local buffFilters = E.CompileFilters(buffs)
if #buffFilters ~= 1 then
    fail("buffs element must compile to a single filter string, got " .. #buffFilters)
end
eq(buffFilters[1], "HELPFUL|INCLUDE_NAME_PLATE_ONLY", "buffs filter string")

local ccFilters = E.CompileFilters(cc)
if #ccFilters ~= 1 then
    fail("cc element must compile to a single filter string, got " .. #ccFilters)
end
eq(ccFilters[1], "HARMFUL|CROWD_CONTROL", "cc filter string")

local debuffCF = E.CompileCandidateFilters(debuffs)
if not (debuffCF and debuffCF.isFromPlayerOrPlayerPet == true) then
    fail("mine-only debuffs must carry candidateFilters.isFromPlayerOrPlayerPet")
end
if E.CompileCandidateFilters(buffs) ~= nil then
    fail("buffs element (not mine-only) must produce no candidate filters")
end

do
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "whitelist"
    e.whitelist = { [116] = true }
    local cf = E.CompileCandidateFilters(e)
    if not (cf and cf.includeSpellIDs and cf.includeSpellIDs[116]) then
        fail("whitelist mode must produce candidateFilters.includeSpellIDs")
    end
    if cf.excludeSpellIDs ~= nil then fail("whitelist alone must not produce excludeSpellIDs") end
    local fs = E.CompileFilters(e)
    if #fs ~= 0 then
        fail("whitelist mode must leave the filter string empty, got " .. table.concat(fs, ","))
    end
end

do
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "classify"
    e.classifications = { important = true }
    e.whitelist = { [116] = true }
    local cf = E.CompileCandidateFilters(e)
    if cf and cf.includeSpellIDs then fail("whitelist must be ignored outside whitelist mode") end
end

do
    local e = E.NewFilterStripElement("HELPFUL")
    e.filterMode = "whitelist"
    e.whitelist = {}
    local cf = E.CompileCandidateFilters(e)
    if cf and cf.includeSpellIDs then fail("empty whitelist must not produce includeSpellIDs") end
end

do
    local e = E.NewFilterStripElement("HARMFUL")
    e.filterMode = "whitelist"
    e.whitelist = { [589] = true }
    e.blacklist = { [589] = true }
    local cf = E.CompileCandidateFilters(e)
    if not (cf and cf.excludeSpellIDs and cf.excludeSpellIDs[589]) then
        fail("blacklist must reach candidateFilters even when the same id is whitelisted")
    end
end

if Auras.IsEngineImportant ~= nil then
    fail("IsEngineImportant must be gone: the engine flag is a FILTER now, not a per-aura verdict")
end

local s = { enableWorld = true, enableDungeon = false, enableRaid = true }
eq(Auras.IsContextEnabled(s, "world"), true, "world on")
eq(Auras.IsContextEnabled(s, "dungeon"), false, "dungeon off")
eq(Auras.IsContextEnabled(s, "raid"), true, "raid on")
eq(Auras.IsContextEnabled({}, "world"), true, "defaults all-on")
eq(Auras.IsContextEnabled({}, "raid"), true, "defaults all-on raid")

print("OK: nameplates_aura_filters_test")
