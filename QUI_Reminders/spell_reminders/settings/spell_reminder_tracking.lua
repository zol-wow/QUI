local _, ns = ...
local O = ns.SpellReminderOptions
local GUI = QUI.GUI

local function Names(L, title, owner, key, rebuild)
    local card = O.Card(L, title)
    local proxy = { text = table.concat(owner[key], ", ") }
    card.Text(ns.L["Player Names"], proxy, "text", ns.L["Separate names with commas. Use Name-Realm to distinguish players with the same name."], function()
        owner[key] = ns.SpellReminderModel.ParseNames(proxy.text)
        O.Refresh()
        if rebuild then rebuild() end
    end)
    card.Finish()
    if ns.QUI_ReorderList then
        local list, height = ns.QUI_ReorderList.Build(L.content, 0, {
            items = owner[key], identify = function(name) return name end,
            getLabel = function(name, index) return index .. ". " .. name end,
            hintText = ns.L["Drag names or use the arrows to change their order."],
            emptyText = ns.L["No players listed."],
            onRemove = function(_, index)
                table.remove(owner[key], index); O.Refresh(); if rebuild then rebuild() end
            end,
            onChange = function() O.Refresh(); if rebuild then rebuild() end end,
        })
        L.placeCustom(list, height)
    end
end

