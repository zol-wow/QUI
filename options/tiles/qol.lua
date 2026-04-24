--[[
    QUI Options V2 — Quality of Life tile
    Ten sub-pages, one per QoL section. Prefer feature-id rendering for
    migrated sections, with the old single-section BuildGeneralTab slice as
    a fallback until the remaining bridges can be removed.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2 = {}
ns.QUI_QoLTile = V2

local SEARCH_TAB_INDEX = 17
local SEARCH_TAB_NAME = "Quality of Life"

local function Unavailable(body, label)
    local t = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 20, -20)
    t:SetText(label .. " settings unavailable (module not loaded).")
end

local function BuildLegacySection(body, displayName, sectionTitle, searchContext)
    local CompatRender = ns.Settings and ns.Settings.CompatRender
    local Opts = ns.QUI_QoLOptions
    if not CompatRender or not CompatRender.WithOnlySections or not Opts or not Opts.BuildGeneralTab then
        Unavailable(body, displayName)
        return
    end

    CompatRender.WithOnlySections({ [sectionTitle] = true }, function()
        Opts.BuildGeneralTab(body, searchContext)
    end)
end

local function Section(displayName, featureId, sectionTitle, searchContext)
    return {
        name = displayName,
        buildFunc = Opts.MakeFeatureTabBuilder(
            featureId,
            searchContext,
            function(body)
                BuildLegacySection(body, displayName, sectionTitle, searchContext)
            end,
            nil,
            displayName
        ),
    }
end

function V2.Register(frame)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 0, "qol", 1)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 1, "qol", 1)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 2, "qol", 2)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 3, "qol", 3)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 4, "qol", 4)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 5, "qol", 5)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 6, "qol", 6)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 7, "qol", 7)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 8, "qol", 8)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 9, "qol", 9)
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 10, "qol", 10)

    GUI:AddFeatureTile(frame, {
        id = "qol",
        icon = "Q",
        name = "Quality of Life",
        subPages = {
            Section("FPS Preset",  "fpsPreset", "Quazii Recommended FPS Settings", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 1,
                subTabName = "FPS Preset",
            }),
            Section("Combat Text", "combatText", "Combat Status Text Indicator", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 2,
                subTabName = "Combat Text",
            }),
            Section("Automation",  "automation", "Automation", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 3,
                subTabName = "Automation",
            }),
            Section("Popups",      "popupBlocker", "Popup & Toast Blocker", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 4,
                subTabName = "Popups",
            }),
            Section("Salvage",     "quickSalvage", "Quick Salvage", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 5,
                subTabName = "Salvage",
            }),
            Section("Consumables", "consumables", "Consumable Check", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 6,
                subTabName = "Consumables",
            }),
            Section("Macros",      "consumableMacros", "Consumable Macros", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 7,
                subTabName = "Macros",
            }),
            Section("Distance",    "targetDistance", "Target Distance Bracket Display", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 8,
                subTabName = "Distance",
            }),
            Section("Panel",       "quiPanel", "QUI Panel Settings", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 9,
                subTabName = "Panel",
            }),
            Section("Reload",      "reloadBehavior", "Reload Behavior", {
                tabIndex = SEARCH_TAB_INDEX,
                tabName = SEARCH_TAB_NAME,
                subTabIndex = 10,
                subTabName = "Reload",
            }),
        },
    })
end
