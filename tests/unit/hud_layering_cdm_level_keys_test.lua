local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data:gsub("\r\n", "\n")
end

local containers = readAll("QUI_CDM/cdm/cdm_containers.lua")

assert(containers:find("CDMContainers_API.HUD_LAYERING = {", 1, true),
    "cdm_containers must define the HUD_LAYERING map from container keys to hudLayering keys and Blizzard viewer names")

local layoutStart = assert(containers:find(
    "local function LayoutContainer(trackerKey, runtimeVisibilityRelayout)", 1, true),
    "LayoutContainer definition not found")
local layoutEnd = assert(containers:find("\nRefreshAll = function", layoutStart, true),
    "LayoutContainer end marker not found")
local layoutBody = containers:sub(layoutStart, layoutEnd)

assert(not layoutBody:find("hudLayering and hudLayering[trackerKey] or 5", 1, true),
    "LayoutContainer must not read hudLayering by raw trackerKey; buff/trackedBar/custom keys are never written by the Frame Levels tab")
assert(layoutBody:find('CDMContainers_API.HUD_LAYERING.keys[trackerKey] or "customBars"', 1, true),
    "LayoutContainer must resolve the hudLayering key through HUD_LAYERING.keys with a customBars fallback for custom containers")
assert(layoutBody:find("CDMContainers_API.HUD_LAYERING.viewers[trackerKey]", 1, true),
    "LayoutContainer must resolve the Blizzard viewer for the tracker key")
assert(layoutBody:find('viewer:SetFrameStrata("MEDIUM")', 1, true),
    "LayoutContainer must pin the Blizzard viewer to MEDIUM so frame levels stay comparable to castbars and unit frames")
assert(layoutBody:find("viewer:SetFrameLevel(frameLevel)", 1, true),
    "LayoutContainer must apply the hudLayering frame level to the Blizzard viewer so natively rendered icons follow the slider")

local tab = readAll("modules/ui/settings/hud_layering_content.lua")

assert(not tab:find("NCDM:ApplySettings", 1, true),
    "the Frame Levels tab must not call NCDM:ApplySettings; _G.NCDM is never assigned so that refresh path is a silent no-op")
assert(tab:find("_G.QUI_RefreshNCDM", 1, true),
    "the Frame Levels tab must refresh CDM containers through the wired _G.QUI_RefreshNCDM global")
assert(not tab:find("QUI_RefreshCustomTrackers", 1, true),
    "the Frame Levels tab must not call QUI_RefreshCustomTrackers; that global is never assigned")
assert(tab:find("local function RefreshCustomTrackers() RefreshCDM() end", 1, true),
    "the customBars slider must refresh through the CDM container layout that consumes hudLayering.customBars")

print("OK: hud_layering_cdm_level_keys_test")
