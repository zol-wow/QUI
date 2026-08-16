local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_ActionBarsTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "action_bars",
        icon = "A",
        name = ns.L["Action Bars"],
        moduleFeatureId = "moduleAddon_QUI_ActionBars",
        primaryCTA = { label = ns.L["Edit in Layout Mode"], moverKey = "bar1" },
        preview = {
            height = 110,
            build = function(pv)
                if ns.QUI_ActionBarsOptions and ns.QUI_ActionBarsOptions.BuildActionBarsPreview then
                    ns.QUI_ActionBarsOptions.BuildActionBarsPreview(pv)
                end
            end,
        },
        subPages = {
            {
                id = "general",
                name = ns.L["General"],
                featureId = "actionBarsGeneral",
                navRoutes = { { tabIndex = 8, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 0,
                    subTabName = ns.L["General"],
                },
            },
            {
                id = "perBar",
                name = ns.L["Per-Bar"],
                featureId = "actionBarsPerBar",
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 3,
                    subTabName = ns.L["Per-Bar"],
                },
            },
            {
                id = "totemBar",
                name = ns.L["Totem Bar"],
                featureId = "actionBarsTotemBar",
                navRoutes = { { tabIndex = 8, subTabIndex = 5 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 5,
                    subTabName = ns.L["Totem Bar"],
                },
            },
            {
                id = "raidMarkers",
                name = ns.L["Raid Markers"],
                featureId = "actionBarsRaidMarkersBar",
                navRoutes = { { tabIndex = 8, subTabIndex = 6 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 6,
                    subTabName = ns.L["Raid Markers"],
                },
            },
            {
                id = "bagBar",
                name = ns.L["Bag Bar"],
                featureId = "actionBarsBagBar",
                navRoutes = { { tabIndex = 8, subTabIndex = 7 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 7,
                    subTabName = ns.L["Bag Bar"],
                },
            },
            {
                id = "extraZone",
                name = ns.L["Extra & Zone"],
                featureId = "actionBarsExtraZone",
                navRoutes = { { tabIndex = 8, subTabIndex = 8 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 8,
                    subTabName = ns.L["Extra & Zone"],
                },
            },
            {
                id = "buffDebuff",
                name = ns.L["Buff/Debuff Frames"],
                featureId = "actionBarsBuffDebuffPage",
                navRoutes = { { tabIndex = 8, subTabIndex = 4 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 4,
                    subTabName = ns.L["Buff/Debuff Frames"],
                },
            },
        },
    })
end
