-- tests/unit/damage_meter_formatters_test.lua
-- Run: lua tests/unit/damage_meter_formatters_test.lua
--
-- Extract FormatDuration + FormatNumber bodies from the core file and exercise
-- them standalone. Both must be pure: no WoW globals, no upvalue access.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local src = readAll("modules/damage_meter/damage_meter.lua")

local function extract(funcName)
    local pat = "(local function " .. funcName .. ".-\nend\n)"
    local chunk = src:match(pat)
    assert(chunk, "could not locate " .. funcName .. " in damage_meter.lua")
    return chunk
end

local loader = assert(loadstring(extract("FormatDuration") .. extract("FormatNumber")
    .. "\nreturn FormatDuration, FormatNumber"))
local FormatDuration, FormatNumber = loader()

-- FormatDuration
assert(FormatDuration(0)   == "",       "0s renders empty")
assert(FormatDuration(nil) == "",       "nil renders empty")
assert(FormatDuration(5)   == "0:05",   "5s -> 0:05")
assert(FormatDuration(65)  == "1:05",   "65s -> 1:05")
assert(FormatDuration(3725) == "62:05", "3725s -> 62:05 (no hour wrap in Phase 1)")

-- FormatNumber — compact (Phase 1)
assert(FormatNumber(0,        "compact") == "",        "0 -> empty")
assert(FormatNumber(nil,      "compact") == "",        "nil -> empty")
assert(FormatNumber(999,      "compact") == "999",     "<1k -> raw")
assert(FormatNumber(1500,     "compact") == "1.5K",    "1500 -> 1.5K")
assert(FormatNumber(2400000,  "compact") == "2.4M",    "2.4M")

-- FormatNumber — minimal (Phase 2): drops fractional digits
assert(FormatNumber(0,        "minimal") == "",        "minimal: 0 -> empty")
assert(FormatNumber(999,      "minimal") == "999",     "minimal: <1k -> raw")
assert(FormatNumber(1500,     "minimal") == "1K",      "minimal: 1500 -> 1K")
assert(FormatNumber(2400000,  "minimal") == "2M",      "minimal: 2.4M -> 2M")
assert(FormatNumber(9990,     "minimal") == "9K",      "minimal: floors to 9K")

-- FormatNumber — complete (Phase 2): thousands separator
assert(FormatNumber(0,        "complete") == "",          "complete: 0 -> empty")
assert(FormatNumber(999,      "complete") == "999",       "complete: <1k -> raw")
assert(FormatNumber(1500,     "complete") == "1,500",     "complete: 1500 -> 1,500")
assert(FormatNumber(2400000,  "complete") == "2,400,000", "complete: 2.4M -> 2,400,000")
assert(FormatNumber(1234567890, "complete") == "1,234,567,890",
    "complete: handles 10-digit values")

-- Unknown format falls back to compact (defensive)
assert(FormatNumber(1500, "garbage") == "1.5K",
    "unknown format must fall back to compact")

print("OK: damage_meter_formatters_test")
