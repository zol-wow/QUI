-- tests/unit/bags_scan_auctions_test.lua
-- Run: lua tests/unit/bags_scan_auctions_test.lua
-- Owned-auction scanner: C_AuctionHouse.GetNumOwnedAuctions +
-- GetOwnedAuctionInfo(i) (OwnedAuctionInfo struct, Nilable return), session
-- keyed by AUCTION_HOUSE_SHOW/CLOSED. Store shape:
-- rec.auctions = { size = n, slots = list } (list-as-slots for IndexInto).
-- luacheck: globals QUI_StorageDB
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- C_AuctionHouse stubs --------------------------------------------------
-- OwnedAuctionInfo struct (AuctionHouseDocumentation): auctionID, itemKey
-- {itemID, itemLevel, itemSuffix, battlePetSpeciesID}, itemLink (nilable),
-- status (Enum.AuctionStatus: Active=0, Sold=1), quantity, ...
local owned = {}
_G.C_AuctionHouse.GetNumOwnedAuctions = function() return #owned end
_G.C_AuctionHouse.GetOwnedAuctionInfo = function(i) return owned[i] end

-- C_Item.GetItemInfoInstant (ItemDocumentation, MayReturnNothing): itemID,
-- itemType, itemSubType, itemEquipLoc, icon, classID, subClassID
local icons = { [6948] = 134414, [2589] = 132889 }
_G.C_Item.GetItemInfoInstant = function(itemID)
    local icon = icons[itemID]
    if not icon then return nil end
    return itemID, "Armor", "Cloth", "INVTYPE_CHEST", icon, 4, 1
end

local ns = loader.LoadAll(nil, "scan_auctions.lua")
ns.Bags.RequestDrain = function() end
local Store, ScanAuctions, Bus = ns.Bags.Store, ns.Bags.ScanAuctions, ns.Bags.Bus

_G.QUI_StorageDB = nil
Store.Initialize()
Store.EnsureCurrentCharacter()
local KEY = "Testchar-TestRealm"

local events = {}
Bus.Subscribe("AuctionsChanged", function(_, charKey) events[#events + 1] = charKey end)

-- Test 1: dirty drain without an AH session must no-op (owned-auction data
-- only streams at the auction house; a wipe here would clobber the cache)
ScanAuctions.MarkDirty()
assert(ScanAuctions.Drain() == false, "drain away from the AH must no-op")
assert(#events == 0, "no-session drain must not publish")

-- Test 2: session drain writes the list; sold auctions are skipped (the
-- buyer has the item; proceeds arrive via mail)
owned = {
    { auctionID = 1, itemKey = { itemID = 6948, itemLevel = 0, itemSuffix = 0,
        battlePetSpeciesID = 0 },
      itemLink = "|Hitem:6948::::::::70:::::|h[Widget]|h",
      status = 0, quantity = 2, buyoutAmount = 100000 },
    { auctionID = 2, itemKey = { itemID = 4242, itemLevel = 0, itemSuffix = 0,
        battlePetSpeciesID = 0 },
      itemLink = "|Hitem:4242::::::::70:::::|h[Gone]|h",
      status = 1, quantity = 1 }, -- Sold
    { auctionID = 3, itemKey = { itemID = 2589, itemLevel = 0, itemSuffix = 0,
        battlePetSpeciesID = 0 },
      itemLink = nil, -- commodities can carry no link
      status = 0, quantity = 200 },
}
ScanAuctions.OnAuctionHouseShow()
ScanAuctions.MarkDirty()
assert(ScanAuctions.Drain() == true, "session drain must write")
local rec = Store.GetCurrentCharacter()
assert(rec.auctions.size == 2 and #rec.auctions.slots == 2,
       "two active auctions expected, got " .. tostring(rec.auctions.size))
local e1, e2 = rec.auctions.slots[1], rec.auctions.slots[2]
assert(e1.itemID == 6948 and e1.count == 2 and e1.icon == 134414
       and e1.link == "|Hitem:6948::::::::70:::::|h[Widget]|h", "first entry wrong")
assert(e2.itemID == 2589 and e2.count == 200 and e2.link == nil and e2.icon == 132889,
       "linkless commodity entry wrong")
for _, e in ipairs(rec.auctions.slots) do
    assert(e.itemID ~= 4242, "sold auctions must not persist")
end
assert(#events == 1 and events[1] == KEY, "exactly one AuctionsChanged(charKey) per drain")
assert(ScanAuctions.Drain() == false, "clean drain must no-op")

-- Test 3: entry-shape minimalism guard — subset of the persisted entry keys
-- (quality/isBound unavailable from OwnedAuctionInfo; count-driven location)
local allowed = { itemID = true, count = true, link = true, icon = true }
for i, e in ipairs(rec.auctions.slots) do
    for k in pairs(e) do
        assert(allowed[k], "unexpected persisted key in auction entry " .. i .. ": " .. tostring(k))
    end
end

-- Test 4: Nilable row + icon-less item tolerated
owned = {
    nil, -- GetOwnedAuctionInfo is Nilable
    { auctionID = 4, itemKey = { itemID = 999999, itemLevel = 0, itemSuffix = 0,
        battlePetSpeciesID = 0 },
      status = 0, quantity = 1 }, -- GetItemInfoInstant returns nothing for this ID
}
function _G.C_AuctionHouse.GetNumOwnedAuctions() return 2 end
function _G.C_AuctionHouse.GetOwnedAuctionInfo(i) return owned[i] end
ScanAuctions.MarkDirty()
assert(ScanAuctions.Drain() == true, "nil rows must not abort the drain")
rec = Store.GetCurrentCharacter()
assert(rec.auctions.size == 1 and rec.auctions.slots[1].itemID == 999999
       and rec.auctions.slots[1].icon == nil, "icon-less entry must persist with nil icon")

-- Test 5: all auctions collected/expired at the AH → genuine wipe + publish
owned = {}
function _G.C_AuctionHouse.GetNumOwnedAuctions() return 0 end
ScanAuctions.MarkDirty()
assert(ScanAuctions.Drain() == true, "empty owned list at the AH must write")
rec = Store.GetCurrentCharacter()
assert(rec.auctions.size == 0 and next(rec.auctions.slots) == nil, "cache must wipe")
assert(#events == 3, "empty-list drain must publish")

-- Test 6: OnAuctionHouseClosed ends the session
ScanAuctions.OnAuctionHouseClosed()
ScanAuctions.MarkDirty()
assert(ScanAuctions.Drain() == false, "drain after close must no-op even when dirty")
assert(#events == 3, "closed-session drain must not publish")

-- Test 7: drain with no character record preserves the dirty mark
ScanAuctions.OnAuctionHouseShow()
Store.DeleteCharacter(KEY)
assert(ScanAuctions.Drain() == false, "drain without a record must not write")
Store.EnsureCurrentCharacter()
assert(ScanAuctions.Drain() == true, "mark must survive a record-less drain")

print("OK: bags_scan_auctions_test")
