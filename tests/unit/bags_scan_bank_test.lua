-- tests/unit/bags_scan_bank_test.lua
-- Run: lua tests/unit/bags_scan_bank_test.lua
-- 12.0 bag-index space: character bank tabs 6–11, warband (account) tabs 12–16.
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

local sizes = { [6] = 2, [7] = 1, [12] = 1 }
local contents = {
    [6] = { [1] = { itemID = 111, stackCount = 1, hyperlink = "|Hitem:111|h[a]|h", quality = 2, iconFileID = 1, isBound = true } },
    [12] = { [1] = { itemID = 333, stackCount = 4, hyperlink = "|Hitem:333|h[c]|h", quality = 3, iconFileID = 3, isBound = false } },
}
_G.C_Container.GetContainerNumSlots = function(bagID) return sizes[bagID] or 0 end
_G.C_Container.GetContainerItemInfo = function(bagID, slot)
    return contents[bagID] and contents[bagID][slot] or nil
end

local accountLocked = nil -- nil = unlocked (BankLockedReason semantics)
_G.C_Bank.FetchBankLockedReason = function() return accountLocked end
_G.C_Bank.FetchPurchasedBankTabData = function(bankType)
    if bankType == Enum.BankType.Character then
        return {
            { ID = 6, bankType = bankType, name = "Tab One", icon = 10, depositFlags = 2 },
            { ID = 7, bankType = bankType, name = "Tab Two", icon = 11, depositFlags = 0 },
        }
    end
    if bankType == Enum.BankType.Account then
        return { { ID = 12, bankType = bankType, name = "WB One", icon = 20, depositFlags = 0 } }
    end
end
_G.C_Bank.FetchDepositedMoney = function() return 123456 end

local ns = loader.LoadAll(nil, "scan_bank.lua")
ns.Bags.RequestDrain = function() end
local Store, ScanBank, Bus = ns.Bags.Store, ns.Bags.ScanBank, ns.Bags.Bus

_G.QUI_StorageDB = nil
Store.Initialize()
Store.EnsureCurrentCharacter()

