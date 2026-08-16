local cache = dofile("tests/helpers/search_cache.lua")()
local settings = assert(cache.settings, "cache must have a settings section")

local function fail(msg)
    print("FAIL: search_cache_raid_markers_bar_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

local byFeature = {}
for _, entry in ipairs(settings) do
    local id = entry.featureId
    if id then
        byFeature[id] = byFeature[id] or {}
        byFeature[id][#byFeature[id] + 1] = entry
    end
end

local ROUTES = {
    actionBarsTotemBar = { subPageIndex = 3, subTabName = "Totem Bar" },
    actionBarsRaidMarkersBar = { subPageIndex = 4, subTabName = "Raid Markers" },
    actionBarsBagBar = { subPageIndex = 5, subTabName = "Bag Bar" },
    actionBarsExtraZone = { subPageIndex = 6, subTabName = "Extra & Zone" },
}

test("every special-bar feature has rows on its own sub-page", function()
    for featureId, route in pairs(ROUTES) do
        local rows = byFeature[featureId]
        if not rows or #rows == 0 then
            fail(("feature %s has zero rows"):format(featureId))
        end
        for _, entry in ipairs(rows) do
            if entry.tileId ~= "action_bars" then
                fail(("%s row %q: tileId %s"):format(featureId, tostring(entry.label), tostring(entry.tileId)))
            end
            if entry.subPageIndex ~= route.subPageIndex then
                fail(("%s row %q: subPageIndex %s, expected %d"):format(
                    featureId, tostring(entry.label), tostring(entry.subPageIndex), route.subPageIndex))
            end
            if entry.subTabName ~= route.subTabName then
                fail(("%s row %q: subTabName %s, expected %s"):format(
                    featureId, tostring(entry.label), tostring(entry.subTabName), route.subTabName))
            end
        end
    end
end)

local EXPECTED_RAID_MARKERS = {
    ["Enabled"] = { dbPath = "profile.raidMarkersBar", dbKey = "enabled" },
    ["Only In Dungeons & Raids"] = { dbPath = "profile.raidMarkersBar", dbKey = "onlyInInstances" },
    ["Grow Direction"] = { dbPath = "profile.raidMarkersBar", dbKey = "growDirection" },
    ["World Markers"] = { dbPath = "profile.raidMarkersBar.worldMarkers", dbKey = "enabled" },
    ["Leader Actions"] = { dbPath = "profile.raidMarkersBar.leaderStrip", dbKey = "enabled" },
    ["Show Only As Leader"] = { dbPath = "profile.raidMarkersBar", dbKey = "autoShowForLeader" },
    ["Pull Countdown Seconds"] = { dbPath = "profile.raidMarkersBar.leaderStrip", dbKey = "pullSeconds" },
}

test("raid markers bar settings keep their db paths", function()
    local byLabel = {}
    for _, entry in ipairs(byFeature.actionBarsRaidMarkersBar or {}) do
        byLabel[entry.label] = entry
    end
    for label, expected in pairs(EXPECTED_RAID_MARKERS) do
        local entry = byLabel[label]
        if not entry then
            fail(("no actionBarsRaidMarkersBar row for label %q"):format(label))
        end
        local descriptor = entry.widgetDescriptor
        if type(descriptor) ~= "table" then
            fail(("row %q: missing widgetDescriptor"):format(label))
        end
        if descriptor.dbPath ~= expected.dbPath then
            fail(("row %q: dbPath %s, expected %s"):format(label, tostring(descriptor.dbPath), expected.dbPath))
        end
        if descriptor.dbKey ~= expected.dbKey then
            fail(("row %q: dbKey %s, expected %s"):format(label, tostring(descriptor.dbKey), expected.dbKey))
        end
    end
end)

test("both special buttons have rows on the Extra & Zone page", function()
    local enabledCount = 0
    for _, entry in ipairs(byFeature.actionBarsExtraZone or {}) do
        if entry.label == "Enabled" then
            enabledCount = enabledCount + 1
        end
    end
    if enabledCount ~= 2 then
        fail(("expected one Enabled row per button, saw %d"):format(enabledCount))
    end
end)

test("per-bar rows route to Per-Bar and exclude the moved bars", function()
    local moved = {
        totemBar = true, raidMarkersBar = true, bagBar = true,
        extraActionButton = true, zoneAbility = true,
    }
    for _, entry in ipairs(byFeature.actionBarsPerBar or {}) do
        if entry.subTabName ~= "Per-Bar" then
            fail(("row %q (providerKey=%s): subTabName %q, expected Per-Bar"):format(
                tostring(entry.label), tostring(entry.providerKey), tostring(entry.subTabName)))
        end
        if moved[entry.providerKey] then
            fail(("moved bar %s still has an actionBarsPerBar row (%s)"):format(
                tostring(entry.providerKey), tostring(entry.label)))
        end
    end
end)
