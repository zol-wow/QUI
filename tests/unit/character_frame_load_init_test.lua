-- tests/unit/character_frame_load_init_test.lua
-- Run: lua tests/unit/character_frame_load_init_test.lua

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

local source = readFile("QUI_Skinning/skinning/frames/character.lua")

assertAbsent(source, "C_Timer.After(0.1",
    "Character frame initialization must not use a fixed 0.1s catch-up timer")

assertContains(source,
    "SkinBase.OnAddOnLoaded(\"Blizzard_CharacterFrame\", InitializeCharacterFrameSkinning, 0)",
    "Character frame skinning must run through the shared fully-loaded lifecycle for Blizzard_CharacterFrame")

assertContains(source,
    "SkinBase.OnAddOnLoaded(\"Blizzard_UIPanels_Game\", InitializeCharacterFrameSkinning, 0)",
    "Character frame skinning must run through the shared fully-loaded lifecycle for Blizzard_UIPanels_Game")

assertContains(source, "SetupCharacterFrameSkinning()",
    "InitializeCharacterFrameSkinning must still run CharacterFrame setup")

assertContains(source, "SetupTitlePaneHook()",
    "InitializeCharacterFrameSkinning must still install the title pane hook")

assertAbsent(source, "frame:RegisterEvent(\"ADDON_LOADED\")",
    "Character frame initialization must not keep a local ADDON_LOADED watcher once SkinBase.OnAddOnLoaded owns the lifecycle")

print("OK: character_frame_load_init_test")
