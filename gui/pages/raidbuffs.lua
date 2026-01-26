--[[
    QUI Options - Missing Raid Buffs Tab
    BuildRaidBuffsTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

---------------------------------------------------------------------------
-- REFRESH FUNCTIONS
---------------------------------------------------------------------------

local function RefreshRaidBuffs()
    if ns.RaidBuffs and ns.RaidBuffs.Refresh then
        ns.RaidBuffs:Refresh()
    end
end

local function TogglePreview(enabled)
    if ns.RaidBuffs then
        if enabled then
            if ns.RaidBuffs.EnablePreview then
                ns.RaidBuffs:EnablePreview()
            end
        else
            if ns.RaidBuffs.DisablePreview then
                ns.RaidBuffs:DisablePreview()
            end
        end
    end
end

---------------------------------------------------------------------------
-- TAB BUILDER
---------------------------------------------------------------------------

local function BuildRaidBuffsTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 1, tabName = "General & QoL", subTabIndex = 9, subTabName = "Missing Raid Buffs"})

    -- Section Header
    local header = GUI:CreateSectionHeader(tabContent, "Missing Raid Buffs Display")
    header:SetPoint("TOPLEFT", PADDING, y)
    y = y - header.gap

    -- Description
    local desc = GUI:CreateLabel(tabContent, "Shows missing raid buffs when a buff-providing class is in your group. Click icons to request buffs.", 11, C.textMuted)
    desc:SetPoint("TOPLEFT", PADDING, y)
    desc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetHeight(30)
    y = y - 40

    if db and db.raidBuffs then
        local settings = db.raidBuffs

        -- Enable Missing Raid Buffs
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Missing Raid Buffs Display",
            "enabled", settings, RefreshRaidBuffs)
        enableCheck:SetPoint("TOPLEFT", PADDING, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Show Only In Group
        local groupOnlyCheck = GUI:CreateFormCheckbox(tabContent, "Show Only When In Group",
            "showOnlyInGroup", settings, RefreshRaidBuffs)
        groupOnlyCheck:SetPoint("TOPLEFT", PADDING, y)
        groupOnlyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Show Only In Instance
        local instanceOnlyCheck = GUI:CreateFormCheckbox(tabContent, "Show Only In Dungeons/Raids",
            "showOnlyInInstance", settings, RefreshRaidBuffs)
        instanceOnlyCheck:SetPoint("TOPLEFT", PADDING, y)
        instanceOnlyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Provider Mode
        local providerCheck = GUI:CreateFormCheckbox(tabContent, "Provider Mode (Show buffs you can cast)",
            "providerMode", settings, RefreshRaidBuffs)
        providerCheck:SetPoint("TOPLEFT", PADDING, y)
        providerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Hide Label Bar
        local hideLabelCheck = GUI:CreateFormCheckbox(tabContent, "Hide 'Missing Buffs' Label",
            "hideLabelBar", settings, RefreshRaidBuffs)
        hideLabelCheck:SetPoint("TOPLEFT", PADDING, y)
        hideLabelCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Appearance Section
        y = y - 10
        local appearanceHeader = GUI:CreateSectionHeader(tabContent, "Appearance")
        appearanceHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - appearanceHeader.gap

        -- Icon Size slider
        local iconSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 16, 64, 1,
            "iconSize", settings, RefreshRaidBuffs)
        iconSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        iconSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Icon Spacing slider
        local iconSpacingSlider = GUI:CreateFormSlider(tabContent, "Icon Spacing", 0, 20, 1,
            "iconSpacing", settings, RefreshRaidBuffs)
        iconSpacingSlider:SetPoint("TOPLEFT", PADDING, y)
        iconSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Label Font Size slider
        local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Label Font Size", 8, 24, 1,
            "labelFontSize", settings, RefreshRaidBuffs)
        fontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Grow Direction dropdown
        local growOptions = {
            { value = "RIGHT", text = "Right" },
            { value = "LEFT", text = "Left" },
            { value = "CENTER_H", text = "Center (Horizontal)" },
            { value = "UP", text = "Up" },
            { value = "DOWN", text = "Down" },
            { value = "CENTER_V", text = "Center (Vertical)" },
        }
        local growDropdown = GUI:CreateFormDropdown(tabContent, "Grow Direction", growOptions,
            "growDirection", settings, RefreshRaidBuffs)
        growDropdown:SetPoint("TOPLEFT", PADDING, y)
        growDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW - 10

        -- Icon Border Section
        y = y - 10
        local borderHeader = GUI:CreateSectionHeader(tabContent, "Icon Border")
        borderHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - borderHeader.gap

        -- Initialize iconBorder settings if not present
        if not settings.iconBorder then
            settings.iconBorder = { show = true, width = 1, useClassColor = false, color = { 0.2, 1.0, 0.6, 1 } }
        end
        local borderSettings = settings.iconBorder

        -- Show Border checkbox
        local showBorderCheck = GUI:CreateFormCheckbox(tabContent, "Show Icon Border",
            "show", borderSettings, RefreshRaidBuffs)
        showBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        showBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Use Class Color checkbox
        local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color",
            "useClassColor", borderSettings, RefreshRaidBuffs)
        classColorCheck:SetPoint("TOPLEFT", PADDING, y)
        classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Border Color picker
        local borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color",
            "color", borderSettings, RefreshRaidBuffs)
        borderColorPicker:SetPoint("TOPLEFT", PADDING, y)
        borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Border Width slider
        local borderWidthSlider = GUI:CreateFormSlider(tabContent, "Border Width", 1, 4, 1,
            "width", borderSettings, RefreshRaidBuffs)
        borderWidthSlider:SetPoint("TOPLEFT", PADDING, y)
        borderWidthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Buff Count Section
        y = y - 10
        local countHeader = GUI:CreateSectionHeader(tabContent, "Buff Count Display")
        countHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - countHeader.gap

        -- Initialize buffCount settings if not present
        if not settings.buffCount then
            settings.buffCount = { show = true, position = "BOTTOM", fontSize = 10, color = { 1, 1, 1, 1 } }
        end
        local countSettings = settings.buffCount

        -- Show Buff Count checkbox
        local showCountCheck = GUI:CreateFormCheckbox(tabContent, "Show Buff Count",
            "show", countSettings, RefreshRaidBuffs)
        showCountCheck:SetPoint("TOPLEFT", PADDING, y)
        showCountCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Count Position dropdown
        local countPosOptions = {
            { value = "TOP", text = "Top" },
            { value = "BOTTOM", text = "Bottom" },
            { value = "LEFT", text = "Left" },
            { value = "RIGHT", text = "Right" },
        }
        local countPosDropdown = GUI:CreateFormDropdown(tabContent, "Count Position", countPosOptions,
            "position", countSettings, RefreshRaidBuffs)
        countPosDropdown:SetPoint("TOPLEFT", PADDING, y)
        countPosDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW - 10

        -- Count Font Size slider
        local countFontSlider = GUI:CreateFormSlider(tabContent, "Count Font Size", 8, 18, 1,
            "fontSize", countSettings, RefreshRaidBuffs)
        countFontSlider:SetPoint("TOPLEFT", PADDING, y)
        countFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Count Color picker
        local countColorPicker = GUI:CreateFormColorPicker(tabContent, "Count Color",
            "color", countSettings, RefreshRaidBuffs)
        countColorPicker:SetPoint("TOPLEFT", PADDING, y)
        countColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Count Font dropdown
        local fontList = {}
        local LSM = LibStub("LibSharedMedia-3.0", true)
        if LSM then
            for name in pairs(LSM:HashTable("font")) do
                table.insert(fontList, {value = name, text = name})
            end
            table.sort(fontList, function(a, b) return a.text < b.text end)
        else
            fontList = {{value = "Friz Quadrata TT", text = "Friz Quadrata TT"}}
        end
        local countFontDropdown = GUI:CreateFormDropdown(tabContent, "Count Font", fontList,
            "font", countSettings, RefreshRaidBuffs)
        countFontDropdown:SetPoint("TOPLEFT", PADDING, y)
        countFontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW - 10

        -- Count X Offset slider
        local countOffsetXSlider = GUI:CreateFormSlider(tabContent, "Count X Offset", -50, 50, 1,
            "offsetX", countSettings, RefreshRaidBuffs)
        countOffsetXSlider:SetPoint("TOPLEFT", PADDING, y)
        countOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Count Y Offset slider
        local countOffsetYSlider = GUI:CreateFormSlider(tabContent, "Count Y Offset", -50, 50, 1,
            "offsetY", countSettings, RefreshRaidBuffs)
        countOffsetYSlider:SetPoint("TOPLEFT", PADDING, y)
        countOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Preview Section
        y = y - 10
        local previewHeader = GUI:CreateSectionHeader(tabContent, "Preview")
        previewHeader:SetPoint("TOPLEFT", PADDING, y)
        y = y - previewHeader.gap

        -- Preview checkbox
        local previewCheck = GUI:CreateCheckbox(tabContent, "Preview Missing Buffs", function(self)
            TogglePreview(self:GetChecked())
        end)
        previewCheck:SetPoint("TOPLEFT", PADDING, y)
        y = y - FORM_ROW

        -- Preview note
        local previewNote = GUI:CreateLabel(tabContent, "Preview shows sample missing buff icons for positioning.", 10, C.textMuted)
        previewNote:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20
    else
        -- Fallback if db not ready
        local noDbText = GUI:CreateLabel(tabContent, "Settings not available. Please reload UI.", 12, C.red)
        noDbText:SetPoint("TOPLEFT", PADDING, y)
    end

    return y
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_RaidBuffsOptions = {
    BuildRaidBuffsTab = BuildRaidBuffsTab,
}
