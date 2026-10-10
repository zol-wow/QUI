-- luacheck: globals PagedContentFrameBaseMixin MonthlyActivitiesFrameMixin TalentFrameBaseMixin

local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors
local WHITE_TEXT_STYLE = { color = { 1, 1, 1, 1 } }
local BLACK_TEXT_STYLE = { color = { 0, 0, 0, 1 } }

local function GetSpellBookFrame(frame)
    return frame and (frame.SpellBookFrame or _G.SpellBookFrame)
end

local function StyleSpellBookAssistant(rotation)
    if not rotation or not rotation.Button or not rotation.Label then return end
    SkinBase.StripTextures(rotation)
    local button = rotation.Button
    SkinBase.ClampTextureHidden(button.Border, true, { preserveLayout = true })
    local border = SkinBase.SkinIcon(button.Icon, { parent = button })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
    SkinBase.RoundIconTexture(button, button.Icon)
    local label = rotation.Label
    local text = label:GetText()
    if text then label:SetText((text:gsub("|n", " "):gsub("[\r\n]+", " "))) end
    SkinBase.SkinFontString(label, { color = { 0.9, 0.9, 0.9, 1 } })
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    label:ClearAllPoints()
    label:SetPoint("RIGHT", button, "LEFT", -8, 0)
    label:SetWidth(0)
    local width = math.ceil(label:GetUnboundedStringWidth()) + 2
    label:SetWidth(width)
    rotation:SetWidth(width + button:GetWidth() + 21)
    if rotation.UpdateDisplay and not SkinBase.GetFrameData(rotation, "qAssistantDisplayHooked") then
        hooksecurefunc(rotation, "UpdateDisplay", StyleSpellBookAssistant)
        SkinBase.SetFrameData(rotation, "qAssistantDisplayHooked", true)
    end
end

local function StyleSpellBookControls(frame)
    local book = GetSpellBookFrame(frame)
    if not book then return end
    StyleSpellBookAssistant(book.AssistedCombatRotationSpellFrame)
    for _, key in ipairs({ "TopBar", "BookBGHalved", "BookBGLeft", "BookBGRight", "BookCornerFlipbook", "Bookmark" }) do
        if book[key] then SkinBase.ClampTextureHidden(book[key]) end
    end
    if book.SearchBox then SkinBase.SkinEditBox(book.SearchBox) end
    if book.SearchBox and book.SearchBox.searchIcon then book.SearchBox.searchIcon:SetAlpha(1) end
    local categories = book.CategoryTabSystem and book.CategoryTabSystem.tabs
    SkinBase.SkinTabGroup(categories, book, { resizeToText = true, hover = true })
end

local function SkinSpellRows(frame)
    if not frame or not IsSettingEnabled("skinSpellBook") then return end
    local spellBookFrame = GetSpellBookFrame(frame)
    local pagedSpellsFrame = spellBookFrame and spellBookFrame.PagedSpellsFrame
    if pagedSpellsFrame and pagedSpellsFrame.EnumerateFrames then
        for _, spellFrame in pagedSpellsFrame:EnumerateFrames() do
            SkinBase.SkinFrameText(spellFrame, { recurse = true, chrome = true })
            if spellFrame.Backplate then SkinBase.ClampTextureHidden(spellFrame.Backplate) end
            if not spellFrame.Button and spellFrame.Border then SkinBase.ClampTextureHidden(spellFrame.Border) end
            local button = spellFrame.Button
            if button and button.Icon then
                SkinBase.ClampTextureHidden(button.Border)
                SkinBase.ClampTextureHidden(button.BorderShadow)
                local border = SkinBase.SkinIcon(button.Icon, { parent = button })
                local passive = spellFrame.spellBookItemInfo and spellFrame.spellBookItemInfo.isPassive
                SkinBase.ApplyChromeBackdrop(border, { radius = passive and 20 or 4, withBackground = false })
                SkinBase.RoundIconTexture(button, button.Icon)
            end
        end
    end
end

local function SkinTalentSpendText(button)
    if not button then return end
    if type(button.ApplyVisualState) == "function"
        and not SkinBase.GetFrameData(button, "qTalentSpendTextHooked") then
        SkinBase.SetFrameData(button, "qTalentSpendTextHooked", true)
        hooksecurefunc(button, "ApplyVisualState", SkinTalentSpendText)
    end
    if button.SpendText then
        SkinBase.SkinFontString(button.SpendText, WHITE_TEXT_STYLE)
    end
    for _, shadow in ipairs(button.spendTextShadows or {}) do
        SkinBase.SkinFontString(shadow, BLACK_TEXT_STYLE)
    end
end

local function SkinTalentSpendTexts(frame)
    local talentsFrame = frame and frame.TalentsFrame
    if not talentsFrame or not talentsFrame.EnumerateAllTalentButtons then return end
    for button in talentsFrame:EnumerateAllTalentButtons() do
        SkinTalentSpendText(button)
    end
    local displayPool = talentsFrame.talentDisplayFramePool
    if displayPool and displayPool.EnumerateActive then
        for display in displayPool:EnumerateActive() do
            SkinTalentSpendText(display)
        end
    end
end

local function HookTalentSpendTextUpdates(frame)
    local talentsFrame = frame and frame.TalentsFrame
    if not talentsFrame or not talentsFrame.RegisterCallback
        or SkinBase.GetFrameData(talentsFrame, "qTalentSpendTextCallback") then return end
    local event = TalentFrameBaseMixin and TalentFrameBaseMixin.Event
        and TalentFrameBaseMixin.Event.TalentButtonAcquired
    if not event then return end
    talentsFrame:RegisterCallback(event, function(_, button)
        SkinTalentSpendText(button)
    end, frame)
    if type(talentsFrame.AcquireTalentDisplayFrame) == "function" then
        hooksecurefunc(talentsFrame, "AcquireTalentDisplayFrame", function(self)
            local displayPool = self.talentDisplayFramePool
            if not displayPool or not displayPool.EnumerateActive then return end
            for display in displayPool:EnumerateActive() do
                SkinTalentSpendText(display)
            end
        end)
    end
    SkinBase.SetFrameData(talentsFrame, "qTalentSpendTextCallback", true)
end

local function StyleSpecializationContent(content)
    if not content then return end
    for _, key in ipairs({ "HoverBackground", "SpecImageBorderOff", "HoverSpecImageBorder", "SpecImageBorderOn", "ActivatedSpecImageBorder", "Separator", "ColumnDivider" }) do
        SkinBase.ClampTextureHidden(content[key], true)
    end
    for _, key in ipairs({ "ActivatedBackFrames", "ActivatedLeftFrames", "ActivatedRightFrames" }) do
        for _, texture in ipairs(content[key] or {}) do SkinBase.ClampTextureHidden(texture, true) end
    end
    SkinBase.SkinButton(content.ActivateButton)
    if not SkinBase.GetBackdrop(content) then SkinBase.CreateBackdrop(content, nil, nil, nil, nil, nil, nil, nil, nil, 6) end
    SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(content), {
        radius = 6, withBackground = true,
        borderColor = content.isInGlowState and SkinBase.GetChromePalette().accent or nil,
    })
    SkinBase.RoundIconTexture(content, content.SpecImage)
    if not SkinBase.GetFrameData(content, "qSpecChromeHooked") then
        SkinBase.SetFrameData(content, "qSpecChromeHooked", true)
        if content.UpdateActiveGlow then hooksecurefunc(content, "UpdateActiveGlow", StyleSpecializationContent) end
    end
end

local function StylePlayerSpellsControls(frame)
    if not frame then return end
    local resize = frame.MaximizeMinimizeButton
    if resize then
        for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
            local button = resize[key]
            if button then
                SkinBase.SkinButton(button, { strip = true, font = false })
                SkinBase.ClampAllTextures(button)
                local text = SkinBase.GetFrameData(button, "qPlayerSpellsResizeGlyph")
                if not text then
                    text = button:CreateFontString(nil, "OVERLAY")
                    text:SetPoint("CENTER", button, "CENTER", 0, 0)
                    SkinBase.SetFrameData(button, "qPlayerSpellsResizeGlyph", text)
                end
                SkinBase.SkinFontString(text, { size = 16, color = { 1, 1, 1, 1 } })
                text:SetText(key == "MaximizeButton" and "+" or "-")
                if not SkinBase.GetFrameData(button, "qPlayerSpellsResizeClickHooked") then
                    SkinBase.SetFrameData(button, "qPlayerSpellsResizeClickHooked", true)
                    button:HookScript("OnClick", function()
                        StylePlayerSpellsControls(frame)
                        C_Timer.After(0, function() StylePlayerSpellsControls(frame) end)
                    end)
                end
            end
        end
    end
    if type(frame.UpdateSize) == "function" and not SkinBase.GetFrameData(frame, "qPlayerSpellsResizeHooked") then
        SkinBase.SetFrameData(frame, "qPlayerSpellsResizeHooked", true)
        hooksecurefunc(frame, "UpdateSize", function()
            C_Timer.After(0, function() StylePlayerSpellsControls(frame) end)
        end)
    end
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.SkinTabGroup(frame.TabSystem.tabs, frame, { dockBottom = true })
    end
    local talents = frame.TalentsFrame
    if talents then
        SkinBase.ClampTextureHidden(talents.BottomBar)
        SkinBase.SkinButton(talents.ApplyButton)
        SkinBase.SkinButton(talents.InspectCopyButton)
        SkinBase.SkinEditBox(talents.SearchBox)
        if talents.SearchBox and talents.SearchBox.searchIcon then talents.SearchBox.searchIcon:SetAlpha(1) end
        SkinBase.SkinDropdown(talents.LoadSystem and talents.LoadSystem.Dropdown, { skinArrow = true })
        if not SkinBase.GetFrameData(talents, "qTalentControlsHooked") then
            SkinBase.SetFrameData(talents, "qTalentControlsHooked", true)
            if talents.HookScript then talents:HookScript("OnShow", function() StylePlayerSpellsControls(frame) end) end
        end
    end
    local spec = frame.SpecFrame
    if spec then
        SkinBase.ClampTextureHidden(spec.Background)
        SkinBase.ClampTextureHidden(spec.BlackBG)
        if spec.SpecContentFramePool and spec.SpecContentFramePool.EnumerateActive then
            for content in spec.SpecContentFramePool:EnumerateActive() do StyleSpecializationContent(content) end
        end
        if not SkinBase.GetFrameData(spec, "qSpecControlsHooked") then
            SkinBase.SetFrameData(spec, "qSpecControlsHooked", true)
            if spec.HookScript then spec:HookScript("OnShow", function() StylePlayerSpellsControls(frame) end) end
            if spec.UpdateSpecFrame then hooksecurefunc(spec, "UpdateSpecFrame", function() StylePlayerSpellsControls(frame) end) end
        end
    end
