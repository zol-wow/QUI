-- tests/unit/unitframe_auras_combat_mutable_test.lua
-- Run: lua tests/unit/unitframe_auras_combat_mutable_test.lua
--
-- Combat contract for the per-element unit-frame aura containers (PTR7 68914):
-- container creation, AddAuraGroup/AddAuraSlot registration and container
-- anchoring are COMBAT-LEGAL (proven in-game 2026-07-24), so UpdateAuras runs
-- the FULL pass live in combat behind a SafeCall belt and queues the
-- restriction-aware replay only when the belt catches a failure (the pass
-- itself queues its own secrecy-skipped gaps). Same contract as group frames,
-- with the unit-frame differences: corner-flip anchoring, a player-only
-- cancel-eligible gate, and per-polarity preview suppression.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_UnitFrames/unitframes/unitframe_auras.lua")
local coreSrc = readAll("core/aura_surface.lua")

local function slice(marker)
    local startPos = src:find(marker, 1, true)
    assert(startPos, "missing: " .. marker)
    local endPos = src:find("\nend", startPos, true)
    assert(endPos, "unterminated function at: " .. marker)
    return src:sub(startPos, endPos)
end

-- ApplyElementPass: the single per-element pass, allowCreate-gated.
local pass = slice("local function ApplyElementPass(frame, allowCreate)")

-- CREATION is allowCreate-gated only — no combat condition (PTR7 68914).
assert(not coreSrc:find("allowCreate and not InCombatLockdown()", 1, true)
    and not coreSrc:find("InCombatLockdown", 1, true),
    "no stale combat condition may remain on container creation or anchoring in core/aura_surface.lua")
assert(pass:find("AuraSurface.ApplyElementPass(frame, elems, {", 1, true),
    "ApplyElementPass must delegate the per-element pass to AuraSurface.ApplyElementPass")
assert(pass:find("allowCreate = allowCreate == true,", 1, true),
    "allowCreate must be forwarded through opts (combat-legal creation is core's responsibility now)")

-- Container anchoring (SetPoint) runs unconditionally — proven combat-legal
-- pre- and post-group registration; SetUnit likewise.
assert(pass:find("anchorContainer = function(container, host, element)", 1, true)
    and pass:find("AnchorElementContainer(container, host, element)", 1, true),
    "AnchorElementContainer runs on the pass via the anchorContainer opts callback")

assert(not pass:find("pcall(AuraSkin", 1, true) and not coreSrc:find("pcall(AuraSkin", 1, true),
    "the combat Configure guard lives in core (AuraGlue.RunConfigPass), not in either surface-glue layer")

-- UNIT-FRAME SPECIFICS ----------------------------------------------------------
-- cancel is player-unit only (HELPFUL strips) — AuraGlue.ElementGroups honors it.
assert(pass:find('cancelEligible = (unitKey == "player")', 1, true),
    "right-click cancel is offered only on the player unit (cancelEligible gate)")
-- A previewed polarity keeps its element containers disabled + hidden so the
-- fake preview icons own the display (per-polarity suppression, not per-zone).
assert(pass:find("skip = function(element)", 1, true)
    and pass:find("buffPreviewActive", 1, true)
    and pass:find("debuffPreviewActive", 1, true),
    "a previewed polarity must suppress its matching-polarity element containers via the skip opts callback")

-- Skipped restricted work queues a regen replay via the shared core queue.
assert(pass:find("onIncomplete = function(host)", 1, true)
    and pass:find("AuraGlue.QueueRegenWork(host, function(f) ApplyElementPass(f, true) end)", 1, true),
    "incomplete (restricted work skipped) must queue a regen replay via the onIncomplete opts callback")

-- UpdateAuras: combat = SafeCall'd FULL pass; queue only on a caught failure.
local update = slice("local function UpdateAuras(frame)")
assert(update:find("InCombatLockdown()", 1, true), "UpdateAuras must branch on combat")
assert(update:find('local ok = ns.SafeCall("best-effort-style", ApplyElementPass, frame, true)', 1, true),
    "UpdateAuras must SafeCall-guard the full creating pass in combat")
assert(update:find("AuraGlue.QueueRegenWork(frame, function(f) ApplyElementPass(f, true) end)", 1, true),
    "a SafeCall-caught failure must queue the regen replay")
assert(update:find("ApplyElementPass(frame, true)", 1, true),
    "UpdateAuras runs the full creating pass OOC")

-- Preview suppression rides the combat-aware full pass (the preview flag is set
-- by the caller before this runs; UpdateAuras handles the combat mutation +
-- queue), so it never touches a forbidden object directly in combat.
local suppress = slice("local function SuppressContainerForPreview(frame)")
assert(suppress:find("UpdateAuras(frame)", 1, true),
    "preview suppression delegates to the combat-aware UpdateAuras")

-- The public export names survive (callers in unitframes.lua depend on them).
assert(src:find("QUI_UF.ApplyContainerConfig = ApplyContainerConfig", 1, true),
    "QUI_UF.ApplyContainerConfig export must keep its name")
assert(src:find("QUI_UF.UpdateAuras = UpdateAuras", 1, true),
    "QUI_UF.UpdateAuras export must keep its name")

print("OK: unitframe_auras_combat_mutable_test")
