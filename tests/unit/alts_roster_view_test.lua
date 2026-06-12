-- tests/unit/alts_roster_view_test.lua
-- Run: lua tests/unit/alts_roster_view_test.lua
-- Covers the PURE parts of the roster tab view: CellText (per column id,
-- incl. rested rounding, professions compact format, nil fallbacks) and
-- BuildActiveColumns (always-columns kept, toggled-off absent, order kept).
-- The frame-building Builder is NOT exercised (no WoW frame API headless);
-- RegisterTab + Helpers + global font are stubbed so the file loads.

local ns = {}

-- Stubs the roster view file touches at load / in pure helpers.
ns.Helpers = {
    GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
    GetGeneralFontOutline = function() return "" end,
}
ns.Storage = { Store = {}, Bus = {} }

-- roster_data first (roster.lua reads Alts.RosterData at load).
assert(loadfile("QUI_Alts/alts/roster_data.lua"))("QUI", ns)

-- window.lua provides Alts.Window.RegisterTab; stub it so we don't load the
-- frame chassis. roster.lua calls it at file end.
ns.Alts.Window = { RegisterTab = function() end }

assert(loadfile("QUI_Alts/alts/views/roster.lua"))("QUI", ns)

local RV = ns.Alts.RosterView
assert(RV, "RosterView exported")

-- columns by id for lookups
local byId = {}
for _, c in ipairs(RV.COLUMNS) do byId[c.id] = c end

local now = 1000000
local row = {
    key = "Amy-Realm",
    name = "Amy",
    realm = "Realm",
    details = {
        level = 80, ilvl = 631.4, money = 12345678,
        playedTotal = 3 * 86400 + 5 * 3600,
        restedXP = 750, xpMax = 1000,
        zone = "Valdrakken", lastSeen = now - 7200, class = "DRUID",
    },
    record = {
        professions = {
            { name = "Alchemy", rank = 75, isPrimary = true },
            { name = "Herbalism", rank = 50, isPrimary = true },
            { name = "Cooking", rank = 30, isPrimary = false },
        },
    },
}

-- CellText per column ---------------------------------------------------
assert(RV.CellText(byId.name, row, now) == "Amy", "name cell")
assert(RV.CellText(byId.level, row, now) == "80", "level cell")
assert(RV.CellText(byId.ilvl, row, now) == "631", "ilvl floors via %.0f")
assert(RV.CellText(byId.gold, row, now) == "1,234g", "gold cell: " .. RV.CellText(byId.gold, row, now))
assert(RV.CellText(byId.played, row, now) == "3d 5h", "played cell")
-- rested: 750/1000 = 75%
assert(RV.CellText(byId.rested, row, now) == "75%", "rested cell")
-- professions: primaries only, name to 4 chars, " · " join
assert(RV.CellText(byId.professions, row, now) == "Alch 75 · Herb 50",
    "professions compact: " .. RV.CellText(byId.professions, row, now))
assert(RV.CellText(byId.zone, row, now) == "Valdrakken", "zone cell")
assert(RV.CellText(byId.lastSeen, row, now) == "2h ago", "lastSeen cell")

-- rested rounding: 0.5 rounds up
local r2 = { details = { restedXP = 5, xpMax = 1000 } }
-- 0.5% + 0.5 round bias = 1.0 → floor → 1%
assert(RV.CellText(byId.rested, r2, now) == "1%", "rested 0.5% rounds to 1")
local r3 = { details = { restedXP = 996, xpMax = 1000 } }
assert(RV.CellText(byId.rested, r3, now) == "100%", "rested rounds 99.6 → 100")

-- nil fallbacks -> em dash --------------------------------------------
local empty = { key = "X-R", name = "X", details = {}, record = {} }
assert(RV.CellText(byId.level, empty, now) == "—", "nil level → —")
assert(RV.CellText(byId.ilvl, empty, now) == "—", "nil ilvl → —")
assert(RV.CellText(byId.rested, empty, now) == "—", "nil rested → —")
assert(RV.CellText(byId.professions, empty, now) == "—", "no professions → —")
assert(RV.CellText(byId.zone, empty, now) == "—", "nil zone → —")
assert(RV.CellText(byId.lastSeen, empty, now) == "—", "nil lastSeen → —")
-- played/gold have their own nil handling in roster_data
assert(RV.CellText(byId.played, empty, now) == "—", "nil played → —")
assert(RV.CellText(byId.gold, empty, now) == "0g", "nil money → 0g")

-- BuildActiveColumns ---------------------------------------------------
-- nil cfg → every column
local all = RV.BuildActiveColumns(nil)
assert(#all == #RV.COLUMNS, "nil cfg shows all columns")

-- all toggles false → only always-columns (name, level), order preserved
local cfg = { ilvl = false, gold = false, played = false, rested = false,
    zone = false, lastSeen = false, professions = false }
local active = RV.BuildActiveColumns(cfg)
assert(#active == 2, "only 2 always-columns survive: " .. #active)
assert(active[1].id == "name" and active[2].id == "level", "always order preserved")

-- selective: gold + zone on, others off
local cfg2 = { ilvl = false, gold = true, played = false, rested = false,
    zone = true, lastSeen = false, professions = false }
local a2 = RV.BuildActiveColumns(cfg2)
local got = {}
for _, c in ipairs(a2) do got[c.id] = true end
assert(got.name and got.level and got.gold and got.zone, "name/level/gold/zone present")
assert(not got.ilvl and not got.played and not got.rested
    and not got.lastSeen and not got.professions, "toggled-off columns absent")
-- order: name, level, gold, zone (catalog order)
assert(a2[1].id == "name" and a2[2].id == "level"
    and a2[3].id == "gold" and a2[4].id == "zone", "selective order preserved")

print("OK: alts_roster_view_test")
