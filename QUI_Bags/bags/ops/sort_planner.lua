---------------------------------------------------------------------------
-- Bags ops: pure sort planner (NO WoW APIs — headless-testable).
--
-- Plan(containers, opts) → array of moves { fromBag, fromSlot, toBag,
-- toSlot } plus `.combines` (count of stack-merge moves included in the
-- list). Each move = cursor pickup→place; placing onto an occupied slot
-- swaps. The executor replays the list against live state and re-plans
-- between batches, so the planner stays cheap and side-effect free.
--
-- Input shape: containers = array of { bagID, size, slots = {[slot] =
-- entry|nil}, ignored = bool, family = number|nil }. entry = the cache
-- shape (itemID, count, quality, …) plus caller-provided enrichment:
-- sortClass, sortSubClass, ilvl, name, expacID, maxStack, itemFamily.
-- opts = { key = "quality"|"type"|"name"|"ilvl"|"expansion", reverse = bool }
-- (unknown/missing key → quality chain; reverse flips every comparator
-- direction wholesale — nil-last and the stability tiebreaker stay fixed).
--
-- Bag families: family ~= 0 marks a specialty container (retail reagent
-- bag) that only accepts entries whose itemFamily mask overlaps it
-- (GetContainerNumFreeSlots second return × GetItemFamily — both nilable,
-- nil → 0). nil/0 itemFamily never fits a specialty bag (pending item data
-- stays out conservatively; the executor re-plans when it loads).
--
-- Three phases over a VIRTUAL copy of the state (input never mutated):
--   A) stack-combine: 2+ partial stacks of an item merge smaller→larger,
--      capped at maxStack (a partial pour leaves the remainder at the
--      source — matching cursor merge semantics).
--   B) ordering: comparator chain per key; nil fields sort LAST within
--      their comparator; a final original-order tiebreaker makes the
--      sort stable and fully deterministic.
--   C) assignment, two passes: SPECIALTY targets first (each claims the
--      best-sorted still-unplaced FITTING cell — Blizzard/reference
--      semantics: reagents pack into the reagent bag), then regular
--      targets take the remainder in sorted order. Each emitted move pulls
--      the desired item from its CURRENT virtual location (reflecting all
--      earlier moves) and swap-updates the displaced occupant — unless the
--      occupant would land in a specialty origin it doesn't fit, in which
--      case it reroutes through an empty accepting slot first (no move is
--      ever emitted that the server would reject).
-- Ignored containers contribute nothing, receive nothing, stay untouched.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local SortPlanner = {}
Bags.SortPlanner = SortPlanner

-- Comparator chains: { fieldName, descending? } consulted in order.
-- "count" reads the VIRTUAL (post-combine) count; all other fields read
-- the entry. nil values sort after non-nil within every step.
local CHAINS = {
    quality   = { { "quality", true }, { "sortClass" }, { "sortSubClass" },
                  { "ilvl", true }, { "name" }, { "itemID" }, { "count", true } },
    type      = { { "sortClass" }, { "sortSubClass" }, { "ilvl", true },
                  { "quality", true }, { "name" }, { "itemID" } },
    name      = { { "name" }, { "ilvl", true }, { "itemID" } },
    ilvl      = { { "ilvl", true }, { "sortClass" }, { "quality", true },
                  { "name" }, { "itemID" } },
    expansion = { { "expacID", true }, { "sortClass" }, { "quality", true },
                  { "name" }, { "itemID" } },
}

local function fieldValue(cell, field)
    if field == "count" then return cell.count end
    return cell.entry[field]
end

local function makeComparator(chain, reverse)
    return function(a, b)
        for i = 1, #chain do
            local step = chain[i]
            local va, vb = fieldValue(a, step[1]), fieldValue(b, step[1])
            if va ~= vb then
                if va == nil then return false end -- nil sorts last
                if vb == nil then return true end
                local desc = step[2]
                if reverse then desc = not desc end
                if desc then return va > vb end
                return va < vb
            end
        end
        return a.seq < b.seq -- original scan order: stable + deterministic
    end
end

