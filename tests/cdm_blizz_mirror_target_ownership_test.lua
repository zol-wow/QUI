-- tests/cdm_blizz_mirror_target_ownership_test.lua
-- Run: lua tests/cdm_blizz_mirror_target_ownership_test.lua

local function noop() end

function hooksecurefunc(owner, method, hook)
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 456 end
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

local targetAuraChild = {
    cooldownID = 88001,
    isActive = true,
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
targetAuraChild.Cooldown.GetParent = function() return targetAuraChild end

EssentialCooldownViewer = { GetChildren = function() end }
UtilityCooldownViewer = { GetChildren = function() end }
BuffIconCooldownViewer = {
    GetChildren = function()
        return targetAuraChild
    end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 2 then
            return { 88001 }
        end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 88001 then
            return {
                cooldownID = 88001,
                spellID = 500001,
                overrideSpellID = 500001,
                overrideTooltipSpellID = 500002,
                linkedSpellIDs = { 500002 },
                selfAura = false,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local queriedTargetAura = false
local targetAuraOwned = false
local targetInstanceOwned = {
    [991] = false,
    [992] = true,
}
local foreignChildDuration = { token = "foreign-child-duration" }
local ownedChildDuration = { token = "owned-child-duration" }
local ownedTargetDuration = { token = "owned-target-duration" }

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        IsAuraOwnedByPlayerOrPet = function(auraData)
            return auraData and auraData.isFromPlayerOrPlayerPet == true
        end,
    },
}

assert(loadfile("modules/cdm/cdm_sources.lua"))("QUI", ns)
assert(loadfile("modules/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" and spellID == 500002 then
        return {
            spellId = 500002,
            auraInstanceID = 990,
            isFromPlayerOrPlayerPet = true,
        }
    end
    if unit == "target" and spellID == 500002 then
        queriedTargetAura = true
        return {
            spellId = 500002,
            auraInstanceID = targetAuraOwned and 992 or 991,
            isFromPlayerOrPlayerPet = targetAuraOwned,
        }
    end
    return nil
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 990 then
        return { token = "player-wrong-unit-duration" }
    end
    if unit == "target" and auraInstanceID == 992 then
        return ownedTargetDuration
    end
    if unit == "target" and auraInstanceID == 991 then
        return { token = "foreign-target-duration" }
    end
    return nil
end

ns.CDMSources.QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
    local owned = targetInstanceOwned[auraInstanceID]
    if unit == "target" and owned ~= nil then
        return {
            spellId = 500002,
            auraInstanceID = auraInstanceID,
            isFromPlayerOrPlayerPet = owned,
        }
    end
    return nil
end

ns.CDMBlizzMirror.ForceRescan()
targetAuraChild.Cooldown:SetCooldownFromDurationObject(foreignChildDuration)

local state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after child duration")
assert(state.isActive ~= true, "target-side child durations must not activate before ownership is proven")
assert(state.durObj == nil, "target-side child durations must not be selected before ownership is proven")

ns.CDMBlizzMirror.HandleUnitAuraChanged("player", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after player scan")
assert(state.isActive ~= true, "target-side debuffs must not activate from player-unit aura scans")
assert(state.hasAuraInstanceID ~= true, "target-side debuffs must not stamp player-unit auraInstanceIDs")
assert(state.durObj == nil, "target-side debuffs must not use player-unit DurationObjects")

ns.CDMBlizzMirror.HandleUnitAuraChanged("target", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing")
assert(queriedTargetAura == true, "test must exercise the target aura lookup path")
assert(state.isActive ~= true, "foreign target debuffs must not activate target-side buff icons")
assert(state.hasAuraInstanceID ~= true, "foreign target debuffs must not stamp an auraInstanceID")
assert(state.durObj == nil, "foreign target debuffs must not supply a DurationObject")

targetAuraChild.auraInstanceID = 991
targetAuraChild.auraDataUnit = "target"
targetAuraChild.Cooldown:SetCooldown()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after foreign child instance")
assert(state.isActive ~= true, "foreign target child auraInstanceIDs must not activate target-side buff icons")
assert(state.hasAuraInstanceID ~= true, "foreign target child auraInstanceIDs must not stamp the mirror")
assert(state.durObj == nil, "foreign target child auraInstanceIDs must not supply a DurationObject")

targetAuraChild.auraInstanceID = 992
targetAuraChild.auraDataUnit = "target"
targetAuraChild.Cooldown:SetCooldown()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "owned target child aura mirror state missing")
assert(state.isActive == true, "owned target child auraInstanceIDs should activate target-side buff icons")
assert(state.hasAuraInstanceID == true, "owned target child auraInstanceIDs should stamp the mirror")
assert(state.durObj == ownedTargetDuration, "owned target child auraInstanceIDs should use their aura DurationObject")

targetInstanceOwned[992] = false
ns.CDMBlizzMirror.HandleUnitAuraChanged("target", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after ownership loss")
assert(state.isActive ~= true, "target child auraInstanceIDs should clear when ownership no longer matches")
assert(state.hasAuraInstanceID ~= true, "target child auraInstanceIDs should clear stamped instances after ownership loss")
assert(state.durObj == nil, "target child auraInstanceIDs should clear DurationObjects after ownership loss")

targetInstanceOwned[992] = true
targetAuraOwned = true
ns.CDMBlizzMirror.HandleUnitAuraChanged("target", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "owned target aura mirror state missing")
assert(state.isActive == true, "owned target debuffs should activate target-side buff icons")
assert(state.hasAuraInstanceID == true, "owned target debuffs should stamp an auraInstanceID")
assert(state.durObj == ownedTargetDuration, "owned target debuffs should use their aura DurationObject")

targetAuraChild.Cooldown:SetCooldownFromDurationObject(ownedChildDuration)

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "owned target aura mirror state missing after child duration")
assert(state.isActive == true, "owned target debuffs should stay active after child duration")
assert(state.durObj == ownedChildDuration, "owned target debuffs should select verified child DurationObjects first")
assert(state.durObjSource == "aura-child", "owned target child DurationObjects should be identified as the child source")

print("OK: cdm_blizz_mirror_target_ownership_test")
