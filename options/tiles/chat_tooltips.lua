--[[
    QUI Options V2 — Chat & Tooltips tile
    Two sub-pages: Chat and Tooltips.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2 = {}
ns.QUI_ChatTooltipsTile = V2

function V2.Register(frame)
    GUI:RegisterV2NavRoute(2, 5, "chat_tooltips", 1)   -- Chat (sub-page 1)
    GUI:RegisterV2NavRoute(2, 6, "chat_tooltips", 2)   -- Tooltip (sub-page 2)

    GUI:AddFeatureTile(frame, {
        id = "chat_tooltips",
        icon = "T",
        name = "Chat & Tooltips",
        subPages = {
            {
                name = "Chat",
                buildFunc = Opts.MakeFeatureTabBuilder("chatFrame1",
                    { tabIndex = 2, tabName = "General & QoL", subTabIndex = 5, subTabName = "Chat" },
                    nil, nil, "Chat"),
            },
            {
                name = "Tooltips",
                buildFunc = Opts.MakeFeatureTabBuilder("tooltipAnchor",
                    { tabIndex = 2, tabName = "General & QoL", subTabIndex = 6, subTabName = "Tooltip" },
                    nil, nil, "Tooltips"),
            },
        },
    })
end
