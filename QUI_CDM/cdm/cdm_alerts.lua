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

RefreshSoundKits()

function Alerts.GetSoundKitOptions()
    if not soundKitsLoaded then RefreshSoundKits() end
    local options = {}
    for i = 1, #soundKitOptions do
        options[i] = { value = soundKitOptions[i].value, text = soundKitOptions[i].text }
    end
    return options
end

local function PlaySoundKit(soundEnum)
    if not soundKitByEnum[soundEnum] then RefreshSoundKits() end
    local soundKitID = soundKitByEnum[soundEnum]
    if not (soundKitID and SoundAPI and SoundAPI.PlaySoundWithOptions) then return false end
    return ns.SafeCall("best-effort-style", SoundAPI.PlaySoundWithOptions, {
        soundKitID = soundKitID,
        uiSoundSubType = "Gameplay SFX",
    })
end

-- "kit:<enum>" keys resolve through the Cooldown Manager sound table; every
-- other key is a media name or path that ns.Announce plays directly.
if ns.Announce and ns.Announce.RegisterSoundResolver then
    ns.Announce.RegisterSoundResolver(function(key)
        local soundEnum = tonumber(key:match("^kit:(%d+)$"))
        if not soundEnum then return false end
        return PlaySoundKit(soundEnum) == true
    end)
end

local function PlaySoundKey(soundKey)
    if type(soundKey) ~= "string" or soundKey == "" or soundKey == "None" then return false end
    if ns.Announce and ns.Announce.PlaySound then
        return ns.Announce.PlaySound(soundKey)
    end
    local soundEnum = tonumber(soundKey:match("^kit:(%d+)$"))
    if soundEnum then return PlaySoundKit(soundEnum) end
    local sound = ns.LSM and ns.LSM:Fetch("sound", soundKey, true)
    if not sound and soundKey:find("[\\/]") then sound = soundKey end
    if not sound or type(PlaySoundFile) ~= "function" then return false end
    return ns.SafeCall("best-effort-style", PlaySoundFile, sound, "Master")
end

local function Speak(text)
    if ns.Announce and ns.Announce.Speak then
        return ns.Announce.Speak(text)
    end
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
    if Alerts.IsNativeSoundRegistered(entry, eventKey) then return false end
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

local nativeRegistrations = {}
local nativeEvents = {}
local nativeStatuses = {}
local refreshPending = false
local nativeDisabled = false
local reconciling = false
local auraEvents = { auraApplied = "OnAuraApplied", auraRemoved = "OnAuraRemoved" }

local function NativeSignature(record)
    if record.kind == "file" then
        return table.concat({ "file", record.unit, record.spellID, record.trigger, record.sound }, ":")
    end
    return table.concat({ "viewer", tostring(record.layout), record.cooldownID, record.event, record.payload }, ":")
end

local function FindNativeAlert(alerts, event, payload)
    for _, alert in ipairs(alerts or {}) do
        if alert[1] == Enum.CooldownViewerAlertType.Sound and alert[2] == event and alert[3] == payload then
            return alert
        end
    end
end

local function GetNativeAlerts(record)
    local info = record.layout and record.layout.cooldownInfo
    local block = info and info[record.cooldownID]
    return block and block.alerts
end

local function EventKey(entry, eventKey)
    local config = entry.quiAlerts and entry.quiAlerts[eventKey] or {}
    return table.concat({ entry.type or "spell", entry.id or entry.spellID or "", entry.auraUnit or "",
        eventKey, config.mode or "sound", config.sound or "", config.text or "" }, ":")
end

function Alerts.IsNativeSoundRegistered(entry, eventKey)
    return entry and auraEvents[eventKey] and nativeEvents[EventKey(entry, eventKey)] == true or false
end

