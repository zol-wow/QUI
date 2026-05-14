-- tests/resourcebars_breakpoint_settings_test.lua
-- Run: lua tests/resourcebars_breakpoint_settings_test.lua

local calls = {
    collapsibles = {},
    widgets = {},
}

local function noop() end

local function newFrame()
    return {
        SetHeight = noop,
        SetWidth = noop,
        SetSize = noop,
        SetPoint = noop,
        GetHeight = function()
            return 400
        end,
    }
end

function CreateFrame()
    return newFrame()
end

function GetSpecialization()
    return 1
end

function GetSpecializationInfo()
    return 102, "Balance"
end

local function recordWidget(kind, label, dbKey, dbTable)
    calls.widgets[#calls.widgets + 1] = {
        kind = kind,
        label = label,
        dbKey = dbKey,
        dbTable = dbTable,
    }
    return newFrame()
end

local GUI = {
    CreateFormCheckbox = function(_, _, label, dbKey, dbTable)
        return recordWidget("checkbox", label, dbKey, dbTable)
    end,
    CreateFormDropdown = function(_, _, label, _, dbKey, dbTable)
        return recordWidget("dropdown", label, dbKey, dbTable)
    end,
    CreateFormSlider = function(_, _, label, _, _, _, dbKey, dbTable)
        return recordWidget("slider", label, dbKey, dbTable)
    end,
    CreateFormColorPicker = function(_, _, label, dbKey, dbTable)
        return recordWidget("color", label, dbKey, dbTable)
    end,
    CreateFormEditBox = function(_, _, label, dbKey, dbTable)
        return recordWidget("editbox", label, dbKey, dbTable)
    end,
}

QUI = {
    GUI = GUI,
}

local profile = {
    powerBar = {
        enabled = true,
    },
    secondaryPowerBar = {
        enabled = true,
    },
}

local ns = {
    Addon = {
        UpdatePowerBar = noop,
        UpdateSecondaryPowerBar = noop,
    },
    Helpers = {
        GetCore = function()
            return { db = { profile = profile } }
        end,
    },
    QUI_LayoutMode_Utils = {
        FORM_ROW = 32,
        StandardRelayout = noop,
        GetTextureList = function()
            return {}
        end,
        PlaceRow = function(_, _, y)
            return (y or 0) - 32
        end,
        CreateCollapsible = function(_, title, _, build, sections)
            calls.collapsibles[#calls.collapsibles + 1] = title
            local body = newFrame()
            build(body)
            if sections then
                sections[#sections + 1] = newFrame()
            end
        end,
        BuildPositionCollapsible = function(_, key, _, sections)
            calls.collapsibles[#calls.collapsibles + 1] = "Position:" .. tostring(key)
            if sections then
                sections[#sections + 1] = newFrame()
            end
        end,
        BuildOpenFullSettingsLink = noop,
    },
}

assert(loadfile("modules/resourcebars/settings/resource_bars_builders.lua"))("QUI", ns)

local builders = assert(ns.QUI_ResourceBarsSettingsBuilders, "resource bar builders should be exported")
assert(type(builders.BuildPrimaryPowerSettings) == "function", "primary resource settings builder should exist")
assert(type(builders.BuildSecondaryPowerSettings) == "function", "secondary resource settings builder should exist")

builders.BuildPrimaryPowerSettings(newFrame(), "primaryPower")
builders.BuildSecondaryPowerSettings(newFrame(), "secondaryPower")

local function countCollapsible(title)
    local count = 0
    for _, value in ipairs(calls.collapsibles) do
        if value == title then
            count = count + 1
        end
    end
    return count
end

local function countWidget(label)
    local count = 0
    for _, widget in ipairs(calls.widgets) do
        if widget.label == label then
            count = count + 1
        end
    end
    return count
end

local function findWidget(label, predicate)
    for _, widget in ipairs(calls.widgets) do
        if widget.label == label and (not predicate or predicate(widget)) then
            return widget
        end
    end
    return nil
end

assert(countCollapsible("Breakpoint Indicators") == 2,
    "primary and secondary resource settings should expose Breakpoint Indicators sections")

assert(countWidget("Enable Breakpoint Indicators") == 2,
    "each resource bar should expose the breakpoint indicator enable toggle")
assert(countWidget("Indicator Thickness") == 2,
    "each resource bar should expose breakpoint indicator thickness")
assert(countWidget("Indicator Color") == 2,
    "each resource bar should expose breakpoint indicator color")
assert(countWidget("Breakpoint 1") == 2 and countWidget("Breakpoint 2") == 2 and countWidget("Breakpoint 3") == 2,
    "each resource bar should expose three per-spec breakpoint value fields")

assert(type(profile.powerBar.indicators) == "table",
    "primary builder should initialize missing indicator settings")
assert(profile.powerBar.indicators.enabled == false,
    "primary indicator settings should default disabled")
assert(type(profile.powerBar.indicators.perSpec) == "table",
    "primary indicator settings should initialize per-spec storage")

assert(type(profile.secondaryPowerBar.indicators) == "table",
    "secondary builder should initialize missing indicator settings")
assert(profile.secondaryPowerBar.indicators.enabled == false,
    "secondary indicator settings should default disabled")
assert(type(profile.secondaryPowerBar.indicators.perSpec) == "table",
    "secondary indicator settings should initialize per-spec storage")

local primaryBreakpoint = assert(findWidget("Breakpoint 1", function(widget)
    return widget.dbTable ~= nil and widget.dbTable ~= profile.secondaryPowerBar.indicators
end), "primary breakpoint edit box should expose a value proxy")
primaryBreakpoint.dbTable[primaryBreakpoint.dbKey] = "45"
assert(profile.powerBar.indicators.perSpec[102][1] == 45,
    "primary breakpoint edit box should save to the current spec indicator values")

local secondaryBreakpoint = assert(findWidget("Breakpoint 1", function(widget)
    return widget.dbTable ~= nil and widget.dbTable ~= primaryBreakpoint.dbTable
end), "secondary breakpoint edit box should expose a separate value proxy")
secondaryBreakpoint.dbTable[secondaryBreakpoint.dbKey] = "3"
assert(profile.secondaryPowerBar.indicators.perSpec[102][1] == 3,
    "secondary breakpoint edit box should save to the current spec indicator values")

print("OK: resourcebars_breakpoint_settings_test")
