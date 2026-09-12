local ADDON_NAME, ns = ...

local mainNS = type(QUI) == "table" and QUI._ns
if type(mainNS) ~= "table" then
    error(("%s requires the QUI core addon to load first"):format(ADDON_NAME), 0)
end

setmetatable(ns, {
    __index = mainNS,
    __newindex = function(_, key, value)
        local track = mainNS._TrackSuiteNsExport
        if track then track(ADDON_NAME, key, value) end
        mainNS[key] = value
    end,
})
