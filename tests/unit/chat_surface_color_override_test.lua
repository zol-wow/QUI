-- tests/unit/chat_surface_color_override_test.lua
-- Run: lua tests/unit/chat_surface_color_override_test.lua
-- luacheck: globals CreateFrame

local function noop() end

local settings = {
    enabled = true,
    glass = {
        enabled = true,
        bgAlpha = 0.42,
        bgColor = { 0, 0, 0 },
    },
}

local function createStateTable()
    local state = setmetatable({}, { __mode = "k" })
    return state, function(key)
        local value = state[key]
        if not value then
            value = {}
            state[key] = value
        end
        return value
    end
end

function CreateFrame()
    return {
        RegisterEvent = noop,
        UnregisterEvent = noop,
        SetScript = noop,
    }
end

local skinBgCalls = 0
local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function() return settings end
        end,
        CreateStateTable = createStateTable,
        IsSecretValue = function() return false end,
        GetSkinBgColorWithOverride = function(_, moduleKey)
            skinBgCalls = skinBgCalls + 1
            assert(moduleKey == "chat", "chat surface must request the chat skin background")
            return 0.20, 0.30, 0.40, 0.90
        end,
        GetSkinBgColor = function()
            return 0.50, 0.60, 0.70, 0.90
        end,
        GetSkinBorderColor = function()
            return 0.70, 0.80, 0.90, 1
        end,
    },
    UIKit = {},
    QUI = {
        Chat = {
            Sounds = { Setup = noop },
            Skinning = {
                SkinAll = noop,
                StyleAllTabs = noop,
            },
            Cleanup = {},
            EditBoxBasics = {},
            EditBoxHistory = {
                InitializeForFrame = noop,
            },
            Copy = {
                SetupURLClick = noop,
            },
        },
    },
}

assert(loadfile("modules/chat/chat.lua"))("QUI", ns)

local getColors = assert(ns.QUI.Chat._internals.GetChatSurfaceColors, "chat surface color helper must be exported")

local bg = getColors(settings)
assert(bg[1] == 0.20 and bg[2] == 0.30 and bg[3] == 0.40, "factory black without alpha should follow the skin background")
assert(bg[4] == 0.42, "chat surface should keep glass.bgAlpha")
assert(skinBgCalls == 1, "default black path should call the skin background helper")

settings.glass.bgColor = { 0, 0, 0, 1 }
bg = getColors(settings)
assert(bg[1] == 0 and bg[2] == 0 and bg[3] == 0, "picker-written black with alpha must be honored as an explicit override")
assert(bg[4] == 0.42, "explicit black should still use glass.bgAlpha")
assert(skinBgCalls == 1, "explicit picker black must not fall back to the skin background")

settings.glass.bgColor = { 0.11, 0.12, 0.13 }
bg = getColors(settings)
assert(bg[1] == 0.11 and bg[2] == 0.12 and bg[3] == 0.13, "non-black glass.bgColor remains an explicit override")

settings.glass.enabled = false
bg = getColors(settings)
assert(bg[4] == 0, "disabled chat background should make the custom display fill transparent")

print("OK: chat_surface_color_override_test")
