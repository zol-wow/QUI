-- tests/unit/time_format_consolidation_test.lua
-- Run: lua tests/unit/time_format_consolidation_test.lua
--
-- The m:ss formatter used to be hand-rolled in brez_counter (twice), mplus_timer
-- (twice), combattimer, damage_meter and QUI_Debug/performance, and the copies had
-- drifted on negatives, nil and zero-padding. They now all route through the single
-- ns.Helpers.FormatMMSS in core/utils.lua.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local d = f:read("*a"); f:close()
    return (d:gsub("\r\n", "\n"))
end

local SECRET = {}
_G.Helpers = { IsSecretValue = function(v) return v == SECRET end }

local src = readAll("core/utils.lua")
local chunk = src:match("(function Helpers%.FormatMMSS.-\nend\n)")
assert(chunk, "could not locate Helpers.FormatMMSS in core/utils.lua")
assert(loadstring(chunk))()

local F = _G.Helpers.FormatMMSS

assert(F(0) == "0:00", "0 -> 0:00")
assert(F(nil) == "0:00", "nil -> 0:00")
assert(F(5) == "0:05", "5 -> 0:05")
assert(F(65) == "1:05", "65 -> 1:05")
assert(F(59.9) == "0:59", "fractional seconds floor")
assert(F(3725) == "62:05", "minutes are not wrapped at 60")
assert(F(-90) == "-1:30", "negatives carry a sign")
assert(F(-1.5) == "-0:02", "negatives floor away from zero, matching the old mplus_timer copy")

assert(F(0, true) == "00:00", "padded 0 -> 00:00")
assert(F(65, true) == "01:05", "padded 65 -> 01:05")
assert(F(3725, true) == "62:05", "padding does not truncate wide minutes")

-- Secret seconds must never reach a Lua comparison or string.format. With
-- C_StringUtil absent this degrades to empty text rather than collapsing.
assert(F(SECRET) == "", "secret seconds degrade to empty text")
_G.C_StringUtil = {
    TruncateWhenZero = function(v) assert(v == SECRET); return "42" end,
    WrapString = function(infix, prefix, suffix) return (prefix or "") .. infix .. (suffix or "") end,
}
assert(F(SECRET) == "42s", "secret seconds route through the C_StringUtil sink untouched")
_G.C_StringUtil = nil

local consumers = {
    "modules/dungeon/brez_counter.lua",
    "modules/dungeon/mplus_timer.lua",
    "modules/qol/combattimer.lua",
    "QUI_DamageMeter/damage_meter/damage_meter.lua",
    "QUI_Debug/performance.lua",
}

for _, path in ipairs(consumers) do
    local text = readAll(path)
    assert(text:find("Helpers.FormatMMSS", 1, true),
        path .. " must route m:ss formatting through Helpers.FormatMMSS")
    assert(not text:find('"%%d:%%02d"'),
        path .. " must not hand-roll an m:ss format string")
    assert(not text:find('"%%02d:%%02d"'),
        path .. " must not hand-roll a padded m:ss format string")
end

print("OK: time_format_consolidation_test")
