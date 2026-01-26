--[[
    QUI Options - Buff & Debuff Tab
    BuildBuffDebuffTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildBuffDebuffTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 1, tabName = "General & QoL", subTabIndex = 4, subTabName = "Buff & Debuff"})

    -- Section Header
    local header = GUI:CreateSectionHeader(tabContent, "Buff & Debuff Borders")
    header:SetPoint("TOPLEFT", PADDING, y)
    y = y - header.gap

    -- Description
    local desc = GUI:CreateLabel(tabContent, "Modifies borders and font size of Blizzard default Buff and Debuff frames, normally placed beside minimap.", 11, C.textMuted)
    desc:SetPoint("TOPLEFT", PADDING, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetHeight(30)
    y = y - 40

    if db and db.buffBorders then
        -- Enable Buff Borders
        local enableBuffs = GUI:CreateFormCheckbox(tabContent, "Enable Buff Borders",
            "enableBuffs", db.buffBorders, Shared.RefreshBuffBorders)
        enableBuffs:SetPoint("TOPLEFT", PADDING, y)
        enableBuffs:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Enable Debuff Borders
        local enableDebuffs = GUI:CreateFormCheckbox(tabContent, "Enable Debuff Borders",
            "enableDebuffs", db.buffBorders, Shared.RefreshBuffBorders)
        enableDebuffs:SetPoint("TOPLEFT", PADDING, y)
        enableDebuffs:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Border Size slider
        local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 1, 5, 0.5,
            "borderSize", db.buffBorders, Shared.RefreshBuffBorders)
        borderSlider:SetPoint("TOPLEFT", PADDING, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Font Size slider
        local fontSlider = GUI:CreateFormSlider(tabContent, "Font Size", 6, 24, 1,
            "fontSize", db.buffBorders, Shared.RefreshBuffBorders)
        fontSlider:SetPoint("TOPLEFT", PADDING, y)
        fontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Section Header: Hide Blizzard Default Buffs and Debuffs
        local hideHeader = GUI:CreateSectionHeader(tabContent, "Hide Blizzard Default Buffs and Debuffs")
        hideHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - hideHeader.gap

        -- Hide Buffs
        local hideBuffs = GUI:CreateFormCheckbox(tabContent, "Hide Buffs",
            "hideBuffFrame", db.buffBorders, Shared.RefreshBuffBorders)
        hideBuffs:SetPoint("TOPLEFT", PADDING, y)
        hideBuffs:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Hide Debuffs
        local hideDebuffs = GUI:CreateFormCheckbox(tabContent, "Hide Debuffs",
            "hideDebuffFrame", db.buffBorders, Shared.RefreshBuffBorders)
        hideDebuffs:SetPoint("TOPLEFT", PADDING, y)
        hideDebuffs:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    else
        local info = GUI:CreateLabel(tabContent, "Buff/Debuff settings not available", 12, C.textMuted)
        info:SetPoint("TOPLEFT", PADDING, y)
    end

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_BuffDebuffOptions = {
    BuildBuffDebuffTab = BuildBuffDebuffTab
}
