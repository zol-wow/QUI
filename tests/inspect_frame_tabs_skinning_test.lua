-- tests/inspect_frame_tabs_skinning_test.lua
-- Run: lua tests/inspect_frame_tabs_skinning_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("modules/skinning/frames/inspect.lua")

assertContains(
    source,
    "local SkinBase = ns.SkinBase",
    "Inspect frame skinning must use the shared SkinBase tab styling helpers")

assertContains(
    source,
    "local function StyleInspectFrameTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)",
    "Inspect frame skinning must style InspectFrame bottom tabs")

assertContains(
    source,
    "local function SkinInspectFrameTabs()",
    "Inspect frame skinning must enumerate InspectFrame tabs")

assertContains(
    source,
    "_G[\"InspectFrameTab\" .. i]",
    "Inspect tab skinning must cover InspectFrameTab1..3")

assertContains(
    source,
    "SkinBase.StripTextures(tab)",
    "Inspect tab skinning must strip Blizzard tab textures")

assertContains(
    source,
    "SkinBase.CreateBackdrop(tab, sr, sg, sb, sa, bgr, bgg, bgb, 0.9)",
    "Inspect tab skinning must create QUI tab backdrops")

assertContains(
    source,
    "hooksecurefunc(\"PanelTemplates_SetTab\"",
    "Inspect tab selected-state visuals must refresh when Blizzard changes selected tab")

assertContains(
    source,
    "frame == InspectFrame",
    "Inspect PanelTemplates_SetTab hook must only refresh InspectFrame tabs")

assertContains(
    source,
    "SkinInspectFrameTabs()",
    "Inspect frame setup must apply bottom tab skinning")

assertContains(
    source,
    "InspectFrame and InspectFrameTab1",
    "Inspect frame skinning must catch up if InspectFrame already exists before ADDON_LOADED is observed")

print("OK: inspect_frame_tabs_skinning_test")
