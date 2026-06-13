-- tests/unit/alts_filter_popup_test.lua
-- Run: lua tests/unit/alts_filter_popup_test.lua
-- Covers the PURE part of the shared filter popup:
--   FilterPopup.MatchRows (flat row list with optional header rows)
-- The frame-building Attach is NOT exercised (no WoW frame API headless).

local ns = {}
ns.Helpers = {
    GetGeneralFont        = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}

assert(loadfile("QUI_Alts/alts/views/shared.lua"))("QUI", ns)
assert(loadfile("QUI_Alts/alts/views/filter_popup.lua"))("QUI", ns)

local FP = ns.Alts.FilterPopup
assert(FP, "FilterPopup exported")

---------------------------------------------------------------------------
-- MatchRows: flat list WITHOUT headers (currencies shape)
---------------------------------------------------------------------------
do
    local rows = {
        { id = 1, label = "Flightstones" },
        { id = 2, label = "Timewarped Badge" },
        { id = 3, label = "Valorstones" },
    }
    local m = FP.MatchRows(rows, "stone")
    assert(#m == 2 and m[1].id == 1 and m[2].id == 3, "substring match: " .. #m)

    m = FP.MatchRows(rows, "TIMEWARPED")
    assert(#m == 1 and m[1].id == 2, "case-insensitive")

    -- empty/nil/whitespace query → everything
    assert(#FP.MatchRows(rows, "") == 3, "empty query keeps all")
    assert(#FP.MatchRows(rows, nil) == 3, "nil query keeps all")
    assert(#FP.MatchRows(rows, "  ") == 3, "whitespace trimmed")

    -- pattern magic chars are literal (plain find)
    assert(#FP.MatchRows(rows, "%a+") == 0, "plain find, no patterns")
end

---------------------------------------------------------------------------
-- MatchRows: list WITH header rows (reputations shape)
---------------------------------------------------------------------------
do
    local rows = {
        { label = "Dream Wardens", header = true },
        { id = 11, label = "AFac" },
        { id = 22, label = "BFac" },
        { label = "Other", header = true },
        { id = 33, label = "CFac" },
    }

    -- child match keeps its header, drops unmatched siblings + empty groups
    local m = FP.MatchRows(rows, "afac")
    assert(#m == 2, "child match: " .. #m)
    assert(m[1].header and m[1].label == "Dream Wardens", "header kept")
    assert(m[2].id == 11, "matched child kept")

    -- header match keeps ALL its children
    m = FP.MatchRows(rows, "dream")
    assert(#m == 3, "header match keeps group: " .. #m)
    assert(m[2].id == 11 and m[3].id == 22, "children kept via header")

    -- no match → empty (headers never emitted alone)
    assert(#FP.MatchRows(rows, "zzz") == 0, "no orphan headers")

    -- empty query returns everything including headers
    assert(#FP.MatchRows(rows, "") == 5, "empty query keeps headers")
end

print("OK alts_filter_popup_test")
