-- tests/taint/analyzer_test.lua
local Analyzer = dofile("tests/taint/analyzer.lua")
local Registry = dofile("tests/taint/registry.lua")
local Config = dofile("tests/taint/config.lua")

local function assert_eq(a, e, msg)
    if a ~= e then error((msg or "") .. ": expected " .. tostring(e) ..
        ", got " .. tostring(a), 2) end
end

-- Skeleton smoke test: no sources registered → no findings on any input.
local r = Registry.new()
local cfg = Config.loadFromString(nil)

local source = [[
local x = 1
local y = x + 2
return y
]]
local findings = Analyzer.analyze(source, "modules/foo.lua", r, cfg)
assert_eq(type(findings), "table", "findings is a table")
assert_eq(#findings, 0, "no findings on plain code with no sources registered")

-- Parse error returns nil + err
local bad = "local = "
local f2, err = Analyzer.analyze(bad, "modules/bad.lua", r, cfg)
assert_eq(f2, nil, "parse error returns nil")
assert(err and #err > 0, "parse error has message")

print("analyzer skeleton test passed")

-- Test: source detection tracks taint set
local r2 = Registry.new()
r2:addSource("C_Spell.GetSpellCharges")

local source2 = [[
local info = C_Spell.GetSpellCharges(123)
local n = info.currentCharges
return n
]]
local findings2, err2, debug2 = Analyzer.analyze(
    source2, "modules/foo.lua", r2, cfg, { exposeDebug = true })
assert(findings2, "no error: " .. tostring(err2))

-- After analysis, the debug table should record `info` was tainted.
assert(debug2.taintedAt, "debug.taintedAt present")
assert(debug2.taintedAt.info, "info marked tainted (source assignment)")

-- For now, no findings yet (rule only adds taint, doesn't emit on tainted reads)
assert_eq(#findings2, 0, "no findings yet — only taint tracking")

print("source detection test passed")

-- Test: tainted local in arithmetic emits a finding
local r3 = Registry.new()
r3:addSource("C_Spell.GetSpellCharges")

local source3 = [[
local info = C_Spell.GetSpellCharges(1)
local n = info + 1
return n
]]
local findings3 = Analyzer.analyze(source3, "modules/foo.lua", r3, cfg)
assert_eq(#findings3, 1, "one finding for arith on tainted")
assert_eq(findings3[1].severity, "advisory", "advisory by default")
assert_eq(findings3[1].sink, "<arith>", "sink labeled arith")

-- Test: tainted local in tonumber call
local source4 = [[
local info = C_Spell.GetSpellCharges(1)
local n = tonumber(info)
return n
]]
local findings4 = Analyzer.analyze(source4, "modules/foo.lua", r3, cfg)
assert_eq(#findings4, 1, "one finding for tonumber on tainted")
assert_eq(findings4[1].sink, "tonumber", "sink labeled tonumber")

-- Test: tainted local in comparison
local source5 = [[
local info = C_Spell.GetSpellCharges(1)
if info == nil then return end
return 1
]]
local findings5 = Analyzer.analyze(source5, "modules/foo.lua", r3, cfg)
assert_eq(#findings5, 1, "one finding for comparison on tainted")
assert_eq(findings5[1].sink, "<comparison>", "sink labeled comparison")

-- Test: tainted local used as branch truthiness
local source5b = [[
local info = C_Spell.GetSpellCharges(1)
if info then
    return 1
end
return 0
]]
local findings5b = Analyzer.analyze(source5b, "modules/foo.lua", r3, cfg)
assert_eq(#findings5b, 1, "one finding for truthiness on tainted")
assert_eq(findings5b[1].sink, "<truthiness>", "sink labeled truthiness")

print("unsafe sink test passed")

-- Test: source nested in binop propagates taint
local r4 = Registry.new()
r4:addSource("S")
local sourceN1 = [[
local a = 1
local x = a + S()
return x
]]
local fN1, _, dN1 = Analyzer.analyze(sourceN1, "modules/foo.lua", r4, cfg, {exposeDebug=true})
assert(dN1.taintedAt.x, "x should be tainted (source nested in binop)")

-- Test: parenthesized expression with source
local sourceN2 = [[
local x = (S())
return x
]]
local fN2, _, dN2 = Analyzer.analyze(sourceN2, "modules/foo.lua", r4, cfg, {exposeDebug=true})
assert(dN2.taintedAt.x, "x should be tainted (source in parens)")

-- Test: parenthesized binop with tainted operand emits finding
local sourceN3 = [[
local a = S()
local x = (a + 1) * 2
return x
]]
local fN3 = Analyzer.analyze(sourceN3, "modules/foo.lua", r4, cfg)
assert_eq(#fN3, 1, "(a + 1) * 2 should emit one finding for the inner +")
assert_eq(fN3[1].sink, "<arith>", "inner arith found")

-- Test: unop on tainted local emits finding
local sourceN4 = [[
local a = S()
local x = -a
return x
]]
local fN4 = Analyzer.analyze(sourceN4, "modules/foo.lua", r4, cfg)
assert_eq(#fN4, 1, "-a should emit a finding")
assert(fN4[1].sink:find("unop"), "sink labeled with unop, got: " .. fN4[1].sink)

print("nested taint propagation test passed")

-- Test: tainted local passed to safe sink method emits no finding
local r5 = Registry.new()
r5:addSource("C_Spell.GetSpellCooldownDuration")

local source6 = [[
local durObj = C_Spell.GetSpellCooldownDuration(123)
cd:SetCooldownFromDurationObject(durObj)
]]
local findings6 = Analyzer.analyze(source6, "modules/foo.lua", r5, cfg)
assert_eq(#findings6, 0, "no finding when piped to safe sink method")

-- Test: tainted local passed to C_StringUtil formatter (qualified safe sink)
local source7 = [[
local n = C_Spell.GetSpellCooldownDuration(1)
text:SetText(C_StringUtil.RoundToNearestString(n, 5))
]]
local findings7 = Analyzer.analyze(source7, "modules/foo.lua", r5, cfg)
assert_eq(#findings7, 0, "no finding through C_StringUtil + SetText pipeline")

-- Test: control — same value to tonumber emits one finding
local source8 = [[
local n = C_Spell.GetSpellCooldownDuration(1)
local m = tonumber(n)
]]
local findings8 = Analyzer.analyze(source8, "modules/foo.lua", r5, cfg)
assert_eq(#findings8, 1, "control: tonumber still emits finding")

print("safe sink test passed")

-- Test: every unwrap call produces a review finding
local r6 = Registry.new()
r6:addSource("C_Spell.GetSpellCharges")

local source9 = [[
local info = C_Spell.GetSpellCharges(1)
local n = Helpers.SafeValue(info, 0)
return n
]]
local findings9 = Analyzer.analyze(source9, "modules/foo.lua", r6, cfg)
assert_eq(#findings9, 1, "one review finding for unwrap call")
assert_eq(findings9[1].severity, "review", "review tier")
assert_eq(findings9[1].sink, "<unwrap>", "unwrap sink label")
assert_eq(findings9[1].source_function, "Helpers.SafeValue", "unwrap name in source_function")

-- Test: post-unwrap, value is untainted (no further finding on read)
local source10 = [[
local info = C_Spell.GetSpellCharges(1)
local n = Helpers.SafeToNumber(info, 0)
local m = n + 1
return m
]]
local findings10 = Analyzer.analyze(source10, "modules/foo.lua", r6, cfg)
assert_eq(#findings10, 1, "only the review finding; no arith finding on n")
assert_eq(findings10[1].severity, "review", "review tier")

print("unwrap test passed")

-- Test: guard untaints in then-branch
local r7 = Registry.new()
r7:addSource("C_Spell.GetSpellCharges")

local source11 = [[
local info = C_Spell.GetSpellCharges(1)
if not Helpers.IsSecretValue(info) then
    local n = info + 1
    return n
end
return 0
]]
local findings11 = Analyzer.analyze(source11, "modules/foo.lua", r7, cfg)
assert_eq(#findings11, 0, "guard makes arith on info safe in then-branch")

-- Test: guard untaints in else-branch
local source12 = [[
local info = C_Spell.GetSpellCharges(1)
if Helpers.IsSecretValue(info) then
    return 0
else
    local n = info + 1
    return n
end
]]
local findings12 = Analyzer.analyze(source12, "modules/foo.lua", r7, cfg)
assert_eq(#findings12, 0, "guard untaints in else-branch")

-- Test: after the if/end, taint is restored (union of branches)
local source13 = [[
local info = C_Spell.GetSpellCharges(1)
if not Helpers.IsSecretValue(info) then
    local n = info + 1
end
local m = info + 2
return m
]]
local findings13 = Analyzer.analyze(source13, "modules/foo.lua", r7, cfg)
assert_eq(#findings13, 1, "post-guard read still tainted")

print("guard test passed")

-- Test: HasSecretValue untaints all named-local args in then-branch
local r8 = Registry.new()
r8:addSource("C_Spell.GetSpellCharges")

local source14 = [[
local a = C_Spell.GetSpellCharges(1)
local b = C_Spell.GetSpellCharges(2)
if not Helpers.HasSecretValue(a, b) then
    local sum = a + b
    return sum
end
return 0
]]
local findings14 = Analyzer.analyze(source14, "modules/foo.lua", r8, cfg)
assert_eq(#findings14, 0, "HasSecretValue untaints all locals in then-branch")

print("HasSecretValue guard test passed")

-- Test: trailing annotation suppresses finding
local r9 = Registry.new()
r9:addSource("C_Spell.GetSpellCharges")

local source15 = [[
local info = C_Spell.GetSpellCharges(1)
local n = info + 1  -- @secret-safe: justified for unit test
return n
]]
local findings15 = Analyzer.analyze(source15, "modules/foo.lua", r9, cfg)
-- Default: filter suppressed findings out of the returned list
assert_eq(#findings15, 0, "annotated finding suppressed")

-- Verbose: returns all findings including suppressed
local findings15v = Analyzer.analyze(source15, "modules/foo.lua", r9, cfg,
    { includeSuppressed = true })
assert_eq(#findings15v, 1, "verbose includes suppressed")
assert_eq(findings15v[1].suppressed, true, "marked suppressed")
assert_eq(findings15v[1].suppression_reason, "justified for unit test", "reason captured")

-- Empty reason: harness warning, finding NOT suppressed
local source16 = [[
local info = C_Spell.GetSpellCharges(1)
local n = info + 1  -- @secret-safe:
return n
]]
local findings16, err16, debug16 = Analyzer.analyze(
    source16, "modules/foo.lua", r9, cfg, { exposeDebug = true })
assert_eq(#findings16, 1, "empty-reason annotation does not suppress")
assert(debug16.warnings, "harness warnings present")
assert_eq(#debug16.warnings, 1, "one warning for empty-reason annotation")

print("annotation suppression test passed")

-- Test: t.k = source(); local v = t.k → v is tainted
local r10 = Registry.new()
r10:addSource("C_Spell.GetSpellCharges")

local source17 = [[
local t = {}
t.x = C_Spell.GetSpellCharges(1)
local v = t.x
local n = v + 1
return n
]]
local findings17 = Analyzer.analyze(source17, "modules/foo.lua", r10, cfg)
assert_eq(#findings17, 1, "field-tainted local flows to arith")

-- Test: different field key not affected
local source18 = [[
local t = {}
t.x = C_Spell.GetSpellCharges(1)
t.y = 5
local v = t.y
local n = v + 1
return n
]]
local findings18 = Analyzer.analyze(source18, "modules/foo.lua", r10, cfg)
assert_eq(#findings18, 0, "different field is not tainted")

print("field-sensitivity test passed")

-- Test: stable loop (taint set unchanged across iterations)
local r11 = Registry.new()
r11:addSource("C_Spell.GetSpellCharges")

local source19 = [[
for i = 1, 10 do
    local info = C_Spell.GetSpellCharges(i)
    local n = info + 1
end
return 0
]]
local findings19 = Analyzer.analyze(source19, "modules/foo.lua", r11, cfg)
-- Loop body has one unsafe sink. The two-iteration walk should emit
-- exactly one finding (only the second-pass walk emits, first pass discarded).
assert(#findings19 >= 1, "loop body's unsafe sink found")
assert_eq(findings19[1].sink, "<arith>", "arith sink")

print("loop test passed")

-- Test: while condition walked for sinks
local r12 = Registry.new()
r12:addSource("S")

local sourceL1 = [[
local x = S()
while x > 5 do
    break
end
]]
local fL1 = Analyzer.analyze(sourceL1, "modules/foo.lua", r12, cfg)
assert_eq(#fL1, 1, "while-condition comparison emits")
assert_eq(fL1[1].sink, "<comparison>", "comparison sink")

-- Test: while condition rejects bare tainted truthiness
local sourceL1b = [[
local x = S()
while x do
    break
end
]]
local fL1b = Analyzer.analyze(sourceL1b, "modules/foo.lua", r12, cfg)
assert_eq(#fL1b, 1, "while-condition truthiness emits")
assert_eq(fL1b[1].sink, "<truthiness>", "truthiness sink")

-- Test: numeric-for End bound walked
-- The End expression is a bare VarExpr `x`. There is no registered sink shape
-- for a bare variable used as a loop bound (no comparison/arith/builtin call),
-- so 0 findings is expected. This is a known limitation: tainted values that
-- flow into numeric-for bounds are not caught unless they appear in a sink shape.
local sourceL2 = [[
local x = S()
for i = 1, x do
    break
end
]]
local fL2 = Analyzer.analyze(sourceL2, "modules/foo.lua", r12, cfg)
print("loop header walk tests — numeric-for End bound finding count: " .. #fL2 .. " (0 expected, bare VarExpr is not a sink shape)")
assert_eq(#fL2, 0, "bare tainted VarExpr as loop bound emits no finding (known limitation)")

-- Test: generic-for generator with tainted argument
-- pairs(t) — pairs is in UNSAFE_BUILTIN_FUNCTIONS; called with tainted t.
local sourceL3 = [[
local t = S()
for k, v in pairs(t) do
    break
end
]]
local fL3 = Analyzer.analyze(sourceL3, "modules/foo.lua", r12, cfg)
assert_eq(#fL3, 1, "pairs(tainted) emits one finding")
assert_eq(fL3[1].sink, "pairs", "pairs sink")

print("loop header expression tests passed")

-- Test: file under strict_paths → finding severity = strict
local strictCfg = Config.loadFromString([[
return { strict_paths = { "modules/cdm/" } }
]])

local r13 = Registry.new()
r13:addSource("C_Spell.GetSpellCharges")

local source20 = [[
local info = C_Spell.GetSpellCharges(1)
local n = info + 1
]]
local findings20 = Analyzer.analyze(
    source20, "modules/cdm/cdm_icon_renderer.lua", r13, strictCfg)
assert_eq(#findings20, 1, "one finding")
assert_eq(findings20[1].severity, "strict", "promoted to strict by path")

-- Same source, different path → advisory
local findings21 = Analyzer.analyze(
    source20, "modules/foo.lua", r13, strictCfg)
assert_eq(findings21[1].severity, "advisory", "advisory outside strict path")

-- Unwrap is review regardless of path
local source22 = [[
local info = C_Spell.GetSpellCharges(1)
local n = Helpers.SafeValue(info, 0)
]]
local findings22 = Analyzer.analyze(
    source22, "modules/cdm/cdm_icon_renderer.lua", r13, strictCfg)
assert_eq(findings22[1].severity, "review", "unwrap stays review")

local strictUnwrapCfg = Config.loadFromString([[
return {
    strict_paths = { "modules/cdm/" },
    strict_unwrap_paths = { "modules/cdm/" },
}
]])

local findings23 = Analyzer.analyze(
    source22, "modules/cdm/cdm_icon_renderer.lua", r13, strictUnwrapCfg)
assert_eq(findings23[1].severity, "strict",
    "unwrap is strict under configured CDM unwrap path")

local findings24 = Analyzer.analyze(
    source22, "modules/foo.lua", r13, strictUnwrapCfg)
assert_eq(findings24[1].severity, "review",
    "unwrap remains review outside configured CDM unwrap path")

print("severity test passed")

-- Test: pcall(<source>, ...) recognized as source, taint propagates
local r14 = Registry.new()
r14:addSource("C_Spell.GetSpellCharges")

local sourceP1 = [[
local ok, info = pcall(C_Spell.GetSpellCharges, 123)
local n = info + 1
return n
]]
local fP1 = Analyzer.analyze(sourceP1, "modules/foo.lua", r14, cfg)
assert_eq(#fP1, 1, "pcall(source,...) result is tainted, info+1 emits")

-- Test: xpcall(<source>, handler, ...) recognized too
local sourceP2 = [[
local ok, info = xpcall(C_Spell.GetSpellCharges, somehandler, 123)
local n = info + 1
return n
]]
local fP2 = Analyzer.analyze(sourceP2, "modules/foo.lua", r14, cfg)
assert_eq(#fP2, 1, "xpcall(source,...) result is tainted, info+1 emits")

-- Test: pcall(<non-source>, ...) does NOT taint
local sourceP3 = [[
local ok, info = pcall(some_other_function, 123)
local n = info + 1
return n
]]
local fP3 = Analyzer.analyze(sourceP3, "modules/foo.lua", r14, cfg)
assert_eq(#fP3, 0, "pcall(non-source,...) does NOT taint")

print("pcall source detection test passed")

-- Test: reading a field on a tainted base local is tainted
local r15 = Registry.new()
r15:addSource("C_Spell.GetSpellCharges")

-- Direct: pcall result, then field access
local sourceFB1 = [[
local ok, info = pcall(C_Spell.GetSpellCharges, 123)
local n = info.currentCharges + 1
return n
]]
local fFB1 = Analyzer.analyze(sourceFB1, "modules/foo.lua", r15, cfg)
assert_eq(#fFB1, 1, "info.field+1 emits when info is tainted")
assert_eq(fFB1[1].sink, "<arith>", "arith sink")

-- Bare field-tainted-base read into local, then arith
local sourceFB2 = [[
local info = C_Spell.GetSpellCharges(1)
local n = info.charges
local m = n + 1
return m
]]
local fFB2 = Analyzer.analyze(sourceFB2, "modules/foo.lua", r15, cfg)
assert_eq(#fFB2, 1, "field-of-tainted-base flows through to arith")

-- Field-on-clean-local does NOT taint
local sourceFB3 = [[
local info = { currentCharges = 5 }
local n = info.currentCharges + 1
return n
]]
local fFB3 = Analyzer.analyze(sourceFB3, "modules/foo.lua", r15, cfg)
assert_eq(#fFB3, 0, "field of clean local does not taint")

-- Deep chain: tainted.sub.field
local sourceFB4 = [[
local info = C_Spell.GetSpellCharges(1)
local n = info.sub.field + 1
return n
]]
local fFB4 = Analyzer.analyze(sourceFB4, "modules/foo.lua", r15, cfg)
assert_eq(#fFB4, 1, "deep field chain on tainted base flows")

-- Closure capture: sort/callback predicates must still see tainted upvalues.
local sourceFB5 = [[
local info = C_Spell.GetSpellCharges(1)
table.sort(rows, function(a, b)
    return info.currentCharges < 2
end)
]]
local fFB5 = Analyzer.analyze(sourceFB5, "modules/foo.lua", r15, cfg)
assert_eq(#fFB5, 1, "closure comparison on tainted upvalue emits")
assert_eq(fFB5[1].sink, "<comparison>", "comparison sink in closure")

-- Function parameters shadow tainted outer locals.
local sourceFB6 = [[
local info = C_Spell.GetSpellCharges(1)
local function f(info)
    return info + 1
end
return f(1)
]]
local fFB6 = Analyzer.analyze(sourceFB6, "modules/foo.lua", r15, cfg)
assert_eq(#fFB6, 0, "function parameter shadows tainted upvalue")

print("tainted-base field read test passed")

-- ===========================================================================
-- Secret-returning functions (taint propagates from the return value)
-- ---------------------------------------------------------------------------
-- C_StringUtil formatters accept secret-tagged arguments without erroring
-- (they are safe sinks), but they also RETURN secret-tagged values. The local
-- assigned from such a call must be treated as tainted, so downstream
-- comparisons like `s == "0"` get flagged. Closes the analyzer gap that hid
-- the live taint crash at damage_meter.lua:906.
-- ===========================================================================

local rSR = Registry.new()

-- Assignment from a secret-returning safe sink taints the LHS.
local srcSR1 = [[
local s = C_StringUtil.TruncateWhenZero(123)
return s
]]
local _fSR1, _eSR1, dSR1 = Analyzer.analyze(
    srcSR1, "modules/foo.lua", rSR, cfg, { exposeDebug = true })
assert(dSR1.taintedAt.s, "s tainted by C_StringUtil.TruncateWhenZero return")

-- Comparison on a secret-returning call's result emits a <comparison> finding.
local srcSR2 = [[
local s = C_StringUtil.TruncateWhenZero(123)
if s == "0" then return end
return 1
]]
local fSR2 = Analyzer.analyze(srcSR2, "modules/foo.lua", rSR, cfg)
assert_eq(#fSR2, 1, "comparison on secret-returning result emits one finding")
assert_eq(fSR2[1].sink, "<comparison>", "sink labeled comparison")

-- Existing safe-sink behavior preserved: passing a tainted arg into the same
-- function does not emit a finding for that argument-passing step.
local rSR3 = Registry.new()
rSR3:addSource("C_Spell.GetSpellInfo")
local srcSR3 = [[
local info = C_Spell.GetSpellInfo(1)
local s = C_StringUtil.TruncateWhenZero(info)
return s
]]
local fSR3 = Analyzer.analyze(srcSR3, "modules/foo.lua", rSR3, cfg)
assert_eq(#fSR3, 0, "passing tainted into safe-sink does not emit at call site")

-- Pipeline: SetText(C_StringUtil.TruncateWhenZero(secret)) is fully safe —
-- the SetText safe-sink method consumes the secret return inline.
local srcSR4 = [[
local info = C_Spell.GetSpellInfo(1)
frame:SetText(C_StringUtil.TruncateWhenZero(info))
]]
local fSR4 = Analyzer.analyze(srcSR4, "modules/foo.lua", rSR3, cfg)
assert_eq(#fSR4, 0, "SetText consumes secret-returning result safely")

-- Arithmetic on a secret-returning result emits an <arith> finding.
local srcSR5 = [[
local s = C_StringUtil.RoundToNearestString(100, 10)
local n = s + 1
return n
]]
local fSR5 = Analyzer.analyze(srcSR5, "modules/foo.lua", rSR, cfg)
assert_eq(#fSR5, 1, "arith on secret-returning result emits one finding")
assert_eq(fSR5[1].sink, "<arith>", "sink labeled arith")

-- Guard on the secret-returning result clears taint in the safe branch.
local srcSR6 = [[
local s = C_StringUtil.TruncateWhenZero(1)
if not Helpers.IsSecretValue(s) then
    if s == "0" then return end
end
return 1
]]
local fSR6 = Analyzer.analyze(srcSR6, "modules/foo.lua", rSR, cfg)
assert_eq(#fSR6, 0, "guard untaints secret-returning result in then-branch")

print("secret-returning test passed")