local function ResolveNativeSelection(entry, eventKey)
    local config = entry and entry.quiAlerts and entry.quiAlerts[eventKey]
    if not (auraEvents[eventKey] and type(config) == "table" and config.enabled == true) then return nil end
    local runs = ns.CDMCustomAuraRuns
    local auraConfig = runs and runs.ResolveAuraConfig and runs.ResolveAuraConfig(entry)
    if not auraConfig then return nil, ns.L["This entry has no aura spell IDs for sound registration."] end
    local payload
    if config.mode == "tts" then
        payload = Enum and Enum.CooldownViewerSound and Enum.CooldownViewerSound.TextToSpeech
    elseif type(config.sound) == "string" then
        payload = tonumber(config.sound:match("^kit:(%d+)$"))
    end
    if config.mode == "tts" or payload then
        local cooldownID = entry.cooldownID
        if not cooldownID then
            local index = ns.CDMIndex
            for spellID in pairs(auraConfig.includeSpellIDs) do
                local record = index and index.Get and index.Get(spellID)
                if record and record.cooldownID then cooldownID = record.cooldownID; break end
            end
        end
        if not cooldownID then
            return nil, ns.L["This aura needs a Blizzard cooldown entry for sound kits or text to speech. Sound files work with custom aura entries."]
        end
        local event = Enum and Enum.CooldownViewerAlertEventType
            and Enum.CooldownViewerAlertEventType[auraEvents[eventKey]]
        if payload == nil or event == nil then return nil, ns.L["Blizzard cooldown sound alerts are not loaded yet."] end
        local api = _G.C_CooldownViewer
        if api and api.GetValidAlertTypes then
            local ok, valid = ns.SafeCall("best-effort-style", api.GetValidAlertTypes, cooldownID)
            local found = false
            if ok and type(valid) == "table" then
                for _, candidate in ipairs(valid) do
                    if candidate == event then found = true; break end
                end
            end
            if not found then return nil, ns.L["Blizzard does not support this aura alert event for the selected cooldown entry."] end
        end
        return { kind = "viewer", cooldownID = cooldownID, event = event, payload = payload },
            config.mode == "tts" and ns.L["Blizzard aura text to speech reads the spell name; custom alert text is used only for previews and cooldown alerts."] or nil
    end
    local sound = config.sound
    if sound == nil or sound == "" or sound == "None" then return nil end
    if ("|" .. (auraConfig.filter or "") .. "|"):find("|PLAYER|", 1, true) then
        return nil, ns.L["Native aura sound files cannot restrict alerts to your own casts. Use a supported Blizzard sound kit or text to speech for this aura."]
    end
    if type(sound) == "string" then sound = ns.LSM and ns.LSM:Fetch("sound", sound, true) or sound end
    if type(sound) ~= "string" and type(sound) ~= "number" then return nil, ns.L["The selected aura sound file could not be resolved."] end
    return { kind = "file", auraConfig = auraConfig, sound = sound,
        trigger = Enum and Enum.UnitAuraSoundTrigger
            and Enum.UnitAuraSoundTrigger[eventKey == "auraApplied" and "Added" or "Removed"]
            or (eventKey == "auraApplied" and 0 or 2) }
end

function Alerts.GetNativeSoundStatus(containerKey, entry, eventKey)
    if not entry then return nil end
    local statuses = nativeStatuses[containerKey]
    local status = statuses and statuses[EventKey(entry, eventKey)]
    if not status then
        local _, reason = ResolveNativeSelection(entry, eventKey)
        status = reason
    end
    local config = entry.quiAlerts and entry.quiAlerts[eventKey]
    if auraEvents[eventKey] and type(config) == "table" and (config.mode == "tts"
        or (type(config.sound) == "string" and config.sound:match("^kit:%d+$"))) then
        local instruction = ns.L["Configure or disable this aura sound in Blizzard's Cooldown Manager settings."]
        if status and status ~= instruction then return status .. "\n" .. instruction end
        return instruction
    end
    return status
end

local function RemoveNativeRegistration(record)
    if record.kind == "file" then
        local api = _G.C_UnitAuras
        if not (api and api.RemoveAuraSound) then return false end
        return ns.SafeCall("best-effort-style", api.RemoveAuraSound, record.id)
    end
    return true
end

local function RegisterNativeSound(record)
    if record.kind == "file" then
        local api = _G.C_UnitAuras
        if not (api and api.AddAuraSound and api.RemoveAuraSound) then
            return false, ns.L["Native aura sound registration is not available yet."]
        end
        local info = { unitToken = record.unit, spellID = record.spellID, outputChannel = "Master" }
        if type(record.sound) == "number" then info.soundFileID = record.sound else info.soundFileName = record.sound end
        local ok, id = ns.SafeCall("best-effort-style", api.AddAuraSound, record.trigger, info)
        if not ok or not id then return false, ns.L["Blizzard could not register this aura sound. It will retry after combat or a configuration refresh."] end
        record.id = id
        return true
    end
    record.alert = FindNativeAlert(GetNativeAlerts(record), record.event, record.payload)
    if record.alert then return true end
    return false, ns.L["Configure or disable this aura sound in Blizzard's Cooldown Manager settings."]
end

