-- tests/unit/cdm_resolvers_cooldown_state_test.lua
-- Run: lua tests/unit/cdm_resolvers_cooldown_state_test.lua
-- luacheck: globals InCombatLockdown geterrorhandler CreateFrame GetTime issecretvalue Enum C_CurveUtil C_DurationUtil GetInventoryItemCooldown

local function noop() end

local inCombat = false
function InCombatLockdown() return inCombat end
function geterrorhandler() return function(err) error(err) end end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        SetScript = noop,
    }
end

local auraDur = { token = "aura-dur" }
local cooldownDur = { token = "cooldown-dur" }
local overrideCooldownDur = { token = "override-cooldown-dur" }
local chargeDur = { token = "charge-dur" }
local gcdDur = { token = "gcd-dur" }
local itemAuraDur = { token = "item-aura-dur" }
local secretItemStart = { token = "secret-item-start" }
local secretItemDuration = { token = "secret-item-duration" }
local secretChargeZero = { token = "secret-current-charges", value = 0 }
local secretChargeOne = { token = "secret-current-charges", value = 1 }
local secretChargeUnknown = { token = "secret-current-charges", value = "unknown" }
local now = 120
local createdDurationObjects = {}
local durationObjectSetCalls = {}

function GetTime() return now end

function issecretvalue(value)
    return value == secretChargeZero
        or value == secretChargeOne
        or value == secretChargeUnknown
        or value == secretItemStart
        or value == secretItemDuration
end

Enum = { LuaCurveType = { Step = "Step" } }
C_CurveUtil = {
    CreateCurve = function()
        return {
            SetType = noop,
            AddPoint = noop,
            Evaluate = function(_, value)
                if value == secretChargeZero then return 1 end
                if value == secretChargeOne then return 0 end
                error("unexpected curve input")
            end,
        }
    end,
}

