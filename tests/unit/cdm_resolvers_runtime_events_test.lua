-- tests/unit/cdm_resolvers_runtime_events_test.lua
-- Run: lua tests/unit/cdm_resolvers_runtime_events_test.lua
--
-- Wave 2b task2b-A adds UNIT_SPELLCAST_SUCCEEDED coverage: the runtime frame registers
-- _runtimeFrame for that event via RegisterUnitEvent("player") only, so the
-- delivered unit token's identity is already guaranteed server-side even
-- when it arrives as an opaque SecretValue under restriction (68569:
-- UnitDocumentation.lua:4663-4674, SecretWhenUnitSpellCastRestricted). The
-- handler must not gate on that token (registered-token discipline) but
-- must independently probe spellID (arg3) before forwarding it through
-- publish(), the single choke point before CDM:COOLDOWN_CHANGED fans out to
-- every subscriber. Uses tests/helpers/secret_sentinel.lua's throwing
-- metatable; InstallSecretStub is called BEFORE loading the module under
-- test per that file's load-order note (cdm_resolvers.lua captures
-- issecretvalue into a file-local upvalue at load time).

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIsSecretValue = SecretSentinel.InstallSecretStub()

local frames = {}

function geterrorhandler()
    return function(err) error(err, 0) end
end

function InCombatLockdown() return false end

function CreateFrame()
    local frame = {
        events = {},
    }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event)
        self.events[event] = true
    end
    function frame:SetScript(scriptName, handler)
        self[scriptName] = handler
    end
    frames[#frames + 1] = frame
    return frame
end

local published = {}
local ns = {
    Helpers = {},
    CDMShared = {},
    CDMSources = {},
    CDMRuntimeQueries = {
        QueryCharges = function() end,
        QueryCooldown = function() end,
        QueryDuration = function() end,
        QueryGCDDuration = function() end,
        QueryChargeDuration = function() end,
        QueryOverrideSpell = function() end,
        QueryDisplayCount = function() end,
        QuerySpellCount = function() end,
    },
    CDMScheduler = {
        Publish = function(...)
            published[#published + 1] = { ... }
        end,
    },
}

-- Instrumented load (Task 7): cdm_resolvers.lua exists standalone, so the
-- consolidated-chunk helper reduced to a plain load — replaced with the
-- instrumented loader (truthiness/==/# on sentinels now THROW inside it).
assert(SecretSentinel.LoadInstrumented("QUI_CDM/cdm/cdm_resolvers.lua"))("QUI", ns)

local runtimeFrame
for _, frame in ipairs(frames) do
    if frame.events.SPELL_UPDATE_COOLDOWN then
        runtimeFrame = frame
        break
    end
end
assert(runtimeFrame, "resolver runtime frame should be registered")
assert(runtimeFrame.events.SPELL_UPDATE_CHARGES == true,
    "resolver should keep listening to legacy charge events")
assert(runtimeFrame.events.SPELL_UPDATE_USES == true,
    "resolver should listen to Blizzard CooldownViewer charge-use events")

runtimeFrame.OnEvent(runtimeFrame, "SPELL_UPDATE_USES", 55090, 55091)
local event = assert(published[#published], "SPELL_UPDATE_USES should publish a charge change")
assert(event[1] == "CDM:CHARGES_CHANGED",
    "SPELL_UPDATE_USES should publish through the charge-change bus")
assert(event[2] == 55090 and event[3] == 55091,
    "SPELL_UPDATE_USES should preserve spell and base spell payload")

runtimeFrame.OnEvent(runtimeFrame, "SPELL_UPDATE_CHARGES", 55092)
event = assert(published[#published], "SPELL_UPDATE_CHARGES should still publish a charge change")
assert(event[1] == "CDM:CHARGES_CHANGED" and event[2] == 55092,
    "SPELL_UPDATE_CHARGES compatibility should be preserved")

runtimeFrame.OnEvent(runtimeFrame, "SPELL_UPDATE_COOLDOWN", 90010, 90011, 12, 133, 90012)
event = assert(published[#published], "SPELL_UPDATE_COOLDOWN should publish a cooldown change")
assert(event[1] == "CDM:COOLDOWN_CHANGED" and event[2] == 90010 and event[3] == 90011
        and event[4] == "refresh" and event[5] == 12 and event[6] == 133 and event[7] == 90012,
    "SPELL_UPDATE_COOLDOWN should preserve category and start-recovery payloads")

---------------------------------------------------------------------------
-- UNIT_SPELLCAST_SUCCEEDED (Wave 2b task2b-A)
---------------------------------------------------------------------------

-- Control: a normal, fully-readable payload still publishes as before.
runtimeFrame.OnEvent(runtimeFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-1", 90001)
event = assert(published[#published], "plain player cast should publish a cooldown change")
assert(event[1] == "CDM:COOLDOWN_CHANGED" and event[2] == 90001 and event[4] == "cast_succeeded",
    "plain player cast should forward spellID tagged cast_succeeded")

-- Registered-token discipline: this frame is registered for "player" only
-- (player-only RegisterUnitEvent), so a secret unit token must NOT block the publish (pre-fix,
-- IsPlayerUnitToken treated any secret unit as "not player" and silently
-- dropped the cast -- exactly during the combat/encounter/challenge/PvP
-- restriction windows where cooldown tracking matters most).
local publishedBefore = #published
runtimeFrame.OnEvent(runtimeFrame, "UNIT_SPELLCAST_SUCCEEDED",
    SecretSentinel.MakeSecretSentinel(), "guid-2", 90002)
assert(#published == publishedBefore + 1,
    "a secret unit token on a player-only-registered frame must still publish (registered-token discipline)")
event = published[#published]
assert(event[1] == "CDM:COOLDOWN_CHANGED" and event[2] == 90002 and event[4] == "cast_succeeded",
    "secret-unit cast should still forward the readable spellID")

-- Secret spellID must be probed and skipped: it crosses publish() into every
-- CDM:COOLDOWN_CHANGED subscriber, some of which table-index or == it.
publishedBefore = #published
local ok, err = pcall(function()
    runtimeFrame.OnEvent(runtimeFrame, "UNIT_SPELLCAST_SUCCEEDED",
        "player", "guid-3", SecretSentinel.MakeSecretSentinel())
end)
assert(ok, "a secret spellID must not throw when probed: " .. tostring(err))
assert(#published == publishedBefore,
    "a secret spellID must be skipped, not forwarded to CDM:COOLDOWN_CHANGED subscribers")

_G.issecretvalue = restoreIsSecretValue

print("OK: cdm_resolvers_runtime_events_test")
