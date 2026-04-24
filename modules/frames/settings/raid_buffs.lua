local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "missingRaidBuffs",
    moverKey = "missingRaidBuffs",
    category = "frames",
    nav = {
        tileId = "gameplay",
        subPageIndex = 6,
    },
    apply = function()
        if _G.QUI_RefreshRaidBuffs then
            _G.QUI_RefreshRaidBuffs()
        end
    end,
    providerKey = "missingRaidBuffs",
})
