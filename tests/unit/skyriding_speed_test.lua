-- tests/unit/skyriding_speed_test.lua
-- Run: lua tests/unit/skyriding_speed_test.lua

local function noop() end

BASE_MOVEMENT_SPEED = 7
UIParent = {}
C_Timer = {
    After = noop,
    NewTimer = function()
        return { Cancel = noop }
    end,
}
C_PlayerInfo = {
    GetGlidingInfo = function()
        return false, false, 0
    end,
}

function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterEvent = noop,
        SetScript = noop,
    }
end

local ns = {
    QUI = {},
    Addon = {},
    Helpers = {
        AssetPath = "",
        CreateDBGetter = function()
            return function()
                return { enabled = true }
            end
        end,
        ApplyCooldownFromSpell = noop,
        IsSecretValue = function(value)
            return value == "secret"
        end,
        SafeValue = function(value, fallback)
            if value == "secret" then return fallback end
            return value
        end,
    },
}

assert(loadfile("QUI_QoL/qol/skyriding.lua"))("QUI", ns)

local api = assert(ns.QUI.Skyriding, "skyriding API should be exported")

assert(type(api.ResolveDisplaySpeed) == "function",
    "skyriding should expose display speed resolution for regression coverage")
assert(type(api.FormatSpeedText) == "function",
    "skyriding should expose speed text formatting for regression coverage")

local speed = api.ResolveDisplaySpeed(false, 0, function()
    return 14
end)
assert(speed == 14,
    "when not currently gliding, speed display should fall back to GetUnitSpeed currentSpeed")

speed = api.ResolveDisplaySpeed(true, 65, function()
    error("GetUnitSpeed should not be queried while gliding")
end)
assert(speed == 65,
    "when gliding, speed display should use C_PlayerInfo.GetGlidingInfo forwardSpeed")

speed = api.ResolveDisplaySpeed(false, 0, function()
    return "secret"
end)
assert(speed == nil,
    "secret movement speed should be treated as unavailable instead of used in arithmetic")

assert(api.FormatSpeedText(14, "PERCENT", 7) == "200%",
    "percentage speed should be relative to base run speed")
assert(api.FormatSpeedText(65, "PERCENT", 7) == "929%",
    "skyriding forwardSpeed should format as movement speed percentage")
assert(api.FormatSpeedText(9.5, "RAW", 7) == "9.5",
    "raw speed should keep one decimal place")
assert(api.FormatSpeedText(nil, "PERCENT", 7) == nil,
    "missing speed should not produce a misleading 0% readout")

print("OK: skyriding_speed_test")
