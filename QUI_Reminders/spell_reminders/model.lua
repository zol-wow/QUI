local _, ns = ...

local M = {}
ns.SpellReminderModel = M

function M.Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end -- @secret-policy: reject-secret-value
    return value
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end

local function Defaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(target[key]) ~= type(value) then
            target[key] = Copy(value)
        elseif type(value) == "table" then
            Defaults(target[key], value)
        end
    end
end

local function Scope(alert)
    return { enabled = true, glow = true, alert = alert, duration = false, mode = "all" }
end

M.defaults = {
    enabled = true, onlyKnown = true, classID = 0, specs = {}, instances = {}, combatOnly = false,
    showWhenReady = true, readyDuration = 5, showBeforeReady = false, beforeReadyTime = 3,
    encounterStart = false, useEstimate = false, estimatedCooldown = 0,
    size = 48, x = 0, y = -200, font = "", fontSize = 16, fontOutline = "OUTLINE",
    showBorder = true, desaturate = false, label = "", nameLayout = "overlay",
    textColor = { 1, 1, 1, 1 }, glow = "proc", glowColor = { 1, 0.7, 0.1, 1 },
    glowReadyOnly = true, animation = "none", animationReadyOnly = true,
    sound = "None", soundChannel = "Master", readySound = false, earlySound = false,
    ttsReady = false, ttsEarly = false, ttsCountdown = false, countdownStart = 5,
    ttsReadyText = "", ttsEarlyText = "", voice = 0,
}

M.piDefaults = {
    enabled = true, healerOnly = true, onlyWhenReady = true, grace = 0,
    raid = Scope(false), party = Scope(false), focus = Scope(true),
    names = {}, spells = {}, customSpells = {}, separateBuffs = false, spellScopes = {},
    glowStyle = "pixel", color = { 1, 0.7, 0.1, 0.9 }, thickness = 2, speed = 1, alertGlow = true,
    durationHost = "frame", durationAnchor = "CENTER", durationSize = 12,
    durationX = 0, durationY = 0, countdownAnchor = "TOP", countdownHeight = 4,
    focusReminder = false, remindRaid = true, remindParty = true,
    focusSound = false, partySound = false, raidSound = false, sound = "None", soundChannel = "Master",
    whisper = { enabled = false, ignoreBnet = true, mode = "priority", names = {},
        rotation = {}, cycle = true, alert = true, glow = true, sound = false },
}

function M.Normalize(config)
    Defaults(config, M.defaults)
    if config.spellID == 10060 then
        if type(config.pi) ~= "table" then config.pi = {} end
        Defaults(config.pi, M.piDefaults)
    end
    return config
end

function M.New(spellID)
    local config = M.Normalize({ spellID = spellID })
    if spellID == 10060 then
        config.classID, config.estimatedCooldown = 5, 120
        config.showWhenReady = false
    elseif spellID == 29166 then
        config.classID, config.estimatedCooldown = 11, 180
    end
    return config
end

