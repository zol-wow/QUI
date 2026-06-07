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
local mirroredAuraDuration = { token = "mirrored-aura-duration" }
local mirroredTargetAuraDuration = { token = "mirrored-target-aura-duration" }
local targetReaperDuration = { token = "target-reaper-duration" }
local playerReaperDuration = { token = "player-reaper-duration" }
local unverifiedMirroredAuraDuration = { token = "unverified-mirrored-aura-duration" }
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
    [434765] = {
        spellId = 439843,
        auraInstanceID = 885,
        isHarmful = true,
        isHelpful = false,
        sourceUnit = "player",
        isFromPlayerOrPlayerPet = true,
        duration = 12,
        applications = 8,
    },
}

local playerAuraBySpellID = {
    [434765] = {
        spellId = 439843,
        auraInstanceID = 435,
        isHarmful = false,
        isHelpful = true,
        sourceUnit = "player",
        isFromPlayerOrPlayerPet = true,
        duration = 30,
        applications = 2,
    },
}

ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" then
        return playerAuraBySpellID[spellID]
    end
    if unit == "target" then
        return auraBySpellID[spellID]
    end
end

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "target" and (auraInstanceID == 9001
        or auraInstanceID == 9002
        or auraInstanceID == 9005
        or auraInstanceID == 9007
        or auraInstanceID == 9008) then
        return auraDuration
    end
    if unit == "target" and auraInstanceID == 9003 then
        return auraDuration
    end
    if unit == "target" and auraInstanceID == 885 then
        return targetReaperDuration
    end
    if unit == "player" and auraInstanceID == 435 then
        return playerReaperDuration
    end
end

ns.CDMSources.QueryAuraApplicationDisplayCount = function(unit, auraInstanceID, minApplications)
    if unit ~= "target" then return nil end
    if auraInstanceID == 9008 then
        return "0"
    end
    local count = auraInstanceID == 9001 and 4
        or auraInstanceID == 9002 and 1
        or auraInstanceID == 9007 and 7
        or auraInstanceID == 885 and 8
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
    if auraInstanceID == 885 then return auraBySpellID[434765] end
    if auraInstanceID == 9007 then
        return {
            spellId = 777005,
            auraInstanceID = 9007,
            isHarmful = true,
            isHelpful = false,
            sourceUnit = "player",
            isFromPlayerOrPlayerPet = true,
            duration = 12,
            applications = 7,
        }
    end
end

ns.CDMBlizzMirror.GetMirroredStateForViewer = function(spellID, viewerType)
    if spellID == 777002 and viewerType == "trackedBar" then
        return {
            isActive = true,
            durObj = unverifiedMirroredAuraDuration,
            selfAura = false,
            cooldownID = 777002,
            stackText = "9",
            stackTextSource = "Applications",
            stackTextShown = true,
        }
    end
    if spellID == 777001 and viewerType == "trackedBar" then
        return {
            auraDurObj = mirroredAuraDuration,
            selfAura = false,
            cooldownID = 777001,
            auraInstanceID = 9001,
            auraUnit = "target",
            stackText = "7",
            stackTextSource = "Applications",
            stackTextShown = true,
        }
    end
    if spellID == 777003 and viewerType == "buff" then
        return {
            auraDurObj = mirroredAuraDuration,
            selfAura = false,
            cooldownID = 777003,
            auraInstanceID = 9004,
            auraUnit = "target",
            stackText = "5",
            stackTextSource = "Applications",
            stackTextShown = true,
        }
    end
    if spellID == 777004 and viewerType == "buff" then
        return {
            auraDurObj = mirroredAuraDuration,
            selfAura = false,
            cooldownID = 777004,
            auraInstanceID = 9006,
            auraUnit = "target",
            stackText = "2",
            stackTextSource = "ChargeCount",
            stackTextShown = false,
            auraStackText = "7",
            auraStackTextSource = "Applications",
            auraStackTextShown = true,
        }
    end
    if spellID == 777005 and viewerType == "buff" then
        return {
            auraDurObj = mirroredTargetAuraDuration,
            selfAura = false,
            cooldownID = 777005,
            auraInstanceID = 9007,
            auraUnit = "target",
        }
    end
    if spellID == 434765 and viewerType == "buff" then
        return {
            selfAura = false,
            cooldownID = 157723,
            spellID = 439843,
            overrideSpellID = 439843,
            overrideTooltipSpellID = 434765,
            linkedSpellIDs = { 434765 },
            auraInstanceID = 885,
            auraUnit = "target",
        }
    end
end

local state = ns.CDMAuraRuntime.ResolveState({
    spellID = 777002,
    entrySpellID = 777002,
    entryID = 777002,
    entryName = "Unverified Mirrored Applications",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "trackedBar",
})

assert(state.isActive ~= true, "target-side mirrored auras without ownership proof should not resolve active")
assert(state.durObj == nil, "target-side mirrored auras without ownership proof should not expose a DurationObject")

state = ns.CDMAuraRuntime.ResolveState({
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

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 777003,
    entrySpellID = 777003,
    entryID = 777003,
    entryName = "Restricted Target Mirror",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "buff",
})

assert(state.isActive == true,
    "stamped target aura mirrors should stay active when live auraData is restricted")
assert(state.durObj == mirroredAuraDuration,
    "restricted stamped target aura mirrors should keep the captured DurationObject")
assert(state.auraUnit == "target",
    "restricted stamped target aura mirrors should keep the stamped target unit")
assert(state.count and state.count.sinkText == "5",
    "restricted stamped target aura mirrors should surface the captured Applications count")

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 777004,
    entrySpellID = 777004,
    entryID = 777004,
    entryName = "Carried Aura Applications",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "buff",
})

assert(state.isActive == true,
    "carried-stack target aura mirrors should resolve active")
assert(state.count and state.count.sinkText == "7",
    "aura runtime should prefer carried Applications text over hidden ChargeCount text")
assert(state.count.source == "Applications",
    "carried aura stack count should keep its Applications source")

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 777005,
    entrySpellID = 777005,
    entryID = 777005,
    entryName = "Mirrored Target Applications",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "buff",
})

assert(state.isActive == true,
    "target aura mirrors should resolve active")
assert(state.durObj == mirroredTargetAuraDuration,
    "target aura mirrors should keep the mirrored DurationObject")
assert(state.count and state.count.sinkText == "7",
    "target aura mirrors should query the C-side Applications display count when no mirror text was captured")
assert(state.count.source == "display-count",
    "target aura mirror fallback count should identify the display-count source")

state = ns.CDMAuraRuntime.ResolveState({
    spellID = 434765,
    entrySpellID = 434765,
    entryID = 434765,
    entryName = "Reaper's Mark",
    entryKind = "aura",
    entryIsAura = true,
    entryType = "spell",
    viewerType = "buff",
})

assert(state.isActive == true,
    "target-side mirror restrictions should still resolve the target aura when mirror duration is absent")
assert(state.auraUnit == "target",
    "target-side mirror restrictions must not fall back to same-spell player auras")
assert(state.auraInstanceID == 885,
    "target-side mirror restrictions should keep the target aura instance")
assert(state.durObj == targetReaperDuration,
    "target-side mirror restrictions should use the target debuff DurationObject")
assert(state.count and state.count.sinkText == "8",
    "target-side mirror restrictions should display the target debuff Applications count")

state = ns.CDMAuraRuntime.ResolveState({
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
