-- tests/unit/sound_mute_delta_test.lua
-- Run: lua tests/unit/sound_mute_delta_test.lua
--
-- Pins ComputeMuteDelta, the reconcile core of Sound Mute. Client mute state is
-- per-session, so on every login/setting-change the engine diffs the currently
-- applied set against the wanted set and only touches the difference — so a
-- newly-unticked entry is unmuted and a newly-ticked one is muted, without
-- re-hammering everything. Extracted from sound_mute.lua between its
-- QUI_TEST_EXTRACT sentinels (pure: uses only pairs/table).

local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("modules/qol/sound_mute.lua")
local S = "-- <<< QUI_TEST_EXTRACT mute_delta"
local a1 = assert(source:find(S, 1, true), "start sentinel must exist")
local a2 = assert(source:find(S, a1 + #S, true), "end sentinel must exist")
local block = source:sub(a1 + #S, a2 - 1)

local chunk = block .. "\nreturn { ComputeMuteDelta = ComputeMuteDelta }"
local M = assert(loadstring(chunk, "sound_mute_delta"))()
local Delta = M.ComputeMuteDelta

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("ok   - " .. name)
    else
        failures = failures + 1
        print("FAIL - " .. name .. (detail and ("  (" .. detail .. ")") or ""))
    end
end

local function toSet(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end
local function count(list) return #list end

-- Nothing applied, nothing wanted -> no-op.
do
    local un, mu = Delta({}, {})
    check("empty/empty: no unmute", count(un) == 0)
    check("empty/empty: no mute", count(mu) == 0)
end

-- Fresh want -> mute all wanted, unmute none.
do
    local un, mu = Delta({}, { a = true, b = true })
    check("fresh: no unmute", count(un) == 0)
    check("fresh: mute both", count(mu) == 2 and toSet(mu).a and toSet(mu).b)
end

-- All applied, none wanted -> unmute all.
do
    local un, mu = Delta({ a = true, b = true }, {})
    check("clear: unmute both", count(un) == 2 and toSet(un).a and toSet(un).b)
    check("clear: no mute", count(mu) == 0)
end

-- Steady state: applied == want -> no churn.
do
    local un, mu = Delta({ a = true, b = true }, { a = true, b = true })
    check("steady: no unmute", count(un) == 0)
    check("steady: no mute", count(mu) == 0)
end

-- Mixed: one removed, one added, one unchanged.
do
    local un, mu = Delta({ a = true, b = true }, { b = true, c = true })
    check("mixed: unmute only a", count(un) == 1 and un[1] == "a")
    check("mixed: mute only c", count(mu) == 1 and mu[1] == "c")
end

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
