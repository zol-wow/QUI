-- tests/unit/cdm_blizz_mirror_candidate_cache_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_candidate_cache_test.lua

local function noop() end

function hooksecurefunc(owner, method, hook)
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
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

local cooldownChild = {
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
cooldownChild.Cooldown.GetParent = function() return cooldownChild end

local auraChild = {
    cooldownID = 2001,
    auraInstanceID = 777,
    auraDataUnit = "player",
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

EssentialCooldownViewer = {
    GetChildren = function()
        return cooldownChild
    end,
}
UtilityCooldownViewer = { GetChildren = function() end }
BuffIconCooldownViewer = {
    GetChildren = function()
        return auraChild
    end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then return { 1001 } end
        if category == 2 then return { 2001 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 1001 then
            return {
                cooldownID = 1001,
                spellID = 5001,
                overrideSpellID = 5002,
                overrideTooltipSpellID = 5003,
                linkedSpellIDs = { 5004 },
                selfAura = true,
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
    end,
}

local queryCooldownAuraCalls = 0
local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMSources = {
        QueryCooldownAuraBySpellID = function(spellID)
            queryCooldownAuraCalls = queryCooldownAuraCalls + 1
            if spellID == 5001 then return 9001 end
        end,
        QueryAuraDuration = function(unit, auraInstanceID)
            if unit == "player" and auraInstanceID == 777 then
                return { token = "aura-duration" }
            end
        end,
    },
    CDMIcons = {
        UpdateAllCooldowns = noop,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMBlizzMirror.ForceRescan()
queryCooldownAuraCalls = 0

cooldownChild.Cooldown:SetCooldown(1, 2, 1)
local firstCount = queryCooldownAuraCalls

cooldownChild.Cooldown:SetCooldown(1, 2, 1)
local secondCount = queryCooldownAuraCalls

assert(firstCount >= 0, "candidate query counter should be readable")
assert(secondCount == firstCount,
    "repeated mirror updates for the same cooldown info should reuse aura candidate cache")

print("OK: cdm_blizz_mirror_candidate_cache_test")
