-- tests/unit/bags_newitems_test.lua
-- Run: lua tests/unit/bags_newitems_test.lua
-- TDD for Bags.NewItems. Pure core (injected `now`, no wall clock):
--   Record    — first observation only; never resurrects a seen/known GUID
--   IsNew     — strict timeout window; seen tombstone (0) is never new
--   MarkSeen  — tombstones a tracked entry
--   Baseline  — priming walk: pre-existing items become seen, idempotent
-- Wrapper layer (stubbed C_Item/ItemLocation/C_Container/Helpers):
--   Session store — never saved; OnLogin/OnDisable wipe it (a reload or a
--                   disable/enable cycle always starts glow-free)
--   Priming window — OnLogin baselines, re-baselines on BagsChanged, takes
--                    a final sweep at close (C_Timer), THEN arms CheckSlot
--   CheckSlot — guard chain: primed/entry/setting/DoesItemExist/pcall'd
--               GetItemGUID (ItemDocumentation: GetItemGUID(itemLocation)
--               → WOWGUID; DoesItemExist(emptiableItemLocation) → bool)
local loader = dofile("tests/helpers/load_bags_data.lua")
loader.InstallBaseStubs()

---------------------------------------------------------------------------
-- Mutable test state
---------------------------------------------------------------------------
local clock = 100000           -- injected wall clock for the wrapper layer
_G.time = function() return clock end

local settings                 -- Helpers.CreateDBGetter("bags") result
local slots = {}               -- ["bag-slot"] = guid | "ERROR" (GetItemGUID throws)
local numSlots = {}            -- [bagID] = container size (baseline walk)

local function reset()
    settings = {
        behavior = { newItemGlow = { enabled = true, timeoutMinutes = 30 } },
    }
    slots = {}
    numSlots = {}
end
reset()

---------------------------------------------------------------------------
-- WoW surface stubs (shapes per vendored docs/FrameXML)
---------------------------------------------------------------------------
-- ItemLocation:CreateFromBagAndSlot (Blizzard_ObjectAPI/ItemLocation.lua:9)
_G.ItemLocation = {
    CreateFromBagAndSlot = function(_, bagID, slot)
        return { bagID = bagID, slot = slot }
    end,
}
_G.C_Item.DoesItemExist = function(loc)
    return slots[loc.bagID .. "-" .. loc.slot] ~= nil
end
_G.C_Item.GetItemGUID = function(loc)
    local guid = slots[loc.bagID .. "-" .. loc.slot]
    if guid == "ERROR" then error("Usage: C_Item.GetItemGUID(itemLocation)") end
    return guid
end
_G.C_Container = _G.C_Container or {}
_G.C_Container.GetContainerNumSlots = function(bagID) return numSlots[bagID] or 0 end

-- Minimal Bus stub (data/bus.lua shape): captures the window's BagsChanged
-- subscription so tests can replay scanner waves.
local busHandlers = {}
local Bus = {
    Subscribe = function(eventName, handler)
        busHandlers[eventName] = busHandlers[eventName] or {}
        table.insert(busHandlers[eventName], handler)
    end,
    Unsubscribe = function(eventName, handler)
        local list = busHandlers[eventName] or {}
        for i = #list, 1, -1 do
            if list[i] == handler then table.remove(list, i) end
        end
    end,
    Publish = function(eventName, ...)
        for _, handler in ipairs(busHandlers[eventName] or {}) do
            handler(eventName, ...)
        end
    end,
}
local function busSubscriberCount(eventName)
    return #(busHandlers[eventName] or {})
end

local ns = {
    Bags = { Bus = Bus },
    Helpers = {
        CreateDBGetter = function() return function() return settings end end,
        GetCore = function() return nil end,
    },
}
assert(loadfile("QUI_Bags/bags/newitems.lua"))("QUI", ns)
local NewItems = ns.Bags.NewItems
assert(NewItems, "newitems.lua must publish Bags.NewItems")

local TIMEOUT = 30 * 60 -- seconds, mirrors timeoutMinutes = 30

---------------------------------------------------------------------------
-- Pure core
---------------------------------------------------------------------------
-- Test 1: Record — first observation records, repeats don't overwrite
local store = {}
assert(NewItems.Record(store, "g1", 1000) == true, "unknown GUID must record")
assert(store.g1 == 1000, "Record must stamp firstSeen")
assert(NewItems.Record(store, "g1", 2000) == false, "known GUID must not re-record")
assert(store.g1 == 1000, "repeat Record must not overwrite firstSeen")

-- Test 2: IsNew — strict timeout window, unknown never new
assert(NewItems.IsNew(store, "g1", 1000, TIMEOUT) == true, "fresh entry must be new")
assert(NewItems.IsNew(store, "g1", 1000 + TIMEOUT - 1, TIMEOUT) == true,
       "entry inside the window must be new")
assert(NewItems.IsNew(store, "g1", 1000 + TIMEOUT, TIMEOUT) == false,
       "entry at the timeout boundary must have expired (strict <)")
