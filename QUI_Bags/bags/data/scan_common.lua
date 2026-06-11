---------------------------------------------------------------------------
-- Bags data layer: shared container readers.
-- Single source of truth for the persisted slot-entry shape. Both the bag
-- scanner and the bank scanner read through here; if the shape changes,
-- it changes in exactly one place (plus store.lua's doc comment).
--
-- SECRET-VALUE POLICY (explicit design decision): ContainerItemInfo fields
-- are stored and compared in plain Lua here ON PURPOSE. The generated docs
-- mark secret-capable RETURNS with function-level SecretWhen* annotations
-- (and exempt individual fields with NeverSecret inside such functions);
-- ContainerDocumentation.lua carries ZERO secret markers — container item
-- returns are never secret. SecretArguments = "AllowedWhenUntainted" on
-- GetContainerItemInfo governs what may be passed IN, not what comes back.
-- The SV round-trip is the backstop: a secret value cannot be persisted,
-- so everything read back from QUI_StorageDB is plain by construction.
-- (Tooltip-data ids are the one secret-capable input in this module — see
-- tooltip_counts.lua for that guard and its rationale.)
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local ScanCommon = {}
Bags.ScanCommon = ScanCommon

--- Read one container slot into the persisted entry shape (or nil if empty).
--- onPending(itemID) is invoked when item data isn't fully loaded yet
--- (quality == nil) so the caller can schedule a re-scan.
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

--- Read a whole container body: { size, slots = { [slot] = entry|nil } }.
--- slots is SPARSE (empty slots are nil): consumers must iterate with pairs
--- or index 1..size — ipairs stops at the first empty slot.
--- onPending may be nil; when given it must be async-safe — do NOT re-enter
--- ReadContainer for the same bagID from inside the callback.
function ScanCommon.ReadContainer(bagID, onPending)
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    local container = { size = numSlots, slots = {} }
    for slot = 1, numSlots do
        container.slots[slot] = ScanCommon.ReadSlot(bagID, slot, onPending)
    end
    return container
end

--- Build the standard onPending handler for a scanner: requests the item
--- load and, ONLY on success, re-marks the container and schedules a drain.
--- The success guard is load-bearing — without it a permanently failing
--- itemID causes a scan→request→scan loop.
function ScanCommon.MakePendingHandler(bagID, markDirty)
    return function(itemID)
        Bags.ItemInfo.RequestLoad(itemID, function(_, success)
            if not success then return end
            markDirty(bagID)
            Bags.RequestDrain()
        end)
    end
end
