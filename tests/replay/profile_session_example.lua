-- tests/replay/profile_session_example.lua
-- Usage: lua tests/replay/profile_session_example.lua <path-to-QUI_Logger.lua> [sessionIndex]
--
-- Profiles per-event-type allocation churn of replaying a captured QUI_Logger
-- session. With the no-op handler below it measures the replay/dispatch cost
-- and the stream mix; swap `handler` for a real subsystem OnEvent (via an
-- event->handler adapter) to attribute churn to that subsystem's code. The
-- engine (profile_replay.lua) and the numbers are identical either way --
-- run the SAME capture before and after a fix to A/B the allocation delta.
local path = arg and arg[1]
if not path then
    error("usage: lua tests/replay/profile_session_example.lua <path-to-QUI_Logger.lua> [sessionIndex]")
end
local idx = tonumber(arg[2] or "0") or 0   -- 0 = last session

local R = assert(loadfile("tests/replay/replay_session.lua"))()
local P = assert(loadfile("tests/replay/profile_replay.lua"))()

local db = R.LoadFile(path)
local sessions = db.sessions or {}
local sess = sessions[idx > 0 and idx or #sessions]
if not sess then error("no session at index " .. idx) end
local events = sess.events

-- Replace this with a real subsystem handler to profile that code path.
local function handler(_event, ...)   -- luacheck: ignore 212
    return ...
end

local churn, counts = P.profilePerKey(
    events,
    function(rec) return rec.e end,
    function(rec) handler(rec.e, unpack(rec.a, 1, rec.n or #rec.a)) end)

print(string.format("session: started=%s  events=%d", tostring(sess.started), #events))
print("--- per-event-type allocation churn (descending) ---")
print(P.report(churn, counts))

local total = P.measure(function()
    for i = 1, #events do
        local rec = events[i]
        handler(rec.e, unpack(rec.a, 1, rec.n or #rec.a))
    end
end)
print(string.format("--- TOTAL: %.1f KB, %.2f ms over %d events ---",
    total.allocKB, total.cpuMs, #events))
