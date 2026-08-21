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

assert(not source:find("ShouldUnitPowerMaxBeSecret", 1, true),
    "rune rendering must not branch on predicted secrecy")
assert(runeBody:find("GetRuneCooldown(i)", 1, true),
    "rune count must use Blizzard's per-rune state API")
assert(not runeBody:find("UnitPower", 1, true),
    "rune count must not use UnitPower, which does not expose spent runes")
assert(not runeBody:find("ReadPlayerPowerPair", 1, true),
    "rune state must not use the generic secret power path")
assert(not runeBody:find("IsSecretValue", 1, true),
    "documented-clean rune cooldown values must not be classified as UnitPower secrets")
assert(source:find("function QUICore:UpdateFragmentedPowerDisplay(bar, resource, isVertical, current)", 1, true),
    "fragment rendering must retain the shared resource path")
assert(source:find("local function RuneTimerOnUpdate(bar, delta)", 1, true),
    "spent runes must animate while recharging")
assert(source:find("runeFrame:SetValue(rec.frac)", 1, true),
    "each rune pip must render its own cooldown fraction")
assert(source:find("table.sort(runeOrder, RuneDisplayLess)", 1, true),
    "ready and cooling runes must retain the reference ordering")
assert(source:find('if valueType == "secret" then', 1, true),
    "non-rune secret resources must retain their sink path")
assert(not source:find('if valueType == "secret" and resource ~= Enum.PowerType.Runes then', 1, true),
    "runes must not need a secret-path exception")
assert(source:find('if type(max) == "nil" then', 1, true),
    "max absence must be checked without truth-testing a secret")
assert(source:find('bar.TextValue:SetFormattedText("%d / %d", current, max)', 1, true),
    "fragmented current and max text must use a C formatting sink")
assert(source:find("cfg.showFragmentedPowerBarText == false", 1, true),
    "fragmented text must honor its live setting")
assert(source:find("self:OnRunePowerUpdate()", 1, true),
    "the secret RUNE_POWER_UPDATE payload must be dropped at the event boundary")

print("PASS resourcebars_rune_secret_sink_test")
