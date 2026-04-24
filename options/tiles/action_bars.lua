--[[
    QUI Options V2 — Action Bars tile
    Sub-pages: Action Bars (main/extra bars, paging, keybind text) and
    Buff/Debuff.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Opts = ns.QUI_Options or {}

local V2 = {}
ns.QUI_ActionBarsTile = V2

local function Unavailable(body, label)
    local t = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 20, -20)
    t:SetText(label .. " settings unavailable (module not loaded).")
end

function V2.Register(frame)
    GUI:RegisterV2NavRoute(8, 0, "action_bars", 1)   -- Action Bars (sub-page 1)
    GUI:RegisterV2NavRoute(2, 4, "action_bars", 2)   -- Buff & Debuff (sub-page 2)

    GUI:AddFeatureTile(frame, {
        id = "action_bars",
        icon = "A",
        name = "Action Bars",
        primaryCTA = { label = "Edit in Layout Mode", moverKey = "bar1" },
        preview = {
            height = 110,
            build = function(pv)
                if ns.QUI_ActionBarsOptions and ns.QUI_ActionBarsOptions.BuildActionBarsPreview then
                    ns.QUI_ActionBarsOptions.BuildActionBarsPreview(pv)
                end
            end,
        },
        subPages = {
            {
                name = "General",
                buildFunc = Opts.MakeFeatureDirectBuilder("actionBarsGeneral", {
                        tabIndex = 8,
                        tabName = "Action Bars",
                        subTabIndex = 0,
                        subTabName = "General",
                    }, function(body)
                        if ns.QUI_ActionBarsOptions and ns.QUI_ActionBarsOptions.BuildMasterSettingsTab then
                            ns.QUI_ActionBarsOptions.BuildMasterSettingsTab(body)
                        else
                            Unavailable(body, "Action Bars General")
                        end
                    end),
            },
            {
                name = "Buff/Debuff",
                buildFunc = Opts.MakeFeatureDirectBuilder("actionBarsBuffDebuff", {
                        tabIndex = 2,
                        tabName = "Unit Frames",
                        subTabIndex = 4,
                        subTabName = "Buff & Debuff",
                    }, function(body)
                        if ns.QUI_BuffDebuffOptions and ns.QUI_BuffDebuffOptions.BuildBuffDebuffTab then
                            ns.QUI_BuffDebuffOptions.BuildBuffDebuffTab(body)
                        else
                            Unavailable(body, "Buff/Debuff")
                        end
                    end),
            },
            {
                name = "Per-Bar",
                buildFunc = Opts.MakeFeatureDirectBuilder("actionBarsPerBar", {
                        tabIndex = 8,
                        tabName = "Action Bars",
                        subTabIndex = 3,
                        subTabName = "Per-Bar",
                    }),
            },
        },
    })
end
