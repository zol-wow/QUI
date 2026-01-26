---------------------------------------------------------------------------
-- QUI Mythic+ Timer Module
-- Custom M+ timer frame with compact layout option
-- This file: Frame creation, layout, data handling, events
-- Skinning applied separately in skinning/mplus_timer.lua
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

---------------------------------------------------------------------------
-- Module Constants
---------------------------------------------------------------------------
local UPDATE_INTERVAL = 0.1  -- Timer update frequency (seconds)

-- Full layout constants
local FRAME_WIDTH = 240
local BAR_WIDTH = 220
local BAR_HEIGHT = 14
local BAR_PADDING = 4
local FRAME_PADDING = 10
local VERTICAL_SPACING = 4
local OBJECTIVES_SPACING = 2

-- Full mode font sizes
local FONT_SIZE_TIMER = 28
local FONT_SIZE_KEY = 14
local FONT_SIZE_AFFIXES = 11
local FONT_SIZE_BAR = 11
local FONT_SIZE_OBJECTIVE = 12
local FONT_SIZE_DEATHS = 12

-- Compact layout constants
local COMPACT_FRAME_WIDTH = 220
local COMPACT_BAR_WIDTH = 200
local COMPACT_BAR_HEIGHT = 12
local COMPACT_BAR_PADDING = 2
local COMPACT_FRAME_PADDING = 6
local COMPACT_VERTICAL_SPACING = 2
local COMPACT_OBJECTIVES_SPACING = 1

-- Compact mode font sizes
local COMPACT_FONT_SIZE_HEADER = 12    -- "+15 Jade Serpent"
local COMPACT_FONT_SIZE_TIMER = 16     -- "23:56/32:00"
local COMPACT_FONT_SIZE_BAR = 9
local COMPACT_FONT_SIZE_OBJECTIVE = 10
local COMPACT_FONT_SIZE_DEATHS = 10

-- Sleek layout constants (most compact, information-dense)
local SLEEK_FRAME_WIDTH = 200
local SLEEK_BAR_WIDTH = 188
local SLEEK_BAR_HEIGHT = 8
local SLEEK_BAR_PADDING = 2
local SLEEK_FRAME_PADDING = 6
local SLEEK_VERTICAL_SPACING = 3
local SLEEK_OBJECTIVES_SPACING = 1

-- Sleek mode font sizes
local SLEEK_FONT_SIZE_HEADER = 12
local SLEEK_FONT_SIZE_TIMER = 14
local SLEEK_FONT_SIZE_PACE = 11
local SLEEK_FONT_SIZE_BAR = 8
local SLEEK_FONT_SIZE_FORCES = 10
local SLEEK_FONT_SIZE_OBJECTIVE = 10
local SLEEK_FONT_SIZE_DEATHS = 9

-- Affix icon sizes
local AFFIX_ICON_SIZE = 18
local AFFIX_ICON_SPACING = 4
local COMPACT_AFFIX_ICON_SIZE = 14
local COMPACT_AFFIX_ICON_SPACING = 2
local SLEEK_AFFIX_ICON_SIZE = 12
local SLEEK_AFFIX_ICON_SPACING = 2

local FONT_FLAGS = "OUTLINE"

---------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------
local MPlusTimer = {}
ns.MPlusTimer = MPlusTimer

MPlusTimer.frames = {}
MPlusTimer.bars = {}
MPlusTimer.objectives = {}

-- Timer state
MPlusTimer.state = {
    inChallenge = false,
    demoModeActive = false,
    timerStarted = false,
    timerLoopRunning = false,

    -- Time data
    timer = 0,              -- Current elapsed time (seconds)
    timeLimit = 0,          -- Total time limit (seconds)
    timeLimits = {},        -- { [1]=+1 limit, [2]=+2 limit, [3]=+3 limit }
    completionTimeMs = 0,
    challengeCompleted = false,
    completedOnTime = false,

    -- Key data
    level = 0,
    affixes = {},
    affixIDs = {},
    mapID = nil,
    dungeonName = "",

    -- Deaths
    deathCount = 0,
    deathTimeLost = 0,

    -- Forces
    currentCount = 0,
    totalCount = 0,
    currentPercent = 0,
    pullCount = 0,
    pullPercent = 0,
    forcesCompleted = false,
    forcesCompletionTime = nil,

    -- Objectives (bosses)
    objectivesList = {},  -- { { name="Boss", time=nil or seconds, expectedTime=nil, differential=nil }, ... }

    -- Pace tracking (Sleek mode)
    currentTargetTier = 3,      -- Which reward tier we're targeting (3=+3, 2=+2, 1=+1, 0=overtime)
    currentTargetTime = 0,      -- Time limit for current target tier
    paceOffset = 0,             -- Seconds ahead (+) or behind (-) current target
}

-- Default state for reset
local defaultState = {
    inChallenge = false,
    demoModeActive = false,
    timerStarted = false,
    timerLoopRunning = false,
    timer = 0,
    timeLimit = 0,
    timeLimits = {},
    completionTimeMs = 0,
    challengeCompleted = false,
    completedOnTime = false,
    level = 0,
    affixes = {},
    affixIDs = {},
    mapID = nil,
    dungeonName = "",
    deathCount = 0,
    deathTimeLost = 0,
    currentCount = 0,
    totalCount = 0,
    currentPercent = 0,
    pullCount = 0,
    pullPercent = 0,
    forcesCompleted = false,
    forcesCompletionTime = nil,
    objectivesList = {},
    currentTargetTier = 3,
    currentTargetTime = 0,
    paceOffset = 0,
}

---------------------------------------------------------------------------
-- Settings Access
---------------------------------------------------------------------------
local DEFAULTS = {
    enabled = true,
    layoutMode = "full",    -- "compact" or "full"
    showTimer = true,       -- Show elapsed/total timer text (full mode only)
    showBorder = true,      -- Show frame border
    showDeaths = true,
    showAffixes = true,
    showObjectives = true,
    scale = 1.0,
}

local function GetSettings()
    return Helpers.GetModuleSettings("mplusTimer", DEFAULTS)
end

local function IsCompactMode()
    local settings = GetSettings()
    return settings.layoutMode == "compact"
end

local function IsSleekMode()
    local settings = GetSettings()
    return settings.layoutMode == "sleek"
end

local function GetPosition()
    local defaults = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -100, y = -200 }

    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.mplusTimer then
        local pos = QUICore.db.profile.mplusTimer.position
        if pos then
            return {
                point = pos.point or defaults.point,
                relPoint = pos.relPoint or defaults.relPoint,
                x = pos.x or defaults.x,
                y = pos.y or defaults.y,
            }
        end
    end
    return defaults
end

local function SavePosition(point, relPoint, x, y)
    local QUICore = _G.QUI and _G.QUI.QUICore
    if QUICore and QUICore.db and QUICore.db.profile then
        if not QUICore.db.profile.mplusTimer then
            QUICore.db.profile.mplusTimer = {}
        end
        QUICore.db.profile.mplusTimer.position = {
            point = point,
            relPoint = relPoint,
            x = x,
            y = y
        }
    end
end

local function IsEnabled()
    local settings = GetSettings()
    return settings.enabled ~= false
end

---------------------------------------------------------------------------
-- Font Helper
---------------------------------------------------------------------------
local function GetGlobalFont()
    return Helpers.GetGeneralFont()
end

