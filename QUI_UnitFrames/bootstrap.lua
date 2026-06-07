---------------------------------------------------------------------------
-- QUI sub-addon bootstrap (generated — keep in sync with
-- core/templates/subaddon_bootstrap.lua; tests enforce byte-equality).
--
-- Bridges this addon's private namespace to the QUI core namespace as a
-- pure metatable proxy: reads resolve to the core table, writes land in
-- the core table. Module files keep their `local _, ns = ...` unchanged
-- and cross-module exports stay visible suite-wide.
--
-- If the core failed to load (## Dependencies should prevent this), this
-- file raises a hard error so the failure is visible rather than silent.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local mainNS = type(QUI) == "table" and QUI._ns
if type(mainNS) ~= "table" then
    error(("%s requires the QUI core addon to load first"):format(ADDON_NAME), 0)
end

setmetatable(ns, {
    __index = mainNS,
    __newindex = function(_, key, value)
        mainNS[key] = value
    end,
})
