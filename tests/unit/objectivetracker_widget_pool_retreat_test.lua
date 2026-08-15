local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("modules/skinning/gameplay/objectivetracker.lua")

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

print("OK: objectivetracker_widget_pool_retreat_test")
