-- tests/unit/chat_sounds_lockdown_test.lua
-- Run: lua tests/unit/chat_sounds_lockdown_test.lua
-- Single-path contract: sounds install NO AddMessage hooks and NO
-- pre-dispatch CHAT_MSG_* handlers — only the store subscriber. Lockdown is
-- checked FIRST (before settings/GUID work): a locked-down append plays
-- nothing and never queries UnitGUID.
-- luacheck: globals CreateFrame PlaySoundFile hooksecurefunc UnitGUID

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
    function frame:SetScript() end
    return frame
end

local soundsPlayed = 0
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

function hooksecurefunc()
    error("sounds must not install ANY secure hooks (single store path)")
end

local subscriber
local ns = {
    Helpers = {
        IsSecretValue = function(value) return value == secret end,
    },
    LSM = {
        Fetch = function(_, _, name) return name end,
    },
    QUI = {
        Chat = {
            MessageStore = {
                OnAppend = function(fn) subscriber = fn end,
            },
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

assert(not next(eventRegistrations), "chat sounds must not register pre-dispatch CHAT_MSG_* handlers")
assert(type(subscriber) == "function", "store subscriber installed")

-- Lockdown active: no sound, and lockdown is checked BEFORE any GUID work
subscriber({ e = "CHAT_MSG_PARTY", gid = "Player-0002", s = false })
assert(soundsPlayed == 0, "chat sounds must not play while chat messaging lockdown is active")
assert(unitGUIDCalls == 0, "lockdown must short-circuit before any UnitGUID query")

-- Unlocked: plays from the store path
locked = false
subscriber({ e = "CHAT_MSG_PARTY", gid = "Player-0002", s = false })
assert(soundsPlayed == 1, "chat sounds should play from the store path when unlocked")

-- Own message: readable GUIDs match → suppressed
subscriber({ e = "CHAT_MSG_PARTY", gid = "Player-0001", s = false })
assert(soundsPlayed == 1, "chat sounds must suppress own party messages when both GUIDs are readable")

-- Absent sender GUID (capture strips secrets to nil): cannot self-suppress → play
local unitGUIDCallsBefore = unitGUIDCalls
subscriber({ e = "CHAT_MSG_PARTY", s = false })
assert(unitGUIDCalls == unitGUIDCallsBefore, "nil sender GUID must not be compared to UnitGUID")
assert(soundsPlayed == 2, "chat sounds should not suppress when sender GUID is absent")

print("OK: chat_sounds_lockdown_test")
