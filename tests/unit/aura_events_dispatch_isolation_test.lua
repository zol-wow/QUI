-- tests/unit/aura_events_dispatch_isolation_test.lua
-- Run: lua tests/unit/aura_events_dispatch_isolation_test.lua
--
-- A throwing subscriber aborted the coalesce OnUpdate mid-loop: remaining
-- units were never dispatched, merged accumulators kept stale deltas with
-- _isMerged still set, and pendingUnits was never wiped — the next event
-- re-dispatched stale units against corrupt accumulators. Dispatch must be
-- wrapped per unit (error forwarded to geterrorhandler) with cleanup and the
-- final wipe unconditional.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("core/aura_events.lua")

assert(source:find("local function DispatchUnit(", 1, true),
    "per-unit dispatch must be a named function (pcall without closure alloc)")
assert(source:find("pcall(DispatchUnit", 1, true),
    "per-unit dispatch must be protected")
assert(source:find("geterrorhandler", 1, true),
    "dispatch errors must stay loud via geterrorhandler")

-- the pcall must precede accumulator cleanup and the final wipe within the
-- OnUpdate body so cleanup is unconditional
local onUpd = assert(source:find('coalesceFrame:SetScript("OnUpdate"', 1, true))
local pcallIdx = assert(source:find("pcall(DispatchUnit", onUpd, true))
local wipeIdx = assert(source:find("wipe(pendingUnits)", onUpd, true))
assert(pcallIdx < wipeIdx, "wipe(pendingUnits) must follow protected dispatch")

print("PASS aura_events_dispatch_isolation_test")
