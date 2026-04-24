--[[
    QUI Options V2 — Minimap & Datatext pilot tile
    Phase 1 proof-of-concept for the feature-tile system. Reuses the
    settings renderers from the existing Minimap and Datatext pages —
    this tile is the shell, the underlying content builders are
    unchanged.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2Minimap = {}
ns.QUI_MinimapTile = V2Minimap

function V2Minimap.Register(frame)
    GUI:RegisterV2NavRoute(9, 0, "minimap", 1)   -- Minimap & Datatext tab → Minimap sub-page
    GUI:RegisterV2NavRoute(9, 1, "minimap", 1)   -- Minimap sub-tab
    GUI:RegisterV2NavRoute(9, 2, "minimap", 2)   -- Datatext sub-tab

    GUI:AddFeatureTile(frame, {
        id = "minimap",
        icon = "o",
        name = "Minimap & Datatext",
        primaryCTA = { label = "Edit in Layout Mode", moverKey = "minimap" },
        subPages = {
            {
                name = "Minimap",
                buildFunc = Opts.MakeFeatureTabBuilder("minimap", {
                    tabIndex = 9,
                    tabName = "Minimap & Datatext",
                    subTabIndex = 1,
                    subTabName = "Minimap",
                }, nil, nil, "Minimap"),
            },
            {
                name = "Datatext",
                buildFunc = Opts.MakeFeatureTabBuilder("datatextPanel", {
                    tabIndex = 9,
                    tabName = "Minimap & Datatext",
                    subTabIndex = 2,
                    subTabName = "Datatext",
                }, nil, nil, "Datatext"),
            },
        },
    })
end
