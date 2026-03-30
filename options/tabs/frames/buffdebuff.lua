local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local Shared = ns.QUI_Options

local function BuildBuffDebuffTab(tabContent)
    local PAD = Shared.PADDING
    local width = math.max(300, (tabContent:GetWidth() or 760) - (PAD * 2))

    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 4, subTabName = "Buff & Debuff"})

    local y = -10

    -- Buffs section header
    local buffHeader = GUI:CreateSectionHeader(tabContent, "Buffs")
    buffHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - buffHeader.gap

    local buffHost = CreateFrame("Frame", nil, tabContent)
    buffHost:SetPoint("TOPLEFT", PAD, y)
    buffHost:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    buffHost:SetHeight(1)

    local buffHeight = ns.SettingsBuilders.BuildBuffDebuffSettings("buff", buffHost, width, { includePosition = false })

    -- Debuffs section header
    local debuffHeader = GUI:CreateSectionHeader(tabContent, "Debuffs")
    debuffHeader:SetPoint("TOPLEFT", buffHost, "BOTTOMLEFT", 0, -12)

    local debuffHost = CreateFrame("Frame", nil, tabContent)
    debuffHost:SetPoint("TOPLEFT", debuffHeader, "TOPLEFT", 0, -debuffHeader.gap)
    debuffHost:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    debuffHost:SetHeight(1)

    local debuffHeight = ns.SettingsBuilders.BuildBuffDebuffSettings("debuff", debuffHost, width, { includePosition = false })
    tabContent:SetHeight((buffHeight or 80) + (debuffHeight or 80) + buffHeader.gap + debuffHeader.gap + 36)
end

ns.QUI_BuffDebuffOptions = {
    BuildBuffDebuffTab = BuildBuffDebuffTab,
}
