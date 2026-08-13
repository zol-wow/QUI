local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local ClassColor = Shared.ClassColor
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local RD = Alts.RosterData

local RosterView = {}
Alts.RosterView = RosterView

local ROW_H, HDR_H, FOOTER_H = 22, 20, 22
local CELL_PAD = 6

local COLUMNS = {
    { id = "name",        label = ns.L["Character"],   width = 160, sortKey = "name",        always = true },
    { id = "level",       label = ns.L["Lvl"],         width = 40,  sortKey = "level",       desc = true, always = true },
    { id = "ilvl",        label = ns.L["iLvl"],        width = 52,  sortKey = "ilvl",        desc = true },
    { id = "gold",        label = ns.L["Gold"],        width = 96,  sortKey = "money",       desc = true },
    { id = "played",      label = ns.L["Played"],      width = 72,  sortKey = "playedTotal", desc = true },
    { id = "rested",      label = ns.L["Rested"],      width = 56,  sortKey = "restedXP",    desc = true },
    { id = "professions", label = ns.L["Professions"], width = 160 },
    { id = "zone",        label = ns.L["Zone"],        width = 150 },
    { id = "lastSeen",    label = ns.L["Seen"],        width = 72,  sortKey = "lastSeen",    desc = true },
}
RosterView.COLUMNS = COLUMNS

