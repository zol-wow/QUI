---------------------------------------------------------------------------
-- QUI XP Tracker
-- Displays experience progress, rested XP, XP/hour rate, time-to-level
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUI = ns.QUI or {}
ns.QUI = QUI
local Helpers = ns.Helpers
local UIKit = ns.UIKit

---------------------------------------------------------------------------
-- State tracking
---------------------------------------------------------------------------
local XPTrackerState = {
    frame = nil,
    isPreviewMode = false,
    ticker = nil,
    tickCount = 0,
    startupScheduled = false,
    -- Session tracking
    sessionStartTime = 0,
    sessionStartXP = 0,
    sessionStartLevel = 0,
    totalSessionXP = 0,       -- Monotonic across level-ups
    levelStartTime = 0,
    lastKnownXP = 0,
    lastKnownLevel = 0,
    -- Ring buffer for XP/hour (10-min window, samples every 5 ticks = 10s)
    samples = {},             -- {time, totalXP} pairs
    maxSampleAge = 600,       -- 10 minutes in seconds
    sessionInitialized = false,
}

---------------------------------------------------------------------------
-- Get settings from database
---------------------------------------------------------------------------
local function GetSettings()
    return Helpers.GetModuleDB("xpTracker")
end

---------------------------------------------------------------------------
-- Format helpers
---------------------------------------------------------------------------
local function FormatXP(value)
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fK", value / 1000)
    end
    return tostring(math.floor(value))
end

local function FormatDuration(seconds)
    if seconds < 0 then seconds = 0 end
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, mins)
    end
    return string.format("%dm %02ds", mins, secs)
end

local function FormatPercent(value)
    if value >= 100 then
        return "100%"
    end
    return string.format("%.1f%%", value)
end

