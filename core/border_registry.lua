local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local BorderRegistry = { entries = {}, byKey = {} }
Helpers.BorderRegistry = BorderRegistry

function BorderRegistry.Register(entry)
    assert(type(entry) == "table" and type(entry.key) == "string" and entry.key ~= "",
        "border entry needs a string key")
    assert(BorderRegistry.byKey[entry.key] == nil,
        "duplicate border entry: " .. tostring(entry.key))
    entry.prefix = entry.prefix or ""
    BorderRegistry.entries[#BorderRegistry.entries + 1] = entry
    BorderRegistry.byKey[entry.key] = entry
    return entry
end

function BorderRegistry.Each(fn)
    for _, e in ipairs(BorderRegistry.entries) do fn(e) end
end

function Helpers.RefreshAllBorders()
    for _, e in ipairs(BorderRegistry.entries) do
        if type(e.refresh) == "function" then pcall(e.refresh) end
    end
end

return BorderRegistry
