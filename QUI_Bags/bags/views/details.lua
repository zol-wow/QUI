---------------------------------------------------------------------------
-- Bags views: shared item-details builder.
-- Lifts BuildDetails from bag_window so both the bag window and the
-- bank window can call Bags.Details.Build(entry) without duplication.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Details = {}
Bags.Details = Details

--- Build a details table from a cache slot entry for search/filtering.
--- Returns nil when entry is nil (empty slot — same nil-for-nil contract as
--- the original local BuildDetails in bag_window.lua).
--- Field set: itemID, count, quality, isBound, classID, subClassID,
---   equipLoc, isEquippable, name, ilvl, expacID, bindType, isReagent.
function Details.Build(entry)
    if not entry then return nil end
    local derived = Bags.ItemInfo.GetDerived(entry.itemID)
    local extended = Bags.ItemInfo.GetExtended(entry.itemID, entry.link)
    return {
        itemID       = entry.itemID,
        count        = entry.count,
        quality      = entry.quality,
        isBound      = entry.isBound,
        classID      = derived and derived.classID      or nil,
        subClassID   = derived and derived.subClassID   or nil,
        equipLoc     = derived and derived.equipLoc     or nil,
        isEquippable = derived and derived.isEquippable or nil,
        name         = extended and extended.name       or nil,
        ilvl         = extended and extended.ilvl       or nil,
        expacID      = extended and extended.expacID    or nil,
        bindType     = extended and extended.bindType   or nil,
        isReagent    = extended and extended.isReagent  or nil,
    }
end
