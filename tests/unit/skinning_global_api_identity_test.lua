-- tests/unit/skinning_global_api_identity_test.lua
-- Run: lua tests/unit/skinning_global_api_identity_test.lua
--
-- Character/inspect pane modules can cache these public API tables before the
-- frame skinners finish loading. Preserve table identity when exporting so
-- cached references see refreshed functions.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local character = readFile("QUI_Skinning/skinning/frames/character.lua")
assertContains(character, "local api = _G.QUI_CharacterFrameSkinning or {}",
    "character frame skinning export must preserve an existing API table")
assertContains(character, "_G.QUI_CharacterFrameSkinning = api",
    "character frame skinning export must publish the preserved API table")
assertAbsent(character, "_G.QUI_CharacterFrameSkinning = {",
    "character frame skinning export must not replace cached API table references")

local inspect = readFile("QUI_Skinning/skinning/frames/inspect.lua")
assertContains(inspect, "local api = _G.QUI_InspectFrameSkinning or {}",
    "inspect frame skinning export must preserve an existing API table")
assertContains(inspect, "_G.QUI_InspectFrameSkinning = api",
    "inspect frame skinning export must publish the preserved API table")
assertAbsent(inspect, "_G.QUI_InspectFrameSkinning = {",
    "inspect frame skinning export must not replace cached API table references")

print("OK: skinning_global_api_identity_test")
