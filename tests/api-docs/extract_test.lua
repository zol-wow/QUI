-- Tests for extract_api_index.lua
-- Run from the repo root: lua tests/api-docs/extract_test.lua

local Extract = dofile("tests/api-docs/extract_api_index.lua")

local function assert_eq(a, e, msg)
    if a ~= e then
        error((msg or "") .. ": expected " .. tostring(e) .. ", got " .. tostring(a), 2)
    end
end

local function assert_true(v, msg)
    if not v then error(msg or "assertion failed", 2) end
end

-- ---------------------------------------------------------------------------
-- Index extraction
-- ---------------------------------------------------------------------------

local index = Extract.fromCorpus("tests/api-docs/synthetic-corpus")

-- SecretWhenCooldownsRestricted function must be indexed with the flag set
assert_true(index["C_Test.GetSecretValue"], "secret-flagged function indexed")
assert_eq(index["C_Test.GetSecretValue"].secretWhenCooldownsRestricted, true,
    "secretWhenCooldownsRestricted flag captured")

-- Clean function (no flags) must NOT appear in the index
assert_true(not index["C_Test.GetCleanValue"], "clean function NOT indexed (no flag)")

-- Function with SecretArguments + IsSecret return
assert_true(index["C_Test.RestrictedReturn"], "restricted function indexed")
assert_eq(index["C_Test.RestrictedReturn"].isSecretReturn, true,
    "isSecretReturn captured")
assert_eq(index["C_Test.RestrictedReturn"].secretArguments, "Restricted",
    "secretArguments captured")

-- Precondition-guarded function (RequiresUnitAuraAccess hard-errors under
-- restrictions) must be indexed regardless of its SecretArguments value.
-- SecretArguments is now captured UNCONDITIONALLY (Task 1: the extractor
-- used to drop "AllowedWhenTainted" outright, which is exactly the spelling
-- a cross-system collision needs to detect), so "AllowedWhenTainted" is
-- captured verbatim and mirrored into secretArgumentsAnyTainted.
assert_true(index["C_Test.GuardedGetter"], "precondition-guarded function indexed")
assert_eq(index["C_Test.GuardedGetter"].preconditions[1], "RequiresUnitAuraAccess",
    "RequiresUnitAuraAccess precondition captured")
assert_eq(index["C_Test.GuardedGetter"].secretArguments, "AllowedWhenTainted",
    "AllowedWhenTainted now captured verbatim, not omitted")
assert_true(index["C_Test.GuardedGetter"].secretArgumentsAnyTainted == true,
    "AllowedWhenTainted mirrors into secretArgumentsAnyTainted")

-- Events: event-level Secret* flag and secretizable payload fields
assert_true(index["event:TEST_SECRET_EVENT"], "secret-flagged event indexed")
assert_eq(index["event:TEST_SECRET_EVENT"].eventFlags[1], "SecretInActivePvPMatch",
    "event-level flag captured")
assert_true(index["event:TEST_SECRET_PAYLOAD_EVENT"], "secret-payload event indexed")
assert_eq(index["event:TEST_SECRET_PAYLOAD_EVENT"].secretPayload, true,
    "secretPayload captured")
assert_true(not index["event:TEST_CLEAN_EVENT"], "clean event NOT indexed")

-- Doc files that reference Enum.* / Constants.* inside table constructors
-- (12.1.0.68675+ aspect flags, e.g. SecretReturnsForAspect =
-- { Enum.SecretAspect.Alpha }) must still load: a plain Lua host has neither
-- global, and an indexing error would silently drop the whole file's tables.
assert_true(index["C_TestEnumRefs.GetAspectValue"], "Enum-referencing file still indexed")
assert_eq(index["C_TestEnumRefs.GetAspectValue"].secretWhenCooldownsRestricted, true,
    "flags captured from Enum-referencing file")
assert_eq(index["C_TestEnumRefs.SetAspectValue"].secretArguments, "AllowedWhenUntainted",
    "secretArguments captured alongside SecretArgumentsAddAspect")
