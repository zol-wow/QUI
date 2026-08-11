-- tests/unit/chat_sounds_will_play_predicate_test.lua
-- Run: lua tests/unit/chat_sounds_will_play_predicate_test.lua
-- Contract for Sounds.WillPlayForEvent — the predicate QUI_QoL event_sounds
-- queries to defer its whisper alert when chat owns it. It must mirror the
-- TryPlayForEvent gating (lockdown, chat-enabled, newMessageSound.enabled,
-- matching entry, non-"None" sound) WITHOUT playing anything or touching
-- UnitGUID (sender self-suppression is a caller-time concern, not knowable here).
-- luacheck: globals CreateFrame PlaySoundFile hooksecurefunc UnitGUID

local settings = {
    enabled = true,
    newMessageSound = {
        enabled = true,
        entries = {
            { channel = "whisper", sound = "Ping" },
        },
    },
}

function CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript() end
    return frame
end

local soundsPlayed = 0
local unitGUIDCalls = 0
local locked = false

function PlaySoundFile() soundsPlayed = soundsPlayed + 1 end
function UnitGUID() unitGUIDCalls = unitGUIDCalls + 1; return "Player-0001" end
function hooksecurefunc() error("sounds must not install ANY secure hooks") end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
    },
    LSM = {
        Fetch = function(_, _, name) return name end,
    },
    QUI = {
        Chat = {
            MessageStore = { OnAppend = function() end },
            _internals = {
                GetSettings = function() return settings end,
                IsChatEnabled = function(s) return s and s.enabled ~= false end,
                IsChatMessagingLockedDown = function() return locked end,
            },
        },
    },
}

assert(loadfile("QUI_Chat/chat/sounds.lua"))("QUI", ns)

local WillPlay = ns.QUI.Chat.Sounds.WillPlayForEvent
assert(type(WillPlay) == "function", "Sounds.WillPlayForEvent must be published")

-- Baseline: configured whisper entry, unlocked, chat enabled → true for both
-- whisper events (the "whisper" channel matches CHAT_MSG_WHISPER and _BN_).
assert(WillPlay("CHAT_MSG_WHISPER") == true, "configured whisper entry plays")
assert(WillPlay("CHAT_MSG_BN_WHISPER") == true, "whisper channel covers BN whisper")
assert(WillPlay("CHAT_MSG_GUILD") == false, "no guild entry → will not play")
assert(WillPlay("CHAT_MSG_GUILD_DISCORD") == false, "no guild entry → GUILD_DISCORD will not play either")

-- Wave 3 Task 4: CHAT_MSG_GUILD_DISCORD mirrors CHAT_MSG_GUILD in every
-- SOUND_CHANNEL_EVENTS entry that lists GUILD (guild, guild_officer, all).
settings.newMessageSound.entries[#settings.newMessageSound.entries + 1] =
    { channel = "guild_officer", sound = "Ding" }
assert(WillPlay("CHAT_MSG_GUILD") == true, "guild_officer entry plays for CHAT_MSG_GUILD")
assert(WillPlay("CHAT_MSG_GUILD_DISCORD") == true,
    "guild_officer entry also plays for CHAT_MSG_GUILD_DISCORD (mirrors GUILD)")
assert(WillPlay("CHAT_MSG_OFFICER") == true, "guild_officer entry still plays for CHAT_MSG_OFFICER")
settings.newMessageSound.entries[#settings.newMessageSound.entries] = nil

-- Combat messaging lockdown: chat plays nothing → predicate false (QoL falls back)
locked = true
assert(WillPlay("CHAT_MSG_WHISPER") == false, "lockdown → chat will not play")
locked = false

-- newMessageSound disabled
settings.newMessageSound.enabled = false
assert(WillPlay("CHAT_MSG_WHISPER") == false, "newMessageSound disabled → false")
settings.newMessageSound.enabled = true

-- Chat takeover disabled
settings.enabled = false
assert(WillPlay("CHAT_MSG_WHISPER") == false, "chat takeover off → false")
settings.enabled = true

-- Entry present but sound is "None" → false (treated as "will not play")
settings.newMessageSound.entries[1].sound = "None"
assert(WillPlay("CHAT_MSG_WHISPER") == false, "None sound → false")
settings.newMessageSound.entries[1].sound = "Ping"

-- Predicate must be side-effect free: never plays, never queries UnitGUID.
assert(soundsPlayed == 0, "WillPlayForEvent must not play any sound")
assert(unitGUIDCalls == 0, "WillPlayForEvent must not query UnitGUID")

print("OK: chat_sounds_will_play_predicate_test")
