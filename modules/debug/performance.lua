local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local QUI_PerfMonitor = {}
ns.QUI_PerfMonitor = QUI_PerfMonitor

-- Constants
local SAMPLE_INTERVAL = 1.0
local MAX_HISTORY = 150
local FRAME_WIDTH = 300
local FRAME_HEIGHT_BASE = 220
local FRAME_HEIGHT_EVENTS = 320
local GRAPH_WIDTH = 260
local GRAPH_HEIGHT = 80
local TOP_EVENTS_COUNT = 5
local ACCENT_R, ACCENT_G, ACCENT_B = 0.204, 0.827, 0.600 -- #34D399
local BG_R, BG_G, BG_B, BG_A = 0.08, 0.08, 0.08, 0.92
local BORDER_R, BORDER_G, BORDER_B = 0.204, 0.827, 0.600

-- State
local monitorFrame
local isTracking = false
local elapsed = 0
local sessionStart = 0
local currentMem = 0
local peakMem = 0
local totalMem = 0
local sampleCount = 0
local currentCPU = 0       -- ms per frame (profiler) or ms/sec (scriptProfile)
local currentCPUPct = 0    -- percentage of frame time
local memoryHistory = {}
local cpuHistory = {}

-- CPU API tier: "profiler" | "scriptProfile" | nil
local cpuAPITier
local lastScriptCPU = 0    -- for scriptProfile delta tracking
local lastScriptTime = 0   -- GetTime() at last scriptProfile sample

-- Event counting
local eventSnifferEnabled = false
local eventCounts = {}      -- [eventName] = count since last sample
local eventRates = {}       -- [eventName] = fires/sec (from last sample)
local eventSniffer          -- hidden frame that registers all events
local topEvents = {}        -- sorted {name, rate} for display

-- UI references
local memText, peakText, avgText, cpuText, sessionText, samplesText
local graphBars = {}
local graphMaxLabel
local gcResultText
local eventSection          -- container frame for the hot events section
local eventRows = {}        -- fontstring pairs for top events
local eventsToggleBtn       -- button to enable/disable event sniffer
local graphContainer        -- the memory graph frame

-- ─── API Detection ───────────────────────────────────────────────────────────

local function DetectCPUAPI()
    -- Tier 1: C_AddOnProfiler (12.0+, no CVar needed)
    if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
        local ok, val = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON_NAME, Enum.AddOnProfilerMetric.RecentAverageTime)
        if ok then
            cpuAPITier = "profiler"
            return
        end
    end

    -- Tier 2: GetAddOnCPUUsage (requires scriptProfile CVar)
    if GetAddOnCPUUsage and GetCVar and GetCVar("scriptProfile") == "1" then
        cpuAPITier = "scriptProfile"
        return
    end

    -- Tier 3: memory only
    cpuAPITier = nil
end

-- ─── Event Sniffer ───────────────────────────────────────────────────────────

local function StartEventSniffer()
    if not eventSniffer then
        eventSniffer = CreateFrame("Frame")
    end
    wipe(eventCounts)
    wipe(eventRates)
    wipe(topEvents)
    eventSniffer:RegisterAllEvents()
    eventSniffer:SetScript("OnEvent", function(_, event)
        eventCounts[event] = (eventCounts[event] or 0) + 1
    end)
    eventSnifferEnabled = true
end

local function StopEventSniffer()
    if eventSniffer then
        eventSniffer:UnregisterAllEvents()
        eventSniffer:SetScript("OnEvent", nil)
    end
    eventSnifferEnabled = false
    wipe(eventCounts)
    wipe(eventRates)
    wipe(topEvents)
end

