-- tests/unit/cdm_resolvers_runtime_query_cache_test.lua
-- Run: lua tests/unit/cdm_resolvers_runtime_query_cache_test.lua

local function noop() end

function InCombatLockdown() return true end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local cooldownCalls = 0
local chargeCalls = 0
local durationCalls = 0
local chargeDurationCalls = 0
local overrideCalls = 0
local displayCountCalls = 0
local spellCountCalls = 0

local cooldownInfo = { isActive = true }
local chargeInfo = { currentCharges = 1, maxCharges = 2, isActive = true }
local durationObject = { token = "cooldown-duration" }
local chargeDurationObject = { token = "charge-duration" }
local secretDisplayCount = { token = "secret-display-count" }
local secretSpellCount = { token = "secret-spell-count" }

function issecretvalue(value)
    return rawequal(value, secretDisplayCount) or rawequal(value, secretSpellCount)
end

local ns = {
    Helpers = {},
    CDMShared = {
        IsSafeNumeric = function(value) return type(value) == "number" end,
        SafeBoolean = function(value)
            return type(value) == "boolean" and value or nil
        end,
    },
    CDMSources = {
        QuerySpellCooldown = function(spellID)
            cooldownCalls = cooldownCalls + 1
            if spellID == 101 then return cooldownInfo end
            return nil
        end,
        QuerySpellCharges = function(spellID)
            chargeCalls = chargeCalls + 1
            if spellID == 101 then return chargeInfo end
            return nil
        end,
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            durationCalls = durationCalls + 1
            if spellID == 101 and ignoreGCD == true then return durationObject end
            return nil
        end,
        QuerySpellChargeDuration = function(spellID)
            chargeDurationCalls = chargeDurationCalls + 1
            if spellID == 101 then return chargeDurationObject end
            return nil
        end,
        QueryOverrideSpell = function(spellID)
            overrideCalls = overrideCalls + 1
            if spellID == 101 then return 202 end
            return nil
        end,
        QuerySpellDisplayCount = function(spellID)
            displayCountCalls = displayCountCalls + 1
            if spellID == 101 then return secretDisplayCount end
            return nil
        end,
        QuerySpellCount = function(spellID)
            spellCountCalls = spellCountCalls + 1
            if spellID == 101 then return secretSpellCount end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)

local runtime = assert(ns.CDMRuntimeQueries, "CDMRuntimeQueries should be exported")
assert(type(runtime.BeginRuntimeQueryBatch) == "function",
    "runtime query batching should expose BeginRuntimeQueryBatch")
assert(type(runtime.EndRuntimeQueryBatch) == "function",
    "runtime query batching should expose EndRuntimeQueryBatch")

-- Outside a batch: queries always go to source. No caching active.
runtime.QueryCooldown(101)
runtime.QueryCooldown(101)
assert(cooldownCalls == 2,
    "outside a batch cooldown queries should remain live reads")

-- Inside a batch: queries are de-duplicated by spellID, regardless of owner.
-- This is the central contract — multiple icons hitting the same spell
-- within a batch share a single source read + return value, avoiding the
-- per-call Blizzard table allocation that dominated combat memaudit traces.
runtime.BeginRuntimeQueryBatch()
assert(runtime.QueryCooldown(101) == cooldownInfo,
    "first batched cooldown query should hit source and cache the payload")
assert(runtime.QueryCooldown(101) == cooldownInfo,
    "duplicate batched cooldown query should be served from the batch cache")
assert(runtime.QueryCharges(101) == chargeInfo,
    "first batched charge query should hit source and cache the payload")
assert(runtime.QueryCharges(101) == chargeInfo,
    "duplicate batched charge query should be served from the batch cache")
assert(runtime.QueryDuration(101) == durationObject,
    "first batched DurationObject query should hit source")
assert(runtime.QueryDuration(101) == durationObject,
    "duplicate batched DurationObject query should be served from the batch cache")
assert(runtime.QueryChargeDuration(101) == chargeDurationObject,
    "first batched charge DurationObject query should hit source")
assert(runtime.QueryChargeDuration(101) == chargeDurationObject,
    "duplicate batched charge DurationObject query should be served from the batch cache")
assert(runtime.QueryOverrideSpell(101) == 202,
    "batched override query should return source payload")
assert(runtime.QueryOverrideSpell(101) == 202,
    "duplicate batched override query should return the stable-cached payload")
assert(rawequal(runtime.QueryDisplayCount(101), secretDisplayCount),
    "batched display-count query should forward secret source payload")
assert(rawequal(runtime.QueryDisplayCount(101), secretDisplayCount),
    "duplicate batched display-count query should be served from the batch cache")
assert(rawequal(runtime.QuerySpellCount(101), secretSpellCount),
    "batched spell-count query should forward secret source payload")
assert(rawequal(runtime.QuerySpellCount(101), secretSpellCount),
    "duplicate batched spell-count query should be served from the batch cache")

assert(runtime.QueryCooldown(404) == nil,
    "batched nil cooldown result should pass through and cache the nil")
assert(runtime.QueryCooldown(404) == nil,
    "duplicate batched nil cooldown result should be served from the batch cache")
assert(runtime.QueryCharges(404) == nil,
    "batched nil charge result should pass through and cache the nil")
assert(runtime.QueryCharges(404) == nil,
    "duplicate batched nil charge result should be served from the batch cache")
runtime.EndRuntimeQueryBatch()

-- After the batch: one source call per distinct spellID-arg combination.
assert(cooldownCalls == 4,
    "batch cache should collapse duplicate cooldown reads (2 outside + 1 for 101 + 1 for 404)")
assert(chargeCalls == 2,
    "batch cache should collapse duplicate charge reads (1 for 101 + 1 for 404)")
assert(durationCalls == 1,
    "batch cache should collapse duplicate DurationObject reads")
assert(chargeDurationCalls == 1,
    "batch cache should collapse duplicate charge DurationObject reads")
assert(overrideCalls == 1,
    "override queries should use the stable identity cache")
assert(displayCountCalls == 1,
    "batch cache should collapse duplicate display-count reads even for secret payloads")
assert(spellCountCalls == 1,
    "batch cache should collapse duplicate spell-count reads even for secret payloads")

-- Owners are accepted for API compatibility but are not part of the cache
-- key — owner A and owner B querying the same spellID share one source
-- read in the same batch.
local owner = { _spellEntry = { viewerType = "essential", type = "spell", id = 101 } }
local otherOwner = { _spellEntry = { viewerType = "utility", type = "spell", id = 101 } }
runtime.BeginRuntimeQueryBatch()
assert(runtime.QueryCooldown(101, owner) == cooldownInfo,
    "owner cooldown query should return source payload")
assert(runtime.QueryCooldown(101, owner) == cooldownInfo,
    "duplicate owner cooldown query should be served from the batch cache")
assert(runtime.QueryCooldown(101, otherOwner) == cooldownInfo,
    "different owner querying same spell should share the batch cache entry")
assert(runtime.QueryCharges(101, owner) == chargeInfo,
    "owner charge query should return source payload")
assert(runtime.QueryCharges(101, otherOwner) == chargeInfo,
    "different owner charge query should share the batch cache entry")
assert(runtime.QueryDuration(101, owner) == durationObject,
    "owner DurationObject query should return source payload")
assert(runtime.QueryDuration(101, otherOwner) == durationObject,
    "different owner DurationObject query should share the batch cache entry")
assert(runtime.QueryChargeDuration(101, owner) == chargeDurationObject,
    "owner charge DurationObject query should return source payload")
assert(runtime.QueryChargeDuration(101, otherOwner) == chargeDurationObject,
    "different owner charge DurationObject query should share the batch cache entry")
assert(rawequal(runtime.QueryDisplayCount(101, owner), secretDisplayCount),
    "owner display-count query should forward secret source payload")
assert(rawequal(runtime.QueryDisplayCount(101, otherOwner), secretDisplayCount),
    "different owner display-count query should share the batch cache entry")
assert(rawequal(runtime.QuerySpellCount(101, owner), secretSpellCount),
    "owner spell-count query should forward secret source payload")
assert(rawequal(runtime.QuerySpellCount(101, otherOwner), secretSpellCount),
    "different owner spell-count query should share the batch cache entry")
assert(runtime.QueryCooldown(404, owner) == nil,
    "owner nil cooldown result should pass through")
assert(runtime.QueryCooldown(404, otherOwner) == nil,
    "different owner nil cooldown result should share the batch cache entry")
runtime.EndRuntimeQueryBatch()

assert(cooldownCalls == 6,
    "owner cooldown facts should share one source read across all owners (4 prior + 1 for 101 + 1 for 404)")
assert(chargeCalls == 3,
    "owner charge facts should share one source read across all owners (2 prior + 1 for 101)")
assert(durationCalls == 2,
    "owner DurationObject facts should share one source read across all owners (1 prior + 1)")
assert(chargeDurationCalls == 2,
    "owner charge DurationObject facts should share one source read across all owners (1 prior + 1)")
assert(displayCountCalls == 2,
    "owner display-count facts should share one source read across all owners")
assert(spellCountCalls == 2,
    "owner spell-count facts should share one source read across all owners")

runtime.QueryCooldown(101)
assert(cooldownCalls == 7,
    "ending a batch should restore live cooldown reads")

runtime.BeginRuntimeQueryBatch()
assert(runtime.QueryOverrideSpell(101) == 202,
    "override queries should reuse the stable cache across batches")
runtime.EndRuntimeQueryBatch()
assert(overrideCalls == 1,
    "stable override cache should avoid repeat source reads across batches")

assert(type(runtime.ClearStableCaches) == "function",
    "runtime query cache should expose stable-cache invalidation")
runtime.ClearStableCaches()
runtime.BeginRuntimeQueryBatch()
assert(runtime.QueryOverrideSpell(101) == 202,
    "stable override cache should repopulate after invalidation")
runtime.EndRuntimeQueryBatch()
assert(overrideCalls == 2,
    "stable override invalidation should allow the next batch to refresh source data")

-- Nested batches share the epoch — entries cached in the outer batch
-- remain visible to the inner batch and vice versa, until the outermost
-- EndRuntimeQueryBatch closes the run.
local nestedOwner = { _spellEntry = { viewerType = "essential", type = "spell", id = 101 } }
local cooldownCallsBeforeNested = cooldownCalls
runtime.BeginRuntimeQueryBatch()
runtime.QueryCooldown(101, nestedOwner)
runtime.BeginRuntimeQueryBatch()
runtime.QueryCooldown(101, nestedOwner)
runtime.EndRuntimeQueryBatch()
runtime.QueryCooldown(101, nestedOwner)
runtime.EndRuntimeQueryBatch()
assert(cooldownCalls == cooldownCallsBeforeNested + 1,
    "nested batches should share the batch cache until the outermost EndRuntimeQueryBatch")

runtime.ResetRuntimeQueryBatch()
local cooldownCallsBeforeNextBatches = cooldownCalls
local chargeCallsBeforeNextBatches = chargeCalls

runtime.BeginRuntimeQueryBatch()
runtime.QueryCooldown(101)
runtime.QueryCharges(101)
runtime.EndRuntimeQueryBatch()
assert(cooldownCalls == cooldownCallsBeforeNextBatches + 1,
    "first post-reset cooldown batch should query source")
assert(chargeCalls == chargeCallsBeforeNextBatches + 1,
    "first post-reset charge batch should query source")

runtime.BeginRuntimeQueryBatch()
runtime.QueryCooldown(101)
runtime.QueryCharges(101)
runtime.EndRuntimeQueryBatch()
assert(cooldownCalls == cooldownCallsBeforeNextBatches + 2,
    "cooldown activity should not be cached across runtime batches")
assert(chargeCalls == chargeCallsBeforeNextBatches + 2,
    "charge activity should not be cached across runtime batches")

runtime.BeginRuntimeQueryBatch()
runtime.QueryCooldown(101)
runtime.QueryCharges(101)
runtime.EndRuntimeQueryBatch()
assert(cooldownCalls == cooldownCallsBeforeNextBatches + 3,
    "third cooldown batch should still query fresh source data")
assert(chargeCalls == chargeCallsBeforeNextBatches + 3,
    "third charge batch should still query fresh source data")

print("OK: cdm_resolvers_runtime_query_cache_test")
