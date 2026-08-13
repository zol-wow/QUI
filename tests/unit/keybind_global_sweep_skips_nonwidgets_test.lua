-- Run: lua tests/unit/keybind_global_sweep_skips_nonwidgets_test.lua

local function noop() end

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function issecretvalue() return false end
function InCombatLockdown() return false end
function GetTime() return 2 end
function GetSpecialization() return nil end
function GetSpecializationInfo() return nil end
function GetInventoryItemID() return nil end
function GetMacroInfo() return nil end
function GetMacroSpell() return nil end
function GetActionText() return nil end
function GetActionInfo(action)
    if action == 7 then return "spell", 4242 end
    return nil
end

UIParent = {}
C_Item = { GetItemInfo = function() return nil end }
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. tostring(id) } end }
C_Timer = { After = noop }
C_Widget = {
    IsFrameWidget = function(object)
        return type(object) == "table" and rawget(object, "isFrameWidget") == true
    end,
}

function CreateFrame()
    local frame = {}
    function frame:SetAllPoints() end
    function frame:CreateFontString() return { SetFont = noop, SetText = noop, Hide = noop, Show = noop } end
    function frame:RegisterEvent() end
    function frame:SetScript() end
    function frame:Hide() end
    function frame:Show() end
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

print("OK: keybind_global_sweep_skips_nonwidgets_test")
