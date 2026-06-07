-- tests/unit/chat_frame1_runtime_no_detach_test.lua
-- Run: lua tests/unit/chat_frame1_runtime_no_detach_test.lua
--
-- Regression: loading chat_frame1.lua on the runtime chat path made login call
-- ChatFrame1Sizing.DetachFromEditMode / SyncToStored. Those paths reparent and
-- reposition ChatFrame1 from addon code. Blizzard's generated widget docs mark
-- SetParent, SetPoint, and ClearAllPoints protected, and Blizzard's chat event
-- handler later enters HistoryKeeper's protected accessIDs table. If the chat
-- frame's event script is already tainted, channel notices fault there.

local function noop() end

local function readAll(path)
    local f = assert(io.open(path, "rb"), "failed to open " .. path)
    local d = f:read("*a"); f:close()
    return d:gsub("\r\n", "\n")
end

local chatXML = readAll("QUI.toc")
assert(not chatXML:find([[modules\chat\settings\chat_frame1.lua]], 1, true),
    "runtime QUI.toc must not load ChatFrame1 sizing/detach helper")

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

assert(loadfile("QUI_Chat/chat/chat.lua"))("QUI", ns)

assert(eventFrame and eventFrame.OnEvent, "chat module should install an event handler")
eventFrame.OnEvent(eventFrame, "ADDON_LOADED", "QUI")
eventFrame.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
eventFrame.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
eventFrame.OnEvent(eventFrame, "CHALLENGE_MODE_RESET")
eventFrame.OnEvent(eventFrame, "ENCOUNTER_END")
eventFrame.OnEvent(eventFrame, "PVP_MATCH_COMPLETE")
eventFrame.OnEvent(eventFrame, "PVP_MATCH_INACTIVE")

for i = 1, #calls do
    assert(calls[i] ~= "detach" and calls[i] ~= "sync",
        "runtime chat module must not call ChatFrame1Sizing." .. calls[i])
end

print("OK: chat_frame1_runtime_no_detach_test")
