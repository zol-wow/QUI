--[[
    QUI Options V2 — Chat & Tooltips tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_ChatTooltipsTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "chat_tooltips",
        icon = "T",
        name = "Chat & Tooltips",
        subPages = {
            {
                id = "chat",
                name = "Chat",
                featureId = "chatFrame1",
                navRoutes = { { tabIndex = 2, subTabIndex = 5 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 5,
                    subTabName = "Chat",
                },
            },
            {
                id = "tooltips",
                name = "Tooltips",
                featureId = "tooltipAnchor",
                navRoutes = { { tabIndex = 2, subTabIndex = 6 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 6,
                    subTabName = "Tooltip",
                },
            },
        },
    })
end
