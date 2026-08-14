-- tests/unit/migration_floor_collapse_test.lua
-- Run: lua5.1 tests/unit/migration_floor_collapse_test.lua
-- Verifies the stable schema-47 floor and the single direct schema-60 gate:
--   - stored < 47 → floored (wiped, _needsStarterReseed, stamped 60)
--   - stored == 47 → NOT floored; the complete transform runs and stamps 60
--   - stored == 59 → burned alpha stamp; re-enters the same gate, rebrand
--     included, and the transform is idempotent against already-final data
local ns = dofile("tools/_addon_env.lua").LoadCore()
local M = ns.Migrations

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

-- 1) Below-floor profile is wiped + flagged for starter reseed.
do
    local profile = { _schemaVersion = 46, buffBorders = { buffIconSize = 99 }, someModule = { foo = true } }
    M.RunOnProfile(profile)
    check("below-floor (46) wiped: user data gone", profile.someModule == nil, tostring(profile.someModule))
    check("below-floor (46) flagged _needsStarterReseed", profile._needsStarterReseed == true, tostring(profile._needsStarterReseed))
    check("below-floor (46) stamped to CURRENT (current)", profile._schemaVersion == M.CURRENT_SCHEMA_VERSION, tostring(profile._schemaVersion))
end

-- 2) At-floor profile (47) is NOT floored; the squash runs RestoreBuffDebuffSplit +
-- PrunePrivateAuras + SeedAuraElements + the rest. The user's buffIconSize is not
-- wiped — the aura-elements seed reshapes it into a buffAuras element (flat key
-- pruned, value preserved).
do
    local profile = { _schemaVersion = 47, buffBorders = { enableBuffs = true, buffIconSize = 35 }, frameAnchoring = { buffFrame = { parent = "minimap" } } }
    M.RunOnProfile(profile)
    local buffEl = profile.buffBorders and profile.buffBorders.buffAuras
        and profile.buffBorders.buffAuras.elements and profile.buffBorders.buffAuras.elements["*"]
        and profile.buffBorders.buffAuras.elements["*"][1]
    check("at-floor (47) NOT wiped: buffIconSize reshaped to element iconSize=35",
        buffEl and buffEl.iconSize == 35, buffEl and tostring(buffEl.iconSize))
    check("at-floor (47) flat buffIconSize pruned by the elements seed", profile.buffBorders.buffIconSize == nil, tostring(profile.buffBorders.buffIconSize))
    check("at-floor (47) NOT flagged for reseed", profile._needsStarterReseed == nil, tostring(profile._needsStarterReseed))
    check("at-floor (47) debuffFrame restored", profile.frameAnchoring.debuffFrame ~= nil, "debuffFrame nil")
    check("at-floor (47) stamped to current (current)", profile._schemaVersion == M.CURRENT_SCHEMA_VERSION, tostring(profile._schemaVersion))
end

-- 2b) PrunePrivateAuras on the stable schema-47 path: stored
-- privateAuras subtables are stripped from every tree the removed defaults
-- carried them in; sibling keys survive.
do
    local profile = {
        _schemaVersion = 47,
        quiUnitFrames = {
            player = { privateAuras = { enabled = true, iconSize = 24 }, portrait = { enabled = true } },
            target = { privateAuras = { enabled = false } },
            focus  = { privateAuras = { maxPerFrame = 3 } },
        },
        quiGroupFrames = {
            party = { privateAuras = { enabled = true }, frames = { width = 90 } },
            raid  = { privateAuras = { growDirection = "RIGHT" } },
        },
    }
    M.RunOnProfile(profile)
    check("prunes quiUnitFrames.player.privateAuras", profile.quiUnitFrames.player.privateAuras == nil,
        tostring(profile.quiUnitFrames.player.privateAuras))
    check("prunes quiUnitFrames.target.privateAuras", profile.quiUnitFrames.target.privateAuras == nil,
        tostring(profile.quiUnitFrames.target.privateAuras))
    check("prunes quiUnitFrames.focus.privateAuras", profile.quiUnitFrames.focus.privateAuras == nil,
        tostring(profile.quiUnitFrames.focus.privateAuras))
    check("prunes quiGroupFrames.party.privateAuras", profile.quiGroupFrames.party.privateAuras == nil,
        tostring(profile.quiGroupFrames.party.privateAuras))
    check("prunes quiGroupFrames.raid.privateAuras", profile.quiGroupFrames.raid.privateAuras == nil,
        tostring(profile.quiGroupFrames.raid.privateAuras))
    check("prune preserves sibling unit settings", profile.quiUnitFrames.player.portrait
        and profile.quiUnitFrames.player.portrait.enabled == true, "portrait clobbered")
    check("prune preserves sibling group settings", profile.quiGroupFrames.party.frames
        and profile.quiGroupFrames.party.frames.width == 90, "frames clobbered")
    check("stable path stamps to CURRENT (current)", profile._schemaVersion == M.CURRENT_SCHEMA_VERSION,
        tostring(profile._schemaVersion))
