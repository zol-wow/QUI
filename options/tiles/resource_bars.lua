--[[
    QUI Options V2 — Resource Bars tile
    Sub-pages: Primary Resource, Secondary Resource. Split from the
    Cooldown Manager tile so resource-bar configuration lives under
    its own sidebar entry.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2 = {}
ns.QUI_ResourceBarsTile = V2

local SEARCH_TAB_INDEX = 16
local SEARCH_TAB_NAME = "Resource Bars"

function V2.Register(frame)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 0, "resource_bars", 1)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 1, "resource_bars", 1)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 2, "resource_bars", 2)

    GUI:AddFeatureTile(frame, {
        id = "resource_bars",
        icon = "R",
        name = "Resource Bars",
        primaryCTA = { label = "Edit in Layout Mode", moverKey = "primaryPower" },
        preview = {
            height = 120,
            build  = function(pv)
                if _G.QUI_BuildResourceBarPreview then
                    _G.QUI_BuildResourceBarPreview(pv)
                end
            end,
        },
        subPages = {
            {
                name = "Primary Resource",
                buildFunc = Opts.MakeFeatureTabBuilder("primaryPower", {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = "Primary Resource",
                }, nil, nil, "Primary Resource"),
            },
            {
                name = "Secondary Resource",
                buildFunc = Opts.MakeFeatureTabBuilder("secondaryPower", {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 2,
                    subTabName = "Secondary Resource",
                }, nil, nil, "Secondary Resource"),
            },
        },
    })
end
