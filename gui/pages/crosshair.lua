--[[
    QUI Options - Cursor & Crosshair Tab
    BuildCrosshairTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildCrosshairTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 1, tabName = "General & QoL", subTabIndex = 3, subTabName = "Cursor & Crosshair"})

    -- ========== CURSOR RING SECTION (before crosshair) ==========
    local cursorHeader = GUI:CreateSectionHeader(tabContent, "Cursor Ring")
    cursorHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - cursorHeader.gap

    if db and db.reticle then
        local cr = db.reticle

        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Reticle", "enabled", cr, Shared.RefreshReticle)
        enableCheck:SetPoint("TOPLEFT", PADDING, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Reticle Style dropdown
        local reticleOptions = {
            {value = "dot", text = "Dot"},
            {value = "cross", text = "Cross"},
            {value = "chevron", text = "Chevron"},
            {value = "diamond", text = "Diamond"},
        }
        local reticleDropdown = GUI:CreateFormDropdown(tabContent, "Reticle Style", reticleOptions, "reticleStyle", cr, Shared.RefreshReticle)
        reticleDropdown:SetPoint("TOPLEFT", PADDING, y)
        reticleDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local reticleSizeSlider = GUI:CreateFormSlider(tabContent, "Reticle Size", 4, 20, 1, "reticleSize", cr, Shared.RefreshReticle)
        reticleSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        reticleSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Ring Style dropdown
        local ringStyleOptions = {
            {value = "thin", text = "Thin"},
            {value = "standard", text = "Standard"},
            {value = "thick", text = "Thick"},
            {value = "solid", text = "Solid"},
        }
        local ringStyleDropdown = GUI:CreateFormDropdown(tabContent, "Ring Style", ringStyleOptions, "ringStyle", cr, Shared.RefreshReticle)
        ringStyleDropdown:SetPoint("TOPLEFT", PADDING, y)
        ringStyleDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local ringSizeSlider = GUI:CreateFormSlider(tabContent, "Ring Size", 20, 80, 1, "ringSize", cr, Shared.RefreshReticle)
        ringSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        ringSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", cr, Shared.RefreshReticle)
        classColorCheck:SetPoint("TOPLEFT", PADDING, y)
        classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local customColorPicker = GUI:CreateFormColorPicker(tabContent, "Custom Color", "customColor", cr, Shared.RefreshReticle)
        customColorPicker:SetPoint("TOPLEFT", PADDING, y)
        customColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local combatAlphaSlider = GUI:CreateFormSlider(tabContent, "Combat Opacity", 0, 1, 0.05, "inCombatAlpha", cr, Shared.RefreshReticle)
        combatAlphaSlider:SetPoint("TOPLEFT", PADDING, y)
        combatAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local oocAlphaSlider = GUI:CreateFormSlider(tabContent, "Out-of-Combat Opacity", 0, 1, 0.05, "outCombatAlpha", cr, Shared.RefreshReticle)
        oocAlphaSlider:SetPoint("TOPLEFT", PADDING, y)
        oocAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local hideOOCCheck = GUI:CreateFormCheckbox(tabContent, "Hide Outside Combat", "hideOutOfCombat", cr, Shared.RefreshReticle)
        hideOOCCheck:SetPoint("TOPLEFT", PADDING, y)
        hideOOCCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- GCD Settings sub-section
        y = y - 10  -- Extra spacing before sub-section
        local gcdLabel = GUI:CreateLabel(tabContent, "GCD Settings", 12, C.accent)
        gcdLabel:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20

        local gcdEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable GCD Swipe", "gcdEnabled", cr, Shared.RefreshReticle)
        gcdEnableCheck:SetPoint("TOPLEFT", PADDING, y)
        gcdEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local gcdFadeSlider = GUI:CreateFormSlider(tabContent, "Ring Fade During GCD", 0, 1, 0.05, "gcdFadeRing", cr, Shared.RefreshReticle)
        gcdFadeSlider:SetPoint("TOPLEFT", PADDING, y)
        gcdFadeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local gcdReverseCheck = GUI:CreateFormCheckbox(tabContent, "Reverse Swipe", "gcdReverse", cr, Shared.RefreshReticle)
        gcdReverseCheck:SetPoint("TOPLEFT", PADDING, y)
        gcdReverseCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local rightClickCheck = GUI:CreateFormCheckbox(tabContent, "Hide on Right-Click", "hideOnRightClick", cr, Shared.RefreshReticle)
        rightClickCheck:SetPoint("TOPLEFT", PADDING, y)
        rightClickCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local cursorTipText = GUI:CreateLabel(tabContent, "Note that cursor replacements consume some CPU resources due to continuous tracking. Negligible on modern CPUs.", 11, C.textMuted)
        cursorTipText:SetPoint("TOPLEFT", PADDING, y)
        cursorTipText:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        cursorTipText:SetJustifyH("LEFT")
        cursorTipText:SetWordWrap(true)
        y = y - 40
    end

    y = y - 20  -- Spacing between sections

    -- ========== QUI CROSSHAIR SECTION ==========
    local crossHeader = GUI:CreateSectionHeader(tabContent, "QUI Crosshair")
    crossHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - crossHeader.gap

    if db and db.crosshair then
        local ch = db.crosshair

        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Show Crosshair", "enabled", ch, Shared.RefreshCrosshair)
        enableCheck:SetPoint("TOPLEFT", PADDING, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local combatCheck = GUI:CreateFormCheckbox(tabContent, "Combat Only", "onlyInCombat", ch, Shared.RefreshCrosshair)
        combatCheck:SetPoint("TOPLEFT", PADDING, y)
        combatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Range-based color changes
        local outOfRangeColorPicker  -- Forward declare
        local rangeColorCombatOnlyCheck  -- Forward declare
        local hideUntilOutOfRangeCheck  -- Forward declare
        local meleeRangeCheck  -- Forward declare
        local midRangeCheck  -- Forward declare
        local midRangeColorPicker  -- Forward declare

        local rangeColorCheck = GUI:CreateFormCheckbox(tabContent, "Enable Range Checking", "changeColorOnRange", ch, function(val)
            Shared.RefreshCrosshair()
            -- Enable/disable the related controls based on toggle
            if meleeRangeCheck and meleeRangeCheck.SetEnabled then
                meleeRangeCheck:SetEnabled(val)
            end
            if midRangeCheck and midRangeCheck.SetEnabled then
                midRangeCheck:SetEnabled(val)
            end
            if outOfRangeColorPicker and outOfRangeColorPicker.SetEnabled then
                outOfRangeColorPicker:SetEnabled(val)
            end
            if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                midRangeColorPicker:SetEnabled(val and ch.enableMeleeRangeCheck and ch.enableMidRangeCheck)
            end
            if rangeColorCombatOnlyCheck and rangeColorCombatOnlyCheck.SetEnabled then
                rangeColorCombatOnlyCheck:SetEnabled(val)
            end
            if hideUntilOutOfRangeCheck and hideUntilOutOfRangeCheck.SetEnabled then
                hideUntilOutOfRangeCheck:SetEnabled(val)
            end
        end)
        rangeColorCheck:SetPoint("TOPLEFT", PADDING, y)
        rangeColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Initialize melee range check default
        if ch.enableMeleeRangeCheck == nil then
            ch.enableMeleeRangeCheck = true
        end

        meleeRangeCheck = GUI:CreateFormCheckbox(tabContent, "Melee Range (5 yards)", "enableMeleeRangeCheck", ch, function(val)
            Shared.RefreshCrosshair()
            -- Mid-range color only relevant when both checks are enabled
            if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                midRangeColorPicker:SetEnabled(ch.changeColorOnRange and val and ch.enableMidRangeCheck)
            end
        end)
        meleeRangeCheck:SetPoint("TOPLEFT", PADDING, y)
        meleeRangeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if meleeRangeCheck.SetEnabled then
            meleeRangeCheck:SetEnabled(ch.changeColorOnRange == true)
        end
        y = y - FORM_ROW

        midRangeCheck = GUI:CreateFormCheckbox(tabContent, "Mid-Range (25 yards) - Evoker/DDH", "enableMidRangeCheck", ch, function(val)
            Shared.RefreshCrosshair()
            if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                midRangeColorPicker:SetEnabled(ch.changeColorOnRange and ch.enableMeleeRangeCheck and val)
            end
        end)
        midRangeCheck:SetPoint("TOPLEFT", PADDING, y)
        midRangeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if midRangeCheck.SetEnabled then
            midRangeCheck:SetEnabled(ch.changeColorOnRange == true)
        end
        y = y - FORM_ROW

        rangeColorCombatOnlyCheck = GUI:CreateFormCheckbox(tabContent, "Check Only In Combat", "rangeColorInCombatOnly", ch, Shared.RefreshCrosshair)
        rangeColorCombatOnlyCheck:SetPoint("TOPLEFT", PADDING, y)
        rangeColorCombatOnlyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if rangeColorCombatOnlyCheck.SetEnabled then
            rangeColorCombatOnlyCheck:SetEnabled(ch.changeColorOnRange == true)
        end
        y = y - FORM_ROW

        hideUntilOutOfRangeCheck = GUI:CreateFormCheckbox(tabContent, "Only Show When Out of Range", "hideUntilOutOfRange", ch, Shared.RefreshCrosshair)
        hideUntilOutOfRangeCheck:SetPoint("TOPLEFT", PADDING, y)
        hideUntilOutOfRangeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if hideUntilOutOfRangeCheck.SetEnabled then
            hideUntilOutOfRangeCheck:SetEnabled(ch.changeColorOnRange == true)
        end
        y = y - FORM_ROW

        if not ch.outOfRangeColor then
            ch.outOfRangeColor = { 1, 0.2, 0.2, 1 }
        end
        outOfRangeColorPicker = GUI:CreateFormColorPicker(tabContent, "Out of Range Color", "outOfRangeColor", ch, function()
            Shared.RefreshCrosshair()
        end)
        outOfRangeColorPicker:SetPoint("TOPLEFT", PADDING, y)
        outOfRangeColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if outOfRangeColorPicker.SetEnabled then
            outOfRangeColorPicker:SetEnabled(ch.changeColorOnRange == true)
        end
        y = y - FORM_ROW

        if ch.midRangeColor == nil then
            ch.midRangeColor = { 1, 0.6, 0.2, 1 }
        end
        midRangeColorPicker = GUI:CreateFormColorPicker(tabContent, "Mid-Range Color (between melee & 25yd)", "midRangeColor", ch, function()
            Shared.RefreshCrosshair()
        end)
        midRangeColorPicker:SetPoint("TOPLEFT", PADDING, y)
        midRangeColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if midRangeColorPicker.SetEnabled then
            -- Only enabled when both range checks are on (otherwise no "mid" range exists)
            midRangeColorPicker:SetEnabled(ch.changeColorOnRange == true and ch.enableMeleeRangeCheck ~= false and ch.enableMidRangeCheck == true)
        end
        y = y - FORM_ROW

        if not ch.lineColor then
            ch.lineColor = { ch.r or 0.286, ch.g or 0.929, ch.b or 1, ch.a or 1 }
        end
        local crossColor = GUI:CreateFormColorPicker(tabContent, "Crosshair Color", "lineColor", ch, function()
            ch.r, ch.g, ch.b, ch.a = ch.lineColor[1], ch.lineColor[2], ch.lineColor[3], ch.lineColor[4]
            Shared.RefreshCrosshair()
        end)
        crossColor:SetPoint("TOPLEFT", PADDING, y)
        crossColor:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        if not ch.borderColorTable then
            ch.borderColorTable = { ch.borderR or 0, ch.borderG or 0, ch.borderB or 0, ch.borderA or 1 }
        end
        local borderColor = GUI:CreateFormColorPicker(tabContent, "Outline Color", "borderColorTable", ch, function()
            ch.borderR, ch.borderG, ch.borderB, ch.borderA = ch.borderColorTable[1], ch.borderColorTable[2], ch.borderColorTable[3], ch.borderColorTable[4]
            Shared.RefreshCrosshair()
        end)
        borderColor:SetPoint("TOPLEFT", PADDING, y)
        borderColor:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local sizeSlider = GUI:CreateFormSlider(tabContent, "Length", 5, 50, 1, "size", ch, Shared.RefreshCrosshair)
        sizeSlider:SetPoint("TOPLEFT", PADDING, y)
        sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local thickSlider = GUI:CreateFormSlider(tabContent, "Thickness", 1, 10, 1, "thickness", ch, Shared.RefreshCrosshair)
        thickSlider:SetPoint("TOPLEFT", PADDING, y)
        thickSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local borderSlider = GUI:CreateFormSlider(tabContent, "Outline Size", 0, 5, 1, "borderSize", ch, Shared.RefreshCrosshair)
        borderSlider:SetPoint("TOPLEFT", PADDING, y)
        borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local strataOptions = {
            {value = "BACKGROUND", text = "Background"},
            {value = "LOW", text = "Low"},
            {value = "MEDIUM", text = "Medium"},
            {value = "HIGH", text = "High"},
            {value = "DIALOG", text = "Dialog"},
        }
        local strataDropdown = GUI:CreateFormDropdown(tabContent, "Frame Strata", strataOptions, "strata", ch, Shared.RefreshCrosshair)
        strataDropdown:SetPoint("TOPLEFT", PADDING, y)
        strataDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local xOffsetSlider = GUI:CreateFormSlider(tabContent, "X-Offset", -500, 500, 1, "offsetX", ch, Shared.RefreshCrosshair)
        xOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Y-Offset", -500, 500, 1, "offsetY", ch, Shared.RefreshCrosshair)
        yOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_CrosshairOptions = {
    BuildCrosshairTab = BuildCrosshairTab
}
