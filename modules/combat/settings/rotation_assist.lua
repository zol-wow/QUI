local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "rotationAssistIcon",
    moverKey = "rotationAssistIcon",
    category = "combat",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    getDB = function(profile)
        return profile and profile.rotationAssistIcon
    end,
    apply = function()
        if _G.QUI_RefreshRotationAssistIcon then
            _G.QUI_RefreshRotationAssistIcon()
        end
    end,
    providerKey = "rotationAssistIcon",
})
