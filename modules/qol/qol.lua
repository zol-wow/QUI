local addonName, ns = ...
local Helpers = ns.Helpers
addonName = addonName or "QUI"

---------------------------------------------------------------------------
-- QOL AUTOMATION FEATURES
---------------------------------------------------------------------------

local GetSettings = Helpers.CreateDBGetter("general")

local qolFrame = CreateFrame("Frame")

local popupBlockerDefaults = {
    enabled = false,
    blockTalentMicroButtonAlerts = false,
    blockEventToasts = false,
    blockMountAlerts = false,
    blockPetAlerts = false,
    blockToyAlerts = false,
    blockCosmeticAlerts = false,
    blockWarbandSceneAlerts = false,
    blockEntitlementAlerts = false,
    blockStaticTalentPopups = false,
    blockStaticHousingPopups = false,
}

local staticPopupBlockRules = {
    blockStaticTalentPopups = { "TALENT", "TRAIT", "PLAYER_SPELLS", "PLAYERSP" },
    blockStaticHousingPopups = { "HOUSING", "HOMESTEAD", "WARBAND_HOME", "WARBANDHOME" },
}

local alertSystemToggleMap = {
    NewMountAlertSystem = "blockMountAlerts",
    NewPetAlertSystem = "blockPetAlerts",
    NewToyAlertSystem = "blockToyAlerts",
    NewCosmeticAlertFrameSystem = "blockCosmeticAlerts",
    NewWarbandSceneAlertSystem = "blockWarbandSceneAlerts",
    EntitlementDeliveredAlertSystem = "blockEntitlementAlerts",
    RafRewardDeliveredAlertSystem = "blockEntitlementAlerts",
}

local talentMicroButtonCandidates = {
    "PlayerSpellsMicroButton",
    "TalentMicroButton",
    "SpellbookMicroButton",
}

local talentMicroButtonAlertCandidates = {
    "PlayerSpellsMicroButtonAlert",
    "TalentMicroButtonAlert",
    "SpellbookMicroButtonAlert",
}

local hookedAlertSystems = {}
local eventToastHooked = false
local mainMenuAlertHooked = false
local _quiPopupBlockerHooked = {}  -- Track hooked alert frames (avoids writing to Blizzard frames)

local function GetMaxStaticPopupDialogs()
    return math.min(STATICPOPUP_NUMDIALOGS or 4, 8)
end

local function GetPopupBlockerSettings()
    local settings = GetSettings()
    if not settings then return nil end

    if type(settings.popupBlocker) ~= "table" then
        settings.popupBlocker = {}
    end

    local blocker = settings.popupBlocker
    for key, defaultValue in pairs(popupBlockerDefaults) do
        if blocker[key] == nil then
            blocker[key] = defaultValue
        end
    end

    return blocker
end

local function IsPopupBlockEnabled(toggleKey)
    local blocker = GetPopupBlockerSettings()
    if not blocker or not blocker.enabled then
        return false
    end
    return blocker[toggleKey] == true
end

local function HideAlertFrame(frame)
    if not frame then return end
    if frame.Hide then
        frame:Hide()
    end
end

