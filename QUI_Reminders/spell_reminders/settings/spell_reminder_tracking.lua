local _, ns = ...
local O = ns.SpellReminderOptions
local GUI = QUI.GUI

local function Names(L, title, owner, key, rebuild)
    local card = O.Card(L, title)
    local proxy = { text = table.concat(owner[key], ", "), _quiTransientOptionsProxy = true }
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
    c.Check(ns.L["Enable PI Helper"], pi, "enabled", ns.L["Track allies' offensive buffs and handle Power Infusion requests. The spell's own cooldown reminder is configured separately."])
    c.Check(ns.L["Holy and Discipline Only"], pi, "healerOnly", ns.L["Limit the PI helper to Holy and Discipline priests. Turn off to use it as Shadow too."])
    c.Check(ns.L["Only While PI Is Ready"], pi, "onlyWhenReady", ns.L["Show tracked-buff highlights and recipient alerts only while PI is ready or within the early request window."])
    c.Slider(ns.L["Early Request Window"], pi, "grace", 0, 15, 1, ns.L["Allow prompts this many seconds before PI is ready. Uses readable timing or an enabled cooldown estimate."])
    c.Finish()
    for _, scope in ipairs({ { "raid", ns.L["Raid Tracking"] }, { "party", ns.L["Dungeon Tracking"] }, { "focus", ns.L["Focus Tracking"] } }) do
        local options = pi[scope[1]]
        c = O.Card(L, scope[2])
        c.Check(ns.L["Track Cooldowns"], options, "enabled", ns.L["Watch players in this context for buffs enabled on the Tracked Buffs tab. A friendly focus takes priority over raid and dungeon tracking."])
        c.Check(ns.L["Glow Group Frames"], options, "glow", ns.L["Highlight a tracked player's group frame while a selected offensive buff is active."])
        c.Check(ns.L["Show Recipient Alerts"], options, "alert", ns.L["Show a recipient icon at the reminder anchor while a tracked player's selected offensive buff is active."])
        c.Check(ns.L["Show Buff Duration"], options, "duration", ns.L["Show the tracked buff's remaining duration at the location selected under Duration Display."])
        if scope[1] ~= "focus" then
            c.Select(ns.L["Players to Track"], options, "mode", O.Choices({ "all", ns.L["All Damage Dealers"], "listed", ns.L["Listed Players"] }), ns.L["Track every damage dealer or only the names in Tracked Players. Listed players can include tanks and healers."])
        end
        c.Finish()
    end
    L.intro(ns.L["A friendly group focus takes priority over raid and dungeon tracking. Tanks and healers are skipped unless listed. Your own character is excluded."])
    Names(L, ns.L["Tracked Players"], pi, "names", rebuild)
    c = O.Card(L, ns.L["Group Frame Highlight"])
    c.Select(ns.L["Highlight Style"], pi, "glowStyle", O.Choices({ "pixel", ns.L["Pixel"], "proc", ns.L["Proc"], "border", ns.L["Border"], "fill", ns.L["Fill"], "countdown", ns.L["Countdown Bar"] }), ns.L["Choose how tracked offensive buffs highlight players' group frames."])
    c.Color(ns.L["Highlight Color"], pi, "color", ns.L["Color and opacity of the group-frame highlight and tracked-buff countdown bar."])
    c.Check(ns.L["Glow Recipient Alerts"], pi, "alertGlow", ns.L["Add a proc glow to buff-triggered recipient icons."])
    c.Slider(ns.L["Border Thickness"], pi, "thickness", 1, 8, 1, ns.L["Thickness of the Border and Pixel group-frame highlights, in pixels."])
    c.Slider(ns.L["Animation Speed"], pi, "speed", 0.25, 3, 0.25, ns.L["Speed of the Pixel and Proc group-frame highlight animations. Higher values animate faster."])
    c.Select(ns.L["Countdown Bar Position"], pi, "countdownAnchor", O.Choices({ "TOP", ns.L["Top"], "CENTER", ns.L["Center"], "BOTTOM", ns.L["Bottom"] }), ns.L["Position of the tracked-buff bar when Highlight Style is Countdown Bar."])
    c.Slider(ns.L["Countdown Bar Height"], pi, "countdownHeight", 1, 16, 1, ns.L["Height in pixels of the tracked-buff Countdown Bar highlight."])
    c.Select(ns.L["Duration Display"], pi, "durationHost", O.Choices({ "frame", ns.L["Group Frame"], "alert", ns.L["Recipient Alert"], "both", ns.L["Both"] }), ns.L["Show tracked-buff duration text on the group frame, recipient icon, or both. Show Buff Duration must be enabled for that context."])
    c.Select(ns.L["Duration Position"], pi, "durationAnchor", ns.QUI_SettingsLayoutShared.BuildNinePointAnchorOptions(), ns.L["Anchor point for tracked-buff duration text on its group frame or recipient icon."])
    c.Slider(ns.L["Duration Font Size"], pi, "durationSize", 8, 32, 1, ns.L["Font size of the tracked-buff duration text."])
    c.Slider(ns.L["Duration Horizontal Offset"], pi, "durationX", -100, 100, 1, ns.L["Move tracked-buff duration text left with negative values or right with positive values."])
    c.Slider(ns.L["Duration Vertical Offset"], pi, "durationY", -100, 100, 1, ns.L["Move tracked-buff duration text down with negative values or up with positive values."])
    c.Finish()
    L.intro(ns.L["Recipient alerts use fixed player positions during combat. Their icon size, font and position follow the Appearance tab."])
    c = O.Card(L, ns.L["Focus Reminder"])
    c.Check(ns.L["Remind Me to Set Focus"], pi, "focusReminder", ns.L["Show a message above the PI reminder when no friendly player is set as your focus in the enabled content types."])
    c.Check(ns.L["Remind in Raids"], pi, "remindRaid", ns.L["Allow the missing-focus message in raids when Remind Me to Set Focus is enabled."])
    c.Check(ns.L["Remind in Dungeons"], pi, "remindParty", ns.L["Allow the missing-focus message in dungeons when Remind Me to Set Focus is enabled."])
    c.Finish()
    c = O.Card(L, ns.L["Tracked Cooldown and Request Sounds"])
    c.Select(ns.L["Alert Sound"], pi, "sound", O.SoundChoices(), ns.L["Sound used for tracked offensive buffs and whisper requests. Enable the contexts that should play it below."])
    c.Select(ns.L["Output Channel"], pi, "soundChannel", O.Choices({ "Master", ns.L["Master"], "SFX", ns.L["Sound Effects"], "Dialog", ns.L["Dialog"] }), ns.L["Volume channel for tracked-buff and request sounds. Its volume must be audible in WoW's sound settings."])
    c.Check(ns.L["Sound on Raid Cooldowns"], pi, "raidSound", ns.L["Play the alert sound when a tracked raid player's selected offensive buff starts while PI is fully ready."])
    c.Check(ns.L["Sound on Party Cooldowns"], pi, "partySound", ns.L["Play the alert sound when a tracked dungeon player's selected offensive buff starts while PI is fully ready."])
    c.Check(ns.L["Sound on Focus Cooldowns"], pi, "focusSound", ns.L["Play the alert sound when your tracked focus gains a selected offensive buff while PI is fully ready."])
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
    c.Check(ns.L["Separate Buffs by Context"], pi, "separateBuffs", ns.L["Use separate buff selections for raids, dungeons, and focus tracking. Contexts without an override use the default list."], function() O.Refresh(); if rebuild then rebuild() end end)
    if pi.separateBuffs then
        local proxy = { scope = buffScope, _quiTransientOptionsProxy = true }
        c.Select(ns.L["Edit Buff List"], proxy, "scope", O.Choices({ "shared", ns.L["Default List"], "raid", ns.L["Raids"], "party", ns.L["Dungeons"], "focus", ns.L["Focus"] }), ns.L["Choose which context's buff selection to edit. Default List supplies buffs without a context override."], function(value)
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
        local proxy = { enabled = enabled, _quiTransientOptionsProxy = true }
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        local label = (info and info.name or ns.L["Unknown Spell"]) .. "  " .. id
        c.Check(label, proxy, "enabled", ns.L["Watch for this active buff to trigger PI tracking highlights, recipient alerts, and enabled sounds in the selected context."], function()
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
    local proxy = { text = table.concat(pi.customSpells, ", "), _quiTransientOptionsProxy = true }
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
    c.Check(ns.L["Enable Whisper Requests"], w, "enabled", ns.L["Treat incoming whispers as PI requests while grouped, in combat, and PI is ready or within the early request window. Your configured list determines the recipient."])
    c.Check(ns.L["Ignore Battle.net Whispers"], w, "ignoreBnet", ns.L["Accept requests from regular whispers only. Turn off to let Battle.net whispers trigger requests too."])
    c.Select(ns.L["Recipient Selection"], w, "mode", O.Choices({ "priority", ns.L["Priority"], "rotation", ns.L["Rotation"] }), ns.L["Priority chooses the first listed group member. Rotation advances through the list after each PI cast."], function()
        if ns.SpellReminderTracking then ns.SpellReminderTracking.Reset() end
        O.Refresh(); if rebuild then rebuild() end
    end)
    c.Check(ns.L["Show Request Icon"], w, "alert", ns.L["Show the requested recipient's name on an icon at the PI reminder anchor."])
    c.Check(ns.L["Highlight Recipient Frame"], w, "glow", ns.L["Highlight the chosen request recipient's group frame until the request is cleared or PI is cast."])
    c.Check(ns.L["Play Request Sound"], w, "sound", ns.L["Uses the alert sound selected on the PI Tracking tab."])
    c.Check(ns.L["Repeat Rotation"], w, "cycle", ns.L["Return to the start after the last player in the rotation. Turn off to stop accepting requests when the list is exhausted."])
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
