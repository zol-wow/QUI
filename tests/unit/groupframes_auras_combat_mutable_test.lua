-- tests/unit/groupframes_auras_combat_mutable_test.lua
-- Run: lua tests/unit/groupframes_auras_combat_mutable_test.lua
--
-- Combat contract for the per-element group-frame aura containers (PTR7
-- 68914): container creation, AddAuraGroup/AddAuraSlot registration and
-- container anchoring are COMBAT-LEGAL (proven in-game 2026-07-24), so the
-- full pass runs live in combat behind a SafeCall belt — a member joining
-- mid-combat builds its containers on the spot. Work skipped under the aura
-- SECRECY restriction (or a SafeCall-caught failure) still queues the
-- restriction-aware regen replay. DisableStripContainers hides a cleared
-- unit's containers live.

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("QUI_GroupFrames/groupframes/groupframes_auras.lua")
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
assert(not coreSrc:find("allowCreate and not InCombatLockdown()", 1, true),
    "no stale combat condition may remain on container creation in core/aura_surface.lua")
assert(coreSrc:find("if allowCreate and CreateFrame then", 1, true),
    "core/aura_surface.lua must gate container creation on allowCreate only (combat-legal)")
assert(coreSrc:find('CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")', 1, true),
    "core/aura_surface.lua creation uses the CustomAuraContainerTemplate")
assert(pass:find("AuraSurface.ApplyElementPass(frame, elems, {", 1, true),
    "ApplyElementPass must delegate the per-element pass to AuraSurface.ApplyElementPass")
assert(pass:find("allowCreate = allowCreate == true,", 1, true),
    "allowCreate must be forwarded through opts (combat-legal creation is core's responsibility now)")

-- Container anchoring (SetPoint) runs unconditionally — proven combat-legal
-- pre- and post-group registration; SetUnit likewise.
assert(pass:find("anchorContainer = function(container, host, element)", 1, true)
    and pass:find("AnchorElementContainer(container, host, element)", 1, true),
    "AnchorElementContainer runs on the pass via the anchorContainer opts callback")
assert(coreSrc:find("container:SetUnit(unit)", 1, true),
    "SetUnit is a combat-legal mutation and runs unconditionally in core/aura_surface.lua")

-- Group / slot reconcile flows through the shared core glue; the combat
-- pcall(Configure)/Restyle fallback lives INSIDE AuraGlue.RunConfigPass, so
-- this file just threads allowCreate through — it never pcalls Configure itself.
assert(coreSrc:find("AuraGlue.RunConfigPass(container, profile, groups, allowCreate)", 1, true),
    "core/aura_surface.lua reconciles filter-strip groups via AuraGlue.RunConfigPass(..., allowCreate)")
assert(coreSrc:find("AuraGlue.ElementGroups(unit, element, profile, cancelEligible)", 1, true),
    "core/aura_surface.lua builds filter-strip descriptors via AuraGlue.ElementGroups")
assert(pass:find("cancelEligible = false,", 1, true),
    "group frames hardcode cancelEligible false (no right-click cancel on group strips)")
assert(coreSrc:find("AuraSlots.Sync(container, element, allowCreate, opts.profileOverrides)", 1, true),
    "core/aura_surface.lua reconciles tracked slots with the forwarded opts.profileOverrides")
assert(pass:find("profileOverrides = profileOverrides,", 1, true),
    "ApplyElementPass must forward profileOverrides through opts so AuraSlots.Sync gets the group-aura visual profile")
assert(not pass:find("pcall(AuraSkin", 1, true) and not coreSrc:find("pcall(AuraSkin", 1, true),
    "the combat Configure guard lives in core (AuraGlue.RunConfigPass), not in either surface-glue layer")
assert(not pass:find("AuraSkin.Reflow", 1, true),
    "AuraSkin.Reflow no longer exists")

-- Skipped restricted work (secrecy-gated child access) queues a regen replay.
assert(pass:find("onIncomplete = QueueContainerCombatWork,", 1, true),
    "incomplete (restricted work skipped) must queue a regen replay via the onIncomplete opts callback")

assert(pass:find("onContainerReady = function(container, host)", 1, true)
    and pass:find("if not InCombatLockdown() then", 1, true)
    and pass:find("return container:GetFrameLevel() == desiredLevel", 1, true),
    "the frame-level pass must be combat-gated via the onContainerReady opts callback")

-- The public full-pass name survives (forward-declared) and always creates.
assert(src:find("function ApplyStripContainers(frame)", 1, true),
    "ApplyStripContainers must keep its (forward-declared) name")
assert(not src:find("ApplyElementPass(frame, not InCombatLockdown())", 1, true),
    "no entry may downgrade allowCreate on combat (full pass is combat-legal)")

-- UpdateStripContainers: combat = SafeCall'd FULL pass; queue only on failure.
local update = slice("local function UpdateStripContainers(frame)")
assert(update:find('local ok = ns.SafeCall("best-effort-style", ApplyElementPass, frame, true)', 1, true),
    "UpdateStripContainers must SafeCall-guard the full creating pass in combat")
assert(update:find("if not ok then\n            QueueContainerCombatWork(frame)\n        end", 1, true),
    "a SafeCall-caught failure must queue the regen replay")
assert(update:find("ApplyElementPass(frame, true)", 1, true),
    "UpdateStripContainers runs the full creating pass OOC")

-- RetireContainer: the shared retire recipe (empty groups + park + disable + hide).
local retire = slice("local function RetireContainer(container, allowCreate)")
assert(retire:find("AuraGlue.RunConfigPass", 1, true) and retire:find("AuraSlots.Park", 1, true),
    "retire = empty groups (RunConfigPass) + park slots")
assert(retire:find("SetEnabled(false)", 1, true) and retire:find(":Hide()", 1, true),
    "retire disables + hides the container")

-- DisableStripContainers: retire every pooled container; combat SafeCall-guards
-- the live retire and still queues a regen replay.
local disable = slice("local function DisableStripContainers(frame)")
assert(disable:find("frame._quiAuraContainers", 1, true),
    "DisableStripContainers iterates the per-element pool")
assert(disable:find('ns.SafeCall("best-effort-style", RetireContainer, container, false)', 1, true),
    "DisableStripContainers must SafeCall-guard the live retire in combat")
assert(disable:find("RetireContainer(container, true)", 1, true),
    "DisableStripContainers retires directly OOC")
assert(disable:find("QueueContainerCombatWork(frame)", 1, true),
    "DisableStripContainers queues a regen replay in combat")

print("OK: groupframes_auras_combat_mutable_test")
