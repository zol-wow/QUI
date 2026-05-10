local ADDON_NAME, ns = ...

local mainNS = QUI and QUI._ns
if type(mainNS) ~= "table" then
    error("QUI_Options requires QUI to load first")
end

local function CopySharedNamespace()
    rawset(ns, "Addon", mainNS.Addon)
    rawset(ns, "Helpers", mainNS.Helpers)
    rawset(ns, "LSM", mainNS.LSM)
    rawset(ns, "Registry", mainNS.Registry)
    rawset(ns, "Settings", mainNS.Settings)
    rawset(ns, "SettingsUI", mainNS.SettingsUI)
    rawset(ns, "UIKit", mainNS.UIKit)
    rawset(ns, "Utils", mainNS.Utils)
end

setmetatable(ns, {
    __index = mainNS,
    __newindex = function(_, key, value)
        mainNS[key] = value
    end,
})

CopySharedNamespace()

QUI._optionsAddonName = ADDON_NAME
