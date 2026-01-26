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

    local subTabs = GUI:CreateSubTabs(content, {
        {name = "General", builder = ns.QUI_QoLOptions.BuildGeneralTab},
        {name = "HUD Visibility", builder = ns.QUI_HUDVisibilityOptions.BuildHUDVisibilityTab},
        {name = "Cursor & Crosshair", builder = ns.QUI_CrosshairOptions.BuildCrosshairTab},
        {name = "Buff & Debuff", builder = ns.QUI_BuffDebuffOptions.BuildBuffDebuffTab},
        {name = "Chat", builder = ns.QUI_ChatOptions.BuildChatTab},
        {name = "Tooltip", builder = ns.QUI_TooltipsOptions.BuildTooltipTab},
        {name = "Character Pane", builder = ns.QUI_CharacterOptions.BuildCharacterPaneTab},
        {name = "Dragonriding", builder = ns.QUI_SkyridingOptions.BuildDragonridingTab},
        {name = "Missing Raid Buffs", builder = ns.QUI_RaidBuffsOptions.BuildRaidBuffsTab},
    })
    subTabs:SetPoint("TOPLEFT", 5, -5)
    subTabs:SetPoint("TOPRIGHT", -5, -5)
    subTabs:SetHeight(600)

    content:SetHeight(650)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_GeneralOptions = {
    CreateGeneralQoLPage = CreateGeneralQoLPage,
}
