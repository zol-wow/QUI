---------------------------------------------------------------------------
-- Core storage: owned-auction scanner.
-- Owned-auction data is server-resident and only streams while the auction
-- house is open: C_AuctionHouse.GetNumOwnedAuctions +
-- GetOwnedAuctionInfo(i) (Nilable; OwnedAuctionInfo struct — itemKey.itemID,
-- quantity, itemLink [nilable: commodities], status, verified against
-- AuctionHouseDocumentation). The session is keyed by
-- AUCTION_HOUSE_SHOW/CLOSED; OWNED_AUCTIONS_UPDATED is payload-free, so the
-- rescan unit is the whole owned list. The scanner deliberately issues no
-- QueryOwnedAuctions pump of its own — AH queries ride a throttled message
-- system the Blizzard UI is already driving at open, and a competing query
-- risks dropped messages; the cache updates whenever the owned list arrives
-- naturally (posting, cancelling, or viewing owned auctions).
-- Sold auctions are skipped: the buyer has the item; proceeds arrive via
-- mail. Quality/isBound aren't available from OwnedAuctionInfo and stay
-- unset (count-driven location); icon comes from C_Item.GetItemInfoInstant
-- (MayReturnNothing → nil tolerated).
-- Store shape: rec.auctions = { size = n, slots = <dense entry list> } —
-- list-as-slots so summaries' IndexInto walks it unchanged.
---------------------------------------------------------------------------
-- luacheck: read globals C_AuctionHouse
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanAuctions = {}
Storage.ScanAuctions = ScanAuctions

local atAuctionHouse = false -- session: true while the AH is open
local hasDirty = false

function ScanAuctions.OnAuctionHouseShow()
    atAuctionHouse = true
end

--- AUCTION_HOUSE_CLOSED ends the session; the collector always clears the
--- flag — a stale at-AH flag would wipe the cache (cf. scan_mail).
function ScanAuctions.OnAuctionHouseClosed()
    atAuctionHouse = false
end

--- OWNED_AUCTIONS_UPDATED carries no payload → whole-list rescan.
function ScanAuctions.MarkDirty()
    hasDirty = true
end

--- Re-read the owned-auction list; publishes AuctionsChanged(charKey)
--- (whole-record event — no changed array; see bus.lua). Returns true when
--- written. No-op unless dirty AND an AH session is open AND the character
--- record exists.
function ScanAuctions.Drain()
    if not hasDirty then return false end
    if not atAuctionHouse then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end -- transient: dirty mark preserved
    hasDirty = false
    local soldStatus = (Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1
    local list = {}
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
        local auction = C_AuctionHouse.GetOwnedAuctionInfo(i) -- Nilable
        if auction and auction.status ~= soldStatus
                and auction.itemKey and auction.itemKey.itemID then
            local itemID = auction.itemKey.itemID
            local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID) -- MayReturnNothing
            list[#list + 1] = {
                itemID = itemID,
                count = auction.quantity,
                link = auction.itemLink, -- nilable (commodities)
                icon = icon,
            }
        end
    end
    -- A genuinely empty owned list at the AH must overwrite (everything
    -- sold/expired/cancelled) and still publish.
    rec.auctions = { size = #list, slots = list }
    Storage.Bus.Publish("AuctionsChanged", Storage.Store.GetCurrentCharacterKey())
    return true
end
