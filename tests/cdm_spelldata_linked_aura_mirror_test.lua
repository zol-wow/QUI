-- tests/cdm_spelldata_linked_aura_mirror_test.lua
-- Run: lua tests/cdm_spelldata_linked_aura_mirror_test.lua

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

local linkedAuraDuration = { token = "linked-aura-duration" }

local cooldownInfo = {
    cooldownID = 1000,
    viewerCategory = "essential",
    spellID = 100,
    overrideSpellID = 100,
    hasAura = true,
    linkedSpellIDs = { 200 },
    wasSetFromAura = false,
    wasSetFromCooldown = true,
    wasSetFromCharges = false,
}

local linkedAuraState = {
    cooldownID = 2000,
    viewerCategory = "buff",
    spellID = 200,
    overrideSpellID = 200,
    isActive = true,
    durObj = linkedAuraDuration,
    durObjSource = "aura-child",
    selfAura = true,
    mirrorEpoch = 9,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID)
            if cooldownID == 1000 then
                return cooldownInfo
            end
        end,
        GetCooldownInfoForViewer = function(spellID, viewerType)
            if spellID == 100 and viewerType == "essential" then
                return cooldownInfo
            end
        end,
        GetMirroredStateForViewer = function(spellID, viewerType)
            if spellID == 200 and viewerType == "buff" then
                return linkedAuraState
            end
        end,
    },
}

assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

local state = ns.CDMSpellData:ResolveAuraState({
    spellID = 100,
    entrySpellID = 100,
    entryID = 100,
    entryName = "Linked Aura Test",
    entryKind = "cooldown",
    entryIsAura = false,
    entryType = "spell",
    viewerType = "essential",
    blizzardMirrorCooldownID = 1000,
})

assert(state.isActive == true, "cooldown icons should use active linked aura mirror state")
assert(state.durObj == linkedAuraDuration, "cooldown icons should receive the linked aura DurationObject")
assert(state.auraUnit == "player", "self linked aura should resolve to player")
assert(state.resolvedAuraSpellID == 200, "linked aura spellID should become the active aura spellID")

local queriedLooseStackName = false
local stackDuration = { token = "stack-duration" }

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" and spellID == 300 then
        return {
            spellId = 300,
            auraInstanceID = 700,
            isHelpful = true,
            duration = 12,
        }
    end
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 700 then
        return stackDuration
    end
end

ns.CDMSources.QueryAuraApplicationDisplayCount = function()
    return nil
end

ns.CDMSources.QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 700 then
        return {
            spellId = 300,
            auraInstanceID = 700,
            isHelpful = true,
            duration = 12,
        }
    end
end

ns.CDMSources.QueryAuraDataBySpellName = function(unit, name, filter)
    if unit == "pet" and name == "Stack Lock Test" and filter == "HELPFUL" then
        queriedLooseStackName = true
        return {
            spellId = 301,
            auraInstanceID = 701,
            isHelpful = true,
            applications = 5,
            duration = 12,
        }
    end
end

state = ns.CDMSpellData:ResolveAuraState({
    spellID = 300,
    entrySpellID = 300,
    entryID = 300,
    entryName = "Stack Lock Test",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "aura",
    viewerType = "custom",
})

assert(state.isActive == true, "instance-backed aura should be active")
assert(state.auraInstanceID == 700, "test must resolve the player aura instance")
assert(state.durObj == stackDuration, "test must use the resolved aura instance duration")
assert(state.stacks == nil, "resolved aura instances with no applications must not inherit loose name fallback stacks")
assert(queriedLooseStackName == false, "resolved aura instances should not query loose name stack fallbacks")

print("OK: cdm_spelldata_linked_aura_mirror_test")
