-- tests/unit/bags_sort_planner_test.lua
-- Run: lua tests/unit/bags_sort_planner_test.lua
-- The planner is PURE: loaded directly with NO WoW stubs installed, on
-- purpose — any WoW API reference in sort_planner.lua crashes this suite.
local ns = {}
local chunk = assert(loadfile("QUI_Bags/bags/ops/sort_planner.lua"))
chunk("QUI", ns)
local Planner = ns.Bags.SortPlanner
assert(Planner and Planner.Plan, "SortPlanner.Plan missing")

---------------------------------------------------------------------------
-- Fixture helpers
---------------------------------------------------------------------------
local function item(id, opts)
    opts = opts or {}
    return {
        itemID = id,
        count = opts.count or 1,
        quality = opts.quality,
        name = opts.name,
        ilvl = opts.ilvl,
        sortClass = opts.sortClass,
        sortSubClass = opts.sortSubClass,
        expacID = opts.expacID,
        maxStack = opts.maxStack,
        itemFamily = opts.itemFamily,
    }
end

local function bag(bagID, size, slotItems, ignored, family)
    return { bagID = bagID, size = size, slots = slotItems or {}, ignored = ignored or false,
             family = family }
end

-- Pure-Lua bitwise AND (headless Lua 5.1 has no bit library); families are
-- small masks so the %2 walk is fine.
local function band(a, b)
    local result, bitval = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + bitval end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitval = bitval * 2
    end
    return result
end

-- Family legality: unrestricted bags (family nil/0) accept everything; a
-- specialty bag accepts only items whose family mask overlaps its own.
local function fitsFamily(itemFamily, bagFamily)
    if not bagFamily or bagFamily == 0 then return true end
    if not itemFamily or itemFamily == 0 then return false end
    return band(itemFamily, bagFamily) ~= 0
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deepCopy(val) end
    return out
end

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Simulator: applies the move list over the ORIGINAL input with cursor
-- semantics (pickup whole stack → place):
--   empty target            → place
--   same item, room in dest → merge up to maxStack, remainder back at source
--   otherwise               → swap
-- This is the honesty check — if any move's from-location fails to reflect
-- earlier moves, the simulation picks up the wrong (or an empty) slot and
-- the final layout won't match.
---------------------------------------------------------------------------
local function buildState(containers)
    local state = {}
    for _, c in ipairs(containers) do
        local slots = {}
        for s = 1, c.size do
            local e = c.slots[s]
            if e then
                slots[s] = { itemID = e.itemID, count = e.count or 1, maxStack = e.maxStack,
                             itemFamily = e.itemFamily }
            end
        end
        state[c.bagID] = { size = c.size, slots = slots, family = c.family }
    end
    return state
end

local function simulate(containers, moves)
    local state = buildState(containers)
    for i, m in ipairs(moves) do
        local fromBag, toBag = state[m.fromBag], state[m.toBag]
        assert(fromBag and toBag, "move " .. i .. " references an unknown bag")
        assert(m.fromSlot >= 1 and m.fromSlot <= fromBag.size, "move " .. i .. " fromSlot out of range")
        assert(m.toSlot >= 1 and m.toSlot <= toBag.size, "move " .. i .. " toSlot out of range")
        local src = fromBag.slots[m.fromSlot]
        assert(src, "move " .. i .. " picks up an EMPTY slot ("
            .. m.fromBag .. "," .. m.fromSlot .. ") — virtual state broke")
        local dst = toBag.slots[m.toSlot]
        if not dst then
            assert(fitsFamily(src.itemFamily, toBag.family),
                "move " .. i .. " places a non-fitting item into family bag " .. m.toBag)
            toBag.slots[m.toSlot] = src
            fromBag.slots[m.fromSlot] = nil
        elseif dst.itemID == src.itemID and dst.maxStack and dst.count < dst.maxStack then
            local xfer = math.min(dst.maxStack - dst.count, src.count)
            dst.count = dst.count + xfer
            src.count = src.count - xfer
            if src.count == 0 then fromBag.slots[m.fromSlot] = nil end
        else
            assert(fitsFamily(src.itemFamily, toBag.family),
                "move " .. i .. " places a non-fitting item into family bag " .. m.toBag)
            assert(fitsFamily(dst.itemFamily, fromBag.family),
                "move " .. i .. " swaps a non-fitting occupant into family bag " .. m.fromBag)
            toBag.slots[m.toSlot] = src
            fromBag.slots[m.fromSlot] = dst
        end
    end
    return state
