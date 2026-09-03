local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local ClassColor = Shared.ClassColor
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local CurrenciesView = {}
Alts.CurrenciesView = CurrenciesView

local ROW_H, TOP_H, FOOTER_H = 22, 28, 22
local CELL_PAD = 6
local ICON_SIZE = 16

local function CommaNumber(n)
    local s = tostring(math.floor(n or 0))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return formatted
end

function CurrenciesView.FormatQuantity(qty, max)
    if not qty then return "—" end
    local text = CommaNumber(qty)
    if max and max > 0 then
        text = text .. " / " .. CommaNumber(max)
    end
    return text
end

function CurrenciesView.BuildDisplayRows(characters, names, filter)
    names = names or {}
    local seen = {}
    for _, rec in pairs(characters or {}) do
        local cur = rec and rec.currencies
        if type(cur) == "table" then
            for id in pairs(cur) do seen[id] = true end
        end
    end
    local rows = {}
    for id in pairs(seen) do
        if not (filter and filter[id] == false) then
            rows[#rows + 1] = { currencyID = id, label = names[id] or ("Currency " .. id) }
        end
    end
    table.sort(rows, function(a, b)
        if a.label == b.label then return a.currencyID < b.currencyID end
        return a.label < b.label
    end)
    return rows
end

function CurrenciesView.ValueText(qty, info)
    local text = CurrenciesView.FormatQuantity(qty, info and info.max)
    if info and info.account then text = text .. " (account)" end
    return text
end

function CurrenciesView.ColumnWidths(rows, measure)
    local nameWidth, valueWidth = 0, 0
    for _, row in ipairs(rows or {}) do
        nameWidth = math.max(nameWidth, measure(row.label or "") or 0)
        valueWidth = math.max(valueWidth, measure(row.valueText or "") or 0)
    end
    return math.ceil(nameWidth) + CELL_PAD * 2 + ICON_SIZE + 6,
        math.ceil(valueWidth) + CELL_PAD * 2
end

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus   = ns.Storage and ns.Storage.Bus

    local frame = CreateFrame("Frame", nil, parent)

    local view        = { frame = frame }
    local offset      = 0
    local scrollbar
    local rows        = {}
    local rowPool     = {}
    local selectedKey = nil
    local nameWidth   = CELL_PAD * 2 + ICON_SIZE + 6
    local valueWidth  = CELL_PAD * 2

    local cachedChars = {}
    local liveInfo = {}

    local function ResolveInfo(id)
        local cached = liveInfo[id]
        if cached ~= nil then return cached or nil end
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo(id)
        if info and info.name then
            cached = {
                name = info.name,
                icon = info.iconFileID,
                max = info.maxQuantity,
                account = info.isAccountWide,
            }
        else
            cached = false
        end
        liveInfo[id] = cached
        return cached or nil
    end

    local function VisibleRows()
        local h = frame:GetHeight() or 0
        local usable = h - TOP_H - FOOTER_H
        if usable < ROW_H then return 1 end
        return math.max(1, math.floor(usable / ROW_H))
    end

    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    local measure = MakeFS(frame, 11)
    measure:Hide()
    local function Measure(text)
        measure:SetText(text or "")
        if measure.GetUnboundedStringWidth then
            return measure:GetUnboundedStringWidth() or 0
        end
        return measure:GetStringWidth() or 0
    end

    local selector = CreateFrame("Button", nil, frame)
    selector:SetHeight(22)
    selector:SetWidth(200)
    selector:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_PAD, 0)

    UIKit.CreateBackground(selector, 1, 1, 1, 0.06)
    UIKit.CreateBorderLines(selector)
    UIKit.UpdateBorderLines(selector, 1, 1, 1, 1, 0.2)
    selector:SetScript("OnEnter", function(self)
        UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.35)
    end)
    selector:SetScript("OnLeave", function(self)
        UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.2)
    end)

    local chevron = UIKit.CreateChevronCaret(selector, {
        point = "RIGHT", relativeTo = selector, relativePoint = "RIGHT",
        xPixels = -8, sizePixels = 10, lineWidthPixels = 6,
        r = 1, g = 1, b = 1, a = 0.45,
        expanded = true,
    })
    selector._chevron = chevron

    local selectorLabel = MakeFS(selector, 11)
    selectorLabel:SetPoint("LEFT", selector, "LEFT", 8, 0)
    selectorLabel:SetPoint("RIGHT", chevron, "LEFT", -4, 0)
    selectorLabel:SetJustifyH("LEFT")

    local function UpdateSelectorLabel()
        if not selectedKey then
            selectorLabel:SetText("—")
            selectorLabel:SetTextColor(0.7, 0.7, 0.7)
            return
        end
        local rec = cachedChars[selectedKey]
        local name = (rec and rec.name) or selectedKey
        local classToken = rec and rec.details and rec.details.class
        local r, g, b = ClassColor(classToken)
        selectorLabel:SetText(name)
        selectorLabel:SetTextColor(r, g, b)
    end

    selector:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        local keys = {}
        for key, rec in pairs(cachedChars) do
            keys[#keys + 1] = { key = key, name = (rec and rec.name) or key }
        end
        table.sort(keys, function(a, b) return a.name < b.name end)
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, entry in ipairs(keys) do
                local k = entry.key
                root:CreateButton(entry.name, function()
                    selectedKey = k
                    offset = 0
                    UpdateSelectorLabel()
                    view.Refresh()
                end)
            end
        end)
    end)

    local filterBtn = CreateFrame("Button", nil, frame)
    filterBtn:SetHeight(22)
    filterBtn:SetWidth(70)
    filterBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CELL_PAD, 0)
    UIKit.CreateBackground(filterBtn, 1, 1, 1, 0.06)
    UIKit.CreateBorderLines(filterBtn)
    UIKit.UpdateBorderLines(filterBtn, 1, 1, 1, 1, 0.2)
    filterBtn:SetScript("OnEnter", function(self)
        UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.35)
    end)
    filterBtn:SetScript("OnLeave", function(self)
        UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.2)
    end)
    local filterLabel = MakeFS(filterBtn, 11)
    filterLabel:SetPoint("CENTER")
    filterLabel:SetText(ns.L["Filter"])
    filterLabel:SetTextColor(0.9, 0.9, 0.9)

    Alts.FilterPopup.Attach({
        tabFrame = frame,
        anchorButton = filterBtn,
        getRows = function()
            local names = {}
            for _, rec in pairs(cachedChars) do
                if type(rec.currencies) == "table" then
                    for id in pairs(rec.currencies) do
                        if names[id] == nil then
                            local info = ResolveInfo(id)
                            names[id] = info and info.name or false
                        end
                    end
                end
            end
            local popupRows = {}
            for _, e in ipairs(CurrenciesView.BuildDisplayRows(cachedChars, names, nil)) do
                popupRows[#popupRows + 1] = { id = e.currencyID, label = e.label }
            end
            return popupRows
        end,
        isChecked = function(id)
            local s = Alts.GetSettings and Alts.GetSettings()
            local filter = s and s.currencyFilter
            return not (filter and filter[id] == false)
        end,
        setChecked = function(id, checked)
            local s = Alts.GetSettings and Alts.GetSettings()
            if not s then return end
            if not s.currencyFilter then s.currencyFilter = {} end
            if checked then s.currencyFilter[id] = nil
            else s.currencyFilter[id] = false end
        end,
        onChanged = function() view.Refresh() end,
    })

    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = Shared.CreateRow(frame, {
            height = ROW_H,
            onEnter = function(self)
                local row = self._row
                if not (row and row.currencyID) then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(row.label, 1, 1, 1)
                GameTooltip:AddLine(ns.L["Right-click to untrack"], 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end,
            onLeave = function() GameTooltip:Hide() end,
        })
        r._icon = r:CreateTexture(nil, "ARTWORK")
        r._icon:SetSize(ICON_SIZE, ICON_SIZE)
        r._icon:SetPoint("LEFT", r, "LEFT", CELL_PAD, 0)
        r._name  = MakeFS(r, 11)
        r._name:SetPoint("LEFT", r, "LEFT", CELL_PAD + ICON_SIZE + 6, 0)
        r._name:SetJustifyH("LEFT")
        r._value = MakeFS(r, 11)
        r._value:SetJustifyH("LEFT")
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then return end
            local row = self._row
            if not (row and row.currencyID) then return end
            local s = Alts.GetSettings and Alts.GetSettings()
            if not s then return end
            if not s.currencyFilter then s.currencyFilter = {} end
            s.currencyFilter[row.currencyID] = false
            GameTooltip:Hide()
            view.Refresh()
        end)
        rowPool[i] = r
        return r
    end

    local function RenderRows()
        local visible = VisibleRows()
        local maxOff  = math.max(0, #rows - visible)
        if offset > maxOff then offset = maxOff end
        if offset < 0 then offset = 0 end

        local topY = -TOP_H

        for i = 1, visible do
            local r   = GetRow(i)
            local row = rows[offset + i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, topY - (i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Shared.SCROLLBAR_RESERVE, topY - (i - 1) * ROW_H)

            if not row then
                r._row = nil
                r:Hide()
            else
                r._row = row
                local info = row.info
                if info and info.icon then
                    r._icon:SetTexture(info.icon)
                    r._icon:Show()
                else
                    r._icon:Hide()
                end

                r._name:SetWidth(math.max(1, nameWidth - CELL_PAD * 2 - ICON_SIZE - 6))
                r._name:SetText(row.label)
                r._name:SetTextColor(0.9, 0.9, 0.9)

                local qty = row.quantity
                r._value:ClearAllPoints()
                r._value:SetPoint("LEFT", r, "LEFT", nameWidth + CELL_PAD, 0)
                r._value:SetWidth(math.max(1, valueWidth - CELL_PAD * 2))
                r._value:SetText(row.valueText)
                if qty == nil then
                    r._value:SetTextColor(0.5, 0.5, 0.5)
                else
                    r._value:SetTextColor(0.9, 0.9, 0.9)
                end
                r:Show()
            end
        end
        for i = visible + 1, #rowPool do
            rowPool[i]:Hide()
        end
        if scrollbar then scrollbar:Update(#rows, visible, offset) end
    end

    local function ChooseDefaultKey(chars)
        if Store and Store.GetCurrentCharacterKey then
            local cur = Store.GetCurrentCharacterKey()
            if cur and chars[cur] then return cur end
        end
        for key in pairs(chars) do return key end
        return nil
    end

    function view.Refresh()
        if not (Store and Store.IsInitialized and Store.IsInitialized()) then return end

        cachedChars = {}
        if Store.ListCharacters and Store.GetCharacter then
            for _, key in ipairs(Store.ListCharacters()) do
                local rec = Store.GetCharacter(key)
                if rec then cachedChars[key] = rec end
            end
        end

        if not selectedKey or not cachedChars[selectedKey] then
            selectedKey = ChooseDefaultKey(cachedChars)
        end

        local names = {}
        local total = 0
        do
            local seen = {}
            for _, rec in pairs(cachedChars) do
                if type(rec.currencies) == "table" then
                    for id in pairs(rec.currencies) do seen[id] = true end
                end
            end
            for id in pairs(seen) do
                total = total + 1
                local info = ResolveInfo(id)
                if info then names[id] = info.name end
            end
        end
        local filter = (Alts.GetSettings and Alts.GetSettings() or {}).currencyFilter
        rows = CurrenciesView.BuildDisplayRows(cachedChars, names, filter)
        local selRec = selectedKey and cachedChars[selectedKey]
        for _, row in ipairs(rows) do
            row.info = ResolveInfo(row.currencyID)
            row.quantity = selRec and selRec.currencies and selRec.currencies[row.currencyID]
            row.valueText = CurrenciesView.ValueText(row.quantity, row.info)
        end
        nameWidth, valueWidth = CurrenciesView.ColumnWidths(rows, Measure)

        UpdateSelectorLabel()
        RenderRows()
        local hidden = total - #rows
        if hidden > 0 then
            footer:SetText(string.format("%d currencies (%d hidden)", #rows, hidden))
        else
            footer:SetText(string.format("%d currencies", #rows))
        end
    end

    scrollbar = Shared.CreateScrollBar(frame, {
        orientation = "vertical",
        onScroll = function(n) offset = n; RenderRows() end,
    })
    scrollbar.track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -28)
    scrollbar.track:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, FOOTER_H)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #rows - VisibleRows())
        offset = offset - delta
        if offset < 0 then offset = 0 end
        if offset > maxOff then offset = maxOff end
        RenderRows()
    end)

    if Bus and Bus.Subscribe then
        local function OnBus()
            if frame:IsVisible() then view.Refresh() end
        end
        Bus.Subscribe("CurrenciesChanged", OnBus)
        Bus.Subscribe("CharacterDeleted", OnBus)
    end

    return view
end

Alts.Window.RegisterTab("currencies", ns.L["Currencies"], Builder,
    "Currency amounts for the selected character — the list covers every currency seen on any of your characters.")
