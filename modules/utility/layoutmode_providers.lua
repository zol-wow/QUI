--[[
    QUI Layout Mode Settings Providers
    Migrated from options panels to layout mode context panels.
    Covers: XP Tracker, Brez Counter, Combat Timer, Rotation Assist Icon,
            Focus Cast Alert, Pet Warning, Buff/Debuff Borders, Minimap,
            Extra Action Button, Zone Ability, Totem Bar, Castbars,
            Missing Raid Buffs, Tooltip, Skyriding, Party Keystones,
            Prey Tracker, Chat
]]

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- REGISTER ALL PROVIDERS
---------------------------------------------------------------------------
local function RegisterAllProviders()
    local settingsPanel = ns.QUI_LayoutMode_Settings
    if not settingsPanel then return end

    local GUI = QUI and QUI.GUI
    if not GUI then return end

    local U = ns.QUI_LayoutMode_Utils
    if not U then return end

    local P = U.PlaceRow
    local FORM_ROW = U.FORM_ROW
    local function NotifyProviderFor(widget, opts)
        if GUI and GUI.NotifyProviderChangedForWidget then
            GUI:NotifyProviderChangedForWidget(widget, opts)
        end
    end

    local anchorOptions = {
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

    ---------------------------------------------------------------------------
    -- XP TRACKER
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("xpTracker", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.xpTracker then return 80 end
        local xp = db.xpTracker
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshXPTracker then _G.QUI_RefreshXPTracker() end end

        U.CreateCollapsible(content, "Size & Text", 9 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Bar Width", 200, 1000, 1, "width", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 60, 200, 1, "height", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Bar Height", 8, 40, 1, "barHeight", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Header Font Size", 8, 22, 1, "headerFontSize", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Header Line Height", 12, 30, 1, "headerLineHeight", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 18, 1, "fontSize", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Line Height", 10, 24, 1, "lineHeight", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "barTexture", xp, Refresh), body, sy)
            P(GUI:CreateFormDropdown(body, "Details Grow Direction", {{value="auto",text="Auto"},{value="up",text="Up"},{value="down",text="Down"}}, "detailsGrowDirection", xp, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Colors", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "XP Bar Color", "barColor", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Rested XP Color", "restedColor", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Backdrop Color", "backdropColor", xp, Refresh), body, sy)
            P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", xp, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Display", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Bar Text", "showBarText", xp, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Rested XP Overlay", "showRested", xp, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Text Until Hover", "hideTextUntilHover", xp, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "xpTracker", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- COMBAT TIMER
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("combatTimer", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.combatTimer then return 80 end
        local ct = db.combatTimer
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end end

        U.CreateCollapsible(content, "General", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Only Show In Encounters", "onlyShowInEncounters", ct, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Width", 40, 200, 1, "width", ct, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 20, 100, 1, "height", ct, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Font Size", 12, 32, 1, "fontSize", ct, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Text", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColorText", ct, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Text Color", "textColor", ct, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Custom Font", "useCustomFont", ct, Refresh), body, sy)
            local fonts = U.GetFontList(); if #fonts > 0 then P(GUI:CreateFormDropdown(body, "Font", fonts, "font", ct, Refresh), body, sy) end
        end, sections, relayout)

        U.BuildBackdropBorderSection(content, ct, sections, relayout, Refresh)

        U.BuildPositionCollapsible(content, "combatTimer", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- BREZ COUNTER
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("brezCounter", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.brzCounter then return 80 end
        local bz = db.brzCounter
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end end

        U.CreateCollapsible(content, "General", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Lock Frame", "locked", bz, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Width", 30, 100, 1, "width", bz, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 30, 100, 1, "height", bz, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Charges Font Size", 10, 28, 1, "fontSize", bz, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Timer Font Size", 8, 24, 1, "timerFontSize", bz, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Colors", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Charges Available", "hasChargesColor", bz, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "No Charges", "noChargesColor", bz, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Class Color Timer Text", "useClassColorText", bz, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Timer Text Color", "timerColor", bz, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Custom Font", "useCustomFont", bz, Refresh), body, sy)
            local fonts = U.GetFontList(); if #fonts > 0 then P(GUI:CreateFormDropdown(body, "Font", fonts, "font", bz, Refresh), body, sy) end
        end, sections, relayout)

        U.BuildBackdropBorderSection(content, bz, sections, relayout, Refresh)

        U.BuildPositionCollapsible(content, "brezCounter", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- ATONEMENT COUNTER
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("atonementCounter", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.atonementCounter then return 80 end
        local ac = db.atonementCounter
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshAtonementCounter then _G.QUI_RefreshAtonementCounter() end end

        U.CreateCollapsible(content, "General", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Lock Frame", "locked", ac, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Only In Dungeons/Raids", "showOnlyInInstance", ac, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Spell Icon", "hideIcon", ac, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Width", 30, 100, 1, "width", ac, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 30, 100, 1, "height", ac, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Count Font Size", 10, 36, 1, "fontSize", ac, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Colors", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color Text", "useClassColorText", ac, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Active Count Color", "activeCountColor", ac, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Zero Count Color", "zeroCountColor", ac, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Custom Font", "useCustomFont", ac, Refresh), body, sy)
            local fonts = U.GetFontList(); if #fonts > 0 then P(GUI:CreateFormDropdown(body, "Font", fonts, "font", ac, Refresh), body, sy) end
        end, sections, relayout)

        U.BuildBackdropBorderSection(content, ac, sections, relayout, Refresh)

        U.BuildPositionCollapsible(content, "atonementCounter", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- ROTATION ASSIST ICON
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("rotationAssistIcon", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.rotationAssistIcon then return 80 end
        local ra = db.rotationAssistIcon
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshRotationAssistIcon then _G.QUI_RefreshRotationAssistIcon() end end

        U.CreateCollapsible(content, "General", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Lock Position", "isLocked", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Cooldown Swipe", "cooldownSwipeEnabled", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Visibility", {{value="always",text="Always"},{value="combat",text="In Combat"},{value="hostile",text="Hostile Target"}}, "visibility", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Frame Strata", {{value="LOW",text="Low"},{value="MEDIUM",text="Medium"},{value="HIGH",text="High"},{value="DIALOG",text="Dialog"}}, "frameStrata", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 16, 400, 1, "iconSize", ra, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Border Size", 0, 15, 1, "borderThickness", ra, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Border & Keybind", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Keybind", "showKeybind", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Keybind Color", "keybindColor", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Keybind Anchor", anchorOptions, "keybindAnchor", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Keybind Size", 6, 48, 1, "keybindSize", ra, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Keybind X Offset", -50, 50, 1, "keybindOffsetX", ra, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Keybind Y Offset", -50, 50, 1, "keybindOffsetY", ra, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "rotationAssistIcon", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- FOCUS CAST ALERT
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("focusCastAlert", { build = function(content, key, width)
        local db = U.GetProfileDB()
        local general = db and db.general
        if not general or not general.focusCastAlert then return 80 end
        local fca = general.focusCastAlert
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshFocusCastAlert then _G.QUI_RefreshFocusCastAlert() end end

        U.CreateCollapsible(content, "Text & Font", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            local fonts = U.GetFontList(); table.insert(fonts, 1, {value = "", text = "(Global Font)"})
            sy = P(GUI:CreateFormDropdown(body, "Font", fonts, "font", fca, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 72, 1, "fontSize", fca, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Font Outline", {{value="",text="None"},{value="OUTLINE",text="Outline"},{value="THICKOUTLINE",text="Thick Outline"}}, "fontOutline", fca, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", fca, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Text Color", "textColor", fca, Refresh), body, sy)
            P(GUI:CreateFormDropdown(body, "Anchor To", {{value="screen",text="Screen"},{value="essential",text="CDM Essential"},{value="focus",text="Focus Frame"}}, "anchorTo", fca, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "focusCastAlert", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- PET WARNING
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("petWarning", { build = function(content, key, width)
        local db = U.GetProfileDB()
        local general = db and db.general
        if not general then return 80 end
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RepositionPetWarning then _G.QUI_RepositionPetWarning() end end

        U.CreateCollapsible(content, "Offsets", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Horizontal Offset", -500, 500, 10, "petWarningOffsetX", general, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Vertical Offset", -500, 500, 10, "petWarningOffsetY", general, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "petWarning", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- BUFF BAR
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("buffFrame", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.buffBorders then return 80 end
        local bb = db.buffBorders
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshBuffBorders then _G.QUI_RefreshBuffBorders() end end

        U.CreateCollapsible(content, "Borders", 2 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Buff Borders", "enableBuffs", bb, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Border Size", 1, 5, 0.5, "borderSize", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Border Size is shared with Debuffs")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.CreateCollapsible(content, "Text", 8 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Font Size", 6, 24, 1, "fontSize", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Stacks", "showStacks", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Stack Text Anchor", anchorOptions, "buffStackTextAnchor", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Stack Text X Offset", -20, 20, 1, "buffStackTextOffsetX", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Stack Text Y Offset", -20, 20, 1, "buffStackTextOffsetY", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Duration Text Anchor", anchorOptions, "buffDurationTextAnchor", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Duration Text X Offset", -20, 20, 1, "buffDurationTextOffsetX", bb, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Duration Text Y Offset", -20, 20, 1, "buffDurationTextOffsetY", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Font Size and Show Stacks are shared with Debuffs")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.CreateCollapsible(content, "Layout", 9 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Icons Per Row", 0, 20, 1, "buffIconsPerRow", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Spacing", 0, 20, 1, "buffIconSpacing", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Row Spacing", 0, 30, 1, "buffRowSpacing", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 0, 60, 1, "buffIconSize", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Bottom Padding", 0, 40, 1, "buffBottomPadding", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Grow Left", "buffGrowLeft", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Grow Up", "buffGrowUp", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Invert Swipe Darkening", "buffInvertSwipeDarkening", bb, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Cooldown Swipe", "hideSwipe", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Swipe is shared with Debuffs. Set sliders to 0 for Blizzard defaults")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.CreateCollapsible(content, "Visibility", 3 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Buff Frame", "hideBuffFrame", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Fade Buffs (Show on Mouseover)", "fadeBuffFrame", bb, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Fade Out Opacity", 0, 1, 0.05, "fadeOutAlpha", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Fade Out Opacity is shared with Debuffs")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.BuildPositionCollapsible(content, key, nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- DEBUFF BAR
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("debuffFrame", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.buffBorders then return 80 end
        local bb = db.buffBorders
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshBuffBorders then _G.QUI_RefreshBuffBorders() end end

        U.CreateCollapsible(content, "Borders", 2 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Debuff Borders", "enableDebuffs", bb, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Border Size", 1, 5, 0.5, "borderSize", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Border Size is shared with Buffs")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.CreateCollapsible(content, "Text", 8 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Font Size", 6, 24, 1, "fontSize", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Stacks", "showStacks", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Stack Text Anchor", anchorOptions, "debuffStackTextAnchor", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Stack Text X Offset", -20, 20, 1, "debuffStackTextOffsetX", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Stack Text Y Offset", -20, 20, 1, "debuffStackTextOffsetY", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Duration Text Anchor", anchorOptions, "debuffDurationTextAnchor", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Duration Text X Offset", -20, 20, 1, "debuffDurationTextOffsetX", bb, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Duration Text Y Offset", -20, 20, 1, "debuffDurationTextOffsetY", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Font Size and Show Stacks are shared with Buffs")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.CreateCollapsible(content, "Layout", 9 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Icons Per Row", 0, 20, 1, "debuffIconsPerRow", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Spacing", 0, 20, 1, "debuffIconSpacing", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Row Spacing", 0, 30, 1, "debuffRowSpacing", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 0, 60, 1, "debuffIconSize", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Bottom Padding", 0, 40, 1, "debuffBottomPadding", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Grow Left", "debuffGrowLeft", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Grow Up", "debuffGrowUp", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Invert Swipe Darkening", "debuffInvertSwipeDarkening", bb, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Cooldown Swipe", "hideSwipe", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Swipe is shared with Buffs. Set sliders to 0 for Blizzard defaults")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.CreateCollapsible(content, "Visibility", 3 * FORM_ROW + 22, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Debuff Frame", "hideDebuffFrame", bb, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Fade Debuffs (Show on Mouseover)", "fadeDebuffFrame", bb, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Fade Out Opacity", 0, 1, 0.05, "fadeOutAlpha", bb, Refresh), body, sy)
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Fade Out Opacity is shared with Buffs")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        U.BuildPositionCollapsible(content, key, nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- MINIMAP
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("minimap", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.minimap then return 80 end
        local mm = db.minimap
        if not db.uiHider then db.uiHider = {} end
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end end
        local function RefreshUIHider() if _G.QUI_RefreshUIHider then _G.QUI_RefreshUIHider() end end

        U.CreateCollapsible(content, "General", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Map Dimensions", 120, 380, 1, "size", mm, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Middle-Click Menu", "middleClickMenuEnabled", mm, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Border", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Border Size", 1, 16, 1, "borderSize", mm, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", mm, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Class Color Border", "useClassColorBorder", mm, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Accent Color Border", "useAccentColorBorder", mm, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Hide Elements", 10 * FORM_ROW + 8, function(body)
            local sy = -4
            -- Inverted checkboxes: checked = hide (DB false), unchecked = show (DB true)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Mail (reload after)", "showMail", mm, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Work Order Notification", "showCraftingOrder", mm, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Tracking", "showTracking", mm, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Difficulty", "showDifficulty", mm, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckboxInverted(body, "Hide Garrison/Mission Report", "showMissions", mm, Refresh), body, sy)
            -- UIHider controls
            sy = P(GUI:CreateFormCheckbox(body, "Hide Border (Top)", "hideMinimapBorder", db.uiHider, RefreshUIHider), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Clock Button", "hideTimeManager", db.uiHider, RefreshUIHider), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Calendar Button", "hideGameTime", db.uiHider, RefreshUIHider), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Zone Text (Native)", "hideMinimapZoneText", db.uiHider, RefreshUIHider), body, sy)
            P(GUI:CreateFormCheckboxInverted(body, "Hide Zoom Buttons", "showZoomButtons", mm, Refresh), body, sy)
        end, sections, relayout)

        -- Zone Label section
        U.CreateCollapsible(content, "Zone Label", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Zone Label", "showZoneText", mm, Refresh), body, sy)
            if not mm.zoneTextConfig then mm.zoneTextConfig = {} end
            local ztc = mm.zoneTextConfig
            sy = P(GUI:CreateFormSlider(body, "Horizontal Offset", -150, 150, 1, "offsetX", ztc, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Vertical Offset", -150, 150, 1, "offsetY", ztc, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Label Size", 8, 20, 1, "fontSize", ztc, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Uppercase Text", "allCaps", ztc, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", ztc, Refresh), body, sy)
        end, sections, relayout)

        -- Dungeon Eye section
        if not mm.dungeonEye then
            mm.dungeonEye = { enabled = true, corner = "BOTTOMLEFT", scale = 0.6, offsetX = 0, offsetY = 0 }
        end
        local eye = mm.dungeonEye
        local cornerOptions = {
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "TOPLEFT", text = "Top Left"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
        }
        U.CreateCollapsible(content, "Dungeon Eye", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Dungeon Eye", "enabled", eye, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Corner Position", cornerOptions, "corner", eye, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Scale", 0.1, 2.0, 0.1, "scale", eye, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "X Offset", -30, 30, 1, "offsetX", eye, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Y Offset", -30, 30, 1, "offsetY", eye, Refresh), body, sy)
        end, sections, relayout)

        -- Button Drawer section
        if not mm.buttonDrawer then
            mm.buttonDrawer = {
                enabled = false, anchor = "RIGHT", offsetX = 0, offsetY = 0,
                toggleOffsetX = 0, toggleOffsetY = 0, autoHideDelay = 1.5,
                buttonSize = 28, buttonSpacing = 2, padding = 6, columns = 1,
                growthDirection = "RIGHT", centerGrowth = false,
                bgColor = {0.03, 0.03, 0.03, 1}, bgOpacity = 98,
                borderSize = 1, borderColor = {0.2, 0.8, 0.6, 1},
                openOnMouseover = true, autoHideToggle = false, hiddenButtons = {},
            }
        end
        local drawer = mm.buttonDrawer
        if drawer.toggleSize == nil then drawer.toggleSize = 20 end
        if not drawer.toggleIcon then drawer.toggleIcon = "hammer" end
        if drawer.hiddenButtons == nil then drawer.hiddenButtons = {} end
        if drawer.padding == nil then drawer.padding = 6 end
        if not drawer.growthDirection then drawer.growthDirection = "RIGHT" end
        if drawer.centerGrowth == nil then drawer.centerGrowth = false end
        if not drawer.bgColor then drawer.bgColor = {0.03, 0.03, 0.03, 1} end
        if drawer.bgOpacity == nil then drawer.bgOpacity = 98 end
        if drawer.borderSize == nil then drawer.borderSize = 1 end
        if not drawer.borderColor then drawer.borderColor = {0.2, 0.8, 0.6, 1} end

        local anchorOptions = {
            {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
            {value = "TOP", text = "Top"}, {value = "BOTTOM", text = "Bottom"},
            {value = "TOPLEFT", text = "Top Left"}, {value = "TOPRIGHT", text = "Top Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"}, {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }
        local growthOptions = {
            {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
            {value = "DOWN", text = "Down"}, {value = "UP", text = "Up"},
        }
        local toggleIconOptions = {
            {value = "hammer", text = "Hammer"}, {value = "grid", text = "Grid Dots"},
        }

        U.CreateCollapsible(content, "Button Drawer", 17 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Button Drawer", "enabled", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Open on Mouseover", "openOnMouseover", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Anchor Side", anchorOptions, "anchor", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Drawer X Offset", -200, 200, 1, "offsetX", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Drawer Y Offset", -200, 200, 1, "offsetY", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Button X Offset", -200, 200, 1, "toggleOffsetX", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Button Y Offset", -200, 200, 1, "toggleOffsetY", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Toggle Size", 12, 40, 1, "toggleSize", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Toggle Icon", toggleIconOptions, "toggleIcon", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Auto-Hide Delay (0=manual)", 0, 5, 0.5, "autoHideDelay", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Button Size", 20, 40, 1, "buttonSize", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Inner Padding", 0, 20, 1, "padding", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Columns", 1, 6, 1, "columns", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Growth Direction", growthOptions, "growthDirection", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Center Growth", "centerGrowth", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto-Hide Toggle Button", "autoHideToggle", drawer, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Button Spacing", "buttonSpacing", drawer, Refresh), body, sy)
        end, sections, relayout)

        -- Button Drawer Appearance
        U.CreateCollapsible(content, "Drawer Appearance", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", drawer, Refresh, { noAlpha = true }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 100, 1, "bgOpacity", drawer, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Size (0=hidden)", 0, 8, 1, "borderSize", drawer, Refresh), body, sy)
            P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", drawer, Refresh, { noAlpha = true }), body, sy)
        end, sections, relayout)

        -- Hidden Buttons
        local buttonNames = _G.QUI_GetDrawerButtonNames and _G.QUI_GetDrawerButtonNames() or {}
        local hiddenCount = #buttonNames > 0 and #buttonNames or 1
        U.CreateCollapsible(content, "Hidden Buttons", hiddenCount * FORM_ROW + 8, function(body)
            local sy = -4
            if #buttonNames > 0 then
                for _, bName in ipairs(buttonNames) do
                    local displayName = bName:gsub("^LibDBIcon10_", "")
                    sy = P(GUI:CreateFormCheckbox(body, displayName, bName, drawer.hiddenButtons, Refresh), body, sy)
                end
            else
                local label = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("TOPLEFT", 4, sy)
                label:SetTextColor(0.6, 0.6, 0.6, 1)
                label:SetText("No buttons collected yet. Enable the drawer and reload.")
            end
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "minimap", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- DATATEXT PANEL (Minimap)
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("datatextPanel", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db then return 80 end
        if not db.datatext then db.datatext = {} end
        local dt = db.datatext
        local QUICore = ns.Addon
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh()
            if _G.QUI_RefreshMinimap then _G.QUI_RefreshMinimap() end
            if QUICore and QUICore.Datatexts and QUICore.Datatexts.UpdateAll then
                QUICore.Datatexts:UpdateAll()
            end
        end

        -- Build datatext dropdown options
        local dtOptions = {{value = "", text = "(empty)"}}
        if QUICore and QUICore.Datatexts then
            local allDatatexts = QUICore.Datatexts:GetAll()
            for _, datatextDef in ipairs(allDatatexts) do
                table.insert(dtOptions, {value = datatextDef.id, text = datatextDef.displayName})
            end
        end

        -- Ensure slot tables
        if not dt.slots then dt.slots = {"time", "friends", "guild"} end
        if not dt.slot1 then dt.slot1 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if not dt.slot2 then dt.slot2 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end
        if not dt.slot3 then dt.slot3 = { shortLabel = false, noLabel = false, xOffset = 0, yOffset = 0 } end

        -- Panel Settings
        U.CreateCollapsible(content, "Panel Settings", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Force Single Line", "forceSingleLine", dt, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Panel Height (Per Row)", 18, 50, 1, "height", dt, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Background Transparency", 0, 100, 5, "bgOpacity", dt, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Size (0=hidden)", 0, 8, 1, "borderSize", dt, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", dt, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Vertical Offset", -40, 40, 1, "offsetY", dt, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Text Size", 9, 18, 1, "fontSize", dt, Refresh), body, sy)
        end, sections, relayout)

        -- Slot Configuration
        U.CreateCollapsible(content, "Slot Configuration", 15 * FORM_ROW + 30, function(body)
            local sy = -4

            -- Slot 1
            local s1dd = GUI:CreateFormDropdown(body, "Slot 1 (Left)", dtOptions, nil, nil, function(val)
                dt.slots[1] = val; Refresh()
            end)
            if s1dd.SetValue then s1dd:SetValue(dt.slots[1] or "", true) end
            sy = P(s1dd, body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Slot 1 Short Label", "shortLabel", dt.slot1, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Slot 1 No Label", "noLabel", dt.slot1, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Slot 1 X Offset", -50, 50, 1, "xOffset", dt.slot1, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Slot 1 Y Offset", -20, 20, 1, "yOffset", dt.slot1, Refresh), body, sy)

            -- Slot 2
            local s2dd = GUI:CreateFormDropdown(body, "Slot 2 (Center)", dtOptions, nil, nil, function(val)
                dt.slots[2] = val; Refresh()
            end)
            if s2dd.SetValue then s2dd:SetValue(dt.slots[2] or "", true) end
            sy = P(s2dd, body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Slot 2 Short Label", "shortLabel", dt.slot2, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Slot 2 No Label", "noLabel", dt.slot2, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Slot 2 X Offset", -50, 50, 1, "xOffset", dt.slot2, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Slot 2 Y Offset", -20, 20, 1, "yOffset", dt.slot2, Refresh), body, sy)

            -- Slot 3
            local s3dd = GUI:CreateFormDropdown(body, "Slot 3 (Right)", dtOptions, nil, nil, function(val)
                dt.slots[3] = val; Refresh()
            end)
            if s3dd.SetValue then s3dd:SetValue(dt.slots[3] or "", true) end
            sy = P(s3dd, body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Slot 3 Short Label", "shortLabel", dt.slot3, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Slot 3 No Label", "noLabel", dt.slot3, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Slot 3 X Offset", -50, 50, 1, "xOffset", dt.slot3, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Slot 3 Y Offset", -20, 20, 1, "yOffset", dt.slot3, Refresh), body, sy)
        end, sections, relayout)

        -- Text Styling
        U.CreateCollapsible(content, "Text Styling", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", dt, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Custom Text Color", "valueColor", dt, Refresh), body, sy)

            -- Note about global scope
            local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            note:SetPoint("TOPLEFT", 4, sy)
            note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
            note:SetTextColor(0.6, 0.6, 0.6, 0.8)
            note:SetText("Applies to all datatext panels")
            note:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Contextual: Spec Display (if any slot has "playerspec")
        local hasSpec = false
        for i = 1, 3 do
            if dt.slots[i] == "playerspec" then hasSpec = true; break end
        end
        if hasSpec then
            U.CreateCollapsible(content, "Spec Display", 1 * FORM_ROW + 20, function(body)
                local sy = -4
                local specOpts = {
                    {value = "icon", text = "Icon Only"},
                    {value = "loadout", text = "Icon + Loadout"},
                    {value = "full", text = "Full (Spec / Loadout)"},
                }
                P(GUI:CreateFormDropdown(body, "Spec Display Mode", specOpts, "specDisplayMode", dt, Refresh), body, sy)

                local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                note:SetPoint("TOPLEFT", 4, sy - FORM_ROW)
                note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                note:SetTextColor(0.6, 0.6, 0.6, 0.8)
                note:SetText("Applies to all panels with Spec datatext")
                note:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        -- Contextual: Time Options (if any slot has "time")
        local hasTime = false
        for i = 1, 3 do
            if dt.slots[i] == "time" then hasTime = true; break end
        end
        if hasTime then
            U.CreateCollapsible(content, "Time Options", 3 * FORM_ROW + 20, function(body)
                local sy = -4
                sy = P(GUI:CreateFormDropdown(body, "Time Format", {
                    {value = "local", text = "Local Time"},
                    {value = "server", text = "Server Time"},
                }, "timeFormat", dt, Refresh), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Clock Format", {
                    {value = true, text = "24-Hour Clock"},
                    {value = false, text = "AM/PM"},
                }, "use24Hour", dt, Refresh), body, sy)
                P(GUI:CreateFormSlider(body, "Lockout Refresh (minutes)", 1, 30, 1, "lockoutCacheMinutes", dt, nil), body, sy)

                local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                note:SetPoint("TOPLEFT", 4, sy - FORM_ROW)
                note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                note:SetTextColor(0.6, 0.6, 0.6, 0.8)
                note:SetText("Applies to all panels with Time datatext")
                note:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        -- Contextual: Currencies (if any slot has "currencies")
        local hasCurrencies = false
        for i = 1, 3 do
            if dt.slots[i] == "currencies" then hasCurrencies = true; break end
        end
        if hasCurrencies then
            -- Get tracked currencies
            local trackedCurrencies = {}
            if _G.C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
                local i = 1
                local seen = {}
                while true do
                    local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                    if not info then break end
                    local currencyID = info.currencyTypesID or info.currencyID
                    if currencyID and info.name and not seen[currencyID] then
                        seen[currencyID] = true
                        trackedCurrencies[#trackedCurrencies + 1] = {
                            value = tostring(currencyID),
                            text = info.name,
                        }
                    end
                    i = i + 1
                end
            end

            -- Sync order
            if type(dt.currencyOrder) ~= "table" then dt.currencyOrder = {} end
            if type(dt.currencyEnabled) ~= "table" then dt.currencyEnabled = {} end

            local trackedById = {}
            for _, c in ipairs(trackedCurrencies) do trackedById[c.value] = c end

            local ordered = {}
            local seen = {}
            for _, rawVal in ipairs(dt.currencyOrder) do
                local val = type(rawVal) == "number" and tostring(rawVal) or rawVal
                if val and val ~= "" and val ~= "none" and trackedById[val] and not seen[val] then
                    seen[val] = true
                    ordered[#ordered + 1] = val
                end
            end
            for _, c in ipairs(trackedCurrencies) do
                if not seen[c.value] then
                    ordered[#ordered + 1] = c.value
                end
            end
            dt.currencyOrder = ordered

            -- Ensure enabled table
            for _, cid in ipairs(ordered) do
                if dt.currencyEnabled[cid] == nil then dt.currencyEnabled[cid] = true end
            end

            local rowCount = math.max(#ordered, 1)
            U.CreateCollapsible(content, "Currencies", rowCount * FORM_ROW + 28, function(body)
                local sy = -4

                local note = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                note:SetPoint("TOPLEFT", 4, sy)
                note:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                note:SetTextColor(0.6, 0.6, 0.6, 0.8)
                note:SetText("First 6 enabled are displayed. Use arrows to reorder.")
                note:SetJustifyH("LEFT")
                sy = sy - 18

                if #ordered == 0 then
                    local empty = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    empty:SetPoint("TOPLEFT", 4, sy)
                    empty:SetTextColor(0.6, 0.6, 0.6, 1)
                    empty:SetText("No tracked currencies. Track currencies via the backpack.")
                else
                    local rowFrames = {}
                    local function RebuildCurrencyRows()
                        -- Hide all existing
                        for _, rf in ipairs(rowFrames) do rf:Hide() end

                        local ry = sy
                        for idx, cid in ipairs(dt.currencyOrder) do
                            local cInfo = trackedById[cid]
                            local displayName = cInfo and cInfo.text or cid

                            local row = rowFrames[idx]
                            if not row then
                                row = CreateFrame("Frame", nil, body)
                                row:SetHeight(FORM_ROW - 4)
                                rowFrames[idx] = row
                            end
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, ry)
                            row:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                            row:Show()

                            -- Reuse or create children
                            if not row._built then
                                row._cb = GUI:CreateFormCheckbox(row, "", nil, nil, nil)
                                row._cb:SetPoint("LEFT", 4, 0)
                                row._cb:SetHeight(FORM_ROW - 4)

                                row._upBtn = CreateFrame("Button", nil, row)
                                row._upBtn:SetSize(16, 16)
                                row._upBtn:SetPoint("RIGHT", row, "RIGHT", -24, 0)
                                row._upBtn:SetNormalFontObject("GameFontNormalSmall")
                                row._upBtn:SetText("^")
                                row._upBtn:GetFontString():SetTextColor(0.376, 0.647, 0.980, 1)

                                row._downBtn = CreateFrame("Button", nil, row)
                                row._downBtn:SetSize(16, 16)
                                row._downBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                                row._downBtn:SetNormalFontObject("GameFontNormalSmall")
                                row._downBtn:SetText("v")
                                row._downBtn:GetFontString():SetTextColor(0.376, 0.647, 0.980, 1)

                                row._built = true
                            end

                            -- Update checkbox
                            row._cb.label:SetText(displayName)
                            row._cb:SetChecked(dt.currencyEnabled[cid] ~= false)
                            row._cb:SetScript("OnClick", function(self)
                                dt.currencyEnabled[cid] = self:GetChecked()
                                Refresh()
                                NotifyProviderFor(row._cb, { structural = true })
                            end)

                            -- Up button
                            local capturedIdx = idx
                            row._upBtn:SetScript("OnClick", function()
                                if capturedIdx > 1 then
                                    local o = dt.currencyOrder
                                    o[capturedIdx], o[capturedIdx - 1] = o[capturedIdx - 1], o[capturedIdx]
                                    RebuildCurrencyRows()
                                    Refresh()
                                    NotifyProviderFor(row._upBtn, { structural = true })
                                end
                            end)
                            row._upBtn:SetAlpha(idx > 1 and 1 or 0.3)

                            -- Down button
                            row._downBtn:SetScript("OnClick", function()
                                if capturedIdx < #dt.currencyOrder then
                                    local o = dt.currencyOrder
                                    o[capturedIdx], o[capturedIdx + 1] = o[capturedIdx + 1], o[capturedIdx]
                                    RebuildCurrencyRows()
                                    Refresh()
                                    NotifyProviderFor(row._downBtn, { structural = true })
                                end
                            end)
                            row._downBtn:SetAlpha(idx < #dt.currencyOrder and 1 or 0.3)

                            ry = ry - FORM_ROW
                        end

                        -- Update body height
                        local realHeight = math.abs(sy) + #dt.currencyOrder * FORM_ROW + 8
                        body:SetHeight(realHeight)
                        local sec = body:GetParent()
                        if sec and sec._expanded then
                            sec._contentHeight = realHeight
                            sec:SetHeight((U.HEADER_HEIGHT or 24) + realHeight)
                            relayout()
                        end
                    end

                    RebuildCurrencyRows()
                end

                local globalNote = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                globalNote:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
                globalNote:SetPoint("RIGHT", body, "RIGHT", -4, 0)
                globalNote:SetTextColor(0.6, 0.6, 0.6, 0.8)
                globalNote:SetText("Applies to all panels with Currencies datatext")
                globalNote:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        U.BuildPositionCollapsible(content, "datatextPanel", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- EXTRA ACTION BUTTON
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("extraActionButton", { build = function(content, key, width)
        local db = U.GetProfileDB()
        local bars = db and db.actionBars and db.actionBars.bars
        local eab = bars and bars.extraActionButton
        if not eab then return 80 end
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshExtraButtons then _G.QUI_RefreshExtraButtons() end end

        U.CreateCollapsible(content, "General", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Scale", 0.5, 2.0, 0.05, "scale", eab, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Artwork", "hideArtwork", eab, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Mouseover Fade", "fadeEnabled", eab, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "extraActionButton", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- ZONE ABILITY
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("zoneAbility", { build = function(content, key, width)
        local db = U.GetProfileDB()
        local bars = db and db.actionBars and db.actionBars.bars
        local za = bars and bars.zoneAbility
        if not za then return 80 end
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshExtraButtons then _G.QUI_RefreshExtraButtons() end end

        U.CreateCollapsible(content, "General", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Scale", 0.5, 2.0, 0.05, "scale", za, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Artwork", "hideArtwork", za, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Mouseover Fade", "fadeEnabled", za, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "zoneAbility", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- TOP CENTER WIDGETS
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("topCenterWidgets", { build = function(content, key, width)
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        U.BuildPositionCollapsible(content, "topCenterWidgets", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- BELOW MINIMAP WIDGETS
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("belowMinimapWidgets", { build = function(content, key, width)
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        U.BuildPositionCollapsible(content, "belowMinimapWidgets", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- TOTEM BAR
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("totemBar", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.totemBar then return 80 end
        local tb = db.totemBar
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshTotemBar then _G.QUI_RefreshTotemBar() end end

        U.CreateCollapsible(content, "Layout", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Grow Direction", {{value="RIGHT",text="Right"},{value="LEFT",text="Left"},{value="DOWN",text="Down"},{value="UP",text="Up"}}, "growDirection", tb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 20, 80, 1, "iconSize", tb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Spacing", 0, 20, 1, "spacing", tb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 6, 1, "borderSize", tb, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Icon Zoom", 0, 0.15, 0.01, "zoom", tb, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Duration & Cooldown", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Duration Text", "hideDurationText", tb, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Duration Text Size", 8, 24, 1, "durationSize", tb, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Show Cooldown Swipe", "showSwipe", tb, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "totemBar", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- ACTION TRACKER
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("actionTracker", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.general then return 80 end
        if type(db.general.actionTracker) ~= "table" then db.general.actionTracker = {} end
        local at = db.general.actionTracker
        U.EnsureDefaults(at, {
            enabled = false, onlyInCombat = true, clearOnCombatEnd = true,
            inactivityFadeEnabled = false, inactivityFadeSeconds = 20, clearOnInactivity = false,
            showFailedCasts = true, maxEntries = 6, iconSize = 28, iconSpacing = 4,
            iconHideBorder = false, iconBorderUseClassColor = false, iconBorderColor = {0,0,0,0.85},
            orientation = "VERTICAL", invertScrollDirection = false,
            showBackdrop = true, hideBorder = false, borderSize = 1,
            backdropColor = {0,0,0,0.6}, borderColor = {0,0,0,1}, blocklistText = "",
        })
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshActionTracker then _G.QUI_RefreshActionTracker() end end

        -- Behavior
        U.CreateCollapsible(content, "Behavior", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Only Show In Combat", "onlyInCombat", at, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Clear History On Combat End", "clearOnCombatEnd", at, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Enable Inactivity Fade-Out", "inactivityFadeEnabled", at, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Inactivity Timeout (sec)", 10, 60, 1, "inactivityFadeSeconds", at, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Clear History After Inactivity", "clearOnInactivity", at, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Show Failed/Interrupted Casts", "showFailedCasts", at, Refresh), body, sy)
        end, sections, relayout)

        -- Layout
        local orientationOpts = {{value="VERTICAL",text="Vertical"},{value="HORIZONTAL",text="Horizontal"}}
        U.CreateCollapsible(content, "Layout", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Bar Orientation", orientationOpts, "orientation", at, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Invert Scroll Direction", "invertScrollDirection", at, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Max Entries", 3, 10, 1, "maxEntries", at, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 16, 64, 1, "iconSize", at, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Icon Spacing", 0, 24, 1, "iconSpacing", at, Refresh), body, sy)
        end, sections, relayout)

        -- Icon Border
        U.CreateCollapsible(content, "Icon Border", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Icon Borders", "iconHideBorder", at, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Icon Borders", "iconBorderUseClassColor", at, Refresh), body, sy)
            P(GUI:CreateFormColorPicker(body, "Icon Border Color", "iconBorderColor", at, Refresh), body, sy)
        end, sections, relayout)

        -- Container Backdrop & Border
        U.CreateCollapsible(content, "Backdrop & Border", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Container Background", "showBackdrop", at, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Container Background Color", "backdropColor", at, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Container Border", "hideBorder", at, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 5, 0.5, "borderSize", at, Refresh), body, sy)
            P(GUI:CreateFormColorPicker(body, "Container Border Color", "borderColor", at, Refresh), body, sy)
        end, sections, relayout)

        -- Spell Blocklist
        U.CreateCollapsible(content, "Spell Blocklist", FORM_ROW + 22 + 8, function(body)
            local sy = -4
            local blocklistField = GUI:CreateFormEditBox(body, "Spell Blocklist IDs", "blocklistText", at, Refresh, {
                maxLetters = 300, live = true,
                onEditFocusGained = function(self) self:HighlightText() end,
            })
            blocklistField:SetPoint("TOPLEFT", 0, sy)
            blocklistField:SetPoint("RIGHT", body, "RIGHT", 0, 0)

            local blocklistPlaceholder = blocklistField:CreateFontString(nil, "OVERLAY")
            blocklistPlaceholder:SetFont(GUI.FONT_PATH, 11, "")
            blocklistPlaceholder:SetPoint("LEFT", blocklistField.editBox, "LEFT", 0, 0)
            blocklistPlaceholder:SetText("Example: 61304, 75, 133")
            blocklistPlaceholder:SetTextColor(0.6, 0.6, 0.6, 0.7)

            local function UpdatePlaceholder()
                blocklistPlaceholder:SetShown((blocklistField.editBox:GetText() or "") == "")
            end
            blocklistField.editBox:HookScript("OnTextChanged", UpdatePlaceholder)
            UpdatePlaceholder()
            sy = sy - FORM_ROW

            local helpLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            helpLabel:SetPoint("TOPLEFT", 0, sy + 4)
            helpLabel:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            helpLabel:SetTextColor(0.6, 0.6, 0.6, 0.8)
            helpLabel:SetText("Comma-separated spell IDs to ignore in the tracker.")
            helpLabel:SetJustifyH("LEFT")
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "actionTracker", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- PREY TRACKER
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("preyTracker", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.preyTracker then return 80 end
        local pt = db.preyTracker
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshPreyTracker then _G.QUI_RefreshPreyTracker() end end
        local function RefreshPreview()
            Refresh()
            if _G.QUI_TogglePreyTrackerPreview then _G.QUI_TogglePreyTrackerPreview(true) end
        end

        -- General
        U.CreateCollapsible(content, "General", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Bar Width", 100, 500, 1, "width", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Bar Height", 10, 40, 1, "height", pt, RefreshPreview), body, sy)
            P(GUI:CreateFormSlider(body, "Border Size", 0, 3, 1, "borderSize", pt, RefreshPreview), body, sy)
        end, sections, relayout)

        -- Bar Appearance
        local colorModeOptions = {
            { value = "accent", text = "Accent Color" },
            { value = "class", text = "Class Color" },
            { value = "custom", text = "Custom Color" },
        }
        local function GetColorMode()
            if pt.barUseClassColor then return "class"
            elseif pt.barUseAccentColor then return "accent"
            else return "custom"
            end
        end
        U.CreateCollapsible(content, "Bar Appearance", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "texture", pt, RefreshPreview), body, sy)

            local colorModeDropdown = GUI:CreateFormDropdown(body, "Bar Color Mode", colorModeOptions, nil, nil, function() end)
            colorModeDropdown:SetPoint("TOPLEFT", 0, sy)
            colorModeDropdown:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            local dropdownBtn
            for _, child in ipairs({ colorModeDropdown:GetChildren() }) do
                if child.GetObjectType and child:GetObjectType() == "Button" then
                    dropdownBtn = child
                    break
                end
            end
            if dropdownBtn then
                local currentMode = GetColorMode()
                for _, opt in ipairs(colorModeOptions) do
                    if opt.value == currentMode then
                        local btnText = dropdownBtn:GetFontString()
                        if btnText then btnText:SetText(opt.text) end
                        break
                    end
                end
                dropdownBtn:SetScript("OnClick", function(self)
                    local menuItems = {}
                    for _, opt in ipairs(colorModeOptions) do
                        table.insert(menuItems, {
                            text = opt.text,
                            checked = (opt.value == GetColorMode()),
                            func = function()
                                pt.barUseClassColor = (opt.value == "class")
                                pt.barUseAccentColor = (opt.value == "accent")
                                local btnText2 = self:GetFontString()
                                if btnText2 then btnText2:SetText(opt.text) end
                                RefreshPreview()
                                NotifyProviderFor(colorModeDropdown)
                            end,
                        })
                    end
                    if GUI.ShowDropdownMenu then GUI:ShowDropdownMenu(self, menuItems) end
                end)
            end
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormColorPicker(body, "Custom Bar Color", "barColor", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Override Background Color", "barBgOverride", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "barBackgroundColor", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Override Border Color", "borderOverride", pt, RefreshPreview), body, sy)
            P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", pt, RefreshPreview), body, sy)
        end, sections, relayout)

        -- Text & Display
        local textFormatOptions = {
            { value = "stage_pct", text = "Stage 3 — 67%" },
            { value = "pct_only", text = "67%" },
            { value = "stage_only", text = "Stage 3" },
            { value = "name_pct", text = "Prey Name — 67%" },
        }
        local tickStyleOptions = {
            { value = "thirds", text = "Thirds (33% / 66%)" },
            { value = "quarters", text = "Quarters (25% / 50% / 75%)" },
        }
        U.CreateCollapsible(content, "Text & Display", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Text", "showText", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Text Format", textFormatOptions, "textFormat", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 18, 1, "textSize", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Tick Marks", "showTickMarks", pt, RefreshPreview), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Tick Style", tickStyleOptions, "tickStyle", pt, RefreshPreview), body, sy)
            P(GUI:CreateFormCheckbox(body, "Show Spark", "showSpark", pt, RefreshPreview), body, sy)
        end, sections, relayout)

        -- Sounds
        U.CreateCollapsible(content, "Sounds", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Sounds", "soundEnabled", pt, nil), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Stage 2 Sound", "soundStage2", pt, nil), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Stage 3 Sound", "soundStage3", pt, nil), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Stage 4 Sound", "soundStage4", pt, nil), body, sy)
            P(GUI:CreateFormCheckbox(body, "Completion Sound", "completionSound", pt, nil), body, sy)
        end, sections, relayout)

        -- Ambush Alerts
        U.CreateCollapsible(content, "Ambush Alerts", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Ambush Alerts", "ambushAlertEnabled", pt, nil), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Ambush Sound", "ambushSoundEnabled", pt, nil), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Ambush Glow Effect", "ambushGlowEnabled", pt, nil), body, sy)
            P(GUI:CreateFormSlider(body, "Glow Duration (sec)", 2, 15, 1, "ambushDuration", pt, nil), body, sy)
        end, sections, relayout)

        -- Visibility
        U.CreateCollapsible(content, "Visibility", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Replace Default Prey Indicator", "replaceDefaultIndicator", pt, function()
                if ns.QUI_PreyTracker and ns.QUI_PreyTracker.ToggleDefaultIndicator then
                    ns.QUI_PreyTracker.ToggleDefaultIndicator(pt.replaceDefaultIndicator)
                end
            end), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto-Hide When No Progress", "autoHide", pt, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide in Instances", "hideInInstances", pt, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Outside Prey Zone", "hideOutsidePreyZone", pt, Refresh), body, sy)
        end, sections, relayout)

        -- Hunt Scanner
        U.CreateCollapsible(content, "Hunt Scanner", 1 * FORM_ROW + 8, function(body)
            local sy = -4
            P(GUI:CreateFormCheckbox(body, "Enable Hunt Scanner", "huntScannerEnabled", pt, nil), body, sy)
        end, sections, relayout)

        -- Currency Tracker
        U.CreateCollapsible(content, "Currency Tracker", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Enable Currency Tooltip", "currencyEnabled", pt, nil), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Session Gains", "currencyShowSession", pt, nil), body, sy)
            P(GUI:CreateFormCheckbox(body, "Show Weekly Progress", "currencyShowWeekly", pt, nil), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "preyTracker", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- CONSUMABLES PROVIDER
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("consumables", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.general then return 80 end
        local settings = db.general
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh()
            if _G.QUI_RefreshConsumables then _G.QUI_RefreshConsumables() end
        end

        U.CreateCollapsible(content, "Triggers", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Ready Check", "consumableOnReadyCheck", settings), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Dungeon Entrance", "consumableOnDungeon", settings), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Raid Entrance", "consumableOnRaid", settings), body, sy)
            P(GUI:CreateFormCheckbox(body, "Instanced Resurrect", "consumableOnResurrect", settings), body, sy)
        end, sections, relayout)

        local mhLabel = (ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetMHLabel() or "Weapon Oil") .. " (MH)"
        local ohLabel = (ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetOHLabel() or "Weapon Oil") .. " (OH)"
        U.CreateCollapsible(content, "Buff Checks", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Food Buff", "consumableFood", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Flask Buff", "consumableFlask", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, mhLabel, "consumableOilMH", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, ohLabel, "consumableOilOH", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Augment Rune", "consumableRune", settings, Refresh), body, sy)
            P(GUI:CreateFormCheckbox(body, "Healthstones", "consumableHealthstone", settings, Refresh), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Expiration Warning", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Warn When Buffs Expiring", "consumableExpirationWarning", settings), body, sy)
            P(GUI:CreateFormSlider(body, "Warning Threshold (seconds)", 60, 600, 30, "consumableExpirationThreshold", settings), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Display", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Always Show (Persistent)", "consumablePersistent", settings, function()
                if settings.consumablePersistent then
                    if _G.QUI_ShowConsumables then _G.QUI_ShowConsumables() end
                else
                    if _G.QUI_HideConsumables then _G.QUI_HideConsumables() end
                end
            end), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 24, 64, 2, "consumableIconSize", settings, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Scale", 0.5, 3, 0.05, "consumableScale", settings, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "consumables", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- POSITION-ONLY PROVIDERS
    ---------------------------------------------------------------------------
    for _, providerKey in ipairs({"rangeCheck", "crosshair",
            "lootFrame", "lootRollAnchor", "alertAnchor",
            "toastAnchor", "bnetToastAnchor", "powerBarAlt"}) do
        settingsPanel:RegisterProvider(providerKey, { build = function(content, key, width)
            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end
            U.BuildPositionCollapsible(content, providerKey, nil, sections, relayout)
            relayout() return content:GetHeight()
        end })
    end
    ---------------------------------------------------------------------------
    -- CASTBARS (player, target, focus)
    ---------------------------------------------------------------------------
    local CASTBAR_UNITS = {
        { key = "playerCastbar", unit = "player" },
        { key = "targetCastbar", unit = "target" },
        { key = "focusCastbar",  unit = "focus" },
        { key = "petCastbar",    unit = "pet" },
        { key = "totCastbar",    unit = "targettarget" },
    }

    local NINE_POINT = {
        {value = "TOPLEFT", text = "Top Left"}, {value = "TOP", text = "Top"},
        {value = "TOPRIGHT", text = "Top Right"}, {value = "LEFT", text = "Left"},
        {value = "CENTER", text = "Center"}, {value = "RIGHT", text = "Right"},
        {value = "BOTTOMLEFT", text = "Bottom Left"}, {value = "BOTTOM", text = "Bottom"},
        {value = "BOTTOMRIGHT", text = "Bottom Right"},
    }

    for _, cbInfo in ipairs(CASTBAR_UNITS) do
        settingsPanel:RegisterProvider(cbInfo.key, { build = function(content, key, width)
            local db = U.GetProfileDB()
            if not db or not db.quiUnitFrames then return 80 end
            local unitDB = db.quiUnitFrames[cbInfo.unit]
            if not unitDB or not unitDB.castbar then return 80 end
            local castDB = unitDB.castbar
            local unitKey = cbInfo.unit

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end
            local function Refresh()
                if _G.QUI_RefreshCastbar then _G.QUI_RefreshCastbar(unitKey) end
            end

            -- Lightweight preview: resize the existing castbar frame from DB
            -- values without a full destroy+recreate. The full Refresh fires on
            -- mouse release to rebuild properly.
            local function PreviewSize()
                local QUI_Castbar = ns.QUI_Castbar
                local cb = QUI_Castbar and QUI_Castbar.castbars and QUI_Castbar.castbars[unitKey]
                if not cb then return end
                local w = castDB.width or 200
                local h = castDB.height or 25
                cb:SetSize(w, h)
            end

            -- Standalone Mode (player only) — keeps castbar when UF is disabled
            if unitKey == "player" then
                local standaloneRow = CreateFrame("Frame", nil, content)
                standaloneRow:SetHeight(FORM_ROW)
                local standaloneCheck = GUI:CreateFormCheckbox(standaloneRow, "Standalone Mode (when UF disabled)", "standaloneCastbar", unitDB, function()
                    if _G.QUI_ToggleStandaloneCastbar then _G.QUI_ToggleStandaloneCastbar() end
                end)
                standaloneCheck:SetPoint("TOPLEFT", 0, 0)
                standaloneCheck:SetPoint("RIGHT", standaloneRow, "RIGHT", 0, 0)
                sections[#sections + 1] = standaloneRow
            end

            -- General
            local generalRows = 5
            if unitKey == "player" then generalRows = generalRows + 1 end  -- class color
            if unitKey == "target" or unitKey == "focus" then generalRows = generalRows + 1 end  -- uninterruptible color
            local DEFER = { deferOnDrag = true }
            local DEFER_SIZE = { deferOnDrag = true, onDragPreview = PreviewSize }

            U.CreateCollapsible(content, "General", generalRows * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Spell Icon", "showIcon", castDB, Refresh), body, sy)
                if unitKey == "player" then
                    sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", castDB, Refresh), body, sy)
                end
                sy = P(GUI:CreateFormColorPicker(body, "Castbar Color", "color", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", castDB, Refresh), body, sy)
                if unitKey == "target" or unitKey == "focus" then
                    sy = P(GUI:CreateFormColorPicker(body, "Uninterruptible Color", "notInterruptibleColor", castDB, Refresh), body, sy)
                end
                sy = P(GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "texture", castDB, Refresh), body, sy)
                P(GUI:CreateFormSlider(body, "Border Size", 0, 5, 1, "borderSize", castDB, Refresh, DEFER), body, sy)
            end, sections, relayout)

            -- GCD (player only)
            if unitKey == "player" then
                if castDB.showGCD == nil then castDB.showGCD = false end
                if castDB.showGCDReverse == nil then castDB.showGCDReverse = false end
                if castDB.showGCDMelee == nil then castDB.showGCDMelee = false end
                if castDB.gcdColor == nil then
                    local c = castDB.color or {1, 1, 1, 1}
                    castDB.gcdColor = {c[1], c[2], c[3], c[4] or 1}
                end
                U.CreateCollapsible(content, "GCD", 4 * FORM_ROW + 8, function(body)
                    local sy = -4
                    sy = P(GUI:CreateFormCheckbox(body, "Show GCD as Castbar", "showGCD", castDB, Refresh), body, sy)
                    sy = P(GUI:CreateFormCheckbox(body, "Reverse Direction", "showGCDReverse", castDB, Refresh), body, sy)
                    sy = P(GUI:CreateFormCheckbox(body, "Show Melee", "showGCDMelee", castDB, Refresh), body, sy)
                    P(GUI:CreateFormColorPicker(body, "GCD Bar Color", "gcdColor", castDB, Refresh), body, sy)
                end, sections, relayout)
            end

            -- Size
            if castDB.widthAdjustment == nil then castDB.widthAdjustment = 0 end
            U.CreateCollapsible(content, "Size", 5 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormSlider(body, "Width", 50, 2000, 1, "width", castDB, Refresh, DEFER_SIZE), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Width Adjustment (Anchor)", -50, 50, 1, "widthAdjustment", castDB, Refresh, DEFER_SIZE), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Bar Height", 4, 60, 1, "height", castDB, Refresh, DEFER_SIZE), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Size", 8, 80, 1, "iconSize", castDB, Refresh, DEFER_SIZE), body, sy)
                P(GUI:CreateFormCheckbox(body, "Channel Fill Forward", "channelFillForward", castDB, Refresh), body, sy)
            end, sections, relayout)

            -- Channel Ticks (not for pet/tot)
            if unitKey ~= "pet" and unitKey ~= "targettarget" then
            U.CreateCollapsible(content, "Channel Ticks", 4 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Channel Tick Markers", "showChannelTicks", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Tick Thickness", 1, 5, 0.5, "channelTickThickness", castDB, Refresh, DEFER), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Tick Color", "channelTickColor", castDB, Refresh), body, sy)
                local tickSourceOptions = {
                    {value = "auto", text = "Auto (Static then Runtime)"},
                    {value = "static", text = "Static Only"},
                    {value = "runtimeOnly", text = "Runtime Calibration Only"},
                }
                P(GUI:CreateFormDropdown(body, "Tick Source", tickSourceOptions, "channelTickSourcePolicy", castDB, Refresh), body, sy)
            end, sections, relayout)
            end

            -- Text & Display
            U.CreateCollapsible(content, "Text & Display", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 24, 1, "fontSize", castDB, Refresh, DEFER), body, sy)
                P(GUI:CreateFormSlider(body, "Max Length (0=none)", 0, 30, 1, "maxLength", castDB, Refresh, DEFER), body, sy)
            end, sections, relayout)

            -- Element Positioning
            if castDB.iconAnchor == nil then castDB.iconAnchor = "LEFT" end
            if castDB.iconSpacing == nil then castDB.iconSpacing = 0 end
            if castDB.spellTextAnchor == nil then castDB.spellTextAnchor = "LEFT" end
            if castDB.spellTextOffsetX == nil then castDB.spellTextOffsetX = 4 end
            if castDB.spellTextOffsetY == nil then castDB.spellTextOffsetY = 0 end
            if castDB.showSpellText == nil then castDB.showSpellText = true end
            if castDB.timeTextAnchor == nil then castDB.timeTextAnchor = "RIGHT" end
            if castDB.timeTextOffsetX == nil then castDB.timeTextOffsetX = -4 end
            if castDB.timeTextOffsetY == nil then castDB.timeTextOffsetY = 0 end
            if castDB.showTimeText == nil then castDB.showTimeText = true end
            if castDB.iconBorderSize == nil then castDB.iconBorderSize = 2 end
            if castDB.iconScale == nil then castDB.iconScale = 1.0 end

            U.CreateCollapsible(content, "Icon Settings", 5 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormDropdown(body, "Icon Anchor", NINE_POINT, "iconAnchor", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormToggle(body, "Show Icon", "showIcon", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Spacing", -50, 50, 1, "iconSpacing", castDB, Refresh, DEFER), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Icon Border Size", 0, 5, 0.1, "iconBorderSize", castDB, Refresh, { precision = 1, deferOnDrag = true }), body, sy)
                P(GUI:CreateFormSlider(body, "Icon Scale", 0.5, 2.0, 0.1, "iconScale", castDB, Refresh, { precision = 1, deferOnDrag = true }), body, sy)
            end, sections, relayout)

            U.CreateCollapsible(content, "Spell Text", 4 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormToggle(body, "Show Spell Text", "showSpellText", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Spell Text Anchor", NINE_POINT, "spellTextAnchor", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormSlider(body, "X Offset", -200, 200, 1, "spellTextOffsetX", castDB, Refresh, DEFER), body, sy)
                P(GUI:CreateFormSlider(body, "Y Offset", -200, 200, 1, "spellTextOffsetY", castDB, Refresh, DEFER), body, sy)
            end, sections, relayout)

            U.CreateCollapsible(content, "Time Text", 4 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormToggle(body, "Show Time Text", "showTimeText", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Time Text Anchor", NINE_POINT, "timeTextAnchor", castDB, Refresh), body, sy)
                sy = P(GUI:CreateFormSlider(body, "X Offset", -200, 200, 1, "timeTextOffsetX", castDB, Refresh, DEFER), body, sy)
                P(GUI:CreateFormSlider(body, "Y Offset", -200, 200, 1, "timeTextOffsetY", castDB, Refresh, DEFER), body, sy)
            end, sections, relayout)

            -- Empowered (player only)
            if unitKey == "player" then
                if castDB.hideTimeTextOnEmpowered == nil then castDB.hideTimeTextOnEmpowered = false end
                if castDB.showEmpoweredLevel == nil then castDB.showEmpoweredLevel = false end
                if castDB.empoweredLevelTextAnchor == nil then castDB.empoweredLevelTextAnchor = "CENTER" end
                if castDB.empoweredLevelTextOffsetX == nil then castDB.empoweredLevelTextOffsetX = 0 end
                if castDB.empoweredLevelTextOffsetY == nil then castDB.empoweredLevelTextOffsetY = 0 end

                U.CreateCollapsible(content, "Empowered Casts", 4 * FORM_ROW + 8, function(body)
                    local sy = -4
                    sy = P(GUI:CreateFormToggle(body, "Hide Time Text on Empowered", "hideTimeTextOnEmpowered", castDB, Refresh), body, sy)
                    sy = P(GUI:CreateFormToggle(body, "Show Empowered Level", "showEmpoweredLevel", castDB, Refresh), body, sy)
                    sy = P(GUI:CreateFormDropdown(body, "Level Text Anchor", NINE_POINT, "empoweredLevelTextAnchor", castDB, Refresh), body, sy)
                    P(GUI:CreateFormSlider(body, "Level Text X Offset", -200, 200, 1, "empoweredLevelTextOffsetX", castDB, Refresh, DEFER), body, sy)
                end, sections, relayout)
            end

            U.BuildPositionCollapsible(content, cbInfo.key, { autoWidth = true }, sections, relayout)
            relayout() return content:GetHeight()
        end })
    end

    ---------------------------------------------------------------------------
    -- MISSING RAID BUFFS
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("missingRaidBuffs", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.raidBuffs then return 80 end
        local settings = db.raidBuffs

        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh()
            if ns.RaidBuffs and ns.RaidBuffs.Refresh then ns.RaidBuffs:Refresh() end
        end

        -- General
        U.CreateCollapsible(content, "General", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Only When In Group", "showOnlyInGroup", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Only In Dungeons/Raids", "showOnlyInInstance", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Class Self-Buffs (poisons, enchants, shields)", "showSelfBuffs", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Provider Mode (only buffs you can cast)", "providerMode", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Label Bar", "hideLabelBar", settings, Refresh), body, sy)

            local growOptions = {
                {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
                {value = "CENTER_H", text = "Center (H)"}, {value = "UP", text = "Up"},
                {value = "DOWN", text = "Down"}, {value = "CENTER_V", text = "Center (V)"},
            }
            P(GUI:CreateFormDropdown(body, "Grow Direction", growOptions, "growDirection", settings, Refresh), body, sy)
        end, sections, relayout)

        -- Appearance
        U.CreateCollapsible(content, "Appearance", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 16, 64, 1, "iconSize", settings, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Spacing", 0, 20, 1, "iconSpacing", settings, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Label Font Size", 8, 24, 1, "labelFontSize", settings, Refresh), body, sy)
        end, sections, relayout)

        -- Icon Border
        if not settings.iconBorder then
            settings.iconBorder = { show = true, width = 1, useClassColor = false, useAccentColor = false, color = {0.376, 0.647, 0.980, 1} }
        end
        local borderSettings = settings.iconBorder
        U.CreateCollapsible(content, "Icon Border", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Icon Border", "show", borderSettings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", borderSettings, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Accent Color", "useAccentColor", borderSettings, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Border Color", "color", borderSettings, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Border Width", 1, 4, 1, "width", borderSettings, Refresh), body, sy)
        end, sections, relayout)

        -- Buff Count
        if not settings.buffCount then
            settings.buffCount = { show = true, position = "BOTTOM", fontSize = 10, color = {1, 1, 1, 1} }
        end
        local countSettings = settings.buffCount
        U.CreateCollapsible(content, "Buff Count", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Buff Count", "show", countSettings, Refresh), body, sy)
            local countPosOptions = {
                {value = "TOP", text = "Top"}, {value = "BOTTOM", text = "Bottom"},
                {value = "LEFT", text = "Left"}, {value = "RIGHT", text = "Right"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Count Position", countPosOptions, "position", countSettings, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Count Font Size", 8, 18, 1, "fontSize", countSettings, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Count Color", "color", countSettings, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Count X Offset", -50, 50, 1, "offsetX", countSettings, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Count Y Offset", -50, 50, 1, "offsetY", countSettings, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "missingRaidBuffs", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- TOOLTIP
    ---------------------------------------------------------------------------
    local DEFAULT_PLAYER_ILVL_BRACKETS = {
        white = 245, green = 255, blue = 265, purple = 275, orange = 285,
    }
    local PLAYER_ILVL_BRACKET_FIELDS = {
        {key = "white", label = "White", color = {1, 1, 1, 1}},
        {key = "green", label = "Green", color = {0, 1, 0, 1}},
        {key = "blue", label = "Blue", color = {0, 0.44, 0.87, 1}},
        {key = "purple", label = "Purple", color = {0.64, 0.21, 0.93, 1}},
        {key = "orange", label = "Orange", color = {1, 0.5, 0, 1}},
    }

    settingsPanel:RegisterProvider("tooltipAnchor", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.tooltip then return 80 end
        local tooltip = db.tooltip

        -- Initialize defaults
        if tooltip.colorPlayerItemLevel == nil then tooltip.colorPlayerItemLevel = true end
        if type(tooltip.itemLevelBrackets) ~= "table" then tooltip.itemLevelBrackets = {} end
        for bkey, defaultValue in pairs(DEFAULT_PLAYER_ILVL_BRACKETS) do
            local value = tonumber(tooltip.itemLevelBrackets[bkey])
            tooltip.itemLevelBrackets[bkey] = value and math.floor(value) or defaultValue
        end
        if not tooltip.cursorAnchor then tooltip.cursorAnchor = "TOPLEFT" end
        if tooltip.cursorOffsetX == nil then tooltip.cursorOffsetX = 16 end
        if tooltip.cursorOffsetY == nil then tooltip.cursorOffsetY = -16 end
        if tooltip.hideDelay == nil then tooltip.hideDelay = 0 end

        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function RefreshTooltips() if ns.QUI_RefreshTooltips then ns.QUI_RefreshTooltips() end end
        local function RefreshTooltipFontSize()
            if ns.QUI_RefreshTooltipFontSize then ns.QUI_RefreshTooltipFontSize()
            else RefreshTooltips() end
        end
        local function RefreshTooltipSkin() if ns.QUI_RefreshTooltipSkinColors then ns.QUI_RefreshTooltipSkinColors() end end

        -- Skinning
        U.CreateCollapsible(content, "Tooltip Skinning", 1, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Skin Tooltips", "skinTooltips", tooltip, function()
                GUI:ShowConfirmation({
                    title = "Reload UI?",
                    message = "Skinning changes require a reload to take effect.",
                    acceptText = "Reload",
                    cancelText = "Later",
                    onAccept = function() QUI:SafeReload() end,
                })
            end), body, sy)

            local skinInfo = GUI:CreateLabel(body, "Apply QUI theme (colors, border) to all game tooltips.", 10, GUI.Colors.textMuted)
            skinInfo:SetPoint("TOPLEFT", 0, sy)
            skinInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            skinInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", tooltip, RefreshTooltipSkin), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1, 0.05, "bgOpacity", tooltip, RefreshTooltipSkin, {precision = 2}), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Border", "showBorder", tooltip, RefreshTooltipSkin), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Thickness", 1, 10, 1, "borderThickness", tooltip, RefreshTooltipSkin), body, sy)

            local borderColorPicker = GUI:CreateFormColorPicker(body, "Border Color", "borderColor", tooltip, RefreshTooltipSkin)
            sy = P(borderColorPicker, body, sy)

            if tooltip.borderUseClassColor and tooltip.borderUseAccentColor then
                tooltip.borderUseAccentColor = false
            end

            local accentColorBorderCheck
            local classColorBorderCheck = GUI:CreateFormCheckbox(body, "Use Class Color for Border", "borderUseClassColor", tooltip, function(val)
                if val then
                    tooltip.borderUseAccentColor = false
                    if accentColorBorderCheck and accentColorBorderCheck.SetChecked then accentColorBorderCheck:SetChecked(false) end
                end
                if borderColorPicker and borderColorPicker.SetEnabled then
                    borderColorPicker:SetEnabled(not val and not tooltip.borderUseAccentColor)
                end
                RefreshTooltipSkin()
            end)
            sy = P(classColorBorderCheck, body, sy)

            accentColorBorderCheck = GUI:CreateFormCheckbox(body, "Use Accent Color for Border", "borderUseAccentColor", tooltip, function(val)
                if val then
                    tooltip.borderUseClassColor = false
                    if classColorBorderCheck and classColorBorderCheck.SetChecked then classColorBorderCheck:SetChecked(false) end
                end
                if borderColorPicker and borderColorPicker.SetEnabled then
                    borderColorPicker:SetEnabled(not val and not tooltip.borderUseClassColor)
                end
                RefreshTooltipSkin()
            end)
            sy = P(accentColorBorderCheck, body, sy)

            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(not tooltip.borderUseClassColor and not tooltip.borderUseAccentColor)
            end

            sy = P(GUI:CreateFormCheckbox(body, "Hide Health Bar", "hideHealthBar", tooltip, RefreshTooltips), body, sy)

            local healthInfo = GUI:CreateLabel(body, "Hide the health bar shown on player, NPC, and enemy tooltips.", 10, GUI.Colors.textMuted)
            healthInfo:SetPoint("TOPLEFT", 0, sy)
            healthInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            healthInfo:SetJustifyH("LEFT")

            local totalHeight = 12 * FORM_ROW + 8
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        -- Font & Content
        U.CreateCollapsible(content, "Font & Content", 1, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Tooltip Font Size", 8, 24, 1, "fontSize", tooltip, RefreshTooltipFontSize), body, sy)

            local fontInfo = GUI:CreateLabel(body, "Adjust tooltip text size (8-24).", 10, GUI.Colors.textMuted)
            fontInfo:SetPoint("TOPLEFT", 0, sy)
            fontInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            fontInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Show Spell/Icon IDs", "showSpellIDs", tooltip, RefreshTooltips), body, sy)

            local spellInfo = GUI:CreateLabel(body, "Display spell ID and icon ID on buff, debuff, and spell tooltips. May not work in combat.", 10, GUI.Colors.textMuted)
            spellInfo:SetPoint("TOPLEFT", 0, sy)
            spellInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            spellInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Class Color Player Names", "classColorName", tooltip, RefreshTooltips), body, sy)

            local classInfo = GUI:CreateLabel(body, "Color player names in tooltips by their class.", 10, GUI.Colors.textMuted)
            classInfo:SetPoint("TOPLEFT", 0, sy)
            classInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            classInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormSlider(body, "Hide Delay", 0, 2, 0.1, "hideDelay", tooltip, RefreshTooltips, {precision = 1}), body, sy)

            local delayInfo = GUI:CreateLabel(body, "Seconds before tooltip fades out after mouse leaves (0 = instant hide).", 10, GUI.Colors.textMuted)
            delayInfo:SetPoint("TOPLEFT", 0, sy)
            delayInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            delayInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Hide Server Name", "hideServerName", tooltip, RefreshTooltips), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Player Titles", "hidePlayerTitle", tooltip, RefreshTooltips), body, sy)

            local totalHeight = 4 * FORM_ROW + 4 * FORM_ROW + 2 * FORM_ROW + 8
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        -- Player Item Level
        U.CreateCollapsible(content, "Player Item Level", 1, function(body)
            local sy = -4

            local itemLevelColorFields = {}
            local itemLevelColorLabels = {}
            local itemLevelBracketHeader
            local itemLevelBracketInfo

            local function RefreshPlayerItemLevelBracketInputs()
                local enabled = tooltip.showPlayerItemLevel and tooltip.colorPlayerItemLevel
                if itemLevelBracketHeader then
                    itemLevelBracketHeader:SetTextColor(enabled and GUI.Colors.text[1] or GUI.Colors.textMuted[1], enabled and GUI.Colors.text[2] or GUI.Colors.textMuted[2], enabled and GUI.Colors.text[3] or GUI.Colors.textMuted[3], 1)
                end
                if itemLevelBracketInfo then
                    itemLevelBracketInfo:SetTextColor(GUI.Colors.textMuted[1], GUI.Colors.textMuted[2], GUI.Colors.textMuted[3], enabled and 1 or 0.6)
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

            sy = P(GUI:CreateFormCheckbox(body, "Show Player Item Level", "showPlayerItemLevel", tooltip, function()
                RefreshPlayerItemLevelBracketInputs()
                RefreshTooltips()
            end), body, sy)

            local ilvlInfo = GUI:CreateLabel(body, "Show average equipped item level on player tooltips. Remote players may populate after a short inspect delay.", 10, GUI.Colors.textMuted)
            ilvlInfo:SetPoint("TOPLEFT", 0, sy)
            ilvlInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            ilvlInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Color Player Item Level by Bracket", "colorPlayerItemLevel", tooltip, function()
                RefreshPlayerItemLevelBracketInputs()
                RefreshTooltips()
            end), body, sy)

            local colorInfo = GUI:CreateLabel(body, "Color by grey/white/green/blue/purple/orange brackets.", 10, GUI.Colors.textMuted)
            colorInfo:SetPoint("TOPLEFT", 0, sy)
            colorInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            colorInfo:SetJustifyH("LEFT")
            sy = sy - 20

            itemLevelBracketHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemLevelBracketHeader:SetPoint("TOPLEFT", 0, sy)
            itemLevelBracketHeader:SetText("Bracket Breakpoints")
            itemLevelBracketHeader:SetTextColor(GUI.Colors.text[1], GUI.Colors.text[2], GUI.Colors.text[3], 1)
            sy = sy - 16

            local bracketRow = CreateFrame("Frame", nil, body)
            bracketRow:SetHeight(44)
            bracketRow:SetPoint("TOPLEFT", 0, sy)
            bracketRow:SetPoint("RIGHT", body, "RIGHT", 0, 0)

            local fieldWidth = 48
            local fieldSpacing = 6
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
                local group = CreateFrame("Frame", nil, bracketRow)
                group:SetSize(fieldWidth, 40)
                group:SetPoint("TOPLEFT", previousGroup or bracketRow, previousGroup and "TOPRIGHT" or "TOPLEFT", previousGroup and fieldSpacing or 0, 0)

                local label = bracketRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
                    onEnterPressed = function(self) CommitBracketValue(field.key, self) end,
                    onEscapePressed = function(self)
                        self:SetText(tostring(tooltip.itemLevelBrackets[field.key]))
                        self:SetCursorPosition(0)
                    end,
                    onEditFocusGained = function(self) self:HighlightText() end,
                })
                fieldBg:SetPoint("TOP", label, "BOTTOM", 0, -2)

                input:HookScript("OnEditFocusLost", function(self)
                    CommitBracketValue(field.key, self)
                end)

                table.insert(itemLevelColorFields, { frame = fieldBg, input = input })
                previousGroup = group
            end

            sy = sy - 48

            itemLevelBracketInfo = GUI:CreateLabel(body, "Inclusive starts for each color bracket. Values below White use the grey bracket.", 10, GUI.Colors.textMuted)
            itemLevelBracketInfo:SetPoint("TOPLEFT", 0, sy)
            itemLevelBracketInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            itemLevelBracketInfo:SetJustifyH("LEFT")

            RefreshPlayerItemLevelBracketInputs()

            -- 2 checkboxes + 2 info labels + header + bracket row + info
            local totalHeight = 2 * FORM_ROW + 20 + FORM_ROW + 16 + 48 + FORM_ROW + 8
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        -- Cursor Anchor
        U.CreateCollapsible(content, "Cursor Anchor", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Anchor Tooltip to Cursor", "anchorToCursor", tooltip, RefreshTooltips), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Cursor Anchor Point", anchorOptions, "cursorAnchor", tooltip, RefreshTooltips), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Cursor X Offset", -200, 200, 1, "cursorOffsetX", tooltip, RefreshTooltips), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Cursor Y Offset", -200, 200, 1, "cursorOffsetY", tooltip, RefreshTooltips), body, sy)

            local info = GUI:CreateLabel(body, "Tooltip follows your mouse cursor with configurable anchor point and offsets.", 10, GUI.Colors.textMuted)
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Visibility
        if tooltip.visibility then
            local visibilityOptions = {
                {value = "SHOW", text = "Always Show"},
                {value = "HIDE", text = "Always Hide"},
                {value = "SHIFT", text = "Shift to Show"},
                {value = "CTRL", text = "Ctrl to Show"},
                {value = "ALT", text = "Alt to Show"},
            }

            U.CreateCollapsible(content, "Tooltip Visibility", 7 * FORM_ROW + 8, function(body)
                local sy = -4
                local info = GUI:CreateLabel(body, "Control tooltip visibility per element type. Choose a modifier key to only show tooltips while holding that key.", 10, GUI.Colors.textMuted)
                info:SetPoint("TOPLEFT", 0, sy)
                info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                info:SetJustifyH("LEFT")
                sy = sy - 24

                sy = P(GUI:CreateFormDropdown(body, "NPCs & Players", visibilityOptions, "npcs", tooltip.visibility, RefreshTooltips), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Abilities", visibilityOptions, "abilities", tooltip.visibility, RefreshTooltips), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Inventory", visibilityOptions, "items", tooltip.visibility, RefreshTooltips), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Frames", visibilityOptions, "frames", tooltip.visibility, RefreshTooltips), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Cooldown Manager", visibilityOptions, "cdm", tooltip.visibility, RefreshTooltips), body, sy)
                P(GUI:CreateFormDropdown(body, "Custom Items/Spells", visibilityOptions, "customTrackers", tooltip.visibility, RefreshTooltips), body, sy)
            end, sections, relayout)
        end

        -- Combat
        U.CreateCollapsible(content, "Combat", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Tooltips in Combat", "hideInCombat", tooltip, RefreshTooltips), body, sy)

            local info = GUI:CreateLabel(body, "Suppresses tooltips during combat. Use the modifier key below to force-show tooltips when needed.", 10, GUI.Colors.textMuted)
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
            sy = sy - 24

            local combatOverrideOptions = {
                {value = "NONE", text = "None"},
                {value = "SHIFT", text = "Shift"},
                {value = "CTRL", text = "Ctrl"},
                {value = "ALT", text = "Alt"},
            }
            P(GUI:CreateFormDropdown(body, "Combat Modifier Key", combatOverrideOptions, "combatKey", tooltip, RefreshTooltips), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "tooltipAnchor", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- SKYRIDING
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("skyriding", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db then return 80 end
        if not db.skyriding then db.skyriding = {} end
        local sr = db.skyriding

        -- Initialize defaults
        if sr.width == nil then sr.width = 250 end
        if sr.vigorHeight == nil then sr.vigorHeight = 12 end
        if sr.secondWindHeight == nil then sr.secondWindHeight = 6 end
        if sr.barTexture == nil then sr.barTexture = "Solid" end
        if sr.showSegments == nil then sr.showSegments = true end
        if sr.showSpeed == nil then sr.showSpeed = true end
        if sr.showVigorText == nil then sr.showVigorText = true end
        if sr.secondWindMode == nil then sr.secondWindMode = "PIPS" end
        if sr.visibility == nil then sr.visibility = "AUTO" end
        if sr.fadeDelay == nil then sr.fadeDelay = 3 end
        if sr.speedFormat == nil then sr.speedFormat = "PERCENT" end
        if sr.vigorTextFormat == nil then sr.vigorTextFormat = "FRACTION" end
        if sr.useClassColorVigor == nil then sr.useClassColorVigor = false end
        if sr.useClassColorSecondWind == nil then sr.useClassColorSecondWind = false end
        if sr.useThrillOfTheSkiesColor == nil then sr.useThrillOfTheSkiesColor = true end

        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshSkyriding then _G.QUI_RefreshSkyriding() end end

        -- Visibility
        U.CreateCollapsible(content, "Visibility", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Visibility Mode", {
                {value = "ALWAYS", text = "Always Visible"},
                {value = "FLYING_ONLY", text = "Only When Flying"},
                {value = "AUTO", text = "Auto (fade when grounded)"},
            }, "visibility", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Delay (sec)", 0, 10, 0.5, "fadeDelay", sr, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Fade Speed (sec)", 0.1, 1.0, 0.1, "fadeDuration", sr, Refresh), body, sy)
        end, sections, relayout)

        -- Bar Size
        U.CreateCollapsible(content, "Bar Size", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Width", 100, 500, 1, "width", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Vigor Height", 4, 30, 1, "vigorHeight", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Second Wind Height", 2, 20, 1, "secondWindHeight", sr, Refresh), body, sy)
            P(GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "barTexture", sr, Refresh), body, sy)
        end, sections, relayout)

        -- Fill Colors
        U.CreateCollapsible(content, "Fill Colors", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Vigor", "useClassColorVigor", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Vigor Fill Color", "barColor", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Second Wind", "useClassColorSecondWind", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Second Wind Color", "secondWindColor", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Change Color with Thrill of the Skies", "useThrillOfTheSkiesColor", sr, Refresh), body, sy)
            P(GUI:CreateFormColorPicker(body, "Thrill of the Skies Color", "thrillOfTheSkiesColor", sr, Refresh), body, sy)
        end, sections, relayout)

        -- Background & Effects
        U.CreateCollapsible(content, "Background & Effects", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "backgroundColor", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Second Wind Background", "secondWindBackgroundColor", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Segment Marker Color", "segmentColor", sr, Refresh), body, sy)
            P(GUI:CreateFormColorPicker(body, "Recharge Animation Color", "rechargeColor", sr, Refresh), body, sy)
        end, sections, relayout)

        -- Text Display
        U.CreateCollapsible(content, "Text Display", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Vigor Count", "showVigorText", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Vigor Format", {
                {value = "FRACTION", text = "Fraction (4/6)"}, {value = "CURRENT", text = "Current Only (4)"},
            }, "vigorTextFormat", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Speed", "showSpeed", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Speed Format", {
                {value = "PERCENT", text = "Percentage (312%)"}, {value = "RAW", text = "Raw Speed (9.5)"},
            }, "speedFormat", sr, Refresh), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Whirling Surge Icon", "showAbilityIcon", sr, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Text Font Size", 8, 24, 1, "vigorFontSize", sr, function()
                sr.speedFontSize = sr.vigorFontSize; Refresh()
            end), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "skyriding", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- PARTY KEYSTONES
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("partyKeystones", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.general then return 80 end
        local general = db.general

        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshKeyTracker then _G.QUI_RefreshKeyTracker() end end

        -- Appearance
        U.CreateCollapsible(content, "Appearance", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Font", U.GetFontList(), "keyTrackerFont", general, Refresh), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 7, 12, 1, "keyTrackerFontSize", general, Refresh), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Text Color", "keyTrackerTextColor", general, Refresh), body, sy)
            P(GUI:CreateFormSlider(body, "Frame Width", 120, 250, 1, "keyTrackerWidth", general, Refresh), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "partyKeystones", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- CHAT
    ---------------------------------------------------------------------------
    settingsPanel:RegisterProvider("chatFrame1", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.chat then return 80 end
        local chat = db.chat
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end end

        -- Frame Size — drives ChatFrame1 directly via FCF_SetWindowSize, so
        -- Blizzard persists the dimensions in ChatConfig on logout. The proxy
        -- table lets CreateFormSlider read/write live frame dimensions.
        local sizeProxy = setmetatable({}, {
            __index = function(_, k)
                local f = _G.ChatFrame1
                if not f then return 0 end
                if k == "width" then return math.floor((f:GetWidth() or 0) + 0.5) end
                if k == "height" then return math.floor((f:GetHeight() or 0) + 0.5) end
                return 0
            end,
            __newindex = function(_, k, v)
                local f = _G.ChatFrame1
                if not f or type(v) ~= "number" then return end
                local w, h = f:GetWidth() or 0, f:GetHeight() or 0
                if k == "width" then w = v end
                if k == "height" then h = v end
                if _G.FCF_SetWindowSize then
                    _G.FCF_SetWindowSize(f, w, h)
                else
                    f:SetSize(w, h)
                end
                if _G.FCF_SavePositionAndDimensions then
                    _G.FCF_SavePositionAndDimensions(f)
                end
            end,
        })

        local widthSlider, heightSlider
        U.CreateCollapsible(content, "Frame Size", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            widthSlider = GUI:CreateFormSlider(body, "Width", 296, 1400, 1, "width", sizeProxy, nil)
            sy = P(widthSlider, body, sy)
            heightSlider = GUI:CreateFormSlider(body, "Height", 120, 900, 1, "height", sizeProxy, nil)
            P(heightSlider, body, sy)
        end, sections, relayout)

        -- Expose a refresh hook so the corner-grip drag can sync slider positions.
        _G.QUI_RefreshChatSizeSliders = function()
            if widthSlider and widthSlider.SetValue then
                widthSlider:SetValue(sizeProxy.width)
            end
            if heightSlider and heightSlider.SetValue then
                heightSlider:SetValue(sizeProxy.height)
            end
        end

        -- Intro Message
        U.CreateCollapsible(content, "Intro Message", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Login Message", "showIntroMessage", chat, nil), body, sy)
            local info = GUI:CreateLabel(body, "Display the QUI reminder tips when you log in.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Default Tab
        U.CreateCollapsible(content, "Default Tab", 3 * FORM_ROW + 8, function(body)
            -- Build tab options dynamically from current chat windows
            local tabOptions = {}
            for i = 1, NUM_CHAT_WINDOWS do
                local name = GetChatWindowInfo(i)
                if name and name ~= "" then
                    tabOptions[#tabOptions + 1] = {
                        value = i,
                        text = i .. ". " .. name,
                    }
                end
            end
            if #tabOptions == 0 then
                tabOptions[1] = { value = 1, text = "1. General" }
            end

            if not chat.defaultTabBySpec then chat.defaultTabBySpec = {} end

            local container = nil

            local function RebuildDefaultTab()
                -- Destroy previous container (clears children AND regions)
                if container then
                    container:Hide()
                    container:SetParent(nil)
                    container = nil
                end

                container = CreateFrame("Frame", nil, body)
                container:SetPoint("TOPLEFT", 0, 0)
                container:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                container:SetHeight(1)

                local sy = -4

                if chat.defaultTabPerSpec then
                    -- Per-spec mode: all spec dropdowns tiled on one row
                    local specs = {}
                    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
                    for s = 1, numSpecs do
                        local specID, specName = GetSpecializationInfo(s)
                        if specID and specName then
                            if not chat.defaultTabBySpec[specID] then
                                chat.defaultTabBySpec[specID] = 1
                            end
                            specs[#specs + 1] = { id = specID, name = specName }
                        end
                    end

                    local count = #specs
                    if count > 0 then
                        local GAP = 16
                        local LABEL_WIDTH = 80
                        local row = CreateFrame("Frame", nil, container)
                        row:SetPoint("TOPLEFT", 0, sy)
                        row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                        row:SetHeight(FORM_ROW)

                        -- Create equal-width column frames by chaining anchors
                        local columns = {}
                        for idx = 1, count do
                            local col = CreateFrame("Frame", nil, row)
                            col:SetPoint("TOP", 0, 0)
                            col:SetPoint("BOTTOM", 0, 0)
                            if idx == 1 then
                                col:SetPoint("LEFT", row, "LEFT", 0, 0)
                            else
                                col:SetPoint("LEFT", columns[idx - 1], "RIGHT", GAP, 0)
                            end
                            columns[idx] = col
                        end
                        -- Distribute column widths evenly via OnSizeChanged
                        local function DistributeColumns(w)
                            local colW = (w - GAP * (count - 1)) / count
                            for idx = 1, count do
                                columns[idx]:SetWidth(math.max(colW, 1))
                            end
                        end
                        row:SetScript("OnSizeChanged", function(self, w) DistributeColumns(w) end)
                        C_Timer.After(0, function()
                            local w = row:GetWidth()
                            if w and w > 0 then DistributeColumns(w) end
                        end)

                        -- Place a dropdown inside each column with compact label offset
                        for idx, spec in ipairs(specs) do
                            local dd = GUI:CreateFormDropdown(columns[idx], spec.name, tabOptions, spec.id, chat.defaultTabBySpec, Refresh)
                            dd:ClearAllPoints()
                            dd:SetPoint("TOPLEFT", 0, 0)
                            dd:SetPoint("RIGHT", columns[idx], "RIGHT", 0, 0)
                            -- Tighten label-to-dropdown gap (default is 180px)
                            local btn = select(1, dd:GetChildren())
                            if btn then
                                btn:ClearAllPoints()
                                btn:SetPoint("LEFT", dd, "LEFT", LABEL_WIDTH, 0)
                                btn:SetPoint("RIGHT", dd, "RIGHT", 0, 0)
                            end
                        end
                        sy = sy - FORM_ROW
                    end

                    local info = GUI:CreateLabel(container, "Each spec selects its own chat tab on login, reload, or spec switch.", 10, {0.5, 0.5, 0.5, 1})
                    info:SetPoint("TOPLEFT", 0, sy)
                    info:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    info:SetJustifyH("LEFT")
                    sy = sy - 20
                else
                    sy = P(GUI:CreateFormDropdown(container, "Default Tab", tabOptions, "defaultTab", chat, Refresh), container, sy)
                    local info = GUI:CreateLabel(container, "Select which chat tab is active when you log in or reload.", 10, {0.5, 0.5, 0.5, 1})
                    info:SetPoint("TOPLEFT", 0, sy)
                    info:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                    info:SetJustifyH("LEFT")
                    sy = sy - 20
                end

                P(GUI:CreateFormCheckbox(container, "Per Spec", "defaultTabPerSpec", chat, function()
                    Refresh()
                    RebuildDefaultTab()
                end), container, sy)
            end

            RebuildDefaultTab()
        end, sections, relayout)

        -- Chat Background
        if chat.glass then
            U.CreateCollapsible(content, "Chat Background", 3 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Chat Background Texture", "enabled", chat.glass, Refresh), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.glass, Refresh), body, sy)
                P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", chat.glass, Refresh), body, sy)
            end, sections, relayout)
        end

        -- Input Box Background
        if chat.editBox then
            U.CreateCollapsible(content, "Input Box Background", 5 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Input Box Background Texture", "enabled", chat.editBox, Refresh), body, sy)
                sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1.0, 0.05, "bgAlpha", chat.editBox, Refresh), body, sy)
                sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", chat.editBox, Refresh), body, sy)
                sy = P(GUI:CreateFormCheckbox(body, "Position Input Box at Top", "positionTop", chat.editBox, Refresh), body, sy)
                local info = GUI:CreateLabel(body, "Moves input box above chat tabs with opaque background.", 10, {0.5, 0.5, 0.5, 1})
                info:SetPoint("TOPLEFT", 0, sy)
                info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                info:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        -- Message Fade
        if chat.fade then
            U.CreateCollapsible(content, "Message Fade", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Fade Messages After Inactivity", "enabled", chat.fade, Refresh), body, sy)
                P(GUI:CreateFormSlider(body, "Fade Delay (seconds)", 1, 120, 1, "delay", chat.fade, Refresh), body, sy)
            end, sections, relayout)
        end

        -- URL Detection
        if chat.urls then
            U.CreateCollapsible(content, "URL Detection", 2 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Make URLs Clickable", "enabled", chat.urls, Refresh), body, sy)
                local info = GUI:CreateLabel(body, "Click any URL in chat to open a copy dialog.", 10, {0.5, 0.5, 0.5, 1})
                info:SetPoint("TOPLEFT", 0, sy)
                info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                info:SetJustifyH("LEFT")
            end, sections, relayout)
        end

        -- Timestamps
        U.CreateCollapsible(content, "Timestamps", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.timestamps then chat.timestamps = {enabled = false, format = "24h", color = {0.6, 0.6, 0.6}} end
            sy = P(GUI:CreateFormCheckbox(body, "Show Timestamps", "enabled", chat.timestamps, Refresh), body, sy)
            local info = GUI:CreateLabel(body, "Timestamps only appear on new messages after enabling.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
            sy = sy - 20
            local formatOptions = {
                {value = "24h", text = "24-Hour (15:27)"},
                {value = "12h", text = "12-Hour (3:27 PM)"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Format", formatOptions, "format", chat.timestamps, Refresh), body, sy)
            P(GUI:CreateFormColorPicker(body, "Timestamp Color", "color", chat.timestamps, Refresh), body, sy)
        end, sections, relayout)

        -- UI Cleanup
        U.CreateCollapsible(content, "UI Cleanup", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Chat Buttons", "hideButtons", chat, Refresh), body, sy)
            local info = GUI:CreateLabel(body, "Hides social, channel, and scroll buttons. Mouse wheel still scrolls.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Copy Button
        U.CreateCollapsible(content, "Copy Button", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            local copyButtonOptions = {
                {value = "always", text = "Show Always"},
                {value = "hover", text = "Show on Hover"},
                {value = "disabled", text = "Disabled"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Copy Button", copyButtonOptions, "copyButtonMode", chat, Refresh), body, sy)
            local info = GUI:CreateLabel(body, "Controls the copy button on each chat frame for copying chat history.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- Message History
        U.CreateCollapsible(content, "Message History", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            if not chat.messageHistory then
                chat.messageHistory = { enabled = true, maxHistory = 50 }
            end
            sy = P(GUI:CreateFormCheckbox(body, "Enable Message History", "enabled", chat.messageHistory, Refresh), body, sy)
            local info = GUI:CreateLabel(body, "Use arrow keys (Up/Down) to navigate through your sent message history while typing.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        -- New Message Sound
        U.CreateCollapsible(content, "New Message Sound", 1, function(body)
            local sy = -4
            if not chat.newMessageSound then
                chat.newMessageSound = { enabled = false, entries = {{ channel = "guild_officer", sound = "None" }} }
            end
            if not chat.newMessageSound.entries or #chat.newMessageSound.entries == 0 then
                chat.newMessageSound.entries = {{ channel = "guild_officer", sound = "None" }}
            end

            sy = P(GUI:CreateFormCheckbox(body, "Play Sound on New Message", "enabled", chat.newMessageSound, Refresh), body, sy)

            local soundEntriesContainer = CreateFrame("Frame", nil, body)
            soundEntriesContainer:SetPoint("TOPLEFT", 0, sy)
            soundEntriesContainer:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            soundEntriesContainer:SetHeight(1)

            local ALL_CHANNEL_OPTIONS = {
                {value = "guild_officer", text = "Guild & Officer"},
                {value = "guild", text = "Guild Only"},
                {value = "officer", text = "Officer Only"},
                {value = "party", text = "Party"},
                {value = "raid", text = "Raid"},
                {value = "whisper", text = "Whisper"},
                {value = "all", text = "All Channels"},
            }

            local function GetChannelOptionsForEntry(entries, excludeIndex)
                local used = {}
                for i, e in ipairs(entries) do
                    if i ~= excludeIndex and e.channel then used[e.channel] = true end
                end
                local currentChannel = entries[excludeIndex] and entries[excludeIndex].channel
                local opts = {}
                for _, o in ipairs(ALL_CHANNEL_OPTIONS) do
                    if not used[o.value] or o.value == currentChannel then
                        opts[#opts + 1] = o
                    end
                end
                return opts
            end

            local section = body:GetParent()

            local function RebuildSoundEntries()
                soundEntriesContainer:SetHeight(0)
                for _, child in ipairs({ soundEntriesContainer:GetChildren() }) do
                    child:Hide()
                    child:SetParent(nil)
                end

                local entries = chat.newMessageSound.entries
                if not entries then return end

                local rowY = 0
                for i, entry in ipairs(entries) do
                    local row = CreateFrame("Frame", nil, soundEntriesContainer)
                    row:SetPoint("TOPLEFT", 0, -rowY)
                    row:SetPoint("RIGHT", soundEntriesContainer, "RIGHT", 0, 0)
                    row:SetHeight(FORM_ROW)

                    local channelOpts = GetChannelOptionsForEntry(entries, i)
                    if #channelOpts == 0 then
                        channelOpts = {{value = entry.channel or "guild_officer", text = entry.channel or "guild_officer"}}
                    end

                    local function OnChannelChange()
                        Refresh()
                        RebuildSoundEntries()
                    end
                    local channelDropdown = GUI:CreateFormDropdown(row, "Channel", channelOpts, "channel", entry, OnChannelChange)
                    if GUI.SetWidgetProviderSyncOptions then
                        GUI:SetWidgetProviderSyncOptions(channelDropdown, { auto = true, structural = true })
                    end
                    channelDropdown:SetPoint("TOPLEFT", 0, 0)
                    channelDropdown:SetPoint("RIGHT", row, "RIGHT", -80, 0)

                    local soundList = U.GetSoundList()
                    local soundDropdown = GUI:CreateFormDropdown(row, "Sound", soundList, "sound", entry, Refresh)
                    soundDropdown:SetPoint("TOPLEFT", 0, -FORM_ROW)
                    soundDropdown:SetPoint("RIGHT", row, "RIGHT", -80, 0)

                    local removeBtn = GUI:CreateButton(row, "X", 24, 22, function()
                        table.remove(entries, i)
                        RebuildSoundEntries()
                        Refresh()
                        NotifyProviderFor(removeBtn, { structural = true })
                    end)
                    removeBtn:SetPoint("RIGHT", row, "RIGHT", 0, -FORM_ROW/2)

                    row:SetHeight(FORM_ROW * 2)
                    rowY = rowY + FORM_ROW * 2 + 4
                end

                soundEntriesContainer:SetHeight(rowY)

                local function GetFirstAvailableChannel()
                    local used = {}
                    for _, e in ipairs(chat.newMessageSound.entries) do
                        if e.channel then used[e.channel] = true end
                    end
                    for _, o in ipairs(ALL_CHANNEL_OPTIONS) do
                        if not used[o.value] then return o.value end
                    end
                    return nil
                end

                local nextChannel = GetFirstAvailableChannel()
                if nextChannel then
                    local addBtn = GUI:CreateButton(soundEntriesContainer, "+ Add Channel + Sound", 180, 24, function()
                        local channel = GetFirstAvailableChannel()
                        if not channel then return end
                        table.insert(chat.newMessageSound.entries, { channel = channel, sound = "None" })
                        RebuildSoundEntries()
                        Refresh()
                        NotifyProviderFor(addBtn, { structural = true })
                    end)
                    addBtn:SetPoint("TOPLEFT", 0, -rowY - 4)
                    rowY = rowY + 28
                end
                soundEntriesContainer:SetHeight(rowY)

                local totalHeight = FORM_ROW + 8 + rowY + 30
                section._contentHeight = totalHeight
                if section._expanded then
                    section:SetHeight(24 + totalHeight)
                    relayout()
                end
            end

            RebuildSoundEntries()

            local info = GUI:CreateLabel(body, "Each channel can have its own sound. Uses LibSharedMedia. Saved to your profile.", 10, {0.5, 0.5, 0.5, 1})
            info:SetPoint("TOPLEFT", soundEntriesContainer, "BOTTOMLEFT", 0, -8)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetJustifyH("LEFT")
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "chatFrame1", nil, sections, relayout)
        relayout() return content:GetHeight()
    end })
end

C_Timer.After(3, RegisterAllProviders)
