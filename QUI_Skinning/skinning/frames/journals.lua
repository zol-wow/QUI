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

-- Skin ONLY the currently-displayed (pooled) spell rows. This is the cheap
-- per-page path: it touches the ~dozen visible element frames, never the whole
-- PlayerSpellsFrame tree. Runs on every PagedContentFrame OnUpdate (page /
-- category switch), so it must stay light.
local function SkinSpellRows(frame)
    if not frame or not IsSettingEnabled("skinSpellBook") then return end
    local spellBookFrame = GetSpellBookFrame(frame)
    local pagedSpellsFrame = spellBookFrame and spellBookFrame.PagedSpellsFrame
    if pagedSpellsFrame and pagedSpellsFrame.EnumerateFrames then
        for _, spellFrame in pagedSpellsFrame:EnumerateFrames() do
            SkinBase.SkinFrameText(spellFrame, { recurse = true, chrome = true })
            -- Spell rows are pooled and Blizzard swaps their font OBJECT on
            -- hover / page re-bind; lock so the one-shot skin above survives.
            SkinBase.LockFrameTextObjects(spellFrame, 3)
        end
    end
end

-- Full one-shot chrome pass over the whole PlayerSpellsFrame (titles, search
-- box, talent labels, category tabs). EXPENSIVE: recurses the entire frame
-- incl. the talent tree's hundreds of node children, so it runs ONLY at
-- init/refresh — NOT on every page update (that caused a stutter when clicking
-- between the class / general / pet category tabs).
local function SkinPlayerSpellsText(frame)
    if not frame or not IsSettingEnabled("skinSpellBook") then return end
    SkinBase.SkinFrameText(frame, { recurse = true, chrome = true })
    SkinSpellRows(frame)
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

---------------------------------------------------------------------------
-- Talent tree node text. Talent buttons are pooled lazily and each swaps its
-- .SpendText font OBJECT on draw, so a one-shot skin reverts. LockFontObject
-- (via LockFrameTextObjects) makes the QUI font survive those swaps. New /
-- recycled buttons come through AcquireTalentButton, so hook it (debounced to
-- one enumerate-and-lock pass per frame) to cover buttons created after init.
---------------------------------------------------------------------------
local talentLockPending
local function LockTalentButtons(talentsFrame)
    if not IsSettingEnabled("skinSpellBook") then return end
    if not talentsFrame or not talentsFrame.EnumerateAllTalentButtons then return end
    for btn in talentsFrame:EnumerateAllTalentButtons() do
        SkinBase.LockFrameTextObjects(btn, 2)
    end
end

local function ScheduleTalentLock(talentsFrame)
    if talentLockPending then return end
    talentLockPending = true
    C_Timer.After(0, function()
        talentLockPending = false
        LockTalentButtons(talentsFrame)
    end)
end

local function HookTalentButtons(frame)
    local talentsFrame = frame and frame.TalentsFrame
    if not talentsFrame or not talentsFrame.AcquireTalentButton then return end
    if not SkinBase.GetFrameData(talentsFrame, "qTalentTextHooked") then
        hooksecurefunc(talentsFrame, "AcquireTalentButton", function(self)
            ScheduleTalentLock(self)
        end)
        SkinBase.SetFrameData(talentsFrame, "qTalentTextHooked", true)
    end
    ScheduleTalentLock(talentsFrame)
end

local function SkinPlayerSpells()
    if not IsSettingEnabled("skinSpellBook") then return end
    local frame = _G.PlayerSpellsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- Modern TabSystemTemplate tabs live at frame.TabSystem.tabs.
    if frame.TabSystem and frame.TabSystem.tabs then
        -- SkinTabGroup already wires the SetTab programmatic-switch refresh via
        -- RegisterOwnerTabRefresh (sets qTabSysHooked), so a manual hook here is dead.
        SkinBase.SkinTabGroup(frame.TabSystem.tabs, frame)
    end
    -- The class / general / pet category tabs live on a SEPARATE TabSystem
    -- (SpellBookFrame.CategoryTabSystem), not frame.TabSystem above. They use
    -- TabSystemButtonArtMixin:SetTabSelected, which calls SetNormalFontObject
    -- on every selection — reverting the QUI font on each click. Lock them so
    -- the swap re-applies the QUI face. (Initial face comes from the full
    -- SkinPlayerSpellsText recurse below.)
    local spellBookFrame = GetSpellBookFrame(frame)
    local categoryTabs = spellBookFrame and spellBookFrame.CategoryTabSystem
        and spellBookFrame.CategoryTabSystem.tabs
    if categoryTabs then
        for _, t in ipairs(categoryTabs) do
            SkinBase.ApplyButtonFontObjects(t)
            SkinBase.LockFrameTextObjects(t, 2)
        end
    end
    -- Spec/talent action buttons swap their Highlight/Disabled font OBJECT on
    -- hover/disable with no setter call — SkinFrameText's one-shot face reverts.
    -- Drive the button font objects so the QUI face survives.
    local function DriveButtonFont(btn)
        if btn then SkinBase.ApplyButtonFontObjects(btn) end
    end
    -- The spec "Activate" buttons are NOT frame.SpecFrame.ActivateButton — they
    -- live on a POOL of ClassSpecContentFrameTemplate frames (one per spec) at
    -- frame.SpecFrame.SpecContentFramePool, each with its own .ActivateButton
    -- (MagicButton). ClassSpecFrameMixin:SetEnabled re-asserts the stock Normal/
    -- Disabled font object on every UpdateSpecFrame/activation, so font when the
    -- pool is (re)built, not just once.
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
    HookTalentButtons(frame)
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
    -- Re-read theme colors into the tab tints (RefreshTabSelected alone re-applies stale stored colors).
    if frame.TabSystem and frame.TabSystem.tabs then
        SkinBase.RefreshTabGroup(frame.TabSystem.tabs, frame)
    end
    HookPlayerSpellsTextUpdates(frame)
    HookTalentButtons(frame)
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
        if SkinBase.LockFrameTextObjects then
            SkinBase.LockFrameTextObjects(frame, 3)
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

