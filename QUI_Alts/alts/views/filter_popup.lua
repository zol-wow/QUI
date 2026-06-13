---------------------------------------------------------------------------
-- Alts shared filter popup: searchable checkbox list with Select all /
-- Deselect all, anchored under a tab's Filter button. Used by the
-- Currencies and Reputations tabs to edit their visibility-filter maps
-- (alts.currencyFilter / alts.reputationFilter: [id] = false hides).
--
-- FilterPopup.Attach(opts) wires a popup onto an anchor button:
--   opts.tabFrame     tab view frame; the popup is its child so it hides
--                     with the tab/window
--   opts.floating     true → parent to UIParent instead (TOOLTIP strata,
--                     above the FULLSCREEN_DIALOG+Toplevel settings window)
--                     and hide via a tabFrame OnHide hook. For anchors
--                     inside clipping scrollframes (settings panel) where a
--                     child popup would be cut off.
--   opts.anchorButton Filter button; OnClick is installed here (toggles)
--   opts.getRows()    → flat display rows { id, label, header? }; header
--                     rows (header = true, no id) render as gold non-
--                     clickable group labels. Pass the UNFILTERED list so
--                     hidden entries stay re-checkable.
--   opts.isChecked(id)        → current visibility
--   opts.setChecked(id, bool) → write the filter map
--   opts.onChanged()          → tab refresh after any write
--
-- Search narrows by label (FilterPopup.MatchRows); a matching group header
-- keeps its whole group. Select/Deselect all act on the MATCHED rows only.
--
-- Pure helper exported for headless tests:
--   MatchRows(rows, query) → filtered flat list (case-insensitive plain
--     substring; headers kept only when they match or a child matches)
-- Frame parts are NOT tested (no WoW frame API headless).
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local FilterPopup = {}
Alts.FilterPopup = FilterPopup

local POPUP_W, ROW_H, MAX_ROWS = 280, 22, 12
local HEADER_H = 54 -- 6 pad + 22 search + 4 gap + 18 buttons + 4 gap

---------------------------------------------------------------------------
-- Pure helper (tested headless).
---------------------------------------------------------------------------

