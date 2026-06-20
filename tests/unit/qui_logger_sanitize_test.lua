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

-- pathological payloads are bounded before they reach SavedVariables
ns.loggerLimits = { maxStringLength = 5, maxTableEntries = 2, maxArgs = 2 }
local long = ns.SanitizeArg("abcdefghij")
assert(long:sub(1, 5) == "abcde" and long:find("truncated", 1, true),
    "long strings should be truncated")

local hugeTable = ns.SanitizeArg({ a = 1, b = 2, c = 3 })
local entries = 0
for _ in pairs(hugeTable) do entries = entries + 1 end
assert(entries <= 3 and hugeTable.__truncated == true,
    "large tables should be truncated with a marker")

local nested = ns.SanitizeArg({ child = { value = 1 } }, { maxTableEntries = 10 })
assert(nested.child == "<table>", "nested tables should be summarized")

local cappedArgs, cappedN = ns.SanitizeArgs(1, 2, 3, 4)
assert(cappedN == 4, "argument arity should remain original")
assert(cappedArgs[1] == 1 and cappedArgs[2] == 2,
    "first capped args should be retained")
assert(cappedArgs[3] == "<args-truncated:4>",
    "extra args should be represented by one bounded marker")
ns.loggerLimits = nil

print("qui_logger_sanitize_test: OK")
