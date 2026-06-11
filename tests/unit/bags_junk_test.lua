-- tests/unit/bags_junk_test.lua
-- Run: lua tests/unit/bags_junk_test.lua
-- TDD for Bags.Junk: junk eligibility (IsJunk matrix), merchant gate,
-- SellJunk via a RateQueue (only eligible items, bankType-free sells,
-- count + coin summary), exclusions + ExcludeJunkSell flag honored,
-- MerchantChanged bus publish on OnMerchant.
-- WoW surface stubs: C_Timer (capture/fire), C_Container (live bags +
-- junk-sell flags), C_Item.GetItemInfo (sellPrice = position 11),
-- C_CurrencyInfo.GetCoinTextureString, C_Container.UseContainerItem capture.

---------------------------------------------------------------------------
-- Mutable test state
---------------------------------------------------------------------------
local timers          -- { {delay, fn}, ... } captured C_Timer.After calls
local sells           -- { {bag, slot, unit, bankType}, ... } UseContainerItem calls
local bagContents     -- [bagID][slot] = liveInfo table | nil
local bagJunkFlag     -- [bagID] = true → ExcludeJunkSell flag set (bags 1–5)
local backpackJunkOff -- bool → GetBackpackSellJunkDisabled() (bag 0)
local itemDB          -- [itemID] = { sellPrice = n } | nil (nil = info not cached)
local printed         -- captured print lines
local settings        -- what Helpers.CreateDBGetter("bags") returns

local function reset()
    timers          = {}
    sells           = {}
    bagContents     = {}
    bagJunkFlag     = {}
    backpackJunkOff = false
    itemDB          = {}
    printed         = {}
    settings        = {
        behavior = {
            junk = { dim = true, sellButton = true, exclusions = {} },
        },
    }
end

