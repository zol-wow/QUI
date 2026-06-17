-- tests/unit/cdm_query_unbatched_test.lua
-- Run: lua5.1 tests/unit/cdm_query_unbatched_test.lua
-- luacheck: globals InCombatLockdown issecretvalue

local function noop() end

function InCombatLockdown() return false end
function issecretvalue() return false end

---------------------------------------------------------------------------
-- Minimal ns: stub Sources so QueryCooldown has something to call.
---------------------------------------------------------------------------
local ns = {
    CDMSources = {
        QuerySpellCooldown = function(spellID)
            return { spellID = spellID, isActive = false, isOnGCD = false }
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)

local rq = assert(ns.CDMRuntimeQueries, "CDMRuntimeQueries should be exported")

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
-- Verify the new probe is registered.
---------------------------------------------------------------------------
assert(findProbe("CDM_queryUnbatchedSource"), "CDM_queryUnbatchedSource probe should be registered")

---------------------------------------------------------------------------
-- Test 1: call QueryCooldown with NO batch open → unbatchedSourceCalls == 1.
---------------------------------------------------------------------------
local before = probeValue("CDM_queryUnbatchedSource")
rq.QueryCooldown(300)
local after = probeValue("CDM_queryUnbatchedSource")
assert(after == before + 1,
    "unbatchedSourceCalls should increment on an unbatched query (got "
    .. tostring(after) .. " expected " .. tostring(before + 1) .. ")")

---------------------------------------------------------------------------
-- Test 2: batched call does NOT increment the counter.
---------------------------------------------------------------------------
local beforeBatched = probeValue("CDM_queryUnbatchedSource")
rq.BeginRuntimeQueryBatch()
rq.QueryCooldown(301)
rq.EndRuntimeQueryBatch()
local afterBatched = probeValue("CDM_queryUnbatchedSource")
assert(afterBatched == beforeBatched,
    "unbatchedSourceCalls must NOT increment for a batched query (got "
    .. tostring(afterBatched) .. " expected " .. tostring(beforeBatched) .. ")")

print("OK: cdm_query_unbatched_test")
