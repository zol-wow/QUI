-- tests/unit/cdm_scheduler_latency_test.lua
-- Run: lua tests/unit/cdm_scheduler_latency_test.lua

local frameScripts = {}
local fakeFrame = {
    SetScript = function(_, scriptName, handler)
        frameScripts[scriptName] = handler
    end,
}

function geterrorhandler()
    return function(err) error(err, 0) end
end

function CreateFrame()
    return fakeFrame
end

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_scheduler.lua", "cdm_scheduler.lua")("QUI", ns)

local scheduler = assert(ns.CDMScheduler, "CDMScheduler should be exported")
local delayCalls = {}
local runCalls = {}
local enabled = true

scheduler.SetRuntimeUpdateHandler({
    getDelay = function(fast, mode)
        delayCalls[#delayCalls + 1] = {
            fast = fast,
            mode = mode,
        }
        if fast then
            if mode == "cooldown" then
                return 0
            end
            return 0.05
        end
        return 0.30
    end,
    isEnabled = function()
        return enabled
    end,
    run = function(mode)
        runCalls[#runCalls + 1] = {
            mode = mode,
        }
    end,
})

scheduler.ScheduleRuntimeUpdate(false, "cooldown")
assert(delayCalls[1].fast == false, "slow request should pass fast=false to delay provider")
assert(delayCalls[1].mode == "cooldown", "delay provider should receive cooldown mode")

assert(frameScripts.OnUpdate, "scheduling should install OnUpdate")
frameScripts.OnUpdate(fakeFrame, 0.10)
assert(#runCalls == 0, "slow 0.30s update should not run after 0.10s")

scheduler.ScheduleRuntimeUpdate(true, "full")
assert(delayCalls[2].fast == true, "fast request should pass fast=true to delay provider")
assert(delayCalls[2].mode == "full", "delay provider should receive full mode")

frameScripts.OnUpdate(fakeFrame, 0)
assert(#runCalls == 1, "pending slow update should flush once a shorter fast delay is merged")
assert(runCalls[1].mode == "full", "merged mode should upgrade to full")

scheduler.ScheduleRuntimeUpdate(true, "cooldown")
assert(delayCalls[3].mode == "cooldown", "next-frame cooldown request should expose cooldown mode")
frameScripts.OnUpdate(fakeFrame, 0)
assert(#runCalls == 2, "zero-delay fast cooldown update should run on the next OnUpdate")
assert(runCalls[2].mode == "cooldown", "fast cooldown request should run cooldown mode")

scheduler.ScheduleRuntimeUpdate(false, "full")
assert(scheduler.IsRuntimeUpdatePending() == true, "enabled scheduler should leave runtime update pending")
enabled = false
scheduler.ScheduleRuntimeUpdate(true, "full")
assert(scheduler.IsRuntimeUpdatePending() == false, "disabled scheduler should cancel pending runtime update")

print("OK: cdm_scheduler_latency_test")
