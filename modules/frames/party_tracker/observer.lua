--[[
    QUI Party Tracker — Evidence Observer
    Per-unit event monitoring that records timestamps for evidence-based
    cooldown attribution. The Brain queries these timestamps to determine
    what events occurred near an aura detection.

    Evidence types:
      Cast       — UNIT_SPELLCAST_SUCCEEDED
      Debuff     — HARMFUL aura added (UNIT_AURA)
      Shield     — UNIT_ABSORB_AMOUNT_CHANGED
      UnitFlags  — UNIT_FLAGS (combat/immune state change)
      FeignDeath — UNIT_FLAGS with UnitIsFeignDeath transition
]]

local ADDON_NAME, ns = ...

local Observer = {}
ns.PartyTracker_Observer = Observer

local GetTime = GetTime
local UnitIsFeignDeath = UnitIsFeignDeath
local UnitIsEnemy = UnitIsEnemy
local CreateFrame = CreateFrame
local C_UnitAuras = C_UnitAuras
local math_abs = math.abs

local EVIDENCE_TOLERANCE = 0.15

---------------------------------------------------------------------------
-- PER-UNIT STATE
---------------------------------------------------------------------------
local unitState = {}  -- unit → { lastCastTime, lastDebuffTime, lastShieldTime, lastUnitFlagsTime, lastFeignDeathTime, lastFeignState }
local unitFrames = {} -- unit → event frame
local watchedUnits = {} -- set of active units

---------------------------------------------------------------------------
-- GLOBAL ABSORB FRAME
---------------------------------------------------------------------------
C_Timer.After(0, function()
    local absorbFrame = CreateFrame("Frame")
    absorbFrame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    absorbFrame:SetScript("OnEvent", function(_, _, unit)
        local state = unitState[unit]
        if state then
            state.lastShieldTime = GetTime()
        end
    end)
end)

---------------------------------------------------------------------------
-- PER-UNIT EVENT FRAME
---------------------------------------------------------------------------
local function CreateUnitEventFrame(unit)
    local frame = CreateFrame("Frame")

    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    frame:RegisterUnitEvent("UNIT_FLAGS", unit)
    frame:RegisterUnitEvent("UNIT_AURA", unit)

    frame:SetScript("OnEvent", function(_, event, u, ...)
        local state = unitState[u]
        if not state then return end

        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Only track friendly casts
            if not UnitIsEnemy("player", u) then
                state.lastCastTime = GetTime()
            end

        elseif event == "UNIT_FLAGS" then
            -- Detect feign death transitions (Hunter-specific)
            local isFeignDeath = UnitIsFeignDeath(u)
            if isFeignDeath and not state.lastFeignState then
                -- Transition into feign death
                state.lastFeignDeathTime = GetTime()
            elseif not isFeignDeath then
                -- Not feigning — record UnitFlags change
                state.lastUnitFlagsTime = GetTime()
            end
            state.lastFeignState = isFeignDeath

        elseif event == "UNIT_AURA" then
            -- Check for HARMFUL aura additions (debuff evidence)
            -- Pass auraInstanceID directly to C-side IsAuraFilteredOutByInstanceID
            -- (handles secrets natively). Don't boolean-test aura fields.
            local updateInfo = ...
            if updateInfo and not updateInfo.isFullUpdate and updateInfo.addedAuras then
                for _, auraData in ipairs(updateInfo.addedAuras) do
                    -- Pass auraInstanceID directly to C-side filter check
                    local ok, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, u, auraData.auraInstanceID, "HARMFUL")
                    if ok and not filtered then
                        state.lastDebuffTime = GetTime()
                        break
                    end
                end
            end
        end
    end)

    return frame
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------

function Observer.Watch(unit)
    if not unit or watchedUnits[unit] then return end

    watchedUnits[unit] = true
    unitState[unit] = {
        lastCastTime = nil,
        lastDebuffTime = nil,
        lastShieldTime = nil,
        lastUnitFlagsTime = nil,
        lastFeignDeathTime = nil,
        lastFeignState = false,
    }

    if not unitFrames[unit] then
        unitFrames[unit] = CreateUnitEventFrame(unit)
    end
end

function Observer.Unwatch(unit)
    if not unit or not watchedUnits[unit] then return end

    watchedUnits[unit] = nil

    local frame = unitFrames[unit]
    if frame then
        frame:UnregisterAllEvents()
        unitFrames[unit] = nil
    end

    unitState[unit] = nil
end

function Observer.GetEvidence(unit, detectionTime)
    local state = unitState[unit]
    if not state then return {} end

    local evidence = {}
    local t = detectionTime or GetTime()

    if state.lastCastTime and math_abs(state.lastCastTime - t) <= EVIDENCE_TOLERANCE then
        evidence.Cast = true
    end
    if state.lastDebuffTime and math_abs(state.lastDebuffTime - t) <= EVIDENCE_TOLERANCE then
        evidence.Debuff = true
    end
    if state.lastShieldTime and math_abs(state.lastShieldTime - t) <= EVIDENCE_TOLERANCE then
        evidence.Shield = true
    end

    -- FeignDeath and UnitFlags are mutually exclusive
    if state.lastFeignDeathTime and math_abs(state.lastFeignDeathTime - t) <= EVIDENCE_TOLERANCE then
        evidence.FeignDeath = true
    elseif state.lastUnitFlagsTime and math_abs(state.lastUnitFlagsTime - t) <= EVIDENCE_TOLERANCE then
        evidence.UnitFlags = true
    end

    return evidence
end

function Observer.GetCastTime(unit)
    local state = unitState[unit]
    return state and state.lastCastTime
end

function Observer.GetWatchedUnits()
    return watchedUnits
end

function Observer.ClearUnit(unit)
    local state = unitState[unit]
    if state then
        state.lastCastTime = nil
        state.lastDebuffTime = nil
        state.lastShieldTime = nil
        state.lastUnitFlagsTime = nil
        state.lastFeignDeathTime = nil
        state.lastFeignState = false
    end
end

function Observer.ClearAll()
    for unit in pairs(watchedUnits) do
        Observer.Unwatch(unit)
    end
    wipe(unitState)
    wipe(unitFrames)
    wipe(watchedUnits)
end
