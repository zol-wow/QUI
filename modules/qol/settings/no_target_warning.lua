local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "noTargetWarning",
    moverKey = "noTargetWarning",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 6,
    },
    apply = function()
        if ns.RefreshNoTargetWarning then
            ns.RefreshNoTargetWarning()
        end
    end,
    providerKey = "noTargetWarning",
    keywords = {
        "no target",
        "target warning",
        "combat warning",
        "missing target",
        "no attackable target",
    },
})
