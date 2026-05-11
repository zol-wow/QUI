-- tests/cdm_resolvers_gcd_mirror_test.lua
-- Run: lua tests/cdm_resolvers_gcd_mirror_test.lua

local function noop() end

function InCombatLockdown() return false end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local mirrorDuration = { token = "stale-mirror-duration" }
local gcdDuration = { token = "gcd-duration" }
local misleadingCooldownDuration = { token = "misleading-cooldown-duration" }
local realCooldownDuration = { token = "real-cooldown-duration" }
local auraChildFrameDuration = { token = "aura-child-frame-duration" }
local mirrorSource = "aura-child-frame"
local gcdSpellFallbackEnabled = false

local ns = {
    Helpers = {},
    CDMSources = {
        QueryMirroredCooldownState = function(spellID, viewerType)
            if (spellID == 12345 or spellID == 33333 or spellID == 44444 or spellID == 55555 or spellID == 11111) and viewerType == "essential" then
                return {
                    cooldownID = 777,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    mirrorEpoch = 5,
                    spellID = spellID,
                }
            end
            if (spellID == 66666 or spellID == 66667) and viewerType == "essential" then
                return {
                    cooldownID = 778,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-charge",
                    mirrorEpoch = 6,
                    spellID = spellID,
                }
            end
        end,
        QuerySpellCharges = function(spellID)
            if spellID == 66666 then
                return { currentCharges = 2, maxCharges = 2, isActive = false }
            end
            if spellID == 66667 then
                return { currentCharges = 1, maxCharges = 2, isActive = true }
            end
            if spellID == 88888 then
                return { currentCharges = 2, maxCharges = 2, isActive = false }
            end
            return nil
        end,
        QuerySpellCooldown = function(spellID)
            if spellID == 12345 then
                return { isActive = true }
            end
            if spellID == 33333 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 55555 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 11111 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 77777 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 66666 or spellID == 66667 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 88888 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 99999 then
                return { isActive = true, isOnGCD = true, realCooldown = true }
            end
            if spellID == 44444 then
                return { isActive = false }
            end
            if spellID == 22222 or spellID == 54321 then
                return { isActive = false }
            end
        end,
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            if spellID == 61304 and gcdSpellFallbackEnabled then
                return gcdDuration
            end
            if spellID == 88888 then
                if ignoreGCD == true then
                    return misleadingCooldownDuration
                end
                return nil
            end
            if spellID == 11111 then
                if ignoreGCD == true then
                    return misleadingCooldownDuration
                end
                return nil
            end
            if spellID == 99999 and ignoreGCD == true then
                return realCooldownDuration
            end
            if spellID == 55555 or spellID == 77777 or spellID == 66666 or spellID == 66667 then
                return nil
            end
            if spellID ~= 12345
               and spellID ~= 22222
               and spellID ~= 33333
               and spellID ~= 54321 then
                return nil
            end
            if ignoreGCD == true then
                return nil
            end
            return gcdDuration
        end,
        QueryOverrideSpell = function() return nil end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, viewerCategory)
            if cooldownID == 888 and viewerCategory == "essential" then
                return {
                    cooldownID = cooldownID,
                    isActive = true,
                    durObj = auraChildFrameDuration,
                    durObjSource = mirrorSource,
                    mirrorEpoch = 6,
                    spellID = 54321,
                }
            end
        end,
    },
}

assert(loadfile("modules/cdm/cdm_resolvers.lua"))("QUI", ns)

local cdmIcons = {
    _trustIsOnGCDForBatch = true,
    _trustedGCDSpellState = {
        [12345] = true,
        [22222] = true,
        [54321] = true,
    },
    ApplyAuraStateToIcon = function()
        return nil, false, nil
    end,
    GetCooldownInfoField = function(info, key)
        return info and info[key]
    end,
    IsGCDSwipeEnabled = function()
        return true
    end,
    IsItemLikeEntry = function()
        return false
    end,
    QueryOverrideSpell = function()
        return nil
    end,
    ShouldUseBuffSwipeForIcon = function()
        return false
    end,
    IsCooldownInfoRealCooldown = function(info)
        if info and info.realCooldown ~= nil then
            return info.realCooldown
        end
        if info and info.isOnGCD == true then
            return false
        end
        return nil
    end,
    SpellHasBaseCooldownLongerThanGCD = function(spellID)
        return spellID == 99999
    end,
}

ns.CDMResolvers._FinalizeImports(cdmIcons)

local icon = {
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        viewerType = "essential",
        type = "spell",
    },
}

local durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(icon)

assert(durObj == gcdDuration, "trusted GCD state should outrank a stale mirror duration")
assert(mode == "gcd-only", "trusted GCD state should resolve as gcd-only")
assert(sourceID == 12345, "GCD-only source should be the runtime spellID")

cdmIcons._trustIsOnGCDForBatch = false
cdmIcons._trustedGCDSpellState = {}

