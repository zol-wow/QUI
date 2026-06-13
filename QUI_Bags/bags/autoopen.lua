---------------------------------------------------------------------------
-- Bags auto-open: per-interaction open/close policy.
-- Two surfaces: (1) PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE events
-- (wired by bags.lua while takeover is active) for interactions that don't
-- open bags themselves; (2) ShouldOpenFor(frame), consulted by the
-- takeover's OpenAllBags/OpenAllBagsMatchingContext hooks and its internal
-- OpenForFrame callers (bank/guild) for programmatic opens (merchant etc.).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local AutoOpen = {}
Bags.AutoOpen = AutoOpen

-- Enum.PlayerInteractionType → settings key (built lazily: Enum may load late)
local typeToKey
local function TypeToKey()
    if typeToKey then return typeToKey end
    local T = Enum and Enum.PlayerInteractionType
    if not T then return {} end -- Enum not loaded yet: don't cache sentinel-keyed table
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

-- "socket" rides the programmatic-open path only (ItemSocketingFrame has no
-- PlayerInteractionType); if that frame never calls OpenAllBags the toggle is
-- inert — revisit in the QoL phase if socket auto-open matters.
-- programmatic opener frame name → settings key
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

local openedByType = nil -- which interaction type opened the window

--- Event sink (wired by bags.lua): interactionType, shown
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

--- Policy for programmatic OpenAllBags(frame): unknown frames default open.
function AutoOpen.ShouldOpenFor(frame)
    if not frame or not frame.GetName then return true end
    local key = FRAME_TO_KEY[frame:GetName() or ""]
    if not key then return true end
    return IsKeyEnabled(key)
end
