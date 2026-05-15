-- tests/damage_meter_reload_size_test.lua
-- Run: lua tests/damage_meter_reload_size_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local source = readFile("modules/skinning/gameplay/damage_meter.lua")

assertContains(
    source,
    "local meterSizeRestoreHooks = Helpers.CreateStateTable()",
    "Damage meter size restore hooks must be tracked outside Blizzard frames")

assertContains(
    source,
    "local function InstallMeterSizeRestoreHook(window)",
    "Session windows must install a post-setup size restore hook")

assertContains(
    source,
    'hooksecurefunc(target, "SetSize"',
    "Saved meter size must be reasserted after later SetSize calls")

assertContains(
    source,
    'hooksecurefunc(target, "SetWidth"',
    "Saved meter width must be reasserted after later SetWidth calls")

assertContains(
    source,
    'hooksecurefunc(target, "SetHeight"',
    "Saved meter height must be reasserted after later SetHeight calls")

assertContains(
    source,
    "if Helpers.IsLayoutModeActive and Helpers.IsLayoutModeActive() then return end",
    "Size restore hook must not fight live Layout Mode resizing")

local patchSessionWindowBody = source:match("local function PatchSessionWindow%b()%s*(.-)%s*end%s*local function DeferSkinSessionWindow")
assert(patchSessionWindowBody, "PatchSessionWindow body should be present")
assertContains(
    patchSessionWindowBody,
    "InstallMeterSizeRestoreHook(sessionWindow)",
    "Every discovered session window must get the size restore hook")

local deferSkinBody = source:match("local function DeferSkinSessionWindow%b()%s*(.-)%s*end%s*local function HandleSessionWindow")
assert(deferSkinBody, "DeferSkinSessionWindow body should be present")
assertContains(
    deferSkinBody,
    "ApplySavedSizeToWindow(window)",
    "SetupSessionWindow post-hook must reapply saved size after Blizzard setup")

print("OK: damage_meter_reload_size_test")
