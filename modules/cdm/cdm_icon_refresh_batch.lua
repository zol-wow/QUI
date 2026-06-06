local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Refresh Batch
--
-- Private controller used by CDMIcons. It owns runtime-query batch accounting,
-- per-refresh DB/time hoists, edit/combat batch preparation, and stack-text
-- write requests that are consumed by cooldown-only refreshes.
---------------------------------------------------------------------------

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
    mirror = true,
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

    -- Flag (not a nil stats table) because controller.stats is public surface
    -- via GetStats(); false until the injected debugRegister activates stats.
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
        activateStats() -- no gate injected (tests): eager, preserves existing behavior
    end
    return controller
end
