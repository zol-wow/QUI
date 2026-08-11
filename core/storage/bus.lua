local ADDON_NAME, ns = ...
local Storage = ns.Storage or {}; ns.Storage = Storage

local unpack = table.unpack or unpack

local Bus = {}
Storage.Bus = Bus

local subscribers = {}

function Bus.Subscribe(eventName, handler)
    local list = subscribers[eventName]
    if not list then list = {}; subscribers[eventName] = list end
    list[#list + 1] = handler
end

function Bus.Unsubscribe(eventName, handler)
    local list = subscribers[eventName]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then table.remove(list, i); return end
    end
end

function Bus.Publish(eventName, ...)
    local list = subscribers[eventName]
    if not list then return end
    local n = #list
    if n == 0 then return end
    local snapshot = {}
    for i = 1, n do snapshot[i] = list[i] end
    local args, nargs = { ... }, select("#", ...)
    for i = 1, n do
        local fn = snapshot[i]
        xpcall(function() fn(eventName, unpack(args, 1, nargs)) end, geterrorhandler())
    end
end
