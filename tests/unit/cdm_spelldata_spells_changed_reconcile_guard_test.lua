-- tests/unit/cdm_spelldata_spells_changed_reconcile_guard_test.lua
-- Run: lua tests/unit/cdm_spelldata_spells_changed_reconcile_guard_test.lua
-- luacheck: globals InCombatLockdown GetTime IsSpellKnown IsPlayerSpell wipe CreateFrame C_Timer C_ClassTalents
--
-- A SPELLS_CHANGED that changes nothing structural (a transient proc override
-- like Hammer of Light replacing Wake of Ashes) must NOT drive the full
-- container refresh (QUI_OnSpellDataChanged -> RefreshAll). That refresh tore
-- glows down/up and rewrote stack text on every proc. The debounced reconcile
-- now skips the refresh when no dormant spell was folded back AND the
-- persistent learned-cooldown set is unchanged across the rebuild. A real
-- talent/spec change moves that set, so it still refreshes.

local function noop() end
local knownSpells = {}
local learnedCooldowns = {}   -- spellID -> true: preferred id of a LEARNED slot

function InCombatLockdown() return false end
function GetTime() return 100 end
function IsSpellKnown(spellID) return knownSpells[spellID] == true end
function IsPlayerSpell(spellID) return knownSpells[spellID] == true end
function wipe(tbl) for k in pairs(tbl) do tbl[k] = nil end end

-- Capture event frames so we can drive the SPELLS_CHANGED handler.
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

-- Run deferred callbacks (the SPELLS_CHANGED 0.3s debounce, Initialize's setup
-- timer) synchronously so each fired event resolves in-line.
C_Timer = {
    After = function(_, fn) fn() end,
    NewTicker = function() return { Cancel = noop } end,
    NewTimer = function() return { Cancel = noop } end,
}

C_ClassTalents = {
    GetActiveConfigID = function() return 777 end,
    GetActiveHeroTalentSpec = function() return 100 end,
}

local WAKE = 255937   -- base; stays known + learned across the HoL proc
local FIRE_BREATH = 357208

local essentialDB = {
    builtIn = true,
    ownedSpells = {
        { type = "spell", id = WAKE, kind = "cooldown", source = "blizzardCDM" },
        { type = "spell", id = FIRE_BREATH, kind = "cooldown", source = "blizzardCDM" },
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
    CDMComposer = {
        RebuildBlizzardCatalogMaps = function(spellToCDID, inCooldowns)
            for id in pairs(learnedCooldowns) do
                spellToCDID[id] = id
                inCooldowns[id] = true
            end
        end,
        -- SelectPersistentSpellID-backed learned set: base-stable. A proc
        -- override never adds the override id here, so the set is unchanged
        -- across a proc; a talent change adds/removes ids.
        RebuildCooldownLearnedPreferredIDs = function(outSet)
            for id in pairs(learnedCooldowns) do outSet[id] = true end
        end,
        CollectKnownCDMSpellIDs = function() end,
    },
}

-- Count container refreshes (the expensive path the guard avoids).
local refreshCount = 0
_G.QUI_OnSpellDataChanged = function() refreshCount = refreshCount + 1 end

knownSpells[WAKE] = true
knownSpells[FIRE_BREATH] = true
learnedCooldowns = { [WAKE] = true, [FIRE_BREATH] = true }

dofile("tests/helpers/load_cdm_spelldata_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_spelldata.lua"))("QUI", ns)

-- Initialize() creates the runtime event frame that owns the SPELLS_CHANGED
-- handler (timers run inline, so its deferred setup completes here too).
ns.CDMSpellData:Initialize()

local eventFrame
for _, f in ipairs(frames) do
    if f.events and f.events.SPELLS_CHANGED and f.OnEvent then eventFrame = f break end
end
assert(eventFrame, "spelldata should register a SPELLS_CHANGED event frame with an OnEvent handler")

local function fireSpellsChanged() eventFrame.OnEvent(eventFrame, "SPELLS_CHANGED") end

-- Baseline: establish the learned set + a clean refresh count.
ns.CDMSpellData:ReconcileAllContainers()
refreshCount = 0

-- CASE 1: proc-style SPELLS_CHANGED -- learned set unchanged, nothing shelved.
-- The debounced reconcile must NOT refresh.
fireSpellsChanged()
assert(refreshCount == 0,
    "SPELLS_CHANGED with no structural change (proc override) must not trigger a "
        .. "container refresh; got " .. refreshCount)

-- CASE 2: talent change -- a learned cooldown is added. The reconcile must
-- refresh.
knownSpells[88888] = true
learnedCooldowns = { [WAKE] = true, [FIRE_BREATH] = true, [88888] = true }
fireSpellsChanged()
assert(refreshCount == 1,
    "SPELLS_CHANGED that adds a learned cooldown (talent change) must refresh once; got "
        .. refreshCount)

-- CASE 3: talent change that drops a learned cooldown must also refresh.
refreshCount = 0
learnedCooldowns = { [WAKE] = true, [FIRE_BREATH] = true }
fireSpellsChanged()
assert(refreshCount == 1,
    "SPELLS_CHANGED that drops a learned cooldown must refresh once; got " .. refreshCount)

-- CASE 4: a dormant spell folded back into the list refreshes even when the
-- learned set is unchanged (the restore is itself a structural change).
refreshCount = 0
essentialDB.dormantSpells = { [424242] = { slot = 1 } }
fireSpellsChanged()
assert(refreshCount == 1,
    "SPELLS_CHANGED that folds a shelved spell back must refresh once; got " .. refreshCount)

-- CASE 5: steady state again -- after the fold cleared the shelf and the
-- learned set is stable, a further proc-style SPELLS_CHANGED is silent.
refreshCount = 0
fireSpellsChanged()
assert(refreshCount == 0,
    "a stable SPELLS_CHANGED after the shelf cleared must not refresh; got " .. refreshCount)

print("OK: cdm_spelldata_spells_changed_reconcile_guard_test")
