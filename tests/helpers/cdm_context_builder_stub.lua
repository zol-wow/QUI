-- Shared test stub for CDMResolvers.BuildCooldownStateContext.
-- Keep this shape aligned with the production resolver-owned context contract.

return function(owner, entry, runtimeSpellID, options)
    local context = options and options.context
    local contextKey = options and options.contextKey or "_cooldownStateContext"
    if not context and owner then
        context = owner[contextKey]
        if not context then
            context = {}
            owner[contextKey] = context
        end
    end
    if not context then
        context = {}
    end

    context.owner = nil
    context.entry = nil
    context.runtimeSpellID = nil
    context.containerKey = nil
    context.totemSlot = nil
    context.useBuffSwipe = nil
    context.skipAuraPhase = nil
    context.showGCDSwipe = nil
    context.lastChargeRuntimeSpellID = nil

    local containerKey = options and options.containerKey
    if containerKey == nil then
        containerKey = entry and entry.viewerType
    end
    if containerKey == nil and options then
        containerKey = options.fallbackContainerKey
    end

    context.owner = owner
    context.entry = entry
    context.runtimeSpellID = runtimeSpellID
    context.containerKey = containerKey
    context.totemSlot = (options and options.totemSlot)
        or (owner and owner._totemSlot)
    context.useBuffSwipe = options and options.useBuffSwipe
    context.skipAuraPhase = options and options.skipAuraPhase == true
    context.showGCDSwipe = options and options.showGCDSwipe == true
    context.lastChargeRuntimeSpellID = options and options.lastChargeRuntimeSpellID
    return context
end
