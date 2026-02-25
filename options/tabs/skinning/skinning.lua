--[[
    QUI Options - Skinning Tab
    BuildSkinningTab for Autohide & Skinning page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Import shared utilities
local Shared = ns.QUI_Options

local GetCore = ns.Helpers.GetCore

local function BuildSkinningTab(tabContent)
    local y = -10
    local PAD = 10
    local FORM_ROW = 32
    local db = Shared.GetDB()

    GUI:SetSearchContext({tabIndex = 7, tabName = "Skinning & Autohide", subTabIndex = 2, subTabName = "Skinning"})

    if db and db.general then
        local general = db.general

        -- Initialize defaults
        if general.skinUseClassColor == nil then general.skinUseClassColor = true end
        if general.addonAccentColor == nil then general.addonAccentColor = {0.204, 0.827, 0.6, 1} end
        if general.hideSkinBorders == nil then general.hideSkinBorders = false end
        if general.skinBorderUseClassColor == nil then general.skinBorderUseClassColor = false end
        if general.skinBorderColor == nil then
            local accent = general.addonAccentColor or {0.204, 0.827, 0.6, 1}
            general.skinBorderColor = { accent[1], accent[2], accent[3], accent[4] or 1 }
        end
        if general.skinKeystoneFrame == nil then general.skinKeystoneFrame = true end

        -- ═══════════════════════════════════════════════════════════════
        -- CHOOSE DEFAULT COLOR SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Choose Default Color")

        local colorHeader = GUI:CreateSectionHeader(tabContent, "Choose Default Color")
        colorHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - colorHeader.gap

        local customColorPicker  -- Forward declare for closure

        -- Helper to refresh all skinned frames when colors change
        local function RefreshAllSkinning()
            if _G.QUI_RefreshKeystoneColors then
                _G.QUI_RefreshKeystoneColors()
            end
            if _G.QUI_RefreshAlertColors then
                _G.QUI_RefreshAlertColors()
            end
            if _G.QUI_RefreshLootColors then
                _G.QUI_RefreshLootColors()
            end
            if _G.QUI_RefreshMPlusTimerColors then
                _G.QUI_RefreshMPlusTimerColors()
            end
            if _G.QUI_RefreshCharacterFrameColors then
                _G.QUI_RefreshCharacterFrameColors()
            end
            if _G.QUI_RefreshInspectColors then
                _G.QUI_RefreshInspectColors()
            end
            if _G.QUI_RefreshPowerBarAltColors then
                _G.QUI_RefreshPowerBarAltColors()
            end
            if _G.QUI_RefreshGameMenuColors then
                _G.QUI_RefreshGameMenuColors()
            end
            if _G.QUI_RefreshOverrideActionBarColors then
                _G.QUI_RefreshOverrideActionBarColors()
            end
            if _G.QUI_RefreshObjectiveTrackerColors then
                _G.QUI_RefreshObjectiveTrackerColors()
            end
            if _G.QUI_RefreshInstanceFramesColors then
                _G.QUI_RefreshInstanceFramesColors()
            end
            if _G.QUI_RefreshReadyCheckColors then
                _G.QUI_RefreshReadyCheckColors()
            end
        end

        local function EnsureBorderOverrideDefaults(settings, prefix)
            if type(settings) ~= "table" then return end
            local keyPrefix = type(prefix) == "string" and prefix or ""
            local overrideKey = keyPrefix ~= "" and (keyPrefix .. "BorderOverride") or "borderOverride"
            local hideKey = keyPrefix ~= "" and (keyPrefix .. "HideBorder") or "hideBorder"
            local useClassKey = keyPrefix ~= "" and (keyPrefix .. "BorderUseClassColor") or "borderUseClassColor"
            local colorKey = keyPrefix ~= "" and (keyPrefix .. "BorderColor") or "borderColor"

            if settings[overrideKey] == nil then settings[overrideKey] = false end
            if settings[hideKey] == nil then settings[hideKey] = false end
            if settings[useClassKey] == nil then settings[useClassKey] = false end
            if settings[colorKey] == nil then
                local fallback = general.skinBorderColor or general.addonAccentColor or { 0.204, 0.827, 0.6, 1 }
                settings[colorKey] = { fallback[1], fallback[2], fallback[3], fallback[4] or 1 }
            end
        end

        local function AddModuleBorderOverrideControls(title, settings, prefix)
            EnsureBorderOverrideDefaults(settings, prefix)

            local keyPrefix = type(prefix) == "string" and prefix or ""
            local overrideKey = keyPrefix ~= "" and (keyPrefix .. "BorderOverride") or "borderOverride"
            local hideKey = keyPrefix ~= "" and (keyPrefix .. "HideBorder") or "hideBorder"
            local useClassKey = keyPrefix ~= "" and (keyPrefix .. "BorderUseClassColor") or "borderUseClassColor"
            local colorKey = keyPrefix ~= "" and (keyPrefix .. "BorderColor") or "borderColor"

            local colorPicker
            local hideCheck
            local classCheck

            local function UpdateBorderControlState()
                local enabled = settings[overrideKey]
                if hideCheck then hideCheck:SetEnabled(enabled) end
                if classCheck then classCheck:SetEnabled(enabled) end
                if colorPicker then
                    colorPicker:SetEnabled(enabled and (not settings[useClassKey]))
                end
            end

            local overrideCheck = GUI:CreateFormCheckbox(tabContent, "Override Global Border Settings", overrideKey, settings, function()
                UpdateBorderControlState()
                RefreshAllSkinning()
            end)
            overrideCheck:SetPoint("TOPLEFT", PAD, y)
            overrideCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            hideCheck = GUI:CreateFormCheckbox(tabContent, "Hide Border", hideKey, settings, RefreshAllSkinning)
            hideCheck:SetPoint("TOPLEFT", PAD, y)
            hideCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            classCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Border", useClassKey, settings, function()
                UpdateBorderControlState()
                RefreshAllSkinning()
            end)
            classCheck:SetPoint("TOPLEFT", PAD, y)
            classCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            colorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", colorKey, settings, RefreshAllSkinning, { noAlpha = true })
            colorPicker:SetPoint("TOPLEFT", PAD, y)
            colorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            UpdateBorderControlState()
        end

        local function AddModuleBackgroundOverrideControls(title, settings, prefix)
            local keyPrefix = type(prefix) == "string" and prefix or ""
            local overrideKey = keyPrefix ~= "" and (keyPrefix .. "BgOverride") or "bgOverride"
            local hideKey = keyPrefix ~= "" and (keyPrefix .. "HideBackground") or "hideBackground"
            local colorKey = keyPrefix ~= "" and (keyPrefix .. "BackgroundColor") or "backgroundColor"

            local colorPicker
            local hideCheck

            local function UpdateBgControlState()
                local enabled = settings[overrideKey]
                if hideCheck then hideCheck:SetEnabled(enabled) end
                if colorPicker then
                    colorPicker:SetEnabled(enabled and (not settings[hideKey]))
                end
            end

            local overrideCheck = GUI:CreateFormCheckbox(tabContent, "Override Global Background Settings", overrideKey, settings, function()
                UpdateBgControlState()
                RefreshAllSkinning()
            end)
            overrideCheck:SetPoint("TOPLEFT", PAD, y)
            overrideCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            hideCheck = GUI:CreateFormCheckbox(tabContent, "Hide Background", hideKey, settings, function()
                UpdateBgControlState()
                RefreshAllSkinning()
            end)
            hideCheck:SetPoint("TOPLEFT", PAD, y)
            hideCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            colorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", colorKey, settings, RefreshAllSkinning)
            colorPicker:SetPoint("TOPLEFT", PAD, y)
            colorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            UpdateBgControlState()
        end

        local useClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Colors", "skinUseClassColor", general, function()
            if customColorPicker then
                customColorPicker:SetEnabled(not general.skinUseClassColor)
            end
            -- Update accent to match class color or custom color
            if general.skinUseClassColor then
                local _, class = UnitClass("player")
                local color = RAID_CLASS_COLORS[class]
                if color and GUI.ApplyAccentColor then
                    GUI:ApplyAccentColor(color.r, color.g, color.b)
                end
            else
                local c = general.addonAccentColor or {0.204, 0.827, 0.6, 1}
                if GUI.ApplyAccentColor then
                    GUI:ApplyAccentColor(c[1], c[2], c[3])
                end
            end
            RefreshAllSkinning()
            if GUI.RefreshAccentColor then
                GUI:RefreshAccentColor()
            end
        end)
        useClassColorCheck:SetPoint("TOPLEFT", PAD, y)
        useClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        customColorPicker = GUI:CreateFormColorPicker(tabContent, "Accent Color", "addonAccentColor", general, function(r, g, b, a)
            -- Sync the options panel theme with the new accent color
            if GUI.ApplyAccentColor then
                GUI:ApplyAccentColor(r, g, b)
            end
            RefreshAllSkinning()
            -- Schedule a panel rebuild when the color picker closes
            if not GUI._accentPickerWatcher then
                local watcher = CreateFrame("Frame")
                GUI._accentPickerWatcher = watcher
                watcher:SetScript("OnUpdate", function(self)
                    if not ColorPickerFrame:IsShown() then
                        self:SetScript("OnUpdate", nil)
                        GUI._accentPickerWatcher = nil
                        if GUI.RefreshAccentColor then
                            GUI:RefreshAccentColor()
                        end
                    end
                end)
            end
        end, { noAlpha = true })
        customColorPicker:SetPoint("TOPLEFT", PAD, y)
        customColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        customColorPicker:SetEnabled(not general.skinUseClassColor)  -- Initial state
        y = y - FORM_ROW

        y = y - 10  -- Extra padding before background color

        -- Background color (with alpha for transparency)
        if general.skinBgColor == nil then general.skinBgColor = { 0.05, 0.05, 0.05, 0.95 } end

        local bgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "skinBgColor", general, RefreshAllSkinning, { hasAlpha = true })
        bgColorPicker:SetPoint("TOPLEFT", PAD, y)
        bgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local hideSkinBordersCheck = GUI:CreateFormCheckbox(tabContent, "Hide Borders", "hideSkinBorders", general, RefreshAllSkinning)
        hideSkinBordersCheck:SetPoint("TOPLEFT", PAD, y)
        hideSkinBordersCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local skinBorderColorPicker

        local borderUseClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Borders", "skinBorderUseClassColor", general, function()
            if skinBorderColorPicker then
                skinBorderColorPicker:SetEnabled(not general.skinBorderUseClassColor)
            end
            RefreshAllSkinning()
        end)
        borderUseClassColorCheck:SetPoint("TOPLEFT", PAD, y)
        borderUseClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        skinBorderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "skinBorderColor", general, RefreshAllSkinning, { noAlpha = true })
        skinBorderColorPicker:SetPoint("TOPLEFT", PAD, y)
        skinBorderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        skinBorderColorPicker:SetEnabled(not general.skinBorderUseClassColor)
        y = y - FORM_ROW

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- GAME MENU SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Game Menu")

        if general.skinGameMenu == nil then general.skinGameMenu = false end
        if general.addQUIButton == nil then general.addQUIButton = false end
        if general.gameMenuFontSize == nil then general.gameMenuFontSize = 12 end

        local gameMenuHeader = GUI:CreateSectionHeader(tabContent, "Game Menu")
        gameMenuHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - gameMenuHeader.gap

        local gameMenuDesc = GUI:CreateLabel(tabContent, "Customize the ESC menu appearance and add a quick access button.", 11, C.textMuted)
        gameMenuDesc:SetPoint("TOPLEFT", PAD, y)
        gameMenuDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        gameMenuDesc:SetJustifyH("LEFT")
        gameMenuDesc:SetWordWrap(true)
        gameMenuDesc:SetHeight(20)
        y = y - 28

        local gameMenuCheck = GUI:CreateFormCheckbox(tabContent, "Skin Game Menu", "skinGameMenu", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        gameMenuCheck:SetPoint("TOPLEFT", PAD, y)
        gameMenuCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local addQUIButtonCheck = GUI:CreateFormCheckbox(tabContent, "Add QUI Button", "addQUIButton", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Button changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        addQUIButtonCheck:SetPoint("TOPLEFT", PAD, y)
        addQUIButtonCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local gameMenuFontSlider = GUI:CreateFormSlider(tabContent, "Button Font Size", 8, 18, 1, "gameMenuFontSize", general, function()
            if _G.QUI_RefreshGameMenuFontSize then
                _G.QUI_RefreshGameMenuFontSize()
            end
        end)
        gameMenuFontSlider:SetPoint("TOPLEFT", PAD, y)
        gameMenuFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.gameMenuDim == nil then general.gameMenuDim = true end
        local gameMenuDimCheck = GUI:CreateFormCheckbox(tabContent, "Dim Background", "gameMenuDim", general, function()
            if _G.QUI_RefreshGameMenuDim then
                _G.QUI_RefreshGameMenuDim()
            end
        end)
        gameMenuDimCheck:SetPoint("TOPLEFT", PAD, y)
        gameMenuDimCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Game Menu", general, "gameMenu")

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- READY CHECK FRAME SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Ready Check Frame")

        if general.skinReadyCheck == nil then general.skinReadyCheck = true end

        local readyCheckHeader = GUI:CreateSectionHeader(tabContent, "Ready Check Frame")
        readyCheckHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - readyCheckHeader.gap

        local readyCheckDesc = GUI:CreateLabel(tabContent, "Skin the ready check popup with QUI styling.", 11, C.textMuted)
        readyCheckDesc:SetPoint("TOPLEFT", PAD, y)
        readyCheckDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        readyCheckDesc:SetJustifyH("LEFT")
        readyCheckDesc:SetWordWrap(true)
        readyCheckDesc:SetHeight(20)
        y = y - 28

        local skinReadyCheckCheck = GUI:CreateFormCheckbox(tabContent, "Skin Ready Check Frame", "skinReadyCheck", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        skinReadyCheckCheck:SetPoint("TOPLEFT", PAD, y)
        skinReadyCheckCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Ready Check", general, "readyCheck")

        -- Move/Reset buttons for Ready Check frame position
        local rcMoveBtn = GUI:CreateButton(tabContent, "Toggle Mover", 140, 28, function()
            if _G.QUI_ToggleReadyCheckMover then
                _G.QUI_ToggleReadyCheckMover()
            end
        end)
        rcMoveBtn:SetPoint("TOPLEFT", PAD, y)

        local rcResetBtn = GUI:CreateButton(tabContent, "Reset Position", 140, 28, function()
            if _G.QUI_ResetReadyCheckPosition then
                _G.QUI_ResetReadyCheckPosition()
                print("|cFF56D1FF[QUI]|r Ready Check position reset to default.")
            end
        end)
        rcResetBtn:SetPoint("LEFT", rcMoveBtn, "RIGHT", 10, 0)
        y = y - 36

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- KEYSTONE FRAME SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Keystone Frame")

        local header = GUI:CreateSectionHeader(tabContent, "Keystone Frame")
        header:SetPoint("TOPLEFT", PAD, y)
        y = y - header.gap

        local desc = GUI:CreateLabel(tabContent, "Skin the M+ keystone insertion window with QUI styling.", 11, C.textMuted)
        desc:SetPoint("TOPLEFT", PAD, y)
        desc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetHeight(20)
        y = y - 28

        local skinCheck = GUI:CreateFormCheckbox(tabContent, "Skin Keystone Window", "skinKeystoneFrame", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        skinCheck:SetPoint("TOPLEFT", PAD, y)
        skinCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Keystone", general, "keystone")

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- ENCOUNTER POWER BAR SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Encounter Power Bar")

        if general.skinPowerBarAlt == nil then general.skinPowerBarAlt = true end

        local powerBarHeader = GUI:CreateSectionHeader(tabContent, "Encounter Power Bar")
        powerBarHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - powerBarHeader.gap

        local powerBarDesc = GUI:CreateLabel(tabContent, "Skin the encounter/quest-specific power bar (Atramedes sound, Darkmoon games, etc.).", 11, C.textMuted)
        powerBarDesc:SetPoint("TOPLEFT", PAD, y)
        powerBarDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        powerBarDesc:SetJustifyH("LEFT")
        powerBarDesc:SetWordWrap(true)
        powerBarDesc:SetHeight(20)
        y = y - 28

        local powerBarAltCheck = GUI:CreateFormCheckbox(tabContent, "Skin Encounter Power Bar", "skinPowerBarAlt", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        powerBarAltCheck:SetPoint("TOPLEFT", PAD, y)
        powerBarAltCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Encounter Power Bar", general, "powerBarAlt")

        local powerBarMoverBtn = GUI:CreateButton(tabContent, "Toggle Position Mover", 160, 28, function()
            if _G.QUI_TogglePowerBarAltMover then
                _G.QUI_TogglePowerBarAltMover()
            end
        end)
        powerBarMoverBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 36

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- ALERT FRAMES SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Alert Frames")

        if general.skinAlerts == nil then general.skinAlerts = true end

        local alertHeader = GUI:CreateSectionHeader(tabContent, "Alert Frames")
        alertHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - alertHeader.gap

        local alertDesc = GUI:CreateLabel(tabContent, "Style loot alerts, achievements, mounts, toys, and other popup frames.", 11, C.textMuted)
        alertDesc:SetPoint("TOPLEFT", PAD, y)
        alertDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        alertDesc:SetJustifyH("LEFT")
        alertDesc:SetWordWrap(true)
        alertDesc:SetHeight(20)
        y = y - 28

        local alertCheck = GUI:CreateFormCheckbox(tabContent, "Skin Alert Frames", "skinAlerts", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        alertCheck:SetPoint("TOPLEFT", PAD, y)
        alertCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Alert Frames", general, "alerts")

        -- Toggle movers button
        local moverBtn = GUI:CreateButton(tabContent, "Toggle Position Movers", 200, 28, function()
            local core = GetCore()
            if core and core.Alerts then
                core.Alerts:ToggleMovers()
            end
        end)
        moverBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 40

        local moverInfo = GUI:CreateLabel(tabContent, "Drag the mover frames to reposition alerts and toasts.", 10, C.textMuted)
        moverInfo:SetPoint("TOPLEFT", PAD, y)
        moverInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        moverInfo:SetJustifyH("LEFT")
        y = y - 25

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- LOOT WINDOW SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Loot Window")

        -- Get loot settings from profile root (not general)
        -- Ensure tables and individual keys exist
        if not db.loot then db.loot = {} end
        if db.loot.enabled == nil then db.loot.enabled = true end
        if db.loot.lootUnderMouse == nil then db.loot.lootUnderMouse = false end
        if db.loot.showTransmogMarker == nil then db.loot.showTransmogMarker = true end

        if not db.lootRoll then db.lootRoll = {} end
        if db.lootRoll.enabled == nil then db.lootRoll.enabled = false end
        if db.lootRoll.growDirection == nil then db.lootRoll.growDirection = "DOWN" end
        if db.lootRoll.spacing == nil then db.lootRoll.spacing = 4 end
        if db.lootRoll.maxFrames == nil then db.lootRoll.maxFrames = 4 end

        if not db.lootResults then db.lootResults = {} end
        if db.lootResults.enabled == nil then db.lootResults.enabled = true end

        local lootDB = db.loot
        local lootRollDB = db.lootRoll
        local lootResultsDB = db.lootResults

        local lootHeader = GUI:CreateSectionHeader(tabContent, "Loot Window")
        lootHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - lootHeader.gap

        local lootDesc = GUI:CreateLabel(tabContent, "Replace Blizzard's loot window with a custom QUI-styled frame.", 11, C.textMuted)
        lootDesc:SetPoint("TOPLEFT", PAD, y)
        lootDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        lootDesc:SetJustifyH("LEFT")
        lootDesc:SetWordWrap(true)
        lootDesc:SetHeight(20)
        y = y - 28

        local lootCheck = GUI:CreateFormCheckbox(tabContent, "Skin Loot Window", "enabled", lootDB, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        lootCheck:SetPoint("TOPLEFT", PAD, y)
        lootCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Loot Module", lootDB)

        local lootUnderMouseCheck = GUI:CreateFormCheckbox(tabContent, "Loot Under Mouse", "lootUnderMouse", lootDB)
        lootUnderMouseCheck:SetPoint("TOPLEFT", PAD, y)
        lootUnderMouseCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local transmogCheck = GUI:CreateFormCheckbox(tabContent, "Show Transmog Markers", "showTransmogMarker", lootDB)
        transmogCheck:SetPoint("TOPLEFT", PAD, y)
        transmogCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- ROLL FRAMES SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Roll Frames")

        local rollHeader = GUI:CreateSectionHeader(tabContent, "Roll Frames")
        rollHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - rollHeader.gap

        local rollDesc = GUI:CreateLabel(tabContent, "Replace Blizzard's loot roll frames with custom QUI-styled frames.", 11, C.textMuted)
        rollDesc:SetPoint("TOPLEFT", PAD, y)
        rollDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        rollDesc:SetJustifyH("LEFT")
        rollDesc:SetWordWrap(true)
        rollDesc:SetHeight(20)
        y = y - 28

        local rollCheck = GUI:CreateFormCheckbox(tabContent, "Skin Roll Frames", "enabled", lootRollDB, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        rollCheck:SetPoint("TOPLEFT", PAD, y)
        rollCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Helper to refresh roll preview live when settings change
        local function RefreshRollPreview()
            local core = GetCore()
            if core and core.Loot and core.Loot:IsRollPreviewActive() then
                core.Loot:HideRollPreview()
                core.Loot:ShowRollPreview()
            end
        end

        local growOptions = {
            { value = "DOWN", text = "Down" },
            { value = "UP", text = "Up" },
        }
        local growDropdown = GUI:CreateFormDropdown(tabContent, "Grow Direction", growOptions, "growDirection", lootRollDB, RefreshRollPreview)
        growDropdown:SetPoint("TOPLEFT", PAD, y)
        growDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local maxFramesSlider = GUI:CreateFormSlider(tabContent, "Max Visible Frames", 1, 8, 1, "maxFrames", lootRollDB, RefreshRollPreview)
        maxFramesSlider:SetPoint("TOPLEFT", PAD, y)
        maxFramesSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spacingSlider = GUI:CreateFormSlider(tabContent, "Frame Spacing", 0, 20, 1, "spacing", lootRollDB, RefreshRollPreview)
        spacingSlider:SetPoint("TOPLEFT", PAD, y)
        spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Toggle movers button
        local rollMoverBtn = GUI:CreateButton(tabContent, "Toggle Position Movers", 200, 28, function()
            local core = GetCore()
            if core and core.Loot then
                core.Loot:ToggleMovers()
            end
        end)
        rollMoverBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 40

        local rollMoverInfo = GUI:CreateLabel(tabContent, "Drag the mover frame to reposition roll frames. Shows preview rolls.", 10, C.textMuted)
        rollMoverInfo:SetPoint("TOPLEFT", PAD, y)
        rollMoverInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        rollMoverInfo:SetJustifyH("LEFT")
        y = y - 25

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- LOOT HISTORY SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Loot History")

        local historyHeader = GUI:CreateSectionHeader(tabContent, "Loot History")
        historyHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - historyHeader.gap

        local historyDesc = GUI:CreateLabel(tabContent, "Apply QUI styling to the loot roll results panel.", 11, C.textMuted)
        historyDesc:SetPoint("TOPLEFT", PAD, y)
        historyDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        historyDesc:SetJustifyH("LEFT")
        historyDesc:SetWordWrap(true)
        historyDesc:SetHeight(20)
        y = y - 28

        local historyCheck = GUI:CreateFormCheckbox(tabContent, "Skin Loot History", "enabled", lootResultsDB, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        historyCheck:SetPoint("TOPLEFT", PAD, y)
        historyCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- QUI M+ TIMER SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("QUI M+ Timer")

        local mplusTimer = db.mplusTimer
        if not mplusTimer then
            db.mplusTimer = {
                enabled = false,
                layoutMode = "full",
                showTimer = true,
                showBorder = true,
                showDeaths = true,
                showAffixes = true,
                showObjectives = true,
                scale = 1.0,
                forcesBarEnabled = true,
                forcesDisplayMode = "bar",
                forcesPosition = "after_timer",
                forcesTextFormat = "both",
                forcesLabel = "Forces",
                forcesFont = "Poppins",
                forcesFontSize = 11,
            }
            mplusTimer = db.mplusTimer
        end
        -- Ensure new fields exist for existing profiles
        if mplusTimer.layoutMode == nil then mplusTimer.layoutMode = "full" end
        if mplusTimer.showTimer == nil then mplusTimer.showTimer = true end
        if mplusTimer.showBorder == nil then mplusTimer.showBorder = true end
        if mplusTimer.scale == nil then mplusTimer.scale = 1.0 end
        if mplusTimer.borderOverride == nil then mplusTimer.borderOverride = false end
        if mplusTimer.hideBorder == nil then mplusTimer.hideBorder = false end
        if mplusTimer.borderUseClassColor == nil then mplusTimer.borderUseClassColor = false end
        if mplusTimer.borderColor == nil then
            local fallbackBorder = general.skinBorderColor or general.addonAccentColor or { 0.204, 0.827, 0.6, 1 }
            mplusTimer.borderColor = { fallbackBorder[1], fallbackBorder[2], fallbackBorder[3], fallbackBorder[4] or 1 }
        end
        if mplusTimer.bgOverride == nil then mplusTimer.bgOverride = false end
        if mplusTimer.hideBackground == nil then mplusTimer.hideBackground = false end
        if mplusTimer.backgroundColor == nil then
            local fallbackBg = general.skinBgColor or { 0.05, 0.05, 0.05, 0.95 }
            mplusTimer.backgroundColor = { fallbackBg[1], fallbackBg[2], fallbackBg[3], fallbackBg[4] or 0.95 }
        end
        if mplusTimer.forcesBarEnabled == nil then mplusTimer.forcesBarEnabled = true end
        if mplusTimer.forcesDisplayMode == nil then mplusTimer.forcesDisplayMode = "bar" end
        if mplusTimer.forcesPosition == nil then mplusTimer.forcesPosition = "after_timer" end
        if mplusTimer.forcesTextFormat == nil then mplusTimer.forcesTextFormat = "both" end
        if mplusTimer.forcesLabel == nil then mplusTimer.forcesLabel = "Forces" end
        if mplusTimer.forcesFont == nil then mplusTimer.forcesFont = "Poppins" end
        if mplusTimer.forcesFontSize == nil then mplusTimer.forcesFontSize = 11 end
        if mplusTimer.barUseClassColor == nil then mplusTimer.barUseClassColor = false end
        if mplusTimer.barColor == nil then
            local fallbackBar = general.skinBorderColor or general.addonAccentColor or { 0.204, 0.827, 0.6, 1 }
            mplusTimer.barColor = { fallbackBar[1], fallbackBar[2], fallbackBar[3], fallbackBar[4] or 1 }
        end
        if mplusTimer.maxDungeonNameLength == nil then mplusTimer.maxDungeonNameLength = 18 end

        local quiMplusHeader = GUI:CreateSectionHeader(tabContent, "QUI M+ Timer")
        quiMplusHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - quiMplusHeader.gap

        local quiMplusDesc = GUI:CreateLabel(tabContent, "Custom M+ timer with QUI styling. Replaces the Blizzard timer with a clean, compact frame.", 11, C.textMuted)
        quiMplusDesc:SetPoint("TOPLEFT", PAD, y)
        quiMplusDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        quiMplusDesc:SetJustifyH("LEFT")
        quiMplusDesc:SetWordWrap(true)
        quiMplusDesc:SetHeight(20)
        y = y - 24

        local quiMplusNote = GUI:CreateLabel(tabContent, "Disabled by default — most M+ players prefer dedicated timer addons. Enable for an all-in-one solution.", 10, {1.0, 0.75, 0.2, 1})
        quiMplusNote:SetPoint("TOPLEFT", PAD, y)
        quiMplusNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        quiMplusNote:SetJustifyH("LEFT")
        quiMplusNote:SetWordWrap(true)
        quiMplusNote:SetHeight(20)
        y = y - 28

        local quiMplusCheck = GUI:CreateFormCheckbox(tabContent, "Enable QUI M+ Timer", "enabled", mplusTimer, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Timer changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        quiMplusCheck:SetPoint("TOPLEFT", PAD, y)
        quiMplusCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Layout mode dropdown
        local layoutOptions = {
            { text = "Compact", value = "compact" },
            { text = "Full", value = "full" },
            { text = "Sleek", value = "sleek" },
        }
        local layoutDropdown = GUI:CreateFormDropdown(tabContent, "Layout Mode", layoutOptions, "layoutMode", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
            if _G.QUI_ApplyMPlusTimerSkin then
                _G.QUI_ApplyMPlusTimerSkin()
            end
        end)
        layoutDropdown:SetPoint("TOPLEFT", PAD, y)
        layoutDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Scale slider
        local scaleSlider = GUI:CreateFormSlider(tabContent, "Timer Scale", 0.5, 2.0, 0.05, "scale", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.ApplyScale then
                MPlusTimer:ApplyScale()
            end
        end, { deferOnDrag = true })
        scaleSlider:SetPoint("TOPLEFT", PAD, y)
        scaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local dungeonNameSlider = GUI:CreateFormSlider(tabContent, "Max Dungeon Name Length", 0, 40, 1, "maxDungeonNameLength", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.RenderKeyDetails then
                MPlusTimer:RenderKeyDetails()
            end
        end)
        dungeonNameSlider:SetPoint("TOPLEFT", PAD, y)
        dungeonNameSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Show Timer checkbox (full mode only)
        local quiMplusTimerCheck = GUI:CreateFormCheckbox(tabContent, "Show Timer Text (Full mode)", "showTimer", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        quiMplusTimerCheck:SetPoint("TOPLEFT", PAD, y)
        quiMplusTimerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Show Border checkbox
        local quiMplusBorderCheck = GUI:CreateFormCheckbox(tabContent, "Show Border", "showBorder", mplusTimer, function()
            if _G.QUI_ApplyMPlusTimerSkin then
                _G.QUI_ApplyMPlusTimerSkin()
            end
        end)
        quiMplusBorderCheck:SetPoint("TOPLEFT", PAD, y)
        quiMplusBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("QUI M+ Timer", mplusTimer)

        AddModuleBackgroundOverrideControls("QUI M+ Timer", mplusTimer)


        local quiMplusDeathsCheck = GUI:CreateFormCheckbox(tabContent, "Show Deaths", "showDeaths", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        quiMplusDeathsCheck:SetPoint("TOPLEFT", PAD, y)
        quiMplusDeathsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local quiMplusAffixCheck = GUI:CreateFormCheckbox(tabContent, "Show Affixes", "showAffixes", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        quiMplusAffixCheck:SetPoint("TOPLEFT", PAD, y)
        quiMplusAffixCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local quiMplusObjCheck = GUI:CreateFormCheckbox(tabContent, "Show Objectives", "showObjectives", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        quiMplusObjCheck:SetPoint("TOPLEFT", PAD, y)
        quiMplusObjCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Demo mode button
        local quiMplusDemoBtn = GUI:CreateButton(tabContent, "Toggle Demo Mode", 200, 28, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer then
                MPlusTimer:ToggleDemoMode()
            end
        end)
        quiMplusDemoBtn:SetPoint("TOPLEFT", PAD, y)
        y = y - 40

        local quiMplusDemoInfo = GUI:CreateLabel(tabContent, "Demo mode shows a preview timer for testing.", 10, C.textMuted)
        quiMplusDemoInfo:SetPoint("TOPLEFT", PAD, y)
        quiMplusDemoInfo:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        quiMplusDemoInfo:SetJustifyH("LEFT")
        y = y - 35

        -- ═══════════════════════════════════════════════════════════════
        -- FORCES BAR CUSTOMIZATION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Forces Bar")

        local forcesHeader = GUI:CreateSectionHeader(tabContent, "Forces Bar")
        forcesHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - forcesHeader.gap

        local forcesDesc = GUI:CreateLabel(tabContent, "Customize the enemy forces progress bar position, format, and appearance.", 11, C.textMuted)
        forcesDesc:SetPoint("TOPLEFT", PAD, y)
        forcesDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        forcesDesc:SetJustifyH("LEFT")
        forcesDesc:SetWordWrap(true)
        forcesDesc:SetHeight(20)
        y = y - 28

        local forcesEnabledCheck = GUI:CreateFormCheckbox(tabContent, "Show Forces Bar", "forcesBarEnabled", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        forcesEnabledCheck:SetPoint("TOPLEFT", PAD, y)
        forcesEnabledCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forcesDisplayModeOptions = {
            { text = "Progress Bar", value = "bar" },
            { text = "Text Only", value = "text" },
        }
        local forcesDisplayModeDropdown = GUI:CreateFormDropdown(tabContent, "Display Mode", forcesDisplayModeOptions, "forcesDisplayMode", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        forcesDisplayModeDropdown:SetPoint("TOPLEFT", PAD, y)
        forcesDisplayModeDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forcesPositionOptions = {
            { text = "After Timer Bars", value = "after_timer" },
            { text = "Before Timer Bars", value = "before_timer" },
            { text = "Before Objectives", value = "before_objectives" },
            { text = "After Objectives", value = "after_objectives" },
        }
        local forcesPosDropdown = GUI:CreateFormDropdown(tabContent, "Position", forcesPositionOptions, "forcesPosition", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        forcesPosDropdown:SetPoint("TOPLEFT", PAD, y)
        forcesPosDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forcesFormatOptions = {
            { text = "Count (123/273)", value = "count" },
            { text = "Percentage (45.32%)", value = "percentage" },
            { text = "Both (45.32% (123/273))", value = "both" },
        }
        local forcesFormatDropdown = GUI:CreateFormDropdown(tabContent, "Text Format", forcesFormatOptions, "forcesTextFormat", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.RenderForces then
                MPlusTimer:RenderForces()
            end
        end)
        forcesFormatDropdown:SetPoint("TOPLEFT", PAD, y)
        forcesFormatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forcesFontList = {}
        local LSM = LibStub("LibSharedMedia-3.0", true)
        if LSM then
            for name in pairs(LSM:HashTable("font")) do
                table.insert(forcesFontList, {value = name, text = name})
            end
            table.sort(forcesFontList, function(a, b) return a.text < b.text end)
        else
            forcesFontList = {{value = "Poppins", text = "Poppins"}}
        end
        local forcesFontDropdown = GUI:CreateFormDropdown(tabContent, "Font", forcesFontList, "forcesFont", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        forcesFontDropdown:SetPoint("TOPLEFT", PAD, y)
        forcesFontDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forcesFontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 18, 1, "forcesFontSize", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.UpdateLayout then
                MPlusTimer:UpdateLayout()
            end
        end)
        forcesFontSizeSlider:SetPoint("TOPLEFT", PAD, y)
        forcesFontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forcesColorPicker = GUI:CreateFormColorPicker(tabContent, "Text Color", "forcesTextColor", mplusTimer, function()
            local MPlusTimer = _G.QUI_MPlusTimer
            if MPlusTimer and MPlusTimer.RenderForces then
                MPlusTimer:RenderForces()
            end
            if _G.QUI_ApplyMPlusTimerSkin then
                _G.QUI_ApplyMPlusTimerSkin()
            end
        end)
        forcesColorPicker:SetPoint("TOPLEFT", PAD, y)
        forcesColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local forcesColorNote = GUI:CreateLabel(tabContent, "Leave text color unset to inherit from contrast-aware system.", 10, C.textMuted)
        forcesColorNote:SetPoint("TOPLEFT", PAD, y)
        forcesColorNote:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        forcesColorNote:SetJustifyH("LEFT")
        y = y - 25

        local barColorPicker

        local barUseClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Bar Fill", "barUseClassColor", mplusTimer, function()
            if barColorPicker then
                barColorPicker:SetEnabled(not mplusTimer.barUseClassColor)
            end
            RefreshAllSkinning()
        end)
        barUseClassColorCheck:SetPoint("TOPLEFT", PAD, y)
        barUseClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        barColorPicker = GUI:CreateFormColorPicker(tabContent, "Bar Fill Color", "barColor", mplusTimer, function()
            if _G.QUI_ApplyMPlusTimerSkin then
                _G.QUI_ApplyMPlusTimerSkin()
            end
        end, { noAlpha = true })
        barColorPicker:SetPoint("TOPLEFT", PAD, y)
        barColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        barColorPicker:SetEnabled(not mplusTimer.barUseClassColor)
        y = y - 40

        -- ═══════════════════════════════════════════════════════════════
        -- REPUTATION/CURRENCY SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Reputation/Currency")

        if general.skinCharacterFrame == nil then general.skinCharacterFrame = true end

        local charFrameHeader = GUI:CreateSectionHeader(tabContent, "Reputation/Currency")
        charFrameHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - charFrameHeader.gap

        local charFrameDesc = GUI:CreateLabel(tabContent, "Apply dark themed styling to the Reputation and Currency tabs with accent-colored borders.", 11, C.textMuted)
        charFrameDesc:SetPoint("TOPLEFT", PAD, y)
        charFrameDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        charFrameDesc:SetJustifyH("LEFT")
        charFrameDesc:SetWordWrap(true)
        charFrameDesc:SetHeight(20)
        y = y - 28

        local charFrameCheck = GUI:CreateFormCheckbox(tabContent, "Skin Reputation/Currency", "skinCharacterFrame", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        charFrameCheck:SetPoint("TOPLEFT", PAD, y)
        charFrameCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Reputation/Currency", general, "characterFrame")

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- INSPECT FRAME SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Inspect Frame")

        if general.skinInspectFrame == nil then general.skinInspectFrame = true end

        local inspectFrameHeader = GUI:CreateSectionHeader(tabContent, "Inspect Frame")
        inspectFrameHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - inspectFrameHeader.gap

        local inspectFrameDesc = GUI:CreateLabel(tabContent, "Skin the Inspect Frame to match Character Frame styling.", 11, C.textMuted)
        inspectFrameDesc:SetPoint("TOPLEFT", PAD, y)
        inspectFrameDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        inspectFrameDesc:SetJustifyH("LEFT")
        inspectFrameDesc:SetWordWrap(true)
        inspectFrameDesc:SetHeight(20)
        y = y - 28

        local inspectFrameCheck = GUI:CreateFormCheckbox(tabContent, "Skin Inspect Frame", "skinInspectFrame", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        inspectFrameCheck:SetPoint("TOPLEFT", PAD, y)
        inspectFrameCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Inspect Frame", general, "inspectFrame")

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- OVERRIDE ACTION BAR SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Override Action Bar")

        if general.skinOverrideActionBar == nil then general.skinOverrideActionBar = false end

        local overrideBarHeader = GUI:CreateSectionHeader(tabContent, "Override Action Bar")
        overrideBarHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - overrideBarHeader.gap

        local overrideBarDesc = GUI:CreateLabel(tabContent, "Skin the vehicle/override action bar (skyriding, possession, etc.).", 11, C.textMuted)
        overrideBarDesc:SetPoint("TOPLEFT", PAD, y)
        overrideBarDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        overrideBarDesc:SetJustifyH("LEFT")
        overrideBarDesc:SetWordWrap(true)
        overrideBarDesc:SetHeight(20)
        y = y - 28

        local overrideBarCheck = GUI:CreateFormCheckbox(tabContent, "Skin Override Action Bar", "skinOverrideActionBar", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        overrideBarCheck:SetPoint("TOPLEFT", PAD, y)
        overrideBarCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        AddModuleBorderOverrideControls("Override Action Bar", general, "overrideActionBar")

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- OBJECTIVE TRACKER SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Objective Tracker")

        if general.skinObjectiveTracker == nil then general.skinObjectiveTracker = false end

        local objTrackerHeader = GUI:CreateSectionHeader(tabContent, "Objective Tracker")
        objTrackerHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - objTrackerHeader.gap

        local objTrackerWip = GUI:CreateLabel(tabContent, "Work-in-progress: Enable only if you want to test. Still being polished.", 11, {1, 0.6, 0.2, 1})
        objTrackerWip:SetPoint("TOPLEFT", PAD, y)
        objTrackerWip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        objTrackerWip:SetJustifyH("LEFT")
        y = y - 18

        local objTrackerDesc = GUI:CreateLabel(tabContent, "Apply QUI styling to quest objectives, achievement tracking, and bonus objectives.", 11, C.textMuted)
        objTrackerDesc:SetPoint("TOPLEFT", PAD, y)
        objTrackerDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        objTrackerDesc:SetJustifyH("LEFT")
        objTrackerDesc:SetWordWrap(true)
        objTrackerDesc:SetHeight(20)
        y = y - 28

        local objTrackerCheck = GUI:CreateFormCheckbox(tabContent, "Skin Objective Tracker", "skinObjectiveTracker", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        objTrackerCheck:SetPoint("TOPLEFT", PAD, y)
        objTrackerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerHeight == nil then general.objectiveTrackerHeight = 600 end
        local objTrackerHeightSlider = GUI:CreateFormSlider(tabContent, "Max Height", 200, 1000, 10,
            "objectiveTrackerHeight", general, function()
                if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
            end)
        objTrackerHeightSlider:SetPoint("TOPLEFT", PAD, y)
        objTrackerHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerModuleFontSize == nil then general.objectiveTrackerModuleFontSize = 12 end
        local objTrackerModuleFontSlider = GUI:CreateFormSlider(tabContent, "Module Header Font (QUESTS, etc.)", 6, 18, 1,
            "objectiveTrackerModuleFontSize", general, function()
                if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
            end)
        objTrackerModuleFontSlider:SetPoint("TOPLEFT", PAD, y)
        objTrackerModuleFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerTitleFontSize == nil then general.objectiveTrackerTitleFontSize = 10 end
        local objTrackerTitleFontSlider = GUI:CreateFormSlider(tabContent, "Quest/Achievement Title Font", 6, 18, 1,
            "objectiveTrackerTitleFontSize", general, function()
                if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
            end)
        objTrackerTitleFontSlider:SetPoint("TOPLEFT", PAD, y)
        objTrackerTitleFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerTextFontSize == nil then general.objectiveTrackerTextFontSize = 10 end
        local objTrackerTextFontSlider = GUI:CreateFormSlider(tabContent, "Objective Text Font", 6, 18, 1,
            "objectiveTrackerTextFontSize", general, function()
                if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
            end)
        objTrackerTextFontSlider:SetPoint("TOPLEFT", PAD, y)
        objTrackerTextFontSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerWidth == nil then general.objectiveTrackerWidth = 260 end
        local objTrackerWidthSlider = GUI:CreateFormSlider(tabContent, "Max Width", 150, 400, 10,
            "objectiveTrackerWidth", general, function()
                if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
            end)
        objTrackerWidthSlider:SetPoint("TOPLEFT", PAD, y)
        objTrackerWidthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.hideObjectiveTrackerBorder == nil then general.hideObjectiveTrackerBorder = false end
        local hideBorderCheck = GUI:CreateFormCheckbox(tabContent, "Hide Border", "hideObjectiveTrackerBorder", general, function()
            if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
        end)
        hideBorderCheck:SetPoint("TOPLEFT", PAD, y)
        hideBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerModuleColor == nil then general.objectiveTrackerModuleColor = { 1.0, 0.82, 0.0, 1.0 } end
        local moduleColorPicker = GUI:CreateFormColorPicker(tabContent, "Module Header Color (QUESTS, etc.)", "objectiveTrackerModuleColor", general, function()
            if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
        end)
        moduleColorPicker:SetPoint("TOPLEFT", PAD, y)
        moduleColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerTitleColor == nil then general.objectiveTrackerTitleColor = { 1.0, 1.0, 1.0, 1.0 } end
        local titleColorPicker = GUI:CreateFormColorPicker(tabContent, "Quest/Achievement Title Color", "objectiveTrackerTitleColor", general, function()
            if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
        end)
        titleColorPicker:SetPoint("TOPLEFT", PAD, y)
        titleColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if general.objectiveTrackerTextColor == nil then general.objectiveTrackerTextColor = { 0.8, 0.8, 0.8, 1.0 } end
        local textColorPicker = GUI:CreateFormColorPicker(tabContent, "Objective Text Color", "objectiveTrackerTextColor", general, function()
            if _G.QUI_RefreshObjectiveTracker then _G.QUI_RefreshObjectiveTracker() end
        end)
        textColorPicker:SetPoint("TOPLEFT", PAD, y)
        textColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Note: Background opacity is controlled via Edit Mode's built-in opacity slider

        y = y - 10  -- Extra padding before next section

        -- ═══════════════════════════════════════════════════════════════
        -- INSTANCE FRAMES SECTION
        -- ═══════════════════════════════════════════════════════════════
        GUI:SetSearchSection("Instance Frames")

        if general.skinInstanceFrames == nil then general.skinInstanceFrames = false end

        local instanceHeader = GUI:CreateSectionHeader(tabContent, "Instance Frames")
        instanceHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - instanceHeader.gap

        local instanceWip = GUI:CreateLabel(tabContent, "Work-in-progress: Enable only if you want to test. Still being polished.", 11, {1, 0.6, 0.2, 1})
        instanceWip:SetPoint("TOPLEFT", PAD, y)
        instanceWip:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        instanceWip:SetJustifyH("LEFT")
        y = y - 18

        local instanceDesc = GUI:CreateLabel(tabContent, "Skin the Dungeons & Raids window, PVP queue, and M+ Dungeons tab.", 11, C.textMuted)
        instanceDesc:SetPoint("TOPLEFT", PAD, y)
        instanceDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        instanceDesc:SetJustifyH("LEFT")
        instanceDesc:SetWordWrap(true)
        instanceDesc:SetHeight(20)
        y = y - 28

        local instanceCheck = GUI:CreateFormCheckbox(tabContent, "Skin Instance Frames", "skinInstanceFrames", general, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Skinning changes require a reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        instanceCheck:SetPoint("TOPLEFT", PAD, y)
        instanceCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        y = y - 10
    end

    tabContent:SetHeight(math.abs(y) + 50)
end

-- Export
ns.QUI_SkinningOptions = {
    BuildSkinningTab = BuildSkinningTab
}
