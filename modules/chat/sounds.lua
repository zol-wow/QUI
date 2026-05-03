---------------------------------------------------------------------------
-- QUI Chat Module — Sounds
-- Per-channel new-message sound alerts (LSM-aware), with self-message
-- skip and combat-safe GUID/name comparison guarded by Helpers.IsSecretValue.
--
-- Extracted from chat.lua during Phase 0 refactor. No behavior change.
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

local soundEventFrame = nil
local registeredSoundEvents = {}

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

local function PlayNewMessageSound(event, ...)
    local settings = I.GetSettings()
    if not settings or not settings.newMessageSound or not settings.newMessageSound.enabled then
        return
    end

    local entries = settings.newMessageSound.entries
    if not entries or #entries == 0 then return end

    -- Skip messages from self (never play when we are the sender).
    -- In restricted contexts (raids/M+) whisper payloads and UnitName/UnitGUID
    -- can return secret values; comparing or string-indexing those taints the
    -- chat event dispatch and makes Blizzard's ChatHistory_GetAccessID fail on
    -- its forbidden `accessIDs` table. Bail out of the self-check rather than
    -- taint — worst case we play one duplicate sound on our own message.
    local guid = select(12, ...)
    local myGUID = UnitGUID("player")
    if guid and myGUID
        and not Helpers.IsSecretValue(guid)
        and not Helpers.IsSecretValue(myGUID)
        and guid == myGUID then
        return
    end

    local author = select(2, ...)
    local playerName = UnitName("player")
    if author and playerName
        and type(author) == "string"
        and not Helpers.IsSecretValue(author)
        and not Helpers.IsSecretValue(playerName) then
        local ok, hasRealm = pcall(string.find, author, "-", 1, true)
        if ok then
            if hasRealm then
                local playerRealm = GetNormalizedRealmName and GetNormalizedRealmName()
                if playerRealm and not Helpers.IsSecretValue(playerRealm)
                    and author == (playerName .. "-" .. playerRealm) then
                    return
                end
            elseif author == playerName then
                return
            end
        end
    end

    -- Prefer exact channel entries first; only fall back to "all".
    for _, entry in ipairs(entries) do
        local channel = entry.channel or "guild_officer"
        if channel ~= "all" and EventMatchesChannel(event, channel) then
            PlayConfiguredMessageSound(entry)
            return
        end
    end

    for _, entry in ipairs(entries) do
        local channel = entry.channel or "guild_officer"
        if channel == "all" and EventMatchesChannel(event, channel) then
            PlayConfiguredMessageSound(entry)
            return
        end
    end
end

local function SetupNewMessageSound()
    local settings = I.GetSettings()
    if not settings or not settings.newMessageSound or not settings.newMessageSound.enabled then
        if soundEventFrame then
            for event in pairs(registeredSoundEvents) do
                soundEventFrame:UnregisterEvent(event)
                registeredSoundEvents[event] = nil
            end
        end
        return
    end

    local allEvents = {}
    local entries = settings.newMessageSound.entries
    if entries then
        for _, entry in ipairs(entries) do
            local channel = entry.channel or "guild_officer"
            local events = SOUND_CHANNEL_EVENTS[channel]
            if events then
                for _, e in ipairs(events) do
                    allEvents[e] = true
                end
            end
        end
    end

    if not soundEventFrame then
        soundEventFrame = CreateFrame("Frame")
        soundEventFrame:SetScript("OnEvent", function(self, event, ...)
            PlayNewMessageSound(event, ...)
        end)
    end

    for event in pairs(registeredSoundEvents) do
        if not allEvents[event] then
            soundEventFrame:UnregisterEvent(event)
            registeredSoundEvents[event] = nil
        end
    end

    for event in pairs(allEvents) do
        if not registeredSoundEvents[event] then
            soundEventFrame:RegisterEvent(event)
            registeredSoundEvents[event] = true
        end
    end
end

Sounds.Setup = SetupNewMessageSound
