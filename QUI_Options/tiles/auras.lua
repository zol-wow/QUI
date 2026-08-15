local ADDON_NAME, ns = ...

ns.QUI_AurasTile = ns.QUI_AurasTile or {}

function ns.QUI_AurasTile.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "auras",
        icon = "*",
        name = ns.L["Auras"],
        subtitle = ns.L["Buffs · debuffs · indicators, all in one place"],
        subPages = {
            {
                id = "aurasWizard",
                name = ns.L["Setup Wizard"],
                featureId = "aurasWizardPage",
                navRoutes = { { tabIndex = 21, subTabIndex = 1 } },
                searchAliases = {
                    ns.L["Setup Wizard"], ns.L["Party auras"], ns.L["Place HoTs"],
                    ns.L["My HoTs"], ns.L["Big defensives on allies"], ns.L["All buffs"],
                    ns.L["Dispellable by me"], ns.L["Boss debuffs"], ns.L["Crowd control"],
                    ns.L["Tank"], ns.L["Healer"], ns.L["DPS"],
                },
                searchContext = {
                    tabIndex = 21,
                    tabName = ns.L["Auras"],
                    subTabIndex = 1,
                    subTabName = ns.L["Setup Wizard"],
                },
            },
            {
                id = "aurasGroup",
                name = ns.L["Group Frames"],
                featureId = "aurasGroupPage",
                navRoutes = { { tabIndex = 21, subTabIndex = 2 } },
                searchContext = {
                    tabIndex = 21,
                    tabName = ns.L["Auras"],
                    subTabIndex = 2,
                    subTabName = ns.L["Group Frames"],
                },
            },
            {
                id = "aurasUnit",
                name = ns.L["Unit Frames"],
                featureId = "aurasUnitPage",
                preview = {
                    height = 140,
                    build = function(previewHost)
                        local surface = ns.QUI_UnitFramesSettingsSurface
                        local preview = surface and surface.preview
                        if preview and type(preview.build) == "function" then
                            preview.build(previewHost, {
                                showDropdown = false,
                                bodyOnly = true,
                                autoHeight = true,
                            })
                        end
                    end,
                },
                navRoutes = { { tabIndex = 21, subTabIndex = 3 } },
                searchContext = {
                    tabIndex = 21,
                    tabName = ns.L["Auras"],
                    subTabIndex = 3,
                    subTabName = ns.L["Unit Frames"],
                },
            },
            {
                id = "aurasActionBar",
                name = ns.L["Buff/Debuff Frames"],
                featureId = "aurasActionBarPage",
                navRoutes = { { tabIndex = 21, subTabIndex = 4 } },
                searchContext = {
                    tabIndex = 21,
                    tabName = ns.L["Auras"],
                    subTabIndex = 4,
                    subTabName = ns.L["Buff/Debuff Frames"],
                },
            },
            {
                id = "aurasNameplate",
                name = ns.L["Nameplates"],
                featureId = "aurasNameplatePage",
                navRoutes = { { tabIndex = 21, subTabIndex = 5 } },
                searchContext = {
                    tabIndex = 21,
                    tabName = ns.L["Auras"],
                    subTabIndex = 5,
                    subTabName = ns.L["Nameplates"],
                },
            },
            {
                id = "aurasDisplays",
                name = ns.L["Aura Displays"],
                featureId = "aurasDisplaysPage",
                navRoutes = { { tabIndex = 21, subTabIndex = 6 } },
                searchAliases = {
                    ns.L["Aura Displays"], ns.L["Custom aura frame"],
                    ns.L["Track a buff on screen"], ns.L["Watch another player's auras"],
                    ns.L["Load Conditions"], ns.L["Classes"], ns.L["Specs"],
                    ns.L["Roles"], ns.L["Encounters"], ns.L["New Display"],
                },
                searchContext = {
                    tabIndex = 21,
                    tabName = ns.L["Auras"],
                    subTabIndex = 6,
                    subTabName = ns.L["Aura Displays"],
                },
            },
        },
    })
end
