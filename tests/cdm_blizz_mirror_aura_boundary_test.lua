-- tests/cdm_blizz_mirror_aura_boundary_test.lua
-- Run: lua tests/cdm_blizz_mirror_aura_boundary_test.lua

local function noop() end
local eventScript

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
        SetScript = function(_, script, handler)
            if script == "OnEvent" then
                eventScript = handler
            end
        end,
    }
end

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

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

local function MakeViewer(getChildren)
    return {
        alpha = 1,
        GetAlpha = function(self) return self.alpha end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        GetChildren = getChildren,
    }
end

EssentialCooldownViewer = MakeViewer(function() end)
UtilityCooldownViewer = MakeViewer(function() end)
BuffIconCooldownViewer = {
    alpha = 1,
    GetAlpha = function(self) return self.alpha end,
    SetAlpha = function(self, alpha) self.alpha = alpha end,
    GetChildren = function()
        return auraChild
    end,
}
BuffBarCooldownViewer = MakeViewer(function() end)

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 2 then return { 2001 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
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

local auraScanCalls = 0
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
    },
    CDMIcons = {
        UpdateAllCooldowns = noop,
    },
}

assert(loadfile("modules/cdm/cdm_blizz_mirror.lua"))("QUI", ns)
assert(type(eventScript) == "function", "mirror event script should be installed")

ns.CDMBlizzMirror.ForceRescan()

local boundaryEvents = {
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
}

for _, event in ipairs(boundaryEvents) do
    auraScanCalls = 0
    eventScript(nil, event)
    assert(auraScanCalls == 0, event .. " should not proactively rebuild auraInstanceID mirror state")
end

print("OK: cdm_blizz_mirror_aura_boundary_test")
