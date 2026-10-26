local _, ns = ...

local Shared = ns.QUI_SettingsLayoutShared or {}
ns.QUI_SettingsLayoutShared = Shared

function Shared.RefreshContentExtent(frame, parent, delta)
    if delta == 0 then
        if parent._quiMeasureSettingsHeight then parent:SetHeight(parent._quiMeasureSettingsHeight()) end
        return
    end
    if not parent.GetChildren or not frame.GetPoint then return end
    local _, _, _, _, cardY = frame:GetPoint(1)
    if type(cardY) ~= "number" then return end
    local siblings = {parent:GetChildren()}
    for i = 1, (parent.GetNumRegions and parent:GetNumRegions() or 0) do
        siblings[#siblings + 1] = select(i, parent:GetRegions())
    end
    for _, sibling in ipairs(siblings) do
        if sibling ~= frame and sibling.GetNumPoints then
            for i = 1, sibling:GetNumPoints() do
                local point, relative, relativePoint, x, y = sibling:GetPoint(i)
                if relative == parent and point:find("TOP", 1, true)
                    and relativePoint:find("TOP", 1, true) and y < cardY then
                    sibling:SetPoint(point, relative, relativePoint, x, y - delta)
                end
            end
        end
    end
    parent:SetHeight(parent._quiMeasureSettingsHeight and parent._quiMeasureSettingsHeight()
        or math.max(1, parent:GetHeight() + delta))
    local section = parent._logicalSection
    if section and section.SetExpanded and section:GetParent() then
        section._contentHeight = parent:GetHeight()
        parent._contentHeight = parent:GetHeight()
        section:SetExpanded(true)
    end
end

-- Custom containers participate in the same flow as settings cards.
function Shared.WatchContentHeight(frame, parent)
    local previous = frame:GetHeight()
    frame:HookScript("OnSizeChanged", function(self, _, height)
        if self:GetParent() ~= parent then return end
        height = height or self:GetHeight()
        local delta = height - previous
        previous = height
        Shared.RefreshContentExtent(self, parent, delta)
    end)
end

-- Measure text documents from their final anchored content instead of adding
-- resize deltas to a native height that may still describe the previous frame.
function Shared.BindContentBottom(content, last, padding)
    content._quiMeasureSettingsHeight = function()
        local _, _, _, _, y = last:GetPoint(1)
        return math.max(1, -(y or 0) + last:GetHeight() + (padding or 10))
    end
    content:SetHeight(content._quiMeasureSettingsHeight())
end

-- Pooled text and page documents share width-aware measurement. Clear a
-- previous explicit height before asking the font string to wrap again.
function Shared.MeasureWrappedLabel(label, width)
    label:SetWidth(math.max(1, width))
    label:SetHeight(0)
    local height = math.max(1, math.ceil(label:GetStringHeight() or 14) + 1)
    label:SetHeight(height)
    return height
end

-- Text-only pages use the same sibling/extent updates as responsive cards.
function Shared.BindWrappedLabel(label, parent, rightInset)
    local previous, previousWidth, updating
    local function Layout(_, suppliedWidth)
        if updating then return end
        updating = true
        local _, _, _, x = label:GetPoint(1)
        local width = suppliedWidth or parent:GetWidth()
        if width == previousWidth then updating = nil; return end
        previousWidth = width
        local height = Shared.MeasureWrappedLabel(label,
            width and width > 0 and width - (x or 0) - (rightInset or 15) or label:GetWidth())
        local delta = previous and height - previous or 0
        previous = height
        if delta ~= 0 then Shared.RefreshContentExtent(label, parent, delta) end
        updating = nil
    end
    local queued
    local function QueueLayout()
        if queued then return end
        if C_Timer and C_Timer.After then
            queued = true
            C_Timer.After(0, function()
                queued = nil
                Layout()
            end)
        else
            Layout()
        end
    end
    Layout()
    parent:HookScript("OnSizeChanged", QueueLayout)
    QueueLayout()
end

function Shared.BuildNinePointAnchorOptions()
    local L = ns.L
    return {
        { value = "TOPLEFT", text = L["Top Left"] },
        { value = "TOP", text = L["Top"] },
        { value = "TOPRIGHT", text = L["Top Right"] },
        { value = "LEFT", text = L["Left"] },
        { value = "CENTER", text = L["Center"] },
        { value = "RIGHT", text = L["Right"] },
        { value = "BOTTOMLEFT", text = L["Bottom Left"] },
        { value = "BOTTOM", text = L["Bottom"] },
        { value = "BOTTOMRIGHT", text = L["Bottom Right"] },
    }
end

function Shared.FitsThreeColumns(label, widget, width)
    if not label or not widget or width < 560 then return false end
    local controlWidth = widget:GetWidth()
    if controlWidth > 100 then return false end
    local pin = widget._quiPinButton
    local pinWidth = pin and pin:IsShown() and (pin:GetWidth() + 4) or 0
    local labelWidth = label.GetStringWidth and label:GetStringWidth() or 118
    return math.max(110, labelWidth) + controlWidth + pinWidth + 16 <= (width - 64) / 3
end

-- Both explicit cards and discovered legacy controls use the same packing and
-- geometry. Callers supply logical groups and presentation insets, not columns.
function Shared.PlanSettingsRows(groups, width, compact, maxColumns)
    local plans, pending = {}, {}
    local paired = width >= 560
    local function Flush()
        local first = 1
        while first <= #pending do
            local columns = 2
            if maxColumns ~= 2 and pending[first + 2] and compact(pending[first])
                and compact(pending[first + 1]) and compact(pending[first + 2]) then
                columns = 3
            elseif maxColumns ~= 2 and not pending[first + 1] and compact(pending[first])
                and plans[#plans] and plans[#plans].columns == 3 then
                columns = 3
            end
            plans[#plans + 1] = {cells = {pending[first], pending[first + 1],
                columns == 3 and pending[first + 2] or nil}, columns = columns}
            first = first + columns
        end
        pending = {}
    end
    for _, group in ipairs(groups) do
        if paired and group.pack and not group.fullWidth then
            for _, cell in ipairs(group.cells) do pending[#pending + 1] = cell end
        else
            Flush()
            plans[#plans + 1] = {cells = group.cells,
                columns = group.fullWidth and 1 or (paired and 2 or 1), bare = group.bare}
        end
    end
    Flush()
    return plans
end

function Shared.LayoutSettingsRow(row, plan, width, style)
    local cells, columns = plan.cells, plan.columns
    local inset, padding = style.inset, style.padding
    local rowWidth = width - 2 * inset
    local cellWidth = rowWidth / columns - 2 * padding
    local height, stackedY = style.minimumHeight, -style.verticalPadding
    for column, cell in ipairs(cells) do
        if style.reparent and cell:GetParent() ~= row then cell:SetParent(row) end
        local cellHeight = math.max(style.minimumHeight, style.measure(cell, cellWidth))
        cell:ClearAllPoints()
        local top = not style.centered or columns == 1 and #cells > 1
        local left, right = top and "TOPLEFT" or "LEFT", top and "TOPRIGHT" or "RIGHT"
        local middle = top and "TOP" or "CENTER"
        local y = top and (columns == 1 and stackedY or -style.verticalPadding) or 0
        if columns == 3 then
            cell:SetPoint(left, row, left, padding + (column - 1) * (cellWidth + 2 * padding), y)
            cell:SetWidth(cellWidth)
        else
            cell:SetPoint(left, row, columns == 2 and column == 2 and middle or left, padding, y)
            cell:SetPoint(right, row, columns == 2 and column == 1 and middle or right, -padding, y)
        end
        height = math.max(height, cellHeight)
        stackedY = stackedY - cellHeight - style.gap
    end
    row._stacked = columns == 1 and cells[2] ~= nil
    if row._stacked then height = -stackedY - style.verticalPadding - style.gap end
    height = height + 2 * style.verticalPadding
    row:SetHeight(height)
    return height, rowWidth / columns
end

function Shared.LayoutSettingsDividers(row, plan, dividers, columnWidth, inset)
    for index, divider in ipairs(dividers) do
        divider:ClearAllPoints()
        if plan.columns == 3 then
            divider:SetPoint("TOPLEFT", row, "TOPLEFT", index * columnWidth, -inset)
            divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", index * columnWidth, inset)
        else
            divider:SetPoint("TOP", row, "TOP", 0, -inset)
            divider:SetPoint("BOTTOM", row, "BOTTOM", 0, inset)
        end
        divider:SetShown(plan.columns > index and plan.cells[index] ~= nil and not plan.bare)
    end
end

function Shared.MakeLayout(content, U, startY, options)
    if U and U._layoutModePositionOnly then
        return U.MakeSuppressedProviderLayout(content)
    end
    options = options or {}
    local Opts = ns.QUI_Options
    local PAD = options.padding or (Opts and Opts.PADDING) or 15
    local HEADER_GAP = options.headerGap or 26
    local SECTION_GAP = options.sectionGap or 14
    local BOTTOM_PAD = options.bottomPadding or 10
    local y = startY or -10
    local trailingGap = 0
    local L = {}
    local sections = {}
    local measuredFrames = {}
    if options.measureHeight then content._quiMeasureSettingsHeight = nil end

    local function TrackHeight(frame, height)
        measuredFrames[#measuredFrames + 1] = { frame = frame, height = height }
    end

    local function HeightDelta()
        local delta = 0
        for _, measured in ipairs(measuredFrames) do
            delta = delta + (measured.frame._quiMeasuredHeight or measured.frame:GetHeight()) - measured.height
        end
        return delta
    end

    local function CurrentY()
        return y - HeightDelta()
    end

    function L.headerAt(text)
        if type(text) ~= "string" or text == "" then return nil, nil end
        local originY = CurrentY()
        local GUI = _G.QUI and _G.QUI.GUI
        if options.searchSections and GUI and GUI.SetSearchSection then GUI:SetSearchSection(text) end
        local h = Opts.CreateAccentDotLabel(content, text, originY)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, originY)
        h:SetWidth(math.max(1, content:GetWidth() - 2 * PAD))
        if h._label and h.SetScript and h.GetTop then
            Shared.VerifyInitialBounds(h, content, function(self)
                local point, relative, relativePoint, x, offset = self:GetPoint(1)
                self:ClearAllPoints()
                self:SetPoint(point, relative, relativePoint, x, offset)
                self:SetWidth(math.max(1, content:GetWidth() - 2 * PAD))
                self._quiRecoveredWidth = true
                self._label:ClearAllPoints()
                self._label:SetPoint("LEFT", self._dot, "RIGHT", 7, 0)
            end, h._label)
            content:HookScript("OnSizeChanged", function(_, width)
                h:SetWidth(math.max(1, (width or content:GetWidth()) - 2 * PAD))
            end)
        end
        y = y - HEADER_GAP
        trailingGap = 0
        return h, originY
    end
    function L.sectionAt()
        local originY = CurrentY()
        local c = Opts.CreateSettingsCardGroup(content, originY)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, originY)
        c.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, originY)
        return c, originY
    end
    function L.closeSection(c)
        local height = c.Finalize() or c.frame:GetHeight()
        TrackHeight(c.frame, height)
        y = y - height - SECTION_GAP
        trailingGap = SECTION_GAP
    end
    function L.placeCustom(frame, height, gap)
        gap = gap or SECTION_GAP
        local originY = CurrentY()
        frame:SetParent(content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, originY)
        if options.explicitWidth then
            frame:SetWidth(math.max(1, content:GetWidth() - 2 * PAD))
        else
            frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, originY)
        end
        frame:SetHeight(height)
        if frame.GetTop and frame.HookScript and frame.GetParent then
            local recovered, recovering
            local function VerifyBounds()
                if frame:GetParent() ~= content or recovering then return end
                Shared.VerifyInitialBounds(frame, content, function(self)
                    recovering = true
                    -- Keep the current origin: cards above may have reflowed.
                    local point, relative, relativePoint, x, offset = self:GetPoint(1)
                    self:ClearAllPoints()
                    self:SetPoint(point, relative, relativePoint, x, offset)
                    self:SetWidth(math.max(1, content:GetWidth() - 2 * PAD))
                    recovered = true
                end)
            end
            frame:HookScript("OnShow", function()
                if recovering then recovering = nil else VerifyBounds() end
            end)
            frame:HookScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
            content:HookScript("OnSizeChanged", function()
                if frame:GetParent() ~= content then return end
                if recovered or options.explicitWidth then frame:SetWidth(math.max(1, content:GetWidth() - 2 * PAD)) end
                VerifyBounds()
            end)
            VerifyBounds()
        end
        TrackHeight(frame, height)
        y = y - height - gap
        trailingGap = gap
    end
    function L.spacer(amount, frame)
        amount = amount or 10
        if frame then TrackHeight(frame, amount) end
        y = y - amount
        trailingGap = amount
    end
    function L.paragraph(text)
        if type(text) ~= "string" or text == "" then return end
        local description = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        description:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        if options.wrapParagraph then
            description:SetWidth(math.max(1, content:GetWidth() - 2 * PAD))
            description:SetWordWrap(true)
        else
            description:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        end
        description:SetJustifyH("LEFT")
        description:SetText(text)
        local color = options.textColor or { 1, 1, 1, 0.6 }
        description:SetTextColor(color[1], color[2], color[3], color[4])
        local height = description.GetStringHeight and math.max(14, math.ceil(description:GetStringHeight() or 14)) or 14
        if options.wrapParagraph then description:SetHeight(height) end
        local gap = options.paragraphGap or 4
        y = y - height - gap
        trailingGap = gap
        return description
    end
    -- Schema sections retain their trailing spacing. Full pages use finish(),
    -- which removes the last section gap before applying bottom padding.
    function L.height(extra)
        local height = math.abs(y) + (extra or BOTTOM_PAD)
        if options.measureHeight then
            content._quiMeasureSettingsHeight = function()
                return height + HeightDelta()
            end
        end
        return height
    end

    local function relayoutSections()
        local cy = CurrentY()
        for _, s in ipairs(sections) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, cy)
            s:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, cy)
            cy = cy - s:GetHeight() - 4
        end
        content:SetHeight(math.abs(cy) - (#sections == 0 and trailingGap or 4) + BOTTOM_PAD)
    end
    function L.finish()
        content:SetHeight(math.abs(CurrentY()) - trailingGap + BOTTOM_PAD)
        return content:GetHeight()
    end
    function L.intro(text)
        local G = QUI and QUI.GUI
        local frame = CreateFrame("Frame", nil, content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        local lbl = G:CreateLabel(frame, text, 11, G.Colors.textMuted)
        lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        lbl:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        local approxHeight = math.max(18, math.ceil(#text / 90) * 15)
        frame:SetHeight(approxHeight)
        y = y - approxHeight - 8
        trailingGap = 8
        return lbl, frame
    end
    function L.getY() return CurrentY() end
    function L.setY(newY) y = newY + HeightDelta(); trailingGap = 0 end
    L.sections = sections
    L.relayoutSections = relayoutSections

    return L
end

function Shared.VerifyInitialBounds(frame, parent, repair, region)
    local firstLayoutFrame = false
    frame:SetScript("OnUpdate", function(self)
        if not parent:GetTop() then return end
        if not firstLayoutFrame then firstLayoutFrame = true; return end
        self:SetScript("OnUpdate", nil)
        if not (region or self):GetTop() then
            repair(self)
            self:Hide()
            self:Show()
        end
    end)
end

function Shared.RefreshInitialEditText(editBox, parent)
    local firstLayoutFrame = false
    editBox:SetScript("OnUpdate", function(self)
        if not parent:GetTop() then return end
        if not firstLayoutFrame then firstLayoutFrame = true; return end
        self:SetScript("OnUpdate", nil)
        if self:HasFocus() then return end
        local text = self:GetText()
        self:SetText("")
        self:SetText(text)
        self:SetCursorPosition(0)
    end)
end
