-- tests/unit/alts_professions_view_test.lua
-- Run: lua tests/unit/alts_professions_view_test.lua
-- Covers the PURE part of the professions tab: ProfessionsView.CellTexts.
-- The frame-building Builder is NOT exercised (no WoW frame API headless).
-- RegisterTab + Helpers + global font stubs mirror the roster view test.

local ns = {}

ns.Helpers = {
    GetGeneralFont    = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}
ns.Storage = { Store = {}, Bus = {} }

-- professions.lua reads Alts.Window.RegisterTab at file end; stub it.
ns.Alts = { Window = { RegisterTab = function() end } }

assert(loadfile("QUI_Alts/alts/views/professions.lua"))("QUI", ns)

local PV = ns.Alts.ProfessionsView
assert(PV, "ProfessionsView exported")

-- fixture: 4 professions incl. primaries + secondaries ------------------
local rec4 = {
    professions = {
        { name = "Alchemy",    rank = 75,  maxRank = 100, isPrimary = true  },
        { name = "Herbalism",  rank = 50,  maxRank = 100, isPrimary = true  },
        { name = "Cooking",    rank = 30,  maxRank = 50,  isPrimary = false },
        { name = "Fishing",    rank = 10,  maxRank = 75,  isPrimary = false },
    },
}

local texts4 = PV.CellTexts(rec4)
assert(#texts4 == 4, "4 professions → 4 strings: " .. #texts4)
assert(texts4[1] == "Alchemy 75/100",   "first primary: " .. texts4[1])
assert(texts4[2] == "Herbalism 50/100", "second primary: " .. texts4[2])
assert(texts4[3] == "Cooking 30/50",    "third (cooking): " .. texts4[3])
assert(texts4[4] == "Fishing 10/75",    "fourth (fishing): " .. texts4[4])

-- max 5 slots: 6-profession record is capped ----------------------------
local rec6 = {
    professions = {
        { name = "A", rank = 1, maxRank = 10 },
        { name = "B", rank = 2, maxRank = 10 },
        { name = "C", rank = 3, maxRank = 10 },
        { name = "D", rank = 4, maxRank = 10 },
        { name = "E", rank = 5, maxRank = 10 },
        { name = "F", rank = 6, maxRank = 10 },
    },
}
local texts6 = PV.CellTexts(rec6)
assert(#texts6 == 5, "6-entry list capped at 5: " .. #texts6)

-- empty / missing professions → empty array -----------------------------
local recEmpty = { professions = {} }
local textsEmpty = PV.CellTexts(recEmpty)
assert(#textsEmpty == 0, "empty professions list → empty array")

local recNil = {}
local textsNil = PV.CellTexts(recNil)
assert(#textsNil == 0, "missing professions key → empty array")

local textsRecNil = PV.CellTexts(nil)
assert(#textsRecNil == 0, "nil record → empty array")

-- nil name tolerance: falls back to "?" --------------------------------
local recNoName = {
    professions = {
        { rank = 10, maxRank = 100 },
    },
}
local textsNoName = PV.CellTexts(recNoName)
assert(#textsNoName == 1, "one slot even with nil name")
assert(textsNoName[1] == "? 10/100", "nil name → '?': " .. textsNoName[1])

-- nil rank/maxRank fall back to 0 --------------------------------------
local recNoRank = {
    professions = {
        { name = "Mining" },
    },
}
local textsNoRank = PV.CellTexts(recNoRank)
assert(#textsNoRank == 1, "one slot with nil rank/maxRank")
assert(textsNoRank[1] == "Mining 0/0", "nil rank/maxRank → 0/0: " .. textsNoRank[1])

print("OK: alts_professions_view_test")
