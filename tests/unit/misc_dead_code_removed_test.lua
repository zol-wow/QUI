-- tests/unit/misc_dead_code_removed_test.lua
-- Run: lua tests/unit/misc_dead_code_removed_test.lua
--
-- Small dead-code removals, each verified by tree-wide grep (zero callers).
-- (.luacheckrc ignores W211, so these unused locals were never auto-flagged.)
--   * core/utils.lua  local GetCore()        — superseded by Helpers.GetCore()
--   * core/utils.lua  Helpers.FindAnchorFrame — zero callers anywhere
--   * QUI_QoL/qol/crosshair.lua CreateOnUpdateThrottle import — never used
--   * QUI_QoL/utility/keybinds.lua ForceRebuildButtonCache — zero callers anywhere
--   * QUI_Minimap/minimap/minimap.lua ApplyMinimapButtonBackground — zero callers anywhere

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local utils = readAll("core/utils.lua")
local crosshair = readAll("QUI_QoL/qol/crosshair.lua")
local keybinds = readAll("QUI_QoL/utility/keybinds.lua")
local minimap = readAll("QUI_Minimap/minimap/minimap.lua")

assert(not utils:find("local function GetCore()", 1, true),
    "shadowed local GetCore() must be removed (callers use Helpers.GetCore)")
assert(utils:find("function Helpers.GetCore()", 1, true),
    "the live Helpers.GetCore must remain")
assert(not utils:find("FindAnchorFrame", 1, true),
    "uncalled Helpers.FindAnchorFrame must be removed")
assert(not crosshair:find("CreateOnUpdateThrottle", 1, true),
    "unused CreateOnUpdateThrottle import must be removed from crosshair.lua")
assert(not keybinds:find("ForceRebuildButtonCache", 1, true),
    "uncalled ForceRebuildButtonCache must be removed from keybinds.lua")
assert(not minimap:find("ApplyMinimapButtonBackground", 1, true),
    "uncalled ApplyMinimapButtonBackground must be removed from minimap.lua")

print("misc_dead_code_removed_test: OK")
