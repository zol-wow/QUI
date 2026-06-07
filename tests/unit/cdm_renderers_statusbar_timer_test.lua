-- tests/unit/cdm_renderers_statusbar_timer_test.lua
-- Run: lua tests/unit/cdm_renderers_statusbar_timer_test.lua

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
local secretStart = { token = "secret-start" }
local secretDuration = { token = "secret-duration" }

function issecretvalue(value)
    return value == secretStart or value == secretDuration
end

loadChunk("QUI_CDM/cdm/cdm_frame_writes.lua", "cdm_frame_writes.lua")("QUI", ns)

local renderers = assert(ns.CDMRenderers, "CDMRenderers table was not exported")

local durObj = { token = "duration-object" }
local minMaxCalls = 0
local timerSelf
local timerDurObj
local timerInterpolation
local timerDirection

local statusBar = {
    SetMinMaxValues = function()
        minMaxCalls = minMaxCalls + 1
    end,
    SetTimerDuration = function(self, duration, interpolation, direction)
        timerSelf = self
        timerDurObj = duration
        timerInterpolation = interpolation
        timerDirection = direction
    end,
}

local ok = renderers.SetStatusBarTimerDuration(statusBar, durObj)

assert(ok == true,
    "duration-object status-bar timer binding should report success")
assert(timerSelf == statusBar,
    "status-bar timer binding should call SetTimerDuration as a method")
assert(timerDurObj == durObj,
    "status-bar timer binding should forward the DurationObject")
assert(timerInterpolation == 0,
    "status-bar timer binding should use Immediate interpolation")
assert(timerDirection == 1,
    "status-bar timer binding should use RemainingTime direction so aura bars drain")
assert(minMaxCalls == 0,
    "status-bar timer binding should not force a 0..1 range before SetTimerDuration")

local cooldownCalls = 0
local reverseValue
local cooldownStart
local cooldownDuration
local cooldown = {
    SetReverse = function(_, value)
        reverseValue = value
    end,
    SetCooldown = function(_, startTime, duration)
        cooldownCalls = cooldownCalls + 1
        cooldownStart = startTime
        cooldownDuration = duration
    end,
}

ok = renderers.ApplyNumericCooldown(cooldown, secretStart, 30, false)
assert(ok == false, "secret start times must not be passed to SetCooldown")
assert(cooldownCalls == 0, "secret start time should skip SetCooldown")
assert(reverseValue == nil, "secret start time should not mutate reverse state")

ok = renderers.ApplyNumericCooldown(cooldown, 10, secretDuration, false)
assert(ok == false, "secret durations must not be passed to SetCooldown")
assert(cooldownCalls == 0, "secret duration should skip SetCooldown")
assert(reverseValue == nil, "secret duration should not mutate reverse state")

ok = renderers.ApplyNumericCooldown(cooldown, 10, 20, true)
assert(ok == true, "clean numeric timing should still use SetCooldown")
assert(cooldownCalls == 1, "clean numeric timing should call SetCooldown once")
assert(cooldownStart == 10 and cooldownDuration == 20,
    "clean numeric timing should forward start and duration")
assert(reverseValue == true, "clean numeric timing should preserve reverse state")

print("OK: cdm_renderers_statusbar_timer_test")
