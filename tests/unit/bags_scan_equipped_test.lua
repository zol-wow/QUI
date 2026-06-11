-- tests/unit/bags_scan_equipped_test.lua
-- Run: lua tests/unit/bags_scan_equipped_test.lua
-- Equipped scanner: legacy inventory globals over slots 1..19
-- (INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED), per-slot dirty unit via
-- PLAYER_EQUIPMENT_CHANGED(equipmentSlot, hasCurrent). Store shape:
-- rec.equipped = { size = 19, slots = { [invSlot] = entry } }.
-- luacheck: globals QUI_StorageDB GetInventoryItemID GetInventoryItemLink GetInventoryItemTexture GetInventoryItemQuality
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

-- Legacy inventory API stubs -------------------------------------------------
-- GetInventoryItemID/Link/Texture/Quality("player", slot) — verified against
-- vendored EquipmentManager.lua / PaperDollFrame.lua call sites.
local worn = {} -- [slot] = { id, link, texture, quality }
local reads = {} -- [slot] = read count (per-slot rescan granularity probe)
_G.GetInventoryItemID = function(unit, slot)
    assert(unit == "player", "scanner must only read the player")
    reads[slot] = (reads[slot] or 0) + 1
    return worn[slot] and worn[slot].id or nil
end
_G.GetInventoryItemLink = function(_, slot) return worn[slot] and worn[slot].link or nil end
_G.GetInventoryItemTexture = function(_, slot) return worn[slot] and worn[slot].texture or nil end
_G.GetInventoryItemQuality = function(_, slot) return worn[slot] and worn[slot].quality or nil end

local ns = loader.LoadAll(nil, "scan_equipped.lua")
local drainRequests = 0
ns.Bags.RequestDrain = function() drainRequests = drainRequests + 1 end
local Store, ScanEquipped, Bus = ns.Bags.Store, ns.Bags.ScanEquipped, ns.Bags.Bus

_G.QUI_StorageDB = nil
Store.Initialize()
Store.EnsureCurrentCharacter()
local KEY = "Testchar-TestRealm"

local events = {}
Bus.Subscribe("EquippedChanged", function(_, charKey) events[#events + 1] = charKey end)

-- Test 1: MarkAllDirty + Drain writes every worn slot; empty slots stay nil
worn[1]  = { id = 1001, link = "|Hitem:1001::|h[Helm]|h",  texture = 111, quality = 3 }
worn[16] = { id = 1016, link = "|Hitem:1016::|h[Sword]|h", texture = 116, quality = 4 }
ScanEquipped.MarkAllDirty()
assert(ScanEquipped.Drain() == true, "dirty drain must write")
local rec = Store.GetCurrentCharacter()
assert(rec.equipped.size == 19, "equipped size must be 19 (INVSLOT_LAST_EQUIPPED)")
local head = rec.equipped.slots[1]
assert(head.itemID == 1001 and head.count == 1 and head.quality == 3
       and head.icon == 111 and head.isBound == true
       and head.link == "|Hitem:1001::|h[Helm]|h", "head entry wrong")
assert(rec.equipped.slots[16].itemID == 1016, "mainhand entry missing")
assert(rec.equipped.slots[2] == nil, "empty slots must be nil")
assert(#events == 1 and events[1] == KEY, "exactly one EquippedChanged(charKey) per drain")
assert(ScanEquipped.Drain() == false, "clean drain must no-op")

-- Test 2: entry-shape minimalism guard — ONLY the six persisted entry keys
local allowed = { itemID = true, count = true, link = true, quality = true,
                  icon = true, isBound = true }
for slot, e in pairs(rec.equipped.slots) do
    for k in pairs(e) do
        assert(allowed[k], "unexpected persisted key in slot " .. slot .. ": " .. tostring(k))
    end
end

-- Test 3: per-slot dirty unit — a weapon swap re-reads only that slot
local headReads = reads[1]
worn[16] = { id = 2016, link = "|Hitem:2016::|h[Axe]|h", texture = 216, quality = 4 }
ScanEquipped.MarkDirty(16)
assert(ScanEquipped.Drain() == true, "slot-dirty drain must write")
assert(rec.equipped.slots[16].itemID == 2016, "swapped slot must re-read")
assert(reads[1] == headReads, "undirtied slots must not re-read")
assert(rec.equipped.slots[1].itemID == 1001, "undirtied slots keep their cache")

-- Test 4: unequip (hasCurrent=false → slot empty) clears the slot
worn[16] = nil
ScanEquipped.MarkDirty(16)
assert(ScanEquipped.Drain() == true)
assert(rec.equipped.slots[16] == nil, "unequipped slot must clear")

-- Test 5: out-of-range slots are ignored (PLAYER_EQUIPMENT_CHANGED also
-- fires for bag-container slots > 19; ammo slot 0 is retail-dead)
ScanEquipped.MarkDirty(0)
ScanEquipped.MarkDirty(20)
ScanEquipped.MarkDirty(nil)
assert(ScanEquipped.Drain() == false, "out-of-range marks must not dirty the scanner")

-- Test 6: nil quality → pending load; success re-marks the slot (scan_common
-- pending handler reuse — success-gated, drain re-requested)
worn[5] = { id = 424242, link = "|Hitem:424242::|h[Chest]|h", texture = 105, quality = nil }
ScanEquipped.MarkDirty(5)
ScanEquipped.Drain()
assert(rec.equipped.slots[5].quality == nil, "pending entry persists with nil quality")
worn[5].quality = 2 -- item data arrives
ns.Bags.ItemInfo.OnItemDataLoadResult(424242, true)
assert(drainRequests >= 1, "successful load must request a drain")
assert(ScanEquipped.Drain() == true, "successful load must re-mark the slot")
assert(rec.equipped.slots[5].quality == 2, "rescan should pick up the loaded quality")

-- Test 7: phase-1 records persisted `equipped = {}` — drain upgrades in place
QUI_StorageDB.characters[KEY].equipped = {}
ScanEquipped.MarkDirty(1)
assert(ScanEquipped.Drain() == true, "drain must upgrade a shape-less record")
rec = Store.GetCurrentCharacter()
assert(rec.equipped.size == 19 and rec.equipped.slots[1].itemID == 1001,
       "upgraded record must carry the standard shape")

-- Test 8: drain with no character record preserves dirty marks
Store.DeleteCharacter(KEY)
ScanEquipped.MarkDirty(1)
assert(ScanEquipped.Drain() == false, "drain without a record must not write")
Store.EnsureCurrentCharacter()
assert(ScanEquipped.Drain() == true, "marks must survive a record-less drain")

print("OK: bags_scan_equipped_test")
