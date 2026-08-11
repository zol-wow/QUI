-- tests/unit/resourcebars_trailing_coalesce_test.lua
-- Run: lua tests/unit/resourcebars_trailing_coalesce_test.lua
--
-- The 16ms leading-edge throttle in OnUnitPower dropped the final power
-- event of a burst (stale fill until the next event; worst on the last
-- resource change of a fight). Suppressed updates must queue one trailing
-- drain per burst via a static C_Timer.After closure.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_ResourceBars/resourcebars/resourcebars.lua")

assert(source:find("local function DrainPrimaryPowerUpdate()", 1, true),
    "primary trailing drain must exist")
assert(source:find("local function DrainSecondaryPowerUpdate()", 1, true),
    "secondary trailing drain must exist")
assert(source:find("QueuePrimaryTrailingUpdate()", 1, true),
    "suppressed primary updates must queue a trailing drain")
assert(source:find("QueueSecondaryTrailingUpdate()", 1, true),
    "suppressed secondary updates must queue a trailing drain")

print("PASS resourcebars_trailing_coalesce_test")
