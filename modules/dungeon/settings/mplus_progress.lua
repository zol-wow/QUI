local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "mplusProgress",
    category = "dungeon",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    getDB = function(profile)
        return profile and profile.mplusProgress
    end,
    apply = function()
        if _G.QUI_RefreshMPlusProgress then
            _G.QUI_RefreshMPlusProgress()
        end
    end,
    providerKey = "mplusProgress",
})
