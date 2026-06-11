--[[
    QUI Options V2 — Bags tile
]]

local ADDON_NAME, ns = ...

local V2Bags = {}
ns.QUI_BagsTile = V2Bags

-- Search-route namespace for this tile. Indices 2-18 are claimed by the
-- other tiles (18 is the Info Bar's — see tiles/infobar.lua); 19 is the
-- next free slot. Route-pair uniqueness is guarded by
-- tests/unit/options_tile_navroute_collision_test.lua.
local SEARCH_TAB_INDEX = 19
local SEARCH_TAB_NAME = "Bags"

function V2Bags.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "bags",
        icon = "B",
        name = "Bags",
        subPages = {
            {
                id = "bags",
                name = "Bags",
                sectionNav = true,
                featureId = "bags",
                navRoutes = {
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 },
                    { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = "Bags",
                },
            },
        },
    })
end