function O.builders.tracking(host, config, rebuild)
    local pi, L = config.pi, O.Layout(host)
    local c = O.Card(L, ns.L["Power Infusion Helper"])
    c.Check(ns.L["Enable PI Helper"], pi, "enabled")
    c.Check(ns.L["Holy and Discipline Only"], pi, "healerOnly")
    c.Check(ns.L["Only While PI Is Ready"], pi, "onlyWhenReady")
    c.Slider(ns.L["Early Request Window"], pi, "grace", 0, 15, 1, ns.L["Allow prompts this many seconds before PI is ready. Uses readable timing or an enabled cooldown estimate."])
    c.Finish()
    for _, scope in ipairs({ { "raid", ns.L["Raid Tracking"] }, { "party", ns.L["Dungeon Tracking"] }, { "focus", ns.L["Focus Tracking"] } }) do
        local options = pi[scope[1]]
        c = O.Card(L, scope[2])
        c.Check(ns.L["Track Cooldowns"], options, "enabled")
        c.Check(ns.L["Glow Group Frames"], options, "glow")
        c.Check(ns.L["Show Recipient Alerts"], options, "alert")
        c.Check(ns.L["Show Buff Duration"], options, "duration")
        if scope[1] ~= "focus" then
            c.Select(ns.L["Players to Track"], options, "mode", O.Choices({ "all", ns.L["All Damage Dealers"], "listed", ns.L["Listed Players"] }))
        end
        c.Finish()
    end
    L.intro(ns.L["A friendly group focus takes priority over raid and dungeon tracking. Tanks and healers are skipped unless listed. Your own character is excluded."])
    Names(L, ns.L["Tracked Players"], pi, "names", rebuild)
    c = O.Card(L, ns.L["Group Frame Highlight"])
    c.Select(ns.L["Highlight Style"], pi, "glowStyle", O.Choices({ "pixel", ns.L["Pixel"], "proc", ns.L["Proc"], "border", ns.L["Border"], "fill", ns.L["Fill"], "countdown", ns.L["Countdown Bar"] }))
    c.Color(ns.L["Highlight Color"], pi, "color")
    c.Check(ns.L["Glow Recipient Alerts"], pi, "alertGlow", ns.L["Add a proc glow to buff-triggered recipient icons."])
    c.Slider(ns.L["Border Thickness"], pi, "thickness", 1, 8, 1)
    c.Slider(ns.L["Animation Speed"], pi, "speed", 0.25, 3, 0.25)
    c.Select(ns.L["Countdown Bar Position"], pi, "countdownAnchor", O.Choices({ "TOP", ns.L["Top"], "CENTER", ns.L["Center"], "BOTTOM", ns.L["Bottom"] }))
    c.Slider(ns.L["Countdown Bar Height"], pi, "countdownHeight", 1, 16, 1)
    c.Select(ns.L["Duration Display"], pi, "durationHost", O.Choices({ "frame", ns.L["Group Frame"], "alert", ns.L["Recipient Alert"], "both", ns.L["Both"] }))
    c.Select(ns.L["Duration Position"], pi, "durationAnchor", ns.QUI_SettingsLayoutShared.BuildNinePointAnchorOptions())
    c.Slider(ns.L["Duration Font Size"], pi, "durationSize", 8, 32, 1)
    c.Slider(ns.L["Duration Horizontal Offset"], pi, "durationX", -100, 100, 1)
    c.Slider(ns.L["Duration Vertical Offset"], pi, "durationY", -100, 100, 1)
    c.Finish()
    L.intro(ns.L["Recipient alerts use fixed player positions during combat. Their icon size, font and position follow the Appearance tab."])
    c = O.Card(L, ns.L["Focus Reminder"])
    c.Check(ns.L["Remind Me to Set Focus"], pi, "focusReminder")
    c.Check(ns.L["Remind in Raids"], pi, "remindRaid")
    c.Check(ns.L["Remind in Dungeons"], pi, "remindParty")
    c.Finish()
    c = O.Card(L, ns.L["Tracked Cooldown and Request Sounds"])
    c.Select(ns.L["Alert Sound"], pi, "sound", O.SoundChoices())
    c.Select(ns.L["Output Channel"], pi, "soundChannel", O.Choices({ "Master", ns.L["Master"], "SFX", ns.L["Sound Effects"], "Dialog", ns.L["Dialog"] }))
    c.Check(ns.L["Sound on Raid Cooldowns"], pi, "raidSound")
    c.Check(ns.L["Sound on Party Cooldowns"], pi, "partySound")
    c.Check(ns.L["Sound on Focus Cooldowns"], pi, "focusSound")
    c.Finish()
    O.Buttons(L, { { ns.L["Test Alert Sound"], function() ns.SpellReminderSounds.Play(pi.sound, pi.soundChannel) end } })
    L.intro(ns.L["Choose a sound and enable the contexts that should play it. Tracked-buff sounds stop when PI is unavailable. They require PI to be fully ready, even with an early window or always-on tracking. WoW blocks re-enabling these sounds during combat or encounters, so they resume once PI is ready and those restrictions lift. The combat-only filter does not affect these sounds."])
    L.intro(ns.L["For a spoken PI-ready reminder, set your phrase and voice on the Sounds tab. WoW's tracked-buff audio supports sound files, not custom text-to-speech."])
    return L.finish()
end

