-- tests/unit/chat_sounds_lockdown_test.lua
-- Run: lua tests/unit/chat_sounds_lockdown_test.lua
-- luacheck: globals CreateFrame PlaySoundFile hooksecurefunc C_Timer NUM_CHAT_WINDOWS ChatFrame1 ChatFrame2 UnitGUID

local function noop() end
local unpack = unpack

local settings = {
    enabled = true,
    newMessageSound = {
        enabled = true,
        entries = {
            { channel = "party", sound = "Ping" },
        },
    },
}

local eventRegistrations = {}
function CreateFrame()
    local frame = {}
    function frame:RegisterEvent(event) eventRegistrations[event] = true end
    function frame:UnregisterEvent(event) eventRegistrations[event] = nil end
    function frame:SetScript(script, handler)
        if script == "OnEvent" then frame.OnEvent = handler end
    end
    return frame
end

local hasSecretChecks = 0
local soundsPlayed = 0
local soundHooks = 0
local unitGUIDCalls = 0
local locked = true
local secret = { __secret = true }

function PlaySoundFile()
    soundsPlayed = soundsPlayed + 1
end

function UnitGUID(unit)
    unitGUIDCalls = unitGUIDCalls + 1
    assert(unit == "player", "self-message suppression should only query the player GUID")
    return "Player-0001"
end

function hooksecurefunc(target, method, func)
    assert(type(target) == "table", "sounds must hook rendered chat frames, not global chat events")
    assert(method == "AddMessage", "sounds must hook AddMessage")
    local original = target[method] or noop
    target[method] = function(self, ...)
        local results = { original(self, ...) }
        func(self, ...)
        return unpack(results)
    end
    soundHooks = soundHooks + 1
end

C_Timer = {
    After = function(_, callback) callback() end,
}

local function newChatFrame()
    local frame = { messages = {} }
    function frame:AddMessage(...)
        self.messages[#self.messages + 1] = {...}
    end
    return frame
end

NUM_CHAT_WINDOWS = 2
ChatFrame1 = newChatFrame()
ChatFrame2 = newChatFrame()

local ns = {
    Helpers = {
        IsSecretValue = function(value) return value == secret end,
        HasSecretValue = function()
            hasSecretChecks = hasSecretChecks + 1
            return true
        end,
    },
    LSM = {
        Fetch = function(_, _, name) return name end,
    },
    QUI = {
        Chat = {
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                IsChatMessagingLockedDown = function() return locked end,
            },
        },
    },
}

assert(loadfile("modules/chat/sounds.lua"))("QUI", ns)
ns.QUI.Chat.Sounds.Setup()

assert(not eventRegistrations.CHAT_MSG_PARTY, "chat sounds must not register pre-dispatch CHAT_MSG_* handlers")
assert(soundHooks == 2, "chat sounds should hook rendered AddMessage on chat frames")

ChatFrame1:AddMessage(
    "secret text",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_PARTY",
    { [11] = 1001 }
)

assert(hasSecretChecks == 0, "chat sounds must not inspect party payloads during chat messaging lockdown")
assert(soundsPlayed == 0, "chat sounds must not play while chat messaging lockdown is active")

locked = false
ChatFrame1:AddMessage(
    "plain text",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_PARTY",
    { [11] = 1002, [12] = "Player-0002" }
)
assert(soundsPlayed == 1, "chat sounds should play from rendered AddMessage when unlocked")

ChatFrame2:AddMessage(
    "same line rendered in another tab",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_PARTY",
    { [11] = 1002, [12] = "Player-0002" }
)
assert(soundsPlayed == 1, "chat sounds should dedupe a line rendered into multiple chat frames")

ChatFrame1:AddMessage(
    "own party text",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_PARTY",
    { [11] = 1003, [12] = "Player-0001" }
)
assert(soundsPlayed == 1, "chat sounds must suppress own party messages when both GUIDs are readable")

local unitGUIDCallsBeforeSecretGuid = unitGUIDCalls
ChatFrame1:AddMessage(
    "secret sender text",
    1, 1, 1,
    1, 0, 0,
    "CHAT_MSG_PARTY",
    { [11] = 1004, [12] = secret }
)
assert(unitGUIDCalls == unitGUIDCallsBeforeSecretGuid, "secret sender GUID must not be compared to UnitGUID")
assert(soundsPlayed == 2, "chat sounds should not suppress when sender GUID is secret")

print("OK: chat_sounds_lockdown_test")
