--[[
  tests/helpers/secret_instrument.lua

  AST-guided source splicer: makes offline sentinel tests reproduce the
  in-game WoW 12.1 secret-value throw semantics that stock Lua 5.1 CANNOT
  trap (truthiness on tables; cross-type ==/~=; # on tables). See
  tests/helpers/secret_sentinel.lua CAVEATs 1-2 — those caveats describe the
  RAW (un-instrumented) sentinel; loading a module through this splicer
  closes exactly those gaps. Token-offset edits only — line numbers are
  preserved exactly.

  Rewrite targets (each preserves value semantics — wrappers return their
  argument unchanged):
    1. if/elseif/while/repeat-until conditions   -> __QUI_SECRET_TT( cond )
    2. `and`/`or` LHS operands only              -> __QUI_SECRET_TT( lhs )
       (the tail is truth-tested only when the whole chain is a condition,
       which target 1 already wraps; `c and secret` in value position stays
       legal — WoW itself allows selecting an opaque value)
    3. `not` operands                            -> not __QUI_SECRET_TT( x )
    4. `#` operands                              -> #__QUI_SECRET_LEN( x )
    5. `a == b` / `a ~= b`  -> __QUI_SECRET_EQ( a , b ) / __QUI_SECRET_NEQ(...)
       (operator token replaced with `,`; call wrapped around the binop)

  The __QUI_SECRET_* helper globals are installed by
  secret_sentinel.lua's InstallSecretStub and late-bind _G.issecretvalue at
  CALL time, so they compose with either that fixture or
  tools/_addon_env.lua's own issecretvalue.

  ── PARSER PROBE FINDINGS (2026-07-18, scratchpad probe vs the vendored
     LuaMinify behind tests/taint/parser/init.lua) ─────────────────────────
  * Every rewrite-target node class carries .Tokens: IfStatement (the
    if/then/elseif/else/end keywords), WhileStatement (while/do/end),
    RepeatStatement (repeat/until), BinopExpr (EXACTLY one token: the
    operator itself), UnopExpr (exactly the unop token), Parentheses
    ('(' and ')'). If-clause tables (stmt.Clauses[i]) have NO .Tokens of
    their own — the Condition subtree span supplies positions, and the
    following `then` keyword lives in IfStatement.Tokens so it is present
    in the flat token stream.
  * Token .Line/.Char are 1-based and BYTE-counted (the lexer's get()
    advances char per byte; '\n' resets char to 1, '\r' does not — CRLF
    sources still index correctly against a '\n'-scanned line-offset
    table). offsetOf = lineOffsets[Line] + Char - 1 slice-matched every
    token's Data in the probe.
  * String-token Data in THIS vendored lexer happens to be the raw source
    slice (quotes/escapes included), but end offsets are still NEVER
    computed from Data length — a comment can trail any node, so the
    close-paren position is always the NEXT flat-stream token's start
    (inserting `)` there is always syntactically safe: a line comment
    between ends at its newline, so the paren lands after it). The only
    Data-length use is the ==/~= operator replacement (Symbol tokens are
    verbatim source, length 2, replaced by the 1-char `,`).
  * Statlist/CallStatement have empty .Tokens; an explicit Eof node is the
    final Statlist body entry, so a following flat-stream token always
    exists for closeOffsetAfter (Eof sits one past the last source char,
    on its own line when the file ends with a newline).
  * M.parse strips a leading '#' line's CONTENTS keeping the newline;
    rewrite() applies the identical normalization before computing offsets
    and returns the normalized-then-spliced source.
  * Generic AST descent MUST skip Scope and Variable keys — the parser
    scope graph reaches the whole program and a naive walk hangs (same
    SKIP_KEYS rule as tests/taint/analyzer.lua). Token lists are consumed
    directly, never descended (they carry Print closures + LeadingWhite).

  ── Edit application order (pinned by the self-test) ─────────────────────
  Edits are {pos, text} inserts or {pos, len, text} replaces against the
  ORIGINAL byte offsets, applied conceptually sorted by pos DESCENDING (the
  implementation is the equivalent single ascending sweep). Equal-position
  tie rule, in OUTPUT order at one position:
    [close-parens] [open-texts outer-node-first] [replaced text]
  — a close at p belongs to a node that ENDED before p, so it precedes any
  open at p (disjoint by construction: two nodes sharing a start position
  are always ancestor/descendant, and pre-order emission puts the outer
  node's open first = leftmost = outermost). The replaced `,` keeps its own
  byte range, after all inserts at that position. Pinned by the nested
  `if (secret and 1) == 2` case and the `#t == 2` close+replace collision.

  Usage (from a test, cwd = repo root):
    local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
    local restore = SecretSentinel.InstallSecretStub() -- BEFORE the load
    local ns = {}
    assert(SecretSentinel.LoadInstrumented("core/aura_events.lua"))("QUI", ns)

  Self-test: lua5.1 tests/helpers/secret_instrument.lua --test
]]

-- The vendored parser's ParseLua does require'strict', which installs a
-- strict-mode metatable on _G (undeclared-global READS throw). That is
-- poison inside unit-test processes: addon modules under test read stubbed
-- globals that resolve to nil by design. Worse, strict.lua MUTATES an
-- already-present _G metatable in place (some tests install a permissive
-- __index that fabricates API stubs — that same __index also makes the
-- parser init's `_G.__qui_parser_path_added` guard read truthy and skip its
-- package.path setup). So: DETACH _G's metatable entirely around the parser
-- load — the parser sees a bare _G, strict builds a fresh throwaway
-- metatable, and the original (untouched) one is put back after.
local Parser
do
    local prevMeta = getmetatable(_G)
    if prevMeta ~= nil then setmetatable(_G, nil) end
    local ok, result = pcall(dofile, "tests/taint/parser/init.lua")
    -- Restore the original metatable FIRST, even on failure — otherwise a
    -- throwing parser load leaves _G strict-moded for the whole process.
    setmetatable(_G, prevMeta) -- nil prevMeta also discards strict's fresh mt
    if not ok then error(result, 0) end
    Parser = result
end

local M = {}

-- Keys that leave the AST tree: Scope/Variable link INTO the parser's scope
-- graph (parent chains reach the whole program — a naive walk hangs).
-- Tokens lists are consumed directly by the collectors, never descended.
local SKIP_KEYS = { Scope = true, Variable = true, Tokens = true }

local function posLess(a, b)
    if a.Line ~= b.Line then return a.Line < b.Line end
    return a.Char < b.Char
end

-- Flat token stream: every token from every node's .Tokens, identity-deduped,
-- sorted by (Line, Char); plus an identity index map for next-token lookup.
local function collectTokens(ast)
    local flat, seen = {}, {}
    local visited = {}
    local function walk(n)
        if type(n) ~= "table" or visited[n] then return end
        visited[n] = true
        local toks = n.Tokens
        if toks then
            for i = 1, #toks do
                local t = toks[i]
                if not seen[t] then
                    seen[t] = true
                    flat[#flat + 1] = t
                end
            end
        end
        for k, v in pairs(n) do
            if not SKIP_KEYS[k] and type(v) == "table" then
                walk(v)
            end
        end
    end
    walk(ast)
    table.sort(flat, posLess)
    local indexOf = {}
    for i = 1, #flat do indexOf[flat[i]] = i end
    return flat, indexOf
end

-- Subtree span: min/max-position tokens across a node's own .Tokens and all
-- child nodes (memoized — big modules walk each condition subtree once).
local function makeSpanner()
    local cache = {}
    local function span(node)
        local hit = cache[node]
        if hit then return hit[1], hit[2] end
        local lo, hi
        local function consider(t)
            if not lo or posLess(t, lo) then lo = t end
            if not hi or posLess(hi, t) then hi = t end
        end
        local visited = {}
        local function walk(n)
            if type(n) ~= "table" or visited[n] then return end
            visited[n] = true
            local toks = n.Tokens
            if toks then
                for i = 1, #toks do consider(toks[i]) end
            end
            for k, v in pairs(n) do
                if not SKIP_KEYS[k] and type(v) == "table" then walk(v) end
            end
        end
        walk(node)
        cache[node] = { lo, hi }
        return lo, hi
    end
    return span
end

--- Rewrite Lua source so secret-unsafe operations route through the
--- __QUI_SECRET_* helper globals. Returns the instrumented source, or
--- nil, err on parse failure. Line numbers are preserved exactly.
function M.rewrite(source, chunkName)
    if type(source) ~= "string" then
        return nil, "source must be a string, got " .. type(source)
    end
    -- Shebang-normalize EXACTLY like Parser.parse (contents stripped,
    -- newline kept) so token offsets match what we splice.
    if source:sub(1, 1) == "#" then
        source = source:gsub("^[^\n]*", "", 1)
    end

    local ast, perr = Parser.parse(source, chunkName)
    if not ast then return nil, perr end

    -- Line -> byte offset (1-based) of that line's first character.
    local lineOffsets = { 1 }
    do
        local pos = 1
        while true do
            local nl = source:find("\n", pos, true)
            if not nl then break end
            lineOffsets[#lineOffsets + 1] = nl + 1
            pos = nl + 1
        end
    end
    local function offsetOf(tok)
        local base = lineOffsets[tok.Line]
        if not base then
            -- Fail loudly here rather than opaquely inside table.sort via a
            -- nil edit position — this indicates a parser/offset invariant
            -- breach, not a caller error.
            error((chunkName or "?") .. ": token position " .. tostring(tok.Line)
                .. ":" .. tostring(tok.Char) .. " (" .. tostring(tok.Data)
                .. ") outside the " .. #lineOffsets .. "-line offset table", 0)
        end
        return base + tok.Char - 1
    end

    local flat, indexOf = collectTokens(ast)
    local span = makeSpanner()

    -- Edits: {pos, class, text [, len]} — class "close"|"open"|"replace".
    -- Output order at one position is close(1) open(2) replace(3); opens at
    -- the same position keep pre-order emission order (outer node first =
    -- leftmost = outermost). See header for why this is the correct tie rule.
    local CLASS_RANK = { close = 1, open = 2, replace = 3 }
    local edits, seq = {}, 0
    local failure = nil
    local function addEdit(pos, class, text, len)
        seq = seq + 1
        edits[#edits + 1] = { pos = pos, class = class, text = text, len = len or 0, seq = seq }
    end

    -- closeOffsetAfter: offset of the flat-stream token FOLLOWING the node's
    -- maximum-position token (always exists — Eof is the final token).
    local function wrap(node, helper)
        local lo, hi = span(node)
        if not (lo and hi) then
            failure = failure or ((chunkName or "?") ..
                ": no tokens in rewrite-target subtree (AstType=" ..
                tostring(node.AstType) .. ")")
            return
        end
        local nextTok = flat[indexOf[hi] + 1]
        if not nextTok then
            failure = failure or ((chunkName or "?") ..
                ": no token after rewrite-target subtree")
            return
        end
        addEdit(offsetOf(lo), "open", helper .. "(")
        addEdit(offsetOf(nextTok), "close", ")")
    end

    local function rewriteEq(node)
        local helper = (node.Op == "==") and "__QUI_SECRET_EQ" or "__QUI_SECRET_NEQ"
        local opTok = node.Tokens and node.Tokens[1]
        if not (opTok and opTok.Data == node.Op) then
            failure = failure or ((chunkName or "?") ..
                ": BinopExpr.Tokens[1] is not the operator token")
            return
        end
        wrap(node, helper) -- open before Lhs (= node min token), close after Rhs
        addEdit(offsetOf(opTok), "replace", ",", #opTok.Data)
    end

    -- Pre-order walk emitting edits per the five target classes; descends
    -- into EVERYTHING including closure bodies (runtime semantics apply
    -- there too). Outer-before-inner emission is what the equal-position
    -- open tie rule relies on.
    local visited = {}
    local function walk(n)
        if type(n) ~= "table" or visited[n] then return end
        visited[n] = true
        local ty = n.AstType
        if ty == "IfStatement" then
            for i = 1, #n.Clauses do
                local cond = n.Clauses[i].Condition
                if cond then wrap(cond, "__QUI_SECRET_TT") end
            end
        elseif ty == "WhileStatement" or ty == "RepeatStatement" then
            if n.Condition then wrap(n.Condition, "__QUI_SECRET_TT") end
        elseif ty == "BinopExpr" then
            if n.Op == "and" or n.Op == "or" then
                -- Lhs only: the truth-tested operand. The tail is tested
                -- only when the whole chain is a condition (target 1).
                wrap(n.Lhs, "__QUI_SECRET_TT")
            elseif n.Op == "==" or n.Op == "~=" then
                rewriteEq(n)
            end
        elseif ty == "UnopExpr" then
            if n.Op == "not" then
                wrap(n.Rhs, "__QUI_SECRET_TT")
            elseif n.Op == "#" then
                wrap(n.Rhs, "__QUI_SECRET_LEN")
            end
        end
        for k, v in pairs(n) do
            if not SKIP_KEYS[k] and type(v) == "table" then walk(v) end
        end
    end
    walk(ast)
    if failure then return nil, failure end

    -- Apply. Conceptually sorted by pos DESCENDING; implemented as the
    -- equivalent single ascending sweep in OUTPUT order:
    --   pos ASC, then close < open < replace, then emission seq ASC.
    table.sort(edits, function(a, b)
        if a.pos ~= b.pos then return a.pos < b.pos end
        local ra, rb = CLASS_RANK[a.class], CLASS_RANK[b.class]
        if ra ~= rb then return ra < rb end
        return a.seq < b.seq
    end)
    local out, cur = {}, 1
    for i = 1, #edits do
        local e = edits[i]
        if e.pos < cur then
            return nil, (chunkName or "?") .. ": overlapping edits at byte " .. e.pos
        end
        out[#out + 1] = source:sub(cur, e.pos - 1)
        out[#out + 1] = e.text
        cur = e.pos + e.len
    end
    out[#out + 1] = source:sub(cur)
    local result = table.concat(out)

    -- Line preservation is the contract: all edits are same-line inserts at
    -- token starts / shorter same-line op replacement. Verify, don't trust.
    local _, inNL = source:gsub("\n", "")
    local _, outNL = result:gsub("\n", "")
    if inNL ~= outNL then
        return nil, (chunkName or "?") .. ": instrumentation changed line count ("
            .. inNL .. " -> " .. outNL .. ")"
    end
    return result
end

--- loadstring() the instrumented form of `source`.
function M.loadString(source, chunkName)
    local rewritten, err = M.rewrite(source, chunkName)
    if not rewritten then return nil, err end
    return (loadstring or load)(rewritten, chunkName)
end

--- Drop-in for loadfile(path): returns chunk, err.
function M.loadFile(path)
    local f, ferr = io.open(path, "rb")
    if not f then return nil, ferr end
    local src = f:read("*a")
    f:close()
    return M.loadString(src, "@" .. path)
end

----------------------------------------------------------------------------
-- Self-test. Pins the five rewrite targets, value-semantics transparency,
-- the equal-position tie rules, and exact line preservation.
----------------------------------------------------------------------------
local function SelfTest()
    local SecretSentinel = dofile("tests/helpers/secret_sentinel.lua")
    local restore = SecretSentinel.InstallSecretStub()
    local secret = SecretSentinel.MakeSecretSentinel()

    local fails = 0
    local function check(name, ok, detail)
        if ok then
            print("  ok  " .. name)
        else
            fails = fails + 1
            print("FAIL  " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
        end
    end

    -- Run instrumented inline source; sentinel (or other values) arrive as
    -- chunk varargs so cases start with `local secret = ...`.
    -- A rewrite/load failure ABORTS the whole self-test: no case expects
    -- one, and returning it as (false, msg) would let a rewriter regression
    -- that produces a syntax error masquerade as an expected secret throw
    -- in the throw-asserting cases.
    local function run(src, ...)
        local chunk, err = M.loadString(src, "=case")
        if not chunk then
            error("self-test case failed to LOAD (rewriter regression?): "
                .. tostring(err) .. "\nsource:\n" .. src, 0)
        end
        return pcall(chunk, ...)
    end
    local function countLines(s)
        local n = 1
        for _ in s:gmatch("\n") do n = n + 1 end
        return n
    end

    -- 1. bare if-condition truthiness throws
    local ok, err = run("local secret = ...\nif secret then end", secret)
    check("T1 if secret -> throws", not ok and tostring(err):find("boolean test"), err)
    -- ...and the throw reports the ORIGINAL line (level-3 error in secretcheck)
    check("T1b throw carries original line 2", not ok and tostring(err):find(":2:"), err)

    -- 2. tail of `and` IS truth-tested when the chain is a condition
    ok, err = run("local secret = ...\nlocal x = 1\nif x and secret then end", secret)
    check("T2 if x and secret (x truthy) -> throws", not ok and tostring(err):find("boolean test"), err)

    -- 3. and-Lhs wrap throws in value position
    ok, err = run("local secret = ...\nlocal v = secret and 1\nreturn v", secret)
    check("T3 v = secret and 1 -> throws", not ok and tostring(err):find("boolean test"), err)

    -- 4. legal value-select of an opaque secret must NOT throw (tail untested)
    local ok4, r4 = run("local secret = ...\nlocal c = true\nlocal v = c and secret\nreturn v", secret)
    check("T4 v = c and secret (c truthy) -> no throw", ok4, r4)
    check("T4b value passes through IDENTICALLY", ok4 and r4 == secret)

    -- 5. or-Lhs wrap: (c and secret) or d throws when c truthy (round-7b class)
    ok, err = run("local secret = ...\nlocal c = true\nlocal d = 2\nlocal v = (c and secret) or d\nreturn v", secret)
    check("T5 (c and secret) or d -> throws", not ok and tostring(err):find("boolean test"), err)

    -- 6. not operand throws
    ok, err = run("local secret = ...\nreturn not secret", secret)
    check("T6 not secret -> throws", not ok and tostring(err):find("boolean test"), err)

    -- 7. cross-type ==/~= throw (impossible for the raw sentinel, CAVEAT 1)
    ok, err = run("local secret = ...\nreturn secret == 5", secret)
    check("T7a secret == 5 -> throws", not ok and tostring(err):find("compare"), err)
    ok, err = run('local secret = ...\nreturn secret ~= "x"', secret)
    check("T7b secret ~= \"x\" -> throws", not ok and tostring(err):find("compare"), err)

    -- 8. clean compares return the right booleans through the helpers
    local ok8, a8, b8, c8 = run('return 1 == 1, 1 == 2, "a" ~= "b"')
    check("T8 clean ==/~= keep semantics", ok8 and a8 == true and b8 == false and c8 == true,
        tostring(a8) .. "," .. tostring(b8) .. "," .. tostring(c8))
    local ok8b, d8, e8 = run("local a, b = {}, {}\nreturn a == b, a == a")
    check("T8b plain-table identity compare intact", ok8b and d8 == false and e8 == true)

    -- 9. # operand throws
    ok, err = run("local secret = ...\nreturn #secret", secret)
    check("T9 #secret -> throws", not ok and tostring(err):find("length"), err)

    -- 10. probe-first discipline passes: the wrapper's own issecretvalue call
    --     is not a truth-test OF the secret.
    local ok10, r10 = run('local secret = ...\nif issecretvalue(secret) then return "probed" end\nreturn "missed"', secret)
    check("T10 if issecretvalue(secret) -> no throw, probed branch", ok10 and r10 == "probed", r10)

    -- 11. while / repeat-until conditions
    ok, err = run("local secret = ...\nwhile secret do end", secret)
    check("T11a while secret -> throws", not ok and tostring(err):find("boolean test"), err)
    ok, err = run("local secret = ...\nrepeat until secret", secret)
    check("T11b repeat until secret -> throws", not ok and tostring(err):find("boolean test"), err)

    -- 12. line preservation: error() in instrumented code reports the
    --     ORIGINAL line number even with rewrites on earlier lines.
    local src12 = 'local secret = ...\nlocal c = true\nlocal v = c and secret\nlocal w = 1 == 1\nerror("boom")'
    local rw12, rerr12 = M.rewrite(src12, "case12")
    check("T12a rewrite succeeds", rw12 ~= nil, rerr12)
    check("T12b line count preserved", rw12 and countLines(rw12) == countLines(src12))
    ok, err = run(src12, secret)
    check("T12c error() reports original line 5", not ok and tostring(err):find(":5:"), err)

    -- 13. comments/strings containing operators are untouched (token-based
    --     edits can't hit them — pinned anyway).
    local src13 = 'local s = "a == b -- and"\n-- x == y and z\nreturn s'
    local rw13 = M.rewrite(src13, "case13")
    check("T13a operator-free source unchanged", rw13 == src13, rw13)
    local ok13, r13 = run(src13)
    check("T13b string literal survives verbatim", ok13 and r13 == "a == b -- and", r13)

    -- 14. equal-position tie rule (nested same-start wraps): condition wrap
    --     and eq rewrite open at the same '(' — outer TT must end up
    --     outermost or EQ silently loses its second argument.
    local src14 = 'local c = 1\nif (c and 2) == 2 then return "eq-true" end\nreturn "fell"'
    local rw14 = M.rewrite(src14, "case14")
    check("T14a TT wraps EQ at shared open position", rw14 ~= nil and
        rw14:find("__QUI_SECRET_TT(__QUI_SECRET_EQ((", 1, true) ~= nil, rw14)
    local ok14, r14 = run(src14)
    check("T14b nested wrap keeps == semantics", ok14 and r14 == "eq-true", r14)

    -- 15. the brief's pin: throws on the and-Lhs FIRST (innermost TT), not
    --     on the compare.
    ok, err = run("local secret = ...\nif (secret and 1) == 2 then end", secret)
    check("T15 if (secret and 1) == 2 -> and-Lhs throws first",
        not ok and tostring(err):find("boolean test"), err)

    -- 16. close-paren + operator-replacement colliding at the same position
    --     (#t's LEN close lands exactly on the == token being replaced).
    local ok16, r16 = run("local t = {1,2}\nreturn #t == 2")
    check("T16a #t == 2 -> true through LEN+EQ", ok16 and r16 == true, r16)
    ok, err = run("local secret = ...\nreturn #secret == 2", secret)
    check("T16b #secret == 2 -> length throw", not ok and tostring(err):find("length"), err)

    -- 17. wrapper transparency for ALL types including nil/false
    local ok17a, r17a = run('local f = ...\nif f then return "t" end\nreturn "f"', false)
    local ok17b, r17b = run('local f = ...\nif f then return "t" end\nreturn "f"', nil)
    local ok17c, r17c = run('local f = ...\nif f then return "t" end\nreturn "f"', 0)
    check("T17 TT transparent for false/nil/0",
        ok17a and r17a == "f" and ok17b and r17b == "f" and ok17c and r17c == "t")
    local ok17d, r17d = run("return not false")
    check("T17b not false -> true", ok17d and r17d == true, r17d)
    local ok17e, r17e = run("local x = nil\nreturn x or 42")
    check("T17c nil or 42 -> 42", ok17e and r17e == 42, r17e)

    -- 18. shebang normalization: contents stripped, newline kept, offsets ok
    ok, err = run("#!/usr/bin/env lua\nlocal secret = ...\nreturn not secret", secret)
    check("T18 shebang source instruments and throws", not ok and tostring(err):find("boolean test"), err)

    -- 19. elseif condition is wrapped too
    ok, err = run("local secret = ...\nlocal c = false\nif c then return 1\nelseif secret then return 2\nend", secret)
    check("T19 elseif secret -> throws", not ok and tostring(err):find("boolean test"), err)

    -- 20. comment between condition end and `then`: close paren lands after
    --     the comment (next-token-start rule), still parses, still throws.
    ok, err = run("local secret = ...\nif secret -- trailing comment\nthen end", secret)
    check("T20 close after trailing comment", not ok and tostring(err):find("boolean test"), err)

    SecretSentinel.RestoreSecretStub(restore)
    assert(rawget(_G, "__QUI_SECRET_TT") == nil, "RestoreSecretStub must remove helpers")

    if fails > 0 then
        error("secret_instrument self-test: " .. fails .. " FAILED")
    end
    print("secret_instrument self-test: OK")
end

M.SelfTest = SelfTest

-- arg[0] scoping: dofile-ing this helper from ANOTHER script running with
-- --test must not auto-fire this self-test.
if arg and arg[1] == "--test"
    and tostring(arg[0] or ""):find("secret_instrument", 1, true) then
    SelfTest()
end

return M
