-- QUI_Logger/recorder.lua
-- Dev-only event recorder. Pure funcs are unit-tested; live wiring runs
-- only when WoW globals exist (guarded), so this file loads under plain lua.
-- luacheck: globals QUI_LoggerDB SLASH_QLOG1
local addonName, ns = ...

local DEFAULT_LIMITS = {
    maxSessions = 3,
    maxEventsPerSession = 2000,
    maxBufferedEvents = 200,
    maxArgs = 12,
    maxStringLength = 240,
    maxTableEntries = 12,
}

local function positiveLimit(value, defaultValue)
    value = tonumber(value)
    if value and value > 0 then return value end
    return defaultValue
end

function ns.GetLimits(opts)
    local source = opts or ns.loggerLimits or {}
    return {
        maxSessions = positiveLimit(source.maxSessions, DEFAULT_LIMITS.maxSessions),
        maxEventsPerSession = positiveLimit(source.maxEventsPerSession, DEFAULT_LIMITS.maxEventsPerSession),
        maxBufferedEvents = positiveLimit(source.maxBufferedEvents, DEFAULT_LIMITS.maxBufferedEvents),
        maxArgs = positiveLimit(source.maxArgs, DEFAULT_LIMITS.maxArgs),
        maxStringLength = positiveLimit(source.maxStringLength, DEFAULT_LIMITS.maxStringLength),
        maxTableEntries = positiveLimit(source.maxTableEntries, DEFAULT_LIMITS.maxTableEntries),
    }
end

