-- tests/unit/cdm_cooldownviewer_ready_native_touch_gate_test.lua
-- Run: lua tests/unit/cdm_cooldownviewer_ready_native_touch_gate_test.lua
--
-- First login can expose Blizzard CooldownViewer frames before their data
-- provider is ready. Native BuffBarCooldownViewer reads/writes must wait for
-- the shared readiness gate; /reload often masks this because the provider is
-- already warm.

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s:gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function slice(text, startMarker, stopMarker)
    local start = assert(text:find(startMarker, 1, true), "missing " .. startMarker)
    local stop = stopMarker and text:find(stopMarker, start + #startMarker, true)
    return text:sub(start, stop and (stop - 1) or #text)
end

local catalog = read("QUI_CDM/cdm/cdm_catalog.lua")
assert(catalog:find("function CDMCatalog.IsCooldownViewerReady()", 1, true),
    "CDMCatalog must export the CooldownViewer data readiness gate")
assert(catalog:find("IsCooldownViewerAvailable", 1, true),
    "readiness gate must use C_CooldownViewer.IsCooldownViewerAvailable")

local buff = read("QUI_CDM/cdm/cdm_buff_layout.lua")
local layoutBars = slice(buff, "LayoutBuffBars = function()", "-- CHANGE DETECTION")
local readyPos = assert(layoutBars:find("IsCooldownViewerReady()", 1, true),
    "LayoutBuffBars must check CooldownViewer readiness")
local entriesPos = assert(layoutBars:find("GetTrackedBarRuntimeEntries()", 1, true),
    "LayoutBuffBars still mirrors native runtime entries after readiness")
assert(readyPos < entriesPos,
    "LayoutBuffBars must gate native BuffBar reads before building runtime entries")
assert(layoutBars:find("QueueTrackedBarLayoutWhenReady()", readyPos, true),
    "LayoutBuffBars must queue a retry for COOLDOWN_VIEWER_DATA_LOADED")

local editlock = read("QUI_CDM/cdm/cdm_reanchor_editlock.lua")
local install = slice(editlock, "function CDMReanchorEditLock:Install(getViewer)")
assert(install:find("_IsCooldownViewerReady()", 1, true),
    "Edit lock must wait for CooldownViewer readiness before viewer lookup/mutation")

local containers = read("QUI_CDM/cdm/cdm_containers.lua")
local readyQueue = slice(containers,
    "local function QueueReanchorHooksWhenCooldownViewerReady(markDirty)",
    "local _reanchorGlowOverlays")
assert(readyQueue:find("reanchorHooksReadyMarkDirty or canMarkDirty", 1, true),
    "COOLDOWN_VIEWER_DATA_LOADED hook retry must request an out-of-combat initial re-claim")

local refreshHooks = slice(containers,
    "function ownedEngine:RefreshReanchorRuntimeHooks(markDirty)",
    "function ownedEngine:BootstrapReanchorRuntime()")
assert(refreshHooks:find("IsCooldownViewerReady()", 1, true),
    "native re-anchor hook install must check CooldownViewer readiness")
assert(refreshHooks:find("QueueReanchorHooksWhenCooldownViewerReady(markDirty)", 1, true),
    "native re-anchor hook install must retain the data-ready retry")
local queuePos = assert(refreshHooks:find("QueueReanchorHooksWhenCooldownViewerReady(markDirty)", 1, true))
local gracePos = assert(refreshHooks:find("if not ns._cdmCombatReloadGrace then return false end", 1, true),
    "only combat /reload may install viewer guards before data readiness")
local installPos = assert(refreshHooks:find("hk:InstallViewerHooks(getViewer)", 1, true))
assert(queuePos < gracePos and gracePos < installPos,
    "combat /reload must install viewer guards synchronously before Blizzard's PEW rebuild")
assert(refreshHooks:find("InstallGlobalMixinHooks", 1, true),
    "native re-anchor hook install must include global CooldownViewer item mixin hooks")

local bootstrapHooks = slice(containers,
    "function ownedEngine:BootstrapReanchorRuntime()",
    "-- Task C (G6 + G8)")
assert(bootstrapHooks:find("BlankReanchoredNativeItemFrame", 1, true),
    "re-anchor bootstrap must provide a native frame blanker")
assert(bootstrapHooks:find("isInitialReanchorDone", 1, true),
    "acquire blanking must be gated until initial reanchor completes")
assert(bootstrapHooks:find("blankKeys = { buff = true }", 1, true),
    "Essential/Utility acquire blanking must stay disabled to avoid native pool flicker")
assert(bootstrapHooks:find("blankKeys = { trackedBar = true }", 1, true),
    "tracked buff-bar acquire blanking must be explicitly enabled")
assert(bootstrapHooks:find("bridge:Sink(frame)", 1, true),
    "combat /reload acquire guards must sink newly rebuilt Essential/Utility frames")
assert(bootstrapHooks:find("ns._cdmCombatReloadGrace or IsInitialReanchorDone(key)", 1, true),
    "combat /reload must guard post-load pool acquires before the first data-ready reanchor")

local guardBody = assert(bootstrapHooks:match(
    "installGuard = function%(frame, key%)%s*(.-)%s*end,%s*installGuardKeys"),
    "combat /reload acquire guard callback must be extractable")
local loadSource = loadstring or load
local installGuard = assert(loadSource(
    "return function(ns, boot, frame, key)\n" .. guardBody .. "\nend"))()
local guarded, sunk = {}, {}
local frame = {}
installGuard({ _cdmCombatReloadGrace = true }, { bridge = {
    InstallAnchorGuard = function(_, value) guarded[#guarded + 1] = value end,
    IsClaimed = function() return false end,
    Sink = function(_, value) sunk[#sunk + 1] = value end,
} }, frame, "essential")
assert(guarded[1] == frame and sunk[1] == frame,
    "combat /reload acquire must install the guard and sink the new Essential frame")

local initialize = slice(containers,
    "function ownedEngine:Initialize()",
    "local function DrainPendingLoadoutSwitch")
assert(initialize:find('UnitAffectingCombat("player")', 1, true),
    "combat /reload must latch physical combat before ForceLoadCDM")

local getViewerFrame = slice(containers,
    "function CDMProvider:GetViewerFrame(key)",
    "function CDMProvider:GetViewerFrames()")
assert(not getViewerFrame:find("_G%[blizzName%]"),
    "CDMProvider:GetViewerFrame must not return Blizzard globals before owned containers initialize")
assert(getViewerFrame:find("return nil", 1, true),
    "CDMProvider:GetViewerFrame must fail closed before owned containers initialize")

print("OK: cdm_cooldownviewer_ready_native_touch_gate_test")
