local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options

local CreateScrollableContent = Shared.CreateScrollableContent

--------------------------------------------------------------------------------
-- PAGE: Minimap & Datatext (coordinator - subtabs from separate files)
--------------------------------------------------------------------------------
local function CreateMinimapPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    local subTabs = GUI:CreateSubTabs(content, {
        {name = "Minimap", builder = ns.QUI_MinimapOptions.BuildMinimapTab},
        {name = "Datatext", builder = ns.QUI_MinimapOptions.BuildDatatextTab},
    })
    subTabs:SetPoint("TOPLEFT", 5, -5)
    subTabs:SetPoint("TOPRIGHT", -5, -5)
    subTabs:SetHeight(700)

    content:SetHeight(750)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_MinimapPageOptions = {
    CreateMinimapPage = CreateMinimapPage,
}
