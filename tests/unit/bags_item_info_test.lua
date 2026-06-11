-- tests/unit/bags_item_info_test.lua
-- Run: lua tests/unit/bags_item_info_test.lua
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

local instantCalls = 0
_G.C_Item.GetItemInfoInstant = function(itemID)
    instantCalls = instantCalls + 1
    if itemID == 6948 then return 6948, "Miscellaneous", "Other", "", 134414, 15, 0 end
    return nil
end
local requested = {}
_G.C_Item.RequestLoadItemDataByID = function(itemID) requested[#requested + 1] = itemID end

local ns = loader.LoadAll(nil, "item_info.lua")
local ItemInfo = ns.Bags.ItemInfo

-- Test 1: derived info is fetched once then session-cached
local d1 = ItemInfo.GetDerived(6948)
assert(d1 and d1.classID == 15 and d1.subClassID == 0 and d1.icon == 134414, "derived fields wrong")
local d2 = ItemInfo.GetDerived(6948)
assert(d2 == d1, "expected cached table identity")
assert(instantCalls == 1, "instant info should be called once, got " .. instantCalls)

-- Test 2: unknown item returns nil and is not cached
assert(ItemInfo.GetDerived(999999) == nil, "unknown item should be nil")
assert(ItemInfo.GetDerived(nil) == nil, "nil itemID should be nil")

-- Test 3: RequestLoad coalesces concurrent requests for the same item
local results = {}
ItemInfo.RequestLoad(123, function(id, ok) results[#results + 1] = { id, ok, 1 } end)
ItemInfo.RequestLoad(123, function(id, ok) results[#results + 1] = { id, ok, 2 } end)
assert(#requested == 1 and requested[1] == 123, "expected exactly one client load request")
ItemInfo.OnItemDataLoadResult(123, true)
assert(#results == 2 and results[1][2] == true and results[2][3] == 2, "callbacks not delivered")
-- a second result for the same item is a no-op (no pending list)
ItemInfo.OnItemDataLoadResult(123, true)
assert(#results == 2, "stale load result re-fired callbacks")

-- Test 4: callback errors are isolated
ItemInfo.RequestLoad(456, function() error("boom") end)
local survived = false
ItemInfo.RequestLoad(456, function() survived = true end)
local ok = pcall(ItemInfo.OnItemDataLoadResult, 456, true)
assert(ok and survived, "callback error broke delivery")

print("OK: bags_item_info_test")
