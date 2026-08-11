-- tests/unit/starter_seed_no_cdm_spell_lists_test.lua
-- Run: lua tests/unit/starter_seed_no_cdm_spell_lists_test.lua
--
-- The shipped Starter Profile string is captured from a REAL character, so
-- its CDM containers arrive carrying that character's curated spell lists.
-- Shipping them breaks the Composer for every new user on every class:
--
--   1. core/new_profile_defaults.lua's ApplyNewProfileSeed deep-applies the
--      seed from AceDB's OnNewProfile hook, before the profile's first read.
--   2. ncdm.<key>.ownedSpells is therefore non-nil on a fresh install.
--   3. CDMSpellData:SnapshotBlizzardCDM bails on `db.ownedSpells ~= nil`
--      and reports ready=true, so the real per-character Blizzard snapshot
--      never runs and nothing retries it.
--   4. On a non-matching class every seeded row is unknown, so the Composer
--      files all of them under "Dormant — Not Learned on This Character":
--      empty grid, empty HUD, permanent across reloads.
--
-- The foreign-class applicability filter does NOT catch this: seeded rows
-- carry no `source`, and that filter only screens `source == "blizzardCDM"`
-- rows (cdm_spelldata.lua IsEntryApplicableForContainer).
--
-- `ownedSpells = {}` is just as broken as a populated list — an empty table
-- is still non-nil. This test therefore asserts ABSENCE, not emptiness.
--
-- Producer side: tools/gen_new_profile_seed.lua PurgeCharacterCDMLists.

local env = dofile("tools/_addon_env.lua")
local ns  = env.LoadCore()

local seed = assert(ns.GetNewProfileSeed and ns.GetNewProfileSeed(),
    "ns.GetNewProfileSeed() returned nothing")

-- Keys the generator purges from every table under the roots below, at any
-- depth. `entries` covers custom containers: those never gated the snapshot
-- (SnapshotBlizzardCDM returns early on non-builtin keys) but the shipped
-- list was residue rather than a curated bar — it held two mutually-exclusive
-- race-locked spells, so no single character could have owned it.
local FORBIDDEN = {
    ownedSpells    = true,
    dormantSpells  = true,
    removedSpells  = true,
    spellOverrides = true,
    entries        = true,
}

-- customTrackers is a second root: a custom bar's rows live BOTH at
-- ncdm.containers.customBar_<id>.entries and customTrackers.bars[n].entries,
-- and the latter is outside ncdm. Checking only ncdm passes while the
-- customTrackers copy still ships.
local ROOTS = { "ncdm", "customTrackers" }

assert(type(seed.ncdm) == "table",
    "seed lost its ncdm block entirely — the purge is too broad")

