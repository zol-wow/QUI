local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "actionTracker",
    moverKey = "actionTracker",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    apply = function()
        if _G.QUI_RefreshActionTracker then
            _G.QUI_RefreshActionTracker()
        end
    end,
    providerKey = "actionTracker",
})
