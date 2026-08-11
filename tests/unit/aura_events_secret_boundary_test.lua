-- tests/unit/aura_events_secret_boundary_test.lua
-- Wave 2 Task 2: UNIT_AURA secret boundary (R1-R4).
--
-- 12.1 PTR 68569: the whole UNIT_AURA payload (unit AND/OR updateInfo) can be
-- a secret value while auras are restricted. core/aura_events.lua is the
-- single router for all 45 roster frames + 1 non-roster catch-all; if it
-- ever touches a secret field/arg directly it throws (roster path) or lets a
-- secret unit token leak to subscribers (catch-all path). Fixes:
--   R1 - roster frames get a per-unit closure; the payload `unit` arg is
--        NEVER read (the registered token is the only trusted identity).
--   R2 - non-roster catch-all probes `issecretvalue(unit)` FIRST, before any
--        other check, and drops silently.
--   R3 - QueueAuraEvent probes `issecretvalue(updateInfo)` before ANY field
--        access (before the pre-existing `updateInfo.isFullUpdate`/
--        PayloadIsSecret checks, which only cover the pre-68569 shape where
--        updateInfo itself is a real table but its delta ARRAYS are secret).
--   R4 - asserted by this test only (no code change): case (a) is the
--        assertion that secrets can no longer be stored as `pendingUnits`
--        VALUES (they still may be used as pendingUnits KEYS pre-fix, see
--        case (d) below -- table keying never throws, see fixture header).
--
-- Run: lua5.1 tests/unit/aura_events_secret_boundary_test.lua
--
-- ---------------------------------------------------------------------------
-- Fixture-doc corrections applied here (tests/helpers/secret_sentinel.lua
-- header -- READ THAT FILE FIRST, it overrides two brief assumptions):
--
-- (1) LOAD ORDER: core/aura_events.lua:28 does
--       local issecretvalue = issecretvalue
--     at module-load time. SecretSentinel.InstallSecretStub() MUST run
--     BEFORE loadfile()-ing the module below, or the module's file-local
--     upvalue latches a permanent nil and never sees the stub.
--
-- (2) TABLE-KEY THROWS DON'T EXIST: `pendingUnits[sentinel] = x` is plain
--     table mechanics (reference keying), not an operation ON the sentinel --
--     no metamethod fires, so it never throws. Only case (a) throws
--     pre-fix, via `updateInfo.isFullUpdate` (a real __index access on the
--     secret). Cases (b) and (d) are asserted purely on BEHAVIOR:
--       (b) dropped (no dispatch, no pendingUnits entry) vs queued/misrouted
--       (d) the CORRECT closure-owned unit token ("party1") is what gets
--           dispatched, not whatever token the payload happened to carry.
--     This file verified empirically (see task-2-report.md) that the
--     pre-existing `issecretvalue(ttUnit)` guard inside
--     IsNonRosterEventInteresting already makes (b) NOT reachable via the
--     tooltip branch either before or after R2 -- so (b)'s RED signal here
--     is instead "IsNonRosterEventInteresting (and InCombatLockdown) gets
--     invoked at all for a secret unit", which R2's early-return eliminates.
--     See the report for the full empirical trace; this is not an
--     overclaim -- CAVEAT 1 in the fixture header explicitly says this
--     fixture cannot catch the "secret == 'string'" misroute shape and warns
--     against claiming otherwise.
-- ---------------------------------------------------------------------------

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")

local fails = 0
local function check(name, ok)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name) end
end

-- MUST run before loadfile(core/aura_events.lua) -- see correction (1) above.
local restoreSecretStub = SecretSentinel.InstallSecretStub()

-- Probe spy: records every value the module passes to issecretvalue. The
-- fixture CANNOT trap a truthiness test on a sentinel (plain-table truthiness
-- never fires a metamethod -- fixture header CAVEAT), so case (g)'s RED
-- signal is probe ABSENCE: pre-fix, `updateInfo.isFullUpdate` was
-- boolean-tested (throws in-game on a per-field secret) without ever being
-- probed. Must wrap BEFORE loadfile for the same upvalue-latch reason as the
-- stub itself.
local probedValues = setmetatable({}, { __mode = "k" })
do
    local realProbe = _G.issecretvalue
    _G.issecretvalue = function(v)
        if v ~= nil then probedValues[v] = true end
        return realProbe(v)
    end
end

-- Controllable WoW-shaped environment -----------------------------------------
local env = { inCombat = false, tooltipShown = false, tooltipUnit = nil, secretAuras = false }

