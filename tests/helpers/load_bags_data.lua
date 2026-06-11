-- Loads the production bags data-layer files into a fresh ns for unit tests.
-- Run tests from the repo root. Installs the minimal WoW surface the data
-- layer touches; individual tests override stubs as needed BEFORE LoadAll.
local M = {}

M.DATA_FILES = {
    "QUI_Bags/bags/data/bus.lua",
    "QUI_Bags/bags/data/store.lua",
    "QUI_Bags/bags/data/item_info.lua",
    "QUI_Bags/bags/data/scan_common.lua",
    "QUI_Bags/bags/data/scan_bags.lua",
    "QUI_Bags/bags/data/scan_bank.lua",
    "QUI_Bags/bags/data/scan_guild.lua",
    "QUI_Bags/bags/data/scan_mail.lua",
    "QUI_Bags/bags/data/scan_equipped.lua",
    "QUI_Bags/bags/data/scan_currencies.lua",
    "QUI_Bags/bags/data/scan_auctions.lua",
    "QUI_Bags/bags/data/summaries.lua",
}

function M.InstallBaseStubs()
    _G.geterrorhandler = _G.geterrorhandler or function() return function(err) error(err, 0) end end
    _G.time = _G.time or os.time
    _G.UnitFullName = _G.UnitFullName or function() return "Testchar", "TestRealm" end
    _G.GetRealmName = _G.GetRealmName or function() return "TestRealm" end
    _G.UnitClass = _G.UnitClass or function() return "Mage", "MAGE" end
    _G.UnitRace = _G.UnitRace or function() return "Gnome", "Gnome" end
    _G.UnitFactionGroup = _G.UnitFactionGroup or function() return "Alliance" end
    _G.GetGuildInfo = _G.GetGuildInfo or function() return nil end
    _G.GetMoney = _G.GetMoney or function() return 0 end
    _G.Enum = _G.Enum or {}
    _G.Enum.BankType = _G.Enum.BankType or { Character = 0, Guild = 1, Account = 2 }
    _G.C_Container = _G.C_Container or {}
    _G.C_Bank = _G.C_Bank or {}
    _G.C_Item = _G.C_Item or {}
    _G.C_Item.RequestLoadItemDataByID = _G.C_Item.RequestLoadItemDataByID or function() end
    _G.C_Item.GetItemInfoInstant = _G.C_Item.GetItemInfoInstant or function() return nil end
    _G.C_Item.GetItemInfo = _G.C_Item.GetItemInfo or function() return nil end
    _G.C_Item.GetDetailedItemLevelInfo = _G.C_Item.GetDetailedItemLevelInfo or function() return nil end
    -- Phase-6 breadth scanner surfaces (no-op defaults; tests override).
    -- Shapes mirror the vendored docs/FrameXML exactly:
    --   GetInboxNumItems() → numItems, totalItems   (Blizzard_MailFrame/MailFrame.lua:180)
    --   GetInboxHeaderInfo/GetInboxItem/GetInboxItemLink → legacy mail globals
    --   GetInventoryItem*("player", slot)           → legacy inventory globals
    --   C_CurrencyInfo list/info APIs MayReturnNothing (CurrencyInfoDocumentation)
    --   C_AuctionHouse.GetOwnedAuctionInfo Nilable   (AuctionHouseDocumentation)
    _G.ATTACHMENTS_MAX_RECEIVE = _G.ATTACHMENTS_MAX_RECEIVE or 16
    _G.GetInboxNumItems = _G.GetInboxNumItems or function() return 0, 0 end
    _G.GetInboxHeaderInfo = _G.GetInboxHeaderInfo or function() return nil end
    _G.GetInboxItem = _G.GetInboxItem or function() return nil end
    _G.GetInboxItemLink = _G.GetInboxItemLink or function() return nil end
    _G.GetInventoryItemID = _G.GetInventoryItemID or function() return nil end
    _G.GetInventoryItemLink = _G.GetInventoryItemLink or function() return nil end
    _G.GetInventoryItemTexture = _G.GetInventoryItemTexture or function() return nil end
    _G.GetInventoryItemQuality = _G.GetInventoryItemQuality or function() return nil end
    _G.C_CurrencyInfo = _G.C_CurrencyInfo or {}
    _G.C_CurrencyInfo.GetCurrencyListSize = _G.C_CurrencyInfo.GetCurrencyListSize or function() return 0 end
    _G.C_CurrencyInfo.GetCurrencyListInfo = _G.C_CurrencyInfo.GetCurrencyListInfo or function() return nil end
    _G.C_CurrencyInfo.GetCurrencyInfo = _G.C_CurrencyInfo.GetCurrencyInfo or function() return nil end
    _G.C_AuctionHouse = _G.C_AuctionHouse or {}
    _G.C_AuctionHouse.GetNumOwnedAuctions = _G.C_AuctionHouse.GetNumOwnedAuctions or function() return 0 end
    _G.C_AuctionHouse.GetOwnedAuctionInfo = _G.C_AuctionHouse.GetOwnedAuctionInfo or function() return nil end
    _G.Enum.AuctionStatus = _G.Enum.AuctionStatus or { Active = 0, Sold = 1 }
end

-- Loads every data file (they each guard with `ns.Bags = ns.Bags or {}`).
-- Pass `upto` (a filename suffix) to stop after a given file when testing a
-- file that must not yet see its later siblings.
function M.LoadAll(ns, upto)
    ns = ns or {}
    M.InstallBaseStubs()
    local matched = false
    for _, path in ipairs(M.DATA_FILES) do
        local chunk, err = loadfile(path)
        assert(chunk, tostring(err))
        chunk("QUI", ns)
        if upto and path:sub(-#upto) == upto then matched = true; break end
    end
    assert(not upto or matched, "LoadAll: upto suffix matched no DATA_FILES entry: " .. tostring(upto))
    return ns
end

return M
