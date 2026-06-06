--[[ QUI Group Frames - Roster, Events, and Refresh ]]
local ADDON_NAME, ns = ...
local QUI_GF = ns.QUI_GroupFrames
if not QUI_GF then return end
local _ = QUI_GF._
if not _ then return end

local Helpers = _.Helpers
local IsSecretValue = _.IsSecretValue
local SafeValue = _.SafeValue
local _state = _.state
local _pending = _.pending
local GetSettings = _.GetSettings
local GetVisualDB = _.GetVisualDB
local GetGroupMode = _.GetGroupMode
local GetGroupSize = _.GetGroupSize
local GetRangeSettings = _.GetRangeSettings
local GetIndicatorSettings = _.GetIndicatorSettings
local GetPowerSettings = _.GetPowerSettings
local GetFrameState = _.GetFrameState
local IsNPCPartyMember = _.IsNPCPartyMember
local UseRaidSectionHeaders = _.UseRaidSectionHeaders
local GetPartySelfFirst = _.GetPartySelfFirst
local AddFrameToMap = _.AddFrameToMap
local ApplyStatusBarTexture = _.ApplyStatusBarTexture
local InvalidateCache = _.InvalidateCache
local UpdateHealth = _.UpdateHealth
local UpdatePower = _.UpdatePower
local UpdateName = _.UpdateName
local UpdateAbsorbs = _.UpdateAbsorbs
local UpdateHealAbsorb = _.UpdateHealAbsorb
local UpdateHealPrediction = _.UpdateHealPrediction
local UpdateReadyCheck = _.UpdateReadyCheck
local UpdateThreat = _.UpdateThreat
local UpdateConnection = _.UpdateConnection
local UpdatePhaseIcon = _.UpdatePhaseIcon
local UpdateResurrection = _.UpdateResurrection
local UpdateSummonPending = _.UpdateSummonPending
local UpdateTargetMarker = _.UpdateTargetMarker
local UpdateLeaderIcon = _.UpdateLeaderIcon
local UpdateTargetHighlight = _.UpdateTargetHighlight
local UpdateFrame = _.UpdateFrame
local UpdateHeaderVisibility = _.UpdateHeaderVisibility
local UpdateFrameScaling = _.UpdateFrameScaling
local UpdateHeaderSizes = _.UpdateHeaderSizes
local UpdateAnchorFrames = _.UpdateAnchorFrames
local PositionRaidGroupHeaders = _.PositionRaidGroupHeaders
local CreateHeaders = _.CreateHeaders
local CreateSpotlightHeader = _.CreateSpotlightHeader
local ConfigurePartyHeader = _.ConfigurePartyHeader
local ConfigureRaidHeader = _.ConfigureRaidHeader
local ConfigureRaidGroupHeaders = _.ConfigureRaidGroupHeaders
local ApplyHUDLayering = _.ApplyHUDLayering
local RegisterUnitWatch = RegisterUnitWatch
local type = type
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local C_Timer = C_Timer
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitClass = UnitClass
local UnitIsUnit = UnitIsUnit
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitCanAttack = UnitCanAttack
local UnitInRange = UnitInRange
local UnitPhaseReason = UnitPhaseReason
local GetNumGroupMembers = GetNumGroupMembers
local C_Spell = C_Spell
local IsPlayerSpell = IsPlayerSpell
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local CheckInteractDistance = CheckInteractDistance
local issecretvalue = _G.issecretvalue
local math_max = math.max

local powerThrottle = {}
local absorbThrottle = {}
local healPredThrottle = {}
local THROTTLE_INTERVAL = 0.1
local UpdateSelectiveEvents
local gruCoalesceFrame = CreateFrame("Frame")
gruCoalesceFrame:Hide()

local function IsCliqueLoaded()
    if _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded then
        local loaded, finished = _G.C_AddOns.IsAddOnLoaded("Clique")
        return (loaded or finished) and true or false
    end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded("Clique") and true or false
end

local function RegisterWithClique()
    if not IsCliqueLoaded() and not _G.ClickCastFrames then return end

    _G.ClickCastFrames = _G.ClickCastFrames or {}
    for _, frame in ipairs(QUI_GF.allFrames) do
        if frame and frame.GetName then
            _G.ClickCastFrames[frame] = true
        end
    end
end
QUI_GF.RegisterWithClique = RegisterWithClique

local function RefreshClickCastFrames()
    RegisterWithClique()

    local GFCC = ns.QUI_GroupFrameClickCast
    if not GFCC or InCombatLockdown() then return end

    if GFCC.Initialize and GFCC.IsEnabled and not GFCC:IsEnabled() then
        GFCC:Initialize()
    end

    if GFCC.RegisterAllFrames and GFCC.IsEnabled and GFCC:IsEnabled() then
        GFCC:RegisterAllFrames()
    end
end
_.RefreshClickCastFrames = RefreshClickCastFrames

local function CollectHeaderUnits(header)
    if not header or not header:IsShown() then return end
    local i = 1
    while true do
        local child = header:GetAttribute("child" .. i)
        if not child then break end
        local unit = child:GetAttribute("unit")
        child.unit = unit  -- sync Lua property (nil clears stale)
        if unit then
            AddFrameToMap(unit, child)
        end
        i = i + 1
    end
end

local function RebuildUnitFrameMap()
    if _state.UnregisterAllUnitEventFrames then
        _state.UnregisterAllUnitEventFrames()
    end
    wipe(QUI_GF.unitFrameMap)

    CollectHeaderUnits(QUI_GF.headers.party)
    CollectHeaderUnits(QUI_GF.headers.self)

    if UseRaidSectionHeaders() and IsInRaid() then
        for _, header in ipairs(QUI_GF.raidGroupHeaders) do
            CollectHeaderUnits(header)
        end
    else
        CollectHeaderUnits(QUI_GF.headers.raid)
    end

    CollectHeaderUnits(QUI_GF.spotlightHeader)

    if _state.RefreshUnitEventRegistrations then
        _state.RefreshUnitEventRegistrations()
    end
end

