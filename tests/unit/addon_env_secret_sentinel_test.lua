-- tests/unit/addon_env_secret_sentinel_test.lua
-- Run: lua tests/unit/addon_env_secret_sentinel_test.lua
-- Verifies M.MakeSecret() sentinels approximate WoW 12.0 secret semantics.

local env = dofile("tools/_addon_env.lua")
local s = env.MakeSecret()

-- predicates
assert(issecretvalue(s) == true,  "sentinel must be secret")
assert(issecretvalue(42) == false, "plain number must not be secret")
assert(canaccesstable(s) == false, "sentinel table must not be accessible")
assert(canaccesstable({}) == true, "plain table must be accessible")

-- forbidden ops throw
assert(not pcall(function() return s + 1 end),  "arithmetic must throw")
assert(not pcall(function() return s > 5 end),  "comparison must throw")
assert(not pcall(function() return s.field end), "indexing must throw")
assert(not pcall(function() s.field = 1 end),   "writing must throw")

-- allowed ops work
assert(pcall(function() return "x" .. s end), "concat must be allowed")
assert(tostring(s) == "<secret>", "tostring must be allowed")
local box = {}
box.v = s                       -- storing is allowed
assert(box.v == s, "stored sentinel must be retrievable")

-- distinct sentinels
assert(env.MakeSecret() ~= s, "each sentinel is distinct")

print("OK: addon_env_secret_sentinel_test")
