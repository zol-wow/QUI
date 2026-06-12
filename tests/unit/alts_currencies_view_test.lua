-- tests/unit/alts_currencies_view_test.lua
-- Run: lua tests/unit/alts_currencies_view_test.lua
-- Covers the PURE parts of the currencies tab:
--   CurrenciesView.FormatQuantity (nil, comma grouping, max suffix)
--   CurrenciesView.BuildDisplayRows (union, name sort, fallback label, ties)
-- The frame-building Builder is NOT exercised (no WoW frame API headless).

local ns = {}

ns.Helpers = {
    GetGeneralFont        = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}
ns.Storage = { Store = {}, Bus = {} }

-- currencies.lua reads Alts.Window.RegisterTab at file end; stub it.
ns.Alts = { Window = { RegisterTab = function() end } }

assert(loadfile("QUI_Alts/alts/views/currencies.lua"))("QUI", ns)

local CV = ns.Alts.CurrenciesView
assert(CV, "CurrenciesView exported")

---------------------------------------------------------------------------
-- FormatQuantity
---------------------------------------------------------------------------
assert(CV.FormatQuantity(nil) == "—", "nil qty → —: " .. tostring(CV.FormatQuantity(nil)))

local got = CV.FormatQuantity(0)
assert(got == "0", "zero: " .. got)

got = CV.FormatQuantity(999)
assert(got == "999", "no separator under 1000: " .. got)

got = CV.FormatQuantity(1234567)
assert(got == "1,234,567", "comma grouping: " .. got)

-- max appended only when > 0
got = CV.FormatQuantity(1500, 2000)
assert(got == "1,500 / 2,000", "max suffix: " .. got)

got = CV.FormatQuantity(1500, 0)
assert(got == "1,500", "max 0 → no suffix: " .. got)

got = CV.FormatQuantity(1500, nil)
assert(got == "1,500", "max nil → no suffix: " .. got)

---------------------------------------------------------------------------
-- BuildDisplayRows: union across characters + name sort + fallback label
---------------------------------------------------------------------------
local chars = {
    ["Amy-Realm"] = { currencies = { [2245] = 100, [1166] = 50 } },
    ["Bob-Realm"] = { currencies = { [2245] = 7, [3008] = 1 } },
    ["NoCur-Realm"] = {},                          -- no currencies table
    ["Empty-Realm"] = { currencies = {} },         -- empty map
}
local names = {
    [2245] = "Flightstones",
    [1166] = "Timewarped Badge",
    -- 3008 deliberately unnamed → "Currency 3008"
}

local rows = CV.BuildDisplayRows(chars, names)
assert(#rows == 3, "union size: " .. #rows)
assert(rows[1].label == "Currency 3008" and rows[1].currencyID == 3008,
    "fallback label sorts by string: " .. rows[1].label)
assert(rows[2].label == "Flightstones" and rows[2].currencyID == 2245,
    "name sort 2: " .. rows[2].label)
assert(rows[3].label == "Timewarped Badge" and rows[3].currencyID == 1166,
    "name sort 3: " .. rows[3].label)

-- empty/nil inputs
assert(#CV.BuildDisplayRows({}, {}) == 0, "empty chars → no rows")
assert(#CV.BuildDisplayRows(nil, nil) == 0, "nil chars → no rows")

-- duplicate names tie-break by id (stable, deterministic)
local dupRows = CV.BuildDisplayRows(
    { a = { currencies = { [5] = 1, [3] = 1 } } },
    { [5] = "Same", [3] = "Same" })
assert(dupRows[1].currencyID == 3 and dupRows[2].currencyID == 5,
    "tie-break by id")

print("OK alts_currencies_view_test")
