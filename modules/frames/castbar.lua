--[[
    QUI Castbar Module
    Extracted from qui_unitframes.lua for better organization
    Handles castbar creation and management for player, target, focus, and boss units
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local Helpers = ns.Helpers
local IsSecretValue = Helpers.IsSecretValue
local SafeValue = Helpers.SafeValue

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_Castbar = {}
ns.QUI_Castbar = QUI_Castbar

QUI_Castbar.castbars = {}

local Helpers = {}

---------------------------------------------------------------------------
-- SETUP HELPERS
---------------------------------------------------------------------------
function QUI_Castbar:SetHelpers(helpers)
    Helpers = helpers or {}
end

-- Helper function wrappers (with fallbacks)
local function GetUnitSettings(unit)
    return Helpers.GetUnitSettings and Helpers.GetUnitSettings(unit) or nil
end

local function Scale(x)
    return Helpers.Scale and Helpers.Scale(x) or x
end

local function GetFontPath()
    return Helpers.GetFontPath and Helpers.GetFontPath() or "Fonts\\FRIZQT__.TTF"
end

local function GetFontOutline()
    return Helpers.GetFontOutline and Helpers.GetFontOutline() or "OUTLINE"
end

local function GetTexturePath(textureName)
    return Helpers.GetTexturePath and Helpers.GetTexturePath(textureName) or "Interface\\Buttons\\WHITE8x8"
end

local function GetUnitClassColor(unit)
    if Helpers.GetUnitClassColor then
        return Helpers.GetUnitClassColor(unit)
    end
    return 0.5, 0.5, 0.5, 1
end

local function TruncateName(name, maxLength)
    return Helpers.TruncateName and Helpers.TruncateName(name, maxLength) or name
end

local function GetGeneralSettings()
    return Helpers.GetGeneralSettings and Helpers.GetGeneralSettings() or nil
end

local function GetDB()
    return Helpers.GetDB and Helpers.GetDB() or nil
end

---------------------------------------------------------------------------
-- SECRET VALUE HANDLING (Midnight 12.0+)
-- CRITICAL: tostring() on secret values THROWS ERROR
-- Use _G.ToPlain (WoW API) or pcall(tonumber) instead
---------------------------------------------------------------------------
-- Convert value to plain number (handles secret values from Midnight API)
-- Simpler approach: trust type check, don't over-validate
local function SafeToNumber(v)
    if v == nil then return nil end
    -- If already a number, return it directly (trust type check)
    if type(v) == "number" then return v end
    -- Try tonumber for non-number types
    local ok, n = pcall(tonumber, v)
    if ok and type(n) == "number" then return n end
    return nil
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
QUI_Castbar.STAGE_COLORS = {
    {0.15, 0.38, 0.58, 1},   -- Stage 1: Dark Blue
    {0.55, 0.20, 0.24, 1},   -- Stage 2: Dark Red/Pink
    {0.58, 0.45, 0.18, 1},   -- Stage 3: Dark Yellow/Orange
    {0.27, 0.50, 0.21, 1},   -- Stage 4: Dark Green
    {0.45, 0.20, 0.50, 1},   -- Stage 5: Dark Purple
}

QUI_Castbar.STAGE_FILL_COLORS = {
    {0.26, 0.64, 0.96, 1},   -- Stage 1: Bright Blue
    {0.91, 0.35, 0.40, 1},   -- Stage 2: Bright Red/Pink
    {0.95, 0.75, 0.30, 1},   -- Stage 3: Bright Yellow/Orange
    {0.45, 0.82, 0.35, 1},   -- Stage 4: Bright Green
    {0.75, 0.40, 0.85, 1},   -- Stage 5: Bright Purple
}

-- Local references for internal use
local STAGE_COLORS = QUI_Castbar.STAGE_COLORS
local STAGE_FILL_COLORS = QUI_Castbar.STAGE_FILL_COLORS

---------------------------------------------------------------------------
-- SETTINGS HELPERS
---------------------------------------------------------------------------
local function GetCastSettings(unitKey)
    local settings = GetUnitSettings(unitKey)
    return settings and settings.castbar or nil
end

-- Text throttling helper (updates text at 10 FPS to reduce overhead)
local function UpdateThrottledText(castbar, elapsed, text, value)
    castbar.textThrottle = (castbar.textThrottle or 0) + elapsed
    if castbar.textThrottle >= 0.1 then
        castbar.textThrottle = 0
        if text then
            text:SetText(string.format("%.1f", value))
        end
        return true
    end
    return false
end

local function InitializeDefaultSettings(castSettings)
    if castSettings.iconAnchor == nil then castSettings.iconAnchor = "LEFT" end
    if castSettings.iconSpacing == nil then castSettings.iconSpacing = 0 end
    if castSettings.showIcon == nil then castSettings.showIcon = true end
    
    if not castSettings.borderColor then
        castSettings.borderColor = {0, 0, 0, 1}
    elseif not castSettings.borderColor[4] then
        castSettings.borderColor[4] = 1
    end
    if not castSettings.iconBorderColor then
        castSettings.iconBorderColor = {0, 0, 0, 1}
    elseif not castSettings.iconBorderColor[4] then
        castSettings.iconBorderColor[4] = 1
    end
    if castSettings.iconBorderSize == nil then
        castSettings.iconBorderSize = 2
    end
    
    if castSettings.statusBarAnchor == nil then castSettings.statusBarAnchor = "BOTTOMRIGHT" end
    
    if castSettings.spellTextAnchor == nil then castSettings.spellTextAnchor = "LEFT" end
    if castSettings.spellTextOffsetX == nil then castSettings.spellTextOffsetX = 4 end
    if castSettings.spellTextOffsetY == nil then castSettings.spellTextOffsetY = 0 end
    if castSettings.showSpellText == nil then castSettings.showSpellText = true end
    
    if castSettings.timeTextAnchor == nil then castSettings.timeTextAnchor = "RIGHT" end
    if castSettings.timeTextOffsetX == nil then castSettings.timeTextOffsetX = -4 end
    if castSettings.timeTextOffsetY == nil then castSettings.timeTextOffsetY = 0 end
    if castSettings.showTimeText == nil then castSettings.showTimeText = true end

    -- Empowered cast settings
    if castSettings.empoweredLevelTextAnchor == nil then castSettings.empoweredLevelTextAnchor = "CENTER" end
    if castSettings.empoweredLevelTextOffsetX == nil then castSettings.empoweredLevelTextOffsetX = 0 end
    if castSettings.empoweredLevelTextOffsetY == nil then castSettings.empoweredLevelTextOffsetY = 0 end
    if castSettings.showEmpoweredLevel == nil then castSettings.showEmpoweredLevel = false end
    if castSettings.hideTimeTextOnEmpowered == nil then castSettings.hideTimeTextOnEmpowered = false end

    -- Empowered color overrides (player only) - initialize with default constants
    if not castSettings.empoweredStageColors then
        castSettings.empoweredStageColors = {}
        for i = 1, 5 do
            if STAGE_COLORS[i] then
                castSettings.empoweredStageColors[i] = {STAGE_COLORS[i][1], STAGE_COLORS[i][2], STAGE_COLORS[i][3], STAGE_COLORS[i][4]}
            end
        end
    end
    if not castSettings.empoweredFillColors then
        castSettings.empoweredFillColors = {}
        for i = 1, 5 do
            if STAGE_FILL_COLORS[i] then
                castSettings.empoweredFillColors[i] = {STAGE_FILL_COLORS[i][1], STAGE_FILL_COLORS[i][2], STAGE_FILL_COLORS[i][3], STAGE_FILL_COLORS[i][4]}
            end
        end
    end
end

local function GetSizingValues(castSettings)
    local barHeight = Scale(castSettings.height or 25)
    barHeight = math.max(barHeight, Scale(4))
    local iconSize = Scale((castSettings.iconSize and castSettings.iconSize > 0) and castSettings.iconSize or 25)
    local iconScale = castSettings.iconScale or 1.0
    return barHeight, iconSize, iconScale
end

---------------------------------------------------------------------------
-- COLOR HELPERS
---------------------------------------------------------------------------
-- Default colors
local DEFAULT_BAR_COLOR = {1, 0.7, 0, 1}
local DEFAULT_BG_COLOR = {0.149, 0.149, 0.149, 1}
local NOT_INTERRUPTIBLE_COLOR = {0.7, 0.2, 0.2, 1}

-- Safe color getter - returns valid color table or fallback
local function GetSafeColor(color, fallback)
    if color and color[1] and color[2] and color[3] then
        return color[1], color[2], color[3], color[4] or 1
    end
    fallback = fallback or DEFAULT_BAR_COLOR
    return fallback[1], fallback[2], fallback[3], fallback[4] or 1
end

---------------------------------------------------------------------------
-- BORDER CREATION
---------------------------------------------------------------------------
local function CreateStatusBarBorder(statusBar, borderSize, borderColor)
    local border = CreateFrame("Frame", nil, statusBar, "BackdropTemplate")
    border:SetFrameLevel(statusBar:GetFrameLevel() - 1)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",  -- Solid border texture
        edgeSize = borderSize,
    })
    local r, g, b, a = GetSafeColor(borderColor, {0, 0, 0, 1})
    border:SetBackdropBorderColor(r, g, b, a)
    statusBar.Border = border
    return border
end

---------------------------------------------------------------------------
-- UI ELEMENT CREATION
---------------------------------------------------------------------------
local function CreateAnchorFrame(name, parent)
    local anchorFrame = CreateFrame("Frame", name, parent)
    anchorFrame:SetFrameStrata("MEDIUM")
    anchorFrame:SetFrameLevel(200)
    anchorFrame:Hide()
    return anchorFrame
end

local function CreateCastbarFrame(name, parent)
    return CreateAnchorFrame(name, parent)
end

