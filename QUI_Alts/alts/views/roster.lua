---------------------------------------------------------------------------
-- Alts roster tab. Reads ns.Storage (Store + Bus), renders a sortable
-- column list with a totals footer. Row pool + wheel offset (no
-- ScrollFrame; rows are uniform and few — tens of characters). Column set
-- honors the profile alts.columns toggles; layout reflows on Refresh.
--
-- View contract: builder(parent) returns { frame, Refresh() } (window.lua).
-- Content fonts are owned here (the chassis reskins chrome + tab labels
-- only): every FontString sets its font at creation from the general font.
--
-- Pure helpers (CellText, BuildActiveColumns) are published on
-- Alts.RosterView for headless unit tests; the frame parts have no test.
---------------------------------------------------------------------------
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

-- Column catalog. `always` columns ignore the profile toggle; the rest are
-- gated by alts.columns[<toggleKey or id>]. `sortKey` maps to a details
-- field (BuildRows reads details[sortKey], "name" is special-cased there);
-- a column with no sortKey is non-sortable. `desc` = the default direction
-- when this header is first clicked.
local COLUMNS = {
    { id = "name",        label = "Character",   width = 160, sortKey = "name",        always = true },
    { id = "level",       label = "Lvl",         width = 40,  sortKey = "level",       desc = true, always = true },
    { id = "ilvl",        label = "iLvl",        width = 52,  sortKey = "ilvl",        desc = true },
    { id = "gold",        label = "Gold",        width = 96,  sortKey = "money",       desc = true },
    { id = "played",      label = "Played",      width = 72,  sortKey = "playedTotal", desc = true },
    { id = "rested",      label = "Rested",      width = 56,  sortKey = "restedXP",    desc = true },
    { id = "professions", label = "Professions", width = 160 },
    { id = "zone",        label = "Zone",        width = 150 },
    { id = "lastSeen",    label = "Seen",        width = 72,  sortKey = "lastSeen",    desc = true },
}
RosterView.COLUMNS = COLUMNS

--- Class token → r,g,b. RAID_CLASS_COLORS read directly (chat sender-recolor
--- precedent; routing through the CUSTOM-aware helper would drift here too).

--- Cell display text for a column over a built row (see RD.BuildRows shape:
--- { key, name, realm, details, record }). `now` for relative timestamps.
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
        -- Compact: "Alch 75 · Herb 50" — primary professions, name truncated
        -- to 4 chars. NOTE: :sub(1,4) is byte-wise (latin-only); acceptable
        -- v1, cells also SetWordWrap(false) so the full string ellipsizes.
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

--- Filter the column catalog by the profile toggles. `always` columns are
--- always kept; the rest survive only if columnsCfg[id] is truthy. Order is
--- preserved. columnsCfg nil → all columns shown (defaults-on fallback).
function RosterView.BuildActiveColumns(columnsCfg)
    local active = {}
    for _, col in ipairs(COLUMNS) do
        if col.always or columnsCfg == nil or columnsCfg[col.id] then
            active[#active + 1] = col
        end
    end
    return active
end

---------------------------------------------------------------------------
-- Frame parts (no headless test).
---------------------------------------------------------------------------




local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus = ns.Storage and ns.Storage.Bus

    local frame = CreateFrame("Frame", nil, parent)

    -- view state
    local view = { frame = frame }
    local sortKey, sortDesc = "name", false
    local offset = 0
    local data = {}          -- last-built rows
    local activeCols = {}    -- last active-column set
    local headers = {}       -- pooled header buttons (one per COLUMNS slot)
    local rowPool = {}       -- pooled row buttons

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

    -- footer (bottom-left)
    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    ---- header pool -------------------------------------------------------
    local function GetHeader(i)
        local h = headers[i]
        if h then return h end
        h = CreateFrame("Button", nil, frame)
        h:SetHeight(HDR_H)
        h._label = MakeFS(h, 11)
        h._label:SetPoint("LEFT", h, "LEFT", CELL_PAD, 0)
        h._label:SetTextColor(1, 0.82, 0)
        -- Sort indicator: texture, not a ▲/▼ glyph — the QUI font lacks the
        -- geometric-shape codepoints, so text arrows render as tofu boxes.
        -- Blizzard's AH header atlas; texcoord flip = direction (Blizzard_
        -- AuctionHouseTableBuilder SetArrowState precedent).
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

    ---- row pool ----------------------------------------------------------
    -- Each row owns a FIXED cell pool of #COLUMNS FontStrings; Refresh
    -- positions/shows only the active columns (simplest correct approach for
    -- a changing active-column set — no per-Refresh re-create).
    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = CreateFrame("Button", nil, frame)
        r:SetHeight(ROW_H)
        r:RegisterForClicks("RightButtonUp")
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(1, 1, 1, 0)
        r._bg = bg
        r._cells = {}
        for c = 1, #COLUMNS do
            r._cells[c] = MakeFS(r, 11)
        end
        r:SetScript("OnEnter", function(self) self._bg:SetVertexColor(1, 1, 1, 0.08) end)
        r:SetScript("OnLeave", function(self) self._bg:SetVertexColor(1, 1, 1, 0) end)
        r:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then return end
            -- snapshot at click time: the menu's title AND its delete
            -- action both bind to what the user right-clicked, even if the
            -- pooled row re-renders underneath while the menu is open
            -- (DeleteCharacter no-ops on an already-gone key).
            local row = self._row
            if not row then return end
            local curKey = Store and Store.GetCurrentCharacterKey and Store.GetCurrentCharacterKey()
            if row.key == curKey then return end -- never delete the current character
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

    ---- layout / render ---------------------------------------------------
    -- Effective per-active-column widths. With every column toggled on the
    -- catalog is wider than the default window; squeeze proportionally to
    -- the view width instead of bleeding past the border (cells ellipsize —
    -- SetWordWrap(false)). Cached: wheel-scroll RenderRows reuses the last
    -- Refresh's widths.
    local colWidths = {}
    local function ComputeColWidths()
        local total = 0
        for _, col in ipairs(activeCols) do total = total + col.width end
        local avail = frame:GetWidth() or 0
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
                -- ascending = flipped (points up), descending = native
                h._arrow:SetTexCoord(0, 1, sortDesc and 0 or 1, sortDesc and 1 or 0)
                h._arrow:Show()
            else
                h._arrow:Hide()
            end
            h:Show()
            x = x + colWidths[i]
        end
        -- hide surplus headers
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
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(HDR_H + (i - 1) * ROW_H))
            if not row then
                r._row = nil -- hidden rows must not retain a clickable target
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
        -- hide surplus rows
        for i = visible + 1, #rowPool do
            rowPool[i]._row = nil
            rowPool[i]:Hide()
        end
    end

    function view.Refresh()
        -- pre-login / read-only store: render nothing rather than a
        -- misleading "0 characters" roster
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

    -- mouse-wheel scroll, clamped to #data - VisibleRows().
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #data - VisibleRows())
        offset = offset - delta
        if offset < 0 then offset = 0 end
        if offset > maxOffset then offset = maxOffset end
        RenderRows(time())
    end)

    -- Bus: refresh only when visible (window.lua refreshes the active tab on
    -- show; these keep an open roster live without churning hidden views).
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

Alts.Window.RegisterTab("roster", "Roster", Builder,
    "Every cached character with level, item level, gold, played time, and more. Click a column header to sort; right-click a row to delete that character from the cache.")
