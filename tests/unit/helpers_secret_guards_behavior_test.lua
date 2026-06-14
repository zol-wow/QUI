-- tests/unit/helpers_secret_guards_behavior_test.lua
-- Run: lua tests/unit/helpers_secret_guards_behavior_test.lua
-- Behavioral coverage for core/utils.lua secret guards using env.MakeSecret().

local env = dofile("tools/_addon_env.lua")
env.LoadLibs()
local ns = env.LoadCore()
local Helpers = assert(ns.Helpers, "ns.Helpers must exist after LoadCore")
local s = env.MakeSecret()

-- IsSecretValue (core/utils.lua:39-41)
assert(Helpers.IsSecretValue(s) == true,  "IsSecretValue(sentinel) [utils.lua:39]")
assert(Helpers.IsSecretValue(7) == false, "IsSecretValue(number) [utils.lua:39]")
assert(Helpers.IsSecretValue(nil) == false, "IsSecretValue(nil) [utils.lua:39]")

-- HasSecretValue (core/utils.lua:45-53)
assert(Helpers.HasSecretValue(1, "a", s) == true,  "HasSecretValue with secret in vararg [utils.lua:45]")
assert(Helpers.HasSecretValue(1, 2, "x") == false, "HasSecretValue all non-secret [utils.lua:45]")
assert(Helpers.HasSecretValue(s) == true,  "HasSecretValue single secret [utils.lua:45]")

-- CanAccessTable (core/utils.lua:58-60)
-- logic: not canaccesstable or canaccesstable(tbl); sentinel returns false from canaccesstable
assert(Helpers.CanAccessTable(s) == false, "CanAccessTable(sentinel) [utils.lua:58]")
assert(Helpers.CanAccessTable({}) == true, "CanAccessTable(plain table) [utils.lua:58]")

-- SafeValue (core/utils.lua:66-71)
-- secret path: returns fallback; non-secret path: returns value
assert(Helpers.SafeValue(s, "fallback") == "fallback", "SafeValue(secret, fallback) [utils.lua:66]")
assert(Helpers.SafeValue(s, nil) == nil,               "SafeValue(secret, nil) [utils.lua:66]")
assert(Helpers.SafeValue(5, "fallback") == 5,          "SafeValue(non-secret) returns value [utils.lua:66]")
assert(Helpers.SafeValue("hi", "fb") == "hi",          "SafeValue(string) returns value [utils.lua:66]")

-- SafeCompare (core/utils.lua:108-113)
-- secret path: returns nil; non-secret path: returns a == b
assert(Helpers.SafeCompare(s, 5) == nil,   "SafeCompare(secret, 5) returns nil [utils.lua:108]")
assert(Helpers.SafeCompare(5, s) == nil,   "SafeCompare(5, secret) returns nil [utils.lua:108]")
assert(Helpers.SafeCompare(3, 5) == false, "SafeCompare(3, 5) returns false [utils.lua:108]")
assert(Helpers.SafeCompare(3, 3) == true,  "SafeCompare(3, 3) returns true [utils.lua:108]")

-- SafeToNumber (core/utils.lua:119-129)
-- secret path: returns fallback or 0; non-secret: tonumber
assert(Helpers.SafeToNumber(s, 99) == 99, "SafeToNumber(secret, 99) [utils.lua:119]")
assert(Helpers.SafeToNumber(s, nil) == 0, "SafeToNumber(secret, nil) returns 0 [utils.lua:119]")
assert(Helpers.SafeToNumber("42", 0) == 42, "SafeToNumber('42') [utils.lua:119]")
assert(Helpers.SafeToNumber(7, 0) == 7,     "SafeToNumber(number) [utils.lua:119]")

-- SafeToString (core/utils.lua:135-146)
-- secret path: returns fallback (or "" if fallback nil); non-secret: tostring
assert(Helpers.SafeToString(s, "fb") == "fb", "SafeToString(secret, 'fb') [utils.lua:135]")
assert(Helpers.SafeToString(s, nil) == "",    "SafeToString(secret, nil) returns '' [utils.lua:135]")
assert(Helpers.SafeToString(42, "") == "42",  "SafeToString(number) [utils.lua:135]")
assert(Helpers.SafeToString(true, "") == "true", "SafeToString(bool) [utils.lua:135]")

print("OK: helpers_secret_guards_behavior_test")
