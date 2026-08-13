local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local ClassColor = Shared.ClassColor
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local RD = Alts.RosterData

local WeekliesView = {}
Alts.WeekliesView = WeekliesView

local ROW_H, FOOTER_H = 22, 22
local CELL_PAD = 6
local LOCKOUT_INDENT = 24

local NAME_W    = 160
local RATING_W  = 60
local KEYSTONE_W = 180

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

function WeekliesView.VaultSummary(weeklies)
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
        parts[#parts + 1] = string.format("%s %d/%d",
            VaultTypeLabel(t), completed[t], totals[t])
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

function WeekliesView.BuildDisplayRows(characters)
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
    for _, entry in ipairs(sorted) do
        rows[#rows + 1] = {
            kind     = "char",
            key      = entry.key,
            name     = entry.name,
            class    = entry.class,
            weeklies = entry.weeklies,
        }
        local lockouts = entry.lockouts
        if lockouts then
            for _, lo in ipairs(lockouts) do
                rows[#rows + 1] = { kind = "lockout", lockout = lo }
            end
        end
    end

    return rows
end

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus   = ns.Storage and ns.Storage.Bus

    local frame = CreateFrame("Frame", nil, parent)

    local view    = { frame = frame }
    local offset  = 0
    local scrollbar
    local rows    = {}
    local rowPool = {}
    local charCount = 0

    local function VisibleRows()
        local h = frame:GetHeight() or 0
        local usable = h - FOOTER_H
        if usable < ROW_H then return 1 end
        return math.max(1, math.floor(usable / ROW_H))
    end

    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = Shared.CreateRow(frame, { height = ROW_H })
        r._name    = MakeFS(r, 11)
        r._rating  = MakeFS(r, 11)
        r._keystone = MakeFS(r, 11)
        r._vault   = MakeFS(r, 11)
        r._lockout = MakeFS(r, 11)
        rowPool[i] = r
        return r
    end

    local function RenderRows()
        local visible = VisibleRows()
        local maxOff  = math.max(0, #rows - visible)
        if offset > maxOff then offset = maxOff end
        if offset < 0 then offset = 0 end

        for i = 1, visible do
            local r   = GetRow(i)
            local row = rows[offset + i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -(i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Shared.SCROLLBAR_RESERVE, -(i - 1) * ROW_H)

            if not row then
                r._row = nil
                r:Hide()
            elseif row.kind == "char" then
                r._row = row
                r._name:ClearAllPoints()
                r._name:SetPoint("LEFT", r, "LEFT", CELL_PAD, 0)
                r._name:SetWidth(NAME_W - CELL_PAD * 2)
                r._name:SetText(row.name or row.key or "?")
                local cr, cg, cb = ClassColor(row.class)
                r._name:SetTextColor(cr, cg, cb)
                r._name:Show()

                local w = row.weeklies
                local rating = w and w.mplusRating
                r._rating:ClearAllPoints()
                r._rating:SetPoint("LEFT", r, "LEFT", NAME_W + CELL_PAD, 0)
                r._rating:SetWidth(RATING_W - CELL_PAD * 2)
                if rating and rating > 0 then
                    r._rating:SetText(string.format("%d", rating))
                else
                    r._rating:SetText("—")
                end
                r._rating:SetTextColor(0.9, 0.9, 0.9)
                r._rating:Show()

                r._keystone:ClearAllPoints()
                r._keystone:SetPoint("LEFT", r, "LEFT", NAME_W + RATING_W + CELL_PAD, 0)
                r._keystone:SetWidth(KEYSTONE_W - CELL_PAD * 2)
                r._keystone:SetText(WeekliesView.KeystoneText(w))
                r._keystone:SetTextColor(0.9, 0.9, 0.9)
                r._keystone:Show()

                r._vault:ClearAllPoints()
                r._vault:SetPoint("LEFT", r, "LEFT", NAME_W + RATING_W + KEYSTONE_W + CELL_PAD, 0)
                r._vault:SetPoint("RIGHT", r, "RIGHT", -CELL_PAD, 0)
                r._vault:SetText(WeekliesView.VaultSummary(w))
                r._vault:SetTextColor(0.9, 0.9, 0.9)
                r._vault:Show()

                r._lockout:Hide()
                r:Show()
            else
                r._row = row
                r._name:Hide()
                r._rating:Hide()
                r._keystone:Hide()
                r._vault:Hide()

                r._lockout:ClearAllPoints()
                r._lockout:SetPoint("LEFT",  r, "LEFT",  LOCKOUT_INDENT + CELL_PAD, 0)
                r._lockout:SetPoint("RIGHT", r, "RIGHT", -CELL_PAD, 0)
                r._lockout:SetText(WeekliesView.LockoutLine(row.lockout, nil))
                r._lockout:SetTextColor(0.8, 0.8, 0.8)
                r._lockout:Show()

                r:Show()
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

        local chars = {}
        charCount = 0
        if Store.ListCharacters and Store.GetCharacter then
            for _, key in ipairs(Store.ListCharacters()) do
                local rec = Store.GetCharacter(key)
                if rec then
                    chars[key] = rec
                    charCount = charCount + 1
                end
            end
        end

        rows = WeekliesView.BuildDisplayRows(chars)

        RenderRows()
        footer:SetText(string.format("%d characters", charCount))
    end

    scrollbar = Shared.CreateScrollBar(frame, {
        orientation = "vertical",
        onScroll = function(n) offset = n; RenderRows() end,
    })
    scrollbar.track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, 0)
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
        Bus.Subscribe("WeekliesChanged",  OnBus)
        Bus.Subscribe("LockoutsChanged",  OnBus)
        Bus.Subscribe("CharacterChanged", OnBus)
        Bus.Subscribe("CharacterDeleted", OnBus)
    end

    return view
end

Alts.Window.RegisterTab("weeklies", ns.L["Weeklies"], Builder,
    "Great Vault progress, Mythic+ rating, keystone, and saved instances per character.")
