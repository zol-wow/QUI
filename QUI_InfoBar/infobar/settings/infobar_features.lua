---------------------------------------------------------------------------
-- QUI Info Bar — Options feature-page registration.
-- Registers the Info Bar feature with the settings ProviderFeatures
-- registry, wiring the infobar tile's single subpage to the "infobar"
-- shared provider (built in infobar_content.lua).
--
-- The bar is a full-width screen-edge strip, not a Layout Mode mover, so
-- there is no render.layout / position collapsible here.
---------------------------------------------------------------------------

local _, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "infobar",
    category = "ui",
    nav = {
        tileId = "infobar",
        subPageIndex = 1,
    },
    getDB = function(profile)
        return profile and profile.infobar
    end,
    apply = function()
        if _G.QUI_RefreshInfoBar then _G.QUI_RefreshInfoBar() end
    end,
    providerKey = "infobar",
})
