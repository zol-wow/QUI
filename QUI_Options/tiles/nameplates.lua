local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_NameplatesTile = V2

local SEARCH_TAB_INDEX = 22

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        featureId = "nameplatesPage",
        id = "nameplates",
        icon = "N",
        name = ns.L["Nameplates"],
        navRoutes = {
            { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0, subPageIndex = 1 },
            { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1, subPageIndex = 1 },
            { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 2, subPageIndex = 1 },
            { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 3, subPageIndex = 1 },
            { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 4, subPageIndex = 1 },
            { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 5, subPageIndex = 1 },
        },
        searchContext = {
            tabIndex = SEARCH_TAB_INDEX,
            tabName = ns.L["Nameplates"],
            subTabIndex = 0,
            subTabName = ns.L["Nameplates"],
        },
        renderOptions = { surface = "full" },
        relatedSettings = {
            { label = ns.L["Unit Frames"],  tileId = "unit_frames" },
            { label = ns.L["Group Frames"], tileId = "group_frames" },
        },
    })
end
