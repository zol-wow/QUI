-- QUI_Reminders/reminders/bossmods.lua -- one bus over the boss-timer sources.
--
-- BigWigs, DBM and Blizzard's own encounter timeline each say "ability X lands
-- in N seconds" in their own shape. This file listens to whichever of them are
-- present and republishes one normalized event, so no consumer ever touches a
-- boss mod API directly. Only one source is ACTIVE at a time (the user's pick,
-- or the first one found in SOURCE_ORDER), which is what keeps a dual-mod setup
-- from firing the same ability twice.
--
-- Secret values are rejected at this boundary: a spell id, duration or bar id
-- that is secret is dropped before a subscriber sees it, so consumers can rely
-- on every field being a plain Lua value. Blizzard's encounter timeline is the
-- deliberate exception -- its Encounter-source events carry a secret spell id
-- by design, so those go out with `spellID = nil` and `secretIdentity = true`
-- and the consumer decides what to do with an anonymous countdown.
--
-- Event shapes (all fields readable):
--   onTimer     { source, spellID?, key, text?, duration, maxDuration?, icon?,
--                 barID, approximate?, eventID?, secretIdentity? }
--   onTimerStop { source, barID, reason }   reason: "stop" (explicit), "pause",
--                                            "finished" (ran to its end)
--   onMessage   { source, spellID?, key, text?, icon?, emphasized? }
--   onStage     { source, stage }
--   onReset     { source, reason }
local _, ns = ...

local Helpers = ns.Helpers

local BossMods = {}
ns.BossMods = BossMods

local SOURCE_ORDER = { "bigwigs", "dbm", "timeline" }
BossMods.SOURCE_ORDER = SOURCE_ORDER

local subscribers = {}
local preferred = "auto"
local hooked = {}
local watchFrame

local function IsSecret(value)
    if Helpers and Helpers.IsSecretValue then return Helpers.IsSecretValue(value) end
    local probe = _G.issecretvalue
    return probe ~= nil and probe(value) == true
end

-- @secret-policy: reject-secret-value -- the bus publishes readable values only.
local function Readable(value)
    if IsSecret(value) then return nil end
    return value
end

local function ReadableNumber(value)
    value = Readable(value)
    if type(value) == "number" then return value end
    return nil
end

