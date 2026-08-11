local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

local function RefreshAltsSurface()
    if _G.QUI_RefreshAlts then
        _G.QUI_RefreshAlts()
    end
end

ProviderFeatures:Register({
    id = "alts",
    category = "ui",
    nav = {
        tileId = "alts",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.alts
    end,
    apply = RefreshAltsSurface,
    providerKey = "alts",
    keywords = {
        "alts",
        "roster",
        "characters",
        "item level",
        "gold",
        "played time",
        "rested",
        "reputations",
        "weeklies",
        "lockouts",
        "professions",
    },
})
