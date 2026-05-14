-- tests/cdm_spec_tracking_persistence_test.lua
-- Headless regression checks for CDM spec-cache scoping.
-- Run: lua tests/cdm_spec_tracking_persistence_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local containers = readAll("modules/cdm/cdm_containers.lua")

assert(
    containers:find("GetCurrentCharacterKey", 1, true),
    "CDM spec tracking should derive a current character key"
)

assert(
    containers:find("_lastSpecCharKey", 1, true),
    "cached _lastSpecID should be scoped by character key"
)

assert(
    containers:find("cachedCharKey == currentCharKey", 1, true),
    "cached spec fallback should only trust a cache written by this character"
)

assert(
    containers:find("db._lastSpecCharKey = currentCharKey", 1, true),
    "cross-session detection should persist the character key with _lastSpecID"
)

assert(
    containers:find("local specDB = GetSpecStateDB(true)", 1, true),
    "spec change events should persist _lastSpecID through the character-scoped state helper"
)

assert(
    containers:find("local shouldLoadActiveSpec = true", 1, true),
    "initial login should hydrate the active spec from scoped storage even when no prior spec stamp exists"
)

local snapshotPos = containers:find("local snapshotReady = TrySnapshotBuiltInContainers(containerKeys)", 1, true)
assert(
    snapshotPos and containers:find("SaveSpecProfile(specID)", snapshotPos, true),
    "fresh snapshots should be saved into the scoped spec profile store immediately"
)

assert(
    containers:find("StampActiveProfileSpecOwner", 1, true),
    "hydrating or saving the active spec should stamp which character owns the profile's live containers"
)

assert(
    containers:find("liveStateOwnedByCurrentChar", 1, true),
    "cross-session detection should not save another character's live containers into this character's spec store"
)

assert(
    containers:find("GetSpecProfileStore", 1, true),
    "CDM spec spell profiles should resolve through a scoped store helper"
)

assert(
    containers:find("_specProfilesByProfile", 1, true),
    "CDM spec spell profiles should be stored per character and per AceDB profile"
)

assert(
    containers:find("GetCurrentProfile", 1, true),
    "CDM spec spell profile storage should include the active AceDB profile name"
)

assert(
    containers:find("for k, v in pairs(specData) do", 1, true),
    "SaveSpecProfile should write per-container into the (specID, loadoutID) loadout slot rather than wholesale-replacing store[specID]"
)

assert(
    not containers:find("db._specProfiles[specID] = specData", 1, true),
    "SaveSpecProfile must not write spec spell lists into shared profile ncdm._specProfiles"
)

assert(
    not containers:find("return db._specProfiles", 1, true),
    "spec profile storage must not fall back to the shared profile ncdm._specProfiles table"
)

-- ===== LOADOUT TRACKING (Phase 1 LDST-01..04 / LDEV-01..05) =====

assert(
    containers:find("GetEffectiveLoadoutID", 1, true),
    "GetEffectiveLoadoutID single-chokepoint resolver must exist (LDST-04)"
)

assert(
    containers:find("GetSpecLoadoutProfileStore", 1, true),
    "GetSpecLoadoutProfileStore single-chokepoint store accessor must exist (LDST-01)"
)

assert(
    containers:find("GetLastSelectedSavedConfigID", 1, true),
    "stable loadout ID must be sourced from GetLastSelectedSavedConfigID (LDST-04)"
)

assert(
    not containers:find("GetActiveConfigID(", 1, true),
    "GetActiveConfigID() must NEVER appear in cdm_containers.lua — it returns ephemeral staging IDs that create orphaned storage keys (LDST-04)"
)

assert(
    containers:find("NO_SAVED_LOADOUT_ID", 1, true),
    "named sentinel constant NO_SAVED_LOADOUT_ID (= -2 STARTER_BUILD_TRAIT_CONFIG_ID) must be defined and used by GetEffectiveLoadoutID (LDST-04)"
)

assert(
    containers:find("_lastKnownSavedConfigID", 1, true),
    "_lastKnownSavedConfigID upvalue must exist for the before/after compare that filters in-place talent edits (LDEV-01)"
)

assert(
    containers:find("loadoutListReady", 1, true),
    "loadoutListReady flag must exist; TRAIT_CONFIG_LIST_UPDATED flips it to true (LDEV-04)"
)

assert(
    containers:find("pendingLoadoutRefresh", 1, true),
    "pendingLoadoutRefresh deferred-combat flag must exist; PLAYER_REGEN_ENABLED drains it (LDEV-03)"
)

assert(
    containers:find("loadoutTrackingToken", 1, true),
    "loadoutTrackingToken abort token must exist; parallels specTrackingRetryToken (LDEV-05)"
)

assert(
    containers:find("_lastLoadoutConfigID", 1, true),
    "_lastLoadoutConfigID char-DB cache key must exist; provides combat-reload fast path when live API returns nil (LDEV-04)"
)

do
    local effLoadoutStart = containers:find("local function GetEffectiveLoadoutID", 1, true)
    local effLoadoutEnd = effLoadoutStart and containers:find("\nend", effLoadoutStart, true)
    local effLoadoutBody = effLoadoutStart and effLoadoutEnd and containers:sub(effLoadoutStart, effLoadoutEnd)
    assert(
        effLoadoutBody and effLoadoutBody:find("_lastLoadoutConfigID", 1, true),
        "GetEffectiveLoadoutID must CONSUME the _lastLoadoutConfigID cache as fallback when the live API returns nil — not just populate it (LDEV-04 read path)"
    )
end

assert(
    containers:find("TRAIT_CONFIG_UPDATED", 1, true),
    "TRAIT_CONFIG_UPDATED event must be registered and dispatched in CDM (LDEV-01)"
)

assert(
    containers:find("ACTIVE_COMBAT_CONFIG_CHANGED", 1, true),
    "ACTIVE_COMBAT_CONFIG_CHANGED event must be registered and dispatched in CDM (LDEV-02)"
)

assert(
    containers:find("TRAIT_CONFIG_LIST_UPDATED", 1, true),
    "TRAIT_CONFIG_LIST_UPDATED event must be registered and dispatched in CDM (LDEV-04)"
)

assert(
    containers:find("perLoadoutSpec", 1, true),
    "perLoadoutSpec toggle key must be read from db.profile.ncdm by GetEffectiveLoadoutID (LDST-02)"
)

assert(
    containers:find("SeedActiveLoadoutFromSharedSlot", 1, true),
    "SeedActiveLoadoutFromSharedSlot helper must exist in cdm_containers.lua (Plan 02-01 / LDUX-05)"
)

assert(
    containers:find("RegisterLoadoutChangeCallback", 1, true),
    "RegisterLoadoutChangeCallback helper must exist in cdm_containers.lua (Plan 02-01 / D-06)"
)

assert(
    containers:find("_loadoutChangeCallbacks", 1, true),
    "_loadoutChangeCallbacks upvalue must exist in cdm_containers.lua (Plan 02-01 / D-06)"
)

print("OK: cdm_spec_tracking_persistence_test")
