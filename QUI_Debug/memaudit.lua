local ADDON_NAME, ns = ...
local TARGET_ADDON_NAME = "QUI"

local function SumSuiteMemoryKB()
    local total, found = 0, false
    local n = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or 0
    for i = 1, n do
        local okL, loaded = pcall(C_AddOns.IsAddOnLoaded, i)
        if okL and loaded then
            local okN, name = pcall(C_AddOns.GetAddOnInfo, i)
            if okN and (name == TARGET_ADDON_NAME
                or (type(name) == "string" and name:sub(1, #"QUI_") == "QUI_")) then
                local okM, mem = pcall(GetAddOnMemoryUsage, name)
                if okM and mem then
                    total = total + mem
                    found = true
                end
            end
        end
    end
    if not found then
        local okM, mem = pcall(GetAddOnMemoryUsage, TARGET_ADDON_NAME)
        return okM and mem or 0
    end
    return total
end

local probes = {}
local lastSnapshot = nil
local profilerActive = false
local profilerAvailable = nil
local profilerWarned = false
local profilerScopes = {}
local profilerScopeOrder = {}
local profilerWrappers = {}
local profilerFrameWrappers = {}
local profilerEventParents = {
    CDM_applyResolveState = true,
    CDM_testMarked = true,
}

local pending = ns._memprobes
if pending then
    for i = 1, #pending do
        probes[#probes + 1] = pending[i]
    end
end
ns._memprobes = probes

local function CountEntries(tbl)
    local count = 0
    local deepCount = 0
    for _, v in pairs(tbl) do
        count = count + 1
        if type(v) == "table" then
            for _ in pairs(v) do
                deepCount = deepCount + 1
            end
        end
    end
    return count, deepCount
end

local function HasProbe(name)
    for i = 1, #probes do
        if probes[i] and probes[i].name == name then
            return true
        end
    end
    return false
end

local function AddProbe(name, fn)
    if not HasProbe(name) then
        probes[#probes + 1] = { name = name, fn = fn }
    end
end

local function CallStats(owner, methodName)
    if owner and owner[methodName] then
        local ok, stats = pcall(owner[methodName], owner)
        if ok and type(stats) == "table" then
            return stats
        end
    end
    return {}
end

local function CallFunction(fn)
    if type(fn) == "function" then
        local ok, stats = pcall(fn)
        if ok and type(stats) == "table" then
            return stats
        end
    end
    return {}
end

local function N(value)
    return tonumber(value) or 0
end

local function RegisterCDMCacheProbes()
    AddProbe("CDM_cache_auraIndex", function()
        local s = CallStats(ns.CDMSpellData, "GetCacheStats")
        return N(s.capturedAuraEntries),
            N(s.capturedAuraUnits) + N(s.capturedAuraSpellKeys) + N(s.capturedAuraNameKeys)
    end)

    AddProbe("CDM_cache_iconPools", function()
        local ic = CallStats(ns.CDMIcons, "GetCacheStats")
        return N(ic.activeIcons) + N(ic.recycleIcons),
            N(ic.activeIconPools) + N(ic.textureCycleCache)
    end)

    AddProbe("CDM_cache_runtimeStore", function()
        local rt = CallFunction(ns.CDMRuntimeStore and ns.CDMRuntimeStore.GetStats)
        return N(rt.version), N(rt.compatState)
    end)

    AddProbe("CDM_cache_tickAura", function()
        local s = CallStats(ns.CDMSpellData, "GetCacheStats")
        return N(s.tickAuraData) + N(s.tickAuraDuration)
            + N(s.tickAuraExpiration) + N(s.tickAuraApplication), 0
    end)

    AddProbe("CDM_cache_resolveMemo", function()
        local s = CallStats(ns.CDMSpellData, "GetCacheStats")
        return N(s.resolveIconMemo) + N(s.resolveAuraMemo),
            N(s.learnedSize) + N(s.totemSlotMap)
    end)

    AddProbe("CDM_cache_framesBars", function()
        local br = CallStats(ns.CDMBars, "GetCacheStats")
        local fr = CallFunction(ns.GetCDMFrameCacheStats)
        return N(br.activeBars) + N(fr.size), 0
    end)
end

RegisterCDMCacheProbes()

local function TakeSnapshot()
    local snap = {}
    for i = 1, #probes do
        local p = probes[i]
        if p.fn then
            local ok, count, deep = pcall(p.fn)
            if ok then
                if p.counter then
                    snap[p.name] = { counter = true, value = count or 0, count = 0, deep = 0 }
                elseif type(count) == "table" then
                    snap[p.name] = count
                else
                    snap[p.name] = { count = count or 0, deep = deep or 0 }
                end
            else
                snap[p.name] = p.counter and { counter = true, value = 0, count = 0, deep = 0 } or { count = 0, deep = 0 }
            end
        elseif p.tbl then
            local count, deep = CountEntries(p.tbl)
            snap[p.name] = { count = count, deep = deep }
        end
    end

    ns.SafeCall("best-effort-style", UpdateAddOnMemoryUsage)
    snap._totalKB = SumSuiteMemoryKB()
    snap._time = GetTime()
    snap._combat = InCombatLockdown() and true or false
    return snap
end

local function FormatKB(kb)
    if kb >= 1024 then
        return string.format("%.1f MB", kb / 1024)
    end
    return string.format("%.0f KB", kb)
end

local function FormatBytes(bytes)
    bytes = tonumber(bytes) or 0
    local kb = bytes / 1024
    return FormatKB(kb)
end

local function ProfilerNumber(value)
    local n = tonumber(value)
    if n then return n end
    local s = value ~= nil and tostring(value) or nil
    if not s then return 0 end
    return tonumber(s:match("^%d+")) or 0
end

local function DetectAddOnProfiler()
    if profilerAvailable ~= nil then return profilerAvailable end
    if not (C_AddOnProfiler and type(C_AddOnProfiler.MeasureCall) == "function") then
        profilerAvailable = false
        return false
    end
    if type(C_AddOnProfiler.IsEnabled) == "function" then
        local ok, enabled = pcall(C_AddOnProfiler.IsEnabled)
        if ok and enabled == false then
            profilerAvailable = false
            return false
        end
    end
    local ok, results, marker = pcall(C_AddOnProfiler.MeasureCall, function()
        return "ok"
    end)
    profilerAvailable = ok and type(results) == "table" and marker == "ok"
    return profilerAvailable
end

local function GetProfilerScope(name)
    local scope = profilerScopes[name]
    if scope then return scope end
    scope = { name = name, calls = 0, allocatedBytes = 0, deallocatedBytes = 0, elapsedMS = 0 }
    profilerScopes[name] = scope
    profilerScopeOrder[#profilerScopeOrder + 1] = name
    return scope
end

local function RecordProfilerScope(name, results)
    if type(results) ~= "table" then return end
    local scope = GetProfilerScope(name)
    scope.calls = scope.calls + 1
    scope.allocatedBytes = scope.allocatedBytes + ProfilerNumber(results.allocatedBytes)
    scope.deallocatedBytes = scope.deallocatedBytes + ProfilerNumber(results.deallocatedBytes)
    scope.elapsedMS = scope.elapsedMS + ProfilerNumber(results.elapsedMilliseconds)

    if not profilerEventParents[name] then return end

    local events = results.events
    if type(events) ~= "table" then return end

    local lastAllocatedBytes = 0
    local lastDeallocatedBytes = 0
    local lastElapsedMS = 0
    for i = 1, #events do
        local event = events[i]
        local eventName = event and event.name
        if type(eventName) == "string" and eventName ~= "" then
            local allocatedBytes = ProfilerNumber(event.allocatedBytes)
            local deallocatedBytes = ProfilerNumber(event.deallocatedBytes)
            local elapsedMS = ProfilerNumber(event.elapsedMilliseconds)
            local eventScope = GetProfilerScope(eventName)
            eventScope.calls = eventScope.calls + 1
            eventScope.allocatedBytes = eventScope.allocatedBytes + math.max(0, allocatedBytes - lastAllocatedBytes)
            eventScope.deallocatedBytes = eventScope.deallocatedBytes + math.max(0, deallocatedBytes - lastDeallocatedBytes)
            eventScope.elapsedMS = eventScope.elapsedMS + math.max(0, elapsedMS - lastElapsedMS)
            lastAllocatedBytes = allocatedBytes
            lastDeallocatedBytes = deallocatedBytes
            lastElapsedMS = elapsedMS
        end
    end
end

local function MeasureProfileCall(name, fn, ...)
    if not profilerActive or not DetectAddOnProfiler() then
        return fn(...)
    end
    local results, a, b, c, d, e, f, g, h = C_AddOnProfiler.MeasureCall(fn, ...)
    RecordProfilerScope(name, results)
    return a, b, c, d, e, f, g, h
end
ns.MemAuditProfilerMeasure = MeasureProfileCall

local function MarkProfileEvent(name)
    if not profilerActive
        or not name
        or not (C_AddOnProfiler and type(C_AddOnProfiler.AddMeasuredCallEvent) == "function") then
        return
    end
    C_AddOnProfiler.AddMeasuredCallEvent(name)
end
ns.MemAuditProfilerMark = MarkProfileEvent

local function WrapProfilerFunction(owner, methodName, scopeName)
    if type(owner) ~= "table" or type(owner[methodName]) ~= "function" then return false end
    local current = owner[methodName]
    local wrapped = profilerWrappers[scopeName]
    if wrapped and current == wrapped.wrapper then return true end

    local original = current
    local wrapper = function(...)
        return MeasureProfileCall(scopeName, original, ...)
    end
    profilerWrappers[scopeName] = { owner = owner, methodName = methodName, original = original, wrapper = wrapper }
    owner[methodName] = wrapper
    return true
end

local function SanitizeScopeName(name)
    local s = tostring(name or "Frame"):gsub("[^%w_]+", "_")
    if s == "" then s = "Frame" end
    return s
end

local function WrapProfilerFrame(entry)
    if type(entry) ~= "table" then return false end
    local name = entry.name or entry[1]
    local frame = entry.frame or entry[2]
    local scriptType = entry.scriptType or entry[3] or "OnEvent"
    if not name
        or type(frame) ~= "table"
        or type(frame.GetScript) ~= "function"
        or type(frame.SetScript) ~= "function"
    then
        return false
    end

    local original = frame:GetScript(scriptType)
    if type(original) ~= "function" then return false end

    local scopeName = "FR_" .. SanitizeScopeName(name)
    if scriptType ~= "OnEvent" then
        scopeName = scopeName .. "_" .. SanitizeScopeName(scriptType)
    end

    local wrapped = profilerFrameWrappers[scopeName]
    if wrapped and original == wrapped.wrapper then return true end

    local wrapper = function(...)
        return MeasureProfileCall(scopeName, original, ...)
    end
    profilerFrameWrappers[scopeName] = { frame = frame, scriptType = scriptType, original = original, wrapper = wrapper }
    frame:SetScript(scriptType, wrapper)
    return true
end

local function InstallProfilerFrameWrappers()
    local reg = ns.QUI_PerfRegistry
    if type(reg) ~= "table" then return end
    for i = 1, #reg do
        WrapProfilerFrame(reg[i])
    end
end

local function InstallProfilerWrappers()
    if not DetectAddOnProfiler() then
        if not profilerWarned then
            profilerWarned = true
            print("|cffffaa00[memaudit]|r C_AddOnProfiler.MeasureCall unavailable; allocation scopes disabled.")
        end
        return false
    end

    WrapProfilerFunction(ns.ActionBarsOwned, "UpdateAllCooldowns", "AB_UpdateAllCooldowns")
    WrapProfilerFunction(ns.ActionBarsOwned, "UpdateAllButtonVisuals", "AB_UpdateAllButtonVisuals")
    WrapProfilerFunction(ns.ActionBarsOwned, "UpdateAllButtonStates", "AB_UpdateAllButtonStates")
    WrapProfilerFunction(ns.CDMIcons, "UpdateAllCooldowns", "CDM_UpdateAllCooldowns")
    WrapProfilerFunction(ns.CDMIcons, "UpdateCooldownOnly", "CDM_UpdateCooldownOnly")
    WrapProfilerFunction(ns.CDMIcons, "UpdateCooldownsForType", "CDM_UpdateCooldownsForType")
    WrapProfilerFunction(ns.CDMIcons, "UpdateAllIconRanges", "CDM_UpdateAllIconRanges")
    WrapProfilerFunction(ns.CDMSources, "QuerySpellCooldown", "CDM_srcCooldown")
    WrapProfilerFunction(ns.CDMSources, "QuerySpellCharges", "CDM_srcCharges")
    WrapProfilerFunction(ns.CDMSources, "QuerySpellCooldownDuration", "CDM_srcCooldownDur")
    WrapProfilerFunction(ns.CDMSources, "QuerySpellChargeDuration", "CDM_srcChargeDur")
    WrapProfilerFunction(ns.CDMSources, "QuerySpellDisplayCount", "CDM_srcDisplayCount")
    WrapProfilerFunction(ns.CDMSources, "QuerySpellCount", "CDM_srcSpellCount")
    WrapProfilerFunction(ns.CDMSources, "QueryOverrideSpell", "CDM_srcOverride")
    WrapProfilerFunction(ns.CDMSources, "QuerySpellUsable", "CDM_srcSpellUsable")
    WrapProfilerFunction(ns.CDMSources, "QueryAuraDuration", "CDM_srcAuraDur")
    WrapProfilerFunction(ns.CDMSources, "QueryAuraDataByAuraInstanceID", "CDM_srcAuraData")
    WrapProfilerFunction(ns.CDMSources, "QueryUnitAuraBySpellID", "CDM_srcUnitAuraSpell")
    WrapProfilerFunction(ns.CDMSources, "QueryPlayerAuraBySpellID", "CDM_srcPlayerAuraSpell")
    WrapProfilerFunction(ns.CDMSources, "QueryAuraDataBySpellID", "CDM_srcAuraBySpell")
    WrapProfilerFunction(ns.CDMSources, "QueryCooldownAuraBySpellID", "CDM_srcCooldownAura")
    WrapProfilerFunction(ns.CDMSources, "QueryAuraDataBySpellName", "CDM_srcAuraByName")
    WrapProfilerFunction(ns.CDMSources, "QueryUnitAuras", "CDM_srcUnitAuras")
    InstallProfilerFrameWrappers()
    return true
end

local function RestoreProfilerWrappers()
    for scopeName, info in pairs(profilerWrappers) do
        if info.owner[info.methodName] == info.wrapper then
            info.owner[info.methodName] = info.original
        end
        profilerWrappers[scopeName] = nil
    end
    for scopeName, info in pairs(profilerFrameWrappers) do
        if info.frame:GetScript(info.scriptType) == info.wrapper then
            info.frame:SetScript(info.scriptType, info.original)
        end
        profilerFrameWrappers[scopeName] = nil
    end
end

local profilerRowLimit = 16

local function DrainProfilerRows()
    local rows = {}
    for i = 1, #profilerScopeOrder do
        local name = profilerScopeOrder[i]
        local scope = profilerScopes[name]
        if scope and scope.calls > 0 then
            rows[#rows + 1] = {
                name = scope.name,
                calls = scope.calls,
                allocatedBytes = scope.allocatedBytes,
                deallocatedBytes = scope.deallocatedBytes,
                elapsedMS = scope.elapsedMS,
            }
            scope.calls = 0
            scope.allocatedBytes = 0
            scope.deallocatedBytes = 0
            scope.elapsedMS = 0
        end
    end
    table.sort(rows, function(a, b)
        if a.allocatedBytes == b.allocatedBytes then
            return a.name < b.name
        end
        return a.allocatedBytes > b.allocatedBytes
    end)
    return rows
end

local function PrintProfilerRows(prefix, rows)
    if #rows == 0 then return end
    local parts = {}
    local limit = profilerRowLimit and math.min(profilerRowLimit, #rows) or #rows
    for i = 1, limit do
        local row = rows[i]
        parts[#parts + 1] = string.format(
            "%s +%s/-%s %dx %.1fms",
            row.name,
            FormatBytes(row.allocatedBytes),
            FormatBytes(row.deallocatedBytes),
            row.calls,
            row.elapsedMS)
    end
    if #rows > limit then
        parts[#parts + 1] = string.format("+%d more", #rows - limit)
    end
    print(prefix .. table.concat(parts, ", "))
end

local function SumProfilerRows(rows)
    local allocatedBytes, deallocatedBytes, calls = 0, 0, 0
    for i = 1, #rows do
        local row = rows[i]
        allocatedBytes = allocatedBytes + (row.allocatedBytes or 0)
        deallocatedBytes = deallocatedBytes + (row.deallocatedBytes or 0)
        calls = calls + (row.calls or 0)
    end
    return allocatedBytes, deallocatedBytes, calls
end

local function FormatSignedKB(kb)
    local prefix = kb > 0 and "+" or ""
    return prefix .. FormatKB(kb)
end

local MODULE_ALIASES = {
    CDM    = "CDM",
    AB     = "ActionBars",
    BB     = "BuffBorders",
    GF     = "GroupFrames",
    KB     = "Keybinds",
    RB     = "RaidBuffs",
    CB     = "CastBar",
    Prey   = "Preybar",
    Anch   = "Anchoring",
    Tooltip = "Tooltip",
    ActionBars     = "ActionBars",
    BuffBorders    = "BuffBorders",
    RotationAssist = "RotationAssist",
    AuraDispatch   = "AuraEvents",
    AuraRouter     = "AuraEvents",
}

local function ModuleOf(rowName)
    if not rowName then return "other" end
    local stripped = rowName:gsub("^FR_", "")
    local token = stripped:match("^([^_]+)")
    if not token then return "other" end
    return MODULE_ALIASES[token] or token
end

local function BuildModuleRollup(rows, heapDeltaKB)
    local modules = {}
    local order = {}
    local function bucket(name)
        local m = modules[name]
        if not m then
            m = {
                name = name,
                allocatedBytes = 0,
                deallocatedBytes = 0,
                calls = 0,
                elapsedMS = 0,
                synthetic = false,
            }
            modules[name] = m
            order[#order + 1] = m
        end
        return m
    end

    for i = 1, #rows do
        local row = rows[i]
        local mod = bucket(ModuleOf(row.name))
        mod.allocatedBytes   = mod.allocatedBytes   + (row.allocatedBytes   or 0)
        mod.deallocatedBytes = mod.deallocatedBytes + (row.deallocatedBytes or 0)
        mod.calls            = mod.calls            + (row.calls            or 0)
        mod.elapsedMS        = mod.elapsedMS        + (row.elapsedMS        or 0)
    end

    if heapDeltaKB ~= nil then
        local netKB = 0
        for i = 1, #order do
            netKB = netKB + (order[i].allocatedBytes - order[i].deallocatedBytes) / 1024
        end
        local gapKB = heapDeltaKB - netKB
        if gapKB > 0 then
            local u = bucket("[unattributed]")
            u.allocatedBytes = gapKB * 1024
            u.synthetic = true
        end
    end

    table.sort(order, function(a, b)
        return a.allocatedBytes > b.allocatedBytes
    end)
    return order
end

local function PrintModuleRollup(prefix, modules)
    if #modules == 0 then return end
    local parts = {}
    local limit = math.min(10, #modules)
    for i = 1, limit do
        local m = modules[i]
        if m.synthetic then
            parts[#parts + 1] = string.format("%s +%s",
                m.name, FormatBytes(m.allocatedBytes))
        elseif m.calls > 0 then
            local netBytes = m.allocatedBytes - m.deallocatedBytes
            parts[#parts + 1] = string.format("%s +%s net %s (%dx)",
                m.name,
                FormatBytes(m.allocatedBytes),
                FormatSignedKB(netBytes / 1024),
                m.calls)
        end
    end
    if #parts > 0 then
        print(prefix .. table.concat(parts, ", "))
    end
end

local function PrintProfilerSummary(prefix, rows, heapDeltaKB)
    if #rows == 0 and heapDeltaKB == nil then return end

    local allocatedBytes, deallocatedBytes, calls = SumProfilerRows(rows)
    local measuredNetKB = (allocatedBytes - deallocatedBytes) / 1024
    local line = string.format(
        "%s+%s/-%s net %s over %d calls",
        prefix,
        FormatBytes(allocatedBytes),
        FormatBytes(deallocatedBytes),
        FormatSignedKB(measuredNetKB),
        calls)

    if heapDeltaKB ~= nil then
        local grossAllocKB = allocatedBytes / 1024
        line = string.format(
            "%s; heap Δ %s; gap vs row-net %s; gap vs gross %s",
            line,
            FormatSignedKB(heapDeltaKB),
            FormatSignedKB(heapDeltaKB - measuredNetKB),
            FormatSignedKB(heapDeltaKB - grossAllocKB))
    end

    print(line)
end

local function PrintSnapshot(snap, prev)
    local P = print
    P("|cff60A5FA--- QUI Memory Audit ---|r")
    P(string.format("  Total: |cffFFFFFF%s|r  %s",
        FormatKB(snap._totalKB),
        snap._combat and "|cffFF4444IN COMBAT|r" or "|cff44FF44out of combat|r"))

    if prev then
        local delta = snap._totalKB - prev._totalKB
        local dt = snap._time - prev._time
        P(string.format("  Delta: |cff%s%s%s|r over %.0fs (%.1f KB/s)",
            delta > 0 and "FF8844" or "44FF44",
            delta > 0 and "+" or "",
            FormatKB(delta),
            dt,
            dt > 0 and (delta / dt) or 0))
    end

    local sorted = {}
    local counters = {}
    for name, val in pairs(snap) do
        if name:sub(1, 1) ~= "_" then
            if type(val) == "table" and val.counter then
                counters[#counters + 1] = { name = name, value = val.value or 0 }
            elseif type(val) == "table" then
                sorted[#sorted + 1] = { name = name, count = val.count, deep = val.deep }
            else
                sorted[#sorted + 1] = { name = name, count = val, deep = 0 }
            end
        end
    end
    table.sort(sorted, function(a, b) return (a.count + a.deep) > (b.count + b.deep) end)

    P("  |cffAAAAAA--- Probed Tables ---|r")
    for _, entry in ipairs(sorted) do
        local line = string.format("  %-35s %5d entries", entry.name, entry.count)
        if entry.deep > 0 then
            line = line .. string.format("  (%d nested)", entry.deep)
        end
        if prev and prev[entry.name] then
            local prevTotal
            if type(prev[entry.name]) == "table" then
                prevTotal = prev[entry.name].count + prev[entry.name].deep
            else
                prevTotal = prev[entry.name]
            end
            local curTotal = entry.count + entry.deep
            local d = curTotal - prevTotal
            if d ~= 0 then
                line = line .. string.format("  |cff%s%s%d|r",
                    d > 0 and "FF8844" or "44FF44",
                    d > 0 and "+" or "", d)
            end
        end
        P(line)
    end

    if #sorted == 0 then
        P("  |cffFF4444No probes registered.|r Register with ns._memprobes.")
    end

    if #counters > 0 then
        table.sort(counters, function(a, b) return a.name < b.name end)
        P("  |cffAAAAAA--- Counters ---|r")
        for _, entry in ipairs(counters) do
            local line = string.format("  %-35s %5d", entry.name, entry.value)
            if prev and prev[entry.name] and prev[entry.name].counter then
                local d = entry.value - (prev[entry.name].value or 0)
                if d ~= 0 then
                    line = line .. string.format("  |cff%s%s%d|r",
                        d > 0 and "FF8844" or "44FF44",
                        d > 0 and "+" or "", d)
                end
            end
            P(line)
        end
    end
end

local function GetExperiments()
    return ns.QUI_PerfExperiments or {}
end

local function FindExperiment(name)
    if not name then return nil end
    local exps = GetExperiments()
    for i = 1, #exps do
        if exps[i].name == name then return exps[i] end
    end
    return nil
end

local function FormatExperimentState(exp)
    local ok, on = pcall(exp.isEnabled)
    if not ok then return "|cffAAAAAA?|r" end
    return on and "|cff44FF44on|r" or "|cffFF4444off|r"
end

local function PrintExperimentsList()
    local exps = GetExperiments()
    if #exps == 0 then
        print("|cff60A5FA[memaudit exp]|r no experiments registered")
        return
    end
    print("|cff60A5FA[memaudit exp]|r registered experiments:")
    for i = 1, #exps do
        local e = exps[i]
        print(string.format("  %-22s %s  %s",
            e.name, FormatExperimentState(e), e.description or ""))
    end
    print("  |cffAAAAAA→ flip: /qui memaudit exp <name> [on|off]   reset: exp reset|r")
end

local function SetExperimentState(exp, on)
    local ok, err = pcall(exp.setEnabled, on)
    if not ok then
        print(string.format("|cff60A5FA[memaudit exp]|r %s setEnabled failed: %s",
            exp.name, tostring(err)))
        return
    end
    print(string.format("|cff60A5FA[memaudit exp]|r %s → %s",
        exp.name, on and "|cff44FF44on|r" or "|cffFF4444off|r"))
end

local function HandleExperiment(arg)
    if not arg or arg == "" then
        PrintExperimentsList()
        return
    end

    if arg == "reset" then
        local exps = GetExperiments()
        for i = 1, #exps do
            ns.SafeCall("report", exps[i].setEnabled, true)
        end
        print("|cff60A5FA[memaudit exp]|r all experiments restored to production (on)")
        return
    end

    local name, state = arg:match("^(%S+)%s+(%S+)$")
    if not name then name = arg end

    local exp = FindExperiment(name)
    if not exp then
        print(string.format("|cff60A5FA[memaudit exp]|r unknown experiment '%s'", name))
        PrintExperimentsList()
        return
    end

    if state == "on" or state == "1" or state == "true" then
        SetExperimentState(exp, true)
    elseif state == "off" or state == "0" or state == "false" then
        SetExperimentState(exp, false)
    elseif state == nil then
        local ok, current = pcall(exp.isEnabled)
        SetExperimentState(exp, not (ok and current))
    else
        print(string.format("|cff60A5FA[memaudit exp]|r '%s' is not on/off", state))
    end
end

local function ExperimentLabel()
    local exps = GetExperiments()
    if #exps == 0 then return "" end
    local parts
    for i = 1, #exps do
        local e = exps[i]
        local ok, on = pcall(e.isEnabled)
        if ok and on == false then
            parts = parts or {}
            parts[#parts + 1] = e.name .. "=off"
        end
    end
    if not parts then return "" end
    return "  |cffFFC85C[exp " .. table.concat(parts, ",") .. "]|r"
end

local autoFrame = CreateFrame("Frame")
autoFrame:Hide()
local autoEnabled = false
local autoInterval = 5.0
local autoElapsed = 0
local autoLastSnap = nil
local autoCombatStartSnap = nil

local function PrintAutoLine(snap, prev)
    local P = print
    local line
    if prev then
        local delta = snap._totalKB - prev._totalKB
        local dt = snap._time - prev._time
        local rate = dt > 0 and (delta / dt) or 0
        line = string.format(
            "|cff60A5FA[memaudit auto]|r  %s  Δ |cff%s%s%s|r over %.0fs (|cffFFFFFF%.1f KB/s|r)",
            FormatKB(snap._totalKB),
            delta > 0 and "FF8844" or "44FF44",
            delta > 0 and "+" or "",
            FormatKB(delta),
            dt,
            rate)
    else
        line = string.format("|cff60A5FA[memaudit auto]|r  %s  (baseline)%s",
            FormatKB(snap._totalKB), ExperimentLabel())
    end
    P(line)

    if prev then
        local totalGrew = (snap._totalKB - prev._totalKB) > 0
        local growers = {}
        for name, val in pairs(snap) do
            if name:sub(1, 1) ~= "_" and prev[name] then
                local prevTotal, curTotal
                if type(prev[name]) == "table" and prev[name].counter then
                    prevTotal = nil
                elseif type(prev[name]) == "table" then
                    prevTotal = prev[name].count + prev[name].deep
                else
                    prevTotal = prev[name]
                end
                if type(val) == "table" and val.counter then
                    curTotal = nil
                elseif type(val) == "table" then
                    curTotal = val.count + val.deep
                else
                    curTotal = val
                end
                if prevTotal and curTotal then
                    local d = curTotal - prevTotal
                    if d > 0 then
                        growers[#growers + 1] = { name = name, delta = d }
                    end
                end
            end
        end
        if #growers > 0 then
            table.sort(growers, function(a, b) return a.delta > b.delta end)
            local parts = {}
            for i = 1, math.min(5, #growers) do
                parts[#parts + 1] = string.format("%s +%d", growers[i].name, growers[i].delta)
            end
            P("  |cffAAAAAA→ probed grew:|r " .. table.concat(parts, ", "))
        elseif totalGrew then
            P("  |cffAAAAAA→ no probed table grew — heap growth is outside probes|r")
        end

        local counterParts = {}
        for name, val in pairs(snap) do
            local prevVal = prev[name]
            if name:sub(1, 1) ~= "_" and type(val) == "table" and val.counter
                and type(prevVal) == "table" and prevVal.counter
            then
                local d = (val.value or 0) - (prevVal.value or 0)
                if d ~= 0 then
                    counterParts[#counterParts + 1] = string.format("%s %s%d", name, d > 0 and "+" or "", d)
                end
            end
        end
        if #counterParts > 0 then
            table.sort(counterParts)
            P("  |cffAAAAAA→ counters:|r " .. table.concat(counterParts, ", "))
        end
    end

    local profilerRows = DrainProfilerRows()
    local heapDeltaKB = prev and (snap._totalKB - prev._totalKB) or nil
    if prev then
        PrintProfilerSummary("  |cffAAAAAA→ profiler row sum:|r ", profilerRows, heapDeltaKB)
    end
    local modules = BuildModuleRollup(profilerRows, heapDeltaKB)
    PrintModuleRollup("  |cffAAAAAA→ by module:|r ", modules)
    PrintProfilerRows("  |cffAAAAAA→ profiler alloc:|r ", profilerRows)
end

autoFrame:SetScript("OnUpdate", function(self, elapsed)
    if not autoEnabled then return end
    autoElapsed = autoElapsed + elapsed
    if autoElapsed < autoInterval then return end
    autoElapsed = 0
    if not InCombatLockdown() then return end

    local snap = TakeSnapshot()
    PrintAutoLine(snap, autoLastSnap)
    autoLastSnap = snap
end)

autoFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
autoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
autoFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        autoElapsed = 0
        DrainProfilerRows()
        profilerActive = autoEnabled and InstallProfilerWrappers()
        autoCombatStartSnap = autoEnabled and TakeSnapshot() or nil
        autoLastSnap = autoCombatStartSnap
    elseif event == "PLAYER_REGEN_ENABLED" and autoEnabled and autoCombatStartSnap then
        local snap = TakeSnapshot()
        local startKB = autoCombatStartSnap._totalKB
        print(string.format("|cff60A5FA[memaudit auto]|r combat ended — final %s (Δ from combat-start %s)%s",
            FormatKB(snap._totalKB),
            FormatKB(snap._totalKB - startKB),
            ExperimentLabel()))
        local profilerRows = DrainProfilerRows()
        local heapDeltaKB = snap._totalKB - startKB
        PrintProfilerSummary("  |cffAAAAAA→ profiler row sum:|r ", profilerRows, heapDeltaKB)
        local modules = BuildModuleRollup(profilerRows, heapDeltaKB)
        PrintModuleRollup("  |cffAAAAAA→ by module:|r ", modules)
        PrintProfilerRows("  |cffAAAAAA→ profiler alloc:|r ", profilerRows)
        profilerActive = false
        autoLastSnap = nil
        autoCombatStartSnap = nil
        C_Timer.After(0.5, function()
            if autoEnabled and not InCombatLockdown() then
                collectgarbage("collect")
                local post = TakeSnapshot()
                print(string.format("|cff60A5FA[memaudit auto]|r post-GC — final %s (Δ from combat-start %s)",
                    FormatKB(post._totalKB),
                    FormatKB(post._totalKB - startKB)))
            end
        end)
    end
end)

local function ToggleAuto(arg)
    if arg == "off" or arg == "0" or arg == "stop" then
        autoEnabled = false
        profilerActive = false
        RestoreProfilerWrappers()
        DrainProfilerRows()
        autoFrame:Hide()
        autoLastSnap = nil
        autoCombatStartSnap = nil
        print("|cff60A5FAQUI memaudit auto:|r |cffFF4444off|r")
        return
    end

    local n = tonumber(arg)
    if n and n >= 1 then
        autoInterval = n
    end

    if not autoEnabled then
        autoEnabled = true
        InstallProfilerWrappers()
        profilerActive = InCombatLockdown() and DetectAddOnProfiler()
        DrainProfilerRows()
        autoElapsed = 0
        autoLastSnap = nil
        autoFrame:Show()
        print(string.format(
            "|cff60A5FAQUI memaudit auto:|r |cff44FF44on|r — printing every %ds while in combat",
            autoInterval))
    else
        if n then
            print(string.format("|cff60A5FAQUI memaudit auto:|r interval = %ds", autoInterval))
        else
            autoEnabled = false
            profilerActive = false
            RestoreProfilerWrappers()
            DrainProfilerRows()
            autoFrame:Hide()
            autoLastSnap = nil
            autoCombatStartSnap = nil
            print("|cff60A5FAQUI memaudit auto:|r |cffFF4444off|r")
        end
    end
end

_G.QUI_MemAudit = function(subcmd, arg)
    if subcmd == "gc" then
        ns.SafeCall("best-effort-style", UpdateAddOnMemoryUsage)
        local before = SumSuiteMemoryKB()
        collectgarbage("collect")
        ns.SafeCall("best-effort-style", UpdateAddOnMemoryUsage)
        local after = SumSuiteMemoryKB()
        print(string.format("|cff60A5FAQUI GC:|r Before: %s  After: %s  Freed: |cff44FF44%s|r",
            FormatKB(before), FormatKB(after), FormatKB(before - after)))
        return
    end

    if subcmd == "auto" then
        ToggleAuto(arg)
        return
    end

    if subcmd == "exp" then
        HandleExperiment(arg)
        return
    end

    if subcmd == "rows" then
        if arg == "all" or arg == "0" then
            profilerRowLimit = nil
            print("|cff60A5FAQUI memaudit:|r allocation scopes = |cff44FF44all|r (full breakdown)")
        else
            local n = tonumber(arg)
            if n and n >= 1 then
                profilerRowLimit = math.floor(n)
                print(string.format("|cff60A5FAQUI memaudit:|r allocation scopes = %d", profilerRowLimit))
            else
                print("|cff60A5FAQUI memaudit:|r usage: /qui memaudit rows <n|all>")
            end
        end
        return
    end

    local snap = TakeSnapshot()
    PrintSnapshot(snap, lastSnapshot)
    lastSnapshot = snap
end
