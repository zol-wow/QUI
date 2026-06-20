-- tests/unit/cdm_sources_aura_memo_test.lua
-- Run: lua tests/unit/cdm_sources_aura_memo_test.lua
--
-- Verifies the cdm_sources aura-query memo: a HIT returns the prior result
-- without re-calling the C function; nil results are memoized; invalidation
-- forces a re-probe; filters and C-function families get separate buckets;
-- non-cacheable units and secret ids bypass the cache entirely.

-- The module captures issecretvalue at load, so it must read a live set the
-- test can extend later (T15 marks an instanceID secret after load).
local secretValues = {}
local secretSpellID = { token = "secret-spell-id" }
secretValues[secretSpellID] = true

-- Per-C-function call counters and scripted returns.
local calls = { unit = 0, player = 0, data = 0, name = 0 }
local function makeAura(tag) return { token = tag } end

_G.wipe = function(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

function issecretvalue(value) return secretValues[value] == true end

-- Returns scripted from these tables; a nil entry models "no such aura".
-- auraInstanceID lets the delta-invalidation tests match cached AuraData.
local unitReturns = {
    [100] = { token = "unit-100", auraInstanceID = 5100 },
    [200] = { token = "unit-200", auraInstanceID = 5200 },
}
local playerReturns = { [100] = makeAura("player-100") }
local dataReturns = { [100] = makeAura("data-100") }
local nameReturns = { Foo = makeAura("name-Foo") }

C_UnitAuras = {
    GetUnitAuraBySpellID = function(_unit, spellID, _filter)
        calls.unit = calls.unit + 1
        return unitReturns[spellID]
    end,
    GetPlayerAuraBySpellID = function(spellID)
        calls.player = calls.player + 1
        return playerReturns[spellID]
    end,
    GetAuraDataBySpellID = function(_unit, spellID, _filter)
        calls.data = calls.data + 1
        return dataReturns[spellID]
    end,
    GetAuraDataBySpellName = function(_unit, name, _filter)
        calls.name = calls.name + 1
        return nameReturns[name]
    end,
}

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)
local S = ns.CDMSources

---------------------------------------------------------------------------
-- T1: identical query is a HIT — underlying C function called exactly once.
---------------------------------------------------------------------------
local a1 = S.QueryUnitAuraBySpellID("player", 100)
local a2 = S.QueryUnitAuraBySpellID("player", 100)
assert(a1 == unitReturns[100], "first query returns the live result")
assert(a2 == a1, "second query returns the memoized result")
assert(calls.unit == 1, "memoized hit must not re-call the C function (got " .. calls.unit .. ")")

---------------------------------------------------------------------------
-- T2: a nil result is memoized too — no re-probe for a known-absent aura.
---------------------------------------------------------------------------
local before = calls.unit
assert(S.QueryUnitAuraBySpellID("player", 999) == nil, "absent aura returns nil")
assert(S.QueryUnitAuraBySpellID("player", 999) == nil, "absent aura still nil")
assert(calls.unit == before + 1, "nil result must be memoized (got " .. (calls.unit - before) .. " calls)")

---------------------------------------------------------------------------
-- T3: invalidation forces a fresh C call.
---------------------------------------------------------------------------
before = calls.unit
S.InvalidateAuraMemoForUnit("player")
S.QueryUnitAuraBySpellID("player", 100)
assert(calls.unit == before + 1, "invalidation must drop the memo and re-probe")
S.QueryUnitAuraBySpellID("player", 100)
assert(calls.unit == before + 1, "re-probe result is memoized again")

---------------------------------------------------------------------------
-- T4: filters get separate buckets (nil / HELPFUL / HARMFUL distinct).
---------------------------------------------------------------------------
before = calls.unit
S.QueryUnitAuraBySpellID("player", 200, "HELPFUL")
S.QueryUnitAuraBySpellID("player", 200, "HARMFUL")
assert(calls.unit == before + 2, "distinct filters are distinct buckets")
S.QueryUnitAuraBySpellID("player", 200, "HELPFUL")
S.QueryUnitAuraBySpellID("player", 200, "HARMFUL")
assert(calls.unit == before + 2, "each filter bucket memoizes independently")

