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
-- MINIMAL hand-kept seed: argless visibility/geometry methods only.
-- Argument-carrying methods (SetCooldownFromDurationObject, SetAlpha,
-- SetText, ...) are now GENERATED from the api-index at scan time
-- (tests/taint/index_load.lua) — a bare Registry.new() no longer seeds
-- them (see the index_load population test below).
assert_true(r:isSafeSinkMethod("Show"), "Show is safe sink")
assert_true(r:isSafeSinkMethod("Hide"), "Hide is safe sink")
assert_true(r:isSafeSinkMethod("ClearAllPoints"), "ClearAllPoints is safe sink")
assert_false(r:isSafeSinkMethod("SetCooldownFromDurationObject"),
    "argument-carrying methods are index-generated, not hand-seeded")
assert_false(r:isSafeSinkMethod("RandomMethod"), "unknown method is not safe sink")

-- BUILTIN_SAFE_SINK_FUNCTIONS is now an empty hand-kept seed — the former
-- C_StringUtil.* entries are index-generated (AllowedWhenTainted /
-- secretArgumentsAnyTainted). Config extra_safe_sinks still feeds this
-- table (see the extension test below).
assert_false(r:isSafeSinkFunction("C_StringUtil.RoundToNearestString"),
    "C_StringUtil sinks are index-generated, not hand-seeded")
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

-- Aspect-returning method track + stripped view
local rA = Registry.new()
assert_false(rA:isAspectReturningMethod("GetAlpha"), "clean instance has no aspect methods")
rA:addAspectReturningMethod("GetAlpha", { "Alpha" })
assert_true(rA:isAspectReturningMethod("GetAlpha"), "aspect method registered")

local stripped = rA:aspectStripped()
assert_false(stripped:isAspectReturningMethod("GetAlpha"),
    "stripped view hides aspect methods")
rA:addSource("C_Spell.GetSpellCharges")
assert_true(stripped:isSource("C_Spell.GetSpellCharges"),
    "stripped view still sees every other registry facility")
assert_true(rA:aspectStripped() == stripped, "stripped view is cached")

print("registry aspect test passed")

-- index_load: population rules against a hand-built mini index (no file I/O)
do
    local IndexLoad = dofile("tests/taint/index_load.lua")
    local Config = dofile("tests/taint/config.lua")
    local cfg = Config.loadFromString(nil)
    local rIdx = Registry.new()

    local mini = {
        -- widget method, some system allows tainted → sink (method track)
        ["TestSinkText"] = { secretArguments = "AllowedWhenUntainted",
                            secretArgumentsAnyTainted = true, scriptObject = true },
        -- widget method, no system allows tainted → documented reject (method track)
        ["TestRejectShown"] = { secretArguments = "AllowedWhenUntainted", scriptObject = true },
        -- DurationObject arg → sink even though AllowedWhenUntainted
        ["TestDurationSink"] = { secretArguments = "AllowedWhenUntainted",
                                 durationObjectArg = true, scriptObject = true },
        -- namespaced function, tainted-allowed → function sink
        ["C_Test.TestFmt"] = { secretArguments = "AllowedWhenTainted" },
        -- namespaced function, forbidden → function reject
        ["C_Test.TestForbid"] = { secretArguments = "NotAllowed" },
        -- bare global (no scriptObject) → registers on BOTH tracks
        ["TestGlobalReject"] = { secretArguments = "AllowedWhenUntainted" },
        -- event entries never touch sink tracks
        ["event:TEST_EVENT"] = { secretPayload = true },
    }
    IndexLoad.populate(rIdx, mini, cfg, function() end)

    assert_true(rIdx:isSafeSinkMethod("TestSinkText"), "anyTainted widget method → sink")
    assert_false(rIdx:isSafeSinkMethod("TestRejectShown"), "untainted-only method is NOT a sink")
    assert_true(rIdx:docArgRestrictionMethod("TestRejectShown") == "AllowedWhenUntainted",
        "untainted-only method lands in the documented reject-set")
    assert_true(rIdx:isSafeSinkMethod("TestDurationSink"), "DurationObject arg → sink")
    assert_true(rIdx:isSafeSinkFunction("C_Test.TestFmt"), "namespaced tainted-allowed → function sink")
    assert_true(rIdx:docArgRestrictionFunction("C_Test.TestForbid") == "NotAllowed",
        "namespaced NotAllowed → function reject")
    assert_true(rIdx:docArgRestrictionMethod("TestGlobalReject") == "AllowedWhenUntainted"
        and rIdx:docArgRestrictionFunction("TestGlobalReject") == "AllowedWhenUntainted",
        "bare non-ScriptObject key registers on both tracks")
    assert_true(not rIdx:isSafeSinkMethod("event:TEST_EVENT") and not rIdx:isSource("event:TEST_EVENT"),
        "event keys never register as sinks")
