-- tests/cdm_blizz_mirror_duration_test.lua
-- Run: lua tests/cdm_blizz_mirror_duration_test.lua

local function noop() end

local hooks = {}
local eventScript
local registeredEvents = {}
function hooksecurefunc(owner, method, hook)
    hooks[#hooks + 1] = { owner = owner, method = method, hook = hook }
    local original = owner[method] or noop
    owner[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

function InCombatLockdown() return false end
function GetTime() return 123 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
function CreateFrame()
    return {
        RegisterEvent = function(_, event)
            registeredEvents[event] = true
        end,
        RegisterUnitEvent = function(_, event)
            registeredEvents[event] = true
        end,
        SetScript = function(_, script, handler)
            if script == "OnEvent" then
                eventScript = handler
            end
        end,
    }
end
C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

local cooldownDuration = { token = "cooldown-duration-object" }
local chargeDuration = { token = "charge-duration-object" }
local auraSpellCooldownDuration = { token = "aura-spell-cooldown-duration-object" }
local auraHookDuration = { token = "aura-hook-duration-object" }
local auraPayloadDuration = { token = "aura-payload-duration-object" }
local auraUnitFallbackDuration = { token = "aura-unit-fallback-duration-object" }
local trackedBarAuraDuration = { token = "tracked-bar-aura-duration-object" }
local cooldownAuraMappedDuration = { token = "cooldown-aura-mapped-duration-object" }
local childFrameAuraDuration = { token = "child-frame-aura-duration-object" }
local relatedChildFrameAuraDuration = { token = "related-child-frame-aura-duration-object" }
local amzCooldownDuration = { token = "amz-cooldown-duration-object" }
local amzAuraDuration = { token = "amz-aura-duration-object" }
local iconRefreshCount = 0

C_Spell = {
    GetSpellCooldownDuration = function(spellID, ignoreGCD)
        if spellID == 1233448 and ignoreGCD == true then
            return cooldownDuration
        end
        if spellID == 1242998 and ignoreGCD == true then
            return auraSpellCooldownDuration
        end
        if spellID == 51052 and ignoreGCD == true then
            return amzCooldownDuration
        end
    end,
    GetSpellChargeDuration = function(spellID)
        if spellID == 444347 then
            return chargeDuration
        end
    end,
}

local child = {
    cooldownID = 27902,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
child.Cooldown.GetParent = function() return child end

local auraChild = {
    cooldownID = 73542,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
auraChild.Cooldown.GetParent = function() return auraChild end

local auraFallbackChild = {
    cooldownID = 141686,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
auraFallbackChild.Cooldown.GetParent = function() return auraFallbackChild end

local trackedBarChild = {
    cooldownID = 27925,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
trackedBarChild.Cooldown.GetParent = function() return trackedBarChild end

local cooldownAuraMappedChild = {
    cooldownID = 69057,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
cooldownAuraMappedChild.Cooldown.GetParent = function() return cooldownAuraMappedChild end

local reapingChild = {
    cooldownID = 70765,
    isActive = false,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
    SetShown = noop,
}
reapingChild.Cooldown.GetParent = function() return reapingChild end

local amzUtilityChild = {
    cooldownID = 27911,
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
}
amzUtilityChild.Cooldown.GetParent = function() return amzUtilityChild end

local amzBuffChild = {
    cooldownID = 103071,
    auraInstanceID = 707,
    auraDataUnit = "player",
    isActive = true,
    Cooldown = {
        SetCooldown = noop,
        SetCooldownFromDurationObject = noop,
        SetCooldownFromExpirationTime = noop,
        SetCooldownDuration = noop,
        SetCooldownUNIX = noop,
        Clear = noop,
    },
    Show = noop,
    Hide = noop,
    SetShown = noop,
}
amzBuffChild.Cooldown.GetParent = function() return amzBuffChild end

EssentialCooldownViewer = {
    GetChildren = function()
        return child
    end,
}
UtilityCooldownViewer = {
    GetChildren = function()
        return amzUtilityChild
    end,
}
BuffIconCooldownViewer = {
    GetChildren = function()
        return auraChild, auraFallbackChild, trackedBarChild, cooldownAuraMappedChild, reapingChild, amzBuffChild
    end,
}
BuffBarCooldownViewer = { GetChildren = function() end }

C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        if category == 0 then
            return { 27902 }
        end
        if category == 1 then
            return { 27911 }
        end
        if category == 2 then
            return { 73542, 141686, 70765, 103071 }
        end
        if category == 3 then
            return { 27925, 69057 }
        end
        return {}
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID)
        if cooldownID == 27902 then
            return {
                cooldownID = 27902,
                spellID = 1233448,
                overrideSpellID = 1233448,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 1235391 },
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 73542 then
            return {
                cooldownID = 73542,
                spellID = 137007,
                overrideSpellID = 137007,
                overrideTooltipSpellID = 1242998,
                linkedSpellIDs = { 1242998 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 141686 then
            return {
                cooldownID = 141686,
                spellID = 137007,
                overrideSpellID = 137007,
                overrideTooltipSpellID = 1254252,
                linkedSpellIDs = { 1254252 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 27925 then
            return {
                cooldownID = 27925,
                spellID = 1233448,
                overrideSpellID = 1233448,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 1235391 },
                selfAura = true,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 69057 then
            return {
                cooldownID = 69057,
                spellID = 1242158,
                overrideSpellID = 1242158,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 1242223 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 70765 then
            return {
                cooldownID = 70765,
                spellID = 377514,
                overrideSpellID = 377514,
                overrideTooltipSpellID = 1235261,
                linkedSpellIDs = { 1235261 },
                selfAura = true,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 27911 then
            return {
                cooldownID = 27911,
                spellID = 51052,
                overrideSpellID = 51052,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = nil,
                selfAura = false,
                hasAura = false,
                charges = false,
                isKnown = true,
            }
        end
        if cooldownID == 103071 then
            return {
                cooldownID = 103071,
                spellID = 51052,
                overrideSpellID = 51052,
                overrideTooltipSpellID = nil,
                linkedSpellIDs = { 145629 },
                selfAura = false,
                hasAura = true,
                charges = false,
                isKnown = true,
            }
        end
    end,
}

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    CDMIcons = {
        UpdateAllCooldowns = function()
            iconRefreshCount = iconRefreshCount + 1
        end,
    },
}

assert(loadfile("modules/cdm/cdm_sources.lua"))("QUI", ns)
assert(loadfile("modules/cdm/cdm_blizz_mirror.lua"))("QUI", ns)

ns.CDMBlizzMirror.ForceRescan()
child.Cooldown:SetCooldown()

local state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing")
assert(state.isActive == true, "SetCooldown should mark the mirror active")
assert(state.durObj == cooldownDuration, "SetCooldown should derive a safe spell cooldown DurationObject")
assert(state.cooldownDurObj == cooldownDuration, "spell cooldown should be carried in the cooldown lane")

child.wasSetFromAura = true
child.wasSetFromCooldown = false
child.wasSetFromCharges = false
child.Cooldown:SetCooldownFromDurationObject(auraHookDuration)

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after aura hook")
assert(state.auraDurObj == auraHookDuration, "non-aura entries should keep Blizzard aura duration in the aura lane")
assert(state.cooldownDurObj == cooldownDuration, "aura duration must not overwrite cooldown duration lane")
assert(state.durObj == auraHookDuration, "non-aura entries should select aura duration ahead of cooldown")
assert(state.durObjSource == "aura-duration", "selected duration source should identify the aura lane")

child.wasSetFromAura = false
child.wasSetFromCooldown = true
child.wasSetFromCharges = false
child.Cooldown:SetCooldownFromDurationObject(cooldownDuration)

state = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27902), "mirror state missing after cooldown hook")
assert(state.auraDurObj == nil, "cooldown hook should clear stale aura duration once Blizzard switches sources")
assert(state.cooldownDurObj == cooldownDuration, "cooldown duration should stay in the cooldown lane")
assert(state.durObj == cooldownDuration, "cooldown duration should be selected after the aura lane clears")

auraChild.Cooldown:SetCooldownFromDurationObject(auraSpellCooldownDuration)

local auraDurationState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542), "aura mirror state missing after DurationObject hook")
assert(auraDurationState.isActive == true, "aura DurationObject hook should mark the mirror active")
assert(auraDurationState.auraDurObj == auraSpellCooldownDuration, "aura viewer entries should mirror child DurationObjects into the aura lane")
assert(auraDurationState.auraDurObjSource == "aura-child", "aura child DurationObjects should be identified as the child source")
assert(auraDurationState.durObj == auraSpellCooldownDuration, "aura viewer entries should select child DurationObjects first")
assert(auraDurationState.durObjSource == "aura-child", "aura viewer selected duration source should identify the child")

auraChild.Cooldown:SetCooldown()

local auraState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542), "aura mirror state missing")
assert(auraState.isActive == true, "aura SetCooldown should mark the mirror active")
assert(auraState.durObj == auraSpellCooldownDuration, "aura SetCooldown should preserve the child DurationObject")
assert(auraState.durObjSource == "aura-child", "aura SetCooldown should not replace child duration with spell cooldown")

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 101 then
        return auraPayloadDuration
    end
end

ns.CDMBlizzMirror.HandleUnitAuraChanged("player", {
    addedAuras = {
        { spellId = 1242998, auraInstanceID = 101 },
    },
})

auraState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(73542), "aura mirror state missing after UNIT_AURA payload")
assert(auraState.isActive == true, "UNIT_AURA payload should preserve active aura state")
assert(auraState.hasAuraInstanceID == true, "UNIT_AURA payload should still stamp the aura instance")
assert(auraState.auraDurObj == auraSpellCooldownDuration, "UNIT_AURA payload should not overwrite the child DurationObject")
assert(auraState.durObj == auraSpellCooldownDuration, "aura viewer entries should keep selecting child duration first")
assert(auraState.durObjSource == "aura-child", "child duration should stay selected after UNIT_AURA payload")

local queriedPlayerAura = false
local queriedUnitAura = false
ns.CDMSources.QueryPlayerAuraBySpellID = function(spellID)
    if spellID == 1254252 then
        queriedPlayerAura = true
    end
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID)
    if unit == "player" and spellID == 1254252 then
        queriedUnitAura = true
        return { spellId = 1254252, auraInstanceID = 202 }
    end
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 202 then
        return auraUnitFallbackDuration
    end
end

ns.CDMBlizzMirror.HandleUnitAuraChanged("player", { isFullUpdate = true })

local fallbackState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(141686), "fallback aura mirror state missing")
assert(queriedPlayerAura == true, "test must exercise the player aura lookup miss")
assert(queriedUnitAura == true, "player aura scan should fall back to unit aura lookup")
assert(fallbackState.auraDurObj == auraUnitFallbackDuration, "unit aura fallback should stamp the aura DurationObject")
assert(fallbackState.durObj == auraUnitFallbackDuration, "aura viewer should select the unit fallback DurationObject")

local queriedTrackedBarAura = false
ns.CDMSources.QueryPlayerAuraBySpellID = function(spellID)
    if spellID == 1235391 then
        queriedTrackedBarAura = true
        return { spellId = 1235391, auraInstanceID = 303 }
    end
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 303 then
        return trackedBarAuraDuration
    end
end

trackedBarChild.Cooldown:SetCooldown()

local trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar mirror state missing")
assert(queriedTrackedBarAura == true, "trackedBar SetCooldown should query the linked aura identity")
assert(trackedBarState.isActive == true, "trackedBar SetCooldown should mark the aura active")
assert(trackedBarState.hasAuraInstanceID == true, "trackedBar SetCooldown should stamp the aura instance")
assert(trackedBarState.auraDurObj == trackedBarAuraDuration, "trackedBar SetCooldown should capture the aura DurationObject")
assert(trackedBarState.durObj == trackedBarAuraDuration, "trackedBar aura entries should select captured aura DurationObjects")

local trackedPayload = assert(ns.CDMBlizzMirror.GetCooldownMethodTestPayload(27925, "trackedBar"), "trackedBar test payload missing")
local foundCurrentFieldProbe = false
local foundRelatedEssentialProbe = false
for _, line in ipairs(trackedPayload.auraProbeLines or {}) do
    if line:find("frameField label=current.trackedBar.27925.child key=auraInstanceID", 1, true) then
        foundCurrentFieldProbe = true
    end
    if line:find("related cat=essential", 1, true) then
        foundRelatedEssentialProbe = true
    end
end
assert(foundCurrentFieldProbe == true, "trackedBar payload should probe current child aura fields")
assert(foundRelatedEssentialProbe == true, "trackedBar payload should probe the related essential child")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = 505
trackedBarChild.auraDataUnit = "player"
ns.CDMSources.QueryPlayerAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 505 then
        return childFrameAuraDuration
    end
end

trackedBarChild.Cooldown:SetCooldown()

trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar child-frame state missing")
assert(trackedBarState.hasAuraInstanceID == true, "trackedBar child auraInstanceID should stamp the mirror")
assert(trackedBarState.auraDurObj == childFrameAuraDuration, "trackedBar child auraInstanceID should capture the DurationObject")
assert(trackedBarState.durObj == childFrameAuraDuration, "trackedBar child auraInstanceID should drive the selected duration")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = nil
trackedBarChild.auraDataUnit = nil
child.auraInstanceID = 606
child.auraDataUnit = "player"
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 606 then
        return relatedChildFrameAuraDuration
    end
end

trackedBarChild.Cooldown:SetCooldown()

trackedBarState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27925, "trackedBar"), "trackedBar related-frame state missing")
assert(trackedBarState.hasAuraInstanceID == true, "related cooldown child auraInstanceID should stamp trackedBar mirror")
assert(trackedBarState.auraDurObj == relatedChildFrameAuraDuration, "related cooldown child should provide trackedBar aura DurationObject")
assert(trackedBarState.durObj == relatedChildFrameAuraDuration, "related cooldown child duration should drive trackedBar duration")

