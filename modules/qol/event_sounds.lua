local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local function PlayEventSound(soundName)
    if not soundName or soundName == "None" or soundName == "" then return end
    local LSM = ns.LSM
    local path = LSM and LSM:Fetch("sound", soundName)
    if path and type(path) == "string" then
        PlaySoundFile(path, "Master")
    end
end

local EVENT_TO_KEY = {
    CHAT_MSG_WHISPER    = "whisper",
    CHAT_MSG_BN_WHISPER = "whisper",
    READY_CHECK         = "readyCheck",
    LFG_PROPOSAL_SHOW   = "lfgProposal",
    RESURRECT_REQUEST   = "resurrect",
    LOOT_ITEM_ROLL_WON      = "lootRollWon",
    SHOW_LOOT_TOAST_UPGRADE = "lootUpgrade",
}

local LOOT_EVENTS = {
    LOOT_ITEM_ROLL_WON      = true,
    SHOW_LOOT_TOAST_UPGRADE = true,
}
local LOOT_SOUND_THROTTLE = 2
local lastLootSoundAt = 0

local WHISPER_EVENTS = {
    CHAT_MSG_WHISPER    = true,
    CHAT_MSG_BN_WHISPER = true,
}

local function ChatOwnsWhisper(event)
    local CS = _G.QUI and _G.QUI.Chat and _G.QUI.Chat.Sounds
    return CS and CS.WillPlayForEvent and CS.WillPlayForEvent(event) or false
end

local hadMail = false
local mailReady = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("READY_CHECK")
frame:RegisterEvent("LFG_PROPOSAL_SHOW")
frame:RegisterEvent("RESURRECT_REQUEST")
frame:RegisterEvent("UPDATE_PENDING_MAIL")
frame:RegisterEvent("LOOT_ITEM_ROLL_WON")
frame:RegisterEvent("SHOW_LOOT_TOAST_UPGRADE")

frame:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_PENDING_MAIL" then
        local nowMail = HasNewMail() and true or false
        local wasMail = hadMail
        hadMail = nowMail
        if mailReady and nowMail and not wasMail then
            local settings = GetSettings()
            local cfg = settings and settings.eventSounds
            if cfg and cfg.enabled then
                PlayEventSound(cfg.mail)
            end
        end
        return
    end

    local settings = GetSettings()
    local cfg = settings and settings.eventSounds
    if not cfg or not cfg.enabled then return end
    if WHISPER_EVENTS[event] and ChatOwnsWhisper(event) then return end
    if LOOT_EVENTS[event] then
        local now = GetTime()
        if now - lastLootSoundAt < LOOT_SOUND_THROTTLE then return end
        lastLootSoundAt = now
    end
    local key = EVENT_TO_KEY[event]
    if key then
        PlayEventSound(cfg[key])
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        hadMail = HasNewMail() and true or false
        mailReady = true
    end)
end
