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

-- InspectFrame bottom tabs must route through the SHARED canonical verb, not the
-- former private StyleInspectFrameTab fork (which used live-only SetBackdropColors
-- for the selected highlight and LOST the tint on any scale/theme rebuild).
assertContains(
    source,
    "local function SkinInspectFrameTabs()",
    "Inspect frame skinning must define the bottom-tab skin entry point")

assertContains(
    source,
    "SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs(\"InspectFrame\", 3), InspectFrame",
    "Inspect bottom tabs must route through the canonical SkinBase.SkinTabGroup (covers InspectFrameTab1..3 + persisted selection)")

assert(not source:find("local function StyleInspectFrameTab", 1, true),
    "InspectFrame tabs must not reintroduce the private StyleInspectFrameTab fork; use SkinBase.SkinTabGroup")
assert(not source:find("SkinBase.SetBackdropColors(bd,", 1, true),
    "InspectFrame tabs must not use live-only SetBackdropColors for selection (lost on scale rebuild); RefreshTabSelected persists via ApplyPixelBackdrop")

assertContains(
    source,
    "SkinInspectFrameTabs()",
    "Inspect frame setup must apply bottom tab skinning")

assertContains(
    source,
    "SkinBase.OnAddOnLoaded(\"Blizzard_InspectUI\"",
    "Inspect frame skinning must gate through the shared OnAddOnLoaded helper, which catches up immediately if Blizzard_InspectUI already loaded before ADDON_LOADED is observed")

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
