-- tests/unit/auras_unit_pinned_preview_test.lua
-- Run: lua tests/unit/auras_unit_pinned_preview_test.lua
--
-- The Auras > Unit Frames mock belongs outside the scroll root. It reuses the
-- real Unit Frames preview in body-only mode and reserves less vertical space.

local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local tile = read("QUI_Options/tiles/auras.lua")
local unitTile = read("QUI_Options/tiles/unit_frames.lua")
local shared = read("QUI_Options/shared.lua")
local framework = read("QUI_Options/framework.lua")
local page = read("core/settings/content/auras_unit_page.lua")
local surface = read("QUI_UnitFrames/unitframes/settings/unit_frames_surface.lua")

local failures = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

check("Auras Unit Frames sub-page registers a compact preview",
    tile:find('id = "aurasUnit"', 1, true) ~= nil
    and tile:find("height = 140", 1, true) ~= nil
    and tile:find("bodyOnly = true", 1, true) ~= nil
    and tile:find("autoHeight = true", 1, true) ~= nil)
check("feature-tile adapter preserves per-sub-page previews",
    shared:find("preview = subPage.preview", 1, true) ~= nil)
check("sub-page preview is built before and outside the scroll root",
    framework:find("local contentRoot = container", 1, true) ~= nil
    and framework:find('contentRoot:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)', 1, true) ~= nil
    and framework:find("CreateScrollableContent(contentRoot)", 1, true) ~= nil)
check("aura page no longer allocates an inline scrolling preview",
    page:find("UFSurface.preview.build", 1, true) == nil
    and page:find('local previewHost = CreateFrame("Frame", nil, host)', 1, true) == nil)
check("both preview modes fit their container to visible content bounds",
    surface:find("local function MeasurePreviewContentHeight", 1, true) ~= nil
    and surface:find("IncludeFrameTreeBounds(mock._castbarMock, bounds)", 1, true) ~= nil
    and surface:find("outer:SetHeight(desiredHeight)", 1, true) ~= nil
    and surface:find("RequestPreviewAutoHeight(mock)", 1, true) ~= nil)
check("auto-fit does not recursively shrink preview content",
    surface:find("mock._previewScaleBudgetHeight", 1, true) ~= nil
    and surface:find("scaleBudgetHeight - chromeHeight", 1, true) ~= nil)
check("body-only preview reclaims castbar space",
    surface:find("if bodyOnly and mock._castbarMock then", 1, true) ~= nil
    and surface:find("showDropdown and 56 or 20", 1, true) ~= nil
    and surface:find("bodyOnly and 60 or 96", 1, true) ~= nil)
check("regular Unit Frames preview is compact but retains its full mode",
    unitTile:find("previewHeight = 180", 1, true) ~= nil
    and surface:find("height = 180", 1, true) ~= nil)
check("cached previews reactivate their own live refresh target",
    surface:find('pv:HookScript("OnShow"', 1, true) ~= nil
    and surface:find("State.previewMock = previewMockForBlock", 1, true) ~= nil)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("auras_unit_pinned_preview_test: all checks passed")
