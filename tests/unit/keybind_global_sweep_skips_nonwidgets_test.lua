-- Run: lua tests/unit/keybind_global_sweep_skips_nonwidgets_test.lua

local function noop() end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function issecretvalue() return false end
function InCombatLockdown() return false end
local now = 2
function GetTime() return now end
function GetSpecialization() return nil end
function GetSpecializationInfo() return nil end
function GetInventoryItemID() return nil end
function GetMacroInfo() return nil end
function GetMacroSpell() return nil end
function GetActionText() return nil end
local actionInfoCalls = 0
function GetActionInfo(action)
    actionInfoCalls = actionInfoCalls + 1
    if action == 7 then return "spell", 4242 end
    return nil
end

UIParent = {}
C_Item = { GetItemInfo = function() return nil end }
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. tostring(id) } end }
local timers = {}
C_Timer = {
    After = noop,
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end,
}
C_Widget = {
    IsFrameWidget = function(object)
        return type(object) == "table" and rawget(object, "isFrameWidget") == true
    end,
}

local frames = {}
function CreateFrame()
    local frame = { events = {}, scripts = {} }
    function frame:SetAllPoints() end
    function frame:CreateFontString() return { SetFont = noop, SetText = noop, Hide = noop, Show = noop } end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:Hide() end
    function frame:Show() end
    frames[#frames + 1] = frame
    return frame
end

local hostileTouches = 0
local hostileMeta = {}
hostileMeta.__index = function(_, key)
    if type(key) ~= "string" then return nil end
    return function()
        hostileTouches = hostileTouches + 1
        error("attempt to index field 'label' (a nil value)", 2)
    end
end

_G.ForeignWidgetWrapper = setmetatable({ type = "label", dframework = true }, hostileMeta)

_G.QUI_Bar1Button1 = {
    isFrameWidget = true,
    action = 7,
    HotKey = { GetText = function() return "F" end },
    GetName = function() return "QUI_Bar1Button1" end,
    GetObjectType = function() return "CheckButton" end,
}

local reportedErrors = {}

local core = {
    db = {
        profile = {
            keybindOverridesEnabledCDM = true,
            viewers = { EssentialCooldownViewer = { showKeybinds = true } },
            ncdm = { containers = {} },
        },
        char = { keybindOverrides = { [0] = {} } },
    },
}

local addon = {
    QUICore = core,
    SafeCall = function(_policy, fn, ...)
        local ok, a, b = pcall(fn, ...)
        if not ok then reportedErrors[#reportedErrors + 1] = a end
        return ok, a, b
    end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(obj[name], obj, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...)
        if obj == nil then return nil end
        local m = obj[name]
        if m == nil then return nil end
        return pcall(m, obj, ...)
    end,
    Helpers = {
        GetCore = function() return core end,
        GetCurrentSpecID = function() return nil end,
        CanAccessTable = function() return true end,
        CanAccessValue = function() return true end,
        CreateStateTable = function() return setmetatable({}, { __mode = "k" }) end,
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "OUTLINE" end,
    },
    FormatKeybind = function(binding) return binding end,
}

_G.QUI = addon

assert(loadfile("modules/utility/keybinds.lua"))("QUI", addon)

addon.Keybinds.RebuildCache()

assert(hostileTouches == 0,
    "the pairs(_G) sweep must not call methods on non-widget globals (ran foreign code " ..
    hostileTouches .. " time(s))")
assert(#reportedErrors == 0,
    "the sweep must not surface third-party errors: " .. tostring(reportedErrors[1]))
assert(addon.Keybinds.GetKeybindForSpell(4242) == "F",
    "the sweep must still collect real action-button widgets from _G")

local eventFrame
for _, frame in ipairs(frames) do
    if frame.events.ACTIONBAR_SLOT_CHANGED then
        eventFrame = frame
        break
    end
end
assert(eventFrame and eventFrame.scripts.OnEvent,
    "the keybind cache must listen for action-slot changes")

local callsBeforeRefresh = actionInfoCalls
eventFrame.scripts.OnEvent(eventFrame, "ACTIONBAR_SLOT_CHANGED")
now = 2.4
eventFrame.scripts.OnEvent(eventFrame, "ACTIONBAR_SLOT_CHANGED")
assert(#timers == 1 and not timers[1].cancelled,
    "action-slot bursts must retain one pending timer")
now = 2.5
timers[1].callback()
assert(#timers == 2 and actionInfoCalls == callsBeforeRefresh
    and timers[2].delay > 0.39 and timers[2].delay < 0.41,
    "an early timer must wait out the remaining quiet period without rebuilding")
now = 3
timers[2].callback()
assert(actionInfoCalls > callsBeforeRefresh,
    "the debounced action-slot refresh must rebuild the keybind cache")

print("OK: keybind_global_sweep_skips_nonwidgets_test")
