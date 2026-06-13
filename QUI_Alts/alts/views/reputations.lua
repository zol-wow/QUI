---------------------------------------------------------------------------
-- Alts reputations tab. ONE selected character at a time; left side is a
-- flat virtualized list of ALL faction IDs seen across ALL characters so you
-- can see gaps. Group-label rows (gold text) precede their factions; groups
-- sorted alphabetically with "Other" last; factions within a group sorted by
-- name. Footer: "%d factions". Wheel scroll + row pool exactly like the
-- roster/professions tabs. Rows honor alts.reputationFilter ([id] = false
-- hides, absent = visible); the top-right Filter button opens the shared
-- searchable checkbox popup (filter_popup.lua: search box + Select all/
-- Deselect all on matched rows, gold group header rows) editing that map
-- (the options panel's "Reputations Tab" section shares the key).
--
-- Pure helpers are exported on Alts.ReputationsView for headless tests:
--   FormatEntry(entry)  → value-cell string
--   BuildDisplayRows(characters, names, groups, filter) → flat row list
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
local UIKit = ns.UIKit

local ReputationsView = {}
Alts.ReputationsView = ReputationsView

local ROW_H, FOOTER_H = 22, 22
local CELL_PAD = 6

local NAME_W = 240   -- faction name column width

local STANDING_LABELS = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

---------------------------------------------------------------------------
-- Pure helpers (tested headless).
---------------------------------------------------------------------------

--- Format the value cell for a single faction entry (or nil).
--- entry nil → "—"; renownLevel present → "Renown %d (%d/%d)";
--- paragonValue present → "Paragon %d/%d%s" (see modulo comment below);
--- else → "%s %d/%d" or just the label when ceiling <= floor;
--- accountWide entries get a " (account)" suffix.
function ReputationsView.FormatEntry(entry)
    if not entry then return "—" end

    local suffix = entry.accountWide and " (account)" or ""
    local text

    if entry.renownLevel then
        -- Major factions: show renown progress
        local earned    = entry.renownEarned    or 0
        local threshold = entry.renownThreshold or 0
        text = string.format("Renown %d (%d/%d)", entry.renownLevel, earned, threshold)

    elseif entry.paragonValue then
        -- Paragon factions: paragonValue is a running total that keeps
        -- accumulating past the threshold.  Display the current cycle's
        -- progress by taking the remainder so the bar resets each cycle.
        -- paragonThreshold > 0 guard prevents divide-by-zero.
        local shown
        if entry.paragonThreshold and entry.paragonThreshold > 0 then
            shown = entry.paragonValue % entry.paragonThreshold  -- modulo for cycle display
        else
            shown = entry.paragonValue
        end
        local threshold = entry.paragonThreshold or 0
        local pendingSuffix = entry.paragonPending and " !" or ""
        text = string.format("Paragon %d/%d%s", shown, threshold, pendingSuffix)

    else
        -- Standard standing
        local standing = entry.standing or 0
        local label = STANDING_LABELS[standing] or ("Standing " .. standing)
        local floor   = entry.floor   or 0
        local ceiling = entry.ceiling or 0
        if ceiling <= floor then
            -- Capped / exalted: no progress fraction
            text = label
        else
            local progress = (entry.value or 0) - floor
            local range    = ceiling - floor
            text = string.format("%s %d/%d", label, progress, range)
        end
    end

    return text .. suffix
end

--- Build the flat display-row list from the union of all factionIDs across
--- all characters' reputations. Returns ordered array of:
---   { kind = "group",   label = groupName }
---   { kind = "faction", label = factionName, factionID = id }
--- Groups are sorted alphabetically; "Other" (nil group) is last.
--- Factions within each group are sorted by name.
---
--- characters: { [key] = rec, ... } (any value shape; only rec.reputations used)
--- names:      [factionID] = name  (or nil → "Faction "..id)
--- groups:     [factionID] = groupLabel (or nil → "Other")
--- filter:     optional visibility map; [id] == false hides that faction
---             (alts.reputationFilter shape — absent/true = visible). Groups
---             whose every faction is hidden lose their header row too.
function ReputationsView.BuildDisplayRows(characters, names, groups, filter)
    names  = names  or {}
    groups = groups or {}

    -- 1. Collect union of all factionIDs across all characters.
    local seen = {}
    for _, rec in pairs(characters or {}) do
        local reps = rec and rec.reputations
        if reps then
            for id in pairs(reps) do
                seen[id] = true
            end
        end
    end

    -- 2. Bucket factionIDs by their group label; record unique group labels.
    --    Hidden factions (filter[id] == false) are skipped here, so groups
    --    whose every faction is hidden never get a header row.
    local groupBuckets = {}  -- { [groupLabel] = { factionID, ... } }
    local groupSet     = {}  -- unique group labels
    for id in pairs(seen) do
        if not (filter and filter[id] == false) then
            local g = groups[id] or "Other"
            if not groupBuckets[g] then
                groupBuckets[g] = {}
                groupSet[#groupSet + 1] = g
            end
            local bucket = groupBuckets[g]
            bucket[#bucket + 1] = id
        end
    end

    -- 3. Sort group labels alphabetically, "Other" forced to the end.
    table.sort(groupSet, function(a, b)
        if a == "Other" then return false end
        if b == "Other" then return true  end
        return a < b
    end)

    -- 4. Within each group sort factions by display name.
    for _, g in ipairs(groupSet) do
        local bucket = groupBuckets[g]
        table.sort(bucket, function(a, b)
            local na = names[a] or ("Faction " .. a)
            local nb = names[b] or ("Faction " .. b)
            return na < nb
        end)
    end

    -- 5. Flatten into the display row list.
    local rows = {}
    for _, g in ipairs(groupSet) do
        rows[#rows + 1] = { kind = "group", label = g }
        for _, id in ipairs(groupBuckets[g]) do
            local name = names[id] or ("Faction " .. id)
            rows[#rows + 1] = { kind = "faction", label = name, factionID = id }
        end
    end

    return rows
end

---------------------------------------------------------------------------
-- Frame parts (no headless test).
---------------------------------------------------------------------------





local function Builder(parent)
    local Store = ns.Storage and ns.Storage.Store
    local Bus   = ns.Storage and ns.Storage.Bus

    local frame = CreateFrame("Frame", nil, parent)

    local view       = { frame = frame }
    local offset     = 0
    local rows       = {}   -- flat display-row list (group + faction rows)
    local rowPool    = {}
    local selectedKey = nil  -- currently selected character key

    -- total faction count (for footer)
    local factionCount = 0

    -- cached per-Refresh data
    local cachedChars    = {}  -- { [key] = rec }
    local cachedNames    = {}
    local cachedGroups   = {}

    local function VisibleRows()
        local h = frame:GetHeight() or 0
        local usable = h - FOOTER_H
        if usable < ROW_H then return 1 end
        return math.max(1, math.floor(usable / ROW_H))
    end

    -- footer
    local footer = MakeFS(frame, 11)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CELL_PAD, 4)
    footer:SetTextColor(0.8, 0.8, 0.8)

    ---- character selector (top-left) ---------------------------------------
    -- Styled like the settings-form dropdown (GUI:CreateFormDropdown chrome):
    -- faint bg, 1px white-0.2 border brightening on hover, chevron caret.
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
        -- Gather available character keys sorted by name
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
                    view.Refresh() -- full re-render joins the new selection
                end)
            end
        end)
    end)

    ---- filter button (top-right; selector chrome) --------------------------
    -- Edits alts.reputationFilter in place ([id] = false hides, absent
    -- shows); opens the shared searchable popup attached below. The
    -- options panel's "Reputations Tab" section writes the same key.
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
    filterLabel:SetText("Filter")
    filterLabel:SetTextColor(0.9, 0.9, 0.9)

    ---- filter popup (shared searchable checkbox popup; filter_popup.lua) ---
    -- Group rows become gold header rows inside the popup list; searching a
    -- group name keeps its whole group (FilterPopup.MatchRows).
    Alts.FilterPopup.Attach({
        tabFrame = frame,
        anchorButton = filterBtn,
        getRows = function()
            -- UNFILTERED rows so hidden entries stay listed (re-checkable)
            local popupRows = {}
            for _, e in ipairs(ReputationsView.BuildDisplayRows(cachedChars, cachedNames, cachedGroups, nil)) do
                if e.kind == "group" then
                    popupRows[#popupRows + 1] = { label = e.label, header = true }
                else
                    popupRows[#popupRows + 1] = { id = e.factionID, label = e.label }
                end
            end
            return popupRows
        end,
        isChecked = function(id)
            local s = Alts.GetSettings and Alts.GetSettings()
            local filter = s and s.reputationFilter
            return not (filter and filter[id] == false)
        end,
        setChecked = function(id, checked)
            local s = Alts.GetSettings and Alts.GetSettings()
            if not s then return end
            if not s.reputationFilter then s.reputationFilter = {} end
            if checked then s.reputationFilter[id] = nil
            else s.reputationFilter[id] = false end
        end,
        onChanged = function() view.Refresh() end,
    })

    ---- row pool (one Button per visible slot) -----------------------------
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
        r._name  = MakeFS(r, 11)   -- left cell: group label or faction name
        r._value = MakeFS(r, 11)   -- right cell: value or empty for groups
        r:SetScript("OnEnter", function(self)
            if self._isGroup then return end
            self._bg:SetVertexColor(1, 1, 1, 0.08)
            local row = self._row
            if not (row and row.factionID) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.label, 1, 1, 1)
            GameTooltip:AddLine("Right-click to untrack", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(self)
            self._bg:SetVertexColor(1, 1, 1, 0)
            GameTooltip:Hide()
        end)
        -- Right-click hides the faction (alts.reputationFilter[id] = false);
        -- re-show via the Filter button. Matches the popup's setChecked.
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then return end
            local row = self._row
            if self._isGroup or not (row and row.factionID) then return end
            local s = Alts.GetSettings and Alts.GetSettings()
            if not s then return end
            if not s.reputationFilter then s.reputationFilter = {} end
            s.reputationFilter[row.factionID] = false
            GameTooltip:Hide()
            view.Refresh()
        end)
        rowPool[i] = r
        return r
    end

    ---- render -------------------------------------------------------------
    local function RenderRows()
        local visible = VisibleRows()
        local maxOff  = math.max(0, #rows - visible)
        if offset > maxOff then offset = maxOff end
        if offset < 0 then offset = 0 end

        -- selector is 22px tall at top; rows start 28px below TOPLEFT
        local topY = -28

        local selRec = selectedKey and cachedChars[selectedKey]

        for i = 1, visible do
            local r   = GetRow(i)
            local row = rows[offset + i]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, topY - (i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, topY - (i - 1) * ROW_H)

            if not row then
                r._row = nil
                r:Hide()
            elseif row.kind == "group" then
                r._row     = row
                r._isGroup = true
                r._bg:SetVertexColor(1, 1, 1, 0)
                r._name:ClearAllPoints()
                r._name:SetPoint("LEFT", r, "LEFT", CELL_PAD, 0)
                r._name:SetWidth(frame:GetWidth() - CELL_PAD * 2)
                r._name:SetText(row.label)
                r._name:SetTextColor(1, 0.82, 0)
                r._name:Show()
                r._value:Hide()
                r:Show()
            else
                -- faction row
                r._row     = row
                r._isGroup = false

                r._name:ClearAllPoints()
                r._name:SetPoint("LEFT", r, "LEFT", CELL_PAD * 2, 0)
                r._name:SetWidth(NAME_W - CELL_PAD * 2)
                r._name:SetText(row.label)
                r._name:SetTextColor(0.9, 0.9, 0.9)
                r._name:Show()

                local entry = selRec and selRec.reputations and selRec.reputations[row.factionID]
                local valueText = ReputationsView.FormatEntry(entry)
                local isGray = (entry == nil)
                r._value:ClearAllPoints()
                r._value:SetPoint("LEFT", r, "LEFT", NAME_W + CELL_PAD, 0)
                r._value:SetWidth((frame:GetWidth() or 0) - NAME_W - CELL_PAD * 2)
                r._value:SetText(valueText)
                if isGray then
                    r._value:SetTextColor(0.5, 0.5, 0.5)
                else
                    r._value:SetTextColor(0.9, 0.9, 0.9)
                end
                r._value:Show()
                r:Show()
            end
        end
        -- hide surplus rows
        for i = visible + 1, #rowPool do
            rowPool[i]._row = nil
            rowPool[i]:Hide()
        end
    end

    -- Choose the best default key: current character first, then first cached.
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

        -- Rebuild character cache
        cachedChars = {}
        if Store.ListCharacters and Store.GetCharacter then
            for _, key in ipairs(Store.ListCharacters()) do
                local rec = Store.GetCharacter(key)
                if rec then cachedChars[key] = rec end
            end
        end

        cachedNames  = (Store.GetFactionNames  and Store.GetFactionNames())  or {}
        cachedGroups = (Store.GetFactionGroups and Store.GetFactionGroups()) or {}

        -- Validate or pick selected key
        if not selectedKey or not cachedChars[selectedKey] then
            selectedKey = ChooseDefaultKey(cachedChars)
        end

        local filter = (Alts.GetSettings and Alts.GetSettings() or {}).reputationFilter
        rows = ReputationsView.BuildDisplayRows(cachedChars, cachedNames, cachedGroups, filter)

        -- Count faction rows for footer
        factionCount = 0
        for _, r in ipairs(rows) do
            if r.kind == "faction" then factionCount = factionCount + 1 end
        end

        -- unfiltered count just for the footer's hidden tally
        local total = 0
        for _, r in ipairs(ReputationsView.BuildDisplayRows(cachedChars, cachedNames, cachedGroups, nil)) do
            if r.kind == "faction" then total = total + 1 end
        end

        UpdateSelectorLabel()
        RenderRows()
        local hidden = total - factionCount
        if hidden > 0 then
            footer:SetText(string.format("%d factions (%d hidden)", factionCount, hidden))
        else
            footer:SetText(string.format("%d factions", factionCount))
        end
    end

    -- mouse-wheel scroll
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #rows - VisibleRows())
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
        Bus.Subscribe("ReputationsChanged", OnBus)
        Bus.Subscribe("CharacterDeleted",   function()
            -- selected character may have been deleted; let Refresh re-pick
            if frame:IsVisible() then view.Refresh() end
        end)
    end

    return view
end

Alts.Window.RegisterTab("reputations", "Reputations", Builder,
    "Faction standings across your characters, including renown and paragon progress.")