local function fireNext()
    assert(#timers > 0, "fireNext: no pending timer")
    local t = table.remove(timers, 1)
    t.fn()
end

local function fireAll()
    local batch = timers
    timers = {}
    for _, t in ipairs(batch) do t.fn() end
end

-- Drain an active sell queue completely (first item ran synchronously on
-- Enqueue; the rest ride the captured C_Timer chain).
local function drain(Junk)
    for _ = 1, 200 do
        if #timers == 0 then break end
        fireNext()
    end
end

---------------------------------------------------------------------------
-- WoW surface stubs
---------------------------------------------------------------------------
_G.geterrorhandler = function() return function(err) error(err, 0) end end
_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
_G.Enum = _G.Enum or {}
_G.Enum.BagSlotFlags = { DisableAutoSort = 1, ExcludeJunkSell = 64 }

-- UseContainerItem lives in the C_Container namespace
-- (ContainerDocumentation.lua: Namespace = "C_Container"); the modern
-- client has no global alias.
_G.C_Container = {
    UseContainerItem = function(bag, slot, unit, bankType)
        sells[#sells + 1] = { bag = bag, slot = slot, unit = unit, bankType = bankType }
    end,
    GetContainerNumSlots = function(bagID)
        local bag = bagContents[bagID]
        if not bag then return 0 end
        local max = 0
        for slot in pairs(bag) do
            if slot > max then max = slot end
        end
        return max
    end,
    GetContainerItemInfo = function(bagID, slot)
        local bag = bagContents[bagID]
        return bag and bag[slot] or nil
    end,
    GetBagSlotFlag = function(bagID, flag)
        assert(flag == _G.Enum.BagSlotFlags.ExcludeJunkSell,
            "junk must query the ExcludeJunkSell flag, got " .. tostring(flag))
        assert(bagID >= 1 and bagID <= 5,
            "GetBagSlotFlag(ExcludeJunkSell) is only valid for held bags 1-5, got bag " .. tostring(bagID))
        return bagJunkFlag[bagID] or false
    end,
    GetBackpackSellJunkDisabled = function()
        return backpackJunkOff
    end,
}

-- GetItemInfo: position 11 = sellPrice (ItemDocumentation.lua, verified).
-- MayReturnNothing: uncached items return zero values.
_G.C_Item = {
    GetItemInfo = function(itemID)
        local rec = itemDB[itemID]
        if not rec then return end
        return "Name" .. itemID, "link", 0, 1, 1, "Misc", "Junk",
            1000, "", 134400, rec.sellPrice
    end,
}

_G.C_CurrencyInfo = {
    GetCoinTextureString = function(copper) return "<" .. tostring(copper) .. "c>" end,
}

reset()

---------------------------------------------------------------------------
-- Load production files under test (bus → transfers → junk, the bags.xml
-- order; junk uses Transfers.RateQueue and publishes on Bags.Bus).
---------------------------------------------------------------------------
local ns = { Helpers = { CreateDBGetter = function() return function() return settings end end } }
assert(loadfile("QUI_Bags/bags/data/bus.lua"))("QUI", ns)
assert(loadfile("QUI_Bags/bags/ops/transfers.lua"))("QUI", ns)
assert(loadfile("QUI_Bags/bags/ops/junk.lua"))("QUI", ns)

local Junk = ns.Bags.Junk
assert(Junk, "Bags.Junk must be defined")
assert(type(Junk.IsJunk) == "function", "IsJunk required")
assert(type(Junk.IsBagExcluded) == "function", "IsBagExcluded required")
assert(type(Junk.OnMerchant) == "function", "OnMerchant required")
assert(type(Junk.IsMerchantOpen) == "function", "IsMerchantOpen required")
assert(type(Junk.SellJunk) == "function", "SellJunk required")
assert(type(Junk.IsSelling) == "function", "IsSelling required (shared ops gate)")
assert(type(Junk.OnCombat) == "function", "OnCombat required (combat routing)")

local realPrint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end

local function live(itemID, quality, opts)
    opts = opts or {}
    return {
        itemID     = itemID,
        quality    = quality,
        stackCount = opts.count or 1,
        hasNoValue = opts.hasNoValue or false,
        isLocked   = false,
    }
end

---------------------------------------------------------------------------
-- Section 1: IsJunk matrix — each gate flips eligibility independently.
-- Base case: quality 0, has value, not excluded, unflagged held bag → junk.
---------------------------------------------------------------------------
do
    reset()
    local none = {}
    assert(Junk.IsJunk(live(101, 0), 1, none) == true,
        "base case: quality-0 sellable item in unflagged bag must be junk")

    -- quality gate: anything but 0 is not junk
    assert(Junk.IsJunk(live(101, 1), 1, none) == false, "quality 1 must not be junk")
    assert(Junk.IsJunk(live(101, 4), 1, none) == false, "quality 4 must not be junk")
    assert(Junk.IsJunk(live(101, nil), 1, none) == false, "nil quality must not be junk")

    -- hasNoValue gate: unsellable junk is not sell-eligible
    assert(Junk.IsJunk(live(101, 0, { hasNoValue = true }), 1, none) == false,
        "hasNoValue item must not be junk")

    -- exclusion gate: user-excluded itemID is not junk
    assert(Junk.IsJunk(live(101, 0), 1, { [101] = true }) == false,
        "excluded itemID must not be junk")
    assert(Junk.IsJunk(live(102, 0), 1, { [101] = true }) == true,
        "exclusion of one itemID must not affect another")

    -- bag-flag gate: ExcludeJunkSell on a held bag blocks its items
    bagJunkFlag[2] = true
    assert(Junk.IsJunk(live(101, 0), 2, none) == false,
        "item in ExcludeJunkSell-flagged bag must not be junk")
    assert(Junk.IsJunk(live(101, 0), 3, none) == true,
        "flag on bag 2 must not affect bag 3")
    bagJunkFlag[2] = nil

    -- nil-tolerance: nil liveInfo / nil exclusions must not error
    assert(Junk.IsJunk(nil, 1, none) == false, "nil liveInfo must not be junk")
    assert(Junk.IsJunk(live(101, 0), 1, nil) == true,
        "nil exclusions must behave like an empty exclusion set")
end

---------------------------------------------------------------------------
-- Section 2: IsBagExcluded — backpack uses GetBackpackSellJunkDisabled
-- (NOT the bag-slot flag; FrameXML ContainerFrame.lua:628-643), held bags
-- 1–5 use GetBagSlotFlag(ExcludeJunkSell), non-player bagIDs → false
-- (the stub asserts GetBagSlotFlag is never called outside 1–5).
---------------------------------------------------------------------------
do
    reset()
    assert(Junk.IsBagExcluded(0) == false, "backpack default: not excluded")
    backpackJunkOff = true
    assert(Junk.IsBagExcluded(0) == true,
        "backpack must follow GetBackpackSellJunkDisabled()")
    assert(Junk.IsJunk(live(101, 0), 0, {}) == false,
        "backpack junk-sell disabled must gate IsJunk for bag 0")
    backpackJunkOff = false

    bagJunkFlag[5] = true
    assert(Junk.IsBagExcluded(5) == true, "held bag 5 must follow the bag-slot flag")
    bagJunkFlag[5] = nil

    -- non-player bagIDs: flag does not apply; the stub errors if queried
    assert(Junk.IsBagExcluded(6) == false, "bank-tab bagID must report false")
    assert(Junk.IsBagExcluded(12) == false, "warband bagID must report false")
    assert(Junk.IsBagExcluded(-1) == false, "negative bagID must report false")
end

---------------------------------------------------------------------------
-- Section 3: merchant gate — closed by default; OnMerchant toggles;
-- SellJunk refuses while closed (no sells, no timers, onDone(false)).
---------------------------------------------------------------------------
do
    reset()
    assert(Junk.IsMerchantOpen() == false, "merchant must start closed")

    bagContents[0] = { [1] = live(101, 0) }
    itemDB[101] = { sellPrice = 10 }
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Junk.SellJunk(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(doneCalls == 1 and doneOk == false and doneReason == "merchant",
        "SellJunk with merchant closed must refuse with (false, 'merchant')")
    assert(#sells == 0, "refused SellJunk must not call UseContainerItem")
    assert(#timers == 0, "refused SellJunk must not schedule timers")

    Junk.OnMerchant(true)
    assert(Junk.IsMerchantOpen() == true, "OnMerchant(true) must open the gate")
    Junk.OnMerchant(false)
    assert(Junk.IsMerchantOpen() == false, "OnMerchant(false) must close the gate")
end

---------------------------------------------------------------------------
-- Section 4: OnMerchant publishes MerchantChanged on the bus, both ways.
---------------------------------------------------------------------------
do
    reset()
    local pings = {}
    local handler = function(_, shown) pings[#pings + 1] = shown end
    ns.Bags.Bus.Subscribe("MerchantChanged", handler)
    Junk.OnMerchant(true)
    Junk.OnMerchant(false)
    assert(#pings == 2 and pings[1] == true and pings[2] == false,
        "OnMerchant must publish MerchantChanged(shown) both ways")
    ns.Bags.Bus.Unsubscribe("MerchantChanged", handler)
end

---------------------------------------------------------------------------
-- Section 5: SellJunk sells exactly the eligible items, bankType-free, and
-- reports count + coin total. Mixed bag:
--   bag 0 slot 1: junk, price 10, stack 3   → sold, +30
--   bag 0 slot 2: quality 1                 → kept
--   bag 1 slot 1: junk, hasNoValue          → kept
--   bag 1 slot 2: junk, excluded itemID     → kept
--   bag 2 slot 1: junk in flagged bag       → kept (ExcludeJunkSell)
--   bag 3 slot 1: junk, price 7, stack 1    → sold, +7
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = {
        [1] = live(101, 0, { count = 3 }),
        [2] = live(102, 1),
    }
    bagContents[1] = {
        [1] = live(103, 0, { hasNoValue = true }),
        [2] = live(104, 0),
    }
    bagContents[2] = { [1] = live(105, 0) }
    bagContents[3] = { [1] = live(106, 0) }
    bagJunkFlag[2] = true
    settings.behavior.junk.exclusions = { [104] = true }
    itemDB[101] = { sellPrice = 10 }
    itemDB[104] = { sellPrice = 99 }  -- excluded: must not be sold or counted
    itemDB[106] = { sellPrice = 7 }

    Junk.OnMerchant(true)
    local doneOk, doneCalls = nil, 0
    Junk.SellJunk(function(ok) doneOk, doneCalls = ok, doneCalls + 1 end)
    drain(Junk)

    assert(doneCalls == 1 and doneOk == true, "SellJunk must complete with onDone(true)")
    assert(#sells == 2, "must sell exactly the 2 eligible items, got " .. #sells)
    assert(sells[1].bag == 0 and sells[1].slot == 1,
        "first sell must be bag 0 slot 1, got bag=" .. tostring(sells[1].bag)
        .. " slot=" .. tostring(sells[1].slot))
    assert(sells[2].bag == 3 and sells[2].slot == 1,
        "second sell must be bag 3 slot 1, got bag=" .. tostring(sells[2].bag)
        .. " slot=" .. tostring(sells[2].slot))
    for i, s in ipairs(sells) do
        assert(s.unit == nil and s.bankType == nil,
            "sell " .. i .. " must be a plain UseContainerItem(bag, slot) — no unit, no bankType")
    end

    -- summary: 2 items, total 10*3 + 7*1 = 37 copper
    assert(#printed == 1, "exactly one summary print expected, got " .. #printed)
    assert(printed[1]:find("2", 1, true), "summary must contain the item count: " .. printed[1])
    assert(printed[1]:find("<37c>", 1, true),
        "summary must contain GetCoinTextureString(37), got: " .. printed[1])
    Junk.OnMerchant(false)
end

---------------------------------------------------------------------------
-- Section 6: sell pacing — items ride a rate queue (~6/sec): first item
-- synchronous, then one per timer fire at a positive sub-0.2s interval.
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 0), [2] = live(102, 0) }
    itemDB[101] = { sellPrice = 1 }
    itemDB[102] = { sellPrice = 1 }
    Junk.OnMerchant(true)
    Junk.SellJunk()
    assert(#sells == 1, "first sell must run synchronously on SellJunk")
    assert(#timers == 1, "second sell must wait on the rate timer")
    local delay = timers[1].delay
    assert(type(delay) == "number" and delay > 0 and delay <= 0.2,
        "sell interval must pace ~6/sec (0 < delay <= 0.2), got " .. tostring(delay))
    fireNext()
    assert(#sells == 2, "second sell must run on the timer fire")
    drain(Junk)
    Junk.OnMerchant(false)
end

---------------------------------------------------------------------------
-- Section 7: nil-tolerant pricing — an uncached GetItemInfo (returns
-- nothing) skips the item from the TOTAL but still sells it.
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 0), [2] = live(102, 0, { count = 2 }) }
    itemDB[101] = nil                 -- uncached: GetItemInfo returns nothing
    itemDB[102] = { sellPrice = 5 }
    Junk.OnMerchant(true)
    local doneOk, doneCalls = nil, 0
    Junk.SellJunk(function(ok) doneOk, doneCalls = ok, doneCalls + 1 end)
    drain(Junk)
    assert(doneCalls == 1 and doneOk == true, "uncached price must not break the run")
    assert(#sells == 2, "uncached-price item must still be sold")
    assert(printed[1] and printed[1]:find("<10c>", 1, true),
        "total must count only the priced item (5*2=10), got: " .. tostring(printed[1]))
    Junk.OnMerchant(false)
end

---------------------------------------------------------------------------
-- Section 8: no junk → immediate onDone(true), no sells, no timers, and a
-- "no junk" notice instead of a sell summary.
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 3) } -- nothing junk
    Junk.OnMerchant(true)
    local doneOk, doneCalls = nil, 0
    Junk.SellJunk(function(ok) doneOk, doneCalls = ok, doneCalls + 1 end)
    assert(doneCalls == 1 and doneOk == true, "no junk must call onDone(true) immediately")
    assert(#sells == 0 and #timers == 0, "no junk must not sell or schedule")
    assert(#printed == 1 and printed[1]:lower():find("no junk", 1, true),
        "no-junk run must print a notice, got: " .. tostring(printed[1]))
    Junk.OnMerchant(false)
end

---------------------------------------------------------------------------
-- Section 9: merchant closing mid-run cancels the queue — remaining items
-- are NOT sold after the window is gone (a post-close UseContainerItem
-- would USE the item instead of selling it).
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 0), [2] = live(102, 0), [3] = live(103, 0) }
    itemDB[101] = { sellPrice = 1 }
    itemDB[102] = { sellPrice = 1 }
    itemDB[103] = { sellPrice = 1 }
    Junk.OnMerchant(true)
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Junk.SellJunk(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(#sells == 1, "precondition: first item sold synchronously")
    Junk.OnMerchant(false)
    assert(doneCalls == 1 and doneOk == false and doneReason == "cancel",
        "merchant close mid-run must cancel with (false, 'cancel')")
    local before = #sells
    fireAll()
    assert(#sells == before, "stale timers after merchant close must not sell")
    assert(#printed == 0, "aborted run must not print a sell summary")
end

---------------------------------------------------------------------------
-- Section 10: re-entrancy — a second SellJunk while one is running refuses
-- with (false, "running") and queues nothing extra.
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 0), [2] = live(102, 0) }
    itemDB[101] = { sellPrice = 1 }
    itemDB[102] = { sellPrice = 1 }
    Junk.OnMerchant(true)
    Junk.SellJunk()
    assert(#sells == 1, "precondition: run in progress")
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Junk.SellJunk(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(doneCalls == 1 and doneOk == false and doneReason == "running",
        "second SellJunk while running must refuse with (false, 'running')")
    drain(Junk)
    assert(#sells == 2, "the original run must finish exactly its own items")
    Junk.OnMerchant(false)
end

---------------------------------------------------------------------------
-- Section 11: per-tick re-validation — a slot whose occupant changed (or
-- vacated) between enqueue and its tick is SKIPPED, not sold and not
-- failed; the run still completes with onDone(true).
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 0), [2] = live(102, 0), [3] = live(103, 0) }
    itemDB[101] = { sellPrice = 1 }
    itemDB[102] = { sellPrice = 1 }
    itemDB[103] = { sellPrice = 1 }
    Junk.OnMerchant(true)
    local doneOk, doneCalls = nil, 0
    Junk.SellJunk(function(ok) doneOk, doneCalls = ok, doneCalls + 1 end)
    assert(#sells == 1, "precondition: slot 1 sold synchronously")
    -- mid-run: the user drags a different item into slot 2 and empties slot 3
    bagContents[0][2] = live(999, 1)
    bagContents[0][3] = nil
    drain(Junk)
    assert(doneCalls == 1 and doneOk == true,
        "skipped slots must not fail the run (onDone(true) expected)")
    assert(#sells == 1,
        "changed/vacated occupants must be skipped, got " .. #sells .. " sells")
    for _, s in ipairs(sells) do
        assert(not (s.bag == 0 and (s.slot == 2 or s.slot == 3)),
            "a slot whose occupant changed must never reach UseContainerItem")
    end
    Junk.OnMerchant(false)
end

---------------------------------------------------------------------------
-- Section 12: combat mid-sell — Junk.OnCombat() (bags.lua's
-- PLAYER_REGEN_DISABLED route) cancels the run with (false, "combat");
-- stale timers are inert, no summary prints, idle OnCombat is a no-op.
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 0), [2] = live(102, 0) }
    itemDB[101] = { sellPrice = 1 }
    itemDB[102] = { sellPrice = 1 }
    Junk.OnMerchant(true)
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Junk.SellJunk(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(#sells == 1 and Junk.IsSelling(), "precondition: run in progress")
    Junk.OnCombat()
    assert(doneCalls == 1 and doneOk == false and doneReason == "combat",
        "combat mid-sell must cancel with (false, 'combat')")
    assert(not Junk.IsSelling(), "OnCombat must clear the selling state")
    local before = #sells
    fireAll()
    assert(#sells == before, "stale timers after combat must not sell")
    assert(#printed == 0, "aborted run must not print a sell summary")
    -- idle OnCombat is a no-op
    Junk.OnCombat()
    assert(doneCalls == 1, "idle OnCombat must not re-fire onDone")
    Junk.OnMerchant(false)
end

---------------------------------------------------------------------------
-- Section 13: shared ops gate — SellJunk refuses with (false, "busy")
-- while a sibling cursor/slot op (sort, deposit) runs; nothing is queued.
---------------------------------------------------------------------------
do
    reset()
    bagContents[0] = { [1] = live(101, 0) }
    itemDB[101] = { sellPrice = 1 }
    Junk.OnMerchant(true)

    ns.Bags.SortExecutor = { IsRunning = function() return true end }
    local doneOk, doneReason, doneCalls = nil, nil, 0
    Junk.SellJunk(function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end)
    assert(doneCalls == 1 and doneOk == false and doneReason == "busy",
        "SellJunk while a sort runs must refuse with (false, 'busy')")
    assert(#sells == 0 and #timers == 0, "busy refusal must not sell or schedule")
    assert(not Junk.IsSelling(), "busy refusal must not enter the selling state")
    ns.Bags.SortExecutor = nil

    -- gate lifted: the same call goes through
    Junk.SellJunk()
    drain(Junk)
    assert(#sells == 1, "SellJunk must proceed once the sibling op is idle")
    Junk.OnMerchant(false)
end

_G.print = realPrint
print("OK: bags_junk_test")
