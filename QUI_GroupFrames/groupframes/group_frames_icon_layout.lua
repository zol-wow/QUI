local ADDON_NAME, ns = ...

local IconLayout = ns.QUI_GroupFrameIconLayout or {}
ns.QUI_GroupFrameIconLayout = IconLayout

local AuraGlue = ns.AuraGlue or (_G.QUI and _G.QUI.AuraGlue)
IconLayout.DISPEL_DEFAULT_COLORS = AuraGlue and AuraGlue.DISPEL_DEFAULT_COLORS

function IconLayout.SeedDispelColors(tbl)
    if type(tbl) ~= "table" then return tbl end
    for k, v in pairs(IconLayout.DISPEL_DEFAULT_COLORS) do
        if type(tbl[k]) ~= "table" then
            tbl[k] = { v[1], v[2], v[3], v[4] or 1 }
        end
    end
    return tbl
end

local function SingleRowOffset(index, iconSize, spacing, direction, totalCount)
    local step = ((index or 1) - 1) * ((iconSize or 0) + (spacing or 0))
    if direction == "LEFT" then
        return -step, 0
    elseif direction == "UP" then
        return 0, step
    elseif direction == "DOWN" then
        return 0, -step
    elseif direction == "CENTER" then
        local count = totalCount or 1
        local totalSpan = count * (iconSize or 0) + math.max(count - 1, 0) * (spacing or 0)
        return step - (totalSpan / 2), 0
    end
    return step, 0
end

function IconLayout.CalculateSlotOffset(index, iconSize, spacing, direction, totalCount, perRow, rowDir)
    perRow = perRow or 0
    if perRow <= 0 then
        return SingleRowOffset(index, iconSize, spacing, direction, totalCount)
    end

    local zeroBased = (index or 1) - 1
    local major = zeroBased % perRow
    local line = math.floor(zeroBased / perRow)
    local stepUnit = (iconSize or 0) + (spacing or 0)
    local wrap = line * stepUnit

    local lineCount = perRow
    if totalCount and totalCount > 0 then
        local remaining = totalCount - line * perRow
        if remaining < perRow then lineCount = remaining end
    end

    local x, y = SingleRowOffset(major + 1, iconSize, spacing, direction, lineCount)

    if direction == "UP" or direction == "DOWN" then
        if rowDir == "LEFT" then x = x - wrap else x = x + wrap end
    else
        if rowDir == "UP" then y = y + wrap else y = y - wrap end
    end
    return x, y
end

local function ComposeAnchor(horizontal, vertical)
    if vertical == "TOP" then
        if horizontal == "LEFT" then return "TOPLEFT" end
        if horizontal == "RIGHT" then return "TOPRIGHT" end
        return "TOP"
    elseif vertical == "BOTTOM" then
        if horizontal == "LEFT" then return "BOTTOMLEFT" end
        if horizontal == "RIGHT" then return "BOTTOMRIGHT" end
        return "BOTTOM"
    end

    if horizontal == "LEFT" then return "LEFT" end
    if horizontal == "RIGHT" then return "RIGHT" end
    return "CENTER"
end

function IconLayout.GetIconAnchorForGrow(frameAnchor, direction)
    local anchor = frameAnchor or "CENTER"
    local horizontal = anchor:find("LEFT") and "LEFT"
        or anchor:find("RIGHT") and "RIGHT"
        or "CENTER"
    local vertical = anchor:find("TOP") and "TOP"
        or anchor:find("BOTTOM") and "BOTTOM"
        or "CENTER"

    if direction == "LEFT" then
        horizontal = "RIGHT"
    elseif direction == "RIGHT" or direction == "CENTER" then
        horizontal = "LEFT"
    elseif direction == "UP" then
        vertical = "BOTTOM"
    elseif direction == "DOWN" then
        vertical = "TOP"
    end

    return ComposeAnchor(horizontal, vertical)
end
