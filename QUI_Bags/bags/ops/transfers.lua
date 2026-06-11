---------------------------------------------------------------------------
-- Bags ops: rate-limited transfer queue + warband deposit-all.
--
-- RateQueue: generic one-item-per-tick paced queue driven by C_Timer chain.
-- Default interval: 0.2s (≈5 ops/sec; slower than the sort executor's bus-
-- paced model because deposit calls go to the server individually and the
-- server will silently drop calls that arrive too fast).
--
-- DepositAllToWarband([onDone]): live-iterates player bags 0–5, builds an
-- ItemLocation per occupied slot, passes it through
--   C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc)
-- and enqueues C_Container.UseContainerItem(bag, slot, nil,
-- Enum.BankType.Account) for each allowed item. The CALLER (bank_window) is
-- responsible for gating on an open warband bank session before calling
-- this; the function itself only filters by IsItemAllowedInBankType and does
-- no additional bank-side check (there is no API to re-query whether the
-- session is still live per-step).
--
-- C_Container.UseContainerItem signature (ContainerDocumentation.lua,
-- Namespace = "C_Container" — there is no global alias on the modern
-- client):
--   UseContainerItem(containerIndex, slotIndex, unitToken, bankType,
--                    reagentBankOpen=false)
-- bankType = Enum.BankType.Account triggers the deposit path.
--
-- C_Bank.IsItemAllowedInBankType(bankType, itemLocation) — verified:
--   bankType first, returns non-nilable bool; SecretArguments = AllowedWhenUntainted.
--
-- ItemLocation:CreateFromBagAndSlot(bagID, slotIndex) — verified in
--   Blizzard_ObjectAPI/Mainline/ItemLocation.lua: static method on the
--   `ItemLocation` global (a mixin table, not a C_ namespace), available at
--   all times (loaded with the ObjectAPI LoD addon, present by the time any
--   bag interaction runs).
--
-- Combat: bags.lua routes PLAYER_REGEN_DISABLED → Transfers.OnCombat()
-- (existence-guarded; already wired in bags.lua at the time this file lands).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local RATE_INTERVAL = 0.2  -- seconds between UseContainerItem calls

