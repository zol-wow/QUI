-- Each `do -- Inlined from X ... end` block is a self-contained chunk that

do
-- Inlined from cdm_icon_update_scheduler.lua
local _, ns = ...

local CDMIconUpdateScheduler = {}
ns.CDMIconUpdateScheduler = CDMIconUpdateScheduler

local UPDATE_COOLDOWN = "cooldown"
local UPDATE_FULL = "full"

local MIN_UPDATE_INTERVAL_IDLE = 0.05
local MIN_UPDATE_INTERVAL_COMBAT = 0.20
local MIN_UPDATE_INTERVAL_RAID_COMBAT = 0.30
local FAST_UPDATE_INTERVAL = 0
local FAST_FULL_UPDATE_INTERVAL = MIN_UPDATE_INTERVAL_IDLE

function CDMIconUpdateScheduler.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        frame = CreateFrame("Frame"),
        pending = false,
        elapsed = 0,
        delay = MIN_UPDATE_INTERVAL_IDLE,
        mode = UPDATE_COOLDOWN,
        barsDirty = false,
        lastUpdateTime = 0,
    }

    local function isRuntimeEnabled()
        return not callbacks.isRuntimeEnabled or callbacks.isRuntimeEnabled() ~= false
    end

    local function getTime()
        if callbacks.getTime then
            return callbacks.getTime()
        end
        return GetTime and GetTime() or 0
    end

    function controller:GetDelay(fast, mode)
        if fast then
            if mode == UPDATE_COOLDOWN then
                return FAST_UPDATE_INTERVAL
            end
            return FAST_FULL_UPDATE_INTERVAL
        end
        local inCombat
        if callbacks.isInCombat then
            inCombat = callbacks.isInCombat()
        else
            inCombat = InCombatLockdown and InCombatLockdown()
        end
        if not inCombat then
            return MIN_UPDATE_INTERVAL_IDLE
        end
        local inRaid
        if callbacks.isInRaid then
            inRaid = callbacks.isInRaid()
        else
            inRaid = IsInRaid and IsInRaid()
        end
        if inRaid then
            return MIN_UPDATE_INTERVAL_RAID_COMBAT
        end
        return MIN_UPDATE_INTERVAL_COMBAT
    end

    function controller:GetCombatQueueDelay()
        return MIN_UPDATE_INTERVAL_RAID_COMBAT
    end

    function controller:SetBarsDirty(dirty)
        controller.barsDirty = dirty == true
    end

    function controller:IsBarsDirty()
        return controller.barsDirty == true
    end

    function controller:RunDirtyBarUpdate()
        if not controller.barsDirty then return end
        local bars = callbacks.getBars and callbacks.getBars()
        if bars and bars.UpdateOwnedBars then
            controller.barsDirty = false
            bars:UpdateOwnedBars()
        end
    end

    function controller:Cancel()
        controller.frame:SetScript("OnUpdate", nil)
        controller.pending = false
        controller.elapsed = 0
        controller.mode = UPDATE_COOLDOWN
        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        if scheduler and scheduler.CancelRuntimeUpdate then
            scheduler.CancelRuntimeUpdate()
        end
    end

    function controller:Run(modeOverride)
        controller.pending = false
        local mode = modeOverride or controller.mode or UPDATE_COOLDOWN
        controller.mode = UPDATE_COOLDOWN

        if not isRuntimeEnabled() then
            return
        end

        controller.lastUpdateTime = getTime()

        if mode == UPDATE_FULL then
            if callbacks.updateAllCooldowns then
                callbacks.updateAllCooldowns()
            end
        elseif callbacks.updateCooldownOnly then
            callbacks.updateCooldownOnly()
        end

        controller:RunDirtyBarUpdate()
    end

    local function onUpdate(self, elapsed)
        controller.elapsed = controller.elapsed + (elapsed or 0)
        if controller.elapsed < controller.delay then return end
        self:SetScript("OnUpdate", nil)
        controller:Run()
    end

    function controller:Schedule(fast, mode)
        if not isRuntimeEnabled() then
            controller:Cancel()
            return
        end

        mode = (mode == UPDATE_FULL) and UPDATE_FULL or UPDATE_COOLDOWN

        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        if scheduler and scheduler.ScheduleRuntimeUpdate then
            scheduler.ScheduleRuntimeUpdate(fast, mode)
            return
        end

        local delay = controller:GetDelay(fast, mode)

        if controller.pending then
            if mode == UPDATE_FULL then
                controller.mode = UPDATE_FULL
            end
            if delay < controller.delay then
                controller.delay = delay
            end
            return
        end

        controller.pending = true
        controller.elapsed = 0
        controller.delay = delay
        controller.mode = mode
        controller.frame:SetScript("OnUpdate", onUpdate)
    end

    function controller:ScheduleFull(fast)
        controller:Schedule(fast, UPDATE_FULL)
    end

    function controller:ScheduleCooldown(fast)
        controller:Schedule(fast, UPDATE_COOLDOWN)
    end

    function controller:RegisterSchedulerHandler()
        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        if not (scheduler and scheduler.SetRuntimeUpdateHandler) then return end
        scheduler.SetRuntimeUpdateHandler({
            run = function(mode)
                return controller:Run(mode)
            end,
            getDelay = function(fast, mode)
                return controller:GetDelay(fast, mode)
            end,
            isEnabled = isRuntimeEnabled,
            onCancel = function()
                controller.pending = false
            end,
        })
    end

    function controller:GetStats()
        local scheduler = callbacks.getScheduler and callbacks.getScheduler()
        local schedulerPending = scheduler
            and scheduler.IsRuntimeUpdatePending
            and scheduler.IsRuntimeUpdatePending()
        return {
            barsDirty = controller.barsDirty == true,
            updatePending = (schedulerPending ~= nil and schedulerPending)
                or (controller.pending == true),
            updateMode = controller.mode,
            lastUpdateTime = controller.lastUpdateTime,
        }
    end

    controller:RegisterSchedulerHandler()
    return controller
