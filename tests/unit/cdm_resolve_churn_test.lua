-- tests/unit/cdm_resolve_churn_test.lua
-- Run: lua tests/unit/cdm_resolve_churn_test.lua
-- luacheck: globals InCombatLockdown geterrorhandler CreateFrame GetTime issecretvalue Enum C_CurveUtil C_DurationUtil GetInventoryItemCooldown

local function noop() end

function InCombatLockdown() return false end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end
function GetTime() return 100 end
function issecretvalue() return false end
Enum = { LuaCurveType = { Step = "Step" } }
C_CurveUtil = {
    CreateCurve = function()
        return {
            SetType = noop,
            AddPoint = noop,
            Evaluate = function() return 0 end,
        }
    end,
}
C_DurationUtil = {
    CreateDuration = function()
        local obj = {}
        function obj:SetTimeFromStart() end
        return obj
    end,
}
function GetInventoryItemCooldown() return nil, nil, nil end

---------------------------------------------------------------------------
-- Minimal CDM mirror state: one spell with a known aura overlay (spellID 70001)
-- and one with no aura (spellID 70002). The aura probe is the general path
-- (non-mirror) triggered when mirrorPayload is nil.
---------------------------------------------------------------------------
local auraActive = false   -- flipped per-test to drive auraProbeHit vs noAura

