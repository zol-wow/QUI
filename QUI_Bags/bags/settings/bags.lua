local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

local function RefreshBagsSurface()
    if _G.QUI_RefreshBags then
        _G.QUI_RefreshBags()
    end
end

ProviderFeatures:Register({
    id = "bags",
    category = "ui",
    nav = {
        tileId = "bags",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.bags
    end,
    apply = RefreshBagsSurface,
    providerKey = "bags",
    keywords = {
        "bags",
        "inventory",
        "bank",
        "guild bank",
        "junk",
        "currency",
        "auto open",
        "new item",
    },
})