local offenders = {}
local function walk(t, path)
    for k, v in pairs(t) do
        local here = path .. "." .. tostring(k)
        if type(k) == "string" and FORBIDDEN[k] then
            local n = (type(v) == "table") and #v or -1
            offenders[#offenders + 1] = ("%s (%d entries)"):format(here, n)
        elseif type(v) == "table" then
            walk(v, here)
        end
    end
end
for _, root in ipairs(ROOTS) do
    local t = seed[root]
    if type(t) == "table" then walk(t, root) end
end

table.sort(offenders)
assert(#offenders == 0,
    "starter seed ships per-character CDM spell lists — a fresh install will\n"
    .. "suppress SnapshotBlizzardCDM and render an empty Composer.\n"
    .. "Regenerate with: lua tools/gen_new_profile_seed.lua --from-seed\n"
    .. "Offending keys:\n  " .. table.concat(offenders, "\n  "))

-- The purge must not take the container layout settings with it: those ARE
-- the curated part of the starter profile and must still ship.
local essential = seed.ncdm.essential
assert(type(essential) == "table", "ncdm.essential missing from seed")
assert(type(essential.row1) == "table" and type(essential.row1.iconCount) == "number",
    "ncdm.essential.row1.iconCount missing — the purge ate layout settings")

---------------------------------------------------------------------------
-- Seeded custom bars.
--
-- Emptying a bar's `entries` still leaves the CONTAINER, so a fresh install
-- showed an enabled, empty bar named "Custom Bar 1". Both its id (`anon_1`)
-- and its name are the values the addon auto-generates on "New", i.e. capture
-- residue, not curated content. The seed ships no custom bars at all.
---------------------------------------------------------------------------
local barOffenders = {}

local containers = seed.ncdm.containers
if type(containers) == "table" then
    for k, v in pairs(containers) do
        if type(v) == "table"
            and (v.containerType == "customBar" or v.builtIn == false) then
            barOffenders[#barOffenders + 1] = "ncdm.containers." .. tostring(k)
        end
    end
end

-- ncdm.customBars is a DEAD store: nothing in the suite reads it, and it has
-- no core/defaults.lua counterpart, so profile_io's defaults-tree type
-- validation never sees it. It must not come back.
if seed.ncdm.customBars ~= nil then
    barOffenders[#barOffenders + 1] = "ncdm.customBars (dead store)"
end

local bars = seed.customTrackers and seed.customTrackers.bars
if type(bars) == "table" and next(bars) ~= nil then
    barOffenders[#barOffenders + 1] = "customTrackers.bars (non-empty)"
end

-- Satellites. PurgeOrphanSatellites reclaims "cdmCustom_" anchors, glow keys
-- and hide_ effects by diffing against ncdm.containers — but only if it runs
-- AFTER the containers are removed. "customCDMBar:" is a shape it never
-- matched at all. Both are asserted here so a purge-order regression fails
-- loudly instead of shipping orphans.
for k in pairs(type(seed.frameAnchoring) == "table" and seed.frameAnchoring or {}) do
    if type(k) == "string"
        and (k:find("^cdmCustom_") or k:find("^customCDMBar:")) then
        barOffenders[#barOffenders + 1] = "frameAnchoring." .. k
    end
end
for k in pairs(type(seed.customGlow) == "table" and seed.customGlow or {}) do
    if type(k) == "string" and k:find("^customBar_") then
        barOffenders[#barOffenders + 1] = "customGlow." .. k
    end
end

table.sort(barOffenders)
assert(#barOffenders == 0,
    "starter seed ships custom-bar residue — a fresh install shows a bar the\n"
    .. "user never created, and orphaned satellites ride along.\n"
    .. "Regenerate with: lua tools/gen_new_profile_seed.lua --from-seed\n"
    .. "Offending keys:\n  " .. table.concat(barOffenders, "\n  "))

-- customTrackers keeps its GLOBAL settings — only the per-bar list is
-- character data. Its real children are bars / cdmBuffTracking / keybinds
-- (the fade + hide-when-* settings live under customTrackersVisibility, a
-- separate top-level key the purge never touches).
local trackers = seed.customTrackers
assert(type(trackers) == "table" and type(trackers.keybinds) == "table"
    and type(trackers.keybinds.keybindTextColor) == "table",
    "customTrackers.keybinds was purged — the bar purge is too broad")
assert(type(trackers.cdmBuffTracking) == "table",
    "customTrackers.cdmBuffTracking was purged — the bar purge is too broad")

-- hudLayering.customBars is an unrelated strata NUMBER. A purge keyed on the
-- name "customBars" rather than the ncdm path would clobber it.
local layering = seed.hudLayering
assert(type(layering) == "table" and type(layering.customBars) == "number",
    "hudLayering.customBars must survive as a number — the purge hit the wrong key")

-- Same-named keys OUTSIDE the CDM roots must be untouched: chat sound routing
-- also uses `entries`, and purging it would silently break new-message sounds.
local sound = seed.chat and seed.chat.newMessageSound
assert(type(sound) == "table" and type(sound.entries) == "table"
    and #sound.entries > 0,
    "chat.newMessageSound.entries was purged — the walk escaped its roots")

print("ok: starter seed carries no per-character CDM spell lists or custom bars")
