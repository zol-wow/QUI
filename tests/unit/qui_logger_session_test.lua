-- tests/unit/qui_logger_session_test.lua
-- Run: lua tests/unit/qui_logger_session_test.lua
local ns = {}
assert(loadfile("QUI_Logger/recorder.lua"))("QUI_Logger", ns)

local s = ns.NewSession("D1")
assert(s.started == "D1" and type(s.events) == "table" and #s.events == 0)

-- InitDB appends a session and returns the live events sink
local store = {}
local provider = { get = function() return store.db end, set = function(v) store.db = v end }
local sink = ns.InitDB(provider)
assert(type(sink) == "table", "InitDB must return events sink")
assert(#store.db.sessions == 1, "one session appended")
sink[#sink + 1] = { e = "X" }

-- second init appends another, leaves first intact
local sink2 = ns.InitDB(provider)
assert(#store.db.sessions == 2, "second session appended")
assert(#store.db.sessions[1].events == 1, "first session preserved")

-- status sums events across sessions
assert(ns.StatusString(store.db) == "sessions=2 events=1",
    "got: " .. ns.StatusString(store.db))

-- pruning keeps the newest sessions and newest events only
local pruneDB = {
    sessions = {
        { started = "old", events = { { e = "a" } } },
        { started = "mid", events = { { e = "b" }, { e = "c" }, { e = "d" } } },
        { started = "new", events = { { e = "e" } } },
    },
}
ns.PruneDB(pruneDB, { maxSessions = 2, maxEventsPerSession = 2 })
assert(#pruneDB.sessions == 2, "old sessions should be dropped")
assert(pruneDB.sessions[1].started == "mid" and pruneDB.sessions[2].started == "new",
    "newest sessions should be retained")
assert(#pruneDB.sessions[1].events == 2 and pruneDB.sessions[1].events[1].e == "c",
    "newest events should be retained")
assert(pruneDB.droppedSessions == 1 and pruneDB.sessions[1].dropped == 1,
    "dropped counts should be tracked")

-- InitDB prunes before saving, so repeated starts cannot grow forever
local bounded = {
    db = {
        sessions = {
            { started = "A", events = {} },
            { started = "B", events = {} },
        },
    },
}
local boundedProvider = {
    get = function() return bounded.db end,
    set = function(v) bounded.db = v end,
}
ns._dateFn = function() return "C" end
local boundedSink = ns.InitDB(boundedProvider, { maxSessions = 2, maxEventsPerSession = 5 })
ns._dateFn = nil
assert(type(boundedSink) == "table", "bounded InitDB returns sink")
assert(#bounded.db.sessions == 2, "bounded InitDB should retain max sessions")
assert(bounded.db.sessions[1].started == "B" and bounded.db.sessions[2].started == "C",
    "bounded InitDB should drop oldest session after append")

-- clear empties sessions
ns.ClearDB(store.db)
assert(#store.db.sessions == 0, "clear empties sessions")

-- live wiring defaults to off, then /qlog on captures a bounded stream
local liveNS = {
    loggerLimits = {
        maxSessions = 2,
        maxEventsPerSession = 2,
        maxBufferedEvents = 1,
        maxArgs = 4,
        maxStringLength = 20,
        maxTableEntries = 4,
    },
}
local frame
local now = 0
local realPrint = print
local oldCreateFrame = CreateFrame
local oldGetTimePreciseSec = GetTimePreciseSec
local oldDate = date
local oldSlashCmdList = SlashCmdList
local oldDB = QUI_LoggerDB
local oldEnable = QUI_LOGGER_ENABLE
CreateFrame = function()
    frame = { events = {}, scripts = {}, allEvents = 0 }
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:RegisterAllEvents()
        self.allEvents = self.allEvents + 1
    end
    function frame:SetScript(name, fn)
        self.scripts[name] = fn
    end
    return frame
end
GetTimePreciseSec = function()
    now = now + 1
    return now
end
date = function() return "D" end
SlashCmdList = {}
print = function() end
QUI_LoggerDB = nil
QUI_LOGGER_ENABLE = nil

assert(loadfile("QUI_Logger/recorder.lua"))("QUI_Logger", liveNS)
assert(frame.events.ADDON_LOADED == true, "logger should listen for ADDON_LOADED")
assert(frame.allEvents == 0, "logger should not register all events while disabled")

frame.scripts.OnEvent(frame, "ADDON_LOADED", "QUI_Logger")
assert(type(QUI_LoggerDB) == "table", "ADDON_LOADED should initialize DB")
assert(#QUI_LoggerDB.sessions == 0, "disabled logger should not start a session")

frame.scripts.OnEvent(frame, "PLAYER_LOGIN", "ignored")
assert(#QUI_LoggerDB.sessions == 0, "disabled logger should not record events")

SlashCmdList.QLOG("on")
assert(QUI_LoggerDB.enabled == true, "/qlog on should persist enabled state")
assert(frame.allEvents == 1, "/qlog on should register all events")
assert(#QUI_LoggerDB.sessions == 1, "/qlog on should start one session")

frame.scripts.OnEvent(frame, "EVENT_ONE", "one")
frame.scripts.OnEvent(frame, "EVENT_TWO", "two")
frame.scripts.OnEvent(frame, "EVENT_THREE", "three")

local session = QUI_LoggerDB.sessions[1]
assert(#session.events == 2, "live recording should cap event count")
assert(session.events[1].e == "EVENT_TWO" and session.events[2].e == "EVENT_THREE",
    "live recording should retain newest events")
assert(session.dropped == 1, "live recording should track dropped events")

SlashCmdList.QLOG("off")
local count = #session.events
frame.scripts.OnEvent(frame, "EVENT_FOUR", "four")
assert(#session.events == count, "/qlog off should stop recording")

SlashCmdList.QLOG("clear")
assert(#QUI_LoggerDB.sessions == 0, "/qlog clear should clear sessions while stopped")

print = realPrint
CreateFrame = oldCreateFrame
GetTimePreciseSec = oldGetTimePreciseSec
date = oldDate
SlashCmdList = oldSlashCmdList
QUI_LoggerDB = oldDB
QUI_LOGGER_ENABLE = oldEnable

print("qui_logger_session_test: OK")
