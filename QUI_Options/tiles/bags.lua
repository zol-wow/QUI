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
                id = "bags_general",
                name = ns.L["General"],
                featureId = "bags",
                renderOptions = { providerPage = "general" },
                searchSections = { ns.L["General"], ns.L["Appearance"] },
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Bags"],
                    tileId = "bags",
                    subPageIndex = 1,
                },
            },
            {
                id = "bags_corners",
                name = ns.L["Icon Corners"],
                featureId = "bags",
                renderOptions = { providerPage = "corners" },
                searchSections = { ns.L["Icon Corners"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Bags"],
                    tileId = "bags",
                    subPageIndex = 2,
                },
            },
            {
                id = "bags_behavior",
                name = ns.L["Behavior"],
                featureId = "bags",
                renderOptions = { providerPage = "behavior" },
                searchSections = { ns.L["Behavior"], ns.L["Auto-Open"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Bags"],
                    tileId = "bags",
                    subPageIndex = 3,
                },
            },
            {
                id = "bags_junk",
                name = ns.L["Junk"],
                featureId = "bags",
                renderOptions = { providerPage = "junk" },
                searchSections = { ns.L["Junk"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Bags"],
                    tileId = "bags",
                    subPageIndex = 4,
                },
            },
            {
                id = "bags_currency",
                name = ns.L["Currency Bar"],
                featureId = "bags",
                renderOptions = { providerPage = "currency" },
                searchSections = { ns.L["Currency Bar"], ns.L["Currencies"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Bags"],
                    tileId = "bags",
                    subPageIndex = 5,
                },
            },
            {
                id = "bags_cache",
                name = ns.L["Cached Data"],
                featureId = "bags",
                renderOptions = { providerPage = "cache" },
                searchSections = { ns.L["Cached Data"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Bags"],
                    tileId = "bags",
                    subPageIndex = 6,
                },
            },
        },
    })
end
