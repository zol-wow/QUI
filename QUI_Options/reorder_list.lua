local ADDON_NAME, ns = ...

local ReorderList = {}
ns.QUI_ReorderList = ReorderList

local ROW_HEIGHT   = 26
local ROW_INSET    = 4
local LIST_TOP     = 24
local DETAIL_INSET = 16
local PILL_WIDTH   = 26
local PILL_GAP     = 8

local function GetAccent()
    if ns.UIKit and ns.UIKit.GetAccentColor then
        local r, g, b = ns.UIKit.GetAccentColor()
        if r then return r, g, b end
    end
    return 0.19, 0.51, 0.98
end

function ReorderList.Build(parent, y, spec)
    local items = spec.items
    local accR, accG, accB = GetAccent()

    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    listFrame:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local hintFs = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintFs:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 4, -4)
    hintFs:SetPoint("RIGHT", listFrame, "RIGHT", -4, 0)
    hintFs:SetJustifyH("LEFT")
    hintFs:SetTextColor(1, 1, 1, 0.48)
    hintFs:SetText(#items > 0 and (spec.hintText or "") or (spec.emptyText or ""))

    local extents = {}
    local dropLine = listFrame:CreateTexture(nil, "OVERLAY")
    dropLine:SetHeight(2)
    dropLine:SetColorTexture(accR, accG, accB, 0.9)
    if ns.UIKit and ns.UIKit.DisablePixelSnap then
        ns.UIKit.DisablePixelSnap(dropLine)
    end
    dropLine:Hide()

    local function DropGapFromCursor()
        local top = listFrame:GetTop()
        if not top or #extents == 0 then return 1 end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / listFrame:GetEffectiveScale()
        local offset = top - cursorY
        for i = 1, #extents do
            local e = extents[i]
            if offset < (e.top + e.bottom) * 0.5 then return i end
        end
        return #extents + 1
    end

    local function GapOffset(gap)
        if #extents == 0 then return LIST_TOP end
        if gap > #extents then return extents[#extents].bottom end
        return extents[gap].top
    end

    local rowHeight = spec.rowHeight or ROW_HEIGHT
    local listTop = spec.hideHint and 4 or LIST_TOP
    if spec.hideHint then hintFs:Hide() end
    listFrame._quiDropGap = DropGapFromCursor
    listFrame._quiDropLine = dropLine
    listFrame._quiGapOffset = GapOffset
    if spec.dragGroup then spec.dragGroup[#spec.dragGroup + 1] = listFrame end
    listFrame._quiDropSpec = spec
    local function DropTarget()
        for _, target in ipairs(spec.dragGroup or {}) do
            if (target._quiDropSpec.dropOwner or target):IsMouseOver() then return target end
        end
        return listFrame
    end
    local ry = listTop
    for idx = 1, #items do
        local item = items[idx]
        local capturedKey = spec.identify(item)
        local rowTop = ry

        local r = CreateFrame("Frame", nil, listFrame)
        r:SetHeight(rowHeight - ROW_INSET)
        r:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -ry)
        if spec.rowWidth then
            local function ResizeRow()
                r:SetWidth(math.min(spec.rowWidth, math.max(1, listFrame:GetWidth())))
            end
            listFrame:HookScript("OnSizeChanged", ResizeRow)
            ResizeRow()
        else
            r:SetPoint("RIGHT", listFrame, "RIGHT", 0, 0)
        end

        if spec.cards and ns.UIKit then
            ns.UIKit.CreateRoundedSurface(r, {radius = 5,
                bgColor = {1, 1, 1, 0.035}, borderColor = {1, 1, 1, 0.08}})
        end
        local hoverBg = r:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(accR, accG, accB, 0.08)
        hoverBg:Hide()

        local function findCurrentIndex()
            for i = 1, #items do
                if spec.identify(items[i]) == capturedKey then return i end
            end
            return nil
        end

        local function makeRowButton(text, xOff, tip)
            local btn = CreateFrame("Button", nil, r)
            btn:SetSize(16, 16)
            btn:SetPoint("RIGHT", r, "RIGHT", xOff, 0)
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:SetText(text)
            btn:GetFontString():SetTextColor(accR, accG, accB, 1)
            btn:SetScript("OnEnter", function(self)
                hoverBg:Show()
                QUI.GUI.Tooltip:Show(self, tip, { anchor = "TOP" })
            end)
            btn:SetScript("OnLeave", function(self)
                QUI.GUI.Tooltip:Hide(false, self)
                if not r:IsMouseOver() then hoverBg:Hide() end
            end)
            if spec.onControl then spec.onControl(btn) end
            return btn
        end

        local canExpand = spec.buildDetail ~= nil
        if canExpand and spec.hasDetail then
            canExpand = spec.hasDetail(item, idx) and true or false
        end
        local isExpanded = canExpand and spec.expanded and spec.expanded[capturedKey] or false

        local function ToggleExpanded()
            if not (canExpand and spec.expanded) then return end
            spec.expanded[capturedKey] = (not isExpanded) or nil
            spec.onChange()
        end

        local labelLeft = 4
        if spec.cards then
            local handle = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            handle:SetPoint("LEFT", r, "LEFT", 7, 0)
            handle:SetText("::")
            handle:SetTextColor(1, 1, 1, 0.45)
            labelLeft = 24
        end
        if spec.buildDetail ~= nil then
            labelLeft = 20
            if canExpand then
                local chevron = CreateFrame("Button", nil, r)
                chevron:SetSize(14, 14)
                chevron:SetPoint("LEFT", r, "LEFT", 3, 0)
                chevron:SetNormalFontObject("GameFontNormalSmall")
                chevron:SetText(isExpanded and "v" or ">")
                chevron:GetFontString():SetTextColor(accR, accG, accB, 1)
                chevron:SetScript("OnClick", ToggleExpanded)
                chevron:SetScript("OnEnter", function() hoverBg:Show() end)
                chevron:SetScript("OnLeave", function()
                    if not r:IsMouseOver() then hoverBg:Hide() end
                end)
                if spec.onControl then spec.onControl(chevron) end
            end
        end

        local nameFs
        local function RefreshLabel()
            local text, dimmed = spec.getLabel(item, idx)
            nameFs:SetText(text)
            if dimmed then
                nameFs:SetTextColor(1, 1, 1, 0.6)
            else
                nameFs:SetTextColor(1, 1, 1, 0.9)
            end
        end

        if spec.getToggleBinding then
            local bindTable, bindKey, bindDescription
            if spec.GUI then
                bindTable, bindKey, bindDescription = spec.getToggleBinding(item, idx)
            end
            if bindTable and bindKey then
                local pill = spec.GUI:CreateFormToggle(r, nil, bindKey, bindTable, function()
                    if spec.onToggle then
                        local curIdx = findCurrentIndex()
                        spec.onToggle(item, curIdx or idx)
                    end
                    RefreshLabel()
                end, bindDescription and { description = bindDescription } or nil)
                pill:ClearAllPoints()
                pill:SetPoint("LEFT", r, "LEFT", labelLeft, 0)
                if spec.onControl then spec.onControl(pill) end
            end
            labelLeft = labelLeft + PILL_WIDTH + PILL_GAP
        end

        nameFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("LEFT", r, "LEFT", labelLeft, 0)
        nameFs:SetPoint("RIGHT", r, "RIGHT", spec.actionsInToolbar and -8 or -70, 0)
        nameFs:SetWordWrap(false)
        if spec.selected == capturedKey then hoverBg:Show() end
        nameFs:SetJustifyH("LEFT")
        RefreshLabel()

        local dragged = false
        r:EnableMouse(true)
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then dragged = false end
        end)
        r:SetScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" then return end
            if dragged then
                dragged = false
                return
            end
            if spec.onSelect then spec.onSelect(item, findCurrentIndex()) end
            ToggleExpanded()
        end)
        r:SetScript("OnEnter", function(self)
            hoverBg:Show()
            if spec.getTooltip then
                QUI.GUI.Tooltip:Show(self, function(tip)
                    local title, body = spec.getTooltip(item, idx)
                    if not title then return end
                    tip:AddTitle(title)
                    if body then tip:AddLine(body) end
                end, { anchor = "TOP" })
            end
        end)
        r:SetScript("OnLeave", function(self)
            QUI.GUI.Tooltip:Hide(false, self)
            if not self:IsMouseOver() and spec.selected ~= capturedKey then hoverBg:Hide() end
        end)
        r:SetScript("OnDragStart", function(self)
            QUI.GUI.Tooltip:Hide(true)
            dragged = true
            self:SetAlpha(0.4)
            dropLine:Show()
            self:SetScript("OnUpdate", function()
                local target = DropTarget()
                for _, other in ipairs(spec.dragGroup or {listFrame}) do other._quiDropLine:Hide() end
                local line = target._quiDropLine
                line:Show()
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", target, "TOPLEFT", 0, -target._quiGapOffset(target._quiDropGap()) + 1)
                line:SetPoint("RIGHT", target, "RIGHT", -4, 0)
            end)
        end)
        r:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            dropLine:Hide()
            for _, other in ipairs(spec.dragGroup or {}) do other._quiDropLine:Hide() end
            local destination = DropTarget()
            if spec.onDrop then
                spec.onDrop(item, destination._quiDropSpec, destination._quiDropGap())
                return
            end
            local gap = DropGapFromCursor()
            local curIdx = findCurrentIndex()
            if not curIdx then return end
            local target = (gap > curIdx) and (gap - 1) or gap
            if target ~= curIdx then
                table.remove(items, curIdx)
                table.insert(items, target, item)
                spec.onChange()
            end
        end)

        if not spec.actionsInToolbar then
        local removable = spec.onRemove ~= nil
            and (spec.canRemove == nil or spec.canRemove(item))
        local removeOffset = -4
        if removable then
            local removeBtn = makeRowButton("x", -4, spec.removeTooltip or "")
            removeBtn:SetScript("OnClick", function()
                local curIdx = findCurrentIndex()
                if curIdx then spec.onRemove(items[curIdx], curIdx) end
            end)
        else
            removeOffset = 16
        end

        local upBtn = makeRowButton("^", removeOffset - 40, spec.moveUpTooltip or "")
        upBtn:SetScript("OnClick", function()
            local curIdx = findCurrentIndex()
            if curIdx and curIdx > 1 then
                table.remove(items, curIdx)
                table.insert(items, curIdx - 1, item)
                spec.onChange()
            end
        end)
        upBtn:SetAlpha(idx > 1 and 1 or 0.3)

        local downBtn = makeRowButton("v", removeOffset - 20, spec.moveDownTooltip or "")
        downBtn:SetScript("OnClick", function()
            local curIdx = findCurrentIndex()
            if curIdx and curIdx < #items then
                table.remove(items, curIdx)
                table.insert(items, curIdx + 1, item)
                spec.onChange()
            end
        end)
        downBtn:SetAlpha(idx < #items and 1 or 0.3)

        end
        ry = ry + rowHeight

        if isExpanded then
            local detail = CreateFrame("Frame", nil, listFrame)
            detail:SetPoint("TOPLEFT", listFrame, "TOPLEFT", DETAIL_INSET, -ry)
            detail:SetPoint("RIGHT", listFrame, "RIGHT", -4, 0)
            local detailHeight = spec.buildDetail(detail, item, idx) or 0
            detail:SetHeight(math.max(detailHeight, 1))
            ry = ry + detailHeight + ROW_INSET
        end

        extents[idx] = { top = rowTop, bottom = ry }
    end

    local height = math.max(ry, spec.hideHint and 44 or LIST_TOP)
    listFrame:SetHeight(height)
    return listFrame, height
end
