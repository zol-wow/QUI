---------------------------------------------------------------------------
-- Core storage: equipped-items scanner.
-- Inventory slots 1..19 (INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED,
-- vendored Blizzard_FrameXMLBase/Constants.lua:152-173) read through the
-- legacy globals GetInventoryItemID/Link/Texture/Quality("player", slot)
-- (verified against vendored EquipmentManager.lua / PaperDollFrame.lua).
-- PLAYER_EQUIPMENT_CHANGED(equipmentSlot, hasCurrent) gives a per-slot
-- dirty unit; login catch-up is a MarkAllDirty from the deferred block.
-- Nil quality means item data isn't loaded yet → the shared scan_common
-- pending handler re-marks the slot on load success (cf. scan_bags.lua).
-- Store shape: rec.equipped = { size = 19, slots = { [invSlot] = entry } }.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanEquipped = {}
Storage.ScanEquipped = ScanEquipped

-- INVSLOT_FIRST_EQUIPPED .. INVSLOT_LAST_EQUIPPED (INVSLOT_TABARD). Slot 0
-- (ammo) is retail-dead; PLAYER_EQUIPMENT_CHANGED can also fire for
-- equipped-bag container slots above 19 — both are out of range here.
local FIRST_SLOT, LAST_SLOT = 1, 19

local dirty = {}
local hasDirty = false

function ScanEquipped.MarkDirty(slot)
    if type(slot) ~= "number" or slot < FIRST_SLOT or slot > LAST_SLOT then return end
    dirty[slot] = true
    hasDirty = true
end

function ScanEquipped.MarkAllDirty()
    for slot = FIRST_SLOT, LAST_SLOT do dirty[slot] = true end
    hasDirty = true
end

--- Read one inventory slot into the persisted entry shape (or nil if empty).
local function ReadSlot(slot, onPending)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return nil end
    local quality = GetInventoryItemQuality("player", slot)
    if quality == nil and onPending then onPending(itemID) end
    return {
        itemID = itemID,
        count = 1,
        link = GetInventoryItemLink("player", slot),
        quality = quality,
        icon = GetInventoryItemTexture("player", slot),
        isBound = true, -- equipping binds (warbound at minimum)
    }
end

--- Re-read every dirty slot; publishes EquippedChanged(charKey)
--- (whole-record event — no changed array; see bus.lua). Returns true when
--- anything was written.
function ScanEquipped.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end -- transient: dirty marks preserved
    -- Snapshot-swap BEFORE reading: the pending handler's load callback can
    -- fire synchronously (client-cached item) and re-mark a slot inside
    -- ReadSlot — re-marks must land in the fresh set (cf. scan_bags.lua).
    local toScan = dirty
    dirty = {}
    hasDirty = false
    -- Phase-1 records persisted `equipped = {}` (no .slots): upgrade in place.
    local eq = rec.equipped
    if type(eq) ~= "table" or not eq.slots then
        eq = { size = LAST_SLOT, slots = {} }
        rec.equipped = eq
    end
    local wrote = false
    for slot in pairs(toScan) do
        eq.slots[slot] = ReadSlot(slot, Storage.ScanCommon.MakePendingHandler(slot, ScanEquipped.MarkDirty))
        wrote = true
    end
    if wrote then
        Storage.Bus.Publish("EquippedChanged", Storage.Store.GetCurrentCharacterKey())
        return true
    end
    return false
end
