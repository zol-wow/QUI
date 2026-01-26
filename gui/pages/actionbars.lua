local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options

-- Local references
local PADDING = Shared.PADDING
local CreateScrollableContent = Shared.CreateScrollableContent
local GetDB = Shared.GetDB
local GetTextureList = Shared.GetTextureList
local GetFontList = Shared.GetFontList
local RefreshAll = Shared.RefreshAll

-- Forward declaration for Totem Bar sub-tab (defined below Action Bars page)
local BuildTotemBarTab

---------------------------------------------------------------------------
-- PAGE: Action Bars
---------------------------------------------------------------------------
local function CreateActionBarsPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local db = GetDB()

    -- Safety check
    if not db or not db.actionBars then
        local errorLabel = GUI:CreateLabel(content, "Action Bars settings not available. Please reload UI.", 12, C.text)
        errorLabel:SetPoint("TOPLEFT", PADDING, -15)
        content:SetHeight(100)
        return scroll, content
    end

    local actionBars = db.actionBars
    local global = actionBars.global
    local fade = actionBars.fade
    local bars = actionBars.bars

    -- Refresh callback
    local function RefreshActionBars()
        if _G.QUI_RefreshActionBars then
            _G.QUI_RefreshActionBars()
        end
    end

    ---------------------------------------------------------
    -- SUB-TAB: Mouseover Hide
    ---------------------------------------------------------
    local function BuildMouseoverHideTab(tabContent)
        local y = -15
        local PAD = PADDING
        local FORM_ROW = 32

        -- Set search context for widget auto-registration
        GUI:SetSearchContext({tabIndex = 4, tabName = "Action Bars", subTabIndex = 2, subTabName = "Mouseover Hide"})

        ---------------------------------------------------------
        -- Warning: Enable Blizzard Action Bars
        ---------------------------------------------------------
        local warningText = GUI:CreateLabel(tabContent,
            "Important: Enable all 8 action bars in Game Menu > Options > Gameplay > Action Bars for mouseover hide to work correctly. To remove the default dragon texture, open Edit Mode, select Action Bar 1, check 'Hide Bar Art', then reload.",
            11, C.warning)
        warningText:SetPoint("TOPLEFT", PAD, y)
        warningText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        warningText:SetJustifyH("LEFT")
        warningText:SetWordWrap(true)
        warningText:SetHeight(45)
        y = y - 55

        local openSettingsBtn = GUI:CreateButton(tabContent, "Open Game Settings", 160, 26, function()
            if SettingsPanel then
                SettingsPanel:Open()
            end
        end)
        openSettingsBtn:SetPoint("TOPLEFT", PAD, y)
        openSettingsBtn:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - 46  -- Extra spacing before main content

        ---------------------------------------------------------
        -- Section: Mouseover Hide
        ---------------------------------------------------------
        local fadeHeader = GUI:CreateSectionHeader(tabContent, "Mouseover Hide")
        fadeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - fadeHeader.gap

        local fadeCheck = GUI:CreateFormCheckbox(tabContent, "Enable Mouseover Hide",
            "enabled", fade, RefreshActionBars)
        fadeCheck:SetPoint("TOPLEFT", PAD, y)
        fadeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fadeTip = GUI:CreateLabel(tabContent,
            "Bars hide when mouse is not over them. Hover to reveal.",
            11, C.textMuted)
        fadeTip:SetPoint("TOPLEFT", PAD, y)
        fadeTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        fadeTip:SetJustifyH("LEFT")
        y = y - 24

        local fadeInSlider = GUI:CreateFormSlider(tabContent, "Fade In Speed (sec)",
            0.1, 1.0, 0.05, "fadeInDuration", fade, RefreshActionBars)
        fadeInSlider:SetPoint("TOPLEFT", PAD, y)
        fadeInSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fadeOutSlider = GUI:CreateFormSlider(tabContent, "Fade Out Speed (sec)",
            0.1, 1.0, 0.05, "fadeOutDuration", fade, RefreshActionBars)
        fadeOutSlider:SetPoint("TOPLEFT", PAD, y)
        fadeOutSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fadeAlphaSlider = GUI:CreateFormSlider(tabContent, "Faded Opacity",
            0, 1, 0.05, "fadeOutAlpha", fade, RefreshActionBars)
        fadeAlphaSlider:SetPoint("TOPLEFT", PAD, y)
        fadeAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fadeDelaySlider = GUI:CreateFormSlider(tabContent, "Fade Out Delay (sec)",
            0, 2.0, 0.1, "fadeOutDelay", fade, RefreshActionBars)
        fadeDelaySlider:SetPoint("TOPLEFT", PAD, y)
        fadeDelaySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local combatCheck = GUI:CreateFormCheckbox(tabContent, "Do Not Hide In Combat",
            "alwaysShowInCombat", fade, RefreshActionBars)
        combatCheck:SetPoint("TOPLEFT", PAD, y)
        combatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local linkBarsCheck = GUI:CreateFormCheckbox(tabContent, "Link Action Bars 1-8 on Mouseover",
            "linkBars1to8", fade, RefreshActionBars)
        linkBarsCheck:SetPoint("TOPLEFT", PAD, y)
        linkBarsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local linkBarsDesc = GUI:CreateLabel(tabContent,
            "When enabled, hovering any action bar (1-8) reveals all bars 1-8 together.",
            11, C.textMuted)
        linkBarsDesc:SetPoint("TOPLEFT", PAD, y)
        linkBarsDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        linkBarsDesc:SetJustifyH("LEFT")
        y = y - 24

        -- Always Show toggles (bars that ignore mouseover hide)
        local alwaysShowTip = GUI:CreateLabel(tabContent,
            "Bars checked below will always remain visible, ignoring mouseover hide.",
            11, C.textMuted)
        alwaysShowTip:SetPoint("TOPLEFT", PAD, y)
        alwaysShowTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        alwaysShowTip:SetJustifyH("LEFT")
        y = y - 24

        local alwaysShowBars = {
            { key = "bar1", label = "Always Show Bar 1" },
            { key = "bar2", label = "Always Show Bar 2" },
            { key = "bar3", label = "Always Show Bar 3" },
            { key = "bar4", label = "Always Show Bar 4" },
            { key = "bar5", label = "Always Show Bar 5" },
            { key = "bar6", label = "Always Show Bar 6" },
            { key = "bar7", label = "Always Show Bar 7" },
            { key = "bar8", label = "Always Show Bar 8" },
            { key = "microbar", label = "Always Show Microbar" },
            { key = "bags", label = "Always Show Bags" },
            { key = "pet", label = "Always Show Pet Bar" },
            { key = "stance", label = "Always Show Stance Bar" },
            { key = "extraActionButton", label = "Always Show Extra Action" },
            { key = "zoneAbility", label = "Always Show Zone Ability" },
        }

        for _, barInfo in ipairs(alwaysShowBars) do
            local barDB = bars[barInfo.key]
            if barDB then
                local check = GUI:CreateFormCheckbox(tabContent, barInfo.label,
                    "alwaysShow", barDB, RefreshActionBars)
                check:SetPoint("TOPLEFT", PAD, y)
                check:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW
            end
        end

        tabContent:SetHeight(math.abs(y) + 50)
    end  -- End BuildMouseoverHideTab

    ---------------------------------------------------------
    -- SUB-TAB: Master Visual Settings (existing global settings)
    ---------------------------------------------------------
    local function BuildMasterSettingsTab(tabContent)
        local y = -15
        local PAD = PADDING
        local FORM_ROW = 32

        -- Set search context for auto-registration
        GUI:SetSearchContext({tabIndex = 4, tabName = "Action Bars", subTabIndex = 1, subTabName = "Master Settings"})

        -- 9-point anchor options for text positioning
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

        ---------------------------------------------------------
        -- Quick Keybind Mode (prominent tool at top)
        ---------------------------------------------------------
        local keybindModeBtn = GUI:CreateButton(tabContent, "Quick Keybind Mode", 180, 28, function()
            local LibKeyBound = LibStub("LibKeyBound-1.0", true)
            if LibKeyBound then
                LibKeyBound:Toggle()
            elseif QuickKeybindFrame then
                ShowUIPanel(QuickKeybindFrame)
            end
        end)
        keybindModeBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 38

        local keybindTip = GUI:CreateLabel(tabContent,
            "Hover over action buttons and press a key to bind. Type /kb anytime.",
            11, C.textMuted)
        keybindTip:SetPoint("TOPLEFT", PAD, y)
        keybindTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        keybindTip:SetJustifyH("LEFT")
        keybindTip:SetWordWrap(true)
        keybindTip:SetHeight(15)
        y = y - 30

        ---------------------------------------------------------
        -- Section: General
        ---------------------------------------------------------
        local generalHeader = GUI:CreateSectionHeader(tabContent, "General")
        generalHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - generalHeader.gap

        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable QUI Action Bars",
            "enabled", actionBars, function(val)
                GUI:ShowConfirmation({
                    title = "Reload Required",
                    message = "Action Bar styling requires a UI reload to take effect.",
                    acceptText = "Reload Now",
                    cancelText = "Later",
                    isDestructive = false,
                    onAccept = function()
                        QUI:SafeReload()
                    end,
                })
            end)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local tipText = GUI:CreateLabel(tabContent,
            "QUI hooks into Blizzard action bars to skin them. Position and resize bars via Edit Mode (Blizzard minimum padding: 2px). If you need actionbar paging (stance/form swapping), want to use action bars as your CDM, or prefer more control - disable QUI Action Bars and use a dedicated addon (e.g., Bartender4, Dominos).",
            11, C.warning)
        tipText:SetPoint("TOPLEFT", PAD, y)
        tipText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        tipText:SetJustifyH("LEFT")
        tipText:SetWordWrap(true)
        tipText:SetHeight(45)
        y = y - 55

        ---------------------------------------------------------
        -- Section: Button Appearance
        ---------------------------------------------------------
        local appearanceHeader = GUI:CreateSectionHeader(tabContent, "Button Appearance")
        appearanceHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - appearanceHeader.gap

        local zoomSlider = GUI:CreateFormSlider(tabContent, "Icon Crop Amount",
            0.05, 0.15, 0.01, "iconZoom", global, RefreshActionBars)
        zoomSlider:SetPoint("TOPLEFT", PAD, y)
        zoomSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local backdropCheck = GUI:CreateFormCheckbox(tabContent, "Show Backdrop",
            "showBackdrop", global, RefreshActionBars)
        backdropCheck:SetPoint("TOPLEFT", PAD, y)
        backdropCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local backdropAlphaSlider = GUI:CreateFormSlider(tabContent, "Backdrop Opacity",
            0, 1, 0.05, "backdropAlpha", global, RefreshActionBars)
        backdropAlphaSlider:SetPoint("TOPLEFT", PAD, y)
        backdropAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glossCheck = GUI:CreateFormCheckbox(tabContent, "Show Gloss Effect",
            "showGloss", global, RefreshActionBars)
        glossCheck:SetPoint("TOPLEFT", PAD, y)
        glossCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local glossAlphaSlider = GUI:CreateFormSlider(tabContent, "Gloss Opacity",
            0, 1, 0.05, "glossAlpha", global, RefreshActionBars)
        glossAlphaSlider:SetPoint("TOPLEFT", PAD, y)
        glossAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local bordersCheck = GUI:CreateFormCheckbox(tabContent, "Show Button Borders",
            "showBorders", global, RefreshActionBars)
        bordersCheck:SetPoint("TOPLEFT", PAD, y)
        bordersCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        ---------------------------------------------------------
        -- Section: Bar Layout
        ---------------------------------------------------------
        local layoutHeader = GUI:CreateSectionHeader(tabContent, "Bar Layout")
        layoutHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - layoutHeader.gap

        local scaleWarning = GUI:CreateLabel(tabContent, "To scale Action Bars, use Edit Mode: select each bar and adjust the 'Icon Size' slider. Enable 'Snap To Element' for easy alignment.", 11, C.warning)
        scaleWarning:SetPoint("TOPLEFT", PAD, y)
        scaleWarning:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        scaleWarning:SetJustifyH("LEFT")
        scaleWarning:SetWordWrap(true)
        scaleWarning:SetHeight(30)
        y = y - 32

        local hideEmptySlotsCheck = GUI:CreateFormCheckbox(tabContent, "Hide Empty Slots",
            "hideEmptySlots", global, RefreshActionBars)
        hideEmptySlotsCheck:SetPoint("TOPLEFT", PAD, y)
        hideEmptySlotsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Action Button Lock - combined lock + override key in one clear dropdown
        local lockOptions = {
            {value = "unlocked", text = "Unlocked"},
            {value = "shift", text = "Locked - Shift to drag"},
            {value = "alt", text = "Locked - Alt to drag"},
            {value = "ctrl", text = "Locked - Ctrl to drag"},
            {value = "none", text = "Fully Locked"},
        }
        -- Proxy that reads/writes to Blizzard's CVars
        local lockProxy = setmetatable({}, {
            __index = function(t, k)
                if k == "buttonLock" then
                    local isLocked = GetCVar("lockActionBars") == "1"
                    if not isLocked then return "unlocked" end
                    local modifier = GetModifiedClick("PICKUPACTION") or "SHIFT"
                    if modifier == "NONE" then return "none" end
                    return modifier:lower()
                end
            end,
            __newindex = function(t, k, v)
                if k == "buttonLock" and type(v) == "string" then
                    if v == "unlocked" then
                        SetCVar("lockActionBars", "0")
                    else
                        SetCVar("lockActionBars", "1")
                        local modifier = (v == "none") and "NONE" or v:upper()
                        SetModifiedClick("PICKUPACTION", modifier)
                        SaveBindings(GetCurrentBindingSet())
                    end
                end
            end
        })
        local lockDropdown = GUI:CreateFormDropdown(tabContent, "Action Button Lock", lockOptions,
            "buttonLock", lockProxy, RefreshActionBars)
        lockDropdown:SetPoint("TOPLEFT", PAD, y)
        lockDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        -- Refresh from Blizzard settings on show
        lockDropdown:HookScript("OnShow", function(self)
            self.SetValue(lockProxy.buttonLock, true)
        end)
        y = y - FORM_ROW

        local rangeCheck = GUI:CreateFormCheckbox(tabContent, "Out of Range Indicator",
            "rangeIndicator", global, RefreshActionBars)
        rangeCheck:SetPoint("TOPLEFT", PAD, y)
        rangeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local rangeColorPicker = GUI:CreateFormColorPicker(tabContent, "Out of Range Color",
            "rangeColor", global, RefreshActionBars)
        rangeColorPicker:SetPoint("TOPLEFT", PAD, y)
        rangeColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local usabilityCheck = GUI:CreateFormCheckbox(tabContent, "Dim Unusable Buttons",
            "usabilityIndicator", global, RefreshActionBars)
        usabilityCheck:SetPoint("TOPLEFT", PAD, y)
        usabilityCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local desaturateCheck = GUI:CreateFormCheckbox(tabContent, "Desaturate Unusable",
            "usabilityDesaturate", global, RefreshActionBars)
        desaturateCheck:SetPoint("TOPLEFT", PAD, y)
        desaturateCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local manaColorPicker = GUI:CreateFormColorPicker(tabContent, "Out of Mana Color",
            "manaColor", global, RefreshActionBars)
        manaColorPicker:SetPoint("TOPLEFT", PAD, y)
        manaColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fastUpdates = GUI:CreateFormCheckbox(tabContent, "Unthrottled CPU Usage",
            "fastUsabilityUpdates", global, RefreshActionBars)
        fastUpdates:SetPoint("TOPLEFT", PAD, y)
        fastUpdates:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local fastDesc = GUI:CreateLabel(tabContent, "Updates range/mana/unusable states 5x faster. Only enable if using action bars as your primary rotation display. Enabling while bars are hidden wastes CPU.", 11, {1, 0.6, 0})
        fastDesc:SetPoint("TOPLEFT", PAD, y + 4)
        y = y - 18

        local layoutTipText = GUI:CreateLabel(tabContent, "Enable 'Out of Range', 'Unusable' and 'Out of Mana' ONLY if you use Action Bars to replace CDM. They eat CPU resources.", 11, {1, 0.6, 0})
        layoutTipText:SetPoint("TOPLEFT", PAD, y)
        layoutTipText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        layoutTipText:SetJustifyH("LEFT")
        layoutTipText:SetWordWrap(true)
        y = y - 40

        ---------------------------------------------------------
        -- Section: Text Display
        ---------------------------------------------------------
        local textHeader = GUI:CreateSectionHeader(tabContent, "Text Display")
        textHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - textHeader.gap

        local keybindCheck = GUI:CreateFormCheckbox(tabContent, "Show Keybind Text",
            "showKeybinds", global, RefreshActionBars)
        keybindCheck:SetPoint("TOPLEFT", PAD, y)
        keybindCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideEmptyCheck = GUI:CreateFormCheckbox(tabContent, "Hide Empty Keybinds",
            "hideEmptyKeybinds", global, RefreshActionBars)
        hideEmptyCheck:SetPoint("TOPLEFT", PAD, y)
        hideEmptyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local keybindSizeSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Size",
            8, 50, 1, "keybindFontSize", global, RefreshActionBars)
        keybindSizeSlider:SetPoint("TOPLEFT", PAD, y)
        keybindSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local keybindAnchorDD = GUI:CreateFormDropdown(tabContent, "Keybind Text Anchor",
            anchorOptions, "keybindAnchor", global, RefreshActionBars)
        keybindAnchorDD:SetPoint("TOPLEFT", PAD, y)
        keybindAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local keybindXOffsetSlider = GUI:CreateFormSlider(tabContent, "Keybind Text X-Offset",
            -20, 20, 1, "keybindOffsetX", global, RefreshActionBars)
        keybindXOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        keybindXOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local keybindYOffsetSlider = GUI:CreateFormSlider(tabContent, "Keybind Text Y-Offset",
            -20, 20, 1, "keybindOffsetY", global, RefreshActionBars)
        keybindYOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        keybindYOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local keybindColorPicker = GUI:CreateFormColorPicker(tabContent, "Keybind Text Color",
            "keybindColor", global, RefreshActionBars)
        keybindColorPicker:SetPoint("TOPLEFT", PAD, y)
        keybindColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local macroCheck = GUI:CreateFormCheckbox(tabContent, "Show Macro Names",
            "showMacroNames", global, RefreshActionBars)
        macroCheck:SetPoint("TOPLEFT", PAD, y)
        macroCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local macroSizeSlider = GUI:CreateFormSlider(tabContent, "Macro Name Text Size",
            8, 50, 1, "macroNameFontSize", global, RefreshActionBars)
        macroSizeSlider:SetPoint("TOPLEFT", PAD, y)
        macroSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local macroAnchorDD = GUI:CreateFormDropdown(tabContent, "Macro Name Anchor",
            anchorOptions, "macroNameAnchor", global, RefreshActionBars)
        macroAnchorDD:SetPoint("TOPLEFT", PAD, y)
        macroAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local macroXOffsetSlider = GUI:CreateFormSlider(tabContent, "Macro Name X-Offset",
            -20, 20, 1, "macroNameOffsetX", global, RefreshActionBars)
        macroXOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        macroXOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local macroYOffsetSlider = GUI:CreateFormSlider(tabContent, "Macro Name Y-Offset",
            -20, 20, 1, "macroNameOffsetY", global, RefreshActionBars)
        macroYOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        macroYOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local macroColorPicker = GUI:CreateFormColorPicker(tabContent, "Macro Name Color",
            "macroNameColor", global, RefreshActionBars)
        macroColorPicker:SetPoint("TOPLEFT", PAD, y)
        macroColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local countCheck = GUI:CreateFormCheckbox(tabContent, "Show Stack Counts",
            "showCounts", global, RefreshActionBars)
        countCheck:SetPoint("TOPLEFT", PAD, y)
        countCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local countSizeSlider = GUI:CreateFormSlider(tabContent, "Stack Text Size",
            8, 50, 1, "countFontSize", global, RefreshActionBars)
        countSizeSlider:SetPoint("TOPLEFT", PAD, y)
        countSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local countAnchorDD = GUI:CreateFormDropdown(tabContent, "Stack Text Anchor",
            anchorOptions, "countAnchor", global, RefreshActionBars)
        countAnchorDD:SetPoint("TOPLEFT", PAD, y)
        countAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local countXOffsetSlider = GUI:CreateFormSlider(tabContent, "Stack Text X-Offset",
            -20, 20, 1, "countOffsetX", global, RefreshActionBars)
        countXOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        countXOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local countYOffsetSlider = GUI:CreateFormSlider(tabContent, "Stack Text Y-Offset",
            -20, 20, 1, "countOffsetY", global, RefreshActionBars)
        countYOffsetSlider:SetPoint("TOPLEFT", PAD, y)
        countYOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local countColorPicker = GUI:CreateFormColorPicker(tabContent, "Stack Count Color",
            "countColor", global, RefreshActionBars)
        countColorPicker:SetPoint("TOPLEFT", PAD, y)
        countColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        tabContent:SetHeight(math.abs(y) + 50)
    end  -- End BuildMasterSettingsTab

    ---------------------------------------------------------
    -- SUB-TAB: Per-Bar Overrides (Accordion Style)
    ---------------------------------------------------------
    local function BuildPerBarOverridesTab(tabContent)
        -- Set search context for widget auto-registration
        GUI:SetSearchContext({tabIndex = 4, tabName = "Action Bars", subTabIndex = 3, subTabName = "Per-Bar Overrides"})

        -- Use tabContent directly - parent Action Bars page already has scroll
        local content = tabContent
        local PAD = PADDING
        local FORM_ROW = 32
        local SECTION_GAP = 4

        -- 9-point anchor options for text positioning
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

        -- Bar info for accordion sections
        local barInfo = {
            {key = "bar1", label = "Action Bar 1"},
            {key = "bar2", label = "Action Bar 2"},
            {key = "bar3", label = "Action Bar 3"},
            {key = "bar4", label = "Action Bar 4"},
            {key = "bar5", label = "Action Bar 5"},
            {key = "bar6", label = "Action Bar 6"},
            {key = "bar7", label = "Action Bar 7"},
            {key = "bar8", label = "Action Bar 8"},
        }

        -- Track sections for accordion behavior
        local sections = {}

        -- Keys to copy when using Copy From
        local copyKeys = {
            "iconZoom", "showBackdrop", "backdropAlpha", "showGloss", "glossAlpha",
            "showKeybinds", "hideEmptyKeybinds", "keybindFontSize", "keybindColor",
            "keybindAnchor", "keybindOffsetX", "keybindOffsetY",
            "showMacroNames", "macroNameFontSize", "macroNameColor",
            "macroNameAnchor", "macroNameOffsetX", "macroNameOffsetY",
            "showCounts", "countFontSize", "countColor",
            "countAnchor", "countOffsetX", "countOffsetY",
        }

        -- Helper to update scroll content height
        local function UpdateScrollHeight()
            local totalHeight = 15
            for _, section in ipairs(sections) do
                totalHeight = totalHeight + section:GetHeight() + SECTION_GAP
            end
            content:SetHeight(totalHeight + 15)
        end

        -- Function to build settings into a container
        local function BuildBarSettingsIntoContainer(barKey, container, onOverrideChanged)
            local barDB = bars[barKey]
            if not barDB then return end

            local sy = -8  -- Start with small padding inside content area
            local widgetRefs = {}

            -- Hide Page Arrow toggle (bar1 only)
            if barKey == "bar1" then
                local pageArrowToggle = GUI:CreateFormCheckbox(container,
                    "Hide Default Paging Arrow", "hidePageArrow", barDB,
                    function(val)
                        if _G.QUI_ApplyPageArrowVisibility then
                            _G.QUI_ApplyPageArrowVisibility(val)
                        end
                    end)
                pageArrowToggle:SetPoint("TOPLEFT", 0, sy)
                pageArrowToggle:SetPoint("RIGHT", container, "RIGHT", 0, 0)
                sy = sy - FORM_ROW
            end

            -- Row 1: Override Master Settings toggle
            local overrideToggle = GUI:CreateFormCheckbox(container,
                "Override Master Settings", "overrideEnabled", barDB,
                function(val)
                    for _, widget in pairs(widgetRefs) do
                        widget:SetEnabled(val)
                    end
                    if onOverrideChanged then
                        onOverrideChanged()
                    end
                    RefreshActionBars()
                end)
            overrideToggle:SetPoint("TOPLEFT", 0, sy)
            overrideToggle:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            -- Row 2: Copy From dropdown
            local copyOptions = {
                {value = "master", text = "Master Settings"},
                {value = "bar1", text = "Bar 1"},
                {value = "bar2", text = "Bar 2"},
                {value = "bar3", text = "Bar 3"},
                {value = "bar4", text = "Bar 4"},
                {value = "bar5", text = "Bar 5"},
                {value = "bar6", text = "Bar 6"},
                {value = "bar7", text = "Bar 7"},
                {value = "bar8", text = "Bar 8"},
            }

            local copyDropdown = GUI:CreateFormDropdown(container, "Copy from", copyOptions, nil, nil,
                function(sourceKey)
                    if sourceKey == barKey then return end

                    local sourceDB
                    if sourceKey == "master" then
                        sourceDB = global
                    else
                        sourceDB = bars[sourceKey]
                    end

                    if not sourceDB then return end

                    for _, key in ipairs(copyKeys) do
                        if sourceDB[key] ~= nil then
                            barDB[key] = sourceDB[key]
                        end
                    end

                    barDB.overrideEnabled = true

                    -- Rebuild this section's content
                    for _, child in pairs({container:GetChildren()}) do
                        child:Hide()
                        child:SetParent(nil)
                    end
                    BuildBarSettingsIntoContainer(barKey, container, onOverrideChanged)

                    if onOverrideChanged then
                        onOverrideChanged()
                    end
                    RefreshActionBars()
                end)
            copyDropdown:SetPoint("TOPLEFT", 0, sy)
            copyDropdown:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            -- Appearance Section
            local appHeader = GUI:CreateSectionHeader(container, "Appearance")
            appHeader:SetPoint("TOPLEFT", 0, sy)
            sy = sy - appHeader.gap

            local zoomSlider = GUI:CreateFormSlider(container, "Icon Crop",
                0.05, 0.15, 0.01, "iconZoom", barDB, RefreshActionBars)
            zoomSlider:SetPoint("TOPLEFT", 0, sy)
            zoomSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, zoomSlider)
            sy = sy - FORM_ROW

            local backdropCheck = GUI:CreateFormCheckbox(container, "Show Backdrop",
                "showBackdrop", barDB, RefreshActionBars)
            backdropCheck:SetPoint("TOPLEFT", 0, sy)
            backdropCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, backdropCheck)
            sy = sy - FORM_ROW

            local backdropAlphaSlider = GUI:CreateFormSlider(container, "Backdrop Opacity",
                0, 1, 0.05, "backdropAlpha", barDB, RefreshActionBars)
            backdropAlphaSlider:SetPoint("TOPLEFT", 0, sy)
            backdropAlphaSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, backdropAlphaSlider)
            sy = sy - FORM_ROW

            local glossCheck = GUI:CreateFormCheckbox(container, "Show Gloss",
                "showGloss", barDB, RefreshActionBars)
            glossCheck:SetPoint("TOPLEFT", 0, sy)
            glossCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, glossCheck)
            sy = sy - FORM_ROW

            local glossAlphaSlider = GUI:CreateFormSlider(container, "Gloss Opacity",
                0, 1, 0.05, "glossAlpha", barDB, RefreshActionBars)
            glossAlphaSlider:SetPoint("TOPLEFT", 0, sy)
            glossAlphaSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, glossAlphaSlider)
            sy = sy - FORM_ROW

            local bordersCheck = GUI:CreateFormCheckbox(container, "Show Borders",
                "showBorders", barDB, RefreshActionBars)
            bordersCheck:SetPoint("TOPLEFT", 0, sy)
            bordersCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, bordersCheck)
            sy = sy - FORM_ROW

            -- Keybind Section
            local keyHeader = GUI:CreateSectionHeader(container, "Keybind Text")
            keyHeader:SetPoint("TOPLEFT", 0, sy)
            sy = sy - keyHeader.gap

            local keybindCheck = GUI:CreateFormCheckbox(container, "Show Keybinds",
                "showKeybinds", barDB, RefreshActionBars)
            keybindCheck:SetPoint("TOPLEFT", 0, sy)
            keybindCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, keybindCheck)
            sy = sy - FORM_ROW

            local hideEmptyCheck = GUI:CreateFormCheckbox(container, "Hide Empty Keybinds",
                "hideEmptyKeybinds", barDB, RefreshActionBars)
            hideEmptyCheck:SetPoint("TOPLEFT", 0, sy)
            hideEmptyCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, hideEmptyCheck)
            sy = sy - FORM_ROW

            local keybindSizeSlider = GUI:CreateFormSlider(container, "Font Size",
                8, 18, 1, "keybindFontSize", barDB, RefreshActionBars)
            keybindSizeSlider:SetPoint("TOPLEFT", 0, sy)
            keybindSizeSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, keybindSizeSlider)
            sy = sy - FORM_ROW

            local keybindAnchorDD = GUI:CreateFormDropdown(container, "Anchor",
                anchorOptions, "keybindAnchor", barDB, RefreshActionBars)
            keybindAnchorDD:SetPoint("TOPLEFT", 0, sy)
            keybindAnchorDD:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, keybindAnchorDD)
            sy = sy - FORM_ROW

            local keybindXOffsetSlider = GUI:CreateFormSlider(container, "X-Offset",
                -20, 20, 1, "keybindOffsetX", barDB, RefreshActionBars)
            keybindXOffsetSlider:SetPoint("TOPLEFT", 0, sy)
            keybindXOffsetSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, keybindXOffsetSlider)
            sy = sy - FORM_ROW

            local keybindYOffsetSlider = GUI:CreateFormSlider(container, "Y-Offset",
                -20, 20, 1, "keybindOffsetY", barDB, RefreshActionBars)
            keybindYOffsetSlider:SetPoint("TOPLEFT", 0, sy)
            keybindYOffsetSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, keybindYOffsetSlider)
            sy = sy - FORM_ROW

            local keybindColorPicker = GUI:CreateFormColorPicker(container, "Color",
                "keybindColor", barDB, RefreshActionBars)
            keybindColorPicker:SetPoint("TOPLEFT", 0, sy)
            keybindColorPicker:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, keybindColorPicker)
            sy = sy - FORM_ROW

            -- Macro Section
            local macroHeader = GUI:CreateSectionHeader(container, "Macro Text")
            macroHeader:SetPoint("TOPLEFT", 0, sy)
            sy = sy - macroHeader.gap

            local macroCheck = GUI:CreateFormCheckbox(container, "Show Macro Names",
                "showMacroNames", barDB, RefreshActionBars)
            macroCheck:SetPoint("TOPLEFT", 0, sy)
            macroCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, macroCheck)
            sy = sy - FORM_ROW

            local macroSizeSlider = GUI:CreateFormSlider(container, "Font Size",
                8, 18, 1, "macroNameFontSize", barDB, RefreshActionBars)
            macroSizeSlider:SetPoint("TOPLEFT", 0, sy)
            macroSizeSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, macroSizeSlider)
            sy = sy - FORM_ROW

            local macroAnchorDD = GUI:CreateFormDropdown(container, "Anchor",
                anchorOptions, "macroNameAnchor", barDB, RefreshActionBars)
            macroAnchorDD:SetPoint("TOPLEFT", 0, sy)
            macroAnchorDD:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, macroAnchorDD)
            sy = sy - FORM_ROW

            local macroXOffsetSlider = GUI:CreateFormSlider(container, "X-Offset",
                -20, 20, 1, "macroNameOffsetX", barDB, RefreshActionBars)
            macroXOffsetSlider:SetPoint("TOPLEFT", 0, sy)
            macroXOffsetSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, macroXOffsetSlider)
            sy = sy - FORM_ROW

            local macroYOffsetSlider = GUI:CreateFormSlider(container, "Y-Offset",
                -20, 20, 1, "macroNameOffsetY", barDB, RefreshActionBars)
            macroYOffsetSlider:SetPoint("TOPLEFT", 0, sy)
            macroYOffsetSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, macroYOffsetSlider)
            sy = sy - FORM_ROW

            local macroColorPicker = GUI:CreateFormColorPicker(container, "Color",
                "macroNameColor", barDB, RefreshActionBars)
            macroColorPicker:SetPoint("TOPLEFT", 0, sy)
            macroColorPicker:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, macroColorPicker)
            sy = sy - FORM_ROW

            -- Count Section
            local countHeader = GUI:CreateSectionHeader(container, "Stack Count")
            countHeader:SetPoint("TOPLEFT", 0, sy)
            sy = sy - countHeader.gap

            local countCheck = GUI:CreateFormCheckbox(container, "Show Counts",
                "showCounts", barDB, RefreshActionBars)
            countCheck:SetPoint("TOPLEFT", 0, sy)
            countCheck:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, countCheck)
            sy = sy - FORM_ROW

            local countSizeSlider = GUI:CreateFormSlider(container, "Font Size",
                8, 20, 1, "countFontSize", barDB, RefreshActionBars)
            countSizeSlider:SetPoint("TOPLEFT", 0, sy)
            countSizeSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, countSizeSlider)
            sy = sy - FORM_ROW

            local countAnchorDD = GUI:CreateFormDropdown(container, "Anchor",
                anchorOptions, "countAnchor", barDB, RefreshActionBars)
            countAnchorDD:SetPoint("TOPLEFT", 0, sy)
            countAnchorDD:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, countAnchorDD)
            sy = sy - FORM_ROW

            local countXOffsetSlider = GUI:CreateFormSlider(container, "X-Offset",
                -20, 20, 1, "countOffsetX", barDB, RefreshActionBars)
            countXOffsetSlider:SetPoint("TOPLEFT", 0, sy)
            countXOffsetSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, countXOffsetSlider)
            sy = sy - FORM_ROW

            local countYOffsetSlider = GUI:CreateFormSlider(container, "Y-Offset",
                -20, 20, 1, "countOffsetY", barDB, RefreshActionBars)
            countYOffsetSlider:SetPoint("TOPLEFT", 0, sy)
            countYOffsetSlider:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, countYOffsetSlider)
            sy = sy - FORM_ROW

            local countColorPicker = GUI:CreateFormColorPicker(container, "Color",
                "countColor", barDB, RefreshActionBars)
            countColorPicker:SetPoint("TOPLEFT", 0, sy)
            countColorPicker:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            table.insert(widgetRefs, countColorPicker)
            sy = sy - FORM_ROW

            -- Initialize enabled state
            for _, widget in pairs(widgetRefs) do
                widget:SetEnabled(barDB.overrideEnabled or false)
            end

            -- Set content height and update parent section
            container:SetHeight(math.abs(sy) + 8)

            -- Update parent section height
            local section = container:GetParent()
            if section and section.UpdateHeight then
                section:UpdateHeight()
            end
        end

        -- Edit Mode tip
        local warningText = GUI:CreateLabel(content, "To modify the number of icons, growth direction, or scale of each Action Bar, use Edit Mode and click on the bar you want to configure.", 11, C.warning)
        warningText:SetPoint("TOPLEFT", PAD, -15)
        warningText:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        warningText:SetJustifyH("LEFT")
        warningText:SetWordWrap(true)
        warningText:SetHeight(30)

        -- Create 8 accordion sections with relative anchoring
        -- Each section anchors to the previous section's bottom for dynamic repositioning
        local prevSection = nil
        for i, info in ipairs(barInfo) do
            local section = GUI:CreateCollapsibleSection(
                content,
                info.label,
                i == 1,  -- First section expanded by default
                {
                    text = "Override",
                    showFunc = function()
                        return bars[info.key] and bars[info.key].overrideEnabled
                    end
                }
            )

            -- Relative anchoring: each section anchors to the previous one's bottom
            if i == 1 then
                section:SetPoint("TOPLEFT", warningText, "BOTTOMLEFT", 0, -12)
            else
                section:SetPoint("TOPLEFT", prevSection, "BOTTOMLEFT", 0, -SECTION_GAP)
            end
            section:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

            -- Build settings into this section's content
            BuildBarSettingsIntoContainer(info.key, section.content, function()
                section:UpdateBadge()
                section:UpdateHeight()
                UpdateScrollHeight()
            end)

            -- Accordion behavior: collapse others when this expands
            section.OnExpandChanged = function(isExpanded)
                if isExpanded then
                    for _, other in ipairs(sections) do
                        if other ~= section and other:GetExpanded() then
                            other:SetExpanded(false)
                        end
                    end
                end
                UpdateScrollHeight()
            end

            table.insert(sections, section)
            prevSection = section
        end

        -- Initial height calculation (delayed to ensure layout is complete)
        C_Timer.After(0.1, UpdateScrollHeight)
    end  -- End BuildPerBarOverridesTab

    ---------------------------------------------------------
    -- SUB-TAB: Extra Buttons (Extra Action Button & Zone Ability)
    ---------------------------------------------------------
    local function BuildExtraButtonsTab(tabContent)
        local y = -15
        local PAD = PADDING
        local FORM_ROW = 32

        -- Set search context
        GUI:SetSearchContext({tabIndex = 4, tabName = "Action Bars", subTabIndex = 4, subTabName = "Extra Buttons"})

        -- Refresh callback
        local function RefreshExtraButtons()
            if _G.QUI_RefreshExtraButtons then
                _G.QUI_RefreshExtraButtons()
            end
        end

        -- Description
        local descLabel = GUI:CreateLabel(tabContent,
            "Customize the Extra Action Button (boss encounters, quests) and Zone Ability Button (garrison, covenant, zone abilities) separately.",
            11, C.textMuted)
        descLabel:SetPoint("TOPLEFT", PAD, y)
        descLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        descLabel:SetJustifyH("LEFT")
        descLabel:SetWordWrap(true)
        descLabel:SetHeight(30)
        y = y - 40

        -- Toggle Movers Button
        local moverBtn = GUI:CreateButton(tabContent, "Toggle Position Movers", 200, 28, function()
            if _G.QUI_ToggleExtraButtonMovers then
                _G.QUI_ToggleExtraButtonMovers()
            end
        end)
        moverBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 35

        local moverTip = GUI:CreateLabel(tabContent,
            "Click to show draggable movers. Drag to position, use sliders for fine-tuning.",
            10, C.textMuted)
        moverTip:SetPoint("TOPLEFT", PAD, y)
        moverTip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        moverTip:SetJustifyH("LEFT")
        y = y - 25

        ---------------------------------------------------------
        -- SECTION: Extra Action Button
        ---------------------------------------------------------
        local extraHeader = GUI:CreateSectionHeader(tabContent, "Extra Action Button")
        extraHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - extraHeader.gap

        local extraDB = bars.extraActionButton
        if extraDB then
            local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Customization",
                "enabled", extraDB, RefreshExtraButtons)
            enableCheck:SetPoint("TOPLEFT", PAD, y)
            enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local scaleSlider = GUI:CreateFormSlider(tabContent, "Scale",
                0.5, 2.0, 0.05, "scale", extraDB, RefreshExtraButtons)
            scaleSlider:SetPoint("TOPLEFT", PAD, y)
            scaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local xOffsetSlider = GUI:CreateFormSlider(tabContent, "X Offset",
                -200, 200, 1, "offsetX", extraDB, RefreshExtraButtons)
            xOffsetSlider:SetPoint("TOPLEFT", PAD, y)
            xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Y Offset",
                -200, 200, 1, "offsetY", extraDB, RefreshExtraButtons)
            yOffsetSlider:SetPoint("TOPLEFT", PAD, y)
            yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local hideArtCheck = GUI:CreateFormCheckbox(tabContent, "Hide Button Artwork",
                "hideArtwork", extraDB, RefreshExtraButtons)
            hideArtCheck:SetPoint("TOPLEFT", PAD, y)
            hideArtCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local fadeCheck = GUI:CreateFormCheckbox(tabContent, "Enable Mouseover Fade",
                "fadeEnabled", extraDB, function()
                    RefreshExtraButtons()
                    if extraDB.fadeEnabled then
                        GUI:ShowConfirmation({
                            title = "Reload UI?",
                            message = "Mouseover fade requires a reload to take effect.",
                            acceptText = "Reload",
                            cancelText = "Later",
                            onAccept = function() QUI:SafeReload() end,
                        })
                    end
                end)
            fadeCheck:SetPoint("TOPLEFT", PAD, y)
            fadeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end
        y = y - 15

        ---------------------------------------------------------
        -- SECTION: Zone Ability Button
        ---------------------------------------------------------
        local zoneHeader = GUI:CreateSectionHeader(tabContent, "Zone Ability Button")
        zoneHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - zoneHeader.gap

        local zoneDB = bars.zoneAbility
        if zoneDB then
            local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Customization",
                "enabled", zoneDB, RefreshExtraButtons)
            enableCheck:SetPoint("TOPLEFT", PAD, y)
            enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local scaleSlider = GUI:CreateFormSlider(tabContent, "Scale",
                0.5, 2.0, 0.05, "scale", zoneDB, RefreshExtraButtons)
            scaleSlider:SetPoint("TOPLEFT", PAD, y)
            scaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local xOffsetSlider = GUI:CreateFormSlider(tabContent, "X Offset",
                -200, 200, 1, "offsetX", zoneDB, RefreshExtraButtons)
            xOffsetSlider:SetPoint("TOPLEFT", PAD, y)
            xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Y Offset",
                -200, 200, 1, "offsetY", zoneDB, RefreshExtraButtons)
            yOffsetSlider:SetPoint("TOPLEFT", PAD, y)
            yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local hideArtCheck = GUI:CreateFormCheckbox(tabContent, "Hide Button Artwork",
                "hideArtwork", zoneDB, RefreshExtraButtons)
            hideArtCheck:SetPoint("TOPLEFT", PAD, y)
            hideArtCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local fadeCheck = GUI:CreateFormCheckbox(tabContent, "Enable Mouseover Fade",
                "fadeEnabled", zoneDB, function()
                    RefreshExtraButtons()
                    if zoneDB.fadeEnabled then
                        GUI:ShowConfirmation({
                            title = "Reload UI?",
                            message = "Mouseover fade requires a reload to take effect.",
                            acceptText = "Reload",
                            cancelText = "Later",
                            onAccept = function() QUI:SafeReload() end,
                        })
                    end
                end)
            fadeCheck:SetPoint("TOPLEFT", PAD, y)
            fadeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        tabContent:SetHeight(math.abs(y) + 50)
    end  -- End BuildExtraButtonsTab

    ---------------------------------------------------------
    -- Create Sub-Tabs
    ---------------------------------------------------------
    local subTabs = GUI:CreateSubTabs(content, {
        {name = "Master Settings", builder = BuildMasterSettingsTab},
        {name = "Mouseover Hide", builder = BuildMouseoverHideTab},
        {name = "Per-Bar Overrides", builder = BuildPerBarOverridesTab},
        {name = "Extra Buttons", builder = BuildExtraButtonsTab},
        {name = "Totem Bar", builder = BuildTotemBarTab},
    })
    subTabs:SetPoint("TOPLEFT", 5, -5)
    subTabs:SetPoint("TOPRIGHT", -5, -5)
    subTabs:SetHeight(700)

    content:SetHeight(750)
    return scroll, content
