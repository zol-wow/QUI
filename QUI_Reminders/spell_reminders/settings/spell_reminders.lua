local _, ns = ...
local O = { builders = {} }
ns.SpellReminderOptions = O
local GUI, Shared = QUI.GUI, ns.QUI_Options
local selected, activeTab = nil, "timing"

function O.Refresh()
    if ns.SpellReminders then ns.SpellReminders.Refresh() end
end

function O.Card(layout, title)
    GUI:SetSearchSection(title)
    layout.headerAt(title)
    local card = layout.sectionAt()
    function card.Row(label, widget)
        card.AddRow(Shared.BuildSettingRow(card.frame, label, widget))
        return widget
    end
    function card.Check(label, db, key, description, change)
        return card.Row(label, GUI:CreateFormCheckbox(card.frame, nil, key, db, change or O.Refresh, { description = description }))
    end
    function card.Slider(label, db, key, min, max, step, description)
        return card.Row(label, GUI:CreateFormSlider(card.frame, nil, min, max, step, key, db, O.Refresh, { description = description }))
    end
    function card.Select(label, db, key, choices, description, change)
        return card.Row(label, GUI:CreateFormDropdown(card.frame, nil, choices, key, db, change or O.Refresh, { description = description }))
    end
    function card.Text(label, db, key, description, change)
        return card.Row(label, GUI:CreateFormEditBox(card.frame, nil, key, db, change or O.Refresh,
            { description = description, maxLetters = 1000 }))
    end
    function card.Color(label, db, key)
        return card.Row(label, GUI:CreateFormColorPicker(card.frame, nil, key, db, O.Refresh))
    end
    function card.Finish() layout.closeSection(card) end
    return card
end

function O.Choices(values)
    local result = {}
    for i = 1, #values, 2 do result[#result + 1] = { value = values[i], text = values[i + 1] } end
    return result
end

function O.SoundChoices()
    local sounds = Shared.GetSoundList()
    sounds[#sounds + 1] = { value = "QUI Reminder Bell", text = ns.L["Reminder Bell"] }
    return sounds
end

function O.Buttons(layout, buttons)
    local parent = CreateFrame("Frame", nil, layout.content)
    local previous
    for _, item in ipairs(buttons) do
        local button = GUI:CreateButton(parent, item[1], item[3] or 140, 26, item[2])
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 8, 0) else button:SetPoint("LEFT") end
        previous = button
    end
    layout.placeCustom(parent, 28)
end

function O.Layout(host)
    local layout = ns.QUI_SettingsLayoutShared.MakeLayout(host)
    layout.content = host
    return layout
end

function O.builders.timing(host, config)
    local L = O.Layout(host)
    local c = O.Card(L, ns.L["Reminder Timing"])
    c.Check(ns.L["Enable This Reminder"], config, "enabled")
    c.Check(ns.L["Show When Ready"], config, "showWhenReady")
    c.Slider(ns.L["Hide After Ready"], config, "readyDuration", 0, 60, 1, ns.L["Seconds to show the ready reminder. Zero keeps it visible until you cast."])
    c.Check(ns.L["Show Before Ready"], config, "showBeforeReady")
    c.Slider(ns.L["Seconds Before Ready"], config, "beforeReadyTime", 1, 30, 1)
    c.Check(ns.L["Remind at Encounter Start"], config, "encounterStart", ns.L["Show the reminder when a boss encounter starts, even if the spell is on cooldown."])
    c.Finish()
    L.intro(ns.L["WoW can display an exact cooldown while hiding its timing from addons. Early sounds and spoken countdowns need readable timing or the optional estimate below."])
    c = O.Card(L, ns.L["Estimated Countdown"])
    c.Check(ns.L["Allow Estimated Early Alerts"], config, "useEstimate", ns.L["Estimate from your last cast when exact timing is hidden. Cooldown reductions can make the estimate wrong. This never marks a spell ready."])
    c.Slider(ns.L["Estimated Cooldown in Seconds"], config, "estimatedCooldown", 0, 1200, 1)
    c.Finish()
    return L.finish()
end

