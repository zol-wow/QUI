-- tests/unit/cdm_bar_renderer_mirror_ticker_test.lua
-- Run: lua tests/unit/cdm_bar_renderer_mirror_ticker_test.lua

local SECRET = newproxy and newproxy(false) or setmetatable({}, {})

function issecretvalue(value)
    return value == SECRET
end

local now = 1000
function GetTime() return now end
function InCombatLockdown() return true end
function UnitClass() return "Rogue", "ROGUE" end
RAID_CLASS_COLORS = {}
C_Timer = { After = function() end }

local createdFrames = {}

function CreateFrame()
    local frame = { shown = true }
    createdFrames[#createdFrames + 1] = frame
    function frame:SetScript(script, fn)
        if script == "OnUpdate" then self.onUpdate = fn end
    end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:CreateAnimationGroup()
        local group = {}
        function group:CreateAnimation() return { SetDuration = function() end } end
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
        IsSecretValue = function(value) return value == SECRET end,
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
    LSM = { Fetch = function() return nil end },
    SafeCallMethodIfPresent = function() end,
    CDMSpellData = { GetSpellOverride = function() return nil end },
}

assert(loadfile("QUI_CDM/cdm/cdm_bar_renderer.lua"))("QUI", ns)

local bars = assert(ns.CDMBars, "CDMBars table was not exported")
local mirrorFrame = assert(createdFrames[2], "paired mirror ticker frame was not created")
assert(type(mirrorFrame.onUpdate) == "function", "mirror ticker has no OnUpdate script")

local pool = bars:GetActiveBars()
local function resetPool()
    for i = #pool, 1, -1 do pool[i] = nil end
end

local BROADSIDE_ICON = 135988
local BROADSIDE_NAME = "Broadside"

local function newBlzChild(cooldownID, active)
    return {
        cooldownID = cooldownID,
        IsActive = function() return active end,
        Icon = { Icon = { GetTexture = function() return BROADSIDE_ICON end } },
        Bar = {
            GetValue = function() return 12 end,
            GetMinMaxValues = function() return 0, 30 end,
            Duration = { GetText = function() return "12" end },
            Name = { GetText = function() return BROADSIDE_NAME end },
        },
    }
end

local function newQUIBar(cooldownID, blzChild)
    local written = {}
    local bar = {
        _isOwnedBar = true,
        _spellID = 315508,
        _spellEntry = { id = 315508, spellID = 315508, viewerType = "trackedBar" },
        _blzCooldownID = cooldownID,
        _blzChild = blzChild,
        written = written,
        StatusBar = {
            SetMinMaxValues = function(_, minValue, maxValue)
                written.minValue, written.maxValue = minValue, maxValue
            end,
            SetValue = function(_, value) written.value = value end,
        },
        NameText = { SetText = function(_, text) written.name = text end },
        DurationText = { SetText = function(_, text) written.duration = text end },
        IconTexture = { SetTexture = function(_, texture) written.icon = texture end },
        PermanentFill = { SetAlpha = function() end },
        IsShown = function() return false end,
        Show = function() end,
        Hide = function() end,
    }
    return bar
end

local function tick()
    mirrorFrame.onUpdate(mirrorFrame, 0.02)
end

local function newViewer(...)
    local frames = { ... }
    return {
        itemFramePool = {
            EnumerateActive = function()
                local i = 0
                return function()
                    i = i + 1
                    return frames[i]
                end
            end,
        },
    }
end

---------------------------------------------------------------------------
resetPool()
local blz = newBlzChild(7001, false)
local bar = newQUIBar(7001, blz)
bar._active = false
pool[1] = bar
mirrorFrame:Show()
tick()

assert(bar.written.name == BROADSIDE_NAME,
    "mirror must forward the live Blizzard name even when the QUI bar is inactive and hidden")
assert(bar.written.icon == BROADSIDE_ICON,
    "mirror must forward the live Blizzard icon even when the QUI bar is inactive and hidden")
assert(bar.written.duration == "12", "mirror must forward the live duration text")
assert(bar.written.value == 12 and bar.written.maxValue == 30,
    "mirror must forward the live fill")
assert(mirrorFrame.shown == true, "ticker must stay armed while a paired bar exists")

---------------------------------------------------------------------------
_G.BuffBarCooldownViewer = newViewer()
bar._blzChild = nil
bar.written.name = nil
tick()

assert(mirrorFrame.shown == true,
    "a transient pairing miss must not disarm the ticker -- it would never re-arm in combat")
assert(bar.written.name == nil, "a missed pairing must not mirror anything")

---------------------------------------------------------------------------
now = now + 1
bar._blzChildMissAt = nil
_G.BuffBarCooldownViewer = newViewer(newBlzChild(9999, true), blz)
tick()

assert(bar.written.name == BROADSIDE_NAME,
    "re-pairing must scan the item pool and match on cooldownID")

---------------------------------------------------------------------------
now = now + 1
bar._blzChild = nil
bar._blzChildMissAt = nil
bar.written.name = nil
_G.BuffBarCooldownViewer = { GetChildren = function() error("GetChildren must never be called") end }
tick()

assert(bar.written.name == nil, "a viewer without an item pool must yield no pairing")
assert(mirrorFrame.shown == true, "a missing item pool must not disarm the ticker")

---------------------------------------------------------------------------
resetPool()
mirrorFrame:Show()
tick()
assert(mirrorFrame.shown == false, "ticker must disarm once no owned bar carries a pairing")

---------------------------------------------------------------------------
resetPool()
local inactiveBlz = newBlzChild(7002, false)
local inactiveBar = newQUIBar(7002, inactiveBlz)
pool[1] = inactiveBar
mirrorFrame:Hide()
bars:UpdateOwnedBarAura(inactiveBar)

assert(inactiveBar._active == false, "an inactive Blizzard child must leave the bar inactive")
assert(mirrorFrame.shown == true,
    "pairing a bar must arm the ticker regardless of active state -- arming only when active leaves it dark")

print("OK: cdm_bar_renderer_mirror_ticker_test")
