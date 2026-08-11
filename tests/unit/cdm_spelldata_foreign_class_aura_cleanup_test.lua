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
-- walked, so early-load passes can't hide legitimate auras. The full catalog
-- is an allowUnlearned superset, so class applicability is checked against a
-- future/off-spec spellbook family before current-spec dormancy.

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
local HUNTER_UNLEARNED_AURA = 257285
-- Death Knight auras that leaked in via the shared profile.
local DK_AURA_1 = 48707  -- Anti-Magic Shell
local DK_AURA_2 = 48792  -- Icebound Fortitude
local MANUAL_AURA = 123456

local trackedBarDB = {
    ownedSpells = {
        { type = "spell", id = HUNTER_AURA, kind = "aura", source = "blizzardCDM" },
        { type = "spell", id = DK_AURA_1,  kind = "aura", source = "blizzardCDM" },
        { type = "spell", id = DK_AURA_2,  kind = "aura", source = "blizzardCDM" },
        { type = "spell", id = HUNTER_UNLEARNED_AURA, kind = "aura", source = "blizzardCDM" },
        { type = "spell", id = MANUAL_AURA, kind = "aura" },
    },
    dormantSpells = {},
    removedSpells = {},
}

-- The per-character Blizzard CDM catalog. The full allowUnlearned family
-- contains the foreign rows too (the PTR failure mode), but only HUNTER_AURA
-- belongs to the learned/current-spec family. The flag models the early-load
-- window before either catalog has been walked.
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
    -- Runtime reads ns.CDMCatalog directly; ns.CDMComposer is only the alias
    -- that ships in the LoadOnDemand options addon.
    CDMCatalog = {
        RebuildBlizzardCatalogMaps = function(spellToCD, _inCooldowns, inAuras)
            if not catalogLoaded then return end
            spellToCD[HUNTER_AURA] = 9001
            spellToCD[DK_AURA_1] = 9002
            spellToCD[DK_AURA_2] = 9003
            spellToCD[HUNTER_UNLEARNED_AURA] = 9004
            inAuras[HUNTER_AURA] = true
            inAuras[DK_AURA_1] = true
            inAuras[DK_AURA_2] = true
            inAuras[HUNTER_UNLEARNED_AURA] = true
        end,
        RebuildAuraLearnedFamilyIDs = function(out)
            if not catalogLoaded then return false end
            out[HUNTER_AURA] = true
            return true
        end,
        RebuildClassApplicableSpellIDs = function(out)
            if not catalogLoaded then return false end
            out[HUNTER_AURA] = true
            out[HUNTER_UNLEARNED_AURA] = true
            return true
        end,
        CollectKnownCDMSpellIDs = function(out)
            out[HUNTER_AURA] = true
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

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
assert(builtIDs[HUNTER_UNLEARNED_AURA],
    "same-class unlearned auras must not be hidden before catalog readiness")
assert(builtIDs[MANUAL_AURA],
    "manual aura spell IDs must render before the catalog is ready")
assert(ns.CDMSpellData:IsEntryDormantForContainer("trackedBar", trackedBarDB.ownedSpells[2]) == false,
    "composer dormancy checks must not mark auras dormant before the catalog is ready")
assert(ns.CDMSpellData:IsEntryDormantForContainer("trackedBar", trackedBarDB.ownedSpells[5]) == false,
    "manual aura spell IDs must not be catalog-gated before the catalog is ready")

-- Phase B: all catalogs walked. The foreign rows still exist in Blizzard's
-- allowUnlearned family, but are absent from the current-class spell family,
-- so they disappear from runtime and Composer rather than surfacing as
-- Dormant. ownedSpells remains pure user intent.
catalogLoaded = true
builtIDs = builtIDSet("trackedBar")
assert(builtIDs[HUNTER_AURA],
    "a same-class aura in the current learned family must render")
assert(not builtIDs[DK_AURA_1],
    "an unlearned foreign aura in the full PTR catalog must be hidden")
assert(not builtIDs[DK_AURA_2],
    "all unlearned foreign PTR rows must be hidden, not just the first")
assert(not builtIDs[HUNTER_UNLEARNED_AURA],
    "a same-class unlearned aura should remain saved but dormant at runtime")
assert(builtIDs[MANUAL_AURA],
    "manual aura spell IDs absent from Blizzard CDM must stay active")
assert(ns.CDMSpellData:IsEntryDormantForContainer("trackedBar", trackedBarDB.ownedSpells[1]) == false,
    "composer dormancy checks must keep same-class auras active")
assert(ns.CDMSpellData:IsEntryApplicableForContainer("trackedBar", trackedBarDB.ownedSpells[1]) == true,
    "same-class auras must remain applicable to Composer")
assert(ns.CDMSpellData:IsEntryApplicableForContainer("trackedBar", trackedBarDB.ownedSpells[2]) == false,
    "foreign-class auras must be hidden from Composer")
assert(ns.CDMSpellData:IsEntryApplicableForContainer("trackedBar", trackedBarDB.ownedSpells[3]) == false,
    "all foreign-class auras must be hidden, not just the first")
assert(ns.CDMSpellData:IsEntryDormantForContainer("trackedBar", trackedBarDB.ownedSpells[2]) == false,
    "foreign-class auras are inapplicable, not Dormant")
assert(ns.CDMSpellData:IsEntryDormantForContainer("trackedBar", trackedBarDB.ownedSpells[3]) == false,
    "no foreign-class aura should be labeled Dormant")
assert(ns.CDMSpellData:IsEntryApplicableForContainer("trackedBar", trackedBarDB.ownedSpells[4]) == true,
    "a same-class unlearned aura must remain applicable to Composer")
assert(ns.CDMSpellData:IsEntryDormantForContainer("trackedBar", trackedBarDB.ownedSpells[4]) == true,
    "a same-class unlearned aura should appear under Dormant")
assert(ns.CDMSpellData:IsEntryDormantForContainer("trackedBar", trackedBarDB.ownedSpells[5]) == false,
    "composer dormancy checks must not expose manual aura spell IDs as dormant")
assert(ns.CDMSpellData:IsEntryApplicableForContainer("trackedBar", trackedBarDB.ownedSpells[5]) == true,
    "manual aura spell IDs must remain user-managed and visible")

assert(#trackedBarDB.ownedSpells == 5,
    "ownedSpells must never be mutated by the render-time aura filter")
ns.CDMSpellData:CheckDormantSpells("trackedBar")
assert(#trackedBarDB.ownedSpells == 5,
    "the reconcile pass must not remove foreign-class auras either")
assert(next(trackedBarDB.dormantSpells) == nil,
    "no shelf record may be written for foreign-class auras")

print("OK: cdm_spelldata_foreign_class_aura_cleanup_test")
