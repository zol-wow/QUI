local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

-- ACTION BARS PER-BAR SETTINGS BUILDERS
---------------------------------------------------------------------------
do
    local ActionBarsPerBarBuilders = ns.QUI_ActionBarsPerBarBuilders or {}
    ns.QUI_ActionBarsPerBarBuilders = ActionBarsPerBarBuilders

    local function InitializePerBarBuilders()
        if type(ActionBarsPerBarBuilders.BuildBarSettings) == "function" then
            return ActionBarsPerBarBuilders.BuildBarSettings
        end

        local GUI = QUI and QUI.GUI
        if not GUI then return nil end

        local C = GUI.Colors or {}
        local U = ns.QUI_LayoutMode_Utils
        local P = U.PlaceRow
        local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980
        local PADDING = 0
        local FORM_ROW = U and U.FORM_ROW or 32

        local function RefreshActionBars()
            InvalidateEffectiveSettingsCache()

            for _, bk in ipairs(ALL_MANAGED_BAR_KEYS) do
                local buttons = ActionBarsOwned.nativeButtons[bk]
                local settings = GetEffectiveSettings(bk)
                if buttons and settings then
                    if SKINNABLE_BAR_KEYS[bk] then
                        for _, btn in ipairs(buttons) do
                            local st = GetFrameState(btn)
                            st.skinKey = nil
                            SkinButton(btn, settings)
                            UpdateButtonText(btn, settings)
                            UpdateEmptySlotVisibility(btn, settings)
                        end
                    end
                    pcall(LayoutNativeButtons, bk)
                end
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

        local orientationOptions = {
            {value = "horizontal", text = "Horizontal"},
            {value = "vertical", text = "Vertical"},
        }

        local LAYOUT_BARS = {
            bar1 = true, bar2 = true, bar3 = true, bar4 = true,
            bar5 = true, bar6 = true, bar7 = true, bar8 = true,
            pet = true, stance = true, microbar = true, bags = true,
        }

        local FLYOUT_BARS = {
            bar1 = true, bar2 = true, bar3 = true, bar4 = true,
            bar5 = true, bar6 = true, bar7 = true, bar8 = true,
        }

        local flyoutDirectionOptions = {
            {value = "AUTO",  text = "Auto"},
            {value = "UP",    text = "Up"},
            {value = "DOWN",  text = "Down"},
            {value = "LEFT",  text = "Left"},
            {value = "RIGHT", text = "Right"},
        }

        local totemBarGrowOptions = {
            {value = "RIGHT", text = "Right"},
            {value = "LEFT",  text = "Left"},
            {value = "UP",    text = "Up"},
            {value = "DOWN",  text = "Down"},
        }

        local GetTotemBarDB = Helpers.CreateDBGetter("totemBar")

        local SETTINGS_DB_KEY_MAP = {
            petBar = "pet", stanceBar = "stance",
            microMenu = "microbar", bagBar = "bags",
        }
        local TOGGLEABLE_MAIN_BARS = {
            bar2 = true, bar3 = true, bar4 = true, bar5 = true,
            bar6 = true, bar7 = true, bar8 = true,
            microbar = true, bags = true,
        }
        local SPECIAL_BUTTON_BARS = { extraActionButton = true, zoneAbility = true }

        local copyKeys = {
            "iconZoom", "showBackdrop", "backdropAlpha", "showGloss", "glossAlpha", "showBorders",
            "showKeybinds", "hideEmptyKeybinds", "keybindFontSize", "keybindColor",
            "keybindAnchor", "keybindOffsetX", "keybindOffsetY",
            "showMacroNames", "macroNameFontSize", "macroNameColor",
            "macroNameAnchor", "macroNameOffsetX", "macroNameOffsetY",
            "showCounts", "countFontSize", "countColor",
            "countAnchor", "countOffsetX", "countOffsetY",
            "showCooldownText", "cooldownTextFontSize", "cooldownTextColor",
            "cooldownTextAnchor", "cooldownTextOffsetX", "cooldownTextOffsetY",
            "showFlash",
        }

        local copyBarOptions = {
            {value = "bar1", text = "Bar 1"}, {value = "bar2", text = "Bar 2"},
            {value = "bar3", text = "Bar 3"}, {value = "bar4", text = "Bar 4"},
            {value = "bar5", text = "Bar 5"}, {value = "bar6", text = "Bar 6"},
            {value = "bar7", text = "Bar 7"}, {value = "bar8", text = "Bar 8"},
        }

        local function CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
            return U.CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
        end

        local function BuildTotemBarSettings(content)
            local totemDB = GetTotemBarDB()
            if not totemDB then return 80 end

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end

            local function RefreshTotemBar()
                if type(_G.QUI_RefreshTotemBar) == "function" then
                    _G.QUI_RefreshTotemBar()
                end
            end

            CreateCollapsible(content, "Layout", FORM_ROW + 8, function(body)
                local sy = -4
                P(GUI:CreateFormDropdown(body, "Grow Direction",
                    totemBarGrowOptions, "growDirection", totemDB, RefreshTotemBar,
                    { description = "Direction the totem bar grows as additional totems are summoned." }), body, sy)
            end, sections, relayout)

            U.BuildPositionCollapsible(content, "totemBar", nil, sections, relayout)

            relayout()
            return content:GetHeight()
        end

        local function BuildSpecialButtonSettings(content, barKey, barDB)
            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end
            local DEFER = { deferOnDrag = true }

            local function ShowSpecialButtonReloadPrompt()
                local QUI = _G.QUI
                local gui = QUI and QUI.GUI
                if gui and gui.ShowConfirmation then
                    gui:ShowConfirmation({
                        title = "Reload UI?",
                        message = "Enabling or disabling this special button requires a UI reload to fully take effect.",
                        acceptText = "Reload",
                        cancelText = "Later",
                        onAccept = function()
                            if QUI and QUI.SafeReload then
                                QUI:SafeReload()
                            end
                        end,
                    })
                end
            end

            local function RefreshSpecialButton()
                if type(_G.QUI_RefreshExtraButtons) == "function" then
                    _G.QUI_RefreshExtraButtons()
                end
                if type(_G.QUI_RefreshActionBarFade) == "function" then
                    _G.QUI_RefreshActionBarFade()
                end
                if type(_G.QUI_UpdateFramesAnchoredTo) == "function" then
                    _G.QUI_UpdateFramesAnchoredTo(barKey)
                end
            end

            local function RefreshSpecialButtonEnabled()
                RefreshSpecialButton()
                ShowSpecialButtonReloadPrompt()
            end

            CreateCollapsible(content, "Button", 3 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormToggle(body, "Enabled", "enabled", barDB, RefreshSpecialButtonEnabled,
                    { description = "Let QUI manage this button's holder, position, scale, artwork, and mouseover behavior." }), body, sy)
                sy = P(GUI:CreateFormToggle(body, "Hide Artwork", "hideArtwork", barDB, RefreshSpecialButton,
                    { description = "Hide the decorative Blizzard artwork around this button while keeping the button itself visible." }), body, sy)
                P(GUI:CreateFormSlider(body, "Scale",
                    0.5, 2.0, 0.05, "scale", barDB, RefreshSpecialButton, DEFER,
                    { description = "Scale multiplier applied to this special button frame." }), body, sy)
            end, sections, relayout)

            U.BuildPositionCollapsible(content, barKey, nil, sections, relayout)
            U.BuildOpenFullSettingsLink(content, barKey, sections, relayout)

            relayout()
            return content:GetHeight()
        end

        local function BuildBarSettings(content, barKey, width)
            if barKey == "totemBar" then
                return BuildTotemBarSettings(content)
            end

            local db = GetDB()
            if not db or not db.bars then return 80 end

            local dbKey = SETTINGS_DB_KEY_MAP[barKey] or barKey
            local barDB = db.bars[dbKey]
            if not barDB then return 80 end

            if SPECIAL_BUTTON_BARS[dbKey] then
                return BuildSpecialButtonSettings(content, dbKey, barDB)
            end

            local global = db.global
            local hasLayout = LAYOUT_BARS[dbKey]
            local layout = barDB.ownedLayout

            local sections = {}
            local function relayout() U.StandardRelayout(content, sections) end
            local DEFER = { deferOnDrag = true }

            -- Lightweight preview: recompute container size from layout params
            local function PreviewBarSize()
                local container = ActionBarsOwned.containers and ActionBarsOwned.containers[dbKey]
                if not container or not layout then return end
                local btnSize = layout.buttonSize or 36
                local spacing = layout.buttonSpacing or 2
                local cols = layout.columns or 12
                local visible = layout.iconCount or (BUTTON_COUNTS[dbKey] or 12)
                local rows = math.ceil(visible / math.max(cols, 1))
                local isVertical = layout.orientation == "vertical"
                local w, h
                if isVertical then
                    w = rows * btnSize + math.max(rows - 1, 0) * spacing
                    h = math.min(visible, cols) * btnSize + math.max(math.min(visible, cols) - 1, 0) * spacing
                else
                    w = math.min(visible, cols) * btnSize + math.max(math.min(visible, cols) - 1, 0) * spacing
                    h = rows * btnSize + math.max(rows - 1, 0) * spacing
                end
                container:SetSize(math.max(w, 1), math.max(h, 1))
            end
            local DEFER_SIZE = { deferOnDrag = true, onDragPreview = PreviewBarSize }

            local function ApplyBarEnabledState(val)
                -- Mirror Layout Mode's element toggle: apply the container
                -- state now so re-enabling takes effect without a reload.
                -- Containers are secure (SetAttribute is protected in
                -- combat); the deferred QUI_RefreshActionBars covers the
                -- disable side on regen, enable completes at reload.
                if not InCombatLockdown() then
                    local container = ActionBarsOwned.containers and ActionBarsOwned.containers[dbKey]
                    if container then
                        container:SetAttribute("qui-user-shown", val and true or false)
                        if val then
                            container:Show()
                        else
                            if ActionBarsOwned.HideOwnedFlyout then
                                ActionBarsOwned.HideOwnedFlyout()
                            end
                            container:Hide()
                        end
                    end
                end
                if type(_G.QUI_RefreshActionBars) == "function" then
                    _G.QUI_RefreshActionBars()
                end
                if type(_G.QUI_RefreshActionBarsVisibility) == "function" then
                    _G.QUI_RefreshActionBarsVisibility()
                end
                if type(_G.QUI_UpdateFramesAnchoredTo) == "function" then
                    local anchorKey = (dbKey == "microbar" and "microMenu")
                        or (dbKey == "bags" and "bagBar")
                        or dbKey
                    _G.QUI_UpdateFramesAnchoredTo(anchorKey)
                end
                if ns.QUI_ActionBarsOptions and ns.QUI_ActionBarsOptions.RefreshPreview then
                    ns.QUI_ActionBarsOptions.RefreshPreview()
                end

                local QUI = _G.QUI
                local GUI = QUI and QUI.GUI
                if GUI and GUI.ShowConfirmation then
                    GUI:ShowConfirmation({
                        title = "Reload UI?",
                        message = "Enabling or disabling an action bar requires a UI reload to fully take effect.",
                        acceptText = "Reload",
                        cancelText = "Later",
                        onAccept = function() QUI:SafeReload() end,
                    })
                end
            end

            if TOGGLEABLE_MAIN_BARS[dbKey] then
                local enabledDesc = (dbKey == "microbar" and "Show or hide the micro menu. Stays in sync with this element's enable toggle in Layout Mode.")
                    or (dbKey == "bags" and "Show or hide the bag bar. Stays in sync with this element's enable toggle in Layout Mode.")
                    or "Show or hide this action bar. Bars 2-8 can be individually disabled without affecting the pet or stance bars."
                CreateCollapsible(content, "Bar", FORM_ROW + 8, function(body)
                    local sy = -4
                    P(GUI:CreateFormCheckbox(body, "Enabled",
                        "enabled", barDB, ApplyBarEnabledState,
                        { description = enabledDesc }), body, sy)
                end, sections, relayout)
            end

            -- SECTION: Layout
            if hasLayout and layout then
                local isMicroBag = (dbKey == "microbar" or dbKey == "bags")
                local maxButtons = BUTTON_COUNTS[dbKey] or (dbKey == "microbar" and 12 or (dbKey == "bags" and 6 or 12))
                local extraRows = 1
                if barKey == "bar1" then extraRows = extraRows + 1 end
                if FLYOUT_BARS[barKey] then extraRows = extraRows + 1 end
                local numRows = 7 + extraRows
                CreateCollapsible(content, "Layout", numRows * FORM_ROW + 8, function(body)
                    local sy = -4

                    if barKey == "bar1" then
                        sy = P(GUI:CreateFormCheckbox(body,
                            "Hide Default Paging Arrow", "hidePageArrow", barDB,
                            function(val)
                                if _G.QUI_ApplyPageArrowVisibility then
                                    _G.QUI_ApplyPageArrowVisibility(val)
                                end
                            end, { description = "Hide Blizzard's small paging arrow attached to the main action bar. Only affects Bar 1." }), body, sy)
                    end

                    if not isMicroBag then
                    local filteredCopyOptions = {}
                    for _, opt in ipairs(copyBarOptions) do
                        if opt.value ~= barKey then
                            table.insert(filteredCopyOptions, opt)
                        end
                    end

                    sy = P(GUI:CreateFormDropdown(body, "Copy Settings From", filteredCopyOptions, nil, nil,
                        function(sourceKey)
                            local sourceDbKey = SETTINGS_DB_KEY_MAP[sourceKey] or sourceKey
                            local sourceDB = db.bars[sourceDbKey]
                            if not sourceDB then return end
                            for _, key in ipairs(copyKeys) do
                                barDB[key] = sourceDB[key]
                            end
                            if sourceDB.ownedLayout then
                                barDB.ownedLayout = barDB.ownedLayout or {}
                                for sk in pairs(barDB.ownedLayout) do barDB.ownedLayout[sk] = nil end
                                for sk, sv in pairs(sourceDB.ownedLayout) do barDB.ownedLayout[sk] = sv end
                            end
                            RefreshActionBars()
                        end, { description = "Clone another bar's layout, visual, keybind, macro name, and stack count settings onto this bar. Position/anchor is not copied." }), body, sy)
                    end -- isMicroBag guard

                    if isMicroBag then
                        sy = P(GUI:CreateFormCheckbox(body, "Clickthrough",
                            "clickthrough", barDB, function(val)
                                local btns = ActionBarsOwned.nativeButtons[dbKey]
                                if btns then
                                    for _, btn in ipairs(btns) do
                                        btn:EnableMouse(not val)
                                    end
                                end
                            end, { description = "Make this bar ignore mouse clicks so they pass through to whatever is underneath. Useful when placing the bar over the world view." }), body, sy)
                    end

                    sy = P(GUI:CreateFormDropdown(body, "Orientation",
                        orientationOptions, "orientation", layout, RefreshActionBars,
                        { description = "Lay out buttons horizontally (left-to-right rows) or vertically (top-to-bottom columns)." }), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Buttons Per Row",
                        1, maxButtons, 1, "columns", layout, RefreshActionBars, DEFER_SIZE,
                        { description = "How many buttons fit in a single row before wrapping. Pair with Visible Buttons to shape multi-row layouts." }), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Visible Buttons",
                        1, maxButtons, 1, "iconCount", layout, RefreshActionBars, DEFER_SIZE,
                        { description = "How many buttons on this bar are visible. Hidden buttons are still keybindable but not drawn." }), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Button Size",
                        20, 64, 1, "buttonSize", layout, RefreshActionBars, DEFER_SIZE,
                        { description = "Square size of each button in pixels." }), body, sy)

                    sy = P(GUI:CreateFormSlider(body, "Button Spacing",
                        -10, 10, 1, "buttonSpacing", layout, RefreshActionBars, DEFER_SIZE,
                        { description = "Pixel gap between adjacent buttons. Negative values overlap buttons for compact layouts." }), body, sy)

                    sy = P(GUI:CreateFormCheckbox(body, "Grow Upward",
                        "growUp", layout, RefreshActionBars,
                        { description = "Add new rows above the anchor row instead of below, so the bar grows up from its anchor." }), body, sy)

                    if FLYOUT_BARS[barKey] then
                        sy = P(GUI:CreateFormCheckbox(body, "Grow Left",
                            "growLeft", layout, RefreshActionBars,
                            { description = "Add new buttons to the left of the anchor instead of the right, so the bar grows leftward." }), body, sy)

                        P(GUI:CreateFormDropdown(body, "Flyout Direction",
                            flyoutDirectionOptions, "flyoutDirection", layout,
                            function()
                                ApplyFlyoutDirection(barKey)
                            end, { description = "Direction a secure-owned spell flyout opens from buttons on this bar." }), body, sy)
                    else
                        P(GUI:CreateFormCheckbox(body, "Grow Left",
                            "growLeft", layout, RefreshActionBars,
                            { description = "Add new buttons to the left of the anchor instead of the right, so the bar grows leftward." }), body, sy)
                    end
                end, sections, relayout)
            end

            -- SECTION: Visual (action bars only — micro/bag buttons are not skinned)
            if SKINNABLE_BAR_KEYS[dbKey] then
            CreateCollapsible(content, "Visual", 7 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormSlider(body, "Icon Crop",
                    0.05, 0.15, 0.01, "iconZoom", barDB, RefreshActionBars, DEFER,
                    { description = "Crop the edges of each icon to hide the default Blizzard border. Higher values crop more." }), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Show Backdrop",
                    "showBackdrop", barDB, RefreshActionBars,
                    { description = "Draw a dark backdrop behind this bar to separate it visually from the world." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Backdrop Opacity",
                    0, 1, 0.05, "backdropAlpha", barDB, RefreshActionBars, DEFER,
                    { description = "Opacity of the backdrop fill. 0 is fully transparent, 1 is fully opaque." }), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Show Gloss",
                    "showGloss", barDB, RefreshActionBars,
                    { description = "Overlay a subtle glossy highlight on each button for a glass-like finish." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Gloss Opacity",
                    0, 1, 0.05, "glossAlpha", barDB, RefreshActionBars, DEFER,
                    { description = "Opacity of the gloss overlay when Show Gloss is on." }), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Show Borders",
                    "showBorders", barDB, RefreshActionBars,
                    { description = "Draw a thin border around each button on this bar." }), body, sy)

                local pressedOptions = {
                    {value = "off", text = "Off"},
                    {value = "blizzard", text = "Blizzard Default"},
                    {value = "qui", text = "QUI"},
                }
                P(GUI:CreateFormDropdown(body, "Pressed Effect",
                    pressedOptions, "showFlash", barDB, RefreshActionBars,
                    { description = "Visual response when a button is pressed. Blizzard Default replays the stock animation; QUI swaps in a subtle overlay; Off disables both." }), body, sy)
            end, sections, relayout)

            -- SECTION: Keybind Text
            CreateCollapsible(content, "Keybind Text", 7 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Keybinds",
                    "showKeybinds", barDB, RefreshActionBars,
                    { description = "Display the bound key on each button in the corner set below." }), body, sy)

                sy = P(GUI:CreateFormCheckbox(body, "Hide Empty Keybinds",
                    "hideEmptyKeybinds", barDB, RefreshActionBars,
                    { description = "Only show keybind text on buttons that actually have an ability assigned." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Font Size",
                    8, 18, 1, "keybindFontSize", barDB, RefreshActionBars, DEFER,
                    { description = "Font size used for the keybind text on this bar's buttons." }), body, sy)

                sy = P(GUI:CreateFormDropdown(body, "Anchor",
                    anchorOptions, "keybindAnchor", barDB, RefreshActionBars,
                    { description = "Which corner of each button the keybind text is anchored to." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "X-Offset",
                    -20, 20, 1, "keybindOffsetX", barDB, RefreshActionBars, DEFER,
                    { description = "Horizontal pixel offset for the keybind text from its anchor corner." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Y-Offset",
                    -20, 20, 1, "keybindOffsetY", barDB, RefreshActionBars, DEFER,
                    { description = "Vertical pixel offset for the keybind text from its anchor corner." }), body, sy)

                P(GUI:CreateFormColorPicker(body, "Color",
                    "keybindColor", barDB, RefreshActionBars, nil,
                    { description = "Color used for the keybind text on this bar." }), body, sy)
            end, sections, relayout)

            -- SECTION: Macro Names
            CreateCollapsible(content, "Macro Names", 6 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Macro Names",
                    "showMacroNames", barDB, RefreshActionBars,
                    { description = "Show the macro name (or ability name, if no macro) across the bottom of each button." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Font Size",
                    8, 18, 1, "macroNameFontSize", barDB, RefreshActionBars, DEFER,
                    { description = "Font size used for the macro name text." }), body, sy)

                sy = P(GUI:CreateFormDropdown(body, "Anchor",
                    anchorOptions, "macroNameAnchor", barDB, RefreshActionBars,
                    { description = "Which corner of each button the macro name is anchored to." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "X-Offset",
                    -20, 20, 1, "macroNameOffsetX", barDB, RefreshActionBars, DEFER,
                    { description = "Horizontal pixel offset for the macro name from its anchor corner." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Y-Offset",
                    -20, 20, 1, "macroNameOffsetY", barDB, RefreshActionBars, DEFER,
                    { description = "Vertical pixel offset for the macro name from its anchor corner." }), body, sy)

                P(GUI:CreateFormColorPicker(body, "Color",
                    "macroNameColor", barDB, RefreshActionBars, nil,
                    { description = "Color used for the macro name text on this bar." }), body, sy)
            end, sections, relayout)

            -- SECTION: Stack Count
            CreateCollapsible(content, "Stack Count", 6 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Counts",
                    "showCounts", barDB, RefreshActionBars,
                    { description = "Show the stack count / charge count on each button (e.g. reagent stacks, charge counts)." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Font Size",
                    8, 20, 1, "countFontSize", barDB, RefreshActionBars, DEFER,
                    { description = "Font size used for the stack count text." }), body, sy)

                sy = P(GUI:CreateFormDropdown(body, "Anchor",
                    anchorOptions, "countAnchor", barDB, RefreshActionBars,
                    { description = "Which corner of each button the stack count is anchored to." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "X-Offset",
                    -20, 20, 1, "countOffsetX", barDB, RefreshActionBars, DEFER,
                    { description = "Horizontal pixel offset for the stack count from its anchor corner." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Y-Offset",
                    -20, 20, 1, "countOffsetY", barDB, RefreshActionBars, DEFER,
                    { description = "Vertical pixel offset for the stack count from its anchor corner." }), body, sy)

                P(GUI:CreateFormColorPicker(body, "Color",
                    "countColor", barDB, RefreshActionBars, nil,
                    { description = "Color used for the stack count text on this bar." }), body, sy)
            end, sections, relayout)

            -- SECTION: Cooldown Duration Text
            CreateCollapsible(content, "Cooldown Duration Text", 6 * FORM_ROW + 8, function(body)
                local sy = -4
                sy = P(GUI:CreateFormCheckbox(body, "Show Duration Text",
                    "showCooldownText", barDB, RefreshActionBars,
                    { description = "Show Blizzard's native cooldown countdown numbers on each button." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Font Size",
                    8, 24, 1, "cooldownTextFontSize", barDB, RefreshActionBars, DEFER,
                    { description = "Font size used for cooldown duration text." }), body, sy)

                sy = P(GUI:CreateFormDropdown(body, "Anchor",
                    anchorOptions, "cooldownTextAnchor", barDB, RefreshActionBars,
                    { description = "Which point of each button the cooldown duration text is anchored to." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "X-Offset",
                    -20, 20, 1, "cooldownTextOffsetX", barDB, RefreshActionBars, DEFER,
                    { description = "Horizontal pixel offset for cooldown duration text from its anchor point." }), body, sy)

                sy = P(GUI:CreateFormSlider(body, "Y-Offset",
                    -20, 20, 1, "cooldownTextOffsetY", barDB, RefreshActionBars, DEFER,
                    { description = "Vertical pixel offset for cooldown duration text from its anchor point." }), body, sy)

                P(GUI:CreateFormColorPicker(body, "Color",
                    "cooldownTextColor", barDB, RefreshActionBars, nil,
                    { description = "Color used for cooldown duration text on this bar." }), body, sy)
            end, sections, relayout)
            end -- SKINNABLE_BAR_KEYS guard

            -- Position / Anchoring
            U.BuildPositionCollapsible(content, barKey, nil, sections, relayout)
            U.BuildOpenFullSettingsLink(content, barKey, sections, relayout)

            -- Initial layout
            relayout()
            return content:GetHeight()
        end

        ActionBarsPerBarBuilders.BuildBarSettings = function(content, barKey, width)
            return BuildBarSettings(content, barKey, width)
        end

        return ActionBarsPerBarBuilders.BuildBarSettings
    end

    ActionBarsPerBarBuilders.EnsureInitialized = InitializePerBarBuilders
end

---------------------------------------------------------------------------
-- EXPOSE MODULE
---------------------------------------------------------------------------

core = GetCore()
if core then
    core.ActionBars = ActionBarsOwned
end

if ns.Registry then
    ns.Registry:Register("actionbars", {
        refresh = _G.QUI_RefreshActionBars,
        priority = 20,
        group = "frames",
        importCategories = { "actionBars" },
    })
end
