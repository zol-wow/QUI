-- tests/unit/cdm_catalog_target_aura_map_test.lua
-- Run: lua tests/unit/cdm_catalog_target_aura_map_test.lua

local infos = {
    [1001] = {
        spellID = 55090,
        overrideSpellID = 55090,
        overrideTooltipSpellID = 194310,
        linkedSpellIDs = { 55090 },
        hasAura = false,
        selfAura = false,
    },
}

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 2 then
            return { 1001 }
        end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        return infos[cooldownID]
    end,
}

local ns = {}
-- Task 45f: cdm_catalog.lua routes discarded-result pcall guards through
-- ns.SafeCall. Additive stub (T1d/T1e precedent) — bare pcall passthrough.
ns.SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end
ns.SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end
ns.SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_catalog.lua", "cdm_catalog.lua")("QUI", ns)

local spellToCDID = {}
local inCooldowns = {}
local inAuras = {}
local abilityToAura = {}
local auraIDsForSpell = {}

local ok = ns.CDMCatalog.RebuildBlizzardCatalogMaps(
    spellToCDID, inCooldowns, inAuras, abilityToAura, auraIDsForSpell)

assert(ok == true, "catalog rebuild should succeed")
assert(inAuras[55090] == true, "linked ability should still be indexed in the aura family")
assert(abilityToAura[55090] == 194310, "linked ability should map to the target aura display ID")
assert(type(auraIDsForSpell[55090]) == "table", "target-side aura entries should provide aura IDs for linked abilities")
assert(auraIDsForSpell[55090][1] == 194310, "Scourge Strike should resolve stacks from Festering Wound")

print("OK: cdm_catalog_target_aura_map_test")
