--[[
    QUI QoL Shared Settings Providers
    Owns provider-backed settings content for QoL and gameplay movers/pages routed through the shared settings layer.
    Migrated to V3 body pattern (CreateAccentDotLabel + CreateSettingsCardGroup + BuildSettingRow).
]]

local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

-- NOTE: do NOT capture `ns.QUI_Options` as a local in this outer closure.
-- This file is loaded by the QUI addon before the on-demand QUI_Options
-- addon is loaded; at that point ns.QUI_Options is the minimal stub
-- installed by core/gui_shell.lua. Once QUI_Options/shared.lua runs it
-- REPLACES the table, so any captured local would be stale. Re-resolve
-- ns.QUI_Options at call time inside MakeLayout / row / build bodies.
ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local NotifyProviderFor = ctx.NotifyProviderFor
    local anchorOptions = ctx.anchorOptions
    local PAD = (ns.QUI_Options and ns.QUI_Options.PADDING) or 15
    local HEADER_GAP = 26
    local SECTION_GAP = 14
    local FORM_ROW = ctx.FORM_ROW

    local function RegisterSharedOnly(key, provider)
        ctx.RegisterShared(key, provider)
    end

    -- Shared provider-panel layout scaffold (core/settings_layout_shared.lua).
    local function MakeLayout(content)
        if U._layoutModePositionOnly then
            return U.MakeSuppressedProviderLayout(content)
        end
        return ns.QUI_SettingsLayoutShared.MakeLayout(content, U)
    end

    local function row(parent, label, widget, desc)
        return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
    end

    local function FinishProviderPage(L, content, key, positionKey)
        U.BuildPositionCollapsible(content, positionKey, nil, L.sections, L.relayoutSections)
        U.BuildOpenFullSettingsLink(content, key, L.sections, L.relayoutSections)
        L.relayoutSections()
        return content:GetHeight()
    end

    -- Shared "Backdrop" card (showBackdrop checkbox + backdropColor picker).
    -- elementPhrase fills the showBackdrop description ("behind the <phrase>").
    local function BuildBackdropSection(L, db, Refresh, elementPhrase)
        L.headerAt("Backdrop")
        local s3 = L.sectionAt()
        local showBdW = GUI:CreateFormCheckbox(s3.frame, nil, "showBackdrop", db, Refresh,
            { description = "Draw a semi-transparent backdrop behind the " .. elementPhrase .. " so it stands out against busy scenes." })
        local bdColorW = GUI:CreateFormColorPicker(s3.frame, nil, "backdropColor", db, Refresh, nil,
            { description = "Color and opacity of the backdrop when Show Backdrop is on." })
        s3.AddRow(row(s3.frame, "Show Backdrop", showBdW), row(s3.frame, "Backdrop Color", bdColorW))
        L.closeSection(s3)
    end

    -- Shared "Use Custom Font" + conditional font dropdown row.
    local function BuildUseCustomFontRow(section, db, Refresh, fontDesc)
        local useCustomFontW = GUI:CreateFormCheckbox(section.frame, nil, "useCustomFont", db, Refresh,
            { description = "Override the global font for this element with the font selected below." })
        local fonts = U.GetFontList()
        if #fonts > 0 then
            local fontW = GUI:CreateFormDropdown(section.frame, nil, fonts, "font", db, Refresh,
                { description = fontDesc })
            section.AddRow(row(section.frame, "Use Custom Font", useCustomFontW), row(section.frame, "Font", fontW))
        else
            section.AddRow(row(section.frame, "Use Custom Font", useCustomFontW))
        end
    end

    -- Shared "Border" card (hideBorder + borderSize + BorderControl.Attach).
    local function BuildBorderSection(L, db, Refresh)
        L.headerAt("Border")
        local s4 = L.sectionAt()
        local hideBorderW = GUI:CreateFormCheckbox(s4.frame, nil, "hideBorder", db, Refresh,
            { description = "Hide the border outline entirely." })
        local borderSizeW2 = GUI:CreateFormSlider(s4.frame, nil, 1, 5, 0.5, "borderSize", db, Refresh,
            { description = "Border thickness in pixels. Ignored while Hide Border is on." })
        s4.AddRow(row(s4.frame, "Hide Border", hideBorderW), row(s4.frame, "Border Size", borderSizeW2))

        local srcW, colW = ns.QUI_BorderControl.Attach(GUI, s4.frame, db, "", Refresh,
            { label = "Border Color Source", colorLabel = "Border Color" })
        s4.AddRow(row(s4.frame, "Border Color Source", srcW), row(s4.frame, "Border Color", colW))
        L.closeSection(s4)
    end

    ---------------------------------------------------------------------------
    -- XP TRACKER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("xpTracker", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.xpTracker then return 80 end
        local xp = db.xpTracker
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshXPTracker then _G.QUI_RefreshXPTracker() end end

        -- SIZE & TEXT
        L.headerAt("Size & Text")
        local s1 = L.sectionAt()
        local widthW = GUI:CreateFormSlider(s1.frame, nil, 200, 1000, 1, "width", xp, Refresh,
            { description = "Overall pixel width of the XP tracker frame." })
        local heightW = GUI:CreateFormSlider(s1.frame, nil, 60, 200, 1, "height", xp, Refresh,
            { description = "Overall pixel height of the XP tracker frame, including the header area and the bar." })
        s1.AddRow(row(s1.frame, "Bar Width", widthW), row(s1.frame, "Height", heightW))

        local barHeightW = GUI:CreateFormSlider(s1.frame, nil, 8, 40, 1, "barHeight", xp, Refresh,
            { description = "Pixel height of just the XP fill bar inside the frame." })
        local headerFontW = GUI:CreateFormSlider(s1.frame, nil, 8, 22, 1, "headerFontSize", xp, Refresh,
            { description = "Font size for the header row that shows your level and total XP gained." })
        s1.AddRow(row(s1.frame, "Bar Height", barHeightW), row(s1.frame, "Header Font Size", headerFontW))

        local headerLineW = GUI:CreateFormSlider(s1.frame, nil, 12, 30, 1, "headerLineHeight", xp, Refresh,
            { description = "Vertical spacing reserved for the header row. Increase if the header text is getting clipped." })
        local fontSizeW = GUI:CreateFormSlider(s1.frame, nil, 8, 18, 1, "fontSize", xp, Refresh,
            { description = "Font size for the detail rows below the header (session XP, time to level, etc.)." })
        s1.AddRow(row(s1.frame, "Header Line Height", headerLineW), row(s1.frame, "Font Size", fontSizeW))

        local lineHeightW = GUI:CreateFormSlider(s1.frame, nil, 10, 24, 1, "lineHeight", xp, Refresh,
            { description = "Vertical spacing between detail rows." })
        local barTexW = GUI:CreateFormDropdown(s1.frame, nil, U.GetTextureList(), "barTexture", xp, Refresh,
            { description = "Statusbar texture used for the XP fill. Supports any extra media packages you have available." })
        s1.AddRow(row(s1.frame, "Line Height", lineHeightW), row(s1.frame, "Bar Texture", barTexW))

        local growW = GUI:CreateFormDropdown(s1.frame, nil,
            {{value="auto",text="Auto"},{value="up",text="Up"},{value="down",text="Down"}},
            "detailsGrowDirection", xp, Refresh,
            { description = "Whether the detail rows stack above or below the bar. Auto picks based on where the frame is anchored on screen." })
        s1.AddRow(row(s1.frame, "Details Grow Direction", growW))
        L.closeSection(s1)

        -- COLORS
        L.headerAt("Colors")
        local s2 = L.sectionAt()
        local barColorW = GUI:CreateFormColorPicker(s2.frame, nil, "barColor", xp, Refresh, nil,
            { description = "Fill color of the XP bar." })
        local restedColorW = GUI:CreateFormColorPicker(s2.frame, nil, "restedColor", xp, Refresh, nil,
            { description = "Color of the rested-XP overlay drawn on top of the regular fill." })
        s2.AddRow(row(s2.frame, "XP Bar Color", barColorW), row(s2.frame, "Rested XP Color", restedColorW))

        local backdropColorW = GUI:CreateFormColorPicker(s2.frame, nil, "backdropColor", xp, Refresh, nil,
            { description = "Background color behind the XP bar." })
        s2.AddRow(row(s2.frame, "Backdrop Color", backdropColorW))
        L.closeSection(s2)

        -- BORDER
        L.headerAt("Border")
        local s2b = L.sectionAt()
        local srcW, colW = ns.QUI_BorderControl.Attach(GUI, s2b.frame, xp, "", Refresh,
            { label = "Border Color Source", colorLabel = "Border Color" })
        s2b.AddRow(row(s2b.frame, "Border Color Source", srcW), row(s2b.frame, "Border Color", colW))
        L.closeSection(s2b)

        -- DISPLAY
        L.headerAt("Display")
        local s3 = L.sectionAt()
        local showBarTextW = GUI:CreateFormCheckbox(s3.frame, nil, "showBarText", xp, Refresh,
            { description = "Show the current/next XP values and percent as text on top of the bar." })
        local showRestedW = GUI:CreateFormCheckbox(s3.frame, nil, "showRested", xp, Refresh,
            { description = "Overlay a rested-XP indicator showing how much bonus XP you have banked." })
        s3.AddRow(row(s3.frame, "Show Bar Text", showBarTextW), row(s3.frame, "Show Rested XP Overlay", showRestedW))

        local hideHoverW = GUI:CreateFormCheckbox(s3.frame, nil, "hideTextUntilHover", xp, Refresh,
            { description = "Hide the bar text until you mouse over the frame. Keeps the tracker visually clean between pulls." })
        s3.AddRow(row(s3.frame, "Hide Text Until Hover", hideHoverW))
        L.closeSection(s3)

        return FinishProviderPage(L, content, key, "xpTracker")
    end })

    ---------------------------------------------------------------------------
    -- COMBAT TIMER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("combatTimer", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.combatTimer then return 80 end
        local ct = db.combatTimer
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end end

        -- GENERAL
        L.headerAt("General")
        local s1 = L.sectionAt()
        local onlyEncW = GUI:CreateFormCheckbox(s1.frame, nil, "onlyShowInEncounters", ct, Refresh,
            { description = "Hide the combat timer outside of boss encounters, M+ dungeons, and PvP matches. Off shows the timer on every pull." })
        local widthW = GUI:CreateFormSlider(s1.frame, nil, 40, 200, 1, "width", ct, Refresh,
            { description = "Pixel width of the combat timer frame." })
        s1.AddRow(row(s1.frame, "Only Show In Encounters", onlyEncW), row(s1.frame, "Width", widthW))

        local heightW = GUI:CreateFormSlider(s1.frame, nil, 20, 100, 1, "height", ct, Refresh,
            { description = "Pixel height of the combat timer frame." })
        local fontSizeW = GUI:CreateFormSlider(s1.frame, nil, 12, 32, 1, "fontSize", ct, Refresh,
            { description = "Font size of the elapsed-time text." })
        s1.AddRow(row(s1.frame, "Height", heightW), row(s1.frame, "Font Size", fontSizeW))
        L.closeSection(s1)

        -- TEXT
        L.headerAt("Text")
        local s2 = L.sectionAt()
        local useClassW = GUI:CreateFormCheckbox(s2.frame, nil, "useClassColorText", ct, Refresh,
            { description = "Color the timer text by your class instead of the Text Color swatch below." })
        local textColorW = GUI:CreateFormColorPicker(s2.frame, nil, "textColor", ct, Refresh, nil,
            { description = "Color used for the timer text when Use Class Color is off." })
        s2.AddRow(row(s2.frame, "Use Class Color", useClassW), row(s2.frame, "Text Color", textColorW))

        BuildUseCustomFontRow(s2, ct, Refresh, "Custom font for the timer text. Requires Use Custom Font to be enabled.")
        L.closeSection(s2)

        BuildBackdropSection(L, ct, Refresh, "combat timer")
        BuildBorderSection(L, ct, Refresh)

        return FinishProviderPage(L, content, key, "combatTimer")
    end })

    ---------------------------------------------------------------------------
    -- BREZ COUNTER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("brezCounter", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.brzCounter then return 80 end
        local bz = db.brzCounter
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end end

        -- GENERAL
        L.headerAt("General")
        local s1 = L.sectionAt()
        local lockedW = GUI:CreateFormCheckbox(s1.frame, nil, "locked", bz, Refresh,
            { description = "Lock the battle-rez counter so it can't be accidentally dragged from its current position." })
        local widthW = GUI:CreateFormSlider(s1.frame, nil, 30, 100, 1, "width", bz, Refresh,
            { description = "Pixel width of the counter frame." })
        s1.AddRow(row(s1.frame, "Lock Frame", lockedW), row(s1.frame, "Width", widthW))

        local heightW = GUI:CreateFormSlider(s1.frame, nil, 30, 100, 1, "height", bz, Refresh,
            { description = "Pixel height of the counter frame." })
        local chargeFontW = GUI:CreateFormSlider(s1.frame, nil, 10, 28, 1, "fontSize", bz, Refresh,
            { description = "Font size of the big number showing remaining battle-rez charges." })
        s1.AddRow(row(s1.frame, "Height", heightW), row(s1.frame, "Charges Font Size", chargeFontW))

        local timerFontW = GUI:CreateFormSlider(s1.frame, nil, 8, 24, 1, "timerFontSize", bz, Refresh,
            { description = "Font size of the recharge timer shown below the charge count." })
        s1.AddRow(row(s1.frame, "Timer Font Size", timerFontW))
        L.closeSection(s1)

        -- COLORS
        L.headerAt("Colors")
        local s2 = L.sectionAt()
        local hasChargesW = GUI:CreateFormColorPicker(s2.frame, nil, "hasChargesColor", bz, Refresh, nil,
            { description = "Color of the charge count when at least one battle-rez is available." })
        local noChargesW = GUI:CreateFormColorPicker(s2.frame, nil, "noChargesColor", bz, Refresh, nil,
            { description = "Color of the charge count when all battle-rezzes have been used." })
        s2.AddRow(row(s2.frame, "Charges Available", hasChargesW), row(s2.frame, "No Charges", noChargesW))

        local useClassTimerW = GUI:CreateFormCheckbox(s2.frame, nil, "useClassColorText", bz, Refresh,
            { description = "Color the recharge timer by your class instead of the Timer Text Color swatch below." })
        local timerColorW = GUI:CreateFormColorPicker(s2.frame, nil, "timerColor", bz, Refresh, nil,
            { description = "Color used for the recharge timer when Class Color is off." })
        s2.AddRow(row(s2.frame, "Class Color Timer Text", useClassTimerW), row(s2.frame, "Timer Text Color", timerColorW))

        BuildUseCustomFontRow(s2, bz, Refresh, "Custom font for the counter text. Requires Use Custom Font to be enabled.")
        L.closeSection(s2)

        BuildBackdropSection(L, bz, Refresh, "brez counter")
        BuildBorderSection(L, bz, Refresh)

        return FinishProviderPage(L, content, key, "brezCounter")
    end })

    ---------------------------------------------------------------------------
    -- ATONEMENT COUNTER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("atonementCounter", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.atonementCounter then return 80 end
        local ac = db.atonementCounter
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshAtonementCounter then _G.QUI_RefreshAtonementCounter() end end

        -- GENERAL
        L.headerAt("General")
        local s1 = L.sectionAt()
        local lockedW = GUI:CreateFormCheckbox(s1.frame, nil, "locked", ac, Refresh,
            { description = "Lock the Atonement counter so it can't be accidentally dragged from its current position." })
        local instOnlyW = GUI:CreateFormCheckbox(s1.frame, nil, "showOnlyInInstance", ac, Refresh,
            { description = "Hide the counter while in the open world. Useful if you only need it for instanced content." })
        s1.AddRow(row(s1.frame, "Lock Frame", lockedW), row(s1.frame, "Show Only In Dungeons/Raids", instOnlyW))

        local hideIconW = GUI:CreateFormCheckbox(s1.frame, nil, "hideIcon", ac, Refresh,
            { description = "Hide the Atonement spell icon and show only the count number." })
        local widthW = GUI:CreateFormSlider(s1.frame, nil, 30, 100, 1, "width", ac, Refresh,
            { description = "Pixel width of the counter frame." })
        s1.AddRow(row(s1.frame, "Hide Spell Icon", hideIconW), row(s1.frame, "Width", widthW))

        local heightW = GUI:CreateFormSlider(s1.frame, nil, 30, 100, 1, "height", ac, Refresh,
            { description = "Pixel height of the counter frame." })
        local fontSizeW = GUI:CreateFormSlider(s1.frame, nil, 10, 36, 1, "fontSize", ac, Refresh,
            { description = "Font size of the Atonement count number." })
        s1.AddRow(row(s1.frame, "Height", heightW), row(s1.frame, "Count Font Size", fontSizeW))
        L.closeSection(s1)

        -- COLORS
        L.headerAt("Colors")
        local s2 = L.sectionAt()
        local useClassW = GUI:CreateFormCheckbox(s2.frame, nil, "useClassColorText", ac, Refresh,
            { description = "Color the count number by your class instead of the Active/Zero color swatches." })
        local activeColorW = GUI:CreateFormColorPicker(s2.frame, nil, "activeCountColor", ac, Refresh, nil,
            { description = "Color of the number when one or more Atonements are active." })
        s2.AddRow(row(s2.frame, "Use Class Color Text", useClassW), row(s2.frame, "Active Count Color", activeColorW))

        local zeroColorW = GUI:CreateFormColorPicker(s2.frame, nil, "zeroCountColor", ac, Refresh, nil,
            { description = "Color of the number when no Atonements are active. Useful for spotting gaps at a glance." })
        local useCustomFontW = GUI:CreateFormCheckbox(s2.frame, nil, "useCustomFont", ac, Refresh,
            { description = "Override the global font for this element with the font selected below." })
        s2.AddRow(row(s2.frame, "Zero Count Color", zeroColorW), row(s2.frame, "Use Custom Font", useCustomFontW))

        local fonts = U.GetFontList()
        if #fonts > 0 then
            local fontW = GUI:CreateFormDropdown(s2.frame, nil, fonts, "font", ac, Refresh,
                { description = "Custom font for the count number. Requires Use Custom Font to be enabled." })
            s2.AddRow(row(s2.frame, "Font", fontW))
        end
        L.closeSection(s2)

        BuildBackdropSection(L, ac, Refresh, "Atonement counter")
        BuildBorderSection(L, ac, Refresh)

        return FinishProviderPage(L, content, key, "atonementCounter")
    end })

    ---------------------------------------------------------------------------
    -- ROTATION ASSIST ICON
    ---------------------------------------------------------------------------
    RegisterSharedOnly("rotationAssistIcon", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.rotationAssistIcon then return 80 end
        local ra = db.rotationAssistIcon
        if ra.frameStrata ~= "LOW" and ra.frameStrata ~= "MEDIUM" then
            ra.frameStrata = "MEDIUM"
        end
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshRotationAssistIcon then _G.QUI_RefreshRotationAssistIcon() end end

        -- GENERAL
        L.headerAt("General")
        local s1 = L.sectionAt()
        local lockW = GUI:CreateFormCheckbox(s1.frame, nil, "isLocked", ra, Refresh,
            { description = "Lock the rotation assist icon so it can't be accidentally dragged from its current position." })
        local gcdW = GUI:CreateFormCheckbox(s1.frame, nil, "cooldownSwipeEnabled", ra, Refresh,
            { description = "Show the global cooldown sweep (~1.5s) over the recommended spell icon." })
        s1.AddRow(row(s1.frame, "Lock Position", lockW), row(s1.frame, "GCD Swipe", gcdW))

        local visibilityW = GUI:CreateFormDropdown(s1.frame, nil,
            {{value="always",text="Always"},{value="combat",text="In Combat"},{value="hostile",text="Hostile Target"}},
            "visibility", ra, Refresh,
            { description = "When to show the icon: always visible, only in combat, or only when you have a hostile target." })
        local strataW = GUI:CreateFormDropdown(s1.frame, nil,
            {{value="LOW",text="Low"},{value="MEDIUM",text="Medium"}},
            "frameStrata", ra, Refresh,
            { description = "Draw layer for the icon. Medium sits above most UI; Low sits underneath nameplates and other mid-layer elements." })
        s1.AddRow(row(s1.frame, "Visibility", visibilityW), row(s1.frame, "Frame Strata", strataW))

        local iconSizeW = GUI:CreateFormSlider(s1.frame, nil, 16, 400, 1, "iconSize", ra, Refresh,
            { description = "Pixel size of the spell icon." })
        local borderSizeW = GUI:CreateFormSlider(s1.frame, nil, 0, 15, 1, "borderThickness", ra, Refresh,
            { description = "Thickness of the border drawn around the icon. Set to 0 to hide the border." })
        s1.AddRow(row(s1.frame, "Icon Size", iconSizeW), row(s1.frame, "Border Size", borderSizeW))
        L.closeSection(s1)

        -- BORDER
        L.headerAt("Border")
        local s1b = L.sectionAt()
        local showBorderW = GUI:CreateFormCheckbox(s1b.frame, nil, "showBorder", ra, Refresh,
            { description = "Show a colored border around the rotation assist icon." })
        s1b.AddRow(row(s1b.frame, "Show Border", showBorderW))

        local srcW, colW = ns.QUI_BorderControl.Attach(GUI, s1b.frame, ra, "", Refresh,
            { label = "Border Color Source", colorLabel = "Border Color" })
        s1b.AddRow(row(s1b.frame, "Border Color Source", srcW), row(s1b.frame, "Border Color", colW))
        L.closeSection(s1b)

        -- KEYBIND
        L.headerAt("Keybind")
        local s2 = L.sectionAt()
        local showKbW = GUI:CreateFormCheckbox(s2.frame, nil, "showKeybind", ra, Refresh,
            { description = "Overlay the keybind text of the bound spell on the icon." })
        s2.AddRow(row(s2.frame, "Show Keybind", showKbW))

        local kbColorW = GUI:CreateFormColorPicker(s2.frame, nil, "keybindColor", ra, Refresh, nil,
            { description = "Color of the keybind text." })
        local kbAnchorW = GUI:CreateFormDropdown(s2.frame, nil, anchorOptions, "keybindAnchor", ra, Refresh,
            { description = "Which corner of the icon the keybind text is anchored to." })
        s2.AddRow(row(s2.frame, "Keybind Color", kbColorW), row(s2.frame, "Keybind Anchor", kbAnchorW))

        local kbSizeW = GUI:CreateFormSlider(s2.frame, nil, 6, 48, 1, "keybindSize", ra, Refresh,
            { description = "Font size of the keybind text." })
        local kbXW = GUI:CreateFormSlider(s2.frame, nil, -50, 50, 1, "keybindOffsetX", ra, Refresh,
            { description = "Horizontal pixel offset for the keybind text from its anchor. Positive moves right, negative moves left." })
        s2.AddRow(row(s2.frame, "Keybind Size", kbSizeW), row(s2.frame, "Keybind X Offset", kbXW))

        local kbYW = GUI:CreateFormSlider(s2.frame, nil, -50, 50, 1, "keybindOffsetY", ra, Refresh,
            { description = "Vertical pixel offset for the keybind text from its anchor. Positive moves up, negative moves down." })
        s2.AddRow(row(s2.frame, "Keybind Y Offset", kbYW))
        L.closeSection(s2)

        return FinishProviderPage(L, content, key, "rotationAssistIcon")
    end })

    ---------------------------------------------------------------------------
    -- FOCUS CAST ALERT
    ---------------------------------------------------------------------------
    RegisterSharedOnly("focusCastAlert", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        local general = db and db.general
        if not general or not general.focusCastAlert then return 80 end
        local fca = general.focusCastAlert
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshFocusCastAlert then _G.QUI_RefreshFocusCastAlert() end end

        L.headerAt("Text & Font")
        local s1 = L.sectionAt()
        local fonts = U.GetFontList(); table.insert(fonts, 1, { value = "", text = "(Global Font)" })
        local fontW = GUI:CreateFormDropdown(s1.frame, nil, fonts, "font", fca, Refresh,
            { description = "Font used for the focus cast alert text. Pick Global Font to inherit the UI font." })
        local sizeW = GUI:CreateFormSlider(s1.frame, nil, 8, 72, 1, "fontSize", fca, Refresh,
            { description = "Font size of the alert text." })
        s1.AddRow(row(s1.frame, "Font", fontW), row(s1.frame, "Font Size", sizeW))

        local outlineW = GUI:CreateFormDropdown(s1.frame, nil,
            {{value="",text="None"},{value="OUTLINE",text="Outline"},{value="THICKOUTLINE",text="Thick Outline"}},
            "fontOutline", fca, Refresh,
            { description = "Outline applied to the alert text for readability against busy backgrounds." })
        local classColorW = GUI:CreateFormCheckbox(s1.frame, nil, "useClassColor", fca, Refresh,
            { description = "Color the alert text by your class instead of the Text Color swatch below." })
        s1.AddRow(row(s1.frame, "Font Outline", outlineW), row(s1.frame, "Use Class Color", classColorW))

        local textColorW = GUI:CreateFormColorPicker(s1.frame, nil, "textColor", fca, Refresh, nil,
            { description = "Color used for the alert text when Use Class Color is off." })
        local anchorToW = GUI:CreateFormDropdown(s1.frame, nil,
            {{value="screen",text="Screen"},{value="essential",text="CDM Essential"},{value="focus",text="Focus Frame"}},
            "anchorTo", fca, Refresh,
            { description = "What the alert is anchored to: the screen, the CDM Essential bar, or your focus unit frame." })
        s1.AddRow(row(s1.frame, "Text Color", textColorW), row(s1.frame, "Anchor To", anchorToW))
        L.closeSection(s1)

        return FinishProviderPage(L, content, key, "focusCastAlert")
    end })

    ---------------------------------------------------------------------------
    -- PET WARNING
    ---------------------------------------------------------------------------
    RegisterSharedOnly("petWarning", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        local general = db and db.general
        if not general then return 80 end
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RepositionPetWarning then _G.QUI_RepositionPetWarning() end end

        L.headerAt("Offsets")
        local s1 = L.sectionAt()
        local xW = GUI:CreateFormSlider(s1.frame, nil, -500, 500, 10, "petWarningOffsetX", general, Refresh,
            { description = "Horizontal pixel offset for the pet warning from its anchor. Positive moves right, negative moves left." })
        local yW = GUI:CreateFormSlider(s1.frame, nil, -500, 500, 10, "petWarningOffsetY", general, Refresh,
            { description = "Vertical pixel offset for the pet warning from its anchor. Positive moves up, negative moves down." })
        s1.AddRow(row(s1.frame, "Horizontal Offset", xW), row(s1.frame, "Vertical Offset", yW))
        L.closeSection(s1)

        return FinishProviderPage(L, content, key, "petWarning")
    end })

    ---------------------------------------------------------------------------
    -- ACTION TRACKER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("actionTracker", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.general then return 80 end
        if type(db.general.actionTracker) ~= "table" then db.general.actionTracker = {} end
        local at = db.general.actionTracker
        U.EnsureDefaults(at, {
            enabled = false, onlyInCombat = true, clearOnCombatEnd = true,
            inactivityFadeEnabled = false, inactivityFadeSeconds = 20, clearOnInactivity = false,
            showFailedCasts = true, maxEntries = 6, iconSize = 28, iconSpacing = 4,
            iconHideBorder = false, iconBorderColorSource = "inherit", iconBorderColor = {0,0,0,0.85},
            orientation = "VERTICAL", invertScrollDirection = false,
            showBackdrop = true, hideBorder = false, borderSize = 1,
            borderColorSource = "inherit",
            backdropColor = {0,0,0,0.6}, borderColor = {0,0,0,1}, blocklistText = "",
        })
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshActionTracker then _G.QUI_RefreshActionTracker() end end

        -- BEHAVIOR
        L.headerAt("Behavior")
        local s1 = L.sectionAt()
        local onlyCombatW = GUI:CreateFormCheckbox(s1.frame, nil, "onlyInCombat", at, Refresh,
            { description = "Hide the action tracker while you are out of combat. Useful if you only want it active during pulls." })
        local clearCombatW = GUI:CreateFormCheckbox(s1.frame, nil, "clearOnCombatEnd", at, Refresh,
            { description = "Empty the tracker when combat ends instead of leaving the last pull's spells on screen." })
        s1.AddRow(row(s1.frame, "Only Show In Combat", onlyCombatW), row(s1.frame, "Clear History On Combat End", clearCombatW))

        local fadeEnableW = GUI:CreateFormCheckbox(s1.frame, nil, "inactivityFadeEnabled", at, Refresh,
            { description = "Fade the tracker out after a period of no casts. The fade delay is configured below." })
        local fadeSecsW = GUI:CreateFormSlider(s1.frame, nil, 10, 60, 1, "inactivityFadeSeconds", at, Refresh,
            { description = "Seconds of inactivity before the tracker fades out. Only applies when Inactivity Fade-Out is on." })
        s1.AddRow(row(s1.frame, "Enable Inactivity Fade-Out", fadeEnableW), row(s1.frame, "Inactivity Timeout (sec)", fadeSecsW))

        local clearInactW = GUI:CreateFormCheckbox(s1.frame, nil, "clearOnInactivity", at, Refresh,
            { description = "Additionally wipe the tracked history once the inactivity timeout fires." })
        local showFailedW = GUI:CreateFormCheckbox(s1.frame, nil, "showFailedCasts", at, Refresh,
            { description = "Include failed or interrupted casts in the tracker. Useful for reviewing what cancelled your rotation." })
        s1.AddRow(row(s1.frame, "Clear History After Inactivity", clearInactW), row(s1.frame, "Show Failed/Interrupted Casts", showFailedW))
        L.closeSection(s1)

        -- LAYOUT
        L.headerAt("Layout")
        local s2 = L.sectionAt()
        local orientationOpts = {{value="VERTICAL",text="Vertical"},{value="HORIZONTAL",text="Horizontal"}}
        local orientW = GUI:CreateFormDropdown(s2.frame, nil, orientationOpts, "orientation", at, Refresh,
            { description = "Whether tracked spells stack vertically or extend horizontally." })
        local invertW = GUI:CreateFormCheckbox(s2.frame, nil, "invertScrollDirection", at, Refresh,
            { description = "Flip the direction new entries enter from. Put newest spells at the top/left instead of bottom/right (or vice versa)." })
        s2.AddRow(row(s2.frame, "Bar Orientation", orientW), row(s2.frame, "Invert Scroll Direction", invertW))

        local maxEntW = GUI:CreateFormSlider(s2.frame, nil, 3, 10, 1, "maxEntries", at, Refresh,
            { description = "How many spell entries the tracker keeps on screen at once." })
        local iconSizeW = GUI:CreateFormSlider(s2.frame, nil, 16, 64, 1, "iconSize", at, Refresh,
            { description = "Pixel size of each spell icon in the tracker." })
        s2.AddRow(row(s2.frame, "Max Entries", maxEntW), row(s2.frame, "Icon Size", iconSizeW))

        local iconSpaceW = GUI:CreateFormSlider(s2.frame, nil, 0, 24, 1, "iconSpacing", at, Refresh,
            { description = "Pixel gap between adjacent icons." })
        s2.AddRow(row(s2.frame, "Icon Spacing", iconSpaceW))
        L.closeSection(s2)

        -- ICON BORDER
        L.headerAt("Icon Border")
        local s3 = L.sectionAt()
        local hideIconBdrW = GUI:CreateFormCheckbox(s3.frame, nil, "iconHideBorder", at, Refresh,
            { description = "Hide the border drawn around each spell icon." })
        s3.AddRow(row(s3.frame, "Hide Icon Borders", hideIconBdrW))

        if ns.QUI_BorderControl then
            local iconSrcW, iconColW = ns.QUI_BorderControl.Attach(GUI, s3.frame, at, "icon", Refresh,
                { label = "Icon Border Source", colorLabel = "Icon Border Color" })
            s3.AddRow(row(s3.frame, "Icon Border Source", iconSrcW), row(s3.frame, "Icon Border Color", iconColW))
        end
        L.closeSection(s3)

        -- CONTAINER BACKDROP & BORDER
        L.headerAt("Backdrop & Border")
        local s4 = L.sectionAt()
        local showBgW = GUI:CreateFormCheckbox(s4.frame, nil, "showBackdrop", at, Refresh,
            { description = "Draw a background behind the tracker to help it stand out." })
        local bgColorW = GUI:CreateFormColorPicker(s4.frame, nil, "backdropColor", at, Refresh, nil,
            { description = "Color used for the tracker background." })
        s4.AddRow(row(s4.frame, "Show Container Background", showBgW), row(s4.frame, "Container Background Color", bgColorW))

        local hideBdrW = GUI:CreateFormCheckbox(s4.frame, nil, "hideBorder", at, Refresh,
            { description = "Hide the border drawn around the tracker container." })
        local bdrSizeW = GUI:CreateFormSlider(s4.frame, nil, 0, 5, 0.5, "borderSize", at, Refresh,
            { description = "Thickness of the tracker container border. Set to 0 to hide the border." })
        s4.AddRow(row(s4.frame, "Hide Container Border", hideBdrW), row(s4.frame, "Border Size", bdrSizeW))

        if ns.QUI_BorderControl then
            local srcW, colW = ns.QUI_BorderControl.Attach(GUI, s4.frame, at, "", Refresh,
                { label = "Border Color Source", colorLabel = "Border Color" })
            s4.AddRow(row(s4.frame, "Border Color Source", srcW), row(s4.frame, "Border Color", colW))
        end
        L.closeSection(s4)

        -- SPELL BLOCKLIST (custom block — edit box + placeholder + help label)
        L.headerAt("Spell Blocklist")
        local blocklistBlock = CreateFrame("Frame", nil, content)
        local BLOCKLIST_HEIGHT = (FORM_ROW or 28) + 22
        local blocklistField = GUI:CreateFormEditBox(blocklistBlock, nil, "blocklistText", at, Refresh, {
            maxLetters = 300, live = true,
            onEditFocusGained = function(self) self:HighlightText() end,
        }, { description = "Comma-separated list of spell IDs to ignore in the tracker. Useful for muting passive procs or low-value abilities." })
        blocklistField:ClearAllPoints()
        blocklistField:SetPoint("TOPLEFT", blocklistBlock, "TOPLEFT", 0, -4)
        blocklistField:SetPoint("RIGHT", blocklistBlock, "RIGHT", 0, 0)

        if blocklistField.editBox then
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
        end

        local helpLabel = blocklistBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        helpLabel:SetPoint("TOPLEFT", blocklistField, "BOTTOMLEFT", 0, -2)
        helpLabel:SetPoint("RIGHT", blocklistBlock, "RIGHT", 0, 0)
        helpLabel:SetTextColor(0.6, 0.6, 0.6, 0.8)
        helpLabel:SetText("Comma-separated spell IDs to ignore in the tracker.")
        helpLabel:SetJustifyH("LEFT")

        L.placeCustom(blocklistBlock, BLOCKLIST_HEIGHT)

        return FinishProviderPage(L, content, key, "actionTracker")
    end })

    ---------------------------------------------------------------------------
    -- CONSUMABLES PROVIDER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("consumables", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.general then return 80 end
        local settings = db.general
        local L = MakeLayout(content)
        local function Refresh()
            if _G.QUI_RefreshConsumables then _G.QUI_RefreshConsumables() end
        end

        -- TRIGGERS
        L.headerAt("Triggers")
        local s1 = L.sectionAt()
        local readyW = GUI:CreateFormCheckbox(s1.frame, nil, "consumableOnReadyCheck", settings, nil,
            { description = "Show the consumables reminder whenever a ready check is triggered." })
        local dungW = GUI:CreateFormCheckbox(s1.frame, nil, "consumableOnDungeon", settings, nil,
            { description = "Show the consumables reminder when you zone into a dungeon." })
        s1.AddRow(row(s1.frame, "Ready Check", readyW), row(s1.frame, "Dungeon Entrance", dungW))

        local raidW = GUI:CreateFormCheckbox(s1.frame, nil, "consumableOnRaid", settings, nil,
            { description = "Show the consumables reminder when you zone into a raid." })
        local resW = GUI:CreateFormCheckbox(s1.frame, nil, "consumableOnResurrect", settings, nil,
            { description = "Show the consumables reminder when you resurrect inside an instance, to catch dropped flasks/food." })
        s1.AddRow(row(s1.frame, "Raid Entrance", raidW), row(s1.frame, "Instanced Resurrect", resW))
        L.closeSection(s1)

        -- BUFF CHECKS
        local mhLabel = (ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetMHLabel() or "Weapon Oil") .. " (MH)"
        local ohLabel = (ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetOHLabel() or "Weapon Oil") .. " (OH)"
        L.headerAt("Buff Checks")
        local s2 = L.sectionAt()
        local foodW = GUI:CreateFormCheckbox(s2.frame, nil, "consumableFood", settings, Refresh,
            { description = "Check for an active food buff." })
        local flaskW = GUI:CreateFormCheckbox(s2.frame, nil, "consumableFlask", settings, Refresh,
            { description = "Check for an active flask/phial buff." })
        s2.AddRow(row(s2.frame, "Food Buff", foodW), row(s2.frame, "Flask Buff", flaskW))

        local oilMHW = GUI:CreateFormCheckbox(s2.frame, nil, "consumableOilMH", settings, Refresh,
            { description = "Check that your main-hand has an active weapon consumable (oil/sharpening stone/etc.)." })
        local oilOHW = GUI:CreateFormCheckbox(s2.frame, nil, "consumableOilOH", settings, Refresh,
            { description = "Check that your off-hand has an active weapon consumable (oil/sharpening stone/etc.)." })
        s2.AddRow(row(s2.frame, mhLabel, oilMHW), row(s2.frame, ohLabel, oilOHW))

        local runeW = GUI:CreateFormCheckbox(s2.frame, nil, "consumableRune", settings, Refresh,
            { description = "Check for an active augment rune buff." })
        local hsW = GUI:CreateFormCheckbox(s2.frame, nil, "consumableHealthstone", settings, Refresh,
            { description = "Check that you have a healthstone in your bags." })
        s2.AddRow(row(s2.frame, "Augment Rune", runeW), row(s2.frame, "Healthstones", hsW))
        L.closeSection(s2)

        -- EXPIRATION WARNING
        L.headerAt("Expiration Warning")
        local s3 = L.sectionAt()
        local warnW = GUI:CreateFormCheckbox(s3.frame, nil, "consumableExpirationWarning", settings, nil,
            { description = "Flash the reminder when a tracked buff is within the threshold of expiring." })
        local threshW = GUI:CreateFormSlider(s3.frame, nil, 60, 600, 30, "consumableExpirationThreshold", settings, nil,
            { description = "Seconds remaining at which the expiration warning triggers." })
        s3.AddRow(row(s3.frame, "Warn When Buffs Expiring", warnW), row(s3.frame, "Warning Threshold (seconds)", threshW))
        L.closeSection(s3)

        -- DISPLAY
        L.headerAt("Display")
        local s4 = L.sectionAt()
        local persistW = GUI:CreateFormCheckbox(s4.frame, nil, "consumablePersistent", settings, function()
            if settings.consumablePersistent then
                if _G.QUI_ShowConsumables then _G.QUI_ShowConsumables() end
            else
                if _G.QUI_HideConsumables then _G.QUI_HideConsumables() end
            end
        end, { description = "Keep the reminder on screen all the time instead of showing it only when triggered." })
        local anchorW = GUI:CreateFormCheckbox(s4.frame, nil, "consumableAnchorMode", settings, Refresh,
            { description = "Snap the reminder to the ready check frame's position instead of using its own anchor." })
        s4.AddRow(row(s4.frame, "Always Show (Persistent)", persistW), row(s4.frame, "Anchor to Ready Check", anchorW))

        local iconSizeW = GUI:CreateFormSlider(s4.frame, nil, 24, 64, 2, "consumableIconSize", settings, Refresh,
            { description = "Pixel size of each consumable icon in the reminder." })
        local iconOffW = GUI:CreateFormSlider(s4.frame, nil, 0, 20, 1, "consumableIconOffset", settings, Refresh,
            { description = "Pixel gap between adjacent icons in the reminder." })
        s4.AddRow(row(s4.frame, "Icon Size", iconSizeW), row(s4.frame, "Icon Offset", iconOffW))

        local scaleW = GUI:CreateFormSlider(s4.frame, nil, 0.5, 3, 0.05, "consumableScale", settings, Refresh,
            { precision = 2, description = "Overall scale multiplier applied to the reminder frame." })
        s4.AddRow(row(s4.frame, "Scale", scaleW))
        L.closeSection(s4)

        -- MACROS: per-character auto-generated consumable macros. The cmDB
        -- proxy routes reads/writes to either profile or char DB depending on
        -- the "Character-specific" toggle. Widget refs remain stable across
        -- toggles because they bind to the proxy, not the underlying table.
        local cmProfileDB = settings and settings.consumableMacros
        local cmCharDB = ns.Helpers and ns.Helpers.GetCharConsumableMacrosDB
            and ns.Helpers.GetCharConsumableMacrosDB() or nil
        if (cmProfileDB or cmCharDB) and GUI.CreateFormDropdown then
            local CM = ns.ConsumableMacros
            local SEED_KEYS = {
                "enabled", "selectedFlask", "selectedPotion", "selectedHealth",
                "selectedHealthstone", "selectedAugment", "selectedVantus",
                "selectedWeapon", "chatNotifications",
            }
            local function ActiveCM()
                if cmCharDB and cmCharDB.characterSpecific then return cmCharDB end
                return cmProfileDB
            end
            local cmDB = setmetatable({}, {
                __index = function(_, k)
                    if k == "characterSpecific" then
                        return cmCharDB and cmCharDB.characterSpecific or false
                    end
                    local active = ActiveCM()
                    return active and active[k]
                end,
                __newindex = function(_, k, v)
                    if k == "characterSpecific" then
                        if not cmCharDB then return end
                        local was = cmCharDB.characterSpecific and true or false
                        cmCharDB.characterSpecific = v and true or false
                        if cmCharDB.characterSpecific and not was and cmProfileDB then
                            for _, kk in ipairs(SEED_KEYS) do
                                cmCharDB[kk] = cmProfileDB[kk]
                            end
                        end
                        return
                    end
                    local active = ActiveCM()
                    if active then active[k] = v end
                end,
            })
            local function MacroRefresh()
                if CM then CM:ForceRefresh() end
            end
            local fallback = { { value = "none", text = "None" } }

            L.headerAt("Macros")
            local s5 = L.sectionAt()
            local charSpecW = GUI:CreateFormCheckbox(s5.frame, nil, "characterSpecific", cmDB, function()
                if CM then
                    if cmDB.enabled then CM:ForceRefresh() else CM:DeleteMacros() end
                end
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff60A5FA[QUI]|r Consumable macro selections are now "
                        .. (cmDB.characterSpecific
                            and "|cffffffffper-character|r for this character."
                            or "|cffffffffshared|r across this profile.")
                        .. " Reopen this page to refresh the displayed values."
                    )
                end
            end, { description = "When enabled, the macro selections below are stored per-character instead of being shared by every character on this AceDB profile. The toggle itself is always per-character. Turning it on copies your current profile selections as a starting point." })
            local enableMacrosW = GUI:CreateFormCheckbox(s5.frame, nil, "enabled", cmDB, function()
                if CM then
                    if cmDB.enabled then CM:ForceRefresh() else CM:DeleteMacros() end
                end
            end, { description = "Auto-generate per-character QUI_* macros for the consumables selected below. Disabling deletes the macros." })
            s5.AddRow(row(s5.frame, "Character-specific", charSpecW), row(s5.frame, "Enable Consumable Macros", enableMacrosW))

            local mFlaskW = GUI:CreateFormDropdown(s5.frame, nil,
                (CM and CM.FLASK_OPTIONS) or fallback, "selectedFlask", cmDB, MacroRefresh,
                { description = "Which flask/phial the QUI flask macro resolves to on this character." })
            local mPotionW = GUI:CreateFormDropdown(s5.frame, nil,
                (CM and CM.POTION_OPTIONS) or fallback, "selectedPotion", cmDB, MacroRefresh,
                { description = "Which combat potion the QUI potion macro resolves to on this character." })
            s5.AddRow(row(s5.frame, "Flask Type", mFlaskW), row(s5.frame, "Potion Type", mPotionW))

            local healthW = GUI:CreateFormDropdown(s5.frame, nil,
                (CM and CM.HEALTH_OPTIONS) or fallback, "selectedHealth", cmDB, MacroRefresh,
                { description = "Which health potion the QUI health macro resolves to on this character." })
            local healthstoneW = GUI:CreateFormDropdown(s5.frame, nil,
                (CM and CM.HEALTHSTONE_OPTIONS) or fallback, "selectedHealthstone", cmDB, MacroRefresh,
                { description = "Which healthstone variant the QUI healthstone macro resolves to on this character." })
            s5.AddRow(row(s5.frame, "Health Potion", healthW), row(s5.frame, "Healthstone", healthstoneW))

            local augmentW = GUI:CreateFormDropdown(s5.frame, nil,
                (CM and CM.AUGMENT_OPTIONS) or fallback, "selectedAugment", cmDB, MacroRefresh,
                { description = "Which augment rune the QUI augment macro resolves to on this character." })
            local vantusW = GUI:CreateFormDropdown(s5.frame, nil,
                (CM and CM.VANTUS_OPTIONS) or fallback, "selectedVantus", cmDB, MacroRefresh,
                { description = "Which vantus rune the QUI vantus macro resolves to on this character." })
            s5.AddRow(row(s5.frame, "Augment Rune", augmentW), row(s5.frame, "Vantus Rune", vantusW))

            local weaponW = GUI:CreateFormDropdown(s5.frame, nil,
                (CM and CM.WEAPON_OPTIONS) or fallback, "selectedWeapon", cmDB, MacroRefresh,
                { description = "Which weapon consumable (oil, sharpening stone, etc.) the QUI weapon macro resolves to on this character." })
            local chatNotifyW = GUI:CreateFormCheckbox(s5.frame, nil, "chatNotifications", cmDB, nil,
                { description = "Print a chat message when consumable macros are regenerated." })
            s5.AddRow(row(s5.frame, "Weapon Consumable", weaponW), row(s5.frame, "Chat Notifications", chatNotifyW))
            L.closeSection(s5)
        end

        return FinishProviderPage(L, content, key, "consumables")
    end })

    ---------------------------------------------------------------------------
    -- MISSING RAID BUFFS
    ---------------------------------------------------------------------------
    RegisterSharedOnly("missingRaidBuffs", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.raidBuffs then return 80 end
        local settings = db.raidBuffs
        local L = MakeLayout(content)
        local function Refresh()
            if ns.RaidBuffs and ns.RaidBuffs.Refresh then ns.RaidBuffs:Refresh() end
        end

        -- GENERAL
        L.headerAt("General")
        local s1 = L.sectionAt()
        local onlyGroupW = GUI:CreateFormCheckbox(s1.frame, nil, "showOnlyInGroup", settings, Refresh,
            { description = "Hide the missing raid buffs display when you aren't in a party or raid." })
        local onlyInstW = GUI:CreateFormCheckbox(s1.frame, nil, "showOnlyInInstance", settings, Refresh,
            { description = "Hide the display while in the open world. Useful if you only care about raid buffs inside instances." })
        s1.AddRow(row(s1.frame, "Show Only When In Group", onlyGroupW), row(s1.frame, "Show Only In Dungeons/Raids", onlyInstW))

        local selfBuffsW = GUI:CreateFormCheckbox(s1.frame, nil, "showSelfBuffs", settings, Refresh,
            { description = "Also track self-only class buffs like rogue poisons, shaman weapon imbues, and mage armor." })
        local providerW = GUI:CreateFormCheckbox(s1.frame, nil, "providerMode", settings, Refresh,
            { description = "Restrict tracking to buffs your current spec can actually provide, so you only see what you need to cast." })
        s1.AddRow(row(s1.frame, "Show Class Self-Buffs (poisons, enchants, shields)", selfBuffsW), row(s1.frame, "Provider Mode (only buffs you can cast)", providerW))

        local hideLabelW = GUI:CreateFormCheckbox(s1.frame, nil, "hideLabelBar", settings, Refresh,
            { description = "Hide the label text under/beside the icon row for a more compact display." })
        local growOptions = {
            {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
            {value = "CENTER_H", text = "Center (H)"}, {value = "UP", text = "Up"},
            {value = "DOWN", text = "Down"}, {value = "CENTER_V", text = "Center (V)"},
        }
        local growW = GUI:CreateFormDropdown(s1.frame, nil, growOptions, "growDirection", settings, Refresh,
            { description = "Direction missing-buff icons extend from the anchor. Center options grow symmetrically in both directions." })
        s1.AddRow(row(s1.frame, "Hide Label Bar", hideLabelW), row(s1.frame, "Grow Direction", growW))
        L.closeSection(s1)

        -- APPEARANCE
        L.headerAt("Appearance")
        local s2 = L.sectionAt()
        local iconSizeW = GUI:CreateFormSlider(s2.frame, nil, 16, 64, 1, "iconSize", settings, Refresh,
            { description = "Pixel size of each missing-buff icon." })
        local iconSpaceW = GUI:CreateFormSlider(s2.frame, nil, 0, 20, 1, "iconSpacing", settings, Refresh,
            { description = "Pixel gap between adjacent icons." })
        s2.AddRow(row(s2.frame, "Icon Size", iconSizeW), row(s2.frame, "Icon Spacing", iconSpaceW))

        local labelSizeW = GUI:CreateFormSlider(s2.frame, nil, 8, 24, 1, "labelFontSize", settings, Refresh,
            { description = "Font size of the label text displayed on the label bar." })
        s2.AddRow(row(s2.frame, "Label Font Size", labelSizeW))
        L.closeSection(s2)

        -- ICON BORDER
        if not settings.iconBorder then
            settings.iconBorder = { show = true, width = 1, useClassColor = false, useAccentColor = false, color = {0.376, 0.647, 0.980, 1} }
        end
        local borderSettings = settings.iconBorder
        L.headerAt("Icon Border")
        local s3 = L.sectionAt()
        local showBdrW = GUI:CreateFormCheckbox(s3.frame, nil, "show", borderSettings, Refresh,
            { description = "Draw a border around each missing-buff icon." })
        local useClassBdrW = GUI:CreateFormCheckbox(s3.frame, nil, "useClassColor", borderSettings, Refresh,
            { description = "Color the icon borders by your class instead of the Border Color swatch below." })
        s3.AddRow(row(s3.frame, "Show Icon Border", showBdrW), row(s3.frame, "Use Class Color", useClassBdrW))

        local useAccentBdrW = GUI:CreateFormCheckbox(s3.frame, nil, "useAccentColor", borderSettings, Refresh,
            { description = "Color the icon borders using the UI accent color instead of the Border Color swatch below." })
        local bdrColorW = GUI:CreateFormColorPicker(s3.frame, nil, "color", borderSettings, Refresh, nil,
            { description = "Color used for icon borders when Class Color and Accent Color are both off." })
        s3.AddRow(row(s3.frame, "Use Accent Color", useAccentBdrW), row(s3.frame, "Border Color", bdrColorW))

        local bdrWidthW = GUI:CreateFormSlider(s3.frame, nil, 1, 4, 1, "width", borderSettings, Refresh,
            { description = "Thickness of the icon border in pixels." })
        s3.AddRow(row(s3.frame, "Border Width", bdrWidthW))
        L.closeSection(s3)

        -- BUFF COUNT
        if not settings.buffCount then
            settings.buffCount = { show = true, position = "BOTTOM", fontSize = 10, color = {1, 1, 1, 1} }
        end
        local countSettings = settings.buffCount
        L.headerAt("Buff Count")
        local s4 = L.sectionAt()
        local showCountW = GUI:CreateFormCheckbox(s4.frame, nil, "show", countSettings, Refresh,
            { description = "Show a count next to each missing buff indicating how many group members are missing it." })
        local countPosOptions = {
            {value = "TOP", text = "Top"}, {value = "BOTTOM", text = "Bottom"},
            {value = "LEFT", text = "Left"}, {value = "RIGHT", text = "Right"},
        }
        local countPosW = GUI:CreateFormDropdown(s4.frame, nil, countPosOptions, "position", countSettings, Refresh,
            { description = "Which side of the icon the count text is placed on." })
        s4.AddRow(row(s4.frame, "Show Buff Count", showCountW), row(s4.frame, "Count Position", countPosW))

        local countSizeW = GUI:CreateFormSlider(s4.frame, nil, 8, 18, 1, "fontSize", countSettings, Refresh,
            { description = "Font size of the count text." })
        local countColorW = GUI:CreateFormColorPicker(s4.frame, nil, "color", countSettings, Refresh, nil,
            { description = "Color of the count text." })
        s4.AddRow(row(s4.frame, "Count Font Size", countSizeW), row(s4.frame, "Count Color", countColorW))

        local countXW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "offsetX", countSettings, Refresh,
            { description = "Horizontal pixel offset for the count text from its anchor. Positive moves right, negative moves left." })
        local countYW = GUI:CreateFormSlider(s4.frame, nil, -50, 50, 1, "offsetY", countSettings, Refresh,
            { description = "Vertical pixel offset for the count text from its anchor. Positive moves up, negative moves down." })
        s4.AddRow(row(s4.frame, "Count X Offset", countXW), row(s4.frame, "Count Y Offset", countYW))
        L.closeSection(s4)

        return FinishProviderPage(L, content, key, "missingRaidBuffs")
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

    RegisterSharedOnly("tooltipAnchor", { build = function(content, key, _width)
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

        local L = MakeLayout(content)
        local function RefreshTooltips() if ns.QUI_RefreshTooltips then ns.QUI_RefreshTooltips() end end
        local function RefreshTooltipFontSize()
            if ns.QUI_RefreshTooltipFontSize then ns.QUI_RefreshTooltipFontSize()
            else RefreshTooltips() end
        end
        local function RefreshTooltipSkin() if ns.QUI_RefreshTooltipSkinColors then ns.QUI_RefreshTooltipSkinColors() end end

        -- TOOLTIP SKINNING
        L.headerAt("Tooltip Skinning")
        local s1 = L.sectionAt()
        local skinW = GUI:CreateFormCheckbox(s1.frame, nil, "skinTooltips", tooltip, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end, { description = "Apply the QUI theme (colors, border) to all game tooltips. Requires a UI reload to take effect." })
        local bgColorW = GUI:CreateFormColorPicker(s1.frame, nil, "bgColor", tooltip, RefreshTooltipSkin, nil,
            { description = "Background color applied to skinned tooltips." })
        s1.AddRow(row(s1.frame, "Skin Tooltips", skinW), row(s1.frame, "Background Color", bgColorW))

        local bgOpacityW = GUI:CreateFormSlider(s1.frame, nil, 0, 1, 0.05, "bgOpacity", tooltip, RefreshTooltipSkin,
            { precision = 2, description = "Opacity of the tooltip background (0 is invisible, 1 is fully opaque)." })
        local showBdrW = GUI:CreateFormCheckbox(s1.frame, nil, "showBorder", tooltip, RefreshTooltipSkin,
            { description = "Draw a border around skinned tooltips." })
        s1.AddRow(row(s1.frame, "Background Opacity", bgOpacityW), row(s1.frame, "Show Border", showBdrW))

        local bdrThickW = GUI:CreateFormSlider(s1.frame, nil, 1, 10, 1, "borderThickness", tooltip, RefreshTooltipSkin,
            { description = "Thickness of the tooltip border in pixels." })
        local borderSourceDrop, borderColorPicker = ns.QUI_BorderControl.Attach(
            GUI, s1.frame, tooltip, "", RefreshTooltipSkin,
            { label = "Border Color Source", colorLabel = "Border Color" }
        )
        s1.AddRow(row(s1.frame, "Border Thickness", bdrThickW))
        s1.AddRow(row(s1.frame, "Border Color Source", borderSourceDrop), row(s1.frame, "Border Color", borderColorPicker))

        local hideHealthW = GUI:CreateFormCheckbox(s1.frame, nil, "hideHealthBar", tooltip, RefreshTooltips,
            { description = "Hide the health bar shown on player, NPC, and enemy tooltips." })
        s1.AddRow(row(s1.frame, "Hide Health Bar", hideHealthW))
        L.closeSection(s1)

        -- FONT & CONTENT
        L.headerAt("Font & Content")
        local s2 = L.sectionAt()
        local fontSizeW = GUI:CreateFormSlider(s2.frame, nil, 8, 24, 1, "fontSize", tooltip, RefreshTooltipFontSize,
            { description = "Font size of tooltip text." })
        local spellIDsW = GUI:CreateFormCheckbox(s2.frame, nil, "showSpellIDs", tooltip, RefreshTooltips,
            { description = "Display spell ID and icon ID on buff, debuff, and spell tooltips. May not populate in combat." })
        s2.AddRow(row(s2.frame, "Tooltip Font Size", fontSizeW), row(s2.frame, "Show Spell/Icon IDs", spellIDsW))

        local classColorNameW = GUI:CreateFormCheckbox(s2.frame, nil, "classColorName", tooltip, RefreshTooltips,
            { description = "Color player names in tooltips by their class." })
        local hideDelayW = GUI:CreateFormSlider(s2.frame, nil, 0, 2, 0.1, "hideDelay", tooltip, RefreshTooltips,
            { precision = 1, description = "Seconds before the tooltip fades after your mouse leaves. 0 means instant hide." })
        s2.AddRow(row(s2.frame, "Class Color Player Names", classColorNameW), row(s2.frame, "Hide Delay", hideDelayW))

        local hideServerW = GUI:CreateFormCheckbox(s2.frame, nil, "hideServerName", tooltip, RefreshTooltips,
            { description = "Strip the realm name from cross-realm player tooltips for a cleaner display." })
        local hideTitleW = GUI:CreateFormCheckbox(s2.frame, nil, "hidePlayerTitle", tooltip, RefreshTooltips,
            { description = "Hide character titles on player tooltips." })
        s2.AddRow(row(s2.frame, "Hide Server Name", hideServerW), row(s2.frame, "Hide Player Titles", hideTitleW))

        local showTargetW = GUI:CreateFormCheckbox(s2.frame, nil, "showTooltipTarget", tooltip, RefreshTooltips,
            { description = "Show the unit's current target on its tooltip. Updates live as the target changes." })
        local showMountW = GUI:CreateFormCheckbox(s2.frame, nil, "showPlayerMount", tooltip, RefreshTooltips,
            { description = "Show the active mount's name on mounted player tooltips." })
        s2.AddRow(row(s2.frame, "Show Target", showTargetW), row(s2.frame, "Show Player Mount", showMountW))

        local showMythicW = GUI:CreateFormCheckbox(s2.frame, nil, "showPlayerMythicRating", tooltip, RefreshTooltips,
            { description = "Show the player's Mythic+ rating on player tooltips." })
        s2.AddRow(row(s2.frame, "Show M+ Rating", showMythicW))

        local hideGuildW = GUI:CreateFormToggle(s2.frame, nil, "hideGuildName", tooltip, RefreshTooltips,
            { description = "Strip the guild name line from player tooltips." })
        s2.AddRow(row(s2.frame, "Hide Guild Name", hideGuildW))
        L.closeSection(s2)

        -- PLAYER ITEM LEVEL
        L.headerAt("Player Item Level")
        local s3 = L.sectionAt()

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

        local showILvlW = GUI:CreateFormCheckbox(s3.frame, nil, "showPlayerItemLevel", tooltip, function()
            RefreshPlayerItemLevelBracketInputs()
            RefreshTooltips()
        end, { description = "Show average equipped item level on player tooltips. Remote players may populate after a short inspect delay." })
        local colorILvlW = GUI:CreateFormCheckbox(s3.frame, nil, "colorPlayerItemLevel", tooltip, function()
            RefreshPlayerItemLevelBracketInputs()
            RefreshTooltips()
        end, { description = "Color the item level number using the bracket thresholds defined below (grey/white/green/blue/purple/orange)." })
        s3.AddRow(row(s3.frame, "Show Player Item Level", showILvlW), row(s3.frame, "Color Player Item Level by Bracket", colorILvlW))
        L.closeSection(s3)

        -- Bracket breakpoint inputs — custom block below the Player Item Level card
        local bracketBlock = CreateFrame("Frame", nil, content)
        local BRACKET_BLOCK_HEIGHT = 16 + 48 + 24

        itemLevelBracketHeader = bracketBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemLevelBracketHeader:SetPoint("TOPLEFT", bracketBlock, "TOPLEFT", 0, 0)
        itemLevelBracketHeader:SetText("Bracket Breakpoints")
        itemLevelBracketHeader:SetTextColor(GUI.Colors.text[1], GUI.Colors.text[2], GUI.Colors.text[3], 1)

        local bracketRow = CreateFrame("Frame", nil, bracketBlock)
        bracketRow:SetHeight(44)
        bracketRow:SetPoint("TOPLEFT", itemLevelBracketHeader, "BOTTOMLEFT", 0, -4)
        bracketRow:SetPoint("RIGHT", bracketBlock, "RIGHT", 0, 0)

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

        itemLevelBracketInfo = GUI:CreateLabel(bracketBlock, "Inclusive starts for each color bracket. Values below White use the grey bracket.", 10, GUI.Colors.textMuted)
        itemLevelBracketInfo:SetPoint("TOPLEFT", bracketRow, "BOTTOMLEFT", 0, -4)
        itemLevelBracketInfo:SetPoint("RIGHT", bracketBlock, "RIGHT", 0, 0)
        itemLevelBracketInfo:SetJustifyH("LEFT")

        RefreshPlayerItemLevelBracketInputs()
        L.placeCustom(bracketBlock, BRACKET_BLOCK_HEIGHT)

        -- CURSOR ANCHOR
        L.headerAt("Cursor Anchor")
        local s4 = L.sectionAt()
        local anchorCursorW = GUI:CreateFormCheckbox(s4.frame, nil, "anchorToCursor", tooltip, RefreshTooltips,
            { description = "Make tooltips follow your mouse cursor instead of using their default anchor point." })
        local cursorAnchorW = GUI:CreateFormDropdown(s4.frame, nil, anchorOptions, "cursorAnchor", tooltip, RefreshTooltips,
            { description = "Which corner of the tooltip is pinned to the cursor position." })
        s4.AddRow(row(s4.frame, "Anchor Tooltip to Cursor", anchorCursorW), row(s4.frame, "Cursor Anchor Point", cursorAnchorW))

        local cursorXW = GUI:CreateFormSlider(s4.frame, nil, -200, 200, 1, "cursorOffsetX", tooltip, RefreshTooltips,
            { description = "Horizontal pixel offset between the cursor and the tooltip anchor. Positive moves right, negative moves left." })
        local cursorYW = GUI:CreateFormSlider(s4.frame, nil, -200, 200, 1, "cursorOffsetY", tooltip, RefreshTooltips,
            { description = "Vertical pixel offset between the cursor and the tooltip anchor. Positive moves up, negative moves down." })
        s4.AddRow(row(s4.frame, "Cursor X Offset", cursorXW), row(s4.frame, "Cursor Y Offset", cursorYW))
        L.closeSection(s4)

        -- TOOLTIP VISIBILITY
        if tooltip.visibility then
            local visibilityOptions = {
                {value = "SHOW", text = "Always Show"},
                {value = "HIDE", text = "Always Hide"},
                {value = "SHIFT", text = "Shift to Show"},
                {value = "CTRL", text = "Ctrl to Show"},
                {value = "ALT", text = "Alt to Show"},
            }

            L.headerAt("Tooltip Visibility")
            local s5 = L.sectionAt()
            local npcsW = GUI:CreateFormDropdown(s5.frame, nil, visibilityOptions, "npcs", tooltip.visibility, RefreshTooltips,
                { description = "When to show tooltips for units (NPCs and players). Modifier options only show the tooltip while the key is held." })
            local abilitiesW = GUI:CreateFormDropdown(s5.frame, nil, visibilityOptions, "abilities", tooltip.visibility, RefreshTooltips,
                { description = "When to show tooltips for spells and abilities. Modifier options only show the tooltip while the key is held." })
            s5.AddRow(row(s5.frame, "NPCs & Players", npcsW), row(s5.frame, "Abilities", abilitiesW))

            local itemsW = GUI:CreateFormDropdown(s5.frame, nil, visibilityOptions, "items", tooltip.visibility, RefreshTooltips,
                { description = "When to show tooltips for items in your bags and equipment. Modifier options only show the tooltip while the key is held." })
            local framesW = GUI:CreateFormDropdown(s5.frame, nil, visibilityOptions, "frames", tooltip.visibility, RefreshTooltips,
                { description = "When to show tooltips on UI frames (action bars, unit frames, etc.)." })
            s5.AddRow(row(s5.frame, "Inventory", itemsW), row(s5.frame, "Frames", framesW))

            local cdmW = GUI:CreateFormDropdown(s5.frame, nil, visibilityOptions, "cdm", tooltip.visibility, RefreshTooltips,
                { description = "When to show tooltips on QUI Cooldown Manager icons." })
            local customTrackersW = GUI:CreateFormDropdown(s5.frame, nil, visibilityOptions, "customTrackers", tooltip.visibility, RefreshTooltips,
                { description = "When to show tooltips on QUI custom item/spell trackers." })
            s5.AddRow(row(s5.frame, "Cooldown Manager", cdmW), row(s5.frame, "Custom Items/Spells", customTrackersW))
            L.closeSection(s5)
        end

        -- COMBAT
        L.headerAt("Combat")
        local s6 = L.sectionAt()
        local hideCombatW = GUI:CreateFormCheckbox(s6.frame, nil, "hideInCombat", tooltip, RefreshTooltips,
            { description = "Suppress all tooltips while you're in combat. Use the modifier key below to force-show them when needed." })
        local combatOverrideOptions = {
            {value = "NONE", text = "None"},
            {value = "SHIFT", text = "Shift"},
            {value = "CTRL", text = "Ctrl"},
            {value = "ALT", text = "Alt"},
        }
        local combatKeyW = GUI:CreateFormDropdown(s6.frame, nil, combatOverrideOptions, "combatKey", tooltip, RefreshTooltips,
            { description = "Modifier key that force-shows tooltips even while Hide Tooltips in Combat is active." })
        s6.AddRow(row(s6.frame, "Hide Tooltips in Combat", hideCombatW), row(s6.frame, "Combat Modifier Key", combatKeyW))
        L.closeSection(s6)

        return FinishProviderPage(L, content, key, "tooltipAnchor")
    end })

    ---------------------------------------------------------------------------
    -- SKYRIDING
    ---------------------------------------------------------------------------
    RegisterSharedOnly("skyriding", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db then return 80 end
        if not db.skyriding then db.skyriding = {} end
        local sr = db.skyriding

        -- Initialize defaults
        if sr.width == nil then sr.width = 250 end
        if sr.vigorHeight == nil then sr.vigorHeight = 20 end
        if sr.secondWindHeight == nil then sr.secondWindHeight = 20 end
        if sr.barTexture == nil then sr.barTexture = "Quazii v4" end
        if sr.showSegments == nil then sr.showSegments = true end
        if sr.showSpeed == nil then sr.showSpeed = true end
        if sr.showVigorText == nil then sr.showVigorText = true end
        if sr.secondWindMode == nil then sr.secondWindMode = "MINIBAR" end
        if sr.secondWindScale == nil then sr.secondWindScale = 2.1 end
        if sr.segmentThickness == nil then sr.segmentThickness = 1 end
        if sr.visibility == nil then sr.visibility = "FLYING_ONLY" end
        if sr.fadeDelay == nil then sr.fadeDelay = 1 end
        if sr.speedFormat == nil then sr.speedFormat = "PERCENT" end
        if sr.vigorTextFormat == nil then sr.vigorTextFormat = "FRACTION" end
        if sr.useClassColorVigor == nil then sr.useClassColorVigor = false end
        if sr.useClassColorSecondWind == nil then sr.useClassColorSecondWind = false end
        if sr.useThrillOfTheSkiesColor == nil then sr.useThrillOfTheSkiesColor = true end

        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshSkyriding then _G.QUI_RefreshSkyriding() end end

        -- VISIBILITY
        L.headerAt("Visibility")
        local s1 = L.sectionAt()
        local visW = GUI:CreateFormDropdown(s1.frame, nil, {
            {value = "ALWAYS", text = "Always Visible"},
            {value = "FLYING_ONLY", text = "Only When Flying"},
            {value = "AUTO", text = "Auto (fade when grounded)"},
        }, "visibility", sr, Refresh,
            { description = "When the skyriding bar is shown: always on, only while flying, or auto-fade out shortly after you land." })
        local fadeDelayW = GUI:CreateFormSlider(s1.frame, nil, 0, 10, 0.5, "fadeDelay", sr, Refresh,
            { description = "Seconds to wait after landing before the bar fades out in Auto mode." })
        s1.AddRow(row(s1.frame, "Visibility Mode", visW), row(s1.frame, "Fade Delay (sec)", fadeDelayW))

        local fadeDurW = GUI:CreateFormSlider(s1.frame, nil, 0.1, 1.0, 0.1, "fadeDuration", sr, Refresh,
            { description = "How long the fade-in / fade-out animation takes, in seconds." })
        local hideFarmW = GUI:CreateFormCheckbox(s1.frame, nil, "hideWhenFarmHudShown", sr, Refresh,
            { description = "Automatically hide the skyriding bar while FarmHud is on screen, to avoid the two overlapping." })
        s1.AddRow(row(s1.frame, "Fade Speed (sec)", fadeDurW), row(s1.frame, "Hide When FarmHud Is Active", hideFarmW))
        L.closeSection(s1)

        -- BAR (shared by both bars)
        L.headerAt("Bar")
        local s2 = L.sectionAt()
        local widthW = GUI:CreateFormSlider(s2.frame, nil, 100, 500, 1, "width", sr, Refresh,
            { description = "Pixel width of the skyriding bar." })
        local barTexW = GUI:CreateFormDropdown(s2.frame, nil, U.GetTextureList(), "barTexture", sr, Refresh,
            { description = "Statusbar texture used for both skyriding bars. Supports any extra media packages you have available." })
        s2.AddRow(row(s2.frame, "Width", widthW), row(s2.frame, "Bar Texture", barTexW))

        local segColorW = GUI:CreateFormColorPicker(s2.frame, nil, "segmentColor", sr, Refresh, nil,
            { description = "Color of the vertical segment markers between charges, on both bars." })
        local segThickW = GUI:CreateFormSlider(s2.frame, nil, 1, 5, 1, "segmentThickness", sr, Refresh,
            { description = "Pixel thickness of the segment markers, on both bars." })
        s2.AddRow(row(s2.frame, "Segment Marker Color", segColorW), row(s2.frame, "Segment Thickness", segThickW))
        L.closeSection(s2)

        -- VIGOR
        L.headerAt("Vigor")
        local s3 = L.sectionAt()
        local vigorHW = GUI:CreateFormSlider(s3.frame, nil, 4, 30, 1, "vigorHeight", sr, Refresh,
            { description = "Pixel height of the main vigor bar." })
        local bgColorW = GUI:CreateFormColorPicker(s3.frame, nil, "backgroundColor", sr, Refresh, nil,
            { description = "Background color behind the vigor bar." })
        s3.AddRow(row(s3.frame, "Vigor Height", vigorHW), row(s3.frame, "Background Color", bgColorW))

        local classVigorW = GUI:CreateFormCheckbox(s3.frame, nil, "useClassColorVigor", sr, Refresh,
            { description = "Color the vigor bar by your class instead of the Fill Color swatch." })
        local vigorFillW = GUI:CreateFormColorPicker(s3.frame, nil, "barColor", sr, Refresh, nil,
            { description = "Fill color of the vigor bar when Use Class Color is off." })
        s3.AddRow(row(s3.frame, "Use Class Color", classVigorW), row(s3.frame, "Fill Color", vigorFillW))

        local showSegW = GUI:CreateFormCheckbox(s3.frame, nil, "showSegments", sr, Refresh,
            { description = "Show the vertical markers between vigor charges on the vigor bar." })
        local rechargeColorW = GUI:CreateFormColorPicker(s3.frame, nil, "rechargeColor", sr, Refresh, nil,
            { description = "Color of the charging-segment highlight as a vigor charge recovers." })
        s3.AddRow(row(s3.frame, "Show Segment Markers", showSegW), row(s3.frame, "Recharge Animation Color", rechargeColorW))

        local showVigorW = GUI:CreateFormCheckbox(s3.frame, nil, "showVigorText", sr, Refresh,
            { description = "Show numeric vigor count on the bar." })
        local vigorFmtW = GUI:CreateFormDropdown(s3.frame, nil, {
            {value = "FRACTION", text = "Fraction (4/6)"}, {value = "CURRENT", text = "Current Only (4)"},
        }, "vigorTextFormat", sr, Refresh,
            { description = "How vigor is displayed: as a fraction (current/max) or just the current value." })
        s3.AddRow(row(s3.frame, "Show Vigor Count", showVigorW), row(s3.frame, "Vigor Format", vigorFmtW))

        local thrillToggleW = GUI:CreateFormCheckbox(s3.frame, nil, "useThrillOfTheSkiesColor", sr, Refresh,
            { description = "Swap the vigor bar color while Thrill of the Skies is active so the buff state is obvious." })
        local thrillColorW = GUI:CreateFormColorPicker(s3.frame, nil, "thrillOfTheSkiesColor", sr, Refresh, nil,
            { description = "Fill color used for the vigor bar while Thrill of the Skies is active." })
        s3.AddRow(row(s3.frame, "Change Color with Thrill of the Skies", thrillToggleW), row(s3.frame, "Thrill of the Skies Color", thrillColorW))
        L.closeSection(s3)

        -- SECOND WIND
        L.headerAt("Second Wind")
        local s4 = L.sectionAt()
        local swModeW = GUI:CreateFormDropdown(s4.frame, nil, {
            {value = "MINIBAR", text = "Mini Bar"},
            {value = "PIPS", text = "Pips"},
            {value = "TEXT", text = "Text (SW: 2/3)"},
            {value = "HIDDEN", text = "Hidden"},
        }, "secondWindMode", sr, Refresh,
            { description = "How Second Wind charges are shown: a mini bar below the vigor bar, pips above it, a text readout below it, or hidden entirely." })
        local swScaleW = GUI:CreateFormSlider(s4.frame, nil, 0.5, 4, 0.1, "secondWindScale", sr, Refresh,
            { description = "Size of the Second Wind pips (Pips mode only)." })
        s4.AddRow(row(s4.frame, "Display Mode", swModeW), row(s4.frame, "Pips Size", swScaleW))

        local swHW = GUI:CreateFormSlider(s4.frame, nil, 2, 20, 1, "secondWindHeight", sr, Refresh,
            { description = "Pixel height of the Second Wind bar (Mini Bar mode only)." })
        local swBgColorW = GUI:CreateFormColorPicker(s4.frame, nil, "secondWindBackgroundColor", sr, Refresh, nil,
            { description = "Background color behind the Second Wind bar (Mini Bar mode only)." })
        s4.AddRow(row(s4.frame, "Height", swHW), row(s4.frame, "Background Color", swBgColorW))

        local classSWW = GUI:CreateFormCheckbox(s4.frame, nil, "useClassColorSecondWind", sr, Refresh,
            { description = "Color the Second Wind display by your class instead of the Second Wind Color swatch." })
        local swColorW = GUI:CreateFormColorPicker(s4.frame, nil, "secondWindColor", sr, Refresh, nil,
            { description = "Color of the Second Wind display when Use Class Color is off." })
        s4.AddRow(row(s4.frame, "Use Class Color", classSWW), row(s4.frame, "Second Wind Color", swColorW))
        L.closeSection(s4)

        -- TEXT DISPLAY
        L.headerAt("Text Display")
        local s5 = L.sectionAt()
        local showSpeedW = GUI:CreateFormCheckbox(s5.frame, nil, "showSpeed", sr, Refresh,
            { description = "Show your current flight speed next to the vigor bar." })
        local speedFmtW = GUI:CreateFormDropdown(s5.frame, nil, {
            {value = "PERCENT", text = "Percentage (312%)"}, {value = "RAW", text = "Raw Speed (9.5)"},
        }, "speedFormat", sr, Refresh,
            { description = "Format the speed readout as a percentage of base run speed or as the raw yards-per-second value." })
        s5.AddRow(row(s5.frame, "Show Speed", showSpeedW), row(s5.frame, "Speed Format", speedFmtW))

        local showAbilityW = GUI:CreateFormCheckbox(s5.frame, nil, "showAbilityIcon", sr, Refresh,
            { description = "Show a Whirling Surge cooldown icon on the skyriding bar." })
        local textSizeW = GUI:CreateFormSlider(s5.frame, nil, 8, 24, 1, "vigorFontSize", sr, function()
            sr.speedFontSize = sr.vigorFontSize; Refresh()
        end, { description = "Font size of the vigor and speed text overlays on the bar." })
        s5.AddRow(row(s5.frame, "Show Whirling Surge Icon", showAbilityW), row(s5.frame, "Text Font Size", textSizeW))
        L.closeSection(s5)

        -- BORDER
        L.headerAt("Border")
        local s6 = L.sectionAt()
        local borderSizeW = GUI:CreateFormSlider(s6.frame, nil, 0, 5, 1, "borderSize", sr, Refresh,
            { description = "Thickness of the border drawn around the skyriding bar." })
        s6.AddRow(row(s6.frame, "Border Size", borderSizeW))

        local srcW, colW = ns.QUI_BorderControl.Attach(GUI, s6.frame, sr, "", Refresh,
            { label = "Border Color Source", colorLabel = "Border Color" })
        s6.AddRow(row(s6.frame, "Border Color Source", srcW), row(s6.frame, "Border Color", colW))
        L.closeSection(s6)

        return FinishProviderPage(L, content, key, "skyriding")
    end })

    ---------------------------------------------------------------------------
    -- PARTY KEYSTONES
    ---------------------------------------------------------------------------
    RegisterSharedOnly("partyKeystones", { build = function(content, key, _width)
        local db = U.GetProfileDB()
        if not db or not db.general then return 80 end
        local general = db.general
        local L = MakeLayout(content)
        local function Refresh() if _G.QUI_RefreshKeyTracker then _G.QUI_RefreshKeyTracker() end end

        -- APPEARANCE
        L.headerAt("Appearance")
        local s1 = L.sectionAt()
        local fontW = GUI:CreateFormDropdown(s1.frame, nil, U.GetFontList(), "keyTrackerFont", general, Refresh,
            { description = "Font used for the party keystone tracker text." })
        local fontSizeW = GUI:CreateFormSlider(s1.frame, nil, 7, 12, 1, "keyTrackerFontSize", general, Refresh,
            { description = "Font size of the party keystone tracker entries." })
        s1.AddRow(row(s1.frame, "Font", fontW), row(s1.frame, "Font Size", fontSizeW))

        local textColorW = GUI:CreateFormColorPicker(s1.frame, nil, "keyTrackerTextColor", general, Refresh, nil,
            { description = "Color of the tracker text." })
        local widthW = GUI:CreateFormSlider(s1.frame, nil, 120, 250, 1, "keyTrackerWidth", general, Refresh,
            { description = "Pixel width of the party keystone tracker frame." })
        s1.AddRow(row(s1.frame, "Text Color", textColorW), row(s1.frame, "Frame Width", widthW))
        L.closeSection(s1)

        return FinishProviderPage(L, content, key, "partyKeystones")
    end })
end)
