local addonName, ns = ...
local Helpers = ns.Helpers

-- Fallback for NUM_BAG_FRAMES if not defined
local NUM_BAG_FRAMES = NUM_BAG_FRAMES or 4

---------------------------------------------------------------------------
-- AUTO-INSERT KEYSTONE
---------------------------------------------------------------------------

-- Get settings from database
local function GetSettings()
    return Helpers.GetModuleDB("general")
end

-- Find keystone in player's bags
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

-- Insert keystone into M+ UI
local function InsertKeystone()
    local settings = GetSettings()
    if not settings or not settings.autoInsertKey then return end

    local bag, slot = FindKeystoneInBags()
    if not bag then return end

    C_Container.PickupContainerItem(bag, slot)
    if C_Cursor.GetCursorItem() then
        C_ChallengeMode.SlotKeystone()
    end
end

-- Hook when Blizzard's M+ UI loads
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == "Blizzard_ChallengesUI" then
        if ChallengesKeystoneFrame then
            ChallengesKeystoneFrame:HookScript("OnShow", InsertKeystone)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
