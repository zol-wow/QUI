--[[
    QUI CDM Bar Factory

    Creates and manages addon-owned bar frames for the CDM tracked bar system.
    All bars are simple Frame objects with StatusBar children — no protected
    attributes, eliminating combat taint concerns for frame operations.

    Data is mirrored from hidden Blizzard BuffBarCooldownViewer children via
    hooksecurefunc. Blizzard C-side methods (SetValue, SetMinMaxValues, etc.)
    handle secret values natively.

    Pattern mirrors cdm_icons.lua pool management.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local QUICore = ns.Addon
local LSM = ns.LSM

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local CDMBars = {}
ns.CDMBars = CDMBars

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local GetGeneralFont = Helpers.GetGeneralFont
local GetGeneralFontOutline = Helpers.GetGeneralFontOutline
local SafeValue = Helpers.SafeValue
local SafeToNumber = Helpers.SafeToNumber
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

-- Upvalue hot-path globals
local type = type
local ipairs = ipairs
local pcall = pcall
local issecretvalue = issecretvalue
local string_format = string.format
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------
local MAX_RECYCLE_POOL_SIZE = 20

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local barPool = {}       -- active bars (array)
local recyclePool = {}   -- recycled bars (array, max MAX_RECYCLE_POOL_SIZE)
local barTimerFrame = CreateFrame("Frame")
local barTimerGroup = barTimerFrame:CreateAnimationGroup()
local barTimerAnim = barTimerGroup:CreateAnimation()
barTimerAnim:SetDuration(0.1)  -- 100ms = ~10 FPS
barTimerGroup:SetLooping("REPEAT")

-- Weak-keyed: Blizzard statusBar → owned bar (handles Blizzard frame recycling)
local mirrorMap = Helpers.CreateStateTable()

-- Track which Blizzard bar children have been hooked (weak-keyed)
local hookedBars = Helpers.CreateStateTable()

-- Stored refs for periodic re-layout after ticker updates _active state
local _lastContainer = nil
local _lastSettings = nil

---------------------------------------------------------------------------
-- BAR FRAME FACTORY
---------------------------------------------------------------------------
local function CreateBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(200, 25)

    -- StatusBar for duration progress
    local statusBar = CreateFrame("StatusBar", nil, bar)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    bar.StatusBar = statusBar

    -- Background texture (BACKGROUND, sublevel -8)
    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0, 0, 0, 1)
    bar.Background = bg

    -- Icon container frame
    local iconContainer = CreateFrame("Frame", nil, bar)
    iconContainer:SetSize(25, 25)
    bar.IconContainer = iconContainer

    -- Icon texture inside container
    local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconContainer)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.IconTexture = iconTex

    -- Border container with 4-edge textures
    local borderFrame = CreateFrame("Frame", nil, bar)
    borderFrame:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 5)
    borderFrame._top = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._top:SetColorTexture(0, 0, 0, 1)
    borderFrame._bottom = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._bottom:SetColorTexture(0, 0, 0, 1)
    borderFrame._left = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._left:SetColorTexture(0, 0, 0, 1)
    borderFrame._right = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderFrame._right:SetColorTexture(0, 0, 0, 1)
    bar.BorderContainer = borderFrame

    -- Text overlay frame (renders above StatusBar fill texture)
    local textOverlay = CreateFrame("Frame", nil, statusBar)
    textOverlay:SetAllPoints(statusBar)
    textOverlay:SetFrameLevel((statusBar.GetFrameLevel and statusBar:GetFrameLevel() or 1) + 2)
    bar.TextOverlay = textOverlay

    -- Name text (spell name)
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    nameText:SetFont(GetGeneralFont(), 14, GetGeneralFontOutline())
    nameText:SetPoint("LEFT", statusBar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetShadowColor(0, 0, 0, 1)
    nameText:SetShadowOffset(1, -1)
    bar.NameText = nameText

    -- Duration text (remaining time)
    local durationText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    durationText:SetFont(GetGeneralFont(), 14, GetGeneralFontOutline())
    durationText:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    durationText:SetJustifyH("RIGHT")
    durationText:SetTextColor(1, 1, 1, 1)
    durationText:SetShadowColor(0, 0, 0, 1)
    durationText:SetShadowOffset(1, -1)
    bar.DurationText = durationText

    -- State tracking
    bar._spellEntry = nil
    bar._blizzBar = nil
    bar._spellID = nil
    bar._active = false
    bar._cSideFill = nil

    bar:Hide()
    return bar
end

---------------------------------------------------------------------------
-- Helper functions for color overrides
---------------------------------------------------------------------------

local function GetBarDisplayName(frame)
    if not frame or not frame.GetRegions then return nil end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            local okText, rawText = pcall(region.GetText, region)
            local text = okText and Helpers.SafeValue(rawText, nil) or nil
            if type(text) == "string" and text ~= "" then
                local justify = region.GetJustifyH and region:GetJustifyH()
                if justify ~= "RIGHT" then
                    return text
                end
            end
        end
    end
    return nil
end

local function GetBlizzTrackedBarSpellData(blizzBarChild)
    if not blizzBarChild then return nil end

    local resolvedSpellID, baseSpellID, overrideSpellID, name
    local cdInfo = blizzBarChild.cooldownInfo
    if cdInfo then
        overrideSpellID = Helpers.SafeToNumber(cdInfo.overrideSpellID, nil)
        baseSpellID = Helpers.SafeToNumber(cdInfo.spellID, nil)
        name = Helpers.SafeValue(cdInfo.name, nil)
        resolvedSpellID = overrideSpellID or baseSpellID
    end

    local cdID = blizzBarChild.cooldownID
    if (not resolvedSpellID or not name) and cdID
        and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if okInfo and info then
            overrideSpellID = overrideSpellID or Helpers.SafeToNumber(info.overrideSpellID, nil)
            baseSpellID = baseSpellID or Helpers.SafeToNumber(info.spellID, nil)
            name = name or Helpers.SafeValue(info.name, nil)
            resolvedSpellID = resolvedSpellID or overrideSpellID or baseSpellID
        end
    end

    if not name then
        name = GetBarDisplayName(blizzBarChild) or GetBarDisplayName(blizzBarChild.Bar)
    end

    if not resolvedSpellID and name and C_Spell and C_Spell.GetSpellInfo then
        local okSpellInfo, spellInfo = pcall(C_Spell.GetSpellInfo, name)
        if okSpellInfo and spellInfo and spellInfo.spellID then
            baseSpellID = baseSpellID or spellInfo.spellID
            resolvedSpellID = resolvedSpellID or spellInfo.spellID
        end
    end

    if not resolvedSpellID and not name and not cdID then
        return nil
    end

    return {
        spellID = resolvedSpellID,
        baseSpellID = baseSpellID or resolvedSpellID,
        overrideSpellID = overrideSpellID,
        name = name,
        cooldownID = cdID,
    }
end

local function GetTrackedBarOverrideColor(settings, spellData)
    local overrides = settings and settings.colorOverrides
    if type(overrides) ~= "table" or type(spellData) ~= "table" then
        return nil
    end

    local color = spellData.spellID and overrides[spellData.spellID]
    if type(color) == "table" then
        return color
    end

    color = spellData.overrideSpellID and overrides[spellData.overrideSpellID]
    if type(color) == "table" then
        return color
    end

    color = spellData.baseSpellID and overrides[spellData.baseSpellID]
    if type(color) == "table" then
        return color
    end

    color = spellData.cooldownID and overrides[spellData.cooldownID]
    if type(color) == "table" then
        return color
    end

    return nil
end

---------------------------------------------------------------------------
-- CONFIGURE BAR (clean rewrite of ApplyBarStyle for owned frames)
---------------------------------------------------------------------------
function CDMBars.ConfigureBar(bar, settings, overrideWidth)
    if not bar then return end

    local barHeight = settings.barHeight or 25
    local barWidth = overrideWidth or settings.barWidth or 215
    local texture = settings.texture or "Quazii v5"
    local useClassColor = settings.useClassColor
    local barColor = settings.barColor or {0.376, 0.647, 0.980, 1}
    local barOpacity = settings.barOpacity or 1.0
    local borderSize = settings.borderSize or 2
    local bgColor = settings.bgColor or {0, 0, 0, 1}
    local bgOpacity = settings.bgOpacity or 0.5
    local textSize = settings.textSize or 14
    local hideIcon = settings.hideIcon
    local hideText = settings.hideText

    -- Inactive visual settings
    local inactiveMode = settings.inactiveMode or "hide"
    if inactiveMode ~= "always" and inactiveMode ~= "fade" and inactiveMode ~= "hide" then
        inactiveMode = "always"
    end
    local inactiveAlpha = settings.inactiveAlpha or 0.3
    if inactiveAlpha < 0 then inactiveAlpha = 0 end
    if inactiveAlpha > 1 then inactiveAlpha = 1 end
    local desaturateInactive = (settings.desaturateInactive == true)

    -- Vertical bar settings
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local fillDirection = settings.fillDirection or "up"
    local iconPosition = settings.iconPosition or "top"
    local showTextOnVertical = settings.showTextOnVertical or false

    local isActive = bar._active
    local spellData = GetBlizzTrackedBarSpellData(bar._blizzBar)
    local overrideColor = GetTrackedBarOverrideColor(settings, spellData)

    -- For vertical bars: swap width/height conceptually
    local frameWidth, frameHeight
    if isVertical then
        frameWidth = barHeight
        frameHeight = barWidth
    else
        frameWidth = barWidth
        frameHeight = barHeight
    end

    -- Set bar dimensions
    bar:SetSize(frameWidth, frameHeight)

    local statusBar = bar.StatusBar
    if statusBar then
        statusBar:SetSize(frameWidth, frameHeight)
        if statusBar.SetOrientation then
            statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
        end
        if isVertical and statusBar.SetReverseFill then
            statusBar:SetReverseFill(fillDirection == "down")
        end
    end

    -- Icon container
    local iconContainer = bar.IconContainer
    if iconContainer then
        if hideIcon then
            iconContainer:Hide()
            iconContainer:SetAlpha(0)
        else
            iconContainer:Show()
            iconContainer:SetAlpha(1)
            local iconSize = isVertical and frameWidth or frameHeight
            iconContainer:SetSize(iconSize, iconSize)

            -- Apply optional desaturation for inactive entries
            if bar.IconTexture and bar.IconTexture.SetDesaturated then
                bar.IconTexture:SetDesaturated((not isActive) and desaturateInactive and inactiveMode ~= "always")
            end
        end
    end

    -- Position statusBar and icon based on orientation
    if statusBar then
        statusBar:ClearAllPoints()
        if isVertical then
            if hideIcon or not iconContainer then
                statusBar:SetAllPoints(bar)
            else
                iconContainer:ClearAllPoints()
                if iconPosition == "bottom" then
                    iconContainer:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("BOTTOM", iconContainer, "TOP", 0, 0)
                else -- "top" (default)
                    iconContainer:SetPoint("TOP", bar, "TOP", 0, 0)
                    statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
                    statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
                    statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
                    statusBar:SetPoint("TOP", iconContainer, "BOTTOM", 0, 0)
                end
            end
        else
            if hideIcon or not iconContainer then
                statusBar:SetPoint("LEFT", bar, "LEFT", 0, 0)
            else
                iconContainer:ClearAllPoints()
                iconContainer:SetPoint("LEFT", bar, "LEFT", 0, 0)
                statusBar:SetPoint("LEFT", iconContainer, "RIGHT", 0, 0)
            end
            statusBar:SetPoint("TOP", bar, "TOP", 0, 0)
            statusBar:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
            statusBar:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        end
    end

    -- Apply StatusBar texture
    if statusBar and statusBar.SetStatusBarTexture then
        local texturePath = LSM:Fetch("statusbar", texture) or LSM:Fetch("statusbar", "Quazii v5")
        if texturePath then
            statusBar:SetStatusBarTexture(texturePath)
        end
    end

    -- Apply bar color (override > class > custom) with opacity
    if statusBar and statusBar.SetStatusBarColor then
        local c = barColor
        if overrideColor then
            -- Use per-spell override color
            statusBar:SetStatusBarColor(overrideColor[1] or 0.2, overrideColor[2] or 0.8, overrideColor[3] or 0.6, barOpacity)
        elseif useClassColor then
            local _, class = UnitClass("player")
            local safeClass = Helpers.SafeToString(class, nil)
            local color = safeClass and RAID_CLASS_COLORS[safeClass]
            if color then
                statusBar:SetStatusBarColor(color.r, color.g, color.b, barOpacity)
            else
                statusBar:SetStatusBarColor(c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity)
            end
        else
            statusBar:SetStatusBarColor(c[1] or 0.2, c[2] or 0.8, c[3] or 0.6, barOpacity)
        end
    end

    -- Background
    local bg = bar.Background
    if bg then
        local bgR, bgG, bgB = bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0
        bg:SetColorTexture(bgR, bgG, bgB, 1)
        if statusBar then
            bg:ClearAllPoints()
            bg:SetAllPoints(statusBar)
        end
        bg:SetAlpha(bgOpacity)
        bg:Show()
    end

    -- Border (4-edge technique)
    local borderFrame = bar.BorderContainer
    if borderFrame then
        if borderSize > 0 then
            borderFrame:ClearAllPoints()
            borderFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -borderSize, borderSize)
            borderFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", borderSize, -borderSize)

            borderFrame._top:ClearAllPoints()
            borderFrame._top:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._top:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._top:SetHeight(borderSize)

            borderFrame._bottom:ClearAllPoints()
            borderFrame._bottom:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._bottom:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._bottom:SetHeight(borderSize)

            borderFrame._left:ClearAllPoints()
            borderFrame._left:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
            borderFrame._left:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
            borderFrame._left:SetWidth(borderSize)

            borderFrame._right:ClearAllPoints()
            borderFrame._right:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
            borderFrame._right:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
            borderFrame._right:SetWidth(borderSize)

            borderFrame:Show()
        else
            borderFrame:Hide()
        end
    end

    -- Text
    local generalFont = GetGeneralFont()
    local generalOutline = GetGeneralFontOutline()
    local showText = not hideText and (not isVertical or showTextOnVertical)

    if bar.NameText then
        bar.NameText:SetFont(generalFont, textSize, generalOutline)
        bar.NameText:SetAlpha(showText and 1 or 0)
    end
    if bar.DurationText then
        bar.DurationText:SetFont(generalFont, textSize, generalOutline)
        bar.DurationText:SetAlpha(showText and 1 or 0)
    end

    -- Apply frame alpha based on active state
    local targetAlpha = 1
    if not isActive then
        if inactiveMode == "fade" then
            targetAlpha = inactiveAlpha
        elseif inactiveMode == "hide" then
            targetAlpha = 0
        end
    end
    bar:SetAlpha(targetAlpha)
