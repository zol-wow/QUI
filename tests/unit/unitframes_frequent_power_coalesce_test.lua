-- tests/unit/unitframes_frequent_power_coalesce_test.lua
-- Run: lua tests/unit/unitframes_frequent_power_coalesce_test.lua
--
-- Non-player unit frames register both UNIT_POWER_UPDATE and
-- UNIT_POWER_FREQUENT and handled them identically — FREQUENT fires many
-- times per second during energy/focus regen and fanned straight into
-- UpdatePower + UpdatePowerText per event. The player frame already
-- coalesces FREQUENT to 5 Hz; generic frames must too (trailing C_Timer
-- drain — the frame's OnUpdate slot stays free for other owners).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_UnitFrames/unitframes/unitframes.lua")

assert(source:find("local function DrainFrequentPower()", 1, true),
    "generic frames must have a FREQUENT power drain")

-- the combined identical-treatment branch must be split
assert(not source:find('event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER"', 1, true),
    "generic handler must not treat FREQUENT identically to discrete power events")

print("PASS unitframes_frequent_power_coalesce_test")
