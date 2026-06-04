-- tests/unit/options_settings_profiler_static_test.lua
-- Run: lua tests/unit/options_settings_profiler_static_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local framework = readFile("QUI_Options/framework.lua")
local fullSurface = readFile("core/settings/full_surface.lua")
local skinBase = readFile("modules/skinning/base.lua")
local uikit = readFile("core/uikit.lua")
local init = readFile("init.lua")

local settingsSources = {
    framework = framework,
    fullSurface = fullSurface,
    skinBase = skinBase,
    uikit = uikit,
}

local forbidden = {
    "SettingsProfiler",
    "settingsperf",
    "GetSettingsProfiler",
    "RecordSettingsProfiler",
    "MeasureSettingsProfiler",
    "StartPostNavigationSample",
    "BeginNavigation",
    "EndNavigation",
    "ReportLast",
    "post-frame",
    "debugprofilestop",
    "GetTimePreciseSec",
    "BuildTilePage.buildFunc",
    "RenderSubPageTabs.build",
    "FullSurface.RenderActive",
    "FullSurfaceTabWarmup",
    "FullSurfaceTab",
    "Options.CreateBackdrop",
}

for name, text in pairs(settingsSources) do
    for _, needle in ipairs(forbidden) do
        assert(
            not text:find(needle, 1, true),
            name .. " should not contain removed settings instrumentation: " .. needle
        )
    end
end

local initForbidden = {
    "SettingsProfiler",
    "settingsperf",
    "GetSettingsProfiler",
    "RecordSettingsProfiler",
    "MeasureSettingsProfiler",
}

for _, needle in ipairs(initForbidden) do
    assert(
        not init:find(needle, 1, true),
        "init should not contain removed settings instrumentation: " .. needle
    )
end

print("OK: options_settings_profiler_static_test")
