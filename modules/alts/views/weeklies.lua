local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local ClassColor = Shared.ClassColor
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local RD = Alts.RosterData

local WeekliesView = {}
Alts.WeekliesView = WeekliesView

local ROW_H, HDR_H, FOOTER_H = 22, 48, 22
local CELL_PAD = 6
local TOOLBAR_H = 28

local COLUMN_LABELS = {
    ns.L["Character"],
    ns.L["M+ Rating"],
    ns.L["Mythic+ Keystone"],
    ns.L["Great Vault"],
    ns.L["Instance lockouts"],
}

local VAULT_TYPE_LABEL = {
    [1] = "Raid",
    [2] = "Dungeons",
    [3] = "World",
    [4] = "PvP",
    [5] = "Concession",
}
do
    local PRETTY = { Raid = "Raid", Activities = "Dungeons", World = "World",
        RankedPvP = "PvP", Concession = "Concession" }
    local enum = type(Enum) == "table" and Enum.WeeklyRewardChestThresholdType
    if type(enum) == "table" then
        for name, v in pairs(enum) do
            if type(v) == "number" then
                VAULT_TYPE_LABEL[v] = PRETTY[name] or name
            end
        end
    end
end

local function VaultTypeLabel(t)
    return VAULT_TYPE_LABEL[t] or ("Type " .. t)
end

local VAULT_SHORT_LABEL = {
    Raid = ns.L["R"],
    Dungeons = ns.L["D"],
    World = ns.L["W"],
    PvP = ns.L["PvP"],
    Concession = ns.L["C"],
}