C_DurationUtil = {
    CreateDuration = function()
        local durObj = { token = "created-duration-" .. tostring(#createdDurationObjects + 1) }
        function durObj:SetTimeFromStart(startTime, duration)
            table.insert(durationObjectSetCalls, {
                object = self,
                start = startTime,
                duration = duration,
            })
        end
        table.insert(createdDurationObjects, durObj)
        return durObj
    end,
}

local states = {}
local mirrorStateLookups = 0
local itemAuraActive = true
local itemCooldownActive = false
local itemAuraDurationObjectAvailable = true
local itemRuntimeAuraInstanceActive = false
local itemRuntimeAuraDataAvailable = false
local itemRuntimeAuraDataExpiration = 165
local itemRuntimeAuraDataDuration = 45
local itemAuraScannedDuration = 30
local itemAuraScannedExpiration = 140
local directAuraQueriesAvailable = true
local capturedCooldownAuraActive = false
local itemSlotCooldownActive = false
local slotCooldownEnabled = true
local slotCooldownStart = 11418.804
local slotCooldownDuration = 90
local itemUseSpellCooldownActive = false
local itemUseSpellCooldownDur = { token = "item-use-spell-cooldown-dur" }
local chargeQueryCounts = {}

local function putState(cooldownID, category, state)
    state.cooldownID = cooldownID
    state.viewerCategory = category
    states[category .. ":" .. cooldownID] = state
end

putState(50001, "essential", {
    mirrorEpoch = 1,
    spellID = 50001,
    overrideSpellID = 50001,
    auraInstanceID = 9001,
    auraUnit = "player",
    hasAura = true,
    selfAura = true,
    stackText = "3",
    stackTextSource = "Applications",
    stackTextShown = true,
    auraDurObj = auraDur,
    auraDurObjSource = "aura-duration",
})

putState(50002, "essential", {
    mirrorEpoch = 2,
    spellID = 50002,
    overrideSpellID = 50002,
})

putState(50003, "essential", {
    mirrorEpoch = 3,
    spellID = 50003,
    overrideSpellID = 50003,
})

putState(50004, "essential", {
    mirrorEpoch = 4,
    spellID = 50004,
    overrideSpellID = 50004,
    charges = true,
    stackText = "1",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
})

putState(50005, "essential", {
    mirrorEpoch = 5,
    spellID = 50005,
    overrideSpellID = 50005,
    charges = true,
    stackText = "0",
    stackTextSource = "ChargeCount",
    stackTextShown = true,
})

putState(50006, "essential", {
    mirrorEpoch = 6,
    spellID = 50006,
    overrideSpellID = 50006,
})

putState(50007, "essential", {
    mirrorEpoch = 7,
    spellID = 50007,
    overrideSpellID = 50007,
    charges = true,
    cooldownChargesCount = "2",
    cooldownChargesShown = true,
})

putState(50008, "essential", {
    mirrorEpoch = 8,
    spellID = 50008,
    overrideSpellID = 50008,
})

putState(50009, "essential", {
    mirrorEpoch = 9,
    spellID = 50009,
    overrideSpellID = 50009,
    charges = true,
})

putState(50010, "essential", {
    mirrorEpoch = 10,
    spellID = 50010,
    overrideSpellID = 50010,
    charges = true,
})

putState(50011, "essential", {
    mirrorEpoch = 11,
    spellID = 50011,
    overrideSpellID = 50011,
    charges = true,
})

putState(50012, "essential", {
    mirrorEpoch = 12,
    spellID = 50012,
    overrideSpellID = 50012,
    charges = true,
})

putState(50013, "essential", {
    mirrorEpoch = 13,
    spellID = 50013,
    overrideSpellID = 50013,
    charges = true,
})

-- 50014: DK Death Charge reference case. cdInfo.isActive=false (the spell
-- is castable from a remaining charge) but chargeInfo.isActive=true with a
-- rolling recharge — the recharge timing lives only on
-- C_Spell.GetSpellChargeDuration.
putState(50014, "essential", {
    mirrorEpoch = 14,
    spellID = 50014,
    overrideSpellID = 50014,
    charges = true,
})

-- 2700: Talent-override reference case (Guardian Druid Berserk slot replaced by
-- Incarnation: Guardian of Ursoc). The Blizzard EssentialCooldownViewer
-- registers the slot under the base spellID (50334 Berserk) but the live
-- cooldown lives on the override spellID (102558 Incarnation). After the buff
-- expires the aura phase ends, m.auraInstanceID clears, and DeriveMirrorPayloadMode
-- must probe the override to surface mode="cooldown" — probing only the base
-- returns isActive=false and the icon falls through to "inactive".
putState(2700, "essential", {
    mirrorEpoch = 99,
    spellID = 50334,
    overrideSpellID = 102558,
    linkedSpellIDs = { 50334, 102558 },
})

putState(55090, "essential", {
    mirrorEpoch = 101,
    spellID = 55090,
    overrideSpellID = 55090,
    hasAura = false,
    childIsActive = true,
    wasSetFromAura = false,
    wasSetFromCooldown = true,
    wasSetFromCharges = false,
    cooldownDurObj = cooldownDur,
    cooldownDurObjSource = "live-cooldown",
})

local auraRuntimeProbeCount = 0

local ns = {
    Helpers = {},
    CDMShared = {
        IsSafeNumeric = function(value)
            return type(value) == "number" or issecretvalue(value)
        end,
    },
    CDMSources = {
        QuerySpellCharges = function(spellID)
            chargeQueryCounts[spellID] = (chargeQueryCounts[spellID] or 0) + 1
            if spellID == 50004 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = true }
            end
            if spellID == 50005 then
                return { currentCharges = secretChargeZero, maxCharges = 2, isActive = true }
            end
            if spellID == 50007 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = true }
            end
            if spellID == 50009 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = true }
            end
            if spellID == 50010 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = false }
            end
            if spellID == 50011 then
                return { currentCharges = secretChargeZero, maxCharges = 1, isActive = false }
            end
            if spellID == 50012 then
                return { currentCharges = secretChargeOne, maxCharges = 1, isActive = false }
            end
            if spellID == 50013 then
                return { currentCharges = secretChargeUnknown, maxCharges = 2, isActive = true }
            end
            if spellID == 60001 then
                return { maxCharges = 2, isActive = true }
            end
            if spellID == 60002 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = true }
            end
            if spellID == 60003 then
                return { currentCharges = secretChargeZero, maxCharges = 2, isActive = true }
            end
            if spellID == 60004 then
                return { currentCharges = secretChargeZero, maxCharges = 2, isActive = true }
            end
            if spellID == 60005 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = true }
            end
            if spellID == 60006 then
                return { currentCharges = secretChargeUnknown, maxCharges = 2, isActive = true }
            end
            -- 50014 / 60010: cdInfo.isActive=false but chargeInfo.isActive=true.
            -- The recharge timing lives on QuerySpellChargeDuration here; the
            -- regular QuerySpellCooldownDuration intentionally returns nil so
            -- the fix's charge-lane probe is the only thing that can bind a
            -- DurationObject.
            if spellID == 50014 or spellID == 60010 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = true }
            end
            -- 60011: a multi-charge spell with a charge available and a recharge
            -- rolling, while an incidental GCD sits on the cooldown lane.
            if spellID == 60011 then
                return { currentCharges = secretChargeOne, maxCharges = 2, isActive = true }
            end
            return nil
        end,
        QuerySpellCooldown = function(spellID)
            if spellID == 50001 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 50002 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 50003 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 55090 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 50004 or spellID == 50005 or spellID == 50007 or spellID == 50009 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 50006 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 50008 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 50010 then
                return { isActive = false, isOnGCD = false }
            end
            if spellID == 50011 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 50012 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 50013 then
                return { isActive = true, isOnGCD = false }
            end
            -- After mode-collapse, the resolver only classifies a charge
            -- spell as "cooldown" when cdInfo.isActive=true (chargeInfo.isActive
            -- alone is no longer enough — see Task 4). Tests that previously
            -- relied on the live-charge override now need cdInfo.isActive=true
            -- for the recharge phase to surface.
            if spellID == 60001 or spellID == 60002 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 60003 or spellID == 60004 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 60005 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 60006 then
                return { isActive = true, isOnGCD = false }
            end
            -- 60011: charge recharge rolling while an incidental GCD sits on the
            -- cooldown lane (isActive=true, isOnGCD=true). The recharge must win.
            if spellID == 60011 then
                return { isActive = true, isOnGCD = true }
            end
            -- 50014 / 60010: the Death Charge case — cooldown lane reports
            -- inactive while a charge recharge is rolling on the charges API.
            if spellID == 50014 or spellID == 60010 then
                return { isActive = false, isOnGCD = false }
            end
            -- 50334 / 102558: talent-override case. C_Spell.GetSpellCooldown
            -- reports isActive=true only on the spellID the cooldown was
            -- directly initiated on (the override), not the registered base.
            if spellID == 50334 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 102558 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 70001 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 91004 and itemUseSpellCooldownActive then
                return { isActive = true, isOnGCD = false }
            end
            return nil
        end,
        QuerySpellCooldownDuration = function(spellID, ignoreGCD)
            if spellID == 70001 and ignoreGCD == false then
                return gcdDur
            end
            -- 60011: a GCD duration is available (a GCD swipe would otherwise be
            -- drawn) so the test proves the active recharge wins over it.
            if spellID == 60011 and ignoreGCD == false then
                return gcdDur
            end
            if spellID == 91004 and itemUseSpellCooldownActive then
                return itemUseSpellCooldownDur
            end
            -- After the mode-collapse refactor: charge spells with a
            -- rolling recharge are classified as mode=="cooldown" and
            -- the resolver calls QueryDuration → QuerySpellCooldownDuration
            -- with ignoreGCD=true. WoW's real API returns the recharge
            -- timer here, so mirror that for the test's charge spells.
            if ignoreGCD == true then
                if spellID == 50001 or spellID == 50002 or spellID == 50008 then
                    return cooldownDur
                end
                if spellID == 50004 or spellID == 50005 or spellID == 50007
                    or spellID == 50009 or spellID == 50010 or spellID == 50011
                    or spellID == 50012 or spellID == 50013 then
                    return chargeDur
                end
                if spellID == 60001 or spellID == 60002 or spellID == 60003
                    or spellID == 60004 or spellID == 60005 or spellID == 60006 then
                    return chargeDur
                end
                -- Talent-override case: both spellIDs return a DurationObject
                -- but they carry different timing. C_Spell.GetSpellCooldownDuration
                -- on the registered base (50334) returns a DurObj whose
                -- visible timing reflects the spell's view of "no active cd"
                -- (because isActive=false on the base for talent-overridden
                -- cooldowns). The override (102558) carries the live timing.
                -- The fix must bind the override's DurObj when the cooldown
                -- was detected on the override; binding the base produces a
                -- desaturated icon with no visible swipe.
                if spellID == 50334 then
                    return cooldownDur
                end
                if spellID == 102558 then
                    return overrideCooldownDur
                end
            else
                if spellID == 50003 then
                    return gcdDur
                end
            end
            return nil
        end,
        QuerySpellChargeDuration = function(spellID)
            if spellID == 50004 or spellID == 50005 or spellID == 50007
               or spellID == 50009 or spellID == 50010 or spellID == 50011
               or spellID == 50013 then
                return chargeDur
            end
            if spellID == 60001 or spellID == 60002 or spellID == 60003
               or spellID == 60004 or spellID == 60005 or spellID == 60006
               or spellID == 60011 then
                return chargeDur
            end
            -- 50014 / 60010: the only path that returns a DurationObject for
            -- these spells. QuerySpellCooldownDuration intentionally returns
            -- nil for them so the resolver must consult the charge lane.
            if spellID == 50014 or spellID == 60010 then
                return chargeDur
            end
            return nil
        end,
        QuerySpellUsable = function(spellID)
            if spellID == 60002 then
                return true
            elseif spellID == 60003 then
                return false
            elseif spellID == 60004 then
                return true
            elseif spellID == 60005 then
                return true
            elseif spellID == 60006 then
                return true
            elseif spellID == 50013 then
                return true
            end
            return nil
        end,
        QueryItemSpell = function(itemID)
            if itemID == 90001 then
                return "Use Item Aura", 91001
            end
            if itemID == 90002 then
                return "Secret Item Use", 91002
            end
            if itemID == 90003 then
                return "Clean Item Use", 91003
            end
            if itemID == 90004 then
                return "Slot Item Use", 91004
            end
            return nil, nil
        end,
        QueryInventoryItemID = function(unit, slotID)
            if unit == "player" and slotID == 13 then
                return 90004
            end
            return nil
        end,
        QueryScannedItemAuraInfo = function(itemID, itemSpellID)
            if itemID == 90001 and itemSpellID == 91001 then
                if itemRuntimeAuraInstanceActive then
                    return {
                        active = true,
                        useSpellID = 91001,
                        auraInstanceID = 94001,
                        auraUnit = "player",
                    }
                end
                return {
                    active = itemAuraActive,
                    useSpellID = 91001,
                    buffSpellID = 92001,
                    duration = itemAuraScannedDuration,
                    expiration = itemAuraScannedExpiration,
                    name = "Related Item Aura",
                }
            end
            return nil
        end,
        QueryCooldownAuraBySpellID = function(spellID)
            if spellID == 91001 then
                return 92001
            end
            return nil
        end,
        QueryUnitAuraBySpellID = function(unit, spellID)
            if directAuraQueriesAvailable
               and unit == "player" and spellID == 92001 and itemAuraActive then
                return { auraInstanceID = 93001, spellId = 92001 }
            end
            return nil
        end,
        QueryPlayerAuraBySpellID = function(spellID)
            if directAuraQueriesAvailable and spellID == 92001 and itemAuraActive then
                return { auraInstanceID = 93001, spellId = 92001 }
            end
            return nil
        end,
        QueryAuraDataBySpellID = function(unit, spellID, filter)
            if directAuraQueriesAvailable
               and unit == "player" and spellID == 92001 and itemAuraActive then
                return { auraInstanceID = 93001, spellId = 92001 }
            end
            return nil
        end,
        QueryAuraDuration = function(unit, auraInstanceID)
            if unit == "player"
               and auraInstanceID == 93001
               and itemAuraActive
               and itemAuraDurationObjectAvailable then
                return itemAuraDur
            end
            if unit == "player"
               and auraInstanceID == 94001
               and itemRuntimeAuraInstanceActive
               and itemAuraDurationObjectAvailable then
                return itemAuraDur
            end
            return nil
        end,
        QueryAuraDataByAuraInstanceID = function(unit, auraInstanceID)
            if unit == "player"
               and auraInstanceID == 94001
               and itemRuntimeAuraInstanceActive
               and itemRuntimeAuraDataAvailable then
                return {
                    auraInstanceID = auraInstanceID,
                    expirationTime = itemRuntimeAuraDataExpiration,
                    duration = itemRuntimeAuraDataDuration,
                }
            end
            -- After the mirror→resolver refactor, the resolver derives aura
            -- mode by verifying mirror-stamped auraInstanceID values against
            -- live aura data. Recognize the test's mirror aura instances so
            -- mirror states with auraInstanceID set resolve as aura mode.
            if unit == "player" and auraInstanceID and auraInstanceID >= 9000 and auraInstanceID < 10000 then
                return { auraInstanceID = auraInstanceID, isFromPlayerOrPlayerPet = true }
            end
            return nil
        end,
        QueryItemCooldown = function(itemID)
            if itemID == 90001 and itemCooldownActive then
                return 100, 60, 1
            end
            if itemID == 90002 then
                return secretItemStart, secretItemDuration, true
            end
            if itemID == 90003 then
                return 200, 90, 1
            end
            if itemID == 90004 and itemSlotCooldownActive then
                return 11418.804, 90, true
            end
            return nil, nil, nil
        end,
    },
    CDMSpellData = {
        GetCapturedAuraForLookup = function(spellIDs)
            if not capturedCooldownAuraActive then return nil end
            for _, spellID in ipairs(spellIDs or {}) do
                if spellID == 92001 then
                    return { auraInstanceID = 93001, unit = "player", spellID = 92001 }
                end
            end
            return nil
        end,
    },
    CDMAuraRuntime = {
        ResolveState = function(params)
            if params and params.spellID == 55090 then
                auraRuntimeProbeCount = auraRuntimeProbeCount + 1
                return {
                    isActive = true,
                    auraInstanceID = 550900,
                    auraUnit = "player",
                    durObj = auraDur,
                    resolvedAuraSpellID = 55090,
                    count = {
                        shown = false,
                    },
                }
            end
            return nil
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, category)
            mirrorStateLookups = mirrorStateLookups + 1
            return states[tostring(category) .. ":" .. tostring(cooldownID)]
        end,
        HasChildForCooldownID = function(cooldownID, category)
            return states[tostring(category) .. ":" .. tostring(cooldownID)] ~= nil
        end,
        GetDirectCooldownIDForViewer = function() return nil end,
        GetCooldownIDForViewer = function() return nil end,
    },
}

