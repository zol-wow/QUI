-- tests/unit/cdm_catalog_equipslot_picker_test.lua
-- The built-in Blizzard CDM picker (GetAvailableSpellsForContainer) must emit
-- an item-typed slot entry from the rendered provider category, not the raw
-- EquipSlotEssential source category, and suppress it when owned.
-- Run: lua tests/unit/cdm_catalog_equipslot_picker_test.lua

_G.issecretvalue = function() return false end
_G.C_CooldownViewer = nil

local ns = {}
-- Task 45f: cdm_catalog.lua routes discarded-result pcall guards through
-- ns.SafeCall. Additive stub (T1d/T1e precedent) — bare pcall passthrough.
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
local chunk = loadChunk("QUI_CDM/cdm/cdm_catalog.lua", "cdm_catalog.lua")
chunk("QUI", ns)

ns.CDMSources = {
    QueryInventoryItemID = function(unit, slot)
        assert(unit == "player", "should query player inventory")
        if slot == 13 then return 11111 end
        return nil
    end,
    QueryItemNameByID = function(itemID)
        if itemID == 11111 then return "Test Trinket" end
        return nil
    end,
    QueryItemIconByID = function(itemID)
        if itemID == 11111 then return 222 end
        return nil
    end,
}

_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function()
        error("built-in picker must use the ordered provider category")
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        assert(cooldownID == 701, "unexpected cooldownID")
        return { equipSlot = 13, isKnown = true }
    end,
}
_G.CooldownViewerSettings = {
    GetDataProvider = function()
        return {
            -- memo fields present = cache already built by a secure consumer
            -- (cold-boot taint gate reads these raw; see cdm_index/cdm_catalog)
            displayDataDirty = false,
            displayData = {},
            GetLayoutManager = function() return {} end,
            GetOrderedCooldownIDsForCategory = function(_, category, allowUnlearned)
                assert(category == 0, "essential picker should ask for rendered Essential category")
                assert(allowUnlearned == true, "picker should request unlearned entries")
                return { 701 }
            end,
        }
    end,
}

local catalog = assert(ns.CDMCatalog, "CDMCatalog table was not exported")

-- (a) not owned -> item entry surfaces
local available = catalog.GetAvailableSpellsForContainer("essential", "cooldown", {}, {})
assert(#available == 1, "expected exactly one EquipSlot item entry, got " .. #available)
local e = available[1]
assert(e._entryType == "slot", "item entry must carry _entryType='slot'")
assert(e._entryID == 13, "item entry _entryID must be the equip slot")
assert(e._slotID == 13, "item entry _slotID must be the equip slot")
assert(e.spellID == 13, "item entry display key should be the slot")
assert(e.name == "Test Trinket", "item entry should resolve the equipped item name")
assert(e.icon == 222, "item entry should resolve the equipped item icon")

-- (b) owned (slot:13 already in the set) -> suppressed
local owned = { ["slot:13"] = true, [13] = true }
local available2 = catalog.GetAvailableSpellsForContainer("essential", "cooldown", owned, {})
assert(#available2 == 0, "owned slot entry must be filtered from the picker")

print("OK cdm_catalog_equipslot_picker_test")