-- Bottom content tabs (Suggestions / Dungeons / Raids / Loot / Journeys /
-- Monthly Activities / Tutorials). Font-only fix — we DON'T reskin the tab art
-- (left as Blizzard's). ApplyButtonFontObjects sets the tab's Normal / Highlight
-- / Disabled font OBJECTS to the QUI font, so neither hover (engine shows the
-- HIGHLIGHT object with no setter call) nor selection (Blizzard sets the
-- DISABLED object) reverts; LockFrameTextObjects re-asserts after the
-- PanelTemplates_SelectTab SetDisabledFontObject swap.
local function SkinEncounterJournalBottomTabs(frame)
    local tabs = GetEncounterJournalBottomTabs(frame)
    if not tabs or #tabs == 0 then return end
    for _, tab in ipairs(tabs) do
        SkinBase.ApplyButtonFontObjects(tab)
        SkinBase.LockFrameTextObjects(tab, 2)
    end
end

-- Tutorials tab "Start Catch-Up Experience" button
-- (EncounterJournal.TutorialsFrame.Contents.StartButton, RPE_START_EXPERIENCE).
-- It inherits SharedButtonSmallTemplate whose Normal/Highlight/Disabled font
-- OBJECTS are GameFont* (FRIZQT); the engine re-asserts them on show/enable/
-- disable, reverting the one-shot recursive font sweep. ApplyButtonFontObjects
-- drives the button's font objects to the QUI face so the swaps stay QUI.
local function SkinEncounterJournalTutorialsButton(frame)
    local tutorials = frame and frame.TutorialsFrame
    local contents = tutorials and tutorials.Contents
    local startButton = contents and contents.StartButton
    if not startButton then return end
    SkinBase.ApplyButtonFontObjects(startButton)
    SkinBase.LockFrameTextObjects(startButton, 2)
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

-- Encounter description / overview / boss-ability headers only. This is the
-- subtree EncounterJournal_ToggleHeaders / SetBullets / SetDescriptionWithBullets
-- mutate, so the runtime hooks re-skin THIS (cheap) instead of recursing the
-- whole EncounterJournal tree.
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

-- Full one-shot pass: whole-frame chrome recurse + Monthly Activities + the
-- encounter subtree. EXPENSIVE (recurses the entire EncounterJournal incl. the
-- instance / boss lists), so it runs ONLY at init/refresh — never on the
-- per-row update hooks, which caused the Adventure Guide / Traveler's Log open
-- stutter (mirrors the spellbook category-tab fix).
local function SkinEncounterJournalText(frame)
    if not frame or not IsSettingEnabled("skinEncounterJournal") then return end

    SkinEncounterJournalTextFrame(frame)
    SkinMonthlyActivitiesText(frame.MonthlyActivitiesFrame)
    SkinEncounterJournalEncounterText(frame)
end

local encounterTextPending
local function ScheduleEncounterJournalText(frame, focusFrame)
    if focusFrame then
        -- Targeted: skin the changed element (+ its parent header/container).
        -- EncounterJournal_UpdateButtonState fires once per instance/boss row on
        -- every list build; the old behavior ALSO recursed the whole
        -- EncounterJournal tree per fire (incl. Monthly Activities) — that was
        -- the open stutter. Skinning just focusFrame + parent is bounded.
        C_Timer.After(0, function()
            SkinEncounterJournalTextFrame(focusFrame)
            if focusFrame.GetParent then
                SkinEncounterJournalTextFrame(focusFrame:GetParent())
            end
        end)
        return
    end
    -- No focus (boss description / bullets / headers changed): coalesce to one
    -- encounter-subtree pass per frame instead of a whole-frame recurse per
    -- hook fire.
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
    -- Targeted element (e.g. BarComplete / HeaderContainer) — cheap, run now.
    if focusFrame then
        C_Timer.After(0, function()
            SkinEncounterJournalTextFrame(focusFrame)
        end)
    end
    -- Traveler's Log fires OnShow + UpdateActivities + SetActivities +
    -- SetThresholds (+ more) back-to-back on open; coalesce the full Monthly
    -- Activities sweep to one run per frame so the open doesn't stutter.
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
    -- Adventure Guide "Suggestions" tab: EJSuggestFrame_RefreshDisplay
    -- (Blizzard_EncounterJournal.lua) re-applies SetFontObject to the
    -- suggestion title/description text on every show / scroll / next-prev,
    -- and those Adventure-Journal font objects carry near-black / dark-red
    -- colors meant for the light suggestion art -> unreadable on the QUI dark
    -- theme. Re-skin the suggestFrame (chrome = near-white) after each refresh.
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
    -- Gate before recoloring (matches RefreshPlayerSpells): a disabled module should
    -- not recolor its (possibly leftover) backdrop on a theme refresh.
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

---------------------------------------------------------------------------
-- CollectionsJournal
---------------------------------------------------------------------------
local function LockCollectionsText(frame)
    if SkinBase.LockFrameTextObjects and frame then
        SkinBase.SkinFrameText(frame, { recurse = true })
        SkinBase.LockFrameTextObjects(frame, 4)
    end
end

local function LockCollectionsScrollBox(scrollBox)
    if not scrollBox then return end
    -- Guarded per-row font lock (recursive pass runs once per pooled row; the
    -- LockFontObject hooks re-assert the QUI face on later rebinds). Replaces an
    -- unguarded acquire callback + redundant ForEachFrame sweep — re-walking
    -- Mount/Pet/Heirloom rows on every open was the open-window hitch.
    SkinBase.HookScrollBoxRowFonts(scrollBox, 3)
end

local function LockHeirloomFrame(frame)
    if not frame or SkinBase.GetFrameData(frame, "qHeirloomTextLocked") then return end
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 3)
    SkinBase.SetFrameData(frame, "qHeirloomTextLocked", true)
