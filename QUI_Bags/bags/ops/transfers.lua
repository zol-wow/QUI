local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local RATE_INTERVAL = 0.2

local PREFIX = Bags.OpsShared.PREFIX

local function RateQueue(interval, onDone)
    interval = interval or RATE_INTERVAL
    local q = {}
    local queue   = {}
    local running = false
    local token   = nil

    local function finish(ok, reason)
        running = false
        token   = nil
        queue   = {}
        if onDone then onDone(ok, reason) end
    end

    local function scheduleNext(myToken)
        C_Timer.After(interval, function()
            if token ~= myToken then return end
            if #queue == 0 then
                finish(true)
                return
            end
            local fn = table.remove(queue, 1)
            fn()
            if #queue == 0 then
                finish(true)
            else
                local nextToken = {}
                token = nextToken
                scheduleNext(nextToken)
            end
        end)
    end

    function q:Enqueue(fn)
        queue[#queue + 1] = fn
        if not running then
            running = true
            local startToken = {}
            token = startToken
            local first = table.remove(queue, 1)
            first()
            if running then
                scheduleNext(startToken)
            end
        end
    end

    function q:IsRunning()
        return running
    end

    function q:Cancel()
        if not running then return end
        finish(false, "cancel")
    end

    function q:OnCombat()
        if not running then return end
        finish(false, "combat")
    end

    return q
end

local singleton = nil

local Transfers = {}
Bags.Transfers = Transfers

Transfers.RateQueue = RateQueue

local OpsBusy = Bags.OpsShared.OpsBusy

function Transfers.DepositAllToWarband(onDone)
    if OpsBusy() then
        if onDone then onDone(false, "busy") end
        return
    end

    local pairs_list = {}
    for bagID = 0, 5 do
        local size = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, size do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info then
                local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
                if C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc) then
                    pairs_list[#pairs_list + 1] = { bag = bagID, slot = slot, itemID = info.itemID }
                end
            end
        end
    end

    if #pairs_list == 0 then
        if onDone then onDone(true) end
        return
    end

    singleton = RateQueue(RATE_INTERVAL, function(ok, reason)
        singleton = nil
        if onDone then onDone(ok, reason) end
    end)

    for _, p in ipairs(pairs_list) do
        local bag, slot, snapshotID = p.bag, p.slot, p.itemID
        singleton:Enqueue(function()
            local live = C_Container.GetContainerItemInfo(bag, slot)
            if not live or live.itemID ~= snapshotID then return end
            C_Container.UseContainerItem(bag, slot, nil, Enum.BankType.Account)
        end)
    end
end

function Transfers.FillReagentBag(onDone)
    if OpsBusy() then
        if onDone then onDone(false, "busy") end
        return
    end
    if InCombatLockdown() then
        if onDone then onDone(false, "combat") end
        return
    end
    local containers = Bags.SortExecutor.BuildContainers({ first = 0, last = 5 })
    local moves = Bags.ReagentFill.Plan(containers, 5)
    if #moves == 0 then
        print(PREFIX .. " " .. ns.L["No reagents to move (no reagent bag, no fitting items, or it's full)."])
        if onDone then onDone(true) end
        return
    end
    singleton = RateQueue(RATE_INTERVAL, function(ok, reason)
        singleton = nil
        if onDone then onDone(ok, reason) end
    end)
    for _, m in ipairs(moves) do
        singleton:Enqueue(function()
            local live = C_Container.GetContainerItemInfo(m.fromBag, m.fromSlot)
            if not live or live.itemID ~= m.itemID or live.isLocked then return end
            ClearCursor()
            C_Container.PickupContainerItem(m.fromBag, m.fromSlot)
            C_Container.PickupContainerItem(m.toBag, m.toSlot)
            ClearCursor()
        end)
    end
end

function Transfers.DepositReagents(bankType, onDone)
    if OpsBusy() then
        if onDone then onDone(false, "busy") end
        return
    end
    local pairs_list = {}
    for bagID = 0, 5 do
        local size = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, size do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID then
                local isReagent = select(17, C_Item.GetItemInfo(info.itemID))
                if isReagent then
                    local allowed = true
                    if bankType == Enum.BankType.Account then
                        local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
                        allowed = C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc)
                    end
                    if allowed then
                        pairs_list[#pairs_list + 1] = { bag = bagID, slot = slot, itemID = info.itemID }
                    end
                end
            end
        end
    end
    if #pairs_list == 0 then
        if onDone then onDone(true) end
        return
    end
    singleton = RateQueue(RATE_INTERVAL, function(ok, reason)
        singleton = nil
        if onDone then onDone(ok, reason) end
    end)
    for _, p in ipairs(pairs_list) do
        local bag, slot, snapshotID = p.bag, p.slot, p.itemID
        singleton:Enqueue(function()
            local live = C_Container.GetContainerItemInfo(bag, slot)
            if not live or live.itemID ~= snapshotID then return end
            C_Container.UseContainerItem(bag, slot, nil, bankType)
        end)
    end
end

function Transfers.AutoDepositReagentsOnOpen()
    local s = GetSettings()
    if not (s and s.behavior and s.behavior.autoDepositReagents) then return end
    C_Timer.After(0.3, function()
        if not (Bags.BankTakeover and Bags.BankTakeover.IsLive and Bags.BankTakeover.IsLive()) then return end
        if not C_Bank.CanViewBank(Enum.BankType.Account) then return end
        if OpsBusy() then return end
        Transfers.DepositReagents(Enum.BankType.Account)
    end)
end

local SEND_CAPS = { mail = 12, trade = 6 }

function Transfers.ResolveSendDestination(state)
    if not state then return nil end
    if state.bankLive then
        return {
            key = "bank",
            verb = ns.L["Deposit"],
            bankType = state.bankType or Enum.BankType.Character,
        }
    end
    if state.guildLive then return { key = "guild", verb = ns.L["Deposit"] } end
    if state.tradeOpen then return { key = "trade", verb = ns.L["Trade"] } end
    if state.mailSendOpen then return { key = "mail", verb = ns.L["Attach"] } end
    if state.merchantOpen then return { key = "merchant", verb = ns.L["Sell"] } end
    return nil
end

function Transfers.ResolveItemRightClickRoute(state)
    if not state then return nil end
    if state.bankTabSelected then return "bankTab" end
    if state.auctionOpen then return "auction" end
    return nil
end

function Transfers.ResolveDepositTargetSlot(size, occupantAt, sourceItemID, maxStack)
    local firstEmpty = nil
    for s = 1, (size or 0) do
        local occ = occupantAt(s)
        if not occ then
            if not firstEmpty then firstEmpty = s end
        elseif occ.itemID == sourceItemID and not occ.isLocked
            and (maxStack == nil or (maxStack > 1 and occ.stackCount < maxStack)) then
            return nil
        end
    end
    return firstEmpty
end

function Transfers.UseSelected(cells, dest, onDone)
    if OpsBusy() then
        if onDone then onDone(false, "busy") end
        return
    end
    local cap = dest and SEND_CAPS[dest.key]
    local list = {}
    for i = 1, #cells do
        if cap and #list >= cap then break end
        list[#list + 1] = cells[i]
    end
    if #list == 0 then
        if onDone then onDone(true) end
        return
    end
    local bankType = nil
    if dest and dest.key == "bank" then
        bankType = dest.bankType or Enum.BankType.Character
    end
    singleton = RateQueue(RATE_INTERVAL, function(ok, reason)
        singleton = nil
        if onDone then onDone(ok, reason) end
    end)
    for _, p in ipairs(list) do
        local bag, slot, snapshotID = p.bag, p.slot, p.itemID
        singleton:Enqueue(function()
            local live = C_Container.GetContainerItemInfo(bag, slot)
            if not live or live.itemID ~= snapshotID then return end
            C_Container.UseContainerItem(bag, slot, nil, bankType)
        end)
    end
end

function Transfers.OnCombat()
    if singleton then singleton:OnCombat() end
end

function Transfers.Cancel()
    if singleton then singleton:Cancel() end
end

function Transfers.IsRunning()
    return singleton ~= nil
end
