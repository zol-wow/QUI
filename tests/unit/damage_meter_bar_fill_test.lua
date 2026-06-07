-- tests/unit/damage_meter_bar_fill_test.lua
-- Run: lua tests/unit/damage_meter_bar_fill_test.lua
--
-- Standalone test for ComputeBarFill — the pure helper that decides the
-- StatusBar (min, max, value) for a damage-meter row.
--
-- The regression it guards: during combat the source's totalAmount is
-- secret-tagged. The old renderer computed the fill ratio in Lua and skipped
-- SetValue entirely when the value was secret, so bars rendered at zero width
-- and their (correctly-set) class color was invisible — the "colorless bars
-- until combat ends" report. The fix hands raw values to the StatusBar widget,
-- which divides on the C side where secret values are readable. So the helper
-- MUST return the raw value even when isSecret() reports true.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

local start_pos = src:find("local function ComputeBarFill")
assert(start_pos, "could not locate ComputeBarFill block in damage_meter.lua")
local end_pos = src:find("QUI_DamageMeter%.ComputeBarFill", start_pos)
assert(end_pos, "could not locate QUI_DamageMeter.ComputeBarFill assignment")

local chunk = src:sub(start_pos, end_pos - 1):match("^(.-)\n%s*$")
assert(chunk, "failed to extract function chunk")

local loader = assert(loadstring(chunk .. "\nreturn ComputeBarFill"))
local ComputeBarFill = loader()

local DEATHS = 9

-- Case 1: normal damage row → range [0, max], value = totalAmount
do
    local mn, mx, v = ComputeBarFill(0, { totalAmount = 500 }, 1000, DEATHS, nil)
    assert(mn == 0, "min must be 0")
    assert(mx == 1000, "max must be the rank-1 total")
    assert(v == 500, "value must be the source totalAmount")
end

-- Case 2: Deaths type → full bar, no magnitude to scale
do
    local mn, mx, v = ComputeBarFill(DEATHS, { totalAmount = 0 }, 0, DEATHS, nil)
    assert(mn == 0 and mx == 1 and v == 1, "Deaths rows render full")
end

-- Case 3 (the regression): secret combat values must pass through RAW, not
-- be zeroed or skipped. Simulate combat by tagging sentinels as secret.
do
    local SECRET_VAL = setmetatable({}, { __tostring = function() return "secret" end })
    local SECRET_MAX = setmetatable({}, { __tostring = function() return "secret" end })
    local function isSecret(x) return x == SECRET_VAL or x == SECRET_MAX end
    local mn, mx, v = ComputeBarFill(0, { totalAmount = SECRET_VAL }, SECRET_MAX, DEATHS, isSecret)
    assert(mn == 0, "min must be 0 even for secret values")
    assert(mx == SECRET_MAX, "secret max must pass through raw to the widget")
    assert(v == SECRET_VAL, "secret value must pass through raw (NOT skipped/zeroed)")
end

-- Case 4: known-zero max (no damage yet, non-secret) → empty bar
do
    local mn, mx, v = ComputeBarFill(0, { totalAmount = 0 }, 0, DEATHS, nil)
    assert(mn == 0 and mx == 1 and v == 0, "zero max renders empty")
end

-- Case 5: nil max → empty bar (no divide-by-nil, no fault)
do
    local mn, mx, v = ComputeBarFill(0, { totalAmount = nil }, nil, DEATHS, nil)
    assert(mn == 0 and mx == 1 and v == 0, "nil max renders empty")
end

-- Case 6: nil deathsType is defensive (enum missing at load) — must not crash
do
    local mn, mx, v = ComputeBarFill(0, { totalAmount = 250 }, 800, nil, nil)
    assert(mn == 0 and mx == 800 and v == 250, "nil deathsType handled")
end

-- Case 7: breakdown call shape — nil meterType AND nil deathsType (spell rows
-- have no per-second / Deaths handling), incl. a secret spell amount.
do
    local mn, mx, v = ComputeBarFill(nil, { totalAmount = 75 }, 300, nil, nil)
    assert(mn == 0 and mx == 300 and v == 75, "breakdown shape (plain) handled")
    local SECRET = setmetatable({}, {})
    local mn2, mx2, v2 = ComputeBarFill(nil, { totalAmount = SECRET }, SECRET, nil,
        function(x) return x == SECRET end)
    assert(mn2 == 0 and mx2 == SECRET and v2 == SECRET, "breakdown secret amount passes raw")
end

print("OK: damage_meter_bar_fill_test")
