--[[
    QUI Options V2 — Help tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_HelpTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "help",
        icon = "?",
        name = "Help",
        isBottomItem = true,
        subPages = {
            {
                id = "help",
                name = "Help",
                featureId = "helpPage",
                sectionNav = true,
                searchContext = { tabIndex = 13, tabName = "Help" },
            },
            {
                id = "troubleshooting",
                name = "Tools",
                featureId = "troubleshootingPage",
                searchContext = {
                    tabIndex   = 13,
                    tabName    = "Help",
                    subTabName = "Tools",
                },
            },
        },
    })
end
