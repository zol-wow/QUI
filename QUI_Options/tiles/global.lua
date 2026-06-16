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
        name = ns.L["General"],
        navRoutes = {
            { tabIndex = 4, subTabIndex = 7, tileId = "cooldown_manager", subPageIndex = 1 },
            { tabIndex = 2, subTabIndex = 1 },
        },
        subPages = {
            {
                id = "profiles",
                name = ns.L["Profiles"],
                featureId = "profilesPage",
                navRoutes = { { tabIndex = 13, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 13,
                    tabName = ns.L["Profiles"],
                    subTabIndex = 0,
                    subTabName = ns.L["Profiles"],
                },
            },
            {
                id = "pinnedGlobals",
                name = ns.L["Pinned Globals"],
                featureId = "pinnedGlobalsPage",
                searchAliases = {
                    ns.L["pinned"],
                    ns.L["pinned settings"],
                    ns.L["favorites"],
                    ns.L["shortcuts"],
                    ns.L["quick access"],
                },
            },
            {
                id = "modules",
                name = ns.L["Feature Toggles"],
                sectionNav = true,
                featureId = "modulesPage",
                searchAliases = {
                    ns.L["modules"],
                    ns.L["module list"],
                    ns.L["disable feature"],
                    ns.L["enable feature"],
                    ns.L["feature toggle"],
                    ns.L["turn off"],
                    ns.L["turn on"],
                },
            },
            {
                id = "importExport",
                name = ns.L["Import / Export"],
                sectionNav = true,
                featureId = "importExportPage",
                navRoutes = { { tabIndex = 14, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 14,
                    tabName = ns.L["Import / Export"],
                    subTabIndex = 0,
                    subTabName = ns.L["Import / Export"],
                },
                searchAliases = {
                    ns.L["import profile"],
                    ns.L["export profile"],
                    ns.L["backup profile"],
                    ns.L["share settings"],
                    ns.L["profile string"],
                    ns.L["profile import"],
                },
            },
            {
                id = "thirdParty",
                name = ns.L["Third-party"],
                featureId = "thirdPartyAnchoring",
            },
            {
                id = "clickCast",
                name = ns.L["Click-Cast"],
                sectionNav = true,
                featureId = "clickCastPage",
                navRoutes = {
                    { tabIndex = 7, subTabIndex = 0 },
                    { tabIndex = 7, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = 7,
                    tabName = ns.L["Group Frames"],
                    subTabIndex = 1,
                    subTabName = ns.L["Click-Cast"],
                },
            },
        },
    })
end
