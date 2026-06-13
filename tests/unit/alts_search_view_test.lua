-- tests/unit/alts_search_view_test.lua
-- Run: lua tests/unit/alts_search_view_test.lua
-- Covers the PURE helpers of the search tab:
--   SearchView.MatchName
--   SearchView.OwnerLabel
--   SearchView.LocationsText
--   SearchView.SortResults
-- Frame-building Builder is NOT exercised (no WoW frame API headless).

local ns = {}

ns.Helpers = {
    GetGeneralFont        = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}
ns.UIKit = {}
-- Summaries stub supplying the canonical owner-key constants the view reads.
ns.Storage = { Store = {}, Bus = {}, Summaries = {
    WARBAND_OWNER = ":warband",
    GUILD_PREFIX  = ":guild:",
} }
ns.Alts = { Window = { RegisterTab = function() end } }

assert(loadfile("QUI_Alts/alts/views/shared.lua"))("QUI", ns)
assert(loadfile("QUI_Alts/alts/views/search.lua"))("QUI", ns)

local SV = ns.Alts.SearchView
assert(SV, "SearchView exported")

---------------------------------------------------------------------------
-- MatchName
---------------------------------------------------------------------------
assert(SV.MatchName("Linen Cloth", "linen") == true, "case-insensitive lower match")
assert(SV.MatchName("Linen Cloth", "CLOTH") == true, "case-insensitive upper query")
assert(SV.MatchName("Linen Cloth", "leather") == false, "non-match")
assert(SV.MatchName("Linen Cloth", "en Cl") == true, "substring with space")
assert(SV.MatchName(nil, "linen") == false, "nil name false")
assert(SV.MatchName("Linen Cloth", nil) == false, "nil query false")
-- magic chars are literal (plain find)
assert(SV.MatchName("Item (rare)", "(rare)") == true, "plain find treats parens literally")
assert(SV.MatchName("Item rare", "(rare)") == false, "no Lua-pattern match")

---------------------------------------------------------------------------
-- OwnerLabel
---------------------------------------------------------------------------
local lc, kind = SV.OwnerLabel("Bob-Stormrage")
assert(kind == "char" and lc.isChar == true, "char kind")
assert(lc.label == "Bob", "char label = name part")

local lw, kw = SV.OwnerLabel(":warband")
assert(kw == "warband" and lw.label == "Warband", "warband label")
assert(lw.isChar == nil, "warband not a char")

local lg, kg = SV.OwnerLabel(":guild:My Guild-Stormrage")
assert(kg == "guild", "guild kind")
assert(lg.label == "Guild: My Guild", "guild label parsed (realm stripped)")
assert(lg.guild == "My Guild", "guild name part")

-- a character key with no realm separator falls back to the whole key
local lr = SV.OwnerLabel("Soloname")
assert(lr.label == "Soloname", "dash-less char key falls back to whole key")

---------------------------------------------------------------------------
-- LocationsText
---------------------------------------------------------------------------
assert(SV.LocationsText({ bank = 5, bags = 3 }) == "bags 3, bank 5", "alphabetical join")
assert(SV.LocationsText({ warband = 2 }) == "warband 2", "single location")
assert(SV.LocationsText({}) == "", "empty table → empty string")
assert(SV.LocationsText(nil) == "", "nil → empty string")

---------------------------------------------------------------------------
-- SortResults (in place: name asc, then ownerLabel asc, then itemID)
---------------------------------------------------------------------------
local r = {
    { name = "Cloth", ownerLabel = "Bob", itemID = 2 },
    { name = "Apple", ownerLabel = "Zed", itemID = 5 },
    { name = "Apple", ownerLabel = "Bob", itemID = 9 },
    { name = nil,     ownerLabel = "Bob", itemID = 1 }, -- pending name sorts last
    { name = "Apple", ownerLabel = "Bob", itemID = 3 }, -- tie → lower itemID first
}
SV.SortResults(r)
assert(r[1].name == "Apple" and r[1].ownerLabel == "Bob" and r[1].itemID == 3, "name asc, owner asc, itemID asc")
assert(r[2].name == "Apple" and r[2].ownerLabel == "Bob" and r[2].itemID == 9, "itemID tiebreak")
assert(r[3].name == "Apple" and r[3].ownerLabel == "Zed", "owner label tiebreak")
assert(r[4].name == "Cloth", "name asc")
assert(r[5].name == nil, "pending name last")

print("OK: alts_search_view_test")
