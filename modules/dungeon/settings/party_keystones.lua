local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "partyKeystones",
    moverKey = "partyKeystones",
    category = "dungeon",
    nav = {
        tileId = "gameplay",
        subPageIndex = 2,
    },
    providerKey = "partyKeystones",
})
