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
    local y = -10
    local PAD = 10
    local FORM_ROW = 32
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 5, tabName = "Autohide & Skinning", subTabIndex = 1, subTabName = "Autohide"})
    GUI:SetSearchSection("Autohide Settings")

    -- Refresh callback
    local function RefreshUIHider()
        if _G.QUI_RefreshUIHider then
            _G.QUI_RefreshUIHider()
        end
    end

    if db then
        if not db.uiHider then db.uiHider = {} end

        -- ═══════════════════════════════════════════════════════════════
        -- SECTION: Objective Tracker
        -- ═══════════════════════════════════════════════════════════════
        local objHeader = GUI:CreateSectionHeader(tabContent, "Objective Tracker")
        objHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - objHeader.gap

        local checkAlways = GUI:CreateFormCheckbox(tabContent, "Hide Always", "hideObjectiveTrackerAlways", db.uiHider, RefreshUIHider)
        checkAlways:SetPoint("TOPLEFT", PAD, y)
        checkAlways:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Ensure instance types table exists
        if not db.uiHider.hideObjectiveTrackerInstanceTypes then
            db.uiHider.hideObjectiveTrackerInstanceTypes = {
                mythicPlus = false,
                mythicDungeon = false,
                normalDungeon = false,
                heroicDungeon = false,
                followerDungeon = false,
                raid = false,
                pvp = false,
                arena = false,
            }
        end

        local instanceTypes = {
            {key = "mythicPlus", label = "Hide in Mythic+"},
            {key = "mythicDungeon", label = "Hide in Mythic Dungeons"},
            {key = "heroicDungeon", label = "Hide in Heroic Dungeons"},
            {key = "normalDungeon", label = "Hide in Normal Dungeons"},
            {key = "followerDungeon", label = "Hide in Follower Dungeons"},
            {key = "raid", label = "Hide in Raids"},
            {key = "pvp", label = "Hide in Battlegrounds"},
            {key = "arena", label = "Hide in Arenas"},
        }

        for _, instanceType in ipairs(instanceTypes) do
            local checkInstance = GUI:CreateFormCheckbox(tabContent, instanceType.label, instanceType.key, db.uiHider.hideObjectiveTrackerInstanceTypes, RefreshUIHider)
            checkInstance:SetPoint("TOPLEFT", PAD, y)
            checkInstance:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- ═══════════════════════════════════════════════════════════════
        -- SECTION: Frames & Buttons
        -- ═══════════════════════════════════════════════════════════════
        local framesHeader = GUI:CreateSectionHeader(tabContent, "Frames & Buttons")
        framesHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - framesHeader.gap

        local frameOptions = {
            {key = "hideRaidFrameManager", label = "Hide Compact Raid Frame Manager"},
            {key = "hideBuffCollapseButton", label = "Hide Buff Frame Collapse Button"},
            {key = "hideTalkingHead", label = "Hide Talking Head Frame"},
            {key = "muteTalkingHead", label = "Mute Talking Head Voice"},
            {key = "hideWorldMapBlackout", label = "Hide World Map Blackout"},
        }

        for _, opt in ipairs(frameOptions) do
            local check = GUI:CreateFormCheckbox(tabContent, opt.label, opt.key, db.uiHider, RefreshUIHider)
            check:SetPoint("TOPLEFT", PAD, y)
            check:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- ═══════════════════════════════════════════════════════════════
        -- SECTION: Nameplates
        -- ═══════════════════════════════════════════════════════════════
        local nameplatesHeader = GUI:CreateSectionHeader(tabContent, "Nameplates")
        nameplatesHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - nameplatesHeader.gap

        local nameplateOptions = {
            {key = "hideFriendlyPlayerNameplates", label = "Hide Friendly Player Nameplates"},
            {key = "hideFriendlyNPCNameplates", label = "Hide Friendly NPC Nameplates"},
        }

        for _, opt in ipairs(nameplateOptions) do
            local check = GUI:CreateFormCheckbox(tabContent, opt.label, opt.key, db.uiHider, RefreshUIHider)
            check:SetPoint("TOPLEFT", PAD, y)
            check:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- ═══════════════════════════════════════════════════════════════
        -- SECTION: Status Bars
        -- ═══════════════════════════════════════════════════════════════
        local barsHeader = GUI:CreateSectionHeader(tabContent, "Status Bars")
        barsHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - barsHeader.gap

        local barOptions = {
            {key = "hideExperienceBar", label = "Hide Experience Bar (XP)"},
            {key = "hideReputationBar", label = "Hide Reputation Bar"},
        }

        for _, opt in ipairs(barOptions) do
            local check = GUI:CreateFormCheckbox(tabContent, opt.label, opt.key, db.uiHider, RefreshUIHider)
            check:SetPoint("TOPLEFT", PAD, y)
            check:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- ═══════════════════════════════════════════════════════════════
        -- SECTION: Combat & Messages
        -- ═══════════════════════════════════════════════════════════════
        local combatHeader = GUI:CreateSectionHeader(tabContent, "Combat & Messages")
        combatHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - combatHeader.gap

        local combatOptions = {
            {key = "hideErrorMessages", label = "Hide Error Messages (Red Text)"},
        }

        for _, opt in ipairs(combatOptions) do
            local check = GUI:CreateFormCheckbox(tabContent, opt.label, opt.key, db.uiHider, RefreshUIHider)
            check:SetPoint("TOPLEFT", PAD, y)
            check:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end
    end

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_AutohideOptions = {
    BuildAutohideTab = BuildAutohideTab
}
