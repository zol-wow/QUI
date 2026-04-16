local ADDON_NAME, ns = ...
----------------------------------------------------------------------------
-- Memory Audit — runtime probe for cache/pool sizes
--
-- Usage:  /qui memaudit        → snapshot current sizes + GC stats
--         /qui memaudit diff   → show delta from last snapshot
--         /qui memaudit gc     → force full GC and report reclaimable
--
-- Modules register probes BEFORE this file loads by pushing entries onto
-- ns._memprobes = { { name = "...", tbl = tbl }, ... }
-- This file drains the list at load time.
----------------------------------------------------------------------------

local probes = {}
local lastSnapshot = nil

-- Drain any probes registered by modules that loaded before us
local pending = ns._memprobes
if pending then
    for i = 1, #pending do
        probes[#probes + 1] = pending[i]
    end
end
-- Keep ns._memprobes alive so late-loading modules can still push
ns._memprobes = probes

-- Count entries in a table (shallow + one-level nested)
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

local function TakeSnapshot()
    local snap = {}
    for i = 1, #probes do
        local p = probes[i]
        if p.fn then
            snap[p.name] = p.fn()
        elseif p.tbl then
            local count, deep = CountEntries(p.tbl)
            snap[p.name] = { count = count, deep = deep }
        end
    end

    pcall(UpdateAddOnMemoryUsage)
    local ok, mem = pcall(GetAddOnMemoryUsage, ADDON_NAME)
    snap._totalKB = ok and mem or 0
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

    -- Sort probes by total entry count descending
    local sorted = {}
    for name, val in pairs(snap) do
        if name:sub(1, 1) ~= "_" then
            if type(val) == "table" then
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
end

_G.QUI_MemAudit = function(subcmd)
    if subcmd == "gc" then
        pcall(UpdateAddOnMemoryUsage)
        local ok1, before = pcall(GetAddOnMemoryUsage, ADDON_NAME)
        collectgarbage("collect")
        pcall(UpdateAddOnMemoryUsage)
        local ok2, after = pcall(GetAddOnMemoryUsage, ADDON_NAME)
        if ok1 and ok2 then
            print(string.format("|cff60A5FAQUI GC:|r Before: %s  After: %s  Freed: |cff44FF44%s|r",
                FormatKB(before), FormatKB(after), FormatKB(before - after)))
        end
        return
    end

    local snap = TakeSnapshot()
    PrintSnapshot(snap, lastSnapshot)
    lastSnapshot = snap
end
