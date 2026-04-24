--[[
    QUI Options V2 — Appearance tile
    Sub-pages: UI Scale, Fonts, Skinning, Autohide, and HUD Visibility
    (visibility rules per spec contract — rule-based, stays in /qui
    rather than moving to Layout Mode).
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2 = {}
ns.QUI_AppearanceTile = V2

local SEARCH_TAB_INDEX = 10
local SEARCH_TAB_NAME = "Appearance"

local function Unavailable(body, label)
    local t = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 20, -20)
    t:SetText(label .. " settings unavailable (module not loaded).")
end

local function BuildLegacyQoLSection(body, displayName, sectionTitle, searchContext)
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

local function BuildQoLSection(displayName, featureId, sectionTitle, searchContext)
    return Opts.MakeFeatureTabBuilder(
        featureId,
        searchContext,
        function(body)
            BuildLegacyQoLSection(body, displayName, sectionTitle, searchContext)
        end,
        nil,
        displayName
    )
end

local function BuildFeaturePage(displayName, featureId, searchContext, fallback)
    return Opts.MakeFeatureDirectBuilder(featureId, searchContext, fallback, nil, displayName)
end

function V2.Register(frame)
    -- Appearance settings are exposed as top-level sub-pages here. Legacy
    -- sub-tab coordinates and tile-native search routes map through for
    -- search/jump-to-setting.
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 0, "appearance", 1)   -- tile-level → UI Scale
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 1, "appearance", 4)   -- Autohide → sub-page 4
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 2, "appearance", 3)   -- Skinning → sub-page 3
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 3, "appearance", 1)   -- UI Scale → sub-page 1
    GUI:RegisterV2NavRoute(SEARCH_TAB_INDEX, 4, "appearance", 2)   -- Fonts → sub-page 2
    GUI:RegisterV2NavRoute(8,  2, "appearance", 5)                 -- Mouseover Hide → Bar Hiding
    GUI:RegisterV2NavRoute(2,  2, "appearance", 6)                 -- HUD Visibility
    GUI:RegisterV2NavRoute(12, 0, "appearance", 7)                 -- Frame Levels
    GUI:RegisterV2NavRoute(2, 12, "appearance", 8)                 -- Blizzard Mover

    GUI:AddFeatureTile(frame, {
        id = "appearance",
        icon = "S",
        name = "Appearance",
        subPages = {
            {
                name = "UI Scale",
                buildFunc = BuildQoLSection("UI Scale", "uiScale", "UI Scale", {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 3,
                    subTabName = "UI Scale",
                }),
            },
            {
                name = "Fonts",
                buildFunc = BuildQoLSection("Fonts", "defaultFonts", "Default Font Settings", {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 4,
                    subTabName = "Fonts",
                }),
            },
            {
                name = "Skinning",
                buildFunc = BuildFeaturePage("Skinning", "skinningPage", {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 2,
                    subTabName = "Skinning",
                }, function(body)
                    local CompatRender = ns.Settings and ns.Settings.CompatRender
                    local wrap = (CompatRender and CompatRender.WithTileLayout) or function(fn) return fn() end
                    wrap(function()
                        if ns.QUI_SkinningOptions and ns.QUI_SkinningOptions.BuildSkinningTab then
                            ns.QUI_SkinningOptions.BuildSkinningTab(body)
                        else
                            Unavailable(body, "Skinning")
                        end
                    end)
                end),
            },
            {
                name = "Autohide",
                buildFunc = BuildFeaturePage("Autohide", "autohidePage", {
                    tabIndex = SEARCH_TAB_INDEX,
                    tabName = SEARCH_TAB_NAME,
                    subTabIndex = 1,
                    subTabName = "Autohide",
                }, function(body)
                    local CompatRender = ns.Settings and ns.Settings.CompatRender
                    local wrap = (CompatRender and CompatRender.WithTileLayout) or function(fn) return fn() end
                    wrap(function()
                        if ns.QUI_AutohideOptions and ns.QUI_AutohideOptions.BuildAutohideTab then
                            ns.QUI_AutohideOptions.BuildAutohideTab(body)
                        else
                            Unavailable(body, "Autohide")
                        end
                    end)
                end),
            },
            {
                name = "Bar Hiding",
                buildFunc = BuildFeaturePage("Bar Hiding", "barHidingPage", {
                    tabIndex = 8,
                    tabName = "Action Bars",
                    subTabIndex = 2,
                    subTabName = "Bar Hiding",
                }, function(body)
                    local CompatRender = ns.Settings and ns.Settings.CompatRender
                    local wrap = (CompatRender and CompatRender.WithTileLayout) or function(fn) return fn() end
                    wrap(function()
                        if ns.QUI_ActionBarsOptions and ns.QUI_ActionBarsOptions.BuildMouseoverHideTab then
                            ns.QUI_ActionBarsOptions.BuildMouseoverHideTab(body)
                        else
                            Unavailable(body, "Bar Hiding")
                        end
                    end)
                end),
            },
            {
                name = "HUD Visibility",
                buildFunc = BuildFeaturePage("HUD Visibility", "hudVisibilityPage", {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 2,
                    subTabName = "HUD Visibility",
                }, function(body)
                    local CompatRender = ns.Settings and ns.Settings.CompatRender
                    local wrap = (CompatRender and CompatRender.WithTileLayout) or function(fn) return fn() end
                    wrap(function()
                        if ns.QUI_HUDVisibilityOptions and ns.QUI_HUDVisibilityOptions.BuildHUDVisibilityTab then
                            ns.QUI_HUDVisibilityOptions.BuildHUDVisibilityTab(body)
                        else
                            Unavailable(body, "HUD Visibility")
                        end
                    end)
                end),
            },
            {
                name = "Frame Levels",
                noScroll = true,
                buildFunc = BuildFeaturePage("Frame Levels", "frameLevelsPage", {
                    tabIndex = 12,
                    tabName = "Frame Levels",
                    subTabIndex = 0,
                    subTabName = "Frame Levels",
                }, function(body)
                    local CompatRender = ns.Settings and ns.Settings.CompatRender
                    local wrap = (CompatRender and CompatRender.WithTileLayout) or function(fn) return fn() end
                    wrap(function()
                        if ns.QUI_HUDLayeringOptions and ns.QUI_HUDLayeringOptions.CreateHUDLayeringPage then
                            ns.QUI_HUDLayeringOptions.CreateHUDLayeringPage(body)
                        else
                            Unavailable(body, "Frame Levels")
                        end
                    end)
                end),
            },
            {
                name = "Blizzard Mover",
                buildFunc = BuildFeaturePage("Blizzard Mover", "blizzardMoverPage", {
                    tabIndex = 2,
                    tabName = "General & QoL",
                    subTabIndex = 12,
                    subTabName = "Blizzard Mover",
                }, function(body)
                    if ns.QUI_BlizzardMoverOptions and ns.QUI_BlizzardMoverOptions.BuildBlizzardMoverTab then
                        ns.QUI_BlizzardMoverOptions.BuildBlizzardMoverTab(body)
                    else
                        Unavailable(body, "Blizzard Mover")
                    end
                end),
            },
        },
        relatedSettings = {
            { label = "Chat & Tooltips",    tileId = "chat_tooltips", subPageIndex = 1 },
            { label = "Minimap & Datatext", tileId = "minimap",       subPageIndex = 1 },
        },
    })
end
