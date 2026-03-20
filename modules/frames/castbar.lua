--[[
    QUI Castbar Module
    Extracted from qui_unitframes.lua for better organization
    Handles castbar creation and management for player, target, focus, and boss units
]]

local ADDON_NAME, ns = ...
local QUICore = ns.Addon
local LSM = ns.LSM
local nsHelpers = ns.Helpers
local UIKit = ns.UIKit
local IsSecretValue = nsHelpers.IsSecretValue
local SafeValue = nsHelpers.SafeValue
local EnsureDefaults = nsHelpers.EnsureDefaults

local GetCore = nsHelpers.GetCore

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local pcall = pcall
local GetTime = GetTime
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

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

local GetFontPath = nsHelpers.GetGeneralFont

local GetFontOutline = nsHelpers.GetGeneralFontOutline

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
    if IsSecretValue(v) then
        return nil
    end
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

local CHANNEL_TICK_DEFAULT_COLOR = {1, 1, 1, 0.9}
local CHANNEL_TICK_SOURCE_POLICY_AUTO = "auto"
local CHANNEL_TICK_SOURCE_POLICY_STATIC = "static"
local CHANNEL_TICK_SOURCE_POLICY_RUNTIME_ONLY = "runtimeOnly"
local GCD_SPELL_ID = 61304
local GCD_MELEE_POWER_TYPES = {
    [1] = true,   -- Rage
    [2] = true,   -- Focus
    [3] = true,   -- Energy
    [4] = true,   -- ComboPoints
    [5] = true,   -- Runes
    [6] = true,   -- RunicPower
    [9] = true,   -- HolyPower
    [12] = true,  -- Chi
    [17] = true,  -- Fury
    [18] = true,  -- Pain
}
local CHANNEL_TICK_SPELL_ALIASES = {
    [468720] = 473728, -- Void Ray wrapper -> periodic channel spell
}

-- Deterministic tick profiles for high-confidence channels.
-- These are intended to be robust on first cast and can still be
-- superseded by runtime calibration when users opt in to runtime-only mode.
local CHANNEL_TICK_RULE_DB = {
    [740] = { baseTicks = 4 },       -- Tranquility
    [5143] = { baseTicks = 4 },      -- Arcane Missiles
    [15407] = { baseTicks = 6 },     -- Mind Flay
    [64843] = { baseTicks = 4 },     -- Divine Hymn
    [120360] = { baseTicks = 15 },   -- Barrage
    [198013] = { baseTicks = 10 },   -- Eye Beam
    [205021] = { baseTicks = 5 },    -- Ray of Frost
    [206931] = { baseTicks = 3 },    -- Blooddrinker
    [212084] = { baseTicks = 10 },   -- Fel Devastation
    [234153] = { baseTicks = 5 },    -- Drain Life
    [356995] = { baseTicks = 5 },    -- Disintegrate
}

-- Interval-based fallback for channels without a curated profile.
local CHANNEL_TICK_STATIC_DB = {
    [115175] = { interval = 1.0 },   -- Soothing Mist
    [473728] = { interval = 0.15 },  -- Void Ray
}

local CHANNEL_TICK_RUNTIME_CACHE = {}
local CHANNEL_TICK_ACTIVE_BY_GUID = {}
local CHANNEL_TICK_EVENT_FRAME = CreateFrame("Frame")
local CHANNEL_TICK_EVENT_REGISTERED = false

local CHANNEL_TICK_SUBEVENTS = {
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_PERIODIC_HEAL = true,
    SPELL_PERIODIC_MISSED = true,
    SPELL_PERIODIC_ENERGIZE = true,
    SPELL_PERIODIC_DRAIN = true,
    SPELL_PERIODIC_LEECH = true,
}

local function NormalizeChannelTickSpellID(spellID)
    if not spellID then return nil end
    if IsSecretValue(spellID) then
        return nil
    end
    local safeSpellID = SafeToNumber(spellID)
    if not safeSpellID then
        return nil
    end
    return CHANNEL_TICK_SPELL_ALIASES[safeSpellID] or safeSpellID
end

local function NormalizeChannelTickGUID(guid)
    if not guid then return nil end
    if IsSecretValue(guid) then
        return nil
    end
    if type(guid) ~= "string" or guid == "" then
        return nil
    end
    return guid
end

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

local function InitializeDefaultSettings(castSettings, unitKey)
    EnsureDefaults(castSettings, {
        iconAnchor = "LEFT",
        iconSpacing = 0,
        showIcon = true,
    })
    if unitKey == "player" and castSettings.showGCD == nil then castSettings.showGCD = false end
    if unitKey == "player" and castSettings.showGCDReverse == nil then castSettings.showGCDReverse = false end
    if unitKey == "player" and castSettings.showGCDMelee == nil then
        castSettings.showGCDMelee = castSettings.showGCDMeleeOnly == true
    end
    if unitKey == "player" and castSettings.gcdColor == nil then
        local baseColor = castSettings.color or DEFAULT_BAR_COLOR
        castSettings.gcdColor = {
            baseColor[1] or DEFAULT_BAR_COLOR[1],
            baseColor[2] or DEFAULT_BAR_COLOR[2],
            baseColor[3] or DEFAULT_BAR_COLOR[3],
            baseColor[4] or DEFAULT_BAR_COLOR[4],
        }
    end
    
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
    EnsureDefaults(castSettings, {
        iconBorderSize = 2,
        statusBarAnchor = "BOTTOMRIGHT",
    })

    EnsureDefaults(castSettings, {
        spellTextAnchor = "LEFT",
        spellTextOffsetX = 4,
        spellTextOffsetY = 0,
        showSpellText = true,
    })

    EnsureDefaults(castSettings, {
        timeTextAnchor = "RIGHT",
        timeTextOffsetX = -4,
        timeTextOffsetY = 0,
        showTimeText = true,
        notInterruptibleColor = {0.7, 0.2, 0.2, 1},
    })

    -- Empowered cast settings
    EnsureDefaults(castSettings, {
        empoweredLevelTextAnchor = "CENTER",
        empoweredLevelTextOffsetX = 0,
        empoweredLevelTextOffsetY = 0,
        showEmpoweredLevel = false,
        hideTimeTextOnEmpowered = false,
    })

    local defaultShowChannelTicks = (unitKey == "player")
    if castSettings.showChannelTicks == nil then castSettings.showChannelTicks = defaultShowChannelTicks end
    if castSettings.channelTickThickness == nil then castSettings.channelTickThickness = 1 end
    if castSettings.channelTickColor == nil then
        castSettings.channelTickColor = {
            CHANNEL_TICK_DEFAULT_COLOR[1],
            CHANNEL_TICK_DEFAULT_COLOR[2],
            CHANNEL_TICK_DEFAULT_COLOR[3],
            CHANNEL_TICK_DEFAULT_COLOR[4]
        }
    end
    if castSettings.channelTickMinConfidence == nil then castSettings.channelTickMinConfidence = 0.7 end
    if castSettings.channelTickSourcePolicy == nil then
        castSettings.channelTickSourcePolicy = CHANNEL_TICK_SOURCE_POLICY_AUTO
    end

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

local function GetSizingValues(castSettings, frame)
    local barHeight = QUICore:PixelRound(castSettings.height or 25, frame)
    barHeight = math.max(barHeight, QUICore:Pixels(4, frame))
    local iconSize = QUICore:PixelRound((castSettings.iconSize and castSettings.iconSize > 0) and castSettings.iconSize or 25, frame)
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
-- UI ELEMENT CREATION
---------------------------------------------------------------------------
local function CreateAnchorFrame(name, parent)
    local anchorFrame = CreateFrame("Frame", name, parent)
    anchorFrame:SetFrameStrata("MEDIUM")
    anchorFrame:SetFrameLevel(200)
    anchorFrame:Hide()
    return anchorFrame
end

local function ShouldUseProtectedVisibilityFallback(frame)
    return frame and frame._quiUseAlphaVisibility == true
end

local function SetCastbarFrameVisible(frame, shouldShow)
    if not frame then return end
    frame._quiDesiredVisible = shouldShow == true

    -- TAINT SAFETY: Show()/Hide() are protected and get ADDON_ACTION_BLOCKED
    -- when called from addon code during a secure execution context (e.g.,
    -- TargetNearestEnemy → PLAYER_TARGET_CHANGED → Cast → here).
    -- In combat, use alpha-only visibility to avoid taint.
    local inCombat = InCombatLockdown()

    if shouldShow then
        frame:SetAlpha(1)
        if not frame:IsShown() and not inCombat then
            frame:Show()
        end
        return
    end

    if inCombat or ShouldUseProtectedVisibilityFallback(frame) then
        -- Keep frame shown and hide via alpha to avoid blocked Hide() in combat.
        if not frame:IsShown() and not inCombat then
            frame:Show()
        end
        frame:SetAlpha(0)
        return
    end

    frame:SetAlpha(1)
    frame:Hide()
end

local function CreateStatusBar(anchorFrame)
    local statusBar = CreateFrame("StatusBar", nil, anchorFrame)
    statusBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    anchorFrame.statusBar = statusBar
    return statusBar
end


local function GetBarColor(unitKey, castSettings)
    if unitKey == "player" and castSettings.useClassColor then
        local _, class = UnitClass("player")
        if not IsSecretValue(class) and class and RAID_CLASS_COLORS[class] then
            local c = RAID_CLASS_COLORS[class]
            return {c.r, c.g, c.b, 1}
        end
    end
    return castSettings.color or DEFAULT_BAR_COLOR
end

local function GetNotInterruptibleColor(castSettings)
    return castSettings.notInterruptibleColor or NOT_INTERRUPTIBLE_COLOR
end

local function ApplyBarColor(statusBar, barColor)
    local r, g, b, a = GetSafeColor(barColor, DEFAULT_BAR_COLOR)
    statusBar:SetStatusBarColor(r, g, b, a)
end

local function ApplyBackgroundColor(bgBar, bgColor)
    local r, g, b, a = GetSafeColor(bgColor, DEFAULT_BG_COLOR)
    bgBar:SetVertexColor(r, g, b, a)
