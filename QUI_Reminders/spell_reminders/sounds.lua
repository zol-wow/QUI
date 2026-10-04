local _, ns = ...
local S = { registrations = {} }
ns.SpellReminderSounds = S

function S.Resolve(name)
    if not name or name == "None" then return nil end
    if name == "QUI Reminder Bell" then return 567458 end
    return ns.LSM and ns.LSM:Fetch("sound", name, true)
end

function S.Play(name, channel)
    local sound = S.Resolve(name)
    if sound then PlaySoundFile(sound, channel or "Master") end
end

function S.Speak(text, voice)
    if not C_VoiceChat or not C_VoiceChat.SpeakText or text == "" then return end
    if not voice or voice == 0 then
        local voices = C_VoiceChat.GetTtsVoices() or {}
        voice = voices[1] and voices[1].voiceID
    end
    if voice then
        C_VoiceChat.SpeakText(voice, text, 0, 100)
    end
end

function S.Notify(config, output)
    local name = ns.SpellReminderPresentation.Name(config)
    if output.readyNotice then
        if config.readySound then S.Play(config.sound, config.soundChannel) end
        if config.ttsReady then S.Speak(config.ttsReadyText ~= "" and config.ttsReadyText or name, config.voice) end
    elseif output.earlyNotice then
        if config.earlySound then S.Play(config.sound, config.soundChannel) end
        if config.ttsEarly then S.Speak(config.ttsEarlyText ~= "" and config.ttsEarlyText or name, config.voice) end
    end
    if output.countdown then S.Speak(tostring(output.countdown), config.voice) end
end

function S.Clear()
    for key, record in pairs(S.registrations) do
        C_UnitAuras.RemoveAuraSound(record.id)
        S.registrations[key] = nil
    end
end

local function Locked()
    if InCombatLockdown() then return true end
    local restrictions, types = C_RestrictedActions, Enum.AddOnRestrictionType
    return restrictions and types and (restrictions.IsAddOnRestrictionActive(types.Combat)
        or restrictions.IsAddOnRestrictionActive(types.Encounter))
end

local function Targets(pi)
    local R, M = ns.SpellReminders, ns.SpellReminderModel
    local targets = {}
    local focus = R.Focus()
    if pi.focusSound and pi.focus.enabled and focus then targets.focus = "focus" end
    local content = IsInRaid() and "raid" or "party"
    if not pi[content .. "Sound"] then return targets end
    local focusGUID = focus and not focus.outsideGroup and focus.guid
    for _, member in ipairs(R.roster) do
        if M.WatchScope(pi, member, content, focusGUID) == content then
            targets[member.unit] = content
        end
    end
    return targets
end

function S.Reconcile(pi, enabled)
    if not C_UnitAuras or not C_UnitAuras.AddAuraSound then return end
    if not enabled or not pi then S.Clear(); return end
    if not ((pi.focusSound and pi.focus.enabled) or (pi.partySound and pi.party.enabled)
        or (pi.raidSound and pi.raid.enabled)) then S.Clear(); return end
    local sound = S.Resolve(pi.sound)
    if not sound then S.Clear(); return end
    local desired = {}
    for unit, scope in pairs(Targets(pi)) do
        for id in pairs(ns.SpellReminderModel.BuffIDs(pi, scope)) do
            local key = unit .. ":" .. id .. ":" .. tostring(sound) .. ":" .. pi.soundChannel
            local info = { unitToken = unit, spellID = id, outputChannel = pi.soundChannel }
            if type(sound) == "number" then info.soundFileID = sound else info.soundFileName = sound end
            desired[key] = info
        end
    end
    -- Removing sounds is allowed during combat and encounters. Retire stale
    -- recipients and settings immediately, even when replacements must wait.
    for key, record in pairs(S.registrations) do
        if not desired[key] then
            C_UnitAuras.RemoveAuraSound(record.id)
            S.registrations[key] = nil
        end
    end
    -- AddAuraSound can resume between pulls while aura artwork is still secret.
    if Locked() then return end
    local pending = {}
    for key, info in pairs(desired) do
        if not S.registrations[key] then
            local ok, registration = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, info)
            if not ok or not registration then
                for _, added in pairs(pending) do C_UnitAuras.RemoveAuraSound(added.id) end
                return
            end
            pending[key] = { id = registration }
        end
    end
    for key, record in pairs(pending) do S.registrations[key] = record end
end

local function PIReady()
    local state = ns.SpellReminders.states[10060]
    return state ~= nil and state.cooldown ~= nil and state.cooldown.ready == true
end

function S.Refresh()
    local R = ns.SpellReminders
    local config = R.Get(10060)
    S.ready = PIReady()
    S.Reconcile(config and config.pi, R.PIAllowed(true) and S.ready)
end

function S.Update()
    -- Remove sounds as soon as PI is unavailable, including the cast-to-API
    -- update gap. Visual early windows and estimates never enable audio.
    -- Rearming may be combat/encounter locked; maintenance retries it later.
    if PIReady() ~= S.ready then S.Refresh() end
end

return S
