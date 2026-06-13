-- tests/unit/bags_reagent_fill_test.lua
-- Run: lua tests/unit/bags_reagent_fill_test.lua
-- Pure planner: loaded with NO WoW stubs on purpose — any WoW API
-- reference in reagent_fill.lua crashes this suite.
local ns = {}
local chunk = assert(loadfile("QUI_Bags/bags/ops/reagent_fill.lua"))
chunk("QUI", ns)
local Fill = ns.Bags.ReagentFill
assert(Fill and Fill.Plan, "ReagentFill.Plan missing")

local function item(id, opts)
    opts = opts or {}
    return {
        itemID = id,
        count = opts.count or 1,
        maxStack = opts.maxStack,
        itemFamily = opts.itemFamily,
        isReagent = opts.isReagent,
    }
end

local function bag(bagID, size, slotItems, family, reagent)
    return { bagID = bagID, size = size, slots = slotItems or {},
             family = family or 0, reagent = reagent }
end

-- REAGENT family bit = 64 on retail; the planner only needs mask overlap.
local R = 64

-- 1) merge into an existing partial stack in the target first
do
    local containers = {
        bag(0, 2, { [1] = item(10, { count = 5, maxStack = 20, itemFamily = R }) }),
        bag(5, 2, { [1] = item(10, { count = 18, maxStack = 20, itemFamily = R }) }, R),
    }
    local moves = Fill.Plan(containers, 5)
    -- pour caps at maxStack: 2 into the existing stack, remainder (3) into the empty slot
    assert(#moves == 2, "expected pour + remainder move, got " .. #moves)
    assert(moves[1].fromBag == 0 and moves[1].fromSlot == 1
        and moves[1].toBag == 5 and moves[1].toSlot == 1, "first move must merge into the partial stack")
    assert(moves[2].toBag == 5 and moves[2].toSlot == 2, "remainder must land in the empty slot")
    assert(moves[1].itemID == 10 and moves[2].itemID == 10, "moves carry source itemID for re-validation")
end

-- 2) non-reagents and full target: nothing planned
do
    local containers = {
        bag(0, 2, { [1] = item(11, { count = 1, maxStack = 20, itemFamily = 0 }) }),
        bag(5, 1, { [1] = item(10, { count = 20, maxStack = 20, itemFamily = R }) }, R),
    }
    assert(#Fill.Plan(containers, 5) == 0, "no fitting items / no room → empty plan")
end

-- 3) stop when the target runs out of empty slots
do
    local containers = {
        bag(0, 3, {
            [1] = item(12, { count = 1, maxStack = 1, itemFamily = R }),
            [2] = item(13, { count = 1, maxStack = 1, itemFamily = R }),
            [3] = item(14, { count = 1, maxStack = 1, itemFamily = R }),
        }),
        bag(5, 1, {}, R),
    }
    local moves = Fill.Plan(containers, 5)
    assert(#moves == 1, "one empty slot → exactly one move, got " .. #moves)
end

-- 4) missing/unrestricted target → empty plan (no reagent bag equipped)
do
    assert(#Fill.Plan({ bag(0, 1, { [1] = item(10, { itemFamily = R }) }) }, 5) == 0,
        "no target container → empty plan")
end

-- 5) a moved partial stack becomes a pour target for later sources
do
    local containers = {
        bag(0, 2, {
            [1] = item(15, { count = 5, maxStack = 20, itemFamily = R }),
            [2] = item(15, { count = 4, maxStack = 20, itemFamily = R }),
        }),
        bag(5, 1, {}, R),
    }
    local moves = Fill.Plan(containers, 5)
    -- slot1's stack lands in the empty slot; slot2's pours into it (room 15)
    assert(#moves == 2, "expected land + pour, got " .. #moves)
    assert(moves[1].fromSlot == 1 and moves[1].toBag == 5 and moves[1].toSlot == 1,
        "first stack lands in the empty slot")
    assert(moves[2].fromSlot == 2 and moves[2].toBag == 5 and moves[2].toSlot == 1,
        "second stack pours into the landed partial")
end

-- 6) universal reagent bag (target.reagent == true): eligibility is isReagent,
-- NOT the family mask (the reagent bag is outside the family system). A
-- crafting reagent with NO itemFamily still sweeps in; a non-reagent stays out.
do
    local containers = {
        bag(0, 3, {
            [1] = item(20, { count = 1, maxStack = 1, isReagent = true }),  -- no family
            [2] = item(21, { count = 1, maxStack = 1, isReagent = false }), -- non-reagent
            [3] = item(22, { count = 1, maxStack = 1, isReagent = true }),
        }),
        bag(5, 5, {}, 0, true), -- reagent bag: family 0, reagent flag set
    }
    local moves = Fill.Plan(containers, 5)
    assert(#moves == 2, "only the two reagents sweep in, got " .. #moves)
    for _, m in ipairs(moves) do
        assert(m.itemID == 20 or m.itemID == 22,
            "non-reagent must not be swept into the reagent bag (itemID " .. m.itemID .. ")")
    end
end

-- 7) reagent bag with NO reagent flag and family 0 → empty plan (defensive:
-- never sweep into a plain bag mistaken for a target).
do
    local containers = {
        bag(0, 1, { [1] = item(20, { isReagent = true }) }),
        bag(5, 2, {}, 0, false),
    }
    assert(#Fill.Plan(containers, 5) == 0,
        "a non-reagent, non-family target must plan nothing")
end

print("OK: bags_reagent_fill_test")
