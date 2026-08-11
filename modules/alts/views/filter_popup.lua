local ADDON_NAME, ns = ...

local Shared = ns.AltsViewShared
local GeneralFont = Shared.GeneralFont
local GeneralOutline = Shared.GeneralOutline
local MakeFS = Shared.MakeFS
local Alts = ns.Alts or {}; ns.Alts = Alts

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local function CJKFont(fs, p, s, f)
    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local FilterPopup = {}
Alts.FilterPopup = FilterPopup

local POPUP_W, ROW_H, MAX_ROWS = 280, 22, 12
local HEADER_H = 54

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

function FilterPopup.Attach(opts)
    local popup
    local rowPool = {}
    local allRows = {}
    local matched = {}
    local offset = 0

    local RenderRows

    local function GetRow(i)
        local r = rowPool[i]
        if r then return r end
        r = Shared.CreateRow(popup, {
            height = ROW_H,
            hoverGuard = function(self) return self._id ~= nil end,
        })
        r:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -HEADER_H - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -HEADER_H - (i - 1) * ROW_H)
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
        popup:SetFrameStrata(opts.floating and "TOOLTIP" or "DIALOG")
        popup:EnableMouse(true)
        popup:Hide()
        if opts.floating then
            opts.tabFrame:HookScript("OnHide", function() popup:Hide() end)
        end
        UIKit.CreateBackground(popup, 0.051, 0.067, 0.09, 0.97)
        UIKit.CreateBorderLines(popup)
        UIKit.UpdateBorderLines(popup, 1, 1, 1, 1, 0.2)

        local sb = CreateFrame("EditBox", nil, popup)
        sb:SetAutoFocus(false)
        sb:SetHeight(22)
        sb:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -6)
        sb:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6)
        CJKFont(sb, GeneralFont(), 11, GeneralOutline())
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
        popup._search:SetText("")
        RenderRows()
        popup:Show()
    end)
end
