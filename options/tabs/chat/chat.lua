local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options

local function BuildChatTab(tabContent)
    local PAD = Shared.PADDING

    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 5, subTabName = "Chat"})

    local host = CreateFrame("Frame", nil, tabContent)
    host:SetPoint("TOPLEFT", PAD, -10)
    host:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    host:SetHeight(1)

    local width = math.max(300, (tabContent:GetWidth() or 760) - (PAD * 2))
    local height = ns.SettingsBuilders.BuildChatSettings(host, width, { includePosition = false })
    tabContent:SetHeight((height or 80) + 20)
end

ns.QUI_ChatOptions = {
    BuildChatTab = BuildChatTab,
}