trackedBarChild.Cooldown:Clear()
trackedBarChild.auraInstanceID = nil
trackedBarChild.auraDataUnit = nil
child.auraInstanceID = nil
child.auraDataUnit = nil

local queriedCooldownAuraMap = false
local queriedMappedFilteredAura = false
ns.CDMSources.QueryCooldownAuraBySpellID = function(spellID)
    if spellID == 1242158 then
        queriedCooldownAuraMap = true
        return 555001
    end
    return nil
end
ns.CDMSources.QueryPlayerAuraBySpellID = function()
    return nil
end
ns.CDMSources.QueryUnitAuraBySpellID = function(unit, spellID, filter)
    if unit == "player" and spellID == 555001 and filter == "HELPFUL" then
        queriedMappedFilteredAura = true
        return { spellId = 555001, auraInstanceID = 404 }
    end
    return nil
end
ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 404 then
        return cooldownAuraMappedDuration
    end
end

cooldownAuraMappedChild.Cooldown:SetCooldown()

local cooldownAuraMappedState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(69057, "trackedBar"), "cooldown-aura mapped state missing")
assert(queriedCooldownAuraMap == true, "trackedBar capture should query the cooldown-aura spell mapping")
assert(queriedMappedFilteredAura == true, "trackedBar capture should try filtered aura lookup for mapped IDs")
assert(cooldownAuraMappedState.hasAuraInstanceID == true, "mapped cooldown-aura lookup should stamp the aura instance")
assert(cooldownAuraMappedState.durObj == cooldownAuraMappedDuration, "mapped cooldown-aura lookup should capture the DurationObject")

