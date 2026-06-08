-- tests/unit/cdm_login_loadout_rekey_test.lua
-- Headless regression checks for event-driven initial-login loadout resolution.
-- Run: lua tests/unit/cdm_login_loadout_rekey_test.lua
--
-- Root cause being guarded: on initial login, GetSpecialization() and
-- C_ClassTalents.GetLastSelectedSavedConfigID() are not readable at
-- ADDON_LOADED. GetLastSelectedSavedConfigID is CVar-backed; per
-- Blizzard_ClassTalentsFrame ("CVars are unloaded when we leave the world,
-- so we have to refresh last selected configID after entering the world")
-- it only becomes authoritative at PLAYER_ENTERING_WORLD. The ADDON_LOADED
-- hydration is therefore provisional (char-DB cache, slot 0 when cold) and
-- MUST be re-keyed by events once the live API answers — silently adopting
-- the live configID as baseline leaves the wrong slot rendered all session
-- and saves slot-0-derived state into the real loadout's slot.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")

local function functionBody(marker)
    local s = assert(
        containers:find(marker, 1, true),
        "expected to find " .. marker
    )
    local e = containers:find("\nlocal function ", s + 1, true) or #containers
    return containers:sub(s, e)
end

-- Slice one `elseif event == "X" then` branch out of the runtime OnEvent
-- dispatcher (up to the next `elseif event ==` / closing of the chain).
local function eventBranch(eventName)
    local marker = 'event == "' .. eventName .. '"'
    local s = assert(
        containers:find(marker, 1, true),
        "runtime event dispatcher should handle " .. eventName
    )
    local e = containers:find("elseif event == ", s + #marker, true) or #containers
    return containers:sub(s, e)
end

-- ===== Event registrations (Blizzard_ClassTalentsFrame login pattern) =====

assert(
    containers:find('RegisterEvent("SELECTED_LOADOUT_CHANGED")', 1, true),
    "runtime event frame must register SELECTED_LOADOUT_CHANGED — the precise "
        .. "signal that GetLastSelectedSavedConfigID changed"
)

assert(
    containers:find('RegisterEvent("PLAYER_TALENT_UPDATE")', 1, true),
    "runtime event frame must register PLAYER_TALENT_UPDATE — Blizzard's "
        .. "login-time 'talent data now readable' wake-up (event-driven, not timer)"
)

-- ===== Authoritative re-key latch =====

assert(
    containers:find("local function ResolveInitialLoadoutSlot", 1, true),
    "an initial-loadout resolution latch (ResolveInitialLoadoutSlot) must exist"
)

assert(
    containers:find("_hydratedLoadoutID", 1, true),
    "hydration must record which loadout slot the live containers were "
        .. "actually loaded from, so the latch can detect a provisional mismatch"
)

do
    local hydrate = functionBody("local function LoadOrSnapshotSpecProfile")
    assert(
        hydrate:find("_hydratedLoadoutID = loadoutID", 1, true),
        "LoadOrSnapshotSpecProfile must stamp _hydratedLoadoutID with the slot it hydrated"
    )
end

do
    local resolver = functionBody("local function ResolveInitialLoadoutSlot")
    assert(
        resolver:find("GetLastSelectedSavedConfigID", 1, true),
        "the latch must re-read GetLastSelectedSavedConfigID fresh (CVar-backed)"
    )
    assert(
        resolver:find("LoadLoadoutProfile", 1, true),
        "on mismatch the latch must reload the authoritative loadout slot, "
            .. "not just adopt the new configID as baseline"
    )
    assert(
        resolver:find("SaveLoadoutProfile(_hydratedLoadoutID", 1, true)
            or resolver:find("SaveLoadoutProfile(hydratedSlot", 1, true),
        "on mismatch the latch must save live state back into the slot it was "
            .. "hydrated FROM — never into the authoritative slot (contamination)"
    )
end

-- ===== Wake-up call sites =====

do
    local listUpdated = eventBranch("TRAIT_CONFIG_LIST_UPDATED")
    assert(
        listUpdated:find("ResolveInitialLoadoutSlot", 1, true),
        "TRAIT_CONFIG_LIST_UPDATED must run the resolution latch"
    )
    assert(
        not listUpdated:find("if _lastKnownSavedConfigID == nil then", 1, true),
        "the silent baseline adoption (_lastKnownSavedConfigID = configID with "
            .. "no hydrated-slot comparison and no reload) must be gone"
    )
end

do
    local pew = eventBranch("PLAYER_ENTERING_WORLD")
    assert(
        pew:find("ResolveInitialLoadoutSlot", 1, true),
        "PLAYER_ENTERING_WORLD must run the resolution latch — "
            .. "GetLastSelectedSavedConfigID CVars are only loaded after entering world"
    )
end

do
    local talentUpdate = eventBranch("PLAYER_TALENT_UPDATE")
    assert(
        talentUpdate:find("ResolveInitialLoadoutSlot", 1, true),
        "PLAYER_TALENT_UPDATE must run the resolution latch"
    )
    assert(
        talentUpdate:find("InitSpecTracking", 1, true),
        "PLAYER_TALENT_UPDATE must self-heal spec tracking when spec was not "
            .. "readable earlier (Blizzard's CheckSetSelectedConfigID retry pattern)"
    )
end

do
    local selectedChanged = eventBranch("SELECTED_LOADOUT_CHANGED")
    assert(
        selectedChanged:find("ResolveInitialLoadoutSlot", 1, true),
        "SELECTED_LOADOUT_CHANGED must run the resolution latch when still unresolved"
    )
end

-- ===== Storage keying hygiene =====

do
    local save = functionBody("local function SaveSpecProfileToLoadout")
    assert(
        save:find("loadoutID = NormalizeLoadoutID(loadoutID)", 1, true),
        "SaveSpecProfileToLoadout must normalize at entry — raw "
            .. "STARTER_BUILD_TRAIT_CONFIG_ID (-2) from GetLastSelectedSavedConfigID "
            .. "must key slot 0, never a literal -2 slot"
    )
end

do
    local load = functionBody("local function LoadLoadoutProfile")
    assert(
        load:find("loadoutID = NormalizeLoadoutID(loadoutID)", 1, true),
        "LoadLoadoutProfile must normalize at entry (same -2 keying hazard)"
    )
end

-- ===== Profile-switch re-arm =====

do
    local sync = functionBody("local function SyncCurrentProfileSpecState")
    assert(
        sync:find("_initialLoadoutResolved = false", 1, true),
        "profile switch must re-arm the resolution latch — the new profile may "
            .. "have perLoadoutSpec set differently"
    )
end

print("cdm_login_loadout_rekey_test: OK")
