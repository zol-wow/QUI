-- tests/unit/groupframes_trailing_coalesce_test.lua
-- Run: lua tests/unit/groupframes_trailing_coalesce_test.lua
--
-- The per-unit 100ms leading-edge throttles dropped any event landing inside
-- the window — the FINAL health/power/absorb/prediction event of a burst was
-- lost until the next unrelated event, leaving stale bars (worst at combat
-- end). Suppressed events must mark the unit pending and a trailing drain
-- must render it when the window closes (Blizzard dirty-flag pattern,
-- CompactUnitFrame.lua:108).

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_GroupFrames/groupframes/groupframes.lua")

assert(source:find("local function ScheduleTrailingDrain", 1, true),
    "trailing drain scheduler must exist")

-- every suppressed leading-edge branch must schedule instead of dropping
for _, family in ipairs({ "health", "power", "absorb", "healAbsorb", "healPred" }) do
    assert(source:find('ScheduleTrailingDrain("' .. family .. '"', 1, true),
        family .. " throttle branch must schedule a trailing drain")
end

-- the drain must stamp the throttle table so drain + next event re-coalesce
local drainStart = assert(source:find("trailingDrainers[family] = function()", 1, true))
local drainEnd = assert(source:find("local function ScheduleTrailingDrain", drainStart, true))
local drainBody = source:sub(drainStart, drainEnd)
assert(drainBody:find("cachedModuleEnabled", 1, true),
    "drain must respect the cached module-enabled flag")

print("PASS groupframes_trailing_coalesce_test")