local function CreateIcon(anchorFrame, iconSize, iconBorderSize, iconBorderColor)
    local iconFrame = CreateFrame("Frame", nil, anchorFrame)
    iconFrame:SetSize(iconSize, iconSize)
    iconFrame:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)

    -- Border fills the iconFrame (background layer)
    local border = iconFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    local r, g, b, a = GetSafeColor(iconBorderColor, {0, 0, 0, 1})
    border:SetColorTexture(r, g, b, a)
    border:SetAllPoints(iconFrame)
    iconFrame.border = border

    -- Icon texture is inset by borderSize so border shows around it
    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", iconBorderSize, -iconBorderSize)
    iconTexture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -iconBorderSize, iconBorderSize)
    iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.texture = iconTexture

    anchorFrame.icon = iconFrame
    anchorFrame.iconTexture = iconTexture
    anchorFrame.iconBorder = border
    return iconFrame
end

local function CreateStatusBar(anchorFrame)
    local statusBar = CreateFrame("StatusBar", nil, anchorFrame)
    statusBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    anchorFrame.statusBar = statusBar
    return statusBar
end

local function CreateBackgroundBar(statusBar)
    local bgBar = statusBar:CreateTexture(nil, "BACKGROUND")
    bgBar:SetAllPoints()
    bgBar:SetTexture("Interface\\Buttons\\WHITE8x8")
    return bgBar
end

local function CreateTextElement(statusBar, fontSize, layer)
    local text = statusBar:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(GetFontPath(), fontSize, GetFontOutline())
    text:SetTextColor(1, 1, 1, 1)
    return text
end

local function GetBarColor(unitKey, castSettings)
    if unitKey == "player" and castSettings.useClassColor then
        local _, class = UnitClass("player")
        if class and RAID_CLASS_COLORS[class] then
            local c = RAID_CLASS_COLORS[class]
            return {c.r, c.g, c.b, 1}
        end
    end
    return castSettings.color or DEFAULT_BAR_COLOR
end

local function ApplyBarColor(statusBar, barColor)
    local r, g, b, a = GetSafeColor(barColor, DEFAULT_BAR_COLOR)
    statusBar:SetStatusBarColor(r, g, b, a)
end

local function ApplyBackgroundColor(bgBar, bgColor)
    local r, g, b, a = GetSafeColor(bgColor, DEFAULT_BG_COLOR)
    bgBar:SetVertexColor(r, g, b, a)
end

local function ApplyCastColor(statusBar, notInterruptible, customColor)
    -- Safely handle secret values (TWW API protection)
    -- Wrap entire check in pcall - if ANY comparison fails, default to interruptible (false)
    local isNotInterruptible = false
    local ok, result = pcall(function()
        return notInterruptible == true
    end)
    if ok and result then
        isNotInterruptible = true
    end

    if isNotInterruptible then
        local r, g, b, a = GetSafeColor(NOT_INTERRUPTIBLE_COLOR)
        statusBar:SetStatusBarColor(r, g, b, a)
    else
        local r, g, b, a = GetSafeColor(customColor, DEFAULT_BAR_COLOR)
        statusBar:SetStatusBarColor(r, g, b, a)
    end
end

---------------------------------------------------------------------------
-- POSITIONING HELPERS
---------------------------------------------------------------------------
local function PositionCastbarByAnchor(anchorFrame, castSettings, unitFrame, barHeight)
    local anchor = castSettings.anchor or "none"
    
    anchorFrame:ClearAllPoints()
    
    if anchor == "essential" then
        local offsetX = Scale(castSettings.offsetX or 0)
        local offsetY = math.floor(Scale(castSettings.offsetY or -25) + 0.5)
        local widthAdj = Scale(castSettings.widthAdjustment or 0)
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            anchorFrame:SetPoint("TOPLEFT", viewer, "BOTTOMLEFT", offsetX - widthAdj, offsetY)
            anchorFrame:SetPoint("TOPRIGHT", viewer, "BOTTOMRIGHT", offsetX + widthAdj, offsetY)
        else
            anchorFrame:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", offsetX, offsetY)
        end
    elseif anchor == "utility" then
        local offsetX = Scale(castSettings.offsetX or 0)
        local offsetY = math.floor(Scale(castSettings.offsetY or -25) + 0.5)
        local widthAdj = Scale(castSettings.widthAdjustment or 0)
        local viewer = _G["UtilityCooldownViewer"]
        if viewer then
            anchorFrame:SetPoint("TOPLEFT", viewer, "BOTTOMLEFT", offsetX - widthAdj, offsetY)
            anchorFrame:SetPoint("TOPRIGHT", viewer, "BOTTOMRIGHT", offsetX + widthAdj, offsetY)
        else
            anchorFrame:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", offsetX, offsetY)
        end
    elseif anchor == "unitframe" then
        local offsetX = Scale(castSettings.offsetX or 0)
        local offsetY = math.floor(Scale(castSettings.offsetY or -25) + 0.5)
        local widthAdj = Scale(castSettings.widthAdjustment or 0)
        anchorFrame:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", offsetX - widthAdj, offsetY)
        anchorFrame:SetPoint("TOPRIGHT", unitFrame, "BOTTOMRIGHT", offsetX + widthAdj, offsetY)
    else
        -- None: positioned independently on screen
        local offsetX = castSettings.offsetX or 0
        local offsetY = castSettings.offsetY or 0
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end
end

local function SetCastbarSize(anchorFrame, castSettings, unitFrame, barHeight)
    local anchor = castSettings.anchor or "none"
    
    if anchor == "essential" or anchor == "utility" then
        anchorFrame:SetSize(1, barHeight)
    elseif anchor == "none" then
        local frameWidth = unitFrame:GetWidth() or 250
        local castWidth = Scale((castSettings.width and castSettings.width > 0) and castSettings.width or frameWidth)
        anchorFrame:SetSize(castWidth, barHeight)
    else
        local frameWidth = unitFrame:GetWidth() or 250
        local castWidth = Scale((castSettings.width > 0) and castSettings.width or frameWidth)
        anchorFrame:SetSize(castWidth, barHeight)
    end
end

---------------------------------------------------------------------------
-- ELEMENT POSITIONING HELPERS
---------------------------------------------------------------------------
local function ShouldShowIcon(anchorFrame, castSettings)
    return castSettings.showIcon == true
end

local function UpdateIconPosition(anchorFrame, castSettings, iconSize, iconScale, iconBorderSize)
    local iconFrame = anchorFrame.icon
    local iconTexture = anchorFrame.iconTexture
    local iconBorder = anchorFrame.iconBorder

    if not ShouldShowIcon(anchorFrame, castSettings) or not iconFrame then
        if iconFrame then iconFrame:Hide() end
        return false
    end

    local baseIconSize = iconSize * iconScale
    iconFrame:SetSize(baseIconSize, baseIconSize)
    iconFrame:ClearAllPoints()
    local iconAnchor = castSettings.iconAnchor or "TOPLEFT"
    iconFrame:SetPoint(iconAnchor, anchorFrame, iconAnchor, 0, 0)

    local textureToUse = anchorFrame.currentIconTexture or anchorFrame.previewIconTexture
    if textureToUse and iconTexture then
        iconTexture:SetTexture(textureToUse)
        -- Inset texture by borderSize so border shows around it
        iconTexture:ClearAllPoints()
        iconTexture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", iconBorderSize, -iconBorderSize)
        iconTexture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -iconBorderSize, iconBorderSize)
        if ShouldShowIcon(anchorFrame, castSettings) then
            iconFrame:Show()
        else
            iconFrame:Hide()
            return false
        end

        if iconBorder then
            local r, g, b, a = GetSafeColor(castSettings.iconBorderColor, {0, 0, 0, 1})
            iconBorder:SetColorTexture(r, g, b, a)
            iconBorder:ClearAllPoints()
            iconBorder:SetAllPoints(iconFrame)
        end
        return true
    else
        iconFrame:Hide()
        return false
    end
end

local function UpdateStatusBarPosition(anchorFrame, castSettings, barHeight, iconSize, iconScale, borderSize)
    local statusBar = anchorFrame.statusBar
    local border = statusBar and statusBar.Border

    if not statusBar then return end

    statusBar:SetHeight(barHeight)
    statusBar:ClearAllPoints()

    -- Inset statusBar by borderSize so border is visible around it (like unit frames)
    if ShouldShowIcon(anchorFrame, castSettings) then
        local iconSizePx = iconSize * iconScale
        local iconSpacing = Scale(castSettings.iconSpacing or 0)
        local iconAnchor = castSettings.iconAnchor or "TOPLEFT"
        if iconAnchor:find("LEFT") then
            statusBar:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", iconSizePx + iconSpacing + borderSize, -borderSize)
            statusBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -borderSize, borderSize)
        elseif iconAnchor:find("RIGHT") then
            statusBar:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", borderSize, -borderSize)
            statusBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -iconSizePx - iconSpacing - borderSize, borderSize)
        else
            statusBar:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", borderSize, -borderSize)
            statusBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -borderSize, borderSize)
        end
    else
        statusBar:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", borderSize, -borderSize)
        statusBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -borderSize, borderSize)
    end
    
    if border then
        border:SetFrameLevel(statusBar:GetFrameLevel() - 1)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
        border:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)

        -- Only show border if borderSize > 0 (edgeSize=0 causes WoW to use texture's natural size)
        if borderSize > 0 then
            border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = borderSize,
            })
            local r, g, b, a = GetSafeColor(castSettings.borderColor, {0, 0, 0, 1})
            border:SetBackdropBorderColor(r, g, b, a)
            border:Show()
        else
            border:SetBackdrop(nil)
            border:Hide()
        end
    end
end

local function UpdateTextPosition(textElement, statusBar, anchor, offsetX, offsetY, show)
    if not textElement then return end
    
    if show then
        textElement:ClearAllPoints()
        textElement:SetPoint(anchor, statusBar, anchor, Scale(offsetX), Scale(offsetY))
        textElement:Show()
    else
        textElement:Hide()
    end
end