assert_eq(index["C_TestEnumRefs.GetConstantsValue"].secretArguments, "NotAllowed",
    "Constants.* reference does not abort file")

-- Aspect flags themselves are captured as bare aspect-name lists
assert_eq(index["C_TestEnumRefs.GetAspectValue"].secretReturnsForAspect[1], "Alpha",
    "SecretReturnsForAspect captured as aspect name")
assert_eq(index["C_TestEnumRefs.SetAspectValue"].secretArgumentsAddAspect[1], "Alpha",
    "SecretArgumentsAddAspect captured as aspect name")

-- ---------------------------------------------------------------------------
-- Namespace-less systems + generic SecretWhen* + top-level SecretReturns
-- ---------------------------------------------------------------------------

-- A system WITHOUT a Namespace exports bare globals: keys must be bare.
assert_true(index["GetGlobalStatValue"], "namespace-less system indexed by bare name")
assert_true(not index["TestGlobal.GetGlobalStatValue"],
    "no system-name-prefixed key for namespace-less system")

-- ALL SecretWhen* flags captured generically (sorted name list), not just
-- SecretWhenCooldownsRestricted.
assert_eq(index["GetGlobalStatValue"].secretWhenRestricted[1],
    "SecretWhenUnitStatsRestricted", "generic SecretWhen* flag captured")

-- Top-level `SecretReturns = true` folds into isSecretReturn.
assert_eq(index["GetGlobalSecretReturner"].isSecretReturn, true,
    "top-level SecretReturns captured as isSecretReturn")

-- Clean function in a namespace-less system still excluded.
assert_true(not index["GetGlobalCleanValue"], "clean bare-global NOT indexed")

-- ---------------------------------------------------------------------------
-- renderLua round-trip
-- ---------------------------------------------------------------------------

local rendered = Extract.renderLua(index)

-- Must be valid Lua
local f = (loadstring or load)(rendered, "rendered")
assert_true(f ~= nil, "rendered output must be loadable Lua")

local ok, decoded = pcall(f)
assert_true(ok and type(decoded) == "table", "rendered loads to a table")

-- Re-render must be identical (idempotency / determinism)
local rendered2 = Extract.renderLua(decoded)
assert_eq(rendered, rendered2, "render is idempotent")

-- ---------------------------------------------------------------------------
-- Cross-system merge: two ScriptObject widgets colliding on one method name
-- ---------------------------------------------------------------------------

do
    local e = index["TestMergeSetThing"]
    assert(e, "merged widget method entry present")
    assert(e.secretArguments == "AllowedWhenUntainted",
        "collision keeps the MOST restrictive secretArguments spelling")
    assert(e.secretArgumentsAnyTainted == true,
        "collision records that SOME system allows tainted callers")
    assert(e.scriptObject == true, "ScriptObject origin recorded")

    local d = index["TestMergeSetTimer"]
    assert(d, "DurationObject-arg entry present")
    assert(d.durationObjectArg == true, "LuaDurationObject argument captured")
    assert(d.secretArguments == "AllowedWhenUntainted",
        "AllowedWhenUntainted still captured verbatim")

    -- An unrecognized future secretArguments spelling merging into a key
    -- whose previous entry has NO secretArguments must survive, not vanish
    -- (SECRET_ARG_RANK's fallback must rank unknown spellings MOST
    -- restrictive, never equal to "no flag at all").
    local u = index["TestMergeUnknownMode"]
    assert(u, "unknown-spelling merge entry present")
    assert(u.secretArguments == "SomeFutureMode",
        "unrecognized secretArguments spelling survives the merge, not dropped")

    -- Round-22b regression: conditionalSecretContents survives a collision
    -- where only the SECOND system's entry carries the flag (fixture order
    -- pins the unflagged-first direction that dropped it before the key
    -- joined MERGE_BOOL_KEYS).
    local c = index["TestMergeCondContents"]
    assert(c, "ConditionalSecretContents collision entry present")
    assert(c.conditionalSecretContents == true,
        "conditionalSecretContents survives cross-system merge when only one entry has it")
end

print("extract test passed")
