local _, ns = ...
local M, P, Sounds = ns.SpellReminderModel, ns.SpellReminderPresentation, ns.SpellReminderSounds
local R = { states = {}, hosts = {}, parked = {}, roster = {}, previews = {}, revision = 0 }
ns.SpellReminders = R

function R.Store()
    local db = ns.Helpers.GetModuleDB("spellReminders")
    return db
end

function R.Get(id)
    local db = R.Store()
    return db and db.reminders[id]
end

function R.Add(id)
    id = tonumber(id)
    if not id or id < 1 or id ~= math.floor(id) or not C_Spell.GetSpellInfo(id) then return nil end
    local db = R.Store()
    if not db then return nil end
    if not db.reminders[id] then db.reminders[id] = M.New(id) end
    R.Refresh()
    return db.reminders[id]
end

function R.Remove(id)
    local db = R.Store()
    if not db then return end
    db.reminders[id] = nil
    R.previews[id] = nil
    R.Refresh()
end

function R.Restricted()
    return InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
end

function R.Context(config)
    local _, _, classID = UnitClass("player")
    local specID = ns.Helpers.GetCurrentSpecID()
    local _, instance = IsInInstance()
    local override = C_Spell.GetOverrideSpell and M.Plain(C_Spell.GetOverrideSpell(config.spellID))
    local known = C_SpellBook.IsSpellKnown(override or config.spellID)
    return { classID = M.Plain(classID), specID = M.Plain(specID), instance = instance,
        combat = InCombatLockdown(), known = M.Plain(known) == true }
end

function R.Allowed(config)
    local db = R.Store()
    return db and db.enabled and M.Allowed(config, R.Context(config)) or false
end

function R.PIAllowed(forSetup)
    local config = R.Get(10060)
    local db = R.Store()
    if not config or not config.pi or not config.pi.enabled or not db or not db.enabled then return false end
    local context = R.Context(config)
    if forSetup then context.combat = true end
    if not M.Allowed(config, context) then return false end
    return context.classID == 5 and (not config.pi.healerOnly or context.specID == 256 or context.specID == 257)
end

function R.Roster()
    local roster = {}
    local function Add(unit)
        if M.Plain(UnitExists(unit)) ~= true then return end
        local name, realm = UnitName(unit)
        name, realm = M.Plain(name), M.Plain(realm)
        local guid = M.Plain(UnitGUID(unit))
        if type(name) ~= "string" or type(guid) ~= "string" then return end
        if not realm or realm == "" then realm = GetNormalizedRealmName() end
        roster[#roster + 1] = { unit = unit, name = name, realm = realm, guid = guid,
            role = M.Plain(UnitGroupRolesAssigned(unit)), self = M.Plain(UnitIsUnit(unit, "player")) == true }
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i) end
    else
        Add("player")
        for i = 1, GetNumSubgroupMembers() do Add("party" .. i) end
    end
    R.roster = roster
end

function R.Focus()
    if M.Plain(UnitExists("focus")) ~= true or M.Plain(UnitIsPlayer("focus")) ~= true
        or M.Plain(UnitCanAssist("player", "focus")) ~= true
        or M.Plain(UnitIsUnit("focus", "player")) == true then return nil end
    local guid = M.Plain(UnitGUID("focus"))
    for _, member in ipairs(R.roster) do
        if guid and member.guid == guid and not member.self then return member end
    end
    -- A friendly non-group focus still gets its own alert, without suppressing
    -- tracking for the rest of the group.
    local name = M.Plain(UnitName("focus"))
    if type(name) == "string" and type(guid) == "string" then
        return { unit = "focus", guid = guid, name = name, outsideGroup = true }
    end
end

local function AnchorKey(id) return "spellReminder:" .. id end

local function Position(id, config, host)
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(AnchorKey(id)) then
        if _G.QUI_ApplyFrameAnchor then _G.QUI_ApplyFrameAnchor(AnchorKey(id)) end
        return
    end
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "CENTER", config.x, config.y)
end

local function CreateHost(id)
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    host.icon = P.CreateIcon(host)
    host.icon:SetPoint("TOPLEFT")
    local drag = CreateFrame("Button", nil, host)
    drag:SetAllPoints(); drag:RegisterForDrag("LeftButton")
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    drag:SetScript("OnDragStart", function()
        if not InCombatLockdown() then host:StartMoving() end
    end)
    drag:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        local config = R.Get(id)
        if not config then return end
        local x, y = host:GetCenter()
        local px, py = UIParent:GetCenter()
        config.x, config.y = x - px, y - py
        local core = ns.Helpers.GetCore()
        local anchors = core and core.db and core.db.profile.frameAnchoring
        if anchors then anchors[AnchorKey(id)] = nil end
    end)
    drag:Hide()
    host.drag = drag
    return host
end

local function RegisterMover(id)
    local layout = ns.QUI_LayoutMode
    if not layout or not layout.RegisterElement then return end
    local config = R.Get(id)
    local key = AnchorKey(id)
    layout:RegisterElement({ key = key, label = P.Name(config), group = ns.L["Spell Reminders"], order = 100, isOwned = true,
        isEnabled = function() return R.Get(id) ~= nil and R.Get(id).enabled end,
        setEnabled = function(value) if R.Get(id) then R.Get(id).enabled = value end; R.Refresh() end,
        getFrame = function() return R.hosts[id] end,
        getSize = function() local c = R.Get(id); return c and c.size, c and c.size end,
        setGameplayHidden = function(hide)
            local host = R.hosts[id]
            if host then
                host.gameplayHidden = hide
                host:SetShown(not hide or R.previews[id] == true)
            end
        end,
    })
    if _G.QUI_RegisterFrameResolver then
        _G.QUI_RegisterFrameResolver(key, { resolver = function() return R.hosts[id] end,
            displayName = P.Name(config), category = ns.L["Spell Reminders"], order = 100 })
    end
