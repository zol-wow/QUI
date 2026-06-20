-- tests/replay/profile_replay.lua
-- Allocation/CPU profiler for offline replay. WoW addon memory IS the Lua heap
-- (WoW runs Lua 5.1; GetAddOnMemoryUsage reports the same GC that
-- collectgarbage("count") exposes), so driving real subsystem code with a
-- captured event stream and sampling the GC reproduces the in-game allocation
-- churn that causes combat GC stutter -- deterministically and A/B-able.
--
-- Caveats: measures the Lua heap only (not WoW C-side frame/texture memory or
-- real render cost). collectgarbage("count") is current live heap; if the GC
-- auto-fires under allocation pressure mid-measure, a churn figure undercounts
-- total garbage. Treat the numbers as a relative, repeatable A/B signal rather
-- than an absolute byte count.
local P = {}

-- Run fn against a clean GC baseline; return live-heap growth (KB) and wall ms.
function P.measure(fn)
    collectgarbage("collect")
    local kb0 = collectgarbage("count")
    local t0 = os.clock()
    fn()
    local cpuMs = (os.clock() - t0) * 1000
    local allocKB = collectgarbage("count") - kb0
    return { allocKB = allocKB, cpuMs = cpuMs }
end

-- Apply applyFn to each item, bucketing heap growth by keyFn(item). Returns
-- (churnKB-by-key, count-by-key). Sampling per item attributes allocation to
-- the handler that caused it -- e.g. ranking which event type churns most.
function P.profilePerKey(items, keyFn, applyFn)
    local churn, counts = {}, {}
    for i = 1, #items do
        local item = items[i]
        local key = keyFn(item)
        local before = collectgarbage("count")
        applyFn(item)
        local delta = collectgarbage("count") - before
        churn[key] = (churn[key] or 0) + delta
        counts[key] = (counts[key] or 0) + 1
    end
    return churn, counts
end

-- Format a churn table (and optional count table) as descending-by-KB lines.
function P.report(churn, counts)
    local arr = {}
    for k, v in pairs(churn) do
        arr[#arr + 1] = { k, v, counts and counts[k] or 0 }
    end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    local lines = {}
    for i = 1, #arr do
        lines[i] = string.format("%12.1f KB  %8d x  %s", arr[i][2], arr[i][3], arr[i][1])
    end
    return table.concat(lines, "\n")
end

return P
