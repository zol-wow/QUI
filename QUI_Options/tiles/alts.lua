local ADDON_NAME, ns = ...

local V2Alts = {}
ns.QUI_AltsTile = V2Alts

local SEARCH_TAB_INDEX = 20
local SEARCH_TAB_NAME = ns.L["Alts"]

function V2Alts.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "alts",
        icon = "A",
        name = ns.L["Alts"],
        moduleFeatureId = "moduleFlag_alts",
        subPages = {
            {
                id = "alts_general",
                name = ns.L["General"],
                featureId = "alts",
                renderOptions = { providerPage = "general" },
                searchSections = { ns.L["Alts Module"], ns.L["Scanners"] },
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Alts"],
                    tileId = "alts",
                    subPageIndex = 1,
                },
            },
            {
                id = "alts_columns",
                name = ns.L["Roster Columns"],
                featureId = "alts",
                renderOptions = { providerPage = "columns" },
                searchSections = { ns.L["Roster Columns"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Alts"],
                    tileId = "alts",
                    subPageIndex = 2,
                },
            },
            {
                id = "alts_currency",
                name = ns.L["Currencies Tab"],
                featureId = "alts",
                renderOptions = { providerPage = "currency" },
                searchSections = { ns.L["Currencies Tab"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Alts"],
                    tileId = "alts",
                    subPageIndex = 3,
                },
            },
            {
                id = "alts_reputation",
                name = ns.L["Reputations Tab"],
                featureId = "alts",
                renderOptions = { providerPage = "reputation" },
                searchSections = { ns.L["Reputations Tab"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Alts"],
                    tileId = "alts",
                    subPageIndex = 4,
                },
            },
            {
                id = "alts_cache",
                name = ns.L["Cache"],
                featureId = "alts",
                renderOptions = { providerPage = "cache" },
                searchSections = { ns.L["Cache"] },
                navRoutes = {

                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Alts"],
                    tileId = "alts",
                    subPageIndex = 5,
                },
            },
        },
    })
end
