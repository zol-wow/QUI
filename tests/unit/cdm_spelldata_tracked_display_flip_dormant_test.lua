-- tests/unit/cdm_spelldata_tracked_display_flip_dormant_test.lua
-- Run: lua tests/unit/cdm_spelldata_tracked_display_flip_dormant_test.lua
--
-- Icon<->bar display sync dormancy. Blizzard tracks a buff as EITHER a
-- BuffIcon (category 2) or a bar (category 3), and the builtin containers
-- render native-only — a blizzardCDM entry owned by the container on the
-- WRONG side of that choice has no native frame and renders nothing live.
-- A PROVEN flip (absent from this container's tracked display category AND
-- present in the opposite one) must classify the entry Dormant; anything
-- less than proof (cold/partial read, neither-category rows like
-- spec-agnostic/equip-slot tracked, manual entries) must stay live. The
-- tracked display sets are cached against the CDMIndex broker version:
-- Blizzard settings mutations bump it via the RefreshLayout hook, so a
-- bump — and only a bump — re-reads the assignment.

local noop = function() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown() return true end
function IsPlayerSpell() return true end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
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

local FLIP = 55233   -- entry whose Blizzard display type the test flips
local STAYS = 195181 -- control entry that stays icon-tracked throughout

-- Mutable Blizzard-side tracked display assignment + broker version. The
-- catalog stub below copies these into the sets it is handed.
local trackedDisplay = {
    icon = { [FLIP] = true, [STAYS] = true },
    bar = {},
    ready = true,
}
local brokerVersion = 1

local ns = {
    Addon = {
        db = {
            profile = { ncdm = {
                buff = { ownedSpells = {}, dormantSpells = {}, removedSpells = {} },
                trackedBar = { ownedSpells = {}, dormantSpells = {}, removedSpells = {} },
            } },
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
    CDMIndex = {
        Version = function() return brokerVersion end,
    },
    CDMCatalog = {
        RebuildBlizzardCatalogMaps = function(spellToCooldownID, _, spellInCDMAuras)
            spellToCooldownID[FLIP] = 111
            spellToCooldownID[STAYS] = 222
            spellInCDMAuras[FLIP] = true
            spellInCDMAuras[STAYS] = true
        end,
        RebuildCooldownLearnedPreferredIDs = function() return true end,
        RebuildAuraLearnedFamilyIDs = function(set)
            set[FLIP] = true
            set[STAYS] = true
            return true
        end,
        -- Not ready -> applicability defaults to true; not under test here.
        RebuildClassApplicableSpellIDs = function() return false end,
        RebuildTrackedDisplayFamilyIDs = function(iconSet, barSet)
            for id in pairs(trackedDisplay.icon) do iconSet[id] = true end
            for id in pairs(trackedDisplay.bar) do barSet[id] = true end
            return trackedDisplay.ready
        end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)
local SD = ns.CDMSpellData

SD:ReconcileAllContainers() -- build the spellID maps once

local function blizzEntry(id)
    return { type = "spell", id = id, kind = "aura", source = "blizzardCDM" }
end

-- 1) Matching side: icon-tracked spell live in buff icons; its trackedBar
--    copy is the wrong side (bar absent + icon present = proven) -> dormant.
assert(not SD:IsEntryDormantForContainer("buff", blizzEntry(FLIP)),
    "icon-tracked spell stays live in the buff icon container")
assert(SD:IsEntryDormantForContainer("trackedBar", blizzEntry(FLIP)),
    "icon-tracked spell is dormant in the buff bar container")

-- 2) Flip to bar display + broker bump: dormancy swaps sides.
trackedDisplay.icon[FLIP] = nil
trackedDisplay.bar[FLIP] = true
brokerVersion = 2
assert(SD:IsEntryDormantForContainer("buff", blizzEntry(FLIP)),
    "flipped-to-bar spell goes dormant in the buff icon container")
assert(not SD:IsEntryDormantForContainer("trackedBar", blizzEntry(FLIP)),
    "flipped-to-bar spell is live in the buff bar container")
assert(not SD:IsEntryDormantForContainer("buff", blizzEntry(STAYS)),
    "unflipped control spell is unaffected")

-- 3) Broker-version cache: mutating Blizzard state WITHOUT a version bump
--    keeps answering from the cached sets.
trackedDisplay.bar[FLIP] = nil
trackedDisplay.icon[FLIP] = true
assert(SD:IsEntryDormantForContainer("buff", blizzEntry(FLIP)),
    "no broker bump -> cached tracked display sets still answer")

-- 4) Bump -> flip back detected, entry wakes.
brokerVersion = 3
assert(not SD:IsEntryDormantForContainer("buff", blizzEntry(FLIP)),
    "flip back + broker bump wakes the buff icon entry")

-- 5) Cold/partial tracked read (ready=false) keeps the check inert.
trackedDisplay.ready = false
trackedDisplay.icon[FLIP] = nil
trackedDisplay.bar[FLIP] = true
brokerVersion = 4
assert(not SD:IsEntryDormantForContainer("buff", blizzEntry(FLIP)),
    "not-ready tracked read never dormants (fail non-dormant)")

-- 6) Neither-category rows (spec-agnostic / equip-slot tracked, cats 6/8)
--    are absent from BOTH maps: no proven flip, stays live.
trackedDisplay.ready = true
trackedDisplay.icon[FLIP] = nil
trackedDisplay.bar[FLIP] = nil
brokerVersion = 5
assert(not SD:IsEntryDormantForContainer("buff", blizzEntry(FLIP)),
    "absent from both display maps = no proven flip, stays live")

-- 7) Manual (non-blizzardCDM) aura entries are never judged.
trackedDisplay.bar[FLIP] = true
brokerVersion = 6
assert(not SD:IsEntryDormantForContainer("buff",
        { type = "spell", id = FLIP, kind = "aura" }),
    "manual aura entries are never display-sync judged")

print("OK: cdm_spelldata_tracked_display_flip_dormant_test")
