-- luacheck: read globals C_AuctionHouse
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanAuctions = {}
Storage.ScanAuctions = ScanAuctions

local atAuctionHouse = false
local hasDirty = false

function ScanAuctions.OnAuctionHouseShow()
    atAuctionHouse = true
end

function ScanAuctions.OnAuctionHouseClosed()
    atAuctionHouse = false
end

function ScanAuctions.MarkDirty()
    hasDirty = true
end

function ScanAuctions.Drain()
    if not hasDirty then return false end
    if not atAuctionHouse then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    hasDirty = false
    local soldStatus = (Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1
    local list = {}
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local auction = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if auction and auction.status ~= soldStatus
                and auction.itemKey and auction.itemKey.itemID then
            local itemID = auction.itemKey.itemID
            local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
            list[#list + 1] = {
                itemID = itemID,
                count = auction.quantity,
                link = auction.itemLink,
                icon = icon,
            }
        end
    end
    rec.auctions = { size = #list, slots = list }
    Storage.Bus.Publish("AuctionsChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
