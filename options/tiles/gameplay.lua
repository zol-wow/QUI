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
            },
            {
                id = "keystones",
                name = "Keystones",
                featureId = "partyKeystones",
                navRoutes = { { tabIndex = 2, subTabIndex = 10 } },
            },
            {
                id = "skyriding",
                name = "Skyriding",
                featureId = "skyriding",
                navRoutes = { { tabIndex = 2, subTabIndex = 8 } },
            },
            {
                id = "crosshair",
                name = "Crosshair",
                sectionNav = true,
                featureId = "crosshair",
                navRoutes = { { tabIndex = 2, subTabIndex = 3 } },
            },
            {
                id = "character",
                name = "Character",
                featureId = "characterPane",
                navRoutes = { { tabIndex = 2, subTabIndex = 7 } },
            },
            {
                id = "raidBuffs",
                name = "Raid Buffs",
                sectionNav = true,
                featureIds = { "missingRaidBuffs", "consumables" },
                navRoutes = { { tabIndex = 2, subTabIndex = 9 } },
            },
            {
                id = "combat",
                name = "Combat",
                sectionNav = true,
                featureIds = {
                    "combatTimer", "brezCounter", "atonementCounter",
                    "rotationAssistIcon", "focusCastAlert", "petWarning",
                    "readyCheck", "mplusTimer", "mplusProgress", "actionTracker",
                },
                navRoutes = { { tabIndex = 2, subTabIndex = 13 } },
            },
            {
                id = "preyTracker",
                name = "Prey Tracker",
                sectionNav = true,
                featureId = "preyTrackerPage",
            },
        },
    })
end
