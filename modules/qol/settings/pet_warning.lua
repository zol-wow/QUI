local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "petWarning",
    moverKey = "petWarning",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 6,
    },
    apply = function()
        if _G.QUI_RefreshPetWarning then
            _G.QUI_RefreshPetWarning()
        end
    end,
    providerKey = "petWarning",
    keywords = {
        "pet",
        "hunter pet",
        "warlock pet",
        "summon reminder",
        "missing pet",
        "no pet",
    },
})
