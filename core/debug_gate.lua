----------------------------------------------------------------------------
-- Debug instrumentation gate
--
-- Main-addon files register their debug instrumentation (stats counters,
-- ns._memprobes probes, QUI_PerfRegistry frames, QUI_PerfExperiments
-- toggles, profiler Mark/Measure bindings) via ns.DebugRegister(fn).
-- The closures stay queued -- zero hot-path cost -- until QUI_Debug loads
-- and its activate.lua (LAST file in debug.xml) calls ns.DebugActivate().
--
-- Contract for instrumented files (eager fallback keeps standalone unit
-- tests working without this file):
--
--     if ns.DebugRegister then
--         ns.DebugRegister(SetupDebugInstrumentation)
--     else
--         SetupDebugInstrumentation()
--     end
--
-- This file must stay the FIRST entry in core/core.xml so the gate exists
-- before any instrumented file loads. Covered by tests/unit/debug_gate_test.lua.
----------------------------------------------------------------------------
local _, ns = ...

local pending = {}
local active = false

-- Queue fn until activation; run immediately if already active (modules
-- that load after QUI_Debug, e.g. on-demand loads). No pcall: a broken
-- setup closure should fail loudly at activation, a debug-only context.
function ns.DebugRegister(fn)
    if active then
        fn()
    else
        pending[#pending + 1] = fn
    end
end

function ns.DebugActivate()
    if active then return end
    -- active is set BEFORE the drain so a closure that itself calls
    -- DebugRegister runs immediately instead of being stranded in the queue.
    active = true
    for i = 1, #pending do
        pending[i]()
        pending[i] = nil
    end
end
