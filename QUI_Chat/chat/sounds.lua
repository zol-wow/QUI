---------------------------------------------------------------------------
-- QUI Chat Module — Sounds
-- Per-channel new-message sound alerts (LSM-aware).
--
-- Single-path ownership: the store subscriber (installed in Setup) owns ALL
-- windows, including the pre-PEW login window. Capture starts at
-- ADDON_LOADED so store entries exist before PLAYER_ENTERING_WORLD; no
-- AddMessage hook path exists. TryPlayForEvent is called directly from the
-- store subscriber.
--
-- Extracted from chat.lua during Phase 0 refactor.
---------------------------------------------------------------------------

local _, ns = ...
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

local function GetReadablePlayerGUID()
    if not UnitGUID then return nil end
    local guid = UnitGUID("player")
    if IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    return guid
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

-- Core: the store subscriber passes the already-resolved senderGUID
-- (entry.gid) so this never needs to unpack event payloads.
local function TryPlayForEvent(event, senderGUID)
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

    -- Self-message check: if we have a readable senderGUID, compare to the
    -- player GUID. If senderGUID is nil (secret or absent) we cannot self-
    -- suppress — play the sound.
    if senderGUID then
        local playerGUID = GetReadablePlayerGUID()
        if playerGUID and senderGUID == playerGUID then return end
    end

    PlayConfiguredMessageSound(entry)
end

local storeSubscribed = false
local function InstallStoreSubscriber()
    local Store = ns.QUI.Chat.MessageStore
    if storeSubscribed or not (Store and Store.OnAppend) then return end
    storeSubscribed = true
    Store.OnAppend(function(entry)
        if entry.s then return end -- secrets carry no playable classification
        -- Replayed login history carries its ORIGINAL event now (so it can be
        -- routed per-window like live traffic), so the e=="HISTORY" guard no
        -- longer catches it -- skip on the hist marker instead, or every login
        -- would replay a burst of message sounds.
        if entry.hist then return end
        local e = entry.e
        if e == "ADDMESSAGE" or e == "BACKFILL" or e == "HISTORY" then return end
        TryPlayForEvent(e, entry.gid)
    end)
end

local function SetupNewMessageSound()
    InstallStoreSubscriber()
end

Sounds.Setup = SetupNewMessageSound
