local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if not ProviderFeatures or type(ProviderFeatures.Register) ~= "function" then
    return
end

ProviderFeatures:Register({
    id = "tooltipAnchor",
    moverKey = "tooltipAnchor",
    category = "qol",
    nav = {
        tileId = "chat_tooltips",
        subPageIndex = 2,
    },
    apply = function()
        if ns.QUI_RefreshTooltips then
            ns.QUI_RefreshTooltips()
        end
        if ns.QUI_RefreshTooltipFontSize then
            ns.QUI_RefreshTooltipFontSize()
        end
        if ns.QUI_RefreshTooltipSkinColors then
            ns.QUI_RefreshTooltipSkinColors()
        end
    end,
    providerKey = "tooltipAnchor",
})
