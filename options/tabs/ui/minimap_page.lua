local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options

local CreateScrollableContent = Shared.CreateScrollableContent

local function BuildDelegatedTab(tabContent, searchContext, builder)
    local PAD = Shared.PADDING

    GUI:SetSearchContext(searchContext)

    local host = CreateFrame("Frame", nil, tabContent)
    host:SetPoint("TOPLEFT", PAD, -10)
    host:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    host:SetHeight(1)

    local width = math.max(300, (tabContent:GetWidth() or 760) - (PAD * 2))
    local height = builder(host, width, { includePosition = false })
    tabContent:SetHeight((height or 80) + 20)
end

local function CreateMinimapPage(parent)
    local scroll, content = CreateScrollableContent(parent)

    GUI:CreateSubTabs(content, {
        {
            name = "Minimap",
            builder = function(tabContent)
                BuildDelegatedTab(tabContent, {
                    tabIndex = 9,
                    tabName = "Minimap & Datatext",
                    subTabIndex = 1,
                    subTabName = "Minimap",
                }, ns.SettingsBuilders.BuildMinimapSettings)
            end,
        },
        {
            name = "Datatext",
            builder = function(tabContent)
                BuildDelegatedTab(tabContent, {
                    tabIndex = 9,
                    tabName = "Minimap & Datatext",
                    subTabIndex = 2,
                    subTabName = "Datatext",
                }, ns.SettingsBuilders.BuildDatatextSettings)
            end,
        },
    })

    content:SetHeight(600)
end

ns.QUI_MinimapPageOptions = {
    CreateMinimapPage = CreateMinimapPage,
}
