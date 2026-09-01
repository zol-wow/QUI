local _, ns = ...

local Alerts = {}
ns.CDMAlerts = Alerts
local SoundAPI = _G.C_Sound
local TTSSettings = _G.C_TTSSettings
local VoiceChat = _G.C_VoiceChat

local soundKitByEnum = {}
local soundKitOptions = {}
local soundKitsLoaded = false

local function RefreshSoundKits()
    if InCombatLockdown and InCombatLockdown() then return false end
    local source = _G.CooldownViewerSoundData
    if type(source) ~= "table" or (canaccesstable and not canaccesstable(source)) then return false end
    wipe(soundKitByEnum)
    wipe(soundKitOptions)
    for _, category in pairs(source) do
        if type(category) == "table" and (not canaccesstable or canaccesstable(category)) then
            for _, record in ipairs(category) do
                if type(record) == "table" and (not canaccesstable or canaccesstable(record))
                    and type(record.soundEnum) == "number" and type(record.soundKitID) == "number" then
                    soundKitByEnum[record.soundEnum] = record.soundKitID
                    soundKitOptions[#soundKitOptions + 1] = {
                        value = "kit:" .. tostring(record.soundEnum),
                        text = tostring(record.text or record.soundEnum),
                    }
                end
            end
        end
    end
    table.sort(soundKitOptions, function(a, b) return a.text < b.text end)
    soundKitsLoaded = #soundKitOptions > 0
    return soundKitsLoaded
end

if not RefreshSoundKits() and type(CreateFrame) == "function" then
    local soundKitFrame = CreateFrame("Frame")
    soundKitFrame:RegisterEvent("ADDON_LOADED")
    soundKitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    soundKitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    soundKitFrame:SetScript("OnEvent", function(self)
        if RefreshSoundKits() then self:UnregisterAllEvents() end
    end)
end

function Alerts.GetSoundKitOptions()
    if not soundKitsLoaded then RefreshSoundKits() end
    local options = {}
    for i = 1, #soundKitOptions do
        options[i] = { value = soundKitOptions[i].value, text = soundKitOptions[i].text }
    end
    return options
end

local function PlaySoundKey(soundKey)
    if type(soundKey) ~= "string" or soundKey == "" or soundKey == "None" then return false end
    local soundEnum = tonumber(soundKey:match("^kit:(%d+)$"))
    if soundEnum then
        if not soundKitByEnum[soundEnum] then RefreshSoundKits() end
        local soundKitID = soundKitByEnum[soundEnum]
        if not (soundKitID and SoundAPI and SoundAPI.PlaySoundWithOptions) then return false end
        return ns.SafeCall("best-effort-style", SoundAPI.PlaySoundWithOptions, {
            soundKitID = soundKitID,
            uiSoundSubType = "Gameplay SFX",
        })
    end

    local sound = ns.LSM and ns.LSM:Fetch("sound", soundKey, true)
    if not sound and soundKey:find("[\\/]") then sound = soundKey end
    if not sound or type(PlaySoundFile) ~= "function" then return false end
    return ns.SafeCall("best-effort-style", PlaySoundFile, sound, "Master")
end

local function Speak(text)
    if type(text) ~= "string" or text == "" then return false end
    if ns.Helpers and ns.Helpers.IsSecretValue and ns.Helpers.IsSecretValue(text) then return false end
    if not (VoiceChat and VoiceChat.SpeakText and TTSSettings) then return false end
    local voiceType = Enum and Enum.TtsVoiceType and Enum.TtsVoiceType.Standard or 0
    local okVoice, voiceID = ns.SafeCall("best-effort-style", TTSSettings.GetVoiceOptionID, voiceType)
    local okRate, rate = ns.SafeCall("best-effort-style", TTSSettings.GetSpeechRate)
    local okVolume, volume = ns.SafeCall("best-effort-style", TTSSettings.GetSpeechVolume)
    if not (okVoice and okRate and okVolume and type(voiceID) == "number") then return false end
    return ns.SafeCall("best-effort-style", VoiceChat.SpeakText, voiceID, text, rate, volume, true)
end

local EVENT_SUFFIX = {
    available = " ready",
    onCooldown = " on cooldown",
    auraApplied = " applied",
    auraRemoved = " removed",
}

local function FallbackText(entry, eventKey)
    local name = entry and entry.name
    if type(name) ~= "string" or name == "" then
        name = tostring(entry and (entry.id or entry.spellID) or "Ability")
    end
    return name .. (EVENT_SUFFIX[eventKey] or "")
end

local function PlayAlert(entry, eventKey)
    local config = entry and entry.quiAlerts and entry.quiAlerts[eventKey]
    if type(config) ~= "table" or config.enabled ~= true then return false end
    if config.mode == "tts" then
        local text = type(config.text) == "string" and config.text ~= ""
            and config.text or FallbackText(entry, eventKey)
        return Speak(text)
    end
    return PlaySoundKey(config.sound)
end

function Alerts.HasEnabled(entry)
    if not (entry and type(entry.quiAlerts) == "table") then return false end
    for _, config in pairs(entry.quiAlerts) do
        if type(config) == "table" and config.enabled == true then return true end
    end
    return false
end

function Alerts.Preview(config, entry, eventKey)
    if type(config) ~= "table" then return false end
    if config.mode == "tts" then
        local text = type(config.text) == "string" and config.text ~= ""
            and config.text or FallbackText(entry, eventKey)
        return Speak(text)
    end
    return PlaySoundKey(config.sound)
end

function Alerts.GetTransitions(oldUnavailable, oldAuraActive, unavailable, auraActive)
    return oldUnavailable and not unavailable,
        not oldUnavailable and unavailable,
        not oldAuraActive and auraActive,
        oldAuraActive and not auraActive
end

local function IsUnavailable(state)
    local cooling = state.isOnCooldown == true or state.rechargeActive == true
    if state.hasCharges == true then
        return cooling and state.hasChargesRemaining ~= true
    end
    return cooling
end

local function IsAuraActive(state)
    if state.auraActive == true then return true end
    return (state.mode == "aura" or state.mode == "item-aura") and state.active == true
end

function Alerts.OnStateChanged(frame, state)
    local entry = frame and frame._spellEntry
    if not (entry and type(state) == "table") then return end
    local unavailable = IsUnavailable(state)
    local auraActive = IsAuraActive(state)
    local previous = frame._quiAlertState
    if previous and previous.key == state.key then
        local available, onCooldown, auraApplied, auraRemoved = Alerts.GetTransitions(
            previous.unavailable, previous.auraActive, unavailable, auraActive)
        if available then PlayAlert(entry, "available") end
        if onCooldown then PlayAlert(entry, "onCooldown") end
        if auraApplied then PlayAlert(entry, "auraApplied") end
        if auraRemoved then PlayAlert(entry, "auraRemoved") end
    else
        previous = previous or {}
        frame._quiAlertState = previous
    end
    previous.key = state.key
    previous.unavailable = unavailable
    previous.auraActive = auraActive
end
