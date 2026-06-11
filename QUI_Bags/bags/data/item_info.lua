---------------------------------------------------------------------------
-- Bags data layer: session-only item info.
-- 1) Derived-field cache (classID/subClassID/equipLoc/icon) — computed from
--    C_Item.GetItemInfoInstant on demand, NEVER persisted (SV stays minimal).
-- 2) Async load tracker: scanners request a data load for slots whose
--    ContainerItemInfo arrived with quality == nil and get a callback when
--    ITEM_DATA_LOAD_RESULT delivers (bags.lua routes the event here).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local ItemInfo = {}
Bags.ItemInfo = ItemInfo

local derived = {}      -- itemID → { classID, subClassID, equipLoc, icon }
local pendingLoads = {} -- itemID → { callback, ... }

function ItemInfo.GetDerived(itemID)
    if not itemID then return nil end
    local hit = derived[itemID]
    if hit then return hit end
    local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end
    local rec = { classID = classID, subClassID = subClassID, equipLoc = equipLoc, icon = icon }
    derived[itemID] = rec
    return rec
end

--- Request a client-side item data load; callback(itemID, success) fires on
--- ITEM_DATA_LOAD_RESULT. Concurrent requests for one itemID coalesce into a
--- single client request.
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

--- Event sink, wired by bags.lua: ITEM_DATA_LOAD_RESULT(itemID, success).
function ItemInfo.OnItemDataLoadResult(itemID, success)
    local list = pendingLoads[itemID]
    if not list then return end
    pendingLoads[itemID] = nil
    for i = 1, #list do
        xpcall(function() list[i](itemID, success) end, geterrorhandler())
    end
end

--- Drop all in-flight load callbacks (module disable). Coalescing state is
--- reset so a later RequestLoad re-issues the client request.
function ItemInfo.CancelAll()
    pendingLoads = {}
end

local extended = {} -- itemID → { name, ilvl, expacID } (session-only)

--- Full-info tier for search: nil until C_Item.GetItemInfo has the item
--- cached (callers treat nil as pending). link improves effective-ilvl
--- accuracy when provided.
--- KNOWN LIMITATION (v1): cache keys by itemID, so two copies of the same
--- base item at different upgrade levels share the first-seen ilvl. Fix if
--- ilvl-search precision ever matters: key by link or recompute per call.
function ItemInfo.GetExtended(itemID, link)
    if not itemID then return nil end
    local hit = extended[itemID]
    if hit then return hit end
    -- Position 8 = itemStackCount (ItemDocumentation.lua GetItemInfo returns[8])
    local name, infoLink, _, baseIlvl, _, _, _, maxStack, _, _, _, _, _, bindType, expacID = C_Item.GetItemInfo(itemID)
    if not name then return nil end
    local ilvl = C_Item.GetDetailedItemLevelInfo(link or infoLink) or baseIlvl
    local rec = { name = name, ilvl = ilvl, expacID = expacID, maxStack = maxStack,
        bindType = bindType }
    extended[itemID] = rec
    return rec
end
