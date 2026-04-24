--[[
    QUI QoL Shared Settings Providers
    Owns provider-backed settings content for QoL and gameplay movers/pages routed through the shared settings layer.
]]

local ADDON_NAME, ns = ...

local Settings = ns.Settings
local ProviderPanels = Settings and Settings.ProviderPanels
if not ProviderPanels or type(ProviderPanels.RegisterAfterLoad) ~= "function" then
    return
end

ProviderPanels:RegisterAfterLoad(function(ctx)
    local GUI = ctx.GUI
    local U = ctx.U
    local P = ctx.P
    local FORM_ROW = ctx.FORM_ROW
    local NotifyProviderFor = ctx.NotifyProviderFor
    local CreateSingleColumnCollapsible = ctx.CreateSingleColumnCollapsible
    local anchorOptions = ctx.anchorOptions
    local function RegisterSharedOnly(key, provider)
        ctx.RegisterShared(key, provider)
    end

    ---------------------------------------------------------------------------
    -- XP TRACKER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("xpTracker", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.xpTracker then return 80 end
        local xp = db.xpTracker
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshXPTracker then _G.QUI_RefreshXPTracker() end end

        U.CreateCollapsible(content, "Size & Text", 9 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Bar Width", 200, 1000, 1, "width", xp, Refresh, nil, { description = "Overall pixel width of the XP tracker frame." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 60, 200, 1, "height", xp, Refresh, nil, { description = "Overall pixel height of the XP tracker frame, including the header area and the bar." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Bar Height", 8, 40, 1, "barHeight", xp, Refresh, nil, { description = "Pixel height of just the XP fill bar inside the frame." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Header Font Size", 8, 22, 1, "headerFontSize", xp, Refresh, nil, { description = "Font size for the header row that shows your level and total XP gained." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Header Line Height", 12, 30, 1, "headerLineHeight", xp, Refresh, nil, { description = "Vertical spacing reserved for the header row. Increase if the header text is getting clipped." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 18, 1, "fontSize", xp, Refresh, nil, { description = "Font size for the detail rows below the header (session XP, time to level, etc.)." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Line Height", 10, 24, 1, "lineHeight", xp, Refresh, nil, { description = "Vertical spacing between detail rows." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "barTexture", xp, Refresh, { description = "Statusbar texture used for the XP fill. Supports any extra media packages you have available." }), body, sy)
            P(GUI:CreateFormDropdown(body, "Details Grow Direction", {{value="auto",text="Auto"},{value="up",text="Up"},{value="down",text="Down"}}, "detailsGrowDirection", xp, Refresh, { description = "Whether the detail rows stack above or below the bar. Auto picks based on where the frame is anchored on screen." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Colors", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "XP Bar Color", "barColor", xp, Refresh, nil, { description = "Fill color of the XP bar." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Rested XP Color", "restedColor", xp, Refresh, nil, { description = "Color of the rested-XP overlay drawn on top of the regular fill." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Backdrop Color", "backdropColor", xp, Refresh, nil, { description = "Background color behind the XP bar." }), body, sy)
            P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", xp, Refresh, nil, { description = "Border color around the XP bar frame." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Display", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Bar Text", "showBarText", xp, Refresh, { description = "Show the current/next XP values and percent as text on top of the bar." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Rested XP Overlay", "showRested", xp, Refresh, { description = "Overlay a rested-XP indicator showing how much bonus XP you have banked." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide Text Until Hover", "hideTextUntilHover", xp, Refresh, { description = "Hide the bar text until you mouse over the frame. Keeps the tracker visually clean between pulls." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "xpTracker", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- COMBAT TIMER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("combatTimer", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.combatTimer then return 80 end
        local ct = db.combatTimer
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end end

        U.CreateCollapsible(content, "General", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Only Show In Encounters", "onlyShowInEncounters", ct, Refresh, { description = "Hide the combat timer outside of boss encounters, M+ dungeons, and PvP matches. Off shows the timer on every pull." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Width", 40, 200, 1, "width", ct, Refresh, nil, { description = "Pixel width of the combat timer frame." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 20, 100, 1, "height", ct, Refresh, nil, { description = "Pixel height of the combat timer frame." }), body, sy)
            P(GUI:CreateFormSlider(body, "Font Size", 12, 32, 1, "fontSize", ct, Refresh, nil, { description = "Font size of the elapsed-time text." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Text", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColorText", ct, Refresh, { description = "Color the timer text by your class instead of the Text Color swatch below." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Text Color", "textColor", ct, Refresh, nil, { description = "Color used for the timer text when Use Class Color is off." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Custom Font", "useCustomFont", ct, Refresh, { description = "Override the global font for this element with the font selected below." }), body, sy)
            local fonts = U.GetFontList(); if #fonts > 0 then P(GUI:CreateFormDropdown(body, "Font", fonts, "font", ct, Refresh, { description = "Custom font for the timer text. Requires Use Custom Font to be enabled." }), body, sy) end
        end, sections, relayout)

        U.BuildBackdropBorderSection(content, ct, sections, relayout, Refresh)

        U.BuildPositionCollapsible(content, "combatTimer", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- BREZ COUNTER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("brezCounter", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.brzCounter then return 80 end
        local bz = db.brzCounter
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end end

        U.CreateCollapsible(content, "General", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Lock Frame", "locked", bz, Refresh, { description = "Lock the battle-rez counter so it can't be accidentally dragged from its current position." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Width", 30, 100, 1, "width", bz, Refresh, nil, { description = "Pixel width of the counter frame." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 30, 100, 1, "height", bz, Refresh, nil, { description = "Pixel height of the counter frame." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Charges Font Size", 10, 28, 1, "fontSize", bz, Refresh, nil, { description = "Font size of the big number showing remaining battle-rez charges." }), body, sy)
            P(GUI:CreateFormSlider(body, "Timer Font Size", 8, 24, 1, "timerFontSize", bz, Refresh, nil, { description = "Font size of the recharge timer shown below the charge count." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Colors", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Charges Available", "hasChargesColor", bz, Refresh, nil, { description = "Color of the charge count when at least one battle-rez is available." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "No Charges", "noChargesColor", bz, Refresh, nil, { description = "Color of the charge count when all battle-rezzes have been used." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Class Color Timer Text", "useClassColorText", bz, Refresh, { description = "Color the recharge timer by your class instead of the Timer Text Color swatch below." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Timer Text Color", "timerColor", bz, Refresh, nil, { description = "Color used for the recharge timer when Class Color is off." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Custom Font", "useCustomFont", bz, Refresh, { description = "Override the global font for this element with the font selected below." }), body, sy)
            local fonts = U.GetFontList(); if #fonts > 0 then P(GUI:CreateFormDropdown(body, "Font", fonts, "font", bz, Refresh, { description = "Custom font for the counter text. Requires Use Custom Font to be enabled." }), body, sy) end
        end, sections, relayout)

        U.BuildBackdropBorderSection(content, bz, sections, relayout, Refresh)

        U.BuildPositionCollapsible(content, "brezCounter", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- ATONEMENT COUNTER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("atonementCounter", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.atonementCounter then return 80 end
        local ac = db.atonementCounter
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshAtonementCounter then _G.QUI_RefreshAtonementCounter() end end

        U.CreateCollapsible(content, "General", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Lock Frame", "locked", ac, Refresh, { description = "Lock the Atonement counter so it can't be accidentally dragged from its current position." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Only In Dungeons/Raids", "showOnlyInInstance", ac, Refresh, { description = "Hide the counter while in the open world. Useful if you only need it for instanced content." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Spell Icon", "hideIcon", ac, Refresh, { description = "Hide the Atonement spell icon and show only the count number." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Width", 30, 100, 1, "width", ac, Refresh, nil, { description = "Pixel width of the counter frame." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Height", 30, 100, 1, "height", ac, Refresh, nil, { description = "Pixel height of the counter frame." }), body, sy)
            P(GUI:CreateFormSlider(body, "Count Font Size", 10, 36, 1, "fontSize", ac, Refresh, nil, { description = "Font size of the Atonement count number." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Colors", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color Text", "useClassColorText", ac, Refresh, { description = "Color the count number by your class instead of the Active/Zero color swatches." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Active Count Color", "activeCountColor", ac, Refresh, nil, { description = "Color of the number when one or more Atonements are active." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Zero Count Color", "zeroCountColor", ac, Refresh, nil, { description = "Color of the number when no Atonements are active. Useful for spotting gaps at a glance." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Custom Font", "useCustomFont", ac, Refresh, { description = "Override the global font for this element with the font selected below." }), body, sy)
            local fonts = U.GetFontList(); if #fonts > 0 then P(GUI:CreateFormDropdown(body, "Font", fonts, "font", ac, Refresh, { description = "Custom font for the count number. Requires Use Custom Font to be enabled." }), body, sy) end
        end, sections, relayout)

        U.BuildBackdropBorderSection(content, ac, sections, relayout, Refresh)

        U.BuildPositionCollapsible(content, "atonementCounter", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- ROTATION ASSIST ICON
    ---------------------------------------------------------------------------
    RegisterSharedOnly("rotationAssistIcon", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.rotationAssistIcon then return 80 end
        local ra = db.rotationAssistIcon
        if ra.frameStrata ~= "LOW" and ra.frameStrata ~= "MEDIUM" then
            ra.frameStrata = "MEDIUM"
        end
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshRotationAssistIcon then _G.QUI_RefreshRotationAssistIcon() end end

        U.CreateCollapsible(content, "General", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Lock Position", "isLocked", ra, Refresh, { description = "Lock the rotation assist icon so it can't be accidentally dragged from its current position." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Cooldown Swipe", "cooldownSwipeEnabled", ra, Refresh, { description = "Show the clockwise cooldown swipe animation over the spell icon." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Visibility", {{value="always",text="Always"},{value="combat",text="In Combat"},{value="hostile",text="Hostile Target"}}, "visibility", ra, Refresh, { description = "When to show the icon: always visible, only in combat, or only when you have a hostile target." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Frame Strata", {{value="LOW",text="Low"},{value="MEDIUM",text="Medium"}}, "frameStrata", ra, Refresh, { description = "Draw layer for the icon. Medium sits above most UI; Low sits underneath nameplates and other mid-layer elements." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 16, 400, 1, "iconSize", ra, Refresh, nil, { description = "Pixel size of the spell icon." }), body, sy)
            P(GUI:CreateFormSlider(body, "Border Size", 0, 15, 1, "borderThickness", ra, Refresh, nil, { description = "Thickness of the border drawn around the icon. Set to 0 to hide the border." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Border & Keybind", 7 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", ra, Refresh, nil, { description = "Color of the border drawn around the icon." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Keybind", "showKeybind", ra, Refresh, { description = "Overlay the keybind text of the bound spell on the icon." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Keybind Color", "keybindColor", ra, Refresh, nil, { description = "Color of the keybind text." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Keybind Anchor", anchorOptions, "keybindAnchor", ra, Refresh, { description = "Which corner of the icon the keybind text is anchored to." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Keybind Size", 6, 48, 1, "keybindSize", ra, Refresh, nil, { description = "Font size of the keybind text." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Keybind X Offset", -50, 50, 1, "keybindOffsetX", ra, Refresh, nil, { description = "Horizontal pixel offset for the keybind text from its anchor. Positive moves right, negative moves left." }), body, sy)
            P(GUI:CreateFormSlider(body, "Keybind Y Offset", -50, 50, 1, "keybindOffsetY", ra, Refresh, nil, { description = "Vertical pixel offset for the keybind text from its anchor. Positive moves up, negative moves down." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "rotationAssistIcon", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- FOCUS CAST ALERT
    ---------------------------------------------------------------------------
    RegisterSharedOnly("focusCastAlert", { build = function(content, key, width)
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
            sy = P(GUI:CreateFormDropdown(body, "Font", fonts, "font", fca, Refresh, { description = "Font used for the focus cast alert text. Pick Global Font to inherit the UI font." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 72, 1, "fontSize", fca, Refresh, nil, { description = "Font size of the alert text." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Font Outline", {{value="",text="None"},{value="OUTLINE",text="Outline"},{value="THICKOUTLINE",text="Thick Outline"}}, "fontOutline", fca, Refresh, { description = "Outline applied to the alert text for readability against busy backgrounds." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", fca, Refresh, { description = "Color the alert text by your class instead of the Text Color swatch below." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Text Color", "textColor", fca, Refresh, nil, { description = "Color used for the alert text when Use Class Color is off." }), body, sy)
            P(GUI:CreateFormDropdown(body, "Anchor To", {{value="screen",text="Screen"},{value="essential",text="CDM Essential"},{value="focus",text="Focus Frame"}}, "anchorTo", fca, Refresh, { description = "What the alert is anchored to: the screen, the CDM Essential bar, or your focus unit frame." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "focusCastAlert", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- PET WARNING
    ---------------------------------------------------------------------------
    RegisterSharedOnly("petWarning", { build = function(content, key, width)
        local db = U.GetProfileDB()
        local general = db and db.general
        if not general then return 80 end
        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RepositionPetWarning then _G.QUI_RepositionPetWarning() end end

        U.CreateCollapsible(content, "Offsets", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Horizontal Offset", -500, 500, 10, "petWarningOffsetX", general, Refresh, nil, { description = "Horizontal pixel offset for the pet warning from its anchor. Positive moves right, negative moves left." }), body, sy)
            P(GUI:CreateFormSlider(body, "Vertical Offset", -500, 500, 10, "petWarningOffsetY", general, Refresh, nil, { description = "Vertical pixel offset for the pet warning from its anchor. Positive moves up, negative moves down." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "petWarning", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- ACTION TRACKER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("actionTracker", { build = function(content, key, width)
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
            sy = P(GUI:CreateFormCheckbox(body, "Only Show In Combat", "onlyInCombat", at, Refresh, { description = "Hide the action tracker while you are out of combat. Useful if you only want it active during pulls." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Clear History On Combat End", "clearOnCombatEnd", at, Refresh, { description = "Empty the tracker when combat ends instead of leaving the last pull's spells on screen." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Enable Inactivity Fade-Out", "inactivityFadeEnabled", at, Refresh, { description = "Fade the tracker out after a period of no casts. The fade delay is configured below." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Inactivity Timeout (sec)", 10, 60, 1, "inactivityFadeSeconds", at, Refresh, nil, { description = "Seconds of inactivity before the tracker fades out. Only applies when Inactivity Fade-Out is on." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Clear History After Inactivity", "clearOnInactivity", at, Refresh, { description = "Additionally wipe the tracked history once the inactivity timeout fires." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Show Failed/Interrupted Casts", "showFailedCasts", at, Refresh, { description = "Include failed or interrupted casts in the tracker. Useful for reviewing what cancelled your rotation." }), body, sy)
        end, sections, relayout)

        -- Layout
        local orientationOpts = {{value="VERTICAL",text="Vertical"},{value="HORIZONTAL",text="Horizontal"}}
        U.CreateCollapsible(content, "Layout", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Bar Orientation", orientationOpts, "orientation", at, Refresh, { description = "Whether tracked spells stack vertically or extend horizontally." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Invert Scroll Direction", "invertScrollDirection", at, Refresh, { description = "Flip the direction new entries enter from. Put newest spells at the top/left instead of bottom/right (or vice versa)." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Max Entries", 3, 10, 1, "maxEntries", at, Refresh, nil, { description = "How many spell entries the tracker keeps on screen at once." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 16, 64, 1, "iconSize", at, Refresh, nil, { description = "Pixel size of each spell icon in the tracker." }), body, sy)
            P(GUI:CreateFormSlider(body, "Icon Spacing", 0, 24, 1, "iconSpacing", at, Refresh, nil, { description = "Pixel gap between adjacent icons." }), body, sy)
        end, sections, relayout)

        -- Icon Border
        U.CreateCollapsible(content, "Icon Border", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Icon Borders", "iconHideBorder", at, Refresh, { description = "Hide the border drawn around each spell icon." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Icon Borders", "iconBorderUseClassColor", at, Refresh, { description = "Color the icon borders by your class instead of the Icon Border Color swatch below." }), body, sy)
            P(GUI:CreateFormColorPicker(body, "Icon Border Color", "iconBorderColor", at, Refresh, nil, { description = "Color used for the icon borders when Use Class Color is off." }), body, sy)
        end, sections, relayout)

        -- Container Backdrop & Border
        U.CreateCollapsible(content, "Backdrop & Border", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Container Background", "showBackdrop", at, Refresh, { description = "Draw a background behind the tracker to help it stand out." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Container Background Color", "backdropColor", at, Refresh, nil, { description = "Color used for the tracker background." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Container Border", "hideBorder", at, Refresh, { description = "Hide the border drawn around the tracker container." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Size", 0, 5, 0.5, "borderSize", at, Refresh, nil, { description = "Thickness of the tracker container border. Set to 0 to hide the border." }), body, sy)
            P(GUI:CreateFormColorPicker(body, "Container Border Color", "borderColor", at, Refresh, nil, { description = "Color of the tracker container border." }), body, sy)
        end, sections, relayout)

        -- Spell Blocklist
        U.CreateCollapsible(content, "Spell Blocklist", FORM_ROW + 22 + 8, function(body)
            local sy = -4
            local blocklistField = GUI:CreateFormEditBox(body, "Spell Blocklist IDs", "blocklistText", at, Refresh, {
                maxLetters = 300, live = true,
                onEditFocusGained = function(self) self:HighlightText() end,
            }, { description = "Comma-separated list of spell IDs to ignore in the tracker. Useful for muting passive procs or low-value abilities." })
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
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- CONSUMABLES PROVIDER
    ---------------------------------------------------------------------------
    RegisterSharedOnly("consumables", { build = function(content, key, width)
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
            sy = P(GUI:CreateFormCheckbox(body, "Ready Check", "consumableOnReadyCheck", settings, nil, { description = "Show the consumables reminder whenever a ready check is triggered." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Dungeon Entrance", "consumableOnDungeon", settings, nil, { description = "Show the consumables reminder when you zone into a dungeon." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Raid Entrance", "consumableOnRaid", settings, nil, { description = "Show the consumables reminder when you zone into a raid." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Instanced Resurrect", "consumableOnResurrect", settings, nil, { description = "Show the consumables reminder when you resurrect inside an instance, to catch dropped flasks/food." }), body, sy)
        end, sections, relayout)

        local mhLabel = (ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetMHLabel() or "Weapon Oil") .. " (MH)"
        local ohLabel = (ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetOHLabel() or "Weapon Oil") .. " (OH)"
        U.CreateCollapsible(content, "Buff Checks", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Food Buff", "consumableFood", settings, Refresh, { description = "Check for an active food buff." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Flask Buff", "consumableFlask", settings, Refresh, { description = "Check for an active flask/phial buff." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, mhLabel, "consumableOilMH", settings, Refresh, { description = "Check that your main-hand has an active weapon consumable (oil/sharpening stone/etc.)." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, ohLabel, "consumableOilOH", settings, Refresh, { description = "Check that your off-hand has an active weapon consumable (oil/sharpening stone/etc.)." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Augment Rune", "consumableRune", settings, Refresh, { description = "Check for an active augment rune buff." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Healthstones", "consumableHealthstone", settings, Refresh, { description = "Check that you have a healthstone in your bags." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Expiration Warning", 2 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Warn When Buffs Expiring", "consumableExpirationWarning", settings, nil, { description = "Flash the reminder when a tracked buff is within the threshold of expiring." }), body, sy)
            P(GUI:CreateFormSlider(body, "Warning Threshold (seconds)", 60, 600, 30, "consumableExpirationThreshold", settings, nil, nil, { description = "Seconds remaining at which the expiration warning triggers." }), body, sy)
        end, sections, relayout)

        U.CreateCollapsible(content, "Display", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Always Show (Persistent)", "consumablePersistent", settings, function()
                if settings.consumablePersistent then
                    if _G.QUI_ShowConsumables then _G.QUI_ShowConsumables() end
                else
                    if _G.QUI_HideConsumables then _G.QUI_HideConsumables() end
                end
            end, { description = "Keep the reminder on screen all the time instead of showing it only when triggered." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Anchor to Ready Check", "consumableAnchorMode", settings, Refresh, { description = "Snap the reminder to the ready check frame's position instead of using its own anchor." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 24, 64, 2, "consumableIconSize", settings, Refresh, nil, { description = "Pixel size of each consumable icon in the reminder." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Offset", 0, 20, 1, "consumableIconOffset", settings, Refresh, nil, { description = "Pixel gap between adjacent icons in the reminder." }), body, sy)
            P(GUI:CreateFormSlider(body, "Scale", 0.5, 3, 0.05, "consumableScale", settings, Refresh, nil, { description = "Overall scale multiplier applied to the reminder frame." }), body, sy)
        end, sections, relayout)

        -- Macros: per-character auto-generated consumable macros. Lets the
        -- user pick which specific Flask / Potion / Health Potion /
        -- Healthstone / Augment Rune / Vantus Rune / Weapon Consumable the
        -- QUI_* macros should resolve to. Each dropdown is sourced from
        -- ConsumableMacros.XXX_OPTIONS so new items can be added in one place.
        local cmDB = settings and settings.consumableMacros
        if cmDB and GUI.CreateFormDropdown then
            local CM = ns.ConsumableMacros
            local function MacroRefresh()
                if CM then CM:ForceRefresh() end
            end
            local fallback = { { value = "none", text = "None" } }

            U.CreateCollapsible(content, "Macros", 10 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Enable Consumable Macros", "enabled", cmDB, function()
                    if CM then
                        if cmDB.enabled then CM:ForceRefresh() else CM:DeleteMacros() end
                    end
                end, { description = "Auto-generate per-character QUI_* macros for the consumables selected below. Disabling deletes the macros." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Flask Type",
                    (CM and CM.FLASK_OPTIONS) or fallback, "selectedFlask", cmDB, MacroRefresh, { description = "Which flask/phial the QUI flask macro resolves to on this character." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Potion Type",
                    (CM and CM.POTION_OPTIONS) or fallback, "selectedPotion", cmDB, MacroRefresh, { description = "Which combat potion the QUI potion macro resolves to on this character." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Health Potion",
                    (CM and CM.HEALTH_OPTIONS) or fallback, "selectedHealth", cmDB, MacroRefresh, { description = "Which health potion the QUI health macro resolves to on this character." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Healthstone",
                    (CM and CM.HEALTHSTONE_OPTIONS) or fallback, "selectedHealthstone", cmDB, MacroRefresh, { description = "Which healthstone variant the QUI healthstone macro resolves to on this character." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Augment Rune",
                    (CM and CM.AUGMENT_OPTIONS) or fallback, "selectedAugment", cmDB, MacroRefresh, { description = "Which augment rune the QUI augment macro resolves to on this character." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Vantus Rune",
                    (CM and CM.VANTUS_OPTIONS) or fallback, "selectedVantus", cmDB, MacroRefresh, { description = "Which vantus rune the QUI vantus macro resolves to on this character." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Weapon Consumable",
                    (CM and CM.WEAPON_OPTIONS) or fallback, "selectedWeapon", cmDB, MacroRefresh, { description = "Which weapon consumable (oil, sharpening stone, etc.) the QUI weapon macro resolves to on this character." }), body, sy)
                P(GUI:CreateFormCheckbox(body, "Chat Notifications", "chatNotifications", cmDB, nil, { description = "Print a chat message when consumable macros are regenerated." }), body, sy)
            end, sections, relayout)
        end

        U.BuildPositionCollapsible(content, "consumables", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- MISSING RAID BUFFS
    ---------------------------------------------------------------------------
    RegisterSharedOnly("missingRaidBuffs", { build = function(content, key, width)
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
            sy = P(GUI:CreateFormCheckbox(body, "Show Only When In Group", "showOnlyInGroup", settings, Refresh, { description = "Hide the missing raid buffs display when you aren't in a party or raid." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Only In Dungeons/Raids", "showOnlyInInstance", settings, Refresh, { description = "Hide the display while in the open world. Useful if you only care about raid buffs inside instances." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Class Self-Buffs (poisons, enchants, shields)", "showSelfBuffs", settings, Refresh, { description = "Also track self-only class buffs like rogue poisons, shaman weapon imbues, and mage armor." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Provider Mode (only buffs you can cast)", "providerMode", settings, Refresh, { description = "Restrict tracking to buffs your current spec can actually provide, so you only see what you need to cast." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Label Bar", "hideLabelBar", settings, Refresh, { description = "Hide the label text under/beside the icon row for a more compact display." }), body, sy)

            local growOptions = {
                {value = "RIGHT", text = "Right"}, {value = "LEFT", text = "Left"},
                {value = "CENTER_H", text = "Center (H)"}, {value = "UP", text = "Up"},
                {value = "DOWN", text = "Down"}, {value = "CENTER_V", text = "Center (V)"},
            }
            P(GUI:CreateFormDropdown(body, "Grow Direction", growOptions, "growDirection", settings, Refresh, { description = "Direction missing-buff icons extend from the anchor. Center options grow symmetrically in both directions." }), body, sy)
        end, sections, relayout)

        -- Appearance
        U.CreateCollapsible(content, "Appearance", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Icon Size", 16, 64, 1, "iconSize", settings, Refresh, nil, { description = "Pixel size of each missing-buff icon." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Icon Spacing", 0, 20, 1, "iconSpacing", settings, Refresh, nil, { description = "Pixel gap between adjacent icons." }), body, sy)
            P(GUI:CreateFormSlider(body, "Label Font Size", 8, 24, 1, "labelFontSize", settings, Refresh, nil, { description = "Font size of the label text displayed on the label bar." }), body, sy)
        end, sections, relayout)

        -- Icon Border
        if not settings.iconBorder then
            settings.iconBorder = { show = true, width = 1, useClassColor = false, useAccentColor = false, color = {0.376, 0.647, 0.980, 1} }
        end
        local borderSettings = settings.iconBorder
        U.CreateCollapsible(content, "Icon Border", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Icon Border", "show", borderSettings, Refresh, { description = "Draw a border around each missing-buff icon." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", borderSettings, Refresh, { description = "Color the icon borders by your class instead of the Border Color swatch below." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Accent Color", "useAccentColor", borderSettings, Refresh, { description = "Color the icon borders using the UI accent color instead of the Border Color swatch below." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Border Color", "color", borderSettings, Refresh, nil, { description = "Color used for icon borders when Class Color and Accent Color are both off." }), body, sy)
            P(GUI:CreateFormSlider(body, "Border Width", 1, 4, 1, "width", borderSettings, Refresh, nil, { description = "Thickness of the icon border in pixels." }), body, sy)
        end, sections, relayout)

        -- Buff Count
        if not settings.buffCount then
            settings.buffCount = { show = true, position = "BOTTOM", fontSize = 10, color = {1, 1, 1, 1} }
        end
        local countSettings = settings.buffCount
        U.CreateCollapsible(content, "Buff Count", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Buff Count", "show", countSettings, Refresh, { description = "Show a count next to each missing buff indicating how many group members are missing it." }), body, sy)
            local countPosOptions = {
                {value = "TOP", text = "Top"}, {value = "BOTTOM", text = "Bottom"},
                {value = "LEFT", text = "Left"}, {value = "RIGHT", text = "Right"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Count Position", countPosOptions, "position", countSettings, Refresh, { description = "Which side of the icon the count text is placed on." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Count Font Size", 8, 18, 1, "fontSize", countSettings, Refresh, nil, { description = "Font size of the count text." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Count Color", "color", countSettings, Refresh, nil, { description = "Color of the count text." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Count X Offset", -50, 50, 1, "offsetX", countSettings, Refresh, nil, { description = "Horizontal pixel offset for the count text from its anchor. Positive moves right, negative moves left." }), body, sy)
            P(GUI:CreateFormSlider(body, "Count Y Offset", -50, 50, 1, "offsetY", countSettings, Refresh, nil, { description = "Vertical pixel offset for the count text from its anchor. Positive moves up, negative moves down." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "missingRaidBuffs", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
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

    RegisterSharedOnly("tooltipAnchor", { build = function(content, key, width)
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
        CreateSingleColumnCollapsible(content, "Tooltip Skinning", 1, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Skin Tooltips", "skinTooltips", tooltip, function()
                GUI:ShowConfirmation({
                    title = "Reload UI?",
                    message = "Skinning changes require a reload to take effect.",
                    acceptText = "Reload",
                    cancelText = "Later",
                    onAccept = function() QUI:SafeReload() end,
                })
            end, { description = "Apply the QUI theme (colors, border) to all game tooltips. Requires a UI reload to take effect." }), body, sy)

            local skinInfo = GUI:CreateLabel(body, "Apply QUI theme (colors, border) to all game tooltips.", 10, GUI.Colors.textMuted)
            skinInfo:SetPoint("TOPLEFT", 0, sy)
            skinInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            skinInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "bgColor", tooltip, RefreshTooltipSkin, nil, { description = "Background color applied to skinned tooltips." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Background Opacity", 0, 1, 0.05, "bgOpacity", tooltip, RefreshTooltipSkin, {precision = 2}, { description = "Opacity of the tooltip background (0 is invisible, 1 is fully opaque)." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Border", "showBorder", tooltip, RefreshTooltipSkin, { description = "Draw a border around skinned tooltips." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Border Thickness", 1, 10, 1, "borderThickness", tooltip, RefreshTooltipSkin, nil, { description = "Thickness of the tooltip border in pixels." }), body, sy)

            local borderColorPicker = GUI:CreateFormColorPicker(body, "Border Color", "borderColor", tooltip, RefreshTooltipSkin, nil, { description = "Color of the tooltip border. Overridden by Class Color or Accent Color below if either is enabled." })
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
            end, { description = "Color the tooltip border by the inspected unit's class (falls back to your class for non-unit tooltips)." })
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
            end, { description = "Color the tooltip border using the UI accent color." })
            sy = P(accentColorBorderCheck, body, sy)

            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(not tooltip.borderUseClassColor and not tooltip.borderUseAccentColor)
            end

            sy = P(GUI:CreateFormCheckbox(body, "Hide Health Bar", "hideHealthBar", tooltip, RefreshTooltips, { description = "Hide the health bar shown on player, NPC, and enemy tooltips." }), body, sy)

            local healthInfo = GUI:CreateLabel(body, "Hide the health bar shown on player, NPC, and enemy tooltips.", 10, GUI.Colors.textMuted)
            healthInfo:SetPoint("TOPLEFT", 0, sy)
            healthInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            healthInfo:SetJustifyH("LEFT")

            local totalHeight = 12 * FORM_ROW + 8
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        -- Font & Content
        CreateSingleColumnCollapsible(content, "Font & Content", 1, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Tooltip Font Size", 8, 24, 1, "fontSize", tooltip, RefreshTooltipFontSize, nil, { description = "Font size of tooltip text." }), body, sy)

            local fontInfo = GUI:CreateLabel(body, "Adjust tooltip text size (8-24).", 10, GUI.Colors.textMuted)
            fontInfo:SetPoint("TOPLEFT", 0, sy)
            fontInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            fontInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Show Spell/Icon IDs", "showSpellIDs", tooltip, RefreshTooltips, { description = "Display spell ID and icon ID on buff, debuff, and spell tooltips. May not populate in combat." }), body, sy)

            local spellInfo = GUI:CreateLabel(body, "Display spell ID and icon ID on buff, debuff, and spell tooltips. May not work in combat.", 10, GUI.Colors.textMuted)
            spellInfo:SetPoint("TOPLEFT", 0, sy)
            spellInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            spellInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Class Color Player Names", "classColorName", tooltip, RefreshTooltips, { description = "Color player names in tooltips by their class." }), body, sy)

            local classInfo = GUI:CreateLabel(body, "Color player names in tooltips by their class.", 10, GUI.Colors.textMuted)
            classInfo:SetPoint("TOPLEFT", 0, sy)
            classInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            classInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormSlider(body, "Hide Delay", 0, 2, 0.1, "hideDelay", tooltip, RefreshTooltips, {precision = 1}, { description = "Seconds before the tooltip fades after your mouse leaves. 0 means instant hide." }), body, sy)

            local delayInfo = GUI:CreateLabel(body, "Seconds before tooltip fades out after mouse leaves (0 = instant hide).", 10, GUI.Colors.textMuted)
            delayInfo:SetPoint("TOPLEFT", 0, sy)
            delayInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            delayInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Hide Server Name", "hideServerName", tooltip, RefreshTooltips, { description = "Strip the realm name from cross-realm player tooltips for a cleaner display." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hide Player Titles", "hidePlayerTitle", tooltip, RefreshTooltips, { description = "Hide character titles on player tooltips." }), body, sy)

            local totalHeight = 4 * FORM_ROW + 4 * FORM_ROW + 2 * FORM_ROW + 8
            local section = body:GetParent()
            section._contentHeight = totalHeight
        end, sections, relayout)

        -- Player Item Level
        CreateSingleColumnCollapsible(content, "Player Item Level", 1, function(body)
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
            end, { description = "Show average equipped item level on player tooltips. Remote players may populate after a short inspect delay." }), body, sy)

            local ilvlInfo = GUI:CreateLabel(body, "Show average equipped item level on player tooltips. Remote players may populate after a short inspect delay.", 10, GUI.Colors.textMuted)
            ilvlInfo:SetPoint("TOPLEFT", 0, sy)
            ilvlInfo:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            ilvlInfo:SetJustifyH("LEFT")
            sy = sy - FORM_ROW

            sy = P(GUI:CreateFormCheckbox(body, "Color Player Item Level by Bracket", "colorPlayerItemLevel", tooltip, function()
                RefreshPlayerItemLevelBracketInputs()
                RefreshTooltips()
            end, { description = "Color the item level number using the bracket thresholds defined below (grey/white/green/blue/purple/orange)." }), body, sy)

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
        CreateSingleColumnCollapsible(content, "Cursor Anchor", 5 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Anchor Tooltip to Cursor", "anchorToCursor", tooltip, RefreshTooltips, { description = "Make tooltips follow your mouse cursor instead of using their default anchor point." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Cursor Anchor Point", anchorOptions, "cursorAnchor", tooltip, RefreshTooltips, { description = "Which corner of the tooltip is pinned to the cursor position." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Cursor X Offset", -200, 200, 1, "cursorOffsetX", tooltip, RefreshTooltips, nil, { description = "Horizontal pixel offset between the cursor and the tooltip anchor. Positive moves right, negative moves left." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Cursor Y Offset", -200, 200, 1, "cursorOffsetY", tooltip, RefreshTooltips, nil, { description = "Vertical pixel offset between the cursor and the tooltip anchor. Positive moves up, negative moves down." }), body, sy)

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

            CreateSingleColumnCollapsible(content, "Tooltip Visibility", 7 * FORM_ROW + 8, function(body)
                local sy = -4
                local info = GUI:CreateLabel(body, "Control tooltip visibility per element type. Choose a modifier key to only show tooltips while holding that key.", 10, GUI.Colors.textMuted)
                info:SetPoint("TOPLEFT", 0, sy)
                info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                info:SetJustifyH("LEFT")
                sy = sy - 24

                sy = P(GUI:CreateFormDropdown(body, "NPCs & Players", visibilityOptions, "npcs", tooltip.visibility, RefreshTooltips, { description = "When to show tooltips for units (NPCs and players). Modifier options only show the tooltip while the key is held." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Abilities", visibilityOptions, "abilities", tooltip.visibility, RefreshTooltips, { description = "When to show tooltips for spells and abilities. Modifier options only show the tooltip while the key is held." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Inventory", visibilityOptions, "items", tooltip.visibility, RefreshTooltips, { description = "When to show tooltips for items in your bags and equipment. Modifier options only show the tooltip while the key is held." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Frames", visibilityOptions, "frames", tooltip.visibility, RefreshTooltips, { description = "When to show tooltips on UI frames (action bars, unit frames, etc.)." }), body, sy)
                sy = P(GUI:CreateFormDropdown(body, "Cooldown Manager", visibilityOptions, "cdm", tooltip.visibility, RefreshTooltips, { description = "When to show tooltips on QUI Cooldown Manager icons." }), body, sy)
                P(GUI:CreateFormDropdown(body, "Custom Items/Spells", visibilityOptions, "customTrackers", tooltip.visibility, RefreshTooltips, { description = "When to show tooltips on QUI custom item/spell trackers." }), body, sy)
            end, sections, relayout)
        end

        -- Combat
        CreateSingleColumnCollapsible(content, "Combat", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Hide Tooltips in Combat", "hideInCombat", tooltip, RefreshTooltips, { description = "Suppress all tooltips while you're in combat. Use the modifier key below to force-show them when needed." }), body, sy)

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
            P(GUI:CreateFormDropdown(body, "Combat Modifier Key", combatOverrideOptions, "combatKey", tooltip, RefreshTooltips, { description = "Modifier key that force-shows tooltips even while Hide Tooltips in Combat is active." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "tooltipAnchor", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- SKYRIDING
    ---------------------------------------------------------------------------
    RegisterSharedOnly("skyriding", { build = function(content, key, width)
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
        U.CreateCollapsible(content, "Visibility", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Visibility Mode", {
                {value = "ALWAYS", text = "Always Visible"},
                {value = "FLYING_ONLY", text = "Only When Flying"},
                {value = "AUTO", text = "Auto (fade when grounded)"},
            }, "visibility", sr, Refresh, { description = "When the skyriding bar is shown: always on, only while flying, or auto-fade out shortly after you land." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Delay (sec)", 0, 10, 0.5, "fadeDelay", sr, Refresh, nil, { description = "Seconds to wait after landing before the bar fades out in Auto mode." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Speed (sec)", 0.1, 1.0, 0.1, "fadeDuration", sr, Refresh, nil, { description = "How long the fade-in / fade-out animation takes, in seconds." }), body, sy)
            P(GUI:CreateFormCheckbox(body, "Hide When FarmHud Is Active", "hideWhenFarmHudShown", sr, Refresh, { description = "Automatically hide the skyriding bar while FarmHud is on screen, to avoid the two overlapping." }), body, sy)
        end, sections, relayout)

        -- Bar Size
        U.CreateCollapsible(content, "Bar Size", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormSlider(body, "Width", 100, 500, 1, "width", sr, Refresh, nil, { description = "Pixel width of the skyriding bar." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Vigor Height", 4, 30, 1, "vigorHeight", sr, Refresh, nil, { description = "Pixel height of the main vigor bar." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Second Wind Height", 2, 20, 1, "secondWindHeight", sr, Refresh, nil, { description = "Pixel height of the Second Wind bar shown below the main vigor bar." }), body, sy)
            P(GUI:CreateFormDropdown(body, "Bar Texture", U.GetTextureList(), "barTexture", sr, Refresh, { description = "Statusbar texture used for both skyriding bars. Supports any extra media packages you have available." }), body, sy)
        end, sections, relayout)

        -- Fill Colors
        U.CreateCollapsible(content, "Fill Colors", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Vigor", "useClassColorVigor", sr, Refresh, { description = "Color the vigor bar by your class instead of the Vigor Fill Color swatch below." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Vigor Fill Color", "barColor", sr, Refresh, nil, { description = "Fill color of the vigor bar when Use Class Color is off." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Use Class Color for Second Wind", "useClassColorSecondWind", sr, Refresh, { description = "Color the Second Wind bar by your class instead of the Second Wind Color swatch below." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Second Wind Color", "secondWindColor", sr, Refresh, nil, { description = "Fill color of the Second Wind bar when Use Class Color is off." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Change Color with Thrill of the Skies", "useThrillOfTheSkiesColor", sr, Refresh, { description = "Swap the vigor bar color while Thrill of the Skies is active so the buff state is obvious." }), body, sy)
            P(GUI:CreateFormColorPicker(body, "Thrill of the Skies Color", "thrillOfTheSkiesColor", sr, Refresh, nil, { description = "Fill color used for the vigor bar while Thrill of the Skies is active." }), body, sy)
        end, sections, relayout)

        -- Background & Effects
        U.CreateCollapsible(content, "Background & Effects", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormColorPicker(body, "Background Color", "backgroundColor", sr, Refresh, nil, { description = "Background color behind the vigor bar." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Second Wind Background", "secondWindBackgroundColor", sr, Refresh, nil, { description = "Background color behind the Second Wind bar." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Segment Marker Color", "segmentColor", sr, Refresh, nil, { description = "Color of the vertical segment markers between vigor charges." }), body, sy)
            P(GUI:CreateFormColorPicker(body, "Recharge Animation Color", "rechargeColor", sr, Refresh, nil, { description = "Color of the charging-segment highlight as a vigor charge recovers." }), body, sy)
        end, sections, relayout)

        -- Text Display
        U.CreateCollapsible(content, "Text Display", 6 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormCheckbox(body, "Show Vigor Count", "showVigorText", sr, Refresh, { description = "Show numeric vigor count on the bar." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Vigor Format", {
                {value = "FRACTION", text = "Fraction (4/6)"}, {value = "CURRENT", text = "Current Only (4)"},
            }, "vigorTextFormat", sr, Refresh, { description = "How vigor is displayed: as a fraction (current/max) or just the current value." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Speed", "showSpeed", sr, Refresh, { description = "Show your current flight speed next to the vigor bar." }), body, sy)
            sy = P(GUI:CreateFormDropdown(body, "Speed Format", {
                {value = "PERCENT", text = "Percentage (312%)"}, {value = "RAW", text = "Raw Speed (9.5)"},
            }, "speedFormat", sr, Refresh, { description = "Format the speed readout as a percentage of base run speed or as the raw yards-per-second value." }), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Show Whirling Surge Icon", "showAbilityIcon", sr, Refresh, { description = "Show a Whirling Surge cooldown icon on the skyriding bar." }), body, sy)
            P(GUI:CreateFormSlider(body, "Text Font Size", 8, 24, 1, "vigorFontSize", sr, function()
                sr.speedFontSize = sr.vigorFontSize; Refresh()
            end, nil, { description = "Font size of the vigor and speed text overlays on the bar." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "skyriding", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })

    ---------------------------------------------------------------------------
    -- PARTY KEYSTONES
    ---------------------------------------------------------------------------
    RegisterSharedOnly("partyKeystones", { build = function(content, key, width)
        local db = U.GetProfileDB()
        if not db or not db.general then return 80 end
        local general = db.general

        local sections = {}
        local function relayout() U.StandardRelayout(content, sections) end
        local function Refresh() if _G.QUI_RefreshKeyTracker then _G.QUI_RefreshKeyTracker() end end

        -- Appearance
        U.CreateCollapsible(content, "Appearance", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            sy = P(GUI:CreateFormDropdown(body, "Font", U.GetFontList(), "keyTrackerFont", general, Refresh, { description = "Font used for the party keystone tracker text." }), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 7, 12, 1, "keyTrackerFontSize", general, Refresh, nil, { description = "Font size of the party keystone tracker entries." }), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "Text Color", "keyTrackerTextColor", general, Refresh, nil, { description = "Color of the tracker text." }), body, sy)
            P(GUI:CreateFormSlider(body, "Frame Width", 120, 250, 1, "keyTrackerWidth", general, Refresh, nil, { description = "Pixel width of the party keystone tracker frame." }), body, sy)
        end, sections, relayout)

        U.BuildPositionCollapsible(content, "partyKeystones", nil, sections, relayout)
        U.BuildOpenFullSettingsLink(content, key, sections, relayout)
        relayout() return content:GetHeight()
    end })
end)
