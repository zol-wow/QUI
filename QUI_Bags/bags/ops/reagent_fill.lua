local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local ReagentFill = {}
Bags.ReagentFill = ReagentFill

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
    if not target then return {} end
    local targetReagent = target.reagent and true or false
    if not targetReagent and (not target.family or target.family == 0) then return {} end
    local function accepts(e)
        if not (e and e.itemID) then return false end
        if targetReagent then return e.isReagent == true end
        return e.itemFamily and e.itemFamily ~= 0 and band(e.itemFamily, target.family) ~= 0
    end

    local partials = {}
    local empties = {}
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
                if accepts(e) then
                    local remaining = e.count or 1
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
                    if remaining > 0 and emptyIdx <= #empties then
                        local toSlot = empties[emptyIdx]
                        emptyIdx = emptyIdx + 1
                        moves[#moves + 1] = {
                            fromBag = c.bagID, fromSlot = slot,
                            toBag = targetBagID, toSlot = toSlot,
                            itemID = e.itemID,
                        }
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
