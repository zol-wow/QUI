--[[
    QUI Options V2 — Gameplay tile
]]

local ADDON_NAME, ns = ...

local V2 = {}
ns.QUI_GameplayTile = V2

function V2.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then
        return
    end

    Opts.RegisterFeatureTile(frame, {
        id = "gameplay",
        icon = "G",
        name = ns.L["Gameplay"],
        subPages = {
            {
                id = "xpTracker",
                name = ns.L["XP Tracker"],
                featureId = "xpTracker",
                navRoutes = { { tabIndex = 2, subTabIndex = 11 } },
            },
            {
                id = "keystones",
                name = ns.L["Keystones"],
                featureId = "partyKeystones",
                navRoutes = { { tabIndex = 2, subTabIndex = 10 } },
            },
            {
                id = "skyriding",
                name = ns.L["Skyriding"],
                featureId = "skyriding",
                navRoutes = { { tabIndex = 2, subTabIndex = 8 } },
            },
            {
                id = "crosshair",
                name = ns.L["Crosshair"],
                sectionNav = true,
                featureId = "crosshair",
                navRoutes = { { tabIndex = 2, subTabIndex = 3 } },
            },
            {
                id = "raidBuffs",
                name = ns.L["Raid Buffs"],
                sectionNav = true,
                featureIds = { "missingRaidBuffs", "consumables" },
                navRoutes = { { tabIndex = 2, subTabIndex = 9 } },
            },
            {
                id = "combat",
                name = ns.L["Combat"],
                sectionNav = true,
                featureIds = {
                    "combatTimer", "brezCounter", "atonementCounter",
                    "rotationAssistIcon", "focusCastAlert", "petWarning",
                    "readyCheck", "mplusTimer", "mplusProgress", "actionTracker",
                },
                navRoutes = { { tabIndex = 2, subTabIndex = 13 } },
            },
            {
                id = "damageMeterNative",
                name = ns.L["Damage Meter"],
                sectionNav = true,
                featureId = "damageMeterNativePage",
                searchContext = {
                    tileId = "gameplay",
                    tabName = ns.L["Gameplay"],
                    subPageIndex = 7,
                    subTabName = ns.L["Damage Meter"],
                },
            },
            {
                id = "preyTracker",
                name = ns.L["Prey Tracker"],
                sectionNav = true,
                featureId = "preyTrackerPage",
            },
        },
    })
end
