-- tests/unit/chat_disabled_skips_editmode_detach_test.lua
-- Run: lua tests/unit/chat_disabled_skips_editmode_detach_test.lua
--
-- Regression guard: when the chat module is DISABLED (settings.enabled == false)
-- QUI must hand ChatFrame1 back to Blizzard's Edit Mode -- i.e. it must NOT
-- detach (reparent + hide Edit Mode resize/select widgets) at ADDON_LOADED.
-- The detach is a one-way customization step with no reattach path, so doing it
-- while disabled would strand chat under QUI. Sibling test
-- chat_frame1_detach_before_skinning_test.lua guards the ENABLED ordering.

local function noop() end

local calls = {}
local function record(name)
    calls[#calls + 1] = name
end

-- Master toggle OFF.
local settings = {
    enabled = false,
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

for i = 1, #calls do
    assert(calls[i] ~= "detach",
        "DISABLED chat module must not detach ChatFrame1 from Edit Mode at ADDON_LOADED; "
        .. "got detach at call #" .. i)
end

print("OK: chat_disabled_skips_editmode_detach_test")
