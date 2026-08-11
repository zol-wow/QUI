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
    hintFs:SetTextColor(0.6, 0.6, 0.6, 0.8)
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

    local ry = LIST_TOP
    for idx = 1, #items do
        local item = items[idx]
        local capturedKey = spec.identify(item)
        local rowTop = ry

        local r = CreateFrame("Frame", nil, listFrame)
        r:SetHeight(ROW_HEIGHT - ROW_INSET)
        r:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -ry)
        r:SetPoint("RIGHT", listFrame, "RIGHT", 0, 0)

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
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tip, 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
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
                nameFs:SetTextColor(0.6, 0.6, 0.6, 1)
            else
                nameFs:SetTextColor(0.9, 0.9, 0.9, 1)
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
        nameFs:SetPoint("RIGHT", r, "RIGHT", -70, 0)
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
            ToggleExpanded()
        end)
        r:SetScript("OnEnter", function(self)
            hoverBg:Show()
            if spec.getTooltip then
                local title, body = spec.getTooltip(item, idx)
                if title then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(title, accR, accG, accB)
                    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
                    GameTooltip:Show()
                end
            end
        end)
        r:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if not self:IsMouseOver() then hoverBg:Hide() end
        end)
        r:SetScript("OnDragStart", function(self)
            GameTooltip:Hide()
            dragged = true
            self:SetAlpha(0.4)
            dropLine:Show()
            self:SetScript("OnUpdate", function()
                dropLine:ClearAllPoints()
                dropLine:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -GapOffset(DropGapFromCursor()) + 1)
                dropLine:SetPoint("RIGHT", listFrame, "RIGHT", -4, 0)
            end)
        end)
        r:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            dropLine:Hide()
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

        ry = ry + ROW_HEIGHT

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

    local height = math.max(ry, LIST_TOP)
    listFrame:SetHeight(height)
    return listFrame, height
end
