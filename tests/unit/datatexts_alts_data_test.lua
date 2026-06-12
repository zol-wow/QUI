-- tests/unit/datatexts_alts_data_test.lua
-- Run: lua tests/unit/datatexts_alts_data_test.lua
local ns = {}
local chunk = assert(loadfile("QUI_Datatexts/datatexts/alts_data.lua"))
chunk("QUI_Datatexts", ns)
local AD = ns.DatatextAltsData
assert(AD, "AltsData published on ns.DatatextAltsData")

-- BuildRows: gold desc, key tiebreak, missing details tolerance, name extraction.
local chars = {
    ["Bob-Aerie Peak"]   = { details = { class = "MAGE",  level = 70, ilvl = 480, money = 50000 } },
    ["Amy-Aerie Peak"]   = { details = { class = "DRUID", level = 80, ilvl = 500, money = 90000 } },
    ["Cara-Aerie Peak"]  = { details = { class = "PRIEST" } },                 -- missing money/level/ilvl
    ["Dan-Stormrage"]    = { details = { class = "WARRIOR", level = 60, ilvl = 400, money = 50000 } },
    ["Eve-Stormrage"]    = {},                                                  -- no details at all
}
local rows = AD.BuildRows(chars)
assert(#rows == 5, "all rows built: " .. #rows)

-- Sort: gold desc → Amy(90000), then Bob & Dan tie at 50000 (key asc: Bob<Dan),
-- then Cara(0) & Eve(0) tie (key asc: Cara<Eve).
assert(rows[1].key == "Amy-Aerie Peak", "gold desc top: " .. rows[1].key)
assert(rows[2].key == "Bob-Aerie Peak", "gold tie key asc Bob first: " .. rows[2].key)
assert(rows[3].key == "Dan-Stormrage",  "gold tie key asc Dan second: " .. rows[3].key)
assert(rows[4].key == "Cara-Aerie Peak", "zero-gold tie Cara first: " .. rows[4].key)
assert(rows[5].key == "Eve-Stormrage",   "zero-gold tie Eve second: " .. rows[5].key)

-- Name extraction from "Name-Realm" keys (realm may contain spaces).
assert(rows[1].name == "Amy", "name strips realm: " .. tostring(rows[1].name))
assert(rows[3].name == "Dan", "name strips realm: " .. tostring(rows[3].name))

-- Missing details tolerance: money defaults to 0, other fields nil.
assert(rows[4].money == 0, "missing money → 0")
assert(rows[4].class == "PRIEST", "partial details carried")
assert(rows[4].level == nil, "missing level → nil")
assert(rows[5].money == 0, "no details → money 0")
assert(rows[5].class == nil, "no details → class nil")

-- Carried fields on a full record.
assert(rows[1].class == "DRUID" and rows[1].level == 80 and rows[1].ilvl == 500, "full record fields")

-- Empty / nil input tolerance.
assert(#AD.BuildRows(nil) == 0, "nil characters → empty rows")
assert(#AD.BuildRows({}) == 0, "empty characters → empty rows")

-- Total: sum of money across rows.
assert(AD.Total(rows) == 190000, "total copper: " .. AD.Total(rows))
assert(AD.Total({}) == 0, "empty total → 0")

-- BarText both modes (inject stub formatGold).
local function stubGold(copper) return "<" .. tostring(copper) .. ">" end
assert(AD.BarText("count", rows, stubGold) == "Alts: 5", "count mode")
assert(AD.BarText("gold", rows, stubGold) == "Alts: <190000>", "gold mode")
-- Default/unknown mode falls through to gold.
assert(AD.BarText(nil, rows, stubGold) == "Alts: <190000>", "nil mode → gold")
assert(AD.BarText("anything", rows, stubGold) == "Alts: <190000>", "unknown mode → gold")

-- MergeLegacyGold: legacy goldData ("Realm-Name", raw realm) folded into
-- storage rows ("Name-NormalizedRealm"). Storage wins; legacy fills gaps.

-- Base storage rows (already in BuildRows shape).
local function storageRows()
    return AD.BuildRows({
        ["Bob-AeriePeak"] = { details = { class = "MAGE", level = 70, ilvl = 480, money = 50000 } },
        ["Amy-Stormrage"] = { details = { class = "DRUID", level = 80, ilvl = 500, money = 90000 } },
    })
end

-- 1. Non-overlapping legacy entry: synth key built, appended, sorted by gold.
do
    local r = AD.MergeLegacyGold(storageRows(), {
        ["Stormrage-Zed"] = { money = 70000, class = "ROGUE" },
    })
    assert(#r == 3, "non-overlap appended: " .. #r)
    -- Sort: Amy(90000) > Zed(70000) > Bob(50000).
    assert(r[1].key == "Amy-Stormrage", "top still Amy: " .. r[1].key)
    assert(r[2].key == "Zed-Stormrage", "legacy synth key + sort pos: " .. r[2].key)
    assert(r[2].name == "Zed" and r[2].class == "ROGUE" and r[2].money == 70000, "legacy row fields")
    assert(r[2].level == nil and r[2].ilvl == nil, "legacy row has no level/ilvl")
    assert(r[3].key == "Bob-AeriePeak", "Bob last: " .. r[3].key)
end

-- 2. Conflict: storage wins, no duplicate, legacy money ignored.
do
    local r = AD.MergeLegacyGold(storageRows(), {
        ["AeriePeak-Bob"] = { money = 999999, class = "WARLOCK" },
    })
    assert(#r == 2, "conflict produced no dupe: " .. #r)
    local bob
    for _, row in ipairs(r) do if row.key == "Bob-AeriePeak" then bob = row end end
    assert(bob and bob.money == 50000, "storage money wins: " .. tostring(bob and bob.money))
    assert(bob.class == "MAGE", "storage class wins: " .. tostring(bob.class))
end

-- 3. Old numeric format → money only, class nil.
do
    local r = AD.MergeLegacyGold(storageRows(), {
        ["Stormrage-Num"] = 12345,
    })
    assert(#r == 3, "numeric appended: " .. #r)
    local num
    for _, row in ipairs(r) do if row.key == "Num-Stormrage" then num = row end end
    assert(num and num.money == 12345, "numeric money: " .. tostring(num and num.money))
    assert(num.class == nil, "numeric format → class nil")
end

-- 4. Spaced realm normalization: "Aerie Peak-Bob" dedupes vs storage "Bob-AeriePeak".
do
    local r = AD.MergeLegacyGold(storageRows(), {
        ["Aerie Peak-Bob"] = { money = 1, class = "PALADIN" },
    })
    assert(#r == 2, "spaced realm dedup, no dupe: " .. #r)
    local bob
    for _, row in ipairs(r) do if row.key == "Bob-AeriePeak" then bob = row end end
    assert(bob and bob.money == 50000, "spaced legacy ignored (storage wins): " .. tostring(bob and bob.money))
end

-- 5. Dashed realm: "Azjol-Nerub-Bob" → realm "Azjol-Nerub" → "AzjolNerub", name "Bob".
do
    local r = AD.MergeLegacyGold(storageRows(), {
        ["Azjol-Nerub-Ник"] = { money = 30000, class = "HUNTER" },
    })
    local synth
    for _, row in ipairs(r) do if row.key == "Ник-AzjolNerub" then synth = row end end
    assert(synth, "dashed realm split on last dash → Ник-AzjolNerub")
    assert(synth.name == "Ник" and synth.money == 30000, "dashed realm row fields")
end

-- 6. Empty / nil goldData tolerance (rows re-sorted, unchanged set).
do
    local r = AD.MergeLegacyGold(storageRows(), nil)
    assert(#r == 2, "nil goldData → rows unchanged: " .. #r)
    assert(r[1].key == "Amy-Stormrage", "nil goldData still sorted")
    local r2 = AD.MergeLegacyGold(storageRows(), {})
    assert(#r2 == 2, "empty goldData → rows unchanged: " .. #r2)
end

-- LegacyToStorageKey
assert(AD.LegacyToStorageKey("Aerie Peak-Bob") == "Bob-AeriePeak")
assert(AD.LegacyToStorageKey("Azjol-Nerub-Bob") == "Bob-AzjolNerub")
assert(AD.LegacyToStorageKey("nodash") == nil)
assert(AD.LegacyToStorageKey(nil) == nil)

-- PurgeLegacyFor: deleted storage character must not resurrect via legacy
local gd = { ["Aerie Peak-Bob"] = 100, ["Aerie Peak-Amy"] = { money = 5 } }
assert(AD.PurgeLegacyFor(gd, "Bob-AeriePeak") == 1)
assert(gd["Aerie Peak-Bob"] == nil and gd["Aerie Peak-Amy"] ~= nil)
assert(AD.PurgeLegacyFor(gd, "Nobody-X") == 0)
assert(AD.PurgeLegacyFor(nil, "Bob-AeriePeak") == 0)

print("OK: datatexts_alts_data_test")