end

---------------------------------------------------------------------------
-- SPELL ID EXTRACTION: Get spellID from a Blizzard bar child via
-- cooldownInfo, cooldownID + C_CooldownViewer API, or name lookup.
---------------------------------------------------------------------------
local function ExtractSpellID(blizzBarChild)
    if not blizzBarChild then return nil end

    -- 1. Direct cooldownInfo (same property icons use)
    local cdInfo = blizzBarChild.cooldownInfo
    if cdInfo then
        local override = SafeToNumber(cdInfo.overrideSpellID, nil)
        if override then return override end
        local spell = SafeToNumber(cdInfo.spellID, nil)
        if spell then return spell end
    end

    -- 2. cooldownID + C_CooldownViewer API
    local cdID = blizzBarChild.cooldownID
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info then
            local override = SafeToNumber(info.overrideSpellID, nil)
            if override then return override end
            local spell = SafeToNumber(info.spellID, nil)
            if spell then return spell end
        end
    end

    -- 3. Name-based lookup: read name from bar FontStrings, look up spellID
    local function GetBarName(frame)
        if not frame or not frame.GetRegions then return nil end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region:GetObjectType() == "FontString" then
                local okT, text = pcall(region.GetText, region)
                if okT and type(text) == "string" and text ~= "" then
                    local justify = region:GetJustifyH()
                    if justify ~= "RIGHT" then return text end
                end
            end
        end
        return nil
    end
    local name = GetBarName(blizzBarChild) or GetBarName(blizzBarChild.Bar)
    if name and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info and info.spellID then
            return info.spellID
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- ACTIVE STATE: Check if a Blizzard bar child is active.
-- Blizzard calls Show/Hide on bar children even when the viewer is alpha=0,
-- so IsShown() is a reliable signal for active state.
---------------------------------------------------------------------------
local function CheckBarActive(blizzBarChild)
    if not blizzBarChild then return false end
    local ok, shown = pcall(blizzBarChild.IsShown, blizzBarChild)
    return ok and shown or false
