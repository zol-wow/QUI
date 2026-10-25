local _, ns = ...
local O = { builders = {} }
ns.SpellReminderOptions = O
local GUI, Shared = QUI.GUI, ns.QUI_Options
local selected, activeTab = nil, "general"

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
    function card.Select(label, db, key, choices, description, change, options)
        return card.Row(label, GUI:CreateFormDropdown(card.frame, nil, choices, key, db, change or O.Refresh, { description = description }, options))
    end
    function card.Text(label, db, key, description, change)
        return card.Row(label, GUI:CreateFormEditBox(card.frame, nil, key, db, change or O.Refresh,
            { description = description, maxLetters = 1000 }))
    end
    function card.Color(label, db, key, description)
        return card.Row(label, GUI:CreateFormColorPicker(card.frame, nil, key, db, O.Refresh, { description = description }))
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
    c.Check(ns.L["Enable This Reminder"], config, "enabled", ns.L["Show alerts for this spell when its timing and load conditions are met."])
    c.Check(ns.L["Show When Ready"], config, "showWhenReady", ns.L["Show the reminder when the spell finishes its cooldown."])
    c.Slider(ns.L["Hide After Ready"], config, "readyDuration", 0, 60, 1, ns.L["Seconds to show the ready reminder. Zero keeps it visible until you cast."])
    c.Check(ns.L["Show Before Ready"], config, "showBeforeReady", ns.L["Show a countdown reminder shortly before the spell becomes ready."])
    c.Slider(ns.L["Seconds Before Ready"], config, "beforeReadyTime", 1, 30, 1, ns.L["How many seconds before the cooldown ends to show the reminder and trigger early alerts."])
    c.Check(ns.L["Remind at Encounter Start"], config, "encounterStart", ns.L["Show the reminder when a boss encounter starts, even if the spell is on cooldown."])
    c.Finish()
    L.intro(ns.L["WoW can display an exact cooldown while hiding its timing from addons. Early sounds and spoken countdowns need readable timing or the optional estimate below."])
    c = O.Card(L, ns.L["Estimated Countdown"])
    c.Check(ns.L["Allow Estimated Early Alerts"], config, "useEstimate", ns.L["Estimate from your last cast when exact timing is hidden. Cooldown reductions can make the estimate wrong. This never marks a spell ready."])
    c.Slider(ns.L["Estimated Cooldown in Seconds"], config, "estimatedCooldown", 0, 1200, 1, ns.L["Cooldown length used for estimated early alerts after your last cast. Zero disables the estimate."])
    c.Finish()
    return L.finish()
end

