---------------------------------------------------------------------------
-- QUI Border Registry
-- Ordered registry of in-scope border modules; drives the global border
-- refresh broadcast (Helpers.RefreshAllBorders) and future UI enumeration.
--
-- Convention:
--   entry = {
--     key      = string,            -- unique stable identifier
--     label    = string,            -- human-readable display name
--     category = string,            -- grouping hint for the options page
--     prefix   = string,            -- DB key prefix (defaults to "")
--     db       = function(profile)->table|nil,
--     refresh  = function()->nil,   -- called by RefreshAllBorders
--     legacy   = { table=, useClass=, accent=, scalars=, override= },
--     multi    = bool,              -- true when one module owns N instances
--     instances= function(profile)->{table,...},
--   }
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local BorderRegistry = { entries = {}, byKey = {} }
Helpers.BorderRegistry = BorderRegistry

--- Register a border module entry.
-- @param entry table  must have a unique string `key`
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

--- Iterate all entries in registration order.
-- @param fn function  called with each entry
function BorderRegistry.Each(fn)
    for _, e in ipairs(BorderRegistry.entries) do fn(e) end
end

--- Fire every registered module's border refresher.
-- Called when the global border color/style changes so all in-scope modules
-- repaint consistently. Individual refresh errors are isolated via pcall.
function Helpers.RefreshAllBorders()
    for _, e in ipairs(BorderRegistry.entries) do
        if type(e.refresh) == "function" then pcall(e.refresh) end
    end
end

return BorderRegistry
