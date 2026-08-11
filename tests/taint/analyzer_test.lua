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
-- These methods are api-index safe sinks at real scan time (durationObjectArg /
-- AllowedWhenTainted); register them so the bare unit registry exercises the
-- safe-sink branch rather than the round-13 default-reject fall-through.
r5:addSafeSinkMethod("SetCooldownFromDurationObject")
r5:addSafeSinkMethod("SetText")

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
-- Round-13b: `return 0` in the secret branch is a secret-to-state collapse
-- (manufactured ordinary value) — the guard still untaints the else-branch
-- arith, so the collapse finding is the ONLY one.
assert_eq(#findings12, 1, "guard untaints in else-branch; only the collapse flags")
assert_eq(findings12[1].sink, "<secret-collapse>",
    "literal return in the secret branch flags collapse")

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
-- Loop body has one unsafe sink. Fixpoint discovery walks are silent and the
-- single emitting transfer from the converged head reports it once.
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
-- A numeric-for consumes every bound/step numerically, so even a bare tainted
-- reference is an unsafe sink shape.
local sourceL2 = [[
local x = S()
for i = 1, x do
    break
end
]]
local fL2 = Analyzer.analyze(sourceL2, "modules/foo.lua", r12, cfg)
assert_eq(#fL2, 1, "bare tainted VarExpr as loop bound emits")
assert_eq(fL2[1].sink, "<numeric-for>", "numeric-for sink label")

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
-- SetText is an api-index safe sink at real scan time; register it so the
-- SetText pipeline exercises the safe-sink branch, not round-13 default-reject.
rSR3:addSafeSinkMethod("SetText")
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

-- ---------------------------------------------------------------------------
-- Precondition-guarded API scan (<precondition>, review tier)
-- ---------------------------------------------------------------------------
local rPre = Registry.new()
rPre:addPreconditionAPI("C_UnitAuras.GetUnitAuras", { "RequiresUnitAuraAccess" })

local function preFindings(findings)
    local out = {}
    for _, f in ipairs(findings or {}) do
        if f.sink == "<precondition>" then out[#out + 1] = f end
    end
    return out
end

-- Raw call in an ungated function -> one review finding
local srcP1 = [[
local function scan(unit)
    local auras = C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    return auras
end
return scan
]]
local fP1 = preFindings(Analyzer.analyze(srcP1, "modules/foo.lua", rPre, cfg))
assert_eq(#fP1, 1, "raw guarded call flagged")
assert_eq(fP1[1].severity, "review", "precondition finding is review tier")
assert_eq(fP1[1].source_function, "C_UnitAuras.GetUnitAuras", "source names the API")

-- pcall'd function REFERENCE -> no finding (not a CallExpr)
local srcP2 = [[
local function scan(unit)
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL")
    return ok and auras
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP2, "modules/foo.lua", rPre, cfg)), 0,
    "pcall function-reference not flagged")

-- Call inside a pcall'd closure -> protected, no finding
local srcP3 = [[
local function scan(unit)
    local ok = pcall(function()
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end)
    return ok
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP3, "modules/foo.lua", rPre, cfg)), 0,
    "pcall-protected closure not flagged")

-- Gate consulted BEFORE the call in the same function scope -> no finding
local srcP4 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP4, "modules/foo.lua", rPre, cfg)), 0,
    "gate in same scope not flagged")

-- Gate in an OUTER function scope covers nested closures (lexical inherit)
local srcP5 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    local function inner()
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
    return inner()
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP5, "modules/foo.lua", rPre, cfg)), 0,
    "outer-scope gate covers nested closure")

-- Gate in a SIBLING function does NOT cover (non-interprocedural)
local srcP6 = [[
local function gated()
    return C_Secrets.ShouldAurasBeSecret()
end
local function scan(unit)
    if gated() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP6, "modules/foo.lua", rPre, cfg)), 1,
    "sibling-function gate does not cover (needs @secret-safe annotation)")

-- @secret-safe annotation suppresses the finding
local srcP7 = [[
local function scan(unit)
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL") -- @secret-safe: caller gates
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP7, "modules/foo.lua", rPre, cfg)), 0,
    "@secret-safe suppresses precondition finding")

-- Unregistered API never flags
local srcP8 = [[
local function scan(unit)
    return C_UnitAuras.GetAuraDataBySpellName(unit, "Rejuvenation")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP8, "modules/foo.lua", rPre, cfg)), 0,
    "unregistered API not flagged")

-- Gate consulted AFTER the call -> flagged (the walk is statement-ordered;
-- a gate below the call cannot have protected it)
do
local srcP9 = [[
local function scan(unit)
    local auras = C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    return auras
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP9, "modules/foo.lua", rPre, cfg)), 1,
    "gate below the call does not protect it")

-- Guarded CALL in a non-first pcall argument -> flagged (evaluated before
-- pcall takes over; only argument 1 is protected)
end
do
local srcP10 = [[
local function scan(unit)
    local ok = pcall(print, C_UnitAuras.GetUnitAuras(unit, "HELPFUL"))
    return ok
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP10, "modules/foo.lua", rPre, cfg)), 1,
    "guarded call in outer pcall argument position flagged")

-- Positive gate clause + call in the ELSE branch -> not flagged: the else
-- of a single positive-gate if runs only when UNRESTRICTED
end
do
local srcP11 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then
        return nil
    else
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP11, "modules/foo.lua", rPre, cfg)), 0,
    "else branch of a positive gate is the unrestricted path")

-- Ordering applies inside nested blocks too: gate above the call in a loop
-- body is clean; a later sibling statement after the gated one stays gated
end
do
local srcP12 = [[
local function scan(units)
    for i = 1, #units do
        if C_Secrets.ShouldAurasBeSecret() then return nil end
        local auras = C_UnitAuras.GetUnitAuras(units[i], "HELPFUL")
        if auras then return auras end
    end
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP12, "modules/foo.lua", rPre, cfg)), 0,
    "gate above the call inside a nested block protects it")

-- Ignored gate result -> no protection (nothing branches on it)
end
do
local srcP14 = [[
local function scan(unit)
    local x = C_Secrets.ShouldAurasBeSecret()
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP14, "modules/foo.lua", rPre, cfg)), 1,
    "gate with ignored result does not protect")

-- Non-terminating positive branch -> no dominance for later statements
end
do
local srcP15 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then
        print("restricted")
    end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP15, "modules/foo.lua", rPre, cfg)), 1,
    "non-terminating gate branch does not protect later calls")

-- INVERTED gate: guarded call inside the RESTRICTED branch -> flagged (it
-- is a guaranteed hard error there)
end
do
local srcP16 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
    return nil
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP16, "modules/foo.lua", rPre, cfg)), 1,
    "guarded call inside the restricted branch flagged")

-- Negated gate: the then-branch is the unrestricted path -> clean
end
do
local srcP17 = [[
local function scan(unit)
    if not C_Secrets.ShouldAurasBeSecret() then
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
    return nil
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP17, "modules/foo.lua", rPre, cfg)), 0,
    "negated gate then-branch is the unrestricted path")

-- The authored `and`-chain idiom keeps working
end
do
local srcP18 = [[
local function scan(unit)
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return nil
    end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP18, "modules/foo.lua", rPre, cfg)), 0,
    "and-chain positive gate with terminating body dominates")

-- pcall(API()) evaluates the call BEFORE pcall runs -> flagged
end
do
local srcP19 = [[
local function scan(unit)
    local ok = pcall(C_UnitAuras.GetUnitAuras(unit, "HELPFUL"))
    return ok
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP19, "modules/foo.lua", rPre, cfg)), 1,
    "call expression in pcall argument 1 evaluates unprotected")

-- File-local alias of a guarded API -> resolved and flagged
end
do
local srcP20 = [[
local GetAuras = C_UnitAuras.GetUnitAuras
local function scan(unit)
    return GetAuras(unit, "HELPFUL")
end
return scan
]]
local fP20 = preFindings(Analyzer.analyze(srcP20, "modules/foo.lua", rPre, cfg))
assert_eq(#fP20, 1, "aliased guarded call flagged")
assert_eq(fP20[1].source_function, "C_UnitAuras.GetUnitAuras",
    "alias finding names the canonical API")

-- Aliased call behind a proper gate stays clean
end
do
local srcP21 = [[
local GetAuras = C_UnitAuras.GetUnitAuras
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    return GetAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP21, "modules/foo.lua", rPre, cfg)), 0,
    "gated aliased call not flagged")

-- UNSOUND elseif: an earlier clause's true-path skips the gate entirely —
-- only clause 1 can prove dominance (2026-07 round-3)
end
do
local srcP23 = [[
local function scan(unit, mode)
    if mode == "off" then
        print("off")
    elseif C_Secrets.ShouldAurasBeSecret() then
        return nil
    end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP23, "modules/foo.lua", rPre, cfg)), 1,
    "elseif gate does not dominate (earlier clause can skip it)")

-- `gate() == true` bail dominates
end
do
local srcP24 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() == true then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP24, "modules/foo.lua", rPre, cfg)), 0,
    "gate() == true bail dominates")

-- `gate() or X` bail dominates: restricted implies the disjunction is true
end
do
local srcP25 = [[
local function scan(unit, cached)
    if C_Secrets.ShouldAurasBeSecret() or cached then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP25, "modules/foo.lua", rPre, cfg)), 0,
    "gate-or-X bail dominates (restricted implies condition true)")

-- ...but the BODY of a gate-or-X condition is restricted-reachable: a
-- guarded call inside it flags
end
do
local srcP26 = [[
local function scan(unit, fallback)
    if C_Secrets.ShouldAurasBeSecret() or fallback then
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP26, "modules/foo.lua", rPre, cfg)), 1,
    "guarded call in a restricted-reachable or-branch flagged")

-- Later-callback: a closure passed to an arbitrary call ESCAPES the gate —
-- it can run under a different restriction state
end
do
local srcP27 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    C_Timer.After(0, function()
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end)
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP27, "modules/foo.lua", rPre, cfg)), 1,
    "escaping closure does not inherit the registration-site gate")

-- Arbitrary conjunct must NOT establish dominance: `someFlag and gate()`
-- can be false while restricted (2026-07 round-4)
end
do
local srcP28 = [[
local function scan(unit, someFlag)
    if someFlag and C_Secrets.ShouldAurasBeSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP28, "modules/foo.lua", rPre, cfg)), 1,
    "arbitrary conjunct does not flip (flag false + restricted slips through)")

-- Unmodeled comparison grants nothing: `gate() ~= nil` is always true
end
do
local srcP29 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() ~= nil then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP29, "modules/foo.lua", rPre, cfg)), 1,
    "unmodeled gate comparison stays ungated")

-- Named callback escape: a local function passed as a call argument runs
-- later — the definition-time gate proves nothing
end
do
local srcP30 = [[
local f = CreateFrame("Frame")
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    local function onEvent(self, event, unit2)
        return C_UnitAuras.GetUnitAuras(unit2, "HELPFUL")
    end
    f:SetScript("OnEvent", onEvent)
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP30, "modules/foo.lua", rPre, cfg)), 1,
    "escaped named callback does not inherit the definition-time gate")

-- ...but a named local only ever CALLED synchronously still inherits (srcP5
-- shape) — covered by srcP5 above; re-assert with the escape prepass active
assert_eq(#preFindings(Analyzer.analyze(srcP5, "modules/foo.lua", rPre, cfg)), 0,
    "synchronously-called named local still inherits the gate")

-- Guarded alias init: `local Get = C_UnitAuras and C_UnitAuras.GetUnitAuras`
end
do
local srcP31 = [[
local GetAuras = C_UnitAuras and C_UnitAuras.GetUnitAuras
local function scan(unit)
    return GetAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP31, "modules/foo.lua", rPre, cfg)), 1,
    "guarded alias init resolved and flagged")

-- Alias chain: `local A = api; local B = A; B()`
end
do
local srcP32 = [[
local A = C_UnitAuras.GetUnitAuras
local B = A
local function scan(unit)
    return B(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP32, "modules/foo.lua", rPre, cfg)), 1,
    "alias chain resolved and flagged")

-- Namespace alias: `local UA = C_UnitAuras; UA.GetUnitAuras()`
end
do
local srcP33 = [[
local UA = C_UnitAuras
local function scan(unit)
    return UA.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP33, "modules/foo.lua", rPre, cfg)), 1,
    "namespace alias resolved and flagged")

