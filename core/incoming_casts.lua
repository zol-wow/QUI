local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local CreateFrame = CreateFrame
local C_NamePlate = C_NamePlate
local GetTime = GetTime
local UnitCanAttack = UnitCanAttack
local UnitCastingDuration = UnitCastingDuration
local UnitCastingInfo = UnitCastingInfo
local UnitChannelDuration = UnitChannelDuration
local UnitChannelInfo = UnitChannelInfo
local UnitShouldDisplaySpellTargetName = UnitShouldDisplaySpellTargetName
local next = next
local pairs = pairs
local type = type
local wipe = wipe

local IsSecretValue = Helpers.IsSecretValue
local SafeCall = ns.SafeCall

-- Shared engine that watches enemy nameplate casters and routes each cast to
-- subscribers interested in who the cast is aimed at (the player, a group
-- member, ...). Casters are nameplate-only: an enemy without a visible
-- nameplate cannot be tracked, so coverage depends on nameplate CVars.
--
-- IncomingCasts.Subscribe(key, {
--     -- target-resolving mode: name the unit a cast is aimed at
--     resolveTarget = function(caster) ... end,
--     -- OR all-casts mode: every hostile cast is delivered and the
--     -- subscriber decides visibility itself (e.g. a SetAlphaFromBoolean
--     -- sink — UnitIsUnit verdicts on caster targets are secret in
--     -- instances, so Lua-side target decisions are impossible there)
--     allCasts = true,
--     onShow = function(caster, targetUnit, cast) ... end,  -- targetUnit nil in all-casts mode
--     onUpdate = function(caster, cast) ... end,            -- optional: re-resolve of a shown cast (target changes)
--     onHide = function(caster) ... end,
-- })
--
-- resolveTarget returns a unit token when the cast targets a unit the
-- subscriber cares about, false when it definitely does not, and nil when the
-- target cannot be read (secret values) — nil keeps the previous verdict.
-- cast fields (texture, spellName, startMS, endMS, durationObj) may be secret
-- values; forward them only into secret-safe sinks. The cast table is reused
-- per caster token across resolves — holding it until onHide is fine (fields
-- refresh in place), retaining it past onHide is not.
local IncomingCasts = {}
ns.IncomingCasts = IncomingCasts

-- Compound tokens like "nameplate3target" are not populated at the instant
-- *_START fires; casts shorter than firstRead are dropped by design.
local TIMING = {
    firstRead = 0.10,
    verifyRead = 0.15,
    targetChangeRead = 0.05,
}

local MAX_NAMEPLATE_CASTERS = 150

local subscribers = {}
local shownTargets = {}
local plateUnits = {}
local watchedCaster = {}
local serialByCaster = {}
local castRecords = {}
local clearQueue = {}
local resolveFirstAt = {}
local resolveSecondAt = {}
local resolveSerial = {}
local pendingResolveCount = 0
local running = false

local function NewCastRecord()
    return {
        spellName = false,
        texture = false,
        isChannel = false,
        startMS = false,
        endMS = false,
        durationObj = false,
        evidence = false,
    }
end

for i = 1, MAX_NAMEPLATE_CASTERS do
    local caster = "nameplate" .. i
    plateUnits[caster] = false
    watchedCaster[caster] = false
    serialByCaster[caster] = 0
    castRecords[caster] = NewCastRecord()
    resolveFirstAt[caster] = false
    resolveSecondAt[caster] = false
    resolveSerial[caster] = false
end

local eventFrame = CreateFrame("Frame")

-- Debug instrumentation: counters are always on (cheap), verbose logging is
-- opt-in via /quiic log. Never feed potentially-secret values (spell names,
-- textures, durations) into these — unit tokens and our own strings only.
local debugLog = false
local stats = {
    events = {},
    eventsUntracked = 0,
    platesSeen = 0,
    watchBegun = 0,
    gatedHostile = 0,
    resolveStale = 0,
    resolveUnwatched = 0,
    resolveNoCast = 0,
    resolveNotDisplayable = 0,
    resolved = 0,
}
local subscriberStats = {}

