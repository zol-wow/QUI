-- tests/unit/cdm_aura_runtime_test.lua
-- Run: lua tests/unit/cdm_aura_runtime_test.lua

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_spelldata.lua", "cdm_aura_runtime.lua")("QUI", ns)

local runtime = assert(ns.CDMAuraRuntime, "CDMAuraRuntime table was not exported")

local resolvedParams
local resolvedState = { isActive = true, auraUnit = "player", auraInstanceID = 9001 }
runtime.SetResolver(function(params)
    resolvedParams = params
    return resolvedState
end)

local state = runtime.ResolveState({ spellID = 12345 })
assert(state == resolvedState, "aura runtime should return the registered resolved state")
assert(resolvedParams.spellID == 12345, "aura runtime should pass params to the registered resolver")

runtime.SetApplicationsGetter(function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 9001 then
        return true, "3"
    end
end)
local ok, stacks = runtime.GetApplications("player", 9001)
assert(ok == true and stacks == "3", "aura runtime should delegate application counts")

runtime.SetCapturedAuraGetter(function(ids)
    return ids and ids[1] == 12345 and { auraInstanceID = 9001 } or nil
end)
local captured = runtime.GetCapturedAuraForLookup({ 12345 })
assert(captured and captured.auraInstanceID == 9001,
    "aura runtime should delegate captured aura lookup")

runtime.SetAbilityAuraSpellIDResolver(function(spellID)
    if spellID == 100 then
        return 200, true
    end
    return spellID, false
end)

local mapped, remapped = runtime.ResolveAbilityAuraSpellID(100)
assert(mapped == 200 and remapped == true,
    "aura runtime should delegate ability-to-aura lookup")
assert(runtime.HasAbilityAuraMapping(100) == true,
    "aura runtime should report registered ability-to-aura mappings")
assert(runtime.HasAbilityAuraMapping(101) == false,
    "aura runtime should reject non-remapped ability IDs")

print("OK: cdm_aura_runtime_test")
