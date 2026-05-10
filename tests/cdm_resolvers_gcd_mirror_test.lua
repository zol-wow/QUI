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
local auraChildFrameDuration = { token = "aura-child-frame-duration" }
local mirrorSource = "aura-child-frame"

local ns = {
    Helpers = {},
    CDMSources = {
        QueryMirroredCooldownState = function(spellID, viewerType)
            if spellID == 12345 and viewerType == "essential" then
                return {
                    cooldownID = 777,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    mirrorEpoch = 5,
                    spellID = spellID,
                }
            end
        end,
        QuerySpellCharges = function() return nil end,
        QuerySpellCooldown = function(spellID)
            if spellID == 12345 then
                return { isActive = true }
            end
        end,
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            if spellID ~= 12345 then return nil end
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

ns.CDMResolvers._FinalizeImports({
    _trustIsOnGCDForBatch = true,
    _trustedGCDSpellState = {
        [12345] = true,
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
})

local icon = {
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        viewerType = "essential",
        type = "spell",
    },
}

local durObj, mode, sourceID = ns.CDMResolvers.ResolveIconDurationObject(icon)

assert(durObj == gcdDuration, "GCD-only live state should outrank a stale mirror duration")
assert(mode == "gcd-only", "GCD-only live state should resolve as gcd-only")
assert(sourceID == 12345, "GCD-only source should be the runtime spellID")

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
assert(mode == "aura", "child-frame aura mirror source should resolve as aura mode")

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
