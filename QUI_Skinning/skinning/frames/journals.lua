---------------------------------------------------------------------------
-- JOURNAL FRAMES SKINNING
--
--   - PlayerSpellsFrame  (PortraitFrameTemplate, LOD Blizzard_PlayerSpells)
--                        — modern combined SpellBook + Talents window
--   - EncounterJournal   (PortraitFrameTemplate, LOD Blizzard_EncounterJournal)
--                        — Adventure Guide
--   - CollectionsJournal (PortraitFrameTemplate, LOD Blizzard_Collections)
--                        — parent of MountJournal / PetJournal / ToyBox /
--                          WardrobeFrame / HeirloomsJournal sub-tabs
--
-- All inherit PortraitFrameTemplate, so SkinBase.SkinButtonFrameTemplate
-- handles chrome strip + backdrop + close-button styling. The Collections
-- sub-tab frames render inside CollectionsJournal so the parent skin
-- covers most visible chrome; per-tab work is a follow-up if needed.
---------------------------------------------------------------------------

-- luacheck: globals PagedContentFrameBaseMixin MonthlyActivitiesFrameMixin

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors

---------------------------------------------------------------------------
-- PlayerSpellsFrame (SpellBook + Talents)
---------------------------------------------------------------------------
local function GetSpellBookFrame(frame)
    return frame and (frame.SpellBookFrame or _G.SpellBookFrame)
end

local function SkinPlayerSpellsText(frame)
    if not frame or not IsSettingEnabled("skinSpellBook") then return end

    SkinBase.SkinFrameText(frame, { recurse = true, chrome = true })

    local spellBookFrame = GetSpellBookFrame(frame)
    local pagedSpellsFrame = spellBookFrame and spellBookFrame.PagedSpellsFrame
    if pagedSpellsFrame and pagedSpellsFrame.EnumerateFrames then
        for _, spellFrame in pagedSpellsFrame:EnumerateFrames() do
            SkinBase.SkinFrameText(spellFrame, { recurse = true, chrome = true })
        end
    end
end

local function SchedulePlayerSpellsText(frame)
    C_Timer.After(0, function()
        SkinPlayerSpellsText(frame)
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
    -- Modern TabSystemTemplate tabs live at frame.TabSystem.tabs.
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.SkinTabGroup(frame.TabSystem.tabs, frame)
        if not SkinBase.GetFrameData(frame.TabSystem, "qTabSysHooked") then
            hooksecurefunc(frame.TabSystem, "SetTab", function()
                C_Timer.After(0, function()
                    for _, t in ipairs(frame.TabSystem.tabs) do
                        SkinBase.RefreshTabSelected(t, frame)
                    end
                end)
            end)
            SkinBase.SetFrameData(frame.TabSystem, "qTabSysHooked", true)
        end
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

---------------------------------------------------------------------------
-- EncounterJournal
---------------------------------------------------------------------------
local function SkinEncounterJournalTextFrame(frame)
    if frame then
        SkinBase.SkinFrameText(frame, { recurse = true, chrome = true })
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

    if monthlyFrame.ScrollBox and monthlyFrame.ScrollBox.ForEachFrame then
        pcall(monthlyFrame.ScrollBox.ForEachFrame, monthlyFrame.ScrollBox, SkinMonthlyActivitiesActivityButton)
    end

    local filterScrollBox = monthlyFrame.FilterList and monthlyFrame.FilterList.ScrollBox
    if filterScrollBox and filterScrollBox.ForEachFrame then
        pcall(filterScrollBox.ForEachFrame, filterScrollBox, SkinMonthlyActivitiesFilterButton)
    end
end

local function SkinEncounterJournalText(frame)
    if not frame or not IsSettingEnabled("skinEncounterJournal") then return end

    SkinEncounterJournalTextFrame(frame)
    SkinMonthlyActivitiesText(frame.MonthlyActivitiesFrame)

    local encounter = frame.encounter
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

local function ScheduleEncounterJournalText(frame, focusFrame)
    C_Timer.After(0, function()
        SkinEncounterJournalTextFrame(focusFrame)
        if focusFrame and focusFrame.GetParent then
            SkinEncounterJournalTextFrame(focusFrame:GetParent())
        end
        SkinEncounterJournalText(frame)
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

local function ScheduleMonthlyActivitiesText(monthlyFrame, focusFrame)
    C_Timer.After(0, function()
        SkinEncounterJournalTextFrame(focusFrame)
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

    SkinBase.SetFrameData(frame, "qEncounterJournalTextHooked", true)
end

local function SkinEncounterJournal()
    if not IsSettingEnabled("skinEncounterJournal") then return end
    local frame = _G.EncounterJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    HookEncounterJournalTextUpdates(frame)
    HookEncounterJournalScrollBoxes(frame)
    SkinEncounterJournalText(frame)
    SkinBase.MarkSkinned(frame)
end

local function RefreshEncounterJournal()
    local frame = _G.EncounterJournal
    RefreshBackdropColors(frame)
    if not frame or not IsSettingEnabled("skinEncounterJournal") then return end
    if not SkinBase.IsSkinned(frame) then
        SkinEncounterJournal()
        return
    end
    HookEncounterJournalTextUpdates(frame)
    HookEncounterJournalScrollBoxes(frame)
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

---------------------------------------------------------------------------
-- CollectionsJournal
---------------------------------------------------------------------------
local function SkinCollections()
    if not IsSettingEnabled("skinCollections") then return end
    local frame = _G.CollectionsJournal
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- CollectionsJournalTab1..6: Mounts / Pets / Toys / Heirlooms / Wardrobe / WarbandScenes
    local tabs = {}
    for i = 1, 6 do
        local tab = _G["CollectionsJournalTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.SkinTabGroup(tabs, frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshCollections() RefreshBackdropColors(_G.CollectionsJournal) end
_G.QUI_RefreshCollectionsColors = RefreshCollections
if ns.Registry then
    ns.Registry:Register("skinCollections", {
        refresh = RefreshCollections,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
SkinBase.OnAddOnLoaded("Blizzard_PlayerSpells",     SkinPlayerSpells,     0.1)
SkinBase.OnAddOnLoaded("Blizzard_EncounterJournal", SkinEncounterJournal, 0.1)
SkinBase.OnAddOnLoaded("Blizzard_Collections",      SkinCollections,      0.1)
