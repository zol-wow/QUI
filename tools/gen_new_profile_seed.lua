--[[
  gen_new_profile_seed.lua

  One-shot generator: decode a full QUI profile export string (QUI1:), strip
  it, and emit importstrings/starter_profile.lua — the compressed Starter
  Profile string that is BOTH the fresh-install seed (decoded lazily by
  core/new_profile_defaults.lua via the AceDB OnNewProfile hook) and the
  Profiles-tab preset. Existing profiles are never touched.

  Meta/latch/runtime keys are stripped (any "_"-prefixed key at ANY depth +
  the fpsBackup runtime CVar buffer) so the seed carries ONLY genuine
  settings; the migration/compat layers still stamp
  _schemaVersion/_defaultsVersion on the seeded profile afterwards exactly as
  they do for a fresh profile. Orphan CDM container satellites (anchors/
  cooldown-effect overrides/glow keys left behind by a deleted container —
  same rule as core/migrations.lua's v51 squash step (f)) are purged too.

  Per-character CDM spell lists under ncdm (ownedSpells/dormantSpells/
  removedSpells/spellOverrides/entries) are purged as well — see
  PurgeCharacterCDMLists below for why shipping them empties the Composer
  for every new user.

  Usage:
    lua tools/gen_new_profile_seed.lua <path-to-string-file>
    lua tools/gen_new_profile_seed.lua -                       # string on stdin
    lua tools/gen_new_profile_seed.lua --from-seed              # reprocess the
                                                                  -- shipped string in place
]]

local function ScriptDir()
    local p = (arg and arg[0]) or ""
    p = p:gsub("\\", "/")
    local dir = p:match("(.*/)")
    if dir == nil or dir == "" then return "./" end
    return dir
end

local env = dofile(ScriptDir() .. "_addon_env.lua")
env.LoadLibs()

local LibDeflate    = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

----------------------------------------------------------------------------
-- Strip set: anything that is migration/runtime state, not a setting.
----------------------------------------------------------------------------
local function ShouldStripTopKey(k)
    if type(k) ~= "string" then return false end
    if k:sub(1, 1) == "_" then return true end   -- every meta/latch key is "_"-prefixed
    if k == "fpsBackup" then return true end       -- runtime CVar backup buffer (defaults.lua = nil)
    if k == "powerBarAltPosition" then return true end -- dead legacy position store, no runtime consumer
    return false
end

----------------------------------------------------------------------------
-- Orphan-satellite purge: DeleteContainer historically leaked per-container
-- keys (frameAnchoring/cooldownEffects/customGlow) that never got cleaned up
-- when the container itself was removed. Mirrors
-- Migrations.PurgeOrphanContainerSatellites (core/migrations.lua v51 squash step (f)) — kept
-- as its own copy here because this tool cannot load addon files (only
-- tools/_addon_env.lua's headless lib stubs). Keep the customGlow suffix
-- list in lockstep with the migrations.lua copy. (cdm_containers.lua's
-- PurgeContainerSatellites needs no list — it prefix-matches on a known
-- containerKey.)
----------------------------------------------------------------------------
-- Ordered longest-suffix-first: several suffixes share a tail (every
-- Pandemic*Enabled variant ends in "Enabled"), so a shorter generic suffix
-- must never be tried before the longer specific one it is a tail of, or it
-- mis-derives the container prefix (e.g. stripping bare "Enabled" from
-- "<liveKey>PandemicBuffEnabled" yields "<liveKey>PandemicBuff", which is
-- not a live container key, wrongly orphaning a LIVE key). The match loop
-- below stops at the first suffix that matches the key's tail at all
-- (break unconditionally on match, not only on delete) so this ordering is
-- load-bearing, not cosmetic. Keep in lockstep with core/migrations.lua.
local CDM_GLOW_SUFFIXES = {
    "PandemicDebuffEnabled", "PandemicBuffEnabled", "PandemicEnabled",
    "Thickness", "Frequency", "GlowType", "XOffset", "YOffset", "Enabled",
    "Color", "Scale", "Lines",
}

local function PurgeOrphanSatellites(p)
    local ncdm = p.ncdm
    local live = {}
    if ncdm and type(ncdm.containers) == "table" then
        for key in pairs(ncdm.containers) do live[key] = true end
    end

    local anchors = p.frameAnchoring
    if type(anchors) == "table" then
        local toRemove = {}
        for k in pairs(anchors) do
            if type(k) == "string" then
                local key = k:match("^cdmCustom_(.+)$")
                if key and not live[key] then toRemove[#toRemove + 1] = k end
            end
        end
        for _, k in ipairs(toRemove) do anchors[k] = nil end
    end

    local effects = p.cooldownEffects
    if type(effects) == "table" then
        local toRemove = {}
        for k in pairs(effects) do
            if type(k) == "string" then
                local key = k:match("^hide_(.+)$")
                if key and not live[key] then toRemove[#toRemove + 1] = k end
            end
        end
        for _, k in ipairs(toRemove) do effects[k] = nil end
    end

    local glow = p.customGlow
    if type(glow) == "table" then
        local toRemove = {}
        for k in pairs(glow) do
            if type(k) == "string" then
                for _, suffix in ipairs(CDM_GLOW_SUFFIXES) do
                    local key = k:match("^(.+)" .. suffix .. "$")
                    if key then
                        -- First matching suffix wins and stops the search
                        -- (see the ordering note on CDM_GLOW_SUFFIXES above).
                        -- Only container-shaped prefixes; never touch the
                        -- essential/utility builtin glow keys.
                        if key ~= "essential" and key ~= "utility"
                            and (key:find("^custom_") or key:find("^customBar_"))
                            and not live[key] then
                            toRemove[#toRemove + 1] = k
                        end
                        break
                    end
                end
            end
        end
        for _, k in ipairs(toRemove) do glow[k] = nil end
    end

    return true
end

----------------------------------------------------------------------------
-- Per-character CDM spell-list purge.
--
-- The source profile is captured from a REAL character, so every CDM
-- container carries that character's curated spell list. Shipping those in
-- the new-profile seed is a hard bug, not cosmetic noise: AceDB's
-- OnNewProfile hook deep-applies the seed before the first read, so
-- `ncdm.<key>.ownedSpells` is non-nil on a fresh install, and
-- CDMSpellData:SnapshotBlizzardCDM (cdm_spelldata.lua) bails on
-- `db.ownedSpells ~= nil`. The real per-character Blizzard snapshot then
-- never runs for ANY new user, on any class, and reports ready=true so
-- nothing retries. A non-matching class sees every seeded row fall into the
-- composer's "Dormant — Not Learned on This Character" bucket: empty grid,
-- empty HUD, permanent across reloads. (The foreign-class filter does not
-- save it — seeded rows carry no `source`, and that filter only applies to
-- `source == "blizzardCDM"` rows.)
--
-- ownedSpells MUST end up absent, not `{}`: an empty table is still
-- non-nil and suppresses the snapshot exactly the same way.
--
-- Scoped to an explicit root list so the walk cannot touch same-named keys
-- elsewhere in the profile (`chat.newMessageSound.entries` is a sound-routing
-- list and must survive).
--
-- customTrackers is a SECOND root, not a convenience: a custom bar's rows are
-- stored twice — `ncdm.containers.customBar_<id>.entries` and
-- `customTrackers.bars[n].entries`, which sits OUTSIDE ncdm. An ncdm-only walk
-- leaves the customTrackers copy in the shipped string. The post-migration
-- fixture still comes out clean (migration rebuilds customTrackers from the
-- ncdm side), so the leak is invisible there — purge both roots rather than
-- leaning on that side effect.
--
-- Guard: tests/unit/starter_seed_no_cdm_spell_lists_test.lua
----------------------------------------------------------------------------
-- `entries` (custom containers) is purged for a different reason than the
-- builtin lists. It never gated the snapshot — SnapshotBlizzardCDM returns
-- early on non-builtin keys (`IsBuiltinContainerKey`) — and a custom bar has
-- no re-seed path, so an emptied one stays empty until the user fills it.
-- Purged anyway (Drew, 2026-07-26): the shipped list was residue, not a
-- curated bar. Its six rows included TWO mutually-exclusive race-locked
-- spells (26297 Berserking/Troll, 312411 Bag of Tricks/Vulpera — verified
-- against libs/LibOpenRaid race tables), so no single character could ever
-- have owned that list. Shipping any character's curated rows is the bug
-- class; a configured-but-empty Custom Bar 1 is the intended shape.
local CHARACTER_CDM_LIST_KEYS = {
    ownedSpells    = true,  -- the curated tracked list — the load-bearing one
    dormantSpells  = true,  -- shelf of that character's unlearned rows
    removedSpells  = true,  -- that character's explicit removals
    spellOverrides = true,  -- per-spellID display tweaks, keyed by their spells
    entries        = true,  -- custom-container curated list (same role as ownedSpells)
}

local PURGE_ROOTS = { "ncdm", "customTrackers" }

local function PurgeCharacterCDMLists(p)
    local purged = 0
    local function walk(t)
        local doomed
        for k, v in pairs(t) do
            if type(k) == "string" and CHARACTER_CDM_LIST_KEYS[k] then
                doomed = doomed or {}
                doomed[#doomed + 1] = k
            elseif type(v) == "table" then
                walk(v)
            end
        end
        if doomed then
            for _, k in ipairs(doomed) do
                t[k] = nil
                purged = purged + 1
            end
        end
    end
    for _, root in ipairs(PURGE_ROOTS) do
        local t = p[root]
        if type(t) == "table" then walk(t) end
    end

    return purged
end

----------------------------------------------------------------------------
-- Seeded custom-bar purge.
--
-- Emptying a custom bar's `entries` above still leaves the CONTAINER, so a
-- fresh install shows an enabled, empty bar literally named "Custom Bar 1".
-- That is capture-character residue, not curated content: both the id
-- (`anon_1`) and the name are the values the addon auto-generates when a user
-- clicks "New". Users create their own bars; the seed ships none.
--
-- Two stores, only one of them live:
--   * `customTrackers.bars` + `ncdm.containers.customBar_<id>` — the live pair.
--   * `ncdm.customBars` — DEAD. Nothing in the suite reads it; the only
--     `customBars` in live code is `hudLayering.customBars` (a strata NUMBER,
--     core/defaults.lua) which this must not touch. It has no defaults
--     counterpart either, so profile_io's type validation — which walks the
--     defaults tree — never sees it, and ~250 lines of unread bar data rode
--     along in every profile.
--
-- ORDER: this must run BEFORE PurgeOrphanSatellites. That function derives its
-- live-set from `ncdm.containers`, so it only reclaims the glow/anchor keys
-- once the container is already gone.
--
-- Guard: tests/unit/starter_seed_no_cdm_spell_lists_test.lua
----------------------------------------------------------------------------
local function PurgeSeededCustomBars(p)
    local purged = 0
    local removedIDs = {}

    local function noteID(bar)
        if type(bar) == "table" and type(bar.id) == "string" then
            removedIDs[bar.id] = true
        end
    end

    local ncdm = p.ncdm
    if type(ncdm) == "table" then
        local containers = ncdm.containers
        if type(containers) == "table" then
            local doomed = {}
            for k, v in pairs(containers) do
                -- builtIn == false is the fallback for any historical row that
                -- predates containerType being written.
                if type(v) == "table"
                    and (v.containerType == "customBar" or v.builtIn == false) then
                    doomed[#doomed + 1] = k
                    noteID(v)
                end
            end
            for _, k in ipairs(doomed) do
                containers[k] = nil
                purged = purged + 1
            end
        end

        if type(ncdm.customBars) == "table" then
            if type(ncdm.customBars.bars) == "table" then
                for _, bar in pairs(ncdm.customBars.bars) do noteID(bar) end
            end
            ncdm.customBars = nil
            purged = purged + 1
        end
    end

    -- customTrackers keeps its global settings (fade, hide-when-*, keybinds);
    -- only the per-bar list is character data.
    local trackers = p.customTrackers
    if type(trackers) == "table" and type(trackers.bars) == "table" then
        if next(trackers.bars) ~= nil then
            for _, bar in pairs(trackers.bars) do noteID(bar) end
            purged = purged + 1
        end
        trackers.bars = {}
    end

    -- PurgeOrphanSatellites only matches the "cdmCustom_" anchor prefix; the
    -- legacy store uses "customCDMBar:<id>", which it would leave behind.
    local anchors = p.frameAnchoring
    if type(anchors) == "table" then
        local doomed = {}
        for k in pairs(anchors) do
            if type(k) == "string" then
                local id = k:match("^customCDMBar:(.+)$")
                if id and removedIDs[id] then doomed[#doomed + 1] = k end
            end
        end
        for _, k in ipairs(doomed) do
            anchors[k] = nil
            purged = purged + 1
        end
    end

    return purged
end

----------------------------------------------------------------------------
-- Decode
----------------------------------------------------------------------------
local function ReadInput(path)
    if path == "-" then return io.read("*a") end
    local f, err = io.open(path, "rb")
    if not f then error("Could not open input: " .. tostring(err)) end
    local data = f:read("*a")
    f:close()
    return data
end

local function Decode(raw)
    raw = (raw:gsub("%s+", ""))
    assert(raw:sub(1, #"QUI1:") == "QUI1:", "expected a QUI1: full-profile string")
    local compressed = assert(LibDeflate:DecodeForPrint(raw:sub(#"QUI1:" + 1)), "DecodeForPrint failed")
    local serialized = assert(LibDeflate:DecompressDeflate(compressed), "DecompressDeflate failed")
    local ok, payload = AceSerializer:Deserialize(serialized)
    assert(ok, "Deserialize failed: " .. tostring(payload))
    assert(type(payload) == "table", "payload is not a table")
    return payload
end

----------------------------------------------------------------------------
-- Recursive strip: ShouldStripTopKey applies at EVERY depth, not just the
-- root, so nested meta/latch keys (ncdm._specProfiles, chat.tabs[n].
-- _groupsVersion, etc.) never ship. Returns only the top-level doomed-key
-- list for the summary printout; deeper strips happen silently in the
-- recursive calls.
----------------------------------------------------------------------------
local function StripMetaKeysDeep(t)
    local doomed = {}
    for k, v in pairs(t) do
        if ShouldStripTopKey(k) then
            doomed[#doomed + 1] = k
        elseif type(v) == "table" then
            StripMetaKeysDeep(v)
        end
    end
    table.sort(doomed, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(doomed) do t[k] = nil end
    return doomed
end

----------------------------------------------------------------------------
-- Main
----------------------------------------------------------------------------
local inPath  = arg[1] or error("usage: gen_new_profile_seed.lua <string-file>|--from-seed [out.lua]")
local outPath = arg[2] or (ScriptDir() .. "../importstrings/starter_profile.lua")

local profile
if inPath == "--from-seed" then
    -- Reprocess the shipped string in place: register the loader, decode the
    -- current starter_profile.lua data, re-strip + re-encode.
    _G.QUI = _G.QUI or {}
    _G.QUI._importLoaders = {}
    assert(loadfile(ScriptDir() .. "../importstrings/starter_profile.lua"))("QUI", {})
    local loader = assert(_G.QUI._importLoaders.StarterProfile, "StarterProfile loader missing")
    local entry = loader()
    local data = type(entry) == "table" and entry.data or entry
    profile = Decode(assert(data, "starter_profile.lua carries no data string"))
else
    profile = Decode(ReadInput(inPath))
end
profile._quiBundledGlobals = nil

local strippedTop = StripMetaKeysDeep(profile)
-- Order is load-bearing: the custom-bar purge removes containers, and
-- PurgeOrphanSatellites reclaims their anchor/effect/glow keys by diffing
-- against the surviving ncdm.containers set. Satellites must run LAST.
local purgedCDMLists = PurgeCharacterCDMLists(profile)
local purgedCustomBars = PurgeSeededCustomBars(profile)
PurgeOrphanSatellites(profile)

-- Force the shipped new-user theme to QUI's Sky Blue, regardless of the
-- source profile's theme. general.themePreset is the live read (main.lua and
-- the options theme picker, QUI_Options/framework.lua); the top-level copy is
-- the legacy store. Set both + the derived accent color so every consumer
-- resolves sky blue. "Sky Blue" -> {0.376, 0.647, 0.980} (#60A5FA).
local function ApplyThemeOverride(p)
    local function skyBlue() return { 0.376, 0.647, 0.98, 1 } end
    p.themePreset = "Sky Blue"
    p.addonAccentColor = skyBlue()
    if type(p.general) ~= "table" then p.general = {} end
    p.general.themePreset = "Sky Blue"
    p.general.addonAccentColor = skyBlue()
    p.general.skinUseClassColor = false   -- picker keeps this in sync with the preset
end
ApplyThemeOverride(profile)

-- Force specific shipped-seed settings that differ from whatever the source
-- profile happened to hold. --from-seed is re-strip only, so this table is the
-- ONLY way a curated value reaches the seed; hand-editing the blob is not an
-- option. Keep each entry commented with why it is pinned.
local function ApplySettingOverrides(p)
    -- Drawer toggle icon: new installs get the QUI mark, not the legacy
    -- Quazii hammer. Existing profiles are untouched by design — a stored
    -- "hammer" cannot be told apart from a deliberate user choice.
    if type(p.minimap) ~= "table" then p.minimap = {} end
    if type(p.minimap.buttonDrawer) ~= "table" then p.minimap.buttonDrawer = {} end
    p.minimap.buttonDrawer.toggleIcon = "qui"
    if type(p.mplusTimer) == "table" then p.mplusTimer.forcesTextFormat = "both" end
end
ApplySettingOverrides(profile)

----------------------------------------------------------------------------
-- Encode: payload = seed keys at top level + the empty bundled-globals block
-- (core/new_profile_defaults.lua drops it on decode; profile_io's import
-- validation expects the key on preset installs).
----------------------------------------------------------------------------
local payload = {}
for k, v in pairs(profile) do payload[k] = v end
payload._quiBundledGlobals = { ncdm_specTrackerSpells = {}, specTrackerSpells = {} }

local serialized = AceSerializer:Serialize(payload)
local compressed = LibDeflate:CompressDeflate(serialized)
local encoded    = "QUI1:" .. LibDeflate:EncodeForPrint(compressed)

-- Pick a long-bracket level that cannot collide with the blob contents.
local bracket = "[["
local close   = "]]"
if encoded:find("]]", 1, true) then bracket, close = "[==[", "]==]" end

local body = table.concat({
    "-- QUI Starter Profile export string.",
    "-- AUTO-GENERATED by tools/gen_new_profile_seed.lua -- DO NOT EDIT BY HAND.",
    "-- SINGLE SOURCE for the fresh-install seed (decoded lazily by",
    "-- core/new_profile_defaults.lua via the OnNewProfile hook) AND the",
    "-- Profiles-tab \"Starter Profile\" preset — they cannot drift.",
    "-- Stripped on generation: every \"_\"-prefixed meta/latch key at ANY depth +",
    "-- fpsBackup + orphan CDM container satellites + per-character CDM spell",
    "-- lists under ncdm (ownedSpells/dormantSpells/removedSpells/",
    "-- spellOverrides/entries -- ownedSpells MUST stay absent so",
    "-- SnapshotBlizzardCDM seeds each character from Blizzard's viewer).",
    "-- Regenerate after curating: lua tools/gen_new_profile_seed.lua <string-file>",
    "-- Reprocess in place (re-strip only): lua tools/gen_new_profile_seed.lua --from-seed",
    "-- Decode guard: tests/unit/starter_preset_matches_seed_test.lua",
    "",
    "QUI._importLoaders.StarterProfile = function()",
    "    return {",
    "    name = \"Starter Profile\",",
    "    description = \"QUI starter profile (the shipped new-profile defaults)\",",
    "    data = " .. bracket .. encoded .. close .. ",",
    "    }",
    "end",
    "",
}, "\n")

local f = assert(io.open(outPath, "wb"))
f:write(body)
f:close()

local kept = 0
for _ in pairs(profile) do kept = kept + 1 end
io.write(string.format(
    "Wrote %s\n  kept %d top-level setting keys, stripped %d top-level meta/runtime keys"
        .. " (deep strip also ran below top level): %s\n"
        .. "  purged %d per-character CDM spell list(s) under ncdm/customTrackers\n"
        .. "  purged %d seeded custom-bar object(s)/store(s)\n",
    outPath, kept, #strippedTop, table.concat(strippedTop, ", "),
    purgedCDMLists, purgedCustomBars))
