-- tests/unit/cdm_spelldata_aura_cleanup_catalog_gate_test.lua
-- Run: lua tests/unit/cdm_spelldata_aura_cleanup_catalog_gate_test.lua
--
-- Guards the class-aware aura cleanup against false positives during early
-- load. Until the per-character Blizzard CDM catalog has been walked, every
-- aura looks "absent" — so cleanup must be a no-op while the catalog is empty.
-- Without the readiness gate, a fresh login (catalog not yet built) would
-- wrongly shelve every legitimate aura.

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown() return false end
function IsPlayerSpell() return false end
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

local AURA_A = 257284
local AURA_B = 48707

local trackedBarDB = {
    ownedSpells = {
        { type = "spell", id = AURA_A, kind = "aura" },
        { type = "spell", id = AURA_B, kind = "aura" },
    },
    dormantSpells = {},
    removedSpells = {},
}

local ns = {
    Addon = {
        db = {
            profile = { ncdm = { trackedBar = trackedBarDB } },
            global = {},
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
    CDMSources = {
        QueryOverrideSpell = function(spellID) return spellID end,
        QueryBaseSpell = function() return nil end,
    },
    -- Catalog never gets populated: RebuildBlizzardCatalogMaps leaves every
    -- map empty, simulating early load before the mirror has been walked.
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function() end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

ns.CDMSpellData:CheckDormantSpells("trackedBar")

assert(#trackedBarDB.ownedSpells == 2,
    "with an empty CDM catalog, aura cleanup must be a no-op (no false-positive shelving)")
local ids = {}
for _, e in ipairs(trackedBarDB.ownedSpells) do ids[e.id] = true end
assert(ids[AURA_A] and ids[AURA_B], "both auras must remain while the catalog is not ready")
assert(next(trackedBarDB.dormantSpells) == nil, "nothing should be shelved while the catalog is empty")

print("OK: cdm_spelldata_aura_cleanup_catalog_gate_test")