--- Case-insensitive plain-substring match of `query` against row labels.
--- nil/empty/whitespace query returns `rows` unchanged. Header rows
--- (header = true) are kept when their own label matches (keeping ALL
--- their children) or when at least one child matches (keeping only the
--- matched children); headers are never emitted without children.
function FilterPopup.MatchRows(rows, query)
    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return rows end
    local needle = query:lower()
    local out = {}
    local pendingHeader, headerMatched = nil, false
    for _, r in ipairs(rows) do
        if r.header then
            pendingHeader = r
            headerMatched = r.label:lower():find(needle, 1, true) and true or false
        else
            if headerMatched or r.label:lower():find(needle, 1, true) then
                if pendingHeader then
                    out[#out + 1] = pendingHeader
                    pendingHeader = nil
                end
                out[#out + 1] = r
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Frame parts (no headless test).
---------------------------------------------------------------------------




-- small text button (Select all / Deselect all chrome)
local function MakeTextButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(18)
    UIKit.CreateBackground(b, 1, 1, 1, 0.06)
    UIKit.CreateBorderLines(b)
    UIKit.UpdateBorderLines(b, 1, 1, 1, 1, 0.2)
    b._label = MakeFS(b, 10)
    b._label:SetPoint("CENTER")
    b._label:SetText(text)
    b._label:SetTextColor(0.9, 0.9, 0.9)
    b:SetScript("OnEnter", function(self)
        UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.35)
    end)
    b:SetScript("OnLeave", function(self)
        UIKit.UpdateBorderLines(self, 1, 1, 1, 1, 0.2)
    end)
    return b
end

--- Wire a searchable filter popup onto opts.anchorButton (see header).
function FilterPopup.Attach(opts)
    local popup          -- built lazily on first open
    local rowPool = {}
    local allRows = {}   -- full row list rebuilt per open
    local matched = {}   -- search-filtered view of allRows
    local offset = 0

    local RenderRows -- forward declared: row factory + search both call it

    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = CreateFrame("Button", nil, popup)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -HEADER_H - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -HEADER_H - (i - 1) * ROW_H)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(1, 1, 1, 0)
        r._bg = bg
        r._cb = UIKit.CreateAccentCheckbox(r, {
            size = 14,
            onChange = function(checked)
                if r._id == nil then return end
                opts.setChecked(r._id, checked)
                opts.onChanged()
            end,
        })
        r._cb:SetPoint("LEFT", r, "LEFT", 2, 0)
        r._label = MakeFS(r, 11)
        r._label:SetJustifyH("LEFT")
        -- the whole row is a click target, not just the 14px box
        r:SetScript("OnClick", function(self)
            if self._id ~= nil then self._cb:Toggle() end
        end)
        r:SetScript("OnEnter", function(self)
            if self._id ~= nil then self._bg:SetVertexColor(1, 1, 1, 0.08) end
        end)
        r:SetScript("OnLeave", function(self) self._bg:SetVertexColor(1, 1, 1, 0) end)
        rowPool[i] = r
        return r
    end

    RenderRows = function()
        local visible = math.min(#matched, MAX_ROWS)
        local maxOff = math.max(0, #matched - MAX_ROWS)
        if offset > maxOff then offset = maxOff end
        if offset < 0 then offset = 0 end
        for i = 1, visible do
            local r = GetRow(i)
            local row = matched[offset + i]
            r._label:ClearAllPoints()
            if row.header then
                r._id = nil
                r._cb:Hide()
                r._label:SetPoint("LEFT", r, "LEFT", 4, 0)
                r._label:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                r._label:SetText(row.label)
                r._label:SetTextColor(1, 0.82, 0)
            else
                r._id = row.id
                r._cb:Show()
                r._cb:SetChecked(opts.isChecked(row.id), true)
                r._label:SetPoint("LEFT", r, "LEFT", 24, 0)
                r._label:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                r._label:SetText(row.label)
                r._label:SetTextColor(0.9, 0.9, 0.9)
            end
            r:Show()
        end
        for i = visible + 1, #rowPool do
            rowPool[i]._id = nil
            rowPool[i]:Hide()
        end
        popup._empty:SetShown(#matched == 0)
        popup:SetHeight(HEADER_H + math.max(visible, 1) * ROW_H + 8)
    end

    local function ForEachMatchedID(fn)
        for _, row in ipairs(matched) do
            if not row.header then fn(row.id) end
        end
    end

    local function Build()
        popup = CreateFrame("Frame", nil, opts.floating and UIParent or opts.tabFrame)
        popup:SetWidth(POPUP_W)
        popup:SetPoint("TOPRIGHT", opts.anchorButton, "BOTTOMRIGHT", 0, -2)
        -- floating: TOOLTIP strata — the settings window is
        -- FULLSCREEN_DIALOG level 500 + Toplevel, so anything below TOOLTIP
        -- renders behind it (framework.lua dropdown-menu precedent)
        popup:SetFrameStrata(opts.floating and "TOOLTIP" or "DIALOG")
        popup:EnableMouse(true)
        popup:Hide()
        if opts.floating then
            -- not a child, so closing/switching the host panel must hide it
            opts.tabFrame:HookScript("OnHide", function() popup:Hide() end)
        end
        UIKit.CreateBackground(popup, 0.051, 0.067, 0.09, 0.97)
        UIKit.CreateBorderLines(popup)
        UIKit.UpdateBorderLines(popup, 1, 1, 1, 1, 0.2)

        -- search box
        local sb = CreateFrame("EditBox", nil, popup)
        sb:SetAutoFocus(false)
        sb:SetHeight(22)
        sb:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -6)
        sb:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6)
        sb:SetFont(GeneralFont(), 11, GeneralOutline())
        sb:SetTextInsets(6, 6, 0, 0)
        sb:SetMaxLetters(40)
        UIKit.CreateBackground(sb, 1, 1, 1, 0.06)
        UIKit.CreateBorderLines(sb)
        UIKit.UpdateBorderLines(sb, 1, 1, 1, 1, 0.2)
        local placeholder = MakeFS(sb, 11)
        placeholder:SetPoint("LEFT", sb, "LEFT", 6, 0)
        placeholder:SetText("Search...")
        placeholder:SetTextColor(0.5, 0.5, 0.5)
        sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        sb:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
        sb:SetScript("OnEditFocusLost", function(self)
            placeholder:SetShown(self:GetText() == "")
        end)
        sb:SetScript("OnTextChanged", function(self)
            placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
            matched = FilterPopup.MatchRows(allRows, self:GetText())
            offset = 0
            RenderRows()
        end)
        popup._search = sb

        -- select all / deselect all (operate on the matched rows only)
        local selAll = MakeTextButton(popup, "Select all")
        selAll:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -32)
        selAll:SetPoint("RIGHT", popup, "CENTER", -2, 0)
        selAll:SetScript("OnClick", function()
            ForEachMatchedID(function(id) opts.setChecked(id, true) end)
            RenderRows()
            opts.onChanged()
        end)
        local deselAll = MakeTextButton(popup, "Deselect all")
        deselAll:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -32)
        deselAll:SetPoint("LEFT", popup, "CENTER", 2, 0)
        deselAll:SetScript("OnClick", function()
            ForEachMatchedID(function(id) opts.setChecked(id, false) end)
            RenderRows()
            opts.onChanged()
        end)

        -- empty-state label (search matched nothing)
        popup._empty = MakeFS(popup, 11)
        popup._empty:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -HEADER_H - 5)
        popup._empty:SetText("No matches")
        popup._empty:SetTextColor(0.5, 0.5, 0.5)
        popup._empty:Hide()

        popup:EnableMouseWheel(true)
        popup:SetScript("OnMouseWheel", function(_, delta)
            local maxOff = math.max(0, #matched - MAX_ROWS)
            offset = math.min(maxOff, math.max(0, offset - delta))
            RenderRows()
        end)
        popup:SetScript("OnHide", function() sb:ClearFocus() end)
    end

    opts.anchorButton:SetScript("OnClick", function()
        if popup and popup:IsShown() then
            popup:Hide()
            return
        end
        if not popup then Build() end
        allRows = opts.getRows() or {}
        matched = allRows
        offset = 0
        popup._search:SetText("") -- OnTextChanged re-renders from allRows
        RenderRows()
        popup:Show()
    end)
end
