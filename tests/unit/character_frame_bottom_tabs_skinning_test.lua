-- tests/unit/character_frame_bottom_tabs_skinning_test.lua
-- Run: lua tests/unit/character_frame_bottom_tabs_skinning_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("QUI_Skinning/skinning/frames/character.lua")

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
    "SkinBase.ClampAllTextures(tab)",
    "Bottom tab styling must clamp all Blizzard tab texture regions hidden (not a one-shot alpha=0 that Blizzard re-asserts on selection)")

assertContains(
    source,
    "hooksecurefunc(\"PanelTemplates_SetTab\"",
    "Bottom tab selected-state visuals must refresh when Blizzard changes selected tab")

assertContains(
    source,
    "SkinBase.OnAddOnLoaded(\"Blizzard_UIPanels_Game\", InitializeCharacterFrameSkinning, 0)",
    "Character frame skinning must initialize when the current CharacterFrame addon loads")

assertContains(
    source,
    "SkinBase.OnAddOnLoaded(\"Blizzard_CharacterFrame\", InitializeCharacterFrameSkinning, 0)",
    "Character frame skinning must catch up if CharacterFrame is already loaded before ADDON_LOADED is observed")

assertContains(
    source,
    "SkinCharacterFrameTabs()",
    "Character frame setup must apply bottom tab skinning")

print("OK: character_frame_bottom_tabs_skinning_test")
