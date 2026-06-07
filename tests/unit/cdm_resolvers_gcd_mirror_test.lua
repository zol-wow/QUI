-- tests/unit/cdm_resolvers_gcd_mirror_test.lua
-- Run: lua tests/unit/cdm_resolvers_gcd_mirror_test.lua
-- luacheck: globals InCombatLockdown geterrorhandler CreateFrame issecretvalue
-- luacheck: ignore 111

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
local liveChargeDuration = { token = "live-charge-duration" }
local misleadingCooldownDuration = { token = "misleading-cooldown-duration" }
local realCooldownDuration = { token = "real-cooldown-duration" }
local auraChildFrameDuration = { token = "aura-child-frame-duration" }
local auraMirrorDuration = { token = "aura-mirror-duration" }
local auraMirrorData = { token = "aura-mirror-data", icon = 98765 }
local ownedTargetAuraData = { token = "owned-target-aura-data", isFromPlayerOrPlayerPet = true }
local foreignTargetAuraData = { token = "foreign-target-aura-data", isFromPlayerOrPlayerPet = false }
local mirrorSource = "aura-child-frame"
local gcdSpellFallbackEnabled = false
local cooldownQueryCounts = {}
local auraDataQueryCount = 0
local SECRET_COOLDOWN_FIELD = { token = "secret-cooldown-field" }
-- Per-spell isOnGCD overrides applied to the cdInfo QuerySpellCooldown returns.
-- The resolver reads isOnGCD directly off cdInfo (NeverSecret), so injecting it
-- here is how a test primes a spell's GCD state. Managed via setGCDState below.
local gcdOverrides = {}

function issecretvalue(value)
    return value == SECRET_COOLDOWN_FIELD
end

