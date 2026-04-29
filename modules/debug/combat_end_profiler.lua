local ADDON_NAME, ns = ...
----------------------------------------------------------------------------
-- Combat-End Profiler
--
-- Measures the cost of the PLAYER_REGEN_ENABLED handler chain to diagnose
-- combat-end stutter. Disabled by default; opt in via slash command.
--
-- Usage:
--   /qui combatprof on        → start profiling
--   /qui combatprof off       → stop and unwrap functions
--   /qui combatprof report    → reprint the last combat-end report
--   /qui combatprof reset     → clear accumulated stats
--
-- A report prints automatically ~2.5s after each combat ends.
--
-- Four layers of evidence:
--   1. Wall-clock window: t0 on PLAYER_REGEN_ENABLED, "settle" mark on the
--      next After(0) tick (proxy for when the synchronous handler chain
--      finishes), FPS sampled before and 0.5s after window closes.
--   2. Per-function timing on named CDM/spell-data suspects via
--      GetTimePreciseSec deltas (immune to nesting unlike debugprofilestart).
--   3. Per-frame-handler timing on every frame in ns.QUI_PerfRegistry
--      (CDM, group frames, action bars, raid buffs, aura dispatch, plus
--      explicit registrations from skinning combat-defer frames). Wraps
--      OnEvent / OnUpdate, records totalMs only inside the watch window.
--   4. Frame-time spike detector — any frame >50ms within the watch window
--      is logged with offset-since-regen.
----------------------------------------------------------------------------

-- =====================================================================
-- State
-- =====================================================================

local enabled       = false
local wrapped       = false
local windowOpen    = false
local windowStart   = 0
local windowSettleMs = 0
local windowFps0    = 0
local windowFps1    = 0

local funcStats     = {}    -- [label] = { calls, totalMs, maxMs }
local frameSpikes   = {}    -- list of { elapsed, t }
local lastReport    = nil   -- string (most recent printed report)

local WINDOW_DURATION = 2.0
local SPIKE_THRESHOLD = 0.05    -- 50 ms

-- Suspect functions to wrap. Resolved at enable time so missing modules
-- (e.g. CDM disabled) don't error.
local SUSPECTS = {
    { path = "CDMSpellData", method = "ForceScan",              label = "ForceScan" },
    { path = "CDMSpellData", method = "SnapshotBlizzardCDM",    label = "SnapshotBlizzardCDM" },
    { path = "CDMSpellData", method = "CheckAllDormantSpells",  label = "CheckAllDormantSpells" },
    { path = "CDMSpellData", method = "ReconcileAllContainers", label = "ReconcileAllContainers" },
    { path = "CDMSpellData", method = "InvalidateChildMap",     label = "InvalidateChildMap" },
}

local originals = {}        -- [label] = { tbl, method, fn }
local frameOriginals = {}   -- [label] = { frame, scriptType, fn }

-- =====================================================================
-- Wrapping (Layer 2)
-- =====================================================================

local function record(label, ms)
    local row = funcStats[label]
    if not row then
        row = { calls = 0, totalMs = 0, maxMs = 0 }
        funcStats[label] = row
    end
    row.calls = row.calls + 1
    row.totalMs = row.totalMs + ms
    if ms > row.maxMs then row.maxMs = ms end
end

local function wrapFn(tbl, method, label)
    if originals[label] then return end
    local orig = tbl[method]
    if type(orig) ~= "function" then return end
    originals[label] = { tbl = tbl, method = method, fn = orig }
    tbl[method] = function(self, ...)
        if not enabled then return orig(self, ...) end
        local t0 = GetTimePreciseSec()
        local function track(...)
            record(label, (GetTimePreciseSec() - t0) * 1000)
            return ...
        end
        return track(orig(self, ...))
    end
end

