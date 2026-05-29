-- tests/unit/cdm_challenge_mode_catalog_rebuild_test.lua
-- Regression: entering a Mythic+ key (or an encounter / rated PvP match) must
-- rebuild the CDM catalog through a LIVE path.
--
-- cdm_runtime.lua's RebuildCatalog() is wired to fire on CHALLENGE_MODE_START
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
    "cdm_runtime.lua",
    "cdm_spelldata.lua",
    "cdm_blizz_mirror.lua",
    "cdm_containers.lua",
    "cdm_icon_renderer.lua",
    "cdm_bar_renderer.lua",
    "cdm_domain.lua",
    "cdm_frame_writes.lua",
    "hud_visibility.lua",
}

local sources = {}
for _, name in ipairs(CDM_FILES) do
    sources[name] = readAll("modules/cdm/" .. name)
end

local runtime = sources["cdm_runtime.lua"]

-- Sanity: the trigger and the publish exist, so the consumer assertion below
-- stays meaningful (if either disappears, this test should be revisited).
assert(
    countPlain(runtime, 'RegisterEvent("CHALLENGE_MODE_START")') >= 1,
    "expected CHALLENGE_MODE_START to be registered as a catalog rebuild trigger"
)
assert(
    countPlain(runtime, 'publish("CDM:CATALOG_REBUILT")') >= 1,
    "expected RebuildCatalog() to publish CDM:CATALOG_REBUILT"
)

-- THE REGRESSION: the published lifecycle event must reach a consumer. A
-- consumer subscribes to the resolver bus event. Without one, the catalog
-- rebuild triggered on key entry does nothing.
local subscriberCount = 0
for _, text in pairs(sources) do
    subscriberCount = subscriberCount + countPlain(text, 'Subscribe("CDM:CATALOG_REBUILT"')
    subscriberCount = subscriberCount + countPlain(text, "Subscribe('CDM:CATALOG_REBUILT'")
end

assert(
    subscriberCount >= 1,
    "CDM:CATALOG_REBUILT is published on CHALLENGE_MODE_START / ENCOUNTER_START / "
        .. "PVP_MATCH_ACTIVE but NO module subscribes to it. The catalog rebuild "
        .. "never reaches a consumer, so cooldown/aura bindings stay stale on key "
        .. "entry until /reload. Wire a consumer (e.g. re-walk the Blizzard mirror "
        .. "to re-capture re-randomized aura instance IDs) or remove the dead "
        .. "publish + _catalogVersion bump."
)

print("OK: cdm_challenge_mode_catalog_rebuild_test")