local function ReadableString(value)
    value = Readable(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-------------------------------------------------------------------------------
-- Availability and source selection
-------------------------------------------------------------------------------
function BossMods.IsAvailable(source)
    if source == "bigwigs" then
        local loader = _G.BigWigsLoader
        return type(loader) == "table" and type(loader.RegisterMessage) == "function"
    elseif source == "dbm" then
        local dbm = _G.DBM
        return type(dbm) == "table" and type(dbm.RegisterCallback) == "function"
    elseif source == "timeline" then
        local tl = _G.C_EncounterTimeline
        if not (type(tl) == "table" and type(tl.IsFeatureAvailable) == "function") then return false end
        local ok, available = ns.SafeCall("best-effort-style", tl.IsFeatureAvailable)
        return ok and available == true
    end
    return false
end

function BossMods.SetPreferredSource(source)
    if source == "bigwigs" or source == "dbm" or source == "timeline" then
        preferred = source
    else
        preferred = "auto"
    end
end

function BossMods.GetPreferredSource()
    return preferred
end

-- The one source whose events reach subscribers right now, or nil.
function BossMods.ActiveSource()
    if preferred ~= "auto" then
        if BossMods.IsAvailable(preferred) then return preferred end
        return nil
    end
    for i = 1, #SOURCE_ORDER do
        if BossMods.IsAvailable(SOURCE_ORDER[i]) then return SOURCE_ORDER[i] end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Subscribers
-------------------------------------------------------------------------------
local function Emit(kind, evt)
    if evt.source ~= BossMods.ActiveSource() then return end
    for _, handlers in pairs(subscribers) do
        local fn = handlers[kind]
        if type(fn) == "function" then
            ns.SafeCall("bulkhead", fn, evt)
        end
    end
end
BossMods._Emit = Emit

function BossMods.Subscribe(key, handlers)
    if type(key) ~= "string" or type(handlers) ~= "table" then return false end
    subscribers[key] = handlers
    BossMods.EnsureHooks()
    return true
end

function BossMods.Unsubscribe(key)
    subscribers[key] = nil
end

function BossMods.HasSubscribers()
    return next(subscribers) ~= nil
end

-------------------------------------------------------------------------------
-- BigWigs
--
-- BigWigs_Timer is preferred over BigWigs_StartBar: the bar message is skipped
-- when the player has turned bars off for that key, the timer message is not.
-- Handler shape: BigWigsLoader dispatches as fn(event, module, ...).
-------------------------------------------------------------------------------
local BW = {}
BossMods.BigWigsHandlers = BW

function BW.BigWigs_Timer(_, _, key, time, maxTime, msg, _, icon, isApprox)
    local duration = ReadableNumber(time)
    if not duration then return end
    local text = ReadableString(msg)
    local readableKey = Readable(key)
    Emit("onTimer", {
        source = "bigwigs",
        spellID = ReadableNumber(key),
        key = readableKey,
        text = text,
        duration = duration,
        maxDuration = ReadableNumber(maxTime),
        icon = Readable(icon),
        barID = "bigwigs:" .. tostring(text or readableKey),
        approximate = isApprox == true,
    })
end

function BW.BigWigs_StopBar(_, _, text)
    local readable = ReadableString(text)
    if not readable then return end
    Emit("onTimerStop", { source = "bigwigs", barID = "bigwigs:" .. readable, reason = "stop" })
end
function BW.BigWigs_PauseBar(_, _, text)
    local readable = ReadableString(text)
    if not readable then return end
    Emit("onTimerStop", { source = "bigwigs", barID = "bigwigs:" .. readable, reason = "pause" })
end

function BW.BigWigs_Message(_, _, key, text, _, icon, isEmphasized)
    Emit("onMessage", {
        source = "bigwigs",
        spellID = ReadableNumber(key),
        key = Readable(key),
        text = ReadableString(text),
        icon = Readable(icon),
        emphasized = isEmphasized == true,
    })
end

function BW.BigWigs_SetStage(_, _, stage)
    local n = ReadableNumber(stage)
    if not n then return end
    Emit("onStage", { source = "bigwigs", stage = n })
end

local function BW_Reset(event)
    Emit("onReset", { source = "bigwigs", reason = tostring(event) })
end
BW.BigWigs_StopBars = BW_Reset
BW.BigWigs_OnBossDisable = BW_Reset
BW.BigWigs_OnBossWipe = BW_Reset
BW.BigWigs_OnBossWin = BW_Reset

local function HookBigWigs()
    if hooked.bigwigs or not BossMods.IsAvailable("bigwigs") then return hooked.bigwigs end
    local loader = _G.BigWigsLoader
    local ok = true
    for message, fn in pairs(BW) do
        local success = ns.SafeCall("compat", loader.RegisterMessage, BossMods, message, fn)
        ok = ok and success
    end
    hooked.bigwigs = ok
    return ok
end

-------------------------------------------------------------------------------
-- DBM
--
-- DBM dispatches callbacks as fn(event, ...). Timer identity for stop/pause is
-- the timer id DBM hands back, not the bar text.
-------------------------------------------------------------------------------
local DB = {}
BossMods.DBMHandlers = DB

function DB.DBM_TimerStart(_, id, msg, timer, icon, timerType, spellId)
    local duration = ReadableNumber(timer)
    local barID = Readable(id)
    if not duration or barID == nil then return end
    Emit("onTimer", {
        source = "dbm",
        spellID = ReadableNumber(spellId),
        key = Readable(spellId) or barID,
        text = ReadableString(msg),
        duration = duration,
        icon = Readable(icon),
        barID = "dbm:" .. tostring(barID),
        timerType = Readable(timerType),
    })
end
DB.DBM_TimerBegin = DB.DBM_TimerStart

function DB.DBM_TimerStop(_, id)
    local barID = Readable(id)
    if barID == nil then return end
    Emit("onTimerStop", { source = "dbm", barID = "dbm:" .. tostring(barID), reason = "stop" })
end
function DB.DBM_TimerPause(_, id)
    local barID = Readable(id)
    if barID == nil then return end
    Emit("onTimerStop", { source = "dbm", barID = "dbm:" .. tostring(barID), reason = "pause" })
end

function DB.DBM_Announce(_, message, icon, announceType, spellId)
    Emit("onMessage", {
        source = "dbm",
        spellID = ReadableNumber(spellId),
        key = Readable(spellId),
        text = ReadableString(message),
        icon = Readable(icon),
        announceType = Readable(announceType),
    })
end

function DB.DBM_SetStage(_, _, _, stage)
    local n = ReadableNumber(stage)
    if not n then return end
    Emit("onStage", { source = "dbm", stage = n })
end

local function DBM_Reset(event)
    Emit("onReset", { source = "dbm", reason = tostring(event) })
end
DB.DBM_Wipe = DBM_Reset
DB.DBM_Kill = DBM_Reset

local function HookDBM()
    if hooked.dbm or not BossMods.IsAvailable("dbm") then return hooked.dbm end
    local dbm = _G.DBM
    local ok = true
    for event, fn in pairs(DB) do
        local success = ns.SafeCall("compat", dbm.RegisterCallback, dbm, event, fn)
        ok = ok and success
    end
    hooked.dbm = ok
    return ok
end

-------------------------------------------------------------------------------
-- Blizzard encounter timeline
--
-- Only `id`, `source` and `duration` on an Encounter-source event are readable;
-- the spell identity is secret by design and is published as such.
-------------------------------------------------------------------------------
local TL = {}
BossMods.TimelineHandlers = TL

local function TimelineBarID(eventID)
    return "timeline:" .. tostring(eventID)
end

-- Removal follows a terminal state; remember which events ran to completion so
-- their removal is reported as "finished" rather than as a cancellation.
local finishedEvents = {}

local function EmitTimelineTimer(eventID, info, duration)
    local spellID = ReadableNumber(info and info.spellID)
    local sourceType = ReadableNumber(info and info.source)
    Emit("onTimer", {
        source = "timeline",
        spellID = spellID,
        key = spellID or eventID,
        text = ReadableString(info and info.spellName),
        duration = duration,
        icon = Readable(info and info.iconFileID),
        barID = TimelineBarID(eventID),
        eventID = eventID,
        secretIdentity = spellID == nil,
        timelineSource = sourceType,
    })
end

function TL.ENCOUNTER_TIMELINE_EVENT_ADDED(info)
    if type(info) ~= "table" then return end
    local eventID = Readable(info.id)
    local duration = ReadableNumber(info.duration)
    if eventID == nil or not duration then return end
    EmitTimelineTimer(eventID, info, duration)
end

function TL.ENCOUNTER_TIMELINE_EVENT_REMOVED(eventID)
    eventID = Readable(eventID)
    if eventID == nil then return end
    local reason = finishedEvents[eventID] and "finished" or "stop"
    finishedEvents[eventID] = nil
    Emit("onTimerStop", { source = "timeline", barID = TimelineBarID(eventID), reason = reason })
end

function TL.ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED(eventID)
    eventID = Readable(eventID)
    if eventID == nil then return end
    local tl = _G.C_EncounterTimeline
    local states = _G.Enum and _G.Enum.EncounterTimelineEventState
    if not (tl and tl.GetEventState and states) then return end
    local ok, state = ns.SafeCall("secret-probe", tl.GetEventState, eventID)
    if not ok then return end
    state = Readable(state)
    if state == states.Active then
        -- Resumed after a pause: re-arm with what is left of the countdown.
        local okInfo, info = false, nil
        if type(tl.GetEventInfo) == "function" then
            okInfo, info = ns.SafeCall("secret-probe", tl.GetEventInfo, eventID)
        end
        local remaining
        if type(tl.GetEventTimeRemaining) == "function" then
            local okRem, value = ns.SafeCall("secret-probe", tl.GetEventTimeRemaining, eventID)
            remaining = okRem and ReadableNumber(value) or nil
        end
        if remaining then
            EmitTimelineTimer(eventID, okInfo and info or nil, remaining)
        end
    elseif state == states.Finished then
        finishedEvents[eventID] = true
        Emit("onTimerStop", { source = "timeline", barID = TimelineBarID(eventID), reason = "finished" })
    elseif state == states.Paused then
        Emit("onTimerStop", { source = "timeline", barID = TimelineBarID(eventID), reason = "pause" })
    elseif state == states.Canceled then
        finishedEvents[eventID] = nil
        Emit("onTimerStop", { source = "timeline", barID = TimelineBarID(eventID), reason = "stop" })
    end
end

local timelineFrame
local function HookTimeline()
    if hooked.timeline then return true end
    if type(_G.C_EncounterTimeline) ~= "table" or type(CreateFrame) ~= "function" then return false end
    timelineFrame = CreateFrame("Frame")
    for event in pairs(TL) do
        ns.SafeCall("compat", timelineFrame.RegisterEvent, timelineFrame, event)
    end
    timelineFrame:SetScript("OnEvent", function(_, event, ...)
        local fn = TL[event]
        if fn then fn(...) end
    end)
    hooked.timeline = true
    return true
end

-------------------------------------------------------------------------------
-- Hook installation, with a late-load watch for boss mods that load after us
-------------------------------------------------------------------------------
local function AllHooked()
    return hooked.bigwigs and hooked.dbm
end

function BossMods.EnsureHooks()
    HookBigWigs()
    HookDBM()
    HookTimeline()
    if AllHooked() or watchFrame or type(CreateFrame) ~= "function" then return end
    watchFrame = CreateFrame("Frame")
    watchFrame:RegisterEvent("ADDON_LOADED")
    watchFrame:SetScript("OnEvent", function(self)
        HookBigWigs()
        HookDBM()
        if AllHooked() then self:UnregisterEvent("ADDON_LOADED") end
    end)
end

function BossMods.IsHooked(source)
    return hooked[source] == true
end

-- Settings-page summary: which sources exist on this client.
function BossMods.DescribeSources()
    local out = {}
    for i = 1, #SOURCE_ORDER do
        local s = SOURCE_ORDER[i]
        out[i] = { source = s, available = BossMods.IsAvailable(s) }
    end
    return out
end
