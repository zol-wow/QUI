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

-- clear empties sessions
ns.ClearDB(store.db)
assert(#store.db.sessions == 0, "clear empties sessions")
print("qui_logger_session_test: OK")
