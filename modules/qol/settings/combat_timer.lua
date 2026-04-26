local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "combatTimer",
    moverKey = "combatTimer",
    category = "qol",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    getDB = function(profile)
        return profile and profile.combatTimer
    end,
    apply = function()
        if _G.QUI_RefreshCombatTimer then
            _G.QUI_RefreshCombatTimer()
        end
    end,
    providerKey = "combatTimer",
    sections = {
        { id = "general", title = "General" },
        { id = "text", title = "Text" },
        { id = "backdrop", title = "Backdrop & Border" },
        { id = "position", title = "Position" },
    },
})