---------------------------------------------------------------------------
-- Utility Functions
---------------------------------------------------------------------------
local function FormatTime(seconds)
    if not seconds then return "0:00" end
    seconds = math.floor(seconds)
    local negative = seconds < 0
    seconds = math.abs(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    local str = string.format("%d:%02d", mins, secs)
    return negative and ("-" .. str) or str
end

local function FormatTimeMs(ms)
    if not ms then return "0:00.000" end
    local seconds = ms / 1000
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%d:%06.3f", mins, secs)
end

local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

local function Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Format pace offset for display: "+1:24" or "-0:45"
local function FormatPaceOffset(seconds)
    if not seconds then return "" end
    local absSeconds = math.abs(seconds)
    local mins = math.floor(absSeconds / 60)
    local secs = absSeconds % 60
    local prefix = seconds >= 0 and "+" or "-"
    return string.format("%s%d:%02d", prefix, mins, secs)
end

---------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------
function MPlusTimer:CreateFrames()
    if self.frames.root then return end

    local font = GetGlobalFont()

    -- Root frame
    local root = CreateFrame("Frame", "QUI_MPlusTimerFrame", UIParent)
    root:SetSize(FRAME_WIDTH, 300)  -- Height will be adjusted dynamically
    root:SetFrameStrata("MEDIUM")
    root:SetClampedToScreen(true)
    root:Hide()

    local pos = GetPosition()
    root:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    self.frames.root = root

    -- Dungeon name (top, centered)
    local dungeonText = root:CreateFontString(nil, "ARTWORK")
    dungeonText:SetFont(font, FONT_SIZE_KEY, FONT_FLAGS)
    dungeonText:SetJustifyH("CENTER")
    dungeonText:SetText("")
    self.frames.dungeonText = dungeonText

    -- Deaths frame (clickable for tooltip)
    local deathsFrame = CreateFrame("Frame", nil, root)
    deathsFrame:SetSize(80, 20)
    deathsFrame:EnableMouse(true)

    local deathsText = deathsFrame:CreateFontString(nil, "ARTWORK")
    deathsText:SetFont(font, FONT_SIZE_DEATHS, FONT_FLAGS)
    deathsText:SetJustifyH("RIGHT")
    deathsText:SetPoint("RIGHT", deathsFrame, "RIGHT", 0, 0)
    deathsText:SetText("")

    deathsFrame:SetScript("OnEnter", function(frame)
        if MPlusTimer.state.deathCount > 0 then
            GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Deaths", 1, 0.3, 0.3)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Total Deaths:", tostring(MPlusTimer.state.deathCount), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine("Time Lost:", FormatTime(MPlusTimer.state.deathTimeLost), 1, 1, 1, 1, 0.3, 0.3)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Each death adds 5 seconds to timer", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)
    deathsFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.frames.deathsFrame = deathsFrame
    self.frames.deathsText = deathsText

    -- Timer text (large, center)
    local timerText = root:CreateFontString(nil, "ARTWORK")
    timerText:SetFont(font, FONT_SIZE_TIMER, FONT_FLAGS)
    timerText:SetJustifyH("CENTER")
    timerText:SetText("0:00 / 0:00")
    self.frames.timerText = timerText

    -- Pace text (Sleek mode: shows "+1:24" or "-0:45")
    local paceText = root:CreateFontString(nil, "ARTWORK")
    paceText:SetFont(font, SLEEK_FONT_SIZE_PACE, FONT_FLAGS)
    paceText:SetJustifyH("RIGHT")
    paceText:SetText("")
    paceText:Hide()
    self.frames.paceText = paceText

    -- Key level text
    local keyText = root:CreateFontString(nil, "ARTWORK")
    keyText:SetFont(font, FONT_SIZE_KEY, FONT_FLAGS)
    keyText:SetJustifyH("LEFT")
    keyText:SetText("[0]")
    self.frames.keyText = keyText

    -- Affixes text (legacy, hidden when using icons)
    local affixText = root:CreateFontString(nil, "ARTWORK")
    affixText:SetFont(font, FONT_SIZE_AFFIXES, FONT_FLAGS)
    affixText:SetJustifyH("LEFT")
    affixText:SetText("")
    self.frames.affixText = affixText

    -- Affix icons container
    local affixIconsFrame = CreateFrame("Frame", nil, root)
    affixIconsFrame:SetSize(AFFIX_ICON_SIZE * 4 + AFFIX_ICON_SPACING * 3, AFFIX_ICON_SIZE)
    self.frames.affixIcons = affixIconsFrame

    -- Create up to 4 affix icon buttons
    self.affixIcons = {}
    for i = 1, 4 do
        local iconFrame = CreateFrame("Frame", nil, affixIconsFrame)
        iconFrame:SetSize(AFFIX_ICON_SIZE, AFFIX_ICON_SIZE)
        iconFrame:EnableMouse(true)

        -- Icon texture
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Trim edges
        iconFrame.icon = icon

        -- Tooltip
        iconFrame:SetScript("OnEnter", function(frame)
            if frame.affixID then
                local name, desc = C_ChallengeMode.GetAffixInfo(frame.affixID)
                if name then
                    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(name, 1, 0.82, 0)
                    if desc then
                        GameTooltip:AddLine(desc, 1, 1, 1, true)
                    end
                    GameTooltip:Show()
                end
            end
        end)
        iconFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        iconFrame:Hide()
        self.affixIcons[i] = iconFrame
    end

    -- Bars container
    local barsFrame = CreateFrame("Frame", nil, root)
    barsFrame:SetSize(BAR_WIDTH, (BAR_HEIGHT + BAR_PADDING) * 4)
    self.frames.bars = barsFrame

    -- Create timer bars (+3, +2, +1)
    self.bars = {}
    for i = 1, 3 do
        local bar = self:CreateProgressBar(barsFrame, "timer" .. i)
        self.bars[i] = bar
    end

    -- Forces bar
    self.bars.forces = self:CreateProgressBar(barsFrame, "forces")

    -- Sleek mode: Segmented progress bar (single bar with colored segments)
    local sleekBarContainer = CreateFrame("Frame", nil, root, "BackdropTemplate")
    sleekBarContainer:SetSize(SLEEK_BAR_WIDTH, SLEEK_BAR_HEIGHT)
    sleekBarContainer:Hide()
    self.frames.sleekBar = sleekBarContainer

    -- Create three segment regions inside the sleek bar
    self.sleekSegments = {}
    local segmentColors = {
        [3] = {0.2, 0.85, 0.4, 1},   -- +3: Green
        [2] = {0.95, 0.75, 0.2, 1},  -- +2: Yellow
        [1] = {0.4, 0.7, 0.9, 1},    -- +1: Blue (accent)
    }

    for i = 3, 1, -1 do
        local segment = sleekBarContainer:CreateTexture(nil, "ARTWORK")
        segment:SetTexture("Interface\\Buttons\\WHITE8x8")
        segment:SetVertexColor(unpack(segmentColors[i]))
        segment:SetHeight(SLEEK_BAR_HEIGHT - 2)
        self.sleekSegments[i] = segment
    end

    -- Position marker (shows current time position)
    local posMarker = sleekBarContainer:CreateTexture(nil, "OVERLAY")
    posMarker:SetTexture("Interface\\Buttons\\WHITE8x8")
    posMarker:SetVertexColor(1, 1, 1, 0.9)
    posMarker:SetSize(2, SLEEK_BAR_HEIGHT)
    self.frames.sleekPosMarker = posMarker

    -- Objectives container
    local objectivesFrame = CreateFrame("Frame", nil, root)
    objectivesFrame:SetSize(FRAME_WIDTH - FRAME_PADDING * 2, 100)
    self.frames.objectives = objectivesFrame

    -- Pre-create objective lines (up to 8 bosses)
    self.objectives = {}
    for i = 1, 8 do
        local objText = objectivesFrame:CreateFontString(nil, "ARTWORK")
        objText:SetFont(font, FONT_SIZE_OBJECTIVE, FONT_FLAGS)
        objText:SetJustifyH("LEFT")
        objText:SetText("")
        self.objectives[i] = objText
    end

    -- Make movable
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")

    root:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        SavePosition(point, relPoint, x, y)
    end)
end

function MPlusTimer:CreateProgressBar(parent, barType)
    local bar = {}

    -- Container frame with backdrop
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(BAR_WIDTH, BAR_HEIGHT)
    bar.frame = frame

    -- Status bar
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetPoint("TOPLEFT", 1, -1)
    statusBar:SetPoint("BOTTOMRIGHT", -1, 1)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar.bar = statusBar

    -- Bar text
    local text = statusBar:CreateFontString(nil, "OVERLAY")
    text:SetFont(GetGlobalFont(), FONT_SIZE_BAR, FONT_FLAGS)
    text:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    text:SetJustifyH("RIGHT")
    bar.text = text

    -- Forces bar has overlay texture for current pull preview
    if barType == "forces" then
        local overlay = statusBar:CreateTexture(nil, "OVERLAY")
        overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
        overlay:SetHeight(statusBar:GetHeight() - 2)
        overlay:Hide()
        bar.overlay = overlay
    end

    bar.type = barType
    return bar
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
function MPlusTimer:UpdateLayout()
    if not self.frames.root then return end

    local font = GetGlobalFont()
    local settings = GetSettings()

    if IsSleekMode() then
        self:UpdateLayoutSleek(font, settings)
    elseif IsCompactMode() then
        self:UpdateLayoutCompact(font, settings)
    else
        self:UpdateLayoutFull(font, settings)
    end
end

function MPlusTimer:UpdateLayoutCompact(font, settings)
    local pad = COMPACT_FRAME_PADDING
    local vSpace = COMPACT_VERTICAL_SPACING
    local barWidth = COMPACT_BAR_WIDTH
    local barHeight = COMPACT_BAR_HEIGHT
    local barPad = COMPACT_BAR_PADDING
    local objSpace = COMPACT_OBJECTIVES_SPACING
    local iconSize = COMPACT_AFFIX_ICON_SIZE
    local iconSpacing = COMPACT_AFFIX_ICON_SPACING

    -- Update root frame width
    self.frames.root:SetWidth(COMPACT_FRAME_WIDTH)

    -- Hide Sleek-only elements
    if self.frames.sleekBar then self.frames.sleekBar:Hide() end
    if self.frames.paceText then self.frames.paceText:Hide() end

    -- Show regular bars container
    self.frames.bars:Show()
    for i = 1, 3 do
        self.bars[i].frame:Show()
    end

    local yOffset = pad

    -- Row 1: "+15 Dungeon Name" (left) + Deaths (right)
    self.frames.dungeonText:ClearAllPoints()
    self.frames.dungeonText:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
    self.frames.dungeonText:SetFont(font, COMPACT_FONT_SIZE_HEADER, FONT_FLAGS)
    self.frames.dungeonText:SetJustifyH("LEFT")

    -- Deaths frame (for tooltip)
    self.frames.deathsFrame:ClearAllPoints()
    self.frames.deathsFrame:SetPoint("TOPRIGHT", self.frames.root, "TOPRIGHT", -pad, -yOffset)
    self.frames.deathsFrame:SetSize(60, COMPACT_FONT_SIZE_DEATHS + 4)
    self.frames.deathsText:SetFont(font, COMPACT_FONT_SIZE_DEATHS, FONT_FLAGS)

    yOffset = yOffset + COMPACT_FONT_SIZE_HEADER + vSpace

    -- Row 2: Affix icons (left) + Timer (right, if enabled)
    if settings.showAffixes then
        self.frames.affixIcons:ClearAllPoints()
        self.frames.affixIcons:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
        self.frames.affixIcons:SetSize(iconSize * 4 + iconSpacing * 3, iconSize)
        self.frames.affixIcons:Show()

        -- Position individual icons
        for i, iconFrame in ipairs(self.affixIcons) do
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("LEFT", self.frames.affixIcons, "LEFT", (i - 1) * (iconSize + iconSpacing), 0)
        end
    else
        self.frames.affixIcons:Hide()
    end

    if settings.showTimer then
        self.frames.timerText:ClearAllPoints()
        self.frames.timerText:SetPoint("TOPRIGHT", self.frames.root, "TOPRIGHT", -pad, -yOffset)
        self.frames.timerText:SetFont(font, COMPACT_FONT_SIZE_TIMER, FONT_FLAGS)
        self.frames.timerText:SetJustifyH("RIGHT")
        self.frames.timerText:Show()
    else
        self.frames.timerText:Hide()
    end

    -- Only add row height if either affixes or timer shown
    if settings.showAffixes or settings.showTimer then
        local rowHeight = settings.showAffixes and iconSize or COMPACT_FONT_SIZE_TIMER
        yOffset = yOffset + rowHeight + vSpace
    end

    -- Hide key and affix text in compact mode (using icons instead)
    self.frames.keyText:Hide()
    self.frames.affixText:Hide()

    -- Timer bars (+3, +2, +1 from left to right)
    self.frames.bars:ClearAllPoints()
    self.frames.bars:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
    self.frames.bars:SetSize(barWidth, (barHeight + barPad) * 2)

    local bar1Frac, bar2Frac, bar3Frac = self:GetTimerBarFractions()
    local barX = 0

    -- +3 bar (leftmost)
    local bar3Width = barWidth * bar3Frac
    self.bars[3].frame:ClearAllPoints()
    self.bars[3].frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", barX, 0)
    self.bars[3].frame:SetSize(bar3Width, barHeight)
    self.bars[3].bar:SetPoint("TOPLEFT", 1, -1)
    self.bars[3].bar:SetPoint("BOTTOMRIGHT", -1, 1)
    barX = barX + bar3Width + 1

    -- +2 bar (middle)
    local bar2Width = barWidth * bar2Frac - 1
    self.bars[2].frame:ClearAllPoints()
    self.bars[2].frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", barX, 0)
    self.bars[2].frame:SetSize(bar2Width, barHeight)
    self.bars[2].bar:SetPoint("TOPLEFT", 1, -1)
    self.bars[2].bar:SetPoint("BOTTOMRIGHT", -1, 1)
    barX = barX + bar2Width + 1

    -- +1 bar (rightmost)
    local bar1Width = barWidth * bar1Frac - 1
    self.bars[1].frame:ClearAllPoints()
    self.bars[1].frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", barX, 0)
    self.bars[1].frame:SetSize(bar1Width, barHeight)
    self.bars[1].bar:SetPoint("TOPLEFT", 1, -1)
    self.bars[1].bar:SetPoint("BOTTOMRIGHT", -1, 1)

    yOffset = yOffset + barHeight + barPad

    -- Forces bar
    self.bars.forces.frame:ClearAllPoints()
    self.bars.forces.frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", 0, -(barHeight + barPad))
    self.bars.forces.frame:SetSize(barWidth, barHeight)
    self.bars.forces.bar:SetPoint("TOPLEFT", 1, -1)
    self.bars.forces.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    if self.bars.forces.overlay then
        self.bars.forces.overlay:SetPoint("TOPLEFT", 1, -1)
        self.bars.forces.overlay:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    yOffset = yOffset + barHeight + barPad + vSpace

    -- Objectives
    self.frames.objectives:ClearAllPoints()
    self.frames.objectives:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)

    local objY = 0
    for i = 1, 8 do
        self.objectives[i]:ClearAllPoints()
        self.objectives[i]:SetPoint("TOPLEFT", self.frames.objectives, "TOPLEFT", 0, -objY)
        self.objectives[i]:SetFont(font, COMPACT_FONT_SIZE_OBJECTIVE, FONT_FLAGS)
        local objText = self.objectives[i]:GetText()
        if objText and objText ~= "" then
            objY = objY + COMPACT_FONT_SIZE_OBJECTIVE + objSpace
        end
    end

    yOffset = yOffset + objY + pad

    self.frames.root:SetHeight(yOffset)
