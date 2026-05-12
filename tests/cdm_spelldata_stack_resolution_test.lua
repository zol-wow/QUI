-- tests/cdm_spelldata_stack_resolution_test.lua
-- Run: lua tests/cdm_spelldata_stack_resolution_test.lua

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

local auraDuration = { token = "aura-duration" }
local mirroredAuraDuration = { token = "mirrored-aura-duration" }

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function(auraData)
            return auraData and auraData.sourceUnit == "player"
        end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
    CDMBlizzMirror = {},
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(_, _, _, abilityToAura, auraIDsForSpell)
            abilityToAura[55090] = 194310
            auraIDsForSpell[55090] = { 194310 }
            auraIDsForSpell[343294] = { 343294 }
            return true
        end,
    },
}

assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)
local spellData = ns.CDMSpellData
spellData._abilityToAuraSpellID[55090] = 194310

local auraBySpellID = {
    [194310] = {
        spellId = 194310,
        auraInstanceID = 9001,
        isHarmful = true,
        isHelpful = false,
        sourceUnit = "player",
        isFromPlayerOrPlayerPet = true,
        duration = 24,
        applications = 4,
    },
    [343294] = {
        spellId = 343294,
        auraInstanceID = 9002,
        isHarmful = true,
        isHelpful = false,
        sourceUnit = "player",
        isFromPlayerOrPlayerPet = true,
        duration = 5,
        applications = 1,
    },
}

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "target" then
        return auraBySpellID[spellID]
    end
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "target" and (auraInstanceID == 9001 or auraInstanceID == 9002) then
        return auraDuration
    end
end

ns.CDMSources.QueryAuraApplicationDisplayCount = function(unit, auraInstanceID, minApplications)
    if unit ~= "target" then return nil end
    local count = auraInstanceID == 9001 and 4 or auraInstanceID == 9002 and 1 or nil
    if count and count >= minApplications then
        return tostring(count)
    end
    return nil
end

ns.CDMSources.QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
    if unit ~= "target" then return nil end
    if auraInstanceID == 9001 then return auraBySpellID[194310] end
    if auraInstanceID == 9002 then return auraBySpellID[343294] end
end

ns.CDMBlizzMirror.GetMirroredStateForViewer = function(spellID, viewerType)
    if spellID == 777001 and viewerType == "trackedBar" then
        return {
            isActive = true,
            durObj = mirroredAuraDuration,
            selfAura = false,
            cooldownID = 777001,
            stackText = "7",
            stackTextSource = "Applications",
            stackTextShown = true,
        }
    end
end

local state = spellData:ResolveAuraState({
    spellID = 777001,
    entrySpellID = 777001,
    entryID = 777001,
    entryName = "Mirrored Applications",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "trackedBar",
})

assert(state.isActive == true, "mirrored aura should resolve as active")
assert(state.durObj == mirroredAuraDuration, "mirrored aura should keep its DurationObject")
assert(state.stacks == nil, "mirrored aura should not expose legacy stack text")
assert(state.stackSource == nil, "mirrored aura should not expose legacy stack source")
assert(state.count, "mirrored aura should expose a shared count payload")
assert(state.count.sinkText == "7", "mirrored aura count should carry sink text")
assert(state.count.value == 7, "mirrored aura count should expose a safe numeric value when readable")
assert(state.count.shown == true, "mirrored aura count should be marked shown")
assert(state.count.source == "Applications", "mirrored aura count should keep its source")

state = spellData:ResolveAuraState({
    spellID = 55090,
    entrySpellID = 55090,
    entryID = 55090,
    entryName = "Scourge Strike",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "trackedBar",
})

assert(state.isActive == true, "Scourge Strike should resolve through its mapped target stack aura")
assert(state.resolvedAuraSpellID == 194310, "Scourge Strike should use Festering Wound as the resolved aura")
assert(state.auraUnit == "target", "mapped stack aura should be target-side")
assert(state.stackSource == nil, "multi-application target aura should not expose legacy stack source")
assert(state.stacks == nil, "multi-application target aura should not expose legacy stack text")
assert(state.count, "display-count stack should expose a shared count payload")
assert(state.count.sinkText == "4", "display-count stack should carry sink text")
assert(state.count.value == 4, "display-count stack should expose a safe numeric value when readable")
assert(state.count.shown == true, "display-count stack should be marked shown")
assert(state.count.source == "display-count", "display-count stack should keep its source")

state = spellData:ResolveAuraState({
    spellID = 343294,
    entrySpellID = 343294,
    entryID = 343294,
    entryName = "Soul Reaper",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "trackedBar",
})

assert(state.isActive == true, "Soul Reaper debuff should still resolve as active")
assert(state.resolvedAuraSpellID == 343294, "Soul Reaper should resolve its own target debuff")
assert(state.stacks == nil, "single-application target debuffs should not be displayed as stacks")
assert(state.stackSource == nil, "single-application target debuffs should not set a stack source")
assert(state.count, "single-application target debuffs should still expose a count payload")
assert(state.count.sinkText == nil, "single-application target debuffs should not carry sink text")
assert(state.count.value == nil, "single-application target debuffs should not carry a count value")
assert(state.count.shown == false, "single-application target debuffs should mark count hidden")

print("OK: cdm_spelldata_stack_resolution_test")