function O.builders.appearance(host, config)
    local L = O.Layout(host)
    local c = O.Card(L, ns.L["Icon and Text"])
    c.Slider(ns.L["Icon Size"], config, "size", 24, 128, 1)
    c.Check(ns.L["Show Border"], config, "showBorder")
    c.Check(ns.L["Desaturate During Countdown"], config, "desaturate")
    c.Text(ns.L["Reminder Label"], config, "label", ns.L["Optional text on your cooldown reminder. PI requests show the recipient's name instead."])
    c.Select(ns.L["Name Position"], config, "nameLayout", O.Choices({ "overlay", ns.L["On Icon"], "left", ns.L["Left"], "right", ns.L["Right"], "none", ns.L["Hidden"] }))
    c.Select(ns.L["Font"], config, "font", Shared.GetFontList())
    c.Select(ns.L["Font Outline"], config, "fontOutline", O.Choices({ "", ns.L["None"], "OUTLINE", ns.L["Outline"], "THICKOUTLINE", ns.L["Thick Outline"] }))
    c.Slider(ns.L["Font Size"], config, "fontSize", 8, 32, 1)
    c.Color(ns.L["Text Color"], config, "textColor")
    c.Finish()
    c = O.Card(L, ns.L["Glow and Animation"])
    c.Select(ns.L["Icon Glow"], config, "glow", O.Choices({ "none", ns.L["None"], "proc", ns.L["Proc"], "pixel", ns.L["Pixel"], "autocast", ns.L["Autocast"], "button", ns.L["Button"] }))
    c.Color(ns.L["Glow Color"], config, "glowColor")
    c.Check(ns.L["Glow Only When Ready"], config, "glowReadyOnly")
    c.Select(ns.L["Animation"], config, "animation", O.Choices({ "none", ns.L["None"], "bounce", ns.L["Bounce"], "pulse", ns.L["Pulse"], "spin", ns.L["Spin"], "flash", ns.L["Flash"] }))
    c.Check(ns.L["Animate Only When Ready"], config, "animationReadyOnly")
    c.Finish()
    c = O.Card(L, ns.L["Position"])
    c.Slider(ns.L["Horizontal Offset"], config, "x", -2000, 2000, 1)
    c.Slider(ns.L["Vertical Offset"], config, "y", -1200, 1200, 1)
    c.Finish()
    L.intro(ns.L["Use Preview to drag this reminder, or position it in Layout Mode. PI recipient alerts use the same anchor and icon settings."])
    return L.finish()
end

