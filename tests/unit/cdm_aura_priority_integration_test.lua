-- tests/unit/cdm_aura_priority_integration_test.lua
-- luacheck: globals InCombatLockdown geterrorhandler CreateFrame
-- Run: lua tests/unit/cdm_aura_priority_integration_test.lua
--
-- Locks the swipe-priority contract end-to-end across the resolver's
-- live-API-driven classification:
--
--     aura entries:     aura > charge > cooldown > gcd-only
--     cooldown entries: aura > charge > cooldown > gcd-only by default,
--                       charge > cooldown > gcd-only when
--                       Show Buff/Debuff Phase on Cooldown Icons is off.
--
-- Mirror state now owns event-driven attribution only (aura instance,
-- totem ownership, registration metadata). Mode and durObj are derived
-- by the resolver at evaluation time from C_Spell.GetSpellCooldown,
-- C_UnitAuras, and registration flags.

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

local auraDur = { token = "aura-dur" }
local chargeDur = { token = "charge-dur" }
local cooldownDur = { token = "cooldown-dur" }
local gcdDur = { token = "gcd-dur" }

local states = {}
local function makeState(cooldownID, category, opts)
    opts = opts or {}
    states[category .. ":" .. cooldownID] = {
        cooldownID = cooldownID,
        viewerCategory = category,
        mirrorEpoch = 1,
        spellID = cooldownID,
        hasAura = opts.hasAura,
        charges = opts.charges,
        selfAura = opts.selfAura,
        auraInstanceID = opts.auraInstanceID,
        hasAuraInstanceID = opts.auraInstanceID and true or false,
        auraUnit = opts.auraUnit,
        auraDurObj = opts.auraDurObj,
        auraDurObjSource = opts.auraDurObj and "aura-duration" or nil,
        totemDurObj = opts.totemDurObj,
        totemDurObjSource = opts.totemDurObj and "totem-duration" or nil,
        childIsActive = opts.childIsActive,
    }
end

-- Scenario A: cooldown entry with active aura + active cooldown
makeState(50001, "essential", {
    hasAura = true,
    auraInstanceID = 1001,
    auraUnit = "player",
    auraDurObj = auraDur,
})
-- Scenario B: cooldown entry with active aura + charge + cooldown
makeState(50002, "essential", {
    hasAura = true,
    charges = true,
    auraInstanceID = 1002,
    auraUnit = "player",
    auraDurObj = auraDur,
})
-- Scenario C: charge + cooldown, no aura
makeState(50003, "essential", {
    charges = true,
})
-- Scenario D: cooldown + (no GCD), no aura
makeState(50004, "essential", {})
-- Scenario E: gcd-only, no aura
makeState(50005, "essential", {})
-- Scenario F: aura-viewer entry with aura
makeState(50006, "buff", {
    hasAura = true,
    auraInstanceID = 1006,
    auraUnit = "player",
    auraDurObj = auraDur,
})
-- Scenario G: utility cooldown entry with aura captured by runtime
makeState(50007, "utility", {
    charges = true,
    hasAura = false,
    childIsActive = true,
})
makeState(50007, "buff", {
    hasAura = true,
    auraInstanceID = 7007,
    auraUnit = "player",
    auraDurObj = auraDur,
})