end

function MPlusTimer:UpdateLayoutSleek(font, settings)
    local pad = SLEEK_FRAME_PADDING
    local vSpace = SLEEK_VERTICAL_SPACING
    local barWidth = SLEEK_BAR_WIDTH
    local barHeight = SLEEK_BAR_HEIGHT
    local objSpace = SLEEK_OBJECTIVES_SPACING
    local iconSize = SLEEK_AFFIX_ICON_SIZE
    local iconSpacing = SLEEK_AFFIX_ICON_SPACING

    -- Update root frame width
    self.frames.root:SetWidth(SLEEK_FRAME_WIDTH)

    local yOffset = pad

    -- Row 1: "+15 Dungeon Name" (left) + Deaths count (right) + Affix icons (far right)
    self.frames.dungeonText:ClearAllPoints()
    self.frames.dungeonText:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
    self.frames.dungeonText:SetFont(font, SLEEK_FONT_SIZE_HEADER, FONT_FLAGS)
    self.frames.dungeonText:SetJustifyH("LEFT")

    -- Deaths - compact format in header
    if settings.showDeaths then
        self.frames.deathsFrame:ClearAllPoints()
        self.frames.deathsFrame:SetPoint("TOPRIGHT", self.frames.root, "TOPRIGHT", -pad - (settings.showAffixes and (iconSize * 4 + iconSpacing * 3 + 4) or 0), -yOffset)
        self.frames.deathsFrame:SetSize(40, SLEEK_FONT_SIZE_DEATHS + 2)
        self.frames.deathsText:SetFont(font, SLEEK_FONT_SIZE_DEATHS, FONT_FLAGS)
        self.frames.deathsFrame:Show()
    else
        self.frames.deathsFrame:Hide()
    end

    -- Affix icons (far right of header)
    if settings.showAffixes then
        self.frames.affixIcons:ClearAllPoints()
        self.frames.affixIcons:SetPoint("TOPRIGHT", self.frames.root, "TOPRIGHT", -pad, -yOffset + 1)
        self.frames.affixIcons:SetSize(iconSize * 4 + iconSpacing * 3, iconSize)
        self.frames.affixIcons:Show()

        for i, iconFrame in ipairs(self.affixIcons) do
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("RIGHT", self.frames.affixIcons, "RIGHT", -((i - 1) * (iconSize + iconSpacing)), 0)
        end
    else
        self.frames.affixIcons:Hide()
    end

    yOffset = yOffset + SLEEK_FONT_SIZE_HEADER + vSpace

    -- Row 2: Timer (left) + Pace indicator (right)
    if settings.showTimer then
        self.frames.timerText:ClearAllPoints()
        self.frames.timerText:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
        self.frames.timerText:SetFont(font, SLEEK_FONT_SIZE_TIMER, FONT_FLAGS)
        self.frames.timerText:SetJustifyH("LEFT")
        self.frames.timerText:Show()

        -- Pace indicator on right
        self.frames.paceText:ClearAllPoints()
        self.frames.paceText:SetPoint("TOPRIGHT", self.frames.root, "TOPRIGHT", -pad, -yOffset)
        self.frames.paceText:SetFont(font, SLEEK_FONT_SIZE_PACE, FONT_FLAGS)
        self.frames.paceText:Show()

        yOffset = yOffset + SLEEK_FONT_SIZE_TIMER + vSpace
    else
        self.frames.timerText:Hide()
        self.frames.paceText:Hide()
    end

    -- Hide key text in sleek mode (integrated into header)
    self.frames.keyText:Hide()
    self.frames.affixText:Hide()

    -- Row 3: Segmented progress bar (single bar with +3/+2/+1 segments)
    -- Hide regular bars in sleek mode
    self.frames.bars:Hide()
    for i = 1, 3 do
        self.bars[i].frame:Hide()
    end

    -- Show and position sleek segmented bar
    self.frames.sleekBar:ClearAllPoints()
    self.frames.sleekBar:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
    self.frames.sleekBar:SetSize(barWidth, barHeight)
    self.frames.sleekBar:Show()

    -- Position segments within sleek bar
    self:UpdateSleekBarSegments()

    yOffset = yOffset + barHeight + vSpace

    -- Row 4: Forces bar (reuse existing, but slimmer)
    self.bars.forces.frame:ClearAllPoints()
    self.bars.forces.frame:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
    self.bars.forces.frame:SetSize(barWidth, barHeight)
    self.bars.forces.frame:Show()
    self.bars.forces.bar:SetPoint("TOPLEFT", 1, -1)
    self.bars.forces.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    self.bars.forces.text:SetFont(font, SLEEK_FONT_SIZE_FORCES, FONT_FLAGS)

    yOffset = yOffset + barHeight + vSpace

    -- Row 5+: Objectives with differentials
    if settings.showObjectives then
        self.frames.objectives:ClearAllPoints()
        self.frames.objectives:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
        self.frames.objectives:Show()

        local objY = 0
        for i = 1, 8 do
            self.objectives[i]:ClearAllPoints()
            self.objectives[i]:SetPoint("TOPLEFT", self.frames.objectives, "TOPLEFT", 0, -objY)
            self.objectives[i]:SetFont(font, SLEEK_FONT_SIZE_OBJECTIVE, FONT_FLAGS)
            local objText = self.objectives[i]:GetText()
            if objText and objText ~= "" then
                objY = objY + SLEEK_FONT_SIZE_OBJECTIVE + objSpace
            end
        end

        yOffset = yOffset + objY
    else
        self.frames.objectives:Hide()
    end

    yOffset = yOffset + pad

    self.frames.root:SetHeight(yOffset)
