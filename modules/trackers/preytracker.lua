--[[
    QUI Prey Tracker Module
    Tracks prey hunting progress (WoW Midnight 12.0+ prey system)
    with a progress bar, hunt scanner, currency tracker, and ambush alerts.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit
local LSM = ns.LSM
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local SkinBase = ns.SkinBase
local GetSettings = Helpers.CreateDBGetter("preyTracker")
local GetCore = Helpers.GetCore

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------

local PREY_WIDGET_TYPE = 31 -- fallback if Enum not available
local WIDGET_SHOWN = 1      -- fallback for Enum.WidgetShownState.Shown
local PREY_CURRENCIES = {
    { id = 3392, name = "Remnant of Anguish" },
    { id = 3316, name = "Voidlight Marl" },
    { id = 3383, name = "Adventurer Dawncrest" },
    { id = 3341, name = "Veteran Dawncrest" },
    { id = 3343, name = "Champion Dawncrest" },
}
local TICK_THIRDS = { 0.333, 0.666 }
local TICK_QUARTERS = { 0.25, 0.50, 0.75 }
local UPDATE_THROTTLE = 0.1
local AMBUSH_PATTERN = "ambush"

local FONT_FLAGS = "OUTLINE"
local MAX_TICKS = 3
local COMPLETION_HOLD_TIME = 8
local SPARK_WIDTH = 32
local SPARK_HEIGHT_MULT = 2.5
local DEFAULT_FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local string_format = string.format

local TEXT_FORMATS = {
    stage_pct  = function(stage, pct, name) return string_format("Stage %d — %d%%", stage, pct) end,
    pct_only   = function(stage, pct, name) return string_format("%d%%", pct) end,
    stage_only = function(stage, pct, name) return string_format("Stage %d", stage) end,
    name_pct   = function(stage, pct, name) return string_format("%s — %d%%", name or "Prey", pct) end,
}

---------------------------------------------------------------------------
-- PERFORMANCE LOCALS
---------------------------------------------------------------------------

local floor = math.floor
local max = math.max
local min = math.min
local pcall = pcall
local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = GameTooltip

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------

local State = {
    frame = nil,
    isPreviewMode = false,
    -- Quest
    activeQuestID = nil,
    preyName = nil,
    difficulty = nil,
    -- Progress (raw widget/quest data)
    progressState = nil,
    progressPercent = nil,
    lastWidgetSeenAt = 0,
    -- Display (derived from raw state in UpdateBarDisplay)
    currentStage = 0,
    currentProgress = 0,
    cachedWidgetID = nil,
    stageSoundPlayed = {},
    -- Zone
    isInPreyZone = false,
    preyZoneMapID = nil,
    preyZoneName = nil,
    -- Hunt scanner
    availableHunts = {},
    isAtHuntTable = false,
    huntPanel = nil,
    -- Currency
    sessionStart = {},
    -- Ambush
    ambushActiveUntil = 0,
    -- Timing
    elapsed = 0,
    -- Deferred geometry
    deferredGeometry = false,
    -- Completion hold
    completionUntil = 0,
    -- Initialization
    initialized = false,
    -- Blizzard widget suppression
    widgetSuppressed = false,
}
local RefreshContinuousUpdateScript

---------------------------------------------------------------------------
-- API GUARDS
---------------------------------------------------------------------------

local HasPreyAPI = C_QuestLog and type(C_QuestLog.GetActivePreyQuest) == "function"
local HasWidgetAPI = C_UIWidgetManager and type(C_UIWidgetManager.GetAllWidgetsBySetID) == "function"
local HasPreyWidgetAPI = C_UIWidgetManager and type(C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo) == "function"
local HasCurrencyAPI = C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function"
local HasMapAPI = C_Map and type(C_Map.GetMapInfo) == "function"
local HasTaskAPI = C_TaskQuest and type(C_TaskQuest.GetQuestZoneID) == "function"

---------------------------------------------------------------------------
-- UTILITY
---------------------------------------------------------------------------

local SafeToNumber = Helpers.SafeToNumber
local SafeValue = Helpers.SafeValue
local widgetSideState = setmetatable({}, { __mode = "k" })
local widgetAnimationState = setmetatable({}, { __mode = "k" })
local pendingWidgetUpdate = false

local function GetWidgetState(target)
    local state = widgetSideState[target]
    if not state then
        state = {}
        widgetSideState[target] = state
    end
    return state
end

local function SafeCall(func, ...)
    if not func then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
    return nil
end

local function GetPreyWidgetType()
    if Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.PreyHuntProgress then
        return Enum.UIWidgetVisualizationType.PreyHuntProgress
    end
    return PREY_WIDGET_TYPE
end

local function GetWidgetShownState()
    if Enum and Enum.WidgetShownState and Enum.WidgetShownState.Shown then
        return Enum.WidgetShownState.Shown
    end
    return WIDGET_SHOWN
end

local function GetCandidateWidgetSetIDs()
    local ids = {}
    if C_UIWidgetManager then
        if C_UIWidgetManager.GetTopCenterWidgetSetID then
            ids[#ids + 1] = C_UIWidgetManager.GetTopCenterWidgetSetID()
        end
        if C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
            ids[#ids + 1] = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
        end
        if C_UIWidgetManager.GetBelowMinimapWidgetSetID then
            ids[#ids + 1] = C_UIWidgetManager.GetBelowMinimapWidgetSetID()
        end
        if C_UIWidgetManager.GetPowerBarWidgetSetID then
            ids[#ids + 1] = C_UIWidgetManager.GetPowerBarWidgetSetID()
        end
    end
    return ids
end

local WIDGET_CONTAINER_GLOBALS = {
    "UIWidgetTopCenterContainerFrame",
    "UIWidgetObjectiveTrackerContainerFrame",
    "UIWidgetBelowMinimapContainerFrame",
    "UIWidgetPowerBarContainerFrame",
}

local function TryGetWidgetFrameByID(container, widgetID)
    if not container or not widgetID then return nil end
    if container.widgetFrames then
        for _, frame in pairs(container.widgetFrames) do
            if frame.widgetID == widgetID then
                return frame
            end
        end
    end
    return nil
end

local function IsInInstanceZone()
    local _, instanceType = IsInInstance()
    return instanceType == "party" or instanceType == "raid" or instanceType == "arena" or instanceType == "pvp" or instanceType == "scenario"
end

---------------------------------------------------------------------------
-- QUEST & WIDGET DATA
---------------------------------------------------------------------------

local function GetActivePreyQuest()
    if not HasPreyAPI then return nil end
    return SafeCall(C_QuestLog.GetActivePreyQuest)
end

local function ScanPreyWidgets()
    if not HasWidgetAPI or not HasPreyWidgetAPI then return nil, nil end

    local preyWidgetType = GetPreyWidgetType()
    local shownState = GetWidgetShownState()

    for _, setID in ipairs(GetCandidateWidgetSetIDs()) do
        local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
        if ok and widgets then
            for _, widget in ipairs(widgets) do
                if widget and widget.widgetType == preyWidgetType and widget.widgetID then
                    local ok2, info = pcall(C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo, widget.widgetID)
                    if ok2 and info and info.shownState == shownState then
                        return widget.widgetID, info
                    end
                end
            end
        end
    end

    return nil, nil
end

local function NormalizePercent(value)
    if type(value) ~= "number" then return nil end
    if value >= 0 and value <= 1 then
        return max(0, min(100, value * 100))
    end
    return max(0, min(100, value))
end

local function ExtractProgressPercent(info, tooltip)
    if not info then return nil end

    -- Try direct percentage fields in priority order
    local directFields = {
        "progressPercentage", "progressPercent", "fillPercentage",
        "percentage", "percent", "progress", "progressValue",
    }
    for _, field in ipairs(directFields) do
        local val = info[field]
        if type(val) == "number" then
            local pct = NormalizePercent(val)
            if pct then return pct end
        end
    end

    -- Try value/max pairs
    local valueFields = { "barValue", "value", "currentValue" }
    local maxFields = { "barMax", "maxValue", "totalValue", "total", "max" }
    for _, vf in ipairs(valueFields) do
        local current = info[vf]
        if type(current) == "number" then
            for _, mf in ipairs(maxFields) do
                local maxVal = info[mf]
                if type(maxVal) == "number" and maxVal > 0 then
                    return max(0, min(100, (current / maxVal) * 100))
                end
            end
        end
    end

    -- Scan all keys for anything containing "percent" or current/max pairs
    local currentValues = {}
    local maxValues = {}
    for key, value in pairs(info) do
        if type(value) == "number" then
            local keyText = tostring(key):lower()
            if keyText:find("percent", 1, true) then
                local pct = NormalizePercent(value)
                if pct then return pct end
            end
            if value >= 0 then
                if keyText:find("current", 1, true) or keyText:find("value", 1, true)
                    or keyText:find("progress", 1, true) or keyText:find("fulfilled", 1, true)
                    or keyText:find("completed", 1, true) then
                    currentValues[#currentValues + 1] = value
                end
                if keyText:find("max", 1, true) or keyText:find("total", 1, true)
                    or keyText:find("required", 1, true) then
                    maxValues[#maxValues + 1] = value
                end
            end
        end
    end
    for _, current in ipairs(currentValues) do
        for _, maxVal in ipairs(maxValues) do
            if maxVal > 0 and current <= maxVal then
                local pct = max(0, min(100, (current / maxVal) * 100))
                if pct >= 0 and pct <= 100 then return pct end
            end
        end
    end

    -- Try parsing percentage from tooltip text
    local tooltipStr = tooltip or (info.tooltip and tostring(info.tooltip)) or nil
    if tooltipStr and type(tooltipStr) == "string" then
        local match = tooltipStr:match("(%d+)%s*%%")
        if match then
            local pct = SafeToNumber(match, 0)
            if pct > 0 then return max(0, min(100, pct)) end
        end
    end

    return nil
end

local function ExtractQuestObjectivePercent(questID)
    if not questID then return nil end
    if not C_QuestLog or not C_QuestLog.GetQuestObjectives then return nil end

    -- Try quest progress bar first
    local questBarPct = nil
    local ok, rawPct = pcall(GetQuestProgressBarPercent, questID)
    if ok and rawPct then
        local val = SafeToNumber(rawPct, nil)
        if val and val > 0 then
            questBarPct = max(0, min(100, val))
        end
    end

    -- Try quest objectives for granular progress
    local ok2, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok2 or type(objectives) ~= "table" or #objectives == 0 then
        return questBarPct
    end

    local totalFulfilled = 0
    local totalRequired = 0
    local anyNumericObjective = false

    for _, objective in ipairs(objectives) do
        if type(objective) == "table" then
            local fulfilled = SafeToNumber(objective.numFulfilled, nil) or SafeToNumber(objective.fulfilled, nil)
            local required = SafeToNumber(objective.numRequired, nil) or SafeToNumber(objective.required, nil)

            -- Handle boolean finished with no required count
            if fulfilled and not required and objective.finished ~= nil then
                required = 1
                fulfilled = objective.finished and 1 or max(0, fulfilled)
            end

            if fulfilled and required and required > 0 then
                anyNumericObjective = true
                totalFulfilled = totalFulfilled + max(0, fulfilled)
                totalRequired = totalRequired + max(0, required)
            else
                -- Try parsing from text like "5/10" or "45%"
                local text = objective.text
                if type(text) == "string" and text ~= "" then
                    local curText, maxText = text:match("(%d+)%s*/%s*(%d+)")
                    local curVal = SafeToNumber(curText, nil)
                    local maxVal = SafeToNumber(maxText, nil)
                    if curVal and maxVal and maxVal > 0 then
                        anyNumericObjective = true
                        totalFulfilled = totalFulfilled + max(0, curVal)
                        totalRequired = totalRequired + max(0, maxVal)
                    else
                        local pctText = text:match("(%d+)%s*%%")
                        local pctVal = SafeToNumber(pctText, nil)
                        if pctVal then
                            return max(0, min(100, pctVal))
                        end
                    end
                end
            end
        end
    end

    local objectivePct = nil
    if anyNumericObjective and totalRequired > 0 then
        objectivePct = max(0, min(100, (totalFulfilled / totalRequired) * 100))
    end

    -- Return the best of objective % and quest bar %
    if objectivePct and questBarPct then
        return max(objectivePct, questBarPct)
    end
    return objectivePct or questBarPct
end

local STAGE_FALLBACK_QUARTERS = { [1] = 25, [2] = 50, [3] = 75, [4] = 100 }
local STAGE_FALLBACK_THIRDS = { [1] = 0, [2] = 33, [3] = 66, [4] = 100 }

local function GetStageFallbackPercent(stage)
    local settings = GetSettings()
    local tickStyle = settings and settings.tickStyle
    local lookup = (tickStyle == "quarters") and STAGE_FALLBACK_QUARTERS or STAGE_FALLBACK_THIRDS
    return lookup[stage] or 0
end

local PREY_PROGRESS_FINAL = 3

local function DetermineStageFromProgressState(progressState)
    if progressState == nil or progressState == 0 then return 1 end
    if progressState == 1 then return 2 end
    if progressState == 2 then return 3 end
    if progressState == PREY_PROGRESS_FINAL then return 4 end
    return 1
end

local function DetermineStageFromPercent(pct)
    if pct >= 75 then return 4
    elseif pct >= 50 then return 3
    elseif pct >= 25 then return 2
    else return 1
    end
end

local function DetectPreyZone(questID)
    if not questID then return end

    -- Try task quest zone first
    if HasTaskAPI then
        local zoneID = SafeCall(C_TaskQuest.GetQuestZoneID, questID)
        if zoneID and zoneID > 0 then
            State.preyZoneMapID = zoneID
            if HasMapAPI then
                local info = SafeCall(C_Map.GetMapInfo, zoneID)
                if info then State.preyZoneName = info.name end
            end
            return
        end
    end

    -- Fall back to best map for player, walk parents
    if HasMapAPI then
        local mapID = SafeCall(C_Map.GetBestMapForUnit, "player")
        if mapID then
            State.preyZoneMapID = mapID
            local info = SafeCall(C_Map.GetMapInfo, mapID)
            if info then State.preyZoneName = info.name end
        end
    end
end

local function CheckInPreyZone()
    if not State.preyZoneMapID then return true end -- if we can't determine zone, assume yes
    if not HasMapAPI then return true end

    local currentMap = SafeCall(C_Map.GetBestMapForUnit, "player")
    if not currentMap then return true end

    -- Walk parent chain to see if we're in the same zone hierarchy
    local checkMap = currentMap
    for _ = 1, 20 do
        if checkMap == State.preyZoneMapID then
            return true
        end
        local info = SafeCall(C_Map.GetMapInfo, checkMap)
        if not info or not info.parentMapID or info.parentMapID == 0 then break end
        checkMap = info.parentMapID
    end

    return false
end

local function ExtractPreyInfo(questID)
    if not questID then return end
    if not C_QuestLog or not C_QuestLog.GetTitleForQuestID then return end

    local title = SafeCall(C_QuestLog.GetTitleForQuestID, questID)
    if not title then return end

    State.preyName = title

    -- Try to parse difficulty from title (e.g., "Hunt: [Name] (Nightmare)")
    local difficulty = title:match("%((%w+)%)%s*$")
    if difficulty then
        State.difficulty = difficulty
    end
end

---------------------------------------------------------------------------
-- BAR CREATION
---------------------------------------------------------------------------

local function GetBarColors()
    local settings = GetSettings()
    if not settings then return 0.2, 0.8, 0.2, 1, 0.1, 0.1, 0.1, 0.8, 0, 0, 0, 1 end

    -- Bar fill color
    local br, bg, bb, ba
    if settings.barUseClassColor then
        br, bg, bb = Helpers.GetPlayerClassColor()
        ba = 1
    elseif settings.barUseAccentColor then
        br, bg, bb, ba = Helpers.GetSkinAccentColor()
    elseif type(settings.barColor) == "table" then
        br = settings.barColor[1] or 0.2
        bg = settings.barColor[2] or 0.8
        bb = settings.barColor[3] or 0.2
        ba = settings.barColor[4] or 1
    else
        br, bg, bb, ba = 0.2, 0.8, 0.2, 1
    end

    -- Background color
    local bgr, bgg, bgb, bga
    if settings.barBgOverride and type(settings.barBackgroundColor) == "table" then
        bgr = settings.barBackgroundColor[1] or 0.1
        bgg = settings.barBackgroundColor[2] or 0.1
        bgb = settings.barBackgroundColor[3] or 0.1
        bga = settings.barBackgroundColor[4] or 0.8
    else
        _, _, _, _, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    end

    -- Border color
    local bdr, bdg, bdb, bda
    if settings.borderOverride then
        if settings.borderUseClassColor then
            bdr, bdg, bdb = Helpers.GetPlayerClassColor()
            bda = 1
        elseif type(settings.borderColor) == "table" then
            bdr = settings.borderColor[1] or 0
            bdg = settings.borderColor[2] or 0
            bdb = settings.borderColor[3] or 0
            bda = settings.borderColor[4] or 1
        else
            bdr, bdg, bdb, bda = 0, 0, 0, 1
        end
    else
        bdr, bdg, bdb, bda = Helpers.GetSkinBorderColor()
    end

    return br, bg, bb, ba, bgr, bgg, bgb, bga, bdr, bdg, bdb, bda
end

local function CreatePreyBar()
    if State.frame then return State.frame end

    local settings = GetSettings()
    local width = (settings and settings.width) or 250
    local height = (settings and settings.height) or 20

    local br, bg, bb, ba, bgr, bgg, bgb, bga, bdr, bdg, bdb, bda = GetBarColors()

    -- Create main StatusBar
    local bar = CreateFrame("StatusBar", "QUI_PreyTracker", UIParent)
    bar:SetSize(width, height)
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
    bar:SetStatusBarTexture(DEFAULT_FALLBACK_TEXTURE)
    bar:SetStatusBarColor(br, bg, bb, ba)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:Hide()

    bar:SetMovable(true)
    bar:SetClampedToScreen(true)

    -- Background texture
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(DEFAULT_FALLBACK_TEXTURE)
    bar.bg:SetVertexColor(bgr, bgg, bgb, bga)
    if UIKit and UIKit.DisablePixelSnap then
        UIKit.DisablePixelSnap(bar.bg)
    end

    -- UIKit border
    if UIKit and UIKit.CreateBackdropBorder then
        local borderSize = (settings and settings.borderSize) or 1
        bar.Border = UIKit.CreateBackdropBorder(bar, borderSize, bdr, bdg, bdb, bda)
    end

    -- Tick marks (up to 3)
    bar.ticks = {}
    for i = 1, MAX_TICKS do
        local tick = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        tick:SetTexture(DEFAULT_FALLBACK_TEXTURE)
        tick:SetVertexColor(1, 1, 1, 0.3)
        tick:SetWidth(1)
        tick:Hide()
        bar.ticks[i] = tick
    end

    -- Spark
    bar.spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetSize(SPARK_WIDTH, height * SPARK_HEIGHT_MULT)
    bar.spark:Hide()

    -- Text
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetPoint("CENTER", bar, "CENTER")
    bar.text:SetFont(STANDARD_TEXT_FONT, 11, FONT_FLAGS)
    bar.text:SetTextColor(1, 1, 1)
    bar.text:SetJustifyH("CENTER")

    -- Tooltip
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if GameTooltip:IsForbidden() then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()

        -- Header
        local settings2 = GetSettings()
        local name = State.preyName or "Prey Hunt"
        GameTooltip:AddLine(name, 1, 1, 1)
        if State.activeQuestID then
            GameTooltip:AddLine(string_format("Stage %d — %d%%", State.currentStage, State.currentProgress), 0.8, 0.8, 0.8)
        end
        if State.difficulty then
            GameTooltip:AddLine("Difficulty: " .. State.difficulty, 0.7, 0.7, 0.7)
        end
        if State.preyZoneName then
            GameTooltip:AddLine("Zone: " .. State.preyZoneName, 0.7, 0.7, 0.7)
        end

        -- Currency section
        if settings2 and settings2.currencyEnabled and HasCurrencyAPI then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Prey Currencies", 0.9, 0.75, 0.3)
            for _, curr in ipairs(PREY_CURRENCIES) do
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, curr.id)
                if ok and info and info.quantity then
                    local qty = SafeToNumber(info.quantity, 0)
                    local sessionDelta = qty - (State.sessionStart[curr.id] or qty)
                    local deltaStr = ""
                    if settings2.currencyShowSession and sessionDelta > 0 then
                        deltaStr = string_format(" |cff00ff00(+%d session)|r", sessionDelta)
                    end
                    GameTooltip:AddDoubleLine(
                        curr.name,
                        tostring(qty) .. deltaStr,
                        0.8, 0.8, 0.8,
                        1, 1, 1
                    )
                end
            end
        end

        -- Preview mode indicator
        if State.isPreviewMode then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Preview Mode", 1, 0.8, 0)
        end

        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        if not GameTooltip:IsForbidden() then GameTooltip:Hide() end
    end)

    State.frame = bar
    return bar
end

---------------------------------------------------------------------------
-- BAR APPEARANCE
---------------------------------------------------------------------------

local function GetBarTexturePath()
    local settings = GetSettings()
    local textureName = settings and settings.texture
    if textureName and LSM then
        local path = LSM:Fetch("statusbar", textureName)
        if path then return path end
    end
    return DEFAULT_FALLBACK_TEXTURE
end

local function UpdateBarAppearance()
    local bar = State.frame
    if not bar then return end
    local settings = GetSettings()
    if not settings then return end

    local br, bg, bb, ba, bgr, bgg, bgb, bga, bdr, bdg, bdb, bda = GetBarColors()

    -- Texture
    local texturePath = GetBarTexturePath()
    bar:SetStatusBarTexture(texturePath)
    bar:SetStatusBarColor(br, bg, bb, ba)

    -- Background
    bar.bg:SetVertexColor(bgr, bgg, bgb, bga)

    -- Border
    if UIKit and UIKit.UpdateBorderLines and bar.Border then
        local borderSize = settings.borderSize or 1
        UIKit.UpdateBorderLines(bar.Border, borderSize, bdr, bdg, bdb, bda)
    end

    -- Font
    local fontSize = settings.textSize or 11
    bar.text:SetFont(STANDARD_TEXT_FONT, fontSize, FONT_FLAGS)
    if settings.showText then
        bar.text:Show()
    else
        bar.text:Hide()
    end

    -- Spark visibility
    if settings.showSpark and bar.spark then
        -- Spark shown/hidden per UpdateBarDisplay
    elseif bar.spark then
        bar.spark:Hide()
    end

    -- Geometry (size) — defer in combat
    if InCombatLockdown() then
        State.deferredGeometry = true
    else
        local w = settings.width or 250
        local h = settings.height or 20
        bar:SetSize(w, h)
        if bar.spark then
            bar.spark:SetSize(SPARK_WIDTH, h * SPARK_HEIGHT_MULT)
        end
        State.deferredGeometry = false
    end
end

local function UpdateTickMarks()
    local bar = State.frame
    if not bar or not bar.ticks then return end
    local settings = GetSettings()

    if not settings or not settings.showTickMarks then
        for i = 1, MAX_TICKS do
            bar.ticks[i]:Hide()
        end
        return
    end

    local positions = (settings.tickStyle == "quarters") and TICK_QUARTERS or TICK_THIRDS
    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()

    for i = 1, MAX_TICKS do
        local tick = bar.ticks[i]
        if i <= #positions then
            tick:ClearAllPoints()
            tick:SetPoint("TOP", bar, "LEFT", barWidth * positions[i], 0)
            tick:SetPoint("BOTTOM", bar, "LEFT", barWidth * positions[i], 0)
            tick:SetWidth(1)
            tick:Show()
        else
            tick:Hide()
        end
    end
end

local function UpdateBarDisplay()
    local bar = State.frame
    if not bar then return end
    local settings = GetSettings()
    if not settings then return end

    -- Derive display stage from raw progressState
    local stage = DetermineStageFromProgressState(State.progressState)

    -- Derive display percent: use raw progressPercent if available,
    -- otherwise fall back to stage-based estimate (like the reference)
    local pct = State.progressPercent
    local shouldUseStageFallback = (pct == nil) or (stage >= 1 and pct <= 0)
    if stage == 4 then
        pct = 100
    elseif shouldUseStageFallback then
        pct = GetStageFallbackPercent(stage)
    end

    State.currentStage = stage
    State.currentProgress = pct

    -- Set bar value (C-side handles secret values)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(pct)

    -- Text
    if settings.showText and bar.text then
        local formatter = TEXT_FORMATS[settings.textFormat] or TEXT_FORMATS.stage_pct
        bar.text:SetText(formatter(stage, pct, State.preyName))
    end

    -- Spark position
    if settings.showSpark and bar.spark then
        local barWidth = bar:GetWidth()
        local sparkX = barWidth * (pct / 100)
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar, "LEFT", sparkX, 0)
        if pct > 0 and pct < 100 then
            bar.spark:Show()
        else
            bar.spark:Hide()
        end
    elseif bar.spark then
        bar.spark:Hide()
    end

    -- Tick marks
    UpdateTickMarks()
end

---------------------------------------------------------------------------
-- VISIBILITY
---------------------------------------------------------------------------

local function ShouldShowBar()
    local settings = GetSettings()
    if not settings or not settings.enabled then return false end

    if State.isPreviewMode then return true end

    -- Completion hold
    if State.completionUntil > 0 and GetTime() < State.completionUntil then return true end

    -- No active quest
    if not State.activeQuestID then return false end

    -- Auto-hide when no widget data is present (out of prey zone, no active hunt visible)
    if settings.autoHide and not State.cachedWidgetID then
        return false
    end

    -- Instance check
    if settings.hideInInstances and IsInInstanceZone() then return false end

    -- Zone check
    if settings.hideOutsidePreyZone and not State.isInPreyZone then return false end

    return true
end

local function ShowBar()
    local bar = State.frame
    if not bar then return end
    if ShouldShowBar() then
        bar:Show()
    end
end

local function HideBar()
    local bar = State.frame
    if bar then bar:Hide() end
end

local function UpdateVisibility()
    if ShouldShowBar() then
        ShowBar()
    else
        HideBar()
    end
end

---------------------------------------------------------------------------
-- BLIZZARD WIDGET SUPPRESSION
---------------------------------------------------------------------------

-- Tracks which widget frames have been hooked for OnShow re-suppression
local suppressionHookedFrames = {}
do local mp = ns._memprobes or {}; ns._memprobes = mp; mp[#mp + 1] = { name = "Prey_suppressionHooked", tbl = suppressionHookedFrames } end

-- Determines if a child frame should be forcibly hidden (models, animations, glow)
local function ShouldHardSuppress(target)
    if not target then return false end
    local objectType = target.GetObjectType and target:GetObjectType() or nil
    if objectType == "ModelScene" or objectType == "PlayerModel" or objectType == "Model" then
        return true
    end
    local name = target.GetName and target:GetName() or ""
    local lowered = name ~= "" and name:lower() or ""
    return lowered:find("modelscene", 1, true) ~= nil
        or lowered:find("scriptedanimation", 1, true) ~= nil
        or lowered:find("anim", 1, true) ~= nil
        or lowered:find("glow", 1, true) ~= nil
end

-- Frames that should never be suppressed (tooltips, money frames, etc.)
local function ShouldNeverSuppress(target)
    if not target then return true end
    local name = target.GetName and target:GetName() or ""
    if name == "" then return false end
    local lowered = name:lower()
    return lowered:find("tooltip", 1, true) ~= nil
        or lowered:find("moneyframe", 1, true) ~= nil
        or lowered:find("lootframe", 1, true) ~= nil
        or lowered:find("merchantframe", 1, true) ~= nil
end

-- Apply suppression to a single widget frame and all its children recursively
local function ApplyWidgetFrameSuppression(frameRef, suppress)
    if not frameRef then return end

    local visited = {}

    local function applyHardVisibilitySuppression(target)
        if not target or not target.Hide then return end
        if not ShouldHardSuppress(target) then return end

        if suppress then
            local targetState = GetWidgetState(target)
            if targetState.wasShown == nil and target.IsShown then
                targetState.wasShown = target:IsShown() and true or false
            end
            pcall(target.Hide, target)
        else
            local targetState = widgetSideState[target]
            if targetState and targetState.wasShown then
                targetState.wasShown = nil
                if target.Show then pcall(target.Show, target) end
            elseif targetState and targetState.wasShown ~= nil then
                targetState.wasShown = nil
            end
        end
    end

    local function applyAnimationSuppression(target)
        if not target or not target.GetAnimationGroups then return end
        local okGroups, groups = pcall(function() return { target:GetAnimationGroups() } end)
        if not okGroups or type(groups) ~= "table" then return end

        for _, group in ipairs(groups) do
            if group then
                if suppress then
                    local isPlaying = false
                    if group.IsPlaying then
                        local okP, playing = pcall(group.IsPlaying, group)
                        isPlaying = okP and playing and true or false
                    end
                    widgetAnimationState[group] = isPlaying and true or false
                    if group.Stop then pcall(group.Stop, group) end
                elseif widgetAnimationState[group] then
                    widgetAnimationState[group] = nil
                    if group.Play then pcall(group.Play, group) end
                end
            end
        end
    end

    local function applyToFrameTree(node, depth)
        if not node or visited[node] or depth > 8 then return end
        if ShouldNeverSuppress(node) then return end
        visited[node] = true

        applyAnimationSuppression(node)
        applyHardVisibilitySuppression(node)

        -- Alpha suppression
        if node.SetAlpha then
            if suppress then
                local nodeState = GetWidgetState(node)
                if nodeState.originalAlpha == nil and node.GetAlpha then
                    nodeState.originalAlpha = node:GetAlpha()
                end
                node:SetAlpha(0)
            else
                local nodeState = widgetSideState[node]
                if nodeState and nodeState.originalAlpha ~= nil then
                    node:SetAlpha(nodeState.originalAlpha)
                    nodeState.originalAlpha = nil
                end
            end
        end

        -- Regions (textures, font strings, etc.)
        if node.GetRegions then
            local regions = { node:GetRegions() }
            for _, region in ipairs(regions) do
                applyAnimationSuppression(region)
                applyHardVisibilitySuppression(region)
                if region and region.SetAlpha then
                    if suppress then
                        local regionState = GetWidgetState(region)
                        if regionState.originalAlpha == nil and region.GetAlpha then
                            regionState.originalAlpha = region:GetAlpha()
                        end
                        region:SetAlpha(0)
                    else
                        local regionState = widgetSideState[region]
                        if regionState and regionState.originalAlpha ~= nil then
                            region:SetAlpha(regionState.originalAlpha)
                            regionState.originalAlpha = nil
                        end
                    end
                end
            end
        end

        -- Recurse into children
        if node.GetChildren then
            local children = { node:GetChildren() }
            for _, child in ipairs(children) do
                applyToFrameTree(child, depth + 1)
            end
        end
    end

    applyToFrameTree(frameRef, 0)

    -- Disable mouse interaction on the top-level widget frame
    if frameRef.EnableMouse then
        frameRef:EnableMouse(not suppress)
    end
end

-- Also suppress the immediate parent if it's a widget container wrapper
local function ApplySuppressionToWidgetParent(frameRef, containerFrame, suppress)
    if not frameRef or not frameRef.GetParent then return end
    local okP, parent = pcall(frameRef.GetParent, frameRef)
    if not okP or not parent or parent == UIParent then return end

    local parentName = parent.GetName and parent:GetName() or ""
    local containerName = containerFrame and containerFrame.GetName and containerFrame:GetName() or ""
    local loweredParent = parentName ~= "" and parentName:lower() or ""
    local loweredContainer = containerName ~= "" and containerName:lower() or ""

    local safeParent = parent == containerFrame
        or (loweredParent ~= "" and loweredParent:find("uiwidget", 1, true) ~= nil)
        or (loweredContainer ~= "" and loweredParent ~= "" and loweredParent:find(loweredContainer, 1, true) ~= nil)

    if safeParent then
        ApplyWidgetFrameSuppression(parent, suppress)
    end
end

-- Hook a widget frame's OnShow so it gets re-suppressed when Blizzard shows it
local function EnsureWidgetSuppressionHook(frameRef)
    if not frameRef or suppressionHookedFrames[frameRef] or not frameRef.HookScript then return end
    suppressionHookedFrames[frameRef] = true

    frameRef:HookScript("OnShow", function(self)
        pcall(function()
            if not State.widgetSuppressed then return end
            local settings = GetSettings()
            if settings and settings.replaceDefaultIndicator and settings.enabled then
                ApplyWidgetFrameSuppression(self, true)
            end
        end)
    end)
end

-- Scan container children for prey/hunt-related widget names as a fallback
local function ApplySuppressionToContainerFallback(container, suppress)
    if not container or not container.GetChildren then return end

    local visited = {}
    local function scan(node, depth)
        if not node or visited[node] or depth > 6 then return end
        visited[node] = true

        local name = node.GetName and node:GetName() or ""
        local lowered = name ~= "" and name:lower() or ""
        local isWidgetName = lowered:find("uiwidget", 1, true) ~= nil
        local isRelated = isWidgetName
            and (lowered:find("prey", 1, true) ~= nil or lowered:find("hunt", 1, true) ~= nil)

        if isRelated then
            ApplyWidgetFrameSuppression(node, suppress)
        end

        if node.GetChildren then
            local children = { node:GetChildren() }
            for _, child in ipairs(children) do
                scan(child, depth + 1)
            end
        end
    end

    scan(container, 0)
end

-- Main function: find all prey widget frames and apply suppression
local function ApplyDefaultPreyIconVisibility()
    if not HasWidgetAPI then return end

    local preyWidgetType = GetPreyWidgetType()
    local suppress = State.widgetSuppressed

    for _, setID in ipairs(GetCandidateWidgetSetIDs()) do
        local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
        if ok and widgets then
            for _, widget in ipairs(widgets) do
                if widget and widget.widgetType == preyWidgetType and widget.widgetID then
                    for _, globalName in ipairs(WIDGET_CONTAINER_GLOBALS) do
                        local container = _G[globalName]

                        -- Try widgetFrames lookup
                        local widgetFrame = TryGetWidgetFrameByID(container, widget.widgetID)
                        if widgetFrame then
                            EnsureWidgetSuppressionHook(widgetFrame)
                            ApplyWidgetFrameSuppression(widgetFrame, suppress)
                            ApplySuppressionToWidgetParent(widgetFrame, container, suppress)
                        end

                        -- Try global name pattern
                        local namedFrame = _G[globalName .. "Widget" .. tostring(widget.widgetID)]
                        if namedFrame then
                            EnsureWidgetSuppressionHook(namedFrame)
                            ApplyWidgetFrameSuppression(namedFrame, suppress)
                            ApplySuppressionToWidgetParent(namedFrame, container, suppress)
                        end

                        -- Fallback: scan container children for prey-related names
                        if container then
                            ApplySuppressionToContainerFallback(container, suppress)
                        end
                    end
                end
            end
        end
    end
end

local function SuppressBlizzardPreyWidget()
    if State.widgetSuppressed then return end
    State.widgetSuppressed = true

    -- Deferred to avoid taint during widget processing
    C_Timer.After(0, ApplyDefaultPreyIconVisibility)
end

local function RestoreBlizzardPreyWidget()
    if not State.widgetSuppressed then return end
    State.widgetSuppressed = false

    -- Re-apply with suppress=false to restore original state
    C_Timer.After(0, ApplyDefaultPreyIconVisibility)
end

local function ToggleDefaultIndicator(hide)
    if hide then
        SuppressBlizzardPreyWidget()
    else
        RestoreBlizzardPreyWidget()
    end
end

---------------------------------------------------------------------------
-- STAGE TRANSITIONS & ALERTS
---------------------------------------------------------------------------

local STAGE_SOUNDS = {
    [2] = SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 170567,
    [3] = SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 170567,
    [4] = SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 170567,
}
local COMPLETION_SOUND = SOUNDKIT.ACHIEVEMENT_GENERAL or 888 -- fallback

local function OnStageTransition(oldStage, newStage)
    local settings = GetSettings()
    if not settings or not settings.soundEnabled then return end
    if State.isPreviewMode then return end

    local questKey = State.activeQuestID or 0
    local soundKey = tostring(questKey) .. "_" .. tostring(newStage)

    if State.stageSoundPlayed[soundKey] then return end
    State.stageSoundPlayed[soundKey] = true

    if newStage == 2 and settings.soundStage2 then
        pcall(PlaySound, STAGE_SOUNDS[2])
    elseif newStage == 3 and settings.soundStage3 then
        pcall(PlaySound, STAGE_SOUNDS[3])
    elseif newStage == 4 and settings.soundStage4 then
        pcall(PlaySound, STAGE_SOUNDS[4])
    end
end

local function TriggerAmbushAlert()
    local bar = State.frame
    local settings = GetSettings()
    if not bar or not settings then return end
    if not settings.ambushAlertEnabled then return end

    local duration = settings.ambushDuration or 6
    State.ambushActiveUntil = GetTime() + duration

    if settings.ambushSoundEnabled then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING or 8959)
    end

    if settings.ambushGlowEnabled and LCG then
        LCG.PixelGlow_Start(bar, { 1, 0.3, 0, 1 }, 14, 0.25, nil, 2)
        C_Timer.After(duration, function()
            if bar and LCG then
                LCG.PixelGlow_Stop(bar)
            end
        end)
    end
end

local function OnAmbushMessage(message)
    if not message or Helpers.IsSecretValue(message) then return end
    local settings = GetSettings()
    if not settings or not settings.ambushAlertEnabled then return end

    if message:lower():find(AMBUSH_PATTERN) then
        TriggerAmbushAlert()
    end
end

local function OnQuestCompleted(questID)
    if questID ~= State.activeQuestID then return end
    local settings = GetSettings()

    -- Show 100% briefly
    State.progressState = PREY_PROGRESS_FINAL
    State.progressPercent = 100
    State.completionUntil = GetTime() + COMPLETION_HOLD_TIME
    UpdateBarDisplay()
    ShowBar()

    if settings and settings.completionSound and settings.soundEnabled then
        pcall(PlaySound, COMPLETION_SOUND)
    end

    -- Clear after hold time
    C_Timer.After(COMPLETION_HOLD_TIME + 0.1, function()
        if State.completionUntil > 0 and GetTime() >= State.completionUntil then
            State.completionUntil = 0
            State.activeQuestID = nil
            State.preyName = nil
            State.difficulty = nil
            State.progressState = nil
            State.progressPercent = nil
            State.lastWidgetSeenAt = 0
            State.currentStage = 0
            State.currentProgress = 0
            State.stageSoundPlayed = {}
            UpdateVisibility()
        end
    end)
end

---------------------------------------------------------------------------
-- HUNT SCANNER
---------------------------------------------------------------------------

local function OnGossipShow()
    local settings = GetSettings()
    if not settings or not settings.huntScannerEnabled then return end

    if not C_GossipInfo or not C_GossipInfo.GetOptions then return end
    local options = SafeCall(C_GossipInfo.GetOptions)
    if not options then return end

    State.availableHunts = {}
    State.isAtHuntTable = false

    for _, option in ipairs(options) do
        local name = option.name or ""
        -- Look for hunt-related gossip options (prey/hunt keywords)
        if name:lower():find("hunt") or name:lower():find("prey") or name:lower():find("track") then
            State.isAtHuntTable = true
            table.insert(State.availableHunts, {
                name = name,
                gossipOptionID = option.gossipOptionID,
            })
        end
    end

    if State.isAtHuntTable and #State.availableHunts > 0 then
        ShowHuntPanel()
    end
end

local function CreateHuntPanel()
    if State.huntPanel then return State.huntPanel end
    local bar = State.frame
    if not bar then return nil end

    local panel = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    panel:SetSize(220, 100)
    panel:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    panel:SetFrameStrata("TOOLTIP")

    local _, _, _, _, bgr, bgg, bgb, bga = Helpers.GetSkinColors()
    panel:SetBackdrop({
        bgFile = DEFAULT_FALLBACK_TEXTURE,
        edgeFile = DEFAULT_FALLBACK_TEXTURE,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(bgr, bgg, bgb, 0.95)
    panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetPoint("TOPLEFT", 6, -6)
    panel.title:SetFont(STANDARD_TEXT_FONT, 12, FONT_FLAGS)
    panel.title:SetTextColor(1, 0.82, 0)
    panel.title:SetText("Available Hunts")

    panel.lines = {}
    for i = 1, 8 do
        local line = panel:CreateFontString(nil, "OVERLAY")
        line:SetPoint("TOPLEFT", 6, -6 - 16 * i)
        line:SetFont(STANDARD_TEXT_FONT, 11, "")
        line:SetTextColor(0.9, 0.9, 0.9)
        line:SetWidth(208)
        line:SetJustifyH("LEFT")
        line:Hide()
        panel.lines[i] = line
    end

    panel:Hide()
    State.huntPanel = panel
    return panel
end

function ShowHuntPanel()
    local panel = State.huntPanel or CreateHuntPanel()
    if not panel then return end

    for i, line in ipairs(panel.lines) do
        line:Hide()
    end

    local count = min(#State.availableHunts, 8)
    for i = 1, count do
        local hunt = State.availableHunts[i]
        panel.lines[i]:SetText(hunt.name)
        panel.lines[i]:Show()
    end

    local panelHeight = 24 + count * 16 + 6
    panel:SetHeight(panelHeight)
    panel:Show()
end

local function HideHuntPanel()
    State.isAtHuntTable = false
    if State.huntPanel then
        State.huntPanel:Hide()
    end
end

---------------------------------------------------------------------------
-- CURRENCY TRACKER
---------------------------------------------------------------------------

local function InitCurrencyBaseline()
    if not HasCurrencyAPI then return end

    for _, curr in ipairs(PREY_CURRENCIES) do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, curr.id)
        if ok and info and info.quantity then
            State.sessionStart[curr.id] = SafeToNumber(info.quantity, 0)
        end
    end
end

local function SaveWarbandSnapshot()
    if not HasCurrencyAPI then return end
    local core = GetCore()
    if not core or not core.db or not core.db.global then return end

    -- Ensure global preyTracker table
    if not core.db.global.preyTracker then
        core.db.global.preyTracker = { warband = {}, weekly = {} }
    end
    local globalDB = core.db.global.preyTracker

    -- Character key
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or not realm then return end
    local charKey = name .. "-" .. realm

    if not globalDB.warband then globalDB.warband = {} end
    if not globalDB.warband[charKey] then globalDB.warband[charKey] = { currencies = {} } end

    local charData = globalDB.warband[charKey]
    charData.lastSeen = time()
    charData.level = UnitLevel("player")

    for _, curr in ipairs(PREY_CURRENCIES) do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, curr.id)
        if ok and info and info.quantity then
            charData.currencies[curr.id] = SafeToNumber(info.quantity, 0)
        end
    end
end

---------------------------------------------------------------------------
-- MASTER UPDATE
---------------------------------------------------------------------------

local function ResetState()
    State.activeQuestID = nil
    State.preyName = nil
    State.difficulty = nil
    State.progressState = nil
    State.progressPercent = nil
    State.lastWidgetSeenAt = 0
    State.currentStage = 0
    State.currentProgress = 0
    State.cachedWidgetID = nil
    State.stageSoundPlayed = {}
    State.isInPreyZone = false
    State.preyZoneMapID = nil
    State.preyZoneName = nil
end

local function UpdatePreyState()
    local settings = GetSettings()
    if not settings or not settings.enabled then
        HideBar()
        return
    end

    if State.isPreviewMode then return end

    -- During completion hold, keep showing 100% — don't let widget data overwrite
    if State.completionUntil > 0 and GetTime() < State.completionUntil then
        return
    end

    -- Try two detection paths: quest API and widget scan
    local questID = GetActivePreyQuest()
    local widgetID, widgetInfo = ScanPreyWidgets()

    -- Check if the quest is flagged completed (catches kills even if QUEST_TURNED_IN is delayed)
    if questID and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) then
        if State.activeQuestID and State.completionUntil == 0 then
            OnQuestCompleted(State.activeQuestID)
        end
        if RefreshContinuousUpdateScript then RefreshContinuousUpdateScript() end
        return
    end

    -- We have an active prey if either the quest API or widget scan found something
    local hasActivePrey = questID ~= nil or widgetInfo ~= nil

    if hasActivePrey then
        -- New quest detected (or first widget detection)
        local trackingKey = questID or widgetID
        if trackingKey ~= State.activeQuestID then
            ResetState()
            State.activeQuestID = trackingKey
            if questID then
                ExtractPreyInfo(questID)
                DetectPreyZone(questID)
            end
        end

        -- Update zone status
        State.isInPreyZone = CheckInPreyZone()

        -- Store raw widget/quest data — display derivation happens in UpdateBarDisplay
        if widgetInfo then
            State.cachedWidgetID = widgetID
            State.isInPreyZone = true
            State.lastWidgetSeenAt = GetTime()

            -- Store raw progressState from widget
            if widgetInfo.progressState ~= nil then
                State.progressState = widgetInfo.progressState
            end

            -- Store raw progressPercent: try widget fields first, then quest objectives
            local widgetPct = ExtractProgressPercent(widgetInfo, widgetInfo.tooltip)
            if widgetPct then
                State.progressPercent = widgetPct
            else
                local objectivePct = ExtractQuestObjectivePercent(questID)
                if objectivePct and objectivePct > 0 then
                    State.progressPercent = objectivePct
                elseif widgetInfo.progressState == PREY_PROGRESS_FINAL then
                    State.progressPercent = 100
                else
                    -- No granular percent available — leave nil so display uses stage fallback
                    State.progressPercent = nil
                end
            end

            -- Try to get prey name from widget info if we didn't get it from quest
            if not State.preyName and widgetInfo.text then
                local text = SafeValue(widgetInfo.text, nil)
                if text and type(text) == "string" and text ~= "" then
                    State.preyName = text
                end
            end
        elseif questID then
            -- Widget no longer visible — clear cached ID, try quest objectives
            State.cachedWidgetID = nil
            local objectivePct = ExtractQuestObjectivePercent(questID)
            if objectivePct then
                State.progressPercent = objectivePct
            end
            -- No widget means no progressState — clear it if widget has been gone > 2s
            if (GetTime() - State.lastWidgetSeenAt) > 2 then
                State.progressState = nil
                State.progressPercent = nil
            end
        end

        -- Stage transition sounds (before display update)
        local newStage = DetermineStageFromProgressState(State.progressState)
        local oldStage = State.currentStage
        if oldStage > 0 and newStage > oldStage then
            OnStageTransition(oldStage, newStage)
        end

        UpdateBarDisplay()
        UpdateVisibility()
    else
        -- No active prey
        if State.activeQuestID and State.completionUntil == 0 then
            ResetState()
            UpdateVisibility()
        end
    end

    if RefreshContinuousUpdateScript then RefreshContinuousUpdateScript() end
end

---------------------------------------------------------------------------
-- REFRESH & PREVIEW
---------------------------------------------------------------------------

local function RefreshPreyTracker()
    if not State.frame then return end
    UpdateBarAppearance()
    UpdateBarDisplay()
    UpdateVisibility()
end

local function TogglePreview(enable)
    State.isPreviewMode = enable
    local bar = State.frame
    if not bar then return end

    if enable then
        -- Fake data for layout/options preview
        State.progressState = 2  -- stage 3
        State.progressPercent = 67
        State.preyName = "Prey Hunt Preview"
        State.difficulty = "Normal"
        UpdateBarAppearance()
        UpdateBarDisplay()
        bar:Show()
    else
        State.progressState = nil
        State.progressPercent = nil
        State.currentStage = 0
        State.currentProgress = 0
        State.preyName = nil
        State.difficulty = nil
        UpdateBarDisplay()
        UpdateVisibility()
    end
end

-- Expose globals
_G.QUI_RefreshPreyTracker = RefreshPreyTracker
_G.QUI_TogglePreyTrackerPreview = TogglePreview

---------------------------------------------------------------------------
-- REGISTRY
---------------------------------------------------------------------------

if ns.Registry then
    ns.Registry:Register("preyTracker", {
        refresh = _G.QUI_RefreshPreyTracker,
        priority = 40,
        group = "trackers",
        importCategories = { "trackersTimers" },
    })
end

---------------------------------------------------------------------------
-- EVENT HANDLING
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

local function ScheduleWidgetUpdate(delay)
    if pendingWidgetUpdate then
        return
    end
    pendingWidgetUpdate = true
    C_Timer.After(delay or 0, function()
        pendingWidgetUpdate = false
        UpdatePreyState()
        if State.widgetSuppressed then
            ApplyDefaultPreyIconVisibility()
        end
    end)
end

local function OnEvent(self, event, arg1, arg2)
    if event == "PLAYER_ENTERING_WORLD" then
        local settings = GetSettings()
        if not settings or not settings.enabled then return end

        if not State.initialized then
            CreatePreyBar()
            UpdateBarAppearance()
            State.initialized = true
        end

        -- Suppress default widget if needed
        if settings.replaceDefaultIndicator then
            SuppressBlizzardPreyWidget()
            -- Re-apply after a delay — widgets may not exist at first load
            C_Timer.After(1, ApplyDefaultPreyIconVisibility)
        end

        InitCurrencyBaseline()
        C_Timer.After(0.5, UpdatePreyState) -- slight delay for quest log to be ready

    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_ACCEPTED" then
        C_Timer.After(0.1, UpdatePreyState)

    elseif event == "QUEST_TURNED_IN" then
        if arg1 and arg1 == State.activeQuestID then
            OnQuestCompleted(arg1)
        end

    elseif event == "QUEST_REMOVED" then
        if arg1 and arg1 == State.activeQuestID and State.completionUntil == 0 then
            ResetState()
            UpdateVisibility()
        end

    elseif event == "UPDATE_UI_WIDGET" then
        -- Always update — internal scan determines if it's a prey widget.
        -- Also re-apply suppression in case Blizzard re-showed the widget frame.
        ScheduleWidgetUpdate(0)

    elseif event == "UPDATE_ALL_UI_WIDGETS" then
        ScheduleWidgetUpdate(0.1)

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        if State.activeQuestID then
            State.isInPreyZone = CheckInPreyZone()
            -- Full state update to re-scan widgets (they disappear outside prey zones)
            C_Timer.After(0.1, UpdatePreyState)
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        OnAmbushMessage(arg1)

    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()

    elseif event == "GOSSIP_CLOSED" then
        HideHuntPanel()

    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        SaveWarbandSnapshot()

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Apply deferred geometry
        if State.deferredGeometry and State.frame then
            local settings = GetSettings()
            if settings then
                local w = settings.width or 250
                local h = settings.height or 20
                State.frame:SetSize(w, h)
                if State.frame.spark then
                    State.frame.spark:SetSize(SPARK_WIDTH, h * SPARK_HEIGHT_MULT)
                end
            end
            State.deferredGeometry = false
            UpdateBarDisplay()
        end
    end
end

-- OnUpdate for continuous progress polling
local function OnUpdate(self, elapsed)
    if State.isPreviewMode or not State.activeQuestID then
        self:SetScript("OnUpdate", nil)
        return
    end

    State.elapsed = State.elapsed + elapsed
    if State.elapsed < UPDATE_THROTTLE then return end
    State.elapsed = 0

    UpdatePreyState()
end

RefreshContinuousUpdateScript = function()
    if not eventFrame then return end
    if State.isPreviewMode or State.activeQuestID then
        eventFrame:SetScript("OnUpdate", OnUpdate)
    else
        eventFrame:SetScript("OnUpdate", nil)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

-- Register events on ADDON_LOADED so we don't miss PLAYER_ENTERING_WORLD
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("UPDATE_UI_WIDGET")
eventFrame:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

RefreshContinuousUpdateScript()

---------------------------------------------------------------------------
-- NAMESPACE EXPORT
---------------------------------------------------------------------------

ns.QUI_PreyTracker = {
    GetState = function() return State end,
    Refresh = RefreshPreyTracker,
    TogglePreview = TogglePreview,
    ToggleDefaultIndicator = ToggleDefaultIndicator,
}
