local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "xpTracker",
    moverKey = "xpTracker",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.xpTracker
    end,
    apply = function()
        if _G.QUI_RefreshXPTracker then
            _G.QUI_RefreshXPTracker()
        end
    end,
    providerKey = "xpTracker",
})
