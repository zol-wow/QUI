-- tests/unit/cdm_challenge_mode_combat_recovery_test.lua
-- Regression: a Mythic+ key that starts while the player is in combat must
-- still recover its CDM display once combat ends.
--
-- cdm_containers.lua's CHALLENGE_MODE_START handler restores incorrectly-shelved
-- dormant spells + reconciles + refreshes, but only `if not InCombatLockdown()`
-- at +0.5s. Its comment claims "If already in combat, PLAYER_REGEN_ENABLED
-- handles recovery" — but the handler sets NO pending flag, and the
-- PLAYER_REGEN_ENABLED handler only drains spec-tracking / loadout / mouse-sync
-- flags. So pulling within ~0.5s of the key starting drops the recovery
-- permanently: spells stay shelved / durations stay stale until /reload.
--
-- Contract (combat-defer-with-drain, the pattern cdm_blizz_mirror.lua already
-- uses via _walkPendingOnRegen): when the recovery can't run because of combat,
-- set a pending flag, and have PLAYER_REGEN_ENABLED drain it by running the
-- same recovery.
--
-- Run from repo root: lua tests/unit/cdm_challenge_mode_combat_recovery_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")

-- Slice an `elseif event == "<NAME>" then` branch out of the runtime event
-- handler: from its guard to the next `elseif event ==` (or end of file).
local function eventBranch(name)
    local marker = 'elseif event == "' .. name .. '" then'
    local startPos = assert(
        string.find(containers, marker, 1, true),
        "expected a " .. name .. " branch in cdm_containers.lua runtime handler"
    )
    local nextPos = string.find(containers, "elseif event ==", startPos + #marker, true)
    return containers:sub(startPos, (nextPos or (#containers + 1)) - 1)
end

local challengeBranch = eventBranch("CHALLENGE_MODE_START")
local regenBranch = eventBranch("PLAYER_REGEN_ENABLED")

-- Sanity: CHALLENGE_MODE_START is the handler that runs the dormant-restore
-- recovery in the first place.
assert(
    string.find(challengeBranch, "CheckAllDormantSpells", 1, true),
    "expected CHALLENGE_MODE_START to run the CheckAllDormantSpells recovery"
)

local PENDING_FLAG = "_challengeModeRecoveryPending"

-- REGRESSION 1: when CHALLENGE_MODE_START cannot recover (player in combat),
-- it must record a pending flag instead of dropping the recovery.
assert(
    string.find(challengeBranch, PENDING_FLAG, 1, true),
    "CHALLENGE_MODE_START must set " .. PENDING_FLAG .. " when it cannot recover "
        .. "in combat, instead of silently dropping the dormant-restore + refresh."
)

-- REGRESSION 2: PLAYER_REGEN_ENABLED must drain that pending flag AND actually
-- re-run the recovery, so an in-combat key start recovers without a /reload.
assert(
    string.find(regenBranch, PENDING_FLAG, 1, true),
    "PLAYER_REGEN_ENABLED must drain " .. PENDING_FLAG .. " so an in-combat key "
        .. "start still recovers when combat ends."
)
assert(
    string.find(regenBranch, "CheckAllDormantSpells", 1, true),
    "PLAYER_REGEN_ENABLED must run the dormant-restore recovery when draining the "
        .. "pending challenge-mode flag (the comment's promise must be backed by code)."
)

print("OK: cdm_challenge_mode_combat_recovery_test")
