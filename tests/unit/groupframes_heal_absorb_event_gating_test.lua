-- tests/unit/groupframes_heal_absorb_event_gating_test.lua
-- Run: lua tests/unit/groupframes_heal_absorb_event_gating_test.lua
--
-- Regression: "Show Absorb Shield" and "Show Heal Absorb" are independent
-- toggles, but UpdateSelectiveEvents gated UNIT_HEAL_ABSORB_AMOUNT_CHANGED on
-- the absorb flag. Turning Show Absorb Shield off while Show Heal Absorb stayed
-- on unregistered the only event that drives UpdateHealAbsorb, freezing the
-- heal-absorb bar. The heal-absorb event must be gated on its own setting.

local path = "modules/groupframes/groupframes.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local startPos = assert(source:find("UpdateSelectiveEvents = function%(%)"),
    "UpdateSelectiveEvents should exist")
local endPos = assert(source:find("Threat events", startPos, true),
    "UpdateSelectiveEvents threat-events section should follow the absorb gating")
local body = source:sub(startPos, endPos)

-- A dedicated heal-absorb enable flag must be derived from the heal-absorb DB.
assert(body:find("healAbsorbEnabled%s*=%s*vdb"),
    "UpdateSelectiveEvents should derive a healAbsorbEnabled flag")
assert(body:find("vdb%.healAbsorbs"),
    "healAbsorbEnabled should read vdb.healAbsorbs (its own setting)")

-- The heal-absorb event must be gated by that flag, not by the absorb flag.
assert(body:find('"UNIT_HEAL_ABSORB_AMOUNT_CHANGED",%s*healAbsorbEnabled'),
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED should be gated on healAbsorbEnabled")

print("OK: groupframes_heal_absorb_event_gating_test")
