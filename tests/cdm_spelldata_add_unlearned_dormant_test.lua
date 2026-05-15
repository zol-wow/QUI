-- tests/cdm_spelldata_add_unlearned_dormant_test.lua
-- Run: lua tests/cdm_spelldata_add_unlearned_dormant_test.lua

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

local customDB = {
    builtIn = false,
    shape = "bar",
    ownedSpells = {},
    dormantSpells = {},
    removedSpells = {},
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    containers = {
                        custom_bar = customDB,
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

local changeCallbacks = 0
function _G.QUI_OnSpellDataChanged()
    changeCallbacks = changeCallbacks + 1
end

assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

local ok = ns.CDMSpellData:AddSpell("custom_bar", 67890, "cooldown", 2, false)
assert(ok == true, "adding an unlearned cooldown entry should mutate the container")
assert(#customDB.ownedSpells == 0, "unlearned cooldown entries should not land in the active entry list")
assert(type(customDB.dormantSpells[67890]) == "table", "unlearned cooldown entries should be stored dormant")
assert(customDB.dormantSpells[67890].slot == 1, "dormant entry should preserve the intended insertion slot")
assert(customDB.dormantSpells[67890].row == 2, "dormant entry should preserve the intended cooldown row")
assert(changeCallbacks == 1, "dormant add should fire exactly one change callback")

local duplicate = ns.CDMSpellData:AddSpell("custom_bar", 67890, "cooldown", 3, false)
assert(duplicate == false, "adding an already-dormant spell should be treated as a duplicate")
assert(changeCallbacks == 1, "duplicate dormant add should not fire another change callback")

local learned = ns.CDMSpellData:AddSpell("custom_bar", 12345, "cooldown", 3, true)
assert(learned == true, "known override from the picker should allow an active add")
assert(#customDB.ownedSpells == 1, "known cooldown entry should land in the active list")
assert(customDB.ownedSpells[1].id == 12345, "active entry should preserve its spell ID")
assert(customDB.ownedSpells[1].row == 3, "active entry should preserve the intended cooldown row")

print("OK: cdm_spelldata_add_unlearned_dormant_test")
