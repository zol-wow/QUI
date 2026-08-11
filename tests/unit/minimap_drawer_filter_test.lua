-- tests/unit/minimap_drawer_filter_test.lua
-- Run: lua tests/unit/minimap_drawer_filter_test.lua

local function noop() end

local env = (dofile("tests/helpers/load_minimap_runtime.lua"))()
local newFrame = env.newFrame
local createdFrames = env.createdFrames
local findUpvalue = env.findUpvalue

local refresh = assert(_G.QUI_RefreshMinimapButtonDrawer, "drawer refresh function should be exported")
local isDrawerCandidate = assert(findUpvalue(refresh, "IsMinimapButton"),
    "drawer candidate classifier should be reachable")

local launcher = newFrame("SampleMinimapButton", "Button", UIParent)
assert(isDrawerCandidate(launcher) == true,
    "named minimap launcher buttons should remain drawer candidates")

local ldbLauncher = newFrame("LibDBIcon10_Sample", "Button", UIParent)
assert(isDrawerCandidate(ldbLauncher) == true,
    "LibDBIcon launcher buttons should remain drawer candidates")

local numericIconPin = newFrame("WaypointMinimapIcon1", "Button", Minimap)
numericIconPin:SetScript("OnClick", noop)
assert(isDrawerCandidate(numericIconPin) == false,
    "numeric minimap icon frames should stay on the minimap instead of entering the drawer")

local numericButtonPin = newFrame("WaypointMinimapButton42", "Button", Minimap)
numericButtonPin:SetScript("OnMouseUp", noop)
assert(isDrawerCandidate(numericButtonPin) == false,
    "numeric minimap button frames should stay on the minimap instead of entering the drawer")

local queueStatusLoadedFrame
for i = 1, #createdFrames do
    local frame = createdFrames[i]
    if frame.events and frame.events.ADDON_LOADED and frame.scripts.OnEvent then
        queueStatusLoadedFrame = frame
        break
    end
end

assert(queueStatusLoadedFrame, "minimap event frame should listen for ADDON_LOADED")
queueStatusLoadedFrame.scripts.OnEvent(queueStatusLoadedFrame, "ADDON_LOADED", "Blizzard_QueueStatusFrame")
assert(QueueStatusButton.lastMicroMenuPosition == MicroMenuPositionEnum.BottomRight,
    "restoring the dungeon eye should call Blizzard with the current micro-menu position")
assert(QueueStatusButton.lastIsMenuHorizontal == true,
    "restoring the dungeon eye should pass the micro-menu orientation")

print("OK: minimap_drawer_filter_test")
