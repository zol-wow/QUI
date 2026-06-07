-- tests/unit/cdm_cold_load_snapshot_readiness_test.lua
-- Run: lua tests/unit/cdm_cold_load_snapshot_readiness_test.lua
--
-- Guards the second cold-load race surface after the mirror drain fix:
-- built-in container snapshots must not commit until the tracked settings
-- provider is ready, and every first-login snapshot caller must use the same
-- readiness contract instead of racing its own one-shot timer.

local function readAll(path)
    local handle = assert(io.open(path))
    local text = handle:read("*a")
    handle:close()
    return text:gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function sliceBetween(text, startMarker, stopMarker)
    local startPos = assert(text:find(startMarker, 1, true),
        "expected to find: " .. startMarker)
    local stopPos = stopMarker
        and select(1, text:find(stopMarker, startPos + #startMarker, true))
    return text:sub(startPos, stopPos and (stopPos - 1) or #text)
end

local spelldata = readAll("QUI_CDM/cdm/cdm_spelldata.lua")
local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")

assert(not spelldata:find("MergeBlizzardTrackedEntries", 1, true),
    "cold-load repair must not append Blizzard tracked entries into the authoritative QUI CDM lists")

local snapshotFn = sliceBetween(
    spelldata,
    "function CDMSpellData:SnapshotBlizzardCDM(containerKey)",
    "local function SnapshotUnsetBuiltinContainers")

assert(snapshotFn:find("return false, false", 1, true),
    "SnapshotBlizzardCDM must report not-ready separately from no-op")
assert(snapshotFn:find("return true, true", 1, true),
    "SnapshotBlizzardCDM must report successful snapshots as ready")

local snapshotUnsetFn = sliceBetween(
    spelldata,
    "local function SnapshotUnsetBuiltinContainers()",
    "-- BuildSpellListFromOwned")

assert(snapshotUnsetFn:find("allReady", 1, true),
    "SnapshotUnsetBuiltinContainers must aggregate readiness across built-ins")
assert(snapshotUnsetFn:find("return snapshotted, allReady", 1, true),
    "SnapshotUnsetBuiltinContainers must return both snapshotted and ready state")

local coldReconcileFn = sliceBetween(
    spelldata,
    "function CDMSpellData:RunColdLoadReconcile",
    "function CDMSpellData:ReconcileAllContainers")

assert(coldReconcileFn:find("snapshotReady", 1, true),
    "RunColdLoadReconcile must observe built-in snapshot readiness")
assert(coldReconcileFn:find("C_Timer.After", 1, true),
    "RunColdLoadReconcile must retry while tracked settings are not ready")
assert(coldReconcileFn:find("RunReconcileSequence", 1, true),
    "RunColdLoadReconcile must still run the normal reconcile once ready")
assert(coldReconcileFn:find("COLD_LOAD_SNAPSHOT_RETRY_SLOW_DELAY", 1, true),
    "RunColdLoadReconcile must keep retrying after the fast retry window")

local notReadyPos = coldReconcileFn:find("if not snapshotReady then", 1, true)
local returnPos = notReadyPos and coldReconcileFn:find("return", notReadyPos, true)
local sequencePos = coldReconcileFn:find("RunReconcileSequence", 1, true)
assert(notReadyPos and returnPos and sequencePos and returnPos < sequencePos,
    "RunColdLoadReconcile must not run the normal reconcile until snapshots are ready")

local trySnapshotFn = sliceBetween(
    containers,
    "local function TrySnapshotBuiltInContainers(containerKeys)",
    "local function FinalizeSpecTracking")

assert(not trySnapshotFn:find("ns.CDMComposer.SeedFromBlizzard", 1, true),
    "container spec tracking must route seeding through SnapshotBlizzardCDM")
assert(trySnapshotFn:find("snapshotReady", 1, true),
    "container spec tracking must honor SnapshotBlizzardCDM readiness")

local bootstrapSnapshot = sliceBetween(
    containers,
    "-- Phase A CDM Overhaul: Snapshot Blizzard CDM spell lists into owned DB.",
    "-- Ensure built-in containers with DB tables have enabled=true")

assert(bootstrapSnapshot:find("RetrySnapshotBuiltInContainers", 1, true),
    "the standalone startup snapshot must retry through the centralized readiness path")

print("OK: cdm_cold_load_snapshot_readiness_test")
