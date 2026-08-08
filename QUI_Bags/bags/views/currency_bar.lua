local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Storage = ns.Storage
local Helpers = ns.Helpers
local GetSettings = Helpers.CreateDBGetter("bags")

local function CJKFont(fs, p, s, f)
    if Bags.CJKFont then return Bags.CJKFont(fs, p, s, f) end
    fs:SetFont(p, s, f)
end

local CurrencyBar = {}
Bags.CurrencyBar = CurrencyBar

local BAR_H = 18
local ICON = 14
local SEG_GAP = 12
local MAX_TOOLTIP_ROWS = 12

local function FormatQty(qty)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(qty) or tostring(qty)
end

local function ShowBreakdownTooltip(hit)
    local id = hit._currencyID
    if not id then return end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not info then return end

    GameTooltip:SetOwner(hit, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(info.name or "", 1, 1, 1)

    if info.isAccountWide then
        GameTooltip:AddDoubleLine(ns.L["Warband (account-wide)"],
            FormatQty(info.quantity or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        local Store = Storage.Store
        if Store and Store.ListCharacters then
            local rows, total = {}, 0
            for _, key in ipairs(Store.ListCharacters()) do
                local rec = Store.GetCharacter(key)
                local qty = rec and rec.currencies and rec.currencies[id]
                if qty and qty > 0 then
                    local classToken = rec.details and rec.details.class
                    rows[#rows + 1] = {
                        name = key:match("^([^%-]+)") or key,
                        qty = qty,
                        color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] or nil,
                    }
                    total = total + qty
                end
            end
            table.sort(rows, function(a, b) return a.qty > b.qty end)
            GameTooltip:AddDoubleLine(ns.L["All Characters"], FormatQty(total),
                0.8, 0.8, 0.8, 1, 1, 1)
            for i = 1, math.min(#rows, MAX_TOOLTIP_ROWS) do
                local r = rows[i]
                local cr, cg, cb = 0.9, 0.9, 0.9
                if r.color then cr, cg, cb = r.color.r, r.color.g, r.color.b end
                GameTooltip:AddDoubleLine("  " .. r.name, FormatQty(r.qty),
                    cr, cg, cb, 1, 1, 1)
            end
            if #rows > MAX_TOOLTIP_ROWS then
                GameTooltip:AddLine("  …", 0.6, 0.6, 0.6)
            end
        end
    end
    GameTooltip:Show()
end

local function Update(bar, record, live)
    local s = GetSettings()
    local cfg = s and s.currencyBar
    local ids = {}
    if cfg and cfg.enabled then
        if type(cfg.currencyOrder) == "table" then
            local en = cfg.currencyEnabled
            for _, sid in ipairs(cfg.currencyOrder) do
                if type(en) == "table" and en[sid] == true then
                    ids[#ids + 1] = tonumber(sid) or sid
                end
            end
        end
        if #ids == 0 and type(cfg.currencies) == "table" then
            for id in pairs(cfg.currencies) do ids[#ids + 1] = id end
            table.sort(ids)
        end
    end

    local shown = 0
    local x = 0
    for _, id in ipairs(ids) do
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
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
                CJKFont(seg.amount, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, 11, "OUTLINE")
                seg.amount:SetPoint("LEFT", seg.icon, "RIGHT", 3, 0)
                seg.hit = CreateFrame("Frame", nil, bar)
                seg.hit:SetHeight(BAR_H)
                seg.hit:EnableMouse(true)
                seg.hit:SetScript("OnEnter", ShowBreakdownTooltip)
                seg.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
                bar._segments[shown] = seg
            end
            seg.icon:SetTexture(info.iconFileID)
            seg.amount:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(qty) or qty)
            seg.icon:ClearAllPoints()
            seg.icon:SetPoint("LEFT", bar, "LEFT", x, 0)
            seg.icon:Show()
            seg.amount:Show()
            local segWidth = ICON + 3 + math.ceil(seg.amount:GetStringWidth())
            seg.hit._currencyID = id
            seg.hit:ClearAllPoints()
            seg.hit:SetPoint("LEFT", bar, "LEFT", x, 0)
            seg.hit:SetWidth(segWidth)
            seg.hit:Show()
            x = x + segWidth + SEG_GAP
        end
    end
    for i = shown + 1, #bar._segments do
        bar._segments[i].icon:Hide()
        bar._segments[i].amount:Hide()
        if bar._segments[i].hit then
            bar._segments[i].hit._currencyID = nil
            bar._segments[i].hit:Hide()
        end
    end

    if shown == 0 then
        bar:Hide()
        return 0
    end
    bar:Show()
    return BAR_H
end

function CurrencyBar.Attach(win)
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("BOTTOMLEFT", win._footer, "TOPLEFT", 8, 0)
    bar:SetPoint("BOTTOMRIGHT", win._footer, "TOPRIGHT", -8, 0)
    bar:SetHeight(BAR_H)
    bar:Hide()
    bar._segments = {}
    bar.Update = Update
    win._currencyBar = bar
    return bar
end
