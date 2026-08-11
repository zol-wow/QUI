-- tests/unit/actiontracker_spellcast_secret_boundary_test.lua
-- Run: lua5.1 tests/unit/actiontracker_spellcast_secret_boundary_test.lua
--
-- Wave 2b Task B: modules/qol/actiontracker.lua registered
-- UNIT_SPELLCAST_SUCCEEDED globally (RegisterEvent, not RegisterUnitEvent)
-- while every OTHER UNIT_SPELLCAST_* event on the same frame was already
-- RegisterUnitEvent(..., "player"). The shared OnEvent code immediately
-- gated `local unit, castGUID, spellID = ...  if unit ~= "player" then
-- return end` before dispatching ANY of the six spellcast branches --
-- i.e. player-only in effect for the whole shared block (quoted evidence
-- in the report). Fix: RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",
-- "player") to match its siblings, drop the now-redundant unit compare,
-- and add a single spellID secret probe (one choke point ahead of every
-- branch) -- PTR 68569's SecretWhenUnitSpellCastRestricted covers the
-- whole payload (spellID/castGUID/unit) regardless of the fact delivery
-- is already unit-scoped to "player".
--
-- This test pins three things against the real OnEvent handler:
--   1. A secret spellID is skipped -- no throw, and the downstream
--      spellID-touching call (C_Spell.GetSpellInfo, reached only via
--      AddSpellToHistory -> GetSpellNameAndIcon) never fires.
--   2. A secret UNIT token no longer matters -- the dropped compare means
--      a secret/garbage unit does not block a legitimate cast (proves the
--      payload unit arg is genuinely unused, not just unreached).
--   3. A normal numeric spellID still reaches that same downstream call
--      (no behavior regression on the common case).
-- It also pins the registration call itself: eventFrame must receive
-- RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player"), never a bare
-- RegisterEvent("UNIT_SPELLCAST_SUCCEEDED").
--
-- Caveat (numeric secrets are headlessly untestable, honestly): a REAL
-- WoW secret spellID is an opaque engine value that throws on table-index
-- and numeric compare. This harness's throwing sentinel (secret_sentinel.lua)
-- stands in for that and pins the "probe before touch" discipline / call
-- ordering, but cannot reproduce the engine's actual throw-on-index
-- semantics for a real secret number -- there is no way to fabricate that
-- outside the client. What IS verified here: with the probe removed (or
-- reordered), this test's negative assertions (spy count / no-throw) would
-- catch a regression; the mutation check below exercises that.

local function noop() end

local createdFrames = {}
local regCalls = {}

