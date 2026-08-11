local ADDON_NAME, ns = ...

local GetAddOnMemoryUsage = GetAddOnMemoryUsage
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage
local C_AddOnProfiler = C_AddOnProfiler
local C_Timer = C_Timer

ns.QUI_PerfFlags = ns.QUI_PerfFlags or { disabled = {} }

local SYSTEMS = { "raidbuffs", "health", "auras", "missingbuffs" }
local SYSTEM_SET = {}
for _, s in ipairs(SYSTEMS) do SYSTEM_SET[s] = true end

local function P(msg) print("|cff60A5FAQUI PerfTest:|r " .. tostring(msg)) end

local function SuiteNames()
    local mon = ns.QUI_PerfMonitor
    if mon and mon.GetMetricTargetNames then return mon.GetMetricTargetNames() end
    return { "QUI" }
end

local function SuiteMemoryKB()
    ns.SafeCall("best-effort-style", UpdateAddOnMemoryUsage)
    local total = 0
    for _, name in ipairs(SuiteNames()) do
        local ok, mem = pcall(GetAddOnMemoryUsage, name)
        if ok and type(mem) == "number" then total = total + mem end
    end
    return total
end

local function SuiteProfilerMs(metric)
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and metric) then return nil end
    local total = 0
    for _, name in ipairs(SuiteNames()) do
        local ok, val = pcall(C_AddOnProfiler.GetAddOnMetric, name, metric)
        if ok and type(val) == "number" then total = total + val end
    end
    return total
end

local function RunKBTest(seconds)
    seconds = tonumber(seconds) or 10
    if seconds < 1 then seconds = 1 end
    collectgarbage("collect")
    local startMem = SuiteMemoryKB()
    local startTime = GetTime()
    P(string.format("allocation test running %ds (GC-bracketed, suite-wide)...", seconds))
    C_Timer.After(seconds, function()
        collectgarbage("collect")
        local endMem = SuiteMemoryKB()
        local elapsed = GetTime() - startTime
        if elapsed <= 0 then elapsed = seconds end
        local perSec = (endMem - startMem) / elapsed
        local tag = (perSec > 0.5 and "|cffff0000HIGH|r")
            or (perSec > 0.1 and "|cffffff00warn|r")
            or "|cff00ff00ok|r"
        P(string.format("delta %.2f KB / %.1fs = %.3f KB/s  [%s]  (green<=0.1, red>0.5)",
            endMem - startMem, elapsed, perSec, tag))
    end)
end

local function ReportTimes()
    local E = Enum and Enum.AddOnProfilerMetric
    local avg = E and SuiteProfilerMs(E.RecentAverageTime)
    if not avg then P("C_AddOnProfiler unavailable") return end
    local peak = (E and SuiteProfilerMs(E.PeakTime)) or 0
    local over1 = (E and SuiteProfilerMs(E.CountTimeOver1Ms)) or 0
    local fps = GetFramerate()
    local frameMs = (fps and fps > 0) and (1000 / fps) or 16.667
    P(string.format("suite avg %.3f ms/frame (%.1f%% of %.2fms) | engine peak %.3f ms | ticks>1ms %d",
        avg, (avg / frameMs) * 100, frameMs, peak, over1))
end

local function ApplyAndRefresh()
    local GFA = ns.QUI_GroupFrameAuras
    if GFA and GFA.RefreshAll then ns.SafeCall("bulkhead", function() GFA:RefreshAll() end) end
end

local function StatusLine()
    local parts = {}
    for _, s in ipairs(SYSTEMS) do
        parts[#parts + 1] = s .. "=" ..
            (ns.QUI_PerfFlags.disabled[s] and "|cffff0000OFF|r" or "|cff00ff00on|r")
    end
    P(table.concat(parts, "  "))
end

local function SetDisabled(sys, state)
    if not sys or not SYSTEM_SET[sys] then
        P("systems: " .. table.concat(SYSTEMS, ", "))
        return
    end
    ns.QUI_PerfFlags.disabled[sys] = state or nil
    ApplyAndRefresh()
    StatusLine()
end

local function Solo(sys)
    if not sys or not SYSTEM_SET[sys] then
        P("usage: solo <" .. table.concat(SYSTEMS, "|") .. ">")
        return
    end
    for _, s in ipairs(SYSTEMS) do
        ns.QUI_PerfFlags.disabled[s] = (s ~= sys) or nil
    end
    ApplyAndRefresh()
    StatusLine()
end

local function ResetAll()
    for _, s in ipairs(SYSTEMS) do ns.QUI_PerfFlags.disabled[s] = nil end
    ApplyAndRefresh()
    StatusLine()
end

_G.QUI_PerfTest = function(subcmd, arg)
    subcmd = subcmd and string.lower(tostring(subcmd)) or "help"
    if subcmd == "kb" or subcmd == "mem" then
        RunKBTest(arg)
    elseif subcmd == "peak" or subcmd == "time" then
        ReportTimes()
    elseif subcmd == "off" then
        SetDisabled(arg and string.lower(arg), true)
    elseif subcmd == "on" then
        SetDisabled(arg and string.lower(arg), false)
    elseif subcmd == "solo" then
        Solo(arg and string.lower(arg))
    elseif subcmd == "reset" then
        ResetAll()
    elseif subcmd == "status" then
        StatusLine()
    else
        P("subcmds: kb [sec] | peak | off <sys> | on <sys> | solo <sys> | reset | status")
        P("systems: " .. table.concat(SYSTEMS, ", "))
    end
end