function GetInventoryItemCooldown(unit, slotID)
    if unit == "player" and slotID == 13 then
        return slotCooldownStart, slotCooldownDuration, slotCooldownEnabled
    end
    return nil, nil, nil
end

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("modules/cdm/cdm_runtime.lua", "cdm_runtime_queries.lua")("QUI", ns)
loadChunk("modules/cdm/cdm_runtime.lua", "cdm_resolvers.lua")("QUI", ns)

local resolvers = assert(ns.CDMResolvers, "CDMResolvers should be exported")
local resolve = assert(resolvers.ResolveCooldownState, "ResolveCooldownState should be exported")

local function storeResolvedRuntimeState(icon, resolvedState)
    icon._cdmRuntimeState = {
        mode = resolvedState.mode,
        sourceID = resolvedState.sourceID,
        start = resolvedState.start,
        duration = resolvedState.duration,
        durObj = resolvedState.durObj,
    }
end

-- isOnGCD is now read directly off cdInfo (NeverSecret) by the resolver, so a
-- spell's GCD state comes from the cdInfo QuerySpellCooldown returns rather than
-- a primed trusted-GCD snapshot. The mocked source for the GCD spell below
-- already reports isOnGCD=true, so this is a no-op kept only to document intent.
local function setGCDState() end

