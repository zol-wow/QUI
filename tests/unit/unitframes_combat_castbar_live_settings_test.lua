-- tests/unit/unitframes_combat_castbar_live_settings_test.lua
-- Run: lua tests/unit/unitframes_combat_castbar_live_settings_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local unitframes = readAll("modules/unitframes/unitframes.lua")
local castbar = readAll("modules/unitframes/castbar.lua")

assert(castbar:find("function QUI_Castbar:ApplyLiveCastbarSettings", 1, true),
    "castbar module should expose a live settings refresh that does not recreate frames")

local helperStart = assert(unitframes:find("local function ApplyExistingCastbarLiveSettings%(unitKey%)"),
    "unitframes should define a combat-safe existing-castbar settings helper")
local helperEnd = assert(unitframes:find("local function IsTargetHealthDirectionInverted", helperStart, true),
    "test should find the end of ApplyExistingCastbarLiveSettings")
local helperBody = unitframes:sub(helperStart, helperEnd)

assert(helperBody:find("QUI_Castbar:ApplyLiveCastbarSettings", 1, true),
    "combat-safe helper should use the castbar live settings path")
assert(not helperBody:find("RefreshCastbar", 1, true),
    "combat-safe helper must not destroy or recreate castbars")

local combatStart = assert(unitframes:find("if InCombatLockdown() and not inInitSafeWindow then", 1, true),
    "RefreshFrame should have a combat early-return branch")
local combatEnd = assert(unitframes:find("local settings = GetUnitSettings(unitKey)", combatStart, true),
    "test should find the end of the combat early-return branch")
local combatBody = unitframes:sub(combatStart, combatEnd)

local updateFramePos = assert(combatBody:find("UpdateFrame(frame)", 1, true),
    "combat branch should keep updating non-secure frame data")
local castbarLivePos = assert(combatBody:find("ApplyExistingCastbarLiveSettings(unitKey)", 1, true),
    "combat branch should refresh existing castbar live settings before returning")
local returnPos = assert(combatBody:find("return", 1, true),
    "combat branch should return after safe updates")

assert(updateFramePos < castbarLivePos and castbarLivePos < returnPos,
    "combat branch should update frame data, refresh live castbar settings, then return")

print("OK: unitframes_combat_castbar_live_settings_test")
