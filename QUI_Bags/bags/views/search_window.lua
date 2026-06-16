-- luacheck: read globals IsModifiedClick HandleModifiedItemClick
---------------------------------------------------------------------------
-- Bags views: the search-everywhere window. One chassis shell whose header
-- search box IS the query input (0.15s debounce → Everywhere.Query →
-- render); the body is a pooled-row list inside a hand-rolled ScrollFrame
-- (house idiom: damage_meter's row viewport / QUI_Options' plain
-- ScrollFrame + wheel-clamp — Blizzard scroll templates stay out of QUI
-- chrome). Rows are informational: icon + quality-colored name + owner
-- breakdown + total, with the full item tooltip on hover
-- (GameTooltip:SetItemByID — the Mainline FrameXML OnEnter idiom;
-- SetHyperlink(entry link) is the fallback when the ID is somehow absent).
-- Results are capped by the query core; the footer shows "+N more" instead
-- of silently truncating.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local SearchWindow = {}
Bags.SearchWindow = SearchWindow

local CONTENT_W = 460
local CONTENT_H = 384           -- 16 rows of 24
local ROW_H = 24
local ICON_PAD = 2
local NAME_W = 170              -- fixed name column; overflow truncates
local SCROLLBAR_W = 6           -- house convention (framework dropdown scroll)
local WHEEL_STEP = ROW_H * 3
local DEBOUNCE = 0.15

local win                       -- chassis window (lazy)
local rows = {}                 -- pooled row frames (scroll-child children)
local queryText = ""
local searchTimer = nil

---------------------------------------------------------------------------
-- Pure: row-text assembly (exported for the headless test)
---------------------------------------------------------------------------

