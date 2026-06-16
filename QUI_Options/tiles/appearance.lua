--[[
    QUI Options V2 — Appearance tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_AppearanceTile = V2

local SEARCH_TAB_INDEX = 10
local SEARCH_TAB_NAME = ns.L["Appearance"]

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "appearance",
        icon = "S",
        name = ns.L["Appearance"],
        subPages = {
            {
                id = "uiScale",
                name = ns.L["UI Scale"],
                featureId = "uiScale",
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 3 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 3,
                    subTabName = ns.L["UI Scale"],
                },
                searchAliases = {
                    ns.L["ui scale"],
                    ns.L["scale"],
                    ns.L["interface size"],
                    ns.L["zoom"],
                    ns.L["resolution scale"],
                },
            },
            {
                id = "fonts",
                name = ns.L["Fonts"],
                featureId = "defaultFonts",
                navRoutes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 4 } },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 4,
                    subTabName = ns.L["Fonts"],
                },
                searchAliases = {
                    ns.L["fonts"],
                    ns.L["default font"],
                    ns.L["typography"],
                    ns.L["font family"],
                    ns.L["font face"],
                },
            },
            {
                id = "character",
                name = ns.L["Character"],
                featureId = "characterPane",
                searchContext = {
                    tileId = "appearance",
                    tabName = SEARCH_TAB_NAME,
                    subPageIndex = 3,
                    subTabName = ns.L["Character"],
                },
            },
            {
                id = "skinning",
                name = ns.L["Skinning"],
                sectionNav = true,
                featureId = "skinningPage",
                navRoutes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 2 } },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 2,
                    subTabName = ns.L["Skinning"],
                },
            },
            {
                id = "autohide",
                name = ns.L["Autohide"],
                sectionNav = true,
                featureId = "autohidePage",
                navRoutes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 } },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = ns.L["Autohide"],
                },
            },
            {
                id = "barHiding",
                name = ns.L["Bar Hiding"],
                featureId = "barHidingPage",
                navRoutes = { { tabIndex = 8, subTabIndex = 2 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = ns.L["Action Bars"],
                    subTabIndex = 2,
                    subTabName = ns.L["Bar Hiding"],
                },
            },
            {
                id = "hudVisibility",
                name = ns.L["HUD Visibility"],
                sectionNav = true,
                featureId = "hudVisibilityPage",
                navRoutes = { { tabIndex = 2, subTabIndex = 2 } },
            },
            {
                id = "frameLevels",
                name = ns.L["Frame Levels"],
                featureId = "frameLevelsPage",
                navRoutes = { { tabIndex = 12, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 12,
                    tabName = ns.L["Frame Levels"],
                    subTabIndex = 0,
                    subTabName = ns.L["Frame Levels"],
                },
            },
            {
                id = "blizzardMover",
                name = ns.L["Blizzard Mover"],
                sectionNav = true,
                featureId = "blizzardMoverPage",
                navRoutes = { { tabIndex = 2, subTabIndex = 12 } },
            },
            {
                id = "themeColors",
                name = ns.L["Theme & Colors"],
                sectionNav = true,
                featureId = "themeColorsPage",
                searchContext = {
                    tileId = "appearance",
                    tabName = SEARCH_TAB_NAME,
                    subPageIndex = 10,
                    subTabName = ns.L["Theme & Colors"],
                },
            },
            {
                id = "borderColoring",
                name = ns.L["Border Coloring"],
                sectionNav = true,
                featureId = "borderColoringPage",
                searchContext = {
                    tileId = "appearance",
                    tabName = SEARCH_TAB_NAME,
                    subPageIndex = 11,
                    subTabName = ns.L["Border Coloring"],
                },
                searchAliases = { ns.L["border"], ns.L["border color"], ns.L["outline"], ns.L["edge color"], ns.L["frame border"] },
            },
        },
        relatedSettings = {
            { label = ns.L["Chat & Tooltips"],    tileId = "chat_tooltips", subPageIndex = 1 },
            { label = ns.L["Minimap & Datatext"], tileId = "minimap",       subPageIndex = 1 },
        },
    })
end
