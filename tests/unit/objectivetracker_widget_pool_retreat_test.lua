local loadstring = loadstring or load

local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("modules/skinning/gameplay/objectivetracker.lua")

local function extract(name)
    local sentinel = "-- <<< QUI_TEST_EXTRACT " .. name
    local first = assert(src:find(sentinel, 1, true), "start sentinel must exist: " .. name)
    local second = assert(src:find(sentinel, first + #sentinel, true), "end sentinel must exist: " .. name)
    return src:sub(first + #sentinel, second - 1)
end

assert(not src:find("editModeHeight", 1, true),
    "objectivetracker.lua must not write ObjectiveTrackerFrame.editModeHeight")
assert(not src:find("ScenarioTrackerProgressBarMixin", 1, true),
    "objectivetracker.lua must not hook the scenario progress bar mixin")
assert(not src:find("StageBlock", 1, true),
    "objectivetracker.lua must not touch ScenarioObjectiveTracker.StageBlock")
assert(src:find("local function IsWidgetPoolBlock", 1, true),
    "objectivetracker.lua must gate block styling on the widget-pool trackers")
assert(src:find("ScenarioObjectiveTracker = true", 1, true)
    and src:find("UIWidgetObjectiveTracker = true", 1, true),
    "objectivetracker.lua must list both widget-pool trackers")
assert(not src:find('"ZONE_CHANGED_NEW_AREA"', 1, true)
    and not src:find('"ZONE_CHANGED_INDOORS"', 1, true),
    "ObjectiveTracker must use Blizzard's zone-driven dirty update instead of scheduling a duplicate layout pass")

local heightChunk = table.concat({
    "local _G, Helpers = ...",
    extract("tracker_max_height"),
    "return ApplyTrackerMaxHeight, CaptureBlizzardTrackerHeight",
}, "\n")

local fakeHelpers = {
    SafeNumberOrNil = function(value)
        return type(value) == "number" and value or nil
    end,
}

local tracker = { height = 800, updateHeightCalls = 0, topModulePadding = 38 }
function tracker:SetHeight(height)
    self.height = height
end
function tracker:GetHeight()
    return self.height
end
function tracker:UpdateHeight()
    self.updateHeightCalls = self.updateHeightCalls + 1
end

local fakeGlobals = { ObjectiveTrackerFrame = tracker }
local applyHeight, captureBlizzardHeight = assert(loadstring(heightChunk, "tracker_max_height"))(
    fakeGlobals, fakeHelpers)

local containerSrc = readAll(
    "tests/framexml/Interface/AddOns/Blizzard_ObjectiveTracker/" ..
    "Blizzard_ObjectiveTrackerContainer.lua")
local getAvailableHeightSrc = assert(containerSrc:match(
    "function ObjectiveTrackerContainerMixin:GetAvailableHeight%(%)\n.-\nend"),
    "local FrameXML must expose the objective tracker available-height calculation")
local getAvailableHeight = assert(loadstring(table.concat({
    "local ObjectiveTrackerContainerMixin = {}",
    getAvailableHeightSrc,
    "return ObjectiveTrackerContainerMixin.GetAvailableHeight",
}, "\n"), "objective_tracker_available_height"))()

applyHeight({ objectiveTrackerHeight = 420 })
assert(tracker.height == 420,
    "configured max height must constrain ObjectiveTrackerFrame, which owns module truncation")
assert(getAvailableHeight(tracker) == 382,
    "Blizzard modules must receive the constrained height as their available layout space")
assert(tracker.updateHeightCalls == 0,
    "QUI must not ask Blizzard to restore its Edit Mode height after applying the constraint")
assert(tracker.editModeHeight == nil,
    "height enforcement must not mutate Blizzard's Edit Mode height state")

applyHeight(nil)
assert(tracker.height == 600, "missing settings must retain the 600px default")

tracker.height = 300
captureBlizzardHeight(tracker)
applyHeight({ objectiveTrackerHeight = 600 })
assert(tracker.height == 300,
    "a smaller Blizzard layout height must remain smaller than the configured maximum")

tracker.height = 800
captureBlizzardHeight(tracker)
applyHeight({ objectiveTrackerHeight = 600 })
assert(tracker.height == 600,
    "the tracker must expand to its configured cap when Blizzard later reports more room")

local shortTracker = { height = 300 }
function shortTracker:SetHeight(height)
    self.height = height
end
function shortTracker:GetHeight()
    return self.height
end
local applyShortHeight = assert(loadstring(heightChunk, "tracker_short_height"))(
    { ObjectiveTrackerFrame = shortTracker }, fakeHelpers)
applyShortHeight({ objectiveTrackerHeight = 600 })
assert(shortTracker.height == 300,
    "configured max height must not enlarge a tracker beyond Blizzard's available height")

fakeGlobals.ObjectiveTrackerFrame = nil
assert(pcall(applyHeight, { objectiveTrackerHeight = 300 }),
    "height enforcement must tolerate the tracker not being loaded yet")

local postLayout = assert(src:match(
    "local function RunObjectiveTrackerPostLayoutUpdate%(%)" ..
    ".-local function DeferObjectiveTrackerPostLayoutUpdate%(%)"),
    "post-layout objective tracker block must exist")
assert(postLayout:find("EnforceSize()", 1, true),
    "post-layout updates must reassert both configured dimensions after Blizzard relayout")
assert(src:find('hooksecurefunc(TrackerFrame, "UpdateHeight"', 1, true),
    "height enforcement must capture Blizzard's available height from its owner lifecycle")

print("OK: objectivetracker_widget_pool_retreat_test")