local RANGE_SPELLS = {
    spec = {
        [250] = nil, [251] = nil, [252] = nil,
        [577] = nil, [581] = nil,
        [102] = 8936, [103] = 8936, [104] = 8936,
        [105] = 774,
        [1467] = 360995, [1468] = 360995, [1473] = 360995,
        [253] = nil, [254] = nil, [255] = nil,
        [62] = 1459, [63] = 1459, [64] = 1459,
        [268] = 116670, [269] = 116670, [270] = 116670,
        [65] = 19750, [66] = 19750, [70] = 19750,
        [256] = 17, [257] = 2061, [258] = 17,
        [259] = 57934, [260] = 57934, [261] = 57934,
        [262] = 8004, [263] = 8004, [264] = 8004,
        [265] = 5697, [266] = 5697, [267] = 5697,
        [71] = nil, [72] = nil, [73] = nil,
    },
    specHostile = {
        [250] = 47541, [251] = 47541, [252] = 47541,
        [577] = 185123, [581] = 185123,
        [102] = 8921, [103] = 8921, [104] = 8921, [105] = 8921,
        [1467] = 361469, [1468] = 361469, [1473] = 361469,
        [253] = 193455, [254] = 19434, [255] = 259491,
        [62] = 30451, [63] = 133, [64] = 116,
        [268] = 115546, [269] = 115546, [270] = 115546,
        [65] = 62124, [66] = 62124, [70] = 62124,
        [256] = 585, [257] = 585, [258] = 585,
        [259] = 36554, [260] = 185763, [261] = 36554,
        [262] = 188196, [263] = 188196, [264] = 188196,
        [265] = 686, [266] = 686, [267] = 29722,
        [71] = 355, [72] = 355, [73] = 355,
    },
    class = {
        PRIEST      = { 2061, 17 },
        PALADIN     = { 19750 },
        DRUID       = { 8936, 774 },
        SHAMAN      = { 8004 },
        MONK        = { 116670 },
        EVOKER      = { 360995, 361469 },
        MAGE        = { 1459 },
        WARLOCK     = { 5697 },
        ROGUE       = { 57934 },
        DEATHKNIGHT = {},
        WARRIOR     = {},
        DEMONHUNTER = {},
        HUNTER      = {},
    },
    classHostile = {
        DEATHKNIGHT = 47541, DEMONHUNTER = 185123, DRUID = 8921,
        EVOKER = 361469, HUNTER = 75, MAGE = 116, MONK = 115546,
        PALADIN = 62124, PRIEST = 585, ROGUE = 36554,
        SHAMAN = 188196, WARLOCK = 686, WARRIOR = 355,
    },
    res = {
        PRIEST = 2006, PALADIN = 7328, DRUID = 50769,
        SHAMAN = 2008, MONK = 115178, EVOKER = 361227, DEATHKNIGHT = 61999,
    },
}

local _range = {
    playerClass = nil,
    spell = nil,
    hostileSpell = nil,
    resSpell = nil,
    cache = {},
    cacheTime = {},
}

local function ResolveRangeSpells()
    if not _range.playerClass then
        _range.playerClass = select(2, UnitClass("player"))
    end

    -- Clear cache — spells changed, previous results may be stale
    wipe(_range.cache)

    -- Resolve primary range spell (spec-based first, then class fallback)
    _range.spell = nil
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if specID and RANGE_SPELLS.spec[specID] then
        local spellID = RANGE_SPELLS.spec[specID]
        if spellID and IsPlayerSpell(spellID) then
            _range.spell = spellID
        end
    end

    -- Class fallback if spec lookup didn't resolve
    if not _range.spell then
        local candidates = RANGE_SPELLS.class[_range.playerClass]
        if candidates then
            for _, spellID in ipairs(candidates) do
                if IsPlayerSpell(spellID) then
                    _range.spell = spellID
                    break
                end
            end
        end
    end

    _range.hostileSpell = nil
    if specID and RANGE_SPELLS.specHostile[specID] then
        local hid = RANGE_SPELLS.specHostile[specID]
        if hid and IsPlayerSpell(hid) then
            _range.hostileSpell = hid
        end
    end
    if not _range.hostileSpell then
        local hid = RANGE_SPELLS.classHostile[_range.playerClass]
        if hid and IsPlayerSpell(hid) then
            _range.hostileSpell = hid
        end
    end

    -- Resolve rez spell (Druid: Rebirth for combat-consistent corpse range)
    _range.resSpell = nil
    if _range.playerClass == "DRUID" then
        if IsPlayerSpell(20484) then
            _range.resSpell = 20484
        elseif IsPlayerSpell(50769) then
            _range.resSpell = 50769
        end
    else
        local rezID = RANGE_SPELLS.res[_range.playerClass]
        if rezID and IsPlayerSpell(rezID) then
            _range.resSpell = rezID
        end
    end
end

local function CheckUnitRange(unit)
    if UnitIsUnit(unit, "player") then return true end
    if not UnitExists(unit) then return true end

    -- Phased units are always out of range
    if UnitPhaseReason and UnitPhaseReason(unit) then
        return false
    end

    local connected = UnitIsConnected(unit)
    if IsSecretValue(connected) then connected = true end
    if not connected then
        if not IsNPCPartyMember(unit) then return true end
    end

    local isDead = UnitIsDeadOrGhost(unit)
    if IsSecretValue(isDead) then isDead = false end

    local friendlyReturnedNil = false

    -- Hostile units (UnitCanAttack): check hostile spell range first;
    -- also handles edge cases with cross-faction party members.
    if UnitCanAttack("player", unit) then
        if _range.hostileSpell then
            local inRangeH = C_Spell.IsSpellInRange(_range.hostileSpell, unit)
            if inRangeH ~= nil then
                return inRangeH
            end
        end
        return true
    end

    if _range.spell and not isDead then
        local result = C_Spell.IsSpellInRange(_range.spell, unit)
        if result == true then
            return true
        elseif result == false then
            if not InCombatLockdown() and CheckInteractDistance(unit, 4) then
                return true
            end
            return false
        else
            friendlyReturnedNil = true
        end
        -- result == nil: spell not applicable, fall through to UnitInRange
    end

    if isDead and _range.resSpell then
        local result = C_Spell.IsSpellInRange(_range.resSpell, unit)
        if result ~= nil then return result end
    end

    if not InCombatLockdown() then
        return CheckInteractDistance(unit, 4) and true or false
    end

    -- In-combat fallback: UnitInRange (~38-40 yd) before treating friendly nil as OOR.
    -- Returns secret booleans in Midnight+ — SetAlphaFromBoolean handles them natively.
    if UnitInRange then
        local inRange = UnitInRange(unit)
        if issecretvalue and issecretvalue(inRange) then
            return inRange
        end
        if inRange ~= nil then return inRange end
    end

    if _range.spell and friendlyReturnedNil and connected and not isDead then
        return false
    end

    return true
