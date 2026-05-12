-- tests/cdm_catalog_target_aura_map_test.lua
-- Run: lua tests/cdm_catalog_target_aura_map_test.lua

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
assert(loadfile("modules/cdm/cdm_catalog.lua"))("QUI", ns)

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