-- Scenario H: cooldown entry with hook-cached cooldownDurObj. The resolver
-- must prefer the cached durObj over QuerySpellCooldownDuration (which the
-- mock leaves nil to simulate the API lag we're papering over).
local cachedCooldownDur = { token = "cached-cooldown-dur" }
makeState(50008, "essential", {})
states["essential:50008"].cooldownDurObj = cachedCooldownDur
states["essential:50008"].cooldownDurObjSource = "live-cooldown"

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
    },
    CDMSources = {
        QueryMirroredCooldownState = function() return nil end,
        QuerySpellCooldown = function(spellID)
            -- Scenarios A, B: aura up but cooldown is also rolling
            if spellID == 50001 or spellID == 50002 then
                return { isActive = true, isOnGCD = false }
            end
            -- Scenarios C, G: charge spell with charges rolling
            if spellID == 50003 or spellID == 50007 then
                return { isActive = true, isOnGCD = false }
            end
            -- Scenario D: real cooldown rolling
            if spellID == 50004 then
                return { isActive = true, isOnGCD = false }
            end
            -- Scenario E: gcd-only
            if spellID == 50005 then
                return { isActive = true, isOnGCD = true }
            end
            -- Scenario F: aura-viewer entry, cooldown state irrelevant
            if spellID == 50006 then
                return { isActive = false, isOnGCD = false }
            end
            -- Scenario H: real cooldown rolling, isOnGCD=false. The resolver
            -- should bind cachedCooldownDur (from mirror), not call
            -- QuerySpellCooldownDuration.
            if spellID == 50008 then
                return { isActive = true, isOnGCD = false }
            end
            return nil
        end,
        QuerySpellCharges = function(spellID)
            if spellID == 50002 or spellID == 50003 or spellID == 50007 then
                return { isActive = true, maxCharges = 2 }
            end
            return nil
        end,
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            if spellID == 50005 and ignoreGCD == false then
                return gcdDur
            end
            if spellID == 50004 and ignoreGCD == true then
                return cooldownDur
            end
            if (spellID == 50001 or spellID == 50002) and ignoreGCD == true then
                return cooldownDur
            end
            -- After the mode-collapse refactor (Task 1-5), charge spells
            -- with a rolling recharge are classified as mode="cooldown" and
            -- the resolver calls QueryDuration → QuerySpellCooldownDuration
            -- with ignoreGCD=true. WoW's real API returns the recharge
            -- timer here for a charge spell whose regen IS the cooldown,
            -- so mirror that for scenarios C and G.
            if (spellID == 50003 or spellID == 50007) and ignoreGCD == true then
                return chargeDur
            end
            return nil
        end,
        QuerySpellChargeDuration = function(spellID)
            if spellID == 50002 or spellID == 50003 or spellID == 50007 then
                return chargeDur
            end
            return nil
        end,
        QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
            if unit == "player" and (auraInstanceID == 1001 or auraInstanceID == 1002 or auraInstanceID == 1006) then
                return { auraInstanceID = auraInstanceID, isFromPlayerOrPlayerPet = true }
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, category)
            return states[tostring(category) .. ":" .. tostring(cooldownID)]
        end,
        HasChildForCooldownID = function(cooldownID, category)
            return states[tostring(category) .. ":" .. tostring(cooldownID)] ~= nil
        end,
        GetCooldownIDForViewer = function(spellID, viewerType)
            if spellID == 50007 and viewerType == "buff" then
                return 50007
            end
            return nil
        end,
        GetDirectCooldownIDForViewer = function() return nil end,
    },
    CDMAuraRuntime = {
        ResolveState = function(params)
            if params and params.spellID == 50007 then
                return {
                    isActive = true,
                    durObj = auraDur,
                    auraInstanceID = 7007,
                    auraUnit = "player",
                    resolvedAuraSpellID = 50007,
                }
            end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("modules/cdm/cdm_runtime.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("modules/cdm/cdm_runtime.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers not exported")

local function entry(spellID)
    return {
        id = spellID,
        spellID = spellID,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
    }
end

local function resolveState(e, cooldownID, category, spellID)
    return resolvers.ResolveCooldownState({
        entry = e,
        runtimeSpellID = spellID,
        mirrorCooldownID = cooldownID,
        mirrorCategory = category,
        containerKey = category,
        useBuffSwipe = true,
    })
end

-- Scenario A: aura up + cooldown rolling → aura mode by default
local state = resolveState(entry(50001), 50001, "essential", 50001)
assert(state and state.mirrorBacked == true, "scenario A: state should be mirror-backed")
assert(state.mode == "aura",
    "scenario A: cooldown entry with aura up should resolve to aura mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == auraDur,
    "scenario A: cooldown entry with aura up should carry the aura DurationObject")
assert(state.active == true, "scenario A: payload should be active")

-- Scenario B: aura up + charge + cooldown → aura mode by default
state = resolveState(entry(50002), 50002, "essential", 50002)
assert(state and state.mirrorBacked == true, "scenario B: state should be mirror-backed")
assert(state.mode == "aura",
    "scenario B: aura + charge + cooldown should resolve to aura mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == auraDur,
    "scenario B: aura + charge + cooldown should carry the aura DurationObject")

-- Scenario C: charge spell with recharge rolling. After the mode-collapse
-- refactor, the resolver no longer publishes mode=="charge"; a rolling
-- recharge is classified as mode=="cooldown" and the icon renderer is
-- responsible for charge-aware desaturation via its own
-- chargesRemaining query (Task 8).
state = resolveState(entry(50003), 50003, "essential", 50003)
assert(state and state.mirrorBacked == true, "scenario C: state should be mirror-backed")
assert(state.mode == "cooldown",
    "scenario C: charge spell with recharge rolling should resolve to cooldown mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == chargeDur,
    "scenario C: charge spell with recharge rolling should carry the recharge DurationObject")
assert(state.isOnCooldown == true,
    "scenario C: charge spell with recharge rolling should publish isOnCooldown")

-- Scenario D: cooldown, no aura, no charge
state = resolveState(entry(50004), 50004, "essential", 50004)
assert(state and state.mirrorBacked == true, "scenario D: state should be mirror-backed")
assert(state.mode == "cooldown",
    "scenario D: cooldown entry with real CD should resolve to cooldown mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == cooldownDur,
    "scenario D: cooldown entry with real CD should carry the cooldown DurationObject")

-- Scenario E: gcd-only floor
state = resolveState(entry(50005), 50005, "essential", 50005)
assert(state and state.mirrorBacked == true, "scenario E: state should be mirror-backed")
assert(state.mode == "gcd-only",
    "scenario E: cooldown entry with only GCD should resolve to gcd-only mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == gcdDur,
    "scenario E: cooldown entry with only GCD should carry the GCD DurationObject")

-- Scenario F: aura-viewer entry with aura lane
local auraEntry = {
    id = 50006,
    spellID = 50006,
    type = "spell",
    kind = "aura",
    viewerType = "buff",
}
state = resolveState(auraEntry, 50006, "buff", 50006)
assert(state and state.mirrorBacked == true, "scenario F: aura-viewer state should be mirror-backed")
assert(state.mode == "aura",
    "scenario F: aura-viewer entry with aura lane should resolve to aura mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == auraDur,
    "scenario F: aura-viewer entry should carry the aura DurationObject")

-- Scenario G with aura phase enabled: utility entry with runtime aura capture
local utilityEntry = entry(50007)
utilityEntry.viewerType = "utility"
utilityEntry.hasCharges = true
state = resolvers.ResolveCooldownState({
    entry = utilityEntry,
    runtimeSpellID = 50007,
    mirrorCooldownID = 50007,
    mirrorCategory = "utility",
    containerKey = "utility",
    useBuffSwipe = true,
})

assert(state and state.mode == "aura",
    "scenario G: utility cooldown entry should show active aura before recharge when aura phase is enabled (got " .. tostring(state.mode) .. ")")
assert(state.durObj == auraDur,
    "scenario G: utility cooldown entry should carry the captured aura DurationObject first")
assert(state.auraActive == true,
    "scenario G: utility cooldown entry should publish auraActive from runtime capture")

-- Scenario G with aura phase disabled: charge mode wins
state = resolvers.ResolveCooldownState({
    entry = utilityEntry,
    runtimeSpellID = 50007,
    mirrorCooldownID = 50007,
    mirrorCategory = "utility",
    containerKey = "utility",
    useBuffSwipe = false,
    skipAuraPhase = true,
})

-- After the mode-collapse refactor, a rolling recharge is classified as
-- mode=="cooldown" regardless of whether aura phase was taken or skipped.
assert(state and state.mode == "cooldown",
    "scenario G: disabled aura phase should fall back to recharge as cooldown mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == chargeDur,
    "scenario G: disabled aura phase should carry the recharge DurationObject")

-- Option toggle: cooldown icons keep / skip aura phase
local showCooldownIconAuraPhase = true
local function resolveIcon(spellID)
    local e = entry(spellID)
    local resolved = resolvers.ResolveCooldownState({
        entry = e,
        runtimeSpellID = spellID,
        mirrorCooldownID = spellID,
        mirrorCategory = "essential",
        containerKey = "essential",
        useBuffSwipe = showCooldownIconAuraPhase ~= false,
        skipAuraPhase = showCooldownIconAuraPhase == false,
    })
    return resolved.durObj, resolved.mode
end

-- Default-on: cooldown icons keep aura phase
local durObj, mode = resolveIcon(50001)
assert(mode == "aura",
    "default option state should keep cooldown icons on aura phase (got " .. tostring(mode) .. ")")
assert(durObj == auraDur,
    "default option state should keep the aura DurationObject")

-- Disabled: cooldown icons skip aura and use cooldown phase
showCooldownIconAuraPhase = false
durObj, mode = resolveIcon(50001)
assert(mode == "cooldown",
    "disabled cooldown-icon aura phase should resolve aura+cooldown to cooldown mode (got " .. tostring(mode) .. ")")
assert(durObj == cooldownDur,
    "disabled cooldown-icon aura phase should carry the cooldown DurationObject")

durObj, mode = resolveIcon(50002)
-- aura+charge+cooldown with aura phase skipped resolves to the cooldown
-- lane (mode=="cooldown"). For multi-charge spells the resolver now binds
-- the charge-duration DurationObject in preference to the regular
-- cooldown duration, mirroring Blizzard CooldownViewer's
-- CheckCacheCooldownValuesFromCharges precedence. For spells whose
-- recharge IS the cooldown (Death Charge is the reference case) the
-- regular cooldown duration is a zero DurationObject and the charge
-- branch is the only thing that can bind a usable swipe.
assert(mode == "cooldown",
    "disabled cooldown-icon aura phase should resolve aura+charge+cooldown to cooldown mode (got " .. tostring(mode) .. ")")
assert(durObj == chargeDur,
    "disabled cooldown-icon aura phase should carry the charge-duration DurationObject "
    .. "(charges take precedence over the spell cooldown per Blizzard CV)")

-- Scenario H: hook-cached cooldown durObj is preferred over the API.
state = resolveState(entry(50008), 50008, "essential", 50008)
assert(state and state.mirrorBacked == true, "scenario H: state should be mirror-backed")
assert(state.mode == "cooldown",
    "scenario H: real CD with no aura should resolve to cooldown mode (got "
    .. tostring(state.mode) .. ")")
assert(state.durObj == cachedCooldownDur,
    "scenario H: resolver must bind the hook-cached cooldownDurObj instead "
    .. "of polling QuerySpellCooldownDuration (got "
    .. tostring(state.durObj and state.durObj.token or state.durObj) .. ")")

print("OK: cdm_aura_priority_integration_test")
