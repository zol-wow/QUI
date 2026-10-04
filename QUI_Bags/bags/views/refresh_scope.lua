local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local RefreshScope = {}
Bags.RefreshScope = RefreshScope

function RefreshScope.Classify(changed)
    if type(changed) ~= "table" then return "full" end
    if #changed == 0 then return "dress-all" end
    return "dress-bags"
end

function RefreshScope.UnionBags(pending, changed)
    pending = pending or {}
    for _, bagID in ipairs(changed) do pending[bagID] = true end
    return pending
end

function RefreshScope.LayoutSignature(slots, opts, buildDetails)
    local categories = opts.layoutMode == "categories"
    local sortKey = Bags.SortPlanner.ResolveKey(opts.sortKey)
    local parts = {
        categories and table.concat({ "cat", sortKey,
            opts.sortReverse and "reverse" or "forward" }, "\1")
            or ("flat:" .. tostring(opts.reagentDisplay or "separate")
                .. (opts.groupEmptySlots and ":g" or ":-")),
    }
    for _, cell in ipairs(slots) do
        if categories then
            if cell.entry then
                local details = buildDetails and buildDetails(cell.entry) or nil
                local recent = opts.getRecent and opts.getRecent(cell) or false
                parts[#parts + 1] = table.concat({
                    cell.bagID, cell.slot,
                    recent and "recent" or Bags.CategoryLayout.Categorize(details),
                    (details and details.quality) or cell.entry.quality or -1,
                    (details and details.name) or "",
                    cell.entry.itemID or 0,
                    (details and details.classID) or -1,
                    (details and details.subClassID) or -1,
                    (details and details.ilvl) or -1,
                    (details and details.expacID) or -1,
                    sortKey == "quality" and (cell.entry.count or 1) or "",
                }, "\1")
            end
        elseif opts.groupEmptySlots then
            parts[#parts + 1] = cell.bagID .. "\1" .. cell.slot
                .. "\1" .. (cell.entry and 1 or 0)
        else
            parts[#parts + 1] = cell.bagID .. "\1" .. cell.slot
        end
    end
    return table.concat(parts, "\2")
end
