-- tests/unit/resourcebars_shims_use_preview_driver_test.lua
-- Run: lua tests/unit/resourcebars_shims_use_preview_driver_test.lua

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    data = data:gsub("\r\n", "\n")
    return data
end

local rb = readAll("modules/resourcebars/resourcebars.lua")

-- T9: globals delegate to the driver
assert(rb:find("ns.QUI_ResourceBarsPreview.Build", 1, true),
    "_G.QUI_BuildResourceBarPreview must delegate to ns.QUI_ResourceBarsPreview.Build")
assert(rb:find("ns.QUI_ResourceBarsPreview.Refresh", 1, true),
    "_G.QUI_RefreshResourceBarPreview must delegate to ns.QUI_ResourceBarsPreview.Refresh")

-- T9: inline preview-helpers block is gone
assert(not rb:find("MOCK_PRIMARY_FILL", 1, true),
    "resourcebars.lua must no longer define MOCK_PRIMARY_FILL (migrated to driver)")
assert(not rb:find("MOCK_SECONDARY_FILL", 1, true),
    "resourcebars.lua must no longer define MOCK_SECONDARY_FILL (migrated to driver)")
assert(not rb:find("local function MakeMockBar", 1, true),
    "resourcebars.lua must no longer define MakeMockBar (migrated to driver)")
assert(not rb:find("local function ApplyPreviewTicks", 1, true),
    "resourcebars.lua must no longer define ApplyPreviewTicks (migrated to driver)")
assert(not rb:find("local function MockValueText", 1, true),
    "resourcebars.lua must no longer define MockValueText (migrated to driver)")

-- T9: ns.QUI_ResourceBars_Internal export is still present
assert(rb:find("ns.QUI_ResourceBars_Internal", 1, true),
    "ns.QUI_ResourceBars_Internal export must still be present (driver needs it)")

-- T10: resourcebars.xml registers the preview driver, AFTER resourcebars.lua
local xml = readAll("modules/resourcebars/resourcebars.xml")
assert(xml:find("resource_bars_preview_driver.lua", 1, true),
    "modules/resourcebars/resourcebars.xml must register resource_bars_preview_driver.lua")
local rbPos     = xml:find("resourcebars.lua", 1, true)
local driverPos = xml:find("resource_bars_preview_driver.lua", 1, true)
assert(rbPos and driverPos and rbPos < driverPos,
    "resourcebars.xml must load resource_bars_preview_driver.lua AFTER resourcebars.lua")

print("OK: resourcebars_shims_use_preview_driver_test")