local function ShouldBlockStaticPopup(which)
    if type(which) ~= "string" then return false end

    local blocker = GetPopupBlockerSettings()
    if not blocker or not blocker.enabled then
        return false
    end

    local upperWhich = string.upper(which)
    for toggleKey, keywords in pairs(staticPopupBlockRules) do
        if blocker[toggleKey] then
            for _, keyword in ipairs(keywords) do
                if string.find(upperWhich, keyword, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function HideStaticPopupByWhich(which)
    if type(which) ~= "string" then return end

    for i = 1, GetMaxStaticPopupDialogs() do
        local frame = _G["StaticPopup" .. i]
        if frame and frame.which == which and frame:IsShown() then
            frame:Hide()
        end
    end
end

local function HookAlertSystem(globalSystemName, toggleKey)
    local system = _G[globalSystemName]
    if not system or hookedAlertSystems[system] then
        return
    end

    if type(system.setUpFunction) ~= "function" then
        return
    end

    -- TAINT SAFETY: Defer to break taint chain from secure alert system context.
    hooksecurefunc(system, "setUpFunction", function(frame)
        C_Timer.After(0, function()
            if IsPopupBlockEnabled(toggleKey) then
                HideAlertFrame(frame)
            end
        end)
    end)
    hookedAlertSystems[system] = true
end

local function HookPopupAlertSystems()
    for globalSystemName, toggleKey in pairs(alertSystemToggleMap) do
        HookAlertSystem(globalSystemName, toggleKey)
    end
end

local function HideEventToasts()
    if not IsPopupBlockEnabled("blockEventToasts") then return end
    if not EventToastManagerFrame then return end
    EventToastManagerFrame:Hide()
end

local function HookEventToastManager()
    if eventToastHooked or not EventToastManagerFrame then
        return
    end

    -- TAINT SAFETY: Defer to break taint chain — EventToastManagerFrame methods
    -- can fire inside secure execution contexts.
    local function PostShowHide(self)
        C_Timer.After(0, function()
            if IsPopupBlockEnabled("blockEventToasts") then
                self:Hide()
            end
        end)
    end

    hooksecurefunc(EventToastManagerFrame, "Show", PostShowHide)
    if type(EventToastManagerFrame.ShowToast) == "function" then
        hooksecurefunc(EventToastManagerFrame, "ShowToast", PostShowHide)
    end
    if type(EventToastManagerFrame.DisplayToast) == "function" then
        hooksecurefunc(EventToastManagerFrame, "DisplayToast", PostShowHide)
    end
    if type(EventToastManagerFrame.QueueToast) == "function" then
        hooksecurefunc(EventToastManagerFrame, "QueueToast", PostShowHide)
    end

    eventToastHooked = true
end

local function IsTalentMicroButton(button)
    if not button then return false end
    if (PlayerSpellsMicroButton and button == PlayerSpellsMicroButton)
        or (TalentMicroButton and button == TalentMicroButton)
        or (SpellbookMicroButton and button == SpellbookMicroButton) then
        return true
    end

    local name = button.GetName and button:GetName()
    if type(name) ~= "string" then
        return false
    end

    local upperName = string.upper(name)
    return string.find(upperName, "TALENT", 1, true)
        or string.find(upperName, "SPELLBOOK", 1, true)
        or string.find(upperName, "PLAYERSP", 1, true)
end

local function HideTalentMicroButtonAlert(button)
    if not button then return end

    local alert = button.alert
    if not alert and button.GetName then
        alert = _G[button:GetName() .. "Alert"]
    end
    if alert then
        alert:Hide()
    end

    if button.NewFeatureTexture then
        button.NewFeatureTexture:Hide()
    end
    if button.NewFeatureShine then
        button.NewFeatureShine:Hide()
    end
    if button.Flash then
        button.Flash:Hide()
    end
end

local function HideTalentReminderAlerts()
    if not IsPopupBlockEnabled("blockTalentMicroButtonAlerts") then return end

    for _, buttonName in ipairs(talentMicroButtonCandidates) do
        local button = _G[buttonName]
        if button then
            HideTalentMicroButtonAlert(button)
        end
    end

    for _, alertName in ipairs(talentMicroButtonAlertCandidates) do
        local alertFrame = _G[alertName]
        if alertFrame then
            alertFrame:Hide()
        end
    end
end

local function HookTalentReminderAlerts()
    if not mainMenuAlertHooked and type(MainMenuMicroButton_ShowAlert) == "function" then
        -- TAINT SAFETY: Defer to break taint chain from secure context.
        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(button)
            C_Timer.After(0, function()
                if IsPopupBlockEnabled("blockTalentMicroButtonAlerts") and IsTalentMicroButton(button) then
                    HideTalentMicroButtonAlert(button)
                end
            end)
        end)
        mainMenuAlertHooked = true
    end

    -- Some frames are only created lazily, so keep checking and attach one-shot OnShow hooks.
    -- Use local table to track hooked frames (NOT writing to Blizzard frames to avoid taint)
    for _, alertName in ipairs(talentMicroButtonAlertCandidates) do
        local alertFrame = _G[alertName]
        if alertFrame and not _quiPopupBlockerHooked[alertFrame] then
            -- TAINT SAFETY: Defer to break taint chain from secure context.
            alertFrame:HookScript("OnShow", function(self)
                C_Timer.After(0, function()
                    if IsPopupBlockEnabled("blockTalentMicroButtonAlerts") and self and self.Hide then
                        self:Hide()
                    end
                end)
            end)
            _quiPopupBlockerHooked[alertFrame] = true
        end
    end
