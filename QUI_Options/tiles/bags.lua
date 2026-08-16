local ADDON_NAME, ns = ...

local V2Bags = {}
ns.QUI_BagsTile = V2Bags

local SEARCH_TAB_INDEX = 19
local SEARCH_TAB_NAME = ns.L["Bags"]

function V2Bags.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "bags",
        icon = "B",
        name = ns.L["Bags"],
        moduleFeatureId = "moduleAddon_QUI_Bags",
        subPages = {
            {
                id = "bags",
                name = ns.L["Bags"],
                sectionNav = true,
                featureId = "bags",
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Bags"],
                },
            },
        },
    })
end
