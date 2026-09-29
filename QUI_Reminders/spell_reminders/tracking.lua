local _, ns = ...
local R, M, P = ns.SpellReminders, ns.SpellReminderModel, ns.SpellReminderPresentation
local T = { cells = {}, alerts = {}, cursor = 1 }
ns.SpellReminderTracking = T
local SLOT = "quiSpellReminder"

local function Content()
    local _, kind = IsInInstance()
    if kind == "raid" or IsInRaid() then return "raid" end
    if kind == "party" or IsInGroup() then return "party" end
end

local function Container(parent, initialize)
    local frame = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    frame:SetSize(1, 1); frame:SetPoint("TOPLEFT")
    frame:EnableMouse(false)
    frame:SetFrameLevel(parent:GetFrameLevel() + 8)
    frame:AddAuraSlot(SLOT, "HELPFUL", {
        candidateFilters = { maxDuration = 0 }, initializeFrame = initialize,
    })
    frame:SetEnabled(false)
    return frame
end

local function CreateRecord(parent, alert, index)
    local record = { parent = parent, alert = alert, index = index }
    record.container = Container(parent, function(slot)
        record.slot = slot
        slot:EnableMouse(false)
        slot:SetSize(1, 1); slot:SetPoint("TOPLEFT", parent, "TOPLEFT")
    end)
    record.durationContainer = Container(parent, function(slot)
        record.durationSlot = slot
        slot:EnableMouse(false)
        slot:SetSize(1, 1); slot:SetPoint("TOPLEFT", parent, "TOPLEFT")
    end)
    if not alert then
        record.request = CreateFrame("Frame", nil, parent, "DisableUntrustedLayoutScriptsTemplate")
        record.request:SetAllPoints(parent)
        record.request:SetFrameLevel(parent:GetFrameLevel() + 10)
        record.request:Hide()
    end
    return record
end

local function ConfigureRecord(record, config, member)
    local width, height = record.parent:GetWidth(), record.parent:GetHeight()
    if record.revision == R.revision and record.guid == (member and member.guid)
        and record.width == width and record.height == height then return end
    local pi = config.pi
    if record.alert then
        record.view = P.AuraIcon(record.slot, record.parent, config, member and member.name or "", pi, record.index, record.view)
        -- Duration is a separate slot so it can be toggled independently of
        -- glows and alert icons without touching the protected art in combat.
    else
        record.art = P.Highlight(record.slot, record.parent, pi, record.art)
        local requestStyle = {}
        for key, value in pairs(pi) do requestStyle[key] = value end
        if requestStyle.glowStyle == "countdown" then requestStyle.glowStyle = "border" end
        record.requestArt = P.Highlight(record.request, record.parent, requestStyle, record.requestArt)
    end
    record.durationText = P.Duration(record.durationSlot, record.alert and record.slot or record.parent,
        config, pi, record.durationText)
    record.revision, record.guid = R.revision, member and member.guid
    record.width, record.height = width, height
    record.scope = nil
end

function T.ClearRequest()
    T.request = nil
    for _, record in pairs(T.cells) do if record.request then record.request:Hide() end end
    local host = R.hosts[10060]
    if host and host.request then host.request:Hide() end
end

function T.Reset()
    T.ClearRequest()
    T.cursor = 1
end

function T.Cast()
    local config = R.Get(10060)
    local whisper = config and config.pi and config.pi.whisper
    if R.PIAllowed() and whisper and whisper.enabled and whisper.mode == "rotation" then
        T.cursor = (T.request and T.request.index or T.cursor) + 1
        if whisper.cycle and T.cursor > #whisper.rotation then T.cursor = 1 end
    end
    T.ClearRequest()
end

local function RequestAllowed(pi)
    local state = R.states[10060]
    return R.PIAllowed() and pi.whisper.enabled and IsInGroup() and InCombatLockdown()
        and state and M.PIReady({ onlyWhenReady = true, grace = pi.grace }, state.cooldown or {})
end

