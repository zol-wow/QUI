local _, ns = ...

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

local function IsGlobalRecoveryCategory(category, isSecretValue)
    if isSecretValue and isSecretValue(category) then
        return false, true
    end
    local spellCooldownConsts = _G.Constants and _G.Constants.SpellCooldownConsts
    return spellCooldownConsts
        and category == spellCooldownConsts.GLOBAL_RECOVERY_CATEGORY
end

local runtimeRefreshStats
local measureFn

local function setResolveCallerTag(tag)
    local R = ns.CDMResolvers
    if R and R.SetResolveCallerTag then R.SetResolveCallerTag(tag) end
end

local function SetupDebugInstrumentation()
    runtimeRefreshStats = {
        catalogScopeRefreshes = 0,
        catalogScopeQueued = 0,
        castStartCooldownSkips = 0,
        castStartCooldownFallbacks = 0,
        castSucceededCooldownSkips = 0,
        chargeCooldownSkips = 0,
        deferredFullRefreshes = 0,
        deferredFullDrains = 0,
        hotfixDeferredFulls = 0,
        spellsChangedScoped = 0,
        unitSpellcastCooldownSkips = 0,
        unitSpellcastCooldownFallbacks = 0,
        refreshAllCooldownFallbacks = 0,
    }
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "CDM_catalogScopeRefreshes", counter = true, fn = function() return runtimeRefreshStats.catalogScopeRefreshes end }
    mp[#mp + 1] = { name = "CDM_catalogScopeQueued", counter = true, fn = function() return runtimeRefreshStats.catalogScopeQueued end }
    mp[#mp + 1] = { name = "CDM_castStartCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.castStartCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_castStartCooldownFallbacks", counter = true, fn = function() return runtimeRefreshStats.castStartCooldownFallbacks end }
    mp[#mp + 1] = { name = "CDM_castSucceededCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.castSucceededCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_chargeCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.chargeCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_deferredFullRefreshes", counter = true, fn = function() return runtimeRefreshStats.deferredFullRefreshes end }
    mp[#mp + 1] = { name = "CDM_deferredFullDrains", counter = true, fn = function() return runtimeRefreshStats.deferredFullDrains end }
    mp[#mp + 1] = { name = "CDM_hotfixDeferredFulls", counter = true, fn = function() return runtimeRefreshStats.hotfixDeferredFulls end }
    mp[#mp + 1] = { name = "CDM_spellsChangedScoped", counter = true, fn = function() return runtimeRefreshStats.spellsChangedScoped end }
    mp[#mp + 1] = { name = "CDM_unitSpellcastCooldownSkips", counter = true, fn = function() return runtimeRefreshStats.unitSpellcastCooldownSkips end }
    mp[#mp + 1] = { name = "CDM_unitSpellcastCooldownFallbacks", counter = true, fn = function() return runtimeRefreshStats.unitSpellcastCooldownFallbacks end }
    mp[#mp + 1] = { name = "CDM_refreshAllCooldownFallbacks", counter = true, fn = function() return runtimeRefreshStats.refreshAllCooldownFallbacks end }
    measureFn = ns.DebugIsolate and ns.DebugIsolate(ns.MemAuditProfilerMeasure)
        or ns.MemAuditProfilerMeasure
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local function isRuntimeEnabled(callbacks)
    return not callbacks.isRuntimeEnabled or callbacks.isRuntimeEnabled() ~= false
end

local function normalizeSpellIdentifier(callbacks, value)
    if callbacks.isSecretValue and callbacks.isSecretValue(value) then return nil end
    if value == nil then return nil end
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

local function getIconPools(callbacks)
    return (callbacks.getIconPools and callbacks.getIconPools()) or {}
end

local function isAuraEntry(callbacks, entry)
    return callbacks.isAuraEntry and callbacks.isAuraEntry(entry) or false
end

local function isSelfAuraUnit(unit)
    return unit == "player" or unit == "pet" or unit == "vehicle"
end

local function listHasEntries(list)
    return type(list) == "table" and #list > 0
end

local function auraDeltaShouldWakeAuraEntries(unit, updateInfo)
    if not (updateInfo and listHasEntries(updateInfo.addedAuras)) then return false end
    return isSelfAuraUnit(unit) or unit == "target"
end

local function isItemEntry(entry)
    local entryType = entry and entry.type
    return entryType == "item" or entryType == "trinket" or entryType == "slot"
        or entryType == "consumable"
end

local function isCustomCooldownEntry(entry)
    return entry and entry._isCustomEntry == true and entry.kind == "cooldown"
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

local function setStackTextWrites(callbacks, enabled)
    if callbacks.setStackTextWrites then
        callbacks.setStackTextWrites(enabled == true)
    end
end

local function clearAuraDurationBinding(callbacks, icon)
    if not icon then return false end
    local mode = icon._lastResolvedMode
    local key = icon._lastDurObjKey
    if mode ~= "aura"
        and not (type(key) == "string" and key:sub(1, 5) == "aura:") then
        return false
    end

    if callbacks.clearDurationBinding then
        callbacks.clearDurationBinding(icon)
    else
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
    end
    return true
end

local function clearCustomCooldownDurationBinding(callbacks, icon, entry)
    if not isCustomCooldownEntry(entry) then return false end
    if callbacks.clearDurationBinding then
        callbacks.clearDurationBinding(icon)
    else
        icon._lastDurObjKey = nil
        icon._lastDurObj = nil
        icon._lastResolvedMode = nil
        icon._lastResolvedSourceID = nil
        icon._lastResolvedSpellID = nil
    end
    return true
end

local function endBatch(callbacks)
    if callbacks.endBatch then
        callbacks.endBatch()
    end
end

local function linkedSpellIDsMatch(callbacks, getLinkedSpellIDs, sourceID, spellIDs)
    if sourceID == nil then return false end
    local linkedIDs = getLinkedSpellIDs(sourceID)
    if type(linkedIDs) ~= "table" then return false end
    for _, linkedID in ipairs(linkedIDs) do
        if spellIDs then
            if spellIdentifierSetHas(callbacks, spellIDs, linkedID) then return true end
        elseif linkedID ~= nil then
            return true
        end
    end
    return false
end

local function entryLinkedSpellIDsMatch(callbacks, icon, entry, spellIDs)
    local getLinkedSpellIDs = callbacks.getLinkedSpellIDsForSpellID
    if not getLinkedSpellIDs or not entry then return false end
    if linkedSpellIDsMatch(callbacks, getLinkedSpellIDs,
        icon and icon._runtimeSpellID, spellIDs) then return true end
    if linkedSpellIDsMatch(callbacks, getLinkedSpellIDs, entry.overrideSpellID, spellIDs) then return true end
    if linkedSpellIDsMatch(callbacks, getLinkedSpellIDs, entry.spellID, spellIDs) then return true end
    return linkedSpellIDsMatch(callbacks, getLinkedSpellIDs, entry.id, spellIDs)
end

local function entryHasLinkedSpellIDs(callbacks, icon, entry)
    local linked = entry and entry.linkedSpellIDs
    if type(linked) == "table" then
        for _, linkedID in ipairs(linked) do
            if linkedID ~= nil then return true end
        end
    end
    return entryLinkedSpellIDsMatch(callbacks, icon, entry)
end

local itemEntryMatchesAuraSpellIdentifierSet

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

    if itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs) then return true end
    return entryLinkedSpellIDsMatch(callbacks, icon, entry, spellIDs)
end

itemEntryMatchesAuraSpellIdentifierSet = function(callbacks, entry, spellIDs, hasSpellIDs)
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
        applySpellIDScratch = {},
        itemScopeOptionsScratch = { refreshRuntime = false },
        catalogScopeOptionsScratch = { includeItems = false },
        spellScopeRefreshOptionsScratch = { refreshRuntime = true },
        itemScopeRefreshOptionsScratch = { refreshRuntime = true },
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
        catalogQueue = {
            frame = nil,
            elapsed = 0,
            scheduled = false,
            includeItems = false,
            delay = callbacks.getCombatQueueDelay and callbacks.getCombatQueueDelay() or 0.3,
        },
        deferredFullRefresh = false,
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

    function controller:ApplyAuraScope(options)
        options = options or {}
        local includeItems = options.includeItems == true
        local includeCustomCooldowns = options.includeCustomCooldowns == true
        local skipSelfAuraFn = options.skipSelfAuraIcons == true
            and callbacks.isDefinitivelySelfAuraIcon
            or nil
        local editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "auraScope")
        local refreshed = 0
        setResolveCallerTag("auraScope")
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry
                    and (isAuraEntry(callbacks, entry)
                        or icon._auraActive == true
                        or (includeItems and isItemEntry(entry))
                        or (includeCustomCooldowns and isCustomCooldownEntry(entry))
                        or (includeCustomCooldowns and entryHasLinkedSpellIDs(callbacks, icon, entry)))
                    and not (skipSelfAuraFn and skipSelfAuraFn(icon)) then
                    if not clearCustomCooldownDurationBinding(callbacks, icon, entry) then
                        clearAuraDurationBinding(callbacks, icon)
                    end
                    if controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState) then
                        local auraEntry = isAuraEntry(callbacks, entry)
                            or entry.kind == "aura" or entry.kind == "auraBar"
                        if not auraEntry then
                            local containerDB = select(1, resolveContainer(callbacks, entry, ncdm, ncdmContainers))
                            if callbacks.updateContainerVisibility then
                                callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                            end
                            if callbacks.syncCooldownBling then
                                callbacks.syncCooldownBling(icon)
                            end
                        end
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        setResolveCallerTag(nil)
        endBatch(callbacks)
        return refreshed
    end

    function controller:ApplyItemScope(options)
        options = options or {}
        local refreshRuntime = options.refreshRuntime == true
        local batchStarted = false
        local refreshed = false
        local stackTextWritesEnabled = false
        local editMode, ncdm, ncdmContainers, inCombatState
        setResolveCallerTag("item")
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if isItemEntry(entry) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "itemScope")
                        batchStarted = true
                    end
                    if refreshRuntime and callbacks.updateIconCooldown then
                        if not stackTextWritesEnabled then
                            setStackTextWrites(callbacks, true)
                            stackTextWritesEnabled = true
                        end
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
        setResolveCallerTag(nil)
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:ApplySpellScope(options)
        options = options or {}
        local refreshRuntime = options.refreshRuntime == true
        local batchStarted = false
        local refreshed = false
        local stackTextWritesEnabled = false
        local editMode, ncdm, ncdmContainers, inCombatState
        setResolveCallerTag("catalog")
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and not isAuraEntry(callbacks, entry) and not isItemEntry(entry) then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellScope")
                        batchStarted = true
                    end
                    if refreshRuntime and callbacks.updateIconCooldown then
                        if not stackTextWritesEnabled then
                            setStackTextWrites(callbacks, true)
                            stackTextWritesEnabled = true
                        end
                        callbacks.updateIconCooldown(icon)
                    elseif callbacks.applyResolvedCooldown then
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
        setResolveCallerTag(nil)
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:ApplyCatalogScope(options)
        options = options or {}
        if runtimeRefreshStats then runtimeRefreshStats.catalogScopeRefreshes = runtimeRefreshStats.catalogScopeRefreshes + 1 end
        local refreshed = controller:ApplySpellScope(controller.spellScopeRefreshOptionsScratch) == true
        if options.includeItems then
            refreshed = controller:ApplyItemScope(controller.itemScopeRefreshOptionsScratch) == true or refreshed
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
                        or mode == "gcd-only"
                        or mode == "item-cooldown"
                    if not isCooldownKey and type(lk) == "string" then
                        isCooldownKey = lk:sub(1, 9) == "cooldown:"
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

    function controller:ApplySpellID(eventSpellID, eventBaseSpellID, trustIsOnGCD,
        eventCategory, eventItemID)
        local spellIDs = controller.applySpellIDScratch
        wipe(spellIDs)
        local hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventSpellID)
        hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventBaseSpellID) or hasSpellIDs
        hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventCategory) or hasSpellIDs
        hasSpellIDs = addSpellIdentifierToSet(callbacks, spellIDs, eventItemID) or hasSpellIDs
        if not hasSpellIDs then return false end

        local normalizedCategory = normalizeSpellIdentifier(callbacks, eventCategory)
        local normalizedItemID = normalizeSpellIdentifier(callbacks, eventItemID)

        local batchStarted = false
        local refreshed = false
        local stackTextWritesEnabled = false
        local editMode, ncdm, ncdmContainers, inCombatState
        setResolveCallerTag("spellID")
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    local entryCategory = normalizeSpellIdentifier(callbacks, entry and entry.id)
                    if normalizedCategory and entryCategory == normalizedCategory
                        and entry and entry.type == "consumable" then
                        entry._runtimeItemID = normalizedItemID
                        entry._runtimeSpellID = normalizeSpellIdentifier(callbacks, eventSpellID)
                            or normalizeSpellIdentifier(callbacks, eventBaseSpellID)
                        entry._runtimeBaseSpellID = normalizeSpellIdentifier(callbacks, eventBaseSpellID)
                    end
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "spellID")
                        batchStarted = true
                    end
                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if isAuraEntry(callbacks, entry) or cType == "aura" or cType == "auraBar" then
                        controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState)
                    else
                        if callbacks.updateIconCooldown then
                            if not stackTextWritesEnabled then
                                setStackTextWrites(callbacks, true)
                                stackTextWritesEnabled = true
                            end
                            callbacks.updateIconCooldown(icon, trustIsOnGCD == true)
                        elseif callbacks.applyResolvedCooldown then
                            callbacks.applyResolvedCooldown(icon, nil, trustIsOnGCD == true)
                        end
                        if callbacks.updateContainerVisibility then
                            callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                        end
                        if callbacks.syncCooldownBling then
                            callbacks.syncCooldownBling(icon)
                        end
                    end
                    refreshed = true
                end
            end
        end
        setResolveCallerTag(nil)
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:ApplyAuraInstances(unit, updateInfo)
        if not updateInfo or updateInfo.isFullUpdate then return nil end

        local ids = controller.auraDeltaInstanceIDs
        wipe(ids)
        local hasIDs = false
        local hasRemovedIDs = false

        local spellIDs = controller.auraDeltaSpellIDs
        wipe(spellIDs)
        local hasSpellIDs = false
        local hasAddedAuraWithoutReadableSpellID = false

        local wakeAuraEntries = auraDeltaShouldWakeAuraEntries(unit, updateInfo)

        if updateInfo.addedAuras then
            for _, auraData in ipairs(updateInfo.addedAuras) do
                local auraInstanceID = auraData and auraData.auraInstanceID
                if auraInstanceID ~= nil then
                    ids[auraInstanceID] = true
                    hasIDs = true
                end
                if auraData then
                    local addedSpellID = addSpellIdentifierToSet(callbacks, spellIDs, auraData.spellId)
                    addedSpellID = addSpellIdentifierToSet(callbacks, spellIDs, auraData.spellID) or addedSpellID
                    hasSpellIDs = addedSpellID or hasSpellIDs
                    if not addedSpellID then
                        hasAddedAuraWithoutReadableSpellID = true
                    end
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
                    hasRemovedIDs = true
                end
            end
        end

        if not hasIDs and not hasSpellIDs and not wakeAuraEntries then return 0 end

        local refreshed = 0
        local batchStarted = false
        local editMode, ncdm, ncdmContainers, inCombatState
        setResolveCallerTag("aura")
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                local iconAuraInstanceID = icon and icon._auraInstanceID
                local matches = iconAuraInstanceID
                    and ids[iconAuraInstanceID]
                    and (not unit or icon._auraUnit == unit)
                if not matches
                    and entryMatchesSpellIdentifierSet(callbacks, icon, entry, spellIDs, hasSpellIDs) then
                    matches = true
                end
                if not matches
                    and itemEntryMatchesAuraSpellIdentifierSet(callbacks, entry, spellIDs, hasSpellIDs) then
                    matches = true
                end
                if not matches
                    and hasRemovedIDs
                    and isSelfAuraUnit(unit)
                    and isItemEntry(entry)
                    and icon
                    and icon._auraActive == true
                    and iconAuraInstanceID == nil then
                    matches = true
                end
                if not matches and wakeAuraEntries and isAuraEntry(callbacks, entry) then
                    matches = true
                end
                if not matches
                    and wakeAuraEntries
                    and hasAddedAuraWithoutReadableSpellID
                    and isItemEntry(entry) then
                    matches = true
                end
                if matches and entry then
                    if not batchStarted then
                        editMode, ncdm, ncdmContainers, inCombatState = beginBatch(callbacks, "auraDelta")
                        batchStarted = true
                    end
                    if not clearCustomCooldownDurationBinding(callbacks, icon, entry) then
                        clearAuraDurationBinding(callbacks, icon)
                    end
                    if controller:ApplyAuraScopedResolvedCooldown(icon, entry, editMode, ncdm, ncdmContainers, inCombatState) then
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        setResolveCallerTag(nil)
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
        if icon._cdDesaturated then return true end
        return false
    end

    function controller:ApplyUsabilityRefresh()
        local refreshed = 0
        local editMode, ncdm, ncdmContainers, inCombatState
        local batchStarted = false
        setResolveCallerTag("usability")
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry and controller:IconNeedsUsabilityCooldownRefresh(icon) then
                    if not batchStarted then
                        if callbacks.prepareBatch then
                            editMode, ncdm, ncdmContainers, inCombatState = callbacks.prepareBatch()
                        end
                        if callbacks.beginBatch then
                            callbacks.beginBatch("usability")
                        end
                        batchStarted = true
                    end

                    local containerDB, cType = resolveContainer(callbacks, entry, ncdm, ncdmContainers)
                    if cType ~= "aura" and cType ~= "auraBar" and callbacks.updateContainerVisibility then
                        callbacks.updateContainerVisibility(icon, entry, containerDB, editMode, inCombatState)
                    end
                    refreshed = refreshed + 1
                end
            end
        end
        setResolveCallerTag(nil)

        if batchStarted then
            endBatch(callbacks)
        end
        if refreshed > 0 and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
        return refreshed
    end

    function controller:RunUsabilityRefresh()
        controller:ApplyUsabilityRefresh()
        if callbacks.updateIconRangesForUsabilityEvent then
            setResolveCallerTag("rangeUsable")
            callbacks.updateIconRangesForUsabilityEvent()
            setResolveCallerTag(nil)
        end
    end

    local function drainSpellQueue()
        local state = controller.spellQueue
        disarmQueue(state)
        if next(state.ids) == nil then return end

        local editMode, ncdm, ncdmContainers, inCombatState
        local refreshed = false
        local batchStarted = false
        local stackTextWritesEnabled = false
        setResolveCallerTag("spellQueue")
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
                        if callbacks.updateIconCooldown then
                            if not stackTextWritesEnabled then
                                setStackTextWrites(callbacks, true)
                                stackTextWritesEnabled = true
                            end
                            callbacks.updateIconCooldown(icon)
                        elseif callbacks.applyResolvedCooldown then
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
        if stackTextWritesEnabled then
            setStackTextWrites(callbacks, false)
        end
        if batchStarted then
            endBatch(callbacks)
        end
        setResolveCallerTag(nil)
        wipe(state.ids)

        if refreshed and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
    end

    ---@type fun(...): ...
    local _drainSpellQueueImpl = drainSpellQueue
    drainSpellQueue = function(...)
        local measure = measureFn
        if measure then return measure("CDM_drainSpellQueue", _drainSpellQueueImpl, ...) end
        return _drainSpellQueueImpl(...)
    end

    local function spellQueueOnUpdate(_, elapsed)
        local state = controller.spellQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainSpellQueue()
    end

    function controller:QueueResolvedCooldownForSpellID(eventSpellID, eventBaseSpellID)
        if not inCombat() then
            controller:ApplySpellID(eventSpellID, eventBaseSpellID, false)
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

    ---@type fun(...): ...
    local _drainUsabilityQueueImpl = drainUsabilityQueue
    drainUsabilityQueue = function(...)
        local measure = measureFn
        if measure then return measure("CDM_drainUsabilityQueue", _drainUsabilityQueueImpl, ...) end
        return _drainUsabilityQueueImpl(...)
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

        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                if icon and icon._showingGCDSwipe == true then
                    controller:RunUsabilityRefresh()
                    return
                end
            end
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
        local opts = controller.itemScopeOptionsScratch
        opts.refreshRuntime = refreshRuntime
        controller:ApplyItemScope(opts)
    end

    ---@type fun(...): ...
    local _drainItemQueueImpl = drainItemQueue
    drainItemQueue = function(...)
        local measure = measureFn
        if measure then return measure("CDM_drainItemQueue", _drainItemQueueImpl, ...) end
        return _drainItemQueueImpl(...)
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

    local function drainCatalogQueue()
        local state = controller.catalogQueue
        local includeItems = state.includeItems == true
        state.includeItems = false
        disarmQueue(state)
        local opts = controller.catalogScopeOptionsScratch
        opts.includeItems = includeItems
        controller:ApplyCatalogScope(opts)
    end

    ---@type fun(...): ...
    local _drainCatalogQueueImpl = drainCatalogQueue
    drainCatalogQueue = function(...)
        local measure = measureFn
        if measure then return measure("CDM_drainCatalogQueue", _drainCatalogQueueImpl, ...) end
        return _drainCatalogQueueImpl(...)
    end

    local function catalogQueueOnUpdate(_, elapsed)
        local state = controller.catalogQueue
        state.elapsed = state.elapsed + (elapsed or 0)
        if state.elapsed < state.delay then return end
        drainCatalogQueue()
    end

    function controller:QueueCatalogScopeRefresh(options)
        options = options or {}
        if not inCombat() then
            controller:ApplyCatalogScope(options)
            return
        end

        local state = controller.catalogQueue
        if options.includeItems then
            state.includeItems = true
        end
        if state.scheduled then return end
        if runtimeRefreshStats then runtimeRefreshStats.catalogScopeQueued = runtimeRefreshStats.catalogScopeQueued + 1 end
        armQueue(state, catalogQueueOnUpdate)
    end

    function controller:DeferFullRefresh()
        if not controller.deferredFullRefresh then
            if runtimeRefreshStats then runtimeRefreshStats.deferredFullRefreshes = runtimeRefreshStats.deferredFullRefreshes + 1 end
        end
        controller.deferredFullRefresh = true
    end

    function controller:DrainDeferredFullRefresh()
        if not controller.deferredFullRefresh then return false end
        controller.deferredFullRefresh = false
        if runtimeRefreshStats then runtimeRefreshStats.deferredFullDrains = runtimeRefreshStats.deferredFullDrains + 1 end
        if callbacks.scheduleUpdate then
            callbacks.scheduleUpdate(true, UPDATE_FULL, "deferred")
        end
        return true
    end

    function controller:ApplyTargetScope(event)
        if callbacks.chargeDebug then
            callbacks.chargeDebug(nil, "EVENT", event, "target-scope-refresh")
        end
        if callbacks.refreshCustomAuraTargets then
            callbacks.refreshCustomAuraTargets(event ~= "UNIT_FACTION")
        end
        if callbacks.updateAllIconRanges then
            setResolveCallerTag("rangeTarget")
            callbacks.updateAllIconRanges()
            setResolveCallerTag(nil)
        end
        controller:QueueUsabilityRefresh()
    end

    function controller:HandleAuraRefresh(unit, updateInfo)
        if not isRuntimeEnabled(callbacks) then return end
        if callbacks.eventTracePrint then
            callbacks.eventTracePrint("aura-pre", "UNIT_AURA", unit, nil, nil,
                callbacks.eventTraceAuraInfo and callbacks.eventTraceAuraInfo(unit, updateInfo))
        end

        if callbacks.requestStackTextUpdate then
            callbacks.requestStackTextUpdate()
        end

        local barsMarked = callbacks.markBarsForAuraRefresh
            and callbacks.markBarsForAuraRefresh(unit, updateInfo) == true

        if not updateInfo or updateInfo.isFullUpdate then
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            controller:ApplyAuraScope({
                includeItems = unit == "player",
                includeCustomCooldowns = isSelfAuraUnit(unit),
                skipSelfAuraIcons = unit == "target",
            })
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
        else
            local refreshed = controller:ApplyAuraInstances(unit, updateInfo) or 0
            if refreshed > 0 or barsMarked then
                if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
                if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
            end
        end

        if callbacks.eventTracePrint then
            callbacks.eventTracePrint("aura-post", "UNIT_AURA", unit, nil, nil,
                callbacks.eventTraceAuraInfo and callbacks.eventTraceAuraInfo(unit, updateInfo))
        end
    end

    function controller:HandleFrameEvent(event, arg1, arg2, arg3, arg4, frame)
        if not isRuntimeEnabled(callbacks) then
            if callbacks.onRuntimeDisabled then
                callbacks.onRuntimeDisabled(frame)
            end
            return
        end

        if event == "UNIT_SPELLCAST_STOP"
           or event == "UNIT_SPELLCAST_CHANNEL_START"
           or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local isPlayerUnit
            if callbacks.isSecretValue and callbacks.isSecretValue(arg1) then
                isPlayerUnit = true
            else
                isPlayerUnit = arg1 == "player" -- @secret-safe: else-branch of the callbacks.isSecretValue(arg1) probe above (callback-indirected guard the analyzer cannot see; tests inject secrets through the stub)
            end
            if isPlayerUnit then
                if normalizeSpellIdentifier(callbacks, arg3) ~= nil then
                    if runtimeRefreshStats then runtimeRefreshStats.unitSpellcastCooldownSkips = runtimeRefreshStats.unitSpellcastCooldownSkips + 1 end
                    controller:QueueResolvedCooldownForSpellID(arg3, nil) -- @secret-safe: reached only when normalizeSpellIdentifier(callbacks, arg3) ~= nil, and that helper probes isSecretValue and returns nil for secrets — arg3 proven readable here
                elseif callbacks.scheduleUpdate then
                    if runtimeRefreshStats then runtimeRefreshStats.unitSpellcastCooldownFallbacks = runtimeRefreshStats.unitSpellcastCooldownFallbacks + 1 end
                    callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, "unit_spellcast")
                end
            end
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then
            controller:ApplyTargetScope(event)
            return
        end
        if event == "PLAYER_SOFT_ENEMY_CHANGED"
            or event == "PLAYER_SOFT_FRIEND_CHANGED"
            or event == "UNIT_FACTION" then
            controller:ApplyTargetScope(event)
            return
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            if arg1 == 13 or arg1 == 14 then
                controller:QueueItemScopeRefresh({ refreshRuntime = true })
            end
            return
        end
        if event == "PLAYER_TOTEM_UPDATE" then
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, "totem")
            end
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            controller:DrainDeferredFullRefresh()
            if callbacks.refreshPendingSecureAttributes then
                callbacks.refreshPendingSecureAttributes()
            end
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
                setResolveCallerTag("rangeCheck")
                callbacks.updateIconsForSpellRangeEvent(arg1, arg2, arg3)
                setResolveCallerTag(nil)
            end
            return
        end
        if event == "SPELL_UPDATE_USABLE" then
            controller:QueueUsabilityRefresh()
            return
        end
        if event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" then
            if callbacks.clearStableCaches then
                callbacks.clearStableCaches()
            end
            controller:QueueCatalogScopeRefresh({ includeItems = false })
            return
        end
        if event == "SPELLS_CHANGED" then
            if runtimeRefreshStats then runtimeRefreshStats.spellsChangedScoped = runtimeRefreshStats.spellsChangedScoped + 1 end
            return
        end
        if event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
            if callbacks.invalidateSpellCaches then
                callbacks.invalidateSpellCaches(arg1)
                if arg2 then callbacks.invalidateSpellCaches(arg2) end
            end
            if callbacks.clearDurationBindingKeyCache then
                callbacks.clearDurationBindingKeyCache()
            end
            controller:QueueResolvedCooldownForSpellID(arg1, arg2)
            return
        end
        if event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
            if inCombat() then
                if runtimeRefreshStats then runtimeRefreshStats.hotfixDeferredFulls = runtimeRefreshStats.hotfixDeferredFulls + 1 end
                controller:DeferFullRefresh()
                return
            end
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_FULL, "hotfix")
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
        if event == "BAG_UPDATE_DELAYED" or event == "ITEM_COUNT_CHANGED" then
            if callbacks.invalidateConsumableCategoryItems then
                callbacks.invalidateConsumableCategoryItems()
            end
            controller:QueueItemScopeRefresh({ refreshRuntime = true })
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
            return
        end
    end

    function controller:Handle(event, arg1, arg2, arg3, arg4, frame)
        if event == "UNIT_AURA" then
            return controller:HandleAuraRefresh(arg1, arg2) -- @secret-safe: HandleAuraRefresh is reached only via cdm_spelldata NotifyAuraConsumers, which passes a plain non-secret unit; updateInfo is a plain container table (round-13 hand-audit)
        end
        return controller:HandleFrameEvent(event, arg1, arg2, arg3, arg4, frame) -- @secret-safe: HandleFrameEvent probes isSecretValue(arg1) before the unit compare and normalizes arg3 through the secret-probing normalizeSpellIdentifier (round-13 hand-audit)
    end

    function controller:HandleCooldownChanged(_, spellID, baseSpellID, kind, category, startRecoveryCategory, itemID)
        if not isRuntimeEnabled(callbacks) then return end
        if kind == "scanner_item" then
            controller:ApplyItemScope()
            if callbacks.setBarsDirty then callbacks.setBarsDirty(true) end
            if callbacks.runDirtyBarUpdate then callbacks.runDirtyBarUpdate() end
        elseif kind == "scanner_spell" then
            controller:ApplySpellScope()
        elseif kind == "refresh" then
            local isGlobalRecovery, isOpaqueCategory = IsGlobalRecoveryCategory(
                startRecoveryCategory, callbacks.isSecretValue)
            if (isGlobalRecovery or isOpaqueCategory)
                and callbacks.updateCooldownOnly then
                local comparableSpellID = normalizeSpellIdentifier(callbacks, spellID) ~= nil
                if comparableSpellID then
                    controller:ApplySpellID(spellID, baseSpellID, true, category, itemID)
                end
                callbacks.updateCooldownOnly(true, true)
                return
            end
            local normalizedCategory = normalizeSpellIdentifier(callbacks, category)
            local normalizedItemID = normalizeSpellIdentifier(callbacks, itemID)
            local categoryOpaque = category ~= nil and normalizedCategory == nil
            local itemOpaque = itemID ~= nil and normalizedItemID == nil
            local payloadlessCooldownRefresh = spellID == nil
                and baseSpellID == nil
                and category == nil
                and startRecoveryCategory == nil
                and itemID == nil
            if categoryOpaque or itemOpaque then
                if callbacks.scheduleUpdate then
                    if runtimeRefreshStats then runtimeRefreshStats.refreshAllCooldownFallbacks = runtimeRefreshStats.refreshAllCooldownFallbacks + 1 end
                    callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, "refresh_all", false)
                end
                return
            end
            local refreshed = controller:ApplySpellID(
                spellID, baseSpellID, true, normalizedCategory, normalizedItemID)
            if not refreshed and callbacks.scheduleUpdate then
                if runtimeRefreshStats then runtimeRefreshStats.refreshAllCooldownFallbacks = runtimeRefreshStats.refreshAllCooldownFallbacks + 1 end
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, "refresh_all", payloadlessCooldownRefresh)
            end
        elseif kind == "cast_start" then
            if normalizeSpellIdentifier(callbacks, spellID) ~= nil then
                if runtimeRefreshStats then runtimeRefreshStats.castStartCooldownSkips = runtimeRefreshStats.castStartCooldownSkips + 1 end
                controller:QueueResolvedCooldownForSpellID(spellID, baseSpellID)
            elseif callbacks.scheduleUpdate then
                if runtimeRefreshStats then runtimeRefreshStats.castStartCooldownFallbacks = runtimeRefreshStats.castStartCooldownFallbacks + 1 end
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, "cast_start")
            end
        elseif kind == "cast_succeeded" then
            if callbacks.recordRecentPlayerSpellCast then
                callbacks.recordRecentPlayerSpellCast(spellID)
            end
            controller:InvalidateGCDOnlyBindings()
            controller:InvalidateSpellCooldownBinding(spellID)
            if normalizeSpellIdentifier(callbacks, spellID) ~= nil then
                controller:ApplySpellID(spellID, nil, false)
            elseif callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, "cast_succeeded")
            end
            if callbacks.requestStackTextUpdate then
                callbacks.requestStackTextUpdate()
            end
            if runtimeRefreshStats then runtimeRefreshStats.castSucceededCooldownSkips = runtimeRefreshStats.castSucceededCooldownSkips + 1 end
            local highlighter = callbacks.getHighlighter and callbacks.getHighlighter()
            if highlighter and highlighter.OnPlayerCastSucceeded then
                highlighter.OnPlayerCastSucceeded(spellID)
            end
        end
    end

    function controller:HandleChargesChanged(_, spellID, baseSpellID)
        if not isRuntimeEnabled(callbacks) then return end
        if callbacks.requestStackTextUpdate then
            callbacks.requestStackTextUpdate()
        end
        if normalizeSpellIdentifier(callbacks, spellID) ~= nil
            or normalizeSpellIdentifier(callbacks, baseSpellID) ~= nil then
            if runtimeRefreshStats then runtimeRefreshStats.chargeCooldownSkips = runtimeRefreshStats.chargeCooldownSkips + 1 end
            controller:QueueResolvedCooldownForSpellID(spellID, baseSpellID)
        else
            if callbacks.scheduleUpdate then
                callbacks.scheduleUpdate(true, UPDATE_COOLDOWN, "charges")
            end
        end
    end

    return controller
end
