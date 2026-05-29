-- tests/unit/options_tile_warmup_static_test.lua
-- Run: lua tests/unit/options_tile_warmup_static_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_Options/framework.lua")

local function assertNotContains(needle, message)
    assert(not source:find(needle, 1, true), message)
end

assert(
    source:find("local function BuildSubPageBody", 1, true),
    "sub-page bodies should still be cached after deliberate navigation")
assert(
    source:find("tile._subPageBodies[i]", 1, true),
    "sub-page body cache should key bodies by selected tab index")

assertNotContains("EnsureTileBodyBuilt", "deferred body-build helper should be removed with prewarm")
assertNotContains("deferBodyBuild", "shell-only deferred body construction should be removed")
assertNotContains("deferInitialSelect", "deferred initial sub-page selection should be removed")
assertNotContains("_pendingInitialSubPageIndex", "deferred initial sub-page state should be removed")
assertNotContains("_buildDirectBody", "direct body deferred build closure should be removed")
assertNotContains("_directBodyBuilt", "direct body deferred build flag should be removed")
assertNotContains("ScheduleFeatureTileWarmup", "panel-open tile warmup should be removed")
assertNotContains("QueueFeatureTileWarmup", "sidebar hover tile warmup should be removed")
assertNotContains("CancelFeatureTileWarmup", "sidebar hover tile warmup cancellation should be removed")
assertNotContains("TileNeedsWarmup", "tile warmup eligibility helper should be removed")
assertNotContains("BuildTilePageForWarmup", "tile warmup builder should be removed")
assertNotContains("MarkSettingsInteraction", "warmup/profiling interaction serials should be removed")
assertNotContains("WarmupTile", "tile warmup profiler label should be removed")
assertNotContains("panel-warmup", "panel-open warmup source should be removed")
assertNotContains("hover-warmup", "hover warmup source should be removed")
assertNotContains("QueueSubPageWarmup", "sub-page hover warmup should be removed")
assertNotContains("CancelSubPageWarmup", "sub-page hover warmup cancellation should be removed")
assertNotContains("SubPageWarmup", "sub-page warmup profiler label should be removed")
assertNotContains("subpage-hover", "sub-page hover warmup source should be removed")
assertNotContains("subpage-background", "background sub-page warmup source should be removed")
assertNotContains("_scheduleSubPageWarmup", "background sub-page warmup scheduler should be removed")
assertNotContains("_cancelSubPageBackgroundWarmup", "background sub-page warmup cancellation should be removed")

print("OK: options_tile_warmup_static_test")