end

local function RefreshPopupBlocker()
    HookPopupAlertSystems()
    HookEventToastManager()
    HookTalentReminderAlerts()

    HideEventToasts()
    HideTalentReminderAlerts()
end

_G.QUI_RefreshPopupBlocker = RefreshPopupBlocker

if ns.Registry then
    ns.Registry:Register("popupBlocker", {
        refresh = _G.QUI_RefreshPopupBlocker,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
end

---------------------------------------------------------------------------
-- MERCHANT: SELL JUNK + AUTO REPAIR
---------------------------------------------------------------------------

local function OnMerchantShow()
    local settings = GetSettings()
    if not settings then return end

    -- Sell gray items
    if settings.sellJunk then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.quality == Enum.ItemQuality.Poor then
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end

    -- Auto repair (dropdown: "off", "personal", "guild")
    local repairMode = settings.autoRepair
    if repairMode and repairMode ~= "off" and CanMerchantRepair() then
        local repairCost = GetRepairAllCost()
        if repairCost and repairCost > 0 then
            if repairMode == "guild" then
                RepairAllItems(CanGuildBankRepair())
            else
                RepairAllItems(false)
            end
        end
    end
end

---------------------------------------------------------------------------
-- ROLE CHECK: AUTO ACCEPT
---------------------------------------------------------------------------

local function OnRoleCheckShow()
    local settings = GetSettings()
    if settings and settings.autoRoleAccept then
        CompleteLFGRoleCheck(true)
    end
end

---------------------------------------------------------------------------
-- PARTY INVITES: AUTO ACCEPT
---------------------------------------------------------------------------

local function IsFriendOrBNet(name)
    if not name then return false end
    -- Check regular friends
    if C_FriendList.IsFriend(name) then return true end
    -- Check BattleNet friends (by iterating through them)
    local numBNetTotal = BNGetNumFriends()
    for i = 1, numBNetTotal do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo then
            local charName = accountInfo.gameAccountInfo.characterName
            local realmName = accountInfo.gameAccountInfo.realmName
            if charName then
                local fullName = realmName and (charName .. "-" .. realmName) or charName
                if fullName == name or charName == name:match("^([^-]+)") then
                    return true
                end
            end
        end
    end
    return false
end

local function IsGuildMemberByName(name)
    if not name or not IsInGuild() then return false end
    local numMembers = GetNumGuildMembers()
    local searchName = name:match("^([^-]+)") or name
    for i = 1, numMembers do
        local memberName = GetGuildRosterInfo(i)
        if memberName then
            local memberShort = memberName:match("^([^-]+)") or memberName
            if memberShort == searchName then
                return true
            end
        end
    end
    return false
end

local function OnPartyInvite(inviterName)
    local settings = GetSettings()
    if not settings then return end

    -- Dropdown: "off", "all", "friends", "guild", "both"
    local mode = settings.autoAcceptInvites
    if not mode or mode == "off" then return end

    local shouldAccept = false

    if mode == "all" then
        shouldAccept = true
    elseif mode == "friends" then
        shouldAccept = IsFriendOrBNet(inviterName)
    elseif mode == "guild" then
        shouldAccept = IsGuildMemberByName(inviterName)
    elseif mode == "both" then
        shouldAccept = IsFriendOrBNet(inviterName) or IsGuildMemberByName(inviterName)
    end

    if shouldAccept then
        AcceptGroup()
        StaticPopup_Hide("PARTY_INVITE")
    end
end

---------------------------------------------------------------------------
-- QUESTS: AUTO ACCEPT & AUTO TURN-IN
---------------------------------------------------------------------------

local function ShouldPauseQuest(settings)
    return settings.questHoldShift and IsShiftKeyDown()
end

local function OnQuestDetail()
    local settings = GetSettings()
    if not settings or not settings.autoAcceptQuest then return end
    if ShouldPauseQuest(settings) then return end

    AcceptQuest()
end

local function OnQuestComplete()
    local settings = GetSettings()
    if not settings or not settings.autoTurnInQuest then return end
    if ShouldPauseQuest(settings) then return end

    -- If multiple reward choices exist, let player decide
    local numChoices = GetNumQuestChoices()
    if numChoices > 1 then return end

    GetQuestReward(numChoices > 0 and 1 or nil)
end

---------------------------------------------------------------------------
-- GOSSIP: AUTO-SELECT SINGLE OPTION
---------------------------------------------------------------------------

local gossipClicked = {}

local function OnGossipShow()
    local settings = GetSettings()
    if not settings or not settings.autoSelectGossip then return end

    -- Shift bypass: let user manually interact (reuse quest shift setting)
    if settings.questHoldShift and IsShiftKeyDown() then return end

    -- Get available quests (pickups) and active quests (turnins)
    local availableQuests = C_GossipInfo.GetAvailableQuests()
    local numActiveQuests = C_GossipInfo.GetNumActiveQuests()

    -- If quest options exist, don't auto-select gossip
    if (availableQuests and #availableQuests > 0) or (numActiveQuests and numActiveQuests > 0) then
        return
    end

    -- Get pure gossip options
    local options = C_GossipInfo.GetOptions()
    if not options or #options == 0 then return end

    -- Count valid options to ensure we truly have only one choice
    local validOptions = {}
    for _, option in pairs(options) do
        if option.gossipOptionID then
            table.insert(validOptions, option)
        end
    end

    -- ONLY auto-select when there is exactly 1 option
    if #validOptions == 1 then
        local option = validOptions[1]
        local optionID = option.gossipOptionID

        if optionID and not gossipClicked[optionID] then
            gossipClicked[optionID] = true
            C_GossipInfo.SelectOption(optionID)
        end
    end
    -- If there are multiple options, do NOTHING - let the player choose
    -- This prevents auto-skipping dialogue/cutscene choices
end

local function OnGossipClosed()
    gossipClicked = {}
end

---------------------------------------------------------------------------
-- FAST AUTO LOOT
---------------------------------------------------------------------------

local lootRetryPending = false

local function TryLootAll()
    local numItems = GetNumLootItems()
    for slotIndex = 1, numItems do
        if LootSlotHasItem(slotIndex) then
            LootSlot(slotIndex)
        end
    end
end

local function CheckRemainingLoot()
    lootRetryPending = false
    local settings = GetSettings()
    if not settings or not settings.fastAutoLoot then return end

    -- Check if any items still remain (handles stuck loot bug)
    local numItems = GetNumLootItems()
    for slotIndex = 1, numItems do
        if LootSlotHasItem(slotIndex) then
            TryLootAll()
            return
        end
    end
end

local function OnLootReady()
    local settings = GetSettings()
    if not settings or not settings.fastAutoLoot then return end

    -- Auto-enable WoW's auto-loot if our setting is on (lazy init on first loot)
    if not GetCVarBool("autoLootDefault") then
        SetCVar("autoLootDefault", "1")
    end

    TryLootAll()

    -- Schedule check for stuck items
    if not lootRetryPending then
        lootRetryPending = true
        C_Timer.After(0.1, CheckRemainingLoot)
    end
end

---------------------------------------------------------------------------
-- M+ COMBAT LOGGING
---------------------------------------------------------------------------

local wasLoggingBeforeChallenge = false
local mplusAutoLoggingActive = false
local wasInMythicPlus = false
local pendingMythicPlusUpdate = nil
local raidAutoLoggingActive = false
local wasInRaidInstance = false

local function CancelPendingMythicPlusUpdate()
    if pendingMythicPlusUpdate and pendingMythicPlusUpdate.Cancel then
        pendingMythicPlusUpdate:Cancel()
    end
    pendingMythicPlusUpdate = nil
end

local function IsMythicPlusActive()
    if C_MythicPlus and type(C_MythicPlus.IsMythicPlusActive) == "function" then
        local ok, active = pcall(C_MythicPlus.IsMythicPlusActive)
        if ok then
            return active == true
        end
    end

    if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok then
            return mapID ~= nil
        end
    end

    if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function" then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok then
            return active == true
        end
    end

    local _, instanceType, difficultyID = GetInstanceInfo()
    return instanceType == "party" and difficultyID == 8
end

local function StopMythicPlusLogging()
    if mplusAutoLoggingActive and LoggingCombat() then
        LoggingCombat(false)
        print("|cFF30D1FFQUI:|r Combat logging stopped")
    end

    mplusAutoLoggingActive = false
    wasLoggingBeforeChallenge = false
end

local function UpdateMythicPlusAutoLogging()
    local settings = GetSettings()
    local inMythicPlus = IsMythicPlusActive()

    if not settings or not settings.autoCombatLog then
        StopMythicPlusLogging()
        wasInMythicPlus = inMythicPlus
        return
    end

    if inMythicPlus then
        if not wasInMythicPlus then
            -- Remember if user already had logging enabled so we never stop their manual logging.
            wasLoggingBeforeChallenge = LoggingCombat()
            mplusAutoLoggingActive = false
        end

        if not LoggingCombat() then
            LoggingCombat(true)
            mplusAutoLoggingActive = true

            if wasInMythicPlus then
                print("|cFF30D1FFQUI:|r Combat logging resumed (active M+ detected)")
            else
                print("|cFF30D1FFQUI:|r Combat logging started for M+")
            end
        end
    elseif wasInMythicPlus then
        StopMythicPlusLogging()
    end

    wasInMythicPlus = inMythicPlus
end

local function ScheduleMythicPlusUpdate(delaySeconds)
    CancelPendingMythicPlusUpdate()
    pendingMythicPlusUpdate = C_Timer.NewTimer(delaySeconds or 0, function()
        pendingMythicPlusUpdate = nil
        UpdateMythicPlusAutoLogging()
    end)
end

local function IsInRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

local function UpdateRaidAutoLogging()
    local settings = GetSettings()
    local inRaidInstance = IsInRaidInstance()

    if not settings or not settings.autoCombatLogRaid then
        -- If disabled while active, only stop if QUI started it.
        if raidAutoLoggingActive and LoggingCombat() then
            LoggingCombat(false)
            print("|cFF30D1FFQUI:|r Combat logging stopped")
        end
        raidAutoLoggingActive = false
        wasInRaidInstance = inRaidInstance
        return
    end

    if inRaidInstance and not wasInRaidInstance then
        raidAutoLoggingActive = false

        if not LoggingCombat() then
            LoggingCombat(true)
            raidAutoLoggingActive = true
            print("|cFF30D1FFQUI:|r Combat logging started for raid")
        end
    elseif not inRaidInstance and wasInRaidInstance then
        -- Only stop if QUI started it on raid entry.
        if raidAutoLoggingActive and LoggingCombat() then
            LoggingCombat(false)
            print("|cFF30D1FFQUI:|r Combat logging stopped")
        end
        raidAutoLoggingActive = false
    end

    wasInRaidInstance = inRaidInstance
end

local function RefreshAutoCombatLogging()
    CancelPendingMythicPlusUpdate()
    UpdateMythicPlusAutoLogging()
    UpdateRaidAutoLogging()
end

_G.QUI_RefreshAutoCombatLogging = RefreshAutoCombatLogging

---------------------------------------------------------------------------
-- DELETE CONFIRMATION: AUTO-FILL
---------------------------------------------------------------------------

local deletePopups = {
    ["DELETE_ITEM"] = true,
    ["DELETE_GOOD_ITEM"] = true,
    ["DELETE_GOOD_QUEST_ITEM"] = true,
    ["DELETE_QUEST_ITEM"] = true,
}

-- TAINT SAFETY: Defer to break taint chain from secure context.
hooksecurefunc("StaticPopup_Show", function(which)
    C_Timer.After(0, function()
        if ShouldBlockStaticPopup(which) then
            HideStaticPopupByWhich(which)
            return
        end

        if not deletePopups[which] then return end

        local settings = GetSettings()
        if not settings or not settings.autoDeleteConfirm then return end

        -- Find the popup frame that's showing this dialog
        for i = 1, GetMaxStaticPopupDialogs() do
            local frame = _G["StaticPopup" .. i]
            if frame and frame.which == which and frame:IsShown() then
                local editBox = frame.editBox or _G["StaticPopup" .. i .. "EditBox"]
                if editBox then
                    editBox:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE")
                    -- Trigger OnTextChanged to enable the confirm button
                    local handler = editBox:GetScript("OnTextChanged")
                    if handler then
                        handler(editBox)
                    end
                -- Note: Cannot auto-click - DeleteCursorItem() is protected
            end
            break
        end
    end
    end)
end)

---------------------------------------------------------------------------
-- AUCTION HOUSE EXPANSION FILTER
---------------------------------------------------------------------------

local ahHooked = false

local function SetupAuctionHouseFilter()
    if ahHooked then return end
    if not AuctionHouseFrame then return end

    ahHooked = true

    local searchBar = AuctionHouseFrame.SearchBar
    local searchBox = searchBar.SearchBox

    local function applyFilter()
        local settings = GetSettings()
        if not settings or not settings.auctionHouseExpansionFilter then return end
        searchBar.FilterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
        searchBar:UpdateClearFiltersButton()
        searchBox:SetFocus()
    end

    searchBar:HookScript("OnShow", function() C_Timer.After(0, applyFilter) end)
    C_Timer.After(0, applyFilter)
end

---------------------------------------------------------------------------
-- CRAFTING ORDERS EXPANSION FILTER
---------------------------------------------------------------------------

local coHooked = false

local function SetupCraftingOrderFilter()
    if coHooked then return end
    local frame = ProfessionsCustomerOrdersFrame
    if not frame then return end

    local browseOrders = frame.BrowseOrders
    if not browseOrders or not browseOrders.SearchBar then return end

    coHooked = true

    local filterDropdown = browseOrders.SearchBar.FilterDropdown
    if not filterDropdown then return end

    local function applyFilter()
        local settings = GetSettings()
        if not settings or not settings.craftingOrderExpansionFilter then return end
        if not filterDropdown.filters then return end
        filterDropdown.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
    end

    browseOrders:HookScript("OnShow", function() C_Timer.After(0, applyFilter) end)
    C_Timer.After(0, applyFilter)
end

---------------------------------------------------------------------------
-- EVENT REGISTRATION
---------------------------------------------------------------------------

qolFrame:RegisterEvent("MERCHANT_SHOW")
qolFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
qolFrame:RegisterEvent("PARTY_INVITE_REQUEST")
qolFrame:RegisterEvent("QUEST_DETAIL")
qolFrame:RegisterEvent("QUEST_COMPLETE")
qolFrame:RegisterEvent("GOSSIP_SHOW")
qolFrame:RegisterEvent("GOSSIP_CLOSED")
qolFrame:RegisterEvent("LOOT_READY")
qolFrame:RegisterEvent("CHALLENGE_MODE_START")
qolFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
qolFrame:RegisterEvent("CHALLENGE_MODE_RESET")
qolFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
qolFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
qolFrame:RegisterEvent("ADDON_LOADED")
qolFrame:RegisterEvent("AUCTION_HOUSE_SHOW")

qolFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        OnMerchantShow()
    elseif event == "LFG_ROLE_CHECK_SHOW" then
        OnRoleCheckShow()
    elseif event == "PARTY_INVITE_REQUEST" then
        OnPartyInvite(...)
    elseif event == "QUEST_DETAIL" then
        OnQuestDetail()
    elseif event == "QUEST_COMPLETE" then
        OnQuestComplete()
    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "GOSSIP_CLOSED" then
        OnGossipClosed()
    elseif event == "LOOT_READY" then
        OnLootReady()
    elseif event == "CHALLENGE_MODE_START" then
        UpdateMythicPlusAutoLogging()
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        -- Active-state APIs can lag the completion/reset event slightly.
        ScheduleMythicPlusUpdate(5)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleMythicPlusUpdate(2)
        C_Timer.After(2, UpdateRaidAutoLogging)
        C_Timer.After(2, RefreshPopupBlocker)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UpdateMythicPlusAutoLogging()
        UpdateRaidAutoLogging()
    elseif event == "AUCTION_HOUSE_SHOW" then
        SetupAuctionHouseFilter()
        qolFrame:UnregisterEvent("AUCTION_HOUSE_SHOW")
    elseif event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            C_Timer.After(0, RefreshPopupBlocker)
            return
        end
        if loadedAddon == "Blizzard_ProfessionsCustomerOrders" then
            C_Timer.After(0.1, SetupCraftingOrderFilter)
        end
        if type(loadedAddon) == "string" and string.find(loadedAddon, "Blizzard_", 1, true) == 1 then
            C_Timer.After(0, RefreshPopupBlocker)
        end
    end
end)
