-- tests/unit/bags_item_info_extended_test.lua
-- Run: lua tests/unit/bags_item_info_extended_test.lua
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

local fullCalls = 0
_G.C_Item.GetItemInfo = function(itemID)
    fullCalls = fullCalls + 1
    if itemID == 2589 then
        -- name, link, quality, baseIlvl, minLvl, type, subType, stack, equipLoc,
        -- texture, sellPrice, classID, subClassID, bindType, expacID, setID, isReagent
        return "Linen Cloth", "|Hitem:2589|h[Linen Cloth]|h", 1, 5, 0, "Tradeskill", "Cloth",
               1000, "", 132889, 13, 7, 5, 0, 0, nil, true
    end
    return nil
end
_G.C_Item.GetDetailedItemLevelInfo = function(link) return 5 end

local ns = loader.LoadAll(nil, "item_info.lua")
local ItemInfo = ns.Bags.ItemInfo

-- Test 1: extended record assembled and cached
local e1 = ItemInfo.GetExtended(2589, "|Hitem:2589|h[Linen Cloth]|h")
assert(e1 and e1.name == "Linen Cloth" and e1.ilvl == 5 and e1.expacID == 0, "extended fields wrong")
-- maxStack: GetItemInfo position 8 = itemStackCount (verified: ItemDocumentation.lua, GetItemInfo returns[8])
assert(e1.maxStack == 1000, "maxStack must equal stub position 8 (1000)")
assert(ItemInfo.GetExtended(2589) == e1, "extended cache identity failed")
assert(fullCalls == 1, "GetItemInfo should be called once")

-- Test 2: uncached item → nil, NOT cached
assert(ItemInfo.GetExtended(999999) == nil, "unknown must be nil")
assert(ItemInfo.GetExtended(nil) == nil, "nil itemID must be nil")

-- Test 3: ilvl falls back to baseIlvl when detailed info is unavailable
_G.C_Item.GetItemInfo = function(itemID)
    if itemID == 777 then
        return "Plain Item", "|Hitem:777|h[Plain Item]|h", 1, 42, 0, "Misc", "Junk",
               1, "", 1, 0, 15, 0, 0, 9, nil, false
    end
    return nil
end
_G.C_Item.GetDetailedItemLevelInfo = function() return nil end
local e3 = ItemInfo.GetExtended(777)
assert(e3 and e3.ilvl == 42, "must fall back to baseIlvl")

-- Test 4: same itemID with a different link returns the cached record
-- (documented first-seen-wins limitation)
local e4 = ItemInfo.GetExtended(777, "|Hitem:777::upgraded|h[Plain Item]|h")
assert(e4 == e3, "itemID-keyed cache must return first-seen record")

-- Test 5: an item that was pending becomes available on a later call
local available = false
_G.C_Item.GetItemInfo = function(itemID)
    if itemID == 888 and available then
        return "Late Item", "|Hitem:888|h[Late Item]|h", 2, 10, 0, "Misc", "Junk",
               1, "", 1, 0, 15, 0, 0, 9, nil, false
    end
    return nil
end
assert(ItemInfo.GetExtended(888) == nil, "pending must be nil")
available = true
local e5 = ItemInfo.GetExtended(888)
assert(e5 and e5.name == "Late Item", "must resolve once data arrives")

print("OK: bags_item_info_extended_test")
