-- tests/unit/groupframes_preview_context_switch_test.lua
-- Run: lua tests/unit/groupframes_preview_context_switch_test.lua
--
-- The Auras and Group Frames tiles cache separate Party/Raid dropdowns while
-- sharing one detached preview renderer. Showing either tile must restore that
-- tile's retained dropdown value before the preview rebuilds.

local function read(path)
    local handle = assert(io.open(path, "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local surface = read("QUI_GroupFrames/groupframes/settings/group_frames_surface.lua")
local auraPage = read("core/settings/content/auras_group_page.lua")

local failures = 0
local function check(name, ok)
    if ok then
        print("  ok  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

local activateStart = assert(surface:find("local function ActivatePreviewBody", 1, true))
local bindStart = assert(surface:find("local function BindPreviewBody", activateStart, true))
local activateBody = surface:sub(activateStart, bindStart - 1)
local setContext = assert(activateBody:find("SetContextMode(contextMode)", 1, true))
local refresh = assert(activateBody:find("RefreshPreviewPanel()", 1, true))

check("visible surface restores its context before rebuilding the preview",
    activateBody:find("body._gfPreviewContextGetter", 1, true) ~= nil
    and setContext < refresh)
check("cached preview binding reads its context getter dynamically",
    surface:find("body._gfPreviewContextGetter = getContextMode", 1, true) ~= nil
    and surface:find("ActivatePreviewBody(body)", bindStart, true) ~= nil)
check("main Group Frames tile restores its retained dropdown value",
    surface:find("local contextDropdown", 1, true) ~= nil
    and surface:find("contextDropdown = FullSurface.BuildContextDropdownRow", 1, true) ~= nil
    and surface:find("contextDropdown.dropdownDB", 1, true) ~= nil)
check("Auras Group Frames page restores its retained dropdown value",
    auraPage:find("GFSurface.ShowPreviewOn(previewHost, function()", 1, true) ~= nil
    and auraPage:find("built and built.dropdownDB", 1, true) ~= nil)

if failures > 0 then
    print(("%d failures"):format(failures))
    os.exit(1)
end

print("groupframes_preview_context_switch_test: all checks passed")
