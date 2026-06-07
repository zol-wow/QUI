-- tests/unit/cdm_blizz_mirror_target_ownership_test.lua
-- Run: lua tests/unit/cdm_blizz_mirror_target_ownership_test.lua

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

local unknownSelfAuraChild = {
    cooldownID = 88002,
    isActive = true,
    auraDataUnit = "target",
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
unknownSelfAuraChild.Cooldown.GetParent = function() return unknownSelfAuraChild end

EssentialCooldownViewer = { GetChildren = function() end }
UtilityCooldownViewer = { GetChildren = function() end }
BuffIconCooldownViewer = {
    GetChildren = function()
        return targetAuraChild, unknownSelfAuraChild
    end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 2 then
            return { 88001, 88002 }
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
        if cooldownID == 88002 then
            return {
                cooldownID = 88002,
                spellID = 500101,
                overrideSpellID = 500101,
                overrideTooltipSpellID = 500102,
                linkedSpellIDs = { 500102 },
                selfAura = nil,
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
    [993] = false,
    [994] = true,
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

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)
assert(loadfile("QUI_CDM/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

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
    if unit == "target" and spellID == 500102 then
        return {
            spellId = 500102,
            auraInstanceID = 993,
            isFromPlayerOrPlayerPet = false,
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
    if unit == "target" and auraInstanceID == 993 then
        return { token = "unknown-self-foreign-duration" }
    end
    if unit == "target" and auraInstanceID == 994 then
        return { token = "unknown-self-owned-duration" }
    end
    return nil
end

ns.CDMSources.QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
    local owned = targetInstanceOwned[auraInstanceID]
    if unit == "target" and owned ~= nil then
        return {
            spellId = auraInstanceID == 993 and 500102 or 500002,
            auraInstanceID = auraInstanceID,
            isFromPlayerOrPlayerPet = owned,
        }
    end
    return nil
end

ns.CDMBlizzMirror.ForceRescan()

-- After the mirror→resolver refactor, the mirror no longer caches a flat
-- isActive flag or a selected durObj/durObjSource. It owns event-driven
-- attribution only: auraInstanceID, auraUnit, auraDurObj. "Ownership proven"
-- in the new model = auraInstanceID stamped on the state. "Activity" is
-- derived by the resolver from that attribution + live aura queries.
local unknownSelfState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88002),
    "unknown-self target aura mirror state missing after rescan")
assert(unknownSelfState.auraInstanceID == nil,
    "target-side aura children with unknown selfAura must not stamp before ownership is proven")
assert(unknownSelfState.hasAuraInstanceID ~= true,
    "unknown-self target aura children must not stamp foreign auraInstanceIDs")
assert(unknownSelfState.auraDurObj == nil,
    "unknown-self target aura children must not retain foreign target DurationObjects")

unknownSelfAuraChild.auraInstanceID = 993
unknownSelfAuraChild.Cooldown:SetCooldown()

unknownSelfState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88002),
    "unknown-self target aura mirror state missing after foreign child cooldown")
assert(unknownSelfState.auraInstanceID == nil,
    "unknown-self target child foreign auraInstanceIDs must not stamp when ownership fails")
assert(unknownSelfState.auraDurObj == nil,
    "unknown-self target child foreign instances must not populate the aura lane")

unknownSelfAuraChild.auraInstanceID = 994
unknownSelfAuraChild.Cooldown:SetCooldown()

unknownSelfState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88002),
    "unknown-self owned target aura mirror state missing")
assert(unknownSelfState.auraInstanceID == 994,
    "unknown-self owned target child auraInstanceIDs should stamp once ownership is proven")
assert(unknownSelfState.hasAuraInstanceID == true,
    "unknown-self owned target child auraInstanceIDs should stamp the mirror")

targetAuraChild.Cooldown:SetCooldownFromDurationObject(foreignChildDuration)

local state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after child duration")
assert(state.auraInstanceID == nil, "target-side child durations must not stamp before ownership is proven")
assert(state.auraDurObj == nil, "target-side child durations must not populate the aura lane before ownership is proven")

ns.CDMBlizzMirror.HandleUnitAuraChanged("player", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after player scan")
assert(state.auraInstanceID == nil, "target-side debuffs must not stamp from player-unit aura scans")
assert(state.hasAuraInstanceID ~= true, "target-side debuffs must not stamp player-unit auraInstanceIDs")
assert(state.auraDurObj == nil, "target-side debuffs must not retain player-unit DurationObjects")

ns.CDMBlizzMirror.HandleUnitAuraChanged("target", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing")
assert(queriedTargetAura == true, "test must exercise the target aura lookup path")
assert(state.auraInstanceID == nil, "foreign target debuffs must not stamp target-side buff icons")
assert(state.hasAuraInstanceID ~= true, "foreign target debuffs must not stamp an auraInstanceID")
assert(state.auraDurObj == nil, "foreign target debuffs must not populate the aura lane")

targetAuraChild.auraInstanceID = 991
targetAuraChild.auraDataUnit = "target"
targetAuraChild.Cooldown:SetCooldown()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after foreign child instance")
assert(state.auraInstanceID == nil, "foreign target child auraInstanceIDs must not stamp the mirror")
assert(state.auraDurObj == nil, "foreign target child auraInstanceIDs must not populate the aura lane")

targetAuraChild.auraInstanceID = 992
targetAuraChild.auraDataUnit = "target"
targetAuraChild.Cooldown:SetCooldown()

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "owned target child aura mirror state missing")
assert(state.auraInstanceID == 992, "owned target child auraInstanceIDs should stamp target-side buff icons")
assert(state.hasAuraInstanceID == true, "owned target child auraInstanceIDs should stamp the mirror")
assert(state.auraDurObj == ownedTargetDuration, "owned target child auraInstanceIDs should populate the aura lane")

targetInstanceOwned[992] = false
ns.CDMBlizzMirror.HandleUnitAuraChanged("target", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "target aura mirror state missing after ownership loss")
assert(state.auraInstanceID == nil, "target child auraInstanceIDs should clear when ownership no longer matches")
assert(state.hasAuraInstanceID ~= true, "target child auraInstanceIDs should clear stamped instances after ownership loss")
assert(state.auraDurObj == nil, "target child auraInstanceIDs should clear the aura lane after ownership loss")

targetInstanceOwned[992] = true
targetAuraOwned = true
ns.CDMBlizzMirror.HandleUnitAuraChanged("target", { isFullUpdate = true })

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "owned target aura mirror state missing")
assert(state.auraInstanceID == 992, "owned target debuffs should stamp an auraInstanceID")
assert(state.hasAuraInstanceID == true, "owned target debuffs should stamp an auraInstanceID")
assert(state.auraDurObj == ownedTargetDuration, "owned target debuffs should populate the aura lane")

targetAuraChild.Cooldown:SetCooldownFromDurationObject(ownedChildDuration)

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(88001), "owned target aura mirror state missing after child duration")
assert(state.auraInstanceID == 992, "owned target debuffs should stay stamped after child duration")
assert(state.auraDurObj == ownedChildDuration, "owned target debuffs should select verified child DurationObjects first")
assert(state.auraDurObjSource == "aura-child", "owned target child DurationObjects should be identified as the child source")

print("OK: cdm_blizz_mirror_target_ownership_test")
