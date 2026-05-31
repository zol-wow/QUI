---------------------------------------------------------------------------
-- QUI Chat Module — Sounds
-- Per-channel new-message sound alerts (LSM-aware), driven from rendered
-- ChatFrame:AddMessage hooks so addon code does not participate in the
-- protected chat-event dispatch path.
--
-- Extracted from chat.lua during Phase 0 refactor.
---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

-- Defensive: assert _internals exists before reading state through it.
-- Set up by chat.lua, which loads first per chat.xml.
local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: sounds.lua loaded before chat.lua. Check chat.xml — chat.lua must precede sounds.lua.")

ns.QUI.Chat.Sounds = ns.QUI.Chat.Sounds or {}
local Sounds = ns.QUI.Chat.Sounds

local LSM = ns.LSM

---------------------------------------------------------------------------
-- New message sound (SharedMedia compatible)
---------------------------------------------------------------------------
local SOUND_CHANNEL_EVENTS = {
    guild = { "CHAT_MSG_GUILD" },
    officer = { "CHAT_MSG_OFFICER" },
    guild_officer = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" },
    party = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" },
    raid = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" },
    whisper = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" },
    all = {
        "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    },
}

local hookedFrames = setmetatable({}, { __mode = "k" })
local newWindowHooksInstalled = false
local recentLineKeys = {}
local recentLineOrder = {}
local RECENT_LINE_LIMIT = 128

local function IsSecret(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value)
end

local function IsChatMessagingLockedDown()
    return I.IsChatMessagingLockedDown and I.IsChatMessagingLockedDown()
end

local function EventMatchesChannel(event, channel)
    local events = SOUND_CHANNEL_EVENTS[channel]
    if not events then return false end
    for _, registeredEvent in ipairs(events) do
        if registeredEvent == event then
            return true
        end
    end
    return false
end

local function PlayConfiguredMessageSound(entry)
    local soundName = entry.sound or "None"
    if soundName and soundName ~= "None" and LSM then
        local path = LSM:Fetch("sound", soundName)
        if path and type(path) == "string" then
            PlaySoundFile(path, "Master")
        end
    end
end

local function GetRenderedLineKey(event, eventArgs)
    if IsSecret(event) or type(event) ~= "string" or event == "" then return nil end
    if type(eventArgs) ~= "table" then return nil end

    -- ChatInfoDocumentation marks payload arg 11, lineID, as NeverSecret for
    -- chat-message events including CHAT_MSG_CHANNEL.
    local lineID = eventArgs[11]
    local lineIDType = type(lineID)
    if lineIDType ~= "number" and lineIDType ~= "string" then return nil end
    return event .. ":" .. tostring(lineID)
end

local function IsDuplicateRenderedLine(event, eventArgs)
    local key = GetRenderedLineKey(event, eventArgs)
    if not key then return false end
    if recentLineKeys[key] then return true end

    recentLineKeys[key] = true
    recentLineOrder[#recentLineOrder + 1] = key
    if #recentLineOrder > RECENT_LINE_LIMIT then
        local oldKey = table.remove(recentLineOrder, 1)
        if oldKey then
            recentLineKeys[oldKey] = nil
        end
    end
    return false
end

local function GetRenderedSenderGUID(eventArgs)
    if IsSecret(eventArgs) or type(eventArgs) ~= "table" then return nil end
    local guid = eventArgs[12]
    if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

local function GetReadablePlayerGUID()
    if not UnitGUID then return nil end
    local guid = UnitGUID("player")
    if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

local function IsSelfRenderedMessage(eventArgs)
    local senderGUID = GetRenderedSenderGUID(eventArgs)
    if not senderGUID then return false end

    local playerGUID = GetReadablePlayerGUID()
    if not playerGUID then return false end

    return senderGUID == playerGUID
end

local function FindConfiguredSoundEntry(event, entries)
    for _, entry in ipairs(entries) do
        local channel = entry.channel or "guild_officer"
        if channel ~= "all" and EventMatchesChannel(event, channel) then
            return entry
        end
    end

    for _, entry in ipairs(entries) do
        local channel = entry.channel or "guild_officer"
        if channel == "all" and EventMatchesChannel(event, channel) then
            return entry
        end
    end
    return nil
end

local function PlayNewMessageSound(event, eventArgs)
    if IsChatMessagingLockedDown() then
        return
    end

    local settings = I.GetSettings()
    if not (I.IsChatEnabled and I.IsChatEnabled(settings))
        or not settings.newMessageSound or not settings.newMessageSound.enabled then
        return
    end

    local entries = settings.newMessageSound.entries
    if not entries or #entries == 0 then return end

    local entry = FindConfiguredSoundEntry(event, entries)
    if not entry then return end
    if IsSelfRenderedMessage(eventArgs) then return end
    if IsDuplicateRenderedLine(event, eventArgs) then return end

    PlayConfiguredMessageSound(entry)
end

local function HookSoundFrame(frame)
    if not frame or hookedFrames[frame] then return end
    if not frame.AddMessage then return end
    if not hooksecurefunc then return end

    hookedFrames[frame] = true
    hooksecurefunc(frame, "AddMessage", function(_, _, _, _, _, _, _, _, event, eventArgs)
        PlayNewMessageSound(event, eventArgs)
    end)
end

local function HookAllSoundFrames()
    local nWindows = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, nWindows do
        HookSoundFrame(_G["ChatFrame" .. i])
    end
end

local function ScheduleHookAllSoundFrames()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, HookAllSoundFrames)
    else
        HookAllSoundFrames()
    end
end

local function InstallSoundHooks()
    HookAllSoundFrames()

    if newWindowHooksInstalled or not hooksecurefunc then return end
    newWindowHooksInstalled = true

    if _G.FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", ScheduleHookAllSoundFrames)
    end
    if _G.FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", ScheduleHookAllSoundFrames)
    end
end

local function SetupNewMessageSound()
    InstallSoundHooks()
end

Sounds.Setup = SetupNewMessageSound
