local addonName, ns = ...
local Helpers = ns.Helpers

local NUM_BAG_FRAMES = NUM_BAG_FRAMES or 4

local GetSettings = Helpers.CreateDBGetter("general")

local function CloseBags()
    local bags = ns.Bags
    local takeover = bags and bags.Takeover
    if takeover and takeover.IsActive and takeover.IsActive() then
        takeover.CloseForFrame()
    else
        CloseAllBags()
    end
end

-- Keep the reminder separate from the keystone insertion UI and its settings.
local reminderEvents = CreateFrame("Frame")
local reminder
local completionGeneration = 0
reminderEvents:RegisterEvent("CHALLENGE_MODE_COMPLETED")
reminderEvents:RegisterEvent("CHALLENGE_MODE_START")
reminderEvents:RegisterEvent("CHALLENGE_MODE_RESET")
reminderEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
reminderEvents:SetScript("OnEvent", function(_, event)
    completionGeneration = completionGeneration + 1
    if reminder then reminder:Hide() end
    if event ~= "CHALLENGE_MODE_COMPLETED" then return end

    local settings = GetSettings()
    if not settings or settings.keystoneRerollReminder == false then return end
    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    if not info or info.practiceRun or not info.level or info.level <= 0 then return end
    local completedLevel = info.level
    local generation = completionGeneration
    local attempts = 0
    -- Allow the owned keystone to refresh after completion before comparing it.
    local function CheckOwnedKeystone()
        if generation ~= completionGeneration then return end
        local currentSettings = GetSettings()
        if not currentSettings or currentSettings.keystoneRerollReminder == false then return end
        attempts = attempts + 1
        local ownedLevel = C_MythicPlus.GetOwnedKeystoneLevel()
        if not ownedLevel or ownedLevel <= 0 then
            if attempts < 5 then C_Timer.After(1, CheckOwnedKeystone) end
            return
        end
        if completedLevel < ownedLevel then return end

        if not reminder then
            reminder = CreateFrame("Frame", nil, UIParent)
            reminder:SetSize(400, 70)
            reminder:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
            reminder:SetFrameStrata("DIALOG")
            local text = reminder:CreateFontString(nil, "OVERLAY")
            text:SetAllPoints()
            text:SetFont(STANDARD_TEXT_FONT, 32, "OUTLINE")
            text:SetTextColor(1, 0.82, 0)
            text:SetText("Re-roll key?")
            reminder:SetScript("OnUpdate", function(self, elapsed)
                self.remaining = self.remaining - elapsed
                local activeSettings = GetSettings()
                if self.remaining <= 0 or not activeSettings or activeSettings.keystoneRerollReminder == false then self:Hide() end
            end)
        end
        reminder.remaining = 15
        reminder:Show()
    end
    C_Timer.After(1, CheckOwnedKeystone)
end)

local function FindKeystoneInBags()
    for bag = 0, NUM_BAG_FRAMES do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local itemClass, itemSubClass = select(12, C_Item.GetItemInfo(itemID))
                if itemClass == Enum.ItemClass.Reagent and itemSubClass == Enum.ItemReagentSubclass.Keystone then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

local function InsertKeystone()
    local settings = GetSettings()
    if not settings or not settings.autoInsertKey then return end

    local bag, slot = FindKeystoneInBags()
    if not bag then return end

    C_Container.PickupContainerItem(bag, slot)
    if C_Cursor.GetCursorItem() then
        C_ChallengeMode.SlotKeystone()
        if settings.closeBagsOnKeystoneInsert then
            CloseBags()
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == "Blizzard_ChallengesUI" then
        if ChallengesKeystoneFrame then
            ChallengesKeystoneFrame:HookScript("OnShow", function()
                C_Timer.After(0, InsertKeystone)
            end)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

if C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
    if ChallengesKeystoneFrame then
        ChallengesKeystoneFrame:HookScript("OnShow", function()
            C_Timer.After(0, InsertKeystone)
        end)
    end
    frame:UnregisterEvent("ADDON_LOADED")
end