end

local function SkinPlayerSpellsText(frame)
    if not frame or not IsSettingEnabled("skinSpellBook") then return end
    StylePlayerSpellsControls(frame)
    StyleSpellBookControls(frame)
    HookTalentSpendTextUpdates(frame)
    SkinBase.SkinFrameText(frame, { recurse = true, chrome = true })
    StyleSpellBookControls(frame)
    SkinSpellRows(frame)
    SkinTalentSpendTexts(frame)
end

local function SchedulePlayerSpellsText(frame)
    C_Timer.After(0, function()
        SkinSpellRows(frame)
    end)
end

local function HookPlayerSpellsTextUpdates(frame)
    local spellBookFrame = GetSpellBookFrame(frame)
    local pagedSpellsFrame = spellBookFrame and spellBookFrame.PagedSpellsFrame
    if not pagedSpellsFrame or not pagedSpellsFrame.RegisterCallback then return end
    if SkinBase.GetFrameData(pagedSpellsFrame, "qSpellBookTextHooked") then return end

    local event = PagedContentFrameBaseMixin
        and PagedContentFrameBaseMixin.Event
        and PagedContentFrameBaseMixin.Event.OnUpdate
    if not event then return end

    pagedSpellsFrame:RegisterCallback(event, function()
        SchedulePlayerSpellsText(frame)
    end, frame)
    SkinBase.SetFrameData(pagedSpellsFrame, "qSpellBookTextHooked", true)
end

local function SkinPlayerSpells()
    if not IsSettingEnabled("skinSpellBook") then return end
    local frame = _G.PlayerSpellsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.SkinTabGroup(frame.TabSystem.tabs, frame, { dockBottom = true })
    end
    local spellBookFrame = GetSpellBookFrame(frame)
    local categoryTabs = spellBookFrame and spellBookFrame.CategoryTabSystem
        and spellBookFrame.CategoryTabSystem.tabs
    if categoryTabs then
        for _, t in ipairs(categoryTabs) do
            SkinBase.ApplyButtonFontObjects(t)
        end
    end
    local pagedSpells = spellBookFrame and spellBookFrame.PagedSpellsFrame
    local paging = pagedSpells and pagedSpells.PagingControls
    if paging then
        if paging.PrevPageButton then SkinBase.SkinNextPrevButton(paging.PrevPageButton, "prev") end
        if paging.NextPageButton then SkinBase.SkinNextPrevButton(paging.NextPageButton, "next") end
    end
    local function DriveButtonFont(btn)
        if btn then SkinBase.ApplyButtonFontObjects(btn) end
    end
    local function FontSpecActivateButtons(specFrame)
        local pool = specFrame and specFrame.SpecContentFramePool
        if not pool or not pool.EnumerateActive then return end
        for contentFrame in pool:EnumerateActive() do
            DriveButtonFont(contentFrame.ActivateButton)
        end
    end
    if frame.SpecFrame then
        FontSpecActivateButtons(frame.SpecFrame)
        if not SkinBase.GetFrameData(frame.SpecFrame, "qSpecActivateHooked")
            and type(frame.SpecFrame.UpdateSpecFrame) == "function" then
            hooksecurefunc(frame.SpecFrame, "UpdateSpecFrame", function(self)
                FontSpecActivateButtons(self)
            end)
            SkinBase.SetFrameData(frame.SpecFrame, "qSpecActivateHooked", true)
        end
    end
    if frame.TalentsFrame then
        DriveButtonFont(frame.TalentsFrame.ApplyButton)
        DriveButtonFont(frame.TalentsFrame.InspectCopyButton)
    end
    HookPlayerSpellsTextUpdates(frame)
    SkinPlayerSpellsText(frame)
    SkinBase.MarkSkinned(frame)
end

local function RefreshPlayerSpells()
    local frame = _G.PlayerSpellsFrame
    if not frame or not IsSettingEnabled("skinSpellBook") then return end
    if not SkinBase.IsSkinned(frame) then
        SkinPlayerSpells()
        return
    end
    RefreshBackdropColors(frame)
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.RefreshTabGroup(frame.TabSystem.tabs, frame)
    end
    HookPlayerSpellsTextUpdates(frame)
    SkinPlayerSpellsText(frame)
