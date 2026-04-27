--[[
    QUI Options V2 — Appearance tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_AppearanceTile = V2

local SEARCH_TAB_INDEX = 10
local SEARCH_TAB_NAME = "Appearance"

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "appearance",
        icon = "S",
        name = "Appearance",
        subPages = {
            {
                id = "uiScale",
                name = "UI Scale",
                featureId = "uiScale",
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 3 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 3,
                    subTabName = "UI Scale",
                },
            },
            {
                id = "fonts",
                name = "Fonts",
                featureId = "defaultFonts",
                navRoutes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 4 } },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 4,
                    subTabName = "Fonts",
                },
            },
            {
                id = "skinning",
                name = "Skinning",
                sectionNav = true,
                featureId = "skinningPage",
                navRoutes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 2 } },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 2,
                    subTabName = "Skinning",
                },
            },
            {
                id = "autohide",
                name = "Autohide",
                sectionNav = true,
                featureId = "autohidePage",
                navRoutes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 } },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = "Autohide",
                },
            },
            {
                id = "barHiding",
                name = "Bar Hiding",
                featureId = "barHidingPage",
                navRoutes = { { tabIndex = 8, subTabIndex = 2 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = "Action Bars",
                    subTabIndex = 2,
                    subTabName = "Bar Hiding",
                },
            },
            {
                id = "hudVisibility",
                name = "HUD Visibility",
                sectionNav = true,
                featureId = "hudVisibilityPage",
                navRoutes = { { tabIndex = 2, subTabIndex = 2 } },
            },
            {
                id = "frameLevels",
                name = "Frame Levels",
                featureId = "frameLevelsPage",
                navRoutes = { { tabIndex = 12, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 12,
                    tabName = "Frame Levels",
                    subTabIndex = 0,
                    subTabName = "Frame Levels",
                },
            },
            {
                id = "blizzardMover",
                name = "Blizzard Mover",
                sectionNav = true,
                featureId = "blizzardMoverPage",
                navRoutes = { { tabIndex = 2, subTabIndex = 12 } },
            },
        },
        relatedSettings = {
            { label = "Chat & Tooltips",    tileId = "chat_tooltips", subPageIndex = 1 },
            { label = "Minimap & Datatext", tileId = "minimap",       subPageIndex = 1 },
        },
    })
end
