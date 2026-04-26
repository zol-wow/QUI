local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "skyriding",
    moverKey = "skyriding",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 3,
    },
    getDB = function(profile)
        return profile and profile.skyriding
    end,
    apply = function()
        if _G.QUI_RefreshSkyriding then
            _G.QUI_RefreshSkyriding()
        end
    end,
    providerKey = "skyriding",
})