---------------------------------------------------------------------------
-- T5: non-cacheable unit (focus) always hits the live path.
---------------------------------------------------------------------------
before = calls.unit
S.QueryUnitAuraBySpellID("focus", 100)
S.QueryUnitAuraBySpellID("focus", 100)
assert(calls.unit == before + 2, "non-cacheable unit must never memoize")

---------------------------------------------------------------------------
-- T6: secret spellID bypasses the cache (cannot key a table on a secret).
---------------------------------------------------------------------------
before = calls.unit
S.QueryUnitAuraBySpellID("player", secretSpellID)
S.QueryUnitAuraBySpellID("player", secretSpellID)
assert(calls.unit == before + 2, "secret id must bypass the memo")

---------------------------------------------------------------------------
-- T7: target memo is independent of player memo.
---------------------------------------------------------------------------
S.InvalidateAllAuraMemo()
calls.unit = 0
S.QueryUnitAuraBySpellID("target", 100)
S.QueryUnitAuraBySpellID("player", 100)
assert(calls.unit == 2, "target and player are separate cache scopes")
S.InvalidateAuraMemoForUnit("player")
S.QueryUnitAuraBySpellID("target", 100) -- still cached
S.QueryUnitAuraBySpellID("player", 100) -- re-probed
assert(calls.unit == 3, "invalidating player must not drop target (got " .. calls.unit .. ")")

---------------------------------------------------------------------------
-- T8: distinct C-function families (UnitAura vs AuraData vs Player vs Name)
-- never share a bucket.
---------------------------------------------------------------------------
S.InvalidateAllAuraMemo()
calls.unit, calls.player, calls.data, calls.name = 0, 0, 0, 0
S.QueryUnitAuraBySpellID("player", 100)
S.QueryAuraDataBySpellID("player", 100)
S.QueryPlayerAuraBySpellID(100)
S.QueryAuraDataBySpellName("player", "Foo")
assert(calls.unit == 1 and calls.data == 1 and calls.player == 1 and calls.name == 1,
    "each C family probes once")
-- repeats all memoized
S.QueryUnitAuraBySpellID("player", 100)
S.QueryAuraDataBySpellID("player", 100)
S.QueryPlayerAuraBySpellID(100)
S.QueryAuraDataBySpellName("player", "Foo")
assert(calls.unit == 1 and calls.data == 1 and calls.player == 1 and calls.name == 1,
    "every family memoizes independently with no cross-talk")

---------------------------------------------------------------------------
-- T9: InvalidateAll drops every unit at once.
---------------------------------------------------------------------------
before = calls.unit
S.InvalidateAllAuraMemo()
S.QueryUnitAuraBySpellID("player", 100)
assert(calls.unit == before + 1, "InvalidateAll must re-probe player")

---------------------------------------------------------------------------
-- T10: delta invalidation — an updated instanceID drops ONLY its cached entry;
-- unrelated present entries stay warm (the whole point — no cold-wipe).
---------------------------------------------------------------------------
S.InvalidateAllAuraMemo()
calls.unit = 0
S.QueryUnitAuraBySpellID("player", 100) -- present, auraInstanceID 5100
S.QueryUnitAuraBySpellID("player", 200) -- present, auraInstanceID 5200
assert(calls.unit == 2, "prime two present entries")
S.InvalidateAuraMemoForDelta("player", { updatedAuraInstanceIDs = { 5100 } })
S.QueryUnitAuraBySpellID("player", 100) -- 5100 changed -> re-probe
S.QueryUnitAuraBySpellID("player", 200) -- untouched -> stays warm
assert(calls.unit == 3, "only the updated instance re-probes; the rest stay warm (got " .. calls.unit .. ")")

