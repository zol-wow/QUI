--[[
    QUI Options V2 — Info Bar tile
]]

local ADDON_NAME, ns = ...

local V2InfoBar = {}
ns.QUI_InfoBarTile = V2InfoBar

function V2InfoBar.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "infobar",
        icon = "i",
        name = "Info Bar",
        subPages = {
            {
                id = "infobar",
                name = "Info Bar",
                sectionNav = true,
                featureId = "infobar",
                navRoutes = {
                    { tabIndex = 18, subTabIndex = 0 },
                    { tabIndex = 18, subTabIndex = 1 },
                },
                searchContext = {
                    tabIndex = 18,
                    tabName = "Info Bar",
                    subTabIndex = 1,
                    subTabName = "Info Bar",
                },
                searchAliases = {
                    "info bar",
                    "infobar",
                    "data bar",
                    "top bar",
                    "bottom bar",
                },
            },
        },
    })
end
