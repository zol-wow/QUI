---------------------------------------------------------------------------
-- Bags ops: pure reagent-fill planner (NO WoW APIs — headless-testable).
--
-- Plan(containers, targetBagID) → array of moves { fromBag, fromSlot,
-- toBag, toSlot, itemID } sweeping family-fitting items from every OTHER
-- container into the target specialty container: merge into the target's
-- partial stacks first (capped at maxStack; a partial pour leaves the
-- remainder at the source, matching cursor merge semantics), then move
-- whole stacks into empty target slots until none remain. A stack that
-- lands partial becomes a pour target for later sources of the same item.
--
-- Input shape matches sort_planner: containers = array of { bagID, size,
-- slots = {[slot] = entry|nil}, family }. entry needs itemID, count,
-- maxStack, itemFamily. itemID rides on each move so the executor can
-- re-validate the source slot before acting.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local ReagentFill = {}
Bags.ReagentFill = ReagentFill

-- Pure-Lua bitwise AND (sort_planner precedent: masks are small ints).
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

function ReagentFill.Plan(containers, targetBagID)
    local target = nil
    for _, c in ipairs(containers) do
        if c.bagID == targetBagID then target = c end
    end
    if not target or not target.family or target.family == 0 then return {} end

    -- Virtual target state: partial stacks by itemID + ordered empty slots.
    local partials = {} -- itemID → array of { slot, count, maxStack }
    local empties = {}  -- ascending slot list
    for slot = 1, target.size do
        local e = target.slots[slot]
        if not e then
            empties[#empties + 1] = slot
        elseif e.itemID and e.maxStack and e.maxStack > 1 and (e.count or 1) < e.maxStack then
            local list = partials[e.itemID]
            if not list then list = {}; partials[e.itemID] = list end
            list[#list + 1] = { slot = slot, count = e.count or 1, maxStack = e.maxStack }
        end
    end

    local moves = {}
    local emptyIdx = 1
    for _, c in ipairs(containers) do
        if c.bagID ~= targetBagID then
            for slot = 1, c.size do
                local e = c.slots[slot]
                if e and e.itemID and e.itemFamily and e.itemFamily ~= 0
                    and band(e.itemFamily, target.family) ~= 0 then
                    local remaining = e.count or 1
                    -- merge into existing partial stacks first
                    local list = partials[e.itemID]
                    if list then
                        for _, p in ipairs(list) do
                            if remaining <= 0 then break end
                            local room = p.maxStack - p.count
                            if room > 0 then
                                local xfer = room < remaining and room or remaining
                                moves[#moves + 1] = {
                                    fromBag = c.bagID, fromSlot = slot,
                                    toBag = targetBagID, toSlot = p.slot,
                                    itemID = e.itemID,
                                }
                                p.count = p.count + xfer
                                remaining = remaining - xfer
                            end
                        end
                    end
                    -- whole remainder into the next empty slot, if any
                    if remaining > 0 and emptyIdx <= #empties then
                        local toSlot = empties[emptyIdx]
                        emptyIdx = emptyIdx + 1
                        moves[#moves + 1] = {
                            fromBag = c.bagID, fromSlot = slot,
                            toBag = targetBagID, toSlot = toSlot,
                            itemID = e.itemID,
                        }
                        -- the landed stack may itself be partial: later
                        -- sources of the same item can pour into it
                        if e.maxStack and e.maxStack > 1 and remaining < e.maxStack then
                            local list2 = partials[e.itemID]
                            if not list2 then list2 = {}; partials[e.itemID] = list2 end
                            list2[#list2 + 1] = { slot = toSlot, count = remaining, maxStack = e.maxStack }
                        end
                    end
                end
            end
        end
    end
    return moves
end
