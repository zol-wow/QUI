local _, ns = ...

local CDMLayout = {}
ns.CDMLayout = CDMLayout

local ROW_GAP = 0

function CDMLayout.PointOffset(point, width, height)
    local halfW = (width or 0) * 0.5
    local halfH = (height or 0) * 0.5
    if point == "TOPLEFT" then return -halfW, halfH
    elseif point == "TOP" then return 0, halfH
    elseif point == "TOPRIGHT" then return halfW, halfH
    elseif point == "LEFT" then return -halfW, 0
    elseif point == "RIGHT" then return halfW, 0
    elseif point == "BOTTOMLEFT" then return -halfW, -halfH
    elseif point == "BOTTOM" then return 0, -halfH
    elseif point == "BOTTOMRIGHT" then return halfW, -halfH
    end
    return 0, 0
end

function CDMLayout.ComputeAnchorOffsets(centerOffsetX, centerOffsetY, point, relative, frameW, frameH, parentW, parentH)
    point = point or "CENTER"
    relative = relative or "CENTER"
    centerOffsetX = centerOffsetX or 0
    centerOffsetY = centerOffsetY or 0

    if point == "CENTER" and relative == "CENTER" then
        return centerOffsetX, centerOffsetY
    end

    local srcX, srcY = CDMLayout.PointOffset(point, frameW, frameH)
    local tgtX, tgtY = CDMLayout.PointOffset(relative, parentW, parentH)
    return centerOffsetX - tgtX + srcX, centerOffsetY - tgtY + srcY
end

function CDMLayout.GetBootstrapSize(trackerKey, currentW, currentH, state, db)
    if currentW and currentW > 1 and currentH and currentH > 1 then
        return nil, nil
    end

    local boundsW = state and (state.cdmIconWidth or 0) or 0
    local boundsH = state and (state.cdmTotalHeight or 0) or 0
    if boundsW > 1 and boundsH > 1 then
        return boundsW, boundsH
    end

    if trackerKey == "trackedBar" then
        local tbs = db and db.trackedBar
        return (tbs and tbs.barWidth) or 215, (tbs and tbs.barHeight) or 25
    end

    if trackerKey == "buff" then
        local buff = db and db.buff
        local iconSize = (buff and buff.iconSize) or 30
        local aspectRatio = (buff and buff.aspectRatioCrop) or 1.0
        local iconWidth, iconHeight = iconSize, iconSize
        if aspectRatio > 1.0 then
            iconHeight = iconSize / aspectRatio
        elseif aspectRatio < 1.0 then
            iconWidth = iconSize * aspectRatio
        end
        return iconWidth, iconHeight
    end

    return 100, 40
end

function CDMLayout.GetUtilityAnchorOffset(settings)
    local utilityTopBorder = settings and settings.row1 and settings.row1.borderSize or 0
    return ((settings and settings.anchorGap) or 0) - utilityTopBorder
end

function CDMLayout.MigrateRowAspect(rowData)
    if rowData and rowData.aspectRatioCrop == nil and rowData.shape then
        if rowData.shape == "rectangle" or rowData.shape == "flat" then
            rowData.aspectRatioCrop = 1.33
        else
            rowData.aspectRatioCrop = 1.0
        end
    end
    return rowData and (rowData.aspectRatioCrop or 1.0) or 1.0
end

function CDMLayout.GetTotalIconCapacity(settings)
    local total = 0
    if not settings then return total end
    for i = 1, 3 do
        local rowKey = "row" .. i
        local row = settings[rowKey]
        if row and row.iconCount then
            total = total + row.iconCount
        end
    end
    return total
end

function CDMLayout.AnchorLinearChain(owner, frames, opts)
    if not owner or type(frames) ~= "table" or #frames == 0 then return false end
    opts = opts or {}
    if opts.axis ~= nil and opts.axis ~= "HORIZONTAL" then return false end
    if opts.grow ~= nil and opts.grow ~= "RIGHT" then return false end

    local spacing = opts.spacing or 0
    local offsetY = opts.offsetY or 0
    local previous
    for i = 1, #frames do
        local frame = frames[i]
        if not (frame and frame.ClearAllPoints and frame.SetPoint) then return false end
        frame:ClearAllPoints()
        if previous then
            frame:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
        else
            frame:SetPoint("LEFT", owner, "LEFT", opts.offsetX or 0, offsetY)
        end
        previous = frame
    end
    return true