end

print("index_load population test passed")

-- Pin: every remaining hand-kept builtin sink must be compatible with the
-- REAL index (index is the authority; builtins are test-ergonomic seeds only).
do
    local chunk = assert(loadfile("tests/api-docs/api-index.lua"))
    local idx = chunk()
    local rPin = Registry.new()
    for name in pairs(rPin.safeSinkMethods) do
        local e = idx[name]
        assert(e == nil or e.secretArgumentsAnyTainted or e.durationObjectArg
            or e.secretArguments == "AllowedWhenTainted",
            "builtin sink method contradicts the api-index: " .. name)
    end
    for name in pairs(rPin.safeSinkFunctions) do
        local e = idx[name]
        assert(e == nil or e.secretArgumentsAnyTainted or e.durationObjectArg
            or e.secretArguments == "AllowedWhenTainted",
            "builtin sink function contradicts the api-index: " .. name)
    end
end

print("builtin-vs-index pin test passed")

-- Element-secret container track (round-23)
do
    local r = Registry.new()
    assert(not r:isElementSecretFunction("C_UnitAuras.GetUnitAuras"),
        "element track empty by default")
    r:addElementSecretFunction("C_UnitAuras.GetUnitAuras")
    assert(r:isElementSecretFunction("C_UnitAuras.GetUnitAuras"),
        "element track registers")
    assert(not r:isSource("C_UnitAuras.GetUnitAuras"),
        "element registration must NOT make the name a whole-call source")
end
print("registry element-secret track test passed")

-- Helper-param seeding track (round-23): declared-name → container-param
-- positions. Positions index the DECLARED argument list (the parser omits a
-- colon method's implicit `self`, so position 1 of `function M:Copy(src)`
-- is `src` — analyzer E22 pins that end-to-end).
do
    local r = Registry.new()
    assert(r:elementContainerParams("CopyReadableAuras") == nil,
        "param track empty by default")
    r:addElementContainerParams("CopyReadableAuras", { 1 })
    local p = r:elementContainerParams("CopyReadableAuras")
    assert(type(p) == "table" and p[1] == 1 and #p == 1,
        "param track registers position array")
    assert(r:elementContainerParams("OtherCopy") == nil,
        "unregistered name stays nil")
    r:addElementContainerParams("M.Copy", { 2 })
    local q = r:elementContainerParams("M.Copy")
    assert(type(q) == "table" and q[1] == 2,
        "dotted spelling keys exactly as registered")
    assert(r:elementContainerParams("Copy") == nil,
        "dotted registration never answers for the bare tail")
    assert(not r:isElementSecretFunction("CopyReadableAuras"),
        "param track never leaks onto the element call-name track")
    assert(not r:isSource("CopyReadableAuras"),
        "param registration must NOT make the name a source")
    local r2 = Registry.new()
    assert(r2:elementContainerParams("CopyReadableAuras") == nil,
        "instances do not share param registrations")
end
print("registry element-container-params track test passed")

-- Round-23: conditionalSecretContents registers element track, stays non-source
do
    local IndexLoad = dofile("tests/taint/index_load.lua")
    local Config = dofile("tests/taint/config.lua")
    local r = Registry.new()
    local cfg = Config.loadFromString(nil)
    IndexLoad.populate(r, {
        ["C_UnitAuras.GetUnitAuras"] = {
            secretArguments = "AllowedWhenUntainted",
            conditionalSecretContents = true,
            preconditions = { "RequiresUnitAuraAccess" },
        },
    }, cfg, function() end)
    assert(r:isElementSecretFunction("C_UnitAuras.GetUnitAuras"),
        "index flag registers element track")
    assert(not r:isSource("C_UnitAuras.GetUnitAuras"),
        "index flag still non-source (no whole-call FP)")
    local rOff = Registry.new()
    local cfgOff = Config.loadFromString(
        "return { coverage = { conditionalSecretContents = false } }")
    IndexLoad.populate(rOff, {
        ["C_UnitAuras.GetUnitAuras"] = { conditionalSecretContents = true },
    }, cfgOff, function() end)
    assert(not rOff:isElementSecretFunction("C_UnitAuras.GetUnitAuras"),
        "coverage off disables element registration")
end
print("index_load element track test passed")