local function RoundNearest(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

---------------------------------------------------------------------------
-- XP Rate calculation (ring buffer)
---------------------------------------------------------------------------
local function RecordSample()
    local now = GetTime()
    local samples = XPTrackerState.samples

    -- Prune old samples beyond the window
    local cutoff = now - XPTrackerState.maxSampleAge
    local firstValid = #samples + 1
    for i = 1, #samples do
        if samples[i][1] >= cutoff then
            firstValid = i
            break
        end
    end
    if firstValid > 1 then
        local newSamples = {}
        for i = firstValid, #samples do
            newSamples[#newSamples + 1] = samples[i]
        end
        XPTrackerState.samples = newSamples
        samples = XPTrackerState.samples
    end

    -- Add new sample
    samples[#samples + 1] = {now, XPTrackerState.totalSessionXP}
end

local function GetXPPerHour()
    local samples = XPTrackerState.samples
    if #samples < 2 then return 0 end

    local oldest = samples[1]
    local newest = samples[#samples]
    local timeDelta = newest[1] - oldest[1]
    if timeDelta < 1 then return 0 end

    local xpDelta = newest[2] - oldest[2]
    return (xpDelta / timeDelta) * 3600
end

---------------------------------------------------------------------------
-- Text visibility (for hide-until-hover mode)
---------------------------------------------------------------------------
local UpdateDetailsDirection

local function SetTextVisible(frame, visible)
    if not frame or not frame.detailsFrame then return end
    local detailsHeight = frame.detailsFrame:GetHeight() or 0
    if visible and detailsHeight > 0 then
        UpdateDetailsDirection(frame)
        frame.detailsFrame:Show()
    else
        frame.detailsFrame:Hide()
    end
end

UpdateDetailsDirection = function(frame)
    if not frame or not frame.detailsFrame then return end

    local settings = GetSettings()
    local detailsFrame = frame.detailsFrame
    local detailsHeight = detailsFrame:GetHeight() or 0
    if detailsHeight <= 0 then return end

    local growDown
    local direction = settings and settings.detailsGrowDirection or "auto"
    if direction == "up" then
        growDown = false
    elseif direction == "down" then
        growDown = true
    else
        local uiTop = UIParent:GetTop() or 0
        local uiBottom = UIParent:GetBottom() or 0
        local frameTop = frame:GetTop() or 0
        local frameBottom = frame:GetBottom() or 0
        local spaceAbove = uiTop - frameTop
        local spaceBelow = frameBottom - uiBottom

        if spaceAbove >= detailsHeight then
            growDown = false
        elseif spaceBelow >= detailsHeight then
            growDown = true
        else
            growDown = spaceBelow > spaceAbove
        end
    end

    detailsFrame:ClearAllPoints()
    if growDown then
        detailsFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
        detailsFrame:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    else
        detailsFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
        detailsFrame:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
    end
end

---------------------------------------------------------------------------
-- Create the XP tracker frame
---------------------------------------------------------------------------
local function CreateFrame_XPTracker()
    if XPTrackerState.frame then return end

    local settings = GetSettings()
    if not settings then return end

    local width = settings.width or 300
    local height = settings.height or 90
    local barHeight = settings.barHeight or 20
    local barFrameHeight = barHeight
    local detailsHeight = math.max(0, height - barFrameHeight)

    local frame = CreateFrame("Frame", "QUI_XPTracker", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 150)
    frame:SetSize(width, barFrameHeight)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetClampedToScreen(true)

    local bc = settings.borderColor or {0, 0, 0, 1}

    -- Details panel (separate from anchor frame so anchoring always targets the bar)
    local detailsFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailsFrame:SetHeight(detailsHeight)
    detailsFrame:SetFrameStrata("MEDIUM")
    detailsFrame:SetFrameLevel(frame:GetFrameLevel())
    detailsFrame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, detailsFrame))
    local bg = settings.backdropColor or {0.05, 0.05, 0.07, 0.85}
    detailsFrame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    UIKit.CreateBorderLines(detailsFrame)
    UIKit.UpdateBorderLines(detailsFrame, 1, bc[1], bc[2], bc[3], bc[4])
    detailsFrame:EnableMouse(true)
    frame.detailsFrame = detailsFrame
    UpdateDetailsDirection(frame)

    -- Font settings
    local fontPath, fontOutline = Helpers.GetGeneralFontSettings()
    local headerFontSize = settings.headerFontSize or 12
    local fontSize = settings.fontSize or 11
    local headerLineHeight = settings.headerLineHeight or 18

    -- Header: "Experience" left, "Level X" right
    local headerLeft = detailsFrame:CreateFontString(nil, "OVERLAY")
    headerLeft:SetFont(fontPath, headerFontSize, fontOutline)
    headerLeft:SetTextColor(0.9, 0.9, 0.9, 1)
    headerLeft:SetPoint("TOPLEFT", detailsFrame, "TOPLEFT", 6, -5)
    headerLeft:SetText("Experience")
    frame.headerLeft = headerLeft

    local headerRight = detailsFrame:CreateFontString(nil, "OVERLAY")
    headerRight:SetFont(fontPath, headerFontSize, fontOutline)
    headerRight:SetTextColor(1.0, 0.82, 0.0, 1) -- Gold
    headerRight:SetPoint("TOPRIGHT", detailsFrame, "TOPRIGHT", -6, -5)
    headerRight:SetText("Level 1")
    frame.headerRight = headerRight

    -- Stat lines
    local lineY = -(5 + headerLineHeight)
    local lineSpacing = settings.lineHeight or 14

    -- Line 1: Completed / Rested
    local line1 = detailsFrame:CreateFontString(nil, "OVERLAY")
    line1:SetFont(fontPath, fontSize, fontOutline)
    line1:SetTextColor(0.8, 0.8, 0.8, 1)
    line1:SetPoint("TOPLEFT", detailsFrame, "TOPLEFT", 6, lineY)
    line1:SetPoint("RIGHT", detailsFrame, "RIGHT", -6, 0)
    line1:SetJustifyH("LEFT")
    line1:SetWordWrap(false)
    frame.line1 = line1

    -- Line 2: XP/hour + Leveling in
    local line2 = detailsFrame:CreateFontString(nil, "OVERLAY")
    line2:SetFont(fontPath, fontSize, fontOutline)
    line2:SetTextColor(0.8, 0.8, 0.8, 1)
    line2:SetPoint("TOPLEFT", detailsFrame, "TOPLEFT", 6, lineY - lineSpacing)
    line2:SetPoint("RIGHT", detailsFrame, "RIGHT", -6, 0)
    line2:SetJustifyH("LEFT")
    line2:SetWordWrap(false)
    frame.line2 = line2

    -- Line 3: Level time / Session time
    local line3 = detailsFrame:CreateFontString(nil, "OVERLAY")
    line3:SetFont(fontPath, fontSize, fontOutline)
    line3:SetTextColor(0.8, 0.8, 0.8, 1)
    line3:SetPoint("TOPLEFT", detailsFrame, "TOPLEFT", 6, lineY - lineSpacing * 2)
    line3:SetPoint("RIGHT", detailsFrame, "RIGHT", -6, 0)
    line3:SetJustifyH("LEFT")
    line3:SetWordWrap(false)
    frame.line3 = line3

    -- XP Bar container
    local barContainer = CreateFrame("Frame", nil, frame)
    barContainer:SetAllPoints(frame)
    frame.barContainer = barContainer

    -- Bar background
    local barBG = barContainer:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints(barContainer)
    barBG:SetColorTexture(0, 0, 0, 0.5)
    frame.barBG = barBG

    -- XP StatusBar
    local xpBar = CreateFrame("StatusBar", nil, barContainer)
    xpBar:SetAllPoints(barContainer)
    xpBar:SetMinMaxValues(0, 1)
    xpBar:SetValue(0)
    local barColor = settings.barColor or {0.2, 0.5, 1.0, 1}
    local LSM = LibStub("LibSharedMedia-3.0", true)
    local texturePath
    if LSM then
        texturePath = LSM:Fetch("statusbar", settings.barTexture or "Solid")
    end
    if texturePath then
        xpBar:SetStatusBarTexture(texturePath)
    else
        xpBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    end
    xpBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] or 1)
    frame.xpBar = xpBar

    -- Rested overlay (texture, not a second bar)
    local restedOverlay = barContainer:CreateTexture(nil, "ARTWORK", nil, 1)
    restedOverlay:SetPoint("LEFT", xpBar:GetStatusBarTexture(), "RIGHT", 0, 0)
    restedOverlay:SetHeight(barHeight)
    restedOverlay:SetWidth(0)
    restedOverlay:Hide()
    if texturePath then
        restedOverlay:SetTexture(texturePath)
    else
        restedOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    end
    local restedColor = settings.restedColor or {1.0, 0.7, 0.1, 0.5}
    restedOverlay:SetVertexColor(restedColor[1], restedColor[2], restedColor[3], restedColor[4] or 0.5)
    frame.restedOverlay = restedOverlay

    -- Bar text overlay (parented to xpBar so it draws above the bar fill)
    local barText = xpBar:CreateFontString(nil, "OVERLAY")
    barText:SetFont(fontPath, fontSize - 1, fontOutline)
    barText:SetTextColor(1, 1, 1, 1)
    barText:SetPoint("CENTER", barContainer, "CENTER", 0, 0)
    barText:SetJustifyH("CENTER")
    frame.barText = barText

    -- Hover to reveal text (keep details visible while hovering either bar or details panel)
    local function UpdateHoverVisibility()
        local s = GetSettings()
        if not s then return end
        if s.hideTextUntilHover then
            local isHover = frame:IsMouseOver() or (frame.detailsFrame and frame.detailsFrame:IsMouseOver())
            SetTextVisible(frame, isHover)
        else
            SetTextVisible(frame, true)
        end
    end
    frame:SetScript("OnEnter", UpdateHoverVisibility)
    frame:SetScript("OnLeave", function()
        C_Timer.After(0, UpdateHoverVisibility)
    end)
    detailsFrame:SetScript("OnEnter", UpdateHoverVisibility)
    detailsFrame:SetScript("OnLeave", function()
        C_Timer.After(0, UpdateHoverVisibility)
    end)

    -- Dragging support
    frame:SetMovable(not settings.locked)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local s = GetSettings()
        local isOverridden = _G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(self)
        if s and not s.locked and not isOverridden then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position back to DB
        local s = GetSettings()
        if s then
            -- Always save center-relative offsets so reload positioning is stable
            -- regardless of which anchor point WoW uses during drag movement.
            local cx, cy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and cy and ux and uy then
                s.offsetX = RoundNearest(cx - ux)
                s.offsetY = RoundNearest(cy - uy)
            else
                local point, _, _, x, y = self:GetPoint(1)
                if point then
                    s.offsetX = RoundNearest(x or 0)
                    s.offsetY = RoundNearest(y or 0)
                end
            end

            -- Normalize to CENTER anchor now to match reload restoration path.
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", s.offsetX or 0, s.offsetY or 0)
        end
        UpdateDetailsDirection(self)
    end)

    frame:Hide()
    XPTrackerState.frame = frame
