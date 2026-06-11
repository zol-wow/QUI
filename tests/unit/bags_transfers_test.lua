-- tests/unit/bags_transfers_test.lua
-- Run: lua tests/unit/bags_transfers_test.lua
-- TDD for Bags.Transfers: generic RateQueue + DepositAllToWarband (incl.
-- the shared ops gate + per-tick slot re-validation).
-- WoW surface stubs: C_Timer (capture/fire), C_Container, C_Bank,
-- ItemLocation, Enum; all combat/cursor state mutable between sections.
local loader = dofile("tests/helpers/load_bags_data.lua")

---------------------------------------------------------------------------
-- Mutable test state
---------------------------------------------------------------------------
local timers          -- { {delay, fn}, ... } captured C_Timer.After calls
local deposits        -- { {bag, slot, bankType}, ... } UseContainerItem calls
local allowed         -- fn(bag, slot) → bool (IsItemAllowedInBankType filter)
local inCombat        -- bool
local bagContents     -- [bagID][slot] = { itemID } | nil
local printed         -- captured print lines

local function reset()
    timers   = {}
    deposits = {}
    allowed  = function() return true end
    inCombat = false
    bagContents = {}
    printed  = {}
end

local function fireNext()
    -- fire the earliest-captured timer and remove it
    assert(#timers > 0, "fireNext: no pending timer")
    local t = table.remove(timers, 1)
    t.fn()
end

local function fireAll()
    local batch = timers
    timers = {}
    for _, t in ipairs(batch) do t.fn() end
end

---------------------------------------------------------------------------
-- WoW surface stubs
---------------------------------------------------------------------------
_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
_G.InCombatLockdown = function() return inCombat end
_G.Enum = _G.Enum or {}
_G.Enum.BankType = _G.Enum.BankType or { Character = 0, Guild = 1, Account = 2 }

-- C_Container: expose per-bag slot counts + occupied-slot info, and capture
-- deposit calls. UseContainerItem lives in the C_Container namespace
-- (ContainerDocumentation.lua: Namespace = "C_Container"); the modern
-- client has no global alias.
_G.C_Container = _G.C_Container or {}
_G.C_Container.UseContainerItem = function(bag, slot, unit, bankType)
    deposits[#deposits + 1] = { bag = bag, slot = slot, unit = unit, bankType = bankType }
end
_G.C_Container.GetContainerNumSlots = function(bagID)
    local bag = bagContents[bagID]
    if not bag then return 0 end
    local max = 0
    for slot in pairs(bag) do
        if slot > max then max = slot end
    end
    return max
end
_G.C_Container.GetContainerItemInfo = function(bagID, slot)
    local bag = bagContents[bagID]
    local cell = bag and bag[slot]
    if not cell then return nil end
    return { itemID = cell.itemID, stackCount = 1, quality = 1, isLocked = false }
end

-- ItemLocation mixin (mirrors the real ObjectAPI implementation exactly)
_G.ItemLocation = {
    CreateFromBagAndSlot = function(_, bagID, slotIndex)
        return { _bagID = bagID, _slotIndex = slotIndex }
    end,
}

-- C_Bank.IsItemAllowedInBankType: delegates to the mutable `allowed` stub
_G.C_Bank = _G.C_Bank or {}
_G.C_Bank.IsItemAllowedInBankType = function(bankType, loc)
    return allowed(loc._bagID, loc._slotIndex)
end

reset()

---------------------------------------------------------------------------
-- Load production file under test
---------------------------------------------------------------------------
local ns = { Helpers = { CreateDBGetter = function() return function() return {} end end } }
assert(loadfile("QUI_Bags/bags/ops/transfers.lua"))("QUI", ns)

local Transfers = ns.Bags.Transfers
assert(Transfers, "Bags.Transfers must be defined")
assert(type(Transfers.RateQueue) == "function", "RateQueue constructor required")
assert(type(Transfers.DepositAllToWarband) == "function", "DepositAllToWarband required")
assert(type(Transfers.IsRunning) == "function", "IsRunning required")
assert(type(Transfers.Cancel) == "function", "Cancel required")
assert(type(Transfers.OnCombat) == "function", "OnCombat required")

local realPrint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Section 1: RateQueue pacing — enqueued functions run one per timer fire,
-- FIFO order; IsRunning reflects lifecycle.
---------------------------------------------------------------------------
do
    reset()
    local q = Transfers.RateQueue()
    assert(not q:IsRunning(), "idle queue must not report running")

    local order = {}
    q:Enqueue(function() order[#order + 1] = 1 end)
    q:Enqueue(function() order[#order + 1] = 2 end)
    q:Enqueue(function() order[#order + 1] = 3 end)

    assert(q:IsRunning(), "queue must be running after Enqueue")
    -- first function runs immediately (no timer for item 1); timer set for item 2
    assert(order[1] == 1, "first fn must run on Enqueue, got: " .. tostring(order[1]))
    assert(#timers == 1, "one timer must be pending after first run, got " .. #timers)
    assert(#order == 1, "only the first fn must have run yet")

    fireNext()
    assert(order[2] == 2, "second fn must run on first timer fire")
    assert(#timers == 1, "one timer pending for item 3")

    fireNext()
    assert(order[3] == 3, "third fn must run on second timer fire")
    assert(#timers == 0, "no timers pending after last item")
    assert(not q:IsRunning(), "queue must be idle after drain")
end

---------------------------------------------------------------------------
-- Section 2: Pacing — default interval is positive (0.2s); timer delay
-- matches the configured interval.
---------------------------------------------------------------------------
do
    reset()
    local q = Transfers.RateQueue()
    q:Enqueue(function() end)
    q:Enqueue(function() end)
    assert(#timers == 1, "one pending timer after first fn ran")
    local delay = timers[1].delay
    assert(type(delay) == "number" and delay > 0,
        "timer delay must be a positive number, got: " .. tostring(delay))
    fireAll()
end

---------------------------------------------------------------------------
-- Section 3: Cancel stops mid-queue (remaining fns do not run; pending
-- timers that fire afterwards are inert). onDone(false, "cancel").
---------------------------------------------------------------------------
do
    reset()
    local doneOk, doneReason, doneCalls = nil, nil, 0
    local q = Transfers.RateQueue(nil, function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)

    local ran = {}
    q:Enqueue(function() ran[#ran + 1] = 1 end)
    q:Enqueue(function() ran[#ran + 1] = 2 end)
    q:Enqueue(function() ran[#ran + 1] = 3 end)

    -- fn 1 ran immediately; cancel before fn 2 fires
    assert(ran[1] == 1, "fn 1 must have run")
    q:Cancel()
    assert(not q:IsRunning(), "Cancel must clear the running state")
    assert(doneCalls == 1 and doneOk == false and doneReason == "cancel",
        "Cancel must call onDone(false, 'cancel')")

    -- stale timer still pending; firing it must be a no-op
    local before = #ran
    fireAll()
    assert(#ran == before, "stale timer after Cancel must not run further fns")
    assert(doneCalls == 1, "onDone must not be called again by stale timer")
end

---------------------------------------------------------------------------
-- Section 4: OnCombat aborts the queue with onDone(false, "combat");
-- stale timers are inert afterwards.
---------------------------------------------------------------------------
do
    reset()
    local doneOk, doneReason, doneCalls = nil, nil, 0
    local q = Transfers.RateQueue(nil, function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)

    local ran = {}
    q:Enqueue(function() ran[#ran + 1] = 1 end)
    q:Enqueue(function() ran[#ran + 1] = 2 end)

    assert(ran[1] == 1, "precondition: fn 1 ran")
    q:OnCombat()
    assert(not q:IsRunning(), "OnCombat must clear the running state")
    assert(doneCalls == 1 and doneOk == false and doneReason == "combat",
        "OnCombat must call onDone(false, 'combat')")

    local before = #ran
    fireAll()
    assert(#ran == before, "stale timer after OnCombat must not run further fns")
    assert(doneCalls == 1, "onDone must not be called again by stale timer")

    -- idle OnCombat is a no-op (no second onDone)
    q:OnCombat()
    assert(doneCalls == 1, "idle OnCombat must not re-fire onDone")
end

---------------------------------------------------------------------------
-- Section 5: Global Transfers.OnCombat() aborts the active deposit queue
-- (the module-level singleton used by DepositAllToWarband). Simulates the
-- bags.lua PLAYER_REGEN_DISABLED route.
---------------------------------------------------------------------------
do
    reset()
    -- put one slot in bag 0 so DepositAllToWarband enqueues something
    bagContents[0] = { [1] = { itemID = 1 } }
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Transfers.DepositAllToWarband(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(Transfers.IsRunning(), "DepositAllToWarband must start the singleton queue")
    Transfers.OnCombat()
    assert(not Transfers.IsRunning(), "OnCombat must clear the singleton queue")
    assert(doneCalls == 1 and doneOk == false and doneReason == "combat",
        "OnCombat must deliver (false, 'combat') to the caller's onDone")
    fireAll() -- stale timers inert
    assert(doneCalls == 1, "no second onDone after OnCombat")
end

---------------------------------------------------------------------------
-- Section 6: IsRunning lifecycle on the module-level singleton (mirrors
-- what DepositAllToWarband exposes via Transfers.IsRunning).
---------------------------------------------------------------------------
do
    reset()
    assert(not Transfers.IsRunning(), "must be idle before any call")

    bagContents[0] = { [1] = { itemID = 1 }, [2] = { itemID = 2 } }
    Transfers.DepositAllToWarband()
    assert(Transfers.IsRunning(), "must be running while items are queued")

    -- drain the queue
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    -- after drain, still one more timer fires to signal completion
    if Transfers.IsRunning() then fireNext() end
    assert(not Transfers.IsRunning(), "must be idle after drain")
end

---------------------------------------------------------------------------
-- Section 7: DepositAllToWarband enqueues exactly the allowed items.
-- IsItemAllowedInBankType stub: allow odd slots only.
-- UseContainerItem must be called with Enum.BankType.Account as bankType.
---------------------------------------------------------------------------
do
    reset()
    -- bag 0: slots 1–4 occupied; allowed = odd slots (1 and 3)
    bagContents[0] = {
        [1] = { itemID = 10 },
        [2] = { itemID = 20 },
        [3] = { itemID = 30 },
        [4] = { itemID = 40 },
    }
    allowed = function(bag, slot)
        return (bag == 0) and (slot % 2 == 1) -- odd slots only
    end

    local doneOk, doneCalls = nil, 0
    Transfers.DepositAllToWarband(function(ok)
        doneOk, doneCalls = ok, doneCalls + 1
    end)

    -- drain the queue completely
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    if Transfers.IsRunning() then fireNext() end -- last possible timer
    -- allow convergence
    for _ = 1, 10 do
        if not Transfers.IsRunning() then break end
        fireNext()
    end

    assert(doneCalls == 1, "onDone must be called exactly once, got " .. doneCalls)
    assert(doneOk == true, "onDone must receive true on success")

    -- exactly 2 deposits (slots 1 and 3)
    assert(#deposits == 2, "must deposit exactly the 2 allowed items, got " .. #deposits)

    -- both must carry Enum.BankType.Account
    for i, d in ipairs(deposits) do
        assert(d.bankType == _G.Enum.BankType.Account,
            "deposit " .. i .. " must use BankType.Account, got " .. tostring(d.bankType))
    end

    -- FIFO slot order: slot 1 then slot 3
    assert(deposits[1].bag == 0 and deposits[1].slot == 1,
        "first deposit must be bag 0, slot 1, got bag=" .. tostring(deposits[1].bag) ..
        " slot=" .. tostring(deposits[1].slot))
    assert(deposits[2].bag == 0 and deposits[2].slot == 3,
        "second deposit must be bag 0, slot 3, got bag=" .. tostring(deposits[2].bag) ..
        " slot=" .. tostring(deposits[2].slot))
end

---------------------------------------------------------------------------
-- Section 8: DepositAllToWarband across multiple player bags (0–5).
---------------------------------------------------------------------------
do
    reset()
    allowed = function() return true end
    bagContents[0] = { [1] = { itemID = 1 } }
    bagContents[2] = { [1] = { itemID = 2 } }
    bagContents[5] = { [1] = { itemID = 3 } }
    -- bags 1, 3, 4 = empty (no entry)

    Transfers.DepositAllToWarband()
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    if Transfers.IsRunning() then fireNext() end

    assert(#deposits == 3, "must deposit items from all occupied bags 0-5, got " .. #deposits)
end

---------------------------------------------------------------------------
-- Section 9: Empty bags → immediate onDone(true), no UseContainerItem
-- calls, no timers scheduled.
---------------------------------------------------------------------------
do
    reset()
    -- bagContents empty: all bags report size 0
    local doneOk, doneCalls = nil, 0
    Transfers.DepositAllToWarband(function(ok)
        doneOk, doneCalls = ok, doneCalls + 1
    end)
    assert(doneCalls == 1 and doneOk == true,
        "empty bags must call onDone(true) immediately")
    assert(#deposits == 0, "empty bags must not call UseContainerItem")
    assert(#timers == 0, "empty bags must not schedule any timers")
    assert(not Transfers.IsRunning(), "must be idle after empty-bags call")
end

---------------------------------------------------------------------------
-- Section 10: Cancel singleton via Transfers.Cancel().
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = { itemID = 1 }, [2] = { itemID = 2 }, [3] = { itemID = 3 } }
    allowed = function() return true end
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Transfers.DepositAllToWarband(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(Transfers.IsRunning(), "must be running")
    -- item 1 already deposited; cancel before item 2
    Transfers.Cancel()
    assert(not Transfers.IsRunning(), "Cancel must clear the running state")
    assert(doneCalls == 1 and doneOk == false and doneReason == "cancel",
        "Cancel must deliver (false, 'cancel') to onDone")
    local before = #deposits
    fireAll()
    assert(#deposits == before, "stale timer after Cancel must not deposit further")
end

---------------------------------------------------------------------------
-- Section 11: per-tick re-validation — a slot whose occupant changed (or
-- vacated) between enqueue and its tick is SKIPPED, not deposited and not
-- failed; the run still completes with onDone(true).
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = {
        [1] = { itemID = 1 },
        [2] = { itemID = 2 },
        [3] = { itemID = 3 },
    }
    local doneOk, doneCalls = nil, 0
    Transfers.DepositAllToWarband(function(ok) doneOk, doneCalls = ok, doneCalls + 1 end)
    assert(#deposits == 1, "precondition: slot 1 deposited synchronously")
    -- mid-run: the user drags a different item into slot 2 and empties slot 3
    bagContents[0][2] = { itemID = 99 }
    bagContents[0][3] = nil
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    if Transfers.IsRunning() then fireNext() end
    assert(doneCalls == 1 and doneOk == true,
        "skipped slots must not fail the run (onDone(true) expected)")
    assert(#deposits == 1,
        "changed/vacated occupants must be skipped, got " .. #deposits .. " deposits")
    for _, d in ipairs(deposits) do
        assert(not (d.bag == 0 and (d.slot == 2 or d.slot == 3)),
            "a slot whose occupant changed must never reach UseContainerItem")
    end
end

---------------------------------------------------------------------------
-- Section 12: shared ops gate — DepositAllToWarband refuses with
-- (false, "busy") while a sibling cursor/slot op (sort, sell) runs;
-- nothing is queued and nothing reaches the API.
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = { itemID = 1 } }

    ns.Bags.SortExecutor = { IsRunning = function() return true end }
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Transfers.DepositAllToWarband(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(doneCalls == 1 and doneOk == false and doneReason == "busy",
        "deposit while a sort runs must refuse with (false, 'busy')")
    assert(#deposits == 0 and #timers == 0,
        "busy refusal must not deposit or schedule")
    assert(not Transfers.IsRunning(), "busy refusal must not enter the running state")
    ns.Bags.SortExecutor = nil

    ns.Bags.Junk = { IsSelling = function() return true end }
    doneCalls = 0
    Transfers.DepositAllToWarband(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(doneCalls == 1 and doneOk == false and doneReason == "busy",
        "deposit while a sell runs must refuse with (false, 'busy')")
    assert(#deposits == 0 and #timers == 0,
        "busy refusal must not deposit or schedule")
    ns.Bags.Junk = nil

    -- gate lifted: the same call goes through
    Transfers.DepositAllToWarband()
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    if Transfers.IsRunning() then fireNext() end
    assert(#deposits == 1, "deposit must proceed once the sibling op is idle")
end

---------------------------------------------------------------------------
-- Section N: send-selected — ResolveSendDestination (pure) + UseSelected
---------------------------------------------------------------------------
do
    reset()
    -- destination resolution: one open surface at a time in practice; the
    -- priority order settles pathological overlaps deterministically
    local R = Transfers.ResolveSendDestination
    assert(R({ bankLive = true }).key == "bank", "bank session resolves to bank")
    assert(R({ bankLive = true }).verb == "Deposit", "bank verb")
    assert(R({ guildLive = true }).key == "guild", "guild session resolves to guild")
    assert(R({ tradeOpen = true }).key == "trade", "trade resolves to trade")
    assert(R({ mailSendOpen = true }).key == "mail", "send-mail resolves to mail")
    assert(R({ mailSendOpen = true }).verb == "Attach", "mail verb")
    assert(R({ merchantOpen = true }).key == "merchant", "merchant resolves to sell")
    assert(R({}) == nil, "no open surface → nil (button hidden)")
    assert(R({ bankLive = true, merchantOpen = true }).key == "bank",
        "bank outranks merchant on overlap")

    -- UseSelected: snapshot list → paced UseContainerItem calls with
    -- per-tick occupant re-validation; bank carries the Character bankType
    bagContents[0] = { [1] = { itemID = 100 }, [2] = { itemID = 200 }, [3] = { itemID = 300 } }
    local doneOK = nil
    Transfers.UseSelected({
        { bag = 0, slot = 1, itemID = 100 },
        { bag = 0, slot = 2, itemID = 999 }, -- stale snapshot: occupant changed
        { bag = 0, slot = 3, itemID = 300 },
    }, { key = "bank" }, function(ok) doneOK = ok end)
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    assert(doneOK == true, "UseSelected must complete")
    assert(#deposits == 2, "stale snapshot must be skipped, got " .. #deposits)
    assert(deposits[1].bag == 0 and deposits[1].slot == 1
        and deposits[1].bankType == Enum.BankType.Character,
        "bank destination must pass the Character bankType")
    assert(deposits[2].slot == 3, "valid cells deposit in order")

    reset()
    bagContents[0] = { [1] = { itemID = 701 } }
    doneOK = nil
    Transfers.UseSelected({ { bag = 0, slot = 1, itemID = 701 } },
        { key = "bank", verb = "Deposit", bankType = Enum.BankType.Account },
        function(ok) doneOK = ok end)
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    assert(doneOK == true, "warband selected transfer must finish")
    assert(#deposits == 1 and deposits[1].bankType == Enum.BankType.Account,
        "selected transfer to warband bank must pass Enum.BankType.Account")

    -- non-bank destinations: plain UseContainerItem (no bankType — the
    -- server routes by the open interaction)
    reset()
    bagContents[0] = { [1] = { itemID = 100 } }
    Transfers.UseSelected({ { bag = 0, slot = 1, itemID = 100 } }, { key = "mail" })
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    assert(#deposits == 1 and deposits[1].bankType == nil,
        "mail/trade/guild/merchant sends must not pass a bankType")

    -- caps: mail 12 (ATTACHMENTS_MAX_SEND), trade 6 (MAX_TRADABLE_ITEMS)
    reset()
    local many = {}
    bagContents[0] = {}
    for slot = 1, 15 do
        bagContents[0][slot] = { itemID = slot }
        many[slot] = { bag = 0, slot = slot, itemID = slot }
    end
    Transfers.UseSelected(many, { key = "mail" })
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    assert(#deposits == 12, "mail sends cap at 12 attachments, got " .. #deposits)
    reset()
    bagContents[0] = {}
    many = {}
    for slot = 1, 9 do
        bagContents[0][slot] = { itemID = slot }
        many[slot] = { bag = 0, slot = slot, itemID = slot }
    end
    Transfers.UseSelected(many, { key = "trade" })
    while Transfers.IsRunning() and #timers > 0 do fireNext() end
    assert(#deposits == 6, "trade sends cap at 6 tradable slots, got " .. #deposits)

    -- busy gate: refused while another transfer runs
    reset()
    bagContents[0] = { [1] = { itemID = 1 }, [2] = { itemID = 2 } }
    Transfers.UseSelected({
        { bag = 0, slot = 1, itemID = 1 },
        { bag = 0, slot = 2, itemID = 2 },
    }, { key = "guild" })
    assert(Transfers.IsRunning(), "queue must be running mid-send")
    local refusedReason = nil
    Transfers.UseSelected({ { bag = 0, slot = 2, itemID = 2 } }, { key = "guild" },
        function(ok, reason) refusedReason = reason end)
    assert(refusedReason == "busy", "overlapping send must refuse with busy")
    while Transfers.IsRunning() and #timers > 0 do fireNext() end

    -- empty selection: immediate success, no calls
    reset()
    local emptyOK = nil
    Transfers.UseSelected({}, { key = "bank" }, function(ok) emptyOK = ok end)
    assert(emptyOK == true and #deposits == 0, "empty selection → immediate done")
end

---------------------------------------------------------------------------
-- Section: targeted right-click route (pure) — bank-tab deposit vs auction
-- post. Drives the bag window's per-button right-click catcher: nil hides
-- the catcher (the template's own OnClick handles the click).
---------------------------------------------------------------------------
do
    reset()
    local R = Transfers.ResolveItemRightClickRoute
    assert(R(nil) == nil, "nil state → nil")
    assert(R({}) == nil, "nothing open → nil (catcher hidden)")
    assert(R({ bankTabSelected = true }) == "bankTab",
        "live bank tab routes the targeted deposit")
    assert(R({ auctionOpen = true }) == "auction",
        "open auction house routes the sell post")
    assert(R({ bankTabSelected = true, auctionOpen = true }) == "bankTab",
        "bank tab outranks auction on (pathological) overlap")
end

_G.print = realPrint
print("OK: bags_transfers_test")
