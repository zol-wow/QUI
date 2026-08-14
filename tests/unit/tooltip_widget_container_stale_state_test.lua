-- tests/unit/tooltip_widget_container_stale_state_test.lua
-- Run: lua tests/unit/tooltip_widget_container_stale_state_test.lua
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return (data:gsub("\r\n", "\n"))
end

local src = readAll("core/utils.lua")
local body = src:match("function Helpers%.HasTaintedWidgetContainer.-\nend")
assert(body, "HasTaintedWidgetContainer not found in core/utils.lua")

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local HelpersStub = {
    IsSecretValue = function(v) return v == SECRET end,
}

local loader = loadstring or load
local factory = assert(loader(
    "return function(Helpers)\n" .. body .. "\nreturn Helpers.HasTaintedWidgetContainer\nend",
    "HasTaintedWidgetContainer"))
local HasTaintedWidgetContainer = factory()(HelpersStub)
assert(type(HasTaintedWidgetContainer) == "function", "helper extracted")

local function makeContainer(overrides)
    local child = {
        RegisterForWidgetSet = function() end,
        widgetSetID = nil,
        shownWidgetCount = 3,
        numWidgetsShowing = 0,
        IsShown = function() return false end,
        GetNumPoints = function() return 0 end,
    }
    for k, v in pairs(overrides or {}) do child[k] = v end
    return child
end

local function makeTooltip(child)
    return {
        GetChildren = function()
            if child then return child end
        end,
    }
end

assert(HasTaintedWidgetContainer(makeTooltip(nil)) == false,
    "no children -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer())) == false,
    "cleared container with stale shownWidgetCount high-water mark -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({ widgetSetID = 5 }))) == true,
    "registered widget set -> tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({ numWidgetsShowing = 2 }))) == true,
    "widgets showing -> tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({
    IsShown = function() return true end,
}))) == true, "container currently shown -> tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({ widgetSetID = SECRET }))) == true,
    "secret widget state -> tainted (keep native when unknown)")

print("OK: tooltip_widget_container_stale_state_test")
