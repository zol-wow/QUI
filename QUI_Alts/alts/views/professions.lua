---------------------------------------------------------------------------
-- Alts professions tab. One row per character — class-coloured name
-- (160 px) followed by up to five profession cells (110 px each), rendered
-- as "%s %d/%d" (name, rank, maxRank), primaries first (stored list order).
-- Empty slots show "—". Sort: character name ascending only (no sortable
-- headers). Footer: "%d characters". Wheel scroll + row pool exactly like
-- the roster tab.
--
-- Pure helpers are exported on Alts.ProfessionsView for headless tests.
-- Frame parts are NOT tested (no WoW frame API headless).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local ClassColor = Shared.ClassColor
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers

local ProfessionsView = {}
Alts.ProfessionsView = ProfessionsView

local ROW_H, HDR_H, FOOTER_H = 22, 20, 22
local CELL_PAD = 6

local NAME_W  = 160
local PROF_W  = 110
local MAX_PROFS = 5

---------------------------------------------------------------------------
-- Pure helpers (tested headless).
---------------------------------------------------------------------------

--- Returns a dense array of up to MAX_PROFS display strings for the
--- professions on a record, in stored list order (primaries first by
--- convention of the collector). Each string is "%s %d/%d".
--- Missing name falls back to "?"; missing rank/maxRank to 0.
function ProfessionsView.CellTexts(record)
    local profs = record and record.professions
    if not profs or #profs == 0 then return {} end
    local out = {}
    for _, p in ipairs(profs) do
        if #out >= MAX_PROFS then break end
        local name    = p.name    or "?"
        local rank    = p.rank    or 0
        local maxRank = p.maxRank or 0
        out[#out + 1] = string.format("%s %d/%d", name, rank, maxRank)
    end
    return out
end

---------------------------------------------------------------------------
-- Frame parts (no headless test).
---------------------------------------------------------------------------





-- Total number of columns: name + MAX_PROFS profession slots.
local TOTAL_COLS = 1 + MAX_PROFS

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus   = ns.Storage and ns.Storage.Bus

    local frame = CreateFrame("Frame", nil, parent)

    local view     = { frame = frame }
    local offset   = 0
    local scrollbar         -- vertical scroll bar (created below)
    local data     = {}   -- sorted array of { key, name, class, record }
    local rowPool  = {}

    local function VisibleRows()
        local h = frame:GetHeight() or 0
        local usable = h - HDR_H - FOOTER_H
        if usable < ROW_H then return 1 end
        return math.max(1, math.floor(usable / ROW_H))
    end

    -- footer
    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    ---- static header row -------------------------------------------------
    local hdrName = MakeFS(frame, 11)
    hdrName:SetPoint("TOPLEFT", frame, "TOPLEFT", CELL_PAD, 0)
    hdrName:SetWidth(NAME_W - CELL_PAD * 2)
    hdrName:SetText("Character")
    hdrName:SetTextColor(1, 0.82, 0)

    local hdrProf = MakeFS(frame, 11)
    hdrProf:SetPoint("TOPLEFT", frame, "TOPLEFT", NAME_W + CELL_PAD, 0)
    hdrProf:SetText("Professions")
    hdrProf:SetTextColor(1, 0.82, 0)

    ---- row pool ----------------------------------------------------------
    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = Shared.CreateRow(frame, { height = ROW_H })
        r._cells = {}
        for c = 1, TOTAL_COLS do
            r._cells[c] = MakeFS(r, 11)
        end
        rowPool[i] = r
        return r
    end

    ---- render ------------------------------------------------------------
    local function RenderRows()
        local visible  = VisibleRows()
        local maxOff   = math.max(0, #data - visible)
        if offset > maxOff then offset = maxOff end
        if offset < 0 then offset = 0 end

        for i = 1, visible do
            local r   = GetRow(i)
            local row = data[offset + i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -(HDR_H + (i - 1) * ROW_H))
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Shared.SCROLLBAR_RESERVE, -(HDR_H + (i - 1) * ROW_H))

            if not row then
                r._row = nil
                r:Hide()
            else
                r._row = row

                -- cell 1: character name (class-coloured)
                local nameCell = r._cells[1]
                nameCell:ClearAllPoints()
                nameCell:SetPoint("LEFT", r, "LEFT", CELL_PAD, 0)
                nameCell:SetWidth(NAME_W - CELL_PAD * 2)
                nameCell:SetText(row.name or row.key or "?")
                nameCell:SetTextColor(ClassColor(row.class))
                nameCell:Show()

                -- cells 2…TOTAL_COLS: profession slots
                local texts = ProfessionsView.CellTexts(row.record)
                for slot = 1, MAX_PROFS do
                    local cell = r._cells[1 + slot]
                    cell:ClearAllPoints()
                    cell:SetPoint("LEFT", r, "LEFT", NAME_W + (slot - 1) * PROF_W + CELL_PAD, 0)
                    cell:SetWidth(PROF_W - CELL_PAD * 2)
                    cell:SetText(texts[slot] or "—")
                    cell:SetTextColor(0.9, 0.9, 0.9)
                    cell:Show()
                end

                r:Show()
            end
        end
        -- hide surplus rows
        for i = visible + 1, #rowPool do
            rowPool[i]._row = nil
            rowPool[i]:Hide()
        end
        if scrollbar then scrollbar:Update(#data, visible, offset) end
    end

    function view.Refresh()
        if not (Store and Store.IsInitialized and Store.IsInitialized()) then return end

        data = {}
        if Store.ListCharacters and Store.GetCharacter then
            for _, key in ipairs(Store.ListCharacters()) do
                local rec = Store.GetCharacter(key)
                if rec then
                    data[#data + 1] = {
                        key    = key,
                        name   = rec.name or key,
                        class  = rec.details and rec.details.class,
                        record = rec,
                    }
                end
            end
        end

        -- sort by character name ascending
        table.sort(data, function(a, b)
            return (a.name or "") < (b.name or "")
        end)

        RenderRows()
        footer:SetText(string.format("%d characters", #data))
    end

    -- vertical scroll bar: rows sit below the header row, above the footer line.
    scrollbar = Shared.CreateScrollBar(frame, {
        orientation = "vertical",
        onScroll = function(n) offset = n; RenderRows() end,
    })
    scrollbar.track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -HDR_H)
    scrollbar.track:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, FOOTER_H)

    -- mouse-wheel scroll
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #data - VisibleRows())
        offset = offset - delta
        if offset < 0 then offset = 0 end
        if offset > maxOff then offset = maxOff end
        RenderRows()
    end)

    -- Bus subscriptions: refresh only when visible
    if Bus and Bus.Subscribe then
        local function OnBus()
            if frame:IsVisible() then view.Refresh() end
        end
        Bus.Subscribe("ProfessionsChanged", OnBus)
        Bus.Subscribe("CharacterDeleted",   OnBus)
        Bus.Subscribe("CharacterChanged",   OnBus)
    end

    return view
end

Alts.Window.RegisterTab("professions", "Professions", Builder,
    "Primary and secondary profession ranks for every cached character.")
