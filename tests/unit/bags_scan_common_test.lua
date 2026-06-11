-- tests/unit/bags_scan_common_test.lua
-- Run: lua tests/unit/bags_scan_common_test.lua
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- Stubbed container: bag 0 has 4 slots; slot 1 full, slot 2 empty,
-- slot 3 full with quality==nil (item data not loaded), slot 4 empty.
_G.C_Container.GetContainerNumSlots = function(bagID)
    if bagID == 0 then return 4 end
    return 0
end
_G.C_Container.GetContainerItemInfo = function(bagID, slot)
    if bagID ~= 0 then return nil end
    if slot == 1 then
        return { itemID = 6948, stackCount = 1, hyperlink = "|Hitem:6948|h[Hearthstone]|h",
                 quality = 1, iconFileID = 134414, isBound = true,
                 isLocked = false, isReadable = false, hasLoot = false,
                 isFiltered = false, hasNoValue = true, itemName = "Hearthstone" }
    end
    if slot == 3 then
        return { itemID = 2589, stackCount = 20, hyperlink = "|Hitem:2589|h[Linen Cloth]|h",
                 quality = nil, iconFileID = 132889, isBound = false,
                 isLocked = false, isReadable = false, hasLoot = false,
                 isFiltered = false, hasNoValue = false, itemName = "Linen Cloth" }
    end
    return nil
end

local ns = loader.LoadAll(nil, "scan_common.lua")
local ScanCommon = ns.Bags.ScanCommon

-- Test 1: full container read with exact entry shape
local pending = {}
local c = ScanCommon.ReadContainer(0, function(itemID) pending[#pending + 1] = itemID end)
assert(c.size == 4, "container size wrong")
local e1 = c.slots[1]
assert(e1.itemID == 6948 and e1.count == 1 and e1.quality == 1 and e1.icon == 134414
       and e1.isBound == true and e1.link == "|Hitem:6948|h[Hearthstone]|h", "slot 1 entry wrong")
assert(c.slots[2] == nil and c.slots[4] == nil, "empty slots must be nil")

-- Test 2: nil-quality slot is still recorded but reported pending
assert(c.slots[3] ~= nil and c.slots[3].quality == nil, "pending slot should still be recorded")
assert(#pending == 1 and pending[1] == 2589, "pending callback wrong")

-- Test 3: entry shape contains ONLY the persisted keys (SV minimalism guard)
-- — checked on every occupied slot, including the nil-quality one (slot 3),
-- so a conditionally-added field can't sneak in.
local allowed = { itemID = true, count = true, link = true, quality = true, icon = true, isBound = true }
for slot, entry in pairs(c.slots) do
    for k in pairs(entry) do
        assert(allowed[k], "unexpected persisted key in slot " .. slot .. ": " .. tostring(k))
    end
end

-- Test 4: empty container
local empty = ScanCommon.ReadContainer(7)
assert(empty.size == 0 and next(empty.slots) == nil, "empty container read wrong")

print("OK: bags_scan_common_test")
