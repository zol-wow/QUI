--[[
    QUI Party Tracker — Brain (Rule Matching Engine)
    Matches detected auras against the spell rules database using evidence
    from the Observer. Attributes cooldowns to specific party members.

    Matching algorithm:
    1. Get unit spec + class from SpecCache
    2. Build evidence set from Observer (within 0.15s of detection time)
    3. Try spec-level rules first, then class fallback
    4. Check: aura type flags, evidence requirements, duration tolerance,
       cooldown deduplication, talent gates
    5. External defensives: multi-candidate tiebreaker via cast evidence
    6. On match: commit cooldown, fire callback
]]

local ADDON_NAME, ns = ...

local Brain = {}
ns.PartyTracker_Brain = Brain

local Rules = nil       -- resolved after load
local SpecCache = nil   -- resolved after load
local Observer = nil    -- resolved after load

local GetTime = GetTime
local UnitClass = UnitClass
local UnitExists = UnitExists
local math_abs = math.abs
local pairs = pairs
local ipairs = ipairs
local type = type
local select = select

local DURATION_TOLERANCE = 0.5
local EVIDENCE_TOLERANCE = 0.15

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local activeCooldowns = {}  -- unit → { [spellId|cdKey] = { startTime, cooldown, timer } }
local cooldownCallback = nil  -- function(unit, spellId, startTime, cooldown, isOffensive)

---------------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------------

function Brain.Init(onCooldownDetected)
    Rules = ns.PartyTracker_Rules
    SpecCache = ns.PartyTracker_SpecCache
    Observer = ns.PartyTracker_Observer
    cooldownCallback = onCooldownDetected
end

---------------------------------------------------------------------------
-- EVIDENCE MATCHING
---------------------------------------------------------------------------

local function EvidenceMatchesReq(evidence, requirement)
    -- nil = no constraint (anything matches)
    if requirement == nil then return true end

    -- false = requires NO evidence
    if requirement == false then
        return not next(evidence)
    end

    -- string = single evidence type required
    if type(requirement) == "string" then
        return evidence[requirement] == true
    end

    -- table = ALL listed types required
    if type(requirement) == "table" then
        for _, req in ipairs(requirement) do
            if not evidence[req] then return false end
        end
        return true
    end

    return false
end

local function AuraTypeMatchesRule(auraTypes, rule)
    -- Check each flag: true = must have, false = must not have, nil = don't care
    if rule.BigDefensive == true and not auraTypes.BigDefensive then return false end
    if rule.BigDefensive == false and auraTypes.BigDefensive then return false end
    if rule.ExternalDefensive == true and not auraTypes.ExternalDefensive then return false end
    if rule.ExternalDefensive == false and auraTypes.ExternalDefensive then return false end
    if rule.Important == true and not auraTypes.Important then return false end
    if rule.Important == false and auraTypes.Important then return false end
    return true
end

local function DurationMatches(measured, expected, rule)
    if rule.MinDuration then
        return measured >= expected - DURATION_TOLERANCE
    end
    if rule.CanCancelEarly then
        return measured <= expected + DURATION_TOLERANCE
    end
    return math_abs(measured - expected) <= DURATION_TOLERANCE
end

---------------------------------------------------------------------------
-- RULE MATCHING
---------------------------------------------------------------------------

