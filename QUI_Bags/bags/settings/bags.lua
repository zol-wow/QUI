---------------------------------------------------------------------------
-- QUI Bags — settings feature registration (minimap settings precedent).
-- Loaded from QUI_Options/options.xml (LoD): registers the provider-backed
-- "bags" feature so the Bags tile sub-page renders the shared provider
-- panel built in bags_providers.lua. The module master toggle (enabled +
-- reload prompt) lives in core/settings/content/modules_nonvisual_onboarding.lua.
---------------------------------------------------------------------------
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
