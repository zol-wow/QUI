-- tests/unit/skyriding_thrill_secret_retention_test.lua
-- Run: lua tests/unit/skyriding_thrill_secret_retention_test.lua
--
-- RefreshThrillOfTheSkiesBuffState cleared hasThrillOfTheSkiesBuff before a
-- GetPlayerAuraBySpellID lookup that returns a gated nil while auras are
-- restricted (gated nil ≠ buff faded), so the vigor bar dropped its Thrill
-- color mid-flight in combat. Gate on secrecy and retain the last state.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("modules/qol/skyriding.lua")

local fnStart = assert(source:find("local function RefreshThrillOfTheSkiesBuffState()", 1, true))
local clearIdx = assert(source:find("hasThrillOfTheSkiesBuff = false", fnStart, true))
local gateIdx = source:find("ShouldAurasBeSecret", fnStart, true)

assert(gateIdx, "RefreshThrillOfTheSkiesBuffState must gate on aura secrecy")
assert(gateIdx < clearIdx,
    "secrecy gate must run BEFORE the destructive clear of hasThrillOfTheSkiesBuff")

print("PASS skyriding_thrill_secret_retention_test")