---------------------------------------------------------------------------
-- MAIN UPDATE FUNCTION
---------------------------------------------------------------------------
local function UpdateCastbarElements(anchorFrame, unitKey, castSettings)
    local currentSettings = GetUnitSettings(unitKey)
    local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
    
    local barHeight, iconSize, iconScale = GetSizingValues(currentCastSettings)
    local borderSize = Scale(currentCastSettings.borderSize or 1)
    local iconBorderSize = Scale(currentCastSettings.iconBorderSize or 1)
    
    anchorFrame:SetHeight(barHeight)
    
    UpdateIconPosition(anchorFrame, currentCastSettings, iconSize, iconScale, iconBorderSize)
    UpdateStatusBarPosition(anchorFrame, currentCastSettings, barHeight, iconSize, iconScale, borderSize)
    
    UpdateTextPosition(
        anchorFrame.spellText, anchorFrame.statusBar,
        currentCastSettings.spellTextAnchor or "LEFT",
        currentCastSettings.spellTextOffsetX or 4,
        currentCastSettings.spellTextOffsetY or 0,
        currentCastSettings.showSpellText
    )

    -- Time text visibility: hide if empowered and setting is enabled
    local showTimeText = currentCastSettings.showTimeText
    if showTimeText and currentCastSettings.hideTimeTextOnEmpowered and anchorFrame.isEmpowered then
        showTimeText = false
    end

    UpdateTextPosition(
        anchorFrame.timeText, anchorFrame.statusBar,
        currentCastSettings.timeTextAnchor or "RIGHT",
        currentCastSettings.timeTextOffsetX or -4,
        currentCastSettings.timeTextOffsetY or 0,
        showTimeText
    )

    -- Empowered level text (player only)
    if unitKey == "player" and anchorFrame.empoweredLevelText then
        UpdateTextPosition(
            anchorFrame.empoweredLevelText, anchorFrame.statusBar,
            currentCastSettings.empoweredLevelTextAnchor or "CENTER",
            currentCastSettings.empoweredLevelTextOffsetX or 0,
            currentCastSettings.empoweredLevelTextOffsetY or 0,
            currentCastSettings.showEmpoweredLevel
        )
    end

    -- Refresh empowered stage overlay colors if currently empowered (for real-time options updates)
    if unitKey == "player" and anchorFrame.isEmpowered and anchorFrame.stageOverlays then
        for i, overlay in ipairs(anchorFrame.stageOverlays) do
            if overlay:IsShown() then
                local stageColor = STAGE_COLORS[i] or STAGE_COLORS[1]
                if currentCastSettings.empoweredStageColors and currentCastSettings.empoweredStageColors[i] then
                    stageColor = currentCastSettings.empoweredStageColors[i]
                end
                overlay:SetColorTexture(unpack(stageColor))
            end
        end
    end
end

---------------------------------------------------------------------------
-- EMPOWERED CAST HELPERS
---------------------------------------------------------------------------
local function ClearEmpoweredState(bar)
    if not bar then return end

    bar.isEmpowered = false
    bar.numStages = 0
    bar.stagePositions = nil
    bar.isInHoldPhase = nil
    
    for _, stage in ipairs(bar.empoweredStages or {}) do
        if stage then stage:Hide() end
    end
    
    if bar.stageOverlays then
        for _, overlay in ipairs(bar.stageOverlays) do
            if overlay then overlay:Hide() end
        end
    end
    
    if bar.bgBar then bar.bgBar:Show() end

    if bar.statusBar then
        ApplyCastColor(bar.statusBar, false, bar.customColor)
    end

    if bar.empoweredLevelText then
        bar.empoweredLevelText:SetText("")
    end
end

---------------------------------------------------------------------------
-- ICON TEXTURE HELPER
---------------------------------------------------------------------------
local function SetIconTexture(castbar, texture)
    if not castbar or not castbar.iconTexture then return false end
    if not texture then return false end
    
    castbar.currentIconTexture = texture
    castbar.iconTexture:SetTexture(texture)
    return true
end

---------------------------------------------------------------------------
-- PREVIEW MODE / SIMULATE CAST
---------------------------------------------------------------------------
local PREVIEW_ICON_ID = 136048

local function SimulateCast(castbar, castSettings, unitKey, bossIndex)
    if not castbar then return end
    
    local castTime = 3.0
    local spellName = (unitKey == "boss" and bossIndex) and ("Boss " .. bossIndex .. " Cast") or "Preview Cast"
    local iconTexture = PREVIEW_ICON_ID
    castbar.isPreviewSimulation = true
    castbar.previewStartTime = GetTime()
    castbar.previewEndTime = GetTime() + castTime
    castbar.previewValue = 0
    castbar.previewMaxValue = castTime
    castbar.previewSpellName = spellName
    castbar.previewIconTexture = iconTexture
    
    -- Set initial visual state
    if castbar.statusBar then
        castbar.statusBar:SetStatusBarTexture(GetTexturePath(castSettings.texture))
        ApplyCastColor(castbar.statusBar, false, castbar.customColor)
        castbar.statusBar:SetMinMaxValues(0, castTime)
        castbar.statusBar:SetValue(0)
        castbar.statusBar:SetReverseFill(false)
    end
    
    if SetIconTexture(castbar, iconTexture) then
        castbar.previewIconTexture = iconTexture
        if ShouldShowIcon(castbar, castSettings) then
            castbar.icon:Show()
        else
            castbar.icon:Hide()
        end
    end
    
    if castbar.spellText then
        castbar.spellText:SetText(spellName)
        castbar.spellText:SetTextColor(1, 1, 1, 1)
        if castSettings.showSpellText ~= false then
            castbar.spellText:Show()
        end
    end
    
    if castbar.timeText then
        castbar.timeText:SetText(string.format("%.1f", castTime))
        castbar.timeText:SetTextColor(1, 1, 1, 1)
        if castSettings.showTimeText ~= false then
            castbar.timeText:Show()
        end
    end
    
    if castbar.bgBar then
        castbar.bgBar:Show()
    end
    
    ClearEmpoweredState(castbar)
    
    if castSettings.anchor == "none" then
        castbar:SetMovable(true)
        castbar:EnableMouse(true)
        castbar:RegisterForDrag("LeftButton")
        castbar:SetClampedToScreen(true)
        
        castbar:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        
        castbar:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local screenX, screenY = UIParent:GetCenter()
            local castbarX, castbarY = self:GetCenter()
            
            if screenX and screenY and castbarX and castbarY then
                local offsetX = castbarX - screenX
                local offsetY = castbarY - screenY
                castSettings.offsetX = offsetX
                castSettings.offsetY = offsetY
                -- Also save to freeOffset for mode switching (drag only works in "none" mode)
                castSettings.freeOffsetX = offsetX
                castSettings.freeOffsetY = offsetY
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
            end
        end)
    else
        castbar:SetMovable(false)
        castbar:EnableMouse(false)
        castbar:SetScript("OnDragStart", nil)
        castbar:SetScript("OnDragStop", nil)
    end
    
    castbar:Show()
end

-- Clear preview simulation
local function ClearPreviewSimulation(castbar)
    if not castbar then return end
    
    castbar.isPreviewSimulation = false
    castbar.previewStartTime = nil
    castbar.previewEndTime = nil
    castbar.previewValue = nil
    castbar.previewMaxValue = nil
    castbar.previewSpellName = nil
    castbar.previewIconTexture = nil
    
    castbar:SetMovable(false)
    castbar:EnableMouse(false)
    castbar:SetScript("OnDragStart", nil)
    castbar:SetScript("OnDragStop", nil)
    
    if not UnitCastingInfo(castbar.unit) and not UnitChannelInfo(castbar.unit) then
        castbar:Hide()
    end
end

---------------------------------------------------------------------------
-- EMPOWERED CAST HELPERS
---------------------------------------------------------------------------
local function UpdateEmpoweredStages(bar, numStages)
    -- Hide existing stage markers and overlays
    for _, stage in ipairs(bar.empoweredStages or {}) do
        if stage then stage:Hide() end
    end
    bar.stageOverlays = bar.stageOverlays or {}
    for _, overlay in ipairs(bar.stageOverlays) do
        if overlay then overlay:Hide() end
    end
    
    if not numStages or numStages <= 0 then
        bar.isEmpowered = false
        bar.numStages = 0
        if bar.bgBar then bar.bgBar:Show() end
        return
    end
    
    bar.isEmpowered = true
    bar.numStages = numStages
    if bar.bgBar then bar.bgBar:Hide() end
    
    C_Timer.After(0, function()
        if not bar.statusBar:IsVisible() then
            C_Timer.After(0.066, function()
                UpdateEmpoweredStages(bar, numStages)
            end)
            return
        end
        
        local barWidth = bar.statusBar:GetWidth()
        if barWidth <= 0 then barWidth = 150 end
        local barHeight = bar.statusBar:GetHeight()
        
        -- Stage boundary positions
        local stagePositions
        if numStages >= 5 then
            stagePositions = {0, 0.15, 0.32, 0.50, 0.68, 0.85, 1.0}
        elseif numStages == 4 then
            stagePositions = {0, 0.18, 0.42, 0.63, 0.84, 1.0}
        elseif numStages == 3 then
            stagePositions = {0, 0.25, 0.50, 0.75, 1.0}
        elseif numStages == 2 then
            stagePositions = {0, 0.50, 1.0}
        else
            stagePositions = {0, 1.0}
        end
        
        bar.stagePositions = stagePositions
        
        -- Create colored overlays for each stage zone
        for i = 1, #stagePositions - 1 do
            local overlay = bar.stageOverlays[i]
            if not overlay then
                overlay = bar.statusBar:CreateTexture(nil, "BACKGROUND", nil, 1)
                bar.stageOverlays[i] = overlay
            end
            
            local startPos = stagePositions[i] * barWidth
            local endPos = stagePositions[i + 1] * barWidth
            local width = endPos - startPos

            -- Get cast settings for color overrides
            local castSettings = GetCastSettings(bar.unitKey)
            local stageColor = STAGE_COLORS[i] or STAGE_COLORS[1]
            if castSettings and castSettings.empoweredStageColors and castSettings.empoweredStageColors[i] then
                stageColor = castSettings.empoweredStageColors[i]
            end

            overlay:SetColorTexture(unpack(stageColor))
            overlay:SetSize(width, barHeight)
            overlay:ClearAllPoints()
            overlay:SetPoint("LEFT", bar.statusBar, "LEFT", startPos, 0)
            overlay:SetPoint("TOP", bar.statusBar, "TOP", 0, 0)
            overlay:SetPoint("BOTTOM", bar.statusBar, "BOTTOM", 0, 0)
            overlay:Show()
        end
        
        -- Create white tick markers between stages
        for i = 2, #stagePositions - 1 do
            local tickIndex = i - 1
            local stage = bar.empoweredStages[tickIndex]
            if not stage then
                stage = bar.statusBar:CreateTexture(nil, "OVERLAY", nil, 2)
                stage:SetColorTexture(1, 1, 1, 0.95)
                stage:SetWidth(2)
                bar.empoweredStages[tickIndex] = stage
            end
            
            stage:SetHeight(barHeight)
            local position = stagePositions[i] * barWidth
            stage:ClearAllPoints()
            stage:SetPoint("LEFT", bar.statusBar, "LEFT", position - 1, 0)
            stage:SetPoint("TOP", bar.statusBar, "TOP", 0, 0)
            stage:SetPoint("BOTTOM", bar.statusBar, "BOTTOM", 0, 0)
            stage:Show()
        end
    end)
