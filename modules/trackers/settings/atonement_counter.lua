local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "atonementCounter",
    moverKey = "atonementCounter",
    category = "trackers",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    getDB = function(profile)
        return profile and profile.atonementCounter
    end,
    apply = function()
        if _G.QUI_RefreshAtonementCounter then
            _G.QUI_RefreshAtonementCounter()
        end
    end,
    providerKey = "atonementCounter",
})