local function SubStats(key)
    local s = subscriberStats[key]
    if not s then
        s = { hit = 0, miss = 0, unreadable = 0, shows = 0, hides = 0 }
        subscriberStats[key] = s
    end
    return s
end

-- Varargs are concatenated only when logging is on, so disabled-path calls
-- cost no string garbage; pass pieces, not pre-concatenated messages.
local function DebugPrint(...)
    if not debugLog then
        return
    end
    print("|cff34D399[QUI-IC]|r " .. table.concat({ ... }))
end

local function NextSerial(caster)
    local serial = (serialByCaster[caster] or 0) + 1
    serialByCaster[caster] = serial
    return serial
end

local function ReadCast(caster)
    local ok, spellName, _, texture, startMS, endMS = SafeCall("best-effort-style", UnitCastingInfo, caster)
    if ok then
        if IsSecretValue(spellName) then
            return spellName, texture, false, nil, nil, "secret"
        end
        if spellName ~= nil then
            if IsSecretValue(startMS) or IsSecretValue(endMS) then
                return spellName, texture, false, nil, nil, "secret"
            end
            return spellName, texture, false, startMS, endMS, "plain"
        end
    end

    ok, spellName, _, texture, startMS, endMS = SafeCall("best-effort-style", UnitChannelInfo, caster)
    if ok then
        if IsSecretValue(spellName) then
            return spellName, texture, true, nil, nil, "secret"
        end
        if spellName ~= nil then
            if IsSecretValue(startMS) or IsSecretValue(endMS) then
                return spellName, texture, true, nil, nil, "secret"
            end
            return spellName, texture, true, startMS, endMS, "plain"
        end
    end

    return nil
end

local function ReadDuration(caster, isChannel)
    local reader = isChannel and UnitChannelDuration or UnitCastingDuration
    if not reader then
        return nil
    end
    local ok, durationObject = SafeCall("best-effort-style", reader, caster)
    if ok then
        return durationObject
    end
    return nil
end

local function SpellTargetIsDisplayable(caster)
    if not UnitShouldDisplaySpellTargetName then
        return true
    end

    local ok, display = SafeCall("best-effort-style", UnitShouldDisplaySpellTargetName, caster)
    if ok and not IsSecretValue(display) and display == false then
        return false
    end
    return true
end

local function NotifyHide(caster)
    for key, subscriber in pairs(subscribers) do
        local shown = shownTargets[key]
        if shown and shown[caster] then
            shown[caster] = false
            SubStats(key).hides = SubStats(key).hides + 1
            DebugPrint("hide ", caster, " [", key, "]")
            subscriber.onHide(caster)
        end
    end
end

local function CancelResolve(caster)
    if resolveSerial[caster] then
        pendingResolveCount = pendingResolveCount - 1
    end
    resolveFirstAt[caster] = false
    resolveSecondAt[caster] = false
    resolveSerial[caster] = false
    if pendingResolveCount == 0 then
        eventFrame:SetScript("OnUpdate", nil)
    end
end

local function ClearCaster(caster)
    CancelResolve(caster)
    NextSerial(caster)
    watchedCaster[caster] = false
    NotifyHide(caster)
end

