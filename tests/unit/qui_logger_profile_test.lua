-- tests/unit/qui_logger_profile_test.lua
-- Run: lua tests/unit/qui_logger_profile_test.lua
local P = assert(loadfile("tests/replay/profile_replay.lua"))()

-- 1. measure(fn): returns alloc KB + cpu ms; retained allocation shows up positive
local sink
local m = P.measure(function()
    sink = {}
    for i = 1, 5000 do sink[i] = { i, i, i } end   -- retained so GC can't reclaim mid-measure
end)
assert(type(m.allocKB) == "number" and type(m.cpuMs) == "number", "measure must return numbers")
assert(m.allocKB > 0, "retained allocation must register positive KB, got: " .. m.allocKB)
assert(sink and #sink == 5000, "fn must have run")

-- 2. profilePerKey: churn bucketed by key; the heavy key outweighs the light one
local items = {
    { k = "light" }, { k = "heavy" }, { k = "light" }, { k = "heavy" },
}
local keep = {}
local churn, counts = P.profilePerKey(
    items,
    function(it) return it.k end,
    function(it)
        if it.k == "heavy" then
            local t = {}
            for i = 1, 4000 do t[i] = { i } end
            keep[#keep + 1] = t            -- retain heavy allocations
        else
            keep[#keep + 1] = { 1 }        -- tiny
        end
    end)
assert(churn.heavy > churn.light, "heavy key must out-churn light: heavy=" .. churn.heavy .. " light=" .. churn.light)
assert(counts.heavy == 2 and counts.light == 2, "counts must tally per key")

-- 3. report: sorted descending by churn, one line per key, heaviest first
local rep = P.report({ a = 1.0, big = 100.0, mid = 50.0 }, { a = 1, big = 3, mid = 2 })
local firstLine = rep:match("^[^\n]*")
assert(firstLine:find("big", 1, true), "heaviest key must be first line, got: " .. firstLine)
assert(select(2, rep:gsub("\n", "\n")) + 1 == 3, "report must have 3 lines")

print("qui_logger_profile_test: OK")