end

function CDMLayout.BuildRows(settings)
    local rows = {}
    if not settings then return rows end

    for i = 1, 3 do
        local rowKey = "row" .. i
        local row = settings[rowKey]
        if row and row.iconCount and row.iconCount > 0 then
            CDMLayout.MigrateRowAspect(row)
            rows[#rows + 1] = {
                rowNum = i,
                count = row.iconCount,
                size = row.iconSize or 50,
                borderSize = row.borderSize or 2,
                borderColorSource = row.borderColorSource,
                borderColor = row.borderColor or row.borderColorTable or {0, 0, 0, 1},
                aspectRatioCrop = row.aspectRatioCrop or 1.0,
                zoom = row.zoom or 0,
                padding = row.padding or 0,
                yOffset = row.yOffset or 0,
                xOffset = row.xOffset or 0,
                durationSize = row.durationSize or 14,
                durationOffsetX = row.durationOffsetX or 0,
                durationOffsetY = row.durationOffsetY or 0,
                durationTextColor = row.durationTextColor or {1, 1, 1, 1},
                durationAnchor = row.durationAnchor or "CENTER",
                durationFont = row.durationFont,
                hideDurationText = row.hideDurationText,
                stackSize = row.stackSize or 14,
                stackOffsetX = row.stackOffsetX or 0,
                stackOffsetY = row.stackOffsetY or 0,
                stackTextColor = row.stackTextColor or {1, 1, 1, 1},
                stackAnchor = row.stackAnchor or "BOTTOMRIGHT",
                stackFont = row.stackFont,
                hideStackText = row.hideStackText,
                opacity = row.opacity or 1.0,
                growDirection = row.growDirection,
            }
        end
    end

    return rows
end