ns.CDMSources.QueryAuraDuration = function(unit, auraInstanceID)
    if unit == "player" and auraInstanceID == 707 then
        return amzAuraDuration
    end
end

amzBuffChild.auraInstanceID = nil
amzBuffChild.auraDataUnit = nil
amzUtilityChild.Cooldown:SetCooldown()
local amzUtilityState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27911, "utility"), "AMZ utility mirror state missing before aura")
assert(amzUtilityState.cooldownDurObj == amzCooldownDuration, "AMZ utility should start with its own spell cooldown lane")
assert(amzUtilityState.auraDurObj == nil, "AMZ utility should not have an aura lane before the related buff child has an instance")

amzBuffChild.auraInstanceID = 707
amzBuffChild.auraDataUnit = "player"
amzBuffChild:SetShown(true)
local amzBuffState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(103071, "buff"), "AMZ buff mirror state missing")
assert(amzBuffState.isActive == true, "AMZ buff child auraInstanceID should make the buff mirror active")
assert(amzBuffState.hasAuraInstanceID == true, "AMZ buff child auraInstanceID should be stamped")
assert(amzBuffState.auraDurObj == amzAuraDuration, "AMZ buff child auraInstanceID should capture the aura duration")

amzUtilityState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(27911, "utility"), "AMZ utility mirror state missing after aura")
assert(amzUtilityState.isActive == true, "AMZ utility child should stay active")
assert(amzUtilityState.cooldownDurObj == amzCooldownDuration, "AMZ utility should keep its own spell cooldown lane")
assert(amzUtilityState.hasAuraInstanceID == true, "AMZ utility should borrow the related buff child aura instance")
assert(amzUtilityState.auraUnit == "player", "AMZ utility should trust the related buff child aura unit")
assert(amzUtilityState.auraDurObj == amzAuraDuration, "AMZ utility should borrow the related buff child aura duration")
assert(amzUtilityState.durObj == amzAuraDuration, "AMZ utility should select the related aura duration ahead of cooldown")
assert(amzUtilityState.durObjSource == "aura-related-child", "AMZ utility selected duration should identify the related aura child")

local reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing")
assert(reapingState.isActive == false, "Reaping test should start inactive")

local refreshBeforeSetShown = iconRefreshCount
reapingChild.isActive = true
reapingChild:SetShown(true)

reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing after SetShown")
assert(reapingState.isActive == true, "durationless buff child SetShown should mirror child.isActive")
assert(reapingState.durObj == nil, "durationless buff child should not invent a DurationObject")
assert(iconRefreshCount > refreshBeforeSetShown, "durationless buff child SetShown should request an icon refresh")

reapingChild.isActive = false
reapingChild:SetShown(false)
reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing after SetShown false")
assert(reapingState.isActive == false, "durationless buff child SetShown(false) should clear active state")

assert(registeredEvents.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW == true,
    "mirror should listen for spell activation overlay show events")
assert(registeredEvents.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE == true,
    "mirror should listen for spell activation overlay hide events")
assert(type(eventScript) == "function", "mirror event script should be installed")

local refreshBeforeOverlay = iconRefreshCount
reapingChild.isActive = true
eventScript(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1235261)

reapingState = assert(ns.CDMBlizzMirror.GetStateByCooldownID(70765, "buff"), "Reaping buff mirror state missing after overlay event")
assert(reapingState.isActive == true, "spell activation overlay should refresh durationless buff child state")
assert(iconRefreshCount > refreshBeforeOverlay, "spell activation overlay should request an icon refresh")

local mirrorStats = ns.CDMBlizzMirror.GetCacheStats and ns.CDMBlizzMirror.GetCacheStats()
assert(mirrorStats, "mirror should expose cache stats")
assert(mirrorStats.mirrorStates >= 1, "mirror stats should include mirrored state count")
assert(mirrorStats.cooldownInfo >= 1, "mirror stats should include cooldown info count")
assert(mirrorStats.spellMapEntries >= 1, "mirror stats should include spell map entry count")

print("OK: cdm_blizz_mirror_duration_test")
