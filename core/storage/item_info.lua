local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local ItemInfo = {}
Storage.ItemInfo = ItemInfo

local derived = {}
local pendingLoads = {}

function ItemInfo.GetDerived(itemID)
    if not itemID then return nil end
    local hit = derived[itemID]
    if hit then return hit end
    local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end
    local isEquippable = C_Item.IsEquippableItem(itemID) and true or false
    local rec = { classID = classID, subClassID = subClassID, equipLoc = equipLoc,
        icon = icon, isEquippable = isEquippable }
    derived[itemID] = rec
    return rec
end

function ItemInfo.RequestLoad(itemID, callback)
    if not itemID then return end
    local list = pendingLoads[itemID]
    if list then
        list[#list + 1] = callback
        return
    end
    pendingLoads[itemID] = { callback }
    C_Item.RequestLoadItemDataByID(itemID)
end

function ItemInfo.OnItemDataLoadResult(itemID, success)
    local list = pendingLoads[itemID]
    if not list then return end
    pendingLoads[itemID] = nil
    for i = 1, #list do
        xpcall(function() list[i](itemID, success) end, geterrorhandler())
    end
end

local extended = {}

function ItemInfo.GetExtended(itemID, link)
    if not itemID then return nil end
    local hit = extended[itemID]
    if hit then return hit end
    local name, infoLink, _, baseIlvl, _, _, _, maxStack, _, _, _, _, _, bindType, expacID, _, isCraftingReagent = C_Item.GetItemInfo(itemID)
    if not name then return nil end
    local ilvl = C_Item.GetDetailedItemLevelInfo(link or infoLink) or baseIlvl
    local rec = { name = name, ilvl = ilvl, expacID = expacID, maxStack = maxStack,
        bindType = bindType, isReagent = isCraftingReagent and true or false }
    extended[itemID] = rec
    return rec
end
