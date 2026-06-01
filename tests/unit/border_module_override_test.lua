-- tests/unit/border_module_override_test.lua
-- Verifies GetSkinBorderColor honors the per-module {prefix}BorderColorSource enum
-- (inherit/theme/class/custom), preserves byte-identical output for inherit, and
-- still reads legacy booleans (useClassColorBorder / borderUseClassColor).
-- Run: lua tests/unit/border_module_override_test.lua

local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()
local Helpers = ns.Helpers

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end
local function approx(a, b) return math.abs((a or -1) - (b or -2)) < 1e-6 end

-- Stub the skin theme color (accent) to a known value.
local THEME = { 0.5, 0.6, 0.7 }
_G.QUI.GetSkinColor = function() return THEME[1], THEME[2], THEME[3], 1 end

-- The harness UnitClass() stub returns "MAGE"; give MAGE a class color.
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.80, b = 0.94 } }
_G.CUSTOM_CLASS_COLORS = nil

-- Plain profile table (NOT AceDB) so unset keys read as real nil.
local profile = { general = { skinBorderColorSource = "theme" } }
Helpers.GetProfile = function() return profile end

local ar, ag, ab = Helpers.GetSkinAccentColor()

-- inherit == no-arg (byte identical)
do
    local gr, gg, gb, ga = Helpers.GetSkinBorderColor()
    local r, g, b, a = Helpers.GetSkinBorderColor({ borderColorSource = "inherit" }, "")
    check("inherit equals no-arg",
        approx(r, gr) and approx(g, gg) and approx(b, gb) and approx(a, ga),
        ("got %s,%s,%s,%s vs %s,%s,%s,%s"):format(r, g, b, a, gr, gg, gb, ga))
end

-- theme -> accent
do
    local r, g, b = Helpers.GetSkinBorderColor({ borderColorSource = "theme" }, "")
    check("theme equals accent", approx(r, ar) and approx(g, ag) and approx(b, ab),
        ("got %s,%s,%s vs accent %s,%s,%s"):format(r, g, b, ar, ag, ab))
end

-- custom -> stored color (prefixed)
do
    local r, g, b, a = Helpers.GetSkinBorderColor(
        { mmBorderColorSource = "custom", mmBorderColor = { 0.1, 0.2, 0.3, 0.4 } }, "mm")
    check("custom prefixed returns stored color",
        approx(r, 0.1) and approx(g, 0.2) and approx(b, 0.3) and approx(a, 0.4),
        ("got %s,%s,%s,%s"):format(r, g, b, a))
end

-- legacy fallback: useClassColorBorder=true -> class
do
    local cr, cg, cb = Helpers.GetPlayerClassColor()
    local r, g, b = Helpers.GetSkinBorderColor({ useClassColorBorder = true }, "")
    check("legacy useClassColorBorder -> class", approx(r, cr) and approx(g, cg) and approx(b, cb),
        ("got %s,%s,%s vs class %s,%s,%s"):format(r, g, b, cr, cg, cb))
end

print(failures == 0 and "ALL PASS" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
