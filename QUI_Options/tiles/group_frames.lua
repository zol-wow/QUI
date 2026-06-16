local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_GroupFramesTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        featureId = "groupFramesPage",
        id = "group_frames",
        icon = "G",
        name = ns.L["Group Frames"],
        primaryCTA = { label = ns.L["Edit in Layout Mode"], moverKey = "partyFrames" },
        navRoutes = {
            { tabIndex = 6, subTabIndex = 0, subPageIndex = 1 },
            { tabIndex = 6, subTabIndex = 1, subPageIndex = 1 },
            { tabIndex = 6, subTabIndex = 2, subPageIndex = 1 },
            { tabIndex = 6, subTabIndex = 3, subPageIndex = 1 },
        },
        searchContext = {
            tabIndex = 6,
            tabName = ns.L["Group Frames"],
            subTabIndex = 0,
            subTabName = ns.L["Group Frames"],
        },
        renderOptions = { surface = "full" },
        relatedSettings = {
            { label = ns.L["Unit Frames"], tileId = "unit_frames" },
            { label = ns.L["Raid Buffs"],  tileId = "gameplay", subPageIndex = 5 },
        },
    })
end
