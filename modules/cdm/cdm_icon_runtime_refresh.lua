local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Runtime Refresh
--
-- Private controller for CDMIcons event/runtime refresh dispatch. CDMIcons
-- owns renderer callbacks; this module owns the event branching shape,
-- scoped icon walking, and combat refresh queues.
---------------------------------------------------------------------------

local CDMIconRuntimeRefresh = {}
ns.CDMIconRuntimeRefresh = CDMIconRuntimeRefresh

local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local next = next

local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local UPDATE_COOLDOWN = "cooldown"
local UPDATE_FULL = "full"

local function isRuntimeEnabled(callbacks)
    return not callbacks.isRuntimeEnabled or callbacks.isRuntimeEnabled() ~= false
end

local function normalizeSpellIdentifier(callbacks, value)
    if value == nil then return nil end
    if callbacks.isSecretValue and callbacks.isSecretValue(value) then return nil end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return value
    end
    return nil
end

local function addSpellIdentifierToSet(callbacks, set, rawID)
    if not set then return false end
    local normalized = normalizeSpellIdentifier(callbacks, rawID)
    if normalized == nil then return false end

    set[normalized] = true
    if type(normalized) == "string" then
        local numeric = tonumber(normalized)
        if numeric then set[numeric] = true end
    end
    return true
end

local function spellIdentifierSetHas(callbacks, set, rawID)
    if not set then return false end
    local normalized = normalizeSpellIdentifier(callbacks, rawID)
    if normalized == nil then return false end
    if set[normalized] == true then return true end

    if type(normalized) == "string" then
        local numeric = tonumber(normalized)
        return numeric and set[numeric] == true or false
    end
    return false
end

local function spellIDIsGCD(callbacks, spellID)
    local normalized = normalizeSpellIdentifier(callbacks, spellID)
    if normalized == nil then return false end
    local gcdSpellID = callbacks.gcdSpellID or 61304
    if normalized == gcdSpellID then return true end
    if type(normalized) == "string" then
        return tonumber(normalized) == gcdSpellID
    end
    return false
end

local function getIconPools(callbacks)
    return (callbacks.getIconPools and callbacks.getIconPools()) or {}
end

local function isAuraEntry(callbacks, entry)
    return callbacks.isAuraEntry and callbacks.isAuraEntry(entry) or false
end

local function isItemEntry(entry)
    local entryType = entry and entry.type
    return entryType == "item" or entryType == "trinket" or entryType == "slot"
end

local function resolveContainer(callbacks, entry, ncdm, ncdmContainers)
    if callbacks.resolveContainerDBAndType then
        return callbacks.resolveContainerDBAndType(entry, ncdm, ncdmContainers)
    end
    return nil, nil
end

local function beginBatch(callbacks, reason)
    local editMode, ncdm, ncdmContainers, inCombat
    if callbacks.prepareBatch then
        editMode, ncdm, ncdmContainers, inCombat = callbacks.prepareBatch()
    end
    if callbacks.beginBatch then
        callbacks.beginBatch(reason)
    end
    return editMode, ncdm, ncdmContainers, inCombat
end

local function endBatch(callbacks)
    if callbacks.endBatch then
        callbacks.endBatch()
    end
end

local function entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs)
    if not hasSpellIDs or not entry then return false end
    if spellIdentifierSetHas(callbacks, spellIDs, icon and icon._runtimeSpellID) then return true end
    if spellIdentifierSetHas(callbacks, spellIDs, entry.overrideSpellID) then return true end
    if spellIdentifierSetHas(callbacks, spellIDs, entry.spellID) then return true end
    if spellIdentifierSetHas(callbacks, spellIDs, entry.id) then return true end

    local linked = entry.linkedSpellIDs
    if type(linked) == "table" then
        for _, linkedID in ipairs(linked) do
            if spellIdentifierSetHas(callbacks, spellIDs, linkedID) then return true end
        end
    end
    return false
end

