-- tests/unit/damage_meter_rate_duration_test.lua
-- Run: lua tests/unit/damage_meter_rate_duration_test.lua
--
-- Standalone test for ResolveRateDuration — the pure helper that picks the
-- per-second divisor used to recompute a row's amountPerSecond.
--
-- The regression it guards: for the live Current session,
-- C_DamageMeter.GetSessionDurationSeconds(Current) is Nilable and frequently
-- returns nil. DerivePerSecond then bailed and the row kept the API's
-- amountPerSecond, which declassifies to garbage post-combat (a DPS row read
-- "0.0576" and an HPS row "0.0000933" instead of ~5K). The fix falls back to
-- QUI's own combat timer (GetCombatElapsed — the same value the [m:ss] header
-- shows) so the Current rate stays consistent with the displayed elapsed time.
-- Overall (cumulative across past combats) still prefers the API duration,
-- which our live timer cannot know.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

local start_pos = src:find("local function ResolveRateDuration")
assert(start_pos, "could not locate ResolveRateDuration block in damage_meter.lua")
local end_pos = src:find("QUI_DamageMeter%.ResolveRateDuration", start_pos)
assert(end_pos, "could not locate QUI_DamageMeter.ResolveRateDuration assignment")

local chunk = src:sub(start_pos, end_pos - 1):match("^(.-)\n%s*$")
assert(chunk, "failed to extract function chunk")

local loader = assert(loadstring(chunk .. "\nreturn ResolveRateDuration"))
local ResolveRateDuration = loader()

local CURRENT, OVERALL, EXPIRED = 1, 0, 2

-- A stand-in secret value our fake isSecret recognises.
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local function isSecret(x) return x == SECRET end

-- Signature: ResolveRateDuration(sessionType, apiDuration, combatElapsed,
--                                 historicalDuration, isSecret, currentType, expiredType)

-- Case 1 (THE REGRESSION): Current session, API duration nil -> fall back to
-- the live combat timer so the rate matches the [0:58] header.
do
    local d = ResolveRateDuration(CURRENT, nil, 58, nil, isSecret, CURRENT, EXPIRED)
    assert(d == 58, "Current with nil API duration must fall back to combatElapsed")
end

-- Case 2: Current session prefers our timer even when the API offers a value
-- (the API Current duration is unreliable; the timer drives the visible clock).
do
    local d = ResolveRateDuration(CURRENT, 999, 58, nil, isSecret, CURRENT, EXPIRED)
    assert(d == 58, "Current must prefer combatElapsed over the API duration")
end

-- Case 3: Overall session uses the API (cumulative) duration the timer can't know.
do
    local d = ResolveRateDuration(OVERALL, 1108, 58, nil, isSecret, CURRENT, EXPIRED)
    assert(d == 1108, "Overall must use the API cumulative duration")
end

-- Case 4: Overall with nil API duration falls back to the live timer.
do
    local d = ResolveRateDuration(OVERALL, nil, 58, nil, isSecret, CURRENT, EXPIRED)
    assert(d == 58, "Overall with nil API duration falls back to combatElapsed")
end

-- Case 5: Expired/historical prefers the session's own recorded duration.
do
    local d = ResolveRateDuration(EXPIRED, 1108, 58, 240, isSecret, CURRENT, EXPIRED)
    assert(d == 240, "Expired must use its recorded historical duration")
    local d2 = ResolveRateDuration(EXPIRED, 1108, 58, nil, isSecret, CURRENT, EXPIRED)
    assert(d2 == 1108, "Expired with no recorded duration falls back to API duration")
end

-- Case 6: a secret duration is never usable (would fault DerivePerSecond).
do
    local d = ResolveRateDuration(OVERALL, SECRET, 58, nil, isSecret, CURRENT, EXPIRED)
    assert(d == 58, "secret API duration is unusable -> fall back to timer")
end

-- Case 7: non-positive / non-number durations are rejected.
do
    assert(ResolveRateDuration(CURRENT, nil, 0, nil, isSecret, CURRENT, EXPIRED) == nil,
        "zero elapsed and nil API -> nil (no usable divisor)")
    assert(ResolveRateDuration(CURRENT, -5, "x", nil, isSecret, CURRENT, EXPIRED) == nil,
        "negative/non-number durations rejected -> nil")
end

print("OK: damage_meter_rate_duration_test")
