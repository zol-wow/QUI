-- tests/unit/cdm_resolvers_activity_state_test.lua
-- Run: lua tests/unit/cdm_resolvers_activity_state_test.lua

local function noop() end

local inCombat = false
local secretTrue = { token = "secret-true" }
local secretFalse = { token = "secret-false" }

function issecretvalue(value)
    return value == secretTrue or value == secretFalse
end

function InCombatLockdown() return inCombat end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

C_CurveUtil = {
    EvaluateColorValueFromBoolean = function()
        error("resolver secret booleans must not be decoded through C_CurveUtil in Lua")
    end,
}

local queryCharges = 0
local queryCooldown = 0

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    CDMShared = {
        IsSafeNumeric = function(value)
            return not issecretvalue(value) and type(value) == "number"
        end,
        SafeBoolean = function(value)
            if issecretvalue(value) then return nil end
            if type(value) == "boolean" then return value end
            return nil
        end,
    },
    CDMSources = {
        QuerySpellCharges = function(spellID)
            queryCharges = queryCharges + 1
            if spellID == 70001 or spellID == 70002 then
                return { maxCharges = 2, isActive = true }
            elseif spellID == 70003 or spellID == 70004 then
                return { maxCharges = 2, isActive = secretTrue }
            end
            return nil
        end,
        QuerySpellCooldown = function(spellID)
            queryCooldown = queryCooldown + 1
            if spellID == 70001 then
                return { isActive = false, isOnGCD = nil }
            elseif spellID == 70002 then
                return { isActive = true, isOnGCD = false }
            elseif spellID == 70003 then
                return { isActive = secretFalse, isOnGCD = false }
            elseif spellID == 70004 then
                return { isActive = secretTrue, isOnGCD = false }
            end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_runtime_store.lua", "cdm_runtime_store.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_runtime_queries.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("QUI_CDM/cdm/cdm_resolvers.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers should be exported")
local store = assert(ns.CDMRuntimeStore, "CDMRuntimeStore should be exported")

local function chargeEntry(spellID)
    return {
        type = "spell",
        kind = "cooldown",
        id = spellID,
        spellID = spellID,
        viewerType = "essential",
        hasCharges = true,
    }
end

local explicitIcon = { _spellEntry = chargeEntry(70001) }
local durObj = { token = "charge" }
store.SetIconState(explicitIcon, {
    mode = "charge",
    active = false,
    durObj = durObj,
    isOnCooldown = false,
    rechargeActive = true,
    hasCharges = true,
    hasChargesRemaining = true,
})

local state = resolvers.ResolveCooldownActivityState(explicitIcon, explicitIcon._spellEntry)
assert(state.hasCharges == true, "stored activity should keep hasCharges")
assert(state.rechargeActive == true, "stored activity should keep rechargeActive")
assert(state.hasChargesRemaining == true, "stored activity should keep hasChargesRemaining")
assert(state.isOnCooldown == false, "stored activity should keep isOnCooldown separate from recharge")
assert(queryCharges == 0, "explicit stored activity facts should avoid charge queries")
assert(queryCooldown == 0, "explicit stored activity facts should avoid cooldown queries")

local legacyIcon = { _spellEntry = chargeEntry(70001) }
store.SetIconState(legacyIcon, {
    mode = "charge",
    active = false,
    durObj = durObj,
})

state = resolvers.ResolveCooldownActivityState(legacyIcon, legacyIcon._spellEntry)
assert(state.hasCharges == true, "legacy stored charge mode should imply hasCharges")
assert(state.rechargeActive == false, "legacy inactive charge should not treat DurationObject alone as rechargeActive")
assert(state.hasChargesRemaining == false, "legacy inactive charge should not imply remaining-charge visibility from DurationObject alone")
assert(state.isOnCooldown == false, "legacy inactive charge should not imply locked cooldown")

state = resolvers.ResolveCooldownActivityStateFromResolvedState(chargeEntry(70001), {
    mode = "charge",
    active = false,
    durObj = durObj,
    hasCharges = true,
})
assert(state.hasCharges == true, "resolved inactive charge mode should keep hasCharges")
assert(state.rechargeActive == false, "resolved inactive charge should not treat DurationObject alone as rechargeActive")
assert(state.hasChargesRemaining == false, "resolved inactive charge should not imply remaining-charge visibility from DurationObject alone")
assert(state.isOnCooldown == false, "resolved inactive charge should not imply locked cooldown")

store.ClearAll()
resolvers.ResolveCooldownState = nil

local rechargeIcon = {
    _spellEntry = chargeEntry(70001),
    _runtimeSpellID = 70001,
}
state = resolvers.ResolveCooldownActivityState(rechargeIcon, rechargeIcon._spellEntry)
assert(state.hasCharges == true, "fallback should detect charged spells")
assert(state.rechargeActive == true, "fallback should detect active recharge")
assert(state.hasChargesRemaining == true, "inactive spell cooldown means a charge remains")
assert(state.isOnCooldown == false, "inactive spell cooldown should not lock the icon")

local depletedIcon = {
    _spellEntry = chargeEntry(70002),
    _runtimeSpellID = 70002,
}
state = resolvers.ResolveCooldownActivityState(depletedIcon, depletedIcon._spellEntry)
assert(state.hasCharges == true, "fallback should keep charged spell metadata")
assert(state.rechargeActive == true, "active spell cooldown should still be recharge-active")
assert(state.hasChargesRemaining == false, "active spell cooldown means no usable charge remains")
assert(state.isOnCooldown == true, "active spell cooldown should lock the icon")

assert(resolvers.IsCooldownInfoActive({ isActive = secretTrue }) == nil,
    "secret cooldown active boolean should remain unknown in Lua")
assert(resolvers.IsCooldownInfoActive({ isActive = secretFalse }) == nil,
    "secret cooldown inactive boolean should remain unknown in Lua")

inCombat = true

local secretRechargeIcon = {
    _spellEntry = chargeEntry(70003),
    _runtimeSpellID = 70003,
}
state = resolvers.ResolveCooldownActivityState(secretRechargeIcon, secretRechargeIcon._spellEntry)
assert(state.hasCharges == true, "secret fallback should keep charged spell metadata")
assert(state.rechargeActive == false, "secret charge-active boolean should not mark recharge active")
assert(state.hasChargesRemaining == false, "secret inactive cooldown should not infer remaining-charge visibility")
assert(state.isOnCooldown == false, "secret inactive cooldown should not lock the icon without a clean signal")

local secretDepletedIcon = {
    _spellEntry = chargeEntry(70004),
    _runtimeSpellID = 70004,
}
state = resolvers.ResolveCooldownActivityState(secretDepletedIcon, secretDepletedIcon._spellEntry)
assert(state.hasCharges == true, "secret active cooldown should keep charged spell metadata")
assert(state.rechargeActive == false, "secret active cooldown should not infer recharge active")
assert(state.hasChargesRemaining == false, "secret active cooldown should not report remaining charges")
assert(state.isOnCooldown == false, "secret active cooldown should not lock the icon without a clean signal")

inCombat = false

local rendererOnlyIcon = {
    _spellEntry = chargeEntry(80001),
    _runtimeSpellID = 80001,
    _hasCooldownActive = true,
    _hasRealCooldownActive = true,
    _showingRealCooldownSwipe = true,
}
state = resolvers.ResolveCooldownActivityState(rendererOnlyIcon, rendererOnlyIcon._spellEntry)
assert(state.isOnCooldown == false,
    "activity fallback should not classify cooldown state from renderer frame flags")
assert(state.rechargeActive == false,
    "activity fallback should not classify recharge state from renderer frame flags")

print("OK: cdm_resolvers_activity_state_test")
