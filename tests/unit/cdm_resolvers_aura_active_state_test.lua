-- tests/unit/cdm_resolvers_aura_active_state_test.lua
-- Run: lua tests/unit/cdm_resolvers_aura_active_state_test.lua

local function noop() end

function InCombatLockdown() return false end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local capturedLookupIDs
local capturedLookupName
local queriedSpellIDs = {}
local opaqueAuraPresence = {}

local ns = {
    Helpers = {},
    CDMSources = {
        QueryUnitAuraBySpellID = function(_, spellID)
            queriedSpellIDs[#queriedSpellIDs + 1] = spellID
            if spellID == 20002 then
                return { auraInstanceID = 9002 }
            end
            if spellID == 10003 then
                return opaqueAuraPresence
            end
            return nil
        end,
        QueryPlayerAuraBySpellID = function() return nil end,
    },
    CDMSpellData = {
        GetCapturedAuraForLookup = function(ids, name)
            capturedLookupIDs = ids
            capturedLookupName = name
            return { unit = "pet", auraInstanceID = 9001 }
        end,
        GetAuraIDsForSpell = function(_, spellID)
            if spellID == 10001 then
                return { 20001 }
            elseif spellID == 10002 then
                return { 20002 }
            end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers should be exported")
local resolve = assert(resolvers.ResolveAuraActiveState, "ResolveAuraActiveState should be exported")

local active, unit, instanceID = resolve({
    spellID = 10001,
    id = 10001,
    name = "Mapped Aura",
})

assert(active == true, "captured aura lookup should mark the entry active")
assert(unit == "pet", "captured aura lookup should preserve the captured unit")
assert(instanceID == 9001, "captured aura lookup should preserve auraInstanceID")
assert(capturedLookupName == "Mapped Aura", "captured lookup should receive entry name")
assert(capturedLookupIDs[1] == 10001, "captured lookup should include entry spellID")
assert(capturedLookupIDs[2] == 20001, "captured lookup should include mapped aura ID")

ns.CDMSpellData.GetCapturedAuraForLookup = nil

active, unit, instanceID = resolve({
    spellID = 10002,
    id = 10002,
    name = "Direct Aura",
})

assert(active == false, "un-captured mapped aura must not use a direct spell getter")
assert(unit == nil and instanceID == nil, "direct aura getter results are removed")
assert(#queriedSpellIDs == 0, "aura resolution must not query spell getters")

active, unit, instanceID = resolve({
    spellID = 10003,
    id = 10003,
    name = "Opaque Aura",
})

assert(active == false, "uncaptured opaque presence must not be queried")
assert(unit == nil and instanceID == nil, "uncaptured aura has no native identity")

print("OK: cdm_resolvers_aura_active_state_test")