-- Deterministic partial-stack order for Phase A: largest first, position
-- as the tiebreaker. The two-pointer walk then pours the smallest stack
-- into the largest with room.
local function byCountDesc(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- Pure-Lua bitwise AND (the planner is headless-testable: no WoW `bit`
-- library). Family masks are small integers, so the %2 walk is cheap.
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

-- Can this cell legally sit in a container of the given family?
-- Unrestricted (nil/0) accepts everything; a specialty family requires an
-- overlapping itemFamily mask. nil/0 itemFamily (regular item, or item data
-- still loading) never fits a specialty bag.
local function Fits(cell, family)
    if not family or family == 0 then return true end
    local itemFamily = cell.entry.itemFamily
    if not itemFamily or itemFamily == 0 then return false end
    return band(itemFamily, family) ~= 0
end

--- containers: see header. opts: { key = sort key }. Returns the move
--- array with `.combines`. Pure — never mutates `containers`.
function SortPlanner.Plan(containers, opts)
    local chain = CHAINS[opts and opts.key] or CHAINS.quality
    local reverse = (opts and opts.reverse) and true or false

    -- Snapshot: wrap every occupied slot in a cell (unique identity even
    -- when itemIDs repeat) and index its virtual location on the cell.
    local virtual = {} -- [bagID] = { [slot] = cell|nil }
    local active = {}  -- non-ignored containers, input order
    local cells = {}   -- scan order (containers in input order, slots 1..size)
    for _, container in ipairs(containers) do
        if not container.ignored then
            local slots = {}
            for slot = 1, container.size do
                local entry = container.slots[slot]
                if entry then
                    local cell = {
                        entry = entry,
                        count = entry.count or 1,
                        bag = container.bagID,
                        slot = slot,
                        seq = #cells + 1,
                    }
                    slots[slot] = cell
                    cells[#cells + 1] = cell
                end
            end
            virtual[container.bagID] = slots
            active[#active + 1] = container
        end
    end

    local moves = {}
    local combines = 0

    -- Phase A: stack-combine. Group partial stacks (count < maxStack) by
    -- itemID; itemIDs processed in ascending order for determinism.
    local groups, groupIDs = {}, {}
    for _, cell in ipairs(cells) do
        local maxStack = cell.entry.maxStack
        if cell.entry.itemID and maxStack and maxStack > 1 and cell.count < maxStack then
            local group = groups[cell.entry.itemID]
            if not group then
                group = {}
                groups[cell.entry.itemID] = group
                groupIDs[#groupIDs + 1] = cell.entry.itemID
            end
            group[#group + 1] = cell
        end
    end
    table.sort(groupIDs)
    for _, itemID in ipairs(groupIDs) do
        local group = groups[itemID]
        if #group >= 2 then
            table.sort(group, byCountDesc)
            local maxStack = group[1].entry.maxStack
            local i, j = 1, #group -- i = fill target (largest), j = source (smallest)
            while i < j do
                local dst, src = group[i], group[j]
                local room = maxStack - dst.count
                if room <= 0 then
                    i = i + 1
                else
                    local xfer = room < src.count and room or src.count
                    moves[#moves + 1] = {
                        fromBag = src.bag, fromSlot = src.slot,
                        toBag = dst.bag, toSlot = dst.slot,
                    }
                    combines = combines + 1
                    dst.count = dst.count + xfer
                    src.count = src.count - xfer
                    if src.count == 0 then
                        virtual[src.bag][src.slot] = nil
                        src.dead = true
                        j = j - 1
                    end
                    if dst.count >= maxStack then i = i + 1 end
                end
            end
        end
    end

    -- Phase B: ordering over the post-combine virtual population.
    local sorted = {}
    for _, cell in ipairs(cells) do
        if not cell.dead then sorted[#sorted + 1] = cell end
    end
    table.sort(sorted, makeComparator(chain, reverse))

    -- Phase C: assignment, two passes. Specialty targets (family ~= 0)
    -- claim the best-sorted still-unplaced FITTING cells first; regular
    -- targets then take the remainder in sorted order. Every emitted move
    -- is family-legal: a displaced occupant that wouldn't fit the want's
    -- origin container reroutes through an empty accepting slot instead.
    local specialtyTargets, regularTargets = {}, {}
    local familyOf = {} -- bagID → family (0 = unrestricted)
    for _, container in ipairs(active) do
        local family = container.family or 0
        familyOf[container.bagID] = family
        local list = (family ~= 0) and specialtyTargets or regularTargets
        for slot = 1, container.size do
            list[#list + 1] = { bag = container.bagID, slot = slot, family = family }
        end
    end

    local cursor = 1 -- sorted-order scan start; advances past placed cells
    local function NextUnplaced(family)
        while sorted[cursor] and sorted[cursor].placed do cursor = cursor + 1 end
        for i = cursor, #sorted do
            local cell = sorted[i]
            if not cell.placed and Fits(cell, family) then return cell end
        end
        return nil
    end

    -- First empty virtual slot that accepts the cell (reroute landing zone
    -- for displaced occupants). Walks containers in input order.
    local function FindEmptyFor(cell)
        for _, container in ipairs(active) do
            if Fits(cell, container.family or 0) then
                local slots = virtual[container.bagID]
                for slot = 1, container.size do
                    if not slots[slot] then return container.bagID, slot end
                end
            end
        end
        return nil
    end

    -- Place `want` at `target`, emitting the move(s). Swapped occupants
    -- land at want's origin; when that origin is a specialty container the
    -- occupant doesn't fit, the occupant is rerouted to an empty accepting
    -- slot first (two legal moves instead of one illegal swap). Returns
    -- without placing when no reroute slot exists (pathological full-bags
    -- cross-family case; the executor's stall valve owns that story).
    local function Place(want, target)
        local occupant = virtual[target.bag][target.slot]
        if occupant == want then
            want.placed = true
            return
        end
        if occupant and not Fits(occupant, familyOf[want.bag]) then
            local emptyBag, emptySlot = FindEmptyFor(occupant)
            if not emptyBag then return end
            moves[#moves + 1] = {
                fromBag = target.bag, fromSlot = target.slot,
                toBag = emptyBag, toSlot = emptySlot,
            }
            virtual[emptyBag][emptySlot] = occupant
            virtual[target.bag][target.slot] = nil
            occupant.bag, occupant.slot = emptyBag, emptySlot
            occupant = nil
        end
        local fromBag, fromSlot = want.bag, want.slot
        moves[#moves + 1] = {
            fromBag = fromBag, fromSlot = fromSlot,
            toBag = target.bag, toSlot = target.slot,
        }
        virtual[target.bag][target.slot] = want
        want.bag, want.slot = target.bag, target.slot
        want.placed = true
        virtual[fromBag][fromSlot] = occupant
        if occupant then
            occupant.bag, occupant.slot = fromBag, fromSlot
        end
    end

    for _, target in ipairs(specialtyTargets) do
        local want = NextUnplaced(target.family)
        if want then Place(want, target) end
    end
    for _, target in ipairs(regularTargets) do
        local want = NextUnplaced(0)
        if not want then break end -- everything placed; rest stays empty
        Place(want, target)
    end

    moves.combines = combines
    return moves
end
