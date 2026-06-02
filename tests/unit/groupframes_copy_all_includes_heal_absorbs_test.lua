-- tests/unit/groupframes_copy_all_includes_heal_absorbs_test.lua
-- Run: lua tests/unit/groupframes_copy_all_includes_heal_absorbs_test.lua
--
-- Regression: "Copy All Settings" copies only the keys listed in VISUAL_DB_KEYS
-- (for key in pairs(VISUAL_DB_KEYS) ... dst[key] = DeepCopy(src[key])).
-- healAbsorbs is a real visual sub-table (defaults + schema editor + runtime
-- consumer) but was missing from the set, so Copy All silently left the
-- destination's heal-absorb settings untouched despite promising to overwrite
-- ALL visual settings.

local path = "modules/groupframes/settings/group_frames_schema.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local startPos = assert(source:find("local VISUAL_DB_KEYS = {", 1, true),
    "VISUAL_DB_KEYS table should exist")
local closePos = assert(source:find("}", startPos, true),
    "VISUAL_DB_KEYS table should be closed")
local body = source:sub(startPos, closePos)

-- Sibling overlay sub-tables that are already (correctly) copied.
assert(body:find("absorbs%s*=%s*true"), "VISUAL_DB_KEYS should include absorbs")
assert(body:find("healPrediction%s*=%s*true"), "VISUAL_DB_KEYS should include healPrediction")

-- The regression: healAbsorbs must be copied too.
assert(body:find("healAbsorbs%s*=%s*true"),
    "VISUAL_DB_KEYS should include healAbsorbs so Copy All copies heal-absorb settings")

print("OK: groupframes_copy_all_includes_heal_absorbs_test")
