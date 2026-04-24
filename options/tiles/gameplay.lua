--[[
    QUI Options V2 — Gameplay tile
    Eight sub-pages aggregated from former General & QoL sub-tabs and
    trackers/raidbuffs/character modules.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2 = {}
ns.QUI_GameplayTile = V2

local function Unavailable(body, label)
    local t = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 20, -20)
    t:SetText(label .. " settings unavailable (module not loaded).")
end

-- Helper: wrap a module builder with an unavailability fallback. The body
-- runs inside SB.WithTileLayout so any U.CreateCollapsible calls inherit the
-- V2 dual-column chrome.
local function delegate(ownerName, fnName, labelIfMissing)
    return function(body)
        local CompatRender = ns.Settings and ns.Settings.CompatRender
        local wrap = (CompatRender and CompatRender.WithTileLayout) or function(fn) return fn() end
        wrap(function()
            local owner = ns[ownerName]
            local fn = owner and owner[fnName]
            if type(fn) == "function" then
                fn(body)
            else
                Unavailable(body, labelIfMissing)
            end
        end)
    end
end


function V2.Register(frame)
    GUI:RegisterV2NavRoute(2, 11, "gameplay", 1)   -- XP Tracker
    GUI:RegisterV2NavRoute(2, 10, "gameplay", 2)   -- Keystones
    GUI:RegisterV2NavRoute(2, 8,  "gameplay", 3)   -- Skyriding
    GUI:RegisterV2NavRoute(2, 3,  "gameplay", 4)   -- Crosshair
    GUI:RegisterV2NavRoute(2, 7,  "gameplay", 5)   -- Character
    GUI:RegisterV2NavRoute(2, 9,  "gameplay", 6)   -- Raid Buffs & Consumables
    GUI:RegisterV2NavRoute(2, 13, "gameplay", 7)   -- Combat
    -- Prey Tracker has no SetSearchContext route registered; leave it
    -- unmapped — the fallback selects the Gameplay tile without a sub-page.

    GUI:AddFeatureTile(frame, {
        id = "gameplay",
        icon = "G",
        name = "Gameplay",
        subPages = {
            { name = "XP Tracker",    buildFunc = Opts.MakeFeatureTabBuilder("xpTracker",
                { tabIndex = 2, tabName = "General & QoL", subTabIndex = 11, subTabName = "XP Tracker" }) },
            { name = "Keystones",     buildFunc = Opts.MakeFeatureTabBuilder("partyKeystones",
                { tabIndex = 2, tabName = "General & QoL", subTabIndex = 10, subTabName = "Party Keystones" }) },
            { name = "Skyriding",     buildFunc = Opts.MakeFeatureTabBuilder("skyriding",
                { tabIndex = 2, tabName = "General & QoL", subTabIndex = 8,  subTabName = "Skyriding" }) },
            { name = "Crosshair",     buildFunc = Opts.MakeFeatureDirectBuilder("crosshair",
                { tabIndex = 2, tabName = "General & QoL", subTabIndex = 3,  subTabName = "Crosshair" },
                delegate("QUI_CrosshairOptions", "BuildCrosshairTab", "Crosshair")) },
            { name = "Character",     buildFunc = Opts.MakeFeatureDirectBuilder("characterPane",
                { tabIndex = 2, tabName = "General & QoL", subTabIndex = 7,  subTabName = "Character Pane" },
                delegate("QUI_CharacterOptions", "BuildCharacterPaneTab", "Character Pane")) },
            { name = "Raid Buffs",    buildFunc = Opts.MakeFeatureStackBuilder({
                "missingRaidBuffs", "consumables",
            }, {
                tabIndex = 2,
                tabName = "General & QoL",
                subTabIndex = 9,
                subTabName = "Raid Buffs & Consumables",
            }) },
            { name = "Combat",        buildFunc = Opts.MakeFeatureStackBuilder({
                "combatTimer", "brezCounter", "atonementCounter",
                "rotationAssistIcon", "focusCastAlert", "petWarning",
                "readyCheck", "mplusTimer", "actionTracker",
            }, {
                tabIndex = 2,
                tabName = "General & QoL",
                subTabIndex = 13,
                subTabName = "Combat",
            }) },
            { name = "Prey Tracker",  noScroll = true, buildFunc = Opts.MakeFeatureDirectBuilder("preyTrackerPage",
                nil, delegate("QUI_PreyTrackerOptions", "CreatePreyTrackerPage", "Prey Tracker")) },
        },
    })
end
