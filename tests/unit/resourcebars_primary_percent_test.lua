local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_ResourceBars/resourcebars/resourcebars.lua")

local start_pos = src:find("local function GetPrimaryResourceValue(resource, cfg)", 1, true)
assert(start_pos, "could not locate GetPrimaryResourceValue")
local end_pos = src:find("\nend\n", start_pos, true)

local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
local restore = SecretSentinel.InstallSecretStub()

Helpers = {
    IsSecretValue = function(value)
        return issecretvalue and issecretvalue(value) or false
    end,
    HasSecretValue = function(...)
        for i = 1, select("#", ...) do
            if issecretvalue and issecretvalue((select(i, ...))) then return true end
        end
        return false
    end,
}

Enum = { PowerType = { Mana = 0, Fury = 17 } }
math_floor = math.floor
HAS_UNIT_POWER_PERCENT = true

local powerCurrent, powerMax, pctValue = 40, 100, 40
function ReadPlayerPowerPair() return powerCurrent, powerMax, false end
function GetPowerPct() return pctValue end

local GetPrimaryResourceValue = assert(loadstring(
    src:sub(start_pos, end_pos + 4) .. "\nreturn GetPrimaryResourceValue"))()

do
    local _, _, displayValue, valueType = GetPrimaryResourceValue(Enum.PowerType.Fury, { showPercent = true })
    assert(valueType == "percent" and displayValue == 40,
        "the showPercent checkbox is generic on both settings pages, so percent must apply to EVERY " ..
        "resource — gating it on Enum.PowerType.Mana silently ignored the option on Fury, Rage, Energy…")
end

do
    local _, _, _, valueType = GetPrimaryResourceValue(Enum.PowerType.Mana, { showPercent = true })
    assert(valueType == "percent", "mana must keep working")
end

do
    local _, _, _, valueType = GetPrimaryResourceValue(Enum.PowerType.Fury, {})
    assert(valueType == "number", "percent is opt-in")
end

do
    local secretPct = SecretSentinel.MakeSecretSentinel()
    pctValue = secretPct
    local _, _, displayValue, valueType = GetPrimaryResourceValue(Enum.PowerType.Fury, { showPercent = true })
    assert(valueType == "percent" and displayValue == secretPct,
        "a secret percent must stay percent and reach SetFormattedText — downgrading it to the raw " ..
        "current value is what made the option look dead in combat")
    pctValue = 40
end

do
    powerMax = SecretSentinel.MakeSecretSentinel()
    local max, _, _, valueType = GetPrimaryResourceValue(Enum.PowerType.Fury, { showPercent = true })
    assert(valueType == "percent" and max == powerMax,
        "a secret max must not be compared against, and must pass through untouched")
    powerMax = 100
end

do
    powerMax = nil
    local max = GetPrimaryResourceValue(Enum.PowerType.Fury, {})
    assert(max == nil,
        "absence is the only bail left — a `max <= 0` compare would throw on a secret, so presence " ..
        "is tested with type() and a zero max simply renders an empty bar")
    powerMax = 100
end

SecretSentinel.RestoreSecretStub(restore)

print("OK: resourcebars_primary_percent_test")
