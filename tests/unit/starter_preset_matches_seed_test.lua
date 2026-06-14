-- tests/unit/starter_preset_matches_seed_test.lua
-- Run: lua tests/unit/starter_preset_matches_seed_test.lua
--
-- The Profiles-tab "Starter Profile" preset (importstrings/starter_profile.lua)
-- must stay byte-for-setting identical to the fresh-install seed
-- (core/new_profile_defaults.lua / ns.NewProfileSeed). Both are encodings of
-- the same shipped layout; if the seed is regenerated without re-running
-- tools/gen_starter_preset_from_seed.lua they drift and a fresh install no
-- longer matches the preset a user installs from the Profiles tab.
--
-- Compares DECODED TABLES, not the encoded blob: AceSerializer iterates
-- pairs() so the blob bytes are non-deterministic, but the decoded settings
-- are stable.

local env = dofile("tools/_addon_env.lua")
local ns  = env.LoadCore()
env.LoadLibs()
local LibDeflate    = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

assert(type(ns.NewProfileSeed) == "table", "ns.NewProfileSeed missing")

-- Load the preset string (sets QUI._importLoaders.StarterProfile).
_G.QUI = _G.QUI or {}
_G.QUI._importLoaders = {}
assert(loadfile("importstrings/starter_profile.lua"))()
local loader = _G.QUI._importLoaders.StarterProfile
assert(type(loader) == "function", "StarterProfile loader missing")
local preset = loader()
assert(type(preset) == "table" and type(preset.data) == "string", "preset.data missing")

-- User-facing rename: the preset must present as "Starter Profile".
assert(preset.name == "Starter Profile",
    "preset name must be 'Starter Profile', got: " .. tostring(preset.name))

-- Decode QUI1: -> table.
local raw = preset.data:gsub("^QUI1:", "")
local decompressed = LibDeflate:DecompressDeflate(LibDeflate:DecodeForPrint(raw))
assert(decompressed, "failed to decompress preset blob")
local ok, decoded = AceSerializer:Deserialize(decompressed)
assert(ok and type(decoded) == "table", "failed to deserialize preset blob")

-- Strip the bundled-globals envelope; compare profile settings to the seed.
decoded._quiBundledGlobals = nil

local function deepEqual(a, b, path)
    if type(a) ~= type(b) then
        return false, path .. ": type " .. type(a) .. " vs " .. type(b)
    end
    if type(a) ~= "table" then
        if a ~= b then
            return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
        end
        return true
    end
    for k, v in pairs(a) do
        local eq, why = deepEqual(v, b[k], path .. "." .. tostring(k))
        if not eq then return false, why end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing in seed" end
    end
    return true
end

local eq, why = deepEqual(ns.NewProfileSeed, decoded, "profile")
assert(eq, "Starter Profile preset has drifted from the seed (" .. tostring(why)
    .. "). Re-run: lua tools/gen_starter_preset_from_seed.lua")

print("ok: Starter Profile preset matches ns.NewProfileSeed")