end

function R.Preview(id, enabled)
    R.previews[id] = enabled or nil
    R.Refresh()
end

function R.Update(onCooldownEvent)
    local db = R.Store()
    if not db then return end
    local now = GetTime()
    for id, host in pairs(R.hosts) do
        local config = db.reminders[id]
        if config then
            local state = R.states[id]
            local info = C_Spell.GetSpellCooldown(id)
            local charges = M.Plain(C_Spell.GetSpellCharges(id))
            local duration = C_Spell.GetSpellCooldownDuration(id, true)
            if charges and C_Spell.GetSpellChargeDuration then duration = C_Spell.GetSpellChargeDuration(id) end
            local remaining = duration and duration.GetRemainingDuration and M.Plain(duration:GetRemainingDuration())
            state.cooldown = M.Cooldown(info, now, onCooldownEvent, state.cooldown, state.castAt, config, charges, remaining)
            local allowed = R.Allowed(config)
            local output = M.Step(config, state, state.cooldown, now, allowed)
            if allowed then Sounds.Notify(config, output) end
            if R.previews[id] then
                P.Draw(host.icon, config, { show = true, ready = true }, nil, P.Name(config))
            else
                -- Do not draw a native early alert for disabled/unknown spells.
                P.Draw(host.icon, config, output, allowed and state.cooldown.ready == false and duration or nil)
            end
            host.drag:SetShown(R.previews[id] == true and not InCombatLockdown())
        else
            host.icon:Hide(); host.drag:Hide()
        end
    end
    Sounds.Update()
    if ns.SpellReminderTracking then ns.SpellReminderTracking.Update() end
end

local ticker, maintenance
function R.Refresh()
    local db = R.Store()
    if not db then return end
    R.revision = R.revision + 1
    R.Roster()
    if R.Restricted() then
        R.pending = true
        -- Removing native sound registrations is permitted even when new art
        -- and sound registrations must wait for combat restrictions to lift.
        Sounds.Refresh()
        R.Update()
        return
    end
    R.pending = nil
    for id, host in pairs(R.hosts) do
        if not db.reminders[id] then
            P.StopEffects(host.icon); host:Hide()
            R.parked[id] = host
            R.states[id], R.hosts[id] = nil, nil
            if ns.QUI_LayoutMode then ns.QUI_LayoutMode:UnregisterElement(AnchorKey(id)) end
            if _G.QUI_UnregisterFrameResolver then _G.QUI_UnregisterFrameResolver(AnchorKey(id)) end
        end
    end
    for id, config in pairs(db.reminders) do
        M.Normalize(config)
        local host = R.hosts[id] or R.parked[id] or CreateHost(id)
        R.parked[id] = nil
        R.hosts[id] = host
        R.states[id] = R.states[id] or {}
        host:SetSize(config.size, config.size)
        P.ConfigureIcon(host.icon, config)
        host:SetShown(not host.gameplayHidden or R.previews[id] == true)
        RegisterMover(id)
    end
    -- Resolve anchors after every host is registered, including references
    -- from one spell reminder to another.
    for id, host in pairs(R.hosts) do Position(id, db.reminders[id], host) end
    Sounds.Refresh()
    local tracking = ns.SpellReminderTracking
    if tracking then tracking.Configure() end
    if ticker then ticker:Cancel(); ticker = nil end
    if maintenance then maintenance:Cancel(); maintenance = nil end
    if (db.enabled and next(db.reminders)) or next(R.previews) then
        ticker = C_Timer.NewTicker(0.1, function() R.Update() end)
        maintenance = C_Timer.NewTicker(1, function()
            Sounds.Refresh()
            if R.pending and not R.Restricted() then R.Refresh()
            elseif tracking and not R.Restricted() then tracking.Discover() end
        end)
    end
    R.Update()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
    "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ENCOUNTER_START",
    "GROUP_ROSTER_UPDATE", "PLAYER_FOCUS_CHANGED", "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_COMPLETED",
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "ADDON_RESTRICTION_STATE_CHANGED" }) do events:RegisterEvent(event) end
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    local tracking = ns.SpellReminderTracking
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if R.pending and not R.Restricted() then
            R.Refresh()
        else
            Sounds.Refresh()
        end
        return
    end
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        -- Deliberately discard the sender and message, which may be secret.
        if tracking then tracking.Whisper(event == "CHAT_MSG_BN_WHISPER") end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        spellID = M.Plain(spellID)
        if type(spellID) ~= "number" then return end
        for id, state in pairs(R.states) do
            local override = C_Spell.GetOverrideSpell and M.Plain(C_Spell.GetOverrideSpell(id))
            if id == spellID or override == spellID then
                state.castAt, state.encounterAt, state.earlySpoken, state.countdown = GetTime(), nil, nil, nil
            end
        end
        if spellID == 10060 and tracking then tracking.Cast() end
        R.Update()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        R.Update(true)
    elseif event == "SPELL_UPDATE_CHARGES" then
        R.Update()
    elseif event == "ENCOUNTER_START" then
        for id, state in pairs(R.states) do
            local config = R.Get(id)
            if config and config.encounterStart then state.encounterAt = GetTime() end
        end
        R.Update()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_FOCUS_CHANGED" then
        R.Roster()
        Sounds.Refresh()
        if tracking then tracking.ClearRequest() end
        if not R.Restricted() and tracking then tracking.Discover() end
        R.Update()
    elseif event == "PLAYER_REGEN_DISABLED" then
        for id in pairs(R.previews) do R.previews[id] = nil end
        R.Update()
    else
        if tracking then tracking.ClearRequest() end
        R.Refresh()
    end
end)

return R
