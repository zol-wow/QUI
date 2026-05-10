-- tests/taint/findings_test.lua
local Findings = dofile("tests/taint/findings.lua")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. ":\n  expected: " .. tostring(expected) ..
              "\n  actual:   " .. tostring(actual), 2)
    end
end

-- Test 1: construct a finding
local f = Findings.new {
    file = "modules/cdm/cdm_icons.lua",
    line = 412,
    col = 18,
    severity = "advisory",
    source_function = "C_Spell.GetSpellCharges",
    sink = "tonumber",
    message = "tainted value used in arithmetic without guard or unwrap",
}
assert_eq(f.file, "modules/cdm/cdm_icons.lua", "file")
assert_eq(f.line, 412, "line")
assert_eq(f.severity, "advisory", "severity")
assert_eq(f.suppressed, false, "default suppressed=false")

-- Test 2: render text
local text = Findings.renderText({f})
local expected = [[
modules/cdm/cdm_icons.lua:412:18 [advisory] tonumber: tainted value used in arithmetic without guard or unwrap (source: C_Spell.GetSpellCharges)
]]
assert_eq(text, expected, "single finding text render")

-- Test 3: render text for multiple findings, sorted by file:line:col
local f2 = Findings.new {
    file = "modules/foo.lua", line = 10, col = 1,
    severity = "review", source_function = "Helpers.SafeValue",
    sink = "<unwrap>",
    message = "review unwrap call site",
}
local text2 = Findings.renderText({f, f2})
-- Sorted: alphabetically, "modules/cdm/cdm_icons.lua" sorts before
-- "modules/foo.lua" because 'c' < 'f'.
local expected2 = [[
modules/cdm/cdm_icons.lua:412:18 [advisory] tonumber: tainted value used in arithmetic without guard or unwrap (source: C_Spell.GetSpellCharges)
modules/foo.lua:10:1 [review] <unwrap>: review unwrap call site (source: Helpers.SafeValue)
]]
assert_eq(text2, expected2, "two findings text render")

-- Test 4: empty findings list
assert_eq(Findings.renderText({}), "", "empty list renders empty string")

print("findings test passed")

-- Test 5: type-validation in M.new
local function expectError(fn, pattern)
    local ok, err = pcall(fn)
    assert(not ok, "expected error, got success")
    assert(tostring(err):find(pattern, 1, true),
        "error should mention " .. pattern .. ", got: " .. tostring(err))
end

expectError(function() Findings.new{file=42, line=1, severity="advisory"} end,
    "file must be a string")
expectError(function() Findings.new{file="a", line="nope", severity="advisory"} end,
    "line must be a number")
expectError(function() Findings.new{file="a", line=1, severity=true} end,
    "severity must be a string")
expectError(function() Findings.new{file="a", line=1, severity="bogus"} end,
    "severity must be strict|advisory|review")

-- Test 6: multi-line message sanitized
local mlf = Findings.new {
    file = "a", line = 1, severity = "advisory",
    sink = "x", source_function = "y",
    message = "line1\nline2\rline3",
}
assert_eq(mlf.message, "line1 line2 line3", "newlines collapsed to single space")
local mlText = Findings.renderText({mlf})
assert(not mlText:sub(1, -2):find("\n"), "rendered text has no embedded newlines except trailing")

-- Test 7: deterministic sort on ties
local t1 = Findings.new{file="x", line=1, col=1, severity="advisory", sink="A", source_function="A", message="A"}
local t2 = Findings.new{file="x", line=1, col=1, severity="advisory", sink="B", source_function="A", message="A"}
local r1 = Findings.renderText({t1, t2})
local r2 = Findings.renderText({t2, t1})
assert_eq(r1, r2, "same findings render same regardless of input order")

print("findings hardening test passed")

-- JSON render test
local jsonOut = Findings.renderJSON({f, f2})
assert(jsonOut:find('"file": "modules/cdm/cdm_icons.lua"', 1, true),
    "first file in JSON")
assert(jsonOut:find('"file": "modules/foo.lua"', 1, true), "second file in JSON")
assert(jsonOut:sub(1, 1) == "[", "JSON starts with [")
assert(jsonOut:gsub("%s", ""):sub(-1) == "]", "JSON ends with ]")
print("findings JSON test passed")

local githubOut = Findings.renderGitHub({f, f2})
assert(githubOut:find("::warning file=modules/foo.lua,line=10,col=1::", 1, true),
    "review→warning annotation")
assert(githubOut:find("::warning file=modules/cdm/cdm_icons.lua,line=412,col=18::", 1, true),
    "advisory→warning annotation")
print("findings GitHub render test passed")

-- Strict severity → error
local fStrict = Findings.new {
    file = "modules/strict/foo.lua", line = 1, col = 1,
    severity = "strict", source_function = "X", sink = "Y", message = "Z",
}
local strictOut = Findings.renderGitHub({fStrict})
assert(strictOut:find("::error file=modules/strict/foo.lua", 1, true),
    "strict→error annotation")
print("findings GitHub strict test passed")
