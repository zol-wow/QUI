local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "brezCounter",
    moverKey = "brezCounter",
    category = "dungeon",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    getDB = function(profile)
        return profile and profile.brzCounter
    end,
    apply = function()
        if _G.QUI_RefreshBrezCounter then
            _G.QUI_RefreshBrezCounter()
        end
    end,
    providerKey = "brezCounter",
})
