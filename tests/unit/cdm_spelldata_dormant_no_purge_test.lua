-- tests/unit/cdm_spelldata_dormant_no_purge_test.lua
-- Run: lua tests/unit/cdm_spelldata_dormant_no_purge_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_ClassTalents
--
-- Regression: CheckDormantSpells Phase 3 permanently deleted dormant
-- records absent from a Blizzard-CDM-catalog + spellbook scan. Both
-- sources can be incomplete at reconcile time (login races, viewer info
-- documented MayReturnNothing), so a shelved talent spell could be purged
-- with no recovery path — the user's tracked spell silently vanished.
-- Dormant records are user config: they must survive every reconcile until
-- the spell tests known again (Phase 2) or the user removes them manually.

local function noop() end

local knownSpells = {}

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown(spellID) return knownSpells[spellID] == true end
function IsPlayerSpell(spellID) return knownSpells[spellID] == true end
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

-- Talent data fully loaded — the Phase 1 gate is open; this test targets
-- the purge path, not the shelving gate.
C_ClassTalents = {
    GetActiveConfigID = function() return 777 end,
}

local QUELL = 351338

local customBarDB = {
    builtIn = false,
    containerType = "customBar",
    shape = "icon",
    entries = {},
    dormantSpells = {
        [QUELL] = { slot = 1, row = 1, kind = "cooldown", seq = 1 },
    },
    removedSpells = {},
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    containers = {
                        quell_bar = customBarDB,
                    },
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
    -- Non-empty catalog scan that does NOT contain QUELL: this is exactly
    -- the partial-data shape that used to pass the next(allCDMSpells)
    -- guard and trigger the permanent purge.
    CDMComposer = {
        CollectKnownCDMSpellIDs = function(out)
            out[99999] = true
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

-- A full (non-restoreOnly) reconcile with a non-empty scan missing the
-- dormant spell must NOT delete the dormant record.
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(type(customBarDB.dormantSpells[QUELL]) == "table",
    "a dormant record must survive a reconcile whose catalog/spellbook scan does not list it")

-- Run several more times: still there (no purge phase at all).
ns.CDMSpellData:CheckDormantSpells("quell_bar")
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(type(customBarDB.dormantSpells[QUELL]) == "table",
    "dormant records must survive repeated reconciles")

-- When the spell finally tests known, Phase 2 restores it — proving the
-- record stayed usable the whole time.
knownSpells[QUELL] = true
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 1 and customBarDB.entries[1].id == QUELL,
    "the surviving dormant record must restore once the spell tests known")
assert(next(customBarDB.dormantSpells) == nil,
    "restore must clear the dormant record")

print("OK: cdm_spelldata_dormant_no_purge_test")
