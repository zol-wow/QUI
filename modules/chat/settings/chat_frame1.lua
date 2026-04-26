local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "chatFrame1",
    moverKey = "chatFrame1",
    category = "chat",
    nav = {
        tileId = "chat_tooltips",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.chat
    end,
    apply = function()
        if _G.QUI_RefreshChat then
            _G.QUI_RefreshChat()
        end
    end,
    providerKey = "chatFrame1",
})