local function cooldownEntry(spellID)
    return {
        type = "spell",
        kind = "cooldown",
        id = spellID,
        spellID = spellID,
        viewerType = "essential",
    }
end

local state = resolve({
    entry = cooldownEntry(50001),
    runtimeSpellID = 50001,
    mirrorCooldownID = 50001,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "aura", "mirror aura lane should resolve as aura")
assert(state.active == true, "mirror aura lane should be active")
assert(state.isActive == true, "isActive alias should match active")
assert(state.isAuraMode == true, "aura lane should publish isAuraMode")
assert(state.isRealCooldownMode == false, "aura lane should not publish real cooldown mode")
assert(state.hasDurationObject == true, "aura lane should report its DurationObject")
assert(state.hasRenderableCooldown == true, "aura lane should report renderable swipe state")
assert(state.auraActive == true, "mirror aura lane should mark the aura active")
assert(state.auraIsActive == true, "auraIsActive alias should match auraActive")
assert(state.durObj == auraDur, "mirror aura lane should carry aura DurationObject")
assert(state.sourceID == "mirror:50001:1", "source should identify mirror cooldown and epoch")
assert(state.mirrorBacked == true, "mirror lane should mark mirrorBacked")
assert(state.mirrorCooldownID == 50001, "mirror cooldown ID should be copied")
assert(state.mirrorCategory == "essential", "mirror category should be copied")
assert(state.auraInstanceID == 9001, "aura instance should be copied")
assert(state.auraUnit == "player", "aura unit should be copied")
assert(state.countSinkText == "3", "mirror count sink text should be copied")
assert(state.countValue == 3, "mirror count numeric value should be copied when readable")
assert(state.countShown == true, "mirror count visibility should be copied")
assert(state.countSource == "Applications", "mirror count source should be copied")
assert(state.countMirrorBacked == true, "mirror count should be marked mirror-backed")

local auraRuntimeProbesBeforeNoAuraCooldown = auraRuntimeProbeCount
state = resolve({
    entry = cooldownEntry(55090),
    runtimeSpellID = 55090,
    mirrorCooldownID = 55090,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "cooldown",
    "hasAura=false active cooldown child without linked or sibling aura should remain cooldown")
assert(state.durObj == cooldownDur,
    "hasAura=false active cooldown child should keep the mirror cooldown duration")
assert(auraRuntimeProbeCount == auraRuntimeProbesBeforeNoAuraCooldown,
    "hasAura=false active cooldown child should not probe same-spell aura runtime without aura metadata")

local lookupsBeforeCachedState = mirrorStateLookups
state = resolve({
    entry = cooldownEntry(50002),
    runtimeSpellID = 50002,
    mirrorCooldownID = 50002,
    mirrorCategory = "essential",
    cachedMirrorState = states["essential:50002"],
    cachedMirrorSourceID = "mirror:50002:cached",
    containerKey = "essential",
    showGCDSwipe = true,
})

assert(state.mode == "cooldown", "cached mirror state should resolve the cooldown lane")
assert(state.durObj == cooldownDur, "cached mirror state should provide the cooldown DurationObject")
-- After the mode-collapse refactor, BuildMirrorRenderPayload deliberately
-- bypasses cachedSourceID for cooldown/item-cooldown modes (per the
-- comment in cdm_runtime.lua:3098-3120) and builds a stable key from
-- (cooldownID, spellID). The cache-hit path is still verified by the
-- mirrorStateLookups counter below.
assert(state.sourceID == "mirror:50002:50002",
    "cached mirror cooldown lane should rebuild its source key from cooldownID and spellID")
assert(mirrorStateLookups == lookupsBeforeCachedState,
    "resolver should not query the global mirror when a matching icon-cached state is provided")

state = resolve({
    entry = cooldownEntry(50001),
    runtimeSpellID = 50001,
    mirrorCooldownID = 50001,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
    skipAuraPhase = true,
})

assert(state.mode == "cooldown", "skip aura phase should select cooldown lane")
assert(state.durObj == cooldownDur, "skip aura phase should carry cooldown DurationObject")
assert(state.mirrorBacked == true, "cooldown phase should preserve mirror backing")
assert(state.auraActive == true, "cooldown phase should preserve active aura facts")
assert(state.isRealCooldownMode == true, "cooldown phase should publish real cooldown mode")
assert(state.hasRenderableCooldown == true, "cooldown phase should report renderable swipe state")

state = resolve({
    entry = cooldownEntry(50003),
    runtimeSpellID = 50003,
    mirrorCooldownID = 50003,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "mirror cooldown should stay in cooldown mode during live GCD")
assert(state.isOnCooldown == true,
    "live isOnGCD must not clear an active mirror-backed cooldown DurationObject")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50004,
        spellID = 50004,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50004,
    mirrorCooldownID = 50004,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

-- After the mode-collapse refactor, charge spells with a rolling
-- recharge are classified as mode=="cooldown"; the icon renderer is
-- responsible for charge-aware saturation via its own chargesRemaining
-- query (Task 8). The hasCharges / hasChargesRemaining / rechargeActive
-- assertions that used to live here have been dropped because those
-- flags are no longer produced by the resolver.
assert(state.mode == "cooldown", "mirror charge spell with recharge rolling should resolve as cooldown")
assert(state.mirrorBacked == true, "mirror charge should preserve mirror backing")
assert(state.durObj == chargeDur, "mirror charge should carry the recharge DurationObject")
assert(state.isOnCooldown == true, "mirror-backed recharge should mark the spell on cooldown")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50005,
        spellID = 50005,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50005,
    mirrorCooldownID = 50005,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "zero-count mirror charge should resolve as cooldown")
assert(state.isOnCooldown == true, "active recharge should mark the spell on cooldown")
assert(state.durObj == chargeDur, "zero-count mirror charge should carry the recharge DurationObject")

state = resolve({
    entry = cooldownEntry(50006),
    runtimeSpellID = 50006,
    mirrorCooldownID = 50006,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "inactive", "clean live isActive=false should still reject a stale mirror cooldown")
assert(state.isOnCooldown == false, "stale mirror rejection should clear cooldown activity")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50007,
        spellID = 50007,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50007,
    mirrorCooldownID = 50007,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "packed mirror charge count should resolve as cooldown")
assert(state.isOnCooldown == true,
    "active mirror-backed recharge should mark the spell on cooldown")
assert(state.durObj == chargeDur,
    "packed mirror charge count should carry the recharge DurationObject")

state = resolve({
    entry = cooldownEntry(50008),
    runtimeSpellID = 50008,
    mirrorCooldownID = 50008,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "inactive", "live isActive=false should reject a stale spell-cooldown mirror")
assert(state.isOnCooldown == false,
    "stale spell-cooldown mirror rejection should clear cooldown activity")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50009,
        spellID = 50009,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50009,
    mirrorCooldownID = 50009,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "hidden mirror charge should resolve as cooldown while recharge is active")
assert(state.durObj == chargeDur, "active recharge should carry the recharge DurationObject")
assert(state.isOnCooldown == true,
    "active mirror-backed recharge should mark the spell on cooldown")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50010,
        spellID = 50010,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50010,
    mirrorCooldownID = 50010,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "inactive", "live charge-active=false should reject a stale hidden charge mirror")
assert(state.isOnCooldown == false, "stale hidden charge mirror should not desaturate")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50011,
        spellID = 50011,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50011,
    mirrorCooldownID = 50011,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown",
    "hidden charge mirror with active cooldown should resolve as cooldown")
