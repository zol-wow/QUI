-- tests/unit/bags_scan_bags_test.lua
-- Run: lua tests/unit/bags_scan_bags_test.lua
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

local contents = {} -- [bagID] = { [slot] = ContainerItemInfo-like table }
local sizes = { [0] = 2, [1] = 1, [2] = 0, [3] = 0, [4] = 0, [5] = 1 }
_G.C_Container.GetContainerNumSlots = function(bagID) return sizes[bagID] or 0 end
_G.C_Container.GetContainerItemInfo = function(bagID, slot)
    return contents[bagID] and contents[bagID][slot] or nil
end
local function fakeItem(itemID, count, quality)
    return { itemID = itemID, stackCount = count, hyperlink = "|Hitem:" .. itemID .. "|h[x]|h",
             quality = quality, iconFileID = 1, isBound = false }
end

local ns = loader.LoadAll(nil, "scan_bags.lua")
ns.Bags.RequestDrain = function() end -- glue normally provided by bags.lua
local Store, ScanBags, Bus = ns.Bags.Store, ns.Bags.ScanBags, ns.Bags.Bus

_G.QUI_StorageDB = nil
Store.Initialize()
Store.EnsureCurrentCharacter()

local published = {}
Bus.Subscribe("BagsChanged", function(_, charKey, changed)
    published[#published + 1] = { charKey = charKey, changed = changed }
end)

-- Test 1: nothing dirty → drain is a no-op
assert(ScanBags.Drain() == false, "drain with nothing dirty should return false")
assert(#published == 0, "no event expected")

-- Test 2: full scan writes all player bags and publishes once
contents[0] = { [1] = fakeItem(6948, 1, 1), [2] = fakeItem(2589, 20, 1) }
contents[5] = { [1] = fakeItem(190396, 5, 2) }
ScanBags.MarkAllDirty()
assert(ScanBags.Drain() == true, "drain should report changes")
local rec = Store.GetCurrentCharacter()
assert(rec.bags[0].size == 2 and rec.bags[0].slots[1].itemID == 6948, "bag 0 not written")
assert(rec.bags[5].slots[1].itemID == 190396, "reagent bag not written")
assert(rec.bags[2].size == 0, "empty bag should still be recorded")
assert(#published == 1 and published[1].charKey == "Testchar-TestRealm", "publish wrong")
assert(#published[1].changed == 6, "expected all 6 player bags in changed list")

-- Test 3: dirty-marking only rescans marked bags
contents[0][1] = fakeItem(777, 1, 3)
contents[5][1] = fakeItem(888, 1, 3)
ScanBags.MarkDirty(0)
ScanBags.Drain()
rec = Store.GetCurrentCharacter()
assert(rec.bags[0].slots[1].itemID == 777, "marked bag not rescanned")
assert(rec.bags[5].slots[1].itemID == 190396, "unmarked bag must not be rescanned")
assert(#published == 2 and #published[2].changed == 1, "second publish should carry 1 bag")

-- Test 4: non-player bag IDs are ignored by MarkDirty
ScanBags.MarkDirty(6)   -- character bank tab — the bank scanner's job
ScanBags.MarkDirty(-1)
assert(ScanBags.Drain() == false, "bank/invalid IDs must not dirty the bag scanner")

-- Test 5: failed async item loads must NOT re-mark the bag (no rescan loop);
-- successful loads must.
local drainRequests = 0
ns.Bags.RequestDrain = function() drainRequests = drainRequests + 1 end
contents[1] = { [1] = fakeItem(424242, 1, nil) } -- quality nil → pending load
ScanBags.MarkDirty(1)
ScanBags.Drain()
ns.Bags.ItemInfo.OnItemDataLoadResult(424242, false)
assert(drainRequests == 0, "failed load must not request a drain")
assert(ScanBags.Drain() == false, "failed load must not re-mark the bag")

contents[2] = { } -- keep bag 2 empty
contents[1][1] = fakeItem(555555, 1, nil) -- new pending item in bag 1
ScanBags.MarkDirty(1)
ScanBags.Drain()
contents[1][1] = fakeItem(555555, 1, 3) -- item data arrives
ns.Bags.ItemInfo.OnItemDataLoadResult(555555, true)
assert(drainRequests == 1, "successful load must request a drain")
assert(ScanBags.Drain() == true, "successful load must re-mark the bag")
assert(Store.GetCurrentCharacter().bags[1].slots[1].quality == 3,
       "rescan should pick up the loaded quality")

-- Test 6: synchronous load-result during drain must not lose the re-mark
-- (ITEM_DATA_LOAD_RESULT is a SynchronousEvent: client-cached items can
-- answer inside ReadContainer, i.e. inside Drain itself)
local realRequest = _G.C_Item.RequestLoadItemDataByID
_G.C_Item.RequestLoadItemDataByID = function(itemID)
    ns.Bags.ItemInfo.OnItemDataLoadResult(itemID, true)
end
sizes[3] = 1
contents[3] = { [1] = fakeItem(606060, 1, nil) } -- nil quality → pending → inline result
ScanBags.MarkDirty(3)
assert(ScanBags.Drain() == true, "drain should write bag 3")
contents[3][1] = fakeItem(606060, 1, 4) -- data now resolved
assert(ScanBags.Drain() == true, "synchronously re-marked bag must survive the drain cleanup")
assert(Store.GetCurrentCharacter().bags[3].slots[1].quality == 4,
       "second pass should pick up the loaded quality")
_G.C_Item.RequestLoadItemDataByID = realRequest

-- Test 7: drain with no character record preserves dirty marks
Store.DeleteCharacter("Testchar-TestRealm")
ScanBags.MarkDirty(0)
assert(ScanBags.Drain() == false, "drain without a record must not write")
Store.EnsureCurrentCharacter()
assert(ScanBags.Drain() == true, "marks must survive a record-less drain")

print("OK: bags_scan_bags_test")