end

---------------------------------------------------------------------------
-- Update display with current XP data
---------------------------------------------------------------------------
local function UpdateDisplay()
    local frame = XPTrackerState.frame
    if not frame then return end

    local isPreview = XPTrackerState.isPreviewMode
    local settings = GetSettings()
    if (not settings or not settings.enabled) and not isPreview then
        frame:Hide()
        return
    end
    if not settings then return end

    local currentXP, maxXP, exhaustion, level, isAtCap, isXPDisabled

    if isPreview then
        -- Fake data for preview
        currentXP = 11000
        maxXP = 13000
        exhaustion = 1260
        level = 72
        isAtCap = false
        isXPDisabled = false
    else
        currentXP = UnitXP("player") or 0
        maxXP = UnitXPMax("player") or 1
        exhaustion = GetXPExhaustion() or 0
        level = UnitLevel("player") or 1
        isAtCap = IsPlayerAtEffectiveLevelCap and IsPlayerAtEffectiveLevelCap() or false
        isXPDisabled = IsXPUserDisabled and IsXPUserDisabled() or false

        -- Auto-hide at max level
        if isAtCap or isXPDisabled then
            frame:Hide()
            return
        end
    end

    if maxXP == 0 then maxXP = 1 end

    local fraction = currentXP / maxXP
    local percent = fraction * 100
    local remaining = maxXP - currentXP

    -- Rested
    local restedPercent = 0
    if exhaustion and exhaustion > 0 and maxXP > 0 then
        restedPercent = (exhaustion / maxXP) * 100
    end

    -- Header
    frame.headerLeft:SetText("Experience")
    frame.headerRight:SetText("Level " .. level)

    -- Line 1: Completed / Rested
    local line1Text = "Completed: " .. FormatPercent(percent)
    if restedPercent > 0 then
        line1Text = line1Text .. "  |  Rested: " .. FormatPercent(restedPercent)
    end
    frame.line1:SetText(line1Text)

    -- XP rate and time-to-level
    local xpPerHour
    if isPreview then
        xpPerHour = 45000
    else
        xpPerHour = GetXPPerHour()
    end

    -- Line 2: XP/hour + Leveling in
    local line2Text
    if xpPerHour > 0 then
        local secondsToLevel = (remaining / xpPerHour) * 3600
        line2Text = FormatXP(xpPerHour) .. "/hr  |  Level in: " .. FormatDuration(secondsToLevel)
    else
        line2Text = "Gathering data..."
    end
    frame.line2:SetText(line2Text)

    -- Line 3: Level time / Session time
    local now = GetTime()
    local levelTime, sessionTime
    if isPreview then
        levelTime = 1845
        sessionTime = 5430
    else
        levelTime = now - XPTrackerState.levelStartTime
        sessionTime = now - XPTrackerState.sessionStartTime
    end
    frame.line3:SetText("Level: " .. FormatDuration(levelTime) .. "  |  Session: " .. FormatDuration(sessionTime))

    -- XP Bar
    frame.xpBar:SetMinMaxValues(0, 1)
    frame.xpBar:SetValue(fraction)

    -- Rested overlay width
    local showRested = settings.showRested ~= false
    if showRested and exhaustion and exhaustion > 0 then
        local barWidth = frame.barContainer:GetWidth()
        if barWidth <= 0 then barWidth = frame:GetWidth() end
        local restedFraction = exhaustion / maxXP
        -- Clamp so rested doesn't extend past the bar end
        local maxRestedWidth = barWidth * (1 - fraction)
        local restedWidth = math.min(barWidth * restedFraction, maxRestedWidth)
        if restedWidth > 0 then
            frame.restedOverlay:SetWidth(restedWidth)
            frame.restedOverlay:Show()
        else
            frame.restedOverlay:Hide()
        end
    else
        frame.restedOverlay:Hide()
    end

    -- Bar text
    local showBarText = settings.showBarText ~= false
    if showBarText then
        local barTextStr = FormatXP(currentXP) .. "/" .. FormatXP(maxXP)
        barTextStr = barTextStr .. " (" .. FormatXP(remaining) .. ") " .. FormatPercent(percent)
        if restedPercent > 0 then
            barTextStr = barTextStr .. " (" .. FormatPercent(restedPercent) .. " rested)"
        end
        frame.barText:SetText(barTextStr)
        frame.barText:Show()
    else
        frame.barText:Hide()
    end

    frame:Show()

    -- Apply text visibility for hide-until-hover mode
    if settings.hideTextUntilHover then
        local isHover = frame:IsMouseOver() or (frame.detailsFrame and frame.detailsFrame:IsMouseOver())
        SetTextVisible(frame, isHover)
    else
        SetTextVisible(frame, true)
    end
