-- tests/unit/cdm_sources_secret_aura_gate_test.lua
-- Run: lua tests/unit/cdm_sources_secret_aura_gate_test.lua
--
-- 12.1: instance-ID aura getters (RequiresUnitAuraAccess) THROW while aura
-- data is globally secret (C_Secrets.ShouldAurasBeSecret() == true), even when
-- the auraInstanceID argument is a plain number cached before combat. The
-- Query* wrappers must bail to nil WITHOUT calling the C function while the
-- predicate is true, and pass through normally when it is false. Spell-based
-- getters (RequiresNonSecretAura — return secrets, never throw) must NOT be
-- gated.

-- Task 7: InstallSecretStub installs the __QUI_SECRET_* instrumentation
-- helpers the LoadInstrumented chunk below routes through. The test's own
-- issecretvalue (next lines) OVERRIDES the sentinel stub afterwards; the
-- helpers late-bind _G.issecretvalue at call time, so they compose.
local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
SecretSentinel.InstallSecretStub()

local secretValues = {}
function issecretvalue(value) return secretValues[value] == true end

_G.wipe = function(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

-- Simulated global aura secrecy. The instance getters below enforce the same
-- contract the live client does: called while secret -> hard Lua error.
local aurasSecret = false
C_Secrets = {
    ShouldAurasBeSecret = function() return aurasSecret end,
}

local calls = {
    duration = 0,
    data = 0,
    expiration = 0,
    filtered = 0,
    appCount = 0,
    unitAuras = 0,
    bySpell = 0,
    playerBySpell = 0,
    dataBySpell = 0,
    byName = 0,
}

local function instanceGetter(counterKey, result)
    return function(...)
        if aurasSecret then
            error(counterKey .. "(): Auras cannot be accessed when secret while tainted")
        end
        calls[counterKey] = calls[counterKey] + 1
        return result
    end
end

local durationToken = { token = "duration" }
local auraDataToken = { token = "aura-data" }
local wholeSecretAura = SecretSentinel.MakeSecretSentinel()
local secretPolarity = { token = "secret-polarity" }
local auraWithSecretPolarity = { isHelpful = secretPolarity }
secretValues[wholeSecretAura] = true
secretValues[secretPolarity] = true

C_UnitAuras = {
    GetAuraDuration = instanceGetter("duration", durationToken),
    GetAuraDataByAuraInstanceID = function(_unit, auraInstanceID)
        if aurasSecret then
            error("data(): Auras cannot be accessed when secret while tainted")
        end
        calls.data = calls.data + 1
        return auraInstanceID == 777 and wholeSecretAura or auraDataToken
    end,
    DoesAuraHaveExpirationTime = instanceGetter("expiration", true),
    IsAuraFilteredOutByInstanceID = instanceGetter("filtered", false),
    GetAuraApplicationDisplayCount = instanceGetter("appCount", 3),
    GetUnitAuras = instanceGetter("unitAuras", { auraDataToken }),
    GetUnitAuraBySpellID = function(_unit, spellID, _filter)
        -- Spell getters never throw; they return (possibly secret) AuraData.
        calls.bySpell = calls.bySpell + 1
        if spellID == 101 then return wholeSecretAura end
        if spellID == 102 then return auraWithSecretPolarity end
        return auraDataToken
    end,
    GetPlayerAuraBySpellID = function()
        calls.playerBySpell = calls.playerBySpell + 1
        return wholeSecretAura
    end,
    GetAuraDataBySpellID = function()
        calls.dataBySpell = calls.dataBySpell + 1
        return wholeSecretAura
    end,
    GetAuraDataBySpellName = function()
        calls.byName = calls.byName + 1
        return wholeSecretAura
    end,
}

local ns = {}
-- Instrumented load (Task 7): cdm_sources.lua exists standalone, so the
-- consolidated-chunk helper reduced to a plain load — replaced with the
-- instrumented loader (truthiness/==/# on sentinels now THROW inside it).
assert(SecretSentinel.LoadInstrumented("QUI_CDM/cdm/cdm_sources.lua"))("QUI", ns)
local S = ns.CDMSources

---------------------------------------------------------------------------
-- T1: AreAurasSecret mirrors the predicate.
---------------------------------------------------------------------------
assert(S.AreAurasSecret() == false, "T1: not secret out of combat")
aurasSecret = true
assert(S.AreAurasSecret() == true, "T1: secret while predicate true")
aurasSecret = false

---------------------------------------------------------------------------
-- T2: non-secret window — every wrapper passes through to the C function.
---------------------------------------------------------------------------
assert(S.QueryAuraDuration("player", 1685) == durationToken, "T2: duration passes through")
assert(S.QueryAuraDataByAuraInstanceID("player", 1685) == auraDataToken, "T2: data passes through")
assert(S.QueryAuraHasExpirationTime("player", 1685) == true, "T2: expiration passes through")
assert(S.QueryAuraFilteredOutByInstanceID("target", 1, "HARMFUL|PLAYER") == false, "T2: filter passes through")
assert(S.QueryAuraApplicationDisplayCount("player", 1731, 0, 99) == 3, "T2: app count passes through")
assert(S.QueryUnitAuras("target", "HARMFUL|PLAYER", 40)[1] == auraDataToken,
    "T2: unit aura scan passes through")
assert(calls.duration == 1 and calls.data == 1 and calls.expiration == 1
    and calls.filtered == 1 and calls.appCount == 1 and calls.unitAuras == 1,
    "T2: each C function called exactly once")

---------------------------------------------------------------------------
-- T3: secret window — wrappers return nil and NEVER reach the C function
-- (the mock throws if reached; plain cached IDs must not be forwarded).
---------------------------------------------------------------------------
aurasSecret = true
assert(S.QueryAuraDuration("player", 1685) == nil, "T3: duration gated to nil")
assert(S.QueryAuraDataByAuraInstanceID("player", 1685) == nil, "T3: data gated to nil")
assert(S.QueryAuraHasExpirationTime("player", 1685) == nil, "T3: expiration gated to nil")
assert(S.QueryAuraFilteredOutByInstanceID("target", 1, "HARMFUL|PLAYER") == nil, "T3: filter gated to nil")
assert(S.QueryAuraApplicationDisplayCount("player", 1731, 0, 99) == nil, "T3: app count gated to nil")
assert(S.QueryUnitAuras("target", "HARMFUL|PLAYER", 40) == nil, "T3: unit aura scan gated to nil")
assert(calls.duration == 1 and calls.data == 1 and calls.expiration == 1
    and calls.filtered == 1 and calls.appCount == 1 and calls.unitAuras == 1,
    "T3: no additional C calls while secret")

---------------------------------------------------------------------------
-- T4: spell-based getter is NOT gated — safe API, must keep resolving the
-- whitelisted auras that carry CDM through combat.
---------------------------------------------------------------------------
assert(S.QueryUnitAuraBySpellID("player", 100) == auraDataToken, "T4: spell getter still resolves while secret")
assert(calls.bySpell >= 1, "T4: spell getter reached the C function")
aurasSecret = false

local function assertCleanOpaquePresence(label, query)
    local ok, value = pcall(query)
    assert(ok, label .. " must quarantine the whole-secret AuraData")
    assert(type(value) == "table", label .. " must return clean presence metadata")
    assert(value.auraInstanceID == nil, label .. " must not expose the secret payload")
end

local bySpellBefore = calls.bySpell
assertCleanOpaquePresence("T4 unit spell getter", function()
    return S.QueryUnitAuraBySpellID("player", 101, "HELPFUL")
end)
assertCleanOpaquePresence("T4 repeated unit spell getter", function()
    return S.QueryUnitAuraBySpellID("player", 101, "HELPFUL")
end)
assert(calls.bySpell == bySpellBefore + 2, "T4 opaque presence must not be memoized")
assertCleanOpaquePresence("T4 secret polarity", function()
    return S.QueryUnitAuraBySpellID("player", 102, "HELPFUL")
end)
assertCleanOpaquePresence("T4 player spell getter", function()
    return S.QueryPlayerAuraBySpellID(101)
end)
assertCleanOpaquePresence("T4 data spell getter", function()
    return S.QueryAuraDataBySpellID("player", 101, "HELPFUL")
end)
assertCleanOpaquePresence("T4 name getter", function()
    return S.QueryAuraDataBySpellName("player", "Secret Aura", "HELPFUL")
end)
assertCleanOpaquePresence("T4 instance getter", function()
    return S.QueryAuraDataByAuraInstanceID("player", 777)
end)

---------------------------------------------------------------------------
-- T5: secret auraInstanceID still rejected even when auras are NOT secret
-- (pre-existing HasOpaqueValue contract preserved).
---------------------------------------------------------------------------
local secretID = { token = "secret-instance-id" }
secretValues[secretID] = true
assert(S.QueryAuraDuration("player", secretID) == nil, "T5: secret ID rejected")
assert(calls.duration == 1, "T5: secret ID never forwarded to the C function")

---------------------------------------------------------------------------
-- T6: absent C_Secrets (test harness / older client) — fail open, no gate.
---------------------------------------------------------------------------
do
    local ns2 = {}
    local savedSecrets = C_Secrets
    C_Secrets = nil
    assert(SecretSentinel.LoadInstrumented("QUI_CDM/cdm/cdm_sources.lua"))("QUI", ns2)
    C_Secrets = savedSecrets
    assert(ns2.CDMSources.AreAurasSecret() == false, "T6: no C_Secrets -> never secret")
    assert(ns2.CDMSources.QueryAuraDuration("player", 1685) == durationToken,
        "T6: wrapper passes through without C_Secrets")
    assert(ns2.CDMSources.QueryUnitAuras("target", "HARMFUL|PLAYER", 40)[1] == auraDataToken,
        "T6: unit aura scan passes through without C_Secrets")
end

---------------------------------------------------------------------------
-- T7: PTR4 fully-secret addedAuras struct. UNIT_AURA now delivers a fully
-- secret payload while auras are secret, so an addedAuras struct's spellId /
-- spellID / name are secret. InvalidateAuraMemoForDelta must NOT compare
-- ad.spellID ~= ad.spellId (a raw ~= on a secret THROWS in-game) -- it must
-- detect the secret via issecretvalue and widen the sweep instead.
--
-- Stock Lua ~= never throws on plain values, so model the in-game throw with
-- secret sentinels whose metatable errors on ==/~= (Lua invokes __eq only when
-- BOTH operands are tables, matching two secret struct fields being compared).
---------------------------------------------------------------------------
do
    aurasSecret = false
    -- Seed the player memo so the delta handler proceeds into the added-aura block
    -- (it returns early when the unit has no memo table).
    assert(S.QueryUnitAuraBySpellID("player", 8080, "HELPFUL") == auraDataToken, "T7: seed player memo")

    -- One shared metatable: Lua 5.1 invokes __eq only when both operands carry
    -- the SAME __eq metamethod, so per-sentinel metatables would never fire (and
    -- the test would pass even against the unguarded code). A shared table models
    -- the in-game "== on a secret throws" for two secret struct fields.
    local SECRET_MT = {
        __eq = function() error("attempt to compare a secret value") end,
        __lt = function() error("attempt to compare a secret value") end,
        __le = function() error("attempt to compare a secret value") end,
    }
    local function makeSecret(token)
        local s = setmetatable({ token = token }, SECRET_MT)
        secretValues[s] = true
        return s
    end

    local secretAdd = {
        spellId = makeSecret("spellId"),
        spellID = makeSecret("mappedSpellID"),
        name    = makeSecret("name"),
    }
    -- Pre-guard, `ad.spellID ~= ad.spellId` compares two secret tables -> __eq
    -- fires -> error. The guard must skip that compare and never throw.
    local ok, err = pcall(S.InvalidateAuraMemoForDelta, "player", { addedAuras = { secretAdd } })
    assert(ok, "T7: fully-secret addedAuras struct must not throw (guard the ~= compare): " .. tostring(err))
end

---------------------------------------------------------------------------
-- T8: Wave 2 H2. `updateInfo` itself (not just fields inside it) can arrive
-- whole-secret. Pre-guard, `updateInfo.isFullUpdate` is a field READ on the
-- secret table -- Lua's __index metamethod fires unconditionally on any key,
-- so a throwing sentinel proves the crash (unlike ==/~=, which only traps
-- sentinel-vs-sentinel -- see tests/helpers/secret_sentinel.lua CAVEAT 1). A
-- nil-shaped delta must WIPE the memo (not silently skip it), exactly like a
-- literal nil updateInfo already does.
---------------------------------------------------------------------------
do
    aurasSecret = false
    local before = calls.bySpell
    -- Prime the player memo so InvalidateAuraMemoForDelta proceeds past its
    -- early "no memo table for this unit" return.
    assert(S.QueryUnitAuraBySpellID("player", 9090) == auraDataToken, "T8: seed player memo")
    assert(calls.bySpell == before + 1, "T8: seed call reached the C function once")

    local secretUpdateInfo = setmetatable({}, {
        __index = function() error("attempt to use a secret value") end,
        __newindex = function() error("attempt to use a secret value") end,
    })
    secretValues[secretUpdateInfo] = true

    local ok, err = pcall(S.InvalidateAuraMemoForDelta, "player", secretUpdateInfo)
    assert(ok, "T8: whole-secret updateInfo must not throw (probe before any field read): " .. tostring(err))

    -- A delta we couldn't read must mean "wipe", not "skip": the seeded
    -- entry must be gone, forcing a fresh C call on the next query.
    S.QueryUnitAuraBySpellID("player", 9090)
    assert(calls.bySpell == before + 2, "T8: whole-secret updateInfo must wipe the memo like a literal nil delta (got "
        .. (calls.bySpell - before) .. " calls)")
end

print("cdm_sources_secret_aura_gate_test: OK")