assert(state.durObj == chargeDur,
    "hidden charge mirror should bind the recharge DurationObject")
assert(state.isOnCooldown == true,
    "active cooldown info should mark the spell on cooldown")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50012,
        spellID = 50012,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50012,
    mirrorCooldownID = 50012,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

-- After mode-collapse: an active cdInfo with isOnGCD=true classifies as
-- gcd-only (the old charge-mode demotion to inactive when charges remain
-- is gone — that logic was part of ApplyMirrorChargeActivityState).
assert(state.mode == "gcd-only",
    "active cdInfo with isOnGCD=true on a charge spell should resolve as gcd-only")
assert(state.isOnCooldown == false,
    "gcd-only state should not mark the spell on cooldown")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50013,
        spellID = 50013,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50013,
    mirrorCooldownID = 50013,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "opaque-count mirror charge with active recharge should resolve as cooldown")
assert(state.durObj == chargeDur, "opaque-count mirror charge should carry the recharge DurationObject")
assert(state.isOnCooldown == true, "active recharge should mark the spell on cooldown")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60001,
        spellID = 60001,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60001,
    containerKey = "essential",
    useBuffSwipe = false,
})

-- After the mode-collapse refactor, the live (non-mirror) recharge path
-- classifies a rolling recharge as mode=="cooldown" with isOnCooldown=true.
-- The icon renderer (Task 8) runs its own chargesRemaining query to
-- preserve the available/unavailable distinction; the resolver no longer
-- publishes hasCharges / hasChargesRemaining / rechargeActive.
assert(state.mode == "cooldown", "live recharge should resolve as cooldown")
assert(state.active == true, "live recharge should be active")
assert(state.durObj == chargeDur, "live recharge should carry the recharge DurationObject")
assert(state.sourceID == 60001, "non-mirror live cooldown source should be the spellID")
assert(state.mirrorBacked == nil, "live recharge without mirror should not be mirror-backed")
assert(state.isRealCooldownMode == true, "cooldown mode should publish real cooldown mode")
assert(state.hasDurationObject == true, "cooldown mode should report its DurationObject")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60002,
        spellID = 60002,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60002,
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "usable live recharge should resolve as cooldown")
assert(state.durObj == chargeDur, "usable live recharge should carry the recharge DurationObject")
assert(state.isOnCooldown == true,
    "live cdInfo.isActive=true classifies as on-cooldown; icon-side decides charge availability")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60003,
        spellID = 60003,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60003,
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "zero-charge live recharge should resolve as cooldown")
assert(state.isOnCooldown == true,
    "active live recharge should mark the spell on cooldown")
assert(state.durObj == chargeDur, "zero-charge live recharge should carry the recharge DurationObject")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60004,
        spellID = 60004,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60004,
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "active cooldown with a secret charge count should resolve as cooldown")
assert(state.isOnCooldown == true,
    "active cooldown should mark the spell on cooldown")
assert(state.durObj == chargeDur,
    "active cooldown with a secret charge count should carry the recharge DurationObject")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60005,
        spellID = 60005,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60005,
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "active cooldown with one secret charge should resolve as cooldown")
assert(state.isOnCooldown == true,
    "live cdInfo.isActive=true classifies as on-cooldown; icon-side decodes charge availability")
assert(state.durObj == chargeDur,
    "active cooldown with one secret charge should carry the recharge DurationObject")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60006,
        spellID = 60006,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60006,
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown", "opaque-count live recharge should resolve as cooldown")
assert(state.durObj == chargeDur, "opaque-count live recharge should carry the recharge DurationObject")
assert(state.isOnCooldown == true,
    "live cdInfo.isActive=true classifies as on-cooldown; icon-side decodes charge availability")

-- 60011: live (non-mirror) multi-charge spell with a charge available and a
-- recharge rolling, while an incidental GCD sits on the cooldown lane
-- (cdInfo.isActive=true, isOnGCD=true). The active recharge outranks the GCD
-- swipe — same precedence Blizzard's CooldownViewer gives the recharge — so the
-- resolver must classify cooldown and bind the charge duration instead of
-- flickering to gcd-only every global cooldown (Unholy DK Putrefy on the live
-- path; the mirror path is covered in cdm_resolvers_gcd_mirror_test).
state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60011,
        spellID = 60011,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60011,
    containerKey = "essential",
    useBuffSwipe = false,
    showGCDSwipe = true,
})

