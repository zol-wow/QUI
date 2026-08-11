-- tests/unit/unitframes_tot_poll_identity_test.lua
-- ToT poll split: vitals (health/absorbs/power) poll every 0.5s tick;
-- identity (name/level) is event-driven (UNIT_NAME_UPDATE / UNIT_LEVEL are
-- registered, and UNIT_TARGET / PLAYER_TARGET_CHANGED run full UpdateFrame)
-- with a slow every-Nth-tick fallback because the client does not route
-- unit events reliably for the compound targettarget token.
-- Run: lua5.1 tests/unit/unitframes_tot_poll_identity_test.lua

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
    source:find("local function ForceUpdateToT(", 1, true),
    "ToT section should exist")
local endPos = assert(
    source:find("local _bossTargetHighlightFrame", startPos, true),
    "ToT section should end before Boss Target Highlight")
local body = source:sub(startPos, endPos - 1)

-- Stub environment: the sliced chunk resolves these as globals.
local calls = { health = 0, absorbs = 0, power = 0, powerText = 0, name = 0, level = 0 }
local totExists = { value = true }
local capturedInterval, capturedCallback

QUI_UF = { frames = { targettarget = {} } }
UnitExists = function(unit) return unit == "targettarget" and totExists.value end
UpdateHealth = function() calls.health = calls.health + 1 end
UpdateAbsorbs = function() calls.absorbs = calls.absorbs + 1 end
UpdatePower = function() calls.power = calls.power + 1 end
UpdatePowerText = function() calls.powerText = calls.powerText + 1 end
UpdateName = function() calls.name = calls.name + 1 end
UpdateLevelText = function() calls.level = calls.level + 1 end
C_Timer = { NewTicker = function(interval, cb)
    capturedInterval, capturedCallback = interval, cb
    return { Cancel = function() capturedCallback = nil end }
end }

local loader = loadstring or load
local ToT = assert(loader(
    body .. "\nreturn { StartToTTicker = StartToTTicker,"
         .. " StopToTTicker = StopToTTicker, ForceUpdateToT = ForceUpdateToT }",
    "tot_section"))()

do -- cadence: vitals every tick, identity every 4th tick (2s at 0.5s interval)
    ToT.StartToTTicker()
    check("ticker interval is 0.5s", capturedInterval == 0.5)
    for _ = 1, 8 do capturedCallback() end
    check("vitals every tick",
        calls.health == 8 and calls.absorbs == 8
        and calls.power == 8 and calls.powerText == 8,
        ("h=%d a=%d p=%d pt=%d"):format(calls.health, calls.absorbs, calls.power, calls.powerText))
    check("identity every 4th tick", calls.name == 2 and calls.level == 2,
        ("name=%d level=%d"):format(calls.name, calls.level))
end

do -- explicit calls: identity only when requested
    local n0 = calls.name
    ToT.ForceUpdateToT(true)
    check("explicit identity refresh", calls.name == n0 + 1)
    local n1 = calls.name
    ToT.ForceUpdateToT()
    check("vitals-only call skips identity", calls.name == n1)
end

do -- restart resets the identity cadence
    ToT.StopToTTicker()
    calls.name = 0
    ToT.StartToTTicker()
    for _ = 1, 3 do capturedCallback() end
    check("no identity before the Nth tick after restart", calls.name == 0)
    capturedCallback()
    check("identity on the Nth tick after restart", calls.name == 1)
end

do -- unit gone: the tick does no work at all
    totExists.value = false
    local h0 = calls.health
    capturedCallback()
    check("no updates when ToT missing", calls.health == h0)
end

do -- event-driven identity paths stay in place (source shape)
    check("UNIT_NAME_UPDATE still registered for frames",
        source:find('frame:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)', 1, true) ~= nil)
    check("UNIT_LEVEL still registered for frames",
        source:find('frame:RegisterUnitEvent("UNIT_LEVEL", unit)', 1, true) ~= nil)
    check("UNIT_TARGET still runs full UpdateFrame for the ToT frame",
        source:find('elseif self.unitKey == "targettarget" then', 1, true) ~= nil)
end

if failures > 0 then os.exit(1) end
print("unitframes_tot_poll_identity_test: all checks passed")
