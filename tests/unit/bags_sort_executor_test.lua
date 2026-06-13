-- tests/unit/bags_sort_executor_test.lua
-- Run: lua tests/unit/bags_sort_executor_test.lua
-- Integration of the REAL planner + REAL bus with the executor: only the
-- WoW surface (C_Container/cursor/timer/C_Item) is stubbed. The container
-- stub is a mutable simulator honoring cursor pickup/place semantics —
-- adapted from the planner test's simulator (pickup→place pair: empty
-- target places, same-item partial merges with the remainder left on the
-- cursor, different item swaps with the displaced item landing at the
-- cursor item's origin slot).
local loader = dofile("tests/helpers/load_bags_data.lua")

---------------------------------------------------------------------------
-- Item metadata the C_Item stubs serve. pending=true → GetItemInfo nil
-- (extended tier unavailable) AND live quality nil, like an unloaded item.
---------------------------------------------------------------------------
local META = {}
local function defineItems(n)
    META = {}
    for i = 1, n do
        META[i] = { quality = i, classID = 1, subClassID = 1,
                    name = "Item" .. i, ilvl = i, expacID = 1, maxStack = 1 }
    end
end

---------------------------------------------------------------------------
-- Mutable container simulator
---------------------------------------------------------------------------
local sim            -- [bagID] = { size, slots = { [slot] = {itemID,count,maxStack} } }
local locks          -- ["bag:slot"] = true
local cursor         -- { item, fromBag, fromSlot } | nil (executor-driven)
local userCursorItem -- refusal-matrix toggle for CursorHasItem()
local inCombat
local pickups        -- total PickupContainerItem calls
local ignorePickups  -- pass-limit section: server "ignores" every pickup
local timers         -- captured C_Timer.After callbacks
local printed        -- captured production print lines
local bagFlags       -- ["bagID:flag"] = true (GetBagSlotFlag)
local backpackIgnored

local function key(b, s) return b .. ":" .. s end

local function reset()
    sim, locks = {}, {}
    cursor, userCursorItem, inCombat = nil, false, false
    pickups, ignorePickups = 0, false
    timers, printed = {}, {}
    bagFlags, backpackIgnored = {}, false
end

local function bag(bagID, size, slotItems)
    sim[bagID] = { size = size, slots = slotItems or {} }
end

local function item(id, count, maxStack)
    return { itemID = id, count = count or 1, maxStack = maxStack or (META[id] and META[id].maxStack) or 1 }
end

