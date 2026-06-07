-- tests/unit/cdm_cold_load_viewer_readiness_test.lua
-- Run: lua tests/unit/cdm_cold_load_viewer_readiness_test.lua
--
-- Regression (alpha54 -> alpha77): the PLAYER_LOGIN cold-load handler in
-- cdm_blizz_mirror.lua opens a 2s grace window that SUPPRESSES every
-- COOLDOWN_VIEWER_DATA_LOADED / SPELLS_CHANGED, then runs ONE deferred
-- Walk + RunColdLoadReconcile on a blind C_Timer.After(2.0) timer and
-- clears the grace unconditionally -- with no check that the CooldownViewer
-- is actually loaded.
--
-- Per Blizzard CooldownViewerDocumentation, C_CooldownViewer.IsCooldownViewerAvailable()
-- is the global readiness signal (the FrameXML CooldownViewerMixin:ShouldBeShown
-- gates on it) and C_CooldownViewer.GetCooldownViewerCooldownInfo is documented
-- MayReturnNothing. If the single cold-load reconcile commits while the viewer is
-- still settling, the built-in buff (TrackedBuff/TrackedBar) container can be built
-- empty and -- because the events that would rebuild it were suppressed -- stay
-- blank until /reload. v3.6.0-alpha53 had no grace window and rebuilt on every
-- COOLDOWN_VIEWER_DATA_LOADED, so it recovered automatically.
--
-- The cold-load finalize must therefore GATE on viewer readiness and RETRY
-- while it is unavailable, instead of finalizing on one fixed timer. Rebuild
-- events that fire during the grace window must also be DEFERRED and drained,
-- not dropped; that preserves alpha53's later rebuild behavior without
-- reintroducing visible intermediate cold-load flicker.

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

local function countPlain(text, needle)
    local count, pos = 0, 1
    while true do
        local found = text:find(needle, pos, true)
        if not found then break end
        count = count + 1
        pos = found + #needle
    end
    return count
end

local mirror = readAll("QUI_CDM/cdm/cdm_blizz_mirror.lua")

local loginBranch = sliceBetween(
    mirror,
    'if event == "PLAYER_LOGIN" then',
    "-- Suppress non-LOGIN catalog reshapes")

-- 1. The finalize must consult the documented readiness signal before it
--    commits the single cold-load reconcile.
assert(loginBranch:find("IsCooldownViewerAvailable", 1, true),
    "cold-load finalize must gate on C_CooldownViewer.IsCooldownViewerAvailable() "
    .. "before committing the single Walk/reconcile")

-- 2. When the viewer is not yet available the finalize must RESCHEDULE itself
--    (so the suppressed rebuild work is not lost), not finalize on one fixed
--    timer. A readiness-gated retry implies more than one C_Timer.After in the
--    branch (the initial delay plus the retry tick).
assert(countPlain(loginBranch, "C_Timer.After") >= 2,
    "cold-load finalize must retry on a timer while the viewer is unavailable, "
    .. "not run a single blind C_Timer.After(2.0)")

-- 3. The grace flag must still be cleared before the reconcile runs (existing
--    contract: suppressed refresh work drains after the flag clears).
local clearPos = loginBranch:find("ns._cdmColdLoadActive = false", 1, true)
local reconcilePos = loginBranch:find("sd:RunColdLoadReconcile()", 1, true)
assert(clearPos, "cold-load finalize must clear the grace flag")
assert(reconcilePos, "cold-load finalize must run the spelldata reconcile")
assert(clearPos < reconcilePos,
    "clear the cold-load grace before the reconcile so suppressed refresh work can drain")

-- 4. Cold-load rebuild events must be recorded and drained after the grace
--    window. Dropping them is the alpha54 regression pattern.
assert(mirror:find("_coldLoadDeferredMirrorRefreshPending", 1, true),
    "cold-load rebuilds must be tracked instead of dropped")

local eventFrameColdLoad = sliceBetween(
    mirror,
    "-- Suppress non-LOGIN catalog reshapes during the cold-load grace",
    "if InCombatLockdown()")
assert(eventFrameColdLoad:find("MarkColdLoadDeferredMirrorRefresh()", 1, true),
    "mirror event-frame reshapes during cold-load must mark a deferred refresh")

local brokerBranch = sliceBetween(
    mirror,
    'ns.CDMIndex.Subscribe("blizz_mirror"',
    "end, 10)")
local brokerColdLoad = sliceBetween(
    brokerBranch,
    "if ns._cdmColdLoadActive then",
    "end")
assert(brokerColdLoad:find("MarkColdLoadDeferredMirrorRefresh()", 1, true),
    "CDMIndex events during cold-load must mark a deferred mirror refresh")

local resolverBranch = sliceBetween(
    mirror,
    'ns.CDMResolvers.Subscribe("CDM:CATALOG_REBUILT"',
    "end)")
local resolverColdLoad = sliceBetween(
    resolverBranch,
    "if ns._cdmColdLoadActive then",
    "end")
assert(resolverColdLoad:find("MarkColdLoadDeferredMirrorRefresh()", 1, true),
    "resolver catalog rebuilds during cold-load must mark a deferred mirror refresh")

assert(loginBranch:find("DrainColdLoadDeferredMirrorRefresh()", 1, true),
    "cold-load finalize must drain deferred mirror refreshes")
assert(mirror:find("_coldLoadDeferredMirrorRefreshPending = false", 1, true),
    "deferred mirror refresh drain must clear the pending flag")

print("OK: cdm_cold_load_viewer_readiness_test")