function M.ParseNames(text)
    local names, seen = {}, {}
    for name in (text or ""):gmatch("[^,;\n]+") do
        name = name:match("^%s*(.-)%s*$")
        local key = name:lower()
        if name ~= "" and not seen[key] then
            names[#names + 1], seen[key] = name, true
        end
    end
    return names
end

-- A realm-qualified entry must match that realm; never widen it to a short name.
function M.NameMatches(entry, name, realm)
    if not entry or not name then return false end
    entry = entry:lower():gsub("%s", "")
    name = name:lower()
    if not entry:find("-", 1, true) then return entry == name end
    return realm ~= nil and entry == name .. "-" .. realm:lower():gsub("%s", "")
end

function M.Listed(names, member)
    for _, name in ipairs(names) do
        if M.NameMatches(name, member.name, member.realm) then return true end
    end
    return false
end

function M.SelectRecipient(names, roster, start, cycle)
    local count = #names
    if count == 0 then return nil end
    start = math.max(1, start or 1)
    if start > count and not cycle then return nil end
    for offset = 0, count - 1 do
        local index = start + offset
        if index > count then
            if not cycle then break end
            index = (index - 1) % count + 1
        end
        for _, member in ipairs(roster) do
            if M.NameMatches(names[index], member.name, member.realm) then return member, index end
        end
    end
end

function M.Allowed(config, context)
    if not config.enabled or (config.onlyKnown and not context.known) then return false end
    if config.combatOnly and not context.combat then return false end
    if config.classID ~= 0 and config.classID ~= context.classID then return false end
    if next(config.specs) and not config.specs[context.specID] then return false end
    if next(config.instances) and not config.instances[context.instance] then return false end
    return true
end

-- The input table may contain secret numeric fields. Only plain values enter
-- decisions; the original duration object is passed to UI sinks elsewhere.
function M.Cooldown(info, now, onCooldownEvent, previous, castTime, config, charges, exactRemaining)
    if type(info) ~= "table" then return { ready = nil } end
    local active, enabled = M.Plain(info.isActive), M.Plain(info.isEnabled)
    local gcd = onCooldownEvent and M.Plain(info.isOnGCD)
    local start, duration, rate = M.Plain(info.startTime), M.Plain(info.duration), M.Plain(info.modRate)
    local ready, remaining
    if enabled == false then
        ready = false
    elseif active == false then
        ready = true
    elseif active == true then
        ready = false
        if gcd == true then ready = true end
        if not onCooldownEvent and previous and previous.gcd and previous.ready then ready = true end
    end
    if type(start) == "number" and type(duration) == "number" then
        rate = type(rate) == "number" and rate > 0 and rate or 1
        remaining = math.max(0, (start + duration - now) / rate)
        if gcd == true then remaining = 0 end
    end
    if type(charges) == "table" then
        local available = M.Plain(charges.currentCharges)
        if type(available) == "number" then
            ready = available > 0
            if not ready then
                local cs, cd, cr = M.Plain(charges.cooldownStartTime), M.Plain(charges.cooldownDuration), M.Plain(charges.chargeModRate)
                if type(cs) == "number" and type(cd) == "number" then
                    remaining = math.max(0, (cs + cd - now) / (type(cr) == "number" and cr > 0 and cr or 1))
                end
            end
        end
    end
    -- The duration object accounts for time modifiers when the number is readable.
    exactRemaining = M.Plain(exactRemaining)
    if type(exactRemaining) == "number" then remaining = math.max(0, exactRemaining) end
    -- Suppress the short interval between a successful cast and the API update.
    if castTime and now - castTime < 0.25 then ready, remaining = false, nil end
    local estimated = false
    if ready == false and remaining == nil and config.useEstimate and castTime
        and config.estimatedCooldown > 0 then
        remaining = math.max(0, castTime + config.estimatedCooldown - now)
        estimated = true
    end
    return { ready = ready, remaining = remaining, estimated = estimated,
        gcd = onCooldownEvent and gcd == true or (not onCooldownEvent and previous and previous.gcd) or false }
end

function M.Step(config, state, cooldown, now, allowed)
    local output = { show = false }
    if not allowed then
        state.status, state.readyAt, state.earlySpoken, state.countdown = nil, nil, nil, nil
        return output
    end
    local before = state.status
    local remaining = cooldown.remaining
    if cooldown.ready == true then
        if before ~= "ready" then state.readyAt = now end
        state.status = "ready"
        output.show = config.showWhenReady and (config.readyDuration == 0 or now - state.readyAt < config.readyDuration)
        output.readyNotice = before == "cooldown" or before == "early"
        state.earlySpoken, state.countdown = nil, nil
    elseif cooldown.ready == false then
        state.status = "cooldown"
        state.readyAt = nil
        if remaining and remaining > 0 and remaining <= config.beforeReadyTime and config.showBeforeReady then
            state.status, output.show = "early", true
            output.earlyNotice = not state.earlySpoken
            state.earlySpoken = true
        end
        if config.ttsCountdown and remaining and remaining > 0 and remaining <= config.countdownStart then
            local second = math.ceil(remaining)
            if state.countdown ~= second then output.countdown = second end
            state.countdown = second
        end
    else
        state.status = "unknown"
    end
    if state.encounterAt and now - state.encounterAt < (config.readyDuration > 0 and config.readyDuration or 10) then
        output.show = true
        output.encounter = true
        if state.encounterNotifiedAt ~= state.encounterAt then
            output.readyNotice = cooldown.ready == true or output.readyNotice
            state.encounterNotifiedAt = state.encounterAt
        end
    end
    output.ready, output.remaining, output.estimated = cooldown.ready == true, remaining, cooldown.estimated
    return output
end

function M.PIReady(pi, cooldown)
    if not pi.onlyWhenReady then return true end
    if cooldown.ready == true then return true end
    return pi.grace > 0 and cooldown.ready == false and cooldown.remaining ~= nil
        and cooldown.remaining > 0 and cooldown.remaining <= pi.grace
end

function M.WatchScope(pi, member, content, focusGUID)
    if member.self then return nil end
    if pi.focus.enabled and focusGUID then
        return member.guid == focusGUID and "focus" or nil
    end
    local scope = pi[content]
    if not scope or not scope.enabled then return nil end
    local listed = M.Listed(pi.names, member)
    if scope.mode == "listed" and not listed then return nil end
    if (member.role == "TANK" or member.role == "HEALER") and not listed then return nil end
    return content
end

return M
