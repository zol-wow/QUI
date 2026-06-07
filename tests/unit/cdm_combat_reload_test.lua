-- tests/unit/cdm_combat_reload_test.lua
-- Headless regression checks for CDM combat-/reload initialization.
-- Run: lua tests/unit/cdm_combat_reload_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function countPlain(text, needle)
    local count = 0
    local pos = 1
    while true do
        local found = string.find(text, needle, pos, true)
        if not found then
            break
        end
        count = count + 1
        pos = found + #needle
    end
    return count
end

local mirror = readAll("QUI_CDM/cdm/cdm_blizz_mirror.lua")
local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")

local safeWindowGate = "if InCombatLockdown() and not (ns and ns._inInitSafeWindow) then"
assert(
    countPlain(mirror, safeWindowGate) >= 3,
    "mirror combat walk gates should allow the ADDON_LOADED/PEW init safe window"
)

local reloadStart = assert(
    string.find(containers, "if isReload then", 1, true),
    "containers should have a PLAYER_ENTERING_WORLD reload branch"
)
local loginStart = assert(
    string.find(containers, "elseif isLogin then", reloadStart, true),
    "reload branch should end before login branch"
)
local reloadBranch = string.sub(containers, reloadStart, loginStart - 1)

local rescanPos = string.find(reloadBranch, "CDMBlizzMirror.ForceRescan", 1, true)
local refreshPos = string.find(reloadBranch, "RefreshAll(true)", 1, true)
assert(rescanPos, "combat reload PEW branch should force a mirror rescan")
assert(refreshPos, "combat reload PEW branch should run synchronous layout")
assert(
    rescanPos < refreshPos,
    "combat reload PEW branch should rescan the mirror before synchronous layout"
)

print("OK: cdm_combat_reload_test")