end
_G.QUI_RefreshSpellBookColors = RefreshPlayerSpells
if ns.Registry then
    ns.Registry:Register("skinSpellBook", {
        refresh = RefreshPlayerSpells,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinEncounterJournalTextFrame(frame)
    if frame then
        SkinBase.SkinFrameText(frame, { recurse = true, chrome = true })
        if SkinBase.ApplyButtonFontObjectsDeep then
            SkinBase.ApplyButtonFontObjectsDeep(frame, 3)
        end
    end
end

local function GetEncounterJournalBottomTabs(frame)
    if not frame then return nil end
    local tabs = {}
    for _, key in ipairs({
        "JourneysTab",
        "MonthlyActivitiesTab",
        "suggestTab",
        "dungeonsTab",
        "raidsTab",
        "LootJournalTab",
        "TutorialsTab",
    }) do
        local tab = frame[key]
        if tab then
            tabs[#tabs + 1] = tab
        end
    end
    return tabs
end

local function SkinEncounterJournalBottomTabs(frame)
    local tabs = GetEncounterJournalBottomTabs(frame)
    if not tabs or #tabs == 0 then return end
    SkinBase.SkinTabGroup(tabs, frame, { resizeToText = true, hover = true, dockBottom = true })
end

local function SkinEncounterJournalTutorialsButton(frame)
    local tutorials = frame and frame.TutorialsFrame
    local contents = tutorials and tutorials.Contents
    local startButton = contents and contents.StartButton
    if not startButton then return end
    SkinBase.SkinButton(startButton)
    if contents.GetRegions then
        SkinBase.StripTextures(contents)
        SkinBase.CreateBackdrop(contents, nil, nil, nil, nil, nil, nil, nil, nil, 5)
        if contents.Header then
            contents.Header:ClearAllPoints()
            contents.Header:SetPoint("TOPLEFT", contents, "TOPLEFT", 40, -36)
            contents.Header:SetWidth(650)
        end
        if contents.Description then
            contents.Description:ClearAllPoints()
            contents.Description:SetPoint("TOPLEFT", contents.Header, "BOTTOMLEFT", 0, -28)
            contents.Description:SetWidth(650)
        end
        startButton:ClearAllPoints()
        startButton:SetPoint("BOTTOM", contents, "BOTTOM", 0, 48)
    end
end

local function ScheduleEncounterJournalTextFrame(frame)
    C_Timer.After(0, function()
        SkinEncounterJournalTextFrame(frame)
    end)
end

local function HookEncounterJournalObjectMethod(object, key, method, callback)
    if not object or SkinBase.GetFrameData(object, key) then return end
    if type(object[method]) ~= "function" then return end

    hooksecurefunc(object, method, callback)
    SkinBase.SetFrameData(object, key, true)
end

local function SkinMonthlyActivitiesActivityButton(button)
    HookEncounterJournalObjectMethod(button, "qMonthlyActivityButtonTextHooked", "UpdateButtonStateShared",
        function(activityButton)
            ScheduleEncounterJournalTextFrame(activityButton)
        end)
    HookEncounterJournalObjectMethod(button and button.TextContainer, "qMonthlyActivityTextContainerHooked",
        "UpdateTextColor", function(textContainer)
            ScheduleEncounterJournalTextFrame(textContainer)
        end)

    if button then
        SkinBase.SkinButton(button)
        SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(button), { radius = 5, withBackground = true })
        SkinBase.ClampTextureHidden(button.Ribbon, true)
        SkinBase.ClampTextureHidden(button.RibbonStacked, true)
    end
    SkinEncounterJournalTextFrame(button)
    SkinEncounterJournalTextFrame(button and button.TextContainer)
end

local function SkinMonthlyActivitiesFilterButton(button)
    HookEncounterJournalObjectMethod(button, "qMonthlyActivityFilterTextHooked", "UpdateStateInternal",
        function(filterButton, selected)
            SkinBase.SetFrameData(filterButton, "qMonthlyFilterSelected", selected)
            SkinMonthlyActivitiesFilterButton(filterButton)
            ScheduleEncounterJournalTextFrame(filterButton)
        end)

    if button and button.Texture then
        local selected = SkinBase.GetFrameData(button, "qMonthlyFilterSelected")
        if selected == nil then selected = button.Texture:GetAtlas() == "Options_List_Active" end
        SkinBase.ClampTextureHidden(button.Texture)
        SkinBase.SkinButton(button)
        SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(button), { radius = 3, withBackground = true })
        if selected then
            local r, g, b, a = SkinBase.GetSkinColors()
            SkinBase.SetBackdropColors(SkinBase.GetBackdrop(button), { r, g, b, a }, nil)
        end
    end
    SkinEncounterJournalTextFrame(button)
end

local function SkinMonthlyActivitiesRewardCurrency(frame)
    HookEncounterJournalObjectMethod(frame, "qMonthlyActivityRewardTextHooked", "SetThresholdInfo",
        function(rewardCurrency)
            ScheduleEncounterJournalTextFrame(rewardCurrency)
        end)

    SkinEncounterJournalTextFrame(frame)
end

local function SkinMonthlyActivitiesText(monthlyFrame)
    if not monthlyFrame then return end

    SkinEncounterJournalTextFrame(monthlyFrame)
    SkinEncounterJournalTextFrame(monthlyFrame.HeaderContainer)
    SkinEncounterJournalTextFrame(monthlyFrame.ThresholdContainer)
    SkinEncounterJournalTextFrame(monthlyFrame.BarComplete)
    SkinEncounterJournalTextFrame(monthlyFrame.FilterList)
    for _, key in ipairs({ "Bg", "DividerVertical", "ShadowLeft", "ShadowRight", "Divider" }) do
        SkinBase.ClampTextureHidden(monthlyFrame[key])
    end
    local theme = monthlyFrame.ThemeContainer
    if theme then
        for _, key in ipairs({ "Bottom", "Left", "Right", "FilterList" }) do
            SkinBase.ClampTextureHidden(theme[key])
        end
    end
    local filters = monthlyFrame.FilterList
    if filters then
        SkinBase.ClampTextureHidden(filters.Bg)
        SkinBase.CreateBackdrop(filters, nil, nil, nil, nil, nil, nil, nil, nil, 5)
        SkinBase.SkinTrimScrollBar(filters.ScrollBar)
    end
    SkinBase.SkinTrimScrollBar(monthlyFrame.ScrollBar)
    local threshold = monthlyFrame.ThresholdContainer
    if threshold then
        SkinBase.ClampTextureHidden(threshold.BarBackground)
        SkinBase.ClampTextureHidden(threshold.BarBorder)
        SkinBase.CreateBackdrop(threshold, nil, nil, nil, nil, nil, nil, nil, nil, 4)
        if threshold.ThresholdBar then
            SkinBase.RoundBarTexture(threshold.ThresholdBar, threshold.ThresholdBar:GetStatusBarTexture())
        end
    end

    if monthlyFrame.thresholdFrames then
        for _, thresholdFrame in ipairs(monthlyFrame.thresholdFrames) do
            SkinEncounterJournalTextFrame(thresholdFrame)
            SkinMonthlyActivitiesRewardCurrency(thresholdFrame and thresholdFrame.RewardCurrency)
        end
    end

    SkinBase.ForEachScrollBoxFrame(monthlyFrame.ScrollBox, SkinMonthlyActivitiesActivityButton)

    local filterScrollBox = monthlyFrame.FilterList and monthlyFrame.FilterList.ScrollBox
    SkinBase.ForEachScrollBoxFrame(filterScrollBox, SkinMonthlyActivitiesFilterButton)
end

local function SkinEncounterJournalAbilityHeader(header)
    if not header then return end
    SkinBase.ClampTextureHidden(header.descriptionBG, true)
    SkinBase.ClampTextureHidden(header.descriptionBGBottom, true)
    local button = header.button
    if not button then return end
    for _, state in pairs(button.textures or {}) do
        for _, textures in pairs(state) do
            for _, texture in ipairs(textures) do SkinBase.ClampTextureHidden(texture, true) end
        end
    end
    for _, region in ipairs({ button:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" and region ~= button.abilityIcon then
            SkinBase.ClampTextureHidden(region, true)
        end
    end
    local glow = button.GetName and button:GetName() and _G[button:GetName() .. "Glow"]
    if glow then SkinBase.StripTextures(glow) end
    SkinBase.SkinButton(button, { font = false })
    SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(button), { radius = 4, withBackground = true })
    SkinBase.RoundIconTexture(button, button.abilityIcon)
    SkinBase.SkinFontString(button.title, { color = { 1, 1, 1, 1 } })
    SkinBase.SkinFontString(button.expandedIcon, { color = { 1, 1, 1, 1 } })
end

local function SkinEncounterJournalEncounterText(frame)
    local encounter = frame and frame.encounter
    if not encounter then return end

    SkinEncounterJournalTextFrame(encounter.infoFrame)
    SkinEncounterJournalTextFrame(encounter.overviewFrame)

    local overviewFrame = encounter.overviewFrame
    if overviewFrame then SkinBase.ClampTextureHidden(overviewFrame.header, true) end
    if overviewFrame and overviewFrame.overviews then
        for _, overview in ipairs(overviewFrame.overviews) do
            SkinEncounterJournalTextFrame(overview)
            SkinEncounterJournalAbilityHeader(overview)
        end
    end

    if encounter.usedHeaders then
        for _, header in ipairs(encounter.usedHeaders) do
            SkinEncounterJournalTextFrame(header)
            SkinEncounterJournalAbilityHeader(header)
        end
    end

    if encounter.freeHeaders then
        for _, header in ipairs(encounter.freeHeaders) do
            SkinEncounterJournalTextFrame(header)
            SkinEncounterJournalAbilityHeader(header)
        end
    end
end

local function SkinEncounterJournalText(frame)
    if not frame or not IsSettingEnabled("skinEncounterJournal") then return end

    SkinEncounterJournalTextFrame(frame)
    SkinMonthlyActivitiesText(frame.MonthlyActivitiesFrame)
    SkinEncounterJournalEncounterText(frame)
end

local encounterTextPending
local function ScheduleEncounterJournalText(frame, focusFrame)
    if focusFrame then
        C_Timer.After(0, function()
            SkinEncounterJournalTextFrame(focusFrame)
            if focusFrame.GetParent then
                SkinEncounterJournalTextFrame(focusFrame:GetParent())
            end
        end)
        return
    end
    if encounterTextPending then return end
    encounterTextPending = true
    C_Timer.After(0, function()
        encounterTextPending = false
        if not IsSettingEnabled("skinEncounterJournal") then return end
        SkinEncounterJournalEncounterText(frame)
    end)
end

local function HookEncounterJournalFunction(name, callback)
    if _G[name] then
        hooksecurefunc(name, callback)
    end
end

local function HookEncounterJournalMixinMethod(mixin, method, callback)
    if mixin and type(mixin[method]) == "function" then
        hooksecurefunc(mixin, method, callback)
    end
end

local function HookEncounterJournalScrollBox(scrollBox, callback)
    if not scrollBox or not SkinBase.HookScrollBoxAcquired then return end
    callback = callback or SkinEncounterJournalTextFrame
    local callbacks = SkinBase.GetFrameData(scrollBox, "qJournalAcquiredCallbacks")
    if not callbacks then
        callbacks = {}
        SkinBase.SetFrameData(scrollBox, "qJournalAcquiredCallbacks", callbacks)
    end
    if not callbacks[callback] then
        SkinBase.HookScrollBoxAcquired(scrollBox, callback)
        callbacks[callback] = true
    elseif SkinBase.ForEachScrollBoxFrame then
        SkinBase.ForEachScrollBoxFrame(scrollBox, callback)
    end
end

local function HookMonthlyActivitiesScrollBoxes(monthlyFrame)
    if not monthlyFrame then return end
    HookEncounterJournalScrollBox(monthlyFrame.ScrollBox, SkinMonthlyActivitiesActivityButton)
    HookEncounterJournalScrollBox(monthlyFrame.FilterList and monthlyFrame.FilterList.ScrollBox,
        SkinMonthlyActivitiesFilterButton)
end

local function HookEncounterJournalScrollBoxes(frame)
    local encounter = frame and frame.encounter
    local info = encounter and encounter.info
    if info then
        HookEncounterJournalScrollBox(info.BossesScrollBox)
        HookEncounterJournalScrollBox(info.LootContainer and info.LootContainer.ScrollBox)
    end
    HookEncounterJournalScrollBox(frame and frame.searchResults and frame.searchResults.ScrollBox)
    HookEncounterJournalScrollBox(frame and frame.instanceSelect and frame.instanceSelect.ScrollBox)
    HookMonthlyActivitiesScrollBoxes(frame and frame.MonthlyActivitiesFrame)
end

local monthlyTextPending
local function ScheduleMonthlyActivitiesText(monthlyFrame, focusFrame)
    if focusFrame then
        C_Timer.After(0, function()
            SkinEncounterJournalTextFrame(focusFrame)
        end)
    end
    if monthlyTextPending then return end
    monthlyTextPending = true
    C_Timer.After(0, function()
        monthlyTextPending = false
        SkinMonthlyActivitiesText(monthlyFrame)
    end)
end

local function HookMonthlyActivitiesTextUpdates(frame)
    if not frame or SkinBase.GetFrameData(frame, "qMonthlyActivitiesTextHooked") then return end

    local monthlyFrame = frame.MonthlyActivitiesFrame
    HookEncounterJournalObjectMethod(monthlyFrame, "qMonthlyActivitiesOnShowTextHooked", "OnShow",
        function(activeMonthlyFrame)
            ScheduleMonthlyActivitiesText(activeMonthlyFrame)
        end)
    HookEncounterJournalObjectMethod(monthlyFrame, "qMonthlyActivitiesUpdateTextHooked", "UpdateActivities",
        function(activeMonthlyFrame)
            ScheduleMonthlyActivitiesText(activeMonthlyFrame)
        end)
    HookEncounterJournalObjectMethod(monthlyFrame, "qMonthlyActivitiesSetActivitiesTextHooked", "SetActivities",
        function(activeMonthlyFrame)
            ScheduleMonthlyActivitiesText(activeMonthlyFrame)
        end)
    HookEncounterJournalObjectMethod(monthlyFrame, "qMonthlyActivitiesSetThresholdsTextHooked", "SetThresholds",
        function(activeMonthlyFrame)
            ScheduleMonthlyActivitiesText(activeMonthlyFrame)
        end)
    HookEncounterJournalObjectMethod(monthlyFrame, "qMonthlyActivitiesRewardsTextHooked",
        "SetRewardsEarnedAndCollected", function(activeMonthlyFrame)
            ScheduleMonthlyActivitiesText(activeMonthlyFrame, activeMonthlyFrame and activeMonthlyFrame.BarComplete)
        end)
    HookEncounterJournalObjectMethod(monthlyFrame, "qMonthlyActivitiesTimeTextHooked", "UpdateTime",
        function(activeMonthlyFrame)
            ScheduleMonthlyActivitiesText(activeMonthlyFrame, activeMonthlyFrame and activeMonthlyFrame.HeaderContainer)
        end)

    HookEncounterJournalMixinMethod(MonthlyActivitiesFrameMixin, "OnShow", function(monthlyFrame)
        ScheduleMonthlyActivitiesText(monthlyFrame)
    end)
    HookEncounterJournalMixinMethod(MonthlyActivitiesFrameMixin, "UpdateActivities", function(monthlyFrame)
        ScheduleMonthlyActivitiesText(monthlyFrame)
    end)
    HookEncounterJournalMixinMethod(MonthlyActivitiesFrameMixin, "SetActivities", function(monthlyFrame)
        ScheduleMonthlyActivitiesText(monthlyFrame)
    end)
    HookEncounterJournalMixinMethod(MonthlyActivitiesFrameMixin, "SetThresholds", function(monthlyFrame)
        ScheduleMonthlyActivitiesText(monthlyFrame)
    end)
    HookEncounterJournalMixinMethod(MonthlyActivitiesFrameMixin, "SetRewardsEarnedAndCollected", function(monthlyFrame)
        ScheduleMonthlyActivitiesText(monthlyFrame, monthlyFrame and monthlyFrame.BarComplete)
    end)
    HookEncounterJournalMixinMethod(MonthlyActivitiesFrameMixin, "UpdateTime", function(monthlyFrame)
        ScheduleMonthlyActivitiesText(monthlyFrame, monthlyFrame and monthlyFrame.HeaderContainer)
    end)

    SkinBase.SetFrameData(frame, "qMonthlyActivitiesTextHooked", true)
end

local function HookEncounterJournalTextUpdates(frame)
    if not frame then return end
    HookMonthlyActivitiesTextUpdates(frame)
    if SkinBase.GetFrameData(frame, "qEncounterJournalTextHooked") then return end

    HookEncounterJournalFunction("EncounterJournal_ToggleHeaders", function()
        ScheduleEncounterJournalText(frame)
    end)
    HookEncounterJournalFunction("EncounterJournal_SetBullets", function()
        ScheduleEncounterJournalText(frame)
    end)
    HookEncounterJournalFunction("EncounterJournal_SetDescriptionWithBullets", function()
        ScheduleEncounterJournalText(frame)
    end)
    HookEncounterJournalFunction("EncounterJournal_UpdateButtonState", function(button)
        ScheduleEncounterJournalText(frame, button)
    end)
    HookEncounterJournalFunction("EJSuggestFrame_RefreshDisplay", function()
        ScheduleEncounterJournalTextFrame(frame.suggestFrame)
    end)

    SkinBase.SetFrameData(frame, "qEncounterJournalTextHooked", true)
end

local function SkinEncounterJournalCard(card)
    if not card then return end
    if card.NormalTexture then SkinBase.ClampTextureHidden(card.NormalTexture, true) end
    if card.PushedTexture then SkinBase.ClampTextureHidden(card.PushedTexture, true) end
    if card.CategoryDivider then SkinBase.ClampTextureHidden(card.CategoryDivider) end
    if card.RenownCardFactionName or card.JourneyCardName then
        SkinBase.SkinButton(card)
        SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(card), { radius = 6, withBackground = true })
    end
    SkinEncounterJournalTextFrame(card)
    local bar = card.JourneyCardProgressBar
    if bar then
        SkinBase.ClampTextureHidden(bar.JourneyCardProgressBarBG)
        SkinBase.ClampTextureHidden(bar.JourneyCardProgressBarFrame)
        SkinBase.CreateBackdrop(bar, nil, nil, nil, nil, nil, nil, nil, nil, 4)
        SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
    end
end

local function SkinEncounterJournalInstanceCard(card)
    if not card then return end
    if card.bgImage then
        if card.GetNormalTexture then SkinBase.ClampTextureHidden(card:GetNormalTexture()) end
        if card.GetPushedTexture then SkinBase.ClampTextureHidden(card:GetPushedTexture()) end
        if card.GetHighlightTexture then SkinBase.ClampTextureHidden(card:GetHighlightTexture()) end
        SkinBase.CreateBackdrop(card, nil, nil, nil, nil, nil, nil, nil, 0, 6)
        SkinBase.RoundIconTexture(card, card.bgImage)
    end
    SkinEncounterJournalTextFrame(card)
end

local function SkinEncounterJournalLootRow(row)
    if not row or not row.icon then return end
    SkinBase.ClampTextureHidden(row.bossTexture)
    SkinBase.ClampTextureHidden(row.bosslessTexture)
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("ROW")
    SkinBase.CreateBackdrop(row, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
    SkinBase.RoundIconTexture(row, row.icon)
    local iconFrame = SkinBase.GetFrameData(row, "qEncounterLootIconFrame")
    if not iconFrame then
        iconFrame = CreateFrame("Frame", nil, row)
        iconFrame:SetAllPoints(row.icon)
        SkinBase.CreateBackdrop(iconFrame, nil, nil, nil, nil, nil, nil, nil, 0, 4)
        SkinBase.SetFrameData(row, "qEncounterLootIconFrame", iconFrame)
    end
    if row.IconBorder then
        local qr, qg, qb = row.IconBorder:GetVertexColor()
        SkinBase.SetBackdropColors(SkinBase.GetBackdrop(iconFrame), { qr, qg, qb, 1 }, nil)
        SkinBase.ClampTextureHidden(row.IconBorder)
    end
    SkinEncounterJournalTextFrame(row)
    HookEncounterJournalObjectMethod(row, "qEncounterLootInitHooked", "Init", SkinEncounterJournalLootRow)
end

local function SkinEncounterJournalBossRow(button)
    SkinBase.SkinButton(button)
    SkinEncounterJournalTextFrame(button)
end

local function StyleJourneyProgress(page)
    if not page then return end
    SkinBase.SkinButton(page.LevelSkipButton)
    local companionFrame = page.DelvesCompanionConfigurationFrame or page.CompanionConfig
    local companion = companionFrame and companionFrame.CompanionConfigBtn
    if companion then
        SkinBase.SkinButton(companion)
        for _, texture in ipairs({ companion.NormalTexture, companion.PushedTexture, companion:GetHighlightTexture() }) do
            SkinBase.ClampTextureHidden(texture, true)
        end
        SkinBase.ClampTextureHidden(companion.IconBorder, true)
    end
    local details = page.ProgressDetailsFrame
    if details then
        SkinBase.ClampTextureHidden(details.JourneyLevelBar, true)
        SkinBase.ClampTextureHidden(details.JourneyLevelBg, true)
        SkinBase.CreateBackdrop(details, nil, nil, nil, nil, nil, nil, nil, nil, 4)
        SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(details), { radius = 4, withBackground = true })
        if details.JourneyLevel then
            details.JourneyLevel:ClearAllPoints()
            details.JourneyLevel:SetPoint("LEFT", details, "LEFT", 8, 0)
        end
    end
    local bar = page.DelveRewardProgressBar
    if bar then
        SkinBase.ClampTextureHidden(bar.DelveRewardProgressBarBG, true)
        SkinBase.ClampTextureHidden(bar.DelveRewardProgressBarFrame, true)
        SkinBase.CreateBackdrop(bar, nil, nil, nil, nil, nil, nil, nil, nil, 4)
        local backdrop = SkinBase.GetBackdrop(bar)
        SkinBase.ApplyChromeBackdrop(backdrop, { radius = 4, withBackground = true })
        local track = page.EncounterRewardProgressFrame
        if track and bar:GetTop() and track:GetTop() then
            local y = bar:GetTop() - track:GetTop()
            backdrop:ClearAllPoints()
            backdrop:SetPoint("TOPLEFT", track, "TOPLEFT", 0, y)
            backdrop:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, y)
            backdrop:SetHeight(bar:GetHeight())
        end
        SkinBase.RoundBarTexture(bar, bar:GetStatusBarTexture())
    end
    for _, key in ipairs({ "EncounterRewardProgressFrame", "RenownTrackFrame" }) do
        local track = page[key]
        if track then
            for _, pair in ipairs({ { "LeftButton", "prev" }, { "RightButton", "next" }, { "JumpLeftButton", "prev" }, { "JumpRightButton", "next" } }) do
                SkinBase.SkinNextPrevButton(track[pair[1]], pair[2])
            end
            local pool = track.elementPool
            if pool and pool.EnumerateActive then
                for card in pool:EnumerateActive() do
                    SkinBase.ClampTextureHidden(card.RewardCardBG, true)
                    SkinBase.ClampTextureHidden(card.LevelSquare, true)
                    SkinBase.CreateBackdrop(card, nil, nil, nil, nil, nil, nil, nil, nil, 5)
                    local backdrop = SkinBase.GetBackdrop(card)
                    SkinBase.ApplyChromeBackdrop(backdrop, { radius = 5, withBackground = true })
                    SkinBase.SetPixelInsetPoints(backdrop, card, 2, 2, 2, 2)
                    if key == "RenownTrackFrame" and card.Icon then
                        local atlas = card.IconBorder and card.IconBorder.GetAtlas and card.IconBorder:GetAtlas()
                        SkinBase.ClampTextureHidden(card.IconBorder, true)
                        SkinBase.ClampTextureHidden(card.LevelRectangle, true)
                        backdrop:ClearAllPoints()
                        backdrop:SetAllPoints(card.Icon)
                        SkinBase.ApplyChromeBackdrop(backdrop, {
                            radius = 4, withBackground = true,
                            borderColor = atlas and atlas:find("yellow", 1, true) and SkinBase.GetChromePalette().accent or nil,
                        })
                    end
                    SkinEncounterJournalTextFrame(card)
                end
            end
            if track.RefreshView and not SkinBase.GetFrameData(track, "qJourneyTrackHooked") then
                SkinBase.SetFrameData(track, "qJourneyTrackHooked", true)
                hooksecurefunc(track, "RefreshView", function() StyleJourneyProgress(page) end)
            end
        end
    end
    SkinBase.SkinButton(page.OverviewBtn, { strip = true })
    if page.rewardPool and page.rewardPool.EnumerateActive then
        for reward in page.rewardPool:EnumerateActive() do
            SkinBase.ClampTextureHidden(reward.RewardCardBG, true)
            SkinBase.ClampTextureHidden(reward.RewardCardIconBorderDefault, true)
            SkinBase.CreateBackdrop(reward, nil, nil, nil, nil, nil, nil, nil, nil, 5)
            local backdrop = SkinBase.GetBackdrop(reward)
            SkinBase.ApplyChromeBackdrop(backdrop, { radius = 5, withBackground = true })
            SkinBase.SetPixelInsetPoints(backdrop, reward, 4, 4, 4, 4)
            SkinEncounterJournalTextFrame(reward)
        end
    end
    local highlights = page.Highlights
    if highlights and highlights.highlightPool and highlights.highlightPool.EnumerateActive then
        for card in highlights.highlightPool:EnumerateActive() do
            SkinBase.ClampTextureHidden(card.Background, true)
            SkinBase.CreateBackdrop(card, nil, nil, nil, nil, nil, nil, nil, nil, 5)
            local backdrop = SkinBase.GetBackdrop(card)
            SkinBase.ApplyChromeBackdrop(backdrop, { radius = 5, withBackground = true })
            SkinBase.SetPixelInsetPoints(backdrop, card, 4, 4, 4, 4)
            SkinEncounterJournalTextFrame(card)
        end
        if highlights.DisplayHighlights and not SkinBase.GetFrameData(highlights, "qJourneyHighlightsHooked") then
            SkinBase.SetFrameData(highlights, "qJourneyHighlightsHooked", true)
            hooksecurefunc(highlights, "DisplayHighlights", function() StyleJourneyProgress(page) end)
        end
    end
    if not SkinBase.GetFrameData(page, "qJourneyProgressHooked") then
        SkinBase.SetFrameData(page, "qJourneyProgressHooked", true)
        page:HookScript("OnShow", function() StyleJourneyProgress(page) end)
        if page.Refresh then hooksecurefunc(page, "Refresh", StyleJourneyProgress) end
        if page.OnTrackUpdate then hooksecurefunc(page, "OnTrackUpdate", StyleJourneyProgress) end
        if page.SetRewards then hooksecurefunc(page, "SetRewards", StyleJourneyProgress) end
    end