assert(NewItems.IsNew(store, "missing", 1000, TIMEOUT) == false, "unknown GUID is never new")
assert(NewItems.IsNew(nil, "g1", 1000, TIMEOUT) == false, "nil store must be tolerated")

-- Test 3: MarkSeen — kills the glow AND blocks resurrection through Record
NewItems.MarkSeen(store, "g1")
assert(NewItems.IsNew(store, "g1", 1001, TIMEOUT) == false, "seen entry must not be new")
assert(NewItems.Record(store, "g1", 1002) == false,
       "Record must not resurrect a seen GUID (tombstone is a known entry)")
assert(NewItems.IsNew(store, "g1", 1002, TIMEOUT) == false, "still seen after re-Record attempt")
NewItems.MarkSeen(store, "untracked") -- only tracked entries get tombstoned
assert(store.untracked == nil, "MarkSeen on an untracked GUID must not create an entry")

-- Test 4: Baseline — unknown GUIDs become seen; a tracked entry is untouched
NewItems.Record(store, "glowing", 5000)
NewItems.Baseline(store, "preexisting")
NewItems.Baseline(store, "glowing")
assert(NewItems.IsNew(store, "preexisting", 5001, TIMEOUT) == false,
       "baselined pre-existing item must never glow")
assert(NewItems.IsNew(store, "glowing", 5001, TIMEOUT) == true,
       "Baseline must not clobber a tracked (unexpired, unseen) entry")

---------------------------------------------------------------------------
-- Wrapper layer: CheckSlot guard chain (no C_Timer → window closes
-- synchronously inside OnLogin)
---------------------------------------------------------------------------
-- Test 5: priming gate — CheckSlot is inert (no recording, no glow) until
-- the activation window has closed. A bag window opened before then renders
-- LAST session's cached slots; recording those would blanket-glow the bag.
reset()
slots["0-1"] = "Item-1-1-1"
assert(NewItems.CheckSlot(0, 1, { itemID = 1 }) == nil, "unprimed CheckSlot must be inert")
assert(next(NewItems._SessionStore()) == nil, "unprimed CheckSlot must not write the store")
NewItems.OnLogin() -- empty walk (numSlots empty): primes without baselining
assert(next(NewItems._SessionStore()) == nil, "empty-bag OnLogin must not write the store")

-- Test 5b: empty slot (nil entry) → nil, nothing recorded
assert(NewItems.CheckSlot(0, 2, nil) == nil, "empty slot must not track")
assert(next(NewItems._SessionStore()) == nil, "empty slot must not write the store")

-- Test 6: setting disabled → nil
settings.behavior.newItemGlow.enabled = false
assert(NewItems.CheckSlot(0, 1, { itemID = 1 }) == nil, "disabled glow must not track")
assert(next(NewItems._SessionStore()) == nil, "disabled glow must not write the store")

-- Test 6b: settings unavailable (login race / harness) → quiet no-op
local saved = settings
settings = nil
assert(NewItems.CheckSlot(0, 1, { itemID = 1 }) == nil, "missing settings → not eligible")
settings = saved

-- Test 7: happy path — unseen GUID records + returns (glow-eligible)
settings.behavior.newItemGlow.enabled = true
assert(NewItems.CheckSlot(0, 1, { itemID = 1 }) == "Item-1-1-1",
       "unseen item must be glow-eligible")
assert(NewItems._SessionStore()["Item-1-1-1"] == clock, "CheckSlot must record firstSeen = now")
-- repeat within the window: still eligible, timestamp unchanged
clock = clock + 60
assert(NewItems.CheckSlot(0, 1, { itemID = 1 }) == "Item-1-1-1",
       "tracked item inside the window stays eligible")
assert(NewItems._SessionStore()["Item-1-1-1"] == clock - 60, "re-check must not re-stamp")

-- Test 8: timeout expiry through the wrapper (timeoutMinutes from settings)
clock = clock + TIMEOUT
assert(NewItems.CheckSlot(0, 1, { itemID = 1 }) == nil, "expired entry must stop glowing")

-- Test 9: MarkSlotSeen kills eligibility immediately
slots["0-2"] = "Item-1-1-2"
assert(NewItems.CheckSlot(0, 2, { itemID = 2 }) == "Item-1-1-2")
NewItems.MarkSlotSeen("Item-1-1-2")
assert(NewItems.CheckSlot(0, 2, { itemID = 2 }) == nil, "seen item must stop glowing")

-- Test 10: location guards — DoesItemExist false, GetItemGUID throwing
assert(NewItems.CheckSlot(3, 9, { itemID = 3 }) == nil,
       "occupied cache entry over a non-existent live location must not track")
slots["3-9"] = "ERROR"
assert(NewItems.CheckSlot(3, 9, { itemID = 3 }) == nil,
       "GetItemGUID errors must be swallowed by the pcall guard")

