local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "mplusTimer",
    moverKey = "mplusTimer",
    category = "dungeon",
    nav = {
        tileId = "gameplay",
        subPageIndex = 7,
    },
    getDB = function(profile)
        return profile and profile.mplusTimer
    end,
    apply = function()
        local timer = _G.QUI_MPlusTimer
        if timer and timer.UpdateLayout then
            timer:UpdateLayout()
        end
        if _G.QUI_ApplyMPlusTimerSkin then
            _G.QUI_ApplyMPlusTimerSkin()
        end
    end,
    providerKey = "mplusTimer",
})
