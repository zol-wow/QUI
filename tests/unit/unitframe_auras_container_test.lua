-- tests/unit/unitframe_auras_container_test.lua
-- Source-text assertion test for QUI_UnitFrames/unitframes/unitframe_auras.lua.
--
-- The unit-frame aura display was cut over from a two-zone buff/debuff
-- CustomAuraContainer split to ONE secure per-unit CustomAuraContainer PER
-- active aura element (the unit's buff strip / debuff strip, plus any tracked
-- icon/square/bar), pooled by ordinal on frame._quiAuraContainers and driven by
-- the SHARED core modules:
--   * ns.AuraElements — the element model (seed-once bucket, filter compiler),
--   * ns.AuraGlue     — element -> profile + group descriptors, RunConfigPass
--                       (AuraSkin.Configure OOC / Restyle in combat) + the
--                       combat-regen replay queue,
--   * ns.AuraSlots    — tracked slots (AddAuraSlot) via AuraSlots.Sync / Park.
-- These source-text assertions pin the structural contract:
--   * ApplyElementPass walks the active elements into a per-ordinal pool,
--   * filter strips -> AuraGlue group descriptors, tracked -> AuraSlots.Sync,
--     SetUnit / SetEnabled self-drive,
--   * the UNIT-FRAME corner flip (MapAuraAnchorToFramePoint) is KEPT,
--   * the old two-zone split (buffContainer / debuffContainer /
--     BuildZoneProfiles / ResolveZoneFilters / ApplyContainerConfigPass /
--     the classification maps) is GONE,
--   * the layout-mode preview renderer is preserved,
--   * forbidden-object work is combat-deferred to PLAYER_REGEN_ENABLED.
-- Run: lua tests/unit/unitframe_auras_container_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    data = data:gsub("\r\n", "\n")
    return data
end

local src = readAll("QUI_UnitFrames/unitframes/unitframe_auras.lua")
local coreSrc = readAll("core/aura_surface.lua")

-- LIVE PATH: secure CustomAuraContainer + shared core glue --------------------
assert(src:find("QUI.AuraSkin", 1, true) or src:find("ns.Addon.AuraSkin", 1, true),
    "live path must resolve the QUI.AuraSkin adapter")
assert(src:find("ns.AuraGlue", 1, true) and src:find("ns.AuraSlots", 1, true)
    and src:find("ns.AuraElements", 1, true) and src:find("ns.AuraSurface", 1, true),
    "live path must consume the shared core modules (AuraGlue / AuraSlots / AuraElements / AuraSurface)")

-- PER-ELEMENT POOL: one container per active element, pooled by ordinal -------
assert(src:find("local function ApplyElementPass(frame, allowCreate)", 1, true),
    "ApplyElementPass drives the per-element container pass")

assert(src:find("AuraSurface.ApplyElementPass(frame, elems, {", 1, true),
    "ApplyElementPass must delegate to AuraSurface.ApplyElementPass")
assert(src:find("unit = QUI_UF.GetFrameUnit(frame),", 1, true),
    "opts must forward unit")
assert(src:find("allowCreate = allowCreate == true,", 1, true),
    "opts must forward allowCreate")
assert(src:find('cancelEligible = (unitKey == "player"),', 1, true),
    "opts must forward cancelEligible")
assert(src:find("profileFor = ElementProfileFor,", 1, true),
    "opts must forward profileFor")
assert(src:find("anchorContainer = function(container, host, element)", 1, true),
    "opts must forward anchorContainer")
assert(src:find("skip = function(element)", 1, true),
    "opts must forward skip")
assert(src:find("onIncomplete = function(host)", 1, true),
    "opts must forward onIncomplete")

-- Configure/Restyle now live in core (AuraGlue.RunConfigPass): this file no
-- longer CALLS them directly (comments may still reference the core plumbing).
assert(not src:find("AuraSkin.Configure(", 1, true)
    and not src:find("pcall(AuraSkin.Configure", 1, true)
    and not src:find("AuraSkin.Restyle(", 1, true)
    and not coreSrc:find("AuraSkin.Configure(", 1, true)
    and not coreSrc:find("pcall(AuraSkin.Configure", 1, true)
    and not coreSrc:find("AuraSkin.Restyle(", 1, true),
    "AuraSkin.Configure/Restyle must not be called directly by either the surface glue or core/aura_surface.lua")
-- The retired per-button API must be gone.
assert(not src:find("AddAuraFilter", 1, true) and not coreSrc:find("AddAuraFilter", 1, true),
    "AddAuraFilter replaced by the shared core glue")

-- ELEMENT MODEL: seed-once default bucket (file-local) + spec-less resolve -----
-- The default bucket fn MUST be file-local on the runtime path: E.EnsureSeeded
-- LATCHES elementsSeeded, so an Options-only bucket could latch an empty store.
assert(src:find("local function DefaultUnitAuraBucket()", 1, true),
    "the fresh-profile default bucket must be defined file-local")
assert(src:find("EnsureSeeded(auras, DefaultUnitAuraBucket)", 1, true),
    "the element store must be seeded through E.EnsureSeeded with the file-local bucket")
-- Unit frames never use per-spec buckets: the resolve always passes a nil spec.
assert(src:find("ActiveElementsForSpec(auras, nil)", 1, true),
    "unit frames resolve elements spec-less (ActiveElementsForSpec(auras, nil))")
-- healthTint tracked feeder is skipped defensively (UF has no tint display).
assert(src:find('e.displayType ~= "healthTint"', 1, true),
    "healthTint tracked elements must be skipped defensively")

