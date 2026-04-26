--[[
    QUI Options V2 — Action Bars tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_ActionBarsTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "action_bars",
        icon = "A",
        name = "Action Bars",
        primaryCTA = { label = "Edit in Layout Mode", moverKey = "bar1" },
        preview = {
            height = 110,
            build = function(pv)
                if ns.QUI_ActionBarsOptions and ns.QUI_ActionBarsOptions.BuildActionBarsPreview then
                    ns.QUI_ActionBarsOptions.BuildActionBarsPreview(pv)
                end
            end,
        },
        subPages = {
            {
                id = "general",
                name = "General",
                featureId = "actionBarsGeneral",
                navRoutes = { { tabIndex = 8, subTabIndex = 0 } },
                searchContext = {
                    tabIndex = 8,
                    tabName = "Action Bars",
                    subTabIndex = 0,
                    subTabName = "General",
                },
            },
            {
                id = "buffDebuff",
                name = "Buff/Debuff",
                featureId = "actionBarsBuffDebuff",
                navRoutes = { { tabIndex = 2, subTabIndex = 4 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "Unit Frames",
                    subTabIndex = 4,
                    subTabName = "Buff & Debuff",
                },
            },
            {
                id = "perBar",
                name = "Per-Bar",
                featureId = "actionBarsPerBar",
                searchContext = {
                    tabIndex = 8,
                    tabName = "Action Bars",
                    subTabIndex = 3,
                    subTabName = "Per-Bar",
                },
            },
        },
    })
end
