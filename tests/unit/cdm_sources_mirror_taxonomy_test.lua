-- tests/unit/cdm_sources_mirror_taxonomy_test.lua
-- Run: lua tests/unit/cdm_sources_mirror_taxonomy_test.lua

local mirroredViewerType
local findCooldownCalls = 0

local ns = {
    CDMShared = {
        IsCooldownMirrorCategory = function(category)
            return category == "aliasCooldown"
        end,
    },
    CDMBlizzMirror = {
        GetMirroredStateForViewer = function(spellID, viewerType)
            mirroredViewerType = viewerType
            return { spellID = spellID, viewerType = viewerType }
        end,
        FindCooldownState = function()
            findCooldownCalls = findCooldownCalls + 1
            return { fallback = true }
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_sources.lua", "cdm_sources.lua")("QUI", ns)

local state = ns.CDMSources.QueryMirroredCooldownState(12345, "aliasCooldown")
assert(state and state.spellID == 12345, "cooldown mirror categories should use exact viewer lookup")
assert(mirroredViewerType == "aliasCooldown", "exact viewer lookup should preserve the viewer key")
assert(findCooldownCalls == 0, "exact cooldown viewer lookup should not fall back to broad search")

state = ns.CDMSources.QueryMirroredCooldownState(12345, "aliasAura")
assert(state and state.fallback == true, "non-cooldown mirror categories should use broad search")
assert(findCooldownCalls == 1, "broad search should run once for non-cooldown categories")

print("OK: cdm_sources_mirror_taxonomy_test")
