-- tests/unit/cdm_catalog_learned_aura_family_test.lua
-- Run: lua tests/unit/cdm_catalog_learned_aura_family_test.lua
--
-- The composer/picker catalog intentionally includes unlearned rows. Aura
-- runtime eligibility must instead come from allowUnlearned=false, while
-- accepting every spell identity in a learned aura family.

_G.issecretvalue = function() return false end
_G.C_CooldownViewer = nil

local LEARNED_BASE = 101
local LEARNED_OVERRIDE = 102
local LEARNED_TOOLTIP = 103
local LEARNED_LINKED = 104
local UNLEARNED_FOREIGN = 201
local EQUIP_SPELL = 301

local ns = {
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...)
        return pcall(function(...) return obj[name](obj, ...) end, ...)
    end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...)
        if obj == nil then return nil end
        local ok, method = pcall(function() return obj[name] end)
        if not ok then return false end
        if method == nil then return nil end
        return pcall(method, obj, ...)
    end,
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_catalog.lua", "cdm_catalog.lua")("QUI", ns)

ns.CDMSources = {
    QuerySpellBookClassAffinity = function(spellID)
        return spellID == LEARNED_BASE
            or spellID == LEARNED_OVERRIDE
            or spellID == LEARNED_TOOLTIP
            or spellID == LEARNED_LINKED
    end,
    QuerySpellInfo = function(spellID)
        return { name = "Spell " .. spellID, iconID = spellID }
    end,
    QueryOverrideSpell = function(spellID) return spellID end,
}

local calls = {}
local injectMissingInfo = false
_G.C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category, allowUnlearned)
        calls[#calls + 1] = { category = category, allowUnlearned = allowUnlearned }
        if category == 2 then
            if allowUnlearned then return { 1001, 1002 } end
            return { 1001 }
        elseif category == 3 and injectMissingInfo then
            return { 9999 }
        elseif category == 8 then
            return { 1003 }
        end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 1001 then
            return {
                spellID = LEARNED_BASE,
                overrideSpellID = LEARNED_OVERRIDE,
                overrideTooltipSpellID = LEARNED_TOOLTIP,
                linkedSpellIDs = { LEARNED_LINKED },
                isKnown = true,
            }
        elseif cooldownID == 1002 then
            return {
                spellID = UNLEARNED_FOREIGN,
                linkedSpellIDs = {},
                isKnown = false,
            }
        elseif cooldownID == 1003 then
            return {
                spellID = EQUIP_SPELL,
                equipSlot = 13,
                linkedSpellIDs = {},
                isKnown = true,
            }
        end
        return nil
    end,
}

local catalog = assert(ns.CDMCatalog, "CDMCatalog table was not exported")
local learned = {}
assert(catalog.RebuildAuraLearnedFamilyIDs(learned) == true,
    "a complete current-spec aura walk should report ready")

assert(learned[LEARNED_BASE] == true, "learned aura base ID must be accepted")
assert(learned[LEARNED_OVERRIDE] == true, "learned aura override ID must be accepted")
assert(learned[LEARNED_TOOLTIP] == true, "learned tooltip aura ID must be accepted")
assert(learned[LEARNED_LINKED] == true, "learned linked aura ID must be accepted")
assert(learned[UNLEARNED_FOREIGN] == nil,
    "an unlearned foreign row must not enter the current-spec family")
assert(learned[EQUIP_SPELL] == nil,
    "equipped-item rows must not pollute spell aura dormancy")

assert(#calls == 4, "all rendered aura categories should be queried")
for _, call in ipairs(calls) do
    assert(call.allowUnlearned == false,
        "learned aura membership must always query allowUnlearned=false")
end

calls = {}
local applicable = {}
assert(catalog.RebuildClassApplicableSpellIDs(applicable) == true,
    "a complete current-class catalog walk should report ready")
assert(applicable[LEARNED_BASE] == true
        and applicable[LEARNED_OVERRIDE] == true
        and applicable[LEARNED_TOOLTIP] == true
        and applicable[LEARNED_LINKED] == true,
    "every identity in a current-class spell family should remain applicable")
assert(applicable[UNLEARNED_FOREIGN] == nil,
    "an unlearned foreign-class family must be excluded entirely")
assert(#calls == 8, "all rendered CDM categories should be checked for class applicability")
for _, call in ipairs(calls) do
    assert(call.allowUnlearned == true,
        "class applicability must include same-class future/off-spec rows")
end

local available = catalog.GetAvailableSpellsForContainer("customAura", "aura", {}, {})
local availableByID = {}
for _, entry in ipairs(available) do availableByID[entry.spellID] = true end
assert(availableByID[LEARNED_TOOLTIP] == true,
    "the current-class aura family should remain available in Composer")
assert(availableByID[UNLEARNED_FOREIGN] == nil,
    "foreign-class rows must not appear in the Composer add catalog")

injectMissingInfo = true
assert(catalog.RebuildAuraLearnedFamilyIDs({}) == false,
    "a partial cooldown-info read must not report the learned aura catalog ready")

print("OK: cdm_catalog_learned_aura_family_test")