end

-- 3) Burned alpha stamp 59 (the QUI 5.0 squash number, folded into v60).
do
    local profile = {
        _schemaVersion = 59,
        quiUnitFrames = { player = { width = 220 } },
        fonts = { global = "__QUI_GLOBAL__" },
    }
    M.RunOnProfile(profile)
    check("alpha stamp (59) quiUnitFrames preserved",
        profile.quiUnitFrames and profile.quiUnitFrames.player
        and profile.quiUnitFrames.player.width == 220, tostring(profile.quiUnitFrames))
    check("alpha stamp (59) font sentinel preserved",
        profile.fonts.global == "__QUI_GLOBAL__", tostring(profile.fonts.global))
    check("alpha stamp (59) NOT floored", profile._needsStarterReseed == nil,
        tostring(profile._needsStarterReseed))
    check("alpha stamp (59) stamped to CURRENT (current)", profile._schemaVersion == M.CURRENT_SCHEMA_VERSION,
        tostring(profile._schemaVersion))
end

-- 4) The collapsed gate is idempotent against already-final data: a profile
-- re-stamped back to 59 after a full run comes out byte-identical (the backup
-- container excepted, which legitimately records the new fromVersion).
do
    local function deepcopy(v, seen)
        if type(v) ~= "table" then return v end
        seen = seen or {}
        if seen[v] then return seen[v] end
        local t = {}
        seen[v] = t
        for k, val in pairs(v) do t[deepcopy(k, seen)] = deepcopy(val, seen) end
        return t
    end
    local function ser(v, indent)
        indent = indent or ""
        if type(v) ~= "table" then return tostring(v) end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local out = {}
        for _, k in ipairs(keys) do
            out[#out + 1] = indent .. tostring(k) .. " = " .. ser(v[k], indent .. "  ")
        end
        return "{\n" .. table.concat(out, "\n") .. "\n" .. indent .. "}"
    end

    local profile = {
        _schemaVersion = 47,
        quiUnitFrames = { player = { auras = { filters = { NOT_CANCELABLE = true } } } },
        quiGroupFrames = { defensiveIndicator = { enabled = true, iconSize = 20 } },
        buffBorders = { enableBuffs = true, buffIconSize = 35, privateAuras = { enabled = true } },
        frameAnchoring = { buffFrame = { parent = "minimap" } },
        fonts = { global = "__QUI_GLOBAL__" },
    }
    M.RunOnProfile(profile)

    local first = deepcopy(profile)
    first._migrationBackup = nil

    profile._schemaVersion = 59
    M.RunOnProfile(profile)
    local second = deepcopy(profile)
    second._migrationBackup = nil

    check("re-entry from 59 leaves final data unchanged", ser(first) == ser(second),
        "migration is not idempotent against already-final data")
end

print("migration_floor_collapse_test " .. (failures == 0 and "OK" or "FAILED"))
os.exit(failures == 0 and 0 or 1)
