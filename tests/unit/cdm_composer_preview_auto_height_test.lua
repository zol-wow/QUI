-- tests/unit/cdm_composer_preview_auto_height_test.lua
-- Run: lua tests/unit/cdm_composer_preview_auto_height_test.lua

local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local composer = read("QUI_CDM/cdm/settings/composer.lua")
local driver = read("QUI_CDM/cdm/settings/composer_preview_driver.lua")
local page = read("QUI_CDM/cdm/settings/containers_page.lua")

local failures = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

check("composer measures only driver-owned icon or bar roots",
    composer:find("local function MeasurePreviewContentHeight", 1, true) ~= nil
    and composer:find("driver.GetContentFrames", 1, true) ~= nil
    and driver:find("function CDMComposerPreview.GetContentFrames", 1, true) ~= nil)

check("fit includes outsetting borders and vertical breathing room",
    composer:find("IncludePreviewBounds(frame.Border, bounds, true)", 1, true) ~= nil
    and composer:find("IncludePreviewBounds(frame.BorderContainer, bounds, true)", 1, true) ~= nil
    and composer:find("PREVIEW_CONTENT_VERTICAL_PADDING * 2", 1, true) ~= nil)

check("fit runs after refreshed frame bounds settle",
    composer:find("local function RequestPreviewAutoHeight", 1, true) ~= nil
    and composer:find("C_Timer.After(0, Apply)", 1, true) ~= nil
    and composer:find("RequestPreviewAutoHeight(previewFrame)", 1, true) ~= nil)

check("fit resizes the configured outer pane and recenters content",
    composer:find("outer:SetHeight(desiredHeight)", 1, true) ~= nil
    and composer:find("driver.Relayout()", 1, true) ~= nil
    and driver:find("function CDMComposerPreview.Relayout", 1, true) ~= nil)

check("standalone composer sections follow the fitted preview",
    composer:find('entrySection:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)', 1, true) ~= nil
    and composer:find('preview:HookScript("OnSizeChanged", Relayout)', 1, true) ~= nil
    and composer:find("frame._composerNaturalHeight = previewHeight", 1, true) ~= nil
    and composer:find("local PREVIEW_H", 1, true) == nil)

check("pinned composer preview fits its outer surface pane",
    page:find("outer = pv", 1, true) ~= nil
    and page:find("outerChromeHeight = LEFT_COL_HEIGHT + 4 + 8", 1, true) ~= nil
    and composer:find("container._previewChromeHeight + PREVIEW_MIN_CONTENT_HEIGHT", 1, true) ~= nil)

check("preview scale slider is removed and its space is reclaimed",
    composer:find('ns.L["Preview Scale:"]', 1, true) == nil
    and composer:find("local sliderTrack", 1, true) == nil
    and composer:find('gridArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)', 1, true) ~= nil
    and composer:find("local PREVIEW_INNER_CHROME_HEIGHT = 32", 1, true) ~= nil)

check("rebuilt preview hosts rebind the singleton driver grid",
    driver:find("state.gridArea = gridArea", 1, true) ~= nil
    and driver:find("state.ticker:SetParent(gridArea)", 1, true) ~= nil)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("cdm_composer_preview_auto_height_test: all checks passed")
