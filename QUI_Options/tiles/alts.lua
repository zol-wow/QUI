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
        subPages = {
            {
                id = "alts",
                name = ns.L["Alts"],
                sectionNav = true,
                featureId = "alts",
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Alts"],
                },
            },
        },
    })
end
