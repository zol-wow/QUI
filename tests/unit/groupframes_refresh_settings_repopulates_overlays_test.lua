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

local path = "QUI_GroupFrames/groupframes/groupframes_roster.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local startPos = assert(source:find("function QUI_GF:RefreshSettings%(%)"),
    "RefreshSettings should exist")
local endPos = assert(source:find("function QUI_GF:Initialize", startPos, true),
    "RefreshSettings should be followed by Initialize")
local body = source:sub(startPos, endPos)

local scalingPos = assert(body:find("UpdateFrameScaling", 1, true),
    "RefreshSettings should re-decorate via UpdateFrameScaling")
local refreshAllPos = assert(body:find("RefreshAllFrames", 1, true),
    "RefreshSettings should repopulate overlays via RefreshAllFrames")

assert(scalingPos < refreshAllPos,
    "RefreshAllFrames should run AFTER re-decoration (UpdateFrameScaling)")

-- Split regression: group frame click-casting must not depend on one early
-- SecureGroupHeader child walk. Unitframes have their own delayed registration
-- path, so groupframes need a local catch-up after layout/settings refresh.
local tocFile = assert(io.open("QUI_GroupFrames/QUI_GroupFrames.toc", "rb"))
local toc = tocFile:read("*a")
tocFile:close()
local layoutFile = assert(io.open("QUI_GroupFrames/groupframes/groupframes_layout.lua", "rb"))
local layout = layoutFile:read("*a")
layoutFile:close()
local clickcastFile = assert(io.open("QUI_GroupFrames/groupframes/groupframes_clickcast.lua", "rb"))
local clickcast = clickcastFile:read("*a")
clickcastFile:close()

local clickcastPos = assert(toc:find("groupframes\\groupframes_clickcast.lua", 1, true),
    "groupframes_clickcast.lua should be loaded")
local rosterPos = assert(toc:find("groupframes\\groupframes_roster.lua", 1, true),
    "groupframes_roster.lua should be loaded")
assert(clickcastPos < rosterPos,
    "click-cast must load before roster Initialize can register group children")

assert(source:find("local function RefreshClickCastFrames%("),
    "roster should expose a shared click-cast registration helper")
assert(source:find("_.RefreshClickCastFrames%s*=%s*RefreshClickCastFrames"),
    "roster should export RefreshClickCastFrames to layout")
assert(source:find("local function RegisterWithClique%("),
    "roster should have a Clique registration catch-up")
assert(source:find("QUI_GF%.RegisterWithClique%s*=%s*RegisterWithClique"),
    "roster should expose RegisterWithClique for group frames")
assert(source:find("ClickCastFrames%[frame%]%s*=%s*true"),
    "RegisterWithClique should add group frames to Clique's ClickCastFrames table")
assert(source:find("RegisterWithClique%(%)"),
    "RefreshClickCastFrames should invoke Clique registration before native registration")
assert(source:find("GFCC:Initialize%(%)"),
    "RefreshClickCastFrames should initialize click-cast if the first pass ran early")
assert(source:find("GFCC:RegisterAllFrames%(%)"),
    "RefreshClickCastFrames should register all group frame children")

local clickRefreshPos = assert(body:find("RefreshClickCastFrames", 1, true),
    "RefreshSettings should re-register click-cast after re-layout")
assert(scalingPos < clickRefreshPos,
    "RefreshSettings should register click-cast after frame re-layout")

local layoutPass = assert(layout:find("ApplyChildFrameLayout%(%)"),
    "deferred visibility callback should apply child layout")
local deferredStart = assert(layout:find("C_Timer%.After%(0, function%(%)", layoutPass - 250),
    "layout should have a deferred visibility callback")
local deferredBody = layout:sub(deferredStart, deferredStart + 700)
local rebuildPos = assert(deferredBody:find("RebuildUnitFrameMap", 1, true),
    "deferred visibility callback should rebuild the unit map")
local layoutClickPos = assert(deferredBody:find("RefreshClickCastFrames", 1, true),
    "deferred visibility callback should refresh click-cast registration")
assert(rebuildPos < layoutClickPos,
    "deferred visibility callback should refresh click-cast after child layout/map rebuild")

assert(clickcast:find("GF%.allFrames"),
    "RegisterAllFrames should fall back to the decorated group frame list")
assert(clickcast:find("if not frame then return end", 1, true),
    "SetupFrameClickCast should validate missing frames")
assert(not clickcast:find("if not frame or registeredFrames%[frame%] then return end"),
    "SetupFrameClickCast must reapply secure attributes to already-registered frames")

print("OK: groupframes_refresh_settings_repopulates_overlays_test")