function O.builders.sounds(host, config)
    local L = O.Layout(host)
    local c = O.Card(L, ns.L["Reminder Sounds"])
    c.Select(ns.L["Sound"], config, "sound", O.SoundChoices())
    c.Select(ns.L["Sound Channel"], config, "soundChannel", O.Choices({ "Master", ns.L["Master"], "SFX", ns.L["Sound Effects"], "Dialog", ns.L["Dialog"], "Music", ns.L["Music"], "Ambience", ns.L["Ambience"] }))
    c.Check(ns.L["Play When Ready"], config, "readySound")
    c.Check(ns.L["Play Before Ready"], config, "earlySound")
    c.Finish()
    O.Buttons(L, { { ns.L["Test Sound"], function() ns.SpellReminderSounds.Play(config.sound, config.soundChannel) end } })
    c = O.Card(L, ns.L["Text to Speech"])
    local voices = { { value = 0, text = ns.L["Default Voice"] } }
    for _, voice in ipairs(C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices() or {}) do
        voices[#voices + 1] = { value = voice.voiceID, text = voice.name }
    end
    c.Select(ns.L["Voice"], config, "voice", voices)
    c.Check(ns.L["Speak When Ready"], config, "ttsReady")
    c.Text(ns.L["Ready Announcement"], config, "ttsReadyText", ns.L["Leave empty to speak the spell name."])
    c.Check(ns.L["Speak Before Ready"], config, "ttsEarly")
    c.Text(ns.L["Early Announcement"], config, "ttsEarlyText", ns.L["Leave empty to speak the spell name."])
    c.Check(ns.L["Speak Countdown"], config, "ttsCountdown")
    c.Slider(ns.L["Countdown Starts At"], config, "countdownStart", 1, 10, 1)
    c.Finish()
    O.Buttons(L, { { ns.L["Test Voice"], function()
        ns.SpellReminderSounds.Speak(config.ttsReadyText ~= "" and config.ttsReadyText or ns.SpellReminderPresentation.Name(config), config.voice)
    end } })
    L.intro(ns.L["Countdown speech uses readable cooldown timing, or your opt-in estimate when timing is hidden. Ready announcements use the reported cooldown state."])
    return L.finish()
end

function O.builders.load(host, config, rebuild)
    local L = O.Layout(host)
    local c = O.Card(L, ns.L["Load Conditions"])
    c.Check(ns.L["Only for Known Spells"], config, "onlyKnown")
    c.Check(ns.L["Only in Combat"], config, "combatOnly")
    local classes = { { value = 0, text = ns.L["Any Class"] } }
    for id = 1, 13 do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo(id)
        if info then classes[#classes + 1] = { value = id, text = info.className } end
    end
    c.Select(ns.L["Class"], config, "classID", classes, nil, function()
        config.specs = {}; O.Refresh(); if rebuild then rebuild() end
    end)
    c.Finish()
    L.intro(ns.L["No selections means every specialization or content type is allowed."])
    c = O.Card(L, ns.L["Specializations"])
    local _, _, playerClassID = UnitClass("player")
    local classID = config.classID ~= 0 and config.classID or ns.SpellReminderModel.Plain(playerClassID)
    local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID or _G.GetSpecializationInfoForClassID
    if getSpec and classID then
        for index = 1, 4 do
            local id, name = getSpec(classID, index)
            if id then
                c.Check(name, config.specs, id, nil, function()
                    if not config.specs[id] then config.specs[id] = nil end
                    O.Refresh()
                end)
            end
        end
    end
    c.Finish()
    c = O.Card(L, ns.L["Content Types"])
    for _, item in ipairs(O.Choices({ "none", ns.L["Open World"], "party", ns.L["Dungeons"], "raid", ns.L["Raids"], "pvp", ns.L["Battlegrounds"], "arena", ns.L["Arenas"], "scenario", ns.L["Scenarios"] })) do
        c.Check(item.text, config.instances, item.value, nil, function()
            if not config.instances[item.value] then config.instances[item.value] = nil end
            O.Refresh()
        end)
    end
    c.Finish()
    return L.finish()
end

local function Tabs(config)
    local tabs = { { key = "timing", label = ns.L["Timing"] }, { key = "appearance", label = ns.L["Appearance"] },
        { key = "sounds", label = ns.L["Sounds"] }, { key = "load", label = ns.L["Load Conditions"] } }
    if config.pi then
        tabs[#tabs + 1] = { key = "tracking", label = ns.L["PI Tracking"] }
        tabs[#tabs + 1] = { key = "buffs", label = ns.L["Tracked Buffs"] }
        tabs[#tabs + 1] = { key = "requests", label = ns.L["Requests"] }
    end
    return tabs
end

function O.RenderTab(key, host, config, rebuild)
    local previous = ns.Settings.Util.ShallowCopy(GUI._searchContext)
    GUI:SetSearchContext({ tileId = "reminders", subPageIndex = 2, featureId = "spellRemindersPage",
        tabName = ns.L["Reminders"], subTabName = ns.L["Spell Reminders"], surfaceTabKey = key, category = "gameplay" })
    local ok, result = pcall(O.builders[key], host, config, rebuild)
    GUI:SetSearchContext(previous)
    if not ok then error(result, 0) end
    return result
end

function O.Build(content)
    local R = ns.SpellReminders
    O.rebuild, O.activeBody = nil, nil
    local L = O.Layout(content)
    if not R then
        L.intro(ns.L["The Reminders module is not loaded. Turn it on under Module Addons, then come back here."])
        return L.finish()
    end
    local db = R.Store()
    L.intro(ns.L["Create reminders for your spells. Power Infusion also highlights allies using offensive cooldowns and handles whisper requests."])
    local c = O.Card(L, ns.L["Spell Reminders"])
    c.Check(ns.L["Enable Spell Reminders"], db, "enabled")
    c.Finish()
    local ui = {}
    local selector = { value = selected }
    local options = {}
    for id, config in pairs(db.reminders) do
        options[#options + 1] = { value = id, text = ns.SpellReminderPresentation and ns.SpellReminderPresentation.Name(config) or tostring(id) }
    end
    table.sort(options, function(a, b) return a.text < b.text end)
    if not selected or not db.reminders[selected] then selected = options[1] and options[1].value end
    selector.value = selected
    local function ChangeSelection(id)
        if selected and R then R.Preview(selected, false) end
        selected = id
        if ui.rebuild then ui.rebuild() end
    end
    c = O.Card(L, ns.L["Choose a Spell"])
    c.Select(ns.L["Reminder"], selector, "value", options, nil, function(value) ChangeSelection(value) end)
    local custom = { id = "" }
    c.Text(ns.L["New Spell ID"], custom, "id", ns.L["Enter a spell ID, then click Add Spell."])
    c.Finish()
    local status
    local function Add(id)
        local config = R and R.Add(id)
        if config then
            if selected then R.Preview(selected, false) end
            selected = config.spellID
            -- The root is rebuilt so the selector includes the new spell.
            GUI:TeardownFrameTree(content)
            O.Build(content)
        elseif status then status:SetText(ns.L["Enter a valid spell ID."]) end
    end
    O.Buttons(L, { { ns.L["Add Spell"], function() Add(custom.id) end, 100 },
        { ns.L["Power Infusion Preset"], function() Add(10060) end, 170 },
        { ns.L["Innervate Preset"], function() Add(29166) end, 150 } })
    status = L.intro(ns.L["Changes to protected aura displays apply when combat restrictions allow."])
    local editorTop = math.abs(L.getY())
    local editor = CreateFrame("Frame", nil, content)
    L.placeCustom(editor, 500)
    ui.rebuild = function()
        GUI:TeardownFrameTree(editor)
        local config = selected and db.reminders[selected]
        if not config then
            local empty = O.Layout(editor)
            empty.intro(ns.L["Add a preset or custom spell to create your first reminder."])
            local h = empty.finish(); editor:SetHeight(h); content:SetHeight(editorTop + h + 30)
            return
        end
        if not config.pi and (activeTab == "tracking" or activeTab == "buffs" or activeTab == "requests") then activeTab = "timing" end
        local top = O.Layout(editor)
        O.Buttons(top, { { ns.L["Preview / Drag"], function() R.Preview(selected, not R.previews[selected]) end },
            { ns.L["Delete Reminder"], function()
                GUI:ShowConfirmation({ title = ns.L["Delete Reminder?"], message = ns.L["Delete the selected spell reminder?"],
                    acceptText = ns.L["Delete"], cancelText = ns.L["Cancel"], isDestructive = true,
                    onAccept = function() R.Remove(selected); selected = nil; GUI:TeardownFrameTree(content); O.Build(content) end })
            end } })
        local strip, paint = ns.Settings.FullSurface.CreateTabStrip(editor, { wrapRows = true, buttonSpacing = 10 })
        top.placeCustom(strip, 28)
        paint(Tabs(config), activeTab, function(key) activeTab = key; ui.rebuild() end)
        local body = CreateFrame("Frame", nil, editor)
        body:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", -15, -10)
        body:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 15, -10)
        O.activeBody = body
        local height = O.RenderTab(activeTab, body, config, ui.rebuild)
        local function Resize()
            editor:SetHeight(height + strip:GetHeight() + 60)
            content:SetHeight(editorTop + editor:GetHeight() + 30)
        end
        strip:HookScript("OnSizeChanged", Resize)
        Resize()
    end
    content:SetScript("OnHide", function()
        if R and selected then R.Preview(selected, false) end
    end)
    O.rebuild = ui.rebuild
    ui.rebuild()
    return content:GetHeight()
end

function O.CaptureSearch(host)
    local config = ns.SpellReminderModel.New(10060)
    for _, tab in ipairs(Tabs(config)) do
        if O.builders[tab.key] then O.RenderTab(tab.key, host, config) end
    end
    config.pi.whisper.mode = "rotation"
    O.RenderTab("requests", host, config)
    config.pi.separateBuffs = true
    O.RenderTab("buffs", host, config)
end

ns.Settings.Registry:RegisterFeature(ns.Settings.Schema.Feature({
    id = "spellRemindersPage", category = "gameplay", nav = { tileId = "reminders", subPageIndex = 2 },
    keywords = { "Power Infusion", "PIHelper", "Innervate", "BeKindRemind", "whisper", "reminder", "TTS" },
    searchNavigate = function(entry, context)
        if not ns.SpellReminders then return false end
        if not O.builders[entry.surfaceTabKey] then return false end
        activeTab = entry.surfaceTabKey
        if activeTab == "tracking" or activeTab == "buffs" or activeTab == "requests" then
            if ns.SpellReminders and ns.SpellReminders.Get(10060) then
                if selected then ns.SpellReminders.Preview(selected, false) end
                selected = 10060
            end
        end
        if O.rebuild then O.rebuild() end
        if context and context.opts then context.opts.searchRoot = O.activeBody end
        return true
    end,
    moduleEntry = {
        group = ns.L["Combat"], label = ns.L["Spell Reminders"], combatLocked = false,
        caption = ns.L["Spell cooldown reminders, spoken alerts, and Power Infusion coordination."],
        isEnabled = function() local db = ns.Helpers.GetModuleDB("spellReminders"); return db and db.enabled or false end,
        setEnabled = function(value)
            local db = ns.Helpers.GetModuleDB("spellReminders")
            if db then db.enabled = value end
            O.Refresh()
        end,
    },
    sections = { ns.Settings.Schema.Section({ id = "settings", kind = "page", minHeight = 80, build = O.Build }) },
}))