end

local function ApplyRangeAlpha(frame, inRange, outAlpha)
    -- SetAlphaFromBoolean handles secret booleans natively (Midnight+ C-side API).
    -- When UnitInRange returns a secret boolean, this resolves it correctly.
    if frame.SetAlphaFromBoolean then
        frame:SetAlphaFromBoolean(inRange, 1, outAlpha)
    else
        frame:SetAlpha(inRange and 1 or outAlpha)
    end
end

local function DoRangeCheck()
    -- Fallback ticker: catches edge cases not covered by UNIT_IN_RANGE_UPDATE
    -- (LibRangeCheck spells with non-38yd thresholds, OOC interact distance).
    -- Skips units recently updated by the event handler.
    local partyRange = GetRangeSettings(false)
    local raidRange = GetRangeSettings(true)
    if (not partyRange or partyRange.enabled == false) and (not raidRange or raidRange.enabled == false) then return end

    local now = GetTime()
    for unit, list in pairs(QUI_GF.unitFrameMap) do
        -- Skip units updated by UNIT_IN_RANGE_UPDATE within the last 0.4s
        local lastEventTime = _range.cacheTime[unit]
        if not (lastEventTime and (now - lastEventTime) < 0.4) then
            -- Compute range once per unit, apply per-frame below.
            local inRange = CheckUnitRange(unit)
            local cached = _range.cache[unit]
            local isSecret = issecretvalue and (issecretvalue(inRange) or issecretvalue(cached))
            local rangeChanged = isSecret or cached ~= inRange
            if rangeChanged then
                _range.cache[unit] = inRange
            end
            for i = 1, #list do
                local frame = list[i]
                if frame and frame:IsShown() then
                    local rangeSettings = GetRangeSettings(frame._isRaid)
                    if rangeSettings and rangeSettings.enabled ~= false then
                        local outAlpha = rangeSettings.outOfRangeAlpha or 0.4
                        local state = GetFrameState(frame)
                        if rangeChanged or state.outOfRange == nil then
                            state.outOfRange = true
                            state.inRange = inRange
                            ApplyRangeAlpha(frame, inRange, outAlpha)
                        end
                    end
                end
            end
        end
    end
end

local function StartRangeCheck()
    if _state.rangeCheckTicker then return end
    -- Start if either party or raid has range checking enabled
    local partyRange = GetRangeSettings(false)
    local raidRange = GetRangeSettings(true)
    if (not partyRange or partyRange.enabled == false) and (not raidRange or raidRange.enabled == false) then return end

    -- Ensure spells are resolved before starting
    if not _range.spell and not _range.resSpell and not _range.hostileSpell then
        ResolveRangeSpells()
    end

    -- Slow fallback interval — UNIT_IN_RANGE_UPDATE is the primary driver.
    -- Large raids use a longer interval to reduce per-tick work (40+ frames).
    local interval = GetGroupSize() > 25 and 1.0 or 0.75
    _state.rangeCheckTicker = C_Timer.NewTicker(interval, DoRangeCheck)
end

local function StopRangeCheck()
    if _state.rangeCheckTicker then
        _state.rangeCheckTicker:Cancel()
        _state.rangeCheckTicker = nil
    end
    wipe(_range.cache)
    wipe(_range.cacheTime)
end

---------------------------------------------------------------------------
-- GROUP_ROSTER_UPDATE: Hoisted deferred callback (avoids closure allocation)
-- Called 0.2s after the coalesced GRU fires, giving secure headers time to
-- create/reassign children before we rebuild the unit→frame map.
---------------------------------------------------------------------------
local function GRU_DeferredWork()
    _state.gruDeferredPending = false
    -- Decoration runs at ADDON_LOADED via QUIGroupUnitButtonTemplate OnLoad —
    -- nothing to decorate here even on a full roster change.
    RebuildUnitFrameMap()
    -- Refresh GUID cache so OnAttributeChanged skip has fresh data
    for unit, list in pairs(QUI_GF.unitFrameMap) do
        local guid = UnitGUID(unit)
        if guid and IsSecretValue(guid) then guid = nil end
        for i = 1, #list do
            _state.unitGuidCache[list[i]] = guid
        end
    end
    wipe(_range.cache)  -- Fresh map — force re-evaluate all units
    wipe(_range.cacheTime)
    wipe(_state.cachedMarkers)
    wipe(powerThrottle)
    wipe(absorbThrottle)
    wipe(healPredThrottle)
    -- Evict stale aura cache entries for units no longer in the group
    local GFA = ns.QUI_GroupFrameAuras
    if GFA and GFA.PruneAuraCache then GFA.PruneAuraCache() end
    UpdateFrameScaling(true)
    RefreshClickCastFrames()
    QUI_GF:RefreshAllFrames("roster")
    -- Ensure ticker is running (may not have started yet on first roster event)
    StartRangeCheck()
end

-- Coalescing OnUpdate: fires once on the render frame AFTER the GRU burst.
gruCoalesceFrame:SetScript("OnUpdate", function(self)
    self:Hide()  -- One-shot: process once, then stop
    UpdateHeaderVisibility()
    UpdateFrameScaling(true)
    UpdateHeaderSizes()
    UpdateSelectiveEvents()
    -- Schedule deferred work (secure headers need time to create children).
    -- Cancel-and-reschedule: if a previous timer is still pending from an
    -- earlier burst that hasn't fired yet, this replaces it harmlessly
    -- (the flag prevents double-processing).
    if not _state.gruDeferredPending then
        _state.gruDeferredPending = true
        C_Timer.After(0.2, GRU_DeferredWork)
    end
end)

