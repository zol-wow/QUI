-- tests/unit/cdm_spelldata_ignores_learned_cast_to_aura_test.lua
-- Run: lua tests/unit/cdm_spelldata_ignores_learned_cast_to_aura_test.lua

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

local ns = {
    Addon = {
        db = {
            global = {
                cdmLearnedCastToAura = {
                    [77575] = { 48707 },
                },
            },
        },
    },
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {},
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(_, _, _, _, auraIDsForSpell)
            auraIDsForSpell[77575] = { 1240996, 191587 }
            return true
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local ids = ns.CDMSpellData:GetAuraIDsForSpell(77575)
assert(type(ids) == "table", "Outbreak should still use catalog aura spell IDs")

local seen = {}
for _, id in ipairs(ids) do
    seen[id] = true
end

assert(seen[1240996] == true, "catalog aura spell ID should remain")
assert(seen[191587] == true, "catalog aura spell ID should remain")
assert(seen[48707] ~= true, "deprecated learned cast-to-aura data must not pollute aura links")
assert(ns.Addon.db.global.cdmLearnedCastToAura == nil, "deprecated learned cast-to-aura SV must be cleared")

print("OK: cdm_spelldata_ignores_learned_cast_to_aura_test")
