local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local AuraTheme = {}
ns.Addon = ns.Addon or {}
ns.Addon.AuraTheme = AuraTheme
_G.QUI = _G.QUI or {}
_G.QUI.AuraTheme = AuraTheme

function AuraTheme.BorderColor()
    if Helpers and Helpers.GetSkinBorderColor then
        return Helpers.GetSkinBorderColor(nil, nil)
    end
    return 1, 1, 1, 1
end

function AuraTheme.Metrics(profile)
    profile = profile or {}
    return {
        iconSize = profile.iconSize or 24,
        spacing  = profile.spacing  or 2,
        grow     = profile.grow     or "RIGHT",
        maxIcons = profile.maxIcons or 16,
    }
end
