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
        -- Buff & Debuff settings moved to Layout Mode settings panels
        -- Chat settings moved to Layout Mode settings panels
        {name = "Character Pane", builder = ns.QUI_CharacterOptions.BuildCharacterPaneTab},
        -- Tooltip, Skyriding, Missing Raid Buffs, Party Keystones moved to Layout Mode settings panels
        -- XP Tracker settings moved to Layout Mode settings panels
    })

    content:SetHeight(600)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_GeneralOptions = {
    CreateGeneralQoLPage = CreateGeneralQoLPage,
}