function RosterView.CellText(col, row, now)
    local d = row.details or {}
    if col.id == "name" then
        return row.name or row.key or "?"
    elseif col.id == "level" then
        return d.level and tostring(d.level) or "—"
    elseif col.id == "ilvl" then
        return d.ilvl and string.format("%.0f", d.ilvl) or "—"
    elseif col.id == "gold" then
        return RD.FormatGold(d.money)
    elseif col.id == "played" then
        return RD.FormatPlayed(d.playedTotal)
    elseif col.id == "rested" then
        if d.restedXP and d.xpMax and d.xpMax > 0 then
            return string.format("%d%%", math.floor(d.restedXP / d.xpMax * 100 + 0.5))
        end
        return "—"
    elseif col.id == "professions" then
        local parts = {}
        local profs = (row.record and row.record.professions) or {}
        for _, p in ipairs(profs) do
            if p.isPrimary then
                parts[#parts + 1] = string.format("%s %d", (p.name or "?"):sub(1, 4), p.rank or 0)
            end
        end
        return (#parts > 0) and table.concat(parts, " · ") or "—"
    elseif col.id == "zone" then
        return d.zone or "—"
    elseif col.id == "lastSeen" then
        return RD.FormatLastSeen(d.lastSeen, now)
    end
    return ""
end

function RosterView.BuildActiveColumns(columnsCfg)
    local active = {}
    for _, col in ipairs(COLUMNS) do
        if col.always or columnsCfg == nil or columnsCfg[col.id] then
            active[#active + 1] = col
        end
    end
    return active
end

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus = ns.Storage and ns.Storage.Bus

    local frame = CreateFrame("Frame", nil, parent)

    local view = { frame = frame }
    local sortKey, sortDesc = "name", false
    local offset = 0
    local scrollbar
    local data = {}
    local activeCols = {}
    local headers = {}
    local rowPool = {}

    local function ColumnsCfg()
        local s = Alts.GetSettings and Alts.GetSettings()
        return s and s.columns
    end

    local function VisibleRows()
        local h = frame:GetHeight() or 0
        local usable = h - HDR_H - FOOTER_H
        if usable < ROW_H then return 1 end
        return math.max(1, math.floor(usable / ROW_H))
    end

    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    local function GetHeader(i)
        local h = headers[i]
        if h then return h end
        h = CreateFrame("Button", nil, frame)
        h:SetHeight(HDR_H)
        h._label = MakeFS(h, 11)
        h._label:SetPoint("LEFT", h, "LEFT", CELL_PAD, 0)
        h._label:SetTextColor(1, 0.82, 0)
        h._arrow = h:CreateTexture(nil, "ARTWORK")
        h._arrow:SetAtlas("auctionhouse-ui-sortarrow", true)
        h._arrow:SetPoint("LEFT", h._label, "RIGHT", 3, 0)
        h._arrow:Hide()
        h:SetScript("OnClick", function()
            local col = h._col
            if not (col and col.sortKey) then return end
            if sortKey == col.sortKey then
                sortDesc = not sortDesc
            else
                sortKey, sortDesc = col.sortKey, col.desc and true or false
            end
            offset = 0
            view.Refresh()
        end)
        headers[i] = h
        return h
    end

    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = Shared.CreateRow(frame, { height = ROW_H })
        r:RegisterForClicks("RightButtonUp")
        r._cells = {}
        for c = 1, #COLUMNS do
            r._cells[c] = MakeFS(r, 11)
        end
        r:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then return end
            local row = self._row
            if not row then return end
            local curKey = Store and Store.GetCurrentCharacterKey and Store.GetCurrentCharacterKey()
            if row.key == curKey then return end
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(row.name or row.key)
                root:CreateButton("Delete from cache", function()
                    if Store and Store.DeleteCharacter then Store.DeleteCharacter(row.key) end
                    view.Refresh()
                end)
            end)
        end)
        rowPool[i] = r
        return r
    end

    local colWidths = {}
    local function ComputeColWidths()
        local total = 0
        for _, col in ipairs(activeCols) do total = total + col.width end
        local avail = math.max(0, (frame:GetWidth() or 0) - Shared.SCROLLBAR_RESERVE)
        local scale = (avail > 0 and total > avail) and (avail / total) or 1
        for i, col in ipairs(activeCols) do
            colWidths[i] = math.max(20, math.floor(col.width * scale))
        end
        for i = #activeCols + 1, #colWidths do colWidths[i] = nil end
    end

    local function LayoutHeaders()
        ComputeColWidths()
        local x = 0
        for i, col in ipairs(activeCols) do
            local h = GetHeader(i)
            h._col = col
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
            h:SetWidth(colWidths[i])
            h._label:SetText(col.label)
            if col.sortKey == sortKey then
                h._arrow:SetTexCoord(0, 1, sortDesc and 0 or 1, sortDesc and 1 or 0)
                h._arrow:Show()
            else
                h._arrow:Hide()
            end
            h:Show()
            x = x + colWidths[i]
        end
        for i = #activeCols + 1, #headers do
            headers[i]:Hide()
        end
    end

    local function RenderRows(now)
        local visible = VisibleRows()
        local maxOffset = math.max(0, #data - visible)
        if offset > maxOffset then offset = maxOffset end
        if offset < 0 then offset = 0 end

        for i = 1, visible do
            local r = GetRow(i)
            local row = data[offset + i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(HDR_H + (i - 1) * ROW_H))
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Shared.SCROLLBAR_RESERVE, -(HDR_H + (i - 1) * ROW_H))
            if not row then
                r._row = nil
                r:Hide()
            else
                r._row = row
                local x = 0
                for c = 1, #COLUMNS do
                    local cell = r._cells[c]
                    local col = activeCols[c]
                    if col then
                        local w = colWidths[c] or col.width
                        cell:ClearAllPoints()
                        cell:SetPoint("LEFT", r, "LEFT", x + CELL_PAD, 0)
                        cell:SetWidth(math.max(1, w - CELL_PAD * 2))
                        cell:SetText(RosterView.CellText(col, row, now))
                        if col.id == "name" then
                            cell:SetTextColor(ClassColor(row.details and row.details.class))
                        else
                            cell:SetTextColor(0.9, 0.9, 0.9)
                        end
                        cell:Show()
                        x = x + w
                    else
                        cell:Hide()
                    end
                end
                r:Show()
            end
        end
        for i = visible + 1, #rowPool do
            rowPool[i]._row = nil
            rowPool[i]:Hide()
        end
        if scrollbar then scrollbar:Update(#data, visible, offset) end
    end

    function view.Refresh()
        if not (Store and Store.IsInitialized and Store.IsInitialized()) then return end
        activeCols = RosterView.BuildActiveColumns(ColumnsCfg())

        local chars = {}
        if Store and Store.ListCharacters and Store.GetCharacter then
            for _, key in ipairs(Store.ListCharacters()) do
                local rec = Store.GetCharacter(key)
                if rec then chars[key] = rec end
            end
        end

        data = RD.BuildRows(chars, { sortKey = sortKey, sortDesc = sortDesc })

        local now = time()
        LayoutHeaders()
        RenderRows(now)
        footer:SetText(string.format("%d characters — total %s",
            #data, RD.FormatGold(RD.TotalGold(chars))))
    end

    scrollbar = Shared.CreateScrollBar(frame, {
        orientation = "vertical",
        onScroll = function(n) offset = n; RenderRows(time()) end,
    })
    scrollbar.track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -HDR_H)
    scrollbar.track:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, FOOTER_H)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #data - VisibleRows())
        offset = offset - delta
        if offset < 0 then offset = 0 end
        if offset > maxOffset then offset = maxOffset end
        RenderRows(time())
    end)

    if Bus and Bus.Subscribe then
        local function OnBus()
            if frame:IsVisible() then view.Refresh() end
        end
        Bus.Subscribe("CharacterChanged", OnBus)
        Bus.Subscribe("ProfessionsChanged", OnBus)
        Bus.Subscribe("MoneyChanged", OnBus)
        Bus.Subscribe("CharacterDeleted", OnBus)
    end

    return view
end

Alts.Window.RegisterTab("roster", ns.L["Roster"], Builder,
    "Every cached character with level, item level, gold, played time, and more. Click a column header to sort; right-click a row to delete that character from the cache.")
