local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options

local CreateScrollableContent = Shared.CreateScrollableContent

--------------------------------------------------------------------------------
-- PAGE: Autohide & Skinning (coordinator - subtabs from separate files)
--------------------------------------------------------------------------------
local function CreateAutohidesPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    local subTabs = GUI:CreateSubTabs(content, {
        {name = "Autohide", builder = ns.QUI_AutohideOptions.BuildAutohideTab},
        {name = "Skinning", builder = ns.QUI_SkinningOptions.BuildSkinningTab},
    })
    subTabs:SetPoint("TOPLEFT", 5, -5)
    subTabs:SetPoint("TOPRIGHT", -5, -5)
    subTabs:SetHeight(600)

    content:SetHeight(650)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
ns.QUI_AutohidesOptions = {
    CreateAutohidesPage = CreateAutohidesPage,
}
