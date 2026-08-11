-- tests/unit/memaudit_addon_profiler_test.lua
-- Run: lua tests/unit/memaudit_addon_profiler_test.lua

local printed = {}
local originalPrint = print
local now = 0
local inCombat = false
local addonKB = 1000
local frames = {}
local measuredCalls = 0
local activeMeasuredEvents

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    printed[#printed + 1] = table.concat(parts, " ")
end

function GetTime()
    return now
end

function InCombatLockdown()
    return inCombat
end

function UpdateAddOnMemoryUsage() end

function GetAddOnMemoryUsage(addonName)
    assert(addonName == "QUI", "unexpected addon name")
    return addonKB
end

function CreateFrame()
    local frame = {
        scripts = {},
        shown = false,
        events = {},
    }
    function frame:Hide()
        self.shown = false
    end
    function frame:Show()
        self.shown = true
    end
    function frame:RegisterEvent(event)
        self.events[event] = true
    end
    function frame:SetScript(script, handler)
        self.scripts[script] = handler
    end
    function frame:GetScript(script)
        return self.scripts[script]
    end
    frames[#frames + 1] = frame
    return frame
end

C_Timer = {
    After = function(_, callback)
        callback()
    end,
}

C_AddOnProfiler = {
    IsEnabled = function()
        return true
    end,
    AddMeasuredCallEvent = function(name)
        if activeMeasuredEvents then
            activeMeasuredEvents[#activeMeasuredEvents + 1] = {
                name = name,
                allocatedBytes = 2048,
                deallocatedBytes = 1024,
                elapsedMilliseconds = 0.25,
            }
        end
    end,
    MeasureCall = function(fn, ...)
        measuredCalls = measuredCalls + 1
        activeMeasuredEvents = {}
        local a, b, c, d, e, f, g, h = fn(...)
        local events = activeMeasuredEvents
        activeMeasuredEvents = nil
        return {
            allocatedBytes = 4096,
            deallocatedBytes = 1024,
            elapsedMilliseconds = 0.5,
            events = events,
        }, a, b, c, d, e, f, g, h
    end,
}

local actionCooldownCalls = 0
local sourceCooldownCalls = 0
local registryFrameCalls = 0

local ns = {
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
    ActionBarsOwned = {
        UpdateAllCooldowns = function()
            actionCooldownCalls = actionCooldownCalls + 1
        end,
    },
    CDMSources = {
        QuerySpellCooldown = function(spellID)
            sourceCooldownCalls = sourceCooldownCalls + 1
            return { spellID = spellID }, true
        end,
    },
}

assert(loadfile("QUI_Debug/memaudit.lua"))("QUI", ns)

local autoFrame = assert(frames[1], "memaudit should create an auto frame")
assert(type(_G.QUI_MemAudit) == "function", "memaudit slash handler should be exported")

local registryFrame = CreateFrame()
registryFrame:SetScript("OnEvent", function()
    registryFrameCalls = registryFrameCalls + 1
end)
ns.QUI_PerfRegistry = {
    { name = "TestFrame", frame = registryFrame },
}

_G.QUI_MemAudit("auto", "1")

inCombat = true
now = 1
autoFrame.scripts.OnEvent(autoFrame, "PLAYER_REGEN_DISABLED")

ns.ActionBarsOwned.UpdateAllCooldowns()
registryFrame.scripts.OnEvent(registryFrame, "UNIT_TEST")
local cdInfo, extra = ns.CDMSources.QuerySpellCooldown(123)
local markerResult = ns.MemAuditProfilerMeasure("CDM_testMarked", function()
    ns.MemAuditProfilerMark("CDM_testPhase")
    return "marked"
end)
assert(type(cdInfo) == "table" and cdInfo.spellID == 123 and extra == true,
    "profiler wrapper should preserve function returns")
assert(markerResult == "marked", "profiler marker test should preserve returns")
assert(actionCooldownCalls == 1, "actionbar cooldown function should run through wrapper")
assert(sourceCooldownCalls == 1, "CDM source function should run through wrapper")
assert(registryFrameCalls == 1, "registry frame handler should run through wrapper")

now = 2.1
autoFrame.scripts.OnUpdate(autoFrame, 1.1)

local foundActionScope = false
local foundSourceScope = false
local foundEventScope = false
local foundFrameScope = false
local foundProfilerSummary = false
for _, line in ipairs(printed) do
    if line:find("AB_UpdateAllCooldowns %+4 KB/%-1 KB", 1) then
        foundActionScope = true
    end
    if line:find("CDM_srcCooldown %+4 KB/%-1 KB", 1) then
        foundSourceScope = true
    end
    if line:find("CDM_testPhase %+2 KB/%-1 KB", 1) then
        foundEventScope = true
    end
    if line:find("FR_TestFrame %+4 KB/%-1 KB", 1) then
        foundFrameScope = true
    end
    if line:find("profiler row sum:", 1) and line:find("heap", 1) then
        foundProfilerSummary = true
    end
end

assert(measuredCalls >= 3, "profiler should be probed and then used by wrapped scopes")
assert(foundActionScope, "memaudit auto should report measured actionbar allocations")
assert(foundSourceScope, "memaudit auto should report measured CDM source allocations")
assert(foundEventScope, "memaudit auto should report measured profiler event allocations")
assert(foundFrameScope, "memaudit auto should report measured registered frame allocations")
assert(foundProfilerSummary, "memaudit auto should report measured rows against heap delta")

originalPrint("OK: memaudit_addon_profiler_test")
