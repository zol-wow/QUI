-- tests/unit/cdm_bars_show_rearm_test.lua
-- Run: lua tests/unit/cdm_bars_show_rearm_test.lua

local afterCallbacks = {}
C_Timer = {
    After = function(_, callback)
        afterCallbacks[#afterCallbacks + 1] = callback
    end,
}

function InCombatLockdown() return false end
function UnitClass() return "Death Knight", "DEATHKNIGHT" end
RAID_CLASS_COLORS = {}

function CreateFrame()
    local frame = {}
    function frame:SetScript() end
    function frame:CreateAnimationGroup()
        local group = {}
        function group:CreateAnimation()
            return { SetDuration = function() end }
        end
        function group:SetLooping() end
        function group:SetScript() end
        function group:IsPlaying() return false end
        function group:Play() end
        function group:Stop() end
        return group
    end
    return frame
end

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
        IsEditModeActive = function() return false end,
        IsLayoutModeActive = function() return false end,
        SafeToNumber = function(value) return value end,
        SafeValue = function(value, fallback)
            if value == nil then return fallback end
            return value
        end,
    },
    Addon = {
        db = { profile = { hudLayering = { buffBar = 5 } } },
        PixelRound = function(_, value) return value end,
        GetHUDFrameLevel = function(_, value) return 200 + (value or 0) end,
    },
    LSM = {
        Fetch = function() return nil end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_bar_renderer.lua"))("QUI", ns)

local bars = assert(ns.CDMBars, "CDMBars table was not exported")
local pool = bars:GetActiveBars()
for i = #pool, 1, -1 do
    pool[i] = nil
end

local durObj = { token = "duration-object" }
local timerBinds = 0
local lastInterpolation
local lastDirection
local shown = false

local statusBar = {
    SetSize = function() end,
    SetOrientation = function() end,
    ClearAllPoints = function() end,
    SetPoint = function() end,
    SetFrameStrata = function() end,
    SetFrameLevel = function() end,
    SetTimerDuration = function(_, duration, interpolation, direction)
        assert(duration == durObj, "show re-arm should preserve the active DurationObject")
        timerBinds = timerBinds + 1
        lastInterpolation = interpolation
        lastDirection = direction
    end,
}

local bar = {
    _isOwnedBar = true,
    _spellID = 48707,
    _spellEntry = {
        id = 48707,
        spellID = 48707,
        name = "Anti-Magic Shell",
        kind = "aura",
        type = "spell",
        viewerType = "trackedBar",
    },
    _active = true,
    _durObj = durObj,
    _cSideFill = true,
    StatusBar = statusBar,
    SetSize = function() end,
    SetAlpha = function() end,
    SetFrameStrata = function() end,
    SetFrameLevel = function() end,
    ClearAllPoints = function() end,
    SetPoint = function() end,
    IsShown = function() return shown end,
    Show = function() shown = true end,
    Hide = function() shown = false end,
}

pool[1] = bar

local container = {
    SetFrameStrata = function() end,
    SetFrameLevel = function() end,
    SetSize = function() end,
}

local settings = {
    enabled = true,
    iconDisplayMode = "active",
    inactiveMode = "hide",
    barWidth = 215,
    barHeight = 25,
    spacing = 2,
    useClassColor = false,
    borderSize = 0,
    textSize = 14,
}

bars:LayoutBars(container, settings)

assert(shown == true,
    "layout should show an active hidden bar")
assert(timerBinds == 1,
    "layout should immediately re-arm a DurationObject timer when an active bar is first shown")
assert(lastInterpolation == 0,
    "show re-arm should use Immediate interpolation")
assert(lastDirection == 1,
    "show re-arm should use RemainingTime direction")
assert(#afterCallbacks == 1,
    "layout should schedule a one-frame re-arm for parent/container show timing")

afterCallbacks[1]()

assert(timerBinds == 2,
    "deferred show re-arm should bind the DurationObject again after layout settles")

bars:LayoutBars(container, settings)

assert(timerBinds == 2,
    "layout should not re-arm an already-shown active bar every refresh")

print("OK: cdm_bars_show_rearm_test")
