---------------------------------------------------------------------------
-- Alts search tab. Cross-character item search over the storage summaries
-- inverted index (Summaries.IterateOwnerItems per owner). An EditBox at the
-- top (chassis search-box styling) drives an on-demand query: ≥2 chars
-- searches every owner (characters + warband + guilds), case-insensitive
-- plain-substring against resolved item names; results render in the roster
-- pool/wheel scaffold below.
--
-- On-demand, NOT bus-driven: a stale result list simply refreshes on the
-- next keystroke (the index it reads is itself lazily rebuilt). Item names
-- may be uncached at query time (C_Item.GetItemInfo nil) — misses trigger
-- one delayed re-run after RequestLoadItemDataByID populates the cache.
--
-- Pure helpers exported on Alts.SearchView (tested headless):
--   MatchName(name, query)      → bool (case-insensitive plain find)
--   OwnerLabel(ownerKey)        → { label, isChar, guild? }, kind
--   LocationsText(byLocation)   → "bags 3, bank 5" (alphabetical)
--   SortResults(results)        → in-place name-then-owner-label sort
-- Frame parts are NOT tested (no WoW frame API headless).
---------------------------------------------------------------------------
-- luacheck: read globals ITEM_QUALITY_COLORS RAID_CLASS_COLORS ColorManager
local ADDON_NAME, ns = ...
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local SearchView = {}
Alts.SearchView = SearchView

local ROW_H, SEARCH_H, FOOTER_H = 22, 24, 22
local CELL_PAD = 6
local RESULT_CAP = 200
local MIN_CHARS = 2

local NAME_W, OWNER_W = 280, 160

-- Owner-key constants. Resolved from the live Summaries table when present
-- (the data layer owns the canonical values); literal fallbacks keep the
-- pure helpers working under the headless test's Summaries stub.
local Summaries = ns.Storage and ns.Storage.Summaries
local WARBAND_OWNER = (Summaries and Summaries.WARBAND_OWNER) or ":warband"
local GUILD_PREFIX = (Summaries and Summaries.GUILD_PREFIX) or ":guild:"

---------------------------------------------------------------------------
-- Pure helpers (tested headless).
---------------------------------------------------------------------------

--- Case-insensitive plain-substring match. nil name → false. `query` may
--- be any case; both sides are lowercased and matched with a PLAIN find
--- (Lua-pattern magic in the query is literal, like the bag grids).
function SearchView.MatchName(name, query)
    if not name or not query then return false end
    return name:lower():find(query:lower(), 1, true) ~= nil
end