end
end

do
-- Inlined from cdm_icon_refresh_batch.lua
local _, ns = ...

local CDMIconRefreshBatch = {}
ns.CDMIconRefreshBatch = CDMIconRefreshBatch

local pairs = pairs

local DEFAULT_REASONS = {
    updateAll = true,
    cooldownOnly = true,
    type = true,
    placed = true,
    auraScope = true,
    itemScope = true,
    spellScope = true,
    spellID = true,
    auraDelta = true,
    usability = true,
    other = true,
}

local function createStats()
    local stats = {}
    for reason in pairs(DEFAULT_REASONS) do
        stats[reason] = 0
    end
    return stats
end

function CDMIconRefreshBatch.Create(callbacks)
    callbacks = callbacks or {}

    local statsActive = false
    local controller = {
        stats = createStats(),
        ncdm = nil,
        batchTime = 0,
        pendingStackTextUpdate = false,
    }

    local function getTime()
        if callbacks.getTime then
            return callbacks.getTime()
        end
        return GetTime and GetTime() or 0
    end

    local function registerMemProbes()
        local getMemProbes = callbacks.getMemProbes
        if not getMemProbes then return end
        local mp = getMemProbes()
        if not mp then return end
        for reason in pairs(DEFAULT_REASONS) do
            mp[#mp + 1] = {
                name = "CDM_iconBatch_" .. reason,
                counter = true,
                fn = function()
                    return controller.stats[reason] or 0
                end,
            }
        end
    end

    function controller:Prepare()
        local editMode = false
        if callbacks.isEditModeActive and callbacks.isEditModeActive() then
            editMode = true
        elseif callbacks.isLayoutModeActive and callbacks.isLayoutModeActive() then
            editMode = true
        elseif callbacks.isGlobalEditModeActive and callbacks.isGlobalEditModeActive() then
            editMode = true
        end

        local ncdm = callbacks.getNCDM and callbacks.getNCDM() or nil
        controller.ncdm = ncdm
        controller.batchTime = getTime()

        if callbacks.refreshSwipeBatchSettings then
            callbacks.refreshSwipeBatchSettings()
        end

        local inCombat
        if callbacks.isInCombat then
            inCombat = callbacks.isInCombat()
        else
            inCombat = InCombatLockdown and InCombatLockdown() or false
        end

        return editMode, ncdm, ncdm and ncdm.containers, inCombat
    end

    function controller:GetNCDM()
        return controller.ncdm
    end

    function controller:GetTime()
        return controller.batchTime
    end

    function controller:Begin(reason)
        if statsActive then
            if reason and controller.stats[reason] ~= nil then
                controller.stats[reason] = controller.stats[reason] + 1
            else
                controller.stats.other = controller.stats.other + 1
            end
        end
        if callbacks.beginRuntimeQueryBatch then
            callbacks.beginRuntimeQueryBatch()
        end
    end

    function controller:End()
        if callbacks.endRuntimeQueryBatch then
            callbacks.endRuntimeQueryBatch()
        end
    end

    function controller:SetStackTextWrites(enabled)
        if callbacks.setStackTextWrites then
            callbacks.setStackTextWrites(enabled == true)
        end
    end

    function controller:RequestStackTextUpdate()
        controller.pendingStackTextUpdate = true
    end

    function controller:ConsumeStackTextWriteRequest()
        local requested = controller.pendingStackTextUpdate == true
        controller.pendingStackTextUpdate = false
        return requested
    end

    function controller:GetStats()
        return controller.stats
    end

    local function activateStats()
        statsActive = true
        registerMemProbes()
    end
    if callbacks.debugRegister then
        callbacks.debugRegister(activateStats)
    else
        activateStats()
    end
    return controller
