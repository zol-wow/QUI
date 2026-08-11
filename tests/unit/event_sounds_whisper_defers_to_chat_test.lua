-- tests/unit/event_sounds_whisper_defers_to_chat_test.lua
-- Run: lua tests/unit/event_sounds_whisper_defers_to_chat_test.lua
-- QUI_QoL event_sounds plays a per-event alert (whisper/readycheck/lfg/rez/mail).
-- Whisper is the ONLY event that overlaps the QUI Chat per-channel new-message
-- sound. To avoid a double ping, event_sounds defers whisper to chat whenever
-- chat is actively configured to play it (queried via
-- _G.QUI.Chat.Sounds.WillPlayForEvent). It must:
--   * suppress whisper when chat will play,
--   * still play whisper when chat will NOT (disabled/None/lockdown/unloaded),
--   * leave the non-overlapping events (ready check, etc.) untouched.
-- luacheck: globals CreateFrame PlaySoundFile QUI

local generalSettings = {
    eventSounds = {
        enabled     = true,
        whisper     = "WhisperPing",
        readyCheck  = "ReadyPing",
        lfgProposal = "None",
        resurrect   = "None",
        mail        = "None",
    },
}

local onEvent
function CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript(scriptType, fn)
        if scriptType == "OnEvent" then onEvent = fn end
    end
    return frame
end

local lastPath
local played = 0
function PlaySoundFile(path) played = played + 1; lastPath = path end

-- Chat predicate is toggled per-case.
local chatWillPlay = false
QUI = {
    Chat = {
        Sounds = {
            WillPlayForEvent = function() return chatWillPlay end,
        },
    },
}

local ns = {
    Helpers = {
        CreateDBGetter = function() return function() return generalSettings end end,
    },
    LSM = {
        Fetch = function(_, _, name) return name end,
    },
}

assert(loadfile("modules/qol/event_sounds.lua"))("QUI_QoL", ns)
assert(type(onEvent) == "function", "event_sounds must install an OnEvent handler")

local function fire(event) onEvent(nil, event) end

-- Chat WILL play whisper → event_sounds defers (no ping), both whisper events.
chatWillPlay = true
played = 0
fire("CHAT_MSG_WHISPER")
fire("CHAT_MSG_BN_WHISPER")
assert(played == 0, "whisper must defer to chat when chat owns it")

-- Non-whisper events are never gated by the chat predicate.
played, lastPath = 0, nil
fire("READY_CHECK")
assert(played == 1 and lastPath == "ReadyPing", "ready check plays regardless of chat whisper ownership")

-- Chat will NOT play (disabled/None/lockdown) → event_sounds plays the fallback.
chatWillPlay = false
played, lastPath = 0, nil
fire("CHAT_MSG_WHISPER")
assert(played == 1 and lastPath == "WhisperPing", "whisper plays when chat will not")

-- Chat module absent entirely → fallback still plays.
QUI = nil
played = 0
fire("CHAT_MSG_BN_WHISPER")
assert(played == 1, "whisper plays when chat module is unloaded")

-- Master gate: eventSounds disabled suppresses everything, whisper included.
QUI = { Chat = { Sounds = { WillPlayForEvent = function() return false end } } }
generalSettings.eventSounds.enabled = false
played = 0
fire("CHAT_MSG_WHISPER")
fire("READY_CHECK")
assert(played == 0, "disabled eventSounds plays nothing")
generalSettings.eventSounds.enabled = true

print("OK: event_sounds_whisper_defers_to_chat_test")
