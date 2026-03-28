local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options

local CreateScrollableContent = Shared.CreateScrollableContent

--------------------------------------------------------------------------------
-- PAGE: General & QoL (coordinator - subtabs from separate files)
--------------------------------------------------------------------------------
local function CreateGeneralQoLPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    GUI:CreateSubTabs(content, {
        {name = "General", builder = ns.QUI_QoLOptions.BuildGeneralTab},
        {name = "HUD Visibility", builder = ns.QUI_HUDVisibilityOptions.BuildHUDVisibilityTab},
        {name = "Cursor & Crosshair", builder = ns.QUI_CrosshairOptions.BuildCrosshairTab},
        {name = "Buff & Debuff", builder = ns.QUI_BuffDebuffOptions.BuildBuffDebuffTab},
        {name = "Chat", builder = ns.QUI_ChatOptions.BuildChatTab},
        {name = "Tooltip", builder = ns.QUI_TooltipsOptions.BuildTooltipTab},
        {name = "Character Pane", builder = ns.QUI_CharacterOptions.BuildCharacterPaneTab},
        {name = "Skyriding", builder = ns.QUI_SkyridingOptions.BuildDragonridingTab},
        {name = "Missing Raid Buffs", builder = ns.QUI_RaidBuffsOptions.BuildRaidBuffsTab},
        {name = "Party Keystones", builder = ns.QUI_PartyKeystonesOptions.BuildPartyKeystonesTab},
        {name = "XP Tracker", builder = ns.QUI_XPTrackerOptions.BuildXPTrackerTab},
        {name = "Blizzard Mover", builder = ns.QUI_BlizzardMoverOptions.BuildBlizzardMoverTab},
    })

    content:SetHeight(600)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_GeneralOptions = {
    CreateGeneralQoLPage = CreateGeneralQoLPage,
}