function O.builders.appearance(host, config)
    local L = O.Layout(host)
    local c = O.Card(L, ns.L["Icon and Text"])
    c.Slider(ns.L["Icon Size"], config, "size", 24, 128, 1, ns.L["Width and height of the reminder icon and recipient alerts, in UI units."])
    c.Check(ns.L["Show Border"], config, "showBorder", ns.L["Draw a border around the reminder icon."])
    c.Check(ns.L["Desaturate During Countdown"], config, "desaturate", ns.L["Show the spell icon in grayscale until the cooldown is ready."])
    c.Text(ns.L["Reminder Label"], config, "label", ns.L["Optional text on your cooldown reminder. PI requests show the recipient's name instead."])
    c.Select(ns.L["Name Position"], config, "nameLayout", O.Choices({ "overlay", ns.L["On Icon"], "left", ns.L["Left"], "right", ns.L["Right"], "none", ns.L["Hidden"] }), ns.L["Place the reminder label on the icon, beside it, or hide it."])
    c.Select(ns.L["Font"], config, "font", Shared.GetFontList(), ns.L["Font used for reminder labels and recipient names. An empty selection uses the global UI font."])
    c.Select(ns.L["Font Outline"], config, "fontOutline", O.Choices({ "", ns.L["None"], "OUTLINE", ns.L["Outline"], "THICKOUTLINE", ns.L["Thick Outline"] }), ns.L["Outline style used to keep reminder text readable over the icon."])
    c.Slider(ns.L["Font Size"], config, "fontSize", 8, 32, 1, ns.L["Text size for the reminder label and recipient names."])
    c.Color(ns.L["Text Color"], config, "textColor", ns.L["Color of the reminder label and recipient names."])
    c.Finish()
    c = O.Card(L, ns.L["Glow and Animation"])
    c.Select(ns.L["Icon Glow"], config, "glow", O.Choices({ "none", ns.L["None"], "proc", ns.L["Proc"], "pixel", ns.L["Pixel"], "autocast", ns.L["Autocast"], "button", ns.L["Button"] }), ns.L["Glow effect displayed around the reminder icon."])
    c.Color(ns.L["Glow Color"], config, "glowColor", ns.L["Color used by the reminder icon glow."])
    c.Check(ns.L["Glow Only When Ready"], config, "glowReadyOnly", ns.L["Hide the icon glow during the cooldown countdown."])
    c.Select(ns.L["Animation"], config, "animation", O.Choices({ "none", ns.L["None"], "bounce", ns.L["Bounce"], "pulse", ns.L["Pulse"], "spin", ns.L["Spin"], "flash", ns.L["Flash"] }), ns.L["Animate the reminder icon while it is visible."])
    c.Check(ns.L["Animate Only When Ready"], config, "animationReadyOnly", ns.L["Pause the icon animation during the cooldown countdown."])
    c.Finish()
    c = O.Card(L, ns.L["Position"])
    c.Slider(ns.L["Horizontal Offset"], config, "x", -2000, 2000, 1, ns.L["Horizontal distance from the center of the screen. Positive values move the reminder right."])
    c.Slider(ns.L["Vertical Offset"], config, "y", -1200, 1200, 1, ns.L["Vertical distance from the center of the screen. Positive values move the reminder up."])
    c.Finish()
    L.intro(ns.L["Use Preview to drag this reminder, or position it in Layout Mode. PI recipient alerts use the same anchor and icon settings."])
    return L.finish()
end

