-- tests/unit/cdm_spelldata_aura_cleanup_partial_catalog_test.lua
-- Run: lua tests/unit/cdm_spelldata_aura_cleanup_partial_catalog_test.lua
--
-- Guards built-in aura cleanup against a partially populated Blizzard CDM
-- catalog during fresh login. Cooldown categories can become visible before
-- aura categories; that must not make aura cleanup treat every tracked aura
-- as foreign.

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

local AURA_ID = 395152
local COOLDOWN_ONLY_ID = 403631

local trackedBarDB = {
    ownedSpells = {
        { type = "spell", id = AURA_ID, kind = "aura" },
    },
    dormantSpells = {},
    removedSpells = {},
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    trackedBar = trackedBarDB,
                },
            },
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
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(spellToCD, inCooldowns, _inAuras)
            spellToCD[COOLDOWN_ONLY_ID] = 7001
            inCooldowns[COOLDOWN_ONLY_ID] = true
        end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

ns.CDMSpellData:CheckDormantSpells("trackedBar")

assert(#trackedBarDB.ownedSpells == 1,
    "partial cooldown-only CDM catalog must not shelve built-in aura entries")
assert(trackedBarDB.ownedSpells[1].id == AURA_ID,
    "tracked aura should remain active until the aura CDM catalog is ready")
assert(next(trackedBarDB.dormantSpells) == nil,
    "partial cooldown-only CDM catalog must not create dormant aura entries")

print("OK: cdm_spelldata_aura_cleanup_partial_catalog_test")
