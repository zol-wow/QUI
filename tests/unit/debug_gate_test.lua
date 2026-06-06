-- tests/unit/debug_gate_test.lua
-- Run: lua tests/unit/debug_gate_test.lua
-- The debug-instrumentation gate: registrations queue until QUI_Debug
-- activates them (core/debug_gate.lua + QUI_Debug/activate.lua).

local ns = {}
assert(loadfile("core/debug_gate.lua"))("QUI", ns)

assert(type(ns.DebugRegister) == "function", "gate must define ns.DebugRegister")
assert(type(ns.DebugActivate) == "function", "gate must define ns.DebugActivate")

-- 1. Dormant by default: registrations must not run before activation.
local ran = {}
ns.DebugRegister(function() ran[#ran + 1] = "a" end)
ns.DebugRegister(function() ran[#ran + 1] = "b" end)
assert(#ran == 0, "registrations must not run before activation")

-- 2. Activation drains the queue in registration order.
ns.DebugActivate()
assert(table.concat(ran, ",") == "a,b",
    "activation must drain queue in order, got: " .. table.concat(ran, ","))

-- 3. Registration after activation runs immediately (late-loading modules).
ns.DebugRegister(function() ran[#ran + 1] = "c" end)
assert(table.concat(ran, ",") == "a,b,c", "late registration must run immediately")

-- 4. Double activation is a no-op.
ns.DebugActivate()
assert(#ran == 3, "double activation must not re-run closures")

-- 4b. Reentrancy: a draining closure that registers another closure must see
-- that closure run immediately (active is set before the drain).
local ns2 = {}
assert(loadfile("core/debug_gate.lua"))("QUI", ns2)
local order = {}
ns2.DebugRegister(function()
    order[#order + 1] = "outer"
    ns2.DebugRegister(function() order[#order + 1] = "inner" end)
end)
ns2.DebugActivate()
assert(table.concat(order, ",") == "outer,inner",
    "reentrant registration during drain must run immediately, got: " .. table.concat(order, ","))

-- 5. Eager-fallback contract used by every instrumented module:
--    when the gate is absent (standalone test harness), setup runs eagerly.
local bareNS = {}
local eagerRan = false
local function SetupDebugInstrumentation() eagerRan = true end
if bareNS.DebugRegister then
    bareNS.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation()
end
assert(eagerRan, "modules must fall back to eager setup without the gate")

print("debug_gate_test OK")
