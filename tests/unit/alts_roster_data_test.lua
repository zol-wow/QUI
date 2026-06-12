-- tests/unit/alts_roster_data_test.lua
-- Run: lua tests/unit/alts_roster_data_test.lua
local ns = {}
local chunk = assert(loadfile("QUI_Alts/alts/roster_data.lua"))
chunk("QUI", ns)
local RD = ns.Alts.RosterData

assert(RD.FormatGold(0) == "0g")
assert(RD.FormatGold(1234567) == "123g", "floor to gold: " .. RD.FormatGold(1234567))
assert(RD.FormatGold(12345678900) == "1,234,567g", "thousands separators")

assert(RD.FormatPlayed(nil) == "—")
assert(RD.FormatPlayed(90) == "1m")
assert(RD.FormatPlayed(3 * 86400 + 5 * 3600) == "3d 5h")
assert(RD.FormatPlayed(2 * 3600 + 30 * 60) == "2h 30m")

local now = 1000000
assert(RD.FormatLastSeen(nil, now) == "—")
assert(RD.FormatLastSeen(now - 30, now) == "now")
assert(RD.FormatLastSeen(now - 7200, now) == "2h ago")
assert(RD.FormatLastSeen(now - 3 * 86400, now) == "3d ago")

-- BuildRows: sort by a details field
local chars = {
    ["Bob-Realm"] = { details = { level = 70, money = 50000, class = "MAGE" } },
    ["Amy-Realm"] = { details = { level = 80, money = 10000, class = "DRUID" } },
}
local rows = RD.BuildRows(chars, { sortKey = "level", sortDesc = true })
assert(#rows == 2 and rows[1].key == "Amy-Realm", "level desc")
rows = RD.BuildRows(chars, { sortKey = "money", sortDesc = true })
assert(rows[1].key == "Bob-Realm", "money desc")
rows = RD.BuildRows(chars, { sortKey = "name" })
assert(rows[1].key == "Amy-Realm", "name asc")
assert(rows[1].details.class == "DRUID", "row carries details")

assert(RD.TotalGold(chars) == 60000, "total copper")

assert(RD.FormatResetIn(nil, now) == "—")
assert(RD.FormatResetIn(now - 5, now) == "expired")
assert(RD.FormatResetIn(now + 2 * 86400 + 5 * 3600, now) == "2d 5h")
assert(RD.FormatResetIn(now + 90 * 60, now) == "1h 30m")
assert(RD.FormatResetIn(now + 90, now) == "1m")

print("OK: alts_roster_data_test")
