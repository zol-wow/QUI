local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_UnitFramesTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        featureId = "unitFramesPage",
        id = "unit_frames",
        icon = "U",
        name = ns.L["Unit Frames"],
        primaryCTA = { label = ns.L["Edit in Layout Mode"], moverKey = "playerFrame" },
        previewHeight = 220,
        navRoutes = {
            { tabIndex = 5, subTabIndex = 0, subPageIndex = 1 },
        },
        searchContext = {
            tabIndex = 5,
            tabName = ns.L["Unit Frames"],
            subTabIndex = 0,
            subTabName = ns.L["Unit Frames"],
        },
        renderOptions = { surface = "full" },
        relatedSettings = {
            { label = ns.L["Group Frames"], tileId = "group_frames" },
            { label = ns.L["Raid Buffs"],   tileId = "gameplay", subPageIndex = 5 },
        },
    })
end