---------------------------------------------------------------------------
-- T11: a removed instanceID drops its entry.
---------------------------------------------------------------------------
S.InvalidateAllAuraMemo()
calls.unit = 0
S.QueryUnitAuraBySpellID("player", 100)
S.QueryUnitAuraBySpellID("player", 200)
S.InvalidateAuraMemoForDelta("player", { removedAuraInstanceIDs = { 5200 } })
S.QueryUnitAuraBySpellID("player", 100) -- warm
S.QueryUnitAuraBySpellID("player", 200) -- removed -> re-probe
assert(calls.unit == 3, "removed instance re-probes; sibling stays warm (got " .. calls.unit .. ")")

---------------------------------------------------------------------------
-- T12: an unrelated delta touches nothing — full hit-rate preserved.
---------------------------------------------------------------------------
S.InvalidateAllAuraMemo()
calls.unit = 0
S.QueryUnitAuraBySpellID("player", 100)
S.QueryUnitAuraBySpellID("player", 200)
S.InvalidateAuraMemoForDelta("player", { updatedAuraInstanceIDs = { 9999 } })
S.QueryUnitAuraBySpellID("player", 100)
S.QueryUnitAuraBySpellID("player", 200)
assert(calls.unit == 2, "a delta that matches nothing must not drop any entry")

---------------------------------------------------------------------------
-- T13: addedAuras re-probes a previously-nil key (a newly-applied aura must be
-- seen) without disturbing unrelated present entries.
---------------------------------------------------------------------------
S.InvalidateAllAuraMemo()
calls.unit = 0
S.QueryUnitAuraBySpellID("player", 100)   -- present, warm
assert(S.QueryUnitAuraBySpellID("player", 777) == nil) -- cache a nil
assert(calls.unit == 2, "prime one present + one nil")
S.InvalidateAuraMemoForDelta("player", { addedAuras = { { spellId = 777, auraInstanceID = 5777 } } })
S.QueryUnitAuraBySpellID("player", 100)    -- unrelated present -> warm
S.QueryUnitAuraBySpellID("player", 777)    -- added -> nil entry dropped -> re-probe
assert(calls.unit == 3, "added spellId re-probes its key; present sibling stays warm (got " .. calls.unit .. ")")

---------------------------------------------------------------------------
-- T14: isFullUpdate / nil payload wipes the whole unit.
---------------------------------------------------------------------------
S.InvalidateAllAuraMemo()
calls.unit = 0
S.QueryUnitAuraBySpellID("player", 100)
S.QueryUnitAuraBySpellID("player", 200)
S.InvalidateAuraMemoForDelta("player", { isFullUpdate = true })
S.QueryUnitAuraBySpellID("player", 100)
S.QueryUnitAuraBySpellID("player", 200)
assert(calls.unit == 4, "isFullUpdate must wipe the whole unit")

---------------------------------------------------------------------------
-- T15: a secret removed instanceID can't be matched -> conservative drop of
-- present entries with unreadable instanceIDs (correctness over precision).
---------------------------------------------------------------------------
local secretIID = { token = "secret-iid" }
secretValues[secretIID] = true
unitReturns[300] = { token = "unit-300", auraInstanceID = secretIID }
S.InvalidateAllAuraMemo()
calls.unit = 0
S.QueryUnitAuraBySpellID("player", 300) -- present, secret instanceID
S.InvalidateAuraMemoForDelta("player", { removedAuraInstanceIDs = { secretIID } })
S.QueryUnitAuraBySpellID("player", 300) -- unverifiable -> dropped -> re-probe
assert(calls.unit == 2, "secret changed instanceID forces a conservative re-probe (got " .. calls.unit .. ")")
secretValues[secretIID] = nil

print("OK: cdm_sources_aura_memo_test")