function CDMLayout.SortIconsByAssignedRow(icons, rows)
    if not icons or not rows or #rows <= 1 then return icons end

    local buckets = {}
    local rowCounts = {}
    for _, rowConfig in ipairs(rows) do
        local rn = rowConfig.rowNum
        buckets[rn] = {}
        rowCounts[rn] = 0
    end

    local function findRowWithRoom(preferredRow)
        local startIndex = 1
        if preferredRow and buckets[preferredRow] then
            for i, rowConfig in ipairs(rows) do
                if rowConfig.rowNum == preferredRow then
                    local rn = rowConfig.rowNum
                    if rowCounts[rn] < rowConfig.count then
                        return rn
                    end
                    startIndex = i + 1
                    break
                end
            end
        end

        for i = startIndex, #rows do
            local rowConfig = rows[i]
            local rn = rowConfig.rowNum
            if rowCounts[rn] < rowConfig.count then
                return rn
            end
        end
        return nil
    end

    local overflow = {}
    for _, icon in ipairs(icons) do
        local ar = (icon._spellEntry and icon._spellEntry._assignedRow) or icon._assignedRow
        local rn = findRowWithRoom(ar)
        if rn then
            buckets[rn][#buckets[rn] + 1] = icon
            rowCounts[rn] = rowCounts[rn] + 1
        else
            overflow[#overflow + 1] = icon
        end
    end

    local sorted = {}
    for _, rowConfig in ipairs(rows) do
        local rn = rowConfig.rowNum
        local rowStart = #sorted + 1
        for _, icon in ipairs(buckets[rn]) do
            sorted[#sorted + 1] = icon
        end

        rowConfig._actualCount = #sorted - rowStart + 1
    end

    for _, icon in ipairs(overflow) do
        sorted[#sorted + 1] = icon
    end

    return sorted
end

function CDMLayout.ApplyCustomBarGrowthOrder(icons, settings)
    if not icons or not settings or settings.containerType ~= "customBar" then
        return icons
    end

    local gd = settings.growDirection
    if gd ~= "LEFT" and gd ~= "UP" then
        return icons
    end

    local reversed = {}
    for i = #icons, 1, -1 do
        reversed[#reversed + 1] = icons[i]
    end
    return reversed
end

function CDMLayout.BuildIconLayout(settings, icons, opts)
    opts = opts or {}
    local rows = CDMLayout.BuildRows(settings)
    if #rows == 0 or not icons or #icons == 0 then
        return nil
    end

    icons = CDMLayout.SortIconsByAssignedRow(icons, rows)
    icons = CDMLayout.ApplyCustomBarGrowthOrder(icons, settings)

    local layoutDirection = (settings and settings.layoutDirection) or "HORIZONTAL"
    local isVertical = (layoutDirection == "VERTICAL")
    local growReverse = settings and settings.growthDirection == "UP"
    local growUp = not isVertical and growReverse
    local growLeft = isVertical and growReverse
    local rowGap = (rows[1] and rows[1].padding) or ROW_GAP

    local potentialRow1Width = 0
    local potentialBottomRowWidth = 0
    if rows[1] then
        potentialRow1Width = (rows[1].count * rows[1].size) + ((rows[1].count - 1) * (rows[1].padding or 0))
    end
    if rows[#rows] then
        potentialBottomRowWidth = (rows[#rows].count * rows[#rows].size) + ((rows[#rows].count - 1) * (rows[#rows].padding or 0))
    end

    local maxRowWidth = 0
    local maxColHeight = 0
    local rowWidths = {}
    local tempIndex = 1

    for rowNum, rowConfig in ipairs(rows) do
        local rowCount = rowConfig._actualCount or rowConfig.count
        local iconsInRow = math.min(rowCount, #icons - tempIndex + 1)
        if iconsInRow > 0 then
            local iconWidth = rowConfig.size
            local aspectRatio = rowConfig.aspectRatioCrop or 1.0
            local iconHeight = rowConfig.size / aspectRatio

            if isVertical then
                local colHeight = (iconsInRow * iconHeight) + ((iconsInRow - 1) * rowConfig.padding)
                rowWidths[rowNum] = iconWidth
                if colHeight > maxColHeight then maxColHeight = colHeight end
            else
                local rowWidth = (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)
                rowWidths[rowNum] = rowWidth
                if rowWidth > maxRowWidth then maxRowWidth = rowWidth end
            end
            tempIndex = tempIndex + iconsInRow
        end
    end

    local totalHeight = 0
    local totalWidth = 0
    local numRowsUsed = 0
    local tempIdx = 1

    for rowNum, rowConfig in ipairs(rows) do
        local rowCount = rowConfig._actualCount or rowConfig.count
        local iconsInRow = math.min(rowCount, #icons - tempIdx + 1)
        if iconsInRow > 0 then
            local aspectRatio = rowConfig.aspectRatioCrop or 1.0
            local iconHeight = rowConfig.size / aspectRatio
            local iconWidth = rowConfig.size
            numRowsUsed = numRowsUsed + 1

            if isVertical then
                totalWidth = totalWidth + iconWidth
                if numRowsUsed > 1 then totalWidth = totalWidth + rowGap end
            else
                totalHeight = totalHeight + iconHeight
                if numRowsUsed > 1 then totalHeight = totalHeight + rowGap end
            end
            tempIdx = tempIdx + iconsInRow
        end
    end

    if isVertical then
        totalHeight = maxColHeight
        maxRowWidth = totalWidth
    end

    local baseTotalHeight = totalHeight
    local proxyTotalHeight = totalHeight
    local proxyYOffset = 0
    if not isVertical and numRowsUsed > 0 then
        local pos = growUp and (-baseTotalHeight / 2) or (baseTotalHeight / 2)
        local actualTop = growUp and (baseTotalHeight / 2) or pos
        local actualBot = growUp and pos or (-baseTotalHeight / 2)
        local tmpIdx = 1
        for _, rc in ipairs(rows) do
            local n = math.min(rc._actualCount or rc.count, #icons - tmpIdx + 1)
            if n > 0 then
                local ih = rc.size / (rc.aspectRatioCrop or 1.0)
                local yOff = rc.yOffset or 0
                if growUp then
                    actualBot = math.min(actualBot, pos + yOff)
                    actualTop = math.max(actualTop, pos + ih + yOff)
                    pos = pos + ih + rowGap
                else
                    actualTop = math.max(actualTop, pos + yOff)
                    actualBot = math.min(actualBot, pos - ih + yOff)
                    pos = pos - ih - rowGap
                end
                tmpIdx = tmpIdx + n
            end
        end
        proxyTotalHeight = actualTop - actualBot
        proxyYOffset = (actualTop + actualBot) / 2
    end

    local rawContentWidth = maxRowWidth
    local applyHUDMinWidth = opts.applyHUDMinWidth and true or false
    local minWidth = opts.minWidth or 0
    if applyHUDMinWidth then
        maxRowWidth = math.max(maxRowWidth, minWidth)
        potentialRow1Width = math.max(potentialRow1Width, minWidth)
        potentialBottomRowWidth = math.max(potentialBottomRowWidth, minWidth)
    end

    local placements = {}
    local iconIndex = 1
    local currentY = growUp and (-baseTotalHeight / 2) or (baseTotalHeight / 2)
    local currentX = growLeft and (totalWidth / 2) or (-totalWidth / 2)

    for rowNum, rowConfig in ipairs(rows) do
        local rowIcons = {}
        local iconsInRow = 0

        for _ = 1, (rowConfig._actualCount or rowConfig.count) do
            if iconIndex <= #icons then
                rowIcons[#rowIcons + 1] = icons[iconIndex]
                iconIndex = iconIndex + 1
                iconsInRow = iconsInRow + 1
            end
        end

        if iconsInRow > 0 then
            local aspectRatio = rowConfig.aspectRatioCrop or 1.0
            local iconWidth = rowConfig.size
            local iconHeight = rowConfig.size / aspectRatio
            local rowWidth = rowWidths[rowNum] or (iconsInRow * iconWidth) + ((iconsInRow - 1) * rowConfig.padding)

            for i, icon in ipairs(rowIcons) do
                local x, y
                if isVertical then
                    local colCenterX = growLeft and (currentX - iconWidth / 2) or (currentX + iconWidth / 2)
                    local colStartY = baseTotalHeight / 2 - iconHeight / 2
                    y = colStartY - ((i - 1) * (iconHeight + rowConfig.padding)) + rowConfig.yOffset
                    x = colCenterX + (rowConfig.xOffset or 0)
                else
                    local rowCenterY
                    if growUp then
                        rowCenterY = currentY + (iconHeight / 2) + rowConfig.yOffset
                    else
                        rowCenterY = currentY - (iconHeight / 2) + rowConfig.yOffset
                    end
                    local rowGrow = rowConfig.growDirection
                    local rowStartX
                    if rowGrow == "RIGHT" then
                        rowStartX = -maxRowWidth / 2 + iconWidth / 2
                    elseif rowGrow == "LEFT" then
                        rowStartX = maxRowWidth / 2 - rowWidth + iconWidth / 2
                    else
                        rowStartX = -rowWidth / 2 + iconWidth / 2
                    end
                    x = rowStartX + ((i - 1) * (iconWidth + rowConfig.padding)) + (rowConfig.xOffset or 0)
                    y = rowCenterY
                end

                placements[#placements + 1] = {
                    icon = icon,
                    rowConfig = rowConfig,
                    x = x,
                    y = y,
                }
            end

            if isVertical then
                if growLeft then
                    currentX = currentX - iconWidth - rowGap
                else
                    currentX = currentX + iconWidth + rowGap
                end
            else
                if growUp then
                    currentY = currentY + iconHeight + rowGap
                else
                    currentY = currentY - iconHeight - rowGap
                end
            end
        end
    end

    local visualTopRow = growUp and rows[#rows] or rows[1]
    local visualBottomRow = growUp and rows[1] or rows[#rows]
    local metrics = {
        iconWidth = maxRowWidth,
        rawContentWidth = rawContentWidth,
        totalHeight = proxyTotalHeight,
        proxyYOffset = proxyYOffset,
        row1IconHeight = visualTopRow and (visualTopRow.size / (visualTopRow.aspectRatioCrop or 1.0)) or 0,
        row1BorderSize = visualTopRow and visualTopRow.borderSize or 0,
        bottomRowBorderSize = visualBottomRow and visualBottomRow.borderSize or 0,
        bottomRowYOffset = visualBottomRow and visualBottomRow.yOffset or 0,
    }

    if isVertical then
        metrics.row1Width = maxRowWidth
        metrics.bottomRowWidth = maxRowWidth
        metrics.rawRow1Width = rawContentWidth
        metrics.rawBottomRowWidth = rawContentWidth
        metrics.potentialRow1Width = maxRowWidth
        metrics.potentialBottomRowWidth = maxRowWidth
    else
        local visualTopRowWidth = growUp and (rowWidths[#rows] or rawContentWidth) or (rowWidths[1] or rawContentWidth)
        local visualBottomRowWidth = growUp and (rowWidths[1] or rawContentWidth) or (rowWidths[#rows] or rawContentWidth)
        local row1Width = visualTopRowWidth
        local bottomRowWidth = visualBottomRowWidth
        if applyHUDMinWidth then
            row1Width = math.max(row1Width, minWidth)
            bottomRowWidth = math.max(bottomRowWidth, minWidth)
        end
        metrics.row1Width = row1Width
        metrics.bottomRowWidth = bottomRowWidth
        metrics.rawRow1Width = visualTopRowWidth
        metrics.rawBottomRowWidth = visualBottomRowWidth
        metrics.potentialRow1Width = growUp and potentialBottomRowWidth or potentialRow1Width
        metrics.potentialBottomRowWidth = growUp and potentialRow1Width or potentialBottomRowWidth
    end

    return {
        rows = rows,
        icons = icons,
        placements = placements,
        metrics = metrics,
    }
end

function CDMLayout.BuildBuffGridLayout(settings, icons, _opts)
    if not icons or #icons == 0 then return nil end
    settings = settings or {}

    local iconSize = settings.iconSize or 42
    local padding = settings.padding or 0
    local aspectRatio = settings.aspectRatioCrop or 1.0
    local growthDirection = settings.growthDirection or "CENTERED_HORIZONTAL"
    local isVertical = (growthDirection == "UP" or growthDirection == "DOWN")

    local iconWidth, iconHeight = iconSize, iconSize
    if aspectRatio > 1.0 then
        iconHeight = iconSize / aspectRatio
    elseif aspectRatio < 1.0 then
        iconWidth = iconSize * aspectRatio
    end

    local rowConfig = {
        rowNum = 1,
        count = #icons,
        size = iconSize,
        borderSize = settings.borderSize or 2,
        borderColorSource = settings.borderColorSource,
        borderColor = settings.borderColor or settings.borderColorTable or {0, 0, 0, 1},
        aspectRatioCrop = aspectRatio,
        zoom = settings.zoom or 0,
        padding = padding,
        yOffset = 0,
        xOffset = 0,
        durationSize = settings.durationSize or 14,
        durationOffsetX = settings.durationOffsetX or 0,
        durationOffsetY = settings.durationOffsetY or 8,
        durationTextColor = settings.durationTextColor or {1, 1, 1, 1},
        durationAnchor = settings.durationAnchor or "TOP",
        durationFont = settings.durationFont,
        hideDurationText = settings.hideDurationText,
        stackSize = settings.stackSize or 14,
        stackOffsetX = settings.stackOffsetX or 0,
        stackOffsetY = settings.stackOffsetY or -8,
        stackTextColor = settings.stackTextColor or {1, 1, 1, 1},
        stackAnchor = settings.stackAnchor or "BOTTOM",
        stackFont = settings.stackFont,
        hideStackText = settings.hideStackText,
        opacity = settings.opacity or 1.0,
    }

    local n = #icons
    local placements = {}
    local totalWidth, totalHeight

    if isVertical then
        totalWidth = iconWidth
        totalHeight = (n * iconHeight) + ((n - 1) * padding)
        local startY
        if growthDirection == "UP" then
            startY = -(totalHeight / 2) + iconHeight / 2
        else
            startY = (totalHeight / 2) - iconHeight / 2
        end
        for i = 1, n do
            local y = (growthDirection == "UP")
                and (startY + (i - 1) * (iconHeight + padding))
                or (startY - (i - 1) * (iconHeight + padding))
            placements[i] = { icon = icons[i], rowConfig = rowConfig, x = 0, y = y }
        end
    else
        totalWidth = (n * iconWidth) + ((n - 1) * padding)
        totalHeight = iconHeight
        local startX = -totalWidth / 2 + iconWidth / 2
        for i = 1, n do
            local x = startX + (i - 1) * (iconWidth + padding)
            placements[i] = { icon = icons[i], rowConfig = rowConfig, x = x, y = 0 }
        end
    end

    return {
        rows = { rowConfig },
        icons = icons,
        placements = placements,
        metrics = {
            iconWidth = totalWidth,
            rawContentWidth = totalWidth,
            totalHeight = totalHeight,
            proxyYOffset = 0,
            row1IconHeight = iconHeight,
            row1BorderSize = rowConfig.borderSize,
            bottomRowBorderSize = rowConfig.borderSize,
            bottomRowYOffset = 0,
            row1Width = totalWidth,
            bottomRowWidth = totalWidth,
            rawRow1Width = totalWidth,
            rawBottomRowWidth = totalWidth,
            potentialRow1Width = totalWidth,
            potentialBottomRowWidth = totalWidth,
        },
    }
end

function CDMLayout.BuildBuffBarLayout(settings, icons, _opts)
    if not icons or #icons == 0 then return nil end
    settings = settings or {}

    local barWidth = settings.barWidth or 215
    local barHeight = settings.barHeight or 25
    local spacing = settings.spacing or 2
    local isVertical = (settings.orientation == "vertical")
    local growUp = (settings.growUp ~= false)

    local barW, barH = barWidth, barHeight
    if isVertical then barW, barH = barHeight, barWidth end

    local n = #icons
    local rowConfig = {
        rowNum = 1,
        count = n,
        size = barW,
        aspectRatioCrop = 1,
        borderSize = settings.borderSize or 0,
        borderColorSource = settings.borderColorSource,
        borderColor = settings.borderColor or settings.borderColorTable or {0, 0, 0, 1},
        zoom = 0,
        padding = spacing,
        yOffset = 0,
        xOffset = 0,
        durationSize = settings.durationSize or 12,
        durationTextColor = settings.durationTextColor or {1, 1, 1, 1},
        stackSize = settings.stackSize or 12,
        stackTextColor = settings.stackTextColor or {1, 1, 1, 1},
        opacity = settings.opacity or 1.0,
    }

    local placements = {}
    local totalW, totalH
    if isVertical then
        totalW = (n * barW) + ((n - 1) * spacing)
        totalH = barH
        local startX = -totalW / 2 + barW / 2
        for i = 1, n do
            placements[i] = { icon = icons[i], rowConfig = rowConfig, w = barW, h = barH,
                x = startX + (i - 1) * (barW + spacing), y = 0 }
        end
    else
        totalW = barW
        totalH = (n * barH) + ((n - 1) * spacing)
        local startY = growUp and (-(totalH / 2) + barH / 2) or ((totalH / 2) - barH / 2)
        for i = 1, n do
            local y = growUp and (startY + (i - 1) * (barH + spacing))
                or (startY - (i - 1) * (barH + spacing))
            placements[i] = { icon = icons[i], rowConfig = rowConfig, w = barW, h = barH, x = 0, y = y }
        end
    end

    return {
        rows = { rowConfig },
        icons = icons,
        placements = placements,
        metrics = {
            iconWidth = totalW,
            rawContentWidth = totalW,
            totalHeight = totalH,
            proxyYOffset = 0,
            row1IconHeight = barH,
            row1BorderSize = rowConfig.borderSize,
            bottomRowBorderSize = rowConfig.borderSize,
            bottomRowYOffset = 0,
            row1Width = totalW,
            bottomRowWidth = totalW,
            rawRow1Width = totalW,
            rawBottomRowWidth = totalW,
            potentialRow1Width = totalW,
            potentialBottomRowWidth = totalW,
        },
    }
end
