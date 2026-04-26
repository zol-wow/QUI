local ADDON_NAME, ns = ...
----------------------------------------------------------------------------
-- Memory Audit — runtime probe for cache/pool sizes
--
-- Usage:  /qui memaudit              → snapshot current sizes + GC stats
--         /qui memaudit diff         → show delta from last snapshot
--         /qui memaudit gc           → force full GC and report reclaimable
--         /qui memaudit auto         → toggle 5s combat auto-print on/off
--         /qui memaudit auto N       → set auto interval to N seconds
--         /qui memaudit auto off     → turn auto off
--
-- Modules register probes BEFORE this file loads by pushing entries onto
-- ns._memprobes = { { name = "...", tbl = tbl }, ... }
-- This file drains the list at load time. Probes can also be `fn = function()
-- return number end` for computed counts (e.g. multi-table pools).
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

local function ProbeTotal(snap)
    local count, deep = 0, 0
    for name, val in pairs(snap) do
        if name:sub(1, 1) ~= "_" then
            if type(val) == "table" and not val.counter then
                count = count + (val.count or 0)
                deep = deep + (val.deep or 0)
            elseif type(val) ~= "table" then
                count = count + (val or 0)
            end
        end
    end
    return count, deep
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

----------------------------------------------------------------------------
-- AUTO MODE: periodic snapshots while in combat. Prints a compact one-liner
-- per tick, and surfaces any probed tables that grew between ticks (so we
-- can spot retention live without scrolling through a full audit).
----------------------------------------------------------------------------
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
        line = string.format("|cff60A5FA[memaudit auto]|r  %s  (baseline)", FormatKB(snap._totalKB))
    end
    P(line)

    -- If the total grew, surface which probed tables grew (to attribute the
    -- delta) and how much of the delta is unaccounted-for (== outside probes).
    if prev and (snap._totalKB - prev._totalKB) > 0 then
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
        else
            P("  |cffAAAAAA→ no probed table grew — retention is outside probes|r")
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

-- PLAYER_REGEN_DISABLED resets baseline so the first in-combat tick is a
-- meaningful baseline rather than a stale OOC reading.
autoFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
autoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
autoFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        autoElapsed = 0
        autoCombatStartSnap = autoEnabled and TakeSnapshot() or nil
        autoLastSnap = autoCombatStartSnap
    elseif event == "PLAYER_REGEN_ENABLED" and autoEnabled and autoCombatStartSnap then
        -- Combat ended: print one final summary line.
        local snap = TakeSnapshot()
        local startKB = autoCombatStartSnap._totalKB
        print(string.format("|cff60A5FA[memaudit auto]|r combat ended — final %s (Δ from combat-start %s)",
            FormatKB(snap._totalKB),
            FormatKB(snap._totalKB - startKB)))
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
        autoFrame:Hide()
        autoLastSnap = nil
        autoCombatStartSnap = nil
        print("|cff60A5FAQUI memaudit auto:|r |cffFF4444off|r")
        return
    end

    -- "auto N" sets interval; "auto" toggles
    local n = tonumber(arg)
    if n and n >= 1 then
        autoInterval = n
    end

    if not autoEnabled then
        autoEnabled = true
        autoElapsed = 0
        autoLastSnap = nil
        autoFrame:Show()
        print(string.format(
            "|cff60A5FAQUI memaudit auto:|r |cff44FF44on|r — printing every %ds while in combat",
            autoInterval))
    else
        -- Already on, just changed interval
        if n then
            print(string.format("|cff60A5FAQUI memaudit auto:|r interval = %ds", autoInterval))
        else
            -- No arg → toggle off
            autoEnabled = false
            autoFrame:Hide()
            autoLastSnap = nil
            autoCombatStartSnap = nil
            print("|cff60A5FAQUI memaudit auto:|r |cffFF4444off|r")
        end
    end
end

_G.QUI_MemAudit = function(subcmd, arg)
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

    if subcmd == "auto" then
        ToggleAuto(arg)
        return
    end

    local snap = TakeSnapshot()
    PrintSnapshot(snap, lastSnapshot)
    lastSnapshot = snap
end