end

-- Update sleek bar segment positions based on time fractions
function MPlusTimer:UpdateSleekBarSegments()
    if not self.frames.sleekBar or not self.sleekSegments then return end

    local barWidth = SLEEK_BAR_WIDTH - 2  -- Account for border
    local bar1Frac, bar2Frac, bar3Frac = self:GetTimerBarFractions()

    local xOffset = 1

    -- +3 segment (leftmost, green)
    local seg3Width = barWidth * bar3Frac
    self.sleekSegments[3]:ClearAllPoints()
    self.sleekSegments[3]:SetPoint("TOPLEFT", self.frames.sleekBar, "TOPLEFT", xOffset, -1)
    self.sleekSegments[3]:SetWidth(seg3Width)
    xOffset = xOffset + seg3Width

    -- +2 segment (middle, yellow)
    local seg2Width = barWidth * bar2Frac
    self.sleekSegments[2]:ClearAllPoints()
    self.sleekSegments[2]:SetPoint("TOPLEFT", self.frames.sleekBar, "TOPLEFT", xOffset, -1)
    self.sleekSegments[2]:SetWidth(seg2Width)
    xOffset = xOffset + seg2Width

    -- +1 segment (rightmost, blue/accent)
    local seg1Width = barWidth * bar1Frac
    self.sleekSegments[1]:ClearAllPoints()
    self.sleekSegments[1]:SetPoint("TOPLEFT", self.frames.sleekBar, "TOPLEFT", xOffset, -1)
    self.sleekSegments[1]:SetWidth(seg1Width)

    -- Update position marker
    self:UpdateSleekPositionMarker()
