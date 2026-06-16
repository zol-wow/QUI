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
        name = ns.L["Help"],
        isBottomItem = true,
        subPages = {
            {
                id = "help",
                name = ns.L["Help"],
                featureId = "helpPage",
                sectionNav = true,
                searchContext = { tabIndex = 13, tabName = ns.L["Help"] },
                searchAliases = {
                    ns.L["help"],
                    ns.L["documentation"],
                    ns.L["manual"],
                    ns.L["guide"],
                    ns.L["how to"],
                    ns.L["instructions"],
                },
            },
            {
                id = "troubleshooting",
                name = ns.L["Tools"],
                featureId = "troubleshootingPage",
                searchContext = {
                    tabIndex   = 13,
                    tabName    = ns.L["Help"],
                    subTabName = ns.L["Tools"],
                },
                searchAliases = {
                    ns.L["troubleshoot"],
                    ns.L["troubleshooting"],
                    ns.L["diagnostics"],
                    ns.L["debug"],
                    ns.L["report bug"],
                    ns.L["tools"],
                    ns.L["console"],
                },
            },
        },
    })
end
