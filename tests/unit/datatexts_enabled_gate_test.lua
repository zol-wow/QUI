-- tests/unit/datatexts_enabled_gate_test.lua
-- Verifies Datapanels:RefreshAll() short-circuits when quiDatatexts.enabled == false.
-- Tests the REAL production guard in modules/datatexts/datapanels.lua.
-- Approach: loads the actual module with minimal WoW stubs; spies on
-- Datapanels:CreatePanel to detect whether the panel-building work ran.
-- Run: lua5.1 tests/unit/datatexts_enabled_gate_test.lua

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]unit[/\\]") or "./"

---------------------------------------------------------------------------
-- Minimal WoW environment stubs (only what datapanels.lua needs at load time)
---------------------------------------------------------------------------
local function noop() end

local function NewFrame()
    local f = {}
    f.RegisterEvent     = noop
    f.UnregisterEvent   = noop
    f.SetScript         = noop
    f.Show              = noop
    f.Hide              = noop
    f.IsShown           = function() return false end
    f.SetSize           = noop
    f.SetPoint          = noop
    f.ClearAllPoints    = noop
    f.SetParent         = noop
    f.SetFrameStrata    = noop
    f.SetFrameLevel     = noop
    f.EnableMouse       = noop
    f.RegisterForDrag   = noop
    f.SetMovable        = noop
    f.SetClampedToScreen = noop
    return f
end

_G.CreateFrame      = function() return NewFrame() end
-- C_Timer.After must NOT invoke its callback during the do-block at load time
-- (RegisterLayoutModeElements is a pure layout helper, irrelevant here).
_G.C_Timer          = { After = noop, NewTicker = function() return { Cancel = noop } end }
_G.SlashCmdList     = {}
_G.InCombatLockdown = function() return false end
_G.UIParent         = NewFrame()

---------------------------------------------------------------------------
-- Minimal QUI namespace
---------------------------------------------------------------------------
local QUICore = { db = nil }     -- db intentionally nil; tests set it below
local ns = {
    Addon   = QUICore,
    LSM     = { Fetch = function() return nil end },
    Helpers = {},
    -- ns.WhenLoggedIn intentionally nil → deferred init block is skipped
    -- ns.Registry intentionally nil → Registry:Register guarded, skipped
}

---------------------------------------------------------------------------
-- Load the REAL module
---------------------------------------------------------------------------
assert(loadfile(ROOT .. "modules/datatexts/datapanels.lua"))("QUI", ns)

local Datapanels = QUICore.Datapanels
assert(Datapanels, "datapanels.lua did not publish QUICore.Datapanels")

---------------------------------------------------------------------------
-- Test harness
---------------------------------------------------------------------------
local failures = 0
local function check(cond, label)
    if cond then
        print("ok   - " .. label)
    else
        failures = failures + 1
        print("FAIL - " .. label)
    end
end

-- Spy on CreatePanel: replace with a counter so we detect whether the
-- post-guard body ran without needing a full WoW frame environment.
local createCalls = 0
Datapanels.CreatePanel = function(self, panelID, config)   -- luacheck: ignore
    createCalls = createCalls + 1
end

---------------------------------------------------------------------------
-- Case 1 (RED before guard): enabled = false → RefreshAll must be a no-op
---------------------------------------------------------------------------
QUICore.db = { profile = { quiDatatexts = { enabled = false, panels = { { id = "p1" } } } } }
createCalls = 0
Datapanels:RefreshAll()
check(createCalls == 0, "enabled=false: RefreshAll must not create panels")

---------------------------------------------------------------------------
-- Case 2: enabled = true → panels must be built
---------------------------------------------------------------------------
QUICore.db = { profile = { quiDatatexts = { enabled = true, panels = { { id = "p1" } } } } }
createCalls = 0
Datapanels:RefreshAll()
check(createCalls == 1, "enabled=true: RefreshAll must create one panel")

---------------------------------------------------------------------------
-- Case 3: enabled absent (nil) → guard must NOT fire (nil ~= false)
---------------------------------------------------------------------------
QUICore.db = { profile = { quiDatatexts = { panels = { { id = "p1" } } } } }
createCalls = 0
Datapanels:RefreshAll()
check(createCalls == 1, "enabled=nil: RefreshAll must build panels (only false gates)")

---------------------------------------------------------------------------
-- Result
---------------------------------------------------------------------------
if failures > 0 then
    io.stderr:write(failures .. " test(s) FAILED\n")
    os.exit(1)
end
print("ok datatexts_enabled_gate")
