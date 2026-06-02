-- tests/unit/cdm_blizz_mirror_two_phase_walk_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_two_phase_walk_test.lua
--
-- The mirror must not treat an incomplete CooldownViewer scan as an empty
-- catalog. A later scan can list a cooldownID before its cooldown info is
-- available; preserving the last complete maps keeps existing icons bound.

local function noop() end

function hooksecurefunc(owner, method, hook)
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 50 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

local child = {
    cooldownID = 90001,
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
child.Cooldown.GetParent = function() return child end

EssentialCooldownViewer = {
    GetChildren = function()
        return child
    end,
}
UtilityCooldownViewer = { GetChildren = function() end }
BuffIconCooldownViewer = { GetChildren = function() end }
BuffBarCooldownViewer = { GetChildren = function() end }

local infoReady = true
C_CooldownViewer = {
    IsCooldownViewerAvailable = function()
        return true, ""
    end,
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then return { 90001 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID ~= 90001 or not infoReady then
            return nil
        end
        return {
            cooldownID = 90001,
            spellID = 990001,
            overrideSpellID = 990002,
            overrideTooltipSpellID = nil,
            linkedSpellIDs = {},
            selfAura = false,
            hasAura = false,
            charges = false,
            isKnown = true,
        }
    end,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
}

assert(loadfile("modules/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMBlizzMirror.ForceRescan()

local state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(90001, "essential"),
    "complete scan should create an essential mirror state")
assert(state.spellID == 990001,
    "complete scan should expose captured cooldown info")
assert(ns.CDMBlizzMirror.GetCooldownIDForViewer(990002, "essential") == 90001,
    "complete scan should populate spell-to-cooldown maps")

infoReady = false
ns.CDMBlizzMirror.ForceRescan()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(90001, "essential"),
    "incomplete rescan should not discard previous mirror state")
assert(state.spellID == 990001,
    "incomplete rescan should preserve previous cooldown info")
assert(ns.CDMBlizzMirror.GetCooldownIDForViewer(990002, "essential") == 90001,
    "incomplete rescan should preserve previous spell-to-cooldown maps")

print("OK: cdm_blizz_mirror_two_phase_walk_test")