local function itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs)
    if not hasSpellIDs or not (entry and callbacks.queryItemSpell) then return false end
    local itemID = callbacks.getItemIDForEntry and callbacks.getItemIDForEntry(entry)
    if normalizeSpellIdentifier(callbacks, itemID) == nil then return false end

    local _, itemSpellID = callbacks.queryItemSpell(itemID)
    itemSpellID = normalizeSpellIdentifier(callbacks, itemSpellID)
    if not itemSpellID then return false end
    if spellIdentifierSetHas(callbacks, spellIDs, itemSpellID) then return true end

    if callbacks.queryCooldownAuraBySpellID then
        local auraSpellID = callbacks.queryCooldownAuraBySpellID(itemSpellID)
        return spellIdentifierSetHas(callbacks, spellIDs, auraSpellID)
    end
    return false
end

function CDMIconRuntimeRefresh.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        auraDeltaInstanceIDs = {},
        auraDeltaSpellIDs = {},
        spellQueue = {
            ids = {},
            frame = nil,
            elapsed = 0,
            scheduled = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
        usabilityQueue = {
            frame = nil,
            elapsed = 0,
            scheduled = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
        itemQueue = {
            frame = nil,
            elapsed = 0,
            scheduled = false,
            refreshRuntime = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
    }

    local function inCombat()
        if callbacks.isPlayerInCombat then
            return callbacks.isPlayerInCombat() == true
        end
        return InCombatLockdown and InCombatLockdown() or false
    end

    local function armQueue(state, onUpdate)
        state.scheduled = true
        state.elapsed = 0
        if not state.frame then
            state.frame = CreateFrame("Frame")
            if state.frame.Hide then state.frame:Hide() end
        end
        state.frame:SetScript("OnUpdate", onUpdate)
        if state.frame.Show then state.frame:Show() end
    end

    local function disarmQueue(state)
        state.scheduled = false
        state.elapsed = 0
        if state.frame then
            state.frame:SetScript("OnUpdate", nil)
            if state.frame.Hide then state.frame:Hide() end
        end
    end

    function controller:AddSpellIdentifierToSet(set, rawID)
        return addSpellIdentifierToSet(callbacks, set, rawID)
    end

    function controller:SpellIdentifierSetHas(set, rawID)
        return spellIdentifierSetHas(callbacks, set, rawID)
    end

    function controller:EntryMatchesSpellIdentifierSet(icon, entry, spellIDs, hasSpellIDs)
        return entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs)
    end

    function controller:ItemEntryMatchesAuraSpellIdentifierSet(entry, spellIDs, hasSpellIDs)
        return itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs)
    end

    function controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
        if callbacks.applyAuraScopedResolvedCooldown then
            return callbacks.applyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
        end
        if callbacks.applyResolvedCooldown then
            callbacks.applyResolvedCooldown(icon)
            return true
        end
        return false
    end

    function controller:ApplyAuraScope()
        local editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "auraScope")
        local refreshed = 0
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and (isAuraEntry(callbacks, entry) or icon._auraActive == true) then
                    if controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState) then
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        endBatch(callbacks)
        return refreshed
    end

    function controller:ApplyItemScope(options)
        options = options or {}
        local batchStarted = false
        local refreshed = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if isItemEntry(entry) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "itemScope")
                        batchStarted = true
                    end
                    if options.refreshRuntime and callbacks.updateIconCooldown then
                        callbacks.updateIconCooldown(icon)
                    elseif callbacks.applyResolvedCooldown then
                        callbacks.applyResolvedCooldown(icon)
                    end
                    local containerDB = select(1, resolveContainer(callbacks, entry, ncdm, ncdmContainers))
                    if callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                    end
                    if callbacks.syncCooldownBling then
                        callbacks.syncCooldownBling(icon)
                    end
                    refreshed = true
                end
            end
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:ApplySpellScope()
        local batchStarted = false
        local refreshed = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and not isAuraEntry(callbacks, entry) and not isItemEntry(entry) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellScope")
                        batchStarted = true
                    end
                    if callbacks.applyResolvedCooldown then
                        callbacks.applyResolvedCooldown(icon)
                    end
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" and callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                    end
                    if callbacks.syncCooldownBling then
                        callbacks.syncCooldownBling(icon)
                    end
                    refreshed = true
                end
            end
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:InvalidateGCDOnlyBindings()
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local lk = icon and icon._lastDurObjKey
                if icon
                    and (icon._lastResolvedMode == "gcd-only"
                        or (type(lk) == "string" and lk:sub(1, 9) == "gcd-only:")) then
                    if callbacks.clearDurationBinding then
                        callbacks.clearDurationBinding(icon)
                    else
                        icon._lastDurObjKey = nil
                        icon._lastDurObj = nil
                        icon._lastResolvedMode = nil
                        icon._lastResolvedSourceID = nil
                        icon._lastResolvedSpellID = nil
                    end
                end
            end
        end
    end

    function controller:InvalidateSpellCooldownBinding(spellID)
        local ids = {}
        if not addSpellIdentifierToSet(callbacks, ids, spellID) then return end
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                local lk = icon and icon._lastDurObjKey
                if entry and lk and entryMatchesSpellIdentifierSet(callbacks, icon, entry, ids, true) then
                    local mode = icon._lastResolvedMode
                    local isCooldownKey = mode == "cooldown"
                        or mode == "charge"
                        or mode == "gcd-only"
                        or mode == "item-cooldown"
                    if not isCooldownKey and type(lk) == "string" then
                        isCooldownKey = lk:sub(1, 9) == "cooldown:"
                            or lk:sub(1, 7) == "charge:"
                            or lk:sub(1, 9) == "gcd-only:"
                            or lk:sub(1, 14) == "item-cooldown:"
                    end
                    if isCooldownKey then
                        if callbacks.clearDurationBinding then
                            callbacks.clearDurationBinding(icon)
                        else
                            icon._lastDurObjKey = nil
                            icon._lastDurObj = nil
                            icon._lastResolvedMode = nil
                            icon._lastResolvedSourceID = nil
                            icon._lastResolvedSpellID = nil
                        end
                    end
                end
            end
        end
    end

    function controller:ApplySpellID(eventSpellID, eventBaseSpellID)
        local spellIDs = {}
        local hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventSpellID)
        hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventBaseSpellID) or hasSpellIDs
        if not hasSpellIDs then return false end

        local batchStarted = false
        local refreshed = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellID")
                        batchStarted = true
                    end
                    local _, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if isAuraEntry(callbacks, entry) or cType == "aura" or cType == "auraBar" then
                        controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
                    elseif callbacks.applyResolvedCooldown then
                        callbacks.applyResolvedCooldown(icon)
                    end
                    refreshed = true
                end
            end
        end
        if batchStarted then
            endBatch(callbacks)
        end
        return refreshed
    end

    function controller:ApplyAuraInstances(unit, updateInfo)
        if not updateInfo or updateInfo.isFullUpdate then return nil end

        local ids = controller.auraDeltaInstanceIDs
        wipe(ids)
        local hasIDs = false

        local spellIDs = controller.auraDeltaSpellIDs
        wipe(spellIDs)
        local hasSpellIDs = false

        if updateInfo.addedAuras then
            for _, auraData in ipairs(updateInfo.addedAuras) do
                local auraInstanceID = auraData and auraData.auraInstanceID
                if auraInstanceID ~= nil then
                    ids[auraInstanceID] = true
                    hasIDs = true
                end
                if auraData then
                    hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, auraData.spellId) or hasSpellIDs
                    hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, auraData.spellID) or hasSpellIDs
                end
            end
        end
        if updateInfo.updatedAuraInstanceIDs then
            for _, auraInstanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if auraInstanceID ~= nil then
                    ids[auraInstanceID] = true
                    hasIDs = true
                end
            end
        end
        if updateInfo.removedAuraInstanceIDs then
            for _, auraInstanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
                if auraInstanceID ~= nil then
                    ids[auraInstanceID] = true
                    hasIDs = true
                end
            end
        end

        if not hasIDs and not hasSpellIDs then return 0 end

        local refreshed = 0
        local batchStarted = false
        local editMode, ncdm, ncdmContainers, inCombatState
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                local iconAuraInstanceID = icon and icon._auraInstanceID
                local matches = iconAuraInstanceID
                    and ids[iconAuraInstanceID]
                    and (not unit or icon._auraUnit == unit)
                if not matches and icon and icon._blizzMirrorCooldownID and callbacks.getMirrorStateByCooldownID then
                    local state = callbacks.getMirrorStateByCooldownID(icon._blizzMirrorCooldownID, icon._blizzMirrorCategory)
                    local mirrorAuraInstanceID = state and state.auraInstanceID
                    matches = mirrorAuraInstanceID
                        and ids[mirrorAuraInstanceID]
                        and (not unit or state.auraUnit == unit or icon._auraUnit == unit)
                end
                if not matches
                    and entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    matches = true
                end
                if not matches
                    and itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs) then
                    matches = true
                end
                if matches and entry then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "auraDelta")
                        batchStarted = true
                    end
                    if controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState) then
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        if batchStarted then
            endBatch(callbacks)
        end

        return refreshed
    end

    function controller:IconNeedsUsabilityCooldownRefresh(icon)
        local entry = icon and icon._spellEntry
        if not entry then return false end
        if isAuraEntry(callbacks, entry) then return false end
        if entry.kind == "aura" or entry.kind == "auraBar" then return false end
        if isItemEntry(entry) then return false end
        if icon._hasCooldownActive == true or icon._hasRealCooldownActive == true then return true end
        if icon._showingRealCooldownSwipe or icon._showingGCDSwipe then return true end
        if icon._lastDurObjKey ~= nil or icon._cooldownExpiryTimerKey ~= nil then return true end
        if icon._isOnGCD ~= nil or icon._cdDesaturated then return true end
        return false
    end

    function controller:ApplyUsabilityRefresh()
        local refreshed = 0
        local spellState, stamp
        local editMode, ncdm, ncdmContainers, inCombatState
        local previousTrust
        local batchStarted = false
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and controller:IconNeedsUsabilityCooldownRefresh(icon) then
                    if not batchStarted then
                        if callbacks.resetTrustedGCDSnapshot then
                            spellState, stamp = callbacks.resetTrustedGCDSnapshot()
                        end
                        if callbacks.prepareBatch then
                            editMode, ncdm, ncdmContainers, inCombatState = callbacks.prepareBatch()
                        end
                        if callbacks.setTrustIsOnGCDForBatch then
                            previousTrust = callbacks.setTrustIsOnGCDForBatch(true)
                        end
                        if callbacks.beginBatch then
                            callbacks.beginBatch("usability")
                        end
                        batchStarted = true
                    end
                    if callbacks.captureTrustedGCDStateForIcon then
                        callbacks.captureTrustedGCDStateForIcon(icon, spellState, stamp)
                    end
                    if callbacks.applyResolvedCooldown then
                        callbacks.applyResolvedCooldown(icon)
                    end

                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" and callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                    end
                    refreshed = refreshed + 1
                end
            end
        end

        if batchStarted then
            endBatch(callbacks)
            if callbacks.setTrustIsOnGCDForBatch then
                callbacks.setTrustIsOnGCDForBatch(previousTrust)
            end
        end
        if refreshed > 0 and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:RunUsabilityRefresh()
        controller:ApplyUsabilityRefresh()
        if callbacks.updateIconRangesForUsabilityEvent then
            callbacks.updateIconRangesForUsabilityEvent()
        end
    end

    function controller:RefreshCooldownVisualsForSpellID(eventSpellID, eventBaseSpellID)
        local spellIDs = {}
        local hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventSpellID)
        hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventBaseSpellID) or hasSpellIDs
        if not hasSpellIDs then return false end

        local editMode, ncdm, ncdmContainers, inCombatState
        if callbacks.prepareBatch then
            editMode, ncdm, ncdmContainers, inCombatState = callbacks.prepareBatch()
        end
        local refreshed = false

        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" and callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                        refreshed = true
                    end
                end
            end
        end

        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end

        return refreshed
    end

    local function drainSpellQueue()
        local state = controller.spellQueue
        disarmQueue(state)
        if next(state.ids) == nil then return end

        local editMode, ncdm, ncdmContainers, inCombatState
        local refreshed = false
        local batchStarted = false
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entryMatchesSpellIdentifierSet(callbacks, icon, entry, state.ids, true) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellID")
                        batchStarted = true
                    end
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if isAuraEntry(callbacks, entry) or cType == "aura" or cType == "auraBar" then
                        controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
                    else
                        if callbacks.applyResolvedCooldown then
                            callbacks.applyResolvedCooldown(icon)
                        end
                        if callbacks.updateContainerVisibility then
                            callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                        end
                    end
                    refreshed = true
                end
            end
        end
        if batchStarted then
            endBatch(callbacks)
        end
        wipe(state.ids)

        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
    end

    local function spellQueueOnUpdate(_, elapsed)
        local state = controller.spellQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainSpellQueue()
    end

    function controller:QueueResolvedCooldownForSpellID(eventSpellID, eventBaseSpellID)
        if not inCombat() then
            controller:ApplySpellID(eventSpellID, eventBaseSpellID)
            controller:RefreshCooldownVisualsForSpellID(eventSpellID, eventBaseSpellID)
            return
        end

        local state = controller.spellQueue
        local added = addSpellIdentifierToSet(callbacks, state.ids, eventSpellID)
        added = addSpellIdentifierToSet(callbacks, state.ids, eventBaseSpellID) or added
        if not added then return end

        if state.scheduled then return end
        armQueue(state, spellQueueOnUpdate)
    end

    local function drainUsabilityQueue()
        disarmQueue(controller.usabilityQueue)
        controller:RunUsabilityRefresh()
    end

    local function usabilityQueueOnUpdate(_, elapsed)
        local state = controller.usabilityQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainUsabilityQueue()
    end

    function controller:QueueUsabilityRefresh()
        if not inCombat() then
            controller:RunUsabilityRefresh()
            return
        end

        local state = controller.usabilityQueue
        if state.scheduled then return end
        armQueue(state, usabilityQueueOnUpdate)
    end

    local function drainItemQueue()
        local state = controller.itemQueue
        local refreshRuntime = state.refreshRuntime == true
        state.refreshRuntime = false
        disarmQueue(state)
        controller:ApplyItemScope({ refreshRuntime = refreshRuntime })
    end

    local function itemQueueOnUpdate(_, elapsed)
        local state = controller.itemQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainItemQueue()
    end

    function controller:QueueItemScopeRefresh(options)
        options = options or {}
        if not inCombat() then
            controller:ApplyItemScope(options)
            return
        end

        local state = controller.itemQueue
        if options.refreshRuntime then
            state.refreshRuntime = true
        end
        if state.scheduled then return end
        armQueue(state, itemQueueOnUpdate)
    end

    function controller:NoteChargeDurationObjectsUpdated()
        if callbacks.noteChargeDurationObjectsUpdated then
            callbacks.noteChargeDurationObjectsUpdated()
        end
    end

    function controller:HandleAuraRefresh(unit, updateInfo)
        if not isRuntimeEnabled(callbacks) then return end
        if callbacks.eventTracePrint then
            callbacks.eventTracePrint("aura-pre", "UNIT_AURA", unit, nil, nil,
                callbacks.eventTraceAuraInfo and callbacks.eventTraceAuraInfo(updateInfo))
        end

        if not updateInfo or updateInfo.isFullUpdate then
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            if callbacks.scheduleFullUpdate then callbacks.scheduleFullUpdate() end
            controller:ApplyAuraScope()
        else
            local refreshed = controller:ApplyAuraInstances(unit, updateInfo) or 0
            if refreshed > 0 then
                if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
                if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
            end
        end

        if callbacks.eventTracePrint then
            callbacks.eventTracePrint("aura-post", "UNIT_AURA", unit, nil, nil,
                callbacks.eventTraceAuraInfo and callbacks.eventTraceAuraInfo(updateInfo))
        end
    end

    function controller:HandleFrameEvent(frame, event, arg1, arg2, arg3)
        if not isRuntimeEnabled(callbacks) then
            if callbacks.onRuntimeDisabled then
                callbacks.onRuntimeDisabled(frame)
            end
            return
        end

        if event == "UNIT_SPELLCAST_STOP"
           or event == "UNIT_SPELLCAST_CHANNEL_START"
           or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if arg1 == "player" and callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN)
            end
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then
            if callbacks.chargeDebug then
                callbacks.chargeDebug(nil, "EVENT", event, "full-refresh")
            end
            if callbacks.updateAllIconRanges then
                callbacks.updateAllIconRanges()
            end
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_FULL)
            end
            return
        end
        if event == "PLAYER_SOFT_ENEMY_CHANGED" then
            if callbacks.chargeDebug then
                callbacks.chargeDebug(nil, "EVENT", event, "full-refresh")
            end
            if callbacks.updateAllIconRanges then
                callbacks.updateAllIconRanges()
            end
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_FULL)
            end
            return
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            if arg1 == 13 or arg1 == 14 then
                controller:QueueItemScopeRefresh({ refreshRuntime = true })
            end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            return
        end
        if event == "UPDATE_MACROS" then
            if callbacks.invalidateMacroCache then
                callbacks.invalidateMacroCache()
            end
            return
        end
        if event == "SPELL_RANGE_CHECK_UPDATE" then
            if callbacks.updateIconsForSpellRangeEvent then
                callbacks.updateIconsForSpellRangeEvent(arg1, arg2, arg3)
            end
            return
        end
        if event == "SPELL_UPDATE_USABLE" then
            controller:QueueUsabilityRefresh()
            return
        end
        if event == "SPELLS_CHANGED" then
            if callbacks.clearTextureCycleCache then
                callbacks.clearTextureCycleCache()
            end
            if callbacks.clearDurationBindingKeyCache then
                callbacks.clearDurationBindingKeyCache()
            end
            if callbacks.clearStableCaches then
                callbacks.clearStableCaches()
            end
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_FULL)
            end
            return
        end
        if event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_FULL)
            end
            return
        end
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
           or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            if arg1 then
                controller:QueueResolvedCooldownForSpellID(arg1, nil)
            end
            return
        end
        if event == "BAG_UPDATE_COOLDOWN" then
            controller:QueueItemScopeRefresh()
            return
        end
    end

    function controller:Handle(event, arg1, arg2, arg3, frame)
        if event == "UNIT_AURA" then
            return controller:HandleAuraRefresh(arg1, arg2)
        end
        return controller:HandleFrameEvent(frame, event, arg1, arg2, arg3)
    end

    function controller:HandleCooldownChanged(_, spellID, baseSpellID, kind)
        if not isRuntimeEnabled(callbacks) then return end
        if kind == "scanner_item" then
            controller:ApplyItemScope()
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
        elseif kind == "scanner_spell" then
            controller:ApplySpellScope()
        elseif kind == "refresh" then
            local gcdChanged = callbacks.captureTrustedGCDState and callbacks.captureTrustedGCDState() or false
            local comparableSpellID = normalizeSpellIdentifier(callbacks, spellID) ~= nil
            local spellIDIsGCDSpell = comparableSpellID and spellIDIsGCD(callbacks, spellID) or false
            if callbacks.setTrustIsOnGCDForBatch then
                callbacks.setTrustIsOnGCDForBatch(true)
            end
            if comparableSpellID and not spellIDIsGCDSpell and not gcdChanged then
                controller:QueueResolvedCooldownForSpellID(spellID, baseSpellID)
            else
                if gcdChanged or spellIDIsGCDSpell then
                    controller:InvalidateGCDOnlyBindings()
                end
                controller:ApplySpellScope()
            end
            if callbacks.setTrustIsOnGCDForBatch then
                callbacks.setTrustIsOnGCDForBatch(false)
            end
        elseif kind == "cast_start" then
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN)
            end
        elseif kind == "cast_succeeded" then
            if callbacks.recordRecentPlayerSpellCast then
                callbacks.recordRecentPlayerSpellCast(spellID)
            end
            controller:InvalidateGCDOnlyBindings()
            controller:InvalidateSpellCooldownBinding(spellID)
            controller:ApplySpellScope()
            local highlighter = callbacks.getHighlighter and callbacks.getHighlighter()
            if highlighter and highlighter.OnPlayerCastSucceeded then
                highlighter.OnPlayerCastSucceeded(spellID)
            end
        end
    end

    function controller:HandleChargesChanged(_, spellID)
        if not isRuntimeEnabled(callbacks) then return end
        controller:NoteChargeDurationObjectsUpdated()
        if callbacks.requestStackTextUpdate then
            callbacks.requestStackTextUpdate()
        end
        if callbacks.scheduleUpdate then
            callbacks.scheduleUpdate(nil, UPDATE_COOLDOWN, false)
        end
        if spellID then
            controller:QueueResolvedCooldownForSpellID(spellID, nil)
        else
            controller:ApplySpellScope()
        end
    end

    return controller
end
