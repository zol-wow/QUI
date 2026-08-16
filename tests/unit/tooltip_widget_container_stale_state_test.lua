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
        dirty = nil,
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
    "hidden container with stale shownWidgetCount high-water mark -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({ widgetSetID = 5 }))) == false,
    "hidden container with registration residue from a crashed unregister -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({ dirty = true }))) == false,
    "hidden container with latched layout dirty flag -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({ numWidgetsShowing = 2 }))) == false,
    "hidden container presents nothing -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({ widgetSetID = SECRET }))) == false,
    "hidden container with stored secret residue -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip({
    widgetType = 2,
    IsShown = function() return true end,
})) == false, "shown non-container child -> not tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({
    IsShown = function() return true end,
}))) == true, "container currently shown -> tainted")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({
    IsShown = function() return SECRET end,
}))) == true, "unreadable shown state -> tainted (keep native when unknown)")

assert(HasTaintedWidgetContainer(makeTooltip(makeContainer({
    IsShown = function() error("secret boolean test") end,
}))) == true, "throwing shown probe -> tainted (keep native when unknown)")

print("OK: tooltip_widget_container_stale_state_test")
