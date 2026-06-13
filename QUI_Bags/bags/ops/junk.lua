---------------------------------------------------------------------------
-- Bags ops: junk detection + merchant auto-sell.
--
-- IsJunk(liveInfo, bagID, exclusions): quality 0 (Poor), sellable
-- (not hasNoValue), itemID not in the user exclusion list, and the bag not
-- opted out of junk selling. ContainerItemInfo.quality is Nilable
-- (ContainerDocumentation.lua:764) — nil quality is never junk.
--
-- IsBagExcluded(bagID) — flag applicability verified against FrameXML
-- ContainerFrame.lua:628-643 (the bag cleanup menu): the backpack does NOT
-- use the bag-slot flag — it has the standalone
-- C_Container.GetBackpackSellJunkDisabled() API; held bags 1–5 use
-- GetBagSlotFlag(bagID, Enum.BagSlotFlags.ExcludeJunkSell) (EnumValue 64,
-- BagConstantsDocumentation.lua:57). Blizzard's menu never offers the flag
-- on bank tabs ("if not ContainerFrame_IsBankTab(bagID)"), so non-player
-- bagIDs are pinned to false — same shape as sort_executor's IsBagIgnored.
--
-- SellJunk([onDone]): merchant-gated (OnMerchant(shown) routed from
-- bags.lua's PLAYER_INTERACTION_MANAGER branch). Live-iterates player bags
-- 0–5, enqueues C_Container.UseContainerItem(bag, slot) — the 2-arg form at
-- an open merchant SELLS (ContainerDocumentation.lua:575; no
-- unitToken/bankType) — on a dedicated Transfers.RateQueue paced at 0.17s
-- (≈6/sec, the server's sell throttle). Sell value accumulates
-- sellPrice * stackCount, sellPrice = C_Item.GetItemInfo return 11
-- (ItemDocumentation.lua:611); MayReturnNothing → an uncached item is still
-- SOLD but skipped from the reported total. Completion prints count +
-- GetMoneyString(total, true). Note: the merchant buyback page holds 12
-- items; bulk sells past that are fine (older entries roll off) — sell
-- anyway, report to chat.
--
-- OnMerchant(false) cancels an in-flight sell run: after the window closes
-- UseContainerItem would USE the item instead of selling it. OnCombat()
-- (routed from bags.lua's PLAYER_REGEN_DISABLED branch) cancels a running
-- sell with onDone(false, "combat") per the RateQueue contract.
--
-- OnMerchant also publishes "MerchantChanged"(shown) on the bus (documented
-- in data/bus.lua) so the bag window can toggle its Sell Junk button.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("bags")

local SELL_INTERVAL = 0.17  -- seconds between UseContainerItem sells (≈6/sec)

-- Informational house print prefix (mirrors sort_executor.lua's PREFIX).
local PREFIX = Bags.OpsShared.PREFIX

local merchantOpen = false
local queue = nil  -- active sell RateQueue, nil when idle

local Junk = {}
Bags.Junk = Junk

--- True when the given bag has opted out of junk selling. Backpack (0) →
--- GetBackpackSellJunkDisabled(); held bags 1–5 → ExcludeJunkSell bag-slot
--- flag; everything else (bank tabs, warband, negatives) → false (the flag
--- does not apply there; see header).
function Junk.IsBagExcluded(bagID)
    if bagID == 0 then
        return C_Container.GetBackpackSellJunkDisabled() and true or false
    end
    if bagID >= 1 and bagID <= 5 then
        return C_Container.GetBagSlotFlag(bagID, Enum.BagSlotFlags.ExcludeJunkSell) and true or false
    end
    return false
end

--- Junk eligibility for one live slot. liveInfo = ContainerItemInfo (may be
--- nil for an empty slot); exclusions = [itemID]=true set (nil tolerated).
function Junk.IsJunk(liveInfo, bagID, exclusions)
    if not liveInfo then return false end
    if liveInfo.quality ~= 0 then return false end       -- Poor only; quality Nilable
    if liveInfo.hasNoValue then return false end          -- vendors won't pay
    if exclusions and exclusions[liveInfo.itemID] then return false end
    if Junk.IsBagExcluded(bagID) then return false end
    return true
end

--- Merchant gate, routed from bags.lua's interaction SHOW/HIDE branch.
--- Closing the merchant cancels an in-flight sell run (post-close
--- UseContainerItem would use the item) and both edges publish
--- "MerchantChanged"(shown) on the bus.
function Junk.OnMerchant(shown)
    merchantOpen = shown and true or false
    if not merchantOpen and queue then
        queue:Cancel()  -- queue's onDone clears `queue` and reports (false, "cancel")
    end
    if Bags.Bus then Bags.Bus.Publish("MerchantChanged", merchantOpen) end
end

--- True while a merchant window is open (consumed by the bag window's
--- Sell Junk button visibility).
function Junk.IsMerchantOpen()
    return merchantOpen
end

--- True while a sell run is in progress (consumed by the shared ops gate in
--- the sibling entry points; the local self-check reads `queue` directly).
function Junk.IsSelling()
    return queue ~= nil
end

--- Combat abort — bags.lua routes PLAYER_REGEN_DISABLED here. Cancels a
--- running sell with onDone(false, "combat") per the RateQueue contract.
function Junk.OnCombat()
    if queue then
        queue:OnCombat()  -- queue's onDone clears `queue`, reports (false, "combat")
    end
end

--- Sell every junk-eligible item in player bags 0–5 at the open merchant.
--- onDone(ok[, reason]) fires once: (true) run complete (or nothing to
--- sell), (false, "merchant"|"running"|"busy"|"cancel"|"combat") otherwise.
function Junk.SellJunk(onDone)
    if not merchantOpen then
        if onDone then onDone(false, "merchant") end
        return
    end
    if queue then
        if onDone then onDone(false, "running") end
        return
    end
    -- shared ops gate: cursor/slot ops must never overlap (wrong-item hazards)
    if Bags.OpsShared.OpsBusy() then
        if onDone then onDone(false, "busy") end
        return
    end

    local s = GetSettings()
    local junkCfg = s and s.behavior and s.behavior.junk
    local exclusions = junkCfg and junkCfg.exclusions or nil

    -- Snapshot eligible (bag, slot, itemID) triples from LIVE state now, so
    -- the queue is deterministic regardless of mid-run bag changes; price the
    -- total in the same pass (sellPrice = GetItemInfo return 11; uncached →
    -- sold but not counted). The itemID rides along for per-tick re-validation.
    local items = {}
    local total = 0
    for bagID = 0, 5 do
        local size = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, size do
            local info = C_Container.GetContainerItemInfo(bagID, slot)  -- MayReturnNothing
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
        print(PREFIX .. " No junk to sell.")
        if onDone then onDone(true) end
        return
    end

    queue = Bags.Transfers.RateQueue(SELL_INTERVAL, function(ok, reason)
        queue = nil
        if ok then
            print(("%s Sold %d junk item%s for %s."):format(
                PREFIX, count, count == 1 and "" or "s",
                GetMoneyString(total, true)))
        end
        if onDone then onDone(ok, reason) end
    end)
    for _, it in ipairs(items) do
        local bag, slot, snapshotID = it.bag, it.slot, it.itemID
        queue:Enqueue(function()
            -- Per-tick re-validation: items can move under a queue (user
            -- drags); never act on a slot whose occupant changed.
            local live = C_Container.GetContainerItemInfo(bag, slot)
            if not live or live.itemID ~= snapshotID then return end
            C_Container.UseContainerItem(bag, slot)  -- 2-arg form at a merchant = sell
        end)
    end
end
