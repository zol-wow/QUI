-- tests/unit/character_pane_combat_resize_immediate_test.lua
-- Run: lua tests/unit/character_pane_combat_resize_immediate_test.lua

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

local source = readFile("QUI_Skinning/skinning/character_pane/character.lua")

assertAbsent(
    source,
    "pendingCharScale",
    "Character panel scale must apply immediately instead of waiting for combat end")

assertAbsent(
    source,
    "pendingTabMode",
    "Character bottom tab anchors must apply immediately instead of waiting for combat end")

assertAbsent(
    source,
    "pendingCharacterLayout",
    "Character pane layout must apply immediately instead of waiting for combat end")

assertAbsent(
    source,
    "local function SafeSetCharScale",
    "Character pane scale helper must not be named as a combat-deferred safe wrapper")

assertContains(
    source,
    "local function SetCharacterFrameScale(scale)",
    "Character pane must keep scale application centralized")

assertContains(
    source,
    "CharacterFrame:SetScale(scale)",
    "Character pane scale application must call SetScale directly")

print("OK: character_pane_combat_resize_immediate_test")
