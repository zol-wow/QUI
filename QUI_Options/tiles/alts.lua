--[[
    QUI Options V2 — Alts tile
]]

local ADDON_NAME, ns = ...

local V2Alts = {}
ns.QUI_AltsTile = V2Alts

-- Search-route namespace for this tile. Indices 2-19 are claimed by the
-- other tiles (19 is the Bags tile's — see tiles/bags.lua); 20 is the next
-- free slot. Route-pair uniqueness is guarded by
-- tests/unit/options_tile_navroute_collision_test.lua.
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
