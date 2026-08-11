-- tests/unit/reticle_spellcast_secret_boundary_test.lua
-- Run: lua5.1 tests/unit/reticle_spellcast_secret_boundary_test.lua
--
-- Wave 2b Task C: modules/qol/reticle.lua registers UNIT_SPELLCAST_SUCCEEDED
-- via RegisterUnitEvent(..., "player") (already player-only) but the shared
-- OnEvent handler still re-checked `event == "UNIT_SPELLCAST_SUCCEEDED" and
-- unit == "player"` before touching spellID. Fix: drop the redundant/
-- unproven-safe unit compare (registration is already the C-side filter),
-- and probe spellID for secrecy before use -- here spellID is only ever
-- forwarded to ApplyCooldownFromSpell (an API call, safe per the
-- absorb/forward-to-API secrets rule) or truthiness-checked, so no table
-- index/== on spellID actually exists in this branch; the probe is
-- defense-in-depth matching the wave's uniform pattern (see the report for
-- the honest distinction from Task C's sibling focuscastalert.lua, which
-- DOES have a real table-index use).
--
-- This test pins the BEHAVIORAL effect of the probe + dropped compare by
-- spying on ApplyCooldownFromSpell's spellID argument: a secret spellID
-- must route to the GCD-fallback call (ApplyCooldownFromSpell(gcdCooldown,
-- GCD_SPELL_ID, nil, false), the same call UpdateGCDCooldown always makes),
-- never forwarding the secret value itself; a normal spellID (even under a
-- secret/garbage unit token, since the compare was dropped) must route to
-- the direct call (ApplyCooldownFromSpell(gcdCooldown, spellID)).
--
-- Caveat (numeric secrets are headlessly untestable, honestly): a REAL WoW
-- secret spellID is an opaque engine value that throws on table-index/==.
-- secret_sentinel.lua's throwing sentinel pins "no throw, correct branch
-- taken" here, but cannot reproduce the engine's actual throw semantics for
-- a real secret number -- there is no way to fabricate that outside the
-- client.

local createdByName = {}
local eventFrame

local function noop() end

local frameMeta = {}
frameMeta.__index = function(frame, key)
    if key == "SetFrameStrata" then
        return function(self, strata) self.frameStrata = strata end
    elseif key == "SetFrameLevel" then
        return function(self, level) self.frameLevel = level end
    elseif key == "GetFrameLevel" then
        return function(self) return self.frameLevel or 10 end
    elseif key == "SetSize"
        or key == "SetAllPoints" or key == "SetPoint"
        or key == "EnableMouse" or key == "SetDrawSwipe"
        or key == "SetDrawEdge" or key == "SetHideCountdownNumbers"
        or key == "SetDrawBling" or key == "SetUseCircularEdge"
        or key == "SetTexture" or key == "SetVertexColor"
        or key == "SetAlpha" or key == "SetSwipeTexture"
        or key == "SetSwipeColor" or key == "SetReverse"
        or key == "SetAtlas" then
        return noop
    elseif key == "Show" then
        return function(self) self.shown = true end
    elseif key == "Hide" then
        return function(self) self.shown = false end
    elseif key == "IsShown" then
        return function(self) return self.shown and true or false end
    elseif key == "CreateTexture" then
        return function(self, _, drawLayer)
            local texture = setmetatable({ drawLayer = drawLayer, children = {}, scripts = {} }, frameMeta)
            table.insert(self.children, texture)
            return texture
        end
    elseif key == "RegisterEvent" then
        return function(self, event) self.events[event] = true end
    elseif key == "RegisterUnitEvent" then
        return function(self, event, unit) self.events[event] = { unit = unit } end
    elseif key == "UnregisterEvent" then
        return function(self, event) self.events[event] = nil end
    elseif key == "SetScript" then
        return function(self, script, handler) self.scripts[script] = handler end
    elseif key == "GetScript" then
        return function(self, script) return self.scripts[script] end
    elseif key == "HookScript" then
        return noop
    end
    return nil
end

local function newFrame(name, parent, frameType)
    local frame = setmetatable({
        name = name,
        parent = parent,
        frameType = frameType,
        frameLevel = 10,
        children = {},
        scripts = {},
        events = {},
    }, frameMeta)
    if name then
        createdByName[name] = frame
    end
    if parent and parent.children then
        table.insert(parent.children, frame)
    end
    return frame
end

UIParent = newFrame("UIParent")
WorldFrame = newFrame("WorldFrame", UIParent)

function CreateFrame(frameType, name, parent)
    local frame = newFrame(name, parent, frameType)
    if not name and not parent and not eventFrame then
        eventFrame = frame
    end
    return frame
end

function InCombatLockdown() return false end
function UnitClass() return "Player", "MAGE" end

C_ClassColor = {
    GetClassColor = function() return { r = 0.2, g = 0.6, b = 1 } end,
}

function GetScaledCursorPosition() return 500, 500 end
function GetTime() return 1 end
function IsLoggedIn() return true end

C_Timer = {
    After = function(_, callback) callback() end,
}

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restoreIssecretvalue = SecretSentinel.InstallSecretStub()