-- Wrap a frame's OnEvent / OnUpdate handler so its synchronous cost is timed
-- whenever it dispatches inside the watch window. Captures every event the
-- frame is registered for, not just PLAYER_REGEN_ENABLED — that's the point:
-- post-combat handlers also fire on UNIT_AURA / BAG_UPDATE / etc cascades.
local function wrapFrameHandler(label, frame, scriptType)
    if frameOriginals[label] then return end
    if type(frame) ~= "table" or type(frame.GetScript) ~= "function"
       or type(frame.SetScript) ~= "function" then return end
    local orig = frame:GetScript(scriptType)
    if type(orig) ~= "function" then return end
    frameOriginals[label] = { frame = frame, scriptType = scriptType, fn = orig }

    local wrapped_fn
    if scriptType == "OnUpdate" then
        wrapped_fn = function(self, elapsed, ...)
            if not (enabled and windowOpen) then return orig(self, elapsed, ...) end
            local t0 = GetTimePreciseSec()
            local function track(...)
                record(label, (GetTimePreciseSec() - t0) * 1000)
                return ...
            end
            return track(orig(self, elapsed, ...))
        end
    else
        wrapped_fn = function(self, event, ...)
            if not (enabled and windowOpen) then return orig(self, event, ...) end
            local t0 = GetTimePreciseSec()
            local function track(...)
                record(label, (GetTimePreciseSec() - t0) * 1000)
                return ...
            end
            return track(orig(self, event, ...))
        end
    end
    frame:SetScript(scriptType, wrapped_fn)
end

-- Snapshot ns.QUI_PerfRegistry at install time so any module that pushed an
-- entry before /qui combatprof on is wrapped. Late pushes (after enable) are
-- not picked up — call combatprof off + on to refresh.
local function InstallFrameWrappers()
    local reg = ns.QUI_PerfRegistry
    if not reg then return end
    for i = 1, #reg do
        local entry = reg[i]
        local name = entry.name or entry[1]
        local frame = entry.frame or entry[2]
        local scriptType = entry.scriptType or entry[3] or "OnEvent"
        if name and frame then
            wrapFrameHandler(name, frame, scriptType)
        end
    end
end

local function RestoreFrameWrappers()
    for _, info in pairs(frameOriginals) do
        if info.frame and info.frame.SetScript then
            info.frame:SetScript(info.scriptType, info.fn)
        end
    end
    wipe(frameOriginals)
end

local function InstallWrappers()
    if wrapped then return true end
    -- Pre-flight: every named suspect must resolve.
    for _, s in ipairs(SUSPECTS) do
        local tbl = ns[s.path]
        if not tbl or type(tbl[s.method]) ~= "function" then
            return false, ("ns.%s:%s not available"):format(s.path, s.method)
        end
    end
    for _, s in ipairs(SUSPECTS) do
        wrapFn(ns[s.path], s.method, s.label)
    end
    InstallFrameWrappers()
    wrapped = true
    return true
end

local function RestoreWrappers()
    for _, info in pairs(originals) do
        info.tbl[info.method] = info.fn
    end
    wipe(originals)
    RestoreFrameWrappers()
    wrapped = false
end

-- =====================================================================
-- Frame-time spike detector (Layer 4)
-- =====================================================================

local spikeFrame = CreateFrame("Frame")
spikeFrame:Hide()
spikeFrame:SetScript("OnUpdate", function(self, elapsed)
    if not enabled or not windowOpen then
        self:Hide()
        return
    end
    local t = GetTimePreciseSec() - windowStart
    if t > WINDOW_DURATION then
        self:Hide()
        return
    end
    if elapsed >= SPIKE_THRESHOLD then
        frameSpikes[#frameSpikes + 1] = { elapsed = elapsed * 1000, t = t * 1000 }
    end
end)

-- =====================================================================
-- Window lifecycle (Layer 1)
-- =====================================================================

local function ResetWindow()
    wipe(funcStats)
    wipe(frameSpikes)
    windowSettleMs = 0
    windowFps0 = 0
    windowFps1 = 0
end

local PrintReport    -- forward declared

local function OpenWindow()
    ResetWindow()
    windowStart = GetTimePreciseSec()
    windowFps0  = GetFramerate() or 0
    windowOpen  = true
    spikeFrame:Show()

    -- Settle marker — fires on the next OnUpdate after the synchronous
    -- handler chain completes. Caveat: our combat handler may itself fire
    -- mid-chain, so this is a lower bound on total sync cost.
    C_Timer.After(0, function()
        if windowOpen then
            windowSettleMs = (GetTimePreciseSec() - windowStart) * 1000
        end
    end)

    -- Window close + auto-report.
    C_Timer.After(WINDOW_DURATION + 0.5, function()
        if not windowOpen then return end
        windowFps1 = GetFramerate() or 0
        windowOpen = false
        spikeFrame:Hide()
        if enabled then PrintReport(true) end
    end)
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if enabled then OpenWindow() end
end)

