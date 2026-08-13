-- luacheck: read globals ITEM_QUALITY_COLORS RAID_CLASS_COLORS ColorManager
local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local ClassColor = Shared.ClassColor
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local SearchView = {}
Alts.SearchView = SearchView

local ROW_H, SEARCH_H, FOOTER_H = 22, 24, 22
local CELL_PAD = 6
local RESULT_CAP = 200
local MIN_CHARS = 2

local NAME_W, OWNER_W = 280, 160

local Summaries = ns.Storage and ns.Storage.Summaries
local WARBAND_OWNER = (Summaries and Summaries.WARBAND_OWNER) or ":warband"
local GUILD_PREFIX = (Summaries and Summaries.GUILD_PREFIX) or ":guild:"

function SearchView.MatchName(name, query)
    if not name or not query then return false end
    return name:lower():find(query:lower(), 1, true) ~= nil
end

function SearchView.OwnerLabel(ownerKey)
    if ownerKey == WARBAND_OWNER then
        return { label = ns.L["Warband"] }, "warband"
    end
    if ownerKey:sub(1, #GUILD_PREFIX) == GUILD_PREFIX then
        local guildKey = ownerKey:sub(#GUILD_PREFIX + 1)
        local namePart = guildKey:match("^(.-)%-") or guildKey
        return { label = ns.L["Guild: "] .. namePart, guild = namePart }, "guild"
    end
    local namePart = ownerKey:match("^(.-)%-") or ownerKey
    return { label = namePart, isChar = true }, "char"
end

function SearchView.LocationsText(byLocation)
    if not byLocation then return "" end
    local keys = {}
    for loc in pairs(byLocation) do keys[#keys + 1] = loc end
    table.sort(keys)
    local parts = {}
    for _, loc in ipairs(keys) do
        parts[#parts + 1] = string.format("%s %d", loc, byLocation[loc] or 0)
    end
    return table.concat(parts, ", ")
end

function SearchView.SortResults(results)
    table.sort(results, function(a, b)
        local an, bn = a.name, b.name
        if an ~= bn then
            if an == nil then return false end
            if bn == nil then return true end
            return an < bn
        end
        local al, bl = a.ownerLabel or "", b.ownerLabel or ""
        if al ~= bl then return al < bl end
        return (a.itemID or 0) < (b.itemID or 0)
    end)
end

local function QualityColor(quality)
    local c
    if quality and ColorManager and ColorManager.GetColorDataForItemQuality then
        c = ColorManager.GetColorDataForItemQuality(quality)
    end
    if not c then
        c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    end
    if c and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

local nameCache = {}
local loadRequested = {}

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Summ  = ns.Storage and ns.Storage.Summaries

    local frame = CreateFrame("Frame", nil, parent)

    local view    = { frame = frame }
    local offset  = 0
    local results = {}
    local rowPool = {}
    local lastQuery = ""

    local function VisibleRows()
        local h = frame:GetHeight() or 0
        local usable = h - SEARCH_H - FOOTER_H
        if usable < ROW_H then return 1 end
        return math.max(1, math.floor(usable / ROW_H))
    end

    local search = CreateFrame("EditBox", nil, frame)
    search:SetHeight(SEARCH_H)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    search:SetAutoFocus(false)
    search:SetTextInsets(6, 6, 0, 0)
    CJKFont(search, GeneralFont(), 12, GeneralOutline())
    local searchBg = search:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    searchBg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(searchBg)
    UIKit.CreateBorderLines(search)
    local placeholder = search:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", search, "LEFT", 7, 0)
    CJKFont(placeholder, GeneralFont(), 12, GeneralOutline())
    placeholder:SetTextColor(0.55, 0.55, 0.55, 0.9)
    placeholder:SetText(ns.L["Search all characters…"])
    search._placeholder = placeholder

    local function RefreshChrome()
        placeholder:SetShown(search:GetText() == "" and not search:HasFocus())
        local sr, sg, sb = Helpers.GetSkinColors()
        if search:HasFocus() then
            local QGUI = _G.QUI and _G.QUI.GUI
            local acc = QGUI and QGUI.Colors and QGUI.Colors.accent
            if acc then sr, sg, sb = acc[1], acc[2], acc[3] end
            UIKit.UpdateBorderLines(search, 1, sr, sg, sb, 0.9)
        else
            UIKit.UpdateBorderLines(search, 1, sr, sg, sb, 0.5)
        end
    end

    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = Shared.CreateRow(frame, { height = ROW_H })
        r._name  = MakeFS(r, 11)
        r._owner = MakeFS(r, 11)
        r._locs  = MakeFS(r, 11)
        rowPool[i] = r
        return r
    end

    local function RunQuery(query)
        local rows, missCount = {}, 0
        if not (Store and Summ and Summ.IterateOwnerItems) then return rows, 0 end

        local owners = {}
        local classCache = {}
        for _, key in ipairs(Store.ListCharacters()) do
            owners[#owners + 1] = key
            local rec = Store.GetCharacter(key)
            classCache[key] = rec and rec.details and rec.details.class
        end
        owners[#owners + 1] = WARBAND_OWNER
        if Store.ListGuilds then
            for _, gkey in ipairs(Store.ListGuilds()) do
                owners[#owners + 1] = GUILD_PREFIX .. gkey
            end
        end

        for _, ownerKey in ipairs(owners) do
            local lbl, kind = SearchView.OwnerLabel(ownerKey)
            local lc = { lbl = lbl, kind = kind }
            Summ.IterateOwnerItems(ownerKey, function(itemID, byLocation)
                local cached = nameCache[itemID]
                local name, quality
                if cached then
                    name, quality = cached[1], cached[2]
                else
                    local q
                    name, _, q = C_Item.GetItemInfo(itemID)
                    if name then
                        quality = q
                        nameCache[itemID] = { name, q }
                    end
                end
                if not name then
                    missCount = missCount + 1
                    if not loadRequested[itemID] then
                        loadRequested[itemID] = true
                        if C_Item.RequestLoadItemDataByID then
                            C_Item.RequestLoadItemDataByID(itemID)
                        end
                    end
                    return
                end
                if SearchView.MatchName(name, query) then
                    rows[#rows + 1] = {
                        itemID     = itemID,
                        name       = name,
                        quality    = quality,
                        ownerKey   = ownerKey,
                        ownerLabel = lc.lbl.label,
                        ownerClass = lc.kind == "char" and classCache[ownerKey] or nil,
                        locations  = byLocation,
                    }
                end
            end)
        end
        return rows, missCount
    end

    local truncated = 0
    local function RenderRows()
        local visible = VisibleRows()
        local maxOff  = math.max(0, #results - visible)
        if offset > maxOff then offset = maxOff end
        if offset < 0 then offset = 0 end

        for i = 1, visible do
            local r   = GetRow(i)
            local row = results[offset + i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -(SEARCH_H + 4 + (i - 1) * ROW_H))
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -(SEARCH_H + 4 + (i - 1) * ROW_H))
            if not row then
                r._row = nil
                r:Hide()
            else
                r._row = row
                r._name:ClearAllPoints()
                r._name:SetPoint("LEFT", r, "LEFT", CELL_PAD, 0)
                r._name:SetWidth(NAME_W - CELL_PAD * 2)
                r._name:SetText(row.name or "?")
                r._name:SetTextColor(QualityColor(row.quality))
                r._name:Show()

                r._owner:ClearAllPoints()
                r._owner:SetPoint("LEFT", r, "LEFT", NAME_W + CELL_PAD, 0)
                r._owner:SetWidth(OWNER_W - CELL_PAD * 2)
                r._owner:SetText(row.ownerLabel or "?")
                if row.ownerClass then
                    r._owner:SetTextColor(ClassColor(row.ownerClass))
                else
                    r._owner:SetTextColor(0.9, 0.9, 0.9)
                end
                r._owner:Show()

                r._locs:ClearAllPoints()
                r._locs:SetPoint("LEFT", r, "LEFT", NAME_W + OWNER_W + CELL_PAD, 0)
                r._locs:SetPoint("RIGHT", r, "RIGHT", -CELL_PAD, 0)
                r._locs:SetText(SearchView.LocationsText(row.locations))
                r._locs:SetTextColor(0.7, 0.7, 0.7)
                r._locs:Show()

                r:Show()
            end
        end
        for i = visible + 1, #rowPool do
            rowPool[i]._row = nil
            rowPool[i]:Hide()
        end
    end

    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    local function ScheduleRerun(query)
        if not (C_Timer and C_Timer.After) then return end
        C_Timer.After(0.7, function()
            if not frame:IsVisible() then return end
            if lastQuery ~= query then return end
            view.DoSearch(query, true)
        end)
    end

    function view.DoSearch(query, skipRerun)
        if not (Store and Store.IsInitialized and Store.IsInitialized()) then return end
        if #query < MIN_CHARS then
            results, truncated = {}, 0
            offset = 0
            RenderRows()
            footer:SetText("")
            return
        end
        local rows, missCount = RunQuery(query)
        SearchView.SortResults(rows)
        local total = #rows
        truncated = 0
        if total > RESULT_CAP then
            truncated = total - RESULT_CAP
            for i = total, RESULT_CAP + 1, -1 do rows[i] = nil end
        end
        results = rows
        offset = 0
        RenderRows()
        if truncated > 0 then
            footer:SetText(string.format("%d matches (showing %d)", total, RESULT_CAP))
        else
            footer:SetText(string.format("%d matches", total))
        end
        if missCount > 0 and not skipRerun then ScheduleRerun(query) end
    end

    search:SetScript("OnEditFocusGained", RefreshChrome)
    search:SetScript("OnEditFocusLost", RefreshChrome)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        RefreshChrome()
        if text == lastQuery then return end
        lastQuery = text
        view.DoSearch(text)
    end)

    function view.Refresh()
        RefreshChrome()
        if #lastQuery >= MIN_CHARS then
            view.DoSearch(lastQuery, true)
        else
            RenderRows()
        end
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #results - VisibleRows())
        offset = offset - delta
        if offset < 0 then offset = 0 end
        if offset > maxOff then offset = maxOff end
        RenderRows()
    end)

    return view
end

Alts.Window.RegisterTab("search", ns.L["Search"], Builder,
    "Find items across every cached character's bags, bank, mail, equipped gear, and the warband bank.")
