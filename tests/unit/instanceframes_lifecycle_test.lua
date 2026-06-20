-- tests/unit/instanceframes_lifecycle_test.lua
-- Run: lua tests/unit/instanceframes_lifecycle_test.lua

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

local instanceframes = readFile("QUI_Skinning/skinning/frames/instanceframes.lua")
local pveFrame = readFile("tests/framexml/Interface/AddOns/Blizzard_GroupFinder/Mainline/PVEFrame.lua")
local pvpui = readFile("tests/framexml/Interface/AddOns/Blizzard_PVPUI/Mainline/Blizzard_PVPUI.lua")
local challenges = readFile("tests/framexml/Interface/AddOns/Blizzard_ChallengesUI/Mainline/Blizzard_ChallengesUI.lua")

assertContains(pveFrame, "UIParentLoadAddOn(panels[tabIndex].addon);",
    "FrameXML must load PVP/Challenges addons inside PVEFrame_ShowFrame before the selected panel is shown")
assertContains(pveFrame, "panel:Show();",
    "FrameXML must show the selected child panel synchronously after addon loading")
assertContains(pveFrame, "function PVEFrameMixin:OnShow()",
    "FrameXML must expose a stable PVEFrame OnShow lifecycle")
assertContains(pvpui, "function PVPUIFrame_OnShow(self)",
    "FrameXML must expose a stable PVPUIFrame OnShow lifecycle")
assertContains(challenges, "function ChallengesFrameMixin:OnShow()",
    "FrameXML must expose a stable ChallengesFrame OnShow lifecycle")

assertAbsent(instanceframes, "single qScrollHooked flag makes a second hook a no-op",
    "Instance-frame comments must not claim HookScrollBoxRowFonts cannot compose; SkinBase now composes acquired callbacks")
assertContains(instanceframes, "HookScrollBoxAcquired composes callbacks",
    "Specific battleground row comment must document the current SkinBase composition behavior")

assertAbsent(instanceframes, "C_Timer.After(0.1, SkinInstanceFrames)",
    "Instance-frame load/show lifecycle must not use fixed 0.1s catch-up timers")
assertAbsent(instanceframes, "frame:RegisterEvent(\"ADDON_LOADED\")",
    "Instance-frame lifecycle must use SkinBase.OnAddOnLoaded instead of a local ADDON_LOADED watcher")
assertContains(instanceframes, "SkinBase.OnAddOnLoaded(\"Blizzard_PVPUI\", SkinInstanceFrames, 0)",
    "PVP LOD catch-up must use SkinBase.OnAddOnLoaded's fully-loaded lifecycle")
assertContains(instanceframes, "SkinBase.OnAddOnLoaded(\"Blizzard_ChallengesUI\", SkinInstanceFrames, 0)",
    "Challenges LOD catch-up must use SkinBase.OnAddOnLoaded's fully-loaded lifecycle")
assertContains(instanceframes, "PVEFrame:HookScript(\"OnShow\", SkinInstanceFrames)",
    "PVEFrame OnShow should skin through the direct FrameXML lifecycle")

print("OK: instanceframes_lifecycle_test")
