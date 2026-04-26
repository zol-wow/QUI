--[[
    QUI Castbar Options
    Module-owned castbar content builders for the Unit Frames settings surface
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Reference to main options file for helper functions
local mainOptions = ns.QUI_Options or {}
local Shared = mainOptions
local QUICore = ns.Addon
local SafeGetPixelSize = (ns.QUI_Options or {}).SafeGetPixelSize or function(frame)
    local core = ns.Addon
    return (core and core.GetPixelSize and core:GetPixelSize(frame)) or 1
end

---------------------------------------------------------------------------
-- BUILD CASTBAR OPTIONS SECTION
-- Parameters:
--   tabContent: The parent frame to add widgets to
--   unitKey: The unit key ("player", "target", etc.)
--   y: Current y position (will be updated and returned)
--   PAD: Padding constant
--   FORM_ROW: Form row height constant
--   RefreshUnit: Callback function to refresh the unit frame
--   GetTextureList: Function to get texture list
--   NINE_POINT_ANCHOR_OPTIONS: Constant for anchor options
--   GetUFDB: Function to get unit frames database
--   GetDB: Function to get main database
---------------------------------------------------------------------------
local function BuildCastbarOptions(tabContent, unitKey, y, PAD, FORM_ROW, RefreshUnit, GetTextureList, NINE_POINT_ANCHOR_OPTIONS, GetUFDB, GetDB)
    local ufdb = GetUFDB()
    if not ufdb or not ufdb[unitKey] then
        return y
    end
    
    local unitDB = ufdb[unitKey]
    local db = GetDB()
    
    -- CASTBAR section (for player, target, targettarget, focus, pet, boss)
    if unitKey == "player" or unitKey == "target" or unitKey == "targettarget" or unitKey == "focus" or unitKey == "pet" or unitKey == "boss" then
        local defaultShowChannelTicks = (unitKey == "player")
        Shared.CreateAccentDotLabel(tabContent, "Castbar", y); y = y - 30

        if not unitDB.castbar then
            unitDB.castbar = { enabled = true, width = 250, height = 25, offsetX = 0, offsetY = -25, widthAdjustment = 0, fontSize = 12, iconSize = 25, iconScale = 1.0, color = {1, 0.7, 0, 1}, notInterruptibleColor = {0.7, 0.2, 0.2, 1}, bgColor = {0.149, 0.149, 0.149, 1}, borderSize = 1, iconBorderSize = 2, texture = "Solid", showChannelTicks = defaultShowChannelTicks, channelTickThickness = 1, channelTickColor = {1, 1, 1, 0.9}, channelTickMinConfidence = 0.7, channelTickSourcePolicy = "auto" }
        end
        local castDB = unitDB.castbar
        if not castDB.fontSize then castDB.fontSize = 12 end
        if not castDB.iconSize then castDB.iconSize = 25 end
        if not castDB.iconScale then castDB.iconScale = 1.0 end
        if not castDB.height then castDB.height = 25 end
        if castDB.widthAdjustment == nil then castDB.widthAdjustment = 0 end
        if not castDB.color then
            castDB.color = {1, 0.7, 0, 1}
        elseif not castDB.color[4] or castDB.color[4] == 0 then
            castDB.color[4] = 1
        end
        if castDB.bgColor == nil then
            castDB.bgColor = {0.149, 0.149, 0.149, 1}  -- #262626
        end
        if castDB.notInterruptibleColor == nil then
            castDB.notInterruptibleColor = {0.7, 0.2, 0.2, 1}
        end
        if castDB.borderSize == nil then
            castDB.borderSize = 1
        end
        if castDB.texture == nil then
            castDB.texture = "Solid"
        end
        if castDB.useClassColor == nil then
            castDB.useClassColor = false
        end
        if castDB.showChannelTicks == nil then castDB.showChannelTicks = defaultShowChannelTicks end
        if castDB.channelTickThickness == nil then castDB.channelTickThickness = 1 end
        if castDB.channelTickColor == nil then castDB.channelTickColor = {1, 1, 1, 0.9} end
        if castDB.channelTickMinConfidence == nil then castDB.channelTickMinConfidence = 0.7 end
        if castDB.channelTickSourcePolicy == nil then castDB.channelTickSourcePolicy = "auto" end
        -- Migrate from old lock flags to anchor field
        if not castDB.anchor then
            if castDB.lockedToEssential then
                castDB.anchor = "essential"
            elseif castDB.lockedToUtility then
                castDB.anchor = "utility"
            elseif castDB.lockedToFrame then
                castDB.anchor = "unitframe"
            else
                castDB.anchor = "none"
            end
            -- Clear old lock flags
            castDB.lockedToEssential = nil
            castDB.lockedToUtility = nil
            castDB.lockedToFrame = nil
        end

        -- Initialize separate offset storage for free vs locked modes
        if castDB.freeOffsetX == nil then castDB.freeOffsetX = 0 end
        if castDB.freeOffsetY == nil then castDB.freeOffsetY = 0 end
        if castDB.lockedOffsetX == nil then castDB.lockedOffsetX = 0 end
        if castDB.lockedOffsetY == nil then castDB.lockedOffsetY = -25 end

        local unitDisplayNames = {
            player = "Player Frame",
            target = "Target Frame",
            targettarget = "ToT Frame",
            focus = "Focus Frame",
            pet = "Pet Frame",
            boss = "Boss Frame",
        }
        local frameDisplayName = unitDisplayNames[unitKey] or "Unit Frame"

        -- ========================================
        -- GENERAL SETTINGS
        -- ========================================
        local generalLabel = GUI:CreateLabel(tabContent, "General", 12, C.accentLight)
        generalLabel:SetPoint("TOPLEFT", PAD, y)
        generalLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        generalLabel:SetJustifyH("LEFT")
        y = y - 20

        local castEnable = GUI:CreateFormCheckbox(tabContent, "Enable Castbar", "enabled", castDB, RefreshUnit,
            { description = "Show the castbar for the " .. frameDisplayName .. "." })
        castEnable:SetPoint("TOPLEFT", PAD, y)
        castEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castShowIcon = GUI:CreateFormCheckbox(tabContent, "Show Spell Icon", "showIcon", castDB, RefreshUnit,
            { description = "Show the spell icon beside the castbar." })
        castShowIcon:SetPoint("TOPLEFT", PAD, y)
        castShowIcon:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Use Class Color toggle (player only)
        local castWidgetRefs = {}
        if unitKey == "player" then
            local castUseClassColor = GUI:CreateFormCheckbox(tabContent, "Use Class Color", "useClassColor", castDB, function()
                RefreshUnit()
                if castWidgetRefs.colorPicker then
                    castWidgetRefs.colorPicker:SetEnabled(not castDB.useClassColor)
                end
            end, { description = "Fill the player castbar with your class color. Disables the Castbar Color picker below when on." })
            castUseClassColor:SetPoint("TOPLEFT", PAD, y)
            castUseClassColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        local castColorPicker = GUI:CreateFormColorPicker(tabContent, "Castbar Color", "color", castDB, RefreshUnit, nil,
            { description = "Base fill color of the castbar. Ignored while Use Class Color is on (player) or while casting an uninterruptible spell (target/focus)." })
        castColorPicker:SetPoint("TOPLEFT", PAD, y)
        castColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        if unitKey == "player" then
            castWidgetRefs.colorPicker = castColorPicker
            castColorPicker:SetEnabled(not castDB.useClassColor)
        end
        y = y - FORM_ROW

        local castBgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", castDB, RefreshUnit, nil,
            { description = "Color of the unfilled portion of the castbar." })
        castBgColorPicker:SetPoint("TOPLEFT", PAD, y)
        castBgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if unitKey == "target" or unitKey == "focus" then
            local notInterruptibleColorPicker = GUI:CreateFormColorPicker(tabContent, "Uninterruptible Cast Color", "notInterruptibleColor", castDB, RefreshUnit, nil,
                { description = "Color applied to the castbar when the target is casting something you can't interrupt." })
            notInterruptibleColorPicker:SetPoint("TOPLEFT", PAD, y)
            notInterruptibleColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        local castTextureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", castDB, RefreshUnit,
            { description = "Status bar texture used to fill the castbar." })
        castTextureDropdown:SetPoint("TOPLEFT", PAD, y)
        castTextureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castBorderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 5, 1, "borderSize", castDB, RefreshUnit, nil,
            { description = "Thickness of the castbar outline in pixels. 0 removes the outline." })
        castBorderSlider:SetPoint("TOPLEFT", PAD, y)
        castBorderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if unitKey == "player" then
            local gcdLabel = GUI:CreateLabel(tabContent, "GCD", 12, C.accentLight)
            gcdLabel:SetPoint("TOPLEFT", PAD, y)
            gcdLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            gcdLabel:SetJustifyH("LEFT")
            y = y - 20

            if castDB.showGCD == nil then castDB.showGCD = false end
            if castDB.showGCDReverse == nil then castDB.showGCDReverse = false end
            if castDB.showGCDMelee == nil then castDB.showGCDMelee = castDB.showGCDMeleeOnly == true end

            local castShowGCD = GUI:CreateFormCheckbox(tabContent, "Show GCD as castbar", "showGCD", castDB, RefreshUnit,
                { description = "Animate the player castbar as a sweep during your global cooldown even when you're not casting." })
            castShowGCD:SetPoint("TOPLEFT", PAD, y)
            castShowGCD:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local castShowGCDReverse = GUI:CreateFormCheckbox(tabContent, "Reverse direction", "showGCDReverse", castDB, RefreshUnit,
                { description = "Reverse the direction of the GCD sweep on the castbar (empty → full instead of full → empty, or vice-versa)." })
            castShowGCDReverse:SetPoint("TOPLEFT", PAD, y)
            castShowGCDReverse:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local castShowGCDMelee = GUI:CreateFormCheckbox(tabContent, "Show melee", "showGCDMelee", castDB, RefreshUnit,
                { description = "Also sweep the GCD animation during your instant melee swings, not just during spell casts." })
            castShowGCDMelee:SetPoint("TOPLEFT", PAD, y)
            castShowGCDMelee:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            if castDB.gcdColor == nil then
                local baseColor = castDB.color or {1, 1, 1, 1}
                castDB.gcdColor = {baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1}
            end
            local gcdColorPicker = GUI:CreateFormColorPicker(tabContent, "GCD Bar Color", "gcdColor", castDB, RefreshUnit, nil,
                { description = "Fill color used specifically for the GCD sweep (separate from the normal cast color)." })
            gcdColorPicker:SetPoint("TOPLEFT", PAD, y)
            gcdColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- ========================================
        -- POSITIONING & SIZE
        -- ========================================
        local positioningLabel = GUI:CreateLabel(tabContent, "Positioning & Size", 12, C.accentLight)
        positioningLabel:SetPoint("TOPLEFT", PAD, y)
        positioningLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        positioningLabel:SetJustifyH("LEFT")
        y = y - 20

        -- Castbar positioning moved to Edit Mode.

        -- Castbar preview row (form style)
        local castPreviewContainer = CreateFrame("Frame", nil, tabContent)
        castPreviewContainer:SetHeight(FORM_ROW)
        castPreviewContainer:SetPoint("TOPLEFT", PAD, y)
        castPreviewContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local castPreviewLabel = castPreviewContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        castPreviewLabel:SetPoint("LEFT", 0, 0)
        castPreviewLabel:SetText("Castbar Preview")
        castPreviewLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Toggle track (pill-shaped, matches CreateFormToggle)
        local castPreviewTrack = CreateFrame("Button", nil, castPreviewContainer, "BackdropTemplate")
        castPreviewTrack:SetSize(40, 20)
        castPreviewTrack:SetPoint("LEFT", castPreviewContainer, "LEFT", 180, 0)
        local pxCastTrack = SafeGetPixelSize(castPreviewTrack)
        castPreviewTrack:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = pxCastTrack})

        -- Thumb (sliding circle)
        local castPreviewThumb = CreateFrame("Frame", nil, castPreviewTrack, "BackdropTemplate")
        castPreviewThumb:SetSize(16, 16)
        local pxCastThumb = SafeGetPixelSize(castPreviewThumb)
        castPreviewThumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = pxCastThumb})
        castPreviewThumb:SetBackdropColor(0.95, 0.95, 0.95, 1)
        castPreviewThumb:SetBackdropBorderColor(0.85, 0.85, 0.85, 1)
        castPreviewThumb:SetFrameLevel(castPreviewTrack:GetFrameLevel() + 1)

        -- Initialize preview state in database (doesn't persist across reloads)
        if castDB.previewMode == nil then
            castDB.previewMode = false
        end

        local function UpdateCastPreviewToggle(on)
            if on then
                castPreviewTrack:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
                castPreviewTrack:SetBackdropBorderColor(C.accent[1]*0.8, C.accent[2]*0.8, C.accent[3]*0.8, 1)
                castPreviewThumb:ClearAllPoints()
                castPreviewThumb:SetPoint("RIGHT", castPreviewTrack, "RIGHT", -2, 0)
            else
                castPreviewTrack:SetBackdropColor(0.15, 0.18, 0.22, 1)
                castPreviewTrack:SetBackdropBorderColor(0.12, 0.14, 0.18, 1)
                castPreviewThumb:ClearAllPoints()
                castPreviewThumb:SetPoint("LEFT", castPreviewTrack, "LEFT", 2, 0)
            end
        end
        UpdateCastPreviewToggle(castDB.previewMode)

        castPreviewTrack:SetScript("OnClick", function()
            castDB.previewMode = not castDB.previewMode
            UpdateCastPreviewToggle(castDB.previewMode)
            -- Refresh to recreate castbar with/without preview content
            RefreshUnit()
        end)
        y = y - FORM_ROW

        -- Copy Settings From dropdown
        local castbarCopyOptions = {}
        local castbarUnits = {
            {key = "player", text = "Player"},
            {key = "target", text = "Target"},
            {key = "targettarget", text = "ToT"},
            {key = "focus", text = "Focus"},
            {key = "pet", text = "Pet"},
            {key = "boss", text = "Boss"},
        }
        for _, unit in ipairs(castbarUnits) do
            if unit.key ~= unitKey then
                table.insert(castbarCopyOptions, {value = unit.key, text = unit.text})
            end
        end

        local castCopyWrapper = { selected = castbarCopyOptions[1] and castbarCopyOptions[1].value or nil }
        local castCopyRow = CreateFrame("Frame", nil, tabContent)
        castCopyRow:SetHeight(FORM_ROW)
        castCopyRow:SetPoint("TOPLEFT", PAD, y)
        castCopyRow:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        -- Helper to copy castbar settings from one unit to another
        local function CopyCastbarSettings(sourceDB, targetDB, sourceUnitKey, targetUnitKey)
            if not sourceDB or not targetDB then return end
            local keys = {"width", "height", "fontSize", "borderSize", "texture", "showIcon", "enabled", "iconAnchor", "iconSpacing", "spellTextAnchor", "spellTextOffsetX", "spellTextOffsetY", "timeTextAnchor", "timeTextOffsetX", "timeTextOffsetY", "showSpellText", "showTimeText", "useClassColor", "channelFillForward", "empoweredStageColors", "empoweredFillColors"}
            local includesUnsupportedTickUnit = (sourceUnitKey == "boss") or (targetUnitKey == "boss")
                or (sourceUnitKey == "pet") or (targetUnitKey == "pet")
            if not includesUnsupportedTickUnit then
                table.insert(keys, "showChannelTicks")
                table.insert(keys, "channelTickThickness")
                table.insert(keys, "channelTickMinConfidence")
                table.insert(keys, "channelTickSourcePolicy")
            end
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
            if sourceDB.gcdColor then
                targetDB.gcdColor = {sourceDB.gcdColor[1], sourceDB.gcdColor[2], sourceDB.gcdColor[3], sourceDB.gcdColor[4]}
            end
            if not includesUnsupportedTickUnit and sourceDB.channelTickColor then
                targetDB.channelTickColor = {
                    sourceDB.channelTickColor[1],
                    sourceDB.channelTickColor[2],
                    sourceDB.channelTickColor[3],
                    sourceDB.channelTickColor[4]
                }
            end
            if sourceDB.notInterruptibleColor then
                targetDB.notInterruptibleColor = {
                    sourceDB.notInterruptibleColor[1],
                    sourceDB.notInterruptibleColor[2],
                    sourceDB.notInterruptibleColor[3],
                    sourceDB.notInterruptibleColor[4]
                }
            end
            if sourceDB.empoweredStageColors then
                targetDB.empoweredStageColors = {}
                for i = 1, 5 do
                    if sourceDB.empoweredStageColors[i] then
                        targetDB.empoweredStageColors[i] = {
                            sourceDB.empoweredStageColors[i][1],
                            sourceDB.empoweredStageColors[i][2],
                            sourceDB.empoweredStageColors[i][3],
                            sourceDB.empoweredStageColors[i][4]
                        }
                    end
                end
            end
            if sourceDB.empoweredFillColors then
                targetDB.empoweredFillColors = {}
                for i = 1, 5 do
                    if sourceDB.empoweredFillColors[i] then
                        targetDB.empoweredFillColors[i] = {
                            sourceDB.empoweredFillColors[i][1],
                            sourceDB.empoweredFillColors[i][2],
                            sourceDB.empoweredFillColors[i][3],
                            sourceDB.empoweredFillColors[i][4]
                        }
                    end
                end
            end
        end

        local castCopyApplyBtn = GUI:CreateButton(castCopyRow, "Apply", 60, 24, function()
            if castCopyWrapper.selected then
                local sourceUnitDB = db.quiUnitFrames and db.quiUnitFrames[castCopyWrapper.selected]
                if sourceUnitDB and sourceUnitDB.castbar then
                    CopyCastbarSettings(sourceUnitDB.castbar, castDB, castCopyWrapper.selected, unitKey)
                    RefreshUnit()
                end
            end
        end)
        castCopyApplyBtn:SetPoint("RIGHT", castCopyRow, "RIGHT", 0, 2)

        local castCopyDropdown = GUI:CreateFormDropdown(castCopyRow, "Copy Settings From", castbarCopyOptions, "selected", castCopyWrapper, nil,
            { description = "Pick another unit's castbar configuration to copy into this one. Click Apply to perform the copy." })
        castCopyDropdown:SetPoint("TOPLEFT", 0, 0)
        castCopyDropdown:SetPoint("RIGHT", castCopyApplyBtn, "LEFT", -8, 0)
        y = y - FORM_ROW

        local castWidthSlider = GUI:CreateFormSlider(tabContent, "Width", 50, 2000, 1, "width", castDB, RefreshUnit, nil,
            { description = "Pixel width of the castbar." })
        castWidthSlider:SetPoint("TOPLEFT", PAD, y)
        castWidthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castHeightSlider = GUI:CreateFormSlider(tabContent, "Bar Height", 4, 60, 1, "height", castDB, RefreshUnit, nil,
            { description = "Pixel height of the castbar itself." })
        castHeightSlider:SetPoint("TOPLEFT", PAD, y)
        castHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 8, 80, 1, "iconSize", castDB, RefreshUnit, nil,
            { description = "Pixel size of the spell icon that sits beside the castbar." })
        iconSizeSlider:SetPoint("TOPLEFT", PAD, y)
        iconSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Channel fill direction toggle
        local channelFillCheck = GUI:CreateFormCheckbox(tabContent, "Channel spells fill forward", "channelFillForward", castDB, RefreshUnit,
            { description = "Channeled spells fill the bar from empty to full instead of draining from full to empty." })
        channelFillCheck:SetPoint("TOPLEFT", PAD, y)
        channelFillCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        if unitKey ~= "boss" and unitKey ~= "pet" then
            -- ========================================
            -- CHANNEL TICKS
            -- ========================================
            local channelTicksLabel = GUI:CreateLabel(tabContent, "Channel Ticks", 12, C.accentLight)
            channelTicksLabel:SetPoint("TOPLEFT", PAD, y)
            channelTicksLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            channelTicksLabel:SetJustifyH("LEFT")
            y = y - 20

            local showChannelTicksCheck = GUI:CreateFormCheckbox(tabContent, "Show Channel Tick Markers", "showChannelTicks", castDB, RefreshUnit,
                { description = "Draw tick marks on the castbar at the moments a channeled spell triggers a tick." })
            showChannelTicksCheck:SetPoint("TOPLEFT", PAD, y)
            showChannelTicksCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local tickSourceOptions = {
                {value = "auto", text = "Tick Source: Auto (Static then Runtime)"},
                {value = "static", text = "Tick Source: Static Only"},
                {value = "runtimeOnly", text = "Tick Source: Runtime Calibration Only"},
            }
            local channelTickSourceDropdown = GUI:CreateFormDropdown(tabContent, "Channel Tick Source", tickSourceOptions, "channelTickSourcePolicy", castDB, RefreshUnit,
                { description = "Where the tick timings come from. Auto tries QUI's static table first, then live calibration. Static skips calibration; Runtime only uses calibration." })
            channelTickSourceDropdown:SetPoint("TOPLEFT", PAD, y)
            channelTickSourceDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            channelTickSourceDropdown:SetEnabled(false)
            y = y - FORM_ROW

            local tickConfidenceSlider = GUI:CreateFormSlider(tabContent, "Channel Tick Min Confidence", 0.5, 1.0, 0.05, "channelTickMinConfidence", castDB, RefreshUnit, nil,
                { description = "Minimum calibration confidence required before runtime-detected tick timings are drawn. Higher values require more consistent observations." })
            tickConfidenceSlider:SetPoint("TOPLEFT", PAD, y)
            tickConfidenceSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            tickConfidenceSlider:SetEnabled(false)
            y = y - FORM_ROW

            local tickThicknessSlider = GUI:CreateFormSlider(tabContent, "Channel Tick Thickness", 1, 5, 0.5, "channelTickThickness", castDB, RefreshUnit, nil,
                { description = "Thickness of the tick markers, in pixels." })
            tickThicknessSlider:SetPoint("TOPLEFT", PAD, y)
            tickThicknessSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local tickColorPicker = GUI:CreateFormColorPicker(tabContent, "Channel Tick Color", "channelTickColor", castDB, RefreshUnit, nil,
                { description = "Color of the tick markers drawn on the castbar." })
            tickColorPicker:SetPoint("TOPLEFT", PAD, y)
            tickColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        -- ========================================
        -- TEXT & DISPLAY
        -- ========================================
        local textDisplayLabel = GUI:CreateLabel(tabContent, "Text & Display", 12, C.accentLight)
        textDisplayLabel:SetPoint("TOPLEFT", PAD, y)
        textDisplayLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textDisplayLabel:SetJustifyH("LEFT")
        y = y - 20

        local castFontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 24, 1, "fontSize", castDB, RefreshUnit, nil,
            { description = "Font size used for the spell name and cast time text on the castbar." })
        castFontSizeSlider:SetPoint("TOPLEFT", PAD, y)
        castFontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castMaxLengthSlider = GUI:CreateFormSlider(tabContent, "Max Length (0=none)", 0, 30, 1, "maxLength", castDB, RefreshUnit, nil,
            { description = "Maximum number of characters shown for the spell name. Names past this length get truncated. 0 disables truncation." })
        castMaxLengthSlider:SetPoint("TOPLEFT", PAD, y)
        castMaxLengthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- ========================================
        -- ELEMENT POSITIONING
        -- ========================================
        local elementAnchorsLabel = GUI:CreateLabel(tabContent, "Element Positioning", 12, C.accentLight)
        elementAnchorsLabel:SetPoint("TOPLEFT", PAD, y)
        elementAnchorsLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        elementAnchorsLabel:SetJustifyH("LEFT")
        y = y - 20

        -- Initialize element settings
        if castDB.iconAnchor == nil then castDB.iconAnchor = "LEFT" end
        if castDB.iconSpacing == nil then castDB.iconSpacing = 0 end
        if castDB.showIcon == nil then castDB.showIcon = true end
        
        if castDB.spellTextAnchor == nil then castDB.spellTextAnchor = "LEFT" end
        if castDB.spellTextOffsetX == nil then castDB.spellTextOffsetX = 4 end
        if castDB.spellTextOffsetY == nil then castDB.spellTextOffsetY = 0 end
        if castDB.showSpellText == nil then castDB.showSpellText = true end
        
        if castDB.timeTextAnchor == nil then castDB.timeTextAnchor = "RIGHT" end
        if castDB.timeTextOffsetX == nil then castDB.timeTextOffsetX = -4 end
        if castDB.timeTextOffsetY == nil then castDB.timeTextOffsetY = 0 end
        if castDB.showTimeText == nil then castDB.showTimeText = true end

        -- Icon settings
        local iconAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Icon Anchor", NINE_POINT_ANCHOR_OPTIONS, "iconAnchor", castDB, RefreshUnit,
            { description = "Which edge or corner of the castbar the spell icon attaches to." })
        iconAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        iconAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Icon", "showIcon", castDB, RefreshUnit,
            { description = "Show the spell icon beside the castbar. Shares the same setting as Show Spell Icon above." })
        iconVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
        iconVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconSpacingSlider = GUI:CreateFormSlider(tabContent, "Icon Spacing", -50, 50, 1, "iconSpacing", castDB, RefreshUnit, nil,
            { description = "Pixel gap between the icon and the castbar. Negative values overlap the two." })
        iconSpacingSlider:SetPoint("TOPLEFT", PAD, y)
        iconSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconBorderSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Border Size", 0, 5, 0.1, "iconBorderSize", castDB, RefreshUnit, nil,
            { description = "Thickness of the border drawn around the spell icon, in pixels." })
        iconBorderSizeSlider:SetPoint("TOPLEFT", PAD, y)
        iconBorderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconScaleSlider = GUI:CreateFormSlider(tabContent, "Icon Scale", 0.5, 2.0, 0.1, "iconScale", castDB, RefreshUnit, nil,
            { description = "Scale multiplier applied to the spell icon. Use values greater than 1 to enlarge the icon relative to the bar." })
        iconScaleSlider:SetPoint("TOPLEFT", PAD, y)
        iconScaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Spell text settings
        local spellTextAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Spell Text Anchor", NINE_POINT_ANCHOR_OPTIONS, "spellTextAnchor", castDB, RefreshUnit,
            { description = "Which edge or corner of the castbar the spell name anchors to." })
        spellTextAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        spellTextAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spellTextVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Spell Text", "showSpellText", castDB, RefreshUnit,
            { description = "Display the spell name on top of the castbar." })
        spellTextVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
        spellTextVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spellTextOffsetXSlider = GUI:CreateFormSlider(tabContent, "Spell Text X Offset", -200, 200, 1, "spellTextOffsetX", castDB, RefreshUnit, nil,
            { description = "Horizontal pixel offset of the spell name from its anchor." })
        spellTextOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        spellTextOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spellTextOffsetYSlider = GUI:CreateFormSlider(tabContent, "Spell Text Y Offset", -200, 200, 1, "spellTextOffsetY", castDB, RefreshUnit, nil,
            { description = "Vertical pixel offset of the spell name from its anchor." })
        spellTextOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        spellTextOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Time text settings
        local timeTextAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Time Text Anchor", NINE_POINT_ANCHOR_OPTIONS, "timeTextAnchor", castDB, RefreshUnit,
            { description = "Which edge or corner of the castbar the time remaining text anchors to." })
        timeTextAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        timeTextAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local timeTextVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Time Text", "showTimeText", castDB, RefreshUnit,
            { description = "Display the cast time remaining (e.g., 1.4s) on top of the castbar." })
        timeTextVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
        timeTextVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local timeTextOffsetXSlider = GUI:CreateFormSlider(tabContent, "Time Text X Offset", -200, 200, 1, "timeTextOffsetX", castDB, RefreshUnit, nil,
            { description = "Horizontal pixel offset of the time text from its anchor." })
        timeTextOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        timeTextOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local timeTextOffsetYSlider = GUI:CreateFormSlider(tabContent, "Time Text Y Offset", -200, 200, 1, "timeTextOffsetY", castDB, RefreshUnit, nil,
            { description = "Vertical pixel offset of the time text from its anchor." })
        timeTextOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        timeTextOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Empowered settings (player only)
        if unitKey == "player" then
            -- Hide time text on empowered
            if castDB.hideTimeTextOnEmpowered == nil then castDB.hideTimeTextOnEmpowered = false end

            local hideTimeTextOnEmpoweredToggle = GUI:CreateFormToggle(tabContent, "Hide Time Text on Empowered", "hideTimeTextOnEmpowered", castDB, RefreshUnit,
                { description = "Hide the time remaining text while casting an empowered spell so the stage markers read more clearly." })
            hideTimeTextOnEmpoweredToggle:SetPoint("TOPLEFT", PAD, y)
            hideTimeTextOnEmpoweredToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Empowered level text settings
            if castDB.empoweredLevelTextAnchor == nil then castDB.empoweredLevelTextAnchor = "CENTER" end
            if castDB.empoweredLevelTextOffsetX == nil then castDB.empoweredLevelTextOffsetX = 0 end
            if castDB.empoweredLevelTextOffsetY == nil then castDB.empoweredLevelTextOffsetY = 0 end
            if castDB.showEmpoweredLevel == nil then castDB.showEmpoweredLevel = false end

            local empoweredLevelTextAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Empowered Level Text Anchor", NINE_POINT_ANCHOR_OPTIONS, "empoweredLevelTextAnchor", castDB, RefreshUnit,
                { description = "Where the current empowered stage number is anchored on the castbar." })
            empoweredLevelTextAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local empoweredLevelTextVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Empowered Level", "showEmpoweredLevel", castDB, RefreshUnit,
                { description = "Display the current empowered stage number on the castbar while casting an empowered spell." })
            empoweredLevelTextVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local empoweredLevelTextOffsetXSlider = GUI:CreateFormSlider(tabContent, "Empowered Level Text X Offset", -200, 200, 1, "empoweredLevelTextOffsetX", castDB, RefreshUnit, nil,
                { description = "Horizontal pixel offset of the empowered stage text from its anchor." })
            empoweredLevelTextOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local empoweredLevelTextOffsetYSlider = GUI:CreateFormSlider(tabContent, "Empowered Level Text Y Offset", -200, 200, 1, "empoweredLevelTextOffsetY", castDB, RefreshUnit, nil,
                { description = "Vertical pixel offset of the empowered stage text from its anchor." })
            empoweredLevelTextOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Empowered color overrides section
            Shared.CreateAccentDotLabel(tabContent, "Empowered Color Overrides", y); y = y - 30

            -- Initialize color arrays if needed with default values from constants
            if not castDB.empoweredStageColors then castDB.empoweredStageColors = {} end
            if not castDB.empoweredFillColors then castDB.empoweredFillColors = {} end

            -- Get default colors from castbar module
            local QUI_Castbar = ns.QUI_Castbar
            local defaultStageColors = QUI_Castbar and QUI_Castbar.STAGE_COLORS or {}
            local defaultFillColors = QUI_Castbar and QUI_Castbar.STAGE_FILL_COLORS or {}

            -- Store color picker references for reset functionality
            local stageColorPickers = {}
            local fillColorPickers = {}

            -- Stage colors (background overlays)
            local stageColorLabel = GUI:CreateLabel(tabContent, "Stage Colors (Background Overlays)", 11, C.textMuted)
            stageColorLabel:SetPoint("TOPLEFT", PAD, y)
            y = y - 20

            for i = 1, 5 do
                if not castDB.empoweredStageColors[i] and defaultStageColors[i] then
                    castDB.empoweredStageColors[i] = {defaultStageColors[i][1], defaultStageColors[i][2], defaultStageColors[i][3], defaultStageColors[i][4]}
                end
                local stageColorPicker = GUI:CreateFormColorPicker(tabContent, "Stage " .. i .. " Color", i, castDB.empoweredStageColors, RefreshUnit, nil,
                    { description = "Background overlay color for empowered stage " .. i .. "." })
                stageColorPicker:SetPoint("TOPLEFT", PAD, y)
                stageColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                stageColorPickers[i] = stageColorPicker
                y = y - FORM_ROW
            end

            y = y - 10

            -- Fill colors (status bar fill)
            local fillColorLabel = GUI:CreateLabel(tabContent, "Fill Colors (Status Bar Fill)", 11, C.textMuted)
            fillColorLabel:SetPoint("TOPLEFT", PAD, y)
            y = y - 20

            for i = 1, 5 do
                if not castDB.empoweredFillColors[i] and defaultFillColors[i] then
                    castDB.empoweredFillColors[i] = {defaultFillColors[i][1], defaultFillColors[i][2], defaultFillColors[i][3], defaultFillColors[i][4]}
                end
                local fillColorPicker = GUI:CreateFormColorPicker(tabContent, "Fill " .. i .. " Color", i, castDB.empoweredFillColors, RefreshUnit, nil,
                    { description = "Fill color used for the castbar itself during empowered stage " .. i .. "." })
                fillColorPicker:SetPoint("TOPLEFT", PAD, y)
                fillColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
                fillColorPickers[i] = fillColorPicker
                y = y - FORM_ROW
            end

            y = y - 10

            -- Reset button
            local resetContainer = CreateFrame("Frame", nil, tabContent)
            resetContainer:SetHeight(FORM_ROW)
            resetContainer:SetPoint("TOPLEFT", PAD, y)
            resetContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

            local resetLabel = resetContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            resetLabel:SetPoint("LEFT", 0, 0)
            resetLabel:SetText("Reset Empowered Colors")
            resetLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

            local resetBtn = CreateFrame("Button", nil, resetContainer, "BackdropTemplate")
            resetBtn:SetSize(140, 24)
            resetBtn:SetPoint("LEFT", resetContainer, "LEFT", 180, 0)
            local px = SafeGetPixelSize(resetBtn)
            resetBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = px,
            })
            resetBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            resetBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

            local resetBtnText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            resetBtnText:SetPoint("CENTER")
            resetBtnText:SetText("Reset to Defaults")
            resetBtnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

            resetBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            end)
            resetBtn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            end)
            resetBtn:SetScript("OnClick", function()
                -- Reset stage colors
                for i = 1, 5 do
                    if defaultStageColors[i] then
                        castDB.empoweredStageColors[i] = {defaultStageColors[i][1], defaultStageColors[i][2], defaultStageColors[i][3], defaultStageColors[i][4]}
                        if stageColorPickers[i] and stageColorPickers[i].swatch then
                            stageColorPickers[i].swatch:SetBackdropColor(defaultStageColors[i][1], defaultStageColors[i][2], defaultStageColors[i][3], defaultStageColors[i][4])
                        end
                    end
                end

                -- Reset fill colors
                for i = 1, 5 do
                    if defaultFillColors[i] then
                        castDB.empoweredFillColors[i] = {defaultFillColors[i][1], defaultFillColors[i][2], defaultFillColors[i][3], defaultFillColors[i][4]}
                        if fillColorPickers[i] and fillColorPickers[i].swatch then
                            fillColorPickers[i].swatch:SetBackdropColor(defaultFillColors[i][1], defaultFillColors[i][2], defaultFillColors[i][3], defaultFillColors[i][4])
                        end
                    end
                end

                RefreshUnit()
            end)

            y = y - FORM_ROW
        end

    end
    
    return y
end

-- Export the function
ns.QUI_CastbarOptions = {
    BuildCastbarOptions = BuildCastbarOptions
}

