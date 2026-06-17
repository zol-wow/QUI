-- tests/unit/cdm_containers_combat_end_refresh_coalesce_test.lua
-- Run: lua tests/unit/cdm_containers_combat_end_refresh_coalesce_test.lua
--
-- Structural regression (cdm_containers is too dependency-heavy to instantiate
-- headlessly; the suite asserts source structure -- see cdm_combat_reload_test).
-- RefreshAll must coalesce duplicate same-frame calls: a guard checked at the top
-- of the function body BEFORE CancelRefreshTimers, set true then reset on the next
-- frame via C_Timer.After(0). Without it, two combat-end drainers (a DATA_LOADED
-- spelldata change-callback and the spec-tracking finalize) run the full teardown
-- twice in one frame.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")

-- The guard local must be declared (file scope: visible to the function + closure).
assert(string.find(containers, "_refreshAllFrameGuard", 1, true),
    "RefreshAll coalescing guard local _refreshAllFrameGuard must be declared")

-- Slice the RefreshAll body from its definition to the first CancelRefreshTimers()
-- (where the heavy teardown begins).
local fnStart = assert(string.find(containers, "RefreshAll = function(forceSync)", 1, true),
    "RefreshAll function definition should exist")
local cancelPos = assert(string.find(containers, "CancelRefreshTimers()", fnStart, true),
    "RefreshAll should call CancelRefreshTimers()")
local body = string.sub(containers, fnStart, cancelPos)

-- The guard early-return + set must appear BEFORE CancelRefreshTimers, in order.
local guardCheck = assert(string.find(body, "if _refreshAllFrameGuard then", 1, true),
    "RefreshAll must early-return on _refreshAllFrameGuard before CancelRefreshTimers")
local guardSet = assert(string.find(body, "_refreshAllFrameGuard = true", 1, true),
    "RefreshAll must set _refreshAllFrameGuard = true after passing the guard")
assert(guardCheck < guardSet, "the guard check must precede setting the guard")

-- The guard must reset on the next frame via C_Timer.After(0, ...).
assert(string.find(body, "C_Timer.After(0", 1, true)
    and string.find(body, "_refreshAllFrameGuard = false", 1, true),
    "RefreshAll must reset _refreshAllFrameGuard on the next frame via C_Timer.After(0)")

print("OK: cdm_containers_combat_end_refresh_coalesce_test")