---------------------------------------------------------------------------
-- EVENTS: Centralized event dispatch
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

-- Cached module-enabled flag: refreshed on settings change, avoids
-- GetSettings() (5-6 table lookups) on every single unit event.
local function RefreshCachedEnabled()
    local db = GetSettings()
    _state.cachedModuleEnabled = db and db.enabled or false
    _state.cachedModuleDB = db
end

local function OnEvent(self, event, arg1, ...)
    if not QUI_GF.initialized then return end

    -- READY_CHECK fires with arg1 = initiatorName (a player NAME, not a unit
    -- token), so it MUST be handled before the unit-token fast path below: that
    -- path enters the type(arg1) == "string" branch, misses the name in
    -- unitFrameMap, and bails (`if not frames then return end`), which left
    -- every frame without its initial "waiting" icon when a ready check started.
    -- Paint all frames here. (READY_CHECK_CONFIRM's arg1 IS a unit token, so it
    -- stays on the fast path; READY_CHECK_FINISHED falls through to the non-unit
    -- section below.)
    if event == "READY_CHECK" then
        if not _state.cachedModuleEnabled then return end
        if QUI_GF._readyCheckHideTimer then
            QUI_GF._readyCheckHideTimer:Cancel()
            QUI_GF._readyCheckHideTimer = nil
        end
        for _, list in pairs(QUI_GF.unitFrameMap) do
            for i = 1, #list do
                UpdateReadyCheck(list[i])
            end
        end
        return
    end

    -- Fast path: unit events use O(1) map lookup.
    -- Skip GetSettings() entirely for units not in the map (nameplates,
    -- boss, arena, target, focus, pet) — saves ~20k table lookups/sec in raids.
    if type(arg1) == "string" then
        local frames = QUI_GF.unitFrameMap[arg1]

        if not frames then
            -- Self-healing: rebuild map on miss for party/raid/player units.
            -- Fast prefix check avoids per-event regex (string.sub vs :match).
            local p4 = arg1:sub(1, 4)
            if p4 == "part" or p4 == "raid" or arg1 == "player" then
                local now = GetTime()
                if not QUI_GF.lastMapRebuild or (now - QUI_GF.lastMapRebuild) > 1.0 then
                    QUI_GF.lastMapRebuild = now
                    RebuildUnitFrameMap()
                    frames = QUI_GF.unitFrameMap[arg1]
                end
            end
            if not frames then return end  -- Not a tracked unit, bail early
        end

        -- Matched frame list — check cached enabled state
        if not _state.cachedModuleEnabled then return end
        local nFrames = #frames

        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            -- Fast path: health bar only. Absorbs and heal prediction are handled
            -- by their own dedicated events (UNIT_ABSORB_AMOUNT_CHANGED,
            -- UNIT_HEAL_ABSORB_AMOUNT_CHANGED, UNIT_HEAL_PREDICTION) — calling
            -- them here doubled work in raids (~150-200 UNIT_HEALTH events/sec).
            if not UnitExists(arg1) then return end
            for i = 1, nFrames do UpdateHealth(frames[i]) end

        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            local now = GetTime()
            local last = powerThrottle[arg1] or 0
            if (now - last) < THROTTLE_INTERVAL then return end
            powerThrottle[arg1] = now
            for i = 1, nFrames do UpdatePower(frames[i]) end

        elseif event == "UNIT_MAXPOWER" then
            for i = 1, nFrames do
                local frame = frames[i]
                frame._lastMaxPower = nil  -- force SetMinMaxValues refresh
                UpdatePower(frame)
            end

        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED"
            or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
            or event == "UNIT_HEAL_PREDICTION" then
            -- Throttle: these events fire 50-100×/sec during raid damage.
            -- 100ms coalesce per unit matches the power throttle pattern.
            local now = GetTime()
            local tbl = (event == "UNIT_HEAL_PREDICTION") and healPredThrottle or absorbThrottle
            local last = tbl[arg1] or 0
            if (now - last) < THROTTLE_INTERVAL then return end
            tbl[arg1] = now
            if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
                for i = 1, nFrames do UpdateAbsorbs(frames[i]) end
            elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                for i = 1, nFrames do UpdateHealAbsorb(frames[i]) end
            else
                for i = 1, nFrames do UpdateHealPrediction(frames[i]) end
            end

        elseif event == "UNIT_NAME_UPDATE" then
            for i = 1, nFrames do UpdateName(frames[i]) end

        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            for i = 1, nFrames do UpdateThreat(frames[i]) end

        -- UNIT_AURA handled by centralized dispatcher → groupframes_auras.lua

        elseif event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
            for i = 1, nFrames do
                local frame = frames[i]
                UpdateConnection(frame)
                UpdateHealth(frame)
                UpdatePower(frame)
            end

        elseif event == "UNIT_IN_RANGE_UPDATE" then
            -- Instant range update from Blizzard (~38yd boundary crossing).
            -- Primary driver for range checks; ticker is a slow fallback.
            -- Range status is per-unit; compute once and apply to all frames.
            local inRange = CheckUnitRange(arg1)
            local cached = _range.cache[arg1]
            local isSecret = issecretvalue and (issecretvalue(inRange) or issecretvalue(cached))
            if isSecret or cached ~= inRange then
                _range.cache[arg1] = inRange
                for i = 1, nFrames do
                    local frame = frames[i]
                    local rangeSettings = GetRangeSettings(frame._isRaid)
                    if rangeSettings and rangeSettings.enabled ~= false then
                        local outAlpha = rangeSettings.outOfRangeAlpha or 0.4
                        local state = GetFrameState(frame)
                        state.outOfRange = true
                        state.inRange = inRange
                        ApplyRangeAlpha(frame, inRange, outAlpha)
                    end
                end
            end
            _range.cacheTime[arg1] = GetTime()

        elseif event == "UNIT_PHASE" then
            for i = 1, nFrames do UpdatePhaseIcon(frames[i]) end

        elseif event == "INCOMING_RESURRECT_CHANGED" then
            wipe(_range.cache)
            for i = 1, nFrames do UpdateResurrection(frames[i]) end

        elseif event == "INCOMING_SUMMON_CHANGED" then
            for i = 1, nFrames do UpdateSummonPending(frames[i]) end

        elseif event == "READY_CHECK_CONFIRM" then
            -- READY_CHECK_CONFIRM arg1 is a unit token — dispatch to all frames
            -- for that unit. GetReadyCheckStatus is per-unit, no cross-frame dep.
            for i = 1, nFrames do UpdateReadyCheck(frames[i]) end
        end
        return
    end  -- end unit event block (type(arg1) == "string")

    -- Non-unit events — check enabled via cached flag
    if not _state.cachedModuleEnabled then return end

    if event == "GROUP_ROSTER_UPDATE" then
        _state.lastGroupRosterUpdateTime = GetTime()
        -- Coalesce: show the throttle frame. Multiple GRU events in the same
        -- render frame collapse into one OnUpdate tick (Show on already-shown
        -- frame is a no-op). The heavy work runs once, next frame.
        gruCoalesceFrame:Show()

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Unhighlight previously targeted frames, then highlight new ones.
        -- Multiple frames can show the same unit (main raid + spotlight), so
        -- track a list rather than a single "the" target-highlight frame.
        local prevList = QUI_GF._targetHighlightFrames
        if prevList then
            for i = 1, #prevList do
                local f = prevList[i]
                if f.targetHighlight then f.targetHighlight:Hide() end
            end
            wipe(prevList)
        else
            QUI_GF._targetHighlightFrames = {}
            prevList = QUI_GF._targetHighlightFrames
        end
        local targetUnit = UnitExists("target") and "target" or nil
        if targetUnit then
            for _, list in pairs(QUI_GF.unitFrameMap) do
                for i = 1, #list do
                    local frame = list[i]
                    if frame.unit and UnitIsUnit(frame.unit, "target") then
                        UpdateTargetHighlight(frame)
                        prevList[#prevList + 1] = frame
                    end
                end
            end
        end

    elseif event == "READY_CHECK_FINISHED" then
        -- Do NOT call UpdateReadyCheck here — GetReadyCheckStatus returns nil
        -- after READY_CHECK_FINISHED, which would hide icons immediately.
        -- Icons already show the correct state from READY_CHECK_CONFIRM events.
        -- Just schedule hiding after persist delay (QUI pattern).
        -- Single timer hides all icons at once (avoids N closures + N timers).
        if QUI_GF._readyCheckHideTimer then
            QUI_GF._readyCheckHideTimer:Cancel()
        end
        QUI_GF._readyCheckHideTimer = C_Timer.NewTimer(6, function()
            for _, list in pairs(QUI_GF.unitFrameMap) do
                for i = 1, #list do
                    local f = list[i]
                    if f.readyCheckIcon then
                        f.readyCheckIcon:Hide()
                    end
                end
            end
            QUI_GF._readyCheckHideTimer = nil
        end)

    elseif event == "RAID_TARGET_UPDATE" then
        local inCombat = InCombatLockdown()
        if inCombat then
            if _pending.markerUpdate then
                return
            end
            _pending.markerUpdate = true
            C_Timer.After(0, function()
                _pending.markerUpdate = false
                for _, list in pairs(QUI_GF.unitFrameMap) do
                    for i = 1, #list do UpdateTargetMarker(list[i]) end
                end
            end)
        else
            for unit, list in pairs(QUI_GF.unitFrameMap) do
                local marker = GetRaidTargetIndex(unit)
                local safeMarker = Helpers.SafeValue(marker, 0)
                if safeMarker ~= _state.cachedMarkers[unit] then
                    _state.cachedMarkers[unit] = safeMarker
                    for i = 1, #list do UpdateTargetMarker(list[i]) end
                end
            end
        end

    elseif event == "PARTY_LEADER_CHANGED" then
        for _, list in pairs(QUI_GF.unitFrameMap) do
            for i = 1, #list do
                UpdateLeaderIcon(list[i])
            end
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: clear range cache so stale OOC values
        -- (CheckInteractDistance) don't persist into combat where
        -- that API is unavailable.
        _state.EnsureCombatVisibleRoots()
        wipe(_range.cache)
        wipe(_range.cacheTime)

    elseif event == "ENCOUNTER_START"
        or event == "CHALLENGE_MODE_START"
        or event == "PVP_MATCH_ACTIVE"
    then
        -- Aura instance IDs reset at encounter / M+ / PvP match start, so
        -- any positive classification hits from the previous context are stale.
        if _.ClearDefensiveCache then _.ClearDefensiveCache() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: clear range cache so combat-era results
        -- don't prevent OOC methods from updating.
        wipe(_range.cache)
        wipe(_range.cacheTime)
        -- Evict the positive defensive classification cache. Even without
        -- negative entries, defensive auraInstanceIDs stay unique for the life
        -- of the application, so OOC is still the right time to reset it.
        if _.ClearDefensiveCache then _.ClearDefensiveCache() end

        -- Process deferred operations
        if _pending.refreshSettings then
            _pending.refreshSettings = false
            -- Full refresh: repositions headers AND reconfigures children.
            -- RefreshSettings deferred during combat because SetAttribute on
            -- SecureGroupHeaders is protected.
            QUI_GF:RefreshSettings()
        elseif _pending.resize then
            _pending.resize = false
            local force = _pending.resizeForce
            _pending.resizeForce = false
            UpdateFrameScaling(force)
        end
        if _pending.visibilityUpdate then
            _pending.visibilityUpdate = false
            UpdateHeaderVisibility()
        end
        if _pending.groupReflow then
            _pending.groupReflow = false
            PositionRaidGroupHeaders()
        end
        if _pending.registerClicks then
            _pending.registerClicks = false
            -- Catch up on click registration for frames whose OnLoad path
            -- deferred RegisterForClicks due to combat lockdown.
            for _, frame in ipairs(QUI_GF.allFrames) do
                frame:RegisterForClicks("AnyUp")
            end
            -- Re-register click-casting for frames that were decorated during
            -- combat but missed click-cast setup (SetupFrameClickCast bails
            -- out during InCombatLockdown — the frame is marked _quiDecorated
            -- but never got its secure click attributes applied).
            RefreshClickCastFrames()
        end
        if _pending.anchorUpdate then
            _pending.anchorUpdate = false
            UpdateAnchorFrames()
        end
        RefreshClickCastFrames()
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            UpdateHeaderVisibility()
            UpdateFrameScaling(true)
            ResolveRangeSpells()
            RefreshClickCastFrames()
        end)

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
        ResolveRangeSpells()
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

