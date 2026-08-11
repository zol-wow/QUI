local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local SortPlanner = {}
Bags.SortPlanner = SortPlanner

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
                if va == nil then return false end
                if vb == nil then return true end
                local desc = step[2]
                if reverse then desc = not desc end
                if desc then return va > vb end
                return va < vb
            end
        end
        return a.seq < b.seq
    end
end

local function byCountDesc(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

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

local function Fits(cell, family, reagent)
    if reagent then return cell.entry.isReagent == true end
    if not family or family == 0 then return true end
    local itemFamily = cell.entry.itemFamily
    if not itemFamily or itemFamily == 0 then return false end
    return band(itemFamily, family) ~= 0
end

function SortPlanner.Plan(containers, opts)
    local chain = CHAINS[opts and opts.key] or CHAINS.quality
    local reverse = (opts and opts.reverse) and true or false
    local fillFromBottom = (opts and opts.fillFromBottom) and true or false

    local virtual = {}
    local active = {}
    local cells = {}
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
            local i, j = 1, #group
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

    local sorted = {}
    for _, cell in ipairs(cells) do
        if not cell.dead then sorted[#sorted + 1] = cell end
    end
    table.sort(sorted, makeComparator(chain, reverse))

    local specialtyTargets, regularTargets = {}, {}
    local familyOf = {}
    local reagentOf = {}
    for _, container in ipairs(active) do
        local family = container.family or 0
        local reagent = container.reagent and true or false
        familyOf[container.bagID] = family
        reagentOf[container.bagID] = reagent
        local list = (family ~= 0 or reagent) and specialtyTargets or regularTargets
        for slot = 1, container.size do
            list[#list + 1] = { bag = container.bagID, slot = slot,
                family = family, reagent = reagent }
        end
    end

    local cursor = 1
    local function NextUnplaced(family, reagent)
        while sorted[cursor] and sorted[cursor].placed do cursor = cursor + 1 end
        for i = cursor, #sorted do
            local cell = sorted[i]
            if not cell.placed and Fits(cell, family, reagent) then return cell end
        end
        return nil
    end

    local function FindEmptyFor(cell)
        for _, container in ipairs(active) do
            if Fits(cell, container.family or 0, container.reagent) then
                local slots = virtual[container.bagID]
                for slot = 1, container.size do
                    if not slots[slot] then return container.bagID, slot end
                end
            end
        end
        return nil
    end

    local function Place(want, target)
        local occupant = virtual[target.bag][target.slot]
        if occupant == want then
            want.placed = true
            return
        end
        if occupant and not Fits(occupant, familyOf[want.bag], reagentOf[want.bag]) then
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
        local want = NextUnplaced(target.family, target.reagent)
        if want then Place(want, target) end
    end
    local regularSkip = 0
    if fillFromBottom then
        local remaining = 0
        for i = cursor, #sorted do
            if not sorted[i].placed then remaining = remaining + 1 end
        end
        regularSkip = #regularTargets - remaining
        if regularSkip < 0 then regularSkip = 0 end
    end
    for idx, target in ipairs(regularTargets) do
        if idx > regularSkip then
            local want = NextUnplaced(0, false)
            if not want then break end
            Place(want, target)
        end
    end

    moves.combines = combines
    return moves
end
