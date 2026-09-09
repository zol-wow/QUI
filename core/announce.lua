-- core/announce.lua -- one place to make noise: a sound by media name, a line
-- of text-to-speech, or a chat message.
--
-- Every alert feature used to carry its own copy of the LibSharedMedia fetch
-- and the C_TTSSettings dance. This is the shared seam; the Cooldown Manager's
-- sound-kit keys ("kit:<enum>") plug in through RegisterSoundResolver so a
-- caller can hand any stored sound key here without knowing which kind it is.
local _, ns = ...

local Announce = {}
ns.Announce = Announce

local resolvers = {}

local CHAT_CHANNELS = {
    SAY = true, YELL = true, PARTY = true, RAID = true,
    INSTANCE_CHAT = true, EMOTE = true,
}
Announce.CHAT_CHANNELS = CHAT_CHANNELS

local function IsSecret(value)
    local H = ns.Helpers
    if H and H.IsSecretValue then return H.IsSecretValue(value) end
    local probe = _G.issecretvalue
    return probe ~= nil and probe(value) == true
end

local function BestEffort(fn, ...)
    if type(fn) ~= "function" then return false end
    if ns.SafeCall then
        local ok = ns.SafeCall("best-effort-style", fn, ...)
        return ok == true
    end
    return pcall(fn, ...) == true
end

-- fn(key) -> true when it played the sound, false/nil to fall through.
function Announce.RegisterSoundResolver(fn)
    if type(fn) ~= "function" then return end
    resolvers[#resolvers + 1] = fn
end

-- key: a LibSharedMedia sound name, a file path, or a resolver-owned key.
function Announce.PlaySound(key)
    if type(key) ~= "string" or key == "" or key == "None" then return false end
    for i = 1, #resolvers do
        local ok, handled = pcall(resolvers[i], key)
        if ok and handled == true then return true end
    end
    local path = ns.LSM and ns.LSM:Fetch("sound", key, true)
    if not path and key:find("[\\/]") then path = key end
    if not path then return false end
    return BestEffort(_G.PlaySoundFile, path, "Master")
end

function Announce.Speak(text)
    if type(text) ~= "string" or text == "" then return false end
    if IsSecret(text) then return false end -- @secret-policy: reject-secret-value
    local VoiceChat = _G.C_VoiceChat
    local TTS = _G.C_TTSSettings
    if not (VoiceChat and VoiceChat.SpeakText and TTS) then return false end
    local voiceType = _G.Enum and _G.Enum.TtsVoiceType and _G.Enum.TtsVoiceType.Standard or 0
    local okVoice, voiceID = pcall(TTS.GetVoiceOptionID, voiceType)
    local okRate, rate = pcall(TTS.GetSpeechRate)
    local okVolume, volume = pcall(TTS.GetSpeechVolume)
    if not (okVoice and okRate and okVolume and type(voiceID) == "number") then return false end
    return BestEffort(VoiceChat.SpeakText, voiceID, text, rate, volume, true)
end

-- Sends `message` on `channel`, falling back from RAID to PARTY when not in a
-- raid and refusing group channels outside a group. Never forwards a secret.
function Announce.Chat(message, channel)
    if type(message) ~= "string" or message == "" then return false end
    if IsSecret(message) then return false end -- @secret-policy: reject-secret-value
    channel = CHAT_CHANNELS[channel] and channel or "SAY"
    local inGroup = type(IsInGroup) == "function" and IsInGroup() == true
    local inRaid = type(IsInRaid) == "function" and IsInRaid() == true
    if channel == "RAID" and not inRaid then channel = "PARTY" end
    if channel == "INSTANCE_CHAT" and not inGroup then return false end
    if channel == "PARTY" and not inGroup then return false end
    local send = (_G.C_ChatInfo and _G.C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    return BestEffort(send, message, channel)
end