assert(state.mode == "cooldown",
    "live recharge during a GCD should resolve as cooldown, not gcd-only, got " .. tostring(state.mode))
assert(state.durObj == chargeDur,
    "live recharge during a GCD should bind the charge recharge DurationObject, got " .. tostring(state.durObj))
assert(state.sourceID == 60011,
    "live recharge during a GCD should source the runtime spellID, got " .. tostring(state.sourceID))

-- DK Death Charge reference case: a multi-charge spell whose cooldown lane
-- reports isActive=false (the spell is castable from a remaining charge)
-- while a recharge is rolling on the charges API. The resolver must still
-- classify as mode=cooldown and bind the charge-duration DurationObject so
-- the recharge swipe is drawn. The previous 4-mode contract dropped this
-- and produced mode=inactive — visibly leaving Death Charge's icon with
-- no swipe between the in-use aura ending and the next charge fully
-- regenerating.
state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 50014,
        spellID = 50014,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 50014,
    mirrorCooldownID = 50014,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown",
    "mirror charge with cdInfo.isActive=false but chargeInfo.isActive=true should resolve as cooldown")
assert(state.mirrorBacked == true,
    "Death-Charge-shaped mirror should preserve mirror backing")
assert(state.durObj == chargeDur,
    "Death-Charge-shaped mirror should bind the charge recharge DurationObject")
assert(state.isOnCooldown == true,
    "active charge recharge with cd.isActive=false should still mark the spell on cooldown")

state = resolve({
    entry = {
        type = "spell",
        kind = "cooldown",
        id = 60010,
        spellID = 60010,
        viewerType = "essential",
        hasCharges = true,
    },
    runtimeSpellID = 60010,
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown",
    "live charge with cdInfo.isActive=false but chargeInfo.isActive=true should resolve as cooldown")
assert(state.durObj == chargeDur,
    "non-mirror Death-Charge-shaped recharge should bind the charge-duration DurationObject")
assert(state.isOnCooldown == true,
    "non-mirror active charge recharge should mark the spell on cooldown")
assert(state.mirrorBacked == nil,
    "live charge recharge without a mirror should not be mirror-backed")

-- isOnGCD is read directly off cdInfo (NeverSecret). 70001 reports
-- isActive=true / isOnGCD=true and has no real cooldown, so it must classify
-- gcd-only and bind the GCD DurationObject straight from the live read — no
-- trusted-GCD snapshot priming, no enable/disable toggle.
setGCDState()
state = resolve({
    entry = cooldownEntry(70001),
    runtimeSpellID = 70001,
    containerKey = "essential",
    useBuffSwipe = false,
    showGCDSwipe = true,
})

assert(state.mode == "gcd-only", "GCD-only state should resolve as gcd-only")
assert(state.active == true, "GCD-only state should be active")
assert(state.durObj == gcdDur, "GCD-only state should carry GCD DurationObject")
assert(state.sourceID == 70001, "GCD-only source should identify the spell")
assert(state.gcdOnly == true, "GCD-only state should publish gcdOnly")
assert(state.isGCDOnly == true, "GCD-only state should publish isGCDOnly")
assert(state.isRealCooldownMode == false, "GCD-only state should not publish real cooldown mode")

itemAuraActive = true
itemCooldownActive = false
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90001,
        itemID = 90001,
        name = "Item With Related Aura",
        viewerType = "custom",
    },
    runtimeSpellID = 91001,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "aura", "item entry should use scanned related aura while the buff is active")
assert(state.active == true, "item related aura should mark the cooldown state active")
assert(state.auraResolved == true, "item related aura should publish auraResolved for icon state stamping")
assert(state.auraActive == true, "item related aura should publish auraActive for icon state stamping")
assert(state.auraInstanceID == 93001,
    "item related aura should stamp the aura instance used for its DurationObject")
assert(state.auraUnit == "player",
    "item related aura should stamp the unit used for its DurationObject")
assert(state.durObj == itemAuraDur, "item related aura should carry the aura DurationObject")
assert(state.resolvedAuraSpellID == 92001, "item related aura should publish the buff spell ID")
assert(state.isOnCooldown == false, "item related aura should not be treated as a real cooldown")

inCombat = true
directAuraQueriesAvailable = false
capturedCooldownAuraActive = true
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90001,
        itemID = 90001,
        name = "Item With Captured Mapped Aura",
        viewerType = "custom",
    },
    runtimeSpellID = 91001,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "aura",
    "item entry should use captured player aura mapped from item use spell in combat")
assert(state.durObj == itemAuraDur,
    "captured cooldown-aura mapping should carry the aura DurationObject")
assert(state.auraResolved == true,
    "captured cooldown-aura mapping should publish auraResolved for icon state stamping")
assert(state.auraActive == true,
    "captured cooldown-aura mapping should publish auraActive for icon state stamping")
assert(state.auraUnit == "player", "captured cooldown-aura mapping should keep the player unit")
assert(state.auraInstanceID == 93001,
    "captured cooldown-aura mapping should stamp the captured aura instance")

inCombat = false
directAuraQueriesAvailable = true
capturedCooldownAuraActive = false

itemAuraActive = false
itemRuntimeAuraInstanceActive = true
itemCooldownActive = false
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90001,
        itemID = 90001,
        name = "Item With Runtime Aura Instance",
        viewerType = "custom",
    },
    runtimeSpellID = 91001,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "aura", "item entry should use runtime aura instance captured from UNIT_AURA")
assert(state.durObj == itemAuraDur, "runtime aura instance should carry the aura DurationObject")
assert(state.auraResolved == true, "runtime aura instance should publish auraResolved for icon state stamping")
assert(state.auraActive == true, "runtime aura instance should publish auraActive for icon state stamping")
assert(state.auraInstanceID == 94001, "runtime aura instance should publish auraInstanceID")

itemAuraActive = false
itemRuntimeAuraInstanceActive = true
itemRuntimeAuraDataAvailable = true
itemAuraDurationObjectAvailable = false
itemCooldownActive = true
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90001,
        itemID = 90001,
        name = "Item With Runtime Aura Instance",
        viewerType = "custom",
    },
    runtimeSpellID = 91001,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "aura", "runtime aura instance should fall back to clean AuraData timing")
assert(state.durObj == nil, "clean AuraData fallback should not invent a DurationObject")
assert(state.auraResolved == true, "clean AuraData fallback should publish auraResolved for icon state stamping")
assert(state.auraActive == true, "clean AuraData fallback should publish auraActive for icon state stamping")
assert(state.numericCooldownActive == true, "clean AuraData fallback should publish numeric timing")
assert(state.start == 120 and state.duration == 45,
    "clean AuraData fallback should carry start and duration")
