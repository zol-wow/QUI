local ADDON_NAME, ns = ...

local LegacyQoLSettings = ns.QUI_LegacyQoLSettings
if not LegacyQoLSettings or type(LegacyQoLSettings.RegisterGeneralSectionFeature) ~= "function" then
    return
end

local function GetGeneralDB(profile)
    return profile and profile.general
end

local featureSpecs = {
    {
        id = "fpsPreset",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 1 },
        sectionTitle = "Quazii Recommended FPS Settings",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 1,
            subTabName = "FPS Preset",
        },
    },
    {
        id = "combatText",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 2 },
        sectionTitle = "Combat Status Text Indicator",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 2,
            subTabName = "Combat Text",
        },
    },
    {
        id = "automation",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 3 },
        sectionTitle = "Automation",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 3,
            subTabName = "Automation",
        },
    },
    {
        id = "popupBlocker",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 4 },
        sectionTitle = "Popup & Toast Blocker",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 4,
            subTabName = "Popups",
        },
    },
    {
        id = "quickSalvage",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 5 },
        sectionTitle = "Quick Salvage",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 5,
            subTabName = "Salvage",
        },
    },
    {
        id = "consumableMacros",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 7 },
        sectionTitle = "Consumable Macros",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 7,
            subTabName = "Macros",
        },
    },
    {
        id = "targetDistance",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 8 },
        sectionTitle = "Target Distance Bracket Display",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 8,
            subTabName = "Distance",
        },
    },
    {
        id = "quiPanel",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 9 },
        sectionTitle = "QUI Panel Settings",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 9,
            subTabName = "Panel",
        },
    },
    {
        id = "reloadBehavior",
        category = "qol",
        nav = { tileId = "qol", subPageIndex = 10 },
        sectionTitle = "Reload Behavior",
        searchContext = {
            tabIndex = 17,
            tabName = "Quality of Life",
            subTabIndex = 10,
            subTabName = "Reload",
        },
    },
    {
        id = "uiScale",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 1 },
        sectionTitle = "UI Scale",
        searchContext = {
            tabIndex = 10,
            tabName = "Appearance",
            subTabIndex = 3,
            subTabName = "UI Scale",
        },
    },
    {
        id = "defaultFonts",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 2 },
        sectionTitle = "Default Font Settings",
        searchContext = {
            tabIndex = 10,
            tabName = "Appearance",
            subTabIndex = 4,
            subTabName = "Fonts",
        },
    },
}

for _, spec in ipairs(featureSpecs) do
    spec.getDB = GetGeneralDB
    LegacyQoLSettings.RegisterGeneralSectionFeature(spec)
end
