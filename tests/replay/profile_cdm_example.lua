-- tests/replay/profile_cdm_example.lua
-- Usage: lua tests/replay/profile_cdm_example.lua <path-to-QUI_Logger.lua> [sessionIndex]
--
-- Loads a captured QUI_Logger session, drives it through CDM's real runtime
-- refresh controller, and prints per-event-type allocation churn + total cost.
-- This is an offline allocation A/B test: run the same capture before and after
-- a change to measure the allocation delta attributed to each event type.
--
-- luacheck: globals arg

local path = arg and arg[1]
if not path then
    error("usage: lua tests/replay/profile_cdm_example.lua <path-to-QUI_Logger.lua> [sessionIndex]")
end
local idx = tonumber(arg and arg[2] or "0") or 0   -- 0 = last session

local R = assert(loadfile("tests/replay/replay_session.lua"))()
local A = assert(loadfile("tests/replay/profile_cdm_adapter.lua"))()

-- Load session from the capture file
local db       = R.LoadFile(path)
local sessions = db.sessions or {}
local sess     = sessions[idx > 0 and idx or #sessions]
if not sess then
    error("no session at index " .. tostring(idx) .. " (total sessions: " .. #sessions .. ")")
end
local events = sess.events

print(string.format("session: started=%s  events=%d", tostring(sess.started), #events))

-- Build the adapter (stubs WoW globals, loads real CDM, creates controller + pools)
local built = A.Build()
print(string.format("pools: essential=%d  utility=%d  buff=%d",
    #built.pools.essential, #built.pools.utility, #built.pools.buff))

-- Profile per-event-type churn through CDM's real refresh controller
local churn, counts, rep, total = A.ProfileSession(built.controller, events)

-- Tally mapped vs unmapped
local mappedEvents = 0
local mappedTypes  = 0
for k, v in pairs(counts) do
    if v and v > 0 then
        mappedEvents = mappedEvents + v
        mappedTypes  = mappedTypes + 1
    end
end
local unmapped = A._lastUnmappedCount or 0

print("--- per-event-type CDM allocation churn (descending by KB) ---")
if rep ~= "" then
    print(rep)
else
    print("  (no churn recorded)")
end
print(string.format("--- TOTAL: %.1f KB, %.2f ms over %d events ---",
    total.allocKB, total.cpuMs, #events))
print(string.format("--- mapped: %d events across %d types | unmapped (skipped): %d ---",
    mappedEvents, mappedTypes, unmapped))
