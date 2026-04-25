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
        featureId = "helpPage",
        noScroll = false,
        searchContext = {
            tabIndex = 13,
            tabName = "Help",
        },
    })
end