end

-- Render a state's occupancy as "itemIDxcount" CSV across the given bags.
local function flatten(state, bagOrder)
    local out = {}
    for _, bagID in ipairs(bagOrder) do
        local c = state[bagID]
        for s = 1, c.size do
            local cell = c.slots[s]
            out[#out + 1] = cell and (cell.itemID .. "x" .. cell.count) or "-"
        end
    end
    return table.concat(out, ",")
end

local function totalCount(state, bagOrder)
    local n = 0
    for _, bagID in ipairs(bagOrder) do
        for _, cell in pairs(state[bagID].slots) do
            n = n + cell.count
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Section 1: already-sorted input → zero moves
---------------------------------------------------------------------------
do
    local containers = {
        bag(0, 6, {
            [1] = item(10, { quality = 4 }),
            [2] = item(5, { quality = 3 }),
            [3] = item(7, { quality = 3 }),
            [4] = item(99, { quality = 1 }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    assert(#moves == 0, "already-sorted: expected 0 moves, got " .. #moves)
    assert(moves.combines == 0, "already-sorted: expected 0 combines")
end

---------------------------------------------------------------------------
-- Section 2: reverse-order input — simulate and verify the sorted layout
---------------------------------------------------------------------------
do
    local containers = {
        bag(0, 5, {
            [1] = item(4, { quality = 1 }),
            [2] = item(3, { quality = 2 }),
            [3] = item(2, { quality = 3 }),
            [4] = item(1, { quality = 4 }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    assert(#moves > 0, "reverse-order: expected moves")
    assert(moves.combines == 0, "reverse-order: no stacks to combine")
    local state = simulate(containers, moves)
    local got = flatten(state, { 0 })
    assert(got == "1x1,2x1,3x1,4x1,-", "reverse-order layout wrong: " .. got)
end

---------------------------------------------------------------------------
-- Section 3: stack combine
---------------------------------------------------------------------------
-- 3a: two partials merge fully — smaller pours onto larger
do
    local containers = {
        bag(0, 4, {
            [1] = item(7, { count = 5, maxStack = 20, quality = 1 }),
            [2] = item(7, { count = 7, maxStack = 20, quality = 1 }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    assert(moves.combines == 1, "combine-two: expected 1 combine, got " .. moves.combines)
    local m1 = moves[1]
    assert(m1.fromBag == 0 and m1.fromSlot == 1 and m1.toBag == 0 and m1.toSlot == 2,
        "combine-two: smaller stack must pour onto larger")
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "7x12,-,-,-",
        "combine-two layout wrong: " .. flatten(state, { 0 }))
    assert(totalCount(state, { 0 }) == 12, "combine-two lost items")
end

-- 3b: maxStack cap — partial pour leaves remainder at the source
do
    local containers = {
        bag(0, 2, {
            [1] = item(7, { count = 15, maxStack = 20, quality = 1 }),
            [2] = item(7, { count = 10, maxStack = 20, quality = 1 }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    assert(moves.combines == 1, "combine-cap: expected 1 combine")
    assert(#moves == 1, "combine-cap: capped merge needs no extra moves, got " .. #moves)
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "7x20,7x5",
        "combine-cap layout wrong: " .. flatten(state, { 0 }))
    assert(totalCount(state, { 0 }) == 25, "combine-cap lost items")
end

-- 3c: three partials collapse into one stack
do
    local containers = {
        bag(0, 3, {
            [1] = item(7, { count = 5, maxStack = 20, quality = 1 }),
            [2] = item(7, { count = 7, maxStack = 20, quality = 1 }),
            [3] = item(7, { count = 8, maxStack = 20, quality = 1 }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    assert(moves.combines == 2, "combine-three: expected 2 combines, got " .. moves.combines)
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "7x20,-,-",
        "combine-three layout wrong: " .. flatten(state, { 0 }))
    assert(totalCount(state, { 0 }) == 20, "combine-three lost items")
end

---------------------------------------------------------------------------
-- Section 4: ignored bag — contributes nothing, receives nothing, untouched
---------------------------------------------------------------------------
do
    local containers = {
        bag(0, 3, {
            [1] = item(3, { quality = 1 }),
            [2] = item(2, { quality = 4 }),
        }),
        bag(1, 2, {
            [1] = item(1, { quality = 5 }),  -- would sort FIRST if not ignored
        }, true),
    }
    local before = flatten(buildState(containers), { 1 })
    local moves = Planner.Plan(containers, { key = "quality" })
    for i, m in ipairs(moves) do
        assert(m.fromBag ~= 1 and m.toBag ~= 1,
            "ignored: move " .. i .. " touches the ignored bag")
    end
    local state = simulate(containers, moves)
    assert(flatten(state, { 1 }) == before, "ignored bag layout changed")
    assert(flatten(state, { 0 }) == "2x1,3x1,-",
        "active bag layout wrong: " .. flatten(state, { 0 }))
end

---------------------------------------------------------------------------
-- Section 5: nil-field items sort last, no errors
---------------------------------------------------------------------------
do
    -- key=name: the nil-name item goes last even with the lowest itemID
    local containers = {
        bag(0, 3, {
            [1] = item(50, {}),                    -- name = nil
            [2] = item(60, { name = "Apple" }),
            [3] = item(40, { name = "Banana" }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "name" })
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "60x1,40x1,50x1",
        "nil-name layout wrong: " .. flatten(state, { 0 }))
end
do
    -- key=ilvl: nil ilvl after a real ilvl
    local containers = {
        bag(0, 2, {
            [1] = item(1, {}),                     -- ilvl = nil
            [2] = item(9, { ilvl = 100 }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "ilvl" })
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "9x1,1x1",
        "nil-ilvl layout wrong: " .. flatten(state, { 0 }))
end

---------------------------------------------------------------------------
-- Section 6: cross-bag assignment
---------------------------------------------------------------------------
do
    local containers = {
        bag(0, 2, {
            [1] = item(3, { quality = 2 }),
        }),
        bag(1, 2, {
            [1] = item(1, { quality = 4 }),
            [2] = item(2, { quality = 3 }),
        }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "1x1,2x1",
        "cross-bag bag0 wrong: " .. flatten(state, { 0 }))
    assert(flatten(state, { 1 }) == "3x1,-",
        "cross-bag bag1 wrong: " .. flatten(state, { 1 }))
end

---------------------------------------------------------------------------
-- Section 7: virtual-state correctness — a 3-cycle resolves in ≤3 moves
---------------------------------------------------------------------------
do
    -- desired: A(q4) B(q3) C(q2); input: C A B → 1←2, 2←3, 3←1 (3-cycle)
    local containers = {
        bag(0, 3, {
            [1] = item(3, { quality = 2 }),  -- C
            [2] = item(1, { quality = 4 }),  -- A
            [3] = item(2, { quality = 3 }),  -- B
        }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    assert(#moves <= 3, "3-cycle: expected <= 3 moves, got " .. #moves)
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "1x1,2x1,3x1",
        "3-cycle layout wrong: " .. flatten(state, { 0 }))
end

---------------------------------------------------------------------------
-- Section 8: determinism + purity
---------------------------------------------------------------------------
do
    local containers = {
        bag(0, 4, {
            [1] = item(7, { count = 5, maxStack = 20, quality = 1 }),
            [2] = item(2, { quality = 4, name = "Zed" }),
            [3] = item(7, { count = 9, maxStack = 20, quality = 1 }),
        }),
        bag(1, 3, {
            [1] = item(5, { quality = 3, name = "Mid" }),
            [2] = item(7, { count = 11, maxStack = 20, quality = 1 }),
        }),
    }
    local pristine = deepCopy(containers)
    local m1 = Planner.Plan(containers, { key = "quality" })
    local m2 = Planner.Plan(containers, { key = "quality" })
    assert(deepEqual(m1, m2), "determinism: two Plan calls differ")
    assert(deepEqual(containers, pristine), "purity: Plan mutated its input")
    -- and the plan itself converges to a valid layout
    local state = simulate(containers, m1)
    assert(totalCount(state, { 0, 1 }) == 27, "determinism fixture lost items")
end

---------------------------------------------------------------------------
-- Section 9: per-key primary ordering, pinned with minimal pairs.
-- Each pair OPPOSES itemID order (itemID is a late tiebreaker in every
-- chain) so the assertion fails if the primary field is not consulted.
---------------------------------------------------------------------------
local function pinPair(key, first, second, expect)
    local containers = { bag(0, 2, { [1] = first, [2] = second }) }
    local moves = Planner.Plan(containers, { key = key })
    assert(#moves == 1, key .. " pair: expected exactly 1 move, got " .. #moves)
    local state = simulate(containers, moves)
    local got = flatten(state, { 0 })
    assert(got == expect, key .. " pair layout wrong: " .. got)
end

pinPair("quality",
    item(100, { quality = 2 }), item(200, { quality = 3 }), "200x1,100x1")
pinPair("type",
    item(100, { sortClass = 4, quality = 1 }), item(200, { sortClass = 2, quality = 1 }), "200x1,100x1")
pinPair("name",
    item(100, { name = "Banana" }), item(200, { name = "Apple" }), "200x1,100x1")
pinPair("ilvl",
    item(100, { ilvl = 100 }), item(200, { ilvl = 200 }), "200x1,100x1")
pinPair("expansion",
    item(100, { expacID = 9 }), item(200, { expacID = 10 }), "200x1,100x1")

---------------------------------------------------------------------------
-- Section 10: edges — empty containers; missing/unknown key falls back
-- to the quality chain
---------------------------------------------------------------------------
do
    local moves = Planner.Plan({ bag(0, 4, {}) }, { key = "name" })
    assert(#moves == 0 and moves.combines == 0, "empty bag: expected no moves")
end
do
    local containers = {
        bag(0, 2, {
            [1] = item(100, { quality = 2 }),
            [2] = item(200, { quality = 3 }),
        }),
    }
    local moves = Planner.Plan(containers, {})
    local state = simulate(containers, moves)
    assert(flatten(state, { 0 }) == "200x1,100x1",
        "default key must behave as quality: " .. flatten(state, { 0 }))
end

---------------------------------------------------------------------------
-- Section 11: bag-family restrictions. Specialty bags (family ~= 0) accept
-- only items whose itemFamily mask overlaps the bag family (retail reagent
-- bag = bagID 5). The simulator's legality asserts above make every test in
-- this file an illegal-move detector; these cases target the family paths.
---------------------------------------------------------------------------
local FAM = 4 -- synthetic family bit for the specialty bag

-- 11a: already-legal layout must stay put — the planner must NOT pull the
-- alphabetically-first reagents out of the specialty bag into the regular
-- bag and swap the swords in (the illegal positional plan).
do
    local containers = {
        bag(0, 2, {
            [1] = item(100, { name = "Zsword1" }),
            [2] = item(101, { name = "Zsword2" }),
        }),
        bag(5, 2, {
            [1] = item(50, { name = "Aherb1", itemFamily = FAM }),
            [2] = item(51, { name = "Aherb2", itemFamily = FAM }),
        }, false, FAM),
    }
    local moves = Planner.Plan(containers, { key = "name" })
    local state = simulate(containers, moves) -- legality asserts fire on any illegal plan
    assert(flatten(state, { 5 }) == "50x1,51x1",
        "specialty bag must keep its fitting items: " .. flatten(state, { 5 }))
    assert(flatten(state, { 0 }) == "100x1,101x1",
        "regular bag must keep the non-fitting items: " .. flatten(state, { 0 }))
    assert(#moves == 0, "already-legal layout must produce no churn, got " .. #moves .. " moves")
end

-- 11b: fitting items are pulled INTO the specialty bag (sorted order), and
-- the regular bag keeps the remainder.
do
    local containers = {
        bag(0, 4, {
            [1] = item(200, { name = "Zsword" }),
            [2] = item(50, { name = "Aherb", itemFamily = FAM }),
            [3] = item(51, { name = "Bherb", itemFamily = FAM }),
        }),
        bag(5, 2, {}, false, FAM),
    }
    local moves = Planner.Plan(containers, { key = "name" })
    local state = simulate(containers, moves)
    assert(flatten(state, { 5 }) == "50x1,51x1",
        "specialty bag must receive the fitting items in sort order: " .. flatten(state, { 5 }))
    assert(state[0].slots[1].itemID == 200, "regular bag slot 1 must hold the sword")
    assert(state[0].slots[2] == nil and state[0].slots[3] == nil,
        "vacated regular slots must end empty")
end

-- 11c: a better-sorted reagent evicts a specialty-bag resident (legal swap:
-- the displaced resident lands in the regular origin slot).
do
    local containers = {
        bag(0, 3, {
            [1] = item(50, { name = "Aherb", itemFamily = FAM }),
            [2] = item(200, { name = "Zsword" }),
        }),
        bag(5, 1, {
            [1] = item(51, { name = "Bherb", itemFamily = FAM }),
        }, false, FAM),
    }
    local moves = Planner.Plan(containers, { key = "name" })
    local state = simulate(containers, moves)
    assert(state[5].slots[1].itemID == 50,
        "specialty bag must hold the best-sorted fitting item, got "
        .. tostring(state[5].slots[1] and state[5].slots[1].itemID))
    -- the displaced resident stays in the regular bag (exact slot is the
    -- planner's choice; legality is what matters)
    local found = false
    for s = 1, state[0].size do
        if state[0].slots[s] and state[0].slots[s].itemID == 51 then found = true end
    end
    assert(found, "evicted resident must land in the regular bag")
end

-- 11d: cross-family displacement reroutes through an empty slot. The f1
-- bag's target wants the multi-family item living in the f2 bag, but the
-- f1 resident does NOT fit the f2 origin — the planner must move the
-- resident to the empty regular slot first instead of emitting an illegal
-- swap (the simulator would throw on it).
do
    local F1, F2 = 1, 2
    local containers = {
        bag(0, 1, {}), -- empty regular slot: the reroute landing zone
        bag(1, 1, {
            [1] = item(60, { name = "Zonly1", itemFamily = F1 }),
        }, false, F1),
        bag(2, 1, {
            [1] = item(61, { name = "Aboth", itemFamily = F1 + F2 }),
        }, false, F2),
    }
    local moves = Planner.Plan(containers, { key = "name" })
    local state = simulate(containers, moves)
    assert(state[1].slots[1] and state[1].slots[1].itemID == 61,
        "f1 bag must receive the better-sorted multi-family item")
    assert(state[0].slots[1] and state[0].slots[1].itemID == 60,
        "displaced f1-only resident must be rerouted to the regular slot")
end

-- reverse option: flips every comparator direction; nils still sort last
do
    -- q4 in slot 1, q1 in slot 2: default quality order is already placed
    local containers = {
        bag(0, 2, { [1] = item(101, { quality = 4 }), [2] = item(102, { quality = 1 }) }),
    }
    local moves = Planner.Plan(containers, { key = "quality" })
    assert(#moves == 0, "default: q4-first already sorted, got " .. #moves .. " moves")

    local rmoves = Planner.Plan(containers, { key = "quality", reverse = true })
    assert(#rmoves == 1, "reverse: expected exactly 1 swap, got " .. #rmoves)
    assert(rmoves[1].fromBag == 0 and rmoves[1].fromSlot == 2
        and rmoves[1].toBag == 0 and rmoves[1].toSlot == 1,
        "reverse: q1 should move to slot 1")
    local state = simulate(containers, rmoves)
    assert(state[0].slots[1].itemID == 102 and state[0].slots[2].itemID == 101,
        "reverse: worst quality must land first")
end

-- reverse keeps nil-last: an unloaded entry must not jump to the front
do
    local containers = {
        bag(0, 2, { [1] = item(201, { quality = nil }), [2] = item(202, { quality = 1 }) }),
    }
    local rmoves = Planner.Plan(containers, { key = "quality", reverse = true })
    assert(#rmoves == 1, "reverse nil-last: expected 1 swap, got " .. #rmoves)
    local state = simulate(containers, rmoves)
    assert(state[0].slots[1].itemID == 202,
        "reverse: nil-quality entry must still sort last")
end

print("OK: bags_sort_planner_test")
