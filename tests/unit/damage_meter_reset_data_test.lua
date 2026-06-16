-- tests/unit/damage_meter_reset_data_test.lua
-- Run: lua tests/unit/damage_meter_reset_data_test.lua
--
-- Guards the "Reset Data" context-menu action: the window config menu must wire
-- a button to C_DamageMeter.ResetAllCombatSessions (Blizzard's only reset entry
-- point, which clears all sessions globally), guarded by an existence check so
-- it no-ops on builds without the API.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a"); file:close()
    return data:gsub("\r\n", "\n")
end

local src = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")

-- The action lives in the config menu.
local menuStart = src:find("function Window:_OpenConfigMenu")
assert(menuStart, "could not locate Window:_OpenConfigMenu")
local menuEnd = src:find("\nfunction Window:", menuStart + 1) or #src
local menu = src:sub(menuStart, menuEnd)

assert(menu:find('CreateButton%(ns%.L%["Reset Data"%]'),
    "config menu must expose a 'Reset Data' button")
assert(menu:find("C_DamageMeter%.ResetAllCombatSessions"),
    "Reset Data must call C_DamageMeter.ResetAllCombatSessions")
assert(menu:find("if C_DamageMeter and C_DamageMeter%.ResetAllCombatSessions"),
    "the reset call must be guarded by an existence check")
assert(src:find("function WindowManager:ClearRuntimeSessionIDs", 1, true),
    "WindowManager must expose ClearRuntimeSessionIDs")
assert(src:find("function Data:ClearCachedViews", 1, true),
    "Data must expose ClearCachedViews")
assert(menu:find("ClearRuntimeSessionIDs", 1, true),
    "Reset Data must clear runtime previous-session selections")
assert(menu:find("ClearCachedViews", 1, true),
    "Reset Data must invalidate cached damage meter views before repaint")

print("OK: damage_meter_reset_data_test")
