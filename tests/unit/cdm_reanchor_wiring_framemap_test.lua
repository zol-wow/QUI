-- tests/unit/cdm_reanchor_wiring_framemap_test.lua
-- Run: lua tests/unit/cdm_reanchor_wiring_framemap_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
local W = assert(ns.CDMReanchorWiring)

local f1, f2, fNil, fSpell = { n = 1 }, { n = 2 }, { n = 3 }, { n = 4 }
fSpell.GetSpellID = function() return 204 end
-- stub bridge: enumerate returns four frames; identity maps f1->101, f2->102, fNil/fSpell->nil
local bridge = {
    EnumerateItems = function(_, viewer) return viewer.items end,
    ResolveIdentity = function(_, frame)
        if frame == f1 then return 101 end
        if frame == f2 then return 102 end
        return nil
    end,
    GetFrameCooldownInfo = function(_, frame)
        if frame == fNil then
            return {
                spellID = 103,
                overrideSpellID = 104,
                linkedSpellIDs = { 105 },
                equipSlot = 13,
                spellCategoryID = 4,
            }
        end
        return nil
    end,
}
local index = {
    ToBaseSpellID = function(id)
        if type(id) == "number" and id > 0 then return id end
        return nil
    end,
    ForEachCooldownInfoID = function(info, callback)
        callback(info.overrideTooltipSpellID)
        callback(info.overrideSpellID)
        callback(info.spellID)
        if info.linkedSpellIDs then
            for i = 1, #info.linkedSpellIDs do
                callback(info.linkedSpellIDs[i])
            end
        end
    end,
}
local wiring = W.New({ bridge = bridge, index = index })
local viewer = { items = { f1, fNil, f2, fSpell } }
local map, items = wiring:BuildFrameMap(viewer)

assert(map[101] == f1, "cooldownID 101 -> f1")
assert(map[102] == f2, "cooldownID 102 -> f2")
local count = 0
for key in pairs(map) do
    if type(key) == "number" then count = count + 1 end
end
assert(count == 2, "frame with nil identity is skipped")
assert(map._bySpell[103] == fNil and map._bySpell[104] == fNil and map._bySpell[105] == fNil,
    "frame cooldownInfo aliases are indexed by spell IDs")
assert(map._bySpell[204] == fSpell, "frame:GetSpellID fallback is indexed by spell ID")
assert(map._byEquipSlot[13] == fNil, "frame cooldownInfo equipSlot is indexed")
assert(map._bySpellCategory[4] == fNil, "frame cooldownInfo spellCategoryID is indexed")
-- second return = raw ordered item list, INCLUDING the nil-identity frame (needed for sinking)
assert(#items == 4 and items[1] == f1 and items[2] == fNil and items[3] == f2 and items[4] == fSpell,
    "BuildFrameMap returns the full ordered item list as its 2nd value")
local nilMap, nilItems = wiring:BuildFrameMap(nil)
assert(#nilItems == 0 and next(nilMap._bySpell) == nil and next(nilMap._byEquipSlot) == nil
    and next(nilMap._bySpellCategory) == nil, "nil viewer -> empty maps + empty items")

print("OK: cdm_reanchor_wiring_framemap_test")
