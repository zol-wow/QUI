-- tests/unit/groupframes_ready_check_initial_icons_test.lua
-- Run: lua tests/unit/groupframes_ready_check_initial_icons_test.lua
--
-- Regression: READY_CHECK fires with arg1 = initiatorName (a player NAME, a
-- string — verified against the WoW event docs), NOT a unit token. OnEvent's
-- `if type(arg1) == "string"` fast path looked the name up in unitFrameMap,
-- missed, and bailed (`if not frames then return end`) before reaching the
-- all-frames READY_CHECK handler, which lived in the non-unit section and was
-- therefore unreachable. Result: no frame showed the initial "waiting" icon
-- when a ready check started. READY_CHECK must be handled BEFORE the fast path,
-- and the dead branch removed.

local path = "QUI_GroupFrames/groupframes/groupframes_roster.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local fastPathPos = assert(source:find('if type(arg1) == "string" then', 1, true),
    "OnEvent unit-token fast path should exist")

-- A dedicated, statement-level READY_CHECK handler must exist...
local readyCheckPos = assert(source:find('\n%s*if event == "READY_CHECK" then'),
    "READY_CHECK should have a dedicated handler")

-- ...and it must run BEFORE the unit-token fast path would bail on the name.
assert(readyCheckPos < fastPathPos,
    "READY_CHECK must be handled before the type(arg1)=='string' fast path")

-- The old unreachable branch must be gone.
assert(not source:find('event == "READY_CHECK" or event == "READY_CHECK_CONFIRM"', 1, true),
    "the unreachable READY_CHECK/READY_CHECK_CONFIRM branch should be removed")

print("OK: groupframes_ready_check_initial_icons_test")
