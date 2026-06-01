--[[
    QUI Options - Cursor & Crosshair Tab (Gameplay tile sub-page). Migrated
    to V3 body pattern.
]]

local _, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local PAD = (Shared and Shared.PADDING) or 15
local HEADER_GAP = 26
local SECTION_GAP = 14

local function MakeLayout(content)
    local y = -10
    local L = {}
    function L.headerAt(text)
        local h = Shared.CreateAccentDotLabel(content, text, y)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        h:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        y = y - HEADER_GAP
    end
    function L.sectionAt()
        local c = Shared.CreateSettingsCardGroup(content, y)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        c.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
        return c
    end
    function L.closeSection(c)
        c.Finalize()
        y = y - c.frame:GetHeight() - SECTION_GAP
    end
    function L.placeCustom(frame, height)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
        frame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        frame:SetHeight(height)
        y = y - height - SECTION_GAP
    end
    function L.finish()
        content:SetHeight(math.abs(y) + 10)
        return content:GetHeight()
    end
    return L
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

local function BuildCrosshairTab(tabContent)
    local db = Shared.GetDB()
    if not db then return end

    local L = MakeLayout(tabContent)

    -- ========== CURSOR RING ==========
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

        L.headerAt("Cursor Ring")
        local sCR = L.sectionAt()

        local crEnableW = GUI:CreateFormCheckbox(sCR.frame, nil, "enabled", cr, Shared.RefreshReticle,
            { description = "Show a customizable reticle at the center of your screen for aiming and combat feedback." })
        local crStyleW = GUI:CreateFormDropdown(sCR.frame, nil, reticleStyleOptions, "reticleStyle", cr, Shared.RefreshReticle,
            { description = "Shape of the reticle drawn at the center of the cursor ring (dot, cross, chevron, or diamond)." })
        sCR.AddRow(
            row(sCR.frame, "Enable Reticle", crEnableW),
            row(sCR.frame, "Reticle Style", crStyleW)
        )

        local crRetSizeW = GUI:CreateFormSlider(sCR.frame, nil, 4, 20, 1, "reticleSize", cr, Shared.RefreshReticle,
            { description = "Pixel size of the center reticle shape." })
        local crRingStyleW = GUI:CreateFormDropdown(sCR.frame, nil, ringStyleOptions, "ringStyle", cr, Shared.RefreshReticle,
            { description = "Stroke style of the ring that surrounds the reticle." })
        sCR.AddRow(
            row(sCR.frame, "Reticle Size", crRetSizeW),
            row(sCR.frame, "Ring Style", crRingStyleW)
        )

        local crRingSizeW = GUI:CreateFormSlider(sCR.frame, nil, 20, 80, 1, "ringSize", cr, Shared.RefreshReticle,
            { description = "Outer diameter of the cursor ring in pixels." })
        local crClassW = GUI:CreateFormCheckbox(sCR.frame, nil, "useClassColor", cr, Shared.RefreshReticle,
            { description = "Tint the reticle with your character's class color instead of the default white." })
        sCR.AddRow(
            row(sCR.frame, "Ring Size", crRingSizeW),
            row(sCR.frame, "Use Class Color", crClassW)
        )

        local crCustomColorW = GUI:CreateFormColorPicker(sCR.frame, nil, "customColor", cr, Shared.RefreshReticle, nil,
            { description = "Custom color applied to the reticle and ring when Use Class Color is off." })
        local crInCombatW = GUI:CreateFormSlider(sCR.frame, nil, 0, 1, 0.05, "inCombatAlpha", cr, Shared.RefreshReticle,
            { precision = 2, description = "Opacity of the reticle while you are in combat. 0 is fully invisible, 1 is fully opaque." })
        sCR.AddRow(
            row(sCR.frame, "Custom Color", crCustomColorW),
            row(sCR.frame, "Combat Opacity", crInCombatW)
        )

        local crOutCombatW = GUI:CreateFormSlider(sCR.frame, nil, 0, 1, 0.05, "outCombatAlpha", cr, Shared.RefreshReticle,
            { precision = 2, description = "Opacity of the reticle while you are out of combat." })
        local crHideOocW = GUI:CreateFormCheckbox(sCR.frame, nil, "hideOutOfCombat", cr, Shared.RefreshReticle,
            { description = "Completely hide the reticle when you are not in combat, ignoring the Out-of-Combat Opacity slider." })
        sCR.AddRow(
            row(sCR.frame, "Out-of-Combat Opacity", crOutCombatW),
            row(sCR.frame, "Hide Outside Combat", crHideOocW)
        )
        L.closeSection(sCR)

        -- Cursor Ring — GCD
        L.headerAt("Cursor Ring — GCD")
        local sGCD = L.sectionAt()
        local gcdEnableW = GUI:CreateFormCheckbox(sGCD.frame, nil, "gcdEnabled", cr, Shared.RefreshReticle,
            { description = "Animate a radial sweep around the cursor ring during your global cooldown so you can see when the next ability is available." })
        local gcdFadeW = GUI:CreateFormSlider(sGCD.frame, nil, 0, 1, 0.05, "gcdFadeRing", cr, Shared.RefreshReticle,
            { precision = 2, description = "Fade the cursor ring itself during the GCD sweep. Higher values fade the ring more as the sweep progresses." })
        sGCD.AddRow(
            row(sGCD.frame, "Enable GCD Swipe", gcdEnableW),
            row(sGCD.frame, "Ring Fade During GCD", gcdFadeW)
        )

        local gcdReverseW = GUI:CreateFormCheckbox(sGCD.frame, nil, "gcdReverse", cr, Shared.RefreshReticle,
            { description = "Reverse the direction of the GCD sweep animation." })
        local gcdHideRMBW = GUI:CreateFormCheckbox(sGCD.frame, nil, "hideOnRightClick", cr, Shared.RefreshReticle,
            { description = "Hide the reticle while you are holding right mouse button to turn the camera." })
        sGCD.AddRow(
            row(sGCD.frame, "Reverse Swipe", gcdReverseW),
            row(sGCD.frame, "Hide on Right-Click", gcdHideRMBW)
        )
        L.closeSection(sGCD)

        -- CPU usage note (custom block, no card chrome).
        local note = CreateFrame("Frame", nil, tabContent)
        local noteText = GUI:CreateLabel(note,
            "Note that cursor replacements consume some CPU resources due to continuous tracking. Negligible on modern CPUs.",
            11, C.textMuted)
        noteText:SetPoint("TOPLEFT", note, "TOPLEFT", 6, 0)
        noteText:SetPoint("RIGHT", note, "RIGHT", -6, 0)
        noteText:SetJustifyH("LEFT")
        noteText:SetWordWrap(true)
        L.placeCustom(note, 24)
    end

    -- ========== QUI CROSSHAIR ==========
    if db.crosshair then
        local ch = db.crosshair

        local strataOptions = {
            {value = "BACKGROUND", text = "Background"},
            {value = "LOW", text = "Low"},
            {value = "MEDIUM", text = "Medium"},
            {value = "HIGH", text = "High"},
            {value = "DIALOG", text = "Dialog"},
        }

        -- General
        L.headerAt("Crosshair — General")
        local sGen = L.sectionAt()
        local genShowW = GUI:CreateFormCheckbox(sGen.frame, nil, "enabled", ch, Shared.RefreshCrosshair,
            { description = "Show the QUI crosshair at the center of your screen. Useful for Dragonriding, action-camera play, and ranged classes." })
        local genCombatW = GUI:CreateFormCheckbox(sGen.frame, nil, "onlyInCombat", ch, Shared.RefreshCrosshair,
            { description = "Only display the crosshair while you are in combat." })
        sGen.AddRow(
            row(sGen.frame, "Show Crosshair", genShowW),
            row(sGen.frame, "Combat Only", genCombatW)
        )

        local genStrataW = GUI:CreateFormDropdown(sGen.frame, nil, strataOptions, "strata", ch, Shared.RefreshCrosshair,
            { description = "Rendering layer the crosshair is drawn in. Raise this if the crosshair is being covered by other frames." })
        sGen.AddRow(row(sGen.frame, "Frame Strata", genStrataW))
        L.closeSection(sGen)

        -- Range Checking — cross-widget enable/disable logic preserved.
        L.headerAt("Crosshair — Range Checking")
        local sRC = L.sectionAt()
        local outOfRangeColorPicker, rangeColorCombatOnlyCheck, hideUntilOutOfRangeCheck
        local meleeRangeCheck, midRangeCheck, midRangeColorPicker

        local rangeColorCheck = GUI:CreateFormCheckbox(sRC.frame, nil, "changeColorOnRange", ch, function(val)
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

        if ch.enableMeleeRangeCheck == nil then ch.enableMeleeRangeCheck = true end

        meleeRangeCheck = GUI:CreateFormCheckbox(sRC.frame, nil, "enableMeleeRangeCheck", ch, function(val)
            Shared.RefreshCrosshair()
            if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                midRangeColorPicker:SetEnabled(ch.changeColorOnRange and val and ch.enableMidRangeCheck)
            end
        end, { description = "Check whether your target is within 5 yards (melee range) and color the crosshair accordingly." })
        if meleeRangeCheck.SetEnabled then meleeRangeCheck:SetEnabled(ch.changeColorOnRange == true) end

        sRC.AddRow(
            row(sRC.frame, "Enable Range Checking", rangeColorCheck),
            row(sRC.frame, "Melee Range (5 yards)", meleeRangeCheck)
        )

        midRangeCheck = GUI:CreateFormCheckbox(sRC.frame, nil, "enableMidRangeCheck", ch, function(val)
            Shared.RefreshCrosshair()
            if midRangeColorPicker and midRangeColorPicker.SetEnabled then
                midRangeColorPicker:SetEnabled(ch.changeColorOnRange and ch.enableMeleeRangeCheck and val)
            end
        end, { description = "Check whether your target is within the mid-range 25-yard threshold used by Evoker and Demon Hunter specs, and color the crosshair accordingly." })
        if midRangeCheck.SetEnabled then midRangeCheck:SetEnabled(ch.changeColorOnRange == true) end

        rangeColorCombatOnlyCheck = GUI:CreateFormCheckbox(sRC.frame, nil, "rangeColorInCombatOnly", ch, Shared.RefreshCrosshair,
            { description = "Only run the range check (and apply tints) while you are in combat." })
        if rangeColorCombatOnlyCheck.SetEnabled then rangeColorCombatOnlyCheck:SetEnabled(ch.changeColorOnRange == true) end

        sRC.AddRow(
            row(sRC.frame, "Mid-Range (25 yards) - Evoker/DDH", midRangeCheck),
            row(sRC.frame, "Check Only In Combat", rangeColorCombatOnlyCheck)
        )

        hideUntilOutOfRangeCheck = GUI:CreateFormCheckbox(sRC.frame, nil, "hideUntilOutOfRange", ch, Shared.RefreshCrosshair,
            { description = "Keep the crosshair hidden unless your target is out of range, turning it into a range-warning indicator." })
        if hideUntilOutOfRangeCheck.SetEnabled then hideUntilOutOfRangeCheck:SetEnabled(ch.changeColorOnRange == true) end

        if not ch.outOfRangeColor then ch.outOfRangeColor = { 1, 0.2, 0.2, 1 } end
        outOfRangeColorPicker = GUI:CreateFormColorPicker(sRC.frame, nil, "outOfRangeColor", ch, Shared.RefreshCrosshair, nil,
            { description = "Color applied to the crosshair when your target is out of the configured range." })
        if outOfRangeColorPicker.SetEnabled then outOfRangeColorPicker:SetEnabled(ch.changeColorOnRange == true) end

        sRC.AddRow(
            row(sRC.frame, "Only Show When Out of Range", hideUntilOutOfRangeCheck),
            row(sRC.frame, "Out of Range Color", outOfRangeColorPicker)
        )

        if ch.midRangeColor == nil then ch.midRangeColor = { 1, 0.6, 0.2, 1 } end
        midRangeColorPicker = GUI:CreateFormColorPicker(sRC.frame, nil, "midRangeColor", ch, Shared.RefreshCrosshair, nil,
            { description = "Color applied to the crosshair when your target is between the melee (5yd) and mid-range (25yd) thresholds." })
        if midRangeColorPicker.SetEnabled then
            midRangeColorPicker:SetEnabled(ch.changeColorOnRange == true and ch.enableMeleeRangeCheck ~= false and ch.enableMidRangeCheck == true)
        end
        sRC.AddRow(row(sRC.frame, "Mid-Range Color (between melee & 25yd)", midRangeColorPicker))
        L.closeSection(sRC)

        -- Appearance
        L.headerAt("Crosshair — Appearance")
        local sAp = L.sectionAt()
        if not ch.lineColor then
            ch.lineColor = { ch.r or 0.286, ch.g or 0.929, ch.b or 1, ch.a or 1 }
        end
        local apLineW = GUI:CreateFormColorPicker(sAp.frame, nil, "lineColor", ch, function()
            ch.r, ch.g, ch.b, ch.a = ch.lineColor[1], ch.lineColor[2], ch.lineColor[3], ch.lineColor[4]
            Shared.RefreshCrosshair()
        end, nil, { description = "Base color of the crosshair lines. Overridden by range tints when range checking is enabled and applicable." })

        local apBorderSrcW, apBorderColW = ns.QUI_BorderControl.Attach(GUI, sAp.frame, ch, "", Shared.RefreshCrosshair,
            { label = "Outline Color Source", colorLabel = "Outline Color",
              colorDescription = "Color of the outline drawn around the crosshair lines, used to make the crosshair readable against any background." })

        sAp.AddRow(
            row(sAp.frame, "Crosshair Color", apLineW),
            row(sAp.frame, "Outline Color Source", apBorderSrcW)
        )
        sAp.AddRow(row(sAp.frame, "Outline Color", apBorderColW))

        local apLenW = GUI:CreateFormSlider(sAp.frame, nil, 5, 50, 1, "size", ch, Shared.RefreshCrosshair,
            { description = "Length of each crosshair arm in pixels." })
        local apThickW = GUI:CreateFormSlider(sAp.frame, nil, 1, 10, 1, "thickness", ch, Shared.RefreshCrosshair,
            { description = "Thickness of the crosshair lines in pixels." })
        sAp.AddRow(
            row(sAp.frame, "Length", apLenW),
            row(sAp.frame, "Thickness", apThickW)
        )

        local apOutlineW = GUI:CreateFormSlider(sAp.frame, nil, 0, 5, 1, "borderSize", ch, Shared.RefreshCrosshair,
            { description = "Thickness of the outline drawn around each crosshair line. 0 disables the outline." })
        sAp.AddRow(row(sAp.frame, "Outline Size", apOutlineW))
        L.closeSection(sAp)
    end

    L.finish()
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
