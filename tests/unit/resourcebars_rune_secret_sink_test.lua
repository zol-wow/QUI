local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local source = readFile("QUI_ResourceBars/resourcebars/resourcebars.lua")

assert(not source:find("GetRuneCooldown", 1, true),
    "rune state must not be inspected in Lua")
assert(not source:find("RuneTimerOnUpdate", 1, true),
    "rune recharge state must not drive a Lua timer")
assert(source:find("function QUICore:UpdateFragmentedPowerDisplay(bar, resource, isVertical, current)", 1, true),
    "fragment rendering must receive the raw power value")
assert(source:find("runeFrame:SetMinMaxValues(pos - 1, pos)", 1, true),
    "each rune pip must use a fixed C-side range")
assert(source:find("runeFrame:SetValue(current)", 1, true),
    "each rune pip must receive the raw power value")
assert(source:find('if valueType == "secret" and resource ~= Enum.PowerType.Runes then', 1, true),
    "secret rune power must reach fragmented C sinks")
assert(source:find('if valueType ~= "secret" and not max then', 1, true),
    "secret rune max must not be truth-tested")
assert(source:find('bar.TextValue:SetFormattedText("%d", displayValue)', 1, true),
    "rune text must use a C formatting sink")

print("PASS resourcebars_rune_secret_sink_test")