end

-- Update the position marker on the sleek bar
function MPlusTimer:UpdateSleekPositionMarker()
    if not self.frames.sleekPosMarker or not self.frames.sleekBar then return end

    local barWidth = SLEEK_BAR_WIDTH - 2
    local timeLimit = self.state.timeLimit
    local elapsed = self.state.timer

    if timeLimit <= 0 then
        self.frames.sleekPosMarker:Hide()
        return
    end

    local position = Clamp(elapsed / timeLimit, 0, 1)
    local xPos = 1 + (barWidth * position)

    self.frames.sleekPosMarker:ClearAllPoints()
    self.frames.sleekPosMarker:SetPoint("TOPLEFT", self.frames.sleekBar, "TOPLEFT", xPos - 1, 0)
    self.frames.sleekPosMarker:Show()
end

function MPlusTimer:UpdateLayoutFull(font, settings)
    local pad = FRAME_PADDING
    local vSpace = VERTICAL_SPACING
    local barWidth = BAR_WIDTH
    local barHeight = BAR_HEIGHT
    local barPad = BAR_PADDING
    local objSpace = OBJECTIVES_SPACING
    local iconSize = AFFIX_ICON_SIZE
    local iconSpacing = AFFIX_ICON_SPACING

    -- Update root frame width
    self.frames.root:SetWidth(FRAME_WIDTH)

    -- Hide Sleek-only elements
    if self.frames.sleekBar then self.frames.sleekBar:Hide() end
    if self.frames.paceText then self.frames.paceText:Hide() end

    -- Show regular bars container
    self.frames.bars:Show()
    for i = 1, 3 do
        self.bars[i].frame:Show()
    end

    local yOffset = pad

    -- Row 1: Dungeon name (left) + Deaths (right)
    self.frames.dungeonText:ClearAllPoints()
    self.frames.dungeonText:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
    self.frames.dungeonText:SetFont(font, FONT_SIZE_KEY, FONT_FLAGS)
    self.frames.dungeonText:SetJustifyH("LEFT")

    -- Deaths frame (for tooltip)
    self.frames.deathsFrame:ClearAllPoints()
    self.frames.deathsFrame:SetPoint("TOPRIGHT", self.frames.root, "TOPRIGHT", -pad, -yOffset)
    self.frames.deathsFrame:SetSize(80, FONT_SIZE_DEATHS + 4)
    self.frames.deathsText:SetFont(font, FONT_SIZE_DEATHS, FONT_FLAGS)

    yOffset = yOffset + FONT_SIZE_KEY + vSpace

    -- Row 2: Timer text (centered, large) - only if showTimer enabled
    if settings.showTimer then
        self.frames.timerText:ClearAllPoints()
        self.frames.timerText:SetPoint("TOP", self.frames.root, "TOP", 0, -yOffset)
        self.frames.timerText:SetFont(font, FONT_SIZE_TIMER, FONT_FLAGS)
        self.frames.timerText:SetJustifyH("CENTER")
        self.frames.timerText:Show()
        yOffset = yOffset + FONT_SIZE_TIMER + vSpace
    else
        self.frames.timerText:Hide()
    end

    -- Row 3: Key level (left) + affix icons (right) on SAME line
    self.frames.keyText:ClearAllPoints()
    self.frames.keyText:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)
    self.frames.keyText:SetFont(font, FONT_SIZE_KEY, FONT_FLAGS)
    self.frames.keyText:SetJustifyH("LEFT")
    self.frames.keyText:Show()

    -- Affix icons on right side
    if settings.showAffixes then
        self.frames.affixIcons:ClearAllPoints()
        self.frames.affixIcons:SetPoint("TOPRIGHT", self.frames.root, "TOPRIGHT", -pad, -yOffset + 2)
        self.frames.affixIcons:SetSize(iconSize * 4 + iconSpacing * 3, iconSize)
        self.frames.affixIcons:Show()

        -- Position individual icons (right to left for right alignment)
        for i, iconFrame in ipairs(self.affixIcons) do
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("RIGHT", self.frames.affixIcons, "RIGHT", -((i - 1) * (iconSize + iconSpacing)), 0)
        end
    else
        self.frames.affixIcons:Hide()
    end

    -- Hide legacy text-based affixes
    self.frames.affixText:Hide()

    yOffset = yOffset + math.max(FONT_SIZE_KEY, iconSize) + vSpace + 2

    -- Timer bars
    self.frames.bars:ClearAllPoints()
    self.frames.bars:SetPoint("TOP", self.frames.root, "TOP", 0, -yOffset)
    self.frames.bars:SetSize(barWidth, (barHeight + barPad) * 2)

    local bar1Frac, bar2Frac, bar3Frac = self:GetTimerBarFractions()
    local barX = 0

    -- +3 bar (leftmost)
    local bar3Width = barWidth * bar3Frac
    self.bars[3].frame:ClearAllPoints()
    self.bars[3].frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", barX, 0)
    self.bars[3].frame:SetSize(bar3Width, barHeight)
    self.bars[3].bar:SetPoint("TOPLEFT", 1, -1)
    self.bars[3].bar:SetPoint("BOTTOMRIGHT", -1, 1)
    barX = barX + bar3Width + 2

    -- +2 bar (middle)
    local bar2Width = barWidth * bar2Frac - 2
    self.bars[2].frame:ClearAllPoints()
    self.bars[2].frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", barX, 0)
    self.bars[2].frame:SetSize(bar2Width, barHeight)
    self.bars[2].bar:SetPoint("TOPLEFT", 1, -1)
    self.bars[2].bar:SetPoint("BOTTOMRIGHT", -1, 1)
    barX = barX + bar2Width + 2

    -- +1 bar (rightmost)
    local bar1Width = barWidth * bar1Frac - 2
    self.bars[1].frame:ClearAllPoints()
    self.bars[1].frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", barX, 0)
    self.bars[1].frame:SetSize(bar1Width, barHeight)
    self.bars[1].bar:SetPoint("TOPLEFT", 1, -1)
    self.bars[1].bar:SetPoint("BOTTOMRIGHT", -1, 1)

    yOffset = yOffset + barHeight + barPad

    -- Forces bar
    self.bars.forces.frame:ClearAllPoints()
    self.bars.forces.frame:SetPoint("TOPLEFT", self.frames.bars, "TOPLEFT", 0, -(barHeight + barPad))
    self.bars.forces.frame:SetSize(barWidth, barHeight)
    self.bars.forces.bar:SetPoint("TOPLEFT", 1, -1)
    self.bars.forces.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    if self.bars.forces.overlay then
        self.bars.forces.overlay:SetPoint("TOPLEFT", 1, -1)
        self.bars.forces.overlay:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    yOffset = yOffset + barHeight + barPad + vSpace

    -- Objectives
    self.frames.objectives:ClearAllPoints()
    self.frames.objectives:SetPoint("TOPLEFT", self.frames.root, "TOPLEFT", pad, -yOffset)

    local objY = 0
    for i = 1, 8 do
        self.objectives[i]:ClearAllPoints()
        self.objectives[i]:SetPoint("TOPLEFT", self.frames.objectives, "TOPLEFT", 0, -objY)
        self.objectives[i]:SetFont(font, FONT_SIZE_OBJECTIVE, FONT_FLAGS)
        local objText = self.objectives[i]:GetText()
        if objText and objText ~= "" then
            objY = objY + FONT_SIZE_OBJECTIVE + objSpace
        end
    end

    yOffset = yOffset + objY + pad

    self.frames.root:SetHeight(yOffset)
