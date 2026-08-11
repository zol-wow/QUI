-- tests/unit/cdm_spelldata_stack_resolution_test.lua
-- Run: lua tests/unit/cdm_spelldata_stack_resolution_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame issecretvalue

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
local secretApplications = "secret-applications"

function issecretvalue(value)
    if value == secretApplications then
        error("auraData.applications decoded in Lua", 2)
    end
    return false
end

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
    -- Runtime reads ns.CDMCatalog directly; ns.CDMComposer is only the alias
    -- that ships in the LoadOnDemand options addon.
    CDMCatalog = {
        RebuildBlizzardCatalogMaps = function(_, _, _, abilityToAura, auraIDsForSpell)
            abilityToAura[55090] = 194310
            auraIDsForSpell[55090] = { 194310 }
            auraIDsForSpell[343294] = { 343294 }
            return true
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)
local spellData = ns.CDMSpellData
assert(spellData:GetAuraIDsForSpell(55090), "test catalog aura map should build through the public getter")

local auraBySpellID = {
    [191587] = {
        spellId = 191587,
        auraInstanceID = 9003,
        isHarmful = true,
        isHelpful = false,
        sourceUnit = "party1",
        isFromPlayerOrPlayerPet = true,
        duration = 20,
        applications = 1,
    },
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
    [444444] = {
        spellId = 444444,
        auraInstanceID = 9005,
        isHarmful = true,
        isHelpful = false,
        sourceUnit = "player",
        isFromPlayerOrPlayerPet = true,
        duration = 12,
        applications = secretApplications,
    },
    [555555] = {
        spellId = 555555,
        auraInstanceID = 9008,
        isHarmful = true,
        isHelpful = false,
        sourceUnit = "player",
        isFromPlayerOrPlayerPet = true,
        duration = 12,
        applications = 0,
    },
}

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "target" then
        return auraBySpellID[spellID]
    end
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "target" and (auraInstanceID == 9001
        or auraInstanceID == 9002
        or auraInstanceID == 9003
        or auraInstanceID == 9005
        or auraInstanceID == 9008) then
        return auraDuration
    end
end

ns.CDMSources.QueryAuraApplicationDisplayCount = function(unit, auraInstanceID, minApplications)
    if unit ~= "target" then return nil end
    if auraInstanceID == 9008 then
        return "0"
    end
    local count = auraInstanceID == 9001 and 4
        or auraInstanceID == 9002 and 1
        or nil
    if count and count >= minApplications then
        return tostring(count)
    end
    return nil
end

ns.CDMSources.QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
    if unit ~= "target" then return nil end
    if auraInstanceID == 9001 then return auraBySpellID[194310] end
    if auraInstanceID == 9002 then return auraBySpellID[343294] end
    if auraInstanceID == 9005 then return auraBySpellID[444444] end
    if auraInstanceID == 9008 then return auraBySpellID[555555] end
end

local state = ns.CDMAuraRuntime.ResolveState({
    spellID = 191587,
    entrySpellID = 191587,
    entryID = 191587,
    entryName = "Virulent Plague",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "trackedBar",
})

assert(state.isActive ~= true, "foreign player target debuffs must not resolve as owned target auras")
assert(state.durObj == nil, "foreign player target debuffs must not expose a DurationObject")

state = ns.CDMAuraRuntime.ResolveState({
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

state = ns.CDMAuraRuntime.ResolveState({
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
assert(state.stacks == nil, "display-count path should not set the legacy stacks field")
assert(state.stackSource == nil, "display-count path should not set the legacy stack source")
assert(state.count, "single-application target debuffs should expose a count payload")
-- minDisplayCount lowered from 2 to 1: abilities that count from a single application
-- (Reaper's Mark, Soul Reaper) now surface their count through the C display-count sink
-- instead of being hidden as a "lone 1-stack".
assert(state.count.sinkText == "1", "single-application debuffs now carry the display-count sink text")
assert(state.count.value == 1, "single-application debuffs expose the readable numeric value")
assert(state.count.shown == true, "single-application debuffs now mark the count shown")

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 444444,
    entrySpellID = 444444,
    entryID = 444444,
    entryName = "Secret Applications",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "trackedBar",
})

assert(state.isActive == true, "secret-application aura should still resolve active")
assert(not (state.count and state.count.shown == true),
    "secret auraData.applications must not become a Lua-decided stack count")

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 555555,
    entrySpellID = 555555,
    entryID = 555555,
    entryName = "Zero Display Count",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "trackedBar",
})

assert(state.isActive == true, "zero display-count aura should still resolve active")
assert(not (state.count and state.count.shown == true),
    "display-count string zero must not become visible stack text")

print("OK: cdm_spelldata_stack_resolution_test")