-- Test 11: module disable wipes the session store and goes inert; re-enable
-- starts glow-free (a glow does NOT survive a disable/enable cycle, and an
-- item acquired while disabled baselines to seen).
slots["0-4"] = "Item-1-1-4"
assert(NewItems.CheckSlot(0, 4, { itemID = 5 }) == "Item-1-1-4", "primed + unseen → eligible")
NewItems.OnDisable()
assert(next(NewItems._SessionStore()) == nil, "OnDisable must wipe the session store")
slots["0-5"] = "Item-1-1-5" -- acquired while disabled
assert(NewItems.CheckSlot(0, 5, { itemID = 6 }) == nil, "disabled module must not track")
numSlots = { [0] = 5 } -- re-enable: baseline walk covers slots 0-1..0-5
NewItems.OnLogin()
assert(NewItems.CheckSlot(0, 5, { itemID = 6 }) == nil,
       "item acquired while disabled must baseline to seen on re-enable")
assert(NewItems.CheckSlot(0, 4, { itemID = 5 }) == nil,
       "a glow must NOT survive a disable/enable cycle (session store wiped)")

---------------------------------------------------------------------------
-- Wrapper layer: reload semantics + priming window
---------------------------------------------------------------------------
-- Test 12: "reload" (fresh OnLogin) — everything present baselines to seen;
-- a glow from the previous activation never survives.
reset()
clock = 200000
numSlots = { [0] = 2, [4] = 1 }
slots["0-1"] = "Item-1-1-10"
slots["4-1"] = "Item-1-1-11"
NewItems.OnLogin()
assert(NewItems.CheckSlot(0, 1, { itemID = 10 }) == nil,
       "present item must not glow after a fresh activation")
assert(NewItems.CheckSlot(4, 1, { itemID = 11 }) == nil,
       "present item must not glow after a fresh activation (second bag)")

-- Test 13: priming window with a real timer — late container waves baseline
-- before tracking arms; only post-window arrivals glow.
reset()
numSlots = { [0] = 4 }
slots["0-1"] = "Item-1-1-20"
local timerCallbacks = {}
_G.C_Timer = { After = function(_, cb) table.insert(timerCallbacks, cb) end }
NewItems.OnLogin()
assert(#timerCallbacks == 1, "OnLogin must schedule exactly one window close")
assert(busSubscriberCount("BagsChanged") == 1, "window must subscribe to BagsChanged")
assert(NewItems.CheckSlot(0, 1, { itemID = 20 }) == nil,
       "CheckSlot must stay inert inside the priming window")
-- a late login wave delivers another item: the Bus re-baseline catches it
slots["0-2"] = "Item-1-1-21"
Bus.Publish("BagsChanged", "char", {})
-- an even later item appears with no wave; the close sweep catches it
slots["0-3"] = "Item-1-1-22"
timerCallbacks[1]() -- close the window (final sweep + arm)
assert(busSubscriberCount("BagsChanged") == 0,
       "closing the window must unsubscribe the re-baseline handler")
assert(NewItems.CheckSlot(0, 2, { itemID = 21 }) == nil,
       "item from a late pre-close wave must baseline to seen")
assert(NewItems.CheckSlot(0, 3, { itemID = 22 }) == nil,
       "item caught by the close sweep must baseline to seen")
slots["0-4"] = "Item-1-1-23" -- genuinely new: arrives after the window
assert(NewItems.CheckSlot(0, 4, { itemID = 23 }) == "Item-1-1-23",
       "post-window arrival must glow")

-- Test 13b: a stale window close must not fire after OnDisable superseded it
NewItems.OnDisable()
numSlots = { [0] = 5 } -- walk range covers the slot used below
timerCallbacks = {}
NewItems.OnLogin()
local firstClose = timerCallbacks[1]
NewItems.OnDisable()
NewItems.OnLogin()
firstClose() -- stale token: must NOT arm tracking
slots["0-5"] = "Item-1-1-24"
assert(NewItems.CheckSlot(0, 5, { itemID = 24 }) == nil,
       "a superseded window close must not arm tracking")
timerCallbacks[2]() -- the live window close arms it
assert(NewItems.CheckSlot(0, 5, { itemID = 24 }) == nil,
       "item present before the live close must baseline to seen")
_G.C_Timer = nil

-- SeenAll: the "clear new" affordance — every tracked GUID tombstones in
-- one sweep (glow ends everywhere); untracked stays untracked.
do
    local s = { a = 100, b = 200, c = 0 }
    NewItems.SeenAll(s)
    assert(NewItems.IsNew(s, "a", 150, 1800) == false, "a must stop glowing after SeenAll")
    assert(NewItems.IsNew(s, "b", 250, 1800) == false, "b must stop glowing after SeenAll")
    assert(s.a == 0 and s.b == 0 and s.c == 0, "SeenAll must tombstone, not delete")
    assert(s.d == nil, "SeenAll must not invent entries")
    NewItems.SeenAll(nil) -- nil store must be a no-op, not an error
end

print("OK: bags_newitems_test")
