local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
local RevealSetting
if ProviderFeatures and type(ProviderFeatures.Register) == "function" then
    local feature = ProviderFeatures:Register({
        id = "bonusRollFrame",
        moverKey = "bonusRollFrame",
        category = "qol",
        lookupKeys = { "bonusRoll" },
        nav = { tileId = "qol", subPageIndex = 16 },
        searchContext = { tabIndex = 17, tabName = "Quality of Life", subTabIndex = 16, subTabName = "Bonus Roll" },
        getDB = function(profile)
            return profile and profile.general and profile.general.bonusRoll
        end,
        providerKey = "bonusRollFrame",
    })
    if feature then
        feature.searchNavigate = function(entry)
            if RevealSetting then RevealSetting(entry) end
        end
    end
end


local function BuildBonusRollSettings(content, U)
    local GUI = QUI.GUI
    local Opts = ns.QUI_Options
    local profile = U.GetProfileDB()
    local db = profile and profile.general and profile.general.bonusRoll
    if not db then return 80 end
    db.difficulty = db.difficulty or {}
    db.mythicPlus = db.mythicPlus or { mode = "show", minLevel = 10 }
    local runtime = ns.BonusRoll
    local layout = ns.QUI_SettingsLayoutShared.MakeLayout(content)
    local updates = {}
    local function Refresh()
        for _, update in ipairs(updates) do update() end
    end
    local function Track(widget, enabled)
        updates[#updates + 1] = function() widget:SetEnabled(db.enabled and (not enabled or enabled())) end
        return widget
    end
    local function Row(card, label, widget, description)
        if description then GUI:AttachTooltip(widget, description, label) end
        return Opts.BuildSettingRow(card.frame, label, widget)
    end
    local function Rule(id)
        if not db.difficulty[id] then db.difficulty[id] = { hide = false, encounters = {} } end
        db.difficulty[id].encounters = db.difficulty[id].encounters or {}
        return db.difficulty[id]
    end
    local function Checkbox(card, label, key, target, enabled, dynamic, description)
        return Row(card, label, Track(GUI:CreateFormCheckbox(card.frame, nil, key, target, Refresh,
            { searchable = not dynamic, pinnable = not dynamic,
              description = description or ns.L["Hide all bonus roll prompts for this content difficulty. Changes apply to future offers."] }), enabled))
    end
    local function Collapsible(parentLayout, parent, title, build, expanded, dynamic)
        local section = CreateFrame("Frame", nil, parent)
        local body = CreateFrame("Frame", nil, section)
        body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -32)
        body:SetPoint("RIGHT", section, "RIGHT", 0, 0)
        local header
        section._expanded = expanded == true
        section._sectionTitle = title
        section._body = body
        body._logicalSection = section
        local function UpdateHeight()
            body:SetShown(section._expanded)
            section:SetHeight(32 + (section._expanded and body:GetHeight() or 0))
            if header then header:SetText((section._expanded and "- " or "+ ") .. title) end
            parentLayout.relayoutSections()
        end
        function section:SetExpanded(value)
            self._expanded = value == true
            UpdateHeight()
        end
        if not dynamic then GUI:SetSearchSection(title) end
        header = GUI:CreateButton(section, title, 200, 26, function()
            section:SetExpanded(not section._expanded)
        end)
        header:SetPoint("TOPLEFT")
        header:SetPoint("RIGHT", section, "RIGHT", 0, 0)
        build(body, UpdateHeight)
        parentLayout.sections[#parentLayout.sections + 1] = section
        UpdateHeight()
        if not dynamic then
            if content.RegisterSection then content:RegisterSection(title, title, section) end
            if GUI.RegisterSectionEntry and GUI._searchContext.tabIndex then
                GUI.RegisterSectionEntry(GUI._searchContext.tabIndex, GUI._searchContext.subTabIndex, title, section, content)
            end
        end
        return section
    end

    layout.headerAt(ns.L["Bonus Roll"])
    layout.intro(ns.L["Checked filters hide bonus roll prompts. Changes apply to future offers. Hidden rolls keep their original expiry and can be reopened without spending currency."])
    local general = layout.sectionAt()
    general.AddRow(Row(general, ns.L["Enable Bonus Roll Filtering"], GUI:CreateFormCheckbox(general.frame,
        nil, "enabled", db, Refresh,
        { description = ns.L["Apply your bonus roll filters to new offers. Turning this off keeps your saved filters and allows future prompts. Use Show Pending Roll to reopen a hidden offer before it expires."] })),
        Checkbox(general, ns.L["Show a Chat Link When a Roll Is Hidden"], "announce", db, nil, nil,
            ns.L["Print a local chat message with a clickable link when a bonus roll is hidden. The link reopens that offer before it expires and works without QUI Chat."]))
    local pending = GUI:CreateButton(general.frame, ns.L["Show Pending Roll"], 180, 26, function()
        if runtime then runtime.ShowPendingRoll() end
    end)
    local elapsedSinceCheck = 0
    pending:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceCheck = elapsedSinceCheck + elapsed
        if elapsedSinceCheck < 0.5 then return end
        elapsedSinceCheck = 0
        pending:SetEnabled(runtime and runtime.GetPendingRoll() ~= nil or false)
    end)
    pending:SetEnabled(runtime and runtime.GetPendingRoll() ~= nil or false)
    general.AddRow(Row(general, ns.L["Hidden Roll"], pending,
        ns.L["Reopen the current hidden bonus roll before its original timer expires. This does not roll or spend currency. Available only while a hidden offer is pending."]),
        Row(general, ns.L["Reset Filters"], Track(GUI:CreateButton(general.frame, ns.L["Clear All Filters"], 180, 26, function()
        GUI:ShowConfirmation({
            title = ns.L["Clear All Filters"],
            message = ns.L["Clear every bonus roll filter in this profile? All difficulties and bosses will be allowed."],
            acceptText = ns.L["Clear"],
            isDestructive = true,
            onAccept = function()
                if U.GetProfileDB() ~= profile then return end
                if runtime then runtime.ClearFilters() end
                if Settings.RenderAdapters then
                    Settings.RenderAdapters.NotifyProviderChanged("bonusRollFrame", { structural = true })
                end
            end,
        })
    end)), ns.L["Clear all difficulty and boss filters in this profile and set Mythic+ to Show All. Your enable and chat-link preferences are kept. Confirmation is required."]))
    layout.closeSection(general)

    local raidOptions = {
        { value = 17, text = ns.L["LFR"] },
        { value = 14, text = ns.L["Normal"] },
        { value = 15, text = ns.L["Heroic"] },
        { value = 16, text = ns.L["Mythic"] },
        { value = 220, text = ns.L["Story"] },
    }
    local raidLabels = {
        [17] = ns.L["Hide All LFR Raid Rolls"],
        [14] = ns.L["Hide All Normal Raid Rolls"],
        [15] = ns.L["Hide All Heroic Raid Rolls"],
        [16] = ns.L["Hide All Mythic Raid Rolls"],
        [220] = ns.L["Hide All Story Raid Rolls"],
    }
    local function BuildBosses(body, id, label, onHeight)
        local bossLayout = ns.QUI_SettingsLayoutShared.MakeLayout(body)
        local rule = Rule(id)
        local card = bossLayout.sectionAt()
        card.AddRow(Checkbox(card, label, "hide", rule, nil, nil,
            ns.L["Hide every bonus roll in this category. Individual boss selections are kept and apply again when this is turned off."]))
        bossLayout.closeSection(card)
        local summary = bossLayout.intro(ns.L["Individual Boss Filters: 0"])
        updates[#updates + 1] = function()
            local count = 0
            for id, hidden in pairs(rule.encounters) do
                if type(id) == "number" and hidden then count = count + 1 end
            end
            summary:SetText(rule.hide and ns.L["All rolls at this difficulty are hidden."]
                or string.format(ns.L["Individual Boss Filters: %d"], count))
        end
        local groups = runtime and runtime.GetEncounterGroups(id) or {}
        if #groups == 0 then
            bossLayout.intro(ns.L["No bosses are available yet. Reopen this page after the Encounter Journal loads or a bonus roll is offered."])
        end
        for _, group in ipairs(groups) do
            Collapsible(bossLayout, body, group.name, function(groupBody)
                local groupLayout = ns.QUI_SettingsLayoutShared.MakeLayout(groupBody)
                local bossCard = groupLayout.sectionAt()
                local widgets = {}
                local function SelectAll(value)
                    for _, widget in ipairs(widgets) do widget:SetValue(value) end
                end
                local active = function() return not rule.hide end
                local selectButton = Track(GUI:CreateButton(bossCard.frame, ns.L["Select All"], 120, 24, function() SelectAll(true) end), active)
                local clearButton = Track(GUI:CreateButton(bossCard.frame, ns.L["Clear Selection"], 120, 24, function() SelectAll(false) end), active)
                bossCard.AddRow(Row(bossCard, ns.L["Bosses to Hide"], selectButton,
                    ns.L["Select every boss in this group to hide their bonus roll prompts at the selected difficulty."]),
                    Row(bossCard, "", clearButton,
                        ns.L["Clear the individual boss filters in this group for the selected difficulty."]))
                local left
                for _, encounter in ipairs(group.encounters) do
                    local cell = Checkbox(bossCard, encounter.name, encounter.id, rule.encounters, active, true,
                        ns.L["Hide bonus roll prompts from this boss at the selected difficulty. Other difficulties are unchanged. Changes apply to future offers."])
                    widgets[#widgets + 1] = cell._widget
                    if left then
                        bossCard.AddRow(left, cell)
                        left = nil
                    else
                        left = cell
                    end
                end
                if left then bossCard.AddRow(left) end
                groupLayout.closeSection(bossCard)
                groupLayout.finish()
            end, false, true)
        end
        local relayout = bossLayout.relayoutSections
        bossLayout.relayoutSections = function()
            relayout()
            onHeight()
        end
        bossLayout.relayoutSections()
    end

    local raidState
    local raidDropdown
    local selectRaidDifficulty
    local raidSection = Collapsible(layout, content, ns.L["Raids"], function(body, onHeight)
        local raidLayout = ns.QUI_SettingsLayoutShared.MakeLayout(body)
        local state = { difficulty = 14, _quiTransientOptionsProxy = true }
        raidState = state
        local pages = {}
        local function SelectDifficulty()
            local height = 0
            for id, page in pairs(pages) do
                local selected = id == state.difficulty
                page:SetShown(selected)
                if selected then height = page:GetHeight() end
            end
            body:SetHeight(math.abs(raidLayout.getY()) + height + 8)
            onHeight()
        end
        selectRaidDifficulty = SelectDifficulty
        local difficultyCard = raidLayout.sectionAt()
        raidDropdown = Track(GUI:CreateFormDropdown(difficultyCard.frame,
            nil, raidOptions, "difficulty", state, SelectDifficulty,
            { searchable = false, description = ns.L["Choose which raid difficulty to configure below. Each difficulty keeps its own filters. This does not change your current raid difficulty."] }))
        GUI:SetWidgetProviderSyncOptions(raidDropdown, { auto = false })
        difficultyCard.AddRow(Row(difficultyCard, ns.L["Raid Difficulty"], raidDropdown))
        raidLayout.closeSection(difficultyCard)
        for _, option in ipairs(raidOptions) do
            local page = CreateFrame("Frame", nil, body)
            page:SetPoint("TOPLEFT", body, "TOPLEFT", 0, raidLayout.getY())
            page:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            pages[option.value] = page
            BuildBosses(page, option.value, raidLabels[option.value], SelectDifficulty)
        end
        SelectDifficulty()
    end, true)

    local worldSection = Collapsible(layout, content, ns.L["World Bosses"], function(body, onHeight)
        BuildBosses(body, 172, ns.L["Hide All World Boss Rolls"], onHeight)
    end)

    local revealMinimum = false
    local dungeonSection = Collapsible(layout, content, ns.L["Dungeons & Mythic+"], function(body, onHeight)
        local dungeonLayout = ns.QUI_SettingsLayoutShared.MakeLayout(body)
        local card = dungeonLayout.sectionAt()
        card.AddRow(Checkbox(card, ns.L["Hide Normal Dungeon Rolls"], "hide", Rule(1)),
            Checkbox(card, ns.L["Hide Heroic Dungeon Rolls"], "hide", Rule(2)))
        card.AddRow(Checkbox(card, ns.L["Hide Mythic Dungeon Rolls"], "hide", Rule(23)),
            Row(card, ns.L["Mythic+ Rolls"], Track(GUI:CreateFormDropdown(card.frame, nil, {
            { value = "show", text = ns.L["Show All"] },
            { value = "hide", text = ns.L["Hide All"] },
            { value = "minimum", text = ns.L["Minimum Key Level"] },
        }, "mode", db.mythicPlus, function()
            revealMinimum = false
            Refresh()
        end, { description = ns.L["Show all Mythic+ bonus rolls, hide all of them, or show only rolls at or above your minimum key level. An unknown key level stays visible in Minimum Key Level mode."] }))))
        dungeonLayout.closeSection(card)
        local minimum = dungeonLayout.sectionAt()
        minimum.AddRow(Row(minimum, ns.L["Minimum Key Level"], Track(GUI:CreateFormSlider(minimum.frame,
            nil, 2, 40, 1, "minLevel", db.mythicPlus, nil,
            { description = ns.L["Show rolls from this key level and higher. Rolls with an unknown key level stay visible."] }),
            function() return db.mythicPlus.mode == "minimum" end)))
        minimum.Finalize()
        updates[#updates + 1] = function()
            local shown = db.mythicPlus.mode == "minimum" or revealMinimum
            minimum.frame:SetShown(shown)
            body:SetHeight(math.abs(dungeonLayout.getY()) + (shown and minimum.frame:GetHeight() or 0) + 8)
            onHeight()
        end
    end)

    local delveSection = Collapsible(layout, content, ns.L["Delves & Other Content"], function(body)
        local otherLayout = ns.QUI_SettingsLayoutShared.MakeLayout(body)
        local card = otherLayout.sectionAt()
        local left = Checkbox(card, ns.L["Hide Delve Rolls"], "hide", Rule(208))
        local known = { [1] = true, [2] = true, [23] = true, [8] = true, [172] = true, [208] = true, [233] = true }
        for _, option in ipairs(raidOptions) do known[option.value] = true end
        for _, id in ipairs(runtime and runtime.GetSeenDifficulties() or {}) do
            if not known[id] then
                local name = _G.GetDifficultyInfo and _G.GetDifficultyInfo(id) or tostring(id)
                local cell = Checkbox(card, string.format(ns.L["Hide %s Rolls"], name), "hide", Rule(id), nil, true)
                if left then
                    card.AddRow(left, cell)
                    left = nil
                else
                    left = cell
                end
            end
        end
        if left then card.AddRow(left) end
        otherLayout.closeSection(card)
        otherLayout.finish()
    end)
    RevealSetting = function(entry)
        local label = entry.label
        for id, raidLabel in pairs(raidLabels) do
            if label == raidLabel then
                raidState.difficulty = id
                raidDropdown:SetValue(id, true)
                selectRaidDifficulty()
                raidSection:SetExpanded(true)
                return
            end
        end
        if entry.sectionName == ns.L["Raids"] then
            raidSection:SetExpanded(true)
        elseif entry.sectionName == ns.L["World Bosses"] then
            worldSection:SetExpanded(true)
        elseif entry.sectionName == ns.L["Dungeons & Mythic+"] then
            revealMinimum = label == ns.L["Minimum Key Level"]
            Refresh()
            dungeonSection:SetExpanded(true)
        elseif entry.sectionName == ns.L["Delves & Other Content"] then
            delveSection:SetExpanded(true)
        end
    end
    Refresh()
    layout.relayoutSections()
    return content:GetHeight()
end

do
    local function RegisterBonusRollProvider()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        local U = ns.QUI_LayoutMode_Utils
        if not settingsPanel or not U
            or type(U.BuildPositionCollapsible) ~= "function"
            or type(U.StandardRelayout) ~= "function" then
            return
        end

        settingsPanel:RegisterSharedProvider("bonusRollFrame", {
            build = function(content, key)
                if not U._layoutModePositionOnly then
                    return BuildBonusRollSettings(content, U)
                end
                local sections = {}
                local function relayout() U.StandardRelayout(content, sections) end
                U.BuildPositionCollapsible(content, "bonusRollFrame", nil, sections, relayout)
                if type(U.BuildOpenFullSettingsLink) == "function" then
                    U.BuildOpenFullSettingsLink(content, key, sections, relayout)
                end
                relayout()
                return content:GetHeight()
            end,
        })

        local adapters = Settings and Settings.RenderAdapters
        if adapters and type(adapters.NotifyProviderChanged) == "function" then
            adapters.NotifyProviderChanged("bonusRollFrame", { structural = true })
        end
    end

    local ProviderPanels = Settings and Settings.ProviderPanels
    if ProviderPanels and type(ProviderPanels.RegisterAfterLoad) == "function" then
        ProviderPanels:RegisterAfterLoad(function()
            RegisterBonusRollProvider()
        end)
    else
        RegisterBonusRollProvider()
    end
end
