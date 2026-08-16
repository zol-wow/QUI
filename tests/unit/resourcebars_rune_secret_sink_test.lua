local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local source = readFile("QUI_ResourceBars/resourcebars/resourcebars.lua")

local getterStart = assert(source:find("local function GetSecondaryResourceValue(resource)", 1, true))
local getterEnd = assert(source:find("\nend\n\nlocal function GetCurrentSpecID", getterStart, true))
local getter = source:sub(getterStart, getterEnd)
local runeStart = assert(getter:find("if resource == Enum.PowerType.Runes then", 1, true))
local runeEnd = assert(getter:find("\n    end", runeStart, true))
local runeBody = getter:sub(runeStart, runeEnd)

assert(not source:find("GetRuneCooldown", 1, true),
    "rune state must not be inspected in Lua")
assert(not source:find("RuneTimerOnUpdate", 1, true),
    "rune recharge state must not drive a Lua timer")
assert(not source:find("ShouldUnitPowerMaxBeSecret", 1, true),
    "rune rendering must not branch on predicted secrecy")
assert(runeBody:find('local current = UnitPower("player", resource)', 1, true),
    "rune current must be read raw")
assert(runeBody:find('local max = UnitPowerMax("player", resource)', 1, true),
    "rune max must be read raw")
assert(not runeBody:find("ReadPlayerPowerPair", 1, true),
    "rune current and max must not be classified")
assert(not runeBody:find("IsSecretValue", 1, true),
    "rune current and max must not be probed")
assert(source:find("function QUICore:UpdateFragmentedPowerDisplay(bar, resource, isVertical, current)", 1, true),
    "fragment rendering must receive the raw power value")
assert(source:find("runeFrame:SetMinMaxValues(pos - 1, pos)", 1, true),
    "each rune pip must use a fixed C-side range")
assert(source:find("runeFrame:SetValue(current)", 1, true),
    "each rune pip must receive the raw power value")
assert(source:find('if valueType == "secret" then', 1, true),
    "non-rune secret resources must retain their sink path")
assert(not source:find('if valueType == "secret" and resource ~= Enum.PowerType.Runes then', 1, true),
    "runes must not need a secret-path exception")
assert(source:find('if type(max) == "nil" then', 1, true),
    "max absence must be checked without truth-testing a secret")
assert(source:find('bar.TextValue:SetFormattedText("%d", displayValue)', 1, true),
    "rune text must use a C formatting sink")

print("PASS resourcebars_rune_secret_sink_test")
