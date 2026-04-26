--[[
    QUI Options V2 — Resource Bars tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_ResourceBarsTile = V2

local SEARCH_TAB_INDEX = 16
local SEARCH_TAB_NAME = "Resource Bars"

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "resource_bars",
        icon = "R",
        name = "Resource Bars",
        primaryCTA = { label = "Edit in Layout Mode", moverKey = "primaryPower" },
        preview = {
            height = 120,
            build = function(pv)
                if _G.QUI_BuildResourceBarPreview then
                    _G.QUI_BuildResourceBarPreview(pv)
                end
            end,
        },
        subPages = {
            {
                id = "primary",
                name = "Primary Resource",
                featureId = "primaryPower",
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = "Primary Resource",
                },
            },
            {
                id = "secondary",
                name = "Secondary Resource",
                featureId = "secondaryPower",
                navRoutes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 2 } },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 2,
                    subTabName = "Secondary Resource",
                },
            },
        },
    })
end