end
end

do
-- Inlined from cdm_icon_refresh_walker.lua
local _, ns = ...

local CDMIconRefreshWalker = {}
ns.CDMIconRefreshWalker = CDMIconRefreshWalker

local pairs = pairs
local ipairs = ipairs

local measureFn
local function SetupDebugInstrumentation()
    measureFn = ns.DebugIsolate and ns.DebugIsolate(ns.MemAuditProfilerMeasure)
        or ns.MemAuditProfilerMeasure
end
if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

local function getIconPools(callbacks)
    return (callbacks.getIconPools and callbacks.getIconPools()) or {}
end

local function isAuraContainerType(containerType)
    return containerType == "aura" or containerType == "auraBar"
end

local function processCooldownOnlyIcon(callbacks, icon, context, measure)
    local entry = icon and icon._spellEntry
    if not entry then return false end

    local containerDB, containerType
    if callbacks.resolveContainerDBAndType then
        if measure then
            containerDB, containerType = measure(
                "CDM_walkResolve",
                callbacks.resolveContainerDBAndType,
                entry,
                context.ncdm,
                context.ncdmContainers)
        else
            containerDB, containerType = callbacks.resolveContainerDBAndType(
                entry, context.ncdm, context.ncdmContainers)
        end
    end
    if isAuraContainerType(containerType) then return false end

    if callbacks.refreshCooldownOnlyIcon then
        if measure then
            measure("CDM_walkCooldownIcon", callbacks.refreshCooldownOnlyIcon, icon, entry, context)
        else
            callbacks.refreshCooldownOnlyIcon(icon, entry, context)
        end
    end
    if callbacks.updateIconVisibility then
        if measure then
            measure(
                "CDM_walkVisibility",
                callbacks.updateIconVisibility,
                icon,
                entry,
                containerDB,
                context.editMode,
                context.inCombat)
        else
            callbacks.updateIconVisibility(
                icon, entry, containerDB, context.editMode, context.inCombat)
        end
    end
    return true
end

function CDMIconRefreshWalker.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    function controller:RefreshAll(context)
        local refreshed = 0
        local measure = measureFn
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                if callbacks.refreshAllIcon then
                    if measure then
                        measure("CDM_walkAllIcon", callbacks.refreshAllIcon, icon, context)
                    else
                        callbacks.refreshAllIcon(icon, context)
                    end
                    refreshed = refreshed + 1
                end
            end
        end
        return refreshed
    end

    function controller:RefreshCooldownOnly(context)
        context = context or {}
        local refreshed = 0
        local measure = measureFn
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                if processCooldownOnlyIcon(callbacks, icon, context, measure) then
                    refreshed = refreshed + 1
                end
            end
        end
        return refreshed
    end

    function controller:RefreshType(viewerType, context)
        local pool = getIconPools(callbacks)[viewerType]
        if not pool then return 0 end

        local refreshed = 0
        local measure = measureFn
        for _, icon in ipairs(pool) do
            if callbacks.refreshTypeIcon then
                if measure then
                    measure("CDM_walkTypeIcon", callbacks.refreshTypeIcon, icon, context)
                else
                    callbacks.refreshTypeIcon(icon, context)
                end
                refreshed = refreshed + 1
            end
        end
        return refreshed
    end

    function controller:RefreshRuntimeType(viewerType, context)
        context = context or {}
        local pool = getIconPools(callbacks)[viewerType]
        if not pool then return 0 end

        local refreshed = 0
        local measure = measureFn
        for _, icon in ipairs(pool) do
            if processCooldownOnlyIcon(callbacks, icon, context, measure) then
                refreshed = refreshed + 1
            end
        end
        return refreshed
    end

    return controller
end
end