function O.builders.sounds(host, config)
    local L = O.Layout(host)
    local c = O.Card(L, ns.L["Reminder Sounds"])
    c.Select(ns.L["Sound"], config, "sound", O.SoundChoices(), ns.L["Sound used by this spell reminder. Select None to silence these alerts."])
    c.Select(ns.L["Sound Channel"], config, "soundChannel", O.Choices({ "Master", ns.L["Master"], "SFX", ns.L["Sound Effects"], "Dialog", ns.L["Dialog"], "Music", ns.L["Music"], "Ambience", ns.L["Ambience"] }), ns.L["Audio channel used for ready and early reminder sounds."])
    c.Check(ns.L["Play When Ready"], config, "readySound", ns.L["Play the selected sound when the spell becomes ready."])
    c.Check(ns.L["Play Before Ready"], config, "earlySound", ns.L["Play the selected sound at the configured time before the spell becomes ready. Requires readable timing or an enabled estimate."])
    c.Finish()
    O.Buttons(L, { { ns.L["Test Sound"], function() ns.SpellReminderSounds.Play(config.sound, config.soundChannel) end } })
    c = O.Card(L, ns.L["Text to Speech"])
    local voices = { { value = 0, text = ns.L["Default Voice"] } }
    for _, voice in ipairs(C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices() or {}) do
        voices[#voices + 1] = { value = voice.voiceID, text = voice.name }
    end
    c.Select(ns.L["Voice"], config, "voice", voices, ns.L["Voice used for spoken ready alerts, early alerts, and countdowns."])
    c.Check(ns.L["Speak When Ready"], config, "ttsReady", ns.L["Speak the ready announcement when the spell becomes ready."])
    c.Text(ns.L["Ready Announcement"], config, "ttsReadyText", ns.L["Leave empty to speak the spell name."])
    c.Check(ns.L["Speak Before Ready"], config, "ttsEarly", ns.L["Speak the early announcement at the configured time before the spell becomes ready."])
    c.Text(ns.L["Early Announcement"], config, "ttsEarlyText", ns.L["Leave empty to speak the spell name."])
    c.Check(ns.L["Speak Countdown"], config, "ttsCountdown", ns.L["Speak the remaining whole seconds before the spell becomes ready. Requires readable timing or an enabled estimate."])
    c.Slider(ns.L["Countdown Starts At"], config, "countdownStart", 1, 10, 1, ns.L["Number of remaining seconds at which the spoken countdown begins."])
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
    c.Check(ns.L["Only for Known Spells"], config, "onlyKnown", ns.L["Load this reminder only when your character knows the spell or its current replacement."])
    c.Check(ns.L["Only in Combat"], config, "combatOnly", ns.L["Show this spell reminder only while you are in combat."])
    local classes = { { value = 0, text = ns.L["Any Class"] } }
    for id = 1, 13 do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo(id)
        if info then classes[#classes + 1] = { value = id, text = info.className } end
    end
    c.Select(ns.L["Class"], config, "classID", classes, ns.L["Load this reminder only for the selected class. Changing class clears specialization selections."], function()
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
                c.Check(name, config.specs, id, ns.L["Allow this specialization. Leave all specializations unchecked to allow every specialization."], function()
                    if not config.specs[id] then config.specs[id] = nil end
                    O.Refresh()
                end)
            end
        end
    end
    c.Finish()
    c = O.Card(L, ns.L["Content Types"])
    for _, item in ipairs(O.Choices({ "none", ns.L["Open World"], "party", ns.L["Dungeons"], "raid", ns.L["Raids"], "pvp", ns.L["Battlegrounds"], "arena", ns.L["Arenas"], "scenario", ns.L["Scenarios"] })) do
        c.Check(item.text, config.instances, item.value, ns.L["Allow this content type. Leave all content types unchecked to allow every type."], function()
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
        tabs[#tabs + 1] = { key = "requests", label = ns.L["Requests"], isSectionAvailable = function(id)
            local whisper = type(config.pi) == "table" and config.pi.whisper
            local rotation = whisper and whisper.mode == "rotation"
            if id == ns.L["Rotation Order"] then return rotation == true end
            if id == ns.L["Priority Order"] then return not rotation end
            return true
        end }
    end
    return tabs
end
O.GetTabs = Tabs

local function ReminderSelection(db)
    local options = {}
    for id, config in pairs(db.reminders) do
        options[#options + 1] = { value = id, text = ns.SpellReminderPresentation and ns.SpellReminderPresentation.Name(config) or tostring(id) }
    end
    table.sort(options, function(a, b) return a.text < b.text end)
    return options, selected and db.reminders[selected] and selected or (options[1] and options[1].value)
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
    local ui = {}
    local _, id = ReminderSelection(db)
    selected = id
    local editor = CreateFrame("Frame", nil, content)
    L.placeCustom(editor, 500)
    local recoveredInset, recovering
    local function VerifyEditorBounds()
        if editor:GetParent() ~= content or recovering then return end
        ns.QUI_SettingsLayoutShared.VerifyInitialBounds(editor, content, function(self)
            recovering = true
            local point, relative, relativePoint, x, y = self:GetPoint(1)
            self:ClearAllPoints()
            self:SetPoint(point, relative, relativePoint, x, y)
            self:SetWidth(math.max(1, content:GetWidth() - 2 * x))
            recoveredInset = x
        end)
    end
    editor:SetScript("OnShow", function()
        if recovering then recovering = nil else VerifyEditorBounds() end
    end)
    editor:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    content:HookScript("OnSizeChanged", function()
        if editor:GetParent() ~= content then return end
        if recoveredInset then editor:SetWidth(math.max(1, content:GetWidth() - 2 * recoveredInset)) end
        VerifyEditorBounds()
    end)
    local activePage, sidebarTabs
    local function ScrollFrame()
        local owner = content
        while owner and not owner._scrollFrame do owner = owner.GetParent and owner:GetParent() end
        return owner and owner._scrollFrame
    end
    local function SelectTab(key)
        local config = selected and db.reminders[selected]
        local available = key == "general"
        for _, tab in ipairs(config and Tabs(config) or {}) do
            if tab.key == key then available = true; break end
        end
        if not available or key == activeTab then return false end
        activeTab = key
        ui.rebuild()
        local scroll = ScrollFrame()
        if scroll then
            local controller = ns.UIKit and ns.UIKit.GetSmoothScroll and ns.UIKit.GetSmoothScroll(scroll)
            if controller then controller:ScrollTo(0, true) else scroll:SetVerticalScroll(0) end
        end
        return true
    end
    if GUI.RegisterTileSurfacePages then
        sidebarTabs = GUI:RegisterTileSurfacePages(content, {
            rootKey = "general",
            selectRoot = function() return SelectTab("general") end,
            getTabs = function()
                local config = selected and db.reminders[selected]
                return config and Tabs(config) or {}
            end,
            getActiveTab = function() return activeTab end,
            selectTab = SelectTab,
            getPage = function(key)
                if key ~= activeTab or not activePage then return nil end
                activePage._scrollFrame = ScrollFrame()
                return activePage
            end,
        })
    end
    local function Preview()
        R.Preview(selected, not R.previews[selected])
    end
    local function General(host, config)
        local root = O.Layout(host)
        root.intro(ns.L["Create reminders for your spells. Power Infusion also highlights allies using offensive cooldowns and handles whisper requests."])
        local c = O.Card(root, ns.L["Spell Reminders"])
        c.Check(ns.L["Enable Spell Reminders"], db, "enabled", ns.L["Enable the configured spell reminders. Individual reminders also have their own enable switch."])
        c.Finish()
        local options = ReminderSelection(db)
        local selector = { value = selected, _quiTransientOptionsProxy = true }
        c = O.Card(root, ns.L["Choose a Spell"])
        local reminder = c.Select(ns.L["Reminder"], selector, "value", options,
            ns.L["Choose a reminder you have already added. Use a preset or enter a spell ID and click Add Spell to create one."],
            function(value)
                if selected then R.Preview(selected, false) end
                selected = value
                ui.rebuild()
            end, { placeholder = ns.L["No reminders yet"] })
        reminder:SetEnabled(#options > 0, ns.L["Add a preset or custom spell to create your first reminder."])
        local custom = { id = "", _quiTransientOptionsProxy = true }
        c.Text(ns.L["New Spell ID"], custom, "id", ns.L["Enter a spell ID, then click Add Spell."])
        c.Finish()
        local status
        local function Add(spellID)
            local added = R.Add(spellID)
            if added then
                if selected then R.Preview(selected, false) end
                selected, activeTab = added.spellID, "general"
                ui.rebuild()
            elseif status then status:SetText(ns.L["Enter a valid spell ID."]) end
        end
        O.Buttons(root, { { ns.L["Add Spell"], function() Add(custom.id) end, 100 },
            { ns.L["Power Infusion Preset"], function() Add(10060) end, 170 },
            { ns.L["Innervate Preset"], function() Add(29166) end, 150 } })
        status = root.intro(ns.L["Changes to protected aura displays apply when combat restrictions allow."])
        if config then
            O.Buttons(root, { { ns.L["Preview / Drag"], Preview },
                { ns.L["Delete Reminder"], function()
                    GUI:ShowConfirmation({ title = ns.L["Delete Reminder?"], message = ns.L["Delete the selected spell reminder?"],
                        acceptText = ns.L["Delete"], cancelText = ns.L["Cancel"], isDestructive = true,
                        onAccept = function()
                            R.Remove(selected)
                            local _, nextID = ReminderSelection(db)
                            selected = nextID
                            ui.rebuild()
                        end })
                end } })
        else
            root.intro(ns.L["Add a preset or custom spell to create your first reminder."])
        end
        return root.finish()
    end
    ui.rebuild = function()
        activePage, O.activeBody = nil, nil
        GUI:TeardownFrameTree(editor)
        local config = selected and db.reminders[selected]
        if not config then activeTab = "general"
        elseif not config.pi and (activeTab == "tracking" or activeTab == "buffs" or activeTab == "requests") then activeTab = "timing" end
        local top = O.Layout(editor)
        if activeTab ~= "general" then
            top.intro(ns.SpellReminderPresentation.Name(config))
            O.Buttons(top, { { ns.L["Preview / Drag"], Preview } })
        end
        local strip, paint, tabs
        if not sidebarTabs and config then
            tabs = { { key = "general", label = ns.L["General"] } }
            for _, tab in ipairs(Tabs(config)) do tabs[#tabs + 1] = tab end
            strip, paint = ns.Settings.FullSurface.CreateTabStrip(editor, { wrapRows = true, buttonSpacing = 10 })
            top.placeCustom(strip, 28)
            paint(tabs, activeTab, SelectTab)
        end
        local body = CreateFrame("Frame", nil, editor)
        if strip then
            body:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", -15, -10)
            body:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 15, -10)
        else
            body:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, top.getY() - 10)
            body:SetPoint("TOPRIGHT", editor, "TOPRIGHT", 0, top.getY() - 10)
        end
        if sidebarTabs and GUI.InitializeNavigationSections then GUI:InitializeNavigationSections(body) end
        O.activeBody = body
        if activeTab == "general" then
            local previous = ns.Settings.Util.ShallowCopy(GUI._searchContext)
            GUI:SetSearchContext({ tileId = "reminders", subPageIndex = 2, featureId = "spellRemindersPage",
                tabName = ns.L["Reminders"], subTabName = ns.L["Spell Reminders"], category = "gameplay" })
            General(body, config)
            GUI:SetSearchContext(previous)
        else
            O.RenderTab(activeTab, body, config, ui.rebuild)
        end
        body._contentBody = body
        activePage = body
        local function Resize()
            if body ~= O.activeBody then return end
            local _, _, _, _, y = editor:GetPoint(1)
            if not y then return end
            local _, _, _, _, bodyY = body:GetPoint(1)
            local offset = math.abs(bodyY)
            if strip then
                local _, _, _, _, stripY = strip:GetPoint(1)
                offset = offset + math.abs(stripY) + strip:GetHeight()
            end
            editor:SetHeight(body:GetHeight() + offset + 30)
            content:SetHeight(math.abs(y) + editor:GetHeight() + 30)
            VerifyEditorBounds()
        end
        if strip then
            local stripWidth = strip:GetWidth()
            strip:HookScript("OnSizeChanged", function(self, width)
                if body ~= O.activeBody then return end
                if width ~= stripWidth then
                    stripWidth = width
                    paint(tabs, activeTab, SelectTab)
                end
                Resize()
            end)
        end
        body:HookScript("OnSizeChanged", Resize)
        Resize()
        if sidebarTabs then GUI:RefreshTileSurfacePages(content) end
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
    getNavigationTabs = function()
        local db = ns.SpellReminders and ns.SpellReminders.Store()
        if not db then return {} end
        local _, id = ReminderSelection(db)
        return id and Tabs(db.reminders[id]) or {}
    end,
    render = {
        layout = function(host, options)
            return ns.Settings.RenderAdapters.RenderLayoutRoute(host, options and options.providerKey)
        end,
    },
    onNavigate = function(key)
        local id = type(key) == "string" and tonumber(key:match("^spellReminder:(%d+)$"))
        local R = ns.SpellReminders
        if not id or not R or not R.Get(id) then return end
        if selected then R.Preview(selected, false) end
        selected, activeTab = id, "general"
        if O.rebuild then O.rebuild() end
    end,
    searchNavigate = function(entry, context)
        if not ns.SpellReminders then return false end
        if entry.surfaceTabKey and entry.surfaceTabKey ~= "general" and not O.builders[entry.surfaceTabKey] then return false end
        activeTab = entry.surfaceTabKey or "general"
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

local R = ns.SpellReminders
if R and R.SyncLayoutSettings then R.SyncLayoutSettings() end
