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
        name = "Gameplay",
        subPages = {
            {
                id = "xpTracker",
                name = "XP Tracker",
                featureId = "xpTracker",
                navRoutes = { { tabIndex = 2, subTabIndex = 11 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 11,
                    subTabName = "XP Tracker",
                },
            },
            {
                id = "keystones",
                name = "Keystones",
                featureId = "partyKeystones",
                navRoutes = { { tabIndex = 2, subTabIndex = 10 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 10,
                    subTabName = "Party Keystones",
                },
            },
            {
                id = "skyriding",
                name = "Skyriding",
                featureId = "skyriding",
                navRoutes = { { tabIndex = 2, subTabIndex = 8 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 8,
                    subTabName = "Skyriding",
                },
            },
            {
                id = "crosshair",
                name = "Crosshair",
                featureId = "crosshair",
                navRoutes = { { tabIndex = 2, subTabIndex = 3 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 3,
                    subTabName = "Crosshair",
                },
            },
            {
                id = "character",
                name = "Character",
                featureId = "characterPane",
                navRoutes = { { tabIndex = 2, subTabIndex = 7 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 7,
                    subTabName = "Character Pane",
                },
            },
            {
                id = "raidBuffs",
                name = "Raid Buffs",
                featureIds = { "missingRaidBuffs", "consumables" },
                navRoutes = { { tabIndex = 2, subTabIndex = 9 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 9,
                    subTabName = "Raid Buffs & Consumables",
                },
            },
            {
                id = "combat",
                name = "Combat",
                featureIds = {
                    "combatTimer", "brezCounter", "atonementCounter",
                    "rotationAssistIcon", "focusCastAlert", "petWarning",
                    "readyCheck", "mplusTimer", "actionTracker",
                },
                navRoutes = { { tabIndex = 2, subTabIndex = 13 } },
                searchContext = {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 13,
                    subTabName = "Combat",
                },
            },
            {
                id = "preyTracker",
                name = "Prey Tracker",
                featureId = "preyTrackerPage",
            },
        },
    })
end