local function newFrame()
    local frame = { scripts = {}, shown = false }
    local methods = {}
    function methods:SetScript(script, handler) self.scripts[script] = handler end
    function methods:GetScript(script) return self.scripts[script] end
    function methods:RegisterEvent(event)
        regCalls[#regCalls + 1] = { kind = "RegisterEvent", event = event }
    end
    function methods:RegisterUnitEvent(event, unit)
        regCalls[#regCalls + 1] = { kind = "RegisterUnitEvent", event = event, unit = unit }
    end
    function methods:UnregisterEvent() end
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:IsShown() return self.shown end
    function methods:CreateTexture() return newFrame() end
    function methods:CreateFontString() return newFrame() end
    return setmetatable(frame, { __index = function(_, k) return methods[k] or noop end })
end

function CreateFrame(...)
    local f = newFrame()
    createdFrames[#createdFrames + 1] = f
    return f
end

UIParent = newFrame()
local now = 1000
GetTime = function() return now end
InCombatLockdown = function() return false end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetActionInfo = function() return nil end
GetMacroSpell = function() return nil end

local getSpellInfoCalls = 0
local lastQueriedSpellID
C_Spell = {
    GetSpellInfo = function(spellID)
        getSpellInfoCalls = getSpellInfoCalls + 1
        lastQueriedSpellID = spellID
        return { name = "Test Spell", iconID = 135812 }
    end,
}
C_Item = {}

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIssecretvalue = SecretSentinel.InstallSecretStub()

local generalDB = {
    actionTracker = {
        enabled = true,
        onlyInCombat = false, -- let a non-combat test cast actually record
    },
}

local ns = {
    QUI = {},
    Addon = {},
    L = setmetatable({}, { __index = function(_, k) return k end }),
    Helpers = {
        CreateStateTable = function() return {} end,
        Clamp = function(v, lo, hi)
            if type(v) ~= "number" then v = lo or 0 end
            if lo and v < lo then v = lo end
            if hi and v > hi then v = hi end
            return v
        end,
        GetModuleDB = function(name)
            if name == "general" then return generalDB end
            return nil
        end,
        EnsureDefaults = function(tbl, defaults)
            for k, v in pairs(defaults) do
                if tbl[k] == nil then tbl[k] = v end
            end
        end,
        IsSecretValue = function(value)
            return issecretvalue and issecretvalue(value) or false
        end,
        GetSkinBorderColor = function() return nil, nil, nil, nil end,
    },
    UIKit = {},
}

-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("modules/qol/actiontracker.lua"))("QUI", ns)

assert(#createdFrames >= 1, "actiontracker.lua should create at least one top-level event frame at load")
local eventFrame = createdFrames[1]
local onEvent = eventFrame:GetScript("OnEvent")
assert(type(onEvent) == "function", "actiontracker event frame should have an OnEvent handler")

----------------------------------------------------------------------------
-- Registration proof: UNIT_SPELLCAST_SUCCEEDED must be RegisterUnitEvent'd
-- to "player", exactly like its five UNIT_SPELLCAST_* siblings, never a
-- bare RegisterEvent.
----------------------------------------------------------------------------
local succeededReg
for _, call in ipairs(regCalls) do
    if call.event == "UNIT_SPELLCAST_SUCCEEDED" then
        assert(not succeededReg, "UNIT_SPELLCAST_SUCCEEDED must be registered exactly once")
        succeededReg = call
    end
end
assert(succeededReg, "UNIT_SPELLCAST_SUCCEEDED must be registered")
assert(succeededReg.kind == "RegisterUnitEvent",
    "UNIT_SPELLCAST_SUCCEEDED must use RegisterUnitEvent, not a global RegisterEvent")
assert(succeededReg.unit == "player",
    "UNIT_SPELLCAST_SUCCEEDED must be scoped to the player unit")

----------------------------------------------------------------------------
-- Enable the tracker (mirrors the login path: ns.WhenLoggedIn is nil in
-- this bare harness, so drive it explicitly via the exposed refresh hook).
----------------------------------------------------------------------------
assert(type(_G.QUI_RefreshActionTracker) == "function", "RefreshActionTracker must be exported")
_G.QUI_RefreshActionTracker()

----------------------------------------------------------------------------
-- Case 1: secret spellID -- must be skipped silently (no throw), and the
-- downstream C_Spell.GetSpellInfo spy must never fire.
----------------------------------------------------------------------------
local secretSpellID = SecretSentinel.MakeSecretSentinel()
local before = getSpellInfoCalls
local ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-secret", secretSpellID)
assert(ok, "OnEvent must not throw on a secret spellID: " .. tostring(err))
assert(getSpellInfoCalls == before,
    "a secret spellID must never reach GetSpellNameAndIcon/C_Spell.GetSpellInfo")

----------------------------------------------------------------------------
-- Case 2: secret UNIT token, normal numeric spellID -- the unit compare
-- was dropped, so this must NOT be treated any differently than a normal
-- "player" unit. Seed the action-bar cache so ResolveCastToSucceeded's
-- fallback path (IsActionBarSpell) actually reaches AddSpellToHistory.
----------------------------------------------------------------------------
GetActionInfo = function(slot)
    if slot == 1 then return "spell", 9101 end
    return nil
end
_G.QUI_RefreshActionTracker() -- rebuild the action-bar spell cache with the stub above

local secretUnit = SecretSentinel.MakeSecretSentinel()
before = getSpellInfoCalls
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", secretUnit, "guid-1", 9101)
assert(ok, "OnEvent must not throw on a secret unit token: " .. tostring(err))
assert(getSpellInfoCalls == before + 1,
    "a normal spellID must still reach GetSpellNameAndIcon even when the payload unit is secret/garbage " ..
    "(registration is already player-scoped; the payload unit arg is unused)")
assert(lastQueriedSpellID == 9101, "the numeric spellID must reach GetSpellNameAndIcon unmodified")

----------------------------------------------------------------------------
-- Case 3: plain regression check -- normal unit, normal spellID.
----------------------------------------------------------------------------
before = getSpellInfoCalls
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-2", 9101)
assert(ok, "OnEvent must not throw on the common case: " .. tostring(err))
assert(getSpellInfoCalls == before + 1, "the common-case cast must still be tracked")

----------------------------------------------------------------------------
-- Case 4: secret castGUID, normal numeric spellID -- castGUID is also
-- secretizable (UnitDocumentation.lua:4671, no NeverSecret) and every
-- spellcast branch indexes state.castByGUID/state.sentByGUID with it, so
-- the shared probe must skip the whole event.
--
-- Caveat (honest): a REAL secret castGUID throws when used as a table key;
-- the sentinel does NOT (plain-table key mechanics -- secret_sentinel.lua's
-- self-test pins that), so this case cannot assert a throw. It asserts
-- BEHAVIOR instead: with the probe covering castGUID the downstream
-- C_Spell.GetSpellInfo spy stays silent; with the probe mutated back to
-- spellID-only the cast falls through IsActionBarSpell(9101) into
-- AddSpellToHistory and the spy fires -- mutation-verified.
----------------------------------------------------------------------------
local secretCastGUID = SecretSentinel.MakeSecretSentinel()
before = getSpellInfoCalls
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", secretCastGUID, 9101)
assert(ok, "OnEvent must not throw on a secret castGUID: " .. tostring(err))
assert(getSpellInfoCalls == before,
    "a secret castGUID must skip the event entirely (castByGUID/sentByGUID are indexed with it in every branch)")

-- Tracker still works normally right after the skipped secret-GUID cast.
before = getSpellInfoCalls
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-3", 9101)
assert(ok, "OnEvent must not throw after a secret-castGUID skip: " .. tostring(err))
assert(getSpellInfoCalls == before + 1, "a normal cast right after a secret-castGUID skip must still be tracked")

----------------------------------------------------------------------------
-- Case 5: whole-secret UNIT_SPELLCAST_SENT payload (SENT is
-- SecretWhenUnitSpellCastRestricted too, UnitDocumentation.lua:4621-4632)
-- -- must not throw and must not register a phantom sent-cast.
--
-- Caveat (honest): this case is NOT mutation-catchable headlessly. A real
-- secret castGUID leaks its underlying type ("string") through type(), so
-- in-game it would pass ExtractCastGUIDAndSpellID's type checks and reach
-- MarkSentCast's sentByGUID index; the table sentinel instead reports
-- type "table" and is filtered by the PRE-EXISTING type check either way.
-- The explicit IsSecretValue probe added in ExtractCastGUIDAndSpellID is
-- therefore pinned only by no-throw here, not by behavior divergence.
----------------------------------------------------------------------------
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SENT", "player", "target-name",
    SecretSentinel.MakeSecretSentinel(), SecretSentinel.MakeSecretSentinel())
assert(ok, "OnEvent must not throw on a whole-secret UNIT_SPELLCAST_SENT payload: " .. tostring(err))

-- A spell that is neither sent-registered nor on the action bar must not be
-- tracked -- proves the secret SENT above did not seed sentBySpell/sentByGUID.
before = getSpellInfoCalls
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-4", 7777)
assert(ok, "OnEvent must not throw on an untracked cast: " .. tostring(err))
assert(getSpellInfoCalls == before,
    "a secret SENT payload must not register a phantom sent-cast for later SUCCEEDED resolution")

_G.issecretvalue = restoreIssecretvalue

print("OK: actiontracker_spellcast_secret_boundary_test")
