local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Storage = ns.Storage

local Details = {}
Bags.Details = Details

function Details.Build(entry)
    if not entry then return nil end
    local derived = Storage.ItemInfo.GetDerived(entry.itemID)
    local extended = Storage.ItemInfo.GetExtended(entry.itemID, entry.link)
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
