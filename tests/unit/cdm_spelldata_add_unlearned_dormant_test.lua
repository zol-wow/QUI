-- tests/unit/cdm_spelldata_add_unlearned_dormant_test.lua
-- Run: lua tests/unit/cdm_spelldata_add_unlearned_dormant_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame

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

local customDB = {
    builtIn = false,
    shape = "bar",
    ownedSpells = {},
    dormantSpells = {},
    removedSpells = {},
}

local customBarDB = {
    builtIn = false,
    containerType = "customBar",
    shape = "icon",
    entries = {},
    dormantSpells = {},
    removedSpells = {},
}

local buffDB = {
    builtIn = true,
    containerType = "aura",
    ownedSpells = {},
    dormantSpells = {},
    removedSpells = {},
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    buff = buffDB,
                    containers = {
                        custom_bar = customDB,
                        custom_user_bar = customBarDB,
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

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
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

local auraDormant = ns.CDMSpellData:AddSpell("buff", 24680, "aura", nil, false)
assert(auraDormant == true, "unlearned aura picker entries should be accepted")
assert(#buffDB.ownedSpells == 0, "unlearned aura picker entries should not land in active entries")
assert(type(buffDB.dormantSpells[24680]) == "table",
    "unlearned aura picker entries should be stored dormant")
ns.CDMSpellData:CheckDormantSpells("buff")
assert(#buffDB.ownedSpells == 0, "explicitly unlearned aura entries should not immediately self-restore")
assert(type(buffDB.dormantSpells[24680]) == "table",
    "explicitly unlearned aura entries should remain dormant after reconciliation")
ns.CDMCatalog = {
    GetCategorySet = function(category, allowUnlearned)
        assert(allowUnlearned == true, "dormant aura restore should include unlearned CDM catalog entries")
        if category == 2 then return { 9001 } end
        return {}
    end,
    GetCooldownInfo = function(cooldownID)
        if cooldownID == 9001 then
            return {
                spellID = 24680,
                overrideSpellID = nil,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = {},
                isKnown = true,
            }
        end
        return nil
    end,
}
ns.CDMSpellData:CheckDormantSpells("buff")
assert(buffDB.dormantSpells[24680] == nil, "CDM-known aura entries should leave dormant storage")
assert(#buffDB.ownedSpells == 1, "CDM-known aura entries should restore to active entries")
assert(buffDB.ownedSpells[1].kind == "aura", "restored aura entries should preserve aura kind")

local customBarDormant = ns.CDMSpellData:AddSpell("custom_user_bar", 54321, "cooldown", nil, false)
assert(customBarDormant == true, "unlearned custom container cooldown entries should be accepted")
assert(#customBarDB.entries == 0, "unlearned custom container cooldown entries should not land in active entries")
assert(type(customBarDB.dormantSpells[54321]) == "table",
    "unlearned custom container cooldown entries should be stored dormant")

knownSpells[54321] = true
local restoredCustomBar = ns.CDMSpellData:RestoreDormantEntry("custom_user_bar", 54321)
assert(restoredCustomBar == true, "known custom container dormant entries should restore")
assert(customBarDB.dormantSpells[54321] == nil, "restored custom container spell should leave dormant storage")
assert(#customBarDB.entries == 1, "restored custom container dormant entries should return to active entries")
assert(customBarDB.entries[1].id == 54321, "restored custom container entry should preserve spell ID")

ns.CDMSources.QueryBestOwnedItemVariant = function(itemID)
    if itemID == 1001 or itemID == 1002 then
        return 1002
    end
    return itemID
end

local itemAdded = ns.CDMSpellData:AddItem("custom_bar", 1001)
assert(itemAdded == true, "first item quality variant should be added")
local duplicateItem = ns.CDMSpellData:AddItem("custom_bar", 1002)
assert(duplicateItem == false, "alternate quality variants should be treated as the same configured item")

print("OK: cdm_spelldata_add_unlearned_dormant_test")
