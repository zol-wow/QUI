-- tests/unit/actionbars_content_uses_preview_driver_test.lua
-- Run: lua tests/unit/actionbars_content_uses_preview_driver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    data = data:gsub("\r\n", "\n")
    return data
end

local content = readAll("modules/actionbars/settings/action_bars_content.lua")

-- T9: content.lua delegates to the driver for build + refresh + selected-bar
assert(content:find("ns.QUI_ActionBarsPreviewDriver.Build", 1, true),
    "content.lua BuildActionBarsPreview must call ns.QUI_ActionBarsPreviewDriver.Build")
assert(content:find("ns.QUI_ActionBarsPreviewDriver.Refresh", 1, true),
    "content.lua must reference ns.QUI_ActionBarsPreviewDriver.Refresh (via PreviewState.refresh)")
assert(content:find("ns.QUI_ActionBarsPreviewDriver.SetSelectedBar", 1, true),
    "content.lua SetActionBarsPreviewBar must call driver.SetSelectedBar")
assert(content:find("ns.QUI_ActionBarsPreviewDriver.IsPreviewable", 1, true),
    "content.lua IsPreviewableBar must delegate to driver.IsPreviewable")

-- T9: safety-net poll cadence is 1.0s, not 0.25s
assert(content:find("_accum < 1.0", 1, true)
    or content:find("_accum < 1 ", 1, true),
    "content.lua safety-net OnUpdate poll must be 1.0s (was 0.25s)")
assert(not content:find("_accum < 0.25", 1, true),
    "content.lua must no longer poll at 0.25s")

-- T9: actionbars.lua _G.QUI_RefreshActionBars chains the driver refresh
local actionbars = readAll("modules/actionbars/actionbars.lua")
assert(actionbars:find("ns.QUI_ActionBarsPreviewDriver", 1, true),
    "actionbars.lua _G.QUI_RefreshActionBars must chain ns.QUI_ActionBarsPreviewDriver.Refresh")

-- T9: options.xml registers the driver file
local optionsXml = readAll("QUI_Options/options.xml")
assert(optionsXml:find("action_bars_preview_driver.lua", 1, true),
    "QUI_Options/options.xml must register action_bars_preview_driver.lua")
-- And it must come BEFORE action_bars_content.lua so the driver is loaded first
local driverPos = optionsXml:find("action_bars_preview_driver.lua", 1, true)
local contentPos = optionsXml:find("action_bars_content.lua", 1, true)
assert(driverPos and contentPos and driverPos < contentPos,
    "options.xml must load action_bars_preview_driver.lua before action_bars_content.lua")

print("OK: actionbars_content_uses_preview_driver_test")
