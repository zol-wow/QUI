local _, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Mirror Index
--
-- Private controller used by CDMIcons to target mirror-backed icon refreshes.
-- It owns the weak icon index, pending mirror refresh queue, and mirror
-- refresh stats; CDMIcons keeps the public lifecycle methods.
---------------------------------------------------------------------------

local CDMIconMirrorIndex = {}
ns.CDMIconMirrorIndex = CDMIconMirrorIndex

local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local wipe = wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function CountPendingKeys(pendingByCategory)
    local count = 0
    for _, byCooldownID in pairs(pendingByCategory or {}) do
        for _ in pairs(byCooldownID) do
            count = count + 1
        end
    end
    return count
end

function CDMIconMirrorIndex.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {
        byCategory = {},
        pendingByCategory = {},
        refreshPending = false,
        stats = {
            targeted = 0,
            fallback = 0,
            maxBatch = 0,
        },
        refreshFrame = nil,
        refreshElapsed = 0,
        refreshDelay = 0,
    }

    local mirrorStatsActive = false -- false until QUI_Debug activates instrumentation (debug gate)
    local function activateStats()
        mirrorStatsActive = true
        local mp = ns._memprobes or {}; ns._memprobes = mp
        mp[#mp + 1] = {
            name = "CDM_mirrorRefreshUnscopedSkips",
            counter = true,
            fn = function()
                return controller.stats.fallback or 0
            end,
        }
    end
    if callbacks.debugRegister then
        callbacks.debugRegister(activateStats)
    else
        activateStats() -- no gate injected (tests): eager, preserves existing behavior
    end

    local function getIconSet(category, cooldownID, create)
        if not (category and cooldownID) then return nil end
        local byCategory = controller.byCategory[category]
        if not byCategory then
            if not create then return nil end
            byCategory = {}
            controller.byCategory[category] = byCategory
        end

        local iconSet = byCategory[cooldownID]
        if not iconSet then
            if not create then return nil end
            iconSet = setmetatable({}, { __mode = "k" })
            byCategory[cooldownID] = iconSet
        end
        return iconSet
    end

    function controller:RemoveIcon(icon)
        if not icon then return end
        local category = icon._blizzMirrorIndexCategory
        local cooldownID = icon._blizzMirrorIndexCooldownID
        if category and cooldownID then
            local iconSet = getIconSet(category, cooldownID, false)
            if iconSet then
                iconSet[icon] = nil
            end
        end
        icon._blizzMirrorIndexCategory = nil
        icon._blizzMirrorIndexCooldownID = nil
        if callbacks.storeMirrorStateForIcon then
            callbacks.storeMirrorStateForIcon(icon)
        end
    end

    function controller:Rebuild(iconPools)
        wipe(controller.byCategory)
        for _, pool in pairs(iconPools or {}) do
            for _, icon in ipairs(pool) do
                if icon and icon._blizzMirrorCooldownID and icon._blizzMirrorCategory then
                    local category = icon._blizzMirrorCategory
                    local cooldownID = icon._blizzMirrorCooldownID
                    local iconSet = getIconSet(
                        category,
                        cooldownID,
                        true)
                    iconSet[icon] = true
                    icon._blizzMirrorIndexCategory = category
                    icon._blizzMirrorIndexCooldownID = cooldownID
                    if callbacks.storeMirrorStateForIcon then
                        local state = callbacks.getMirrorStateByCooldownID
                            and callbacks.getMirrorStateByCooldownID(cooldownID, category)
                            or nil
                        callbacks.storeMirrorStateForIcon(icon, cooldownID, category, state)
                    end
                end
            end
        end
    end

    function controller:BindIcon(icon, cooldownID, category)
        if not icon then return end
        controller:RemoveIcon(icon)
        if cooldownID and category then
            local iconSet = getIconSet(category, cooldownID, true)
            iconSet[icon] = true
            icon._blizzMirrorIndexCategory = category
            icon._blizzMirrorIndexCooldownID = cooldownID
            if callbacks.storeMirrorStateForIcon then
                local state = callbacks.getMirrorStateByCooldownID
                    and callbacks.getMirrorStateByCooldownID(cooldownID, category)
                    or nil
                callbacks.storeMirrorStateForIcon(icon, cooldownID, category, state)
            end
        end
        if callbacks.onBound then
            callbacks.onBound(icon, cooldownID, category)
        end
    end

    function controller:UnbindIcon(icon)
        controller:RemoveIcon(icon)
        if callbacks.onUnbound then
            callbacks.onUnbound(icon)
        end
    end

    function controller:Count()
        local mirrorIndexKeys = 0
        local mirrorIndexIcons = 0
        for _, byCooldownID in pairs(controller.byCategory) do
            for _, iconSet in pairs(byCooldownID) do
                mirrorIndexKeys = mirrorIndexKeys + 1
                for icon in pairs(iconSet) do
                    if icon then
                        mirrorIndexIcons = mirrorIndexIcons + 1
                    end
                end
            end
        end
        return mirrorIndexKeys, mirrorIndexIcons
    end


    function controller:PendingKeyCount()
        return CountPendingKeys(controller.pendingByCategory)
    end

    function controller:GetStats()
        return controller.stats
    end

    local function drainRefreshQueue()
        controller.refreshPending = false
        local pendingByCategory = controller.pendingByCategory
        controller.pendingByCategory = {}

        local batchKeys = CountPendingKeys(pendingByCategory)
        if batchKeys == 0 then return end

        local stats = controller.stats
        if mirrorStatsActive and batchKeys > stats.maxBatch then
            stats.maxBatch = batchKeys
        end

        local refreshed = 0
        local effectiveKeys = 0
        local editMode, ncdm, ncdmContainers, inCombat
        local batchStarted = false

        for category, byCooldownID in pairs(pendingByCategory) do
            for cooldownID in pairs(byCooldownID) do
                local iconSet = getIconSet(category, cooldownID, false)
                if iconSet then
                    local mirrorState = callbacks.getMirrorStateByCooldownID
                        and callbacks.getMirrorStateByCooldownID(cooldownID, category)
                        or nil
                    local keyHadIcon = false
                    for icon in pairs(iconSet) do
                        if icon
                            and icon._blizzMirrorCooldownID == cooldownID
                            and icon._blizzMirrorCategory == category
                            and callbacks.refreshIcon then
                            if callbacks.storeMirrorStateForIcon then
                                callbacks.storeMirrorStateForIcon(icon, cooldownID, category, mirrorState)
                            end
                            if not keyHadIcon then
                                effectiveKeys = effectiveKeys + 1
                                keyHadIcon = true
                            end
                            if not batchStarted then
                                if callbacks.prepareBatch then
                                    editMode, ncdm, ncdmContainers, inCombat = callbacks.prepareBatch()
                                end
                                if callbacks.setStackTextWrites then
                                    callbacks.setStackTextWrites(true)
                                end
                                if callbacks.beginBatch then
                                    callbacks.beginBatch()
                                end
                                batchStarted = true
                            end
                            if callbacks.refreshIcon(icon, editMode, ncdm, ncdmContainers, inCombat) then
                                refreshed = refreshed + 1
                            end
                        end
                    end
                end
            end
        end

        if mirrorStatsActive then stats.targeted = stats.targeted + effectiveKeys end

        if batchStarted then
            if callbacks.setStackTextWrites then
                callbacks.setStackTextWrites(false)
            end
            if callbacks.endBatch then
                callbacks.endBatch()
            end
        end

        if refreshed > 0 and callbacks.drainLayoutDirty then
            callbacks.drainLayoutDirty()
        end
    end

    local function drainRefreshFrame(_, elapsed)
        controller.refreshElapsed = controller.refreshElapsed + (elapsed or 0)
        if controller.refreshElapsed < controller.refreshDelay then return end
        if controller.refreshFrame then
            controller.refreshFrame:SetScript("OnUpdate", nil)
            controller.refreshFrame:Hide()
        end
        drainRefreshQueue()
    end

    function controller:RequestRefresh(cooldownID, category)
        if callbacks.isRuntimeEnabled and not callbacks.isRuntimeEnabled() then return end

        if not (cooldownID and category) then
            if mirrorStatsActive then controller.stats.fallback = controller.stats.fallback + 1 end
            return
        end

        local byCooldownID = controller.pendingByCategory[category]
        if not byCooldownID then
            byCooldownID = {}
            controller.pendingByCategory[category] = byCooldownID
        end
        byCooldownID[cooldownID] = true

        if controller.refreshPending then return end
        controller.refreshPending = true
        if InCombatLockdown and InCombatLockdown() then
            controller.refreshElapsed = 0
            controller.refreshDelay = callbacks.getCombatDelay and callbacks.getCombatDelay() or 0.2
            if not controller.refreshFrame then
                controller.refreshFrame = CreateFrame("Frame")
                controller.refreshFrame:Hide()
            end
            controller.refreshFrame:SetScript("OnUpdate", drainRefreshFrame)
            controller.refreshFrame:Show()
            return
        end

        if not (C_Timer and C_Timer.After) then
            drainRefreshQueue()
            return
        end

        C_Timer.After(0, drainRefreshQueue)
    end

    function controller:IsRefreshPending()
        return controller.refreshPending == true
    end

    return controller
end
