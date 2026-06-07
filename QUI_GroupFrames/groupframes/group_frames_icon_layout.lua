local ADDON_NAME, ns = ...

local IconLayout = ns.QUI_GroupFrameIconLayout or {}
ns.QUI_GroupFrameIconLayout = IconLayout

function IconLayout.CalculateSlotOffset(index, iconSize, spacing, direction, totalCount)
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

function IconLayout.CalculateStripSize(count, iconSize, spacing, direction)
    local size = iconSize or 0
    local gap = spacing or 0
    local visible = math.max(count or 0, 0)
    if visible <= 0 then
        return 0, 0
    end

    if direction == "UP" or direction == "DOWN" then
        return size, visible * size + math.max(visible - 1, 0) * gap
    end

    return visible * size + math.max(visible - 1, 0) * gap, size
end

