local ADDON_NAME, ns = ...

local mainNS = QUI and QUI._ns
if type(mainNS) ~= "table" then
    error("QUI_Debug requires QUI to load first")
end

setmetatable(ns, {
    __index = mainNS,
    __newindex = function(_, key, value)
        mainNS[key] = value
    end,
})

QUI._debugAddonName = ADDON_NAME