end

local function SkinEncounterJournalContents(frame)
    if not frame or not IsSettingEnabled("skinEncounterJournal") then return end
    local select = frame.instanceSelect
    if select then
        SkinBase.ClampTextureHidden(select.bg)
        SkinBase.ClampTextureHidden(select.evergreenBg)
        if select.ExpansionDropdown then SkinBase.SkinDropdown(select.ExpansionDropdown, { skinArrow = true }) end
        local vault = select.GreatVaultButton
        if vault then
            SkinBase.SkinButton(vault, { font = false })
            for _, texture in ipairs({ vault.NormalTexture, vault.PushedTexture, vault:GetHighlightTexture() }) do
                SkinBase.ClampTextureHidden(texture, true)
            end
            vault:SetSize(26, 26)
            if select.ExpansionDropdown then
                vault:ClearAllPoints()
                vault:SetPoint("LEFT", select.ExpansionDropdown, "RIGHT", 6, 0)
            end
            local text = SkinBase.GetFrameData(vault, "qVaultShortcutText")
            if not text then
                text = vault:CreateFontString(nil, "OVERLAY")
                text:SetPoint("CENTER", vault, "CENTER", 0, 0)
                SkinBase.SetFrameData(vault, "qVaultShortcutText", text)
            end
            SkinBase.SkinFontString(text, { size = 14, color = { 0.9, 0.9, 0.9, 1 } })
            text:SetText("V")
        end
        SkinBase.SkinTrimScrollBar(select.ScrollBar)
        if select.ScrollBox then HookEncounterJournalScrollBox(select.ScrollBox, SkinEncounterJournalInstanceCard) end
    end
    if frame.inset then
        SkinBase.StripTextures(frame.inset)
        SkinBase.KillNineSlice(frame.inset.NineSlice)
        SkinBase.CreateBackdrop(frame.inset, nil, nil, nil, nil, nil, nil, nil, nil, 5)
    end
    local nav = frame.navBar
    if nav then
        SkinBase.StripTextures(nav)
        for _, key in ipairs({ "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight" }) do
            SkinBase.ClampTextureHidden(nav[key])
        end
        if nav.overlay then SkinBase.StripTextures(nav.overlay) end
        for _, button in ipairs(nav.navList or {}) do
            SkinBase.SkinButton(button)
            SkinBase.ClampTextureHidden(button.arrowUp)
            SkinBase.ClampTextureHidden(button.arrowDown)
            SkinBase.ClampTextureHidden(button.selected)
            if button.MenuArrowButton then
                SkinBase.SkinDropdown(button.MenuArrowButton, { skinArrow = true, font = false })
                SkinBase.ClampTextureHidden(button.MenuArrowButton.Art)
                local bg = SkinBase.GetBackdrop(button.MenuArrowButton)
                if bg then bg:Hide() end
            end
        end
        if nav.overflowButton then SkinBase.SkinButton(nav.overflowButton) end
    end
    local journeys = frame.JourneysFrame
    if journeys then
        if journeys.BorderFrame then
            SkinBase.StripTextures(journeys.BorderFrame)
            SkinBase.KillNineSlice(journeys.BorderFrame.NineSlice)
        end
        SkinBase.SkinTrimScrollBar(journeys.ScrollBar)
        if journeys.JourneysList then
            HookEncounterJournalScrollBox(journeys.JourneysList, SkinEncounterJournalCard)
        end
        for _, key in ipairs({ "JourneyProgress", "JourneyOverview" }) do
            local page = journeys[key]
            if page then
                StyleJourneyProgress(page)
                SkinBase.ClampTextureHidden(page.DividerTexture)
                SkinBase.ClampTextureHidden(page.DividerGlowTexture)
                if page.OverviewBtn then SkinBase.SkinButton(page.OverviewBtn) end
                local companion = page.CompanionConfig and page.CompanionConfig.CompanionConfigBtn
                if companion then
                    SkinBase.SkinButton(companion)
                    SkinBase.ClampTextureHidden(companion.IconBorder)
                end
                SkinEncounterJournalTextFrame(page)
            end
        end
        if type(journeys.Refresh) == "function" and not SkinBase.GetFrameData(journeys, "qJourneysChromeHooked") then
            SkinBase.SetFrameData(journeys, "qJourneysChromeHooked", true)
            hooksecurefunc(journeys, "Refresh", function() SkinEncounterJournalContents(frame) end)
            hooksecurefunc(journeys, "ResetView", function() SkinEncounterJournalContents(frame) end)
        end
    end
    local encounter = frame.encounter
    local info = encounter and encounter.info
    if info then
        for _, region in ipairs({ info:GetRegions() }) do
            if region ~= info.difficultyIcon and region.IsObjectType and region:IsObjectType("Texture") then
                SkinBase.ClampTextureHidden(region)
            end
        end
        SkinBase.CreateBackdrop(info, nil, nil, nil, nil, nil, nil, nil, nil, 5)
        if info.BossesScrollBox then
            HookEncounterJournalScrollBox(info.BossesScrollBox, SkinEncounterJournalBossRow)
        end
        local model = info.model
        if model then
            for _, region in ipairs({ model:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") then
                    SkinBase.ClampTextureHidden(region, true)
                end
            end
            SkinBase.CreateBackdrop(model, nil, nil, nil, nil, nil, nil, nil, nil, 6)
            local backdrop = SkinBase.GetBackdrop(model)
            backdrop:SetFrameLevel(math.max(0, model:GetFrameLevel() - 1))
            SkinBase.SkinFontString(model.imageTitle, { color = { 1, 1, 1, 1 } })
        end
        for _, button in ipairs(info.creatureButtons or {}) do
            SkinBase.SkinButton(button, { font = false })
            button:SetSize(50, 49)
            if button.creature then button.creature:SetSize(36, 36) end
            local backdrop = SkinBase.GetBackdrop(button)
            backdrop:ClearAllPoints()
            backdrop:SetSize(44, 44)
            backdrop:SetPoint("CENTER", button, "CENTER")
            local selected = info.shownCreatureButton
            local isSelected = selected and selected.displayInfo == button.displayInfo
            SkinBase.SetButtonSelected(button, isSelected)
            local r, g, b, a = SkinBase.GetWindowColors()
            if isSelected then r, g, b, a = SkinBase.GetSkinColors() end
            SkinBase.SetFrameData(button, "windowColor", { r, g, b, a })
            backdrop:SetBackdropBorderColor(r, g, b, a)
        end
        for _, key in ipairs({ "overviewTab", "lootTab", "bossTab", "modelTab" }) do
            local tab = info[key]
            if tab then
                SkinBase.SkinButton(tab, { font = false })
                local line = SkinBase.GetFrameData(tab, "qEncounterSelectedLine")
                if not line then
                    line = tab:CreateTexture(nil, "OVERLAY")
                    line:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -1, -5)
                    line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 5)
                    line:SetWidth(SkinBase.GetPixelSize(tab, 1))
                    SkinBase.SetFrameData(tab, "qEncounterSelectedLine", line)
                end
                local r, g, b = SkinBase.GetSkinColors()
                line:SetColorTexture(r, g, b, 1)
                line:SetShown(tab.selected and tab.selected:IsShown() or false)
            end
        end
        if info.instanceButton then
            SkinBase.SkinButton(info.instanceButton, { font = false })
        end
        for _, key in ipairs({ "difficulty" }) do
            if info[key] then SkinBase.SkinDropdown(info[key], { skinArrow = true }) end
        end
        local loot = info.LootContainer
        if loot then
            HookEncounterJournalScrollBox(loot.ScrollBox, SkinEncounterJournalLootRow)
            local clear = loot.classClearFilter
            if clear then
                SkinBase.StripTextures(clear)
                clear:ClearAllPoints()
                clear:SetPoint("BOTTOMLEFT", loot, "TOPLEFT", 0, -23)
                clear:SetPoint("BOTTOMRIGHT", loot, "TOPRIGHT", -20, -23)
                clear:SetHeight(20)
                if clear:IsShown() and loot.ScrollBox then
                    loot.ScrollBox:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -4)
                end
                SkinBase.CreateBackdrop(clear, nil, nil, nil, nil, nil, nil, nil, nil, 4)
                SkinBase.SkinFontString(clear.text)
                for _, child in ipairs({ clear:GetChildren() }) do
                    if child.IsObjectType and child:IsObjectType("Button") then SkinBase.SkinCloseButton(child) end
                end
            end
            for _, key in ipairs({ "filter", "slotFilter" }) do
                if loot[key] then SkinBase.SkinDropdown(loot[key], { skinArrow = true }) end
            end
            if loot.filter and loot.slotFilter and info.difficulty then
                loot.slotFilter:ClearAllPoints()
                loot.slotFilter:SetPoint("TOPRIGHT", info.difficulty, "TOPLEFT", -8, 0)
                loot.filter:ClearAllPoints()
                loot.filter:SetPoint("TOPRIGHT", loot.slotFilter, "TOPLEFT", -8, 0)
                loot.filter:SetWidth(160)
            end
            SkinBase.SkinTrimScrollBar(loot.ScrollBar)
        end
        SkinBase.SkinTrimScrollBar(info.BossesScrollBar)
        for _, key in ipairs({ "detailsScroll", "overviewScroll" }) do
            local scroll = info[key]
            if scroll then SkinBase.SkinTrimScrollBar(scroll.ScrollBar) end
        end
    end
    local overview = encounter and encounter.instance
    if overview then
        local art = overview.loreBG
        if art then
            art:SetTexCoord(0.0495117, 0.7160156, 0.0721875, 0.585)
            art:SetSize(350, 300)
            local panel = SkinBase.GetFrameData(overview, "qEncounterLorePanel")
            if not panel then
                panel = CreateFrame("Frame", nil, overview)
                panel:SetAllPoints(art)
                SkinBase.SetFrameData(overview, "qEncounterLorePanel", panel)
            end
            SkinBase.CreateBackdrop(panel, nil, nil, nil, nil, nil, nil, nil, nil, 6)
            SkinBase.ApplyChromeBackdrop(SkinBase.GetBackdrop(panel), { radius = 6, withBackground = false })
            SkinBase.RoundIconTexture(overview, art)
        end
        SkinBase.ClampTextureHidden(overview.titleBG)
        local mapButton = overview.mapButton
        if mapButton then
            SkinBase.StripTextures(mapButton)
            SkinBase.SkinButton(mapButton)
            mapButton:SetSize(108, 28)
            local text = SkinBase.GetFrameData(mapButton, "qEncounterMapText")
            if not text then
                for _, region in ipairs({ mapButton:GetRegions() }) do
                    if region.GetObjectType and region:GetObjectType() == "FontString" then text = region; break end
                end
                text = text or mapButton:CreateFontString(nil, "OVERLAY")
                text:ClearAllPoints()
                text:SetPoint("CENTER", mapButton, "CENTER", 0, 0)
                text:SetWidth(96)
                text:SetWordWrap(false)
                SkinBase.SkinFontString(text)
                text:SetText((_G.ENCOUNTER_JOURNAL_SHOW_MAP or "Show Map"):gsub("%s+", " "))
                SkinBase.SetFrameData(mapButton, "qEncounterMapText", text)
            end
            SkinBase.SkinFontString(text)
        end
        SkinBase.SkinTrimScrollBar(overview.LoreScrollBar)
    end
    if frame.searchBox then
        SkinBase.SkinEditBox(frame.searchBox)
        if frame.searchBox.searchIcon then frame.searchBox.searchIcon:SetAlpha(1) end
    end
    local suggested = frame.suggestFrame
    if suggested then
        for _, key in ipairs({ "Suggestion1", "Suggestion2", "Suggestion3" }) do
            local card = suggested[key]
            if card then
                SkinBase.ClampTextureHidden(card.bg)
                SkinBase.ClampTextureHidden(card.iconRing)
                SkinBase.CreateBackdrop(card, nil, nil, nil, nil, nil, nil, nil, nil, 6)
                SkinBase.SkinButton(card.button)
                if card.centerDisplay then SkinBase.SkinButton(card.centerDisplay.button) end
                for _, control in ipairs({ "prevButton", "nextButton" }) do
                    local button = card[control]
                    if button then
                        SkinBase.SkinButton(button)
                        button:SetText(control == "prevButton" and "‹" or "›")
                    end
                end
                local reward = card.reward
                if reward then
                    SkinBase.ClampTextureHidden(reward.iconRing)
                    SkinBase.ClampTextureHidden(reward.iconRingHighlight)
                end
                SkinEncounterJournalTextFrame(card)
            end
        end
    end
    SkinEncounterJournalBottomTabs(frame)
