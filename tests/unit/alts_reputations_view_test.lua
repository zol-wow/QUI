-- tests/unit/alts_reputations_view_test.lua
-- Run: lua tests/unit/alts_reputations_view_test.lua
-- Covers the PURE parts of the reputations tab:
--   ReputationsView.FormatEntry  (all branches)
--   ReputationsView.BuildDisplayRows (grouping, sorting, Other-last, union)
-- The frame-building Builder is NOT exercised (no WoW frame API headless).

local ns = {}

ns.Helpers = {
    GetGeneralFont        = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}
ns.Storage = { Store = {}, Bus = {} }

-- reputations.lua reads Alts.Window.RegisterTab at file end; stub it.
ns.Alts = { Window = { RegisterTab = function() end } }

assert(loadfile("QUI_Alts/alts/views/shared.lua"))("QUI", ns)
assert(loadfile("QUI_Alts/alts/views/reputations.lua"))("QUI", ns)

local RV = ns.Alts.ReputationsView
assert(RV, "ReputationsView exported")

---------------------------------------------------------------------------
-- FormatEntry: nil entry → "—"
---------------------------------------------------------------------------
assert(RV.FormatEntry(nil) == "—", "nil entry → —: " .. tostring(RV.FormatEntry(nil)))

---------------------------------------------------------------------------
-- FormatEntry: renown branch
---------------------------------------------------------------------------
local renownEntry = { renownLevel = 14, renownEarned = 1500, renownThreshold = 2500 }
local got = RV.FormatEntry(renownEntry)
assert(got == "Renown 14 (1500/2500)", "renown: " .. got)

-- renown with missing earned/threshold falls back to 0
local renownZero = { renownLevel = 5 }
got = RV.FormatEntry(renownZero)
assert(got == "Renown 5 (0/0)", "renown zero fallback: " .. got)

---------------------------------------------------------------------------
-- FormatEntry: paragon branch — modulo + pending suffix
---------------------------------------------------------------------------
-- paragonValue = 31000, threshold = 10000 → shown = 31000 % 10000 = 1000
local paragonPending = { paragonValue = 31000, paragonThreshold = 10000, paragonPending = true }
got = RV.FormatEntry(paragonPending)
assert(got == "Paragon 1000/10000 !", "paragon modulo + pending: " .. got)

-- no pending suffix when paragonPending is false/nil
local paragonNoPend = { paragonValue = 31000, paragonThreshold = 10000, paragonPending = false }
got = RV.FormatEntry(paragonNoPend)
assert(got == "Paragon 1000/10000", "paragon no pending: " .. got)

-- threshold = 0 → skip modulo, use raw value
local paragonZeroThresh = { paragonValue = 5000, paragonThreshold = 0, paragonPending = false }
got = RV.FormatEntry(paragonZeroThresh)
assert(got == "Paragon 5000/0", "paragon zero threshold: " .. got)

---------------------------------------------------------------------------
-- FormatEntry: standing branch — with progress
---------------------------------------------------------------------------
-- standing=5 (Friendly), value=4500, floor=3000, ceiling=6000 → 1500/3000
local standingEntry = { standing = 5, value = 4500, floor = 3000, ceiling = 6000 }
got = RV.FormatEntry(standingEntry)
assert(got == "Friendly 1500/3000", "standing with progress: " .. got)

-- all eight standing labels
local labels = { "Hated","Hostile","Unfriendly","Neutral","Friendly","Honored","Revered","Exalted" }
for i, lbl in ipairs(labels) do
    local e = { standing = i, value = 100, floor = 0, ceiling = 200 }
    got = RV.FormatEntry(e)
    assert(got == lbl .. " 100/200", "standing label " .. i .. ": " .. got)
end

-- unknown standing falls back to "Standing N"
local unknownStanding = { standing = 99, value = 10, floor = 0, ceiling = 100 }
got = RV.FormatEntry(unknownStanding)
assert(got == "Standing 99 10/100", "unknown standing fallback: " .. got)

---------------------------------------------------------------------------
-- FormatEntry: capped standing — ceiling <= floor, no progress fraction
---------------------------------------------------------------------------
local cappedEntry = { standing = 8, value = 21000, floor = 21000, ceiling = 21000 }
got = RV.FormatEntry(cappedEntry)
assert(got == "Exalted", "capped exalted no progress: " .. got)

-- ceiling < floor also capped
local capLow = { standing = 8, value = 21000, floor = 21000, ceiling = 20000 }
got = RV.FormatEntry(capLow)
assert(got == "Exalted", "ceiling < floor also capped: " .. got)

---------------------------------------------------------------------------
-- FormatEntry: accountWide suffix
---------------------------------------------------------------------------
local awEntry = { standing = 6, value = 9000, floor = 6000, ceiling = 12000, accountWide = true }
got = RV.FormatEntry(awEntry)
assert(got == "Honored 3000/6000 (account)", "accountWide suffix: " .. got)

-- accountWide on renown
local awRenown = { renownLevel = 10, renownEarned = 500, renownThreshold = 1000, accountWide = true }
got = RV.FormatEntry(awRenown)
assert(got == "Renown 10 (500/1000) (account)", "accountWide renown: " .. got)

-- accountWide on paragon
local awParagon = { paragonValue = 5000, paragonThreshold = 10000, paragonPending = false, accountWide = true }
got = RV.FormatEntry(awParagon)
assert(got == "Paragon 5000/10000 (account)", "accountWide paragon: " .. got)

---------------------------------------------------------------------------
-- BuildDisplayRows: basic grouping + sorting
---------------------------------------------------------------------------
-- Two characters; faction 1 in "Stormwind", faction 2 in "Ironforge",
-- faction 3 ungrouped ("Other"), faction 4 only on char2.

