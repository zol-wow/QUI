-- tests/taint/cli_test.lua
-- End-to-end tests for the tools/test_taint.lua CLI runner.
-- Run from the repo root: lua tests/taint/cli_test.lua

-- ---------------------------------------------------------------------------
-- Portable command runner
-- Captures stdout+stderr and exit code.
-- On Lua 5.2+ os.execute returns (ok, "exit", code); on Lua 5.1 it returns an int.
-- io.popen captures output; os.execute in a second call captures exit code.
-- ---------------------------------------------------------------------------

local isWindows = package.config:sub(1, 1) == "\\"

local function runCmd(cmd)
    -- Capture output
    local p = io.popen(cmd .. (isWindows and " 2>&1" or " 2>&1"), "r")
    local out = p:read("*a")
    p:close()

    -- Capture exit code via a separate os.execute call (redirect output to null)
    local nullDev = isWindows and "NUL" or "/dev/null"
    local exitCode
    local raw = os.execute(cmd .. " >" .. nullDev .. " 2>&1")
    if type(raw) == "number" then
        -- Lua 5.1: os.execute returns the raw exit status integer
        -- On Windows the raw value is the exit code directly.
        -- On Unix it is the wait(2) status — shift right 8 bits.
        if isWindows then
            exitCode = raw
        else
            exitCode = math.floor(raw / 256)
        end
    else
        -- Lua 5.2+: os.execute returns (ok, "exit", code)
        -- The third return value is the numeric exit code.
        local _, _, code = os.execute(cmd .. " >" .. nullDev .. " 2>&1")
        exitCode = code or (raw and 0 or 1)
    end

    return out, exitCode
end

-- ---------------------------------------------------------------------------
-- Test 1: advisory-only fixture (modules/foo) → exit 0, [advisory] shown
-- ---------------------------------------------------------------------------

local cmd1 = 'lua tools/test_taint.lua --no-color --only "modules/foo" tests/taint/cli-fixture'
local out1, exit1 = runCmd(cmd1)

assert(out1:find("dirty.lua"),
    "Test 1: expected dirty.lua in output.\nGot: " .. out1)
assert(out1:find("%[advisory%]"),
    "Test 1: expected [advisory] tier in output.\nGot: " .. out1)
assert(not out1:find("%[strict%]"),
    "Test 1: should not contain [strict].\nGot: " .. out1)
assert(exit1 == 0,
    "Test 1: advisory-only run should exit 0, got: " .. tostring(exit1))

-- ---------------------------------------------------------------------------
-- Test 2: strict fixture (modules/cdm) → exit 1, [strict] shown
-- ---------------------------------------------------------------------------

local cmd2 = 'lua tools/test_taint.lua --no-color --only "modules/cdm" tests/taint/cli-fixture'
local out2, exit2 = runCmd(cmd2)

assert(out2:find("strict.lua"),
    "Test 2: expected strict.lua in output.\nGot: " .. out2)
assert(out2:find("%[strict%]"),
    "Test 2: expected [strict] tier in output.\nGot: " .. out2)
assert(exit2 == 1,
    "Test 2: strict findings should exit 1, got: " .. tostring(exit2))

-- ---------------------------------------------------------------------------
-- Test 2b: CDM unwrap review is promoted to strict by strict_unwrap_paths
-- ---------------------------------------------------------------------------

local cmd2b = 'lua tools/test_taint.lua --no-color --strict-only --only "unwrap.lua" tests/taint/cli-fixture'
local out2b, exit2b = runCmd(cmd2b)

assert(out2b:find("unwrap.lua"),
    "Test 2b: expected unwrap.lua in output.\nGot: " .. out2b)
assert(out2b:find("%[strict%]") and out2b:find("<unwrap>", 1, true),
    "Test 2b: expected strict unwrap finding.\nGot: " .. out2b)
assert(exit2b == 1,
    "Test 2b: strict unwrap should exit 1, got: " .. tostring(exit2b))

-- ---------------------------------------------------------------------------
-- Test 3: --strict-only suppresses advisory findings
-- ---------------------------------------------------------------------------

local cmd3 = 'lua tools/test_taint.lua --no-color --strict-only --only "modules/foo" tests/taint/cli-fixture'
local out3, exit3 = runCmd(cmd3)

assert(not out3:find("%[advisory%]"),
    "Test 3: --strict-only should hide advisory findings.\nGot: " .. out3)
assert(exit3 == 0,
    "Test 3: --strict-only with no strict findings should exit 0, got: " .. tostring(exit3))

-- ---------------------------------------------------------------------------
-- Test 4: clean file produces no finding lines
-- ---------------------------------------------------------------------------

local cmd4 = 'lua tools/test_taint.lua --no-color --only "clean.lua" tests/taint/cli-fixture'
local out4, exit4 = runCmd(cmd4)

assert(not out4:find("%[strict%]") and not out4:find("%[advisory%]"),
    "Test 4: clean.lua should produce no findings.\nGot: " .. out4)
assert(exit4 == 0,
    "Test 4: clean run should exit 0, got: " .. tostring(exit4))

-- ---------------------------------------------------------------------------
-- Test 5: --update-index regenerates api-index.lua, exits 0
-- ---------------------------------------------------------------------------

local cmdUI = 'lua tools/test_taint.lua --update-index .'
local outUI, exitUI = runCmd(cmdUI)