assert(state.isOnCooldown == false,
    "clean AuraData fallback should suppress the underlying item cooldown")

itemAuraActive = true
itemRuntimeAuraInstanceActive = false
itemRuntimeAuraDataAvailable = false
itemAuraDurationObjectAvailable = false
itemCooldownActive = false
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90001,
        itemID = 90001,
        name = "Item With Related Aura",
        viewerType = "custom",
    },
    runtimeSpellID = 91001,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "aura", "item entry should keep aura mode from scanner timing without a DurationObject")
assert(state.durObj == nil, "scanner numeric aura fallback should not invent a DurationObject")
assert(state.auraResolved == true, "scanner numeric aura fallback should publish auraResolved for icon state stamping")
assert(state.auraActive == true, "scanner numeric aura fallback should publish auraActive for icon state stamping")
assert(state.numericCooldownActive == true, "scanner numeric aura fallback should publish clean timing")
assert(state.start == 110 and state.duration == 30, "scanner numeric aura fallback should carry start and duration")

itemAuraActive = true
itemRuntimeAuraInstanceActive = false
itemAuraDurationObjectAvailable = false
itemAuraScannedDuration = nil
itemAuraScannedExpiration = nil
itemCooldownActive = true
createdDurationObjects = {}
durationObjectSetCalls = {}
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90001,
        itemID = 90001,
        name = "Item With Durationless Related Aura",
        viewerType = "custom",
    },
    runtimeSpellID = 91001,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "aura",
    "active durationless item aura should suppress item cooldown fallback")
assert(state.durObj == nil, "durationless item aura should not publish a DurationObject")
assert(state.auraResolved == true, "durationless item aura should publish auraResolved for icon state stamping")
assert(state.auraActive == true, "durationless item aura should publish auraActive for icon state stamping")
assert(state.numericCooldownActive == nil,
    "durationless item aura should not publish numeric cooldown timing")
assert(state.hasRenderableCooldown == false,
    "durationless item aura should not render the underlying item cooldown")
assert(state.isOnCooldown == false,
    "durationless item aura should not be treated as a real cooldown")
assert(state.hideDurationText == true,
    "durationless item aura should hide duration text")
assert(#createdDurationObjects == 0,
    "durationless item aura should not create an item cooldown DurationObject")

itemAuraActive = false
itemAuraDurationObjectAvailable = true
itemAuraScannedDuration = 30
itemAuraScannedExpiration = 140
itemCooldownActive = true
createdDurationObjects = {}
durationObjectSetCalls = {}
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90001,
        itemID = 90001,
        name = "Item With Related Aura",
        viewerType = "custom",
    },
    runtimeSpellID = 91001,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "item-cooldown", "item entry should fall back to its item cooldown after the aura ends")
assert(state.isOnCooldown == true, "item cooldown fallback should publish cooldown activity")
assert(state.durObj == createdDurationObjects[1],
    "item cooldown fallback should use a DurationObject for cooldown frames")
assert(state.numericCooldownActive == true, "clean DurationObject item cooldown should retain numeric timing")
assert(state.start == 100 and state.duration == 60,
    "clean DurationObject item cooldown should carry timing for bar fills")
assert(durationObjectSetCalls[1].start == 100 and durationObjectSetCalls[1].duration == 60,
    "clean item cooldown should seed the DurationObject from raw item timing")

