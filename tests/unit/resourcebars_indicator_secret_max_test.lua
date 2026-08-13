local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local start_pos = src:find("local function ResolveBarMax(bar, resource, max)", 1, true)
assert(start_pos, "could not locate ResolveBarMax")
local end_pos = src:find("\nend\n", start_pos, true)
assert(end_pos, "could not locate the end of ResolveBarMax")

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restore = SecretSentinel.InstallSecretStub()

Helpers = {
    IsSecretValue = function(value)
        return issecretvalue and issecretvalue(value) or false
    end,
}

local livePowerMax = 0
function UnitPowerMax(_unit, powerType)
    if powerType == 17 then return livePowerMax end
    return 0
end

local loader = assert(loadstring(src:sub(start_pos, end_pos + 4) .. "\nreturn ResolveBarMax"))
local ResolveBarMax = loader()

local bar = {}
assert(ResolveBarMax(bar, 7, 100) == 100, "a plain max must pass straight through")
assert((bar._shadowMax or {})[7] == 100, "a plain max must be remembered as shadow state")

local secretMax = SecretSentinel.MakeSecretSentinel()
assert(ResolveBarMax(bar, 7, secretMax) == 100,
    "UnitPowerMax is SecretWhenUnitPowerMaxRestricted, so a restricted max must fall back to the " ..
    "last plain one — SetPoint/SetSize are AllowedWhenUntainted and cannot take the secret")
assert((bar._shadowMax or {})[7] == 100, "a secret max must never overwrite the shadow state")

assert(ResolveBarMax(bar, 7, 6) == 6 and (bar._shadowMax or {})[7] == 6,
    "a later plain max must replace the shadow state")

local coldBar = {}
assert(ResolveBarMax(coldBar, 7, SecretSentinel.MakeSecretSentinel()) == nil,
    "a secret max with no prior plain read must resolve to nil so the caller draws nothing")

assert(ResolveBarMax(coldBar, 7, 0) == nil and coldBar._shadowMax == nil,
    "a non-positive max is never cached and resolves nil, which is the same bail the callers already take")


assert(ResolveBarMax(bar, 7, nil) == 6,
    "both UpdatePowerBarValue and UpdateSecondaryPowerBarValue return `\"secret\", nil, resource` — " ..
    "the max arrives as nil, not as a secret, so nil MUST fall back to the shadow state too")

assert(ResolveBarMax(bar, 7, 0) == 6 and bar._shadowMax[7] == 6,
    "a non-positive max is treated as unusable, not as a value: it is never cached over a good one")

local formBar = {}
assert(ResolveBarMax(formBar, 3, 100) == 100 and ResolveBarMax(formBar, 1, 60) == 60,
    "each resource keeps its own shadow max")
assert(ResolveBarMax(formBar, 1, SecretSentinel.MakeSecretSentinel()) == 60,
    "a druid swapping form mid-combat must not inherit the other resource's max")

local furyBar = {}
livePowerMax = 100
assert(ResolveBarMax(furyBar, 17, nil) == 100,
    "UpdatePowerBarValue hands out `\"secret\", nil, resource`, so the primary bar's max arrives nil " ..
    "on every secret read — the resolver must ask UnitPowerMax itself instead of trusting the value path")
assert(furyBar._shadowMax[17] == 100, "a direct read must warm the shadow state like any other")

livePowerMax = 0
assert(ResolveBarMax(furyBar, 17, nil) == 100,
    "once warm, an unreadable direct read falls back to the cache")

local coldFury = {}
assert(ResolveBarMax(coldFury, 17, nil) == nil,
    "a cold bar with no readable max must resolve nil so the caller draws nothing")

local ind_start = src:find("local function ResolveIndicatorMax(resource, max)", 1, true)
assert(ind_start, "could not locate ResolveIndicatorMax")
local ind_end = src:find("\nend\n", ind_start, true)
local ResolveIndicatorMax = assert(loadstring(
    src:sub(ind_start, ind_end + 4) .. "\nreturn ResolveIndicatorMax"))()

local secretPowerMax = SecretSentinel.MakeSecretSentinel()
assert(ResolveIndicatorMax(17, secretPowerMax) == secretPowerMax,
    "a secret max must reach the ruler StatusBar UNTOUCHED — SetMinMaxValues on a StatusBar is " ..
    "AllowedWhenTainted with the BarValue aspect, so the engine does the division")

livePowerMax = 100
assert(ResolveIndicatorMax(17, nil) == 100,
    "a nil max from the value path must be replaced by a direct UnitPowerMax read")
assert(ResolveIndicatorMax(17, 120) == 120, "a usable plain max passes through unchanged")
assert(ResolveIndicatorMax("SOUL", nil) == nil, "a string pseudo-resource has no UnitPowerMax to read")

local san_start = src:find("local function SanitizeIndicatorValues(values, maxValue)", 1, true)
assert(san_start, "could not locate SanitizeIndicatorValues")
local san_end = src:find("\nend\n", san_start, true)
math_floor, string_format, table_insert, table_remove = math.floor, string.format, table.insert, table.remove
local SanitizeIndicatorValues = assert(loadstring(
    src:sub(san_start, san_end + 4) .. "\nreturn SanitizeIndicatorValues"))()

do
    local kept = SanitizeIndicatorValues({ 20, 60, 100 }, 100)
    assert(#kept == 3 and kept[3] == 100,
        "a breakpoint equal to max is a full-bar marker and must be kept, not silently dropped")
end

do
    local kept = SanitizeIndicatorValues({ 20, 60, 100 }, SecretSentinel.MakeSecretSentinel())
    assert(#kept == 3,
        "a secret max cannot be compared against in Lua, so the range filter is skipped and the " ..
        "StatusBar clamps instead — dropping every value here is what blanked the bar in combat")
end

SecretSentinel.RestoreSecretStub(restore)

print("OK: resourcebars_indicator_secret_max_test")
