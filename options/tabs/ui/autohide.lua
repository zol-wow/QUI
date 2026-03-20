--[[
    QUI Options - Autohide Tab
    BuildAutohideTab for Autohide & Skinning page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildAutohideTab(tabContent)
    local PAD = 10
    local FORM_ROW = 32
    local Helpers = ns.Helpers
    local P = Helpers.PlaceRow
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 7, tabName = "Skinning & Autohide", subTabIndex = 1, subTabName = "Autohide"})

    local function RefreshUIHider()
        if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end
    end

    if not db then return end
    if not db.uiHider then db.uiHider = {} end

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

    -- Objective Tracker
    if not db.uiHider.hideObjectiveTrackerInstanceTypes then
        db.uiHider.hideObjectiveTrackerInstanceTypes = {
            mythicPlus = false, mythicDungeon = false, normalDungeon = false,
            heroicDungeon = false, followerDungeon = false, raid = false, pvp = false, arena = false,
        }
    end
    CreateCollapsible("Objective Tracker", 9 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Always", "hideObjectiveTrackerAlways", db.uiHider, RefreshUIHider), body, sy)
        for _, it in ipairs({
            {key = "mythicPlus", label = "Hide in Mythic+"}, {key = "mythicDungeon", label = "Hide in Mythic Dungeons"},
            {key = "heroicDungeon", label = "Hide in Heroic Dungeons"}, {key = "normalDungeon", label = "Hide in Normal Dungeons"},
            {key = "followerDungeon", label = "Hide in Follower Dungeons"}, {key = "raid", label = "Hide in Raids"},
            {key = "pvp", label = "Hide in Battlegrounds"}, {key = "arena", label = "Hide in Arenas"},
        }) do
            sy = P(GUI:CreateFormCheckbox(body, it.label, it.key, db.uiHider.hideObjectiveTrackerInstanceTypes, RefreshUIHider), body, sy)
        end
    end)

    -- Frames & Buttons
    CreateCollapsible("Frames & Buttons", 6 * FORM_ROW + 8, function(body)
        local sy = -4
        for _, opt in ipairs({
            {key = "hideRaidFrameManager", label = "Hide Compact Raid Frame Manager"},
            {key = "hideBuffCollapseButton", label = "Hide Buff Frame Collapse Button"},
            {key = "hideTalkingHead", label = "Hide Talking Head Frame"},
            {key = "muteTalkingHead", label = "Mute Talking Head Voice"},
            {key = "hideWorldMapBlackout", label = "Hide World Map Blackout"},
            {key = "hidePlayerFrameInParty", label = "Hide Player Frame in Party/Raid"},
        }) do
            sy = P(GUI:CreateFormCheckbox(body, opt.label, opt.key, db.uiHider, RefreshUIHider), body, sy)
        end
    end)

    -- Nameplates
    CreateCollapsible("Nameplates", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Friendly Player Nameplates", "hideFriendlyPlayerNameplates", db.uiHider, RefreshUIHider), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Friendly NPC Nameplates", "hideFriendlyNPCNameplates", db.uiHider, RefreshUIHider), body, sy)
    end)

    -- Status Bars
    CreateCollapsible("Status Bars", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Experience Bar (XP)", "hideExperienceBar", db.uiHider, RefreshUIHider), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Reputation Bar", "hideReputationBar", db.uiHider, RefreshUIHider), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Data Bars in Vehicle", "hideDataBarsInVehicle", db.uiHider, RefreshUIHider), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Data Bars in Pet Battle", "hideDataBarsInPetBattle", db.uiHider, RefreshUIHider), body, sy)
    end)

    -- Buff / Debuff Frames
    if not db.buffBorders then db.buffBorders = {} end
    local function RefreshBuffBorders()
        if _G.QUI_RefreshBuffBorders then _G.QUI_RefreshBuffBorders() end
    end
    CreateCollapsible("Buff / Debuff Frames", 5 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Buff Frame", "hideBuffFrame", db.buffBorders, RefreshBuffBorders), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Debuff Frame", "hideDebuffFrame", db.buffBorders, RefreshBuffBorders), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Fade Buffs (Show on Mouseover)", "fadeBuffFrame", db.buffBorders, RefreshBuffBorders), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Fade Debuffs (Show on Mouseover)", "fadeDebuffFrame", db.buffBorders, RefreshBuffBorders), body, sy)
        P(GUI:CreateFormSlider(body, "Fade Out Opacity", 0, 1, 0.05, "fadeOutAlpha", db.buffBorders, RefreshBuffBorders), body, sy)
    end)

    -- Combat & Messages
    CreateCollapsible("Combat & Messages", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Error Messages (Red Text)", "hideErrorMessages", db.uiHider, RefreshUIHider), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Info Messages (i.e. Quest Prog)", "hideInfoMessages", db.uiHider, RefreshUIHider), body, sy)
    end)

    relayout()
end

-- Export
ns.QUI_AutohideOptions = {
    BuildAutohideTab = BuildAutohideTab
}
