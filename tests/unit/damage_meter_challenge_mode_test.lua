-- tests/unit/damage_meter_challenge_mode_test.lua
-- Run: lua tests/unit/damage_meter_challenge_mode_test.lua
--
-- Guards Mythic+ lifecycle behavior:
--   * optional reset on CHALLENGE_MODE_START
--   * optional Current/Overall swap at start/completion/reset
--   * behavior options are exposed in defaults and settings

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local coreSrc = readAll("QUI_DamageMeter/damage_meter/damage_meter.lua")
local defaultsSrc = readAll("core/defaults.lua")
local contentSrc = readAll("QUI_DamageMeter/damage_meter/settings/damage_meter_content.lua")
local challengeStartPos = coreSrc:find("function WindowManager:ApplyChallengeModeStart", 1, true)
assert(challengeStartPos, "WindowManager must expose ApplyChallengeModeStart")
local challengeCompletedPos = coreSrc:find("function WindowManager:ApplyChallengeModeCompleted", challengeStartPos, true)
assert(challengeCompletedPos, "WindowManager must expose ApplyChallengeModeCompleted")
local challengeStartBlock = coreSrc:sub(challengeStartPos, challengeCompletedPos - 1)

local nativeStart = defaultsSrc:find("native = {", 1, true)
assert(nativeStart, "could not locate damageMeter.native defaults")
local nativeEnd = defaultsSrc:find("\n%s*alerts%s*=", nativeStart) or #defaultsSrc
local nativeBlock = defaultsSrc:sub(nativeStart, nativeEnd)

assert(nativeBlock:find("autoResetOnChallengeStart", 1, true),
    "defaults must expose autoResetOnChallengeStart")
assert(nativeBlock:find("autoSwapChallengeSessions", 1, true),
    "defaults must expose autoSwapChallengeSessions")

assert(contentSrc:find("autoResetOnChallengeStart", 1, true),
    "settings must expose autoResetOnChallengeStart")
assert(contentSrc:find("autoSwapChallengeSessions", 1, true),
    "settings must expose autoSwapChallengeSessions")
assert(contentSrc:find("Auto Reset on Key Start", 1, true),
    "settings must label the key-start reset option")
assert(contentSrc:find("Auto Swap Current/Overall", 1, true),
    "settings must label the key lifecycle swap option")

assert(coreSrc:find('RegisterEvent("CHALLENGE_MODE_START"', 1, true),
    "damage meter must listen for CHALLENGE_MODE_START")
assert(coreSrc:find('RegisterEvent("CHALLENGE_MODE_COMPLETED"', 1, true),
    "damage meter must listen for CHALLENGE_MODE_COMPLETED")
assert(coreSrc:find('RegisterEvent("CHALLENGE_MODE_RESET"', 1, true),
    "damage meter must listen for CHALLENGE_MODE_RESET")
assert(coreSrc:find("autoResetOnChallengeStart", 1, true),
    "CHALLENGE_MODE_START handler must consult autoResetOnChallengeStart")
assert(coreSrc:find("autoSwapChallengeSessions", 1, true),
    "challenge lifecycle handler must consult autoSwapChallengeSessions")
assert(challengeStartBlock:find("s.enabled", 1, true),
    "CHALLENGE_MODE_START must be inert when damageMeter.native.enabled is false")
assert(coreSrc:find("C_DamageMeter.ResetAllCombatSessions", 1, true),
    "key-start reset must call C_DamageMeter.ResetAllCombatSessions")
assert(coreSrc:find("function Data:ResetCombatClock", 1, true),
    "damage meter must reset its local combat timer when session data is reset")
assert(coreSrc:find("function WindowManager:ApplyChallengeModeReset", 1, true),
    "WindowManager must expose ApplyChallengeModeReset")

print("OK: damage_meter_challenge_mode_test")
