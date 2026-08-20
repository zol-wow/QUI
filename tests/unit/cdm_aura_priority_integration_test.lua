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
-- Mode and durObj are derived by the resolver at evaluation time from the
-- live APIs: C_Spell.GetSpellCooldown, C_Spell.GetSpellCharges, and the
-- aura runtime (CDMAuraRuntime.ResolveState). The Blizzard-mirror pipeline
-- has been removed, so aura attribution now flows exclusively through the
-- aura runtime.

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

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
    },
    CDMSources = {
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
            if spellID == 50001 and ignoreGCD == true then
                return cooldownDur
            end
            -- After the mode-collapse refactor, charge spells with a rolling
            -- recharge are classified as mode="cooldown" and the resolver calls
            -- QueryDuration → QuerySpellCooldownDuration with ignoreGCD=true.
            -- For spells whose regen IS the cooldown (scenarios C, G, and the
            -- disabled-aura 50002 case) WoW returns the recharge timer here, so
            -- mirror that. Note 50002 is intentionally absent: it is a multi-
            -- charge spell whose regular cooldown duration is a zero/unavailable
            -- DurationObject while a charge is regenerating, so the charge
            -- branch is the only thing that can bind a usable swipe (mirroring
            -- Blizzard CooldownViewer's CheckCacheCooldownValuesFromCharges).
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
    },
    CDMAuraRuntime = {
        -- Live aura attribution: returns the active aura facts for the spells
        -- that have an aura up. The resolver's aura probe is gated on
        -- useBuffSwipe (cooldown entries skip it when aura phase is off), so
        -- this mock can answer unconditionally.
        ResolveState = function(params)
            local spellID = params and params.spellID
            if spellID == 50001 then
                return {
                    isActive = true, durObj = auraDur,
                    auraInstanceID = 1001, auraUnit = "player",
                    resolvedAuraSpellID = 50001,
                }
            end
            if spellID == 50002 then
                return {
                    isActive = true, durObj = auraDur,
                    auraInstanceID = 1002, auraUnit = "player",
                    resolvedAuraSpellID = 50002,
                }
            end
            if spellID == 50006 then
                return {
                    isActive = true, durObj = auraDur,
                    auraInstanceID = 1006, auraUnit = "player",
                    resolvedAuraSpellID = 50006,
                }
            end
            if spellID == 50007 then
                return {
                    isActive = true, durObj = auraDur,
                    auraInstanceID = 7007, auraUnit = "player",
                    resolvedAuraSpellID = 50007,
                }
            end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

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

local function resolveState(e, spellID, category)
    return resolvers.ResolveCooldownState({
        entry = e,
        runtimeSpellID = spellID,
        containerKey = category or e.viewerType,
        useBuffSwipe = true,
        showGCDSwipe = true,
        trustIsOnGCD = true,
    })
end

-- Scenario A: aura up + cooldown rolling → aura mode by default
local state = resolveState(entry(50001), 50001, "essential")
assert(state.mode == "aura",
    "scenario A: cooldown entry with aura up should resolve to aura mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == auraDur,
    "scenario A: cooldown entry with aura up should carry the aura DurationObject")
assert(state.active == true, "scenario A: payload should be active")

-- Scenario B: aura up + charge + cooldown → aura mode by default
state = resolveState(entry(50002), 50002, "essential")
assert(state.mode == "aura",
    "scenario B: aura + charge + cooldown should resolve to aura mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == auraDur,
    "scenario B: aura + charge + cooldown should carry the aura DurationObject")

-- Scenario C: charge spell with recharge rolling. After the mode-collapse
-- refactor, the resolver no longer publishes mode=="charge"; a rolling
-- recharge is classified as mode=="cooldown" and the icon renderer is
-- responsible for charge-aware desaturation via its own
-- chargesRemaining query.
state = resolveState(entry(50003), 50003, "essential")
assert(state.mode == "cooldown",
    "scenario C: charge spell with recharge rolling should resolve to cooldown mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == chargeDur,
    "scenario C: charge spell with recharge rolling should carry the recharge DurationObject")
assert(state.isOnCooldown == true,
    "scenario C: charge spell with recharge rolling should publish isOnCooldown")

-- Scenario D: cooldown, no aura, no charge
state = resolveState(entry(50004), 50004, "essential")
assert(state.mode == "cooldown",
    "scenario D: cooldown entry with real CD should resolve to cooldown mode (got " .. tostring(state.mode) .. ")")
assert(state.durObj == cooldownDur,
    "scenario D: cooldown entry with real CD should carry the cooldown DurationObject")

-- Scenario E: gcd-only floor
state = resolveState(entry(50005), 50005, "essential")
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
state = resolveState(auraEntry, 50006, "buff")
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
    containerKey = "utility",
    useBuffSwipe = true,
    showGCDSwipe = true,
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
    containerKey = "utility",
    useBuffSwipe = false,
    skipAuraPhase = true,
    showGCDSwipe = true,
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
        containerKey = "essential",
        useBuffSwipe = showCooldownIconAuraPhase ~= false,
        skipAuraPhase = showCooldownIconAuraPhase == false,
        showGCDSwipe = true,
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
-- lane (mode=="cooldown"). For multi-charge spells the resolver binds the
-- charge-duration DurationObject in preference to the regular cooldown
-- duration, mirroring Blizzard CooldownViewer's
-- CheckCacheCooldownValuesFromCharges precedence. For spells whose recharge
-- IS the cooldown (Death Charge is the reference case) the regular cooldown
-- duration is a zero DurationObject and the charge branch is the only thing
-- that can bind a usable swipe.
assert(mode == "cooldown",
    "disabled cooldown-icon aura phase should resolve aura+charge+cooldown to cooldown mode (got " .. tostring(mode) .. ")")
assert(durObj == chargeDur,
    "disabled cooldown-icon aura phase should carry the charge-duration DurationObject "
    .. "(charges take precedence over the spell cooldown per Blizzard CV)")

-- Independent skipAuraPhase gate (regression for the reanchor aura-phase
-- override): skipAuraPhase=true must skip the aura phase even when
-- useBuffSwipe is NOT false. Proves the resolver consults skipAuraPhase
-- directly, not only via the useBuffSwipe coupling.
local indep = resolvers.ResolveCooldownState({
    entry = entry(50001),
    runtimeSpellID = 50001,
    containerKey = "essential",
    useBuffSwipe = true,
    skipAuraPhase = true,
    showGCDSwipe = true,
})
assert(indep and indep.mode == "cooldown",
    "skipAuraPhase=true must skip aura phase independent of useBuffSwipe (got "
    .. tostring(indep and indep.mode) .. ")")
assert(indep.durObj == cooldownDur,
    "skipAuraPhase gate must carry the cooldown DurationObject")

print("OK: cdm_aura_priority_integration_test")
