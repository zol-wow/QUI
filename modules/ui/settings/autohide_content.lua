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

    GUI:SetSearchContext({tabIndex = 10, tabName = "Skinning & Autohide", subTabIndex = 1, subTabName = "Autohide"})

    local function RefreshUIHider()
        if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end
    end

    if not db then return end
    if not db.uiHider then db.uiHider = {} end

    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(tabContent, PAD)

    -- Objective Tracker
    if not db.uiHider.hideObjectiveTrackerInstanceTypes then
        db.uiHider.hideObjectiveTrackerInstanceTypes = {
            mythicPlus = false, mythicDungeon = false, normalDungeon = false,
            heroicDungeon = false, followerDungeon = false, raid = false, pvp = false, arena = false,
        }
    end
    CreateCollapsible("Objective Tracker", 9 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Always", "hideObjectiveTrackerAlways", db.uiHider, RefreshUIHider,
            { description = "Hide the quest and objective tracker everywhere, ignoring the per-instance toggles below." }), body, sy)
        local instanceDescriptions = {
            mythicPlus      = "Hide the objective tracker while you are running a Mythic+ keystone.",
            mythicDungeon   = "Hide the objective tracker while you are in a Mythic difficulty dungeon.",
            heroicDungeon   = "Hide the objective tracker while you are in a Heroic difficulty dungeon.",
            normalDungeon   = "Hide the objective tracker while you are in a Normal difficulty dungeon.",
            followerDungeon = "Hide the objective tracker while you are in a Follower dungeon.",
            raid            = "Hide the objective tracker while you are inside a raid instance.",
            pvp             = "Hide the objective tracker while you are in a Battleground.",
            arena           = "Hide the objective tracker while you are in an Arena match.",
        }
        for _, it in ipairs({
            {key = "mythicPlus", label = "Hide in Mythic+"}, {key = "mythicDungeon", label = "Hide in Mythic Dungeons"},
            {key = "heroicDungeon", label = "Hide in Heroic Dungeons"}, {key = "normalDungeon", label = "Hide in Normal Dungeons"},
            {key = "followerDungeon", label = "Hide in Follower Dungeons"}, {key = "raid", label = "Hide in Raids"},
            {key = "pvp", label = "Hide in Battlegrounds"}, {key = "arena", label = "Hide in Arenas"},
        }) do
            sy = P(GUI:CreateFormCheckbox(body, it.label, it.key, db.uiHider.hideObjectiveTrackerInstanceTypes, RefreshUIHider,
                { description = instanceDescriptions[it.key] }), body, sy)
        end
    end)

    -- Frames & Buttons
    local frameDescriptions = {
        hideRaidFrameManager   = "Hide the compact raid frame manager widget that lets you pick built-in raid profiles.",
        hideBuffCollapseButton = "Hide the small arrow button above the buff frame that collapses your buffs into a dropdown.",
        hideTalkingHead        = "Hide the talking head frame used by cinematic NPC dialogue.",
        muteTalkingHead        = "Silence the voice audio that plays with talking head events, without hiding the frame itself.",
        hideWorldMapBlackout   = "Remove the dark overlay drawn behind the world map so the game world stays visible while it's open.",
        hidePlayerFrameInParty = "Hide the standalone player unit frame whenever you are in a group, since the raid frames already show you.",
    }
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
            sy = P(GUI:CreateFormCheckbox(body, opt.label, opt.key, db.uiHider, RefreshUIHider,
                { description = frameDescriptions[opt.key] }), body, sy)
        end
    end)

    -- Nameplates
    CreateCollapsible("Nameplates", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Friendly Player Nameplates", "hideFriendlyPlayerNameplates", db.uiHider, RefreshUIHider,
            { description = "Hide nameplates above friendly player characters to reduce visual clutter." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Friendly NPC Nameplates", "hideFriendlyNPCNameplates", db.uiHider, RefreshUIHider,
            { description = "Hide nameplates above friendly NPCs such as quest givers and town residents." }), body, sy)
    end)

    -- Status Bars
    CreateCollapsible("Status Bars", 4 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Experience Bar (XP)", "hideExperienceBar", db.uiHider, RefreshUIHider,
            { description = "Hide the experience bar shown along the bottom of the screen while leveling." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Reputation Bar", "hideReputationBar", db.uiHider, RefreshUIHider,
            { description = "Hide the reputation tracking bar shown above the main action bar." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Data Bars in Vehicle", "hideDataBarsInVehicle", db.uiHider, RefreshUIHider,
            { description = "Hide the experience and reputation bars while you are riding a vehicle." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Data Bars in Pet Battle", "hideDataBarsInPetBattle", db.uiHider, RefreshUIHider,
            { description = "Hide the experience and reputation bars while you are in a pet battle." }), body, sy)
    end)

    -- Buff / Debuff Frames
    if not db.buffBorders then db.buffBorders = {} end
    local function RefreshBuffBorders()
        if _G.QUI_RefreshBuffBorders then _G.QUI_RefreshBuffBorders() end
    end
    CreateCollapsible("Buff / Debuff Frames", 5 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Buff Frame", "hideBuffFrame", db.buffBorders, RefreshBuffBorders,
            { description = "Hide the player buff frame entirely, including while mousing over its anchor area." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide Debuff Frame", "hideDebuffFrame", db.buffBorders, RefreshBuffBorders,
            { description = "Hide the player debuff frame entirely, including while mousing over its anchor area." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Fade Buffs (Show on Mouseover)", "fadeBuffFrame", db.buffBorders, RefreshBuffBorders,
            { description = "Fade the buff frame out when you're not hovering over it. Hover to reveal." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Fade Debuffs (Show on Mouseover)", "fadeDebuffFrame", db.buffBorders, RefreshBuffBorders,
            { description = "Fade the debuff frame out when you're not hovering over it. Hover to reveal." }), body, sy)
        P(GUI:CreateFormSlider(body, "Fade Out Opacity", 0, 1, 0.05, "fadeOutAlpha", db.buffBorders, RefreshBuffBorders, nil,
            { description = "Opacity used when the buff or debuff frame is faded out. 0 is fully invisible, 1 is fully opaque." }), body, sy)
    end)

    -- Combat & Messages
    CreateCollapsible("Combat & Messages", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        sy = P(GUI:CreateFormCheckbox(body, "Hide Error Messages (Red Text)", "hideErrorMessages", db.uiHider, RefreshUIHider,
            { description = "Suppress the red error messages printed above the action bar, such as Not Enough Mana or Spell Not Ready." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Info Messages (i.e. Quest Prog)", "hideInfoMessages", db.uiHider, RefreshUIHider,
            { description = "Suppress the yellow info messages printed above the action bar, such as quest objective progress updates." }), body, sy)
    end)

    relayout()
end

-- Export
ns.QUI_AutohideOptions = {
    BuildAutohideTab = BuildAutohideTab
}
