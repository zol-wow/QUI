-- tests/unit/craftingorders_filter_resetx_strata_test.lua
-- Run: lua tests/unit/craftingorders_filter_resetx_strata_test.lua
--
-- Regression guard: the crafting-orders filter dropdown's reset "X"
-- (ResetButton) must reflect the real filter state on a fresh open.
--
-- Diagnosed in-game: the X is NOT occluded (it sits at frame level 9, well above
-- the QUI backdrop) -- it is genuinely SetShown(false). Blizzard's
-- WowDropdownFilterBehaviorMixin:ValidateResetState() shows it only when a filter
-- is non-default, and on a fresh open the dropdown's first OnShow can run that
-- validate before InitFilterDropdown (Blizzard_ProfessionsCustomerOrdersBrowse-
-- Orders.lua) wires the isDefault callback -- so an already-active filter's X
-- stays hidden until the next validate (a menu click). The skin must re-run
-- ValidateResetState once after skinning so the X reflects the real state.
--
-- (The backdrop is also lowered below the dropdown's children as general
-- hygiene, but that is NOT what fixes the reset-X -- this was a show bug.)

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("modules/skinning/frames/craftingorders.lua")

assertContains(
    source,
    "dropdown.ValidateResetState",
    "CO filter skinning must re-validate the reset-X state after skinning")

assertContains(
    source,
    "pcall(dropdown.ValidateResetState, dropdown)",
    "CO reset-X re-validate must be guarded and run against the live dropdown")

print("OK: craftingorders_filter_resetx_strata_test")
