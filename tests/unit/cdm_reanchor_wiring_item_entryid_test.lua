-- tests/unit/cdm_reanchor_wiring_item_entryid_test.lua
-- ResolveEntryCooldownID resolves item entries type-first (by equipSlot / category),
-- NOT via the generic spellID path. Run: lua tests/unit/cdm_reanchor_wiring_item_entryid_test.lua
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_wiring.lua", "cdm_reanchor_wiring.lua")("QUI", ns)
local W = assert(ns.CDMReanchorWiring)

local index = {
    IsUsableID = function(id) return type(id) == "number" and id > 0 end,
    Get = function(id)
        -- generic spell path: pretend 13 IS a real spell with a cooldownID,
        -- to prove the slot branch does NOT fall through to it.
        if id == 13 then return { cooldownID = 9999 } end
        return nil
    end,
    GetOrderedByEquipSlot = function(slot)
        if slot == 13 then return { cooldownID = 1302 } end
        return nil
    end,
    GetByEquipSlot = function(slot)
        if slot == 13 then return { cooldownID = 1301 } end
        if slot == 15 then return { cooldownID = 1501 } end
        return nil
    end,
    GetOrderedByCategory = function(cat)
        if cat == 4 then return { cooldownID = 405 } end
        return nil
    end,
    GetByCategory = function(cat)
        if cat == 4 then return { cooldownID = 404 } end
        if cat == 30 then return { cooldownID = 3001 } end
        return nil
    end,
}
local wiring = W.New({ index = index })

-- slot entry resolves via ordered rendered map, NOT broad GetByEquipSlot and
-- NOT the generic Get(13)=9999 spell path.
assert(wiring:ResolveEntryCooldownID({ type = "slot", id = 13 }) == 1302, "slot -> GetOrderedByEquipSlot")
assert(wiring:ResolveEntryCooldownID({ type = "trinket", id = 13 }) == 1302, "trinket -> GetOrderedByEquipSlot")
assert(wiring:ResolveEntryCooldownID({ type = "slot", id = 15 }) == 1501, "slot falls back to GetByEquipSlot")
-- consumable resolves via ordered rendered category before broad category index.
assert(wiring:ResolveEntryCooldownID({ type = "consumable", id = 4 }) == 405, "consumable -> GetOrderedByCategory")
assert(wiring:ResolveEntryCooldownID({ type = "consumable", id = 30 }) == 3001, "consumable falls back to GetByCategory")
-- unknown item identity -> nil (does NOT fall through to generic path)
assert(wiring:ResolveEntryCooldownID({ type = "slot", id = 14 }) == nil, "unknown slot -> nil")
assert(wiring:ResolveEntryCooldownID({ type = "consumable", id = 31 }) == nil, "unknown consumable -> nil")
-- spell entries still use the generic path
assert(wiring:ResolveEntryCooldownID({ spellID = 13 }) == 9999, "spell entry still uses generic Get")

print("OK cdm_reanchor_wiring_item_entryid_test")
