--[[
    QUI Options - Autohide Tab
    BuildAutohideTab for Autohide & Skinning page. Migrated to V3 body
    pattern (CreateAccentDotLabel + CreateSettingsCardGroup + BuildSettingRow).
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI

local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema

local MakeLayout = ns.QUI_ModulesSettingsLayout.MakeLayout
local row = ns.QUI_ModulesSettingsLayout.Row

-- Pair an entry list 2-per-row into card `s`, optionally trailing unpaired.
local function pairEntries(s, entries, dbTable, refresh)
    local cells = {}
    for _, it in ipairs(entries) do
        local w = GUI:CreateFormCheckbox(s.frame, nil, it.key, dbTable, refresh,
            { description = it.desc })
        cells[#cells + 1] = row(s.frame, it.label, w)
    end
    ns.QUI_ModulesSettingsLayout.PairCells(s, cells)
end

local function BuildAutohideTab(tabContent)
    local db = Shared.GetDB()
    if not db then return end
    if not db.uiHider then db.uiHider = {} end
    if not db.buffBorders then db.buffBorders = {} end

    GUI:SetSearchContext({tabIndex = 10, tabName = "Skinning & Autohide", subTabIndex = 1, subTabName = "Autohide"})

    local function RefreshUIHider()
        if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end
    end
    local function RefreshBuffBorders()
        if _G.QUI_RefreshBuffBorders then _G.QUI_RefreshBuffBorders() end
    end

    if not db.uiHider.hideObjectiveTrackerInstanceTypes then
        db.uiHider.hideObjectiveTrackerInstanceTypes = {
            mythicPlus = false, mythicDungeon = false, normalDungeon = false,
            heroicDungeon = false, followerDungeon = false, raid = false, pvp = false, arena = false,
        }
    end

    local L = MakeLayout(tabContent)

    ---------------------------------------------------------------------------
    -- OBJECTIVE TRACKER
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Objective Tracker"])
    local sOT = L.sectionAt()
    local hideAlwaysW = GUI:CreateFormCheckbox(sOT.frame, nil, "hideObjectiveTrackerAlways", db.uiHider, RefreshUIHider,
        { description = ns.L["Hide the quest and objective tracker everywhere, ignoring the per-instance toggles below."] })
    sOT.AddRow(row(sOT.frame, ns.L["Hide Always"], hideAlwaysW))

    pairEntries(sOT, {
        {key = "mythicPlus",      label = ns.L["Hide in Mythic+"],            desc = ns.L["Hide the objective tracker while you are running a Mythic+ keystone."]},
        {key = "mythicDungeon",   label = ns.L["Hide in Mythic Dungeons"],    desc = ns.L["Hide the objective tracker while you are in a Mythic difficulty dungeon."]},
        {key = "heroicDungeon",   label = ns.L["Hide in Heroic Dungeons"],    desc = ns.L["Hide the objective tracker while you are in a Heroic difficulty dungeon."]},
        {key = "normalDungeon",   label = ns.L["Hide in Normal Dungeons"],    desc = ns.L["Hide the objective tracker while you are in a Normal difficulty dungeon."]},
        {key = "followerDungeon", label = ns.L["Hide in Follower Dungeons"],  desc = ns.L["Hide the objective tracker while you are in a Follower dungeon."]},
        {key = "raid",            label = ns.L["Hide in Raids"],              desc = ns.L["Hide the objective tracker while you are inside a raid instance."]},
        {key = "pvp",             label = ns.L["Hide in Battlegrounds"],      desc = ns.L["Hide the objective tracker while you are in a Battleground."]},
        {key = "arena",           label = ns.L["Hide in Arenas"],             desc = ns.L["Hide the objective tracker while you are in an Arena match."]},
    }, db.uiHider.hideObjectiveTrackerInstanceTypes, RefreshUIHider)
    L.closeSection(sOT)

    ---------------------------------------------------------------------------
    -- FRAMES & BUTTONS
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Frames & Buttons"])
    local sFB = L.sectionAt()
    pairEntries(sFB, {
        {key = "hideRaidFrameManager",   label = ns.L["Hide Compact Raid Frame Manager"], desc = ns.L["Hide the compact raid frame manager widget that lets you pick built-in raid profiles."]},
        {key = "hideBuffCollapseButton", label = ns.L["Hide Buff Frame Collapse Button"], desc = ns.L["Hide the small arrow button above the buff frame that collapses your buffs into a dropdown."]},
        {key = "hideTalkingHead",        label = ns.L["Hide Talking Head Frame"],          desc = ns.L["Hide the talking head frame used by cinematic NPC dialogue."]},
        {key = "muteTalkingHead",        label = ns.L["Mute Talking Head Voice"],          desc = ns.L["Silence the voice audio that plays with talking head events, without hiding the frame itself."]},
        {key = "hideWorldMapBlackout",   label = ns.L["Hide World Map Blackout"],          desc = ns.L["Remove the dark overlay drawn behind the world map so the game world stays visible while it's open."]},
        {key = "hidePlayerFrameInParty", label = ns.L["Hide Player Frame in Party/Raid"],  desc = ns.L["Hide the standalone player unit frame whenever you are in a group, since the raid frames already show you."]},
    }, db.uiHider, RefreshUIHider)
    L.closeSection(sFB)

    ---------------------------------------------------------------------------
    -- NAMEPLATES
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Nameplates"])
    local sNP = L.sectionAt()
    local npFriendlyW = GUI:CreateFormCheckbox(sNP.frame, nil, "hideFriendlyPlayerNameplates", db.uiHider, RefreshUIHider,
        { description = ns.L["Hide nameplates above friendly player characters to reduce visual clutter."] })
    local npNPCW = GUI:CreateFormCheckbox(sNP.frame, nil, "hideFriendlyNPCNameplates", db.uiHider, RefreshUIHider,
        { description = ns.L["Hide nameplates above friendly NPCs such as quest givers and town residents."] })
    sNP.AddRow(
        row(sNP.frame, ns.L["Hide Friendly Player Nameplates"], npFriendlyW),
        row(sNP.frame, ns.L["Hide Friendly NPC Nameplates"], npNPCW)
    )
    L.closeSection(sNP)

    ---------------------------------------------------------------------------
    -- STATUS BARS
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Status Bars"])
    local sSB = L.sectionAt()
    local sbXP = GUI:CreateFormCheckbox(sSB.frame, nil, "hideExperienceBar", db.uiHider, RefreshUIHider,
        { description = ns.L["Hide the experience bar shown along the bottom of the screen while leveling."] })
    local sbRep = GUI:CreateFormCheckbox(sSB.frame, nil, "hideReputationBar", db.uiHider, RefreshUIHider,
        { description = ns.L["Hide the reputation tracking bar shown above the main action bar."] })
    sSB.AddRow(
        row(sSB.frame, ns.L["Hide Experience Bar (XP)"], sbXP),
        row(sSB.frame, ns.L["Hide Reputation Bar"], sbRep)
    )

    local sbVeh = GUI:CreateFormCheckbox(sSB.frame, nil, "hideDataBarsInVehicle", db.uiHider, RefreshUIHider,
        { description = ns.L["Hide the experience and reputation bars while you are riding a vehicle."] })
    local sbPet = GUI:CreateFormCheckbox(sSB.frame, nil, "hideDataBarsInPetBattle", db.uiHider, RefreshUIHider,
        { description = ns.L["Hide the experience and reputation bars while you are in a pet battle."] })
    sSB.AddRow(
        row(sSB.frame, ns.L["Hide Data Bars in Vehicle"], sbVeh),
        row(sSB.frame, ns.L["Hide Data Bars in Pet Battle"], sbPet)
    )
    L.closeSection(sSB)

    ---------------------------------------------------------------------------
    -- BUFF / DEBUFF FRAMES
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Buff / Debuff Frames"])
    local sBD = L.sectionAt()
    local bdHideBuff = GUI:CreateFormCheckbox(sBD.frame, nil, "hideBuffFrame", db.buffBorders, RefreshBuffBorders,
        { description = ns.L["Hide the player buff frame entirely, including while mousing over its anchor area."] })
    local bdHideDebuff = GUI:CreateFormCheckbox(sBD.frame, nil, "hideDebuffFrame", db.buffBorders, RefreshBuffBorders,
        { description = ns.L["Hide the player debuff frame entirely, including while mousing over its anchor area."] })
    sBD.AddRow(
        row(sBD.frame, ns.L["Hide Buff Frame"], bdHideBuff),
        row(sBD.frame, ns.L["Hide Debuff Frame"], bdHideDebuff)
    )

    local bdFadeBuff = GUI:CreateFormCheckbox(sBD.frame, nil, "fadeBuffFrame", db.buffBorders, RefreshBuffBorders,
        { description = ns.L["Fade the buff frame out when you're not hovering over it. Hover to reveal."] })
    local bdFadeDebuff = GUI:CreateFormCheckbox(sBD.frame, nil, "fadeDebuffFrame", db.buffBorders, RefreshBuffBorders,
        { description = ns.L["Fade the debuff frame out when you're not hovering over it. Hover to reveal."] })
    sBD.AddRow(
        row(sBD.frame, ns.L["Fade Buffs (Show on Mouseover)"], bdFadeBuff),
        row(sBD.frame, ns.L["Fade Debuffs (Show on Mouseover)"], bdFadeDebuff)
    )

    local bdAlphaW = GUI:CreateFormSlider(sBD.frame, nil, 0, 1, 0.05, "fadeOutAlpha", db.buffBorders, RefreshBuffBorders,
        { precision = 2, description = ns.L["Opacity used when the buff or debuff frame is faded out. 0 is fully invisible, 1 is fully opaque."] })
    sBD.AddRow(row(sBD.frame, ns.L["Fade Out Opacity"], bdAlphaW))
    L.closeSection(sBD)

    ---------------------------------------------------------------------------
    -- COMBAT & MESSAGES
    ---------------------------------------------------------------------------
    L.headerAt(ns.L["Combat & Messages"])
    local sCM = L.sectionAt()
    local cmErr = GUI:CreateFormCheckbox(sCM.frame, nil, "hideErrorMessages", db.uiHider, RefreshUIHider,
        { description = ns.L["Suppress the red error messages printed above the action bar, such as Not Enough Mana or Spell Not Ready."] })
    local cmInfo = GUI:CreateFormCheckbox(sCM.frame, nil, "hideInfoMessages", db.uiHider, RefreshUIHider,
        { description = ns.L["Suppress the yellow info messages printed above the action bar, such as quest objective progress updates."] })
    sCM.AddRow(
        row(sCM.frame, ns.L["Hide Error Messages (Red Text)"], cmErr),
        row(sCM.frame, ns.L["Hide Info Messages (i.e. Quest Prog)"], cmInfo)
    )
    L.closeSection(sCM)

    L.finish()
end

ns.QUI_AutohideOptions = {
    BuildAutohideTab = BuildAutohideTab
}

if Registry and Schema
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "autohidePage",
        moverKey = "autohide",
        category = "appearance",
        nav = { tileId = "appearance", subPageIndex = 5 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildAutohideTab,
            }),
        },
    }))
end
