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
local TOOLTIP_FONT_SIZE_MIN = 8
local TOOLTIP_FONT_SIZE_MAX = 24
local DEFAULT_PLAYER_ILVL_BRACKETS = {
    white = 245,
    green = 255,
    blue = 265,
    purple = 275,
    orange = 285,
}
local PLAYER_ILVL_BRACKET_FIELDS = {
    {key = "white", label = "White", color = {1, 1, 1, 1}},
    {key = "green", label = "Green", color = {0, 1, 0, 1}},
    {key = "blue", label = "Blue", color = {0, 0.44, 0.87, 1}},
    {key = "purple", label = "Purple", color = {0.64, 0.21, 0.93, 1}},
    {key = "orange", label = "Orange", color = {1, 0.5, 0, 1}},
}

local function BuildTooltipTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 6, subTabName = "Tooltip"})

    -- Refresh callback
    local function RefreshTooltips()
        if ns.QUI_RefreshTooltips then
            ns.QUI_RefreshTooltips()
        end
    end

    local function RefreshTooltipFontSize()
        if ns.QUI_RefreshTooltipFontSize then
            ns.QUI_RefreshTooltipFontSize()
        else
            -- Fallback path if skinning module has not initialized yet.
            RefreshTooltips()
        end
    end

    local tooltip = db and db.tooltip
    if not tooltip then return end
    if tooltip.showTooltipTarget == nil then
        tooltip.showTooltipTarget = true
    end
    if tooltip.showPlayerMount == nil then
        tooltip.showPlayerMount = true
    end
    if tooltip.showPlayerMythicRating == nil then
        tooltip.showPlayerMythicRating = true
    end
    if tooltip.colorPlayerItemLevel == nil then
        tooltip.colorPlayerItemLevel = true
    end
    if type(tooltip.itemLevelBrackets) ~= "table" then
        tooltip.itemLevelBrackets = {}
    end
    for key, defaultValue in pairs(DEFAULT_PLAYER_ILVL_BRACKETS) do
        local value = tonumber(tooltip.itemLevelBrackets[key])
        tooltip.itemLevelBrackets[key] = value and math.floor(value) or defaultValue
    end

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

    local cursorAnchorOptions = {
        {value = "TOPLEFT", text = "Top Left"},
        {value = "TOP", text = "Top"},
        {value = "TOPRIGHT", text = "Top Right"},
        {value = "LEFT", text = "Left"},
        {value = "CENTER", text = "Center"},
        {value = "RIGHT", text = "Right"},
        {value = "BOTTOMLEFT", text = "Bottom Left"},
        {value = "BOTTOM", text = "Bottom"},
        {value = "BOTTOMRIGHT", text = "Bottom Right"},
    }

    if not tooltip.cursorAnchor then
        tooltip.cursorAnchor = "TOPLEFT"
    end
    if tooltip.cursorOffsetX == nil then
        tooltip.cursorOffsetX = 16
    end
    if tooltip.cursorOffsetY == nil then
        tooltip.cursorOffsetY = -16
    end

    -- SECTION: Enable/Disable
    GUI:SetSearchSection("Enable/Disable")
    local enableHeader = GUI:CreateSectionHeader(tabContent, "Enable/Disable QUI Tooltip Module")
    enableHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - enableHeader.gap

    local enableCheck = GUI:CreateFormCheckbox(tabContent, "QUI Tooltip Module", "enabled", tooltip, function()
        GUI:ShowConfirmation({
            title = "Reload UI?",
            message = "Tooltip module changes require a reload to take effect.",
            acceptText = "Reload",
            cancelText = "Later",
            onAccept = function() QUI:SafeReload() end,
        })
    end)
    enableCheck:SetPoint("TOPLEFT", PADDING, y)
    enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local enableInfo = GUI:CreateLabel(tabContent, "Master toggle for all QUI tooltip features (positioning, visibility, skinning).", 10, C.textMuted)
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

    -- Refresh callback for live tooltip skin updates
    local function RefreshTooltipSkin()
        if ns.QUI_RefreshTooltipSkinColors then
            ns.QUI_RefreshTooltipSkinColors()
        end
    end

    local bgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", tooltip, RefreshTooltipSkin)
    bgColorPicker:SetPoint("TOPLEFT", PADDING, y)
    bgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local bgOpacitySlider = GUI:CreateFormSlider(tabContent, "Background Opacity", 0, 1, 0.05, "bgOpacity", tooltip, RefreshTooltipSkin, {precision = 2})
    bgOpacitySlider:SetPoint("TOPLEFT", PADDING, y)
    bgOpacitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local showBorderCheck = GUI:CreateFormCheckbox(tabContent, "Show Border", "showBorder", tooltip, RefreshTooltipSkin)
    showBorderCheck:SetPoint("TOPLEFT", PADDING, y)
    showBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local borderThicknessSlider = GUI:CreateFormSlider(tabContent, "Border Thickness", 1, 10, 1, "borderThickness", tooltip, RefreshTooltipSkin)
    borderThicknessSlider:SetPoint("TOPLEFT", PADDING, y)
    borderThicknessSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColor", tooltip, RefreshTooltipSkin)
    borderColorPicker:SetPoint("TOPLEFT", PADDING, y)
    borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- Normalize mutually exclusive flags on load (prefer class color)
    if tooltip.borderUseClassColor and tooltip.borderUseAccentColor then
        tooltip.borderUseAccentColor = false
    end

    local accentColorBorderCheck
    local classColorBorderCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Border", "borderUseClassColor", tooltip, function(val)
        if val then
            tooltip.borderUseAccentColor = false
            if accentColorBorderCheck and accentColorBorderCheck.SetChecked then accentColorBorderCheck:SetChecked(false) end
        end
        if borderColorPicker and borderColorPicker.SetEnabled then
            borderColorPicker:SetEnabled(not val and not tooltip.borderUseAccentColor)
        end
        RefreshTooltipSkin()
    end)
    classColorBorderCheck:SetPoint("TOPLEFT", PADDING, y)
    classColorBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    accentColorBorderCheck = GUI:CreateFormCheckbox(tabContent, "Use Accent Color for Border", "borderUseAccentColor", tooltip, function(val)
        if val then
            tooltip.borderUseClassColor = false
            if classColorBorderCheck and classColorBorderCheck.SetChecked then classColorBorderCheck:SetChecked(false) end
        end
        if borderColorPicker and borderColorPicker.SetEnabled then
            borderColorPicker:SetEnabled(not val and not tooltip.borderUseClassColor)
        end
        RefreshTooltipSkin()
    end)
    accentColorBorderCheck:SetPoint("TOPLEFT", PADDING, y)
    accentColorBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    -- Sync color picker enabled state on load
    if borderColorPicker and borderColorPicker.SetEnabled then
        borderColorPicker:SetEnabled(not tooltip.borderUseClassColor and not tooltip.borderUseAccentColor)
    end

    local hideHealthCheck = GUI:CreateFormCheckbox(tabContent, "Hide Health Bar", "hideHealthBar", tooltip, RefreshTooltips)
    hideHealthCheck:SetPoint("TOPLEFT", PADDING, y)
    hideHealthCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local hideHealthInfo = GUI:CreateLabel(tabContent, "Hide the health bar shown on player, NPC, and enemy tooltips.", 10, C.textMuted)
    hideHealthInfo:SetPoint("TOPLEFT", PADDING, y)
    hideHealthInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    hideHealthInfo:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Tooltip Font Size", TOOLTIP_FONT_SIZE_MIN, TOOLTIP_FONT_SIZE_MAX, 1, "fontSize", tooltip, RefreshTooltipFontSize)
    fontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
    fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local fontSizeInfo = GUI:CreateLabel(tabContent, "Adjust tooltip text size (" .. TOOLTIP_FONT_SIZE_MIN .. "-" .. TOOLTIP_FONT_SIZE_MAX .. ").", 10, C.textMuted)
    fontSizeInfo:SetPoint("TOPLEFT", PADDING, y)
    fontSizeInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    fontSizeInfo:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local spellIDCheck = GUI:CreateFormCheckbox(tabContent, "Show Spell/Icon/Item IDs", "showSpellIDs", tooltip, RefreshTooltips)
    spellIDCheck:SetPoint("TOPLEFT", PADDING, y)
    spellIDCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local spellIDInfo = GUI:CreateLabel(tabContent, "Display spell ID, icon ID, and item ID on buff, debuff, spell, and item tooltips. May not work in combat.", 10, C.textMuted)
    spellIDInfo:SetPoint("TOPLEFT", PADDING, y)
    spellIDInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    spellIDInfo:SetJustifyH("LEFT")
    y = y - FORM_ROW

    -- Class Color Name option
    local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Class Color Player Names", "classColorName", tooltip, RefreshTooltips)
    classColorCheck:SetPoint("TOPLEFT", PADDING, y)
    classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local classColorInfo = GUI:CreateLabel(tabContent, "Color player names in tooltips by their class.", 10, C.textMuted)
    classColorInfo:SetPoint("TOPLEFT", PADDING, y)
    classColorInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    classColorInfo:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local targetInfoCheck = GUI:CreateFormCheckbox(tabContent, "Show Target Info", "showTooltipTarget", tooltip, RefreshTooltips)
    targetInfoCheck:SetPoint("TOPLEFT", PADDING, y)
    targetInfoCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local targetInfoLabel = GUI:CreateLabel(tabContent, "Show the hovered unit's current target when available.", 10, C.textMuted)
    targetInfoLabel:SetPoint("TOPLEFT", PADDING, y)
    targetInfoLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    targetInfoLabel:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local mountInfoCheck = GUI:CreateFormCheckbox(tabContent, "Show Player Mount", "showPlayerMount", tooltip, RefreshTooltips)
    mountInfoCheck:SetPoint("TOPLEFT", PADDING, y)
    mountInfoCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local mountInfoLabel = GUI:CreateLabel(tabContent, "Show mounted player mount names on player tooltips (out of combat).", 10, C.textMuted)
    mountInfoLabel:SetPoint("TOPLEFT", PADDING, y)
    mountInfoLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    mountInfoLabel:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local mythicRatingCheck = GUI:CreateFormCheckbox(tabContent, "Show Player M+ Rating", "showPlayerMythicRating", tooltip, RefreshTooltips)
    mythicRatingCheck:SetPoint("TOPLEFT", PADDING, y)
    mythicRatingCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local mythicRatingLabel = GUI:CreateLabel(tabContent, "Show player Mythic+ rating on player tooltips (out of combat).", 10, C.textMuted)
    mythicRatingLabel:SetPoint("TOPLEFT", PADDING, y)
    mythicRatingLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    mythicRatingLabel:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local RefreshPlayerItemLevelBracketInputs
    local playerILvlCheck = GUI:CreateFormCheckbox(tabContent, "Show Player Item Level", "showPlayerItemLevel", tooltip, function()
        RefreshPlayerItemLevelBracketInputs()
        RefreshTooltips()
    end)
    playerILvlCheck:SetPoint("TOPLEFT", PADDING, y)
    playerILvlCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local playerILvlInfo = GUI:CreateLabel(tabContent, "Show average equipped item level on player tooltips. Remote players may populate after a short inspect delay.", 10, C.textMuted)
    playerILvlInfo:SetPoint("TOPLEFT", PADDING, y)
    playerILvlInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    playerILvlInfo:SetJustifyH("LEFT")
    y = y - FORM_ROW

    local itemLevelColorFields = {}
    local itemLevelColorLabels = {}
    local itemLevelBracketHeader
    local itemLevelBracketInfo

    RefreshPlayerItemLevelBracketInputs = function()
        local enabled = tooltip.showPlayerItemLevel and tooltip.colorPlayerItemLevel

        if itemLevelBracketHeader then
            itemLevelBracketHeader:SetTextColor(enabled and C.text[1] or C.textMuted[1], enabled and C.text[2] or C.textMuted[2], enabled and C.text[3] or C.textMuted[3], 1)
        end
        if itemLevelBracketInfo then
            itemLevelBracketInfo:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], enabled and 1 or 0.6)
        end

        for _, label in ipairs(itemLevelColorLabels) do
            label:SetAlpha(enabled and 1 or 0.6)
        end

        for _, fieldInfo in ipairs(itemLevelColorFields) do
            fieldInfo.input:SetEnabled(enabled)
            fieldInfo.input:EnableMouse(enabled)
            fieldInfo.frame:SetAlpha(enabled and 1 or 0.6)
        end
    end

    local playerILvlColorCheck = GUI:CreateFormCheckbox(tabContent, "Color Player Item Level by Bracket", "colorPlayerItemLevel", tooltip, function()
        RefreshPlayerItemLevelBracketInputs()
        RefreshTooltips()
    end)
    playerILvlColorCheck:SetPoint("TOPLEFT", PADDING, y)
    playerILvlColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local playerILvlColorInfo = GUI:CreateLabel(tabContent, "Use WoW-style grey, white, green, blue, purple, and orange brackets when coloring the player item level line.", 10, C.textMuted)
    playerILvlColorInfo:SetPoint("TOPLEFT", PADDING, y)
    playerILvlColorInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    playerILvlColorInfo:SetJustifyH("LEFT")
    y = y - 24

    local bracketRow = CreateFrame("Frame", nil, tabContent)
    bracketRow:SetHeight(44)
    bracketRow:SetPoint("TOPLEFT", PADDING, y)
    bracketRow:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)

    itemLevelBracketHeader = bracketRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLevelBracketHeader:SetPoint("LEFT", bracketRow, "LEFT", 0, 0)
    itemLevelBracketHeader:SetWidth(170)
    itemLevelBracketHeader:SetJustifyH("LEFT")
    itemLevelBracketHeader:SetText("Bracket Breakpoints")
    itemLevelBracketHeader:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local inputsAnchor = CreateFrame("Frame", nil, bracketRow)
    inputsAnchor:SetPoint("TOPLEFT", bracketRow, "TOPLEFT", 180, 2)
    inputsAnchor:SetPoint("BOTTOMRIGHT", bracketRow, "BOTTOMRIGHT", 0, -2)

    local fieldWidth = 52
    local fieldSpacing = 8
    local previousGroup = nil

    local function CommitBracketValue(fieldKey, editBox)
        local currentValue = tonumber(tooltip.itemLevelBrackets[fieldKey]) or DEFAULT_PLAYER_ILVL_BRACKETS[fieldKey]
        local parsedValue = tonumber(editBox:GetText())
        if parsedValue then
            parsedValue = math.max(0, math.floor(parsedValue))
            tooltip.itemLevelBrackets[fieldKey] = parsedValue
            editBox:SetText(tostring(parsedValue))
            RefreshTooltips()
        else
            editBox:SetText(tostring(currentValue))
        end
        editBox:SetCursorPosition(0)
    end

    for _, field in ipairs(PLAYER_ILVL_BRACKET_FIELDS) do
        local group = CreateFrame("Frame", nil, inputsAnchor)
        group:SetSize(fieldWidth, 40)
        group:SetPoint("TOPLEFT", previousGroup or inputsAnchor, previousGroup and "TOPRIGHT" or "TOPLEFT", previousGroup and fieldSpacing or 0, 0)

        local label = inputsAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(field.label)
        label:SetTextColor(field.color[1], field.color[2], field.color[3], 1)
        label:SetPoint("TOP", group, "TOP", 0, 0)
        table.insert(itemLevelColorLabels, label)

        local fieldBg, input = GUI:CreateInlineEditBox(group, {
            width = fieldWidth,
            height = 22,
            textInset = 6,
            text = tostring(tooltip.itemLevelBrackets[field.key]),
            justifyH = "CENTER",
            maxLetters = 3,
            bgColor = {0.05, 0.05, 0.05, 0.5},
            borderColor = field.color,
            activeBorderColor = field.color,
            onEnterPressed = function(self)
                CommitBracketValue(field.key, self)
            end,
            onEscapePressed = function(self)
                self:SetText(tostring(tooltip.itemLevelBrackets[field.key]))
                self:SetCursorPosition(0)
            end,
            onEditFocusGained = function(self)
                self:HighlightText()
            end,
        })
        fieldBg:SetPoint("TOP", label, "BOTTOM", 0, -2)

        input:HookScript("OnEditFocusLost", function(self)
            CommitBracketValue(field.key, self)
        end)

        table.insert(itemLevelColorFields, {
            frame = fieldBg,
            input = input,
        })

        previousGroup = group
    end

    y = y - 48

    itemLevelBracketInfo = GUI:CreateLabel(tabContent, "Inclusive starts for each color bracket. Values below White use the grey bracket.", 10, C.textMuted)
    itemLevelBracketInfo:SetPoint("TOPLEFT", PADDING, y)
    itemLevelBracketInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    itemLevelBracketInfo:SetJustifyH("LEFT")
    y = y - FORM_ROW

    RefreshPlayerItemLevelBracketInputs()

    if tooltip.hideDelay == nil then tooltip.hideDelay = 0 end
    local hideDelaySlider = GUI:CreateFormSlider(tabContent, "Hide Delay", 0, 2, 0.1, "hideDelay", tooltip, RefreshTooltips, {precision = 1})
    hideDelaySlider:SetPoint("TOPLEFT", PADDING, y)
    hideDelaySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local hideDelayInfo = GUI:CreateLabel(tabContent, "Seconds before tooltip fades out after mouse leaves (0 = instant hide).", 10, C.textMuted)
    hideDelayInfo:SetPoint("TOPLEFT", PADDING, y)
    hideDelayInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    hideDelayInfo:SetJustifyH("LEFT")
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

    local cursorAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Cursor Anchor Point", cursorAnchorOptions, "cursorAnchor", tooltip, RefreshTooltips)
    cursorAnchorDropdown:SetPoint("TOPLEFT", PADDING, y)
    cursorAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cursorOffsetXSlider = GUI:CreateFormSlider(tabContent, "Cursor X Offset", -200, 200, 1, "cursorOffsetX", tooltip, RefreshTooltips)
    cursorOffsetXSlider:SetPoint("TOPLEFT", PADDING, y)
    cursorOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cursorOffsetYSlider = GUI:CreateFormSlider(tabContent, "Cursor Y Offset", -200, 200, 1, "cursorOffsetY", tooltip, RefreshTooltips)
    cursorOffsetYSlider:SetPoint("TOPLEFT", PADDING, y)
    cursorOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    local cursorInfo = GUI:CreateLabel(tabContent, "Tooltip follows your mouse cursor with configurable anchor point and offsets.", 10, C.textMuted)
    cursorInfo:SetPoint("TOPLEFT", PADDING, y)
    cursorInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    cursorInfo:SetJustifyH("LEFT")
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