-- Informational house print prefix (mirrors sort_executor.lua's PREFIX).
local PREFIX = "|cFF30D1FFQUI:|r"

---------------------------------------------------------------------------
-- RateQueue constructor (returned as Transfers.RateQueue for test access
-- and for Junk.SellJunk which wants its own independent queue instance).
--
-- Usage:
--   local q = Transfers.RateQueue([interval[, onDone]])
--   q:Enqueue(fn)   -- fn() called on its scheduled tick
--   q:IsRunning()   -- bool
--   q:Cancel()      -- abort; onDone(false, "cancel")
--   q:OnCombat()    -- abort; onDone(false, "combat")
--
-- Pacing model: the first Enqueue fires the function immediately (no timer
-- delay so the UI feels responsive), then schedules a C_Timer.After for the
-- next item. Subsequent items each schedule the one after them. When the
-- queue drains, onDone(true) fires. A guard token makes stale timer callbacks
-- (from before a Cancel/OnCombat) inert.
---------------------------------------------------------------------------
local function RateQueue(interval, onDone)
    interval = interval or RATE_INTERVAL
    local q = {}
    local queue   = {}    -- pending fn list (FIFO)
    local running = false -- true between first Enqueue and finish
    local token   = nil   -- identity guard for the active timer callback

    local function finish(ok, reason)
        running = false
        token   = nil   -- invalidate any pending timer
        queue   = {}
        if onDone then onDone(ok, reason) end
    end

    -- Schedule the next timer tick.  The timer callback runs the next queued
    -- item (if any) or finishes the run.  Staleness-checked via token so that
    -- Cancel/OnCombat between scheduling and firing is a no-op.
    local function scheduleNext(myToken)
        C_Timer.After(interval, function()
            if token ~= myToken then return end  -- stale: aborted since scheduling
            if #queue == 0 then
                finish(true)
                return
            end
            local fn = table.remove(queue, 1)
            fn()
            if #queue == 0 then
                -- Nothing more to do; finish without scheduling another timer.
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
            -- Queue was idle: start it.  Run the first item immediately so
            -- the operation feels responsive, then schedule a timer for the
            -- rest.  `running` is set BEFORE executing fn so IsRunning() is
            -- true even if fn itself calls Enqueue again.
            running = true
            local startToken = {}
            token = startToken
            local first = table.remove(queue, 1)
            first()
            -- After the synchronous first run: if no further items were
            -- Enqueued in the same call frame, schedule the drain timer.
            -- That timer will finish(true) when it sees an empty queue.
            if running then  -- guard: fn() could have called Cancel/OnCombat
                scheduleNext(startToken)
            end
        end
        -- If already running, the item was appended and the active timer
        -- chain will pick it up on its next scheduleNext invocation.
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

---------------------------------------------------------------------------
-- Module-level singleton queue used by DepositAllToWarband (and later by
-- Junk.SellJunk, which will create its own RateQueue instance instead).
-- Exposed via Transfers.IsRunning / Transfers.Cancel / Transfers.OnCombat
-- so bags.lua's PLAYER_REGEN_DISABLED route can reach it.
---------------------------------------------------------------------------
local singleton = nil

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
local Transfers = {}
Bags.Transfers = Transfers

-- Expose the constructor for Junk and tests.
Transfers.RateQueue = RateQueue

--- Deposit all warband-allowed items from player bags 0–5 into the warband
--- bank (Enum.BankType.Account). The caller must gate on an open warband
--- bank session; this function only filters by IsItemAllowedInBankType and
--- does not re-check the session state per step.
---
--- onDone(ok[, reason]) fires once: (true) all items deposited, or
--- (false, "combat"|"cancel") if aborted; refused outright with
--- (false, "busy") while any cursor/slot op (sort, deposit, sell) runs.
--- Shared refusal gate for cursor/slot ops (sort, deposit, sell, fill):
--- they must never overlap (wrong-item hazards).
local function OpsBusy()
    return (Bags.SortExecutor and Bags.SortExecutor.IsRunning and Bags.SortExecutor.IsRunning())
        or (Bags.Transfers and Bags.Transfers.IsRunning and Bags.Transfers.IsRunning())
        or (Bags.Junk and Bags.Junk.IsSelling and Bags.Junk.IsSelling())
end

function Transfers.DepositAllToWarband(onDone)
    -- shared ops gate: cursor/slot ops must never overlap (wrong-item hazards)
    if OpsBusy() then
        if onDone then onDone(false, "busy") end
        return
    end

    -- Build the full list of (bag, slot) pairs that pass the filter now, so
    -- the queue is deterministic regardless of mid-run bag changes. Live reads
    -- are cheap at this point (at most 6×36 = 216 GetContainerItemInfo calls).
    -- The occupant itemID is snapshotted alongside for per-tick re-validation.
    local pairs_list = {}
    for bagID = 0, 5 do
        local size = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, size do
            -- GetContainerItemInfo: MayReturnNothing — guard nil
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info then
                local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
                if C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc) then
                    pairs_list[#pairs_list + 1] = { bag = bagID, slot = slot, itemID = info.itemID }
                end
            end
        end
    end

    -- Empty bags → immediate success, nothing to queue.
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
            -- Per-tick re-validation: items can move under a queue (user
            -- drags); never act on a slot whose occupant changed.
            local live = C_Container.GetContainerItemInfo(bag, slot)
            if not live or live.itemID ~= snapshotID then return end
            -- C_Container.UseContainerItem with bankType =
            -- Enum.BankType.Account triggers the deposit path
            -- (ContainerDocumentation: 5-arg form; unitToken nil = self;
            -- reagentBankOpen defaults false).
            C_Container.UseContainerItem(bag, slot, nil, Enum.BankType.Account)
        end)
    end
end

--- Sweep crafting reagents from bags 0–4 into the reagent bag (bag 5):
--- merge into its partial stacks first, then fill empty slots. Plans once
--- against live state (ReagentFill.Plan over the sort executor's container
--- reader), executes through the paced queue with per-move source
--- re-validation. onDone(ok[, reason]) as elsewhere.
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
        print(PREFIX .. " No reagents to move (no reagent bag, no fitting items, or it's full).")
        if onDone then onDone(true) end
        return
    end
    singleton = RateQueue(RATE_INTERVAL, function(ok, reason)
        singleton = nil
        if onDone then onDone(ok, reason) end
    end)
    for _, m in ipairs(moves) do
        singleton:Enqueue(function()
            -- Source re-validation: never act on a slot whose occupant changed.
            local live = C_Container.GetContainerItemInfo(m.fromBag, m.fromSlot)
            if not live or live.itemID ~= m.itemID or live.isLocked then return end
            ClearCursor()
            C_Container.PickupContainerItem(m.fromBag, m.fromSlot)
            C_Container.PickupContainerItem(m.toBag, m.toSlot)
            ClearCursor()
        end)
    end
end

--- Deposit all crafting reagents from bags 0–5 into the given bank type.
--- isCraftingReagent = C_Item.GetItemInfo return 17 (ItemDocumentation:617);
--- uncached items return nothing and are skipped (rare for carried
--- reagents). Account deposits additionally pass IsItemAllowedInBankType.
--- The caller gates on an open bank session, as with DepositAllToWarband.
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

--- behavior.autoDepositReagents: on a live bank open, deposit reagents into
--- the warband bank (account-wide reagent storage is the point; character-
--- only bankers no-op). Deferred a beat so the session fully settles.
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

---------------------------------------------------------------------------
-- Send-selected: the bag window's multi-select batch transfer.
---------------------------------------------------------------------------

-- Per-destination caps (verified in vendored FrameXML: MailFrame.lua:4
-- ATTACHMENTS_MAX_SEND = 12; TradeFrame.lua:2 MAX_TRADABLE_ITEMS = 6).
local SEND_CAPS = { mail = 12, trade = 6 }

--- Which destination can take the current selection? state = booleans
--- { bankLive, bankType, guildLive, tradeOpen, mailSendOpen, merchantOpen } (the
--- caller reads the live surfaces; this stays pure). Priority settles
--- pathological overlaps: bank > guild > trade > mail > merchant.
--- → { key, verb[, bankType] } or nil when nothing is open (button hidden).
function Transfers.ResolveSendDestination(state)
    if not state then return nil end
    if state.bankLive then
        return {
            key = "bank",
            verb = "Deposit",
            bankType = state.bankType or Enum.BankType.Character,
        }
    end
    if state.guildLive then return { key = "guild", verb = "Deposit" } end
    if state.tradeOpen then return { key = "trade", verb = "Trade" } end
    if state.mailSendOpen then return { key = "mail", verb = "Attach" } end
    if state.merchantOpen then return { key = "merchant", verb = "Sell" } end
    return nil
end

--- Which destination owns a targeted right-click on a live bag item button?
--- state = booleans { bankTabSelected, auctionOpen } (the caller reads the
--- live surfaces; this stays pure). A banker and an auctioneer can't be
--- open at once — the priority just settles pathological overlaps.
--- → "bankTab" | "auction" | nil (catcher hidden, the template's own
--- OnClick handles the click).
function Transfers.ResolveItemRightClickRoute(state)
    if not state then return nil end
    if state.bankTabSelected then return "bankTab" end
    if state.auctionOpen then return "auction" end
    return nil
end

--- Send a snapshot list of cells ({ bag, slot, itemID }) to dest (from
--- ResolveSendDestination). Same machinery as DepositAllToWarband: the
--- shared ops gate, the paced queue, per-tick occupant re-validation.
--- UseContainerItem routes by the OPEN interaction for guild/mail/trade/
--- merchant (no bankType); the bank destination passes its explicit bankType
--- (the deposit path needs it).
--- Destination caps truncate the queue (mail 12, trade 6).
function Transfers.UseSelected(cells, dest, onDone)
    if (Bags.SortExecutor and Bags.SortExecutor.IsRunning and Bags.SortExecutor.IsRunning())
        or Transfers.IsRunning()
        or (Bags.Junk and Bags.Junk.IsSelling and Bags.Junk.IsSelling()) then
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
            -- never act on a slot whose occupant changed under the queue
            local live = C_Container.GetContainerItemInfo(bag, slot)
            if not live or live.itemID ~= snapshotID then return end
            C_Container.UseContainerItem(bag, slot, nil, bankType)
        end)
    end
end

--- Combat abort — bags.lua routes PLAYER_REGEN_DISABLED here.
function Transfers.OnCombat()
    if singleton then singleton:OnCombat() end
end

--- User abort.
function Transfers.Cancel()
    if singleton then singleton:Cancel() end
end

--- True while a DepositAllToWarband run is in progress.
function Transfers.IsRunning()
    return singleton ~= nil
end
