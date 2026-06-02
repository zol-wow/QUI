-- tests/unit/groupframes_refresh_settings_repopulates_overlays_test.lua
-- Run: lua tests/unit/groupframes_refresh_settings_repopulates_overlays_test.lua
--
-- Regression: RefreshSettings clears _quiDecorated and re-decorates every frame
-- via UpdateFrameScaling(true). DecorateGroupFrame unconditionally resets the
-- absorb / heal-absorb / heal-prediction overlays to SetValue(0) + Hide and does
-- NOT repopulate them. Because UNIT_HEALTH takes a health-only fast path, a
-- static overlay (e.g. a non-changing heal absorb) stayed hidden after any
-- settings change until its next dedicated event. RefreshSettings must
-- repopulate overlays (via RefreshAllFrames) after re-decorating.

local path = "modules/groupframes/groupframes.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local startPos = assert(source:find("function QUI_GF:RefreshSettings%(%)"),
    "RefreshSettings should exist")
local endPos = assert(source:find("ApplyHUDLayering", startPos, true),
    "RefreshSettings should be followed by ApplyHUDLayering")
local body = source:sub(startPos, endPos)

local scalingPos = assert(body:find("UpdateFrameScaling", 1, true),
    "RefreshSettings should re-decorate via UpdateFrameScaling")
local refreshAllPos = assert(body:find("RefreshAllFrames", 1, true),
    "RefreshSettings should repopulate overlays via RefreshAllFrames")

assert(scalingPos < refreshAllPos,
    "RefreshAllFrames should run AFTER re-decoration (UpdateFrameScaling)")

print("OK: groupframes_refresh_settings_repopulates_overlays_test")