local function MatchRuleList(rules, unit, auraTypes, measuredDuration, evidence, unitCooldowns)
    local fallback = nil

    for _, rule in ipairs(rules) do
        -- Talent gates (skip if we don't have talent info — allow match)
        -- TODO: Implement talent checking when talent data is available

        -- Aura type match
        if AuraTypeMatchesRule(auraTypes, rule) then
            -- Evidence match
            if EvidenceMatchesReq(evidence, rule.RequiresEvidence) then
                -- Duration match
                if DurationMatches(measuredDuration, rule.BuffDuration, rule) then
                    -- Cooldown deduplication
                    if rule.SpellId and unitCooldowns[rule.SpellId] then
                        -- Already on CD — store as fallback only
                        if not fallback then fallback = rule end
                    else
                        return rule
                    end
                end
            end
        end
    end

    return fallback
end

local function MatchRule(unit, auraTypes, measuredDuration, evidence)
    if not Rules then return nil end

    local unitCooldowns = activeCooldowns[unit] or {}

    -- Try spec-level rules first
    local specId = SpecCache and SpecCache.GetSpec(unit)
    if specId and Rules.BySpec[specId] then
        local rule = MatchRuleList(Rules.BySpec[specId], unit, auraTypes, measuredDuration, evidence, unitCooldowns)
        if rule then return rule end
    end

    -- Fall back to class rules
    local _, classToken = UnitClass(unit)
    if classToken and Rules.ByClass[classToken] then
        local rule = MatchRuleList(Rules.ByClass[classToken], unit, auraTypes, measuredDuration, evidence, unitCooldowns)
        if rule then return rule end
    end

    return nil
end

---------------------------------------------------------------------------
-- MULTI-CANDIDATE SELECTION (for external defensives)
---------------------------------------------------------------------------

local function FindBestCandidate(targetUnit, auraTypes, measuredDuration, detectionTime)
    if not Observer then return nil, nil end

    local bestRule, bestUnit, bestCastTime = nil, nil, nil

    -- Evaluate target unit first
    local evidence = Observer.GetEvidence(targetUnit, detectionTime)
    local rule = MatchRule(targetUnit, auraTypes, measuredDuration, evidence)
    if rule then
        bestRule = rule
        bestUnit = targetUnit
        local castTime = Observer.GetCastTime(targetUnit)
        if castTime and math_abs(castTime - detectionTime) <= EVIDENCE_TOLERANCE then
            bestCastTime = castTime
        end
    end

    -- For external defensives, check other watched units as potential casters
    if auraTypes.ExternalDefensive then
        for watchedUnit in pairs(Observer.GetWatchedUnits()) do
            if watchedUnit ~= targetUnit and UnitExists(watchedUnit) then
                local candidateEvidence = Observer.GetEvidence(watchedUnit, detectionTime)
                local candidateRule = MatchRule(watchedUnit, auraTypes, measuredDuration, candidateEvidence)
                if candidateRule then
                    local candidateCast = Observer.GetCastTime(watchedUnit)
                    local candidateCastTime = candidateCast and math_abs(candidateCast - detectionTime) <= EVIDENCE_TOLERANCE and candidateCast or nil

                    -- Prefer candidate with cast evidence (most recent cast wins)
                    if candidateCastTime then
                        if not bestCastTime or candidateCastTime > bestCastTime then
                            bestRule = candidateRule
                            bestUnit = watchedUnit
                            bestCastTime = candidateCastTime
                        end
                    elseif not bestCastTime and not bestUnit then
                        -- No cast evidence anywhere — take the non-target candidate
                        bestRule = candidateRule
                        bestUnit = watchedUnit
                    end
                end
            end
        end
    end

    return bestRule, bestUnit
end

---------------------------------------------------------------------------
-- COOLDOWN COMMIT
---------------------------------------------------------------------------

local function CommitCooldown(unit, rule, measuredDuration)
    if not unit or not rule then return end

    local cooldown = rule.Cooldown
    local spellId = rule.SpellId
    local cdKey = spellId or string.format("%s_%s_%s",
        rule.BigDefensive and "BD" or (rule.ExternalDefensive and "ED" or "IMP"),
        rule.BuffDuration, rule.Cooldown)

    local startTime = GetTime()
    local remaining = cooldown - measuredDuration
    if remaining <= 0 then remaining = cooldown end

    if not activeCooldowns[unit] then activeCooldowns[unit] = {} end

    -- Cancel existing timer for this cdKey
    local existing = activeCooldowns[unit][cdKey]
    if existing and existing.timer then
        existing.timer:Cancel()
    end

    -- Create cleanup timer
    local timer = C_Timer.NewTimer(remaining, function()
        local unitCDs = activeCooldowns[unit]
        if unitCDs then
            unitCDs[cdKey] = nil
        end
        -- Notify display to update
        if cooldownCallback then
            cooldownCallback(unit, spellId, nil, nil, nil)
        end
    end)

    activeCooldowns[unit][cdKey] = {
        startTime = startTime,
        cooldown = cooldown,
        spellId = spellId,
        timer = timer,
    }

    local isOffensive = rule.Offensive or (spellId and Rules.OffensiveSpellIds[spellId])
    if cooldownCallback then
        cooldownCallback(unit, spellId, startTime, cooldown, isOffensive)
    end
end

---------------------------------------------------------------------------
-- PUBLIC API — Called by CooldownDisplay when auras change
---------------------------------------------------------------------------

function Brain.ProcessAuraDetection(unit, auraTypes, measuredDuration, detectionTime)
    if not unit or not measuredDuration then return end

    local dt = detectionTime or GetTime()

    -- Try immediate match
    local rule, ruleUnit = FindBestCandidate(unit, auraTypes, measuredDuration, dt)

    if rule and ruleUnit then
        CommitCooldown(ruleUnit, rule, measuredDuration)
    else
        -- Deferred backfill: retry after evidence tolerance window
        -- (late-arriving UNIT_SPELLCAST_SUCCEEDED)
        C_Timer.After(EVIDENCE_TOLERANCE, function()
            if not UnitExists(unit) then return end
            local retryRule, retryUnit = FindBestCandidate(unit, auraTypes, measuredDuration, dt)
            if retryRule and retryUnit then
                -- Check we haven't already committed this
                local unitCDs = activeCooldowns[retryUnit]
                local cdKey = retryRule.SpellId or string.format("%s_%s_%s",
                    retryRule.BigDefensive and "BD" or (retryRule.ExternalDefensive and "ED" or "IMP"),
                    retryRule.BuffDuration, retryRule.Cooldown)
                if not unitCDs or not unitCDs[cdKey] then
                    CommitCooldown(retryUnit, retryRule, measuredDuration)
                end
            end
        end)
    end
end

function Brain.GetActiveCooldowns(unit)
    return activeCooldowns[unit] or {}
end

function Brain.GetAllActiveCooldowns()
    return activeCooldowns
end

function Brain.ClearUnit(unit)
    local unitCDs = activeCooldowns[unit]
    if unitCDs then
        for _, cdData in pairs(unitCDs) do
            if cdData.timer then cdData.timer:Cancel() end
        end
        activeCooldowns[unit] = nil
    end
end

function Brain.ClearAll()
    for unit, unitCDs in pairs(activeCooldowns) do
        for _, cdData in pairs(unitCDs) do
            if cdData.timer then cdData.timer:Cancel() end
        end
    end
    wipe(activeCooldowns)
end
