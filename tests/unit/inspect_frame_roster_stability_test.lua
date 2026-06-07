-- tests/unit/inspect_frame_roster_stability_test.lua
-- Run: lua tests/unit/inspect_frame_roster_stability_test.lua

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

local source = readFile("QUI_Skinning/skinning/character_pane/inspect.lua")

assertContains(
    source,
    "local inspectSessionGUID = nil",
    "Inspect pane must track the inspected player GUID independently of volatile raid unit tokens")

assertContains(
    source,
    "local function ResolveInspectUnitByGUID(guid)",
    "Inspect pane must be able to find the inspected player after raid/party unit tokens shift")

assertContains(
    source,
    "InspectFrame:UnregisterEvent(\"GROUP_ROSTER_UPDATE\")",
    "Inspect pane must prevent Blizzard's roster handler from hiding non-target inspect frames")

assertContains(
    source,
    "eventFrame:RegisterEvent(\"GROUP_ROSTER_UPDATE\")",
    "Inspect pane must handle roster updates itself after unregistering Blizzard's close path")

assertContains(
    source,
    "RefreshInspectUnitAfterRosterUpdate()",
    "Roster updates must refresh the inspected unit token instead of closing InspectFrame")

assertContains(
    source,
    "_G.INSPECTED_UNIT = resolvedUnit",
    "Roster refresh must keep Blizzard's inspected unit global in sync with the rebound unit token")

local rosterBranchStart = assert(
    source:find("elseif event == \"GROUP_ROSTER_UPDATE\" then", 1, true),
    "GROUP_ROSTER_UPDATE event branch should exist")
local rosterBranchEnd = assert(
    source:find("elseif event == \"INSPECT_READY\" then", rosterBranchStart, true),
    "INSPECT_READY branch should follow roster branch")
local rosterBranch = source:sub(rosterBranchStart, rosterBranchEnd)

assertAbsent(
    rosterBranch,
    "HideUIPanel",
    "QUI's roster handler must not close InspectFrame during raid roster churn")

assertAbsent(
    rosterBranch,
    "ClearInspectPlayer",
    "QUI's roster handler must not clear inspect data during raid roster churn")

print("OK: inspect_frame_roster_stability_test")