end

local function SkinEncounterJournal()
    if not IsSettingEnabled("skinEncounterJournal") then return end
    local frame = _G.EncounterJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    SkinEncounterJournalContents(frame)
    for _, name in ipairs({ "EncounterJournal_SetTab", "EncounterJournal_DisplayInstance", "EncounterJournal_DisplayEncounter", "EJ_ContentTab_Select", "EJSuggestFrame_RefreshDisplay", "EncounterJournal_LootUpdate", "EncounterJournal_DisplayCreature" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function() SkinEncounterJournalContents(frame) end)
        end
    end
    if frame.HookScript then frame:HookScript("OnShow", function() SkinEncounterJournalContents(frame) end) end
    SkinEncounterJournalBottomTabs(frame)
    SkinEncounterJournalTutorialsButton(frame)
    HookEncounterJournalTextUpdates(frame)
    HookEncounterJournalScrollBoxes(frame)
    SkinEncounterJournalText(frame)
    SkinBase.MarkSkinned(frame)
end

local function RefreshEncounterJournal()
    local frame = _G.EncounterJournal
    if not frame or not IsSettingEnabled("skinEncounterJournal") then return end
    RefreshBackdropColors(frame)
    if not SkinBase.IsSkinned(frame) then
        SkinEncounterJournal()
        return
    end
    HookEncounterJournalTextUpdates(frame)
    HookEncounterJournalScrollBoxes(frame)
    SkinEncounterJournalContents(frame)
    SkinEncounterJournalTutorialsButton(frame)
    SkinEncounterJournalText(frame)
end
_G.QUI_RefreshEncounterJournalColors = RefreshEncounterJournal
if ns.Registry then
    ns.Registry:Register("skinEncounterJournal", {
        refresh = RefreshEncounterJournal,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function LockCollectionsScrollBox(scrollBox)
    if not scrollBox then return end
    SkinBase.HookScrollBoxRowFonts(scrollBox, 3)
end

local function HookCollectionsText(frame)
    if SkinBase.ApplyButtonFontObjectsDeep then
        SkinBase.ApplyButtonFontObjectsDeep(frame, 5)
    end
    LockCollectionsScrollBox(_G.MountJournal and _G.MountJournal.ScrollBox)
    LockCollectionsScrollBox(_G.PetJournal and _G.PetJournal.ScrollBox)

    local wardrobe = _G.WardrobeCollectionFrame
    local sets = wardrobe and wardrobe.SetsCollectionFrame
    local list = sets and sets.ListContainer
    LockCollectionsScrollBox(list and list.ScrollBox)
end

local function StyleCollectionNeutralLabel(label, shade)
    if not label or not label.SetTextColor then return end
    SkinBase.SetFrameData(label, "qCollectionLabelShade", shade or 0.9)
    SkinBase.SkinFontString(label, { color = { shade or 0.9, shade or 0.9, shade or 0.9, 1 } })
    if not SkinBase.GetFrameData(label, "qCollectionLabelColorHooked") then
        SkinBase.SetFrameData(label, "qCollectionLabelColorHooked", true)
        hooksecurefunc(label, "SetTextColor", function(self, r, g, b, a)
            if not IsSettingEnabled("skinCollections") then return end
            local v = SkinBase.GetFrameData(self, "qCollectionLabelShade")
            if r ~= v or g ~= v or b ~= v or (a and a ~= 1) then self:SetTextColor(v, v, v, 1) end
        end)
    end
end

local function StyleCollectionIconAction(button)
    if not button then return end
    SkinBase.ClampTextureHidden(button.Border, true)
    local icon = button.Icon
    if not icon then
        for _, region in ipairs({ button:GetRegions() }) do
            if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "ARTWORK" then
                icon = region
                break
            end
        end
    end
    local border = SkinBase.SkinIcon(icon, { parent = button })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
    SkinBase.RoundIconTexture(button, icon)
end

local function StyleMountEquipment(button)
    if not button then return end
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetAtlas() == "mountequipment-slot-background" then
            SkinBase.ClampTextureHidden(region, true)
        end
    end
    for _, key in ipairs({ "ItemBorder", "SlotBorder", "SlotBorderOpen" }) do
        SkinBase.ClampTextureHidden(button[key], true)
    end
    SkinBase.ApplyChromeBackdrop(button, { radius = 5, withBackground = true, belowChildren = true })
    SkinBase.RoundIconTexture(button, button.ItemIcon)
    if button.Initialize and not SkinBase.GetFrameData(button, "qEquipmentStyleHooked") then
        SkinBase.SetFrameData(button, "qEquipmentStyleHooked", true)
        hooksecurefunc(button, "Initialize", StyleMountEquipment)
    end
end

local function StyleCollectionSurface(frame)
    if not frame then return end
    SkinBase.StripTextures(frame)
    SkinBase.KillNineSlice(frame.NineSlice, true)
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
end

local function StyleCollectionPaging(paging)
    if not paging then return end
    SkinBase.SkinNextPrevButton(paging.PrevPageButton, "prev")
    SkinBase.SkinNextPrevButton(paging.NextPageButton, "next")
    SkinBase.SkinFrameText(paging, { recurse = true, chrome = true })
end

local function StyleCollectionPage(page)
    if not page then return end
    for _, key in ipairs({ "LeftInset", "BottomLeftInset", "RightInset", "MountCount", "iconsFrame", "IconsFrame" }) do
        StyleCollectionSurface(page[key])
    end
    for _, key in ipairs({ "ClassDropdown", "WeaponDropdown", "VariantSetsDropdown" }) do
        SkinBase.SkinDropdown(page[key], { skinArrow = true })
        SkinBase.RefreshWidget(page[key])
    end
    if page.ScrollBar then SkinBase.SkinTrimScrollBar(page.ScrollBar) end
    StyleCollectionPaging(page.PagingFrame)
    StyleCollectionNeutralLabel(page.MountCount and page.MountCount.Label)
    StyleCollectionNeutralLabel(page.PetCount and page.PetCount.Label)
    local progress = page.progressBar
    if progress then
        SkinBase.ClampTextureHidden(progress.border)
        SkinBase.SkinStatusBar(progress)
        SkinBase.ApplyChromeBackdrop(progress, { radius = 4, withBackground = true })
        SkinBase.SkinFontString(progress.text, { fontOnly = true })
    end
end

local function StyleCollectionListRow(row)
    if not row then return end
    SkinBase.ClampTextureHidden(row.background)
    SkinBase.ClampTextureHidden(row.selectedTexture, true)
    SkinBase.ClampTextureHidden(row.Background)
    SkinBase.ClampTextureHidden(row.SelectedTexture, true)
    SkinBase.ClampTextureHidden(row.HighlightTexture)
    SkinBase.ClampTextureHidden(row.GetHighlightTexture and row:GetHighlightTexture())
    local selected = row.selected or (row.selectedTexture and row.selectedTexture:IsShown()) or SkinBase.GetFrameData(row, "qCollectionSelected") or (row.GetChecked and row:GetChecked())
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("ROW")
    SkinBase.CreateBackdrop(row, sr, sg, sb, selected and sa or sa * 0.4, r, g, b, a, 4)
    SkinBase.SkinFontString(row.name, { color = { 1, 1, 1, 1 } })
    SkinBase.SkinFontString(row.subName, { fontOnly = true })
    SkinBase.SkinFontString(row.Name, { fontOnly = true })
    SkinBase.SkinFontString(row.Label, { color = { 0.75, 0.75, 0.75, 1 } })
    SkinBase.RoundIconTexture(row, row.icon)
end

local function StylePetCollection(page)
    if not page then return end
    StyleCollectionSurface(page.PetCardInset)
    StyleCollectionSurface(page.PetCount)
    if page.loadoutBorder then SkinBase.StripTextures(page.loadoutBorder) end
    local card = page.PetCard
    if card then
        SkinBase.ClampTextureHidden(_G.PetJournalPetCardBG)
        for _, key in ipairs({ "AbilitiesBG1", "AbilitiesBG2", "AbilitiesBG3", "shadows" }) do
            SkinBase.ClampTextureHidden(card[key])
        end
        for i = 1, 6 do
            local spell = card["spell" .. i]
            if spell then
                local normal = spell.GetNormalTexture and spell:GetNormalTexture()
                SkinBase.ClampTextureHidden(normal)
                SkinBase.SkinIcon(spell.icon, { parent = spell })
                SkinBase.RoundIconTexture(spell, spell.icon)
            end
        end
        SkinBase.SkinFrameText(card, { recurse = true, chrome = true })
    end
    for i = 1, 3 do
        local slot = page.Loadout and page.Loadout["Pet" .. i]
        if slot then
            SkinBase.ClampTextureHidden(_G["PetJournalLoadoutPet" .. i .. "BG"])
            SkinBase.ClampTextureHidden(slot.shadows)
            local sr, sg, sb, sa = SkinBase.GetWindowColors()
            local r, g, b, a = SkinBase.GetDepthColor("ROW")
            SkinBase.CreateBackdrop(slot, sr, sg, sb, sa * 0.4, r, g, b, a, 5)
            SkinBase.SkinFrameText(slot, { recurse = true, chrome = true })
        end
    end
    HookEncounterJournalScrollBox(page.ScrollBox, StyleCollectionListRow)
end

local function StyleWardrobeModels(items)
    if not items then return end
    for _, model in ipairs(items.Models or {}) do
        SkinBase.ClampTextureHidden(model.Border)
        local info = model.visualInfo
        local sr, sg, sb, sa = SkinBase.GetWindowColors()
        if info and info.isCollected and not info.isUsable then sr, sg, sb = 0.8, 0.2, 0.2 end
        for _, region in ipairs({ model:GetRegions() }) do
            if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
                SkinBase.ClampTextureHidden(region, true)
            end
        end
        local r, g, b, a = SkinBase.GetDepthColor("ROW")
        SkinBase.CreateBackdrop(model, sr, sg, sb, sa, r, g, b, a, 5)
        local backdrop = SkinBase.GetBackdrop(model)
        backdrop:SetFrameLevel(math.max(0, model:GetFrameLevel() - 1))
        SkinBase.ApplyChromeBackdrop(backdrop, { radius = 5, withBackground = true,
            bgColor = { r, g, b, a },
            borderColor = { sr, sg, sb, info and not info.isCollected and sa * 0.4 or sa } })
    end
end

local function StyleCollectionSpellButton(button)
    if not button then return end
    local dim = button.iconTextureUncollected and button.iconTextureUncollected:IsShown()
    local v = dim and 0.7 or 1
    StyleCollectionNeutralLabel(button.name, v)
    SkinBase.SkinFontString(button.special, { color = { 0.75, 0.75, 0.75, 1 } })
    SkinBase.ClampTextureHidden(button.slotFrameCollected)
    SkinBase.ClampTextureHidden(button.slotFrameUncollected)
    SkinBase.ClampTextureHidden(button.slotFrameUncollectedInnerGlow)
    local border = SkinBase.SkinIcon(button.iconTexture, { parent = button })
    SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
    SkinBase.RoundIconTexture(button, button.iconTexture)
    SkinBase.RoundIconTexture(button, button.iconTextureUncollected)
end

local function StyleToyAndHeirloomEntries()
    local toys = _G.ToyBox
    for i = 1, 18 do
        StyleCollectionSpellButton(toys and toys.iconsFrame and toys.iconsFrame["spellButton" .. i])
    end
    local heirlooms = _G.HeirloomsJournal
    for _, button in ipairs(heirlooms and heirlooms.heirloomEntryFrames or {}) do
        StyleCollectionSpellButton(button)
    end
    for _, header in ipairs(heirlooms and heirlooms.heirloomHeaderFrames or {}) do
        SkinBase.StripTextures(header)
        SkinBase.SkinFontString(header.text, { color = { 1, 1, 1, 1 } })
    end
end

local function StyleCampsiteEntry(entry)
    if not entry or not IsSettingEnabled("skinCollections") then return end
    SkinBase.ClampTextureHidden(entry.Border)
    SkinBase.ClampTextureHidden(entry.HighlightTexture)
    local border = SkinBase.SkinIcon(entry.Icon, { parent = entry, crop = false })
    SkinBase.ApplyChromeBackdrop(border, { radius = 5, withBackground = false })
    SkinBase.RoundIconTexture(entry, entry.Icon)
    SkinBase.SkinFontString(entry.Name, { color = { 1, 1, 1, 1 } })
end

local function StyleCollectionsTitle(frame)
    if not frame then return end
    local title = frame.GetTitleText and frame:GetTitleText()
        or frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if not title then return end
    SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } })
    if not SkinBase.GetFrameData(title, "qCollectionTitleColorHooked") then
        SkinBase.SetFrameData(title, "qCollectionTitleColorHooked", true)
        hooksecurefunc(title, "SetTextColor", function(self, r, g, b, a)
            if r ~= 1 or g ~= 1 or b ~= 1 or (a and a ~= 1) then self:SetTextColor(1, 1, 1, 1) end
        end)
    end
