-- tests/unit/cdm_spelldata_no_auto_removal_test.lua
-- Run: lua tests/unit/cdm_spelldata_no_auto_removal_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_ClassTalents
--
-- Container lists are pure user intent. No automatic path may remove or
-- relocate an entry because its spell tests "unknown": IsSpellKnown /
-- IsPlayerSpell race at cold login and during loadout swaps (the trait
-- system transiently unlearns talent spells while
-- C_ClassTalents.GetActiveConfigID() stays non-nil), so every readiness
-- gate bolted onto the old dormant shelving pass only narrowed the data
-- loss window — tracked talent spells (e.g. Evoker Quell 351338) kept
-- vanishing from containers. Unknown spells are hidden at render time
-- instead (BuildSpellListFromOwned and the custom-bar build filter),
-- which self-heals on the next reconcile without ever touching saved
-- data. AddEntry must likewise always land in the list, never on a shelf.

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
local FIRE_BREATH = 357208
local HEALTHSTONE = 5512

local customBarDB = {
    builtIn = false,
    containerType = "customBar",
    shape = "icon",
    entries = { { type = "spell", id = QUELL, kind = "cooldown", row = 1 } },
    dormantSpells = {},
    removedSpells = {},
}

local essentialDB = {
    builtIn = true,
    ownedSpells = {
        { type = "spell", id = FIRE_BREATH, kind = "cooldown" },
        { type = "spell", id = QUELL, kind = "cooldown" },
        { type = "item", id = HEALTHSTONE },
    },
    dormantSpells = {},
    removedSpells = {},
}

local ns = {
    Addon = {
        db = {
            profile = {
                ncdm = {
                    essential = essentialDB,
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
    CDMContainers = {
        GetAllContainerKeys = function() return { "essential", "quell_bar" } end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

knownSpells[FIRE_BREATH] = true

-- Case 1: every load signal "ready" (the exact conditions under which the
-- old Phase 1 legitimately shelved) and the spell tests unknown — the
-- entry must stay. There is no readiness state in which removal is allowed.
activeConfigID = 777
ns._cdmColdLoadActive = false
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 1,
    "an unknown spell must never be removed from a custom container")
assert(customBarDB.entries[1].id == QUELL, "the tracked entry must be untouched")
assert(next(customBarDB.dormantSpells) == nil,
    "no shelf record may be written for an unknown spell")

-- Case 2: cold-login conditions — same invariant.
activeConfigID = nil
ns._cdmColdLoadActive = true
ns.CDMSpellData:CheckDormantSpells("quell_bar")
assert(#customBarDB.entries == 1,
    "an unknown spell must never be removed at cold login either")
ns._cdmColdLoadActive = false
activeConfigID = 777

-- Case 3: the all-container sweep (the reconcile-cadence entry point) must
-- not mutate any container's list — builtin or custom.
ns.CDMSpellData:CheckAllDormantSpells()
assert(#customBarDB.entries == 1, "sweep must not touch custom entries")
assert(#essentialDB.ownedSpells == 3, "sweep must not touch builtin ownedSpells")
assert(next(essentialDB.dormantSpells) == nil,
    "sweep must not shelve builtin spells")

-- Case 4: display-time dormancy for builtins — BuildSpellListFromOwned
-- skips the unknown cooldown spell without mutating ownedSpells, and the
-- entry reappears once the spell tests known.
local built = ns.CDMSpellData:BuildSpellListFromOwned("essential")
local builtIDs = {}
for _, resolved in ipairs(built) do
    builtIDs[resolved.id] = true
end
assert(builtIDs[FIRE_BREATH], "known spell must render")
assert(builtIDs[HEALTHSTONE], "item entries must always render")
assert(not builtIDs[QUELL], "unknown spell must be hidden at render time")
assert(#essentialDB.ownedSpells == 3,
    "render filter must not mutate ownedSpells")

knownSpells[QUELL] = true
built = ns.CDMSpellData:BuildSpellListFromOwned("essential")
builtIDs = {}
for _, resolved in ipairs(built) do
    builtIDs[resolved.id] = true
end
assert(builtIDs[QUELL],
    "the hidden spell must reappear once it tests known (self-heal)")
knownSpells[QUELL] = nil

-- Case 5: AddEntry while the spell tests unknown — the add must land in
-- the list (never on a shelf), and must clear any stale shelf record so
-- the fold-back pass can't later re-insert a duplicate.
customBarDB.dormantSpells[FIRE_BREATH] = { slot = 1, kind = "cooldown", seq = 1 }
local ok = ns.CDMSpellData:AddEntry("quell_bar",
    { type = "spell", id = FIRE_BREATH, kind = "cooldown" })
assert(ok == true, "AddEntry must succeed for an unknown spell")
assert(#customBarDB.entries == 2,
    "AddEntry must insert into the visible list even while unknown")
assert(customBarDB.entries[2].id == FIRE_BREATH, "added entry must be in the list")
assert(customBarDB.dormantSpells[FIRE_BREATH] == nil,
    "AddEntry must clear a stale shelf record for the added spell")

print("OK: cdm_spelldata_no_auto_removal_test")
