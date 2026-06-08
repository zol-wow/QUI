-- tests/unit/cdm_spelldata_cooldown_passive_override_flip_dormant_test.lua
-- Run: lua tests/unit/cdm_spelldata_cooldown_passive_override_flip_dormant_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_ClassTalents
--
-- Regression for the Augmentation "Time Skip" report: an active blizzardCDM
-- cooldown that a talent converts into a passive (with a different spell ID)
-- must read as dormant.
--
-- The trap this guards: the per-character CDM membership map
-- (_spellInCDMCooldowns) is built with allowUnlearned=TRUE, so the
-- converted-away active ID STAYS a "member" of that map forever. Judging
-- dormancy by that map (the old behavior) never retires Time Skip. Dormancy
-- must instead key on the LEARNED, currently-active catalog (the set of
-- preferred spell IDs of learned cooldown slots), which drops the old active
-- ID and surfaces the passive's ID in its place.

local function noop() end
local knownSpells = {}
-- allowUnlearned cooldown membership: KEEPS the converted-away active id.
local cooldownAllowUnlearned = {}
-- learned/active catalog: preferred spell id of each LEARNED cooldown slot.
local cooldownLearnedPreferred = {}

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

local TIME_SKIP_ACTIVE  = 375087   -- active cooldown, added while active
local TIME_SKIP_PASSIVE = 1216957  -- the passive variant the talent grants
local FIRE_BREATH       = 357208   -- stays an active cooldown
-- A legit active override slot: stored entry id is the override (the CDM
-- picker prefers overrideSpellID), and the slot's preferred id is still it.
local DEATH_CHARGE_OVERRIDE = 444347

local essentialDB = {
    builtIn = true,
    ownedSpells = {
        { type = "spell", id = FIRE_BREATH,      kind = "cooldown", source = "blizzardCDM" },
        { type = "spell", id = TIME_SKIP_ACTIVE, kind = "cooldown", source = "blizzardCDM" },
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
        -- Talent override: the active id now resolves to the passive variant,
        -- so IsSpellKnownByPlayer(active) is TRUE and the cheap "unknown ->
        -- dormant" gate does NOT fire. Dormancy must come from the catalog.
        QueryOverrideSpell = function(s)
            if s == TIME_SKIP_ACTIVE then return TIME_SKIP_PASSIVE end
            return s
        end,
        QueryBaseSpell = function() return nil end,
    },
    CDMContainers = { GetAllContainerKeys = function() return { "essential" } end },
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(spellToCDID, inCooldowns)
            for id in pairs(cooldownAllowUnlearned) do
                spellToCDID[id] = id
                inCooldowns[id] = true
            end
        end,
        RebuildCooldownLearnedPreferredIDs = function(outSet)
            for id in pairs(cooldownLearnedPreferred) do
                outSet[id] = true
            end
        end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

-- Active and passive are both KNOWN spells (passive form is learned; active
-- is "known" through the override), so the unknown-spell filter never fires.
knownSpells[TIME_SKIP_ACTIVE]  = true
knownSpells[TIME_SKIP_PASSIVE] = true
knownSpells[FIRE_BREATH]       = true
knownSpells[DEATH_CHARGE_OVERRIDE] = true

local function entry(id, source)
    return { type = "spell", id = id, kind = "cooldown", source = source or "blizzardCDM" }
end

-- After the talent flip:
--  * allowUnlearned membership STILL lists the old active id (the bug surface).
--  * the learned/active catalog lists the passive + the unchanged actives.
cooldownAllowUnlearned = {
    [TIME_SKIP_ACTIVE]      = true,   -- stale member: never dropped
    [TIME_SKIP_PASSIVE]     = true,
    [FIRE_BREATH]           = true,
    [DEATH_CHARGE_OVERRIDE] = true,
}
cooldownLearnedPreferred = {
    [TIME_SKIP_PASSIVE]     = true,   -- the slot's preferred id is now the passive
    [FIRE_BREATH]           = true,
    [DEATH_CHARGE_OVERRIDE] = true,   -- legit active override slot
}
ns.CDMSpellData:ReconcileAllContainers()

assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(TIME_SKIP_ACTIVE)) == true,
    "active cooldown converted to a passive (gone from the learned catalog) must be dormant, "
    .. "even though it lingers in the allowUnlearned membership map")
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(FIRE_BREATH)) == false,
    "an unchanged active cooldown must not be dormant")
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(TIME_SKIP_PASSIVE)) == false,
    "the passive variant (now in the learned catalog) must not be dormant")
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(DEATH_CHARGE_OVERRIDE)) == false,
    "a legit active override (entry id == slot's preferred id) must NOT be dormant")

-- Hand-added (non-blizzardCDM) cooldowns are never judged by catalog membership.
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(TIME_SKIP_ACTIVE, "userSpellID")) == false,
    "non-blizzardCDM cooldowns are never judged by catalog membership")

-- Unready learned catalog (cold load): never mark anything dormant.
cooldownLearnedPreferred = {}
ns.CDMSpellData:ReconcileAllContainers()
assert(ns.CDMSpellData:IsEntryDormantForContainer("essential", entry(TIME_SKIP_ACTIVE)) == false,
    "an empty/unready learned catalog must not mark anything dormant")

print("OK: cdm_spelldata_cooldown_passive_override_flip_dormant_test")
