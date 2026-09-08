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

local function SkinSpellRows(frame)
    if not frame or not IsSettingEnabled("skinSpellBook") then return end
    local spellBookFrame = GetSpellBookFrame(frame)
    local pagedSpellsFrame = spellBookFrame and spellBookFrame.PagedSpellsFrame
    if pagedSpellsFrame and pagedSpellsFrame.EnumerateFrames then
        for _, spellFrame in pagedSpellsFrame:EnumerateFrames() do
            SkinBase.SkinFrameText(spellFrame, { recurse = true, chrome = true })
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

local function SkinPlayerSpellsText(frame)
    if not frame or not IsSettingEnabled("skinSpellBook") then return end
    HookTalentSpendTextUpdates(frame)
    SkinBase.SkinFrameText(frame, { recurse = true, chrome = true })
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
        SkinBase.SkinTabGroup(frame.TabSystem.tabs, frame)
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
    for _, tab in ipairs(tabs) do
        SkinBase.ApplyButtonFontObjects(tab)
    end
end

local function SkinEncounterJournalTutorialsButton(frame)
    local tutorials = frame and frame.TutorialsFrame
    local contents = tutorials and tutorials.Contents
    local startButton = contents and contents.StartButton
    if not startButton then return end
    SkinBase.ApplyButtonFontObjects(startButton)
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

    SkinEncounterJournalTextFrame(button)
    SkinEncounterJournalTextFrame(button and button.TextContainer)
end

local function SkinMonthlyActivitiesFilterButton(button)
    HookEncounterJournalObjectMethod(button, "qMonthlyActivityFilterTextHooked", "UpdateStateInternal",
        function(filterButton)
            ScheduleEncounterJournalTextFrame(filterButton)
        end)

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

local function SkinEncounterJournalEncounterText(frame)
    local encounter = frame and frame.encounter
    if not encounter then return end

    SkinEncounterJournalTextFrame(encounter.infoFrame)
    SkinEncounterJournalTextFrame(encounter.overviewFrame)

    local overviewFrame = encounter.overviewFrame
    if overviewFrame and overviewFrame.overviews then
        for _, overview in ipairs(overviewFrame.overviews) do
            SkinEncounterJournalTextFrame(overview)
        end
    end

    if encounter.usedHeaders then
        for _, header in ipairs(encounter.usedHeaders) do
            SkinEncounterJournalTextFrame(header)
        end
    end

    if encounter.freeHeaders then
        for _, header in ipairs(encounter.freeHeaders) do
            SkinEncounterJournalTextFrame(header)
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
    if SkinBase.HookScrollBoxAcquired then
        SkinBase.HookScrollBoxAcquired(scrollBox, callback or SkinEncounterJournalTextFrame)
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

local function SkinEncounterJournal()
    if not IsSettingEnabled("skinEncounterJournal") then return end
    local frame = _G.EncounterJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
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
    SkinEncounterJournalBottomTabs(frame)
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

local function SkinCollections()
    if not IsSettingEnabled("skinCollections") then return end
    local frame = _G.CollectionsJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    local tabs = {}
    for i = 1, 6 do
        local tab = _G["CollectionsJournalTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.SkinTabGroup(tabs, frame, { resizeToText = true })
    HookCollectionsText(frame)
    SkinBase.MarkSkinned(frame)
end

local function RefreshCollections()
    local frame = _G.CollectionsJournal
    if not frame or not IsSettingEnabled("skinCollections") then return end
    RefreshBackdropColors(frame)
    local tabs = {}
    for i = 1, 6 do
        local tab = _G["CollectionsJournalTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.RefreshTabGroup(tabs, frame)
    HookCollectionsText(frame)
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
