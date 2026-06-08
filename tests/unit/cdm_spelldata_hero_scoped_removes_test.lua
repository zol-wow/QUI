-- tests/unit/cdm_spelldata_hero_scoped_removes_test.lua
-- Run: lua tests/unit/cdm_spelldata_hero_scoped_removes_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_ClassTalents
--
-- removedSpells is scoped per active hero sub-tree:
--   * a legacy FLAT set migrates into the global bucket [0] (still honored everywhere)
--   * RemoveEntry records the current sub-tree's bucket
--   * the render filter hides a spell only in the build that removed it
--   * re-add clears the global + current bucket, leaving other builds intact

local function noop() end
local knownSpells = {}
local activeHeroSpec = 100   -- mutable: which hero sub-tree is active

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown(spellID) return knownSpells[spellID] == true end
function IsPlayerSpell(spellID) return knownSpells[spellID] == true end
function wipe(tbl) for k in pairs(tbl) do tbl[k] = nil end end
function CreateFrame()
    return { RegisterEvent = noop, RegisterUnitEvent = noop,
             UnregisterEvent = noop, UnregisterAllEvents = noop, SetScript = noop }
end

C_ClassTalents = {
    GetActiveConfigID = function() return 777 end,
    GetActiveHeroTalentSpec = function() return activeHeroSpec end,
}

local DEATH_STRIKE = 49998
local MARROWREND  = 195182

local essentialDB = {
    builtIn = true,
    ownedSpells = {
        { type = "spell", id = DEATH_STRIKE, kind = "cooldown", source = "blizzardCDM" },
        { type = "spell", id = MARROWREND,  kind = "cooldown", source = "blizzardCDM" },
    },
    dormantSpells = {},
    -- LEGACY FLAT shape: a pre-migration removal of Marrowrend.
    removedSpells = { [MARROWREND] = true },
}

local ns = {
    Addon = { db = { profile = { ncdm = { essential = essentialDB } }, global = {} } },
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = { IsRuntimeEnabled = function() return true end },
    CDMSources = {
        QueryOverrideSpell = function(s) return s end,
        QueryBaseSpell = function() return nil end,
    },
    CDMContainers = { GetAllContainerKeys = function() return { "essential" } end },
    CDMComposer = {
        -- Both spells are valid active cooldowns in the catalog (so dormancy
        -- never fires here; this test isolates removedSpells behavior).
        RebuildBlizzardCatalogMaps = function(spellToCDID, inCooldowns)
            for _, id in ipairs({ DEATH_STRIKE, MARROWREND }) do
                spellToCDID[id] = id
                inCooldowns[id] = true
            end
        end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

knownSpells[DEATH_STRIKE] = true
knownSpells[MARROWREND] = true

local function idsInBuild()
    local list = ns.CDMSpellData:BuildSpellListFromOwned("essential")
    local seen = {}
    for _, e in ipairs(list) do seen[e.id or (e.entry and e.entry.id)] = true end
    return seen
end

-- Legacy flat removal must migrate to the global bucket and stay suppressed.
local seen = idsInBuild()
assert(seen[DEATH_STRIKE], "Death Strike must render")
assert(not seen[MARROWREND], "legacy-removed Marrowrend must stay hidden (global bucket)")
assert(type(essentialDB.removedSpells[0]) == "table" and essentialDB.removedSpells[0][MARROWREND],
    "flat removedSpells must migrate into the [0] global bucket")

-- The global bucket suppresses in EVERY hero build.
activeHeroSpec = 200
assert(not idsInBuild()[MARROWREND], "global-bucket removal applies in all hero builds")

-- Scoped hard-remove: removing Death Strike while hero build 100 is active
-- must hide it in build 100 only, not in build 200.
activeHeroSpec = 100
local idx
for i, e in ipairs(essentialDB.ownedSpells) do if e.id == DEATH_STRIKE then idx = i end end
assert(idx, "Death Strike must still be in ownedSpells before removal")
assert(ns.CDMSpellData:RemoveEntry("essential", idx) == true, "RemoveEntry should succeed")

-- It is gone from the list entirely (RemoveEntry pulls it from ownedSpells)...
local present = {}
for _, e in ipairs(essentialDB.ownedSpells) do present[e.id] = true end
assert(not present[DEATH_STRIKE], "RemoveEntry deletes the entry from ownedSpells")
-- ...and the removal is recorded in build 100's bucket, not the global one.
assert(type(essentialDB.removedSpells[100]) == "table"
    and essentialDB.removedSpells[100][DEATH_STRIKE] == true,
    "hard-remove records the active hero sub-tree's bucket")
assert(not (essentialDB.removedSpells[0] and essentialDB.removedSpells[0][DEATH_STRIKE]),
    "hard-remove must NOT touch the global bucket")

-- Re-add Death Strike: clears global + current bucket; other builds untouched.
ns.CDMSpellData:AddSpell("essential", DEATH_STRIKE, "cooldown")
ns.CDMSpellData:ClearRemoved(essentialDB, DEATH_STRIKE)
assert(not (essentialDB.removedSpells[100] and essentialDB.removedSpells[100][DEATH_STRIKE]),
    "re-add clears the current build's removal")

print("OK: cdm_spelldata_hero_scoped_removes_test")