-- =====================================================================
-- Reporting
-- =====================================================================

local function fmtMs(n) return ("%6.1f"):format(n or 0) end

PrintReport = function(autoPrint)
    local lines = {}
    lines[#lines+1] = ("|cff60A5FAQUI combatprof:|r combat-end window (auto=%s)")
        :format(autoPrint and "yes" or "no")
    lines[#lines+1] = ("  next-frame settle: %s ms      fps before/after: %d -> %d")
        :format(fmtMs(windowSettleMs), windowFps0, windowFps1)

    local sorted = {}
    for label, row in pairs(funcStats) do sorted[#sorted+1] = { label, row } end
    table.sort(sorted, function(a, b) return a[2].totalMs > b[2].totalMs end)
    if #sorted > 0 then
        lines[#lines+1] = "  Handlers (totalMs / calls / maxMs — frame OnEvent + named CDM fns):"
        for _, e in ipairs(sorted) do
            lines[#lines+1] = ("    %-28s %s ms / %3d / %s ms")
                :format(e[1], fmtMs(e[2].totalMs), e[2].calls, fmtMs(e[2].maxMs))
        end
    else
        lines[#lines+1] = "  Handlers: no wrapped suspects fired (registry empty?)."
    end

    if #frameSpikes > 0 then
        lines[#lines+1] = ("  Frame spikes (>%d ms within %.1fs):")
            :format(SPIKE_THRESHOLD * 1000, WINDOW_DURATION)
        for _, s in ipairs(frameSpikes) do
            lines[#lines+1] = ("    +%s ms after regen — frame=%s ms"):format(fmtMs(s.t), fmtMs(s.elapsed))
        end
    else
        lines[#lines+1] = "  Frame spikes: none."
    end

    lastReport = table.concat(lines, "\n")
    for _, line in ipairs(lines) do print(line) end
end

-- =====================================================================
-- Slash dispatch
-- =====================================================================

local function CmdOn()
    if enabled then
        print("|cff60A5FAQUI combatprof:|r already on.")
        return
    end
    local ok, err = InstallWrappers()
    if not ok then
        print(("|cff60A5FAQUI combatprof:|r cannot start — %s."):format(err))
        return
    end
    enabled = true
    ResetWindow()
    local frameCount = 0
    local reg = ns.QUI_PerfRegistry
    if reg then frameCount = #reg end
    print(("|cff60A5FAQUI combatprof:|r on — wrapped %d named fn(s) + %d frame handler(s). Report after each combat ends.")
        :format(#SUSPECTS, frameCount))
end

local function CmdOff()
    if not enabled then
        print("|cff60A5FAQUI combatprof:|r already off.")
        return
    end
    enabled = false
    windowOpen = false
    spikeFrame:Hide()
    RestoreWrappers()
    print("|cff60A5FAQUI combatprof:|r off.")
end

local function CmdReset()
    ResetWindow()
    lastReport = nil
    print("|cff60A5FAQUI combatprof:|r stats reset.")
end

local function CmdReport()
    if lastReport then
        for line in lastReport:gmatch("[^\n]+") do print(line) end
    else
        print("|cff60A5FAQUI combatprof:|r no report yet — exit combat first.")
    end
end

_G.QUI_CombatProf = function(arg)
    arg = (arg or ""):lower()
    if     arg == "on"     then CmdOn()
    elseif arg == "off"    then CmdOff()
    elseif arg == "reset"  then CmdReset()
    elseif arg == "report" or arg == "" then CmdReport()
    else
        print("|cff60A5FAQUI combatprof:|r usage — /qui combatprof [on|off|report|reset]")
    end
end
