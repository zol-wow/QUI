-- tests/replay/profile_groupframes_example.lua
-- Usage: lua tests/replay/profile_groupframes_example.lua <path-to-QUI_Logger.lua> [sessionIndex]
--
-- Loads a captured QUI_Logger session, drives it through group-frames' real
-- aura render sub-modules (groupframes_aura_model + groupframes_aura_render),
-- and prints per-event-type allocation churn + total cost.
--
-- This is an offline allocation A/B test: run the same capture before and
-- after a change to measure the allocation delta attributed to each event type.
-- UNIT_AURA is the hot path — it drives Model.ActiveElementsForSpec +
-- R.Dispatch (-> R.RenderIcon) for every active element on the synthetic frame.
--
-- luacheck: globals arg

local path = arg and arg[1]
if not path then
    error("usage: lua tests/replay/profile_groupframes_example.lua" ..
          " <path-to-QUI_Logger.lua> [sessionIndex]")
end
local idx = tonumber(arg and arg[2] or "0") or 0   -- 0 = last session

local R = assert(loadfile("tests/replay/replay_session.lua"))()
local A = assert(loadfile("tests/replay/profile_groupframes_adapter.lua"))()

-- Load session from the capture file
local db       = R.LoadFile(path)
local sessions = db.sessions or {}
local sess     = sessions[idx > 0 and idx or #sessions]
if not sess then
    error("no session at index " .. tostring(idx) ..
          " (total sessions: " .. #sessions .. ")")
end
local events = sess.events

print(string.format("session: started=%s  events=%d",
    tostring(sess.started), #events))

-- Build the adapter (stubs WoW globals, loads real group-frame aura sub-modules,
-- creates synthetic frame + aura cache + element list)
local built = A.Build()
local ctx = built.ctx
print(string.format("scope: PRIMARY (aura sub-modules)  elements=%d  auraCache.buffs=%d  auraCache.debuffs=%d",
    #ctx.elements,
    (function()
        local n = 0
        for _ in pairs(ctx.auraCache.buffsBySpellID or {}) do n = n + 1 end
        return n
    end)(),
    (function()
        local n = 0
        for _ in pairs(ctx.auraCache.debuffsBySpellID or {}) do n = n + 1 end
        return n
    end)()))

-- Profile per-event-type churn through real group-frame aura render code
local churn, counts, rep, total = A.ProfileSession(ctx, events)

-- Tally mapped vs unmapped
local mappedEvents = 0
local mappedTypes  = 0
for k, v in pairs(counts) do
    if v and v > 0 then
        -- Exclude events that were in the capture but not in our EVENT_MAP
        if A.EVENT_MAP[k] then
            mappedEvents = mappedEvents + v
            mappedTypes  = mappedTypes + 1
        end
    end
end
local unmapped = A._lastUnmappedCount or 0

print("--- per-event-type group-frames allocation churn (descending by KB) ---")
if rep ~= "" then
    print(rep)
else
    print("  (no churn recorded)")
end
print(string.format("--- TOTAL: %.1f KB, %.2f ms over %d events ---",
    total.allocKB, total.cpuMs, #events))
print(string.format("--- mapped: %d events across %d types | unmapped (skipped): %d ---",
    mappedEvents, mappedTypes, unmapped))
