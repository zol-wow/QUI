-- tests/cdm_bus_test.lua
-- Headless verification of resolver bus semantics. Run: lua tests/cdm_bus_test.lua
-- Mirrors bus primitives from modules/cdm/cdm_resolvers.lua —
-- keep in sync if production changes. See spec:
-- docs/superpowers/specs/2026-05-05-cdm-blizzard-child-decoupling-design.md §3.

_G.geterrorhandler = function() return function(err) error(err, 0) end end

local unpack = table.unpack or unpack

local ns = { CDMResolvers = {} }
local _subscribers = {}

local function publish(eventName, ...)
    local list = _subscribers[eventName]
    if not list then return end
    local n = #list
    if n == 0 then return end
    local snapshot = {}
    for i = 1, n do snapshot[i] = list[i] end
    -- Divergence from production bus: standalone Lua 5.1's xpcall does not
    -- forward trailing args to the protected function. WoW patches xpcall to
    -- accept them, so the production bus in cdm_resolvers.lua passes args
    -- directly. Wrap in a closure here to preserve the same semantics under
    -- stock Lua 5.1.5.
    local args = { ... }
    local nargs = select("#", ...)
    for i = 1, n do
        local fn = snapshot[i]
        xpcall(function() fn(eventName, unpack(args, 1, nargs)) end, _G.geterrorhandler())
    end
end
function ns.CDMResolvers.Subscribe(name, h)
    _subscribers[name] = _subscribers[name] or {}
    table.insert(_subscribers[name], h)
end
function ns.CDMResolvers.Unsubscribe(name, h)
    local l = _subscribers[name]
    if not l then return end
    for i = #l, 1, -1 do if l[i] == h then table.remove(l, i); return end end
end

-- Test 1: basic dispatch
local got = {}
ns.CDMResolvers.Subscribe("E1", function(name, a, b) table.insert(got, {name, a, b}) end)
publish("E1", 1, 2)
assert(#got == 1 and got[1][1] == "E1" and got[1][2] == 1 and got[1][3] == 2,
       "basic dispatch failed")

-- Test 2: subscriber error isolation
local ran = false
ns.CDMResolvers.Subscribe("E2", function() error("boom") end)
ns.CDMResolvers.Subscribe("E2", function() ran = true end)
local ok = pcall(publish, "E2")
assert(ok, "publish should not propagate handler errors")
assert(ran, "second subscriber didn't run after first errored")

-- Test 3: snapshot semantics — subscribe during publish doesn't fire that event
local fires = 0
local late = function() fires = fires + 1 end
ns.CDMResolvers.Subscribe("E3", function()
    ns.CDMResolvers.Subscribe("E3", late)
end)
publish("E3")
assert(fires == 0, "late-subscribed handler fired during its own publish")
publish("E3")
assert(fires == 1, "late handler should fire on next publish")

-- Test 4: unsubscribe
local fired = false
local h = function() fired = true end
ns.CDMResolvers.Subscribe("E4", h)
ns.CDMResolvers.Unsubscribe("E4", h)
publish("E4")
assert(not fired, "unsubscribed handler still fired")

print("OK: cdm_bus_test")
