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
        name = ns.L["Chat & Tooltips"],
        subPages = {
            {
                id = "chat",
                name = ns.L["Chat"],
                sectionNav = true,
                featureId = "chatFrame1",
                navRoutes = { { tabIndex = 2, subTabIndex = 5 } },
            },
            {
                id = "filters",
                name = ns.L["Filters"],
                sectionNav = true,
                featureId = "chatFrame1Filters",
            },
            {
                id = "buttonBar",
                name = ns.L["Button Bar"],
                sectionNav = true,
                featureId = "chatFrame1ButtonBar",
            },
            {
                id = "alerts",
                name = ns.L["Alerts"],
                sectionNav = true,
                featureId = "chatFrame1Alerts",
            },
            {
                id = "history",
                name = ns.L["History"],
                sectionNav = true,
                featureId = "chatFrame1History",
            },
            {
                id = "tooltips",
                name = ns.L["Tooltips"],
                sectionNav = true,
                featureId = "tooltipAnchor",
                navRoutes = { { tabIndex = 2, subTabIndex = 6 } },
            },
        },
    })
end
