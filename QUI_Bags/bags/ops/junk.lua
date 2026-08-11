local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Storage = ns.Storage
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("bags")

local SELL_INTERVAL = 0.17

local PREFIX = Bags.OpsShared.PREFIX

local merchantOpen = false
local queue = nil

local Junk = {}
Bags.Junk = Junk

function Junk.IsBagExcluded(bagID)
    if bagID == 0 then
        return C_Container.GetBackpackSellJunkDisabled() and true or false
    end
    if bagID >= 1 and bagID <= 5 then
        return C_Container.GetBagSlotFlag(bagID, Enum.BagSlotFlags.ExcludeJunkSell) and true or false
    end
    return false
end

function Junk.IsJunk(liveInfo, bagID, exclusions)
    if not liveInfo then return false end
    if liveInfo.quality ~= 0 then return false end
    if liveInfo.hasNoValue then return false end
    if exclusions and exclusions[liveInfo.itemID] then return false end
    if Junk.IsBagExcluded(bagID) then return false end
    return true
end

function Junk.OnMerchant(shown)
    merchantOpen = shown and true or false
    if not merchantOpen and queue then
        queue:Cancel()
    end
    if Storage.Bus then Storage.Bus.Publish("MerchantChanged", merchantOpen) end
end

function Junk.IsMerchantOpen()
    return merchantOpen
end

function Junk.IsSelling()
    return queue ~= nil
end

function Junk.OnCombat()
    if queue then
        queue:OnCombat()
    end
end

function Junk.SellJunk(onDone)
    if not merchantOpen then
        if onDone then onDone(false, "merchant") end
        return
    end
    if queue then
        if onDone then onDone(false, "running") end
        return
    end
    if Bags.OpsShared.OpsBusy() then
        if onDone then onDone(false, "busy") end
        return
    end

    local s = GetSettings()
    local junkCfg = s and s.behavior and s.behavior.junk
    local exclusions = junkCfg and junkCfg.exclusions or nil

    local items = {}
    local total = 0
    for bagID = 0, 5 do
        local size = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, size do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and Junk.IsJunk(info, bagID, exclusions) then
                items[#items + 1] = { bag = bagID, slot = slot, itemID = info.itemID }
                local sellPrice = select(11, C_Item.GetItemInfo(info.itemID))
                if type(sellPrice) == "number" then
                    total = total + sellPrice * (info.stackCount or 1)
                end
            end
        end
    end

    local count = #items
    if count == 0 then
        print(PREFIX .. " " .. ns.L["No junk to sell."])
        if onDone then onDone(true) end
        return
    end

    queue = Bags.Transfers.RateQueue(SELL_INTERVAL, function(ok, reason)
        queue = nil
        if ok then
            print(("%s " .. ns.L["Sold %d junk items for %s."]):format(
                PREFIX, count, GetMoneyString(total, true)))
        end
        if onDone then onDone(ok, reason) end
    end)
    for _, it in ipairs(items) do
        local bag, slot, snapshotID = it.bag, it.slot, it.itemID
        queue:Enqueue(function()
            local live = C_Container.GetContainerItemInfo(bag, slot)
            if not live or live.itemID ~= snapshotID then return end
            C_Container.UseContainerItem(bag, slot)
        end)
    end
end
