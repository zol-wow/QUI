-- tests/unit/bags_currency_bar_test.lua
-- Run: lua tests/unit/bags_currency_bar_test.lua
-- TDD for Bags.CurrencyBar's selection/order logic after the move to the
-- shared currency-section config model: render currencyOrder entries whose
-- currencyEnabled value is explicit true (STRING ids — the shape the shared
-- settings section writes), in order; fall back to the legacy
-- currencyBar.currencies [id]=true set (sorted) on a pre-migration profile;
-- amounts are mode-aware (live = struct quantity, cached = the viewed
-- record's scanner map, absent = 0); hidden (height 0) when disabled or
-- nothing renders.
-- WoW surface stubs: CreateFrame (bar frame + texture/fontstring pools),
-- C_CurrencyInfo.GetCurrencyInfo (MayReturnNothing → unknown IDs skipped).

local function MakeFontString()
    local fs = { _text = "", _shown = true }
    function fs:SetFont() end
    function fs:SetPoint() end
    function fs:SetText(t) self._text = tostring(t) end
    function fs:Show() self._shown = true end
    function fs:Hide() self._shown = false end
    function fs:GetStringWidth() return 20 end
    return fs
end

local function MakeTexture()
    local t = { _shown = true }
    function t:SetSize() end
    function t:SetTexture(tex) self._tex = tex end
    function t:ClearAllPoints() end
    function t:SetPoint() end
    function t:Show() self._shown = true end
    function t:Hide() self._shown = false end
    return t
end

local function MakeFrame()
    local f = { _shown = true }
    function f:SetPoint() end
    function f:SetHeight() end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:CreateTexture() return MakeTexture() end
    function f:CreateFontString() return MakeFontString() end
    return f
end

_G.CreateFrame = function(...) return MakeFrame() end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- Currency DB: GetCurrencyInfo MayReturnNothing → 999 unknown.
local CURRENCY_DB = {
    [2706] = { iconFileID = 111, quantity = 7 },
    [2245] = { iconFileID = 222, quantity = 30 },
    [1191] = { iconFileID = 333, quantity = 4 },
    [3]    = { iconFileID = 444, quantity = 1 },
    [5]    = { iconFileID = 555, quantity = 2 },
}
_G.C_CurrencyInfo = {
    GetCurrencyInfo = function(id) return CURRENCY_DB[tonumber(id)] end,
}

local settings = {}
local ns = {
    Helpers = {
        CreateDBGetter = function() return function() return settings end end,
        GetGeneralFont = function() return nil end,
    },
}

local chunk = assert(loadfile("QUI_Bags/bags/views/currency_bar.lua"))
chunk("QUI", ns)

local win = { _footer = MakeFrame() }
local bar = ns.Bags.CurrencyBar.Attach(win)

--- Rendered (icon texture, amount text) pairs in segment order.
local function RenderedSegments()
    local out = {}
    for _, seg in ipairs(bar._segments) do
        if seg.icon._shown then
            out[#out + 1] = { tex = seg.icon._tex, amount = seg.amount._text }
        end
    end
    return out
end

-- Section 1: new model, live mode — order respected, enabled==true only,
-- unknown ID skipped, nil-enabled (never seeded) skipped.
settings.currencyBar = {
    enabled = true,
    currencyOrder = { "2245", "999", "2706", "1191", "3" },
    currencyEnabled = { ["2245"] = true, ["999"] = true, ["2706"] = true, ["1191"] = false },
    -- "3" deliberately absent from currencyEnabled (nil ≠ true → skipped);
    -- a stale legacy set must be IGNORED while the new model has rows:
    currencies = { [5] = true },
}
local h = bar:Update(nil, true)
assert(h > 0, "bar must reserve height while currencies render")
local segs = RenderedSegments()
assert(#segs == 2, "only enabled==true + known IDs render, got " .. #segs)
assert(segs[1].tex == 222 and segs[1].amount == "30", "first segment must follow currencyOrder (2245 live qty)")
assert(segs[2].tex == 111 and segs[2].amount == "7", "second segment is 2706; disabled 1191 and unseeded 3 skipped")

-- Section 2: cached mode — amounts from the viewed record's scanner map,
-- absent = 0; icon identity still from the live struct.
local record = { currencies = { [2245] = 1234 } }
bar:Update(record, false)
segs = RenderedSegments()
assert(segs[1].amount == "1234", "cached mode must read the record map")
assert(segs[2].amount == "0", "cached mode renders 0 for IDs absent from the record")

-- Section 3: legacy pre-migration profile (no order/enabled lists) —
-- the [id]=true set renders sorted.
settings.currencyBar = { enabled = true, currencies = { [5] = true, [3] = true } }
bar:Update(nil, true)
segs = RenderedSegments()
assert(#segs == 2, "legacy set must render")
assert(segs[1].tex == 444 and segs[2].tex == 555, "legacy set renders in sorted ID order (3 then 5)")

-- Section 4: disabled / empty → hidden, zero height.
settings.currencyBar = { enabled = false, currencyOrder = { "2706" }, currencyEnabled = { ["2706"] = true } }
assert(bar:Update(nil, true) == 0, "disabled bar must reserve no height")
assert(bar._shown == false, "disabled bar must hide")
settings.currencyBar = { enabled = true, currencyOrder = {}, currencyEnabled = {} }
assert(bar:Update(nil, true) == 0, "empty lists must reserve no height")

print("OK: bags_currency_bar_test")
