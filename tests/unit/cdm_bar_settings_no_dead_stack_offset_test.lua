-- tests/unit/cdm_bar_settings_no_dead_stack_offset_test.lua
-- Run: lua tests/unit/cdm_bar_settings_no_dead_stack_offset_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local source = readAll("modules/cdm/settings/containers_page.lua")
local searchCache = readAll("QUI_Options/search_cache.lua")

local barSpacingStart = assert(source:find('"Bar Spacing"', 1, true),
    "bar layout section must expose the renderer-backed Bar Spacing control")
local dimensionsEnd = assert(source:find("builder.CloseCard(dimensionsCard)", barSpacingStart, true),
    "bar dimensions card must close after Bar Spacing")
local dimensionsBody = source:sub(barSpacingStart, dimensionsEnd)

assert(not dimensionsBody:find("stackOffsetX", 1, true),
    "bar layout section must not expose stackOffsetX; CDMBars uses spacing")
assert(not dimensionsBody:find("stackOffsetY", 1, true),
    "bar layout section must not expose stackOffsetY; CDMBars uses spacing")
assert(not dimensionsBody:find("Stack X Offset", 1, true),
    "bar layout section must not show a dead Stack X Offset control")
assert(not dimensionsBody:find("Stack Y Offset", 1, true),
    "bar layout section must not show a dead Stack Y Offset control")

local function assertNoTrackedBarOffsetCacheEntry(dbKey)
    local pos = 1
    while true do
        local startPos = searchCache:find('["dbKey"] = "' .. dbKey .. '"', pos, true)
        if not startPos then break end
        local blockStart = math.max(1, startPos - 700)
        local blockEnd = math.min(#searchCache, startPos + 700)
        local block = searchCache:sub(blockStart, blockEnd)
        assert(not block:find('["providerKey"] = "trackedBar"', 1, true),
            "search cache must not expose trackedBar " .. dbKey)
        assert(not block:find('["dbPath"] = "profile.ncdm.trackedBar"', 1, true),
            "search cache must not expose trackedBar " .. dbKey)
        pos = startPos + 1
    end
end

assertNoTrackedBarOffsetCacheEntry("stackOffsetX")
assertNoTrackedBarOffsetCacheEntry("stackOffsetY")

print("OK: cdm_bar_settings_no_dead_stack_offset_test")
