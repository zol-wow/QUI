--[[
    QUI QoL Options - General Tab
    BuildGeneralTab for General & QoL page
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local QUICore = ns.Addon
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local P = Helpers.PlaceRow

local function BuildGeneralTab(tabContent)
    local FORM_ROW = 32
    local PAD = Shared.PADDING
    local db = Shared.GetDB()

    -- Refresh callback for fonts/textures (refreshes everything that uses these defaults)
    local function RefreshAll()
        if QUICore and QUICore.RefreshAll then QUICore:RefreshAll() end
        if _G.QUI_RefreshUnitFrames then _G.QUI_RefreshUnitFrames() end
        if QUICore then
            if QUICore.UpdatePowerBar then QUICore:UpdatePowerBar() end
            if QUICore.UpdateSecondaryPowerBar then QUICore:UpdateSecondaryPowerBar() end
        end
        if QUICore and QUICore.Minimap and QUICore.Minimap.Refresh then QUICore.Minimap:Refresh() end
        if _G.QUI_RefreshBuffBorders then _G.QUI_RefreshBuffBorders() end
        if ns and ns.NCDM and ns.NCDM.RefreshAll then ns.NCDM:RefreshAll() end
        if QUICore and QUICore.Loot and QUICore.Loot.RefreshColors then QUICore.Loot:RefreshColors() end
        C_Timer.After(0.1, function()
            if QUICore and QUICore.ApplyViewerLayout then
                local essV = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
                local utilV = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
                if essV then QUICore:ApplyViewerLayout(essV) end
                if utilV then QUICore:ApplyViewerLayout(utilV) end
            end
        end)
    end

    GUI:SetSearchContext({tabIndex = 2, tabName = "General & QoL", subTabIndex = 1, subTabName = "General"})

    if not db then return end

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(tabContent, PAD)

    -- ========== UI Scale ==========
    if db.general then
        CreateCollapsible("UI Scale", 1, function(body)
            local sy = -4
            local scaleSlider = GUI:CreateFormSlider(body, "Global UI Scale", 0.3, 2.0, 0.01,
                "uiScale", db.general, function(val)
                    if InCombatLockdown() then return end
                    UIParent:SetScale(val)
                end, { deferOnDrag = true, precision = 7 })
            sy = P(scaleSlider, body, sy)

            local presetLabel = GUI:CreateLabel(body, "Quick UI Scale Presets:", 12, C.text)
            presetLabel:SetPoint("TOPLEFT", 0, sy)

            local function ApplyPreset(val, name)
                if InCombatLockdown() then return end
                db.general.uiScale = val
                UIParent:SetScale(val)
                local msg = "|cff60A5FA[QUI]|r UI scale set to " .. val
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

            local buttonContainer = CreateFrame("Frame", nil, body)
            buttonContainer:SetPoint("LEFT", scaleSlider, "LEFT", 180, 0)
            buttonContainer:SetPoint("RIGHT", scaleSlider, "RIGHT", 0, 0)
            buttonContainer:SetPoint("TOP", presetLabel, "TOP", 0, 0)
            buttonContainer:SetHeight(26)

            local BUTTON_GAP = 6
            local NUM_BUTTONS = 5
            local buttons = {}
            buttons[1] = GUI:CreateButton(buttonContainer, "1080p", 50, 26, function() ApplyPreset(0.7111111, "1080p") end)
            buttons[2] = GUI:CreateButton(buttonContainer, "1440p", 50, 26, function() ApplyPreset(0.5333333, "1440p") end)
            buttons[3] = GUI:CreateButton(buttonContainer, "1440p+", 50, 26, function() ApplyPreset(0.64, "1440p+") end)
            buttons[4] = GUI:CreateButton(buttonContainer, "4K", 50, 26, function() ApplyPreset(0.3555556, "4K") end)
            buttons[5] = GUI:CreateButton(buttonContainer, "Auto", 50, 26, AutoScale)

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

            local tooltipData = {
                { title = "1080p", desc = "Scale: 0.7111111\nPixel-perfect for 1920x1080" },
                { title = "1440p", desc = "Scale: 0.5333333\nPixel-perfect for 2560x1440" },
                { title = "1440p+", desc = "Scale: 0.64\nQuazii's personal setting - larger and more readable.\nRequires manual adjustment for pixel perfection." },
                { title = "4K", desc = "Scale: 0.3555556\nPixel-perfect for 3840x2160" },
                { title = "Auto", desc = "Computes pixel-perfect scale based on your resolution.\nFormula: 768 / screen height" },
            }
            for i, btn in ipairs(buttons) do
                local data = tooltipData[i]
                btn:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(data.title, 1, 1, 1)
                    GameTooltip:AddLine(data.desc, 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
                btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end

            sy = sy - FORM_ROW - 6

            local presetSummary = GUI:CreateLabel(body, "Hover over any preset for details. 1440p+ is Quazii's personal setting.", 11, C.textMuted)
            presetSummary:SetPoint("TOPLEFT", 0, sy)
            sy = sy - 20

            local bigPicture = GUI:CreateLabel(body,
                "UI scale is highly personal-it depends on your monitor size, resolution, and preference. If you already have a scale you like from years of playing WoW, stick with it. These presets are just common values people tend to use.",
                11, C.textMuted)
            bigPicture:SetPoint("TOPLEFT", 0, sy)
            bigPicture:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            bigPicture:SetJustifyH("LEFT")

            local section = body:GetParent()
            section._contentHeight = FORM_ROW + FORM_ROW + 6 + 20 + 36 + 8
        end)
    end

    -- ========== Default Font Settings ==========
    if db.general then
        CreateCollapsible("Default Font Settings", 4 * FORM_ROW + 8, function(body)
            local sy = -4
            local tipText = GUI:CreateLabel(body, "These settings apply throughout the UI. Individual elements with their own font options will override these defaults.", 11, C.textMuted)
            tipText:SetPoint("TOPLEFT", 0, sy)
            tipText:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            tipText:SetJustifyH("LEFT")
            sy = sy - 28

            local fontList = {}
            local LSM = ns.LSM
            if LSM then
                for name in pairs(LSM:HashTable("font")) do
                    table.insert(fontList, {value = name, text = name})
                end
                table.sort(fontList, function(a, b) return a.text < b.text end)
            else
                fontList = {{value = "Friz Quadrata TT", text = "Friz Quadrata TT"}}
            end

            sy = P(GUI:CreateFormDropdown(body, "Default Font", fontList, "font", db.general, RefreshAll), body, sy)

            local outlineOptions = {
                {value = "", text = "None"},
                {value = "OUTLINE", text = "Outline"},
                {value = "THICKOUTLINE", text = "Thick Outline"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Font Outline", outlineOptions, "fontOutline", db.general, RefreshAll), body, sy)
            P(GUI:CreateFormCheckbox(body, "Override Scrolling Combat Text Font", "overrideSCTFont", db.general, RefreshAll), body, sy)
        end)
    end

    -- ========== Quazii Recommended FPS Settings ==========
    CreateCollapsible("Quazii Recommended FPS Settings", 1, function(body)
        local sy = -4
        local fpsDesc = GUI:CreateLabel(body,
            "Apply Quazii's optimized graphics settings for competitive play. " ..
            "Your current settings are automatically saved when you click Apply - use 'Restore Previous Settings' to revert anytime. " ..
            "Caution: Clicking Apply again will overwrite your backup with these settings.",
            11, C.textMuted)
        fpsDesc:SetPoint("TOPLEFT", 0, sy)
        fpsDesc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        fpsDesc:SetJustifyH("LEFT")
        fpsDesc:SetWordWrap(true)
        fpsDesc:SetHeight(30)
        sy = sy - 40

        local restoreFpsBtn
        local fpsStatusText

        local function UpdateFPSStatus()
            local allMatch, matched, total = Shared.CheckCVarsMatch()
            if matched >= 50 then
                fpsStatusText:SetText("Settings: All applied")
                fpsStatusText:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                fpsStatusText:SetText(string.format("Settings: %d/%d match", matched, total))
                fpsStatusText:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
            end
        end

        local applyFpsBtn = GUI:CreateButton(body, "Apply FPS Settings", 180, 28, function()
            Shared.ApplyQuaziiFPSSettings()
            restoreFpsBtn:SetAlpha(1)
            restoreFpsBtn:Enable()
            UpdateFPSStatus()
        end)
        applyFpsBtn:SetPoint("TOPLEFT", 0, sy)
        applyFpsBtn:SetPoint("RIGHT", body, "CENTER", -5, 0)

        restoreFpsBtn = GUI:CreateButton(body, "Restore Previous Settings", 180, 28, function()
            if Shared.RestorePreviousFPSSettings() then
                restoreFpsBtn:SetAlpha(0.5)
                restoreFpsBtn:Disable()
            end
            UpdateFPSStatus()
        end)
        restoreFpsBtn:SetPoint("LEFT", body, "CENTER", 5, 0)
        restoreFpsBtn:SetPoint("TOP", applyFpsBtn, "TOP", 0, 0)
        restoreFpsBtn:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        sy = sy - 38

        fpsStatusText = GUI:CreateLabel(body, "", 11, C.accent)
        fpsStatusText:SetPoint("TOPLEFT", 0, sy)

        if not db.fpsBackup then
            restoreFpsBtn:SetAlpha(0.5)
            restoreFpsBtn:Disable()
        end
        UpdateFPSStatus()

        local section = body:GetParent()
        section._contentHeight = 40 + 38 + 22 + 8
    end)

    -- ========== Combat Status Text Indicator ==========
    local combatTextDB = db and db.combatText
    if combatTextDB then
        CreateCollapsible("Combat Status Text Indicator", 1, function(body)
            local sy = -4
            local desc = GUI:CreateLabel(body,
                "Displays '+Combat' or '-Combat' text on screen when entering or leaving combat. Useful for Shadowmeld skips.",
                11, C.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            desc:SetHeight(15)
            sy = sy - 25

            local previewEnterBtn = GUI:CreateButton(body, "Preview +Combat", 140, 28, function()
                if _G.QUI_PreviewCombatText then _G.QUI_PreviewCombatText("+Combat") end
            end)
            previewEnterBtn:SetPoint("TOPLEFT", 0, sy)
            previewEnterBtn:SetPoint("RIGHT", body, "CENTER", -5, 0)

            local previewLeaveBtn = GUI:CreateButton(body, "Preview -Combat", 140, 28, function()
                if _G.QUI_PreviewCombatText then _G.QUI_PreviewCombatText("-Combat") end
            end)
            previewLeaveBtn:SetPoint("LEFT", body, "CENTER", 5, 0)
            previewLeaveBtn:SetPoint("TOP", previewEnterBtn, "TOP", 0, 0)
            previewLeaveBtn:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - 38

            local function RefreshCombatText()
                if _G.QUI_RefreshCombatText then _G.QUI_RefreshCombatText() end
            end

            sy = P(GUI:CreateFormCheckbox(body, "Enable Combat Text", "enabled", combatTextDB, RefreshCombatText), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Display Time (sec)", 0.3, 3.0, 0.1, "displayTime", combatTextDB, RefreshCombatText), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Fade Duration (sec)", 0.1, 1.0, 0.05, "fadeTime", combatTextDB, RefreshCombatText), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 12, 48, 1, "fontSize", combatTextDB, RefreshCombatText), body, sy)

            local fontList = Shared.GetFontList()
            local combatTextFontDropdown

            local useCustomFontCheck = GUI:CreateFormCheckbox(body, "Use Custom Font", "useCustomFont", combatTextDB, function(val)
                RefreshCombatText()
                if combatTextFontDropdown and combatTextFontDropdown.SetEnabled then
                    combatTextFontDropdown:SetEnabled(val)
                end
            end)
            sy = P(useCustomFontCheck, body, sy)

            combatTextFontDropdown = GUI:CreateFormDropdown(body, "Font", fontList, "font", combatTextDB, RefreshCombatText)
            if combatTextFontDropdown.SetEnabled then
                combatTextFontDropdown:SetEnabled(combatTextDB.useCustomFont == true)
            end
            sy = P(combatTextFontDropdown, body, sy)

            sy = P(GUI:CreateFormSlider(body, "X Position Offset", -2000, 2000, 1, "xOffset", combatTextDB, RefreshCombatText), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Y Position Offset", -2000, 2000, 1, "yOffset", combatTextDB, RefreshCombatText), body, sy)
            sy = P(GUI:CreateFormColorPicker(body, "+Combat Text Color", "enterCombatColor", combatTextDB, RefreshCombatText), body, sy)
            P(GUI:CreateFormColorPicker(body, "-Combat Text Color", "leaveCombatColor", combatTextDB, RefreshCombatText), body, sy)

            local section = body:GetParent()
            section._contentHeight = 25 + 38 + 10 * FORM_ROW + 8
        end)
    end

    -- ========== Automation ==========
    local generalDB = db and db.general
    if generalDB then
        CreateCollapsible("Automation", 1, function(body)
            local sy = -4
            local desc = GUI:CreateLabel(body,
                "Toggle quality-of-life automation features. These run silently in the background.",
                11, C.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            desc:SetHeight(15)
            sy = sy - 25

            sy = P(GUI:CreateFormCheckbox(body, "Sell Junk Items at Vendors", "sellJunk", generalDB), body, sy)

            local repairOptions = {
                {value = "off", text = "Off"},
                {value = "personal", text = "Personal Gold"},
                {value = "guild", text = "Guild Bank (fallback to personal)"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Auto Repair at Vendors", repairOptions, "autoRepair", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Fast Auto Loot", "fastAutoLoot", generalDB), body, sy)

            local inviteOptions = {
                {value = "off", text = "Off"},
                {value = "all", text = "Everyone"},
                {value = "friends", text = "Friends & BNet Only"},
                {value = "guild", text = "Guild Members Only"},
                {value = "both", text = "Friends & Guild"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Auto Accept Party Invites", inviteOptions, "autoAcceptInvites", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto Accept Role Check", "autoRoleAccept", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto Accept Quests", "autoAcceptQuest", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto Turn-In Quests", "autoTurnInQuest", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto Select Single Gossip Option", "autoSelectGossip", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Hold Shift to Pause Quest/Gossip Automation", "questHoldShift", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto Insert M+ Keys", "autoInsertKey", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto Combat Log in M+", "autoCombatLog", generalDB, function()
                if _G.QUI_RefreshAutoCombatLogging then _G.QUI_RefreshAutoCombatLogging() end
            end), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto Combat Log in Raids", "autoCombatLogRaid", generalDB, function()
                if _G.QUI_RefreshAutoCombatLogging then _G.QUI_RefreshAutoCombatLogging() end
            end), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Click-to-Teleport on M+ Tab", "mplusTeleportEnabled", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto-Fill DELETE Confirmation Text", "autoDeleteConfirm", generalDB), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Auto-Enable Current Expansion Filter in Auction House", "auctionHouseExpansionFilter", generalDB), body, sy)
            P(GUI:CreateFormCheckbox(body, "Auto-Enable Current Expansion Filter in Crafting Orders", "craftingOrderExpansionFilter", generalDB), body, sy)

            local section = body:GetParent()
            section._contentHeight = 25 + 16 * FORM_ROW + 8
        end)
    end

    -- ========== Popup & Toast Blocker ==========
    if generalDB then
        if type(generalDB.popupBlocker) ~= "table" then generalDB.popupBlocker = {} end
        local popupDB = generalDB.popupBlocker

        CreateCollapsible("Popup & Toast Blocker", 1, function(body)
            local sy = -4
            local desc = GUI:CreateLabel(body,
                "Block selected Blizzard popups, toasts, and reminder alerts (including talent reminders and collection toasts).",
                11, C.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            desc:SetHeight(20)
            sy = sy - 30

            local function RefreshPopupBlocker()
                if _G.QUI_RefreshPopupBlocker then _G.QUI_RefreshPopupBlocker() end
            end

            local popupToggleWidgets = {}

            local function UpdatePopupToggleState()
                local enabled = popupDB.enabled == true
                for _, widget in ipairs(popupToggleWidgets) do
                    if widget and widget.SetEnabled then widget:SetEnabled(enabled) end
                end
            end

            sy = P(GUI:CreateFormCheckbox(body, "Enable Popup/Toast Blocker", "enabled", popupDB, function()
                UpdatePopupToggleState()
                RefreshPopupBlocker()
            end), body, sy)

            local function AddPopupToggle(label, key)
                local check = GUI:CreateFormCheckbox(body, label, key, popupDB, RefreshPopupBlocker)
                sy = P(check, body, sy)
                table.insert(popupToggleWidgets, check)
            end

            AddPopupToggle("Block Talent Reminder Alerts (Microbutton)", "blockTalentMicroButtonAlerts")
            AddPopupToggle("Block Help Tips (talent/spellbook tutorial popups)", "blockHelpTips")
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

            local section = body:GetParent()
            section._contentHeight = 30 + 11 * FORM_ROW + 8
        end)
    end

    -- ========== Quick Salvage ==========
    local qsDB = db and db.general and db.general.quickSalvage
    if qsDB then
        CreateCollapsible("Quick Salvage", 3 * FORM_ROW + 8, function(body)
            local sy = -4
            local desc = GUI:CreateLabel(body,
                "Mill, prospect, or disenchant items with a single click using a modifier key. Requires the corresponding profession.",
                11, C.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            desc:SetHeight(20)
            sy = sy - 30

            sy = P(GUI:CreateFormCheckbox(body, "Enable Quick Salvage", "enabled", qsDB, function()
                if _G.QUI_RefreshQuickSalvage then _G.QUI_RefreshQuickSalvage() end
            end), body, sy)

            local modifierOptions = {
                {value = "ALT", text = "Alt"},
                {value = "ALTCTRL", text = "Alt + Ctrl"},
                {value = "ALTSHIFT", text = "Alt + Shift"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Modifier Key", modifierOptions, "modifier", qsDB, function()
                if _G.QUI_RefreshQuickSalvage then _G.QUI_RefreshQuickSalvage() end
            end), body, sy)

            local actionsDesc = GUI:CreateLabel(body,
                "Milling: Herbs (5+ stack)  |  Prospecting: Ores (5+ stack)  |  Disenchanting: Green+ gear",
                11, C.textMuted)
            actionsDesc:SetPoint("TOPLEFT", 0, sy)
            actionsDesc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            actionsDesc:SetJustifyH("LEFT")
            actionsDesc:SetWordWrap(true)
        end)
    end

    -- ========== Consumable Check ==========
    if generalDB then
        CreateCollapsible("Consumable Check", 1, function(body)
            local sy = -4
            local desc = GUI:CreateLabel(body,
                "Display consumable status icons when triggered by events below. Left-click missing icons to use your preferred item; right-click in ready check to choose a different item.",
                11, C.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            desc:SetHeight(20)
            sy = sy - 30

            sy = P(GUI:CreateFormCheckbox(body, "Enable Consumable Check", "consumableCheckEnabled", generalDB), body, sy)

            sy = P(GUI:CreateFormCheckbox(body, "Always Show (Persistent Mode)", "consumablePersistent", generalDB, function()
                if generalDB.consumablePersistent then
                    if _G.QUI_ShowConsumables then _G.QUI_ShowConsumables() end
                else
                    if _G.QUI_HideConsumables then _G.QUI_HideConsumables() end
                end
            end), body, sy)

            -- Triggers sub-header
            local triggersLabel = GUI:CreateLabel(body, "Triggers", 12, C.accent)
            triggersLabel:SetPoint("TOPLEFT", 0, sy)
            sy = sy - 20

            local triggerReadyCheck = GUI:CreateFormCheckbox(body, "Ready Check", "consumableOnReadyCheck", generalDB)
            triggerReadyCheck:SetPoint("TOPLEFT", 20, sy)
            triggerReadyCheck:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local triggerDungeon = GUI:CreateFormCheckbox(body, "Dungeon Entrance", "consumableOnDungeon", generalDB)
            triggerDungeon:SetPoint("TOPLEFT", 20, sy)
            triggerDungeon:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local triggerRaid = GUI:CreateFormCheckbox(body, "Raid Entrance", "consumableOnRaid", generalDB)
            triggerRaid:SetPoint("TOPLEFT", 20, sy)
            triggerRaid:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local triggerResurrect = GUI:CreateFormCheckbox(body, "Instanced Resurrect", "consumableOnResurrect", generalDB)
            triggerResurrect:SetPoint("TOPLEFT", 20, sy)
            triggerResurrect:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            -- Buff Checks sub-header
            local buffsLabel = GUI:CreateLabel(body, "Buff Checks", 12, C.accent)
            buffsLabel:SetPoint("TOPLEFT", 0, sy)
            sy = sy - 20

            local consumableFoodCheck = GUI:CreateFormCheckbox(body, "Food Buff", "consumableFood", generalDB)
            consumableFoodCheck:SetPoint("TOPLEFT", 20, sy)
            consumableFoodCheck:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local consumableFlaskCheck = GUI:CreateFormCheckbox(body, "Flask Buff", "consumableFlask", generalDB)
            consumableFlaskCheck:SetPoint("TOPLEFT", 20, sy)
            consumableFlaskCheck:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local mhLabel = ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetMHLabel() or "Weapon Oil"
            local consumableOilMHCheck = GUI:CreateFormCheckbox(body, mhLabel .. " (Main Hand)", "consumableOilMH", generalDB)
            consumableOilMHCheck:SetPoint("TOPLEFT", 20, sy)
            consumableOilMHCheck:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local ohLabel = ns.ConsumableCheckLabels and ns.ConsumableCheckLabels.GetOHLabel() or "Weapon Oil"
            local consumableOilOHCheck = GUI:CreateFormCheckbox(body, ohLabel .. " (Off Hand)", "consumableOilOH", generalDB)
            consumableOilOHCheck:SetPoint("TOPLEFT", 20, sy)
            consumableOilOHCheck:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local consumableRuneCheck = GUI:CreateFormCheckbox(body, "Augment Rune", "consumableRune", generalDB)
            consumableRuneCheck:SetPoint("TOPLEFT", 20, sy)
            consumableRuneCheck:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local consumableHSCheck = GUI:CreateFormCheckbox(body, "Healthstones", "consumableHealthstone", generalDB)
            consumableHSCheck:SetPoint("TOPLEFT", 20, sy)
            consumableHSCheck:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - FORM_ROW

            local hsDesc = GUI:CreateLabel(body, "Only shows when a Warlock is in the group.", 11, C.textMuted)
            hsDesc:SetPoint("TOPLEFT", 0, sy + 4)
            hsDesc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            hsDesc:SetJustifyH("LEFT")
            sy = sy - 20

            -- Expiration Warning sub-header
            local expirationLabel = GUI:CreateLabel(body, "Expiration Warning", 12, C.accent)
            expirationLabel:SetPoint("TOPLEFT", 0, sy)
            sy = sy - 20

            sy = P(GUI:CreateFormCheckbox(body, "Warn When Buffs Expiring", "consumableExpirationWarning", generalDB), body, sy)

            local expirationDesc = GUI:CreateLabel(body, "Show consumables window when food/flask/rune is about to expire (instanced content only).", 11, C.textMuted)
            expirationDesc:SetPoint("TOPLEFT", 0, sy + 4)
            expirationDesc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            expirationDesc:SetJustifyH("LEFT")
            expirationDesc:SetWordWrap(true)
            expirationDesc:SetHeight(20)
            sy = sy - 30

            sy = P(GUI:CreateFormSlider(body, "Warning Threshold (seconds)", 60, 600, 30, "consumableExpirationThreshold", generalDB), body, sy)

            -- Display sub-header
            local displayLabel = GUI:CreateLabel(body, "Display", 12, C.accent)
            displayLabel:SetPoint("TOPLEFT", 0, sy)
            sy = sy - 20

            local function RefreshConsumables()
                if _G.QUI_RefreshConsumables then _G.QUI_RefreshConsumables() end
            end

            sy = P(GUI:CreateFormSlider(body, "Icon Size", 24, 64, 2, "consumableIconSize", generalDB, RefreshConsumables), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Scale", 0.5, 3, 0.05, "consumableScale", generalDB, RefreshConsumables), body, sy)

            -- Total: desc(30) + enable(32) + triggers header(20) + 4 triggers(128) + buffs header(20)
            -- + 6 buffs(192) + hs desc(20) + expiration header(20) + warn check(32) + exp desc(30)
            -- + threshold(32) + display header(20) + icon size(32) + scale(32)
            local section = body:GetParent()
            section._contentHeight = 30 + FORM_ROW + 20 + 4*FORM_ROW + 20 + 6*FORM_ROW + 20 + 20 + FORM_ROW + 30 + FORM_ROW + 20 + 2*FORM_ROW + 8
        end)
    end

    -- ========== Consumable Macros ==========
    local cmDB = generalDB and generalDB.consumableMacros
    if cmDB then
        CreateCollapsible("Consumable Macros", 1, function(body)
            local sy = -4

            local desc = GUI:CreateLabel(body,
                "Auto-create per-character macros that use the best quality Flask or Potion in your bags. "
                .. "Higher quality variants are tried first (Gold Fleeting > Silver Fleeting > Gold Crafted > Silver Crafted).",
                11, C.textMuted)
            desc:SetPoint("TOPLEFT", 0, sy)
            desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            desc:SetWordWrap(true)
            desc:SetHeight(40)
            sy = sy - 44

            sy = P(GUI:CreateFormCheckbox(body, "Enable Consumable Macros", "enabled", cmDB, function()
                if ns.ConsumableMacros then
                    if cmDB.enabled then
                        ns.ConsumableMacros:ForceRefresh()
                    else
                        ns.ConsumableMacros:DeleteMacros()
                    end
                end
            end), body, sy)

            local flaskOptions = ns.ConsumableMacros and ns.ConsumableMacros.FLASK_OPTIONS or {
                { value = "none", text = "None" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Flask Type", flaskOptions, "selectedFlask", cmDB, function()
                if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
            end), body, sy)

            local potionOptions = ns.ConsumableMacros and ns.ConsumableMacros.POTION_OPTIONS or {
                { value = "none", text = "None" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Potion Type", potionOptions, "selectedPotion", cmDB, function()
                if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
            end), body, sy)

            local healthOptions = ns.ConsumableMacros and ns.ConsumableMacros.HEALTH_OPTIONS or {
                { value = "none", text = "None" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Health Potion", healthOptions, "selectedHealth", cmDB, function()
                if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
            end), body, sy)

            local healthstoneOptions = ns.ConsumableMacros and ns.ConsumableMacros.HEALTHSTONE_OPTIONS or {
                { value = "none", text = "None" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Healthstone", healthstoneOptions, "selectedHealthstone", cmDB, function()
                if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
            end), body, sy)

            local augmentOptions = ns.ConsumableMacros and ns.ConsumableMacros.AUGMENT_OPTIONS or {
                { value = "none", text = "None" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Augment Rune", augmentOptions, "selectedAugment", cmDB, function()
                if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
            end), body, sy)

            local vantusOptions = ns.ConsumableMacros and ns.ConsumableMacros.VANTUS_OPTIONS or {
                { value = "none", text = "None" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Vantus Rune", vantusOptions, "selectedVantus", cmDB, function()
                if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
            end), body, sy)

            local weaponOptions = ns.ConsumableMacros and ns.ConsumableMacros.WEAPON_OPTIONS or {
                { value = "none", text = "None" },
            }
            sy = P(GUI:CreateFormDropdown(body, "Weapon Consumable", weaponOptions, "selectedWeapon", cmDB, function()
                if ns.ConsumableMacros then ns.ConsumableMacros:ForceRefresh() end
            end), body, sy)

            sy = P(GUI:CreateFormCheckbox(body, "Chat Notifications", "chatNotifications", cmDB), body, sy)

            local info = GUI:CreateLabel(body,
                "Creates per-character macros: QUI_Flask, QUI_Pot, QUI_Health, QUI_Stone, QUI_Rune, QUI_Vantus, QUI_Weapon. Drag them to your action bars.",
                11, C.textMuted)
            info:SetPoint("TOPLEFT", 0, sy)
            info:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            info:SetWordWrap(true)
            info:SetHeight(30)
            sy = sy - 34

            -- desc(44) + enable(32) + 7 dropdowns(224) + chat(32) + info(34) + pad
            local section = body:GetParent()
            section._contentHeight = 44 + 9 * FORM_ROW + 34 + 8
        end)
    end

    -- ========== Target Distance Bracket Display ==========
    local rangeCheckDB = db and db.rangeCheck
    if rangeCheckDB then
        CreateCollapsible("Target Distance Bracket Display", 1, function(body)
            local sy = -4

            local dynamicColorCheck
            local classColorCheck
            local textColorPicker

            local function RefreshRangeControls()
                if rangeCheckDB.dynamicColor and rangeCheckDB.useClassColor then
                    rangeCheckDB.useClassColor = false
                    if classColorCheck and classColorCheck.SetValue then classColorCheck.SetValue(false, true) end
                end
                if dynamicColorCheck and dynamicColorCheck.SetEnabled then dynamicColorCheck:SetEnabled(true) end
                if classColorCheck and classColorCheck.SetEnabled then
                    classColorCheck:SetEnabled(not rangeCheckDB.dynamicColor)
                end
                if textColorPicker and textColorPicker.SetEnabled then
                    textColorPicker:SetEnabled(not rangeCheckDB.dynamicColor and not rangeCheckDB.useClassColor)
                end
            end

            sy = P(GUI:CreateFormCheckbox(body, "Enable Distance Bracket Display", "enabled", rangeCheckDB, function()
                Shared.RefreshRangeCheck()
            end), body, sy)

            local previewState = { enabled = _G.QUI_IsRangeCheckPreviewMode and _G.QUI_IsRangeCheckPreviewMode() or false }
            sy = P(GUI:CreateFormCheckbox(body, "Preview / Move Frame", "enabled", previewState, function(val)
                if _G.QUI_ToggleRangeCheckPreview then _G.QUI_ToggleRangeCheckPreview(val) end
            end), body, sy)

            sy = P(GUI:CreateFormCheckbox(body, "Combat Only", "combatOnly", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Only Show With Hostile Target", "showOnlyWithTarget", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)
            sy = P(GUI:CreateFormCheckbox(body, "Shorten Text", "shortenText", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)

            dynamicColorCheck = GUI:CreateFormCheckbox(body, "Dynamic Color (by distance bracket)", "dynamicColor", rangeCheckDB, function(val)
                if val then
                    rangeCheckDB.useClassColor = false
                    if classColorCheck and classColorCheck.SetValue then classColorCheck.SetValue(false, true) end
                end
                Shared.RefreshRangeCheck()
                RefreshRangeControls()
            end)
            sy = P(dynamicColorCheck, body, sy)

            classColorCheck = GUI:CreateFormCheckbox(body, "Use Class Color", "useClassColor", rangeCheckDB, function()
                Shared.RefreshRangeCheck()
                RefreshRangeControls()
            end)
            sy = P(classColorCheck, body, sy)

            if not rangeCheckDB.textColor then rangeCheckDB.textColor = { 0.2, 0.95, 0.55, 1 } end
            textColorPicker = GUI:CreateFormColorPicker(body, "Text Color", "textColor", rangeCheckDB, function() Shared.RefreshRangeCheck() end)
            sy = P(textColorPicker, body, sy)

            local fontList = Shared.GetFontList()
            sy = P(GUI:CreateFormDropdown(body, "Font", fontList, "font", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)
            sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 48, 1, "fontSize", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)

            local strataOptions = {
                {value = "BACKGROUND", text = "Background"},
                {value = "LOW", text = "Low"},
                {value = "MEDIUM", text = "Medium"},
                {value = "HIGH", text = "High"},
                {value = "DIALOG", text = "Dialog"},
            }
            sy = P(GUI:CreateFormDropdown(body, "Frame Strata", strataOptions, "strata", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)
            sy = P(GUI:CreateFormSlider(body, "X-Offset", -700, 700, 1, "offsetX", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)
            P(GUI:CreateFormSlider(body, "Y-Offset", -700, 700, 1, "offsetY", rangeCheckDB, function() Shared.RefreshRangeCheck() end), body, sy)

            RefreshRangeControls()

            local section = body:GetParent()
            section._contentHeight = 13 * FORM_ROW + 8
        end)
    end

    -- ========== QUI Panel Settings ==========
    CreateCollapsible("QUI Panel Settings", 1, function(body)
        local sy = -4

        local minimapBtnDB = db and db.minimapButton
        if minimapBtnDB then
            sy = P(GUI:CreateFormCheckbox(body, "Hide QUI Minimap Icon", "hide", minimapBtnDB, function(dbVal)
                local LibDBIcon = LibStub("LibDBIcon-1.0", true)
                if LibDBIcon then
                    if dbVal then LibDBIcon:Hide("QUI") else LibDBIcon:Show("QUI") end
                end
                if _G.QUI_RefreshMinimapButtonDrawer then _G.QUI_RefreshMinimapButtonDrawer() end
            end), body, sy)
        end

        P(GUI:CreateFormSlider(body, "QUI Panel Transparency", 0.3, 1.0, 0.01, "configPanelAlpha", db, function(val)
            local mainFrame = GUI.MainFrame
            if mainFrame then
                local bgColor = GUI.Colors.bg
                mainFrame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], val)
            end
        end), body, sy)

        local section = body:GetParent()
        section._contentHeight = 2 * FORM_ROW + 8
    end)

    -- ========== Reload Behavior ==========
    CreateCollapsible("Reload Behavior", 2 * FORM_ROW + 8, function(body)
        local sy = -4
        local desc = GUI:CreateLabel(body,
            "By default, QUI queues /reload until combat ends to prevent taint issues. Enable this to bypass the combat check and reload immediately.",
            11, C.textMuted)
        desc:SetPoint("TOPLEFT", 0, sy)
        desc:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetHeight(28)
        sy = sy - 32

        if db.general then
            P(GUI:CreateFormCheckbox(body, "Allow Reload During Combat", "allowReloadInCombat", db.general), body, sy)
        end
    end)

    relayout()
end

-- Export
ns.QUI_QoLOptions = {
    BuildGeneralTab = BuildGeneralTab
}
