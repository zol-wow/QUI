-- tests/unit/unitframes_power_coalesce_test.lua
-- Generation-token coalescing for UNIT_POWER_FREQUENT: pure drain-decision
-- helper (QUI_UF.PowerCoalesce) sliced out of unitframes.lua and driven with
-- injected state. C_Timer.After callbacks are uncancellable, so an immediate
-- power refresh invalidates a pending drain by bumping a generation token;
-- the drain no-ops when the generation it captured at queue time is stale.
-- Run: lua5.1 tests/unit/unitframes_power_coalesce_test.lua

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local source = readAll("QUI_UnitFrames/unitframes/unitframes.lua")

local startPos = assert(
    source:find("QUI_UF.PowerCoalesce = {}", 1, true),
    "PowerCoalesce section should exist in unitframes.lua")
local endPos = assert(
    source:find("local function ForceUpdateToT(", startPos, true),
    "PowerCoalesce section should end before the ToT section")
local body = source:sub(startPos, endPos - 1)

local loader = loadstring or load
local chunk = assert(loader(
    "local QUI_UF = {}\n" .. body .. "\nreturn QUI_UF",
    "power_coalesce_section"))

-- Secret simulation: a sentinel table stands in for an engine secret value.
-- The sliced chunk resolves IsSecretValue / UnitPowerType as globals.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local stub = { token = "MANA" }
IsSecretValue = function(v) return v == SECRET end
UnitPowerType = function(_) return 0, stub.token end

local QUI_UF = chunk()
local PC = assert(QUI_UF.PowerCoalesce, "chunk should export QUI_UF.PowerCoalesce")

do -- double-queue collapse: one timer per drain window
    local s = PC.NewState()
    check("first frequent schedules a timer", PC.OnFrequent(s) == true)
    check("second frequent collapses (no second timer)", PC.OnFrequent(s) == false)
    check("drain fires while current", PC.OnFire(s) == true)
    check("fire clears queue: next frequent schedules again", PC.OnFrequent(s) == true)
end

do -- stale timer fires after an immediate refresh: must no-op
    local s = PC.NewState()
    PC.OnFrequent(s)      -- timer queued at gen 0
    PC.OnImmediate(s)     -- UNIT_POWER_UPDATE already redrew the bar
    check("stale drain no-ops after immediate", PC.OnFire(s) == false)
end

do -- frequent arriving after an immediate re-validates the pending timer
    local s = PC.NewState()
    check("schedule", PC.OnFrequent(s) == true)
    PC.OnImmediate(s)
    check("still no second timer while one is pending", PC.OnFrequent(s) == false)
    check("pending timer serves the newer frequent", PC.OnFire(s) == true)
end

do -- spurious fire with nothing queued (uncancellable-timer paranoia)
    local s = PC.NewState()
    check("fire with empty queue no-ops", PC.OnFire(s) == false)
end

do -- generation wraparound irrelevance: gen is a Lua double, exact to 2^53.
   -- One immediate bump per 5ms for a year is ~6.3e9 (~2^33); staleness must
   -- still be detected far beyond any real session.
    local s = PC.NewState()
    s.gen = 2^40
    PC.OnFrequent(s)
    PC.OnImmediate(s)
    check("2^40 + 1 stays distinct from 2^40", s.gen == 2^40 + 1 and s.gen ~= 2^40)
    check("stale detected at huge generation", PC.OnFire(s) == false)
    PC.OnFrequent(s)
    check("fresh fires at huge generation", PC.OnFire(s) == true)
end

do -- EventMatters: pure powerType relevance
    check("nil event type refreshes", PC.EventMatters(nil, "MANA", false) == true)
    check("nil displayed token refreshes", PC.EventMatters("MANA", nil, false) == true)
    check("secret on either side refreshes", PC.EventMatters("MANA", "ENERGY", true) == true)
    check("matching type refreshes", PC.EventMatters("MANA", "MANA", false) == true)
    check("mismatched type skips", PC.EventMatters("MANA", "ENERGY", false) == false)
end

do -- EventPowerMatters wrapper: probes before comparing (@secret-policy collapse-only)
    stub.token = "ENERGY"
    check("wrapper skips off-display type", QUI_UF.EventPowerMatters("player", "MANA") == false)
    check("wrapper refreshes displayed type", QUI_UF.EventPowerMatters("player", "ENERGY") == true)
    stub.token = SECRET
    check("secret displayed token collapses to refresh", QUI_UF.EventPowerMatters("player", "MANA") == true)
    stub.token = "MANA"
    check("secret event token collapses to refresh", QUI_UF.EventPowerMatters("player", SECRET) == true)
    check("nil event token refreshes", QUI_UF.EventPowerMatters("player", nil) == true)
end

do -- wiring: the frame OnEvent uses the token helper, not a raw boolean latch
    check("boolean latch removed",
        not source:find("_freqPowerQueued", 1, true))
    check("handler receives the powerType payload (arg2)",
        source:find('frame:SetScript("OnEvent", function(self, event, arg1, arg2)', 1, true) ~= nil)
    check("frequent branch filters by payload type",
        source:find("QUI_UF.EventPowerMatters(frameUnit, arg2)", 1, true) ~= nil)
    check("frequent branch queues via the token helper",
        source:find("QUI_UF.PowerCoalesce.OnFrequent(_freqPower)", 1, true) ~= nil)
    check("immediate branch bumps the generation",
        source:find("QUI_UF.PowerCoalesce.OnImmediate(_freqPower)", 1, true) ~= nil)
    check("drain gates on the captured generation",
        source:find("QUI_UF.PowerCoalesce.OnFire(_freqPower)", 1, true) ~= nil)
    check("MAXPOWER always refreshes regardless of payload type",
        source:find('if event == "UNIT_MAXPOWER" or QUI_UF.EventPowerMatters(frameUnit, arg2) then', 1, true) ~= nil)
end

if failures > 0 then os.exit(1) end
print("unitframes_power_coalesce_test: all checks passed")
