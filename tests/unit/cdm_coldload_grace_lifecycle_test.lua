-- tests/unit/cdm_coldload_grace_lifecycle_test.lua
-- Run: lua tests/unit/cdm_coldload_grace_lifecycle_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_Timer
--
-- The cold-load grace flag must be OPENED by Initialize and CLOSED by every
-- terminal exit of RunColdLoadReconcile (combat bail, disabled bail, commit).
-- Regression: the production writer was deleted with cdm_blizz_mirror.lua
-- (cd95f3b7be); the three grace reads in cdm_spelldata.lua were dead --
-- SPELLS_CHANGED / COOLDOWN_VIEWER_DATA_LOADED bursts during cold login were
-- never absorbed, so login churned full container rebuilds.

local function noop() end

local inCombat = false
local runtimeEnabled = true

function InCombatLockdown() return inCombat end
function GetTime() return 100 end
function IsSpellKnown() return false end
function IsPlayerSpell() return false end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

-- Capture C_Timer.After callbacks instead of running them. The cold-load
-- snapshot retry has no attempt cap (it only slows down after
-- COLD_LOAD_SNAPSHOT_RETRY_MAX_ATTEMPTS), so draining it synchronously in a
-- fixture that never becomes "ready" would loop forever; capture-only lets
-- the not-ready case assert a single retry was scheduled instead.
local timerCalls = {}
C_Timer = {
    After = function(delay, fn)
        timerCalls[#timerCalls + 1] = { delay = delay, fn = fn }
    end,
}

-- All four builtin containers pre-snapshotted (ownedSpells ~= nil) so
-- SnapshotUnsetBuiltinContainers reports ready by default; case 4 knocks one
-- back to nil to force the not-ready retry path.
local function ReadyDB()
    return { builtIn = true, ownedSpells = {}, dormantSpells = {}, removedSpells = {} }
end

local ncdm = {
    essential = ReadyDB(),
    utility = ReadyDB(),
    buff = ReadyDB(),
    trackedBar = ReadyDB(),
}

local ns = {
    Addon = {
        db = {
            profile = { ncdm = ncdm },
            global = {},
        },
    },
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return runtimeEnabled end,
    },
    CDMSources = {
        QueryOverrideSpell = function(spellID) return spellID end,
        QueryBaseSpell = function() return nil end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

-- Case 1: Initialize() must open the grace at the event-registration point
-- (cold login and /reload alike).
ns.CDMSpellData:Initialize()
assert(ns._cdmColdLoadActive == true,
    "Initialize must open the cold-load grace")

-- Case 2: snapshot ready -> RunColdLoadReconcile commits and closes the grace.
ns._cdmColdLoadActive = true
ns.CDMSpellData:RunColdLoadReconcile()
assert(ns._cdmColdLoadActive == false,
    "a successful commit (snapshot ready) must close the grace")

-- Case 3: combat bail closes the grace so post-combat SPELLS_CHANGED /
-- data_loaded events run the normal reconcile instead of being absorbed
-- forever.
ns._cdmColdLoadActive = true
inCombat = true
ns.CDMSpellData:RunColdLoadReconcile()
assert(ns._cdmColdLoadActive == false,
    "a combat bail must close the grace")
inCombat = false

-- Case 4: snapshot not ready -> the grace stays open across the retry, and a
-- single C_Timer.After retry is scheduled (never drained here -- see the
-- capture-only rationale above).
ns._cdmColdLoadActive = true
ncdm.essential.ownedSpells = nil -- SnapshotBlizzardCDM now reports not-ready
local timerCallsBefore = #timerCalls
ns.CDMSpellData:RunColdLoadReconcile()
assert(ns._cdmColdLoadActive == true,
    "a snapshot-not-ready retry must keep the grace open")
assert(#timerCalls == timerCallsBefore + 1,
    "a snapshot-not-ready retry must schedule exactly one C_Timer.After retry")

print("OK: cdm_coldload_grace_lifecycle_test")