local chars = {
    char1 = { reputations = { [1] = { standing = 5 }, [3] = { standing = 4 } } },
    char2 = { reputations = { [2] = { standing = 6 }, [4] = { standing = 7 } } },
}
local names = { [1] = "SW Guards", [2] = "IF Dwarves", [3] = "Wanderers", [4] = "Zeta" }
local groups = { [1] = "Stormwind", [2] = "Ironforge" }
-- faction 3 and 4 have no group → "Other"

local rowList = RV.BuildDisplayRows(chars, names, groups)

-- Expect group headers: "Ironforge", "Stormwind", "Other" (alphabetical, Other last)
local groupLabels = {}
local factionLabels = {}
for _, r in ipairs(rowList) do
    if r.kind == "group" then
        groupLabels[#groupLabels + 1] = r.label
    else
        factionLabels[#factionLabels + 1] = r.label
    end
end

assert(#groupLabels == 3, "3 group header rows: " .. #groupLabels)
assert(groupLabels[1] == "Ironforge",  "first group = Ironforge: "  .. groupLabels[1])
assert(groupLabels[2] == "Stormwind",  "second group = Stormwind: " .. groupLabels[2])
assert(groupLabels[3] == "Other",      "last group = Other: "       .. groupLabels[3])

assert(#factionLabels == 4, "4 faction rows: " .. #factionLabels)

-- All four factionIDs present in the union
local factionIDs = {}
for _, r in ipairs(rowList) do
    if r.kind == "faction" then factionIDs[r.factionID] = true end
end
assert(factionIDs[1] and factionIDs[2] and factionIDs[3] and factionIDs[4],
    "all four factionIDs in union")

---------------------------------------------------------------------------
-- BuildDisplayRows: "Other" is last even when it would sort first
---------------------------------------------------------------------------
local charsOther = {
    c = { reputations = { [10] = {}, [20] = {} } }
}
local namesOther = { [10] = "Aardvark Guild", [20] = "Zyxel Mob" }
-- no groups at all → both are "Other"
local rowsOther = RV.BuildDisplayRows(charsOther, namesOther, {})
assert(#rowsOther == 3, "1 group header + 2 faction rows: " .. #rowsOther)
assert(rowsOther[1].kind == "group" and rowsOther[1].label == "Other",
    "sole group is Other: " .. tostring(rowsOther[1].label))
-- factions within Other sorted by name: Aardvark < Zyxel
assert(rowsOther[2].label == "Aardvark Guild", "Aardvark first in Other: " .. rowsOther[2].label)
assert(rowsOther[3].label == "Zyxel Mob",      "Zyxel second in Other: "  .. rowsOther[3].label)

---------------------------------------------------------------------------
-- BuildDisplayRows: union semantics — factionIDs from ALL characters
---------------------------------------------------------------------------
local c1 = { reputations = { [100] = { standing = 5 } } }
local c2 = { reputations = { [200] = { standing = 6 } } }  -- char2 only has 200
local rowsUnion = RV.BuildDisplayRows({ x = c1, y = c2 }, {}, {})
local unionIDs = {}
for _, r in ipairs(rowsUnion) do
    if r.kind == "faction" then unionIDs[r.factionID] = true end
end
assert(unionIDs[100] and unionIDs[200],
    "union includes factionIDs from both chars (100 and 200)")
assert(not unionIDs[999], "non-existent faction absent from union")

---------------------------------------------------------------------------
-- BuildDisplayRows: empty characters → empty rows
---------------------------------------------------------------------------
local emptyRows = RV.BuildDisplayRows({}, {}, {})
assert(#emptyRows == 0, "no characters → no rows: " .. #emptyRows)

local nilRows = RV.BuildDisplayRows(nil, nil, nil)
assert(#nilRows == 0, "nil args → no rows: " .. #nilRows)

---------------------------------------------------------------------------
-- BuildDisplayRows: faction name fallback when names map absent
---------------------------------------------------------------------------
local charsFallback = { k = { reputations = { [42] = { standing = 3 } } } }
local rowsFallback = RV.BuildDisplayRows(charsFallback, {}, {})
local found = false
for _, r in ipairs(rowsFallback) do
    if r.kind == "faction" and r.factionID == 42 then
        assert(r.label == "Faction 42", "fallback name: " .. r.label)
        found = true
    end
end
assert(found, "faction 42 present in rows with fallback name")

print("OK: alts_reputations_view_test")

---------------------------------------------------------------------------
-- BuildDisplayRows: filter param ([factionID]=false hides; group headers
-- with zero visible factions are dropped)
---------------------------------------------------------------------------
do
    local fchars  = { a = { reputations = { [11] = {}, [22] = {}, [33] = {} } } }
    local fnames  = { [11] = "AFac", [22] = "BFac", [33] = "CFac" }
    local fgroups = { [11] = "G1", [22] = "G1", [33] = "G2" }

    -- nil filter → 2 group rows + 3 faction rows (back-compat)
    local frows = RV.BuildDisplayRows(fchars, fnames, fgroups, nil)
    assert(#frows == 5, "nil filter keeps all: " .. #frows)

    -- hide one faction in a two-faction group: header stays
    frows = RV.BuildDisplayRows(fchars, fnames, fgroups, { [11] = false })
    assert(#frows == 4, "one hidden: " .. #frows)

    -- hide a group's only faction: header dropped too
    -- (G1 header + AFac + BFac = 3 rows)
    frows = RV.BuildDisplayRows(fchars, fnames, fgroups, { [33] = false })
    assert(#frows == 3, "G2 elided: " .. #frows)
    for _, r in ipairs(frows) do
        assert(not (r.kind == "group" and r.label == "G2"), "G2 header gone")
    end
end

print("OK: filter param")
