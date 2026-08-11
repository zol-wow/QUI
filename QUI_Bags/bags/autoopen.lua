local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local AutoOpen = {}
Bags.AutoOpen = AutoOpen

local typeToKey
local function TypeToKey()
    if typeToKey then return typeToKey end
    local T = Enum and Enum.PlayerInteractionType
    if not T then return {} end
    typeToKey = {
        [T.Merchant or -1] = "merchant",
        [T.MailInfo or -2] = "mail",
        [T.Auctioneer or -3] = "auctionHouse",
        [T.TradePartner or -4] = "trade",
        [T.ScrappingMachine or -5] = "scrappingMachine",
        [T.ItemUpgrade or -6] = "itemUpgrade",
    }
    return typeToKey
end

local FRAME_TO_KEY = {
    MerchantFrame = "merchant",
    MailFrame = "mail",
    AuctionHouseFrame = "auctionHouse",
    TradeFrame = "trade",
    ScrappingMachineFrame = "scrappingMachine",
    ItemUpgradeFrame = "itemUpgrade",
    ItemSocketingFrame = "socket",
    QUI_BankWindow = "bank",
    QUI_GuildBankWindow = "guildBank",
}

local function IsKeyEnabled(key)
    local s = GetSettings()
    local map = s and s.behavior and s.behavior.autoOpen
    if not map then return true end
    local v = map[key]
    if v == nil then return true end
    return v and true or false
end

local openedByType = nil

function AutoOpen.OnInteraction(interactionType, shown)
    local key = TypeToKey()[interactionType]
    if not key then return end
    if shown then
        if IsKeyEnabled(key) and not Bags.BagWindow.IsShown() then
            openedByType = interactionType
            Bags.BagWindow.Show()
        end
    else
        if openedByType == interactionType then
            openedByType = nil
            Bags.BagWindow.Hide()
        end
    end
end

function AutoOpen.ShouldOpenFor(frame)
    if not frame or not frame.GetName then return true end
    local key = FRAME_TO_KEY[frame:GetName() or ""]
    if not key then return true end
    return IsKeyEnabled(key)
end