end

-- When an owned bar is rebuilt from the pool, the Blizzard child may already
-- be hooked and actively updating, but the new owned bar starts with blank
-- text. Resync the current name/duration strings immediately.
local function ResyncBlizzBarTexts(ownedBar, blizzBarChild, blizzStatusBar)
    if not ownedBar or not blizzBarChild then return end

    local knownNameFS = {}
    local knownDurationFS = {}
    local frames = { blizzBarChild }
    if blizzStatusBar then
        frames[#frames + 1] = blizzStatusBar
    end
    if blizzBarChild.GetChildren then
        for _, subChild in ipairs({ blizzBarChild:GetChildren() }) do
            frames[#frames + 1] = subChild
        end
    end

    local function DiscoverNamedFontStrings(frame)
        if not frame then return end
        if frame.Name and type(frame.Name) == "table"
            and frame.Name.GetObjectType and frame.Name:GetObjectType() == "FontString" then
            knownNameFS[frame.Name] = true
        end
        if frame.Duration and type(frame.Duration) == "table"
            and frame.Duration.GetObjectType and frame.Duration:GetObjectType() == "FontString" then
            knownDurationFS[frame.Duration] = true
        end
    end

    for _, frame in ipairs(frames) do
        DiscoverNamedFontStrings(frame)
    end

    local function ForwardCurrentText(fs, text)
        if knownDurationFS[fs] then
            pcall(ownedBar.DurationText.SetText, ownedBar.DurationText, text or "")
        elseif knownNameFS[fs] then
            pcall(ownedBar.NameText.SetText, ownedBar.NameText, text or "")
        else
            local justify = fs:GetJustifyH()
            if justify == "RIGHT" then
                pcall(ownedBar.DurationText.SetText, ownedBar.DurationText, text or "")
            else
                pcall(ownedBar.NameText.SetText, ownedBar.NameText, text or "")
            end
        end
    end

    for _, frame in ipairs(frames) do
        if frame and frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region and region:GetObjectType() == "FontString" then
                    local okText, text = pcall(region.GetText, region)
                    if okText then
                        ForwardCurrentText(region, text)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- MIRROR BLIZZARD BAR DATA → OWNED BAR
-- Uses hooksecurefunc to forward data from hidden Blizzard bar children.
-- C-side StatusBar methods handle secret values natively.
---------------------------------------------------------------------------
local function MirrorBlizzBar(ownedBar, blizzBarChild)
    if not blizzBarChild then return end
    if hookedBars[blizzBarChild] then
        -- Already hooked — just update the mapping and resync initial state
        mirrorMap[blizzBarChild] = ownedBar
        -- Resync current state since the owned bar is new (from pool rebuild)
        local blizzStatusBar = blizzBarChild.Bar
        if blizzStatusBar then
            local ok1, minVal, maxVal = pcall(blizzStatusBar.GetMinMaxValues, blizzStatusBar)
            if ok1 then
                pcall(ownedBar.StatusBar.SetMinMaxValues, ownedBar.StatusBar, minVal, maxVal)
            end
            local ok2, val = pcall(blizzStatusBar.GetValue, blizzStatusBar)
            if ok2 then
                pcall(ownedBar.StatusBar.SetValue, ownedBar.StatusBar, val)
            end
        end
        -- Resync icon texture
        local blizzIcon = blizzBarChild.Icon
        local blizzIconTex = blizzIcon and (blizzIcon.Icon or blizzIcon.icon or blizzIcon.texture)
        if blizzIconTex then
            local ok, currentTex = pcall(blizzIconTex.GetTexture, blizzIconTex)
            if ok and currentTex then
                pcall(ownedBar.IconTexture.SetTexture, ownedBar.IconTexture, currentTex)
            end
        end
        ResyncBlizzBarTexts(ownedBar, blizzBarChild, blizzStatusBar)
        return
    end
    hookedBars[blizzBarChild] = true
    mirrorMap[blizzBarChild] = ownedBar

    -- Active state is tracked via CheckBarActive(IsShown()) in BuildBars,
    -- called on every Refresh cycle. No Show/Hide hooks on Blizzard frames
    -- needed — avoids tainting Blizzard's secure execution context during
    -- Edit Mode frame iteration.

    -- Hook StatusBar value/range forwarding
    local blizzStatusBar = blizzBarChild.Bar
    if blizzStatusBar then
        -- Mirror SetValue: forward progress to owned StatusBar
        hooksecurefunc(blizzStatusBar, "SetValue", function(self, value)
            local target = mirrorMap[blizzBarChild]
            if not target then return end
            -- Forward value to owned StatusBar (C-side handles secret values)
            pcall(target.StatusBar.SetValue, target.StatusBar, value)
        end)

        -- Mirror SetMinMaxValues
        hooksecurefunc(blizzStatusBar, "SetMinMaxValues", function(self, minVal, maxVal)
            local target = mirrorMap[blizzBarChild]
            if not target then return end
            pcall(target.StatusBar.SetMinMaxValues, target.StatusBar, minVal, maxVal)
        end)
    end

    -- Hook icon texture (SetTexture and SetAtlas)
    local blizzIcon = blizzBarChild.Icon
    local blizzIconTex = blizzIcon and (blizzIcon.Icon or blizzIcon.icon or blizzIcon.texture)
    if blizzIconTex then
        if blizzIconTex.SetTexture then
            hooksecurefunc(blizzIconTex, "SetTexture", function(self, tex)
                local target = mirrorMap[blizzBarChild]
                if not target or not target.IconTexture then return end
                pcall(target.IconTexture.SetTexture, target.IconTexture, tex)
            end)
        end
        if blizzIconTex.SetAtlas then
            hooksecurefunc(blizzIconTex, "SetAtlas", function(self, atlas)
                local target = mirrorMap[blizzBarChild]
                if not target or not target.IconTexture then return end
                pcall(target.IconTexture.SetAtlas, target.IconTexture, atlas)
            end)
        end
        -- Initial texture copy
        local ok, currentTex = pcall(blizzIconTex.GetTexture, blizzIconTex)
        if ok and currentTex then
            pcall(ownedBar.IconTexture.SetTexture, ownedBar.IconTexture, currentTex)
        end
    end

    -- Hook text: Blizzard bar children have .Name and .Duration FontString
    -- properties on sub-children. Both FontStrings can be LEFT-justified so
    -- we identify them by reference identity, not justify direction.
    local hookedFontStrings = {}  -- track to avoid double-hooking
    local knownNameFS = {}        -- FontStrings identified as spell name
    local knownDurationFS = {}    -- FontStrings identified as duration

    -- Discover .Name and .Duration FontString references from all frames
    local function DiscoverNamedFontStrings(frame)
        if not frame then return end
        if frame.Name and type(frame.Name) == "table"
            and frame.Name.GetObjectType and frame.Name:GetObjectType() == "FontString" then
            knownNameFS[frame.Name] = true
        end
        if frame.Duration and type(frame.Duration) == "table"
            and frame.Duration.GetObjectType and frame.Duration:GetObjectType() == "FontString" then
            knownDurationFS[frame.Duration] = true
        end
    end

    -- Discover from bar child, .Bar, and all sub-children first
    DiscoverNamedFontStrings(blizzBarChild)
    if blizzStatusBar then
        DiscoverNamedFontStrings(blizzStatusBar)
    end
    if blizzBarChild.GetChildren then
        for _, subChild in ipairs({ blizzBarChild:GetChildren() }) do
            DiscoverNamedFontStrings(subChild)
        end
    end

    local function ForwardText(fs, text)
        local target = mirrorMap[blizzBarChild]
        if not target then return end
        if knownDurationFS[fs] then
            pcall(target.DurationText.SetText, target.DurationText, text or "")
        elseif knownNameFS[fs] then
            pcall(target.NameText.SetText, target.NameText, text or "")
        else
            -- Fallback: use justify for unknown FontStrings
            local justify = fs:GetJustifyH()
            if justify == "RIGHT" then
                pcall(target.DurationText.SetText, target.DurationText, text or "")
            else
                pcall(target.NameText.SetText, target.NameText, text or "")
            end
        end
    end

    local function HookFontString(fs)
        if hookedFontStrings[fs] then return end
        hookedFontStrings[fs] = true

        hooksecurefunc(fs, "SetText", function(self, text)
            ForwardText(self, text)
        end)
        if fs.SetFormattedText then
            hooksecurefunc(fs, "SetFormattedText", function(self, fmt, ...)
                local okT, finalText = pcall(self.GetText, self)
                if okT then
                    ForwardText(self, finalText)
                end
            end)
        end
        -- Initial text copy
        local ok, text = pcall(fs.GetText, fs)
        if ok and text then
            ForwardText(fs, text)
        end
    end

    -- Hook all FontString regions on a frame
    local function HookFrameRegions(frame)
        if not frame or not frame.GetRegions then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region:GetObjectType() == "FontString" then
                HookFontString(region)
            end
        end
    end

    -- Hook bar child, .Bar, and all sub-children
    HookFrameRegions(blizzBarChild)
    if blizzStatusBar then
        HookFrameRegions(blizzStatusBar)
    end
    if blizzBarChild.GetChildren then
        for _, subChild in ipairs({ blizzBarChild:GetChildren() }) do
            HookFrameRegions(subChild)
        end
    end

    -- Initial value sync (C-side forwarding, handles secret values)
    if blizzStatusBar then
        local ok1, minVal, maxVal = pcall(blizzStatusBar.GetMinMaxValues, blizzStatusBar)
        if ok1 then
            pcall(ownedBar.StatusBar.SetMinMaxValues, ownedBar.StatusBar, minVal, maxVal)
        end
        local ok2, val = pcall(blizzStatusBar.GetValue, blizzStatusBar)
        if ok2 then
            pcall(ownedBar.StatusBar.SetValue, ownedBar.StatusBar, val)
        end
    end
end

---------------------------------------------------------------------------
-- POOL MANAGEMENT
---------------------------------------------------------------------------
local function AcquireBar(parent)
    local bar
    if #recyclePool > 0 then
        bar = table.remove(recyclePool)
        bar:SetParent(parent)
    else
        bar = CreateBar(parent)
    end
    bar:Show()
    barPool[#barPool + 1] = bar
    return bar
end

local function ReleaseBar(bar)
    bar:Hide()
    bar:ClearAllPoints()
    bar._spellEntry = nil
    bar._blizzBar = nil
    bar._spellID = nil
    bar._active = false
    bar._cSideFill = nil
    bar.NameText:SetText("")
    bar.DurationText:SetText("")
    bar.IconTexture:SetTexture(nil)
    bar.StatusBar:SetValue(0)

    if #recyclePool < MAX_RECYCLE_POOL_SIZE then
        recyclePool[#recyclePool + 1] = bar
    end
end

function CDMBars:ClearPool()
    for i = #barPool, 1, -1 do
        ReleaseBar(barPool[i])
        barPool[i] = nil
    end
end

function CDMBars:GetActiveBars()
    return barPool
end

---------------------------------------------------------------------------
-- BUILD BARS: Scan Blizzard BuffBarCooldownViewer children, create owned
-- bars for each, and set up hooks for data mirroring.
---------------------------------------------------------------------------
function CDMBars:BuildBars(container)
    if not container then return end

    local blizzViewer = _G["BuffBarCooldownViewer"]
    if not blizzViewer then return end

    -- Collect Blizzard bar children
    local blizzBars = {}
    local sel = blizzViewer.Selection
    local okc, children = pcall(function()
        return { blizzViewer:GetChildren() }
    end)
    if okc and children then
        for _, child in ipairs(children) do
            if child and child ~= sel and child:IsObjectType("Frame") then
                -- Bar children have a .Bar StatusBar + cooldownID/layoutIndex
                -- Skip Blizzard's empty pool frames (no cooldownID and no layoutIndex)
                if child.Bar and child.Bar.IsObjectType and child.Bar:IsObjectType("StatusBar")
                    and (child.cooldownID or child.layoutIndex) then
                    blizzBars[#blizzBars + 1] = child
                end
            end
        end
    end

    -- Sort by layoutIndex
    table.sort(blizzBars, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)

    -- Check if we need to rebuild: compare blizzard bar count with current pool
    local needsRebuild = (#blizzBars ~= #barPool)
    if not needsRebuild then
        for i, bar in ipairs(barPool) do
            if bar._blizzBar ~= blizzBars[i] then
                needsRebuild = true
                break
            end
        end
    end

    -- Force rebuild if bars are parented to wrong frame (e.g. initial build
    -- happened before owned container existed)
    if not needsRebuild and #barPool > 0 then
        local firstParent = barPool[1]:GetParent()
        if firstParent ~= container then
            needsRebuild = true
        end
    end

    -- No rebuild needed — just update active state from Blizzard IsShown
    if not needsRebuild then
        for _, bar in ipairs(barPool) do
            if bar._blizzBar then
                bar._active = CheckBarActive(bar._blizzBar)
            end
        end
        return
    end

    -- Clear existing pool
    self:ClearPool()

    -- Create owned bars for each Blizzard bar child
    for _, blizzChild in ipairs(blizzBars) do
        local bar = AcquireBar(container)
        bar._blizzBar = blizzChild

        -- Extract spellID for reliable active state detection
        bar._spellID = ExtractSpellID(blizzChild)

        -- Check active state from Blizzard IsShown (reliable even with alpha=0 viewer)
        bar._active = CheckBarActive(blizzChild)

        -- Set up data mirroring hooks
        MirrorBlizzBar(bar, blizzChild)
    end
end

---------------------------------------------------------------------------
-- FIND BLIZZARD BAR CHILD: Scan BuffBarCooldownViewer for a child matching
-- the given spell ID.  Returns the Blizzard bar child frame or nil.
---------------------------------------------------------------------------
local function FindBlizzBarChild(spellID, entry)
    if not spellID then return nil end
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then return nil end
    local sel = viewer.Selection
    local okc, children = pcall(function() return { viewer:GetChildren() } end)
    if not okc or not children then return nil end

    local idsToMatch = { [spellID] = true }
    if entry then
        if entry.spellID then idsToMatch[entry.spellID] = true end
        if entry.id then idsToMatch[entry.id] = true end
    end

    for _, child in ipairs(children) do
        if child and child ~= sel and child.Bar then
            local ci = child.cooldownInfo
            if ci then
                local sid = Helpers.SafeValue(ci.overrideSpellID, nil)
                local sid2 = Helpers.SafeValue(ci.spellID, nil)
                if (sid and idsToMatch[sid]) or (sid2 and idsToMatch[sid2]) then
                    return child
                end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- BUILD BARS FROM OWNED SPELL LIST: Create bars from owned spell data
-- instead of scanning Blizzard BuffBarCooldownViewer children.
-- Uses C_UnitAuras.GetPlayerAuraBySpellID for aura-driven bar updates.
---------------------------------------------------------------------------
function CDMBars:BuildBarsFromOwned(container, spellList)
    if not container then return end
    if not spellList or #spellList == 0 then
        -- No owned spells — clear pool and return
        self:ClearPool()
        return
    end

    -- Check if we need to rebuild: compare spell count + IDs with current pool
    local needsRebuild = (#spellList ~= #barPool)
    if not needsRebuild then
        for i, bar in ipairs(barPool) do
            local entry = spellList[i]
            if not entry or bar._spellID ~= (entry.overrideSpellID or entry.spellID or entry.id) then
                needsRebuild = true
                break
            end
        end
    end

    -- Force rebuild if bars are parented to wrong frame
    if not needsRebuild and #barPool > 0 then
        local firstParent = barPool[1]:GetParent()
        if firstParent ~= container then
            needsRebuild = true
        end
    end

    -- No rebuild needed — just update active state from aura data
    if not needsRebuild then
        for _, bar in ipairs(barPool) do
            if bar._isOwnedBar and bar._spellID then
                self:UpdateOwnedBarAura(bar)
            elseif bar._blizzBar then
                bar._active = CheckBarActive(bar._blizzBar)
            end
        end
        return
    end

    -- Clear existing pool
    self:ClearPool()

    -- Create owned bars for each spell entry
    for _, entry in ipairs(spellList) do
        local bar = AcquireBar(container)
        bar._spellEntry = entry
        bar._isOwnedBar = true

        local spellID = entry.overrideSpellID or entry.spellID or entry.id
        bar._spellID = spellID

        -- Find matching BuffBarCooldownViewer child and set up direct mirror.
        local blzBarChild = FindBlizzBarChild(spellID, entry)
        bar._blizzBar = blzBarChild
        if blzBarChild then
            MirrorBlizzBar(bar, blzBarChild)
        end

        -- Find matching buff icon viewer child for DurationObject hook cache.
        -- Same spell ID may exist in both cooldown and buff viewers — prefer
        -- buff viewer children (they have DurationObjects for aura timing).
        -- Find the buff viewer child (not cooldown viewer) for aura DurationObject.
        -- child.viewerFrame identifies which viewer it belongs to.
        local buffViewer = _G["BuffIconCooldownViewer"]
        local childMap = ns.CDMSpellData and ns.CDMSpellData._spellIDToChild
        if childMap and buffViewer then
            local candidates = childMap[spellID]
                or (entry.spellID and childMap[entry.spellID])
                or (entry.id and childMap[entry.id])
            if candidates then
                for _, ch in ipairs(candidates) do
                    if ch.viewerFrame == buffViewer then
                        bar._blizzIconChild = ch
                        break
                    end
                end
            end
        end
        -- Set initial texture
        if bar.IconTexture and spellID then
            local texID
            if entry.type == "item" or entry.type == "slot" then
                if entry.type == "slot" then
                    texID = GetInventoryItemTexture("player", entry.id)
                else
                    local _, _, _, _, icon = C_Item.GetItemInfoInstant(spellID)
                    texID = icon
                end
            elseif entry.type == "spell" then
                -- Use overrideSpellID (resolved via GetOverrideSpell / correction
                -- maps) so the icon matches talent replacements and spec overrides.
                local iconSid = entry.overrideSpellID or entry.id or spellID
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconSid)
                texID = info and info.iconID
            end
            if texID then
                pcall(bar.IconTexture.SetTexture, bar.IconTexture, texID)
            end
        end

        -- Set initial name text
        if bar.NameText and entry.name then
            bar.NameText:SetText(entry.name)
        end

        -- Update active state from aura data
        self:UpdateOwnedBarAura(bar)
    end
end

---------------------------------------------------------------------------
-- UPDATE OWNED BAR AURA: Delegates to shared CDMSpellData:ResolveAuraState()
-- and applies results to bar StatusBar fill / duration text / stacks.
---------------------------------------------------------------------------
function CDMBars:UpdateOwnedBarAura(bar)
    if not bar or not bar._spellID then return end
    local spellID = bar._spellID
    local entry = bar._spellEntry
    if not ns.CDMSpellData then return end

    local Helpers = ns.Helpers

    local p = bar._auraParams or {}
    bar._auraParams = p
    p.spellID = spellID
    p.entrySpellID = entry and entry.spellID
    p.entryID = entry and entry.id
    p.entryName = entry and entry.name
    p.viewerType = entry and entry.viewerType
    p.blizzChild = bar._blizzIconChild
    p.blizzBarChild = bar._blizzBar

    local r = ns.CDMSpellData:ResolveAuraState(p)
    if r.blizzChild then bar._blizzIconChild = r.blizzChild end

    if r.isActive then
        bar._active = true
        bar._auraDataUnit = r.auraUnit

        -- Cache readable duration/expiration from OOC auraData (for OnUpdate timer text)
        if r.auraData then
            local rawDur = r.auraData.duration
            if rawDur and not Helpers.IsSecretValue(rawDur) and rawDur > 0 then
                bar._totalDuration = rawDur
            end
            local rawExp = r.auraData.expirationTime
            if rawExp and not Helpers.IsSecretValue(rawExp) and rawExp > 0 then
                bar._expirationTime = rawExp
            end
        end

        -- Bar fill via DurationObject
        local durObj = r.durObj or r.hookDurObj
        if durObj then
            bar._durObj = durObj
            if bar.StatusBar then
                pcall(bar.StatusBar.SetMinMaxValues, bar.StatusBar, 0, 1)
                if bar.StatusBar.SetTimerDuration then
                    pcall(bar.StatusBar.SetTimerDuration, bar.StatusBar, durObj, nil, 1)
                    bar._cSideFill = true
                end
            end
        end

        -- Stacks (appended to name text)
        if bar.NameText then
            local name = (entry and entry.name) or ""
            local stacks = r.stacks
                and C_StringUtil.WrapString(C_StringUtil.TruncateWhenZero(r.stacks), " (", ")")
                or ""
            pcall(bar.NameText.SetText, bar.NameText, name .. stacks)
        end
    else
        bar._active = false
        bar._durObj = nil
        bar._cSideFill = nil
        bar._totalDuration = nil
        bar._expirationTime = nil
        if not InCombatLockdown() then
            bar._resolvedAuraID = nil
        end
        if bar.StatusBar then
            pcall(bar.StatusBar.SetValue, bar.StatusBar, 0)
        end
        if bar.DurationText then
            bar.DurationText:SetText("")
        end
    end
end

---------------------------------------------------------------------------
-- FORCE ALL ACTIVE: For Edit Mode, force all bars with names visible
-- so the mover overlay shows the full expected area.
---------------------------------------------------------------------------
function CDMBars:ForceAllActive()
    for _, bar in ipairs(barPool) do
        local name = bar.NameText and bar.NameText:GetText()
        if name and name ~= "" then
            bar._active = true
        end
    end
end

---------------------------------------------------------------------------
-- LAYOUT BARS: Pure math positioning, no Blizzard frame interaction.
-- Stacks bars vertically (default) or horizontally (vertical orientation).
---------------------------------------------------------------------------
function CDMBars:LayoutBars(container, settings)
    if not container then return end
    if not settings then return end

    local barHeight = settings.barHeight or 25
    local barWidth = settings.barWidth or 215

    local count = #barPool

    -- Even with 0 bars, set a minimum container size so the Edit Mode
    -- overlay is draggable and visible (not 1x1).
    if count == 0 then
        local orientation = settings.orientation or "horizontal"
        local w, h
        if orientation == "vertical" then
            w, h = barHeight, barWidth
        else
            w, h = barWidth, barHeight
        end
        container:SetSize(w, h)
        if _G.QUI_SetCDMViewerBounds then
            _G.QUI_SetCDMViewerBounds(container, w, h)
        end
        return
    end

    local stylingEnabled = settings.enabled
    local spacing = settings.spacing or 2
    local growFromBottom = (settings.growUp ~= false)
    local orientation = settings.orientation or "horizontal"
    local isVertical = (orientation == "vertical")
    local inactiveMode = settings.inactiveMode or "hide"
    local reserveSlotWhenInactive = (settings.reserveSlotWhenInactive == true)

    -- For vertical bars, swap dimensions
    local effectiveBarWidth, effectiveBarHeight
    if isVertical then
        effectiveBarWidth = barHeight
        effectiveBarHeight = barWidth
    else
        effectiveBarWidth = barWidth
        effectiveBarHeight = barHeight
    end

    -- Apply HUD layer priority
    local hudLayering = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.hudLayering
    local layerPriority = hudLayering and hudLayering.buffBar or 5
    local frameLevel = 200
    if QUICore and QUICore.GetHUDFrameLevel then
        frameLevel = QUICore:GetHUDFrameLevel(layerPriority)
    end
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(frameLevel)

    -- Configure and position each bar
    local editModeActive = Helpers.IsEditModeActive()
        or (_G.QUI_IsCDMEditModeActive and _G.QUI_IsCDMEditModeActive())
    local visibleIndex = 0
    for _, bar in ipairs(barPool) do
        -- Apply styling
        CDMBars.ConfigureBar(bar, settings, barWidth)

        -- Apply strata/level
        bar:SetFrameStrata("MEDIUM")
        bar:SetFrameLevel(frameLevel)
        if bar.StatusBar then
            bar.StatusBar:SetFrameStrata("MEDIUM")
            bar.StatusBar:SetFrameLevel(frameLevel + 1)
        end
        if bar.TextOverlay then
            bar.TextOverlay:SetFrameStrata("MEDIUM")
            bar.TextOverlay:SetFrameLevel(frameLevel + 3)
        end
        if bar.IconContainer then
            bar.IconContainer:SetFrameStrata("MEDIUM")
            bar.IconContainer:SetFrameLevel(frameLevel + 1)
        end

        -- In edit/layout mode, force bar active with a visible fill for previewing
        if editModeActive then
            bar._active = true
            if bar.StatusBar then
                pcall(bar.StatusBar.SetMinMaxValues, bar.StatusBar, 0, 1)
                pcall(bar.StatusBar.SetValue, bar.StatusBar, 0.65)
            end
            if bar.DurationText then
                bar.DurationText:SetText("0:32")
            end
        end

        -- Determine visibility using display mode for owned bars
        local shouldShow = true

        -- In edit/layout mode, force all bars visible (ignore visibility settings)
        if not editModeActive then
            local displayMode = settings.iconDisplayMode or "always"
            local effectiveDisplayMode = displayMode
            if effectiveDisplayMode == "combat" then
                effectiveDisplayMode = InCombatLockdown() and "always" or "active"
            end

            if effectiveDisplayMode == "active" then
                -- Active-only: only show bars with active auras/cooldowns
                if not bar._active then
                    shouldShow = false
                end
            elseif effectiveDisplayMode == "always" then
                -- Always mode: use existing inactiveMode for inactive bars
                if not bar._active then
                    if inactiveMode == "hide" and not reserveSlotWhenInactive then
                        shouldShow = false
                    end
                end
            else
                -- Fallback to existing behavior
                if not bar._active then
                    if inactiveMode == "hide" and not reserveSlotWhenInactive then
                        shouldShow = false
                    end
                end
            end
        end

        if shouldShow then
            bar:ClearAllPoints()
            local offsetIndex = visibleIndex

            if isVertical then
                local x
                if growFromBottom then
                    x = QUICore:PixelRound(offsetIndex * (effectiveBarWidth + spacing))
                    bar:SetPoint("LEFT", container, "LEFT", x, 0)
                else
                    x = QUICore:PixelRound(-offsetIndex * (effectiveBarWidth + spacing))
                    bar:SetPoint("RIGHT", container, "RIGHT", x, 0)
                end
            else
                local y
                if growFromBottom then
                    y = QUICore:PixelRound(offsetIndex * (effectiveBarHeight + spacing))
                    bar:SetPoint("BOTTOM", container, "BOTTOM", 0, y)
                else
                    y = QUICore:PixelRound(-offsetIndex * (effectiveBarHeight + spacing))
                    bar:SetPoint("TOP", container, "TOP", 0, y)
                end
            end

            bar:Show()
            visibleIndex = visibleIndex + 1
        else
            bar:Hide()
        end
    end

    -- Set container size from calculated bounds
    local totalW, totalH
    if visibleIndex == 0 then
        -- All bars hidden by inactiveMode — use settings dimensions so
        -- the container (and Edit Mode overlay) stays a reasonable size.
        totalW = effectiveBarWidth
        totalH = effectiveBarHeight
    elseif isVertical then
        totalW = (visibleIndex * effectiveBarWidth) + ((visibleIndex - 1) * spacing)
        totalH = effectiveBarHeight
    else
        totalW = effectiveBarWidth
        totalH = (visibleIndex * effectiveBarHeight) + ((visibleIndex - 1) * spacing)
    end
    totalW = QUICore:PixelRound(totalW)
    totalH = QUICore:PixelRound(totalH)
    container:SetSize(totalW, totalH)

    -- Write calculated dimensions to viewer state for proxy sizing
    if _G.QUI_SetCDMViewerBounds then
        _G.QUI_SetCDMViewerBounds(container, totalW, totalH)
    end
end

---------------------------------------------------------------------------
-- REFRESH: Rebuild + re-layout (called from buffbar.lua)
---------------------------------------------------------------------------
function CDMBars:Refresh(container, settings, overrideWidth, containerKey)
    if not container then return end
    if not settings then return end

    -- Update barWidth if autoWidth provides an override
    if overrideWidth then
        settings = setmetatable({ barWidth = overrideWidth }, { __index = settings })
    end

    -- Store refs so the periodic ticker can re-layout after _active changes
    _lastContainer = container
    _lastSettings = settings

    -- Route through owned path if ownedSpells are snapshotted
    if settings.ownedSpells ~= nil and ns.CDMSpellData then
        -- Phase G: use provided containerKey or fall back to "trackedBar"
        local spellList = ns.CDMSpellData:GetSpellList(containerKey or "trackedBar")
        self:BuildBarsFromOwned(container, spellList)
    else
        self:BuildBars(container)
    end
    self:LayoutBars(container, settings)
end

---------------------------------------------------------------------------
-- UPDATE ALL OWNED BARS: Periodic aura poll for owned bars.
-- Called from the CDMIcons update ticker (piggybacks on existing 0.5s tick).
---------------------------------------------------------------------------
function CDMBars:UpdateOwnedBars()
    local anyChanged = false
    local anyActive = false
    for _, bar in ipairs(barPool) do
        if bar._isOwnedBar and bar._spellID then
            local wasPreviouslyActive = bar._active
            self:UpdateOwnedBarAura(bar)
            if bar._active ~= wasPreviouslyActive then
                anyChanged = true
            end
            if bar._active then anyActive = true end
        end
    end
    -- Ensure the bar timer is running when any bar is active.
    if anyActive and not barTimerGroup:IsPlaying() then
        barTimerGroup:Play()
    end
    -- Re-layout when any bar's active state changed so Show/Hide updates
    if anyChanged and _lastContainer and _lastSettings then
        self:LayoutBars(_lastContainer, _lastSettings)
    end
end

---------------------------------------------------------------------------
-- OWNED BAR TIMER: 100ms AnimationGroup loop for duration text + bar fill.
-- Uses DurationObject:GetRemainingDuration() for remaining time and
-- bar._totalDuration (cached from auraData OOC) for the fill ratio.
-- MirrorBlizzBar hooks handle fill when a Blizzard bar child exists;
-- this timer handles owned bars that have no Blizzard bar child,
-- or supplements the mirror during combat when hooks may lag.
-- AnimationGroup:SetLooping("REPEAT") is C-side driven — no Lua elapsed
-- accumulator overhead compared to raw OnUpdate.
---------------------------------------------------------------------------
barTimerGroup:SetScript("OnLoop", function()
    local Helpers = ns.Helpers
    local anyActive = false
    local anyDeactivated = false
    for _, bar in ipairs(barPool) do
        if bar._isOwnedBar and bar._active and bar:IsShown() then
            local durObj = bar._durObj
            if durObj and durObj.GetRemainingDuration then
                anyActive = true
                local rok, remaining = pcall(durObj.GetRemainingDuration, durObj)
                local isSecret = remaining and Helpers.IsSecretValue(remaining)
                if rok and remaining and not isSecret and remaining > 0 then
                    -- OOC: readable remaining — update text in Lua
                    if bar.DurationText then
                        if remaining >= 60 then
                            local text = string_format("%.0fm", remaining / 60)
                            if text ~= bar._lastDurationText then
                                bar._lastDurationText = text
                                bar.DurationText:SetText(text)
                            end
                        else
                            local text = string_format("%.1f", remaining)
                            if text ~= bar._lastDurationText then
                                bar._lastDurationText = text
                                bar.DurationText:SetText(text)
                            end
                        end
                    end
                    -- Update bar fill ONLY if C-side SetTimerDuration isn't driving it.
                    if not bar._cSideFill then
                        local total = bar._totalDuration
                        if (not total or total <= 0) and remaining > 1 then
                            bar._totalDuration = remaining
                            total = remaining
                        end
                        if total and total > 0 and bar.StatusBar then
                            local fill = remaining / total
                            if fill > 1 then fill = 1 end
                            pcall(bar.StatusBar.SetMinMaxValues, bar.StatusBar, 0, 1)
                            pcall(bar.StatusBar.SetValue, bar.StatusBar, fill)
                        end
                    end
                elseif isSecret then
                    -- Combat: C-side SetTimerDuration drives bar fill.
                    -- Pass secret remaining to C-side SetFormattedText for text.
                    -- Expiry detection relies on the child Hide hook in
                    -- cdm_spelldata.lua clearing the durObj cache — the next
                    -- UpdateOwnedBars cycle will see no active aura.
                    anyActive = true
                    if bar.DurationText then
                        pcall(bar.DurationText.SetFormattedText, bar.DurationText, "%.1f", remaining)
                    end
                else
                    -- OOC expired: remaining is nil or 0
                    bar._active = false
                    anyDeactivated = true
                    bar._durObj = nil
                    bar._cSideFill = nil
                    bar._lastDurationText = nil
                    if bar.DurationText then
                        bar.DurationText:SetText("")
                    end
                    if bar.StatusBar then
                        pcall(bar.StatusBar.SetValue, bar.StatusBar, 0)
                    end
                end
            end
        end
    end
    -- Re-layout ONLY when a bar actually deactivated during THIS tick.
    -- The old scan checked all bars for `not _active and IsShown()`, which
    -- matched intentionally-shown inactive bars (inactiveMode "always"/"fade")
    -- and triggered a full LayoutBars (with ConfigureBar re-applying textures,
    -- points, alpha on every bar) every 100ms — causing visible flickering.
    if anyDeactivated and _lastContainer and _lastSettings then
        CDMBars:LayoutBars(_lastContainer, _lastSettings)
    end
    -- Stop the animation when no bars need ticking to avoid idle CPU cost.
    if not anyActive then
        barTimerGroup:Stop()
    end
end)

