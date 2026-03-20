--[[
    QUI Prey Tracker Options
    Options sub-tab for the Prey Tracker module
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors
local Shared = ns.QUI_Options
local Helpers = ns.Helpers
local P = Helpers.PlaceRow

local PADDING = Shared.PADDING
local FORM_ROW = 32

local function GetDB()
    local db = Shared.GetDB()
    return db and db.preyTracker
end

ns.QUI_PreyTrackerOptions = {}

function ns.QUI_PreyTrackerOptions.CreatePreyTrackerPage(parent)
    local scroll, content = Shared.CreateScrollableContent(parent)
    local db = GetDB()

    GUI:SetSearchContext({ tabIndex = 9, tabName = "Prey Tracker" })

    if not db then
        local noData = GUI:CreateLabel(content, "Prey Tracker settings are not available. Please reload the UI.", 12, C.textMuted)
        noData:SetPoint("TOPLEFT", PADDING, -20)
        return scroll
    end

    local function Refresh()
        if _G.QUI_RefreshPreyTracker then _G.QUI_RefreshPreyTracker() end
    end

    local function RefreshPreview()
        Refresh()
        -- Auto-toggle preview when adjusting settings
        if _G.QUI_TogglePreyTrackerPreview then
            _G.QUI_TogglePreyTrackerPreview(true)
        end
    end

    local sections, relayout, CreateCollapsible = Shared.CreateCollapsiblePage(content, PADDING)

    ---------------------------------------------------------------------------
    -- GENERAL
    ---------------------------------------------------------------------------
    CreateCollapsible("General", 5 * FORM_ROW + 20, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Prey Tracker", "enabled", db, Refresh), body, sy)

        local enableHint = GUI:CreateLabel(body, "Tracks prey hunting progress from the Midnight prey system. Requires an active prey hunt quest.", 11, C.textMuted)
        enableHint:SetPoint("TOPLEFT", 0, sy)
        enableHint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        enableHint:SetJustifyH("LEFT")
        enableHint:SetWordWrap(true)
        enableHint:SetHeight(28)
        sy = sy - 32

        sy = P(GUI:CreateFormSlider(body, "Bar Width", 100, 500, 1, "width", db, RefreshPreview), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Bar Height", 10, 40, 1, "height", db, RefreshPreview), body, sy)
        P(GUI:CreateFormSlider(body, "Border Size", 0, 3, 1, "borderSize", db, RefreshPreview), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- BAR APPEARANCE
    ---------------------------------------------------------------------------
    CreateCollapsible("Bar Appearance", 7 * FORM_ROW + 8, function(body)
        local sy = -4

        -- Texture dropdown
        local textureList = Shared.GetTextureList()
        sy = P(GUI:CreateFormDropdown(body, "Bar Texture", textureList, "texture", db, RefreshPreview), body, sy)

        -- Color mode
        local colorModeOptions = {
            { value = "accent", text = "Accent Color" },
            { value = "class", text = "Class Color" },
            { value = "custom", text = "Custom Color" },
        }
        local function GetColorMode()
            if db.barUseClassColor then return "class"
            elseif db.barUseAccentColor then return "accent"
            else return "custom"
            end
        end
        local colorModeDropdown = GUI:CreateFormDropdown(body, "Bar Color Mode", colorModeOptions, nil, nil, function()
            -- Read from the dropdown's current value via a small trick
        end)
        -- Manual handling since this maps to multiple DB keys
        colorModeDropdown:SetPoint("TOPLEFT", 0, sy)
        colorModeDropdown:SetPoint("RIGHT", body, "RIGHT", 0, 0)

        -- Find the dropdown button inside the container
        local dropdownBtn
        for _, child in ipairs({ colorModeDropdown:GetChildren() }) do
            if child.GetObjectType and child:GetObjectType() == "Button" then
                dropdownBtn = child
                break
            end
        end

        if dropdownBtn then
            local currentMode = GetColorMode()
            -- Set initial text
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
                            db.barUseClassColor = (opt.value == "class")
                            db.barUseAccentColor = (opt.value == "accent")
                            local btnText2 = self:GetFontString()
                            if btnText2 then btnText2:SetText(opt.text) end
                            RefreshPreview()
                        end,
                    })
                end
                if GUI.ShowDropdownMenu then
                    GUI:ShowDropdownMenu(self, menuItems)
                end
            end)
        end
        sy = sy - FORM_ROW

        sy = P(GUI:CreateFormColorPicker(body, "Custom Bar Color", "barColor", db, RefreshPreview), body, sy)

        -- Background
        sy = P(GUI:CreateFormCheckbox(body, "Override Background Color", "barBgOverride", db, RefreshPreview), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", "barBackgroundColor", db, RefreshPreview), body, sy)

        -- Border override
        sy = P(GUI:CreateFormCheckbox(body, "Override Border Color", "borderOverride", db, RefreshPreview), body, sy)
        P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", db, RefreshPreview), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- TEXT & DISPLAY
    ---------------------------------------------------------------------------
    CreateCollapsible("Text & Display", 6 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Show Text", "showText", db, RefreshPreview), body, sy)

        local textFormatOptions = {
            { value = "stage_pct", text = "Stage 3 — 67%" },
            { value = "pct_only", text = "67%" },
            { value = "stage_only", text = "Stage 3" },
            { value = "name_pct", text = "Prey Name — 67%" },
        }
        sy = P(GUI:CreateFormDropdown(body, "Text Format", textFormatOptions, "textFormat", db, RefreshPreview), body, sy)

        sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 18, 1, "textSize", db, RefreshPreview), body, sy)

        sy = P(GUI:CreateFormCheckbox(body, "Show Tick Marks", "showTickMarks", db, RefreshPreview), body, sy)

        local tickStyleOptions = {
            { value = "thirds", text = "Thirds (33% / 66%)" },
            { value = "quarters", text = "Quarters (25% / 50% / 75%)" },
        }
        sy = P(GUI:CreateFormDropdown(body, "Tick Style", tickStyleOptions, "tickStyle", db, RefreshPreview), body, sy)

        P(GUI:CreateFormCheckbox(body, "Show Spark", "showSpark", db, RefreshPreview), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- SOUNDS
    ---------------------------------------------------------------------------
    CreateCollapsible("Sounds", 5 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Sounds", "soundEnabled", db, nil), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Stage 2 Sound", "soundStage2", db, nil), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Stage 3 Sound", "soundStage3", db, nil), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Stage 4 Sound", "soundStage4", db, nil), body, sy)
        P(GUI:CreateFormCheckbox(body, "Completion Sound", "completionSound", db, nil), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- AMBUSH ALERTS
    ---------------------------------------------------------------------------
    CreateCollapsible("Ambush Alerts", 4 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Ambush Alerts", "ambushAlertEnabled", db, nil), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Ambush Sound", "ambushSoundEnabled", db, nil), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Ambush Glow Effect", "ambushGlowEnabled", db, nil), body, sy)
        P(GUI:CreateFormSlider(body, "Glow Duration (sec)", 2, 15, 1, "ambushDuration", db, nil), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- VISIBILITY
    ---------------------------------------------------------------------------
    CreateCollapsible("Visibility", 4 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Replace Default Prey Indicator", "replaceDefaultIndicator", db, function()
            if ns.QUI_PreyTracker and ns.QUI_PreyTracker.ToggleDefaultIndicator then
                ns.QUI_PreyTracker.ToggleDefaultIndicator(db.replaceDefaultIndicator)
            end
        end), body, sy)

        sy = P(GUI:CreateFormCheckbox(body, "Auto-Hide When No Progress", "autoHide", db, Refresh), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide in Instances", "hideInInstances", db, Refresh), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Outside Prey Zone", "hideOutsidePreyZone", db, Refresh), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- HUNT SCANNER
    ---------------------------------------------------------------------------
    CreateCollapsible("Hunt Scanner", 2 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Hunt Scanner", "huntScannerEnabled", db, nil), body, sy)

        local hint = GUI:CreateLabel(body, "Shows available hunts when visiting a hunt table NPC.", 11, C.textMuted)
        hint:SetPoint("TOPLEFT", 0, sy)
        hint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        hint:SetJustifyH("LEFT")
        hint:SetWordWrap(true)
        hint:SetHeight(20)
    end)

    ---------------------------------------------------------------------------
    -- CURRENCY TRACKER
    ---------------------------------------------------------------------------
    CreateCollapsible("Currency Tracker", 3 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Currency Tooltip", "currencyEnabled", db, nil), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Session Gains", "currencyShowSession", db, nil), body, sy)
        P(GUI:CreateFormCheckbox(body, "Show Weekly Progress", "currencyShowWeekly", db, nil), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- PREVIEW BUTTON
    ---------------------------------------------------------------------------
    local previewSection = CreateFrame("Frame", nil, content)
    previewSection:SetHeight(40)
    previewSection:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, 0)
    previewSection:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)
    table.insert(sections, previewSection)

    local previewBtn = GUI:CreateButton(previewSection, "Toggle Preview", 140, 28, function()
        if _G.QUI_TogglePreyTrackerPreview then
            local state = ns.QUI_PreyTracker and ns.QUI_PreyTracker.GetState and ns.QUI_PreyTracker.GetState()
            local isPreview = state and state.isPreviewMode
            _G.QUI_TogglePreyTrackerPreview(not isPreview)
        end
    end)
    previewBtn:SetPoint("TOPLEFT", 0, -6)

    relayout()
    return scroll
end