end

---------------------------------------------------------------------------
-- Update appearance from settings (without changing data)
---------------------------------------------------------------------------
local function UpdateAppearance()
    if not XPTrackerState.frame then
        CreateFrame_XPTracker()
    end

    local frame = XPTrackerState.frame
    if not frame then return end

    local settings = GetSettings()
    if not settings then return end

    local width = settings.width or 300
    local height = settings.height or 90
    local barHeight = settings.barHeight or 20
    local barFrameHeight = barHeight
    local detailsHeight = math.max(0, height - barFrameHeight)
    frame:SetSize(width, barFrameHeight)

    -- Position
    if not (_G.QUI_IsFrameOverridden and _G.QUI_IsFrameOverridden(frame)) then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.offsetX or 0, settings.offsetY or 150)
    end

    local bc = settings.borderColor or {0, 0, 0, 1}

    -- Details panel appearance/size
    local bg = settings.backdropColor or {0.05, 0.05, 0.07, 0.85}
    frame.detailsFrame:SetWidth(width)
    frame.detailsFrame:SetHeight(detailsHeight)
    frame.detailsFrame:SetBackdrop(UIKit.GetBackdropInfo(nil, nil, frame.detailsFrame))
    frame.detailsFrame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    UIKit.UpdateBorderLines(frame.detailsFrame, 1, bc[1], bc[2], bc[3], bc[4])
    UpdateDetailsDirection(frame)

    -- Font
    local fontPath, fontOutline = Helpers.GetGeneralFontSettings()
    local fontSize = settings.fontSize or 11

    local headerFontSize = settings.headerFontSize or 12
    frame.headerLeft:SetFont(fontPath, headerFontSize, fontOutline)
    frame.headerRight:SetFont(fontPath, headerFontSize, fontOutline)
    frame.line1:SetFont(fontPath, fontSize, fontOutline)
    frame.line2:SetFont(fontPath, fontSize, fontOutline)
    frame.line3:SetFont(fontPath, fontSize, fontOutline)
    frame.barText:SetFont(fontPath, fontSize - 1, fontOutline)

    -- Line height (reposition stat lines)
    local headerLineHeight = settings.headerLineHeight or 18
    local lineSpacing = settings.lineHeight or 14
    local lineY = -(5 + headerLineHeight)
    frame.line1:ClearAllPoints()
    frame.line1:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 6, lineY)
    frame.line1:SetPoint("RIGHT", frame.detailsFrame, "RIGHT", -6, 0)
    frame.line2:ClearAllPoints()
    frame.line2:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 6, lineY - lineSpacing)
    frame.line2:SetPoint("RIGHT", frame.detailsFrame, "RIGHT", -6, 0)
    frame.line3:ClearAllPoints()
    frame.line3:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 6, lineY - lineSpacing * 2)
    frame.line3:SetPoint("RIGHT", frame.detailsFrame, "RIGHT", -6, 0)

    -- Bar height
    frame.restedOverlay:SetHeight(barHeight)

    -- Bar texture
    local LSM = LibStub("LibSharedMedia-3.0", true)
    local texturePath
    if LSM then
        texturePath = LSM:Fetch("statusbar", settings.barTexture or "Solid")
    end
    if texturePath then
        frame.xpBar:SetStatusBarTexture(texturePath)
        frame.restedOverlay:SetTexture(texturePath)
    end

    -- Bar color
    local barColor = settings.barColor or {0.2, 0.5, 1.0, 1}
    frame.xpBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] or 1)

    -- Rested color
    local restedColor = settings.restedColor or {1.0, 0.7, 0.1, 0.5}
    frame.restedOverlay:SetVertexColor(restedColor[1], restedColor[2], restedColor[3], restedColor[4] or 0.5)

    -- Movable state
    frame:SetMovable(not settings.locked)

    if settings.hideTextUntilHover then
        local isHover = frame:IsMouseOver() or (frame.detailsFrame and frame.detailsFrame:IsMouseOver())
        SetTextVisible(frame, isHover)
    else
        SetTextVisible(frame, true)
    end
