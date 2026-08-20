local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local source = read("modules/ui/uihider.lua")
local objectiveStart = assert(source:find("if ObjectiveTrackerFrame then", 1, true))
local objectiveEnd = assert(source:find("\n    if MinimapCluster", objectiveStart, true))
local objective = source:sub(objectiveStart, objectiveEnd)

assert(objective:find("otState.objectiveTrackerHidden", 1, true),
    "Objective Tracker visibility must track whether UIHider hid it")
assert(objective:find("and otState.objectiveTrackerHidden then", 1, true),
    "Objective Tracker restore must not run for unrelated roster refreshes")

print("PASS uihider_roster_objective_tracker_test")
