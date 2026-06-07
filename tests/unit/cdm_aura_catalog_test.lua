-- tests/unit/cdm_aura_catalog_test.lua
-- Run: lua tests/unit/cdm_aura_catalog_test.lua

_G.issecretvalue = function()
    return false
end

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_spelldata.lua", "cdm_aura_catalog.lua")("QUI", ns)

local catalog = assert(ns.CDMAuraCatalog, "CDMAuraCatalog table was not exported")

local displayID, remapped = catalog.ResolveEntryAuraDisplay(55090, {
    [55090] = 194310,
})
assert(displayID == 194310, "ability entries should remap to catalog aura display IDs")
assert(remapped == true, "ability->aura remap should be reported")

local mirror = {
    GetDirectCooldownIDForViewer = function(spellID, viewerType)
        if spellID == 55090 and viewerType == "buff" then
            return 7001
        end
    end,
}

displayID, remapped = catalog.ResolveEntryAuraDisplay(55090, {
    [55090] = 194310,
}, mirror)
assert(displayID == 55090, "direct aura children should keep their own display ID")
assert(remapped == false, "direct aura children should not report a remap")

local resolved = {}
catalog.AttachLinkedAuraIDs(resolved, {
    [55090] = { 194310, 194311 },
    [194310] = { 194310, 194312 },
}, nil, 55090, 194310)
assert(#resolved.linkedSpellIDs == 3, "linked aura IDs should be deduped across source IDs")
assert(resolved.linkedSpellIDs[1] == 194310, "first linked aura ID should preserve catalog order")
assert(resolved.linkedSpellIDs[2] == 194311, "second linked aura ID should preserve catalog order")
assert(resolved.linkedSpellIDs[3] == 194312, "third linked aura ID should preserve catalog order")

local callbackResolved = {}
catalog.AttachLinkedAuraIDs(callbackResolved, nil, function(spellID)
    if spellID == 343294 then
        return { 343294 }
    end
end, 343294)
assert(callbackResolved.linkedSpellIDs[1] == 343294,
    "linked aura IDs should be readable from the supplied lookup callback")

print("OK: cdm_aura_catalog_test")
