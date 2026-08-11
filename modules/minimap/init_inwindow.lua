local ADDON_NAME, ns = ...
local QUICore = ns.Addon

if ns._inInitSafeWindow and QUICore and QUICore.Minimap and QUICore.Minimap.InitializeOnce then
    QUICore.Minimap:InitializeOnce()
end