local function flatten(bagID)
    local c = sim[bagID]
    local out = {}
    for s = 1, c.size do
        local cell = c.slots[s]
        out[#out + 1] = cell and (cell.itemID .. "x" .. cell.count) or "-"
    end
    return table.concat(out, ",")
end

local function fireTimers()
    local batch = timers
    timers = {}
    for _, t in ipairs(batch) do t.fn() end
end

---------------------------------------------------------------------------
-- WoW surface stubs
---------------------------------------------------------------------------
_G.C_Container = {
    GetContainerNumSlots = function(bagID)
        local c = sim[bagID]
        return c and c.size or 0
    end,
    GetContainerItemInfo = function(bagID, slot)
        local c = sim[bagID]
        local cell = c and c.slots[slot]
        if not cell then return nil end
        local m = META[cell.itemID] or {}
        return {
            itemID = cell.itemID,
            stackCount = cell.count,
            isLocked = locks[key(bagID, slot)] or false,
            quality = (not m.pending) and m.quality or nil,
            hyperlink = "link:" .. cell.itemID,
        }
    end,
    GetBagSlotFlag = function(bagID, flag)
        return bagFlags[key(bagID, flag)] or false
    end,
    GetBackpackAutosortDisabled = function()
        return backpackIgnored
    end,
    -- (numFreeSlots, bagFamily) — family nilable per ContainerDocumentation.
    -- The sim's bags carry no family (regular containers); family-restricted
    -- planning is covered by the planner suite.
    GetContainerNumFreeSlots = function(bagID)
        local c = sim[bagID]
        return 0, (c and c.family) or 0
    end,
    PickupContainerItem = function(bagID, slot)
        pickups = pickups + 1
        if ignorePickups then return end
        local c = assert(sim[bagID], "pickup references unknown bag " .. bagID)
        assert(slot >= 1 and slot <= c.size, "pickup slot out of range")
        local cell = c.slots[slot]
        if not cursor then
            -- pickup: locked or empty slots yield nothing
            if cell and not locks[key(bagID, slot)] then
                cursor = { item = cell, fromBag = bagID, fromSlot = slot }
                c.slots[slot] = nil
            end
        elseif not cell then
            c.slots[slot] = cursor.item
            cursor = nil
        elseif cell.itemID == cursor.item.itemID
            and cell.maxStack and cell.count < cell.maxStack then
            local xfer = math.min(cell.maxStack - cell.count, cursor.item.count)
            cell.count = cell.count + xfer
            cursor.item.count = cursor.item.count - xfer
            if cursor.item.count == 0 then cursor = nil end
            -- remainder stays on the cursor (ClearCursor returns it)
        else
            -- swap: displaced item lands at the cursor item's origin slot
            c.slots[slot] = cursor.item
            sim[cursor.fromBag].slots[cursor.fromSlot] = cell
            cursor = nil
        end
    end,
}
_G.ClearCursor = function()
    if cursor then
        local c = sim[cursor.fromBag]
        assert(c.slots[cursor.fromSlot] == nil,
            "ClearCursor: origin slot occupied — executor left a dangling cursor")
        c.slots[cursor.fromSlot] = cursor.item
        cursor = nil
    end
end
_G.CursorHasItem = function() return userCursorItem or cursor ~= nil end
_G.InCombatLockdown = function() return inCombat end
_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
_G.Enum = _G.Enum or {}
_G.Enum.BagSlotFlags = { DisableAutoSort = 1, ExcludeJunkSell = 64 }

reset()

_G.C_Item = {
    RequestLoadItemDataByID = function() end,
    -- Nilable per ItemDocumentation; META items carry no family (regular
    -- items) — family-restricted planning is covered by the planner suite.
    GetItemFamily = function(itemID)
        local m = META[itemID]
        return m and m.itemFamily or 0
    end,
    GetItemInfoInstant = function(itemID)
        local m = META[itemID]
        if not m then return nil end
        return itemID, "t", "st", "loc", 134400, m.classID, m.subClassID
    end,
    GetItemInfo = function(itemID)
        local m = META[itemID]
        if not m or m.pending then return nil end
        return m.name, "link:" .. itemID, m.quality, m.ilvl,
               nil, nil, nil, m.maxStack, nil, nil, nil, nil, nil, nil, m.expacID
    end,
    GetDetailedItemLevelInfo = function() return nil end, -- → baseIlvl fallback
}

---------------------------------------------------------------------------
-- Load production files: data layer (bus/store/item_info), then the real
-- planner, then the executor under test.
---------------------------------------------------------------------------
local settings = { behavior = { sortKey = "quality" } }
local ns = { Helpers = { CreateDBGetter = function() return function() return settings end end } }
loader.LoadAll(ns, "item_info.lua")
assert(loadfile("QUI_Bags/bags/ops/sort_planner.lua"))("QUI", ns)
assert(loadfile("QUI_Bags/bags/ops/shared.lua"))("QUI", ns)
assert(loadfile("QUI_Bags/bags/ops/sort_executor.lua"))("QUI", ns)
local Exec = ns.Bags.SortExecutor
assert(Exec and Exec.Start and Exec.IsRunning and Exec.Cancel and Exec.OnCombat,
    "SortExecutor API incomplete")

local realPrint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Section 1: refusal matrix — combat, occupied cursor, already running,
-- unknown scope. Refusals return (false, reason) and never call onDone.
---------------------------------------------------------------------------
do
    reset()
    defineItems(4)
    bag(0, 4, { [1] = item(1), [2] = item(2), [3] = item(3), [4] = item(4) })

    inCombat = true
    local ok, reason = Exec.Start("bags")
    assert(ok == false and reason == "combat", "must refuse in combat")
    assert(not Exec.IsRunning(), "refusal must not enter the running state")
    inCombat = false

    userCursorItem = true
    ok, reason = Exec.Start("bags")
    assert(ok == false and reason == "cursor", "must refuse with an occupied cursor")
    userCursorItem = false

    ok, reason = Exec.Start("nonsense")
    assert(ok == false and reason == "which", "must refuse an unknown scope")

    -- running: ascending quality with key=quality (descending) needs moves,
    -- so Start stays in the waiting state after its first batch
    ok = Exec.Start("bags")
    assert(ok == true, "valid Start must accept")
    assert(Exec.IsRunning(), "Start must enter the running state")
    ok, reason = Exec.Start("bags")
    assert(ok == false and reason == "running", "must refuse while running")
    Exec.Cancel()
    assert(not Exec.IsRunning(), "Cancel must clear the running state")
end

---------------------------------------------------------------------------
-- Section 2: convergence — 12 reversed singletons = 6 swaps = 2 batches.
-- Bus event drives the re-plan; the stale fallback timer must no-op.
---------------------------------------------------------------------------
do
    reset()
    defineItems(12)
    local slots = {}
    for s = 1, 12 do slots[s] = item(s) end -- ascending; quality key wants descending
    bag(0, 12, slots)

    local doneOk, doneReason, doneCalls = nil, nil, 0
    assert(Exec.Start("bags", function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end))
    -- batch 1: 5 of the 6 swaps issued (2 pickups each), then a yield
    assert(pickups == 10, "batch 1 must issue exactly 5 moves, got " .. pickups .. " pickups")
    assert(doneCalls == 0, "must not finish mid-run")
    assert(#timers == 1, "each yield must schedule exactly one fallback timer")

    -- bus event wins the race → batch 2 (the last swap) + a fresh yield
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    assert(pickups == 12, "batch 2 must issue the remaining move")
    -- the stale batch-1 fallback timer must NOT double-trigger a pass
    local stale = timers[1]
    assert(#timers == 2, "batch 2 must schedule its own fallback")
    stale.fn()
    assert(pickups == 12 and doneCalls == 0, "stale fallback timer must be a no-op")

    -- next trigger re-plans → empty plan → converged
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    assert(doneCalls == 1 and doneOk == true and doneReason == nil,
        "convergence must call onDone(true) exactly once")
    assert(not Exec.IsRunning(), "executor must be idle after convergence")
    assert(cursor == nil, "cursor must be clean after the run")
    local want = {}
    for s = 1, 12 do want[#want + 1] = (13 - s) .. "x1" end
    assert(flatten(0) == table.concat(want, ","),
        "final layout not sorted: " .. flatten(0))
    local summary = printed[#printed]
    assert(summary and summary:find("QUI:", 1, true) and summary:find("6", 1, true),
        "summary print must use the house prefix and report the move count")

    -- leftover timers after completion must no-op
    fireTimers()
    assert(doneCalls == 1 and pickups == 12, "post-done timers must be inert")
end

---------------------------------------------------------------------------
-- Section 2b: already sorted → immediate onDone(true), zero moves
---------------------------------------------------------------------------
do
    reset()
    defineItems(3)
    bag(0, 4, { [1] = item(3), [2] = item(2), [3] = item(1) }) -- desc quality
    local doneOk, doneCalls = nil, 0
    assert(Exec.Start("bags", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end))
    assert(doneCalls == 1 and doneOk == true, "already sorted must finish immediately")
    assert(pickups == 0, "already sorted must issue no moves")
end

---------------------------------------------------------------------------
-- Section 3: stack merge through the live pair — remainder returns home
-- via the trailing ClearCursor (cursor hygiene around each pickup pair).
---------------------------------------------------------------------------
do
    reset()
    -- unique itemID: ItemInfo caches extended records per itemID for the
    -- whole session, so re-defining an already-seen ID would serve stale data
    defineItems(0)
    META[901] = { quality = 1, classID = 7, subClassID = 1,
                  name = "Ore", ilvl = 1, expacID = 1, maxStack = 20 }
    bag(0, 3, { [1] = item(901, 15, 20), [2] = item(901, 10, 20) })
    local doneOk, doneCalls = nil, 0
    assert(Exec.Start("bags", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end))
    while Exec.IsRunning() do ns.Bags.Bus.Publish("BagsChanged", "k", { 0 }) end
    assert(doneCalls == 1 and doneOk == true, "merge run must converge")
    assert(flatten(0) == "901x20,901x5,-", "capped merge layout wrong: " .. flatten(0))
end

---------------------------------------------------------------------------
-- Section 4: locked slot — move deferred while locked, completed after
-- unlock; independent moves in the same batch still execute.
---------------------------------------------------------------------------
do
    reset()
    defineItems(4)
    -- two independent swap pairs: (slot1 q3 ↔ slot2 q4), (slot3 q1 ↔ slot4 q2)
    bag(0, 4, { [1] = item(3), [2] = item(4), [3] = item(1), [4] = item(2) })
    locks[key(0, 4)] = true
    local doneOk, doneCalls = nil, 0
    assert(Exec.Start("bags", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end))
    -- pair (1,2) executed; pair (3,4) deferred on the lock
    assert(flatten(0) == "4x1,3x1,1x1,2x1",
        "locked batch must defer only the locked pair: " .. flatten(0))
    assert(pickups == 2, "exactly one move must issue while the lock holds")
    assert(doneCalls == 0 and Exec.IsRunning(), "deferred move must keep the run alive")

    -- still locked: another pass defers again, run stays alive
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    assert(pickups == 2 and Exec.IsRunning(), "locked move must stay deferred")

    -- unlock → next pass completes the deferred move, then converges
    locks[key(0, 4)] = nil
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    assert(doneCalls == 1 and doneOk == true, "run must converge after unlock")
    assert(flatten(0) == "4x1,3x1,2x1,1x1", "final layout wrong: " .. flatten(0))
end

---------------------------------------------------------------------------
-- Section 5: mid-run combat → onDone(false, "combat"), no further moves
---------------------------------------------------------------------------
do
    reset()
    defineItems(12)
    local slots = {}
    for s = 1, 12 do slots[s] = item(s) end
    bag(0, 12, slots)
    local doneOk, doneReason, doneCalls = nil, nil, 0
    assert(Exec.Start("bags", function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end))
    assert(Exec.IsRunning(), "precondition: mid-run")
    local before = pickups
    Exec.OnCombat()
    assert(doneCalls == 1 and doneOk == false and doneReason == "combat",
        "combat must abort with onDone(false, 'combat')")
    assert(not Exec.IsRunning(), "combat abort must clear the running state")
    -- neither the bus nor the pending fallback may issue further moves
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    fireTimers()
    assert(pickups == before, "no moves may issue after a combat abort")
    -- idle OnCombat is a no-op
    Exec.OnCombat()
    assert(doneCalls == 1, "idle OnCombat must not re-fire onDone")
end

---------------------------------------------------------------------------
-- Section 6: pass limit — the server "ignores" every pickup, so the plan
-- never shrinks; 8 consecutive stalled re-plans abort the run.
---------------------------------------------------------------------------
do
    reset()
    defineItems(4)
    bag(0, 4, { [1] = item(1), [2] = item(2), [3] = item(3), [4] = item(4) })
    ignorePickups = true
    local doneOk, doneReason, doneCalls = nil, nil, 0
    assert(Exec.Start("bags", function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end))
    local fires = 0
    while Exec.IsRunning() and fires < 20 do
        fires = fires + 1
        fireTimers() -- fallback path drives the re-plan here
    end
    assert(doneCalls == 1 and doneOk == false and doneReason == "passes",
        "non-convergence must abort with onDone(false, 'passes')")
    assert(fires == 8, "stall limit must trip after exactly 8 stalled passes, used " .. fires .. " fires")
    -- the stall-abort summary must report how far the run got
    local summary = printed[#printed]
    assert(summary and summary:find("after %d+ move"),
        "stall-abort print must include the moved count, got: " .. tostring(summary))
end

---------------------------------------------------------------------------
-- Section 7: Cancel mid-run
---------------------------------------------------------------------------
do
    reset()
    defineItems(12)
    local slots = {}
    for s = 1, 12 do slots[s] = item(s) end
    bag(0, 12, slots)
    local doneOk, doneReason, doneCalls = nil, nil, 0
    assert(Exec.Start("bags", function(ok, reason)
        doneOk, doneReason, doneCalls = ok, reason, doneCalls + 1
    end))
    local before = pickups
    Exec.Cancel()
    assert(doneCalls == 1 and doneOk == false and doneReason == "cancel",
        "Cancel must abort with onDone(false, 'cancel')")
    assert(not Exec.IsRunning(), "Cancel must clear the running state")
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    fireTimers()
    assert(pickups == before, "no moves may issue after Cancel")
    -- idle Cancel is a no-op
    Exec.Cancel()
    assert(doneCalls == 1, "idle Cancel must not re-fire onDone")
end

---------------------------------------------------------------------------
-- Section 8: ignored flags — backpack via GetBackpackAutosortDisabled,
-- held bags via GetBagSlotFlag(DisableAutoSort). Ignored bags contribute
-- nothing and receive nothing.
---------------------------------------------------------------------------
do
    reset()
    defineItems(4)
    bag(0, 2, { [1] = item(1) })
    bag(1, 2, { [1] = item(2) })
    bag(2, 2, { [2] = item(4), [1] = item(3) })
    backpackIgnored = true
    bagFlags[key(1, Enum.BagSlotFlags.DisableAutoSort)] = true
    local doneCalls = 0
    assert(Exec.Start("bags", function() doneCalls = doneCalls + 1 end))
    while Exec.IsRunning() do ns.Bags.Bus.Publish("BagsChanged", "k", { 0 }) end
    assert(doneCalls == 1, "ignored-flag run must converge")
    assert(flatten(0) == "1x1,-", "ignored backpack must stay untouched: " .. flatten(0))
    assert(flatten(1) == "2x1,-", "DisableAutoSort bag must stay untouched: " .. flatten(1))
    assert(flatten(2) == "4x1,3x1", "active bag must sort: " .. flatten(2))
end

-- Section 9: bank scopes — character bank tabs (6–11) and warband bank
-- tabs (12–16) sort independently, and selected-tab sorts stay inside the
-- requested tab.
---------------------------------------------------------------------------
do
    reset()
    defineItems(4)
    bag(6, 3, { [1] = item(1), [2] = item(2) })
    bag(7, 2, { [1] = item(3) })
    bag(12, 2, { [1] = item(4) })
    bagFlags[key(6, Enum.BagSlotFlags.DisableAutoSort)] = true -- must be ineffective
    local doneOk, doneCalls = nil, 0
    assert(Exec.Start("characterBank", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end))
    assert(pickups > 0, "character bank sort must issue moves")
    -- a BagsChanged event must NOT advance a bank run
    local mid = pickups
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    assert(pickups == mid and doneCalls == 0, "BagsChanged must not drive a character bank run")
    while Exec.IsRunning() do ns.Bags.Bus.Publish("BankChanged", "k", { 6 }) end
    assert(doneCalls == 1 and doneOk == true, "character bank run must converge")
    assert(flatten(6) == "3x1,2x1,1x1", "character bank tab 6 layout wrong: " .. flatten(6))
    assert(flatten(7) == "-,-", "character bank tab 7 should be drained into tab 6: " .. flatten(7))
    assert(flatten(12) == "4x1,-", "warband tab must stay untouched by character bank sort: " .. flatten(12))

    reset()
    defineItems(4)
    bag(6, 2, { [1] = item(4) })
    bag(12, 3, { [1] = item(1), [2] = item(2) })
    bag(13, 2, { [1] = item(3) })
    doneOk, doneCalls = nil, 0
    assert(Exec.Start("warbandBank", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end))
    assert(pickups > 0, "warband bank sort must issue moves")
    mid = pickups
    ns.Bags.Bus.Publish("BankChanged", "k", { 6 })
    assert(pickups == mid and doneCalls == 0, "BankChanged must not drive a warband bank run")
    while Exec.IsRunning() do ns.Bags.Bus.Publish("WarbandChanged", { 12 }) end
    assert(doneCalls == 1 and doneOk == true, "warband bank run must converge")
    assert(flatten(12) == "3x1,2x1,1x1", "warband bank tab 12 layout wrong: " .. flatten(12))
    assert(flatten(13) == "-,-", "warband bank tab 13 should be drained into tab 12: " .. flatten(13))
    assert(flatten(6) == "4x1,-", "character tab must stay untouched by warband bank sort: " .. flatten(6))

    reset()
    defineItems(3)
    bag(6, 2, { [1] = item(3) })
    bag(7, 3, { [1] = item(1), [2] = item(2) })
    doneOk, doneCalls = nil, 0
    assert(Exec.Start("characterBank", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end,
        { tabID = 7 }))
    while Exec.IsRunning() do ns.Bags.Bus.Publish("BankChanged", "k", { 7 }) end
    assert(doneCalls == 1 and doneOk == true, "selected character bank tab run must converge")
    assert(flatten(7) == "2x1,1x1,-", "selected tab 7 layout wrong: " .. flatten(7))
    assert(flatten(6) == "3x1,-", "tab 6 must stay untouched by selected tab 7 sort: " .. flatten(6))

    local ok, reason = Exec.Start("characterBank", nil, { tabID = 12 })
    assert(ok == false and reason == "which",
        "characterBank must refuse a warband tabID with (false, 'which')")
end

---------------------------------------------------------------------------
-- Section 10: pending extended data — GetItemInfo nil + live quality nil
-- must not error; the planner tolerates nil fields (they sort last).
---------------------------------------------------------------------------
do
    reset()
    -- unique itemID for the pending item: an already-seen ID would hit the
    -- ItemInfo session cache and defeat the nil-extended-data path
    defineItems(1)
    META[950] = { pending = true, classID = 1, subClassID = 1 }
    bag(0, 3, { [1] = item(950), [2] = item(1) })
    local doneOk, doneCalls = nil, 0
    assert(Exec.Start("bags", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end))
    while Exec.IsRunning() do ns.Bags.Bus.Publish("BagsChanged", "k", { 0 }) end
    assert(doneCalls == 1 and doneOk == true, "pending-data run must converge")
    assert(flatten(0) == "1x1,950x1,-",
        "pending item must sort last without error: " .. flatten(0))
end

---------------------------------------------------------------------------
-- Section 11: synthetic re-dress pings (empty changed array) must NOT
-- drive a re-plan — only scanner publishes (non-empty arrays) do. Both
-- handler argument shapes: BagsChanged/BankChanged carry (charKey,
-- changed); WarbandChanged carries just (changed).
---------------------------------------------------------------------------
do
    reset()
    defineItems(12)
    local slots = {}
    for s = 1, 12 do slots[s] = item(s) end
    bag(0, 12, slots)
    local doneCalls = 0
    assert(Exec.Start("bags", function() doneCalls = doneCalls + 1 end))
    assert(pickups == 10, "precondition: batch 1 issued, run waiting")
    -- empty ping (the bags.lua lock/cooldown route): no re-plan
    ns.Bags.Bus.Publish("BagsChanged", "k", {})
    assert(pickups == 10 and doneCalls == 0,
        "an empty BagsChanged ping must not trigger a re-plan")
    -- scanner-shaped publish: drives batch 2
    ns.Bags.Bus.Publish("BagsChanged", "k", { 0 })
    assert(pickups == 12, "a non-empty BagsChanged must drive the re-plan")
    Exec.Cancel()

    -- WarbandChanged shape: (eventName, changed) — no charKey argument
    reset()
    defineItems(3)
    bag(12, 3, { [1] = item(1), [2] = item(2) }) -- warband tab
    local doneOk
    doneCalls = 0
    assert(Exec.Start("warbandBank", function(ok) doneOk, doneCalls = ok, doneCalls + 1 end))
    local mid = pickups
    ns.Bags.Bus.Publish("WarbandChanged", {})
    assert(pickups == mid and doneCalls == 0,
        "an empty WarbandChanged ping must not trigger a re-plan")
    while Exec.IsRunning() do ns.Bags.Bus.Publish("WarbandChanged", { 12 }) end
    assert(doneCalls == 1 and doneOk == true,
        "non-empty WarbandChanged publishes must drive the bank run to convergence")
end

---------------------------------------------------------------------------
-- Section 12: shared ops gate — Start refuses with (false, "busy") while a
-- sibling cursor/slot op (deposit, sell) runs; no moves issue.
---------------------------------------------------------------------------
do
    reset()
    defineItems(2)
    bag(0, 2, { [1] = item(1), [2] = item(2) })

    ns.Bags.Transfers = { IsRunning = function() return true end }
    local ok, reason = Exec.Start("bags")
    assert(ok == false and reason == "busy",
        "Start while a transfer queue runs must refuse with (false, 'busy')")
    assert(not Exec.IsRunning(), "busy refusal must not enter the running state")
    ns.Bags.Transfers = nil

    ns.Bags.Junk = { IsSelling = function() return true end }
    ok, reason = Exec.Start("bags")
    assert(ok == false and reason == "busy",
        "Start while a sell runs must refuse with (false, 'busy')")
    ns.Bags.Junk = nil
    assert(pickups == 0, "busy refusals must issue no moves")

    -- gate lifted: the same Start goes through
    local doneCalls = 0
    assert(Exec.Start("bags", function() doneCalls = doneCalls + 1 end))
    while Exec.IsRunning() do ns.Bags.Bus.Publish("BagsChanged", "k", { 0 }) end
    assert(doneCalls == 1 and pickups > 0,
        "Start must proceed once the sibling ops are idle")
end

_G.print = realPrint
print("OK: bags_sort_executor_test")
