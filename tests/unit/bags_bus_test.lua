-- tests/unit/bags_bus_test.lua
-- Headless verification of the bags callback bus. Run: lua tests/unit/bags_bus_test.lua
local loader = dofile("tests/helpers/load_bags_data.lua")
local ns = loader.LoadAll(nil, "bus.lua")
local Bus = ns.Bags.Bus

-- Test 1: basic dispatch with args
local got = {}
Bus.Subscribe("E1", function(name, a, b) got[#got + 1] = { name, a, b } end)
Bus.Publish("E1", 1, 2)
assert(#got == 1 and got[1][1] == "E1" and got[1][2] == 1 and got[1][3] == 2, "basic dispatch failed")

-- Test 2: handler error isolation (second handler still runs, publish doesn't throw)
local ran = false
Bus.Subscribe("E2", function() error("boom") end)
Bus.Subscribe("E2", function() ran = true end)
local ok = pcall(Bus.Publish, "E2")
assert(ok, "publish should not propagate handler errors")
assert(ran, "second subscriber didn't run after first errored")

-- Test 3: snapshot semantics — handler subscribed during publish fires next publish only
local fires = 0
Bus.Subscribe("E3", function() Bus.Subscribe("E3", function() fires = fires + 1 end) end)
Bus.Publish("E3")
assert(fires == 0, "late-subscribed handler fired during its own publish")
Bus.Publish("E3")
assert(fires == 1, "late-subscribed handler should fire exactly once on the next publish")

-- Test 4: unsubscribe
local fired = false
local h = function() fired = true end
Bus.Subscribe("E4", h)
Bus.Unsubscribe("E4", h)
Bus.Publish("E4")
assert(not fired, "unsubscribed handler still fired")

print("OK: bags_bus_test")
