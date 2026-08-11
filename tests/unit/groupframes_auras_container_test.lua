-- tests/unit/groupframes_auras_container_test.lua
-- Source-text assertion test for QUI_GroupFrames/groupframes/groupframes_auras.lua.
--
-- The container-rendered aura display (generic buff/debuff filter strips AND
-- tracked icon/square/bar) now renders ONE secure per-unit CustomAuraContainer
-- PER active element, pooled by ordinal on frame._quiAuraContainers, driven by
-- the SHARED core modules:
--   * ns.AuraGlue  — element -> profile + group descriptors, RunConfigPass
--                    (AuraSkin.Configure OOC / Restyle in combat),
--   * ns.AuraSlots — tracked slots (AddAuraSlot) via AuraSlots.Sync / Park.
-- These source-text assertions pin the structural contract:
--   * ApplyElementPass walks the active elements into a per-ordinal pool,
--   * filter strips -> AuraGlue group descriptors, tracked -> AuraSlots.Sync,
--     SetUnit / SetEnabled self-drive,
--   * the OLD two-zone buff/debuff container split (buffContainer /
--     debuffContainer / BuildZoneFilters / ZoneProfile / ApplyStripPass) is GONE,
--   * Missing Raid Buffs (missingRaidBuff) + the healthTint tint feeder STILL
--     flow through the (untouched) element renderer,
--   * forbidden-object work is combat-deferred to PLAYER_REGEN_ENABLED,
--   * the element model file is now a delegating SHIM.
-- Run: lua tests/unit/groupframes_auras_container_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_GroupFrames/groupframes/groupframes_auras.lua")
local callSrc = readAll("QUI_GroupFrames/groupframes/groupframes.lua")
local coreSrc = readAll("core/aura_surface.lua")

local fails = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        fails = fails + 1
        print("FAIL  " .. name)
    end
end

-- LIVE CONTAINER PATH: secure CustomAuraContainer + shared core glue ----------
check("core/aura_surface.lua creates CustomAuraContainerTemplate frames",
    coreSrc:find('"CustomAuraContainerTemplate"', 1, true) ~= nil)
check("resolves the QUI.AuraSkin adapter",
    src:find("QUI.AuraSkin", 1, true) ~= nil or src:find("ns.Addon.AuraSkin", 1, true) ~= nil)

-- PER-ELEMENT POOL: one container per active element, pooled by ordinal -------
check("per-element container pool on the frame (frame._quiAuraContainers)",
    src:find("frame._quiAuraContainers", 1, true) ~= nil)
check("ApplyElementPass drives the per-element container pass",
    src:find("local function ApplyElementPass(frame, allowCreate)", 1, true) ~= nil)
check("ApplyElementPass delegates the per-element pass to AuraSurface.ApplyElementPass",
    src:find("AuraSurface.ApplyElementPass(frame, elems, {", 1, true) ~= nil)

-- SHARED CORE GLUE: config via AuraGlue.RunConfigPass, slots via AuraSlots ----
check("consumes ns.AuraGlue + ns.AuraSlots",
    src:find("ns.AuraGlue", 1, true) ~= nil and src:find("ns.AuraSlots", 1, true) ~= nil)
check("core/aura_surface.lua configures containers via AuraGlue.RunConfigPass",
    coreSrc:find("AuraGlue.RunConfigPass", 1, true) ~= nil)
check("core/aura_surface.lua reconciles tracked slots via AuraSlots.Sync + Park",
    coreSrc:find("AuraSlots.Sync", 1, true) ~= nil and coreSrc:find("AuraSlots.Park", 1, true) ~= nil)
check("core/aura_surface.lua builds group descriptors via AuraGlue.ElementGroups",
    coreSrc:find("AuraGlue.ElementGroups", 1, true) ~= nil)
check("container flow anchors via AuraSkin.LayoutAnchor",
    src:find("AuraSkin.LayoutAnchor", 1, true) ~= nil)
-- The retired per-button / two-zone APIs must be gone.
check("AddAuraFilter gone (engine creates buttons; RunConfigPass replaces it)",
    src:find("AddAuraFilter", 1, true) == nil)