createdDurationObjects = {}
durationObjectSetCalls = {}
itemAuraActive = false
itemRuntimeAuraInstanceActive = false
itemCooldownActive = false
state = resolve({
    entry = {
        type = "item",
        kind = "cooldown",
        id = 90002,
        itemID = 90002,
        name = "Secret Item Cooldown",
        viewerType = "custom",
    },
    runtimeSpellID = 91002,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "item-cooldown", "secret item timing should still resolve as an item cooldown")
assert(state.isOnCooldown == true, "secret item DurationObject should publish cooldown activity")
assert(state.durObj == createdDurationObjects[1],
    "secret item timing should be passed through a DurationObject")
assert(state.numericCooldownActive == nil, "secret item timing must not publish numeric cooldown timing")
assert(state.start == nil and state.duration == nil, "secret item timing must not be exposed as SetCooldown timing")
assert(durationObjectSetCalls[1].start == secretItemStart
    and durationObjectSetCalls[1].duration == secretItemDuration,
    "secret item cooldown values should pass directly into DurationObject setup")

createdDurationObjects = {}
durationObjectSetCalls = {}
local cleanItemEntry = {
    type = "item",
    kind = "cooldown",
    id = 90003,
    itemID = 90003,
    name = "Clean Item Cooldown",
    viewerType = "custom",
}
local cleanItemIcon = {}
state = resolve({
    owner = cleanItemIcon,
    entry = cleanItemEntry,
    runtimeSpellID = 91003,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "item-cooldown", "clean item timing should resolve as an item cooldown")
assert(state.isOnCooldown == true, "clean item DurationObject should publish cooldown activity")
assert(state.durObj == createdDurationObjects[1], "clean item timing should prefer the DurationObject path")
assert(state.numericCooldownActive == true, "clean item timing should remain available to non-frame consumers")
assert(state.start == 200 and state.duration == 90, "clean item timing should be published on the state")
assert(durationObjectSetCalls[1].start == 200 and durationObjectSetCalls[1].duration == 90,
    "clean item cooldown should use raw start and duration for the DurationObject")

storeResolvedRuntimeState(cleanItemIcon, state)
state = resolve({
    owner = cleanItemIcon,
    entry = cleanItemEntry,
    runtimeSpellID = 91003,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.durObj == createdDurationObjects[1],
    "clean item timing should reuse the icon-owned DurationObject while timing is unchanged")
assert(#createdDurationObjects == 1,
    "repeated clean item timing on the same icon should not allocate another DurationObject")

state = resolve({
    owner = {},
    entry = cleanItemEntry,
    runtimeSpellID = 91003,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.durObj ~= createdDurationObjects[1],
    "a second icon should not reuse another icon's item DurationObject")
assert(#createdDurationObjects == 2,
    "clean item DurationObject reuse should not be keyed by the shared cooldown entry")

createdDurationObjects = {}
durationObjectSetCalls = {}
itemUseSpellCooldownActive = true
itemSlotCooldownActive = false
slotCooldownStart = 11418.804
slotCooldownDuration = 90
slotCooldownEnabled = true
local slotCooldownEntry = {
    type = "slot",
    kind = "cooldown",
    id = 13,
    name = "Slot Cooldown",
    viewerType = "custom",
}
local slotCooldownIcon = {}
state = resolve({
    owner = slotCooldownIcon,
    entry = slotCooldownEntry,
    runtimeSpellID = 91004,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "item-cooldown", "slot item cooldown with enabled=true should resolve as an item cooldown")
assert(state.isOnCooldown == true, "slot item cooldown with enabled=true should publish cooldown activity")
assert(state.durObj == createdDurationObjects[1], "slot item cooldown should use a DurationObject")
assert(state.durObj ~= itemUseSpellCooldownDur,
    "slot item cooldown should prefer real slot timing over the item-use spell cooldown")
assert(state.sourceID == "item-duration:13:90004",
    "slot item cooldown should identify the real item duration source")
assert(state.numericCooldownActive == true, "slot item cooldown should publish clean numeric timing")
assert(state.start == 11418.804 and state.duration == 90,
    "slot item cooldown should carry timing for custom bars")
assert(durationObjectSetCalls[1].start == 11418.804 and durationObjectSetCalls[1].duration == 90,
    "slot item cooldown should seed the DurationObject from slot timing")

storeResolvedRuntimeState(slotCooldownIcon, state)
state = resolve({
    owner = slotCooldownIcon,
    entry = slotCooldownEntry,
    runtimeSpellID = 91004,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.durObj == createdDurationObjects[1],
    "unchanged slot item timing should reuse the icon-owned DurationObject")
assert(#createdDurationObjects == 1,
    "repeated slot item timing on the same icon should not allocate another DurationObject")

state = resolve({
    owner = {},
    entry = slotCooldownEntry,
    runtimeSpellID = 91004,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.durObj ~= createdDurationObjects[1],
    "a second slot icon should not reuse another icon's item DurationObject")
assert(#createdDurationObjects == 2,
    "slot item DurationObject reuse should not be keyed by the shared cooldown entry")

createdDurationObjects = {}
durationObjectSetCalls = {}
itemSlotCooldownActive = true
slotCooldownStart = 0
slotCooldownDuration = 0
slotCooldownEnabled = true
state = resolve({
    entry = {
        type = "slot",
        kind = "cooldown",
        id = 13,
        name = "Slot Item Cooldown Fallback",
        viewerType = "custom",
    },
    runtimeSpellID = 91004,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "item-cooldown",
    "slot item cooldown should fall back to item timing when slot timing is inactive")
assert(state.isOnCooldown == true, "slot item cooldown fallback should publish cooldown activity")
assert(state.durObj == createdDurationObjects[1], "slot item cooldown fallback should use a DurationObject")
assert(state.durObj ~= itemUseSpellCooldownDur,
    "slot item cooldown fallback should prefer real item timing over the item-use spell cooldown")
assert(state.sourceID == "item-duration:13:90004",
    "slot item cooldown fallback should identify the real item duration source")
assert(state.numericCooldownActive == true, "slot item cooldown fallback should publish clean numeric timing")
assert(state.start == 11418.804 and state.duration == 90,
    "slot item cooldown fallback should carry item timing for custom bars")

createdDurationObjects = {}
durationObjectSetCalls = {}
itemSlotCooldownActive = false
slotCooldownStart = 11418.804
slotCooldownDuration = 90
slotCooldownEnabled = false
itemUseSpellCooldownActive = false
state = resolve({
    entry = {
        type = "slot",
        kind = "cooldown",
        id = 13,
        name = "Disabled Slot Cooldown",
        viewerType = "custom",
    },
    runtimeSpellID = 91004,
    containerKey = "custom",
    useBuffSwipe = true,
    showGCDSwipe = true,
})

assert(state.mode == "inactive", "slot item cooldown with enabled=false should resolve inactive")

state = resolve({
    entry = cooldownEntry(80001),
    runtimeSpellID = 80001,
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "inactive", "missing runtime facts should resolve inactive")
assert(state.active == false, "inactive state should not be active")
assert(state.durObj == nil, "inactive state should not carry a DurationObject")
assert(state.mirrorBacked == nil, "inactive state should not be mirror-backed")
assert(state.hasDurationObject == false, "inactive state should not report a DurationObject")
assert(state.hasRenderableCooldown == false, "inactive state should not report renderable swipe state")

inCombat = true
local unknownChargeQueries = chargeQueryCounts[80001] or 0
state = resolve({
    entry = cooldownEntry(80001),
    runtimeSpellID = 80001,
    containerKey = "essential",
    useBuffSwipe = false,
})
assert((chargeQueryCounts[80001] or 0) == unknownChargeQueries,
    "combat cooldown resolution should not probe charge state for unknown non-charge spells")
inCombat = false

state = resolvers.NormalizeResolvedCooldownStateContract({
    mode = "unknown",
    active = true,
    isOnCooldown = "truthy",
    rechargeActive = nil,
})
assert(state.mode == "inactive", "contract normalization should reject unknown modes")
assert(state.active == false and state.isActive == false,
    "contract normalization should clear active aliases for inactive states")
assert(state.isOnCooldown == false, "contract normalization should coerce cooldown flags")

-- Talent-override post-aura case: the Blizzard EssentialCooldownViewer slot
-- carries m.spellID=base (Berserk 50334) and m.overrideSpellID=override
-- (Incarnation: Guardian of Ursoc 102558). C_Spell.GetSpellCooldown only
-- reports isActive=true for the override. Once the aura phase ends and the
-- resolver falls through to the cooldown branch, DeriveMirrorPayloadMode must
-- probe the override or the icon stays "inactive" for the rest of the 3 min cd.
state = resolve({
    entry = cooldownEntry(102558),
    runtimeSpellID = 102558,
    mirrorCooldownID = 2700,
    mirrorCategory = "essential",
    containerKey = "essential",
    useBuffSwipe = false,
})

assert(state.mode == "cooldown",
    "talent-override slot should surface mode=cooldown once aura phase ends (Guardian Druid Incarnation reference case)")
assert(state.isOnCooldown == true,
    "talent-override cooldown should be marked active after aura phase ends")
assert(state.durObj == overrideCooldownDur,
    "talent-override cooldown must bind the override's DurationObject (the base's DurObj reflects an inactive cooldown lane and produces no visible swipe)")

print("OK: cdm_resolvers_cooldown_state_test")