end

---------------------------------------------------------------------------
-- Ticker callback (every 2 seconds)
---------------------------------------------------------------------------
local function OnTick()
    if not XPTrackerState.frame then return end

    local settings = GetSettings()
    if not settings or not settings.enabled then return end
    if XPTrackerState.isPreviewMode then return end

    XPTrackerState.tickCount = XPTrackerState.tickCount + 1

    -- Record sample every 5 ticks (10 seconds)
    if XPTrackerState.tickCount % 5 == 0 then
        RecordSample()
    end

    UpdateDisplay()
end

---------------------------------------------------------------------------
-- Handle XP gain events
---------------------------------------------------------------------------
local function OnXPUpdate()
    if XPTrackerState.isPreviewMode then return end
    if not XPTrackerState.sessionInitialized then return end

    local currentXP = UnitXP("player") or 0
    local currentLevel = UnitLevel("player") or 1

    -- Track XP delta
    if currentLevel == XPTrackerState.lastKnownLevel then
        local delta = currentXP - XPTrackerState.lastKnownXP
        if delta > 0 then
            XPTrackerState.totalSessionXP = XPTrackerState.totalSessionXP + delta
        end
    end

    XPTrackerState.lastKnownXP = currentXP
    XPTrackerState.lastKnownLevel = currentLevel

    -- Record a sample immediately on XP gain for responsiveness
    RecordSample()

    UpdateDisplay()