end

local function UpdateEmpoweredFillColor(bar, progress, duration)
    if not bar.isEmpowered or not bar.stagePositions then return end

    local progressPercent = progress / duration
    local currentStage = 1

    for i = 2, #bar.stagePositions do
        if progressPercent >= bar.stagePositions[i] then
            currentStage = i
        else
            break
        end
    end

    -- Get cast settings for color overrides
    local castSettings = GetCastSettings(bar.unitKey)
    local fillColors = STAGE_FILL_COLORS
    if castSettings and castSettings.empoweredFillColors then
        -- Use override colors if available, fallback to defaults
        fillColors = {}
        for i = 1, 5 do
            if castSettings.empoweredFillColors[i] then
                fillColors[i] = castSettings.empoweredFillColors[i]
            else
                fillColors[i] = STAGE_FILL_COLORS[i] or STAGE_FILL_COLORS[1]
            end
        end
    end

    if currentStage > #fillColors then
        currentStage = #fillColors
    end

    local c = fillColors[currentStage]
    if c then
        bar.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
end

-- Get current empowered level from player castbar
function QUI_Castbar:GetEmpoweredLevel()
    local playerCastbar = self.castbars["player"]
    if not playerCastbar then
        playerCastbar = _G.QUI_Castbars and _G.QUI_Castbars["player"]
    end

    if not playerCastbar or not playerCastbar.isEmpowered then
        return nil, nil, false
    end

    if not playerCastbar.startTime or not playerCastbar.endTime or not playerCastbar.stagePositions then
        return nil, nil, false
    end

    local now = GetTime()
    local progress = now - playerCastbar.startTime
    local duration = playerCastbar.endTime - playerCastbar.startTime

    if duration <= 0 then
        return nil, nil, false
    end

    local progressPercent = progress / duration
    local currentStage = 0  -- Start at 0 (before first stage boundary)

    for i = 2, #playerCastbar.stagePositions do
        if progressPercent >= playerCastbar.stagePositions[i] then
            currentStage = i - 1  -- Convert array index to stage number (1-based stages)
        else
            break
        end
    end

    -- Cap to actual number of stages (stagePositions has numStages+1 entries for hold phase)
    local maxStages = playerCastbar.numStages or 1
    if currentStage > maxStages then
        currentStage = maxStages
    end

    return currentStage, maxStages, true
end

---------------------------------------------------------------------------
-- TEXT HELPERS
---------------------------------------------------------------------------
local function UpdateSpellText(castbar, text, spellName, castSettings, unit)
    if not castbar.spellText then return end
    
    local displayName = text or spellName or "Casting..."
    local maxLen = castSettings.maxLength
    if maxLen and maxLen > 0 then
        displayName = TruncateName(displayName, maxLen)
    end
    castbar.spellText:SetText(displayName)
    
    local general = GetGeneralSettings()
    if general and general.masterColorCastbarText then
        local r, g, b = GetUnitClassColor(unit)
        castbar.spellText:SetTextColor(r, g, b, 1)
    else
        castbar.spellText:SetTextColor(1, 1, 1, 1)
    end
end

local function UpdateTimeTextColor(castbar, unit)
    if not castbar.timeText then return end
    
    local general = GetGeneralSettings()
    if general and general.masterColorCastbarText then
        local r, g, b = GetUnitClassColor(unit)
        castbar.timeText:SetTextColor(r, g, b, 1)
    else
        castbar.timeText:SetTextColor(1, 1, 1, 1)
    end
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- CREATE: Castbar for a unit frame
---------------------------------------------------------------------------
function QUI_Castbar:CreateCastbar(unitFrame, unit, unitKey)
    local settings = GetUnitSettings(unitKey)
    if not settings or not settings.castbar or not settings.castbar.enabled then
        return nil
    end
    
    local castSettings = settings.castbar
    InitializeDefaultSettings(castSettings)
    
    local barHeight, iconSize, iconScale = GetSizingValues(castSettings)
    local borderSize = Scale(castSettings.borderSize or 1)
    local iconBorderSize = Scale(castSettings.iconBorderSize or 1)
    local fontSize = castSettings.fontSize or 12
    
    local anchorFrame = CreateAnchorFrame(nil, UIParent)
    anchorFrame:SetSize(1, barHeight)

    -- Apply HUD layer priority
    local QUICore = _G.QUI and _G.QUI.QUICore
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority
    if unitKey == "player" then
        layerPriority = hudLayering and hudLayering.playerCastbar or 5
    elseif unitKey == "target" then
        layerPriority = hudLayering and hudLayering.targetCastbar or 5
    else
        layerPriority = 5  -- Default for any other castbar
    end
    if QUICore and QUICore.GetHUDFrameLevel then
        local frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
        anchorFrame:SetFrameLevel(frameLevel)
    end

    CreateIcon(anchorFrame, iconSize, iconBorderSize, castSettings.iconBorderColor)
    local statusBar = CreateStatusBar(anchorFrame)
    
    CreateStatusBarBorder(statusBar, borderSize, castSettings.borderColor)
    
    local bgBar = CreateBackgroundBar(statusBar)
    anchorFrame.bgBar = bgBar
    
    local spellText = CreateTextElement(statusBar, fontSize)
    anchorFrame.spellText = spellText

    local timeText = CreateTextElement(statusBar, fontSize)
    anchorFrame.timeText = timeText

    -- Empowered level text (player only)
    if unitKey == "player" then
        local empoweredLevelText = CreateTextElement(statusBar, fontSize)
        anchorFrame.empoweredLevelText = empoweredLevelText
    end

    anchorFrame.UpdateCastbarElements = function(self)
        UpdateCastbarElements(self, unitKey, castSettings)
    end
    
    SetCastbarSize(anchorFrame, castSettings, unitFrame, barHeight)
    PositionCastbarByAnchor(anchorFrame, castSettings, unitFrame, barHeight)
    
    local barColor = GetBarColor(unitKey, castSettings)
    anchorFrame.customColor = barColor
    ApplyBarColor(statusBar, barColor)
    ApplyBackgroundColor(bgBar, castSettings.bgColor)
    statusBar:SetStatusBarTexture(GetTexturePath(castSettings.texture))

    -- Store unit info
    anchorFrame.unit = unit
    anchorFrame.unitKey = unitKey
    anchorFrame.isChanneled = false
    
    anchorFrame.isEmpowered = false
    anchorFrame.numStages = 0
    anchorFrame.empoweredStages = {}
    anchorFrame.stageOverlays = {}
    
    self:SetupCastbar(anchorFrame, unit, unitKey, castSettings)
    
    UpdateCastbarElements(anchorFrame, unitKey, castSettings)
    if castSettings.previewMode then
        SimulateCast(anchorFrame, castSettings, unitKey)
        -- Start OnUpdate handler for preview
        if anchorFrame.castbarOnUpdate then
            anchorFrame:SetScript("OnUpdate", anchorFrame.castbarOnUpdate)
        end
    end
    
    return anchorFrame
end

---------------------------------------------------------------------------
-- CAST FUNCTION HELPERS
---------------------------------------------------------------------------
-- Get cast information from UnitCastingInfo or UnitChannelInfo
-- Returns: spellName, text, texture, startTimeMS, endTimeMS, notInterruptible, unitSpellID, isChanneled, channelStages, durationObj, hasSecretTiming
local function GetCastInfo(castbar, unit)
    local spellName, text, texture, startTimeMS, endTimeMS, _, _, notInterruptible, unitSpellID = UnitCastingInfo(unit)
    local isChanneled = false
    local channelStages = 0

    if not spellName then
        spellName, text, texture, startTimeMS, endTimeMS, _, notInterruptible, _, _, channelStages = UnitChannelInfo(unit)
        if spellName then
            isChanneled = true
        end
    end

    -- Get duration object for engine-driven animation (Midnight 12.0+)
    -- This is used for non-player units where timing values may be secret
    local durationObj = nil
    if spellName then
        local getDurationFn = isChanneled and UnitChannelDuration or UnitCastingDuration
        if type(getDurationFn) == "function" then
            local ok, dur = pcall(getDurationFn, unit)
            if ok then durationObj = dur end
        end
    end

    -- Check for secret timing values (API restriction for target units in combat)
    local hasSecretTiming = false
    if spellName and startTimeMS and endTimeMS then
        -- Check using issecretvalue if available (12.0+)
        if IsSecretValue(startTimeMS) or IsSecretValue(endTimeMS) then
            hasSecretTiming = true
        end
        -- Also validate with pcall (secret values pass type checks but fail arithmetic)
        if not hasSecretTiming then
            local ok = pcall(function() return startTimeMS + 0 end)
            if not ok then hasSecretTiming = true end
        end
    end

    -- Return all data - don't throw away usable info when timing is secret
    -- Caller can check hasSecretTiming and use durationObj for engine-driven animation
    return spellName, text, texture, startTimeMS, endTimeMS, notInterruptible, unitSpellID, isChanneled, channelStages, durationObj, hasSecretTiming
end

