-- tests/unit/chat_frame1_detach_before_skinning_test.lua
-- Run: lua tests/unit/chat_frame1_detach_before_skinning_test.lua
--
-- Regression guard for ChatFrame1/Edit Mode taint surfacing in Blizzard's
-- chat history path during restricted chat messaging. The chat module must
-- detach ChatFrame1 before any QUI skinning/layout pass touches it.

local function noop() end

local calls = {}
local function record(name)
    calls[#calls + 1] = name
end

local settings = {
    enabled = true,
    timestamps = { enabled = false },
    urls = { enabled = false },
    modifiers = {},
    hyperlinks = { coordinates = false, friendlyURLs = false },
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

ChatFrameUtil = { AddMessageEventFilter = noop }
function ChatFrame_AddMessageEventFilter() end

function hooksecurefunc() end

C_Timer = { After = function(_, callback) callback() end }
C_ChatInfo = {
    _locked = false,
    InChatMessagingLockdown = function()
        return C_ChatInfo._locked
    end,
}

function date() return "12:34" end
function geterrorhandler() return function(err) error(err, 2) end end
function InCombatLockdown() return false end

local eventFrame
function CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript(script, handler)
        if script == "OnEvent" then
            eventFrame = frame
            frame.OnEvent = handler
        end
    end
    return frame
end

NUM_CHAT_WINDOWS = 1
ChatFrame1 = {}
DEFAULT_CHAT_FRAME = ChatFrame1

local ns = {
    Helpers = {
        CreateDBGetter = function()
            return function() return settings end
        end,
        CreateStateTable = createStateTable,
        IsSecretValue = function() return false end,
        HasSecretValue = function() return false end,
    },
    UIKit = {},
    QUI = {
        ChatFrame1Sizing = {
            DetachFromEditMode = function()
                record("detach")
                return true
            end,
            SyncToStored = function()
                record("sync")
                return true
            end,
        },
        Chat = {
            Sounds = { Setup = noop },
            Skinning = {
                SkinAll = function() record("skin") end,
                StyleAllTabs = function() record("tabs") end,
            },
            Cleanup = {},
            EditBoxBasics = {},
            EditBoxHistory = { InitializeForFrame = noop },
            Copy = { SetupURLClick = noop },
        },
    },
}

assert(loadfile("modules/chat/chat.lua"))("QUI", ns)

assert(eventFrame and eventFrame.OnEvent, "chat module should install an ADDON_LOADED handler")
eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "QUI")

assert(calls[1] == "detach",
    "ChatFrame1 must detach before chat skinning; first call was " .. tostring(calls[1]))
assert(calls[2] == "skin",
    "chat skinning should run after detach; second call was " .. tostring(calls[2]))
assert(calls[3] == "tabs",
    "tab styling should run after SkinAll; third call was " .. tostring(calls[3]))

print("OK: chat_frame1_detach_before_skinning_test")
