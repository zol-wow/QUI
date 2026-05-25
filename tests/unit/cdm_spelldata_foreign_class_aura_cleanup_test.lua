-- tests/unit/cdm_spelldata_foreign_class_aura_cleanup_test.lua
-- Run: lua tests/unit/cdm_spelldata_foreign_class_aura_cleanup_test.lua
--
-- Regression: a profile shared across classes (single AceDB "Default") let a
-- previous character's tracked-buff auras linger in a built-in AURA container
-- (buff / trackedBar) on a different class. CheckDormantSpells historically
-- skipped aura entries entirely (buff aura IDs aren't in the spellbook, so
-- IsSpellKnownByPlayer can't judge them), so foreign-class auras were never
-- cleaned. The fix uses the per-character Blizzard CDM catalog
-- (IsSpellInCDMCategory) as the class signal: an aura absent from THIS
-- character's aura family is foreign and must be shelved.

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown() return false end       -- aura buff IDs are never in the spellbook
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

-- Hunter (current class) aura that legitimately belongs in trackedBar.
local HUNTER_AURA = 257284
-- Death Knight auras that leaked in via the shared profile.
local DK_AURA_1 = 48707  -- Anti-Magic Shell
local DK_AURA_2 = 48792  -- Icebound Fortitude

local trackedBarDB = {
    ownedSpells = {
        { type = "spell", id = HUNTER_AURA, kind = "aura" },
        { type = "spell", id = DK_AURA_1,  kind = "aura" },
        { type = "spell", id = DK_AURA_2,  kind = "aura" },
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
    -- The per-character Blizzard CDM catalog. On this Hunter only HUNTER_AURA
    -- is registered in the aura family; the DK auras are absent.
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(spellToCD, _inCooldowns, inAuras)
            spellToCD[HUNTER_AURA] = 9001
            inAuras[HUNTER_AURA] = true
        end,
        CollectKnownCDMSpellIDs = function(out)
            out[HUNTER_AURA] = true
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_spelldata.lua"))("QUI", ns)

ns.CDMSpellData:CheckDormantSpells("trackedBar")

local owned = trackedBarDB.ownedSpells
local ownedIDs = {}
for _, entry in ipairs(owned) do
    ownedIDs[entry.id] = true
end

assert(ownedIDs[HUNTER_AURA] == true,
    "a same-class aura (in this character's CDM aura catalog) must be kept")
assert(ownedIDs[DK_AURA_1] == nil,
    "a foreign-class aura absent from this character's CDM aura catalog must be removed from ownedSpells")
assert(ownedIDs[DK_AURA_2] == nil,
    "all foreign-class auras must be removed, not just the first")
assert(#owned == 1, "only the same-class aura should remain in the tracked-bar container")

-- Re-running must be stable: the surviving same-class aura stays put.
ns.CDMSpellData:CheckDormantSpells("trackedBar")
assert(#trackedBarDB.ownedSpells == 1, "second pass must be a no-op for the same-class aura")
assert(trackedBarDB.ownedSpells[1].id == HUNTER_AURA, "same-class aura must survive repeated passes")

print("OK: cdm_spelldata_foreign_class_aura_cleanup_test")
