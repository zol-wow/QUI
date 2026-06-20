-- tests/replay/profile_groupframes_full_example.lua
-- Usage: lua tests/replay/profile_groupframes_full_example.lua <path-to-QUI_Logger.lua> [sessionIndex]
--
-- Loads a captured QUI_Logger session, drives it through the REAL
-- groupframes.lua OnEvent handler (SECONDARY / full-module scope), and
-- prints per-event-type allocation churn + total cost.
--
-- This complements profile_groupframes_example.lua (PRIMARY / aura scope).
-- Events driven here exercise the REAL local Update* functions in
-- groupframes.lua: UpdateHealth, UpdatePower, UpdateAbsorbs,
-- UpdateHealAbsorb, UpdateHealPrediction, UpdateName, UpdateThreat,
-- UpdateConnection.
--
-- luacheck: globals arg

local path = arg and arg[1]
if not path then
    error("usage: lua tests/replay/profile_groupframes_full_example.lua" ..
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

-- Build the full-scope adapter (loads real groupframes.lua, captures OnEvent,
-- injects synthetic unit frame into QUI_GF.unitFrameMap["raid1"])
local healthSetValueTotal = 0
local powerSetValueTotal  = 0

local fbuilt = A.Build({
    scope = "full",
    onCallback = function(name)
        if name == "healthBar:SetValue" then
            healthSetValueTotal = healthSetValueTotal + 1
        elseif name == "powerBar:SetValue" then
            powerSetValueTotal = powerSetValueTotal + 1
        end
    end,
})

local fctx = fbuilt.ctx
local QUI_GF = fctx.QUI_GF

print(string.format(
    "scope: SECONDARY (full-module)  unit=raid1  initialized=%s  cachedModuleEnabled=%s",
    tostring(QUI_GF.initialized),
    tostring(QUI_GF.initialized)))  -- enabled was set via RefreshSettings

-- Profile per-event-type churn through real groupframes.lua Update* code
local churn, counts, rep, total = A.ProfileSessionFull(fctx, events)

-- Tally mapped vs unmapped
local mappedEvents = 0
local mappedTypes  = 0
for k, v in pairs(counts) do
    if v and v > 0 and A.FULL_EVENT_MAP[k] then
        mappedEvents = mappedEvents + v
        mappedTypes  = mappedTypes + 1
    end
end
local unmapped = A._lastFullUnmappedCount or 0

print("--- per-event-type group-frames FULL-MODULE allocation churn (descending by KB) ---")
if rep ~= "" then
    print(rep)
else
    print("  (no churn recorded)")
end
print(string.format("--- TOTAL: %.1f KB, %.2f ms over %d events ---",
    total.allocKB, total.cpuMs, #events))
print(string.format("--- mapped: %d events across %d types | unmapped (skipped): %d ---",
    mappedEvents, mappedTypes, unmapped))
print(string.format("--- proof: healthBar:SetValue=%d  powerBar:SetValue=%d ---",
    healthSetValueTotal, powerSetValueTotal))