end

local function HookCollectionUpdates()
    local frame = _G.CollectionsJournal
    if frame and frame.SetTitle and not SkinBase.GetFrameData(frame, "qCollectionTitleHooked") then
        SkinBase.SetFrameData(frame, "qCollectionTitleHooked", true)
        hooksecurefunc(frame, "SetTitle", function(self)
            StyleCollectionsTitle(self)
        end)
    end
    if _G.MountJournal_InitMountButton and frame and not SkinBase.GetFrameData(frame, "qMountInitHooked") then
        SkinBase.SetFrameData(frame, "qMountInitHooked", true)
        hooksecurefunc("MountJournal_InitMountButton", StyleCollectionListRow)
    end

    for _, name in ipairs({ "PetJournal_UpdatePetList", "MountJournal_UpdateMountList" }) do
        local fn = _G[name]
        if fn and not SkinBase.GetFrameData(_G.CollectionsJournal, name) then
            hooksecurefunc(name, function()
                if not IsSettingEnabled("skinCollections") then return end
                local page = name == "PetJournal_UpdatePetList" and _G.PetJournal or _G.MountJournal
                SkinBase.ForEachScrollBoxFrame(page and page.ScrollBox, StyleCollectionListRow)
            end)
            SkinBase.SetFrameData(_G.CollectionsJournal, name, true)
        end
    end
    if _G.ToyBox_UpdateButtons and not SkinBase.GetFrameData(_G.CollectionsJournal, "qToyEntriesHooked") then
        hooksecurefunc("ToyBox_UpdateButtons", StyleToyAndHeirloomEntries)
        SkinBase.SetFrameData(_G.CollectionsJournal, "qToyEntriesHooked", true)
    end
    if _G.ToySpellButton_UpdateButton and not SkinBase.GetFrameData(_G.CollectionsJournal, "qToyButtonHooked") then
        hooksecurefunc("ToySpellButton_UpdateButton", function(button)
            if IsSettingEnabled("skinCollections") then StyleCollectionSpellButton(button) end
        end)
        SkinBase.SetFrameData(_G.CollectionsJournal, "qToyButtonHooked", true)
    end
    local scenesMixin = _G.WarbandSceneEntryMixin
    if scenesMixin and scenesMixin.UpdateWarbandSceneData and not SkinBase.GetFrameData(scenesMixin, "qCollectionStyleHooked") then
        hooksecurefunc(scenesMixin, "UpdateWarbandSceneData", StyleCampsiteEntry)
        SkinBase.SetFrameData(scenesMixin, "qCollectionStyleHooked", true)
    end
    local heirloomsMixin = _G.HeirloomsJournal or _G.HeirloomsMixin
    if heirloomsMixin and heirloomsMixin.RefreshView and not SkinBase.GetFrameData(heirloomsMixin, "qCollectionStyleHooked") then
        hooksecurefunc(heirloomsMixin, "RefreshView", StyleToyAndHeirloomEntries)
        if heirloomsMixin.UpdateButton then
            hooksecurefunc(heirloomsMixin, "UpdateButton", function(_, button)
                if IsSettingEnabled("skinCollections") then StyleCollectionSpellButton(button) end
            end)
        end
        SkinBase.SetFrameData(heirloomsMixin, "qCollectionStyleHooked", true)
    end
    local mixin = _G.WardrobeSetsScrollFrameButtonMixin
    if mixin and not SkinBase.GetFrameData(mixin, "qCollectionStyleHooked") then
        if mixin.Init then hooksecurefunc(mixin, "Init", StyleCollectionListRow) end
        if mixin.SetSelected then
            hooksecurefunc(mixin, "SetSelected", function(row, selected)
                SkinBase.SetFrameData(row, "qCollectionSelected", selected)
                StyleCollectionListRow(row)
            end)
        end
        SkinBase.SetFrameData(mixin, "qCollectionStyleHooked", true)
    end
    local itemsMixin = _G.WardrobeCollectionFrame and _G.WardrobeCollectionFrame.ItemsCollectionFrame or _G.WardrobeItemsCollectionMixin
    if itemsMixin and itemsMixin.UpdateItems and not SkinBase.GetFrameData(itemsMixin, "qCollectionStyleHooked") then
        hooksecurefunc(itemsMixin, "UpdateItems", StyleWardrobeModels)
        SkinBase.SetFrameData(itemsMixin, "qCollectionStyleHooked", true)
    end