local ns = {
    Helpers = {},
    CDMShared = {
        IsSafeNumeric = function(v) return type(v) == "number" end,
    },
    CDMSources = {
        QuerySpellCharges = function() return nil end,
        QuerySpellCooldown = function(spellID)
            if spellID == 70002 then
                return { isActive = true, isOnGCD = false }
            end
            return { isActive = false, isOnGCD = false }
        end,
        QuerySpellCooldownDuration = function() return nil end,
        QuerySpellChargeDuration = function() return nil end,
        QueryOverrideSpell = function() return nil end,
        QuerySpellInfo = function() return nil end,
        QueryItemSpell = function() return nil end,
        QueryItemCooldown = function() return nil end,
        QueryItemAura = function() return nil end,
        QuerySpellUsable = function() return true, false end,
    },
    CDMAuraRuntime = {
        ResolveState = function(params)
            if params and params.spellID == 70001 and auraActive then
                return {
                    isActive = true,
                    auraInstanceID = 700010,
                    auraUnit = "player",
                    durObj = nil,
                    resolvedAuraSpellID = 70001,
                    count = { shown = false },
                }
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function() return nil end,
        HasChildForCooldownID = function() return false end,
        GetDirectCooldownIDForViewer = function() return nil end,
        GetCooldownIDForViewer = function() return nil end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers should be exported")
local resolve = assert(resolvers.ResolveCooldownState, "ResolveCooldownState should be exported")
local setTag = assert(resolvers.SetResolveCallerTag, "SetResolveCallerTag should be exported")

---------------------------------------------------------------------------
-- Helper: find a memprobe by name and return its fn.
---------------------------------------------------------------------------
local function findProbe(name)
    local mp = ns._memprobes or {}
    for _, probe in ipairs(mp) do
        if probe.name == name then
            return probe.fn
        end
    end
    return nil
end

local function probeValue(name)
    local fn = findProbe(name)
    assert(fn, "memprobe not found: " .. name)
    return fn()
end

---------------------------------------------------------------------------
-- Verify all expected memprobes are registered.
---------------------------------------------------------------------------
local expectedProbes = {
    "CDM_resolveBy_spellID",
    "CDM_resolveBy_aura",
    "CDM_resolveBy_usability",
    "CDM_resolveBy_catalog",
    "CDM_resolveBy_walk",
    "CDM_resolveBy_cooldownOnly",
    "CDM_resolveBy_other",
    "CDM_resolveBy_item",
    "CDM_resolveBy_auraScope",
    "CDM_resolveBy_spellQueue",
    "CDM_resolveBy_expiry",
    "CDM_resolveBy_mirrorCooldownOnly",
    "CDM_resolveBy_auraScopedCooldown",
    "CDM_resolveBy_ownedBar",
    "CDM_resolveBy_mirrorRefresh",
    "CDM_resolveBy_typeRefresh",
    "CDM_resolveBy_runtimeTypeRefresh",
    "CDM_resolveBy_iconPlaced",
    "CDM_auraProbeHit",
    "CDM_auraProbeGuardSkip",
    "CDM_auraProbeExpensiveMiss",
}
for _, name in ipairs(expectedProbes) do
    assert(findProbe(name), "expected memprobe to be registered: " .. name)
end

---------------------------------------------------------------------------
-- A minimal spell entry for a non-aura, non-item, non-mirror spell.
---------------------------------------------------------------------------
local function cooldownEntry(spellID)
    return {
        type = "spell",
        kind = "cooldown",
        id = spellID,
        spellID = spellID,
        viewerType = "essential",
    }
end

local function doResolve(spellID)
    return resolve({
        entry = cooldownEntry(spellID),
        runtimeSpellID = spellID,
        containerKey = "essential",
        -- useBuffSwipe defaults to nil/unset so the aura probe is not short-circuited
        -- (ResolveAuraRuntimeStateForContext skips probe when useBuffSwipe == false)
    })
end

---------------------------------------------------------------------------
-- Test 1: tagged resolve increments resolveBy[tag].
---------------------------------------------------------------------------
local beforeSpellID = probeValue("CDM_resolveBy_spellID")
setTag("spellID")
doResolve(70002)
setTag(nil)
local afterSpellID = probeValue("CDM_resolveBy_spellID")
assert(afterSpellID == beforeSpellID + 1,
    "resolveBy_spellID should increment on a spellID-tagged resolve (got "
    .. tostring(afterSpellID) .. " expected " .. tostring(beforeSpellID + 1) .. ")")

---------------------------------------------------------------------------
-- Test 2: two different tags accumulate independently.
---------------------------------------------------------------------------
local beforeUsability = probeValue("CDM_resolveBy_usability")
local beforeWalk = probeValue("CDM_resolveBy_walk")

setTag("usability")
doResolve(70002)
setTag(nil)

setTag("walk")
doResolve(70002)
setTag(nil)

assert(probeValue("CDM_resolveBy_usability") == beforeUsability + 1,
    "resolveBy_usability should increment on a usability-tagged resolve")
assert(probeValue("CDM_resolveBy_walk") == beforeWalk + 1,
    "resolveBy_walk should increment on a walk-tagged resolve")
-- spellID counter should not have changed again
assert(probeValue("CDM_resolveBy_spellID") == afterSpellID,
    "resolveBy_spellID should not increment for walk-tagged resolves")

---------------------------------------------------------------------------
-- Test 3: untagged resolve increments other.
---------------------------------------------------------------------------
local beforeOther = probeValue("CDM_resolveBy_other")
-- no setTag call — tag is nil
doResolve(70002)
assert(probeValue("CDM_resolveBy_other") == beforeOther + 1,
    "resolveBy_other should increment when no tag is set")

---------------------------------------------------------------------------
-- Test 4: SetResolveCallerTag(nil) resets to other.
---------------------------------------------------------------------------
local beforeOther2 = probeValue("CDM_resolveBy_other")
local beforeCatalog = probeValue("CDM_resolveBy_catalog")
setTag("catalog")
setTag(nil)   -- explicit reset before any resolve runs under the catalog tag
doResolve(70002)
assert(probeValue("CDM_resolveBy_other") == beforeOther2 + 1,
    "after SetResolveCallerTag(nil) the next resolve should count as other")
assert(probeValue("CDM_resolveBy_catalog") == beforeCatalog,
    "catalog counter must NOT change: tag was reset to nil before the resolve")

---------------------------------------------------------------------------
-- Test 5: aura probe — expensiveMiss path.
-- useBuffSwipe is nil (not false), entryIsAura is false → expensive miss
-- (the guard condition is NOT met, so C_UnitAuras would be probed, but
-- auraActive=false means nothing found).
---------------------------------------------------------------------------
auraActive = false
local beforeExpMiss = probeValue("CDM_auraProbeExpensiveMiss")
local beforeGuard = probeValue("CDM_auraProbeGuardSkip")
local beforeHit = probeValue("CDM_auraProbeHit")
doResolve(70001)   -- useBuffSwipe nil → not a guard-skip → expensiveMiss
assert(probeValue("CDM_auraProbeExpensiveMiss") == beforeExpMiss + 1,
    "auraProbeExpensiveMiss should increment when probe runs but finds nothing (useBuffSwipe nil)")
assert(probeValue("CDM_auraProbeGuardSkip") == beforeGuard,
    "auraProbeGuardSkip should not increment when useBuffSwipe is nil")
assert(probeValue("CDM_auraProbeHit") == beforeHit,
    "auraProbeHit should not increment when probe returns nil/inactive")

---------------------------------------------------------------------------
-- Test 6: aura probe — guardSkip path.
-- useBuffSwipe == false AND entryIsAura == false → cheap guard-skip.
---------------------------------------------------------------------------
auraActive = false
local beforeGuard2 = probeValue("CDM_auraProbeGuardSkip")
local beforeExpMiss2 = probeValue("CDM_auraProbeExpensiveMiss")
local beforeHit2 = probeValue("CDM_auraProbeHit")
local guardContext = {
    entry = cooldownEntry(70001),
    runtimeSpellID = 70001,
    containerKey = "essential",
    useBuffSwipe = false,   -- explicit false → guard-skip
}
resolve(guardContext)
assert(probeValue("CDM_auraProbeGuardSkip") == beforeGuard2 + 1,
    "auraProbeGuardSkip should increment when useBuffSwipe==false and not entryIsAura")
assert(probeValue("CDM_auraProbeExpensiveMiss") == beforeExpMiss2,
    "auraProbeExpensiveMiss should not increment on a guard-skip")
assert(probeValue("CDM_auraProbeHit") == beforeHit2,
    "auraProbeHit should not increment on a guard-skip")

---------------------------------------------------------------------------
-- Test 7: aura probe — hit path.
---------------------------------------------------------------------------
auraActive = true
local beforeHit3 = probeValue("CDM_auraProbeHit")
local beforeGuard3 = probeValue("CDM_auraProbeGuardSkip")
local beforeExpMiss3 = probeValue("CDM_auraProbeExpensiveMiss")
doResolve(70001)   -- spellID 70001: aura probe will fire, auraActive=true → hit
assert(probeValue("CDM_auraProbeHit") == beforeHit3 + 1,
    "auraProbeHit should increment when probe returns an active aura")
assert(probeValue("CDM_auraProbeGuardSkip") == beforeGuard3,
    "auraProbeGuardSkip should not increment on a hit")
assert(probeValue("CDM_auraProbeExpensiveMiss") == beforeExpMiss3,
    "auraProbeExpensiveMiss should not increment on a hit")

---------------------------------------------------------------------------
-- Test 8: new resolveBy tags accumulate independently.
---------------------------------------------------------------------------
local beforeItem = probeValue("CDM_resolveBy_item")
local beforeAuraScope = probeValue("CDM_resolveBy_auraScope")
local beforeSpellQueue = probeValue("CDM_resolveBy_spellQueue")
auraActive = false

setTag("item")
doResolve(70002)
setTag(nil)
assert(probeValue("CDM_resolveBy_item") == beforeItem + 1,
    "resolveBy_item should increment on an item-tagged resolve")
assert(probeValue("CDM_resolveBy_auraScope") == beforeAuraScope,
    "resolveBy_auraScope should not increment for item-tagged resolve")

setTag("auraScope")
doResolve(70002)
setTag(nil)
assert(probeValue("CDM_resolveBy_auraScope") == beforeAuraScope + 1,
    "resolveBy_auraScope should increment on an auraScope-tagged resolve")
assert(probeValue("CDM_resolveBy_spellQueue") == beforeSpellQueue,
    "resolveBy_spellQueue should not increment for auraScope-tagged resolve")

setTag("spellQueue")
doResolve(70002)
setTag(nil)
assert(probeValue("CDM_resolveBy_spellQueue") == beforeSpellQueue + 1,
    "resolveBy_spellQueue should increment on a spellQueue-tagged resolve")

---------------------------------------------------------------------------
-- Test 9: ownedBar tag increments resolveBy.ownedBar.
---------------------------------------------------------------------------
local beforeOwnedBar = probeValue("CDM_resolveBy_ownedBar")
local beforeOther9 = probeValue("CDM_resolveBy_other")
auraActive = false
setTag("ownedBar")
doResolve(70002)
setTag(nil)
assert(probeValue("CDM_resolveBy_ownedBar") == beforeOwnedBar + 1,
    "resolveBy_ownedBar should increment on an ownedBar-tagged resolve")
assert(probeValue("CDM_resolveBy_other") == beforeOther9,
    "resolveBy_other must not increment when ownedBar tag is set")

---------------------------------------------------------------------------
-- Test 10: mirrorRefresh tag increments resolveBy.mirrorRefresh.
---------------------------------------------------------------------------
local beforeMirrorRefresh = probeValue("CDM_resolveBy_mirrorRefresh")
local beforeOther10 = probeValue("CDM_resolveBy_other")
setTag("mirrorRefresh")
doResolve(70002)
setTag(nil)
assert(probeValue("CDM_resolveBy_mirrorRefresh") == beforeMirrorRefresh + 1,
    "resolveBy_mirrorRefresh should increment on a mirrorRefresh-tagged resolve")
assert(probeValue("CDM_resolveBy_other") == beforeOther10,
    "resolveBy_other must not increment when mirrorRefresh tag is set")

print("OK: cdm_resolve_churn_test")
