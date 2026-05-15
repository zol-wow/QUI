-- tests/unitframes_boss_range_alpha_stability_test.lua
-- Run: lua tests/unitframes_boss_range_alpha_stability_test.lua

local path = "modules/unitframes/unitframes.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local startPos = assert(source:find("%-%- Boss Range Alpha"),
    "Boss Range Alpha section should exist")
local endPos = assert(source:find("%-%-%-+%s*\n%-%- CREATE: Unit Frame", startPos),
    "Boss Range Alpha section should end before CreateUnitFrame")
local body = source:sub(startPos, endPos)

assert(body:find("BOSS_RANGE_CHANGE_CONFIRMATIONS", 1, true),
    "boss range alpha should debounce range flips instead of applying single-sample changes")
assert(body:find("local inRange, checkedRange = UnitInRange(unit)", 1, true),
    "boss range fallback must read UnitInRange's checkedRange result")
assert(body:find("checkedRange == false", 1, true),
    "boss range fallback must treat unchecked UnitInRange results as indeterminate")
assert(body:find("return nil", body:find("checkedRange == false", 1, true), true),
    "unchecked boss range results should be skipped, not treated as in or out of range")
assert(body:find("if inRange == nil then", 1, true),
    "boss range alpha should skip indeterminate samples from spell range checks")
assert(body:find("bossRange.pending", 1, true),
    "boss range alpha should keep pending samples until a range change is stable")

print("OK: unitframes_boss_range_alpha_stability_test")