check("ClearAuraFilters gone (PTR4 groups are reconciled, never cleared)",
    src:find("ClearAuraFilters", 1, true) == nil)
check("AuraSkin.Attach / Reflow gone",
    src:find("AuraSkin.Attach", 1, true) == nil and src:find("AuraSkin.Reflow", 1, true) == nil)
-- Configure/Restyle now live in core (AuraGlue.RunConfigPass): this file no
-- longer CALLS them directly (comments may still reference the core plumbing).
check("AuraSkin.Configure/Restyle no longer called directly by either the surface glue or core",
    src:find("AuraSkin.Configure(", 1, true) == nil
    and src:find("pcall(AuraSkin.Configure", 1, true) == nil
    and src:find("AuraSkin.Restyle(", 1, true) == nil
    and coreSrc:find("AuraSkin.Configure(", 1, true) == nil
    and coreSrc:find("pcall(AuraSkin.Configure", 1, true) == nil
    and coreSrc:find("AuraSkin.Restyle(", 1, true) == nil)
check("core/aura_surface.lua calls SetUnit before configuring the container",
    coreSrc:find("container:SetUnit(unit)", 1, true) ~= nil)
check("core/aura_surface.lua calls container:SetEnabled to self-drive UNIT_AURA",
    coreSrc:find("SetEnabled(true)", 1, true) ~= nil and coreSrc:find("SetEnabled(false)", 1, true) ~= nil)

check("opts forwards unit",
    src:find("unit = unit,", 1, true) ~= nil)
check("opts forwards allowCreate",
    src:find("allowCreate = allowCreate == true,", 1, true) ~= nil)
check("opts forwards cancelEligible (hardcoded false, no right-click cancel here)",
    src:find("cancelEligible = false,", 1, true) ~= nil)
check("opts forwards profileOverrides (also needed directly by AuraSlots.Sync)",
    src:find("profileOverrides = profileOverrides,", 1, true) ~= nil)
check("opts forwards profileFor",
    src:find("profileFor = function(element)", 1, true) ~= nil
    and src:find("return AuraGlue.ElementProfile(element, profileOverrides)", 1, true) ~= nil)
check("opts forwards anchorContainer",
    src:find("anchorContainer = function(container, host, element)", 1, true) ~= nil
    and src:find("AnchorElementContainer(container, host, element)", 1, true) ~= nil)
check("opts forwards onContainerReady (the combat-gated frame-level pass)",
    src:find("onContainerReady = function(container, host)", 1, true) ~= nil)
check("opts forwards onIncomplete",
    src:find("onIncomplete = QueueContainerCombatWork,", 1, true) ~= nil)

-- OLD TWO-ZONE STRIP MODEL IS GONE -------------------------------------------
check("buffContainer / debuffContainer fields removed (per-element pool now)",
    src:find("buffContainer", 1, true) == nil and src:find("debuffContainer", 1, true) == nil)
check("ResolveStripElements replaced by ResolveContainerElements",
    src:find("ResolveStripElements", 1, true) == nil
    and src:find("local function ResolveContainerElements(frame)", 1, true) ~= nil)
check("zone helpers removed (BuildZoneFilters / ZoneProfile / ApplyStripPass / AnchorZoneContainer)",
    src:find("BuildZoneFilters", 1, true) == nil
    and src:find("ZoneProfile", 1, true) == nil
    and src:find("ApplyStripPass", 1, true) == nil
    and src:find("AnchorZoneContainer", 1, true) == nil)
check("container classification maps removed (moved to core aura_elements)",
    src:find("CONTAINER_BUFF_CLASS_MAP", 1, true) == nil
    and src:find("CONTAINER_DEBUFF_CLASS_MAP", 1, true) == nil
    and src:find("local BUFF_CLASSIFICATION_MAP", 1, true) == nil
    and src:find("local DEBUFF_CLASSIFICATION_MAP", 1, true) == nil)