local buffScope = "shared"
function O.builders.buffs(host, config, rebuild)
    local pi, L = config.pi, O.Layout(host)
    L.intro(ns.L["Track buffs applied by offensive cooldowns. Use the buff ID, which can differ from the cast spell ID. Abilities without a detectable buff cannot trigger PI tracking."])
    local c = O.Card(L, ns.L["Buff Lists"])
    c.Check(ns.L["Separate Buffs by Context"], pi, "separateBuffs", nil, function() O.Refresh(); if rebuild then rebuild() end end)
    if pi.separateBuffs then
        local proxy = { scope = buffScope }
        c.Select(ns.L["Edit Buff List"], proxy, "scope", O.Choices({ "shared", ns.L["Default List"], "raid", ns.L["Raids"], "party", ns.L["Dungeons"], "focus", ns.L["Focus"] }), nil, function(value)
            buffScope = value; if rebuild then rebuild() end
        end)
    end
    c.Finish()
    local scope = pi.separateBuffs and buffScope or "shared"
    local previous
    local function Entry(id, group, default)
        if group ~= previous then
            if c then c.Finish() end
            c = O.Card(L, group)
            previous = group
        end
        local enabled = pi.spells[id]
        if enabled == nil then enabled = default end
        local overrides = pi.spellScopes[id]
        if scope ~= "shared" and overrides and overrides[scope] ~= nil then enabled = overrides[scope] end
        local proxy = { enabled = enabled }
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        local label = (info and info.name or ns.L["Unknown Spell"]) .. "  " .. id
        c.Check(label, proxy, "enabled", nil, function()
            if scope == "shared" then pi.spells[id] = proxy.enabled
            else
                pi.spellScopes[id] = pi.spellScopes[id] or {}
                pi.spellScopes[id][scope] = proxy.enabled
            end
            O.Refresh()
        end)
    end
    c = nil
    for _, buff in ipairs(ns.SpellReminderModel.buffs) do
        local className = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[buff[2]] or buff[2]
        Entry(buff[1], buff[3] and ns.L["Potions"] or className, not buff[3])
    end
    for _, id in ipairs(pi.customSpells) do Entry(id, ns.L["Custom Buffs"], true) end
    if c then c.Finish() end
    c = O.Card(L, ns.L["Custom Buff IDs"])
    local proxy = { text = table.concat(pi.customSpells, ", ") }
    c.Text(ns.L["Buff IDs"], proxy, "text", ns.L["Enter buff IDs separated by commas. Removing an ID from this field removes it from tracking."], function()
        local ids, seen = {}, {}
        for value in proxy.text:gmatch("[^,%s;]+") do
            local id = tonumber(value)
            if not id or id < 1 or id ~= math.floor(id) or not C_Spell.GetSpellInfo(id) then
                if UIErrorsFrame then UIErrorsFrame:AddMessage(ns.L["Enter valid buff IDs separated by commas."], 1, 0.3, 0.3) end
                return
            end
            if not seen[id] then ids[#ids + 1], seen[id] = id, true end
        end
        pi.customSpells = ids; O.Refresh(); if rebuild then rebuild() end
    end)
    c.Finish()
    return L.finish()
end

function O.builders.requests(host, config, rebuild)
    local pi, L = config.pi, O.Layout(host)
    local w = pi.whisper
    L.intro(ns.L["Any qualifying whisper counts as a request. WoW hides the sender and message, so your list determines who is highlighted. Requests only work in a group, in combat, while PI is ready or within the early request window."])
    local c = O.Card(L, ns.L["Whisper Requests"])
    c.Check(ns.L["Enable Whisper Requests"], w, "enabled")
    c.Check(ns.L["Ignore Battle.net Whispers"], w, "ignoreBnet")
    c.Select(ns.L["Recipient Selection"], w, "mode", O.Choices({ "priority", ns.L["Priority"], "rotation", ns.L["Rotation"] }), nil, function()
        if ns.SpellReminderTracking then ns.SpellReminderTracking.Reset() end
        O.Refresh(); if rebuild then rebuild() end
    end)
    c.Check(ns.L["Show Request Icon"], w, "alert")
    c.Check(ns.L["Highlight Recipient Frame"], w, "glow")
    c.Check(ns.L["Play Request Sound"], w, "sound", ns.L["Uses the alert sound selected on the PI Tracking tab."])
    c.Check(ns.L["Repeat Rotation"], w, "cycle")
    c.Finish()
    if w.mode == "rotation" then
        L.intro(ns.L["A whisper selects the next listed player in your group. Each PI cast advances the rotation. Whispers received during cooldown are discarded."])
        Names(L, ns.L["Rotation Order"], w, "rotation", rebuild)
    else
        L.intro(ns.L["A whisper selects the first listed player currently in your group."])
        Names(L, ns.L["Priority Order"], w, "names", rebuild)
    end
    O.Buttons(L, { { ns.L["Reset Rotation"], function() ns.SpellReminderTracking.Reset(); if rebuild then rebuild() end end },
        { ns.L["Clear Request"], function() ns.SpellReminderTracking.ClearRequest(); ns.SpellReminders.Update() end } })
    return L.finish()
end
