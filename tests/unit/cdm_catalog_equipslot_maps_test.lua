-- tests/unit/cdm_catalog_equipslot_maps_test.lua
-- RebuildBlizzardCatalogMaps must reach the EquipSlotTracked (cat 8) category
-- and treat it as an aura category, mapping a trinket proc aura to its cooldownID.
-- Run: lua tests/unit/cdm_catalog_equipslot_maps_test.lua

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

ns.CDMSources = {}

_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category, allowUnlearned)
        assert(allowUnlearned == true, "maps should request unlearned entries")
        if category == 8 then return { 801 } end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        assert(cooldownID == 801, "unexpected cooldownID")
        return {
            spellID = 500,                 -- trinket on-use spell
            overrideTooltipSpellID = 555,  -- proc aura
            linkedSpellIDs = { 555 },
            equipSlot = 14,
            isKnown = true,
        }
    end,
}

local catalog = assert(ns.CDMCatalog, "CDMCatalog table was not exported")

local spellToCDID, inCooldowns, inAuras, abilityToAura, auraIDsForSpell =
    {}, {}, {}, {}, {}
local ok = catalog.RebuildBlizzardCatalogMaps(
    spellToCDID, inCooldowns, inAuras, abilityToAura, auraIDsForSpell)

assert(ok == true, "RebuildBlizzardCatalogMaps should succeed")
assert(abilityToAura[500] == 555,
    "cat-8 trinket on-use spell should map to its proc aura (loop must reach cat 8)")
assert(inAuras[555] == true,
    "cat-8 proc aura must land in the aura family set (isAura must include 8)")
assert(inAuras[500] == true,
    "cat-8 on-use spell must be classified as aura family, not cooldown")
assert(inCooldowns[500] == nil,
    "cat-8 entry must NOT be added to the cooldown family set")

print("OK cdm_catalog_equipslot_maps_test")