function WeekliesView.VaultSummary(weeklies, compact)
    local acts = weeklies and weeklies.activities
    if not acts or #acts == 0 then return "—" end

    local totals    = {}
    local completed = {}
    local typeOrder = {}

    for _, a in ipairs(acts) do
        local t = a.type
        if t then
            if not totals[t] then
                totals[t]    = 0
                completed[t] = 0
                typeOrder[#typeOrder + 1] = t
            end
            totals[t] = totals[t] + 1
            if (a.progress or 0) >= (a.threshold or 0) then
                completed[t] = completed[t] + 1
            end
        end
    end

    table.sort(typeOrder)

    local parts = {}
    for _, t in ipairs(typeOrder) do
        local label = VaultTypeLabel(t)
        if compact then label = VAULT_SHORT_LABEL[label] or label end
        parts[#parts + 1] = string.format("%s %d/%d", label, completed[t], totals[t])
    end

    if #parts == 0 then return "—" end
    return table.concat(parts, " · ")
end

function WeekliesView.KeystoneText(weeklies)
    if not weeklies then return "—" end
    local mapID = weeklies.keystoneMapID
    if not mapID then return "—" end
    local name  = weeklies.keystoneName
    local level = weeklies.keystoneLevel
    if name then
        if level then
            return string.format("%s +%d", name, level)
        else
            return string.format("%s +?", name)
        end
    else
        if level then
            return string.format("+%d", level)
        else
            return "+?"
        end
    end
end

function WeekliesView.LockoutLine(lockout, now)
    if not lockout then return "" end

    local name = lockout.name or "?"
    local diff = lockout.difficultyName or ""

    local bossStr = ""
    local killed = lockout.bossesKilled
    local total  = lockout.bossesTotal
    if type(killed) == "number" and type(total) == "number" then
        bossStr = string.format("%d/%d", killed, total)
    end

    local resetStr = (RD and RD.FormatResetIn)
        and RD.FormatResetIn(lockout.resetAt, now)
        or "—"

    local parts = {}
    if name ~= "" then parts[#parts + 1] = name end
    if diff ~= "" then parts[#parts + 1] = diff end
    if bossStr ~= "" then parts[#parts + 1] = bossStr end

    local line = table.concat(parts, " ") .. " — resets " .. resetStr
    if lockout.extended then
        line = line .. " (extended)"
    end
    return line
end

function WeekliesView.LockoutCells(lockout, now)
    local killed, total = lockout.bossesKilled, lockout.bossesTotal
    local reset = RD.FormatResetIn(lockout.resetAt, now)
    if lockout.extended then reset = reset .. " (" .. ns.L["extended"] .. ")" end
    return {
        lockout.name or "?",
        lockout.difficultyName or "—",
        type(killed) == "number" and type(total) == "number"
            and string.format("%d/%d", killed, total) or "—",
        reset,
    }
end

function WeekliesView.BuildDisplayRows(characters, collapsed)
    local sorted = {}
    for key, rec in pairs(characters or {}) do
        sorted[#sorted + 1] = {
            key      = key,
            name     = (rec and rec.name) or key,
            class    = rec and rec.details and rec.details.class,
            weeklies = rec and rec.weeklies,
            lockouts = rec and rec.lockouts,
        }
    end
    table.sort(sorted, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    local rows = {}
    for groupIndex, entry in ipairs(sorted) do
        rows[#rows + 1] = {
            kind     = "char",
            key      = entry.key,
            name     = entry.name,
            class    = entry.class,
            weeklies = entry.weeklies,
            lockouts = entry.lockouts,
            groupIndex = groupIndex,
        }
        local lockouts = entry.lockouts
        if lockouts and not (collapsed and collapsed[entry.key]) then
            for _, lo in ipairs(lockouts) do
                rows[#rows + 1] = { kind = "lockout", lockout = lo, key = entry.key,
                    name = entry.name, class = entry.class, groupIndex = groupIndex }
            end
        end
    end

    return rows
end

function WeekliesView.CellTexts(row)
    if not (row and row.kind == "char") then return nil end
    local w = row.weeklies
    local rating = w and w.mplusRating
    return {
        row.name or row.key or "?",
        rating and rating > 0 and string.format("%d", rating) or "—",
        WeekliesView.KeystoneText(w),
        WeekliesView.VaultSummary(w, true),
        row.lockouts and (#row.lockouts > 0
            and string.format(ns.L["%d saved"], #row.lockouts) or ns.L["None"]) or ns.L["Unknown"],
    }
end

function WeekliesView.ColumnWidths(rows, measure, available)
    local widths = {}
    for i, label in ipairs(COLUMN_LABELS) do
        widths[i] = math.ceil(measure(label) or 0) + CELL_PAD * 2
    end
    for _, row in ipairs(rows or {}) do
        local texts = row.cellTexts or WeekliesView.CellTexts(row)
        row.cellTexts = texts
        if texts then
            for i, text in ipairs(texts) do
                widths[i] = math.max(widths[i], math.ceil(measure(text) or 0) + CELL_PAD * 2)
            end
        end
    end
    if available and available > 0 then
        local summaryBudget = available * 0.55
        widths[4] = math.min(widths[4], summaryBudget * 0.55)
        local total = widths[1] + widths[2] + widths[3]
        local scale = math.min(1, (summaryBudget - widths[4]) / total)
        local used = widths[4]
        for i = 1, 3 do
            widths[i] = math.floor(widths[i] * scale)
            used = used + widths[i]
        end
        widths[5] = available - used
    end
    return widths
end

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus = ns.Storage and ns.Storage.Bus
    local frame = CreateFrame("Frame", nil, parent)
    local view = { frame = frame }
    local offset = 0
    local rows, rowPool, collapsed = {}, {}, {}
    local colWidths = {}
    local scrollbar

    local function VisibleRows()
        return math.max(1, math.floor(((frame:GetHeight() or 0) - HDR_H - FOOTER_H) / ROW_H))
    end

    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(1, 1, 1)
    local measure = MakeFS(frame, 11)
    measure:Hide()
    local function Measure(text)
        measure:SetText(text or "")
        if measure.GetUnboundedStringWidth then
            return measure:GetUnboundedStringWidth() or 0
        end
        return measure:GetStringWidth() or 0
    end

    local headers = {}
    for i, label in ipairs(COLUMN_LABELS) do
        local header = MakeFS(frame, 11)
        header:SetText(label)
        header:SetTextColor(1, 1, 1)
        header:SetJustifyH("LEFT")
        headers[i] = header
    end

    local function LayoutHeaders()
        local x = 0
        for i, header in ipairs(headers) do
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", x + CELL_PAD, -TOOLBAR_H)
            header:SetWidth(math.max(1, colWidths[i] - CELL_PAD * 2))
            x = x + colWidths[i]
        end
    end

    local function GetRow(i)
        if rowPool[i] then return rowPool[i] end
        local r = Shared.CreateRow(frame, { height = ROW_H,
            onEnter = function(self)
                local row = self._row
                if not row then return end
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 12, 12)
                GameTooltip:SetText(row.name or row.key)
                if row.kind == "lockout" then
                    GameTooltip:AddLine(WeekliesView.LockoutLine(row.lockout), 1, 1, 1, true)
                else
                    for c = 2, 5 do
                        local text = c == 4 and WeekliesView.VaultSummary(row.weeklies) or row.cellTexts[c]
                        GameTooltip:AddLine(COLUMN_LABELS[c] .. ": " .. text, 1, 1, 1, true)
                    end
                    if row.lockouts and #row.lockouts > 0 and collapsed[row.key] then
                        GameTooltip:AddLine(ns.L["Click to expand for details"], 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
            end,
            onLeave = function() GameTooltip:Hide() end,
        })
        r._stripe = r:CreateTexture(nil, "BACKGROUND")
        r._stripe:SetAllPoints()
        r._cells, r._details = {}, {}
        for c = 1, 5 do
            r._cells[c] = MakeFS(r, 11)
            r._cells[c]:SetJustifyH("LEFT")
        end
        for c = 1, 4 do
            r._details[c] = MakeFS(r, 11)
            r._details[c]:SetJustifyH("LEFT")
            r._details[c]:SetTextColor(1, 1, 1)
        end
        r._toggle = CreateFrame("Button", nil, r)
        r._toggle:SetHeight(ROW_H)
        r._arrow = MakeFS(r._toggle, 11)
        r._arrow:SetPoint("LEFT", r._toggle, "LEFT", 0, 0)
        local onEnter, onLeave = r:GetScript("OnEnter"), r:GetScript("OnLeave")
        r._toggle:SetScript("OnEnter", function() onEnter(r) end)
        r._toggle:SetScript("OnLeave", function() onLeave(r) end)
        local function ToggleLockouts()
            local row = r._row
            if not row or row.kind ~= "char" or not row.lockouts or #row.lockouts == 0 then return end
            collapsed[row.key] = not collapsed[row.key]
            onLeave(r)
            view.Refresh()
            if r:IsShown() and r:IsMouseOver() then onEnter(r) end
        end
        r:SetScript("OnClick", ToggleLockouts)
        r._toggle:SetScript("OnClick", ToggleLockouts)
        rowPool[i] = r
        return r
    end

    local function RenderRows()
        local visible = VisibleRows()
        offset = math.max(0, math.min(offset, #rows - visible))
        local lockoutX = colWidths[1] + colWidths[2] + colWidths[3] + colWidths[4]
        for i = 1, visible do
            local r, row = GetRow(i), rows[offset + i]
            r._row = row
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HDR_H - (i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Shared.SCROLLBAR_RESERVE, -HDR_H - (i - 1) * ROW_H)
            r._toggle:Hide()
            for _, fs in ipairs(r._cells) do fs:Hide() end
            for _, fs in ipairs(r._details) do fs:Hide() end
            if row then
                r._stripe:SetColorTexture(1, 1, 1, row.groupIndex % 2 == 0 and 0.035 or 0)
                if row.kind == "char" then
                    local x = 0
                    for c, fs in ipairs(r._cells) do
                        local inset = c == 5 and row.lockouts and #row.lockouts > 0 and 16 or 0
                        fs:ClearAllPoints()
                        fs:SetPoint("LEFT", r, "LEFT", x + CELL_PAD + inset, 0)
                        fs:SetWidth(math.max(1, colWidths[c] - CELL_PAD * 2 - inset))
                        fs:SetText(row.cellTexts[c])
                        fs:SetTextColor(1, 1, 1)
                        fs:Show()
                        x = x + colWidths[c]
                    end
                    r._cells[1]:SetTextColor(ClassColor(row.class))
                    if row.lockouts and #row.lockouts > 0 then
                        r._toggle:ClearAllPoints()
                        r._toggle:SetPoint("LEFT", r, "LEFT", lockoutX + CELL_PAD, 0)
                        r._toggle:SetWidth(math.max(1, colWidths[5] - CELL_PAD * 2))
                        r._arrow:SetText(collapsed[row.key] and "+" or "−")
                        r._toggle:Show()
                    end
                else
                    local texts = WeekliesView.LockoutCells(row.lockout)
                    local fractions = { 0.40, 0.22, 0.12, 0.26 }
                    local x = lockoutX + CELL_PAD
                    local available = colWidths[5] - CELL_PAD * 2
                    for c, fs in ipairs(r._details) do
                        local width = available * fractions[c]
                        fs:ClearAllPoints()
                        fs:SetPoint("LEFT", r, "LEFT", x, 0)
                        fs:SetWidth(math.max(1, width - CELL_PAD))
                        fs:SetText(texts[c])
                        fs:Show()
                        x = x + width
                    end
                    if i == 1 then
                        local name = r._cells[1]
                        name:ClearAllPoints()
                        name:SetPoint("LEFT", r, "LEFT", CELL_PAD, 0)
                        name:SetWidth(math.max(1, colWidths[1] - CELL_PAD * 2))
                        name:SetText(row.name)
                        name:SetTextColor(ClassColor(row.class))
                        name:Show()
                    end
                end
                r:Show()
            else
                r:Hide()
            end
        end
        for i = visible + 1, #rowPool do
            rowPool[i]._row = nil
            rowPool[i]:Hide()
        end
        if scrollbar then scrollbar:Update(#rows, visible, offset) end
    end

    function view.Refresh()
        if not (Store and Store.IsInitialized and Store.IsInitialized()) then return end
        local chars, charCount = {}, 0
        for _, key in ipairs(Store.ListCharacters()) do
            local rec = Store.GetCharacter(key)
            if rec then chars[key] = rec; charCount = charCount + 1 end
        end
        rows = WeekliesView.BuildDisplayRows(chars, collapsed)
        colWidths = WeekliesView.ColumnWidths(rows, Measure, (frame:GetWidth() or 0) - Shared.SCROLLBAR_RESERVE)
        LayoutHeaders()
        RenderRows()
        footer:SetText(string.format(ns.L["%d characters"], charCount))
    end

    local function SetAll(value)
        for _, key in ipairs(Store.ListCharacters()) do collapsed[key] = value end
        offset = 0
        view.Refresh()
    end
    local collapseAll = ns.UIKit.CreateButton(frame, {
        text = ns.L["Collapse all"], height = 22,
        onClick = function() SetAll(true) end,
    })
    collapseAll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Shared.SCROLLBAR_RESERVE, 0)
    local expandAll = ns.UIKit.CreateButton(frame, {
        text = ns.L["Expand all"], height = 22,
        onClick = function() SetAll(nil) end,
    })
    expandAll:SetPoint("RIGHT", collapseAll, "LEFT", -6, 0)

    scrollbar = Shared.CreateScrollBar(frame, {
        orientation = "vertical",
        onScroll = function(n) offset = n; RenderRows() end,
    })
    scrollbar.track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -HDR_H)
    scrollbar.track:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, FOOTER_H)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        RenderRows()
    end)
    frame:SetScript("OnSizeChanged", function() view.Refresh() end)
    if Bus and Bus.Subscribe then
        local function OnBus()
            if frame:IsVisible() then view.Refresh() end
        end
        Bus.Subscribe("WeekliesChanged", OnBus)
        Bus.Subscribe("LockoutsChanged", OnBus)
        Bus.Subscribe("CharacterChanged", OnBus)
        Bus.Subscribe("CharacterDeleted", OnBus)
    end
    return view
end

Alts.Window.RegisterTab("weeklies", ns.L["Weeklies"], Builder,
    "Great Vault progress, Mythic+ rating, keystone, and saved instances per character.")