end

---------------------------------------------------------------------------
-- SUB-TAB: Totem Bar (Shaman only)
---------------------------------------------------------------------------
BuildTotemBarTab = function(tabContent)
    local y = -15
    local PAD = PADDING
    local FORM_ROW = 32

    local QUICore = _G.QUI and _G.QUI.QUICore
    local db = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.totemBar

    -- Class guard: show notice for non-shamans
    local _, playerClass = UnitClass("player")
    if playerClass ~= "SHAMAN" then
        local notice = GUI:CreateLabel(tabContent, "Totem Bar is only available for Shaman characters.", 12, C.textMuted)
        notice:SetPoint("TOPLEFT", PAD, y)
        notice:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        notice:SetJustifyH("LEFT")
        tabContent:SetHeight(60)
        return
    end

    if not db then
        local notice = GUI:CreateLabel(tabContent, "Totem Bar settings not available. Try /rl.", 12, C.textMuted)
        notice:SetPoint("TOPLEFT", PAD, y)
        notice:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        notice:SetJustifyH("LEFT")
        tabContent:SetHeight(60)
        return
    end

    local function RefreshTotemBar()
        if _G.QUI_RefreshTotemBar then
            _G.QUI_RefreshTotemBar()
        end
    end

    -- =====================================================
    -- ENABLE & LOCK
    -- =====================================================
    local enableHeader = GUI:CreateSectionHeader(tabContent, "Totem Bar")
    enableHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - enableHeader.gap

    local enableCB = GUI:CreateFormCheckbox(tabContent, "Enable Totem Bar", "enabled", db, RefreshTotemBar)
    enableCB:SetPoint("TOPLEFT", PAD, y)
    enableCB:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local lockCB = GUI:CreateFormCheckbox(tabContent, "Lock Position", "locked", db)
    lockCB:SetPoint("TOPLEFT", PAD, y)
    lockCB:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- Preview toggle (pill-shaped, matches Debuff/Buff Preview style)
    local previewContainer = CreateFrame("Frame", nil, tabContent)
    previewContainer:SetHeight(FORM_ROW)
    previewContainer:SetPoint("TOPLEFT", PAD, y)
    previewContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

    local previewLabel = previewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLabel:SetPoint("LEFT", 0, 0)
    previewLabel:SetText("Preview")
    previewLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

    local previewTrack = CreateFrame("Button", nil, previewContainer, "BackdropTemplate")
    previewTrack:SetSize(40, 20)
    previewTrack:SetPoint("LEFT", previewContainer, "LEFT", 180, 0)
    previewTrack:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})

    local previewThumb = CreateFrame("Frame", nil, previewTrack, "BackdropTemplate")
    previewThumb:SetSize(16, 16)
    previewThumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    previewThumb:SetBackdropColor(0.95, 0.95, 0.95, 1)
    previewThumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
    previewThumb:SetFrameLevel(previewTrack:GetFrameLevel() + 1)

    local isPreviewOn = false
    local function UpdatePreviewToggle(on)
        if on then
            previewTrack:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
            previewTrack:SetBackdropBorderColor(C.accent[1]*0.8, C.accent[2]*0.8, C.accent[3]*0.8, 1)
            previewThumb:ClearAllPoints()
            previewThumb:SetPoint("RIGHT", previewTrack, "RIGHT", -2, 0)
        else
            previewTrack:SetBackdropColor(0.15, 0.18, 0.22, 1)
            previewTrack:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
            previewThumb:ClearAllPoints()
            previewThumb:SetPoint("LEFT", previewTrack, "LEFT", 2, 0)
        end
    end
    UpdatePreviewToggle(isPreviewOn)

    previewTrack:SetScript("OnClick", function()
        isPreviewOn = not isPreviewOn
        UpdatePreviewToggle(isPreviewOn)
        if _G.QUI_ToggleTotemBarPreview then
            _G.QUI_ToggleTotemBarPreview()
        end
    end)
    y = y - FORM_ROW

    local info = GUI:CreateLabel(tabContent, "Shows mock totems for positioning. Drag to reposition.", 11, C.textMuted)
    info:SetPoint("TOPLEFT", PAD, y)
    info:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    info:SetJustifyH("LEFT")
    y = y - 24

    -- Hide preview when leaving the tab
    tabContent:SetScript("OnHide", function()
        if _G.QUI_HideTotemBarPreview then
            _G.QUI_HideTotemBarPreview()
            isPreviewOn = false
            UpdatePreviewToggle(false)
        end
    end)

    -- =====================================================
    -- LAYOUT
    -- =====================================================
    local layoutHeader = GUI:CreateSectionHeader(tabContent, "Layout")
    layoutHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - layoutHeader.gap

    local growOptions = {
        {value = "RIGHT", text = "Right"},
        {value = "LEFT", text = "Left"},
        {value = "DOWN", text = "Down"},
        {value = "UP", text = "Up"},
    }
    local growDD = GUI:CreateFormDropdown(tabContent, "Grow Direction", growOptions, "growDirection", db, RefreshTotemBar)
    growDD:SetPoint("TOPLEFT", PAD, y)
    growDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW - 4

    local sizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 20, 80, 1, "iconSize", db, RefreshTotemBar)
    sizeSlider:SetPoint("TOPLEFT", PAD, y)
    sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local spacingSlider = GUI:CreateFormSlider(tabContent, "Spacing", 0, 20, 1, "spacing", db, RefreshTotemBar)
    spacingSlider:SetPoint("TOPLEFT", PAD, y)
    spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local borderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 6, 1, "borderSize", db, RefreshTotemBar)
    borderSlider:SetPoint("TOPLEFT", PAD, y)
    borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local zoomSlider = GUI:CreateFormSlider(tabContent, "Icon Zoom", 0, 0.15, 0.01, "zoom", db, RefreshTotemBar)
    zoomSlider:SetPoint("TOPLEFT", PAD, y)
    zoomSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- =====================================================
    -- DURATION DISPLAY
    -- =====================================================
    local durHeader = GUI:CreateSectionHeader(tabContent, "Duration Display")
    durHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - durHeader.gap

    local hideDurCB = GUI:CreateFormCheckbox(tabContent, "Hide Duration Text", "hideDurationText", db, RefreshTotemBar)
    hideDurCB:SetPoint("TOPLEFT", PAD, y)
    hideDurCB:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local durSizeSlider = GUI:CreateFormSlider(tabContent, "Duration Text Size", 8, 24, 1, "durationSize", db, RefreshTotemBar)
    durSizeSlider:SetPoint("TOPLEFT", PAD, y)
    durSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local showSwipeCB = GUI:CreateFormCheckbox(tabContent, "Show Cooldown Swipe", "showSwipe", db, RefreshTotemBar)
    showSwipeCB:SetPoint("TOPLEFT", PAD, y)
    showSwipeCB:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    -- =====================================================
    -- POSITION
    -- =====================================================
    local posHeader = GUI:CreateSectionHeader(tabContent, "Position")
    posHeader:SetPoint("TOPLEFT", PAD, y)
    y = y - posHeader.gap

    local oxSlider = GUI:CreateFormSlider(tabContent, "Offset X", -960, 960, 1, "offsetX", db, RefreshTotemBar)
    oxSlider:SetPoint("TOPLEFT", PAD, y)
    oxSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    local oySlider = GUI:CreateFormSlider(tabContent, "Offset Y", -540, 540, 1, "offsetY", db, RefreshTotemBar)
    oySlider:SetPoint("TOPLEFT", PAD, y)
    oySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
    y = y - FORM_ROW

    tabContent:SetHeight(math.abs(y) + 30)
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
ns.QUI_ActionBarsOptions = {
    CreateActionBarsPage = CreateActionBarsPage
}
