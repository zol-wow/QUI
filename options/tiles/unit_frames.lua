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
        name = "Unit Frames",
        primaryCTA = { label = "Edit in Layout Mode", moverKey = "playerFrame" },
        previewHeight = 220,
        navRoutes = {
            { tabIndex = 5, subTabIndex = 0, subPageIndex = 1 },
        },
        searchContext = {
            tabIndex = 5,
            tabName = "Unit Frames",
            subTabIndex = 0,
            subTabName = "Unit Frames",
        },
        renderOptions = { surface = "full" },
        relatedSettings = {
            { label = "Group Frames", tileId = "group_frames" },
            { label = "Raid Buffs",   tileId = "gameplay", subPageIndex = 6 },
        },
    })
end
