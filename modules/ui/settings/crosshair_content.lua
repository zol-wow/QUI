--[[
    QUI Options - Cursor & Crosshair Tab (Gameplay tile sub-page)
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local P = Helpers.PlaceRow
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local function BuildCrosshairTab(tabContent)
    local FORM_ROW = 32
    local PAD = Shared.PADDING
    local db = Shared.GetDB()

    if not db then return end

    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(tabContent, PAD)

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
            sy = P(GUI:CreateFormCheckbox(body, "Enable Reticle", "enabled", cr, Shared.RefreshReticle, {
                description = "Show a customizable reticle at the center of your screen for aiming and combat feedback.",
            }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Reticle Style", reticleStyleOptions, "reticleStyle", cr, Shared.RefreshReticle,
                { description = "Shape of the reticle drawn at the center of the cursor ring (dot, cross, chevron, or diamond)." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Reticle Size", 4, 20, 1, "reticleSize", cr, Shared.RefreshReticle, nil,
                { description = "Pixel size of the center reticle shape." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Ring Style", ringStyleOptions, "ringStyle", cr, Shared.RefreshReticle,
                { description = "Stroke style of the ring that surrounds the reticle." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Ring Size", 20, 80, 1, "ringSize", cr, Shared.RefreshReticle, nil,
                { description = "Outer diameter of the cursor ring in pixels." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", cr, Shared.RefreshReticle, {
                description = "Tint the reticle with your character's class color instead of the default white.",
            }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Custom Color", "customColor", cr, Shared.RefreshReticle, nil,
                { description = "Custom color applied to the reticle and ring when Use Class Color is off." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Combat Opacity", 0, 1, 0.05, "inCombatAlpha", cr, Shared.RefreshReticle, nil,
                { description = "Opacity of the reticle while you are in combat. 0 is fully invisible, 1 is fully opaque." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Out-of-Combat Opacity", 0, 1, 0.05, "outCombatAlpha", cr, Shared.RefreshReticle, nil,
                { description = "Opacity of the reticle while you are out of combat." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Outside Combat", "hideOutOfCombat", cr, Shared.RefreshReticle,
                { description = "Completely hide the reticle when you are not in combat, ignoring the Out-of-Combat Opacity slider." }), body, sy)
        end)

        CreateCollapsible("Cursor Ring — GCD", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable GCD Swipe", "gcdEnabled", cr, Shared.RefreshReticle,
                { description = "Animate a radial sweep around the cursor ring during your global cooldown so you can see when the next ability is available." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Ring Fade During GCD", 0, 1, 0.05, "gcdFadeRing", cr, Shared.RefreshReticle, nil,
                { description = "Fade the cursor ring itself during the GCD sweep. Higher values fade the ring more as the sweep progresses." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Reverse Swipe", "gcdReverse", cr, Shared.RefreshReticle,
                { description = "Reverse the direction of the GCD sweep animation." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide on Right-Click", "hideOnRightClick", cr, Shared.RefreshReticle,
                { description = "Hide the reticle while you are holding right mouse button to turn the camera." }), body, sy)

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
            sy = P(GUI:CreateFormCheckbox(body, "Show Crosshair", "enabled", ch, Shared.RefreshCrosshair,
                { description = "Show the QUI crosshair at the center of your screen. Useful for Dragonriding, action-camera play, and ranged classes." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Combat Only", "onlyInCombat", ch, Shared.RefreshCrosshair,
                { description = "Only display the crosshair while you are in combat." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Frame Strata", strataOptions, "strata", ch, Shared.RefreshCrosshair,
                { description = "Rendering layer the crosshair is drawn in. Raise this if the crosshair is being covered by other frames." }), body, sy)
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
            end, { description = "Tint the crosshair based on your target's range. Enables the melee/mid-range thresholds and color pickers below." })
            sy = P(rangeColorCheck, body, sy)

            if ch.enableMeleeRangeCheck == nil then ch.enableMeleeRangeCheck = true end

            meleeRangeCheck = GUI:CreateFormCheckbox(body, "Melee Range (5 yards)", "enableMeleeRangeCheck", ch, function(val)
                Shared.RefreshCrosshair()
                if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                    midRangeColorPicker:SetEnabled(ch.changeColorOnRange and val and ch.enableMidRangeCheck)
                end
            end, { description = "Check whether your target is within 5 yards (melee range) and color the crosshair accordingly." })
            if meleeRangeCheck.SetEnabled then meleeRangeCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(meleeRangeCheck, body, sy)

            midRangeCheck = GUI:CreateFormCheckbox(body, "Mid-Range (25 yards) - Evoker/DDH", "enableMidRangeCheck", ch, function(val)
                Shared.RefreshCrosshair()
                if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                    midRangeColorPicker:SetEnabled(ch.changeColorOnRange and ch.enableMeleeRangeCheck and val)
                end
            end, { description = "Check whether your target is within the mid-range 25-yard threshold used by Evoker and Demon Hunter specs, and color the crosshair accordingly." })
            if midRangeCheck.SetEnabled then midRangeCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(midRangeCheck, body, sy)

            rangeColorCombatOnlyCheck = GUI:CreateFormCheckbox(body, "Check Only In Combat", "rangeColorInCombatOnly", ch, Shared.RefreshCrosshair,
                { description = "Only run the range check (and apply tints) while you are in combat." })
            if rangeColorCombatOnlyCheck.SetEnabled then rangeColorCombatOnlyCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(rangeColorCombatOnlyCheck, body, sy)

            hideUntilOutOfRangeCheck = GUI:CreateFormCheckbox(body, "Only Show When Out of Range", "hideUntilOutOfRange", ch, Shared.RefreshCrosshair,
                { description = "Keep the crosshair hidden unless your target is out of range, turning it into a range-warning indicator." })
            if hideUntilOutOfRangeCheck.SetEnabled then hideUntilOutOfRangeCheck:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(hideUntilOutOfRangeCheck, body, sy)

            if not ch.outOfRangeColor then ch.outOfRangeColor = { 1, 0.2, 0.2, 1 } end
            outOfRangeColorPicker = GUI:CreateFormColorPicker(body, "Out of Range Color", "outOfRangeColor", ch, Shared.RefreshCrosshair, nil,
                { description = "Color applied to the crosshair when your target is out of the configured range." })
            if outOfRangeColorPicker.SetEnabled then outOfRangeColorPicker:SetEnabled(ch.changeColorOnRange == true) end
            sy = P(outOfRangeColorPicker, body, sy)

            if ch.midRangeColor == nil then ch.midRangeColor = { 1, 0.6, 0.2, 1 } end
            midRangeColorPicker = GUI:CreateFormColorPicker(body, "Mid-Range Color (between melee & 25yd)", "midRangeColor", ch, Shared.RefreshCrosshair, nil,
                { description = "Color applied to the crosshair when your target is between the melee (5yd) and mid-range (25yd) thresholds." })
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
            end, nil, { description = "Base color of the crosshair lines. Overridden by range tints when range checking is enabled and applicable." }), body, sy)

            if not ch.borderColorTable then
                ch.borderColorTable = { ch.borderR or 0, ch.borderG or 0, ch.borderB or 0, ch.borderA or 1 }
            end
            sy = P(GUI:CreateFormColorPicker(body, "Outline Color", "borderColorTable", ch, function()
                ch.borderR, ch.borderG, ch.borderB, ch.borderA = ch.borderColorTable[1], ch.borderColorTable[2], ch.borderColorTable[3], ch.borderColorTable[4]
                Shared.RefreshCrosshair()
            end, nil, { description = "Color of the outline drawn around the crosshair lines, used to make the crosshair readable against any background." }), body, sy)

            sy = P(GUI:CreateFormSlider(body, "Length", 5, 50, 1, "size", ch, Shared.RefreshCrosshair, nil,
                { description = "Length of each crosshair arm in pixels." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Thickness", 1, 10, 1, "thickness", ch, Shared.RefreshCrosshair, nil,
                { description = "Thickness of the crosshair lines in pixels." }), body, sy)
            P(GUI:CreateFormSlider(body, "Outline Size", 0, 5, 1, "borderSize", ch, Shared.RefreshCrosshair, nil,
                { description = "Thickness of the outline drawn around each crosshair line. 0 disables the outline." }), body, sy)
        end)
    end

    relayout()
end

-- Export
ns.QUI_CrosshairOptions = {
    BuildCrosshairTab = BuildCrosshairTab
}

if Registry and Schema and RenderAdapters
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "crosshair",
        moverKey = "crosshair",
        category = "gameplay",
        nav = { tileId = "gameplay", subPageIndex = 4 },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = BuildCrosshairTab,
            }),
        },
        render = {
            layout = function(host, options)
                return RenderAdapters.RenderLayoutRoute(host, options and options.providerKey or "crosshair")
            end,
        },
    }))
end