local function SnapshotEventRates(dt)
    if not eventSnifferEnabled then return end
    local rate = dt > 0 and dt or 1
    wipe(eventRates)
    for event, count in pairs(eventCounts) do
        eventRates[event] = count / rate
    end
    wipe(eventCounts)

    -- Sort for top N
    wipe(topEvents)
    for event, r in pairs(eventRates) do
        topEvents[#topEvents + 1] = { name = event, rate = r }
    end
    table.sort(topEvents, function(a, b) return a.rate > b.rate end)
end

-- ─── Layout Toggle ───────────────────────────────────────────────────────────

local function RefreshLayout()
    if not monitorFrame then return end
    if eventSnifferEnabled then
        monitorFrame:SetHeight(FRAME_HEIGHT_EVENTS)
        eventSection:Show()
        eventsToggleBtn:SetText("Events: ON")
    else
        monitorFrame:SetHeight(FRAME_HEIGHT_BASE)
        eventSection:Hide()
        eventsToggleBtn:SetText("Events: OFF")
        -- Clear event rows
        for i = 1, TOP_EVENTS_COUNT do
            eventRows[i].name:SetText("")
            eventRows[i].rate:SetText("")
        end
    end
end

-- ─── Sampling ────────────────────────────────────────────────────────────────

local function FormatMemory(kb)
    if kb >= 1024 then
        return format("%.2f MB", kb / 1024)
    end
    return format("%.1f KB", kb)
end

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return format("%d:%02d", m, s)
end

local function PushHistory(history, value)
    history[#history + 1] = value
    if #history > MAX_HISTORY then
        table.remove(history, 1)
    end
end

local function Sample()
    -- Memory
    pcall(UpdateAddOnMemoryUsage)
    local ok, mem = pcall(GetAddOnMemoryUsage, ADDON_NAME)
    if ok and mem then
        currentMem = mem
        if mem > peakMem then peakMem = mem end
        totalMem = totalMem + mem
        sampleCount = sampleCount + 1
    end

    -- CPU — compute as percentage of total frame time
    local fps = GetFramerate()
    local frameTimeMs = fps > 0 and (1000 / fps) or 16.667

    if cpuAPITier == "profiler" then
        local cpuOk, val = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON_NAME, Enum.AddOnProfilerMetric.RecentAverageTime)
        if cpuOk and val then
            currentCPU = val
            currentCPUPct = (val / frameTimeMs) * 100
        end
    elseif cpuAPITier == "scriptProfile" then
        pcall(UpdateAddOnCPUUsage)
        local cpuOk, val = pcall(GetAddOnCPUUsage, ADDON_NAME)
        if cpuOk and val then
            local now = GetTime()
            local dt = now - lastScriptTime
            if dt > 0 and lastScriptTime > 0 then
                local cpuDelta = val - lastScriptCPU
                local msPerSec = cpuDelta / dt
                currentCPU = msPerSec
                currentCPUPct = (msPerSec / 1000) * 100
            end
            lastScriptCPU = val
            lastScriptTime = now
        end
    end

    -- Event rates (no-op if sniffer disabled)
    SnapshotEventRates(SAMPLE_INTERVAL)

    PushHistory(memoryHistory, currentMem)
    PushHistory(cpuHistory, currentCPUPct)
end

-- ─── Graph Update ────────────────────────────────────────────────────────────

local function UpdateGraph()
    local count = #memoryHistory
    if count == 0 then return end

    local maxVal = 0
    for i = 1, count do
        if memoryHistory[i] > maxVal then
            maxVal = memoryHistory[i]
        end
    end
    if maxVal == 0 then maxVal = 1 end

    graphMaxLabel:SetText(FormatMemory(maxVal))

    local barWidth = GRAPH_WIDTH / MAX_HISTORY
    for i = 1, MAX_HISTORY do
        local bar = graphBars[i]
        local dataIndex = count - (MAX_HISTORY - i)
        if dataIndex >= 1 then
            local ratio = memoryHistory[dataIndex] / maxVal
            local h = math.max(1, ratio * GRAPH_HEIGHT)
            bar:SetHeight(h)
            bar:Show()
        else
            bar:Hide()
        end
    end
end

-- ─── UI Update ───────────────────────────────────────────────────────────────

local function UpdateDisplay()
    if not monitorFrame or not monitorFrame:IsShown() then return end

    memText:SetText(FormatMemory(currentMem))
    peakText:SetText(FormatMemory(peakMem))

    local avg = sampleCount > 0 and (totalMem / sampleCount) or 0
    avgText:SetText(FormatMemory(avg))

    if cpuAPITier then
        cpuText:SetText(format("%.2f%%  (%.3f ms)", currentCPUPct, currentCPU))
    else
        cpuText:SetText("N/A")
    end

    sessionText:SetText(FormatTime(GetTime() - sessionStart))
    samplesText:SetText(tostring(sampleCount))

    -- Top events (only when sniffer is active)
    if eventSnifferEnabled then
        for i = 1, TOP_EVENTS_COUNT do
            local row = eventRows[i]
            local entry = topEvents[i]
            if entry then
                row.name:SetText(entry.name)
                row.rate:SetText(format("%.0f/s", entry.rate))
            else
                row.name:SetText("")
                row.rate:SetText("")
            end
        end
    end

    UpdateGraph()
end

-- ─── OnUpdate Handler ────────────────────────────────────────────────────────

local function OnUpdate(self, dt)
    elapsed = elapsed + dt
    if elapsed >= SAMPLE_INTERVAL then
        elapsed = elapsed - SAMPLE_INTERVAL
        Sample()
        UpdateDisplay()
    end
end

-- ─── Frame Creation ──────────────────────────────────────────────────────────

local function CreateStatRow(parent, label, yOffset)
    local labelFs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelFs:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
    labelFs:SetTextColor(0.6, 0.6, 0.6)
    labelFs:SetText(label)

    local valueFs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueFs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    valueFs:SetTextColor(1, 1, 1)
    valueFs:SetText("--")

    return valueFs
end

local function CreateMonitorFrame()
    local f = CreateFrame("Frame", "QUI_PerfMonitorFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT_BASE)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -100)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(BG_R, BG_G, BG_B, BG_A)
    f:SetBackdropBorderColor(BORDER_R, BORDER_G, BORDER_B, 0.8)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
    title:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    title:SetText("QUI Performance")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        isTracking = false
        f:SetScript("OnUpdate", nil)
        StopEventSniffer()
    end)

    -- Accent separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -24)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -24)
    sep:SetHeight(1)
    sep:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.6)

    -- Stats rows
    local y = -30
    local rowSpacing = -14
    memText = CreateStatRow(f, "Memory:", y)
    y = y + rowSpacing
    peakText = CreateStatRow(f, "Peak:", y)
    y = y + rowSpacing
    avgText = CreateStatRow(f, "Average:", y)
    y = y + rowSpacing
    cpuText = CreateStatRow(f, "CPU:", y)
    y = y + rowSpacing
    sessionText = CreateStatRow(f, "Session:", y)
    y = y + rowSpacing
    samplesText = CreateStatRow(f, "Samples:", y)

    -- ─── Hot Events section (hidden by default) ─────────────────────────────
    y = y + rowSpacing - 4
    eventSection = CreateFrame("Frame", nil, f)
    eventSection:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
    eventSection:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
    eventSection:SetHeight(TOP_EVENTS_COUNT * (-rowSpacing) + 22)
    eventSection:Hide()

    local eventSep = eventSection:CreateTexture(nil, "ARTWORK")
    eventSep:SetPoint("TOPLEFT", eventSection, "TOPLEFT", 8, 0)
    eventSep:SetPoint("TOPRIGHT", eventSection, "TOPRIGHT", -8, 0)
    eventSep:SetHeight(1)
    eventSep:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)

    local eventHeader = eventSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eventHeader:SetPoint("TOPLEFT", eventSection, "TOPLEFT", 12, -4)
    eventHeader:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    eventHeader:SetText("Hot Events")

    local rateHeader = eventSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rateHeader:SetPoint("TOPRIGHT", eventSection, "TOPRIGHT", -12, -4)
    rateHeader:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    rateHeader:SetText("Rate")

    local ey = -4 + rowSpacing
    for i = 1, TOP_EVENTS_COUNT do
        local nameFs = eventSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("TOPLEFT", eventSection, "TOPLEFT", 16, ey)
        nameFs:SetTextColor(0.8, 0.8, 0.8)
        nameFs:SetText("")

        local rateFs = eventSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rateFs:SetPoint("TOPRIGHT", eventSection, "TOPRIGHT", -12, ey)
        rateFs:SetTextColor(1, 1, 1)
        rateFs:SetText("")

        eventRows[i] = { name = nameFs, rate = rateFs }
        ey = ey + rowSpacing
    end

    -- ─── Memory Graph (anchored to bottom so it shifts with frame height) ───
    graphContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    graphContainer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 36)
    graphContainer:SetSize(GRAPH_WIDTH, GRAPH_HEIGHT)
    graphContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    graphContainer:SetBackdropColor(0.04, 0.04, 0.04, 0.8)
    graphContainer:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

    -- Grid lines at 25%, 50%, 75%
    for _, pct in ipairs({ 0.25, 0.50, 0.75 }) do
        local line = graphContainer:CreateTexture(nil, "ARTWORK")
        line:SetPoint("LEFT", graphContainer, "BOTTOMLEFT", 1, GRAPH_HEIGHT * pct)
        line:SetPoint("RIGHT", graphContainer, "BOTTOMRIGHT", -1, GRAPH_HEIGHT * pct)
        line:SetHeight(1)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.4)
    end

    -- Y-axis max label
    graphMaxLabel = graphContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    graphMaxLabel:SetPoint("TOPRIGHT", graphContainer, "TOPRIGHT", -4, -2)
    graphMaxLabel:SetTextColor(0.5, 0.5, 0.5)
    graphMaxLabel:SetText("")

    -- Pre-create bar textures
    local barWidth = GRAPH_WIDTH / MAX_HISTORY
    for i = 1, MAX_HISTORY do
        local bar = graphContainer:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("BOTTOMLEFT", graphContainer, "BOTTOMLEFT", (i - 1) * barWidth, 1)
        bar:SetWidth(math.max(1, barWidth - 0.5))
        bar:SetHeight(1)
        bar:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        bar:Hide()
        graphBars[i] = bar
    end

    -- ─── Bottom buttons ─────────────────────────────────────────────────────
    local gcBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gcBtn:SetSize(80, 20)
    gcBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    gcBtn:SetText("Force GC")
    gcBtn:SetScript("OnClick", function()
        local before = collectgarbage("count")
        collectgarbage("collect")
        local after = collectgarbage("count")
        local freed = before - after
        gcResultText:SetText(format("Freed %s", FormatMemory(freed)))
        gcResultText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
    end)

    gcResultText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gcResultText:SetPoint("LEFT", gcBtn, "RIGHT", 8, 0)
    gcResultText:SetTextColor(0.6, 0.6, 0.6)
    gcResultText:SetText("")

    eventsToggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    eventsToggleBtn:SetSize(90, 20)
    eventsToggleBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    eventsToggleBtn:SetText("Events: OFF")
    eventsToggleBtn:SetScript("OnClick", function()
        if eventSnifferEnabled then
            StopEventSniffer()
        else
            StartEventSniffer()
        end
        RefreshLayout()
    end)

    monitorFrame = f
    return f