assert(exitUI == 0,
    "Test 5: --update-index should exit 0, got: " .. tostring(exitUI) .. "\nOutput: " .. outUI)
assert(outUI:find("api%-index%.lua regenerated"),
    "Test 5: expected success message.\nGot: " .. outUI)

-- Verify the regenerated file contains expected entries
local fIdx = io.open("tests/api-docs/api-index.lua", "rb")
assert(fIdx, "Test 5: api-index.lua should exist after --update-index")
local idxContent = fIdx:read("*a")
fIdx:close()
assert(idxContent:find("C_Spell.GetSpellCharges", 1, true),
    "Test 5: C_Spell.GetSpellCharges should be in regenerated index.\nGot: " .. idxContent)

print("update-index test passed")

-- ---------------------------------------------------------------------------
-- Test 6: --report json actually prints JSON (regression for the discard bug)
-- ---------------------------------------------------------------------------

local cmd6 = 'lua tools/test_taint.lua --report json --only "modules/foo" tests/taint/cli-fixture'
local out6, exit6 = runCmd(cmd6)

assert(exit6 == 0,
    "Test 6: json mode should exit 0, got: " .. tostring(exit6) .. "\nOutput: " .. out6)
assert(out6:find("%[", 1) and out6:find("%]"),
    "Test 6: json output must be bracketed.\nGot: " .. tostring(out6))
assert(out6:find('"file"', 1, true),
    "Test 6: json output must contain 'file' key.\nGot: " .. tostring(out6))

print("renderer output regression test passed (json)")

-- ---------------------------------------------------------------------------
-- Test 7: --report github actually prints annotations
-- ---------------------------------------------------------------------------

local cmd7 = 'lua tools/test_taint.lua --report github --only "modules/foo" tests/taint/cli-fixture'
local out7, exit7 = runCmd(cmd7)

assert(out7:find("::warning", 1, true),
    "Test 7: github mode must print ::warning annotation.\nGot: " .. tostring(out7))

print("renderer output regression test passed (github)")

-- ---------------------------------------------------------------------------
-- Test 8: --json-out archives every severity while stdout stays gated
--
-- This is the whole point of the flag: CI runs one analysis pass that fails on
-- strict findings AND uploads the full advisory report. If --json-out ever
-- starts honouring --strict-only, the artifact silently loses its advisory and
-- review rows while still looking like a valid report.
-- ---------------------------------------------------------------------------

local jsonOutPath = "tests/taint/cli_test_jsonout.tmp.json"
os.remove(jsonOutPath)

local cmd8 = 'lua tools/test_taint.lua --report github --strict-only'
    .. ' --json-out ' .. jsonOutPath .. ' tests/taint/cli-fixture'
local out8, exit8 = runCmd(cmd8)

assert(exit8 == 1,
    "Test 8: fixture has strict findings, so exit should be 1, got: " .. tostring(exit8)
    .. "\nOutput: " .. out8)

local fJson = io.open(jsonOutPath, "rb")
assert(fJson, "Test 8: --json-out should have written " .. jsonOutPath)
local jsonContent = fJson:read("*a")
fJson:close()
os.remove(jsonOutPath)

assert(jsonContent:find('"severity": "strict"', 1, true),
    "Test 8: json-out must keep strict findings.\nGot: " .. jsonContent)
assert(jsonContent:find('"severity": "advisory"', 1, true),
    "Test 8: json-out must keep advisory findings despite --strict-only.\nGot: " .. jsonContent)
assert(not out8:find("modules/foo/dirty.lua", 1, true),
    "Test 8: stdout is --strict-only, so the advisory file must not appear.\nGot: " .. out8)

print("json-out archives unfiltered findings test passed")

-- ---------------------------------------------------------------------------
-- Test 9: --shard is a partition, not a sample
--
-- The shard split is cost-balanced bin-packing rather than a simple modulo, so
-- a bug there drops files silently: every shard exits 0 and CI stays green
-- while part of the corpus is never analyzed. Assert the union of all shards
-- reproduces the unsharded finding set exactly.
-- ---------------------------------------------------------------------------

local function findingKeys(text)
    local keys = {}
    for file, line in text:gmatch('"file": "(.-)", "line": (%d+)') do
        keys[file .. ":" .. line] = (keys[file .. ":" .. line] or 0) + 1
    end
    return keys
end

local outFull = runCmd('lua tools/test_taint.lua --report json tests/taint/cli-fixture')
local expected = findingKeys(outFull)

local expectedCount = 0
for _ in pairs(expected) do expectedCount = expectedCount + 1 end
assert(expectedCount > 0, "Test 9: fixture should produce findings to partition")

local SHARDS = 3
local union = {}
for shard = 1, SHARDS do
    local outShard = runCmd(string.format(
        'lua tools/test_taint.lua --report json --shard %d/%d tests/taint/cli-fixture',
        shard, SHARDS))
    for key, count in pairs(findingKeys(outShard)) do
        union[key] = (union[key] or 0) + count
    end
end

for key, count in pairs(expected) do
    assert(union[key] == count, string.format(
        "Test 9: %s appears %s time(s) across shards, expected %d -- shards must partition",
        key, tostring(union[key]), count))
end
for key in pairs(union) do
    assert(expected[key], "Test 9: shards produced a finding the unsharded run did not: " .. key)
end

print("shard partition test passed")

-- ---------------------------------------------------------------------------

print("cli_test.lua: all tests passed")
