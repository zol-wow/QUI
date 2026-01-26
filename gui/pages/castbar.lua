--[[
    QUI Castbar Options
    Extracted from qui_options.lua for better organization
    Builds the castbar options section for unit frame tabs
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- Reference to main options file for helper functions
local mainOptions = ns.QUI_Options or {}

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
        local castbarHeader = GUI:CreateSectionHeader(tabContent, "Castbar")
        castbarHeader:SetPoint("TOPLEFT", PAD, y)
        y = y - castbarHeader.gap

        if not unitDB.castbar then
            unitDB.castbar = { enabled = true, width = 250, height = 25, offsetX = 0, offsetY = -25, widthAdjustment = 0, fontSize = 12, iconSize = 25, iconScale = 1.0, color = {1, 0.7, 0, 1}, bgColor = {0.149, 0.149, 0.149, 1}, borderSize = 1, iconBorderSize = 2, texture = "Solid" }
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
        if castDB.borderSize == nil then
            castDB.borderSize = 1
        end
        if castDB.texture == nil then
            castDB.texture = "Solid"
        end
        if castDB.useClassColor == nil then
            castDB.useClassColor = false
        end
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

        local castEnable = GUI:CreateFormCheckbox(tabContent, "Enable Castbar", "enabled", castDB, RefreshUnit)
        castEnable:SetPoint("TOPLEFT", PAD, y)
        castEnable:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castShowIcon = GUI:CreateFormCheckbox(tabContent, "Show Spell Icon", "showIcon", castDB, RefreshUnit)
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
            end)
            castUseClassColor:SetPoint("TOPLEFT", PAD, y)
            castUseClassColor:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW
        end

        local castColorPicker = GUI:CreateFormColorPicker(tabContent, "Castbar Color", "color", castDB, RefreshUnit)
        castColorPicker:SetPoint("TOPLEFT", PAD, y)
        castColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        if unitKey == "player" then
            castWidgetRefs.colorPicker = castColorPicker
            castColorPicker:SetEnabled(not castDB.useClassColor)
        end
        y = y - FORM_ROW

        local castBgColorPicker = GUI:CreateFormColorPicker(tabContent, "Background Color", "bgColor", castDB, RefreshUnit)
        castBgColorPicker:SetPoint("TOPLEFT", PAD, y)
        castBgColorPicker:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castTextureDropdown = GUI:CreateFormDropdown(tabContent, "Bar Texture", GetTextureList(), "texture", castDB, RefreshUnit)
        castTextureDropdown:SetPoint("TOPLEFT", PAD, y)
        castTextureDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castBorderSlider = GUI:CreateFormSlider(tabContent, "Border Size", 0, 5, 1, "borderSize", castDB, RefreshUnit)
        castBorderSlider:SetPoint("TOPLEFT", PAD, y)
        castBorderSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- ========================================
        -- POSITIONING & SIZE
        -- ========================================
        local positioningLabel = GUI:CreateLabel(tabContent, "Positioning & Size", 12, C.accentLight)
        positioningLabel:SetPoint("TOPLEFT", PAD, y)
        positioningLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        positioningLabel:SetJustifyH("LEFT")
        y = y - 20

        -- Anchor selection dropdown
        local anchorOptions = {
            {value = "none", text = "None"}
        }
        table.insert(anchorOptions, {value = "unitframe", text = "Unit Frame"})
        if unitKey == "player" then
            table.insert(anchorOptions, {value = "essential", text = "Essential Cooldowns"})
            table.insert(anchorOptions, {value = "utility", text = "Utility Cooldowns"})
        end
        
        -- Initialize anchor if not set
        if not castDB.anchor then
            castDB.anchor = "none"
        end
        
        -- Create slider references first (needed for UpdateCastbarSliders)
        local castWidthSlider, castWidthAdjSlider, castHeightSlider, castOffsetXSlider, castOffsetYSlider, anchorDropdown
        
        -- Helper to update all sliders and anchor label (defined early so it can be used in callbacks)
        local function UpdateCastbarSliders()
            if castWidthSlider and castWidthSlider.SetValue then
                castWidthSlider.SetValue(castDB.width or 250)
            end
            if castHeightSlider and castHeightSlider.SetValue then
                castHeightSlider.SetValue(castDB.height or 16)
            end
            if castOffsetXSlider and castOffsetXSlider.SetValue then
                castOffsetXSlider.SetValue(castDB.offsetX or 0)
            end
            if castOffsetYSlider and castOffsetYSlider.SetValue then
                castOffsetYSlider.SetValue(castDB.offsetY or 0)
            end

            -- Update dropdown selection
            if anchorDropdown and anchorDropdown.SetValue then
                anchorDropdown.SetValue(castDB.anchor or "none", true)
            end
            
            -- Disable width slider when auto-resize anchor is set (width controlled by anchors)
            -- Only enable width slider when anchor is "none" (manual positioning)
            if castWidthSlider then
                if castDB.anchor == "none" then
                    castWidthSlider:SetEnabled(true)
                else
                    castWidthSlider:SetEnabled(false)
                end
            end

            -- Width Adjustment slider is the opposite: enabled when locked to a frame
            if castWidthAdjSlider then
                local isLocked = (castDB.anchor == "essential" or castDB.anchor == "utility" or castDB.anchor == "unitframe")
                castWidthAdjSlider:SetEnabled(isLocked)
            end
            
            -- Enable X/Y offset sliders for all anchor modes
            -- "none" mode: offset from screen center (absolute positioning)
            -- locked modes: offset from anchor (relative positioning)
            if castOffsetXSlider and castOffsetYSlider then
                castOffsetXSlider:SetEnabled(true)
                castOffsetYSlider:SetEnabled(true)
            end
        end
        
        -- Track previous anchor to swap offsets when mode changes
        local prevAnchor = castDB.anchor or "none"

        anchorDropdown = GUI:CreateFormDropdown(tabContent, "Autoresize + Lock To", anchorOptions, "anchor", castDB, function()
            -- Clear all lock flags when anchor changes
            castDB.lockedToFrame = false
            castDB.lockedToEssential = false
            castDB.lockedToUtility = false
            -- Clear width to allow anchors to control sizing (only for essential/utility)
            if castDB.anchor == "essential" or castDB.anchor == "utility" then
                castDB.width = 0
            end

            -- Swap offsets between free (none) and locked modes
            local wasNone = (prevAnchor == "none")
            local isNone = (castDB.anchor == "none")

            if wasNone and not isNone then
                -- Switching FROM none TO locked: save free offsets, load locked offsets
                castDB.freeOffsetX = castDB.offsetX or 0
                castDB.freeOffsetY = castDB.offsetY or 0
                castDB.offsetX = castDB.lockedOffsetX or 0
                castDB.offsetY = castDB.lockedOffsetY or -25
            elseif not wasNone and isNone then
                -- Switching FROM locked TO none: save locked offsets, load free offsets
                castDB.lockedOffsetX = castDB.offsetX or 0
                castDB.lockedOffsetY = castDB.offsetY or 0
                castDB.offsetX = castDB.freeOffsetX or 0
                castDB.offsetY = castDB.freeOffsetY or 0
            end
            -- If locked→locked (e.g. essential→utility), keep current offsets

            -- Update previous anchor for next change
            prevAnchor = castDB.anchor

            UpdateCastbarSliders()
            RefreshUnit()
        end)
        anchorDropdown:SetPoint("TOPLEFT", PAD, y)
        anchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

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
        castPreviewTrack:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})

        -- Thumb (sliding circle)
        local castPreviewThumb = CreateFrame("Frame", nil, castPreviewTrack, "BackdropTemplate")
        castPreviewThumb:SetSize(16, 16)
        castPreviewThumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
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

        -- Quick Snap buttons row (one-time snap)
        local snapContainer = CreateFrame("Frame", nil, tabContent)
        snapContainer:SetHeight(FORM_ROW)
        snapContainer:SetPoint("TOPLEFT", PAD, y)
        snapContainer:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)

        local snapLabel = snapContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapLabel:SetPoint("LEFT", 0, 0)
        snapLabel:SetText("Quick Snap")
        snapLabel:SetTextColor(C.text[1], C.text[2], C.text[3], 1)

        -- Snap to Frame button
        local snapFrameBtn = CreateFrame("Button", nil, snapContainer, "BackdropTemplate")
        snapFrameBtn:SetSize(100, 24)
        snapFrameBtn:SetPoint("LEFT", snapContainer, "LEFT", 180, 0)
        snapFrameBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        snapFrameBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        snapFrameBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        local snapFrameBtnText = snapFrameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        snapFrameBtnText:SetPoint("CENTER")
        snapFrameBtnText:SetText("To Frame")
        snapFrameBtnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        snapFrameBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
        snapFrameBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)

        local snapEssentialBtn, snapUtilityBtn
        if unitKey == "player" then
            -- Snap to Essential button
            snapEssentialBtn = CreateFrame("Button", nil, snapContainer, "BackdropTemplate")
            snapEssentialBtn:SetSize(100, 24)
            snapEssentialBtn:SetPoint("LEFT", snapFrameBtn, "RIGHT", 8, 0)
            snapEssentialBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
            snapEssentialBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            snapEssentialBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            local snapEssentialBtnText = snapEssentialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            snapEssentialBtnText:SetPoint("CENTER")
            snapEssentialBtnText:SetText("To Essentials")
            snapEssentialBtnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            snapEssentialBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
            snapEssentialBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)

            -- Snap to Utility button
            snapUtilityBtn = CreateFrame("Button", nil, snapContainer, "BackdropTemplate")
            snapUtilityBtn:SetSize(100, 24)
            snapUtilityBtn:SetPoint("LEFT", snapEssentialBtn, "RIGHT", 8, 0)
            snapUtilityBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
            snapUtilityBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            snapUtilityBtn:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            local snapUtilityBtnText = snapUtilityBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            snapUtilityBtnText:SetPoint("CENTER")
            snapUtilityBtnText:SetText("To Utility")
            snapUtilityBtnText:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
            snapUtilityBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
            snapUtilityBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)
        end
        y = y - FORM_ROW

        -- Copy Settings From dropdown
        local castbarCopyOptions = {}
        local castbarUnits = {
            {key = "player", text = "Player"},
            {key = "target", text = "Target"},
            {key = "targettarget", text = "ToT"},
            {key = "focus", text = "Focus"},
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
        local function CopyCastbarSettings(sourceDB, targetDB)
            if not sourceDB or not targetDB then return end
            local keys = {"width", "height", "offsetX", "offsetY", "fontSize", "borderSize", "maxLength", "texture", "showIcon", "enabled", "anchor", "iconAnchor", "iconSpacing", "spellTextAnchor", "spellTextOffsetX", "spellTextOffsetY", "timeTextAnchor", "timeTextOffsetX", "timeTextOffsetY", "showSpellText", "showTimeText", "useClassColor", "empoweredStageColors", "empoweredFillColors"}
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
                    CopyCastbarSettings(sourceUnitDB.castbar, castDB)
                    RefreshUnit()
                end
            end
        end)
        castCopyApplyBtn:SetPoint("RIGHT", castCopyRow, "RIGHT", 0, 2)

        local castCopyDropdown = GUI:CreateFormDropdown(castCopyRow, "Copy Settings From", castbarCopyOptions, "selected", castCopyWrapper, nil)
        castCopyDropdown:SetPoint("TOPLEFT", 0, 0)
        castCopyDropdown:SetPoint("RIGHT", castCopyApplyBtn, "LEFT", -8, 0)
        y = y - FORM_ROW

        -- Quick Snap button click handlers (one-time snap, no lock)
        snapFrameBtn:SetScript("OnClick", function()
            castDB.anchor = "unitframe"
            castDB.offsetX = 0
            castDB.offsetY = 0
            castDB.width = unitDB.width or 250

            UpdateCastbarSliders()
            RefreshUnit()
        end)

        if snapEssentialBtn then
            snapEssentialBtn:SetScript("OnClick", function()
                local viewer = _G["EssentialCooldownViewer"]
                if viewer and viewer:IsShown() then
                    castDB.anchor = "essential"
                    castDB.offsetX = 0
                    castDB.offsetY = 0
                    castDB.width = 0  -- Clear width to allow dual anchors to control sizing

                    UpdateCastbarSliders()
                    RefreshUnit()
                else
                    print("|cFF56D1FFQUI:|r Essential Cooldowns viewer not visible.")
                end
            end)
        end

        if snapUtilityBtn then
            snapUtilityBtn:SetScript("OnClick", function()
                local viewer = _G["UtilityCooldownViewer"]
                if viewer and viewer:IsShown() then
                    castDB.anchor = "utility"
                    castDB.offsetX = 0
                    castDB.offsetY = 0
                    castDB.width = 0  -- Clear width to allow dual anchors to control sizing

                    UpdateCastbarSliders()
                    RefreshUnit()
                else
                    print("|cFF56D1FFQUI:|r Utility Cooldowns viewer not visible.")
                end
            end)
        end

        castWidthSlider = GUI:CreateFormSlider(tabContent, "Width", 50, 2000, 1, "width", castDB, RefreshUnit)
        castWidthSlider:SetPoint("TOPLEFT", PAD, y)
        castWidthSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Width Adjustment On Lock: fine-tune width when locked to anchor (enabled only when locked)
        castWidthAdjSlider = GUI:CreateFormSlider(tabContent, "Width Adjustment On Lock", -500, 500, 1, "widthAdjustment", castDB, RefreshUnit)
        castWidthAdjSlider:SetPoint("TOPLEFT", PAD, y)
        castWidthAdjSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW
        -- Set initial enabled state (will be updated by UpdateCastbarSliders)
        local isLocked = (castDB.anchor == "essential" or castDB.anchor == "utility" or castDB.anchor == "unitframe")
        castWidthAdjSlider:SetEnabled(isLocked)

        castHeightSlider = GUI:CreateFormSlider(tabContent, "Bar Height", 4, 60, 1, "height", castDB, RefreshUnit)
        castHeightSlider:SetPoint("TOPLEFT", PAD, y)
        castHeightSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Size", 8, 80, 1, "iconSize", castDB, RefreshUnit)
        iconSizeSlider:SetPoint("TOPLEFT", PAD, y)
        iconSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        castOffsetXSlider = GUI:CreateFormSlider(tabContent, "X Offset", -3000, 3000, 1, "offsetX", castDB, RefreshUnit)
        castOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        castOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        castOffsetYSlider = GUI:CreateFormSlider(tabContent, "Y Offset", -3000, 3000, 1, "offsetY", castDB, RefreshUnit)
        castOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        castOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Channel fill direction toggle
        local channelFillCheck = GUI:CreateFormCheckbox(tabContent, "Channel spells fill forward", "channelFillForward", castDB, RefreshUnit)
        channelFillCheck:SetPoint("TOPLEFT", PAD, y)
        channelFillCheck:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- ========================================
        -- TEXT & DISPLAY
        -- ========================================
        local textDisplayLabel = GUI:CreateLabel(tabContent, "Text & Display", 12, C.accentLight)
        textDisplayLabel:SetPoint("TOPLEFT", PAD, y)
        textDisplayLabel:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        textDisplayLabel:SetJustifyH("LEFT")
        y = y - 20

        local castFontSizeSlider = GUI:CreateFormSlider(tabContent, "Font Size", 8, 24, 1, "fontSize", castDB, RefreshUnit)
        castFontSizeSlider:SetPoint("TOPLEFT", PAD, y)
        castFontSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local castMaxLengthSlider = GUI:CreateFormSlider(tabContent, "Max Length (0=none)", 0, 30, 1, "maxLength", castDB, RefreshUnit)
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
        local iconAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Icon Anchor", NINE_POINT_ANCHOR_OPTIONS, "iconAnchor", castDB, RefreshUnit)
        iconAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        iconAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Icon", "showIcon", castDB, RefreshUnit)
        iconVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
        iconVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconSpacingSlider = GUI:CreateFormSlider(tabContent, "Icon Spacing", -50, 50, 1, "iconSpacing", castDB, RefreshUnit)
        iconSpacingSlider:SetPoint("TOPLEFT", PAD, y)
        iconSpacingSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconBorderSizeSlider = GUI:CreateFormSlider(tabContent, "Icon Border Size", 0, 5, 0.1, "iconBorderSize", castDB, RefreshUnit)
        iconBorderSizeSlider:SetPoint("TOPLEFT", PAD, y)
        iconBorderSizeSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local iconScaleSlider = GUI:CreateFormSlider(tabContent, "Icon Scale", 0.5, 2.0, 0.1, "iconScale", castDB, RefreshUnit)
        iconScaleSlider:SetPoint("TOPLEFT", PAD, y)
        iconScaleSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Spell text settings
        local spellTextAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Spell Text Anchor", NINE_POINT_ANCHOR_OPTIONS, "spellTextAnchor", castDB, RefreshUnit)
        spellTextAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        spellTextAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spellTextVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Spell Text", "showSpellText", castDB, RefreshUnit)
        spellTextVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
        spellTextVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spellTextOffsetXSlider = GUI:CreateFormSlider(tabContent, "Spell Text X Offset", -200, 200, 1, "spellTextOffsetX", castDB, RefreshUnit)
        spellTextOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        spellTextOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local spellTextOffsetYSlider = GUI:CreateFormSlider(tabContent, "Spell Text Y Offset", -200, 200, 1, "spellTextOffsetY", castDB, RefreshUnit)
        spellTextOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        spellTextOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Time text settings
        local timeTextAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Time Text Anchor", NINE_POINT_ANCHOR_OPTIONS, "timeTextAnchor", castDB, RefreshUnit)
        timeTextAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
        timeTextAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local timeTextVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Time Text", "showTimeText", castDB, RefreshUnit)
        timeTextVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
        timeTextVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local timeTextOffsetXSlider = GUI:CreateFormSlider(tabContent, "Time Text X Offset", -200, 200, 1, "timeTextOffsetX", castDB, RefreshUnit)
        timeTextOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
        timeTextOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        local timeTextOffsetYSlider = GUI:CreateFormSlider(tabContent, "Time Text Y Offset", -200, 200, 1, "timeTextOffsetY", castDB, RefreshUnit)
        timeTextOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
        timeTextOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
        y = y - FORM_ROW

        -- Empowered settings (player only)
        if unitKey == "player" then
            -- Hide time text on empowered
            if castDB.hideTimeTextOnEmpowered == nil then castDB.hideTimeTextOnEmpowered = false end

            local hideTimeTextOnEmpoweredToggle = GUI:CreateFormToggle(tabContent, "Hide Time Text on Empowered", "hideTimeTextOnEmpowered", castDB, RefreshUnit)
            hideTimeTextOnEmpoweredToggle:SetPoint("TOPLEFT", PAD, y)
            hideTimeTextOnEmpoweredToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Empowered level text settings
            if castDB.empoweredLevelTextAnchor == nil then castDB.empoweredLevelTextAnchor = "CENTER" end
            if castDB.empoweredLevelTextOffsetX == nil then castDB.empoweredLevelTextOffsetX = 0 end
            if castDB.empoweredLevelTextOffsetY == nil then castDB.empoweredLevelTextOffsetY = 0 end
            if castDB.showEmpoweredLevel == nil then castDB.showEmpoweredLevel = false end

            local empoweredLevelTextAnchorDropdown = GUI:CreateFormDropdown(tabContent, "Empowered Level Text Anchor", NINE_POINT_ANCHOR_OPTIONS, "empoweredLevelTextAnchor", castDB, RefreshUnit)
            empoweredLevelTextAnchorDropdown:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextAnchorDropdown:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local empoweredLevelTextVisibilityToggle = GUI:CreateFormToggle(tabContent, "Show Empowered Level", "showEmpoweredLevel", castDB, RefreshUnit)
            empoweredLevelTextVisibilityToggle:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextVisibilityToggle:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local empoweredLevelTextOffsetXSlider = GUI:CreateFormSlider(tabContent, "Empowered Level Text X Offset", -200, 200, 1, "empoweredLevelTextOffsetX", castDB, RefreshUnit)
            empoweredLevelTextOffsetXSlider:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextOffsetXSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            local empoweredLevelTextOffsetYSlider = GUI:CreateFormSlider(tabContent, "Empowered Level Text Y Offset", -200, 200, 1, "empoweredLevelTextOffsetY", castDB, RefreshUnit)
            empoweredLevelTextOffsetYSlider:SetPoint("TOPLEFT", PAD, y)
            empoweredLevelTextOffsetYSlider:SetPoint("RIGHT", tabContent, "RIGHT", -PAD, 0)
            y = y - FORM_ROW

            -- Empowered color overrides section
            local empoweredColorsHeader = GUI:CreateSectionHeader(tabContent, "Empowered Color Overrides")
            empoweredColorsHeader:SetPoint("TOPLEFT", PAD, y)
            y = y - empoweredColorsHeader.gap

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
                local stageColorPicker = GUI:CreateFormColorPicker(tabContent, "Stage " .. i .. " Color", i, castDB.empoweredStageColors, RefreshUnit)
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
                local fillColorPicker = GUI:CreateFormColorPicker(tabContent, "Fill " .. i .. " Color", i, castDB.empoweredFillColors, RefreshUnit)
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
            resetBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
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

        -- Initialize UI state
        UpdateCastbarSliders()

    end
    
    return y
end

-- Export the function
ns.QUI_CastbarOptions = {
    BuildCastbarOptions = BuildCastbarOptions
}