function Alerts.ReconcileNativeSounds(disabled)
    if disabled ~= nil then nativeDisabled = disabled == true end
    if reconciling then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
    reconciling = true
    local desired = {}
    nativeEvents, nativeStatuses = {}, {}
    local settingsFrame = _G.CooldownViewerSettings
    local provider = settingsFrame and settingsFrame.dataProvider
    local manager = provider and provider.displayData and not provider.displayDataDirty and provider.layoutManager
    local layout = manager and manager.layouts and manager.layouts[manager.activeLayoutID]
    local containers = ns.CDMContainers
    local enabled = not nativeDisabled and (not ns.CDMShared or ns.CDMShared.IsRuntimeEnabled())
    local all = enabled and containers and containers.GetContainers and containers:GetContainers() or {}
    for _, container in ipairs(all) do
        local settings, containerKey = container.settings, container.key
        if settings and settings.enabled ~= false then
            local entries
            if settings.specSpecific and ns.CDMSpellData and ns.CDMSpellData.GetSpecEntries then
                entries = ns.CDMSpellData:GetSpecEntries(containerKey)
            end
            entries = entries or (settings.containerType == "customBar" and settings.entries or settings.ownedSpells) or {}
            for _, entry in ipairs(entries) do
                if entry.enabled ~= false then
                    for eventKey in pairs(auraEvents) do
                        local selection, reason = ResolveNativeSelection(entry, eventKey)
                        local key = EventKey(entry, eventKey)
                        nativeStatuses[containerKey] = nativeStatuses[containerKey] or {}
                        nativeStatuses[containerKey][key] = reason
                        if selection then
                            local records = {}
                            if selection.kind == "file" then
                                for spellID in pairs(selection.auraConfig.includeSpellIDs) do
                                    records[#records + 1] = { kind = "file", unit = selection.auraConfig.unit,
                                        spellID = spellID, sound = selection.sound, trigger = selection.trigger }
                                end
                            elseif manager then
                                selection.manager, selection.layout = manager, layout
                                records[1] = selection
                            else
                                nativeStatuses[containerKey][key] = ns.L["Blizzard cooldown alert settings are not loaded yet."]
                            end
                            for _, record in ipairs(records) do
                                local signature = NativeSignature(record)
                                local existing = desired[signature]
                                if not existing then record.users = {}; desired[signature] = record; existing = record end
                                existing.users[#existing.users + 1] = { container = containerKey, key = key }
                            end
                        end
                    end
                end
            end
        end
    end
    for signature, record in pairs(nativeRegistrations) do
        local nextRecord = desired[signature]
        local missing = false
        if record.kind == "viewer" then
            local alerts = GetNativeAlerts(record)
            missing = FindNativeAlert(alerts, record.event, record.payload) ~= record.alert
        end
        if not nextRecord or missing or (record.kind == "viewer" and (record.layout ~= layout or record.manager ~= manager)) then
            if RemoveNativeRegistration(record) then nativeRegistrations[signature] = nil end
        end
    end
    for signature, record in pairs(desired) do
        local existing = nativeRegistrations[signature]
        local ok, reason = existing ~= nil, nil
        if not existing then
            ok, reason = RegisterNativeSound(record)
            if ok then nativeRegistrations[NativeSignature(record)] = record end
        end
        for _, user in ipairs(record.users) do
            if ok then nativeEvents[user.key] = true else nativeStatuses[user.container][user.key] = reason end
        end
    end
    reconciling = false
end

function Alerts.RequestNativeSoundRefresh(disabled)
    nativeDisabled = disabled == true
    if refreshPending then return end
    if C_Timer and C_Timer.After then
        refreshPending = true
        C_Timer.After(0, function()
            refreshPending = false
            Alerts.ReconcileNativeSounds()
        end)
    else
        Alerts.ReconcileNativeSounds()
    end
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        if not refreshPending and not reconciling then Alerts.RequestNativeSoundRefresh(nativeDisabled) end
    end, Alerts)
end

if type(CreateFrame) == "function" then
    local soundKitFrame = CreateFrame("Frame")
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "COOLDOWN_VIEWER_DATA_LOADED" }) do
        soundKitFrame:RegisterEvent(event)
    end
    soundKitFrame:SetScript("OnEvent", function(self, event)
        if not soundKitsLoaded then RefreshSoundKits() end
        if soundKitsLoaded and self.UnregisterEvent then self:UnregisterEvent("ADDON_LOADED") end
        if event == "PLAYER_REGEN_ENABLED" then Alerts.ReconcileNativeSounds()
        else Alerts.RequestNativeSoundRefresh(nativeDisabled) end
    end)
end
