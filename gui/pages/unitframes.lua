--[[
    QUI Unit Frames Options
    Extracted from qui_options.lua for better organization
    Contains the CreateUnitFramesPage function
]]

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
local RefreshUnitFrames = Shared.RefreshUnitFrames
local NINE_POINT_ANCHOR_OPTIONS = Shared.NINE_POINT_ANCHOR_OPTIONS

---------------------------------------------------------------------------
-- PAGE: Unit Frames (Single Frames & Castbars)
---------------------------------------------------------------------------
local function CreateUnitFramesPage(parent)
    local scroll, content = CreateScrollableContent(parent)
    local db = GetDB()

    -- Get the new unit frames database
    local function GetUFDB()
        return db and db.quiUnitFrames
    end

    -- Refresh function for new unit frames
    local function RefreshNewUF()
        if _G.QUI_RefreshUnitFrames then
            _G.QUI_RefreshUnitFrames()
        end
    end

    -- Build the General tab content
    local function BuildGeneralTab(tabContent)
        local y = -10
        local PAD = 10
        local FORM_ROW = 32
        local ufdb = GetUFDB()

        -- Set search context for auto-registration
        GUI:SetSearchContext({tabIndex = 2, tabName = "Single Frames & Castbars", subTabIndex = 1, subTabName = "General"})

        if not ufdb then
            local info = GUI:CreateLabel(tabContent, "Unit frame settings not available - database not loaded", 12, C.textMuted)
            info:SetPoint("TOPLEFT", PAD, y)
            tabContent:SetHeight(100)
            return
        end

        -- Use the main profile general settings (not ufdb.general)
        local general = db.general
        if not general then
            db.general = {}
            general = db.general
        end

        -- Enable checkbox
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable Unitframes (Req. Reload)", "enabled", ufdb, RefreshNewUF)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- EDIT MODE section
        local editHeader = GUI:CreateSectionHeader(tabContent, "Positioning")
        editHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - editHeader.gap

        local editDesc = GUI:CreateLabel(tabContent, "Toggle Edit Mode to drag and reposition unit frames. Or use /qui editmode", 11, C.textMuted)
        editDesc:SetPoint("TOPLEFT", PAD, y)
        editDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        editDesc:SetJustifyH("LEFT")
        y = y - 24

        -- Edit Mode button (form style)
        local editContainer = CreateFrame("Frame", nil, tabContent)
        editContainer:SetHeight(FORM_ROW)
        editContainer:SetPoint("TOPLEFT", PAD, y)
        editContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local editLabel = editContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        editLabel:SetPoint("LEFT", 0, 0)
        editLabel:SetText("Edit Mode")
        editLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        local editModeBtn = CreateFrame("Button", nil, editContainer, "BackdropTemplate")
        editModeBtn:SetSize(120, 24)
        editModeBtn:SetPoint("LEFT", editContainer, "LEFT", 180, 0)
        editModeBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        editModeBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        editModeBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

        local editBtnText = editModeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        editBtnText:SetPoint("CENTER")
        editBtnText:SetText("Toggle")
        editBtnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        editModeBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        end)
        editModeBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end)
        editModeBtn:SetScript("OnClick", function()
            if _G.QUI_ToggleUnitFrameEditMode then
                _G.QUI_ToggleUnitFrameEditMode()
            end
        end)
        y = y - FORM_ROW - 10

        -- Store widget refs for BOTH sections (bidirectional conditional disable)
        local defaultWidgets = {}
        local darkModeWidgets = {}

        -- Helper to update enable states based on dark mode toggle
        local function UpdateDarkModeWidgetStates()
            local darkModeOn = general.darkMode
            -- Default widgets: enabled when dark mode OFF
            if defaultWidgets.healthColor then defaultWidgets.healthColor:SetEnabled(not darkModeOn) end
            if defaultWidgets.bgColor then defaultWidgets.bgColor:SetEnabled(not darkModeOn) end
            if defaultWidgets.opacity then defaultWidgets.opacity:SetEnabled(not darkModeOn) end
            -- Darkmode widgets: enabled when dark mode ON
            if darkModeWidgets.healthColor then darkModeWidgets.healthColor:SetEnabled(darkModeOn) end
            if darkModeWidgets.bgColor then darkModeWidgets.bgColor:SetEnabled(darkModeOn) end
            if darkModeWidgets.opacity then darkModeWidgets.opacity:SetEnabled(darkModeOn) end
        end

        -- DEFAULT UNITFRAME COLORS section
        local defaultHeader = GUI:CreateSectionHeader(tabContent, "Default Unitframe Colors")
        defaultHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - defaultHeader.gap

        local defaultDesc = GUI:CreateLabel(tabContent, "Colors and opacity applied to unit frames when Dark Mode is disabled.", 11, C.textMuted)
        defaultDesc:SetPoint("TOPLEFT", PAD, y)
        defaultDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultDesc:SetJustifyH("LEFT")
        y = y - 24

        -- Use Class Colors toggle (greys out Default Health Color when ON)
        local defUseClassColor = GUI:CreateFormCheckbox(tabContent, "Use Class Colors", "defaultUseClassColor", general, function()
            RefreshNewUF()
            -- Grey out health color picker when class colors is enabled
            if defaultWidgets.healthColor then
                defaultWidgets.healthColor:SetEnabled(not general.defaultUseClassColor)
            end
        end)
        defUseClassColor:SetPoint("TOPLEFT", PAD, y)
        defUseClassColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.useClassColor = defUseClassColor
        y = y - FORM_ROW

        -- Default Health Color (greyed out when Use Class Colors is ON)
        local defHealthColor = GUI:CreateFormColorPicker(tabContent, "Default Health Color", "defaultHealthColor", general, RefreshNewUF, { noAlpha = true })
        defHealthColor:SetPoint("TOPLEFT", PAD, y)
        defHealthColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.healthColor = defHealthColor
        defHealthColor:SetEnabled(not general.defaultUseClassColor)  -- Initial state
        y = y - FORM_ROW

        -- Default Background Color
        local defBgColor = GUI:CreateFormColorPicker(tabContent, "Default Background Color", "defaultBgColor", general, RefreshNewUF, { noAlpha = true })
        defBgColor:SetPoint("TOPLEFT", PAD, y)
        defBgColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.bgColor = defBgColor
        y = y - FORM_ROW

        -- Health Opacity slider
        local defHealthOpacity = GUI:CreateFormSlider(tabContent, "Health Opacity", 0.1, 1.0, 0.01, "defaultHealthOpacity", general, RefreshNewUF)
        defHealthOpacity:SetPoint("TOPLEFT", PAD, y)
        defHealthOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.healthOpacity = defHealthOpacity
        y = y - FORM_ROW

        -- Background Opacity slider
        local defBgOpacity = GUI:CreateFormSlider(tabContent, "Background Opacity", 0.1, 1.0, 0.01, "defaultBgOpacity", general, RefreshNewUF)
        defBgOpacity:SetPoint("TOPLEFT", PAD, y)
        defBgOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        defaultWidgets.bgOpacity = defBgOpacity
        y = y - FORM_ROW - 10

        -- DARK MODE section
        local darkHeader = GUI:CreateSectionHeader(tabContent, "Darkmode For Unitframes")
        darkHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - darkHeader.gap

        local darkDesc = GUI:CreateLabel(tabContent, "Instantly applies dark flat colors to all unit frame health bars.", 11, C.textMuted)
        darkDesc:SetPoint("TOPLEFT", PAD, y)
        darkDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkDesc:SetJustifyH("LEFT")
        y = y - 24

        local darkEnable = GUI:CreateFormCheckbox(tabContent, "Enable Dark Mode", "darkMode", general, function()
            RefreshNewUF()
            UpdateDarkModeWidgetStates()
        end)
        darkEnable:SetPoint("TOPLEFT", PAD, y)
        darkEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Darkmode Health Color (no alpha - pure RGB)
        local healthColor = GUI:CreateFormColorPicker(tabContent, "Darkmode Health Color", "darkModeHealthColor", general, RefreshNewUF, { noAlpha = true })
        healthColor:SetPoint("TOPLEFT", PAD, y)
        healthColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.healthColor = healthColor
        y = y - FORM_ROW

        -- Darkmode Background Color (no alpha - pure RGB)
        local bgColor = GUI:CreateFormColorPicker(tabContent, "Darkmode Background Color", "darkModeBgColor", general, RefreshNewUF, { noAlpha = true })
        bgColor:SetPoint("TOPLEFT", PAD, y)
        bgColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.bgColor = bgColor
        y = y - FORM_ROW

        -- Darkmode Health Opacity slider
        local dmHealthOpacity = GUI:CreateFormSlider(tabContent, "Darkmode Health Opacity", 0.1, 1.0, 0.01, "darkModeHealthOpacity", general, RefreshNewUF)
        dmHealthOpacity:SetPoint("TOPLEFT", PAD, y)
        dmHealthOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.healthOpacity = dmHealthOpacity
        y = y - FORM_ROW

        -- Darkmode Background Opacity slider
        local dmBgOpacity = GUI:CreateFormSlider(tabContent, "Darkmode Background Opacity", 0.1, 1.0, 0.01, "darkModeBgOpacity", general, RefreshNewUF)
        dmBgOpacity:SetPoint("TOPLEFT", PAD, y)
        dmBgOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        darkModeWidgets.bgOpacity = dmBgOpacity
        y = y - FORM_ROW - 10

        -- Set initial enable/disable states for both sections
        UpdateDarkModeWidgetStates()

        -- MASTER TEXT COLOR OVERRIDES section
        local textHeader = GUI:CreateSectionHeader(tabContent, "Text Class Color/React Color Overrides (Recommended For Dark Mode)")
        textHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - textHeader.gap

        local textDesc = GUI:CreateLabel(tabContent, "Apply class/reaction color to text across ALL unit frames. When enabled, master toggles override individual frame settings.", 11, C.textMuted)
        textDesc:SetPoint("TOPLEFT", PAD, y)
        textDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textDesc:SetJustifyH("LEFT")
        textDesc:SetWordWrap(true)
        textDesc:SetHeight(30)
        y = y - 40

        local masterNameText = GUI:CreateFormCheckbox(tabContent, "Color ALL Name Text", "masterColorNameText", general, RefreshNewUF)
        masterNameText:SetPoint("TOPLEFT", PAD, y)
        masterNameText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local masterHealthText = GUI:CreateFormCheckbox(tabContent, "Color ALL Health Text", "masterColorHealthText", general, RefreshNewUF)
        masterHealthText:SetPoint("TOPLEFT", PAD, y)
        masterHealthText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local masterPowerText = GUI:CreateFormCheckbox(tabContent, "Color ALL Power Text", "masterColorPowerText", general, RefreshNewUF)
        masterPowerText:SetPoint("TOPLEFT", PAD, y)
        masterPowerText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local masterCastbarText = GUI:CreateFormCheckbox(tabContent, "Color ALL Castbar Text", "masterColorCastbarText", general, RefreshNewUF)
        masterCastbarText:SetPoint("TOPLEFT", PAD, y)
        masterCastbarText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local masterToTText = GUI:CreateFormCheckbox(tabContent, "Color ALL ToT Text", "masterColorToTText", general, RefreshNewUF)
        masterToTText:SetPoint("TOPLEFT", PAD, y)
        masterToTText:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- TOOLTIPS SECTION
        y = y - 10

        local tooltipHeader = GUI:CreateSectionHeader(tabContent, "Tooltips on QUI Unitframes")
        tooltipHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - tooltipHeader.gap

        local tooltipCheck = GUI:CreateFormCheckbox(tabContent, "Show Tooltip for Unitframes", "showTooltips", ufdb.general, RefreshNewUF)
        tooltipCheck:SetPoint("TOPLEFT", PAD, y)
        tooltipCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Smoother Updates section
        local smoothHeader = GUI:CreateSectionHeader(tabContent, "Smoother Updates")
        smoothHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - smoothHeader.gap

        local smoothDesc = GUI:CreateLabel(tabContent, "Target, Focus, and Boss castbars are throttled to 60 FPS for CPU efficiency. Enable this option if you prefer maximum smoothness and don't mind the extra CPU usage.", 11, C.textMuted)
        smoothDesc:SetPoint("TOPLEFT", PAD, y)
        smoothDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        smoothDesc:SetJustifyH("LEFT")
        y = y - 24

        local smoothCheck = GUI:CreateFormCheckbox(tabContent, "Smoother Animation", "smootherAnimation", ufdb.general, RefreshNewUF)
        smoothCheck:SetPoint("TOPLEFT", PAD, y)
        smoothCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Hostility Color Customization section
        local hostilityHeader = GUI:CreateSectionHeader(tabContent, "Hostility Color Customization")
        hostilityHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - hostilityHeader.gap

        local hostilityDesc = GUI:CreateLabel(tabContent, "Customize the colors used for hostile, neutral, and friendly NPCs on unit frames that have 'Use Hostility Color' enabled.", 11, C.textMuted)
        hostilityDesc:SetPoint("TOPLEFT", PAD, y)
        hostilityDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        hostilityDesc:SetJustifyH("LEFT")
        y = y - 24

        local hostileColor = GUI:CreateFormColorPicker(tabContent, "Hostile Color", "hostilityColorHostile", general, RefreshNewUF, { noAlpha = true })
        hostileColor:SetPoint("TOPLEFT", PAD, y)
        hostileColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local neutralColor = GUI:CreateFormColorPicker(tabContent, "Neutral Color", "hostilityColorNeutral", general, RefreshNewUF, { noAlpha = true })
        neutralColor:SetPoint("TOPLEFT", PAD, y)
        neutralColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local friendlyColor = GUI:CreateFormColorPicker(tabContent, "Friendly Color", "hostilityColorFriendly", general, RefreshNewUF, { noAlpha = true })
        friendlyColor:SetPoint("TOPLEFT", PAD, y)
        friendlyColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        tabContent:SetHeight(math.abs(y) + 20)
    end

    -- Build unit-specific tab content (Player, Target, etc.)
    local function BuildUnitTab(tabContent, unitKey)
        local y = -10
        local PAD = 10
        local FORM_ROW = 32
        local ufdb = GetUFDB()

        -- Set search context for widget auto-registration (dynamic based on unitKey)
        local unitSubTabs = {
            player = {index = 2, name = "Player"},
            target = {index = 3, name = "Target"},
            targettarget = {index = 4, name = "ToT"},
            pet = {index = 5, name = "Pet"},
            focus = {index = 6, name = "Focus"},
            boss = {index = 7, name = "Boss"},
        }
        local subTabInfo = unitSubTabs[unitKey] or {index = 2, name = unitKey}
        GUI:SetSearchContext({tabIndex = 2, tabName = "Single Frames & Castbars", subTabIndex = subTabInfo.index, subTabName = subTabInfo.name})

        if not ufdb or not ufdb[unitKey] then
            local info = GUI:CreateLabel(tabContent, "Unit frame settings not available for " .. unitKey, 12, C.textMuted)
            info:SetPoint("TOPLEFT", PAD, y)
            tabContent:SetHeight(100)
            return
        end

        local unitDB = ufdb[unitKey]

        -- Refresh function for this specific unit
        local function RefreshUnit()
            RefreshNewUF()
            -- Preview state is now in database, CreateCastbar will handle it
        end

        -- Refresh function specifically for aura settings
        local function RefreshAuras()
            RefreshNewUF()
            -- Refresh aura preview if active (re-render with new settings)
            local QUI_UF = ns.QUI_UnitFrames
            if QUI_UF and QUI_UF.auraPreviewMode then
                if QUI_UF.auraPreviewMode[unitKey .. "_debuff"] then
                    _G.QUI_ShowAuraPreview(unitKey, "debuff")
                end
                if QUI_UF.auraPreviewMode[unitKey .. "_buff"] then
                    _G.QUI_ShowAuraPreview(unitKey, "buff")
                end
            end
            -- Refresh real auras if not in preview mode
            if _G.QUI_RefreshAuras then
                _G.QUI_RefreshAuras(unitKey)
            end
        end

        -- Preview button row (form style)
        local previewContainer = CreateFrame("Frame", nil, tabContent)
        previewContainer:SetHeight(FORM_ROW)
        previewContainer:SetPoint("TOPLEFT", PAD, y)
        previewContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local previewLabel = previewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        previewLabel:SetPoint("LEFT", 0, 0)
        previewLabel:SetText("Frame Preview")
        previewLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Toggle track (pill-shaped, matches CreateFormToggle)
        local previewTrack = CreateFrame("Button", nil, previewContainer, "BackdropTemplate")
        previewTrack:SetSize(40, 20)
        previewTrack:SetPoint("LEFT", previewContainer, "LEFT", 180, 0)
        previewTrack:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})

        -- Thumb (sliding circle)
        local previewThumb = CreateFrame("Frame", nil, previewTrack, "BackdropTemplate")
        previewThumb:SetSize(16, 16)
        previewThumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        previewThumb:SetBackdropColor(0.95, 0.95, 0.95, 1)
        previewThumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
        previewThumb:SetFrameLevel(previewTrack:GetFrameLevel() + 1)

        -- Initialize state (preview defaults to off when panel opens)
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
            if isPreviewOn then
                if _G.QUI_ShowUnitFramePreview then _G.QUI_ShowUnitFramePreview(unitKey) end
            else
                if _G.QUI_HideUnitFramePreview then _G.QUI_HideUnitFramePreview(unitKey) end
            end
        end)
        y = y - FORM_ROW

        -- Enable checkbox (requires reload)
        local displayNames = {targettarget = "Target of Target"}
        local frameName = displayNames[unitKey] or unitKey:gsub("^%l", string.upper)
        local enableCheck = GUI:CreateFormCheckbox(tabContent, "Enable " .. frameName .. " Frame", "enabled", unitDB, function()
            GUI:ShowConfirmation({
                title = "Reload UI?",
                message = "Enabling or disabling unit frames requires a UI reload to take effect.",
                acceptText = "Reload",
                cancelText = "Later",
                onAccept = function() QUI:SafeReload() end,
            })
        end)
        enableCheck:SetPoint("TOPLEFT", PAD, y)
        enableCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- FRAME SIZE section
        local sizeHeader = GUI:CreateSectionHeader(tabContent, "Frame Size & Position")
        sizeHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - sizeHeader.gap

        -- Size sliders (form style)
        -- For player unit, wrap callback to also update locked castbar width
        local widthCallback = RefreshUnit
        if unitKey == "player" then
            widthCallback = function()
                RefreshUnit()
                if _G.QUI_UpdateLockedCastbarToFrame then
                    _G.QUI_UpdateLockedCastbarToFrame()
                end
            end
        end
        local widthSlider = GUI:CreateFormSlider(tabContent, "Width", 100, 500, 1, "width", unitDB, widthCallback)
        widthSlider:SetPoint("TOPLEFT", PAD, y)
        widthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local heightSlider = GUI:CreateFormSlider(tabContent, "Height", 20, 100, 1, "height", unitDB, RefreshUnit)
        heightSlider:SetPoint("TOPLEFT", PAD, y)
        heightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local borderSizeSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 5, 1, "borderSize", unitDB, RefreshUnit)
        borderSizeSlider:SetPoint("TOPLEFT", PAD, y)
        borderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Boss frames get spacing slider
        if unitKey == "boss" then
            local spacingSlider = GUI:CreateFormSlider(tabContent, "Spacing", 0, 100, 1, "spacing", unitDB, RefreshUnit)
            spacingSlider:SetPoint("TOPLEFT", PAD, y)
            spacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- Position sliders
        local offsetXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -3000, 3000, 1, "offsetX", unitDB, RefreshUnit)
        offsetXSlider:SetPoint("TOPLEFT", PAD, y)
        offsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local offsetYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -3000, 3000, 1, "offsetY", unitDB, RefreshUnit)
        offsetYSlider:SetPoint("TOPLEFT", PAD, y)
        offsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Register sliders for real-time sync during Edit Mode
        if _G.QUI_RegisterEditModeSliders then
            _G.QUI_RegisterEditModeSliders(unitKey, offsetXSlider, offsetYSlider)
        end

        -- Frame Anchoring section (only for player and target)
        if unitKey == "player" or unitKey == "target" then
            local anchorHeader = GUI:CreateSectionHeader(tabContent, "Frame Anchoring")
            anchorHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - anchorHeader.gap

            -- Initialize defaults if needed
            if unitDB.anchorTo == nil then unitDB.anchorTo = "disabled" end
            if unitDB.anchorGap == nil then unitDB.anchorGap = 10 end
            if unitDB.anchorYOffset == nil then unitDB.anchorYOffset = 0 end

            -- Description text
            local anchorDesc = GUI:CreateLabel(tabContent,
                unitKey == "player"
                    and "Anchors frame to the LEFT edge of selected target. As the anchor width changes, this frame will reposition automatically."
                    or "Anchors frame to the RIGHT edge of selected target. As the anchor width changes, this frame will reposition automatically.",
                11, C.textMuted)
            anchorDesc:SetPoint("TOPLEFT", PAD, y)
            anchorDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            anchorDesc:SetJustifyH("LEFT")
            y = y - 36

            -- Forward declarations for sliders
            local anchorGapSlider, anchorYOffsetSlider

            -- Helper function to update slider enabled states
            local function UpdateAnchorSliderStates()
                local isAnchored = unitDB.anchorTo and unitDB.anchorTo ~= "disabled"
                if isAnchored then
                    anchorGapSlider:SetAlpha(1)
                    anchorGapSlider:EnableMouse(true)
                    anchorYOffsetSlider:SetAlpha(1)
                    anchorYOffsetSlider:EnableMouse(true)
                    offsetXSlider:SetAlpha(0.4)
                    offsetXSlider:EnableMouse(false)
                    offsetYSlider:SetAlpha(0.4)
                    offsetYSlider:EnableMouse(false)
                else
                    anchorGapSlider:SetAlpha(0.4)
                    anchorGapSlider:EnableMouse(false)
                    anchorYOffsetSlider:SetAlpha(0.4)
                    anchorYOffsetSlider:EnableMouse(false)
                    offsetXSlider:SetAlpha(1)
                    offsetXSlider:EnableMouse(true)
                    offsetYSlider:SetAlpha(1)
                    offsetYSlider:EnableMouse(true)
                end
            end

            -- Anchor dropdown with 5 options
            local anchorOptions = {
                {value = "disabled", text = "Disabled"},
                {value = "essential", text = "Essential CDM"},
                {value = "utility", text = "Utility CDM"},
                {value = "primary", text = "Primary Resource Bar"},
                {value = "secondary", text = "Secondary Resource Bar"},
            }
            local anchorDropdown = GUI:CreateFormDropdown(tabContent, "Anchor To", anchorOptions, "anchorTo", unitDB, function()
                RefreshUnit()
                if _G.QUI_UpdateAnchoredUnitFrames then
                    _G.QUI_UpdateAnchoredUnitFrames()
                end
                UpdateAnchorSliderStates()
            end)
            anchorDropdown:SetPoint("TOPLEFT", PAD, y)
            anchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Horizontal gap slider
            anchorGapSlider = GUI:CreateFormSlider(tabContent, "Horizontal Gap", 0, 100, 1, "anchorGap", unitDB, function()
                if _G.QUI_UpdateAnchoredUnitFrames then
                    _G.QUI_UpdateAnchoredUnitFrames()
                end
            end)
            anchorGapSlider:SetPoint("TOPLEFT", PAD, y)
            anchorGapSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Vertical offset slider
            anchorYOffsetSlider = GUI:CreateFormSlider(tabContent, "Vertical Offset", -200, 200, 1, "anchorYOffset", unitDB, function()
                if _G.QUI_UpdateAnchoredUnitFrames then
                    _G.QUI_UpdateAnchoredUnitFrames()
                end
            end)
            anchorYOffsetSlider:SetPoint("TOPLEFT", PAD, y)
            anchorYOffsetSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Set initial enabled state
            UpdateAnchorSliderStates()
        end

        -- Texture dropdown
        local textureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", unitDB, RefreshUnit)
        textureDropdown:SetPoint("TOPLEFT", PAD, y)
        textureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- COLORS section
        local colorHeader = GUI:CreateSectionHeader(tabContent, "Health Bar Colors")
        colorHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - colorHeader.gap

        -- Helper text explaining color priority (only for frames with hostility option)
        if unitKey ~= "player" then
            local colorDesc = GUI:CreateLabel(tabContent, "Class color for players, hostility color for NPCs. Custom color is the fallback.", 11, C.textMuted)
            colorDesc:SetPoint("TOPLEFT", PAD, y)
            colorDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            colorDesc:SetJustifyH("LEFT")
            y = y - 24
        end

        -- Store custom color reference for conditional disable
        local customColor = nil

        local classColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", unitDB, RefreshUnit)
        classColorCheck:SetPoint("TOPLEFT", PAD, y)
        classColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Hostility Color checkbox (for frames that can show varied unit types)
        if unitKey == "target" or unitKey == "focus" or unitKey == "targettarget" or unitKey == "pet" or unitKey == "boss" then
            local hostilityColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Hostility Color", "useHostilityColor", unitDB, function()
                RefreshUnit()
                -- Disable custom color when hostility is ON (covers all units)
                if customColor then
                    customColor:SetEnabled(not unitDB.useHostilityColor)
                end
            end)
            hostilityColorCheck:SetPoint("TOPLEFT", PAD, y)
            hostilityColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        customColor = GUI:CreateFormColorPicker(tabContent, "Custom Color", "customHealthColor", unitDB, RefreshUnit)
        customColor:SetPoint("TOPLEFT", PAD, y)
        customColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        -- Set initial enabled state based on hostility setting
        if unitKey == "target" or unitKey == "focus" or unitKey == "targettarget" or unitKey == "pet" or unitKey == "boss" then
            customColor:SetEnabled(not unitDB.useHostilityColor)
        end
        y = y - FORM_ROW

        -- ABSORB INDICATOR section
        local absorbHeader = GUI:CreateSectionHeader(tabContent, "Absorb Indicator")
        absorbHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - absorbHeader.gap

        if not unitDB.absorbs then
            unitDB.absorbs = {
                enabled = true,
                color = { 0.2, 0.8, 0.8 },
                opacity = 0.7,
                texture = "QUI Stripes",
            }
        end

        local absorbCheck = GUI:CreateFormCheckbox(tabContent, "Show Absorb Shields", "enabled", unitDB.absorbs, RefreshUnit)
        absorbCheck:SetPoint("TOPLEFT", PAD, y)
        absorbCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local absorbOpacity = GUI:CreateFormSlider(tabContent, "Opacity", 0, 1, 0.05, "opacity", unitDB.absorbs, RefreshUnit)
        absorbOpacity:SetPoint("TOPLEFT", PAD, y)
        absorbOpacity:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local absorbColor = GUI:CreateFormColorPicker(tabContent, "Absorb Color", "color", unitDB.absorbs, RefreshUnit)
        absorbColor:SetPoint("TOPLEFT", PAD, y)
        absorbColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local absorbTexture = GUI:CreateFormDropdown(tabContent, "Absorb Texture", GetTextureList(), "texture", unitDB.absorbs, RefreshUnit)
        absorbTexture:SetPoint("TOPLEFT", PAD, y)
        absorbTexture:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local absorbTextureDesc = GUI:CreateLabel(tabContent, "Supports SharedMedia textures. Install the SharedMedia addon to add your own.", 11, C.textMuted)
        absorbTextureDesc:SetPoint("TOPLEFT", PAD, y + 4)
        absorbTextureDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        absorbTextureDesc:SetJustifyH("LEFT")
        y = y - 20

        -- NAME TEXT section
        local nameHeader = GUI:CreateSectionHeader(tabContent, "Name Text")
        nameHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - nameHeader.gap

        local showNameCheck = GUI:CreateFormCheckbox(tabContent, "Show Name", "showName", unitDB, RefreshUnit)
        showNameCheck:SetPoint("TOPLEFT", PAD, y)
        showNameCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Anchor options for text positioning
        local anchorOptions = {
            {value = "TOPLEFT", text = "Top Left"},
            {value = "TOP", text = "Top Center"},
            {value = "TOPRIGHT", text = "Top Right"},
            {value = "LEFT", text = "Center Left"},
            {value = "CENTER", text = "Center"},
            {value = "RIGHT", text = "Center Right"},
            {value = "BOTTOMLEFT", text = "Bottom Left"},
            {value = "BOTTOM", text = "Bottom Center"},
            {value = "BOTTOMRIGHT", text = "Bottom Right"},
        }

        local nameSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 24, 1, "nameFontSize", unitDB, RefreshUnit)
        nameSizeSlider:SetPoint("TOPLEFT", PAD, y)
        nameSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local nameColorPicker = GUI:CreateFormColorPicker(tabContent, "Custom Name Text Color", "nameTextColor", unitDB, RefreshUnit)
        nameColorPicker:SetPoint("TOPLEFT", PAD, y)
        nameColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local nameAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Anchor", anchorOptions, "nameAnchor", unitDB, RefreshUnit)
        nameAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        nameAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local nameXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "nameOffsetX", unitDB, RefreshUnit)
        nameXSlider:SetPoint("TOPLEFT", PAD, y)
        nameXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local nameYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -50, 50, 1, "nameOffsetY", unitDB, RefreshUnit)
        nameYSlider:SetPoint("TOPLEFT", PAD, y)
        nameYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local nameTruncSlider = GUI:CreateFormSlider(tabContent, "Max Length (0=none)", 0, 30, 1, "maxNameLength", unitDB, RefreshUnit)
        nameTruncSlider:SetPoint("TOPLEFT", PAD, y)
        nameTruncSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- TARGET OF TARGET TEXT section (target only)
        if unitKey == "target" then
            local totHeader = GUI:CreateSectionHeader(tabContent, "Target Of Target Text")
            totHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - totHeader.gap

            local totCheck = GUI:CreateFormCheckbox(tabContent, "Show Inline Target-of-Target", "showInlineToT", unitDB, RefreshUnit)
            totCheck:SetPoint("TOPLEFT", PAD, y)
            totCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local totSepOptions = {
                {value = " >> ", text = ">>"},
                {value = " > ", text = ">"},
                {value = " - ", text = "-"},
                {value = " | ", text = "|"},
                {value = " -> ", text = "->"},
                {value = " —> ", text = "—>"},
                {value = " >>> ", text = ">>>"},
            }
            local totSepDropdown = GUI:CreateFormDropdown(tabContent, "ToT Separator", totSepOptions, "totSeparator", unitDB, RefreshUnit)
            totSepDropdown:SetPoint("TOPLEFT", PAD, y)
            totSepDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Store reference for enable/disable logic
            local totDividerWidgets = {}

            -- Toggle: Color Divider By Class/React
            local totDividerClassCheck = GUI:CreateFormCheckbox(tabContent, "Color Divider By Class/React", "totDividerUseClassColor", unitDB, function()
                RefreshUnit()
                -- Disable custom color picker when class color is enabled
                if totDividerWidgets.customColor then
                    totDividerWidgets.customColor:SetEnabled(not unitDB.totDividerUseClassColor)
                end
            end)
            totDividerClassCheck:SetPoint("TOPLEFT", PAD, y)
            totDividerClassCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Color Picker: Custom Divider Color (disabled when class color toggle is ON)
            local totDividerColor = GUI:CreateFormColorPicker(tabContent, "Custom Divider Color", "totDividerColor", unitDB, RefreshUnit)
            totDividerColor:SetPoint("TOPLEFT", PAD, y)
            totDividerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            totDividerWidgets.customColor = totDividerColor
            totDividerColor:SetEnabled(not unitDB.totDividerUseClassColor)  -- Initial state
            y = y - FORM_ROW

            local totCharLimitSlider = GUI:CreateFormSlider(tabContent, "ToT Name Character Limit", 0, 100, 1, "totNameCharLimit", unitDB, RefreshUnit)
            totCharLimitSlider:SetPoint("TOPLEFT", PAD, y)
            totCharLimitSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- HEALTH TEXT section
        local healthHeader = GUI:CreateSectionHeader(tabContent, "Health Text")
        healthHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - healthHeader.gap

        local showHealthCheck = GUI:CreateFormCheckbox(tabContent, "Show Health", "showHealth", unitDB, RefreshUnit)
        showHealthCheck:SetPoint("TOPLEFT", PAD, y)
        showHealthCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healthStyleOptions = {
            {value = "percent", text = "Percent Only (75%)"},
            {value = "absolute", text = "Value Only (45.2k)"},
            {value = "both", text = "Value | Percent"},
            {value = "both_reverse", text = "Percent | Value"},
            {value = "missing_percent", text = "Missing Percent (-25%)"},
            {value = "missing_value", text = "Missing Value (-12.5k)"},
        }
        local healthStyleDropdown = GUI:CreateFormDropdown(tabContent, "Display Style", healthStyleOptions, "healthDisplayStyle", unitDB, RefreshUnit)
        healthStyleDropdown:SetPoint("TOPLEFT", PAD, y)
        healthStyleDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healthDividerOptions = {
            {value = " | ", text = "|  (pipe)"},
            {value = " - ", text = "-  (dash)"},
            {value = " / ", text = "/  (slash)"},
            {value = " • ", text = "•  (dot)"},
        }
        local healthDividerDropdown = GUI:CreateFormDropdown(tabContent, "Divider", healthDividerOptions, "healthDivider", unitDB, RefreshUnit)
        healthDividerDropdown:SetPoint("TOPLEFT", PAD, y)
        healthDividerDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healthTextColorPicker = GUI:CreateFormColorPicker(tabContent, "Custom Health Text Color", "healthTextColor", unitDB, RefreshUnit)
        healthTextColorPicker:SetPoint("TOPLEFT", PAD, y)
        healthTextColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healthSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 24, 1, "healthFontSize", unitDB, RefreshUnit)
        healthSizeSlider:SetPoint("TOPLEFT", PAD, y)
        healthSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healthAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Anchor", anchorOptions, "healthAnchor", unitDB, RefreshUnit)
        healthAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        healthAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healthXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "healthOffsetX", unitDB, RefreshUnit)
        healthXSlider:SetPoint("TOPLEFT", PAD, y)
        healthXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local healthYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -50, 50, 1, "healthOffsetY", unitDB, RefreshUnit)
        healthYSlider:SetPoint("TOPLEFT", PAD, y)
        healthYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- POWER BAR section
        local powerHeader = GUI:CreateSectionHeader(tabContent, "Power Bar")
        powerHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - powerHeader.gap

        local showPowerCheck = GUI:CreateFormCheckbox(tabContent, "Show Power Bar", "showPowerBar", unitDB, RefreshUnit)
        showPowerCheck:SetPoint("TOPLEFT", PAD, y)
        showPowerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerHeightSlider = GUI:CreateFormSlider(tabContent, "Power Bar Height", 1, 20, 1, "powerBarHeight", unitDB, RefreshUnit)
        powerHeightSlider:SetPoint("TOPLEFT", PAD, y)
        powerHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerBorderCheck = GUI:CreateFormCheckbox(tabContent, "Power Bar Border", "powerBarBorder", unitDB, RefreshUnit)
        powerBorderCheck:SetPoint("TOPLEFT", PAD, y)
        powerBorderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerBarColorPicker  -- Forward declare for closure

        local powerBarUsePowerColor = GUI:CreateFormCheckbox(tabContent, "Use Power Type Color", "powerBarUsePowerColor", unitDB, function()
            RefreshUnit()
            -- Grey out color picker when power type color is enabled
            if powerBarColorPicker then
                powerBarColorPicker:SetEnabled(not unitDB.powerBarUsePowerColor)
            end
        end)
        powerBarUsePowerColor:SetPoint("TOPLEFT", PAD, y)
        powerBarUsePowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        powerBarColorPicker = GUI:CreateFormColorPicker(tabContent, "Custom Bar Color", "powerBarColor", unitDB, RefreshUnit)
        powerBarColorPicker:SetPoint("TOPLEFT", PAD, y)
        powerBarColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        -- Set initial state (greyed out if power type color is enabled)
        powerBarColorPicker:SetEnabled(not unitDB.powerBarUsePowerColor)
        y = y - FORM_ROW

        -- POWER TEXT section
        local powerTextHeader = GUI:CreateSectionHeader(tabContent, "Power Text")
        powerTextHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - powerTextHeader.gap

        local showPowerTextCheck = GUI:CreateFormCheckbox(tabContent, "Show Power Text", "showPowerText", unitDB, RefreshUnit)
        showPowerTextCheck:SetPoint("TOPLEFT", PAD, y)
        showPowerTextCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerTextFormatOptions = {
            {value = "percent", text = "Percent (75%)"},
            {value = "current", text = "Current (12.5k)"},
            {value = "both", text = "Both (12.5k | 75%)"},
        }
        local powerTextFormatDropdown = GUI:CreateFormDropdown(tabContent, "Display Format", powerTextFormatOptions, "powerTextFormat", unitDB, RefreshUnit)
        powerTextFormatDropdown:SetPoint("TOPLEFT", PAD, y)
        powerTextFormatDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerTextColorPicker  -- Forward declare for closure

        local powerTextUsePowerColor = GUI:CreateFormCheckbox(tabContent, "Use Power Type Color", "powerTextUsePowerColor", unitDB, function()
            RefreshUnit()
            if powerTextColorPicker then
                powerTextColorPicker:SetEnabled(not unitDB.powerTextUsePowerColor)
            end
        end)
        powerTextUsePowerColor:SetPoint("TOPLEFT", PAD, y)
        powerTextUsePowerColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        powerTextColorPicker = GUI:CreateFormColorPicker(tabContent, "Custom Power Text Color", "powerTextColor", unitDB, RefreshUnit)
        powerTextColorPicker:SetPoint("TOPLEFT", PAD, y)
        powerTextColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        powerTextColorPicker:SetEnabled(not unitDB.powerTextUsePowerColor)
        y = y - FORM_ROW

        local powerTextSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 24, 1, "powerTextFontSize", unitDB, RefreshUnit)
        powerTextSizeSlider:SetPoint("TOPLEFT", PAD, y)
        powerTextSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerTextAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Anchor", anchorOptions, "powerTextAnchor", unitDB, RefreshUnit)
        powerTextAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        powerTextAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerTextXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "powerTextOffsetX", unitDB, RefreshUnit)
        powerTextXSlider:SetPoint("TOPLEFT", PAD, y)
        powerTextXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local powerTextYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -50, 50, 1, "powerTextOffsetY", unitDB, RefreshUnit)
        powerTextYSlider:SetPoint("TOPLEFT", PAD, y)
        powerTextYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Helper to copy castbar settings from one unit to another
        local function CopyCastbarSettings(sourceDB, targetDB)
            if not sourceDB or not targetDB then return end
            local keys = {"width", "height", "offsetX", "offsetY", "fontSize", "borderSize", "maxLength", "texture", "showIcon", "enabled"}
            for _, key in ipairs(keys) do
                if sourceDB[key] ~= nil then
                    targetDB[key] = sourceDB[key]
                end
            end
            if sourceDB.color then
                targetDB.color = {sourceDB.color[1], sourceDB.color[2], sourceDB.color[3], sourceDB.color[4]}
            end
            if sourceDB.bgColor then
                targetDB.bgColor = {sourceDB.bgColor[1], sourceDB.bgColor[2], sourceDB.bgColor[3], sourceDB.bgColor[4]}
            end
        end

        -- CASTBAR section (for player, target, targettarget, focus, pet, boss)
        if unitKey == "player" or unitKey == "target" or unitKey == "targettarget" or unitKey == "focus" or unitKey == "pet" or unitKey == "boss" then
            -- Use dedicated castbar options module (it creates its own header)
            if ns.QUI_CastbarOptions and ns.QUI_CastbarOptions.BuildCastbarOptions then
                y = ns.QUI_CastbarOptions.BuildCastbarOptions(tabContent, unitKey, y, PAD, FORM_ROW, RefreshUnit, GetTextureList, NINE_POINT_ANCHOR_OPTIONS, GetUFDB, GetDB)
            end
        end

        -- Aura settings (all single unit frames)
        if unitKey == "player" or unitKey == "target" or unitKey == "focus"
           or unitKey == "pet" or unitKey == "targettarget" or unitKey == "boss" then
            if not unitDB.auras then unitDB.auras = {} end
            local auraDB = unitDB.auras
            if auraDB.showBuffs == nil then auraDB.showBuffs = false end
            if auraDB.showDebuffs == nil then auraDB.showDebuffs = false end
            if unitKey ~= "player" then
                if auraDB.onlyMyDebuffs == nil then auraDB.onlyMyDebuffs = true end
            end
            if auraDB.iconSize == nil then auraDB.iconSize = 22 end
            if auraDB.buffIconSize == nil then auraDB.buffIconSize = 22 end
            if auraDB.debuffAnchor == nil then auraDB.debuffAnchor = "TOPLEFT" end
            if auraDB.debuffGrow == nil then auraDB.debuffGrow = "RIGHT" end
            if auraDB.debuffOffsetX == nil then auraDB.debuffOffsetX = 0 end
            if auraDB.debuffOffsetY == nil then auraDB.debuffOffsetY = 2 end
            if auraDB.buffAnchor == nil then auraDB.buffAnchor = "BOTTOMLEFT" end
            if auraDB.buffGrow == nil then auraDB.buffGrow = "RIGHT" end
            if auraDB.buffOffsetX == nil then auraDB.buffOffsetX = 0 end
            if auraDB.buffOffsetY == nil then auraDB.buffOffsetY = -2 end
            if auraDB.debuffMaxIcons == nil then auraDB.debuffMaxIcons = 16 end
            if auraDB.buffMaxIcons == nil then auraDB.buffMaxIcons = 16 end

            local auraAnchorOptions = {
                {value = "TOPLEFT", text = "Top Left"},
                {value = "TOPRIGHT", text = "Top Right"},
                {value = "BOTTOMLEFT", text = "Bottom Left"},
                {value = "BOTTOMRIGHT", text = "Bottom Right"},
            }
            local growOptions = {
                {value = "LEFT", text = "Left"},
                {value = "RIGHT", text = "Right"},
                {value = "UP", text = "Up"},
                {value = "DOWN", text = "Down"},
            }
            local ninePointAnchorOptions = {
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

            -- === DEBUFF ICONS SECTION ===
            local debuffHeader = GUI:CreateSectionHeader(tabContent, "Debuff Icons")
            debuffHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - debuffHeader.gap

            local showDebuffsCheck = GUI:CreateFormCheckbox(tabContent, "Show Debuffs", "showDebuffs", auraDB, RefreshAuras)
            showDebuffsCheck:SetPoint("TOPLEFT", PAD, y)
            showDebuffsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local debuffHideSwipe = GUI:CreateFormCheckbox(tabContent, "Hide Duration Swipe", "debuffHideSwipe", auraDB, RefreshAuras)
            debuffHideSwipe:SetPoint("TOPLEFT", PAD, y)
            debuffHideSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            if unitKey ~= "player" then
                local onlyMyDebuffsCheck = GUI:CreateFormCheckbox(tabContent, "Only My Debuffs", "onlyMyDebuffs", auraDB, RefreshAuras)
                onlyMyDebuffsCheck:SetPoint("TOPLEFT", PAD, y)
                onlyMyDebuffsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW
            end

            -- Debuff Preview toggle (pill-shaped, matches Castbar Preview style)
            local debuffPreviewContainer = CreateFrame("Frame", nil, tabContent)
            debuffPreviewContainer:SetHeight(FORM_ROW)
            debuffPreviewContainer:SetPoint("TOPLEFT", PAD, y)
            debuffPreviewContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            local debuffPreviewLabel = debuffPreviewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            debuffPreviewLabel:SetPoint("LEFT", 0, 0)
            debuffPreviewLabel:SetText("Debuff Preview")
            debuffPreviewLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

            local debuffPreviewTrack = CreateFrame("Button", nil, debuffPreviewContainer, "BackdropTemplate")
            debuffPreviewTrack:SetSize(40, 20)
            debuffPreviewTrack:SetPoint("LEFT", debuffPreviewContainer, "LEFT", 180, 0)
            debuffPreviewTrack:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})

            local debuffPreviewThumb = CreateFrame("Frame", nil, debuffPreviewTrack, "BackdropTemplate")
            debuffPreviewThumb:SetSize(16, 16)
            debuffPreviewThumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
            debuffPreviewThumb:SetBackdropColor(0.95, 0.95, 0.95, 1)
            debuffPreviewThumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
            debuffPreviewThumb:SetFrameLevel(debuffPreviewTrack:GetFrameLevel() + 1)

            local isDebuffPreviewOn = false
            local function UpdateDebuffPreviewToggle(on)
                if on then
                    debuffPreviewTrack:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    debuffPreviewTrack:SetBackdropBorderColor(C.accent[1]*0.8, C.accent[2]*0.8, C.accent[3]*0.8, 1)
                    debuffPreviewThumb:ClearAllPoints()
                    debuffPreviewThumb:SetPoint("RIGHT", debuffPreviewTrack, "RIGHT", -2, 0)
                else
                    debuffPreviewTrack:SetBackdropColor(0.15, 0.18, 0.22, 1)
                    debuffPreviewTrack:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
                    debuffPreviewThumb:ClearAllPoints()
                    debuffPreviewThumb:SetPoint("LEFT", debuffPreviewTrack, "LEFT", 2, 0)
                end
            end
            UpdateDebuffPreviewToggle(isDebuffPreviewOn)

            debuffPreviewTrack:SetScript("OnClick", function()
                isDebuffPreviewOn = not isDebuffPreviewOn
                UpdateDebuffPreviewToggle(isDebuffPreviewOn)
                if isDebuffPreviewOn then
                    if _G.QUI_ShowAuraPreview then
                        _G.QUI_ShowAuraPreview(unitKey, "debuff")
                    end
                else
                    if _G.QUI_HideAuraPreview then
                        _G.QUI_HideAuraPreview(unitKey, "debuff")
                    end
                end
            end)
            y = y - FORM_ROW

            local auraIconSize = GUI:CreateFormSlider(tabContent, "Icon Size", 12, 50, 1, "iconSize", auraDB, RefreshAuras)
            auraIconSize:SetPoint("TOPLEFT", PAD, y)
            auraIconSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local debuffAnchorDrop = GUI:CreateFormDropdown(tabContent, "Anchor", auraAnchorOptions, "debuffAnchor", auraDB, RefreshAuras)
            debuffAnchorDrop:SetPoint("TOPLEFT", PAD, y)
            debuffAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local debuffGrowDrop = GUI:CreateFormDropdown(tabContent, "Grow Direction", growOptions, "debuffGrow", auraDB, RefreshAuras)
            debuffGrowDrop:SetPoint("TOPLEFT", PAD, y)
            debuffGrowDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local debuffMaxSlider = GUI:CreateFormSlider(tabContent, "Max Icons", 1, 32, 1, "debuffMaxIcons", auraDB, RefreshAuras)
            debuffMaxSlider:SetPoint("TOPLEFT", PAD, y)
            debuffMaxSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local debuffXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "debuffOffsetX", auraDB, RefreshAuras)
            debuffXSlider:SetPoint("TOPLEFT", PAD, y)
            debuffXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local debuffYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -100, 100, 1, "debuffOffsetY", auraDB, RefreshAuras)
            debuffYSlider:SetPoint("TOPLEFT", PAD, y)
            debuffYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Debuff-specific text customization (stack and duration)
            if unitKey == "target" or unitKey == "player" or unitKey == "focus" or unitKey == "targettarget" or unitKey == "boss" then
                -- Initialize debuff-specific defaults
                if auraDB.debuffSpacing == nil then auraDB.debuffSpacing = 2 end
                if auraDB.debuffShowStack == nil then auraDB.debuffShowStack = true end
                if auraDB.debuffStackSize == nil then auraDB.debuffStackSize = 10 end
                if auraDB.debuffStackAnchor == nil then auraDB.debuffStackAnchor = "BOTTOMRIGHT" end
                if auraDB.debuffStackOffsetX == nil then auraDB.debuffStackOffsetX = -1 end
                if auraDB.debuffStackOffsetY == nil then auraDB.debuffStackOffsetY = 1 end
                if auraDB.debuffStackColor == nil then auraDB.debuffStackColor = {1, 1, 1, 1} end
                -- Duration defaults
                if auraDB.debuffShowDuration == nil then auraDB.debuffShowDuration = true end
                if auraDB.debuffDurationSize == nil then auraDB.debuffDurationSize = 12 end
                if auraDB.debuffDurationAnchor == nil then auraDB.debuffDurationAnchor = "CENTER" end
                if auraDB.debuffDurationOffsetX == nil then auraDB.debuffDurationOffsetX = 0 end
                if auraDB.debuffDurationOffsetY == nil then auraDB.debuffDurationOffsetY = 0 end
                if auraDB.debuffDurationColor == nil then auraDB.debuffDurationColor = {1, 1, 1, 1} end

                local debuffSpacingSlider = GUI:CreateFormSlider(tabContent, "Spacing", 0, 10, 1, "debuffSpacing", auraDB, RefreshAuras)
                debuffSpacingSlider:SetPoint("TOPLEFT", PAD, y)
                debuffSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffShowStackCheck = GUI:CreateFormCheckbox(tabContent, "Stack Show", "debuffShowStack", auraDB, RefreshAuras)
                debuffShowStackCheck:SetPoint("TOPLEFT", PAD, y)
                debuffShowStackCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffStackSizeSlider = GUI:CreateFormSlider(tabContent, "Stack Size", 8, 40, 1, "debuffStackSize", auraDB, RefreshAuras)
                debuffStackSizeSlider:SetPoint("TOPLEFT", PAD, y)
                debuffStackSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffStackAnchorDD = GUI:CreateFormDropdown(tabContent, "Stack Anchor", ninePointAnchorOptions, "debuffStackAnchor", auraDB, RefreshAuras)
                debuffStackAnchorDD:SetPoint("TOPLEFT", PAD, y)
                debuffStackAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffStackXSlider = GUI:CreateFormSlider(tabContent, "Stack X Offset", -20, 20, 1, "debuffStackOffsetX", auraDB, RefreshAuras)
                debuffStackXSlider:SetPoint("TOPLEFT", PAD, y)
                debuffStackXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffStackYSlider = GUI:CreateFormSlider(tabContent, "Stack Y Offset", -20, 20, 1, "debuffStackOffsetY", auraDB, RefreshAuras)
                debuffStackYSlider:SetPoint("TOPLEFT", PAD, y)
                debuffStackYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffStackColorPicker = GUI:CreateFormColorPicker(tabContent, "Stack Color", "debuffStackColor", auraDB, RefreshAuras)
                debuffStackColorPicker:SetPoint("TOPLEFT", PAD, y)
                debuffStackColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                -- Duration text settings
                local debuffShowDurationCheck = GUI:CreateFormCheckbox(tabContent, "Duration Show", "debuffShowDuration", auraDB, RefreshAuras)
                debuffShowDurationCheck:SetPoint("TOPLEFT", PAD, y)
                debuffShowDurationCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffDurationSizeSlider = GUI:CreateFormSlider(tabContent, "Duration Size", 8, 40, 1, "debuffDurationSize", auraDB, RefreshAuras)
                debuffDurationSizeSlider:SetPoint("TOPLEFT", PAD, y)
                debuffDurationSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffDurationAnchorDD = GUI:CreateFormDropdown(tabContent, "Duration Anchor", ninePointAnchorOptions, "debuffDurationAnchor", auraDB, RefreshAuras)
                debuffDurationAnchorDD:SetPoint("TOPLEFT", PAD, y)
                debuffDurationAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffDurationXSlider = GUI:CreateFormSlider(tabContent, "Duration X Offset", -20, 20, 1, "debuffDurationOffsetX", auraDB, RefreshAuras)
                debuffDurationXSlider:SetPoint("TOPLEFT", PAD, y)
                debuffDurationXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffDurationYSlider = GUI:CreateFormSlider(tabContent, "Duration Y Offset", -20, 20, 1, "debuffDurationOffsetY", auraDB, RefreshAuras)
                debuffDurationYSlider:SetPoint("TOPLEFT", PAD, y)
                debuffDurationYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local debuffDurationColorPicker = GUI:CreateFormColorPicker(tabContent, "Duration Color", "debuffDurationColor", auraDB, RefreshAuras)
                debuffDurationColorPicker:SetPoint("TOPLEFT", PAD, y)
                debuffDurationColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW
            end

            -- === BUFF ICONS SECTION ===
            local buffHeader = GUI:CreateSectionHeader(tabContent, "Buff Icons")
            buffHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - buffHeader.gap

            local showBuffsCheck = GUI:CreateFormCheckbox(tabContent, "Show Buffs", "showBuffs", auraDB, RefreshAuras)
            showBuffsCheck:SetPoint("TOPLEFT", PAD, y)
            showBuffsCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local buffHideSwipe = GUI:CreateFormCheckbox(tabContent, "Hide Duration Swipe", "buffHideSwipe", auraDB, RefreshAuras)
            buffHideSwipe:SetPoint("TOPLEFT", PAD, y)
            buffHideSwipe:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Buff Preview toggle (pill-shaped, matches Castbar Preview style)
            local buffPreviewContainer = CreateFrame("Frame", nil, tabContent)
            buffPreviewContainer:SetHeight(FORM_ROW)
            buffPreviewContainer:SetPoint("TOPLEFT", PAD, y)
            buffPreviewContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            local buffPreviewLabel = buffPreviewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            buffPreviewLabel:SetPoint("LEFT", 0, 0)
            buffPreviewLabel:SetText("Buff Preview")
            buffPreviewLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

            local buffPreviewTrack = CreateFrame("Button", nil, buffPreviewContainer, "BackdropTemplate")
            buffPreviewTrack:SetSize(40, 20)
            buffPreviewTrack:SetPoint("LEFT", buffPreviewContainer, "LEFT", 180, 0)
            buffPreviewTrack:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})

            local buffPreviewThumb = CreateFrame("Frame", nil, buffPreviewTrack, "BackdropTemplate")
            buffPreviewThumb:SetSize(16, 16)
            buffPreviewThumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
            buffPreviewThumb:SetBackdropColor(0.95, 0.95, 0.95, 1)
            buffPreviewThumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
            buffPreviewThumb:SetFrameLevel(buffPreviewTrack:GetFrameLevel() + 1)

            local isBuffPreviewOn = false
            local function UpdateBuffPreviewToggle(on)
                if on then
                    buffPreviewTrack:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    buffPreviewTrack:SetBackdropBorderColor(C.accent[1]*0.8, C.accent[2]*0.8, C.accent[3]*0.8, 1)
                    buffPreviewThumb:ClearAllPoints()
                    buffPreviewThumb:SetPoint("RIGHT", buffPreviewTrack, "RIGHT", -2, 0)
                else
                    buffPreviewTrack:SetBackdropColor(0.15, 0.18, 0.22, 1)
                    buffPreviewTrack:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
                    buffPreviewThumb:ClearAllPoints()
                    buffPreviewThumb:SetPoint("LEFT", buffPreviewTrack, "LEFT", 2, 0)
                end
            end
            UpdateBuffPreviewToggle(isBuffPreviewOn)

            buffPreviewTrack:SetScript("OnClick", function()
                isBuffPreviewOn = not isBuffPreviewOn
                UpdateBuffPreviewToggle(isBuffPreviewOn)
                if isBuffPreviewOn then
                    if _G.QUI_ShowAuraPreview then
                        _G.QUI_ShowAuraPreview(unitKey, "buff")
                    end
                else
                    if _G.QUI_HideAuraPreview then
                        _G.QUI_HideAuraPreview(unitKey, "buff")
                    end
                end
            end)
            y = y - FORM_ROW

            local buffIconSize = GUI:CreateFormSlider(tabContent, "Icon Size", 12, 50, 1, "buffIconSize", auraDB, RefreshAuras)
            buffIconSize:SetPoint("TOPLEFT", PAD, y)
            buffIconSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local buffAnchorDrop = GUI:CreateFormDropdown(tabContent, "Anchor", auraAnchorOptions, "buffAnchor", auraDB, RefreshAuras)
            buffAnchorDrop:SetPoint("TOPLEFT", PAD, y)
            buffAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local buffGrowDrop = GUI:CreateFormDropdown(tabContent, "Grow Direction", growOptions, "buffGrow", auraDB, RefreshAuras)
            buffGrowDrop:SetPoint("TOPLEFT", PAD, y)
            buffGrowDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local buffMaxSlider = GUI:CreateFormSlider(tabContent, "Max Icons", 1, 32, 1, "buffMaxIcons", auraDB, RefreshAuras)
            buffMaxSlider:SetPoint("TOPLEFT", PAD, y)
            buffMaxSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local buffXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "buffOffsetX", auraDB, RefreshAuras)
            buffXSlider:SetPoint("TOPLEFT", PAD, y)
            buffXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local buffYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -100, 100, 1, "buffOffsetY", auraDB, RefreshAuras)
            buffYSlider:SetPoint("TOPLEFT", PAD, y)
            buffYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Buff-specific text customization (stack and duration)
            if unitKey == "target" or unitKey == "player" or unitKey == "focus" or unitKey == "targettarget" or unitKey == "boss" then
                -- Initialize buff-specific defaults
                if auraDB.buffSpacing == nil then auraDB.buffSpacing = 2 end
                if auraDB.buffShowStack == nil then auraDB.buffShowStack = true end
                if auraDB.buffStackSize == nil then auraDB.buffStackSize = 10 end
                if auraDB.buffStackAnchor == nil then auraDB.buffStackAnchor = "BOTTOMRIGHT" end
                if auraDB.buffStackOffsetX == nil then auraDB.buffStackOffsetX = -1 end
                if auraDB.buffStackOffsetY == nil then auraDB.buffStackOffsetY = 1 end
                if auraDB.buffStackColor == nil then auraDB.buffStackColor = {1, 1, 1, 1} end
                -- Duration defaults
                if auraDB.buffShowDuration == nil then auraDB.buffShowDuration = true end
                if auraDB.buffDurationSize == nil then auraDB.buffDurationSize = 12 end
                if auraDB.buffDurationAnchor == nil then auraDB.buffDurationAnchor = "CENTER" end
                if auraDB.buffDurationOffsetX == nil then auraDB.buffDurationOffsetX = 0 end
                if auraDB.buffDurationOffsetY == nil then auraDB.buffDurationOffsetY = 0 end
                if auraDB.buffDurationColor == nil then auraDB.buffDurationColor = {1, 1, 1, 1} end

                local buffSpacingSlider = GUI:CreateFormSlider(tabContent, "Spacing", 0, 10, 1, "buffSpacing", auraDB, RefreshAuras)
                buffSpacingSlider:SetPoint("TOPLEFT", PAD, y)
                buffSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffShowStackCheck = GUI:CreateFormCheckbox(tabContent, "Stack Show", "buffShowStack", auraDB, RefreshAuras)
                buffShowStackCheck:SetPoint("TOPLEFT", PAD, y)
                buffShowStackCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffStackSizeSlider = GUI:CreateFormSlider(tabContent, "Stack Size", 8, 40, 1, "buffStackSize", auraDB, RefreshAuras)
                buffStackSizeSlider:SetPoint("TOPLEFT", PAD, y)
                buffStackSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffStackAnchorDD = GUI:CreateFormDropdown(tabContent, "Stack Anchor", ninePointAnchorOptions, "buffStackAnchor", auraDB, RefreshAuras)
                buffStackAnchorDD:SetPoint("TOPLEFT", PAD, y)
                buffStackAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffStackXSlider = GUI:CreateFormSlider(tabContent, "Stack X Offset", -20, 20, 1, "buffStackOffsetX", auraDB, RefreshAuras)
                buffStackXSlider:SetPoint("TOPLEFT", PAD, y)
                buffStackXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffStackYSlider = GUI:CreateFormSlider(tabContent, "Stack Y Offset", -20, 20, 1, "buffStackOffsetY", auraDB, RefreshAuras)
                buffStackYSlider:SetPoint("TOPLEFT", PAD, y)
                buffStackYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffStackColorPicker = GUI:CreateFormColorPicker(tabContent, "Stack Color", "buffStackColor", auraDB, RefreshAuras)
                buffStackColorPicker:SetPoint("TOPLEFT", PAD, y)
                buffStackColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                -- Duration text settings
                local buffShowDurationCheck = GUI:CreateFormCheckbox(tabContent, "Duration Show", "buffShowDuration", auraDB, RefreshAuras)
                buffShowDurationCheck:SetPoint("TOPLEFT", PAD, y)
                buffShowDurationCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffDurationSizeSlider = GUI:CreateFormSlider(tabContent, "Duration Size", 8, 40, 1, "buffDurationSize", auraDB, RefreshAuras)
                buffDurationSizeSlider:SetPoint("TOPLEFT", PAD, y)
                buffDurationSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffDurationAnchorDD = GUI:CreateFormDropdown(tabContent, "Duration Anchor", ninePointAnchorOptions, "buffDurationAnchor", auraDB, RefreshAuras)
                buffDurationAnchorDD:SetPoint("TOPLEFT", PAD, y)
                buffDurationAnchorDD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffDurationXSlider = GUI:CreateFormSlider(tabContent, "Duration X Offset", -20, 20, 1, "buffDurationOffsetX", auraDB, RefreshAuras)
                buffDurationXSlider:SetPoint("TOPLEFT", PAD, y)
                buffDurationXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffDurationYSlider = GUI:CreateFormSlider(tabContent, "Duration Y Offset", -20, 20, 1, "buffDurationOffsetY", auraDB, RefreshAuras)
                buffDurationYSlider:SetPoint("TOPLEFT", PAD, y)
                buffDurationYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW

                local buffDurationColorPicker = GUI:CreateFormColorPicker(tabContent, "Duration Color", "buffDurationColor", auraDB, RefreshAuras)
                buffDurationColorPicker:SetPoint("TOPLEFT", PAD, y)
                buffDurationColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                y = y - FORM_ROW
            end
        end

        -- STATUS INDICATORS section (player only)
        if unitKey == "player" then
            local indicatorsHeader = GUI:CreateSectionHeader(tabContent, "Status Indicators")
            indicatorsHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - indicatorsHeader.gap

            -- Ensure indicators table exists
            if not unitDB.indicators then
                unitDB.indicators = {
                    rested = { enabled = true, size = 16, anchor = "TOPLEFT", offsetX = -2, offsetY = 2 },
                    combat = { enabled = false, size = 16, anchor = "TOPLEFT", offsetX = -2, offsetY = 2 },
                }
            end

            -- Rested indicator
            local restedDesc = GUI:CreateLabel(tabContent, "Rested: Shows when in a rested area (disabled by default).", 11, C.textMuted)
            restedDesc:SetPoint("TOPLEFT", PAD, y)
            restedDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            restedDesc:SetJustifyH("LEFT")
            y = y - 20

            local restedCheck = GUI:CreateFormCheckbox(tabContent, "Enable Rested Indicator", "enabled", unitDB.indicators.rested, RefreshUnit)
            restedCheck:SetPoint("TOPLEFT", PAD, y)
            restedCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local restedSizeSlider = GUI:CreateFormSlider(tabContent, "Rested Icon Size", 8, 32, 1, "size", unitDB.indicators.rested, RefreshUnit)
            restedSizeSlider:SetPoint("TOPLEFT", PAD, y)
            restedSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local restedAnchorDrop = GUI:CreateFormDropdown(tabContent, "Rested Anchor", anchorOptions, "anchor", unitDB.indicators.rested, RefreshUnit)
            restedAnchorDrop:SetPoint("TOPLEFT", PAD, y)
            restedAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local restedXSlider = GUI:CreateFormSlider(tabContent, "Rested X Offset", -50, 50, 1, "offsetX", unitDB.indicators.rested, RefreshUnit)
            restedXSlider:SetPoint("TOPLEFT", PAD, y)
            restedXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local restedYSlider = GUI:CreateFormSlider(tabContent, "Rested Y Offset", -50, 50, 1, "offsetY", unitDB.indicators.rested, RefreshUnit)
            restedYSlider:SetPoint("TOPLEFT", PAD, y)
            restedYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Combat indicator
            local combatDesc = GUI:CreateLabel(tabContent, "Combat: Shows during combat (disabled by default).", 11, C.textMuted)
            combatDesc:SetPoint("TOPLEFT", PAD, y)
            combatDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            combatDesc:SetJustifyH("LEFT")
            y = y - 20

            local combatCheck = GUI:CreateFormCheckbox(tabContent, "Enable Combat Indicator", "enabled", unitDB.indicators.combat, RefreshUnit)
            combatCheck:SetPoint("TOPLEFT", PAD, y)
            combatCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local combatSizeSlider = GUI:CreateFormSlider(tabContent, "Combat Icon Size", 8, 32, 1, "size", unitDB.indicators.combat, RefreshUnit)
            combatSizeSlider:SetPoint("TOPLEFT", PAD, y)
            combatSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local combatAnchorDrop = GUI:CreateFormDropdown(tabContent, "Combat Anchor", anchorOptions, "anchor", unitDB.indicators.combat, RefreshUnit)
            combatAnchorDrop:SetPoint("TOPLEFT", PAD, y)
            combatAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local combatXSlider = GUI:CreateFormSlider(tabContent, "Combat X Offset", -50, 50, 1, "offsetX", unitDB.indicators.combat, RefreshUnit)
            combatXSlider:SetPoint("TOPLEFT", PAD, y)
            combatXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local combatYSlider = GUI:CreateFormSlider(tabContent, "Combat Y Offset", -50, 50, 1, "offsetY", unitDB.indicators.combat, RefreshUnit)
            combatYSlider:SetPoint("TOPLEFT", PAD, y)
            combatYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- ═══════════════════════════════════════════════════════════════
            -- STANCE/FORM TEXT SECTION (player only)
            -- ═══════════════════════════════════════════════════════════════
            local stanceHeader = GUI:CreateSectionHeader(tabContent, "Stance / Form Text")
            stanceHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - stanceHeader.gap

            -- Ensure stance table exists
            if not unitDB.indicators.stance then
                unitDB.indicators.stance = {
                    enabled = false,
                    fontSize = 12,
                    anchor = "BOTTOM",
                    offsetX = 0,
                    offsetY = -2,
                    useClassColor = true,
                    customColor = { 1, 1, 1, 1 },
                    showIcon = false,
                    iconSize = 14,
                    iconOffsetX = -2,
                }
            end

            local stanceDesc = GUI:CreateLabel(tabContent, "Displays current stance, form, or aura (e.g. Bear Form, Battle Stance, Devotion Aura).", 11, C.textMuted)
            stanceDesc:SetPoint("TOPLEFT", PAD, y)
            stanceDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            stanceDesc:SetJustifyH("LEFT")
            y = y - 20

            local stanceCheck = GUI:CreateFormCheckbox(tabContent, "Show Stance/Form Text", "enabled", unitDB.indicators.stance, RefreshUnit)
            stanceCheck:SetPoint("TOPLEFT", PAD, y)
            stanceCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceFontSize = GUI:CreateFormSlider(tabContent, "Font Size", 8, 24, 1, "fontSize", unitDB.indicators.stance, RefreshUnit)
            stanceFontSize:SetPoint("TOPLEFT", PAD, y)
            stanceFontSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceAnchorDrop = GUI:CreateFormDropdown(tabContent, "Anchor", anchorOptions, "anchor", unitDB.indicators.stance, RefreshUnit)
            stanceAnchorDrop:SetPoint("TOPLEFT", PAD, y)
            stanceAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "offsetX", unitDB.indicators.stance, RefreshUnit)
            stanceXSlider:SetPoint("TOPLEFT", PAD, y)
            stanceXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -100, 100, 1, "offsetY", unitDB.indicators.stance, RefreshUnit)
            stanceYSlider:SetPoint("TOPLEFT", PAD, y)
            stanceYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceClassColor = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", unitDB.indicators.stance, RefreshUnit)
            stanceClassColor:SetPoint("TOPLEFT", PAD, y)
            stanceClassColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceCustomColor = GUI:CreateFormColorPicker(tabContent, "Custom Color", "customColor", unitDB.indicators.stance, RefreshUnit)
            stanceCustomColor:SetPoint("TOPLEFT", PAD, y)
            stanceCustomColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceShowIcon = GUI:CreateFormCheckbox(tabContent, "Show Icon", "showIcon", unitDB.indicators.stance, RefreshUnit)
            stanceShowIcon:SetPoint("TOPLEFT", PAD, y)
            stanceShowIcon:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceIconSize = GUI:CreateFormSlider(tabContent, "Icon Size", 8, 32, 1, "iconSize", unitDB.indicators.stance, RefreshUnit)
            stanceIconSize:SetPoint("TOPLEFT", PAD, y)
            stanceIconSize:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local stanceIconOffsetX = GUI:CreateFormSlider(tabContent, "Icon X Offset", -20, 20, 1, "iconOffsetX", unitDB.indicators.stance, RefreshUnit)
            stanceIconOffsetX:SetPoint("TOPLEFT", PAD, y)
            stanceIconOffsetX:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- TARGET MARKER section (all unit frames)
        local markerHeader = GUI:CreateSectionHeader(tabContent, "Target Marker")
        markerHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - markerHeader.gap

        -- Ensure targetMarker table exists
        if not unitDB.targetMarker then
            unitDB.targetMarker = { enabled = false, size = 20, anchor = "TOP", xOffset = 0, yOffset = 8 }
        end

        local markerDesc = GUI:CreateLabel(tabContent, "Shows raid target markers (skull, cross, diamond, etc.) on the unit frame.", 11, C.textMuted)
        markerDesc:SetPoint("TOPLEFT", PAD, y)
        markerDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        markerDesc:SetJustifyH("LEFT")
        y = y - 20

        local markerCheck = GUI:CreateFormCheckbox(tabContent, "Show Target Marker", "enabled", unitDB.targetMarker, RefreshUnit)
        markerCheck:SetPoint("TOPLEFT", PAD, y)
        markerCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local markerSizeSlider = GUI:CreateFormSlider(tabContent, "Marker Size", 8, 48, 1, "size", unitDB.targetMarker, RefreshUnit)
        markerSizeSlider:SetPoint("TOPLEFT", PAD, y)
        markerSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local markerAnchorDrop = GUI:CreateFormDropdown(tabContent, "Anchor To", anchorOptions, "anchor", unitDB.targetMarker, RefreshUnit)
        markerAnchorDrop:SetPoint("TOPLEFT", PAD, y)
        markerAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local markerXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "xOffset", unitDB.targetMarker, RefreshUnit)
        markerXSlider:SetPoint("TOPLEFT", PAD, y)
        markerXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local markerYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -100, 100, 1, "yOffset", unitDB.targetMarker, RefreshUnit)
        markerYSlider:SetPoint("TOPLEFT", PAD, y)
        markerYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- LEADER ICON section (player, target, focus only)
        if unitKey == "player" or unitKey == "target" or unitKey == "focus" then
            local leaderHeader = GUI:CreateSectionHeader(tabContent, "Leader/Assistant Icon")
            leaderHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - leaderHeader.gap

            -- Ensure leaderIcon table exists
            if not unitDB.leaderIcon then
                unitDB.leaderIcon = { enabled = false, size = 16, anchor = "TOPLEFT", xOffset = -8, yOffset = 8 }
            end

            local leaderDesc = GUI:CreateLabel(tabContent, "Shows crown icon for party/raid leader, flag icon for raid assistants.", 11, C.textMuted)
            leaderDesc:SetPoint("TOPLEFT", PAD, y)
            leaderDesc:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            leaderDesc:SetJustifyH("LEFT")
            y = y - 20

            local leaderCheck = GUI:CreateFormCheckbox(tabContent, "Show Leader/Assistant Icon", "enabled", unitDB.leaderIcon, RefreshUnit)
            leaderCheck:SetPoint("TOPLEFT", PAD, y)
            leaderCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local leaderSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 8, 32, 1, "size", unitDB.leaderIcon, RefreshUnit)
            leaderSizeSlider:SetPoint("TOPLEFT", PAD, y)
            leaderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local leaderAnchorDrop = GUI:CreateFormDropdown(tabContent, "Anchor To", anchorOptions, "anchor", unitDB.leaderIcon, RefreshUnit)
            leaderAnchorDrop:SetPoint("TOPLEFT", PAD, y)
            leaderAnchorDrop:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local leaderXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -100, 100, 1, "xOffset", unitDB.leaderIcon, RefreshUnit)
            leaderXSlider:SetPoint("TOPLEFT", PAD, y)
            leaderXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local leaderYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -100, 100, 1, "yOffset", unitDB.leaderIcon, RefreshUnit)
            leaderYSlider:SetPoint("TOPLEFT", PAD, y)
            leaderYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- Portrait section (player, target, focus only)
        if unitKey == "player" or unitKey == "target" or unitKey == "focus" then
            local portraitHeader = GUI:CreateSectionHeader(tabContent, "Portrait")
            portraitHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - portraitHeader.gap

            -- Initialize defaults
            if unitDB.showPortrait == nil then unitDB.showPortrait = false end
            if unitDB.portraitSide == nil then
                unitDB.portraitSide = (unitKey == "player") and "LEFT" or "RIGHT"
            end
            -- Migrate from portraitScale to portraitSize (pixels)
            if unitDB.portraitSize == nil then
                if unitDB.portraitScale then
                    local frameHeight = unitDB.height or 40
                    unitDB.portraitSize = math.floor(frameHeight * unitDB.portraitScale)
                else
                    unitDB.portraitSize = 40
                end
            end
            if unitDB.portraitBorderSize == nil then unitDB.portraitBorderSize = 1 end

            -- Show Portrait checkbox
            local showPortraitCheck = GUI:CreateFormCheckbox(tabContent, "Show Portrait", "showPortrait", unitDB, RefreshUnit)
            showPortraitCheck:SetPoint("TOPLEFT", PAD, y)
            showPortraitCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Portrait Side dropdown
            local sideOptions = {
                {value = "LEFT", text = "Left"},
                {value = "RIGHT", text = "Right"},
            }
            local sideDropdown = GUI:CreateFormDropdown(tabContent, "Portrait Side", sideOptions, "portraitSide", unitDB, RefreshUnit)
            sideDropdown:SetPoint("TOPLEFT", PAD, y)
            sideDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Portrait Size slider (pixels)
            local sizeSlider = GUI:CreateFormSlider(tabContent, "Portrait Size (Pixels)", 20, 150, 1, "portraitSize", unitDB, RefreshUnit)
            sizeSlider:SetPoint("TOPLEFT", PAD, y)
            sizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Portrait Border Size slider
            local borderSlider = GUI:CreateFormSlider(tabContent, "Portrait Border", 0, 5, 1, "portraitBorderSize", unitDB, RefreshUnit)
            borderSlider:SetPoint("TOPLEFT", PAD, y)
            borderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Portrait Gap slider
            if unitDB.portraitGap == nil then unitDB.portraitGap = 0 end
            local gapSlider = GUI:CreateFormSlider(tabContent, "Portrait Gap", 0, 10, 1, "portraitGap", unitDB, RefreshUnit)
            gapSlider:SetPoint("TOPLEFT", PAD, y)
            gapSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Portrait Offset X slider
            if unitDB.portraitOffsetX == nil then unitDB.portraitOffsetX = 0 end
            local portraitOffsetXSlider = GUI:CreateFormSlider(tabContent, "Portrait Offset X", -500, 500, 1, "portraitOffsetX", unitDB, RefreshUnit)
            portraitOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
            portraitOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Portrait Offset Y slider
            if unitDB.portraitOffsetY == nil then unitDB.portraitOffsetY = 0 end
            local portraitOffsetYSlider = GUI:CreateFormSlider(tabContent, "Portrait Offset Y", -500, 500, 1, "portraitOffsetY", unitDB, RefreshUnit)
            portraitOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
            portraitOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Initialize border color defaults
            if unitDB.portraitBorderUseClassColor == nil then unitDB.portraitBorderUseClassColor = false end
            if unitDB.portraitBorderColor == nil then unitDB.portraitBorderColor = { 0, 0, 0, 1 } end

            -- Forward declare color picker for conditional enable/disable
            local borderColorPicker

            -- Use Class Color for Border checkbox
            local useClassColorCheck = GUI:CreateFormCheckbox(tabContent, "Use Class Color for Border", "portraitBorderUseClassColor", unitDB, function(val)
                RefreshUnit()
                -- Enable/disable color picker based on toggle
                if borderColorPicker and borderColorPicker.SetEnabled then
                    borderColorPicker:SetEnabled(not val)
                end
            end)
            useClassColorCheck:SetPoint("TOPLEFT", PAD, y)
            useClassColorCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Custom Border Color picker
            borderColorPicker = GUI:CreateFormColorPicker(tabContent, "Border Color", "portraitBorderColor", unitDB, RefreshUnit)
            borderColorPicker:SetPoint("TOPLEFT", PAD, y)
            borderColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            -- Initial state based on class color toggle
            if borderColorPicker.SetEnabled then
                borderColorPicker:SetEnabled(not unitDB.portraitBorderUseClassColor)
            end
            y = y - FORM_ROW
        end

        tabContent:SetHeight(math.abs(y) + 30)
    end

    -- Create sub-tabs
    local subTabs = GUI:CreateSubTabs(content, {
        {name = "General", builder = BuildGeneralTab},
        {name = "Player", builder = function(c) BuildUnitTab(c, "player") end},
        {name = "Target", builder = function(c) BuildUnitTab(c, "target") end},
        {name = "ToT", builder = function(c) BuildUnitTab(c, "targettarget") end},
        {name = "Pet", builder = function(c) BuildUnitTab(c, "pet") end},
        {name = "Focus", builder = function(c) BuildUnitTab(c, "focus") end},
        {name = "Boss", builder = function(c) BuildUnitTab(c, "boss") end},
    })
    subTabs:SetPoint("TOPLEFT", 5, -5)
    subTabs:SetPoint("TOPRIGHT", -5, -5)
    subTabs:SetHeight(600)

    content:SetHeight(650)
end

---------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
---------------------------------------------------------------------------
ns.QUI_UnitFramesOptions = {
    CreateUnitFramesPage = CreateUnitFramesPage
}
