-- tests/unit/groupframes_absorb_throttle_split_test.lua
-- Run: lua tests/unit/groupframes_absorb_throttle_split_test.lua
--
-- UNIT_ABSORB_AMOUNT_CHANGED and UNIT_HEAL_ABSORB_AMOUNT_CHANGED are separate
-- visual overlays. Their throttles must not suppress each other for the same
-- unit inside the 100 ms coalesce window.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a")
    f:close()
    return d:gsub("\r\n", "\n")
end

local source = readAll("QUI_GroupFrames/groupframes/groupframes.lua")
local startPos = assert(source:find("local function OnEvent%(self, event, arg1, %.%.%.%)"),
    "OnEvent should exist")
local endMarker = "\neventFrame:SetScript(\"OnEvent\", OnEvent)"
local endPos = assert(source:find(endMarker, startPos, true),
    "OnEvent should end before eventFrame:SetScript")
local onEventSource = source:sub(startPos, endPos - 1)

local calls = {
    absorb = 0,
    healAbsorb = 0,
    healPrediction = 0,
}
local now = 100
local frame = {}

local ctx = {
    QUI_GF = {
        initialized = true,
        unitFrameMap = {
            raid1 = { frame },
        },
    },
    _state = {
        cachedModuleEnabled = true,
        healAbsorbThrottle = {},
    },
    _range = {
        cache = {},
        cacheTime = {},
    },
    powerThrottle = {},
    absorbThrottle = {},
    healAbsorbThrottle = {},
    healPredThrottle = {},
    THROTTLE_INTERVAL = 0.1,
    GetTime = function() return now end,
    UnitExists = function() return true end,
    RebuildUnitFrameMap = function() error("unexpected map rebuild") end,
    UpdateAbsorbs = function(seenFrame)
        assert(seenFrame == frame, "UpdateAbsorbs should receive mapped frame")
        calls.absorb = calls.absorb + 1
    end,
    UpdateHealAbsorb = function(seenFrame)
        assert(seenFrame == frame, "UpdateHealAbsorb should receive mapped frame")
        calls.healAbsorb = calls.healAbsorb + 1
    end,
    UpdateHealPrediction = function(seenFrame)
        assert(seenFrame == frame, "UpdateHealPrediction should receive mapped frame")
        calls.healPrediction = calls.healPrediction + 1
    end,
    type = type,
    pairs = pairs,
    wipe = function(t) for k in pairs(t) do t[k] = nil end end,
}

local prelude = [[
local QUI_GF = QUI_GF
local _state = _state
local _range = _range
local powerThrottle = powerThrottle
local absorbThrottle = absorbThrottle
local healAbsorbThrottle = healAbsorbThrottle
local healPredThrottle = healPredThrottle
local THROTTLE_INTERVAL = THROTTLE_INTERVAL
local GetTime = GetTime
local UnitExists = UnitExists
local RebuildUnitFrameMap = RebuildUnitFrameMap
local UpdateAbsorbs = UpdateAbsorbs
local UpdateHealAbsorb = UpdateHealAbsorb
local UpdateHealPrediction = UpdateHealPrediction
]]

local loader = assert(loadstring(prelude .. onEventSource .. "\nreturn OnEvent"))
setfenv(loader, ctx)
local OnEvent = loader()

OnEvent(nil, "UNIT_ABSORB_AMOUNT_CHANGED", "raid1")
OnEvent(nil, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "raid1")
OnEvent(nil, "UNIT_ABSORB_AMOUNT_CHANGED", "raid1")

assert(calls.absorb == 1, "duplicate absorb event inside 100 ms should be throttled")
assert(calls.healAbsorb == 1,
    "heal-absorb event should not be suppressed by absorb event throttle")
assert(calls.healPrediction == 0, "heal prediction should not run for absorb events")

print("OK: groupframes_absorb_throttle_split_test")
