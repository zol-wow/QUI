-- tests/unit/performance_metric_targets_test.lua
-- Run: lua tests/unit/performance_metric_targets_test.lua

local function noop() end

local function makeRegion()
    return {
        SetPoint = noop,
        SetText = noop,
        SetTextColor = noop,
        SetHeight = noop,
        SetWidth = noop,
        SetColorTexture = noop,
        SetAlpha = noop,
        Hide = noop,
        Show = noop,
    }
end

local function makeFrame()
    local frame = makeRegion()
    frame.SetSize = noop
    frame.SetFrameStrata = noop
    frame.SetMovable = noop
    frame.SetClampedToScreen = noop
    frame.EnableMouse = noop
    frame.RegisterForDrag = noop
    frame.SetBackdrop = noop
    frame.SetBackdropColor = noop
    frame.SetBackdropBorderColor = noop
    frame.RegisterEvent = noop
    frame.RegisterAllEvents = noop
    frame.UnregisterAllEvents = noop
    frame.SetScript = function(self, script, handler)
        self._scripts = self._scripts or {}
        self._scripts[script] = handler
    end
    frame.GetScript = function(self, script)
        return self._scripts and self._scripts[script] or nil
    end
    frame.CreateFontString = function()
        return makeRegion()
    end
    frame.CreateTexture = function()
        return makeRegion()
    end
    frame.IsShown = function(self)
        return self._shown == true
    end
    frame.Show = function(self)
        self._shown = true
    end
    frame.Hide = function(self)
        self._shown = false
    end
    return frame
end

function CreateFrame()
    return makeFrame()
end

function GetTime() return 10 end
function GetFramerate() return 60 end
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage(addonName)
    if addonName == "QUI" then return 100 end
    if addonName == "QUI_CDM" then return 50 end
    if addonName == "QUI_Debug" then return 25 end
end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
format = string.format
UIParent = makeFrame()
Enum = {
    AddOnProfilerMetric = {
        RecentAverageTime = 1,
    },
}
C_AddOnProfiler = {
    GetAddOnMetric = function(addonName, metric)
        assert(metric == Enum.AddOnProfilerMetric.RecentAverageTime,
            "test should request the recent average metric")
        if addonName == "QUI" then return 1 end
        if addonName == "QUI_CDM" then return 3 end
        if addonName == "QUI_Debug" then return 2 end
    end,
}

-- The post-split metric targets are enumerated from the loaded addon list:
-- every addon named "QUI" or beginning with "QUI_". Non-QUI and unloaded
-- addons must be excluded.
local addonList = {
    { name = "QUI",            loaded = true },
    { name = "QUI_CDM",        loaded = true },
    { name = "SomeOtherAddon", loaded = true },  -- not a QUI addon → excluded
    { name = "QUI_Bags",       loaded = false }, -- not loaded → excluded
    { name = "QUI_Debug",      loaded = true },
}
C_AddOns = {
    GetNumAddOns = function() return #addonList end,
    IsAddOnLoaded = function(i)
        local e = addonList[i]
        return e.loaded, e.loaded
    end,
    GetAddOnInfo = function(i)
        return addonList[i].name
    end,
}

local ns = {}

assert(loadfile("QUI_Debug/performance.lua"))("QUI_Debug", ns)

local perf = assert(ns.QUI_PerfMonitor, "perf monitor should be exported")
assert(type(perf.GetMetricTargetNames) == "function",
    "perf monitor should expose metric target names")

local targets = perf.GetMetricTargetNames()
assert(type(targets) == "table", "metric target names should be returned as a table")
assert(targets[1] == "QUI", "main addon should be the first metric target")

local has = {}
for _, name in ipairs(targets) do has[name] = true end
assert(has["QUI"], "core addon should be a metric target")
assert(has["QUI_CDM"], "loaded QUI_* sub-addons should be metric targets (suite split)")
assert(has["QUI_Debug"], "debug addon should be included as a metric target")
assert(not has["SomeOtherAddon"], "non-QUI addons must be excluded")
assert(not has["QUI_Bags"], "unloaded suite members must be excluded")

assert(perf.GetCPUAPITier() == nil,
    "load-on-demand perf should not rely on a missed PLAYER_LOGIN bootstrap")
assert(type(_G.QUI_TogglePerfMonitor) == "function",
    "perf monitor toggle should be exported")

_G.QUI_TogglePerfMonitor()

assert(perf.GetCPUAPITier() == "profiler",
    "opening the load-on-demand perf monitor should detect the CPU profiler API")

print("OK: performance_metric_targets_test")
