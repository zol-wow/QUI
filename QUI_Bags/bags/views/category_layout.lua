local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local CategoryLayout = {}
Bags.CategoryLayout = CategoryLayout

CategoryLayout.CATEGORIES = {
    { key = "recent",      title = ns.L["Recent"] },
    { key = "equipment",   title = ns.L["Equipment"] },
    { key = "consumables", title = ns.L["Consumables"] },
    { key = "trade",       title = ns.L["Trade Goods"] },
    { key = "quest",       title = ns.L["Quest"] },
    { key = "recipes",     title = ns.L["Recipes"] },
    { key = "battlepets",  title = ns.L["Battle Pets"] },
    { key = "misc",        title = ns.L["Miscellaneous"] },
    { key = "junk",        title = ns.L["Junk"] },
}

local CLASS_BUCKET = {
    [2] = "equipment", [4] = "equipment",
    [0] = "consumables",
    [7] = "trade", [5] = "trade", [19] = "trade",
    [12] = "quest", [13] = "quest",
    [9] = "recipes",
    [17] = "battlepets",
}

function CategoryLayout.Categorize(details)
    if not details then return "misc" end
    if details.quality == 0 then return "junk" end
    return CLASS_BUCKET[details.classID] or "misc"
end

function CategoryLayout.Group(cells, buildDetails, opts)
    local buckets = {}
    for seq, cell in ipairs(cells) do
        if cell.entry then
            local details = buildDetails(cell.entry)
            local key = cell.recent and "recent" or CategoryLayout.Categorize(details)
            local b = buckets[key]
            if not b then b = {}; buckets[key] = b end
            b[#b + 1] = cell
            cell._sortDetails = {
                entry = {
                    quality = (details and details.quality) or cell.entry.quality,
                    sortClass = details and details.classID,
                    sortSubClass = details and details.subClassID,
                    ilvl = details and details.ilvl,
                    name = details and details.name,
                    expacID = details and details.expacID,
                    itemID = cell.entry.itemID,
                },
                count = cell.entry.count or 1,
                seq = seq,
            }
        end
    end
    local compare = Bags.SortPlanner.MakeComparator(opts)
    local function less(a, b) return compare(a._sortDetails, b._sortDetails) end
    local groups = {}
    for _, def in ipairs(CategoryLayout.CATEGORIES) do
        local b = buckets[def.key]
        if b and #b > 0 then
            table.sort(b, less)
            for _, cell in ipairs(b) do cell._sortDetails = nil end
            groups[#groups + 1] = { key = def.key, title = def.title, cells = b }
        end
    end
    return groups
end

function CategoryLayout.Compute(groups, config)
    local headerH = config.headerHeight or 16
    local gap = config.spacing or 4
    local out = { buttons = {}, headers = {} }
    local y = 0
    local width = 0
    for _, group in ipairs(groups) do
        out.headers[#out.headers + 1] = { title = group.title, y = y }
        y = y - headerH
        local grid = Bags.GridLayout.Compute(#group.cells, config)
        for i, cell in ipairs(group.cells) do
            out.buttons[#out.buttons + 1] = {
                cell = cell, x = grid[i].x, y = y + grid[i].y,
            }
        end
        width = math.max(width, grid.width)
        y = y - grid.height - gap
    end
    out.width = width
    out.height = -y - gap
    if out.height < 0 then out.height = 0 end
    return out
end

return CategoryLayout
