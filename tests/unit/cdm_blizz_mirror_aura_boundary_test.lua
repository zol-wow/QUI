-- tests/unit/cdm_blizz_mirror_aura_boundary_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_aura_boundary_test.lua

local function noop() end
local eventScript
local registeredUnitEvents = {}
local timers = {}
local hookCalls = 0

function hooksecurefunc(owner, method, hook)
    hookCalls = hookCalls + 1
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 10 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = function(_, event)
            registeredUnitEvents[event] = true
        end,
        SetScript = function(_, script, handler)
            if script == "OnEvent" then
                eventScript = handler
            end
        end,
    }
end

C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = {
            delay = delay,
            callback = callback,
        }
    end,
}

local function RunTimers()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        timer.callback()
    end
end

local auraChild = {
    cooldownID = 2001,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
auraChild.Cooldown.GetParent = function() return auraChild end
local auraChildWrites = {}
setmetatable(auraChild, {
    __newindex = function(tbl, key, value)
        auraChildWrites[key] = value
        rawset(tbl, key, value)
    end,
})

local lateAuraChild = {
    cooldownID = 3001,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
lateAuraChild.Cooldown.GetParent = function() return lateAuraChild end

local essentialChild = {
    cooldownID = 1001,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
essentialChild.Cooldown.GetParent = function() return essentialChild end

local function MakeViewer(getChildren)
    return {
        alpha = 1,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        GetChildren = getChildren,
    }
end

EssentialCooldownViewer = MakeViewer(function()
    return essentialChild
end)
UtilityCooldownViewer = MakeViewer(function() end)
local includeLateAuraChild = false
BuffIconCooldownViewer = {
    alpha = 1,
    GetAlpha = function(self) return self.alpha end,
    SetAlpha = function(self, alpha) self.alpha = alpha end,
    GetChildren = function()
        if includeLateAuraChild then
            return auraChild, lateAuraChild
        end
        return auraChild
    end,
}
BuffBarCooldownViewer = MakeViewer(function() end)

local essentialOverrideSpellID = 255937
C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then return { 1001 } end
        if category == 2 then return { 2001, 3001 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 1001 then
            return {
                cooldownID = 1001,
                spellID = 255937,
                overrideSpellID = essentialOverrideSpellID,
                linkedSpellIDs = {},
                selfAura = false,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 2001 then
            return {
                cooldownID = 2001,
                spellID = 9001,
                overrideSpellID = 9001,
                linkedSpellIDs = {},
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 3001 then
            return {
                cooldownID = 3001,
                spellID = 300001,
                overrideSpellID = 300001,
                linkedSpellIDs = {},
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local auraScanCalls = 0
local mirrorRefreshes = {}
local function CountTargetedMirrorRefreshes()
    local count = 0
    for _, refresh in ipairs(mirrorRefreshes) do
        if refresh.cooldownID ~= nil then
            count = count + 1
        end
    end
    return count
end
local function CountTargetedMirrorRefreshesFor(cooldownID, category)
    local count = 0
    for _, refresh in ipairs(mirrorRefreshes) do
        if refresh.cooldownID == cooldownID and refresh.category == category then
            count = count + 1
        end
    end
    return count
end
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMSources = {
        QueryPlayerAuraBySpellID = function()
            auraScanCalls = auraScanCalls + 1
            return nil
        end,
        QueryUnitAuraBySpellID = function()
            auraScanCalls = auraScanCalls + 1
            return nil
        end,
        QueryAuraDataBySpellID = function()
            auraScanCalls = auraScanCalls + 1
            return nil
        end,
        QueryBaseSpell = function(spellID)
            if spellID == 427453 then return 255937 end
            return nil
        end,
    },
    CDMIcons = {
        UpdateAllCooldowns = noop,
        RequestMirrorTextRefresh = function(_, cooldownID, category, reason)
            mirrorRefreshes[#mirrorRefreshes + 1] = {
                cooldownID = cooldownID,
                category = category,
                reason = reason,
            }
        end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)
assert(type(eventScript) == "function", "mirror event script should be installed")
assert(registeredUnitEvents.UNIT_AURA ~= true,
    "mirror should consume UNIT_AURA from cdm_spelldata instead of registering its own raw UNIT_AURA handler")

ns.CDMBlizzMirror.ForceRescan()
local wakeState = ns.CDMBlizzMirror.GetStateByCooldownID(1001, "essential")
assert(wakeState and wakeState.overrideSpellID == 255937,
    "initial essential mirror state should be captured before overlay")
assert(rawget(auraChild, "_quiMirrorBound") == nil,
    "mirror must not store hook bookkeeping on Blizzard cooldown children")
assert(auraChildWrites._quiMirrorBound == nil,
    "mirror must keep hook bookkeeping in side tables to avoid tainting Blizzard children")

local firstHookCalls = hookCalls
ns.CDMBlizzMirror.ForceRescan()
assert(hookCalls == firstHookCalls,
    "rescanning an already-bound child must not install duplicate hooks")

local boundaryEvents = {
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
}

for _, event in ipairs(boundaryEvents) do
    auraScanCalls = 0
    eventScript(nil, event)
    assert(auraScanCalls == 0, event .. " should not proactively rebuild auraInstanceID mirror state")
end

mirrorRefreshes = {}
eventScript(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 9001)
assert(#mirrorRefreshes >= 1,
    "mapped overlay events should refresh the matching aura-viewer child")
assert(mirrorRefreshes[1].cooldownID == 2001,
    "mapped overlay refresh should target the matching aura cooldownID")
RunTimers()

mirrorRefreshes = {}
essentialOverrideSpellID = 255937
eventScript(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 427453)
local staleHammerState = ns.CDMBlizzMirror.GetStateByCooldownID(1001, "essential")
assert(staleHammerState and staleHammerState.overrideSpellID == 255937,
    "initial overlay read can race before the viewer exposes the override")
essentialOverrideSpellID = 427453
RunTimers()
local delayedHammerState = ns.CDMBlizzMirror.GetStateByCooldownID(1001, "essential")
assert(delayedHammerState and delayedHammerState.overrideSpellID == 427453,
    "overlay retry should refresh the mapped base cooldown info after viewer state catches up")
assert(CountTargetedMirrorRefreshesFor(1001, "essential") >= 1,
    "overlay retry should refresh the matching essential cooldownID")
assert(CountTargetedMirrorRefreshesFor(2001, "buff") == 0,
    "override overlay events should not refresh unrelated aura-viewer children")

mirrorRefreshes = {}
essentialOverrideSpellID = 427453
eventScript(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 427453)
local hammerState = ns.CDMBlizzMirror.GetStateByCooldownID(1001, "essential")
assert(hammerState and hammerState.overrideSpellID == 427453,
    "override overlay events should refresh the mapped base cooldown info")
includeLateAuraChild = true
assert(lateAuraChild._quiMirrorBound ~= true,
    "late unrelated aura child should start unbound")
eventScript(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 427453)
assert(lateAuraChild._quiMirrorBound ~= true,
    "override overlay events should not bind unrelated late aura children")

mirrorRefreshes = {}
eventScript(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 123456)
assert(CountTargetedMirrorRefreshes() == 0,
    "unmapped overlay events should not refresh every aura-viewer child")
assert(#mirrorRefreshes == 0,
    "unmapped overlay events should not request a broad mirror refresh")

print("OK: cdm_blizz_mirror_aura_boundary_test")