local liveCooldownGCDIcon = {
    _spellEntry = {
        id = 33333,
        spellID = 33333,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(liveCooldownGCDIcon)

assert(durObj == gcdDuration, "live isOnGCD should render GCD when trusted batch state is absent")
assert(mode == "gcd-only", "live isOnGCD should resolve as gcd-only")
assert(sourceID == 33333, "live isOnGCD source should be the runtime spellID")

local mirroredGCDIcon = {
    _spellEntry = {
        id = 55555,
        spellID = 55555,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(mirroredGCDIcon)

assert(durObj == mirrorDuration, "GCD mirror duration should be reused when spell-specific GCD duration is missing")
assert(mode == "gcd-only", "GCD mirror duration should resolve as gcd-only")
assert(sourceID == 55555, "GCD mirror source should use the runtime spellID for stable binding")

local misleadingMirroredCooldownIcon = {
    _spellEntry = {
        id = 11111,
        spellID = 11111,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(misleadingMirroredCooldownIcon)

assert(durObj == mirrorDuration, "spell-cooldown mirror duration should be reused as GCD when live state is only GCD")
assert(mode == "gcd-only", "spell-cooldown mirror during GCD should resolve as gcd-only, got " .. tostring(mode))
assert(sourceID == 11111, "spell-cooldown mirror GCD source should use runtime spellID")

gcdSpellFallbackEnabled = true
local gcdSpellFallbackIcon = {
    _spellEntry = {
        id = 77777,
        spellID = 77777,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(gcdSpellFallbackIcon)

assert(durObj == gcdDuration, "GCD spell duration should be used when spell-specific duration is missing")
assert(mode == "gcd-only", "GCD spell fallback should resolve as gcd-only")
assert(sourceID == 77777, "GCD spell fallback source should remain the runtime spellID")
gcdSpellFallbackEnabled = false

local staleChargeMirrorGCDIcon = {
    _spellEntry = {
        id = 66666,
        spellID = 66666,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(staleChargeMirrorGCDIcon)

assert(durObj == mirrorDuration, "inactive charge mirror duration should be reused as GCD when GCD duration is missing")
assert(mode == "gcd-only", "inactive charge mirror during GCD should resolve as gcd-only, got " .. tostring(mode))
assert(sourceID == 66666, "inactive charge mirror GCD source should use runtime spellID")

local activeChargeMirrorIcon = {
    _spellEntry = {
        id = 66667,
        spellID = 66667,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(activeChargeMirrorIcon)

assert(durObj == mirrorDuration, "active charge mirror should remain selected")
assert(mode == "charge", "active charge mirror should remain charge mode even during GCD")

local misleadingLiveCooldownIcon = {
    _spellEntry = {
        id = 88888,
        spellID = 88888,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(misleadingLiveCooldownIcon)

assert(durObj == misleadingCooldownDuration, "inactive charge live cooldown duration should be reused as GCD when no GCD duration is available")
assert(mode == "gcd-only", "inactive charge live cooldown duration during GCD should resolve as gcd-only, got " .. tostring(mode))
assert(sourceID == 88888, "inactive charge live cooldown GCD source should use runtime spellID")

local realCooldownDuringGCDIcon = {
    _spellEntry = {
        id = 99999,
        spellID = 99999,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(realCooldownDuringGCDIcon)

assert(durObj == realCooldownDuration, "real cooldown duration should remain selected during GCD")
assert(mode == "cooldown", "real cooldown duration should remain cooldown mode during GCD")
assert(sourceID == 99999, "real cooldown source should use runtime spellID")

local staleInactiveMirrorIcon = {
    _spellEntry = {
        id = 44444,
        spellID = 44444,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(staleInactiveMirrorIcon)

assert(durObj == nil, "inactive live cooldown state should clear stale mirror cooldown duration")
assert(mode == "inactive", "inactive live cooldown state should resolve inactive despite stale mirror")
assert(sourceID == nil, "inactive stale mirror source should be nil")

local mirrorPolicyStats = ns.CDMResolvers.GetMirrorPolicyStats and ns.CDMResolvers.GetMirrorPolicyStats()
assert(mirrorPolicyStats, "resolver should expose mirror policy stats")
assert(mirrorPolicyStats.staleGCDSkips == 2, "stale GCD mirror skips should be counted")
assert(mirrorPolicyStats.staleInactiveSkips == 1, "stale inactive mirror skip should be counted")

cdmIcons._trustIsOnGCDForBatch = true
cdmIcons._trustedGCDSpellState = {
    [12345] = true,
    [22222] = true,
    [54321] = true,
}

local inactiveCooldownGCDIcon = {
    _spellEntry = {
        id = 22222,
        spellID = 22222,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(inactiveCooldownGCDIcon)

assert(durObj == gcdDuration, "trusted isOnGCD should render GCD even when cooldown isActive is false")
assert(mode == "gcd-only", "inactive cooldown GCD state should resolve as gcd-only")
assert(sourceID == 22222, "inactive cooldown GCD source should be the runtime spellID")

local auraBackedCooldownIcon = {
    _blizzMirrorCooldownID = 888,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        id = 54321,
        spellID = 54321,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode = ns.CDMResolvers.ResolveIconDurationObject(auraBackedCooldownIcon)

assert(durObj == auraChildFrameDuration, "child-frame aura mirror duration should be selected")
assert(mode == "aura", "child-frame aura mirror source should resolve as aura mode even during GCD")

mirrorSource = "aura-related-child"
durObj, mode = ns.CDMResolvers.ResolveIconDurationObject(auraBackedCooldownIcon)

assert(durObj == auraChildFrameDuration, "related-child aura mirror duration should be selected")
assert(mode == "aura", "related-child aura mirror source should resolve as aura mode")

local trackedBarEntry = {
    id = 67890,
    spellID = 67890,
    viewerType = "trackedBar",
    type = "spell",
}
local trackedBarIcon = {
    _spellEntry = trackedBarEntry,
}

assert(ns.CDMResolvers.HasRealCooldownState(
    trackedBarIcon,
    trackedBarEntry,
    30,
    true,
    true,
    mirrorDuration,
    67890) == false, "trackedBar entries should use aura shape, not real-cooldown shape")

print("OK: cdm_resolvers_gcd_mirror_test")
