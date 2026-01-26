--[[
    QUI Options - Tooltip Tab
    BuildTooltipTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildTooltipTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 1, tabName = "General & QoL", subTabIndex = 6, subTabName = "Tooltip"})

    -- Refresh callback
    local function RefreshTooltips()
        if _G.QUI_RefreshTooltips then
            _G.QUI_RefreshTooltips()
        end
    end

    local tooltip = db and db.tooltip
    if not tooltip then return end

    -- Visibility dropdown options
    local visibilityOptions = {
        {value = "SHOW", text = "Always Show"},
        {value = "HIDE", text = "Always Hide"},
        {value = "SHIFT", text = "Shift to Show"},
        {value = "CTRL", text = "Ctrl to Show"},
        {value = "ALT", text = "Alt to Show"},
    }

    -- Combat override dropdown options
    local combatOverrideOptions = {
        {value = "NONE", text = "None"},
        {value = "SHIFT", text = "Shift"},
        {value = "CTRL", text = "Ctrl"},
        {value = "ALT", text = "Alt"},
    }

    -- SECTION: Enable/Disable
    GUI:SetSearchSection("Enable/Disable")
    local enableHeader = GUI:CreateSectionHeader(tabContent, "Enable/Disable QUI Tooltip Module")
    enableHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - enableHeader.gap

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "QUI Tooltip Module", "enabled", tooltip, RefreshTooltips)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local enableInfo = GUI:CreateLabel(tabContent, "Controls tooltip positioning and per-context visibility.", 10, C.textMuted)
    enableInfo:SetPoint("TOPLEFT", PADDING, y)
    enableInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    enableInfo:SetJustifyH("LEFT")
    y = y - 20

    -- SECTION: Tooltip Skinning
    GUI:SetSearchSection("Tooltip Skinning")
    local skinHeader = GUI:CreateSectionHeader(tabContent, "Tooltip Skinning")
    skinHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - skinHeader.gap

    local skinCheck = GUI:CreateFormCheckbox(tabContent, "Skin Tooltips", "skinTooltips", tooltip, function()
        GUI:ShowConfirmation({
            title = "Reload UI?",
            message = "Skinning changes require a reload to take effect.",
            acceptText = "Reload",
            cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end)
    skinCheck:SetPoint("TOPLEFT", PADDING, y)
    skinCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local skinInfo = GUI:CreateLabel(tabContent, "Apply QUI theme (colors, border) to all game tooltips.", 10, C.textMuted)
    skinInfo:SetPoint("TOPLEFT", PADDING, y)
    skinInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    skinInfo:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local hideHealthCheck = GUI:CreateFormCheckbox(tabContent, "Hide Health Bar", "hideHealthBar", tooltip, RefreshTooltips)
    hideHealthCheck:SetPoint("TOPLEFT", PADDING, y)
    hideHealthCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local hideHealthInfo = GUI:CreateLabel(tabContent, "Hide the health bar shown on player, NPC, and enemy tooltips.", 10, C.textMuted)
    hideHealthInfo:SetPoint("TOPLEFT", PADDING, y)
    hideHealthInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    hideHealthInfo:SetJustifyH("LEFT")
    y = y - 20

    -- SECTION: Cursor Anchor
    GUI:SetSearchSection("Cursor Anchor")
    local cursorHeader = GUI:CreateSectionHeader(tabContent, "Cursor Anchor")
    cursorHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - cursorHeader.gap

    local cursorCheck = GUI:CreateFormCheckbox(tabContent, "Anchor Tooltip to Cursor", "anchorToCursor", tooltip, RefreshTooltips)
    cursorCheck:SetPoint("TOPLEFT", PADDING, y)
    cursorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cursorInfo = GUI:CreateLabel(tabContent, "Tooltip follows your mouse cursor instead of default position.", 10, C.textMuted)
    cursorInfo:SetPoint("TOPLEFT", PADDING, y)
    cursorInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    cursorInfo:SetJustifyH("LEFT")
    y = y - 20

    -- Class Color Name option
    local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Class Color Player Names", "classColorName", tooltip, RefreshTooltips)
    classColorCheck:SetPoint("TOPLEFT", PADDING, y)
    classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local classColorInfo = GUI:CreateLabel(tabContent, "Color player names in tooltips by their class.", 10, C.textMuted)
    classColorInfo:SetPoint("TOPLEFT", PADDING, y)
    classColorInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    classColorInfo:SetJustifyH("LEFT")
    y = y - 20

    -- SECTION: Tooltip Visibility
    GUI:SetSearchSection("Tooltip Visibility")
    local visHeader = GUI:CreateSectionHeader(tabContent, "Tooltip Visibility")
    visHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - visHeader.gap

    local visInfo = GUI:CreateLabel(tabContent, "Control tooltip visibility per element type. Choose a modifier key to only show tooltips while holding that key.", 10, C.textMuted)
    visInfo:SetPoint("TOPLEFT", PADDING, y)
    visInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    visInfo:SetJustifyH("LEFT")
    y = y - 24

    if tooltip.visibility then
        local npcsDropdown = GUI:CreateFormDropdown(tabContent, "NPCs & Players", visibilityOptions, "npcs", tooltip.visibility, RefreshTooltips)
        npcsDropdown:SetPoint("TOPLEFT", PADDING, y)
        npcsDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local abilitiesDropdown = GUI:CreateFormDropdown(tabContent, "Abilities", visibilityOptions, "abilities", tooltip.visibility, RefreshTooltips)
        abilitiesDropdown:SetPoint("TOPLEFT", PADDING, y)
        abilitiesDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local itemsDropdown = GUI:CreateFormDropdown(tabContent, "Inventory", visibilityOptions, "items", tooltip.visibility, RefreshTooltips)
        itemsDropdown:SetPoint("TOPLEFT", PADDING, y)
        itemsDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local framesDropdown = GUI:CreateFormDropdown(tabContent, "Frames", visibilityOptions, "frames", tooltip.visibility, RefreshTooltips)
        framesDropdown:SetPoint("TOPLEFT", PADDING, y)
        framesDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local cdmDropdown = GUI:CreateFormDropdown(tabContent, "Cooldown Manager", visibilityOptions, "cdm", tooltip.visibility, RefreshTooltips)
        cdmDropdown:SetPoint("TOPLEFT", PADDING, y)
        cdmDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local customTrackersDropdown = GUI:CreateFormDropdown(tabContent, "Custom Items/Spells", visibilityOptions, "customTrackers", tooltip.visibility, RefreshTooltips)
        customTrackersDropdown:SetPoint("TOPLEFT", PADDING, y)
        customTrackersDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    y = y - 10

    -- SECTION: Combat
    GUI:SetSearchSection("Combat")
    local combatHeader = GUI:CreateSectionHeader(tabContent, "Combat")
    combatHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - combatHeader.gap

    local hideInCombatCheck = GUI:CreateFormCheckbox(tabContent, "Hide Tooltips in Combat", "hideInCombat", tooltip, RefreshTooltips)
    hideInCombatCheck:SetPoint("TOPLEFT", PADDING, y)
    hideInCombatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local hideInCombatInfo = GUI:CreateLabel(tabContent, "Suppresses tooltips during combat. Use the modifier key below to force-show tooltips when needed.", 10, C.textMuted)
    hideInCombatInfo:SetPoint("TOPLEFT", PADDING, y)
    hideInCombatInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    hideInCombatInfo:SetJustifyH("LEFT")
    y = y - 24

    local combatDropdown = GUI:CreateFormDropdown(tabContent, "Combat Modifier Key", combatOverrideOptions, "combatKey", tooltip, RefreshTooltips)
    combatDropdown:SetPoint("TOPLEFT", PADDING, y)
    combatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_TooltipsOptions = {
    BuildTooltipTab = BuildTooltipTab
}