end

-- ─── Toggle / Start / Stop ───────────────────────────────────────────────────

local function ResetSession()
    elapsed = 0
    sessionStart = GetTime()
    currentMem = 0
    peakMem = 0
    totalMem = 0
    sampleCount = 0
    currentCPU = 0
    currentCPUPct = 0
    lastScriptCPU = 0
    lastScriptTime = 0
    memoryHistory = {}
    cpuHistory = {}
    wipe(eventCounts)
    wipe(eventRates)
    wipe(topEvents)
    if gcResultText then gcResultText:SetText("") end
end

local function StartTracking()
    if not monitorFrame then
        CreateMonitorFrame()
    end
    ResetSession()

    -- Reset graph bars
    for i = 1, MAX_HISTORY do
        graphBars[i]:Hide()
    end

    -- Reset event rows
    for i = 1, TOP_EVENTS_COUNT do
        eventRows[i].name:SetText("")
        eventRows[i].rate:SetText("")
    end

    isTracking = true
    monitorFrame:Show()
    monitorFrame:SetScript("OnUpdate", OnUpdate)
    RefreshLayout()

    -- Take first sample immediately
    Sample()
    UpdateDisplay()
end

local function StopTracking()
    isTracking = false
    StopEventSniffer()
    if monitorFrame then
        monitorFrame:SetScript("OnUpdate", nil)
        monitorFrame:Hide()
    end
end

local function Toggle()
    if isTracking and monitorFrame and monitorFrame:IsShown() then
        StopTracking()
    else
        StartTracking()
    end
end

-- Expose for slash command
_G.QUI_TogglePerfMonitor = Toggle

-- ─── Bootstrap ───────────────────────────────────────────────────────────────

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function(self)
    DetectCPUAPI()
    self:UnregisterAllEvents()
end)
