-- tests/unit/cdm_spelldata_dormant_login_gate_test.lua
-- Run: lua tests/unit/cdm_spelldata_dormant_login_gate_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_ClassTalents
--
-- Regression: at cold login, IsSpellKnown/IsPlayerSpell return false for
-- class-tree talents (e.g. Evoker Quell 351338) until the trait system
-- loads. CheckDormantSpells Phase 1 judged entries by those APIs with no
-- readiness gate, so a login-timing race shelved valid talent spells out of
-- custom containers' `entries`. Phase 1 must not judge spell knowledge
-- while C_ClassTalents.GetActiveConfigID() is nil or while the cold-load
-- grace window (ns._cdmColdLoadActive) is open. Phase 2 restore is
-- affirmative evidence (IsSpellKnownByPlayer true) and must keep working
-- regardless of the gate.

local function noop() end

local knownSpells = {}
local activeConfigID = nil

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

C_ClassTalents = {
    GetActiveConfigID = function() return activeConfigID end,
}

local QUELL = 351338

local customBarDB = {
    builtIn = false,
    containerType = "customBar",
    shape = "icon",
    entries = { { type = "spell", id = QUELL, kind = "cooldown", row = 1 } },
    dormantSpells = {},
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
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

-- Case 1: talent data not loaded (GetActiveConfigID nil) — Phase 1 must NOT
-- shelve, even though the spell tests unknown.
activeConfigID = nil
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 1,
    "Phase 1 must not shelve while talent data is unloaded (GetActiveConfigID nil)")
assert(next(customBarDB.dormantSpells) == nil,
    "no dormant record may be written while talent data is unloaded")

-- Case 2: cold-load grace open — Phase 1 must NOT shelve even with talent
-- data loaded (catalog/spellbook still settling).
activeConfigID = 777
ns._cdmColdLoadActive = true
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 1,
    "Phase 1 must not shelve during the cold-load grace window")
ns._cdmColdLoadActive = false

-- Case 3: data ready and spell genuinely unknown (real respec away) — the
-- legitimate shelve must still work.
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 0,
    "with data ready, an unknown spell must still be shelved (respec case)")
local dormant = customBarDB.dormantSpells[QUELL]
assert(type(dormant) == "table", "shelved spell must get a dormant record")
assert(dormant.slot == 1, "dormant record must preserve the slot")

-- Case 4: spell becomes known again while the gate is CLOSED — Phase 2
-- restore is affirmative evidence and must run regardless of the gate.
knownSpells[QUELL] = true
activeConfigID = nil
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 1,
    "Phase 2 restore must work even while the Phase 1 gate is closed")
assert(customBarDB.entries[1].id == QUELL, "restored entry must be the shelved spell")
assert(next(customBarDB.dormantSpells) == nil,
    "restored spell must leave the dormant map")

print("OK: cdm_spelldata_dormant_login_gate_test")
