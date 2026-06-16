--[[
    QUI Options V2 — Minimap & Datatext tile
]]

local ADDON_NAME, ns = ...

local V2Minimap = {}
ns.QUI_MinimapTile = V2Minimap

function V2Minimap.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "minimap",
        icon = "o",
        name = ns.L["Minimap & Datatext"],
        primaryCTA = { label = ns.L["Edit in Layout Mode"], moverKey = "minimap" },
        subPages = {
            {
                id = "minimap",
                name = ns.L["Minimap"],
                sectionNav = true,
                featureId = "minimap",
                navRoutes = {
                    { tabIndex = 9, subTabIndex = 0 },
                    { tabIndex = 9, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = 9,
                    tabName = ns.L["Minimap & Datatext"],
                    subTabIndex = 1,
                    subTabName = ns.L["Minimap"],
                },
            },
            {
                id = "datatext",
                name = ns.L["Datatext"],
                featureId = "datatextPanel",
                navRoutes = { { tabIndex = 9, subTabIndex = 2 } },
                searchContext = {
                    tabIndex = 9,
                    tabName = ns.L["Minimap & Datatext"],
                    subTabIndex = 2,
                    subTabName = ns.L["Datatext"],
                },
            },
        },
    })
end
