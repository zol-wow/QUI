local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "readyCheck",
    moverKey = "readyCheck",
    category = "gameplay",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    getDB = function(profile)
        return profile and profile.general
    end,
    apply = function()
        if _G.QUI_RefreshReadyCheckColors then
            _G.QUI_RefreshReadyCheckColors()
        end
    end,
    providerKey = "readyCheck",
})