end

function MPlusTimer:GetTimerBarFractions()
    -- Returns fractions for +1, +2, +3 bars
    -- Default: 20% for +1, 20% for +2, 60% for +3
    local timeLimit = self.state.timeLimit
    if timeLimit <= 0 then
        return 0.2, 0.2, 0.6
    end

    local timeLimits = self.state.timeLimits
    if not timeLimits[1] then
        return 0.2, 0.2, 0.6
    end

    local fractions = {}
    for i = 1, 3 do
        local limit = timeLimits[i] or 0
        local nextLimit = timeLimits[i + 1] or 0
        local barMax = limit - nextLimit
        fractions[i] = barMax / timeLimit
    end

    return fractions[1] or 0.2, fractions[2] or 0.2, fractions[3] or 0.6
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
function MPlusTimer:RenderTimer()
    if not self.frames.timerText then return end

    local sleek = IsSleekMode()

    -- Update pace tracking
    self:UpdateTargetTier()

    local timerStr = FormatTime(self.state.timer) .. " / " .. FormatTime(self.state.timeLimit)

    if self.state.challengeCompleted then
        local completionStr = FormatTime(self.state.completionTimeMs / 1000)
        timerStr = completionStr .. " / " .. FormatTime(self.state.timeLimit)
    end

    self.frames.timerText:SetText(timerStr)

    -- Update pace text for Sleek mode
    if sleek and self.frames.paceText then
        local paceStr = FormatPaceOffset(self.state.paceOffset)
        local tier = self.state.currentTargetTier

        -- Color based on pace status
        if self.state.paceOffset > 30 then
            -- Ahead by more than 30s: green
            self.frames.paceText:SetTextColor(0.2, 0.85, 0.4)
        elseif self.state.paceOffset >= -30 then
            -- Within 30s: yellow
            self.frames.paceText:SetTextColor(0.95, 0.75, 0.2)
        else
            -- Behind by more than 30s: red
            self.frames.paceText:SetTextColor(1, 0.3, 0.3)
        end

        -- Add tier indicator
        if tier > 0 then
            paceStr = paceStr .. " (+" .. tier .. ")"
        else
            paceStr = paceStr .. " (OT)"
        end

        self.frames.paceText:SetText(paceStr)

        -- Update sleek bar position marker
        self:UpdateSleekPositionMarker()
    end

    -- Update bar values (Full and Compact modes)
    if not sleek then
        for i = 1, 3 do
            local limit = self.state.timeLimits[i] or self.state.timeLimit
            local nextLimit = self.state.timeLimits[i + 1] or 0
            local barMax = limit - nextLimit
            local timeRemaining = limit - self.state.timer
            local barElapsed = barMax - timeRemaining
            local barValue = Clamp(barElapsed / barMax, 0, 1)

            self.bars[i].bar:SetValue(barValue)

            -- Time remaining text
            local timeText = FormatTime(math.abs(timeRemaining))
            if timeRemaining < 0 and i == 1 then
                timeText = "-" .. timeText
            elseif timeRemaining < 0 then
                timeText = ""
            end
            self.bars[i].text:SetText(timeText)
        end
    end
end

function MPlusTimer:RenderDeaths()
    if not self.frames.deathsText then return end

    local settings = GetSettings()
    if not settings.showDeaths then
        self.frames.deathsText:SetText("")
        return
    end

    local sleek = IsSleekMode()

    if self.state.deathCount > 0 then
        local deathStr
        if sleek then
            -- Sleek mode: compact format "3 -15s"
            deathStr = string.format("%d -%ds",
                self.state.deathCount,
                self.state.deathTimeLost)
        else
            -- Full/Compact mode: verbose format
            deathStr = string.format("Deaths: %d (-%s)",
                self.state.deathCount,
                FormatTime(self.state.deathTimeLost))
        end
        self.frames.deathsText:SetText(deathStr)
    else
        self.frames.deathsText:SetText("")
    end
end

function MPlusTimer:RenderKeyDetails()
    if not self.frames.keyText then return end

    local settings = GetSettings()
    local compact = IsCompactMode()
    local sleek = IsSleekMode()

    if compact or sleek then
        -- Compact/Sleek mode: "+15 Dungeon Name" in dungeonText
        if self.frames.dungeonText then
            local headerText = string.format("+%d %s", self.state.level, self.state.dungeonName or "")
            self.frames.dungeonText:SetText(headerText)
        end
    else
        -- Full mode: separate dungeon name and key level
        if self.frames.dungeonText then
            self.frames.dungeonText:SetText(self.state.dungeonName or "")
        end
        self.frames.keyText:SetText(string.format("[%d]", self.state.level))
    end

    -- Render affix icons (all modes)
    self:RenderAffixIcons()
end

function MPlusTimer:RenderAffixIcons()
    local settings = GetSettings()

    -- Hide all icons first
    for i = 1, 4 do
        if self.affixIcons[i] then
            self.affixIcons[i]:Hide()
            self.affixIcons[i].affixID = nil
        end
    end

    if not settings.showAffixes then return end

    local affixIDs = self.state.affixIDs or {}

    for i, affixID in ipairs(affixIDs) do
        if i <= 4 and self.affixIcons[i] then
            local iconFrame = self.affixIcons[i]
            local name, desc, iconTexture = C_ChallengeMode.GetAffixInfo(affixID)

            if iconTexture then
                iconFrame.icon:SetTexture(iconTexture)
                iconFrame.affixID = affixID
                iconFrame:Show()
            end
        end
    end
end

function MPlusTimer:RenderForces()
    if not self.bars.forces then return end

    local bar = self.bars.forces
    bar.bar:SetValue(self.state.currentPercent)

    -- Format: "45.32% (123/273)"
    local percentStr = string.format("%.2f%%", self.state.currentPercent * 100)
    local countStr = string.format("(%d/%d)", self.state.currentCount, self.state.totalCount)
    bar.text:SetText(percentStr .. " " .. countStr)

    -- Update pull overlay texture
    if bar.overlay then
        if self.state.pullPercent > 0 and self.state.currentPercent < 1 then
            -- Position overlay to start at current percent and extend by pull amount
            local barWidth = bar.bar:GetWidth()
            local startX = self.state.currentPercent * barWidth
            local pullWidth = math.min(self.state.pullPercent, 1 - self.state.currentPercent) * barWidth

            bar.overlay:ClearAllPoints()
            bar.overlay:SetPoint("LEFT", bar.bar, "LEFT", startX, 0)
            bar.overlay:SetWidth(math.max(1, pullWidth))
            bar.overlay:Show()
        else
            bar.overlay:Hide()
        end
    end