-- PUBLIC ENTRY NAMES preserved (callers in unitframes.lua depend on these) -----
assert(src:find("QUI_UF.UpdateAuras = UpdateAuras", 1, true),
    "QUI_UF.UpdateAuras must remain exposed")
assert(src:find("QUI_UF.ApplyContainerConfig = ApplyContainerConfig", 1, true),
    "QUI_UF.ApplyContainerConfig must remain exposed")
assert(src:find("QUI_UF.SetupAuraTracking = SetupAuraTracking", 1, true),
    "QUI_UF.SetupAuraTracking must remain exposed")
assert(src:find("function QUI_UF:ShowAuraPreview(", 1, true),
    "QUI_UF:ShowAuraPreview must remain defined")
assert(src:find("function QUI_UF:ShowAuraPreviewForFrame(", 1, true),
    "QUI_UF:ShowAuraPreviewForFrame must remain defined")
assert(src:find("function QUI_UF:HideAuraPreview(", 1, true),
    "QUI_UF:HideAuraPreview must remain defined")
assert(src:find("function QUI_UF:HideAuraPreviewForFrame(", 1, true),
    "QUI_UF:HideAuraPreviewForFrame must remain defined")

-- OLD TWO-ZONE STRIP MODEL IS GONE -------------------------------------------
assert(not src:find("buffContainer", 1, true) and not src:find("debuffContainer", 1, true),
    "frame.buffContainer / frame.debuffContainer fields removed (per-element pool now)")
assert(not src:find("BuildZoneProfiles", 1, true)
    and not src:find("BuildZoneGroups", 1, true)
    and not src:find("ResolveZoneFilters", 1, true)
    and not src:find("ApplyContainerConfigPass", 1, true)
    and not src:find("EnsureContainers", 1, true)
    and not src:find("ReflowContainers", 1, true),
    "the two-zone helpers (BuildZoneProfiles / BuildZoneGroups / ResolveZoneFilters / "
    .. "ApplyContainerConfigPass / EnsureContainers / ReflowContainers) must be gone")
assert(not src:find("BUFF_CLASSIFICATION_MAP", 1, true)
    and not src:find("DEBUFF_CLASSIFICATION_MAP", 1, true)
    and not src:find("BuildClassificationFilters", 1, true)
    and not src:find("BuildFilterString", 1, true),
    "the local classification maps + filter-string builders moved to core aura_elements")

-- DEAD ICON FACTORY removed (preview is self-contained; factory was cutover) -----
assert(not src:find("local function CreateAuraIcon(", 1, true),
    "dead factory CreateAuraIcon must be absent after cutover")
assert(not src:find("local function GetAuraIcon(", 1, true),
    "dead factory GetAuraIcon must be absent after cutover")
assert(not src:find("local function ApplyAuraIconSettings(", 1, true),
    "dead factory ApplyAuraIconSettings must be absent after cutover")
-- Preview must suppress the previewed polarity's live containers.
assert(src:find("SuppressContainerForPreview", 1, true),
    "preview must disable the live container while showing fake icons")

-- ANCHOR PARITY: the UNIT-FRAME corner flip is KEPT (surface-specific).  The
-- container pins its flow-origin corner to the frame's NON-flipped corner via
-- MapAuraAnchorToFramePoint, so a TOPLEFT debuff strip hangs ABOVE the frame and
-- a BOTTOMLEFT buff strip hangs BELOW it, matching the layout-mode preview.
assert(src:find("local function MapAuraAnchorToFramePoint(anchor)", 1, true),
    "MapAuraAnchorToFramePoint (UF corner flip) must be KEPT")
local anchorFn = src:match("local function AnchorElementContainer%(.-\nend")
assert(anchorFn, "AnchorElementContainer must be defined")
assert(anchorFn:find("MapAuraAnchorToFramePoint", 1, true),
    "AnchorElementContainer must derive the frame pin from MapAuraAnchorToFramePoint")
assert(anchorFn:find("AuraSkin.LayoutAnchor", 1, true),
    "AnchorElementContainer must pin the flow-origin corner (AuraSkin.LayoutAnchor)")
assert(not anchorFn:find("frame, \"BOTTOMLEFT\"", 1, true),
    "AnchorElementContainer must not hardcode the frame's BOTTOMLEFT as relative point")

-- The corner flip must be folded into the SAME profile both anchor and configure
-- use (ElementProfileFor), so geometry can't drift: it passes attachPoint (the
-- flipped corner) + the flipped wrap as overrides to AuraGlue.ElementProfile.
local profileFn = src:match("local function ElementProfileFor%(element%).-\nend")
assert(profileFn, "ElementProfileFor must be the single profile builder")
assert(profileFn:find("attachPoint", 1, true) and profileFn:find("wrap", 1, true),
    "ElementProfileFor must fold the corner-flip attachPoint + wrap overrides in")
assert(profileFn:find("AuraGlue.ElementProfile", 1, true),
    "ElementProfileFor must layer its overrides onto AuraGlue.ElementProfile")

-- COMBAT SAFETY: forbidden-object work is deferred to PLAYER_REGEN_ENABLED -----
assert(src:find("InCombatLockdown", 1, true),
    "container setup must guard on InCombatLockdown()")
assert(src:find("AuraGlue.QueueRegenWork", 1, true),
    "deferred container work must replay via the shared AuraGlue.QueueRegenWork queue")

-- The live container display must NOT re-introduce a manual per-icon aura read
-- loop (the whole point of the cutover is no QUI Lua reading secret aura data).
assert(not src:find("C_UnitAuras.GetAuraDataByIndex", 1, true),
    "live path must not poll C_UnitAuras.GetAuraDataByIndex (container self-drives)")

print("OK: unitframe_auras_container_test")
