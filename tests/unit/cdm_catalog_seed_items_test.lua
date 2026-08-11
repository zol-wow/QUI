-- tests/unit/cdm_catalog_seed_items_test.lua
-- SeedFromBlizzard ("Reset to Blizzard Defaults") must item-type categorized
-- trinkets (equipSlot) and consumables (spellCategoryID), not emit them as spells.
-- Run: lua tests/unit/cdm_catalog_seed_items_test.lua

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

ns.CDMSources = {
    -- spell entry 5000 must look learned so SelectPersistentSpellID keeps it
    QueryIsSpellKnownOrPlayerSpell = function(id) return id == 5000 end,
}

-- essential container -> category 0. Provide a tracked set via the data provider
-- (GetTrackedCategorySet prefers CooldownViewerSettings:GetDataProvider) with a
-- trinket (equipSlot), a consumable (spellCategoryID), and a plain spell.
_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category, allow) return {} end,
    GetCooldownViewerCooldownInfo = function(cdID)
        if cdID == 11 then return { equipSlot = 13 } end
        if cdID == 12 then return { spellCategoryID = 4 } end
        if cdID == 13 then return { spellID = 5000 } end
        error("unexpected cdID " .. tostring(cdID))
    end,
}
_G.CooldownViewerSettings = {
    GetDataProvider = function()
        return {
            -- memo fields present = cache already built by a secure consumer
            -- (cold-boot taint gate reads these raw; see cdm_index/cdm_catalog)
            displayDataDirty = false,
            displayData = {},
            GetLayoutManager = function() return { IsLoaded = function() return true end } end,
            GetOrderedCooldownIDsForCategory = function(_, category, allow)
                assert(category == 0, "essential -> category 0")
                return { 11, 12, 13 }
            end,
        }
    end,
}

local catalog = assert(ns.CDMCatalog, "CDMCatalog not exported")
local entries, ready = catalog.SeedFromBlizzard("essential")

assert(ready == true, "seed should report ready")
assert(#entries == 3, "expected 3 entries, got " .. #entries)

local byType = {}
for _, e in ipairs(entries) do byType[e.type] = e end

assert(byType.slot, "a slot (trinket) entry must be emitted")
assert(byType.slot.id == 13, "slot entry id == equipSlot 13")
assert(byType.consumable, "a consumable entry must be emitted")
assert(byType.consumable.id == 4, "consumable entry id == spellCategoryID 4")
assert(byType.spell, "the plain spell entry must still be emitted")
assert(byType.spell.id == 5000, "spell entry id == 5000")
for _, e in ipairs(entries) do
    assert(e.source == "blizzardCDM", "every seeded entry keeps the blizzardCDM source")
end

print("OK cdm_catalog_seed_items_test")
