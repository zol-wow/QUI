--[[
    QUI QoL Options - General Tab
    BuildGeneralTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local QUICore = ns.Addon
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local function BuildGeneralTab(tabContent)
    local y = -10
    local FORM_ROW = 32
    local PADDING = Shared.PADDING
    local db = Shared.GetDB()

    -- Refresh callback for fonts/textures (refreshes everything that uses these defaults)
    local function RefreshAll()
        -- Refresh core CDM viewers
        if QUICore and QUICore.RefreshAll then
            QUICore:RefreshAll()
        end
        -- Refresh unit frames (use global function)
        if _G.QUI_RefreshUnitFrames then
            _G.QUI_RefreshUnitFrames()
        end
        -- Refresh power bars (recreate to apply new fonts/textures)
        if QUICore then
            if QUICore.UpdatePowerBar then
                QUICore:UpdatePowerBar()
            end
            if QUICore.UpdateSecondaryPowerBar then
                QUICore:UpdateSecondaryPowerBar()
            end
        end
        -- Refresh minimap/datatext
        if QUICore and QUICore.Minimap and QUICore.Minimap.Refresh then
            QUICore.Minimap:Refresh()
        end
        -- Refresh buff borders
        if _G.QUI_RefreshBuffBorders then
            _G.QUI_RefreshBuffBorders()
        end
        -- Refresh NCDM (CDM icons)
        if ns and ns.NCDM and ns.NCDM.RefreshAll then
            ns.NCDM:RefreshAll()
        end
        -- Refresh loot window fonts
        if QUICore and QUICore.Loot and QUICore.Loot.RefreshColors then
            QUICore.Loot:RefreshColors()
        end
        -- Trigger CDM layout refresh
        C_Timer.After(0.1, function()
            if QUICore and QUICore.ApplyViewerLayout then
                QUICore:ApplyViewerLayout("EssentialCooldownViewer")
                QUICore:ApplyViewerLayout("UtilityCooldownViewer")
            end
        end)
    end

    -- Set search context for auto-registration
    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 1, subTabName = "General"})

    -- UI Scale Section
    GUI:SetSearchSection("UI Scale")
    local scaleHeader = GUI:CreateSectionHeader(tabContent, "UI Scale")
    scaleHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - scaleHeader.gap

    if db and db.general then
        local scaleSlider = GUI:CreateFormSlider(tabContent, "Global UI Scale", 0.3, 2.0, 0.01,
            "uiScale", db.general, function(val)
                pcall(function() UIParent:SetScale(val) end)
            end, { deferOnDrag = true, precision = 7 })
        scaleSlider:SetPoint("TOPLEFT", PADDING, y)
        scaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Quick preset buttons
        local presetLabel = GUI:CreateLabel(tabContent, "Quick UI Scale Presets:", 12, C.text)
        presetLabel:SetPoint("TOPLEFT", PADDING, y)

        local function ApplyPreset(val, name)
            db.general.uiScale = val
            pcall(function() UIParent:SetScale(val) end)
            local msg = "|cff34D399[QUI]|r UI scale set to " .. val
            if name then msg = msg .. " (" .. name .. ")" end
            DEFAULT_CHAT_FRAME:AddMessage(msg)
            scaleSlider.SetValue(val, true)
        end

        local function AutoScale()
            local _, height = GetPhysicalScreenSize()
            local scale = 768 / height
            scale = math.max(0.3, math.min(2.0, scale))
            ApplyPreset(scale, "Auto")
        end

        -- Button container aligned with slider track (180px) to editbox right edge
        local buttonContainer = CreateFrame("Frame", nil, tabContent)
        buttonContainer:SetPoint("LEFT", scaleSlider, "LEFT", 180, 0)
        buttonContainer:SetPoint("RIGHT", scaleSlider, "RIGHT", 0, 0)
        buttonContainer:SetPoint("TOP", presetLabel, "TOP", 0, 0)
        buttonContainer:SetHeight(26)

        local BUTTON_GAP = 6
        local NUM_BUTTONS = 5
        local buttons = {}

        -- Create buttons with placeholder width (will be set dynamically)
        buttons[1] = GUI:CreateButton(buttonContainer, "1080p", 50, 26, function() ApplyPreset(0.7111111, "1080p") end)
        buttons[2] = GUI:CreateButton(buttonContainer, "1440p", 50, 26, function() ApplyPreset(0.5333333, "1440p") end)
        buttons[3] = GUI:CreateButton(buttonContainer, "1440p+", 50, 26, function() ApplyPreset(0.64, "1440p+") end)
        buttons[4] = GUI:CreateButton(buttonContainer, "4K", 50, 26, function() ApplyPreset(0.3555556, "4K") end)
        buttons[5] = GUI:CreateButton(buttonContainer, "Auto", 50, 26, AutoScale)

        -- Dynamically size and position buttons when container width is known
        buttonContainer:SetScript("OnSizeChanged", function(self, width)
            if width and width > 0 then
                local buttonWidth = (width - (NUM_BUTTONS - 1) * BUTTON_GAP) / NUM_BUTTONS
                for i, btn in ipairs(buttons) do
                    btn:SetWidth(buttonWidth)
                    btn:ClearAllPoints()
                    if i == 1 then
                        btn:SetPoint("LEFT", self, "LEFT", 0, 0)
                    else
                        btn:SetPoint("LEFT", buttons[i-1], "RIGHT", BUTTON_GAP, 0)
                    end
                end
            end
        end)

        -- Tooltip data for preset buttons
        local tooltipData = {
            { title = "1080p", desc = "Scale: 0.7111111\nPixel-perfect for 1920x1080" },
            { title = "1440p", desc = "Scale: 0.5333333\nPixel-perfect for 2560x1440" },
            { title = "1440p+", desc = "Scale: 0.64\nQuazii's personal setting - larger and more readable.\nRequires manual adjustment for pixel perfection." },
            { title = "4K", desc = "Scale: 0.3555556\nPixel-perfect for 3840x2160" },
            { title = "Auto", desc = "Computes pixel-perfect scale based on your resolution.\nFormula: 768 / screen height" },
        }

        -- Add tooltips to buttons
        for i, btn in ipairs(buttons) do
            local data = tooltipData[i]
            btn:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(data.title, 1, 1, 1)
                GameTooltip:AddLine(data.desc, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            btn:HookScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end

        y = y - FORM_ROW - 6

        -- Single summary line
        local presetSummary = GUI:CreateLabel(tabContent,
            "Hover over any preset for details. 1440p+ is Quazii's personal setting.",
            11, C.textMuted)
        presetSummary:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20

        -- Big picture advice
        local bigPicture = GUI:CreateLabel(tabContent,
            "UI scale is highly personal-it depends on your monitor size, resolution, and preference. If you already have a scale you like from years of playing WoW, stick with it. These presets are just common values people tend to use.",
            11, C.textMuted)
        bigPicture:SetPoint("TOPLEFT", PADDING, y)
        bigPicture:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        bigPicture:SetJustifyH("LEFT")
        y = y - 36
    end

    -- Default Font Section
    GUI:SetSearchSection("Default Font Settings")
    local fontTexHeader = GUI:CreateSectionHeader(tabContent, "Default Font Settings")
    fontTexHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - fontTexHeader.gap

    local tipText = GUI:CreateLabel(tabContent, "These settings apply throughout the UI. Individual elements with their own font options will override these defaults.", 11, C.textMuted)
    tipText:SetPoint("TOPLEFT", PADDING, y)
    tipText:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    tipText:SetJustifyH("LEFT")
    y = y - 28

    if db and db.general then
        local fontList = {}
        local LSM = LibStub("LibSharedMedia-3.0", true)
        if LSM then
            for name in pairs(LSM:HashTable("font")) do
                table.insert(fontList, {value = name, text = name})
            end
            table.sort(fontList, function(a, b) return a.text < b.text end)
        else
            fontList = {{value = "Friz Quadrata TT", text = "Friz Quadrata TT"}}
        end

        local fontDropdown = GUI:CreateFormDropdown(tabContent, "Default Font", fontList, "font", db.general, RefreshAll)
        fontDropdown:SetPoint("TOPLEFT", PADDING, y)
        fontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local outlineOptions = {
            {value = "", text = "None"},
            {value = "OUTLINE", text = "Outline"},
            {value = "THICKOUTLINE", text = "Thick Outline"},
        }
        local outlineDropdown = GUI:CreateFormDropdown(tabContent, "Font Outline", outlineOptions, "fontOutline", db.general, RefreshAll)
        outlineDropdown:SetPoint("TOPLEFT", PADDING, y)
        outlineDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    y = y - 10

    -- Quazii Recommended FPS Settings Section
    local fpsHeader = GUI:CreateSectionHeader(tabContent, "Quazii Recommended FPS Settings")
    fpsHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - fpsHeader.gap

    local fpsDesc = GUI:CreateLabel(tabContent,
        "Apply Quazii's optimized graphics settings for competitive play. " ..
        "Your current settings are automatically saved when you click Apply - use 'Restore Previous Settings' to revert anytime. " ..
        "Caution: Clicking Apply again will overwrite your backup with these settings.",
        11, C.textMuted)
    fpsDesc:SetPoint("TOPLEFT", PADDING, y)
    fpsDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    fpsDesc:SetJustifyH("LEFT")
    fpsDesc:SetWordWrap(true)
    fpsDesc:SetHeight(30)
    y = y - 40

    local restoreFpsBtn
    local fpsStatusText

    local function UpdateFPSStatus()
        local allMatch, matched, total = Shared.CheckCVarsMatch()
        -- Some CVars can't be verified (protected/restart required), so threshold at 50+
        if matched >= 50 then
            fpsStatusText:SetText("Settings: All applied")
            fpsStatusText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            fpsStatusText:SetText(string.format("Settings: %d/%d match", matched, total))
            fpsStatusText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
        end
    end

    local applyFpsBtn = GUI:CreateButton(tabContent, "Apply FPS Settings", 180, 28, function()
        Shared.ApplyQuaziiFPSSettings()
        restoreFpsBtn:SetAlpha(1)
        restoreFpsBtn:Enable()
        UpdateFPSStatus()
    end)
    applyFpsBtn:SetPoint("TOPLEFT", PADDING, y)
    applyFpsBtn:SetPoint("RIGHT", tabContent, "CENTER", -5, 0)

    restoreFpsBtn = GUI:CreateButton(tabContent, "Restore Previous Settings", 180, 28, function()
        if Shared.RestorePreviousFPSSettings() then
            restoreFpsBtn:SetAlpha(0.5)
            restoreFpsBtn:Disable()
        end
        UpdateFPSStatus()
    end)
    restoreFpsBtn:SetPoint("LEFT", tabContent, "CENTER", 5, 0)
    restoreFpsBtn:SetPoint("TOP", applyFpsBtn, "TOP", 0, 0)
    restoreFpsBtn:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - 38

    fpsStatusText = GUI:CreateLabel(tabContent, "", 11, C.accent)
    fpsStatusText:SetPoint("TOPLEFT", PADDING, y)

    if not db.fpsBackup then
        restoreFpsBtn:SetAlpha(0.5)
        restoreFpsBtn:Disable()
    end

    UpdateFPSStatus()

    y = y - 22

    -- Combat Status Text Indicator Section
    local combatTextHeader = GUI:CreateSectionHeader(tabContent, "Combat Status Text Indicator")
    combatTextHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - combatTextHeader.gap

    local combatTextDesc = GUI:CreateLabel(tabContent,
        "Displays '+Combat' or '-Combat' text on screen when entering or leaving combat. Useful for Shadowmeld skips.",
        11, C.textMuted)
    combatTextDesc:SetPoint("TOPLEFT", PADDING, y)
    combatTextDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    combatTextDesc:SetJustifyH("LEFT")
    combatTextDesc:SetWordWrap(true)
    combatTextDesc:SetHeight(15)
    y = y - 25

    -- Preview buttons
    local previewEnterBtn = GUI:CreateButton(tabContent, "Preview +Combat", 140, 28, function()
        if _G.QUI_PreviewCombatText then _G.QUI_PreviewCombatText("+Combat") end
    end)
    previewEnterBtn:SetPoint("TOPLEFT", PADDING, y)
    previewEnterBtn:SetPoint("RIGHT", tabContent, "CENTER", -5, 0)

    local previewLeaveBtn = GUI:CreateButton(tabContent, "Preview -Combat", 140, 28, function()
        if _G.QUI_PreviewCombatText then _G.QUI_PreviewCombatText("-Combat") end
    end)
    previewLeaveBtn:SetPoint("LEFT", tabContent, "CENTER", 5, 0)
    previewLeaveBtn:SetPoint("TOP", previewEnterBtn, "TOP", 0, 0)
    previewLeaveBtn:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - 38

    local combatTextDB = db and db.combatText
    if combatTextDB then
        local combatTextCheck = GUI:CreateFormCheckbox(tabContent, "Enable Combat Text", "enabled", combatTextDB, function(val)
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        combatTextCheck:SetPoint("TOPLEFT", PADDING, y)
        combatTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local displayTimeSlider = GUI:CreateFormSlider(tabContent, "Display Time (sec)", 0.3, 3.0, 0.1, "displayTime", combatTextDB, function()
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        displayTimeSlider:SetPoint("TOPLEFT", PADDING, y)
        displayTimeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local fadeTimeSlider = GUI:CreateFormSlider(tabContent, "Fade Duration (sec)", 0.1, 1.0, 0.05, "fadeTime", combatTextDB, function()
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        fadeTimeSlider:SetPoint("TOPLEFT", PADDING, y)
        fadeTimeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 12, 48, 1, "fontSize", combatTextDB, function()
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        fontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local xOffsetSlider = GUI:CreateFormSlider(tabContent, "X Position Offset", -2000, 2000, 1, "xOffset", combatTextDB, function()
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        xOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Y Position Offset", -2000, 2000, 1, "yOffset", combatTextDB, function()
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        yOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local enterColorPicker = GUI:CreateFormColorPicker(tabContent, "+Combat Text Color", "enterCombatColor", combatTextDB, function()
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        enterColorPicker:SetPoint("TOPLEFT", PADDING, y)
        enterColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local leaveColorPicker = GUI:CreateFormColorPicker(tabContent, "-Combat Text Color", "leaveCombatColor", combatTextDB, function()
            if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
        end)
        leaveColorPicker:SetPoint("TOPLEFT", PADDING, y)
        leaveColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    y = y - 10

    -- Combat Timer Section
    local combatTimerHeader = GUI:CreateSectionHeader(tabContent, "Combat Timer")
    combatTimerHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - combatTimerHeader.gap

    local combatTimerDesc = GUI:CreateLabel(tabContent,
        "Displays elapsed combat time. Timer resets each time you leave combat.",
        11, C.textMuted)
    combatTimerDesc:SetPoint("TOPLEFT", PADDING, y)
    combatTimerDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    combatTimerDesc:SetJustifyH("LEFT")
    combatTimerDesc:SetWordWrap(true)
    combatTimerDesc:SetHeight(15)
    y = y - 25

    local combatTimerDB = db and db.combatTimer
    if combatTimerDB then
        local combatTimerCheck = GUI:CreateFormCheckbox(tabContent, "Enable Combat Timer", "enabled", combatTimerDB, function(val)
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        combatTimerCheck:SetPoint("TOPLEFT", PADDING, y)
        combatTimerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Encounters-only mode toggle
        local encountersOnlyCheck = GUI:CreateFormCheckbox(tabContent, "Only Show In Encounters", "onlyShowInEncounters", combatTimerDB, function(val)
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        encountersOnlyCheck:SetPoint("TOPLEFT", PADDING, y)
        encountersOnlyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Preview toggle
        local previewState = { enabled = _G.QUI_IsCombatTimerPreviewMode and _G.QUI_IsCombatTimerPreviewMode() or false }
        local previewCheck = GUI:CreateFormCheckbox(tabContent, "Preview Combat Timer", "enabled", previewState, function(val)
            if _G.QUI_ToggleCombatTimerPreview then
                _G.QUI_ToggleCombatTimerPreview(val)
            end
        end)
        previewCheck:SetPoint("TOPLEFT", PADDING, y)
        previewCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Frame size settings
        local timerWidthSlider = GUI:CreateFormSlider(tabContent, "Frame Width", 40, 200, 1, "width", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        timerWidthSlider:SetPoint("TOPLEFT", PADDING, y)
        timerWidthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local timerHeightSlider = GUI:CreateFormSlider(tabContent, "Frame Height", 20, 100, 1, "height", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        timerHeightSlider:SetPoint("TOPLEFT", PADDING, y)
        timerHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local timerFontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 12, 32, 1, "fontSize", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        timerFontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        timerFontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local timerXOffsetSlider = GUI:CreateFormSlider(tabContent, "X Position Offset", -2000, 2000, 1, "xOffset", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        timerXOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        timerXOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local timerYOffsetSlider = GUI:CreateFormSlider(tabContent, "Y Position Offset", -2000, 2000, 1, "yOffset", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        timerYOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        timerYOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Text color with class color toggle
        local timerColorPicker  -- Forward declare

        local useClassColorTextCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Text", "useClassColorText", combatTimerDB, function(val)
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
            -- Enable/disable text color picker based on toggle
            if timerColorPicker and timerColorPicker.SetEnabled then
                timerColorPicker:SetEnabled(not val)
            end
        end)
        useClassColorTextCheck:SetPoint("TOPLEFT", PADDING, y)
        useClassColorTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        timerColorPicker = GUI:CreateFormColorPicker(tabContent, "Timer Text Color", "textColor", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        timerColorPicker:SetPoint("TOPLEFT", PADDING, y)
        timerColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        -- Initial state based on setting
        if timerColorPicker.SetEnabled then
            timerColorPicker:SetEnabled(not combatTimerDB.useClassColorText)
        end
        y = y - FORM_ROW

        -- Font selection with custom toggle
        local fontList = Shared.GetFontList()
        local timerFontDropdown  -- Forward declare

        local useCustomFontCheck = GUI:CreateFormCheckbox(tabContent, "Use Custom Font", "useCustomFont", combatTimerDB, function(val)
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
            -- Enable/disable font dropdown based on toggle
            if timerFontDropdown and timerFontDropdown.SetEnabled then
                timerFontDropdown:SetEnabled(val)
            end
        end)
        useCustomFontCheck:SetPoint("TOPLEFT", PADDING, y)
        useCustomFontCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        timerFontDropdown = GUI:CreateFormDropdown(tabContent, "Font", fontList, "font", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        timerFontDropdown:SetPoint("TOPLEFT", PADDING, y)
        timerFontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        -- Initial state based on setting
        if timerFontDropdown.SetEnabled then
            timerFontDropdown:SetEnabled(combatTimerDB.useCustomFont == true)
        end
        y = y - FORM_ROW

        -- Backdrop settings
        local backdropCheck = GUI:CreateFormCheckbox(tabContent, "Show Backdrop", "showBackdrop", combatTimerDB, function(val)
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        backdropCheck:SetPoint("TOPLEFT", PADDING, y)
        backdropCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local backdropColorPicker = GUI:CreateFormColorPicker(tabContent, "Backdrop Color", "backdropColor", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        backdropColorPicker:SetPoint("TOPLEFT", PADDING, y)
        backdropColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Border settings
        -- Normalize mutually exclusive flags on load (prefer class color)
        if combatTimerDB.useClassColorBorder and combatTimerDB.useAccentColorBorder then
            combatTimerDB.useAccentColorBorder = false
        end

        local borderSizeSlider, borderTextureDropdown, useClassColorCheck, useAccentColorCheck, borderColorPicker

        local function UpdateBorderControlsEnabled(enabled)
            if borderSizeSlider and borderSizeSlider.SetEnabled then borderSizeSlider:SetEnabled(enabled) end
            if borderTextureDropdown and borderTextureDropdown.SetEnabled then borderTextureDropdown:SetEnabled(enabled) end
            if useClassColorCheck and useClassColorCheck.SetEnabled then useClassColorCheck:SetEnabled(enabled) end
            if useAccentColorCheck and useAccentColorCheck.SetEnabled then useAccentColorCheck:SetEnabled(enabled) end
            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(enabled and not combatTimerDB.useClassColorBorder and not combatTimerDB.useAccentColorBorder)
            end
        end

        local hideBorderCheck = GUI:CreateFormCheckbox(tabContent, "Hide Border", "hideBorder", combatTimerDB, function(val)
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
            UpdateBorderControlsEnabled(not val)
        end)
        hideBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        hideBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        borderSizeSlider = GUI:CreateFormSlider(tabContent, "Border Size", 1, 5, 0.5, "borderSize", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        borderSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        borderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local borderList = Shared.GetBorderList()
        borderTextureDropdown = GUI:CreateFormDropdown(tabContent, "Border Texture", borderList, "borderTexture", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        borderTextureDropdown:SetPoint("TOPLEFT", PADDING, y)
        borderTextureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        useClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Border", "useClassColorBorder", combatTimerDB, function(val)
            if val then
                combatTimerDB.useAccentColorBorder = false
                if useAccentColorCheck and useAccentColorCheck.SetValue then useAccentColorCheck:SetValue(false, true) end
            end
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(not val and not combatTimerDB.useAccentColorBorder and not combatTimerDB.hideBorder)
            end
        end)
        useClassColorCheck:SetPoint("TOPLEFT", PADDING, y)
        useClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        useAccentColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Accent Color for Border", "useAccentColorBorder", combatTimerDB, function(val)
            if val then
                combatTimerDB.useClassColorBorder = false
                if useClassColorCheck and useClassColorCheck.SetValue then useClassColorCheck:SetValue(false, true) end
            end
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(not val and not combatTimerDB.useClassColorBorder and not combatTimerDB.hideBorder)
            end
        end)
        useAccentColorCheck:SetPoint("TOPLEFT", PADDING, y)
        useAccentColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColor", combatTimerDB, function()
            if _G.QUI_RefreshCombatTimer then _G.QUI_RefreshCombatTimer() end
        end)
        borderColorPicker:SetPoint("TOPLEFT", PADDING, y)
        borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Apply initial border control states
        UpdateBorderControlsEnabled(not combatTimerDB.hideBorder)
    end

    y = y - 10

    -- Action Tracker Section
    GUI:SetSearchSection("Action Tracker")
    local actionTrackerHeader = GUI:CreateSectionHeader(tabContent, "Action Tracker")
    actionTrackerHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - actionTrackerHeader.gap

    local actionTrackerDesc = GUI:CreateLabel(tabContent,
        "Shows your recent casts as an animated icon bar, including optional failed/interrupted attempts.",
        11, C.textMuted)
    actionTrackerDesc:SetPoint("TOPLEFT", PADDING, y)
    actionTrackerDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    actionTrackerDesc:SetJustifyH("LEFT")
    actionTrackerDesc:SetWordWrap(true)
    actionTrackerDesc:SetHeight(15)
    y = y - 25

    local actionGeneralDB = db and db.general
    if actionGeneralDB then
        if type(actionGeneralDB.actionTracker) ~= "table" then
            actionGeneralDB.actionTracker = {}
        end
        local actionTrackerDB = actionGeneralDB.actionTracker

        if actionTrackerDB.enabled == nil then actionTrackerDB.enabled = false end
        if actionTrackerDB.onlyInCombat == nil then actionTrackerDB.onlyInCombat = true end
        if actionTrackerDB.clearOnCombatEnd == nil then actionTrackerDB.clearOnCombatEnd = true end
        if actionTrackerDB.inactivityFadeEnabled == nil then actionTrackerDB.inactivityFadeEnabled = false end
        if actionTrackerDB.inactivityFadeSeconds == nil then actionTrackerDB.inactivityFadeSeconds = 20 end
        if actionTrackerDB.clearOnInactivity == nil then actionTrackerDB.clearOnInactivity = false end
        if actionTrackerDB.showFailedCasts == nil then actionTrackerDB.showFailedCasts = true end
        if actionTrackerDB.maxEntries == nil then actionTrackerDB.maxEntries = 6 end
        if actionTrackerDB.iconSize == nil then actionTrackerDB.iconSize = 28 end
        if actionTrackerDB.iconSpacing == nil then actionTrackerDB.iconSpacing = 4 end
        if actionTrackerDB.iconHideBorder == nil then actionTrackerDB.iconHideBorder = false end
        if actionTrackerDB.iconBorderUseClassColor == nil then actionTrackerDB.iconBorderUseClassColor = false end
        if actionTrackerDB.iconBorderColor == nil then actionTrackerDB.iconBorderColor = {0, 0, 0, 0.85} end
        if actionTrackerDB.orientation == nil then actionTrackerDB.orientation = "VERTICAL" end
        if actionTrackerDB.invertScrollDirection == nil then actionTrackerDB.invertScrollDirection = false end
        if actionTrackerDB.showBackdrop == nil then actionTrackerDB.showBackdrop = true end
        if actionTrackerDB.hideBorder == nil then actionTrackerDB.hideBorder = false end
        if actionTrackerDB.borderSize == nil then actionTrackerDB.borderSize = 1 end
        if actionTrackerDB.backdropColor == nil then actionTrackerDB.backdropColor = {0, 0, 0, 0.6} end
        if actionTrackerDB.borderColor == nil then actionTrackerDB.borderColor = {0, 0, 0, 1} end
        if actionTrackerDB.xOffset == nil then actionTrackerDB.xOffset = 0 end
        if actionTrackerDB.yOffset == nil then actionTrackerDB.yOffset = -210 end
        if actionTrackerDB.blocklistText == nil then actionTrackerDB.blocklistText = "" end

        local actionPreviewActive = false
        local actionPreviewBtn

        local function RefreshActionTracker()
            if _G.QUI_RefreshActionTracker then
                _G.QUI_RefreshActionTracker()
            end
        end

        local function UpdateActionPreviewButtonState()
            if not actionPreviewBtn then
                return
            end
            local enabled = actionTrackerDB.enabled == true
            if actionPreviewBtn.SetEnabled then
                actionPreviewBtn:SetEnabled(enabled)
            end
            actionPreviewBtn:SetAlpha(enabled and 1 or 0.5)
            if not enabled then
                actionPreviewActive = false
                actionPreviewBtn:SetText("Show Preview")
            end
        end

        local actionEnabledCheck = GUI:CreateFormCheckbox(tabContent, "Enable Action Tracker", "enabled", actionTrackerDB, function()
            if not actionTrackerDB.enabled and actionPreviewActive then
                actionPreviewActive = false
                if _G.QUI_ToggleActionTrackerPreview then
                    _G.QUI_ToggleActionTrackerPreview(false)
                end
                if actionPreviewBtn then
                    actionPreviewBtn:SetText("Show Preview")
                end
            end
            RefreshActionTracker()
            UpdateActionPreviewButtonState()
        end)
        actionEnabledCheck:SetPoint("TOPLEFT", PADDING, y)
        actionEnabledCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local onlyCombatCheck = GUI:CreateFormCheckbox(tabContent, "Only Show In Combat", "onlyInCombat", actionTrackerDB, RefreshActionTracker)
        onlyCombatCheck:SetPoint("TOPLEFT", PADDING, y)
        onlyCombatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local clearOnEndCheck = GUI:CreateFormCheckbox(tabContent, "Clear History On Combat End", "clearOnCombatEnd", actionTrackerDB, RefreshActionTracker)
        clearOnEndCheck:SetPoint("TOPLEFT", PADDING, y)
        clearOnEndCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local inactivitySlider
        local clearOnInactivityCheck
        local inactivityCheck = GUI:CreateFormCheckbox(tabContent, "Enable Inactivity Fade-Out", "inactivityFadeEnabled", actionTrackerDB, function()
            if inactivitySlider and inactivitySlider.SetEnabled then
                inactivitySlider:SetEnabled(actionTrackerDB.inactivityFadeEnabled == true)
            end
            if clearOnInactivityCheck and clearOnInactivityCheck.SetEnabled then
                clearOnInactivityCheck:SetEnabled(actionTrackerDB.inactivityFadeEnabled == true)
            end
            RefreshActionTracker()
        end)
        inactivityCheck:SetPoint("TOPLEFT", PADDING, y)
        inactivityCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        inactivitySlider = GUI:CreateFormSlider(tabContent, "Inactivity Timeout (sec)", 10, 60, 1, "inactivityFadeSeconds", actionTrackerDB, RefreshActionTracker)
        inactivitySlider:SetPoint("TOPLEFT", PADDING, y)
        inactivitySlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if inactivitySlider.SetEnabled then
            inactivitySlider:SetEnabled(actionTrackerDB.inactivityFadeEnabled == true)
        end
        y = y - FORM_ROW

        clearOnInactivityCheck = GUI:CreateFormCheckbox(tabContent, "Clear History After Inactivity", "clearOnInactivity", actionTrackerDB, RefreshActionTracker)
        clearOnInactivityCheck:SetPoint("TOPLEFT", PADDING, y)
        clearOnInactivityCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if clearOnInactivityCheck.SetEnabled then
            clearOnInactivityCheck:SetEnabled(actionTrackerDB.inactivityFadeEnabled == true)
        end
        y = y - FORM_ROW

        local showFailedCheck = GUI:CreateFormCheckbox(tabContent, "Show Failed/Interrupted Casts", "showFailedCasts", actionTrackerDB, RefreshActionTracker)
        showFailedCheck:SetPoint("TOPLEFT", PADDING, y)
        showFailedCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local maxEntriesSlider = GUI:CreateFormSlider(tabContent, "Max Entries", 3, 10, 1, "maxEntries", actionTrackerDB, RefreshActionTracker)
        maxEntriesSlider:SetPoint("TOPLEFT", PADDING, y)
        maxEntriesSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local iconSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 16, 64, 1, "iconSize", actionTrackerDB, RefreshActionTracker)
        iconSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        iconSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local iconSpacingSlider = GUI:CreateFormSlider(tabContent, "Icon Spacing", 0, 24, 1, "iconSpacing", actionTrackerDB, RefreshActionTracker)
        iconSpacingSlider:SetPoint("TOPLEFT", PADDING, y)
        iconSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local iconBorderColorPicker
        local iconUseClassBorderCheck
        local function UpdateIconBorderControls()
            local borderEnabled = actionTrackerDB.iconHideBorder ~= true
            if iconUseClassBorderCheck and iconUseClassBorderCheck.SetEnabled then
                iconUseClassBorderCheck:SetEnabled(borderEnabled)
            end
            if iconBorderColorPicker and iconBorderColorPicker.SetEnabled then
                iconBorderColorPicker:SetEnabled(borderEnabled and actionTrackerDB.iconBorderUseClassColor ~= true)
            end
        end

        local iconHideBorderCheck = GUI:CreateFormCheckbox(tabContent, "Hide Icon Borders", "iconHideBorder", actionTrackerDB, function()
            UpdateIconBorderControls()
            RefreshActionTracker()
        end)
        iconHideBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        iconHideBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        iconUseClassBorderCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Icon Borders", "iconBorderUseClassColor", actionTrackerDB, function()
            UpdateIconBorderControls()
            RefreshActionTracker()
        end)
        iconUseClassBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        iconUseClassBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        iconBorderColorPicker = GUI:CreateFormColorPicker(tabContent, "Icon Border Color", "iconBorderColor", actionTrackerDB, RefreshActionTracker)
        iconBorderColorPicker:SetPoint("TOPLEFT", PADDING, y)
        iconBorderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        UpdateIconBorderControls()

        local orientationOptions = {
            { value = "VERTICAL", text = "Vertical" },
            { value = "HORIZONTAL", text = "Horizontal" },
        }
        local orientationDropdown = GUI:CreateFormDropdown(tabContent, "Bar Orientation", orientationOptions, "orientation", actionTrackerDB, RefreshActionTracker)
        orientationDropdown:SetPoint("TOPLEFT", PADDING, y)
        orientationDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local invertDirectionCheck = GUI:CreateFormCheckbox(tabContent, "Invert Scroll Direction", "invertScrollDirection", actionTrackerDB, RefreshActionTracker)
        invertDirectionCheck:SetPoint("TOPLEFT", PADDING, y)
        invertDirectionCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local backdropColorPicker
        local backdropCheck = GUI:CreateFormCheckbox(tabContent, "Show Container Background", "showBackdrop", actionTrackerDB, function()
            if backdropColorPicker and backdropColorPicker.SetEnabled then
                backdropColorPicker:SetEnabled(actionTrackerDB.showBackdrop == true)
            end
            RefreshActionTracker()
        end)
        backdropCheck:SetPoint("TOPLEFT", PADDING, y)
        backdropCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        backdropColorPicker = GUI:CreateFormColorPicker(tabContent, "Container Background Color", "backdropColor", actionTrackerDB, RefreshActionTracker)
        backdropColorPicker:SetPoint("TOPLEFT", PADDING, y)
        backdropColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if backdropColorPicker.SetEnabled then
            backdropColorPicker:SetEnabled(actionTrackerDB.showBackdrop == true)
        end
        y = y - FORM_ROW

        local borderColorPicker
        local borderSizeSlider
        local hideBorderCheck = GUI:CreateFormCheckbox(tabContent, "Hide Container Border", "hideBorder", actionTrackerDB, function()
            local enabled = actionTrackerDB.hideBorder ~= true
            if borderSizeSlider and borderSizeSlider.SetEnabled then
                borderSizeSlider:SetEnabled(enabled)
            end
            if borderColorPicker and borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(enabled)
            end
            RefreshActionTracker()
        end)
        hideBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        hideBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        borderSizeSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 5, 0.5, "borderSize", actionTrackerDB, RefreshActionTracker)
        borderSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        borderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if borderSizeSlider.SetEnabled then
            borderSizeSlider:SetEnabled(actionTrackerDB.hideBorder ~= true)
        end
        y = y - FORM_ROW

        borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Container Border Color", "borderColor", actionTrackerDB, RefreshActionTracker)
        borderColorPicker:SetPoint("TOPLEFT", PADDING, y)
        borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if borderColorPicker.SetEnabled then
            borderColorPicker:SetEnabled(actionTrackerDB.hideBorder ~= true)
        end
        y = y - FORM_ROW

        local actionXOffsetSlider = GUI:CreateFormSlider(tabContent, "X Position Offset", -2000, 2000, 1, "xOffset", actionTrackerDB, RefreshActionTracker)
        actionXOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        actionXOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local actionYOffsetSlider = GUI:CreateFormSlider(tabContent, "Y Position Offset", -2000, 2000, 1, "yOffset", actionTrackerDB, RefreshActionTracker)
        actionYOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        actionYOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local blocklistContainer = CreateFrame("Frame", nil, tabContent)
        blocklistContainer:SetHeight(FORM_ROW)
        blocklistContainer:SetPoint("TOPLEFT", PADDING, y)
        blocklistContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)

        local blocklistLabel = blocklistContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        blocklistLabel:SetPoint("LEFT", 0, 0)
        blocklistLabel:SetText("Spell Blocklist IDs")
        blocklistLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local blocklistBg = CreateFrame("Frame", nil, blocklistContainer, "BackdropTemplate")
        blocklistBg:SetPoint("LEFT", blocklistContainer, "LEFT", 180, 0)
        blocklistBg:SetPoint("RIGHT", blocklistContainer, "RIGHT", 0, 0)
        blocklistBg:SetHeight(24)
        local pxBlock = 1
        if QUICore and type(QUICore.GetPixelSize) == "function" then
            pxBlock = QUICore:GetPixelSize(blocklistBg)
        end
        blocklistBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxBlock,
        })
        blocklistBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        blocklistBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        local blocklistInput = CreateFrame("EditBox", nil, blocklistBg)
        blocklistInput:SetPoint("LEFT", 8, 0)
        blocklistInput:SetPoint("RIGHT", -8, 0)
        blocklistInput:SetHeight(22)
        blocklistInput:SetAutoFocus(false)
        blocklistInput:SetMaxLetters(300)
        blocklistInput:SetFont(GUI.FONT_PATH, 11, "")
        blocklistInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        blocklistInput:SetText(actionTrackerDB.blocklistText or "")

        local blocklistPlaceholder = blocklistBg:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        blocklistPlaceholder:SetPoint("LEFT", blocklistInput, "LEFT", 0, 0)
        blocklistPlaceholder:SetText("Example: 61304, 75, 133")
        blocklistPlaceholder:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7)
        blocklistPlaceholder:SetShown((actionTrackerDB.blocklistText or "") == "")

        blocklistInput:SetScript("OnEscapePressed", function(self)
            self:SetText(actionTrackerDB.blocklistText or "")
            self:ClearFocus()
            blocklistPlaceholder:SetShown((actionTrackerDB.blocklistText or "") == "")
        end)
        blocklistInput:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        blocklistInput:SetScript("OnEditFocusGained", function(self)
            blocklistBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self:HighlightText()
        end)
        blocklistInput:SetScript("OnEditFocusLost", function()
            blocklistBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end)
        blocklistInput:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local value = self:GetText() or ""
            actionTrackerDB.blocklistText = value
            blocklistPlaceholder:SetShown(value == "")
            RefreshActionTracker()
        end)
        y = y - FORM_ROW

        local blocklistHelp = GUI:CreateLabel(tabContent,
            "Comma-separated spell IDs to ignore in the tracker.",
            11, C.textMuted)
        blocklistHelp:SetPoint("TOPLEFT", PADDING, y + 4)
        blocklistHelp:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        blocklistHelp:SetJustifyH("LEFT")
        blocklistHelp:SetWordWrap(true)
        blocklistHelp:SetHeight(16)
        y = y - 22

        actionPreviewBtn = GUI:CreateButton(tabContent, "Show Preview", 140, 24)
        actionPreviewBtn:SetPoint("TOPLEFT", PADDING, y)
        actionPreviewBtn:SetScript("OnClick", function(self)
            if actionTrackerDB.enabled ~= true then
                actionPreviewActive = false
                if _G.QUI_ToggleActionTrackerPreview then
                    _G.QUI_ToggleActionTrackerPreview(false)
                end
                self:SetText("Show Preview")
                return
            end

            actionPreviewActive = not actionPreviewActive
            if _G.QUI_ToggleActionTrackerPreview then
                _G.QUI_ToggleActionTrackerPreview(actionPreviewActive)
            end
            if _G.QUI_IsActionTrackerPreviewMode then
                actionPreviewActive = _G.QUI_IsActionTrackerPreviewMode() == true
            end
            self:SetText(actionPreviewActive and "Hide Preview" or "Show Preview")
        end)
        UpdateActionPreviewButtonState()
        y = y - 32

        local existingOnHideActionTracker = tabContent:GetScript("OnHide")
        tabContent:SetScript("OnHide", function(self)
            if actionPreviewActive and _G.QUI_ToggleActionTrackerPreview then
                _G.QUI_ToggleActionTrackerPreview(false)
                actionPreviewActive = false
                if actionPreviewBtn then
                    actionPreviewBtn:SetText("Show Preview")
                end
            end
            if existingOnHideActionTracker then existingOnHideActionTracker(self) end
        end)
    end

    y = y - 10

    -- QoL Automation Section
    GUI:SetSearchSection("Automation")
    local autoHeader = GUI:CreateSectionHeader(tabContent, "Automation")
    autoHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - autoHeader.gap

    local autoDesc = GUI:CreateLabel(tabContent,
        "Toggle quality-of-life automation features. These run silently in the background.",
        11, C.textMuted)
    autoDesc:SetPoint("TOPLEFT", PADDING, y)
    autoDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    autoDesc:SetJustifyH("LEFT")
    autoDesc:SetWordWrap(true)
    autoDesc:SetHeight(15)
    y = y - 25

    local generalDB = db and db.general
    if generalDB then
        -- Sell Junk
        local sellJunkCheck = GUI:CreateFormCheckbox(tabContent, "Sell Junk Items at Vendors", "sellJunk", generalDB)
        sellJunkCheck:SetPoint("TOPLEFT", PADDING, y)
        sellJunkCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Repair
        local repairOptions = {
            {value = "off", text = "Off"},
            {value = "personal", text = "Personal Gold"},
            {value = "guild", text = "Guild Bank (fallback to personal)"},
        }
        local autoRepairDropdown = GUI:CreateFormDropdown(tabContent, "Auto Repair at Vendors", repairOptions, "autoRepair", generalDB)
        autoRepairDropdown:SetPoint("TOPLEFT", PADDING, y)
        autoRepairDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Fast Auto Loot
        local fastLootCheck = GUI:CreateFormCheckbox(tabContent, "Fast Auto Loot", "fastAutoLoot", generalDB)
        fastLootCheck:SetPoint("TOPLEFT", PADDING, y)
        fastLootCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Accept Party Invites
        local inviteOptions = {
            {value = "off", text = "Off"},
            {value = "all", text = "Everyone"},
            {value = "friends", text = "Friends & BNet Only"},
            {value = "guild", text = "Guild Members Only"},
            {value = "both", text = "Friends & Guild"},
        }
        local autoInviteDropdown = GUI:CreateFormDropdown(tabContent, "Auto Accept Party Invites", inviteOptions, "autoAcceptInvites", generalDB)
        autoInviteDropdown:SetPoint("TOPLEFT", PADDING, y)
        autoInviteDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Role Accept
        local autoRoleCheck = GUI:CreateFormCheckbox(tabContent, "Auto Accept Role Check", "autoRoleAccept", generalDB)
        autoRoleCheck:SetPoint("TOPLEFT", PADDING, y)
        autoRoleCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Accept Quests
        local autoQuestCheck = GUI:CreateFormCheckbox(tabContent, "Auto Accept Quests", "autoAcceptQuest", generalDB)
        autoQuestCheck:SetPoint("TOPLEFT", PADDING, y)
        autoQuestCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Turn-In Quests
        local autoTurnInCheck = GUI:CreateFormCheckbox(tabContent, "Auto Turn-In Quests", "autoTurnInQuest", generalDB)
        autoTurnInCheck:SetPoint("TOPLEFT", PADDING, y)
        autoTurnInCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Select Gossip
        local autoGossipCheck = GUI:CreateFormCheckbox(tabContent, "Auto Select Single Gossip Option", "autoSelectGossip", generalDB)
        autoGossipCheck:SetPoint("TOPLEFT", PADDING, y)
        autoGossipCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Hold Shift to Pause
        local shiftPauseCheck = GUI:CreateFormCheckbox(tabContent, "Hold Shift to Pause Quest/Gossip Automation", "questHoldShift", generalDB)
        shiftPauseCheck:SetPoint("TOPLEFT", PADDING, y)
        shiftPauseCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Insert M+ Keys
        local autoInsertKeyCheck = GUI:CreateFormCheckbox(tabContent, "Auto Insert M+ Keys", "autoInsertKey", generalDB)
        autoInsertKeyCheck:SetPoint("TOPLEFT", PADDING, y)
        autoInsertKeyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Combat Log in M+
        local autoCombatLogCheck = GUI:CreateFormCheckbox(tabContent, "Auto Combat Log in M+", "autoCombatLog", generalDB)
        autoCombatLogCheck:SetPoint("TOPLEFT", PADDING, y)
        autoCombatLogCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Combat Log in Raids
        local autoCombatLogRaidCheck = GUI:CreateFormCheckbox(tabContent, "Auto Combat Log in Raids", "autoCombatLogRaid", generalDB)
        autoCombatLogRaidCheck:SetPoint("TOPLEFT", PADDING, y)
        autoCombatLogRaidCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- M+ Dungeon Teleport
        local mplusTeleportCheck = GUI:CreateFormCheckbox(tabContent, "Click-to-Teleport on M+ Tab", "mplusTeleportEnabled", generalDB)
        mplusTeleportCheck:SetPoint("TOPLEFT", PADDING, y)
        mplusTeleportCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Auto Delete Confirmation
        local autoDeleteCheck = GUI:CreateFormCheckbox(tabContent, "Auto-Fill DELETE Confirmation Text", "autoDeleteConfirm", generalDB)
        autoDeleteCheck:SetPoint("TOPLEFT", PADDING, y)
        autoDeleteCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    y = y - 10

    -- Popup & Toast Blocker Section
    GUI:SetSearchSection("Popup Blocker")
    local popupBlockHeader = GUI:CreateSectionHeader(tabContent, "Popup & Toast Blocker")
    popupBlockHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - popupBlockHeader.gap

    local popupBlockDesc = GUI:CreateLabel(tabContent,
        "Block selected Blizzard popups, toasts, and reminder alerts (including talent reminders and collection toasts).",
        11, C.textMuted)
    popupBlockDesc:SetPoint("TOPLEFT", PADDING, y)
    popupBlockDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    popupBlockDesc:SetJustifyH("LEFT")
    popupBlockDesc:SetWordWrap(true)
    popupBlockDesc:SetHeight(20)
    y = y - 30

    if generalDB then
        if type(generalDB.popupBlocker) ~= "table" then
            generalDB.popupBlocker = {}
        end

        local popupDB = generalDB.popupBlocker

        local function RefreshPopupBlocker()
            if _G.QUI_RefreshPopupBlocker then
                _G.QUI_RefreshPopupBlocker()
            end
        end

        local popupToggleWidgets = {}
        local popupSearchKeywords = {
            enabled = {
                "popup blocker",
                "toast blocker",
                "block popups",
                "block toasts",
                "disable popups",
            },
            blockTalentMicroButtonAlerts = {
                "unspent talent",
                "talent reminder",
                "microbutton alert",
                "player spells",
                "spellbook alert",
            },
            blockEventToasts = {
                "event toast",
                "campaign toast",
                "housing toast",
                "blizzard news toast",
            },
            blockMountAlerts = {
                "new mount",
                "mount toast",
                "wrapped mount",
                "unwrapped mount",
            },
            blockPetAlerts = {
                "new pet",
                "pet toast",
                "companion pet",
            },
            blockToyAlerts = {
                "new toy",
                "toy toast",
                "toy box",
            },
            blockCosmeticAlerts = {
                "new cosmetic",
                "cosmetic toast",
                "appearance unlock",
            },
            blockWarbandSceneAlerts = {
                "warband scene",
                "warband toast",
                "housing scene",
            },
            blockEntitlementAlerts = {
                "entitlement",
                "raf",
                "recruit a friend",
                "delivery toast",
            },
            blockStaticTalentPopups = {
                "talent popup",
                "trait popup",
                "static popup talent",
            },
            blockStaticHousingPopups = {
                "housing popup",
                "homestead popup",
                "static popup housing",
            },
        }

        local function GetSearchRegistryInfo(key)
            local keywords = popupSearchKeywords[key]
            if not keywords then return nil end
            return { keywords = keywords }
        end

        local function UpdatePopupToggleState()
            local enabled = popupDB.enabled == true
            for _, widget in ipairs(popupToggleWidgets) do
                if widget and widget.SetEnabled then
                    widget:SetEnabled(enabled)
                end
            end
        end

        local popupEnableCheck = GUI:CreateFormCheckbox(
            tabContent,
            "Enable Popup/Toast Blocker",
            "enabled",
            popupDB,
            function()
                UpdatePopupToggleState()
                RefreshPopupBlocker()
            end,
            GetSearchRegistryInfo("enabled")
        )
        popupEnableCheck:SetPoint("TOPLEFT", PADDING, y)
        popupEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local function AddPopupToggle(label, key)
            local check = GUI:CreateFormCheckbox(
                tabContent,
                label,
                key,
                popupDB,
                RefreshPopupBlocker,
                GetSearchRegistryInfo(key)
            )
            check:SetPoint("TOPLEFT", PADDING, y)
            check:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
            y = y - FORM_ROW
            table.insert(popupToggleWidgets, check)
        end

        AddPopupToggle("Block Talent Reminder Alerts (Microbutton)", "blockTalentMicroButtonAlerts")
        AddPopupToggle("Block Event Toasts (often campaign/housing)", "blockEventToasts")
        AddPopupToggle("Block New Mount Toasts", "blockMountAlerts")
        AddPopupToggle("Block New Pet Toasts", "blockPetAlerts")
        AddPopupToggle("Block New Toy Toasts", "blockToyAlerts")
        AddPopupToggle("Block New Cosmetic Toasts", "blockCosmeticAlerts")
        AddPopupToggle("Block Warband Scene Toasts", "blockWarbandSceneAlerts")
        AddPopupToggle("Block Entitlement/RAF Delivery Toasts", "blockEntitlementAlerts")
        AddPopupToggle("Block Talent-Related Static Popups", "blockStaticTalentPopups")
        AddPopupToggle("Block Housing-Related Static Popups", "blockStaticHousingPopups")

        UpdatePopupToggleState()
    end

    y = y - 10

    -- Quick Salvage Section
    GUI:SetSearchSection("Quick Salvage")
    local quickSalvageHeader = GUI:CreateSectionHeader(tabContent, "Quick Salvage")
    quickSalvageHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - quickSalvageHeader.gap

    local quickSalvageDesc = GUI:CreateLabel(tabContent,
        "Mill, prospect, or disenchant items with a single click using a modifier key. Requires the corresponding profession.",
        11, C.textMuted)
    quickSalvageDesc:SetPoint("TOPLEFT", PADDING, y)
    quickSalvageDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    quickSalvageDesc:SetJustifyH("LEFT")
    quickSalvageDesc:SetWordWrap(true)
    quickSalvageDesc:SetHeight(20)
    y = y - 30

    local qsDB = db and db.general and db.general.quickSalvage
    if qsDB then
        local qsEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Quick Salvage", "enabled", qsDB, function()
            if _G.QUI_RefreshQuickSalvage then _G.QUI_RefreshQuickSalvage() end
        end)
        qsEnableCheck:SetPoint("TOPLEFT", PADDING, y)
        qsEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local modifierOptions = {
            {value = "ALT", text = "Alt"},
            {value = "ALTCTRL", text = "Alt + Ctrl"},
            {value = "ALTSHIFT", text = "Alt + Shift"},
        }
        local qsModifierDropdown = GUI:CreateFormDropdown(tabContent, "Modifier Key", modifierOptions, "modifier", qsDB, function()
            if _G.QUI_RefreshQuickSalvage then _G.QUI_RefreshQuickSalvage() end
        end)
        qsModifierDropdown:SetPoint("TOPLEFT", PADDING, y)
        qsModifierDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local qsActionsDesc = GUI:CreateLabel(tabContent,
            "Milling: Herbs (5+ stack)  |  Prospecting: Ores (5+ stack)  |  Disenchanting: Green+ gear",
            11, C.textMuted)
        qsActionsDesc:SetPoint("TOPLEFT", PADDING, y)
        qsActionsDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        qsActionsDesc:SetJustifyH("LEFT")
        qsActionsDesc:SetWordWrap(true)
        qsActionsDesc:SetHeight(20)
        y = y - 30
    end

    y = y - 10

    -- Pet Warning Section
    GUI:SetSearchSection("Pet Warning")
    local petWarningHeader = GUI:CreateSectionHeader(tabContent, "Pet Warning")
    petWarningHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - petWarningHeader.gap

    local petWarningIntro = GUI:CreateLabel(tabContent, "Warn pet class players (Hunter, Warlock, DK, Frost Mage) when pet is missing or on passive during combat in instances.", 11, C.textMuted)
    petWarningIntro:SetPoint("TOPLEFT", PADDING, y)
    petWarningIntro:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    petWarningIntro:SetJustifyH("LEFT")
    petWarningIntro:SetWordWrap(true)
    petWarningIntro:SetHeight(20)
    y = y - 30

    if generalDB then
        local petCombatCheck = GUI:CreateFormCheckbox(tabContent, "Show Combat Warning in Instances", "petCombatWarning", generalDB, function()
            if _G.QUI_RefreshPetWarning then
                _G.QUI_RefreshPetWarning()
            elseif _G.QUI_RepositionPetWarning then
                _G.QUI_RepositionPetWarning()
            end
        end)
        petCombatCheck:SetPoint("TOPLEFT", PADDING, y)
        petCombatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local petOffsetXSlider = GUI:CreateFormSlider(tabContent, "Horizontal Offset", -500, 500, 10, "petWarningOffsetX", generalDB, function()
            if _G.QUI_RepositionPetWarning then _G.QUI_RepositionPetWarning() end
        end)
        petOffsetXSlider:SetPoint("TOPLEFT", PADDING, y)
        petOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local petOffsetYSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -500, 500, 10, "petWarningOffsetY", generalDB, function()
            if _G.QUI_RepositionPetWarning then _G.QUI_RepositionPetWarning() end
        end)
        petOffsetYSlider:SetPoint("TOPLEFT", PADDING, y)
        petOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Preview toggle button
        local petPreviewActive = false
        local petPreviewBtn = GUI:CreateButton(tabContent, "Show Preview", 140, 24)
        petPreviewBtn:SetPoint("TOPLEFT", PADDING, y)
        petPreviewBtn:SetScript("OnClick", function(self)
            petPreviewActive = not petPreviewActive
            if _G.QUI_TogglePetWarningPreview then
                _G.QUI_TogglePetWarningPreview(petPreviewActive)
            end
            self:SetText(petPreviewActive and "Hide Preview" or "Show Preview")
        end)

        -- Hide preview when leaving this tab
        local existingOnHide = tabContent:GetScript("OnHide")
        tabContent:SetScript("OnHide", function(self)
            if petPreviewActive and _G.QUI_TogglePetWarningPreview then
                _G.QUI_TogglePetWarningPreview(false)
                petPreviewActive = false
                petPreviewBtn:SetText("Show Preview")
            end
            if existingOnHide then existingOnHide(self) end
        end)
        y = y - 32
    end

    y = y - 10

    -- Focus Cast Alert Section
    GUI:SetSearchSection("Focus Cast Alert")
    local focusCastHeader = GUI:CreateSectionHeader(tabContent, "Focus Cast Alert")
    focusCastHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - focusCastHeader.gap

    local focusCastIntro = GUI:CreateLabel(
        tabContent,
        "Shows customizable text when your hostile focus starts casting and your interrupt is ready.",
        11,
        C.textMuted
    )
    focusCastIntro:SetPoint("TOPLEFT", PADDING, y)
    focusCastIntro:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    focusCastIntro:SetJustifyH("LEFT")
    focusCastIntro:SetWordWrap(true)
    focusCastIntro:SetHeight(20)
    y = y - 30

    if generalDB then
        -- Ensure the table exists; GetSettings() in focuscastalert.lua
        -- backfills missing keys from DEFAULT_SETTINGS on first access.
        if type(generalDB.focusCastAlert) ~= "table" then
            generalDB.focusCastAlert = {}
        end
        local focusAlertDB = generalDB.focusCastAlert

        local function RefreshFocusCastAlert()
            if _G.QUI_RefreshFocusCastAlert then
                _G.QUI_RefreshFocusCastAlert()
            end
        end

        local focusPreviewActive = false
        local focusPreviewBtn -- forward declared, created below

        local focusEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Focus Cast Alert", "enabled", focusAlertDB, function()
            -- Reset preview when disabling.
            if not focusAlertDB.enabled and focusPreviewActive then
                focusPreviewActive = false
                if _G.QUI_ToggleFocusCastAlertPreview then
                    _G.QUI_ToggleFocusCastAlertPreview(false)
                end
                if focusPreviewBtn then
                    focusPreviewBtn:SetText("Show Preview")
                end
            end
            RefreshFocusCastAlert()
        end)
        focusEnableCheck:SetPoint("TOPLEFT", PADDING, y)
        focusEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local textContainer = CreateFrame("Frame", nil, tabContent)
        textContainer:SetHeight(FORM_ROW)
        textContainer:SetPoint("TOPLEFT", PADDING, y)
        textContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)

        local textLabel = textContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        textLabel:SetPoint("LEFT", 0, 0)
        textLabel:SetText("Alert Text")
        textLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local textInputBg = CreateFrame("Frame", nil, textContainer, "BackdropTemplate")
        textInputBg:SetPoint("LEFT", textContainer, "LEFT", 180, 0)
        textInputBg:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
        textInputBg:SetHeight(24)
        local pxText = 1
        if QUICore and type(QUICore.GetPixelSize) == "function" then
            pxText = QUICore:GetPixelSize(textInputBg)
        end
        textInputBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = pxText,
        })
        textInputBg:SetBackdropColor(0.08, 0.08, 0.08, 1)
        textInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        local textInput = CreateFrame("EditBox", nil, textInputBg)
        textInput:SetPoint("LEFT", 8, 0)
        textInput:SetPoint("RIGHT", -8, 0)
        textInput:SetHeight(22)
        textInput:SetAutoFocus(false)
        textInput:SetMaxLetters(200)
        textInput:SetFont(GUI.FONT_PATH, 11, "")
        textInput:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        textInput:SetText(focusAlertDB.text or "")

        local textPlaceholder = textInputBg:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        textPlaceholder:SetPoint("LEFT", textInput, "LEFT", 0, 0)
        textPlaceholder:SetText("Example: {unit} is casting {spell}. Kick!")
        textPlaceholder:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.7)
        textPlaceholder:SetShown((focusAlertDB.text or "") == "")

        textInput:SetScript("OnEscapePressed", function(self)
            self:SetText(focusAlertDB.text or "")
            self:ClearFocus()
            textPlaceholder:SetShown((focusAlertDB.text or "") == "")
        end)
        textInput:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        textInput:SetScript("OnEditFocusGained", function(self)
            textInputBg:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self:HighlightText()
        end)
        textInput:SetScript("OnEditFocusLost", function()
            textInputBg:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        end)
        textInput:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local value = self:GetText() or ""
            focusAlertDB.text = value
            textPlaceholder:SetShown(value == "")
            RefreshFocusCastAlert()
        end)
        y = y - FORM_ROW

        local placeholderHelp = GUI:CreateLabel(
            tabContent,
            "Use {unit} for the target's name and {spell} for the spell being cast.",
            11,
            C.textMuted
        )
        placeholderHelp:SetPoint("TOPLEFT", PADDING, y + 4)
        placeholderHelp:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        placeholderHelp:SetJustifyH("LEFT")
        placeholderHelp:SetWordWrap(true)
        placeholderHelp:SetHeight(20)
        y = y - 26

        local focusAnchorOptions = {
            {value = "screen", text = "Screen Center"},
            {value = "essential", text = "CDM Essentials"},
            {value = "focus", text = "Focus Target"},
        }
        local focusAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Anchor", focusAnchorOptions, "anchorTo", focusAlertDB, RefreshFocusCastAlert)
        focusAnchorDropdown:SetPoint("TOPLEFT", PADDING, y)
        focusAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local focusOffsetX = GUI:CreateFormSlider(tabContent, "X Offset", -300, 300, 1, "offsetX", focusAlertDB, RefreshFocusCastAlert)
        focusOffsetX:SetPoint("TOPLEFT", PADDING, y)
        focusOffsetX:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local focusOffsetY = GUI:CreateFormSlider(tabContent, "Y Offset", -300, 300, 1, "offsetY", focusAlertDB, RefreshFocusCastAlert)
        focusOffsetY:SetPoint("TOPLEFT", PADDING, y)
        focusOffsetY:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local focusFontOptions = {
            {value = "", text = "Global QUI Font"},
        }
        local fontList = Shared.GetFontList()
        for _, fontOption in ipairs(fontList) do
            table.insert(focusFontOptions, fontOption)
        end
        local focusFontDropdown = GUI:CreateFormDropdown(tabContent, "Font", focusFontOptions, "font", focusAlertDB, RefreshFocusCastAlert)
        focusFontDropdown:SetPoint("TOPLEFT", PADDING, y)
        focusFontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local focusFontSize = GUI:CreateFormSlider(tabContent, "Font Size", 8, 72, 1, "fontSize", focusAlertDB, RefreshFocusCastAlert)
        focusFontSize:SetPoint("TOPLEFT", PADDING, y)
        focusFontSize:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local focusOutlineOptions = {
            {value = "", text = "None"},
            {value = "OUTLINE", text = "Outline"},
            {value = "THICKOUTLINE", text = "Thick Outline"},
        }
        local focusOutlineDropdown = GUI:CreateFormDropdown(tabContent, "Font Outline", focusOutlineOptions, "fontOutline", focusAlertDB, RefreshFocusCastAlert)
        focusOutlineDropdown:SetPoint("TOPLEFT", PADDING, y)
        focusOutlineDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local focusColorPicker
        local useClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", focusAlertDB, function()
            if focusColorPicker and focusColorPicker.SetEnabled then
                focusColorPicker:SetEnabled(not focusAlertDB.useClassColor)
            end
            RefreshFocusCastAlert()
        end)
        useClassColorCheck:SetPoint("TOPLEFT", PADDING, y)
        useClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        focusColorPicker = GUI:CreateFormColorPicker(tabContent, "Text Color", "textColor", focusAlertDB, RefreshFocusCastAlert)
        focusColorPicker:SetPoint("TOPLEFT", PADDING, y)
        focusColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if focusColorPicker.SetEnabled then
            focusColorPicker:SetEnabled(not focusAlertDB.useClassColor)
        end
        y = y - FORM_ROW

        focusPreviewBtn = GUI:CreateButton(tabContent, "Show Preview", 140, 24)
        focusPreviewBtn:SetPoint("TOPLEFT", PADDING, y)
        focusPreviewBtn:SetScript("OnClick", function(self)
            focusPreviewActive = not focusPreviewActive
            if _G.QUI_ToggleFocusCastAlertPreview then
                _G.QUI_ToggleFocusCastAlertPreview(focusPreviewActive)
            end
            self:SetText(focusPreviewActive and "Hide Preview" or "Show Preview")
        end)

        local existingOnHideFocus = tabContent:GetScript("OnHide")
        tabContent:SetScript("OnHide", function(self)
            if focusPreviewActive and _G.QUI_ToggleFocusCastAlertPreview then
                _G.QUI_ToggleFocusCastAlertPreview(false)
                focusPreviewActive = false
                focusPreviewBtn:SetText("Show Preview")
            end
            if existingOnHideFocus then existingOnHideFocus(self) end
        end)
        y = y - 32
    end

    y = y - 10

    -- Consumable Check Section
    GUI:SetSearchSection("Consumable Check")
    local consumableHeader = GUI:CreateSectionHeader(tabContent, "Consumable Check")
    consumableHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - consumableHeader.gap

    local consumableDesc = GUI:CreateLabel(tabContent,
        "Display consumable status icons when triggered by events below. Left-click missing icons to use your preferred item; right-click in ready check to choose a different item.",
        11, C.textMuted)
    consumableDesc:SetPoint("TOPLEFT", PADDING, y)
    consumableDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    consumableDesc:SetJustifyH("LEFT")
    consumableDesc:SetWordWrap(true)
    consumableDesc:SetHeight(20)
    y = y - 30

    if generalDB then
        local consumableEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Consumable Check", "consumableCheckEnabled", generalDB)
        consumableEnableCheck:SetPoint("TOPLEFT", PADDING, y)
        consumableEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Triggers sub-header
        local triggersLabel = GUI:CreateLabel(tabContent, "Triggers", 12, C.accent)
        triggersLabel:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20

        local triggerReadyCheck = GUI:CreateFormCheckbox(tabContent, "Ready Check", "consumableOnReadyCheck", generalDB)
        triggerReadyCheck:SetPoint("TOPLEFT", PADDING + 20, y)
        triggerReadyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local triggerDungeon = GUI:CreateFormCheckbox(tabContent, "Dungeon Entrance", "consumableOnDungeon", generalDB)
        triggerDungeon:SetPoint("TOPLEFT", PADDING + 20, y)
        triggerDungeon:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local triggerRaid = GUI:CreateFormCheckbox(tabContent, "Raid Entrance", "consumableOnRaid", generalDB)
        triggerRaid:SetPoint("TOPLEFT", PADDING + 20, y)
        triggerRaid:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local triggerResurrect = GUI:CreateFormCheckbox(tabContent, "Instanced Resurrect", "consumableOnResurrect", generalDB)
        triggerResurrect:SetPoint("TOPLEFT", PADDING + 20, y)
        triggerResurrect:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Buff Checks sub-header
        local buffsLabel = GUI:CreateLabel(tabContent, "Buff Checks", 12, C.accent)
        buffsLabel:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20

        local consumableFoodCheck = GUI:CreateFormCheckbox(tabContent, "Food Buff", "consumableFood", generalDB)
        consumableFoodCheck:SetPoint("TOPLEFT", PADDING + 20, y)
        consumableFoodCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local consumableFlaskCheck = GUI:CreateFormCheckbox(tabContent, "Flask Buff", "consumableFlask", generalDB)
        consumableFlaskCheck:SetPoint("TOPLEFT", PADDING + 20, y)
        consumableFlaskCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local consumableOilMHCheck = GUI:CreateFormCheckbox(tabContent, "Weapon Oil (Main Hand)", "consumableOilMH", generalDB)
        consumableOilMHCheck:SetPoint("TOPLEFT", PADDING + 20, y)
        consumableOilMHCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local consumableOilOHCheck = GUI:CreateFormCheckbox(tabContent, "Weapon Oil (Off Hand)", "consumableOilOH", generalDB)
        consumableOilOHCheck:SetPoint("TOPLEFT", PADDING + 20, y)
        consumableOilOHCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local consumableRuneCheck = GUI:CreateFormCheckbox(tabContent, "Augment Rune", "consumableRune", generalDB)
        consumableRuneCheck:SetPoint("TOPLEFT", PADDING + 20, y)
        consumableRuneCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local consumableHSCheck = GUI:CreateFormCheckbox(tabContent, "Healthstones", "consumableHealthstone", generalDB)
        consumableHSCheck:SetPoint("TOPLEFT", PADDING + 20, y)
        consumableHSCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local consumableHSDesc = GUI:CreateLabel(tabContent, "Only shows when a Warlock is in the group.", 11, C.textMuted)
        consumableHSDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        consumableHSDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        consumableHSDesc:SetJustifyH("LEFT")
        y = y - 20

        -- Expiration Warning sub-header
        local expirationLabel = GUI:CreateLabel(tabContent, "Expiration Warning", 12, C.accent)
        expirationLabel:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20

        local expirationCheck = GUI:CreateFormCheckbox(tabContent, "Warn When Buffs Expiring", "consumableExpirationWarning", generalDB)
        expirationCheck:SetPoint("TOPLEFT", PADDING, y)
        expirationCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local expirationDesc = GUI:CreateLabel(tabContent, "Show consumables window when food/flask/rune is about to expire (instanced content only).", 11, C.textMuted)
        expirationDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        expirationDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        expirationDesc:SetJustifyH("LEFT")
        expirationDesc:SetWordWrap(true)
        expirationDesc:SetHeight(20)
        y = y - 30

        local thresholdSlider = GUI:CreateFormSlider(tabContent, "Warning Threshold (seconds)", 60, 600, 30, "consumableExpirationThreshold", generalDB)
        thresholdSlider:SetPoint("TOPLEFT", PADDING, y)
        thresholdSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Positioning sub-header
        local positionLabel = GUI:CreateLabel(tabContent, "Positioning", 12, C.accent)
        positionLabel:SetPoint("TOPLEFT", PADDING, y)
        y = y - 20

        local function RefreshConsumables()
            if _G.QUI_RefreshConsumables then _G.QUI_RefreshConsumables() end
        end

        local function RepositionConsumables()
            if _G.QUI_RepositionConsumables then _G.QUI_RepositionConsumables() end
        end

        -- Forward declare for callback reference
        local iconOffsetSlider

        local anchorModeCheck = GUI:CreateFormCheckbox(tabContent, "Anchor to Ready Check", "consumableAnchorMode", generalDB, function()
            if iconOffsetSlider then
                iconOffsetSlider:SetEnabled(generalDB.consumableAnchorMode)
            end
            RepositionConsumables()
        end)
        anchorModeCheck:SetPoint("TOPLEFT", PADDING, y)
        anchorModeCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local anchorDesc = GUI:CreateLabel(tabContent, "When off, use 'Toggle Mover' to freely position the frame.", 11, C.textMuted)
        anchorDesc:SetPoint("TOPLEFT", PADDING, y + 4)
        anchorDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        anchorDesc:SetJustifyH("LEFT")
        y = y - 20

        local moverButton = GUI:CreateButton(tabContent, "Toggle Mover", 140, 24)
        moverButton:SetPoint("TOPLEFT", PADDING, y)
        moverButton:SetScript("OnClick", function()
            if _G.QUI_ToggleConsumablesMover then _G.QUI_ToggleConsumablesMover() end
        end)
        y = y - 32

        iconOffsetSlider = GUI:CreateFormSlider(tabContent, "Icon Offset", -10, 30, 1, "consumableIconOffset", generalDB, RepositionConsumables)
        iconOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        iconOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        iconOffsetSlider:SetEnabled(generalDB.consumableAnchorMode)
        y = y - FORM_ROW

        local iconSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 24, 64, 2, "consumableIconSize", generalDB, RefreshConsumables)
        iconSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        iconSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local scaleSlider = GUI:CreateFormSlider(tabContent, "Scale", 0.5, 3, 0.05, "consumableScale", generalDB, RefreshConsumables)
        scaleSlider:SetPoint("TOPLEFT", PADDING, y)
        scaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Show/hide preview buttons
        local consumablePreviewActive = false
        local consumablePreviewBtn = GUI:CreateButton(tabContent, "Show Preview", 140, 24)
        consumablePreviewBtn:SetPoint("TOPLEFT", PADDING, y)
        consumablePreviewBtn:SetScript("OnClick", function(self)
            consumablePreviewActive = not consumablePreviewActive
            if consumablePreviewActive then
                if _G.QUI_ShowConsumables then _G.QUI_ShowConsumables() end
            else
                if _G.QUI_HideConsumables then _G.QUI_HideConsumables() end
            end
            self:SetText(consumablePreviewActive and "Hide Preview" or "Show Preview")
        end)

        -- Clean up preview when leaving tab
        local existingOnHideConsumable = tabContent:GetScript("OnHide")
        tabContent:SetScript("OnHide", function(self)
            if consumablePreviewActive and _G.QUI_HideConsumables then
                _G.QUI_HideConsumables()
                consumablePreviewActive = false
                consumablePreviewBtn:SetText("Show Preview")
            end
            if existingOnHideConsumable then existingOnHideConsumable(self) end
        end)
        y = y - 32
    end

    y = y - 10

    -- Battle Res Counter Section
    GUI:SetSearchSection("Battle Res Counter")
    local brzHeader = GUI:CreateSectionHeader(tabContent, "Battle Res Counter")
    brzHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - brzHeader.gap

    local brzDesc = GUI:CreateLabel(tabContent,
        "Displays battle res charges and cooldown timer in raids and M+ dungeons.",
        11, C.textMuted)
    brzDesc:SetPoint("TOPLEFT", PADDING, y)
    brzDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    brzDesc:SetJustifyH("LEFT")
    brzDesc:SetWordWrap(true)
    brzDesc:SetHeight(15)
    y = y - 25

    local brzDB = db and db.brzCounter
    if brzDB then
        local brzEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Battle Res Counter", "enabled", brzDB, function(val)
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzEnableCheck:SetPoint("TOPLEFT", PADDING, y)
        brzEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Preview toggle
        local brzPreviewState = { enabled = _G.QUI_IsBrezCounterPreviewMode and _G.QUI_IsBrezCounterPreviewMode() or false }
        local brzPreviewCheck = GUI:CreateFormCheckbox(tabContent, "Preview Battle Res Counter", "enabled", brzPreviewState, function(val)
            if _G.QUI_ToggleBrezCounterPreview then
                _G.QUI_ToggleBrezCounterPreview(val)
            end
        end)
        brzPreviewCheck:SetPoint("TOPLEFT", PADDING, y)
        brzPreviewCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Lock toggle
        local brzLockCheck = GUI:CreateFormCheckbox(tabContent, "Lock Frame", "locked", brzDB, function(val)
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzLockCheck:SetPoint("TOPLEFT", PADDING, y)
        brzLockCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Frame size settings
        local brzWidthSlider = GUI:CreateFormSlider(tabContent, "Frame Width", 30, 100, 1, "width", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzWidthSlider:SetPoint("TOPLEFT", PADDING, y)
        brzWidthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzHeightSlider = GUI:CreateFormSlider(tabContent, "Frame Height", 30, 100, 1, "height", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzHeightSlider:SetPoint("TOPLEFT", PADDING, y)
        brzHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzFontSizeSlider = GUI:CreateFormSlider(tabContent, "Charges Font Size", 10, 28, 1, "fontSize", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzFontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        brzFontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzTimerFontSlider = GUI:CreateFormSlider(tabContent, "Timer Font Size", 8, 24, 1, "timerFontSize", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzTimerFontSlider:SetPoint("TOPLEFT", PADDING, y)
        brzTimerFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzXOffsetSlider = GUI:CreateFormSlider(tabContent, "X Position Offset", -2000, 2000, 1, "xOffset", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzXOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        brzXOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzYOffsetSlider = GUI:CreateFormSlider(tabContent, "Y Position Offset", -2000, 2000, 1, "yOffset", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzYOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        brzYOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Color pickers
        local brzHasChargesColor = GUI:CreateFormColorPicker(tabContent, "Charges Available Color", "hasChargesColor", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzHasChargesColor:SetPoint("TOPLEFT", PADDING, y)
        brzHasChargesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzNoChargesColor = GUI:CreateFormColorPicker(tabContent, "No Charges Color", "noChargesColor", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzNoChargesColor:SetPoint("TOPLEFT", PADDING, y)
        brzNoChargesColor:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Timer text color with class color toggle
        local brzTimerColorPicker  -- Forward declare

        local brzUseClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Timer Text", "useClassColorText", brzDB, function(val)
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
            if brzTimerColorPicker and brzTimerColorPicker.SetEnabled then
                brzTimerColorPicker:SetEnabled(not val)
            end
        end)
        brzUseClassColorCheck:SetPoint("TOPLEFT", PADDING, y)
        brzUseClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        brzTimerColorPicker = GUI:CreateFormColorPicker(tabContent, "Timer Text Color", "timerColor", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzTimerColorPicker:SetPoint("TOPLEFT", PADDING, y)
        brzTimerColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if brzTimerColorPicker.SetEnabled then
            brzTimerColorPicker:SetEnabled(not brzDB.useClassColorText)
        end
        y = y - FORM_ROW

        -- Font selection with custom toggle
        local brzFontList = Shared.GetFontList()
        local brzFontDropdown  -- Forward declare

        local brzUseCustomFontCheck = GUI:CreateFormCheckbox(tabContent, "Use Custom Font", "useCustomFont", brzDB, function(val)
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
            if brzFontDropdown and brzFontDropdown.SetEnabled then
                brzFontDropdown:SetEnabled(val)
            end
        end)
        brzUseCustomFontCheck:SetPoint("TOPLEFT", PADDING, y)
        brzUseCustomFontCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        brzFontDropdown = GUI:CreateFormDropdown(tabContent, "Font", brzFontList, "font", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzFontDropdown:SetPoint("TOPLEFT", PADDING, y)
        brzFontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        if brzFontDropdown.SetEnabled then
            brzFontDropdown:SetEnabled(brzDB.useCustomFont == true)
        end
        y = y - FORM_ROW

        -- Backdrop settings
        local brzBackdropCheck = GUI:CreateFormCheckbox(tabContent, "Show Backdrop", "showBackdrop", brzDB, function(val)
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzBackdropCheck:SetPoint("TOPLEFT", PADDING, y)
        brzBackdropCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzBackdropColor = GUI:CreateFormColorPicker(tabContent, "Backdrop Color", "backdropColor", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzBackdropColor:SetPoint("TOPLEFT", PADDING, y)
        brzBackdropColor:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Border settings
        -- Normalize mutually exclusive flags on load (prefer class color)
        if brzDB.useClassColorBorder and brzDB.useAccentColorBorder then
            brzDB.useAccentColorBorder = false
        end

        local brzBorderSizeSlider, brzBorderTextureDropdown, brzUseClassBorderCheck, brzUseAccentBorderCheck, brzBorderColorPicker

        local function UpdateBrzBorderControlsEnabled(enabled)
            if brzBorderSizeSlider and brzBorderSizeSlider.SetEnabled then brzBorderSizeSlider:SetEnabled(enabled) end
            if brzBorderTextureDropdown and brzBorderTextureDropdown.SetEnabled then brzBorderTextureDropdown:SetEnabled(enabled) end
            if brzUseClassBorderCheck and brzUseClassBorderCheck.SetEnabled then brzUseClassBorderCheck:SetEnabled(enabled) end
            if brzUseAccentBorderCheck and brzUseAccentBorderCheck.SetEnabled then brzUseAccentBorderCheck:SetEnabled(enabled) end
            if brzBorderColorPicker and brzBorderColorPicker.SetEnabled then
                brzBorderColorPicker:SetEnabled(enabled and not brzDB.useClassColorBorder and not brzDB.useAccentColorBorder)
            end
        end

        local brzHideBorderCheck = GUI:CreateFormCheckbox(tabContent, "Hide Border", "hideBorder", brzDB, function(val)
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
            UpdateBrzBorderControlsEnabled(not val)
        end)
        brzHideBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        brzHideBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        brzBorderSizeSlider = GUI:CreateFormSlider(tabContent, "Border Size", 1, 5, 0.5, "borderSize", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzBorderSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        brzBorderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local brzBorderList = Shared.GetBorderList()
        brzBorderTextureDropdown = GUI:CreateFormDropdown(tabContent, "Border Texture", brzBorderList, "borderTexture", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzBorderTextureDropdown:SetPoint("TOPLEFT", PADDING, y)
        brzBorderTextureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        brzUseClassBorderCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Border", "useClassColorBorder", brzDB, function(val)
            if val then
                brzDB.useAccentColorBorder = false
                if brzUseAccentBorderCheck and brzUseAccentBorderCheck.SetValue then brzUseAccentBorderCheck:SetValue(false, true) end
            end
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
            if brzBorderColorPicker and brzBorderColorPicker.SetEnabled then
                brzBorderColorPicker:SetEnabled(not val and not brzDB.useAccentColorBorder and not brzDB.hideBorder)
            end
        end)
        brzUseClassBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        brzUseClassBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        brzUseAccentBorderCheck = GUI:CreateFormCheckbox(tabContent, "Use Accent Color for Border", "useAccentColorBorder", brzDB, function(val)
            if val then
                brzDB.useClassColorBorder = false
                if brzUseClassBorderCheck and brzUseClassBorderCheck.SetValue then brzUseClassBorderCheck:SetValue(false, true) end
            end
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
            if brzBorderColorPicker and brzBorderColorPicker.SetEnabled then
                brzBorderColorPicker:SetEnabled(not val and not brzDB.useClassColorBorder and not brzDB.hideBorder)
            end
        end)
        brzUseAccentBorderCheck:SetPoint("TOPLEFT", PADDING, y)
        brzUseAccentBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        brzBorderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "borderColor", brzDB, function()
            if _G.QUI_RefreshBrezCounter then _G.QUI_RefreshBrezCounter() end
        end)
        brzBorderColorPicker:SetPoint("TOPLEFT", PADDING, y)
        brzBorderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        -- Apply initial border control states
        UpdateBrzBorderControlsEnabled(not brzDB.hideBorder)
    end

    y = y - 10

    -- Target Distance Bracket Display Section
    GUI:SetSearchSection("Target Distance Bracket Display")
    local rangeHeader = GUI:CreateSectionHeader(tabContent, "Target Distance Bracket Display")
    rangeHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - rangeHeader.gap

    local rangeCheckDB = db and db.rangeCheck
    if rangeCheckDB then
        local dynamicColorCheck
        local classColorCheck
        local textColorPicker

        local function RefreshRangeControls()
            if rangeCheckDB.dynamicColor and rangeCheckDB.useClassColor then
                rangeCheckDB.useClassColor = false
                if classColorCheck and classColorCheck.SetValue then
                    classColorCheck:SetValue(false, true)
                end
            end
            if dynamicColorCheck and dynamicColorCheck.SetEnabled then
                dynamicColorCheck:SetEnabled(true)
            end
            if classColorCheck and classColorCheck.SetEnabled then
                classColorCheck:SetEnabled(not rangeCheckDB.dynamicColor)
            end
            if textColorPicker and textColorPicker.SetEnabled then
                textColorPicker:SetEnabled(not rangeCheckDB.dynamicColor and not rangeCheckDB.useClassColor)
            end
        end

        local rangeEnableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Distance Bracket Display", "enabled", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        rangeEnableCheck:SetPoint("TOPLEFT", PADDING, y)
        rangeEnableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local previewState = { enabled = _G.QUI_IsRangeCheckPreviewMode and _G.QUI_IsRangeCheckPreviewMode() or false }
        local previewCheck = GUI:CreateFormCheckbox(tabContent, "Preview / Move Frame", "enabled", previewState, function(val)
            if _G.QUI_ToggleRangeCheckPreview then
                _G.QUI_ToggleRangeCheckPreview(val)
            end
        end)
        previewCheck:SetPoint("TOPLEFT", PADDING, y)
        previewCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local combatOnlyCheck = GUI:CreateFormCheckbox(tabContent, "Combat Only", "combatOnly", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        combatOnlyCheck:SetPoint("TOPLEFT", PADDING, y)
        combatOnlyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local targetOnlyCheck = GUI:CreateFormCheckbox(tabContent, "Only Show With Hostile Target", "showOnlyWithTarget", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        targetOnlyCheck:SetPoint("TOPLEFT", PADDING, y)
        targetOnlyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local shortenTextCheck = GUI:CreateFormCheckbox(tabContent, "Shorten Text", "shortenText", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        shortenTextCheck:SetPoint("TOPLEFT", PADDING, y)
        shortenTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        dynamicColorCheck = GUI:CreateFormCheckbox(tabContent, "Dynamic Color (by distance bracket)", "dynamicColor", rangeCheckDB, function(val)
            if val then
                rangeCheckDB.useClassColor = false
                if classColorCheck and classColorCheck.SetValue then
                    classColorCheck:SetValue(false, true)
                end
            end
            Shared.RefreshRangeCheck()
            RefreshRangeControls()
        end)
        dynamicColorCheck:SetPoint("TOPLEFT", PADDING, y)
        dynamicColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
            RefreshRangeControls()
        end)
        classColorCheck:SetPoint("TOPLEFT", PADDING, y)
        classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        if not rangeCheckDB.textColor then
            rangeCheckDB.textColor = { 0.2, 0.95, 0.55, 1 }
        end
        textColorPicker = GUI:CreateFormColorPicker(tabContent, "Text Color", "textColor", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        textColorPicker:SetPoint("TOPLEFT", PADDING, y)
        textColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local fontList = Shared.GetFontList()
        local fontDropdown = GUI:CreateFormDropdown(tabContent, "Font", fontList, "font", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        fontDropdown:SetPoint("TOPLEFT", PADDING, y)
        fontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local fontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 48, 1, "fontSize", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        fontSizeSlider:SetPoint("TOPLEFT", PADDING, y)
        fontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local strataOptions = {
            {value = "BACKGROUND", text = "Background"},
            {value = "LOW", text = "Low"},
            {value = "MEDIUM", text = "Medium"},
            {value = "HIGH", text = "High"},
            {value = "DIALOG", text = "Dialog"},
        }
        local strataDropdown = GUI:CreateFormDropdown(tabContent, "Frame Strata", strataOptions, "strata", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        strataDropdown:SetPoint("TOPLEFT", PADDING, y)
        strataDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local xOffsetSlider = GUI:CreateFormSlider(tabContent, "X-Offset", -700, 700, 1, "offsetX", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        xOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        xOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW

        local yOffsetSlider = GUI:CreateFormSlider(tabContent, "Y-Offset", -700, 700, 1, "offsetY", rangeCheckDB, function()
            Shared.RefreshRangeCheck()
        end)
        yOffsetSlider:SetPoint("TOPLEFT", PADDING, y)
        yOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - 30

        RefreshRangeControls()
    end

    y = y - 10

    -- QUI Panel Settings
    local panelHeader = GUI:CreateSectionHeader(tabContent, "QUI Panel Settings")
    panelHeader:SetPoint("TOPLEFT", PADDING, y)
    y = y - panelHeader.gap

    local minimapBtnDB = db and db.minimapButton
    if minimapBtnDB then
        local showMinimapIconCheck = GUI:CreateFormCheckbox(tabContent, "Hide QUI Minimap Icon", "hide", minimapBtnDB, function(dbVal)
            local LibDBIcon = LibStub("LibDBIcon-1.0", true)
            if LibDBIcon then
                if dbVal then
                    LibDBIcon:Hide("QUI")
                else
                    LibDBIcon:Show("QUI")
                end
            end
        end)
        showMinimapIconCheck:SetPoint("TOPLEFT", PADDING, y)
        showMinimapIconCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
        y = y - FORM_ROW
    end

    local panelAlphaSlider = GUI:CreateFormSlider(tabContent, "QUI Panel Transparency", 0.3, 1.0, 0.01, "configPanelAlpha", db, function(val)
        local mainFrame = GUI.MainFrame
        if mainFrame then
            local bgColor = GUI.Colors.bg
            mainFrame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], val)
        end
    end)
    panelAlphaSlider:SetPoint("TOPLEFT", PADDING, y)
    panelAlphaSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PADDING, 0)
    y = y - FORM_ROW

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_QoLOptions = {
    BuildGeneralTab = BuildGeneralTab
}
