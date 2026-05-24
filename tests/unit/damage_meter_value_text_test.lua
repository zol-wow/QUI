-- tests/unit/damage_meter_value_text_test.lua
-- Run: lua tests/unit/damage_meter_value_text_test.lua
--
-- Regression test for the value-cell taint crash at
-- modules/damage_meter/damage_meter.lua:_SetRowSource. FormatNumber routes
-- secret-tagged amounts through C_StringUtil.TruncateWhenZero, whose return
-- is itself secret-tagged. The pre-fix code ran `secondaryStr == "0"` on
-- that result, which taints execution under Patch 12.0+ combat restrictions
-- and crashes the renderer.
--
-- This test extracts BuildValueText and verifies that the equality-based
-- "(0)" suppression is bypassed whenever the source value was secret —
-- proving the fix stays correct as the file evolves.

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

local loader = assert(loadstring(extract("BuildValueText")
    .. "\nreturn BuildValueText"))
local BuildValueText = loader()

-- Stubs that model secret-tagged values. SECRET_ZERO is the killer case:
-- FormatNumber returns the literal string "0" for it (mirroring what
-- C_StringUtil.TruncateWhenZero produces for a secret zero), and the old
-- code's `== "0"` check on that secret string was what crashed.
local SECRET_NUMBER = {}
local SECRET_ZERO   = {}
local function IsSecret(v) return v == SECRET_NUMBER or v == SECRET_ZERO end
local function FormatNumber(v, fmt)
    if v == SECRET_NUMBER then return "SEC" end
    if v == SECRET_ZERO   then return "0"   end
    if v == nil           then return ""    end
    if v == 0             then return ""    end
    if fmt == "compact" then
        if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
        if v >= 1e3 then return string.format("%.1fK", v / 1e3) end
    end
    return tostring(v)
end

-- Standard non-secret rendering: primary + secondary in parens.
assert(BuildValueText(1500, 999, "compact", IsSecret, FormatNumber) == "1.5K (999)",
    "standard primary + secondary render")

-- Non-secret "0" secondary is suppressed (UX cleanup for short combats).
assert(BuildValueText(1500, 0, "compact", IsSecret, FormatNumber) == "1.5K",
    "non-secret zero secondary suppressed")

-- Empty primary falls through to secondary.
assert(BuildValueText(0, 100, "compact", IsSecret, FormatNumber) == "100",
    "empty primary falls through to secondary")

-- Both empty produces empty string.
assert(BuildValueText(0, 0, "compact", IsSecret, FormatNumber) == "",
    "both empty -> empty string")

-- Both secret: render together. No equality comparison on either string.
assert(BuildValueText(SECRET_NUMBER, SECRET_NUMBER, "compact", IsSecret, FormatNumber)
    == "SEC (SEC)",
    "both secret render together")

-- KEY REGRESSION: secret-tagged value whose formatter returned literal "0".
-- Pre-fix: ran `secondaryStr == "0"` on this secret string → tainted crash.
-- Post-fix: secondarySecret short-circuits the suppression, "(0)" is kept.
-- If this assertion ever fails again, the bug at damage_meter.lua:906 is back.
assert(BuildValueText(1500, SECRET_ZERO, "compact", IsSecret, FormatNumber) == "1.5K (0)",
    "secret zero secondary keeps (0) — proves equality-based suppression is bypassed")

-- Primary secret, secondary plain.
assert(BuildValueText(SECRET_NUMBER, 500, "compact", IsSecret, FormatNumber)
    == "SEC (500)",
    "secret primary + plain secondary")

-- nil IsSecret (e.g. Helpers not loaded yet): non-secret path everywhere.
assert(BuildValueText(1500, 0, "compact", nil, FormatNumber) == "1.5K",
    "nil IsSecret falls back to non-secret path")

print("OK: damage_meter_value_text_test")
