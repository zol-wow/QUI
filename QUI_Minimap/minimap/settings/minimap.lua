local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

local function RefreshMinimapSurface()
    if _G.QUI_RefreshMinimap then
        _G.QUI_RefreshMinimap()
    end
end

ProviderFeatures:Register({
    id = "minimap",
    moverKey = "minimap",
    category = "ui",
    nav = {
        tileId = "minimap",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.minimap
    end,
    apply = RefreshMinimapSurface,
    providerKey = "minimap",
})
