-- tests/unit/starter_preset_matches_seed_test.lua
-- Run: lua tests/unit/starter_preset_matches_seed_test.lua
--
-- The Starter Profile string (importstrings/starter_profile.lua) is the
-- SINGLE source for both the fresh-install seed (decoded lazily by
-- core/new_profile_defaults.lua) and the Profiles-tab preset. This guards
-- the decode plumbing: ns.GetNewProfileSeed() must deep-equal a direct
-- decode of preset.data (minus the _quiBundledGlobals block the seed path
-- drops), the preset must present as "Starter Profile", and the seed must
-- never leak _quiBundledGlobals into profiles.
--
-- Compares DECODED TABLES, not the encoded blob: AceSerializer iterates
-- pairs() so the blob bytes are non-deterministic, but the decoded settings
-- are stable.

local env = dofile("tools/_addon_env.lua")
local ns  = env.LoadCore()
local LibDeflate    = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

-- The harness registers the loader (importstrings/starter_profile.lua).
local loader = _G.QUI._importLoaders.StarterProfile
assert(type(loader) == "function", "StarterProfile loader missing")
local preset = loader()
assert(type(preset) == "table" and type(preset.data) == "string", "preset.data missing")

-- User-facing rename: the preset must present as "Starter Profile".
assert(preset.name == "Starter Profile",
    "preset name must be 'Starter Profile', got: " .. tostring(preset.name))

-- Direct decode QUI1: -> table.
local raw = preset.data:gsub("^QUI1:", "")
local decompressed = LibDeflate:DecompressDeflate(LibDeflate:DecodeForPrint(raw))
assert(decompressed, "failed to decompress preset blob")
local ok, decoded = AceSerializer:Deserialize(decompressed)
assert(ok and type(decoded) == "table", "failed to deserialize preset blob")
decoded._quiBundledGlobals = nil

local seed = assert(ns.GetNewProfileSeed and ns.GetNewProfileSeed(),
    "ns.GetNewProfileSeed() returned nothing")
assert(seed._quiBundledGlobals == nil,
    "seed must not leak _quiBundledGlobals into profiles")

local function deepEqual(a, b, path)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false, path .. ": " .. tostring(a) .. " ~= " .. tostring(b)
    end
    for k, v in pairs(a) do
        local eq, why = deepEqual(v, b[k], path .. "." .. tostring(k))
        if not eq then return false, why end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false, path .. "." .. tostring(k) .. ": missing on seed side"
        end
    end
    return true
end

local eq, why = deepEqual(seed, decoded, "profile")
assert(eq, "seed accessor drifted from direct string decode:\n" .. tostring(why))

print("ok: GetNewProfileSeed matches Starter Profile string decode")
