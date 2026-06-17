-- tests/unit/cdm_usability_no_resolve_test.lua
-- Run: lua5.1 tests/unit/cdm_usability_no_resolve_test.lua
-- Verifies that ApplyUsabilityRefresh does NOT call applyResolvedCooldown for
-- on-cooldown icons, while still calling updateContainerVisibility for them.
-- Usable tint is handled by cdm_icon_range_policy.lua on the same event;
-- cooldown swipe/desat are live C-side — the full resolve is redundant here.
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
local appliedCooldowns = {}
local updatedVisibility = {}
local rangeRefreshes = 0

---------------------------------------------------------------------------
-- Load the module under test (same pattern as cdm_spells_changed_defer_test)
---------------------------------------------------------------------------
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_runtime_refresh.lua")("QUI", ns)
local module = assert(ns.CDMIconRuntimeRefresh, "CDMIconRuntimeRefresh should be exported")

---------------------------------------------------------------------------
-- Icon factory helpers
---------------------------------------------------------------------------
local function makeEntry(name, kind)
    return {
        id = 100,
        spellID = 100,
        name = name,
        kind = kind or "cooldown",
        type = "spell",
        viewerType = "essential",
    }
end

-- Build an on-cooldown icon that satisfies IconNeedsUsabilityCooldownRefresh.
-- The gate checks (in order): _hasCooldownActive, _hasRealCooldownActive,
-- _showingRealCooldownSwipe, _showingGCDSwipe, _lastDurObjKey,
-- _cooldownExpiryTimerKey, _cdDesaturated.  Setting _hasCooldownActive is
-- sufficient to pass it through.
local function makeOnCooldownIcon(name)
    return {
        name = name,
        _spellEntry = makeEntry(name),
        _hasCooldownActive = true,
    }
end

-- Build an idle icon that does NOT satisfy the gate.
local function makeIdleIcon(name)
    return {
        name = name,
        _spellEntry = makeEntry(name),
    }
end

---------------------------------------------------------------------------
-- Shared callbacks factory
---------------------------------------------------------------------------
local function makeCallbacks(iconPool)
    appliedCooldowns = {}
    updatedVisibility = {}
    rangeRefreshes = 0

    return {
        isRuntimeEnabled = function() return true end,
        getIconPools = function() return { essential = iconPool } end,
        isSecretValue = function() return false end,
        gcdSpellID = 61304,
        prepareBatch = function() return false, {}, {}, false end,
        beginBatch = noop,
        endBatch = noop,
        setStackTextWrites = noop,
        applyResolvedCooldown = function(icon)
            appliedCooldowns[icon.name] = (appliedCooldowns[icon.name] or 0) + 1
        end,
        updateIconCooldown = noop,
        applyAuraScopedResolvedCooldown = function() return false end,
        resolveContainerDBAndType = function() return {}, nil end,
        updateContainerVisibility = function(icon)
            updatedVisibility[icon.name] = (updatedVisibility[icon.name] or 0) + 1
        end,
        syncCooldownBling = noop,
        drainLayoutDirty = noop,
        isAuraEntry = function() return false end,
        getMirrorStateByCooldownID = function() return nil end,
        getItemIDForEntry = function() return nil end,
        queryItemSpell = function() return nil end,
        queryCooldownAuraBySpellID = function() return nil end,
        clearDurationBinding = noop,
        updateIconRangesForUsabilityEvent = function()
            rangeRefreshes = rangeRefreshes + 1
        end,
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
        clearTextureCycleCache = noop,
        clearDurationBindingKeyCache = noop,
        clearStableCaches = noop,
    }
end

---------------------------------------------------------------------------
-- Test 1: applyResolvedCooldown is NOT called for on-cooldown icon during
--         ApplyUsabilityRefresh.
---------------------------------------------------------------------------
local cooldownIcon = makeOnCooldownIcon("spell")
local idleIcon     = makeIdleIcon("idle")

local ctrl = module.Create(makeCallbacks({ cooldownIcon, idleIcon }))
ctrl:ApplyUsabilityRefresh()

assert(appliedCooldowns.spell == nil,
    "Test1: applyResolvedCooldown must NOT be called for an on-cooldown icon during usability refresh")
assert(appliedCooldowns.idle == nil,
    "Test1: applyResolvedCooldown must NOT be called for an idle icon during usability refresh")

print("OK: Test1 — applyResolvedCooldown not called during usability refresh")

---------------------------------------------------------------------------
-- Test 2: updateContainerVisibility IS still called for the on-cooldown icon.
---------------------------------------------------------------------------
assert(updatedVisibility.spell == 1,
    "Test2: updateContainerVisibility must still be called for the on-cooldown icon")
assert(updatedVisibility.idle == nil,
    "Test2: updateContainerVisibility must NOT be called for the idle (gated-out) icon")

print("OK: Test2 — updateContainerVisibility still fires for the on-cooldown icon")

---------------------------------------------------------------------------
-- Test 3: The on-cooldown icon passes the gate (sanity — it was iterated).
--         Confirmed by Test 2: visibility was updated, so the icon was processed.
---------------------------------------------------------------------------
-- No extra assertion needed; if updatedVisibility.spell == 1 above, the gate
-- was passed.  We add a redundant positive check for clarity.
local iterated = (updatedVisibility.spell or 0) > 0
assert(iterated,
    "Test3: on-cooldown icon must pass IconNeedsUsabilityCooldownRefresh gate and be iterated")

print("OK: Test3 — on-cooldown icon passes the usability gate and is iterated")

---------------------------------------------------------------------------
-- Test 4: RunUsabilityRefresh also skips the resolve while still running the
--         range policy (updateIconRangesForUsabilityEvent).
---------------------------------------------------------------------------
ctrl = module.Create(makeCallbacks({ cooldownIcon }))
ctrl:RunUsabilityRefresh()

assert(appliedCooldowns.spell == nil,
    "Test4: RunUsabilityRefresh must not call applyResolvedCooldown")
assert(rangeRefreshes == 1,
    "Test4: RunUsabilityRefresh must still call updateIconRangesForUsabilityEvent")
assert(updatedVisibility.spell == 1,
    "Test4: RunUsabilityRefresh must still call updateContainerVisibility")

print("OK: Test4 — RunUsabilityRefresh skips resolve but keeps range policy and visibility")

---------------------------------------------------------------------------
-- Test 5: GCD-locked icon (was previously skip-guarded) now also skips the
--         resolve — the skipCooldownApply guard is gone entirely.
--         Visibility must still fire.
---------------------------------------------------------------------------
local gcdIcon = makeIdleIcon("gcd")
gcdIcon._showingGCDSwipe = true
gcdIcon._showingRealCooldownSwipe = nil
gcdIcon._hasRealCooldownActive = nil
-- _showingGCDSwipe == true makes IconNeedsUsabilityCooldownRefresh return true

ctrl = module.Create(makeCallbacks({ gcdIcon }))
ctrl:ApplyUsabilityRefresh()

assert(appliedCooldowns.gcd == nil,
    "Test5: GCD-locked icon must not trigger applyResolvedCooldown (guard removed)")
assert(updatedVisibility.gcd == 1,
    "Test5: GCD-locked icon must still have updateContainerVisibility called")

print("OK: Test5 — GCD-locked icon still gets visibility update without resolve")

print("OK: cdm_usability_no_resolve_test")
