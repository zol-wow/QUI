-- tests/unit/cdm_spec_profile_skips_custom_containers_test.lua
-- Run: lua tests/unit/cdm_spec_profile_skips_custom_containers_test.lua
--
-- Regression: custom (customBar) containers keep their curated list in
-- `entries`, which the spec/loadout profile machinery never saves
-- (SaveSpecProfile keys on ownedSpells ~= nil). The restore paths still
-- iterated ALL container keys, so every custom container hit the
-- "wasn't in the saved profile" branch and got ClearContainerSpecState —
-- wiping its dormantSpells on every spec-profile/loadout load (including
-- every login). That destroyed the recovery record of any spell the
-- dormant pass had shelved, turning a transient login race into permanent
-- data loss.
--
-- cdm_containers.lua is not loadable headless; per the established pattern
-- (cdm_cross_character_live_container_test.lua) this test asserts the
-- structure of the source.

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local containers = readAll("modules/cdm/cdm_containers.lua")

-- The predicate must exist and key off the customBar containerType.
assert(
    containers:find("local function IsSpecManagedContainer", 1, true),
    "an IsSpecManagedContainer predicate must exist so spec/loadout machinery can skip entries-based custom containers"
)
local predStart = containers:find("local function IsSpecManagedContainer", 1, true)
local predEnd = containers:find("\nend", predStart, true)
local predBody = containers:sub(predStart, predEnd)
assert(
    predBody:find('containerType ~= "customBar"', 1, true),
    "IsSpecManagedContainer must exclude containerType == \"customBar\" containers"
)

-- Helper to slice a function body out of the source.
local function functionBody(marker)
    local s = assert(
        containers:find(marker, 1, true),
        "expected to find " .. marker
    )
    -- Body ends at the next top-of-line `local function` declaration.
    local e = containers:find("\nlocal function ", s + 1, true) or #containers
    return containers:sub(s, e)
end

-- LoadLoadoutProfile's restore loop must be guarded.
local loadLoadout = functionBody("local function LoadLoadoutProfile")
assert(
    loadLoadout:find("IsSpecManagedContainer(containerDB)", 1, true),
    "LoadLoadoutProfile must skip non-spec-managed (customBar) containers"
)

-- LoadOrSnapshotSpecProfile has TWO destructive sites: the savedProfile
-- restore loop and the fresh-snapshot clear loop. Both must be guarded.
local loadSpec = functionBody("local function LoadOrSnapshotSpecProfile")
local _, guardCount = loadSpec:gsub("IsSpecManagedContainer%(containerDB%)", "")
assert(
    guardCount >= 2,
    "LoadOrSnapshotSpecProfile must guard both the restore loop and the fresh-snapshot clear loop (found "
        .. guardCount .. " guard(s))"
)

-- ResnapshotForCurrentSpec (profile import path) must also skip custom
-- containers: for customBar containers its ownedSpells wipe is a no-op and
-- SnapshotBlizzardCDM no-ops on non-builtin keys, so its only effect there
-- was destroying the dormantSpells recovery shelf.
local resnapStart = assert(
    containers:find("ResnapshotForCurrentSpec = function()", 1, true),
    "expected to find ResnapshotForCurrentSpec"
)
local resnapEnd = assert(
    containers:find("\n    end,", resnapStart, true),
    "expected ResnapshotForCurrentSpec to end"
)
local resnapBody = containers:sub(resnapStart, resnapEnd)
assert(
    resnapBody:find("IsSpecManagedContainer(containerDB)", 1, true),
    "ResnapshotForCurrentSpec must skip non-spec-managed (customBar) containers when clearing"
)
assert(
    resnapBody:find("IsSpecManagedContainer(GetTrackerSettings(key))", 1, true)
        or select(2, resnapBody:gsub("IsSpecManagedContainer%(", "")) >= 2,
    "ResnapshotForCurrentSpec must also skip non-spec-managed containers in the snapshot loop"
)

print("OK: cdm_spec_profile_skips_custom_containers_test")
