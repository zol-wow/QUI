-- tests/unit/cdm_spelldata_override_drain_no_refresh_test.lua
-- Run: lua tests/unit/cdm_spelldata_override_drain_no_refresh_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_Timer C_ClassTalents
--
-- A proc-override fired in combat (COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED) arms
-- the combat-deferred rebuild. On the PLAYER_REGEN_ENABLED drain it must rebuild
-- the spellID->cooldownID map (cheap) but must NOT fire the change callback that
-- drives the full container RefreshAll -- the procced icon is already correct
-- live via the mirror + render-time filter, so the teardown is redundant and was
-- the end-of-pull stutter. DATA_LOADED / TABLE_HOTFIXED (cold-login / hotfix
-- staleness) still need the full refresh. Mixed arming: data_loaded wins.

local function noop() end
local knownSpells = {}
local learnedCooldowns = {}

local inCombat = false
function InCombatLockdown() return inCombat end
function GetTime() return 100 end
function IsSpellKnown(spellID) return knownSpells[spellID] == true end
function IsPlayerSpell(spellID) return knownSpells[spellID] == true end
function wipe(tbl) for k in pairs(tbl) do tbl[k] = nil end end

local frames = {}
function CreateFrame()
    local f = {
        events = {},
        RegisterEvent = function(self, e) self.events[e] = true end,
        RegisterUnitEvent = noop,
        UnregisterEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = function(self, script, handler) self[script] = handler end,
    }
    frames[#frames + 1] = f
    return f
end

C_Timer = {
    After = function(_, fn) fn() end,
    NewTicker = function() return { Cancel = noop } end,
    NewTimer = function() return { Cancel = noop } end,
}

C_ClassTalents = {
    GetActiveConfigID = function() return 777 end,
    GetActiveHeroTalentSpec = function() return 100 end,
}

local WAKE = 255937
local essentialDB = {
    builtIn = true,
    ownedSpells = {
        { type = "spell", id = WAKE, kind = "cooldown", source = "blizzardCDM" },
    },
    dormantSpells = {},
    removedSpells = {},
}

-- Count map rebuilds (RebuildSpellToCooldownID -> RebuildBlizzardCatalogMaps)
-- and container refreshes (FireChangeCallback -> QUI_OnSpellDataChanged).
local mapRebuilds = 0
local refreshCount = 0

-- The other builtin containers need a db with a non-nil ownedSpells so
-- SnapshotBlizzardCDM reports "ready" (steady state, not cold-login). Without
-- them, SnapshotUnsetBuiltinContainers reports not-ready and the OOC path falls
-- into RunColdLoadReconcile's retry loop instead of the steady-state reconcile.
local function ReadyDB()
    return { builtIn = true, ownedSpells = {}, dormantSpells = {}, removedSpells = {} }
end

local ns = {
    Addon = { db = { profile = { ncdm = {
        essential = essentialDB,
        utility = ReadyDB(),
        buff = ReadyDB(),
        trackedBar = ReadyDB(),
    } }, global = {} } },
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
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(spellToCDID, inCooldowns)
            mapRebuilds = mapRebuilds + 1
            for id in pairs(learnedCooldowns) do
                spellToCDID[id] = id
                inCooldowns[id] = true
            end
        end,
        RebuildCooldownLearnedPreferredIDs = function(outSet)
            for id in pairs(learnedCooldowns) do outSet[id] = true end
        end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

_G.QUI_OnSpellDataChanged = function() refreshCount = refreshCount + 1 end

knownSpells[WAKE] = true
learnedCooldowns = { [WAKE] = true }

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)
ns.CDMSpellData:Initialize()

local eventFrame
for _, f in ipairs(frames) do
    if f.events and f.events.COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED
        and f.events.PLAYER_REGEN_ENABLED and f.OnEvent then
        eventFrame = f
        break
    end
end
assert(eventFrame, "spelldata should register a runtime event frame owning the CDM viewer + regen events")

local function fire(event) eventFrame.OnEvent(eventFrame, event) end

-- CASE 1: proc-override armed in combat -> drained at combat end.
-- Map rebuilt, but NO container refresh.
mapRebuilds, refreshCount = 0, 0
inCombat = true
fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
assert(refreshCount == 0, "override in combat must defer, not refresh immediately; got " .. refreshCount)
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(mapRebuilds == 1, "combat-end drain must rebuild the spell->cdID map once; got " .. mapRebuilds)
assert(refreshCount == 0, "proc-override drain must NOT fire the full container refresh; got " .. refreshCount)

-- CASE 2: DATA_LOADED armed in combat -> drained at combat end. Full refresh.
mapRebuilds, refreshCount = 0, 0
inCombat = true
fire("COOLDOWN_VIEWER_DATA_LOADED")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(mapRebuilds == 1, "data_loaded drain must rebuild the map once; got " .. mapRebuilds)
assert(refreshCount == 1, "data_loaded drain must fire the full container refresh once; got " .. refreshCount)

-- CASE 3: mixed arming (override THEN data_loaded) in combat -> data_loaded wins.
mapRebuilds, refreshCount = 0, 0
inCombat = true
fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
fire("COOLDOWN_VIEWER_DATA_LOADED")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(refreshCount == 1, "mixed arming must take the full-refresh path (data_loaded wins); got " .. refreshCount)

-- CASE 3b: reverse mixed arming (data_loaded THEN override) -> refresh still wins.
-- The needsRefresh flag, once set by a non-override event, must survive a later
-- override event in the same combat (override must never clear it).
mapRebuilds, refreshCount = 0, 0
inCombat = true
fire("COOLDOWN_VIEWER_DATA_LOADED")
fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
assert(refreshCount == 1, "data_loaded-then-override must still take the full-refresh path; got " .. refreshCount)

-- CASE 4: nothing armed -> drain is a no-op.
mapRebuilds, refreshCount = 0, 0
fire("PLAYER_REGEN_ENABLED")
assert(mapRebuilds == 0 and refreshCount == 0,
    "unarmed combat-end drain must do nothing; got rebuilds=" .. mapRebuilds .. " refresh=" .. refreshCount)

-- CASE 5: proc-override OUT OF COMBAT must NOT drive a full container refresh.
-- This is the OOC Hammer-of-Light flicker: the override is scoped (mirror +
-- renderer update the one icon). Neither the immediate FireChangeCallback (now
-- gated off for OVERRIDE_UPDATED) nor the debounced reconcile (guarded, base-keyed
-- learned signature unchanged) may fire -- the steady-state proc rebuilt every
-- icon and flashed charge/stack text across the whole bar.
mapRebuilds, refreshCount = 0, 0
inCombat = false
fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
assert(refreshCount == 0,
    "OOC proc-override must NOT fire a full container refresh (scoped event); got " .. refreshCount)

-- CASE 6: DATA_LOADED out of combat still drives the full refresh (genuine
-- catalog staleness, e.g. cold-login binding fix) -- the gate is override-only.
mapRebuilds, refreshCount = 0, 0
inCombat = false
fire("COOLDOWN_VIEWER_DATA_LOADED")
assert(refreshCount >= 1,
    "OOC data_loaded must still fire the full container refresh; got " .. refreshCount)

print("OK: cdm_spelldata_override_drain_no_refresh_test")
