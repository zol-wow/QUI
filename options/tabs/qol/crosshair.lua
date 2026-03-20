--[[
    QUI Options - Cursor & Crosshair Tab
    BuildCrosshairTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local P = Helpers.PlaceRow

local function BuildCrosshairTab(tabContent)
    local FORM_ROW = 32
    local PAD = Shared.PADDING
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 3, subTabName = "Cursor & Crosshair"})

    if not db then return end

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

    -- ========== CURSOR RING SECTION ==========
    if db.reticle then
        local cr = db.reticle

        local reticleStyleOptions = {
            {value = "dot", text = "Dot"},
            {value = "cross", text = "Cross"},
            {value = "chevron", text = "Chevron"},
            {value = "diamond", text = "Diamond"},
        }
        local ringStyleOptions = {
            {value = "thin", text = "Thin"},
            {value = "standard", text = "Standard"},
            {value = "thick", text = "Thick"},
            {value = "solid", text = "Solid"},
        }

        CreateCollapsible("Cursor Ring", 10 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Reticle", "enabled", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Reticle Style", reticleStyleOptions, "reticleStyle", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Reticle Size", 4, 20, 1, "reticleSize", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Ring Style", ringStyleOptions, "ringStyle", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Ring Size", 20, 80, 1, "ringSize", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Custom Color", "customColor", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Combat Opacity", 0, 1, 0.05, "inCombatAlpha", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Out-of-Combat Opacity", 0, 1, 0.05, "outCombatAlpha", cr, Shared.RefreshReticle), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Outside Combat", "hideOutOfCombat", cr, Shared.RefreshReticle), body, sy)
        end)

        CreateCollapsible("Cursor Ring — GCD", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable GCD Swipe", "gcdEnabled", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Ring Fade During GCD", 0, 1, 0.05, "gcdFadeRing", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Reverse Swipe", "gcdReverse", cr, Shared.RefreshReticle), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide on Right-Click", "hideOnRightClick", cr, Shared.RefreshReticle), body, sy)

            local tipText = GUI:CreateLabel(body, "Note that cursor replacements consume some CPU resources due to continuous tracking. Negligible on modern CPUs.", 11, C.textMuted)
            tipText:SetPoint("TOPLEFT", 0, sy)
            tipText:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            tipText:SetJustifyH("LEFT")
            tipText:SetWordWrap(true)
        end)
    end

    -- ========== QUI CROSSHAIR SECTION ==========
    if db.crosshair then
        local ch = db.crosshair

        local strataOptions = {
            {value = "BACKGROUND", text = "Background"},
            {value = "LOW", text = "Low"},
            {value = "MEDIUM", text = "Medium"},
            {value = "HIGH", text = "High"},
            {value = "DIALOG", text = "Dialog"},
        }

        CreateCollapsible("Crosshair — General", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Crosshair", "enabled", ch, Shared.RefreshCrosshair), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Combat Only", "onlyInCombat", ch, Shared.RefreshCrosshair), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Frame Strata", strataOptions, "strata", ch, Shared.RefreshCrosshair), body, sy)
        end)

        CreateCollapsible("Crosshair — Range Checking", 9 * FORM_ROW + 8, function(body)
            local sy = -4
            local outOfRangeColorPicker, rangeColorCombatOnlyCheck, hideUntilOutOfRangeCheck, meleeRangeCheck, midRangeCheck, midRangeColorPicker

            local rangeColorCheck = GUI:CreateFormCheckbox(body, "Enable Range Checking", "changeColorOnRange", ch, function(val)
                Shared.RefreshCrosshair()
                if meleeRangeCheck and meleeRangeCheck.SetEnabled then meleeRangeCheck:SetEnabled(val) end
                if midRangeCheck and midRangeCheck.SetEnabled then midRangeCheck:SetEnabled(val) end
                if outOfRangeColorPicker and outOfRangeColorPicker.SetEnabled then outOfRangeColorPicker:SetEnabled(val) end
                if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                    midRangeColorPicker:SetEnabled(val and ch.enableMeleeRangeCheck and ch.enableMidRangeCheck)
                end
                if rangeColorCombatOnlyCheck and rangeColorCombatOnlyCheck.SetEnabled then rangeColorCombatOnlyCheck:SetEnabled(val) end
                if hideUntilOutOfRangeCheck and hideUntilOutOfRangeCheck.SetEnabled then hideUntilOutOfRangeCheck:SetEnabled(val) end
            end)
            sy = P(rangeColorCheck, body, sy)

            if ch.enableMeleeRangeCheck == nil then ch.enableMeleeRangeCheck = true end

            meleeRangeCheck = GUI:CreateFormCheckbox(body, "Melee Range (5 yards)", "enableMeleeRangeCheck", ch, function(val)
                Shared.RefreshCrosshair()
                if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                    midRangeColorPicker:SetEnabled(ch.changeColorOnRange and val and ch.enableMidRangeCheck)
                end
            end)
            if meleeRangeCheck.SetEnabled then meleeRangeCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(meleeRangeCheck, body, sy)

            midRangeCheck = GUI:CreateFormCheckbox(body, "Mid-Range (25 yards) - Evoker/DDH", "enableMidRangeCheck", ch, function(val)
                Shared.RefreshCrosshair()
                if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                    midRangeColorPicker:SetEnabled(ch.changeColorOnRange and ch.enableMeleeRangeCheck and val)
                end
            end)
            if midRangeCheck.SetEnabled then midRangeCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(midRangeCheck, body, sy)

            rangeColorCombatOnlyCheck = GUI:CreateFormCheckbox(body, "Check Only In Combat", "rangeColorInCombatOnly", ch, Shared.RefreshCrosshair)
            if rangeColorCombatOnlyCheck.SetEnabled then rangeColorCombatOnlyCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(rangeColorCombatOnlyCheck, body, sy)

            hideUntilOutOfRangeCheck = GUI:CreateFormCheckbox(body, "Only Show When Out of Range", "hideUntilOutOfRange", ch, Shared.RefreshCrosshair)
            if hideUntilOutOfRangeCheck.SetEnabled then hideUntilOutOfRangeCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(hideUntilOutOfRangeCheck, body, sy)

            if not ch.outOfRangeColor then ch.outOfRangeColor = { 1, 0.2, 0.2, 1 } end
            outOfRangeColorPicker = GUI:CreateFormColorPicker(body, "Out of Range Color", "outOfRangeColor", ch, Shared.RefreshCrosshair)
            if outOfRangeColorPicker.SetEnabled then outOfRangeColorPicker:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(outOfRangeColorPicker, body, sy)

            if ch.midRangeColor == nil then ch.midRangeColor = { 1, 0.6, 0.2, 1 } end
            midRangeColorPicker = GUI:CreateFormColorPicker(body, "Mid-Range Color (between melee & 25yd)", "midRangeColor", ch, Shared.RefreshCrosshair)
            if midRangeColorPicker.SetEnabled then
                midRangeColorPicker:SetEnabled(ch.changeColorOnRange == true and ch.enableMeleeRangeCheck ~= false and ch.enableMidRangeCheck == true)
            end
            sy = P(midRangeColorPicker, body, sy)
        end)

        CreateCollapsible("Crosshair — Appearance", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            if not ch.lineColor then
                ch.lineColor = { ch.r or 0.286, ch.g or 0.929, ch.b or 1, ch.a or 1 }
            end
            sy = P(GUI:CreateFormColorPicker(body, "Crosshair Color", "lineColor", ch, function()
                ch.r, ch.g, ch.b, ch.a = ch.lineColor[1], ch.lineColor[2], ch.lineColor[3], ch.lineColor[4]
                Shared.RefreshCrosshair()
            end), body, sy)

            if not ch.borderColorTable then
                ch.borderColorTable = { ch.borderR or 0, ch.borderG or 0, ch.borderB or 0, ch.borderA or 1 }
            end
            sy = P(GUI:CreateFormColorPicker(body, "Outline Color", "borderColorTable", ch, function()
                ch.borderR, ch.borderG, ch.borderB, ch.borderA = ch.borderColorTable[1], ch.borderColorTable[2], ch.borderColorTable[3], ch.borderColorTable[4]
                Shared.RefreshCrosshair()
            end), body, sy)

            sy = P(GUI:CreateFormSlider(body, "Length", 5, 50, 1, "size", ch, Shared.RefreshCrosshair), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Thickness", 1, 10, 1, "thickness", ch, Shared.RefreshCrosshair), body, sy)
            P(GUI:CreateFormSlider(body, "Outline Size", 0, 5, 1, "borderSize", ch, Shared.RefreshCrosshair), body, sy)
        end)
    end

    relayout()
end

-- Export
ns.QUI_CrosshairOptions = {
    BuildCrosshairTab = BuildCrosshairTab
}
