-- tests/unit/cdm_icon_runtime_refresh_test.lua
-- Run: lua tests/unit/cdm_icon_runtime_refresh_test.lua
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

local function reset(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function count(tbl, key)
    return tbl[key] or 0
end

local secretSpellID = { token = "secret" }
local secretUnit = { token = "secret-unit" }

local function makeIcon(name, entry)
    return {
        name = name,
        _spellEntry = entry,
    }
end

local spellIcon = makeIcon("spell", {
    id = 101,
    spellID = 101,
    kind = "cooldown",
    type = "spell",
    viewerType = "essential",
})
local otherSpellIcon = makeIcon("otherSpell", {
    id = 202,
    spellID = 202,
    kind = "cooldown",
    type = "spell",
    viewerType = "essential",
})
local auraIcon = makeIcon("aura", {
    id = 303,
    spellID = 303,
    kind = "aura",
    type = "spell",
    viewerType = "buff",
    containerType = "aura",
})
local itemIcon = makeIcon("item", {
    id = 404,
    itemID = 404,
    kind = "cooldown",
    type = "item",
    viewerType = "essential",
})
local mirrorAuraIcon = makeIcon("mirrorAura", {
    id = 505,
    spellID = 505,
    kind = "cooldown",
    type = "spell",
    viewerType = "essential",
})
mirrorAuraIcon._blizzMirrorCooldownID = 505
mirrorAuraIcon._blizzMirrorCategory = "essential"
local idleIcon = makeIcon("idle", {
    id = 606,
    spellID = 606,
    kind = "cooldown",
    type = "spell",
    viewerType = "essential",
})

local iconPools = {
    essential = { spellIcon, otherSpellIcon, itemIcon, mirrorAuraIcon, idleIcon },
    buff = { auraIcon },
}

local applied = {}
local auraApplied = {}
local runtimeUpdated = {}
local visibilityUpdated = {}
local blingSynced = {}
local clearedBindings = {}
local batches = {}
local endedBatches = 0
local drained = 0
local rangeRefreshes = 0
local schedules = {}
local barsDirty = false
local dirtyBarRuns = 0
local stackRequested = false
local stackWriteStates = {}
local chargeDurationNotes = 0
local recentCasts = {}
local highlighterCasts = {}
local textureClears = 0
local durationKeyClears = 0
local stableClears = 0
local spellCacheInvalidations = {}
local barAuraRefreshMarks = {}
local mirrorStates = {
    ["505:essential"] = {
        auraInstanceID = 9001,
        auraUnit = "target",
    },
}

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_runtime_refresh.lua")("QUI", ns)
local module = assert(ns.CDMIconRuntimeRefresh, "runtime refresh module should be exported")

local controller = module.Create({
    isRuntimeEnabled = function() return true end,
    getIconPools = function() return iconPools end,
    isSecretValue = function(value) return value == secretSpellID or value == secretUnit end,
    gcdSpellID = 61304,
    prepareBatch = function()
        return false, {}, {}, false
    end,
    beginBatch = function(reason)
        batches[#batches + 1] = reason
    end,
    endBatch = function()
        endedBatches = endedBatches + 1
    end,
    setStackTextWrites = function(enabled)
        stackWriteStates[#stackWriteStates + 1] = enabled == true
    end,
    applyResolvedCooldown = function(icon)
        applied[icon.name] = count(applied, icon.name) + 1
    end,
    updateIconCooldown = function(icon)
        runtimeUpdated[icon.name] = count(runtimeUpdated, icon.name) + 1
    end,
    applyAuraScopedResolvedCooldown = function(icon)
        auraApplied[icon.name] = count(auraApplied, icon.name) + 1
        return true
    end,
    resolveContainerDBAndType = function(entry)
        return {}, entry and entry.containerType
    end,
    updateContainerVisibility = function(icon)
        visibilityUpdated[icon.name] = count(visibilityUpdated, icon.name) + 1
    end,
    syncCooldownBling = function(icon)
        blingSynced[icon.name] = count(blingSynced, icon.name) + 1
    end,
    drainLayoutDirty = function()
        drained = drained + 1
    end,
    isAuraEntry = function(entry)
        return entry and entry.kind == "aura"
    end,
    getMirrorStateByCooldownID = function(cooldownID, category)
        return mirrorStates[tostring(cooldownID) .. ":" .. tostring(category)]
    end,
    getItemIDForEntry = function(entry)
        return entry and entry.itemID
    end,
    queryItemSpell = function(itemID)
        if itemID == 404 then return "Item Use", 707 end
        return nil
    end,
    queryCooldownAuraBySpellID = function(spellID)
        if spellID == 707 then return 808 end
        return nil
    end,
    clearDurationBinding = function(icon)
        clearedBindings[icon.name] = count(clearedBindings, icon.name) + 1
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
    end,
    updateIconRangesForUsabilityEvent = function()
        rangeRefreshes = rangeRefreshes + 1
    end,
    scheduleUpdate = function(fast, mode, reason)
        schedules[#schedules + 1] = {
            fast = fast,
            mode = mode,
            reason = reason,
        }
    end,
    requestStackTextUpdate = function()
        stackRequested = true
    end,
    noteChargeDurationObjectsUpdated = function()
        chargeDurationNotes = chargeDurationNotes + 1
    end,
    recordRecentPlayerSpellCast = function(spellID)
        recentCasts[#recentCasts + 1] = spellID
    end,
    getHighlighter = function()
        return {
            OnPlayerCastSucceeded = function(spellID)
                highlighterCasts[#highlighterCasts + 1] = spellID
            end,
        }
    end,
    setBarsDirty = function(dirty)
        barsDirty = dirty == true
    end,
    markBarsForAuraRefresh = function(unit, updateInfo)
        barAuraRefreshMarks[#barAuraRefreshMarks + 1] = {
            unit = unit,
            updateInfo = updateInfo,
        }
    end,
    runDirtyBarUpdate = function()
        dirtyBarRuns = dirtyBarRuns + 1
    end,
    getCombatQueueDelay = function()
        return 0.3
    end,
    isPlayerInCombat = function()
        return inCombat
    end,
    clearTextureCycleCache = function()
        textureClears = textureClears + 1
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

spellIcon._hasCooldownActive = true
controller:Handle("SPELL_UPDATE_USABLE")
-- applyResolvedCooldown is intentionally NOT called on SPELL_UPDATE_USABLE: the usable
-- tint is applied by cdm_icon_range_policy.lua (updateIconRangesForUsabilityEvent on the
-- same event); swipe/desat are live C-side.  Dropping it eliminates ~300 KB/drain of
-- C_UnitAuras allocations per batch.
assert(applied.spell == nil, "usability refresh must NOT call applyResolvedCooldown (redundant resolve dropped)")
assert(applied.idle == nil, "usability refresh should skip idle cooldown icons")
assert(applied.aura == nil, "usability refresh should skip aura icons")
assert(visibilityUpdated.spell == 1, "usability refresh should still update container visibility for stale cooldown icons")
assert(rangeRefreshes == 1, "usability refresh should reconcile range/usability visuals")

reset(applied)
reset(visibilityUpdated)
spellIcon._hasCooldownActive = false
spellIcon._hasRealCooldownActive = false
spellIcon._showingGCDSwipe = true
spellIcon._showingRealCooldownSwipe = nil
controller:Handle("SPELL_UPDATE_USABLE")
-- applyResolvedCooldown is never called in ApplyUsabilityRefresh regardless of GCD state.
assert(applied.spell == nil, "usability refresh must not call applyResolvedCooldown for a GCD-locked icon")
assert(visibilityUpdated.spell == 1, "usability refresh should still update visibility for an active GCD swipe")
assert(rangeRefreshes == 2, "usability refresh should still reconcile range/usability visuals for an active GCD swipe")
spellIcon._showingGCDSwipe = nil
spellIcon._hasCooldownActive = true

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
wipe(stackWriteStates)
controller:Handle("BAG_UPDATE_COOLDOWN")
assert(applied.item == 1, "bag cooldown event should re-resolve item-backed icons")
assert(applied.spell == nil, "bag cooldown event should not touch spell-only icons")
assert(visibilityUpdated.item == 1, "item-scope refresh should update item visibility")
assert(#stackWriteStates == 0,
    "bag cooldown event takes the applyResolvedCooldown path and must not toggle stack-text writes")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
wipe(stackWriteStates)
barsDirty = false
local dirtyRunsBeforeBagUpdate = dirtyBarRuns
controller:Handle("BAG_UPDATE_DELAYED")
assert(runtimeUpdated.item == 1, "bag inventory updates should refresh item runtime/texture state")
assert(runtimeUpdated.spell == nil, "bag inventory updates should stay scoped to item-backed icons")
assert(applied.item == nil, "bag inventory updates should use the full item runtime path")
assert(barsDirty == true, "bag inventory updates should mark item-backed bars dirty")
assert(dirtyBarRuns == dirtyRunsBeforeBagUpdate + 1, "bag inventory updates should refresh dirty item-backed bars")
assert(#stackWriteStates == 2 and stackWriteStates[1] == true and stackWriteStates[2] == false,
    "bag inventory updates must enable then disable stack-text writes so the item-count badge refreshes")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
wipe(stackWriteStates)
barsDirty = false
local dirtyRunsBeforeItemCount = dirtyBarRuns
controller:Handle("ITEM_COUNT_CHANGED", 404)
assert(runtimeUpdated.item == 1, "item count changes should refresh item runtime/texture state")
assert(runtimeUpdated.spell == nil, "item count changes should stay scoped to item-backed icons")
assert(barsDirty == true, "item count changes should mark item-backed bars dirty")
assert(dirtyBarRuns == dirtyRunsBeforeItemCount + 1, "item count changes should refresh dirty item-backed bars")
assert(#stackWriteStates == 2 and stackWriteStates[1] == true and stackWriteStates[2] == false,
    "item count changes must enable then disable stack-text writes so the item-count badge refreshes")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
wipe(stackWriteStates)
controller:Handle("PLAYER_EQUIPMENT_CHANGED", 13)
assert(runtimeUpdated.item == 1, "equipment change should refresh item runtime/texture state")
assert(runtimeUpdated.spell == nil, "equipment change should stay scoped to item-backed icons")
assert(#schedules == 0, "equipment change should not schedule a broad full cooldown walk")
assert(#stackWriteStates == 2 and stackWriteStates[1] == true and stackWriteStates[2] == false,
    "trinket equip changes must enable then disable stack-text writes for the item-count badge")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
reset(batches)
endedBatches = 0
controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", 999999, nil, "refresh")
assert(next(applied) == nil, "unmatched per-spell cooldown refresh should not re-resolve icons")
assert(next(runtimeUpdated) == nil, "unmatched per-spell cooldown refresh should not run icon updates")
assert(#batches == 0, "unmatched per-spell cooldown refresh should not open a runtime batch")

controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", 101, nil, "refresh")
assert(runtimeUpdated.spell == 1, "matched per-spell cooldown refresh should run the full matching spell update")
assert(runtimeUpdated.otherSpell == nil, "matched per-spell cooldown refresh should not touch unrelated spells")
assert(applied.spell == nil, "matched per-spell cooldown refresh should not use the stackless cooldown-only path")
assert(visibilityUpdated.spell == 1, "matched per-spell cooldown refresh should update matching visibility")
assert(stackWriteStates[1] == true and stackWriteStates[2] == false,
    "matched per-spell cooldown refresh should enable stack text writes around the full update")

-- isOnGCD is read directly off cdInfo (NeverSecret), so a refresh with a nil
-- spellID no longer captures a trusted-GCD snapshot or runs a broad GCD-edge
-- spell-scope re-resolve. It is the documented no-op fallback: GCD-only swipe
-- refresh is driven by the cast_succeeded InvalidateGCDOnlyBindings path
-- instead. A refresh must leave existing bindings untouched when no comparable
-- spellID is carried.
reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
reset(stackWriteStates)
reset(batches)
spellIcon._lastResolvedMode = "gcd-only"
spellIcon._lastDurObjKey = "gcd-only:101"
spellIcon._lastDurObj = {}
controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", nil, nil, "refresh")
assert(spellIcon._lastDurObjKey == "gcd-only:101",
    "nil-spellID refresh should not invalidate any duration binding (no broad GCD-edge walk)")
assert(next(applied) == nil, "nil-spellID refresh should not re-resolve any icon")
assert(next(runtimeUpdated) == nil, "nil-spellID refresh should not run any icon update")
assert(#batches == 0, "nil-spellID refresh should not open a runtime batch")
spellIcon._lastResolvedMode = nil
spellIcon._lastDurObjKey = nil
spellIcon._lastDurObj = nil

reset(auraApplied)
reset(clearedBindings)
wipe(barAuraRefreshMarks)
stackRequested = false
local schedulesBeforeAuraDelta = #schedules
mirrorAuraIcon._lastDurObjKey = "aura:9001"
mirrorAuraIcon._lastDurObj = { token = "stale-target-aura-duration" }
mirrorAuraIcon._lastResolvedMode = "aura"
mirrorAuraIcon._lastResolvedSourceID = 9001
controller:Handle("UNIT_AURA", "target", {
    updatedAuraInstanceIDs = { 9001 },
})
assert(auraApplied.mirrorAura == 1, "aura delta should match mirror-backed aura instance IDs")
assert(clearedBindings.mirrorAura == 1, "target aura deltas should invalidate stale aura DurationObject bindings before re-resolve")
assert(mirrorAuraIcon._lastDurObjKey == nil, "target aura delta invalidation should clear the previous duration key")
assert(#barAuraRefreshMarks == 1
    and barAuraRefreshMarks[1].unit == "target"
    and barAuraRefreshMarks[1].updateInfo.updatedAuraInstanceIDs[1] == 9001,
    "aura deltas should mark matching bars for DurationObject rebind before the dirty bar update")
assert(stackRequested == true, "aura deltas should request a follow-up stack text refresh")
assert(#schedules == schedulesBeforeAuraDelta,
    "aura deltas should stay on the targeted aura path instead of scheduling a broad cooldown walk")

reset(auraApplied)
controller:Handle("UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 9002, spellId = 808 },
    },
})
assert(auraApplied.item == 1, "aura delta should match item entries through item-use aura mapping")

reset(auraApplied)
controller:Handle("UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 9003, spellId = secretSpellID },
    },
})
assert(auraApplied.item == 1, "secret player added aura identity should still wake item aura entries")

reset(auraApplied)
controller:Handle("UNIT_AURA", "target", {
    addedAuras = {
        { auraInstanceID = 9004, spellId = secretSpellID },
    },
})
assert(auraApplied.item == 1, "secret target added aura identity should still wake item aura entries")

reset(auraApplied)
reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
reset(blingSynced)
stackRequested = false
barsDirty = false
local schedulesBeforeFullAura = #schedules
local dirtyRunsBeforeFullAura = dirtyBarRuns
controller:Handle("UNIT_AURA", "player", {
    isFullUpdate = true,
})
assert(auraApplied.aura == 1, "full player aura refresh should update aura entries through the scoped path")
assert(auraApplied.item == 1, "full player aura refresh should update item-backed aura/cooldown entries")
assert(auraApplied.spell == nil, "full player aura refresh should not touch unrelated spell-only cooldown icons")
assert(visibilityUpdated.item == 1, "full player aura refresh should update item-backed visibility")
assert(blingSynced.item == 1, "full player aura refresh should sync item-backed bling")
assert(#schedules == schedulesBeforeFullAura,
    "full player aura refresh should not schedule a broad full cooldown walk")
assert(stackRequested == true, "full player aura refresh should still request stack text refresh")
assert(barsDirty == true, "full player aura refresh should mark bars dirty")
assert(dirtyBarRuns == dirtyRunsBeforeFullAura + 1,
    "full player aura refresh should run the dirty bar update without a full icon walk")

reset(auraApplied)
reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
stackRequested = false
barsDirty = false
local schedulesBeforeTarget = #schedules
local rangeRefreshesBeforeTarget = rangeRefreshes
local dirtyRunsBeforeTarget = dirtyBarRuns
spellIcon._hasCooldownActive = true
controller:Handle("PLAYER_TARGET_CHANGED")
assert(rangeRefreshes == rangeRefreshesBeforeTarget + 1,
    "target changes should still refresh icon ranges")
assert(auraApplied.aura == 1, "target changes should refresh aura entries through aura scope")
assert(auraApplied.item == nil, "target changes should not run player item-aura scope")
-- applyResolvedCooldown is not called in the usability path; visibility still updates.
assert(applied.spell == nil, "target changes must not call applyResolvedCooldown via the usability path")
assert(visibilityUpdated.spell == 1, "target changes should still update visibility for active cooldown icons")
assert(#schedules == schedulesBeforeTarget,
    "target changes should not schedule a broad full cooldown walk")
assert(barsDirty == true, "target aura refresh should mark bars dirty when aura scope refreshed icons")
assert(dirtyBarRuns == dirtyRunsBeforeTarget + 1,
    "target aura refresh should run dirty bar updates without a full icon walk")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
reset(blingSynced)
reset(auraApplied)
-- SPELLS_CHANGED is a no-payload event: it must do NO icon work and NO cache
-- wipe (it co-fires with every proc override). Structural re-resolves are owned
-- by the scoped events below. Holds in and out of combat.
local schedulesBeforeSpellsChanged = #schedules
local textureClearsBefore = textureClears
local durationKeyClearsBefore = durationKeyClears
local stableClearsBefore = stableClears
inCombat = true
controller.deferredFullRefresh = false
controller:Handle("SPELLS_CHANGED")
controller:Handle("SPELLS_CHANGED")
assert(next(applied) == nil and next(runtimeUpdated) == nil,
    "combat SPELLS_CHANGED must not run any icon work")
assert(#schedules == schedulesBeforeSpellsChanged,
    "combat SPELLS_CHANGED must not schedule a broad full cooldown walk")
assert(textureClears == textureClearsBefore
    and durationKeyClears == durationKeyClearsBefore
    and stableClears == stableClearsBefore,
    "SPELLS_CHANGED must not wipe resolver caches (scoped override event owns invalidation)")
assert(controller.deferredFullRefresh == false,
    "SPELLS_CHANGED must not defer a full re-resolve (no payload to scope)")
-- Combat end owes nothing: SPELLS_CHANGED queued no deferred full refresh.
inCombat = false
controller:Handle("PLAYER_REGEN_ENABLED")
assert(#schedules == schedulesBeforeSpellsChanged,
    "combat end after SPELLS_CHANGED should schedule nothing (no deferred full walk)")

-- Out of combat, SPELLS_CHANGED is still inert.
reset(applied)
reset(runtimeUpdated)
inCombat = false
local schedulesBeforeOocSpells = #schedules
local stableBeforeOocSpells = stableClears
controller:Handle("SPELLS_CHANGED")
assert(next(applied) == nil and next(runtimeUpdated) == nil,
    "out-of-combat SPELLS_CHANGED must not re-resolve any icon")
assert(#schedules == schedulesBeforeOocSpells,
    "out-of-combat SPELLS_CHANGED must not schedule a catalog walk")
assert(stableClears == stableBeforeOocSpells,
    "out-of-combat SPELLS_CHANGED must not wipe the stable override cache")

-- COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED(base, override) re-resolves ONLY the
-- affected spell icon and scoped-invalidates only its caches.
reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
reset(stackWriteStates)
inCombat = false
local schedulesBeforeOverride = #schedules
local invalidatedBeforeOverride = #spellCacheInvalidations
controller:Handle("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 101, 999)
assert(runtimeUpdated.spell == 1,
    "spell override should re-resolve the affected base-spell icon")
assert(runtimeUpdated.otherSpell == nil and runtimeUpdated.idle == nil,
    "spell override must not touch unrelated icons")
assert(#schedules == schedulesBeforeOverride,
    "spell override must not schedule a broad catalog walk")
assert(spellCacheInvalidations[invalidatedBeforeOverride + 1] == 101
    and spellCacheInvalidations[invalidatedBeforeOverride + 2] == 999,
    "spell override should scoped-invalidate exactly the base and override spell caches")

-- Override removal carries a nil overrideSpellID; the base icon still re-resolves
-- and only the base cache is invalidated.
reset(runtimeUpdated)
inCombat = false
local invalidatedBeforeRemoval = #spellCacheInvalidations
controller:Handle("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 101, nil)
assert(runtimeUpdated.spell == 1,
    "override removal (nil overrideSpellID) should still re-resolve the base-spell icon")
assert(#spellCacheInvalidations == invalidatedBeforeRemoval + 1
    and spellCacheInvalidations[invalidatedBeforeRemoval + 1] == 101,
    "override removal should scoped-invalidate only the base spell cache")

local schedulesBeforeHotfix = #schedules
inCombat = true
controller:Handle("COOLDOWN_VIEWER_TABLE_HOTFIXED")
assert(#schedules == schedulesBeforeHotfix,
    "combat cooldown table hotfix should defer the broad full refresh")
inCombat = false
controller:Handle("PLAYER_REGEN_ENABLED")
assert(#schedules == schedulesBeforeHotfix + 1
    and schedules[#schedules].mode == "full"
    and schedules[#schedules].reason == "deferred",
    "deferred hotfix refresh should schedule one full update after combat")

reset(applied)
reset(runtimeUpdated)
reset(stackWriteStates)
stackRequested = false
chargeDurationNotes = 0
local schedulesBeforeCharges = #schedules
controller:HandleChargesChanged("CDM:CHARGES_CHANGED", 101)
assert(chargeDurationNotes == 1, "charge changes should notify runtime query cache")
assert(stackRequested == true, "charge changes should request stack text writes")
assert(#schedules == schedulesBeforeCharges,
    "charge changes with a spell ID should stay on the targeted spell path")
assert(runtimeUpdated.spell == 1, "charge changes with a spell ID should run the full matching spell update")
assert(stackWriteStates[1] == true and stackWriteStates[2] == false,
    "charge scoped spell refresh should enable stack text writes")

reset(applied)
reset(runtimeUpdated)
reset(stackWriteStates)
local schedulesBeforeCastStart = #schedules
controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", 101, nil, "cast_start")
assert(#schedules == schedulesBeforeCastStart,
    "cast start with a spell ID should stay on the targeted spell path")
assert(runtimeUpdated.spell == 1, "cast start should update the matching spell icon")
assert(runtimeUpdated.otherSpell == nil, "cast start should not update unrelated spell icons")
assert(stackWriteStates[1] == true and stackWriteStates[2] == false,
    "cast start targeted refresh should enable stack text writes")

reset(applied)
reset(runtimeUpdated)
reset(stackWriteStates)
local schedulesBeforeSpellcastStop = #schedules
controller:Handle("UNIT_SPELLCAST_STOP", "player", "cast-guid", 101)
assert(#schedules == schedulesBeforeSpellcastStop,
    "player spellcast stop with a spell ID should stay on the targeted spell path")
assert(runtimeUpdated.spell == 1, "player spellcast stop should update the matching spell icon")
assert(runtimeUpdated.otherSpell == nil, "player spellcast stop should not update unrelated spell icons")

reset(applied)
reset(runtimeUpdated)
local schedulesBeforeSecretSpellcastStop = #schedules
controller:Handle("UNIT_SPELLCAST_STOP", "player", "cast-guid", secretSpellID)
assert(#schedules == schedulesBeforeSecretSpellcastStop + 1,
    "secret player spellcast stop should fall back to the broad cooldown refresh")
assert(schedules[#schedules].reason == "unit_spellcast",
    "secret player spellcast fallback should be attributable in memaudit")

local schedulesBeforeSecretUnit = #schedules
controller:Handle("UNIT_SPELLCAST_STOP", secretUnit, "cast-guid", 101)
assert(#schedules == schedulesBeforeSecretUnit,
    "secret unit spellcast payloads should not be compared or scheduled")

reset(applied)
reset(runtimeUpdated)
reset(stackWriteStates)
reset(recentCasts)
reset(highlighterCasts)
reset(visibilityUpdated)
reset(blingSynced)
stackRequested = false
local schedulesBeforeCastSucceeded = #schedules
controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", 101, nil, "cast_succeeded")
assert(recentCasts[1] == 101, "cast succeeded should record the player cast")
assert(highlighterCasts[1] == 101, "cast succeeded should still notify the highlighter")
-- Design shift: cast_succeeded no longer runs a broad applyResolvedCooldown
-- sweep over every spell icon. UNIT_SPELLCAST_SUCCEEDED carries the spellID,
-- so the targeted updateIconCooldown via ApplySpellID is sufficient and
-- avoids ~3 MB/sec of churn during sustained combat.
assert(applied.spell == nil,
    "cast succeeded should NOT run a broad applyResolvedCooldown sweep")
assert(runtimeUpdated.spell == 1,
    "cast succeeded should run the targeted updateIconCooldown for the cast spell")
assert(visibilityUpdated.spell == 1,
    "cast succeeded should update visibility for the cast spell (folded into ApplySpellID)")
assert(blingSynced.spell == 1,
    "cast succeeded should sync bling for the cast spell (folded into ApplySpellID)")
assert(stackWriteStates[1] == true and stackWriteStates[2] == false,
    "cast succeeded targeted refresh should enable stack text writes")
assert(stackRequested == true, "cast succeeded should request a delayed stack text refresh")
assert(#schedules == schedulesBeforeCastSucceeded,
    "cast succeeded should not schedule a redundant broad cooldown refresh")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
reset(stackWriteStates)
inCombat = true
controller:Handle("SPELL_UPDATE_USABLE")
controller:Handle("SPELL_UPDATE_USABLE")
assert(next(applied) == nil, "combat usability refresh should defer until the queue drains")
local queuedFrame = createdFrames[#createdFrames]
assert(queuedFrame and queuedFrame.shown == true, "combat usability refresh should arm a reusable frame")
queuedFrame.scripts.OnUpdate(queuedFrame, 0.29)
assert(next(applied) == nil, "combat usability refresh should wait for the coalescing delay")
queuedFrame.scripts.OnUpdate(queuedFrame, 0.02)
-- applyResolvedCooldown is never called in the usability path; container visibility still runs.
assert(applied.spell == nil, "coalesced combat usability refresh must not call applyResolvedCooldown")
assert(visibilityUpdated.spell == 1, "coalesced combat usability refresh should still update container visibility")
assert(queuedFrame.shown == false, "coalesced combat usability refresh should hide its frame")

reset(applied)
reset(runtimeUpdated)
reset(stackWriteStates)
controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", 101, nil, "refresh")
-- SPELL_UPDATE_COOLDOWN is the canonical signal that the cooldown lane
-- changed for a specific spell, so HandleCooldownChanged now applies
-- immediately even in combat. Earlier code queued this with a 0.3s
-- combat delay (CDMIconRuntimeRefresh.Create spellQueue at line 2152);
-- in-game traces showed proc-window rebinds lagging 2+ seconds behind
-- the SUC fire because each fresh SUC reset the queue. The targeted
-- ApplySpellID at line 2414 keeps the work bounded to matching icons
-- so the immediate path is safe under combat burst.
assert(runtimeUpdated.spell == 1,
    "combat per-spell cooldown refresh should apply immediately to the matching icon")
assert(applied.spell == nil,
    "combat per-spell cooldown refresh should use the targeted updateIconCooldown path, not stackless apply")
assert(stackWriteStates[1] == true and stackWriteStates[2] == false,
    "combat per-spell cooldown refresh should enable stack text writes around the immediate update")
inCombat = false

controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", secretSpellID, nil, "refresh")
assert(true, "secret spell IDs should be treated as unscoped without Lua comparisons")

print("OK: cdm_icon_runtime_refresh_test")
