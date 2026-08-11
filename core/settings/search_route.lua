local ADDON_NAME, ns = ...

local unpack = unpack or table.unpack

local Settings = ns.Settings or {}
ns.Settings = Settings

local SearchRoute = Settings.SearchRoute or {}
Settings.SearchRoute = SearchRoute

local ROUTE_FIELDS = {
    "tabIndex", "tabName", "subTabIndex", "subTabName",
    "tileId", "subPageIndex", "featureId",
}

local stack = {}

function SearchRoute.Depth()
    return #stack
end

function SearchRoute.Active()
    return stack[#stack]
end

function SearchRoute.Push(route)
    if type(route) ~= "table" then
        return false
    end
    stack[#stack + 1] = route
    return true
end

function SearchRoute.Pop()
    if #stack == 0 then
        return false
    end
    stack[#stack] = nil
    return true
end

function SearchRoute.Apply(context)
    local route = stack[#stack]
    if type(context) ~= "table" or type(route) ~= "table" then
        return context
    end
    for index = 1, #ROUTE_FIELDS do
        local field = ROUTE_FIELDS[index]
        if route[field] ~= nil then
            context[field] = route[field]
        end
    end
    return context
end

function SearchRoute.With(route, fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    if type(route) ~= "table" then
        return fn(...)
    end

    local depth = #stack
    stack[#stack + 1] = route

    local results = { pcall(fn, ...) }

    for index = #stack, depth + 1, -1 do
        stack[index] = nil
    end

    if not results[1] then
        error(results[2], 0)
    end
    return unpack(results, 2)
end