local function ClearAllCasts()
    wipe(clearQueue)
    for caster, watched in pairs(watchedCaster) do
        if watched then
            clearQueue[#clearQueue + 1] = caster
        end
    end
    for key in pairs(shownTargets) do
        for caster, shown in pairs(shownTargets[key]) do
            if shown then
                clearQueue[#clearQueue + 1] = caster
            end
        end
    end

    for i = 1, #clearQueue do
        ClearCaster(clearQueue[i])
    end
    wipe(clearQueue)
    pendingResolveCount = 0
    eventFrame:SetScript("OnUpdate", nil)
end

local function ResolveCaster(caster, expectedSerial)
    if serialByCaster[caster] ~= expectedSerial then
        stats.resolveStale = stats.resolveStale + 1
        return
    end
    if not watchedCaster[caster] then
        stats.resolveUnwatched = stats.resolveUnwatched + 1
        return
    end

    local spellName, texture, isChannel, startMS, endMS, evidence = ReadCast(caster)
    if evidence == nil then
        stats.resolveNoCast = stats.resolveNoCast + 1
        DebugPrint("resolve ", caster, " -> no readable cast")
        return
    end

    local durationObject
    if evidence == "secret" then
        durationObject = ReadDuration(caster, false)
        if IsSecretValue(durationObject) then
        elseif durationObject == nil then
            durationObject = ReadDuration(caster, true)
        end
    else
        durationObject = ReadDuration(caster, isChannel)
    end

    stats.resolved = stats.resolved + 1

    -- Reused per caster token (bounded by the nameplate token space) so the
    -- two-read verify pass and target-change rechecks allocate nothing.
    local cast = castRecords[caster]
    if not cast then
        cast = NewCastRecord()
        castRecords[caster] = cast
    end
    cast.spellName = spellName
    cast.texture = texture
    cast.isChannel = isChannel and true or false
    cast.startMS = startMS
    cast.endMS = endMS
    cast.durationObj = durationObject
    cast.evidence = evidence

    local displayable
    for key, subscriber in pairs(subscribers) do
        local shown = shownTargets[key]
        local subStats = SubStats(key)

        if subscriber.allCasts then
            if not shown[caster] then
                shown[caster] = true
                subStats.shows = subStats.shows + 1
                DebugPrint("show ", caster, " [", evidence, "] ", key)
                subscriber.onShow(caster, nil, cast)
            elseif subscriber.onUpdate then
                DebugPrint("update ", caster, " [", key, "]")
                subscriber.onUpdate(caster, cast)
            end
        else
            -- The target-name displayability gate only applies to subscribers
            -- that read caster-target attributes to resolve a unit.
            if displayable == nil then
                displayable = SpellTargetIsDisplayable(caster)
            end
            if not displayable then
                stats.resolveNotDisplayable = stats.resolveNotDisplayable + 1
                DebugPrint("resolve ", caster, " [", key, "] -> target not displayable")
            else
                local target = subscriber.resolveTarget(caster)
                if target then
                    subStats.hit = subStats.hit + 1
                    DebugPrint("resolve ", caster, " [", evidence, "] ", key, " -> ", target)
                    if shown[caster] ~= target then
                        if shown[caster] then
                            shown[caster] = false
                            subStats.hides = subStats.hides + 1
                            subscriber.onHide(caster)
                        end
                        shown[caster] = target
                        subStats.shows = subStats.shows + 1
                        subscriber.onShow(caster, target, cast)
                    end
                elseif target == false then
                    subStats.miss = subStats.miss + 1
                    DebugPrint("resolve ", caster, " [", evidence, "] ", key, " -> not-my-target")
                    if shown[caster] then
                        shown[caster] = false
                        subStats.hides = subStats.hides + 1
                        subscriber.onHide(caster)
                    end
                else
                    subStats.unreadable = subStats.unreadable + 1
                    DebugPrint("resolve ", caster, " [", evidence, "] ", key, " -> unreadable")
                end
            end
        end
    end
end

local function ProcessResolveQueue()
    local now = GetTime()
    for caster, serial in pairs(resolveSerial) do
        if serial then
            local firstAt = resolveFirstAt[caster]
            if firstAt and now >= firstAt then
                resolveFirstAt[caster] = false
                ResolveCaster(caster, serial)
            end

            local secondAt = resolveSecondAt[caster]
            if resolveSerial[caster] == serial and secondAt and now >= secondAt then
                resolveSecondAt[caster] = false
                resolveSerial[caster] = false
                pendingResolveCount = pendingResolveCount - 1
                ResolveCaster(caster, serial)
            end
        end
    end
    if pendingResolveCount == 0 then
        eventFrame:SetScript("OnUpdate", nil)
    end
end

local function QueueResolves(caster, serial, firstDelay)
    local now = GetTime()
    if not resolveSerial[caster] then
        pendingResolveCount = pendingResolveCount + 1
    end
    resolveSerial[caster] = serial
    resolveFirstAt[caster] = now + firstDelay
    resolveSecondAt[caster] = now + firstDelay + TIMING.verifyRead
    eventFrame:SetScript("OnUpdate", ProcessResolveQueue)
end

local function BeginCastWatch(caster)
    ClearCaster(caster)

    local ok, hostile = SafeCall("best-effort-style", UnitCanAttack, "player", caster)
    if ok and not IsSecretValue(hostile) and hostile ~= true then
        stats.gatedHostile = stats.gatedHostile + 1
        DebugPrint("watch ", caster, " -> skipped (not hostile)")
        return
    end

    stats.watchBegun = stats.watchBegun + 1
    DebugPrint("watch ", caster)
    watchedCaster[caster] = true
    local serial = serialByCaster[caster] or 0
    QueueResolves(caster, serial, TIMING.firstRead)
end

local function RecheckCasterTarget(caster)
    if not watchedCaster[caster] then
        return
    end

    local serial = NextSerial(caster)
    QueueResolves(caster, serial, TIMING.targetChangeRead)
end

local function AdoptLiveCast(unit)
    local _, _, _, _, _, evidence = ReadCast(unit)
    if evidence == "plain" then
        BeginCastWatch(unit)
    end
end

local function SeedVisibleNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end

    local ok, plates = SafeCall("best-effort-style", C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then
        return
    end

    for i = 1, #plates do
        local unit = plates[i] and plates[i].namePlateUnitToken
        if unit and not plateUnits[unit] then
            plateUnits[unit] = true
            AdoptLiveCast(unit)
        end
    end
end

local function ResetPlateUnits()
    for unit in pairs(plateUnits) do
        plateUnits[unit] = false
    end
end

-- Empowered casts have their own lifecycle events (no *_START/*_STOP), and
-- failed casts do not always emit STOP — both must be tracked or empowered
-- casts go unseen and failed ones leave stale icons.
local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}

local FINISH_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
}

local WATCHED_EVENTS = {
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "UNIT_TARGET",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
}

local function SetRunning(enabled)
    if enabled == running then
        return
    end
    running = enabled

    for i = 1, #WATCHED_EVENTS do
        if enabled then
            eventFrame:RegisterEvent(WATCHED_EVENTS[i])
        else
            eventFrame:UnregisterEvent(WATCHED_EVENTS[i])
        end
    end

    DebugPrint(enabled and "engine started" or "engine stopped")
    if enabled then
        SeedVisibleNameplates()
    else
        ClearAllCasts()
        ResetPlateUnits()
    end
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        ClearAllCasts()
        ResetPlateUnits()
        SeedVisibleNameplates()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        ClearAllCasts()
        ResetPlateUnits()
        SeedVisibleNameplates()
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        plateUnits[unit] = true
        stats.platesSeen = stats.platesSeen + 1
        DebugPrint("plate added ", unit)
        AdoptLiveCast(unit)
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        plateUnits[unit] = false
        DebugPrint("plate removed ", unit)
        ClearCaster(unit)
        return
    end

    if not plateUnits[unit] then
        stats.eventsUntracked = stats.eventsUntracked + 1
        return
    end

    stats.events[event] = (stats.events[event] or 0) + 1
    DebugPrint(event, " ", unit)

    if START_EVENTS[event] then
        BeginCastWatch(unit)
    elseif FINISH_EVENTS[event] then
        ClearCaster(unit)
    elseif event == "UNIT_TARGET" then
        RecheckCasterTarget(unit)
    end
end)

function IncomingCasts.Subscribe(key, subscriber)
    if type(key) ~= "string"
        or type(subscriber) ~= "table"
        or type(subscriber.onShow) ~= "function"
        or type(subscriber.onHide) ~= "function" then
        return false
    end
    if not subscriber.allCasts and type(subscriber.resolveTarget) ~= "function" then
        return false
    end

    subscribers[key] = subscriber
    local shown = shownTargets[key]
    if not shown then
        shown = {}
        shownTargets[key] = shown
        for i = 1, MAX_NAMEPLATE_CASTERS do
            shown["nameplate" .. i] = false
        end
    end
    SubStats(key)
    SetRunning(true)
    return true
end

-- Wipe a subscriber's shown-state and re-evaluate every in-flight cast so the
-- subscriber can re-show markers after clearing its own widgets (roster
-- change, subscribing while the engine is already running). Other subscribers
-- are unaffected: their shown maps keep deduping repeat resolves.
function IncomingCasts.ResetSubscriber(key)
    local shown = shownTargets[key]
    if not shown then
        return
    end
    for caster in pairs(shown) do
        shown[caster] = false
    end
    for caster, watched in pairs(watchedCaster) do
        if watched then
            RecheckCasterTarget(caster)
        end
    end
end

function IncomingCasts.Unsubscribe(key)
    subscribers[key] = nil
    shownTargets[key] = nil
    if not next(subscribers) then
        SetRunning(false)
    end
end

function IncomingCasts.IsRunning()
    return running
end

function IncomingCasts.ToggleDebugLog()
    debugLog = not debugLog
    return debugLog
end

function IncomingCasts.DebugDump(out)
    out = out or print
    local prefix = "|cff34D399[QUI-IC]|r "

    out(prefix .. "engine running: " .. tostring(running) .. "  verbose log: " .. tostring(debugLog))

    local plates = {}
    for unit, tracked in pairs(plateUnits) do
        if tracked then
            plates[#plates + 1] = unit
        end
    end
    local watched = {}
    for caster, active in pairs(watchedCaster) do
        if active then
            watched[#watched + 1] = caster
        end
    end
    out(prefix .. "plates tracked: " .. #plates .. " (" .. table.concat(plates, " ") .. ")  seen total: " .. stats.platesSeen)
    if running and #plates == 0 then
        out(prefix .. "  ^ no nameplates tracked — enemy nameplates must be visible for casts to be detected")
    end
    out(prefix .. "watched casters: " .. #watched .. " (" .. table.concat(watched, " ") .. ")")

    local eventBits = {}
    for event, count in pairs(stats.events) do
        eventBits[#eventBits + 1] = event .. "=" .. count
    end
    out(prefix .. "plate events: " .. (#eventBits > 0 and table.concat(eventBits, " ") or "none")
        .. "  untracked-unit events: " .. stats.eventsUntracked)
    out(prefix .. "watch: begun=" .. stats.watchBegun
        .. " gatedHostile=" .. stats.gatedHostile)
    out(prefix .. "resolve: evaluated=" .. stats.resolved
        .. " noCast=" .. stats.resolveNoCast
        .. " notDisplayable=" .. stats.resolveNotDisplayable
        .. " stale=" .. stats.resolveStale
        .. " unwatched=" .. stats.resolveUnwatched)

    local any = false
    for key, s in pairs(subscriberStats) do
        any = true
        local shownCount = 0
        local shown = shownTargets[key]
        if shown then
            for _, target in pairs(shown) do
                if target then
                    shownCount = shownCount + 1
                end
            end
        end
        out(prefix .. "subscriber " .. key .. (subscribers[key] and "" or " (inactive)")
            .. ": hit=" .. s.hit .. " miss=" .. s.miss .. " unreadable=" .. s.unreadable
            .. " shows=" .. s.shows .. " hides=" .. s.hides .. " showing=" .. shownCount)
    end
    if not any then
        out(prefix .. "no subscribers have been active")
    end
end
