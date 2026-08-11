local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ScanCommon = {}
Storage.ScanCommon = ScanCommon

function ScanCommon.ReadSlot(bagID, slot, onPending)
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if not info then return nil end
    if info.quality == nil and onPending then
        onPending(info.itemID)
    end
    return {
        itemID = info.itemID,
        count = info.stackCount,
        link = info.hyperlink,
        quality = info.quality,
        icon = info.iconFileID,
        isBound = info.isBound,
    }
end

function ScanCommon.ReadContainer(bagID, onPending)
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    local container = { size = numSlots, slots = {} }
    for slot = 1, numSlots do
        container.slots[slot] = ScanCommon.ReadSlot(bagID, slot, onPending)
    end
    return container
end

function ScanCommon.MakePendingHandler(bagID, markDirty)
    return function(itemID)
        Storage.ItemInfo.RequestLoad(itemID, function(_, success)
            if not success then return end
            markDirty(bagID)
            Storage.RequestDrain()
        end)
    end
end