-- PUBLIC ENTRY NAMES the call sites in groupframes.lua depend on --------------
check("QUI_GFA.ApplyStripContainers exposed",
    src:find("QUI_GFA.ApplyStripContainers = ApplyStripContainers", 1, true) ~= nil)
check("QUI_GFA.UpdateStripContainers exposed",
    src:find("QUI_GFA.UpdateStripContainers = UpdateStripContainers", 1, true) ~= nil)
check("QUI_GFA.DisableStripContainers exposed (unit clear)",
    src:find("QUI_GFA.DisableStripContainers = DisableStripContainers", 1, true) ~= nil)
check("prealloc surface retired (creation is combat-legal since PTR7 68914)",
    src:find("EnsureContainersForFrame", 1, true) == nil
    and src:find("PrebuildHeadroomGroups", 1, true) == nil
    and src:find("PREALLOC_HEADROOM", 1, true) == nil)
check("groupframes.lua wires UpdateStripContainers on unit assign",
    callSrc:find("UpdateStripContainers(", 1, true) ~= nil)
check("groupframes.lua wires DisableStripContainers on unit clear",
    callSrc:find("DisableStripContainers(", 1, true) ~= nil)

-- ENGINE NO LONGER RENDERS STRIPS / DROPPED TRACKED DISPLAY -------------------
-- The single gate the engine routes every element through.
check("EngineRendersElement gate defined + exported",
    src:find("local function EngineRendersElement", 1, true) ~= nil
    and src:find("QUI_GFA.EngineRendersElement = EngineRendersElement", 1, true) ~= nil)
-- The dead Lua-side strip match builder is gone (container filters C-side now).
check("BuildFilterStripMatches (strip Lua render path) removed",
    src:find("local function BuildFilterStripMatches", 1, true) == nil)
check("RenderFrameElements no longer dispatches a filterStrip match build",
    src:find("BuildFilterStripMatches(unit", 1, true) == nil)

-- MRB + TINT STILL FLOW THROUGH THE ELEMENT RENDERER (kept this step) ---------
check("missingRaidBuff handling still present in the render path",
    src:find('"missingRaidBuff"', 1, true) ~= nil
    and src:find("QUI_GroupFrameMissingRaidBuffs", 1, true) ~= nil
    and src:find("BuildMatches", 1, true) ~= nil)
check("healthTint tracked feeder kept in the engine gate",
    src:find('element.displayType == "healthTint"', 1, true) ~= nil)
check("RenderFrameElements still defined + exported (MRB + tint renderer)",
    src:find("QUI_GFA.RenderFrameElements = RenderFrameElements", 1, true) ~= nil)

-- COMBAT SAFETY: forbidden-object work deferred until BOTH combat lockdown
-- and the 12.1 aura restriction clear. The replay routes through the shared
-- restriction-aware queue (core/aura_glue.lua QueueRegenWork: regen event +
-- restriction poll) — a PLAYER_REGEN_ENABLED-only local flush left tracked
-- slots stale when secrecy began and ended without a combat window.
check("container setup guards on InCombatLockdown()",
    src:find("InCombatLockdown()", 1, true) ~= nil)
check("deferred container work replays via the restriction-aware shared queue",
    src:find("AuraGlue.QueueRegenWork", 1, true) ~= nil)
check("no module-local PLAYER_REGEN_ENABLED flush remains (shared queue owns it)",
    src:find('"PLAYER_REGEN_ENABLED"', 1, true) == nil)
check("a combat-deferral queue exists for forbidden container work",
    src:find("QueueContainerCombatWork", 1, true) ~= nil)

-- The live container path must NOT re-introduce a manual per-icon aura read
-- loop -- the whole point is no QUI Lua reading secret aura data.
check("container path adds no GetAuraDataByIndex poll",
    src:find("ApplyStripContainers", 1, true) ~= nil
    and src:find("C_UnitAuras.GetAuraDataByIndex", 1, true) == nil)

-- DEAD-CODE TRIM (engine-only) -----------------------------------------------
-- The last orphaned Lua-side strip-filter primitives stay removed.
check("AuraPassesSpellFilter (whitelist/blacklist) removed",
    src:find("local function AuraPassesSpellFilter", 1, true) == nil)
