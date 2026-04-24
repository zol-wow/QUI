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

    local sections, relayout, CreateCollapsible = Shared.CreateTilePage(content, PADDING)

    ---------------------------------------------------------------------------
    -- GENERAL
    ---------------------------------------------------------------------------
    CreateCollapsible("General", 5 * FORM_ROW + 20, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Prey Tracker", "enabled", db, Refresh,
            { description = "Enable the prey tracker bar that shows your hunt progress from the Midnight prey system. Requires an active prey hunt quest." }), body, sy)

        local enableHint = GUI:CreateLabel(body, "Tracks prey hunting progress from the Midnight prey system. Requires an active prey hunt quest.", 11, C.textMuted)
        enableHint:SetPoint("TOPLEFT", 0, sy)
        enableHint:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        enableHint:SetJustifyH("LEFT")
        enableHint:SetWordWrap(true)
        enableHint:SetHeight(28)
        sy = sy - 32

        sy = P(GUI:CreateFormSlider(body, "Bar Width", 100, 500, 1, "width", db, RefreshPreview, nil,
            { description = "Width of the prey tracker bar in pixels." }), body, sy)
        sy = P(GUI:CreateFormSlider(body, "Bar Height", 10, 40, 1, "height", db, RefreshPreview, nil,
            { description = "Height of the prey tracker bar in pixels." }), body, sy)
        P(GUI:CreateFormSlider(body, "Border Size", 0, 3, 1, "borderSize", db, RefreshPreview, nil,
            { description = "Thickness of the bar's border in pixels. 0 removes the border entirely." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- BAR APPEARANCE
    ---------------------------------------------------------------------------
    CreateCollapsible("Bar Appearance", 7 * FORM_ROW + 8, function(body)
        local sy = -4

        -- Texture dropdown
        local textureList = Shared.GetTextureList()
        sy = P(GUI:CreateFormDropdown(body, "Bar Texture", textureList, "texture", db, RefreshPreview,
            { description = "Status bar texture used to fill the prey tracker bar." }), body, sy)

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
        end, { description = "How the prey tracker bar is colored. Accent uses the addon accent, Class uses your class color, Custom uses the picker below." })
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

        sy = P(GUI:CreateFormColorPicker(body, "Custom Bar Color", "barColor", db, RefreshPreview, nil,
            { description = "Custom bar fill color used when Bar Color Mode is set to Custom Color." }), body, sy)

        -- Background
        sy = P(GUI:CreateFormCheckbox(body, "Override Background Color", "barBgOverride", db, RefreshPreview,
            { description = "Use a custom color for the bar background instead of the default subtle fill." }), body, sy)
        sy = P(GUI:CreateFormColorPicker(body, "Background Color", "barBackgroundColor", db, RefreshPreview, nil,
            { description = "Background color applied when the override above is enabled." }), body, sy)

        -- Border override
        sy = P(GUI:CreateFormCheckbox(body, "Override Border Color", "borderOverride", db, RefreshPreview,
            { description = "Use a custom color for the bar border instead of inheriting from the global skin." }), body, sy)
        P(GUI:CreateFormColorPicker(body, "Border Color", "borderColor", db, RefreshPreview, nil,
            { description = "Border color applied when the override above is enabled." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- TEXT & DISPLAY
    ---------------------------------------------------------------------------
    CreateCollapsible("Text & Display", 6 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Show Text", "showText", db, RefreshPreview,
            { description = "Display the progress text on top of the prey tracker bar." }), body, sy)

        local textFormatOptions = {
            { value = "stage_pct", text = "Stage 3 — 67%" },
            { value = "pct_only", text = "67%" },
            { value = "stage_only", text = "Stage 3" },
            { value = "name_pct", text = "Prey Name — 67%" },
        }
        sy = P(GUI:CreateFormDropdown(body, "Text Format", textFormatOptions, "textFormat", db, RefreshPreview,
            { description = "Format of the overlay text. Choose whether to show the stage, the percentage, the prey name, or a combination." }), body, sy)

        sy = P(GUI:CreateFormSlider(body, "Font Size", 8, 18, 1, "textSize", db, RefreshPreview, nil,
            { description = "Font size used for the progress text." }), body, sy)

        sy = P(GUI:CreateFormCheckbox(body, "Show Tick Marks", "showTickMarks", db, RefreshPreview,
            { description = "Show tick marks on the bar at the stage boundaries configured by Tick Style." }), body, sy)

        local tickStyleOptions = {
            { value = "thirds", text = "Thirds (33% / 66%)" },
            { value = "quarters", text = "Quarters (25% / 50% / 75%)" },
        }
        sy = P(GUI:CreateFormDropdown(body, "Tick Style", tickStyleOptions, "tickStyle", db, RefreshPreview,
            { description = "Where tick marks are drawn. Thirds matches prey stages; Quarters is purely visual." }), body, sy)

        P(GUI:CreateFormCheckbox(body, "Show Spark", "showSpark", db, RefreshPreview,
            { description = "Show a bright spark at the leading edge of the filled portion of the bar." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- SOUNDS
    ---------------------------------------------------------------------------
    CreateCollapsible("Sounds", 5 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Sounds", "soundEnabled", db, nil,
            { description = "Master toggle for prey tracker audio cues. Individual stage sounds below won't play unless this is enabled." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Stage 2 Sound", "soundStage2", db, nil,
            { description = "Play a sound when you reach hunt stage 2." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Stage 3 Sound", "soundStage3", db, nil,
            { description = "Play a sound when you reach hunt stage 3." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Stage 4 Sound", "soundStage4", db, nil,
            { description = "Play a sound when you reach hunt stage 4." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Completion Sound", "completionSound", db, nil,
            { description = "Play a sound when the hunt finishes and the prey spawns." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- AMBUSH ALERTS
    ---------------------------------------------------------------------------
    CreateCollapsible("Ambush Alerts", 4 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Ambush Alerts", "ambushAlertEnabled", db, nil,
            { description = "Show an alert when the prey enters an ambushable state so you can position for the takedown." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Ambush Sound", "ambushSoundEnabled", db, nil,
            { description = "Play a distinct sound when the ambush alert fires." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Ambush Glow Effect", "ambushGlowEnabled", db, nil,
            { description = "Flash a glow effect on the prey tracker bar when an ambush is available." }), body, sy)
        P(GUI:CreateFormSlider(body, "Glow Duration (sec)", 2, 15, 1, "ambushDuration", db, nil, nil,
            { description = "How long the ambush glow remains visible, in seconds." }), body, sy)
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
        end, { description = "Hide the default Blizzard prey indicator so only the QUI tracker is shown." }), body, sy)

        sy = P(GUI:CreateFormCheckbox(body, "Auto-Hide When No Progress", "autoHide", db, Refresh,
            { description = "Hide the bar when no prey hunt is active. Turn off to keep a placeholder bar visible at all times." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Hide in Instances", "hideInInstances", db, Refresh,
            { description = "Hide the prey tracker bar while you are inside dungeons, raids, and other instances." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Hide Outside Prey Zone", "hideOutsidePreyZone", db, Refresh,
            { description = "Hide the bar whenever you leave the zone the current prey belongs to." }), body, sy)
    end)

    ---------------------------------------------------------------------------
    -- HUNT SCANNER
    ---------------------------------------------------------------------------
    CreateCollapsible("Hunt Scanner", 2 * FORM_ROW + 8, function(body)
        local sy = -4

        sy = P(GUI:CreateFormCheckbox(body, "Enable Hunt Scanner", "huntScannerEnabled", db, nil,
            { description = "Show a list of available hunts when you interact with a hunt table NPC, so you can pick the best prey at a glance." }), body, sy)

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

        sy = P(GUI:CreateFormCheckbox(body, "Enable Currency Tooltip", "currencyEnabled", db, nil,
            { description = "Add prey-related currency tracking details to the bag and currency tooltips." }), body, sy)
        sy = P(GUI:CreateFormCheckbox(body, "Show Session Gains", "currencyShowSession", db, nil,
            { description = "Include how much of each prey currency you've earned in the current play session in the tooltip." }), body, sy)
        P(GUI:CreateFormCheckbox(body, "Show Weekly Progress", "currencyShowWeekly", db, nil,
            { description = "Include progress toward weekly prey currency caps in the tooltip." }), body, sy)
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