end

local function StyleCollectionsControls()
    HookCollectionUpdates()
    StyleCollectionsTitle(_G.CollectionsJournal)
    StyleToyAndHeirloomEntries()
    for _, name in ipairs({ "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame", "WarbandSceneJournal" }) do
        local page = _G[name]
        if page then
            StyleCollectionPage(page)
            if not SkinBase.GetFrameData(page, "qCollectionControlsHooked") then
                SkinBase.SetFrameData(page, "qCollectionControlsHooked", true)
                if page.HookScript then page:HookScript("OnShow", StyleCollectionsControls) end
            end
            local search = page.searchBox or page.SearchBox
            SkinBase.SkinEditBox(search)
            SkinBase.RefreshWidget(search)
            if search and search.searchIcon then search.searchIcon:SetAlpha(1) end
            local filter = page.FilterDropdown or page.FilterButton
            SkinBase.SkinDropdown(filter, { skinArrow = true })
            SkinBase.RefreshWidget(filter)
            StyleCollectionNeutralLabel(filter and (filter.Text or (filter.GetFontString and filter:GetFontString())))
            for _, key in ipairs({ "MountButton", "SummonButton", "FindBattleButton" }) do
                SkinBase.SkinButton(page[key])
                SkinBase.RefreshWidget(page[key])
            end
        end
    end
    StylePetCollection(_G.PetJournal)
    local mounts = _G.MountJournal
    if mounts then
        HookEncounterJournalScrollBox(mounts.ScrollBox, StyleCollectionListRow)
        StyleMountEquipment(mounts.BottomLeftInset and mounts.BottomLeftInset.SlotButton)
        StyleCollectionIconAction(mounts.ToggleDynamicFlightFlyoutButton)
        StyleCollectionIconAction(mounts.SummonRandomFavoriteSpellFrame and mounts.SummonRandomFavoriteSpellFrame.Button)
        local display = mounts.MountDisplay
        if display then
            SkinBase.ClampTextureHidden(display.YesMountsTex)
            SkinBase.ClampTextureHidden(display.NoMountsTex)
            SkinBase.ClampTextureHidden(display.ShadowOverlay, true)
            SkinBase.SkinFontString(display.InfoButton and display.InfoButton.Lore, { color = { 0.85, 0.85, 0.85, 1 } })
            local scene = display.ModelScene
            local controls = scene and scene.ControlFrame
            local toggle = scene and scene.TogglePlayer or (controls and controls.TogglePlayer)
            SkinBase.SkinCheckBox(toggle)
            local backdrop = toggle and SkinBase.GetBackdrop(toggle)
            if backdrop then
                backdrop:ClearAllPoints()
                backdrop:SetPoint("TOPLEFT", toggle, "TOPLEFT", 6, -6)
                backdrop:SetPoint("BOTTOMRIGHT", toggle, "BOTTOMRIGHT", -6, 6)
                SkinBase.ApplyChromeBackdrop(backdrop, { radius = 3, withBackground = true })
            end
            StyleCollectionNeutralLabel(toggle and toggle.TogglePlayerText)
        end
    end
    local wardrobe = _G.WardrobeCollectionFrame
    if wardrobe then
        local tabs = { wardrobe.ItemsTab, wardrobe.SetsTab }
        SkinBase.SkinTabGroup(tabs, wardrobe, { resizeToText = true, hover = true })
        StyleCollectionSurface(wardrobe.ItemsCollectionFrame)
        StyleCollectionPage(wardrobe.ItemsCollectionFrame)
        StyleWardrobeModels(wardrobe.ItemsCollectionFrame)
        local sets = wardrobe.SetsCollectionFrame
        StyleCollectionPage(sets)
        if sets then
            HookEncounterJournalScrollBox(sets.ListContainer and sets.ListContainer.ScrollBox, StyleCollectionListRow)
            local details = sets.DetailsFrame
            if details then
                SkinBase.ClampTextureHidden(details.IconRowBackground)
                SkinBase.ClampTextureHidden(details.ModelFadeTexture)
                SkinBase.SkinFontString(details.Name, { color = { 1, 1, 1, 1 } })
                SkinBase.SkinFontString(details.LongName, { color = { 1, 1, 1, 1 } })
            end
            SkinBase.SkinTrimScrollBar(sets.ListContainer and sets.ListContainer.ScrollBar)
            SkinBase.SkinDropdown(sets.DetailsFrame and sets.DetailsFrame.VariantSetsDropdown, { skinArrow = true })
        end
    end
    local scenes = _G.WarbandSceneJournal
    local icons = scenes and scenes.IconsFrame and scenes.IconsFrame.Icons
    local controls = icons and icons.Controls
    if icons and icons.EnumerateFrames then
        for _, entry in icons:EnumerateFrames() do StyleCampsiteEntry(entry) end
    end
    StyleCollectionPaging(controls and controls.PagingControls)
    local checkbox = controls and controls.ShowOwned and controls.ShowOwned.Checkbox
    if checkbox then SkinBase.SkinCheckBox(checkbox) end
