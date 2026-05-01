--[[
    QUI Options V2 — General tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_GlobalTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "global",
        icon = "*",
        name = "General",
        navRoutes = {
            { tabIndex = 4, subTabIndex = 7, tileId = "cooldown_manager", subPageIndex = 1 },
            { tabIndex = 2, subTabIndex = 1 },
        },
        subPages = {
            {
                id = "profiles",
                name = "Profiles",
                featureId = "profilesPage",
                navRoutes = { { tabIndex = 13, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 13,
                    tabName = "Profiles",
                    subTabIndex = 0,
                    subTabName = "Profiles",
                },
            },
            {
                id = "pinnedGlobals",
                name = "Pinned Globals",
                featureId = "pinnedGlobalsPage",
            },
            {
                id = "modules",
                name = "Modules",
                sectionNav = true,
                featureId = "modulesPage",
            },
            {
                id = "importExport",
                name = "Import / Export",
                sectionNav = true,
                featureId = "importExportPage",
                navRoutes = { { tabIndex = 14, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 14,
                    tabName = "Import / Export",
                    subTabIndex = 0,
                    subTabName = "Import / Export",
                },
            },
            {
                id = "thirdParty",
                name = "Third-party",
                featureId = "thirdPartyAnchoring",
            },
            {
                id = "clickCast",
                name = "Click-Cast",
                sectionNav = true,
                featureId = "clickCastPage",
                navRoutes = {
                    { tabIndex = 7, subTabIndex = 0 },
                    { tabIndex = 7, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = 7,
                    tabName = "Group Frames",
                    subTabIndex = 1,
                    subTabName = "Click-Cast",
                },
            },
        },
    })
end
