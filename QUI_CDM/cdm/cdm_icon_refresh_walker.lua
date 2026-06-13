local _, ns = ...

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

local measureFn -- profiler hook; bound at debug activation (nil otherwise)
local function SetupDebugInstrumentation()
    measureFn = ns.MemAuditProfilerMeasure
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

local function getIconPools(callbacks)
    return (callbacks.getIconPools and callbacks.getIconPools()) or {}
end

local function isAuraContainerType(containerType)
    return containerType == "aura" or containerType == "auraBar"
end

-- Per-icon cooldown-only processing shared by RefreshCooldownOnly (all pools)
-- and RefreshRuntimeType (one pool). Resolves the icon's container, skips aura
-- containers, then runs the cooldown refresh + visibility callbacks. Returns
-- true when the icon was refreshed so the caller can bump its counter.
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
