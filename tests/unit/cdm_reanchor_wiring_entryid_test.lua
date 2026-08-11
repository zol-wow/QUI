-- tests/unit/cdm_reanchor_wiring_entryid_test.lua
-- Run: lua tests/unit/cdm_reanchor_wiring_entryid_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
local W = assert(ns.CDMReanchorWiring)

-- stub index: only 555 and 777 have cooldownIDs; 0 is not usable
local index = {
    IsUsableID = function(id) return type(id) == "number" and id > 0 end,
    Get = function(id)
        if id == 555 then return { cooldownID = 5005, category = 0 } end
        if id == 777 then return { cooldownID = 7007, category = 2 } end
        return nil
    end,
}
local wiring = W.New({ index = index })

-- overrideSpellID preferred over spellID
assert(wiring:ResolveEntryCooldownID({ overrideSpellID = 555, spellID = 777 }) == 5005, "override wins")
-- falls through to spellID then id
assert(wiring:ResolveEntryCooldownID({ overrideSpellID = 0, spellID = 777 }) == 7007, "spellID used when override unusable")
assert(wiring:ResolveEntryCooldownID({ id = 555 }) == 5005, "id fallback")
-- linkedSpellIDs scanned last
assert(wiring:ResolveEntryCooldownID({ spellID = 999, linkedSpellIDs = { 999, 777 } }) == 7007, "linked scanned")
-- nothing matches -> nil
assert(wiring:ResolveEntryCooldownID({ spellID = 12345 }) == nil, "no match -> nil")
-- no index -> nil
assert(W.New({}):ResolveEntryCooldownID({ spellID = 555 }) == nil, "no index -> nil")
-- override hook honored
assert(W.New({ resolveEntryCooldownID = function() return 42 end }):ResolveEntryCooldownID({}) == 42, "override hook")

print("OK: cdm_reanchor_wiring_entryid_test")