-- Detect if cast is empowered (player only)
local function DetectEmpoweredCast(isPlayer, spellID, unitSpellID, isEmpowerEvent, isChanneled, channelStages)
    if not isPlayer then
        return false, 0
    end
    
    local isEmpowered = isEmpowerEvent or false
    local numStages = 0
    
    if isChanneled and isEmpowerEvent and channelStages and channelStages > 0 then
        numStages = channelStages
        isEmpowered = true
    end
    
    local checkSpellID = spellID or unitSpellID
    if checkSpellID and C_Spell and C_Spell.GetSpellEmpowerInfo then
        local empowerInfo = C_Spell.GetSpellEmpowerInfo(checkSpellID)
        if empowerInfo and empowerInfo.numStages and empowerInfo.numStages > 0 then
            isEmpowered = true
            numStages = empowerInfo.numStages
        end
    end
    
    return isEmpowered, numStages
end

-- Adjust end time for empowered cast hold time
local function AdjustEmpoweredEndTime(castbar, isPlayer, isEmpowered, endTime)
    if not (isPlayer and isEmpowered and GetUnitEmpowerHoldAtMaxTime) then
        return endTime
    end
    
    local ok, adjustedEndTime = pcall(function()
        local ht = GetUnitEmpowerHoldAtMaxTime(castbar.unit)
        if ht and ht > 0 then
            return endTime + (ht / 1000)
        end
        return endTime
    end)
    
    return ok and adjustedEndTime or endTime
end

-- Store cast times in appropriate format
local function StoreCastTimes(castbar, isPlayer, startTimeMS, endTimeMS, startTime, endTime)
    if isPlayer then
        castbar.startTime = startTime
        castbar.endTime = endTime
    else
        castbar.castStartTime = startTimeMS
        castbar.castEndTime = endTimeMS
    end
end

-- Update castbar visual elements (icon, text, colors, bar)
local function UpdateCastbarVisuals(castbar, castSettings, unitKey, texture, text, spellName, unit, isChanneled, notInterruptible, startTime, endTime)
    -- Get current settings
    local currentSettings = GetUnitSettings(unitKey)
    local currentCastSettings = currentSettings and currentSettings.castbar or castSettings

    -- Update status bar texture
    if castbar.statusBar then
        castbar.statusBar:SetStatusBarTexture(GetTexturePath(currentCastSettings.texture))
    end

    -- Icon texture is already set in Cast function before this is called
    -- This function just updates other visual elements

    -- Update spell text
    UpdateSpellText(castbar, text, spellName, castSettings, unit)

    -- Never use reverse fill - drain effect achieved via progress calculation
    local isEmpowered = castbar.isEmpowered
    castbar.statusBar:SetReverseFill(false)

    -- Set initial bar value and time text
    -- Only calculate progress if we have timing values (non-timer-driven mode)
    -- For timer-driven mode, SetTimerDuration already set up the bar
    if startTime and endTime then
        local now = GetTime()
        local duration = endTime - startTime
        local channelFillForward = currentCastSettings and currentCastSettings.channelFillForward
        local shouldDrain = isChanneled and not isEmpowered and not channelFillForward
        local progress = shouldDrain and (endTime - now) or (now - startTime)

        if duration > 0 then
            castbar.statusBar:SetMinMaxValues(0, duration)
            castbar.statusBar:SetValue(math.max(0, math.min(duration, progress)))
        end

        -- Set initial time text
        if castbar.timeText then
            local remaining = endTime - now
            castbar.timeText:SetText(string.format("%.1f", math.max(0, remaining)))
        end
    end

    -- Set color using helper (always apply, regardless of timer mode)
    ApplyCastColor(castbar.statusBar, notInterruptible, castbar.customColor)
end

-- Update empowered cast state
local function UpdateEmpoweredState(castbar, isPlayer, isEmpowered, numStages)
    if isPlayer then
        if isEmpowered and numStages and numStages > 0 then
            UpdateEmpoweredStages(castbar, numStages)
        else
            ClearEmpoweredState(castbar)
        end
    end
end

-- Handle case when no cast is active
local function HandleNoCast(castbar, castSettings, isPlayer, onUpdateHandler)
    C_Timer.After(0.1, function()
        if not UnitCastingInfo(castbar.unit) and not UnitChannelInfo(castbar.unit) then
            if isPlayer then
                ClearEmpoweredState(castbar)
            end

            -- Clear timer-driven state
            castbar.timerDriven = false
            castbar.durationObj = nil

            local settings = GetUnitSettings(castbar.unitKey)
            if settings and settings.castbar and settings.castbar.previewMode then
                -- Show preview simulation
                SimulateCast(castbar, castSettings, castbar.unitKey)
                castbar:SetScript("OnUpdate", onUpdateHandler)
            else
                -- No preview mode - hide
                if castbar.isPreviewSimulation then
                    ClearPreviewSimulation(castbar)
                end
                castbar:SetScript("OnUpdate", nil)
                castbar:Hide()
            end
        end
    end)
end

