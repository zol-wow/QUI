-- tests/character_pane_popout_restore_test.lua
-- Run: lua tests/character_pane_popout_restore_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("modules/skinning/character_pane/character.lua")

assertContains(
    source,
    "local function RestoreCharacterPanePopouts()",
    "Character pane popout cleanup must be centralized")

assertContains(
    source,
    "RestoreCharacterPanePopouts()",
    "Character pane tab transitions must restore floating popouts")

local paperDollOnShowStart = assert(
    source:find('PaperDollFrame:HookScript("OnShow"', 1, true),
    "PaperDollFrame OnShow block should be present")

local characterTabHookStart = assert(
    source:find("CharacterFrameTab1:HookScript", paperDollOnShowStart, true),
    "CharacterFrameTab1 click hook should be present")

local paperDollOnShowBlock = source:sub(paperDollOnShowStart, characterTabHookStart)

assertContains(
    paperDollOnShowBlock,
    "RestoreCharacterPanePopouts()",
    "Returning to the Character panel must close equipment/title popouts")

local characterTabHookEnd = assert(
    source:find("GetState(CharacterFrameTab1).popoutRestoreHooked = true", characterTabHookStart, true),
    "CharacterFrameTab1 click hook should stamp weak-key state")

local characterTabBlock = source:sub(characterTabHookStart, characterTabHookEnd)

assertContains(
    characterTabBlock,
    "RestoreCharacterPanePopouts()",
    "Clicking the main Character tab must close equipment/title popouts")

print("OK: character_pane_popout_restore_test")
