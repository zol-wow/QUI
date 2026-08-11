local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderFeatures = Settings and Settings.ProviderFeatures
if ProviderFeatures and type(ProviderFeatures.Register) == "function" then
    ProviderFeatures:Register({
        id = "bonusRollFrame",
        moverKey = "bonusRollFrame",
        category = "ui",
        providerKey = "bonusRollFrame",
    })
end

do
    local function RegisterBonusRollProvider()
        local settingsPanel = ns.QUI_LayoutMode_Settings
        local U = ns.QUI_LayoutMode_Utils
        if not settingsPanel or not U
            or type(U.BuildPositionCollapsible) ~= "function"
            or type(U.StandardRelayout) ~= "function" then
            return
        end

        settingsPanel:RegisterSharedProvider("bonusRollFrame", {
            build = function(content, key)
                local sections = {}
                local function relayout() U.StandardRelayout(content, sections) end
                U.BuildPositionCollapsible(content, "bonusRollFrame", nil, sections, relayout)
                if type(U.BuildOpenFullSettingsLink) == "function" then
                    U.BuildOpenFullSettingsLink(content, key, sections, relayout)
                end
                relayout()
                return content:GetHeight()
            end,
        })

        local adapters = Settings and Settings.RenderAdapters
        if adapters and type(adapters.NotifyProviderChanged) == "function" then
            adapters.NotifyProviderChanged("bonusRollFrame", { structural = true })
        end
    end

    local ProviderPanels = Settings and Settings.ProviderPanels
    if ProviderPanels and type(ProviderPanels.RegisterAfterLoad) == "function" then
        ProviderPanels:RegisterAfterLoad(function()
            RegisterBonusRollProvider()
        end)
    else
        RegisterBonusRollProvider()
    end
end