--- Owner display label for a summaries owner key. → table, kind:
---   character key "Name-Realm" → { label = "Name", isChar = true }, "char"
---   WARBAND_OWNER               → { label = "Warband" }, "warband"
---   GUILD_PREFIX..key           → { label = "Guild: Name", guild = "Name" }, "guild"
--- The character label is the name part (before the first "-"); the caller
--- class-colors it from the record (the key carries no class).
function SearchView.OwnerLabel(ownerKey)
    if ownerKey == WARBAND_OWNER then
        return { label = "Warband" }, "warband"
    end
    if ownerKey:sub(1, #GUILD_PREFIX) == GUILD_PREFIX then
        local guildKey = ownerKey:sub(#GUILD_PREFIX + 1)
        -- name part before the first "-" of the "GuildName-Realm" store key
        local namePart = guildKey:match("^(.-)%-") or guildKey
        return { label = "Guild: " .. namePart, guild = namePart }, "guild"
    end
    local namePart = ownerKey:match("^(.-)%-") or ownerKey
    return { label = namePart, isChar = true }, "char"
end

--- Compact locations summary: "bags 3, bank 5". Location keys taken as-is
--- from the index, sorted alphabetically. Empty/nil → "".
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

--- In-place sort: item name asc, then owner label asc. Nil names sort last;
--- ties broken by itemID for stability.
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

---------------------------------------------------------------------------
-- Frame parts (no headless test).
---------------------------------------------------------------------------

local function GeneralFont()
    return (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont())
        or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function GeneralOutline()
    return (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline())
        or ""
end

local function MakeFS(parent, size)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    fs:SetFont(GeneralFont(), size or 11, GeneralOutline())
    fs:SetWordWrap(false)
    return fs
end

local function ClassColor(classToken)
    local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

--- Quality color for an item name. Prefers the 12.0 ColorManager path
--- (honors quality-color accessibility overrides), then the legacy global,
--- then white.
local function QualityColor(quality)
    -- shape proven by QUI_Bags item_buttons.GetQualityColor: the return
    -- carries .r/.g/.b directly (both ColorManager and the legacy global)
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

local nameCache = {}     -- [itemID] = { name, quality } (session memo)
local loadRequested = {} -- [itemID] = true (RequestLoadItemDataByID issued)

local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Summ  = ns.Storage and ns.Storage.Summaries

    local frame = CreateFrame("Frame", nil, parent)

    local view    = { frame = frame }
    local offset  = 0
    local results = {}     -- last result rows
    local rowPool = {}
    local lastQuery = ""   -- last dispatched lowercased query

    local function VisibleRows()
        local h = frame:GetHeight() or 0
        local usable = h - SEARCH_H - FOOTER_H
        if usable < ROW_H then return 1 end
        return math.max(1, math.floor(usable / ROW_H))
    end

    ---- search box (top, full width) -------------------------------------
    local search = CreateFrame("EditBox", nil, frame)
    search:SetHeight(SEARCH_H)
    search:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    search:SetAutoFocus(false)
    search:SetTextInsets(6, 6, 0, 0)
    search:SetFont(GeneralFont(), 12, GeneralOutline())
    local searchBg = search:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    searchBg:SetVertexColor(0, 0, 0, 0.35)
    UIKit.DisablePixelSnap(searchBg)
    UIKit.CreateBorderLines(search)
    local placeholder = search:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", search, "LEFT", 7, 0)
    placeholder:SetFont(GeneralFont(), 12, GeneralOutline())
    placeholder:SetTextColor(0.55, 0.55, 0.55, 0.9)
    placeholder:SetText("Search all characters…")
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

    ---- row pool ----------------------------------------------------------
    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = CreateFrame("Button", nil, frame)
        r:SetHeight(ROW_H)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(1, 1, 1, 0)
        r._bg = bg
        r._name  = MakeFS(r, 11)
        r._owner = MakeFS(r, 11)
        r._locs  = MakeFS(r, 11)
        r:SetScript("OnEnter", function(self) self._bg:SetVertexColor(1, 1, 1, 0.08) end)
        r:SetScript("OnLeave", function(self) self._bg:SetVertexColor(1, 1, 1, 0) end)
        rowPool[i] = r
        return r
    end

    ---- query core --------------------------------------------------------
    -- Walks every owner's lazily-rebuilt index, matches resolved item names,
    -- and builds result rows. Returns (rows, missCount): missCount > 0 means
    -- some names were uncached and a delayed re-run is worthwhile.
    local function RunQuery(query)
        local rows, missCount = {}, 0
        if not (Store and Summ and Summ.IterateOwnerItems) then return rows, 0 end

        local owners = {}
        local labelCache = {}   -- ownerKey → { table, kind }
        local classCache = {}   -- ownerKey → classToken (chars only)
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
            local lc = labelCache[ownerKey]
            if not lc then
                local lbl, kind = SearchView.OwnerLabel(ownerKey)
                lc = { lbl = lbl, kind = kind }
                labelCache[ownerKey] = lc
            end
            Summ.IterateOwnerItems(ownerKey, function(itemID, byLocation)
                -- session memo: a resolved name never changes, and a cache
                -- miss only requests the data load ONCE per session — without
                -- this every keystroke re-sweeps and re-requests all misses
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
                    return -- unresolved name can't match; delayed re-run retries
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

    ---- render -------------------------------------------------------------
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

    -- footer
    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    ---- search dispatch ---------------------------------------------------
    -- Re-run after uncached names load. ONE timer per dispatch; the closure
    -- re-checks the frame is still visible and the query text is unchanged
    -- so a stale timer from an old keystroke is a no-op.
    local function ScheduleRerun(query)
        if not (C_Timer and C_Timer.After) then return end
        C_Timer.After(0.7, function()
            if not frame:IsVisible() then return end
            if lastQuery ~= query then return end
            view.DoSearch(query, true)
        end)
    end

    -- skipRerun guards against an endless reschedule loop on perpetually
    -- uncached items: the delayed pass renders what it has and stops.
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
        -- on-demand: re-run the current query (index/names may have changed)
        if #lastQuery >= MIN_CHARS then
            view.DoSearch(lastQuery, true)
        else
            RenderRows()
        end
    end

    -- mouse-wheel scroll
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #results - VisibleRows())
        offset = offset - delta
        if offset < 0 then offset = 0 end
        if offset > maxOff then offset = maxOff end
        RenderRows()
    end)

    -- No bus subscriptions: search is on-demand. A stale result list refreshes
    -- on the next keystroke; the summaries index it reads is itself lazily
    -- rebuilt, so the next query always sees current data.

    return view
end

Alts.Window.RegisterTab("search", "Search", Builder)
