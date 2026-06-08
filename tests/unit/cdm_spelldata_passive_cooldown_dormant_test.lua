-- tests/unit/cdm_spelldata_passive_cooldown_dormant_test.lua
-- Run: lua tests/unit/cdm_spelldata_passive_cooldown_dormant_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_ClassTalents
--
-- A blizzardCDM-sourced cooldown that has dropped out of the live cooldown
-- catalog (e.g. a hero talent made it passive) must read as dormant, exactly
-- like the existing aura branch. A hand-added cooldown (source ~= blizzardCDM)
-- is never judged by catalog membership. An empty catalog never marks dormant.

local function noop() end
local knownSpells = {}
local cooldownCatalog = {}   -- spellID -> true: present in /cdm cooldown cats

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown(spellID) return knownSpells[spellID] == true end
function IsPlayerSpell(spellID) return knownSpells[spellID] == true end
function wipe(tbl) for k in pairs(tbl) do tbl[k] = nil end end
function CreateFrame()
    return { RegisterEvent = noop, RegisterUnitEvent = noop,
             UnregisterEvent = noop, UnregisterAllEvents = noop, SetScript = noop }
end

C_ClassTalents = {
    GetActiveConfigID = function() return 777 end,
    GetActiveHeroTalentSpec = function() return 100 end,
}

local TIME_SKIP = 375087   -- active cooldown that goes passive under a hero talent
local FIRE_BREATH = 357208 -- stays an active cooldown

local essentialDB = {
    builtIn = true,
    ownedSpells = {
        { type = "spell", id = FIRE_BREATH, kind = "cooldown", source = "blizzardCDM" },
        { type = "spell", id = TIME_SKIP,   kind = "cooldown", source = "blizzardCDM" },
    },
    dormantSpells = {},
    removedSpells = {},
}

local ns = {
    Addon = { db = { profile = { ncdm = { essential = essentialDB } }, global = {} } },
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
        IsAuraOwnedByPlayerOrPet = function() return true end,
    },
    CDMShared = { IsRuntimeEnabled = function() return true end },
    CDMSources = {
        QueryOverrideSpell = function(s) return s end,
        QueryBaseSpell = function() return nil end,
    },
    CDMContainers = { GetAllContainerKeys = function() return { "essential" } end },
    -- Populate ONLY the cooldown-membership map from cooldownCatalog.
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(spellToCDID, inCooldowns)
            for id in pairs(cooldownCatalog) do
                spellToCDID[id] = id
                inCooldowns[id] = true
            end
        end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

knownSpells[FIRE_BREATH] = true
knownSpells[TIME_SKIP] = true   -- still a KNOWN spell (passive form) -> unknown filter won't hide it

local function entry(id) return { type = "spell", id = id, kind = "cooldown", source = "blizzardCDM" } end

-- Catalog ready, Time Skip absent (passive): dormant. Fire Breath present: not.
cooldownCatalog = { [FIRE_BREATH] = true }
ns.CDMSpellData:ReconcileAllContainers()
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(TIME_SKIP)) == true,
    "passive (catalog-absent) blizzardCDM cooldown must be dormant")
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(FIRE_BREATH)) == false,
    "an in-catalog cooldown must not be dormant")

-- Hand-added (non-blizzardCDM) cooldown absent from catalog: never dormant.
local manual = { type = "spell", id = TIME_SKIP, kind = "cooldown", source = "userSpellID" }
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", manual) == false,
    "non-blizzardCDM cooldowns are never judged by catalog membership")

-- Empty catalog (not ready): never dormant (no false positives mid-load).
cooldownCatalog = {}
ns.CDMSpellData:ReconcileAllContainers()
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(TIME_SKIP)) == false,
    "an empty/unready catalog must not mark anything dormant")

-- Unknown spell stays dormant regardless of source (existing behavior).
cooldownCatalog = { [FIRE_BREATH] = true }
ns.CDMSpellData:ReconcileAllContainers()
knownSpells[TIME_SKIP] = nil
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(TIME_SKIP)) == true,
    "an unknown spell remains dormant (unchanged)")

print("OK: cdm_spelldata_passive_cooldown_dormant_test")
