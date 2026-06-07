-- tests/unit/cdm_cold_load_reconcile_snapshot_test.lua
-- Run: lua tests/unit/cdm_cold_load_reconcile_snapshot_test.lua
--
-- Regression: alpha54 introduced a cold-login grace window that suppresses
-- early CooldownViewer rebuilds. If the first snapshot/reconcile runs while
-- the viewer is still settling, built-in buff entries can remain unsnapshotted
-- until /reload. The cold-load reconcile must retry nil ownedSpells snapshots
-- after the grace window has ended.

local function readAll(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text:gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function sliceBetween(text, startMarker, stopMarker)
    local startPos = assert(text:find(startMarker, 1, true),
        "expected to find: " .. startMarker)
    local stopPos = stopMarker
        and select(1, text:find(stopMarker, startPos + #startMarker, true))
    return text:sub(startPos, (stopPos or (#text + 1)) - 1)
end

local spelldata = readAll("QUI_CDM/cdm/cdm_spelldata.lua")
local mirror = readAll("QUI_CDM/cdm/cdm_blizz_mirror.lua")

local coldReconcile = sliceBetween(
    spelldata,
    "function CDMSpellData:RunColdLoadReconcile()",
    "function CDMSpellData:ReconcileAllContainers()")

local snapshotPos = coldReconcile:find("SnapshotUnsetBuiltinContainers", 1, true)
local sequencePos = coldReconcile:find("RunReconcileSequence", 1, true)
local notReadyPos = coldReconcile:find("if not snapshotReady then", 1, true)
local notReadyReturnPos = notReadyPos and coldReconcile:find("return", notReadyPos, true)

assert(snapshotPos,
    "cold-load reconcile must retry unsnapshotted built-in containers")
assert(sequencePos,
    "cold-load reconcile must still run the normal dormant/reconcile sequence")
assert(snapshotPos < sequencePos,
    "cold-load snapshot retry must happen before dormant cleanup/reconcile")
assert(notReadyPos and notReadyReturnPos and notReadyReturnPos < sequencePos,
    "cold-load reconcile must not run dormant cleanup/reconcile while snapshots are not ready")
assert(coldReconcile:find("COLD_LOAD_SNAPSHOT_RETRY_SLOW_DELAY", 1, true),
    "cold-load reconcile must keep retrying after the fast retry window")

local playerLoginBranch = sliceBetween(
    mirror,
    'if event == "PLAYER_LOGIN" then',
    "-- Suppress non-LOGIN catalog reshapes")

local clearPos = playerLoginBranch:find("ns._cdmColdLoadActive = false", 1, true)
local reconcilePos = playerLoginBranch:find("sd:RunColdLoadReconcile()", 1, true)

assert(clearPos,
    "PLAYER_LOGIN deferred cold-load callback must clear the grace flag")
assert(reconcilePos,
    "PLAYER_LOGIN deferred cold-load callback must run spelldata reconcile")
assert(clearPos < reconcilePos,
    "clear cold-load grace before reconcile so suppressed refresh work can drain")

print("OK: cdm_cold_load_reconcile_snapshot_test")
