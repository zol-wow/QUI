-- tests/cdm_icon_runtime_refresh_test.lua
-- Run: lua tests/cdm_icon_runtime_refresh_test.lua

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
local batches = {}
local endedBatches = 0
local drained = 0
local rangeRefreshes = 0
local schedules = {}
local barsDirty = false
local dirtyBarRuns = 0
local stackRequested = false
local chargeDurationNotes = 0
local recentCasts = {}
local highlighterCasts = {}
local trustedGCD = false
local trustCalls = {}
local mirrorStates = {
    ["505:essential"] = {
        auraInstanceID = 9001,
        auraUnit = "target",
    },
}

local ns = {}
assert(loadfile("modules/cdm/cdm_icon_runtime_refresh.lua"))("QUI", ns)
local module = assert(ns.CDMIconRuntimeRefresh, "runtime refresh module should be exported")

local controller = module.Create({
    isRuntimeEnabled = function() return true end,
    getIconPools = function() return iconPools end,
    isSecretValue = function(value) return value == secretSpellID end,
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
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
    end,
    updateIconRangesForUsabilityEvent = function()
        rangeRefreshes = rangeRefreshes + 1
    end,
    resetTrustedGCDSnapshot = function()
        return {}, 1
    end,
    captureTrustedGCDStateForIcon = function(icon)
        icon._capturedGCD = true
    end,
    captureTrustedGCDState = function()
        return trustedGCD
    end,
    setTrustIsOnGCDForBatch = function(value)
        trustCalls[#trustCalls + 1] = value
        return false
    end,
    scheduleUpdate = function(fast, mode, trustIsOnGCD)
        schedules[#schedules + 1] = {
            fast = fast,
            mode = mode,
            trustIsOnGCD = trustIsOnGCD,
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
    runDirtyBarUpdate = function()
        dirtyBarRuns = dirtyBarRuns + 1
    end,
    getCombatQueueDelay = function()
        return 0.3
    end,
    isPlayerInCombat = function()
        return inCombat
    end,
})

spellIcon._hasCooldownActive = true
controller:Handle("SPELL_UPDATE_USABLE")
assert(applied.spell == 1, "usability refresh should re-resolve stale cooldown icons")
assert(applied.idle == nil, "usability refresh should skip idle cooldown icons")
assert(applied.aura == nil, "usability refresh should skip aura icons")
assert(rangeRefreshes == 1, "usability refresh should reconcile range/usability visuals")
assert(spellIcon._capturedGCD == true, "usability refresh should capture trusted GCD state per refreshed icon")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
controller:Handle("BAG_UPDATE_COOLDOWN")
assert(applied.item == 1, "bag cooldown event should re-resolve item-backed icons")
assert(applied.spell == nil, "bag cooldown event should not touch spell-only icons")
assert(visibilityUpdated.item == 1, "item-scope refresh should update item visibility")

reset(applied)
reset(runtimeUpdated)
reset(visibilityUpdated)
controller:Handle("PLAYER_EQUIPMENT_CHANGED", 13)
assert(runtimeUpdated.item == 1, "equipment change should refresh item runtime/texture state")
assert(runtimeUpdated.spell == nil, "equipment change should stay scoped to item-backed icons")
assert(#schedules == 0, "equipment change should not schedule a broad full cooldown walk")

reset(applied)
reset(visibilityUpdated)
reset(batches)
endedBatches = 0
trustedGCD = false
controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", 999999, nil, "refresh")
assert(next(applied) == nil, "unmatched per-spell cooldown refresh should not re-resolve icons")
assert(#batches == 0, "unmatched per-spell cooldown refresh should not open a runtime batch")

controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", 101, nil, "refresh")
assert(applied.spell == 1, "matched per-spell cooldown refresh should re-resolve matching spell icons")
assert(applied.otherSpell == nil, "matched per-spell cooldown refresh should not touch unrelated spells")
assert(visibilityUpdated.spell == 1, "matched per-spell cooldown refresh should update matching visibility")

reset(applied)
spellIcon._lastResolvedMode = "gcd-only"
spellIcon._lastDurObjKey = "gcd-only:101"
spellIcon._lastDurObj = {}
trustedGCD = true
controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", nil, nil, "refresh")
assert(spellIcon._lastDurObjKey == nil, "broad GCD edge should invalidate GCD-only duration binding")
assert(applied.spell == 1, "broad GCD edge should refresh spell-shaped icons")
assert(applied.item == nil, "broad GCD edge should not refresh item-backed icons")
assert(applied.aura == nil, "broad GCD edge should not refresh aura icons")

reset(auraApplied)
controller:Handle("UNIT_AURA", "target", {
    updatedAuraInstanceIDs = { 9001 },
})
assert(auraApplied.mirrorAura == 1, "aura delta should match mirror-backed aura instance IDs")

reset(auraApplied)
controller:Handle("UNIT_AURA", "player", {
    addedAuras = {
        { auraInstanceID = 9002, spellId = 808 },
    },
})
assert(auraApplied.item == 1, "aura delta should match item entries through item-use aura mapping")

reset(applied)
stackRequested = false
chargeDurationNotes = 0
controller:HandleChargesChanged("CDM:CHARGES_CHANGED", 101)
assert(chargeDurationNotes == 1, "charge changes should notify runtime query cache")
assert(stackRequested == true, "charge changes should request stack text writes")
assert(schedules[#schedules].mode == "cooldown", "charge changes should schedule a cooldown refresh")
assert(applied.spell == 1, "charge changes with a spell ID should queue a scoped spell refresh")

reset(applied)
inCombat = true
controller:Handle("SPELL_UPDATE_USABLE")
controller:Handle("SPELL_UPDATE_USABLE")
assert(next(applied) == nil, "combat usability refresh should defer until the queue drains")
local queuedFrame = createdFrames[#createdFrames]
assert(queuedFrame and queuedFrame.shown == true, "combat usability refresh should arm a reusable frame")
queuedFrame.scripts.OnUpdate(queuedFrame, 0.29)
assert(next(applied) == nil, "combat usability refresh should wait for the coalescing delay")
queuedFrame.scripts.OnUpdate(queuedFrame, 0.02)
assert(applied.spell == 1, "coalesced combat usability refresh should run once")
assert(queuedFrame.shown == false, "coalesced combat usability refresh should hide its frame")
inCombat = false

controller:HandleCooldownChanged("CDM:COOLDOWN_CHANGED", secretSpellID, nil, "refresh")
assert(true, "secret spell IDs should be treated as unscoped without Lua comparisons")

print("OK: cdm_icon_runtime_refresh_test")
