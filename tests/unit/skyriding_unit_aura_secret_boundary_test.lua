-- tests/unit/skyriding_unit_aura_secret_boundary_test.lua
-- Run: lua tests/unit/skyriding_unit_aura_secret_boundary_test.lua
--
-- Wave 2 Task 7 (H6): eventFrame registers UNIT_AURA player-only
-- (RegisterUnitEvent("UNIT_AURA", "player"), modules/qol/skyriding.lua
-- :1414) — the C-level filter already guarantees this branch of OnEvent
-- only ever fires for the player unit. The pre-fix handler additionally
-- compared the payload `arg1` against the literal string "player" (:1460).
--
-- PTR 68569 marks the whole UNIT_AURA event SecretWhenAurasRestricted, so in
-- combat/encounter/challenge/PvP the payload unit may arrive as an opaque
-- secret value. tests/helpers/secret_sentinel.lua CAVEAT 1 documents that a
-- secret-vs-string `==` compare is a cross-type comparison in Lua 5.1: it
-- does NOT throw, it silently evaluates to `false`. So the old guard didn't
-- crash under restriction — it silently skipped the Thrill-of-the-Skies
-- buff-state refresh every time the event fired while restricted. This test
-- pins the fix (drop the arg1 read/guard for this branch) via that
-- silent-skip behavior, not a throw.

local function noop() end

local createdFrames = {}
local function newFrame()
    local frame = { scripts = {}, shown = false }
    local methods = {}
    function methods:SetScript(script, handler) self.scripts[script] = handler end
    function methods:GetScript(script) return self.scripts[script] end
    function methods:RegisterEvent() end
    function methods:RegisterUnitEvent() end
    function methods:UnregisterEvent() end
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:IsShown() return self.shown end
    return setmetatable(frame, { __index = function(_, k) return methods[k] or noop end })
end
function CreateFrame()
    local f = newFrame()
    createdFrames[#createdFrames + 1] = f
    return f
end

BASE_MOVEMENT_SPEED = 7
UIParent = newFrame()
C_Timer = {
    After = noop,
    NewTimer = function() return { Cancel = noop } end,
}
C_PlayerInfo = {
    GetGlidingInfo = function() return false, false, 0 end,
}

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIssecretvalue = SecretSentinel.InstallSecretStub()

-- settings.enabled = false forces the UNIT_AURA branch's second statement
-- (`if not settings or settings.enabled == false then return end`) to
-- return immediately after the ONE GetSettings() call — a clean,
-- side-effect-free call counter proving whether the branch body ran, with
-- no need to drive RefreshThrillOfTheSkiesBuffState/frame refs.
local getSettingsCalls = 0
local ns = {
    QUI = {},
    Addon = {},
    Helpers = {
        AssetPath = "",
        CreateDBGetter = function()
            return function()
                getSettingsCalls = getSettingsCalls + 1
                return { enabled = false }
            end
        end,
        ApplyCooldownFromSpell = noop,
        IsSecretValue = function(value) return value == "secret" end,
        SafeValue = function(value, fallback)
            if value == "secret" then return fallback end
            return value
        end,
    },
}

-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("modules/qol/skyriding.lua"))("QUI", ns)

assert(#createdFrames == 1, "skyriding.lua should create exactly one top-level event frame at load")
local eventFrame = createdFrames[1]
local onEvent = eventFrame:GetScript("OnEvent")
assert(type(onEvent) == "function", "skyriding event frame should have an OnEvent handler")

-- Secret/opaque unit token (simulates PTR 68569 restriction).
local before = getSettingsCalls
onEvent(eventFrame, "UNIT_AURA", SecretSentinel.MakeSecretSentinel())
assert(getSettingsCalls == before + 1,
    "UNIT_AURA branch must run (call GetSettings) regardless of the payload unit's identity (registration is already player-only)")

-- Plain "player" string still works (no regression on the common case).
before = getSettingsCalls
onEvent(eventFrame, "UNIT_AURA", "player")
assert(getSettingsCalls == before + 1,
    "UNIT_AURA branch should still fire for the literal 'player' token")

_G.issecretvalue = restoreIssecretvalue

print("OK: skyriding_unit_aura_secret_boundary_test")