---------------------------------------------------------------------------
-- UNIFIED CASTBAR SETUP (handles player, target, focus, targettarget)
---------------------------------------------------------------------------
function QUI_Castbar:SetupCastbar(castbar, unit, unitKey, castSettings)
    local isPlayer = (unit == "player")
    
    -- Unified OnUpdate handler - handles both real casts and preview
    local function CastBar_OnUpdate(self, elapsed)
        -- Check if actually casting (real cast takes priority)
        local spellName = UnitCastingInfo(self.unit)
        local channelName = UnitChannelInfo(self.unit)

        -- Continue showing castbar during empowered hold phase even when API returns nil
        local isInEmpoweredHold = isPlayer and self.isEmpowered and self.startTime and self.endTime

        if spellName or channelName or isInEmpoweredHold then
            -- Real cast - use real cast data

            -- Handle timer-driven mode (non-player units with secret timing)
            if self.timerDriven and not isPlayer then
                -- Engine is driving the animation via SetTimerDuration
                -- Just update time text by reading remaining time

                local remaining = nil

                -- Method 1: Try duration object GetRemainingDuration first
                if self.durationObj then
                    local getter = self.durationObj.GetRemainingDuration or self.durationObj.GetRemaining
                    if getter then
                        local okRem, rem = pcall(getter, self.durationObj)
                        if okRem and rem ~= nil then
                            remaining = SafeToNumber(rem)
                        end
                    end
                end

                -- Method 2: Fall back to StatusBar extraction
                if remaining == nil and self.statusBar and self.statusBar.GetValue and self.statusBar.GetMinMaxValues then
                    local okV, value = pcall(self.statusBar.GetValue, self.statusBar)
                    local okMM, minV, maxV = pcall(self.statusBar.GetMinMaxValues, self.statusBar)

                    if okV and okMM then
                        value = SafeToNumber(value)
                        minV = SafeToNumber(minV) or 0
                        maxV = SafeToNumber(maxV)

                        if value and maxV and maxV > minV then
                            local span = maxV - minV

                            -- Detect countdown vs countup
                            -- If value is closer to max, bar is counting down
                            local assumeCountdown = self._assumeCountdown
                            if assumeCountdown == nil then
                                local distMin = math.abs(value - minV)
                                local distMax = math.abs(maxV - value)
                                assumeCountdown = (distMax < distMin)
                                self._assumeCountdown = assumeCountdown
                            end

                            if assumeCountdown then
                                remaining = value - minV
                            else
                                remaining = maxV - value
                            end

                            if remaining < 0 then remaining = 0 end
                            if remaining > span then remaining = span end
                        end
                    end
                end

                -- Update time text (throttled) - only if we have valid remaining
                if remaining ~= nil then
                    UpdateThrottledText(self, elapsed, self.timeText, remaining)
                end
                return
            end

            -- Normal mode: calculate progress from stored timing values
            local startTime, endTime
            if isPlayer then
                startTime = self.startTime
                endTime = self.endTime
            else
                -- Target/focus uses milliseconds, convert to seconds
                if not self.castStartTime or not self.castEndTime then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                    return
                end
                startTime = self.castStartTime / 1000
                endTime = self.castEndTime / 1000
            end

            if not startTime or not endTime then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end

            local now = GetTime()
            if now >= endTime then
                if isPlayer then
                    ClearEmpoweredState(self)
                end
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end

            local duration = endTime - startTime
            if duration <= 0 then duration = 0.001 end

            -- Never use reverse fill - drain effect achieved via progress calculation
            self.statusBar:SetReverseFill(false)

            local remaining = endTime - now
            local channelFillForward = castSettings and castSettings.channelFillForward
            local shouldDrain = self.isChanneled and not self.isEmpowered and not channelFillForward
            local progress = shouldDrain and remaining or (now - startTime)

            self.statusBar:SetMinMaxValues(0, duration)
            self.statusBar:SetValue(progress)

            -- Empowered cast handling (player only)
            if isPlayer and self.isEmpowered then
                UpdateEmpoweredFillColor(self, progress, duration)

                -- Update empowered level text
                if self.empoweredLevelText and self.showEmpoweredLevel then
                    local currentStage, maxStages, isEmpowered = QUI_Castbar:GetEmpoweredLevel()
                    if isEmpowered and currentStage then
                        self.textThrottle = (self.textThrottle or 0) + elapsed
                        if self.textThrottle >= 0.1 then
                            self.textThrottle = 0
                            self.empoweredLevelText:SetText(tostring(math.floor(currentStage)))
                            UpdateTimeTextColor(self, self.unit)
                        end
                    else
                        self.empoweredLevelText:SetText("")
                    end
                elseif self.empoweredLevelText then
                    self.empoweredLevelText:SetText("")
                end

                -- Update time text visibility if hiding on empowered
                local currentSettings = GetUnitSettings(self.unitKey)
                local currentCastSettings = currentSettings and currentSettings.castbar
                if currentCastSettings and currentCastSettings.hideTimeTextOnEmpowered then
                    if self.timeText then
                        self.timeText:Hide()
                    end
                end
            elseif isPlayer and self.empoweredLevelText then
                self.empoweredLevelText:SetText("")

                -- Show time text again if not empowered
                local currentSettings = GetUnitSettings(self.unitKey)
                local currentCastSettings = currentSettings and currentSettings.castbar
                if currentCastSettings and currentCastSettings.showTimeText and self.timeText then
                    self.timeText:Show()
                end
            end

            -- Update time text (throttle to 10 FPS) - only if not hiding on empowered
            if isPlayer and self.isEmpowered then
                local currentSettings = GetUnitSettings(self.unitKey)
                local currentCastSettings = currentSettings and currentSettings.castbar
                if not (currentCastSettings and currentCastSettings.hideTimeTextOnEmpowered) then
                    if UpdateThrottledText(self, elapsed, self.timeText, remaining) and remaining > 0 then
                        UpdateTimeTextColor(self, self.unit)
                    end
                end
            else
                if UpdateThrottledText(self, elapsed, self.timeText, remaining) and remaining > 0 and isPlayer then
                    UpdateTimeTextColor(self, self.unit)
                end
            end
        elseif self.isPreviewSimulation then
            -- Preview simulation - use preview data
            if not self.previewStartTime or not self.previewEndTime then
                return
            end
            
            local now = GetTime()
            if now >= self.previewEndTime then
                -- Loop preview animation
                self.previewStartTime = now
                self.previewEndTime = now + self.previewMaxValue
                self.previewValue = 0
            end
            
            self.previewValue = self.previewValue + elapsed
            local progress = math.min(self.previewValue, self.previewMaxValue)
            local remaining = self.previewMaxValue - progress
            
            self.statusBar:SetValue(progress)
            
            UpdateThrottledText(self, elapsed, self.timeText, remaining)
        else
            -- No cast and no preview - hide
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end

    -- Store OnUpdate handler reference
    castbar.castbarOnUpdate = CastBar_OnUpdate
    
    -- Unified Cast function
    function castbar:Cast(spellID, isEmpowerEvent)
        -- Get cast information (now includes durationObj and hasSecretTiming)
        local spellName, text, texture, startTimeMS, endTimeMS, notInterruptible, unitSpellID, isChanneled, channelStages, durationObj, hasSecretTiming = GetCastInfo(self, self.unit)

        -- Detect empowered cast (player only)
        local isEmpowered, numStages = DetectEmpoweredCast(isPlayer, spellID, unitSpellID, isEmpowerEvent, isChanneled, channelStages)

        -- If actually casting, show real cast
        -- For non-player units: can cast if we have spellName and durationObj (even with secret timing)
        -- For player: need actual timing values
        local canShowCast = false
        local useTimerDriven = false
        local startTime, endTime

        if spellName then
            if isPlayer then
                -- Player castbar: need actual timing values
                if startTimeMS and endTimeMS then
                    local success
                    success, startTime, endTime = pcall(function()
                        return startTimeMS / 1000, endTimeMS / 1000
                    end)
                    canShowCast = success
                end
            else
                -- Non-player (target/focus/boss): use engine-driven animation if timing is secret
                if hasSecretTiming and durationObj and self.statusBar and self.statusBar.SetTimerDuration then
                    -- Engine-driven mode: use SetTimerDuration
                    useTimerDriven = true
                    canShowCast = true
                elseif startTimeMS and endTimeMS then
                    -- Normal mode: timing values are accessible
                    local success
                    success, startTime, endTime = pcall(function()
                        return startTimeMS / 1000, endTimeMS / 1000
                    end)
                    canShowCast = success
                elseif durationObj and self.statusBar and self.statusBar.SetTimerDuration then
                    -- Fallback: timing not explicitly secret but also not accessible, try engine-driven
                    useTimerDriven = true
                    canShowCast = true
                end
            end
        end

        if canShowCast then
            -- Clear preview simulation if active
            if self.isPreviewSimulation then
                ClearPreviewSimulation(self)
            end

            -- Store cast state
            self.isChanneled = isChanneled
            self.isEmpowered = isEmpowered
            self.numStages = numStages or 0
            self.notInterruptible = notInterruptible
            self.timerDriven = useTimerDriven
            self.durationObj = durationObj
            self._assumeCountdown = nil  -- Reset countdown detection for new cast

            if useTimerDriven then
                -- Engine-driven animation for non-player units with secret timing
                -- Use SetTimerDuration to let the engine animate the bar
                if self.statusBar and self.statusBar.SetTimerDuration then
                    -- Determine direction: 0=fill (casts), 1=drain (channels that should drain)
                    local channelFillForward = castSettings and castSettings.channelFillForward
                    local direction = (isChanneled and not channelFillForward) and 1 or 0
                    local ok = pcall(self.statusBar.SetTimerDuration, self.statusBar, durationObj, 0, direction)
                    if not ok then
                        -- Fallback: try without direction parameter
                        pcall(self.statusBar.SetTimerDuration, self.statusBar, durationObj)
                    end
                end
                -- Don't store timing values - we'll read progress from the StatusBar
                self.castStartTime = nil
                self.castEndTime = nil
            else
                -- Normal mode: store timing values for OnUpdate calculation
                -- Adjust end time for empowered hold time
                endTime = AdjustEmpoweredEndTime(self, isPlayer, isEmpowered, endTime)
                StoreCastTimes(self, isPlayer, startTimeMS, endTimeMS, startTime, endTime)
            end

            -- Set icon texture IMMEDIATELY
            if SetIconTexture(self, texture) then
                if ShouldShowIcon(self, castSettings) then
                    self.icon:Show()
                else
                    self.icon:Hide()
                end
            end

            -- Update visual elements (pass nil for startTime/endTime if timer-driven)
            UpdateCastbarVisuals(self, castSettings, self.unitKey, texture, text, spellName, self.unit, isChanneled, notInterruptible, startTime, endTime)

            -- Store showEmpoweredLevel setting for OnUpdate
            if isPlayer then
                self.showEmpoweredLevel = castSettings.showEmpoweredLevel
            end

            -- Update empowered state
            UpdateEmpoweredState(self, isPlayer, isEmpowered, numStages)

            -- Start OnUpdate handler and show
            self:SetScript("OnUpdate", CastBar_OnUpdate)
            self:Show()
        else
            -- No real cast - handle preview mode
            HandleNoCast(self, castSettings, isPlayer, CastBar_OnUpdate)
        end
    end
    
    -- Event dispatch table (cleaner than if-elseif chain)
    local eventHandlers = {
        -- Target/focus change events
        PLAYER_TARGET_CHANGED = function(self) self:Cast() end,
        PLAYER_FOCUS_CHANGED = function(self) self:Cast() end,
        UNIT_TARGET = function(self) self:Cast() end,
        
        -- Cast start events
        UNIT_SPELLCAST_START = function(self, spellID) self:Cast(spellID, false) end,
        UNIT_SPELLCAST_CHANNEL_START = function(self, spellID) self:Cast(spellID, false) end,
        
        -- Cast end events - hide immediately without re-querying APIs
        UNIT_SPELLCAST_STOP = function(self, spellID)
            if isPlayer then ClearEmpoweredState(self) end
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end,
        UNIT_SPELLCAST_CHANNEL_STOP = function(self, spellID)
            if isPlayer then ClearEmpoweredState(self) end
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end,
        UNIT_SPELLCAST_FAILED = function(self, spellID)
            -- Don't hide if a channel is still active (e.g., pressing spell key again during channel)
            if UnitChannelInfo(self.unit) or UnitCastingInfo(self.unit) then
                return
            end
            if isPlayer then ClearEmpoweredState(self) end
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end,
        UNIT_SPELLCAST_INTERRUPTED = function(self, spellID)
            if isPlayer then ClearEmpoweredState(self) end
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end,
        
        -- Interruptible state changes
        UNIT_SPELLCAST_INTERRUPTIBLE = function(self)
            self.notInterruptible = false
            ApplyCastColor(self.statusBar, false, self.customColor)
        end,
        UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(self)
            self.notInterruptible = true
            ApplyCastColor(self.statusBar, true, self.customColor)
        end,
    }
    
    -- Player-only empowered cast handlers
    if isPlayer then
        eventHandlers.UNIT_SPELLCAST_EMPOWER_START = function(self, spellID)
            self:Cast(spellID, true)
        end
        eventHandlers.UNIT_SPELLCAST_EMPOWER_UPDATE = function(self, spellID)
            self:Cast(spellID, true)
        end
        eventHandlers.UNIT_SPELLCAST_EMPOWER_STOP = function(self, spellID)
            local name = UnitCastingInfo(self.unit)
            if name then
                -- Another cast started, transition to it
                ClearEmpoweredState(self)
                self:Cast(spellID, false)
            else
                -- Cast ended (cancelled, interrupted, or completed) - hide immediately
                ClearEmpoweredState(self)
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end
    end
    
    -- Register common events
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)
    
    -- Player-specific events (empowered casts)
    if isPlayer then
        castbar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", unit)
        castbar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", unit)
        castbar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", unit)
    end
    
    -- Target/focus-specific events
    if unit == "target" then
        castbar:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unit == "focus" then
        castbar:RegisterEvent("PLAYER_FOCUS_CHANGED")
    elseif unit == "targettarget" then
        castbar:RegisterEvent("PLAYER_TARGET_CHANGED")
        castbar:RegisterUnitEvent("UNIT_TARGET", "target")
    end
    
    -- Unified event handler using dispatch table
    castbar:SetScript("OnEvent", function(self, event, eventUnit, castGUID, spellID)
        local handler = eventHandlers[event]
        if handler then
            handler(self, spellID)
        end
    end)
end

-- Legacy function names for backwards compatibility (now just call unified setup)
function QUI_Castbar:SetupTargetFocusCastbar(castbar, unit, unitKey, castSettings)
    self:SetupCastbar(castbar, unit, unitKey, castSettings)
end

function QUI_Castbar:SetupPlayerCastbar(castbar, unit, unitKey, castSettings)
    self:SetupCastbar(castbar, unit, unitKey, castSettings)
end

