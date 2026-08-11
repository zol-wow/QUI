-- tests/unit/actionbars_preview_auto_height_test.lua
-- Run: lua tests/unit/actionbars_preview_auto_height_test.lua

local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local content = read("QUI_ActionBars/actionbars/settings/action_bars_content.lua")
local driver = read("QUI_ActionBars/actionbars/settings/action_bars_preview_driver.lua")
local tile = read("QUI_Options/tiles/action_bars.lua")

local failures = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

check("Action Bars header matches the CDM Live Preview treatment",
    content:find('lbl:SetText(ns.L["Live Preview"])', 1, true) ~= nil
    and content:find("lbl:SetTextColor(0.6, 0.6, 0.6, 1)", 1, true) ~= nil
    and content:find("SkinBase.SkinFontString(lbl, { fontOnly = true })", 1, true) ~= nil
    and content:find('ns.L["P R E V I E W"]', 1, true) == nil)

check("tile height remains an initial budget while the driver owns auto-fit",
    tile:find("height = 110", 1, true) ~= nil
    and content:find("autoHeight = true", 1, true) ~= nil
    and content:find("chromeHeight = 42", 1, true) ~= nil
    and content:find("verticalPadding = 2", 1, true) ~= nil)

check("configured multi-row geometry determines fitted height",
    driver:find("state.layoutCount = visibleCount", 1, true) ~= nil
    and driver:find("for i = 1, state.layoutCount do", 1, true) ~= nil
    and driver:find("IncludeContentBounds(pb.frame, bounds, false)", 1, true) ~= nil)

check("visible button text overflow participates in measurement",
    driver:find("IncludeContentBounds(pb.hotkey, bounds, true)", 1, true) ~= nil
    and driver:find("IncludeContentBounds(pb.name, bounds, true)", 1, true) ~= nil
    and driver:find("IncludeContentBounds(pb.count, bounds, true)", 1, true) ~= nil
    and driver:find("GetCountdownFontString", 1, true) ~= nil)

check("asymmetric text offsets reserve a centered content radius",
    driver:find("math.abs(bounds.top - centerY)", 1, true) ~= nil
    and driver:find("math.abs(bounds.bottom - centerY)", 1, true) ~= nil
    and driver:find("return radius * 2", 1, true) ~= nil)

check("fit runs after refresh bounds settle",
    driver:find("local function RequestPreviewAutoHeight", 1, true) ~= nil
    and driver:find("C_Timer.After(0, Apply)", 1, true) ~= nil
    and driver:find("host:SetHeight(desiredHeight)", 1, true) ~= nil
    and driver:find("RequestPreviewAutoHeight()", 1, true) ~= nil)

check("rebuilt settings surfaces bind the driver to the visible host",
    driver:find("if state.host == host then", 1, true) ~= nil
    and driver:find("ActionBarsPreviewDriver.Teardown()", 1, true) ~= nil)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("actionbars_preview_auto_height_test: all checks passed")
