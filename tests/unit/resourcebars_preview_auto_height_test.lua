-- tests/unit/resourcebars_preview_auto_height_test.lua
-- Run: lua tests/unit/resourcebars_preview_auto_height_test.lua

local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local driver = read("QUI_ResourceBars/resourcebars/settings/resource_bars_preview_driver.lua")
local runtime = read("QUI_ResourceBars/resourcebars/resourcebars.lua")
local tile = read("QUI_Options/tiles/resource_bars.lua")

local failures = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

check("Resource Bars header matches the CDM Live Preview treatment",
    driver:find('lbl:SetText(ns.L["Live Preview"])', 1, true) ~= nil
    and driver:find("lbl:SetTextColor(0.6, 0.6, 0.6, 1)", 1, true) ~= nil
    and driver:find("SkinBase.SkinFontString(lbl, { fontOnly = true })", 1, true) ~= nil
    and driver:find('ns.L["PREVIEW"]', 1, true) == nil)

check("tile height remains an initial budget while the driver owns auto-fit",
    tile:find("height = 120", 1, true) ~= nil
    and tile:find("autoHeight = true", 1, true) ~= nil
    and tile:find("contentTop = 20", 1, true) ~= nil
    and tile:find("minHeight = 60", 1, true) ~= nil
    and tile:find("verticalPadding = 2", 1, true) ~= nil)

check("visible section geometry and value-text overflow participate",
    driver:find("IncludeContentBounds(section, bounds, false)", 1, true) ~= nil
    and driver:find("IncludeContentBounds(section.lbl, bounds, true)", 1, true) ~= nil
    and driver:find("IncludeContentBounds(section.barFrame, bounds, true)", 1, true) ~= nil
    and driver:find("IncludeContentBounds(section.val, bounds, true)", 1, true) ~= nil)

check("positive text overflow shifts the top-stacked content below the header",
    driver:find("local topShift = math_max(0, bounds.top - topLimit)", 1, true) ~= nil
    and driver:find("section._previewStackY - shift", 1, true) ~= nil
    and driver:find("bounds.bottom - topShift", 1, true) ~= nil)

check("fit runs after refreshed bounds settle and handles an empty preview",
    driver:find("local function RequestPreviewAutoHeight", 1, true) ~= nil
    and driver:find("C_Timer.After(0, Apply)", 1, true) ~= nil
    and driver:find("host:SetHeight(desiredHeight)", 1, true) ~= nil
    and driver:find("RequestPreviewAutoHeight()", 1, true) ~= nil)

check("auto-height resize does not recurse through OnSizeChanged",
    driver:find("host._previewAutoHeightApplying = true", 1, true) ~= nil
    and driver:find("if not host._previewAutoHeightApplying then", 1, true) ~= nil)

check("rebuilt settings surfaces bind the driver to the visible host",
    driver:find("if state.host == host then", 1, true) ~= nil
    and driver:find("Module.Teardown()", 1, true) ~= nil)

check("tile auto-height options reach the preview driver",
    runtime:find("function(pv, options)", 1, true) ~= nil
    and runtime:find("ns.QUI_ResourceBarsPreview.Build(pv, options)", 1, true) ~= nil
    and tile:find("_G.QUI_BuildResourceBarPreview(pv, {", 1, true) ~= nil)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("resourcebars_preview_auto_height_test: all checks passed")
