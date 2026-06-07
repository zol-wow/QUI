-- tests/unit/cdm_spelldata_dormant_foldback_test.lua
-- Run: lua tests/unit/cdm_spelldata_dormant_foldback_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame UnitClass GetSpecialization GetSpecializationInfo
--
-- The dormant shelf no longer stores anything new, but records stranded by
-- the old shelving model (or resurrected from old saved spec/loadout
-- profiles) must be recovered: CheckDormantSpells folds every record back
-- into the container's live list at its saved slot — unconditionally, even
-- while the spell tests unknown (render-time filters own visibility) —
-- then clears the shelf. Records for spells the user already re-added are
-- dropped instead of duplicated. All historical shelf shapes must fold:
-- the legacy array of spellIDs, the spellID→slot number map, and the
-- spellID→{slot,row,kind,seq} map. Builtin containers that haven't
-- snapshotted ownedSpells yet keep their shelf untouched (creating the
-- list would suppress SnapshotBlizzardCDM); specSpecific custom
-- containers fold into the current spec's list, not the legacy shared
-- field.

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
function UnitClass() return "Evoker", "EVOKER" end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 1467 end

local QUELL = 351338
local FIRE_BREATH = 357208
local HOVER = 358267
local LANDSLIDE = 358385

local customBarDB = {
    builtIn = false,
    containerType = "customBar",
    shape = "icon",
    entries = { { type = "spell", id = FIRE_BREATH, kind = "cooldown", row = 1 } },
    -- QUELL stranded by the old shelving model at slot 1; HOVER as a
    -- legacy number-format record; FIRE_BREATH stale (already re-added).
    dormantSpells = {
        [QUELL] = { slot = 1, row = 2, kind = "cooldown", seq = 5 },
        [HOVER] = 3,
        [FIRE_BREATH] = { slot = 2, kind = "cooldown", seq = 9 },
    },
    _dormantSequence = 9,
    removedSpells = {},
}

local arrayBarDB = {
    builtIn = false,
    containerType = "customBar",
    shape = "icon",
    entries = {},
    -- Oldest historical shape: plain array of spellIDs.
    dormantSpells = { LANDSLIDE, HOVER },
    removedSpells = {},
}

local essentialDB = {
    builtIn = true,
    ownedSpells = nil,  -- not snapshotted yet
    dormantSpells = { [QUELL] = { slot = 1, kind = "cooldown", seq = 1 } },
    removedSpells = {},
}

local specBarDB = {
    builtIn = false,
    containerType = "customBar",
    shape = "icon",
    specSpecific = true,
    entries = {},
    dormantSpells = { [QUELL] = { slot = 1, kind = "cooldown", seq = 1 } },
    removedSpells = {},
}

local specList = { { type = "spell", id = FIRE_BREATH, kind = "cooldown" } }

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    essential = essentialDB,
                    containers = {
                        quell_bar = customBarDB,
                        array_bar = arrayBarDB,
                        spec_bar = specBarDB,
                    },
                },
            },
            global = {
                ncdm = {
                    specTrackerSpells = {
                        spec_bar = {
                            ["EVOKER-1467"] = specList,
                        },
                    },
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
    CDMSources = {
        QueryOverrideSpell = function(spellID) return spellID end,
        QueryBaseSpell = function() return nil end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

-- Case 1: map-format shelf folds back at saved slots, unknown or not.
-- Shelf: QUELL slot 1, HOVER slot 3, FIRE_BREATH stale duplicate.
-- List before: { FIRE_BREATH }. Expected after: QUELL inserted at 1,
-- HOVER appended at min(3, #list+1) = 3, no FIRE_BREATH duplicate.
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 3, "both stranded records must fold back")
assert(customBarDB.entries[1].id == QUELL, "record must return to its saved slot")
assert(customBarDB.entries[1].row == 2, "saved row assignment must be restored")
assert(customBarDB.entries[2].id == FIRE_BREATH, "existing entries keep their order")
assert(customBarDB.entries[3].id == HOVER, "legacy number-format record must fold")
assert(next(customBarDB.dormantSpells) == nil, "shelf must be emptied after folding")
assert(customBarDB._dormantSequence == nil, "dormant sequence counter must be cleared")
local quellCount = 0
for _, entry in ipairs(customBarDB.entries) do
    if entry.id == FIRE_BREATH then quellCount = quellCount + 1 end
end
assert(quellCount == 1, "a stale record for a re-added spell must not duplicate")

-- Folding is idempotent: a second pass changes nothing.
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 3, "second fold pass must be a no-op")

-- Case 2: legacy array-format shelf folds (appended; no saved slots).
ns.CDMSpellData:CheckDormantSpells("array_bar")
assert(#arrayBarDB.entries == 2, "array-format shelf must fold back")
assert(next(arrayBarDB.dormantSpells) == nil, "array shelf must be emptied")

-- Case 3: builtin with no ownedSpells snapshot — shelf must be left
-- intact (no list creation), then fold once the snapshot exists.
ns.CDMSpellData:CheckDormantSpells("essential")
assert(essentialDB.ownedSpells == nil,
    "fold-back must not create ownedSpells on an unsnapshotted builtin")
assert(essentialDB.dormantSpells[QUELL] ~= nil,
    "shelf must survive until the builtin list exists")

essentialDB.ownedSpells = { { type = "spell", id = FIRE_BREATH, kind = "cooldown" } }
ns.CDMSpellData:CheckDormantSpells("essential")
assert(#essentialDB.ownedSpells == 2, "shelf must fold once the list exists")
assert(essentialDB.ownedSpells[1].id == QUELL, "record returns to its saved slot")
assert(next(essentialDB.dormantSpells) == nil, "builtin shelf must be emptied")

-- Case 4: specSpecific custom container — the record must fold into the
-- CURRENT spec's list (what the renderer reads), not the legacy shared
-- entries field, or the recovery is invisible.
ns.CDMSpellData:CheckDormantSpells("spec_bar")
assert(#specBarDB.entries == 0,
    "specSpecific fold must not write the legacy shared entries field")
assert(#specList == 2, "record must fold into the current spec list")
assert(specList[1].id == QUELL, "record returns to its saved slot in the spec list")
assert(next(specBarDB.dormantSpells) == nil, "specSpecific shelf must be emptied")

print("OK: cdm_spelldata_dormant_foldback_test")
