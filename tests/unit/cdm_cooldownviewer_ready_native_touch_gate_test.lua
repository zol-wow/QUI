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
    "-- Task C / G8")
assert(readyQueue:find("reanchorHooksReadyMarkDirty or canMarkDirty", 1, true),
    "COOLDOWN_VIEWER_DATA_LOADED hook retry must request an out-of-combat initial re-claim")

local refreshHooks = slice(containers,
    "function ownedEngine:RefreshReanchorRuntimeHooks(markDirty)",
    "function ownedEngine:BootstrapReanchorRuntime()")
assert(refreshHooks:find("IsCooldownViewerReady()", 1, true),
    "native re-anchor hook install must check CooldownViewer readiness")
assert(refreshHooks:find("QueueReanchorHooksWhenCooldownViewerReady(markDirty)", 1, true),
    "native re-anchor hook install must wait for COOLDOWN_VIEWER_DATA_LOADED before viewer hooks")
assert(refreshHooks:find("InstallGlobalMixinHooks", 1, true),
    "native re-anchor hook install must include global CooldownViewer item mixin hooks")

local bootstrapHooks = slice(containers,
    "function ownedEngine:BootstrapReanchorRuntime()",
    "-- Task C (G6 + G8)")
assert(bootstrapHooks:find("BlankReanchoredNativeItemFrame", 1, true),
    "re-anchor bootstrap must provide a native frame blanker")
assert(bootstrapHooks:find("isInitialReanchorDone", 1, true),
    "acquire blanking must be gated until initial reanchor completes")
assert(bootstrapHooks:find("blankKeys = { buff = true, essential = true, utility = true }", 1, true),
    "buff + essential/utility acquire blanking must be explicitly enabled (combat-start snap fix)")
assert(bootstrapHooks:find("blankKeys = { trackedBar = true }", 1, true),
    "tracked buff-bar acquire blanking must be explicitly enabled")

local getViewerFrame = slice(containers,
    "function CDMProvider:GetViewerFrame(key)",
    "function CDMProvider:GetViewerFrames()")
assert(not getViewerFrame:find("_G%[blizzName%]"),
    "CDMProvider:GetViewerFrame must not return Blizzard globals before owned containers initialize")
assert(getViewerFrame:find("return nil", 1, true),
    "CDMProvider:GetViewerFrame must fail closed before owned containers initialize")

print("OK: cdm_cooldownviewer_ready_native_touch_gate_test")
