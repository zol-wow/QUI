-- tests/unit/qui_logger_sanitize_test.lua
-- Run: lua tests/unit/qui_logger_sanitize_test.lua
local ns = {}
assert(loadfile("QUI_Logger/recorder.lua"))("QUI_Logger", ns)

-- scalars pass raw
assert(ns.SanitizeArg(5) == 5)
assert(ns.SanitizeArg("x") == "x")
assert(ns.SanitizeArg(true) == true)

-- table shallow-copied (new table, same contents)
local t = { a = 1 }
local st = ns.SanitizeArg(t)
assert(st ~= t and st.a == 1, "table must be shallow-copied")

-- function/userdata-like -> placeholder string
assert(type(ns.SanitizeArg(print)) == "string", "function -> placeholder")

-- SanitizeArgs must swallow a throwing SanitizeArg and substitute a placeholder
local realSanitize = ns.SanitizeArg
ns.SanitizeArg = function() error("boom") end
local guarded, gn = ns.SanitizeArgs("x", "y")
ns.SanitizeArg = realSanitize
assert(gn == 2, "guarded arity must be 2")
assert(guarded[1] == "<unstorable>" and guarded[2] == "<unstorable>",
    "SanitizeArgs must substitute placeholder when SanitizeArg throws")

-- arity preserved incl trailing nils
local args, n = ns.SanitizeArgs("a", nil, 3, nil)
assert(n == 4, "must preserve arity 4, got " .. tostring(n))
assert(args[1] == "a" and args[3] == 3)

print("qui_logger_sanitize_test: OK")