end

---------------------------------------------------------------------------
-- Handle level-up
---------------------------------------------------------------------------
local function OnLevelUp(newLevel)
    if XPTrackerState.isPreviewMode then return end
    if not XPTrackerState.sessionInitialized then return end

    -- PLAYER_XP_UPDATE fires before PLAYER_LEVEL_UP, so XP delta is already tracked

    XPTrackerState.levelStartTime = GetTime()
    XPTrackerState.lastKnownXP = UnitXP("player") or 0
    XPTrackerState.lastKnownLevel = newLevel or UnitLevel("player") or 1

    -- Clear ring buffer on level-up for fresh rate calculation
    XPTrackerState.samples = {}
    RecordSample()

    UpdateDisplay()
end

---------------------------------------------------------------------------
-- Initialize session tracking
---------------------------------------------------------------------------
local function InitializeSession()
    local now = GetTime()
    local currentXP = UnitXP("player") or 0
    local currentLevel = UnitLevel("player") or 1

    XPTrackerState.sessionStartTime = now
    XPTrackerState.sessionStartXP = currentXP
    XPTrackerState.sessionStartLevel = currentLevel
    XPTrackerState.totalSessionXP = 0
    XPTrackerState.levelStartTime = now
    XPTrackerState.lastKnownXP = currentXP
    XPTrackerState.lastKnownLevel = currentLevel
    XPTrackerState.samples = {}
    XPTrackerState.tickCount = 0

    XPTrackerState.sessionInitialized = true
    RecordSample()
