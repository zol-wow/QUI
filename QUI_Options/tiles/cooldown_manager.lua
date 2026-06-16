local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_CooldownManagerTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        featureId = "cooldownManagerContainersPage",
        id = "cooldown_manager",
        icon = "C",
        name = ns.L["Cooldown Manager"],
        primaryCTA = { label = ns.L["Edit in Layout Mode"], moverKey = "cdmEssential" },
        previewHeight = 230,
        navRoutes = {
            { tabIndex = 4, subTabIndex = 0, subPageIndex = 1 },
            { tabIndex = 4, subTabIndex = 6, subPageIndex = 1 },
            { tabIndex = 4, subTabIndex = 8, subPageIndex = 1 },
        },
        searchContext = {
            tabIndex = 4,
            tabName = ns.L["Cooldown Manager"],
            subTabIndex = 0,
            subTabName = ns.L["Containers"],
        },
        renderOptions = { surface = "full" },
        relatedSettings = {
            { label = ns.L["Buff/Debuff"],   tileId = "action_bars", subPageIndex = 2 },
            { label = ns.L["Raid Buffs"],    tileId = "gameplay", subPageIndex = 5 },
            { label = ns.L["Resource Bars"], tileId = "resource_bars", subPageIndex = 1 },
        },
    })
end
