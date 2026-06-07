-- tests/unit/cdm_cross_character_live_container_test.lua
-- Headless regression checks for the shared-profile cross-character live
-- container guard.
-- Run: lua tests/unit/cdm_cross_character_live_container_test.lua
--
-- Bug: with a single AceDB profile shared across characters, the live CDM
-- container (profile.ncdm) is shared too. On a peaceful login the spec-
-- tracking init can defer (spec APIs not ready) and its 1s retry can be
-- cancelled by an early profile/loadout event; no PLAYER_REGEN_ENABLED fires
-- without combat, so the reconcile never runs and the previous character's
-- (even another class's) spells keep rendering. The login path must self-heal
-- by re-running spec tracking, and must force a reconcile when the live
-- container is still owned by another character.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")

-- The cross-character ownership predicate must exist.
assert(
    containers:find("local function LiveContainerOwnedByOtherCharacter", 1, true),
    "a LiveContainerOwnedByOtherCharacter predicate must exist to detect a shared-profile live container last written by a different character"
)

-- Isolate the PLAYER_ENTERING_WORLD isLogin branch.
local loginStart = assert(
    containers:find("elseif isLogin then", 1, true),
    "containers should have a PLAYER_ENTERING_WORLD login branch"
)
local loginEnd = assert(
    containers:find("elseif not isReload then", loginStart, true),
    "login branch should end before the non-reload branch"
)
local loginBranch = containers:sub(loginStart, loginEnd - 1)

-- Self-heal: the login branch must re-run spec tracking rather than only
-- bailing when it isn't ready (peaceful logins get no PLAYER_REGEN_ENABLED).
assert(
    loginBranch:find("InitSpecTracking()", 1, true),
    "the login branch must re-run InitSpecTracking() to self-heal when spec tracking did not finish during the load window"
)

-- Deterministic cross-character guard: the login branch must force a reconcile
-- when the live container is still owned by another character.
assert(
    loginBranch:find("LiveContainerOwnedByOtherCharacter()", 1, true),
    "the login branch must force a reconcile when the shared-profile live container is owned by another character"
)
assert(
    loginBranch:find("LoadOrSnapshotSpecProfile", 1, true),
    "the cross-character guard must reconcile via LoadOrSnapshotSpecProfile so the live container is reloaded for the current character"
)

print("OK: cdm_cross_character_live_container_test")
