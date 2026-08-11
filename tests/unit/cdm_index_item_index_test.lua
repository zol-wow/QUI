-- tests/unit/cdm_index_item_index_test.lua
-- Item-only cooldowns (equipSlot / spellCategoryID, no spellID) must be indexed
-- and retrievable by GetByEquipSlot / GetByCategory.
-- Run: lua tests/unit/cdm_index_item_index_test.lua

_G.wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end end
_G.issecretvalue = function() return false end

_G.Enum = {
    CooldownViewerCategory = {
        Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3,
        SpecAgnosticEssential = 5, SpecAgnosticTracked = 6,
        EquipSlotEssential = 7, EquipSlotTracked = 8,
    },
}
_G.C_CooldownViewer = nil
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
_G.EventRegistry = { RegisterCallback = function() end }

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_index.lua", "cdm_index.lua")("QUI", ns)
ns.CDMSources = { QueryBaseSpell = function(s) return s end }

_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category, includeHidden)
        assert(includeHidden == true, "index should request hidden entries")
        if category == 7 then return { 701 } end  -- EquipSlotEssential: a trinket, no spellID
        if category == 8 then return { 801 } end  -- EquipSlotTracked: a consumable, no spellID
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 701 then return { equipSlot = 13 } end          -- trinket, no spellID
        if cooldownID == 801 then return { spellCategoryID = 4 } end     -- combat potion, no spellID
        error("unexpected cooldownID " .. tostring(cooldownID))
    end,
}

local index = assert(ns.CDMIndex, "CDMIndex not exported")
index.Rebuild()

local bySlot = index.GetByEquipSlot(13)
assert(bySlot, "equipSlot-only cooldown must be indexed by GetByEquipSlot")
assert(bySlot.cooldownID == 701, "wrong cooldownID for equipSlot 13")

local byCat = index.GetByCategory(4)
assert(byCat, "spellCategoryID-only cooldown must be indexed by GetByCategory")
assert(byCat.cooldownID == 801, "wrong cooldownID for spellCategoryID 4")

local orderedCalls = 0
_G.CooldownViewerSettings = {
    GetDataProvider = function()
        return {
            -- memo fields present = cache already built by a secure consumer
            -- (cold-boot taint gate reads these raw; see cdm_index/cdm_catalog)
            displayDataDirty = false,
            displayData = {},
            GetOrderedCooldownIDsForCategory = function(_, category, includeHidden)
                orderedCalls = orderedCalls + 1
                assert(includeHidden == true, "ordered item map should include hidden provider rows")
                if category == 0 then return { 701 } end
                if category == 3 then return { 801 } end
                return {}
            end,
        }
    end,
}

local orderedSlot = assert(index.GetOrderedByEquipSlot(13),
    "rendered equipSlot cooldown must be indexed by ordered slot map")
assert(orderedSlot.cooldownID == 701, "wrong ordered cooldownID for equipSlot 13")
assert(orderedSlot.category == 0, "ordered equipSlot category should be the rendered category")

local orderedCat = assert(index.GetOrderedByCategory(4),
    "rendered spellCategoryID cooldown must be indexed by ordered category map")
assert(orderedCat.cooldownID == 801, "wrong ordered cooldownID for spellCategoryID 4")
assert(orderedCat.category == 3, "ordered consumable category should be the rendered category")

local callsAfterFirst = orderedCalls
assert(index.GetOrderedByEquipSlot(13) == orderedSlot,
    "ordered equipSlot map should be cached by index version")
assert(orderedCalls == callsAfterFirst,
    "cached ordered item map should not re-walk provider")

index.Notify("manual")
local rebuiltSlot = assert(index.GetOrderedByEquipSlot(13),
    "ordered equipSlot map should rebuild after invalidation")
assert(rebuiltSlot ~= orderedSlot, "ordered equipSlot entry should rebuild after index invalidation")
assert(orderedCalls > callsAfterFirst, "ordered item map rebuild should re-walk provider")

assert(index.GetByEquipSlot(99) == nil, "unknown equipSlot -> nil")
assert(index.GetByCategory(99) == nil, "unknown category -> nil")
assert(index.GetByEquipSlot("x") == nil, "non-number equipSlot -> nil")

print("OK cdm_index_item_index_test")