-- Spy on ApplyCooldownFromSpell: records every call's spellID argument.
-- Returns true for a real numeric spellID (pretend the cooldown applied) so
-- the direct-call branch does NOT also fall through to UpdateGCDCooldown's
-- own ApplyCooldownFromSpell(gcdCooldown, GCD_SPELL_ID, ...) call -- that
-- fallback path is exercised deliberately by the secret-spellID case only.
local applyCalls = {}
local function ApplyCooldownFromSpellSpy(_, spellID, reverse, ignoreGCD)
    applyCalls[#applyCalls + 1] = { spellID = spellID, reverse = reverse, ignoreGCD = ignoreGCD }
    return type(spellID) == "number"
end

local ns = {
    Helpers = {
        AssetPath = "Interface\\AddOns\\QUI\\media\\",
        IsSecretValue = function(value) return issecretvalue and issecretvalue(value) or false end,
        GetModuleDB = function(moduleName)
            assert(moduleName == "reticle", "unexpected module db request")
            return {
                enabled = true,
                hideOutOfCombat = false,
                useClassColor = false,
                customColor = { 0.2, 0.6, 1, 1 },
                inCombatAlpha = 0.8,
                outCombatAlpha = 0.3,
                ringStyle = "standard",
                ringSize = 40,
                reticleStyle = "dot",
                reticleSize = 10,
                gcdEnabled = true, -- must be true to reach the spellID-routing branch
                offsetX = 0,
                offsetY = 0,
            }
        end,
        CreateTimeThrottle = function(_, callback) return callback end,
        ApplyCooldownFromSpell = ApplyCooldownFromSpellSpy,
    },
    QUI = {},
    WhenLoggedIn = function(fn) if fn then fn() end end,
}

-- Instrumented load (Task 7): truthiness/==/# on sentinels now THROW
-- inside the module, matching in-game 12.1 secret semantics.
assert(SecretSentinel.LoadInstrumented("modules/qol/reticle.lua"))("QUI", ns)
assert(eventFrame and eventFrame.scripts.OnEvent, "reticle should register an event handler")

----------------------------------------------------------------------------
-- Registration proof: player-only via RegisterUnitEvent (unchanged by this
-- task, but pinned so a future regression to a global RegisterEvent is
-- caught here too).
----------------------------------------------------------------------------
assert(eventFrame.events.UNIT_SPELLCAST_SUCCEEDED and eventFrame.events.UNIT_SPELLCAST_SUCCEEDED.unit == "player",
    "UNIT_SPELLCAST_SUCCEEDED must be RegisterUnitEvent'd to player")

local onEvent = eventFrame.scripts.OnEvent
local GCD_SPELL_ID = 61304

----------------------------------------------------------------------------
-- Case 1: secret spellID -- must not throw, and (behaviorally) must never
-- forward the secret value to ApplyCooldownFromSpell; must instead take the
-- GCD-fallback call signature (gcdCooldown, GCD_SPELL_ID, nil, false).
----------------------------------------------------------------------------
local secretSpellID = SecretSentinel.MakeSecretSentinel()
local before = #applyCalls
local ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-1", secretSpellID)
assert(ok, "OnEvent must not throw on a secret spellID: " .. tostring(err))
assert(#applyCalls == before + 1, "exactly one ApplyCooldownFromSpell call expected for the secret-spellID case")
local last = applyCalls[#applyCalls]
assert(last.spellID == GCD_SPELL_ID and last.ignoreGCD == false,
    "a secret spellID must route to the GCD-fallback call (UpdateGCDCooldown), never forward the secret value")
for _, call in ipairs(applyCalls) do
    assert(call.spellID ~= secretSpellID, "the secret spellID must never be forwarded to ApplyCooldownFromSpell")
end

----------------------------------------------------------------------------
-- Case 2: secret UNIT token, normal numeric spellID -- the redundant unit
-- compare was dropped, so a secret/garbage unit must NOT block the direct
-- cooldown-application call. Observable effect: ApplyCooldownFromSpell must
-- be called with the REAL spellID (116, Frostbolt), not the GCD fallback.
----------------------------------------------------------------------------
local secretUnit = SecretSentinel.MakeSecretSentinel()
before = #applyCalls
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", secretUnit, "guid-2", 116)
assert(ok, "OnEvent must not throw on a secret unit token: " .. tostring(err))
assert(#applyCalls == before + 1, "exactly one ApplyCooldownFromSpell call expected")
last = applyCalls[#applyCalls]
assert(last.spellID == 116 and last.ignoreGCD == nil,
    "a normal spellID must still route to the direct cooldown call even when the payload unit is secret/garbage " ..
    "(registration is already player-scoped; the payload unit arg is unused)")

----------------------------------------------------------------------------
-- Case 3: plain regression check -- normal unit, normal spellID, common case.
----------------------------------------------------------------------------
before = #applyCalls
ok, err = pcall(onEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid-3", 116)
assert(ok, "OnEvent must not throw on the common case: " .. tostring(err))
last = applyCalls[#applyCalls]
assert(#applyCalls == before + 1 and last.spellID == 116 and last.ignoreGCD == nil,
    "the common-case cast must still route through the direct cooldown call")

_G.issecretvalue = restoreIssecretvalue

print("OK: reticle_spellcast_secret_boundary_test")