-- Task 3: C_Secrets.ShouldAurasBeSecret() gate for the restriction-lift
-- notifier. Controlled via env.secretAuras.
_G.C_Secrets = {
    ShouldAurasBeSecret = function() return env.secretAuras end,
}

local InCombatLockdownCalls = 0
function InCombatLockdown()
    InCombatLockdownCalls = InCombatLockdownCalls + 1
    return env.inCombat
end

function wipe(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

GameTooltip = {
    IsShown = function() return env.tooltipShown end,
    GetUnit = function() return env.tooltipUnit and "SomeName" or nil, env.tooltipUnit end,
}

local function noop() end
local createdFrames = {}
function CreateFrame()
    local f = {
        _onEvent = nil,
        _onUpdate = nil,
        _registeredGlobal = false,
        _registeredUnit = nil,
        _registeredEvents = {}, -- [event] = true, any RegisterEvent (Task 3: ADDON_RESTRICTION_STATE_CHANGED)
        RegisterEvent = function(self, event)
            if event == "UNIT_AURA" then self._registeredGlobal = true end
            self._registeredEvents[event] = true
        end,
        RegisterUnitEvent = function(self, event, unit)
            if event == "UNIT_AURA" then self._registeredUnit = unit end
        end,
        Show = noop,
        Hide = noop,
        SetScript = function(self, script, handler)
            if script == "OnEvent" then self._onEvent = handler
            elseif script == "OnUpdate" then self._onUpdate = handler end
        end,
    }
    createdFrames[#createdFrames + 1] = f
    return f
end

-- Load the live dispatcher with a fresh namespace ------------------------------
local ns = {}
-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("core/aura_events.lua"))("QUI", ns)
local AuraEvents = ns.AuraEvents
assert(AuraEvents, "core/aura_events.lua must publish ns.AuraEvents")

-- Locate every per-unit roster frame (keyed by the token it registered for),
-- the global non-roster catch-all frame, and the coalescing frame.
local rosterHandlers = {}
local eventFrame, coalesceFrame
for _, f in ipairs(createdFrames) do
    if f._registeredUnit and f._onEvent then rosterHandlers[f._registeredUnit] = f._onEvent end
    if f._registeredGlobal and f._onEvent then eventFrame = f end
    if f._onUpdate then coalesceFrame = f end
end
assert(rosterHandlers["player"], "could not find the player roster frame's OnEvent handler")
assert(rosterHandlers["party1"], "could not find the party1 roster frame's OnEvent handler")
assert(eventFrame, "could not find the global UNIT_AURA router frame")
assert(coalesceFrame, "could not find the coalescing frame")

-- Task 3: the restriction-lift notifier frame, identified by the event it
-- registered (ADDON_RESTRICTION_STATE_CHANGED -- see the RESTRICTION LIFT
-- section in core/aura_events.lua and the Step 1 research quotes in the
-- task-3 report for why this event, alone, is the chosen signal).
local liftFrame
for _, f in ipairs(createdFrames) do
    if f._registeredEvents["ADDON_RESTRICTION_STATE_CHANGED"] and f._onEvent then
        liftFrame = f
    end
end
assert(liftFrame, "could not find the restriction-lift notifier frame (ADDON_RESTRICTION_STATE_CHANGED)")

local function rosterHandler_for(unit) return rosterHandlers[unit] end
local function nonRosterHandler(...) return eventFrame._onEvent(...) end
local function drain() coalesceFrame._onUpdate(coalesceFrame) end

-- Recorder: subscribe on every filter tier so misrouted dispatches (wrong
-- tier, wrong unit token) are visible too, not just "all".
local recorded -- list of { tier = ..., unit = ..., info = ... }
local function resetRecorder() recorded = {} end
local function record(tier)
    return function(unit, info)
        recorded[#recorded + 1] = { tier = tier, unit = unit, info = info }
    end
end
AuraEvents:Subscribe("all", record("all"))
AuraEvents:Subscribe("roster", record("roster"))
AuraEvents:Subscribe("player", record("player"))
AuraEvents:Subscribe("group", record("group"))

local function dispatchedTo(tier, unit)
    for _, r in ipairs(recorded) do
        if r.tier == tier and r.unit == unit then return r end
    end
    return nil
end

---------------------------------------------------------------------------
-- (a) secret updateInfo -> sentinel promotion, no throw.
-- Registered token "player"; payload unit arg is ALSO a (different) secret,
-- pinning that R1's per-frame closure never reads it either.
---------------------------------------------------------------------------
resetRecorder()
env.inCombat, env.tooltipShown, env.tooltipUnit = false, false, nil
local payloadSecretUnit_a = SecretSentinel.MakeSecretSentinel()
local secretUpdateInfo_a = SecretSentinel.MakeSecretSentinel()
local frame_player = { _isFrame = true }
local ok_a, err_a = pcall(rosterHandler_for("player"), frame_player, "UNIT_AURA", payloadSecretUnit_a, secretUpdateInfo_a)
check("(a) roster handler does not throw on a secret updateInfo", ok_a)
if not ok_a then print("      error was: " .. tostring(err_a)) end
if ok_a then
    drain()
    local r = dispatchedTo("player", "player")
    check("(a) subscriber receives ('player', nil) -- promoted to full update, no secret leaked",
        r ~= nil and r.info == nil)
end

---------------------------------------------------------------------------
-- (b) non-roster OnEvent with a secret unit -> dropped, no throw, no
-- dispatch under any subscriber tier.
---------------------------------------------------------------------------
resetRecorder()
env.inCombat, env.tooltipShown, env.tooltipUnit = false, false, nil
local preCallCount_b = InCombatLockdownCalls
local secretUnit_b = SecretSentinel.MakeSecretSentinel()
local frame_catchall = { _isFrame = true }
local ok_b, err_b = pcall(nonRosterHandler, frame_catchall, "UNIT_AURA", secretUnit_b, {})
check("(b) non-roster catch-all does not throw on a secret unit", ok_b)
if not ok_b then print("      error was: " .. tostring(err_b)) end
drain()
check("(b) no dispatch to ANY subscriber tier for a secret non-roster unit",
    #recorded == 0)
-- Distinguishes R2 (probe-and-return-FIRST) from "happens to drop anyway":
-- pre-fix, IsNonRosterEventInteresting (and therefore InCombatLockdown) is
-- unconditionally invoked for every non-roster unit that isn't a roster key,
-- secret or not -- an empirical run against pre-fix code confirms the
-- "dropped, no throw" outcome above ALREADY holds even without R2 (a
-- pre-existing `issecretvalue(ttUnit)` guard inside IsNonRosterEventInteresting
-- protects the one branch that could otherwise compare a secret unit token
-- as equal to the tooltip's unit). This is the real RED/GREEN signal for
-- (b): R2's `issecretvalue(unit)` early-return must skip the interest
-- predicate (and its InCombatLockdown call) ENTIRELY for a secret unit,
-- rather than reaching it and merely surviving it. See file header
-- correction (2) and task-2-report.md for the full empirical trace.
local calledInterestPredicate_b = InCombatLockdownCalls > preCallCount_b
check("(b) R2 short-circuits on issecretvalue(unit) BEFORE invoking IsNonRosterEventInteresting "
    .. "(no InCombatLockdown call for a secret unit)", not calledInterestPredicate_b)

---------------------------------------------------------------------------
-- (c) REGRESSION PIN -- plain-table updateInfo with secret inner arrays
-- (pre-68569 shape). Already promoted via the pre-existing PayloadIsSecret
-- check; must keep passing unchanged by R1-R3.
---------------------------------------------------------------------------
resetRecorder()
local frame_player2 = { _isFrame = true }
rosterHandler_for("player")(frame_player2, "UNIT_AURA", "player",
    { addedAuras = SecretSentinel.MakeSecretSentinel() })
drain()
local r_c = dispatchedTo("player", "player")
check("(c) PIN: plain-table updateInfo with secret addedAuras still promotes to ('player', nil)",
    r_c ~= nil and r_c.info == nil)

---------------------------------------------------------------------------
-- (d) roster closure ignores the payload unit arg -- handler registered for
-- "party1" must dispatch ("party1", nil) even when called with a secret
-- (or any bogus) unit argument. Pre-fix (shared OnRosterUnitAura reads the
-- PAYLOAD unit arg) this is a genuine MISROUTE: the secret token itself
-- becomes the pendingUnits key (table keying doesn't throw -- see file
-- header correction (2)) and gets dispatched to "all" subscribers under its
-- own (secret, non-roster-recognized) identity instead of "party1" ever
-- reaching roster/group subscribers.
---------------------------------------------------------------------------
resetRecorder()
local payloadSecretUnit_d = SecretSentinel.MakeSecretSentinel()
local frame_party1 = { _isFrame = true }
rosterHandler_for("party1")(frame_party1, "UNIT_AURA", payloadSecretUnit_d, nil)
drain()
local r_d = dispatchedTo("group", "party1")
check("(d) subscriber receives ('party1', nil) via the closure's OWN registered token",
    r_d ~= nil and r_d.info == nil)
local misroutedUnderSecretToken_d = false
for _, r in ipairs(recorded) do
    if r.unit == payloadSecretUnit_d then misroutedUnderSecretToken_d = true end
end
check("(d) the secret payload unit token itself never appears as a dispatched unit",
    not misroutedUnderSecretToken_d)

---------------------------------------------------------------------------
-- (e) RESTRICTION LIFT, secrecy actually cleared -- ADDON_RESTRICTION_STATE_
-- CHANGED fires with C_Secrets.ShouldAurasBeSecret() now false: every
-- roster unit (all 45) + target must get a full-update sentinel queued, so
-- subscribers receive (unit, nil).
---------------------------------------------------------------------------
resetRecorder()
env.secretAuras = false
local frame_lift_e = { _isFrame = true }
local ok_e, err_e = pcall(liftFrame._onEvent, frame_lift_e, "ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
check("(e) lift handler does not throw when restrictions have lifted", ok_e)
if not ok_e then print("      error was: " .. tostring(err_e)) end
drain()
local r_e_player = dispatchedTo("roster", "player")
check("(e) player receives (player, nil) via the roster tier", r_e_player ~= nil and r_e_player.info == nil)
local r_e_raid40 = dispatchedTo("roster", "raid40")
check("(e) raid40 receives (raid40, nil) via the roster tier", r_e_raid40 ~= nil and r_e_raid40.info == nil)
local r_e_party1 = dispatchedTo("group", "party1")
check("(e) party1 receives (party1, nil) via the group tier", r_e_party1 ~= nil and r_e_party1.info == nil)
local r_e_target = dispatchedTo("all", "target")
check("(e) target receives (target, nil) via the all tier", r_e_target ~= nil and r_e_target.info == nil)
local rosterRecordedCount_e = 0
for _, r in ipairs(recorded) do
    if r.tier == "roster" then rosterRecordedCount_e = rosterRecordedCount_e + 1 end
end
check("(e) all 45 roster units (player + party1-4 + raid1-40) were queued and dispatched",
    rosterRecordedCount_e == 45)

---------------------------------------------------------------------------
-- (f) RESTRICTION STILL ACTIVE -- ADDON_RESTRICTION_STATE_CHANGED fires
-- (e.g. a different restriction type toggled) but
-- C_Secrets.ShouldAurasBeSecret() is still true: nothing should be queued.
-- A later lift event covers the eventual real transition.
---------------------------------------------------------------------------
resetRecorder()
env.secretAuras = true
local frame_lift_f = { _isFrame = true }
local ok_f, err_f = pcall(liftFrame._onEvent, frame_lift_f, "ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
check("(f) lift handler does not throw while still restricted", ok_f)
if not ok_f then print("      error was: " .. tostring(err_f)) end
drain()
check("(f) nothing is queued while ShouldAurasBeSecret() is still true", #recorded == 0)
env.secretAuras = false

---------------------------------------------------------------------------
-- (g) 12.1 PER-FIELD secrecy -- updateInfo is a READABLE plain table whose
-- scalar isFullUpdate field is itself a secret boolean (live shape:
-- updateInfo={ removedAuraInstanceIDs=<secret table>, isFullUpdate=<secret
-- boolean> }, seen 1326x on raid units). In-game, `updateInfo.isFullUpdate`
-- as a boolean test THROWS ("attempt to perform boolean test on field
-- 'isFullUpdate'"). The harness cannot reproduce that throw (truthiness of
-- a sentinel table is trappable by nothing -- fixture CAVEAT), so this case
-- pins BOTH:
--   * behavior: promoted to the full-update sentinel, subscriber gets
--     (unit, nil), no secret leaked;
--   * probe discipline: the isFullUpdate value itself was passed through
--     issecretvalue BEFORE any boolean test (probe-spy above). Pre-fix RED:
--     the branch ordering boolean-tested it first, so the spy never saw it.
---------------------------------------------------------------------------
resetRecorder()
local secretFull_g = SecretSentinel.MakeSecretSentinel()
local secretRemoved_g = SecretSentinel.MakeSecretSentinel()
local frame_player3 = { _isFrame = true }
local ok_g, err_g = pcall(rosterHandler_for("player"), frame_player3, "UNIT_AURA", "player",
    { isFullUpdate = secretFull_g, removedAuraInstanceIDs = secretRemoved_g })
check("(g) roster handler does not throw on per-field secret isFullUpdate", ok_g)
if not ok_g then print("      error was: " .. tostring(err_g)) end
drain()
local r_g = dispatchedTo("player", "player")
check("(g) per-field secret isFullUpdate promotes to ('player', nil)",
    r_g ~= nil and r_g.info == nil)
check("(g) isFullUpdate was probed via issecretvalue before any boolean test",
    probedValues[secretFull_g] == true)

---------------------------------------------------------------------------
-- (h) ELEMENT-level secrecy: a READABLE delta array carrying a SECRET
-- element (UnitAuraUpdateInfo no longer promises non-secret contents).
-- Consumers ==-compare and table-key these elements, so the router must
-- promote to the full-update sentinel instead of passing them through.
---------------------------------------------------------------------------
resetRecorder()
local secretElem_h = SecretSentinel.MakeSecretSentinel()
local ok_h, err_h = pcall(rosterHandler_for("player"), { _isFrame = true }, "UNIT_AURA", "player",
    { isFullUpdate = false, removedAuraInstanceIDs = { 101, secretElem_h, 103 } })
check("(h) roster handler does not throw on a secret array ELEMENT", ok_h)
if not ok_h then print("      error was: " .. tostring(err_h)) end
drain()
local r_h = dispatchedTo("player", "player")
check("(h) secret removed-array element promotes to ('player', nil)",
    r_h ~= nil and r_h.info == nil)
check("(h) the element itself was probed", probedValues[secretElem_h] == true)

---------------------------------------------------------------------------
-- (i) FIELD-level secrecy on a readable added aura: consumers table-key
-- auraInstanceID and look up spellId — a secret identity field promotes.
---------------------------------------------------------------------------
resetRecorder()
local secretSpellId_i = SecretSentinel.MakeSecretSentinel()
local ok_i, err_i = pcall(rosterHandler_for("player"), { _isFrame = true }, "UNIT_AURA", "player",
    { isFullUpdate = false, addedAuras = { { auraInstanceID = 7, spellId = secretSpellId_i } } })
check("(i) roster handler does not throw on a secret added-aura field", ok_i)
if not ok_i then print("      error was: " .. tostring(err_i)) end
drain()
local r_i = dispatchedTo("player", "player")
check("(i) secret added-aura spellId promotes to ('player', nil)",
    r_i ~= nil and r_i.info == nil)

-- Control: a fully readable delta still passes through as a DELTA.
resetRecorder()
local okCtl = pcall(rosterHandler_for("player"), { _isFrame = true }, "UNIT_AURA", "player",
    { isFullUpdate = false, addedAuras = { { auraInstanceID = 8, spellId = 2825 } } })
check("(i) control: readable delta does not throw", okCtl)
drain()
local r_ctl = dispatchedTo("player", "player")
check("(i) control: readable delta passes through as a table",
    r_ctl ~= nil and type(r_ctl.info) == "table"
        and r_ctl.info.addedAuras[1].spellId == 2825)

---------------------------------------------------------------------------
-- (j) PER-SUBSCRIBER isolation: one throwing subscriber must not abort the
-- remaining subscribers for the same unit (errors route to geterrorhandler).
---------------------------------------------------------------------------
local handledErrors = 0
_G.geterrorhandler = function() return function() handledErrors = handledErrors + 1 end end
local laterRan = false
AuraEvents:Subscribe("player", function() error("boom: first subscriber") end)
AuraEvents:Subscribe("player", function() laterRan = true end)
resetRecorder()
local ok_j = pcall(rosterHandler_for("player"), { _isFrame = true }, "UNIT_AURA", "player", nil)
check("(j) dispatch survives a throwing subscriber", ok_j)
local okDrain_j = pcall(drain)
check("(j) coalesce drain does not throw", okDrain_j)
check("(j) the later subscriber still ran", laterRan == true)
check("(j) the throw reached geterrorhandler", handledErrors == 1)

_G.issecretvalue = restoreSecretStub

if fails > 0 then error(fails .. " failure(s) in aura_events_secret_boundary_test") end
print("OK: aura_events_secret_boundary_test (all checks passed)")
