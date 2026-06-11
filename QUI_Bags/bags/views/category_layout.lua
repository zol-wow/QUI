---------------------------------------------------------------------------
-- Bags views: category layout engine (PURE math, headless-testable — the
-- "future category engine" grid_layout.lua's header promised).
-- Groups occupied cells into ordered buckets and stacks one grid per
-- bucket under a header row, on the same TOPLEFT-relative coordinate
-- contract as GridLayout (y negative going down).
--
-- Buckets (ItemClass EnumValues per ItemConstantsDocumentation.lua:199):
--   recent      — cell.recent flag (new-item tracking), outranks everything
--   equipment   — Weapon(2) + Armor(4)
--   consumables — Consumable(0)
--   trade       — Tradegoods(7) + Reagent(5) + Profession(19)
--   quest       — Questitem(12) + Key(13)
--   recipes     — Recipe(9)
--   battlepets  — Battlepet(17)
--   misc        — everything else (incl. Container(1), pending details)
--   junk        — quality 0 (outranks class), always last
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local CategoryLayout = {}
Bags.CategoryLayout = CategoryLayout

-- Ordered bucket definitions (render order; junk deliberately last).
CategoryLayout.CATEGORIES = {
    { key = "recent",      title = "Recent" },
    { key = "equipment",   title = "Equipment" },
    { key = "consumables", title = "Consumables" },
    { key = "trade",       title = "Trade Goods" },
    { key = "quest",       title = "Quest" },
    { key = "recipes",     title = "Recipes" },
    { key = "battlepets",  title = "Battle Pets" },
    { key = "misc",        title = "Miscellaneous" },
    { key = "junk",        title = "Junk" },
}

local CLASS_BUCKET = {
    [2] = "equipment", [4] = "equipment",
    [0] = "consumables",
    [7] = "trade", [5] = "trade", [19] = "trade",
    [12] = "quest", [13] = "quest",
    [9] = "recipes",
    [17] = "battlepets",
}

--- details (Details.Build shape: classID/quality/name) → bucket key.
--- Pending (nil) details fall into misc — the next refresh re-buckets them.
function CategoryLayout.Categorize(details)
    if not details then return "misc" end
    if details.quality == 0 then return "junk" end
    return CLASS_BUCKET[details.classID] or "misc"
end

--- cells: array of { bagID, slot, entry|nil, recent? }; buildDetails(entry)
--- → details|nil (injectable — pure). Empty slots are dropped. → ordered
--- array of { key, title, cells } with empty buckets omitted; in-bucket
--- sort is quality desc → name asc (pending names last) → itemID asc.
function CategoryLayout.Group(cells, buildDetails)
    local buckets = {}
    for _, cell in ipairs(cells) do
        if cell.entry then
            local details = buildDetails(cell.entry)
            local key = cell.recent and "recent" or CategoryLayout.Categorize(details)
            local b = buckets[key]
            if not b then b = {}; buckets[key] = b end
            b[#b + 1] = cell
            cell._sortDetails = details
        end
    end
    local function less(a, b)
        local da, db = a._sortDetails, b._sortDetails
        local qa = (da and da.quality) or (a.entry.quality) or -1
        local qb = (db and db.quality) or (b.entry.quality) or -1
        if qa ~= qb then return qa > qb end
        local na, nb = da and da.name, db and db.name
        if na ~= nb then
            if na == nil then return false end
            if nb == nil then return true end
            return na < nb
        end
        return (a.entry.itemID or 0) < (b.entry.itemID or 0)
    end
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

--- groups (from Group) + config { columns, iconSize, spacing, headerHeight }
--- → { buttons = { { cell, x, y } ... }, headers = { { title, y } ... },
---     width, height }. One full-columns-wide grid per bucket, stacked
--- under its header; sections are separated by one `spacing` gap.
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
    out.height = -y - gap -- drop the trailing section gap
    if out.height < 0 then out.height = 0 end
    return out
end

return CategoryLayout