end

local function SkinCollections()
    if not IsSettingEnabled("skinCollections") then return end
    local frame = _G.CollectionsJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    local tabs = frame.TabContainer and frame.TabContainer.Tabs
        or SkinBase.CollectNumberedTabs("CollectionsJournal", 6)
    SkinBase.SkinTabGroup(tabs, frame, { resizeToText = true, dockBottom = true })
    HookCollectionsText(frame)
    StyleCollectionsControls()
    frame:HookScript("OnShow", StyleCollectionsControls)
    SkinBase.MarkSkinned(frame)
end

local function RefreshCollections()
    local frame = _G.CollectionsJournal
    if not frame or not IsSettingEnabled("skinCollections") then return end
    RefreshBackdropColors(frame)
    local tabs = frame.TabContainer and frame.TabContainer.Tabs
        or SkinBase.CollectNumberedTabs("CollectionsJournal", 6)
    SkinBase.RefreshTabGroup(tabs, frame)
    HookCollectionsText(frame)
    StyleCollectionsControls()
end
_G.QUI_RefreshCollectionsColors = RefreshCollections
if ns.Registry then
    ns.Registry:Register("skinCollections", {
        refresh = RefreshCollections,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_PlayerSpells",     SkinPlayerSpells,     0)
SkinBase.OnAddOnLoaded("Blizzard_EncounterJournal", SkinEncounterJournal, 0)
SkinBase.OnAddOnLoaded("Blizzard_Collections",      SkinCollections,      0)
