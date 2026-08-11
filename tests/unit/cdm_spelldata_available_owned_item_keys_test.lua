-- tests/unit/cdm_spelldata_available_owned_item_keys_test.lua
-- Run: lua5.1 tests/unit/cdm_spelldata_available_owned_item_keys_test.lua
-- luacheck: globals InCombatLockdown GetTime wipe CreateFrame
--
-- Verifies that CDMSpellData:GetAvailableSpells(containerKey) builds
-- ownedSet keys of the form "slot:<id>" AND bare <id> from a stored
-- non-spell (slot-type) owned entry.  The implementation is exercised
-- end-to-end; the composer stub captures the ownedSet passed to it.

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
        RegisterEvent    = noop,
        RegisterUnitEvent = noop,
        UnregisterEvent  = noop,
        UnregisterAllEvents = noop,
        SetScript        = noop,
    }
end

-- Container DB: one slot-type entry (id=13).
local essentialDB = {
    containerType = "cooldown",
    ownedSpells   = { { type = "slot", id = 13, kind = "cooldown" } },
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    -- GetContainerDB falls back to ncdm[containerKey] when
                    -- Shared.GetContainerDB / Shared.GetNcdmDB are not set.
                    essential = essentialDB,
                },
            },
        },
    },
    Helpers = {
        IsSecretValue           = function() return false end,
        SafeValue               = function(value) return value end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
    },
    CDMSources = {
        QueryOverrideSpell = function(spellID) return spellID end,
        QueryBaseSpell     = function() return nil end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

-- Stub the composer: capture the ownedSet it receives.
local capturedOwned
-- Runtime reads ns.CDMCatalog directly; ns.CDMComposer is only the alias that
-- ships in the LoadOnDemand options addon.
ns.CDMCatalog = {
    GetAvailableSpellsForContainer = function(containerKey, containerType, ownedSet, correctionMap)
        capturedOwned = ownedSet
        return {}
    end,
}

ns.CDMSpellData:GetAvailableSpells("essential")

assert(capturedOwned ~= nil,
    "ownedSet was not passed to GetAvailableSpellsForContainer")
assert(capturedOwned["slot:13"] == true,
    'ownedSet["slot:13"] must be true for a slot-type owned entry with id=13')
assert(capturedOwned[13] == true,
    'ownedSet[13] must be true for a slot-type owned entry with id=13')

print("OK cdm_spelldata_available_owned_item_keys_test")
