--[[
    QUI Options V2 — Quality of Life tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_QoLTile = V2

local SEARCH_TAB_INDEX = 17
local SEARCH_TAB_NAME = ns.L["Quality of Life"]

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
        name = ns.L["Quality of Life"],
        subPages = {
            SubPage("fpsPreset",        ns.L["FPS Preset"],  "fpsPreset",        1,  ns.L["FPS Preset"]),
            SubPage("combatText",       ns.L["Combat Text"], "combatText",       2,  ns.L["Combat Text"]),
            SubPage("automation",       ns.L["Automation"],  "automation",       3,  ns.L["Automation"]),
            SubPage("popupBlocker",     ns.L["Popups"],      "popupBlocker",     4,  ns.L["Popups"]),
            SubPage("quickSalvage",     ns.L["Salvage"],     "quickSalvage",     5,  ns.L["Salvage"]),
            SubPage("consumables",      ns.L["Consumables"], "consumables",      6,  ns.L["Consumables"]),
            SubPage("targetDistance",   ns.L["Distance"],    "targetDistance",   7,  ns.L["Distance"]),
            SubPage("quiPanel",         ns.L["Panel"],       "quiPanel",         8,  ns.L["Panel"]),
            SubPage("reloadBehavior",   ns.L["Reload"],      "reloadBehavior",   9,  ns.L["Reload"]),
        },
    })
end
