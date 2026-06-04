-- tests/unit/cdm_challenge_mode_catalog_rebuild_test.lua
-- Regression: entering a Mythic+ key (or an encounter / rated PvP match) must
-- rebuild the CDM catalog through a LIVE path.
--
-- cdm_resolvers.lua's RebuildCatalog() is wired to fire on CHALLENGE_MODE_START
-- (and ENCOUNTER_START / PVP_MATCH_ACTIVE). Its header explains *why*: aura
-- instance IDs re-randomize on those boundaries, so the catalog must rebuild.
-- But RebuildCatalog() only bumps CDMResolvers._catalogVersion and publishes
-- "CDM:CATALOG_REBUILT". If nothing consumes that signal, the rebuild is a
-- no-op: cooldown/aura bindings stay bound to the pre-key state and durations
-- do not show until the player /reloads or swaps spec.
--
-- This test asserts the wiring contract that is currently violated: the
-- lifecycle event published on key entry has at least one consumer. Source-
-- structure assertions mirror the established pattern in
-- tests/unit/cdm_combat_reload_test.lua (the cdm_resolvers chunk is ~3.2k lines
-- of coupled resolver logic, impractical to execute headlessly).
--
-- Run from repo root: lua tests/unit/cdm_challenge_mode_catalog_rebuild_test.lua

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function countPlain(text, needle)
    local count, pos = 0, 1
    while true do
        local found = string.find(text, needle, pos, true)
        if not found then break end
        count = count + 1
        pos = found + #needle
    end
    return count
end

local CDM_FILES = {
    "cdm_resolvers.lua",
    "cdm_runtime_queries.lua",
    "cdm_scheduler.lua",
    "cdm_sources.lua",
    "cdm_spelldata.lua",
    "cdm_blizz_mirror.lua",
    "cdm_containers.lua",
    "cdm_icon_renderer.lua",
    "cdm_bar_renderer.lua",
    "cdm_shared.lua",
    "cdm_index.lua",
    "cdm_catalog.lua",
    "cdm_frame_writes.lua",
    "hud_visibility.lua",
}

local sources = {}
for _, name in ipairs(CDM_FILES) do
    sources[name] = readAll("modules/cdm/" .. name)
end

local resolvers = sources["cdm_resolvers.lua"]
local mirror = sources["cdm_blizz_mirror.lua"]

-- Entering a key / encounter / rated-PvP match re-randomizes aura instance IDs.
-- The cdID<->spell catalog and child bindings are UNCHANGED, so the recovery is
-- a targeted aura RE-CAPTURE in the Blizzard mirror (re-stamps the instance IDs),
-- NOT a full catalog Walk deferred to combat end. These boundary events are
-- handled directly by the mirror's event frame so the re-capture runs in combat
-- (no PLAYER_REGEN_ENABLED end-of-pull stutter).
for _, evt in ipairs({ "CHALLENGE_MODE_START", "ENCOUNTER_START", "PVP_MATCH_ACTIVE" }) do
    assert(
        countPlain(mirror, 'RegisterEvent("' .. evt .. '")') >= 1,
        evt .. " must be handled by the Blizzard mirror (cdm_blizz_mirror.lua) so the "
            .. "re-randomized aura instance IDs are re-captured live on key entry."
    )
end

-- The mirror's boundary handler must run an aura re-capture
-- (HandleUnitAuraChanged / CaptureAurasFromUnit), not a full catalog Walk. Walk
-- rebuilds the cdID<->spell catalog + child bindings, which do NOT change on a
-- reroll, and was the deferred end-of-pull cost this fix removes.
assert(
    countPlain(mirror, "HandleUnitAuraChanged") >= 1
        or countPlain(mirror, "CaptureAurasFromUnit") >= 1,
    "the mirror's reroll handler must re-capture auras (HandleUnitAuraChanged / "
        .. "CaptureAurasFromUnit) to re-stamp the re-randomized instance IDs."
)

-- The resolver must NOT also fire a catalog rebuild on those boundaries — that
-- was the old path that deferred a full mirror Walk to PLAYER_REGEN_ENABLED.
for _, evt in ipairs({ "CHALLENGE_MODE_START", "ENCOUNTER_START", "PVP_MATCH_ACTIVE" }) do
    assert(
        countPlain(resolvers, 'RegisterEvent("' .. evt .. '")') == 0,
        evt .. " should no longer trigger a cdm_resolvers catalog rebuild — the "
            .. "mirror owns the cheap in-combat aura re-capture for it now."
    )
end

-- The STRUCTURAL catalog-rebuild path (spec / talent / spell-list changes) must
-- still publish to a live consumer, or cooldown bindings would go stale on a
-- real catalog reshape.
assert(
    countPlain(resolvers, 'publish("CDM:CATALOG_REBUILT")') >= 1,
    "expected RebuildCatalog() to still publish CDM:CATALOG_REBUILT for structural reshapes"
)
local subscriberCount = 0
for _, text in pairs(sources) do
    subscriberCount = subscriberCount + countPlain(text, 'Subscribe("CDM:CATALOG_REBUILT"')
    subscriberCount = subscriberCount + countPlain(text, "Subscribe('CDM:CATALOG_REBUILT'")
end
assert(
    subscriberCount >= 1,
    "CDM:CATALOG_REBUILT is published for structural catalog reshapes but NO module "
        .. "subscribes to it; the rebuild never reaches a consumer."
)

print("OK: cdm_challenge_mode_catalog_rebuild_test")
