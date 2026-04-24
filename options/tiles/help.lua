--[[
    QUI Options V2 — Help tile
    Renders the Feature Guides page at the bottom of the sidebar. The
    Welcome page is a separate top-of-sidebar tile registered in
    options/init.lua.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI

local V2 = {}
ns.QUI_HelpTile = V2

function V2.Register(frame)
    GUI:AddFeatureTile(frame, {
        id = "help",
        icon = "?",
        name = "Help",
        isBottomItem = true, -- render at bottom of the sidebar
        noScroll = true,     -- CreateHelpPage self-wraps
        buildFunc = function(contentArea)
            if ns.QUI_HelpOptions and ns.QUI_HelpOptions.CreateHelpPage then
                ns.QUI_HelpOptions.CreateHelpPage(contentArea)
            else
                local t = contentArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                t:SetPoint("TOPLEFT", 20, -20)
                t:SetText("Help content unavailable (module not loaded).")
            end
        end,
    })
end