end

-- Create helper textures used for secret-safe interruptibility rendering:
-- 1) hidden alpha helper receives SetAlphaFromBoolean result
-- 2) visible overlay tints the filled cast texture for non-interruptible casts
local function GetInterruptibilityColorObjects(statusBar)
    if not statusBar then
        return nil, nil
    end

    if not statusBar.interruptibilityColorHelper then
        local helper = statusBar:CreateTexture(nil, "BACKGROUND")
        helper:SetSize(1, 1)
        helper:SetColorTexture(0, 0, 0, 0)
        helper:SetAlpha(0)
        helper:Hide()
        statusBar.interruptibilityColorHelper = helper
    end

    if not statusBar.notInterruptibleOverlay then
        local overlay = statusBar:CreateTexture(nil, "OVERLAY")
        overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
        overlay:SetAlpha(0)
        overlay:Hide()
        statusBar.notInterruptibleOverlay = overlay
    end

    return statusBar.interruptibilityColorHelper, statusBar.notInterruptibleOverlay
end

local function ApplyCastColor(statusBar, notInterruptible, customColor, notInterruptibleColor)
    if not statusBar then
        return
    end

    -- Always apply the normal cast color directly to the StatusBar.
    local normalR, normalG, normalB, normalA = GetSafeColor(customColor, DEFAULT_BAR_COLOR)
    statusBar:SetStatusBarColor(normalR, normalG, normalB, normalA)

    -- Apply non-interruptible color via a dedicated overlay whose alpha is
    -- driven by SetAlphaFromBoolean, so we never compare secret values.
    local helper, overlay = GetInterruptibilityColorObjects(statusBar)
    if not helper or not overlay then
        return
    end

    local fillTexture = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    overlay:ClearAllPoints()
    if fillTexture then
        overlay:SetPoint("TOPLEFT", fillTexture, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", fillTexture, "BOTTOMRIGHT", 0, 0)
        local texturePath = fillTexture.GetTexture and fillTexture:GetTexture()
        if texturePath then
            overlay:SetTexture(texturePath)
        else
            overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
    else
        overlay:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    end

    local lockedR, lockedG, lockedB, lockedA = GetSafeColor(notInterruptibleColor, NOT_INTERRUPTIBLE_COLOR)
    overlay:SetVertexColor(lockedR, lockedG, lockedB, lockedA)

    if helper.SetAlphaFromBoolean and notInterruptible ~= nil then
        pcall(helper.SetAlphaFromBoolean, helper, notInterruptible, 1, 0)
        overlay:SetAlpha(helper:GetAlpha())
        overlay:Show()
    elseif type(notInterruptible) == "boolean" then
        overlay:SetAlpha(notInterruptible and 1 or 0)
        overlay:Show()
    else
        overlay:SetAlpha(0)
        overlay:Hide()
    end
end

---------------------------------------------------------------------------
-- POSITIONING HELPERS
---------------------------------------------------------------------------
local function PositionCastbarByAnchor(anchorFrame, castSettings, unitFrame, barHeight)
    local anchor = castSettings.anchor or "none"

    -- Skip if anchoring system has overridden this frame
    if anchorFrame.unitKey and _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(anchorFrame.unitKey .. "Castbar") then return end

    anchorFrame:ClearAllPoints()
    
    if anchor == "essential" then
        local offsetX = QUICore:PixelRound(castSettings.offsetX or 0, anchorFrame)
        local offsetY = QUICore:PixelRound(castSettings.offsetY or -25, anchorFrame)
        local widthAdj = QUICore:PixelRound(castSettings.widthAdjustment or 0, anchorFrame)
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
        if viewer then
            -- Keep castbar spacing visually consistent with the active bottom CDM row.
            -- In horizontal CDM layouts, row yOffset can move the visible bottom row
            -- without changing the viewer frame bounds.
            local bottomRowYOffset = 0
            local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(viewer)
            if (vs and vs.layoutDir) ~= "VERTICAL" then
                bottomRowYOffset = QUICore:PixelRound((vs and vs.bottomRowYOffset) or 0, anchorFrame)
            end
            anchorFrame:SetPoint("TOPLEFT", viewer, "BOTTOMLEFT", offsetX - widthAdj, offsetY + bottomRowYOffset)
            anchorFrame:SetPoint("TOPRIGHT", viewer, "BOTTOMRIGHT", offsetX + widthAdj, offsetY + bottomRowYOffset)
        else
            if unitFrame then
                anchorFrame:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", offsetX, offsetY)
            else
                anchorFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
            end
        end
    elseif anchor == "utility" then
        local offsetX = QUICore:PixelRound(castSettings.offsetX or 0, anchorFrame)
        local offsetY = QUICore:PixelRound(castSettings.offsetY or -25, anchorFrame)
        local widthAdj = QUICore:PixelRound(castSettings.widthAdjustment or 0, anchorFrame)
        local viewer = _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("utility")
        if viewer then
            -- Mirror Essential logic so Utility-anchored castbars behave consistently.
            local bottomRowYOffset = 0
            local vs = _G.QUI_GetCDMViewerState and _G.QUI_GetCDMViewerState(viewer)
            if (vs and vs.layoutDir) ~= "VERTICAL" then
                bottomRowYOffset = QUICore:PixelRound((vs and vs.bottomRowYOffset) or 0, anchorFrame)
            end
            anchorFrame:SetPoint("TOPLEFT", viewer, "BOTTOMLEFT", offsetX - widthAdj, offsetY + bottomRowYOffset)
            anchorFrame:SetPoint("TOPRIGHT", viewer, "BOTTOMRIGHT", offsetX + widthAdj, offsetY + bottomRowYOffset)
        else
            if unitFrame then
                anchorFrame:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", offsetX, offsetY)
            else
                anchorFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
            end
        end
    elseif anchor == "unitframe" then
        local offsetX = QUICore:PixelRound(castSettings.offsetX or 0, anchorFrame)
        local offsetY = QUICore:PixelRound(castSettings.offsetY or -25, anchorFrame)
        local widthAdj = QUICore:PixelRound(castSettings.widthAdjustment or 0, anchorFrame)
        if unitFrame then
            anchorFrame:SetPoint("TOPLEFT", unitFrame, "BOTTOMLEFT", offsetX - widthAdj, offsetY)
            anchorFrame:SetPoint("TOPRIGHT", unitFrame, "BOTTOMRIGHT", offsetX + widthAdj, offsetY)
        else
            anchorFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        end
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
    else
        local frameWidth = (unitFrame and unitFrame:GetWidth()) or 250
        local widthValue = (type(castSettings.width) == "number" and castSettings.width > 0) and castSettings.width or frameWidth
        local castWidth = QUICore:PixelRound(widthValue, anchorFrame)
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
    local border = anchorFrame and anchorFrame.Border

    if not statusBar then return end

    statusBar:SetHeight(barHeight)
    statusBar:ClearAllPoints()

    -- Inset statusBar by borderSize so border is visible around it (like unit frames)
    if ShouldShowIcon(anchorFrame, castSettings) then
        local iconSizePx = iconSize * iconScale
        local iconSpacing = QUICore:PixelRound(castSettings.iconSpacing or 0, anchorFrame)
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
    
    local r, g, b, a = GetSafeColor(castSettings.borderColor, {0, 0, 0, 1})
    if UIKit and UIKit.CreateBackdropBorder then
        border = UIKit.CreateBackdropBorder(anchorFrame, castSettings.borderSize or 1, r, g, b, a)
        anchorFrame.Border = border
        statusBar.Border = border
    end

    if border then
        border:SetFrameLevel(statusBar:GetFrameLevel() - 1)

        if borderSize > 0 then
            border:Show()
        else
            border:Hide()
        end
    end
end

local VALID_TEXT_ANCHORS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local BAR_EDGE_PADDING = 2
local TIME_TEXT_RESERVE_SAMPLE = "9.9"
local TIME_TEXT_EXTRA_PADDING = -4

local function NormalizeTextAnchor(anchor)
    local safeAnchor = string.upper(tostring(anchor or "CENTER"))
    if not VALID_TEXT_ANCHORS[safeAnchor] then
        return "CENTER"
    end
    return safeAnchor
end

local function GetTextJustificationFromAnchor(anchor)
    local safeAnchor = NormalizeTextAnchor(anchor)
    local justifyH = "CENTER"
    local justifyV = "MIDDLE"

    if safeAnchor == "LEFT" or safeAnchor == "TOPLEFT" or safeAnchor == "BOTTOMLEFT" then
        justifyH = "LEFT"
    elseif safeAnchor == "RIGHT" or safeAnchor == "TOPRIGHT" or safeAnchor == "BOTTOMRIGHT" then
        justifyH = "RIGHT"
    end

    if safeAnchor == "TOP" or safeAnchor == "TOPLEFT" or safeAnchor == "TOPRIGHT" then
        justifyV = "TOP"
    elseif safeAnchor == "BOTTOM" or safeAnchor == "BOTTOMLEFT" or safeAnchor == "BOTTOMRIGHT" then
        justifyV = "BOTTOM"
    end

    return justifyH, justifyV
end

local function UpdateTextPosition(textElement, statusBar, anchor, offsetX, offsetY, show)
    if not textElement then return end
    
    if show then
        local normalizedAnchor = NormalizeTextAnchor(anchor)
        local justifyH, justifyV = GetTextJustificationFromAnchor(anchor)
        textElement:SetJustifyH(justifyH)
        textElement:SetJustifyV(justifyV)
        textElement:ClearAllPoints()
        textElement:SetPoint(normalizedAnchor, statusBar, normalizedAnchor, QUICore:PixelRound(offsetX, textElement), QUICore:PixelRound(offsetY, textElement))
        textElement:Show()
    else
        textElement:Hide()
    end
end

local function GetFixedTimeTextReserveWidth(anchorFrame, currentCastSettings)
    if not (anchorFrame and anchorFrame.statusBar and anchorFrame.timeText) then
        return 0
    end

    local timeText = anchorFrame.timeText
    local fontPath, fontSize, fontFlags = timeText:GetFont()
    local safeFontPath = fontPath or GetFontPath()
    local safeFontSize = fontSize or currentCastSettings.fontSize or 12
    local safeFontFlags = fontFlags or GetFontOutline() or ""
    local fontSignature = tostring(safeFontPath) .. "|" .. tostring(safeFontSize) .. "|" .. tostring(safeFontFlags)

    if anchorFrame._timeTextReserveSignature ~= fontSignature then
        local probe = anchorFrame._timeTextReserveProbe
        if not probe then
            probe = anchorFrame.statusBar:CreateFontString(nil, "OVERLAY")
            probe:SetWordWrap(false)
            anchorFrame._timeTextReserveProbe = probe
        end

        local ok = pcall(probe.SetFont, probe, safeFontPath, safeFontSize, safeFontFlags)
        if not ok then
            probe:SetFont(GetFontPath(), currentCastSettings.fontSize or 12, GetFontOutline())
        end
        probe:SetText(TIME_TEXT_RESERVE_SAMPLE)

        anchorFrame._timeTextReserveWidth = SafeToNumber(probe:GetStringWidth()) or 0
        anchorFrame._timeTextReserveSignature = fontSignature
    end

    local reserveWidth = anchorFrame._timeTextReserveWidth or 0
    if reserveWidth <= 0 then
        reserveWidth = SafeToNumber(timeText:GetStringWidth()) or 0
    end
    return reserveWidth
end

local function UpdateSpellTextWidthClamp(anchorFrame, castSettingsOverride, showTimeTextOverride)
    if not (anchorFrame and anchorFrame.spellText and anchorFrame.statusBar) then return end

    local currentSettings = anchorFrame.unitKey and GetUnitSettings(anchorFrame.unitKey)
    local currentCastSettings = (currentSettings and currentSettings.castbar) or castSettingsOverride
    if not currentCastSettings then return end

    local barWidth = SafeToNumber(anchorFrame.statusBar:GetWidth())
    if not (barWidth and barWidth > 0) then return end

    local showTimeText = showTimeTextOverride
    if showTimeText == nil then
        showTimeText = currentCastSettings.showTimeText
        if showTimeText and currentCastSettings.hideTimeTextOnEmpowered and anchorFrame.isEmpowered then
            showTimeText = false
        end
    end

    local spellPad = math.max(0, math.abs(currentCastSettings.spellTextOffsetX or 4))
    local reserveForTime = 0

    if showTimeText and anchorFrame.timeText and anchorFrame.timeText:IsShown() then
        local timePad = math.max(0, math.abs(currentCastSettings.timeTextOffsetX or -4))
        local fixedReserveWidth = GetFixedTimeTextReserveWidth(anchorFrame, currentCastSettings)
        if fixedReserveWidth > 0 then
            reserveForTime = timePad + fixedReserveWidth + TIME_TEXT_EXTRA_PADDING
        end
    end

    anchorFrame.spellText:SetWidth(math.max(1, barWidth - spellPad - reserveForTime - BAR_EDGE_PADDING))
end

---------------------------------------------------------------------------
-- CHANNEL TICK RESOLVER + RENDERING
---------------------------------------------------------------------------
local ClampNumber = nsHelpers.Clamp

local function SafeRound(value)
    if not value then return nil end
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function GetChannelTickSourcePolicy(castSettings)
    local policy = castSettings and castSettings.channelTickSourcePolicy
    if policy == CHANNEL_TICK_SOURCE_POLICY_STATIC or policy == CHANNEL_TICK_SOURCE_POLICY_RUNTIME_ONLY then
        return policy
    end
    return CHANNEL_TICK_SOURCE_POLICY_AUTO
end

local function GetDurationSecondsFromDurationObject(durationObj)
    if not durationObj then return nil end

    local getters = {
        "GetTotalDuration",
        "GetDuration",
        "GetMaxDuration",
        "GetRemainingDuration",
        "GetRemaining",
    }

    for _, methodName in ipairs(getters) do
        local getter = durationObj[methodName]
        if getter then
            local ok, value = pcall(getter, durationObj)
            if ok then
                value = SafeToNumber(value)
                if value and value > 0 then
                    return value
                end
            end
        end
    end
    return nil
end

local function BuildEvenTickPositions(tickCount)
    if not tickCount or tickCount <= 1 then
        return nil
    end
    local positions = {}
    for i = 1, tickCount - 1 do
        positions[#positions + 1] = i / tickCount
    end
    return positions
end

local function BuildIntervalTickPositions(duration, interval)
    if not duration or duration <= 0 or not interval or interval <= 0 then
        return nil, nil
    end

    local tickCount = SafeRound(duration / interval)
    tickCount = ClampNumber(tickCount or 0, 2, 24)
    local positions = {}
    for i = 1, tickCount - 1 do
        local position = (i * interval) / duration
        if position > 0 and position < 1 then
            positions[#positions + 1] = position
        end
    end

    if #positions == 0 then
        positions = BuildEvenTickPositions(tickCount)
    end

    return tickCount, positions
end

local function IsSpellKnownForTickRule(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID)
    end
    if IsPlayerSpell then
        return IsPlayerSpell(spellID)
    end
    return false
end

local function UnitHasAuraBySpellID(unit, auraSpellID, filter)
    if not unit or not auraSpellID then return false end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        local aura = C_UnitAuras.GetAuraDataBySpellID(unit, auraSpellID)
        if aura then
            return true
        end
    end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        local aura = AuraUtil.FindAuraBySpellID(auraSpellID, unit, filter)
        return aura ~= nil
    end

    return false
end

local function ResolveRuleBasedTickModel(castbar, castContext)
    local spellID = castContext and NormalizeChannelTickSpellID(castContext.spellID)
    local rule = spellID and CHANNEL_TICK_RULE_DB[spellID]
    if not rule then return nil end

    local tickCount = rule.baseTicks
    if not tickCount or tickCount <= 1 then
        return nil
    end

    if rule.talentOptions then
        for _, option in ipairs(rule.talentOptions) do
            if option and IsSpellKnownForTickRule(option.spellID) and option.ticks and option.ticks > 1 then
                tickCount = option.ticks
                break
            end
        end
    end

    if rule.auraOptions and castContext and castContext.unit then
        for _, option in ipairs(rule.auraOptions) do
            if option and UnitHasAuraBySpellID(castContext.unit, option.auraSpellID, option.filter) and option.ticks and option.ticks > 1 then
                tickCount = option.ticks
                break
            end
        end
    end

    if rule.sequenceBonus and castContext and castContext.unit and UnitIsUnit and UnitIsUnit(castContext.unit, "player") then
        local history = castbar.channelTickRuleHistory or {}
        local now = GetTime()
        local last = history[spellID]
        if last and (now - last) <= (rule.sequenceBonus.windowSeconds or 0) then
            tickCount = tickCount + (rule.sequenceBonus.bonusTicks or 0)
        end
        history[spellID] = now
        castbar.channelTickRuleHistory = history
    end

    tickCount = ClampNumber(SafeRound(tickCount) or 0, 2, 24)
    local positions = BuildEvenTickPositions(tickCount)
    if not positions or #positions == 0 then
        return nil
    end

    return {
        positions = positions,
        tickCount = tickCount,
        confidence = 0.9,
        source = "rules",
        reason = "curated_profile",
    }
end

local function HideChannelTickMarkers(bar)
    if not bar or not bar.channelTickMarkers then return end
    for _, marker in ipairs(bar.channelTickMarkers) do
        marker:Hide()
    end
end

local function StoreChannelTickCalibration(observation)
    if not observation then return end
    local spellID = NormalizeChannelTickSpellID(observation.spellID)
    if not spellID then return end
    if not observation.tickTimes or #observation.tickTimes < 2 then return end

    local intervals = {}
    for i = 2, #observation.tickTimes do
        local delta = observation.tickTimes[i] - observation.tickTimes[i - 1]
        if delta and delta > 0.05 and delta < 5 then
            intervals[#intervals + 1] = delta
        end
    end
    if #intervals == 0 then return end

    local sum = 0
    for _, interval in ipairs(intervals) do
        sum = sum + interval
    end
    local avgInterval = sum / #intervals
    if not avgInterval or avgInterval <= 0 then return end

    local variance = 0
    for _, interval in ipairs(intervals) do
        local diff = interval - avgInterval
        variance = variance + (diff * diff)
    end
    variance = variance / #intervals
    local stdev = math.sqrt(variance)
    local variation = stdev / avgInterval

    local observedTickCount = #observation.tickTimes
    if observation.startTime and observation.endTime and observation.endTime > observation.startTime then
        local duration = observation.endTime - observation.startTime
        local derivedCount = SafeRound(duration / avgInterval)
        if derivedCount and derivedCount > observedTickCount then
            observedTickCount = derivedCount
        end
    end
    observedTickCount = ClampNumber(observedTickCount, 2, 24)

    local confidence = 0.45 + math.min(0.2, #intervals * 0.05)
    if variation <= 0.08 then
        confidence = confidence + 0.25
    elseif variation <= 0.15 then
        confidence = confidence + 0.15
    elseif variation <= 0.25 then
        confidence = confidence + 0.05
    else
        confidence = confidence - 0.1
    end

    local matchQuality = ClampNumber(observation.matchQuality or 0.5, 0.25, 1)
    confidence = confidence + (0.1 * (matchQuality - 0.5))
    confidence = ClampNumber(confidence, 0.35, 0.95)

    local existing = CHANNEL_TICK_RUNTIME_CACHE[spellID]
    if existing then
        existing.interval = (existing.interval * 0.7) + (avgInterval * 0.3)
        existing.tickCount = SafeRound((existing.tickCount * 0.7) + (observedTickCount * 0.3))
        existing.confidence = ClampNumber(math.max(existing.confidence * 0.9, confidence), 0.3, 0.95)
        existing.updatedAt = GetTime()
    else
        CHANNEL_TICK_RUNTIME_CACHE[spellID] = {
            interval = avgInterval,
            tickCount = observedTickCount,
            confidence = confidence,
            updatedAt = GetTime(),
        }
    end
end

local function StopChannelTickObservation(bar)
    if not bar then return end
    local guid = NormalizeChannelTickGUID(bar.channelTickObservationGUID)
    if not guid then
        local unit = bar.unit
        guid = unit and NormalizeChannelTickGUID(UnitGUID(unit))
    end
    if not guid then
        bar.channelTickObservationGUID = nil
        return
    end

    local observation = CHANNEL_TICK_ACTIVE_BY_GUID[guid]
    if observation then
        StoreChannelTickCalibration(observation)
        CHANNEL_TICK_ACTIVE_BY_GUID[guid] = nil
    end
    bar.channelTickObservationGUID = nil
end

local function OnChannelTickCombatLogEvent()
    local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
    if not CHANNEL_TICK_SUBEVENTS[subEvent] then return end
    sourceGUID = NormalizeChannelTickGUID(sourceGUID)
    if not sourceGUID then return end

    local observation = CHANNEL_TICK_ACTIVE_BY_GUID[sourceGUID]
    if not observation then return end

    local now = GetTime()
    if observation.endTime and now > (observation.endTime + 0.5) then
        StoreChannelTickCalibration(observation)
        CHANNEL_TICK_ACTIVE_BY_GUID[sourceGUID] = nil
        return
    end

    local matched = false
    local quality = 0.5
    local normalizedSpellID = NormalizeChannelTickSpellID(spellID)
    local observationSpellID = NormalizeChannelTickSpellID(observation.spellID)
    if observationSpellID and normalizedSpellID and observationSpellID == normalizedSpellID then
        matched = true
        quality = 1.0
    elseif observation.spellName and spellName and observation.spellName == spellName then
        matched = true
        quality = 0.75
    end
    if not matched then return end

    if observation.lastTickTime and (now - observation.lastTickTime) < 0.08 then
        return
    end

    observation.lastTickTime = now
    observation.matchQuality = math.max(observation.matchQuality or 0, quality)
    if observation.tickTimes then
        observation.tickTimes[#observation.tickTimes + 1] = now
    end
end

local function EnsureChannelTickEventRegistration()
    if CHANNEL_TICK_EVENT_REGISTERED then return end
    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return end
    EventRegistry:RegisterCallback("COMBAT_LOG_EVENT_UNFILTERED", OnChannelTickCombatLogEvent, CHANNEL_TICK_EVENT_FRAME)
    CHANNEL_TICK_EVENT_REGISTERED = true
end

local function StartChannelTickObservation(bar, spellID, spellName, startTime, endTime)
    if not bar or not bar.unit then return end
    local sourceGUID = NormalizeChannelTickGUID(UnitGUID(bar.unit))
    if not sourceGUID then return end

    EnsureChannelTickEventRegistration()
    StopChannelTickObservation(bar)

    CHANNEL_TICK_ACTIVE_BY_GUID[sourceGUID] = {
        spellID = NormalizeChannelTickSpellID(spellID),
        spellName = spellName,
        sourceGUID = sourceGUID,
        startTime = startTime or GetTime(),
        endTime = endTime,
        tickTimes = {},
        matchQuality = 0,
        lastTickTime = nil,
    }
    bar.channelTickObservationGUID = sourceGUID
end

local function GetChannelTickMinConfidence(castSettings)
    local v = castSettings and castSettings.channelTickMinConfidence
    return ClampNumber(v or 0.7, 0.5, 1.0)
end

local function ResolveChannelTickModel(castbar, castSettings, castContext)
    if not castContext or not castContext.isChanneled then
        return nil
    end
    if castContext.isEmpowered then
        return nil
    end
    if not castSettings or castSettings.showChannelTicks == false then
        return nil
    end

    local minConfidence = GetChannelTickMinConfidence(castSettings)
    local sourcePolicy = GetChannelTickSourcePolicy(castSettings)
    local duration = castContext.duration
    local spellID = NormalizeChannelTickSpellID(castContext.spellID)

    local rulesCandidate
    if sourcePolicy ~= CHANNEL_TICK_SOURCE_POLICY_RUNTIME_ONLY then
        rulesCandidate = ResolveRuleBasedTickModel(castbar, castContext)
    end

    local staticCandidate
    if sourcePolicy ~= CHANNEL_TICK_SOURCE_POLICY_RUNTIME_ONLY and spellID then
        local staticModel = CHANNEL_TICK_STATIC_DB[spellID]
        if staticModel then
            local tickCount, positions = BuildIntervalTickPositions(duration, staticModel.interval)
            if positions and #positions > 0 then
                staticCandidate = {
                    positions = positions,
                    tickCount = tickCount,
                    confidence = 0.8,
                    source = "static",
                    reason = "static_interval",
                }
            end
        end
    end

    local runtimeCandidate
    if sourcePolicy ~= CHANNEL_TICK_SOURCE_POLICY_STATIC and spellID then
        local runtimeModel = CHANNEL_TICK_RUNTIME_CACHE[spellID]
        if runtimeModel then
            local tickCount = runtimeModel.tickCount
            local positions = nil

            if runtimeModel.interval and duration and duration > 0 then
                tickCount, positions = BuildIntervalTickPositions(duration, runtimeModel.interval)
            elseif tickCount and tickCount > 1 then
                positions = BuildEvenTickPositions(tickCount)
            end

            if positions and #positions > 0 then
                runtimeCandidate = {
                    positions = positions,
                    tickCount = tickCount or #positions + 1,
                    confidence = ClampNumber(runtimeModel.confidence or 0.5, 0.3, 0.95),
                    source = "runtime",
                    reason = "runtime_calibration",
                }
            end
        end
    end

    local function candidatePasses(candidate)
        return candidate and candidate.confidence >= minConfidence
    end

    if sourcePolicy == CHANNEL_TICK_SOURCE_POLICY_RUNTIME_ONLY then
        if candidatePasses(runtimeCandidate) then return runtimeCandidate end
        return nil
    end
    if sourcePolicy == CHANNEL_TICK_SOURCE_POLICY_STATIC then
        if candidatePasses(rulesCandidate) then return rulesCandidate end
        if candidatePasses(staticCandidate) then return staticCandidate end
        return nil
    end

    -- Auto policy:
    -- - use static immediately as a baseline,
    -- - allow runtime to override when it is more trustworthy or materially disagrees.
    if candidatePasses(rulesCandidate) then
        return rulesCandidate
    end

    local staticOk = candidatePasses(staticCandidate)
    local runtimeOk = candidatePasses(runtimeCandidate)
    if staticOk and runtimeOk then
        local runtimeBetter = runtimeCandidate.confidence >= ((staticCandidate.confidence or 0) + 0.03)
        local tickMismatch = runtimeCandidate.tickCount and staticCandidate.tickCount
            and math.abs(runtimeCandidate.tickCount - staticCandidate.tickCount) >= 1
        if runtimeBetter or (tickMismatch and runtimeCandidate.confidence >= 0.75) then
            return runtimeCandidate
        end
        return staticCandidate
    end
    if staticOk then return staticCandidate end
    if runtimeOk then return runtimeCandidate end
    return nil
end

local function EnsureChannelTickTextures(bar, count)
    if not bar or not bar.statusBar or not count or count <= 0 then return end
    bar.channelTickMarkers = bar.channelTickMarkers or {}

    for i = 1, count do
        local marker = bar.channelTickMarkers[i]
        if not marker then
            marker = bar.statusBar:CreateTexture(nil, "OVERLAY", nil, 3)
            bar.channelTickMarkers[i] = marker
        end
    end
end

local function ApplyChannelTickPositions(bar, positions, castSettings)
    if not bar or not bar.statusBar or not positions then return false end

    local barWidth = SafeToNumber(bar.statusBar:GetWidth())
    local barHeight = SafeToNumber(bar.statusBar:GetHeight())
    if not barWidth or barWidth <= 0 or not barHeight or barHeight <= 0 then
        bar.channelTickLayoutDirty = true
        return false
    end

    EnsureChannelTickTextures(bar, #positions)
    local color = castSettings and castSettings.channelTickColor or CHANNEL_TICK_DEFAULT_COLOR
    local thickness = QUICore:Pixels((castSettings and castSettings.channelTickThickness) or 1, bar.statusBar)
    thickness = math.max(QUICore:Pixels(1, bar.statusBar), thickness)

    for i, position in ipairs(positions) do
        local marker = bar.channelTickMarkers[i]
        local x = QUICore:PixelRound((barWidth * position) - (thickness / 2), bar.statusBar)
        marker:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 0.9)
        marker:ClearAllPoints()
        marker:SetPoint("LEFT", bar.statusBar, "LEFT", x, 0)
        marker:SetPoint("TOP", bar.statusBar, "TOP", 0, 0)
        marker:SetPoint("BOTTOM", bar.statusBar, "BOTTOM", 0, 0)
        marker:SetWidth(thickness)
        marker:Show()
    end

    if bar.channelTickMarkers then
        for i = #positions + 1, #bar.channelTickMarkers do
            if bar.channelTickMarkers[i] then
                bar.channelTickMarkers[i]:Hide()
            end
        end
    end

    bar.channelTickLayoutDirty = nil
    bar.channelTickLastLayout = string.format("%d:%d:%d:%0.2f",
        SafeRound(barWidth) or 0,
        SafeRound(barHeight) or 0,
        #positions,
        thickness
    )
    return true
end

local function RefreshChannelTickMarkers(bar, castSettings)
    if not bar then return end
    if not bar.channelTickPositions or #bar.channelTickPositions == 0 then
        HideChannelTickMarkers(bar)
        return
    end
    if not castSettings or castSettings.showChannelTicks == false then
        HideChannelTickMarkers(bar)
        return
    end
    ApplyChannelTickPositions(bar, bar.channelTickPositions, castSettings)
end

local function ClearChannelTickState(bar)
    if not bar then return end
    HideChannelTickMarkers(bar)
    StopChannelTickObservation(bar)
    bar.channelTickPositions = nil
    bar.channelTickResolution = nil
    bar.channelTickSpellID = nil
    bar.channelTickLayoutDirty = nil
    bar.channelTickLastLayout = nil
end

local function UpdateChannelTicksForCurrentCast(bar, castSettings, castContext)
    if not bar then return end
    ClearChannelTickState(bar)
    if bar.unitKey == "boss" or bar.unitKey == "pet"
        or (type(bar.unit) == "string" and (bar.unit:match("^boss%d+$") or bar.unit == "pet")) then
        return
    end

    if not castContext or not castContext.isChanneled then
        return
    end
    if castContext.isEmpowered then
        return
    end

    local sourcePolicy = GetChannelTickSourcePolicy(castSettings)
    if sourcePolicy ~= CHANNEL_TICK_SOURCE_POLICY_STATIC then
        StartChannelTickObservation(
            bar,
            castContext.spellID,
            castContext.spellName,
            castContext.startTime,
            castContext.endTime
        )
    end

    local resolution = ResolveChannelTickModel(bar, castSettings, castContext)
    if not resolution or not resolution.positions or #resolution.positions == 0 then
        return
    end

    bar.channelTickResolution = resolution
    bar.channelTickPositions = resolution.positions
    bar.channelTickSpellID = NormalizeChannelTickSpellID(castContext.spellID)
    RefreshChannelTickMarkers(bar, castSettings)
end

---------------------------------------------------------------------------
-- MAIN UPDATE FUNCTION
---------------------------------------------------------------------------
local function UpdateCastbarElements(anchorFrame, unitKey, castSettings)
    local currentSettings = GetUnitSettings(unitKey)
    local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
    
    local barHeight, iconSize, iconScale = GetSizingValues(currentCastSettings, anchorFrame)
    local borderSize = QUICore:Pixels(currentCastSettings.borderSize or 1, anchorFrame)
    local iconBorderSize = QUICore:Pixels(currentCastSettings.iconBorderSize or 1, anchorFrame)
    
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

    -- Constrain spell text width while avoiding over-reserving when time text is empty.
    UpdateSpellTextWidthClamp(anchorFrame, currentCastSettings, showTimeText)

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

    if anchorFrame.channelTickPositions then
        RefreshChannelTickMarkers(anchorFrame, currentCastSettings)
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
        ApplyCastColor(bar.statusBar, false, bar.customColor, bar.customNotInterruptibleColor)
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
    ClearChannelTickState(castbar)
    
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
        ApplyCastColor(castbar.statusBar, false, castbar.customColor, castbar.customNotInterruptibleColor)
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
            if self.unitKey and _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(self.unitKey .. "Castbar") then return end
            self:StartMoving()
        end)
        
        castbar:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local screenX, screenY = UIParent:GetCenter()
            local castbarX, castbarY = self:GetCenter()

            if screenX and screenY and castbarX and castbarY then
                local offsetX = QUICore:PixelRound(castbarX - screenX, self)
                local offsetY = QUICore:PixelRound(castbarY - screenY, self)
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
    
    SetCastbarFrameVisible(castbar, true)
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

    ClearChannelTickState(castbar)
    
    if not UnitCastingInfo(castbar.unit) and not UnitChannelInfo(castbar.unit) then
        SetCastbarFrameVisible(castbar, false)
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
    InitializeDefaultSettings(castSettings, unitKey)
    
    local fontSize = castSettings.fontSize or 12

    local anchorFrame = CreateAnchorFrame(nil, UIParent)

    local barHeight, iconSize, iconScale = GetSizingValues(castSettings, anchorFrame)
    local borderSize = QUICore:Pixels(castSettings.borderSize or 1, anchorFrame)
    anchorFrame:SetSize(1, barHeight)

    -- Apply HUD layer priority
    local core = GetCore()
    local hudLayering = core and core.db and core.db.profile and core.db.profile.hudLayering
    local layerPriority
    if unitKey == "player" then
        layerPriority = hudLayering and hudLayering.playerCastbar or 5
    elseif unitKey == "target" then
        layerPriority = hudLayering and hudLayering.targetCastbar or 5
    else
        layerPriority = 5  -- Default for any other castbar
    end
    if core and core.GetHUDFrameLevel then
        local frameLevel = core:GetHUDFrameLevel(layerPriority)
        anchorFrame:SetFrameLevel(frameLevel)
    end

    local ir, ig, ib, ia = GetSafeColor(castSettings.iconBorderColor, {0, 0, 0, 1})
    UIKit.CreateIcon(anchorFrame, iconSize, castSettings.iconBorderSize or 1, ir, ig, ib, ia)
    local statusBar = CreateStatusBar(anchorFrame)

    local br, bg_, bb, ba = GetSafeColor(castSettings.borderColor, {0, 0, 0, 1})
    UIKit.CreateBackdropBorder(anchorFrame, castSettings.borderSize or 1, br, bg_, bb, ba)
    statusBar.Border = anchorFrame.Border
    statusBar.Border:SetFrameLevel(statusBar:GetFrameLevel() - 1)

    local bgBar = UIKit.CreateBackground(statusBar)
    anchorFrame.bgBar = bgBar

    local spellText = UIKit.CreateText(statusBar, fontSize, GetFontPath(), GetFontOutline())
    anchorFrame.spellText = spellText

    local timeText = UIKit.CreateText(statusBar, fontSize, GetFontPath(), GetFontOutline())
    anchorFrame.timeText = timeText

    -- Empowered level text (player only)
    if unitKey == "player" then
        local empoweredLevelText = UIKit.CreateText(statusBar, fontSize, GetFontPath(), GetFontOutline())
        anchorFrame.empoweredLevelText = empoweredLevelText
    end

    anchorFrame.UpdateCastbarElements = function(self)
        UpdateCastbarElements(self, unitKey, castSettings)
    end
    
    SetCastbarSize(anchorFrame, castSettings, unitFrame, barHeight)
    PositionCastbarByAnchor(anchorFrame, castSettings, unitFrame, barHeight)
    
    local barColor = GetBarColor(unitKey, castSettings)
    anchorFrame.customColor = barColor
    anchorFrame.customNotInterruptibleColor = GetNotInterruptibleColor(castSettings)
    ApplyBarColor(statusBar, barColor)
    ApplyBackgroundColor(bgBar, castSettings.bgColor)
    statusBar:SetStatusBarTexture(GetTexturePath(castSettings.texture))

    -- Store unit info
    anchorFrame.unit = unit
    anchorFrame.unitKey = unitKey
    anchorFrame._quiCastbar = true
    anchorFrame._quiDesiredVisible = false
    anchorFrame.isChanneled = false
    
    anchorFrame.isEmpowered = false
    anchorFrame.numStages = 0
    anchorFrame.empoweredStages = {}
    anchorFrame.stageOverlays = {}
    anchorFrame.channelTickMarkers = {}
    anchorFrame.channelTickPositions = nil

    -- Castbars can be reached from secure contexts in combat (for example target
    -- swap + immediate cast events). Keep them shown and toggle visibility using
    -- alpha so we don't depend on Show()/Hide() during combat.
    anchorFrame._quiUseAlphaVisibility = true
    anchorFrame:SetAlpha(0)
    anchorFrame:Show()
    
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
    local channelSpellID = nil

    if not spellName then
        spellName, text, texture, startTimeMS, endTimeMS, _, notInterruptible, channelSpellID, _, channelStages = UnitChannelInfo(unit)
        if spellName then
            isChanneled = true
            if channelSpellID and not unitSpellID then
                unitSpellID = channelSpellID
            end
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

local function BuildChannelTickCastContext(castbar, spellName, spellID, isChanneled, isEmpowered, channelStages, startTime, endTime, durationObj, useTimerDriven)
    if not isChanneled then
        return nil
    end

    local resolvedDuration = nil
    local resolvedStart = startTime
    local resolvedEnd = endTime

    if startTime and endTime and endTime > startTime then
        resolvedDuration = endTime - startTime
    else
        resolvedDuration = GetDurationSecondsFromDurationObject(durationObj)
    end

    if not resolvedStart then
        resolvedStart = GetTime()
    end
    if not resolvedEnd and resolvedDuration and resolvedDuration > 0 then
        resolvedEnd = resolvedStart + resolvedDuration
    end

    return {
        spellID = NormalizeChannelTickSpellID(spellID),
        spellName = spellName,
        isChanneled = true,
        isEmpowered = isEmpowered,
        channelStages = channelStages or 0,
        duration = resolvedDuration,
        startTime = resolvedStart,
        endTime = resolvedEnd,
        timerDriven = useTimerDriven == true,
        unit = castbar and castbar.unit,
    }
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
    local activeBarColor = castbar.customColor
    if castbar.isGCD and currentCastSettings and currentCastSettings.gcdColor then
        activeBarColor = currentCastSettings.gcdColor
    end
    ApplyCastColor(castbar.statusBar, notInterruptible, activeBarColor, castbar.customNotInterruptibleColor)
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

local TryApplyDeferredCastbarRefresh

-- Handle case when no cast is active
local function HandleNoCast(castbar, castSettings, isPlayer, onUpdateHandler)
    C_Timer.After(0.1, function()
        if not UnitCastingInfo(castbar.unit) and not UnitChannelInfo(castbar.unit) then
            if isPlayer then
                ClearEmpoweredState(castbar)
            end
            ClearChannelTickState(castbar)

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
                SetCastbarFrameVisible(castbar, false)
                TryApplyDeferredCastbarRefresh(castbar)
            end
        end
    end)
end

local function GetGCDCooldownInfo()
    if not (C_Spell and C_Spell.GetSpellCooldown) then
        return nil, nil
    end

    local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
    if not info then
        return nil, nil
    end

    local startTime = SafeToNumber(info.startTime)
    local duration = SafeToNumber(info.duration)
    local isEnabled = info.isEnabled

    if not ((isEnabled == nil or isEnabled == true or isEnabled == 1) and startTime and duration and duration > 0) then
        return nil, nil
    end

    if (startTime + duration) <= (GetTime() + 0.05) then
        return nil, nil
    end

    return startTime, duration
end

local function GetSpellDisplayInfo(spellID)
    local resolvedSpellID = SafeToNumber(spellID) or GCD_SPELL_ID
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(resolvedSpellID)
        if info then
            return info.name, info.iconID
        end
    end

    return nil, nil
end

local function IsMeleeGCDSpell(spellID)
    local resolvedSpellID = SafeToNumber(spellID)
    if not resolvedSpellID or not (C_Spell and C_Spell.GetSpellPowerCost) then
        return false
    end

    local costs = C_Spell.GetSpellPowerCost(resolvedSpellID)
    if not costs then
        return false
    end

    for _, costInfo in ipairs(costs) do
        local powerType = SafeToNumber(costInfo.type) or SafeToNumber(costInfo.powerType)
        if powerType and GCD_MELEE_POWER_TYPES[powerType] then
            return true
        end
    end

    return false
end

local function IsPlayerOwnedSpell(spellID)
    local resolvedSpellID = SafeToNumber(spellID)
    if not resolvedSpellID then
        return true
    end

    if type(IsSpellKnownOrOverridesKnown) == "function" then
        return IsSpellKnownOrOverridesKnown(resolvedSpellID) == true
    end

    if type(IsPlayerSpell) == "function" then
        return IsPlayerSpell(resolvedSpellID) == true
    end

    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(resolvedSpellID) == true
    end

    return false
end

---------------------------------------------------------------------------
-- UNIFIED CASTBAR SETUP (handles player, target, focus, targettarget)
---------------------------------------------------------------------------
function QUI_Castbar:SetupCastbar(castbar, unit, unitKey, castSettings)
    local isPlayer = (unit == "player")
    castbar.channelTickMarkers = castbar.channelTickMarkers or {}

    local function HideCastbarIfIdle(self)
        if not self then return false end
        if UnitCastingInfo(self.unit) or UnitChannelInfo(self.unit) then
            return false
        end

        local settings = GetUnitSettings(self.unitKey)
        if settings and settings.castbar and settings.castbar.previewMode then
            return false
        end

        if isPlayer then
            ClearEmpoweredState(self)
        end
        ClearChannelTickState(self)
        self.isGCD = false
        self.timerDriven = false
        self.durationObj = nil
        self:SetScript("OnUpdate", nil)
        SetCastbarFrameVisible(self, false)
        return true
    end

    local function ShowGCDCast(self, spellID)
        if not isPlayer then return false end
        if UnitCastingInfo(self.unit) or UnitChannelInfo(self.unit) then return false end
        if not InCombatLockdown() then return false end

        local settings = GetUnitSettings(self.unitKey)
        local currentCastSettings = settings and settings.castbar or castSettings
        if not (currentCastSettings and currentCastSettings.enabled ~= false and currentCastSettings.showGCD) then return false end
        if not IsPlayerOwnedSpell(spellID) then return false end
        if currentCastSettings.showGCDMelee ~= true and IsMeleeGCDSpell(spellID) then return false end

        local startTime, duration = GetGCDCooldownInfo()
        if not startTime or not duration then return false end

        local now = GetTime()
        local endTime = startTime + duration
        if endTime <= (now + 0.02) then return false end

        local spellName, iconTexture = GetSpellDisplayInfo(spellID)
        self.isGCD = true
        self.isChanneled = false
        self.isEmpowered = false
        self.notInterruptible = false
        self.timerDriven = false
        self.durationObj = nil
        self.startTime = startTime
        self.endTime = endTime
        self.castStartTime = nil
        self.castEndTime = nil
        self.channelSpellID = nil
        self._assumeCountdown = nil

        ClearEmpoweredState(self)
        ClearChannelTickState(self)
        self.statusBar:SetReverseFill(currentCastSettings.showGCDReverse == true)
        self:SetScript("OnUpdate", self.castbarOnUpdate)
        SetCastbarFrameVisible(self, true)

        if SetIconTexture(self, iconTexture) then
            if ShouldShowIcon(self, currentCastSettings) then
                self.icon:Show()
            else
                self.icon:Hide()
            end
        end

        UpdateCastbarVisuals(
            self,
            currentCastSettings,
            self.unitKey,
            iconTexture,
            spellName,
            spellName,
            self.unit,
            false,
            false,
            startTime,
            endTime
        )

        return true
    end
    
    -- Unified OnUpdate handler - handles both real casts and preview
    local function CastBar_OnUpdate(self, elapsed)
        local spellName = UnitCastingInfo(self.unit) ~= nil
        local channelName = UnitChannelInfo(self.unit) ~= nil

        -- Continue showing castbar during empowered hold phase even when API returns nil
        local isInEmpoweredHold = isPlayer and self.isEmpowered and self.startTime and self.endTime
        local isShowingGCD = isPlayer and self.isGCD and self.startTime and self.endTime

        if spellName or channelName or isInEmpoweredHold or isShowingGCD then
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

                if self.channelTickPositions then
                    self.channelTickLayoutThrottle = (self.channelTickLayoutThrottle or 0) + elapsed
                    local refreshInterval = self.channelTickLayoutDirty and 0.05 or 0.2
                    if self.channelTickLayoutThrottle >= refreshInterval then
                        self.channelTickLayoutThrottle = 0
                        local currentSettings = GetUnitSettings(self.unitKey)
                        local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
                        RefreshChannelTickMarkers(self, currentCastSettings)
                    end
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
                    ClearChannelTickState(self)
                    self:SetScript("OnUpdate", nil)
                    SetCastbarFrameVisible(self, false)
                    TryApplyDeferredCastbarRefresh(self)
                    return
                end
                startTime = self.castStartTime / 1000
                endTime = self.castEndTime / 1000
            end

            if not startTime or not endTime then
                ClearChannelTickState(self)
                self:SetScript("OnUpdate", nil)
                SetCastbarFrameVisible(self, false)
                TryApplyDeferredCastbarRefresh(self)
                return
            end

            local now = GetTime()
            if now >= endTime then
                if isPlayer then
                    ClearEmpoweredState(self)
                end
                ClearChannelTickState(self)
                self.isGCD = false
                self:SetScript("OnUpdate", nil)
                SetCastbarFrameVisible(self, false)
                TryApplyDeferredCastbarRefresh(self)
                return
            end

            local duration = endTime - startTime
            if duration <= 0 then duration = 0.001 end

            local currentSettings = GetUnitSettings(self.unitKey)
            local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
            local shouldReverseGCD = isShowingGCD and currentCastSettings and currentCastSettings.showGCDReverse
            self.statusBar:SetReverseFill(shouldReverseGCD == true)

            local remaining = endTime - now
            local channelFillForward = castSettings and castSettings.channelFillForward
            local shouldDrain = self.isChanneled and not self.isEmpowered and not channelFillForward
            local progress = shouldDrain and remaining or (now - startTime)

            self.statusBar:SetMinMaxValues(0, duration)
            self.statusBar:SetValue(progress)

            if self.channelTickPositions then
                self.channelTickLayoutThrottle = (self.channelTickLayoutThrottle or 0) + elapsed
                local refreshInterval = self.channelTickLayoutDirty and 0.05 or 0.2
                if self.channelTickLayoutThrottle >= refreshInterval then
                    self.channelTickLayoutThrottle = 0
                    local currentSettings = GetUnitSettings(self.unitKey)
                    local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
                    RefreshChannelTickMarkers(self, currentCastSettings)
                end
            end

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
            ClearChannelTickState(self)
            self:SetScript("OnUpdate", nil)
            SetCastbarFrameVisible(self, false)
        end
    end

    -- Store OnUpdate handler reference
    castbar.castbarOnUpdate = CastBar_OnUpdate
    
    -- Unified Cast function
    function castbar:Cast(spellID, isEmpowerEvent)
        -- Get cast information (now includes durationObj and hasSecretTiming)
        local spellName, text, texture, startTimeMS, endTimeMS, notInterruptible, unitSpellID, isChanneled, channelStages, durationObj, hasSecretTiming = GetCastInfo(self, self.unit)
        local resolvedSpellID = spellID or unitSpellID

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
            self.channelSpellID = resolvedSpellID
            self._assumeCountdown = nil  -- Reset countdown detection for new cast
            self.isGCD = false

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

            -- Start OnUpdate handler and show FIRST — if any visual update below
            -- errors, the castbar still appears (with stale visuals for one frame)
            -- instead of silently staying hidden until /reload.
            self:SetScript("OnUpdate", CastBar_OnUpdate)
            SetCastbarFrameVisible(self, true)

            local channelCastContext = BuildChannelTickCastContext(
                self,
                spellName,
                resolvedSpellID,
                isChanneled,
                isEmpowered,
                channelStages,
                startTime,
                endTime,
                durationObj,
                useTimerDriven
            )
            UpdateChannelTicksForCurrentCast(self, castSettings, channelCastContext)

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
        else
            -- No real cast - handle preview mode
            ClearChannelTickState(self)
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
            if self.isGCD and not UnitCastingInfo(self.unit) and not UnitChannelInfo(self.unit) then
                return
            end
            if isPlayer then ClearEmpoweredState(self) end
            ClearChannelTickState(self)
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            SetCastbarFrameVisible(self, false)
            TryApplyDeferredCastbarRefresh(self)
        end,
        UNIT_SPELLCAST_CHANNEL_STOP = function(self, spellID)
            if self.isGCD and not UnitCastingInfo(self.unit) and not UnitChannelInfo(self.unit) then
                return
            end
            if isPlayer then ClearEmpoweredState(self) end
            ClearChannelTickState(self)
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            SetCastbarFrameVisible(self, false)
            TryApplyDeferredCastbarRefresh(self)
        end,
        UNIT_SPELLCAST_FAILED = function(self, spellID)
            -- Don't hide if a channel is still active (e.g., pressing spell key again during channel)
            if UnitChannelInfo(self.unit) or UnitCastingInfo(self.unit) then
                return
            end
            if self.isGCD then
                return
            end
            if isPlayer then ClearEmpoweredState(self) end
            ClearChannelTickState(self)
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            SetCastbarFrameVisible(self, false)
            TryApplyDeferredCastbarRefresh(self)
        end,
        UNIT_SPELLCAST_INTERRUPTED = function(self, spellID)
            if self.isGCD and not UnitCastingInfo(self.unit) and not UnitChannelInfo(self.unit) then
                return
            end
            if isPlayer then ClearEmpoweredState(self) end
            ClearChannelTickState(self)
            self.timerDriven = false
            self.durationObj = nil
            self:SetScript("OnUpdate", nil)
            SetCastbarFrameVisible(self, false)
            TryApplyDeferredCastbarRefresh(self)
        end,
        
        -- Interruptible state changes
        UNIT_SPELLCAST_INTERRUPTIBLE = function(self)
            self.notInterruptible = false
            ApplyCastColor(self.statusBar, false, self.customColor, self.customNotInterruptibleColor)
        end,
        UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(self)
            self.notInterruptible = true
            ApplyCastColor(self.statusBar, true, self.customColor, self.customNotInterruptibleColor)
        end,
    }
    
    -- Player-only empowered cast handlers
    if isPlayer then
        eventHandlers.PLAYER_REGEN_ENABLED = function(self)
            HideCastbarIfIdle(self)
        end
        eventHandlers.PLAYER_ENTERING_WORLD = function(self)
            C_Timer.After(0, function()
                HideCastbarIfIdle(self)
            end)
        end
        eventHandlers.SPELL_UPDATE_COOLDOWN = function(self)
            if self.isGCD then
                return
            end

            local lastSpellID = self._lastGCDSpellID
            local lastEventAt = self._lastGCDTriggerAt
            if not lastSpellID or not lastEventAt or (GetTime() - lastEventAt) > 0.25 then
                return
            end

            ShowGCDCast(self, lastSpellID)
        end
        eventHandlers.UNIT_SPELLCAST_SUCCEEDED = function(self, spellID)
            if self.isGCD then
                return
            end
            local resolvedSpellID = SafeToNumber(spellID)
            if resolvedSpellID then
                self._lastGCDSpellID = resolvedSpellID
                self._lastGCDTriggerAt = GetTime()
            end

            if not ShowGCDCast(self, resolvedSpellID or self._lastGCDSpellID) then
                if self.isGCD then
                    return
                end
                C_Timer.After(0, function()
                    local retrySpellID = self._lastGCDSpellID
                    if retrySpellID and ShowGCDCast(self, retrySpellID) then
                        return
                    end
                    if self.isGCD then
                        return
                    end
                    HideCastbarIfIdle(self)
                end)
            end
        end
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
                ClearChannelTickState(self)
                self:SetScript("OnUpdate", nil)
                SetCastbarFrameVisible(self, false)
                TryApplyDeferredCastbarRefresh(self)
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
        castbar:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unit)
        castbar:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        castbar:RegisterEvent("PLAYER_REGEN_ENABLED")
        castbar:RegisterEvent("PLAYER_ENTERING_WORLD")
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


---------------------------------------------------------------------------
-- CREATE: Boss Castbar
---------------------------------------------------------------------------
function QUI_Castbar:CreateBossCastbar(unitFrame, unit, bossIndex)
    local settings = GetUnitSettings("boss")
    if not settings or not settings.castbar or not settings.castbar.enabled then
        return nil
    end
    
    local castSettings = settings.castbar
    InitializeDefaultSettings(castSettings, "boss")
    
    local fontSize = castSettings.fontSize or 12

    -- Create anchor frame (outer frame for positioning/sizing)
    local anchorFrame = CreateAnchorFrame("QUI_Boss" .. bossIndex .. "_Castbar", UIParent)

    local frameWidth = unitFrame:GetWidth()
    local castWidth = QUICore:PixelRound((castSettings.width and castSettings.width > 0) and castSettings.width or frameWidth, anchorFrame)
    local barHeight, iconSize, iconScale = GetSizingValues(castSettings, anchorFrame)
    local borderSize = QUICore:Pixels(castSettings.borderSize or 1, anchorFrame)
    anchorFrame:SetSize(castWidth, barHeight)

    -- Anchor to boss unit frame
    QUICore:SetSnappedPoint(anchorFrame, "TOP", unitFrame, "BOTTOM", castSettings.offsetX or 0, castSettings.offsetY or -25)
    
    -- Create UI elements (icon with integrated border) - parented to anchorFrame
    local ir, ig, ib, ia = GetSafeColor(castSettings.iconBorderColor, {0, 0, 0, 1})
    UIKit.CreateIcon(anchorFrame, iconSize, castSettings.iconBorderSize or 1, ir, ig, ib, ia)
    local statusBar = CreateStatusBar(anchorFrame)

    -- Create border for status bar (parented to statusBar)
    local br, bg_, bb, ba = GetSafeColor(castSettings.borderColor, {0, 0, 0, 1})
    UIKit.CreateBackdropBorder(anchorFrame, castSettings.borderSize or 1, br, bg_, bb, ba)
    statusBar.Border = anchorFrame.Border
    statusBar.Border:SetFrameLevel(statusBar:GetFrameLevel() - 1)

    local bgBar = UIKit.CreateBackground(statusBar)
    anchorFrame.bgBar = bgBar

    local spellText = UIKit.CreateText(statusBar, fontSize, GetFontPath(), GetFontOutline())
    spellText:SetPoint("LEFT", statusBar, "LEFT", QUICore:Pixels(4, spellText), 0)
    spellText:SetJustifyH("LEFT")
    anchorFrame.spellText = spellText

    local timeText = UIKit.CreateText(statusBar, fontSize, GetFontPath(), GetFontOutline())
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
    anchorFrame.customNotInterruptibleColor = GetNotInterruptibleColor(castSettings)
    ApplyBarColor(statusBar, barColor)
    ApplyBackgroundColor(bgBar, castSettings.bgColor)
    statusBar:SetStatusBarTexture(GetTexturePath(castSettings.texture))

    -- Update element positions
    UpdateCastbarElements(anchorFrame, "boss", castSettings)

    -- Store unit info
    anchorFrame.unit = unit
    anchorFrame.unitKey = "boss"
    anchorFrame._quiCastbar = true
    anchorFrame._quiDesiredVisible = false
    anchorFrame.bossIndex = bossIndex
    anchorFrame.isChanneled = false
    
    -- Unified OnUpdate handler - handles both real casts and preview
    local function BossCastBar_OnUpdate(self, elapsed)
        -- Check if actually casting (real cast takes priority)
        local spellName = UnitCastingInfo(self.unit)
        local channelName = UnitChannelInfo(self.unit)

        if spellName or channelName then
            -- Timer-driven mode: engine animates the bar, we just update time text
            if self.timerDriven then
                local remaining = nil
                if self.durationObj then
                    local getter = self.durationObj.GetRemainingDuration or self.durationObj.GetRemaining
                    if getter then
                        local okRem, rem = pcall(getter, self.durationObj)
                        if okRem and rem ~= nil then
                            remaining = SafeToNumber(rem)
                        end
                    end
                end
                if remaining and self.timeText then
                    self.timeText:SetText(string.format("%.1f", remaining))
                    UpdateTimeTextColor(self, self.unit)
                end
                return
            end

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
                ClearChannelTickState(self)
                self:SetScript("OnUpdate", nil)
                SetCastbarFrameVisible(self, false)
                TryApplyDeferredCastbarRefresh(self)
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
            ClearChannelTickState(self)
            self:SetScript("OnUpdate", nil)
            SetCastbarFrameVisible(self, false)
            TryApplyDeferredCastbarRefresh(self)
        end
    end
    
    -- Store OnUpdate handler reference
    anchorFrame.bossOnUpdate = BossCastBar_OnUpdate
    
    -- Cast function
    function anchorFrame:Cast()
        -- Use shared GetCastInfo for secret timing detection and duration objects
        local spellName, text, texture, startTimeMS, endTimeMS, notInterruptible, unitSpellID, isChanneled, _, durationObj, hasSecretTiming = GetCastInfo(self, self.unit)

        -- Determine if we can show the cast
        local canShowCast = false
        local useTimerDriven = false
        local startTime, endTime

        if spellName then
            if hasSecretTiming and durationObj and self.statusBar and self.statusBar.SetTimerDuration then
                -- Engine-driven mode: use SetTimerDuration for secret timing
                useTimerDriven = true
                canShowCast = true
            elseif startTimeMS and endTimeMS then
                local success
                success, startTime, endTime = pcall(function()
                    return startTimeMS / 1000, endTimeMS / 1000
                end)
                canShowCast = success
            elseif durationObj and self.statusBar and self.statusBar.SetTimerDuration then
                -- Fallback: timing not explicitly secret but not accessible, try engine-driven
                useTimerDriven = true
                canShowCast = true
            end
        end

        if canShowCast then
            -- Clear preview simulation
            if self.isPreviewSimulation then
                ClearPreviewSimulation(self)
            end

            -- Store cast state
            self.isChanneled = isChanneled
            self.notInterruptible = notInterruptible
            self.channelSpellID = unitSpellID
            self.timerDriven = useTimerDriven
            self.durationObj = durationObj

            if useTimerDriven then
                -- Engine-driven animation for secret timing
                local channelFillForward = castSettings and castSettings.channelFillForward
                local direction = (isChanneled and not channelFillForward) and 1 or 0
                local ok = pcall(self.statusBar.SetTimerDuration, self.statusBar, durationObj, 0, direction)
                if not ok then
                    pcall(self.statusBar.SetTimerDuration, self.statusBar, durationObj)
                end
                self.startTime = nil
                self.endTime = nil
            else
                local now = GetTime()
                self.startTime = startTime
                self.endTime = endTime

                if self.startTime < now - 5 then
                    local dur = self.endTime - self.startTime
                    if dur and dur > 0 then
                        self.startTime = now
                        self.endTime = now + dur
                    end
                end
            end

            -- Start OnUpdate handler and show FIRST — if any visual update below
            -- errors, the castbar still appears instead of silently staying hidden.
            self:SetScript("OnUpdate", BossCastBar_OnUpdate)
            SetCastbarFrameVisible(self, true)

            -- Visual updates (non-critical — castbar already visible above)
            local currentSettings = GetUnitSettings(self.unitKey)
            local currentCastSettings = currentSettings and currentSettings.castbar or castSettings
            if self.statusBar then
                self.statusBar:SetStatusBarTexture(GetTexturePath(currentCastSettings.texture))
                self.statusBar:SetReverseFill(false)
            end

            if SetIconTexture(self, texture) then
                if ShouldShowIcon(self, currentCastSettings) then
                    self.icon:Show()
                else
                    self.icon:Hide()
                end
            end

            UpdateSpellText(self, text, spellName, castSettings, self.unit)
            ApplyCastColor(self.statusBar, notInterruptible, self.customColor, self.customNotInterruptibleColor)
        else
            -- No real cast - check if preview mode is enabled AND boss frame preview is active
            ClearChannelTickState(self)
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
                        SetCastbarFrameVisible(self, false)
                        TryApplyDeferredCastbarRefresh(self)
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
            ClearChannelTickState(self)
            self:Cast()
            TryApplyDeferredCastbarRefresh(self)
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            self.notInterruptible = false
            ApplyCastColor(self.statusBar, false, self.customColor, self.customNotInterruptibleColor)
        elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            self.notInterruptible = true
            ApplyCastColor(self.statusBar, true, self.customColor, self.customNotInterruptibleColor)
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

    -- Explicitly hide the castbar frame in case refresh didn't (e.g. castbar disabled)
    local castbar = QUI_Castbar.castbars and QUI_Castbar.castbars[unitKey]
    if castbar and castbar:IsShown() then
        castbar:Hide()
    end
end

---------------------------------------------------------------------------
-- DESTROY: Clean up a castbar
---------------------------------------------------------------------------
local function DestroyCastbar(castbar)
    if not castbar then return end

    ClearChannelTickState(castbar)
    castbar:UnregisterAllEvents()
    castbar:SetScript("OnUpdate", nil)
    castbar:SetScript("OnEvent", nil)
    castbar:SetScript("OnDragStart", nil)
    castbar:SetScript("OnDragStop", nil)

    castbar:Hide()
    castbar:ClearAllPoints()
end

local function IsRealCastActive(unit)
    if not unit then return false end
    return UnitCastingInfo(unit) ~= nil or UnitChannelInfo(unit) ~= nil
end

local function IsBossPreviewModeActive(bossKey)
    local QUI_UF = QUI_Castbar and QUI_Castbar.unitFramesModule
    return QUI_UF and QUI_UF.previewMode and bossKey and QUI_UF.previewMode[bossKey]
end

local function IsPreviewRefreshRequested(castbar, refreshKey, castSettings)
    if castbar and castbar.isPreviewSimulation then
        return true
    end
    if not (castSettings and castSettings.previewMode) then
        return false
    end
    if refreshKey and refreshKey:match("^boss%d+$") then
        return IsBossPreviewModeActive(refreshKey)
    end
    return true
end

local function ApplyLiveCastbarSettings(castbar, unitKey, castSettings)
    if not castbar or not castSettings then return end

    if castbar.UpdateCastbarElements then
        castbar:UpdateCastbarElements()
    end

    if castbar.statusBar then
        castbar.statusBar:SetStatusBarTexture(GetTexturePath(castSettings.texture))
        ApplyBackgroundColor(castbar.bgBar, castSettings.bgColor)
    end

    if unitKey and unitKey:match("^boss%d+$") then
        castbar.customColor = castSettings.color or castbar.customColor
    else
        castbar.customColor = GetBarColor(unitKey, castSettings)
    end
    castbar.customNotInterruptibleColor = GetNotInterruptibleColor(castSettings)

    if castbar.statusBar then
        ApplyCastColor(castbar.statusBar, castbar.notInterruptible, castbar.customColor, castbar.customNotInterruptibleColor)
    end

    if castbar.icon then
        if ShouldShowIcon(castbar, castSettings) then
            castbar.icon:Show()
        else
            castbar.icon:Hide()
        end
    end

    RefreshChannelTickMarkers(castbar, castSettings)
end

local function QueueDeferredCastbarRefresh(castbar, refreshKey)
    if not castbar or not refreshKey then return end
    castbar._deferredRefreshPending = true
    castbar._deferredRefreshKey = refreshKey
end

TryApplyDeferredCastbarRefresh = function(castbar)
    if not castbar or not castbar._deferredRefreshPending then return end
    if IsRealCastActive(castbar.unit) then return end

    local refreshKey = castbar._deferredRefreshKey
    castbar._deferredRefreshPending = nil
    castbar._deferredRefreshKey = nil

    if type(_G.QUI_RefreshCastbar) == "function" and refreshKey then
        C_Timer.After(0, function()
            _G.QUI_RefreshCastbar(refreshKey)
        end)
    end
end

---------------------------------------------------------------------------
-- REFRESH: Update castbar in place (preserves active casts)
---------------------------------------------------------------------------
function QUI_Castbar:RefreshCastbar(castbar, unitKey, castSettings, unitFrame)
    if not castSettings then return end

    local unit = (castbar and castbar.unit) or unitKey
    if castbar then
        ApplyLiveCastbarSettings(castbar, unitKey, castSettings)
    end

    local previewRefresh = IsPreviewRefreshRequested(castbar, unitKey, castSettings)
    local hasRealCast = IsRealCastActive(unit)
    if castbar and hasRealCast and not previewRefresh then
        QueueDeferredCastbarRefresh(castbar, unitKey)
        return
    end

    if castbar then
        DestroyCastbar(castbar)
    end
    
    local newCastbar = self:CreateCastbar(unitFrame, unit, unitKey)
    if newCastbar then
        local QUI_UF = self.unitFramesModule
        if QUI_UF and QUI_UF.castbars then
            QUI_UF.castbars[unitKey] = newCastbar
        end
        -- Immediately reapply frame anchoring override to the new frame.
        -- PositionCastbarByAnchor already ran on the new frame but couldn't
        -- detect the override (old frame was in layoutOwnedFrames, not this one).
        -- The debounced reapply from HookRefreshGlobal handles eventual
        -- consistency, but this eliminates the brief position jump.
        local anchorKey = unitKey .. "Castbar"
        if _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor(anchorKey)
        end
    end
end

function QUI_Castbar:RefreshBossCastbar(castbar, bossKey, castSettings, unitFrame)
    if not castSettings or not unitFrame then return end

    local bossIndex = (castbar and castbar.bossIndex) or (bossKey and tonumber(bossKey:match("boss(%d+)")))
    if not bossIndex then return end
    
    local unit = (castbar and castbar.unit) or ("boss" .. bossIndex)
    if castbar then
        ApplyLiveCastbarSettings(castbar, bossKey, castSettings)
    end

    local previewRefresh = IsPreviewRefreshRequested(castbar, bossKey, castSettings)
    local hasRealCast = IsRealCastActive(unit)
    if castbar and hasRealCast and not previewRefresh then
        QueueDeferredCastbarRefresh(castbar, bossKey)
        return
    end

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
    -- Note: Edit overlay restoration is handled by RefreshFrame
end

-- Refresh all castbars (used by HUD Layering options)
_G.QUI_RefreshCastbars = function()
    local QUI_UF = QUI_Castbar.unitFramesModule
    if not QUI_UF then return end
    -- Refresh player, target, and focus castbars
    for _, unitKey in ipairs({"player", "target", "focus"}) do
        QUI_UF:RefreshFrame(unitKey)
    end
    -- Note: Edit overlay restoration is handled by RefreshFrame
end

_G.QUI_Castbars = QUI_Castbar.castbars

---------------------------------------------------------------------------
-- EDIT MODE STUBS (old overlay system removed — Layout Mode handles replace)
---------------------------------------------------------------------------

-- No-op stub: called from unitframes.lua RefreshFrame but edit mode overlays are gone.
function QUI_Castbar:RestoreEditOverlaysIfNeeded() end


---------------------------------------------------------------------------
-- UNLOCK MODE ELEMENT REGISTRATION
---------------------------------------------------------------------------
do
    local function RegisterLayoutModeElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local CASTBAR_ELEMENTS = {
            { key = "playerCastbar", label = "Player Castbar", unit = "player", order = 1 },
            { key = "targetCastbar", label = "Target Castbar", unit = "target", order = 2 },
            { key = "focusCastbar",  label = "Focus Castbar",  unit = "focus",  order = 3 },
            { key = "petCastbar",    label = "Pet Castbar",    unit = "pet",    order = 4 },
            { key = "totCastbar",    label = "Target of Target Castbar", unit = "targettarget", order = 5 },
        }

        local function GetCastbarDB(unit)
            local core = ns.Helpers.GetCore()
            local ufdb = core and core.db and core.db.profile and core.db.profile.quiUnitFrames
            return ufdb and ufdb[unit] and ufdb[unit].castbar
        end

        for _, info in ipairs(CASTBAR_ELEMENTS) do
            um:RegisterElement({
                key = info.key,
                label = info.label,
                group = "Castbars",
                order = info.order,
                isOwned = true,
                isEnabled = function()
                    local cb = GetCastbarDB(info.unit)
                    return cb and cb.enabled ~= false
                end,
                setEnabled = function(val)
                    local cb = GetCastbarDB(info.unit)
                    if cb then cb.enabled = val end
                    if _G.QUI_RefreshCastbar then _G.QUI_RefreshCastbar(info.unit) end
                end,
                getFrame = function()
                    return QUI_Castbar.castbars and QUI_Castbar.castbars[info.unit]
                end,
                onOpen = function()
                    if _G.QUI_ShowCastbarPreview then _G.QUI_ShowCastbarPreview(info.unit) end
                end,
                onClose = function()
                    if _G.QUI_HideCastbarPreview then _G.QUI_HideCastbarPreview(info.unit) end
                end,
            })
        end
    end

    C_Timer.After(2, RegisterLayoutModeElements)
end

if ns.Registry then
    ns.Registry:Register("castbar", {
        refresh = _G.QUI_RefreshCastbars,
        priority = 25,
        group = "castbars",
        importCategories = { "castBars", "unitFrames" },
    })
end