end

local function LockHeirloomsJournal(journal)
    if not journal then return end
    if journal.heirloomEntryFrames then
        for _, frame in ipairs(journal.heirloomEntryFrames) do
            LockHeirloomFrame(frame)
        end
    end
    if journal.heirloomHeaderFrames then
        for _, frame in ipairs(journal.heirloomHeaderFrames) do
            LockHeirloomFrame(frame)
        end
    end
end

local function HookHeirloomsJournal(journal)
    if not journal or SkinBase.GetFrameData(journal, "qHeirloomsJournalTextHooked") then return end

    if type(journal.AcquireFrame) == "function" then
        hooksecurefunc(journal, "AcquireFrame", function(_, framePool, numInUse)
            LockHeirloomFrame(framePool and framePool[numInUse])
        end)
    end
    if type(journal.RefreshView) == "function" then
        hooksecurefunc(journal, "RefreshView", function(activeJournal)
            LockHeirloomsJournal(activeJournal)
        end)
    end
    if type(journal.UpdateButton) == "function" then
        hooksecurefunc(journal, "UpdateButton", function(_, button)
            LockHeirloomFrame(button)
        end)
    end

    SkinBase.SetFrameData(journal, "qHeirloomsJournalTextHooked", true)
    LockHeirloomsJournal(journal)
end

local function HookCollectionsText(frame)
    LockCollectionsText(frame)
    -- Bottom action buttons (MountJournal.MountButton "MOUNT", PetJournal summon
    -- buttons, etc.) are MagicButton/UIPanel-style: the engine swaps their
    -- Highlight/Disabled font OBJECT on hover/disable without calling a setter, so
    -- LockFrameTextObjects above can't catch it. Drive their font objects.
    if SkinBase.ApplyButtonFontObjectsDeep then
        SkinBase.ApplyButtonFontObjectsDeep(frame, 5)
    end
    LockCollectionsScrollBox(_G.MountJournal and _G.MountJournal.ScrollBox)
    LockCollectionsScrollBox(_G.PetJournal and _G.PetJournal.ScrollBox)
    HookHeirloomsJournal(_G.HeirloomsJournal)

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
    -- CollectionsJournalTab1..6: Mounts / Pets / Toys / Heirlooms / Wardrobe / WarbandScenes
    local tabs = {}
    for i = 1, 6 do
        local tab = _G["CollectionsJournalTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.SkinTabGroup(tabs, frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    HookCollectionsText(frame)
    SkinBase.MarkSkinned(frame)
end

local function RefreshCollections()
    local frame = _G.CollectionsJournal
    if not frame or not IsSettingEnabled("skinCollections") then return end
    RefreshBackdropColors(frame)
    -- Recolor the CollectionsJournalTab1..6 strip on a live theme/accent change
    -- (RefreshTabSelected alone re-applies stale stored tints).
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

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
-- delay 0 = skin synchronously inside the ADDON_LOADED handler, BEFORE the LOD
-- frame's first paint, so the window never flashes Blizzard FRIZQT before the
-- QUI font lands. (The 0.1s defer skinned a frame already on screen → flash.)
SkinBase.OnAddOnLoaded("Blizzard_PlayerSpells",     SkinPlayerSpells,     0)
SkinBase.OnAddOnLoaded("Blizzard_EncounterJournal", SkinEncounterJournal, 0)
SkinBase.OnAddOnLoaded("Blizzard_Collections",      SkinCollections,      0)
