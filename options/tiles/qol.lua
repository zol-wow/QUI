--[[
    QUI Options V2 — Quality of Life tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_QoLTile = V2

local SEARCH_TAB_INDEX = 17
local SEARCH_TAB_NAME = "Quality of Life"

local function SubPage(id, name, featureId, subTabIndex, subTabName)
    local routes = { { tabIndex = SEARCH_TAB_INDEX, subTabIndex = subTabIndex } }
    if subTabIndex == 1 then
        routes[#routes + 1] = { tabIndex = SEARCH_TAB_INDEX, subTabIndex = 0 }
    end

    return {
        id = id,
        name = name,
        featureId = featureId,
        navRoutes = routes,
        searchContext = {
            tabIndex = SEARCH_TAB_INDEX,
            tabName = SEARCH_TAB_NAME,
            subTabIndex = subTabIndex,
            subTabName = subTabName,
        },
    }
end

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "qol",
        icon = "Q",
        name = "Quality of Life",
        subPages = {
            SubPage("fpsPreset",        "FPS Preset",  "fpsPreset",        1,  "FPS Preset"),
            SubPage("combatText",       "Combat Text", "combatText",       2,  "Combat Text"),
            SubPage("automation",       "Automation",  "automation",       3,  "Automation"),
            SubPage("popupBlocker",     "Popups",      "popupBlocker",     4,  "Popups"),
            SubPage("quickSalvage",     "Salvage",     "quickSalvage",     5,  "Salvage"),
            SubPage("consumables",      "Consumables", "consumables",      6,  "Consumables"),
            SubPage("targetDistance",   "Distance",    "targetDistance",   7,  "Distance"),
            SubPage("quiPanel",         "Panel",       "quiPanel",         8,  "Panel"),
            SubPage("reloadBehavior",   "Reload",      "reloadBehavior",   9,  "Reload"),
        },
    })
end
