-- tests/unit/nameplate_profile_export_roundtrip_test.lua
-- NP1 strings carry ONE named nameplate profile (account-wide store), not a
-- whole QUI profile. Round-trip must preserve settings, strip control keys
-- (enabled/legacy preset keys), sanitize type mismatches against the shipped
-- nameplates defaults, and cross-paste between the NP1 and QUI1 importers
-- must fail with a pointed error, not import garbage.

local env = dofile("tools/_addon_env.lua")
local h = env.BuildHarness()
local core = h.QUICore

h.db.global.nameplateProfiles = {
    ["My Plates"] = {
        friendly = { enabled = false, showInWorld = false },
        simplified = { scale = 1.25 },
    },
}

local str, err = core:ExportNameplateProfileToString("My Plates")
assert(type(str) == "string", "export failed: " .. tostring(err))
assert(str:sub(1, 4) == "NP1:", "nameplate profile strings must carry the NP1 prefix, got: " .. str:sub(1, 8))

local missing, missingErr = core:ExportNameplateProfileToString("Nope")
assert(missing == nil and type(missingErr) == "string", "exporting an unknown profile must fail")

-- Round-trip into a new name.
local ok, importedName = core:ImportNameplateProfileFromString(str, "Copied Plates")
assert(ok == true, "import failed: " .. tostring(importedName))
assert(importedName == "Copied Plates", "explicit target name must win, got: " .. tostring(importedName))
local copied = h.db.global.nameplateProfiles["Copied Plates"]
assert(copied and copied.simplified and copied.simplified.scale == 1.25, "settings must round-trip")
assert(copied.friendly.showInWorld == false, "nested values must round-trip")

-- Payload name is the default target when none is given.
h.db.global.nameplateProfiles["My Plates"] = nil
local ok2, name2 = core:ImportNameplateProfileFromString(str)
assert(ok2 == true and name2 == "My Plates", "payload name must be the default target, got: " .. tostring(name2))

-- Control keys must never enter the store via import, and type mismatches
-- against the shipped nameplates defaults are stripped, not imported.
h.db.global.nameplateProfiles["Doctored"] = {
    enabled = true,
    specPresets = { [2] = {} },
    specAutoSwitch = true,
    friendly = { enabled = "yes" }, -- boolean in defaults: must be stripped
    simplified = { scale = 2.0 },
}
local dstr = assert(core:ExportNameplateProfileToString("Doctored"))
local ok3, name3, stripped = core:ImportNameplateProfileFromString(dstr, "Cleaned")
assert(ok3 == true, "doctored import should sanitize, not fail: " .. tostring(name3))
local cleaned = h.db.global.nameplateProfiles["Cleaned"]
assert(cleaned.enabled == nil and cleaned.specPresets == nil and cleaned.specAutoSwitch == nil,
    "control keys must be stripped on import")
assert(cleaned.friendly == nil or cleaned.friendly.enabled ~= "yes",
    "type-mismatched values must be sanitized away")
assert(cleaned.simplified.scale == 2.0, "valid values must survive sanitizing")
assert(type(stripped) == "table" and #stripped > 0, "sanitizer must report what it stripped")

-- Cross-paste: an NP1 string in the full-profile importer must be rejected
-- with a pointer to the nameplate importer...
local fok, ferr = core:ImportProfileFromString(str, "WrongTarget")
assert(fok == false, "full-profile importer must reject NP1 strings")
assert(type(ferr) == "string" and ferr:lower():find("nameplate", 1, true),
    "rejection must point at the nameplate importer, got: " .. tostring(ferr))

-- ...and a full QUI1 profile string in the nameplate importer fails too.
local fullStr = core:ExportProfileToString()
assert(type(fullStr) == "string" and fullStr:sub(1, 5) == "QUI1:", "full export sanity")
local nok, nerr = core:AnalyzeNameplateProfileImportString(fullStr)
assert(nok == false, "nameplate importer must reject full profile strings")
assert(type(nerr) == "string" and nerr:lower():find("full", 1, true),
    "rejection must say it is a full profile string, got: " .. tostring(nerr))

-- The UI's "__none" dropdown sentinel is not a legal profile name; imports
-- targeting it fall back to the default name instead of creating an
-- unselectable profile.
local rok, rname = core:ImportNameplateProfileFromString(str, "__none")
assert(rok == true, "reserved-name import should fall back, not fail: " .. tostring(rname))
assert(rname == "Imported nameplate profile", "reserved target name must fall back, got: " .. tostring(rname))
assert(h.db.global.nameplateProfiles["__none"] == nil, "no profile may be created under the reserved name")

-- Garbage in, error out.
local gok, gerr = core:AnalyzeNameplateProfileImportString("NP1:notbase64!!!")
assert(gok == false and type(gerr) == "string", "corrupt strings must fail cleanly")

print("ok nameplate profile export roundtrip")
