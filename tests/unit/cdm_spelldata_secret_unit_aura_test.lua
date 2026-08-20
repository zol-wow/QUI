-- tests/unit/cdm_spelldata_secret_unit_aura_test.lua
-- Run: lua tests/unit/cdm_spelldata_secret_unit_aura_test.lua
--
-- Wave 2 H2: auraCaptureFrame (QUI_CDM/cdm/cdm_spelldata.lua) registers ONE
-- frame for THREE units (player/pet/target) via a single RegisterUnitEvent.
-- Under 12.1 (68569) aura restriction, the UNIT_AURA payload's own `unit`
-- arg -- not just fields inside updateInfo -- can arrive as an opaque
-- SecretValue. On a secret unit the handler cannot tell which of the three
-- changed, so it must invalidate/rescan all three instead of guessing (or
-- worse, comparing/indexing with the secret unit). updateInfo can
-- independently arrive whole-secret even when unit is readable.
--
-- Uses tests/helpers/secret_sentinel.lua's throwing metatable so a regressed
-- guard actually crashes this test (a plain-table pseudo-secret would assert
-- nothing -- see that file's own header note on this exact failure mode).
-- InstallSecretStub is called BEFORE loading the module under test per that
-- file's load-order note.

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIsSecretValue = SecretSentinel.InstallSecretStub()

-- Probe spy for T6: records every value passed to issecretvalue. Truthiness
-- of a sentinel table is untrappable headlessly (fixture CAVEAT), so T6's
-- RED signal is probe ABSENCE, not a throw. Wrapped BEFORE the module load
-- below so any load-time latch of issecretvalue sees the spy.
local probedValues = setmetatable({}, { __mode = "k" })
do
    local realProbe = _G.issecretvalue
    _G.issecretvalue = function(v)
        if v ~= nil then probedValues[v] = true end
        return realProbe(v)
    end
end

local function noop() end
local now = 1
function InCombatLockdown() return false end
function GetTime() return now end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local frames = {}
function CreateFrame()
    local frame = {
        events = {},
        unitEvents = {},
        script = nil,
    }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, ...) self.unitEvents[event] = { ... } end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {}; self.unitEvents = {} end
    function frame:SetScript(script, handler) if script == "OnEvent" then self.script = handler end end
    frames[#frames + 1] = frame
    return frame
end

C_Timer = { After = function(_, callback) callback() end }

-- Benign (non-throwing) unlike cdm_spelldata_aura_boundary_test.lua's
-- deliberately-erroring stub -- that file uses the error to prove OTHER
-- events never force a rescan; this file's whole point is to reach
-- RescanCapturedAurasForUnit (the isFullUpdate / secret-unit fallback path)
-- and observe it complete without throwing.
local forEachAuraCalls = 0
AuraUtil = {
    ForEachAura = function() forEachAuraCalls = forEachAuraCalls + 1 end,
}

local invalidateCalls = {}
local refreshCalls = {}
local ns = {
    Helpers = {
        IsSecretValue = function(v) return issecretvalue and issecretvalue(v) or false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
        InvalidateAuraMemoForDelta = function(unit, updateInfo)
            invalidateCalls[#invalidateCalls + 1] = unit
        end,
    },
    CDMIcons = {
        HandleRuntimeRefresh = function(_, unit, updateInfo)
            refreshCalls[#refreshCalls + 1] = unit
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local auraFrame
for _, frame in ipairs(frames) do
    if frame.unitEvents.UNIT_AURA then
        auraFrame = frame
        break
    end
end
assert(auraFrame, "aura capture frame should register UNIT_AURA")

---------------------------------------------------------------------------
-- T1: unit arrives whole-secret (updateInfo secret too, paired) -- the
-- handler must not compare/index the secret unit, must never read the
-- secret updateInfo (it should short-circuit on the unit check before even
-- looking at updateInfo), and must invalidate all three registered units.
---------------------------------------------------------------------------
local secretUnit = SecretSentinel.MakeSecretSentinel()
local secretUpdateInfo = SecretSentinel.MakeSecretSentinel()

local ok, err = pcall(function()
    auraFrame.script(auraFrame, "UNIT_AURA", secretUnit, secretUpdateInfo)
end)
assert(ok, "T1: secret unit + secret updateInfo dispatch must not throw: " .. tostring(err))

local seen = {}
for _, u in ipairs(invalidateCalls) do
    seen[u] = (seen[u] or 0) + 1
end
assert(next(seen) == nil,
    "T1: secret unit must not call the removed aura memo invalidation bridge")

local rseen = {}
for _, u in ipairs(refreshCalls) do
    rseen[u] = (rseen[u] or 0) + 1
end
assert(rseen.player == 1 and rseen.pet == 1 and rseen.target == 1,
    "T1: secret unit must notify aura consumers for all three registered units")

---------------------------------------------------------------------------
-- T2: unit is readable ("player") but updateInfo itself arrives
-- whole-secret. Pre-fix this throws on `updateInfo.isFullUpdate` field
-- access; the fix must probe and fold to the nil / full-rescan path.
---------------------------------------------------------------------------
invalidateCalls, refreshCalls = {}, {}
local ok2, err2 = pcall(function()
    auraFrame.script(auraFrame, "UNIT_AURA", "player", SecretSentinel.MakeSecretSentinel())
end)
assert(ok2, "T2: whole-secret updateInfo on a readable unit must not throw: " .. tostring(err2))
assert(#invalidateCalls == 0,
    "T2: readable unit must not call the removed aura memo invalidation bridge")
assert(#refreshCalls == 1 and refreshCalls[1] == "player",
    "T2: consumers notified once for the readable unit")

---------------------------------------------------------------------------
-- T3: control -- a normal, fully-readable UNIT_AURA payload still works
-- (guards must not misfire on the non-secret path).
---------------------------------------------------------------------------
invalidateCalls, refreshCalls = {}, {}
local ok3, err3 = pcall(function()
    auraFrame.script(auraFrame, "UNIT_AURA", "target", { isFullUpdate = true })
end)
assert(ok3, "T3: plain payload must still dispatch cleanly: " .. tostring(err3))
assert(#invalidateCalls == 0, "T3: plain payload must not call the removed aura memo bridge")
assert(#refreshCalls == 1 and refreshCalls[1] == "target", "T3: plain payload notifies only its own unit")

---------------------------------------------------------------------------
-- T4: UNIT_SPELLCAST_SUCCEEDED (Wave 2b task2b-A) -- this same auraFrame
-- also registers UNIT_SPELLCAST_SUCCEEDED("player") only. A secret
-- unit token must not gate RecordPlayerCast (registered-token discipline:
-- the registration itself already guarantees identity). Pre-fix, `unit ==
-- "player"` against a REAL secret throws on a live client; this harness's
-- table sentinel can only cross-type-false (CAVEAT 1), so headlessly the
-- observable regression is a silently DROPPED cast rather than a crash.
-- Assert on the cast-correlation side effect, not on pcall success.
---------------------------------------------------------------------------
invalidateCalls, refreshCalls = {}, {}
local ok4, err4 = pcall(function()
    auraFrame.script(auraFrame, "UNIT_SPELLCAST_SUCCEEDED", SecretSentinel.MakeSecretSentinel(), "guid-4", 90101)
    auraFrame.script(auraFrame, "UNIT_AURA", "player", {
        addedAuras = {
            { auraInstanceID = 9401, spellId = 8401, name = "Secret Cast Correlated Aura", isHelpful = true },
        },
    })
end)
assert(ok4, "T4: secret-unit UNIT_SPELLCAST_SUCCEEDED dispatch must not throw: " .. tostring(err4))
local captured4 = ns.CDMSpellData.GetCapturedAuraForLookup({ 90101 }, nil, { "player" }, false)
assert(captured4 and captured4.auraInstanceID == 9401,
    "T4: a secret unit token on the player-only-registered frame must still record the cast for correlation")

---------------------------------------------------------------------------
-- T5: a secret spellID on an otherwise-readable cast must NOT be recorded
-- (RecordPlayerCast's IsUsableSpellIDKey gate, :456). Proven behaviorally,
-- not just by no-throw: FindCorrelatedCast correlates the next aura to the
-- LAST recorded cast (_recentCasts[#_recentCasts]), so a plain cast (90201)
-- is recorded first, then the secret-spellID cast fires. If the secret cast
-- were recorded it would displace 90201 as the correlation candidate and
-- the following aura's cast-key would be the (unkeyable) sentinel instead
-- of 90201 -- the lookup by 90201 below then fails. Verified RED against a
-- mutated copy with the RecordPlayerCast gate deleted.
--
-- CAVEAT (mirrors tests/helpers/secret_sentinel.lua's own caveat style):
-- the sentinel is a table, so IsUsableSpellIDKey's leading
-- `type(spellID) == "number"` check rejects it BEFORE the issecretvalue
-- probe inside IsUsableTableKey is ever consulted -- this test exercises
-- the type() filter, not the probe. Real in-game secret spellIDs keep
-- type() == "number" and are caught only by the probe; stock Lua 5.1
-- cannot emulate a number that issecretvalue flags, so that layer is
-- untestable headlessly. The probe's correctness rests on code review
-- plus the in-game pass, not on this assertion.
---------------------------------------------------------------------------
local ok5, err5 = pcall(function()
    auraFrame.script(auraFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-5a", 90201)
    auraFrame.script(auraFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-5b", SecretSentinel.MakeSecretSentinel())
    auraFrame.script(auraFrame, "UNIT_AURA", "player", {
        addedAuras = {
            { auraInstanceID = 9501, spellId = 8501, name = "Post Secret Cast Aura", isHelpful = true },
        },
    })
end)
assert(ok5, "T5: secret spellID on a readable unit must not throw: " .. tostring(err5))
local captured5 = ns.CDMSpellData.GetCapturedAuraForLookup({ 90201 }, nil, { "player" }, false)
assert(captured5 and captured5.auraInstanceID == 9501,
    "T5: the secret-spellID cast must NOT be recorded -- it must not displace the plain cast (90201) as the correlation candidate")

---------------------------------------------------------------------------
-- T6: 12.1 per-field secrecy -- unit readable, updateInfo a READABLE plain
-- table whose scalar isFullUpdate field is itself a secret boolean (live
-- shape: { addedAuras=<secret table>, isFullUpdate=<secret boolean> }, seen
-- on pet/target). In-game the boolean test THROWS ("attempt to perform
-- boolean test on field 'isFullUpdate'", cdm_spelldata.lua:736 pre-fix);
-- headlessly the sentinel's truthiness can't be trapped, so pin BOTH:
--   * behavior: folds to the full-rescan path for exactly its own unit;
--   * probe discipline: the isFullUpdate value passed through issecretvalue
--     BEFORE any boolean test (probedValues spy at the top of this file).
---------------------------------------------------------------------------
invalidateCalls, refreshCalls = {}, {}
local secretFull6 = SecretSentinel.MakeSecretSentinel()
local ok6, err6 = pcall(function()
    auraFrame.script(auraFrame, "UNIT_AURA", "pet", {
        isFullUpdate = secretFull6,
        addedAuras = SecretSentinel.MakeSecretSentinel(),
    })
end)
assert(ok6, "T6: per-field secret isFullUpdate must not throw: " .. tostring(err6))
assert(#invalidateCalls == 0,
    "T6: per-field secret isFullUpdate must not call the removed aura memo bridge")
assert(#refreshCalls == 1 and refreshCalls[1] == "pet",
    "T6: per-field secret isFullUpdate notifies consumers once for its own unit")
assert(probedValues[secretFull6] == true,
    "T6: isFullUpdate must be probed via issecretvalue before any boolean test")

_G.issecretvalue = restoreIsSecretValue

print("OK: cdm_spelldata_secret_unit_aura_test")
