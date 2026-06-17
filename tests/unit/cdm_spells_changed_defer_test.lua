-- tests/unit/cdm_spells_changed_defer_test.lua
-- Run: lua5.1 tests/unit/cdm_spells_changed_defer_test.lua
-- Verifies:
--   1. SPELLS_CHANGED is inert (no payload to scope): no cache wipe, no defer,
--      no catalog walk -- in or out of combat. It co-fires with every proc
--      override, so any work here flickered all icons.
--   2. COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED(base, override) scoped-invalidates
--      only the affected spell caches and re-resolves only those icons -- never
--      a catalog walk.
--   3. UPDATE_SHAPESHIFT_FORM and UPDATE_SHAPESHIFT_FORMS clear stable caches and
--      queue a catalog scope refresh with includeItems == false.
-- luacheck: globals InCombatLockdown wipe CreateFrame

local function noop() end

local inCombat = false
local createdFrames = {}

function InCombatLockdown() return inCombat end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function CreateFrame()
    local frame = {
        scripts = {},
        shown = false,
        SetScript = function(self, scriptName, handler)
            self.scripts[scriptName] = handler
        end,
        Show = function(self)
            self.shown = true
        end,
        Hide = function(self)
            self.shown = false
        end,
    }
    createdFrames[#createdFrames + 1] = frame
    return frame
end

---------------------------------------------------------------------------
-- Spy counters
---------------------------------------------------------------------------
local textureCycleClears = 0
local durationKeyClears  = 0
local stableClears       = 0
local catalogRefreshCalls = 0
local lastCatalogOptions  = nil
local spellCacheInvalidations = {}

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_runtime_refresh.lua")("QUI", ns)
local module = assert(ns.CDMIconRuntimeRefresh, "CDMIconRuntimeRefresh should be exported")

local function makeController()
    textureCycleClears = 0
    durationKeyClears  = 0
    stableClears       = 0
    catalogRefreshCalls = 0
    lastCatalogOptions  = nil
    spellCacheInvalidations = {}

    local ctrl = module.Create({
        isRuntimeEnabled = function() return true end,
        getIconPools = function() return {} end,
        isSecretValue = function() return false end,
        gcdSpellID = 61304,
        prepareBatch = function() return false, {}, {}, false end,
        beginBatch = noop,
        endBatch = noop,
        setStackTextWrites = noop,
        applyResolvedCooldown = noop,
        updateIconCooldown = noop,
        applyAuraScopedResolvedCooldown = function() return false end,
        resolveContainerDBAndType = function() return {}, nil end,
        updateContainerVisibility = noop,
        syncCooldownBling = noop,
        drainLayoutDirty = noop,
        isAuraEntry = function() return false end,
        getMirrorStateByCooldownID = function() return nil end,
        getItemIDForEntry = function() return nil end,
        queryItemSpell = function() return nil end,
        queryCooldownAuraBySpellID = function() return nil end,
        clearDurationBinding = noop,
        updateIconRangesForUsabilityEvent = noop,
        scheduleUpdate = noop,
        requestStackTextUpdate = noop,
        noteChargeDurationObjectsUpdated = noop,
        recordRecentPlayerSpellCast = noop,
        getHighlighter = function() return { OnPlayerCastSucceeded = noop } end,
        setBarsDirty = noop,
        markBarsForAuraRefresh = noop,
        runDirtyBarUpdate = noop,
        getCombatQueueDelay = function() return 0.3 end,
        isPlayerInCombat = function() return inCombat end,
        clearTextureCycleCache = function()
            textureCycleClears = textureCycleClears + 1
        end,
        clearDurationBindingKeyCache = function()
            durationKeyClears = durationKeyClears + 1
        end,
        clearStableCaches = function()
            stableClears = stableClears + 1
        end,
        invalidateSpellCaches = function(spellID)
            spellCacheInvalidations[#spellCacheInvalidations + 1] = spellID
        end,
    })

    -- Intercept QueueCatalogScopeRefresh to record calls without running queue machinery
    local origQueue = ctrl.QueueCatalogScopeRefresh
    function ctrl:QueueCatalogScopeRefresh(options)
        catalogRefreshCalls = catalogRefreshCalls + 1
        lastCatalogOptions = options
        -- call through so internal state stays consistent
        return origQueue(self, options)
    end

    return ctrl
end

---------------------------------------------------------------------------
-- Test 1: SPELLS_CHANGED is inert in combat — no cache wipe, no defer, no walk.
---------------------------------------------------------------------------
inCombat = true
local ctrl = makeController()
ctrl.deferredFullRefresh = false

ctrl:Handle("SPELLS_CHANGED")

assert(textureCycleClears == 0,
    "Test1: clearTextureCycleCache must NOT fire for SPELLS_CHANGED")
assert(durationKeyClears == 0,
    "Test1: clearDurationBindingKeyCache must NOT fire for SPELLS_CHANGED")
assert(stableClears == 0,
    "Test1: clearStableCaches must NOT fire for SPELLS_CHANGED")
assert(ctrl.deferredFullRefresh == false,
    "Test1: DeferFullRefresh must NOT be called for SPELLS_CHANGED (no payload to scope)")
assert(catalogRefreshCalls == 0,
    "Test1: QueueCatalogScopeRefresh must NOT be called for SPELLS_CHANGED")
assert(#spellCacheInvalidations == 0,
    "Test1: SPELLS_CHANGED must not invalidate any spell cache")

print("OK: Test1 — in-combat SPELLS_CHANGED is inert")

---------------------------------------------------------------------------
-- Test 2: Out of combat, SPELLS_CHANGED is equally inert.
---------------------------------------------------------------------------
inCombat = false
ctrl = makeController()
ctrl.deferredFullRefresh = false

ctrl:Handle("SPELLS_CHANGED")

assert(textureCycleClears == 0 and durationKeyClears == 0 and stableClears == 0,
    "Test2: OOC SPELLS_CHANGED must not wipe any cache")
assert(ctrl.deferredFullRefresh == false,
    "Test2: deferredFullRefresh must stay false for OOC SPELLS_CHANGED")
assert(catalogRefreshCalls == 0,
    "Test2: OOC SPELLS_CHANGED must NOT call QueueCatalogScopeRefresh")
assert(#spellCacheInvalidations == 0,
    "Test2: OOC SPELLS_CHANGED must not invalidate any spell cache")

print("OK: Test2 — OOC SPELLS_CHANGED is inert")

---------------------------------------------------------------------------
-- Test 2b: COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED scoped-invalidates only the
--          affected spell(s); never a catalog walk. nil overrideSpellID (removal)
--          still invalidates the base spell.
---------------------------------------------------------------------------
inCombat = false
ctrl = makeController()

ctrl:Handle("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 255937, 427453)

assert(catalogRefreshCalls == 0,
    "Test2b: override event must NOT run a catalog walk")
assert(stableClears == 0 and textureCycleClears == 0,
    "Test2b: override event must NOT blanket-wipe caches")
assert(durationKeyClears == 1,
    "Test2b: override event resets the single-slot duration binding key memo")
assert(spellCacheInvalidations[1] == 255937 and spellCacheInvalidations[2] == 427453
    and #spellCacheInvalidations == 2,
    "Test2b: override event invalidates exactly the base and override spell caches")

ctrl:Handle("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 255937, nil)
assert(spellCacheInvalidations[3] == 255937 and #spellCacheInvalidations == 3,
    "Test2b: override removal (nil overrideSpellID) invalidates only the base spell cache")
assert(catalogRefreshCalls == 0,
    "Test2b: override removal must NOT run a catalog walk")

print("OK: Test2b — override event scoped-invalidates only affected spells")

---------------------------------------------------------------------------
-- Test 3: UPDATE_SHAPESHIFT_FORM clears stable caches + queues scope
--         refresh with includeItems == false.
---------------------------------------------------------------------------
inCombat = false
ctrl = makeController()

ctrl:Handle("UPDATE_SHAPESHIFT_FORM")

assert(stableClears == 1,
    "Test3: clearStableCaches must fire for UPDATE_SHAPESHIFT_FORM")
assert(textureCycleClears == 0,
    "Test3: clearTextureCycleCache must NOT fire for UPDATE_SHAPESHIFT_FORM")
assert(durationKeyClears == 0,
    "Test3: clearDurationBindingKeyCache must NOT fire for UPDATE_SHAPESHIFT_FORM")
assert(catalogRefreshCalls == 1,
    "Test3: QueueCatalogScopeRefresh must be called for UPDATE_SHAPESHIFT_FORM")
assert(lastCatalogOptions and lastCatalogOptions.includeItems == false,
    "Test3: UPDATE_SHAPESHIFT_FORM catalog refresh must NOT include items")

print("OK: Test3 — UPDATE_SHAPESHIFT_FORM clears stable caches and queues spell-only refresh")

---------------------------------------------------------------------------
-- Test 4: UPDATE_SHAPESHIFT_FORMS behaves identically to UPDATE_SHAPESHIFT_FORM.
---------------------------------------------------------------------------
inCombat = false
ctrl = makeController()

ctrl:Handle("UPDATE_SHAPESHIFT_FORMS")

assert(stableClears == 1,
    "Test4: clearStableCaches must fire for UPDATE_SHAPESHIFT_FORMS")
assert(textureCycleClears == 0,
    "Test4: clearTextureCycleCache must NOT fire for UPDATE_SHAPESHIFT_FORMS")
assert(durationKeyClears == 0,
    "Test4: clearDurationBindingKeyCache must NOT fire for UPDATE_SHAPESHIFT_FORMS")
assert(catalogRefreshCalls == 1,
    "Test4: QueueCatalogScopeRefresh must be called for UPDATE_SHAPESHIFT_FORMS")
assert(lastCatalogOptions and lastCatalogOptions.includeItems == false,
    "Test4: UPDATE_SHAPESHIFT_FORMS catalog refresh must NOT include items")

print("OK: Test4 — UPDATE_SHAPESHIFT_FORMS clears stable caches and queues spell-only refresh")

---------------------------------------------------------------------------
-- Test 5: UPDATE_SHAPESHIFT_FORM in combat still clears stable caches
--         and queues scope refresh (not deferred).
---------------------------------------------------------------------------
inCombat = true
ctrl = makeController()
ctrl.deferredFullRefresh = false

ctrl:Handle("UPDATE_SHAPESHIFT_FORM")

assert(stableClears == 1,
    "Test5: clearStableCaches must fire for in-combat UPDATE_SHAPESHIFT_FORM")
assert(catalogRefreshCalls == 1,
    "Test5: QueueCatalogScopeRefresh must be called for in-combat UPDATE_SHAPESHIFT_FORM")
assert(lastCatalogOptions and lastCatalogOptions.includeItems == false,
    "Test5: in-combat UPDATE_SHAPESHIFT_FORM must NOT include items")
assert(ctrl.deferredFullRefresh == false,
    "Test5: DeferFullRefresh must NOT be called for UPDATE_SHAPESHIFT_FORM")

print("OK: Test5 — in-combat UPDATE_SHAPESHIFT_FORM queues scope refresh (not deferred)")

inCombat = false

print("OK: cdm_spells_changed_defer_test")