local ns = {
    Helpers = {
        IsAuraOwnedByPlayerOrPet = function(auraData)
            return auraData and auraData.isFromPlayerOrPlayerPet == true
        end,
    },
    CDMSources = {
        QueryMirroredCooldownState = function(spellID, viewerType)
            if spellID == 44444 and viewerType == "essential" then
                return {
                    cooldownID = 777,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    mirrorEpoch = 5,
                    spellID = spellID,
                    cooldownIsActive = false,
                }
            end
            if spellID == 55555 and viewerType == "essential" then
                return {
                    cooldownID = 777,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "gcd-duration",
                    resolvedMode = "gcd-only",
                    mirrorEpoch = 5,
                    spellID = spellID,
                }
            end
            if spellID == 1227280 and viewerType == "essential" then
                return {
                    cooldownID = 8203,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "gcd-duration",
                    resolvedMode = "gcd-only",
                    mirrorEpoch = 19,
                    spellID = spellID,
                }
            end
            if spellID == 1227281 and viewerType == "essential" then
                return {
                    cooldownID = 8204,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    -- cdm_blizz_mirror.lua:732 packs cooldownDurObj as the
                    -- production field name; the legacy `durObj` field above
                    -- isn't read by the resolver. Set both so the assertion
                    -- "active live recharge should not override a mirror
                    -- cooldown duration" exercises the m.cooldownDurObj
                    -- short-circuit instead of the QueryDuration fallback.
                    cooldownDurObj = mirrorDuration,
                    resolvedMode = "cooldown",
                    mirrorEpoch = 21,
                    spellID = spellID,
                }
            end
            if spellID == 202020 and viewerType == "essential" then
                return {
                    cooldownID = 781,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    resolvedMode = "gcd-only",
                    mirrorEpoch = 10,
                    spellID = spellID,
                }
            end
            if spellID == 242424 and viewerType == "essential" then
                return {
                    cooldownID = 782,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    resolvedMode = "cooldown",
                    mirrorEpoch = 12,
                    spellID = spellID,
                }
            end
            if spellID == 252525 and viewerType == "essential" then
                return {
                    cooldownID = 783,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    resolvedMode = "cooldown",
                    mirrorEpoch = 14,
                    spellID = spellID,
                }
            end
            if spellID == 262626 and viewerType == "essential" then
                return {
                    cooldownID = 784,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    resolvedMode = "cooldown",
                    mirrorEpoch = 15,
                    spellID = spellID,
                    hasAura = false,
                }
            end
            if (spellID == 11111 or spellID == 181818 or spellID == 181819 or spellID == 181820) and viewerType == "essential" then
                return {
                    cooldownID = 777,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    mirrorEpoch = 5,
                    spellID = spellID,
                    childIsActive = (spellID == 181818 or spellID == 181819 or spellID == 181820) and true or nil,
                    wasSetFromCooldown = (spellID == 181818 or spellID == 181819 or spellID == 181820) and true or nil,
                }
            end
            if spellID == 181821 and viewerType == "essential" then
                return {
                    cooldownID = 781,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "gcd-duration",
                    resolvedMode = "gcd-only",
                    mirrorEpoch = 9,
                    spellID = spellID,
                    childIsActive = true,
                    wasSetFromCooldown = true,
                }
            end
            if spellID == 191919 and viewerType == "essential" then
                return {
                    cooldownID = 780,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-cooldown",
                    mirrorEpoch = 9,
                    spellID = spellID,
                    childIsActive = true,
                    cooldownIsActive = true,
                    wasSetFromCooldown = true,
                }
            end
            if (spellID == 161616 or spellID == 171717) and viewerType == "essential" then
                return {
                    cooldownID = 779,
                    mirrorEpoch = 7,
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
            if spellID == 1247378 and viewerType == "essential" then
                -- Putrefy (Unholy DK) reference case: a known multi-charge
                -- essential mirror. charges=true keeps HasActiveChargeRecharge's
                -- combat gate satisfied so the recharge is detected in lockdown.
                return {
                    cooldownID = 27991,
                    isActive = true,
                    durObj = mirrorDuration,
                    durObjSource = "spell-charge",
                    mirrorEpoch = 27,
                    spellID = spellID,
                    charges = true,
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
            if spellID == 1227280 then
                return { currentCharges = 1, maxCharges = 2, isActive = true }
            end
            if spellID == 1227281 then
                return { currentCharges = 1, maxCharges = 2, isActive = true }
            end
            if spellID == 1247378 then
                return { currentCharges = 1, maxCharges = 3, isActive = true }
            end
            return nil
        end,
        QuerySpellChargeDuration = function(spellID)
            if spellID == 1227280 or spellID == 1227281 or spellID == 1247378 then
                return liveChargeDuration
            end
            return nil
        end,
        QuerySpellCooldown = function(spellID)
            cooldownQueryCounts[spellID] = (cooldownQueryCounts[spellID] or 0) + 1
            local info = (function()
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
                -- After mirror→resolver refactor: live isOnGCD wins. The
                -- old test asserted mirror cooldown stays "cooldown" through
                -- a live GCD; the new design routes through gcd-only.
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
                return { isActive = true, isOnGCD = true, activeCategory = "spell" }
            end
            if spellID == 439843 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 121212 then
                return { isActive = true, isOnGCD = true, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 131313 then
                return { isActive = true, isOnGCD = true, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 141414 then
                return { isActive = true, isOnGCD = false, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 141415 then
                return { isActive = true, isOnGCD = true, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 151515 then
                return { isActive = true, isOnGCD = false, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 151516 then
                return { isActive = true, isOnGCD = true, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 161616 then
                -- Cooldown-frame mirror: real CD + GCD overlap scenario.
                -- Set isOnGCD=false so the resolver derives cooldown mode
                -- from live cdInfo. (The pre-refactor design distinguished
                -- "real CD masquerading as GCD" via secret activeCategory,
                -- now collapsed.)
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 171717 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 44444 then
                return { isActive = false }
            end
            if spellID == 181818 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 181819 then
                return { isActive = true, isOnGCD = true, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 181820 then
                return { isActive = true, isOnGCD = true, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 181821 then
                return { isActive = false, isOnGCD = false }
            end
            if spellID == 191919 then
                return { isActive = true, isOnGCD = true, activeCategory = SECRET_COOLDOWN_FIELD }
            end
            if spellID == 212121 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 232323 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 242424 then
                return { isActive = true, isOnGCD = true, startTime = 10, duration = 1.5 }
            end
            if spellID == 252525 then
                return { isActive = true, isOnGCD = false, startTime = 0, duration = 0 }
            end
            if spellID == 85948 then
                return { isActive = true, isOnGCD = true, startTime = 10, duration = 1.5 }
            end
            if spellID == 458128 then
                return { isActive = true, isOnGCD = false, startTime = 10, duration = 18, activeCategory = "spell" }
            end
            if spellID == 357210 then
                -- Breath of Eons base (Deep Breath): no cooldown of its own,
                -- so an incidental GCD from casting any other spell reads
                -- isActive=true, isOnGCD=true on the base.
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 403631 then
                -- Breath of Eons override (Augmentation): carries the real
                -- ~2-min cooldown and is never on the GCD.
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 1227281 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 1247378 then
                -- Recharging a charge while an incidental GCD (from casting
                -- another spell) sits on the cooldown lane: isActive=true,
                -- isOnGCD=true. The charge recharge must still win.
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 262626 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 22222 or spellID == 54321 then
                return { isActive = false }
            end
            end)()
            if info and gcdOverrides[spellID] ~= nil then
                info.isOnGCD = gcdOverrides[spellID]
            end
            return info
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
            if spellID == 121212 then
                if ignoreGCD == true then
                    return misleadingCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 131313 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 141414 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return nil
            end
            if spellID == 141415 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 151515 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return nil
            end
            if spellID == 151516 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 161616 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 171717 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return nil
            end
            if spellID == 181820 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 191919 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 212121 then
                if ignoreGCD == true then
                    return nil
                end
                return gcdDuration
            end
            if spellID == 232323 then
                if ignoreGCD == true then
                    return nil
                end
                return gcdDuration
            end
            if spellID == 242424 then
                if ignoreGCD == true then
                    return nil
                end
                return gcdDuration
            end
            if spellID == 85948 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return gcdDuration
            end
            if spellID == 252525 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return nil
            end
            if spellID == 458128 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return nil
            end
            if spellID == 403631 then
                if ignoreGCD == true then
                    return realCooldownDuration
                end
                return nil
            end
            if spellID == 55555 then
                -- mirror→resolver refactor: durObj comes from live API.
                if ignoreGCD == false then return mirrorDuration end
                return nil
            end
            if (spellID == 1227281 or spellID == 262626) and ignoreGCD == true then
                return mirrorDuration
            end
            if spellID == 77777 or spellID == 66666 or spellID == 66667 then
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
        QuerySpellUsable = function(spellID)
            if spellID == 141414 or spellID == 141415 or spellID == 181820 or spellID == 191919 then
                return true, false
            end
            if spellID == 85948 then
                return true, false
            end
            if spellID == 252525 then
                return true, false
            end
            if spellID == 458128 then
                return false, true
            end
            if spellID == 151515 or spellID == 151516 or spellID == 212121 then
                return false, true
            end
            return nil, nil
        end,
        QueryOverrideSpell = function() return nil end,
        QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
            auraDataQueryCount = auraDataQueryCount + 1
            if unit == "player" and auraInstanceID == 808 then
                return auraMirrorData
            end
            if unit == "target" and auraInstanceID == 810 then
                return ownedTargetAuraData
            end
            if unit == "target" and auraInstanceID == 811 then
                return foreignTargetAuraData
            end
            if unit == "player" and auraInstanceID == 8888 then
                return { auraInstanceID = 8888, isFromPlayerOrPlayerPet = true }
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, viewerCategory)
            if cooldownID == 888 and viewerCategory == "essential" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 6,
                    spellID = 54321,
                    hasAura = true,
                    auraInstanceID = 8888,
                    auraUnit = "player",
                    auraData = { auraInstanceID = 8888, isFromPlayerOrPlayerPet = true },
                    auraDurObj = auraChildFrameDuration,
                    auraDurObjSource = mirrorSource,
                }
            end
            if cooldownID == 889 and viewerCategory == "buff" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 13,
                    spellID = 70765,
                    viewerCategory = "buff",
                    selfAura = true,
                    hasAura = true,
                    auraInstanceID = 808,
                    auraUnit = "player",
                    auraDurObj = auraMirrorDuration,
                    auraDurObjSource = "aura-duration",
                }
            end
            if cooldownID == 890 and viewerCategory == "essential" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 14,
                    spellID = 232323,
                    viewerCategory = "essential",
                }
            end
            if cooldownID == 895 and viewerCategory == "essential" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 20,
                    spellID = 85948,
                    viewerCategory = "essential",
                }
            end
            if cooldownID == 896 and viewerCategory == "essential" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 21,
                    spellID = 85948,
                    overrideSpellID = 458128,
                    viewerCategory = "essential",
                }
            end
            if cooldownID == 1769 and viewerCategory == "essential" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 22,
                    spellID = 357210,
                    overrideSpellID = 403631,
                    viewerCategory = "essential",
                }
            end
            if cooldownID == 891 and viewerCategory == "buff" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 15,
                    spellID = 70766,
                    viewerCategory = "buff",
                    selfAura = true,
                    hasAura = true,
                    auraInstanceID = 809,
                    auraUnit = "player",
                    auraData = auraMirrorData,
                    auraDurObj = auraMirrorDuration,
                    auraDurObjSource = "aura-duration",
                }
            end
            if cooldownID == 892 and viewerCategory == "buff" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 16,
                    spellID = 70767,
                    viewerCategory = "buff",
                    selfAura = false,
                    hasAura = true,
                    auraDurObj = auraMirrorDuration,
                    auraDurObjSource = "aura-duration",
                }
            end
            if cooldownID == 893 and viewerCategory == "buff" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 17,
                    spellID = 70768,
                    viewerCategory = "buff",
                    selfAura = false,
                    hasAura = true,
                    auraInstanceID = 811,
                    auraUnit = "target",
                    auraDurObj = auraMirrorDuration,
                    auraDurObjSource = "aura-duration",
                }
            end
            if cooldownID == 894 and viewerCategory == "buff" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 18,
                    spellID = 70769,
                    viewerCategory = "buff",
                    selfAura = false,
                    hasAura = true,
                    auraInstanceID = 810,
                    auraUnit = "target",
                    auraDurObj = auraMirrorDuration,
                    auraDurObjSource = "aura-duration",
                }
            end
            if cooldownID == 51696 and viewerCategory == "essential" then
                return {
                    cooldownID = cooldownID,
                    mirrorEpoch = 184,
                    spellID = 439843,
                    overrideSpellID = 439843,
                    overrideTooltipSpellID = 434765,
                    viewerCategory = "essential",
                    selfAura = false,
                    hasAura = true,
                    auraInstanceID = 862,
                    auraUnit = "target",
                    auraDurObj = auraMirrorDuration,
                    auraDurObjSource = "aura-related-child",
                    auraStackText = "7",
                    auraStackTextSource = "Applications",
                    auraStackTextShown = true,
                }
            end
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

-- isOnGCD is now read directly off cdInfo (NeverSecret) by the resolver, so
-- the per-spell GCD state is injected onto the mocked cooldown-info table the
-- source returns (see gcdOverrides handling in QuerySpellCooldown above)
-- instead of priming a trusted-GCD snapshot. setGCDState(nil) clears the
-- overrides, leaving each spell's own hardcoded isOnGCD authoritative.
local function setGCDState(values)
    for k in pairs(gcdOverrides) do
        gcdOverrides[k] = nil
    end
    for spellID, value in pairs(values or {}) do
        gcdOverrides[spellID] = value
    end
end

local function ReadMemCounter(name)
    for _, probe in ipairs(ns._memprobes or {}) do
        if probe.name == name then
            return probe.fn()
        end
    end
    return 0
end

setGCDState({
    [12345] = true,
    [22222] = true,
    [54321] = true,
})

local function ResolveIconFields(icon)
    local entry = icon and icon._spellEntry
    local context = ns.CDMResolvers.BuildCooldownStateContext(icon, entry, icon and icon._runtimeSpellID, {
        containerKey = entry and entry.viewerType,
        totemSlot = icon and icon._totemSlot,
        useBuffSwipe = false,
        skipAuraPhase = false,
        showGCDSwipe = true,
        lastChargeMirrorCooldownID = icon and icon._lastChargeMirrorCooldownID,
        lastChargeMirrorCategory = icon and icon._lastChargeMirrorCategory,
        lastChargeRuntimeSpellID = icon and icon._lastChargeRuntimeSpellID,
    })
    context.mirrorCooldownID = icon and icon._blizzMirrorCooldownID
    context.mirrorCategory = icon and icon._blizzMirrorCategory
    local state = ns.CDMResolvers.ResolveCooldownState(context)
    return state.durObj,
        state.mode,
        state.sourceID,
        state.start,
        state.duration,
        state.spellID,
        state.mirrorBacked == true,
        state.mirrorBacked == true and state or nil
end

local icon = {
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        viewerType = "essential",
        type = "spell",
    },
}

