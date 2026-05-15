-- tests/character_frame_bottom_tabs_skinning_test.lua
-- Run: lua tests/character_frame_bottom_tabs_skinning_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("modules/skinning/frames/character.lua")

assertContains(
    source,
    "local function StyleCharacterFrameTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)",
    "Character frame skinning must style the bottom Character/Reputation/Currency tabs")

assertContains(
    source,
    "local function SkinCharacterFrameTabs()",
    "Character frame skinning must enumerate the bottom CharacterFrame tabs")

assertContains(
    source,
    "_G[\"CharacterFrameTab\" .. i]",
    "Bottom tab skinning must cover CharacterFrameTab1..3")

assertContains(
    source,
    "SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)",
    "Bottom tab styling must create QUI tab backdrops")

assertContains(
    source,
    "SkinBase.StripTextures(tab)",
    "Bottom tab styling must strip all Blizzard tab texture regions, not only named fields")

assertContains(
    source,
    "hooksecurefunc(\"PanelTemplates_SetTab\"",
    "Bottom tab selected-state visuals must refresh when Blizzard changes selected tab")

assertContains(
    source,
    "addon == \"Blizzard_UIPanels_Game\"",
    "Character frame skinning must initialize when the current CharacterFrame addon loads")

assertContains(
    source,
    "CharacterFrame and CharacterFrameTab1",
    "Character frame skinning must catch up if CharacterFrame already exists before ADDON_LOADED is observed")

assertContains(
    source,
    "SkinCharacterFrameTabs()",
    "Character frame setup must apply bottom tab skinning")

print("OK: character_frame_bottom_tabs_skinning_test")
