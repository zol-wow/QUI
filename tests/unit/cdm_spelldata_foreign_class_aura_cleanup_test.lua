-- tests/unit/cdm_spelldata_foreign_class_aura_cleanup_test.lua
-- Run: lua tests/unit/cdm_spelldata_foreign_class_aura_cleanup_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame
--
-- A profile shared across classes (single AceDB "Default") lets a previous
-- character's tracked-buff auras linger in a built-in AURA container
-- (buff / trackedBar) on a different class. Owned lists are pure user
-- intent and are never mutated for it — the foreign auras are hidden at
-- render time instead: BuildSpellListFromOwned skips an aura entry that is
-- absent from THIS character's CDM aura family (per-character Blizzard CDM
-- catalog via IsSpellInCDMCategory), and only once that catalog has been
-- walked, so early-load passes can't hide legitimate auras.

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

-- The per-character Blizzard CDM catalog. On this Hunter only HUNTER_AURA
-- is registered in the aura family; the DK auras are absent. The flag
-- models the early-load window before the catalog has been walked.
local catalogLoaded = false

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
        RebuildBlizzardCatalogMaps = function(spellToCD, _inCooldowns, inAuras)
            if not catalogLoaded then return end
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

local function builtIDSet(containerKey)
    local set = {}
    for _, resolved in ipairs(ns.CDMSpellData:BuildSpellListFromOwned(containerKey)) do
        set[resolved.spellID or resolved.id] = true
    end
    return set
end

-- Phase A: catalog not walked yet (early load). No aura may be hidden —
-- "absent from the catalog" is indistinguishable from "not loaded yet".
local builtIDs = builtIDSet("trackedBar")
assert(builtIDs[HUNTER_AURA], "same-class aura must render before the catalog is ready")
assert(builtIDs[DK_AURA_1] and builtIDs[DK_AURA_2],
    "no aura may be hidden before the catalog is ready")

-- Phase B: catalog walked. Foreign-class auras disappear from the built
-- list — and ONLY from the built list; ownedSpells is pure user intent.
catalogLoaded = true
builtIDs = builtIDSet("trackedBar")
assert(builtIDs[HUNTER_AURA],
    "a same-class aura (in this character's CDM aura catalog) must render")
assert(not builtIDs[DK_AURA_1],
    "a foreign-class aura absent from this character's CDM aura catalog must be hidden")
assert(not builtIDs[DK_AURA_2],
    "all foreign-class auras must be hidden, not just the first")

assert(#trackedBarDB.ownedSpells == 3,
    "ownedSpells must never be mutated by the render-time aura filter")
ns.CDMSpellData:CheckDormantSpells("trackedBar")
assert(#trackedBarDB.ownedSpells == 3,
    "the reconcile pass must not remove foreign-class auras either")
assert(next(trackedBarDB.dormantSpells) == nil,
    "no shelf record may be written for foreign-class auras")

print("OK: cdm_spelldata_foreign_class_aura_cleanup_test")
