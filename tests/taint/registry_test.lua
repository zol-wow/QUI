-- tests/taint/registry_test.lua
local Registry = dofile("tests/taint/registry.lua")

local function assert_true(v, msg) if not v then error(msg or "expected true", 2) end end
local function assert_false(v, msg) if v then error(msg or "expected false", 2) end end

local r = Registry.new()

-- Sources (none built-in — all come from api-index later. Confirm empty by default.)
assert_false(r:isSource("C_Spell.GetSpellCharges"), "no built-in sources")

-- Add a source manually (api-index integration in later task)
r:addSource("C_Spell.GetSpellCharges")
assert_true(r:isSource("C_Spell.GetSpellCharges"), "added source detected")

-- Safe sinks: method names (any obj:Method) + qualified names (Module.fn)
assert_true(r:isSafeSinkMethod("SetCooldownFromDurationObject"), "method is safe sink")
assert_true(r:isSafeSinkMethod("SetAlpha"), "SetAlpha is safe sink")
assert_true(r:isSafeSinkMethod("SetText"), "SetText is safe sink")
assert_true(r:isSafeSinkMethod("Show"), "Show is safe sink")
assert_true(r:isSafeSinkMethod("Hide"), "Hide is safe sink")
assert_false(r:isSafeSinkMethod("RandomMethod"), "unknown method is not safe sink")

assert_true(r:isSafeSinkFunction("C_StringUtil.RoundToNearestString"),
    "C_StringUtil.RoundToNearestString is safe sink")
assert_true(r:isSafeSinkFunction("C_StringUtil.FloorToNearestString"),
    "C_StringUtil.FloorToNearestString is safe sink")
assert_false(r:isSafeSinkFunction("tonumber"), "tonumber is NOT a safe sink")

-- Guards
assert_true(r:isGuard("IsSecretValue"), "IsSecretValue is guard")
assert_true(r:isGuard("Helpers.IsSecretValue"), "qualified IsSecretValue is guard")
assert_true(r:isGuard("HasSecretValue"), "HasSecretValue is guard")
assert_true(r:isGuard("Helpers.HasSecretValue"), "qualified HasSecretValue is guard")
assert_false(r:isGuard("foo"), "random is not guard")

-- Unwraps
assert_true(r:isUnwrap("Helpers.SafeValue"), "SafeValue unwrap")
assert_true(r:isUnwrap("Helpers.SafeToNumber"), "SafeToNumber unwrap")
assert_true(r:isUnwrap("Helpers.SafeToString"), "SafeToString unwrap")
assert_true(r:isUnwrap("Helpers.SafeCompare"), "SafeCompare unwrap")
assert_false(r:isUnwrap("SomeOther"), "random not unwrap")

-- Extension via config (extra_safe_sinks / extra_unwraps)
r:addSafeSinkFunction("MyHelpers.DoThing")
assert_true(r:isSafeSinkFunction("MyHelpers.DoThing"), "extension registered")
r:addUnwrap("MyHelpers.SafeAccess")
assert_true(r:isUnwrap("MyHelpers.SafeAccess"), "extension unwrap")

-- Secret-returning functions: produce a secret-tagged return value when given
-- a secret-tagged argument. The C_StringUtil formatters are safe sinks (you
-- may pass secret args) AND secret-returning (the result is itself tainted).
-- LHS assignment from one of these calls must mark the LHS as tainted so
-- downstream comparisons get caught — this is the analyzer gap that allowed
-- the damage_meter.lua:906 taint crash to slip past static analysis.
assert_true(r:isSecretReturning("C_StringUtil.TruncateWhenZero"),
    "TruncateWhenZero is secret-returning")
assert_true(r:isSecretReturning("C_StringUtil.RoundToNearestString"),
    "RoundToNearestString is secret-returning")
assert_true(r:isSecretReturning("C_StringUtil.FloorToNearestString"),
    "FloorToNearestString is secret-returning")
assert_true(r:isSecretReturning("C_StringUtil.WrapString"),
    "WrapString is secret-returning")
assert_false(r:isSecretReturning("tonumber"), "tonumber is not secret-returning")
assert_false(r:isSecretReturning("Helpers.IsSecretValue"),
    "guards are not secret-returning")

r:addSecretReturning("MyHelpers.WrapSecret")
assert_true(r:isSecretReturning("MyHelpers.WrapSecret"), "extension registered")

-- Verify two instances don't share mutation
local r2 = Registry.new()
assert_false(r2:isSource("C_Spell.GetSpellCharges"), "second instance has clean sources")
assert_false(r2:isSafeSinkFunction("MyHelpers.DoThing"), "second instance has clean sinks")
assert_false(r2:isUnwrap("MyHelpers.SafeAccess"), "second instance has clean unwraps")
assert_false(r2:isSecretReturning("MyHelpers.WrapSecret"),
    "second instance has clean secretReturning")

print("registry test passed")