function T.Whisper(bnet)
    local config = R.Get(10060)
    local pi = config and config.pi
    if not pi or not RequestAllowed(pi) or (bnet and pi.whisper.ignoreBnet) then return end
    if T.request then return end
    local rotation = pi.whisper.mode == "rotation"
    local member, index = M.SelectRecipient(rotation and pi.whisper.rotation or pi.whisper.names,
        R.roster, rotation and T.cursor or 1, rotation and pi.whisper.cycle)
    if not member then return end
    T.request = { guid = member.guid, name = member.name, index = index }
    if pi.whisper.sound then ns.SpellReminderSounds.Play(pi.sound, pi.soundChannel) end
    T.Update()
end

function T.Discover()
    if R.Restricted() then return end
    local config, host = R.Get(10060), R.hosts[10060]
    if not config or not host or not R.PIAllowed(true) then return end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then return end
    local byUnit = {}
    for _, member in ipairs(R.roster) do byUnit[member.unit] = member end
    local seen = {}
    for _, entry in ipairs(ns.SpellReminderFrames.Collect()) do
        local record = T.cells[entry.frame] or CreateRecord(entry.frame)
        T.cells[entry.frame] = record
        record.unit = entry.unit
        record.available = true
        seen[entry.frame] = true
        ConfigureRecord(record, config, byUnit[entry.unit])
    end
    for frame, record in pairs(T.cells) do
        if not seen[frame] then
            record.unit, record.available = nil, false
            record.container:SetEnabled(false); record.durationContainer:SetEnabled(false)
            record.live, record.durationLive = false, false
        end
    end
    local count = 0
    for _, member in ipairs(R.roster) do
        if not member.self then
            count = count + 1
            local record = T.alerts[count] or CreateRecord(host, true, count)
            T.alerts[count] = record
            record.unit = member.unit
            ConfigureRecord(record, config, member)
        end
    end
    for i = count + 1, #T.alerts do T.alerts[i].unit = nil end
    local focus = R.Focus()
    if focus and focus.outsideGroup then
        T.focusAlert = T.focusAlert or CreateRecord(host, true, 1)
        T.focusAlert.unit = "focus"
        ConfigureRecord(T.focusAlert, config, focus)
    elseif T.focusAlert then T.focusAlert.unit = nil end
    T.Update()
end

function T.Configure()
    local config, host = R.Get(10060), R.hosts[10060]
    T.ClearRequest()
    if config and host then
        if not host.request then
            host.request = P.CreateIcon(host)
            host.request:SetPoint("TOPLEFT")
        end
        P.ConfigureIcon(host.request, config)
        if not host.focusReminder then
            host.focusReminder = host:CreateFontString(nil, "OVERLAY")
            host.focusReminder:SetPoint("BOTTOM", host, "TOP", 0, 12)
        end
        ns.Helpers.ApplyFontWithFallback(host.focusReminder, ns.Helpers.GetGeneralFont(), 16, "OUTLINE")
        host.focusReminder:SetText(ns.L["Set a friendly player as your focus"])
        host.focusReminder:Hide()
        if not host.sample then
            host.sample = CreateFrame("Frame", nil, host)
            host.sample:SetSize(140, 38)
            host.sample:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -28)
            local background = host.sample:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints(); background:SetColorTexture(0.12, 0.12, 0.16, 0.95)
            host.sample.name = host.sample:CreateFontString(nil, "OVERLAY")
            host.sample.name:SetPoint("CENTER")
        end
        ns.Helpers.ApplyFontWithFallback(host.sample.name, ns.Helpers.GetGeneralFont(), 14, "OUTLINE")
        host.sample.name:SetText(ns.L["PI Recipient"])
        host.sample.art = P.Highlight(host.sample, host.sample, config.pi, host.sample.art)
        if config.pi.glowStyle == "countdown" then
            local bar = host.sample.art.bar
            bar:ClearAllPoints(); bar:SetPoint(config.pi.countdownAnchor)
            bar:SetWidth(140); bar:SetHeight(config.pi.countdownHeight)
            bar:SetStatusBarColor(unpack(config.pi.color))
            bar:SetMinMaxValues(0, 15); bar:SetValue(10); bar:Show()
        end
        host.sample:Hide()
    end
    T.Discover()
    if not R.PIAllowed(true) then ns.SpellReminderSounds.Clear() end
    T.Update()