local bankEvents, wbEvents = {}, {}
Bus.Subscribe("BankChanged", function(_, charKey, tabs) bankEvents[#bankEvents + 1] = tabs end)
Bus.Subscribe("WarbandChanged", function(_, tabs) wbEvents[#wbEvents + 1] = tabs end)

-- Test 1: ID classification
assert(ScanBank.IsCharTab(6) and ScanBank.IsCharTab(11), "char tab range wrong")
assert(ScanBank.IsWarbandTab(12) and ScanBank.IsWarbandTab(16), "warband tab range wrong")
assert(not ScanBank.IsCharTab(5) and not ScanBank.IsWarbandTab(17), "range edges wrong")

-- Test 2: metadata refresh + full scan writes tabs with metadata overlay
ScanBank.RefreshTabMetadata()
ScanBank.MarkAllDirty()
assert(ScanBank.Drain() == true, "drain should write")
local rec = Store.GetCurrentCharacter()
assert(rec.bankTabs[6].name == "Tab One" and rec.bankTabs[6].depositFlags == 2, "char tab metadata missing")
assert(rec.bankTabs[6].slots[1].itemID == 111, "char tab contents missing")
assert(rec.bankTabs[7].size == 1 and rec.bankTabs[7].name == "Tab Two", "second char tab missing")
local wb = Store.GetWarband()
assert(wb.tabs[12].name == "WB One" and wb.tabs[12].slots[1].itemID == 333, "warband tab missing")
assert(wb.money == 123456, "warband money not captured on metadata refresh")
assert(#bankEvents == 1 and #wbEvents == 1, "expected one event per surface")

-- Test 3: per-tab dirty only rescans that tab
contents[6][1] = { itemID = 999, stackCount = 1, hyperlink = "|Hitem:999|h[z]|h", quality = 4, iconFileID = 9, isBound = false }
contents[12][1] = { itemID = 555, stackCount = 1, hyperlink = "|Hitem:555|h[w]|h", quality = 4, iconFileID = 9, isBound = false }
ScanBank.MarkDirty(6)
ScanBank.Drain()
rec = Store.GetCurrentCharacter()
assert(rec.bankTabs[6].slots[1].itemID == 999, "dirty char tab not rescanned")
assert(Store.GetWarband().tabs[12].slots[1].itemID == 333, "clean warband tab must not be rescanned")
assert(#bankEvents == 2 and #wbEvents == 1, "event routing wrong")

-- Test 4: locked account bank → warband metadata/scan skipped, char bank unaffected
accountLocked = 1 -- any non-nil BankLockedReason
ScanBank.RefreshTabMetadata()
ScanBank.MarkAllDirty()
ScanBank.Drain()
assert(Store.GetWarband().tabs[12].slots[1].itemID == 333, "locked warband bank must not be rescanned")
assert(Store.GetCurrentCharacter().bankTabs[6] ~= nil, "char bank must still scan when account bank locked")

-- Test 5: failed async loads must not re-mark (no rescan loop); successful must
accountLocked = nil
ScanBank.RefreshTabMetadata()
local drainRequests = 0
ns.Bags.RequestDrain = function() drainRequests = drainRequests + 1 end
contents[7] = { [1] = { itemID = 707070, stackCount = 1, hyperlink = "|Hitem:707070|h[p]|h", quality = nil, iconFileID = 2, isBound = false } }
ScanBank.MarkDirty(7)
ScanBank.Drain()
ns.Bags.ItemInfo.OnItemDataLoadResult(707070, false)
assert(drainRequests == 0, "failed load must not request a drain")
assert(ScanBank.Drain() == false, "failed load must not re-mark the tab")
-- a NEW pending round: re-mark manually and let the success path run
contents[7][1] = { itemID = 717171, stackCount = 1, hyperlink = "|Hitem:717171|h[q]|h", quality = nil, iconFileID = 2, isBound = false }
ScanBank.MarkDirty(7)
ScanBank.Drain()
contents[7][1].quality = 2
ns.Bags.ItemInfo.OnItemDataLoadResult(717171, true)
assert(drainRequests == 1, "successful load must request a drain")
assert(ScanBank.Drain() == true, "successful load must re-mark the tab")
assert(Store.GetCurrentCharacter().bankTabs[7].slots[1].quality == 2, "rescan should pick up quality")

-- Test 6: synchronous load-result during drain must not lose the re-mark
local realRequest = _G.C_Item.RequestLoadItemDataByID
_G.C_Item.RequestLoadItemDataByID = function(itemID)
    ns.Bags.ItemInfo.OnItemDataLoadResult(itemID, true)
end
contents[7] = { [1] = { itemID = 808080, stackCount = 1, hyperlink = "|Hitem:808080|h[r]|h", quality = nil, iconFileID = 2, isBound = false } }
ScanBank.MarkDirty(7)
assert(ScanBank.Drain() == true, "drain should write tab 7")
contents[7][1].quality = 3
assert(ScanBank.Drain() == true, "synchronously re-marked tab must survive the drain cleanup")
assert(Store.GetCurrentCharacter().bankTabs[7].slots[1].quality == 3, "second pass picks up quality")
_G.C_Item.RequestLoadItemDataByID = realRequest

-- Test 7: away-from-bank read (size 0) must not clobber a cached tab
sizes[6] = 0 -- bank closed: container unreadable
ScanBank.MarkDirty(6)
assert(ScanBank.Drain() == false, "unreadable tab must not count as written")
assert(Store.GetCurrentCharacter().bankTabs[6].slots[1] ~= nil, "cached tab contents must survive")
sizes[6] = 2 -- bank open again

-- Test 8: locked warband MarkDirty is a no-op even for known tabs
accountLocked = 1
ScanBank.RefreshTabMetadata()
ScanBank.MarkDirty(12)
assert(ScanBank.Drain() == false, "locked warband mark must be dropped")
accountLocked = nil

print("OK: bags_scan_bank_test")
