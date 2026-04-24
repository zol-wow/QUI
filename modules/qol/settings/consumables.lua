local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "consumables",
    moverKey = "consumables",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 6,
    },
    getDB = function(profile)
        return profile and profile.general
    end,
    apply = function()
        if _G.QUI_RefreshConsumables then
            _G.QUI_RefreshConsumables()
        end
    end,
    providerKey = "consumables",
})
