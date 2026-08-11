-- tests/unit/cdm_reanchor_activestate_scheduler_test.lua
-- Run: lua tests/unit/cdm_reanchor_activestate_scheduler_test.lua
--
-- Root cause under test: cdm_containers' scheduleActiveState held ONE pending
-- callback in a single upvalue while BOTH hook instances (buff/essential/utility
-- + trackedBar) schedule through it. Overlapping active-state flips (a buff-icon
-- and a tracked-bar aura changing within the 2-tick settle window -- routine at
-- pull start) made the second schedule overwrite the first: the losing instance's
-- flush never ran and its _activeScheduled latch stuck true for the whole
-- session, leaving that surface permanently deaf to OnActiveStateChanged.
local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_reanchor_hooks.lua", "cdm_reanchor_hooks.lua")("QUI", ns)
local H = assert(ns.CDMReanchorHooks, "CDMReanchorHooks should be exported")

assert(type(H.CreateActiveStateScheduler) == "function",
    "CreateActiveStateScheduler factory must be exported on CDMReanchorHooks")

-- fake CreateFrame capturing the OnUpdate driver so the test drives the ticks
local fakeFrame
local function fakeCreateFrame()
    fakeFrame = {
        shown = false,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetScript = function(self, name, fn) self[name] = fn end,
    }
    return fakeFrame
end
local function tick(n)
    for _ = 1, n or 1 do
        if fakeFrame and fakeFrame.shown and fakeFrame.OnUpdate then
            fakeFrame.OnUpdate(fakeFrame)
        end
    end
end

-- Factory semantics: EVERY pending callback runs on settle (the single-slot
-- overwrite is the bug), and the scheduler re-arms after a flush.
do
    local sched = H.CreateActiveStateScheduler(fakeCreateFrame)
    local ran = {}
    sched(function() ran[#ran + 1] = "a" end)
    sched(function() ran[#ran + 1] = "b" end)
    assert(#ran == 0, "no callback runs before the settle ticks elapse")
    tick(2)
    assert(#ran == 2 and ran[1] == "a" and ran[2] == "b",
        "both callbacks scheduled within one settle window must run (single-slot drop)")
    assert(fakeFrame.shown == false, "driver frame hides after the flush")

    sched(function() ran[#ran + 1] = "c" end)
    tick(2)
    assert(#ran == 3 and ran[3] == "c", "scheduler re-arms after a flush")
end

-- Two hook instances sharing one scheduler: an overlapping flip must flush BOTH,
-- and neither instance's _activeScheduled latch may be orphaned afterwards.
do
    local sched = H.CreateActiveStateScheduler(fakeCreateFrame)
    local refreshed = {}
    local function mk(key)
        return H.New({
            refresh = function(k) refreshed[#refreshed + 1] = k end,
            keys = { key },
            scheduleActiveState = sched,
        })
    end
    local buffHooks, barHooks = mk("buff"), mk("trackedBar")

    buffHooks:MarkActiveStateDirty("buff")
    barHooks:MarkActiveStateDirty("trackedBar")
    tick(2)
    local seen = {}
    for _, k in ipairs(refreshed) do seen[k] = true end
    assert(seen.buff and seen.trackedBar,
        "overlapping active-state flips must flush BOTH hook instances")

    -- The regression's signature: the losing instance latched forever.
    refreshed = {}
    buffHooks:MarkActiveStateDirty("buff")
    tick(2)
    assert(#refreshed == 1 and refreshed[1] == "buff",
        "buff instance stays responsive after a shared-window flip (no permanent latch)")

    refreshed = {}
    barHooks:MarkActiveStateDirty("trackedBar")
    tick(2)
    assert(#refreshed == 1 and refreshed[1] == "trackedBar",
        "trackedBar instance stays responsive after a shared-window flip")
end

-- Starvation deadline: the settle counter resets on every enqueue, so a
-- combat-start burst that re-enqueues every frame (OnActiveStateChanged /
-- frame-OnShow churn while every utility cooldown activates) kept the flush
-- from EVER firing -- unclaimed frames sat visible at the native viewer
-- position for the whole churn. A hard age deadline must bound the wait.
do
    local sched = H.CreateActiveStateScheduler(fakeCreateFrame)
    local ran = 0
    sched(function() ran = ran + 1 end)
    for _ = 1, 12 do
        tick(1)
        sched(function() end) -- churn: one new enqueue per frame, forever
    end
    assert(ran >= 1,
        "continuous per-frame enqueue churn must not starve the flush (hard deadline)")

    -- and the scheduler still settles normally after the storm
    local settled = false
    sched(function() settled = true end)
    tick(2)
    assert(settled, "scheduler recovers to normal 2-tick settle after a deadline flush")
end

-- cdm_containers must wire the shared factory instead of a local single-slot closure.
do
    local f = assert(io.open("QUI_CDM/cdm/cdm_containers.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    assert(src:find("CDMReanchorHooks.CreateActiveStateScheduler", 1, true),
        "cdm_containers must build scheduleActiveState via CDMReanchorHooks.CreateActiveStateScheduler")
    assert(not src:find("local activeStateFn\n", 1, true),
        "the single-slot activeStateFn upvalue must be gone from cdm_containers")
end

print("OK: cdm_reanchor_activestate_scheduler_test")