function _state.RegisterUnitEventsForUnit(unit)
    if not _state.unitEventRegistrationEnabled or not unit or not QUI_GF.unitFrameMap[unit] then return end

    local frame = _state.unitEventFrames[unit]
    if not frame then
        frame = CreateFrame("Frame")
        frame:Hide()
        frame:SetScript("OnEvent", OnEvent)
        _state.unitEventFrames[unit] = frame
    end

    local active = _state.unitEventActive
    for i = 1, #_state.unitEventList do
        local event = _state.unitEventList[i]
        if active[event] then
            frame:RegisterUnitEvent(event, unit)
        else
            frame:UnregisterEvent(event)
        end
    end
end

function _state.UnregisterUnitEventsForUnit(unit)
    local frame = unit and _state.unitEventFrames[unit]
    if not frame then return end

    for i = 1, #_state.unitEventList do
        frame:UnregisterEvent(_state.unitEventList[i])
    end
end

function _state.UnregisterAllUnitEventFrames()
    for unit in pairs(_state.unitEventFrames) do
        _state.UnregisterUnitEventsForUnit(unit)
    end
end

function _state.RefreshUnitEventRegistrations()
    if not _state.unitEventRegistrationEnabled then return end

    for unit in pairs(_state.unitEventFrames) do
        if not QUI_GF.unitFrameMap[unit] then
            _state.UnregisterUnitEventsForUnit(unit)
        end
    end
    for unit in pairs(QUI_GF.unitFrameMap) do
        _state.RegisterUnitEventsForUnit(unit)
    end
