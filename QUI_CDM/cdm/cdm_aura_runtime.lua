local _, ns = ...

---------------------------------------------------------------------------
-- CDM Aura Runtime
--
-- Runtime aura-state interface. CDMSpellData currently provides the adapter
-- implementation because it owns the UNIT_AURA capture indexes and scratch
-- helpers; callers consume this module instead of treating SpellData as a
-- parallel runtime truth source.
---------------------------------------------------------------------------

local CDMAuraRuntime = {}
ns.CDMAuraRuntime = CDMAuraRuntime

local resolveState
local getApplications
local getCapturedAura
local resolveAbilityAuraSpellID

function CDMAuraRuntime.SetResolver(callback)
    resolveState = callback
end

function CDMAuraRuntime.ResolveState(params)
    if resolveState then
        return resolveState(params)
    end
    return nil
end

function CDMAuraRuntime.SetApplicationsGetter(callback)
    getApplications = callback
end

function CDMAuraRuntime.GetApplications(unit, auraInstanceID)
    if getApplications then
        return getApplications(unit, auraInstanceID)
    end
    return nil
end

function CDMAuraRuntime.SetCapturedAuraGetter(callback)
    getCapturedAura = callback
end

function CDMAuraRuntime.GetCapturedAuraForLookup(...)
    if getCapturedAura then
        return getCapturedAura(...)
    end
    return nil
end

function CDMAuraRuntime.SetAbilityAuraSpellIDResolver(callback)
    resolveAbilityAuraSpellID = callback
end

function CDMAuraRuntime.ResolveAbilityAuraSpellID(spellID)
    if resolveAbilityAuraSpellID then
        return resolveAbilityAuraSpellID(spellID)
    end
    return spellID, false
end

function CDMAuraRuntime.HasAbilityAuraMapping(spellID)
    local _, remapped = CDMAuraRuntime.ResolveAbilityAuraSpellID(spellID)
    return remapped == true
end
