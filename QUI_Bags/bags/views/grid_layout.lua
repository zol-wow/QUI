local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local GridLayout = {}
Bags.GridLayout = GridLayout

function GridLayout.Compute(count, config)
    local columns = math.max(1, math.floor(config.columns or 12))
    local size = config.iconSize or 36
    local gap = config.spacing or 4
    local step = size + gap

    local out = {}
    for i = 1, count do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        out[i] = { x = col * step, y = -row * step }
    end
    local rows = math.ceil(count / columns)
    out.width = columns * size + (columns - 1) * gap
    out.height = rows > 0 and (rows * size + (rows - 1) * gap) or 0
    return out
end
