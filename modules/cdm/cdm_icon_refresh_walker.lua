local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- CDM Icon Refresh Walker
--
-- Private controller used by CDMIcons. It owns broad icon-pool traversal for
-- runtime refresh passes while CDMIcons supplies renderer mutation callbacks.
---------------------------------------------------------------------------

local CDMIconRefreshWalker = {}
ns.CDMIconRefreshWalker = CDMIconRefreshWalker

local pairs = pairs
local ipairs = ipairs

local function getIconPools(callbacks)
    return (callbacks.getIconPools and callbacks.getIconPools()) or {}
end

local function isAuraContainerType(containerType)
    return containerType == "aura" or containerType == "auraBar"
end

function CDMIconRefreshWalker.Create(callbacks)
    callbacks = callbacks or {}

    local controller = {}

    function controller:RefreshAll(context)
        local refreshed = 0
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                if callbacks.refreshAllIcon then
                    callbacks.refreshAllIcon(icon, context)
                    refreshed = refreshed + 1
                end
            end
        end
        return refreshed
    end

    function controller:RefreshCooldownOnly(context)
        context = context or {}
        local refreshed = 0
        for _, pool in pairs(getIconPools(callbacks)) do
            for _, icon in ipairs(pool) do
                local entry = icon and icon._spellEntry
                if entry then
                    local containerDB, containerType
                    if callbacks.resolveContainerDBAndType then
                        containerDB, containerType = callbacks.resolveContainerDBAndType(
                            entry, context.ncdm, context.ncdmContainers)
                    end
                    if not isAuraContainerType(containerType) then
                        if callbacks.refreshCooldownOnlyIcon then
                            callbacks.refreshCooldownOnlyIcon(icon, entry, context)
                        end
                        if callbacks.updateIconVisibility then
                            callbacks.updateIconVisibility(
                                icon, entry, containerDB, context.editMode, context.inCombat)
                        end
                        refreshed = refreshed + 1
                    end
                end
            end
        end
        return refreshed
    end

    function controller:RefreshType(viewerType, context)
        local pool = getIconPools(callbacks)[viewerType]
        if not pool then return 0 end

        local refreshed = 0
        for _, icon in ipairs(pool) do
            if callbacks.refreshTypeIcon then
                callbacks.refreshTypeIcon(icon, context)
                refreshed = refreshed + 1
            end
        end
        return refreshed
    end

    return controller
end