local durObj, mode, sourceID = ResolveIconFields(icon)

assert(durObj == gcdDuration, "trusted GCD state should resolve when no active mirror duration exists")
assert(mode == "gcd-only", "trusted GCD state should resolve as gcd-only")
assert(sourceID == 12345, "GCD-only source should be the runtime spellID")

setGCDState(nil)

local liveCooldownGCDIcon = {
    _spellEntry = {
        id = 33333,
        spellID = 33333,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(liveCooldownGCDIcon)

-- isOnGCD is read directly off cdInfo (NeverSecret). Spell 33333's cdInfo is
-- { isActive=true, isOnGCD=true } with no real cooldown, so the resolver binds
-- the GCD DurationObject and classifies gcd-only purely from the live read.
assert(durObj == gcdDuration, "live isOnGCD should render the GCD DurationObject via the direct read")
assert(mode == "gcd-only", "live isOnGCD=true should resolve as gcd-only")
assert(sourceID == 33333, "GCD-only source should be the runtime spellID")

local mirroredGCDIcon = {
    _spellEntry = {
        id = 55555,
        spellID = 55555,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(mirroredGCDIcon)

assert(durObj == mirrorDuration, "GCD mirror duration should be reused when spell-specific GCD duration is missing")
assert(mode == "gcd-only", "GCD mirror duration should resolve as gcd-only")
assert(sourceID == 55555, "GCD mirror source should use the runtime spellID for stable binding")
-- After mirror→resolver refactor, the resolver always queries live cdInfo
-- to classify mode. The "bypass live state" optimization no longer applies.

local misleadingMirroredCooldownIcon = {
    _spellEntry = {
        id = 11111,
        spellID = 11111,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(misleadingMirroredCooldownIcon)

-- After refactor: cdInfo.isOnGCD=true → mode "gcd-only", durObj from
-- QueryGCDDuration. The mock returns nil for spellID 11111 → durObj nil.
assert(mode == "gcd-only", "live isOnGCD should classify as gcd-only, got " .. tostring(mode))

local cooldownFrameMirroredGCDIcon = {
    _spellEntry = {
        id = 161616,
        spellID = 161616,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(cooldownFrameMirroredGCDIcon)

-- After mirror→resolver refactor: durObj comes from live API
-- (Sources.QuerySpellCooldownDuration). realCooldownDuration is what the
-- live mock returns for spell 161616 with ignoreGCD=true.
assert(durObj == realCooldownDuration, "cooldown mode should resolve durObj from live API, got " .. tostring(durObj))
assert(mode == "cooldown", "cooldown-frame mirror should resolve as cooldown when isOnGCD=false")

local cooldownFrameMirroredGCDWithoutExplicitDurationIcon = {
    _spellEntry = {
        id = 171717,
        spellID = 171717,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(cooldownFrameMirroredGCDWithoutExplicitDurationIcon)

assert(durObj == realCooldownDuration, "cooldown mode should resolve durObj from live API, got " .. tostring(durObj))
assert(mode == "cooldown", "cooldown-frame mirror should resolve as cooldown when isOnGCD=false")

setGCDState({
    [242424] = true,
    [252525] = false,
    [85948] = true,
})

local shortGCDMirrorCooldownIcon = {
    _spellEntry = {
        id = 242424,
        spellID = 242424,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(shortGCDMirrorCooldownIcon)

assert(durObj == gcdDuration, "mirror cooldown with clean short GCD cdInfo should select the live GCD duration")
assert(mode == "gcd-only", "mirror cooldown with clean short GCD cdInfo should resolve as gcd-only")
assert(sourceID == 242424, "mirror cooldown GCD override should use the live spellID source")

local staleNonGCDMirrorIcon = {
    _spellEntry = {
        id = 252525,
        spellID = 252525,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(staleNonGCDMirrorIcon)

-- After refactor: live cdInfo says isActive=true,isOnGCD=false → "cooldown".
-- durObj comes from QuerySpellCooldownDuration(spellID, true).
assert(mode == "cooldown", "live cdInfo says cooldown, got " .. tostring(mode))
assert(durObj == realCooldownDuration, "cooldown durObj should be the live API value, got " .. tostring(durObj))

local overrideRuntimeMirrorCooldownIcon = {
    _runtimeSpellID = 458128,
    _blizzMirrorCooldownID = 895,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        id = 85948,
        spellID = 85948,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(overrideRuntimeMirrorCooldownIcon)

assert(durObj == gcdDuration, "mirror cooldown activity should query the mirror spell, not a transient runtime override")
assert(mode == "gcd-only", "usable base spell during GCD should not inherit stale mirror cooldown desaturation")
assert(sourceID == 85948, "runtime override mismatch should resolve GCD against the mirror/base spellID")

setGCDState(nil)

local cachedBaseGCDMirrorCooldownIcon = {
    _runtimeSpellID = 458128,
    _blizzMirrorCooldownID = 895,
    _blizzMirrorCategory = "essential",
    _isOnGCD = true,
    _spellEntry = {
        id = 85948,
        spellID = 85948,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(cachedBaseGCDMirrorCooldownIcon)

assert(durObj == gcdDuration, "cached trusted base-spell GCD state should keep the GCD swipe over a stale override cooldown")
assert(mode == "gcd-only", "icon-local trusted GCD state should resolve stale mirror cooldowns as gcd-only outside the originating event")
assert(sourceID == 85948, "cached base-spell GCD source should use the mirror/base spellID")

local iconFactIsLiveSourceIcon = {
    _runtimeSpellID = 458128,
    _blizzMirrorCooldownID = 896,
    _blizzMirrorCategory = "essential",
    _isOnGCD = false,
    _spellEntry = {
        id = 85948,
        spellID = 85948,
        viewerType = "essential",
        type = "spell",
    },
}
local iconFactContext = ns.CDMResolvers.BuildCooldownStateContext(
    iconFactIsLiveSourceIcon,
    iconFactIsLiveSourceIcon._spellEntry,
    iconFactIsLiveSourceIcon._runtimeSpellID,
    {
        containerKey = "essential",
        useBuffSwipe = false,
        skipAuraPhase = false,
        showGCDSwipe = true,
    })
iconFactContext.mirrorCooldownID = iconFactIsLiveSourceIcon._blizzMirrorCooldownID
iconFactContext.mirrorCategory = iconFactIsLiveSourceIcon._blizzMirrorCategory
-- This mirror's real cooldown lives on the override spellID 458128
-- (isActive=true, isOnGCD=false) while the base 85948 is on the GCD. A real
-- (non-GCD) cooldown on the override outranks the base's GCD — even a trusted
-- icon-owned base GCD fact (_isOnGCD=true below) must not erase it. This is the
-- talent-override case (Augmentation Breath of Eons); demoting to gcd-only here
-- erased the real-cooldown swipe on every incidental GCD during the cooldown.
-- The icon-owned GCD fact still drives gcd-only for base-only spells with no
-- competing override cooldown — see cachedBaseGCDMirrorCooldownIcon above
-- (cooldownID 895, no overrideSpellID).
iconFactIsLiveSourceIcon._isOnGCD = true

local iconFactState = ns.CDMResolvers.ResolveCooldownState(iconFactContext)

assert(iconFactState.durObj == realCooldownDuration,
    "override real cooldown should bind even while the base spell is on the GCD")
assert(iconFactState.mode == "cooldown",
    "override real cooldown outranks the base-spell GCD (talent-override case)")
assert(iconFactState.sourceID == "mirror:896:85948",
    "override-backed cooldown should key on the mirror cooldownID + base spellID")

local untrustedUsableStaleMirrorIcon = {
    _spellEntry = {
        id = 252525,
        spellID = 252525,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(untrustedUsableStaleMirrorIcon)

-- Same as the matching test above: live cdInfo says cooldown → resolver
-- derives cooldown mode with the live durObj.
assert(mode == "cooldown", "live cdInfo says cooldown, got " .. tostring(mode))
assert(durObj == realCooldownDuration, "cooldown durObj should be the live API value, got " .. tostring(durObj))

setGCDState(nil)

setGCDState({
    [77777] = true,
})
gcdSpellFallbackEnabled = true
local gcdSpellFallbackIcon = {
    _spellEntry = {
        id = 77777,
        spellID = 77777,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(gcdSpellFallbackIcon)

assert(durObj == gcdDuration, "GCD spell duration should be used when spell-specific duration is missing")
assert(mode == "gcd-only", "GCD spell fallback should resolve as gcd-only")
assert(sourceID == 77777, "GCD spell fallback source should remain the runtime spellID")
gcdSpellFallbackEnabled = false
setGCDState(nil)

local staleChargeMirrorGCDIcon = {
    _spellEntry = {
        id = 66666,
        spellID = 66666,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(staleChargeMirrorGCDIcon)

-- After refactor: m.charges is not set in this fixture; resolver falls
-- through to cdInfo (isOnGCD=true) → gcd-only mode. Live charge override
-- returns nil (chargeInfo.isActive=false), so durObj stays nil.
assert(mode == "gcd-only", "non-charge mirror during live GCD resolves as gcd-only, got " .. tostring(mode))

local activeChargeMirrorIcon = {
    _spellEntry = {
        id = 66667,
        spellID = 66667,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(activeChargeMirrorIcon)

-- Active charge cycle (chargeInfo.isActive=true) during an incidental GCD
-- (cdInfo.isActive=true, isOnGCD=true). The recharge swipe outranks the GCD:
-- HasActiveChargeRecharge reads the live charge state directly out of combat
-- even though this fixture omits the charges capability flag, so the resolver
-- classifies it as cooldown instead of flickering to gcd-only. (In combat the
-- missing flag would gate HasActiveChargeRecharge off and fall back to the GCD;
-- the Putrefy fixture below carries charges=true to cover the combat path.)
assert(mode == "cooldown", "active charge recharge during a GCD should resolve as cooldown, got " .. tostring(mode))

-- Putrefy reference case (Unholy DK, spellID 1247378, essential mirror
-- cooldownID 27991): a known multi-charge spell recharging a charge while the
-- player is on the GCD from casting other spells (cdInfo.isActive=true,
-- isOnGCD=true). The active charge recharge is the authoritative swipe —
-- Blizzard's CooldownViewer surfaces the recharge, not the incidental GCD — so
-- the mirror resolver must classify this as "cooldown", not flicker to
-- "gcd-only" every global cooldown.
local rechargingChargeDuringGCDIcon = {
    _spellEntry = {
        id = 1247378,
        spellID = 1247378,
        viewerType = "essential",
        type = "spell",
        hasCharges = true,
    },
}

durObj, mode, sourceID = ResolveIconFields(rechargingChargeDuringGCDIcon)

assert(mode == "cooldown",
    "recharging multi-charge spell on the GCD should show the recharge swipe, not gcd-only, got " .. tostring(mode))
assert(durObj == liveChargeDuration,
    "recharging multi-charge spell should bind the charge recharge duration, got " .. tostring(durObj))
assert(sourceID == "mirror:27991:1247378",
    "recharging charge cooldown should key on the mirror cooldownID + base spellID, got " .. tostring(sourceID))

-- Same scenario inside combat lockdown: charges=true keeps
-- HasActiveChargeRecharge's combat gate satisfied so the recharge swipe
-- survives instead of falling back to the GCD.
function InCombatLockdown() return true end
durObj, mode, sourceID = ResolveIconFields(rechargingChargeDuringGCDIcon)
function InCombatLockdown() return false end

assert(mode == "cooldown",
    "recharging multi-charge spell on the GCD should show the recharge swipe in combat, got " .. tostring(mode))

-- Scenario removed by the mode-collapse refactor (Task 4): the live-charge
-- override that used to make an active charge recharge win over a
-- mirror-reported GCD was deleted along with
-- ResolveLiveChargeDurationObject. Under the new contract, charge
-- classification is driven entirely by cdInfo; there is no separate
-- "charge" mode to surface, and mirror state's resolvedMode is no
-- longer overridden by chargeInfo. The companion scenario
-- (activeLiveChargeOverCooldownMirrorIcon, below) continues to verify
-- that a mirror cooldown lane resists live-charge overrides.

local activeLiveChargeOverCooldownMirrorIcon = {
    _spellEntry = {
        id = 1227281,
        spellID = 1227281,
        viewerType = "essential",
        type = "spell",
        hasCharges = true,
    },
}

durObj, mode, sourceID = ResolveIconFields(activeLiveChargeOverCooldownMirrorIcon)

assert(durObj == mirrorDuration, "active live recharge should not override a mirror cooldown duration")
assert(mode == "cooldown", "active mirror cooldown should stay cooldown mode over live charge, got " .. tostring(mode))
-- After mode-collapse, BuildMirrorDurationSourceKey embeds (cooldownID,
-- spellID) for real-cooldown modes instead of the per-event mirrorEpoch
-- (see cdm_resolvers.lua's BuildMirrorDurationSourceKey). The (cooldownID, spellID) pair is
-- stable across routine event ticks, so the swipe binds once and runs
-- to completion.
assert(sourceID == "mirror:8204:1227281", "active mirror cooldown should keep its mirror source key")

local noAuraMirrorIcon = {
    _spellEntry = {
        id = 262626,
        spellID = 262626,
        viewerType = "essential",
        type = "spell",
    },
}
local mirrorAuraSkipsBefore = ReadMemCounter("CDM_resolverMirrorAuraSkips")
durObj, mode, sourceID = ResolveIconFields(noAuraMirrorIcon)

assert(durObj == mirrorDuration, "mirror cooldown with explicit hasAura=false should keep its mirror duration")
assert(mode == "cooldown", "mirror cooldown with explicit hasAura=false should remain cooldown mode")
assert(sourceID == "mirror:784:262626", "mirror cooldown with explicit hasAura=false should keep its mirror source")
assert(ReadMemCounter("CDM_resolverMirrorAuraSkips") == mirrorAuraSkipsBefore + 1,
    "mirror cooldown with explicit hasAura=false should skip aura runtime resolution")

setGCDState({
    [88888] = true,
    [99999] = false,
    [121212] = true,
    [131313] = false,
    [141415] = true,
    [151516] = false,
    [181819] = true,
    [181820] = true,
    [191919] = true,
    [212121] = true,
})

local misleadingLiveCooldownIcon = {
    _spellEntry = {
        id = 88888,
        spellID = 88888,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(misleadingLiveCooldownIcon)

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

durObj, mode, sourceID = ResolveIconFields(realCooldownDuringGCDIcon)

assert(durObj == realCooldownDuration, "real cooldown duration should remain selected during GCD")
assert(mode == "cooldown", "real cooldown duration should remain cooldown mode during GCD")
assert(sourceID == 99999, "real cooldown source should use runtime spellID")

local unknownRealCooldownDuringGCDIcon = {
    _spellEntry = {
        id = 121212,
        spellID = 121212,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(unknownRealCooldownDuringGCDIcon)

assert(durObj == gcdDuration, "unknown real-cooldown proof during live GCD should prefer explicit GCD duration")
assert(mode == "gcd-only", "unknown real-cooldown proof during live GCD should resolve as gcd-only")
assert(sourceID == 121212, "unknown real-cooldown GCD source should use runtime spellID")

local knownRealCooldownDuringLaterGCDIcon = {
    _hasRealCooldownActive = true,
    _showingRealCooldownSwipe = true,
    _spellEntry = {
        id = 131313,
        spellID = 131313,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(knownRealCooldownDuringLaterGCDIcon)

assert(durObj == realCooldownDuration, "trusted non-GCD state should keep the real cooldown duration")
assert(mode == "cooldown", "trusted non-GCD state should keep cooldown mode")
assert(sourceID == 131313, "known real cooldown source should use runtime spellID")

local usableResourceCooldownIcon = {
    _spellEntry = {
        id = 141414,
        spellID = 141414,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(usableResourceCooldownIcon)

-- cdInfo.isActive=true with cdInfo.isOnGCD=false is the trusted NeverSecret
-- signal for "real cooldown active." C_Spell.IsSpellUsable does not factor
-- in cooldowns per Blizzard's docs, so it cannot legitimately clear this
-- classification. The resolver must trust the API.
assert(durObj == realCooldownDuration,
    "active non-GCD cdInfo should bind the real cooldown duration regardless of IsSpellUsable")
assert(mode == "cooldown",
    "active non-GCD cdInfo should resolve cooldown mode regardless of IsSpellUsable")
assert(sourceID == 141414,
    "active non-GCD cooldown should keep its runtime spellID source")

local usableResourceDuringGCDIcon = {
    _hasRealCooldownActive = true,
    _showingRealCooldownSwipe = true,
    _spellEntry = {
        id = 141415,
        spellID = 141415,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(usableResourceDuringGCDIcon)

assert(durObj == gcdDuration, "usable resource spell should render GCD during a later GCD pulse")
assert(mode == "gcd-only", "usable resource spell should not keep stale real-cooldown mode during GCD")
assert(sourceID == 141415, "usable resource GCD source should use runtime spellID")

local resourceBlockedCooldownIcon = {
    _spellEntry = {
        id = 151515,
        spellID = 151515,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(resourceBlockedCooldownIcon)

assert(durObj == realCooldownDuration, "resource-blocked cooldown should bind its real duration")
assert(mode == "cooldown", "resource-blocked cooldown should stay in cooldown mode")
assert(sourceID == 151515, "resource-blocked cooldown should keep its runtime spellID source")

local resourceBlockedDuringGCDIcon = {
    _hasRealCooldownActive = true,
    _showingRealCooldownSwipe = true,
    _spellEntry = {
        id = 151516,
        spellID = 151516,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(resourceBlockedDuringGCDIcon)

assert(durObj == realCooldownDuration, "trusted non-GCD resource-blocked spell should keep its real cooldown duration")
assert(mode == "cooldown", "trusted non-GCD resource-blocked spell should keep real-cooldown mode")
assert(sourceID == 151516, "resource-blocked cooldown source should use runtime spellID")

local resourceBlockedPriorMirrorDuringGCDIcon = {
    _hasRealCooldownActive = true,
    _showingRealCooldownSwipe = true,
    _lastDurObjKey = "cooldown:mirror:27927:2218",
    _lastDurObj = mirrorDuration,
    _spellEntry = {
        id = 212121,
        spellID = 212121,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(resourceBlockedPriorMirrorDuringGCDIcon)

assert(durObj == gcdDuration, "trusted GCD API state should replace a prior mirror binding during a later GCD pulse")
assert(mode == "gcd-only", "trusted GCD API state should keep GCD mode over a prior mirror binding")
assert(sourceID == 212121, "trusted GCD source should use runtime spellID instead of the prior mirror source")

local activeChildMirrorLiveInactiveIcon = {
    _spellEntry = {
        id = 181818,
        spellID = 181818,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(activeChildMirrorLiveInactiveIcon)

assert(durObj == nil, "live isActive=false should clear a stale active child mirror duration")
assert(mode == "inactive", "live isActive=false should resolve the stale mirror as inactive")
assert(sourceID == nil, "stale mirror source should clear when live cooldown state is inactive")

local activeChildMirrorDuringLaterGCDIcon = {
    _spellEntry = {
        id = 181819,
        spellID = 181819,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(activeChildMirrorDuringLaterGCDIcon)

-- After mirror→resolver refactor: live isOnGCD=true wins; mode "gcd-only".
assert(mode == "gcd-only", "live isOnGCD=true classifies as gcd-only, got " .. tostring(mode))
assert(sourceID == 181819, "gcd-only sourceID is the runtime spellID")

local activeChildUsableMirrorDuringGCDIcon = {
    _spellEntry = {
        id = 181820,
        spellID = 181820,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(activeChildUsableMirrorDuringGCDIcon)

assert(durObj == gcdDuration, "trusted GCD API state should replace a usable active child mirror duration")
assert(mode == "gcd-only", "usable active child mirror should resolve as GCD when trusted isOnGCD is true")
assert(sourceID == 181820, "usable active child mirror GCD source should use runtime spellID")

local usableActiveMirrorIcon = {
    _spellEntry = {
        id = 191919,
        spellID = 191919,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(usableActiveMirrorIcon)

assert(durObj == gcdDuration, "trusted GCD API state should win over a usable active mirror cooldown")
assert(mode == "gcd-only", "usable active mirror should resolve as GCD when trusted isOnGCD is true")
assert(sourceID == 191919, "usable active mirror GCD source should use runtime spellID")

local resolvedModeMirrorIcon = {
    _spellEntry = {
        id = 202020,
        spellID = 202020,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(resolvedModeMirrorIcon)

-- After refactor: mode derived from live cdInfo, not mirror's resolvedMode.
-- cdInfo for 202020 is nil → mode "inactive".
assert(mode == "inactive", "no live cdInfo → inactive, got " .. tostring(mode))

local authoritativeGCDMirrorIcon = {
    _spellEntry = {
        id = 181821,
        spellID = 181821,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(authoritativeGCDMirrorIcon)

-- cdInfo for 181821 says { isActive=false, isOnGCD=false } → inactive.
assert(mode == "inactive", "inactive live cdInfo → inactive, got " .. tostring(mode))

local staleInactiveMirrorIcon = {
    _spellEntry = {
        id = 44444,
        spellID = 44444,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(staleInactiveMirrorIcon)

assert(durObj == nil, "resolver should clear active mirror duration when live cooldown is inactive")
assert(mode == "inactive", "active mirror duration should resolve inactive when live cooldown is inactive")
assert(sourceID == nil, "stale mirror source should clear when live cooldown is inactive")

assert(ns.CDMResolvers.GetMirrorPolicyStats == nil,
    "resolver should not expose mirror policy counters after mirror ownership is restored")
assert(ns.CDMResolvers.ShouldUseMirroredCooldownDuration == nil,
    "resolver should not expose mirror policy adjudication after mirror ownership is restored")

setGCDState({
    [12345] = true,
    [22222] = true,
    [54321] = true,
})

local inactiveCooldownGCDIcon = {
    _spellEntry = {
        id = 22222,
        spellID = 22222,
        viewerType = "essential",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(inactiveCooldownGCDIcon)

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

durObj, mode = ResolveIconFields(auraBackedCooldownIcon)

assert(durObj == auraChildFrameDuration, "child-frame aura mirror duration should be selected")
assert(mode == "aura", "child-frame aura mirror source should resolve as aura mode even during GCD")

mirrorSource = "aura-related-child"
durObj, mode = ResolveIconFields(auraBackedCooldownIcon)

assert(durObj == auraChildFrameDuration, "related-child aura mirror duration should be selected")
assert(mode == "aura", "related-child aura mirror source should resolve as aura mode")

local auraMirrorIcon = {
    _blizzMirrorCooldownID = 889,
    _blizzMirrorCategory = "buff",
    _spellEntry = {
        id = 70765,
        spellID = 70765,
        viewerType = "buff",
        kind = "aura",
        type = "spell",
    },
}

local mirrorBacked, mirrorPayload
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(auraMirrorIcon)

assert(durObj == auraMirrorDuration, "valid aura mirror should bypass aura resolver adjudication")
assert(mode == "aura", "valid aura mirror should pass its own mode to render")
assert(sourceID == "mirror:889:13", "valid aura mirror should keep its mirror source key")
assert(mirrorBacked == true, "valid aura mirror should mark the result mirror-backed")
assert(mirrorPayload and mirrorPayload.state and mirrorPayload.state.auraDurObj == auraMirrorDuration,
    "valid aura mirror should pass the mirror payload through to render")
assert(mirrorPayload.auraData == auraMirrorData,
    "valid aura mirror should resolve auraData from the stamped auraInstanceID")
assert(auraDataQueryCount == 1,
    "valid aura mirror should query auraData exactly once for the payload (got " .. tostring(auraDataQueryCount) .. ")")

auraDataQueryCount = 0
function InCombatLockdown() return true end
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(auraMirrorIcon)
function InCombatLockdown() return false end

assert(durObj == auraMirrorDuration, "combat aura mirror should still keep the DurationObject")
assert(mirrorPayload.auraData == auraMirrorData,
    "combat aura mirror should resolve auraData from the stamped auraInstanceID")
assert(auraDataQueryCount == 1,
    "combat aura mirror should query auraData by non-secret auraInstanceID")

auraDataQueryCount = 0
local directAuraDataMirrorIcon = {
    _blizzMirrorCooldownID = 891,
    _blizzMirrorCategory = "buff",
    _spellEntry = {
        id = 70766,
        spellID = 70766,
        viewerType = "buff",
        kind = "aura",
        type = "spell",
    },
}
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(directAuraDataMirrorIcon)

assert(durObj == auraMirrorDuration, "direct child auraData mirror should keep the mirror DurationObject")
assert(mirrorPayload.auraData == auraMirrorData,
    "direct child auraData mirror should pass through the child-sourced auraData")
assert(auraDataQueryCount == 0,
    "direct child auraData mirror should not re-query auraData by auraInstanceID")

auraDataQueryCount = 0
function InCombatLockdown() return true end
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(directAuraDataMirrorIcon)
function InCombatLockdown() return false end

assert(durObj == auraMirrorDuration, "combat direct child auraData mirror should keep the mirror DurationObject")
assert(mirrorPayload.auraData == auraMirrorData,
    "combat direct child auraData mirror should pass through child-sourced auraData")
assert(auraDataQueryCount == 0,
    "combat direct child auraData mirror should not query auraData by auraInstanceID")

local unverifiedTargetAuraMirrorIcon = {
    _blizzMirrorCooldownID = 892,
    _blizzMirrorCategory = "buff",
    _spellEntry = {
        id = 70767,
        spellID = 70767,
        viewerType = "buff",
        kind = "aura",
        type = "spell",
    },
}
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(unverifiedTargetAuraMirrorIcon)

assert(durObj == nil, "target aura mirrors without ownership proof must not expose a DurationObject")
assert(mode == "inactive", "target aura mirrors without ownership proof should resolve inactive")
assert(mirrorBacked == true, "unverified target aura mirrors should remain mirror-backed for clearing")
assert(mirrorPayload and mirrorPayload.active == false,
    "unverified target aura mirror payloads should be inactive")

-- Capture is the sole ownership gatekeeper: AuraInstanceMatchesExpectedOwner
-- (cdm_blizz_mirror.lua:1495) filters target auras through "HARMFUL|PLAYER"
-- before stamping auraInstanceID. The resolver trusts that stamp. This
-- scenario simulates an auraInstanceID that survived capture-side filtering
-- but whose live auraData reports isFromPlayerOrPlayerPet=false — the
-- documented case (post-12.0.5) is a player-cast aura whose ownership
-- fields turn secret in combat and pcall-decode to nil/false. Resolver-side
-- ownership re-checks broke that case for DK Unholy Soul Reaper by demoting
-- to mode=inactive; the new design renders the captured aura.
local trustedStampedTargetAuraMirrorIcon = {
    _blizzMirrorCooldownID = 893,
    _blizzMirrorCategory = "buff",
    _spellEntry = {
        id = 70768,
        spellID = 70768,
        viewerType = "buff",
        kind = "aura",
        type = "spell",
    },
}
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(trustedStampedTargetAuraMirrorIcon)

assert(durObj == auraMirrorDuration,
    "stamped target aura mirrors must render the captured DurationObject; "
    .. "capture is the ownership gatekeeper, resolver trusts the stamp")
assert(mode == "aura",
    "stamped target aura mirrors should resolve as aura mode "
    .. "regardless of how live auraData ownership fields read")
assert(mirrorPayload and mirrorPayload.active == true,
    "stamped target aura mirror payloads should be active")

local ownedTargetAuraMirrorIcon = {
    _blizzMirrorCooldownID = 894,
    _blizzMirrorCategory = "buff",
    _spellEntry = {
        id = 70769,
        spellID = 70769,
        viewerType = "buff",
        kind = "aura",
        type = "spell",
    },
}
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(ownedTargetAuraMirrorIcon)

assert(durObj == auraMirrorDuration, "owned target aura mirrors should keep the mirror DurationObject")
assert(mode == "aura", "owned target aura mirrors should resolve as aura mode")
assert(mirrorPayload and mirrorPayload.auraData == ownedTargetAuraData,
    "owned target aura mirrors should retain the ownership-proving auraData")

local reapersMarkEssentialIcon = {
    _blizzMirrorCooldownID = 51696,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        id = 439843,
        spellID = 439843,
        viewerType = "essential",
        kind = "cooldown",
        type = "spell",
        linkedSpellIDs = { 434765 },
    },
}
durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(reapersMarkEssentialIcon)

assert(durObj == auraMirrorDuration,
    "target aura mirrors with a captured DurationObject should not flicker to the real cooldown")
assert(mode == "aura",
    "target aura mirrors should keep aura mode when the live auraData re-query is restricted")
assert(mirrorPayload and mirrorPayload.countSinkText == "7",
    "target aura mirrors should keep the carried Applications stack while rendering aura mode")

cooldownQueryCounts[232323] = nil
local inactiveMirrorIcon = {
    _blizzMirrorCooldownID = 890,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        id = 232323,
        spellID = 232323,
        viewerType = "essential",
        kind = "cooldown",
        type = "spell",
    },
}

durObj, mode, sourceID, _, _, _, mirrorBacked, mirrorPayload =
    ResolveIconFields(inactiveMirrorIcon)

-- After mirror→resolver refactor: live cdInfo wins. cdInfo for 232323 says
-- isActive=true, isOnGCD=true → mode "gcd-only". The mirror's missing
-- isActive flag no longer overrides live state.
assert(mode == "gcd-only", "live isOnGCD=true classifies as gcd-only, got " .. tostring(mode))
assert(mirrorBacked == true, "mirror-backed flag should still propagate")

local trackedBarEntry = {
    id = 67890,
    spellID = 67890,
    viewerType = "trackedBar",
    type = "spell",
}
local trackedBarIcon = {
    _spellEntry = trackedBarEntry,
}

durObj, mode = ResolveIconFields(trackedBarIcon)

assert(durObj == nil, "trackedBar entries should not resolve a cooldown DurationObject from cooldown APIs")
assert(mode == "inactive", "trackedBar entries should use aura shape, not real-cooldown shape")
assert(cooldownQueryCounts[67890] == nil,
    "trackedBar entries should not query spell cooldown state as real-cooldown entries")

-- Talent-override cooldown (Augmentation Breath of Eons: base Deep Breath
-- 357210 -> override Breath of Eons 403631 carries the real ~2-min cooldown).
-- The base spell has no cooldown of its own, so casting ANY other spell during
-- the real cooldown reports isActive=true, isOnGCD=true on the base. The mirror
-- resolver must not let that incidental GCD erase the override's real-cooldown
-- swipe — it must prefer the override's real (non-GCD) cooldown.
setGCDState(nil)

local talentOverrideRealCooldownDuringIncidentalGCDIcon = {
    _blizzMirrorCooldownID = 1769,
    _blizzMirrorCategory = "essential",
    _spellEntry = {
        id = 357210,
        spellID = 357210,
        viewerType = "essential",
        kind = "cooldown",
        type = "spell",
    },
}

durObj, mode, sourceID = ResolveIconFields(talentOverrideRealCooldownDuringIncidentalGCDIcon)

assert(mode == "cooldown",
    "talent-override real cooldown must survive an incidental base-spell GCD, got " .. tostring(mode))
assert(durObj == realCooldownDuration,
    "talent-override icon should bind the override's real cooldown duration during an incidental GCD, got " .. tostring(durObj))
assert(sourceID == "mirror:1769:357210",
    "talent-override cooldown should key on the mirror cooldownID + base spellID, got " .. tostring(sourceID))

setGCDState(nil)

print("OK: cdm_resolvers_gcd_mirror_test")
