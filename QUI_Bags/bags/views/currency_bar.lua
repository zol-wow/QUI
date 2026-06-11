---------------------------------------------------------------------------
-- Bags views: currency bar. A footer-adjacent row on the BAG window showing
-- the user's settings-listed currencies (currencyBar.currencies, a
-- [currencyID]=true map managed in options) as icon + amount segments.
--
-- Data (verified, CurrencyInfoDocumentation.lua): C_CurrencyInfo.
-- GetCurrencyInfo(id) → CurrencyInfo { iconFileID (fileID), quantity
-- (number), ... }, MayReturnNothing — unknown IDs are skipped. Icon/identity
-- always come from the live struct; the AMOUNT is mode-aware: live mode uses
-- the struct's quantity, cached browsing uses the viewed character's
-- scanner-cached map (rec.currencies[id], scan_currencies.lua — zero
-- quantities are pruned there, so absent = 0).
--
-- Update cadence: the bag window's Refresh calls bar:Update() (which also
-- returns the extra content height for SetContentSize), and bag_window
-- subscribes CurrenciesChanged → ScheduleRefresh, so scanner drains land
-- here. Hidden (height 0) when disabled, list empty, or nothing renderable.
-- Clicks do nothing in v1.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local CurrencyBar = {}
Bags.CurrencyBar = CurrencyBar

local BAR_H = 18   -- extra content height while shown
local ICON = 14
local SEG_GAP = 12 -- gap between segments

--- Re-render from settings + the viewed record. `live` mirrors the window's
--- mode (viewedCharacter == nil). Returns the content height the window must
--- reserve above the footer (0 when hidden).
local function Update(bar, record, live)
    local s = GetSettings()
    local cfg = s and s.currencyBar
    local listed = cfg and cfg.enabled and cfg.currencies or nil
    local ids = {}
    if listed then
        for id in pairs(listed) do ids[#ids + 1] = id end
    end
    table.sort(ids) -- deterministic order (options manage an unordered map)

    local shown = 0
    local x = 0
    for _, id in ipairs(ids) do
        local info = C_CurrencyInfo.GetCurrencyInfo(id) -- MayReturnNothing
        if info then
            local qty
            if live then
                qty = info.quantity or 0
            else
                qty = record and record.currencies and record.currencies[id] or 0
            end
            shown = shown + 1
            local seg = bar._segments[shown]
            if not seg then
                seg = { icon = bar:CreateTexture(nil, "ARTWORK") }
                seg.icon:SetSize(ICON, ICON)
                seg.amount = bar:CreateFontString(nil, "ARTWORK")
                seg.amount:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
                seg.amount:SetPoint("LEFT", seg.icon, "RIGHT", 3, 0)
                bar._segments[shown] = seg
            end
            seg.icon:SetTexture(info.iconFileID)
            seg.amount:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(qty) or qty)
            seg.icon:ClearAllPoints()
            seg.icon:SetPoint("LEFT", bar, "LEFT", x, 0)
            seg.icon:Show()
            seg.amount:Show()
            x = x + ICON + 3 + math.ceil(seg.amount:GetStringWidth()) + SEG_GAP
        end
    end
    for i = shown + 1, #bar._segments do
        bar._segments[i].icon:Hide()
        bar._segments[i].amount:Hide()
    end

    if shown == 0 then
        bar:Hide()
        return 0
    end
    bar:Show()
    return BAR_H
end

--- Build the bar on a chassis window (EnsureWindow-time, bag window only).
--- Anchors above the footer across the body's width; starts hidden.
function CurrencyBar.Attach(win)
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("BOTTOMLEFT", win._footer, "TOPLEFT", 8, 0)
    bar:SetPoint("BOTTOMRIGHT", win._footer, "TOPRIGHT", -8, 0)
    bar:SetHeight(BAR_H)
    bar:Hide()
    bar._segments = {} -- pooled { icon = Texture, amount = FontString }
    bar.Update = Update
    win._currencyBar = bar
    return bar
end