end

function _state.SetUnitEventActive(event, active)
    local enabled = active and true or nil
    if _state.unitEventActive[event] == enabled then return end

    _state.unitEventActive[event] = enabled
    if not _state.unitEventRegistrationEnabled then return end

    if enabled then
        for unit in pairs(QUI_GF.unitFrameMap) do
            _state.RegisterUnitEventsForUnit(unit)
        end
    else
        for _, frame in pairs(_state.unitEventFrames) do
            frame:UnregisterEvent(event)
        end
    end
end

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = { name = "GF_powerThrottle", tbl = powerThrottle }
    mp[#mp + 1] = { name = "GF_absorbThrottle", tbl = absorbThrottle }
    mp[#mp + 1] = { name = "GF_healPredThrottle", tbl = healPredThrottle }
    ns.QUI_PerfRegistry = ns.QUI_PerfRegistry or {}
    ns.QUI_PerfRegistry[#ns.QUI_PerfRegistry + 1] = { name = "GroupFrames", frame = eventFrame }
end

if ns.DebugRegister then
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end

---------------------------------------------------------------------------
-- EVENT REGISTRATION
---------------------------------------------------------------------------
local function RegisterEvents()
    -- Group events
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("PVP_MATCH_ACTIVE")

    -- Noisy unit events are registered on per-unit hidden frames via
    -- RegisterUnitEvent, so unrelated nameplate/target traffic never reaches
    -- the group-frame dispatcher.
    _state.unitEventRegistrationEnabled = true
    _state.RefreshUnitEventRegistrations()

    -- Lower-volume or compatibility-sensitive unit events stay on the central
    -- frame and are still filtered through unitFrameMap in OnEvent.
    eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    -- UNIT_AURA handled by centralized dispatcher (core/aura_events.lua)
    eventFrame:RegisterEvent("UNIT_FLAGS")
    eventFrame:RegisterEvent("UNIT_PHASE")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")

    -- Range event (instant ~38yd boundary crossing, supplements ticker polling)
    eventFrame:RegisterEvent("UNIT_IN_RANGE_UPDATE")

    -- Non-unit events
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
    eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
end

local function UnregisterEvents()
    eventFrame:UnregisterAllEvents()
    _state.unitEventRegistrationEnabled = false
    _state.UnregisterAllUnitEventFrames()
end

---------------------------------------------------------------------------
-- SELECTIVE EVENT REGISTRATION: Unregister noisy events when their
-- corresponding visual feature is disabled, reducing wasted Lua dispatch.
---------------------------------------------------------------------------
UpdateSelectiveEvents = function()
    local db = GetSettings()
    local mode = GetGroupMode()
    local isRaid = (mode ~= "party")

    -- Power events: unregister in large raids when power bar hidden
    local powerSettings = GetPowerSettings(isRaid)
    if mode == "large" and (not powerSettings or powerSettings.showPowerBar == false) then
        _state.SetUnitEventActive("UNIT_POWER_UPDATE", false)
        _state.SetUnitEventActive("UNIT_POWER_FREQUENT", false)
        _state.SetUnitEventActive("UNIT_MAXPOWER", false)
    else
        _state.SetUnitEventActive("UNIT_POWER_UPDATE", true)
        _state.SetUnitEventActive("UNIT_POWER_FREQUENT", false)
        _state.SetUnitEventActive("UNIT_MAXPOWER", true)
    end

    -- Absorb/heal-prediction events: unregister when their bars are disabled
    -- in the current mode. These fire 50-100×/sec during raid damage.
    local vdb = GetVisualDB(isRaid)
    local absorbEnabled = vdb and vdb.absorbs and vdb.absorbs.enabled ~= false
    local healAbsorbEnabled = vdb and vdb.healAbsorbs and vdb.healAbsorbs.enabled ~= false
    local healPredEnabled = vdb and vdb.healPrediction and vdb.healPrediction.enabled ~= false
    -- Gate each event on its OWN toggle. "Show Absorb Shield" (absorbs) and
    -- "Show Heal Absorb" (healAbsorbs) are independent, and
    -- UNIT_HEAL_ABSORB_AMOUNT_CHANGED is the only runtime driver of
    -- UpdateHealAbsorb (the UNIT_HEALTH fast path deliberately skips it), so
    -- coupling it to absorbEnabled froze the heal-absorb bar.
    _state.SetUnitEventActive("UNIT_ABSORB_AMOUNT_CHANGED", absorbEnabled and true or false)
    _state.SetUnitEventActive("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", healAbsorbEnabled and true or false)
    if healPredEnabled then
        _state.SetUnitEventActive("UNIT_HEAL_PREDICTION", true)
    else
        _state.SetUnitEventActive("UNIT_HEAL_PREDICTION", false)
    end

    -- Threat events: UNIT_THREAT_SITUATION_UPDATE fires for ALL units in the
    -- game world (not just group members) because it uses global RegisterEvent.
    -- When threat borders are disabled, unregister to avoid ~100s of wasted
    -- dispatches per second in raids with many adds.
    local partyInd = GetIndicatorSettings(false)
    local raidInd = GetIndicatorSettings(true)
    local partyThreat = partyInd and partyInd.showThreatBorder ~= false
    local raidThreat = raidInd and raidInd.showThreatBorder ~= false
    if partyThreat or raidThreat then
        eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    else
        eventFrame:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    end
end

---------------------------------------------------------------------------
-- PUBLIC: Expose dispel/defensive updates for the shared aura scan in
-- groupframes_auras.lua (avoids redundant GetUnitAuras calls)
---------------------------------------------------------------------------
function QUI_GF:UpdateDispelOverlay(frame)
    local update = _.UpdateDispelOverlay
    if update then update(frame) end
end

function QUI_GF:UpdateDefensiveIndicator(frame)
    local update = _.UpdateDefensiveIndicator
    if update then update(frame) end
end

function QUI_GF:RefreshHealth(frame)
    local update = _.UpdateHealth
    if update then update(frame) end
end

---------------------------------------------------------------------------
-- REFRESH ALL: Update all visible frames
---------------------------------------------------------------------------
function QUI_GF:RefreshAllFrames(reason)
    -- Pre-loop setup that each module's RefreshAll does once before iteration.
    -- Inlining per-frame work from auras + indicators avoids 2 extra full
    -- iterations of unitFrameMap (was 4 passes, now 1 + private auras).
    local GFA = ns.QUI_GroupFrameAuras
    if GFA and GFA.InvalidateLayout then GFA:InvalidateLayout() end
    local auraCacheAvailable = GFA and GFA.ScanUnitAuras and GFA.RenderFrame
    local GFI = ns.QUI_GroupFrameIndicators

    for unit, list in pairs(self.unitFrameMap) do
        local auraScanned = false
        for i = 1, #list do
            local frame = list[i]
            if frame and frame:IsShown() then
                if frame.healthBar then ApplyStatusBarTexture(frame.healthBar) end
                if frame.healPredictionBar then ApplyStatusBarTexture(frame.healPredictionBar) end
                if frame.powerBar then ApplyStatusBarTexture(frame.powerBar) end
                local auraCacheRender = auraCacheAvailable
                    and (not GFA.HasActiveConsumersForFrame or GFA:HasActiveConsumersForFrame(frame))
                if auraCacheRender and not auraScanned then
                    GFA.ScanUnitAuras(unit)
                    auraScanned = true
                end
                UpdateFrame(frame)

                -- Auras: render from the per-unit cache when available.
                if auraCacheAvailable then
                    GFA:RenderFrame(frame)
                elseif GFA and GFA.RefreshFrame then
                    GFA:RefreshFrame(frame)
                end
                -- Indicators: update tracked spells (was a separate full iteration)
                if GFI and GFI.RefreshFrame then GFI:RefreshFrame(frame) end
            end
        end
    end

    -- Private auras use a different clear-all + rebuild pattern for settings
    -- changes. Roster changes are handled by their lighter reanchor debounce.
    if reason ~= "roster"
        and ns.QUI_GroupFramePrivateAuras
        and ns.QUI_GroupFramePrivateAuras.RefreshAll
    then
        ns.QUI_GroupFramePrivateAuras:RefreshAll()
    end
end

---------------------------------------------------------------------------
-- REFRESH: Settings changed (called from options panel)
---------------------------------------------------------------------------
function QUI_GF:RefreshSettings()
    InvalidateCache()
    RefreshCachedEnabled()
    if _.ResetDispelColorCurve then _.ResetDispelColorCurve() end

    if not self.initialized then
        return
    end

    local db = GetSettings()
    if not db or not db.enabled then
        self:Disable()
        return
    end

    if InCombatLockdown() and not _state.inInitSafeWindow then
        _pending.refreshSettings = true
        return
    end

    -- Restore root frame positions from the (possibly new) profile DB.
    -- Prefer frameAnchoring positions; fall back to legacy db.position.
    -- Position the ROOT frames (not headers) — UpdateAnchorRoot handles
    -- internal header layout within each root.
    -- Skip repositioning when the anchoring override system owns the frame.
    local faDB = QUI.db and QUI.db.profile and QUI.db.profile.frameAnchoring
    local partyRoot = self.anchorFrames and self.anchorFrames.party
    if partyRoot and not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("partyFrames")) then
        local faParty = faDB and faDB.partyFrames
        partyRoot:ClearAllPoints()
        if faParty and faParty.point then
            partyRoot:SetPoint(faParty.point, UIParent, faParty.relative or faParty.point, faParty.offsetX or 0, faParty.offsetY or 0)
        else
            local position = db.position
            local offsetX = position and position.offsetX or -400
            local offsetY = position and position.offsetY or 0
            partyRoot:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        end
    end
    local raidRoot = self.anchorFrames and self.anchorFrames.raid
    if raidRoot and not (_G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("raidFrames")) then
        local faRaid = faDB and faDB.raidFrames
        raidRoot:ClearAllPoints()
        if faRaid and faRaid.point then
            raidRoot:SetPoint(faRaid.point, UIParent, faRaid.relative or faRaid.point, faRaid.offsetX or 0, faRaid.offsetY or 0)
        else
            local raidPos = db.raidPosition
            local raidOffX = raidPos and raidPos.offsetX or -400
            local raidOffY = raidPos and raidPos.offsetY or 0
            raidRoot:SetPoint("CENTER", UIParent, "CENTER", raidOffX, raidOffY)
        end
    end

    -- Re-configure headers
    if self.headers.party then ConfigurePartyHeader(self.headers.party) end
    if UseRaidSectionHeaders(db) then
        ConfigureRaidGroupHeaders()
    else
        if self.headers.raid then ConfigureRaidHeader(self.headers.raid) end
    end
    -- Self header uses party settings; re-apply self-first visibility
    if self.headers.self then
        local partySelfFirst = GetPartySelfFirst(db)
        self.headers.self:SetAttribute("showSolo", partySelfFirst and true or false)
    end

    -- Force re-decoration of all children
    for _, frame in pairs(self.allFrames) do
        frame._quiDecorated = false
        frame._lastBackdropColorR = nil
        frame._lastBackdropColorG = nil
        frame._lastBackdropColorB = nil
        frame._lastBackdropColorA = nil
        frame._lastHealthBarAlpha = nil
        frame._lastHealthColorR = nil
        frame._lastHealthColorG = nil
        frame._lastHealthColorB = nil
        frame._lastHealthColorA = nil
    end
    wipe(self.allFrames)

    -- Also clear decorated flag on header children directly
    local function ClearDecoratedFlags(header)
        if not header then return end
        local i = 1
        while true do
            local child = header:GetAttribute("child" .. i)
            if not child then break end
            child._quiDecorated = false
            child._lastBackdropColorR = nil
            child._lastBackdropColorG = nil
            child._lastBackdropColorB = nil
            child._lastBackdropColorA = nil
            child._lastHealthBarAlpha = nil
            child._lastHealthColorR = nil
            child._lastHealthColorG = nil
            child._lastHealthColorB = nil
            child._lastHealthColorA = nil
            i = i + 1
        end
    end
    for _, headerKey in ipairs({"party", "raid", "self"}) do
        ClearDecoratedFlags(self.headers[headerKey])
    end
    for _, header in ipairs(self.raidGroupHeaders) do
        ClearDecoratedFlags(header)
    end

    -- Update visibility + redecorate
    UpdateHeaderVisibility()
    UpdateFrameScaling(true)
    UpdateHeaderSizes()
    UpdateSelectiveEvents()
    RefreshClickCastFrames()

    -- Re-decoration above (UpdateFrameScaling -> DecorateGroupFrame) resets the
    -- absorb / heal-absorb / heal-prediction overlays to SetValue(0) + Hide
    -- without repopulating them. Because UNIT_HEALTH takes a health-only fast
    -- path, a STATIC overlay (one whose value isn't changing, so no dedicated
    -- UNIT_*_AMOUNT_CHANGED fires) would otherwise stay hidden until its next
    -- value change. Repopulate from current unit state so it reappears now.
    -- Combat-guarded: RefreshAllFrames runs PrivateAuras:RefreshAll (which the
    -- in-combat roster path deliberately skips via reason == "roster"), and we
    -- can reach here in combat through the init-safe window above.
    if not InCombatLockdown() then
        self:RefreshAllFrames()
    end
end

---------------------------------------------------------------------------
-- HUD LAYERING

function QUI_GF:Initialize()
    local db = GetSettings()
    if not db or not db.enabled then return end

    -- ADDON_LOADED safe window: protected calls are allowed even though
    -- InCombatLockdown() returns true during a combat /reload.
    _state.inInitSafeWindow = true
    _state.initialLayoutDone = false

    -- Create headers
    CreateHeaders()

    -- Create spotlight header (if enabled)
    CreateSpotlightHeader()

    -- Register events
    RegisterEvents()

    -- Apply HUD layering
    ApplyHUDLayering()

    -- Show appropriate header based on group status
    UpdateHeaderVisibility()
    UpdateFrameScaling(true)

    -- Resolve range check spells and start ticker
    ResolveRangeSpells()
    StartRangeCheck()

    self.initialized = true
    RefreshCachedEnabled()

    -- Group frames were pre-created before click-casting was initialized,
    -- so they need one registration pass after headers exist.
    RefreshClickCastFrames()

    -- Hide Blizzard group frames
    if ns.QUI_GroupFrameBlizzard and ns.QUI_GroupFrameBlizzard.HideBlizzardFrames then
        ns.QUI_GroupFrameBlizzard:HideBlizzardFrames()
    end

    _state.inInitSafeWindow = false
end

---------------------------------------------------------------------------
-- DISABLE
---------------------------------------------------------------------------
function QUI_GF:Disable()
    _state.cachedModuleEnabled = false
    _state.cachedModuleDB = nil
    UnregisterEvents()
    StopRangeCheck()

    if InCombatLockdown() then return end

    for _, headerKey in ipairs({"party", "raid", "self"}) do
        local header = self.headers[headerKey]
        if header then
            header:Hide()
        end
    end
    for _, header in ipairs(self.raidGroupHeaders) do
        if header then header:Hide() end
    end

    for _, proxy in pairs(self.anchorFrames) do
        proxy:Hide()
    end

    if self.spotlightHeader then self.spotlightHeader:Hide() end
    if self.spotlightContainer then self.spotlightContainer:Hide() end

    if ns.QUI_GroupFramePrivateAuras and ns.QUI_GroupFramePrivateAuras.CleanupAll then
        ns.QUI_GroupFramePrivateAuras:CleanupAll()
    end

    wipe(self.unitFrameMap)
    self.initialized = false

    -- Restore Blizzard frames
    if ns.QUI_GroupFrameBlizzard and ns.QUI_GroupFrameBlizzard.RestoreBlizzardFrames then
        ns.QUI_GroupFrameBlizzard:RestoreBlizzardFrames()
    end
end

---------------------------------------------------------------------------
-- STARTUP: Init on ADDON_LOADED
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        QUI_GF:Initialize()
    end
end)

---------------------------------------------------------------------------
-- PUBLIC API (for other modules)
---------------------------------------------------------------------------

_.RebuildUnitFrameMap = RebuildUnitFrameMap
_.ResolveRangeSpells = ResolveRangeSpells
_.CheckUnitRange = CheckUnitRange
_.ApplyRangeAlpha = ApplyRangeAlpha
_.StartRangeCheck = StartRangeCheck
_.StopRangeCheck = StopRangeCheck
_.RefreshCachedEnabled = RefreshCachedEnabled
_.UpdateSelectiveEvents = UpdateSelectiveEvents
