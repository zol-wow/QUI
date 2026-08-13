-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame IsSpellKnown IsPlayerSpell

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
        RegisterEvent       = noop,
        RegisterUnitEvent   = noop,
        UnregisterEvent     = noop,
        UnregisterAllEvents = noop,
        SetScript           = noop,
    }
end
function IsSpellKnown() return true end
function IsPlayerSpell() return true end

local OWNED_ID = 8936
local OVERRIDE_ID = 999001
local BASE_ID = 8930

local essentialDB = {
    containerType = "cooldown",
    ownedSpells   = { { type = "spell", id = OWNED_ID, kind = "cooldown", row = 1 } },
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    essential = essentialDB,
                },
            },
        },
    },
    Helpers = {
        IsSecretValue            = function() return false end,
        SafeValue                = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
        QueryOverrideSpell = function(spellID)
            if spellID == OWNED_ID then return OVERRIDE_ID end
            return spellID
        end,
        QueryBaseSpell = function(spellID)
            if spellID == OWNED_ID then return BASE_ID end
            return nil
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

local capturedOwned
ns.CDMCatalog = {
    GetAvailableSpellsForContainer = function(_containerKey, _containerType, ownedSet)
        capturedOwned = ownedSet
        return {}
    end,
}

ns.CDMSpellData:GetAvailableSpells("essential")

assert(capturedOwned ~= nil,
    "ownedSet was not passed to GetAvailableSpellsForContainer")
assert(capturedOwned[OWNED_ID] == true,
    "ownedSet must contain the stored spell ID")
assert(capturedOwned[OVERRIDE_ID] == true,
    "ownedSet must contain the override spell ID so /cdm cannot re-offer the same ability")
assert(capturedOwned[BASE_ID] == true,
    "ownedSet must contain the base spell ID so /cdm cannot re-offer the same ability")
assert(capturedOwned["spell:" .. OWNED_ID] == true,
    "ownedSet must keep the type-qualified key for the stored spell ID")

local slotDB = {
    containerType = "cooldown",
    ownedSpells   = { { type = "slot", id = 13, kind = "cooldown" } },
}
local slotSet = ns.CDMSpellData.BuildOwnedSet(slotDB)
assert(slotSet["slot:13"] == true, 'BuildOwnedSet must keep the "slot:<id>" key')
assert(slotSet[13] == true, "BuildOwnedSet must keep the bare id key for non-spell entries")

print("OK cdm_spelldata_owned_set_override_family_test")
