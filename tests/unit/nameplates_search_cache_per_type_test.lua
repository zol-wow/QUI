local cache = dofile("tests/helpers/search_cache.lua")()
local settings = assert(cache.settings, "cache must have a settings section")

local function fail(msg)
    print("FAIL: nameplates_search_cache_per_type_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

local nameplateRows = {}
for _, entry in ipairs(settings) do
    if entry.featureId == "nameplatesPage" then
        nameplateRows[#nameplateRows + 1] = entry
    end
end

if #nameplateRows == 0 then
    fail("no nameplatesPage rows found in the generated search cache")
end

local EXPECTED_TYPES = {
    petMinion = true, friendly = true, bossElite = true,
    minorTrivial = true, enemyPlayer = true, enemyNPC = true,
}

test("every per-type tab carries rows for all six types", function()
    for _, tabKey in ipairs({ "frame", "text", "indicators", "auras", "castbars", "colors" }) do
        local seenTypes = {}
        for _, entry in ipairs(nameplateRows) do
            if entry.surfaceTabKey == tabKey and EXPECTED_TYPES[entry.surfaceTypeKey] then
                seenTypes[entry.surfaceTypeKey] = true
            end
        end
        local count = 0
        for _ in pairs(seenTypes) do count = count + 1 end
        if count ~= 6 then
            fail(("tab %q: expected rows for all 6 types, saw %d"):format(tabKey, count))
        end
    end
end)

test("General and Behavior rows never carry a surfaceTypeKey", function()
    for _, tabKey in ipairs({ "general", "visibility" }) do
        for _, entry in ipairs(nameplateRows) do
            if entry.surfaceTabKey == tabKey and entry.surfaceTypeKey ~= nil then
                fail(("tab %q row %q unexpectedly carries surfaceTypeKey=%s"):format(
                    tabKey, tostring(entry.label), tostring(entry.surfaceTypeKey)))
            end
        end
    end
end)

test("a per-type row's surfaceTabKey and surfaceTypeKey are always both present or both absent", function()
    for _, entry in ipairs(nameplateRows) do
        local hasTab = entry.surfaceTabKey ~= nil
        local hasType = entry.surfaceTypeKey ~= nil
        if hasType and not hasTab then
            fail(("row %q has surfaceTypeKey but no surfaceTabKey"):format(tostring(entry.label)))
        end
    end
end)

test("action-button rows with no per-type data are never duplicated per type", function()
    local seen = {}
    for _, entry in ipairs(nameplateRows) do
        local descriptor = entry.widgetDescriptor
        local hasNoDbPath = type(descriptor) ~= "table" or descriptor.dbPath == nil
        if entry.widgetType == "action_button" and hasNoDbPath then
            local key = tostring(entry.label) .. "|" .. tostring(entry.tileId)
                .. "|" .. tostring(entry.subPageIndex) .. "|" .. tostring(entry.subTabIndex)
            seen[key] = (seen[key] or 0) + 1
        end
    end
    for key, count in pairs(seen) do
        if count > 1 then
            fail(("action-button row %q appears %d times -- surfaceTypeKey must not legalize per-type duplicates for an action with no per-type data behind it"):format(key, count))
        end
    end
end)

test("action-button rows with no per-type data never carry a surfaceTypeKey", function()
    local checked = 0
    for _, entry in ipairs(nameplateRows) do
        local descriptor = entry.widgetDescriptor
        local hasNoDbPath = type(descriptor) ~= "table" or descriptor.dbPath == nil
        if entry.widgetType == "action_button" and hasNoDbPath then
            checked = checked + 1
            if entry.surfaceTypeKey ~= nil then
                fail(("action-button row %q carries surfaceTypeKey=%s -- clicking it would silently "
                    .. "flip the user's selected type instead of leaving the current selection alone")
                    :format(tostring(entry.label), tostring(entry.surfaceTypeKey)))
            end
        end
    end
    if checked == 0 then
        fail("no descriptor-less action_button rows found under nameplatesPage -- this check would pass vacuously")
    end
end)

test("navigation entries also carry a surfaceTypeKey for all six types", function()
    local navigation = assert(cache.navigation, "cache must have a navigation section")
    local seenTypes = {}
    for _, entry in ipairs(navigation) do
        if EXPECTED_TYPES[entry.surfaceTypeKey] then
            seenTypes[entry.surfaceTypeKey] = true
        end
    end
    local count = 0
    for _ in pairs(seenTypes) do count = count + 1 end
    if count ~= 6 then
        fail(("navigation: expected surfaceTypeKey rows for all 6 types, saw %d"):format(count))
    end
end)

print(("OK: nameplates_search_cache_per_type_test (%d nameplatesPage rows checked)"):format(#nameplateRows))
