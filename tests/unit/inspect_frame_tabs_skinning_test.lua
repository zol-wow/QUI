-- tests/unit/inspect_frame_tabs_skinning_test.lua
-- Run: lua tests/unit/inspect_frame_tabs_skinning_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("QUI_Skinning/skinning/frames/inspect.lua")

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
    "SkinBase.ClampAllTextures(tab)",
    "Inspect tab skinning must clamp all Blizzard tab textures hidden (not a one-shot alpha=0 that Blizzard re-asserts on selection)")

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

-- Close button + paper-doll action buttons must be skinned (were unskinned:
-- stock red close X, plain View/Talents buttons showed through the chrome).
assertContains(
    source,
    "local function SkinInspectButtons()",
    "Inspect frame skinning must skin the close + paper-doll action buttons")

assertContains(
    source,
    "SkinBase.SkinChromeCloseButton(InspectFrame.CloseButton",
    "Inspect close button (ButtonFrameTemplate) must route through SkinChromeCloseButton")

assertContains(
    source,
    "paperDoll.ViewButton",
    "Inspect 'View in Dressing Room' button must be skinned")

assertContains(
    source,
    "itemsFrame.InspectTalents",
    "Inspect Talents button must be skinned")

assertContains(
    source,
    "SkinInspectButtons()",
    "Inspect frame setup must apply close/action button skinning")

-- Scale changes must rebuild the 1px borders (per-frame SetScale does not fire
-- the global scale-refresh event).
assertContains(
    source,
    "local function RefreshInspectFrameScale()",
    "Inspect skinning must expose a scale-refresh that rebuilds pixel borders")

assertContains(
    source,
    "UIKit.QueueScaleRefresh",
    "Inspect scale-refresh must queue a pixel-border rebuild")

print("OK: inspect_frame_tabs_skinning_test")
