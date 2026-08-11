local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "lustTimer",
    moverKey = "lustTimer",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 6,
    },
    getDB = function(profile)
        return profile and profile.lustTimer
    end,
    apply = function()
        if _G.QUI_RefreshLustTimer then
            _G.QUI_RefreshLustTimer()
        end
    end,
    providerKey = "lustTimer",
})