local function trimString(value, limits)
    if #value <= limits.maxStringLength then return value end
    return value:sub(1, limits.maxStringLength) .. "...<truncated:" .. tostring(#value) .. ">"
end

local function pruneArrayFromFront(items, maxItems)
    if type(items) ~= "table" then return 0 end
    local count = #items
    if count <= maxItems then return 0 end

    local dropped = count - maxItems
    for i = 1, maxItems do
        items[i] = items[i + dropped]
    end
    for i = maxItems + 1, count do
        items[i] = nil
    end
    return dropped
end

local function sanitizeTable(t, limits, depth)
    if depth >= 1 then return "<table>" end

    local out = {}
    local copied = 0
    for k, v in pairs(t) do
        copied = copied + 1
        if copied > limits.maxTableEntries then
            out.__truncated = true
            break
        end

        local okKey, safeKey = pcall(ns.SanitizeArg, k, limits, depth + 1)
        local okValue, safeValue = pcall(ns.SanitizeArg, v, limits, depth + 1)
        out[okKey and safeKey or "<unstorable-key>"] = okValue and safeValue or "<unstorable>"
    end
    return out
end

function ns.SanitizeArg(v, opts, depth)
    local limits = ns.GetLimits(opts)
    depth = depth or 0

    local tv = type(v)
    if tv == "string" then
        return trimString(v, limits)
    end
    if tv == "number" or tv == "boolean" or tv == "nil" then
        return v
    end
    if tv == "table" then
        local ok, copy = pcall(sanitizeTable, v, limits, depth)
        return ok and copy or "<unstorable-table>"
    end
    -- userdata / function / thread / secret values: never store the live ref.
    return "<" .. tv .. ">"
end

function ns.SanitizeArgs(...)
    local limits = ns.GetLimits()
    local n = select("#", ...)
    local captured = n
    if captured > limits.maxArgs then captured = limits.maxArgs end

    local out = {}
    for i = 1, captured do
        local ok, s = pcall(ns.SanitizeArg, (select(i, ...)), limits, 0)
        out[i] = ok and s or "<unstorable>"
    end
    if n > captured then
        out[captured + 1] = "<args-truncated:" .. tostring(n) .. ">"
    end
    return out, n
end
function ns.BuildRecord(timeFn, event, ...)
    local args, n = ns.SanitizeArgs(...)
    return { t = timeFn(), e = event, a = args, n = n }
end
function ns.NewSession(dateStr)
    return { started = dateStr, events = {} }
end

function ns.PruneSession(session, opts)
    if type(session) ~= "table" then return 0 end
    if type(session.events) ~= "table" then
        session.events = {}
        return 0
    end

    local limits = ns.GetLimits(opts)
    local dropped = pruneArrayFromFront(session.events, limits.maxEventsPerSession)
    if dropped > 0 then
        session.dropped = (tonumber(session.dropped) or 0) + dropped
    end
    return dropped
end

function ns.PruneDB(db, opts)
    if type(db) ~= "table" then return db end

    local limits = ns.GetLimits(opts)
    if type(db.sessions) ~= "table" then db.sessions = {} end

    local droppedSessions = pruneArrayFromFront(db.sessions, limits.maxSessions)
    if droppedSessions > 0 then
        db.droppedSessions = (tonumber(db.droppedSessions) or 0) + droppedSessions
    end

    for i = 1, #db.sessions do
        ns.PruneSession(db.sessions[i], limits)
    end
    return db
end

function ns.EnsureDB(dbProvider, opts)
    local db = dbProvider.get() or {}
    if type(db) ~= "table" then db = {} end
    if type(db.sessions) ~= "table" then db.sessions = {} end
    ns.PruneDB(db, opts)
    dbProvider.set(db)
    return db
end

function ns.InitDB(dbProvider, opts)
    local db = ns.EnsureDB(dbProvider, opts)
    local session = ns.NewSession(ns._dateFn and ns._dateFn() or "?")
    db.sessions[#db.sessions + 1] = session
    ns.PruneDB(db, opts)
    dbProvider.set(db)
    return session.events, session
end

function ns.ClearDB(db)
    if db then
        db.sessions = {}
        db.droppedSessions = 0
    end
end

function ns.StatusString(db)
    local sessions = (db and db.sessions) or {}
    local events = 0
    for i = 1, #sessions do
        local session = sessions[i]
        if type(session) == "table" and type(session.events) == "table" then
            events = events + #session.events
        end
    end
    return string.format("sessions=%d events=%d", #sessions, events)
end

-- Live wiring: only with WoW globals present.
if type(CreateFrame) == "function" then
    ns._dateFn = date
    local limits = ns.GetLimits()
    local provider = {
        get = function() return QUI_LoggerDB end,
        set = function(v) QUI_LoggerDB = v end,
    }

    local buffer = {}
    local sink = buffer
    local liveSink
    local liveSession
    local registeredAllEvents = false
    local recording = _G and _G.QUI_LOGGER_ENABLE == true

    local frame = CreateFrame("Frame")
    local function registerAllEvents()
        if registeredAllEvents then return end
        frame:RegisterAllEvents()
        registeredAllEvents = true
    end

    local function appendRecord(event, ...)
        sink[#sink + 1] = ns.BuildRecord(GetTimePreciseSec, event, ...)
        local maxEvents = (sink == buffer) and limits.maxBufferedEvents or limits.maxEventsPerSession
        local dropped = pruneArrayFromFront(sink, maxEvents)
        if dropped > 0 and liveSession then
            liveSession.dropped = (tonumber(liveSession.dropped) or 0) + dropped
        end
    end

    local function startRecording()
        local db = ns.EnsureDB(provider, limits)
        db.enabled = true
        provider.set(db)
        if not liveSink then
            liveSink, liveSession = ns.InitDB(provider, limits)
        end
        sink = liveSink
        recording = true
        registerAllEvents()
    end

    local function stopRecording()
        local db = ns.EnsureDB(provider, limits)
        db.enabled = false
        provider.set(db)
        recording = false
    end

    local function record(event, ...)
        if recording then appendRecord(event, ...) end
    end

    -- NOTE: COMBAT_LOG_EVENT_UNFILTERED is NOT capturable from an addon in 12.0
    -- (Midnight). CLEU was removed from the addon environment: Frame:RegisterEvent
    -- for it raises ADDON_ACTION_FORBIDDEN, the public CombatLogGetCurrentEventInfo
    -- is gone from the API docs, and combat data moved to the Blizzard-only
    -- COMBAT_LOG_EVENT_INTERNAL_UNFILTERED / C_CombatLogInternal plus the aggregate
    -- C_DamageMeter API. RegisterAllEvents also never delivered CLEU. For raw
    -- combat-log capture use the client's own /combatlog (writes
    -- WoWCombatLog-*.txt), which is not addon-gated.
    frame:RegisterEvent("ADDON_LOADED")
    if recording then registerAllEvents() end

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" and ... == addonName then
            local db = ns.EnsureDB(provider, limits)
            if _G and _G.QUI_LOGGER_ENABLE == true then db.enabled = true end
            recording = db.enabled == true

            if recording then
                registerAllEvents()
                liveSink, liveSession = ns.InitDB(provider, limits)
                for i = 1, #buffer do
                    liveSink[#liveSink + 1] = buffer[i]
                end
                ns.PruneSession(liveSession, limits)
            end

            buffer = nil
            sink = liveSink or {}
            return
        end
        record(event, ...)
    end)

    SLASH_QLOG1 = "/qlog"
    SlashCmdList["QLOG"] = function(msg)
        msg = (msg or ""):lower():gsub("%s+", "")
        if msg == "clear" then
            ns.ClearDB(QUI_LoggerDB)
            liveSink = nil
            liveSession = nil
            sink = {}
            if recording then startRecording() end
            print("QUI_Logger: cleared")
        elseif msg == "on" then
            startRecording()
            print("QUI_Logger: recording on")
        elseif msg == "off" then
            stopRecording()
            print("QUI_Logger: recording off")
        else
            local state = recording and "on" or "off"
            print("QUI_Logger: recording=" .. state .. " " .. ns.StatusString(QUI_LoggerDB))
        end
    end
end