---------------------------------------------------------------------------
-- BOSS CASTBAR SETUP
---------------------------------------------------------------------------
function QUI_Castbar:SetupBossCastbar(castbar, unit, bossIndex, castSettings)
    -- Unified OnUpdate handler - handles both real casts and preview
    local function CastBar_OnUpdate(self, elapsed)
        -- Check if actually casting (real cast takes priority)
        local spellName = UnitCastingInfo(self.unit)
        local channelName = UnitChannelInfo(self.unit)
        
        if spellName or channelName then
            -- Real cast - use real cast data
            if not self.startTime or not self.endTime then return end
            
            local now = GetTime()
            if now >= self.endTime then
                ClearEmpoweredState(self)
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end
            
            local duration = self.endTime - self.startTime
            if duration <= 0 then duration = 0.001 end
            
            -- Never use reverse fill - drain effect achieved via progress calculation
            self.statusBar:SetReverseFill(false)

            local remaining = self.endTime - now
            local channelFillForward = castSettings and castSettings.channelFillForward
            local shouldDrain = self.isChanneled and not self.isEmpowered and not channelFillForward
            local progress = shouldDrain and remaining or (now - self.startTime)

            self.statusBar:SetMinMaxValues(0, duration)
            self.statusBar:SetValue(progress)

            if self.isEmpowered then
                UpdateEmpoweredFillColor(self, progress, duration)
            end
            
            if UpdateThrottledText(self, elapsed, self.timeText, remaining) and remaining > 0 then
                UpdateTimeTextColor(self, self.unit)
            end
        elseif self.isPreviewSimulation then
            -- Preview simulation - use preview data
            if not self.previewStartTime or not self.previewEndTime then
                return
            end
            
            local now = GetTime()
            if now >= self.previewEndTime then
                -- Loop preview animation
                self.previewStartTime = now
                self.previewEndTime = now + self.previewMaxValue
                self.previewValue = 0
            end
            
            self.previewValue = self.previewValue + elapsed
            local progress = math.min(self.previewValue, self.previewMaxValue)
            local remaining = self.previewMaxValue - progress
            
            self.statusBar:SetValue(progress)
            
            UpdateThrottledText(self, elapsed, self.timeText, remaining)
        else
            -- No cast and no preview - hide
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end
    
    -- Store OnUpdate handler reference
    castbar.playerOnUpdate = CastBar_OnUpdate
    
    -- Cast function for player
    function castbar:Cast(spellID, isEmpowerEvent)
        -- Check if actually casting
        local spellName, text, texture, startTimeMS, endTimeMS, _, _, notInterruptible, unitSpellID = UnitCastingInfo(self.unit)
        local isChanneled = false
        local isEmpowered = isEmpowerEvent or false
        local numStages = 0
        
        if not spellName then
            local channelName, _, channelTex, channelStart, channelEnd, _, channelNotInt, _, _, channelStages = UnitChannelInfo(self.unit)
            if channelName then
                spellName = channelName
                texture = channelTex
                startTimeMS = channelStart
                endTimeMS = channelEnd
                notInterruptible = channelNotInt
                isChanneled = true
                if isEmpowerEvent and channelStages and channelStages > 0 then
                    numStages = channelStages
                end
            end
        end
        
        local checkSpellID = spellID or unitSpellID
        if checkSpellID and C_Spell and C_Spell.GetSpellEmpowerInfo then
            local empowerInfo = C_Spell.GetSpellEmpowerInfo(checkSpellID)
            if empowerInfo and empowerInfo.numStages and empowerInfo.numStages > 0 then
                isEmpowered = true
                numStages = empowerInfo.numStages
            end
        end
        
        if spellName and startTimeMS and endTimeMS then
            -- Use pcall to handle Midnight secret values (pass type checks but fail arithmetic)
            local success, startTime, endTime = pcall(function()
                return startTimeMS / 1000, endTimeMS / 1000
            end)
            if not success then return end

            if isEmpowered and GetUnitEmpowerHoldAtMaxTime then
                local ok, adjustedEndTime = pcall(function()
                    local ht = GetUnitEmpowerHoldAtMaxTime(self.unit)
                    if ht and ht > 0 then
                        return endTime + (ht / 1000)
                    end
                    return endTime
                end)
                if ok and adjustedEndTime then
                    endTime = adjustedEndTime
                end
            end
            
            local now = GetTime()
            self.startTime = startTime
            self.endTime = endTime
            self.isChanneled = isChanneled
            self.isEmpowered = isEmpowered
            self.numStages = numStages or 0
            self.notInterruptible = notInterruptible
            
            -- Ensure status bar has texture
            local currentSettings = GetUnitSettings(self.unitKey)
            local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
            if self.statusBar then
                self.statusBar:SetStatusBarTexture(GetTexturePath(currentCastSettings.texture))
            end
            
            -- Set icon texture and show it
            if SetIconTexture(self, texture) then
                -- Only show icon if showIcon is enabled
                local currentSettings = GetUnitSettings(self.unitKey)
                local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
                if ShouldShowIcon(self, currentCastSettings) then
                    self.icon:Show()
                else
                    self.icon:Hide()
                end
            end
            
            UpdateSpellText(self, text, spellName, castSettings, self.unit)

            self.statusBar:SetReverseFill(false)

            ApplyCastColor(self.statusBar, notInterruptible, self.customColor)

            if isEmpowered and numStages and numStages > 0 then
                UpdateEmpoweredStages(self, numStages)
            else
                ClearEmpoweredState(self)
            end
            
            -- Clear preview simulation if active
            if self.isPreviewSimulation then
                ClearPreviewSimulation(self)
            end
            
            -- Start OnUpdate handler
            self:SetScript("OnUpdate", CastBar_OnUpdate)
            self:Show()
        else
            -- No real cast - check if preview mode is enabled AND boss frame preview is active
            C_Timer.After(0.1, function()
                if not UnitCastingInfo(self.unit) and not UnitChannelInfo(self.unit) then
                    ClearEmpoweredState(self)
                    local settings = GetUnitSettings(self.unitKey)
                    local QUI_UF = QUI_Castbar.unitFramesModule
                    local bossFramePreviewActive = QUI_UF and QUI_UF.previewMode and QUI_UF.previewMode["boss" .. bossIndex]
                    if settings and settings.castbar and settings.castbar.previewMode and bossFramePreviewActive then
                        -- Show preview simulation
                        SimulateCast(self, castSettings, self.unitKey, bossIndex)
                        self:SetScript("OnUpdate", CastBar_OnUpdate)
                    else
                        -- No preview mode or boss frame not in preview - hide
                        if self.isPreviewSimulation then
                            ClearPreviewSimulation(self)
                        end
                        self:SetScript("OnUpdate", nil)
                        self:Hide()
                    end
                end
            end)
        end
    end

    -- Register events
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", unit)
    castbar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", unit)
    
    castbar:SetScript("OnEvent", function(self, event, eventUnit, castGUID, spellID)
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            self:Cast(spellID, false)
        elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
            self:Cast(spellID, true)
        elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
            self:Cast(spellID, true)
        elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            local name = UnitCastingInfo(self.unit)
            if name then
                -- Another cast started, transition to it
                ClearEmpoweredState(self)
                self:Cast(spellID, false)
            else
                -- Cast ended (cancelled, interrupted, or completed) - hide immediately
                ClearEmpoweredState(self)
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            ClearEmpoweredState(self)
            self:Cast(spellID, false)
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            self.notInterruptible = false
            ApplyCastColor(self.statusBar, false, self.customColor)
        elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            self.notInterruptible = true
            ApplyCastColor(self.statusBar, true, self.customColor)
        end
    end)
end