end

local function Apply(record, member, scope, config, live, request)
    local pi = config and config.pi
    local watch = pi and scope and pi[scope]
    local valid = member and watch and live and (not record.alert or member.guid == record.guid)
    if valid and (record.scope ~= scope or record.filterRevision ~= R.revision) then
        local ids = M.BuffIDs(pi, scope)
        local filters = next(ids) and { includeSpellIDs = ids } or { maxDuration = 0 }
        record.container:SetAuraSlotCandidateFilters(SLOT, filters)
        record.durationContainer:SetAuraSlotCandidateFilters(SLOT, filters)
        record.scope, record.filterRevision = scope, R.revision
    end
    local show = valid and (record.alert and watch.alert or not record.alert and watch.glow) or false
    local duration = valid and watch.duration and (record.alert and watch.alert and pi.durationHost ~= "frame"
        or not record.alert and pi.durationHost ~= "alert") or false
    -- Reapply the unit after enabling: SetUnit while disabled need not persist.
    if record.live ~= show or (show and record.boundUnit ~= member.unit) then
        record.container:SetEnabled(show)
        if show then record.container:SetUnit(member.unit) end
        record.live, record.boundUnit = show, show and member.unit
    end
    if record.durationLive ~= duration or (duration and record.durationUnit ~= member.unit) then
        record.durationContainer:SetEnabled(duration)
        if duration then record.durationContainer:SetUnit(member.unit) end
        record.durationLive, record.durationUnit = duration, duration and member.unit
    end
    if record.request then
        record.request:SetShown(request ~= nil and pi ~= nil and pi.whisper.glow and member ~= nil and member.guid == request.guid)
    end
end

function T.Update()
    local config, host = R.Get(10060), R.hosts[10060]
    local pi = config and config.pi
    local state = R.states[10060]
    local enabled = R.PIAllowed()
    local live = enabled and state and M.PIReady(pi, state.cooldown or {}) or false
    local content, focus = Content(), R.Focus()
    local focusGUID = focus and not focus.outsideGroup and focus.guid
    local byUnit = {}
    for _, member in ipairs(R.roster) do byUnit[member.unit] = member end
    if T.request and (not pi or not RequestAllowed(pi)) then T.ClearRequest() end
    for frame, record in pairs(T.cells) do
        -- A secure header can recycle a cell without a roster event.
        local unit = ns.SpellReminderFrames.Unit(frame)
        local member = record.available and byUnit[unit] or nil
        local scope = pi and member and M.WatchScope(pi, member, content, focusGUID)
        Apply(record, member, scope, config, live, T.request)
    end
    for _, record in ipairs(T.alerts) do
        local member = byUnit[record.unit]
        local scope = pi and member and M.WatchScope(pi, member, content, focusGUID)
        Apply(record, member, scope, config, live)
    end
    if T.focusAlert then
        Apply(T.focusAlert, focus and focus.outsideGroup and focus, pi and pi.focus.enabled and "focus", config, live)
    end
    if host and host.request then
        if host.sample then host.sample:SetShown(R.previews[10060] == true) end
        if T.request and pi.whisper.alert then
            host.icon:Hide()
            P.Draw(host.request, config, { show = true, ready = true }, nil, T.request.name)
        else
            if host.request.effectKey then P.StopEffects(host.request) end
            host.request:Hide()
        end
        local remind = enabled and pi.focusReminder and not focus
            and ((content == "raid" and pi.remindRaid) or (content == "party" and pi.remindParty))
        host.focusReminder:SetShown(remind or false)
    end
end

return T
