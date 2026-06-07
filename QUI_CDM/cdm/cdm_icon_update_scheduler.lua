local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Update Scheduler
--
-- Private controller used by CDMIcons. It owns icon refresh cadence, fallback
-- frame coalescing, merged GCD trust state, and bar-dirty draining.
---------------------------------------------------------------------------

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