end

function MPlusTimer:RenderObjectives()
    if not self.frames.objectives then return end

    local settings = GetSettings()
    local sleek = IsSleekMode()

    -- Clear all and reset colors
    for i = 1, 8 do
        self.objectives[i]:SetText("")
        self.objectives[i].completed = nil
    end

    if not settings.showObjectives then return end

    local totalBosses = #self.state.objectivesList
    local targetTime = self.state.currentTargetTime

    for i, obj in ipairs(self.state.objectivesList) do
        if i <= 8 then
            local indicator = obj.time and "|cFF66FF66+|r " or "|cFFAAAAAA-|r "  -- Green + or grey -
            local text = obj.name or "Unknown"

            if sleek then
                -- Sleek mode: Show differential and completion time
                if obj.time then
                    -- Calculate expected time for this boss
                    local expectedTime = (i / totalBosses) * targetTime
                    local differential = obj.time - expectedTime

                    -- Color code the differential
                    local diffColor
                    if differential < -30 then
                        diffColor = "|cFF33D98C"  -- Green (ahead by more than 30s)
                    elseif differential <= 30 then
                        diffColor = "|cFFF0C020"  -- Yellow (within 30s)
                    else
                        diffColor = "|cFFFF4D4D"  -- Red (behind by more than 30s)
                    end

                    local diffStr = FormatPaceOffset(-differential)  -- Negate so + means ahead
                    text = indicator .. text .. " " .. diffColor .. diffStr .. "|r |cFF888888" .. FormatTime(obj.time) .. "|r"
                else
                    text = indicator .. text
                end
            else
                -- Full/Compact mode: original format
                if obj.time then
                    text = indicator .. text .. " |cFF888888[" .. FormatTime(obj.time) .. "]|r"
                else
                    text = indicator .. text
                end
            end

            self.objectives[i]:SetText(text)
            self.objectives[i].completed = obj.time ~= nil
        end
    end

    self:UpdateLayout()
end

function MPlusTimer:RenderAll()
    self:RenderTimer()
    self:RenderDeaths()
    self:RenderKeyDetails()
    self:RenderForces()
    self:RenderObjectives()
end

---------------------------------------------------------------------------
-- Timer Loop
---------------------------------------------------------------------------
local sinceLastUpdate = 0

function MPlusTimer:OnTimerTick(elapsed)
    sinceLastUpdate = sinceLastUpdate + elapsed
    if sinceLastUpdate < UPDATE_INTERVAL then return end
    sinceLastUpdate = 0

    -- Get current timer from game
    self.state.timer = select(2, GetWorldElapsedTime(1)) or 0

    -- First tick after timer starts
    if self.state.timer > 0 and not self.state.timerStarted then
        self.state.timerStarted = true
        self:RenderForces()
        self:RenderObjectives()
    end

    self:RenderTimer()
end

function MPlusTimer:StartTimerLoop()
    if self.state.timerLoopRunning then return end
    self.state.timerLoopRunning = true
    sinceLastUpdate = 0

    self.frames.root:SetScript("OnUpdate", function(_, elapsed)
        MPlusTimer:OnTimerTick(elapsed)
    end)
end

function MPlusTimer:StopTimerLoop()
    self.state.timerLoopRunning = false
    sinceLastUpdate = 0

    if self.frames.root then
        self.frames.root:SetScript("OnUpdate", nil)
    end
end

---------------------------------------------------------------------------
-- State Management
---------------------------------------------------------------------------
function MPlusTimer:ResetState()
    self.state = DeepCopy(defaultState)
end

function MPlusTimer:SetTimeLimit(limit)
    self.state.timeLimit = limit
    -- Calculate +1/+2/+3 thresholds (100%/80%/60% of time limit)
    self.state.timeLimits = {
        [1] = limit,           -- +1 at 100% (full time)
        [2] = limit * 0.8,     -- +2 at 80%
        [3] = limit * 0.6,     -- +3 at 60%
    }
    -- Initialize pace tracking to +3 target
    self.state.currentTargetTier = 3
    self.state.currentTargetTime = self.state.timeLimits[3] or limit * 0.6
end

-- Update which reward tier we're tracking against (dynamic pace indicator)
function MPlusTimer:UpdateTargetTier()
    local elapsed = self.state.timer
    local limits = self.state.timeLimits

    if not limits[1] then
        self.state.currentTargetTier = 0
        self.state.currentTargetTime = self.state.timeLimit
        self.state.paceOffset = self.state.timeLimit - elapsed
        return
    end

    -- Determine best achievable tier based on elapsed time
    if elapsed < (limits[3] or 0) then
        -- Still can get +3
        self.state.currentTargetTier = 3
        self.state.currentTargetTime = limits[3]
    elseif elapsed < (limits[2] or 0) then
        -- Missed +3, can still get +2
        self.state.currentTargetTier = 2
        self.state.currentTargetTime = limits[2]
    elseif elapsed < (limits[1] or 0) then
        -- Missed +2, can still get +1
        self.state.currentTargetTier = 1
        self.state.currentTargetTime = limits[1]
    else
        -- Overtime - past all thresholds
        self.state.currentTargetTier = 0
        self.state.currentTargetTime = self.state.timeLimit
    end

    -- Calculate pace offset (positive = ahead, negative = behind)
    self.state.paceOffset = self.state.currentTargetTime - elapsed
end

function MPlusTimer:SetKeyDetails(level, affixes, affixIDs, mapID, dungeonName)
    self.state.level = level or 0
    self.state.affixes = affixes or {}
    self.state.affixIDs = affixIDs or {}
    self.state.mapID = mapID
    self.state.dungeonName = dungeonName or ""
    self:RenderKeyDetails()
end

function MPlusTimer:SetDeathCount(count, timeLost)
    self.state.deathCount = count or 0
    self.state.deathTimeLost = timeLost or 0
    self:RenderDeaths()
end

function MPlusTimer:SetForces(current, total)
    self.state.currentCount = current or 0
    self.state.totalCount = total or 1
    self.state.currentPercent = self.state.totalCount > 0
        and (self.state.currentCount / self.state.totalCount)
        or 0
    self:RenderForces()
end

function MPlusTimer:SetObjectives(objectives)
    self.state.objectivesList = objectives or {}
    self:RenderObjectives()
end

---------------------------------------------------------------------------
-- Scaling
---------------------------------------------------------------------------
function MPlusTimer:ApplyScale()
    if not self.frames.root then return end

    local settings = GetSettings()
    local scale = settings.scale or 1.0

    -- Store current position before scale change
    local point, _, relPoint, x, y = self.frames.root:GetPoint()

    self.frames.root:SetScale(scale)

    -- Re-anchor to maintain visual position
    if point then
        self.frames.root:ClearAllPoints()
        self.frames.root:SetPoint(point, UIParent, relPoint, x, y)
    end
end

