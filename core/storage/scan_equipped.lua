local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanEquipped = {}
Storage.ScanEquipped = ScanEquipped

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

local function ReadSlot(slot, onPending)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return nil end
    local quality = GetInventoryItemQuality("player", slot)
    local link = GetInventoryItemLink("player", slot)
    local ilvl = C_Item.GetDetailedItemLevelInfo(link or itemID)
    if (quality == nil or ilvl == nil) and onPending then onPending(itemID) end
    return {
        itemID = itemID,
        count = 1,
        link = link,
        quality = quality,
        ilvl = ilvl,
        icon = GetInventoryItemTexture("player", slot),
        isBound = true,
    }
end

function ScanEquipped.Drain()
    if not hasDirty then return false end
    local rec = Storage.Store.GetCurrentCharacter()
    if not rec then return false end
    local toScan = dirty
    dirty = {}
    hasDirty = false
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