check("AuraPassesFilter (inline classification query) removed",
    src:find("local function AuraPassesFilter", 1, true) == nil)
check("GetAuraPriority + PRIORITY_* sort constants removed",
    src:find("local function GetAuraPriority", 1, true) == nil
    and src:find("PRIORITY_DISPELLABLE", 1, true) == nil)

-- ENTANGLEMENT: renderer/preview paths are NOT dead --------------------------
-- The LIVE group-frame runtime (groupframes_auras.lua) dispatches EVERY element
-- type through R.Dispatch, so the renderer's RenderSquare / RenderBar / Dispatch
-- paths (aura_render.lua) are LIVE, not dead. The layout-mode PREVIEW DRIVER
-- (group_frames_preview_driver.lua) now previews filterStrip + tracked
-- icon/square/bar through the shared ns.AuraPreview placeholder renderer and
-- keeps ONLY missingRaidBuff + healthTint on R.Dispatch. These assertions guard
-- that the renderer paths were NOT mistakenly trimmed.
local renderSrc = readAll("QUI_GroupFrames/groupframes/groupframes_aura_render.lua")
local modelSrc  = readAll("QUI_GroupFrames/groupframes/groupframes_aura_model.lua")
local previewSrc = readAll("QUI_GroupFrames/groupframes/settings/group_frames_preview_driver.lua")
check("live runtime dispatches every element type via R.Dispatch",
    src:find("Render:Dispatch(frame, element, matches)", 1, true) ~= nil)
check("preview driver keeps MRB + healthTint on R.Dispatch, rest via ns.AuraPreview",
    previewSrc:find("Render:Dispatch(f, element, matches)", 1, true) ~= nil
    and previewSrc:find('element.mode == "missingRaidBuff"', 1, true) ~= nil
    and previewSrc:find("ns.AuraPreview", 1, true) ~= nil)
check("R.RenderSquare KEPT (live via tracked-square dispatch)",
    renderSrc:find("function R.RenderSquare", 1, true) ~= nil)
check("R.RenderBar KEPT (live via tracked-bar dispatch)",
    renderSrc:find("function R.RenderBar", 1, true) ~= nil)
check("R.RenderIcon + R.RenderHealthTint + R.Dispatch KEPT",
    renderSrc:find("function R.RenderIcon", 1, true) ~= nil
    and renderSrc:find("function R.RenderHealthTint", 1, true) ~= nil
    and renderSrc:find("function R.SyncHealthBarTint", 1, true) ~= nil
    and renderSrc:find("function R.Dispatch", 1, true) ~= nil)

-- MODEL FILE IS NOW A DELEGATING SHIM ----------------------------------------
-- The element model moved to core/aura_elements.lua; the GF model file only
-- delegates (setmetatable __index) + keeps the GF preview populator.
check("model file is a setmetatable(__index=E) shim, not a re-declaration",
    modelSrc:find("setmetatable({}, { __index = E })", 1, true) ~= nil
    and modelSrc:find("function Model.NewFilterStripElement", 1, true) == nil)
-- The shipped default bucket must be SHIM-owned (always-loaded), never
-- Options-side: the runtime seed LATCHES elementsSeeded, so an Options-only
-- bucket would let an Options-disabled install latch an empty "*" bucket and
-- permanently lose the shipped strips (Task 4 review regression).
check("DefaultStripBucket owned by the always-loaded shim",
    modelSrc:find("function Model.DefaultStripBucket", 1, true) ~= nil)
check("runtime seed path has NO Options-side dependency",
    src:find("QUI_GroupFramesAuraDefaults", 1, true) == nil)
check("shim keeps the GF-only PopulateElementMatches populator",
    modelSrc:find("function Model.PopulateElementMatches", 1, true) ~= nil)

if fails > 0 then error(fails .. " failure(s) in groupframes_auras_container_test") end
print("OK: groupframes_auras_container_test (" .. "all checks passed)")