---------------------------------------------------------------------------
-- Show/Hide
---------------------------------------------------------------------------
function MPlusTimer:Show()
    if not self.frames.root then
        self:CreateFrames()
    end

    self:UpdateLayout()
    self:ApplyScale()
    self:RenderAll()
    self.frames.root:Show()

    -- Trigger skin application
    if _G.QUI_ApplyMPlusTimerSkin then
        _G.QUI_ApplyMPlusTimerSkin()
    end

    -- Hide Blizzard's timer
    if ScenarioObjectiveTracker then
        ScenarioObjectiveTracker:Hide()
    end
end

function MPlusTimer:Hide()
    if self.frames.root then
        self.frames.root:Hide()
    end
    self:StopTimerLoop()

    -- Show Blizzard's timer again
    if ScenarioObjectiveTracker and ObjectiveTrackerFrame then
        ObjectiveTrackerFrame:Update()
    end
end

---------------------------------------------------------------------------
-- Demo Mode (for testing outside M+)
---------------------------------------------------------------------------
function MPlusTimer:EnableDemoMode()
    if self.state.inChallenge then
        print("|cFF34D4E8[QUI M+ Timer]|r Can't enable demo mode during active M+!")
        return
    end

    if self.state.demoModeActive then return end

    self:ResetState()
    self.state.demoModeActive = true

    -- Set demo data
    self:SetTimeLimit(32 * 60)  -- 32 minutes
    self:SetKeyDetails(11, {"Tyrannical", "Storming", "Fortified"}, {9, 124, 10}, 1, "Jade Serpent")
    self:SetDeathCount(3, 15)
    self:SetForces(285, 289)

    self:SetObjectives({
        { name = "Wise Mari", time = 328 },
        { name = "Lorewalker Stonestep", time = 683 },
        { name = "Liu Flameheart", time = 1428 },
        { name = "Sha of Doubt", time = nil },
    })

    self.state.timer = 23 * 60 + 56  -- 23:56 elapsed (demo value)

    self:Show()
    self:StartTimerLoop()

    print("|cFF34D4E8[QUI M+ Timer]|r Demo mode enabled. Type /qmpt demo to disable.")
end

function MPlusTimer:DisableDemoMode()
    if not self.state.demoModeActive then return end

    self.state.demoModeActive = false
    self:Hide()
    self:ResetState()

    print("|cFF34D4E8[QUI M+ Timer]|r Demo mode disabled.")
end

function MPlusTimer:ToggleDemoMode()
    if self.state.demoModeActive then
        self:DisableDemoMode()
    else
        self:EnableDemoMode()
    end
end

---------------------------------------------------------------------------
-- Challenge Mode Event Handling
---------------------------------------------------------------------------
function MPlusTimer:EnableChallengeMode()
    if self.state.inChallenge then return end

    self:ResetState()
    self.state.inChallenge = true

    -- Get key info
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    local dungeonName = ""
    if mapID then
        self.state.mapID = mapID
        local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
        dungeonName = name or ""
        if timeLimit then
            self:SetTimeLimit(timeLimit)
        end
    end

    -- Get active keystone info
    local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()
    if level then
        local affixNames = {}
        for _, affixID in ipairs(affixes or {}) do
            local name = C_ChallengeMode.GetAffixInfo(affixID)
            if name then
                table.insert(affixNames, name)
            end
        end
        self:SetKeyDetails(level, affixNames, affixes, mapID, dungeonName)
    end

    -- Get initial death count
    local deaths, timeLost = C_ChallengeMode.GetDeathCount()
    self:SetDeathCount(deaths, timeLost)

    -- Update objectives
    self:UpdateObjectives()

    self:Show()
    self:StartTimerLoop()
end

function MPlusTimer:DisableChallengeMode()
    if not self.state.inChallenge then return end

    self.state.inChallenge = false
    self:StopTimerLoop()
    self:Hide()
    self:ResetState()
end

function MPlusTimer:CompleteChallenge()
    if not self.state.inChallenge then return end

    self.state.challengeCompleted = true

    local info = C_ChallengeMode.GetChallengeCompletionInfo()
    if info then
        self.state.completionTimeMs = info.time or 0
        self.state.completedOnTime = info.onTime or false
    end

    self:StopTimerLoop()
    self:RenderTimer()
end

function MPlusTimer:UpdateObjectives()
    local objectives = {}

    local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
    local numCriteria = stepInfo and stepInfo.numCriteria or 0
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        local criteriaString = info and info.description
        local completed = info and info.completed
        local isWeightedProgress = info and info.isWeightedProgress

        if criteriaString and not isWeightedProgress then
            local obj = { name = criteriaString, time = nil }
            if completed then
                -- Try to get completion time from scenario
                obj.time = self.state.timer
            end
            table.insert(objectives, obj)
        end
    end

    self:SetObjectives(objectives)
end

function MPlusTimer:UpdateForces()
    local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
    local numCriteria = stepInfo and stepInfo.numCriteria or 0

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info and info.isWeightedProgress then
            local quantityString = info.quantityString
            local totalQuantity = info.totalQuantity
            if quantityString then
                local current = tonumber(quantityString:match("(%d+)")) or 0
                self:SetForces(current, totalQuantity or 100)
            end
            break
        end
    end
end

function MPlusTimer:CheckForChallengeMode()
    local _, instanceType, difficulty = GetInstanceInfo()
    local inChallenge = difficulty == 8 and instanceType == "party"

    if inChallenge and not self.state.inChallenge and not self.state.demoModeActive then
        -- Only enable if timer is enabled in settings
        if IsEnabled() then
            self:EnableChallengeMode()
        end
    elseif not inChallenge and self.state.inChallenge then
        self:DisableChallengeMode()
    end
end

---------------------------------------------------------------------------
-- Event Registration
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Initialize on addon load
        C_Timer.After(0.5, function()
            if IsEnabled() then
                MPlusTimer:CreateFrames()
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            MPlusTimer:CheckForChallengeMode()
        end)

    elseif event == "CHALLENGE_MODE_START" then
        if IsEnabled() then
            MPlusTimer:EnableChallengeMode()
        end

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        MPlusTimer:CompleteChallenge()

    elseif event == "CHALLENGE_MODE_RESET" then
        MPlusTimer:DisableChallengeMode()

    elseif event == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        local deaths, timeLost = C_ChallengeMode.GetDeathCount()
        MPlusTimer:SetDeathCount(deaths, timeLost)

    elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_POI_UPDATE" then
        if MPlusTimer.state.inChallenge then
            MPlusTimer:UpdateObjectives()
            MPlusTimer:UpdateForces()
        end

    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(0.5, function()
            MPlusTimer:CheckForChallengeMode()
        end)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
eventFrame:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
eventFrame:RegisterEvent("SCENARIO_POI_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

---------------------------------------------------------------------------
-- Slash Command
---------------------------------------------------------------------------
SLASH_QUIIMPLUSTIMER1 = "/qmpt"
SlashCmdList["QUIIMPLUSTIMER"] = function(msg)
    local cmd = msg:lower():trim()

    if cmd == "demo" then
        MPlusTimer:ToggleDemoMode()
    elseif cmd == "show" then
        MPlusTimer:Show()
    elseif cmd == "hide" then
        MPlusTimer:Hide()
    else
        print("|cFF34D4E8[QUI M+ Timer]|r Commands:")
        print("  /qmpt demo - Toggle demo mode")
        print("  /qmpt show - Show timer")
        print("  /qmpt hide - Hide timer")
    end
end

---------------------------------------------------------------------------
-- Expose for skinning
---------------------------------------------------------------------------
_G.QUI_MPlusTimer = MPlusTimer
