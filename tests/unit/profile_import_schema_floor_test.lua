local env = dofile("tools/_addon_env.lua")
local h = env.BuildHarness()

local origSchema = h.db.profile._schemaVersion
h.db.profile._schemaVersion = 46
local oldStr = h.QUICore:ExportProfileToString()
assert(type(oldStr) == "string" and #oldStr > 0, "export of doctored profile failed: " .. tostring(oldStr))

local ok, err = h.QUICore:ImportProfileFromString(oldStr, "FloorTarget")
assert(ok == false, "pre-floor full import must be rejected, or migrations will wipe and reseed it on next load")
assert(type(err) == "string" and err:find("too old", 1, true),
    "rejection must name the schema floor, got: " .. tostring(err))

local sok, _, _, _, serr = h.QUICore:SanitizeProfileImportString(oldStr)
assert(sok == false,
    "the sanitize fallback must reject pre-floor payloads too, or it silently bypasses the floor ParseProfileImportString enforces")
assert(type(serr) == "string" and serr:find("too old", 1, true),
    "sanitize rejection must name the schema floor, got: " .. tostring(serr))

h.db.profile._schemaVersion = origSchema
local freshStr = h.QUICore:ExportProfileToString()
local okNow, errNow = h.QUICore:ImportProfileFromString(freshStr, "FloorTargetCurrent")
assert(okNow == true, "current-schema import must still succeed, got: " .. tostring(errNow))

print("ok profile import schema floor")