-- Gate aliases keep protection working: aliased gate function AND aliased
-- gate namespace both recognized (the repo's `local _C_ShouldAurasBeSecret =
-- C_Secrets and C_Secrets.ShouldAurasBeSecret` idiom)
end
do
local srcP34 = [[
local isSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret
local function scan(unit)
    if isSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP34, "modules/foo.lua", rPre, cfg)), 0,
    "aliased gate function still dominates")

end
do
local srcP35 = [[
local S = C_Secrets
local function scan(unit)
    if S and S.ShouldAurasBeSecret and S.ShouldAurasBeSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#preFindings(Analyzer.analyze(srcP35, "modules/foo.lua", rPre, cfg)), 0,
    "gate through a namespace alias still dominates")

-- strict_precondition_paths promotes precondition findings to strict
end
do
local cfgStrictLib = Config.loadFromString(
    "return { strict_precondition_paths = { 'libs/' } }")
local fP22 = preFindings(Analyzer.analyze(srcP1, "libs/SomeLib/foo.lua", rPre, cfgStrictLib))
assert_eq(#fP22, 1, "strict-precondition path still finds the raw call")
assert_eq(fP22[1].severity, "strict", "precondition finding promoted to strict")

end
do
-- preconditionOnly mode (vendored-lib coverage): the taint pass is skipped,
-- the raw guarded-call scan still runs
end
do
local srcP13 = [[
local function scan(unit)
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
local fP13 = Analyzer.analyze(srcP13, "libs/foo.lua", rPre, cfg, { preconditionOnly = true })
local preP13 = preFindings(fP13)
assert_eq(#preP13, 1, "preconditionOnly: guarded call still flagged")
assert_eq(#fP13, #preP13, "preconditionOnly: no non-precondition findings emitted")

end
print("precondition scan test passed")

-- ---------------------------------------------------------------------------
-- Secret event payload seeding (config event_payload_params)
-- ---------------------------------------------------------------------------
do
local rEvt = Registry.new()
rEvt:addSecretPayloadEvent("UNIT_AURA", { 4 })

-- Handler detected by its event-name comparison: configured param position 4
-- (updateInfo) is a taint source; position 3 (unit) is not.
local srcE1 = [[
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        print(unit)
        print(updateInfo)
    end
end)
]]
local fE1 = Analyzer.analyze(srcE1, "modules/foo.lua", rEvt, cfg)
assert_eq(#fE1, 1, "secret event payload param flagged at sink (unit param stays clean)")

-- Handler for a non-secret event: nothing seeded
local srcE2 = [[
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "PLAYER_LOGIN" then
        print(updateInfo)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcE2, "modules/foo.lua", rEvt, cfg), 0,
    "non-secret event handler not seeded")

-- Registry without configured events: no seeding at all
assert_eq(#Analyzer.analyze(srcE1, "modules/foo.lua", rPre, cfg), 0,
    "no event_payload_params config, no seeding")

end
print("secret event payload test passed")

-- Aspect + direct-use test blocks live in one do…end scope: the main chunk
-- was brushing Lua 5.1's 200-local limit, and block scoping frees these
-- locals' registers at the closing end.
do
-- Test: aspect-returning widget getters (secretReturnsForAspect) taint their
-- results ONLY inside config aspect_paths.
local rAsp = Registry.new()
rAsp:addAspectReturningMethod("GetAlpha", { "Alpha" })

local cfgAsp = Config.loadFromString([[return {
    aspect_paths = { "QUI_CDM/" },
}]])

local srcAsp = [[
local icon = GetIcon()
local a = icon:GetAlpha()
if a > 0.5 then return end
]]

-- Inside an aspect path: comparison on the getter result is flagged
local fAsp1 = Analyzer.analyze(srcAsp, "QUI_CDM/cdm/foo.lua", rAsp, cfgAsp)
assert_eq(#fAsp1, 1, "aspect getter result comparison flagged inside aspect_paths")

-- Outside aspect paths: same source, registry auto-stripped, nothing fires
local fAsp2 = Analyzer.analyze(srcAsp, "modules/foo.lua", rAsp, cfgAsp)
assert_eq(#fAsp2, 0, "aspect getter inert outside aspect_paths")

-- Empty aspect_paths (defaults): inert everywhere
local fAsp3 = Analyzer.analyze(srcAsp, "QUI_CDM/cdm/foo.lua", rAsp, cfg)
assert_eq(#fAsp3, 0, "aspect getter inert with default (empty) aspect_paths")

-- Piping the getter result straight into a safe sink stays clean
local srcAspSink = [[
local icon = GetIcon()
local other = GetOther()
other:SetAlpha(icon:GetAlpha())
]]
local rAspSink = Registry.new()
rAspSink:addAspectReturningMethod("GetAlpha", { "Alpha" })
-- SetAlpha is the C-side sink here; an api-index safe sink at real scan time.
-- Register it so this exercises the safe-sink branch, not default-reject.
rAspSink:addSafeSinkMethod("SetAlpha")
assert_eq(#Analyzer.analyze(srcAspSink, "QUI_CDM/cdm/foo.lua", rAspSink, cfgAsp), 0,
    "aspect getter piped to C-side sink is clean")

print("aspect getter test passed")

-- Test: DIRECT source-call operands (no intermediate local) are flagged in
-- comparisons, unary ops, and unsafe-builtin arguments.
local rDirect = Registry.new()
rDirect:addSource("C_Spell.GetSpellCastCount")
rDirect:addAspectReturningMethod("GetAlpha", { "Alpha" })
rDirect:addAspectReturningMethod("IsShown", { "Shown" })

local srcDirect = [[
local icon = GetIcon()
if icon:GetAlpha() > 0.5 then return end
]]
assert_eq(#Analyzer.analyze(srcDirect, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "direct aspect-getter comparison flagged (no intermediate local)")

local srcDirectNot = [[
local icon = GetIcon()
if not icon:IsShown() then return end
]]
assert_eq(#Analyzer.analyze(srcDirectNot, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "direct aspect-getter under unary not flagged")

local srcDirectBuiltin = [[
local icon = GetIcon()
local s = tostring(icon:GetAlpha())
]]
assert_eq(#Analyzer.analyze(srcDirectBuiltin, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "direct aspect-getter passed to unsafe builtin flagged")

-- Dotted sources get the same direct-use coverage
local srcDirectDotted = [[
if C_Spell.GetSpellCastCount(61304) > 0 then return end
]]
assert_eq(#Analyzer.analyze(srcDirectDotted, "modules/foo.lua", rDirect, cfgAsp), 1,
    "direct dotted-source comparison flagged")

-- Outside aspect_paths the getters stay inert even in direct use
assert_eq(#Analyzer.analyze(srcDirect, "modules/foo.lua", rDirect, cfgAsp), 0,
    "direct aspect-getter inert outside aspect_paths")

print("direct source-call use test passed")

-- Test: BARE direct source-call truthiness (`if icon:IsShown() then`) —
-- result truth-tested without ever landing in a local.
local srcBareIf = [[
local icon = GetIcon()
if icon:IsShown() then return end
]]
assert_eq(#Analyzer.analyze(srcBareIf, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "bare aspect-getter if-condition flagged")
assert_eq(#Analyzer.analyze(srcBareIf, "modules/foo.lua", rDirect, cfgAsp), 0,
    "bare aspect-getter if-condition inert outside aspect_paths")

local srcBareWhile = [[
local icon = GetIcon()
while icon:IsShown() do DoThing() end
]]
assert_eq(#Analyzer.analyze(srcBareWhile, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "bare aspect-getter while-condition flagged")

local srcBareRepeat = [[
local icon = GetIcon()
repeat DoThing() until icon:IsShown()
]]
assert_eq(#Analyzer.analyze(srcBareRepeat, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "bare aspect-getter until-condition flagged")

-- Compound condition: exactly ONE finding (binop path), no double-emit
local srcCompound = [[
local icon = GetIcon()
local ready = IsReady()
if ready and icon:IsShown() then return end
]]
assert_eq(#Analyzer.analyze(srcCompound, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "compound condition emits exactly once")

-- Guard predicates as bare conditions stay clean (not sources)
local srcGuardCond = [[
local v = GetValue()
if IsSecretValue(v) then return end
]]
assert_eq(#Analyzer.analyze(srcGuardCond, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 0,
    "guard call as bare condition not flagged")

print("bare truthiness test passed")

-- Test: protected-call probes are NOT flagged — in expression context
-- pcall/xpcall truncate to the clean ok boolean.
local srcPcallIf = [[
if pcall(C_Spell.GetSpellCastCount, 61304) then return end
]]
assert_eq(#Analyzer.analyze(srcPcallIf, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 0,
    "bare pcall(source) if-condition stays clean")

local srcPcallNot = [[
if not pcall(C_Spell.GetSpellCastCount, 61304) then return end
]]
assert_eq(#Analyzer.analyze(srcPcallNot, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 0,
    "not pcall(source) stays clean")

local srcPcallBinop = [[
local usable = pcall(C_Spell.GetSpellCastCount, 61304) == true
]]
assert_eq(#Analyzer.analyze(srcPcallBinop, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 0,
    "pcall(source) == true comparison stays clean")

-- Protected call in LAST argument position spills every return into the
-- builtin — the secret returns reach it, so this must flag.
local srcPcallSpillBuiltin = [[
print(pcall(C_Spell.GetSpellCastCount, 61304))
]]
assert_eq(#Analyzer.analyze(srcPcallSpillBuiltin, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "pcall(source) spilling into builtin (last arg) flagged")

-- Non-last position truncates to the clean ok boolean.
local srcPcallTruncBuiltin = [[
print(pcall(C_Spell.GetSpellCastCount, 61304), "tail")
]]
assert_eq(#Analyzer.analyze(srcPcallTruncBuiltin, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 0,
    "pcall(source) truncated by non-last builtin position stays clean")

-- Parentheses truncate to one value even in last position.
local srcPcallParens = [[
print((pcall(C_Spell.GetSpellCastCount, 61304)))
]]
assert_eq(#Analyzer.analyze(srcPcallParens, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 0,
    "parenthesized pcall(source) in last position stays clean")

-- Multi-assignment spill still taints: the protected function's returns land
-- in the second local.
local srcPcallSpill = [[
local ok, v = pcall(C_Spell.GetSpellCastCount, 61304)
if v > 0 then return end
]]
assert_eq(#Analyzer.analyze(srcPcallSpill, "QUI_CDM/cdm/foo.lua", rDirect, cfgAsp), 1,
    "pcall multi-assign spill still tainted at comparison")

print("protected-call probe test passed")
end

-- ---------------------------------------------------------------------------
-- Round-6 precondition soundness: prior-clause proofs, compound-else,
-- poisoned aliases, returned/stored callbacks
-- ---------------------------------------------------------------------------
do
local rPre6 = Registry.new()
rPre6:addPreconditionAPI("C_UnitAuras.GetUnitAuras", { "RequiresUnitAuraAccess" })
local function pre(findings)
    local out = {}
    for _, f in ipairs(findings or {}) do
        if f.sink == "<precondition>" then out[#out + 1] = f end
    end
    return out
end

-- elseif after a gate-bearing first clause: reaching it means the gate
-- evaluated FALSE -> unrestricted -> clean (was a false positive).
local src1 = [[
local function scan(unit, mode)
    if C_Secrets.ShouldAurasBeSecret() then
        return nil
    elseif mode == "full" then
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
    return nil
end
return scan
]]
assert_eq(#pre(Analyzer.analyze(src1, "modules/foo.lua", rPre6, cfg)), 0,
    "elseif after positive gate clause is unrestricted-proven")

-- else of a BARE positive gate stays protected (regression guard).
local src2 = [[
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then
        return nil
    else
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
end
return scan
]]
assert_eq(#pre(Analyzer.analyze(src2, "modules/foo.lua", rPre6, cfg)), 0,
    "else of bare positive gate stays protected")

-- else of a COMPOUND `gate() and ready` is restricted-REACHABLE
-- (gate true + ready false) -> flagged (was a false negative).
local src3 = [[
local function scan(unit, ready)
    if C_Secrets.ShouldAurasBeSecret() and ready then
        return nil
    else
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
end
return scan
]]
assert_eq(#pre(Analyzer.analyze(src3, "modules/foo.lua", rPre6, cfg)), 1,
    "else of compound gate-and-flag condition is restricted-reachable")

-- ANY prior gate clause proves later clauses, even with a non-gate first
-- clause: reaching clause 3 / else means the clause-2 gate evaluated false.
local src4 = [[
local function scan(unit, mode)
    if mode == "off" then
        return nil
    elseif C_Secrets.ShouldAurasBeSecret() then
        return nil
    elseif mode == "full" then
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    else
        return C_UnitAuras.GetUnitAuras(unit, "HARMFUL")
    end
end
return scan
]]
assert_eq(#pre(Analyzer.analyze(src4, "modules/foo.lua", rPre6, cfg)), 0,
    "any prior gate-bearing clause protects later clauses and else")

-- Poisoned gate alias: the alias name is rebound elsewhere in the file, so
-- it must not grant protection (round-6: file-scope union suppressed real
-- findings through scope-blind aliases).
local src5 = [[
local isSecret = C_Secrets.ShouldAurasBeSecret
local function other()
    local isSecret = function() return false end
    return isSecret()
end
local function scan(unit)
    if isSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan, other
]]
assert_eq(#pre(Analyzer.analyze(src5, "modules/foo.lua", rPre6, cfg)), 1,
    "rebound gate alias is poisoned and grants no protection")

-- Un-conflicted alias keeps protecting (regression guard for poisoning).
local src6 = [[
local isSecret = C_Secrets.ShouldAurasBeSecret
local function scan(unit)
    if isSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
assert_eq(#pre(Analyzer.analyze(src6, "modules/foo.lua", rPre6, cfg)), 0,
    "un-conflicted gate alias still protects")

-- RETURNED closure escapes the definition-time gate.
local src7 = [[
local function make(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    return function()
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
end
return make
]]
assert_eq(#pre(Analyzer.analyze(src7, "modules/foo.lua", rPre6, cfg)), 1,
    "returned closure does not inherit the definition-time gate")

-- TABLE-STORED closure escapes the definition-time gate.
local src8 = [[
local function make(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    local handlers = {
        scan = function()
            return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
        end,
    }
    return handlers
end
return make
]]
assert_eq(#pre(Analyzer.analyze(src8, "modules/foo.lua", rPre6, cfg)), 1,
    "table-stored closure does not inherit the definition-time gate")

-- ASSIGNED (module-export) closure escapes the definition-time gate.
local src9 = [[
local M = {}
local function setup(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    M.scan = function()
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
end
return setup, M
]]
assert_eq(#pre(Analyzer.analyze(src9, "modules/foo.lua", rPre6, cfg)), 1,
    "assigned closure does not inherit the definition-time gate")

-- Named local function STORED into a table escapes too.
local src10 = [[
local M = {}
local function setup(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    local function scan()
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
    M.scan = scan
end
return setup, M
]]
assert_eq(#pre(Analyzer.analyze(src10, "modules/foo.lua", rPre6, cfg)), 1,
    "stored named callback does not inherit the definition-time gate")

-- Synchronously-called local closure still inherits (regression guard).
local src11 = [[
local function setup(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    local function scan()
        return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
    end
    return scan()
end
return setup
]]
assert_eq(#pre(Analyzer.analyze(src11, "modules/foo.lua", rPre6, cfg)), 0,
    "synchronously-called local function still inherits the gate")

print("round-6 precondition soundness test passed")
end

-- ---------------------------------------------------------------------------
-- Round-6 secret-event detection: RegisterEvent linkage, vararg spill,
-- dispatch-branch overtaint
-- ---------------------------------------------------------------------------
do
local rEvt6 = Registry.new()
rEvt6:addSecretPayloadEvent("UNIT_AURA", { 4 })

-- Single-event frame: handler never compares the event name but the frame
-- registers a secret event -> payload position seeded via linkage.
local srcL1 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    print(updateInfo)
end)
]]
assert_eq(#Analyzer.analyze(srcL1, "modules/foo.lua", rEvt6, cfg), 1,
    "RegisterEvent-linked handler seeded without event-name comparison")

-- Same linkage through a NAMED local handler.
local srcL2 = [[
local f = CreateFrame("Frame")
local function OnEvent(self, event, unit, updateInfo)
    print(updateInfo)
end
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", OnEvent)
]]
assert_eq(#Analyzer.analyze(srcL2, "modules/foo.lua", rEvt6, cfg), 1,
    "RegisterEvent linkage resolves named local handlers")

-- Frame registering only NON-secret events: nothing seeded.
local srcL3 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    print(updateInfo)
end)
]]
assert_eq(#Analyzer.analyze(srcL3, "modules/foo.lua", rEvt6, cfg), 0,
    "non-secret RegisterEvent seeds nothing")

-- Vararg spill: configured position 4 lands in `...`; the spill's second
-- local is tainted, the first (unit, position 3) is not.
local srcL4 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local unit, updateInfo = ...
    print(unit)
    print(updateInfo)
end)
]]
assert_eq(#Analyzer.analyze(srcL4, "modules/foo.lua", rEvt6, cfg), 1,
    "vararg spill taints the configured payload position only")

-- Dispatch overtaint: payload use inside a branch for a DIFFERENT,
-- non-secret event stays clean; the secret-event branch still flags.
local srcL5 = [[
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        print(updateInfo)
    elseif event == "PLAYER_ENTERING_WORLD" then
        print(updateInfo)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcL5, "modules/foo.lua", rEvt6, cfg), 1,
    "non-secret dispatch branch untainted; secret branch still flags")

-- After the dispatch, taint is restored (branch union) — a tail read flags.
-- (RegisterEvent linkage detects the handler; the only comparison is against
-- a non-secret event.)
local srcL6 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "PLAYER_ENTERING_WORLD" then
        print("clean here")
    end
    print(updateInfo)
end)
]]
assert_eq(#Analyzer.analyze(srcL6, "modules/foo.lua", rEvt6, cfg), 1,
    "taint restored after the dispatch branch (union)")

print("round-6 secret-event detection test passed")
end

-- ---------------------------------------------------------------------------
-- Round-6 probe idiom + dispatch-branch spill suppression
-- ---------------------------------------------------------------------------
do
local rP6b = Registry.new()
rP6b:addSource("C_Spell.GetSpellCharges")

-- Safe compound probe: `issecretvalue and issecretvalue(x)` (existence
-- check of the GUARD, then the probe) is the guard idiom — no finding.
local srcG0 = [[
local info = C_Spell.GetSpellCharges(1)
if issecretvalue and issecretvalue(info) then
    info = nil
end
]]
assert_eq(#Analyzer.analyze(srcG0, "modules/foo.lua", rP6b, cfg), 0,
    "guard-existence compound probe idiom not flagged")

-- UNSAFE probe order (round-7): `x and issecretvalue and issecretvalue(x)`
-- truth-tests the possibly-secret local BEFORE probing it — a secret x
-- throws on that truth-test in-game ("attempt to perform boolean test on
-- ..."), the exact case the probe exists to handle. Must flag.
local srcG1 = [[
local info = C_Spell.GetSpellCharges(1)
if info and issecretvalue and issecretvalue(info) then
    info = nil
end
]]
local fG1 = Analyzer.analyze(srcG1, "modules/foo.lua", rP6b, cfg)
assert_eq(#fG1, 1, "truth-test before the probe flags (unsafe probe order)")
assert_eq(fG1[1].sink, "<truthiness>", "probe-order finding is a truthiness sink")
assert(fG1[1].message:find("probe"), "probe-order finding names the probe ordering")

-- An arbitrary extra conjunct disqualifies the probe shape: no guard
-- untaint applies. The leading truth-test of the probed local still flags
-- (same unsafe order as srcG1), and the local stays tainted downstream.
local srcG2 = [[
local info = C_Spell.GetSpellCharges(1)
local other = GetOther()
if info and other and issecretvalue(info) then
    info = nil
end
print(info)
]]
local fG2 = Analyzer.analyze(srcG2, "modules/foo.lua", rP6b, cfg)
assert_eq(#fG2, 2, "probe with unrelated conjunct: probe-order + downstream both flag")
assert_eq(fG2[1].sink, "<truthiness>", "the unsafe probe order is the first finding")
assert_eq(fG2[2].sink, "print", "the downstream sink is the second finding")

-- Value-select idiom (round-7b): `cond and taintedX or fallback` — the `or`
-- truth-tests taintedX's yielded value; a secret throws. Must flag.
local srcG5 = [[
local info = C_Spell.GetSpellCharges(1)
local v = (GetMode() == 1) and info or nil
]]
local fG5 = Analyzer.analyze(srcG5, "modules/foo.lua", rP6b, cfg)
assert_eq(#fG5, 1, "value-select of a tainted local through and/or flags")
assert_eq(fG5[1].sink, "<binop:or>", "value-select finding is the or binop")
assert(fG5[1].message:find("if/else"), "value-select finding suggests if/else")

-- Non-tainted value-select stays clean.
local srcG6 = [[
local v = (GetMode() == 1) and 5 or 3
]]
assert_eq(#Analyzer.analyze(srcG6, "modules/foo.lua", rP6b, cfg), 0,
    "value-select of plain constants not flagged")

-- Round-8: the round-6b defaulting carve-out is GONE. `taintedX or fallback`
-- truth-tests the possibly-secret value at the `or` and a secret throws
-- there (verified live in the 12.1 review — `GetText() or ""` was a shipped
-- crash of exactly this shape). Both the or-test and the downstream sink
-- flag.
local srcG7 = [[
local info = C_Spell.GetSpellCharges(1)
local v = info or 0
print(v)
]]
local fG7 = Analyzer.analyze(srcG7, "modules/foo.lua", rP6b, cfg)
assert_eq(#fG7, 2, "or-default truth-tests the tainted value; sink flags too")
assert_eq(fG7[1].sink, "<truthiness>", "the or-test itself is the first finding")
assert(fG7[1].message:find("probe"), "or-default finding demands a probe")
assert_eq(fG7[2].sink, "print", "the downstream sink is the second finding")

-- Round-7c: probe order fires in VALUE positions too, not just conditions.
local srcG8 = [[
local info = C_Spell.GetSpellCharges(1)
local ok = info and issecretvalue and issecretvalue(info)
]]
local fG8 = Analyzer.analyze(srcG8, "modules/foo.lua", rP6b, cfg)
assert_eq(#fG8, 1, "value-position probe order flags (assignment RHS)")
assert_eq(fG8[1].sink, "<truthiness>", "value-position probe-order is a truthiness sink")

-- Round-7c: dotted refs — `t.f and issecretvalue(t.f)` truth-tests the
-- possibly-secret field before probing it.
local srcG9 = [[
local info = C_Spell.GetSpellCharges(1)
if info.isActive and issecretvalue(info.isActive) then
    return
end
]]
local fG9 = Analyzer.analyze(srcG9, "modules/foo.lua", rP6b, cfg)
assert_eq(#fG9, 1, "dotted-ref probe order flags")
assert_eq(fG9[1].sink, "<truthiness>", "dotted probe-order is a truthiness sink")

-- Round-7c: disjunct form — `not info or issecretvalue(info)` truth-tests
-- info first. The existing unop rule also fires on `not <tainted>`, so the
-- same defect surfaces through both lenses.
local srcG10 = [[
local info = C_Spell.GetSpellCharges(1)
if not info or issecretvalue(info) then
    return
end
]]
local fG10 = Analyzer.analyze(srcG10, "modules/foo.lua", rP6b, cfg)
assert_eq(#fG10, 2, "disjunct (not x or probe(x)) probe order flags (unop + probe-order)")
assert_eq(fG10[1].sink, "<unop:not>", "unop rule fires on the not-test (sink walk runs first since round-8)")
assert_eq(fG10[2].sink, "<truthiness>", "disjunct probe-order is a truthiness sink")

-- Round-7d: nested cross-operator chains. Lua evaluates boolean chains
-- strictly left-to-right regardless of and/or mixing, so a ref truth-tested
-- inside an earlier SUB-chain still precedes a later guard call (and vice
-- versa for a guard call inside a later sub-chain).
local srcN1 = [[
local info = C_Spell.GetSpellCharges(1)
if info and (issecretvalue(info) or IsFallback()) then
    return
end
]]
local fN1x = Analyzer.analyze(srcN1, "modules/foo.lua", rP6b, cfg)
assert_eq(#fN1x, 1, "guard call nested in a later or-subchain still flags")
assert_eq(fN1x[1].sink, "<truthiness>", "nested-guard probe-order is a truthiness sink")

local srcN2 = [[
local info = C_Spell.GetSpellCharges(1)
if (info or GetBackup()) and issecretvalue(info) then
    return
end
]]
local fN2x = Analyzer.analyze(srcN2, "modules/foo.lua", rP6b, cfg)
assert_eq(#fN2x, 1, "ref truth-tested in an earlier or-subchain still flags")
assert_eq(fN2x[1].sink, "<truthiness>", "nested-ref probe-order is a truthiness sink")

-- Guard-first stays clean even with the probed ref used in a later subchain.
local srcN3 = [[
local info = C_Spell.GetSpellCharges(1)
if issecretvalue(info) or (info and DoThing()) then
    return
end
]]
assert_eq(#Analyzer.analyze(srcN3, "modules/foo.lua", rP6b, cfg), 0,
    "guard-first with later subchain use not flagged")

-- Round-7e: path sensitivity — guard-dominated truth-tests are SAFE and
-- must not flag. A later and/or position only executes when every earlier
-- operand resolved the way the chain needs (and→truthy, or→falsy), so a
-- probe with that polarity proves the ref non-secret at the later test.
-- The canonical SAFE unwrap idiom (`not probe(x) and x or default`):
local srcPS1 = [[
local info = C_Spell.GetSpellCharges(1)
local v = not issecretvalue(info) and info or nil
]]
assert_eq(#Analyzer.analyze(srcPS1, "modules/foo.lua", rP6b, cfg), 0,
    "safe unwrap (not probe(x) and x or default) not flagged")

-- Guard-dominated re-probe in an and-chain:
local srcPS2 = [[
local info = C_Spell.GetSpellCharges(1)
if not issecretvalue(info) and info and issecretvalue(info) then
    return
end
]]
assert_eq(#Analyzer.analyze(srcPS2, "modules/foo.lua", rP6b, cfg), 0,
    "and-chain truth-test dominated by not-probe not flagged")

-- Or-falsy domination: reaching the second disjunct means the probe
-- returned false (non-secret), so the inner truth-test is safe.
local srcPS3 = [[
local info = C_Spell.GetSpellCharges(1)
if issecretvalue(info) or (info and issecretvalue(info)) then
    return
end
]]
assert_eq(#Analyzer.analyze(srcPS3, "modules/foo.lua", rP6b, cfg), 0,
    "or-chain truth-test dominated by a falsy probe not flagged")

-- Probe-order also fires inside call ARGUMENTS (chains self-test there).
local srcPS4 = [[
local info = C_Spell.GetSpellCharges(1)
UseIt(info and issecretvalue(info))
]]
local fP4x = Analyzer.analyze(srcPS4, "modules/foo.lua", rP6b, cfg)
assert_eq(#fP4x, 1, "probe-order inside a call argument flags")
assert_eq(fP4x[1].sink, "<truthiness>", "call-arg probe-order is a truthiness sink")

-- Round-7f: proofs are SCOPED to the subtree they dominate — a proof
-- harvested inside one branch must not leak into sibling branches of an
-- ancestor. Reaching the second disjunct here means the guarded first
-- disjunct was FALSY (info may be secret), so `info and` can throw.
local srcPS5 = [[
local info = C_Spell.GetSpellCharges(1)
if (not issecretvalue(info) and Use(info)) or (info and issecretvalue(info)) then
    return
end
]]
local fPS5 = Analyzer.analyze(srcPS5, "modules/foo.lua", rP6b, cfg)
assert_eq(#fPS5, 1, "proof from a sibling or-branch does not suppress (leak fixed)")
assert_eq(fPS5[1].sink, "<truthiness>", "leaked-proof case is a truthiness sink")

-- Truthy(or) proves nothing: reaching the and-Rhs here can mean the probe
-- returned TRUE (info IS secret), so the inner test still flags.
local srcPS6 = [[
local info = C_Spell.GetSpellCharges(1)
if (issecretvalue(info) or Skip()) and (info and issecretvalue(info)) then
    return
end
]]
assert_eq(#Analyzer.analyze(srcPS6, "modules/foo.lua", rP6b, cfg), 1,
    "truthy or-chain lhs proves nothing; inner test flags")

-- Control: a proof that legitimately EXTENDS past its subtree is re-derived
-- by the ancestor's own collection and still suppresses.
local srcPS7 = [[
local info = C_Spell.GetSpellCharges(1)
if (not issecretvalue(info) and info) and issecretvalue(info) then
    return
end
]]
assert_eq(#Analyzer.analyze(srcPS7, "modules/foo.lua", rP6b, cfg), 0,
    "proof extending through nested and-chain still suppresses")

-- Round-7g: a truth-test running under an active safe-proof must not mark
-- the ref as tested for later SIBLING guards — the test executes only on
-- paths where the probe already said non-secret.
local srcPS8 = [[
local info = C_Spell.GetSpellCharges(1)
if (not issecretvalue(info) and info) or (issecretvalue(info) and Other()) then
    return
end
]]
assert_eq(#Analyzer.analyze(srcPS8, "modules/foo.lua", rP6b, cfg), 0,
    "guard-dominated test does not poison a sibling-branch guard (rollback FP fixed)")

-- Round-7g: wrong-polarity domination — the test executes exactly on paths
-- where the probe proved the value SECRET; certain throw. Both forms.
local srcPS9 = [[
local info = C_Spell.GetSpellCharges(1)
if issecretvalue(info) and info then
    return
end
]]
local fPS9 = Analyzer.analyze(srcPS9, "modules/foo.lua", rP6b, cfg)
assert_eq(#fPS9, 1, "truth-test under a truthy probe (proved secret) flags")
assert(fPS9[1].message:find("probe polarity"), "wrong-polarity finding names the polarity")

local srcPS10 = [[
local info = C_Spell.GetSpellCharges(1)
if not issecretvalue(info) or info then
    return
end
]]
assert_eq(#Analyzer.analyze(srcPS10, "modules/foo.lua", rP6b, cfg), 1,
    "inverted safe-or-use idiom (not probe(x) or x) flags")

-- Tail honesty: in VALUE position the chain tail is never truth-tested —
-- `v = issecretvalue(x) and x` assigns the secret without testing it.
local srcPS11 = [[
local info = C_Spell.GetSpellCharges(1)
local v = issecretvalue(info) and info
]]
assert_eq(#Analyzer.analyze(srcPS11, "modules/foo.lua", rP6b, cfg), 0,
    "secret yield into an assignment (untested tail) not flagged")

-- Infeasible path: safe-proof and secret-proof both active means the test
-- never executes; safe-proof wins and nothing emits.
local srcPS12 = [[
local info = C_Spell.GetSpellCharges(1)
if (Use(info) and issecretvalue(info)) and (issecretvalue(info) or info) then
    return
end
]]
assert_eq(#Analyzer.analyze(srcPS12, "modules/foo.lua", rP6b, cfg), 0,
    "infeasible (safe+secret dominated) test not flagged")

-- Round-7h: probe-order coverage in remaining value contexts — chains
-- self-test inside table constructors, index expressions, non-Var LHS
-- assignments, extra RHS expressions, and loop headers.
local srcVC = {
    { [[
local info = C_Spell.GetSpellCharges(1)
local t = { info and issecretvalue(info) }
]], 1, "table constructor entry" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local v = T[info and issecretvalue(info)]
]], 1, "index expression" },
    { [[
local info = C_Spell.GetSpellCharges(1)
T.field = info and issecretvalue(info)
]], 1, "member-LHS assignment RHS" },
    { [[
local info = C_Spell.GetSpellCharges(1)
T[1] = info and issecretvalue(info)
]], 1, "index-LHS assignment RHS (was silently skipped)" },
    { [[
local info = C_Spell.GetSpellCharges(1)
for k in Iter(info and issecretvalue(info)) do end
]], 1, "generic-for iterator expression" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local t = { issecretvalue(info) and info }
]], 0, "constructor value with untested tail stays clean" },
}
for _, tc in ipairs(srcVC) do
    local fs = Analyzer.analyze(tc[1], "modules/foo.lua", rP6b, cfg)
    local got = 0
    for _, f in ipairs(fs) do
        if f.message:find("probe first") or f.message:find("probe polarity") then
            got = got + 1
        end
    end
    assert_eq(got, tc[2], "value-context coverage: " .. tc[3])
end

-- Round-7i: remaining expression positions — call bases (function-select),
-- call sugar, non-`not` unop operands, complex member bases, chain args to
-- the guard itself, and closure bodies.
local srcVC2 = {
    { [[
local info = C_Spell.GetSpellCharges(1)
local v = (info and issecretvalue(info) and A or B)(1)
]], 1, "call base chain (function-select idiom)" },
    { [[
local info = C_Spell.GetSpellCharges(1)
Foo{ info and issecretvalue(info) }
]], 1, "table-call sugar argument" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local v = #(GetList(info and issecretvalue(info)))
]], 1, "length-unop operand" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local v = (info and issecretvalue(info) and T or U).field
]], 1, "complex member base" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local f = function() return info and issecretvalue(info) end
]], 1, "closure body (captured upvalue)" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local v = (issecretvalue(info) and info)(1)
]], 0, "call base with untested tail stays clean" },
}
for _, tc in ipairs(srcVC2) do
    local fs = Analyzer.analyze(tc[1], "modules/foo.lua", rP6b, cfg)
    local got = 0
    for _, f in ipairs(fs) do
        if f.message:find("probe first") or f.message:find("probe polarity") then
            got = got + 1
        end
    end
    assert_eq(got, tc[2], "expression-position coverage: " .. tc[3])
end

-- Round-7j: KEYED refs (`t[1]`, `t["f"]`, `t[k]`) participate in probe-order,
-- wrong-polarity, and proof suppression exactly like bare/dotted refs.
local srcKR = {
    { [[
local info = C_Spell.GetSpellCharges(1)
if info[1] and issecretvalue(info[1]) then return end
]], 1, "keyed probe order flags" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local k = GetKey()
if info[k] and issecretvalue(info[k]) then return end
]], 1, "variable-keyed probe order flags" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local v = not issecretvalue(info[1]) and info[1] or nil
]], 0, "keyed safe unwrap not flagged" },
    { [[
local info = C_Spell.GetSpellCharges(1)
if issecretvalue(info[1]) and info[1] then return end
]], 1, "keyed wrong-polarity flags" },
    { [[
local info = C_Spell.GetSpellCharges(1)
if info[1] and issecretvalue(info[2]) then return end
]], 1, "distinct keys never collide as probe-order; the unprobed info[1] truth-test flags on its own (round-8)" },
}
for _, tc in ipairs(srcKR) do
    local fs = Analyzer.analyze(tc[1], "modules/foo.lua", rP6b, cfg)
    local got = 0
    for _, f in ipairs(fs) do
        if f.message:find("probe first") or f.message:find("probe polarity") then
            got = got + 1
        end
    end
    assert_eq(got, tc[2], "keyed-ref coverage: " .. tc[3])
end

-- Round-7k: keyed-reference IDENTITY — equivalent spellings unify, mutable
-- (variable-indexed) keys are volatile across impure calls.
local srcKI = {
    { [[
local info = C_Spell.GetSpellCharges(1)
if info.f and issecretvalue(info["f"]) then return end
]], 1, 'identifier string key unifies with dot access (t["f"] == t.f)' },
    { [[
local info = C_Spell.GetSpellCharges(1)
if info[1] and issecretvalue(info[1.0]) then return end
]], 1, "number literals canonicalize (1 == 1.0)" },
    { [[
local info = C_Spell.GetSpellCharges(1)
if info[1] and issecretvalue(info["1"]) then return end
]], 1, 'number key stays distinct from string key (t[1] ~= t["1"]) — no probe-order collision, but the unprobed info[1] truth-test flags (round-8)' },
    { [[
local info = C_Spell.GetSpellCharges(1)
local k = GetKey()
if info[k] and Foo() and issecretvalue(info[k]) then return end
]], 0, "volatile key purged by an intervening impure call (k may rebind)" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local k = GetKey()
if issecretvalue(info[k]) and Foo() and info[k] then return end
]], 0, "volatile secret-proof filtered across an impure call" },
    { [[
local info = C_Spell.GetSpellCharges(1)
if info.f and Foo() and issecretvalue(info.f) then return end
]], 1, "literal/dotted keys survive calls (heap approximation, unchanged)" },
    { [[
local info = C_Spell.GetSpellCharges(1)
if info[9e999] and Foo() and issecretvalue(info[9e999]) then return end
]], 1, "identifier-looking canonical literals (tostring(inf)) stay non-volatile" },
    { [[
local info = C_Spell.GetSpellCharges(1)
local j, k = J(), K()
if info[j][k] and Foo() and issecretvalue(info[j][k]) then return end
]], 0, "nested variable-indexed chains stay volatile (single marker)" },
}
for _, tc in ipairs(srcKI) do
    local fs = Analyzer.analyze(tc[1], "modules/foo.lua", rP6b, cfg)
    local got = 0
    for _, f in ipairs(fs) do
        if f.message:find("probe first") or f.message:find("probe polarity") then
            got = got + 1
        end
    end
    assert_eq(got, tc[2], "keyed identity: " .. tc[3])
end

local rEvt6b = Registry.new()
rEvt6b:addSecretPayloadEvent("UNIT_AURA", { 3, 4 })

-- Vararg spill inside an or-chained dispatch branch for OTHER events stays
-- clean; a spill outside any proving branch still flags.
local srcG3 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit == "player" then print("ok") end
    end
end)
]]
assert_eq(#Analyzer.analyze(srcG3, "modules/foo.lua", rEvt6b, cfg), 0,
    "spill inside or-chained non-secret dispatch branch stays clean")

local srcG4 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local unit = ...
    if unit == "player" then print("ok") end
end)
]]
assert_eq(#Analyzer.analyze(srcG4, "modules/foo.lua", rEvt6b, cfg), 1,
    "spill outside a proving branch still flags")

print("round-6 probe idiom + spill suppression test passed")
end

-- RegisterUnitEvent links handlers the same way as RegisterEvent.
do
local rEvt6c = Registry.new()
rEvt6c:addSecretPayloadEvent("UNIT_AURA", { 4 })
local srcRU = [[
local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_AURA", "player", "target")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    print(updateInfo)
end)
]]
assert_eq(#Analyzer.analyze(srcRU, "modules/foo.lua", rEvt6c, cfg), 1,
    "RegisterUnitEvent linkage seeds the handler")
print("round-6 RegisterUnitEvent linkage test passed")
end

-- ---------------------------------------------------------------------------
-- Round-6b false-negative fixes: independent re-taint vs dispatch untaint,
-- assignment-statement vararg spill, select() extraction
-- ---------------------------------------------------------------------------
do
local r6b = Registry.new()
r6b:addSecretPayloadEvent("UNIT_AURA", { 3, 4 })
r6b:addSource("C_UnitAuras.GetUnitAuras")

-- A payload param re-tainted from an INDEPENDENT source must survive the
-- non-secret dispatch untaint.
local srcFN1 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
    if event == "PLAYER_ENTERING_WORLD" then
        print(updateInfo)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcFN1, "modules/foo.lua", r6b, cfg), 1,
    "independent re-taint survives the dispatch-branch untaint")

-- `...` spill through a plain (non-local) assignment taints like the
-- LocalStatement spill.
local srcFN2 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local unit, updateInfo
    unit, updateInfo = ...
    print(updateInfo)
end)
]]
assert_eq(#Analyzer.analyze(srcFN2, "modules/foo.lua", r6b, cfg), 1,
    "assignment-statement vararg spill taints configured positions")

-- select(k, ...) extracts secret vararg positions.
local srcFN3 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local updateInfo = select(2, ...)
    print(updateInfo)
end)
]]
assert_eq(#Analyzer.analyze(srcFN3, "modules/foo.lua", r6b, cfg), 1,
    "select() over secret vararg positions taints the result")

-- select below every secret position stays clean.
local srcFN4 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local extra = select(3, ...)
    print(extra)
end)
]]
assert_eq(#Analyzer.analyze(srcFN4, "modules/foo.lua", r6b, cfg), 0,
    "select() past every secret position stays clean")

-- select('#', ...) is a count, not a value read.
local srcFN5 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local n = select("#", ...)
    print(n)
end)
]]
assert_eq(#Analyzer.analyze(srcFN5, "modules/foo.lua", r6b, cfg), 0,
    "select('#', ...) stays clean")

-- Bare `...` handed to an unsafe builtin leaks the payload.
local srcFN6 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    print(...)
end)
]]
assert_eq(#Analyzer.analyze(srcFN6, "modules/foo.lua", r6b, cfg), 1,
    "bare vararg into an unsafe builtin flags")

-- Regression guards: pure event taint still untaints in non-secret dispatch
-- branches, for named params and assignment spills alike.
local srcFN7 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "PLAYER_ENTERING_WORLD" then
        print(updateInfo)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcFN7, "modules/foo.lua", r6b, cfg), 0,
    "pure event taint still untainted in non-secret dispatch branch")

local srcFN8 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local unit, updateInfo
        unit, updateInfo = ...
        print(updateInfo)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcFN8, "modules/foo.lua", r6b, cfg), 0,
    "assignment spill suppressed inside non-secret dispatch branch")

print("round-6b false-negative fix test passed")
end

-- ---------------------------------------------------------------------------
-- Round-6b false-positive fixes: receiver identity, dynamic select,
-- existence-test idioms, do-block coverage
-- ---------------------------------------------------------------------------
do
local rFp = Registry.new()
rFp:addSecretPayloadEvent("UNIT_AURA", { 3, 4 })

-- Same-named receivers in sibling scopes do not cross-seed.
local srcS1 = [[
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(self, event, unit, updateInfo) end)
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, isLogin)
        if isLogin then print("login") end
    end)
end
]]
assert_eq(#Analyzer.analyze(srcS1, "modules/foo.lua", rFp, cfg), 0,
    "shadowed same-name receivers do not cross-seed")

-- A REBOUND receiver drops the old frame's registrations.
local srcS2 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo) end)
f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, isLogin)
    if isLogin then print("login") end
end)
]]
assert_eq(#Analyzer.analyze(srcS2, "modules/foo.lua", rFp, cfg), 0,
    "rebound receiver does not inherit prior registrations")

-- do-block bodies are walked (previously a total blind spot): linkage AND
-- taint rules apply inside them.
local srcS3 = [[
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(self, event, unit, updateInfo)
        print(updateInfo)
    end)
end
]]
assert_eq(#Analyzer.analyze(srcS3, "modules/foo.lua", rFp, cfg), 1,
    "do-block bodies are taint-walked (handler seeded and flagged)")

-- Dynamic-k select loop: call sites clean, the RESULT carries the taint.
local srcS4 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        print(v)
    end
end)
]]
local fS4 = Analyzer.analyze(srcS4, "modules/foo.lua", rFp, cfg)
assert_eq(#fS4, 1, "dynamic select loop: one finding (the print), not per select site")
assert_eq(fS4[1].sink, "print", "the surviving finding is the actual sink")

local rIdiom = Registry.new()
rIdiom:addSource("C_Spell.GetSpellCharges")
rIdiom:addSource("C_Spell.GetSpellCooldown")

-- `x and x.f` struct guard feeding an unwrap arg: the unwrap review finding
-- plus (round-8) the truth-test of the possibly-secret ref itself.  Real
-- table-or-nil API structs suppress the latter with `-- @secret-safe:`.
local srcS5 = [[
local chargeInfo = C_Spell.GetSpellCharges(1)
local cur = SafeToNumber(chargeInfo and chargeInfo.currentCharges, 0)
]]
local rIdiomU = Registry.new()
rIdiomU:addSource("C_Spell.GetSpellCharges")
rIdiomU:addUnwrap("SafeToNumber")
assert_eq(#Analyzer.analyze(srcS5, "modules/foo.lua", rIdiomU, cfg), 2,
    "struct guard into unwrap: unwrap review finding + tainted truth-test")

-- `x and Decode(x.f)` guard-before-use: the truth-test flags (round-8);
-- documented table-or-nil containers annotate.
local srcS6 = [[
local chargeInfo = C_Spell.GetSpellCharges(1)
local active = chargeInfo and Decode(chargeInfo.isActive)
]]
assert_eq(#Analyzer.analyze(srcS6, "modules/foo.lua", rIdiom, cfg), 1,
    "guard-before-call idiom flags the possibly-secret truth-test")

-- `Source() or DEFAULT` fallback truth-tests the direct source result at the
-- `or`, then the selected result remains tainted downstream.
local srcS7 = [[
local cdInfo = C_Spell.GetSpellCooldown(1) or DEFAULT
local d = cdInfo.duration + 1
]]
local fS7 = Analyzer.analyze(srcS7, "modules/foo.lua", rIdiom, cfg)
assert_eq(#fS7, 2, "source-or-default: truth-test and downstream arith both flag")
assert_eq(fS7[1].sink, "<binop:or>", "source result truth-test caught")
assert_eq(fS7[2].sink, "<arith>", "downstream arith still caught")

-- `C_X.Fn and C_X.Fn(id)` API-existence guard: no binop emission, result
-- still tainted downstream.
local srcS8 = [[
local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(1)
local d = cdInfo.duration + 1
]]
local fS8 = Analyzer.analyze(srcS8, "modules/foo.lua", rIdiom, cfg)
assert_eq(#fS8, 1, "existence-guarded source call: only the downstream arith flags")

-- Regression: unrelated conjunct with a source call still emits.
local srcS9 = [[
local ready = IsReady()
local x = ready and C_Spell.GetSpellCharges(1)
if x then return end
]]
assert(#Analyzer.analyze(srcS9, "modules/foo.lua", rIdiom, cfg) >= 1,
    "non-guard conjunct with source still emits")

print("round-6b false-positive fix test passed")
end

-- ---------------------------------------------------------------------------
-- Round-6c: value flow through and/or, payload-copy dispatch untaint
-- ---------------------------------------------------------------------------
do
local r6c = Registry.new()
r6c:addSource("C_Spell.GetSpellCharges")

-- Guard-shape into an unsafe builtin: the YIELDED field is tainted.
local srcV1 = [[
local info = C_Spell.GetSpellCharges(1)
print(info and info.currentCharges)
]]
assert_eq(#Analyzer.analyze(srcV1, "modules/foo.lua", r6c, cfg), 2,
    "guard-shape into unsafe builtin flags value flow + truth-test (round-8)")

-- Guard-shape assignment keeps the taint on the target.
local srcV2 = [[
local info = C_Spell.GetSpellCharges(1)
local cur = info and info.currentCharges
print(cur)
]]
assert_eq(#Analyzer.analyze(srcV2, "modules/foo.lua", r6c, cfg), 2,
    "guard-shape assignment propagates taint; the and-test also flags (round-8)")

-- Comparison through the guard shape flags.
local srcV3 = [[
local info = C_Spell.GetSpellCharges(1)
if (info and info.currentCharges) > 0 then return end
]]
assert_eq(#Analyzer.analyze(srcV3, "modules/foo.lua", r6c, cfg), 2,
    "comparison over guard shape flags, plus the and-test (round-8)")

-- `x and DecodeHelper(x.f)`: a falsy SECRET x is yielded by the and (the
-- index never evaluates on that path), so the decoded target stays tainted —
-- round-6d superseded the earlier struct-assertion shortcut; table-or-nil
-- API contracts use `-- @secret-safe:` instead.
local srcV4 = [[
local info = C_Spell.GetSpellCharges(1)
local active = info and Decode(info.isActive)
if active == true then return end
]]
assert_eq(#Analyzer.analyze(srcV4, "modules/foo.lua", r6c, cfg), 2,
    "decode-helper guard flags the comparison AND the and-test (round-8)")

-- Truthy tainted lhs flows through `or`.
local srcV5 = [[
local count = C_Spell.GetSpellCharges(1)
local n = count or 0
print(n)
]]
assert_eq(#Analyzer.analyze(srcV5, "modules/foo.lua", r6c, cfg), 2,
    "or-lhs taint flows to the target; the or-test itself also flags (round-8)")

local rEvt6c2 = Registry.new()
rEvt6c2:addSecretPayloadEvent("UNIT_AURA", { 3, 4 })
rEvt6c2:addSource("C_UnitAuras.GetUnitAuras")

-- Payload COPIES join the dispatch untaint set (round-6c FP fix)...
local srcV6 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local u = unit
    if event == "PLAYER_ENTERING_WORLD" then
        print(u)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcV6, "modules/foo.lua", rEvt6c2, cfg), 0,
    "payload copy untaints in non-secret dispatch branch")

-- ...including param-to-param copies...
local srcV7 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    unit = updateInfo
    if event == "PLAYER_ENTERING_WORLD" then
        print(unit)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcV7, "modules/foo.lua", rEvt6c2, cfg), 0,
    "param-to-param copy stays event taint, untaints in dispatch branch")

-- ...while copies still flag OUTSIDE proving branches...
local srcV8 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local u = unit
    print(u)
end)
]]
assert_eq(#Analyzer.analyze(srcV8, "modules/foo.lua", rEvt6c2, cfg), 1,
    "payload copy still flags outside a proving branch")

-- ...and INDEPENDENT re-taint still survives the dispatch untaint.
local srcV9 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
    if event == "PLAYER_ENTERING_WORLD" then
        print(updateInfo)
    end
end)
]]
assert_eq(#Analyzer.analyze(srcV9, "modules/foo.lua", rEvt6c2, cfg), 1,
    "independent source re-taint survives dispatch untaint")

print("round-6c value-flow + payload-copy test passed")
end

-- ---------------------------------------------------------------------------
-- Round-6d: sound and-falsy value flow (secret-false yields), struct
-- assertions, plain-ref existence emissions
-- ---------------------------------------------------------------------------
do
local r6d = Registry.new()
r6d:addSource("C_Spell.GetFlag")

-- A falsy secret lhs IS the yield of `and` — taint must flow.
local srcD1 = [[
local isActive = C_Spell.GetFlag(1)
local v = isActive and 1
print(v)
]]
assert_eq(#Analyzer.analyze(srcD1, "modules/foo.lua", r6d, cfg), 2,
    "and-falsy secret yield flows to the sink; the and-test also flags (round-8)")

-- Same through a non-indexing call rhs (`x and Wrap(x)`).
local srcD2 = [[
local isActive = C_Spell.GetFlag(1)
local v = isActive and Wrap(isActive)
print(v)
]]
assert_eq(#Analyzer.analyze(srcD2, "modules/foo.lua", r6d, cfg), 2,
    "and-falsy yield flows through non-indexing call rhs; and-test flags too (round-8)")

-- ...and through the a-and-b-or-c ternary idiom.
local srcD3 = [[
local isActive = C_Spell.GetFlag(1)
print(isActive and 1 or 0)
]]
assert_eq(#Analyzer.analyze(srcD3, "modules/foo.lua", r6d, cfg), 2,
    "ternary idiom over secret flag flows to the sink; and-test flags too (round-8)")

-- The decode idiom is NOT type-provable: `info and Decode(info.isActive)` —
-- the index inside Decode's argument only evaluates when info is TRUTHY, so
-- a secret-false info short-circuits past it and IS the yield. The
-- comparison must flag; genuinely table-or-nil API structs carry a
-- `-- @secret-safe:` annotation instead (round-6d follow-up: the struct-
-- assertion shortcut was itself a reproducible false negative).
-- Round-8: the `info and` truth-test ITSELF also flags now — a secret info
-- throws right there, before the comparison is ever reached.
local srcD4 = [[
local info = C_Spell.GetFlag(1)
local v = info and Decode(info.isActive)
if v == true then return end
]]
local fD4 = Analyzer.analyze(srcD4, "modules/foo.lua", r6d, cfg)
assert_eq(#fD4, 2, "decode idiom flags the truth-test AND the comparison consumer")
assert_eq(fD4[1].sink, "<truthiness>", "the and-test of the tainted local flags (round-8)")
assert_eq(fD4[2].sink, "<comparison>", "the comparison consumer still flags")

-- Same through a 3-term chain: the tainted ref's truth-test flags once (the
-- untainted `cached` conjunct does not), plus the consumer.
local srcD5 = [[
local cached = IsCached()
local info = C_Spell.GetFlag(1)
local v = cached and info and Decode(info.isActive)
if v == true then return end
]]
local fD5 = Analyzer.analyze(srcD5, "modules/foo.lua", r6d, cfg)
assert_eq(#fD5, 2, "3-term chain: truth-test + consumer, one finding each")
assert_eq(fD5[1].sink, "<truthiness>", "3-term chain flags the tainted truth-test")
assert_eq(fD5[2].sink, "<comparison>", "3-term chain flags the comparison")

-- The @secret-safe annotation is the sanctioned suppression for
-- API-contract table-or-nil structs — one per flagged line.
local srcD6 = [[
local info = C_Spell.GetFlag(1)
local v = info and Decode(info.isActive) -- @secret-safe: GetFlag returns table-or-nil per docs
if v == true then return end -- @secret-safe: GetFlag returns table-or-nil per docs
]]
assert_eq(#Analyzer.analyze(srcD6, "modules/foo.lua", r6d, cfg), 0,
    "@secret-safe annotation suppresses the contract-safe decode site")

print("round-6d and-falsy value-flow test passed")
end

-- ---------------------------------------------------------------------------
-- Round-8 (2026-07 external 12.1 review): unproven truth-tests of tainted
-- refs in and/or chains EMIT; guard bail idioms and gate dominance untaint;
-- gate proofs are scoped to payload-derived (aura-class) taint; guard
-- aliases resolve with poisoning.
-- ---------------------------------------------------------------------------
do
local r8 = Registry.new()
r8:addSecretPayloadEvent("UNIT_AURA", { 3, 4 })
r8:addSource("C_Spell.GetSpellCharges")
r8:addRestrictionGate("AurasAreSecret")

-- THE review repro: `if updateInfo and updateInfo.isFullUpdate` with a
-- configured secret payload produced NO finding (round-6b plain-ref
-- exemption). It must flag: a secret updateInfo throws on the and-test.
local srcR1 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
local fR1 = Analyzer.analyze(srcR1, "modules/foo.lua", r8, cfg)
assert_eq(#fR1, 1, "review repro: payload truth-test chain flags")
assert_eq(fR1[1].sink, "<truthiness>", "review repro finding is a truthiness sink")
assert(fR1[1].message:find("probe first"), "review repro demands an unconditional probe")

-- The shipped FIX idiom stays clean: probe-bail, then use.  Requires the
-- round-8 terminator-aware untaint (the bail branch never reaches post-if;
-- the fall-through means the guard was false).
local srcR2 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsSecretValue(updateInfo) then return end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR2, "modules/foo.lua", r8, cfg), 0,
    "probe-bail idiom analyzes clean (terminator-aware guard untaint)")

-- error() is a terminator too: probe-bail via error() analyzes clean.
local srcR2e = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsSecretValue(updateInfo) then error("secret payload") end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR2e, "modules/foo.lua", r8, cfg), 0,
    "error() bail is a terminator (guard untaint)")

-- ...but a chunk that SHADOWS `error` forfeits the terminator: the rebound
-- call may return normally, so the bail branch can fall through with the
-- guard proven TRUE — the post-if truth-test must still flag.
local srcR2f = [[
local error = Log.error
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsSecretValue(updateInfo) then error("secret payload") end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
local fR2f = Analyzer.analyze(srcR2f, "modules/foo.lua", r8, cfg)
assert_eq(#fR2f, 1, "shadowed error() is no terminator — truth-test flags")
assert_eq(fR2f[1].sink, "<truthiness>", "shadowed-error finding is a truthiness sink")

-- Parameter shadow counts too (chunk-wide union, scoping not modeled).
local srcR2g = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
local function report(error) DoSomething(error) end
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsSecretValue(updateInfo) then error("secret payload") end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR2g, "modules/foo.lua", r8, cfg), 1,
    "parameter named error also forfeits the terminator")

-- Global-environment rebinds evade bare-name binders but rebind the bare
-- error() call all the same — every shape forfeits the terminator.
local envShadowPreludes = {
    ["_G member write"]      = [[_G.error = Log.error]],
    ["_G string index"]      = [[_G["error"] = Log.error]],
    ["_G dynamic index"]     = [[local k = GetKey() _G[k] = Log.error]],
    ["rawset on _G"]         = [[rawset(_G, "error", Log.error)]],
    ["write via _G alias"]   = [[local g = _G g.error = Log.error]],
    ["write via getfenv()"]  = [[getfenv().error = Log.error]],
    ["setfenv call"]         = [[setfenv(1, setmetatable({}, { __index = _G }))]],
    ["_G function decl"]     = [[function _G.error(msg) Report(msg) end]],
    ["alias function decl"]  = [[local g = _G function g.error(msg) Report(msg) end]],
    ["local function decl"]  = [[local function error(msg) Report(msg) end]],
    ["localized _G re-export"] = [[local _G = _G _G.error = Log.error]],
    -- NOTE `local _G = {} local _G = _G _G.error = f` stays CLEAN: the
    -- second init lexically reads the FIRST local (the plain table), so the
    -- global env is never reachable — distinct binder identities get this
    -- right where name-keying could not.
    ["shadow scope ends, env write follows"] =
        [[do local _G = {} end _G.error = Log.error]],
}
for label, prelude in pairs(envShadowPreludes) do
    local src = prelude .. [[

local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsSecretValue(updateInfo) then error("secret payload") end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
    assert_eq(#Analyzer.analyze(src, "modules/foo.lua", r8, cfg), 1,
        label .. " forfeits the error() terminator")
end

-- Non-env dotted writes are a module logger DEFINITION, not a rebind of the
-- bare global — the terminator (and the clean bail) must survive them, in
-- both the assignment and the function-declaration form.
local srcR2h = [[
local M = {}
M.error = function(msg) Report(msg) end
function M.error(msg) Report(msg) end
do
    -- A local SHADOWING _G is a plain table — variable identity, not the
    -- name, decides env-ness (review round: this was a false positive).
    local _G = {}
    function _G.error(msg) Report(msg) end
    _G["error"] = M.error
end
-- Same-scope redeclaration: each binder is a DISTINCT variable (review
-- round: parser CreateLocal used to reuse the same-name object, so the
-- env-ness of the first binder leaked onto the second).
local _G = _G
local _G = {}
_G.error = M.error
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsSecretValue(updateInfo) then error("secret payload") end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR2h, "modules/foo.lua", r8, cfg), 0,
    "module-table .error definition keeps the terminator")

-- Guard-clause falsity also protects elseif/else clauses, not just a bare
-- else: reaching them means the probe returned false.
local srcR3 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsSecretValue(updateInfo) then
        Bail()
    elseif updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR3, "modules/foo.lua", r8, cfg), 0,
    "guard falsity protects subsequent clauses")

-- Restriction-gate bail unrestricts the payload class for following code.
local srcR4 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR4, "modules/foo.lua", r8, cfg), 0,
    "gate bail idiom unrestricts payload taint post-if")

-- `if not gate() then <body>` — the body runs unrestricted.
local srcR5 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if not AurasAreSecret() then
        if updateInfo and updateInfo.isFullUpdate then
            Rebuild()
        end
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR5, "modules/foo.lua", r8, cfg), 0,
    "negative gate branch unrestricts payload taint")

-- REVIEW SOUNDNESS FIX: a falsy aura gate must NOT bless NON-payload
-- secrets. GetSpellCharges taint is cooldown-class, not aura-class — the
-- in-expression gate proof no longer covers it.
local srcR6 = [[
local cd = C_Spell.GetSpellCharges(1)
local v = not AurasAreSecret() and cd or 0
]]
local fR6 = Analyzer.analyze(srcR6, "modules/foo.lua", r8, cfg)
assert(#fR6 >= 1, "aura gate must not prove a cooldown-class secret safe")

-- ...while the same shape over PAYLOAD taint stays proven (the gate governs
-- exactly that class).
local srcR7 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local v = not AurasAreSecret() and updateInfo or nil
    Consume(v)
end)
]]
assert_eq(#Analyzer.analyze(srcR7, "modules/foo.lua", r8, cfg), 0,
    "aura gate still proves payload-class taint in-expression")

-- Same for the statement-level bail: gate bail must NOT unrestrict
-- cooldown-class taint.
local srcR8 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local cd = C_Spell.GetSpellCharges(1)
    if cd and cd.currentCharges then Use() end
end)
]]
assert(#Analyzer.analyze(srcR8, "modules/foo.lua", r8, cfg) >= 1,
    "gate bail must not unrestrict cooldown-class taint")

-- Guard ALIAS resolution (review: aliases were not soundly resolved): a
-- clean single-binding alias probes like the guard itself...
local srcR9 = [[
local isv = issecretvalue
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if isv(updateInfo) then return end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "guard alias probes like the guard")

-- ...but a POISONED alias (conflicting binding anywhere in the file) grants
-- no protection.
local srcR10 = [[
local isv = issecretvalue
isv = AlwaysFalse
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if isv(updateInfo) then return end
    if updateInfo and updateInfo.isFullUpdate then
        Rebuild()
    end
end)
]]
assert(#Analyzer.analyze(srcR10, "modules/foo.lua", r8, cfg) >= 1,
    "poisoned guard alias grants no protection")

-- Round-8b (stop-time review): field provenance — a field written from an
-- INDEPENDENT source onto a payload-named table is NOT payload-class taint;
-- gate clears/proofs must not erase it just because its root is a payload
-- name.
local srcR11 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo.cd = C_Spell.GetSpellCharges(1)
    if AurasAreSecret() then return end
    print(updateInfo.cd)
end)
]=]
assert(#Analyzer.analyze(srcR11, "modules/foo.lua", r8, cfg) >= 1,
    "gate bail must not erase independently sourced field taint")

-- ...while a pure payload COPY into a field stays gate-governed.
local srcR12 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo.copy = updateInfo.isFullUpdate
    if AurasAreSecret() then return end
    print(updateInfo.copy)
end)
]=]
assert_eq(#Analyzer.analyze(srcR12, "modules/foo.lua", r8, cfg), 0,
    "payload-copy field taint is gate-governed and clears on bail")

-- Same hole in the in-expression gate proof: `not gate() and updateInfo.cd`
-- must NOT be proven safe when .cd carries independent source taint.
local srcR13 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo.cd = C_Spell.GetSpellCharges(1)
    local v = not AurasAreSecret() and updateInfo.cd or 0
    Consume(v)
end)
]=]
assert(#Analyzer.analyze(srcR13, "modules/foo.lua", r8, cfg) >= 1,
    "gate proof must not cover independently sourced field taint")

-- Round-8c (stop-time review): independent provenance survives COPIES.
-- `local cd = updateInfo.cd` used to re-enter the payload class via its root
-- name, letting the gate erase cooldown taint through the copy.
local srcR14 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo.cd = C_Spell.GetSpellCharges(1)
    local cd = updateInfo.cd
    if AurasAreSecret() then return end
    print(cd)
end)
]=]
assert(#Analyzer.analyze(srcR14, "modules/foo.lua", r8, cfg) >= 1,
    "copy of an independently sourced field stays independent through the gate")

-- ...while a local copy of a PURE payload field remains gate-governed.
local srcR15 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local full = updateInfo.isFullUpdate
    if AurasAreSecret() then return end
    print(full)
end)
]=]
assert_eq(#Analyzer.analyze(srcR15, "modules/foo.lua", r8, cfg), 0,
    "copy of a pure payload field clears on gate bail")

-- Deep reads through an independent segment are refused by the gate proof
-- (prefix-aware keyIsPayloadRooted).
local srcR16 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo.cd = C_Spell.GetSpellCharges(1)
    local v = not AurasAreSecret() and updateInfo.cd.duration or 0
    Consume(v)
end)
]=]
assert(#Analyzer.analyze(srcR16, "modules/foo.lua", r8, cfg) >= 1,
    "gate proof refuses deep reads through an independent segment")

-- Round-8d (stop-time review): independent provenance across table ALIASES.
-- Field keys canonicalize through `local info = updateInfo`, so a field
-- written via one name is found — with its provenance — via the other.
local srcR17 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = updateInfo
    info.cd = C_Spell.GetSpellCharges(1)
    if AurasAreSecret() then return end
    print(updateInfo.cd)
end)
]=]
assert(#Analyzer.analyze(srcR17, "modules/foo.lua", r8, cfg) >= 1,
    "independent field written via alias survives the gate for the original name")

local srcR18 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    updateInfo.cd = C_Spell.GetSpellCharges(1)
    local info = updateInfo
    if AurasAreSecret() then return end
    print(info.cd)
end)
]=]
assert(#Analyzer.analyze(srcR18, "modules/foo.lua", r8, cfg) >= 1,
    "independent field read via alias survives the gate")

-- Pure payload data through an alias is still gate-governed.
local srcR19 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = updateInfo
    if AurasAreSecret() then return end
    if info and info.isFullUpdate then
        Rebuild()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR19, "modules/foo.lua", r8, cfg), 0,
    "aliased pure payload data clears on gate bail")

-- Rebinding the alias name breaks the aliasing: fields written through the
-- REBOUND name must not unify with the payload table's keys.
local srcR20 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = updateInfo
    info = C_Spell.GetSpellCharges(1)
    if AurasAreSecret() then return end
    print(info.currentCharges)
end)
]=]
assert(#Analyzer.analyze(srcR20, "modules/foo.lua", r8, cfg) >= 1,
    "rebound alias carries its own (cooldown-class) taint through the gate")

-- Round-8e (stop-time review): alias canonicalization is PATH-SCOPED.  A
-- branch-conditional alias makes the name ambiguous — on the untaken path it
-- still holds non-payload data, so the gate must not erase it.
local srcR21 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local cd = C_Spell.GetSpellCharges(1)
    local info = cd
    if IsAltMode() then
        info = updateInfo
    end
    updateInfo.x = info.duration
    if AurasAreSecret() then return end
    print(updateInfo.x)
end)
]=]
assert(#Analyzer.analyze(srcR21, "modules/foo.lua", r8, cfg) >= 1,
    "branch-conditional alias poisons: gate must not erase the maybe-cooldown field")

-- Base taint of an ambiguous name survives the gate clear too.
local srcR22 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = C_Spell.GetSpellCharges(1)
    if IsAltMode() then
        info = updateInfo
    end
    if AurasAreSecret() then return end
    print(info)
end)
]=]
assert(#Analyzer.analyze(srcR22, "modules/foo.lua", r8, cfg) >= 1,
    "gate clear must keep base taint of a path-ambiguous name")

-- Re-convergent binding (same alias in BOTH branches) is NOT ambiguous:
-- payload data through it stays gate-governed.
local srcR23 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info
    if IsAltMode() then
        info = updateInfo
    else
        info = updateInfo
    end
    if AurasAreSecret() then return end
    if info and info.isFullUpdate then
        Rebuild()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR23, "modules/foo.lua", r8, cfg), 0,
    "re-convergent alias stays payload-governed through the gate")

-- A stable pre-if alias is untouched by an unrelated branch.
local srcR24 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = updateInfo
    if IsAltMode() then
        Prepare()
    end
    info.cd = C_Spell.GetSpellCharges(1)
    if AurasAreSecret() then return end
    print(updateInfo.cd)
end)
]=]
assert(#Analyzer.analyze(srcR24, "modules/foo.lua", r8, cfg) >= 1,
    "stable pre-if alias still unifies independent field keys")

-- Round-8f (stop-time review): terminating branches cannot reach post-if
-- code — their provenance changes roll back entirely instead of poisoning.
local srcR25 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = updateInfo
    if IsBadState() then
        info = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    if info and info.isFullUpdate then
        Rebuild()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR25, "modules/foo.lua", r8, cfg), 0,
    "terminating-branch rebind must not poison the surviving alias")

-- ...and the rollback also stops the terminating branch's PAYLOAD
-- classification from leaking onto the surviving path.
local srcR26 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local cd = C_Spell.GetSpellCharges(1)
    local info = cd
    if IsAltMode() then
        info = updateInfo
        return
    end
    updateInfo.x = info.duration
    if AurasAreSecret() then return end
    print(updateInfo.x)
end)
]=]
assert(#Analyzer.analyze(srcR26, "modules/foo.lua", r8, cfg) >= 1,
    "terminated branch's payload classification must not leak to the surviving path")

-- Round-8g (stop-time review): nested all-path termination.  A branch that
-- leaves through an inner if/else whose every path returns cannot reach the
-- post-if state — its provenance rolls back like a plain `return` branch.
local srcR27 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = updateInfo
    if IsBadState() then
        info = C_Spell.GetSpellCharges(1)
        if IsLoud() then
            Report()
            return
        else
            return
        end
    end
    if AurasAreSecret() then return end
    if info and info.isFullUpdate then
        Rebuild()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR27, "modules/foo.lua", r8, cfg), 0,
    "nested all-path-return branch rolls back like a plain return")

-- Partial nested termination (inner if with no else) still falls through —
-- the rebind IS reachable post-if, so the ambiguity must poison and flag.
local srcR28 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local info = updateInfo
    if IsBadState() then
        info = C_Spell.GetSpellCharges(1)
        if IsLoud() then
            return
        end
    end
    if AurasAreSecret() then return end
    if info and info.isFullUpdate then
        Rebuild()
    end
end)
]=]
assert(#Analyzer.analyze(srcR28, "modules/foo.lua", r8, cfg) >= 1,
    "partially terminating nested if still reaches post-if: ambiguity must flag")

-- Round-8h (stop-time review): FIELD taint is heap state.  A field written
-- on a terminated path persists into LATER invocations of the handler that
-- do reach the post-if code — it must survive the branch merge, with its
-- independent provenance, and flag through the gate.
local srcR29 = [=[
local obj = {}
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsFirstPass() then
        obj.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(obj.cd)
end)
]=]
assert(#Analyzer.analyze(srcR29, "modules/foo.lua", r8, cfg) >= 1,
    "field written on a terminated path persists (heap) and flags post-gate")

-- Round-8i (stop-time review): the heap union exempts INVOCATION-LOCAL
-- tables — `local tmp = {}` bound only to fresh constructors and never
-- escaping dies with the call, so a terminated branch's field write on it
-- is unreachable from ANY invocation's post-if code.
local srcR31 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR31, "modules/foo.lua", r8, cfg), 0,
    "terminated-branch write to an invocation-local table rolls back")

-- ...but an ESCAPED fresh table is heap: later invocations can reach it.
local srcR32 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    Register(tmp)
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert(#Analyzer.analyze(srcR32, "modules/foo.lua", r8, cfg) >= 1,
    "escaped table stays heap: the terminated-branch write persists")

-- Round-8j (stop-time review): freshness is per scope-resolved VARIABLE.
-- An inner `local tmp = {}` must not make OUTER/upvalue uses of the same
-- name look invocation-local — those writes hit a heap table.
local srcR33 = [=[
local tmp = MakeShared()
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    do
        local tmp = {}
        tmp.scratch = Compute()
    end
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert(#Analyzer.analyze(srcR33, "modules/foo.lua", r8, cfg) >= 1,
    "shadowed name: upvalue heap table must not inherit the inner local's freshness")

-- Round-8k (stop-time review): a scratch table freshly bound INSIDE the
-- terminated branch is block-local — it dies with the branch and must not
-- leave heap taint under its name for unrelated post-if code.
local srcR34 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsBadState() then
        local tmp = {}
        tmp.cd = C_Spell.GetSpellCharges(1)
        Consume(tmp.cd)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR34, "modules/foo.lua", r8, cfg), 0,
    "branch-local scratch table rolls back with its terminating branch")

-- ...unless it ESCAPES inside the branch — then later invocations can reach
-- it and the write is heap.
local srcR35 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if IsBadState() then
        local tmp = {}
        Register(tmp)
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert(#Analyzer.analyze(srcR35, "modules/foo.lua", r8, cfg) >= 1,
    "escaped branch-local table stays heap")

-- Round-8l (stop-time review): closure capture is an escape.  A nested
-- function using the table — even field-only — can outlive the invocation,
-- so the captured table is heap and the terminated-branch write persists.
local srcR36 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    RunLater(function() return tmp.cd end)
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert(#Analyzer.analyze(srcR36, "modules/foo.lua", r8, cfg) >= 1,
    "closure-captured table is heap: the terminated-branch write persists")

-- Round-8m (stop-time review): closure PARAMETERS (and closure top-level
-- locals) shadow the outer name — their uses are not captures, so the outer
-- fresh table keeps its invocation-local rollback.
local srcR37 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    Sort(list, function(tmp) return tmp.a end)
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR37, "modules/foo.lua", r8, cfg), 0,
    "closure param shadowing is not a capture: outer fresh table rolls back")

local srcR38 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    RunLater(function()
        local tmp = {}
        tmp.x = 1
    end)
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR38, "modules/foo.lua", r8, cfg), 0,
    "closure-local shadow is not a capture: outer fresh table rolls back")

-- Round-8n (stop-time review): `local function` inside a closure shadows —
-- uses of the name are the closure's own function, not a capture.
local srcR39 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    RunLater(function()
        local function tmp() return 1 end
        Use(tmp())
    end)
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR39, "modules/foo.lua", r8, cfg), 0,
    "closure-local function shadow is not a capture: outer fresh table rolls back")

-- Control: a GLOBAL `function tmp()` inside the closure rebinds the outer
-- name — that is not a shadow, so freshness dies and the write is heap.
local srcR40 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    RunLater(function()
        function tmp() return 1 end
    end)
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert(#Analyzer.analyze(srcR40, "modules/foo.lua", r8, cfg) >= 1,
    "global function-statement rebind of the outer name kills freshness")

-- Round-8o (preempt): loop variables are body-scoped bindings.  Inside a
-- closure they shadow for exactly the loop body; at the outer level a
-- collision with a fresh name kills its freshness.
local srcR41 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    RunLater(function()
        for _, tmp in ipairs(GetList()) do
            Use(tmp.name)
        end
    end)
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR41, "modules/foo.lua", r8, cfg), 0,
    "closure loop-var shadow is not a capture: outer fresh table rolls back")

local srcR42 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    for _, tmp in ipairs(GetList()) do
        Use(tmp.name)
    end
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert(#Analyzer.analyze(srcR42, "modules/foo.lua", r8, cfg) >= 1,
    "outer loop-var collision makes the name ambiguous: stays heap")

-- Round-8p (stop-time review): a colon method DECLARATION is a field write
-- on the base (`self` binds at call time), not a receiver escape.
local srcR43 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    function tmp:refresh() return 1 end
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR43, "modules/foo.lua", r8, cfg), 0,
    "colon method declaration keeps the base fresh (field write, no escape)")

-- Control: a colon method CALL passes the table as `self` — receiver escape.
local srcR44 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local tmp = {}
    tmp:Init()
    if IsBadState() then
        tmp.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(tmp.cd)
end)
]=]
assert(#Analyzer.analyze(srcR44, "modules/foo.lua", r8, cfg) >= 1,
    "colon method CALL is a receiver escape: stays heap")

-- Round-8q (stop-time review): a colon method body's `self` is the method's
-- own implicit parameter — never a capture of an outer name `self`.
local srcR45 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(frame, event, unit, updateInfo)
    local self = {}
    local tmp = {}
    function tmp:m()
        self.count = (self.count or 0) + 1
    end
    if IsBadState() then
        self.cd = C_Spell.GetSpellCharges(1)
        return
    end
    if AurasAreSecret() then return end
    print(self.cd)
end)
]=]
assert_eq(#Analyzer.analyze(srcR45, "modules/foo.lua", r8, cfg), 0,
    "colon method body's implicit self does not capture an outer fresh `self`")

-- Round-8r (stop-time review): implicit `self` in the TAINT walk.  A colon
-- method body's self is a fresh parameter (the receiver) — it must not
-- inherit an outer tainted variable named `self` as an upvalue.
local srcR46 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(frame, event, unit, updateInfo)
    local self = C_Spell.GetSpellCharges(1)
    local obj = {}
    function obj:refresh()
        if self.isActive and self.currentCharges then
            Use()
        end
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR46, "modules/foo.lua", r8, cfg), 0,
    "colon method body's implicit self does not inherit outer `self` taint")

-- ---------------------------------------------------------------------------
-- Round-9 (2026-07 external review): gate governance + deep-field provenance
-- Own do…end scope: the enclosing block brushes Lua 5.1's 200-local limit.
-- ---------------------------------------------------------------------------
do
-- One reused source local: the enclosing function is at the 200-local edge.
local srcR9

-- An ALWAYS-secret payload event (gateGoverned = false): the aura gate does
-- not govern it, so a gate bail must NOT clear the payload taint.
r8:addSecretPayloadEvent("UNIT_AURA_BLOCKED", { 4, gateGoverned = false })

-- Detected via the event-name comparison.
srcR9 = [=[
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, unitTarget, auraInstanceID)
    if event == "UNIT_AURA_BLOCKED" then
        if AurasAreSecret() then return end
        if auraInstanceID then
            Use()
        end
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "aura gate must not clear an always-secret (gate-ungoverned) payload")

-- Detected via the RegisterEvent/SetScript linkage (no comparison).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA_BLOCKED")
f:SetScript("OnEvent", function(self, event, unitTarget, auraInstanceID)
    if AurasAreSecret() then return end
    if auraInstanceID then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "RegisterEvent-linked ungoverned payload survives the gate bail too")

-- Mixed handler: ONE ungoverned event in the mix disables the gate bless for
-- the whole handler (conservative — the clear cannot tell the payloads apart).
srcR9 = [=[
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "UNIT_AURA" or event == "UNIT_AURA_BLOCKED" then
        if AurasAreSecret() then return end
        if updateInfo then
            Use()
        end
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "mixed governed+ungoverned handler keeps payload taint through the gate")

-- Governed-only control: the gate bail still clears UNIT_AURA payload taint.
srcR9 = [=[
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if event == "UNIT_AURA" then
        if AurasAreSecret() then return end
        if updateInfo then
            Use()
        end
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "governed-only handler keeps the gate clear (no over-taint regression)")

-- Deep-field independent provenance: a write through a NESTED dotted chain
-- keys on the full canonical chain, so the aura-gate clear cannot launder a
-- cooldown secret parked on a payload-rooted deep field.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub.cd = C_Spell.GetSpellCharges(1)
    local cd = updateInfo.sub.cd
    if cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "deep-field write keeps independent provenance through the gate clear")

-- Read side: the deep truth-test itself (no copy) sees the full-chain key.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub.cd = C_Spell.GetSpellCharges(1)
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "deep-chain truth-test reads the full-chain field-taint key")

-- Control: a CLEAN deep write after the gate bail stays clean.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub.cd = 5
    local cd = updateInfo.sub.cd
    if cd then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "clean deep write after the gate bail does not over-taint")

-- Round-9b (Codex stop-review catch): STABLE bracketed deep fields.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub[1] = C_Spell.GetSpellCharges(1)
    if updateInfo.sub[1] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "stable numeric bracket write keeps independent provenance through the gate")

-- Identifier string keys fold to the dot form: bracket write, dot read.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub["cd"] = C_Spell.GetSpellCharges(1)
    local cd = updateInfo.sub.cd
    if cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "bracket identifier-string write unifies with the dot-form read")

-- VOLATILE bracket write of a tainted value: no sound key — the payload
-- root re-taints as independent so the gate clear cannot launder the slot.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local k = GetKey()
    updateInfo.sub[k] = C_Spell.GetSpellCharges(1)
    if updateInfo.sub[k] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "volatile bracket write of a tainted value re-taints the payload root")

-- Control: a CLEAN volatile bracket write must not re-taint the root.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local k = GetKey()
    updateInfo.sub[k] = 5
    if updateInfo.isFullUpdate then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "clean volatile bracket write after the gate bail does not over-taint")

-- Round-9c (Codex stop-review catch #2): volatile fallback aliasing.
-- A STABLE write read back through a VOLATILE index of the same base — the
-- volatile read may alias any recorded key under its stable prefix.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub[1] = C_Spell.GetSpellCharges(1)
    local i = GetIndex()
    if updateInfo.sub[i] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "volatile read aliases a stable bracket write under the same prefix")

-- Dot write, volatile read of the same base.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub.cd = C_Spell.GetSpellCharges(1)
    local i = GetIndex()
    if updateInfo.sub[i] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "volatile read aliases a dot write under the same prefix")

-- Volatile write through an UNTAINTED post-gate ALIAS copy: alias identity
-- is about the table, not its taint — the untracked write re-taints the
-- canonical root AND the alias name.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local info = updateInfo
    local k = GetKey()
    info.sub[k] = C_Spell.GetSpellCharges(1)
    if info.sub[k] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "volatile write through an untainted alias copy re-taints the table")

-- Control: unrelated volatile read of a DIFFERENT base after a stable write
-- must not flag (prefix scoping, no blanket root smear).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub.cd = C_Spell.GetSpellCharges(1)
    local other = {}
    local i = GetIndex()
    if other.list[i] then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "volatile read of an unrelated base stays clean (prefix scoped)")

-- Round-9d (Codex stop-review catch #3): contamination markers are HEAP
-- state — a volatile write on a TERMINATING branch persists into later
-- invocations (the taintSet-based root re-taint rolled back with the
-- branch locals).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local k = GetKey()
    if IsBadState() then
        updateInfo.sub[k] = C_Spell.GetSpellCharges(1)
        return
    end
    if updateInfo.sub[k] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "terminating-branch volatile contamination persists (heap marker)")

-- May-alias across a branch merge: a poisoned target that MAY be the
-- payload table still records the contamination under its own name.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local target
    if PickPayload() then
        target = updateInfo
    else
        target = {}
    end
    local k = GetKey()
    target.sub[k] = C_Spell.GetSpellCharges(1)
    if target.sub[k] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "may-alias merge target keeps volatile contamination visible")

-- Lua simultaneous-assignment semantics: `info, other = other, info`
-- resolves every RHS before any LHS binds — the swap must not lose the
-- payload-table identity.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local info = updateInfo
    local other = {}
    info, other = other, info
    local k = GetKey()
    other.sub[k] = C_Spell.GetSpellCharges(1)
    if other.sub[k] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "simultaneous-assignment swap keeps the payload-table alias")

-- Member-chain copy: `local sub = updateInfo.sub` names a table an
-- untracked write contaminates under its own root.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local sub = updateInfo.sub
    local k = GetKey()
    sub[k] = C_Spell.GetSpellCharges(1)
    if sub[k] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "member-chain copy keeps volatile contamination visible")

-- FP guard (Codex stop-review): the marker taints strict DESCENDANTS only.
-- Reading the contaminated prefix itself yields the container table
-- reference — never a secret value; its truth-test must stay clean (parity
-- with a VarExpr-rooted container, which never consulted markers).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    local k = GetKey()
    t.sub[k] = C_Spell.GetSpellCharges(1)
    if t.sub then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "contamination marker leaves the container table itself clean")

-- FP guard (Codex stop-review): volatile-read aliasing is DEPTH-GATED. A
-- volatile read SHALLOWER than every recorded tainted key can only yield
-- an ancestor container reference (a plain table, never a secret value):
-- `t[j]` under marker "t.sub[*]" reaches t.sub at most.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    local k = GetKey()
    t.sub[k] = C_Spell.GetSpellCharges(1)
    local j = GetKey()
    if t[j] then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "shallow volatile read under a deeper marker stays clean")

-- Same gate, stable deep write: `t[j]` cannot reach t.sub.cd's value.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    t.sub.cd = C_Spell.GetSpellCharges(1)
    local j = GetKey()
    if t[j] then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "shallow volatile read under a deeper stable write stays clean")

-- Depth gate keeps the taint at equal depth (the read may BE the slot) …
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    local k = GetKey()
    t.sub[k] = C_Spell.GetSpellCharges(1)
    local j = GetKey()
    local m = GetKey()
    if t[j][m] then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "equal-depth volatile read under a marker still flags")

-- … and BEYOND it (a deeper read indexes THROUGH the tainted slot, and
-- indexing a secret value throws).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    t.sub.cd = C_Spell.GetSpellCharges(1)
    local j = GetKey()
    if t.sub[j].x then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "past-depth volatile read through a tainted slot still flags")

-- FP guard (Codex stop-review): volatile aliasing is SEGMENT-matched, not
-- depth-matched.  `t[j].x` can only name t.<any>.x — never the recorded
-- slot t.sub.y (j may be "sub" but .x ≠ .y); mismatched stable segments
-- also block the pass-through reading (t[j].x[m] never crosses t.sub.y).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    t.sub.y = C_Spell.GetSpellCharges(1)
    local j = GetKey()
    local m = GetKey()
    if t[j].x then Use() end
    if t[j].x[m] then Use() end
    if t[j][3] then Use() end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "stable segment mismatch defeats volatile aliasing at every depth")

-- … while matching segments keep flagging: the volatile hop may be "sub",
-- and the identifier string key folds to the dot spelling.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    t.sub.y = C_Spell.GetSpellCharges(1)
    local j = GetKey()
    if t[j]["y"] then Use() end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "segment-matched volatile read still flags (string-fold parity)")

-- FN guard (Codex stop-review, round-9n): segment matching must hop LIVE
-- chain aliases — differently spelled paths can be one table.  With
-- `t.alt.x = t.sub.y`, the volatile read t[j].x.z (j == "alt") IS the
-- recorded secret t.sub.y.z.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    local j = GetKey()
    t.sub.y.z = C_Spell.GetSpellCharges(1)
    t.alt.x = t.sub.y
    if t[j].x.z then Use() end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "volatile read bridges a live chain alias to the recorded key")

-- … while the alias must not blunt the segment rule: a read matching
-- neither the recorded spelling nor the alias slot stays clean, and the
-- shallow container-reference read does too.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    local j = GetKey()
    t.sub.y.z = C_Spell.GetSpellCharges(1)
    t.alt.x = t.sub.y
    if t[j].w.z then Use() end
    if t[j].x then Use() end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "alias hop keeps segment and container-depth pruning for other reads")

-- Alias slot EQUAL to the read's stable prefix: descendant writes live
-- under the target root, invisible to a raw prefix scan.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    local q = {}
    local j = GetKey()
    t.sub = q
    t.sub.cd = C_Spell.GetSpellCharges(1)
    if t.sub[j] then Use() end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "volatile read hops a slot alias equal to its stable prefix")

-- Codex stop-review (round-9n perf): the alias walk memoizes
-- (prefix, position) states — converging aliases must stay polynomial and
-- CYCLIC aliases must terminate, without losing matches reachable through
-- a shared downstream state.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t = {}
    local q = {}
    local j = GetKey()
    q.z = C_Spell.GetSpellCharges(1)
    t.a.x = q
    t.b.x = q
    t.hub = t
    if t[j].x.z then Use() end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "converging aliases still match through the memoized shared state")

-- FP guards (round-9d): a definite CLEAN parent replacement clears the
-- recorded descendants.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub.cd = C_Spell.GetSpellCharges(1)
    updateInfo.sub = {}
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "clean parent replacement clears descendant field taint")

-- Round-9e (Codex stop-review catch #4): the sweep is CONTENT-clean only.
-- An untainted VARIABLE can carry tainted fields keyed under its own root
-- — replacing the slot with it must not erase the recorded descendants.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    t2.cd = C_Spell.GetSpellCharges(1)
    updateInfo.sub.cd = C_Spell.GetSpellCharges(2)
    updateInfo.sub = t2
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "untainted-variable replacement must not sweep descendant taint")

-- Round-9e flip side: variable replacement REKEYS — a clean-content
-- variable drops the OLD table's stale descendant taint.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    t2.name = "clean"
    updateInfo.sub.cd = C_Spell.GetSpellCharges(1)
    updateInfo.sub = t2
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "clean-content variable replacement drops the old table's stale taint")

-- Round-9f (Codex stop-review catch #5): the slot↔source link is LIVE, not
-- a snapshot — a write through the source AFTER the slot assignment is
-- visible through the slot...
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    updateInfo.sub = t2
    t2.cd = C_Spell.GetSpellCharges(1)
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "late tainted write through the source alias is visible via the slot")

-- ...and a late CLEAN overwrite through the source clears the slot read.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    t2.cd = C_Spell.GetSpellCharges(1)
    updateInfo.sub = t2
    t2.cd = 5
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "late clean overwrite through the source alias clears the slot read")

-- The exact slot key is a SNAPSHOT (scalar copies do not track the source
-- name): re-binding the source NAME afterwards leaves the slot's recorded
-- state intact via the rebind mirror.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    t2.cd = C_Spell.GetSpellCharges(1)
    updateInfo.sub = t2
    t2 = {}
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "source-name rebind mirrors accumulated keys onto the slot spelling")

-- Round-9g (Codex stop-review catch #6): slot rebinds must not RETARGET
-- dependents.  A name bound from a slot chain resolves to the table
-- IDENTITY at bind time and survives the slot moving on.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    updateInfo.sub = t2
    local x = updateInfo.sub
    updateInfo.sub = {}
    x.cd = C_Spell.GetSpellCharges(1)
    if t2.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "name bound from a slot chain keeps the table identity across a slot rebind")

-- Slot aliased to another SLOT chain: the middle slot's rebind must not
-- dangle the dependent slot's target.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t1 = {}
    updateInfo.a = t1
    updateInfo.b = updateInfo.a
    updateInfo.a = {}
    t1.cd = C_Spell.GetSpellCharges(1)
    if updateInfo.b.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "slot-to-slot alias resolves to the underlying table identity")

-- Round-9h (Codex stop-review catch #7): SAME-ROOT disjoint-subtree slot
-- aliases are legitimate — `updateInfo.sub = updateInfo.other` unifies.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    updateInfo.sub = updateInfo.other
    updateInfo.other.cd = C_Spell.GetSpellCharges(1)
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "same-root disjoint-subtree slot alias unifies reads and writes")

-- ...including through a bare variable whose identity is a same-root chain.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local a = updateInfo.other
    updateInfo.sub = a
    a.cd = C_Spell.GetSpellCharges(1)
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "bare var with a same-root chain identity unifies via the slot alias")

-- Round-9i (Codex stop-review catch #8): breaking a shared target must
-- RELINK its co-dependents, not sever them — they still share the table.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local a = updateInfo.other
    updateInfo.sub = a
    updateInfo.other = {}
    a.cd = C_Spell.GetSpellCharges(1)
    if updateInfo.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "co-dependents of a broken slot target stay unified")

srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    local a = t2
    local b = t2
    t2 = {}
    a.cd = C_Spell.GetSpellCharges(1)
    if b.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "co-dependents of a re-bound source name stay unified")

-- Round-9j (Codex stop-review catch #9): a slot SPELLED under the rebound
-- root is a dead spelling — it must not become the representative (its
-- mirrored keys would sit where the NEW table's writes land).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local a = {}
    local z = {}
    a.sub = a.other
    z.keep = a.other
    a.other.cd = C_Spell.GetSpellCharges(1)
    a = {}
    a.sub.cd = 5
    if z.keep.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "dead-spelling slots are excluded from representative election")

-- Round-9k (Codex stop-review catch #10): a chainAlias entry spelled under
-- a rebound name describes a LIVE descendant link of the inherited table —
-- it re-spells under the representative instead of dropping.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if AurasAreSecret() then return end
    local t2 = {}
    local q = {}
    local a = t2
    a.sub = q
    t2 = {}
    q.cd = C_Spell.GetSpellCharges(1)
    if a.sub.cd then
        Use()
    end
end)
]=]
assert(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg) >= 1,
    "descendant chain links re-spell under the representative on root rebind")

-- FP guard: a STABLE bracket payload copy stays gate-governed
-- (`updateInfo["foo"]` is a payload read like the dotted form).
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local v = updateInfo["foo"]
    if AurasAreSecret() then return end
    if v then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "stable bracket payload copy is cleared by the gate bail")

-- FP guard: bracket reads honor the clean-field whitelist like dotted ones.
r8:addCleanField("isOnGCD")
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    if updateInfo["isOnGCD"] then
        Use()
    end
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "bracket read of a registered clean field stays clean")

-- FP guard: keyed refs are plain references in and/or chains — probe
-- ordering is detectUnsafeProbeOrder's job, same as dotted refs.
srcR9 = [=[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, updateInfo)
    local t = updateInfo
    local v = not issecretvalue(t[1]) and t[1]
    Use(v)
end)
]=]
assert_eq(#Analyzer.analyze(srcR9, "modules/foo.lua", r8, cfg), 0,
    "probed keyed ref in an and-chain emits no generic binop finding")

end

-- ---------------------------------------------------------------------------
-- Round-10: structural expression coverage, handler identity, positional
-- multi-return flow, and exact-reference guard proofs.
-- ---------------------------------------------------------------------------
;(function()
local r10 = Registry.new()
r10:addSource("S")

local expressionCases = {
    { [[local v = S() or 0]], 1, "direct source result truth-tested by or" },
    { [[local t = { x = S() }; print(t.x)]], 1,
        "constructor stores a direct source" },
    { [[local x = S(); local t = { x = x }; print(t.x)]], 1,
        "constructor stores a tainted reference" },
    { [[local t = { x = S() }; if t then Use() end]], 0,
        "constructor container reference is never itself secret" },
    { [[local t = { x = S() }; print(t.y)]], 0,
        "constructor taint does not spread to an unrelated field" },
    { [[print({ x = S() })]], 0,
        "passing a constructor consumes only its plain table reference" },
    { [[local t = { sub = { x = S() } }; print(t.sub.x)]], 1,
        "nested constructor preserves the exact tainted field" },
    { [[local t = { sub = { x = S() } }; print(t.sub.y)]], 0,
        "nested constructor keeps sibling fields clean" },
    { [[local t = cond and { x = S() } or {}; print(t.x)]], 1,
        "conditional constructor preserves a tainted field on one path" },
    { [[local t = cond and { x = S() } or {}; print(t.y)]], 0,
        "conditional constructor keeps sibling fields clean" },
    { [[local t = {}; t.sub = { x = S() }; print(t.sub.x)]], 1,
        "constructor assigned into a member records descendant taint" },
    { [[local t = {}; t.sub = cond and { x = S() } or {}; print(t.sub.x)]], 1,
        "conditional member constructor preserves a tainted descendant" },
    { [[local t = {}; t.sub = cond and { x = S() } or {}; print(t.sub.y)]], 0,
        "conditional member constructor keeps sibling fields clean" },
    { [[local t = {}; t.sub.x = S(); t.sub = { x = 1 }; print(t.sub.x)]], 0,
        "known constructor replacement clears stale descendant taint" },
    { [[local t = { x = S() }; for k, v in pairs(t) do print(v) end]], 1,
        "tainted constructor content diagnoses at the use-site sink (print)" },
    { [[local t = { x = S() }; rawget(t, "x")]], 1,
        "rawget still diagnoses tainted constructor contents" },
    { [[local t = { pcall(S) }; print(t[1])]], 0,
        "constructor pcall expansion keeps the success slot clean" },
    { [[local t = { pcall(S) }; print(t[2])]], 1,
        "constructor pcall expansion taints the first protected result" },
    { [[local x = S(); local t = { tonumber(x) }]], 1,
        "constructor value walks nested sinks" },
    { [=[local x = S(); local y = t[tonumber(x)]]=], 1,
        "index expression walks nested sinks" },
    { [=[local x = S(); t[x] = 1]=], 1,
        "assignment LHS consumes a tainted computed key" },
    { [[local x = S(); local y = (tonumber(x) and A or B)()]], 1,
        "computed call base walks nested sinks" },
    { [[local x = S(); Foo{ tonumber(x) }]], 1,
        "table-call sugar walks nested sinks" },
    { [[local x = S(); for i = x, 10 do end]], 1,
        "numeric-for consumes a bare tainted start bound" },
    { [[local x = S(); for i = 1, 10, x do end]], 1,
        "numeric-for consumes a bare tainted step" },
}
for _, tc in ipairs(expressionCases) do
    assert_eq(#Analyzer.analyze(tc[1], "modules/foo.lua", r10, cfg), tc[2],
        "round-10 expression coverage: " .. tc[3])
end

local r10Event = Registry.new()
r10Event:addSecretPayloadEvent("UNIT_AURA", { 4 })

local src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, info)
    print(info)
end)
f:SetScript("OnEvent", function() end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 0,
    "SetScript replacement drops the dead primary handler")

src10 = [[
local f = CreateFrame("Frame")
local function OnEvent(self, event, unit, info)
    print(info)
end
local Handler = OnEvent
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", Handler)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "handler value aliases resolve at SetScript time")

src10 = [[
local Data = {}
Data.frame = CreateFrame("Frame")
Data.frame:RegisterEvent("UNIT_AURA")
Data.frame:SetScript("OnEvent", function(self, event, unit, info)
    print(info)
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "stable dotted receivers link registrations to handlers")

src10 = [[
local f = CreateFrame("Frame")
function Handlers.OnEvent(self, event, unit, info)
    print(info)
end
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", Handlers.OnEvent)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "member-stored named handlers resolve")

src10 = [[
local f = CreateFrame("Frame")
local function MakeHandler()
    return function(self, event, unit, info)
        print(info)
    end
end
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", MakeHandler())
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "simple handler factories link their returned closure")

src10 = [[
local f = CreateFrame("Frame")
if GetMode() then
    f:RegisterEvent("UNIT_AURA")
else
    f:SetScript("OnEvent", function(self, event, unit, info)
        print(info)
    end)
end
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 0,
    "mutually exclusive receiver branches do not cross-link")

src10 = [[
local f = CreateFrame("Frame")
if GetMode() then
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(self, event, unit, info)
        print(info)
    end)
end
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "same-branch registration and handler still link")

src10 = [[
function Mixin:OnEvent(event, unit, info)
    if event == "UNIT_AURA" then
        print(info)
    end
end
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "colon handler accounts for the parser-omitted implicit self")

src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local unit, info = select(1, ...)
    print(unit)
    print(info)
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "select multi-return taints only the configured payload position")

src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, ...)
    local unit = select(1, ...)
    print(unit)
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 0,
    "scalar select truncation does not inherit later secret returns")

r10Event:addSecretPayloadEvent("SECRET_THREE", { 3 })
src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("SECRET_THREE")
f:SetScript("OnEvent", function(self, event, pos3, pos4)
    if event == "UNIT_AURA" then
        print(pos3)
    elseif event == "SECRET_THREE" then
        print(pos4)
    end
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 0,
    "mixed-event dispatch keeps per-event payload positions distinct")

src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("SECRET_THREE")
f:SetScript("OnEvent", function(self, event, pos3, pos4)
    if event == "UNIT_AURA" then
        print(pos4)
    elseif event == "SECRET_THREE" then
        print(pos3)
    end
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 2,
    "mixed-event dispatch retains each event's actual secret position")

src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, pos3, pos4)
    if event ~= "UNIT_AURA" then
        print(pos4)
    end
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 0,
    "event inequality excludes the named secret payload")

src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, info)
    local box = { info = info }
    if C_Secrets.ShouldAurasBeSecret() then return end
    print(box.info)
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 0,
    "constructor containing only payload taint stays gate-governed")

r10Event:addSource("S")
src10 = [[
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:SetScript("OnEvent", function(self, event, unit, info)
    local box = { info = info, independent = S() }
    if C_Secrets.ShouldAurasBeSecret() then return end
    print(box.independent)
end)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10Event, cfg), 1,
    "mixed constructor keeps its independent field tainted")

src10 = [[
local t = {}
t.f = S()
if issecretvalue(t.f) then return end
if t.f then Use() end
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "dotted guard bail proves only the exact field safe")

src10 = [[
local t = {}
t.f = S()
if issecretvalue(t.f) then return end
t.f = S()
if t.f then Use() end
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "field rebind invalidates the exact-reference guard proof")

src10 = [[
local ok, value
ok, value = pcall(S)
print(ok)
print(value)
]]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "plain assignment keeps pcall ok clean and taints spilled results")

-- Keyed cache slots keep their recorded taint in and/or chains:
-- chainRefTainted's old recurse-to-base shortcut read `cache[1]` as clean
-- (only the table base was consulted) while the dotted spelling flagged.
src10 = [=[
local cache = {}
local function Read()
    cache[1] = S()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "numeric-keyed cache slot keeps taint through an or-chain truth-test")

src10 = [=[
local cache = {}
local function Read()
    cache.a = S()
    return cache.a or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "dotted parity control: same shape, dotted spelling")

src10 = [=[
local cache = {}
local function Read()
    cache[1] = 5
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "clean keyed slot stays clean in an or-chain (no FP)")

-- Persistent-cache modeling (round-10b): a chunk-local cache slot filled
-- with a tainted value in ONE call/function is tainted when read by a
-- LATER call — the production cache-hit path reads BEFORE it writes.
src10 = [=[
local cache = {}
local function Read()
    local v = cache[1] or DEFAULT
    cache[1] = S()
    return v
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "read-before-write on a persistent slot models the cache-hit call")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "split Fill/Read functions share the persistent slot's taint")

src10 = [=[
local cache = {}
local function Read()
    return cache[1] or DEFAULT
end
local function Fill()
    cache[1] = S()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "definition order does not hide the Fill function's taint from Read")

-- Production-shaped cache (batch seen-token + volatile key): the hit path
-- truth-tests the slot a previous call filled with the raw source result.
src10 = [=[
local seen, cache = {}, {}
local function Get(action)
    if seen[action] then
        return cache[action] or DEFAULT
    end
    local v = S()
    seen[action] = true
    cache[action] = v
    return cache[action]
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "production-shaped cache: the hit path's or-chain sees the fill's taint")

-- Two-hop fixpoint: a cache filled FROM another persistent cache.
src10 = [=[
local c1, c2 = {}, {}
local function F1() c1[1] = S() end
local function F2() c2[1] = c1[1] end
local function F3() return c2[1] or DEFAULT end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "persistent taint propagates cache-to-cache across the fixpoint")

-- The export lattice must converge rather than stop at a magic pass count.
-- Pass 1 exports c1; each following pass exports one more cache, and the
-- final pass must consume c6 before the read can be diagnosed.
src10 = [=[
local c1, c2, c3, c4, c5, c6 = {}, {}, {}, {}, {}, {}
local function F1() c1[1] = S() end
local function F2() c2[1] = c1[1] end
local function F3() c3[1] = c2[1] end
local function F4() c4[1] = c3[1] end
local function F5() c5[1] = c4[1] end
local function F6() c6[1] = c5[1] end
local function Read() return c6[1] or DEFAULT end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "persistent-cache analysis runs to convergence beyond six passes")

-- Controls: the persistent seed must not over-approximate.
src10 = [=[
local cache = {}
local function Fill()
    cache[1] = 5
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "clean cross-function fill stays clean (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    local v = S()
    if issecretvalue(v) then return end
    cache[1] = v
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "probed-before-store fill exports no taint (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    if issecretvalue(cache[1]) then return DEFAULT end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "guard bail at the read proves the seeded slot safe (no FP)")

src10 = [=[
local cache = {}
if cache[1] then Use() end
local function Fill()
    cache[1] = S()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "straight-line chunk read before any fill runs once and stays clean (no FP)")

src10 = [=[
local function Make()
    local cache = {}
    local v = cache[1] or DEFAULT
    cache[1] = S()
    return v
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "invocation-local table dies with the call: no persistent seed (no FP)")

src10 = [=[
local function Fill(t)
    t.f = S()
end
local function Read(t)
    return t.f or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "param-rooted writes have no cross-function slot identity (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    cache[1] = 5
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "clean overwrite inside the reader clears the seed flow-sensitively (no FP)")

-- Lexical soundness (round-10c, Codex counterexamples): seeds and exports
-- are NAME-keyed, so shadowing must be handled explicitly.
src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Other()
    local cache = {}
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a shadowing local cache must not inherit the chunk cache's seed (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Other()
    local cache = {}
    return cache[1] or DEFAULT
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "the shadow skip must not defuse the real chunk-cache reader")

src10 = [=[
local cache = {}
local function Fill()
    do local cache = 5 end
    cache[1] = S()
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an unrelated block-local shadow must not suppress the chunk-cache export")

src10 = [=[
local cache = {}
local function Fill()
    local cache = {}
    cache[1] = S()
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a write through a shadowing local exports nothing (no FP)")

src10 = [=[
local cache = {}
local function Fill(cache)
    cache[1] = S()
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a write through a shadowing parameter exports nothing (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    for cache = 1, 3 do print(cache) end
    cache[1] = S()
end
local function Read()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a loop-variable shadow in a closed block must not suppress the export")

-- Per-READ seed resolution (round-10c, Codex counterexamples #2): shadow
-- suppression must be per read site, not whole-function.
src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    do local cache = 5 end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a closed-block shadow in the READER must not suppress the seed")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    local v = cache[1] or DEFAULT
    local cache = 5
    return v
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a read BEFORE a later same-scope shadow resolves outer and keeps the seed")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    local v = cache[1] or DEFAULT
    local cache = {}
    return cache[1] or DEFAULT, v
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "mixed function: the outer read flags, the shadow read stays clean")

src10 = [=[
local seen, cache = {}, {}
local function Fill(action)
    cache[action] = S()
end
local function Read(action)
    do local cache = 5 end
    return cache[action] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "volatile-key seed (contamination marker) survives an unrelated reader shadow")

-- Binding provenance (round-10c, Codex counterexample #3): a REAL write
-- must not make the key's taint name-global again — evidence carries the
-- WRITE root's binding identity, and reads consume it only from the same
-- binding.
src10 = [=[
local cache = {}
local function Read()
    cache[1] = S()
    local cache = {}
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "an outer-root write must not taint a later shadow's read (no FP)")

src10 = [=[
local cache = {}
local function Read()
    cache[1] = S()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "provenance control: same-binding write-then-read still flags")

src10 = [=[
local cache = {}
local function Read()
    do local cache = {} cache[1] = S() end
    do local cache = {} print(cache[1] or DEFAULT) end
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "sibling-block shadows are DIFFERENT bindings: no cross-block taint (no FP)")

src10 = [=[
local function Outer()
    local t = {}
    t.f = S()
    local g = function() return t.f or DEFAULT end
    return g
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a nested closure still sees the enclosing local's write (provenance inherits as outer)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    local cache = cache
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "the localize idiom (local cache = cache) inherits the outer binding and keeps the seed")

-- General table aliases participate in persistent-cache identity outside
-- event handlers too; lexical shadows and path joins remain conservative.
src10 = [=[
local cache = {}
local function Fill() cache[1] = S() end
local function Read()
    local alias = cache
    return alias[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "different-name local alias consumes the persistent cache seed")

src10 = [=[
local cache = {}
local alias = cache
local function Fill() cache[1] = S() end
local function Read() return alias[1] or DEFAULT end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "chunk alias identity is inherited by a nested reader")

src10 = [=[
local cache = {}
local alias = cache
local function Fill() cache[1] = S() end
local function Read(alias) return alias[1] or DEFAULT end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a parameter shadow does not inherit the enclosing alias (no FP)")

src10 = [=[
local cache = {}
local function Fill() cache[1] = S() end
local function Read(cond)
    local alias = {}
    if cond then alias = cache end
    return alias[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "path-conditional alias keeps the may-alias cache path")

src10 = [=[
local cache = {}
local function Fill() cache[1] = S() end
local function Read(cond)
    local alias = cache
    while cond do
        alias = {}
        cond = false
    end
    return alias[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "zero-iteration loop path preserves the entry alias")

src10 = [=[
local cache = {}
local function Read()
    local cache = {}
    Register(cache)
    cache[1] = S()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an ESCAPED shadow's write stays readable through its own binding")

-- Binding privacy (round-10c, Codex counterexample #4): escape must not
-- make evidence universally usable — a later FRESH shadow is a private
-- allocation that cannot be the escaped table. Cross-binding evidence
-- flows only when NEITHER side is a private (fresh, never-escaping)
-- binding.
src10 = [=[
local cache = {}
local function Read()
    Register(cache)
    cache[1] = S()
    local cache = {}
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "escaped-outer write must not leak into an unrelated fresh shadow (no FP)")

src10 = [=[
local cache = {}
local function Read(k)
    Register(cache)
    cache[k] = S()
    local cache = {}
    return cache[k] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "volatile-key escaped write must not leak into a fresh shadow (no FP)")

src10 = [=[
local cache = {}
local function Read()
    do
        local cache = {}
        Register(cache)
        cache[1] = S()
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "escaped shadow write stays heap-readable through the OUTER binding (round-8h)")

src10 = [=[
local cache = {}
local function Read()
    do
        local cache = {}
        Register(cache)
        cache[1] = S()
    end
    local cache = GetRegistered()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a non-fresh shadow may alias the escaped table: evidence stays usable")

-- Closure capture is an escape (round-8l; Codex counterexample #5): a
-- captured constructor local is private only syntactically — the closure
-- reads/writes THE SAME table, so its privacy must break.
src10 = [=[
local function Outer()
    local cache = {}
    local fill = function() cache[1] = S() end
    fill()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a closure writing a captured fresh local taints the parent's read")

src10 = [=[
local function Outer()
    local cache = {}
    local function fill() cache[1] = S() end
    fill()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a `local function` closure capture escapes the parent binding too")

-- Capture detection is lexically scope-aware (Codex counterexample #6): a
-- closure whose OWN param/local shadows the name captures nothing — the
-- parent binding keeps its privacy.
src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    local cache = {}
    local helper = function(cache) print(cache) end
    helper(1)
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a shadow-only closure PARAM must not escape the parent's private binding (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    local cache = {}
    local function helper(cache) print(cache) end
    helper(1)
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a shadow-only `local function` param must not escape the parent binding (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    local cache = {}
    local helper = function() local cache = {} print(cache) end
    helper()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a closure-own LOCAL shadow must not escape the parent binding (no FP)")

src10 = [=[
local function Outer()
    local cache = {}
    local fill = function()
        cache[1] = S()
        local cache = {}
        print(cache)
    end
    fill()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a use BEFORE the closure's own binding is still a capture")

src10 = [=[
local function Outer()
    local cache = {}
    local mk = function()
        return function() cache[1] = S() end
    end
    mk()()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a capture two closures deep still escapes the outermost binding")

-- Colon methods bind an implicit `self` the parser omits from Arguments
-- (Codex counterexample #7): a method body's `self` is the method's own
-- binding, not a capture of an enclosing local named self.
src10 = [=[
local self = {}
local function Fill()
    self[1] = S()
end
local function Read()
    local self = {}
    local obj = {}
    function obj:m() print(self) end
    obj:m()
    return self[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a colon method's implicit self must not escape an enclosing self shadow (no FP)")

src10 = [=[
local self = {}
local function Fill()
    self[1] = S()
end
local function Read()
    local self = {}
    local obj = {}
    function obj.m() print(self) end
    obj.m()
    return self[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a DOT function's self is a genuine capture: the shadow escapes and reads flag")

src10 = [=[
local function Outer()
    local cache = {}
    local obj = {}
    function obj:fill() cache[1] = S() end
    obj:fill()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a colon method capturing a NON-self binding still escapes it")

-- Declarations are field writes, not receiver escapes (round-8p; Codex
-- counterexample #8): `function self:m()` on the private binding itself
-- must not break its privacy — the colon binds self at CALL time only.
src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Read()
    local cache = {}
    function cache:m() end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a colon declaration ON the private binding is a field write, not an escape (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read()
    local cache = {}
    cache:resolve()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a method CALL still escapes the receiver (self passes at call time)")

-- A colon method's implicit self is PRIVATE by default (#8b): its body
-- must not inherit an unrelated chunk-local `self` table's seed.
src10 = [=[
local self, obj = {}, {}
local function Fill()
    self[1] = S()
end
function obj:m() return self[1] or DEFAULT end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a colon method body's implicit self ignores the chunk-self seed (no FP)")

src10 = [=[
local self, obj = {}, {}
local function Fill()
    self[1] = S()
end
function obj.m() return self[1] or DEFAULT end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a DOT function body's self is the chunk binding and reads its seed")

-- Upvalue reads inside nested closures (#8c): a name bound in an
-- enclosing function is that function's binding — it matches inherited
-- ("enclosing") evidence but never the chunk seed of the same name.
src10 = [=[
local self, obj = {}, {}
local function Fill()
    self[1] = S()
end
function obj:m()
    local g = function() return self[1] or DEFAULT end
    return g()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a closure inside a colon method reads the METHOD's self, not the chunk seed (no FP)")

src10 = [=[
local function Outer()
    local t = {}
    t.f = S()
    local g = function()
        t.f = S()
        return t.f or DEFAULT
    end
    return g
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an upvalue write-then-read inside one closure still flags (enclosing provenance)")

-- Upvalue-ness is per NODE at the closure's lexical position (Codex
-- counterexample #9): a local declared AFTER the closure, or only in a
-- closed sibling block, does not enclose it — the closure's name is the
-- chunk binding and keeps the seed.
src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Outer()
    local g = function() return cache[1] or DEFAULT end
    local cache = {}
    return g()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a local declared AFTER the closure does not enclose it (seed kept)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Outer()
    local g = function() return cache[1] or DEFAULT end
    do local cache = {} end
    return g()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a sibling-block local does not enclose the closure (seed kept)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Outer()
    local cache = {}
    cache[1] = S()
    local g = function() return cache[1] or DEFAULT end
    return g()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a true enclosing local's OWN write reaches its captured upvalue read ('both' provenance)")

src10 = [=[
local cache = {}
local function Fill()
    cache[1] = S()
end
local function Outer()
    local cache = {}
    local g = function() return cache[1] or DEFAULT end
    return g()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a pristine enclosing local blocks the chunk seed for its captured reads (no FP)")

-- Ancestry identity survives any nesting depth (Codex counterexample
-- #10): chunk-seed + enclosing-local evidence on one key must not leak
-- into a DIFFERENT function's fresh same-named local, even when that
-- local is captured by its own closure. Qualified binding IDs — no class
-- flattening.
src10 = [=[
local cache = {}
local function FillChunk()
    cache[1] = S()
end
local function Outer()
    local cache = {}
    cache[1] = S()
    local function Middle()
        local cache = {}
        local read = function() return cache[1] or DEFAULT end
        return read()
    end
    return Middle()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "merged chunk+enclosing evidence must not taint a nested fresh shadow's captured read (no FP)")

src10 = [=[
local cache = {}
local function FillChunk()
    cache[1] = S()
end
local function Outer()
    local cache = {}
    cache[1] = S()
    local function Middle()
        local cache = {}
        cache[1] = S()
        local read = function() return cache[1] or DEFAULT end
        return read()
    end
    return Middle()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "the nested local's OWN write still reaches its captured read (binding identity)")

-- Same-name localization preserves QUALIFIED identity (Codex
-- counterexample #11): `local cache = cache` inside a closure aliases the
-- captured ENCLOSING binding, not the chunk one — mapping it to "outer"
-- let the alias consume an unrelated chunk seed.
src10 = [=[
local cache = {}
local function FillChunk()
    cache[1] = S()
end
local function Outer()
    local cache = {}
    local function Middle()
        local cache = cache
        return cache[1] or DEFAULT
    end
    return Middle()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "nested localize of a pristine enclosing cache must not consume the chunk seed (no FP)")

src10 = [=[
local cache = {}
local function FillChunk()
    cache[1] = S()
end
local function Outer()
    local cache = {}
    cache[1] = S()
    local function Middle()
        local cache = cache
        return cache[1] or DEFAULT
    end
    return Middle()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "nested localize still reads the enclosing binding's own write (identity kept)")

src10 = [=[
local function Outer()
    local cache = {}
    cache[1] = S()
    local cache = cache
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "same-function localize aliases the written local's binding")

-- Rebinding SPLITS identity (Codex counterexample #12): after
-- `cache = {}` the NAME holds a new value — evidence recorded against the
-- old binding must not follow it.
src10 = [=[
local function Outer()
    local cache = {}
    local function MutateCaptured() cache[1] = S() end
    local function Middle()
        local cache = cache
        cache = {}
        MutateCaptured()
        return cache[1] or DEFAULT
    end
    return Middle()
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a captured write to the OLD table must not taint the rebound alias (no FP)")

src10 = [=[
local function Outer()
    local cache = {}
    local function MutateOld() cache[1] = S() end
    local cache = cache
    MutateOld()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an UNREBOUND alias still sees the captured write (identity kept)")

src10 = [=[
local cache = {}
local function Outer()
    local cache = {}
    cache[1] = S()
    cache = {}
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a write before a fresh rebind stays with the OLD binding (no FP)")

src10 = [=[
local cache = {}
local function Outer()
    local cache = {}
    cache = {}
    cache[1] = S()
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a write AFTER the rebind flags through the new binding identity")

-- Identity splits only in the binding's DECLARING block (Codex
-- counterexample #13): a rebind inside a conditional/loop may never
-- execute — the not-taken path's taint must survive, so identity stays
-- shared and privacy is conservatively canceled instead.
src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    if cond then
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a CONDITIONAL rebind keeps the not-taken path's taint alive")

src10 = [=[
local function Outer(n)
    local cache = {}
    cache[1] = S()
    for i = 1, n do
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a LOOP-body rebind may run zero times: the taint survives")

src10 = [=[
local function Outer()
    local cache = {}
    cache[1] = S()
    cache = cache
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a self-rebind names the SAME table: the taint survives")

-- Dominating nested rebinds ARE definite (Codex counterexample #14):
-- do/repeat bodies always execute, and an if/else that rebinds in EVERY
-- arm leaves the old binding unreachable.
src10 = [=[
local function Outer()
    local cache = {}
    cache[1] = S()
    do cache = {} end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a do-block rebind executes unconditionally: the old taint is unreachable (no FP)")

src10 = [=[
local function Outer(done)
    local cache = {}
    cache[1] = S()
    repeat cache = {} until done
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a repeat-body rebind runs at least once: the old taint is unreachable (no FP)")

src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    if cond then cache = {} else cache = {} end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "fresh rebinds in EVERY if/else arm merge to a clean identity (no FP)")

src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    if cond then cache = {} elseif not cond then cache = {} end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an elseif chain WITHOUT else is not definite: the taint survives")

src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    if cond then cache = {} else cache = GetCache() end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a non-fresh arm keeps the merged identity aliasable: the taint survives")

src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    if cond then do cache = {} end end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a do-block INSIDE a single if arm stays conditional: the taint survives")

-- Break-aware repeat dominance (Codex counterexample #15): at-least-once
-- is block-ENTRY truth — a break can bypass a later rebind, so a repeat
-- body with its own break is not assignment-dominating.
src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then break end
        cache = {}
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a break BEFORE the repeat rebind keeps the bypassed path's taint")

src10 = [=[
local function Outer(done, n)
    local cache = {}
    cache[1] = S()
    repeat
        for i = 1, n do break end
        cache = {}
    until done
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a break in a NESTED loop addresses that loop: the repeat still dominates (no FP)")

src10 = [=[
local function Outer(outer, c)
    local cache = {}
    cache[1] = S()
    if outer then
        if c then cache = {} else cache = {} end
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an all-arms merge nested in a SINGLE if arm stays conditional: the taint survives")

-- Break handling is ORDER-aware (Codex counterexample #16): a break can
-- only bypass statements AFTER it — a rebind walked before the repeat's
-- first addressing break keeps its dominance.
src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    repeat
        cache = {}
        if cond then break end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a break AFTER the repeat rebind cannot bypass it: old taint unreachable (no FP)")

src10 = [=[
local function Outer(cond, stop)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then cache = {} else cache = {} end
        if stop then break end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "an all-arms merge BEFORE the repeat's break keeps its split (no FP)")

src10 = [=[
local function Outer(cond)
    local cache = {}
    repeat
        if cond then break end
        cache = {}
        cache[1] = S()
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "taint written AFTER a break-downgraded rebind still flags")

-- Arm-local breaks vs the all-arms merge (Codex counterexample #17): a
-- break AFTER its arm's rebind cannot bypass it — every exit path already
-- replaced the table, so the merge stands. A break BEFORE the arm's
-- rebind (or an arm that only breaks) defeats it.
src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            cache = {}
            break
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "an arm break AFTER every-arm rebinds keeps the merge (no FP)")

src10 = [=[
local function Outer(cond, z)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            if z then break end
            cache = {}
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a conditional break BEFORE the arm's rebind defeats the merge (sticky closure)")

src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            break
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an arm that only breaks leaves the old table reachable: the taint survives")

-- A break addressing a loop ENTERED WITHIN the arm exits only that loop
-- (Codex counterexample #18): the arm continues, so the every-arm rebind
-- merge stands.
src10 = [=[
local function Outer(cond, n)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            for i = 1, n do break end
            cache = {}
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a nested-loop break inside the arm must not defeat the every-arm merge (no FP)")

src10 = [=[
local function Outer(cond, done)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            repeat break until done
            cache = {}
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "an inner repeat's break stays local to it: the merge stands (no FP)")

-- Break depth propagates across inner if/else collector boundaries (Codex
-- counterexample #19): a nested-loop break wrapped in if/else is still
-- loop-local; an ARM-escaping break wrapped the same way still defeats
-- the merge.
src10 = [=[
local function Outer(cond, n, z)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            for i = 1, n do
                if z then
                    break
                else
                    local x = i
                end
            end
            cache = {}
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "an if/else-wrapped nested-loop break keeps the every-arm merge (no FP)")

src10 = [=[
local function Outer(cond, z)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            if z then
                break
            else
                local x = 1
            end
            cache = {}
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an if/else-wrapped ARM-escaping break still defeats the merge (depth carried)")

-- Nested pre-break rebinds propagate BEFORE the escape closes the outer
-- collector (Codex counterexample #20): every counted arm rebinds before
-- its own break, so the inner merge precedes any escape.
src10 = [=[
local function Outer(outer, inner)
    local cache = {}
    cache[1] = S()
    repeat
        if outer then
            if inner then
                cache = {}
                break
            else
                cache = {}
            end
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a nested all-arm rebind before a same-loop break keeps the outer merge (no FP)")

src10 = [=[
local function Outer(outer, inner)
    local cache = {}
    repeat
        if outer then
            if inner then
                cache = {}
                break
            else
                cache = {}
            end
            cache = {}
            cache[1] = S()
        else
            cache = {}
            cache[1] = S()
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "fall-through re-taint after the arm's escape still reaches the read")

src10 = [=[
local function Outer(cond)
    local cache = {}
    repeat
        if cond then
            cache = {}
            cache[1] = S()
        else
            cache = {}
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a field write into the fresh arm rebind defeats the merge's privacy")

-- Freshness clearing keys on the WRITE's shape and escapes flow into the
-- merge (Codex counterexample #21): benign literal initialization keeps
-- privacy; a whole-value escape in every arm widens the merged identity.
src10 = [=[
local function Outer(cond)
    local cache = {}
    cache[1] = S()
    repeat
        if cond then
            cache = {}
            cache.version = 1
        else
            cache = {}
            cache.version = 1
        end
    until true
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a clean literal field init after the arm rebind keeps merge privacy (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond)
    local cache = {}
    if cond then
        cache = {}
        Register(cache)
    else
        cache = {}
        Register(cache)
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a whole-value escape in EVERY arm makes the merged identity heap-readable")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond, v)
    local cache = {}
    if cond then
        cache = {}
        cache[1] = v
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an unknown-variable field write still defeats merge privacy")

-- Closure-side escapes reach the arm merge (Codex counterexample #22):
-- the collector is suspended for RECORDS inside a closure, but escape
-- marks apply — a capture-escape holds from closure creation.
src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond)
    local cache = {}
    if cond then
        cache = {}
        local cb = function() Register(cache) end
        Register(cb)
    else
        cache = {}
        local cb = function() Register(cache) end
        Register(cb)
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a registered closure escaping the arm value defeats merge privacy")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond)
    local cache = {}
    if cond then
        cache = {}
        local cb = function() return cache[2] end
        Register(cb)
    else
        cache = {}
        local cb = function() return cache[2] end
        Register(cb)
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a field-only reading closure keeps the merge's privacy (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond)
    local cache = {}
    if cond then
        cache = {}
        local cb = function() cache[1] = S() end
        cb()
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a tainted write through a capture defeats the merge's privacy")

-- Collector updates require BINDING identity (Codex counterexample #23):
-- a same-named block shadow is a different table — its escapes and writes
-- must not corrupt the enclosing arm's record.
src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond)
    local cache = {}
    if cond then
        cache = {}
        do
            local cache = {}
            local cb = function() Register(cache) end
            Register(cb)
        end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a captured block-shadow escape must not mark the arm's record escaped (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond)
    local cache = {}
    if cond then
        cache = {}
        do
            local cache = {}
            cache[1] = S()
        end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a block-shadow tainted write must not clear the arm record's freshness (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond, v)
    local cache = {}
    if cond then
        cache = {}
        do
            local cache = {}
            Register(cache)
        end
        cache[1] = v
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "the ARM binding's own write after a shadow block still defeats privacy")

-- Records propagate outward only for bindings that SURVIVE the clause
-- (Codex counterexample #24): a same-named shadow's nested merge or
-- conditional rebind dies with its block and must not clobber the
-- enclosing arm's record.
src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond, inner)
    local cache = {}
    if cond then
        cache = {}
        do
            local cache = {}
            if inner then
                cache = {}
            else
                cache = {}
            end
        end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a nested SHADOW's all-arm merge must not clobber the enclosing record (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond, z)
    local cache = {}
    if cond then
        cache = {}
        do
            local cache = {}
            if z then cache = GetCache() end
        end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a SHADOW's conditional rebind must not record into the enclosing collector (no FP)")

src10 = [=[
local cache = {}
local function Fill()
    Register(cache)
    cache[1] = S()
end
local function Read(cond)
    local cache = {}
    if cond then
        cache = {}
        do
            local cache = cache
            cache[1] = S()
        end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a same-binding LOCALIZATION's tainted write still defeats privacy (alias, not shadow)")

-- Field activity after an all-arms fresh rebind is key-sensitive.  The old
-- boolean "not fresh" widening both lost nested writes and revived stale
-- evidence for unrelated fields.
src10 = [=[
local function Read(cond, inner)
    local cache = {}
    if cond then
        cache = {}
        if inner then
            cache[1] = S()
        else
            cache[1] = S()
        end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "nested all-arm field writes reach the enclosing merge")

src10 = [=[
local function Read(cond, inner)
    local cache = {}
    if cond then
        cache = {}
        if inner then cache[1] = S() end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "nested else-less activity unions its written and fall-through paths")

src10 = [=[
local function Read(cond)
    local cache = {}
    cache[1] = S()
    if cond then
        cache = {}
        cache[2] = S()
    else
        cache = {}
        cache[2] = S()
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "dirty field 2 must not revive the replaced table's stale field 1 (no FP)")

src10 = [=[
local function Read(cond, inner)
    local cache = {}
    cache[1] = S()
    if cond then
        cache = {}
        cache[1] = S()
        if inner then
            cache[1] = 1
        else
            cache[1] = 1
        end
    else
        cache = {}
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "clean overwrite on every nested path clears merged field activity (no FP)")

src10 = [=[
local function Read(cond)
    local cache = {}
    cache[1] = S()
    if cond then
        cache = {}
        cache.meta = { version = 1 + 2 }
    else
        cache = {}
        cache.meta = { version = 3 }
    end
    return cache[1] or DEFAULT
end
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "recursively clean constructor writes preserve field privacy (no FP)")

-- ROUND-10d: literal-key canonicalization. Boolean, negative, arithmetic
-- and escaped-string keys are stable runtime identities — writes and
-- and/or reads must unify exactly like `c[1]` (each shape previously
-- produced ZERO findings).
src10 = [=[
local c = {}
c[true] = S()
return c[true] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "boolean-keyed secret write is visible to the boolean-keyed or-read")

src10 = [=[
local c = {}
c[false] = S()
return c[true] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "the two boolean keys stay distinct slots (no FP)")

src10 = [=[
local c = {}
c[-1] = S()
return c[-1] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "negative-number key canonicalizes through the unary fold")

src10 = [=[
local c = {}
c[1+1] = S()
return c[2] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "constant arithmetic folds onto the equal literal key")

src10 = [=[
local c = {}
c["a\nb"] = S()
return c["a\nb"] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "escaped-string keys decode to one runtime identity")

src10 = [=[
local h = { ["a\nb"] = S() }
return h["a\nb"] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "constructor escaped-string keys spell exactly like the bracket read")

-- Call-based keys have NO stable identity: the write records a
-- contamination marker on the chain's stable prefix and the un-keyable
-- read must consult it (probe pairing is impossible for either side).
src10 = [=[
local c = {}
c[K()] = S()
return c[K()] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "call-keyed write contaminates the container; the call-keyed or-read flags")

src10 = [=[
local c = {}
local d = {}
d[K()] = S()
return c[K()] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a clean container's call-keyed read does not borrow another table's marker (no FP)")

-- ROUND-10d: constructor table-reference entries are LIVE aliases —
-- `{cache = c}` links "h.cache" to c like the assignment `h.cache = c`
-- would; a LATER secret write through `c` must be visible through the
-- constructor spelling (keyed, list-style, and nested).
src10 = [=[
local c = {}
local h = { cache = c }
c.foo = S()
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "keyed constructor entry aliases the referenced table")

src10 = [=[
local c = {}
local h = { c }
c.foo = S()
return h[1].foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "list-style constructor entry aliases the referenced table")

src10 = [=[
local c = {}
local h = { a = { cache = c } }
c.foo = S()
return h.a.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "nested constructor entry aliases through the inner table")

src10 = [=[
local c = {}
local d = {}
local h = { cache = c }
d.foo = S()
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "constructor alias to a table that stays clean reads clean (no FP)")

-- ROUND-10d: a DEFINITE straight-line root rebind replaces the table —
-- stale descendant taint under the rebound name must not flag the fresh
-- table's reads. (The conditional/loop conservatism fixtures live above:
-- those rebinds may run zero times and keep the taint.)
src10 = [=[
local c = {}
c.foo = S()
c = {}
return c.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "definite root rebind clears the old table's descendant taint (no FP)")

src10 = [=[
local c = {}
c[K()] = S()
c = {}
return c[K()] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "definite root rebind clears volatile markers under the old name (no FP)")

src10 = [=[
local c = {}
local keep = c
c.foo = S()
c = {}
return keep.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "surviving alias keeps the OLD table's evidence across the rebind")

src10 = [=[
local c = {}
c.foo = S()
c = {}
c.foo = S()
return c.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a fresh write after the rebind flags through the new table")

-- ROUND-10d: CONDITIONAL aliases persist as MAY-aliases. A merge that
-- drops a disagreeing alias link while its targets are still clean must
-- not hide a LATER secret write through either spelling (Codex catch:
-- conditional constructor aliases hid secret-tainted paths).
src10 = [=[
local c = {}
local h = {}
while X do
    h = { cache = c }
end
c.foo = S()
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "loop-body constructor alias survives the merge as a may-alias")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "one-branch constructor alias catches taint written after the merge")

src10 = [=[
local c = {}
local d = {}
local h
if X then
    h = { cache = c }
else
    h = { cache = d }
end
c.foo = S()
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "divergent branch aliases keep BOTH may-targets visible")

src10 = [=[
local c = {}
local h = {}
while X do
    h = c
end
h.foo = S()
return c.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "may-aliasing is symmetric: a write through the poisoned name reads through the target")

src10 = [=[
local c = {}
local d = {}
local h
if X then
    h = { cache = c }
else
    h = { cache = d }
end
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "clean may-alias targets read clean (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.bar = S()
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "may-alias hop stays slot-precise: taint on a SIBLING key does not flag (no FP)")

-- ROUND-10d follow-up (Codex catch: may-alias FN/FP): DOMINATING rebinds
-- sever stale may-links (the fresh table's spelling must not read the
-- old may-target); non-dominating rebinds keep them; volatile reads hop
-- may-links like live ones.
src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
h = {}
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "dominating ROOT rebind severs the may-link: the fresh table reads clean (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
h.cache = {}
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "dominating SLOT rebind severs the may-link (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
if Y then
    h = {}
end
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a CONDITIONAL rebind keeps the may-link: the not-taken path still aliases")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
h.cache.foo = S()
h = {}
return c.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "severing mirrors the dying spelling's keys to the surviving may-target first")

src10 = [=[
local c = {}
local h = {}
while X do
    h = { cache = c }
end
c[1] = S()
return h.cache[k] or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "volatile reads hop may-links exactly like live chain aliases")

-- ROUND-10d follow-up 2 (Codex catch: blanket branch/loop suppression):
-- may-links are PATH state — snapshot per clause, union over reachable
-- exits — so GUARANTEED replacement severs even inside control flow.
src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
if Y then
    h = {}
else
    h = {}
end
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "an ALL-ARMS rebind is guaranteed replacement: the may-link severs (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    h = {}
until Y
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a REPEAT-body rebind runs at least once: the may-link severs (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
do
    h = {}
end
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a DO-block rebind always runs: the may-link severs (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
while Y do
    h = {}
end
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a WHILE-body rebind may run zero times: the may-link survives")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
if Y then
    h = { cache = c }
else
    h = {}
end
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "an all-arms rebind where one arm RE-LINKS keeps the link")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
if Y then
    h = {}
    return nil
end
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a TERMINATING arm's sever rolls back: the surviving path still aliases")

-- ROUND-10d follow-up 3 (Codex catch: pre-rebind break): a DIRECT break
-- in a repeat body is an exit path that can bypass the rebind — repeat
-- then re-admits the entry state, keeping the may-link. Breaks inside
-- NESTED loops bind those loops and do not.
src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    if Y then break end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a pre-rebind break in a repeat body keeps the may-link alive")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    do
        if Y then break end
    end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a break nested in if/do blocks still escapes the repeat body")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    while A do break end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a break belonging to a NESTED loop does not weaken the repeat sever (no FP)")

-- ROUND-10d follow-up 4 (Codex catch: statement-order FP): each break
-- site contributes ITS OWN state snapshot to the repeat merge — a break
-- AFTER the rebind exits with the replacement already done.
src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    h = {}
    if Y then break end
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a POST-rebind break still exits with the replacement: the sever sticks (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    h = {}
    if Y then break end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "every exit path (break and fall-through) saw a rebind: severed (no FP)")

-- ROUND-10d follow-up 5 (Codex catch: unreachable break sites): a break
-- that dead code can never reach (after a terminating do-block,
-- all-arms-return if, or error()) must not contribute an exit snapshot.
src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    if Y then
        do return nil end
        break
    end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a DEAD break site (terminating do-block above) contributes no snapshot (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    if Y then
        error("boom")
        break
    end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a DEAD break site (error() above) contributes no snapshot (no FP)")

src10 = [=[
local error = print
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    if Y then
        error("boom")
        break
    end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a SHADOWED error() forfeits terminator status: the break stays live")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    if Y then
        if W then
            return nil
        end
        break
    end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a break after a NON-terminating if stays a live exit path")

-- ROUND-10d follow-up 6 (Codex catch: loop-exit wrappers): flow also
-- ends through a bare break, a `do break end` wrapper, or an
-- all-arms-break if — dead statements after them (re-links, severs,
-- break sites) are skipped outright, never walked into flow state.
src10 = [=[
local c = {}
local h = {}
c.foo = S()
repeat
    h = {}
    if Y then
        do break end
        h = { cache = c }
        break
    end
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "a dead re-link + dead break after a do-break wrapper stay out of flow state (no FP)")

src10 = [=[
local c = {}
local h = {}
c.foo = S()
repeat
    h = {}
    if Y then
        break
    else
        break
    end
    h = { cache = c }
    if W then break end
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 0,
    "dead code after an all-arms-break if stays out of flow state (no FP)")

src10 = [=[
local c = {}
local h = {}
if X then
    h = { cache = c }
end
c.foo = S()
repeat
    if Y then
        do break end
    end
    h = {}
until Z
return h.cache.foo or DEFAULT
]=]
assert_eq(#Analyzer.analyze(src10, "modules/foo.lua", r10, cfg), 1,
    "a LIVE do-break wrapper before the rebind still keeps the link")

-- ROUND-10d follow-up 7 (Codex catch: dead loop-exit code contaminated
-- the event-handler linkage): a RegisterEvent in dead code never
-- executes — it must not link a LIVE handler's payload params.
do
    local rDead = Registry.new()
    rDead:addSecretPayloadEvent("UNIT_AURA", { 4 })
    local srcDead = [=[
local f = CreateFrame("Frame")
while true do
    do break end
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 0,
        "a DEAD RegisterEvent does not link the live handler (no FP)")
    srcDead = [=[
local f = CreateFrame("Frame")
repeat
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(self, event, unit, info)
        if info then return end
    end)
    break
until true
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 1,
        "a registration BEFORE the break stays a live linkage")

    -- ROUND-10d follow-up 8 (Codex catch: unconditional repeat
    -- termination): a loop whose exit is provably never reached —
    -- break-free repeat with a terminating body or `until false`,
    -- break-free `while true` — ends flow; code after it is dead.
    srcDead = [=[
local f = CreateFrame("Frame")
local function Setup()
    repeat
        return nil
    until X
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 0,
        "a dead RegisterEvent after an always-returning repeat does not link (no FP)")

    srcDead = [=[
local f = CreateFrame("Frame")
local function Setup()
    while true do
        DoWork()
    end
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 0,
        "a dead RegisterEvent after a break-free `while true` does not link (no FP)")

    srcDead = [=[
local f = CreateFrame("Frame")
local function Setup()
    repeat
        if Y then break end
        return nil
    until X
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 1,
        "a direct break makes the post-repeat registration reachable again")

    -- ROUND-10d follow-up 9 (Codex catch: the direct-break scan revived
    -- dead post-loop code): only REACHABLE breaks make the post-loop
    -- position live — a break in dead code (after a terminating
    -- do-block) never executes, and a dead trailing break must not mask
    -- a body that always returns.
    srcDead = [=[
local f = CreateFrame("Frame")
local function Setup()
    repeat
        do return nil end
        break
    until X
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 0,
        "a DEAD trailing break does not revive post-repeat code (no FP)")

    srcDead = [=[
local f = CreateFrame("Frame")
local function Setup()
    repeat
        if Y then
            break
        else
            return nil
        end
    until X
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 1,
        "a live break INSIDE an all-arms flow-ender still reaches post-loop code")

    -- ROUND-10d follow-up 10 (Codex catch: last-statement checks inside
    -- if/do wrappers): a clause/do body ends flow when any REACHABLE
    -- statement ends it — a dead trailing call must not mask the ender.
    srcDead = [=[
local f = CreateFrame("Frame")
local function Setup()
    repeat
        if Y then
            do return nil end
            DoWork()
        else
            return nil
        end
    until X
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 0,
        "a dead trailing call after the clause's flow-ender does not mask it (no FP)")

    srcDead = [=[
local f = CreateFrame("Frame")
local function Setup()
    repeat
        if Y then
            DoWork()
        else
            return nil
        end
    until X
    f:RegisterEvent("UNIT_AURA")
end
f:SetScript("OnEvent", function(self, event, unit, info)
    if info then return end
end)
]=]
    assert_eq(#Analyzer.analyze(srcDead, "modules/foo.lua", rDead, cfg), 1,
        "a clause with NO flow-ender keeps the post-loop position reachable")
end

print("round-10 structural coverage test passed")
end)()

-- ROUND-11: adversarial state-model coverage.  These are semantic
-- equivalence families rather than one-off spellings: assignment ordering,
-- lexical binding identity, loop exits/back-edges, key identity, and alias
-- reachability must not change merely because the source is re-spelled.
;(function()
    local r11 = Registry.new()
    r11:addSource("S")

    local function findingsFor(source)
        local findings, err = Analyzer.analyze(source, "modules/foo.lua", r11, cfg)
        assert(findings, "round-11 source failed to parse: " .. tostring(err))
        return #findings
    end

    local soundCases = {
        { "two-way table swap", [=[
local x, y = {}, {}
x.foo = S()
x, y = y, x
return y.foo or DEFAULT
]=] },
        { "reverse-spelled two-way table swap", [=[
local x, y = {}, {}
x.foo = S()
y, x = x, y
return y.foo or DEFAULT
]=] },
        { "three-way table rotation", [=[
local a, b, c = {}, {}, {}
a.foo = S()
a, b, c = b, c, a
return c.foo or DEFAULT
]=] },
        { "simultaneous root rebind keeps the old LHS address", [=[
local x = {}
local keep = x
x, x.foo = {}, S()
return keep.foo or DEFAULT
]=] },
        { "negative-zero write aliases zero read", [=[
local t = {}
t[-0] = S()
return t[0] or DEFAULT
]=] },
        { "zero write aliases negative-zero read", [=[
local t = {}
t[0] = S()
return t[-0] or DEFAULT
]=] },
        { "computed constructor key keeps a table may-alias", [=[
local c = {}
local h = { [K()] = c }
c.foo = S()
return h[K()].foo or DEFAULT
]=] },
        { "computed assignment key keeps a table may-alias", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
return h[K()].foo or DEFAULT
]=] },
        { "variable assignment key keeps a forward table may-alias", [=[
local c, h = {}, {}
local k = K()
h[k] = c
c.foo = S()
return h[k].foo or DEFAULT
]=] },
        { "variable assignment key keeps a reverse table may-alias", [=[
local c, h = {}, {}
local k = K()
h[k] = c
h[k].foo = S()
return c.foo or DEFAULT
]=] },
        { "wildcard assignment alias reaches a deterministic read key", [=[
local c, h = {}, {}
h["a" .. "b"] = c
c.foo = S()
return h.ab.foo or DEFAULT
]=] },
        { "while zero-iteration scalar exit", [=[
local x = S()
while C do x = 1 end
return x and 1
]=] },
        { "while zero-iteration field exit", [=[
local t = GetCache()
t.foo = S()
while C do t.foo = 1 end
return t.foo or DEFAULT
]=] },
        { "repeat pre-rebind break scalar exit", [=[
local x = S()
repeat
    if C then break end
    x = 1
until DONE
return x and 1
]=] },
        { "repeat pre-rebind break field exit", [=[
local t = GetCache()
t.foo = S()
repeat
    if C then break end
    t.foo = 1
until DONE
return t.foo or DEFAULT
]=] },
        { "loop convergence beyond two iterations", [=[
local a, b, c, d = S(), nil, nil, nil
while C do
    d, c, b, a = c, b, a, nil
end
return d and 1
]=] },
        { "while condition is checked on the back-edge", [=[
local x = 1
while x do
    x = S()
end
]=] },
        { "repeat body locals remain visible to the until condition", [=[
repeat
    local x = S()
until x
]=] },
        { "simultaneous aliases converge through a loop back-edge", [=[
local x, y = {}, {}
x.foo = S()
while C do
    x, y = y, x
end
return x.foo or y.foo or DEFAULT
]=] },
        { "outer scalar survives a clean do-local shadow", [=[
local x = S()
do local x = 1; Use(x) end
return x and 1
]=] },
        { "outer alias survives a clean do-local shadow", [=[
local c = {}
local h = c
do local h = {} end
c.foo = S()
return h.foo or DEFAULT
]=] },
        { "outer alias remains usable inside a root-name shadow", [=[
local c = {}
local h = c
do
    local c = {}
    h.foo = S()
end
return h.foo or DEFAULT
]=] },
        { "exact alias reachability has no hop ceiling", (function()
            local lines = { "local t0 = {}", "t0.foo = S()" }
            for i = 1, 12 do
                lines[#lines + 1] = ("local t%d = {}"):format(i)
                lines[#lines + 1] = ("t%d.x = t%d"):format(i, i - 1)
            end
            local expr = "t12"
            for _ = 1, 12 do expr = expr .. ".x" end
            lines[#lines + 1] = "return " .. expr .. ".foo or DEFAULT"
            return table.concat(lines, "\n")
        end)() },
        { "same-file source wrapper return", [=[
local function GetSecret()
    return S()
end
local x = GetSecret()
return x and 1
]=] },
        { "same-file parameter-to-return flow", [=[
local function Identity(value)
    return value
end
local x = Identity(S())
return x and 1
]=] },
        { "same-file tainted parameter reaches a callee sink", [=[
local function Consume(value)
    return value + 1
end
Consume(S())
]=] },
        { "same-file summaries compose through local temporaries", [=[
local function Identity(value)
    local copy = value
    return copy
end
local function Outer(value)
    return Identity(value)
end
return Outer(S()) and 1
]=] },
        { "same-file callee sink summaries compose", [=[
local function Consume(value)
    Use(value + 1)
end
local function Forward(value)
    Consume(value)
end
Forward(S())
]=] },
        { "block-local same-file helper is collected in its lexical scope", [=[
do
    local function Identity(value)
        return value
    end
    return Identity(S()) and 1
end
]=] },
        { "nested same-file helper composes through its outer wrapper", [=[
local function Outer(value)
    local function Identity(inner)
        return inner
    end
    return Identity(value)
end
return Outer(S()) and 1
]=] },
        { "straight-line same-file function alias preserves summary identity", [=[
local function Identity(value)
    return value
end
local Alias = Identity
return Alias(S()) and 1
]=] },
        { "same-file function alias chains preserve summary identity", [=[
local function Identity(value)
    return value
end
local First = Identity
local Second = First
return Second(S()) and 1
]=] },
        { "same-file sink summary flows through a function alias", [=[
local function Consume(value)
    return value + 1
end
local Alias = Consume
Alias(S())
]=] },
        { "function alias captures the value before its source binder rebinds", [=[
local function Identity(value)
    return value
end
local Alias = Identity
Identity = function()
    return 1
end
return Alias(S()) and 1
]=] },
        { "nested wrapper resolves a clean-to-forward callee at invocation time", [=[
local function Identity()
    return 1
end
local function Outer(value)
    return Identity(value)
end
Identity = function(value)
    return value
end
return Outer(S()) and 1
]=] },
        { "named function statement installs its new helper summary", [=[
local function Identity()
    return 1
end
function Identity(value)
    return value
end
return Identity(S()) and 1
]=] },
        { "parenthesized assignment installs its new helper summary", [=[
local function Identity()
    return 1
end
(Identity) = function(value)
    return value
end
return Identity(S()) and 1
]=] },
        { "unconditional do rebind installs its new helper summary", [=[
local function Identity()
    return 1
end
do
    Identity = function(value)
        return value
    end
end
return Identity(S()) and 1
]=] },
        { "exhaustive helper rebind installs every possible new summary", [=[
local function Identity()
    return 1
end
if C then
    Identity = function(value)
        return value
    end
else
    Identity = function(value)
        return value
    end
end
return Identity(S()) and 1
]=] },
        { "invoked wrapper sees its clean-to-forward upvalue rebind", [=[
local function Identity()
    return 1
end
local function Outer(value)
    Identity = function(inner)
        return inner
    end
    return Identity(value)
end
return Outer(S()) and 1
]=] },
        { "wrapper alias captures its clean-to-forward upvalue rebind", [=[
local function Identity()
    return 1
end
local function Outer(value)
    Identity = function(inner)
        return inner
    end
    local Alias = Identity
    return Alias(value)
end
return Outer(S()) and 1
]=] },
        { "nested wrapper inherits a clean-to-forward invocation rebind", [=[
local function Identity()
    return 1
end
local function Middle(value)
    return Identity(value)
end
local function Outer(value)
    Identity = function(inner)
        return inner
    end
    return Middle(value)
end
return Outer(S()) and 1
]=] },
        { "nested wrapper alias inherits a clean-to-forward invocation rebind", [=[
local function Identity()
    return 1
end
local function Middle(value)
    local Alias = Identity
    return Alias(value)
end
local function Outer(value)
    Identity = function(inner)
        return inner
    end
    return Middle(value)
end
return Outer(S()) and 1
]=] },
        { "unrelated parameter spelling does not invalidate a helper summary", [=[
local function Identity(value)
    return value
end
local function Other(Identity)
    return Identity
end
local value = Identity(S())
return value and 1
]=] },
        { "unrelated local spelling does not invalidate a helper summary", [=[
local function Identity(value)
    return value
end
local function Other()
    local Identity = {}
    return Identity
end
local value = Identity(S())
return value and 1
]=] },
        { "nested rebind does not invalidate an uncalled outer flow", [=[
local function Identity(value)
    return value
end
local function NeverCalled()
    Identity = function()
        return 1
    end
end
local value = Identity(S())
return value and 1
]=] },
        { "conditional helper rebind retains the original possible flow", [=[
local function Identity(value)
    return value
end
if C then
    Identity = function()
        return 1
    end
end
return Identity(S()) and 1
]=] },
        { "later helper rebind does not invalidate an earlier call", [=[
local function Identity(value)
    return value
end
local value = Identity(S())
Identity = function()
    return 1
end
return value and 1
]=] },
        { "same-line later rebind preserves the earlier call", [=[
local function Identity(value) return value end; local value = Identity(S()); Identity = function() return 1 end; return value and 1
]=] },
        { "same-line named function rebind preserves the earlier call", [=[
local function Identity(value) return value end; local value = Identity(S()); function Identity() return 1 end; return value and 1
]=] },
    }
    for _, case in ipairs(soundCases) do
        assert(findingsFor(case[2]) >= 1,
            case[1] .. " must retain a possibly-secret path")
    end

    local cleanCases = {
        { "guaranteed repeat root rebind", [=[
local cache = GetCache()
cache.foo = S()
repeat cache = {} until DONE
return cache.foo or DEFAULT
]=] },
        { "repeat post-rebind break scalar exit", [=[
local x = S()
repeat
    x = 1
    if C then break end
until DONE
return x and 1
]=] },
        { "repeat post-rebind break field exit", [=[
local t = GetCache()
t.foo = S()
repeat
    t.foo = 1
    if C then break end
until DONE
return t.foo or DEFAULT
]=] },
        { "exhaustive scalar clean overwrite", [=[
local x = S()
if C then x = 1 else x = 2 end
return x and 1
]=] },
        { "exhaustive field clean overwrite", [=[
local t = GetCache()
t.foo = S()
if C then t.foo = 1 else t.foo = 2 end
return t.foo or DEFAULT
]=] },
        { "do-local scalar taint does not pollute outer binding", [=[
local x = 1
do local x = S() end
return x and 1
]=] },
        { "if-local scalar taint does not pollute outer binding", [=[
local x = 1
if C then local x = S() end
return x and 1
]=] },
        { "do-local alias does not pollute outer binding", [=[
local c, h = {}, {}
do local h = c end
c.foo = S()
return h.foo or DEFAULT
]=] },
        { "numeric-for variable shadows a tainted outer local", [=[
local i = S()
for i = 1, 2 do
    if i then Use() end
end
]=] },
        { "generic-for variable shadows a tainted outer local", [=[
local k = S()
for k in pairs(t) do
    if k then Use() end
end
]=] },
        { "local function name shadows a tainted outer local", [=[
local callback = S()
do
    local function callback()
        if callback then Use() end
    end
end
]=] },
        { "net-growth may-alias cycle terminates", [=[
local frame, iconHost = {}, {}
if A then frame = iconHost else frame = {} end
if B then iconHost = frame.Icon else iconHost = {} end
return iconHost.GetRegions
]=] },
        { "rebound local helper does not retain a stale summary", [=[
local function Identity(value)
    return value
end
Identity = function()
    return 1
end
return Identity(S()) and 1
]=] },
        { "same-line rebound helper does not retain a stale summary", [=[
local function Identity(value) return value end; Identity = function() return 1 end; return Identity(S()) and 1
]=] },
        { "nested wrapper resolves a forward-to-clean callee at invocation time", [=[
local function Identity(value)
    return value
end
local function Outer(value)
    return Identity(value)
end
Identity = function()
    return 1
end
return Outer(S()) and 1
]=] },
        { "function alias captures a clean rebound value", [=[
local function Identity(value)
    return value
end
Identity = function()
    return 1
end
local Alias = Identity
return Alias(S()) and 1
]=] },
        { "named function statement is a deterministic helper value event", [=[
local function Identity(value)
    return value
end
function Identity()
    return 1
end
return Identity(S()) and 1
]=] },
        { "parenthesized assignment target is a deterministic helper value event", [=[
local function Identity(value)
    return value
end
(Identity) = function()
    return 1
end
return Identity(S()) and 1
]=] },
        { "unconditional do rebind is a deterministic helper value event", [=[
local function Identity(value)
    return value
end
do
    Identity = function()
        return 1
    end
end
return Identity(S()) and 1
]=] },
        { "same-line named function rebind replaces the old helper value", [=[
local function Identity(value) return value end; function Identity() return 1 end; return Identity(S()) and 1
]=] },
        { "exhaustive helper rebind cannot retain the impossible old summary", [=[
local function Identity(value)
    return value
end
if C then
    Identity = function()
        return 1
    end
else
    Identity = function()
        return 2
    end
end
return Identity(S()) and 1
]=] },
        { "invoked wrapper sees its forward-to-clean upvalue rebind", [=[
local function Identity(value)
    return value
end
local function Outer(value)
    Identity = function()
        return 1
    end
    return Identity(value)
end
return Outer(S()) and 1
]=] },
        { "wrapper alias captures its forward-to-clean upvalue rebind", [=[
local function Identity(value)
    return value
end
local function Outer(value)
    Identity = function()
        return 1
    end
    local Alias = Identity
    return Alias(value)
end
return Outer(S()) and 1
]=] },
        { "nested wrapper inherits a forward-to-clean invocation rebind", [=[
local function Identity(value)
    return value
end
local function Middle(value)
    return Identity(value)
end
local function Outer(value)
    Identity = function()
        return 1
    end
    return Middle(value)
end
return Outer(S()) and 1
]=] },
        { "nested wrapper alias inherits a forward-to-clean invocation rebind", [=[
local function Identity(value)
    return value
end
local function Middle(value)
    local Alias = Identity
    return Alias(value)
end
local function Outer(value)
    Identity = function()
        return 1
    end
    return Middle(value)
end
return Outer(S()) and 1
]=] },
        { "call before local declaration does not see the later summary", [=[
local value = GetSecret()
local function GetSecret()
    return S()
end
return value and 1
]=] },
        { "block-local helper summary does not escape its lexical scope", [=[
do
    local function GetSecret()
        return S()
    end
end
local value = GetSecret()
return value and 1
]=] },
        { "transaction identity cannot collide with a user identifier", [=[
local __QUI_TAINT_TXN_1_x = {}
__QUI_TAINT_TXN_1_x.foo = S()
local x, y = {}, {}
x, y = y, x
return y.foo or DEFAULT
]=] },
    }
    for _, case in ipairs(cleanCases) do
        assert_eq(findingsFor(case[2]), 0,
            case[1] .. " must not retain unreachable taint")
    end

    -- A wide branch merge used to make every may-alias read scan and recurse
    -- over the full graph.  Keep a generous wall-clock ceiling for slower CI
    -- while still rejecting the former multi-second cubic curve.
    local function wideMayAliasSource(targetCount)
        local lines = {
            "local c = {}",
            "local h",
            "if X1 then h = { cache = c[1] }",
        }
        for i = 2, targetCount do
            lines[#lines + 1] =
                ("elseif X%d then h = { cache = c[%d] }"):format(i, i)
        end
        lines[#lines + 1] = "else h = {} end"
        lines[#lines + 1] = "return h.cache.foo or DEFAULT"
        return table.concat(lines, "\n")
    end
    for _, targetCount in ipairs({ 100, 200 }) do
        local started = os.clock()
        assert_eq(findingsFor(wideMayAliasSource(targetCount)), 0,
            "wide clean may-alias graph stays clean")
        assert(os.clock() - started < 1.0,
            targetCount
                .. "-target may-alias reachability must stay below one CPU second")
    end

    print("round-11 state-model coverage test passed")
end)()

-- ROUND-12: MAY-alias graph closure, concrete strong updates, and query-cache
-- invalidation. Unknown slots are symmetric aliases, can compose with exact
-- aliases at any depth, and must not override a later definite concrete write.
;(function()
    local r12 = Registry.new()
    r12:addSource("S")

    local function count(source)
        local findings, err =
            Analyzer.analyze(source, "modules/foo.lua", r12, cfg)
        assert(findings, "round-12 source failed to parse: " .. tostring(err))
        return #findings
    end

    local soundCases = {
        { "wildcard hop continues through a live alias", [=[
local c, h, j = {}, {}, {}
h[K()] = j
j.x = c
c.foo = S()
return h.ab.x.foo or DEFAULT
]=] },
        { "assignment wildcard reverse stable write", [=[
local c, h = {}, {}
h[K()] = c
h.ab.foo = S()
return c.foo or DEFAULT
]=] },
        { "constructor wildcard reverse stable write", [=[
local c = {}
local h = { [K()] = c }
h.ab.foo = S()
return c.foo or DEFAULT
]=] },
        { "concatenated-key wildcard reverse stable write", [=[
local c, h = {}, {}
h["a" .. "b"] = c
h.ab.foo = S()
return c.foo or DEFAULT
]=] },
        { "variable-key wildcard reverse stable write", [=[
local c, h = {}, {}
local key = K()
h[key] = c
h.ab.foo = S()
return c.foo or DEFAULT
]=] },
        { "one-arm concrete overwrite cannot clear the other path", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
if X then h.ab = {} end
return h.ab.foo or DEFAULT
]=] },
        { "zero-iteration loop concrete overwrite is not definite", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
while X do h.ab = {} end
return h.ab.foo or DEFAULT
]=] },
        { "cached clean read invalidates on later target taint", [=[
local c, h = {}, {}
h[K()] = c
local before = h.ab.foo
c.foo = S()
return h.ab.foo or DEFAULT
]=] },
        { "cached clean read invalidates on later alias insertion", [=[
local c, h = {}, {}
local before = h.ab.foo
h[K()] = c
c.foo = S()
return h.ab.foo or DEFAULT
]=] },
        { "same wildcard edge reasserts after a concrete overwrite", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
h[K()] = c
return h.ab.foo or DEFAULT
]=] },
        { "new nested wildcard edge survives a parent overwrite", [=[
local c, d, h = {}, {}, {}
h[K()] = c
c.foo.secret = S()
h.ab = {}
h.ab[J()] = d
d.secret = S()
return h.ab.foo.secret or DEFAULT
]=] },
        { "new wildcard target survives an older target cutoff", [=[
local c, d, h = {}, {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
h[K()] = d
d.foo = S()
return h.ab.foo or DEFAULT
]=] },
        { "loop clean then same-edge reassert converges live", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
while X do
    h.ab = {}
    h[K()] = c
    X = false
end
return h.ab.foo or DEFAULT
]=] },
        { "guaranteed repeat clean then reassert stays live", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
repeat
    h.ab = {}
    h[K()] = c
until X
return h.ab.foo or DEFAULT
]=] },
    }
    for _, case in ipairs(soundCases) do
        assert(count(case[2]) >= 1,
            case[1] .. " must retain a possibly-secret path")
    end

    local cleanCases = {
        { "whole-slot overwrite excludes an older wildcard edge", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
return h.ab.foo or DEFAULT
]=] },
        { "leaf overwrite excludes an older wildcard edge", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
h.ab.foo = 1
return h.ab.foo or DEFAULT
]=] },
        { "concrete overwrite survives a cached tainted read", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
local before = h.ab.foo
h.ab = {}
return h.ab.foo or DEFAULT
]=] },
        { "both branch arms concretely overwrite the wildcard slot", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
if X then h.ab = {} else h.ab = {} end
return h.ab.foo or DEFAULT
]=] },
        { "guaranteed repeat overwrite excludes the wildcard slot", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
repeat h.ab = {} until DONE
return h.ab.foo or DEFAULT
]=] },
        { "sibling overwrite does not manufacture sibling taint", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
return h.ab.bar or DEFAULT
]=] },
        { "later old-target taint stays behind the concrete overwrite", [=[
local c, h = {}, {}
h[K()] = c
h.ab = {}
c.foo = S()
return h.ab.foo or DEFAULT
]=] },
        { "later different target does not revive the old target", [=[
local c, d, h = {}, {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
h[K()] = d
return h.ab.foo or DEFAULT
]=] },
        { "descendant taint does not revoke a parent overwrite", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
h.ab.other = S()
return h.ab.foo or DEFAULT
]=] },
        { "unrelated wildcard insertion preserves the overwrite", [=[
local c, h, x, y = {}, {}, {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
x[J()] = y
return h.ab.foo or DEFAULT
]=] },
        { "unrelated constructor wildcard preserves the overwrite", [=[
local c, h, y = {}, {}, {}
h[K()] = c
c.foo = S()
h.ab = {}
local x = { [J()] = y }
return h.ab.foo or DEFAULT
]=] },
        { "all branch arms block their local edge epoch", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
if X then
    h[K()] = c
    h.ab = {}
else
    h[K()] = c
    h.ab = {}
end
return h.ab.foo or DEFAULT
]=] },
        { "guaranteed repeat reassert then clean stays blocked", [=[
local c, h = {}, {}
h[K()] = c
c.foo = S()
repeat
    h[K()] = c
    h.ab = {}
until X
return h.ab.foo or DEFAULT
]=] },
    }
    for _, case in ipairs(cleanCases) do
        assert_eq(count(case[2]), 0,
            case[1] .. " must not retain unreachable taint")
    end

    local function repeatedMayReads(targetCount, readCount)
        local lines = {
            "local c = {}",
            "local h",
            "if X1 then h = { cache = c[1] }",
        }
        for i = 2, targetCount do
            lines[#lines + 1] =
                ("elseif X%d then h = { cache = c[%d] }"):format(i, i)
        end
        lines[#lines + 1] = "else h = {} end"
        for i = 1, readCount do
            lines[#lines + 1] =
                ("local value%d = h.cache.foo or DEFAULT"):format(i)
        end
        lines[#lines + 1] = "return 1"
        return table.concat(lines, "\n")
    end
    local started = os.clock()
    assert_eq(count(repeatedMayReads(400, 400)), 0,
        "repeated clean may-alias reads stay clean")
    assert(os.clock() - started < 3.0,
        "400-target x 400-read may-alias reachability must stay cached")

    -- The loop join drops and rematerializes this MAY edge while finding its
    -- fixed point. Its temporal identity must stabilize instead of allocating
    -- a fresh epoch on every abstract transfer.
    started = os.clock()
    assert(count([=[
local cache = {}
cache[1] = S()
local alias = cache
while X do
    alias = {}
end
return alias[1] or DEFAULT
]=]) >= 1, "zero-iteration loop retains the entry MAY edge")
    assert(os.clock() - started < 1.0,
        "rematerialized loop MAY edge must converge below one CPU second")

    print("round-12 MAY-alias closure + cache test passed")
end)()

print("round-8 truth-test + gate-scope + guard-alias test passed")
print("round-9 gate-governance + deep-field provenance test passed")
end

-- round-12b: all-guard OR-chain untaint (`if G(x) or G(y) then return end`
-- proves x AND y for else/subsequent code — the canonical multi-value probe
-- bail). Mixed chains (any non-guard disjunct) must keep the taint.
;(function()
    local r12 = Registry.new()
    r12:addSource("UnitCastingInfo")
    r12:addGuard("RSV")  -- extra_guards-style registered wrapper name
    local c12 = Config.loadFromString(nil)
    local function count(src)
        local f = Analyzer.analyze(src, "modules/foo.lua", r12, c12)
        assert(f, "analyze ok")
        return #f
    end

    -- Round-13b: `return nil` inside the all-guard branch is itself a
    -- secret-to-state collapse (the fail-open spelling), so each of these
    -- now carries exactly ONE finding — the collapse — while the or-chain
    -- proof still keeps the post-if reads clean.
    assert_eq(count([[
local _, _, _, startMS, endMS = UnitCastingInfo("player")
if issecretvalue(startMS) or issecretvalue(endMS) then
    return nil
end
if startMS and endMS then
    return startMS / 1000, (endMS - startMS) / 1000
end
return false
]]), 1, "all-guard or-chain terminator proves every probed value"
    .. " (+ the return-nil collapse)")

    assert_eq(count([[
local _, _, _, startMS, endMS = UnitCastingInfo("player")
if RSV(startMS) or RSV(endMS) then
    return nil
end
return startMS + endMS
]]), 1, "registered wrapper guards work in the or-chain"
    .. " (+ the return-nil collapse)")

    assert(count([[
local _, _, _, startMS, endMS = UnitCastingInfo("player")
if issecretvalue(startMS) or endMS == 5 then
    return nil
end
return startMS + endMS
]]) >= 1, "mixed or-chain must NOT untaint (endMS never probed, and the == throws)")

    assert(count([[
local _, _, _, startMS, endMS = UnitCastingInfo("player")
if issecretvalue(startMS) or issecretvalue(endMS) then
    return nil
end
local other = UnitCastingInfo("player")
return other and 1 or 0
]]) >= 1, "or-chain proof scoped to probed values only")

    print("round-12b all-guard or-chain untaint test passed")
end)()

-- ===== Round-13: unknown-consumer default-reject =====
do
    local r13 = Registry.new()
    r13:addSource("C_Spell.GetSpellCharges")
    r13:addDocArgRestrictedMethod("SetShown", "AllowedWhenUntainted")
    r13:addDocArgRestrictedFunction("C_Test.Forbidden", "NotAllowed")
    r13:addSafeSinkMethod("SetValue")
    local srcR13

    -- 1. tainted arg to an UNKNOWN method → flags
    srcR13 = [[
local info = C_Spell.GetSpellCharges(1)
local obj = GetFrame()
obj:Configure(info)
]]
    local f = Analyzer.analyze(srcR13, "modules/foo.lua", r13, cfg)
    assert_eq(#f, 1, "unknown method consumer flags")
    assert(f[1].sink:find("consumer", 1, true), "consumer sink label")

    -- 2. tainted arg to a DOCUMENTED-restricted method → flags, cites doc
    srcR13 = [[
local info = C_Spell.GetSpellCharges(1)
local obj = GetFrame()
obj:SetShown(info)
]]
    f = Analyzer.analyze(srcR13, "modules/foo.lua", r13, cfg)
    assert_eq(#f, 1, "documented-restricted method flags")
    assert(f[1].message:find("AllowedWhenUntainted", 1, true), "message cites the doc value")

    -- 3. tainted arg to a documented-restricted FUNCTION → flags
    srcR13 = [[
local info = C_Spell.GetSpellCharges(1)
C_Test.Forbidden(info)
]]
    f = Analyzer.analyze(srcR13, "modules/foo.lua", r13, cfg)
    assert_eq(#f, 1, "documented-restricted function flags")

    -- 4. tainted arg to an UNDOCUMENTED plain function → NO consumer finding
    --    (non-interprocedural boundary: helpers are hand-audited)
    srcR13 = [[
local info = C_Spell.GetSpellCharges(1)
HelperFn(info)
]]
    f = Analyzer.analyze(srcR13, "modules/foo.lua", r13, cfg)
    assert_eq(#f, 0, "plain undocumented function stays traversal-only")

    -- 5. safe-sink control: no finding
    srcR13 = [[
local info = C_Spell.GetSpellCharges(1)
local bar = GetFrame()
bar:SetValue(info)
]]
    f = Analyzer.analyze(srcR13, "modules/foo.lua", r13, cfg)
    assert_eq(#f, 0, "allowlisted sink method stays clean")

    -- 6. clean arg to unknown method: no finding
    srcR13 = [[
local obj = GetFrame()
obj:Configure(5)
]]
    f = Analyzer.analyze(srcR13, "modules/foo.lua", r13, cfg)
    assert_eq(#f, 0, "clean args never flag")

    -- 7. protected-call demotion parity with the UNSAFE_BUILTIN branch
    srcR13 = [[
local obj = GetFrame()
obj:Configure((pcall(C_Spell.GetSpellCharges, 1)))
]]
    f = Analyzer.analyze(srcR13, "modules/foo.lua", r13, cfg)
    assert_eq(#f, 0, "parenthesized pcall truncates to the clean ok boolean")
end
print("round-13 unknown-consumer default-reject tests passed")

-- ===== Round-13b: secret-to-state collapse (Drew's 12d canon) =====
do
    local r13b = Registry.new()
    r13b:addSource("C_Spell.GetSpellCharges")
    r13b:addSafeSinkMethod("SetValue")
    local srcC

    -- 1. THE canonical defect: secret ⇒ true
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    return true
end
]]
    local f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    local n = 0
    for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 1, "secret => return true flags collapse")

    -- 2. secret ⇒ nil (the fail-open spelling is the SAME error)
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    return nil
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 1, "secret => return nil flags collapse")

    -- 3. bare return = reject/defer → sanctioned, clean
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    return
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 0, "bare return (defer) stays clean")

    -- 4. routing the opaque value to a documented C sink → clean
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
local bar = GetBar()
if issecretvalue(x) then
    bar:SetValue(x)
    return
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 0, "sink-route + defer stays clean")

    -- 5. literal STATE write in the guard-secret branch flags
    srcC = [[
local state = {}
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    state.active = true
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 1, "secret => state.active = true flags")

    -- 6. inverted polarity: else-branch of `if not issecretvalue(x)` is the
    --    secret region
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if not issecretvalue(x) then
    local y = 1
else
    return false
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 1, "later clauses after untaint-then are the secret region")

    -- 7. nested statements inside the region are scanned
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    if GetFlag() then
        return {}
    end
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 1, "literal constructor return in nested if flags")

    -- 8. @secret-policy suppresses; @secret-safe does NOT
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    return true -- @secret-policy: keep-visible-when-unknown
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 0, "named policy annotation suppresses collapse")

    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    return true -- @secret-safe: fine
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 1, "@secret-safe cannot bless a collapse — policy must be named")

    -- 9. closures inside the region are NOT scanned (deferred bodies run
    --    outside the guard's dominance)
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    RunLater(function() return true end)
    return
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 0, "closure bodies skipped")

    -- 10. non-literal returns stay clean (forwarding/unwrap paths)
    srcC = [[
local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    return x
end
]]
    f = Analyzer.analyze(srcC, "modules/foo.lua", r13b, cfg)
    n = 0; for _, ff in ipairs(f) do if ff.sink == "<secret-collapse>" then n = n + 1 end end
    assert_eq(n, 0, "forwarding the opaque value is not a collapse")
end
print("round-13b secret-collapse tests passed")

-- ===== Round-23: element-taint (conditionalSecretContents) =====
do
    local rE = Registry.new()
    rE:addElementSecretFunction("C_UnitAuras.GetUnitAuras")
    rE:addGuard("issecretvalue")
    local srcE, fE

    -- E1: bind records marker; container truth-test + # + arg-pass clean
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if auras then
    local n = #auras
    Consume(auras)
end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E1: container-level ops all clean")

    -- E2: element read flags
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if auras then
    local a = auras[1]
    if a then return 1 end
end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E2: unprobed element read flags")

    -- E3: deep read through element flags
    -- (Plan deviation, documented: the plan spelled E3/E5/E6 as
    -- `return X and X[1]` — a pure VALUE-yield return. No consumer emits
    -- there for ANY taint kind: forwarding an opaque possibly-secret value
    -- is legal and pinned clean (round-13b case 10), and the design spec's
    -- Consumption section mandates marker-mediated reads flow through
    -- EXISTING consumers only. Each case keeps its tested semantics —
    -- deep-read matching / alias hop / source-alias binding — with the
    -- read moved to condition position, where the and-chain truth-tests
    -- the yielded element and the round-8 consumer emits.)
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if auras and auras[1].spellId then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E3: deep read through slot flags")

    -- E4: probed element (runtime canon shape) scans clean
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if auras then
    for i = 1, #auras do
        local a = auras[i]
        if issecretvalue(a) then a = nil end
        if a ~= nil then Use(a) end
    end
end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E4: probe + nil-rebind discipline scans clean")

    -- E5: alias hop — copy of container carries markers
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
local list = auras
if list and list[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E5: element read through alias flags")

    -- E6: value-copy source alias (and-chain shape) binds marker
    srcE = [[
local Get = C_UnitAuras and C_UnitAuras.GetUnitAuras
local auras = Get("player", "HELPFUL")
if auras and auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E6: aliased source call binds marker, read flags")

    -- E7: clean overwrite clears. Positive control first: the SAME read
    -- without the overwrite must flag, so the 0 below proves the sweep —
    -- not a read shape that never emits (return-position reads are
    -- non-emitting, so the plan's `return auras[1]` spelling was vacuous).
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E7-control: same read without overwrite flags")
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
auras = {}
if auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E7: content-clean overwrite clears markers")

    -- E8: unregistered function control (consuming read position, so a
    -- spurious marker WOULD flag — non-vacuous no-FP control)
    srcE = [[
local auras = C_UnitAuras.GetOtherThing("player")
if auras and auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E8: unregistered call binds nothing")

    print("round-23 element-taint bind/read tests passed")

    -- E9: pcall spill — result 2 is the container
    srcE = [[
local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
if ok and auras then
    if auras[1] then return 1 end
end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E9: pcall-spilled container element read flags")

    -- E9b: multi-assign direct call — result 1 only
    srcE = [[
local a, b = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if a and a[1] then return 1 end
if b and b[1] then return 2 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E9b: exactly result 1 carries the marker")

    -- E10: ok boolean + truncation controls stay clean. The t1[2]/t2[2]
    -- reads (Task-4 extension, review-approved) READ the would-be marker
    -- slots in consuming position: a marker wrongly recorded past the
    -- truncating parentheses (t1) or at a non-final pcall (t2) would flag
    -- here — locks both truncation guards against regression.
    srcE = [[
local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
local t1 = { (pcall(C_UnitAuras.GetUnitAuras, "player")) }
local t2 = { pcall(C_UnitAuras.GetUnitAuras, "player"), 5 }
if ok and t1[1] and t2[1] then return 1 end
if t1[2] and t1[2][1] then return 2 end
if t2[2] and t2[2][1] then return 3 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E10: ok/truncated slots clean")

    -- E11: constructor expansion records slot marker
    srcE = [[
local t = { pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL") }
if t[2][1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E11: {pcall(Src)} slot-2 element read flags")

    -- E12: bare constructor expansion
    srcE = [[
local t = { C_UnitAuras.GetUnitAuras("player", "HELPFUL") }
if t[1][1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E12: {Src()} slot-1 element read flags")

    print("round-23 spill/constructor tests passed")

    -- E13: direct-expression element read
    srcE = [[
return C_UnitAuras.GetUnitAuras("player", "HELPFUL")[1]
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E13: Src(u)[1] flags")
    do
        local found = false
        for _, f in ipairs(fE) do
            if tostring(f.message):find("secret-content container", 1, true) then
                found = true
            end
        end
        assert(found, "E13: distinct class message present")
    end

    -- E14: probed ipairs loop scans ZERO (header FP suppression)
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if auras then
    for _, a in ipairs(auras) do
        if issecretvalue(a) then a = nil end
        if a ~= nil then Use(a) end
    end
end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E14: probed ipairs loop clean — header emit suppressed")

    -- E15: unprobed loop-var use flags
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if auras then
    for _, a in ipairs(auras) do
        if a.spellId then return 1 end
    end
end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E15: unprobed loop value flags")

    -- E16: key var stays clean
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
local n = 0
if auras then
    for i in ipairs(auras) do n = n + i end
end
return n
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E16: key/index var clean")

    -- E17: directly-tainted table into ipairs keeps header emit (control)
    do
        local rT = Registry.new()
        rT:addSource("C_Spell.GetSpellCharges")
        srcE = [[
local info = C_Spell.GetSpellCharges(1)
for _, v in ipairs(info) do Use(v) end
return 0
]]
        fE = Analyzer.analyze(srcE, "modules/foo.lua", rT, cfg)
        assert(#fE >= 1, "E17: whole-tainted ref into ipairs still emits")
    end

    -- E18: iterator over direct source call taints loop value
    srcE = [[
for _, a in ipairs(C_UnitAuras.GetUnitAuras("player", "HELPFUL") or {}) do
    if a then return 1 end
end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E18: ipairs(Src(u)) loop value tainted, use flags")

    print("round-23 expression/loop tests passed")

    -- ===== Round-23 Task 5: helper-param seeding =====

    -- E19: seeded param — unprobed element read flags
    rE:addElementContainerParams("CopyReadableAuras", { 1 })
    srcE = [[
local function CopyReadableAuras(src, dst)
    local a = src[1]
    if a then dst[1] = a end
end
return CopyReadableAuras
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E19: seeded param element read flags")

    -- E20: probed body scans clean (runtime canon)
    srcE = [[
local function CopyReadableAuras(src, dst)
    local n = 0
    for i = 1, #src do
        local a = src[i]
        if issecretvalue(a) then a = nil end
        if a ~= nil then n = n + 1 dst[n] = a end
    end
end
return CopyReadableAuras
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E20: probed seeded-param body clean")

    -- E21: unrelated same-shape function unseeded (control)
    -- (Plan deviation, documented: the plan spelled the body as
    -- `dst[1] = src[1]` — a pure propagation write. Assignments RECORD
    -- taint, they never emit, for ANY taint kind, so a 0 there could not
    -- distinguish "unseeded" from "seeded but non-emitting shape". The
    -- read moves to consuming condition position — same rationale as the
    -- E8 control — and a positive control with the SAME body under a
    -- registered spelling pins non-vacuity first.)
    rE:addElementContainerParams("OtherCopyControl", { 1 })
    srcE = [[
local function OtherCopyControl(src, dst)
    if src[1] then dst[1] = src[1] end
end
return OtherCopyControl
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E21-control: same shape with registered name flags")
    srcE = [[
local function OtherCopy(src, dst)
    if src[1] then dst[1] = src[1] end
end
return OtherCopy
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E21: unseeded helper unaffected")

    -- E22: colon method — implicit self shifts declared positions
    -- (Plan deviation, documented: the plan spelled the body as
    -- `return src[1]` — a pure value-yield return. Return-position reads
    -- are non-emitting for EVERY taint kind (round-13b case 10; the E3/E7
    -- deviation notes above), so the assert could never fire. The read
    -- moves to condition position; the tested semantics — position 1 maps
    -- to the first DECLARED param, never implicit self — is unchanged and
    -- still discriminates: a wrongly argOffset-compensated mapping seeds
    -- nothing onto `src` and this scans clean.)
    rE:addElementContainerParams("M.Copy", { 1 })
    srcE = [[
local M = {}
function M:Copy(src)
    if src[1] then return 1 end
    return 0
end
return M
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1,
        "E22: colon method position 1 = first DECLARED param (not self)")

    print("round-23 param-seed tests passed")

    -- ===== Round-23 final review (F1): keyed / non-final constructor =====

    -- E23: keyed constructor entry binds the slot marker (whole-branch
    -- review verified FN: `{ auras = Src(u) }` then `state.auras[1]`
    -- scanned clean — only final list position expanded).
    srcE = [[
local state = { auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL") }
if state.auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E23: keyed-entry element read flags")

    -- E24: probed keyed-entry element scans clean (runtime canon shape)
    srcE = [[
local state = { auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL") }
local a = state.auras[1]
if issecretvalue(a) then a = nil end
if a ~= nil then Use(a) end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E24: probed keyed-entry element stays clean")

    -- E25: non-final LIST entry truncates to result 1 — which IS the
    -- container — at the entry's OWN slot (not the pcall +1 arithmetic)
    srcE = [[
local t = { C_UnitAuras.GetUnitAuras("player", "HELPFUL"), 5 }
if t[1][1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert(#fE >= 1, "E25: non-final list slot element read flags")

    -- E26: non-final PCALL entry still yields ONLY the clean ok boolean
    -- at its own slot (control — consuming read of the would-be marker
    -- slot, so a wrongly recorded marker WOULD flag here)
    srcE = [[
local t = { pcall(C_UnitAuras.GetUnitAuras, "player"), 5 }
if t[1] and t[1][1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E26: non-final pcall entry ok-slot stays clean")

    print("round-23 final-review F1 constructor tests passed")

    -- ===== Round-23 final review (F2): soundness pins =====

    -- E27: restriction-gate bail does NOT clear element markers — the
    -- gate governs payload-class taint, while element secrecy is
    -- per-entry and gate-INDEPENDENT (independentFields provenance);
    -- the post-bail element read must still flag.
    rE:addRestrictionGate("SomeGate")
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if SomeGate() then return 0 end
if auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E27: gate bail leaves element marker live")

    -- E28: terminating guard bail on the extracted element proves the
    -- fall-through (round-8 terminator-aware untaint applies to markers)
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
local a = auras[1]
if issecretvalue(a) then return end
if a then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E28: guard-bail on element proves fall-through")

    -- E29: statement-split KEYED probe proves exactly its slot (round-7j
    -- keyed-ref identity); the unprobed sibling slot still flags.
    srcE = [[
local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if issecretvalue(auras[1]) then return end
if auras[1] then return 1 end
if auras[2] then return 2 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E29: keyed probe scopes to its slot; sibling flags")

    -- E30: config-registered wrapper spelling (receiver-import shape, no
    -- value-copy alias involved) binds the marker like the index track
    rE:addElementSecretFunction("Sources.QueryUnitAuras")
    srcE = [[
local auras = Sources.QueryUnitAuras("player")
if auras and auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E30: config wrapper spelling binds marker")

    -- E31: slot write then read through ANOTHER spelling — the heap slot
    -- `t.list` carries the marker and the local copy reads it back
    -- (alias/chainAlias unification, same path as round-10d)
    srcE = [[
local t = {}
t.list = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
local l = t.list
if l[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E31: aliased spelling of marked slot flags")

    -- E32: shadowed-param control — a nested closure declares its OWN
    -- param spelled like the seeded helper param. Param seeding is
    -- spelling-keyed (chunk-wide union, scoping not modeled — same
    -- boundary as the round-8 shadowed-`error` rule), so the inner read
    -- INHERITS the seed and flags: a conservative KNOWN false positive
    -- (T5 review), pinned here as current behavior, not as a contract.
    rE:addElementContainerParams("ShadowedCopy", { 1 })
    srcE = [[
local function ShadowedCopy(src, dst)
    local inner = function(src)
        if src[1] then return 1 end
        return 0
    end
    return inner(dst)
end
return ShadowedCopy
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1,
        "E32: shadowing closure param inherits seed (known-FP pin)")

    print("round-23 final-review F2 soundness pins passed")

    -- ===== Round-23 final review (F5): pcall spill into member/index =====

    -- E33: protected-call spill into a MEMBER target binds the marker on
    -- the target's canonical chain key (Codex stop-gate: `ok, state.auras
    -- = pcall(Src, ...)` landed the container with ZERO findings — the
    -- spill path was VarExpr-only).
    srcE = [[
local state = {}
local ok
ok, state.auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
if ok and state.auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E33: member-target pcall spill binds element marker")

    -- E34: index-target twin (stable literal key)
    srcE = [[
local state = {}
local ok
ok, state[1] = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
if ok and state[1][1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E34: index-target pcall spill binds element marker")

    -- E35: controls — the ok slot, a results-3+ member target, and a
    -- NON-element pcall member spill all record nothing (consuming reads
    -- of every would-be marker slot; state.auras — the one slot that DOES
    -- carry the marker — is deliberately left unread)
    srcE = [[
local state = {}
local ok
ok, state.auras, state.extra = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
local s2 = {}
local ok2
ok2, s2.data = pcall(C_Other.GetThing, "x")
if ok and state.extra[1] then return 1 end
if ok2 and s2.data[1] then return 2 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E35: ok slot / result-3 / non-element spill clean")

    print("round-23 final-review F5 member-spill tests passed")

    -- ===== Round-23 final review (F5b): spill = full member-write =====
    -- Codex verified F5's first cut recorded the marker but BYPASSED the
    -- member-write lifecycle (slot retarget/alias drop + strong-update
    -- clearing). PARITY IS THE CONTRACT: a spill write must behave
    -- exactly like the direct assignment twin.

    -- E36 (Bug 1, alias retarget): earlier `state.auras = other` recorded
    -- a chainAlias; without the retarget the spill's marker was recorded
    -- under a spelling reads never reach (verified FN: 0 findings).
    -- Direct twin FIRST — its observed count (1: the slot's own read
    -- flags via the fresh marker, `other[1]` stays clean per round-9g)
    -- is the contract the spill twin must match exactly.
    srcE = [[
local other = {}
local state = {}
state.auras = other
state.auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if state.auras[1] then return 1 end
if other[1] then return 2 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E36-twin: direct overwrite of aliased slot flags once")
    srcE = [[
local other = {}
local state = {}
state.auras = other
local ok
ok, state.auras = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
if ok and state.auras[1] then return 1 end
if other[1] then return 2 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E36: spill overwrite matches the direct twin exactly")

    -- E37 (Bug 2, stale-marker FP): result position 3 receives NIL at
    -- runtime (single-container contract) — a previously marked slot
    -- there must be strong-update CLEARED, not keep flagging. Control
    -- without the spill pins non-vacuity first.
    srcE = [[
local state = {}
state.x = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if state.x[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E37-control: marked slot read flags without the spill")
    srcE = [[
local state = {}
state.x = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
local ok, other
ok, other, state.x = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
if state.x[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E37: result-3 nil overwrite clears the stale marker")

    -- E38: the ok BOOLEAN landing on a previously marked member slot is
    -- provably content-clean (pcall result 1 is always a boolean) —
    -- strong update clears the old marker.
    srcE = [[
local state = {}
state.ok = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
local x
state.ok, x = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL")
if state.ok[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E38: ok-boolean overwrite clears the stale marker")

    print("round-23 final-review F5b lifecycle-parity tests passed")

    -- ===== Round-23 final review (F5c): parenthesized pcall rhs =====

    -- E39: `t.x = (pcall(F))` assigns the SAME ok boolean the bare
    -- spelling does (parentheses truncate to one value) — the
    -- content-clean strong update must not depend on the spelling
    -- (Codex verified stale-marker FP: raw-RHS classification missed
    -- the Parentheses node). Control pins non-vacuity first.
    srcE = [[
local t = {}
t.x = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if t.x[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E39-control: marked slot flags without the overwrite")
    srcE = [[
local t = {}
t.x = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
t.x = (pcall(C_UnitAuras.GetUnitAuras, "player"))
if t.x[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0,
        "E39: parenthesized pcall overwrite clears like the bare spelling")

    print("round-23 final-review F5c paren-pcall tests passed")

    -- ===== Round-23 final review (F5d): LocalStatement paren pcall =====

    -- E40: the LocalStatement classification twin of F5c — `local ok =
    -- (pcall(Src, 1))` binds the SAME clean ok boolean as the bare
    -- spelling (parentheses truncate to result 1), so pcallOfSource must
    -- classify the STRIPPED rhs (raw-RHS check was a probe-verified FP
    -- taint on ok). Ordinary-source registry per the E17 convention.
    do
        local rT = Registry.new()
        rT:addSource("C_Spell.GetSpellCharges")
        srcE = [[
local ok = (pcall(C_Spell.GetSpellCharges, 1))
if ok then return 1 end
return 0
]]
        fE = Analyzer.analyze(srcE, "modules/foo.lua", rT, cfg)
        assert_eq(#fE, 0, "E40: parenthesized pcall ok-local stays clean")
        -- Control: the unparenthesized SPILL still taints (result 2 of a
        -- pcall-of-source) — pins that the strip narrows only the ok
        -- classification, not the spill rule.
        srcE = [[
local ok, v = pcall(C_Spell.GetSpellCharges, 1)
if v then return 1 end
return 0
]]
        fE = Analyzer.analyze(srcE, "modules/foo.lua", rT, cfg)
        assert(#fE >= 1, "E40-control: bare pcall source spill still flags")
    end

    print("round-23 final-review F5d local-paren-pcall tests passed")

    -- ===== Round-23 final review (F5e): parenthesized CALLEE =====
    -- `(pcall)(f, ...)` ≡ `pcall(f, ...)` at runtime (a paren wrap
    -- around the callee is identity — truncation only matters in
    -- value-list positions, never callee position), so classification
    -- must not depend on the callee spelling (Codex verified FP + FN).

    -- E41a: paren-callee pcall overwrite of a marked member slot
    -- strong-updates like the bare spelling (control pins non-vacuity)
    srcE = [[
local t = {}
t.x = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
if t.x[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E41a-control: marked slot flags without overwrite")
    srcE = [[
local t = {}
t.x = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
t.x = (pcall)(F)
if t.x[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 0, "E41a: paren-callee pcall overwrite clears the marker")

    -- E41c: paren-callee ELEMENT pcall spill still binds the container
    -- marker at result 2
    srcE = [[
local ok, auras = (pcall)(C_UnitAuras.GetUnitAuras, "player")
if ok and auras[1] then return 1 end
return 0
]]
    fE = Analyzer.analyze(srcE, "modules/foo.lua", rE, cfg)
    assert_eq(#fE, 1, "E41c: paren-callee element pcall spill binds marker")

    -- E41b: paren-callee pcall of an ordinary SOURCE — the spilled v is
    -- secret and must flag (was a verified FN: spill never classified)
    do
        local rT = Registry.new()
        rT:addSource("C_Spell.GetSpellCharges")
        srcE = [[
local ok, v = (pcall)(C_Spell.GetSpellCharges, 1)
if v then return 1 end
return 0
]]
        fE = Analyzer.analyze(srcE, "modules/foo.lua", rT, cfg)
        assert_eq(#fE, 1, "E41b: paren-callee source pcall spill flags")
    end

    print("round-23 final-review F5e paren-callee tests passed")
end  -- closes the round-23 do…end block

-- ===== Probe exemption: registered guards are never SecretArguments consumers =====
-- The generated doc index stamps issecretvalue itself with
-- SecretArguments=AllowedWhenUntainted (generator default template stamp).
-- Runtime accepts probes from tainted code — the probe-first canon idiom
-- must never be classified as a consumer leak, or the idiom itself goes red.
do
    local rP = Registry.new()
    rP:addSource("UnitClass")
    rP:addDocArgRestrictedFunction("issecretvalue", "AllowedWhenUntainted")
    rP:addDocArgRestrictedFunction("Helpers.IsSecretValue", "AllowedWhenUntainted")

    local srcP = [[
local name = UnitClass("target")
if issecretvalue(name) then name = nil end
return name
]]
    local fP = Analyzer.analyze(srcP, "modules/foo.lua", rP, cfg)
    for _, fi in ipairs(fP) do
        assert(not (tostring(fi.sink):find("consumer:issecretvalue", 1, true)),
            "registered probe must be exempt from consumer classification, got: "
            .. tostring(fi.message))
    end

    local srcP2 = [[
local name = UnitClass("target")
if Helpers.IsSecretValue(name) then name = nil end
return name
]]
    local fP2 = Analyzer.analyze(srcP2, "modules/foo.lua", rP, cfg)
    for _, fi in ipairs(fP2) do
        assert(not (tostring(fi.sink):find("consumer:Helpers.IsSecretValue", 1, true)),
            "dotted registered probe must be exempt too, got: " .. tostring(fi.message))
    end

    print("probe-exemption consumer tests passed")
end

-- Existence-guard probe shape (pre-12.1 client compat): the RHS call in
-- `local s = issecretvalue and issecretvalue(v)` is still THE probe — the
-- consumer classifier must not flag it either.
do
    local rP3 = Registry.new()
    rP3:addSource("UnitClass")
    rP3:addDocArgRestrictedFunction("issecretvalue", "AllowedWhenUntainted")
    local srcP3 = [[
local _, class = UnitClass("target")
local classIsSecret = issecretvalue and issecretvalue(class)
if classIsSecret then class = nil end
return class
]]
    local fP3 = Analyzer.analyze(srcP3, "modules/foo.lua", rP3, cfg)
    for _, fi in ipairs(fP3) do
        assert(not (tostring(fi.sink):find("consumer:issecretvalue", 1, true)),
            "existence-guard probe shape must be exempt, got: " .. tostring(fi.message))
    end
    print("probe-exemption existence-guard test passed")
end

-- Shadowed-guard counterexamples (stop-gate): the exemption is protection-
-- granting, so poison discipline applies to BOTH arms. A file that rebinds a
-- guard name gets NO exemption — function form or method form.
do
    local rP4 = Registry.new()
    rP4:addSource("UnitClass")

    -- method form, guard name rebound in-file → must STILL flag
    local srcP4 = [[
local IsSecretValue = function() return false end
local name = UnitClass("target")
local obj = GetHelper()
obj:IsSecretValue(name)
return name
]]
    local fP4 = Analyzer.analyze(srcP4, "modules/foo.lua", rP4, cfg)
    local sawConsumer = false
    for _, fi in ipairs(fP4) do
        if tostring(fi.sink):find("consumer:", 1, true)
            and tostring(fi.sink):find("IsSecretValue", 1, true) then
            sawConsumer = true
        end
    end
    assert(sawConsumer,
        "rebound guard name used as method must NOT get the probe exemption")

    -- method form on an UNKNOWN receiver → NOT exempt (receiver-aware rule:
    -- any object may carry a same-named non-probe method; only registered
    -- qualified guards like Helpers.IsSecretValue are the probe surface)
    local srcP5 = [[
local name = UnitClass("target")
local obj = GetHelper()
obj:IsSecretValue(name)
return name
]]
    local fP5 = Analyzer.analyze(srcP5, "modules/foo.lua", rP4, cfg)
    local sawUnknownRecv = false
    for _, fi in ipairs(fP5) do
        if tostring(fi.sink):find("consumer:", 1, true)
            and tostring(fi.sink):find("IsSecretValue", 1, true) then
            sawUnknownRecv = true
        end
    end
    assert(sawUnknownRecv,
        "unknown-receiver method sharing a guard name must NOT be exempt")

    -- method form on the REGISTERED receiver → exempt
    local srcP5b = [[
local name = UnitClass("target")
if Helpers:IsSecretValue(name) then name = nil end
return name
]]
    local fP5b = Analyzer.analyze(srcP5b, "modules/foo.lua", rP4, cfg)
    for _, fi in ipairs(fP5b) do
        assert(not (tostring(fi.sink):find("consumer:", 1, true)
            and tostring(fi.sink):find("IsSecretValue", 1, true)),
            "registered-receiver method-form probe must stay exempt, got: "
            .. tostring(fi.message))
    end

    -- function form, rebound → the rebound local is no longer even a source
    -- of protection; the poisoned name must not suppress consumer findings
    -- on a DIFFERENT documented-restricted callee reached with the value.
    local rP6 = Registry.new()
    rP6:addSource("UnitClass")
    rP6:addDocArgRestrictedFunction("issecretvalue", "AllowedWhenUntainted")
    local srcP6 = [[
local issecretvalue = function() return false end
local name = UnitClass("target")
issecretvalue(name)
return name
]]
    local fP6 = Analyzer.analyze(srcP6, "modules/foo.lua", rP6, cfg)
    local sawShadowed = false
    for _, fi in ipairs(fP6) do
        if tostring(fi.sink):find("consumer:issecretvalue", 1, true) then
            sawShadowed = true
        end
    end
    -- The rebound name is a plain local function (non-interprocedural
    -- boundary): consumer classification of locals is traversal-only, so no
    -- consumer finding is REQUIRED here — but the exemption must not have
    -- been the reason. Accept either outcome except silent exemption of a
    -- REAL documented global: assert the poisoned path never used the guard
    -- registry (behavioral: fP6 must equal analysis with guards absent).
    local rP6b = Registry.new()
    rP6b:addSource("UnitClass")
    rP6b:addDocArgRestrictedFunction("issecretvalue", "AllowedWhenUntainted")
    -- remove guard status to compare
    rP6b.guards = {}
    local fP6b = Analyzer.analyze(srcP6, "modules/foo.lua", rP6b, cfg)
    assert(#fP6 == #fP6b,
        "poisoned function-form guard must analyze identically to no-guard registry ("
        .. #fP6 .. " vs " .. #fP6b .. ")")
    local _ = sawShadowed

    print("shadowed-guard counterexample tests passed")
end

-- Self-cache forms keep guard credit (stop-gate follow-up): bare and
-- _G-qualified caches are the same guard, not impostors.
do
    local rP7 = Registry.new()
    rP7:addSource("UnitClass")
    -- Live consumer classifier: without this restriction the exemption is
    -- never exercised and a broken credit path passes silently.
    rP7:addDocArgRestrictedFunction("issecretvalue", "AllowedWhenUntainted")
    for _, cache in ipairs({
        "local issecretvalue = issecretvalue",
        "local issecretvalue = _G.issecretvalue",
    }) do
        local srcP7 = cache .. [[

local name = UnitClass("target")
if issecretvalue(name) then name = nil end
return name
]]
        local fP7 = Analyzer.analyze(srcP7, "modules/foo.lua", rP7, cfg)
        for _, fi in ipairs(fP7) do
            assert(not tostring(fi.sink):find("consumer:issecretvalue", 1, true),
                "self-cached probe must keep exemption (" .. cache .. "), got: "
                .. tostring(fi.message))
            assert(not tostring(fi.message):find("truth%-tested"),
                "self-cached probe must keep guard credit (" .. cache .. "), got: "
                .. tostring(fi.message))
        end
    end
    print("self-cache guard credit tests passed")
end

-- Guard-alias credit (regression): `local IsSecretValue = Helpers.IsSecretValue`
-- rebinds a bare builtin guard name — the direct-hit shadow rule must fall
-- through to the alias map, which credits the registered target, not fail.
do
    local rP8 = Registry.new()
    rP8:addSource("UnitClass")
    rP8:addDocArgRestrictedFunction("issecretvalue", "AllowedWhenUntainted")
    local srcP8 = [[
local IsSecretValue = Helpers.IsSecretValue
local name = UnitClass("target")
if IsSecretValue(name) then name = nil end
return name
]]
    local fP8 = Analyzer.analyze(srcP8, "modules/foo.lua", rP8, cfg)
    for _, fi in ipairs(fP8) do
        assert(not tostring(fi.sink):find("consumer:", 1, true),
            "guard-alias must keep consumer exemption, got: " .. tostring(fi.message))
        assert(not tostring(fi.message):find("truth%-tested"),
            "guard-alias must keep probe credit, got: " .. tostring(fi.message))
    end
    -- Impostor refusal is covered by the shadowed-guard counterexamples
    -- above (method form) and the no-guard-registry comparison: a local
    -- impostor's CALL is the documented non-interprocedural boundary, so
    -- zero findings here is correct — the load-bearing property is only
    -- that no GUARD CREDIT was granted, which the counterexamples pin.
    print("guard-alias credit tests passed")
end

-- Custom (.taintrc extra_guards) wrapper guards are function-literal-bound by
-- construction — exempt from the builtin-only shadow rule.
do
    local rP9 = Registry.new()
    rP9:addSource("UnitClass")
    rP9:addGuard("MyWrapGuard")
    local srcP9 = [[
local MyWrapGuard = function(v) return issecretvalue and issecretvalue(v) end
local name = UnitClass("target")
if MyWrapGuard(name) then name = nil end
return name
]]
    local fP9 = Analyzer.analyze(srcP9, "modules/foo.lua", rP9, cfg)
    for _, fi in ipairs(fP9) do
        assert(not tostring(fi.message):find("truth%-tested"),
            "registered custom wrapper guard must keep credit, got: " .. tostring(fi.message))
    end

    -- ns-chain namespace alias: `local nsHelpers = ns.Helpers` then a bare
    -- cache of the dotted builtin guard through it must resolve and credit.
    local srcP9b = [[
local nsHelpers = ns.Helpers
local IsSecretValue = nsHelpers.IsSecretValue
local name = UnitClass("target")
if IsSecretValue(name) then name = nil end
return name
]]
    local fP9b = Analyzer.analyze(srcP9b, "modules/foo.lua", rP9, cfg)
    for _, fi in ipairs(fP9b) do
        assert(not tostring(fi.message):find("truth%-tested"),
            "ns-chained Helpers cache must keep credit, got: " .. tostring(fi.message))
    end
    print("custom-guard and ns-chain credit tests passed")
end

-- isGateName direct-hit shadow counterexamples (PTR7 follow-up): gate credit
-- is protection-granting, so a direct dotted registry hit must be an exact
-- unshadowed identity — mirror of the shadowed-guard block above. binds only
-- keys simple names, so the load-bearing arm for the dotted builtin gate is
-- the namespace-prefix consult.
do
    local rG1 = Registry.new()
    rG1:addPreconditionAPI("C_UnitAuras.GetUnitAuras", { "RequiresUnitAuraAccess" })

    -- impostor namespace: a local C_Secrets rebind must NOT grant gate
    -- protection through the registered dotted spelling
    local srcG1 = [[
local C_Secrets = { ShouldAurasBeSecret = function() return false end }
local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
    assert_eq(#preFindings(Analyzer.analyze(srcG1, "modules/foo.lua", rG1, cfg)), 1,
        "impostor local C_Secrets namespace must not grant direct gate credit")

    -- parameter shadow: same discipline as guard parameters
    local srcG2 = [[
local function scan(unit, C_Secrets)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
    assert_eq(#preFindings(Analyzer.analyze(srcG2, "modules/foo.lua", rG1, cfg)), 1,
        "parameter-shadowed C_Secrets must not grant direct gate credit")

    -- self-canonical namespace caches keep credit: bare, _G-qualified, and
    -- the pre-12.1 compat polyfill shape (all resolve canonically in harvest)
    for _, cacheLine in ipairs({
        "local C_Secrets = C_Secrets",
        "local C_Secrets = _G.C_Secrets",
        "C_Secrets = C_Secrets or {}",
    }) do
        local srcG3 = cacheLine .. [[

local function scan(unit)
    if C_Secrets.ShouldAurasBeSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
        assert_eq(#preFindings(Analyzer.analyze(srcG3, "modules/foo.lua", rG1, cfg)), 0,
            "self-canonical C_Secrets cache must keep gate credit: " .. cacheLine)
    end

    -- registered alias credit survives the direct-hit rule (fall-through
    -- parity: an early false on shadowed names revoked exactly this idiom
    -- repo-wide on the guard side)
    local srcG4 = [[
local isSecret = C_Secrets.ShouldAurasBeSecret
local function scan(unit)
    if isSecret() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
    assert_eq(#preFindings(Analyzer.analyze(srcG4, "modules/foo.lua", rG1, cfg)), 0,
        "registered gate alias keeps credit under the direct-hit shadow rule")

    -- custom (.taintrc extra_restriction_gates) wrapper gates are
    -- function-literal-bound by construction — exempt from the shadow rule
    local rG2 = Registry.new()
    rG2:addPreconditionAPI("C_UnitAuras.GetUnitAuras", { "RequiresUnitAuraAccess" })
    rG2:addRestrictionGate("MyGateWrap")
    local srcG5 = [[
local MyGateWrap = function() return C_Secrets.ShouldAurasBeSecret() end
local function scan(unit)
    if MyGateWrap() then return nil end
    return C_UnitAuras.GetUnitAuras(unit, "HELPFUL")
end
return scan
]]
    assert_eq(#preFindings(Analyzer.analyze(srcG5, "modules/foo.lua", rG2, cfg)), 0,
        "custom wrapper gate stays exempt from the builtin-only shadow rule")

    print("gate direct-hit shadow counterexample tests passed")
end