---------------------------------------------------------------------------
-- CREATE: Boss Castbar
---------------------------------------------------------------------------
function QUI_Castbar:CreateBossCastbar(unitFrame, unit, bossIndex)
    local settings = GetUnitSettings("boss")
    if not settings or not settings.castbar or not settings.castbar.enabled then
        return nil
    end
    
    local castSettings = settings.castbar
    InitializeDefaultSettings(castSettings)
    
    local frameWidth = unitFrame:GetWidth()
    local castWidth = Scale((castSettings.width and castSettings.width > 0) and castSettings.width or frameWidth)
    local barHeight, iconSize, iconScale = GetSizingValues(castSettings)
    local borderSize = Scale(castSettings.borderSize or 1)
    local iconBorderSize = Scale(castSettings.iconBorderSize or 1)
    local fontSize = castSettings.fontSize or 12
    
    -- Create anchor frame (outer frame for positioning/sizing)
    local anchorFrame = CreateAnchorFrame("QUI_Boss" .. bossIndex .. "_Castbar", UIParent)
    anchorFrame:SetSize(castWidth, barHeight)
    
    -- Anchor to boss unit frame
    local offsetX = Scale(castSettings.offsetX or 0)
    local offsetY = Scale(castSettings.offsetY or -25)
    anchorFrame:SetPoint("TOP", unitFrame, "BOTTOM", offsetX, offsetY)
    
    -- Create UI elements (icon with integrated border) - parented to anchorFrame
    CreateIcon(anchorFrame, iconSize, iconBorderSize, castSettings.iconBorderColor)
    local statusBar = CreateStatusBar(anchorFrame)
    
    -- Create border for status bar (parented to statusBar)
    CreateStatusBarBorder(statusBar, borderSize, castSettings.borderColor)
    
    local bgBar = CreateBackgroundBar(statusBar)
    anchorFrame.bgBar = bgBar
    
    local spellText = CreateTextElement(statusBar, fontSize)
    spellText:SetPoint("LEFT", statusBar, "LEFT", Scale(4), 0)
    spellText:SetJustifyH("LEFT")
    anchorFrame.spellText = spellText
    
    local timeText = CreateTextElement(statusBar, fontSize)
    timeText:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")
    anchorFrame.timeText = timeText
    
    -- Set up UpdateCastbarElements function
    anchorFrame.UpdateCastbarElements = function(self)
        UpdateCastbarElements(self, "boss", castSettings)
    end
    
    -- Apply colors and textures
    local barColor = castSettings.color or {1, 0.7, 0, 1}
    anchorFrame.customColor = barColor
    ApplyBarColor(statusBar, barColor)
    ApplyBackgroundColor(bgBar, castSettings.bgColor)
    statusBar:SetStatusBarTexture(GetTexturePath(castSettings.texture))

    -- Update element positions
    UpdateCastbarElements(anchorFrame, "boss", castSettings)

    -- Store unit info
    anchorFrame.unit = unit
    anchorFrame.unitKey = "boss"
    anchorFrame.bossIndex = bossIndex
    anchorFrame.isChanneled = false
    
    -- Unified OnUpdate handler - handles both real casts and preview
    local function BossCastBar_OnUpdate(self, elapsed)
        -- Check if actually casting (real cast takes priority)
        local spellName = UnitCastingInfo(self.unit)
        local channelName = UnitChannelInfo(self.unit)
        
        if spellName or channelName then
            -- Real cast - use real cast data
            if not self.startTime or not self.endTime then return end
            
            local ufdb = GetDB()
            local uncapped = ufdb and ufdb.general and ufdb.general.smootherAnimation
            
            if not uncapped then
                self.updateElapsed = (self.updateElapsed or 0) + elapsed
                if self.updateElapsed < 0.0167 then return end
                self.updateElapsed = 0
            end
            
            local now = GetTime()
            if now >= self.endTime then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end
            
            local duration = self.endTime - self.startTime
            if duration <= 0 then return end
            
            -- Never use reverse fill - drain effect achieved via progress calculation
            self.statusBar:SetReverseFill(false)

            local channelFillForward = castSettings and castSettings.channelFillForward
            local shouldDrain = self.isChanneled and not self.isEmpowered and not channelFillForward
            local progress
            if shouldDrain then
                progress = (self.endTime - now) / duration
            else
                progress = (now - self.startTime) / duration
            end

            self.statusBar:SetMinMaxValues(0, 1)
            self.statusBar:SetValue(math.max(0, math.min(1, progress)))

            local remaining = self.endTime - now
            if self.timeText then
                self.timeText:SetText(string.format("%.1f", remaining))
                UpdateTimeTextColor(self, self.unit)
            end
        elseif self.isPreviewSimulation then
            -- Preview simulation - use preview data
            if not self.previewStartTime or not self.previewEndTime then
                return
            end
            
            local now = GetTime()
            if now >= self.previewEndTime then
                -- Loop preview animation
                self.previewStartTime = now
                self.previewEndTime = now + self.previewMaxValue
                self.previewValue = 0
            end
            
            self.previewValue = self.previewValue + elapsed
            local progress = math.min(self.previewValue, self.previewMaxValue)
            local remaining = self.previewMaxValue - progress
            
            self.statusBar:SetValue(progress)
            
            UpdateThrottledText(self, elapsed, self.timeText, remaining)
        else
            -- No cast and no preview - hide
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end
    
    -- Store OnUpdate handler reference
    anchorFrame.bossOnUpdate = BossCastBar_OnUpdate
    
    -- Cast function
    function anchorFrame:Cast()
        -- Check if actually casting
        local spellName, text, texture, startTimeMS, endTimeMS, _, _, notInterruptible = UnitCastingInfo(self.unit)
        local isChanneled = false
        
        if not spellName then
            spellName, text, texture, startTimeMS, endTimeMS, _, notInterruptible = UnitChannelInfo(self.unit)
            if spellName then
                isChanneled = true
            end
        end

        -- If actually casting, show real cast (preview is hidden during real casts)
        if spellName and startTimeMS and endTimeMS then
            -- Use pcall to handle Midnight secret values (pass type checks but fail arithmetic)
            local success, startTime, endTime = pcall(function()
                return startTimeMS / 1000, endTimeMS / 1000
            end)
            if not success then return end

            -- Clear preview simulation
            if self.isPreviewSimulation then
                ClearPreviewSimulation(self)
            end

            local now = GetTime()
            self.startTime = startTime
            self.endTime = endTime
            self.isChanneled = isChanneled
            self.notInterruptible = notInterruptible

            if self.startTime < now - 5 then
                local dur = self.endTime - self.startTime
                if dur and dur > 0 then
                    self.startTime = now
                    self.endTime = now + dur
                end
            end
            
            -- Ensure status bar has texture
            local currentSettings = GetUnitSettings(self.unitKey)
            local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
            if self.statusBar then
                self.statusBar:SetStatusBarTexture(GetTexturePath(currentCastSettings.texture))
            end
            
            -- Set icon texture and show it
            if SetIconTexture(self, texture) then
                -- Only show icon if showIcon is enabled
                local currentSettings = GetUnitSettings(self.unitKey)
                local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
                if ShouldShowIcon(self, currentCastSettings) then
                    self.icon:Show()
                else
                    self.icon:Hide()
                end
            end
            
            UpdateSpellText(self, text, spellName, castSettings, self.unit)

            self.statusBar:SetReverseFill(false)

            ApplyCastColor(self.statusBar, notInterruptible, self.customColor)

            -- Start OnUpdate handler
            self:SetScript("OnUpdate", BossCastBar_OnUpdate)
            self:Show()
        else
            -- No real cast - check if preview mode is enabled AND boss frame preview is active
            C_Timer.After(0.1, function()
                if not UnitCastingInfo(self.unit) and not UnitChannelInfo(self.unit) then
                    local settings = GetUnitSettings(self.unitKey)
                    local QUI_UF = QUI_Castbar.unitFramesModule
                    local bossFramePreviewActive = QUI_UF and QUI_UF.previewMode and QUI_UF.previewMode["boss" .. self.bossIndex]
                    if settings and settings.castbar and settings.castbar.previewMode and bossFramePreviewActive then
                        -- Show preview simulation
                        SimulateCast(self, castSettings, "boss", self.bossIndex)
                        self:SetScript("OnUpdate", BossCastBar_OnUpdate)
                    else
                        -- No preview mode or boss frame not in preview - hide
                        if self.isPreviewSimulation then
                            ClearPreviewSimulation(self)
                        end
                        self:SetScript("OnUpdate", nil)
                        self:Hide()
                    end
                end
            end)
        end
    end
    
    -- Register events
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)
    anchorFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
    
    anchorFrame:SetScript("OnEvent", function(self, event, eventUnit)
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            self:Cast()
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" 
            or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
            or event == "UNIT_SPELLCAST_SUCCEEDED" then
            self:Cast()
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            self.notInterruptible = false
            ApplyCastColor(self.statusBar, false, self.customColor)
        elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            self.notInterruptible = true
            ApplyCastColor(self.statusBar, true, self.customColor)
        end
    end)

    -- Apply preview if enabled AND boss frame preview is active
    local QUI_UF = QUI_Castbar.unitFramesModule
    local bossFramePreviewActive = QUI_UF and QUI_UF.previewMode and QUI_UF.previewMode["boss" .. bossIndex]
    if castSettings.previewMode and bossFramePreviewActive then
        SimulateCast(anchorFrame, castSettings, "boss", bossIndex)
        -- Start OnUpdate handler for preview
        if anchorFrame.bossOnUpdate then
            anchorFrame:SetScript("OnUpdate", anchorFrame.bossOnUpdate)
        end
    end

    return anchorFrame
end

---------------------------------------------------------------------------
-- GLOBAL FUNCTIONS
---------------------------------------------------------------------------
QUI_Castbar.unitFramesModule = nil

function QUI_Castbar:SetUnitFramesModule(ufModule)
    self.unitFramesModule = ufModule
    if ufModule and ufModule.castbars then
        self.castbars = ufModule.castbars
    end
end

_G.QUI_ShowCastbarPreview = function(unitKey)
    local settings = GetUnitSettings(unitKey)
    if not settings or not settings.castbar then
        return
    end
    
    settings.castbar.previewMode = true
    
    -- Refresh the frame to apply preview
    local QUI_UF = QUI_Castbar.unitFramesModule
    if QUI_UF then
        QUI_UF:RefreshFrame(unitKey)
    end
end

_G.QUI_HideCastbarPreview = function(unitKey)
    local settings = GetUnitSettings(unitKey)
    if not settings or not settings.castbar then
        return
    end
    
    settings.castbar.previewMode = false
    
    -- Refresh the frame to clear preview
    local QUI_UF = QUI_Castbar.unitFramesModule
    if QUI_UF then
        QUI_UF:RefreshFrame(unitKey)
    end
end

---------------------------------------------------------------------------
-- DESTROY: Clean up a castbar
---------------------------------------------------------------------------
local function DestroyCastbar(castbar)
    if not castbar then return end
    
    castbar:SetScript("OnUpdate", nil)
    castbar:SetScript("OnEvent", nil)
    castbar:SetScript("OnDragStart", nil)
    castbar:SetScript("OnDragStop", nil)
    
    castbar:Hide()
    castbar:ClearAllPoints()
end

---------------------------------------------------------------------------
-- REFRESH: Update castbar in place (preserves active casts)
---------------------------------------------------------------------------
function QUI_Castbar:RefreshCastbar(castbar, unitKey, castSettings, unitFrame)
    if not castSettings or not unitFrame then return end
    
    -- Simple: always recreate the castbar when settings change
    local unit = (castbar and castbar.unit) or unitKey
    if castbar then
        DestroyCastbar(castbar)
    end
    
    local newCastbar = self:CreateCastbar(unitFrame, unit, unitKey)
    if newCastbar then
        local QUI_UF = self.unitFramesModule
        if QUI_UF and QUI_UF.castbars then
            QUI_UF.castbars[unitKey] = newCastbar
        end
    end
end

function QUI_Castbar:RefreshBossCastbar(castbar, bossKey, castSettings, unitFrame)
    if not castSettings or not unitFrame then return end
    
    local bossIndex = (castbar and castbar.bossIndex) or (bossKey and tonumber(bossKey:match("boss(%d+)")))
    if not bossIndex then return end
    
    -- Simple: always recreate the castbar when settings change
    local unit = (castbar and castbar.unit) or ("boss" .. bossIndex)
    if castbar then
        DestroyCastbar(castbar)
    end
    
    local newCastbar = self:CreateBossCastbar(unitFrame, unit, bossIndex)
    if newCastbar then
        local QUI_UF = self.unitFramesModule
        if QUI_UF and QUI_UF.castbars then
            QUI_UF.castbars[bossKey] = newCastbar
        end
    end
end

_G.QUI_RefreshCastbar = function(unitKey)
    local QUI_UF = QUI_Castbar.unitFramesModule
    if not QUI_UF then return end
    QUI_UF:RefreshFrame(unitKey)
end

-- Refresh all castbars (used by HUD Layering options)
_G.QUI_RefreshCastbars = function()
    local QUI_UF = QUI_Castbar.unitFramesModule
    if not QUI_UF then return end
    -- Refresh player and target castbars
    for _, unitKey in ipairs({"player", "target"}) do
        QUI_UF:RefreshFrame(unitKey)
    end
end

_G.QUI_Castbars = QUI_Castbar.castbars
