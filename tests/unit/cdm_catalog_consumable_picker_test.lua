-- tests/unit/cdm_catalog_consumable_picker_test.lua
-- The built-in picker emits a consumable entry for a rendered spellCategoryID
-- cooldown (equipSlot nil).
-- Run: lua tests/unit/cdm_catalog_consumable_picker_test.lua
_G.issecretvalue = function() return false end
_G.C_CooldownViewer = nil

local ns = {}
-- Task 45f: cdm_catalog.lua routes discarded-result pcall guards through
-- ns.SafeCall. Additive stub (T1d/T1e precedent) — bare pcall passthrough.
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_catalog.lua", "cdm_catalog.lua")("QUI", ns)
ns.CDMSources = {}

_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function()
        error("built-in picker must use the ordered provider category")
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        assert(cooldownID == 701, "unexpected cooldownID")
        return { spellCategoryID = 4, isKnown = true }  -- combat potion, no equipSlot, no spellID
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
                assert(allowUnlearned == true, "picker requests unlearned")
                return { 701 }
            end,
        }
    end,
}

local catalog = assert(ns.CDMCatalog, "CDMCatalog not exported")
local available = catalog.GetAvailableSpellsForContainer("essential", "cooldown", {}, {})
assert(#available == 1, "expected one consumable entry, got " .. #available)
local e = available[1]
assert(e._entryType == "consumable", "must be _entryType='consumable'")
assert(e._entryID == 4, "_entryID must be the spellCategoryID")
assert(e.spellID == 4, "display key is the category id")
assert(e.name == "Combat Potion", "name from the meta table (no ns.L in test -> English)")

-- dedup by consumable key
local owned = { ["consumable:4"] = true }
local available2 = catalog.GetAvailableSpellsForContainer("essential", "cooldown", owned, {})
assert(#available2 == 0, "owned consumable filtered")

print("OK cdm_catalog_consumable_picker_test")