--- Display label for a summaries-dialect owner key: characters keep their
--- "Name-Realm" key, the warband gets a friendly constant, guild keys drop
--- the registry prefix and gain chat-style brackets.
function SearchWindow.OwnerLabel(ownerKey)
    if ownerKey == Bags.Summaries.WARBAND_OWNER then return ns.L["Warband"] end
    local prefix = Bags.Summaries.GUILD_PREFIX
    if ownerKey:sub(1, #prefix) == prefix then
        return "<" .. ownerKey:sub(#prefix + 1) .. ">"
    end
    return ownerKey
end

--- One-line owner summary from a result's owners array: per-owner sums
--- (the per-location split would read as duplicate owners on one line),
--- largest first, "Owner: n" comma-joined. The FontString truncates the
--- tail when the line outgrows its column.
function SearchWindow.BuildOwnersLine(owners)
    local sums, order = {}, {}
    for _, o in ipairs(owners or {}) do
        if sums[o.ownerKey] == nil then
            sums[o.ownerKey] = 0
            order[#order + 1] = o.ownerKey
        end
        sums[o.ownerKey] = sums[o.ownerKey] + o.count
    end
    table.sort(order, function(a, b)
        if sums[a] ~= sums[b] then return sums[a] > sums[b] end
        return a < b
    end)
    local parts = {}
    for _, key in ipairs(order) do
        parts[#parts + 1] = SearchWindow.OwnerLabel(key) .. ": " .. sums[key]
    end
    return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Frame construction (lazy)
---------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    -- Button HIGHLIGHT layer: shown by the widget on hover, no scripts needed
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\WHITE8x8")
    hl:SetVertexColor(1, 1, 1, 0.06)
    UIKit.DisablePixelSnap(hl)

    row._icon = row:CreateTexture(nil, "ARTWORK")
    row._icon:SetSize(ROW_H - ICON_PAD * 2, ROW_H - ICON_PAD * 2)
    row._icon:SetPoint("LEFT", ICON_PAD, 0)

    local fontPath = Helpers.GetGeneralFont() or STANDARD_TEXT_FONT
    row._name = row:CreateFontString(nil, "ARTWORK")
    CJKFont(row._name, fontPath, 12, "OUTLINE")
    row._name:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
    row._name:SetSize(NAME_W, ROW_H)
    row._name:SetJustifyH("LEFT")
    row._name:SetWordWrap(false)

    row._total = row:CreateFontString(nil, "ARTWORK")
    CJKFont(row._total, fontPath, 12, "OUTLINE")
    row._total:SetPoint("RIGHT", -4, 0)

    row._owners = row:CreateFontString(nil, "ARTWORK")
    CJKFont(row._owners, fontPath, 11, "OUTLINE")
    row._owners:SetTextColor(0.65, 0.65, 0.65)
    row._owners:SetPoint("LEFT", row._name, "RIGHT", 8, 0)
    row._owners:SetPoint("RIGHT", row._total, "LEFT", -8, 0)
    row._owners:SetHeight(ROW_H)
    row._owners:SetJustifyH("RIGHT")
    row._owners:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        -- Shared helper: battlepet links route to BattlePetToolTip_ShowLink
        -- (and outrank the cage itemID); plain items keep the SetItemByID-
        -- first idiom.
        Bags.ItemButtons.ShowItemTooltip(self, self._link, self._itemID)
    end)
    row:SetScript("OnLeave", function() Bags.ItemButtons.HideItemTooltip() end)
    row:SetScript("OnClick", function(self)
        -- Navigate to the best placement (ResolveTarget priority): open the
        -- owning window, auto-select its tab, pulse the item. Chat-link
        -- modifier keeps Blizzard semantics and outranks navigation.
        if IsModifiedClick and IsModifiedClick("CHATLINK") and self._link
            and HandleModifiedItemClick then
            HandleModifiedItemClick(self._link)
            return
        end
        local target = self._item
            and Bags.Everywhere.ResolveTarget(self._item, Bags.Store.GetCurrentCharacterKey())
        if not target then return end
        if target.window == "bags" then
            Bags.BagWindow.FocusItem(self._itemID, target.ownerKey)
        elseif target.window == "bank" then
            Bags.BankWindow.FocusItem(self._itemID, target.ownerKey, { warband = target.warband })
        elseif target.window == "guild" then
            Bags.GuildWindow.FocusItem(self._itemID, target.guildKey)
        end
    end)
    return row
end

--- Clamp + apply a vertical scroll offset, then sync the display-only thumb
--- (auto-hidden while the content fits the viewport).
local function SetScroll(offset)
    local viewH = win._scroll:GetHeight()
    local contentH = win._scrollChild:GetHeight()
    local maxScroll = math.max(0, contentH - viewH)
    offset = math.max(0, math.min(maxScroll, offset))
    win._scroll:SetVerticalScroll(offset)
    local bar = win._scrollBar
    if maxScroll <= 0 or viewH <= 0 then
        bar:Hide()
        return
    end
    local trackH = bar:GetHeight()
    local thumbH = math.max(12, trackH * viewH / contentH)
    bar.thumb:SetHeight(thumbH)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0,
        -((trackH - thumbH) * (offset / maxScroll)))
    bar:Show()
end

local function EnsureWindow()
    if win then return win end
    win = Bags.Chassis.CreateWindow({
        name = "QUI_SearchEverywhere",
        title = ns.L["Search Everywhere"],
        getPosition = function()
            local s = GetSettings()
            return s and s.windows and s.windows.search or nil
        end,
        setPosition = function(point, x, y)
            local s = GetSettings()
            if s and s.windows and s.windows.search then
                s.windows.search.point, s.windows.search.x, s.windows.search.y =
                    point, x, y
            end
        end,
        onSearchChanged = function(text)
            queryText = text or ""
            -- debounce: query at most once per typing pause; 0.15s (vs the
            -- grids' 0.1s) because each keystroke here walks EVERY owner
            if searchTimer then searchTimer:Cancel() end
            searchTimer = C_Timer.NewTimer(DEBOUNCE, function()
                searchTimer = nil
                SearchWindow.Refresh()
            end)
        end,
        -- informational window: plain hide on X is exactly right (no live
        -- session, no opener to clear), so no onUserClose override
    })

    -- body: viewport + scroll child carrying the row pool
    local scroll = CreateFrame("ScrollFrame", nil, win._body)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        SetScroll((self:GetVerticalScroll() or 0) - delta * WHEEL_STEP)
    end)
    win._scroll = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1) -- real size assigned per render
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then child:SetWidth(w) end
    end)
    win._scrollChild = child

    -- display-only thumb (damage_meter / options-dropdown convention)
    local bar = CreateFrame("Frame", nil, win._body)
    bar:SetWidth(SCROLLBAR_W)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -1)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 1)
    bar:SetFrameLevel(scroll:GetFrameLevel() + 5)
    bar:Hide()
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SCROLLBAR_W)
    local sr, sg, sb = Helpers.GetSkinColors()
    thumb:SetColorTexture(sr, sg, sb, 0.5)
    UIKit.DisablePixelSnap(thumb)
    bar.thumb = thumb
    win._scrollBar = bar

    -- footer: result count / "+N more" / blank-query hint
    win._status = win._footer:CreateFontString(nil, "ARTWORK")
    win._status:SetPoint("LEFT", 8, 0)
    CJKFont(win._status, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
    win._status:SetTextColor(0.65, 0.65, 0.65)

    win:SetContentSize(CONTENT_W, CONTENT_H)
    win:ApplyPosition()
    return win
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function DressRow(row, item)
    row._itemID = item.itemID
    row._link = item.link
    row._item = item -- aggregated result (owners breakdown) for click navigation
    row._icon:SetTexture(item.icon or 134400) -- INV_Misc_QuestionMark fallback
    if item.name then
        local r, g, b = Bags.ItemButtons.GetQualityColor(item.quality or 1)
        row._name:SetText(item.name)
        row._name:SetTextColor(r, g, b)
    else
        -- details not loaded yet; the next refresh picks the name up
        row._name:SetText(ns.L["Item #"] .. item.itemID)
        row._name:SetTextColor(0.6, 0.6, 0.6)
    end
    row._total:SetText("\195\151" .. item.total) -- ×total
    row._owners:SetText(SearchWindow.BuildOwnersLine(item.owners))
end

function SearchWindow.Refresh()
    if not win or not win:IsShown() then return end
    local results = Bags.Everywhere.Query(queryText)
    -- thumb tracks the skin per refresh (sort-button/tab-strip contract);
    -- DisablePixelSnap must follow EVERY SetColorTexture or the quad can
    -- vanish position-dependently
    local sr, sg, sb = Helpers.GetSkinColors()
    win._scrollBar.thumb:SetColorTexture(sr, sg, sb, 0.5)
    UIKit.DisablePixelSnap(win._scrollBar.thumb)
    for _, row in ipairs(rows) do row:Hide() end
    for i, item in ipairs(results) do
        local row = rows[i]
        if not row then
            row = CreateRow(win._scrollChild)
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win._scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", win._scrollChild, "TOPRIGHT", -SCROLLBAR_W - 2, -(i - 1) * ROW_H)
        DressRow(row, item)
        row:Show()
    end
    win._scrollChild:SetHeight(math.max(#results * ROW_H, 1))
    SetScroll(0) -- a new result set always starts at the top
    if results.blank then
        win._status:SetText(ns.L["Type to search every cached bag, bank, mailbox, auction and guild vault."])
    elseif results.truncated then
        win._status:SetText(#results .. " " .. ns.L["shown"] .. ", +" .. results.truncated
            .. " " .. ns.L["more"] .. " \226\128\148 " .. ns.L["refine the query"]) -- — em dash
    else
        win._status:SetText(#results .. (#results == 1 and " " .. ns.L["match"] or " " .. ns.L["matches"]))
    end
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------

function SearchWindow.Show()
    EnsureWindow()
    win:Show()
    -- a fresh look always re-queries: the cache may have moved since the
    -- last render, and the box keeps its text across closes
    SearchWindow.Refresh()
    win._searchBox:SetFocus()
end

function SearchWindow.Hide()
    if win and win:IsShown() then win:Hide() end
end

function SearchWindow.Toggle()
    if win and win:IsShown() then SearchWindow.Hide() else SearchWindow.Show() end
end

function SearchWindow.IsShown()
    return win ~= nil and win:IsShown()
end

--- Profile switched while the module stays enabled: re-anchor + re-render.
function SearchWindow.OnProfileChanged()
    if not win then return end
    win:ApplyPosition()
    if win:IsShown() then SearchWindow.Refresh() end
end