end

---------------------------------------------------------------------------
-- Start/stop ticker
---------------------------------------------------------------------------
local function StartTicker()
    if XPTrackerState.ticker then return end
    XPTrackerState.ticker = C_Timer.NewTicker(2, OnTick)
end

local function StopTicker()
    if XPTrackerState.ticker then
        XPTrackerState.ticker:Cancel()
        XPTrackerState.ticker = nil
    end
end

---------------------------------------------------------------------------
-- Refresh (called when settings change)
---------------------------------------------------------------------------
local function RefreshXPTracker()
    local settings = GetSettings()

    if (not settings or not settings.enabled) and not XPTrackerState.isPreviewMode then
        StopTicker()
        if XPTrackerState.frame then
            XPTrackerState.frame:Hide()
        end
        return
    end

    CreateFrame_XPTracker()
    UpdateAppearance()

    if not XPTrackerState.isPreviewMode then
        StartTicker()
    end

    UpdateDisplay()
end

---------------------------------------------------------------------------
-- Toggle preview mode
---------------------------------------------------------------------------
local function TogglePreview(enable)
    CreateFrame_XPTracker()
    if not XPTrackerState.frame then return end

    enable = (enable == true)
    XPTrackerState.isPreviewMode = enable

    if enable then
        StopTicker()
        UpdateAppearance()
        UpdateDisplay()
    else
        local settings = GetSettings()
        if settings and settings.enabled then
            -- Check if at max level
            local isAtCap = IsPlayerAtEffectiveLevelCap and IsPlayerAtEffectiveLevelCap() or false
            local isXPDisabled = IsXPUserDisabled and IsXPUserDisabled() or false
            if isAtCap or isXPDisabled then
                XPTrackerState.frame:Hide()
            else
                StartTicker()
                UpdateDisplay()
            end
        else
            XPTrackerState.frame:Hide()
        end
    end
end

local function IsPreviewMode()
    return XPTrackerState.isPreviewMode
end

local function InitializeXPTrackerStartup()
    if XPTrackerState.sessionInitialized then return end

    InitializeSession()
    CreateFrame_XPTracker()

    local settings = GetSettings()
    if settings and settings.enabled then
        local isAtCap = IsPlayerAtEffectiveLevelCap and IsPlayerAtEffectiveLevelCap() or false
        local isXPDisabled = IsXPUserDisabled and IsXPUserDisabled() or false
        if not isAtCap and not isXPDisabled then
            UpdateAppearance()
            StartTicker()
            UpdateDisplay()
        end
    end

    -- Force one immediate details/layout pass right after init.
    if XPTrackerState.frame then
        UpdateDetailsDirection(XPTrackerState.frame)
    end
end

local function ScheduleXPTrackerStartup()
    if XPTrackerState.sessionInitialized or XPTrackerState.startupScheduled then return end
    XPTrackerState.startupScheduled = true
    C_Timer.After(1, function()
        XPTrackerState.startupScheduled = false
        InitializeXPTrackerStartup()
    end)
end

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        ScheduleXPTrackerStartup()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        OnLevelUp(newLevel)
    elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" then
        if XPTrackerState.sessionInitialized then
            UpdateDisplay()
        end
    end
end)

---------------------------------------------------------------------------
-- Global exports
---------------------------------------------------------------------------
_G.QUI_RefreshXPTracker = RefreshXPTracker
_G.QUI_ToggleXPTrackerPreview = TogglePreview
_G.QUI_IsXPTrackerPreviewMode = IsPreviewMode

QUI.XPTracker = {
    Refresh = RefreshXPTracker,
    TogglePreview = TogglePreview,
    IsPreviewMode = IsPreviewMode,
}
